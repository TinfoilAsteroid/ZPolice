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
        ld a,K_BOOST
        call key_pressed
        jr nz,.boff                     ; pressed again: off
        ld hl,boost_fuel
        dec (hl)
        jr nz,.bkeep                    ; still burning
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
        ; --- speed ---
        ld a,K_SPEED_UP                 ; (by SPEED_STEP, 1)
        call key_held
        jr z,.nq
        ld a,(speed)
        cp SPEED_MAX
        jr z,.nq
        inc a
        ld (speed),a
.nq:    ld a,K_SPEED_DN
        call key_held
        jr z,.na
        ld a,(speed)
        cp (SPEED_MIN) & $FF
        jr z,.na
        dec a
        ld (speed),a
.na:    ; --- air brake: while held, the speed falls AIRBRAKE_STEP a frame
        ; towards 0, going forwards or backwards.  Each braking frame tips the
        ; nose one pitch step, as a nose key press does: up when braking
        ; forward motion, down when braking reverse.  The pitch damper waits
        ; while it brakes (ab_on), as it does while a nose key is held.
        xor a
        ld (ab_on),a
        ld a,K_AIRBRAKE
        call key_held
        jr z,.nw
        ld a,(speed)
        or a
        jr z,.nw                        ; stopped: nothing to brake
        ld (ab_on),a                    ; (non-zero: braking this frame)
        jp m,.rev
        sub AIRBRAKE_STEP               ; forwards: slower, not past 0
        jr nc,.fwd
        xor a
.fwd:   ld (speed),a
        xor a
        ld (pitch_frac),a               ; whole steps, as the keys
        ld a,(pitch)
        cp PMAX
        jr z,.nw
        inc a                           ; nose up
        ld (pitch),a
        jr .nw
.rev:   add a,AIRBRAKE_STEP             ; backwards: towards 0, not past it
        jr nc,.bk
        xor a
.bk:    ld (speed),a
        xor a
        ld (pitch_frac),a
        ld a,(pitch)
        cp (-PMAX) & $FF
        jr z,.nw
        dec a                           ; nose down
        ld (pitch),a
.nw:
        ; --- yaw: YAW_RATE a frame, but YAW_FINE on the frame a turn key is
        ; first pressed (a tap turns 1 degree: fine control)
        ld a,K_LEFT
        call key_held
        jr z,.ns
        ld de,YAW_RATE
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
        ld de,YAW_RATE
        ld a,K_RIGHT
        call key_pressed
        jr z,.rr
        ld de,YAW_FINE
.rr:    ld hl,(yaw_frac)
        add hl,de
        ld (yaw_frac),hl
.nf:
        ; --- pitch ---
        ld a,K_NOSE_DN
        call key_held
        jr z,.ng
        xor a
        ld (pitch_frac),a               ; keys move in whole steps
        ld a,(pitch)
        cp (-PMAX) & $FF
        jr z,.ng
        dec a
        ld (pitch),a
.ng:    ld a,K_NOSE_UP
        call key_held
        jr z,.nt
        xor a
        ld (pitch_frac),a
        ld a,(pitch)
        cp PMAX
        jr z,.nt
        inc a
        ld (pitch),a
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
        ld hl,pd_count
        dec (hl)
        jr nz,.pdx
        ld (hl),PDAMP_FRAMES
        call pitch_damp
        jr .pdx
.held:  ld a,PDAMP_FRAMES               ; a full interval after letting go
        ld (pd_count),a
.pdx:
        ; --- height ---
        ld a,K_CLIMB
        call key_held
        jr z,.ne
        ld hl,(cam_y)
        ld de,CLIMB_RATE
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
        ld hl,(cam_y)
        ld de,-CLIMB_RATE
        add hl,de
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
        ld a,(yaw)
        call get_sin
        ex de,hl
        ld a,(speed)
        ld h,a
        ld l,0
        call fmul                       ; HL = speed*sin in 1/256 units
        ld ix,cam_x
        call add_pos
        ld a,(yaw)
        add a,64
        call get_sin
        ex de,hl
        ld a,(speed)
        ld h,a
        ld l,0
        call fmul
        ld ix,cam_z
        call add_pos
.moved:
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
        ld hl,(yaw_frac)                ; spin
        ld de,DEAD_SPIN
        add hl,de
        ld (yaw_frac),hl
        ld a,(dead_vy)                  ; fall, faster each frame
        cp DEAD_FALL_MAX
        jr nc,.vy
        inc a
        ld (dead_vy),a
.vy:    ld e,a
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
.down:  ld hl,dead_wait                 ; on the ground: the pause, then
        dec (hl)                        ; GAME OVER
        ret nz
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
pd_count:   db PDAMP_FRAMES             ; frames to the next damping step
ab_on:      db 0                        ; non-zero: the air brake acted this frame
