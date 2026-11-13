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
; Autocannon (WPN_AUTOCANNON, a wing pylon, AUTOCANNON_SHOTS shells): the
; machine gun's rounds (B_KIND = BK_AUTOCANNON, drawn as tracers) one every
; AUTOCANNON_INTERVAL frames; each bursts where it stops: AUTOCANNON_DMG
; within AUTOCANNON_R (3 m) on each axis, AUTOCANNON_PARTS particles.
;
; Proximity cannon (WPN_PROX, a wing pylon, PROX_SHOTS shells): the
; autocannon (B_KIND = BK_PROX), its shells also bursting when they pass within
; PROX_R (2 m) of a monster (b_pr widens the monster hit boxes,
; cell_zombies); the burst does PROX_DMG within PROX_R on each axis.
;
; Missile pod (WPN_MISSILE, a wing pylon, MISSILE_SHOTS missiles): as the
; rockets (B_KIND = BK_MISSILE, drawn the same) at half the speed; the burst
; does MISSILE_DMG within MISSILE_R (1.0 tile) on each axis, and sprays
; MISSILE_PARTS particles.  Guided: one fires only with a target locked
; (lock_update: the reticule), and turns towards it (msl_steer) at
; MISSILE_TURN a frame until it is more than LOCK_RANGE away.
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
        call lock_off                   ;   no lock
        call wreck_fx                   ;   the crash: fire and debris
        jr .move
.alive:
    IF DEBUG_KILLALL
        call debug_killall              ; (debug: keys 0, 9 and 8)
        call debug_gun_cycle            ; (debug: key 7)
    ENDIF
        call wpn_select                 ; (slots can be chosen when landed)
        call gun_aim                    ; and the centre gun tilted
        call vtol_landed
        jr nz,.fire
        call las_reset                  ; landed: no firing, no beam, until
        call lock_off                   ; it takes off (nor a lock); on the
        call pad_service                ; pad: repairs and reloads
        jr .move
.fire:  xor a
        ld (svc_on),a                   ; (service starts afresh next landing)
        call lock_update                ; the missile lock
        call aim_probe                  ; the aim assist, and the sight
        call gun_fire
        call laser_update
.move:  call lich_update                 ; a lich's fireballs
        ld ix,bullets
        ld b,NBULLETS
.lp:    push bc
        ld a,(ix+B_STATE)
        or a
        jr z,.nx
        cp 2
        jr nz,.fly
        ld (ix+B_STATE),0               ; its impact was shown last frame
        jr .nx
.fly:   ld a,(ix+B_KIND)
        cp BK_MISSILE
        call z,msl_steer                ; a missile turns to its target
        ld a,(ix+B_KIND)
        cp BK_BOMB
        call z,bomb_steer               ; a bomb's glide steepens
        call bullet_step
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
        cp WPN_LCHAIN_L
        jp z,.linked
        cp WPN_LCHAIN_R
        jp z,.linked
        cp WPN_ROCKETS
        jr z,.rocket
        cp WPN_MISSILE
        jr z,.missile
        cp WPN_AUTOCANNON
        jp z,.autocannon
        cp WPN_BOMB
        jp z,bomb_drop
        cp WPN_PROX
        jp z,.prox
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
        call aim_apply
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
        ld a,(lock_state)               ; missile pod: only with a lock
        cp 2
        ret nz
        call free_round                 ; one missile
        ret c
        call take_ammo
        ret c
        ld a,MISSILE_INTERVAL-1
        ld (gun_wait),a
        ld hl,MISSILE_STEP
        call spawn_round
        ld (ix+B_KIND),BK_MISSILE       ; no direct damage: its blast
        ld a,(lock_tgt)                 ; tracking the target locked,
        ld (ix+B_TGT),a
        ld a,(yaw_frac)                 ; from straight ahead
        ld (ix+B_YAW),a
        ld a,(yaw)
        ld (ix+B_YAW+1),a
        ld a,(pitch_frac)
        ld (ix+B_PIT),a
        ld a,(pitch)
        ld (ix+B_PIT+1),a
        ld a,SFX_MISSILE                ; its woosh
        ld (sfx_req),a
        ret
.prox:  ld a,BK_PROX                    ; proximity cannon: one shell
        jr .shell
.autocannon:
        ld a,BK_AUTOCANNON              ; autocannon: one shell
.shell: ld (sh_kind),a
        call free_round
        ret c
        call take_ammo
        ret c
        ld a,AUTOCANNON_INTERVAL-1
        ld (gun_wait),a
        ld hl,BULLET_STEP
        call spawn_round
        ld a,(sh_kind)
        ld (ix+B_KIND),a                ; no direct damage: its burst
        ld a,SFX_AUTOCANNON             ; its sound (the proximity cannon's
        ld (sfx_req),a                  ; too)
        ret
        ASSERT PROX_INTERVAL == AUTOCANNON_INTERVAL
.linked: ; a linked chain gun selected: every one fitted fires a round,
        ; LINK_OFF to the left / right, from its own ammo (LINK_SHOTS)
        ld a,CHAIN_INTERVAL-1
        ld (gun_wait),a
        xor a
        ld (lk_fired),a
        ld a,(wpn_slots+2*WPN_LINK_L)
        cp WPN_LCHAIN_L
        jr nz,.lr
        call free_round
        ret c
        ld hl,wpn_slots+2*WPN_LINK_L
        call take_slot_ammo
        jr c,.lr                        ; out of rounds
        call chain_round
        ld hl,-LINK_OFF
        call round_side
        xor a                           ; its own aim assist (the left's)
        call lk_apply
        ld a,1
        ld (lk_fired),a
.lr:    ld a,(wpn_slots+2*WPN_LINK_R)
        cp WPN_LCHAIN_R
        jr nz,.ls
        call free_round
        jr c,.ls
        ld hl,wpn_slots+2*WPN_LINK_R
        call take_slot_ammo
        jr c,.ls
        call chain_round
        ld hl,LINK_OFF
        call round_side
        ld a,2                          ; its own aim assist (the right's)
        call lk_apply
        ld a,1
        ld (lk_fired),a
.ls:    ld a,(lk_fired)                 ; its sound, if either fired
        or a
        ret z
        ld a,SFX_CHAIN
        ld (sfx_req),a
        ret
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
        ld a,(wpn_sel)                  ; (linked guns: wings, straight ahead)
        cp WPN_CENTRE
        call z,aim_apply
        ld (ix+B_DMG),CHAIN_DMG
        ld a,CHAIN_DEV
        ; fall through

; Round IX's direction turned by a random angle of -A..+A steps (1/256 rad)
; sideways and up/down (a chain gun's CHAIN_DEV, a fireball's FB_DEV)
round_spread:
        ld (rs_dev),a
        call zrand                      ; (zombie page)
        push hl
        ld a,l
        call dev_n                      ; sideways
        call round_turn
        pop hl                          ; up/down: slope (tan) +/- d/256
        ld a,h
        call dev_n
        ld l,(ix+B_SLOPE)
        ld h,(ix+B_SLOPE+1)
        call add_sa
        ld (ix+B_SLOPE),l
        ld (ix+B_SLOPE+1),h
        ret

; Round IX's heading turned A steps (1/256 rad; + right): rotate (sin, cos)
round_turn:
        or a
        ret z
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
        ret

;------------------------------------------------------------------------------
; Aim assist, for a centre slot round IX just spawned, pointing where the gun
; does (or a linked chain gun's, from its own muzzle: each on its own): the
; nearest monster drawn last frame (a monster behind a building isn't: bit 1
; of +31) near the gun's crosshair column (aa_col) with its middle within
; AIM_DEV steps of the path, or its box on the path already.  The round turns to its middle, at most
; AIM_DEV steps sideways and AIM_DEV up or down: aa_d and aa_ds, kept for the
; frame's shots (aim_apply) and the sight.  Only the round: the view doesn't
; move.  A chain gun's spread goes on top.
;------------------------------------------------------------------------------

; Once a frame, before the guns fire (lock_update has put the drawn marks in
; bit 1): with a gun in the centre slot, the assist for a round from the
; muzzle (aa_probe, not one in flight), and the centre crosshair moved to
; where its rounds go: sight_ax, sight_ay.  gun_aim put them on the gun's
; line, and nothing turns it unless this runs.
aim_probe:
        xor a
        ld (aa_d),a
        ld (aa_ds),a
        ld hl,lk_aim                    ; (the linked guns': none yet)
        ld b,4
.z:     ld (hl),a
        inc hl
        djnz .z
        call sel_slot
        ld a,(hl)
        or a
        ret z                           ; (an empty slot)
        cp WPN_LCHAIN_L
        jr z,.lk
        cp WPN_LCHAIN_R
        jr z,.lk
        ld a,(wpn_sel)
        cp WPN_CENTRE
        ret nz
        ld hl,0                         ; the centre gun: from the middle
        ld a,128
        ld de,sight_ax
        call aa_gun
        ld a,(aa_d)                     ; (aim_apply: its turn)
        ld (lk_aim),a
        ld a,(aa_ds)
        ld (lk_aim+1),a
        jr .done
.lk:    ld a,(wpn_slots+2*WPN_LINK_L)   ; a linked chain gun: each fitted,
        cp WPN_LCHAIN_L                 ; from its own muzzle, its own turn
        jr nz,.lr
        ld hl,-LINK_OFF
        ld a,128-LINK_SIGHT_DX
        ld de,sight_lx
        call aa_gun
        ld a,(aa_d)
        ld (lk_aim),a
        ld a,(aa_ds)
        ld (lk_aim+1),a
.lr:    ld a,(wpn_slots+2*WPN_LINK_R)
        cp WPN_LCHAIN_R
        jr nz,.done
        ld hl,LINK_OFF
        ld a,128+LINK_SIGHT_DX
        ld de,sight_rx
        call aa_gun
        ld a,(aa_d)
        ld (lk_aim+2),a
        ld a,(aa_ds)
        ld (lk_aim+3),a
.done:  ld a,(lk_aim)                   ; aa_d, aa_ds: the centre gun's (or
        ld (aa_d),a                     ; the left linked gun's) for aim_apply
        ld a,(lk_aim+1)
        ld (aa_ds),a
        ret

; A gun's assist: HL = its muzzle's offset to the right (round_side), A = its
; crosshair's column unturned, DE -> its crosshair (x, y: y = sight_y
; unturned).  aa_d, aa_ds: its turn; the crosshair moved to where its rounds
; go.
aa_gun:
        ld (aa_col),a
        ld (aa_sp),de
        xor a
        ld (aa_d),a
        ld (aa_ds),a
        push hl
        ld ix,aa_probe
        ld hl,BULLET_STEP
        call spawn_round
        pop hl
        ld a,h
        or l
        call nz,round_side
        call aim_assist
        ld hl,(aa_sp)
        ld a,(aa_d)                     ; across: 128 * d/256 pixels
        sra a
        ld c,a
        ld a,(aa_col)
        add a,c
        ld (hl),a
        inc hl
        ld a,(aa_ds)                    ; up: the slope's change, likewise
        sra a
        neg
        ld c,a
        ld a,(sight_y)
        add a,c
        cp SIGHT_MARGIN
        jr nc,.lo
        ld a,SIGHT_MARGIN
.lo:    cp VIEW_H-SIGHT_MARGIN
        jr c,.hi
        ld a,VIEW_H-SIGHT_MARGIN-1
.hi:    ld (hl),a
        ret
        ASSERT AIM_DEV/2 < SIGHT_MARGIN ; (sight_y is within the view)

; Round IX (a linked chain gun's, just spawned and moved to its muzzle): its
; gun's turn, A = 0 left, 2 right (lk_aim, aim_probe)
lk_apply:
        ld hl,lk_aim
        add hl,a
        ld a,(hl)
        ld (aa_d),a
        inc hl
        ld a,(hl)
        ld (aa_ds),a
        call aim_apply
        ld a,(lk_aim)                   ; (aa_d back to the left's: as
        ld (aa_d),a                     ; aim_probe left it)
        ld a,(lk_aim+1)
        ld (aa_ds),a
        ret

; Round IX (a centre slot round just spawned): the frame's turn (aim_probe)
aim_apply:
        ld a,(aa_d)
        call round_turn
        ld a,(aa_ds)
        ld l,(ix+B_SLOPE)
        ld h,(ix+B_SLOPE+1)
        call add_sa
        ld (ix+B_SLOPE),l
        ld (ix+B_SLOPE+1),h
        ret

aim_assist:
        push iy
        ld hl,$FFFF
        ld (aa_al),hl
        ld iy,zombies
        ld a,NMON
.lp:    ld (aa_n),a
        bit 1,(iy+31)
        jr z,.nx
        ld a,(iy+32)                    ; (most are nowhere near the sight)
        ld hl,aa_col
        sub (hl)
        jp p,.c
        neg
.c:     cp AIM_COLS
        jr nc,.nx
        call lk_alive
        call nc,aa_try
.nx:    ld de,ZREC
        add iy,de
        ld a,(aa_n)
        dec a
        jr nz,.lp
        pop iy
        ld hl,(aa_al)
        ld a,h
        and l
        inc a
        ret z                           ; none
        ld hl,(aa_ac)                   ; sideways: |across| * 256 / along,
        call abs_hl                     ; rounded, at most AIM_DEV
        ld h,l
        ld l,0
        ld de,(aa_al)
        push de
        srl d
        rr e
        add hl,de
        pop de
        call udiv16                     ; (human.asm)
        ld a,h
        or a
        jr nz,.max
        ld a,l
        cp AIM_DEV+1
        jr c,.d
.max:   ld a,AIM_DEV
.d:     ld hl,aa_ac+1
        bit 7,(hl)
        jr z,.t
        neg
.t:     ld (aa_d),a
        ld hl,(aa_dy)                   ; the slope to its middle
        ld a,h
        push af
        call abs_hl
        ld a,h                          ; A:HL = |dy| << 8
        ld h,l
        ld l,0
        ld de,(aa_al)
        call udiv24
        pop af
        rla
        call c,neg_hl
        ld e,(ix+B_SLOPE)
        ld d,(ix+B_SLOPE+1)
        or a
        sbc hl,de                       ; the change, at most AIM_DEV each way
        ld bc,AIM_DEV
        add hl,bc                       ; (0 .. 2*AIM_DEV)
        bit 7,h
        jr z,.c1
        ld hl,0
.c1:    ld a,h
        or a
        jr nz,.c2
        ld a,l
        cp 2*AIM_DEV+1
        jr c,.c3
.c2:    ld hl,2*AIM_DEV
.c3:    or a
        sbc hl,bc
        ld a,l
        ld (aa_ds),a
        jp aim_apply

; Monster IY, in play: the one to aim at, so far?  Ahead of round IX, nearer
; than the last, within AIM_DEV (or its box) of the path each way
aa_try:
        ld l,(iy+0)                     ; relative position
        ld h,(iy+1)
        ld e,(ix+B_X)
        ld d,(ix+B_X+1)
        or a
        sbc hl,de
        ld (aa_rx),hl
        ld l,(iy+2)
        ld h,(iy+3)
        ld e,(ix+B_Z)
        ld d,(ix+B_Z+1)
        or a
        sbc hl,de
        ld (aa_rz),hl
        ld hl,(aa_rx)                   ; along = rx sin + rz cos
        ld e,(ix+B_SIN)
        ld d,(ix+B_SIN+1)
        call fmul
        push hl
        ld hl,(aa_rz)
        ld e,(ix+B_COS)
        ld d,(ix+B_COS+1)
        call fmul
        pop de
        add hl,de
        bit 7,h
        ret nz                          ; behind
        ld de,NEAR
        or a
        sbc hl,de
        ret c                           ; (too close to matter)
        add hl,de
        ld de,(aa_al)
        or a
        sbc hl,de
        ret nc                          ; not nearer
        add hl,de
        ld (aa_tl),hl
        ld de,AIM_DEV                   ; the room each way: along * AIM_DEV
        call fmul                       ; / 256
        ld (aa_lim),hl
        ld hl,(aa_rx)                   ; across = rx cos - rz sin
        ld e,(ix+B_COS)
        ld d,(ix+B_COS+1)
        call fmul
        push hl
        ld hl,(aa_rz)
        ld e,(ix+B_SIN)
        ld d,(ix+B_SIN+1)
        call fmul
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ld (aa_tc),hl
        call abs_hl
        ld a,ZHIT_R
        call aa_in
        ret nc
        ld a,(iy+15)                    ; half its height: a ghoul half as
        ld c,ZHIT_H/2                   ; tall, a lich twice (the devil: its
        cp ZT_GHOUL                     ; chest)
        jr nz,.nh
        ld c,ZHIT_H/4
.nh:    cp ZT_LICH
        jr nz,.hd
        ld c,LICH_H/2
.hd:    cp ZT_DEVIL
        jr nz,.hh
        ld c,DEVIL_AIM_H
.hh:    ld a,c
        ld (aa_half),a
        ld l,(iy+21)                    ; its middle, from the muzzle
        ld h,(iy+22)
        add hl,a
        ld e,(ix+B_Y)
        ld d,(ix+B_Y+1)
        or a
        sbc hl,de
        ld (aa_ty),hl
        ld hl,(aa_tl)                   ; the path's height there
        ld e,(ix+B_SLOPE)
        ld d,(ix+B_SLOPE+1)
        call fmul
        ex de,hl
        ld hl,(aa_ty)
        or a
        sbc hl,de
        call abs_hl
        ld a,(aa_half)
        call aa_in
        ret nc
        ld hl,(aa_tl)                   ; this one
        ld (aa_al),hl
        ld hl,(aa_tc)
        ld (aa_ac),hl
        ld hl,(aa_ty)
        ld (aa_dy),hl
        ret

; HL <= aa_lim + A?  Carry set if so
aa_in:  ld de,(aa_lim)
        add de,a
        inc de
        or a
        sbc hl,de
        ret

; Round IX (just spawned) and its muzzle moved HL units to the right of the
; heading (negative: left), square to it: x += HL * cos, z -= HL * sin
round_side:
        ld (rs_off),hl
        ld de,(cos_y)
        call fmul
        ld e,(ix+B_X)
        ld d,(ix+B_X+1)
        add hl,de
        ld (ix+B_X),l
        ld (ix+B_X+1),h
        ld (ix+B_PX),l
        ld (ix+B_PX+1),h
        ld hl,(rs_off)
        ld de,(sin_y)
        call fmul
        ex de,hl
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        or a
        sbc hl,de
        ld (ix+B_Z),l
        ld (ix+B_Z+1),h
        ld (ix+B_PZ),l
        ld (ix+B_PZ+1),h
        ret

;------------------------------------------------------------------------------
; The missile lock, each frame in flight.  With the missile pod selected the
; reticule is shown (ret_on).  Searching (lock_state 0), it wanders the view.
; A monster drawn last frame (fig_seen: +31) within LOCK_RANGE of the VTOL
; along x and z, the nearest, becomes the target (lock_tgt): locking (1),
; the reticule moves to where it was drawn (+32, +33) at RET_STEP pixels a
; frame, and after LOCK_TIME frames on it (within LOCK_NEAR) the target is
; locked (2): the lock tone, and the reticule stays on it.  The target lost
; (killed, out of view, out of range) it searches again.  With a target,
; K_TARGET (M) moves to the next one (lk_next).  Then the drawn marks are
; cleared for this frame's drawing.
;------------------------------------------------------------------------------
lock_update:
        call sel_slot
        ld a,(hl)
        cp WPN_MISSILE
        jp nz,lock_off
        ld a,1
        ld (ret_on),a
        ld a,(lock_tgt)
        cp $FF
        jr z,.find
        call lk_rec
        call lk_valid
        jr c,.lost
        ld a,K_TARGET                   ; the next target?
        call key_pressed
        call nz,lk_next
        jr .have
.lost:  call lk_lose                    ; the target lost
.find:  call lk_nearest                 ; a new one?
        cp $FF
        jr z,.wander
        ld (lock_tgt),a
        ld a,1
        ld (lock_state),a
        xor a
        ld (lock_t),a
        ld a,(lock_tgt)
        call lk_rec
.have:  call lk_spot                    ; C, B = where it was drawn
        ld a,(lock_state)
        cp 2
        jr nz,.move
        ld a,c                          ; locked: on it
        ld (ret_x),a
        ld a,b
        ld (ret_y),a
        jr lk_clear
.move:  ld e,RET_STEP
        call ret_toward
        jr nc,lk_clear                  ; not on it yet
        ld hl,lock_t
        inc (hl)
        ld a,(hl)
        cp LOCK_TIME
        jr c,lk_clear
        ld a,2                          ; locked
        ld (lock_state),a
        ld a,SFX_LOCK
        ld (sfx_req),a
        jr lk_clear
.wander:
        ld a,(wnd_x)
        ld c,a
        ld a,(wnd_y)
        ld b,a
        ld e,RET_WANDER
        call ret_toward
        jr nc,lk_clear
        call zrand                      ; there: somewhere new, within
        ld d,l                          ; RET_WANDER_R of the view's centre
        ld e,2*RET_WANDER_R+1
        mul d,e                         ; D = 0..2*RET_WANDER_R
        ld a,d
        add a,128-RET_WANDER_R
        ld (wnd_x),a
        ld d,h
        ld e,2*RET_WANDER_R+1
        mul d,e
        ld a,d
        add a,VIEW_CY-RET_WANDER_R
        ld (wnd_y),a
        jr lk_clear
        ASSERT VIEW_CY-RET_WANDER_R >= RET_HALF && VIEW_CY+RET_WANDER_R < VIEW_H-RET_HALF

; No lock, no reticule (another weapon, landed, destroyed)
lock_off:
        xor a
        ld (ret_on),a
        ld a,128                        ; next time from the centre
        ld (ret_x),a
        ld a,VIEW_CY
        ld (ret_y),a
        call lk_lose
        ; fall through

; Every monster's drawn mark (+31): bit 0 cleared, what it was in bit 1 for
; the guns, which fire after this (aim_assist)
lk_clear:
        ld iy,zombies+31
        ld b,NMON
        ld de,ZREC
.lp:    ld a,(iy+0)
        add a,a
        and 2
        ld (iy+0),a
        add iy,de
        djnz .lp
        ret

; No target: searching
lk_lose:
        ld a,$FF
        ld (lock_tgt),a
        xor a
        ld (lock_state),a
        ld (lock_t),a
        ret

; K_TARGET: the next target after lock_tgt (by index, round the list: the
; first after the last) that lk_valid takes, drawn last frame and in range;
; it locks on afresh (locking, lock_t 0: LOCK_TIME again).  Back round to
; the current one, none: the lock is kept.  IY = the target's record.
lk_next:
        ld a,(lock_tgt)
        ld (ln_i),a
.lp:    ld a,(ln_i)
        inc a
        cp NMON
        jr c,.in
        xor a                           ; (round to the first)
.in:    ld (ln_i),a
        ld hl,lock_tgt
        cp (hl)
        jr z,lk_rec                     ; back to it: no other
        call lk_rec
        call lk_valid
        jr c,.lp
        ld a,(ln_i)
        ld (lock_tgt),a
        ld a,1                          ; locking
        ld (lock_state),a
        xor a
        ld (lock_t),a
        ret

; A = monster index -> IY = its record
lk_rec:
        ld e,a
        ld d,ZREC
        mul d,e
        ld iy,zombies
        add iy,de
        ret

; Monster IY: a target?  In play, not fading out, drawn last frame, and
; within LOCK_RANGE of the VTOL along x and z.  Carry set if not; else HL =
; the larger distance (x or z).
lk_valid:
        bit 0,(iy+31)
        scf
        ret z                           ; not seen
        ; fall through

; As lk_valid, seen or not (a missile's target: msl_steer)
lk_alive:
        bit 0,(iy+10)
        scf
        ret z                           ; not in play
        ld a,(iy+16)
        cp GM_DYING
        scf
        ret z                           ; a ghost fading out
        ld hl,(cam_x+1)
        call lk_dist
        ret c
        push hl
        ld hl,(cam_z+1)
        call lk_dist2
        pop de
        ret c
        or a                            ; the larger
        sbc hl,de
        add hl,de
        ret nc
        ex de,hl
        or a
        ret

; HL = a point's x: HL = |x - monster IY's x|, carry set if over LOCK_RANGE
lk_dist:
        ld e,(iy+0)
        ld d,(iy+1)
        jr lk_d
lk_dist2:                               ; (z)
        ld e,(iy+2)
        ld d,(iy+3)
lk_d:   or a
        sbc hl,de
        call abs_hl
        ld de,LOCK_RANGE+1
        or a
        sbc hl,de
        ccf
        ret c                           ; too far
        add hl,de
        or a
        ret

; The nearest target (lk_valid): A = its index, $FF if none
lk_nearest:
        ld a,$FF
        ld (ln_best),a
        ld hl,$FFFF
        ld (ln_dist),hl
        ld iy,zombies
        xor a
.lp:    ld (ln_i),a
        call lk_valid
        jr c,.nx
        ld de,(ln_dist)
        or a
        sbc hl,de
        jr nc,.nx                       ; not nearer
        add hl,de
        ld (ln_dist),hl
        ld a,(ln_i)
        ld (ln_best),a
.nx:    ld de,ZREC
        add iy,de
        ld a,(ln_i)
        inc a
        cp NMON
        jr c,.lp
        ld a,(ln_best)
        ret

; Monster IY -> C, B = where it was drawn (+32, +33), kept so the reticule
; stays in the view
lk_spot:
        ld a,(iy+32)
        cp RET_HALF
        jr nc,.x1
        ld a,RET_HALF
.x1:    cp 256-RET_HALF
        jr c,.x2
        ld a,255-RET_HALF
.x2:    ld c,a
        ld a,(iy+33)
        cp RET_HALF
        jr nc,.y1
        ld a,RET_HALF
.y1:    cp VIEW_H-RET_HALF
        jr c,.y2
        ld a,VIEW_H-1-RET_HALF
.y2:    ld b,a
        ret

; Move the reticule towards (C, B) by up to E pixels on each axis: carry
; set if it is then within LOCK_NEAR of it on both.  Keeps B, C.
ret_toward:
        ld hl,ret_x
        ld a,c
        call .ax
        ld hl,ret_y
        ld a,b
        call .ax
        ld a,(ret_x)
        sub c
        jr nc,.p1
        neg
.p1:    cp LOCK_NEAR+1
        ret nc
        ld a,(ret_y)
        sub b
        jr nc,.p2
        neg
.p2:    cp LOCK_NEAR+1
        ret
.ax:    sub (hl)                        ; A = the way to go
        ret z
        jr c,.dn
        cp e
        jr c,.up
        ld a,e
.up:    add a,(hl)
        ld (hl),a
        ret
.dn:    neg
        cp e
        jr c,.d2
        ld a,e
.d2:    ld d,a
        ld a,(hl)
        sub d
        ld (hl),a
        ret

;------------------------------------------------------------------------------
; Missile IX, before its step: turn towards its target (B_TGT) by up to
; MISSILE_TURN sideways (B_YAW) and up or down (B_PIT), aiming at its middle
; (MSL_AIM_Y above its feet).  The target gone (killed, fading out) or more
; than LOCK_RANGE from the missile along x or z: no more tracking, it flies
; straight on.  When the turn changes its heading or climb (their high
; bytes), its direction is worked out again (B_SIN, B_COS, B_S, B_SLOPE,
; and the cell spans afresh).
;------------------------------------------------------------------------------
msl_steer:
        ld a,(ix+B_TGT)
        cp $FF
        ret z
        call lk_rec
        bit 0,(iy+10)
        jp z,.lost
        ld a,(iy+16)
        cp GM_DYING
        jp z,.lost
        ld l,(ix+B_X)                   ; dx, dz from the missile
        ld h,(ix+B_X+1)
        call lk_dist
        jp c,.lost
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        call lk_dist2
        jp c,.lost
        ld l,(iy+0)
        ld h,(iy+1)
        ld e,(ix+B_X)
        ld d,(ix+B_X+1)
        or a
        sbc hl,de
        ld (ms_dx),hl
        ld l,(iy+2)
        ld h,(iy+3)
        ld e,(ix+B_Z)
        ld d,(ix+B_Z+1)
        or a
        sbc hl,de
        ld (ms_dz),hl
        ex de,hl
        ld hl,(ms_dx)
        call atan2                      ; the heading to it
        ld c,a
        xor a
        ld (ms_chg),a
        ld a,c
        ld hl,B_YAW
        call ms_turn
        ld hl,(ms_dx)                   ; horizontal distance: max + 3/8 min
        call abs_hl
        push hl
        ld hl,(ms_dz)
        call abs_hl
        pop de
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl                        ; HL = max, DE = min
.mx:    push hl
        ex de,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        pop de
        add hl,de
        push hl
        ld l,(iy+21)                    ; dy: to its middle
        ld h,(iy+22)
        ld de,MSL_AIM_Y
        add hl,de
        ld e,(ix+B_Y)
        ld d,(ix+B_Y+1)
        or a
        sbc hl,de
        pop de
        call atan2                      ; the climb to it
        ld hl,B_PIT
        call ms_turn
        ld a,(ix+B_PIT+1)               ; kept within +-MSL_PITCH_MAX
        add a,$80
        cp $80+MSL_PITCH_MAX+1
        jr c,.p1
        ld (ix+B_PIT+1),MSL_PITCH_MAX
        jr .p2
.p1:    cp $80-MSL_PITCH_MAX
        jr nc,.p2
        ld (ix+B_PIT+1),-MSL_PITCH_MAX & $FF
.p2:    ld a,(ms_chg)                   ; turned to a new heading or climb?
        or a
        ret z
        ld hl,MISSILE_STEP
        jp rnd_dir
.lost:  ld (ix+B_TGT),$FF               ; no more tracking
        ret

;------------------------------------------------------------------------------
; Bomb (WPN_BOMB, the selected slot's): gun_fire jumps here.  One bomb,
; released straight ahead at the VTOL's speed + BOMB_SPEED (at least 1 unit
; a frame), gliding down from BOMB_ANGLE, steeper every BOMB_STEEPEN frames
; (bomb_steer), to the ground or whatever it hits first.
;------------------------------------------------------------------------------
bomb_drop:
        call free_round
        ret c
        call take_ammo
        ret c
        ld a,BOMB_INTERVAL-1
        ld (gun_wait),a
        ld a,(speed)                    ; (signed: reversing, less)
        add a,BOMB_SPEED
        jp p,.pos
        xor a
.pos:   or a
        jr nz,.st
        inc a                           ; at least 1
.st:    ld l,a
        ld h,0
        push hl
        call spawn_round
        pop hl
        ld (ix+B_KIND),BK_BOMB          ; no direct damage: its blast
        ld (ix+B_TGT),l                 ; its length a frame
        ld a,(yaw_frac)                 ; its heading: the view's,
        ld (ix+B_YAW),a
        ld a,(yaw)
        ld (ix+B_YAW+1),a
        ld (ix+B_PIT),BOMB_STEEPEN      ; (the low byte: frames to steeper)
        ld (ix+B_PIT+1),-BOMB_ANGLE & $FF   ; gliding down
        call rnd_dir
        ld a,SFX_ROCKET                 ; (a release woosh)
        ld (sfx_req),a
        ret
        ASSERT BOOST_SPEED+BOMB_SPEED < 128 ; (a signed byte, and B_TGT's)
        ASSERT SPEED_MAX <= BOOST_SPEED

        ASSERT BOMB_ANGLE < MSL_PITCH_MAX && BOMB_STEEPEN > 0

; Bomb IX, before its step: every BOMB_STEEPEN frames (B_PIT's low byte
; counts them down) its climb one angle step steeper (B_PIT's high byte),
; to -MSL_PITCH_MAX, and its direction afresh
bomb_steer:
        dec (ix+B_PIT)
        ret nz
        ld (ix+B_PIT),BOMB_STEEPEN
        ld a,(ix+B_PIT+1)
        cp -MSL_PITCH_MAX & $FF
        ret z                           ; as steep as it goes
        dec (ix+B_PIT+1)
        ld l,(ix+B_TGT)                 ; its length a frame
        ld h,0
        jp rnd_dir

; Round IX's direction from its heading and climb (the high bytes of B_YAW,
; B_PIT), HL = its length along its path a frame: B_SIN, B_COS, B_S,
; B_SLOPE, and its cell spans afresh.  (A missile turning, a bomb diving.)
rnd_dir:
        ld (sr_len),hl
        ld a,(ix+B_YAW+1)               ; its new direction
        push af
        call get_sin
        ld (ix+B_SIN),l
        ld (ix+B_SIN+1),h
        pop af
        add a,64
        call get_sin
        ld (ix+B_COS),l
        ld (ix+B_COS+1),h
        ld a,(ix+B_PIT+1)
        push af
        call get_sin
        ld (sr_sin),hl
        pop af
        add a,64
        call get_sin
        ld (sr_cos),hl
        call round_climb
        xor a                           ; the cell spans afresh
        ld (ix+B_TDX),a
        ld (ix+B_TDX+1),a
        ret

; A = the angle wanted, HL = B_YAW or B_PIT: turn missile IX's angle there
; (8.8) towards it by up to MISSILE_TURN.  ms_chg = 1 if its high byte
; changed.
ms_turn:
        push ix
        pop de
        add hl,de                       ; HL -> the angle
        ld (ms_p),hl
        ld d,a                          ; DE = wanted * 256
        ld e,0
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = the angle now
        ld (ms_old),hl
        ex de,hl
        or a
        sbc hl,de                       ; HL = the turn (wrapping: signed)
        bit 7,h
        jr nz,.neg
        ld bc,MISSILE_TURN
        or a
        sbc hl,bc
        add hl,bc
        jr c,.ok
        ld hl,MISSILE_TURN
        jr .ok
.neg:   ld bc,-MISSILE_TURN
        or a
        sbc hl,bc
        add hl,bc
        jr nc,.ok
        ld hl,-MISSILE_TURN
.ok:    ld de,(ms_old)
        add hl,de
        ex de,hl
        ld hl,(ms_p)
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,(ms_old+1)
        cp d
        ret z
        ld a,1
        ld (ms_chg),a
        ret
        ASSERT MISSILE_TURN < 64*256    ; (under a quarter turn a frame)

; HL = x, DE = z (signed) -> A = the angle of (x, z) from +z towards +x,
; 256 a turn (as yaw: 64 = +x).  0 for (0, 0).  For a climb, HL = dy and
; DE = the horizontal distance (>= 0): -64..64.
atan2:
        ld (at_x),hl
        ld (at_z),de
        call abs_hl
        push hl
        ex de,hl
        call abs_hl                     ; HL = |z|
        pop de                          ; DE = |x|
.sc:    ld a,h                          ; both under 1024 (for * 64)
        or d
        and $FC
        jr z,.ok
        srl h
        rr l
        srl d
        rr e
        jr .sc
.ok:    ld a,h
        or l
        or d
        or e
        ret z                           ; (0, 0)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.steep                     ; |z| < |x|
        ex de,hl                        ; |x| / |z|
        call .div
        jr .quad
.steep: call .div                       ; |z| / |x|
        neg
        add a,64
.quad:  ld c,a
        ld a,(at_z+1)
        bit 7,a
        jr z,.zp
        ld a,128                        ; z < 0
        sub c
        ld c,a
.zp:    ld a,(at_x+1)
        bit 7,a
        ld a,c
        ret z
        neg                             ; x < 0
        ret
.div:   add hl,hl                       ; HL * 64 / DE (HL <= DE): atan_tab
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        call udiv16                     ; (human.asm)
        ld a,l
        ld hl,atan_tab
        add hl,a
        ld a,(hl)
        ret

; round(atan(k/64) * 128/pi), k = 0..64: the angle (256 a turn) whose tan
; is k/64
atan_tab:
            db 0, 1, 1, 2, 3, 3, 4, 4, 5, 6, 6, 7, 8
            db 8, 9, 9, 10, 11, 11, 12, 12, 13, 13, 14, 15, 15
            db 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22
            db 22, 23, 23, 24, 24, 25, 25, 25, 26, 26, 27, 27, 27
            db 28, 28, 29, 29, 29, 30, 30, 30, 31, 31, 31, 32, 32
        ASSERT $ - atan_tab == 65

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

; A = random byte -> A = -rs_dev..+rs_dev, evenly spread
dev_n:
        ld d,a
        ld a,(rs_dev)
        ld e,a
        add a,a
        inc a
        push de
        ld e,a
        mul d,e
        ld a,d
        pop de
        sub e
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
        ; fall through

; As take_ammo, from the slot HL points to
take_slot_ammo:
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
        ld b,NBULLETS-NFIRE             ; (the last are the fireballs')
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
.pt:    ; fall through

; Round IX's climb: sr_len along its path a frame, at the climb whose sin,
; cos are sr_sin, sr_cos: B_S (horizontal distance a frame) and B_SLOPE
round_climb:
        ld hl,(sr_len)                  ; horizontal distance per frame
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
; Then sight_y: the gunsight's row for the selected weapon, where its rounds
; are SIGHT_RANGE ahead: the centre slot's from sight_rows (by its tilt), a
; pylon's or linked gun's VIEW_CY + GUN_SIGHT_DY (straight ahead), kept
; SIGHT_MARGIN rows inside the view; the crosshairs there, unturned (aim_probe
; turns them).
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
.sight: ld c,VIEW_CY+GUN_SIGHT_DY
        ld a,(wpn_sel)
        cp WPN_CENTRE
        jr nz,.sy                       ; a pylon: straight ahead
        ld a,(gun_tilt)                 ; the centre slot: by its tilt
        add a,GUN_TILT_DN
        ld hl,sight_rows
        add hl,a
        ld a,(hl)
        ld c,a
        cp SIGHT_MARGIN
        jr nc,.lo
        ld c,SIGHT_MARGIN
.lo:    ld a,c
        cp VIEW_H-SIGHT_MARGIN
        jr c,.sy
        ld c,VIEW_H-SIGHT_MARGIN-1
.sy:    ld a,c
        ld (sight_y),a
        ld (sight_ay),a                 ; (the crosshairs: aim_probe moves
        ld (sight_ly),a                 ; them)
        ld (sight_ry),a
        ld a,128
        ld (sight_ax),a
        ld a,128-LINK_SIGHT_DX
        ld (sight_lx),a
        ld a,128+LINK_SIGHT_DX
        ld (sight_rx),a
        call sel_slot                   ; the crosshairs (sight_mask): a
        ld a,(hl)                       ; linked chain gun selected, one for
        ld c,SM_CENTRE                  ; each fitted; else the centre one
        cp WPN_LCHAIN_L
        jr z,.lk
        cp WPN_LCHAIN_R
        jr nz,.sm
.lk:    ld c,0
        ld a,(wpn_slots+2*WPN_LINK_L)
        cp WPN_LCHAIN_L
        jr nz,.lr
        set 1,c
.lr:    ld a,(wpn_slots+2*WPN_LINK_R)
        cp WPN_LCHAIN_R
        jr nz,.sm
        set 2,c
.sm:    ld a,c
        ld (sight_mask),a
        ret
        ASSERT SM_CENTRE == 1 && SM_LINK_L == 2 && SM_LINK_R == 4

; The centre gunsight's row for a tilt of k (256 = 360 deg), k =
; -GUN_TILT_DN..GUN_TILT_UP: where its rounds are SIGHT_RANGE (R) ahead,
; from a muzzle GUN_DY below the camera: round(VIEW_CY - 128 tan(a) +
; 128 * -GUN_DY / (R cos a)), before the margin (test_aim.py checks it)
sight_rows:
            db 194, 188, 182, 176, 171, 165, 160, 156, 151, 146, 142
            db 138, 134, 130, 126, 122, 118, 115, 111, 108, 104, 101
            db 97, 94, 91, 87, 84, 81, 78, 75, 71, 68, 65
            db 62, 59, 56, 53, 49, 46, 43, 40, 36, 33, 30
        ASSERT $ - sight_rows == GUN_TILT_DN + GUN_TILT_UP + 1
        ASSERT GUN_TILT_UP <= GUN_TILT_DN

;------------------------------------------------------------------------------
; A lich's fireballs, every frame (not with the VTOL a wreck).  A lich with
; its reload done (LICH_WAIT 0) and the VTOL within FB_RANGE fires at where
; the VTOL will be: from its velocity (its move last frame, sideways and up
; or down too) and the flight time at FB_MS, worked out twice over.  The
; aim is then turned by up to FB_DEV each way (round_spread).  A
; fireball is a round (BK_FIREBALL, in its own records: the player's guns
; can't use them up) that passes through monsters and stops at a building,
; the ground, the VTOL (within FB_HIT_R: fb_step) or after FB_FRAMES frames
; (FB_RANGE).  Wherever it stops it bursts (rocket_blast): FB_DMG within
; FB_R to the VTOL, humans and base tiles, not to monsters.
;------------------------------------------------------------------------------
lich_update:
        ld hl,(cam_x+1)                 ; the VTOL's velocity
        ld de,(lf_px)
        ld (lf_px),hl
        or a
        sbc hl,de
        ld (lf_vx),hl
        ld hl,(cam_y)
        ld de,(lf_py)
        ld (lf_py),hl
        or a
        sbc hl,de
        ld (lf_vy),hl
        ld hl,(cam_z+1)
        ld de,(lf_pz)
        ld (lf_pz),hl
        or a
        sbc hl,de
        ld (lf_vz),hl
        ld a,(vtol_dead)
        or a
        ret nz
        ld iy,zombies+NZOMB*ZREC
        ld b,NSPEC
.lp:    push bc
        bit 0,(iy+10)
        jr z,.nx
        ld a,(iy+15)
        cp ZT_LICH
        jr nz,.nx
        ld a,(iy+LICH_WAIT)
        or a
        jr z,.rdy
        dec (iy+LICH_WAIT)
        jr .nx
.rdy:   push iy
        call lich_fire
        pop iy
.nx:    ld de,ZREC
        add iy,de
        pop bc
        djnz .lp
        ret

; Lich IY, reloaded: a fireball at the VTOL, if it's in range and a record
; is free (else it stays ready)
lich_fire:
        ld l,(iy+0)                     ; from its head
        ld h,(iy+1)
        ld (lf_x),hl
        ld l,(iy+2)
        ld h,(iy+3)
        ld (lf_z),hl
        ld hl,(cam_x+1)                 ; at the VTOL now
        ld (lf_ax),hl
        ld hl,(cam_y)
        ld (lf_ay),hl
        ld hl,(cam_z+1)
        ld (lf_az),hl
        call lf_dist
        ld de,FB_RANGE+1
        or a
        sbc hl,de
        ret nc                          ; out of range
        add hl,de
        ld b,2                          ; where it'll be: the flight there,
.it:    push bc                         ; then the flight to that place
        call lf_lead
        call lf_dist
        pop bc
        djnz .it
        ld ix,bullets+(NBULLETS-NFIRE)*BREC
        ld b,NFIRE
        ld de,BREC
.f:     ld a,(ix+B_STATE)
        or a
        jr z,.got
        add ix,de
        djnz .f
        ret
.got:   ld a,(iy+LICH_FRAMES)           ; the next, so many frames on
        dec a
        ld (iy+LICH_WAIT),a
        ld hl,FB_STEP
        call spawn_round
        ld (ix+B_KIND),BK_FIREBALL
        ld (ix+B_TGT),FB_FRAMES         ; frames left
        ld hl,(lf_x)
        ld (ix+B_X),l
        ld (ix+B_X+1),h
        ld (ix+B_PX),l
        ld (ix+B_PX+1),h
        ld hl,LICH_MOUTH
        ld (ix+B_Y),l
        ld (ix+B_Y+1),h
        ld (ix+B_PY),l
        ld (ix+B_PY+1),h
        ld hl,(lf_z)
        ld (ix+B_Z),l
        ld (ix+B_Z+1),h
        ld (ix+B_PZ),l
        ld (ix+B_PZ+1),h
        ld hl,(lf_dx)                   ; its heading and climb
        ld de,(lf_dz)
        call atan2
        ld (ix+B_YAW+1),a
        ld hl,(lf_dy)
        ld de,(lf_dh)
        call atan2
        ld (ix+B_PIT+1),a
        ld hl,FB_STEP
        call rnd_dir
        ld a,FB_DEV
        call round_spread
        ld a,SFX_ROCKET                 ; (a woosh)
        ld (sfx_req),a
        ret

; HL = the distance from the lich to the aim -> lf_ax, ay, az = where the
; VTOL will be after a fireball's flight that far
lf_lead:
        ld a,h                          ; (no further: the time fits a byte)
        cp FB_D_MAX>>8
        jr c,.d
        ld hl,FB_D_MAX-1
.d:     add hl,hl                       ; frames, 4.4 fixed: d * 16 / FB_STEP
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,FB_STEP
        call udiv16                     ; (human.asm)
        ld a,l
        ld (lf_t),a
        ld hl,(lf_vx)
        ld de,(cam_x+1)
        call .ax
        ld (lf_ax),hl
        ld hl,(lf_vy)
        ld de,(cam_y)
        call .ax
        ld (lf_ay),hl
        ld hl,(lf_vz)
        ld de,(cam_z+1)
        call .ax
        ld (lf_az),hl
        ret
.ax:    push de                         ; HL = DE + velocity HL * lf_t / 16
        ld a,h
        push af
        call abs_hl
        ld d,l
        ld a,(lf_t)
        ld e,a
        mul d,e
        ex de,hl
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        pop af
        rla
        call c,neg_hl
        pop de
        add hl,de
        ret
FB_D_MAX        equ $B00            ; 2816 units: * 16 / FB_STEP fits a byte
        ASSERT FB_RANGE < FB_D_MAX && (FB_D_MAX*16)/FB_STEP < 256 && (FB_D_MAX & 255) == 0

; lf_dx, dy, dz = from the lich's head to the aim, lf_dh its horizontal
; distance -> HL = its distance
lf_dist:
        ld hl,(lf_ax)
        ld de,(lf_x)
        or a
        sbc hl,de
        ld (lf_dx),hl
        ld hl,(lf_az)
        ld de,(lf_z)
        or a
        sbc hl,de
        ld (lf_dz),hl
        ld hl,(lf_ay)
        ld de,LICH_MOUTH
        or a
        sbc hl,de
        ld (lf_dy),hl
        ld hl,(lf_dx)
        ld de,(lf_dz)
        call lf_hyp
        ld (lf_dh),hl
        ld de,(lf_dy)
        ; fall through
; HL, DE (signed) -> HL ~ their length: max + 3/8 min
lf_hyp:
        call abs_hl
        ex de,hl
        call abs_hl
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl                        ; HL = max, DE = min
.mx:    push hl
        ex de,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        pop de
        add hl,de
        ret

; Fireball IX, its path this frame set up (bullet_step): its last frame, or
; the VTOL on the path within FB_HIT_R, ends the path there (b_send), as
; reaching the ground does (b_gnd): a burst
fb_step:
        dec (ix+B_TGT)
        jr nz,.v
        ld a,1
        ld (b_gnd),a
.v:     ld a,(vtol_dead)
        or a
        ret nz
        ld hl,(cam_x+1)
        ld de,(b_x0)
        or a
        sbc hl,de
        ld (b_rx),hl
        ld hl,(cam_z+1)
        ld de,(b_z0)
        or a
        sbc hl,de
        ld (b_rz),hl
        ld hl,(b_rx)                    ; along = rx sinY + rz cosY
        ld de,(b_sin)
        call fmul
        push hl
        ld hl,(b_rz)
        ld de,(b_cos)
        call fmul
        pop de
        add hl,de
        bit 7,h
        ret nz                          ; behind it
        ld (b_al),hl
        ld de,(b_send)
        or a
        sbc hl,de
        ret nc                          ; beyond this frame's path
        ld hl,(b_rz)                    ; across = rx cosY - rz sinY
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
        ld de,FB_HIT_R+1
        or a
        sbc hl,de
        ret nc
        ld hl,(b_al)                    ; and at its height?
        call b_y_at
        ld de,(cam_y)
        or a
        sbc hl,de
        call abs_hl
        ld de,FB_HIT_R+1
        or a
        sbc hl,de
        ret nc
        ld hl,(b_al)
        ld (b_send),hl
        ld a,1
        ld (b_gnd),a
        ret

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
; Debug: key 7 changes the centre slot's gun, machine gun -> laser -> chain
; gun -> machine gun (anything else there: the machine gun), with its full
; (infinite) load, and selects the centre slot
;------------------------------------------------------------------------------
debug_gun_cycle:
        ld hl,KB_7
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
; Debug: key 0 kills every enemy of the current wave at once (zombies and
; its specials, none left fading: dk_monsters); the humans are left as they
; are.  zombie_update then finds the wave wiped out: the next wave, or after
; the last the level complete.
; Key 9 picks a level instead (debug_level_select, zpolice.asm: Q / A and
; SPACE, over the view).
; Key 8 kills them all, counts every human still in the city or aboard as
; rescued, and ends the level, on to the final boss: the wave
; becomes the level's last, the level the one before the
; last (so level complete moves on to LEVEL_LAST), and that level starts at
; its last wave, the devil's (resume_wave $FF: next_level keeps it to the
; level's waves, as a save game's).
;------------------------------------------------------------------------------
debug_killall:
        ld hl,KB_8
        call key_code_pressed
        jr z,.k9
        ld a,LEVEL_LAST-1
        ld (level),a
        ld a,$FF
        ld (resume_wave),a
        jr .end
.k9:    ld hl,KB_9
        call key_code_pressed
        jp nz,debug_level_select        ; (zpolice.asm: back here if not)
        jr .k0
.end:   ld a,(level_cur+LV_WAVES)
        ld (wave_number),a              ; its last wave
        jr .all
.k0:    ld hl,KB_0
        call key_code_pressed
        ret z
        jr dk_monsters
.all:   call dk_monsters
        jr dk_humans

; Every monster record gone (zombies and specials), none attacking
dk_monsters:
        ld ix,zombies
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
        ret

; Every human still in the city or aboard: rescued (key 8)
dk_humans:
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
        ld (wf_t),a                     ; (no crash yet)
        ld (wf_hit),a
        ld a,VIEW_CY+GUN_SIGHT_DY
        ld (sight_y),a
        ld (sight_ay),a
        ld (sight_ly),a
        ld (sight_ry),a
        ld a,128
        ld (sight_ax),a
        ld a,128-LINK_SIGHT_DX
        ld (sight_lx),a
        ld a,128+LINK_SIGHT_DX
        ld (sight_rx),a
        ld a,SM_CENTRE                  ; the centre crosshair
        ld (sight_mask),a
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
        call aim_apply
        ld (ix+B_DMG),LASER_DMG         ; per beam frame on a target
        call bullet_step                ; trace it to the first thing it meets
        ld a,(ix+B_STATE)
        or a
        ret z                           ; off the map (can't, inside the wall)
        ld (ix+B_STATE),3               ; beam
        ret

;------------------------------------------------------------------------------
; The crash, each frame the VTOL is a wreck (vtol_dead; vtol_wreck, player.asm,
; spins it down): fire bursts WRECK_AHEAD in front of the camera.  The first
; frame an explosion (WRECK_BOOM, a shake, a bang); falling, WRECK_DEBRIS
; every other frame; the frame it is down (dead_down) the impact
; (WRECK_IMPACT, the heavy shake, the crash); then WRECK_EMBERS every 4th
; frame until GAME OVER.
;------------------------------------------------------------------------------
wreck_fx:
        ld hl,wf_t
        ld a,(hl)
        inc (hl)
        jr nz,.n
        dec (hl)                        ; (at most 255)
.n:     or a
        jr nz,.fall
        ld hl,WRECK_EYE                 ; destroyed: the explosion, in front
        ld (wf_drop),hl                 ; of the eye
        ld a,WRECK_BOOM
        call wf_burst
        ld hl,WRECK_DROP                ; (the rest lower: debris)
        ld (wf_drop),hl
        ld a,SFX_BOOM_ROCKET
        ld (sfx2_req),a
        ld a,(shake_t)
        or a
        ret nz
        ld a,SHAKE_LEN
        ld (shake_t),a
        ret
.fall:  ld a,(dead_down)
        or a
        jr nz,.down
        ld a,(wf_t)                     ; falling: debris
        and 1
        ret nz
        ld a,WRECK_DEBRIS
        jr wf_burst
.down:  ld a,(wf_hit)
        or a
        jr nz,.burn
        inc a
        ld (wf_hit),a
        ld a,SFX_CRASH                  ; the impact
        ld (sfx2_req),a
        call shake_big                  ; (zpolice.asm)
        ld a,WRECK_IMPACT
        jr wf_burst
.burn:  ld a,(wf_t)                     ; on the ground: embers
        and 3
        ret nz
        ld a,WRECK_EMBERS
        ; fall through

; A fire particles WRECK_AHEAD in front of the camera, wf_drop below the
; eye (but WRECK_LOW above the ground at least)
wf_burst:
        ld (rb_parts),a
        ld hl,WRECK_AHEAD               ; x = cam x + d sin(yaw)
        ld de,(sin_y)
        call fmul
        ld de,(cam_x+1)
        add hl,de
        ld (rb_x),hl
        ld hl,WRECK_AHEAD               ; z = cam z + d cos(yaw)
        ld de,(cos_y)
        call fmul
        ld de,(cam_z+1)
        add hl,de
        ld (rb_z),hl
        ld hl,(wf_drop)                 ; y
        ld de,WRECK_LOW
        add hl,de
        ex de,hl
        ld hl,(cam_y)
        or a
        sbc hl,de
        jr nc,.y
        ld hl,0
.y:     ld de,WRECK_LOW
        add hl,de
        ld (rb_y),hl
        jp fire_burst

wf_t:       db 0                        ; wreck_fx: frames since destroyed
wf_hit:     db 0                        ;   1: the impact done
wf_drop:    dw WRECK_DROP               ; wf_burst: how far below the eye

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
        ld (b_fire),a
        ld a,(ix+B_KIND)                ; a fireball passes through monsters
        cp BK_FIREBALL
        jr nz,.nofb
        ld (b_fire),a
.nofb:
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
        ld a,(b_fire)                   ; a fireball's end, or the VTOL?
        or a
        call nz,fb_step
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
        jp nz,rocket_blast
        ld a,(ix+B_DMG)                 ; a chain gun's round (the linked
        cp CHAIN_DMG                    ; ones' too): a spark
        ret nz
        ld l,(ix+B_X)
        ld h,(ix+B_X+1)
        ld (ps_x),hl
        ld l,(ix+B_Y)
        ld h,(ix+B_Y+1)
        ld (ps_y),hl
        ld l,(ix+B_Z)
        ld h,(ix+B_Z+1)
        ld (ps_z),hl
        ld hl,FIRE_COL0 | SPARK_LIFE<<8
        ld (ps_col),hl
        xor a
        ld (ps_fire),a
        ld c,1
        jp part_spray
SPARK_LIFE      equ 3               ; frames: bright, gone at once

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
        ld a,(b_fire)
        or a                            ; (carry clear)
        ret nz                          ; a fireball: none
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
        jp nc,.zn                       ; beyond this frame's path
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
        ld a,(iy+15)                    ; (a lich: twice as wide; the devil
        cp ZT_DEVIL                     ; a square)
        ld a,DEVIL_HIT_R
        jr z,.wd
        ld a,(iy+15)
        cp ZT_LICH
        ld a,ZHIT_R
        jr nz,.wd
        ld a,2*ZHIT_R
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
        ld a,(iy+15)                    ; a ghoul: half as tall,
        cp ZT_LICH                      ; a lich twice, the devil its height
        jr nz,.zd
        ld de,LICH_H+1
.zd:    cp ZT_DEVIL
        jr nz,.zg
        ld de,DEVIL_H+1
.zg:    cp ZT_GHOUL
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
        ld a,(dv_hum)                   ; (not over the devil's whine)
        or a
        jr nz,.hurt
        ld a,SFX_SPLAT
        ld (sfx3_req),a
.hurt:  ld a,(iy+15)
        cp ZT_LICH
        jr z,.lich
        cp ZT_DEVIL                     ; (the devil: 16 bits too)
        jr z,.lich
        ld a,(iy+18)
        sub c
        jr z,.kill
        jr c,.kill
        ld (iy+18),a
        ret
.lich:  ld a,(iy+18)                    ; a lich: 16-bit hit points
        sub c
        ld (iy+18),a
        ld a,(iy+LICH_HP_HI)
        sbc a,0
        ld (iy+LICH_HP_HI),a
        jr c,.kill
        or (iy+18)
        jr z,.kill
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
        cp ZT_DEVIL
        jr nz,.gx
        ld (ix+17),DV_DIE_FR            ; the devil sinks (devil.asm)
        ld a,SFX_BOOM_MISSILE
        ld (sfx2_req),a
.gx:    pop ix
        ret

;------------------------------------------------------------------------------
; Rocket, missile, bomb or shell IX has stopped (at B_X, B_Y, B_Z): its
; damage (rb_dmg: BLAST_DMG, MISSILE_DMG, BOMB_DMG, AUTOCANNON_DMG, ...) to
; every zombie, human and base tile (a bomb's: the VTOL too, rb_vtol; a
; fireball's: the VTOL, not the monsters) within its reach (rb_r: BLAST_R, MISSILE_R, BOMB_R, AUTOCANNON_R, ...) on
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
        ld hl,AUTOCANNON_R              ; an autocannon shell
        ld b,AUTOCANNON_DMG
        ld c,AUTOCANNON_PARTS
        ld e,SFX_BOOM_AUTOCANNON
        cp BK_AUTOCANNON
        jr z,.k
        ld hl,BOMB_R                    ; a bomb (the missile's boom)
        ld b,BOMB_DMG
        ld c,BOMB_PARTS
        ld e,SFX_BOOM_MISSILE
        cp BK_BOMB
        jr z,.k
        ld hl,FB_R                      ; a lich's fireball
        ld b,FB_DMG
        ld c,FB_PARTS
        ld e,SFX_BOOM_ROCKET
        cp BK_FIREBALL
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
        ld a,(ix+B_KIND)                ; a bomb's hits the VTOL too
        cp BK_BOMB
        call z,rb_vtol
        ld a,(ix+B_KIND)                ; a fireball's too, not the monsters
        cp BK_FIREBALL
        jr nz,.mons
        call rb_vtol
        jp .hums
.mons:  ; zombies and special monsters (their feet's height, +21)
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
        ld a,(iy+15)
        cp ZT_DEVIL
        jr nz,.zb
        call rb_devil                   ; (its body: tall and wide)
        jr nc,.zn
        jr .zh
.zb:    ld l,(iy+0)
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
.zh:
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
.hums:  ; humans still waiting (x, z, y of their feet)
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

; A bomb's burst: the VTOL takes rb_dmg if it is within rb_r on each axis
; (its camera point)
rb_vtol:
        ld a,(vtol_dead)
        or a
        ret nz                          ; (a wreck already)
        ld hl,(cam_x+1)
        ld de,(rb_x)
        call rb_near
        ret nc
        ld hl,(cam_z+1)
        ld de,(rb_z)
        call rb_near
        ret nc
        ld hl,(cam_y)
        ld de,(rb_y)
        call rb_near
        ret nc
        ld a,(rb_dmg)
        jp vtol_damage                  ; (resident)

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

; The devil IY within a blast (rb_x/y/z, rb_r)?  Carry set if so: its body
; DEVIL_HIT_R either side of it and DEVIL_H up from its feet, plus rb_r
rb_devil:
        ld hl,(rb_r)
        push hl
        ld de,DEVIL_HIT_R
        add hl,de
        ld (rb_r),hl                    ; across: its half width further
        ld l,(iy+0)
        ld h,(iy+1)
        ld de,(rb_x)
        call rb_near
        jr nc,.x
        ld l,(iy+2)
        ld h,(iy+3)
        ld de,(rb_z)
        call rb_near
        jr nc,.x
        pop hl                          ; up: from its middle, its half height
        push hl                         ; further
        ld de,DEVIL_H/2
        add hl,de
        ld (rb_r),hl
        ld l,(iy+21)
        ld h,(iy+22)
        add hl,de
        ex de,hl
        ld hl,(rb_y)
        call rb_near
.x:     pop hl
        ld (rb_r),hl                    ; (rb_r as it was; the flags kept)
        ret

; HL = s -> HL = height of the path there, y0 + s * slope, the drop (or
; climb) rounded to the nearest unit: truncated, a slow round's (a bomb's,
; 20 units a frame) lost up to 1 unit a frame, flattening its glide.  s is
; within one frame's path (under 32768).
b_y_at:
        ld de,(b_slope)
        bit 7,d
        jr z,.up
        push hl                         ; descending: DE = |slope|
        ex de,hl
        call neg_hl
        ex de,hl
        pop hl
        call .mag
        call neg_hl
        jr .add
.up:    call .mag
.add:   ld de,(b_y0)
        add hl,de
        ret
.mag:   add hl,hl                       ; round(s * DE / 256), both >= 0:
        call fmul                       ;   (floor(2 s DE / 256) + 1) / 2
        inc hl
        srl h
        rr l
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
rs_off:     dw 0                        ; round_side
aa_col:     db 128                      ; aim_assist: the gun's crosshair column
aa_sp:      dw 0                        ; aa_gun: -> the crosshair
lk_aim:     ds 4                        ; aim_probe: the turns (d, ds) of the
                                        ; centre gun or left linked gun, and
                                        ; the right linked gun
aa_d:       db 0                        ; the frame's aim assist: turn
aa_ds:      db 0                        ;   (1/256 rad), the slope's change
aa_probe:   ds BREC                     ; aim_probe's round (never flies)
aa_n:       db 0                        ; aim_assist: records left,
aa_al:      dw 0                        ;   the monster chosen: along the path
aa_ac:      dw 0                        ;   ($FFFF: none), across it,
aa_dy:      dw 0                        ;   its middle above the muzzle;
aa_rx:      dw 0                        ; aa_try: from the muzzle,
aa_rz:      dw 0
aa_tl:      dw 0                        ;   along, across, up,
aa_tc:      dw 0
aa_ty:      dw 0
aa_lim:     dw 0                        ;   the room each way,
aa_half:    db 0                        ;   half its height
rs_dev:     db 0                        ; round_spread: its steps either way
lk_fired:   db 0                        ; gun_fire: 1 once a linked gun fired
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
b_fire:     db 0                        ;   not 0: a fireball
lf_px:      dw 0                        ; lich_update: the VTOL last frame,
lf_py:      dw 0
lf_pz:      dw 0
lf_vx:      dw 0                        ;   its velocity (units a frame)
lf_vy:      dw 0
lf_vz:      dw 0
lf_x:       dw 0                        ; lich_fire: from,
lf_z:       dw 0
lf_ax:      dw 0                        ;   the aim,
lf_ay:      dw 0
lf_az:      dw 0
lf_dx:      dw 0                        ;   the way there,
lf_dy:      dw 0
lf_dz:      dw 0
lf_dh:      dw 0                        ;   its horizontal distance,
lf_t:       db 0                        ;   and the flight (frames, 4.4)
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
ln_best:    db 0                        ; lk_nearest: the nearest so far,
ln_dist:    dw 0                        ;   its distance,
ln_i:       db 0                        ;   the record looked at
ms_dx:      dw 0                        ; msl_steer: to the target
ms_dz:      dw 0
ms_p:       dw 0                        ; ms_turn: -> the angle,
ms_old:     dw 0                        ;   its value before
ms_chg:     db 0                        ;   1: a high byte changed
at_x:       dw 0                        ; atan2
at_z:       dw 0
