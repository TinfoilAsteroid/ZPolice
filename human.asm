;==============================================================================
; Z-POLICE - humans to rescue (in the zombie page, after zombie.asm: kept
; mapped in slot 1)
;
; Up to HUMAN_MAX humans, nhumans of them placed at random at start-up (on a
; road, or on a roof low enough to land on).  They stand facing the player,
; and wave their right arm while the VTOL is within WAVE_R.  On the city map
; each is a blue dot, flashing 3 frames on, 3 off.
;
; Fleeing (hum_flee): a human on the road (never one on a roof) with a
; monster within FLEE_R runs from the nearest one for FLEE_TIME frames, at
; HUMAN_FLEE units a frame, then looks again.  Its way is picked at random
; of the two that take it away from the monster (along x or along z); if
; that way is blocked (a building, the base, the wall) it takes the other,
; and if both are, it stands.  It only runs along roads.
;
; Base: landed on the landing pad (map code PAD_CODE), the passengers get off
; one every DISEMBARK frames (a second) and are counted as saved.
;
; Rescue: when the craft has landed (speed 0, resting on the road or on the
; roof under it), carries fewer than PASSENGER_MAX and a human stands within
; RESCUE_R at the same height (a roof of the same height, or the road), the
; human runs to it at HUMAN_RUN units a frame and climbs in.  A human on a
; taller or lower roof cannot be reached.
;
; Each human is an HREC-byte record:
;   +0,+1  x  (world units: high byte = cell, as for zombies)
;   +2,+3  z
;   +4,+5  y  height of its feet (roof height, or 0 on the road)
;   +6     state (HS_*): 0 unused, 1 waiting in the city, 2 aboard the
;          VTOL, 3 rescued (off at the landing pad), 4 dead
;   +7,+8  cell (x, z) of its map dot
;   +9     1 = map dot shown
;   +10    hit points left (HUMAN_HP; a rocket blast, weapons.asm)
;   +11,+12  cell (x, z) marked with CELL_HUMAN in city_map ($FF = none)
;   +13    how it's drawn this frame: 0 standing, HUM_WAVING waving, or
;          running (to the VTOL, or fleeing): its way + 1 (1 +z, 2 +x,
;          3 -z, 4 -x, as a zombie's heading + 1)
;   +14    fleeing: frames left (0: not fleeing)
;   +15    fleeing: its way + 1 (as +13)
;
; Drawing: draw_cell (city page) tests the cell's CELL_HUMAN mark in
; city_map (bit 6, set by hum_flags) and draws them with human_cell: after
; the building on whose roof they stand, so the roof doesn't cover them.  With
; OCCLUSION_CULL the cell goes on the draw list instead (as its city_col
; address, $6000-$6FFF) and is drawn from there.
;==============================================================================

HREC            equ 16
HUM_WAVING      equ 5               ; +13: waving (above the 4 ways)
HS_NONE         equ 0               ; human states (+6)
HS_WAIT         equ 1               ; waiting in the city to be rescued
HS_ABOARD       equ 2               ; aboard the VTOL
HS_SAVED        equ 3               ; rescued: off at the landing pad
HS_DEAD         equ 4               ; killed (a rocket blast, a ghost)


;------------------------------------------------------------------------------
; Place nhumans humans at random: on a road cell, or on a roof of level
; no taller than HUMAN_ROOF_MAX, never on the perimeter wall.
;------------------------------------------------------------------------------
human_init:
        xor a
        ld (passengers),a
        ld (saved),a
        ld (hanim),a
        ld (hflash),a
        ld a,DISEMBARK
        ld (dis_wait),a
        xor a
        ld ix,humans
        ld b,HUMAN_MAX
        ld de,HREC
.clr:   ld (ix+6),0
        ld (ix+9),0
        ld (ix+14),0                    ; not fleeing
        ld (ix+11),$FF                  ; no cell marked
        add ix,de
        djnz .clr
        ld c,~CELL_HUMAN & $FF          ; no human marks in city_map (a new
        call map_mask                   ; game reuses it; zombie page)
        ld ix,humans
        ld a,(nhumans)
        ld b,a
.lp:    push bc
.try:   call zrand                      ; (zombie page)
        ld a,l
        and GRID-1
        jr z,.try                       ; not on the wall (cell 0 or GRID-1)
        cp GRID-1
        jr z,.try
        ld (ix+1),a
        ld a,h
        and GRID-1
        jr z,.try
        cp GRID-1
        jr z,.try
        ld (ix+3),a
        call hum_map                    ; A = map byte
        cp PAD_CODE
        jr nc,.try                      ; not on the base (pad, terrace)
        call bld_height                 ; feet: the roof, or 0 on the road
        ld (ix+4),l
        ld (ix+5),h
        ld de,HUMAN_ROOF_MAX+1
        or a
        sbc hl,de
        jr nc,.try                      ; roof taller than HUMAN_ROOF_MAX
        call zrand                      ; somewhere in the cell
        ld a,l
        and 127
        add a,64
        ld (ix+0),a
        ld a,h
        and 127
        add a,64
        ld (ix+2),a
        ld (ix+6),HS_WAIT               ; waiting
        ld (ix+10),HUMAN_HP
        ld de,HREC
        add ix,de
        pop bc
        djnz .lp
        jp hum_flags

; A = the cell code (CELL_CODE bits) of human IX's cell
hum_map:
        call hum_map_ptr
        ld a,(hl)
        and CELL_CODE
        ret

; HL -> city_map byte of human IX's cell.  Preserves BC.
hum_map_ptr:
        ld l,(ix+3)
        ld h,0
        ROWOFS
        ld a,(ix+1)
        add hl,a
        ld de,city_map
        add hl,de
        ret

; Mark the waiting humans' cells in city_map (CELL_HUMAN, bit 6): first take
; the mark off every record's marked cell (+11, +12), then mark the cell of
; each human still waiting and remember it.  Called whenever humans are
; placed, move, board or die.
hum_flags:
        ld ix,humans
        ld b,HUMAN_MAX
.clr:   ld a,(ix+11)
        cp GRID
        jr nc,.cn                       ; none marked
        ld l,(ix+12)
        ld h,0
        ROWOFS
        add hl,a
        ld de,city_map
        add hl,de
        res CELL_HUMAN_B,(hl)
        ld (ix+11),$FF
.cn:    ld de,HREC
        add ix,de
        djnz .clr
        ld ix,humans
        ld b,HUMAN_MAX
.set:   ld a,(ix+6)
        cp HS_WAIT
        jr nz,.sn                       ; not in the city: no mark
        call hum_map_ptr
        set CELL_HUMAN_B,(hl)
        ld a,(ix+1)
        ld (ix+11),a
        ld a,(ix+3)
        ld (ix+12),a
.sn:    ld de,HREC
        add ix,de
        djnz .set
        ret

;------------------------------------------------------------------------------
; Draw the humans in a cell: HL -> its city_map byte.  Needs the city page.
;------------------------------------------------------------------------------
human_cell:
        bit CELL_HUMAN_B,(hl)
        ret z
        ld de,city_map
        or a
        sbc hl,de
        ld (hc_idx),hl
        push ix
        ld ix,humans
        ld b,HUMAN_MAX
.lp:    push bc
        ld a,(ix+6)
        cp HS_WAIT
        jr nz,.nx
        ld l,(ix+3)                     ; in this cell?
        ld h,0
        ROWOFS
        ld a,(ix+1)
        add hl,a
        ld de,(hc_idx)
        or a
        sbc hl,de
        jr nz,.nx
        call human_draw
.nx:    ld de,HREC
        add ix,de
        pop bc
        djnz .lp
        pop ix
        ret

; Draw human IX: feet at its height, waving at the viewer, or running to
; the VTOL
human_draw:
        ld l,(ix+4)
        ld h,(ix+5)
        ld (fig_y),hl
        ld hl,hum_sel
        ld (fig_sel),hl
        xor a
        ld (spr_col),a                  ; (its own colours)
        ld (fig_mon),a                  ; (not a monster)
        jp fig_draw                     ; (zombie page)

; Frame chooser: standing (facing the viewer), waving (a new frame every 4
; frames, facing the viewer), or running (every 2), facing its way relative
; to the view (as a zombie)
hum_sel:
        ld a,(ix+13)
        or a
        jr nz,.move
        ld (zface),a                    ; (A = 0: not mirrored)
        ld (fig_frame),a
        ld a,ANIM_HUMAN_STAND
        ld (fig_anim),a
        ret
.move:  cp HUM_WAVING
        jr nz,.run
        xor a
        ld (zface),a
        ld a,ANIM_HUMAN_WAVE
        ld (fig_anim),a
        ld a,(hanim)
        srl a
        srl a
        ld (fig_frame),a
        ret
.run:   dec a                           ; its way 0-3: * 64, less the yaw
        rrca
        rrca
        ld hl,yaw
        sub (hl)
        add a,32
        rlca
        rlca
        and 3
        ld hl,face_tab                  ; (zombie page)
        add hl,a
        ld c,(hl)
        ld a,c
        and 3
        add a,ANIM_HUMAN_RUN_FRONT
        ld (fig_anim),a
        xor a
        bit 7,c
        jr z,.m
        ld a,2
.m:     ld (zface),a
        ld a,(hanim)
        srl a
        ld (fig_frame),a
        ret
        ASSERT ANIM_HUMAN_RUN_SIDE == ANIM_HUMAN_RUN_FRONT+1 && ANIM_HUMAN_RUN_REAR == ANIM_HUMAN_RUN_FRONT+2

;------------------------------------------------------------------------------
; The level complete (level_complete_screen): everyone aboard is rescued at
; once, off the VTOL and counted as saved (before the salvage is worked out)
;------------------------------------------------------------------------------
hum_unload_all:
        ld ix,humans
        ld b,HUMAN_MAX
        ld de,HREC
.lp:    ld a,(ix+6)
        cp HS_ABOARD
        jr nz,.nx
        ld (ix+6),HS_SAVED
        ld hl,saved
        inc (hl)
.nx:    add ix,de
        djnz .lp
        xor a
        ld (passengers),a
        ret

;------------------------------------------------------------------------------
; Per frame: map dots, rescues while the craft is landed, fleeing from the
; monsters and waving at the VTOL
;------------------------------------------------------------------------------
human_update:
        xor a
        ld (hu_moved),a
        ld hl,hanim
        inc (hl)
        call .upd
        call hum_flee
        ld a,(hu_moved)
        or a
        ret z
        call hum_flags                  ; someone moved to another cell, or
        ld c,1                          ; boarded: redraw the dots that are on
        ld a,(hflash)
        cp HUM_FLASH
        ret nc
        jp hum_dots
.upd:   ld ix,humans                    ; nobody running yet this frame
        ld b,HUMAN_MAX
        ld de,HREC
.rc:    ld (ix+13),0
        add ix,de
        djnz .rc
        ; map dots: on for HUM_FLASH frames, off for HUM_FLASH (1: every
        ; other frame, as the VTOL's dot, map_player)
        ld hl,hflash
        ld a,(hl)
        inc a
        cp 2*HUM_FLASH
        jr c,.f
        xor a
.f:     ld (hl),a
        or a
        ld c,1
        jr z,.dots                      ; phase 0: show
        cp HUM_FLASH
        ld c,0
        call z,hum_dots                 ; phase HUM_FLASH: hide
        jr .resc
.dots:  call hum_dots
.resc:  ; landed?  speed 0, resting on the floor under the craft (and
        ; not a wreck: nobody runs to it or gets off)
        call vtol_landed
        jr nz,.notpad
        call cam_cell_ptr
        ld a,(hl)
        and CELL_CODE
        ld (hu_cell),a
        call bld_height
        ld (hu_floor),hl                ; height of the floor under it
        ld a,(hu_cell)
        cp PAD_CODE
        jr nz,.field
        ; on the base pad: passengers get off, one every DISEMBARK frames
        ld a,(passengers)
        or a
        jr z,.notpad
        ld hl,dis_wait
        dec (hl)
        ret nz
        ld (hl),DISEMBARK
        ld hl,passengers
        dec (hl)
        ld hl,saved
        inc (hl)
        ld ix,humans                    ; the first aboard is rescued
        ld b,HUMAN_MAX
        ld de,HREC
.off:   ld a,(ix+6)
        cp HS_ABOARD
        jr z,.saved
        add ix,de
        djnz .off
        ret
.saved: ld (ix+6),HS_SAVED
        ret
.notpad:
        ld a,DISEMBARK                  ; the first gets off a second after
        ld (dis_wait),a                 ; landing
        ret
.field: ld ix,humans
        ld b,HUMAN_MAX
.lp:    push bc
        ld a,(passengers)
        cp PASSENGER_MAX
        jr nc,.full                     ; the craft is full: nobody runs
        ld a,(ix+6)
        cp HS_WAIT
        jr nz,.nx
        call hum_rescue
.nx:    ld de,HREC
        add ix,de
        pop bc
        djnz .lp
        ret
.full:  pop bc
        ret

;------------------------------------------------------------------------------
; Each waiting human not running to the VTOL: fleeing (on the road, from a
; monster within FLEE_R), else waving if the VTOL is within WAVE_R, else
; standing.  Sets +13 (how it's drawn) and moves the fleeing.
;------------------------------------------------------------------------------
hum_flee:
        ld ix,humans
        ld b,HUMAN_MAX
.lp:    push bc
        ld a,(ix+6)
        cp HS_WAIT
        jp nz,.nx
        ld a,(ix+13)
        or a
        jr z,.free
        ld (ix+14),0                    ; running to the VTOL: not fleeing
        jp .nx
.free:  ld a,(ix+14)
        or a
        jr z,.look
        dec (ix+14)                     ; fleeing: on its way
        ld a,(ix+15)
        call hum_step
        jr nc,.ran
        ld (ix+14),0                    ; blocked: stops (looks again)
        jr .wave
.look:  ld a,(ix+4)                     ; above the road: never flees
        or (ix+5)
        jr nz,.wave
        ld a,(hanim)                    ; look every FLEE_EVERY frames,
        add a,b                         ; the humans in turn
        and FLEE_EVERY-1
        jr nz,.wave
        call hum_near
        jr c,.wave                      ; no monster near
        ld a,(hu_dx+1)                  ; the ways away from it: along x
        rla
        ld a,2                          ; +x
        jr nc,.wx
        ld a,4                          ; -x
.wx:    ld c,a
        ld a,(hu_dz+1)                  ; along z
        rla
        ld a,1                          ; +z
        jr nc,.wz
        ld a,3                          ; -z
.wz:    ld e,a
        call zrand                      ; one at random (keeps C, E)
        bit 0,l
        jr z,.pick
        ld a,c                          ; swap: C the one tried first,
        ld c,e                          ; E the other
        ld e,a
.pick:  ld (ix+14),FLEE_TIME
        ld a,c
        ld (ix+15),a
        push de
        call hum_step                   ; (keeps BC)
        pop de
        jr nc,.ran
        ld a,e                          ; blocked: the other way
        ld (ix+15),a
        call hum_step
        jr nc,.ran
        ld (ix+14),0                    ; both blocked: stands
        jr .wave
.ran:   ld a,(ix+15)                    ; drawn running its way
        ld (ix+13),a
        jr .nx
.wave:  ld hl,(cam_x+1)                 ; the VTOL within WAVE_R: waves
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        call abs_hl
        ld de,WAVE_R
        or a
        sbc hl,de
        jr nc,.nx
        ld hl,(cam_z+1)
        ld e,(ix+2)
        ld d,(ix+3)
        or a
        sbc hl,de
        call abs_hl
        ld de,WAVE_R
        or a
        sbc hl,de
        jr nc,.nx
        ld (ix+13),HUM_WAVING
.nx:    ld de,HREC
        add ix,de
        pop bc
        dec b
        jp nz,.lp
        ret

; The nearest active monster to human IX within FLEE_R (along x and z):
; carry clear and hu_dx, hu_dz = the human less the monster; carry set if
; none.  Keeps IX.
hum_near:
        ld hl,FLEE_R
        ld (hu_dist),hl                 ; the nearest so far
        xor a
        ld (hn_found),a
        ld iy,zombies
        ld b,NMON
.lp:    bit 0,(iy+10)
        jr z,.nx                        ; not in play
        ld a,(iy+1)                     ; quick: within a cell (x, z)?
        sub (ix+1)
        inc a
        cp 3
        jr nc,.nx
        ld a,(iy+3)
        sub (ix+3)
        inc a
        cp 3
        jr nc,.nx
        ld l,(ix+0)
        ld h,(ix+1)
        ld e,(iy+0)
        ld d,(iy+1)
        or a
        sbc hl,de
        ld (hn_dx),hl
        call abs_hl
        push hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld e,(iy+2)
        ld d,(iy+3)
        or a
        sbc hl,de
        ld (hn_dz),hl
        call abs_hl                     ; HL = |dz|
        pop de                          ; DE = |dx|
        or a
        sbc hl,de
        add hl,de
        jr nc,.mx
        ex de,hl                        ; HL = the larger
.mx:    ld de,(hu_dist)
        or a
        sbc hl,de
        jr nc,.nx                       ; not nearer
        add hl,de
        ld (hu_dist),hl
        ld hl,(hn_dx)
        ld (hu_dx),hl
        ld hl,(hn_dz)
        ld (hu_dz),hl
        ld a,1
        ld (hn_found),a
.nx:    ld de,ZREC
        add iy,de
        djnz .lp
        ld a,(hn_found)
        sub 1                           ; carry if none
        ret

; Move human IX HUMAN_FLEE units its way A (1 +z, 2 +x, 3 -z, 4 -x), if
; that is on a road: carry set (and not moved) if not.  hu_moved = 1 if it
; is in another cell now.  Keeps BC, IX.
hum_step:
        ld l,(ix+0)                     ; where it was
        ld h,(ix+1)
        ld (hs_x),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld (hs_z),hl
        dec a                           ; 0 +z, 1 +x, 2 -z, 3 -x
        ld de,HUMAN_FLEE
        bit 1,a
        jr z,.pos
        ld de,-HUMAN_FLEE
.pos:   rra
        jr c,.x
        add hl,de                       ; z
        ld (ix+2),l
        ld (ix+3),h
        jr .chk
.x:     ld hl,(hs_x)
        add hl,de
        ld (ix+0),l
        ld (ix+1),h
.chk:   ld a,(ix+1)                     ; not on the wall, nor past it
        dec a
        cp GRID-2
        jr nc,.no
        ld a,(ix+3)
        dec a
        cp GRID-2
        jr nc,.no
        call hum_map                    ; (keeps BC)
        cp PAD_CODE
        jr nc,.no                       ; the base
        call bld_height
        ld a,h
        or l
        jr nz,.no                       ; a building
        ld a,(hs_x+1)                   ; another cell?
        cp (ix+1)
        jr nz,.cell
        ld a,(hs_z+1)
        cp (ix+3)
        ret z                           ; (carry clear)
.cell:  ld a,1
        ld (hu_moved),a
        or a
        ret
.no:    ld hl,(hs_x)                    ; back where it was
        ld (ix+0),l
        ld (ix+1),h
        ld hl,(hs_z)
        ld (ix+2),l
        ld (ix+3),h
        scf
        ret

; Human IX: if at the craft's height and within RESCUE_R, run to it (and
; board when there)
hum_rescue:
        ld l,(ix+4)                     ; same height as the floor under the
        ld h,(ix+5)                     ; craft?
        ld de,(hu_floor)
        or a
        sbc hl,de
        ret nz
        ld hl,(cam_x+1)                 ; dx, dz to the craft
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        ld (hu_dx),hl
        ld hl,(cam_z+1)
        ld e,(ix+2)
        ld d,(ix+3)
        or a
        sbc hl,de
        ld (hu_dz),hl
        ; distance ~ max + 3/8 min of |dx|, |dz|
        call abs_hl
        ex de,hl
        ld hl,(hu_dx)
        call abs_hl                     ; HL = |dx|, DE = |dz|
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
        add hl,de                       ; 3 min
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                            ; 3/8 min
        pop de
        add hl,de
        ld (hu_dist),hl
        ld de,RESCUE_R+1
        or a
        sbc hl,de
        ret nc                          ; too far
        ld a,1
        ld (hu_moved),a
        ; its way, for drawing it running: along the larger of |dx|, |dz|
        ld hl,(hu_dx)
        call abs_hl
        ex de,hl
        ld hl,(hu_dz)
        call abs_hl                     ; HL = |dz|, DE = |dx|
        or a
        sbc hl,de
        ld a,(hu_dx+1)
        jr c,.wx                        ; |dx| the larger
        ld a,(hu_dz+1)
        rla
        ld a,1                          ; +z
        jr nc,.wd
        ld a,3                          ; -z
        jr .wd
.wx:    rla
        ld a,2                          ; +x
        jr nc,.wd
        ld a,4                          ; -x
.wd:    ld (ix+13),a
        ld hl,(hu_dist)
        ld de,HUMAN_RUN+1
        or a
        sbc hl,de
        jr c,.board                     ; reaches the craft this frame
        ; step HUMAN_RUN towards it: (dx, dz) * HUMAN_RUN / dist
        ld de,(hu_dist)
        ld hl,HUMAN_RUN*256
        call udiv16                     ; HL = S7.8 fraction
        ld (hu_t),hl
        ld hl,(hu_dx)
        ld de,(hu_t)
        call fmul
        ld e,(ix+0)
        ld d,(ix+1)
        add hl,de
        ld (ix+0),l
        ld (ix+1),h
        ld hl,(hu_dz)
        ld de,(hu_t)
        call fmul
        ld e,(ix+2)
        ld d,(ix+3)
        add hl,de
        ld (ix+2),l
        ld (ix+3),h
        ret
.board: ld c,0                          ; in: dot off, aboard, one more
        call hum_dot
        ld (ix+6),HS_ABOARD
        ld hl,passengers
        inc (hl)
        ret

; HL / DE -> HL, unsigned 16-bit
udiv16:
        ld a,h
        ld c,l
        ld hl,0
        ld b,16
.lp:    sla c
        rla
        adc hl,hl
        sbc hl,de
        jr nc,.ok
        add hl,de
        dec c                           ; (bit stays 0: undo the inc below)
.ok:    inc c
        djnz .lp
        ld h,a
        ld l,c
        ret

;==============================================================================
; Human data
;==============================================================================
nhumans:    db HUMANS_INIT              ; humans placed at start (<= HUMAN_MAX)
passengers: db 0                        ; humans on board (<= PASSENGER_MAX)
saved:      db 0                        ; humans delivered to the base
dis_wait:   db DISEMBARK                ; frames to the next one getting off
hu_cell:    db 0                        ; map byte under the craft
hanim:      db 0                        ; waving animation clock
hflash:     db 0                        ; map dot flash phase 0..2*HUM_FLASH-1
hc_idx:     dw 0
hu_floor:   dw 0
hu_moved:   db 0
hu_dx:      dw 0
hu_dz:      dw 0
hu_dist:    dw 0
hu_t:       dw 0
hn_dx:      dw 0                        ; hum_near: this monster's dx, dz
hn_dz:      dw 0
hn_found:   db 0
hs_x:       dw 0                        ; hum_step: where it was
hs_z:       dw 0
humans:     ds HUMAN_MAX*HREC
