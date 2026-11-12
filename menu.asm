;==============================================================================
; Z-POLICE - end screens (8K page PAGE_MENU, runs at $C000 in slot 6)
;
; Game over, game complete and the load error.  Game over (the VTOL or the
; landing pad destroyed) is drawn over the view, on the game's own Layer 2:
; GAME OVER, why, and PRESS SPACE TO CONTINUE.  The others (and game over
; after game complete) are drawn on the ULA screen with opaque paper
; (text.asm), Layer 2 hidden.  The main menu and level complete have their
; own pages (mainmenu.asm, levelend.asm): these go back to the main menu
; through menu_go (zpolice.asm).
;==============================================================================


; The game is over (main_loop: the VTOL or the landing pad destroyed): over
; the last frame of the view, still on the screen, GAME OVER in fire
; colours (the large font), why (VTOL DESTROYED / BASE DESTROYED) and PRESS
; SPACE TO CONTINUE, each with a shadow (l256_title, layer2-320x256.asm,
; mapped into slot 2 for it); the engines off; then, at a new SPACE, the
; main menu.  The HUD stays as it was.
GO_TITLE_Y      equ 34                  ; rows in the view (VIEW_H high)
GO_WHY_Y        equ 54
GO_PROMPT_Y     equ 100
        ASSERT GO_PROMPT_Y + 9 < VIEW_H
game_over_screen:
        ld sp,stack_top
        call shake_off                  ; (the view back in place)
        nextreg CODE_MMU,PAGE_AUDIO     ; silence: the engines off
        call init_audio
        nextreg CODE_MMU,PAGE_INPUT     ; (the keys)
        nextreg L320_MMU,PAGE_L320      ; the text routines, the fonts
        call l256_shown
        ld a,L320_NOPAPER
        ld (l320_paper),a
        ld a,L320_F12
        ld (l320_font),a
        ld hl,txt_game_over             ; GAME OVER, in fire
        ld c,GO_TITLE_Y
        ld de,go_fire
        call l256_title
        ld a,BULLET_COL                 ; why, yellow
        ld (l320_ink),a
        ld hl,txt_go_vtol
        ld a,(vtol_dead)
        or a
        jr nz,.why
        ld hl,txt_go_base
.why:   ld c,GO_WHY_Y
        ld de,0
        call l256_title
        ld a,L320_F8                    ; PRESS SPACE TO CONTINUE, white
        ld (l320_font),a
        ld a,EDGE_COL
        ld (l320_ink),a
        ld hl,txt_continue
        ld c,GO_PROMPT_Y
        ld de,0
        call l256_title
        nextreg OCC_MMU,PAGE_OCC0       ; (slot 2 as the game had it)
        call space_wait
        jp menu_go                      ; (zpolice.asm) the main menu

; GAME OVER's rows: the fire particles' colours, bright to dark (fixed in
; every level's palette)
go_fire:    db FIRE_COL0, FIRE_COL0+4, FIRE_COL0+8, FIRE_COL0+12, FIRE_COL0+16
            db FIRE_COL0+20, FIRE_COL0+24, FIRE_COL0+28, FIRE_COL0+32, FIRE_COL0+36
        ASSERT $ - go_fire == F12_H

txt_game_over:
        db "GAME OVER", 0
txt_go_vtol:
        db "VTOL DESTROYED", 0
txt_go_base:
        db "BASE DESTROYED", 0

; After game complete (the ULA screen up, Layer 2 hidden): GAME OVER on the
; ULA screen until SPACE is pressed, then the main menu
game_over_ula:
        ld sp,stack_top
        call menu_clear
        ld d,11
        ld e,11
        ld c,MENU_TITLE
        ld hl,txt_game_over
        call menu_print
        call space_prompt
        jp menu_go                      ; (zpolice.asm) the main menu

; "PRESS SPACE TO CONTINUE", and wait until SPACE is pressed (newly: one held
; down for firing as the screen came up doesn't count)
LD_PROMPT_ROW   equ 23
space_prompt:
        ld de,LD_PROMPT_ROW<<8 | 4
        ld c,MENU_ATTR
        ld hl,txt_continue
        call menu_print
; Wait until SPACE is pressed, newly
space_wait:
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
        jp game_over_ula                ; then GAME OVER, then the menu

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
