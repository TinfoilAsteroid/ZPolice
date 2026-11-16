;==============================================================================
; Z-POLICE - player page (8K page PAGE_PLAYER, runs at $C000 in slot 6)
;
; Keyboard input, movement along the heading, world-edge clamping and
; building collision.  Paged in by main_loop with nextreg LOGIC_MMU,
; PAGE_PLAYER, with the keys page (key_held) in slot 7.
; Uses the resident helpers get_sin, fmul and bld_height; camera state (cam_x/z/y, yaw, pitch, speed) is shared and
; stays in zpolice.asm.
;==============================================================================

;==============================================================================
; Player input and movement
;==============================================================================
update_player:
        xor a
        out ($FE),a                     ; border back to black
        ld hl,YAW_RATE                  ; this frame's turn (a frame's worth)
        call fs_mul
        ld (yaw_step),hl
        ; remember position in case we fly into something
        ld hl,cam_x                     ; (and the heading: turning swings
        ld de,old_pos                   ; the VTOL's nose and tail)
        ld bc,10                        ; cam_x(3) cam_z(3) cam_y(2) yaw(2)
        ldir
        ld a,(vtol_dead)
        or a
        jr z,.alive
        xor a
        ld (boost_on),a                 ; (no boost in a wreck)
        jp vtol_wreck                   ; destroyed: out of control
.alive:
        ; (keys: kbd_scan has read them; actions from input.asm)
        ; --- boost (zpolice.asm: BOOST_*): while on, the speed keys and the
        ; air brake don't change the speed, and each frame burns a fuel
        ld a,(boost_on)
        or a
        jr z,.nb
        ld a,(speed)
        cp BOOST_SPEED
        jr nz,.bend                     ; stopped meanwhile (a collision)
        call vtol_on_floor
        jr z,.bend                      ; set down: off (the brake stops it)
        ld a,K_BOOST
        call key_pressed
        jr nz,.boff                     ; pressed again: off
        ld a,(fsteps)                   ; a fuel a frame's worth
        ld c,a
        ld a,(boost_fuel)
        sub c
        jr z,.bout
        jr c,.bout
        ld (boost_fuel),a
        jr .bkeep                       ; still burning
.bout:  xor a
        ld (boost_fuel),a
.boff:  ld a,(boost_spd)                ; off (or out of fuel): the speed it
        ld (speed),a                    ; had before
.bend:  xor a
        ld (boost_on),a
.bkeep: xor a                           ; (no air brake this frame)
        ld (ab_on),a
        jp .nw
.nb:    ld a,K_BOOST                    ; off: pressed to start it?
        call key_pressed
        jr z,.nbs
        ld a,(boost_fitted)
        or a
        jr z,.nbs                       ; no booster
        ld a,(boost_fuel)
        or a
        jr z,.nbs                       ; no fuel
        call vtol_on_floor
        jr z,.nbs                       ; landed: not on the ground
        ld a,(speed)
        bit 7,a
        jr nz,.nbs                      ; reversing
        cp BOOST_MIN
        jr c,.nbs                       ; under half speed
        ld (boost_spd),a
        ld a,BOOST_SPEED                ; on: twice the top speed at once
        ld (speed),a
        ld a,1
        ld (boost_on),a
        jr .bkeep
.nbs:
        ; --- landed (resting on the road, a roof or the pad): the speed keys
        ; only bring it back to 0 (speeding up only from reverse, slowing
        ; only from forwards), and any speed is braked away as the air brake
        ; does (as if Z were held), with a shake
        call vtol_on_floor
        jr nz,.fly
        ld a,K_SPEED_UP
        call key_held
        jr z,.lq
        ld a,(speed)
        bit 7,a
        jr z,.lq                        ; not reversing: no
        ld hl,fsteps
        add a,(hl)
        jp m,.lqs
        xor a                           ; (not past 0)
.lqs:   ld (speed),a
.lq:    ld a,K_SPEED_DN
        call key_held
        jr z,.lb
        ld a,(speed)
        or a
        jr z,.lb                        ; at 0 or reversing: no
        jp m,.lb
        ld hl,fsteps
        sub (hl)
        jr nc,.lds
        xor a                           ; (not past 0)
.lds:   ld (speed),a
.lb:    ld a,(speed)
        or a
        jp z,.na                        ; stopped (Z: nothing to brake)
        ld a,(shake_t)                  ; a shake, unless one is going
        or a
        jr nz,.lbr
        ld a,SHAKE_LEN
        ld (shake_t),a
.lbr:   xor a
        ld (ab_on),a
        jp .brk                         ; braked, as by the air brake
.fly:
        ; --- speed ---
        ld a,K_SPEED_UP                 ; (by SPEED_STEP, 1, a frame's worth)
        call key_held
        jr z,.nq
        ld a,(speed)
        ld hl,fsteps
        add a,(hl)
        jp m,.qs                        ; (still reversing)
        cp SPEED_MAX+1
        jr c,.qs
        ld a,SPEED_MAX
.qs:    ld (speed),a
.nq:    ld a,K_SPEED_DN
        call key_held
        jr z,.na
        ld a,(speed)
        ld hl,fsteps
        sub (hl)
        jp p,.ds
        cp SPEED_MIN & $FF              ; (reversing: not below SPEED_MIN)
        jr nc,.ds
        ld a,SPEED_MIN & $FF
.ds:    ld (speed),a
        ASSERT SPEED_STEP == 1
.na:    ; --- air brake: while held, the speed falls AIRBRAKE_STEP a frame
        ; towards 0, going forwards or backwards.  Each braking frame tips the
        ; nose one pitch step, as a nose key press does: up when braking
        ; forward motion, down when braking reverse.  The pitch damper waits
        ; while it brakes (ab_on), as it does while a nose key is held.
        xor a
        ld (ab_on),a
        ld a,(bolt_brake)               ; the devil's lightning: braked as by
        or a                            ; the air brake, to half the speed it
        jr z,.kz                        ; had (bolt_spd)
        ld a,(bolt_spd)
        bit 7,a
        jr z,.t1
        neg
.t1:    ld c,a
        ld a,(speed)
        bit 7,a
        jr z,.t2
        neg
.t2:    cp c
        jr z,.bto
        jp nc,.brk                      ; still faster: brake
.bto:   xor a                           ; down to it: the brake off
        ld (bolt_brake),a
.kz:    ld a,K_AIRBRAKE
        call key_held
        jr z,.nw
.brk:   ld a,(speed)
        or a
        jr z,.stp                       ; stopped: nothing to brake
        ld (ab_on),a                    ; (non-zero: braking this frame)
        ld a,(fsteps)                   ; a step a frame's worth
        or a
        jr z,.nw
        ld b,a
.bl:    ld a,(speed)
        or a
        jr z,.nw
        jp m,.rev
        sub AIRBRAKE_STEP               ; forwards: slower, not past 0
        jr nc,.fwd
        xor a
.fwd:   ld (speed),a
        xor a
        ld (pitch_frac),a               ; whole steps, as the keys
        ld a,(pitch)
        cp PMAX
        jr z,.bn
        inc a                           ; nose up
        ld (pitch),a
        jr .bn
.rev:   add a,AIRBRAKE_STEP             ; backwards: towards 0, not past it
        jr nc,.bk
        xor a
.bk:    ld (speed),a
        xor a
        ld (pitch_frac),a
        ld a,(pitch)
        cp (-PMAX) & $FF
        jr z,.bn
        dec a                           ; nose down
        ld (pitch),a
.bn:    djnz .bl
        jr .nw
.stp:   xor a                           ; stopped: the lightning's brake off
        ld (bolt_brake),a
.nw:
        ; --- yaw: YAW_RATE a frame, but YAW_FINE on the frame a turn key is
        ; first pressed (a tap turns 1 degree: fine control)
        ld a,K_LEFT
        call key_held
        jr z,.ns
        ld de,(yaw_step)
        ld a,K_LEFT
        call key_pressed
        jr z,.lr
        ld de,YAW_FINE
.lr:    ld hl,(yaw_frac)                ; 8.8 heading
        or a
        sbc hl,de
        ld (yaw_frac),hl
.ns:    ld a,K_RIGHT
        call key_held
        jr z,.nf
        ld de,(yaw_step)
        ld a,K_RIGHT
        call key_pressed
        jr z,.rr
        ld de,YAW_FINE
.rr:    ld hl,(yaw_frac)
        add hl,de
        ld (yaw_frac),hl
.nf:    ld a,(spin_t)                   ; the devil's lightning: spun round
        or a                            ; (spin_rate a tick for spin_t ticks,
        jr z,.nsp                       ; devil.asm)
        ld c,a
        ld a,(dt)
        cp c
        jr c,.sp1
        ld a,c                          ; (the last of it)
.sp1:   ld b,a
        ld a,c
        sub b
        ld (spin_t),a
        ld a,b
        or a
        jr z,.nsp
        ld hl,(yaw_frac)
        ld de,(spin_rate)
.sp2:   add hl,de
        djnz .sp2
        ld (yaw_frac),hl
.nsp:
        ; --- pitch ---
        ld a,K_NOSE_DN
        call key_held
        jr z,.ng
        xor a
        ld (pitch_frac),a               ; keys move in whole steps, a step
        ld a,(fsteps)                   ; a frame's worth
        or a
        jr z,.ng
        ld b,a
.pd:    ld a,(pitch)
        cp (-PMAX) & $FF
        jr z,.ng
        dec a
        ld (pitch),a
        djnz .pd
.ng:    ld a,K_NOSE_UP
        call key_held
        jr z,.nt
        xor a
        ld (pitch_frac),a
        ld a,(fsteps)
        or a
        jr z,.nt
        ld b,a
.pu:    ld a,(pitch)
        cp PMAX
        jr z,.nt
        inc a
        ld (pitch),a
        djnz .pu
.nt:    ; --- pitch damper: ease back to level when the pitch keys are released
        ; (and the air brake isn't tipping the nose)
        ld a,(ab_on)
        or a
        jr nz,.held
        ld a,K_NOSE_UP
        call key_held
        jr nz,.held
        ld a,K_NOSE_DN
        call key_held
        jr nz,.held
        ld a,(fsteps)                   ; (frames' worth)
        or a
        jr z,.pdx
        ld b,a
.pdl:   push bc
        ld hl,pd_count
        dec (hl)
        jr nz,.pdn
        ld (hl),PDAMP_FRAMES
        call pitch_damp
.pdn:   pop bc
        djnz .pdl
        jr .pdx
.held:  ld a,PDAMP_FRAMES               ; a full interval after letting go
        ld (pd_count),a
.pdx:
        ; --- height ---
        ld a,K_CLIMB
        call key_held
        jr z,.ne
        ld a,CLIMB_RATE                 ; (a frame's worth)
        ld hl,cy_frac
        call fs_amount
        ld e,a
        ld d,0
        ld hl,(cam_y)
        add hl,de
        ld de,MAX_Y                     ; the ceiling: higher with the
        ld a,(vthrust_fitted)           ; vertical thrusters
        or a
        jr z,.ceil
        ld de,MAX_Y_THRUST
.ceil:  call min_hl_de
        ld (cam_y),hl
.ne:    ld a,K_DESCEND
        call key_held
        jr z,.nd
        ld a,CLIMB_RATE
        ld hl,cy_frac
        call fs_amount
        ld e,a
        ld d,0
        ld hl,(cam_y)
        or a
        sbc hl,de
        ld de,MIN_Y
        call max_hl_de
        push hl                         ; and not below the floor under the
        call floor_y                    ; VTOL: it lands on the road or the
        ex de,hl                        ; highest roof under it (no collision)
        pop hl
        call max_hl_de
        ld (cam_y),hl
.nd:
        ; --- move along heading: pos += speed * (sin, cos) ---
        ld a,(speed)
        or a
        jr z,.moved
        ld h,a                          ; this frame's: speed * fs, 8.8
        ld l,0
        call fs_mul
        ld (spd88),hl
        ld a,(yaw)
        call get_sin
        ex de,hl
        ld hl,(spd88)
        call fmul                       ; HL = speed*sin in 1/256 units
        ld ix,cam_x
        call add_pos
        ld a,(yaw)
        add a,64
        call get_sin
        ex de,hl
        ld hl,(spd88)
        call fmul
        ld ix,cam_z
        call add_pos
.moved:
        call strafe                     ; (the lateral thrusters)
        call check_collision
        ret z
        ; crashed - restore and stop, taking |speed| / 4 (a 2-bit shift
        ; right, rounded down) as damage
        ld hl,old_pos
        ld de,cam_x
        ld bc,10
        ldir
        ld a,(speed)
        bit 7,a
        jr z,.dmg
        neg                             ; (reversing into it)
.dmg:   srl a
        srl a
        call vtol_damage                ; (zpolice.asm)
        xor a
        ld (speed),a
        ld a,C_WARN
        out ($FE),a                     ; red border flash
        ld a,(shake_t)                  ; a shake and a crunch, unless one is
        or a                            ; still going (held against a wall:
        ret nz                          ; not every bump)
        ld a,SHAKE_LEN
        ld (shake_t),a                  ; (shake_tick, zpolice.asm)
        ld a,SFX_CRASH
        ld (sfx2_req),a                 ; (AY 3: the explosions' voice)
        ret

; The lateral thrusters (lthrust_fitted): while a strafe control
; (K_STRAFE_L, K_STRAFE_R) is held, the VTOL moves STRAFE_D sideways,
; square to its heading, each frame; not when landed (resting on the
; floor).  Collisions as for any move (check_collision, after this).
STRAFE_D_HALVES equ 5               ; 2.5 world units a frame (0.195 m)
strafe:
        ld a,(lthrust_fitted)
        or a
        ret z
        call vtol_on_floor
        ret z                           ; landed
        ld c,64                         ; right: the heading + 90 degrees
        ld a,K_STRAFE_R
        call key_held                   ; (keeps BC)
        jr nz,.go
        ld c,-64 & $FF                  ; left: - 90
        ld a,K_STRAFE_L
        call key_held
        ret z
.go:    ld a,(yaw)
        add a,c
        ld (st_a),a
        call get_sin                    ; its x: sin
        call .d
        ld ix,cam_x
        call add_pos
        ld a,(st_a)
        add a,64
        call get_sin                    ; its z: cos
        call .d
        ld ix,cam_z
        jp add_pos
; HL = S7.8 component -> HL = 2.5 * it: the move in 1/256 units
.d:     ld d,h
        ld e,l
        sra d
        rr e                            ; half
        add hl,hl                       ; twice
        add hl,de
        jp fs_mul                       ; (a frame's worth)
        ASSERT STRAFE_D_HALVES == 5     ; (.d: 2 + 1/2)

; IX -> 24-bit position (frac, lo, hi). HL = signed delta in 1/256 units.
; Clamps the integer part to WORLD_MIN..WORLD_MAX.
add_pos:
        ld a,h
        rla
        sbc a,a
        ld c,a                          ; sign extension
        ld a,(ix+0)
        add a,l
        ld (ix+0),a
        ld a,(ix+1)
        adc a,h
        ld (ix+1),a
        ld a,(ix+2)
        adc a,c
        ld (ix+2),a
        ld l,(ix+1)
        ld h,(ix+2)
        bit 7,h
        jr nz,.lo
        ld de,WORLD_MIN
        or a
        sbc hl,de
        jr c,.lo
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,WORLD_MAX
        call min_hl_de
        ld (ix+1),l
        ld (ix+2),h
        ret
.lo:    ld (ix+1),WORLD_MIN & $FF
        ld (ix+2),WORLD_MIN >> 8
        ret

; Unsigned 16-bit clamps
min_hl_de:
        push hl
        or a
        sbc hl,de
        pop hl
        ret c
        ex de,hl
        ret

max_hl_de:
        push hl
        or a
        sbc hl,de
        pop hl
        ret nc
        ex de,hl
        ret

; Returns NZ if the VTOL hits a building: its footprint (10 m x 3 m, turned
; to the heading; vtol_ground) is over a roof less than COLL_H below it.
check_collision:
        call vtol_ground                ; HL = highest ground under it
        ret z                           ; all road
        ld de,COLL_H
        add hl,de
        ld de,(cam_y)
        or a
        sbc hl,de                       ; height+M - camY
        jr c,.no
        jr z,.no
        or 1                            ; NZ: collision
        ret
.no:    xor a
        ret

; The VTOL has been destroyed (vtol_dead): the controls do nothing.  It
; spins DEAD_SPIN a frame and falls, a unit a frame faster each frame (up
; to DEAD_FALL_MAX), until it hits the ground under it (floor_y: the road,
; or the highest roof under its footprint).  Once down it lies still for
; DEAD_PAUSE frames, then sets game_over (main_loop: the GAME OVER screen,
; then the main menu).
vtol_wreck:
        xor a
        ld (speed),a
        ld a,(dead_down)
        or a
        jr nz,.down
        ld hl,DEAD_SPIN                 ; spin (a frame's worth)
        call fs_mul
        ex de,hl
        ld hl,(yaw_frac)
        add hl,de
        ld (yaw_frac),hl
        ld a,(fsteps)                   ; fall, faster each frame's worth
        ld c,a
        ld a,(dead_vy)
        add a,c
        cp DEAD_FALL_MAX
        jr c,.vy
        ld a,DEAD_FALL_MAX
.vy:    ld (dead_vy),a
        ld hl,dv_frac
        call fs_amount
        ld e,a
        ld d,0
        ld hl,(cam_y)
        or a
        sbc hl,de
        jr nc,.y
        ld hl,0
.y:     push hl
        call floor_y                    ; HL = the ground under it
        ex de,hl
        pop hl
        or a
        sbc hl,de
        add hl,de
        jr nc,.set                      ; still above it
        ex de,hl                        ; hit the ground: on it
        ld a,1
        ld (dead_down),a
.set:   ld (cam_y),hl
        ret
.down:  ld a,(dt)                       ; on the ground: the pause (ticks),
        ld c,a                          ; then GAME OVER
        ld a,(dead_wait)
        sub c
        jr z,.go
        jr c,.go
        ld (dead_wait),a
        ret
.go:
        ld a,1
        ld (game_over),a
        ret

; One damping step: move the signed 8.8 pitch (pitch_frac/pitch) towards 0
; by max(PDAMP_MIN, |whole pitch| * PDAMP_K), stopping exactly at 0.
; Calculated rather than looked up: the Z80N MUL makes it as quick as a
; table, and the curve stays editable through the two equates.
pitch_damp:
        ld hl,(pitch_frac)
        ld a,h
        or l
        ret z                           ; already level
        ld a,h
        push af                         ; sign
        call abs_hl
        ld d,h                          ; whole part of |pitch|
        ld e,PDAMP_K
        mul d,e                         ; DE = step
        ld a,d
        or a
        jr nz,.sub
        ld a,e
        cp PDAMP_MIN
        jr nc,.sub
        ld de,PDAMP_MIN
.sub:   or a
        sbc hl,de
        jr nc,.sgn
        ld hl,0                         ; would pass level: stop at 0
.sgn:   pop af
        rla                             ; carry = was nose down
        call c,neg_hl
        ld (pitch_frac),hl
        ret

;==============================================================================
; Player page data
;==============================================================================
old_pos:    ds 10                       ; cam_x, cam_z, cam_y, yaw before the move
st_a:       db 0                        ; strafe: the pulse's direction
pd_count:   db PDAMP_FRAMES             ; frames to the next damping step
ab_on:      db 0                        ; non-zero: the air brake acted this frame
yaw_step:   dw 0                        ; YAW_RATE this frame
spd88:      dw 0                        ; speed this frame (8.8)
cy_frac:    db 0                        ; climbing: the fraction carried
dv_frac:    db 0                        ; the wreck's fall: the fraction carried
