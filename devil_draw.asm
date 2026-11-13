;==============================================================================
; Z-POLICE - drawing the devil, the final boss (devil.asm), and its
; lightning: part of the second city page (city2.asm includes it), with the
; city page in slot 7, the zombie page in slot 1 and Layer 2 through slot 0
;
; The devil is far bigger than the figures' graphics go (GFX_MAX_H rows), so
; it is scaled as it is drawn, from its DEVIL_W x DEVIL_SRC_H frame (one 8K
; page each, the devil's graphics from the kept figures' pages on:
; devil_load), mapped at $C000 in slot 6:
;   * its feet, its head (DEVIL_H above them) and the ground under it are
;     projected one by one (16 bits: it can be many times the view's height
;     close to);
;   * its width is DV_WU at its feet's distance;
;   * each screen column in view gets its frame column (mirrored for facing
;     right) in four tables, DV_CTAB, one for each of the four frame rows a
;     256-byte step holds (+0, +64, +128, +192: a row is 64 bytes);
;   * each screen row in view, from its top down to its feet or the ground,
;     whichever is higher (it sinks into the ground killed), is its frame row,
;     the pixels through the table for that row's step: 0 transparent.
; Where it was drawn is noted for the missile lock (+31..+33, as fig_seen)
; and its eyes' place for the lightning (dv_seen, dv_ex, dv_ey).
;==============================================================================

DV_ZMIN         equ 48              ; its feet nearer than this (Z): not drawn
DV_FAR          equ 16000           ; a row far off the view (sums stay in 16 bits)
        ASSERT DEVIL_H*2*128/DV_ZMIN + DV_FAR < 32768
DV_WU           equ DEVIL_H*DEVIL_W/DEVIL_SRC_H     ; its width (world units)
DV_EYE_ROW      equ 20              ; its eyes' row in its frame
BOLT_SEGS       equ 8               ; the lightning: lines from its eyes
BOLT_JIT        equ 16              ;   to the VTOL, the points between
                                    ;   jittered up to half this either way
        ASSERT DEVIL_W == 64 && DEVIL_SRC_H == 128

; Draw devil IX (zombie_draw jumps here; preserves IX)
devil_draw:
        ld a,(devil_gfx)
        or a
        ret z                           ; (its graphics aren't in yet)
        push ix
        push iy
    IFDEF REAL_HARDWARE
        ld a,OCC_MMU                    ; its work page in slot 2 (the line, the
        call read_nextreg               ; column tables), over the occlusion
        ld (dv_occ),a                   ; page (it doesn't use it): put back
        ld a,(gfx_keep)                 ; after
        add a,PAGE_GFX0+DEVIL_FRAMES
        ld (dv_wpg),a
        nextreg OCC_MMU,a
        xor a
        ld (dv_run),a                   ; (no rows waiting for a copy)
        ld (dv_dma1),a
        dec a
        ld (dv_lsr),a
    ENDIF
        call dv_draw
    IFDEF REAL_HARDWARE
        call dv_flush                   ; (the last rows)
        ld a,(dv_occ)                   ; slot 2 as the drawing had it
        nextreg OCC_MMU,a
        call span_arm                   ; (the DMA as the faces' spans want it)
    ENDIF
        pop iy
        pop ix
        ret

dv_draw:
        ld l,(ix+0)                     ; from the camera
        ld h,(ix+1)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw                    ; (city.asm) HL = X
        ld (dv_X),hl
        call rot_pitch                  ; the ground under it: Y, Z
        ld (dv_Yg),hl
        ld (dv_Zg),de
        ld l,(ix+21)                    ; its feet: + their height (cosP,
        ld h,(ix+22)                    ; sinP), below the ground sinking
        push hl
        ld de,(cos_p)
        call fmul
        ld de,(dv_Yg)
        add hl,de
        ld (dv_Yf),hl
        pop hl
        ld de,(sin_p)
        call fmul
        ld de,(dv_Zg)
        add hl,de
        ld (dv_Zf),hl
        ld hl,DEVIL_H                   ; its head: DEVIL_H above them
        ld de,(cos_p)
        call fmul
        ld de,(dv_Yf)
        add hl,de
        ld (dv_Yh),hl
        ld hl,DEVIL_H
        ld de,(sin_p)
        call fmul
        ld de,(dv_Zf)
        add hl,de
        ld (dv_Zh),hl
        ld hl,(dv_Zf)                   ; far enough in front?
        ld de,-DV_ZMIN
        add hl,de
        bit 7,h
        ret nz
        ; its width, and its columns
        ld hl,DV_WU
        ld de,(dv_Zf)
        call dv128
        ld a,b
        or c
        ret z
        ld (dv_w),bc
        ld hl,(dv_X)                    ; its middle: 128 + 128 X / Z
        ld de,(dv_Zf)
        call dv_proj
        ld de,128
        add hl,de
        ld (dv_sx),hl
        ld de,(dv_w)
        srl d
        rr e
        or a
        sbc hl,de
        ld (dv_left),hl                 ; left = middle - w/2
        ld a,h                          ; off the right?
        or a
        jp p,.lp
        ld hl,0                         ; (left of the view: from column 0)
        jr .c0
.lp:    ret nz                          ; (>= 256)
.c0:    ld (dv_c0),hl
        ld hl,(dv_left)
        ld de,(dv_w)
        add hl,de
        dec hl                          ; its right column
        bit 7,h
        ret nz                          ; left of the view
        ld a,h
        or a
        jr z,.rc
        ld hl,255                       ; (past the right: to column 255)
.rc:    ld de,(dv_c0)
        or a
        sbc hl,de
        ret c
        inc l                           ; columns (256: 0)
        ld a,l
        ld (dv_n),a
        ; its rows: feet, head, the ground
        ld hl,(dv_Yf)
        ld de,(dv_Zf)
        call dv_row
        ld (dv_bot),hl
        ld hl,(dv_Zh)                   ; (its head behind the near plane:
        ld de,-DV_ZMIN                  ; above the view)
        add hl,de
        bit 7,h
        ld hl,-DV_FAR
        jr nz,.th
        ld hl,(dv_Yh)
        ld de,(dv_Zh)
        call dv_row
.th:    ld (dv_top),hl
        ld hl,(dv_Zg)                   ; (the ground under the near plane:
        ld de,-DV_ZMIN                  ; no edge)
        add hl,de
        bit 7,h
        ld hl,DV_FAR
        jr nz,.gr
        ld hl,(dv_Yg)
        ld de,(dv_Zg)
        call dv_row
.gr:    ld (dv_gnd),hl
        ld hl,(dv_bot)                  ; its height on the screen
        ld de,(dv_top)
        or a
        sbc hl,de
        inc hl
        ld (dv_hh),hl
    IFDEF REAL_HARDWARE
        ld de,DV_DMA_H                  ; tall enough that rows repeat: DMA+
        or a                            ; (dv_line, dv_flush); else the CPU
        sbc hl,de
        ld a,0
        jr c,.vd
        inc a
.vd:    ld (dv_viadma),a
        ld hl,(dv_hh)
    ENDIF
        ld de,3                         ; (under 3 rows: not drawn)
        or a
        sbc hl,de
        ret m
        ; seen (the missile lock): its middle column and row, in the view
        ld (ix+31),1
        ld hl,(dv_sx)
        call dv_clamp_x
        ld (ix+32),a
        ld (dv_ex),a                    ; (and its eyes', for the lightning)
        ld hl,(dv_top)
        ld de,(dv_bot)
        add hl,de
        sra h
        rr l
        call dv_clamp_y
        ld (ix+33),a
        ld hl,(dv_hh)                   ; its eyes: DV_EYE_ROW of its rows
        ld de,DV_EYE_ROW*256/DEVIL_SRC_H
        call dv_mulhi
        ld de,(dv_top)
        add hl,de
        call dv_clamp_y
        ld (dv_ey),a
        ld a,1
        ld (dv_seen),a
        ; the rows in view: from max(0, top) to min(VIEW_H-1, feet, ground)
        ld hl,(dv_top)
        bit 7,h
        jr z,.r0
        ld hl,0
.r0:    ld a,h
        or a
        ret nz                          ; (below the view)
        ld a,l
        cp VIEW_H
        ret nc
        ld (dv_y),a
        ld hl,(dv_bot)
        ld de,(dv_gnd)
        call dv_min
        ld de,VIEW_H-1
        call dv_min
        bit 7,h
        ret nz                          ; above the view
        ld a,(dv_y)
        cp l
        jr z,.r1
        ret nc                          ; (none)
.r1:    ld a,l
        ld (dv_r1),a
        ; its frame: facing (as a zombie's: face_tab), its legs
        ld a,(ix+4)
        rrca
        rrca
        ld hl,yaw
        sub (hl)
        add a,32
        rlca
        rlca
        and 3
        ld hl,face_tab                  ; (zombie.asm)
        add hl,a
        ld c,(hl)                       ; front 0, side 1, rear 2; bit 7 mirrored
        ld a,c
        and $80
        ld (dv_mir),a
        ld a,c
        and 3
        add a,a
        ld b,a
        ld a,(ix+5)
        and 1
        add a,b
        ld (dv_fr),a                    ; (its opaque columns: dv_ext)
        ld hl,gfx_keep
        add a,(hl)
        add a,PAGE_GFX0
        nextreg LOGIC_MMU,a             ; at $C000
        ASSERT DEVIL_FRAMES_EACH == 2
        ; the column tables: frame column (x - left) * 64 / w, from c0
        ld hl,(dv_c0)
        ld de,(dv_left)
        or a
        sbc hl,de
        ld de,(dv_w)
        ex de,hl
        add hl,hl
        ld (dv_w2),hl                   ; (2w: * 128 / 2w is * 64 / w)
        ex de,hl
        call dv128
        ld (dv_rr),hl
        ld a,c
        ld (dv_q),a
        ld a,(dv_c0)
        ld l,a
        ld h,high dv_ctab
        ld a,(dv_n)
        ld b,a
.ct:    ld a,(dv_q)
        cp DEVIL_W
        jr c,.cq
        ld a,DEVIL_W-1
.cq:    ld c,a
        ld a,(dv_mir)
        or a
        ld a,c
        jr z,.cm
        ld a,DEVIL_W-1
        sub c
.cm:    ld (hl),a                       ; its four tables
        inc h
        add a,DEVIL_W
        ld (hl),a
        inc h
        add a,DEVIL_W
        ld (hl),a
        inc h
        add a,DEVIL_W
        ld (hl),a
        dec h
        dec h
        dec h
        push hl
        ld hl,(dv_rr)                   ; the next column's
        ld de,128
        add hl,de
        ld de,(dv_w2)
.cs:    or a
        sbc hl,de
        jr c,.cd
        ld a,(dv_q)
        inc a
        ld (dv_q),a
        jr .cs
.cd:    add hl,de
        ld (dv_rr),hl
        pop hl
        inc l
        djnz .ct
        ; the first row's frame row: (y - top) * 128 / hh
        ld a,(dv_y)
        ld l,a
        ld h,0
        ld de,(dv_top)
        or a
        sbc hl,de
        ld de,(dv_hh)
        call dv128
        ld (dv_rr),hl
        ld a,c
        cp DEVIL_SRC_H
        jr c,.sr
        ld a,DEVIL_SRC_H-1
.sr:    ld (dv_sr),a
        ld hl,(dv_c0)                   ; the last column in view, + 1
        ld a,(dv_n)
        dec a
        add hl,a
        inc hl
        ld (dv_c1),hl
        ; each frame column's first screen column, left + ceil(q * w / 64),
        ; kept to the view (c0 .. c1+1): dv_xq, q = 0..64
        ld hl,0
        ld (dv_acc),hl                  ; q * w
        ld hl,dv_xq
        ld b,DEVIL_W+1
.xq:    push bc
        push hl
        ld hl,(dv_acc)
        ld de,(dv_w)
        push hl
        add hl,de
        ld (dv_acc),hl                  ; (the next q's)
        pop hl
        ld de,DEVIL_W-1
        add hl,de
        ex de,hl
        ld b,6
        bsrl de,b                       ; / 64, up
        ld hl,(dv_left)
        add hl,de
        ld de,(dv_c0)
        call dv_max
        ld de,(dv_c1)
        call dv_min
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        pop bc
        djnz .xq
        ; each row: only from its frame row's first opaque pixel to its last
        ; (dv_ext), in view
.row:   ld a,(dv_fr)
        add a,high dv_ext
        ld h,a
        ld a,(dv_sr)
        add a,a
        ld l,a
        ld e,(hl)                       ; first ($FF: none)
        inc l
        ld d,(hl)                       ; last
        ld a,e
        inc a
        jp z,.eol                       ; (an empty row)
        ld a,(dv_mir)
        or a
        jr z,.q
        ld a,DEVIL_W-1                  ; (mirrored: the other way round)
        sub d
        ld c,a
        ld a,DEVIL_W-1
        sub e
        ld d,a
        ld e,c
.q:     ld a,e                          ; its first screen column, in view
        add a,a
        ld hl,dv_xq
        add hl,a
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld (dv_x0),bc
        ld a,d                          ; and the next frame column's
        inc a
        add a,a
        ld hl,dv_xq
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,bc
        jp z,.eol                       ; (none in view)
        jp m,.eol
        ld (dv_cnt),hl                  ; pixels, 1..256
    IFDEF REAL_HARDWARE
        ; DMA+: each frame row drawn once, into the line (dv_line); the rows
        ; showing it copied from there, a run at a time (dv_flush)
        ld a,(dv_viadma)
        or a
        jr z,.cpu
        ld a,(dv_sr)                    ; the same frame row as the run's?
        ld hl,dv_lsr
        cp (hl)
        jr nz,.new
        ld a,(dv_run)                   ; one more row of the run (DV_RUN_MAX
        cp DV_RUN_MAX                   ; at most a copy)
        jr nc,.full
        inc a
        ld (dv_run),a
        jp .eol
.full:  call dv_flush                   ; (the line as it is)
        jr .start
.new:   call dv_flush
        call dv_line
.start: ld a,(dv_y)
        ld (dv_ry),a
        ld a,1
        ld (dv_run),a
        jp .eol
.cpu:
    ENDIF
        ld a,(dv_sr)
        ld c,a
        rrca                            ; its 64 bytes at $C000 + sr * 64
        rrca
        and $3F
        add a,high GFX_DIR              ; ($C000)
        ld b,a
        ld a,(dv_y)
        call seg_map                    ; (city.asm) A = y & 31, keeps BC, DE, L
        ld d,a
        ld a,(dv_x0)
        ld e,a
        ld l,a
        ld a,c
        and 3                           ; the table for its step in the page
        add a,high dv_ctab
        ld h,a
        ld a,(dv_cnt)                   ; a lookup a pixel (0: 256)
        call dv_px
.eol:   ld a,(dv_y)                     ; (from jp: within reach of jr)
        ld hl,dv_r1
        cp (hl)
        ret z                           ; its last row
        inc a
        ld (dv_y),a
        ld hl,(dv_rr)                   ; the next row's frame row
        ld de,128
        add hl,de
        ld de,(dv_hh)
.rs:    or a
        sbc hl,de
        jr c,.rd
        ld a,(dv_sr)
        inc a
        ld (dv_sr),a
        jr .rs
.rd:    add hl,de
        ld (dv_rr),hl
        ld a,(dv_sr)
        cp DEVIL_SRC_H
        jp c,.row
        ld a,DEVIL_SRC_H-1
        ld (dv_sr),a
        jp .row

 IFDEF REAL_HARDWARE
; The row's frame row (dv_sr) from column dv_x0, dv_cnt pixels, into the
; line at the same columns: every pixel, 0 where transparent (the copy
; skips them), four to a loop
dv_line:
        ld a,(dv_sr)
        ld (dv_lsr),a
        ld c,a
        ld hl,(dv_x0)
        ld (dv_rx0),hl
        ld hl,(dv_cnt)
        ld (dv_rcnt),hl
        ld a,l
        and 3
        ld ixh,a                        ; the odd ones
        srl h
        rr l
        srl h
        rr l
        ld a,l
        ld ixl,a                        ; the fours (0..64)
        ld a,c
        rrca                            ; its 64 bytes at $C000 + sr * 64
        rrca
        and $3F
        add a,high GFX_DIR
        ld b,a
        ld a,(dv_x0)
        ld e,a
        ld l,a
        ld d,high DV_LINE
        ld a,c
        and 3                           ; the table for its step in the page
        add a,high dv_ctab
        ld h,a
        ld a,ixl
        or a
        jr z,.one
.four:  REPT 4
        ld c,(hl)
        ld a,(bc)
        ld (de),a
        inc e
        inc l
        ENDR
        dec ixl
        jr nz,.four
.one:   ld a,ixh
        or a
        ret z
.o:     ld c,(hl)
        ld a,(bc)
        ld (de),a
        inc e
        inc l
        dec ixh
        jr nz,.o
        ret

; The run of rows waiting (dv_run from row dv_ry): one 2D transparent copy
; of the line (its columns dv_rx0, dv_rcnt of them) to each, both ends by
; physical address (as spr_rect.asm's), the line's stride 0
dv_flush:
        ld a,(dv_run)
        or a
        ret z
        ld (dz_rows),a
        ld (dzs_rows),a
        xor a
        ld (dz_rows+1),a
        ld (dzs_rows+1),a
        ld (dv_run),a
        ld hl,(dv_rcnt)
        ld (dz_len),hl
        ld (dzs_len),hl
        ld a,(dv_wpg)                   ; the line: $40000 + page * $2000 + x
        ld c,a
        and 7
        rrca
        rrca
        rrca
        add a,high (DV_LINE & $1FFF)   ; (its offset in the page)
        ld h,a
        ld a,(dv_rx0)
        ld l,a
        ld (dz_src),hl
        ld (dzs_src),hl
        ld a,c
        rrca
        rrca
        rrca
        and 31
        add a,4
        ld (dz_sext),a
        ld a,(seg_base)                 ; the screen: the buffer being drawn
        ld l,a
        rrca
        rrca
        rrca
        and 31
        add a,4
        ld h,a
        ld a,l
        and 7
        rrca
        rrca
        rrca
        ld l,a
        ld a,(dv_ry)
        add a,l
        jr nc,.nc
        inc h
.nc:    ld (dz_dst+1),a
        ld (dzs_dst+1),a
        ld a,h
        ld (dz_dext),a
        ld (dzs_dext),a
        ld a,(dv_rx0)
        ld (dz_dst),a
        ld (dzs_dst),a
        ld hl,dz_cmds                   ; the first copy of a draw: all of it;
        ld b,DZ_N                       ; then only what changes (the guide's
        ld a,(dv_dma1)                  ; short reload: docs/ZXNDDMA.md)
        or a
        jr z,.all
        ld hl,dz_short
        ld b,DZ_SHORT
.all:   ld a,1
        ld (dv_dma1),a
        ld c,IO_DATAGEAR_DMA_PORT
        otir                            ; (the CPU waits while it copies)
        ret

dz_short:   db DDMA_B_EXT
dzs_dext:   db 0
            db DDMA_ROW_LEN
dzs_len:    dw 0
            db DDMA_ROWS
dzs_rows:   dw 0
            db DMA_WR0_A_ADDR           ; port A's address alone
dzs_src:    dw 0
            db DMA_WR4_CONT_MODE
dzs_dst:    dw 0
            db DMA_LOAD, DMA_ENABLE
DZ_SHORT    equ $ - dz_short
DMA_WR0_A_ADDR equ $1D

dz_cmds:    db DMA_DISABLE, DMA_RESET
            db DDMA_MODE, DDMA_FLAG_PHYS|DDMA_FLAG_2D|DDMA_FLAG_TRANS
            db DDMA_TRANS_COL, 0
            db DDMA_A_EXT
dz_sext:    db 0                        ; the line's address bits 23:16,
            db DDMA_B_EXT
dz_dext:    db 0                        ; the screen's
            db DDMA_ROW_LEN
dz_len:     dw 0                        ; the columns,
            db DDMA_ROWS
dz_rows:    dw 0                        ; the rows,
            db DDMA_A_STRIDE
            dw 0                        ; the same line each row,
            db DDMA_B_STRIDE
            dw 256                      ; the screen's
            db DMA_WRO_BLOCK_PORTA_A2B_XFR
dz_src:     dw 0, 0                     ; port A (the length: not used, 2D)
            db DMA_WR1_P1INC_MEMORY
            db DMA_WR2_P2INC_MEMORY
            db DMA_WR4_CONT_MODE
dz_dst:     dw 0                        ; port B
            db DMA_STOP_AT_END, DMA_LOAD, DMA_ENABLE
DZ_N        equ $ - dz_cmds
DV_RUN_MAX  equ 32                      ; rows a copy at most (8K: the bus, the
                                        ; interrupt; docs/ZXNDDMA.md)
DV_LINE     equ $4000                   ; in its work page (slot 2): the line,
dv_ctab     equ $4100                   ;   the column tables
dv_wpg:     db 0                        ; its work page (after its frames)
dv_run:     db 0                        ; rows waiting for a copy,
dv_dma1:    db 0                        ; 1: a copy sent this draw (short now)
dv_ry:      db 0                        ;   from this one,
dv_lsr:     db 0                        ;   the frame row in the line,
dv_rx0:     dw 0                        ;   its first column,
dv_rcnt:    dw 0                        ;   and how many
dv_occ:     db 0                        ; slot 2's page before
dv_viadma:  db 0                        ; 1: this draw by DMA+
DV_DMA_H    equ 150                     ; (rows tall: the DMA+ way)
    ENDIF

; A pixels (0: 256) of a row, a lookup each: HL -> its column table entry,
; DE -> the screen, B = its frame row's page address (high)
dv_px:  ld ixl,a
.px:    ld c,(hl)                       ; its frame column (+ its row's step)
        ld a,(bc)
        or a
        jr z,.tr                        ; transparent
        ld (de),a
.tr:    inc e
        inc l
        dec ixl
        jr nz,.px
        ret

        ASSERT DEVIL_W == 1<<6 && (DV_WU*128/DV_ZMIN)*DEVIL_W < 65536-DEVIL_W

; HL = max(HL, DE), signed
dv_max:
        push hl
        or a
        sbc hl,de
        pop hl
        jp pe,.ov
        ret p                           ; HL - DE >= 0: HL
        ex de,hl
        ret
.ov:    ret m                           ; (overflowed: the sign the other way)
        ex de,hl
        ret

;------------------------------------------------------------------------------
; Its graphics just loaded (devil_load, with this page mapped in slot 4):
; each frame row's first and last opaque columns (dv_ext; $FF: none), so a
; row is drawn only between them.  Each frame through slot 0.
;------------------------------------------------------------------------------
dv_extents:
        ld b,0                          ; the frame
.fr:    push bc
        ld a,(gfx_keep)
        add a,PAGE_GFX0
        add a,b
        nextreg L2SEC_MMU,a             ; at $0000
        ld a,b
        add a,high dv_ext
        ld d,a
        ld e,0                          ; DE -> its rows' extents
        ld hl,0                         ; its rows, DEVIL_W bytes each
        ld c,DEVIL_SRC_H
.row:   push hl
        ld b,DEVIL_W                    ; the first from the left
.l:     ld a,(hl)
        or a
        jr nz,.lf
        inc hl
        djnz .l
        pop hl                          ; none
        ld a,$FF
        ld (de),a
        inc e
        ld (de),a
        inc e
        jr .nx
.lf:    ld a,DEVIL_W
        sub b
        ld (de),a
        inc e
        pop hl
        push hl
        ld a,l
        add a,DEVIL_W-1
        ld l,a                          ; (rows 64-aligned: no carry)
        ld b,DEVIL_W                    ; the last, from the right
.r:     ld a,(hl)
        or a
        jr nz,.rf
        dec hl
        djnz .r
.rf:    ld a,b
        dec a
        ld (de),a
        inc e
        pop hl
.nx:    ld a,l
        add a,DEVIL_W
        ld l,a
        jr nc,.c
        inc h
.c:     dec c
        jr nz,.row
        pop bc
        inc b
        ld a,b
        cp DEVIL_FRAMES
        jr nz,.fr
        ret
        ASSERT DEVIL_SRC_H*2 == 256

; HL = Y, DE = Z (>= DV_ZMIN) -> HL = its screen row, VIEW_CY - 128 Y / Z
; (signed: off the view either way)
dv_row:
        call dv_proj
        ex de,hl
        ld hl,VIEW_CY
        or a
        sbc hl,de
        ret

; HL (signed), DE (> 0) -> HL = HL * 128 / DE, signed (at most 32767 either
; way)
dv_proj:
        bit 7,h
        jr z,.p
        call neg_hl
        call dv128
        ld h,b
        ld l,c
        jp neg_hl
.p:     call dv128
        ld h,b
        ld l,c
        ret

; HL, DE (1..32767) -> BC = HL * 128 / DE (at most 32767), HL = the
; remainder.  (A 24-bit dividend, restoring division.)
dv128:
        xor a                           ; A:B:C = HL * 128
        ld b,h
        ld c,l
        REPT 7
        sla c
        rl b
        rla
        ENDR
        ld hl,0
        ld iyl,24
.lp:    sla c
        rl b
        rla
        adc hl,hl                       ; (under 65536: carry clear)
        sbc hl,de
        jr nc,.one
        add hl,de
        jr .nx
.one:   inc c
.nx:    dec iyl
        jr nz,.lp
        or a
        jr nz,.sat
        bit 7,b
        ret z
.sat:   ld bc,$7FFF
        ret

; HL = min(HL, DE), signed
dv_min:
        push hl
        or a
        sbc hl,de
        pop hl
        jp pe,.ov
        ret m                           ; HL - DE < 0: HL
        ex de,hl
        ret
.ov:    ret p                           ; (overflowed: the sign the other way)
        ex de,hl
        ret

; HL (unsigned, < 32768) * E (a fraction, /256) -> HL = HL * E >> 8
dv_mulhi:
        ld b,h
        ld c,l
        ld l,e                          ; (the factor)
        ld d,c                          ; low * it: its high byte
        mul d,e
        ld a,d
        ld d,b                          ; high * it
        ld e,l
        mul d,e
        add a,e
        ld l,a
        ld a,d
        adc a,0
        ld h,a
        ret

; HL (signed) -> A = it within 0..255 / 0..VIEW_H-1
dv_clamp_x:
        bit 7,h
        jr nz,.z
        ld a,h
        or a
        ld a,l
        ret z
        ld a,255
        ret
.z:     xor a
        ret
dv_clamp_y:
        bit 7,h
        jr nz,dv_clamp_x.z
        ld a,h
        or a
        jr nz,.b
        ld a,l
        cp VIEW_H
        ret c
.b:     ld a,VIEW_H-1
        ret

;------------------------------------------------------------------------------
; The devil's lightning (bolt_t frames: devil.asm): from its eyes as drawn
; this frame (dv_seen, dv_ex, dv_ey) to the VTOL, the view's bottom middle
; (or, bolt_up, fired into the sky: straight up to the view's top):
; BOLT_SEGS lines, the points between jittered across, new every frame,
; white, with a blue line beside.  Not drawn if it wasn't (it's behind).
;------------------------------------------------------------------------------
draw_bolt:
        ld hl,dv_seen
        ld c,(hl)
        ld (hl),0                       ; (for the next frame)
        ld a,(bolt_t)
        or a
        ret z
        ld a,c
        or a
        ret z
        ld a,(dv_ex)                    ; from its eyes
        ld (bp_x0),a
        ld l,a
        ld h,0
        ld de,128                       ; dx, dy to the bottom middle
        ex de,hl
        or a
        sbc hl,de
        ld (bp_dx),hl
        ld a,(dv_ey)
        ld (bp_y0),a
        ld e,a
        ld d,0
        ld hl,VIEW_H-1
        or a
        sbc hl,de
        ld (bp_dy),hl
        ld a,(bolt_hit)                 ; (stopped by a building: to where it
        or a                            ; hit, if that's in view)
        jr z,.nh
        push de
        ld hl,bolt_end
        call bul_cam                    ; Z: in view, A = x, C = y
        pop de
        ret nz
        ld l,a
        ld h,0
        ld a,(dv_ex)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ld (bp_dx),hl
        ld l,c
        ld h,0
        ld a,(dv_ey)
        ld e,a
        or a
        sbc hl,de
        ld (bp_dy),hl
        jr .at
.nh:    ld a,(bolt_up)                  ; (out of range: up into the sky, to
        or a                            ; the top of the view)
        jr z,.at
        ld hl,0
        ld (bp_dx),hl
        or a
        sbc hl,de
        ld (bp_dy),hl
.at:    ld hl,0
        ld (bp_ax),hl
        ld (bp_ay),hl
        ld b,BOLT_SEGS
.seg:   push bc
        ld hl,(bp_ax)                   ; i / BOLT_SEGS of the way
        ld de,(bp_dx)
        add hl,de
        ld (bp_ax),hl
        call .div
        ld a,(dv_ex)
        ld e,a
        ld d,0
        add hl,de
        pop bc
        push bc
        dec b
        jr z,.nj                        ; (the end: no jitter)
        push hl
        call zrand
        ld a,l
        and BOLT_JIT-1
        sub BOLT_JIT/2
        pop hl
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
.nj:    call dv_clamp_x
        ld (bp_x1),a
        ld hl,(bp_ay)
        ld de,(bp_dy)
        add hl,de
        ld (bp_ay),hl
        call .div
        ld a,(dv_ey)
        ld e,a
        ld d,0
        add hl,de
        call dv_clamp_y
        ld (bp_y1),a
        ld a,BOLT_COL                   ; the core
        ld (line_col),a
        call .line
        ld a,(bp_x0)                    ; and the glow beside it
        inc a
        jr z,.ng
        ld a,(bp_x1)
        inc a
        jr z,.ng
        ld a,BOLT_COL2
        ld (line_col),a
        ld a,(bp_x0)
        inc a
        ld l,a
        ld a,(bp_y0)
        ld h,a
        ld a,(bp_x1)
        inc a
        ld e,a
        ld a,(bp_y1)
        ld d,a
        call draw_line
.ng:    ld a,(bp_x1)
        ld (bp_x0),a
        ld a,(bp_y1)
        ld (bp_y0),a
        pop bc
        dec b
        jp nz,.seg
        ret
.line:  ld a,(bp_x0)
        ld l,a
        ld a,(bp_y0)
        ld h,a
        ld a,(bp_x1)
        ld e,a
        ld a,(bp_y1)
        ld d,a
        jp draw_line                    ; (city.asm)
.div:   sra h                           ; HL / BOLT_SEGS, signed
        rr l
        sra h
        rr l
        sra h
        rr l
        ret
        ASSERT BOLT_SEGS == 8

;------------------------------------------------------------------------------
; The devil's drawing data
;------------------------------------------------------------------------------
dv_X:       dw 0                        ; dv_draw: camera space: X,
dv_Yg:      dw 0                        ;   the ground under it (Y, Z),
dv_Zg:      dw 0
dv_Yf:      dw 0                        ;   its feet,
dv_Zf:      dw 0
dv_Yh:      dw 0                        ;   its head
dv_Zh:      dw 0
dv_w:       dw 0                        ; its width on the screen, twice it,
dv_w2:      dw 0
dv_sx:      dw 0                        ;   its middle column, its left one,
dv_left:    dw 0
dv_c0:      dw 0                        ;   the first in view (high byte 0)
dv_n:       db 0                        ;   and how many (0: 256)
dv_top:     dw 0                        ; its rows: top, feet, the ground,
dv_bot:     dw 0
dv_gnd:     dw 0
dv_hh:      dw 0                        ;   its height (rows)
dv_y:       db 0                        ; the row being drawn, the last,
dv_r1:      db 0
dv_sr:      db 0                        ;   its frame row,
dv_q:       db 0                        ; (the column tables' frame column)
dv_rr:      dw 0                        ; (their remainders)
dv_mir:     db 0                        ; $80: mirrored
dv_fr:      db 0                        ; its frame (0..DEVIL_FRAMES-1)
dv_c1:      dw 0                        ; the last column in view, + 1
dv_acc:     dw 0                        ; (q * w)
dv_xq:      ds 2*(DEVIL_W+1)            ; each frame column's first screen one
dv_x0:      dw 0                        ; a row's first column drawn,
dv_cnt:     dw 0                        ;   and its pixels
dv_seen:    db 0                        ; 1: drawn this frame, its eyes at
dv_ex:      db 0                        ;   (dv_ex, dv_ey) on the screen
dv_ey:      db 0
bp_x0:      db 0                        ; draw_bolt: a line's ends,
bp_y0:      db 0
bp_x1:      db 0
bp_y1:      db 0
bp_dx:      dw 0                        ;   the whole way,
bp_dy:      dw 0
bp_ax:      dw 0                        ;   so far (* BOLT_SEGS)
bp_ay:      dw 0
        ALIGN 256
    IFNDEF REAL_HARDWARE
dv_ctab:    ds 4*256                    ; the column tables (above)
    ENDIF
dv_ext:     ds DEVIL_FRAMES*256         ; each frame row's first, last opaque
                                        ; columns (dv_extents)
