;==============================================================================
; Z-POLICE - main menu (8K page PAGE_MENU, runs at $C000 in slot 6)
;
; Shown after start-up.  Layer 2 is hidden and the menu is drawn on the ULA
; screen with opaque paper.  Every frame it advances the random number
; generator (zrand), so the game doesn't start from the same seed each time
; (the wait for a key press varies), then reads the keys:
;   1  New game   -> newGame (zpolice.asm): level 1
;   2  Continue   -> the save game (made by save and quit, from the pause:
;                 game_pause), its level at its wave (load_save,
;                 continue_game, zpolice.asm); NO SAVED GAME if there's none
;   9  Redefine keys -> keydef_screen (keydef.asm)
; game_over_screen (the landing pad destroyed) shows GAME OVER for 10
; seconds, then returns here.
;==============================================================================


main_menu:
        nextreg CODE_MMU,PAGE_INPUT     ; the input page at $E000 (this page: $C000)
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
        ld hl,KB_9                      ; redefine keys
        call key_code_pressed
        jp nz,keydef_go                 ; (zpolice.asm)
        ld hl,KB_2                      ; continue the save game
        call key_code_pressed
        jr z,.loop
        call load_save                  ; (zpolice.asm; pages the file
        jp nc,continue_game             ; handler in)
        nextreg CODE_MMU,PAGE_INPUT     ; none (or not usable): say so
        ld de,18<<8 | 9
        ld c,MENU_BAD
        ld hl,txt_no_save
        call menu_print
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

; The level's last wave is wiped out: LEVEL COMPLETE, until SPACE is pressed
; (newly: one held down for firing as the level ended doesn't count), then
; the load-out screen and the next level (next_level, zpolice.asm)
LD_PROMPT_ROW   equ 23              ; "PRESS SPACE TO CONTINUE" (under the
                                    ; reward lines, SA_ROW0..SA_ROW_MAX)
level_complete_screen:
        ld sp,stack_top
        ld a,(level)                    ; the last level: the whole game
        cp LEVEL_LAST
        jp nc,game_complete_screen
        call menu_clear
        ld d,8
        ld e,9
        ld c,MENU_TITLE
        ld hl,txt_level_done
        call menu_print
        call rearm_all                  ; every weapon's ammo full again
        call hum_unload_all             ; (human.asm) those aboard: rescued
        call salvage_award              ; the humans saved: salvage, unlocks
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
        ld hl,level
        inc (hl)
        jp loadout_go                   ; (zpolice.asm) the load-out screen,
                                        ; then the next level

txt_level_done:
        db "LEVEL COMPLETE", 0
txt_continue:
        db "PRESS SPACE TO CONTINUE", 0
        ASSERT LD_PROMPT_ROW > SA_ROW_MAX

;------------------------------------------------------------------------------
; End of a level: every slot's weapon gets its full load again (wpn_cfg,
; WCFG_LOAD; AMMO_INF for the guns, 0 for an empty slot), and the screen
; says so
rearm_all:
        ld ix,wpn_slots
        ld b,WPN_SLOTS
.lp:    ld a,(ix+WPN_TYPE)
        call wpn_cfg_ptr                ; (resident; preserves BC)
        ld a,(hl)                       ; WCFG_LOAD
        ld (ix+WPN_AMMO),a
        inc ix
        inc ix
        djnz .lp
        ld d,14
        ld e,7
        ld c,MENU_ATTR
        ld hl,txt_sa_rearm
        jp menu_print
        ASSERT WCFG_LOAD == 0

;------------------------------------------------------------------------------
; Salvage, at the end of a level: each human saved this level (saved) adds
; a salvage point (salvage_points).  Every point total in salvage_tab that
; the new total reaches (passed over from the old one) gives its rewards: a
; weapon unlocked (one more of that type in wpn_stock, for the load-out page)
; and / or (SA_* flags) a full repair (vtol_hp = VTOL_HP) or the booster
; module (fitted at once, its tank full).  After the table's last total,
; SALVAGE_TAIL, every SALVAGE_STEP more points is a full repair.  Shown on
; the LEVEL COMPLETE screen: the humans saved, the salvage, and a line for
; each reward (rows SA_ROW0..SA_ROW_MAX; any more aren't shown).
;------------------------------------------------------------------------------
SA_REPAIR       equ 1               ; salvage_tab rewards (flags): full repair,
SA_BOOSTER      equ 2               ;   the booster module
SALVAGE_TAIL    equ 145
SALVAGE_STEP    equ 5
SA_ROW0         equ 16
SA_ROW_MAX      equ 22
salvage_award:
        ld d,11                         ; HUMANS SAVED n
        ld e,7
        ld c,MENU_ATTR
        ld hl,txt_sa_saved
        call menu_print
        ld a,(saved)
        ld l,a
        ld h,0
        ld de,11<<8 | 21
        call menu_num
        ld hl,(salvage_points)          ; the new total
        ld (sa_old),hl
        ld a,(saved)
        add hl,a
        ld (salvage_points),hl
        ld d,12                         ; SALVAGE n
        ld e,7
        ld c,MENU_ATTR
        ld hl,txt_sa_points
        call menu_print
        ld hl,(salvage_points)
        ld de,12<<8 | 21
        call menu_num
        ld a,SA_ROW0
        ld (sa_row),a
        ld hl,salvage_tab
.lp:    ld e,(hl)                       ; DE = its points total
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        and e
        inc a
        jr z,.tail                      ; ($FFFF: the end)
        ld a,(hl)                       ; B = weapon, C = SA_* rewards
        ld b,a
        inc hl
        ld c,(hl)
        inc hl
        push hl
        call sa_reached
        call c,sa_reward
        pop hl
        jr .lp
.tail:  ld de,SALVAGE_TAIL              ; then a repair every SALVAGE_STEP
.tl:    ld hl,SALVAGE_STEP
        add hl,de
        ex de,hl
        ld hl,(salvage_points)
        or a
        sbc hl,de
        ret c                           ; beyond the new total
        ld b,WPN_NONE
        ld c,SA_REPAIR
        push de
        call sa_reached
        call c,sa_reward
        pop de
        jr .tl

; Carry set if total DE is reached this time: sa_old < DE <= salvage_points.
; Preserves BC, DE.
sa_reached:
        ld hl,(sa_old)
        or a
        sbc hl,de
        jr c,.lo
        or a                            ; old >= DE: reached before
        ret
.lo:    ld hl,(salvage_points)
        or a
        sbc hl,de                       ; new - DE: no carry if reached
        ccf
        ret

; Reward: B = weapon type (WPN_NONE: none) unlocked, C = SA_* flags: a full
; repair, the booster module.  A line on the screen for each.
sa_reward:
        ld a,b
        or a
        jr z,.rep
        ld hl,wpn_unlocked              ; unlocked (load-out screen lists it)
        add hl,a
        ld (hl),1
        ld hl,wpn_stock
        add hl,a
        inc (hl)
        jr nz,.nm
        dec (hl)                        ; (at most 255)
.nm:    push bc
        ld a,b                          ; "NEW " and its name
        add a,a
        ld hl,wpn_names
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        ld hl,txt_sa_new
        ld e,7
        call sa_line
        pop hl
        ld e,11
        call sa_line.at
        call sa_next
        pop bc
.rep:   bit 1,c                         ; the booster module: fitted, full
        jr z,.rp
        ASSERT SA_BOOSTER == 1<<1
        ld a,1
        ld (boost_fitted),a
        ld a,BOOST_FUEL_MAX
        ld (boost_fuel),a
        push bc
        ld hl,txt_sa_booster
        ld e,7
        call sa_line
        call sa_next
        pop bc
.rp:    bit 0,c
        ret z
        ASSERT SA_REPAIR == 1<<0
        ld a,VTOL_HP                    ; full repair
        ld (vtol_hp),a
        ld hl,txt_sa_repair
        ld e,7
        call sa_line
        ; fall through

; The next reward line
sa_next:
        ld hl,sa_row
        inc (hl)
        ret

; HL -> text, E = column: print it on the reward row (if there is room)
sa_line:
.at:    ld a,(sa_row)
        cp SA_ROW_MAX+1
        ret nc
        ld d,a
        ld c,MENU_TITLE
        jp menu_print

; HL = number, D = row, E = column: printed in decimal, no leading zeros
menu_num:
        ld (mn_pos),de
        ld ix,mn_pow
        ld b,0                          ; 1 once a digit has been printed
.dg:    ld e,(ix+0)
        ld d,(ix+1)
        ld a,'0'-1
.sb:    inc a
        or a
        sbc hl,de
        jr nc,.sb
        add hl,de
        ld c,a
        ld a,e
        dec a
        or d
        jr z,.pr                        ; the units: always
        ld a,c
        cp '0'
        jr nz,.pr
        bit 0,b
        jr z,.nx                        ; a leading zero
.pr:    ld b,1
        push hl
        push bc
        ld a,c
        ld de,(mn_pos)
        ld c,MENU_ATTR
        call menu_char
        pop bc
        pop hl
        ld a,(mn_pos)
        inc a
        ld (mn_pos),a
.nx:    inc ix
        inc ix
        ld a,(ix-2)
        dec a
        or (ix-1)
        jr nz,.dg
        ret

mn_pow:     dw 10000, 1000, 100, 10, 1
mn_pos:     dw 0                        ; column (low), row (high)
sa_old:     dw 0                        ; the salvage before this level
sa_row:     db 0                        ; the next reward line

; Salvage totals and their rewards: points (word), weapon unlocked
; (WPN_NONE: none), full repair (1); $FFFF ends it
salvage_tab:
        dw 10
        db WPN_LASER, 0
        dw 15
        db WPN_NONE, SA_REPAIR
        dw 20
        db WPN_CHAIN, 0
        dw 25
        db WPN_NONE, SA_REPAIR
        dw 30
        db WPN_ROCKETS, 0
        dw 35
        db WPN_NONE, SA_REPAIR
        dw 40
        db WPN_LASER, 0
        dw 45
        db WPN_NONE, SA_BOOSTER         ; (was a full repair)
        dw 50
        db WPN_CHAIN, 0
        dw 55
        db WPN_NONE, SA_REPAIR
        dw 60
        db WPN_ROCKETS, 0
        dw 65
        db WPN_LASER, 0
        dw 70
        db WPN_NONE, SA_REPAIR
        dw 75
        db WPN_CHAIN, 0
        dw 80
        db WPN_ROCKETS, 0
        dw 85
        db WPN_NONE, SA_REPAIR
        dw 90
        db WPN_LASER, 0
        dw 95
        db WPN_CHAIN, 0
        dw 100
        db WPN_ROCKETS, 1
        dw 105
        db WPN_BOFORS, 1
        dw 110
        db WPN_BOFORS, 1
        dw 115
        db WPN_MISSILE, 1
        dw 120
        db WPN_BOFORS, 1
        dw 125
        db WPN_BOFORS, 1
        dw 130
        db WPN_MISSILE, 1
        dw 135
        db WPN_MISSILE, 1
        dw 140
        db WPN_MISSILE, 1
        dw SALVAGE_TAIL
        db WPN_MISSILE, 1
        dw $FFFF

; Weapon names, by WPN_*
wpn_names:  dw txt_wn_none, txt_wn_gun, txt_wn_laser, txt_wn_chain
            dw txt_wn_rockets, txt_wn_missile, txt_wn_bomb, txt_wn_bofors
            dw txt_wn_prox
        ASSERT ($ - wpn_names)/2 == WPN_LAST+1
txt_wn_none:    db "NOTHING", 0
txt_wn_gun:     db "MACHINE GUN", 0
txt_wn_laser:   db "LASER", 0
txt_wn_chain:   db "CHAIN GUN", 0
txt_wn_rockets: db "ROCKET POD", 0
txt_wn_missile: db "MISSILE POD", 0
txt_wn_bomb:    db "BOMB", 0
txt_wn_bofors:  db "BOFORS CANNON", 0
txt_wn_prox:    db "PROXIMITY CANNON", 0
txt_sa_saved:   db "HUMANS SAVED", 0
txt_sa_points:  db "SALVAGE", 0
txt_sa_new:     db "NEW", 0
txt_sa_repair:  db "FULL REPAIR", 0
txt_sa_booster: db "BOOSTER MODULE", 0
txt_sa_rearm:   db "AMMUNITION REPLENISHED", 0

; The last level (LEVEL_LAST) complete: CONGRATULATIONS for GAME_DONE_FR
; frames (10 seconds), then GAME OVER (10 seconds) and the main menu
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
        jp main_menu

txt_load_err:
        db "CANNOT LOAD LEVEL", 0
txt_load_err2:
        db "ZPDATA MUST BE BESIDE THE NEX", 0

; row, column, attribute, text, 0 ... $FF
menu_text:
        db 3, 12, MENU_TITLE
        db "Z-POLICE", 0
        db 8, 8, MENU_ATTR
        db "1. NEW GAME", 0
        db 10, 8, MENU_ATTR
        db "2. CONTINUE SAVED GAME", 0
        db 12, 8, MENU_ATTR
        db "9. REDEFINE KEYS", 0
        db $FF
txt_no_save:
        db "NO SAVED GAME", 0
