;==============================================================================
; Z-POLICE - humans to rescue (in the zombie page, after zombie.asm: kept
; mapped in slot 1)
;
; Up to HUMAN_MAX humans, nhumans of them placed at random at start-up (on a
; road, or on a roof low enough to land on).  They stand still, always face
; the player and wave their right arm.  On the city map each is a blue dot,
; flashing 3 frames on, 3 off.
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
;
; Drawing: draw_cell (city page) tests the cell's CELL_HUMAN mark in
; city_map (bit 6, set by hum_flags) and draws them with human_cell: after
; the building on whose roof they stand, so the roof doesn't cover them.  With
; OCCLUSION_CULL the cell goes on the draw list instead (as its city_col
; address, $6000-$6FFF) and is drawn from there.
;==============================================================================

HREC            equ 13
HS_NONE         equ 0               ; human states (+6)
HS_WAIT         equ 1               ; waiting in the city to be rescued
HS_ABOARD       equ 2               ; aboard the VTOL
HS_SAVED        equ 3               ; rescued: off at the landing pad
HS_DEAD         equ 4               ; killed (a rocket blast, a ghost)

        INCLUDE "tables_human.inc"      ; hum_ptr, waving stick men

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

; Draw human IX: feet at its height, facing the viewer, waving
human_draw:
        ld l,(ix+4)
        ld h,(ix+5)
        ld (fig_y),hl
        ld hl,hum_sel
        ld (fig_sel),hl
        ld a,HUMAN_COL
        ld (zspr_rows.col+1),a
        jp fig_draw                     ; (zombie page)

; Frame chooser: the waving frame (every 4 frames), never mirrored
hum_sel:
        xor a
        ld (zface),a
        ld a,(hanim)
        rrca
        rrca
        and 3                           ; frame
        add a,a
        add a,a
        add a,a
        ld hl,zlvl
        add a,(hl)                      ; frame*8 + level
        add a,a
        ld hl,hum_ptr
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (zrow),hl
        jp zspr_rows

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
; Per frame: map dots, and rescues while the craft is landed
;------------------------------------------------------------------------------
human_update:
        ld hl,hanim
        inc (hl)
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
.field: xor a
        ld (hu_moved),a
        ld ix,humans
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
        jr .done
.full:  pop bc
.done:  ld a,(hu_moved)
        or a
        ret z
        call hum_flags                  ; someone moved or boarded
        ld c,1                          ; and redraw the dots that are on
        ld a,(hflash)
        cp HUM_FLASH
        ret nc
        jp hum_dots

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
humans:     ds HUMAN_MAX*HREC
