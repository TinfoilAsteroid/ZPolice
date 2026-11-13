;==============================================================================
; Z-POLICE - text (resident): menu_print / menu_char, 8x8 characters
; (font8, ASCII 32-95) on the ULA screen by row and column with an
; attribute, for the boxes over the game (PAUSED, PREPARE FOR COMBAT); and
; screen320, the start of a Layer 2 320x256 screen (every screen outside the
; game: layer2-320x256.asm draws them), from whichever page is in slot 6.
;==============================================================================

MENU_ATTR       equ P_PANEL<<3 | 7          ; white on the panel colour
MENU_TITLE      equ P_PANEL<<3 | C_YEL      ; yellow
MENU_OK         equ P_PANEL<<3 | C_OK       ; green
MENU_BAD        equ P_PANEL<<3 | C_WARN     ; red

; A Layer 2 320x256 screen (the main menu, redefine keys): sprites hidden,
; the AY chips silent, the keys in slot 7, the 320x256 page in slot 2 (and
; left there: the screen draws with it), cleared with a frame and shown
; (l320_screen, layer2-320x256.asm)
screen320:
        call menu_quiet
        nextreg L320_MMU,PAGE_L320
        jp l320_screen

; No HUD sprites, silence (the engines off), and the input page in slot 7
; (the screens read the keys)
menu_quiet:
        nextreg CODE_MMU,PAGE_SPRITES
        call spr_hide_all
        call spr_update
        nextreg CODE_MMU,PAGE_AUDIO
        call init_audio                 ; (audio.asm)
        nextreg CODE_MMU,PAGE_INPUT
        ret

; D = character row, E = column, C = attribute, HL -> text ending 0.
; Prints it; HL ends past the 0.
menu_print:
.ch:    ld a,(hl)
        inc hl
        or a
        ret z
        push hl
        push de
        push bc
        call menu_char
        pop bc
        pop de
        pop hl
        inc e
        jr .ch

; A = ASCII 32-95, D = row, E = column, C = attribute: draw one character
menu_char:
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        push de
        ld de,font8
        add hl,de                       ; HL -> its 8 bytes
        pop de
        push de
        ld a,d                          ; attribute: ULA_ATTR + row*32 + col
        rrca
        rrca
        rrca
        ld b,a
        and %11100000
        or e
        push hl
        ld l,a
        ld a,b
        and %00000011
        add a,high ULA_ATTR
        ld h,a
        ld (hl),c
        pop hl
        pop de
        ld a,d                          ; bitmap: third, row in third, column
        and %00011000
        add a,high ULA_BMP
        ld b,a
        ld a,d
        and 7
        rrca
        rrca
        rrca
        or e
        ld e,a
        ld d,b                          ; DE -> the cell's top line
        ld b,8
.l:     ld a,(hl)
        ld (de),a
        inc hl
        inc d
        djnz .l
        ret

; Wait for the start of the next video frame (the raster reaching line 192)
menu_frame:
.in:    call menu_line                  ; let any current blanking end
        jr nc,.in
.out:   call menu_line                  ; then wait for the next one
        jr c,.out
        ret

; Carry clear if the raster is at line 192 or later (blanking).  The line is
; read as high byte ($1E), low byte ($1F), high byte again: if the high
; byte changed in between (line 255 -> 256) the pair is torn, so read again.
menu_line:
        ld bc,$243B
        ld a,$1E
        out (c),a
        inc b
        in e,(c)                        ; high byte
        dec b
        ld a,$1F
        out (c),a
        inc b
        in d,(c)                        ; low byte
        dec b
        ld a,$1E
        out (c),a
        inc b
        in a,(c)
        cp e
        jr nz,menu_line                 ; torn: again
        and 1
        ret nz                          ; line >= 256 (carry clear)
        ld a,d
        cp 192
        ret

        INCLUDE "tables_font.inc"       ; font8: ASCII 32-95 (ZPDATA/FONT8.ZPF's,
                                        ; at build time and again at start-up:
                                        ; fonts_load)
