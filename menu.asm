;==============================================================================
; Z-POLICE - main menu (8K page PAGE_MENU, runs at $E000)
;
; Shown after start-up.  Layer 2 is hidden and the menu is drawn on the ULA
; screen with opaque paper.  Every frame it advances the random number
; generator (zrand), so the game doesn't start from the same seed each time
; (the wait for a key press varies), then reads the keys:
;   1  New game   -> newGame (zpolice.asm): level 1
;   2  Save game  (not yet)
;   3  Load game  (not yet)
;   9  Redefine keys (not yet)
; game_over_screen (the landing pad destroyed) shows GAME OVER for 10
; seconds, then returns here.
;==============================================================================

MENU_ATTR       equ P_PANEL<<3 | 7          ; white on the panel colour
MENU_TITLE      equ P_PANEL<<3 | C_YEL      ; yellow

main_menu:
        call menu_clear
        ld hl,menu_text                 ; title and options
.txt:   ld a,(hl)
        cp $FF
        jr z,.loop
        ld d,a                          ; row
        inc hl
        ld e,(hl)                       ; column
        inc hl
        ld c,(hl)                       ; attribute
        inc hl
        call menu_print                 ; HL -> the text, past it after
        jr .txt
.loop:  call menu_frame                 ; one video frame
        call zrand                      ; stir the random number generator
        call kbd_scan
        ld hl,KB_1
        call key_code_pressed
        jp nz,newGame
        ld hl,KB_2                      ; save, load, redefine: to come
        call key_code_pressed
        ld hl,KB_3
        call key_code_pressed
        ld hl,KB_9
        call key_code_pressed
        jr .loop

; The landing pad has been destroyed: GAME OVER for GAME_OVER_FR frames
; (10 seconds), then the main menu
game_over_screen:
        ld sp,stack_top
        call menu_clear
        ld d,11
        ld e,11
        ld c,MENU_TITLE
        ld hl,txt_game_over
        call menu_print
        ld bc,GAME_OVER_FR
.w:     push bc
        call menu_frame
        call zrand                      ; (keep stirring the seed)
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,.w
        jp main_menu

txt_game_over:
        db "GAME OVER", 0

; Hide Layer 2, and blank the ULA screen with opaque paper
menu_clear:
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

; row, column, attribute, text, 0 ... $FF
menu_text:
        db 3, 12, MENU_TITLE
        db "Z-POLICE", 0
        db 8, 8, MENU_ATTR
        db "1. NEW GAME", 0
        db 10, 8, MENU_ATTR
        db "2. SAVE GAME", 0
        db 12, 8, MENU_ATTR
        db "3. LOAD GAME", 0
        db 14, 8, MENU_ATTR
        db "9. REDEFINE KEYS", 0
        db $FF

        INCLUDE "tables_font.inc"       ; font8: ASCII 32-95
