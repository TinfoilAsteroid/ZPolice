;==============================================================================
; spr_draw for the real-hardware build (REAL_HARDWARE, included by city2.asm):
; the graphics are ZPDATA/SPRITEHW.ZPG's, each level a rectangle (zw x zh
; bytes, row by row, 0 transparent: tools/spritefile.py), so a figure is one
; DMA+ transfer (docs/ZXNDDMA.md): 2D, transparent (pixel 0 not written),
; both ends by physical address (no paging: the source page spr_pg, the
; buffer being drawn at seg_base), cut to the view: the rows (zy can be off
; the top or the bottom) and the columns (the screen's edges).  Mirrored
; (zface bit 1), port B counts down along each row.  One colour (spr_col not
; 0: the fading ghost) can't be a copy: the CPU draws the same rectangle.
; Draws what the plain build's spr_draw does (tests/test_hardware.py).
; Over the spans' DMA set-up: put back after (span_arm).
;==============================================================================
spr_draw:
        ld a,(zh)                       ; the rows in the view
        ld b,a
        ld a,(zy)
        cp VIEW_H
        jr nc,.above
        ld (fq_y),a                     ; from the top row: VIEW_H - zy at most
        neg
        add a,VIEW_H
        cp b
        jr c,.nr
        ld a,b
.nr:    ld (fq_rows),a
        xor a                           ; (none skipped)
        jr .r0
.above: neg                             ; zy past the view: 256 - zy rows above
        cp b                            ; (from below: more than zh)
        ret nc
        ld c,a
        ld a,b
        sub c
        ld (fq_rows),a
        xor a
        ld (fq_y),a
        ld a,c
.r0:    ld e,a                          ; rows skipped x width: the source
        ld a,(zw)
        ld d,a
        mul d,e
        ld (fq_off),de
        ld a,(zw)                       ; x0 = centre - w/2 (-8..255)
        ld c,a
        srl a
        ld e,a
        ld d,0
        ld a,(zsx)
        ld l,a
        ld h,0
        or a
        sbc hl,de
        ld a,(zface)
        bit 1,a
        jr nz,.mir
        ld e,0                          ; c0: the first column shown,
        bit 7,h                         ;   -x0 if x0 < 0
        jr z,.n0
        ld a,l
        neg
        ld e,a
        ld l,0                          ; and the screen's x: x0 + c0
.n0:    ld a,c                          ; columns: min(w - c0, 256 - x)
        sub e
        ld b,a
        ld a,l
        neg
        jr z,.nw                        ; (x 0: no limit)
        cp b
        jr nc,.nw
        ld b,a
.nw:    ld a,DMA_WR2_P2INC_MEMORY
        jr .cols
.mir:   ld b,0                          ; mirrored: source column c is at
        add hl,bc                       ; x0 + w-1 - c; E' = x0 + w-1 (0..270)
        dec hl
        ld e,0                          ; the first column: E' - 255 if past
        ld a,h                          ; the right edge, at x 255
        or a
        jr z,.m0
        ld a,l
        inc a
        ld e,a
        ld l,255
.m0:    ld a,c                          ; columns: min(w - c0, x + 1)
        sub e
        ld b,a
        ld a,l
        inc a
        jr z,.mw                        ; (x 255: no limit)
        cp b
        jr nc,.mw
        ld b,a
.mw:    ld a,DMA_WR2_P2DEC_MEMORY
.cols:  ld (fq_wr2),a
        ld a,l
        ld (fq_x),a
        ld a,b
        ld (fq_n),a
        ld hl,(fq_off)                  ; the source: + the first column
        ld a,e
        add hl,a
        ld de,(spr_ptr)
        add hl,de                       ; (in slot 6, page spr_pg)
        ld a,(spr_col)
        or a
        jp nz,fq_cpu
        ld de,-GFX_ADDR_C000            ; physical: $40000 + spr_pg * $2000
        add hl,de                       ;   + the offset in the page
        ld a,(spr_pg)
        ld c,a
        and 7                           ; 15:13 = spr_pg & 7 (no carry: the
        rrca                            ; offset is under $2000)
        rrca
        rrca
        add a,h
        ld h,a
        ld (fq_src),hl
        ld a,c                          ; 23:16 = 4 + spr_pg / 8
        rrca
        rrca
        rrca
        and 31
        add a,4
        ld (fq_sext),a
        ld a,(seg_base)                 ; the screen: as dd_rect (city.asm)
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
        ld a,(fq_y)
        add a,l
        jr nc,.nc
        inc h
.nc:    ld (fq_dst+1),a
        ld a,h
        ld (fq_dext),a
        ld a,(fq_x)
        ld (fq_dst),a
        ld a,(zw)
        ld (fq_sstr),a                  ; a source row on: the width
        ld a,(fq_n)
        ld (fq_len),a
        ld a,(fq_rows)
        ld (fq_nrow),a
        ld hl,fq_cmds
        ld bc,FQ_N<<8 | IO_DATAGEAR_DMA_PORT
        otir                            ; (the CPU waits while it copies)
        jp span_arm                     ; (the DMA as the faces' spans want it)

GFX_ADDR_C000 equ $C000                 ; (the graphics' pages are read at $C000)

fq_cmds:    db DMA_DISABLE, DMA_RESET
            db DDMA_MODE, DDMA_FLAG_PHYS|DDMA_FLAG_2D|DDMA_FLAG_TRANS
            db DDMA_TRANS_COL, 0
            db DDMA_A_EXT
fq_sext:    db 0                        ; the source's address bits 23:16,
            db DDMA_B_EXT
fq_dext:    db 0                        ; the screen's
            db DDMA_ROW_LEN
fq_len:     dw 0                        ; the columns drawn,
            db DDMA_ROWS
fq_nrow:    dw 0                        ; the rows,
            db DDMA_A_STRIDE
fq_sstr:    dw 0                        ; the source's row (the width),
            db DDMA_B_STRIDE
            dw 256                      ; the screen's
            db DMA_WRO_BLOCK_PORTA_A2B_XFR
fq_src:     dw 0, 0                     ; port A (the length: not used, 2D)
            db DMA_WR1_P1INC_MEMORY
fq_wr2:     db DMA_WR2_P2INC_MEMORY     ; port B up, or down mirrored
            db DMA_WR4_CONT_MODE
fq_dst:     dw 0                        ; port B
            db DMA_STOP_AT_END, DMA_LOAD, DMA_ENABLE
FQ_N        equ $ - fq_cmds

; One colour (spr_col): the CPU, the same rectangle; HL = its first pixel
; (in slot 6).
fq_cpu:
        ld a,(spr_pg)
        nextreg LOGIC_MMU,a
        ex de,hl
        ld a,(zface)
        bit 1,a
        ld a,OP_INC_L
        jr z,.m
        ld a,OP_DEC_L
.m:     ld (.step),a
        ld a,(fq_rows)
        ld (zcnt),a
.row:   ld a,(fq_y)
        call seg_map                    ; A = y & 31 (keeps BC, DE, L)
        ld h,a
        ld a,(fq_x)
        ld l,a
        ld a,(fq_n)
        ld b,a
        ld a,(spr_col)
        ld c,a
.px:    ld a,(de)
        inc de
        or a
        jr z,.step                      ; (transparent)
        ld (hl),c
.step:  inc l                           ; (patched: dec l)
        djnz .px
        ld a,(fq_n)                     ; the next row: + width - columns
        ld b,a
        ld a,(zw)
        sub b
        add de,a
        ld hl,fq_y
        inc (hl)
        ld hl,zcnt
        dec (hl)
        jr nz,.row
        ret

fq_y:       db 0                        ; spr_draw: the first row drawn,
fq_rows:    db 0                        ;   the rows,
fq_x:       db 0                        ;   the first pixel's x,
fq_n:       db 0                        ;   the columns,
fq_off:     dw 0                        ;   the rows skipped x the width
