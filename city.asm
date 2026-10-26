;==============================================================================
; Z-POLICE - city page (8K page PAGE_CITY, runs at $E000)
;
; All Layer 2 drawing: back-to-front city traversal, building transform,
; culling and shading, 3D clipping, projection, polygon fill, lines, the
; viewport clear, ground dots and the gunsight.  Paged in by main_loop with
; nextreg $57,PAGE_CITY.  Shared variables and tables live in zpolice.asm.
;==============================================================================

        ALIGN 256
vtx:        ds 8*16                     ; X,Y,Z,oc,sx,sy + pad
p2buf:      ds 4*16                     ; x,y,edge flag,pad

        ALIGN 256
; Unrolled span writer: entry = push_end - pairs
push_blk:
        REPT 128
        push de
        ENDR
push_end:
        ld a,b
        inc b
        cp ixl
        jr z,.done
        ld a,b
        and 31
        jp nz,fs_loop
        ld a,(seg_page)                 ; next row starts a new section
        inc a                           ; (inline: SP is borrowed, no calls)
        ld (seg_page),a
        nextreg $50,a
        jp fs_loop
.done:  ld sp,(saved_sp)
        ret

        ALIGN 256
TA:         ds 256                      ; x of downward edges per row
TB:         ds 256                      ; x of upward edges per row

        INCLUDE "tables_city.inc"       ; reciprocal, log2, used corners, colours

; A = row y (0..VIEW_H-1): page in its section, return A = y & 31.
; Preserves BC, DE, L.
seg_map:
        push bc
        ld c,a
        rlca
        rlca
        rlca
        and 3                           ; section 0..3
        ld b,a
        ld a,(seg_base)
        add a,b
        ld (seg_page),a
        nextreg $50,a
        ld a,c
        and 31
        pop bc
        ret

; Line drawer stepped H off the section (H = 32 going down, $FF going up):
; page in the neighbouring section and wrap H.  Preserves A, BC, DE, L.
line_seg:
        push af
        ld a,h
        cp 32
        ld a,(seg_page)
        jr nz,.up
        inc a                           ; down into the next section
        ld h,0
        jr .set
.up:    dec a                           ; up into the previous section
        ld h,31
.set:   ld (seg_page),a
        nextreg $50,a
        pop af
        ret

; HL = (HL * DE) >> 16   HL signed, DE unsigned 0.16 fraction
mul_frac:
        ld a,h
        ld (mf_sign),a
        call abs_hl
        ld b,h                          ; ah
        ld c,l                          ; al
        push de
        ld d,c
        mul d,e                         ; al*tl
        ld l,d
        ld h,0
        pop de
        push de
        ld e,d
        ld d,c
        mul d,e                         ; al*th
        add hl,de
        ld a,0
        adc a,a
        pop de
        push de
        ld d,b
        mul d,e                         ; ah*tl
        add hl,de
        adc a,0                         ; A:HL = middle sum
        ld l,h
        ld h,a
        pop de
        ld e,d
        ld d,b
        mul d,e                         ; ah*th
        add hl,de
        ld a,(mf_sign)
        bit 7,a
        ret z
        jp neg_hl

; IX = (HL << 16) / DE   with HL < DE (unsigned) -> 0.16 fraction
div_frac:
        ld ix,0
        ld a,16
.lp:    add ix,ix
        add hl,hl
        jr c,.sub
        or a
        sbc hl,de
        jr nc,.set
        add hl,de
        jr .nx
.sub:   or a
        sbc hl,de
.set:   inc ix
.nx:    dec a
        jr nz,.lp
        ret

; E = A / C, A = A mod C  (8-bit unsigned)
div8:
        ld e,a
        xor a
        ld b,8
.lp:    sla e
        rla
        jr c,.s
        cp c
        jr c,.n
.s:     sub c
        inc e
.n:     djnz .lp
        ret

;==============================================================================
; Perspective projection
;   in : HL -> X,Y,Z (camera space, inside the view frustum, Z > 0)
;   out: A = screen x (0..255), C = screen y (0..VIEW_H-1)
;   sx = 128 + 128*X/Z,  sy = 64 - 128*Y/Z   (90 x 53 degree field of view)
;   Z is normalised to 9 bits (256..511) with a barrel shift (count from a
;   log2 table) that is also applied to X and Y, which are then multiplied
;   by a 16-bit reciprocal from rtab.  |X| <= Z keeps Xn within 9 bits.
;==============================================================================
project:
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl                          ; BC = X
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl                          ; DE = Y
        push de
        push bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = Z
        call zpatch

        pop hl                          ; X
        ld a,h
        push af
        call scale_comp
        ld c,a
        pop af
        rla
        jr c,.xn
        ld a,128
        add a,c
        jr nc,.xd
        ld a,255
        jr .xd
.xn:    ld a,128
        sub c
        jr nc,.xd
        xor a
.xd:    ld (pj_sx),a

        pop hl                          ; Y
        ; fall through

; HL = Y -> C = screen y, A = screen x of the last project.  Uses the Z
; patched into scale_comp by the last project, so on its own it projects a
; point straight above or below that one when pitch is 0 (same X and Z).
proj_y:
        ld a,h
        push af
        call scale_comp
        ld c,a
        pop af
        rla
        jr c,.yn
        ld a,VIEW_CY
        sub c
        jr nc,.yd
        xor a
        jr .yd
.yn:    ld a,VIEW_CY
        add a,c
        jr c,.yc
        cp VIEW_H
        jr c,.yd
.yc:    ld a,VIEW_H-1
.yd:    ld c,a
        ld a,(pj_sx)
        ret

; HL = Z (camera space): normalise it and patch its shift and reciprocal
; into scale_comp, which then gives A = |component| * 128 / Z
zpatch:
        bit 7,h
        jr nz,.z1
        or h
        jr nz,.zok
.z1:    ld hl,1
.zok:   ld a,h
        cp 2
        jr c,.lt512
        ld e,a                          ; Z >= 512: shift right by log2(H)
        ld d,high lgtab
        ld a,(de)
        ld b,a
        ex de,hl
        bsrl de,b
        ex de,hl
        jr .nrm
.lt512: ld b,0
        or a
        jr nz,.nrm                      ; 256..511 already normalised
        ld e,l                          ; Z < 256: shift left by 8-log2(L)
        ld d,high lgtab
        ld a,(de)
        sub 8
        ld c,a                          ; negative shift count
        neg
        ld b,a
        ex de,hl
        bsla de,b
        ex de,hl
        ld b,c
.nrm:   ld a,b                          ; patch shift and reciprocal into
        ld (scale_comp.sh+1),a                  ; scale_comp's immediates
        ld h,high rtab_lo               ; L = Zn - 256
        ld a,(hl)
        ld (scale_comp.rl+1),a
        ld (scale_comp.r16+1),a
        inc h
        ld a,(hl)
        ld (scale_comp.rh+1),a
        ld (scale_comp.r16+2),a
        ret

; HL = signed component -> A = round(|HL| * 128 / Z)
; The shift and reciprocal for this Z are patched in by project.
scale_comp:
        bit 7,h
        jr z,.ap
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.ap:
.sh:    ld a,0
        or a
        jr z,.sd
        ex de,hl
        jp m,.l
        ld b,a
        bsrl de,b
        ex de,hl
        jr .sd
.l:     neg
        ld b,a
        bsla de,b
        ex de,hl
.sd:    ld a,h
        cp 2
        jr nc,.big
.ok:    ld b,h                          ; bit 8 of Xn
        ld d,l
.rl:    ld e,0
        mul d,e                         ; Xl*Rl
        ld c,d
        ld d,l
.rh:    ld e,0
        mul d,e                         ; Xl*Rh
        ld a,c
        add a,e
        ld l,a
        ld a,d
        adc a,0
        ld h,a                          ; HL = (Xl*R) >> 8
        ld c,0
        dec b
        jr nz,.nh
.r16:   ld de,0
        add hl,de                       ; + (256*R) >> 8
        rl c
.nh:    inc h                           ; + rounding (0.5 after >>9)
        jr nz,.nr
        inc c
.nr:    ld a,c
        rra
        ld a,h
        rra                             ; A = (C:H) >> 1  = P >> 9
        ret
.big:   ld hl,511                       ; clamp (rounding at frustum edge)
        jr .ok

;==============================================================================
; Outcode: HL -> vertex (X,Y,Z) -> A = bits
;   1 near (Z<NEAR)  2 left (X<-Z)  4 right (X>Z)
;   8 top (Y>0.5Z)   16 bottom (Y<-0.5Z)
;==============================================================================
calc_oc:
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = X
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)                       ; BC = Y
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = Z
        bit 7,h
        jr nz,.nr
        ld a,h
        or a
        ld a,0
        jr nz,.n1
        ld a,l
        cp NEAR
        ld a,0
        jr nc,.n1
.nr:    ld a,1
.n1:    push hl
        add hl,de                       ; Z+X
        bit 7,h
        jr z,.n2
        or 2
.n2:    pop hl
        push hl
        or a
        sbc hl,de                       ; Z-X
        bit 7,h
        jr z,.n3
        or 4
.n3:    pop hl
        sra h
        rr l                            ; 0.5Z
        push hl
        or a
        sbc hl,bc                       ; 0.5Z-Y
        bit 7,h
        jr z,.n4
        or 8
.n4:    pop hl
        add hl,bc                       ; 0.5Z+Y
        bit 7,h
        ret z
        or 16
        ret

; Signed distance of vertex IX to clip plane (clip_plane bit). >= 0 is inside.
plane_dist:
        ld l,(ix+4)
        ld h,(ix+5)
        ld a,(clip_plane)
        cp 1
        jr nz,.p2
        ld de,-NEAR
        add hl,de
        ret
.p2:    ld e,(ix+0)
        ld d,(ix+1)
        cp 2
        jr nz,.p3
        add hl,de
        ret
.p3:    cp 4
        jr nz,.p4
        or a
        sbc hl,de
        ret
.p4:    push af
        call zhalf
        pop af
        ld e,(ix+2)
        ld d,(ix+3)
        cp 8
        jr nz,.p5
        or a
        sbc hl,de
        ret
.p5:    add hl,de
        ret

;==============================================================================
; Sutherland-Hodgman clip of clip_src (clip_n verts) against clip_plane into
; clip_dst.  Vertex = X,Y,Z,flag,corner (8 bytes).  flag=1 means the edge from
; this vertex to the next is a real building edge (gets outlined); edges
; created along a clip plane get flag=0 so the screen border isn't outlined.
; corner = vtx offset of an unclipped building corner that is on screen, so
; its cached projection can be reused; $80 + plane bit for a vertex the
; clipper put on that plane; $FF for any other vertex.
;==============================================================================
clip_poly:
        ld a,(clip_n)
        dec a
        add a,a
        add a,a
        add a,a
        ld hl,(clip_src)
        add hl,a
        ld (clip_s),hl
        push hl
        pop ix
        call plane_dist
        ld (clip_ds),hl
        ld hl,(clip_src)
        ld (clip_e),hl
        ld iy,(clip_dst)
        xor a
        ld (clip_on),a
        ld a,(clip_n)
        ld (clip_cnt),a
.loop:  ld ix,(clip_e)
        call plane_dist
        ld (clip_de),hl
        bit 7,h
        jr nz,.eout
        ld a,(clip_ds+1)
        bit 7,a
        jr z,.ein
        ; S out, E in: intersection carries S's edge flag
        ld ix,(clip_s)
        ld a,(ix+6)
        ld (clip_if),a
        call clip_isect
.ein:   ld ix,(clip_e)
        ld b,8                          ; whole vertex, with its corner byte
.cpy:   ld a,(ix+0)
        ld (iy+0),a
        inc ix
        inc iy
        djnz .cpy
        ld hl,clip_on
        inc (hl)
        jr .next
.eout:  ld a,(clip_ds+1)
        bit 7,a
        jr nz,.next
        ; S in, E out: intersection starts a clip-plane edge
        xor a
        ld (clip_if),a
        call clip_isect
.next:  ld hl,(clip_e)
        ld (clip_s),hl
        ld de,8
        add hl,de
        ld (clip_e),hl
        ld hl,(clip_de)
        ld (clip_ds),hl
        ld hl,clip_cnt
        dec (hl)
        jr nz,.loop
        ld a,(clip_on)
        ld (clip_n),a
        ret

; Output S + t*(E-S) at IY, t = dS/(dS-dE)
clip_isect:
    IFDEF LEVEL_FAST_PATH
        ; Level flight: a vertical building edge (S and E share X and Z)
        ; meets the top or bottom plane at (X, +-0.5Z, Z) - no divide or
        ; interpolation.  At pitch 0 vertical edges can't cross the near or
        ; side planes, so this covers every plane they do cross.
        ld a,(pitch)
        or a
        jr nz,.gen
        ld a,(clip_plane)
        cp 8
        jr c,.gen                       ; not top or bottom
        ld hl,(clip_s)
        ld de,(clip_e)
        ld a,(de)
        cp (hl)
        jr nz,.gen
        inc hl
        inc de
        ld a,(de)
        cp (hl)
        jr nz,.gen                      ; X differs
        inc hl
        inc hl
        inc hl
        inc de
        inc de
        inc de
        ld a,(de)
        cp (hl)
        jr nz,.gen
        inc hl
        inc de
        ld a,(de)
        cp (hl)
        jr nz,.gen                      ; Z differs
        ld ix,(clip_s)
        ld a,(ix+0)                     ; X and Z from S (= E)
        ld (iy+0),a
        ld a,(ix+1)
        ld (iy+1),a
        ld l,(ix+4)
        ld h,(ix+5)
        ld (iy+4),l
        ld (iy+5),h
        ld a,(clip_plane)
        jr .ty                          ; Y = +-0.5Z
.gen:
    ENDIF
        ld hl,(clip_ds)
        call abs_hl
        ld (ci_a),hl
        ld hl,(clip_de)
        call abs_hl
        ld de,(ci_a)
        add hl,de
        ex de,hl                        ; DE = |dS|+|dE|, HL = |dS|
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.dv
        ld ix,$FFFF
        jr .t
.dv:    call div_frac
.t:     ld (ci_t),ix
        xor a
        call lerp_c
        ld (iy+0),l
        ld (iy+1),h
        ld a,2
        call lerp_c
        ld (iy+2),l
        ld (iy+3),h
        ld a,4
        call lerp_c
        ld (iy+4),l
        ld (iy+5),h
        ; snap the point exactly onto the plane so rounding can't leave a
        ; gap between the polygon and the screen edge
        ld l,(iy+4)
        ld h,(iy+5)                     ; Z
        ld a,(clip_plane)
        cp 1
        jr nz,.s2
        ld (iy+4),NEAR                  ; near:   Z = NEAR
        ld (iy+5),0
        jr .nz
.s2:    cp 2
        jr nz,.s4
        call neg_hl                     ; left:   X = -Z
        jr .sx
.s4:    cp 4
        jr z,.sx                        ; right:  X = Z
.ty:    push af
        call zhalf
        pop af
        cp 8
        jr z,.sy                        ; top:    Y = 0.5Z
        call neg_hl                     ; bottom: Y = -0.5Z
.sy:    ld (iy+2),l
        ld (iy+3),h
        jr .nz
.sx:    ld (iy+0),l
        ld (iy+1),h
.nz:    ld a,(clip_if)
        ld (iy+6),a
        ld a,(clip_plane)               ; new vertex: no cached projection,
        or $80                          ; but remember the plane it is on
        ld (iy+7),a
        ld bc,8
        add iy,bc
        ld hl,clip_on
        inc (hl)
        ret

; A = coordinate offset -> HL = S.c + (E.c - S.c) * t
lerp_c:
        ld hl,(clip_e)
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(clip_s)
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        ex de,hl
        or a
        sbc hl,de
        ld de,(ci_t)
        call mul_frac
        pop de
        add hl,de
        ret

;==============================================================================
; Draw one face of the current building
;   HL -> 4 vertex offsets into vtx[] (index*16), df_mask = edges to outline
;   (bit k = edge from corner k to corner k+1)
;==============================================================================
draw_face:
        ld (df_ptr),hl
        ld bc,$FF00                     ; B = AND of outcodes, C = OR
        ld a,(vtx_hi)
        ld d,a
        REPT 4
        ld a,(hl)
        inc hl
        add a,6
        ld e,a
        ld a,(de)
        ld e,a
        and b
        ld b,a
        ld a,e
        or c
        ld c,a
        ENDR
        ld a,b
        or a
        ret nz                          ; wholly outside one plane
        ld a,c
        or a
        jr nz,.clip

        ; fast path - every corner on screen, use cached projections
        ld hl,(df_ptr)
        ld de,p2buf
        ld a,(vtx_hi)
        ld b,a
        FACEVTX 1
        FACEVTX 2
        FACEVTX 4
        FACEVTX 8
        ld a,4
        ld (p2n),a
        jp .render

.clip:  ld (df_or),a
        ld a,(df_mask)
        ld (df_m),a
        ld hl,(df_ptr)
        ld iy,clipA
        ld b,4
.cp:    ld a,(hl)
        inc hl
        ld (df_cur),a
        ld ixl,a
        ld a,(vtx_hi)
        ld ixh,a
        ld c,6
.cpb:   ld a,(ix+0)
        ld (iy+0),a
        inc ix
        inc iy
        dec c
        jr nz,.cpb
        ld a,(df_m)
        ld e,a
        and 1
        ld (iy+0),a                     ; edge flag from mask
        ld a,e
        rrca
        ld (df_m),a
        ld a,(ix+0)                     ; the corner's outcode (IX at +6)
        or a
        ld a,$FF
        jr nz,.cn
        ld a,(df_cur)                   ; on screen: projection is cached
.cn:    ld (iy+1),a
        inc iy
        inc iy
        djnz .cp
        ld a,4
        ld (clip_n),a
        ld hl,clipA
        ld (clip_src),hl
        ld hl,clipB
        ld (clip_dst),hl
        ld a,1
.pl:    ld (clip_plane),a
        ld hl,df_or
        and (hl)
        jr z,.skip
        call clip_poly
        ld a,(clip_n)
        cp 3
        ret c
        ld hl,(clip_src)
        ld de,(clip_dst)
        ld (clip_src),de
        ld (clip_dst),hl
.skip:  ld a,(clip_plane)
        add a,a
        cp 32
        jr nz,.pl

        ld ix,(clip_src)
        ld iy,p2buf
        ld a,(clip_n)
        ld (p2n),a
        ld b,a
.pj:    push bc
        ld a,(ix+7)
        cp $80
        jr nc,.pf
        add a,7                         ; unclipped on-screen corner:
        ld l,a                          ; reuse its cached sx, sy
        ld a,(vtx_hi)
        ld h,a
        ld a,(hl)
        inc l
        ld c,(hl)
        jr .ps
.pf:    push ix
        pop hl
        call project
        ld e,a
        ld a,(ix+7)
        inc a
        jr z,.p0                        ; $FF: an ordinary vertex
        dec a
        ; On a clip plane: put it exactly on that screen edge (projection
        ; rounding could leave it a pixel inside, opening a 1-pixel gap).
        rra                             ; near: nothing
        rra
        jr nc,.e1
        ld e,0                          ; left
.e1:    rra
        jr nc,.e2
        ld e,255                        ; right
.e2:    rra
        jr nc,.e3
        ld c,0                          ; top
.e3:    rra
        jr nc,.p0
        ld c,VIEW_H-1                   ; bottom
.p0:    ld a,e
.ps:    ld (iy+0),a
        ld (iy+1),c
        ld a,(ix+6)
        ld (iy+2),a
        ld bc,8
        add ix,bc
        ld bc,4
        add iy,bc
        pop bc
        djnz .pj

.render:
        ; close the polygon: copy vertex 0 after the last
        ld a,(p2n)
        add a,a
        add a,a
        ld hl,p2buf
        add hl,a
        ld a,(p2buf)
        ld (hl),a
        inc hl
        ld a,(p2buf+1)
        ld (hl),a
    IFDEF DRAW_LINES
        call fill_poly
        ld a,EDGE_COL
        ld (line_col),a
        jp outline_poly
    ELSE
        jp fill_poly                    ; solid faces only
    ENDIF

;==============================================================================
; Convex polygon fill from p2buf (8-bit screen coords).
;   Each edge is walked with an exact integer DDA into one of two x tables:
;   downward edges -> TA, upward edges -> TB.  For a convex polygon every row
;   then has one entry in each, and the span between them is filled.
;   Winding doesn't matter.
;==============================================================================
fill_poly:
        ld a,(p2n)
        ld b,a
        ld hl,p2buf+1
        ld c,255
        ld d,0
.mm:    ld a,(hl)
        cp c
        jr nc,.m1
        ld c,a
.m1:    cp d
        jr c,.m2
        ld d,a
.m2:    inc hl
        inc hl
        inc hl
        inc hl
        djnz .mm
        ld a,c
        cp d
        ret z                           ; zero height - outline only
        ld (fy0),a
        ld a,d
        ld (fy1),a

        ld ix,p2buf
        ld a,(p2n)
        ld (fe_cnt),a
.ed:    ld d,(ix+0)
        ld e,(ix+1)
        ld b,(ix+4)
        ld c,(ix+5)
        ld a,e
        cp c
        jr z,.nx                        ; horizontal edge
        jr c,.down
        ld a,d                          ; going up: swap ends, use TB
        ld d,b
        ld b,a
        ld a,e
        ld e,c
        ld c,a
        ld a,high TB
        jr .walk
.down:  ld a,high TA
.walk:  push ix
        call walk_edge
        pop ix
.nx:    ld bc,4
        add ix,bc
        ld hl,fe_cnt
        dec (hl)
        jr nz,.ed

        ld a,(face_col)                 ; shaded colour of this face
        ld (l2_cls_byte),a              ; DMA source byte for long spans
        ld d,a
        ld e,a                          ; PUSH pair for short spans
        jp fill_spans

; Walk an edge (D=xa, E=ya) -> (B=xb, C=yb), yb > ya, into table page A.
; Bresenham style: x += q each row, fractional r/dy accumulated in a biased
; byte (carry == wrap), so the end point is hit exactly.
walk_edge:
        ld h,a
        ld l,e
        ld a,c
        sub e
        ld c,a                          ; C = dy (1..191)
        ld a,b
        sub d                           ; dx
        jr c,.neg
        cp c
        jr nc,.pdv
        ld ixl,a                        ; steep: q = 0, r = dx
        call .setup
        jr .p0
.pdv:   call div8                       ; E = q, A = r
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.p0
.pl:    ld (hl),d
        inc l
        ld a,d
        add a,ixh
        ld d,a
        ld a,e
        add a,ixl
        jr nc,.pl1
        add a,c
        inc d
.pl1:   ld e,a
        djnz .pl
        ret
.p0:    ld (hl),d
        inc l
        ld a,e
        add a,ixl
        jr nc,.p01
        add a,c
        inc d
.p01:   ld e,a
        djnz .p0
        ret

.neg:   neg
        cp c
        jr nc,.ndv
        ld ixl,a
        call .setup
        jr .n0
.ndv:   call div8
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.n0
.nl:    ld (hl),d
        inc l
        ld a,d
        sub ixh
        ld d,a
        ld a,e
        add a,ixl
        jr nc,.nl1
        add a,c
        dec d
.nl1:   ld e,a
        djnz .nl
        ret
.n0:    ld (hl),d
        inc l
        ld a,e
        add a,ixl
        jr nc,.n01
        add a,c
        dec d
.n01:   ld e,a
        djnz .n0
        ret

; B = dy+1 rows, E = biased accumulator (dy/2 - dy), C = -dy
.setup: ld b,c
        inc b
        ld a,c
        srl a
        sub c
        ld e,a
        ld a,c
        neg
        ld c,a
        ret

;==============================================================================
; Span filler.  Rows fy0..fy1, x from TA/TB.  DE = colour pair.
; Short spans use the stack pointer as a 2-byte write pointer into the frame
; buffer (interrupts are disabled), jumping into an unrolled block of PUSH DE.
; Spans of DMA_SPAN_MIN pixels or more are written by the zxnDMA, which only
; needs its length and destination reloaded (see clear_screen).
;==============================================================================
fill_spans:
        ld a,(fy0)
        call seg_map                    ; first row's section into slot 0
        ld (saved_sp),sp
        ld a,(fy0)
        ld b,a
        ld a,(fy1)
        ld ixl,a

fs_loop:
        ld h,high TA
        ld l,b
        ld a,(hl)
        inc h
        ld c,(hl)
        cp c
        jr c,.ord
        ld l,c
        ld c,a
        ld a,l
.ord:   ld l,a                          ; A = left x, C = right x
        ld a,b
        and 31
        ld h,a                          ; row within the paged section
        ld a,c
        sub l                           ; width-1
        cp DMA_SPAN_MIN-1
        jr nc,.dma
.push:  srl a
        jr c,.even
        ld (hl),e                       ; odd width: single pixel first
        jr .go
.even:  inc a
.go:    ld l,c
        inc hl                          ; one past right edge (may be $C000)
        ld sp,hl
        ld l,a
        ld a,low push_end
        sub l
        ld l,a
        ld h,high push_end
        jp (hl)

        ; Long span: zxnDMA from the fixed colour byte (port A) to HL.
        ; Everything but length and destination was set up by clear_screen.
.dma:   inc a
        jr nz,.dmal
        dec a                           ; 256 wide: length needs the high
        jr .push                        ; byte, so PUSH it (A = width-1)
.dmal:
        ld c,a
        ld a,DMA_WR0_LEN_LO
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,c
        out (IO_DATAGEAR_DMA_PORT),a    ; length = width
        ld a,DMA_WR4_CONT_MODE
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,l
        out (IO_DATAGEAR_DMA_PORT),a    ; port B = y*256 + x
        ld a,h
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,DMA_LOAD
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,DMA_ENABLE
        out (IO_DATAGEAR_DMA_PORT),a    ; CPU waits until the span is written
        jp push_end

;==============================================================================
; Outline the polygon in p2buf, skipping edges flagged 0 (clip edges)
;==============================================================================
outline_poly:
        ld ix,p2buf
        ld a,(p2n)
        ld b,a
.lp:    push bc
        ld a,(ix+2)
        or a
        jr z,.sk
        ld l,(ix+0)
        ld h,(ix+1)
        ld e,(ix+4)
        ld d,(ix+5)
        call draw_line
.sk:    ld bc,4
        add ix,bc
        pop bc
        djnz .lp
        ret

;==============================================================================
; Bresenham line, on-screen 8-bit coordinates.
;   L = x0, H = y0, E = x1, D = y1, colour in line_col.  Preserves IX, IY.
;   Pages Layer 2 sections into slot 0 as the line crosses them.
;==============================================================================
draw_line:
        ld a,(line_col)
        ld c,a
        ld a,e
        sub l
        jr nc,.xp
        neg
        ld b,OP_DEC_L
        jr .xd
.xp:    ld b,OP_INC_L
.xd:    ld e,a                          ; |dx|
        ld a,b
        ld (.smx1),a
        ld (.smx2),a
        ld a,d
        sub h
        jr nc,.yp
        neg
        ld b,OP_DEC_H
        jr .yd
.yp:    ld b,OP_INC_H
.yd:    ld d,a                          ; |dy|
        ld a,b
        ld (.smy1),a
        ld (.smy2),a
        ld a,h
        call seg_map                    ; page in the start row's section
        ld h,a                          ; y within the section
        ld a,e
        cp d
        jr c,.ymaj
        ld b,e
        inc b
        srl a
.xl:    ld (hl),c
.smx1:  inc l
        sub d
        jr nc,.xs
.smy1:  inc h
        bit 5,h                         ; left the 32-row section?
        call nz,line_seg
        add a,e
.xs:    djnz .xl
        ret
.ymaj:  ld b,d
        inc b
        ld a,d
        srl a
.yl:    ld (hl),c
.smy2:  inc h
        bit 5,h
        call nz,line_seg
        sub e
        jr nc,.ys
.smx2:  inc l
        add a,d
.ys:    djnz .yl
        ret

;==============================================================================
; Clear the viewport (rows 0..VIEW_H-1) of the back buffer with the zxnDMA,
; one 8K section (32 rows) at a time through slot 0: sky above the horizon
; row, ground below.  The fills reuse the l2_fill command block from
; layer2_cls.asm, patching its destination (port B) and length; the source
; (port A) is the fixed byte l2_cls_byte.  Zero-length fills are skipped.
;==============================================================================
clear_screen:
        ld c,0                          ; C = first row of the section
.sec:   ld a,c
        call seg_map
        ld a,(horizon)                  ; sky rows here = clamp(hz - C, 0, 32)
    IFDEF SKY_IS_WALL
        inc a                           ; the horizon row too: at the horizon
                                        ; it is all distant wall, and it hides
                                        ; a 1-row rounding gap under the
                                        ; wall's top edge when pitched
    ENDIF
        sub c
        jr nc,.s1
        xor a
.s1:    cp 33
        jr c,.s2
        ld a,32
.s2:    ld (cs_sky),a
        or a
        jr z,.gnd
        push bc
        ld b,a                          ; sky: section start, rows*256 bytes
        ld c,0
        ld hl,0
    IFDEF SKY_IS_WALL
        ld a,WALL_FAMILY*4+SHADE_FACE   ; "sky" is the perimeter wall
    ELSE
        ld a,SKY_COL
    ENDIF
        call dma_fill
        pop bc
.gnd:   ld a,(cs_sky)
        cp 32
        jr z,.nx
        push bc
        ld h,a                          ; ground: after the sky rows
        ld l,0
        neg
        add a,32
        ld b,a
        ld c,0
        ld a,GROUND_COL
        call dma_fill
        pop bc
.nx:    ld a,c
        add a,32
        ld c,a
        cp VIEW_H
        jr nz,.sec
        ; Leave the DMA ready for fill_spans: length high byte 0, so each span
        ; only reloads length low, destination, LOAD and ENABLE.  fill_poly
        ; puts each building's colour in the source byte l2_cls_byte.
.spans: ld a,DMA_WR0_LEN_HI
        out (IO_DATAGEAR_DMA_PORT),a
        xor a
        out (IO_DATAGEAR_DMA_PORT),a
        ret

; DMA fill: HL = destination, BC = length (non-zero), A = colour
dma_fill:
        ld (l2_cls_byte),a
        ld (l2_fill_bstrt),hl
        ld (l2_fill_length),bc
        ld hl,l2_fill
        ld b,l2_fill_cmd_len
        ld c,IO_DATAGEAR_DMA_PORT
        otir                            ; CPU waits while the DMA runs
        ret

;==============================================================================
; City traversal - back to front without sorting.
;   For grid-aligned boxes in separate cells, a box can only hide boxes whose
;   cell offsets from the camera cell are larger (or equal) on both axes in
;   the same quadrant.  So: rows from the far edges inwards, and within each
;   row columns from the far edges inwards, the camera row/column last.
;==============================================================================
draw_city:
    IFDEF OCCLUSION_CULL
        call occ_begin
        ld a,(occ_on)
        or a
        jr z,draw_cells                 ; pitched: the painter's order as is
        call occ_cells                  ; front to back: keep what isn't hidden
        ld a,(occ_full)
        or a
        jp z,occ_draw_list              ; back to front: draw it
        xor a                           ; too many to keep: draw this frame
        ld (occ_on),a                   ; the plain way
    ENDIF
draw_cells:
        ld a,(cz)
        sub VIEW_R
        ld (cell_j),a
.b:     ld a,(cell_j)
        ld hl,cz
        cp (hl)
        jr z,.f
        call draw_row
        ld hl,cell_j
        inc (hl)
        jr .b
.f:     ld a,(cz)
        add a,VIEW_R
        ld (cell_j),a
.f2:    ld a,(cell_j)
        ld hl,cz
        cp (hl)
        jr z,draw_row                   ; camera row last
        call draw_row
        ld hl,cell_j
        dec (hl)
        jr .f2

draw_row:
        ld a,(cell_j)
        cp GRID
        ret nc
        ld a,(cx)
        sub VIEW_R
        ld (cell_i),a
        call row_start
.l:     ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jr z,.r
        call try_cell
        ld hl,cell_i
        inc (hl)
        ld hl,(row_x)                   ; one cell +x: (X,Z1) += (cosY,sinY)
        ld de,(cos_y)
        add hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        add hl,de
        ld (row_z1),hl
        jr .l
.r:     ld a,(cx)
        add a,VIEW_R
        ld (cell_i),a
        call row_start
.r2:    ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jr z,try_cell                   ; camera column last
        call try_cell
        ld hl,cell_i
        dec (hl)
        ld hl,(row_x)                   ; one cell -x
        ld de,(cos_y)
        or a
        sbc hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        or a
        sbc hl,de
        ld (row_z1),hl
        jr .r2

; Yaw-rotated centre of cell (cell_i, cell_j) -> row_x, row_z1.  Moving one
; cell (256 units) in x then changes (X, Z1) by exactly the raw (cosY, sinY).
row_start:
        ld a,(cell_i)
        ld h,a
        ld l,128
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld a,(cell_j)
        ld h,a
        ld l,128
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (row_x),hl
        ld hl,(t_z1)
        ld (row_z1),hl
        ret

try_cell:
        ld a,(cell_i)
        cp GRID
        ret nc
    IFDEF DRAW_FPS
        call vtick                      ; keep the FPS clock sampling
    ENDIF
        ; fall through

;------------------------------------------------------------------------------
; Transform and draw the building in (cell_i, cell_j)
;------------------------------------------------------------------------------
draw_cell:
        ld a,(cell_j)
        ld l,a
        ld h,0
        ROWOFS
        ld a,(cell_i)
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        or a
        jr nz,.bld
        ; street: the zombies and humans standing there
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a
        jr z,.sdraw
        push hl
        call occ_zombie                 ; level flight: list them
        pop hl
        jp occ_human
.sdraw:
    ENDIF
        push hl
        call zombie_cell
        pop hl
        jp human_cell
.bld:   ld c,a
        call hum_here
        jr z,draw_bld                   ; nobody on the roof
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a
        jr z,.hdraw
        push bc
        push hl
        call occ_human                  ; listed before the building, so
        pop hl                          ; drawn after it
        pop bc
        jr draw_bld
.hdraw:
    ENDIF
        push hl
        call draw_bld                   ; the building, then the humans on
        pop hl                          ; its roof
        jp human_cell

; The building in the cell at HL (C = its map byte)
draw_bld:
        ld de,city_col-city_map         ; same index in city_col (page 7)
        add hl,de
        ld a,(hl)
        and %11111100
        ld (bld_col),a                  ; colour family (shade bits clear)
        ld a,c
        call bld_height
        ld (bld_h),hl
    IFDEF SKY_IS_WALL
        ; Perimeter wall (outer row/column): everything above the horizon is
        ; already wall-coloured, so draw it only up to camera height - its
        ; top edge then lies exactly on the horizon line, at any pitch.
        xor a
        ld (bld_wall),a
        ld a,(cell_i)
        inc a
        and GRID-2                      ; zero for column 0 or GRID-1
        jr z,.wall
        ld a,(cell_j)
        inc a
        and GRID-2
        jr nz,.nwall
.wall:  ld hl,(cam_y)
        ld (bld_h),hl
        ld a,1
        ld (bld_wall),a
.nwall:
    ENDIF
        ; world corners: the building fills its cell
        ld a,(cell_i)
        ld h,a
        ld l,0
        ld (bld_x0),hl
        inc h
        ld (bld_x1),hl
        ld a,(cell_j)
        ld h,a
        ld (bld_z0),hl
        inc h
        ld (bld_z1),hl

        ld hl,vecs0
        ld (bld_vecs),hl
        ld hl,256                       ; cull radius: 181 (half diagonal) * sqrt2
        ld (bld_r),hl

        ; yaw-space centre of this cell, kept up to date by draw_row
        ld hl,(row_z1)
        ld (t_z1),hl
        ld hl,(row_x)
        ld (t_x),hl
        ; Horizontal frustum cull, valid at any pitch: a visible point has
        ; |X|*c <= Z1 with c = cosP - 0.5|sinP|. Reject the bounding circle.
        call abs_hl
        ld de,(cull_c)
        call fmul
        ld de,(t_z1)
        or a
        sbc hl,de
        ld de,(bld_r)
        or a
        sbc hl,de
        ret p
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a                            ; (carry clear)
        call nz,occ_pretest
        ret c                           ; surely hidden: skip the transform
    ENDIF
        ; centre -> corner (x0,z0), still in yaw space
        ld ix,(bld_vecs)
        ld l,(ix+12)
        ld h,(ix+13)
        ld de,(t_x)
        add hl,de
        ld (vtx+0),hl
        ld l,(ix+14)
        ld h,(ix+15)
        ld de,(t_z1)
        add hl,de
        ld (t_z1),hl
        call rot_pitch
        ld (vtx+2),hl
        ld (vtx+4),de
        ld hl,(bld_vecs)
        ld de,cur_vx
        ld bc,12
        ldir                            ; cur_vx, cur_vz

        ; vertical edge vector (0, h cosP, h sinP)
        ld hl,(bld_h)
        ld de,(cos_p)
        call fmul
        ld (vy_vec+2),hl
        ld hl,(bld_h)
        ld de,(sin_p)
        call fmul
        ld (vy_vec+4),hl

        ; vertices: index = x + 2*z + 4*top  (box edges are shared vectors)
        VADD vtx+16, vtx+0,  cur_vx
        VADD vtx+32, vtx+0,  cur_vz
        VADD vtx+48, vtx+16, cur_vz
        VADD vtx+64, vtx+0,  vy_vec
        VADD vtx+80, vtx+16, vy_vec
        VADD vtx+96, vtx+32, vy_vec
        VADD vtx+112,vtx+48, vy_vec

        ; Back face culling is exact in world space for an axis aligned box.
        ; C = visible faces: bit0 -X, bit1 +X, bit2 -Z, bit3 +Z, bit4 top
        ld c,0
        ld hl,(cam_x+1)
        ld de,(bld_x0)
        or a
        sbc hl,de
        jr nc,.v1
        set 0,c
.v1:    ld hl,(bld_x1)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        jr nc,.v2
        set 1,c
.v2:    ld hl,(cam_z+1)
        ld de,(bld_z0)
        or a
        sbc hl,de
        jr nc,.v3
        set 2,c
.v3:    ld hl,(bld_z1)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        jr nc,.v4
        set 3,c
.v4:    ld hl,(bld_h)
        ld de,(cam_y)
        or a
        sbc hl,de
        jr nc,.v5
        set 4,c
.v5:    ; A wall against a neighbour at least as tall is completely hidden
        bit 0,c
        jr z,.w1
        ld a,(cell_i)
        dec a
        ld b,a
        ld a,(cell_j)
        call nb_cover
        jr nc,.w1
        res 0,c
.w1:    bit 1,c
        jr z,.w2
        ld a,(cell_i)
        inc a
        ld b,a
        ld a,(cell_j)
        call nb_cover
        jr nc,.w2
        res 1,c
.w2:    bit 2,c
        jr z,.w3
        ld a,(cell_i)
        ld b,a
        ld a,(cell_j)
        dec a
        call nb_cover
        jr nc,.w3
        res 2,c
.w3:    bit 3,c
        jr z,.w4
        ld a,(cell_i)
        ld b,a
        ld a,(cell_j)
        inc a
        call nb_cover
        jr nc,.w4
        res 3,c
.w4:    ld a,c
        ld (bld_vis),a
        or a
        ret z                           ; nothing of it can be seen
        ld hl,used_tab
        add hl,a
        ld a,(hl)
        ld (bld_used),a                 ; corners belonging to visible faces
        ld (bld_used0),a

        ; outcodes, trivial reject, project the on-screen corners.  Each
        ; bottom corner v (0-3) is done with the top corner above it (v+4).
        ld a,$FF
        ld (and_oc),a
        ld ix,vtx
        ld b,4
.ocl:   push bc
        ld a,$FF
        ld (bot_oc),a                   ; $FF: bottom corner not projected
        ld a,(bld_used)
        rrca
        ld (bld_used),a
        jr nc,.top                      ; hidden corner: not needed
        call vtx_oc
        ld (bot_oc),a
        or a
        call z,vtx_proj
.top:   ld de,64
        add ix,de
        ld a,(bld_used)
        bit 3,a                         ; this corner's top (bit v+4)
        jr z,.nt
        call vtx_oc
        or a
        jr nz,.nt
    IFDEF LEVEL_FAST_PATH
        ld a,(pitch)
        ld hl,bot_oc
        or (hl)
        jr nz,.full                     ; pitched, or bottom not projected
        ; Level flight: the top corner has the bottom corner's X and Z, so
        ; it shares its screen x and its 1/Z (still patched into
        ; scale_comp); only the screen y is new.
        ld l,(ix+2)
        ld h,(ix+3)
        call proj_y
        ld (ix+7),a                     ; sx
        ld (ix+8),c                     ; sy
        jr .nt
.full:
    ENDIF
        call vtx_proj
.nt:    ld de,16-64
        add ix,de
        pop bc
        djnz .ocl
        ld a,(and_oc)
        or a
        ret nz

        ; Shading: the roof is lighter; of the visible sides, the one the
        ; camera sees most squarely (furthest from its plane) is the base
        ; colour and the other is darker.
        ld a,(bld_col)
        or SHADE_ROOF
        ld (col_top),a
        ld a,(bld_col)
        or SHADE_FACE
        ld (col_x),a
        ld (col_z),a
        ld a,(bld_vis)
        and %00000011
        jr z,.shd                       ; only a Z side (or none)
        ld a,(bld_vis)
        and %00001100
        jr z,.shd                       ; only an X side
        ; both an X and a Z side: compare camera distances to the planes
        ld hl,(bld_x0)
        ld de,(cam_x+1)
        or a
        sbc hl,de                       ; x0 - camX  (> 0 when -X visible)
        ld a,(bld_vis)
        rra
        jr c,.dx
        ld hl,(cam_x+1)
        ld de,(bld_x1)
        or a
        sbc hl,de                       ; camX - x1
.dx:    push hl
        ld hl,(bld_z0)
        ld de,(cam_z+1)
        or a
        sbc hl,de                       ; z0 - camZ
        ld a,(bld_vis)
        bit 2,a
        jr nz,.dz
        ld hl,(cam_z+1)
        ld de,(bld_z1)
        or a
        sbc hl,de                       ; camZ - z1
.dz:    pop de                          ; DE = X distance, HL = Z distance
        or a
        sbc hl,de
        ld a,(bld_col)                  ; SHADE_DARK = 0
        jr c,.zdark                     ; Z side is further round: darker
        ld (col_x),a
        jr .shd
.zdark: ld (col_z),a
.shd:
    IFDEF SKY_IS_WALL
        ld a,(bld_wall)
        or a
        jr z,.nws
        ld a,(bld_col)                  ; wall: every side in the base colour,
        or SHADE_FACE                   ; to match the wall-coloured sky
        ld (col_x),a
        ld (col_z),a
.nws:
    ENDIF
        ld a,(bld_vis)
        ld c,a
        ; An edge shared with a face drawn later is left to that face:
        ; X faces skip their top edge if the roof shows and the vertical
        ; edge shared with a visible Z face; Z faces skip the top edge.
        ld b,$0F
        bit 4,c
        jr z,.m1
        res 2,b
.m1:    ld a,b
        ld (bld_mz),a
        bit 3,c
        jr z,.m2
        res 1,b
.m2:    bit 2,c
        jr z,.m3
        res 3,b
.m3:    ld a,b
        ld (bld_mx),a
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a
        jp nz,occ_record                ; level flight: draw it later
    ENDIF

; Draw the visible faces of the building whose corners are at vtx_hi:00,
; from bld_vis, bld_mx, bld_mz, col_x, col_z and col_top
draw_faces:
        ld a,(bld_vis)
        bit 0,a
        jr z,.f1
        ld a,(bld_mx)
        ld (df_mask),a
        ld a,(col_x)
        ld (face_col),a
        ld hl,face_nx
        call draw_face
.f1:    ld a,(bld_vis)
        bit 1,a
        jr z,.f2
        ld a,(bld_mx)
        ld (df_mask),a
        ld a,(col_x)
        ld (face_col),a
        ld hl,face_px
        call draw_face
.f2:    ld a,(bld_vis)
        bit 2,a
        jr z,.f3
        ld a,(bld_mz)
        ld (df_mask),a
        ld a,(col_z)
        ld (face_col),a
        ld hl,face_nz
        call draw_face
.f3:    ld a,(bld_vis)
        bit 3,a
        jr z,.f4
        ld a,(bld_mz)
        ld (df_mask),a
        ld a,(col_z)
        ld (face_col),a
        ld hl,face_pz
        call draw_face
.f4:    ld a,(bld_vis)
        bit 4,a
        ret z
        ld a,$0F
        ld (df_mask),a
        ld a,(col_top)
        ld (face_col),a
        ld hl,face_top
        jp draw_face

; IX -> vertex: outcode into (ix+6), ANDed into and_oc.  A = outcode.
vtx_oc:
        push ix
        pop hl
        call calc_oc
        ld (ix+6),a
        ld hl,and_oc
        and (hl)
        ld (hl),a
        ld a,(ix+6)
        ret

; IX -> vertex inside the frustum: project it into (ix+7) sx, (ix+8) sy
vtx_proj:
        push ix
        pop hl
        call project
        ld (ix+7),a
        ld (ix+8),c
        ret

; B = i, A = j of a neighbouring cell (may be off the map) -> carry set if
; it holds a building at least as tall as this one (bld_h).  Keeps C.
nb_cover:
        cp GRID
        ret nc                          ; off the map (carry clear)
        ld l,a
        ld a,b
        cp GRID
        ret nc
        ld h,0
        ROWOFS
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        or a
        ret z                           ; street (carry clear)
        call bld_height
        ld de,(bld_h)
        or a
        sbc hl,de
        ccf                             ; carry = neighbour >= this building
        ret

; Yaw rotation of (t_dx, t_dz):  Z1 = dx sinY + dz cosY -> t_z1
;                               X  = dx cosY - dz sinY -> HL
rot_yaw:
        ld hl,(t_dx)
        ld de,(sin_y)
        call fmul
        push hl
        ld hl,(t_dz)
        ld de,(cos_y)
        call fmul
        pop de
        add hl,de
        ld (t_z1),hl
        ld hl,(t_dz)
        ld de,(sin_y)
        call fmul
        push hl
        ld hl,(t_dx)
        ld de,(cos_y)
        call fmul
        pop de
        or a
        sbc hl,de
        ret

; Pitch rotation of a ground point at t_z1:
;   HL = Y = yb - Z1 sinP     DE = Z = zb + Z1 cosP
rot_pitch:
        ld hl,(t_z1)
        ld de,(sin_p)
        call fmul
        ex de,hl
        ld hl,(yb)
        or a
        sbc hl,de
        push hl
        ld hl,(t_z1)
        ld de,(cos_p)
        call fmul
        ld de,(zb)
        add hl,de
        ex de,hl
        pop hl
        ret

;==============================================================================
; Street intersection markers - one dot per grid corner near the camera
;==============================================================================
draw_dots:
        ld a,(cz)
        sub DOT_R
        ld (dot_j),a
        ld a,2*DOT_R+2
        ld (dot_rows),a
.row:   ld a,(dot_j)
        cp GRID+1
        jr nc,.nrow
        ; first corner of the row by full rotation, then step along x:
        ; +256 world units in x adds exactly (cosY, sinY) to (X, Z1)
        ld a,(cx)
        sub DOT_R
        ld (dot_i),a
        ld h,a
        ld l,0
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld a,(dot_j)
        ld h,a
        ld l,0
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (t_x),hl
        ld a,2*DOT_R+2
        ld (dot_cols),a
.col:   ld a,(dot_i)
        cp GRID+1
        call c,plot_dot
        ld hl,(t_x)
        ld de,(cos_y)
        add hl,de
        ld (t_x),hl
        ld hl,(t_z1)
        ld de,(sin_y)
        add hl,de
        ld (t_z1),hl
        ld hl,dot_i
        inc (hl)
        ld hl,dot_cols
        dec (hl)
        jr nz,.col
.nrow:  ld hl,dot_j
        inc (hl)
        ld hl,dot_rows
        dec (hl)
        jr nz,.row
        ret

; Plot the ground point (t_x, t_z1)
plot_dot:
        ld hl,(t_x)
        ld (tmpv+0),hl
        call abs_hl
        ld de,(cull_c)
        call fmul
        ld de,(t_z1)
        or a
        sbc hl,de
        ret p                           ; outside horizontal frustum / behind
        call rot_pitch
        ld (tmpv+2),hl
        ld (tmpv+4),de
        ld hl,tmpv
        call calc_oc
        or a
        ret nz
        ld hl,tmpv
        call project
        ld l,a
        ld a,c
        call seg_map
        ld h,a
        ld (hl),DOT_COL
        ret

;==============================================================================
; Rounds and the laser beam (`bullets`, laser_rec; moved by weapons.asm): a
; line along the path each covered this frame, from where it started to
; where it is.  A fresh round's path starts at the muzzle, below and behind
; the view, so its start is moved along the line to where it enters the
; view and pinned to that screen edge: the shot rises from the bottom row.
; Drawn over the city; a line whose end is outside the view is skipped.
;==============================================================================
draw_bullets:
        ld ix,bullets                   ; the rounds, then the laser beam
        ld b,NBULLETS+1
.lp:    push bc
        ld a,(ix+B_STATE)
        or a
        jr z,.nx
        ld a,(ix+B_KIND)
        cp BK_ROCKET
        jr nz,.rnd
        call draw_rocket
        jr .nx
.rnd:   ld a,(ix+B_STATE)
        cp 3                            ; 3: laser beam
        ld a,BULLET_COL
        jr nz,.col
        ld a,LASER_COL
.col:   ld (line_col),a
        push ix                         ; end: where it is now
        pop hl
        inc hl                          ; -> B_X, B_Y, B_Z
        call bul_cam
        jr nz,.nx                       ; not in view
        ld (bl_x),a
        ld a,c
        ld (bl_y),a
        ld hl,tmpv
        ld de,bh_cam
        ld bc,6
        ldir
        push ix                         ; start of this frame's path
        pop hl
        ld de,B_PX
        add hl,de
        call bul_cam
        call nz,bul_clip                ; outside: where the line enters
        ld e,a
        ld d,c
        ld a,(bl_x)
        ld l,a
        ld a,(bl_y)
        ld h,a
        call draw_line
.nx:    ld de,BREC
        add ix,de
        pop bc
        djnz .lp
        ret

; Rocket IX: a white streak ROCKET_LEN (1 m) long from its head back along
; its path, then a yellow trail to ROCKET_TRAIL (1.5 m) behind the head.
; Drawn only when every point drawn is in view (it's tiny: no clipping).
draw_rocket:
        push ix
        pop hl
        inc hl                          ; head: B_X, B_Y, B_Z
        call bul_cam
        ret nz                          ; not in view
        ld (bl_x),a
        ld a,c
        ld (bl_y),a
        ld a,ROCKET_LEN                 ; the tail of the streak
        call rk_back
        call bul_cam
        jr nz,.head                     ; out of view: the head pixel only
        ld (rk_sx),a
        ld a,c
        ld (rk_sy),a
        ld a,ROCKET_TRAIL               ; the end of the trail
        call rk_back
        call bul_cam
        jr nz,.white
        ld e,a                          ; yellow trail first, so the white
        ld d,c                          ; streak stays on top
        ld a,(rk_sx)
        ld l,a
        ld a,(rk_sy)
        ld h,a
        ld a,TRAIL_COL
        ld (line_col),a
        call draw_line
.white: ld a,(rk_sx)
        ld e,a
        ld a,(rk_sy)
        ld d,a
        jr .line
.head:  ld a,(bl_x)
        ld e,a
        ld a,(bl_y)
        ld d,a
.line:  ld a,(bl_x)
        ld l,a
        ld a,(bl_y)
        ld h,a
        ld a,ROCKET_COL
        ld (line_col),a
        jp draw_line

; A = distance d (units) -> HL -> rk_pt = rocket IX's head - d * (sin, slope,
; cos): d back along its path
rk_back:
        ld (rk_d),a
        ld e,(ix+B_SIN)
        ld d,(ix+B_SIN+1)
        ld bc,B_X
        call .ax
        ld (rk_pt),hl
        ld e,(ix+B_SLOPE)
        ld d,(ix+B_SLOPE+1)
        ld bc,B_Y
        call .ax
        ld (rk_pt+2),hl
        ld e,(ix+B_COS)
        ld d,(ix+B_COS+1)
        ld bc,B_Z
        call .ax
        ld (rk_pt+4),hl
        ld hl,rk_pt
        ret
; DE = S7.8 component, BC = offset of the coordinate -> HL = coord - d * DE
.ax:    push bc
        ld a,(rk_d)
        ld l,a
        ld h,0
        call fmul
        ex de,hl
        push ix
        pop hl
        pop bc
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,de
        ret

;==============================================================================
; Zombie burst particles: one pixel each, coloured by age (PART_COL0 + 4 per
; frame of age, bright to dark green), drawn over the city
;==============================================================================
draw_particles:
        ld ix,particles
        ld b,NPART
.lp:    push bc
        ld a,(ix+0)
        or a
        jr z,.nx
        push ix
        pop hl
        inc hl                          ; -> x, y, z
        call bul_cam
        jr nz,.nx                       ; not in view
        ld l,a                          ; x
        ld a,c
        call seg_map                    ; row's section -> A = y & 31
        ld h,a
        ld a,(ix+0)                     ; colour: PART_COL0 + (age-1)*4
        dec a
        add a,a
        add a,a
        add a,PART_COL0
        ld (hl),a
.nx:    ld de,PREC
        add ix,de
        pop bc
        djnz .lp
        ret

; HL -> world x, y, z: camera space into tmpv; A = outcode, Z set if in view
; (then A = screen x, C = screen y)
bul_cam:
        ld de,bp_x
        ld bc,6
        ldir
        ld hl,(bp_x)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld hl,(bp_z)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (tmpv+0),hl
        call rot_pitch                  ; at ground level
        ld (tmpv+2),hl
        ld (tmpv+4),de
        ld hl,(bp_y)                    ; + height * (cosP, sinP)
        ld de,(cos_p)
        call fmul
        ld de,(tmpv+2)
        add hl,de
        ld (tmpv+2),hl
        ld hl,(bp_y)
        ld de,(sin_p)
        call fmul
        ld de,(tmpv+4)
        add hl,de
        ld (tmpv+4),hl
        ld hl,tmpv
        call calc_oc
        or a
        ret nz
        ld hl,tmpv
        call project
        cp a                            ; Z set
        ret

; tmpv = the start, outside the planes in A; bh_cam = the end, in view.
; -> A = screen x, C = screen y where the line enters the view, pinned to
; the edge it crosses.
bul_clip:
        push ix
        ld (bc_oc),a
        ld hl,0
        ld (bc_t),hl
        ld c,1                          ; each plane the start is outside
.pl:    ld a,(bc_oc)
        and c
        jr z,.np
        ld a,c
        ld (clip_plane),a
        push bc
        ld ix,tmpv
        call plane_dist                 ; start: < 0
        push hl
        ld ix,bh_cam
        call plane_dist                 ; end: >= 0
        pop de
        or a
        sbc hl,de                       ; fe - fs
        ex de,hl
        call neg_hl                     ; -fs
        call div_frac                   ; t = -fs / (fe - fs)
        push ix
        pop hl
        ld de,(bc_t)                    ; the latest crossing counts
        or a
        sbc hl,de
        pop bc
        jr c,.np
        add hl,de
        ld (bc_t),hl
        ld a,c
        ld (bc_pl),a
.np:    sla c
        ld a,c
        cp 32
        jr nz,.pl
        ld ix,tmpv                      ; start += t * (end - start)
        ld b,3
.lc:    push bc
        ld l,(ix+bh_cam-tmpv)           ; end - start
        ld h,(ix+bh_cam-tmpv+1)
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        push de
        ld de,(bc_t)
        call mul_frac
        pop de
        add hl,de
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop bc
        djnz .lc
        pop ix
        ld hl,tmpv
        call project
        ld e,a
        ld a,(bc_pl)                    ; pin to the edge it crossed
        cp 16
        jr nz,.t
        ld c,VIEW_H-1                   ; bottom
.t:     cp 8
        jr nz,.l
        ld c,0                          ; top
.l:     cp 2
        jr nz,.r
        ld e,0                          ; left
.r:     cp 4
        jr nz,.d
        ld e,255                        ; right
.d:     ld a,e
        ret

;==============================================================================
; Gunsight in the centre of the Layer 2 viewport
;==============================================================================
draw_gunsight:
        ld a,HUD_COL
        ld (line_col),a
        ld hl,VIEW_CY*256+122
        ld de,VIEW_CY*256+125
        call draw_line
        ld hl,VIEW_CY*256+131
        ld de,VIEW_CY*256+134
        call draw_line
        ld hl,(VIEW_CY-6)*256+128
        ld de,(VIEW_CY-3)*256+128
        call draw_line
        ld hl,(VIEW_CY+3)*256+128
        ld de,(VIEW_CY+6)*256+128
        jp draw_line

    IFDEF OCCLUSION_CULL
;==============================================================================
; Occlusion culling (OCCLUSION_CULL, level flight only)
;
; In level flight every screen column is a vertical slice of the world through
; the camera.  The cells are walked in exactly the reverse of the painter's
; order, i.e. front to back.  Each building is transformed as usual, then
; tested against OCC_YBUF, which holds per column the row from which the
; screen is known to be covered down to the ground:
;   * hidden - in every column it spans, its highest point is no higher than
;     that row - it is dropped;
;   * otherwise it lowers the row across its columns to its lowest top
;     corner, and its corners and face settings are kept in a record.
; The kept buildings and the zombie cells are then drawn back to front.
; This is safe because buildings that share a column meet the walk front to
; back (the grid order guarantees it), the camera is above the ground (what
; is behind sits higher on screen), the cover row is the lowest top corner
; (an underestimate) and bounds are clamped inwards to the screen.  A
; building with a corner behind the camera is never dropped and never covers.
;==============================================================================
OCC_YBUF        equ $4000       ; per column: covered from this row down
OCC_LIST        equ $4100       ; kept buildings and zombie cells, 2 bytes each
OCC_REC0        equ $42         ; first record (high byte); 256 bytes each,
OCC_RECN        equ $60         ; up to $5F: 30 records ($6000 on: city_col)
; Record: copy of vtx (bytes 0-8 of each 16), then
OR_VIS          equ 128         ; bld_vis, bld_mx, bld_mz, col_x, col_z, col_top
; A list entry is a record's high byte (< $60), a cell with humans as its
; city_col address ($6000-$6FFF) or a cell with zombies as its city_map
; address (>= $C000).

; Start of the city: occlusion on only in level flight
occ_begin:
        xor a
        ld (occ_on),a
        ld (occ_full),a
        ld a,(pitch)
        or a
        ret nz
        inc a
        ld (occ_on),a
        ld hl,OCC_LIST
        ld (occ_lp),hl
        ld a,OCC_REC0
        ld (occ_rec),a
        ld hl,OCC_YBUF                  ; nothing covered yet
        ld (hl),VIEW_H
        ld de,OCC_YBUF+1
        ld bc,255
        ldir
        ret

; The cells of draw_cells in exactly the reverse order.  Each half row
; starts from the same cell as draw_row and steps the same way, so every
; cell gets bit-identical yaw-space coordinates.
occ_cells:
        ld a,(cz)
        ld (cell_j),a
        call occ_row                    ; camera row first
        ld b,VIEW_R
.f:     push bc
        ld hl,cell_j
        inc (hl)
        call occ_row                    ; then cz+1 .. cz+R
        pop bc
        djnz .f
        ld a,(cz)
        ld (cell_j),a
        ld b,VIEW_R
.n:     push bc
        ld hl,cell_j
        dec (hl)
        call occ_row                    ; then cz-1 .. cz-R
        pop bc
        djnz .n
        ret

occ_row:
        ld a,(cell_j)
        cp GRID
        ret nc
        ; right half, as draw_row: start at cx+R, step down to cx
        ld a,(cx)
        add a,VIEW_R
        ld (cell_i),a
        call row_start
        ld b,VIEW_R
.d:     call occ_stepm
        djnz .d
        ld a,(cx)
        ld (cell_i),a
        call try_cell                   ; camera column first
        ld b,VIEW_R
.r:     push bc
        ld hl,cell_i
        inc (hl)
        call occ_stepp
        call try_cell                   ; then cx+1 .. cx+R
        pop bc
        djnz .r
        ; left half, as draw_row: start at cx-R, step up to cx-1
        ld a,(cx)
        sub VIEW_R
        ld (cell_i),a
        call row_start
        ld b,VIEW_R-1
.u:     call occ_stepp
        djnz .u
        ld a,(cx)
        dec a
        ld (cell_i),a
        call try_cell                   ; then cx-1 .. cx-R
        ld b,VIEW_R-1
.l:     push bc
        ld hl,cell_i
        dec (hl)
        call occ_stepm
        call try_cell
        pop bc
        djnz .l
        ret

; One cell +x / -x in yaw space: (X, Z1) +/-= (cosY, sinY).  Keeps B.
occ_stepp:
        ld hl,(row_x)
        ld de,(cos_y)
        add hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        add hl,de
        ld (row_z1),hl
        ret
occ_stepm:
        ld hl,(row_x)
        ld de,(cos_y)
        or a
        sbc hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        or a
        sbc hl,de
        ld (row_z1),hl
        ret

; HL -> a city_map byte: list the cell (as its city_col address) if humans
; stand there
occ_human:
        call hum_here
        ret z
        ld de,city_col-city_map
        add hl,de
        ex de,hl
        ld hl,(occ_lp)
        ld (hl),e
        inc l
        ld (hl),d
        inc l
        ld (occ_lp),hl
        ret

; Empty cell, HL -> its city_map byte: list it if zombies stand there
occ_zombie:
        push hl
        ld de,zcell-city_map
        add hl,de
        ld a,(hl)
        pop hl
        or a
        ret z
        ex de,hl
        ld hl,(occ_lp)
        ld (hl),e
        inc l
        ld (hl),d
        inc l
        ld (occ_lp),hl
        ret

; draw_cell tail in level flight: drop the building if it is hidden,
; otherwise make it a cover and keep it (corners in vtx, face settings)
occ_record:
        ld a,(occ_full)
        or a
        ret nz
        ld a,(occ_rec)
        cp OCC_RECN
        jr c,.room
        ld a,1                          ; out of records: give up this frame
        ld (occ_full),a
        ret
.room:  ld (occ_cur),a
        ; screen bounds of the corners of the drawn faces
        xor a
        ld (o_xmax),a
        ld (o_tcov),a
        dec a
        ld (o_xmin),a
        ld (o_ymin),a
        ld a,(bld_used0)
        ld (o_used),a
        ld ix,vtx
        ld b,8
.cl:    push bc
        ld a,(o_used)
        rrca
        ld (o_used),a
        jr nc,.nx                       ; corner not on a drawn face
        ld a,(ix+6)
        bit 0,a
        jr nz,.keep                     ; behind the near plane: no bounds
        or a
        call nz,vtx_proj                ; off screen: clamped projection
        ld a,(ix+7)                     ; sx
        ld hl,o_xmin
        cp (hl)
        jr nc,.x1
        ld (hl),a
.x1:    ld hl,o_xmax
        cp (hl)
        jr c,.x2
        ld (hl),a
.x2:    ld a,(ix+8)                     ; sy
        ld hl,o_ymin
        cp (hl)
        jr nc,.y1
        ld (hl),a
.y1:    pop bc
        push bc
        ld a,b
        cp 5
        jr nc,.nx                       ; corners 0-3 are the bottom ones
        ld a,(ix+6)
        and 16
        ld a,VIEW_H                     ; top corner below the screen:
        jr nz,.tc                       ; covers nothing
        ld a,(ix+8)
.tc:    ld hl,o_tcov
        cp (hl)
        jr c,.nx
        ld (hl),a                       ; lowest top corner
.nx:    ld de,16
        add ix,de
        pop bc
        djnz .cl
        call occ_test
        ret c                           ; hidden: dropped
        jr .store
.keep:  pop bc                          ; no bounds: keep, but no cover
.store: ld a,(occ_cur)
        ld d,a
        ld e,0
        ld hl,vtx
        ; corners: only bytes 0-8 of each 16 are used (X,Y,Z,oc,sx,sy);
        ; vtx and the record are both page aligned, so L = E throughout
        REPT 8
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ld a,l
        add a,7
        ld l,a
        ld e,a
        ENDR
        ld e,OR_VIS
        ld hl,bld_vis                   ; bld_vis .. col_top: record order
        ld bc,6
        ldir
        ld hl,(occ_lp)                  ; keep it on the list
        ld (hl),0
        inc l
        ld a,(occ_cur)
        ld (hl),a
        inc l
        ld (occ_lp),hl
        ld hl,occ_rec
        inc (hl)
        ret

; Before the transform: rough screen bounds of the building from its cell
; centre (t_x, t_z1; at pitch 0 camera Z = Z1), a circle of radius OCC_R
; around it and its height, each widened by a pixel for rounding.
; Carry set if those bounds are already hidden.
OCC_R           equ 188             ; half the cell diagonal (181) + rounding
occ_pretest:
        ld a,(occ_full)
        or a
        ret nz                          ; not keeping any more: no point
        ld hl,(t_z1)
        ld de,-OCC_R-NEAR
        add hl,de
        bit 7,h
        jp nz,.no                       ; may reach the near plane
        ld hl,(t_z1)
        ld de,-OCC_R
        add hl,de
        ld (o_zmin),hl
        ld de,2*OCC_R
        add hl,de
        ld (o_zmax),hl
        ; left edge: X-R, over the far Z if positive, the near Z if negative
        ld hl,(t_x)
        ld de,-OCC_R
        add hl,de
        ld de,(o_zmax)
        bit 7,h
        jr z,.l1
        ld de,(o_zmin)
.l1:    call occ_sx
        or a
        jr z,.l2
        dec a
.l2:    ld (o_xmin),a
        ; right edge: X+R, over the near Z if positive, the far Z if negative
        ld hl,(t_x)
        ld de,OCC_R
        add hl,de
        ld de,(o_zmin)
        bit 7,h
        jr z,.r1
        ld de,(o_zmax)
.r1:    call occ_sx
        inc a
        jr nz,.r2
        dec a
.r2:    ld (o_xmax),a
        ; top: height above the eye over the near Z, or below it over the far Z
        ld hl,(bld_h)
        ld de,(cam_y)
        or a
        sbc hl,de
        jr c,.below
        push hl                         ; (zpatch uses DE)
        ld hl,(o_zmin)
        call zpatch
        pop hl
        call scale_comp                 ; A = 128 * (h - camY) / Zmin
        ld c,a
        ld a,VIEW_CY-1
        sub c
        jr nc,.ty
        xor a
        jr .ty
.below: call neg_hl                     ; camY - h
        push hl
        ld hl,(o_zmax)
        call zpatch
        pop hl
        call scale_comp                 ; A = 128 * (camY - h) / Zmax
        add a,VIEW_CY-1
        jr nc,.ty
        ld a,255
.ty:    ld (o_ymin),a
        jp occ_hidden
.no:    or a
        ret

; HL = X, DE = Z -> A = screen x, clamped to 0..255
occ_sx:
        ld a,h
        push af
        push hl
        ex de,hl
        call zpatch
        pop hl
        call scale_comp
        ld c,a
        pop af
        rla
        jr c,.n
        ld a,128
        add a,c
        ret nc
        ld a,255
        ret
.n:     ld a,128
        sub c
        ret nc
        xor a
        ret

; Bounds o_xmin/o_xmax/o_ymin against the cover buffer: carry set if hidden
; in every column; otherwise lower the cover to o_tcov over those columns.
occ_test:
        call occ_hidden
        ret c
        ld a,(o_tcov)
        cp VIEW_H
        jr nc,.none                     ; covers nothing
        ld c,a
        ld l,e
.u:     ld a,(hl)
        cp c
        jr c,.un                        ; already covered higher up
        ld (hl),c
.un:    inc l
        djnz .u
.none:  or a                            ; visible (carry clear)
        ret

; Carry set if o_xmin..o_xmax are all covered from o_ymin or higher.
; Leaves E = o_xmin, B = column count, H = high OCC_YBUF.
occ_hidden:
        ld a,(o_xmin)
        ld e,a
        ld a,(o_xmax)
        sub e
        inc a
        ld b,a                          ; columns (0 = all 256)
        ld a,(o_ymin)
        inc a
        ld c,a                          ; hidden where cover <= ymin
        ld h,high OCC_YBUF
        ld l,e
        push bc
.t:     ld a,(hl)
        cp c
        jr nc,.vis
        inc l
        djnz .t
        pop bc
        scf
        ret
.vis:   pop bc
        or a
        ret

; Draw the kept buildings and zombie cells, back to front (list backwards)
occ_draw_list:
        ld hl,(occ_lp)
.l:     ld a,l
        or a
        ret z
        dec l
        ld d,(hl)
        dec l
        ld e,(hl)
        push hl
        ld a,d
        cp $60
        jr c,.bld                       ; < $60: a building record
        ex de,hl
        cp $80
        jr nc,.zom
        ld de,city_map-city_col         ; $60-$6F: humans (city_col address)
        add hl,de
        call human_cell
        jr .nx
.zom:   call zombie_cell                ; >= $C000: zombies (city_map address)
        jr .nx
.bld:   ld h,d                          ; record D
        ld l,OR_VIS
        ld de,bld_vis
        ld bc,6
        ldir
        ld a,h
        ld (vtx_hi),a
        call draw_faces
        ld a,high vtx
        ld (vtx_hi),a
.nx:    pop hl
        jr .l
    ENDIF

;==============================================================================
; City page data
;==============================================================================
; Faces as vertex offsets (index*16); vertex index = x + 2*z + 4*top.
; Side faces list bottom edge first, then the z1/x1 vertical, top, z0/x0.
face_nx:  db 0*16,2*16,6*16,4*16
face_px:  db 1*16,3*16,7*16,5*16
face_nz:  db 0*16,1*16,5*16,4*16
face_pz:  db 2*16,3*16,7*16,6*16
face_top: db 4*16,5*16,7*16,6*16

; --- building / view work areas ---
cur_vx:     ds 6
cur_vz:     ds 6
vy_vec:     dw 0,0,0
cell_i:     db 0
cell_j:     db 0
bld_h:      dw 0
bld_wall:   db 0                        ; 1: perimeter wall cell (SKY_IS_WALL)
bld_col:    db 0
face_col:   db 0
bld_vecs:   dw 0
bld_x0:     dw 0
bld_x1:     dw 0
bld_z0:     dw 0
bld_z1:     dw 0
t_dx:       dw 0
t_dz:       dw 0
t_z1:       dw 0
t_x:        dw 0
row_x:      dw 0
row_z1:     dw 0
bld_used:   db 0
vtx_hi:     db high vtx                 ; corners draw_face reads (vtx or a record)
bld_used0:  db 0                        ; corners of drawn faces (unrotated)
    IFDEF OCCLUSION_CULL
occ_on:     db 0                        ; 1: recording (level flight)
occ_full:   db 0                        ; 1: ran out of records this frame
occ_lp:     dw 0                        ; end of the draw list
occ_rec:    db 0                        ; next free record (high byte)
occ_cur:    db 0
o_used:     db 0
o_xmin:     db 0
o_xmax:     db 0
o_ymin:     db 0
o_tcov:     db 0
o_zmin:     dw 0
o_zmax:     dw 0
    ENDIF
bld_r:      dw 0
and_oc:     db 0
bot_oc:     db 0
rk_pt:      ds 6                        ; draw_rocket: a point behind it
rk_d:       db 0
rk_sx:      db 0                        ; screen point 1 m behind the head
rk_sy:      db 0
bp_x:       dw 0                        ; draw_bullets
bp_y:       dw 0
bp_z:       dw 0
bl_x:       db 0
bl_y:       db 0
bh_cam:     ds 6                        ; end of the drawn path, camera space
bc_oc:      db 0                        ; bul_clip
bc_t:       dw 0
bc_pl:      db 0
dot_i:      db 0
dot_j:      db 0
dot_rows:   db 0
dot_cols:   db 0
tmpv:       ds 8

; --- projection ---
pj_x:       dw 0
pj_y:       dw 0
pj_sh:      db 0
pj_r:       dw 0
pj_sx:      db 0
mf_sign:    db 0

; --- clipping ---
df_ptr:     dw 0
df_or:      db 0
df_mask:    db 0
df_m:       db 0
df_cur:     db 0
bld_vis:    db 0                        ; bld_vis .. col_top: kept together
bld_mx:     db 0                        ; (occlusion records copy them)
bld_mz:     db 0
col_x:      db 0
col_z:      db 0
col_top:    db 0
clip_n:     db 0
clip_on:    db 0
clip_cnt:   db 0
clip_plane: db 0
clip_src:   dw 0
clip_dst:   dw 0
clip_s:     dw 0
clip_e:     dw 0
clip_ds:    dw 0
clip_de:    dw 0
clip_if:    db 0
ci_a:       dw 0
ci_t:       dw 0
clipA:      ds 8*12
clipB:      ds 8*12

; --- polygon / line / clear ---
p2n:        db 0
fy0:        db 0
fy1:        db 0
fe_cnt:     db 0
line_col:   db 0
saved_sp:   dw 0
seg_page:   db 0                        ; page now in slot 0
cs_sky:     db 0

        INCLUDE "layer2_cls.asm"        ; zxnDMA equates + fill command block
