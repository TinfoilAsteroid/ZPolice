;==============================================================================
; Z-POLICE - level complete screen (8K page PAGE_LEVELEND, runs at $C000 in
; slot 6)
;
; The level's last wave wiped out (main_loop pages it in): LEVEL n COMPLETE,
; the weapons rearmed, those aboard rescued, the humans saved and the
; salvage, and a line for each reward the salvage gives; then PRESS SPACE TO
; CONTINUE and the load-out screen (loadout_go).  After the last level, the
; game complete screen instead (game_done_go: menu.asm).  Drawn on Layer 2
; at 320x256 (screen320, text.asm; layer2-320x256.asm in slot 2) in the
; large font (26 x 25 characters), with the input page in slot 7.
;==============================================================================

LE_TITLE_ROW    equ 2
LE_SAVED_ROW    equ 5               ; HUMANS SAVED n
LE_SALV_ROW     equ 6               ; SALVAGE n
LE_REARM_ROW    equ 8               ; AMMUNITION REPLENISHED
LE_COL          equ 1               ; the lines' column (NIGHT VISION -
                                    ; MONOCHROME is 25 long)
LE_NUM_COL      equ 17              ; the numbers'
LE_PROMPT_ROW   equ 23              ; PRESS SPACE TO CONTINUE

; The level's last wave is wiped out: LEVEL n COMPLETE, until SPACE is
; pressed, then the load-out screen and the next level (next_level,
; zpolice.asm)
level_complete_screen:
        ld sp,stack_top
        ld a,(level)                    ; the last level: the whole game
        cp LEVEL_LAST
        jp nc,game_done_go              ; (zpolice.asm: menu.asm's page)
        call screen320                  ; (text.asm) the input page in slot 7
        ld a,(level)                    ; LEVEL n COMPLETE: its digits (a
        ld b,'0'-1                      ; level below LEVEL_LAST: 1 or 2)
.tens:  inc b
        sub 10
        jr nc,.tens
        add a,'0'+10
        ld c,a
        ld hl,txt_ld_num
        ld e,(F12_COLS-16)/2            ; (centred)
        ld a,b
        cp '0'
        jr z,.units
        ld (hl),a
        inc hl
        dec e
.units: ld (hl),c
        inc hl
        push de
        ex de,hl
        ld hl,txt_ld_end
        ld bc,TXT_LD_END
        ldir
        pop de
        ld d,LE_TITLE_ROW
        ld c,SCR_TITLE
        ld hl,txt_level_done
        call l320_print_at
        call rearm_all                  ; every weapon's ammo full again
        call hum_unload_all             ; (human.asm) those aboard: rescued
        call salvage_award              ; the humans saved: salvage, unlocks
        call le_space
        ld hl,level
        inc (hl)
        jp loadout_go                   ; (zpolice.asm) the load-out screen,
                                        ; then the next level

txt_level_done:
        db "LEVEL "
txt_ld_num:
        ds 2+TXT_LD_END                 ; (filled in)
txt_ld_end:
        db " COMPLETE", 0
TXT_LD_END      equ $-txt_ld_end

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
        ld d,LE_REARM_ROW
        ld e,LE_COL
        ld c,SCR_TEXT
        ld hl,txt_sa_rearm
        jp l320_print_at
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
SA_BOOSTER      equ 2               ;   the booster module,
SA_NV_GREEN     equ 4               ;   vision modes (vision_owned): night
SA_NV_MONO      equ 8               ;   vision green, monochrome,
SA_THERMAL      equ 16              ;   thermal, the vertical thrusters
SA_VTHRUST      equ 32              ;   (vthrust_fitted), the lateral
SA_LTHRUST      equ 64              ;   thrusters (lthrust_fitted)
SALVAGE_TAIL    equ 145
SALVAGE_STEP    equ 5
SA_ROW0         equ 10
SA_ROW_MAX      equ 21
salvage_award:
        ld d,LE_SAVED_ROW               ; HUMANS SAVED n
        ld e,LE_COL
        ld c,SCR_TEXT
        ld hl,txt_sa_saved
        call l320_print_at
        ld a,(saved)
        ld l,a
        ld h,0
        ld de,LE_SAVED_ROW<<8 | LE_NUM_COL
        call le_num
        ld hl,(salvage_points)          ; the new total
        ld (sa_old),hl
        ld a,(saved)
        add hl,a
        ld (salvage_points),hl
        ld d,LE_SALV_ROW                ; SALVAGE n
        ld e,LE_COL
        ld c,SCR_TEXT
        ld hl,txt_sa_points
        call l320_print_at
        ld hl,(salvage_points)
        ld de,LE_SALV_ROW<<8 | LE_NUM_COL
        call le_num
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
; repair, the booster module, the vision modes.  A line on the screen for
; each.
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
        ld e,LE_COL
        call sa_line
        pop hl
        ld e,LE_COL+4                   ; (after NEW)
        call sa_line.at
        call sa_next
        pop bc
.rep:   ld a,VIS_NV_GREEN               ; the vision modes: the VTOL has them
        ld hl,txt_sa_nv_green
        bit 2,c
        call nz,sa_vision
        ld a,VIS_NV_MONO
        ld hl,txt_sa_nv_mono
        bit 3,c
        call nz,sa_vision
        ld a,VIS_THERMAL
        ld hl,txt_sa_thermal
        bit 4,c
        call nz,sa_vision
        ASSERT SA_NV_GREEN == 1<<2 && SA_NV_MONO == 1<<3 && SA_THERMAL == 1<<4
        bit 5,c                         ; the vertical thrusters: part of the
        jr z,.bo                        ; VTOL from now on
        ASSERT SA_VTHRUST == 1<<5
        ld a,1
        ld (vthrust_fitted),a
        push bc
        ld hl,txt_sa_vthrust
        ld e,LE_COL
        call sa_line
        call sa_next
        pop bc
.bo:    bit 6,c                         ; the lateral thrusters: the same
        jr z,.bm
        ASSERT SA_LTHRUST == 1<<6
        ld a,1
        ld (lthrust_fitted),a
        push bc
        ld hl,txt_sa_lthrust
        ld e,LE_COL
        call sa_line
        call sa_next
        pop bc
.bm:    bit 1,c                         ; the booster module: fitted, full
        jr z,.rp
        ASSERT SA_BOOSTER == 1<<1
        ld a,1
        ld (boost_fitted),a
        ld a,BOOST_FUEL_MAX
        ld (boost_fuel),a
        push bc
        ld hl,txt_sa_booster
        ld e,LE_COL
        call sa_line
        call sa_next
        pop bc
.rp:    bit 0,c
        ret z
        ASSERT SA_REPAIR == 1<<0
        ld a,VTOL_HP                    ; full repair
        ld (vtol_hp),a
        ld hl,txt_sa_repair
        ld e,LE_COL
        call sa_line
        ; fall through (to sa_next: keep it next)

; The next reward line
sa_next:
        ld hl,sa_row
        inc (hl)
        ret

; A vision mode: A = its VIS_* bit, HL = its name: the VTOL has it now
; (vision_owned), and a line says so.  Preserves BC.
sa_vision:
        push hl
        ld hl,vision_owned
        or (hl)
        ld (hl),a
        pop hl
        push bc
        ld e,LE_COL
        call sa_line
        call sa_next
        pop bc
        ret

; HL -> text, E = column: print it on the reward row (if there is room)
sa_line:
.at:    ld a,(sa_row)
        cp SA_ROW_MAX+1
        ret nc
        ld d,a
        ld c,SCR_TITLE
        jp l320_print_at

; HL = number, D = row, E = column: printed in decimal, no leading zeros
le_num:
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
        ld c,SCR_TEXT
        call le_char
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
; (WPN_NONE: none), SA_* flags (full repair, booster, vision modes); $FFFF
; ends it.  (SALVAGE.md lists them.)
salvage_tab:
        dw 10
        db WPN_LASER, 0
        dw 15
        db WPN_NONE, SA_REPAIR
        dw 20
        db WPN_CHAIN, 0
        dw 25
        db WPN_NONE, SA_NV_GREEN        ; (was a full repair)
        dw 30
        db WPN_ROCKETS, 0
        dw 35
        db WPN_NONE, SA_VTHRUST         ; (was a full repair)
        dw 40
        db WPN_BOMB, 0                  ; (was a pulse laser)
        dw 45
        db WPN_NONE, SA_BOOSTER         ; (was a full repair)
        dw 50
        db WPN_LCHAIN_L, 0              ; (was a chain gun)
        dw 55
        db WPN_LCHAIN_R, SA_REPAIR      ; (was a proximity cannon)
        dw 60
        db WPN_ROCKETS, 0
        dw 65
        db WPN_NONE, SA_NV_MONO         ; (the pulse laser removed)
        dw 70
        db WPN_PROX, SA_REPAIR
        dw 75
        db WPN_PROX, 0                  ; (was a chain gun)
        dw 80
        db WPN_ROCKETS, 0
        dw 85
        db WPN_NONE, SA_THERMAL         ; (was a full repair)
        dw 90
        db WPN_NONE, SA_LTHRUST         ; (was a pulse laser)
        dw 100                          ; (95, a chain gun, removed)
        db WPN_ROCKETS, 1
        dw 105
        db WPN_AUTOCANNON, 1
        dw 110
        db WPN_AUTOCANNON, 1
        dw 115
        db WPN_MISSILE, 1
        dw 120
        db WPN_AUTOCANNON, 1
        dw 125
        db WPN_AUTOCANNON, 1
        dw 130
        db WPN_MISSILE, 1
        dw 135
        db WPN_MISSILE, 1
        dw 140
        db WPN_MISSILE, 1
        dw SALVAGE_TAIL
        db WPN_NONE, 1                  ; (the missile pod removed)
        dw $FFFF

; Weapon names, by WPN_*
wpn_names:  dw txt_wn_none, txt_wn_gun, txt_wn_laser, txt_wn_chain
            dw txt_wn_rockets, txt_wn_missile, txt_wn_bomb, txt_wn_autocannon
            dw txt_wn_prox, txt_wn_lchain_l, txt_wn_lchain_r
        ASSERT ($ - wpn_names)/2 == WPN_LAST+1
txt_wn_none:    db "NOTHING", 0
txt_wn_gun:     db "MACHINE GUN", 0
txt_wn_laser:   db "LASER", 0
txt_wn_chain:   db "CHAIN GUN", 0
txt_wn_rockets: db "ROCKET POD", 0
txt_wn_missile: db "MISSILE POD", 0
txt_wn_bomb:    db "BOMB", 0
txt_wn_autocannon: db "AUTOCANNON", 0
txt_wn_prox:    db "PROXIMITY CANNON", 0
txt_wn_lchain_l: db "LINKED CHAIN GUN L", 0
txt_wn_lchain_r: db "LINKED CHAIN GUN R", 0
txt_sa_saved:   db "HUMANS SAVED", 0
txt_sa_points:  db "SALVAGE", 0
txt_sa_new:     db "NEW", 0
txt_sa_repair:  db "FULL REPAIR", 0
txt_sa_booster: db "BOOSTER MODULE", 0
txt_sa_nv_green: db "NIGHT VISION - GREEN", 0
txt_sa_nv_mono: db "NIGHT VISION - MONOCHROME", 0
txt_sa_thermal: db "THERMAL VISION", 0
txt_sa_vthrust: db "VERTICAL THRUSTERS", 0
txt_sa_lthrust: db "LATERAL THRUSTERS", 0
txt_sa_rearm:   db "AMMUNITION REPLENISHED", 0

; "PRESS SPACE TO CONTINUE", and wait until SPACE is pressed (newly: one held
; down for firing as the screen came up doesn't count)
le_space:
        ld de,LE_PROMPT_ROW<<8 | (F12_COLS-23)/2
        ld c,SCR_HELP
        ld hl,txt_le_continue
        call l320_print_at
.w:     call menu_frame
        call zrand                      ; (keep stirring the seed)
        call kbd_scan                   ; (the input page: screen320)
        ld hl,KB_SPACE
        call key_code_pressed
        jr z,.w
        ret

; A = ASCII, D = row, E = column, C = colour: one character (menu_char's
; registers, text.asm)
le_char:
        push af
        ld a,c
        ld (l320_ink),a
        call l320_at
        pop af
        jp l320_char

txt_le_continue:
        db "PRESS SPACE TO CONTINUE", 0
        ASSERT LE_PROMPT_ROW > SA_ROW_MAX && SA_ROW0 > LE_REARM_ROW
