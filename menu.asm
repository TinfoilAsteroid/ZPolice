;==============================================================================
; Z-POLICE - end screens (8K page PAGE_MENU, runs at $C000 in slot 6)
;
; Game over, game complete and the load error.  Game over (the VTOL or the
; landing pad destroyed) is drawn over the view, on the game's own Layer 2:
; GAME OVER, why, and PRESS SPACE TO CONTINUE.  Game complete and the load
; error are Layer 2 320x256 screens in the large font (screen320, as the
; level complete).  The main menu and level complete have their
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

; Wait until SPACE is pressed, newly (one held down for firing as the
; screen came up doesn't count)
space_wait:
.w:     call menu_frame
        call zrand                      ; (keep stirring the seed)
        call kbd_scan                   ; (the input page: screen320)
        ld hl,KB_SPACE
        call key_code_pressed
        jr z,.w
        ret

txt_continue:
        db "PRESS SPACE TO CONTINUE", 0

; The last level (LEVEL_LAST) complete: CONGRATULATIONS on a 320x256 screen
; in the large font, and PRESS SPACE TO CONTINUE, until SPACE is pressed;
; then the main menu
GC_PROMPT_ROW   equ 23              ; (the large font's grid: 26 x 25)
game_complete_screen:
        call screen320                  ; (text.asm) the input page in slot 7
        ld hl,txt_congrats              ; row, column, ink, text, 0 ...
        call l320_print_list
        call space_wait
        jp menu_go                      ; (zpolice.asm) the main menu

txt_congrats:                           ; (the large font's grid, centred)
        db 8, (F12_COLS-15)/2, SCR_TITLE
        db "CONGRATULATIONS", 0
        db 11, (F12_COLS-22)/2, SCR_TEXT
        db "ALL 50 LEVELS COMPLETE", 0
        db 13, (F12_COLS-19)/2, SCR_TEXT
        db "THE CITIES ARE SAFE", 0
        db GC_PROMPT_ROW, (F12_COLS-23)/2, SCR_HELP
        db "PRESS SPACE TO CONTINUE", 0
        db $FF
        ASSERT LEVEL_LAST == 50         ; (the message says so)

; A level's files couldn't be read (its level file, its city: next_level;
; the figures' or the devil's graphics: wave_prepare): say so on a 320x256
; screen in the large font for LOAD_ERR_FR frames, then the main menu
LOAD_ERR_FR     equ 250             ; 5 s of 50 Hz frames
load_error_screen:
        ld sp,stack_top
        call screen320                  ; (text.asm) the input page in slot 7
        ld hl,txt_load_err              ; row, column, ink, text, 0 ...
        call l320_print_list
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

txt_load_err:                           ; (the large font's grid, centred)
        db 9, (F12_COLS-17)/2, SCR_BAD
        db "CANNOT LOAD LEVEL", 0
        db 12, (F12_COLS-21)/2, SCR_TEXT
        db "PUT THE ZPDATA FOLDER", 0
        db 13, (F12_COLS-18)/2, SCR_TEXT
        db "BESIDE ZPOLICE.NEX", 0
        db $FF
