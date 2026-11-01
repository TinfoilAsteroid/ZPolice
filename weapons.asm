;==============================================================================
; Z-POLICE - weapons page (8K page PAGE_WEAPONS, runs at $C000 in slot 6)
;
; Player weapons.  Paged in by main_loop with nextreg LOGIC_MMU,PAGE_WEAPONS
; (the keys page in slot 7) after
; the frame is set up (it uses sin_y/cos_y/sin_p/cos_p) and the zombies have
; moved.  Bullet state lives in the resident `bullets` table so that the city
; page can draw the tracers (draw_bullets).
;
; Keys 1-5 select the weapon slot that SPACE fires (wpn_sel: 1 = the centre
; slot, 2-5 = the wing pylons).  An empty slot isn't selected: the HUD
; flashes it instead (wflash_slot / wflash_t).  What is fitted where is set
; on the load-out screen between levels (loadout.asm).
;
; Machine gun (WPN_GUN, the centre slot): hold SPACE to fire one round every
; GUN_INTERVAL frames.  Rounds leave the ship's centre line 0.5 m below the
; camera and fly straight along the view direction at 500 m/s until they hit
; something.
;
; Collision, every frame for every round in flight: the path from its last
; position to its new one (BULLET_STEP long) is walked cell by cell through
; the city grid, in order (a 2D DDA on the horizontal distance s along the
; path).  The first thing met ends the path:
;   * a building cell: hit where the path enters the cell if it is below the
;     roof there (a wall), otherwise where it drops below the roof (the roof);
;   * a street cell marked as holding zombies (CELL_ZOMBIE): those in it, each a box
;     0.5 m wide and 2 m tall, nearest along the path first;
;   * the ground, where the path reaches height 0;
;   * leaving the GRID x GRID map: the round is gone.
; A round that hits is drawn once at the impact point, then freed.  A zombie
; that is hit loses B_DMG hit points; at 0 it is killed (its map blip
; removed, its record made inactive).  A rocket also bursts (rocket_blast).
;
; Rocket pod (WPN_ROCKETS, a wing pylon, ROCKET_SHOTS rockets): rockets are
; rounds too (B_KIND = BK_ROCKET), at 150 m/s and drawn as a short white
; streak with a yellow trail.  Wherever one stops (a building, the ground,
; a zombie) rocket_blast does BLAST_DMG to every zombie, human and base tile
; within BLAST_R on each axis, and sprays BLAST_PARTS orange particles.
;
; Bofors cannon (WPN_BOFORS, a wing pylon, BOFORS_SHOTS shells): the machine
; gun's rounds (B_KIND = BK_BOFORS, drawn as tracers) one every
; BOFORS_INTERVAL frames; each bursts where it stops: BOFORS_DMG within
; BOFORS_R (3 m) on each axis, BOFORS_PARTS particles.
;
; Proximity cannon (WPN_PROX, a wing pylon, PROX_SHOTS shells): the Bofors
; cannon (B_KIND = BK_PROX), its shells also bursting when they pass within
; PROX_R (2 m) of a monster (b_pr widens the monster hit boxes,
; cell_zombies); the burst does PROX_DMG within PROX_R on each axis.
;
; Missile pod (WPN_MISSILE, a wing pylon, MISSILE_SHOTS missiles): as the
; rockets (B_KIND = BK_MISSILE, drawn the same) at half the speed; the burst
; does MISSILE_DMG within MISSILE_R (1.0 tile) on each axis, and sprays
; MISSILE_PARTS particles.
;
; Damage: each round carries its damage (B_DMG): machine gun GUN_DMG, chain
; gun CHAIN_DMG, the laser LASER_DMG a beam frame, a rocket none directly
; (only its blast).  A zombie dies when its hit points (+18) run out.
;
; Positions are world units (1 tile = 20 m = 256 units, 1 m = 12.8).  Along the path,
; x = x0 + s*sinY, z = z0 + s*cosY and y = y0 + s*slope, with sinY/cosY the
; S7.8 heading at firing and slope = tan(pitch) in S7.8.
;==============================================================================

;------------------------------------------------------------------------------
; Per frame: fire, then move every round in flight
;------------------------------------------------------------------------------
update_weapons:
        call part_update                ; age and move the burst particles
        ld a,(vtol_dead)
        or a
        jr z,.alive
        call las_reset                  ; destroyed: no firing, no beam
        jr .move
.alive:
    IF DEBUG_KILLALL
        call debug_killall              ; (debug: keys 0 and 9)
        call debug_gun_cycle            ; (debug: key 8)
    ENDIF
        call wpn_select                 ; (slots can be chosen when landed)
        call gun_aim                    ; and the centre gun tilted
        call vtol_landed
        jr nz,.fire
        call las_reset                  ; landed: no firing, no beam, until
        call pad_service                ; it takes off; on the pad: repairs
        jr .move                        ; and reloads
.fire:  xor a
        ld (svc_on),a                   ; (service starts afresh next landing)
        call gun_fire
        call laser_update
.move:  ld ix,bullets
        ld b,NBULLETS
.lp:    push bc
        ld a,(ix+B_STATE)
        or a
        jr z,.nx
        cp 2
        jr nz,.fly
        ld (ix+B_STATE),0               ; its impact was shown last frame
        jr .nx
.fly:   call bullet_step
.nx:    ld de,BREC
        add ix,de
        pop bc
        djnz .lp
        ret

;------------------------------------------------------------------------------
; Machine gun / chain gun: SPACE held with one of them in the centre slot,
; ammo, and a free round
;------------------------------------------------------------------------------
gun_fire:
        ld hl,gun_wait
        ld a,(hl)
        or a
        jr z,.ready
        dec (hl)                        ; still cycling
        ret
.ready: ld a,K_FIRE
        call key_held
        ret z                           ; fire not pressed
        call sel_slot
        ld a,(hl)                       ; the selected slot's weapon
        cp WPN_CHAIN
        jp z,.chain
        cp WPN_ROCKETS
        jr z,.rocket
        cp WPN_MISSILE
        jr z,.missile
        cp WPN_BOFORS
        jr z,.bofors
        cp WPN_PROX
        jr z,.prox
        cp WPN_GUN
        ret nz
        call free_round                 ; machine gun: one round
        ret c
        call take_ammo
        ret c
        ld a,GUN_INTERVAL-1
        ld (gun_wait),a
        ld hl,BULLET_STEP
        call spawn_round
        ld (ix+B_DMG),GUN_DMG
        ld a,SFX_MG                     ; its sound (the interrupt plays it)
        ld (sfx_req),a
        ret
.rocket:
        call free_round                 ; rocket pod: one rocket
        ret c
        call take_ammo
        ret c
        ld a,ROCKET_INTERVAL-1
        ld (gun_wait),a
        ld hl,ROCKET_STEP
        call spawn_round
        ld (ix+B_KIND),BK_ROCKET        ; no direct damage: its blast
        ld a,SFX_ROCKET                 ; its woosh (the interrupt plays it)
        ld (sfx_req),a
        ret
.missile:
        call free_round                 ; missile pod: one missile
        ret c
        call take_ammo
        ret c
        ld a,MISSILE_INTERVAL-1
        ld (gun_wait),a
        ld hl,MISSILE_STEP
        call spawn_round
        ld (ix+B_KIND),BK_MISSILE       ; no direct damage: its blast
        ld a,SFX_MISSILE                ; its woosh
        ld (sfx_req),a
        ret
.prox:  ld a,BK_PROX                    ; proximity cannon: one shell
        jr .shell
.bofors:
        ld a,BK_BOFORS                  ; Bofors: one shell
.shell: ld (sh_kind),a
        call free_round
        ret c
        call take_ammo
        ret c
        ld a,BOFORS_INTERVAL-1
        ld (gun_wait),a
        ld hl,BULLET_STEP
        call spawn_round
        ld a,(sh_kind)
        ld (ix+B_KIND),a                ; no direct damage: its burst
        ld a,SFX_BOFORS                 ; its sound (the proximity cannon's
        ld (sfx_req),a                  ; too)
        ret
        ASSERT PROX_INTERVAL == BOFORS_INTERVAL
.chain: ; chain gun: one round every CHAIN_INTERVAL frames
        call free_round
        ret c
        call take_ammo
        ret c
        ld a,CHAIN_INTERVAL-1
        ld (gun_wait),a
        ld a,SFX_CHAIN                  ; its sound (the interrupt plays it)
        ld (sfx_req),a
        ; fall through

; A chain gun round from IX: the view direction turned by a random angle
; of -CHAIN_DEV..+CHAIN_DEV steps (1/256 rad) sideways and up/down
chain_round:
        ld hl,BULLET_STEP
        call spawn_round
        ld (ix+B_DMG),CHAIN_DMG
        call zrand                      ; (zombie page)
        push hl
        ld a,l
        call dev_n                      ; sideways: rotate (sin, cos) by d/256
        or a
        jr z,.v
        ld h,a
        ld l,0
        ld (cg_d),hl                    ; d * 256
        ld e,(ix+B_COS)                 ; sin += round(d * cos / 256)
        ld d,(ix+B_COS+1)
        call dmul
        ld (cg_s),hl
        ld hl,(cg_d)                    ; cos -= round(d * sin / 256)
        ld e,(ix+B_SIN)
        ld d,(ix+B_SIN+1)
        call dmul
        ex de,hl
        ld l,(ix+B_COS)
        ld h,(ix+B_COS+1)
        or a
        sbc hl,de
        ld (ix+B_COS),l
        ld (ix+B_COS+1),h
        ld l,(ix+B_SIN)
        ld h,(ix+B_SIN+1)
        ld de,(cg_s)
        add hl,de
        ld (ix+B_SIN),l
        ld (ix+B_SIN+1),h
.v:     pop hl                          ; up/down: slope (tan) +/- d/256
        ld a,h
        call dev_n
        ld l,(ix+B_SLOPE)
        ld h,(ix+B_SLOPE+1)
        call add_sa
        ld (ix+B_SLOPE),l
        ld (ix+B_SLOPE+1),h
        ret

; HL = d * 256, DE = S7.8 value -> HL = d * value / 256, rounded
dmul:
        call fmul                       ; HL = d * value (exact)
        ld de,128
        add hl,de
        ld l,h                          ; >> 8, keeping the sign
        ld a,h
        rla
        sbc a,a
        ld h,a
        ret

; A = random byte -> A = -CHAIN_DEV..+CHAIN_DEV, evenly spread
dev_n:
        ld d,a
        ld e,2*CHAIN_DEV+1
        mul d,e
        ld a,d
        sub CHAIN_DEV
        ret

; HL = HL + A (signed)
add_sa:
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
        ret

; One round from the selected slot's ammo: carry set if it is empty.
; AMMO_INF (255) is never counted down.
take_ammo:
        call sel_slot
        inc hl                          ; its ammo counter
        ld a,(hl)
        cp AMMO_INF
        ret z                           ; infinite (carry clear)
        or a
        scf
        ret z                           ; empty
        dec (hl)
        or a
        ret

; IX = a free round, carry clear; carry set if all are in flight
free_round:
        ld ix,bullets
        ld b,NBULLETS
        ld de,BREC
.f:     ld a,(ix+B_STATE)
        or a
        ret z                           ; (carry clear)
        add ix,de
        djnz .f
        scf
        ret
; Start round IX at the muzzle along the view direction, travelling HL
; units (along its path) per frame
spawn_round:
        ld (sr_len),hl
        ld (ix+B_STATE),$81             ; in flight, fresh: its first path
                                        ; starts at the muzzle (B_PX..)
        xor a                           ; cell intervals: on its first step
        ld (ix+B_TDX),a
        ld (ix+B_TDX+1),a
        ld (ix+B_KIND),a                ; a round, no damage (the caller
        ld (ix+B_DMG),a                 ; sets them)
        ; muzzle: the ship's centre line, GUN_DY below the camera
        ld hl,(cam_x+1)
        ld (ix+B_X),l
        ld (ix+B_X+1),h
        ld hl,(cam_y)
        ld de,GUN_DY
        add hl,de
        ld (ix+B_Y),l
        ld (ix+B_Y+1),h
        ld hl,(cam_z+1)
        ld (ix+B_Z),l
        ld (ix+B_Z+1),h
        ld (ix+B_PZ),l
        ld (ix+B_PZ+1),h
        ld l,(ix+B_X)
        ld h,(ix+B_X+1)
        ld (ix+B_PX),l
        ld (ix+B_PX+1),h
        ld l,(ix+B_Y)
        ld h,(ix+B_Y+1)
        ld (ix+B_PY),l
        ld (ix+B_PY+1),h
        ; direction: the view direction this frame
        ld hl,(sin_y)
        ld (ix+B_SIN),l
        ld (ix+B_SIN+1),h
        ld hl,(cos_y)
        ld (ix+B_COS),l
        ld (ix+B_COS+1),h
        ld hl,(sin_p)                   ; its climb: the view's pitch, or from
        ld (sr_sin),hl                  ; the centre slot pitch + gun_tilt
        ld hl,(cos_p)
        ld (sr_cos),hl
        ld a,(wpn_sel)
        cp WPN_CENTRE
        jr nz,.pt
        ld a,(gun_tilt)
        or a
        jr z,.pt
        ld hl,pitch
        add a,(hl)
        push af
        call get_sin
        ld (sr_sin),hl
        pop af
        add a,64
        call get_sin
        ld (sr_cos),hl
.pt:    ld hl,(sr_len)                  ; horizontal distance per frame
        ld de,(sr_cos)
        call fmul
        ld (ix+B_S),l
        ld (ix+B_S+1),h
        ld hl,(sr_sin)                  ; slope = sin / cos  (S7.8)
        ld a,h
        push af
        call abs_hl
        ld a,h                          ; A:HL = |sin| << 8
        ld h,l
        ld l,0
        ld de,(sr_cos)
        call udiv24
        pop af
        rla
        call c,neg_hl
        ld (ix+B_SLOPE),l
        ld (ix+B_SLOPE+1),h
        ret

;------------------------------------------------------------------------------
; R / F: tilt the centre gun up / down (GUN_TILT_STEP a frame, to
; GUN_TILT_UP up, GUN_TILT_DN down); V: back towards level at GUN_CTR_STEP.
; Then sight_y: the gunsight's row for the selected weapon, VIEW_CY minus
; 128 * tan(tilt) for the centre slot (the projection's scale), kept
; SIGHT_MARGIN rows inside the view.
;------------------------------------------------------------------------------
gun_aim:
        ld a,K_GUN_UP
        call key_held
        jr z,.dn
        ld a,(gun_tilt)
        add a,$80                       ; (signed compare)
        cp GUN_TILT_UP+$80
        jr nc,.dn                       ; at the top
        sub $80-GUN_TILT_STEP
        ld (gun_tilt),a
.dn:    ld a,K_GUN_DN
        call key_held
        jr z,.ct
        ld a,(gun_tilt)
        add a,$80
        cp $80-GUN_TILT_DN+1
        jr c,.ct                        ; at the bottom
        sub $80+GUN_TILT_STEP
        ld (gun_tilt),a
.ct:    ld a,K_GUN_CTR
        call key_held
        jr z,.sight
        ld a,(gun_tilt)
        or a
        jr z,.sight
        jp m,.neg
        sub GUN_CTR_STEP                ; tilted up: down towards 0
        jp p,.st
        xor a
        jr .st
.neg:   add a,GUN_CTR_STEP              ; tilted down: up towards 0
        jp m,.st
        xor a
.st:    ld (gun_tilt),a
.sight: ld c,VIEW_CY
        ld a,(wpn_sel)
        cp WPN_CENTRE
        jr nz,.sy                       ; a pylon: straight ahead
        ld a,(gun_tilt)
        or a
        jr z,.sy
        jp m,.sd
        ld hl,tilt_rows                 ; up: higher on the screen
        add hl,a
        ld a,c
        sub (hl)
        jr .sc
.sd:    neg                             ; down: lower
        ld hl,tilt_rows
        add hl,a
        ld a,c
        add a,(hl)
.sc:    ld c,a
        cp SIGHT_MARGIN
        jr nc,.lo
        ld c,SIGHT_MARGIN
.lo:    ld a,c
        cp VIEW_H-SIGHT_MARGIN
        jr c,.sy
        ld c,VIEW_H-SIGHT_MARGIN-1
.sy:    ld a,c
        ld (sight_y),a
        ret

; round(128 * tan(k * 360/256 deg)), k = 0..GUN_TILT_DN: the gunsight's
; rows from the centre for a tilt of k
tilt_rows:  db 0, 3, 6, 9, 13, 16, 19, 22, 25, 29, 32, 35, 39, 42, 46, 49
            db 53, 57, 61, 64, 68, 73, 77, 81, 86, 90, 95, 100, 105, 110
            db 116, 122, 128
        ASSERT $ - tilt_rows == GUN_TILT_DN + 1
        ASSERT GUN_TILT_UP <= GUN_TILT_DN

;------------------------------------------------------------------------------
; Keys 1-5: select the weapon slot SPACE fires (an empty one isn't selected:
; the HUD flashes it instead)
;------------------------------------------------------------------------------
wpn_select:
        ld c,0                          ; slot keys, newly pressed
.k:     ld a,c
        add a,K_SLOT1
        call key_pressed
        jr nz,.sel
        inc c
        ld a,c
        cp WPN_SLOTS
        jr nz,.k
        ret
.sel:   ld a,c
        add a,a
        ld hl,wpn_slots
        add hl,a
        ld a,(hl)
        or a
        jr nz,.fitted
        ld a,c                          ; empty: keep the current slot and
        ld (wflash_slot),a              ; have the HUD flash the asked-for one
        ld a,6*WFLASH
        ld (wflash_t),a
        ret
.fitted:
        ld a,(wpn_sel)
        cp c
        ret z                           ; already selected
        ld a,c
        ld (wpn_sel),a
        jp las_reset                    ; no beam carried to the new slot

    IF DEBUG_KILLALL
;------------------------------------------------------------------------------
; Debug: key 8 changes the centre slot's gun, machine gun -> laser -> chain
; gun -> machine gun (anything else there: the machine gun), with its full
; (infinite) load, and selects the centre slot
;------------------------------------------------------------------------------
debug_gun_cycle:
        ld hl,KB_8
        call key_code_pressed
        ret z
        ld hl,wpn_slots                 ; the centre slot: type, ammo
        ld a,(hl)
        ld b,WPN_LASER
        cp WPN_GUN
        jr z,.set
        ld b,WPN_CHAIN
        cp WPN_LASER
        jr z,.set
        ld b,WPN_GUN
.set:   ld (hl),b
        inc hl
        ld (hl),AMMO_INF
        xor a
        ld (wpn_sel),a                  ; fire it
        jp las_reset                    ; (no beam carried over)

;------------------------------------------------------------------------------
; Debug: key 0 kills every monster at once (zombies, ghouls, ghosts and
; banshees, none left fading) and counts every human still in the city or
; aboard as rescued.  zombie_update then finds the wave wiped out: the next
; wave, or after the last the level complete.
; Key 9 does the same and ends the level, on to the next city's first level
; (level 2 -> 6): level becomes this city's last (level_complete_screen
; moves it on one, or after the last city the game is complete) and the
; wave the level's last.
;------------------------------------------------------------------------------
debug_killall:
        ld hl,KB_9
        call key_code_pressed
        jr z,.k0
        ld a,(level)                    ; (level-1) mod CITY_LEVELS - CITY_LEVELS
        dec a
.m:     sub CITY_LEVELS
        jr nc,.m
        neg                             ; CITY_LEVELS-1 - (level-1) mod
        dec a                           ; CITY_LEVELS: levels left in the city
        ld hl,level
        add a,(hl)
        ld (hl),a                       ; the city's last level
        ld a,(level_cur+LV_WAVES)
        ld (wave_number),a              ; its last wave
        jr .all
.k0:    ld hl,KB_0
        call key_code_pressed
        ret z
.all:   ld ix,zombies
        ld b,NMON
.z:     push bc
        call zblip_off                  ; (map.asm)
        ld (ix+10),0                    ; gone (zflags unmarks its cell)
        ld de,ZREC
        add ix,de
        pop bc
        djnz .z
        ld hl,zatk_flags                ; nobody attacking
        ld b,NMON
.a:     ld (hl),FALSE
        inc hl
        djnz .a
        ld ix,humans
        ld b,HUMAN_MAX
.h:     push bc
        ld a,(ix+6)
        cp HS_WAIT
        jr z,.s
        cp HS_ABOARD
        jr nz,.hn
.s:     ld c,0                          ; dot off,
        call hum_dot
        ld (ix+6),HS_SAVED              ; rescued
        ld hl,saved
        inc (hl)
.hn:    ld de,HREC
        add ix,de
        pop bc
        djnz .h
        xor a
        ld (passengers),a
        jp hum_flags                    ; (no waiting humans' cells marked)
    ENDIF

; New game: no gun cool-down, no beam
weapons_reset:
        xor a
        ld (gun_wait),a
        ld (svc_on),a
        ld (gun_tilt),a                 ; the centre gun level
        ld a,VIEW_CY
        ld (sight_y),a
        xor a
        ; fall through

; Stop any laser beam or cool-down
las_reset:
        xor a
        ld (las_on),a
        ld (las_cool),a
        ld (laser_rec+B_STATE),a
        ret

; HL -> the selected weapon slot (type, then ammo)
sel_slot:
        ld a,(wpn_sel)
        add a,a
        ld hl,wpn_slots
        add hl,a
        ret

;------------------------------------------------------------------------------
; Landed (update_weapons): on the base pad, repair and reload.  The VTOL
; gains 1 hit point every REPAIR_FRAMES frames up to VTOL_HP; each slot
; whose weapon reloads (wpn_cfg, zpolice.asm: its full load and frames a
; shot) gains a
; shot every that many frames up to its full load.  The counts start afresh
; each landing (svc_on), so a shot or hit point takes the whole interval.
;------------------------------------------------------------------------------
pad_service:
        call cam_cell_ptr
        ld a,(hl)
        and CELL_CODE
        cp PAD_CODE
        jr z,.pad
        xor a                           ; landed elsewhere: nothing
        ld (svc_on),a
        ret
.pad:   ld a,(svc_on)
        or a
        jr nz,.go
        inc a                           ; just landed: start the counts
        ld (svc_on),a
        ld a,REPAIR_FRAMES
        ld (svc_rep),a
        ld hl,svc_rel
        ld b,WPN_SLOTS
.cl:    ld (hl),0                       ; (0: its interval starts next)
        inc hl
        djnz .cl
.go:    ld a,(boost_fitted)             ; the booster: refuelled 1 a frame
        or a
        jr z,.nf
        ld a,(boost_fuel)
        cp BOOST_FUEL_MAX
        jr nc,.nf
        inc a
        ld (boost_fuel),a
.nf:    ld hl,svc_rep                   ; repair
        dec (hl)
        jr nz,.rl
        ld (hl),REPAIR_FRAMES
        ld a,(vtol_hp)
        cp VTOL_HP
        jr nc,.rl                       ; (undamaged)
        inc a
        ld (vtol_hp),a
.rl:    ld ix,wpn_slots                 ; reload, slot by slot
        ld hl,svc_rel
        ld b,WPN_SLOTS
.sl:    push bc
        ld a,(ix+WPN_TYPE)
        push hl
        call wpn_cfg_ptr                ; (resident)
        ld a,(hl)
        ld c,a                          ; C = its full load (WCFG_LOAD)
        inc hl
        ld a,(hl)                       ; frames a shot (WCFG_RELOAD)
        pop hl
        or a
        jr z,.nx                        ; doesn't reload (or an empty slot)
        ld b,a                          ; B = frames a shot
        ld a,(ix+WPN_AMMO)
        cp c
        jr nc,.full
        ld a,(hl)
        or a
        jr nz,.cnt
        ld (hl),b                       ; a new interval
.cnt:   dec (hl)
        jr nz,.nx
        inc (ix+WPN_AMMO)               ; one more shot
        jr .nx
.full:  ld (hl),0
.nx:    inc hl
        inc ix
        inc ix
        pop bc
        djnz .sl
        ret

;------------------------------------------------------------------------------
; Pulse laser: SPACE held with the laser in the centre slot fires a beam for
; LASER_ON frames, then it cools for LASER_COOL frames.  Each beam frame the
; beam is traced from the muzzle along the current view direction (the round
; walk, LASER_RANGE long) to the first building, ground or zombie, killing a
; zombie it reaches.  It is kept in laser_rec as a round (state 3) whose
; path runs from the muzzle to where the beam stops; draw_bullets clips it
; to the view, so it rises from the bottom edge of the screen.
;------------------------------------------------------------------------------
laser_update:
        ld a,(las_on)
        or a
        jr nz,.beam
        ld (laser_rec+B_STATE),a        ; no beam this frame
        ld a,(las_cool)
        or a
        jr z,.ready
        dec a                           ; cooling down
        ld (las_cool),a
        ret
.ready: call sel_slot
        ld a,(hl)
        cp WPN_LASER
        ret nz
        ld a,K_FIRE
        call key_held
        ret z
        ld a,LASER_ON
        ld (las_on),a
        ld a,SFX_LASER                  ; a new pulse: its zap
        ld (sfx_req),a
.beam:  ld hl,las_on
        dec (hl)
        jr nz,.on
        ld a,LASER_COOL                 ; last beam frame: cool down next
        ld (las_cool),a
.on:    ld ix,laser_rec
        ld hl,LASER_RANGE
        call spawn_round                ; (start of path = the muzzle)
        ld (ix+B_DMG),LASER_DMG         ; per beam frame on a target
        call bullet_step                ; trace it to the first thing it meets
        ld a,(ix+B_STATE)
        or a
        ret z                           ; off the map (can't, inside the wall)
        ld (ix+B_STATE),3               ; beam
        ret

;------------------------------------------------------------------------------
; Particles (pool `particles`, drawn by draw_particles): zombie bursts and
; rocket / missile bursts
;------------------------------------------------------------------------------
; IX = a zombie just killed: spray NPART_BURST green particles from its body
; (PART_Y up), each with a random velocity: sideways -4..3 units a frame in
; x and z, upwards 2..5
part_burst:
        ld l,(ix+0)
        ld h,(ix+1)
        ld (ps_x),hl
        ld hl,PART_Y
        ld (ps_y),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (ps_z),hl
        ld hl,PART_COL0 | PART_LIFE<<8
        ld (ps_col),hl                  ; (and ps_life)
        xor a
        ld (ps_fire),a
        ld c,NPART_BURST
        jr part_spray

; A rocket or missile burst at rb_x/y/z: rb_parts orange particles for
; FIRE_LIFE frames, flying out faster than a zombie's (x and z -8..7 units
; a frame, y -2..5)
fire_burst:
        ld hl,(rb_x)
        ld (ps_x),hl
        ld hl,(rb_y)
        ld (ps_y),hl
        ld hl,(rb_z)
        ld (ps_z),hl
        ld hl,FIRE_COL0 | FIRE_LIFE<<8
        ld (ps_col),hl
        ld a,1
        ld (ps_fire),a
        ld a,(rb_parts)
        ld c,a
        ; fall through

; Spray C particles from ps_x/y/z, colour ps_col (age 1), lasting ps_life
; frames, velocities by ps_fire.  Uses free particles only; if the pool
; runs out, fewer.  Preserves IX.
part_spray:
        push iy
        ld iy,particles
        ld b,NPART
.lp:    ld a,(iy+0)
        or a
        jr nz,.nx                       ; in use
        ld (iy+0),1                     ; age 1: brightest
        ld hl,(ps_x)
        ld (iy+1),l
        ld (iy+2),h
        ld hl,(ps_y)
        ld (iy+3),l
        ld (iy+4),h
        ld hl,(ps_z)
        ld (iy+5),l
        ld (iy+6),h
        ld hl,(ps_col)
        ld (iy+10),l                    ; its colour and life
        ld (iy+11),h
        push bc
        call zrand                      ; (zombie page)
        ld a,(ps_fire)
        or a
        jr nz,.fire
        ld a,l
        and 7
        sub 4
        ld (iy+7),a                     ; vx -4..3
        ld a,h
        and 7
        sub 4
        ld (iy+9),a                     ; vz -4..3
        ld a,l
        rrca
        rrca
        rrca
        rrca
        and 3
        add a,2
        ld (iy+8),a                     ; vy 2..5 (up)
        jr .v
.fire:  ld a,l
        and 15
        sub 8
        ld (iy+7),a                     ; vx -8..7
        ld a,h
        and 15
        sub 8
        ld (iy+9),a                     ; vz -8..7
        ld a,l
        rrca
        rrca
        rrca
        rrca
        and 7
        sub 2
        ld (iy+8),a                     ; vy -2..5
.v:     pop bc
        dec c
        jr z,.done
.nx:    ld de,PREC
        add iy,de
        djnz .lp
.done:  pop iy
        ret

; Age every particle; past its life (+11) it is freed.  Move the rest by
; their velocity, with gravity, stopping on the ground.
part_update:
        ld ix,particles
        ld b,NPART
.lp:    ld a,(ix+0)
        or a
        jr z,.nx
        inc a
        ld c,a
        ld a,(ix+11)
        cp c
        ld a,c
        jr nc,.live
        xor a                           ; gone
.live:  ld (ix+0),a
        or a
        jr z,.nx
        ld a,(ix+7)                     ; x += vx
        ld l,(ix+1)
        ld h,(ix+2)
        call add_sa
        ld (ix+1),l
        ld (ix+2),h
        ld a,(ix+9)                     ; z += vz
        ld l,(ix+5)
        ld h,(ix+6)
        call add_sa
        ld (ix+5),l
        ld (ix+6),h
        ld a,(ix+8)                     ; y += vy, vy -= gravity
        ld l,(ix+3)
        ld h,(ix+4)
        call add_sa
        bit 7,h
        jr z,.up
        ld hl,0                         ; on the ground: stays there
        ld (ix+8),0
        jr .y
.up:    ld a,(ix+8)
        sub PART_GRAV
        ld (ix+8),a
.y:     ld (ix+3),l
        ld (ix+4),h
.nx:    ld de,PREC
        add ix,de
        djnz .lp
        ret

;------------------------------------------------------------------------------
; Move round IX one frame along its path, stopping at the first thing it hits
;------------------------------------------------------------------------------
bullet_step:
        ; start of this frame's path; kept for drawing (B_PX..), except on a
        ; fresh round's first step, which is drawn from the muzzle
        bit 7,(ix+B_STATE)
        res 7,(ix+B_STATE)
        jr nz,.fresh
        ld l,(ix+B_X)
        ld h,(ix+B_X+1)
        ld (ix+B_PX),l
        ld (ix+B_PX+1),h
        ld l,(ix+B_Y)
        ld h,(ix+B_Y+1)
        ld (ix+B_PY),l
        ld (ix+B_PY+1),h
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        ld (ix+B_PZ),l
        ld (ix+B_PZ+1),h
.fresh: ld l,(ix+B_X)
        ld h,(ix+B_X+1)
        ld (b_x0),hl
        ld l,(ix+B_Y)
        ld h,(ix+B_Y+1)
        ld (b_y0),hl
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        ld (b_z0),hl
        ld l,(ix+B_SIN)
        ld h,(ix+B_SIN+1)
        ld (b_sin),hl
        ld l,(ix+B_COS)
        ld h,(ix+B_COS+1)
        ld (b_cos),hl
        ld l,(ix+B_SLOPE)
        ld h,(ix+B_SLOPE+1)
        ld (b_slope),hl
        ld l,(ix+B_S)
        ld h,(ix+B_S+1)
        ld (b_send),hl
        ld a,(ix+B_DMG)
        ld (b_dmg),a
        ld a,(ix+B_KIND)                ; a proximity shell: monsters' hit
        cp BK_PROX                      ; boxes PROX_R bigger every way
        ld a,0
        jr nz,.pr
        ld a,PROX_R
.pr:    ld (b_pr),a
        xor a
        ld (b_gnd),a
        ; does it reach the ground this frame?  s = y0 / -slope
        ld hl,(b_slope)
        bit 7,h
        jr z,.nognd
        ld hl,(b_send)
        call b_y_at                     ; HL = height at the end
        bit 7,h
        jr z,.nognd
        ld hl,(b_slope)
        call neg_hl
        ex de,hl                        ; DE = -slope
        ld hl,(b_y0)
        ld a,h                          ; A:HL = y0 << 8
        ld h,l
        ld l,0
        call udiv24
        ld (b_send),hl
        ld a,1
        ld (b_gnd),a
.nognd:
        ; grid walk set-up.  The distance between cell boundaries depends only
        ; on the direction: worked out (two divides) on the round's first step.
        ld a,(ix+B_TDX)
        or (ix+B_TDX+1)
        jr nz,.tdok
        ld hl,(b_sin)
        call cell_span
        ld (ix+B_TDX),l
        ld (ix+B_TDX+1),h
        ld hl,(b_cos)
        call cell_span
        ld (ix+B_TDZ),l
        ld (ix+B_TDZ+1),h
.tdok:  ld l,(ix+B_TDX)
        ld h,(ix+B_TDX+1)
        ld (b_tdx),hl
        ld l,(ix+B_TDZ)
        ld h,(ix+B_TDZ+1)
        ld (b_tdz),hl
        ld hl,(b_sin)                   ; first boundary, x then z
        ld a,(b_x0)
        ld de,(b_tdx)
        call dda_axis
        ld (b_tmx),hl
        ld (b_stx),a
        ld hl,(b_cos)
        ld a,(b_z0)
        ld de,(b_tdz)
        call dda_axis
        ld (b_tmz),hl
        ld (b_stz),a
        ld a,(b_x0+1)
        ld (b_ci),a
        ld a,(b_z0+1)
        ld (b_cj),a
        ld hl,0
        ld (b_sin_),hl                  ; s where the path enters this cell
.cell:  ; s_out = min(tmx, tmz, send)
        ld hl,(b_tmx)
        ld de,(b_tmz)
        call min_u
        ld de,(b_send)
        call min_u
        ld (b_sout),hl
        call cell_hit
        jp c,.hit
        ld hl,(b_sout)                  ; path ends in this cell?
        ld de,(b_send)
        or a
        sbc hl,de
        jr z,.end
        ld hl,(b_tmx)                   ; step into the next cell
        ld de,(b_tmz)
        or a
        sbc hl,de
        jr nc,.stz
        ld hl,(b_tmx)                   ; x boundary first
        ld (b_sin_),hl
        ld de,(b_tdx)
        call add_sat
        ld (b_tmx),hl
        ld a,(b_stx)
        ld hl,b_ci
        add a,(hl)
        ld (hl),a
        jr .chk
.stz:   ld hl,(b_tmz)                   ; z boundary first
        ld (b_sin_),hl
        ld de,(b_tdz)
        call add_sat
        ld (b_tmz),hl
        ld a,(b_stz)
        ld hl,b_cj
        add a,(hl)
        ld (hl),a
.chk:   ld a,(b_ci)
        cp GRID
        jr nc,.gone                     ; left the map
        ld a,(b_cj)
        cp GRID
        jr c,.cell
.gone:  ld (ix+B_STATE),0
        ret
.end:   ld hl,(b_send)
        ld a,(b_gnd)
        or a
        jr z,.fly
        call b_move                     ; reached the ground
        ld (ix+B_STATE),2
        jr .burst
.fly:   call b_move                     ; whole step, nothing hit
        ld a,(ix+B_X+1)                 ; still over the map?
        cp GRID
        jr nc,.gone
        ld a,(ix+B_Z+1)
        cp GRID
        jr nc,.gone
        ret
.hit:   ld hl,(b_shit)
        call b_move
        ld (ix+B_STATE),2               ; show the impact, then free it
.burst: ld a,(ix+B_KIND)                ; a rocket, missile or shell bursts
        or a
        ret z
        jp rocket_blast

; HL = S7.8 direction component -> HL = path distance s between cell
; boundaries along that axis, 256 * 256 / |c|  ($FFFF = never)
cell_span:
        ld a,h
        or l
        jr z,.never
        call abs_hl
        ex de,hl
        ld a,1
        ld hl,0
        jp udiv24
.never: dec hl                          ; $FFFF
        ret

; HL = S7.8 direction component, A = low byte of the start coordinate,
; DE = cell_span for it.  -> HL = s to the first cell boundary ($FFFF =
; never), A = cell step (+1, -1, 0).  s = distance * span / 256, by MUL.
dda_axis:
        ld b,a
        ld a,h
        or l
        jr nz,.mv
        ld hl,$FFFF                     ; not moving along this axis
        xor a
        ret
.mv:    ld a,h
        ld (dd_sg),a
        rla
        jr c,.neg
        xor a                           ; moving up: 256 - (x & 255)
        sub b
        jr nz,.part
        ex de,hl                        ; (x & 255) = 0: a whole cell
        jr .sgn
.neg:   ld a,b                          ; moving down: x & 255
.part:  ld c,a                          ; HL = (dist * span) >> 8
        push de
        ld d,a
        mul d,e                         ; dist * span low
        ld a,d
        pop de
        ld e,d
        ld d,c
        mul d,e                         ; dist * span high
        add a,e
        ld l,a
        ld a,d
        adc a,0
        ld h,a
.sgn:   ld a,(dd_sg)
        rla
        ld a,1
        ret nc
        ld a,-1
        ret

; Carry set if the path hits something in cell (b_ci, b_cj) between
; s = b_sin_ and b_sout; b_shit = where.
cell_hit:
        ld a,(b_cj)
        ld l,a
        ld h,0
        ROWOFS
        ld a,(b_ci)
        add hl,a
        push hl
        ld de,city_map
        add hl,de
        ld a,(hl)
        pop hl
        ld c,a
        and CELL_CODE
        jr nz,.bld
        bit CELL_ZOMBIE_B,c             ; street: zombies there?
        ret z                           ; no (carry clear)
        ld hl,(b_send)                  ; any along this frame's path
        ld (b_lim),hl
        jp cell_zombies
.bld:   ld a,c
        ld (b_mapc),a                   ; (for monsters above the roof)
        call bld_height                 ; HL = roof height
        ld (b_h),hl
        ld hl,(b_sin_)                  ; below the roof where it enters?
        call b_y_at
        ld de,(b_h)
        or a
        sbc hl,de
        jp m,.wall
        ld hl,(b_sout)                  ; above it where it leaves: clear
        call b_y_at
        ld de,(b_h)
        or a
        sbc hl,de
        jp p,.miss                      ; clear of the building
        ; drops through the roof: s = (y0 - h) / -slope
        ld hl,(b_slope)
        call neg_hl
        ex de,hl
        ld hl,(b_y0)
        ld bc,(b_h)
        or a
        sbc hl,bc
        ld a,h
        ld h,l
        ld l,0
        call udiv24
        ld de,(b_sin_)                  ; keep it inside this cell
        call max_u
        ld de,(b_sout)
        call min_u
        ld (b_shit),hl
        jr .bhit
.wall:  ld hl,(b_sin_)
        ld (b_shit),hl
.bhit:  ; it hits the building at b_shit: but first a monster flying over
        ; the roof nearer than that?
        ld a,(b_mapc)
        bit CELL_ZOMBIE_B,a
        scf
        ret z                           ; none: the building
        ld hl,(b_shit)
        ld (b_bhit),hl
        ld (b_lim),hl
        call cell_zombies
        ret c                           ; the monster
        ld hl,(b_bhit)                  ; the building
        ld (b_shit),hl
        scf
        ret
.miss:  ld a,(b_mapc)                   ; passes the building: a monster
        bit CELL_ZOMBIE_B,a             ; above it?
        ret z                           ; (carry clear)
        ld hl,(b_send)
        ld (b_lim),hl
        ; fall through

; Cell (b_ci, b_cj) marked as holding zombies or special monsters: the
; nearest whose box (ZHIT_R either side, ZHIT_H tall from its feet, +21;
; for a proximity shell instead within b_pr of its x, z and feet, as the
; burst measures) the path passes through
; before b_lim.  The records are searched, highest index first.
cell_zombies:
        ld hl,$FFFF
        ld (b_shit),hl
        push iy
        ld a,NMON
.zl:    dec a
        ld (b_zi),a
        ld e,a
        ld d,ZREC
        mul d,e
        ld iy,zombies
        add iy,de
        bit 0,(iy+10)
        jp z,.zn                        ; already dead
        ld a,(iy+16)
        cp GM_DYING
        jp z,.zn                        ; a ghost fading out
        ld a,(b_ci)                     ; in this cell?
        cp (iy+1)
        jp nz,.zn
        ld a,(b_cj)
        cp (iy+3)
        jp nz,.zn
        ld l,(iy+0)                     ; relative position
        ld h,(iy+1)
        ld de,(b_x0)
        or a
        sbc hl,de
        ld (b_rx),hl
        ld l,(iy+2)
        ld h,(iy+3)
        ld de,(b_z0)
        or a
        sbc hl,de
        ld (b_rz),hl
        ; along = rx sinY + rz cosY
        ld hl,(b_rx)
        ld de,(b_sin)
        call fmul
        push hl
        ld hl,(b_rz)
        ld de,(b_cos)
        call fmul
        pop de
        add hl,de
        bit 7,h
        jp nz,.zn                       ; behind the start
        ld (b_al),hl
        ld de,(b_lim)
        or a
        sbc hl,de
        jr nc,.zn                       ; beyond this frame's path
        ; across = rx cosY - rz sinY, within the half width?
        ld hl,(b_rz)
        ld de,(b_sin)
        call fmul
        push hl
        ld hl,(b_rx)
        ld de,(b_cos)
        call fmul
        pop de
        or a
        sbc hl,de
        call abs_hl
        ld a,(b_pr)                     ; (a proximity shell: within b_pr
        or a                            ; of it instead)
        jr nz,.wd
        ld a,ZHIT_R
.wd:    inc a
        ld e,a
        ld d,0
        or a
        sbc hl,de
        jr nc,.zn
        ; height there between the feet and the top of the box?
        ld hl,(b_al)
        call b_y_at
        ld e,(iy+21)                    ; above its feet
        ld d,(iy+22)
        or a
        sbc hl,de
        ld a,(b_pr)                     ; (a proximity shell: from b_pr
        add hl,a                        ; below the feet)
        bit 7,h
        jr nz,.zn
        ld de,ZHIT_H+1
        ld a,(iy+15)                    ; a ghoul: half as tall
        cp ZT_GHOUL
        jr nz,.zh
        ld de,ZHIT_H/2+1
.zh:    ld a,(b_pr)                     ; (a proximity shell: to b_pr above
        or a                            ; the feet instead, as the burst
        jr z,.zc                        ; measures)
        add a,a
        inc a
        ld e,a
        ld d,0
.zc:    or a
        sbc hl,de
        jr nc,.zn
        ld hl,(b_al)                    ; nearest so far?
        ld de,(b_shit)
        or a
        sbc hl,de
        jr nc,.zn
        ld hl,(b_al)
        ld (b_shit),hl
        ld (b_zhit),iy
        ld a,(b_zi)                     ; (its index, for zatk_flags)
        ld (b_zhit_i),a
.zn:    ld a,(b_zi)                     ; next record
        or a
        jp nz,.zl
        pop iy
        ld hl,(b_shit)
        ld a,h
        and l
        inc a
        ret z                           ; none hit (carry clear)
        push iy                         ; it takes the round's damage
        ld iy,(b_zhit)
        ld a,(b_dmg)
        ld c,a
        ld a,(b_zhit_i)
        call zdamage
        pop iy
        scf
        ret

; Zombie IY (index A) takes C damage; when its hit points run out it is
; killed: map blip off, attack flag cleared, made inactive, particles.
; Preserves IX, IY.
zdamage:
        ld b,a
        ld a,c
        or a
        ret z                           ; (a rocket's direct hit: the blast)
        ld a,(iy+15)                    ; a walker (zombie, fast, ghoul) hit:
        cp ZT_GHOST                     ; a splat (the interrupt plays it; each
        jr nc,.hurt                     ; cuts the last)
        ld a,SFX_SPLAT
        ld (sfx3_req),a
.hurt:  ld a,(iy+18)
        sub c
        jr z,.kill
        jr c,.kill
        ld (iy+18),a
        ret
.kill:  ld (iy+18),0
        ld a,b                          ; no longer attacking anything
        ld hl,zatk_flags
        add hl,a
        ld (hl),FALSE
        push ix
        push iy
        pop ix
        call zblip_off
        ld a,(ix+15)                    ; a ghost or banshee fades out
        cp ZT_GHOST                     ; instead
        jr nc,.ghost
        ld (ix+10),0
        call part_burst                 ; and spray particles from it
        pop ix
        ret
.ghost: ld (ix+16),GM_DYING             ; (still drawn, and marked, while it
        ld (ix+17),GHOST_FADE_FRAMES    ; fades: specials.asm)
        pop ix
        ret

;------------------------------------------------------------------------------
; Rocket, missile or Bofors shell IX has stopped (at B_X, B_Y, B_Z): its
; damage (rb_dmg: BLAST_DMG, MISSILE_DMG, BOFORS_DMG) to every zombie, human
; and base tile within its reach (rb_r: BLAST_R, MISSILE_R, BOFORS_R) on
; each axis, and its orange particles.  Plain integer box tests: anything
; further than rb_r on any one axis is skipped.
;------------------------------------------------------------------------------
rocket_blast:
        ld a,(ix+B_KIND)
        ld hl,BLAST_R                   ; a rocket
        ld b,BLAST_DMG
        ld c,BLAST_PARTS
        ld e,SFX_BOOM_ROCKET
        cp BK_ROCKET
        jr z,.k
        ld hl,MISSILE_R                 ; a missile
        ld b,MISSILE_DMG
        ld c,MISSILE_PARTS
        ld e,SFX_BOOM_MISSILE
        cp BK_MISSILE
        jr z,.k
        ld hl,BOFORS_R                  ; a Bofors shell
        ld b,BOFORS_DMG
        ld c,BOFORS_PARTS
        ld e,SFX_BOOM_BOFORS
        cp BK_BOFORS
        jr z,.k
        ld hl,PROX_R                    ; a proximity shell
        ld b,PROX_DMG
        ld c,PROX_PARTS
        ld e,SFX_BOOM_PROX
.k:     ld a,e                          ; its explosion (AY 3: the interrupt
        ld (sfx2_req),a                 ; plays it)
        ld (rb_r),hl
        ld a,b
        ld (rb_dmg),a
        ld a,c
        ld (rb_parts),a
        ld l,(ix+B_X)
        ld h,(ix+B_X+1)
        ld (rb_x),hl
        ld l,(ix+B_Y)
        ld h,(ix+B_Y+1)
        ld (rb_y),hl
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        ld (rb_z),hl
        call fire_burst                 ; the orange shower
        ; zombies and special monsters (their feet's height, +21)
        push iy
        ld iy,zombies
        ld b,NMON
        ld c,0                          ; index
.zl:    push bc
        bit 0,(iy+10)
        jr z,.zn                        ; gone
        ld a,(iy+16)
        cp GM_DYING
        jr z,.zn                        ; a ghost fading out
        ld l,(iy+0)
        ld h,(iy+1)
        ld de,(rb_x)
        call rb_near
        jr nc,.zn
        ld l,(iy+2)
        ld h,(iy+3)
        ld de,(rb_z)
        call rb_near
        jr nc,.zn
        ld hl,(rb_y)
        ld e,(iy+21)
        ld d,(iy+22)
        call rb_near
        jr nc,.zn
        pop bc
        push bc
        ld a,(rb_dmg)
        ld b,a
        ld a,c
        ld c,b
        call zdamage
.zn:    ld de,ZREC
        add iy,de
        pop bc
        inc c
        djnz .zl
        pop iy
        ; humans still waiting (x, z, y of their feet)
        push ix
        xor a
        ld (rb_hum),a
        ld ix,humans
        ld b,HUMAN_MAX
.hl:    push bc
        ld a,(ix+6)
        cp HS_WAIT
        jr nz,.hn
        ld l,(ix+0)
        ld h,(ix+1)
        ld de,(rb_x)
        call rb_near
        jr nc,.hn
        ld l,(ix+2)
        ld h,(ix+3)
        ld de,(rb_z)
        call rb_near
        jr nc,.hn
        ld l,(ix+4)
        ld h,(ix+5)
        ld de,(rb_y)
        call rb_near
        jr nc,.hn
        ld a,(rb_dmg)
        ld c,a
        ld a,(ix+10)
        sub c
        jr z,.hk
        jr c,.hk
        ld (ix+10),a
        jr .hn
.hk:    ld (ix+10),0                    ; killed: dot off, dead
        ld c,0
        call hum_dot                    ; (map.asm)
        ld (ix+6),HS_DEAD
        ld a,1
        ld (rb_hum),a
.hn:    ld de,HREC
        add ix,de
        pop bc
        djnz .hl
        pop ix
        ld a,(rb_hum)
        or a
        jr z,.base
        push ix
        call hum_flags                  ; (human.asm) no longer drawn
        pop ix
.base:
        ; base tiles: the cells from (x, z) - rb_r to (x, z) + rb_r, if
        ; the burst is no more than rb_r above the tile's top
        ld hl,(rb_z)
        ld de,(rb_r)
        or a
        sbc hl,de
        ld a,h
        ld (rb_j),a
.bj:    ld hl,(rb_x)
        ld de,(rb_r)
        or a
        sbc hl,de
        ld a,h
        ld (rb_i),a
.bi:    ld a,(rb_i)
        cp GRID
        jr nc,.bn                       ; off the map
        ld e,a
        ld a,(rb_j)
        cp GRID
        jr nc,.bn
        ld d,a
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        ld bc,city_map
        add hl,bc
        ld a,(hl)
        and CELL_CODE
        call zbase                      ; (zombie.asm) Z: pad or terrace
        jr nz,.bn
        push de
        call bld_height                 ; HL = its top
        ld de,(rb_r)
        add hl,de
        ld de,(rb_y)
        or a
        sbc hl,de
        pop de
        jr c,.bn                        ; burst too high above it
        ld a,(rb_dmg)
        ld c,a
        call base_damage                ; (zombie.asm)
.bn:    ld hl,(rb_x)                    ; next column, up to x + rb_r
        ld de,(rb_r)
        add hl,de
        ld a,(rb_i)
        cp h
        jr z,.br
        inc a
        ld (rb_i),a
        jr .bi
.br:    ld hl,(rb_z)                    ; next row, up to z + rb_r
        ld de,(rb_r)
        add hl,de
        ld a,(rb_j)
        cp h
        ret z
        inc a
        ld (rb_j),a
        jr .bj

; Carry set if |HL - DE| <= rb_r (signed)
rb_near:
        or a
        sbc hl,de
        call abs_hl
        ld de,(rb_r)
        inc de
        or a
        sbc hl,de
        ret

; HL = s -> HL = height of the path there, y0 + s * slope
b_y_at:
        ld de,(b_slope)
        call fmul
        ld de,(b_y0)
        add hl,de
        ret

; HL = s: move round IX to that point of this frame's path
b_move:
        push hl
        ld de,(b_sin)
        call fmul
        ld de,(b_x0)
        add hl,de
        ld (ix+B_X),l
        ld (ix+B_X+1),h
        pop hl
        push hl
        ld de,(b_cos)
        call fmul
        ld de,(b_z0)
        add hl,de
        ld (ix+B_Z),l
        ld (ix+B_Z+1),h
        pop hl
        call b_y_at
        ld (ix+B_Y),l
        ld (ix+B_Y+1),h
        ret

; HL = min / max (HL, DE), unsigned
min_u:
        or a
        sbc hl,de
        add hl,de
        ret c
        ex de,hl
        ret
max_u:
        or a
        sbc hl,de
        add hl,de
        ret nc
        ex de,hl
        ret

; HL = HL + DE, saturating at $FFFF
add_sat:
        add hl,de
        ret nc
        ld hl,$FFFF
        ret

; A:HL / DE -> HL, unsigned, saturating at $FFFF.  DE < $8000.
udiv24:
        ld b,a
        ld a,d                          ; quotient over $FFFF?
        or a
        jr nz,.go
        ld a,b
        cp e
        jr c,.go
        ld hl,$FFFF
        ret
.go:    ld a,b                          ; A:H:L, shifted left 24 times;
        ld c,24                         ; quotient bits come in at the bottom
        push ix
        ld ix,0                         ; remainder
.lp:    add hl,hl
        rla
        push af
        add ix,ix
        pop af
        jr nc,.n0
        inc ix
.n0:    push hl
        push ix
        pop hl
        or a
        sbc hl,de
        jr c,.n1
        push hl
        pop ix
        pop hl
        inc l
        jr .nx
.n1:    pop hl
.nx:    dec c
        jr nz,.lp
        pop ix
        ret

;==============================================================================
; Weapons page data
;==============================================================================
gun_wait:   db 0                        ; frames until the gun can fire again
svc_on:     db 0                        ; pad_service: 1 once the counts started,
svc_rep:    db 0                        ;   frames to the next hit point,
svc_rel:    ds WPN_SLOTS                ;   and to each slot's next shot
las_on:     db 0                        ; laser beam frames left
las_cool:   db 0                        ; laser cool-down frames left
sr_len:     dw 0                        ; spawn_round
sr_sin:     dw 0                        ; spawn_round: its climb's sin, cos
sr_cos:     dw 0
cg_d:       dw 0                        ; chain_round
cg_s:       dw 0
b_x0:       dw 0                        ; start of this frame's path
b_y0:       dw 0
b_z0:       dw 0
b_sin:      dw 0                        ; direction (S7.8)
b_cos:      dw 0
b_slope:    dw 0
b_send:     dw 0                        ; s where this frame's path ends
b_gnd:      db 0                        ; 1: it ends on the ground
b_tmx:      dw 0                        ; s of the next x / z cell boundary
b_tmz:      dw 0
b_tdx:      dw 0                        ; s between x / z boundaries
b_tdz:      dw 0
b_stx:      db 0                        ; cell steps
b_stz:      db 0
b_ci:       db 0                        ; current cell
b_cj:       db 0
b_sin_:     dw 0                        ; s entering / leaving the cell
b_sout:     dw 0
b_h:        dw 0                        ; roof height of the cell
b_shit:     dw 0                        ; s of the hit
b_zi:       db 0
b_zhit:     dw 0                        ; zombie hit
b_zhit_i:   db 0                        ; and its index
b_rx:       dw 0
b_rz:       dw 0
b_al:       dw 0
dd_sg:      db 0                        ; dda_axis
b_dmg:      db 0                        ; damage of the round being moved
b_lim:      dw 0                        ; cell_zombies: hits only before this s
b_mapc:     db 0                        ; cell_hit: the building cell's map byte
b_bhit:     dw 0                        ;   and where the path hits it
b_pr:       db 0                        ; bullet_step: monster hit box margin
sh_kind:    db 0                        ; gun_fire: the shell's kind
rb_r:       dw 0                        ; rocket_blast: its reach on each axis,
rb_dmg:     db 0                        ;   damage
rb_parts:   db 0                        ;   and particles
ps_x:       dw 0                        ; part_spray: where from,
ps_y:       dw 0
ps_z:       dw 0
ps_col:     db 0                        ;   colour at age 1,
ps_life:    db 0                        ;   life (frames; follows ps_col)
ps_fire:    db 0                        ;   1: a burst's faster spread
rb_x:       dw 0                        ; rocket_blast: where it burst
rb_y:       dw 0
rb_z:       dw 0
rb_i:       db 0                        ; base tile cell being tested
rb_j:       db 0
rb_hum:     db 0                        ; 1: a human was killed
