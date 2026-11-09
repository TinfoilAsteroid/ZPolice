;==============================================================================
; Z-POLICE - city page (8K page PAGE_CITY, runs at $E000)
;
; All Layer 2 drawing: back-to-front city traversal, building transform,
; culling and shading, 3D clipping, projection, polygon fill, lines, the
; viewport clear, ground dots and the gunsight.  Paged in by main_loop with
; nextreg CODE_MMU,PAGE_CITY.  Shared variables and tables live in zpolice.asm.
;==============================================================================

        ALIGN 256
vtx:        ds 8*16                     ; X,Y,Z,oc,sx,sy + pad
p2buf:      ds 4*16                     ; x,y,edge flag,pad
; (the rest of this 256 bytes, and of push_blk's: clipping variables)
df_ptr:     dw 0
df_or:      db 0
df_mask:    db 0
df_m:       db 0
df_cur:     db 0
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
    IFDEF CLIP_2D
c2_or:      db 0                        ; clip2d: the planes to clip against,
c2_off:     db 0                        ;   the one now (coordinate, bound)
c2_hi:      db 0
; the 2D planes, in c2_or's bit order: coordinate (0 x, 2 y), bound (0: a
; lower bound of 0, else an upper bound)
c2_planes:  db 0,0, 0,255, 2,0, 2,VIEW_H-1
    ENDIF
pj_sx:      db 0
mf_sign:    db 0
p2n:        db 0
fy0:        db 0
fy1:        db 0
fe_cnt:     db 0
line_col:   db 0
seg_page:   db 0                        ; page now in slot 0
cs_sky:     db 0
and_oc:     db 0
bot_oc:     db 0
bc_oc:      db 0                        ; bul_clip
bc_t:       dw 0
bc_pl:      db 0
dot_i:      db 0
dot_j:      db 0
dot_rows:   db 0
dot_cols:   db 0
        ASSERT $ <= vtx + 256

        ALIGN 256
; Unrolled span writer: entry = push_end - 1 - pairs (pairs 1..128).  SP is
; borrowed (it points into the span), so an interrupt pushes its return
; address just below SP: harmless while PUSHes remain, as they overwrite it,
; but not after the last one.  So interrupts are off from just before the
; last PUSH until SP is back (a few instructions: one arriving meanwhile
; waits, as the interrupt line is held far longer).  The routine
; (im2_routine) also switches to its own stack at once.
push_blk:
        REPT 127
        push de
        ENDR
        di                              ; (no interrupt after the last PUSH
        push de                         ; with SP still borrowed)
push_end:
        ld sp,iy                        ; (fill_spans keeps the stack in IY)
        ei
push_next:                              ; (a 1-pixel span: SP never borrowed)
        inc b                           ; the next row
        dec ixh                         ; (rows left)
        ret z
        ld a,b
        and 31
        jp nz,fs_loop
.sect:  ld a,(seg_page)                 ; next row starts a new section
        inc a
        ld (seg_page),a
        nextreg L2SEC_MMU,a
        jp fs_loop
clipA:      ds 8*12                     ; (in the rest of these 256 bytes)
        ASSERT $ <= push_blk + 256

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
        nextreg L2SEC_MMU,a
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
        nextreg L2SEC_MMU,a
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
; Restoring division, unrolled: each quotient bit goes in inverted, as the
; carry (set: the divisor didn't fit), 8 into A, which is complemented:
; the high byte, then the low.  Keeps BC.
    MACRO DIVBIT q
        add hl,hl
        jr c,$+9                        ; (17-bit remainder: it fits)
        sbc hl,de                       ; (carry clear)
        jr nc,$+9                       ; fits: bit 1 (carry clear)
        add hl,de                       ; doesn't: put it back (carry set)
        jr $+6
        or a                            ; (from the jr c)
        sbc hl,de
        or a                            ; bit 1
        q                               ; (all the jumps land here)
    ENDM
div_frac:
        push bc
        ld b,2
.lp:    REPT 8
        DIVBIT rla
        ENDR
        cpl
        ld ixl,a
        dec b
        jr z,.d
        ld ixh,a                        ; (the high byte)
        jp .lp
.d:     pop bc
        ret

; E = A / C, A = A mod C  (8-bit unsigned, C 1..127).  By reciprocal:
; q = (A * R) >> 16, R = rcp8[C] = ceil(65536 / C), exact for every A
; (gentables.py checks it); then the remainder A - q C.  Keeps C, D, H, L
; (walk_edge's); B is lost.
div8:
        push hl
        push de
        ld e,a                          ; A (the dividend)
        ld a,c
        dec a
        jr z,.one                       ; C = 1
        ld l,c
        ld h,high rcp8
        ld d,(hl)                       ; R low
        set 7,l
        ld h,(hl)                       ; R high
        ld l,e                          ; (A kept)
        mul d,e                         ; A * R low
        ld b,d
        ld d,h
        ld e,l
        mul d,e                         ; A * R high
        ld a,b
        add a,e
        ld a,d
        adc a,0                         ; q = (A Rh + (A Rl >> 8)) >> 8
        ld b,a
        ld d,a
        ld e,c
        mul d,e                         ; q C (< 256)
        ld a,l
        sub e                           ; the remainder
        pop de
        pop hl
        ld e,b                          ; E = q
        ret
.one:   ld b,e                          ; over 1: q = A, remainder 0
        xor a
        pop de
        pop hl
        ld e,b
        ret
        ASSERT low rcp8 == 0 && VIEW_H <= 128   ; (C, an edge's rows, < 128)

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
        ld c,OP_BSRL                    ; (scale_comp: right)
        jr .nrm
.lt512: ld b,0
        ld c,OP_BSRL                    ; (right by 0: as it is)
        or a
        jr nz,.nrm                      ; 256..511 already normalised
        ld e,l                          ; Z < 256: shift left by 8-log2(L)
        ld d,high lgtab
        ld a,(de)
        sub 8
        neg
        ld b,a                          ; the count
        ex de,hl
        bsla de,b
        ex de,hl
        ld c,OP_BSLA                    ; (scale_comp: left)
.nrm:   ld a,b                          ; patch shift and reciprocal into
        ld (scale_comp.sh+1),a          ; scale_comp's immediates: the shift's
        ld a,c                          ; count and its opcode (the barrel
        ld (scale_comp.op+1),a          ; shift's second byte: which way)
        ld h,high rtab_lo               ; L = Zn - 256
        ld a,(hl)
        ld (scale_comp.rl+1),a
        ld (scale_comp.r16+1),a
        inc h
        ld a,(hl)
        ld (scale_comp.rh+1),a
        ld (scale_comp.r16+2),a
        ret

    IFDEF CLIP_2D
;==============================================================================
; 2D clip of the current face (df_ptr, df_mask), no corner behind the near
; plane.  Carry set: a corner is outside the guard band (nothing drawn, clip
; it in 3D).  Else p2buf / p2n hold the clipped polygon (p2n < 3: none).
; The corners go into clipA as x, y (16-bit screen), pad, edge flag (+6),
; pad, and are clipped by clip_poly with clip_plane = $80: plane_dist and
; clip_isect then work on the 2D plane c2_off / c2_hi, one of x >= 0,
; x <= 255, y >= 0, y <= VIEW_H-1, and only those some corner is outside.
;==============================================================================
clip2d:
        ld hl,(df_ptr)
        ld iy,clipA
        ld a,(df_mask)
        ld (df_m),a
        xor a
        ld (c2_or),a                    ; the planes the corners cross
        ld b,4
.cp:    push bc
        ld a,(hl)
        inc hl
        push hl
        ld l,a
        ld a,(vtx_hi)
        ld h,a
        push hl
        pop ix                          ; IX -> the corner
        ld a,(ix+6)
        or a
        jr nz,.off
        ld a,(ix+7)                     ; on screen: its cached sx, sy
        ld (iy+0),a
        ld (iy+1),0
        ld a,(ix+8)
        ld (iy+2),a
        ld (iy+3),0
        jr .fl
.off:   call guard_proj
        jp c,.fail
.fl:    ld a,(df_m)                     ; edge flag from the mask
        ld e,a
        and 1
        ld (iy+6),a
        ld a,e
        rrca
        ld (df_m),a
        ld de,8
        add iy,de
        pop hl
        pop bc
        djnz .cp

        ld a,4
        ld (clip_n),a
        ld hl,clipA
        ld (clip_src),hl
        ld hl,clipB
        ld (clip_dst),hl
        ld a,$80
        ld (clip_plane),a               ; (a 2D plane)
        ld hl,c2_planes
.pl:    ld a,(c2_or)
        srl a
        ld (c2_or),a
        jr nc,.skip
        ld a,(hl)
        ld (c2_off),a
        inc hl
        ld a,(hl)
        ld (c2_hi),a
        dec hl
        push hl
        call clip_poly
        pop hl
        ld a,(clip_n)
        cp 3
        jr c,.none
.skip:  inc hl
        inc hl
        ld a,(c2_or)
        or a
        jr nz,.pl

        ld hl,(clip_src)                ; to p2buf: all on screen, 8-bit
        ld de,p2buf
        ld a,(clip_n)
        ld (p2n),a
        ld b,a
.o:     ld a,(hl)                       ; x
        ld (de),a
        inc de
        inc hl
        inc hl
        ld a,(hl)                       ; y
        ld (de),a
        inc de
        ld a,4
        add hl,a
        ld a,(hl)                       ; edge flag
        ld (de),a
        inc de
        inc de
        inc hl
        inc hl
        djnz .o
        or a
        ret
.none:  xor a                           ; (carry clear)
        ld (p2n),a
        ret
.fail:  pop hl
        pop bc
        scf
        ret

; IX -> corner (X, Y, Z; Z >= NEAR) -> its screen x, y (16-bit) at IY+0, +2,
; the screen planes it is outside ORed into c2_or.  Carry set (nothing
; stored) if outside the guard band |X| <= 2Z, |Y| <= Z.
guard_proj:
        ld l,(ix+4)
        ld h,(ix+5)
        push hl                         ; Z
        ld l,(ix+0)
        ld h,(ix+1)
        call abs_hl
        ex de,hl                        ; |X|
        pop hl
        push hl
        add hl,hl                       ; 2Z (carry: over 65535, so more)
        jr c,.g1
        sbc hl,de
        jr c,.out
.g1:    ld l,(ix+2)
        ld h,(ix+3)
        call abs_hl
        ex de,hl                        ; |Y|
        pop hl
        push hl
        or a
        sbc hl,de
        jr c,.out
        pop hl
        ld a,l                          ; (zpatch tests HL = 0 with A = L)
        call zpatch
        ld l,(ix+0)
        ld h,(ix+1)
        ld de,128
        ld bc,255<<8|1                  ; x: 0..255, c2_or bits 0, 1
        call c2_scr                     ; 128 + 128X/Z
        ld (iy+0),l
        ld (iy+1),h
        ld l,(ix+2)
        ld h,(ix+3)
        call neg_hl
        ld de,VIEW_CY
        ld bc,(VIEW_H-1)<<8|4           ; y: 0..VIEW_H-1, c2_or bits 2, 3
        call c2_scr                     ; VIEW_CY - 128Y/Z
        ld (iy+2),l
        ld (iy+3),h
        or a
        ret
.out:   pop hl
        scf
        ret

; HL = component, DE = the screen centre, B = the upper bound, C = the lower
; plane's c2_or bit (the upper's is the next) -> HL = DE + 128 HL / Z (the
; Z patched in by zpatch), and the plane it is outside, if any, into c2_or
c2_scr:
        push bc
        push de
        ld a,h
        push af
        call scomp16
        pop af
        rla
        call c,neg_hl
        pop de
        add hl,de
        pop bc
        ld a,h
        or a
        jr z,.z
        jp m,.lo                        ; < 0
        jr .hi                          ; > 255
.z:     ld a,b
        cp l
        ret nc                          ; inside
.hi:    sla c
.lo:    ld a,(c2_or)
        or c
        ld (c2_or),a
        ret

; HL = signed component -> HL = round(|HL| * 128 / Z), |HL| <= 2Z: as
; scale_comp (the same shift and reciprocal, patched into it by zpatch),
; with a 10-bit Xn and a 16-bit result
scomp16:
        call abs_hl
        ex de,hl
        ld a,(scale_comp.sh+1)          ; the shift zpatch set: its count,
        ld b,a
        ld a,(scale_comp.op+1)          ; and which way (its opcode)
        cp OP_BSLA
        jr z,.l
        bsrl de,b
        jr .s
.l:     bsla de,b
.s:     ex de,hl
        ld a,h
        cp 4
        jr c,.ok
        ld hl,1023                      ; (rounding at the guard band's edge)
.ok:    ld b,h                          ; bits 8-9 of Xn
        ld a,(scale_comp.rl+1)
        ld e,a
        ld d,l
        mul d,e                         ; Xl*Rl
        ld c,d
        ld a,(scale_comp.rh+1)
        ld e,a
        ld d,l
        mul d,e                         ; Xl*Rh
        ld a,c
        add a,e
        ld l,a
        ld a,d
        adc a,0
        ld h,a                          ; HL = (Xl*R) >> 8
        ld c,0
        ld a,b
        or a
        jr z,.nh
        ld de,(scale_comp.r16+1)
.ad:    add hl,de                       ; + (256 * Xh * R) >> 8
        jr nc,.a1
        inc c
.a1:    djnz .ad
.nh:    inc h                           ; + rounding (0.5 after >>9)
        jr nz,.nr
        inc c
.nr:    ld l,h
        ld h,c
        srl h
        rr l                            ; HL = (C:H) >> 1 = P >> 9
        ret

; clip_isect for a 2D plane: the point where the edge S-E crosses it, out
; at IY (IY and clip_on advanced).  Worked out from the edge's inside end,
; so an edge two faces share is cut at the same point whichever way it
; runs: t = d_in / (|dS| + |dE|), the other coordinate o_in + t (o_out -
; o_in), this one exactly on the bound.
c2_isect:
        ld hl,(clip_s)
        ld de,(clip_e)
        ld a,(clip_ds+1)
        rla
        jr nc,.sin
        ex de,hl                        ; S outside: E is the inside end
.sin:   ld a,(c2_off)
        xor 2                           ; the other coordinate
        add hl,a
        ld c,(hl)
        inc hl
        ld b,(hl)                       ; o_in
        ex de,hl
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; o_out
        or a
        sbc hl,bc                       ; o_out - o_in
        jr z,.same                      ; (a vertical / horizontal edge: o_in)
        push bc
        push hl
        ld hl,(clip_ds)
        call abs_hl
        ex de,hl
        ld hl,(clip_de)
        call abs_hl
        add hl,de
        ex de,hl                        ; |dS| + |dE|
        ld hl,(clip_ds)
        bit 7,h
        jr z,.di
        ld hl,(clip_de)
.di:    call div_frac                   ; t = d_in / (|dS| + |dE|)
        pop hl                          ; o_out - o_in
        push ix
        pop de
        call mul_frac
        pop bc
.same:  add hl,bc                       ; o_in + t (o_out - o_in)
        ld a,(c2_off)
        or a
        jr nz,.y
        ld (iy+2),l                     ; an x plane: y worked out
        ld (iy+3),h
        ld a,(c2_hi)
        ld (iy+0),a
        ld (iy+1),0
        jr .f
.y:     ld (iy+0),l                     ; a y plane: x worked out
        ld (iy+1),h
        ld a,(c2_hi)
        ld (iy+2),a
        ld (iy+3),0
.f:     jp clip_isect.nz                ; its edge flag, IY and clip_on on
    ENDIF

; HL = signed component -> A = round(|HL| * 128 / Z)
; The shift and reciprocal for this Z are patched in by zpatch: the shift
; as a barrel shift whose count and direction (its opcode, BSRL or BSLA)
; are both patched, so it runs straight through (a right shift by 0 for a Z
; already 256..511 leaves it as it is).
scale_comp:
        bit 7,h
        jr z,.ap
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.ap:    ex de,hl
.sh:    ld b,0                          ; (zpatch: the count)
.op:    bsrl de,b                       ; (zpatch: bsrl, or bsla)
        ex de,hl
        ASSERT {b scale_comp.op} == $ED && {b scale_comp.op+1} == OP_BSRL
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

    IFDEF CLIP_2D
; plane_dist for a 2D plane (clip2d): IX -> 2D vertex -> HL = its distance
; inside c2_off / c2_hi (>= 0: inside)
c2_dist:
        ld a,(c2_off)
        push ix
        pop hl
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,(c2_hi)
        or a
        ret z                           ; v >= 0: v
        ex de,hl
        ld l,a
        ld h,0
        or a
        sbc hl,de                       ; v <= bound: bound - v
        ret
    ENDIF

; Signed distance of vertex IX to clip plane (clip_plane bit). >= 0 is inside.
plane_dist:
    IFDEF CLIP_2D
        ld a,(clip_plane)
        rla
        jr c,c2_dist                    ; (bit 7: a 2D plane)
    ENDIF
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
.ein:   ld hl,(clip_e)                  ; whole vertex, with its corner byte
        push iy                         ; (LDI: 16 T a byte)
        pop de
        REPT 8
        ldi
        ENDR
        push de
        pop iy
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
        ld hl,(clip_src)                ; the output is the next pass's input
        ld de,(clip_dst)
        ld (clip_src),de
        ld (clip_dst),hl
        ret

; Output S + t*(E-S) at IY, t = dS/(dS-dE)
clip_isect:
    IFDEF CLIP_2D
        ld a,(clip_plane)
        rla
        jp c,c2_isect                   ; (bit 7: a 2D plane)
    ENDIF
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
        ld a,(face_set)                 ; (corners in a page's upper half, an
        add hl,a                        ; odd occlusion record: the +128 lists)
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
    IFDEF CLIP_2D
        rra
        jr c,.clip3                     ; crosses the near plane: in 3D
        ld c,a
        ld a,(pitch)
        or a
        jr nz,.c2d                      ; pitched: in 2D
        ld a,c
        dec a
        and c                           ; (the lowest plane's bit cleared)
        jr z,.clip3                     ; level, one plane: in 3D, as quick
.c2d:   call clip2d                     ; (its vertical-edge shortcut, and
                                        ; no corners off screen to project)
        jr c,.clip3                     ; outside the guard band: in 3D
        ld a,(p2n)
        cp 3
        ret c                           ; clipped away
        jp .render
.clip3:
    ENDIF
        ld a,(df_mask)
        ld (df_m),a
        ld hl,(df_ptr)
        ld iy,clipA
        ld b,4
.cp:    ld a,(hl)
        inc hl
        ld (df_cur),a
        push hl
        push bc
        ld l,a                          ; the corner's X, Y, Z into the clip
        ld a,(vtx_hi)                   ; buffer (LDI: 16 T a byte)
        ld h,a
        push iy
        pop de
        REPT 6
        ldi
        ENDR
        push hl
        pop ix                          ; IX -> the corner's outcode (+6)
        push de
        pop iy
        pop bc
        pop hl
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
        ld a,(df_cur)                   ; on screen: projection is cached;
        rrca                            ; kept as its offset / 2, below $80
.cn:    ld (iy+1),a                     ; (a new point's is $80 up)
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
        add a,a                         ; unclipped on-screen corner (its
        add a,7                         ; offset / 2): reuse its cached sx, sy
        ld l,a
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
        ld hl,bld_cut                   ; rows from bld_cut down are hidden by
        cp (hl)                         ; nearer buildings, drawn after this
        ret nc                          ; one (occlusion): none to fill
        ld a,(hl)
        dec a
        cp d
        jr c,.cut                       ; the last row to fill: the lower of
        ld a,d                          ; the face's and bld_cut-1
.cut:   ld (fy1),a

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
        jr z,.vert                      ; vertical (every wall in level flight)
        jr c,.neg
        cp c
        jr nc,.pdv
        ld ixl,a                        ; steep: q = 0, r = dx
        call .setup
        jr .p0s
.pdv:   call div8                       ; E = q, A = r
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.p0s
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
; (no x step: the accumulator kept in A and the remainder in E, not IXL)
.p0s:   ld a,e
        ld e,ixl
.p0:    ld (hl),d
        inc l
        add a,e
        jr nc,.p01
        add a,c
        inc d
.p01:   djnz .p0
        ret

.neg:   neg
        cp c
        jr nc,.ndv
        ld ixl,a
        call .setup
        jr .n0s
.ndv:   call div8
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.n0s
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
.n0s:   ld a,e
        ld e,ixl
.n0:    ld (hl),d
        inc l
        add a,e
        jr nc,.n01
        add a,c
        dec d
.n01:   djnz .n0
        ret

; A vertical edge: the same x on every row (as the steep walk gives it with
; no x step: exactly)
.vert:  ld b,c
        inc b                           ; dy+1 rows
.vl:    ld (hl),d
        inc l
        djnz .vl
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
; buffer (see push_blk), jumping into an unrolled block of PUSH DE.  Spans of
; DMA_SPAN_MIN pixels or more are written by the zxnDMA, which only needs its
; length and destination reloaded (see clear_screen).
; For speed: the stack pointer is kept in IY (ld sp,iy), the rows are
; counted down in IXH, and the table that is the left edge at the polygon's
; middle row is read first, so the left / right swap (still made whenever
; it's needed: a sliver's edges can cross) is mostly skipped.
;==============================================================================
fill_spans:
        ld a,(fy0)
        call seg_map                    ; first row's section into slot 0
        ld iy,0
        add iy,sp                       ; the stack, for push_end
        ld a,(fy0)
        ld b,a
        ld a,(fy1)
        sub b
        inc a
        ld ixh,a                        ; rows to fill
        ld a,(fy1)                      ; the middle row: which table is left?
        add a,b
        rra
        ld l,a
        ld h,high TA
        ld a,(hl)
        inc h
        cp (hl)
        ld a,high TA                    ; TA left (or level): TA first
        ld c,$24                        ;   (inc h)
        jr c,.ta
        ld a,high TB                    ; TB left: TB first
        ld c,$25                        ;   (dec h)
.ta:    ld (fs_loop+1),a
        ld a,c
        ld (fs_loop.tb),a

fs_loop:
        ld h,high TA                    ; (patched: the left table first)
        ld l,b
        ld a,(hl)
.tb:    inc h                           ; (patched: inc h, or dec h, the other)
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
        or a
        jp z,push_next                  ; (1 pixel: no PUSHes, so SP isn't
        jr .go                          ; borrowed: see push_blk)
.even:  inc a
.go:    ld l,c
        inc hl                          ; one past right edge (may be $C000)
        ld sp,hl
        ld l,a
        ld a,low push_end - 1           ; (the DI before the last PUSH)
        sub l
        ld l,a
        ld h,high push_end
        jp (hl)
        ASSERT high push_blk == high push_end && low push_end - 1 - 128 == low push_blk

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
        inc b                           ; the next row (as push_next: SP was
        dec ixh                         ; never borrowed here)
        ret z
        ld a,b
        and 31
        jp nz,fs_loop
        jp push_next.sect
        ASSERT high TB == high TA + 1

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
; row, ground below.  The fills are dma_fill's (layer2_cls.asm, resident),
; the l2_fill command block with its destination (port B) and length; the source
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


;==============================================================================
; City traversal - back to front without sorting.
;   For grid-aligned boxes in separate cells, a box can only hide boxes whose
;   cell offsets from the camera cell are larger (or equal) on both axes in
;   the same quadrant.  So: rows from the far edges inwards, and within each
;   row columns from the far edges inwards, the camera row/column last.
;==============================================================================
draw_city:
        call walk_patch                 ; this frame's cell steps
        call row_cull                   ; and the rows wholly out of view
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
        ld a,VIEW_H
        ld (bld_cut),a                  ; (and nothing cut)
    ENDIF
draw_cells:
        ld a,(cz)
        ld hl,view_r
        sub (hl)
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
        ld hl,view_r
        add a,(hl)
        ld (cell_j),a
.f2:    ld a,(cell_j)
        ld hl,cz
        cp (hl)
        jr z,draw_row                   ; camera row last
        call draw_row
        ld hl,cell_j
        dec (hl)
        jr .f2

; The cell walks (draw_row here, occ_row in city2.asm) keep the cell's
; yaw-space centre (X, Z1) in the alternate registers HL', DE' (nothing else
; uses the alternate set, the interrupt routine included), and step it one
; cell at a time by (cosY, sinY), patched into the steps each frame
; (walk_patch).  draw_bld reads it from there.
draw_row:
        ld a,(cell_j)
        cp GRID
        ret nc
        ld hl,cz                        ; a row wholly out of view (row_cull):
        sub (hl)                        ; nothing in it to try
        ld hl,view_r
        add a,(hl)
        ld hl,row_skip
        add hl,a
        ld a,(hl)
        or a
        ret nz
        ld a,(cell_j)
        call row_base
        ld a,(cx)
        ld hl,view_r
        sub (hl)
        ld (cell_i),a
        call row_start
.l:     ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jr z,.r
        WALK_TRY
        ld hl,cell_i
        inc (hl)
        exx                             ; one cell +x: (X,Z1) += (cosY,sinY)
.cp:    ld bc,0                         ; (cosY: walk_patch)
        add hl,bc
        ex de,hl
.sp:    ld bc,0                         ; (sinY)
        add hl,bc
        ex de,hl
        exx
        jr .l
.r:     ld a,(cx)
        ld hl,view_r
        add a,(hl)
        ld (cell_i),a
        call row_start
.r2:    ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jp z,try_cell                   ; camera column last
        WALK_TRY
        ld hl,cell_i
        dec (hl)
        exx                             ; one cell -x
.cm:    ld bc,0                         ; (cosY)
        or a
        sbc hl,bc
        ex de,hl
.sm:    ld bc,0                         ; (sinY)
        or a
        sbc hl,bc
        ex de,hl
        exx
        jr .r2

; The rows the cell walks can skip this frame: row_skip[j - cz + view_r] not
; 0 if every cell in row j would be skipped by WALK_TRY.  Its tests are
; linear along a row (X and Z1 are), so a row is out if both its end cells
; (cx -/+ view_r, the walk's starts) are past the same edge: right, X - Z1 >=
; WALK_R; left, -X - Z1 >= WALK_R; behind, -Z1 >= WALK_R (pitched: only
; behind, as WALK_TRY).  So the camera column's cell, which the walks try
; without WALK_TRY, is out too.  X = dx cosY - dz sinY, Z1 = dx sinY + dz
; cosY, by fmul as row_start's rot_yaw, the dz terms stepped by sinY and
; cosY a row (fmul(256, f) is f exactly); ROW_M covers the rounding (each
; of these and the walk's own within 2).
ROW_M           equ 8
row_cull:
        ld hl,16383                     ; (|v| < 16384: rc_min's v - word fits)
        ld (rc_m),hl
        ld (rc_m+2),hl
        ld (rc_m+4),hl
        ld a,(view_r)
        ld b,a
        ld a,(cx)
        sub b
        call rc_end                     ; the left end, cell cx - R
        ld a,(view_r)
        ld b,a
        ld a,(cx)
        add a,b
        call rc_end                     ; the right end, cx + R
        ; the first row, cz - R: s = dz sinY, r = dz cosY
        ld a,(view_r)
        ld b,a
        ld a,(cz)
        sub b
        ld h,a
        ld l,128
        ld de,(cam_z+1)
        or a
        sbc hl,de                       ; dz
        push hl
        ld de,(sin_y)
        call fmul
        ld (rc_s),hl
        pop hl
        ld de,(cos_y)
        call fmul                       ; r
        ; d = t - (WALK_R + ROW_M - m) for each edge, t its row part:
        ; right t = -(s + r), left t = s - r, behind t = -r
        push hl
        call neg_hl
        ld de,(rc_s)
        or a
        sbc hl,de
        ld de,(rc_m)
        call rc_d
        ld (rc_d0),hl                   ; right
        pop de
        push de
        ld hl,(rc_s)
        or a
        sbc hl,de
        ld de,(rc_m+2)
        call rc_d
        ld (rc_d0+2),hl                 ; left
        pop hl
        call neg_hl
        ld de,(rc_m+4)
        call rc_d
        ld (rc_d0+4),hl                 ; behind
        ; each row on: right - (sinY + cosY), left + (sinY - cosY), behind
        ; - cosY
        ld hl,(sin_y)
        ld de,(cos_y)
        add hl,de
        call neg_hl
        ld (rc_st),hl
        ld hl,(sin_y)
        or a
        sbc hl,de
        ld (rc_st+2),hl
        ex de,hl
        call neg_hl
        ld (rc_st+4),hl
        ld a,(pitch)
        ld c,a                          ; 0: level, all three edges
        ld a,(view_r)
        add a,a
        inc a
        ld b,a                          ; 2R + 1 rows
        push ix
        ld ix,row_skip
.row:   xor a
        ld hl,rc_d0+5
        bit 7,(hl)
        jr z,.out                       ; behind
        inc c
        dec c
        jr nz,.in                       ; pitched: behind only
        ld hl,rc_d0+1
        bit 7,(hl)
        jr z,.out                       ; right
        ld hl,rc_d0+3
        bit 7,(hl)
        jr nz,.in                       ; left
.out:   inc a
.in:    ld (ix+0),a
        inc ix
        ld hl,(rc_d0)
        ld de,(rc_st)
        add hl,de
        ld (rc_d0),hl
        ld hl,(rc_d0+2)
        ld de,(rc_st+2)
        add hl,de
        ld (rc_d0+2),hl
        ld hl,(rc_d0+4)
        ld de,(rc_st+4)
        add hl,de
        ld (rc_d0+4),hl
        djnz .row
        pop ix
        ret
        ASSERT WALK_R + ROW_M < 16384   ; (no overflow in the d's)

; A = an end cell's i: p = dx cosY, q = dx sinY; rc_m's minimums of each
; edge's end part: right p - q, left -(p + q), behind -q
rc_end:
        ld h,a
        ld l,128
        ld de,(cam_x+1)
        or a
        sbc hl,de                       ; dx
        push hl
        ld de,(cos_y)
        call fmul
        ld (rc_s),hl                    ; p (rc_s: scratch until the row)
        pop hl
        ld de,(sin_y)
        call fmul                       ; q
        push hl
        ex de,hl
        ld hl,(rc_s)
        or a
        sbc hl,de
        ld de,rc_m
        call rc_min                     ; right: p - q
        pop de
        push de
        ld hl,(rc_s)
        add hl,de
        call neg_hl
        ld de,rc_m+2
        call rc_min                     ; left: -(p + q)
        pop hl
        call neg_hl
        ld de,rc_m+4
                                        ; behind: -q
; HL = v, DE -> a word: the word = min(word, v), signed (|v| < 16384)
rc_min:
        push hl
        ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = the word, HL -> its high byte
        ex (sp),hl                      ; HL = v
        push hl
        or a
        sbc hl,de                       ; v - word (no overflow)
        pop de                          ; DE = v
        pop hl                          ; HL -> the high byte
        ret p                           ; v >= word
        ld (hl),d
        dec hl
        ld (hl),e
        ret

; HL = t, DE = m -> HL = t - (WALK_R + ROW_M - m) = t + m - WALK_R - ROW_M
rc_d:
        add hl,de
        ld de,-(WALK_R+ROW_M)
        add hl,de
        ret

; This frame's (cosY, sinY) into the cell walks' steps (draw_row, occ_row)
walk_patch:
        ld hl,(cos_y)
        ld (draw_row.cp+1),hl
        ld (draw_row.cm+1),hl
    IFDEF OCCLUSION_CULL
        ld (occ_row.cp+1),hl
        ld (occ_row.cm+1),hl
    ENDIF
        ld hl,(sin_y)
        ld (draw_row.sp+1),hl
        ld (draw_row.sm+1),hl
    IFDEF OCCLUSION_CULL
        ld (occ_row.sp+1),hl
        ld (occ_row.sm+1),hl
    ENDIF
        ret

; A = cell_j: its row's first city_map byte (city_map + j * GRID) -> cell_row
row_base:
        ld l,a
        ld h,0
        ROWOFS
        ld de,city_map
        add hl,de
        ld (cell_row),hl
        ret

; HL = v, A = k -> HL = v * k, modulo 65536: exactly v added k times (k
; small, its product with each byte of v at most 16 bits).  Keeps BC.
kmul:
        ld e,a
        ld d,l
        mul d,e                         ; low byte * k
        push de
        ld d,h
        ld e,a
        mul d,e                         ; high byte * k: its low byte counts
        ld a,e
        pop hl
        add a,h
        ld h,a
        ret

; Yaw-rotated centre of cell (cell_i, cell_j) -> (X, Z1) in HL', DE' (the
; cell walks').  Moving one cell (256 units) in x then changes (X, Z1) by
; exactly the raw (cosY, sinY).
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
        push hl                         ; X
        ld hl,(t_z1)
        push hl                         ; Z1
        exx
        pop de
        pop hl
        exx
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
        ld hl,(cell_row)                ; (the row's first map byte: row_base)
        ld a,(cell_i)
        add hl,a
        ld a,(hl)
        ld c,a
        and CELL_CODE
        jr nz,.nst
        ; street: the zombies and humans standing there (bits 7, 6)
        ld a,c
        and CELL_ZOMBIE|CELL_HUMAN
        ret z                           ; nobody
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
.nst:   cp VOID_CODE
        ret z                           ; out of bounds: never drawn
.bld:   ld a,c                          ; humans on the roof, monsters
        and CELL_ZOMBIE|CELL_HUMAN      ; (ghosts) above it?
        jr z,draw_bld                   ; nobody
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a
        jr z,.hdraw
        push bc
        push hl
        call occ_human                  ; listed before the building, so
        pop hl                          ; drawn after it
        push hl
        call occ_zombie
        pop hl
        pop bc
        jr draw_bld
.hdraw:
    ENDIF
        push hl
        call draw_bld                   ; the building, then the ghosts
        pop hl                          ; above it and the humans on its
        push hl                         ; roof
        call zombie_cell
        pop hl
        jp human_cell

; The building in the cell at HL (C = its map byte)
BLD_R           equ 256             ; cull radius: 181 (half diagonal) * sqrt2
        ASSERT WALK_R >= BLD_R          ; (the walk's cull: WALK_TRY)
draw_bld:
        ; Horizontal frustum cull, valid at any pitch: a visible point has
        ; |X|*c <= Z1 with c = cosP - 0.5|sinP|.  Reject the bounding circle
        ; (radius BLD_R) round the cell's yaw-space centre (X, Z1, kept up
        ; to date in HL', DE' by the walk).  First, as it needs nothing else:
        ; most cells it rejects then cost no more.  (Level flight: c is
        ; exactly 1.0, so no multiply.)
        push hl
        push bc
        exx                             ; the walk's (X, Z1): HL', DE'
        ld (t_z1),de
        ld (t_x),hl
        push hl
        exx
        pop hl
        call abs_hl
        ld a,(pitch)
        or a
        jr z,.cl
        ld de,(cull_c)
        call fmul
.cl:    ld de,(t_z1)
        or a
        sbc hl,de
        ld de,BLD_R
        or a
        sbc hl,de
        pop bc
        pop hl
        ret p                           ; wholly outside: nothing to draw
        ld de,city_col-city_map         ; same index in city_col (city bank)
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

        ; (the frustum test was first: t_x, t_z1 hold the cell's centre)
    IFDEF OCCLUSION_CULL
        ld a,(occ_on)
        or a                            ; (carry clear)
        call nz,occ_pretest
        ret c                           ; surely hidden: skip the transform
    ENDIF
        ; centre -> corner (x0,z0), still in yaw space (vecs0: the frame's
        ; edge vectors and corner offset, make_vecs)
        ld hl,(vecs0+12)
        ld de,(t_x)
        add hl,de
        ld (vtx+0),hl
        ld hl,(vecs0+14)
        ld de,(t_z1)
        add hl,de
        ld (t_z1),hl
        call rot_pitch
        ld (vtx+2),hl
        ld (vtx+4),de

        ; vertical edge vector (0, h cosP, h sinP); level flight: (0, h, 0)
        ; exactly (cosP 1.0, sinP 0), no multiplies
        ld hl,(bld_h)
        ld a,(pitch)
        or a
        jr nz,.vyp
        ld (vy_vec+2),hl
        ld (vy_vec+4),a                 ; (A = 0)
        ld (vy_vec+5),a
        jr .vyd
.vyp:   ld de,(cos_p)
        call fmul
        ld (vy_vec+2),hl
        ld hl,(bld_h)
        ld de,(sin_p)
        call fmul
        ld (vy_vec+4),hl
.vyd:

        ; vertices: index = x + 2*z + 4*top  (box edges are shared vectors)
        VBOX0 0                         ; X (vy's X is 0)
        VBOX 2                          ; Y
        ld a,(pitch)
        or a
        jr nz,.vbz
        VBOX0 4                         ; Z: level flight, vy's Z is 0
        jr .vbd
.vbz:   VBOX 4
.vbd:

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
        call z,vproj
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
        ; it shares its screen x; only the screen y is new.
        call vproj_y
        jr .nt
.full:
    ENDIF
        call vproj
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

; IX -> a building corner whose outcode is 0 -> its screen x and y in (ix+7)
; and (ix+8).  The same arithmetic as vtx_proj (project, zpatch and
; scale_comp, step for step), so the same pixels, in one routine: Z's shift
; chosen by a branch (three ways) rather than patched in, X and Y made
; positive and shifted as they're read, the reciprocal kept in BC for both,
; no calls or self-patching.  Outcode 0 means Z >= NEAR (so not zpatch's
; Z <= 0 guard), |X| <= Z and |Y| <= Z/2.  Leaves scale_comp as it was.
vproj:
        ld l,(ix+4)
        ld h,(ix+5)                     ; HL = Z
        ld a,h
        cp 2
        jr nc,.zr
        or a
        jr z,.zl
        ; Z 256..511: no shift (zpatch's right by 0)
        ld e,(ix+2)
        ld d,(ix+3)                     ; Y
        bit 7,d
        jr z,.ny
        NEG_DE
.ny:    push de
        ld e,(ix+0)
        ld d,(ix+1)                     ; X
        bit 7,d
        jr z,vp_xy
        NEG_DE
        jr vp_xy
.zr:    ld e,a                          ; Z >= 512: right by log2(H)
        ld d,high lgtab
        ld a,(de)
        ld b,a
        ex de,hl
        bsrl de,b
        ex de,hl                        ; L = Zn - 256
        ld e,(ix+2)
        ld d,(ix+3)
        bit 7,d
        jr z,.ry
        NEG_DE
.ry:    bsrl de,b
        push de
        ld e,(ix+0)
        ld d,(ix+1)
        bit 7,d
        jr z,.rx
        NEG_DE
.rx:    bsrl de,b
        jr vp_xy
.zl:    ld e,l                          ; Z < 256: left by 8-log2(L)
        ld d,high lgtab
        ld a,(de)
        sub 8
        neg
        ld b,a
        ex de,hl
        bsla de,b
        ex de,hl
        ld e,(ix+2)
        ld d,(ix+3)
        bit 7,d
        jr z,.ly
        NEG_DE
.ly:    bsla de,b
        push de
        ld e,(ix+0)
        ld d,(ix+1)
        bit 7,d
        jr z,.lx
        NEG_DE
.lx:    bsla de,b
        ; fall through
; DE = |X| and the stack |Y|, both shifted as Z; L = Zn - 256
vp_xy:  ld h,high rtab_lo
        ld c,(hl)
        inc h
        ld b,(hl)                       ; BC = R, the reciprocal
        ex de,hl
        VP_SCALE                        ; A = round(|X| * 128 / Z)
        bit 7,(ix+1)
        jr nz,.xn
        add a,128
        jr nc,.xd
        ld a,255
        jr .xd
.xn:    ld e,a
        ld a,128
        sub e
        jr nc,.xd
        xor a
.xd:    ld (ix+7),a
        pop hl
        ; fall through
; HL = |Y| shifted as Z, BC = R -> the screen y in (ix+8)
vp_y:   VP_SCALE                        ; A = round(|Y| * 128 / Z)
        bit 7,(ix+3)
        jr nz,.yn
        ld e,a
        ld a,VIEW_CY
        sub e
        jr nc,.yd
        xor a
        ld (ix+8),a
        ret
.yn:    add a,VIEW_CY
        jr c,.yc
        cp VIEW_H
        jr c,.yd
.yc:    ld a,VIEW_H-1
.yd:    ld (ix+8),a
        ret

; IX -> a top corner straight above the one at IX-64, already projected
; (level flight: the same X and Z) -> its screen x copied, its screen y
; worked out as vproj's
vproj_y:
        ld a,(ix+7-64)
        ld (ix+7),a
        ld l,(ix+4)
        ld h,(ix+5)                     ; HL = Z
        ld e,(ix+2)
        ld d,(ix+3)                     ; Y
        bit 7,d
        jr z,.p
        NEG_DE
.p:     ld a,h
        cp 2
        jr nc,.r
        or a
        jr nz,.y                        ; 256..511: no shift
        push de
        ld e,l                          ; < 256: left
        ld d,high lgtab
        ld a,(de)
        sub 8
        neg
        ld b,a
        ex de,hl
        bsla de,b
        ex de,hl
        pop de
        bsla de,b
        jr .y
.r:     push de                         ; >= 512: right
        ld e,a
        ld d,high lgtab
        ld a,(de)
        ld b,a
        ex de,hl
        bsrl de,b
        ex de,hl
        pop de
        bsrl de,b
.y:     ld h,high rtab_lo               ; L = Zn - 256
        ld c,(hl)
        inc h
        ld b,(hl)
        ex de,hl
        jp vp_y
        ASSERT high rtab_hi == high rtab_lo + 1

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
        and CELL_CODE
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
; (Level flight: sinP 0 and cosP 1.0 exactly, so Y = yb, Z = zb + Z1.)
rot_pitch:
        ld a,(pitch)
        or a
        jr nz,.p
        ld hl,(t_z1)
        ld de,(zb)
        add hl,de
        ex de,hl
        ld hl,(yb)
        ret
.p:     ld hl,(t_z1)
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
; City page data
;==============================================================================
; Faces as vertex offsets (index*16); vertex index = x + 2*z + 4*top.
; Side faces list bottom edge first, then the z1/x1 vertical, top, z0/x0.
face_nx:  db 0*16,2*16,6*16,4*16
face_px:  db 1*16,3*16,7*16,5*16
face_nz:  db 0*16,1*16,5*16,4*16
face_pz:  db 2*16,3*16,7*16,6*16
face_top: db 4*16,5*16,7*16,6*16
; The same, for corners in a page's upper half (an odd occlusion record,
; at +128): draw_face adds face_set (0, or FACE_SET2) to the list address
face_hi:  db 128+0*16,128+2*16,128+6*16,128+4*16
          db 128+1*16,128+3*16,128+7*16,128+5*16
          db 128+0*16,128+1*16,128+5*16,128+4*16
          db 128+2*16,128+3*16,128+7*16,128+6*16
          db 128+4*16,128+5*16,128+7*16,128+6*16
FACE_SET2       equ face_hi - face_nx
        ASSERT face_px == face_nx+4 && face_nz == face_nx+8 && face_pz == face_nx+12
        ASSERT face_top == face_nx+16 && FACE_SET2 == 20
face_set:   db 0                        ; 0: corners at offsets 0-127 (vtx, an
                                        ; even record), FACE_SET2: 128-255

; --- building / view work areas ---
vy_vec:     dw 0,0,0                    ; (its X: always 0, VBOX0)
cell_i:     db 0
cell_j:     db 0
bld_h:      dw 0
bld_wall:   db 0                        ; 1: perimeter wall cell (SKY_IS_WALL)
bld_col:    db 0
face_col:   db 0
bld_x0:     dw 0
bld_x1:     dw 0
bld_z0:     dw 0
bld_z1:     dw 0
t_dx:       dw 0
t_dz:       dw 0
t_z1:       dw 0
t_x:        dw 0
cell_row:   dw 0                        ; city_map + cell_j * GRID (row_base)
bld_used:   db 0
vtx_hi:     db high vtx                 ; corners draw_face reads (vtx or a record)
bld_used0:  db 0                        ; corners of drawn faces (unrotated)
    IFDEF OCCLUSION_CULL
occ_on:     db 0                        ; 1: recording (level flight)
occ_full:   db 0                        ; 1: ran out of records this frame
occ_lp:     dw 0                        ; end of the draw list
occ_rp:     dw 0                        ; next free record (its address)
o_used:     db 0
o_xmin:     db 0
o_xmax:     db 0
o_ymin:     db 0
o_tcov:     db 0
    IFDEF OCC_PITCHED
o_bx0:      db 0                        ; occ_record, pitched: the bottom
o_bx1:      db 0                        ;   corners' first and last column,
o_tx0:      db 0                        ;   and the top corners'
o_tx1:      db 0
    ENDIF
o_zmin:     dw 0
o_zmax:     dw 0                        ; occ_pretest's far Z (oz_far)
    IFDEF OCC_PITCHED
o_ytop:     dw 0                        ; pitched: the most Y,
o_kc:       dw 0                        ;   2R cosP and min(0, 2R sinP)
o_ks:       dw 0                        ;   (occ_begin)
    ENDIF
oz_min:     ds 4                        ; occ_pretest: the near and far Z's
oz_max:     ds 4                        ;   shift and reciprocal (oz_norm),
oz_maxok:   db 0                        ;   the far one's set yet
row_skip:   ds 2*VIEW_R+1               ; row_cull: the rows wholly out of view
rc_m:       ds 6                        ;   each edge's end minimum,
rc_d0:      ds 6                        ;   the row's distance past it,
rc_st:      ds 6                        ;   its step a row,
rc_s:       dw 0                        ;   and scratch
    ENDIF
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
tmpv:       ds 8

; --- clipping (and the variables after p2buf) ---
bld_vis:    db 0                        ; bld_vis .. col_top: kept together
bld_mx:     db 0                        ; (occlusion records copy them)
bld_mz:     db 0
col_x:      db 0
col_z:      db 0
col_top:    db 0
bld_cut:    db VIEW_H                   ; rows from here down hidden by nearer
                                        ; buildings (VIEW_H: none; occlusion)
clipB:      ds 8*12

; --- polygon / line / clear ---

