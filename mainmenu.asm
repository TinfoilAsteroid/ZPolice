;==============================================================================
; Z-POLICE - main menu (8K page PAGE_MAINMENU, runs at $C000 in slot 6)
;
; Shown after start-up, after game over, a load error, and quitting from the
; pause (menu_go, zpolice.asm, pages it in).  Drawn on Layer 2 at 320x256
; (screen320, text.asm; layer2-320x256.asm in slot 2) in the large font
; (26 x 25 characters).  Every frame it
; advances the random number generator (zrand), so the game doesn't start
; from the same seed each time (the wait for a key press varies), then reads
; the keys:
;   1  New game   -> newGame (zpolice.asm): level 1
;   2  Continue   -> the save game (made by save and quit, from the pause:
;                 game_pause), its level at its wave (load_save,
;                 continue_game, zpolice.asm); NO SAVED GAME if there's none
;   9  Redefine keys -> keydef_screen (keydef.asm)
; The game start puts the game's Layer 2 back (l2_game_mode).
;==============================================================================

MM_COL          equ 2               ; the options' column
MM_NOSAVE_ROW   equ 18

main_menu:
        call screen320                  ; (text.asm) the input page in slot 7
        ld hl,mm_text                   ; title and options
        call l320_print_list
.loop:  call menu_frame                 ; one video frame
        call zrand                      ; stir the random number generator
        call kbd_scan
        ld hl,KB_1
        call key_code_pressed
        jp nz,newGame
        ld hl,KB_9                      ; redefine keys
        call key_code_pressed
        jp nz,keydef_go                 ; (zpolice.asm)
        ld hl,KB_2                      ; continue the save game
        call key_code_pressed
        jr z,.loop
        call load_save                  ; (zpolice.asm; pages the file
        jp nc,continue_game             ; handler in)
        nextreg CODE_MMU,PAGE_INPUT     ; none (or not usable): say so
        ld de,MM_NOSAVE_ROW<<8 | (F12_COLS-13)/2
        ld c,SCR_BAD
        ld hl,txt_no_save
        call l320_print_at
        jr .loop

; row, column, colour, text, 0 ... $FF
mm_text:
        db 3, (F12_COLS-8)/2, SCR_TITLE
        db "Z-POLICE", 0
        db 9, MM_COL, SCR_TEXT
        db "1. NEW GAME", 0
        db 11, MM_COL, SCR_TEXT
        db "2. CONTINUE SAVED GAME", 0
        db 13, MM_COL, SCR_TEXT
        db "9. REDEFINE KEYS", 0
        db $FF
txt_no_save:
        db "NO SAVED GAME", 0
