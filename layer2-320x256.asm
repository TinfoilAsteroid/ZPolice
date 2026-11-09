;==============================================================================
; Z-POLICE - Layer 2 320x256 graphics (8K page PAGE_L320, runs at $4000 in
; slot 2)
;
; For the screens outside the game: the menus, the load-out, level complete
; and game over.  They're mostly text, so they use Layer 2's 320x256 mode
; (40 x 32 characters of 8x8, the whole screen, border included) in place of
; the ULA.  This page has everything they draw with:
;   l320_mode320 / l320_mode256   switch the display to 320x256 / back to the
;                                 game's 256x192
;   l320_cls                      clear the screen to a colour (by DMA)
;   l320_at, l320_pos             set the text position (character / pixel)
;   l320_char, l320_print,        text: one character, a string (with colour
;   l320_print_list                 and position codes), a table of strings
;   l320_recolour, l320_swap      change colours already drawn: a run of
;                                 text cells (highlighting), or one colour in
;                                 a box
;   l320_plot, l320_line,         pixels, lines, filled boxes, outlines
;   l320_fill, l320_hline,
;   l320_vline, l320_box
;
; Use: page it in, switch, clear, draw:
;       nextreg L320_MMU,PAGE_L320      ; this page at $4000 (slot 2)
;       ld a,L320_BLACK
;       call l320_cls
;       call l320_mode320
; and on leaving for the game, switch back and put the occlusion page back
; in slot 2 (l2_game_mode, zpolice.asm, does both).
;
; Slot 2 is the occlusion data's, used only while the city is drawn, so it
; is free on these screens: they run in slot 6, with the keys (and the
; sprites, sound, file handler) in slot 7, the resident page in slot 5, the
; zombie page (and the IM 2 table) in slot 1 and the city bank in slot 3.
;
; The screen: 5 16K banks from L2_BANK_A (banks 9-13, pages 18-27: the first
; game buffer and part of the second, unused while these screens are up;
; the game clears both before it draws).  320x256 is column-major: pixel
; (x, y) is byte x*256 + y, so each 8K page is 32 columns of 256 pixels and
; a column's pixels are in one page.  Writes go through slot 0, as the game's
; do: (x, y) is page 18 + x/32, at $0000 + (x & 31)*256 + y.
;
; Colours: Layer 2's second palette, set to RRRGGGBB (the colour is the
; byte; the level's palette is the first one and is left alone).  $E3 is
; the transparency colour: it is never drawn, and as a paper it means "leave
; the background" (L320_NOPAPER).
;
; Registers: every routine may change AF, BC, DE, HL unless it says so; IX,
; IY and the alternate set are kept.  The text uses the resident 8x8 font
; (font8, text.asm: ASCII 32-95; lower case is drawn as upper case).
;==============================================================================

L320_W          equ 320             ; pixels
L320_H          equ 256
L320_COLS       equ 40              ; text: 8x8 characters
L320_ROWS       equ 32
L320_BANK       equ L2_BANK_A       ; the first of its 5 16K banks
L320_PAGE0      equ L320_BANK*2     ; the first of its 10 8K pages
L320_PAGES      equ 10
        ASSERT L320_PAGE0+L320_PAGES <= PAGE_L2_B+6     ; (in the two buffers)
        ASSERT L2SEC_ADDR == 0          ; (l320_addr: H = x & 31)

; Colours (RRRGGGBB)
L320_BLACK      equ $00
L320_WHITE      equ $FF
L320_GREY       equ $6D             ; the HUD panel's
L320_DKGREY     equ $49
L320_RED        equ $E0
L320_GREEN      equ $1C
L320_BLUE       equ $03
L320_DKBLUE     equ $02
L320_YELLOW     equ $FC
L320_AMBER      equ $F4
L320_CYAN       equ $1F
L320_MAGENTA    equ $E2             ; ($E3 is the transparency colour)
L320_NOPAPER    equ $E3             ; paper: leave the background

; Codes in l320_print's text
L320_C_INK      equ 1               ; 1, colour: the ink from here on
L320_C_PAPER    equ 2               ; 2, colour: the paper
L320_C_AT       equ 3               ; 3, row, column: the text position

;------------------------------------------------------------------------------
; Switching
;------------------------------------------------------------------------------

; Show Layer 2 at 320x256: from L320_BANK, the whole screen (clip window),
; over the ULA (priority S L U: Layer 2 drawn nowhere transparent, so the
; ULA screen is hidden behind it), with the second palette, set to RRRGGGBB.
; Clear the screen first (l320_cls): this shows whatever is in the banks.
l320_mode320:
        ld a,(l320_on)
        or a
        jr nz,.on                       ; (already: keep the saved $15)
        ld a,$15
        call read_nextreg
        ld (l320_nr15),a                ; the layer priority, for l320_mode256
.on:    ld a,(l320_nr15)
        and %11100011                   ; priority S L U (sprites kept)
        nextreg $15,a
        ld a,$43
        call read_nextreg
        and %00001011                   ; (the sprite, ULA palette choices)
        or %01010100                    ; edit Layer 2's second palette, and
        nextreg $43,a                   ; show it
        nextreg $40,0
        xor a
.pal:   nextreg $41,a                   ; entry n = colour n (RRRGGGBB)
        inc a
        jr nz,.pal
        nextreg $1C,%00000001           ; Layer 2's clip window: all of it
        nextreg $18,0                   ; (x in pairs of pixels)
        nextreg $18,(L320_W/2)-1
        nextreg $18,0
        nextreg $18,L320_H-1
        nextreg $12,L320_BANK
        nextreg $70,%00010000           ; 320x256
        ld bc,$123B
        ld a,%00000010                  ; Layer 2 visible
        out (c),a
        ld a,1
        ld (l320_on),a
        ret

; Back to the game's Layer 2: 256x192, clipped to 192 rows, its palette and
; layer priority (ULA over Layer 2), and hidden (the game shows it once it
; has cleared its buffers).  Nothing if l320_mode320 hasn't been called.
l320_mode256:
        ld a,(l320_on)
        or a
        ret z
        xor a
        ld (l320_on),a
        ld bc,$123B
        out (c),a                       ; Layer 2 hidden
        nextreg $70,0                   ; 256x192
        nextreg $1C,%00000001           ; the clip window as initgame's
        nextreg $18,0
        nextreg $18,255
        nextreg $18,0
        nextreg $18,191
        ld a,$43
        call read_nextreg
        and %11111011                   ; Layer 2's first palette (the level's)
        nextreg $43,a
        ld a,(l320_nr15)
        nextreg $15,a
        ret

;------------------------------------------------------------------------------
; Clearing
;------------------------------------------------------------------------------

; A = colour: the whole screen, page by page through slot 0, by DMA
; (dma_fill, layer2_cls.asm)
l320_cls:
        ld e,a
        ld d,L320_PAGE0
.pg:    ld a,d
        nextreg L2SEC_MMU,a
        ld a,e
        ld hl,L2SEC_ADDR
        ld bc,MEMBANK_SIZE
        call dma_fill                   ; (keeps DE)
        inc d
        ld a,d
        cp L320_PAGE0+L320_PAGES
        jr c,.pg
        ret

;------------------------------------------------------------------------------
; Text
;------------------------------------------------------------------------------

; D = row (0-31), E = column (0-39): the text position
l320_at:
        ld a,d
        add a,a
        add a,a
        add a,a
        ld (l320_cy),a
        ld l,e
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld (l320_cx),hl
        ret

; HL = x (0-319), C = y (0-248): the text position in pixels
l320_pos:
        ld (l320_cx),hl
        ld a,c
        ld (l320_cy),a
        ret

; A = ASCII: one character at the text position, in l320_ink on
; l320_paper, and the position on 8.  Lower case is drawn as upper case,
; anything else not in the font as a space.  Columns past the right edge
; are left off.
l320_char:
        push ix
        cp 'a'
        jr c,.uc
        cp 'z'+1
        jr nc,.uc
        sub 'a'-'A'
.uc:    sub 32
        cp 64
        jr c,.inf
        xor a
.inf:   ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,font8
        add hl,de
        ld (l320_fp),hl                 ; -> its 8 bytes
        ld a,(l320_ink)
        ld ixh,a
        ld a,(l320_paper)
        ld ixl,a
        call l320_nopg
        ld c,%10000000                  ; the column's bit in each byte
        ld hl,(l320_cx)
.col:   call l320_xok
        jr nc,.done                     ; off the right edge
        push hl
        push bc
        ld a,(l320_cy)
        ld e,a
        call l320_addr                  ; HL -> the column's top pixel
        ld de,(l320_fp)
        ld b,8
.row:   ld a,(de)
        and c
        jr z,.pap
        ld a,ixh
        ld (hl),a
        jr .nx
.pap:   ld a,ixl
        cp L320_NOPAPER
        jr z,.nx
        ld (hl),a
.nx:    inc de
        inc l
        djnz .row
        pop bc
        pop hl
        inc hl
        rrc c
        jr nc,.col                      ; 8 columns, until the bit comes round
.done:  ld hl,(l320_cx)
        ld de,8
        add hl,de
        ld (l320_cx),hl
        pop ix
        ret

; HL -> text ending 0: printed from the text position.  HL ends past the 0.
; In the text: L320_C_INK, colour and L320_C_PAPER, colour change the
; colours (and they stay changed); L320_C_AT, row, column moves the
; position.  Other codes below 32 are skipped.
l320_print:
.ch:    ld a,(hl)
        inc hl
        or a
        ret z
        cp 32
        jr nc,.pr
        dec a
        jr z,.ink
        dec a
        jr z,.pap
        dec a
        jr nz,.ch
        ld d,(hl)                       ; L320_C_AT
        inc hl
        ld e,(hl)
        inc hl
        push hl
        call l320_at
        pop hl
        jr .ch
.ink:   ld a,(hl)
        inc hl
        ld (l320_ink),a
        jr .ch
.pap:   ld a,(hl)
        inc hl
        ld (l320_paper),a
        jr .ch
.pr:    push hl
        call l320_char
        pop hl
        jr .ch

; HL -> a table of strings: row, column, ink, text ending 0 for each, then
; $FF.  Each is printed (l320_print) on the current paper.  HL ends past the
; $FF.
l320_print_list:
.rec:   ld a,(hl)
        inc hl
        cp $FF
        ret z
        ld d,a
        ld e,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld (l320_ink),a
        push hl
        call l320_at
        pop hl
        call l320_print
        jr .rec

;------------------------------------------------------------------------------
; Changing colours already drawn
;------------------------------------------------------------------------------

; Highlighting: D = row, E = column, B = length in characters, H = the paper
; they were printed on, C = new ink, A = new paper.  In those cells each
; pixel of the old paper becomes the new paper and every other pixel the new
; ink.  (Back again: the same with H = the highlight's paper.)
l320_recolour:
        ld (l320_kp),a
        ld a,h
        ld (l320_k),a
        ld a,c
        ld (l320_ki),a
        ld a,d
        add a,a
        add a,a
        add a,a
        ld (l320_by),a
        ld a,8
        ld (l320_bh),a
        ld l,b
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld (l320_bw),hl
        ld l,e
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld (l320_bx),hl
        jr l320_rebox

; HL = x, C = y, DE = width, B = height (0 = 256), A = a colour: in that
; box, each pixel of that colour becomes l320_ink.  The rest are left.
l320_swap:
        ld (l320_k),a
        ld a,(l320_ink)
        ld (l320_kp),a
        ld a,L320_NOPAPER
        ld (l320_ki),a                  ; (the other pixels: left)
        ld (l320_bx),hl
        ld (l320_bw),de
        ld a,c
        ld (l320_by),a
        ld a,b
        ld (l320_bh),a
        ; (on into l320_rebox)

; The box (l320_bx, _by, _bw, _bh): each pixel of colour l320_k becomes
; l320_kp; every other becomes l320_ki, unless that is L320_NOPAPER (left).
l320_rebox:
        call l320_nopg
        ld hl,(l320_bx)
        ld de,(l320_bw)
.col:   ld a,d
        or e
        ret z
        call l320_xok
        ret nc
        push de
        push hl
        ld a,(l320_by)
        ld e,a
        call l320_addr                  ; HL -> the column's top pixel
        ld a,(l320_bh)
        ld b,a
        ld a,(l320_ki)
        ld c,a
        ld de,(l320_k)                  ; E = from (l320_k), D = to (l320_kp)
.px:    ld a,(hl)
        cp e
        jr nz,.oth
        ld (hl),d
        jr .nx
.oth:   ld a,c
        cp L320_NOPAPER
        jr z,.nx
        ld (hl),a
.nx:    inc l
        djnz .px
        pop hl
        pop de
        inc hl
        dec de
        jr .col

;------------------------------------------------------------------------------
; Pixels, lines, boxes
;------------------------------------------------------------------------------

; HL = x (0-319), E = y, A = colour: one pixel.  (Nothing if x is off the
; screen.)  Keeps BC, DE, HL.
l320_plot:
        push af
        call l320_nopg
        pop af
l320_pset:                              ; (the same, slot 0 as l320_pg says)
        push hl
        push de
        push af
        call l320_xok
        jr nc,.off
        call l320_addr
        pop af
        ld (hl),a
        pop de
        pop hl
        ret
.off:   pop af
        pop de
        pop hl
        ret

; HL = x0, C = y0, DE = x1, B = y1, A = colour: a line, both ends included
; (Bresenham).  Points off the right edge are left off.
l320_line:
        ld (l320_lc),a
        ld (l320_x0),hl
        ld (l320_x1),de
        ld a,c
        ld (l320_y0),a
        ld a,b
        ld (l320_y1),a
        call l320_nopg
        ex de,hl                        ; dx = |x1 - x0|, sx
        or a
        sbc hl,de
        ld a,0
        jr nc,.sx
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
        ld a,1                          ; (x goes down)
.sx:    ld (l320_sx),a
        ld (l320_dx),hl
        ld a,(l320_y1)                  ; dy = |y1 - y0|, sy
        ld hl,l320_y0
        sub (hl)
        ld e,1
        jr nc,.sy
        neg
        ld e,-1
.sy:    ld l,a
        ld h,0
        ld (l320_dy),hl
        ld a,e
        ld (l320_sy),a
        ld hl,(l320_dx)                 ; err = dx - dy
        ld de,(l320_dy)
        or a
        sbc hl,de
        ld (l320_err),hl
.lp:    ld hl,(l320_x0)
        ld a,(l320_y0)
        ld e,a
        ld a,(l320_lc)
        call l320_pset
        ld de,(l320_x1)                 ; the end?
        or a
        sbc hl,de
        jr nz,.st
        ld a,(l320_y0)
        ld hl,l320_y1
        cp (hl)
        ret z
.st:    ld hl,(l320_err)
        add hl,hl
        push hl                         ; e2 = 2 err
        ld de,(l320_dy)
        add hl,de                       ; e2 > -dy: a step in x
        bit 7,h
        jr nz,.nx
        ld a,h
        or l
        jr z,.nx
        ld hl,(l320_err)
        or a
        sbc hl,de
        ld (l320_err),hl
        ld hl,(l320_x0)
        ld a,(l320_sx)
        or a
        jr nz,.xd
        inc hl
        jr .xs
.xd:    dec hl
.xs:    ld (l320_x0),hl
.nx:    pop hl
        ld de,(l320_dx)                 ; e2 < dx: a step in y
        or a
        sbc hl,de
        bit 7,h
        jr z,.lp
        ld hl,(l320_err)
        add hl,de
        ld (l320_err),hl
        ld a,(l320_sy)
        ld hl,l320_y0
        add a,(hl)
        ld (hl),a
        jr .lp

; HL = x, C = y, DE = width, A = colour: a line across
l320_hline:
        ld b,1
        jr l320_fill

; HL = x, C = y, B = height (0 = 256), A = colour: a line down
l320_vline:
        ld de,1
        ; (on into l320_fill)

; HL = x, C = y, DE = width, B = height (0 = 256), A = colour: a filled box.
; Columns past the right edge are left off; rows past the bottom wrap to
; the top.
l320_fill:
        ld (l320_fc),a
        ld a,b
        ld (l320_fh),a
        ld a,c
        ld (l320_fy),a
        call l320_nopg
.col:   ld a,d
        or e
        ret z
        call l320_xok
        ret nc
        push de
        push hl
        ld a,(l320_fy)
        ld e,a
        call l320_addr                  ; HL -> the column's top pixel
        ld a,(l320_fh)
        ld b,a
        ld a,(l320_fc)
.px:    ld (hl),a
        inc l
        djnz .px
        pop hl
        pop de
        inc hl
        dec de
        jr .col

; HL = x, C = y, DE = width, B = height (both 1 or more), A = colour: a
; box's outline, one pixel wide
l320_box:
        ld (l320_bx),hl
        ld (l320_bw),de
        ld (l320_bc),bc
        ld (l320_bk),a
        call l320_hline                 ; top
        ld hl,(l320_bx)
        ld de,(l320_bw)
        ld bc,(l320_bc)
        ld a,c
        add a,b
        dec a
        ld c,a
        ld a,(l320_bk)
        call l320_hline                 ; bottom
        ld hl,(l320_bx)
        ld bc,(l320_bc)
        ld a,(l320_bk)
        call l320_vline                 ; left
        ld hl,(l320_bx)
        ld de,(l320_bw)
        add hl,de
        dec hl
        ld bc,(l320_bc)
        ld a,(l320_bk)
        jr l320_vline                   ; right

;------------------------------------------------------------------------------
; Addressing
;------------------------------------------------------------------------------

; Carry set if HL (x) is on the screen (below 320).  Keeps HL, DE, BC.
l320_xok:
        push de
        ld de,L320_W
        or a
        sbc hl,de
        add hl,de                       ; (carry as the sbc's)
        pop de
        ret

; Slot 0's page unknown (each drawing routine starts with it: anything else
; may have mapped slot 0 since)
l320_nopg:
        ld a,$FF
        ld (l320_pg),a
        ret

; HL = x (0-319), E = y: its page into slot 0 (unless it's there already),
; HL -> the pixel.  Changes A, D.
l320_addr:
        ld a,h                          ; page: x / 32 = H*8 + L/32
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,l
        rlca
        rlca
        rlca
        and 7
        or d
        add a,L320_PAGE0
        ld d,a
        ld a,(l320_pg)
        cp d
        jr z,.in
        ld a,d
        ld (l320_pg),a
        nextreg L2SEC_MMU,a
.in:    ld a,l
        and 31                          ; (slot 0: $0000 + (x & 31)*256 + y)
        ld h,a
        ld l,e
        ret

;------------------------------------------------------------------------------
; Variables
;------------------------------------------------------------------------------
l320_on:    db 0                        ; 1 while the display is 320x256
l320_nr15:  db %00001011                ; the game's layer priority (NextReg $15)
l320_pg:    db $FF                      ; the page in slot 0 ($FF: unknown)
l320_ink:   db L320_WHITE               ; text colours
l320_paper: db L320_BLACK
l320_cx:    dw 0                        ; text position, pixels
l320_cy:    db 0
l320_fp:    dw 0                        ; l320_char: -> the character's bytes
l320_fc:    db 0                        ; l320_fill: colour, height, y
l320_fh:    db 0
l320_fy:    db 0
l320_bx:    dw 0                        ; l320_rebox, l320_box: the box
l320_by:    db 0
l320_bw:    dw 0
l320_bh:    db 0
l320_bc:    dw 0                        ; l320_box: y, height
l320_bk:    db 0                        ;   and colour
l320_k:     db 0                        ; l320_rebox: this colour
l320_kp:    db 0                        ;   becomes this (keep together)
l320_ki:    db 0                        ;   and the rest this
l320_lc:    db 0                        ; l320_line: colour,
l320_x0:    dw 0                        ;   ends,
l320_y0:    db 0
l320_x1:    dw 0
l320_y1:    db 0
l320_dx:    dw 0                        ;   Bresenham's sizes, steps and error
l320_dy:    dw 0
l320_sx:    db 0                        ;   (0: x up, 1: down)
l320_sy:    db 0                        ;   (+1 / -1)
l320_err:   dw 0
