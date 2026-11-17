;==============================================================================
; Z-POLICE - the hardware tilemap (in the sprites page, PAGE_SPRITES, at
; $E000 in slot 7: page it in with nextreg CODE_MMU,PAGE_SPRITES before
; calling)
;
; The Next's tilemap layer: a grid of 8x8 tiles, 40x32 (or 80x32) over the
; whole 320x256 screen, drawn with the ULA (in front of it here, $6B bit 0;
; its pixel index 0 transparent, $4C).  Its map and its tile definitions
; must be in bank 5 or the first half of bank 7: page 14 (PAGE_TILES),
; which holds the start-up code (initialise.asm) until start-up is done and
; is free after.  In page 14:
;   $0000-$09FF  the map: 2 bytes a cell (tile, attribute), row by row,
;                40 x 32 (the 40-column mode only: the screen's 320 x 256)
;   $0A00-$1FFF  the tile definitions: 176 tiles of 32 bytes (4 bits a
;                pixel, 2 pixels a byte, the left one in the high nibble,
;                row by row): 0-63 the font (font8, text.asm: ASCII 32-95,
;                ink 1 on index 0), 64-175 free (tm_defs; the console's)
; The routines map page 14 into slot 0 to write it ($0000: the scratch
; slot, which get_sin and the Layer 2 drawing map for themselves), and
; leave it there.
;
; A cell's attribute: bits 7-4 its palette offset (tile pixel n shows
; tilemap palette entry offset*16+n), bit 3 mirror x, bit 2 mirror y, bit
; 1 rotate, bit 0 1: the ULA over it.  tm_init sets the first tilemap
; palette: for each offset 0-15, entry 1 (the font's ink) one of
; tm_inks (white, red, green ...); tm_colour changes one.
;
; Routines (preserve IX, IY):
;   tm_init      A = TM_40 (the columns: 40 only): the map cleared, the font's
;                tiles, the palette, the registers; the tilemap shown
;   tm_off       hidden (the map and tiles kept); tm_on shows it again
;   tm_clear     every cell blank (tile TM_BLANK, attribute 0)
;   tm_tile      D = row, E = column, A = tile, C = attribute
;   tm_putc      D, E, A = an ASCII character, C = attribute; E steps on
;   tm_print     D, E, HL -> text (ending 0), C = attribute; HL past the 0
;   tm_defs      HL -> definitions (32 bytes each), A = first tile, B = how
;                many
;   tm_colour    A = palette offset 0-15, E = its ink colour (RRRGGGBB)
;   tm_scroll    HL = x offset (0-319), A = y (0-255)
;   tm_pal16     A = palette offset 0-15, HL -> its 16 colours (RRRGGGBB)
;   tm_pal16_9   A = palette offset 0-15, HL -> its 16 colours, 9-bit (2
;                bytes each: RRRGGGBB, then blue's low bit in bit 0)
;   console_on   the VTOL console round the view (in the game): below
;==============================================================================

PAGE_TILES      equ PAGE_INIT       ; page 14: bank 7's first half
        ASSERT PAGE_TILES == 14
TM_MMU          equ SIN_MMU         ; (slot 0: the scratch slot)
TM_ADDR         equ SIN_ADDR        ; $0000
TM_MAP          equ 0               ; offsets in page 14
TM_DEFS         equ $0A00
TM_TILE_SIZE    equ 32
TM_TILES        equ ($2000-TM_DEFS)/TM_TILE_SIZE    ; 176
TM_FONT_FIRST   equ 32              ; the font: ASCII 32-95 as tiles 0-63
TM_FONT_N       equ 64
TM_FREE         equ TM_FONT_N       ; the first free tile
TM_BLANK        equ 0               ; (ASCII space: every pixel index 0)
TM_INK          equ 1               ; the font's pixels' index
TM_ROWS         equ 32
TM_40           equ 40
        ASSERT TM_MAP + TM_40*TM_ROWS*2 <= TM_DEFS && TM_TILES >= TM_FONT_N
        ASSERT TM_TILES <= 256          ; (the 256-tile mode)

; NextRegs
NR_TM_CTRL      equ $6B             ; bit 7 on, 6 80 columns, 5 no
TM_ON           equ %10000000       ;   attributes, 4 second palette, 3 text
TM_80COL        equ %01000000       ;   mode, 1 512 tiles, 0 over the ULA
TM_OVER_ULA     equ %00000001
NR_TM_ATTR      equ $6C             ; the default attribute (no attributes)
NR_TM_MAP       equ $6E             ; bit 7: bank 7; bits 5-0: offset / 256
NR_TM_DEFS      equ $6F
NR_TM_TRANS     equ $4C             ; the transparent pixel index (0-15)
NR_TM_CLIP      equ $1B             ; x1, x2, y1, y2 (x / 2 at 40 columns)
NR_TM_XMSB      equ $2F
NR_TM_XLSB      equ $30
NR_TM_Y         equ $31
TM_BANK7        equ %10000000

tm_init:
        ld (tm_cols),a
        add a,a
        ld (tm_stride),a
        call tm_page
        call tm_clear
        ld hl,font8                     ; the font's tiles
        ld de,TM_ADDR+TM_DEFS
        ld bc,TM_FONT_N*8               ; its rows (each: 4 bytes of 2 pixels)
.f:     push bc
        ld c,(hl)
        inc hl
        ld b,4
.px:    xor a
        rl c                            ; the left pixel: the high nibble
        jr nc,.l0
        ld a,TM_INK<<4
.l0:    rl c
        jr nc,.r0
        or TM_INK
.r0:    ld (de),a
        inc de
        djnz .px
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,.f
        call tm_palette
        nextreg NR_TM_MAP,TM_BANK7 | (TM_MAP>>8)
        nextreg NR_TM_DEFS,TM_BANK7 | (TM_DEFS>>8)
        nextreg NR_TM_TRANS,0           ; pixel index 0: see through
        nextreg NR_TM_ATTR,0
        ld hl,0
        xor a
        call tm_scroll
        nextreg $1C,%00001000           ; the clip window: all of it
        nextreg NR_TM_CLIP,0
        nextreg NR_TM_CLIP,159
        nextreg NR_TM_CLIP,0
        nextreg NR_TM_CLIP,255
        ; fall through

; Show it
tm_on:
        nextreg NR_TM_CTRL,TM_ON | TM_OVER_ULA      ; (40 columns)
        ret

; Hide it (the map and the tiles kept)
tm_off:
        nextreg NR_TM_CTRL,0
        ret

; Page 14 into slot 0, to write the map and the tiles.  Preserves all but A.
tm_page:
        nextreg TM_MMU,PAGE_TILES
        ret

; Every cell blank: TM_BLANK, attribute 0
tm_clear:
        call tm_page
        ld hl,TM_ADDR+TM_MAP
        ld de,TM_ADDR+TM_MAP+1
        ld bc,TM_40*TM_ROWS*2-1
        ld (hl),TM_BLANK
        ldir
        ASSERT TM_BLANK == 0
        ret

; D = row, E = column -> HL = its cell in the map (page 14 in slot 0)
tm_at:
        call tm_page
        push de
        ld a,(tm_stride)
        ld e,a
        mul d,e                         ; row * the row's bytes
        ex de,hl
        pop de
        ld a,e
        add a,a                         ; + column * 2
        add hl,a
        ret
        ASSERT TM_ADDR+TM_MAP == 0

; D = row, E = column: tile A, attribute C
tm_tile:
        push hl
        push af
        call tm_at
        pop af
        ld (hl),a
        inc hl
        ld (hl),c
        pop hl
        ret

; A = an ASCII character at D, E, attribute C; E steps on.  Lower case is
; shown as upper case; anything else not in the font as a space.
tm_putc:
        cp 'a'
        jr c,.u
        cp 'z'+1
        jr nc,.u
        sub 32
.u:     sub TM_FONT_FIRST
        cp TM_FONT_N
        jr c,.ok
        ld a,TM_BLANK
.ok:    call tm_tile
        inc e
        ret

; HL -> text ending 0, at D, E, attribute C.  HL ends past the 0.
tm_print:
        ld a,(hl)
        inc hl
        or a
        ret z
        call tm_putc
        jr tm_print

; HL -> tile definitions (TM_TILE_SIZE bytes each), A = the first tile
; (TM_FREE..), B = how many
tm_defs:
        push bc
        call tm_page
        ld e,a                          ; DE = TM_DEFS + A * 32
        ld d,TM_TILE_SIZE
        mul d,e
        ld a,d
        add a,high (TM_ADDR+TM_DEFS)
        ld d,a
        pop bc
        ld c,0                          ; BC = B * 32
        srl b
        rr c
        srl b
        rr c
        srl b
        rr c
        ldir
        ret
        ASSERT TM_TILE_SIZE == 32 && low (TM_ADDR+TM_DEFS) == 0

; The first tilemap palette: for each of the 16 offsets, entry 0 black
; (see through anyway) and entry 1 (the font's ink) from tm_inks; the rest
; black
tm_palette:
        ld a,$43
        call read_nextreg               ; (zpolice.asm) the layers' choices
        ld (tm_nr43),a
        and %00001111                   ; kept; edit the tilemap's first
        or %00110000                    ; palette, auto-incrementing
        nextreg $43,a
        nextreg $40,0
        ld hl,tm_inks
        ld c,16
.o:     xor a
        nextreg $41,a                   ; 0
        ld a,(hl)
        inc hl
        nextreg $41,a                   ; 1: the ink
        ld b,14
.z:     xor a
        nextreg $41,a                   ; 2-15
        djnz .z
        dec c
        jr nz,.o
        ld a,(tm_nr43)                  ; (as it was)
        nextreg $43,a
        ret
        ASSERT TM_INK == 1

; A = palette offset 0-15, E = its ink colour (RRRGGGBB)
tm_colour:
        and 15
        ld d,a
        ld a,$43
        call read_nextreg
        ld (tm_nr43),a
        and %00001111
        or %00110000
        nextreg $43,a
        ld a,d                          ; entry offset * 16 + TM_INK
        add a,a
        add a,a
        add a,a
        add a,a
        add a,TM_INK
        nextreg $40,a
        ld a,e
        nextreg $41,a
        ld a,(tm_nr43)
        nextreg $43,a
        ret

; HL = x offset, A = y offset
tm_scroll:
        nextreg NR_TM_Y,a
        ld a,h
        and 3
        nextreg NR_TM_XMSB,a
        ld a,l
        nextreg NR_TM_XLSB,a
        ret

; The inks of the 16 palette offsets (attribute bits 7-4)
tm_inks:    db $FF, $E0, $1C, $FC, $1F, $E3, $F4, $6D   ; white, red, green,
            db $92, $03, $10, $80, $B6, $FD, $9F, $49   ; yellow, cyan, magenta,
                                                        ; amber, grey ...
tm_cols:    db TM_40                    ; the columns (TM_40)
tm_stride:  db 2*TM_40                  ;   a row's bytes in the map
tm_nr43:    db 0                        ; (tm_palette: NextReg $43 kept)
con_attr:   db 0                        ; (console_on: a cell's bank)

; A = palette offset 0-15, HL -> 16 colours (RRRGGGBB): its entries
; offset*16 .. +15 in the first tilemap palette
tm_pal16:
        and 15
        add a,a
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,$43
        call read_nextreg
        ld (tm_nr43),a
        and %00001111
        or %00110000
        nextreg $43,a
        ld a,d
        nextreg $40,a
        ld b,16
.c:     ld a,(hl)
        inc hl
        nextreg $41,a
        djnz .c
        ld a,(tm_nr43)
        nextreg $43,a
        ret

; A = palette offset 0-15, HL -> 16 colours, 9-bit (2 bytes each: RRRGGGBB,
; then the third blue bit in bit 0; NextReg $44, which steps on after the
; second): its entries offset*16 .. +15 in the first tilemap palette.  HL
; ends past them.
tm_pal16_9:
        and 15
        add a,a
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,$43
        call read_nextreg
        ld (tm_nr43),a
        and %00001111
        or %00110000
        nextreg $43,a
        ld a,d
        nextreg $40,a
        ld b,32                         ; (16 colours, 2 bytes each)
.c:     ld a,(hl)
        inc hl
        nextreg $44,a
        djnz .c
        ld a,(tm_nr43)
        nextreg $43,a
        ret

;------------------------------------------------------------------------------
; The VTOL console (next_level, each level's start): the tilemap at 40
; columns with the console's tiles (tables_console.inc, tools/
; consoletiles.py: TM_FREE on), their colours (CON_BANKS banks of 16, 9-bit,
; bank k at tilemap palette offset CON_OFFSET0 + k: each tile has its bank,
; console_tbank) and its map (console_map: 2 bytes a cell, the tile's
; place in the console's tiles + 1 (0: see-through), then its flags, the
; attribute's bit 3 mirror x, bit 2 mirror y, bit 1 rotate, bit 0 the ULA
; over it: so the tilemap isn't forced over the ULA, $6B bit 0).  The font's colours (tm_inks) stay at offset 0
; only: the banks take the other offsets.  Under the HUD's
; sprites (the compass, the humans, the view's frame) and beside the ULA
; panel; the vision modes leave it as it is (its own palette).  menu_quiet
; (text.asm) hides it on the screens outside the game.
;------------------------------------------------------------------------------
console_on:
        ld a,TM_40
        call tm_init                    ; (cleared, the font, shown)
        ld hl,console_defs
        ld a,TM_FREE
        ld b,CON_N
        call tm_defs
        ld hl,console_pal               ; the banks' colours
        ld a,CON_OFFSET0
.bk:    push af
        call tm_pal16_9
        pop af
        inc a
        cp CON_OFFSET0+CON_BANKS
        jr nz,.bk
        call tm_page
        ld hl,console_map
        ld de,TM_ADDR+TM_MAP
        ld bc,TM_40*TM_ROWS
.lp:    ld a,(hl)                       ; its tile's place + 1
        inc hl
        or a
        jr z,.e                         ; none: see-through
        push hl
        ld hl,console_tbank-1           ; its bank (its attribute's top half;
        add hl,a                        ; BC is the cells' count)
        ld l,(hl)
        ld h,a
        ld a,l
        ld (con_attr),a
        ld a,h
        pop hl
        add a,TM_FREE-1
        ld (de),a                       ; the tile (TM_FREE + its place),
        inc de
        ld a,(hl)                       ; its flags (mirrors, rotation),
        inc hl
        push hl
        ld hl,con_attr                  ; and its bank's colours
        or (hl)
        pop hl
        ld (de),a
        jr .n
.e:     inc hl                          ; (its flags: none)
        ld (de),a
        inc de
        ld (de),a
.n:     inc de
        dec bc
        ld a,b
        or c
        jr nz,.lp
        nextreg NR_TM_CTRL,TM_ON        ; each tile's attribute bit 0 says
        ret                             ; which is on top: it or the ULA
        ASSERT CON_N <= TM_TILES-TM_FREE && CON_N < 128
        ASSERT CON_OFFSET0 >= 1 && CON_OFFSET0+CON_BANKS <= 16

        INCLUDE "tables_console.inc"    ; console_pal, console_defs,
                                        ; console_map (gentables.py)
