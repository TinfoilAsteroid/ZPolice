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

        ; (keys: kbd_scan has read them; actions from keys.asm)
        ; --- speed ---
        ld a,K_SPEED_UP
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
.na:    ld a,K_STOP
        call key_held
        jr z,.nw
        xor a
        ld (speed),a
.nw:
        ; --- yaw ---
        ld a,K_LEFT
        call key_held
        jr z,.ns
        ld hl,(yaw_frac)                ; 8.8 heading
        ld de,YAW_RATE
        or a
        sbc hl,de
        ld (yaw_frac),hl
.ns:    ld a,K_RIGHT
        call key_held
        jr z,.nf
        ld hl,(yaw_frac)
        ld de,YAW_RATE
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
        ld de,MAX_Y
        call min_hl_de
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
        ; crashed - restore and stop
        ld hl,old_pos
        ld de,cam_x
        ld bc,10
        ldir
        xor a
        ld (speed),a
        ld a,C_WARN
        out ($FE),a                     ; red border flash
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
