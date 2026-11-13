;==============================================================================
; Z-POLICE - the final boss: the devil (in the special monsters' page,
; PAGE_SPECIAL, at $C000 in slot 6: specials.asm includes it)
;
; Quatermass's horned Martian, ten building levels tall (DEVIL_H, 46 m) and a
; whole square wide, in the last wave of the last level (the level files:
; SPEC_DEVIL, alone).  It rises at the entrance to hell (HELL_X, HELL_Z: a
; circle of road the level's map changes make) or, if that isn't road, on a
; street at random (zplace).  A special monster record (zombie.asm), type
; ZT_DEVIL; drawn by devil_draw (city2.asm) from its own graphics, which go
; over the other monsters' pages when its wave starts (wave_prepare,
; devil_load: only the zombies and humans are drawn with it).
;   * It walks the streets to the landing pad, half a tile a step
;     (DV_STEP_FR frames each: moving for DV_MOVE_FR, then planted), every
;     footfall shaking the view.  At a cell's middle it takes the way that
;     brings it nearest the pad (not back the way it came unless it must);
;     a terrace or pad tile it steps onto is crushed (base_damage: the pad,
;     game over).
;   * Its eyes charge, black to blue, wherever the VTOL is, for
;     DV_CHARGE_T interrupts (10 s; a rising whine for the last DV_HUM_T,
;     3 s: SFX_CHARGE), then it fires lightning (a crackling zap and
;     thunder: SFX_BOLT): straight at the
;     VTOL, instantly, through anything in the way.  A building the bolt
;     passes below the roof of comes down (dv_topple: DV_PARTS particles,
;     falling 1 m every 2 frames to RUBBLE_H; the humans on it killed; the
;     map in memory only).  The VTOL takes BOLT_DMG, spins 15-90 degrees
;     either way (spin_rate, spin_t: player.asm), is pitched full up or
;     down, and is braked to a stop as the air brake does (bolt_brake).
;     Then DV_REST_T interrupts (2 s) before it charges again.
;   * DEVIL_HP hit points (16 bits, as a lich's: +18 and LICH_HP_HI); its
;     hit box DEVIL_HIT_R either side, DEVIL_H tall (weapons.asm).  Killed,
;     it sinks into the ground over DV_DIE_FR frames in fire, then it's gone.
; Its record, besides the zombies' fields: +4 heading (0 +z, 1 +x, 2 -z,
; 3 -x), +5 its legs' frame, +7 1: stuck (nowhere to go), +11 the frame in
; its step, +16 mode (0 walking, GM_DYING), +17 frames left sinking,
; +21,+22 its feet (below the ground as it sinks), DV_EYES (0 resting,
; 1 charging) and DV_T0 (isr_ticks when that began).
;==============================================================================

DEVIL_HP        equ 1000
DV_STEP_FR      equ 24              ; frames a step
DV_MOVE_FR      equ 16              ; moving for this many of them
DV_STEP_U       equ TILE_UNITS/2/DV_MOVE_FR     ; units a frame (half a tile a step)
        ASSERT DV_STEP_U * DV_MOVE_FR == TILE_UNITS/2
DV_RANGE        equ 8*TILE_UNITS    ; it fires at the VTOL this near (160 m)
DV_CHARGE_T     equ 500             ; interrupts charging (10 s),
DV_HUM_T        equ 150             ;   the last of them whining (3 s: SFX_CHARGE)
DV_REST_T       equ 100             ; and resting after a shot (2 s)
BOLT_DMG        equ 10
BOLT_FRAMES     equ 4               ; frames the bolt is drawn
DV_EYE_H        equ DEVIL_H*108/DEVIL_SRC_H     ; its eyes' height (row 20)
DV_DIE_FR       equ 40              ; frames sinking, killed
DEVIL_HIT_R     equ 100             ; its hit box: this far either side (8 m),
DEVIL_AIM_H     equ 240             ;   DEVIL_H tall; the guns' aim: its chest
        ASSERT DEVIL_HIT_R < 255 && DEVIL_AIM_H < 256
DV_SINK         equ DEVIL_H/DV_DIE_FR+1         ; units a frame, dying
DV_PARTS        equ 50              ; a building brought down: its particles
DV_TALL         equ 5               ; it walks through buildings under level 5
DV_TREAD_PARTS  equ 6               ; a zombie trodden on: its burst
DV_KILL_PARTS   equ 2               ; each monster dying with it: its burst
DV_DARK_HP      equ 100             ; its hit points a darker step
DV_DIE_PARTS    equ 4               ; dying: fire every other frame
SPIN_FR         equ 8               ; frames the VTOL's spin takes
SPIN_MIN        equ 5               ; 7 degrees (256 a turn)
SPIN_RANGE      equ 27              ; .. up to 44 (31)
PITCH_KICK      equ PMAX/2          ; the nose up or down this much (17 degrees)
DV_EYES         equ 24              ; record: its eyes (0 resting, 1 charging),
DV_T0           equ 25              ;   isr_ticks when that began (2)
        ASSERT DV_T0+1 < 31 && LICH_HP_HI != DV_EYES && LICH_HP_HI != DV_T0

;------------------------------------------------------------------------------
; A level's start (spec_init): no building coming down, no bolt, no spin,
; its eyes black
;------------------------------------------------------------------------------
dv_reset:
        ld hl,cl_ptr
        ld b,2*COLLAPSE_N
.cl:    ld (hl),0
        inc hl
        djnz .cl
        ld hl,htab+2*COLLAPSE_CODE
        ld b,2*COLLAPSE_N
.ht:    ld (hl),0
        inc hl
        djnz .ht
        xor a
        ld (bolt_t),a
        ld (spin_t),a
        ld (bolt_brake),a
        ld (dv_hum),a
        ld (dv_dark),a                  ; (the level's palette as it was)
        ld (dv_dark_req),a
        jp dv_eye_black

;------------------------------------------------------------------------------
; The devil in record IX (sp_idx): at the entrance to hell if it's road,
; else on a street at random; facing the pad's side (-z), its graphics
; wanted after this frame (wave_prepare loads them)
;------------------------------------------------------------------------------
devil_init:
        ld (ix+1),HELL_X
        ld (ix+3),HELL_Z
        call zmap_ptr                   ; (zombie page)
        ld a,(hl)
        and CELL_CODE
        call nz,zplace                  ; not road: a street at random
        ld (ix+15),ZT_DEVIL
        ld (ix+0),128                   ; in the middle of its cell
        ld (ix+2),128
        ld (ix+4),2                     ; facing -z (the pad's way from hell)
        xor a
        ld (ix+5),a
        ld (ix+7),a
        ld (ix+11),a
        ld (ix+16),a
        ld (ix+21),a
        ld (ix+22),a
        ld (ix+DV_EYES),a
        ld (ix+DV_T0),a
        ld (ix+DV_T0+1),a
        ld (ix+18),low DEVIL_HP
        ld (ix+LICH_HP_HI),high DEVIL_HP
        ld (ix+10),1                    ; active
        ld hl,wave_prep                 ; its graphics, after this frame
        set WP_DEVIL,(hl)
        call dv_eye_black
        jp zblip                        ; (map.asm)

;------------------------------------------------------------------------------
; Every frame (spec_update), devil or not: the bolt's frames, buildings
; coming down
;------------------------------------------------------------------------------
dv_frame:
        ld hl,bolt_t
        ld a,(hl)
        or a
        jr z,.nb
        dec (hl)
.nb:    ld hl,cl_tog                    ; every other frame
        ld a,(hl)
        xor 1
        ld (hl),a
        ret z
        push iy
        ld iy,cl_ptr                    ; each slot: its cell (cl_ptr), its
        ld ix,htab+2*COLLAPSE_CODE      ; height (cl_h and its htab entry)
        ld b,COLLAPSE_N
.sl:    ld e,(iy+0)
        ld d,(iy+1)                     ; DE -> its cell
        ld a,d
        or e
        jr z,.nx                        ; free
        ld l,(iy+2*COLLAPSE_N)
        ld h,(iy+2*COLLAPSE_N+1)        ; (cl_h follows cl_ptr)
        push de
        ld de,-HEIGHT_UNITS/10          ; 1 m lower
        add hl,de
        pop de
        push hl
        push de
        ld de,-RUBBLE_H-1
        add hl,de                       ; no carry: at or under RUBBLE_H
        pop de
        pop hl
        jr nc,.down
        ld (iy+2*COLLAPSE_N),l
        ld (iy+2*COLLAPSE_N+1),h
        ld (ix+0),l
        ld (ix+1),h
        jr .nx
.down:  ld a,(de)                       ; down: rubble, the slot free
        and CELL_FLAGS
        or RUBBLE_CODE
        ld (de),a
        xor a
        ld (iy+0),a
        ld (iy+1),a
        ld (ix+0),a
        ld (ix+1),a
.nx:    inc iy
        inc iy
        inc ix
        inc ix
        djnz .sl
        pop iy
        ret
        ASSERT cl_h == cl_ptr + 2*COLLAPSE_N

;------------------------------------------------------------------------------
; Devil IX, one frame (spec_update)
;------------------------------------------------------------------------------
devil_move:
        call dv_darken
        ld a,(ix+16)
        cp GM_DYING
        jp z,dv_dying
        call dv_walk
        call dv_charge
        ld a,(zanim)                    ; its map blip, every 8 frames
        ld hl,sp_idx
        add a,(hl)
        and 7
        ret nz
        jp zblip

; Its hit points down by DV_DARK_HP: the normal palette a step darker
; (each r, g, b down 1; dv_dark, at most 7): asked of the main loop
; (dv_dark_req: vis_dark, level_load.asm, where the palette is)
dv_darken:
        ld l,(ix+18)
        ld h,(ix+LICH_HP_HI)
        ex de,hl
        ld hl,DEVIL_HP
        or a
        sbc hl,de                       ; taken off it
        ld a,-1
        ld de,DV_DARK_HP
.k:     inc a
        or a
        sbc hl,de
        jr nc,.k
        cp 8
        jr c,.c
        ld a,7
.c:     ld hl,dv_dark
        cp (hl)
        ret z
        ld (hl),a
        ld a,1
        ld (dv_dark_req),a
        ret

; A step: at its start in a cell's middle, the way to go (dv_turn: what's
; in the way knocked down); then DV_STEP_U a frame along its heading for
; DV_MOVE_FR frames, the footfall (a shake, a thud, the other leg), and
; planted for the rest of the step
dv_walk:
        ld a,(ix+11)
        or a
        jr nz,.mid
        ld a,(ix+0)                     ; a cell's middle?
        cp 128
        jr nz,.mid
        ld a,(ix+2)
        cp 128
        call z,dv_turn
.mid:   inc (ix+11)
        ld a,(ix+11)
        cp DV_STEP_FR
        jr c,.in
        ld (ix+11),0                    ; (the next step next frame)
        ret
.in:    cp DV_MOVE_FR+1
        ret nc                          ; planted
        bit 0,(ix+7)
        ret nz                          ; stuck: nowhere to go
        push af
        ld a,(ix+4)                     ; DV_STEP_U along its heading
        add a,a
        ld hl,zdir_step
        add hl,a
        ld a,(hl)                       ; dx: -1, 0, 1
        inc hl
        ld c,(hl)                       ; dz
        call .axis
        ld (ix+0),l
        ld (ix+1),h
        ld a,c
        ld l,(ix+2)
        ld h,(ix+3)
        call .ax
        ld (ix+2),l
        ld (ix+3),h
        pop af
        cp DV_MOVE_FR
        ret nz
        ; the footfall
        ld a,(ix+5)                     ; the other leg next
        xor 1
        ld (ix+5),a
        ld a,(shake_t)                  ; the ground shakes
        or a
        jr nz,.sh
        ld a,SHAKE_LEN
        ld (shake_t),a
.sh:    ld a,SFX_CRASH                  ; (a thud)
        ld (sfx2_req),a
        jp dv_tread                     ; what's under its feet
.axis:  ld l,(ix+0)
        ld h,(ix+1)
.ax:    or a                            ; HL += A * DV_STEP_U (A -1, 0, 1)
        ret z
        ld de,DV_STEP_U
        jp p,.p
        ld de,-DV_STEP_U
.p:     add hl,de
        ret

; In a cell's middle: after the VTOL.  The heading to the neighbouring cell
; it can walk (dv_walkable) nearest the VTOL's cell (across plus along),
; back the way it came only if that's DT_BACK cells better; ties at random.
; What's there is knocked down (dv_flatten).  None: stuck (+7).
DT_BACK         equ 1               ; (cells)
DT_FAR          equ 120             ; (cells: farther counts as this far)
dv_turn:
        ld a,$FF
        ld (dt_best),a
        ld a,(ix+4)                     ; back the way it came
        xor 2
        ld (dt_back),a
        ld a,(cam_x+2)                  ; the VTOL's cell
        ld (dt_vx),a
        ld a,(cam_z+2)
        ld (dt_vz),a
        call .look
        ld a,(dt_best)
        inc a
        jr nz,.got
        ld (ix+7),1                     ; stuck
        ret
.got:   ld a,(dt_dir)
        ld (ix+4),a
        ld (ix+7),0
        ld de,(dt_cell)                 ; (E, D)
        ld hl,(dt_ptr)
        jp dv_flatten
.look:  ld b,0                          ; each heading
.h:     ld a,b
        add a,a
        ld hl,zdir_step
        add hl,a
        ld a,(ix+1)
        add a,(hl)
        cp GRID
        jr nc,.nh                       ; off the map
        ld e,a
        inc hl
        ld a,(ix+3)
        add a,(hl)
        cp GRID
        jr nc,.nh
        ld d,a
        push de
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        ld de,city_map
        add hl,de
        pop de
        ld a,(hl)
        and CELL_CODE
        call dv_walkable
        jr nz,.nh
        ld (dt_try),hl
        ld a,(dt_vx)                    ; its score: |x - vx| + |z - vz|,
        sub e                           ; doubled, + a random bit, + DT_BACK
        jr nc,.ax                       ; (doubled) back the way it came
        neg
.ax:    ld c,a
        ld a,(dt_vz)
        sub d
        jr nc,.az
        neg
.az:    add a,c
        cp DT_FAR
        jr c,.nf
        ld a,DT_FAR                     ; (far: as far)
.nf:    add a,a
        ld c,a
        ld a,(dt_back)
        cp b
        jr nz,.nb
        ld a,c
        add a,2*DT_BACK
        ld c,a
.nb:    push bc
        push de
        call zrand
        pop de
        pop bc
        ld a,l
        and 1
        add a,c
        ld hl,dt_best
        cp (hl)
        jr nc,.nh
        ld (hl),a
        ld a,b
        ld (dt_dir),a
        ld (dt_cell),de
        ld hl,(dt_try)
        ld (dt_ptr),hl
.nh:    inc b
        ld a,b
        cp 4
        jp nz,.h
        ret
        ASSERT 2*DT_FAR+2*DT_BACK+1 < 255      ; (scores fit a byte)

; A = a cell's code: Z if the devil can walk there: road, rubble, a building
; coming down, a building under level DV_TALL (knocked down), a terrace
; tile, the base's or a barricade, or the landing pad (knocked down too)
dv_walkable:
        or a
        ret z                           ; road
        cp DV_TALL
        jr c,.y                         ; a low building
        cp PAD_CODE
        ret z
        cp TERRACE_CODE
        ret z
        cp RUBBLE_CODE
        ret c                           ; (a tall building: NZ, carry)
        cp COLLAPSE_CODE+COLLAPSE_N
        jr nc,.n
.y:     cp a                            ; Z
        ret
.n:     or 1                            ; NZ
        ret
        ASSERT RUBBLE_CODE+1 == COLLAPSE_CODE && TERRACE_CODE < RUBBLE_CODE

; Cell HL (E, D), where the devil walks next: a building, a terrace or
; barricade tile or the landing pad there knocked down, as its lightning
; does (dv_topple: it falls to rubble).  The base tiles' hit points go to 0
; (base_damage, and the pad's directly: crushed by the devil it's no game
; over), a terrace tile's colour the road's.  Road, rubble: nothing.
dv_flatten:
        ld a,(hl)
        and CELL_CODE
        ret z
        cp RUBBLE_CODE
        ret nc                          ; rubble, or coming down already
        push hl
        call bld_height
        ld (dt_h),hl                    ; its height
        pop hl
        ld a,(hl)
        and CELL_CODE
        cp PAD_CODE
        jr z,.pad
        cp TERRACE_CODE
        jp nz,dv_topple_h               ; a low building
        push hl                         ; a terrace or barricade tile: gone
        push de                         ; (road for now, its colour too)
        ld c,255
        call base_damage                ; (zombie.asm)
        pop de
        pop hl
        jp dv_topple_h
.pad:   ld a,TERRACE_R*(2*TERRACE_R+1)+TERRACE_R
        push hl
        ld hl,base_hp
        add hl,a
        ld (hl),0                       ; (zombies leave it alone now)
        pop hl
        jp dv_topple_h

; Its eyes and its lightning: resting DV_REST_T interrupts after a shot,
; then (with the VTOL within DV_RANGE) charging DV_CHARGE_T, the eyes black
; to blue; charged, it fires when the VTOL is in range
dv_charge:
        ld hl,(isr_ticks)               ; the time since its state began
        ld e,(ix+DV_T0)
        ld d,(ix+DV_T0+1)
        or a
        sbc hl,de
        bit 7,h
        jr z,.t
        ld hl,(isr_ticks)               ; (the count was reset: from now)
        ld (ix+DV_T0),l
        ld (ix+DV_T0+1),h
        ld hl,0
.t:     ld (dc_t),hl
        ld a,(vtol_dead)
        or a
        jp nz,dv_eye_black              ; (nothing to shoot)
        bit 0,(ix+DV_EYES)
        jr nz,.chg
        ld de,DV_REST_T                 ; resting
        or a
        sbc hl,de
        ret c
        ld (ix+DV_EYES),1               ; charge (wherever the VTOL is)
        jr .now
.chg:   ld de,DV_CHARGE_T-DV_HUM_T     ; the last 3 s: the whine (once)
        or a
        sbc hl,de
        jr c,.nh
        bit 1,(ix+DV_EYES)
        jr nz,.nh
        set 1,(ix+DV_EYES)
        ld a,SFX_CHARGE
        ld (sfx3_req),a
        ld a,1
        ld (dv_hum),a                   ; (splats wait: weapons.asm)
.nh:    ld hl,(dc_t)
        ld de,DV_CHARGE_T
        or a
        sbc hl,de
        jr nc,.full
        ld hl,(dc_t)                    ; charging: the eyes' blue, 0..7,
        add hl,hl                       ; t * 8 / DV_CHARGE_T
        add hl,hl
        add hl,hl
        ld de,DV_CHARGE_T
        call udiv16                     ; (human.asm) HL = HL / DE
        ld a,l
        jp dv_eye
.full:  ld a,7                          ; charged: full blue
        call dv_eye
        call dv_range                   ; the VTOL in range: at it; else up
        jr c,.at                        ; into the sky
        call dv_fire_up
        jr .rest
.at:    call dv_fire
.rest:  ld (ix+DV_EYES),0               ; rest, then charge again
        call dv_eye_black
.now:   ld hl,(isr_ticks)
        ld (ix+DV_T0),l
        ld (ix+DV_T0+1),h
        ret

; Carry set if the VTOL is within DV_RANGE of devil IX (max + 3/8 min of the
; axes' distances); dc_dx, dc_dz = from it to the VTOL
dv_range:
        ld hl,(cam_x+1)
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        ld (dc_dx),hl
        call abs_hl
        push hl
        ld hl,(cam_z+1)
        ld e,(ix+2)
        ld d,(ix+3)
        or a
        sbc hl,de
        ld (dc_dz),hl
        call abs_hl
        pop de
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl                        ; HL = max, DE = min
.mx:    push hl
        ld h,d
        ld l,e
        add hl,hl
        add hl,de                       ; 3 min
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        pop de
        add hl,de
        ld de,DV_RANGE+1
        or a
        sbc hl,de                       ; carry: within range
        ret

; Its eyes' palette entry (DEVIL_EYE): A = blue 0..7 (with some green as
; it brightens)
dv_eye:
        ld c,a
        ld a,(vision_mode)              ; thermal: red; night vision (green
        cp VM_THERMAL                   ; or monochrome): white; else blue
        jr z,.red
        or a
        jr nz,.white
        ld a,c
        srl a                           ; RRRGGGBB: blue's top two bits,
        ld b,a                          ; green from 5 on
        ld a,c
        sub 4
        jr nc,.g
        xor a
.g:     add a,a
        add a,a
        or b
        ld b,a
.wr:    nextreg $43,%00010000           ; (Layer 2's first palette: the level's)
        nextreg $40,DEVIL_EYE
        ld a,b
        nextreg $44,a
        ld a,c
        and 1
        nextreg $44,a                   ; its low blue bit
        ret
.red:   ld a,c                          ; red: level << 5
        rrca
        rrca
        rrca
        and $E0
        ld b,a
        ld c,0
        jr .wr
.white: ld a,c                          ; white: the level in red, green and
        rrca                            ; blue (RRRGGGBB, the low blue bit)
        rrca
        rrca
        and $E0
        ld b,a
        ld a,c
        add a,a
        add a,a
        or b
        ld b,a
        ld a,c
        srl a
        or b
        ld b,a
        jr .wr
        ASSERT VM_NORMAL == 0
dv_eye_black:
        xor a
        jr dv_eye
        ASSERT DEVIL_EYE == DEVIL_EYE_ENTRY

;------------------------------------------------------------------------------
; Devil IX fires: the bolt from its eyes to the VTOL (drawn BOLT_FRAMES
; frames: draw_bolt, city2.asm); every building the line passes below the
; roof of comes down; and the VTOL is hit
;------------------------------------------------------------------------------
dv_fire:
        xor a
        ld (bolt_up),a                  ; (at the VTOL)
        ld a,BOLT_FRAMES
        ld (bolt_t),a
        ld a,SFX_BOLT                   ; the crackling zap, the thunder
        ld (sfx2_req),a
        xor a
        ld (dv_hum),a                   ; (the whine over: splats again)
        call shake_big                  ; (zpolice.asm)
        ; along the line: 32 points, from its eyes to the VTOL
        ld l,(ix+0)
        ld h,(ix+1)
        ld (df_x),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (df_z),hl
        ld hl,DV_EYE_H
        ld (df_y),hl
        ld hl,(dc_dx)                   ; (dv_range: to the VTOL)
        call .d32
        ld (df_sx),hl
        ld hl,(dc_dz)
        call .d32
        ld (df_sz),hl
        ld hl,(cam_y)
        ld de,DV_EYE_H
        or a
        sbc hl,de
        call .d32
        ld (df_sy),hl
        ld hl,$FFFF
        ld (df_cell),hl
        ld b,31
.pt:    push bc
        ld hl,(df_x)
        ld de,(df_sx)
        add hl,de
        ld (df_x),hl
        ld hl,(df_z)
        ld de,(df_sz)
        add hl,de
        ld (df_z),hl
        ld hl,(df_y)
        ld de,(df_sy)
        add hl,de
        ld (df_y),hl
        ld a,(df_x+1)                   ; its cell, if new
        ld e,a
        ld a,(df_z+1)
        ld d,a
        ld hl,(df_cell)
        or a
        sbc hl,de
        jr z,.nx
        ld (df_cell),de
        call dv_struck
        jr c,.cover                     ; a building in the way: it stops there
.nx:    pop bc
        djnz .pt
        xor a
        ld (bolt_hit),a                 ; (on to the VTOL)
        ; the VTOL: damage, a spin, its nose pitched, its speed halved
        ld a,BOLT_DMG
        call vtol_damage                ; (zpolice.asm)
        ld a,(vtol_dead)
        or a
        ret nz                          ; (destroyed: a wreck spins its own way)
        call zrand
        ld a,l                          ; 7..44 degrees
        and 31
        cp SPIN_RANGE
        jr c,.r
        sub SPIN_RANGE
.r:     add a,SPIN_MIN
        ld e,a                          ; a frame: angle * 256 / SPIN_FR
        ld d,256/SPIN_FR
        mul d,e
        bit 0,h                         ; either way
        jr z,.sp
        ex de,hl
        call neg_hl
        ex de,hl
.sp:    ld (spin_rate),de
        ld a,SPIN_FR
        ld (spin_t),a
        ld a,PITCH_KICK                 ; the nose half way up or down
        bit 1,h
        jr z,.pu
        ld a,-PITCH_KICK
.pu:    ld (pitch),a
        xor a
        ld (pitch_frac),a
        ld a,(boost_on)                 ; (a boost: off, its speed kept to
        or a                            ; halve)
        jr z,.nb
        xor a
        ld (boost_on),a
.nb:    ld a,(speed)                    ; braked to half its speed
        sra a
        ld (bolt_spd),a
        ld a,1
        ld (bolt_brake),a
        ret
.cover: pop bc                          ; the building it hit: the bolt ends
        ld hl,(df_x)                    ; there (draw_bolt), the VTOL safe
        ld (bolt_end),hl
        ld hl,(df_y)
        ld (bolt_end+2),hl
        ld hl,(df_z)
        ld (bolt_end+4),hl
        ld a,1
        ld (bolt_hit),a
        ret
.d32:   sra h                           ; HL / 32, signed
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ret
        ASSERT 256 % SPIN_FR == 0 && (SPIN_MIN+SPIN_RANGE-1)*(256/SPIN_FR) < 32768

; Charged with the VTOL out of range: the bolt up into the sky (drawn so:
; bolt_up), the crackle and thunder, nothing hit
dv_fire_up:
        xor a
        ld (bolt_hit),a
        inc a
        ld (bolt_up),a
        ld a,BOLT_FRAMES
        ld (bolt_t),a
        ld a,SFX_BOLT
        ld (sfx2_req),a
        xor a
        ld (dv_hum),a                   ; (the whine over: splats again)
        ret

; The bolt over cell (E, D) at height df_y: a building (not the perimeter
; wall) whose roof is above it comes down, and carry is set (the bolt stops
; there: buildings are cover)
dv_struck:
        ld a,e
        dec a
        cp GRID-2
        ret nc                          ; the wall's columns (or off the map)
        ld a,d
        dec a
        cp GRID-2
        ret nc
        push de
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        ld de,city_map
        add hl,de
        pop de
        ld a,(hl)
        and CELL_CODE
        ret z                           ; road
        cp 16
        ret nc                          ; not a building (the base, rubble...)
        push hl
        push de
        call bld_height                 ; (zpolice.asm)
        ld de,(df_y)
        bit 7,d
        jr nz,.hit                      ; (under the ground: any)
        or a
        sbc hl,de                       ; roof - line
        pop de
        pop hl
        jr c,.no
        jr nz,.down
.no:    or a                            ; (carry clear: past it)
        ret
.hit:   pop de
        pop hl
.down:  call dv_topple
        scf                             ; (carry: it stopped the bolt)
        ret

; Building cell HL (E, D) comes down: the humans on it killed, a slot to
; fall in (none free: rubble at once), DV_PARTS particles over it
dv_topple:
        ld a,(hl)
        and CELL_CODE
        push hl
        call bld_height
        ld (dt_h),hl                    ; its height
        pop hl
dv_topple_h:                            ; (dt_h: its height)
        push hl
        push de
        call dv_kill_hums
        pop de
        pop hl
        push de
        push iy
        ld iy,cl_ptr                    ; a free slot
        ld b,COLLAPSE_N
        ld c,COLLAPSE_CODE
.sl:    ld a,(iy+0)
        or (iy+1)
        jr z,.got
        inc iy
        inc iy
        inc c
        djnz .sl
        ld a,(hl)                       ; none: rubble now
        and CELL_FLAGS
        or RUBBLE_CODE
        ld (hl),a
        jr .parts
.got:   ld (iy+0),l
        ld (iy+1),h
        ld a,(hl)                       ; its slot's code: its height there
        and CELL_FLAGS
        or c
        ld (hl),a
        ld de,(dt_h)
        ld (iy+2*COLLAPSE_N),e
        ld (iy+2*COLLAPSE_N+1),d
        ld a,c
        add a,a
        ld hl,htab
        add hl,a
        ld (hl),e
        inc hl
        ld (hl),d
.parts: pop iy
        pop de                          ; fire and dust all over it
        ld c,DV_PARTS
        ld hl,(dt_h)
        jp dv_spray_wide
        ASSERT COLLAPSE_CODE+COLLAPSE_N <= 32 && RUBBLE_CODE < 32

; The humans waiting in cell (E, D): killed
dv_kill_hums:
        push ix
        ld ix,humans
        ld b,HUMAN_MAX
.lp:    ld a,(ix+6)
        cp HS_WAIT
        jr nz,.nx
        ld a,(ix+1)
        cp e
        jr nz,.nx
        ld a,(ix+3)
        cp d
        jr nz,.nx
        push bc
        push de
        ld (ix+10),0
        ld c,0
        call hum_dot                    ; (map.asm) its dot off
        ld (ix+6),HS_DEAD
        pop de
        pop bc
.nx:    push de
        ld de,HREC
        add ix,de
        pop de
        djnz .lp
        call hum_flags                  ; (human.asm) the marks again
        pop ix
        ret

; Each footfall: the zombies (and the other walkers: ghouls, a lich) and
; the waiting humans within DEVIL_HIT_R of it on each axis are trodden on:
; killed (a zombie as zdamage kills one, a burst of green; a human dead)
dv_tread:
        push ix
        ld l,(ix+0)
        ld h,(ix+1)
        ld (dt_fx),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (dt_fz),hl
        push iy
        ld iy,zombies
        ld b,NMON
        ld c,0                          ; (its index)
.z:     push bc
        bit 0,(iy+10)
        jr z,.zn
        ld a,(iy+15)
        cp ZT_GHOST
        jr nc,.zn                       ; (fliers, and the devil: not trodden)
        call .near
        jr nc,.zn
        pop bc
        push bc
        ld a,c                          ; not attacking anything now
        ld hl,zatk_flags
        add hl,a
        ld (hl),FALSE
        push iy
        pop ix
        call zblip_off                  ; (map.asm)
        ld (ix+10),0                    ; gone
        ld e,(ix+1)                     ; a green burst
        ld d,(ix+3)
        ld hl,ZOMBIE_H
        ld bc,PART_COL0 | PART_LIFE<<8
        ld a,DV_TREAD_PARTS
        call dv_spray_c
        ld a,(dv_hum)                   ; (a splat: not over the whine)
        or a
        jr nz,.zn
        ld a,SFX_SPLAT
        ld (sfx3_req),a
.zn:    ld de,ZREC
        add iy,de
        pop bc
        inc c
        djnz .z
        xor a
        ld (dt_any),a
        ld iy,humans                    ; the humans waiting
        ld b,HUMAN_MAX
.h:     push bc
        ld a,(iy+6)
        cp HS_WAIT
        jr nz,.hn
        call .near
        jr nc,.hn
        push iy
        pop ix
        ld (ix+10),0
        ld c,0
        call hum_dot                    ; (map.asm) its dot off
        ld (ix+6),HS_DEAD
        ld a,1
        ld (dt_any),a
.hn:    ld de,HREC
        add iy,de
        pop bc
        djnz .h
        pop iy
        ld a,(dt_any)
        or a
        call nz,hum_flags               ; (human.asm) the marks again
        pop ix
        ret
.near:  ld l,(iy+0)                     ; carry: IY within DEVIL_HIT_R on x, z
        ld h,(iy+1)
        ld de,(dt_fx)
        call .ax
        ret nc
        ld l,(iy+2)
        ld h,(iy+3)
        ld de,(dt_fz)
.ax:    or a
        sbc hl,de
        call abs_hl
        ld de,DEVIL_HIT_R+1
        or a
        sbc hl,de
        ret

; The devil killed: every other monster record (zombies, any special) gone
; at once, as zdamage kills one (not attacking, its blip off), a little
; green burst each
dv_kill_all:
        push ix
        push iy
        ld iy,zombies
        ld b,NMON
        ld c,0                          ; (its index)
.lp:    push bc
        bit 0,(iy+10)
        jr z,.nx
        ld a,(iy+15)
        cp ZT_DEVIL
        jr z,.nx                        ; (itself)
        ld a,c
        ld hl,zatk_flags
        add hl,a
        ld (hl),FALSE
        push iy
        pop ix
        call zblip_off                  ; (map.asm)
        ld (ix+10),0                    ; gone
        ld e,(ix+1)
        ld d,(ix+3)
        ld hl,ZOMBIE_H
        ld bc,PART_COL0 | PART_LIFE<<8
        ld a,DV_KILL_PARTS
        call dv_spray_c
.nx:    ld de,ZREC
        add iy,de
        pop bc
        inc c
        djnz .lp
        pop iy
        pop ix
        ret

; C fire particles at random places in cell (E, D), from the ground to
; height HL, flying out (as a rocket's burst, x and z -8..7 a frame; wide:
; a building's, -16..15); only free ones
dv_spray_wide:
        ld a,31
        jr dv_spray_m
dv_spray:
        ld a,15
dv_spray_m:
        ld (ds_m),a
        ld a,c
        ld bc,FIRE_COL0 | FIRE_LIFE<<8
        jr dv_spray_go
; A particles, colour C (age 1), lasting B frames (the narrow spread)
dv_spray_c:
        push af
        ld a,15
        ld (ds_m),a
        pop af
dv_spray_go:
        ld (ds_col),bc
        ld c,a
        ld (ds_top),hl
        ld (ds_cell),de
        push iy
        ld iy,particles
        ld b,NPART
.lp:    ld a,(iy+0)
        or a
        jr nz,.nx                       ; in use
        push bc
        call zrand
        ld (iy+1),l                     ; x: in the cell
        ld a,(ds_cell)
        ld (iy+2),a
        ld (iy+5),h                     ; z
        ld a,(ds_cell+1)
        ld (iy+6),a
        call zrand                      ; y: 0..top, (top * r) / 256
        push hl
        ld a,(ds_top)
        ld e,a
        ld d,l
        mul d,e
        ld c,d                          ; (top low * r) >> 8
        ld a,(ds_top+1)
        ld e,a
        ld d,l
        mul d,e                         ; top high * r
        ld a,c
        add a,e
        ld (iy+3),a
        ld a,d
        adc a,0
        ld (iy+4),a
        pop hl
        ld a,(ds_m)                     ; velocities: x, z -(m+1)/2..m/2
        ld e,a                          ; (ds_m: 15 or 31), y -2..5
        inc a
        srl a
        ld d,a
        ld a,h
        and e
        sub d
        ld (iy+7),a
        ld a,h
        rrca
        rrca
        rrca
        and e
        sub d
        ld (iy+9),a
        ld a,l
        and 7
        sub 2
        ld (iy+8),a
        ld (iy+0),1                     ; age 1
        ld a,(ds_col)
        ld (iy+10),a
        ld a,(ds_col+1)
        ld (iy+11),a
        pop bc
        dec c
        jr z,.done
.nx:    ld de,PREC
        add iy,de
        djnz .lp
.done:  pop iy
        ret

;------------------------------------------------------------------------------
; Killed (zdamage: GM_DYING, +17 = DV_DIE_FR): every other monster dies
; with it at once (dv_kill_all); it sinks into the ground in fire, its eyes
; dark, the ground shaking; then gone.  Its wave is the last, so with
; nothing left the level, the game, is complete (zombie_update: level_done;
; the congratulations).
;------------------------------------------------------------------------------
dv_dying:
        ld a,(ix+17)                    ; (its first frame dying)
        cp DV_DIE_FR
        call z,dv_kill_all
        xor a
        ld (dv_hum),a
        call dv_eye_black
        ld l,(ix+21)
        ld h,(ix+22)
        ld de,-DV_SINK
        add hl,de
        ld (ix+21),l
        ld (ix+22),h
        ld a,(shake_t)
        or a
        jr nz,.sh
        ld a,SHAKE_LEN
        ld (shake_t),a
.sh:    ld a,(ix+17)
        and 1
        jr nz,.nf
        ld e,(ix+1)                     ; fire over what's left of it
        ld d,(ix+3)
        ld hl,DEVIL_H
        ld c,DV_DIE_PARTS
        call dv_spray
.nf:    dec (ix+17)
        ret nz
        ld (ix+10),0                    ; gone
        ret

;------------------------------------------------------------------------------
; The devil's data
;------------------------------------------------------------------------------
cl_ptr:     ds 2*COLLAPSE_N             ; buildings coming down: each its
cl_h:       ds 2*COLLAPSE_N             ;   city_map cell (0: a free slot) and
                                        ;   height now (in htab too)
cl_tog:     db 0                        ; (they fall every other frame)
dt_best:    db 0                        ; dv_turn: the best score so far,
dt_dir:     db 0                        ;   its heading,
dt_back:    db 0                        ;   the way it came from,
dt_vx:      db 0                        ;   the VTOL's cell,
dt_vz:      db 0
dt_try:     dw 0                        ;   the cell tried,
dt_cell:    dw 0                        ;   the best one (x, z),
dt_ptr:     dw 0                        ;   and its city_map byte
dt_h:       dw 0                        ; dv_topple: the building's height
dc_t:       dw 0                        ; dv_charge: interrupts in this state
dc_dx:      dw 0                        ; dv_range: to the VTOL
dc_dz:      dw 0
df_x:       dw 0                        ; dv_fire: the point along the bolt,
df_y:       dw 0
df_z:       dw 0
df_sx:      dw 0                        ;   its step,
df_sy:      dw 0
df_sz:      dw 0
df_cell:    dw 0                        ;   the last cell (x, z)
ds_top:     dw 0                        ; dv_spray: the top,
ds_col:     dw 0                        ;   the colour and life,
ds_m:       db 0                        ;   the spread (15 or 31)
dt_fx:      dw 0                        ; dv_tread: where it is,
dt_fz:      dw 0
dt_any:     db 0                        ;   1: a human trodden on
ds_cell:    dw 0                        ;   the cell (x, z)
