;==============================================================================
; Z-POLICE - text screens (resident): the ULA routines the menu screens
; (menu.asm) and the load-out screen (loadout.asm) share, from whichever
; page is in slot 6.  Layer 2 hidden, the ULA screen with opaque paper,
; 8x8 characters (font8, ASCII 32-95) by row and column with an attribute.
;==============================================================================

MENU_ATTR       equ P_PANEL<<3 | 7          ; white on the panel colour
MENU_TITLE      equ P_PANEL<<3 | C_YEL      ; yellow
MENU_OK         equ P_PANEL<<3 | C_OK       ; green
MENU_BAD        equ P_PANEL<<3 | C_WARN     ; red

; Hide Layer 2, silence the AY chips, and blank the ULA screen with opaque
; paper
menu_clear:
        nextreg CODE_MMU,PAGE_SPRITES   ; no HUD sprites over the menu
        call spr_hide_all
        call spr_update
        nextreg CODE_MMU,PAGE_AUDIO     ; and silence: the engines off
        call init_audio                 ; (audio.asm)
        nextreg CODE_MMU,PAGE_INPUT     ; (the menu reads the keys)
        ld bc,$123B
        xor a
        out (c),a
        ld hl,ULA_BMP
        ld de,ULA_BMP+1
        ld bc,$1800-1
        ld (hl),0
        ldir
        ld hl,ULA_ATTR
        ld de,ULA_ATTR+1
        ld bc,$300-1
        ld (hl),MENU_ATTR
        ldir
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

        INCLUDE "tables_font.inc"       ; font8: ASCII 32-95
