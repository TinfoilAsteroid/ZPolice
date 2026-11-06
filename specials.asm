;==============================================================================
; Z-POLICE - special monsters (8K page PAGE_SPECIAL, game logic: runs at
; $C000 in slot 6)
;
; Special monsters use the zombie records after the zombies' own (NZOMB ..
; NMON-1, zombie.asm), so they share the zombies' drawing (zombie_cell,
; fig_draw), map blips, cell marks (zflags), weapon hits and zdamage.  The
; record's type (+15) says which monster it is.  Each wave's specials come
; from the level file (level_cur, LV_WAVE_DATA: up to LV_SPEC_SLOTS types,
; SPEC_*, and how many of each), placed by spec_wave as the wave starts;
; the level's start is wave 1 (spec_init).  spec_update moves them each
; frame, after zombie_update.
;
; The ghost (ZT_GHOST, special monster id SPEC_GHOST): a stick man under a white
; sheet.  It can't attack the base.  It flies at twice the zombies' speed,
; at any angle, and up and down between the ground and the VTOL's ceiling
; (MAX_Y), over buildings lower than it.
;   * Roaming: it flies in a random direction (a random climb or descent
;     too) until something makes it turn: a building in the way or the map
;     edge (a new random direction at once), or, at its decision check
;     every GHOST_DECIDE (30) frames, a human or the VTOL within GHOST_SEE
;     (3 tiles) that it can see.
;   * Chasing: it flies straight at the nearest one it can see, aiming
;     again every GHOST_TRACK (5) frames.  If it loses sight of its target
;     (behind a taller building) or the target is gone, it roams again in a
;     random direction, back on the 30-frame cycle.
;   * Attacking: within ATTACK_R (0.1 tile) of its target on each axis it
;     stops and takes GHOST_DMG hit point every GHOST_HIT_FRAMES (10)
;     frames: from a human (HUMAN_HP) until it dies, or from the VTOL
;     (vtol_hp, VTOL_HP; at 0 it is destroyed and the game ends).  Its map blip is red
;     meanwhile (zatk_flags, zblip_red), as an attacking zombie's.  If the
;     target moves out of reach it chases it again; once the human is dead
;     it roams again.
;   * It has GHOST_HP (10) hit points; any weapon can shoot it.  Killed, it
;     fades out where it is, white to near black in 4 steps of 3 frames
;     (GM_DYING; zdamage starts it, zombie_draw colours it, g_dying ends
;     it), and can't be hit meanwhile.
; Ghost record fields, besides the zombies' (zombie.asm):
;   +11 frames to its next decision check, +16 mode (GM_*), +17 frames to
;   its next blow, +18 hit points, +21,+22 height of its feet, +23,+24 and
;   +25,+26 velocity x, z (signed 8.8 units a frame), +27,+28 the x and z
;   position fractions, +29 climb (signed units a frame), +30 target
;   (TG_NONE, TG_VTOL, or a human's index).
;==============================================================================

GHOST_HP        equ 10              ; hit points
GHOST_DECIDE    equ 30              ; frames between decisions while roaming
GHOST_TRACK     equ 5               ; and while chasing
GHOST_SEE       equ 3*TILE_UNITS    ; it spots humans / the VTOL this near
GHOST_HIT_FRAMES equ 10             ; frames between blows
GHOST_DMG       equ 1               ; hit points a blow
GHOST_CLIMB     equ 1               ; units a frame up or down
GHOST_AIM_MIN   equ 80              ; (aiming: nearer counts as this far)
GM_ROAM         equ 0               ; modes (+16)
GM_CHASE        equ 1
GM_ATTACK       equ 2
GM_DYING        equ 3               ; killed: fading out (+17 frames left)
GHOST_FADE_FRAMES equ 12            ; the fade: 4 steps of 3 frames
TG_NONE         equ $FF             ; targets (+30)
TG_VTOL         equ $FE
TG_BASE         equ $C0             ; + a base tile's index (base_hp, 0..24)
; The banshee (ZT_BANSHEE, id SPEC_BANSHEE): a ghost that flies twice as
; fast, reaches BANSHEE_R (0.5 tile), does BANSHEE_DMG a blow and also
; attacks the base (the terrace and pad tiles).
; The ghoul (ZT_GHOUL, id SPEC_GHOUL, zombie.asm): a half-height zombie
; walking at five times the zombies' speed.  It is placed here (spec_wave)
; but moved, drawn and hit as a zombie.
; The lich (ZT_LICH, id SPEC_LICH): a city's boss, in the last wave of its
; last level (the level files).  Placed here (lich_init); walks as a zombie
; at 4 times the speed, drawn at LICH_H; shoots fireballs at the VTOL
; (lich_update, weapons.asm).  Each city's is harder: LICH_HP + LICH_HP_STEP
; hit points a city before it, and a shot every LICH_RATE frames,
; LICH_RATE_STEP fewer a city before it, at least LICH_RATE_MIN.  Its
; record: +18 and +23 (LICH_HP_HI) its hit points, 16 bits; +24 (LICH_WAIT)
; frames to its next shot; +25 (LICH_FRAMES) frames between.
; (Which waves have which is the level files' business: gentables.py.)
BANSHEE_HP      equ 8
BANSHEE_DMG     equ 5
BANSHEE_R       equ TILE_UNITS/2
BASE_TILES      equ (2*TERRACE_R+1)*(2*TERRACE_R+1)
LICH_HP         equ 50              ; the first city's
LICH_HP_STEP    equ 25              ; more a city
LICH_RATE       equ 60              ; the first city's frames between shots
LICH_RATE_STEP  equ 10              ; fewer a city
LICH_RATE_MIN   equ 10

;------------------------------------------------------------------------------
; A level's start: every special record inactive, then wave 1's specials
; (the level's start is wave 1, as any other: spec_wave)
;------------------------------------------------------------------------------
spec_init:
        ld ix,zombies+NZOMB*ZREC
        ld b,NSPEC
        ld c,NZOMB                      ; record index
.lp:    ld a,c
        ld hl,zatk_flags                ; not attacking
        add hl,a
        ld (hl),FALSE
        ld (ix+10),0                    ; inactive,
        ld (ix+14),0                    ; no blip,
        ld (ix+19),$FF                  ; no cell marked
        ld de,ZREC
        add ix,de
        inc c
        djnz .lp
        call spec_wave                  ; wave 1's specials (wave_number 1)
        jp zflags                       ; (zombie.asm) mark their cells

; Special monster IX (record sp_idx) of type sp_type: at a random street
; position and height, roaming in a random direction
ghost_init:
        ld a,(sp_type)
        ld (ix+15),a
        call g_params                   ; (its speed for its first direction)
.try:   call zrand                      ; (zombie page)
        ld a,l
        and GRID-1
        ld (ix+1),a                     ; x cell
        ld a,h
        and GRID-1
        ld (ix+3),a                     ; z cell
        call zmap_ptr
        ld a,(hl)
        and CELL_CODE
        jr nz,.try                      ; a building: pick again
        call zrand
        ld a,l
        and 127
        add a,64                        ; 64..191 inside the cell
        ld (ix+0),a
        ld a,h
        and 127
        add a,64
        ld (ix+2),a
        call zrand
        ld a,l
        and 127                         ; height 0..127 (MAX_Y 192)
        ld (ix+21),a
        ld (ix+22),0
        xor a
        ld (ix+27),a                    ; position fractions
        ld (ix+28),a
        ld (ix+5),a
        ld (ix+7),a
        ld (ix+16),GM_ROAM
        ld (ix+18),GHOST_HP
        ld a,(ix+15)
        cp ZT_BANSHEE
        jr nz,.hp
        ld (ix+18),BANSHEE_HP
.hp:
        ld (ix+30),TG_NONE
        ld (ix+10),1                    ; active
        ld a,(sp_idx)                   ; first decisions spread over the
        ld e,a                          ; 30 frames
        ld d,7
        mul d,e
        ld a,e
.mod:   sub GHOST_DECIDE
        jr nc,.mod
        add a,GHOST_DECIDE+1
        ld (ix+11),a
        call g_random
        jp zblip                        ; (map.asm)

;------------------------------------------------------------------------------
; Per frame (after zombie_update): move every special monster, then mark
; the cells again
;------------------------------------------------------------------------------
spec_update:
        ld a,(zwave_new)                ; a new wave: its banshees or ghouls
        or a
        call nz,spec_wave
        ld ix,zombies+NZOMB*ZREC
        ld b,NSPEC
        ld c,NZOMB
.lp:    push bc
        ld a,c
        ld (sp_idx),a
        bit 0,(ix+10)
        jr z,.nx                        ; gone
        ld a,(ix+15)
        cp ZT_GHOST
        jr c,.nx                        ; (a ghoul walks: zombie_update)
        call g_params                   ; a ghost or banshee: its settings
        call ghost_move
.nx:    ld de,ZREC
        add ix,de
        pop bc
        inc c
        djnz .lp
        jp zflags                       ; their cells, as they are now

;------------------------------------------------------------------------------
; Ghost IX, one frame
;------------------------------------------------------------------------------
ghost_move:
        ld a,(ix+16)
        cp GM_DYING
        jp z,g_dying
        cp GM_ATTACK
        jp z,g_attack
        dec (ix+11)                     ; decision check due?
        call z,g_decide
        call g_step                     ; fly
        ld a,(ix+16)
        cp GM_CHASE
        call z,g_reach                  ; close enough to attack?
        ld a,(ix+16)
        cp GM_ATTACK
        ret z                           ; (its blip is red)
        ld a,(zanim)                    ; its map blip, every 8 frames
        ld hl,sp_idx
        add a,(hl)
        and 7
        ret nz
        jp zblip

; A new wave began (zwave_new, zombie.asm; spec_init for wave 1): its
; specials from the level file (level_cur, LV_WAVE_DATA: wave_number's
; record), each of its LV_SPEC_SLOTS types (SPEC_NONE: none) as many as it
; says, into free special records.  Waves past LV_MAX_WAVES have none.
spec_wave:
        xor a
        ld (zwave_new),a
        ld a,(wave_number)
        dec a
        cp LV_MAX_WAVES
        ret nc
        ld e,a
        ld d,LV_WAVE_REC
        mul d,e
        ld hl,level_cur+LV_WAVE_DATA
        add hl,de
        ld (sw_ptr),hl                  ; -> this wave's types
        ld b,LV_SPEC_SLOTS
.sl:    push bc
        ld hl,(sw_ptr)
        ld a,(hl)                       ; a type
        cp SPEC_IDS
        jr nc,.ns                       ; (SPEC_NONE, or not a type)
        ld de,spec_types
        add de,a
        ld a,(de)
        ld (sp_type),a                  ; its record type (ZT_*)
        ld a,LV_SPECIAL-LV_SPECIAL_ID
        add hl,a
        ld a,(hl)                       ; how many
        ld (sp_left),a
        call spec_place
.ns:    ld hl,(sw_ptr)
        inc hl
        ld (sw_ptr),hl
        pop bc
        djnz .sl
        ret

; Special type (SPEC_*, the level files) -> record type (ZT_*)
spec_types: db ZT_GHOST, ZT_BANSHEE, ZT_GHOUL, ZT_LICH
        ASSERT $ - spec_types == SPEC_IDS
        ASSERT SPEC_GHOST == 0 && SPEC_BANSHEE == 1 && SPEC_GHOUL == 2
        ASSERT SPEC_LICH == 3

; sp_left monsters of record type sp_type into free special records (as
; many as there's room for)
spec_place:
        ld ix,zombies+NZOMB*ZREC
        ld b,NSPEC
        ld c,NZOMB
.lp:    ld a,(sp_left)
        or a
        ret z                           ; all placed
        bit 0,(ix+10)
        jr nz,.nx                       ; in use
        push bc
        ld a,c
        ld (sp_idx),a
        ld hl,zatk_flags
        add hl,a
        ld (hl),FALSE
        ld (ix+14),0                    ; no blip yet
        ld hl,sp_left
        dec (hl)
        ld a,(sp_type)
        cp ZT_LICH
        jr z,.li
        cp ZT_GHOUL
        jr z,.gh
        call ghost_init
        pop bc
        jr .nx
.li:    call lich_init
        pop bc
        jr .nx
.gh:    call ghoul_init
        pop bc
.nx:    ld de,ZREC
        add ix,de
        inc c
        djnz .lp
        ret                             ; (no room for the rest)

; A ghoul in record IX (sp_idx): placed as a zombie (zplace, zombie.asm),
; then made a ghoul; its first decision check spread by its index
ghoul_init:
        call zplace
        ld (ix+15),ZT_GHOUL
        ld (ix+18),GHOUL_HP
        ld a,(sp_idx)
        and 7
        inc a
        ld (ix+11),a
        jp zblip                        ; (map.asm)

; A lich in record IX (sp_idx): placed as a zombie, then made a lich, the
; harder the later the city: its hit points and frames between shots
lich_init:
        call zplace
        ld (ix+15),ZT_LICH
        ld a,(level)                    ; B = the cities before this one
        dec a
        ld b,-1
.city:  inc b
        sub CITY_LEVELS
        jr nc,.city
        ld d,b                          ; its hit points
        ld e,LICH_HP_STEP
        mul d,e
        ld hl,LICH_HP
        add hl,de
        ld (ix+18),l
        ld (ix+LICH_HP_HI),h
        ld d,b                          ; its rate of fire
        ld e,LICH_RATE_STEP
        mul d,e
        ld a,LICH_RATE-LICH_RATE_MIN
        sub e
        jr nc,.r
        xor a
.r:     add a,LICH_RATE_MIN
        ld (ix+LICH_FRAMES),a
        ld (ix+LICH_WAIT),a
        ld a,(sp_idx)
        and 7
        inc a
        ld (ix+11),a
        jp zblip                        ; (map.asm)

; Special monster IX's settings, from its type (+15): g_speed (8.8 units a
; frame: a ghost twice the zombies' zspeed, a banshee four times), gp_range
; (its reach on each axis), gp_dmg (a blow), gp_base (1: attacks the base)
g_params:
        ld a,(zspeed)                   ; zspeed (4.4) * 32 = twice it, 8.8
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(ix+15)
        cp ZT_BANSHEE
        jr z,.b
        ld (g_speed),hl                 ; a ghost
        ld hl,ATTACK_R
        ld (gp_range),hl
        ld a,GHOST_DMG
        ld (gp_dmg),a
        xor a
        ld (gp_base),a
        ret
.b:     add hl,hl                       ; a banshee: twice as fast
        ld (g_speed),hl
        ld hl,BANSHEE_R
        ld (gp_range),hl
        ld a,BANSHEE_DMG
        ld (gp_dmg),a
        ld a,1
        ld (gp_base),a
        ret

; Killed (zdamage): it hangs where it is, fading out (zombie_draw colours
; it by the frames left), then is gone
g_dying:
        dec (ix+17)
        ret nz
        ld (ix+10),0                    ; gone (zflags unmarks its cell)
        ret

; Decision check: look for a human or the VTOL to chase
g_decide:
        call g_find                     ; carry: a target, at gt_x/z/y
        jr nc,.none
        ld (ix+16),GM_CHASE
        ld (ix+11),GHOST_TRACK
        jp g_aim
.none:  ld (ix+11),GHOST_DECIDE
        ld a,(ix+16)
        or a
        ret z                           ; roaming: fly on
        ; lost it (gone, or out of sight): roam again, a new direction
g_lose: ld (ix+16),GM_ROAM
        ld (ix+11),GHOST_DECIDE
        ld (ix+30),TG_NONE
        ; fall through

; A random direction: velocity g_speed at a random angle, and a random climb
; (-1, 0, +1, 0 units a frame)
g_random:
        call zrand
        push hl
        ld a,l
        push af
        call get_sin                    ; (resident; pages the sine table)
        ex de,hl
        ld hl,(g_speed)
        call fmul                       ; vx = speed * sin (8.8)
        ld (ix+23),l
        ld (ix+24),h
        pop af
        add a,64
        call get_sin
        ex de,hl
        ld hl,(g_speed)
        call fmul                       ; vz = speed * cos
        ld (ix+25),l
        ld (ix+26),h
        pop hl
        ld a,h
        and 3
        ld hl,g_climbs
        add hl,a
        ld a,(hl)
        ld (ix+29),a
        ret

; Fly one frame: x, z by the velocity, unless that runs into a building
; taller than its feet or the map edge (then a new random direction, and a
; chase is given up); then the climb, kept between the roof or ground under
; it and MAX_Y
g_step:
        ld l,(ix+27)                    ; keep the old position
        ld h,(ix+0)
        ld (gs_x),hl
        ld a,(ix+1)
        ld (gs_x+2),a
        ld l,(ix+28)
        ld h,(ix+2)
        ld (gs_z),hl
        ld a,(ix+3)
        ld (gs_z+2),a
        ld e,(ix+23)                    ; x: (fraction, lo, hi) += vx
        ld d,(ix+24)
        ld a,d
        rla
        sbc a,a
        ld c,a                          ; sign
        ld a,(ix+27)
        add a,e
        ld (ix+27),a
        ld a,(ix+0)
        adc a,d
        ld (ix+0),a
        ld a,(ix+1)
        adc a,c
        ld (ix+1),a
        ld e,(ix+25)                    ; z likewise
        ld d,(ix+26)
        ld a,d
        rla
        sbc a,a
        ld c,a
        ld a,(ix+28)
        add a,e
        ld (ix+28),a
        ld a,(ix+2)
        adc a,d
        ld (ix+2),a
        ld a,(ix+3)
        adc a,c
        ld (ix+3),a
        call g_ground                   ; HL = roof under the new position,
        jr c,.blk                       ; carry: off the map
        ld e,(ix+21)
        ld d,(ix+22)
        ex de,hl
        or a
        sbc hl,de                       ; feet - roof
        jr nc,.ok                       ; at or above it
.blk:   ld hl,(gs_x)                    ; blocked: back, and turn
        ld (ix+27),l
        ld (ix+0),h
        ld a,(gs_x+2)
        ld (ix+1),a
        ld hl,(gs_z)
        ld (ix+28),l
        ld (ix+2),h
        ld a,(gs_z+2)
        ld (ix+3),a
        ld a,(ix+16)
        or a
        jp z,g_random                   ; roaming: a new direction
        jp g_lose                       ; chasing: give it up
.ok:    ld a,(ix+29)                    ; climb
        ld l,(ix+21)
        ld h,(ix+22)
        ld e,a
        rla
        sbc a,a
        ld d,a
        add hl,de
        bit 7,h
        jr z,.pos
        ld hl,0
.pos:   ld de,MAX_Y                     ; no higher than the VTOL can go
        call g_min
        ex de,hl
        push de
        call g_ground                   ; nor below the roof under it
        pop de
        call g_max_de
        ld (ix+21),l
        ld (ix+22),h
        ret

; HL = the roof height (0 on a road) of ghost IX's cell; carry set if the
; cell is off the map (then HL = $FFFF)
g_ground:
        ld a,(ix+1)
        cp GRID
        jr nc,.off
        ld a,(ix+3)
        cp GRID
        jr nc,.off
        call zmap_ptr                   ; (zombie page)
        ld a,(hl)
        call bld_height                 ; (masks the cell code)
        or a
        ret
.off:   ld hl,$FFFF
        scf
        ret

; HL = min(HL, DE), unsigned
g_min:  or a
        sbc hl,de
        add hl,de
        ret c
        ex de,hl
        ret
; HL = max(HL, DE), unsigned
g_max_de:
        or a
        sbc hl,de
        add hl,de
        ret nc
        ex de,hl
        ret

; Chasing: aim at the target's place again (g_find left it in gt_*) is done
; at the decision checks; here, check whether it is within reach and if so
; start attacking.
g_reach:
        call g_target                   ; gt_x/z/y = where it is now; carry:
        jp c,g_lose                     ; gone
        call g_near                     ; within ATTACK_R on each axis?
        ret nc
        ld (ix+16),GM_ATTACK
        ld (ix+17),GHOST_HIT_FRAMES
        call g_flag                     ; attacking: map blip red
        ld (hl),TRUE
        jp zblip_red                    ; (map.asm)

; HL -> ghost IX's zatk_flags entry
g_flag: ld a,(sp_idx)
        ld hl,zatk_flags
        add hl,a
        ret

; Attacking: one blow every GHOST_HIT_FRAMES frames while the target is in
; reach
g_attack:
        call g_target
        jr c,.done                      ; gone (dead, aboard, rescued)
        call g_near
        jr c,.blow
        ld (ix+16),GM_CHASE             ; it moved away: after it
        ld (ix+11),1                    ; (aim next frame)
        call g_flag
        ld (hl),FALSE
        jp zblip
.blow:  dec (ix+17)
        ret nz
        ld (ix+17),GHOST_HIT_FRAMES
        ld a,(ix+30)
        cp TG_VTOL
        jr z,.vtol
        cp TG_BASE
        jr nc,.base
        push ix                         ; a human: gp_dmg hit points
        call g_human                    ; IX -> it
        ld a,(gp_dmg)
        ld c,a
        ld a,(ix+10)
        sub c
        jr c,.dead
        ld (ix+10),a
        jr z,.dead
        pop ix
        ret
.dead:  ld (ix+10),0                    ; killed: dot off, dead
        ld c,0
        call hum_dot                    ; (map.asm)
        ld (ix+6),HS_DEAD
        call hum_flags                  ; (human.asm) its mark off
        pop ix
.done:  call g_flag                     ; back to roaming
        ld (hl),FALSE
        call zblip
        jp g_lose
.vtol:  ld a,(gp_dmg)                   ; the VTOL (at 0 it is destroyed;
        jp vtol_damage                  ; zpolice.asm)
.base:  sub TG_BASE                     ; a base tile: E, D = its cell
        call g_basecell
        ld a,(gp_dmg)
        ld c,a
        jp base_damage                  ; (zombie.asm; the pad: game over)

; IX -> the record of ghost IX's target human (+30).  (Push IX first.)
g_human:
        ld a,(ix+30)
        ld e,a
        ld d,HREC
        mul d,e
        ld ix,humans
        add ix,de
        ret

; gt_x, gt_z, gt_y = where ghost IX's target is now; carry set if it has
; none or it is gone (a human no longer waiting)
g_target:
        ld a,(ix+30)
        cp TG_NONE
        scf
        ret z
        cp TG_VTOL
        jr z,.vtol
        cp TG_BASE
        jr c,.hum
        sub TG_BASE                     ; a base tile: still standing?
        ld hl,base_hp
        add hl,a
        ld a,(hl)
        or a
        scf
        ret z                           ; destroyed
        ld a,(ix+30)
        sub TG_BASE
        call g_basecell
        call g_tilepos                  ; its centre, its top
        ld hl,(gf_x)
        ld (gt_x),hl
        ld hl,(gf_z)
        ld (gt_z),hl
        ld hl,(gf_y)
        ld (gt_y),hl
        or a
        ret
.vtol:
        ld hl,(cam_x+1)
        ld (gt_x),hl
        ld hl,(cam_z+1)
        ld (gt_z),hl
        ld hl,(cam_y)
        ld (gt_y),hl
        or a
        ret
.hum:   push ix
        call g_human
        ld a,(ix+6)
        cp HS_WAIT
        jr nz,.gone
        ld l,(ix+0)
        ld h,(ix+1)
        ld (gt_x),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (gt_z),hl
        ld l,(ix+4)
        ld h,(ix+5)
        ld (gt_y),hl
        pop ix
        or a
        ret
.gone:  pop ix
        scf
        ret

; Carry set if ghost IX is within ATTACK_R of gt_x/z/y on each axis
g_near: ld l,(ix+0)
        ld h,(ix+1)
        ld de,(gt_x)
        call g_close
        ret nc
        ld l,(ix+2)
        ld h,(ix+3)
        ld de,(gt_z)
        call g_close
        ret nc
        ld l,(ix+21)
        ld h,(ix+22)
        ld de,(gt_y)
        ; fall through
; Carry set if |HL - DE| <= gp_range (the monster's reach)
g_close:
        or a
        sbc hl,de
        call abs_hl
        ld de,(gp_range)
        inc de
        or a
        sbc hl,de
        ret

; A = a base tile's index (row * 5 + column of the 5x5 square round the
; pad) -> E, D = its cell
g_basecell:
        ld d,PAD_Z-TERRACE_R
.r:     cp 2*TERRACE_R+1
        jr c,.c
        sub 2*TERRACE_R+1
        inc d
        jr .r
.c:     add a,PAD_X-TERRACE_R
        ld e,a
        ret

; gf_x/z/y = the centre of base tile (E, D) and its top (its height now)
g_tilepos:
        ld h,e
        ld l,128
        ld (gf_x),hl
        ld h,d
        ld (gf_z),hl
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        call bld_height
        ld (gf_y),hl
        ret

;------------------------------------------------------------------------------
; Look for the nearest human (waiting) or the VTOL within GHOST_SEE of ghost
; IX on each axis that it can see (g_sight).  Carry set if found: +30 = the
; target, gt_x/z/y = where it is.
;------------------------------------------------------------------------------
g_find:
        ld hl,$FFFF
        ld (gf_best),hl                 ; nearest so far
        ld a,TG_VTOL                    ; the VTOL
        ld (gf_who),a
        ld hl,(cam_x+1)
        ld (gf_x),hl
        ld hl,(cam_z+1)
        ld (gf_z),hl
        ld hl,(cam_y)
        ld (gf_y),hl
        call g_cand
        push ix                         ; the humans still waiting
        ld iy,humans
        ld b,HUMAN_MAX
        ld c,0
.hl:    push bc
        ld a,(iy+6)
        cp HS_WAIT
        jr nz,.hn
        ld a,c
        ld (gf_who),a
        ld l,(iy+0)
        ld h,(iy+1)
        ld (gf_x),hl
        ld l,(iy+2)
        ld h,(iy+3)
        ld (gf_z),hl
        ld l,(iy+4)
        ld h,(iy+5)
        ld (gf_y),hl
        pop bc
        push bc
        push iy
        call g_cand
        pop iy
.hn:    ld de,HREC
        add iy,de
        pop bc
        inc c
        djnz .hl
        pop ix
        ld a,(gp_base)                  ; a banshee: the base tiles too
        or a
        call nz,g_find_base
        ld hl,(gf_best)
        ld a,h
        and l
        inc a
        scf
        ccf
        ret z                           ; nobody (carry clear)
        ld a,(gf_tgt)
        ld (ix+30),a
        scf
        ret

; The base tiles still standing (base_hp) as candidates for ghost IX
g_find_base:
        ld c,0                          ; tile index
.lp:    push bc
        ld a,c
        ld hl,base_hp
        add hl,a
        ld a,(hl)
        or a
        jr z,.nx                        ; destroyed (road now)
        ld a,c
        add a,TG_BASE
        ld (gf_who),a
        ld a,c
        call g_basecell
        call g_tilepos                  ; gf_x/z/y = the candidate
        call g_cand
.nx:    pop bc
        inc c
        ld a,c
        cp BASE_TILES
        jr nz,.lp
        ret

; Candidate gf_who at gf_x/z/y for ghost IX: if within GHOST_SEE on each
; axis, nearer than the best so far and in sight, it becomes the best
; (gf_best = its distance, gf_tgt, gt_x/z/y).  Preserves IX.
g_cand:
        ld l,(ix+0)                     ; dx = target - ghost
        ld h,(ix+1)
        ex de,hl
        ld hl,(gf_x)
        or a
        sbc hl,de
        ld (gf_dx),hl
        call abs_hl
        ld de,GHOST_SEE+1
        or a
        sbc hl,de
        ret nc                          ; too far
        ld l,(ix+2)
        ld h,(ix+3)
        ex de,hl
        ld hl,(gf_z)
        or a
        sbc hl,de
        ld (gf_dz),hl
        call abs_hl
        ld de,GHOST_SEE+1
        or a
        sbc hl,de
        ret nc
        ld hl,(gf_dx)                   ; distance: max + min/2 of |dx|, |dz|
        call abs_hl
        ex de,hl
        ld hl,(gf_dz)
        call abs_hl
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl                        ; HL = max, DE = min
.mx:    srl d
        rr e
        add hl,de
        ld (gf_d),hl
        ld de,(gf_best)
        or a
        sbc hl,de
        ret nc                          ; not nearer
        call g_sight
        ret c                           ; hidden behind a building
        ld hl,(gf_d)
        ld (gf_best),hl
        ld a,(gf_who)
        ld (gf_tgt),a
        ld hl,(gf_x)
        ld (gt_x),hl
        ld hl,(gf_z)
        ld (gt_z),hl
        ld hl,(gf_y)
        ld (gt_y),hl
        ret

; Can ghost IX see gf_x/z/y?  Carry set if a building is in the way: the
; line between them is sampled at 7 points (1/8 .. 7/8 of the way), each
; checked against the roof of the cell it is over (not the target's own
; cell).  Preserves IX.
g_sight:
        ld hl,(gf_dx)                   ; steps: d / 8
        call g_div8
        ld (gs_dx),hl
        ld hl,(gf_dz)
        call g_div8
        ld (gs_dz),hl
        ld l,(ix+21)                    ; dy = target - ghost
        ld h,(ix+22)
        ex de,hl
        ld hl,(gf_y)
        or a
        sbc hl,de
        call g_div8
        ld (gs_dy),hl
        ld l,(ix+0)                     ; from the ghost
        ld h,(ix+1)
        ld (gs_px),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (gs_pz),hl
        ld l,(ix+21)
        ld h,(ix+22)
        ld (gs_py),hl
        ld b,7
.lp:    push bc
        ld hl,(gs_px)
        ld de,(gs_dx)
        add hl,de
        ld (gs_px),hl
        ld hl,(gs_pz)
        ld de,(gs_dz)
        add hl,de
        ld (gs_pz),hl
        ld hl,(gs_py)
        ld de,(gs_dy)
        add hl,de
        ld (gs_py),hl
        ld a,(gs_px+1)                  ; over the target's own cell: not in
        ld hl,gf_x+1                    ; the way (a base tile's top would
        cp (hl)                         ; hide itself)
        jr nz,.cell
        ld a,(gs_pz+1)
        ld hl,gf_z+1
        cp (hl)
        jr nz,.cell
        pop bc
        jr .nx
.cell:  ld a,(gs_pz+1)                  ; the cell under this point
        ld l,a
        ld h,0
        ROWOFS
        ld a,(gs_px+1)
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        call bld_height
        ld de,(gs_py)
        or a
        sbc hl,de                       ; roof - line height
        pop bc
        jr z,.nx
        jr nc,.hid                      ; the roof is above the line
.nx:    djnz .lp
        or a                            ; in sight
        ret
.hid:   scf
        ret

; HL = HL / 8, signed
g_div8: sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ret

; Aim ghost IX at gt_x/z/y: velocity g_speed straight at it, climbing or
; descending towards its height
g_aim:
        ld l,(ix+0)                     ; dx, dz = target - ghost
        ld h,(ix+1)
        ex de,hl
        ld hl,(gt_x)
        or a
        sbc hl,de
        ld (gf_dx),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ex de,hl
        ld hl,(gt_z)
        or a
        sbc hl,de
        ld (gf_dz),hl
        call abs_hl                     ; distance ~ max + 3/8 min
        ex de,hl
        ld hl,(gf_dx)
        call abs_hl
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl
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
        rr l                            ; 3/8 min
        pop de
        add hl,de
        ld de,GHOST_AIM_MIN             ; (so the factor stays <= 1.0)
        call g_max_de
        ex de,hl                        ; DE = distance
        ld hl,(g_speed)                 ; factor = speed * 32 / distance
        add hl,hl                       ; (at most 1.0, even for a banshee)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        call udiv16                     ; (human.asm) HL = HL / DE
        ld (ga_t),hl
        ld hl,(gf_dx)                   ; v = d * factor * 8 (8.8)
        ld de,(ga_t)
        call fmul
        add hl,hl
        add hl,hl
        add hl,hl
        ld (ix+23),l
        ld (ix+24),h
        ld hl,(gf_dz)
        ld de,(ga_t)
        call fmul
        add hl,hl
        add hl,hl
        add hl,hl
        ld (ix+25),l
        ld (ix+26),h
        ld l,(ix+21)                    ; climb towards its height
        ld h,(ix+22)
        ex de,hl
        ld hl,(gt_y)
        or a
        sbc hl,de
        ld a,0
        jr z,.cy
        ld a,GHOST_CLIMB
        jp p,.cy
        ld a,-GHOST_CLIMB
.cy:    ld (ix+29),a
        ret

;==============================================================================
; Special monster data
;==============================================================================
g_climbs:   db -GHOST_CLIMB, 0, GHOST_CLIMB, 0  ; random climbs
g_speed:    dw 0                        ; this monster's speed, 8.8 units
gp_range:   dw 0                        ; its reach (g_params)
gp_dmg:     db 0                        ; its blow
gp_base:    db 0                        ; 1: it attacks the base
sp_type:    db 0                        ; ghost_init: the type to place
sp_idx:     db 0                        ; the record being moved
sp_left:    db 0                        ; spec_place: specials still to place
sw_ptr:     dw 0                        ; spec_wave: -> the wave's next type
gs_x:       ds 3                        ; g_step: the old position
gs_z:       ds 3
gs_dx:      dw 0                        ; g_sight: steps and point
gs_dz:      dw 0
gs_dy:      dw 0
gs_px:      dw 0
gs_pz:      dw 0
gs_py:      dw 0
gt_x:       dw 0                        ; the target's position
gt_z:       dw 0
gt_y:       dw 0
gf_best:    dw 0                        ; g_find: nearest distance so far,
gf_tgt:     db 0                        ;   and who
gf_who:     db 0                        ; the candidate
gf_x:       dw 0
gf_z:       dw 0
gf_y:       dw 0
gf_dx:      dw 0
gf_dz:      dw 0
gf_d:       dw 0
ga_t:       dw 0                        ; g_aim: the speed factor
