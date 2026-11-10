;==============================================================================
; Z-POLICE - end screens (8K page PAGE_MENU, runs at $C000 in slot 6)
;
; Game over, game complete and the load error.  Layer 2 is hidden and they
; are drawn on the ULA screen with opaque paper (text.asm).  The main menu
; and level complete have their own pages (mainmenu.asm, levelend.asm):
; these go back to the main menu through menu_go (zpolice.asm).
; game_over_screen (the landing pad destroyed) shows GAME OVER until SPACE
; is pressed, then the main menu.
;==============================================================================


; The game is over: GAME OVER until SPACE is pressed, then the main menu
game_over_screen:
        ld sp,stack_top
        call menu_clear
        ld d,11
        ld e,11
        ld c,MENU_TITLE
        ld hl,txt_game_over
        call menu_print
        call space_prompt
        jp menu_go                      ; (zpolice.asm) the main menu

txt_game_over:
        db "GAME OVER", 0

; "PRESS SPACE TO CONTINUE", and wait until SPACE is pressed (newly: one held
; down for firing as the screen came up doesn't count)
LD_PROMPT_ROW   equ 23
space_prompt:
        ld de,LD_PROMPT_ROW<<8 | 4
        ld c,MENU_ATTR
        ld hl,txt_continue
        call menu_print
.w:     call menu_frame
        call zrand                      ; (keep stirring the seed)
        call kbd_scan                   ; (the input page: menu_clear)
        ld hl,KB_SPACE
        call key_code_pressed
        jr z,.w
        ret

txt_continue:
        db "PRESS SPACE TO CONTINUE", 0

; The last level (LEVEL_LAST) complete: CONGRATULATIONS for GAME_DONE_FR
; frames (10 seconds), then GAME OVER and the main menu
GAME_DONE_FR    equ 500             ; 10 s of 50 Hz frames
game_complete_screen:
        call menu_clear
        ld hl,txt_congrats              ; row, column, attribute, text, 0 ...
.txt:   ld a,(hl)
        cp $FF
        jr z,.wait
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld c,(hl)
        inc hl
        call menu_print                 ; HL past the text after
        jr .txt
.wait:  ld bc,GAME_DONE_FR
.w:     push bc
        call menu_frame
        call zrand                      ; (keep stirring the seed)
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,.w
        jp game_over_screen             ; then GAME OVER, then the menu

txt_congrats:
        db 8, 8, MENU_TITLE
        db "CONGRATULATIONS", 0
        db 11, 5, MENU_ATTR
        db "ALL 50 LEVELS COMPLETE", 0
        db 13, 6, MENU_ATTR
        db "THE CITIES ARE SAFE", 0
        db $FF
        ASSERT LEVEL_LAST == 50         ; (the message says so)

; newGame couldn't load the level's files (ZPDATA/LEVELnn.ZPL, its city):
; say so for LOAD_ERR_FR frames, then the main menu
LOAD_ERR_FR     equ 250             ; 5 s of 50 Hz frames
load_error_screen:
        ld sp,stack_top
        call menu_clear
        ld d,10
        ld e,7
        ld c,MENU_TITLE
        ld hl,txt_load_err
        call menu_print
        ld d,12
        ld e,3
        ld c,MENU_ATTR
        ld hl,txt_load_err2
        call menu_print
        ld bc,LOAD_ERR_FR
.w:     push bc
        call menu_frame
        call zrand                      ; (keep stirring the seed)
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,.w
        jp menu_go                      ; (zpolice.asm) the main menu

txt_load_err:
        db "CANNOT LOAD LEVEL", 0
txt_load_err2:
        db "ZPDATA MUST BE BESIDE THE NEX", 0
