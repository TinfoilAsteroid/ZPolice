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
;   l320_screen                   a screen's start: cleared, framed, shown
;                                 (screen320, text.asm, calls it)
;   l320_cls                      clear the screen to a colour (by DMA)
;   l320_at, l320_pos             set the text position (character / pixel)
;   l320_char, l320_print,        text: one character, a string (with colour
;   l320_print_at,                  and position codes), a string at a row
;   l320_print_list                 and column (menu_print's registers), a
;                                   table of strings
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

; The screens' colours (l320_screen; the screen pages print in these)
SCR_BG          equ L320_DKBLUE     ; background (the paper)
SCR_FRAME       equ L320_GREY       ; the frame round the screen
SCR_FRAME2      equ L320_DKGREY
SCR_TEXT        equ L320_WHITE
SCR_TITLE       equ L320_YELLOW
SCR_OK          equ L320_GREEN      ; highlighted / done
SCR_BAD         equ L320_RED        ; can't / failed
SCR_HELP        equ L320_CYAN       ; the keys' help line

; Codes in l320_print's text
L320_C_INK      equ 1               ; 1, colour: the ink from here on
L320_C_PAPER    equ 2               ; 2, colour: the paper
L320_C_AT       equ 3               ; 3, row, column: the text position
L320_C_FONT     equ 4               ; 4, font: the font (L320_F8 / L320_F12)
L320_LIST_FONT  equ $FE             ; in l320_print_list's table: $FE, font

; Fonts (l320_font): the 8x8 one (font8, text.asm) on a 40 x 32 grid, or the
; large one (12x10 cells, ZPDATA/FONT12.ZPF, loaded at start-up: f12_load)
; on a 26 x 25 grid from (F12_X0, F12_Y0), inside the screens' frame.  The
; large one is drawn in a gradient for its colour (one row colour each).
; Without the file the large grid is kept, with the 8x8 glyphs in each cell.
L320_F8         equ 0
L320_F12        equ 1
F12_W           equ 12              ; the cell
F12_H           equ 10
F12_COLS        equ 26
F12_ROWS        equ 25
F12_X0          equ 4
F12_Y0          equ 3
        ASSERT F12_X0 + F12_COLS*F12_W <= L320_W-4 && F12_Y0 + F12_ROWS*F12_H <= L320_H-3
F12_FIRST       equ 32              ; the file (tools/fontfile.py): space to Z,
F12_COUNT       equ 59
F12_BPR         equ 2               ;   2 bytes a row
F12_HEADER      equ 12
F12_GRAD_MAX    equ 8
F12_GLYPHS      equ F12_COUNT*F12_H*F12_BPR
F12_SIZE_MAX    equ F12_HEADER + F12_GLYPHS + F12_GRAD_MAX*(1+F12_H)
; The 8x8 font's file, ZPDATA/FONT8.ZPF: its glyphs go over the built-in
; font8 (text.asm, resident: the ULA screens and the HUD use them too), its
; gradients stay here (the 320x256 screens draw it in them)
F8_H            equ 8
F8_FIRST        equ 32              ; space to _
F8_COUNT        equ 64
F8_BPR          equ 1
F8_GLYPHS       equ F8_COUNT*F8_H*F8_BPR
F8_SIZE_MAX     equ F12_HEADER + F8_GLYPHS + F12_GRAD_MAX*(1+F8_H)

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

; A screen's start: cleared to SCR_BG with a frame (SCR_FRAME, SCR_FRAME2)
; round the edge, the text colours SCR_TEXT on SCR_BG in the large font,
; and shown at 320x256.  (screen320, text.asm, calls it with this page
; mapped.)
l320_screen:
        ld a,SCR_BG
        call l320_cls
        ld hl,0
        ld c,0
        ld de,L320_W
        ld b,0                          ; (256)
        ld a,SCR_FRAME
        call l320_box
        ld hl,2
        ld c,2
        ld de,L320_W-4
        ld b,L320_H-4
        ld a,SCR_FRAME2
        call l320_box
        ld a,SCR_TEXT
        ld (l320_ink),a
        ld a,SCR_BG
        ld (l320_paper),a
        ld a,L320_F12
        ld (l320_font),a
        jp l320_mode320

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

; D = row, E = column: the text position, on the font's grid (8x8: 0-31,
; 0-39; large: 0-24, 0-25)
l320_at:
        ld a,(l320_font)
        or a
        jr z,.f8
        ld a,d                          ; large: y = F12_Y0 + row*10
        add a,a
        ld d,a
        add a,a
        add a,a
        add a,d
        add a,F12_Y0
        ld (l320_cy),a
        ld l,e                          ; x = F12_X0 + column*12
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,F12_X0
        add hl,de
        ld (l320_cx),hl
        ret
.f8:    ld a,d
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
; l320_paper, in the font (l320_font), and the position on (8 or 12).
; Lower case is drawn as upper case, anything else not in the font as a
; space.  Columns past the right edge are left off.
l320_char:
        ld c,a
        ld a,(l320_font)
        or a
        ld a,c
        jp nz,l320_char12
l320_char8:
        push ix
        push iy
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
        call l320_grad8                 ; f12_gp -> the row colours
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
        ld iy,(f12_gp)
        ld b,8
.row:   ld a,(de)
        and c
        jr z,.pap
        ld a,(iy+0)
        ld (hl),a
        jr .nx
.pap:   ld a,ixl
        cp L320_NOPAPER
        jr z,.nx
        ld (hl),a
.nx:    inc de
        inc iy
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
        pop iy
        pop ix
        ret

; HL -> text ending 0: printed from the text position.  HL ends past the 0.
; In the text: L320_C_INK, colour and L320_C_PAPER, colour change the
; colours (and they stay changed); L320_C_AT, row, column moves the
; position; L320_C_FONT, font changes the font (from the next position).
; Other codes below 32 are skipped.
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
        jr z,.at
        dec a
        jr nz,.ch
        ld a,(hl)                       ; L320_C_FONT
        inc hl
        ld (l320_font),a
        jr .ch
.at:    ld d,(hl)                       ; L320_C_AT
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

; D = row, E = column, C = ink, HL -> text ending 0: printed there on the
; current paper (l320_print).  HL ends past the 0.  (menu_print's
; registers, text.asm, with a colour for the attribute.)
l320_print_at:
        ld a,c
        ld (l320_ink),a
        push hl
        call l320_at
        pop hl
        jp l320_print

; HL -> a table of strings: row, column, ink, text ending 0 for each, then
; $FF.  Each is printed (l320_print) on the current paper, row and column
; on the current font's grid; L320_LIST_FONT, font in place of a string
; changes the font.  HL ends past the $FF.
l320_print_list:
.rec:   ld a,(hl)
        inc hl
        cp $FF
        ret z
        cp L320_LIST_FONT
        jr nz,.str
        ld a,(hl)
        inc hl
        ld (l320_font),a
        jr .rec
.str:   ld d,a
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
; The large font
;------------------------------------------------------------------------------

; A = ASCII: one character in the large font (l320_char, with l320_font
; L320_F12): its 12x10 cell at the text position, the ink rows in the
; gradient for l320_ink (l320_grad), the rest l320_paper; the position on
; 12.  Without the font file, the 8x8 glyph in the cell.
l320_char12:
        ld c,a
        ld a,(f12_ok)
        or a
        jr nz,.ok
        ld hl,(l320_cx)                 ; no font: the 8x8 glyph, in the cell
        push hl
        inc hl
        inc hl
        ld (l320_cx),hl
        ld hl,l320_cy
        inc (hl)
        ld a,c
        call l320_char8
        ld hl,l320_cy
        dec (hl)
        pop hl
        jp .next
.ok:    push ix
        push iy
        ld a,c
        cp 'a'
        jr c,.uc
        cp 'z'+1
        jr nc,.uc
        sub 'a'-'A'
.uc:    sub F12_FIRST
        cp F12_COUNT
        jr c,.inf
        xor a                           ; (not in the font: a space)
.inf:   ld l,a                          ; HL = the glyph: char * 20
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,f12_buf+F12_HEADER
        add hl,de
        ld (l320_fp),hl
        call l320_grad
        call l320_nopg
        xor a
        ld (f12_fb),a                   ; the glyph's byte: 0, then 1
        ld a,F12_W
        ld (f12_n),a
        ld c,%10000000                  ; the column's bit
        ld hl,(l320_cx)
.col:   call l320_xok
        jr nc,.done                     ; off the right edge
        push hl
        push bc
        ld a,(l320_cy)
        ld e,a
        call l320_addr                  ; HL -> the column's top pixel
        ld de,(l320_fp)
        ld a,(f12_fb)
        add de,a
        ld iy,(f12_gp)
        ld b,F12_H
.row:   ld a,(de)
        and c
        jr z,.pap
        ld a,(iy+0)
        ld (hl),a
        jr .nx
.pap:   ld a,(l320_paper)
        cp L320_NOPAPER
        jr z,.nx
        ld (hl),a
.nx:    inc de
        inc de
        inc iy
        inc l
        djnz .row
        pop bc
        pop hl
        inc hl
        rrc c
        jr nc,.same
        ld a,1                          ; past the first byte's 8 columns
        ld (f12_fb),a
.same:  ld a,(f12_n)
        dec a
        ld (f12_n),a
        jr nz,.col
.done:  pop iy
        pop ix
        ld hl,(l320_cx)
.next:  ld de,F12_W
        add hl,de
        ld (l320_cx),hl
        ret

; f12_gp -> the row colours for l320_ink in the large font (l320_grad) or
; the 8x8 one (l320_grad8): its gradient in the font file, or f12_flat
; filled with it (none for it, or no file)
l320_grad:
        ld a,(f12_buf+10)               ; gradients
        ld b,a
        ld hl,f12_buf+F12_HEADER+F12_GLYPHS
        ld c,F12_H
        jr l320_gradin
l320_grad8:
        ld a,(f8_ok)
        or a
        ld b,a                          ; (none without the file)
        jr z,l320_gradin
        ld a,(f8_buf+10)
        ld b,a
        ld hl,f8_buf+F12_HEADER+F8_GLYPHS
        ld c,F8_H
; HL -> the gradients, B = how many, C = rows each
l320_gradin:
        ld a,(l320_ink)
        inc b
        dec b
        jr z,.flat
        ld e,c
        ld d,0
.f:     cp (hl)
        inc hl
        jr z,.got
        add hl,de
        djnz .f
.flat:  ld hl,f12_flat              ; none: flat
        ld b,F12_H
.fl:    ld (hl),a
        inc hl
        djnz .fl
        ld hl,f12_flat
.got:   ld (f12_gp),hl
        ret

; At start-up (this page in slot 2, after the random seed is read): the
; fonts' files (tools/fontfile.py), each if it is there and fits this game
; (its size, magic, cell, characters, and 1 to F12_GRAD_MAX gradients):
; FONT8.ZPF's glyphs over the built-in font8 (f8_ok 1: its gradients here),
; FONT12.ZPF (f12_ok 1; else the screens put the 8x8 glyphs in the large
; cells).  Leaves the input page in slot 7.
fonts_load:
        call f8_load
        call f12_load
        ld hl,f8_buf+F12_HEADER         ; the 8x8 glyphs over the built-in
        ld de,font8                     ; ones (text.asm, resident)
        ld bc,F8_GLYPHS
        ld a,(f8_ok)
        or a
        ret z
        ldir
        ret

; Load file name to buf (at most size bytes); ok := 1 if its header is head
; (10 bytes), its gradients 1..F12_GRAD_MAX of rows+1 bytes each, and its
; size the header, glyphs bytes and the gradients'
    MACRO FONT_LOAD FLNAME, FLBUF, FLSIZE, FLHEAD, FLGLYPHS, FLROWS, FLOK
        xor a
        ld (FLOK),a
        nextreg CODE_MMU,PAGE_FILE
        ld hl,FLNAME
        ld de,FLBUF
        ld bc,FLSIZE+1                  ; (one more: a longer file isn't one)
        call fh_load
        nextreg CODE_MMU,PAGE_INPUT
        ret c                           ; none
        ld (f12_len),bc                 ; (the bytes read)
        ld hl,FLBUF                     ; the header
        ld de,FLHEAD
        ld b,10
.h:     ld a,(de)
        cp (hl)
        ret nz
        inc hl
        inc de
        djnz .h
        ld a,(hl)                       ; gradients: 1..F12_GRAD_MAX
        or a
        ret z
        cp F12_GRAD_MAX+1
        ret nc
        ld e,a                          ; the size: header, glyphs, gradients
        ld d,1+FLROWS
        mul d,e
        ld hl,F12_HEADER+FLGLYPHS
        add hl,de
        ld bc,(f12_len)
        or a
        sbc hl,bc
        ret nz
        ld a,1
        ld (FLOK),a
        ret
    ENDM

f8_load:    FONT_LOAD f8_name, f8_buf, F8_SIZE_MAX, f8_head, F8_GLYPHS, F8_H, f8_ok
f12_load:   FONT_LOAD f12_name, f12_buf, F12_SIZE_MAX, f12_head, F12_GLYPHS, F12_H, f12_ok

f8_name:    db "ZPDATA/FONT8.ZPF", 0
f8_head:    db "ZPFN", 1, 8, F8_H, F8_FIRST, F8_COUNT, F8_BPR
f12_name:   db "ZPDATA/FONT12.ZPF", 0
f12_head:   db "ZPFN", 1, F12_W, F12_H, F12_FIRST, F12_COUNT, F12_BPR

;------------------------------------------------------------------------------
; Images from the SD card
;------------------------------------------------------------------------------
; An image file (ZPDATA/*.ZPI, tools/imagefile.py; made with
; tools/screen_editor.py): "ZPIM", a version, the box it covers on the
; screen (x word, y byte, width word, height word), then its pixels column
; by column, each column top to bottom: the screen's own order.  $E3
; (L320_NOPAPER, the transparency colour) leaves the screen as it is.  It is
; read IMG_BUF bytes (whole columns) at a time into img_buf and copied to
; the screen, so a screen loads its image when it opens.
IMG_HEADER      equ 16
IMG_BUF         equ 2048

; HL -> the file's name (in $4000-$DFFF: not slot 7): the image drawn.
; Carry set if it couldn't be (no file, not an image, or not on the screen:
; then nothing, or part of it, is drawn).  Pages the file handler into slot
; 7 and the input page back after.
l320_image:
        nextreg CODE_MMU,PAGE_FILE
        ld b,FA_READ|FA_OPEN_EX
        call fh_open
        jp c,.out
        ld (img_fh),a
        ld hl,img_buf                   ; the header
        ld bc,IMG_HEADER
        call fh_read
        jp c,.close
        ld hl,IMG_HEADER
        call .short                     ; (all of it read?)
        jp c,.close
        ld hl,img_buf                   ; "ZPIM", the version
        ld de,img_magic
        ld b,5
.m:     ld a,(de)
        cp (hl)
        jp nz,.bad
        inc hl
        inc de
        djnz .m
        ld e,(hl)                       ; x
        inc hl
        ld d,(hl)
        inc hl
        ld (img_x),de
        ld a,(hl)                       ; y
        inc hl
        ld (img_y),a
        ld e,(hl)                       ; width
        inc hl
        ld d,(hl)
        inc hl
        ld (img_left),de
        ld c,(hl)                       ; height
        inc hl
        ld b,(hl)
        ld (img_h),bc
        ld a,d                          ; width 1..320, x + width <= 320
        or e
        jp z,.bad
        ld hl,(img_x)
        add hl,de
        ld de,L320_W+1
        or a
        sbc hl,de
        jp nc,.bad
        ld a,b                          ; height 1..256, y + height <= 256
        or c
        jp z,.bad
        ld a,(img_y)
        ld l,a
        ld h,0
        add hl,bc
        ld de,L320_H+1
        or a
        sbc hl,de
        jp nc,.bad
        ld hl,IMG_BUF                   ; columns a read: IMG_BUF / height
        ld de,0
.n:     or a
        sbc hl,bc
        jr c,.nd
        inc de
        jr .n
.nd:    ld (img_n),de
.read:  ld hl,(img_left)                ; columns this time: the most a read,
        ld de,(img_n)                   ; or the rest
        or a
        sbc hl,de
        jr nc,.full
        ld de,(img_left)
.full:  ld (img_cols),de
        ld hl,0                         ; bytes: columns * height
        ld bc,(img_h)
.mul:   ld a,d
        or e
        jr z,.md
        add hl,bc
        dec de
        jr .mul
.md:    ld (img_bytes),hl
        ld b,h
        ld c,l
        ld a,(img_fh)
        ld hl,img_buf
        call fh_read
        jr c,.close
        ld hl,(img_bytes)
        call .short
        jr c,.close
        call l320_nopg
        ld de,img_buf                   ; the columns to the screen
.col:   push de
        ld a,(img_y)
        ld e,a
        ld hl,(img_x)
        call l320_addr                  ; HL -> the column's top pixel
        pop de
        ld a,(img_h)                    ; (256: 0, so 256 rows)
        ld b,a
.px:    ld a,(de)
        cp L320_NOPAPER
        jr z,.skip
        ld (hl),a
.skip:  inc de
        inc l
        djnz .px
        ld hl,(img_x)
        inc hl
        ld (img_x),hl
        ld hl,(img_left)
        dec hl
        ld (img_left),hl
        ld hl,(img_cols)
        dec hl
        ld (img_cols),hl
        ld a,h
        or l
        jr nz,.col
        ld hl,(img_left)
        ld a,h
        or l
        jr nz,.read
.close: push af                         ; (carry: failed)
        ld a,(img_fh)
        call fh_close
        pop af
.out:   nextreg CODE_MMU,PAGE_INPUT
        ret
.bad:   scf
        jr .close
; carry set if BC (bytes read) isn't HL
.short: or a
        sbc hl,bc
        ret z
        scf
        ret

img_magic:  db "ZPIM", 1

;------------------------------------------------------------------------------
; The background: a copy of the screen, to put back under text that changes
;------------------------------------------------------------------------------
; A screen with a picture behind its text (the load-out) saves the screen
; once it is drawn (l320_bg_save: pages PAGE_L320_BG on, 80K) and prints its
; text with no paper (L320_NOPAPER); before a field's text changes it puts
; that box of the background back (l320_restore), then prints the new text.
; Both go through slot 4 ($8000, the ULA screen's, unused on these screens:
; put back after).
        ASSERT PAGE_GFX0 + GFX_PAGES_MAX <= PAGE_L320_BG
        ASSERT PAGE_L320_BG + L320_PAGES <= 96

; The screen as it is now, into the background copy
l320_bg_save:
        ld b,0
.pg:    ld a,b
        add a,L320_PAGE0
        nextreg L2SEC_MMU,a
        ld a,b
        add a,PAGE_L320_BG
        nextreg ULA_MMU,a
        push bc
        ld hl,L2SEC_ADDR
        ld de,ULA_ADDR
        ld bc,MEMBANK_SIZE
        ldir
        pop bc
        inc b
        ld a,b
        cp L320_PAGES
        jr nz,.pg
        nextreg ULA_MMU,PAGE_ULA0
        jp l320_nopg

; HL = x, C = y, DE = width, B = height (0 = 256; y + height <= 256): that
; box of the background copy back on the screen
l320_restore:
        ld a,c
        ld (l320_fy),a
        ld a,b
        ld (l320_fh),a
        call l320_nopg
.col:   ld a,d
        or e
        jr z,.done
        call l320_xok
        jr nc,.done
        push de
        push hl
        ld a,(l320_fy)
        ld e,a
        call l320_addr                  ; HL -> the screen's pixel (slot 0)
        ld a,(l320_pg)                  ; its copy: the same place in slot 4
        sub L320_PAGE0
        add a,PAGE_L320_BG
        nextreg ULA_MMU,a
        ex de,hl
        ld hl,ULA_ADDR
        add hl,de
        ld a,(l320_fh)
        ld c,a
        ld b,0
        or a
        jr nz,.n
        inc b                           ; (256)
.n:     ldir
        pop hl
        pop de
        inc hl
        dec de
        jr .col
.done:  nextreg ULA_MMU,PAGE_ULA0
        ret
        ASSERT ULA_ADDR == $8000 && L2SEC_ADDR == 0

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
l320_font:  db L320_F8                  ; the font (L320_F8, L320_F12)
f12_ok:     db 0                        ; 1: the large font is loaded
f8_ok:      db 0                        ; 1: the 8x8 font's file is loaded
f12_len:    dw 0                        ; f12_load: the bytes read
f12_fb:     db 0                        ; l320_char12: the glyph's byte (0, 1),
f12_n:      db 0                        ;   columns left,
f12_gp:     dw 0                        ;   -> the row colours
f12_flat:   ds F12_H                    ; a colour with no gradient
f12_buf:    ds F12_SIZE_MAX             ; the large font's file (f12_load)
f8_buf:     ds F8_SIZE_MAX              ; the 8x8 font's file (f8_load)
img_fh:     db 0                        ; l320_image: the file,
img_x:      dw 0                        ;   the next column's x,
img_y:      db 0                        ;   the top row,
img_h:      dw 0                        ;   the height (1..256),
img_left:   dw 0                        ;   columns still to draw,
img_n:      dw 0                        ;   the most a read,
img_cols:   dw 0                        ;   this read's,
img_bytes:  dw 0                        ;   and its bytes
img_buf:    ds IMG_BUF                  ;   the columns read
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
