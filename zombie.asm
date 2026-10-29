;==============================================================================
; Z-POLICE - zombie page (8K page PAGE_ZOMBIE, mapped at $2000 in MMU slot 1)
;
; Placeholder zombies: Layer 2 stick-man silhouettes walking the streets.
; The page stays mapped at $2000 the whole time (slot 0 is used for paging
; Layer 2 sections, slot 7 for the other code pages), so the city page can
; call in here while it draws.
;
; Each zombie is a ZREC-byte record:
;   +0,+1  x  8.8 fixed point in cell units (high byte = cell, low = fraction;
;             the same as world units, one cell = 256)
;   +2,+3  z  likewise
;   +4     heading 0 = +z, 1 = +x, 2 = -z, 3 = -x  (yaw angle = heading*64;
;             heading+1 turns right, heading+3 turns left)
;   +5     walk animation phase 0..3
;   +6     step accumulator: fraction of a world unit (4 bits)
;   +7     wait: frames left standing still (0 = walking)
;   +8,+9  cell (x, z) of the last turn decision ($FF = none)
;   +10    active: 1 = in play, 0 = gone (not moved, linked or drawn)
;   +11    frames until this zombie's next decision check
;   +12,+13  cell (x, z) of its blip on the street map
;   +14    1 = blip plotted
;   +15    type: 0 = zombie, 1 = fast zombie (walks at twice the speed),
;          ZT_GHOUL (a special: 5x, half height), ZT_GHOST, ZT_BANSHEE
;   +16    mode: 0 = walking, 1 = going for a base tile, 2 = attacking it
;   +17    frames to its next hit on the tile
;   +18    hit points left (ZHP, ZHP_FAST; weapons.asm zdamage)
;   +19,+20  cell (x, z) marked with CELL_ZOMBIE in city_map ($FF = none)
;   +21,+22  height of its feet (0 for zombies; special monsters fly)
;   +23..+30 special monsters' own fields (specials.asm)
; Records 0..NZOMB-1 are the zombies, NZOMB..NMON-1 the special monsters
; (specials.asm), which share the drawing, cell marks, map blips and weapon
; hits; their type (+15) says which.
; zatk_flags (one byte per zombie, by index): TRUE while it attacks a base
; tile, when its map dot is red; FALSE again once the tile is destroyed.
;
; The base: at junctions a zombie leans towards the road that points at the
; landing pad (zbias_t, from the level).  A base tile (terrace or pad) in its
; way isn't avoided: it walks up to ATTACK_R from it and hits it every
; ZHIT_FRAMES frames.  A destroyed terrace tile becomes road and the zombie
; walks on; the pad destroyed sets game_over.
;
; Street map blips: zblip / zblip_off (map.asm) are called on the zombie's
; decision-check frames.  Call zblip_off for a zombie before making it gone.
;
; Decisions are staggered: each active zombie only checks for junctions and
; obstacles once every zsteps frames, with the zombies' check frames spread
; out so only about NZOMB/zsteps of them check on any one frame.  In between
; they just walk, so the look-ahead (zlook) covers zsteps frames of walking
; plus a margin: ZMARGIN + zsteps*zspeed/16.
;
; Movement (zmove), every frame:
;   * Standing still: count the wait down and do nothing else.
;   * Not this zombie's check frame: step forwards (see the last point).
;   * Junctions: once per cell, when the zombie is 0.25-0.75 of the way
;     through the cell along its heading, look for a road (street cell) to
;     the left and to the right.  Left is tested first: if there is a road,
;     turn left at random (1 in 2); if not taken, the same for the right.
;     The cell is then marked as decided, so it isn't tested again until the
;     zombie has been somewhere else.
;   * Blocked (building or map edge within zlook ahead): turn left if there
;     is a road there, else right; otherwise turn round and stand still for
;     ZWAIT frames before testing anything again.
;   * Otherwise step forwards zspeed/16 world units (the remainder is kept,
;     so slow speeds still move smoothly on average).
;
; Zombies are only ever on street (empty) cells.  They are drawn by the city
; traversal when it reaches their cell (draw_cell jumps to zombie_cell for
; empty cells), so the painter's algorithm hides them behind nearer buildings.
; A cell holding zombies has bit 7 (CELL_ZOMBIE) of its city_map byte set,
; by zflags every frame; zombie_cell then searches the records for them.
;
; Sprites (tables_zombie.inc, generated): 8 scales from 1x4 to 8x16 pixels,
; forward and left facings, 4 walk frames.  Rear and right are the mirrored
; forward and left.  One byte per row, bit 7 = leftmost pixel.
;==============================================================================

NZOMB           equ 30          ; zombie records: the most in a wave
NSPEC           equ 8           ; most special monsters (5 ghosts, banshees)
NMON            equ NZOMB+NSPEC ; records: zombies, then special monsters
ZREC            equ 31          ; bytes per record
ZT_FAST         equ 1           ; +15: fast zombie
ZT_GHOUL        equ 2           ; +15: a ghoul: a special monster that walks
                                ; as a zombie (zmove), half height, 5x speed
ZT_GHOST        equ 3           ; +15: a ghost (specials.asm); types from
ZT_BANSHEE      equ 4           ; here on fly (specials.asm moves them)
ZHP             equ 5           ; hit points: a zombie (level 1)
ZHP_FAST        equ 4           ; and a fast zombie
GHOUL_HP        equ ZHP         ; and a ghoul
ZSPEED_INIT     equ 10          ; starting zspeed: 0.63 units (4.9 cm) per
                                ; frame, ~0.7 m/s at 14 fps
ZSTEPS_INIT     equ 10          ; starting zsteps: decide every 10 frames
ZMARGIN         equ 16          ; keep at least this far from walls: 1.25 m
ZWAIT           equ 100         ; frames to stand still when stuck
ZOMBIE_H        equ 26          ; height: 2 m (the same as the hit box, ZHIT_H)
GHOUL_H         equ ZOMBIE_H/2  ; a ghoul's height: 1 m
        ASSERT ZSPEED_INIT*5+15 < 256   ; a ghoul's step (zcalc_step) fits

        INCLUDE "tables_zombie.inc"     ; sprites, sizes, bitrev

;------------------------------------------------------------------------------
; Seed NZOMB zombies at random street positions, away from building walls
;------------------------------------------------------------------------------
zombie_init:
        ld c,~CELL_ZOMBIE & $FF         ; no zombie marks in city_map (a new
        call map_mask                   ; game reuses it)
        ; (zseed: seeded at power-on, stirred by the menu every frame)
        ld a,(level)                    ; junction bias towards the pad:
        add a,a                         ; min(ZBIAS_MAX, ZBIAS_BASE +
        add a,ZBIAS_BASE                ; ZBIAS_STEP * level) percent
        cp ZBIAS_MAX
        jr c,.bp
        ld a,ZBIAS_MAX
.bp:    ld d,a                          ; as a 0..255 threshold: pct*41/16
        ld e,41
        mul d,e
        ld b,4
        bsrl de,b
        ld a,e
        ld (zbias_t),a
        ld ix,zombies                   ; no zombies, no cells marked
        ld b,NZOMB
        ld de,ZREC
.off:   ld (ix+10),0
        ld (ix+14),0
        ld (ix+19),$FF
        add ix,de
        djnz .off
        ; fall through: the first wave

;------------------------------------------------------------------------------
; A wave: the level's LV_ZOMBIES zombies (level_cur; at most NZOMB), LV_FAST
; of them fast, at random street positions; the other zombie records stay
; inactive.  zombie_update calls it again when a wave is wiped out.  (The
; records' cell marks, +19 / +20, are left to zflags: a zombie killed this
; frame may still have one.)
;------------------------------------------------------------------------------
zombie_wave:
        ld a,(level_cur+LV_FAST)
        ld (zi_fast),a
        ld a,(level_cur+LV_ZOMBIES)
        cp NZOMB+1
        jr c,.n
        ld a,NZOMB
.n:     ld (zi_left),a
        ld ix,zombies
        ld b,NZOMB
        ld c,1                          ; first check frame, spread 1..zsteps
.lp:    push bc
        ld a,(zi_left)                  ; this wave's zombies placed?
        or a
        jr nz,.one
        ld (ix+10),0                    ; the rest: inactive
        pop bc
        jp .nx
.one:   dec a
        ld (zi_left),a
        call zplace
        ld a,NZOMB                      ; not attacking
        sub b
        ld hl,zatk_flags
        add hl,a
        ld (hl),FALSE
        ld a,(zi_fast)                  ; zi_fast are fast zombies
        or a
        jr z,.typ
        dec a
        ld (zi_fast),a
        ld (ix+15),ZT_FAST
        ld (ix+18),ZHP_FAST
.typ:
        call zblip
        pop bc
        ld (ix+11),c                    ; first decision check
        ld a,(zsteps)
        cp c
        jr nz,.nc
        ld c,0                          ; wrap after zsteps
.nc:    inc c
.nx:    ld de,ZREC
        add ix,de
        dec b
        jp nz,.lp
        jp zflags

; Record IX: a zombie (type 0, ZHP) at a random street position, walking a
; random heading, active; no blip yet (the caller sets the type, then
; zblip), check frame and attack flag left to the caller.  Preserves BC.
zplace:
.try:   call zrand
        ld a,l
        and GRID-1
        ld (ix+1),a                     ; x cell
        ld a,h
        and GRID-1
        ld (ix+3),a                     ; z cell
        call zmap_ptr
        ld a,(hl)
        and CELL_CODE
        jr nz,.try                      ; building: pick again
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
        and 3
        ld (ix+4),a
        ld a,h
        and 3
        ld (ix+5),a
        xor a
        ld (ix+6),a                     ; step accumulator
        ld (ix+7),a                     ; walking
        dec a
        ld (ix+8),a                     ; no decision cell yet
        ld (ix+9),a
        ld (ix+10),1                    ; active
        ld (ix+14),0                    ; no blip yet
        ld (ix+16),0                    ; walking
        ld (ix+17),0
        ld (ix+21),0                    ; on the ground
        ld (ix+22),0
        ld (ix+15),0                    ; a zombie
        ld (ix+18),ZHP
        ret

;------------------------------------------------------------------------------
; Per frame: walk every zombie and mark the cells they stand in.  Call after
; setup_frame (uses cos_p/sin_p for the zombie height vector).
;------------------------------------------------------------------------------
zombie_update:
        ; a wave wiped out (no monster record active: zombies, ghosts and
        ; banshees, a dying special still counting until it has faded)?
        ; The next wave, or with none left the level is complete
        ; (level_done; main_loop)
        ld ix,zombies
        ld b,NMON
        ld de,ZREC
.cnt:   bit 0,(ix+10)
        jr nz,.alive
        add ix,de
        djnz .cnt
        ld a,(level_cur+LV_WAVES)
        ld hl,wave_number
        cp (hl)
        jr z,.done
        jr c,.done
        inc (hl)                        ; the next wave
        ld a,1
        ld (zwave_new),a                ; (spec_update: banshees on even ones)
        call zombie_wave
        jr .alive
.done:  ld a,1
        ld (level_done),a
.alive:
        ld hl,zanim
        inc (hl)
        ld hl,ZOMBIE_H                  ; height vector (0, H cosP, H sinP)
        ld de,(cos_p)
        call fmul
        ld (zh_y),hl
        ld hl,ZOMBIE_H
        ld de,(sin_p)
        call fmul
        ld (zh_z),hl
        ld a,(zsteps)                   ; look-ahead: walking between checks
        ld e,a                          ; plus the wall margin
        ld a,(zspeed)
        ld d,a
        mul d,e
        ld b,4
        bsrl de,b
        ld hl,ZMARGIN
        add hl,de
        ld (zlook),hl
        add hl,de                       ; fast zombies walk twice as far
        ld (zlook_fast),hl              ; between checks
        add hl,de                       ; ghouls five times
        add hl,de
        add hl,de
        ld (zlook_ghoul),hl
        ld ix,zombies                   ; the zombies, and ghouls in the
        ld b,NMON                       ; special records
.mv:    push bc
        ld a,NMON                       ; this record's index (zatk_flags)
        sub b
        ld (zcur_i),a
        bit 0,(ix+10)
        jr z,.mn                        ; active ones only
        ld a,(ix+15)
        cp ZT_GHOST
        call c,zmove                    ; (not the fliers: specials.asm)
.mn:    pop bc
        ld de,ZREC
        add ix,de
        djnz .mv
        ; fall through

; Mark the zombies' cells in city_map (CELL_ZOMBIE, bit 7): first take the
; mark off every record's marked cell (+19, +20), then mark the cell of each
; active zombie and remember it.  Two passes, so two zombies sharing a cell
; keep it marked, and one killed since the last pass loses its mark.
zflags:
        ld ix,zombies
        ld b,NMON
.clr:   ld a,(ix+19)
        cp GRID
        jr nc,.cn                       ; none marked
        ld l,(ix+20)
        ld h,0
        ROWOFS
        add hl,a
        ld de,city_map
        add hl,de
        res CELL_ZOMBIE_B,(hl)
        ld (ix+19),$FF
.cn:    ld de,ZREC
        add ix,de
        djnz .clr
        ld ix,zombies
        ld b,NMON
.set:   bit 0,(ix+10)
        jr z,.sn                        ; gone: no mark
        call zmap_ptr
        set CELL_ZOMBIE_B,(hl)
        ld a,(ix+1)
        ld (ix+19),a
        ld a,(ix+3)
        ld (ix+20),a
.sn:    ld de,ZREC
        add ix,de
        djnz .set
        ret

; City_map bytes AND= C, all of them (clears marks at a new game)
map_mask:
        ld hl,city_map
        ld d,GRID*GRID/256
        ld b,0
.lp:    ld a,(hl)
        and c
        ld (hl),a
        inc hl
        djnz .lp
        dec d
        jr nz,.lp
        ret

; Move zombie IX for one frame (see the header for the rules)
zmove:
        ld a,(ix+16)
        or a
        jp nz,zattack                   ; going for / attacking a base tile
        ld a,(ix+7)
        or a
        jr z,.go
        dec (ix+7)                      ; standing still
        ret
.go:    call zcalc_step
        dec (ix+11)
        jr nz,.step                     ; not this zombie's check frame
        ld a,(zsteps)
        ld (ix+11),a
        call zblip                      ; move its map blip
        call zjunction
        ld e,(ix+4)
        ld hl,(zlook)
        ld a,(ix+15)
        cp ZT_FAST
        jr c,.lk
        ld hl,(zlook_fast)
        jr z,.lk
        ld hl,(zlook_ghoul)
.lk:    call ztest
        jr nz,.blocked
.step:  ld a,(zstep)                    ; step forwards
        jp zforward
.blocked:
        ld a,(ix+4)                     ; what is ahead: the base?
        call zside
        call zbase
        jr nz,.side
        ld (ix+16),1                    ; go for it
        ld (ix+17),ZHIT_FRAMES
        ret
.side:  ld c,0                          ; roads to the left and right
        ld a,(ix+4)
        add a,3
        call zroad
        ld a,(ix+4)
        inc a
        call zroad
        ld a,c
        or a
        jr z,.dead
        call zrand                      ; biased: the one towards the pad
        ld a,(zbias_t)
        ld b,a
        ld a,l
        cp b
        jr nc,.old
        ld a,c
        call zbest
        jp zturn
.old:   ld a,(ix+4)                     ; otherwise left if there is one,
        add a,3                         ; else right
        and 3
        call zhas
        ld a,(ix+4)
        jr z,.rt
        add a,3
        jp zturn
.rt:    inc a
        jp zturn
.dead:  ld a,(ix+4)                     ; dead end: turn round and wait
        xor 2
        ld (ix+4),a
        ld (ix+7),ZWAIT
        ret

; This frame's distance for zombie IX (zspeed, twice for a fast zombie,
; five times for a ghoul), 4.4 fixed with the fraction kept -> zstep.
; Keeps B.
zcalc_step:
        ld a,(ix+15)
        cp ZT_FAST
        ld a,(zspeed)                   ; distance this frame, 4.4 fixed
        jr c,.reg
        ld c,a
        jr z,.fast
        add a,a                         ; a ghoul: five times the speed
        add a,a
        add a,c
        jr .reg
.fast:  add a,a                         ; fast zombie: twice the speed
.reg:   add a,(ix+6)
        ld c,a
        and 15
        ld (ix+6),a                     ; keep the fraction
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and 15
        ld (zstep),a
        ret

; Move zombie IX A units along its heading
zforward:
        ld l,a
        ld h,0
        ld e,(ix+4)
        bit 1,e
        call nz,neg_hl
        bit 0,e
        jr nz,.sx
        ld c,(ix+2)
        ld b,(ix+3)
        add hl,bc
        ld (ix+2),l
        ld (ix+3),h
        ret
.sx:    ld c,(ix+0)
        ld b,(ix+1)
        add hl,bc
        ld (ix+0),l
        ld (ix+1),h
        ret

; Zombie IX going for (mode 1) or attacking (mode 2) the base tile ahead
zattack:
        ld a,(ix+4)
        call zside                      ; still a base tile ahead?
        call zbase
        jr nz,.gone
        call zedge                      ; distance to its edge
        sub ATTACK_R
        jr z,.at
        jr c,.at
        ld b,a                          ; still to go: walk on, no further
        call zcalc_step
        ld a,(zstep)
        cp b
        jr c,.mv
        ld a,b
.mv:    jp zforward
.at:    ld a,(ix+16)
        cp 2
        jr z,.hit
        ld (ix+16),2                    ; in reach: attack
        call zflag                      ; attack flag on, map dot red
        ld (hl),TRUE
        call zblip_red                  ; (map.asm)
.hit:   dec (ix+17)
        ret nz
        ld (ix+17),ZHIT_FRAMES
        jp base_hit
.gone:  ld a,(ix+16)
        ld (ix+16),0                    ; destroyed: walk on (towards the pad)
        cp 2
        ret nz                          ; (was only on its way)
        call zflag                      ; attack flag off, map dot back to
        ld (hl),FALSE                   ; its usual shade
        jp zblip

; HL -> zatk_flags entry of the zombie being moved (zcur_i)
zflag:
        ld a,(zcur_i)
        ld hl,zatk_flags
        add hl,a
        ret

; A = map code: Z if it is a base tile (the pad or the terrace)
zbase:
        cp PAD_CODE
        jr c,.no
        cp TERRACE_CODE+1
        jr nc,.no
        cp a                            ; Z
        ret
.no:    or 1                            ; NZ
        ret

; A = distance from zombie IX to the edge of the next cell along its
; heading (0..255)
zedge:
        ld a,(ix+4)
        rra                             ; carry: along x
        ld a,(ix+0)
        jr c,.ax
        ld a,(ix+2)
.ax:    ld c,a
        ld a,(ix+4)
        bit 1,a
        ld a,c
        ret nz                          ; going down: the low byte
        neg                             ; going up: 256 - the low byte
        ret nz
        dec a                           ; (a whole cell: 255)
        ret

; Zombie IX hits the base tile ahead of it: 1 damage
base_hit:
        ld a,(ix+4)
        add a,a
        ld hl,zdir_step
        add hl,a
        ld a,(ix+1)                     ; the tile: the zombie's cell + a step
        add a,(hl)
        ld e,a
        inc hl
        ld a,(ix+3)
        add a,(hl)
        ld d,a
        ld c,1
        ; fall through

; Base tile (E, D) = (x, z) takes C damage (if it is one, and not already
; gone).  Destroyed, a terrace tile becomes road and the pad sets game_over.
base_damage:
        ld a,d
        sub PAD_Z-TERRACE_R             ; its hit points: base_hp[row*5+col]
        cp 2*TERRACE_R+1
        jp nc,barr_damage               ; (not the base: a barricade?)
        ld b,a
        add a,a
        add a,a
        add a,b
        ld b,a
        ld a,e
        sub PAD_X-TERRACE_R
        cp 2*TERRACE_R+1
        jp nc,barr_damage
        add a,b
        ld hl,base_hp
        add hl,a
        ld a,(hl)
        or a
        ret z                           ; (already gone)
        sub c
        jr z,.dead
        jr c,.dead
        ld (hl),a
        ret
.dead:  ld (hl),0
        ld l,d                          ; destroyed
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        push hl
        ld bc,city_map
        add hl,bc
        ld a,(hl)
        and CELL_CODE
        cp PAD_CODE
        jr nz,.ter
        pop hl
        ld a,1                          ; the landing pad: game over
        ld (game_over),a
        ret
.ter:   ld a,(hl)                       ; a terrace tile: road now (the
        and CELL_FLAGS                  ; marks kept)
        ld (hl),a
        pop hl
        ld bc,city_col
        add hl,bc
        ld (hl),GROUND_COL
        ld a,MAP_BG
        jp map_pix                      ; and on the map (map.asm)

; New game: the pad and terrace whole, at full strength
base_init:
        ld hl,base_hp
        ld d,PAD_Z-TERRACE_R
.r:     ld e,PAD_X-TERRACE_R
.c:     ld a,d
        cp PAD_Z
        jr nz,.t
        ld a,e
        cp PAD_X
        jr nz,.t
        ld (hl),PAD_HP
        ld b,PAD_CODE
        ld c,PAD_COL
        jr .set
.t:     ld (hl),TERRACE_HP
        ld b,TERRACE_CODE
        ld c,TERRACE_COL
.set:   inc hl
        push hl
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        push hl
        push bc
        ld bc,city_map
        add hl,bc
        pop bc
        ld (hl),b
        pop hl
        push bc
        ld bc,city_col
        add hl,bc
        pop bc
        ld (hl),c
        pop hl
        inc e
        ld a,e
        cp PAD_X+TERRACE_R+1
        jr nz,.c
        inc d
        ld a,d
        cp PAD_Z+TERRACE_R+1
        jr nz,.r
        ; fall through: the barricades

;------------------------------------------------------------------------------
; Barricades: terrace tiles away from the base, improvised barricades.  Each
; has its own hit points, in barr_tab (resident): NBARR entries of BARR_REC
; bytes, x, z, hit points (0: none, or destroyed).  barricade_init fills it
; at the level's start from the city map (after the level's map changes),
; the first NBARR found; any more stay but can't be destroyed.  Zombies and
; blasts damage them through base_damage (zbase: any terrace tile is a base
; tile to them); destroyed, a barricade is road, as a base terrace tile.
;------------------------------------------------------------------------------
barricade_init:
        ld hl,barr_tab                  ; none yet
        ld b,NBARR*BARR_REC
.cl:    ld (hl),0
        inc hl
        djnz .cl
        xor a
        ld (barr_n),a
        ld de,barr_tab
        ld hl,city_map
        ld c,0                          ; z
.row:   ld b,0                          ; x
.cell:  ld a,(hl)
        and CELL_CODE
        cp TERRACE_CODE
        jr nz,.nx
        ld a,b                          ; the base's own terrace: not one
        sub PAD_X-TERRACE_R
        cp 2*TERRACE_R+1
        jr nc,.add
        ld a,c
        sub PAD_Z-TERRACE_R
        cp 2*TERRACE_R+1
        jr c,.nx
.add:   ld a,(barr_n)
        cp NBARR
        jr nc,.nx                       ; (the table is full)
        inc a
        ld (barr_n),a
        ld a,b
        ld (de),a                       ; x,
        inc de
        ld a,c
        ld (de),a                       ; z,
        inc de
        ld a,TERRACE_HP
        ld (de),a                       ; hit points
        inc de
.nx:    inc hl
        inc b
        ld a,b
        cp GRID
        jr nz,.cell
        inc c
        ld a,c
        cp GRID
        jr nz,.row
        ret

; Tile (E, D) = (x, z), not the base's: if it is a barricade still standing,
; it takes C damage; destroyed, it becomes road (base_damage.dead)
barr_damage:
        ld hl,barr_tab
        ld b,NBARR
.lp:    ld a,(hl)
        cp e
        jr nz,.nx
        inc hl
        ld a,(hl)
        dec hl
        cp d
        jr nz,.nx
        inc hl                          ; this one: its hit points
        inc hl
        ld a,(hl)
        or a
        ret z                           ; (already gone)
        sub c
        jp z,base_damage.dead
        jp c,base_damage.dead
        ld (hl),a
        ret
.nx:    inc hl
        inc hl
        inc hl
        djnz .lp
        ret                             ; not one (or past the table)
        ASSERT BARR_REC == 3

; A = heading (mod 4): if the cell next to zombie IX that way is a street,
; or a base tile (so the road towards the pad can lead into the base and an
; attack), set the heading's bit in C.  Keeps C otherwise.
zroad:
        and 3
        push af
        push bc
        call zside
        call nz,zbase                   ; not a street: a base tile?
        pop bc
        jr nz,.no
        pop af
        push hl
        ld hl,zbits
        add hl,a
        ld a,(hl)
        or c
        ld c,a
        pop hl
        ret
.no:    pop af
        ret

; A = heading, C = heading bits: NZ if that heading's bit is set
zhas:
        push hl
        ld hl,zbits
        add hl,a
        ld a,(hl)
        and c
        pop hl
        ret

; C = candidate heading bits -> A = the heading pointing most towards the
; landing pad (its dot product with the way to the pad is largest)
zbest:
        ld a,c
        ld (zb_mask),a
        ld hl,PAD_X*256+128             ; the way to the pad
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        ld (zb_dx),hl
        ld hl,PAD_Z*256+128
        ld e,(ix+2)
        ld d,(ix+3)
        or a
        sbc hl,de
        ld (zb_dz),hl
        ld a,$FF
        ld (zb_h),a
        ld b,0                          ; heading
.lp:    ld a,(zb_mask)
        srl a
        ld (zb_mask),a
        jr nc,.nx                       ; not a candidate
        ld hl,(zb_dz)                   ; score: +z dz, +x dx, -z -dz, -x -dx
        bit 0,b
        jr z,.z
        ld hl,(zb_dx)
.z:     bit 1,b
        call nz,neg_hl
        ld a,(zb_h)
        inc a
        jr z,.take                      ; the first candidate
        push hl
        ld de,(zb_best)
        or a
        sbc hl,de
        pop hl
        jr z,.nx                        ; not better
        jp m,.nx
.take:  ld (zb_best),hl
        ld a,b
        ld (zb_h),a
.nx:    inc b
        ld a,b
        cp 4
        jr nz,.lp
        ld a,(zb_h)
        ret

; Junction decision, once per cell, 0.25-0.75 of the way through it
zjunction:
        ld a,(ix+1)
        cp (ix+8)
        jr nz,.new
        ld a,(ix+3)
        cp (ix+9)
        ret z                           ; already decided in this cell
.new:   ld a,(ix+4)
        rra                             ; carry = moving along x
        ld a,(ix+0)
        jr c,.ax
        ld a,(ix+2)
.ax:    sub 64
        cp 128
        ret nc                          ; not 0.25-0.75 through the cell yet
        ld c,0                          ; side roads?
        ld a,(ix+4)
        add a,3
        call zroad
        ld a,(ix+4)
        inc a
        call zroad
        ld a,c
        or a
        jr z,zmark                      ; none: nothing to decide
        ld a,(ix+4)                     ; and straight on
        call zroad
        call zrand
        ld a,(zbias_t)                  ; biased: the road towards the pad
        ld b,a
        ld a,l
        cp b
        jr nc,.old
        ld a,c
        call zbest
        jr zturn
.old:   ld a,(ix+4)                     ; otherwise: left at 1 in 2 if there
        add a,3                         ; is one, else right at 1 in 2
        and 3
        call zhas
        jr z,.right
        bit 0,h
        jr z,.right
        ld a,(ix+4)
        add a,3
        jr zturn
.right: ld a,(ix+4)
        inc a
        and 3
        call zhas
        jr z,zmark
        bit 1,h
        jr z,zmark
        ld a,(ix+4)
        inc a
        ; fall through

; Take heading A (mod 4) and mark this cell as decided
zturn:  and 3
        ld (ix+4),a
zmark:  ld a,(ix+1)
        ld (ix+8),a
        ld a,(ix+3)
        ld (ix+9),a
        ret

; Z set if the cell beside the zombie in heading A (mod 4) is a street
zside:  and 3
        ld e,a
        ld hl,256                       ; exactly one cell over
        ; fall through

; Z set if the point HL units from zombie IX along heading E is a street
; cell inside the map.  Preserves IX.
ztest:
        bit 1,e
        call nz,neg_hl
        bit 0,e
        jr nz,.x
        ld c,(ix+2)
        ld b,(ix+3)
        add hl,bc
        ld a,h                          ; z cell
        ld d,(ix+1)                     ; x cell
        jr .chk
.x:     ld c,(ix+0)
        ld b,(ix+1)
        add hl,bc
        ld d,h
        ld a,(ix+3)
.chk:   cp GRID
        jr nc,.no                       ; off the map (or negative)
        ld l,a
        ld a,d
        cp GRID
        jr nc,.no
        ld h,0
        ROWOFS
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        and CELL_CODE                   ; Z: road (A = the cell code)
        ret
.no:    or a                            ; A >= 32: NZ
        ret

; BC += A (signed).  Preserves HL, DE.
add_sb:
        push hl
        ld l,a
        rla
        sbc a,a
        ld h,a
        add hl,bc
        ld b,h
        ld c,l
        pop hl
        ret

; HL -> city_map entry for zombie IX's cell.  Preserves BC.
zmap_ptr:
        call zcell_ofs
        ld de,city_map
        add hl,de
        ret

zcell_ofs:
        ld l,(ix+3)
        ld h,0
        ROWOFS
        ld a,(ix+1)
        add hl,a
        ret

; Frame chooser for a ghost or banshee (its sprite pointers in gfs_tab):
; its sheet's 2 frames (a new one every 4 frames), never mirrored
gfig_sel:
        xor a
        ld (zface),a
        ld a,(zanim)
        rrca
        rrca
        and 1                           ; frame
        add a,a
        add a,a
        add a,a
        ld hl,zlvl
        add a,(hl)                      ; frame*8 + level
        add a,a
        ld hl,(gfs_tab)
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (zrow),hl
        jp zspr_rows

        INCLUDE "tables_ghost.inc"      ; ghost sprites (gentables.py)

; HL = next 16-bit xorshift random number
zrand:
        ld hl,(zseed)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (zseed),hl
        ret

;------------------------------------------------------------------------------
; Called (jp) from draw_cell for an empty cell, HL -> its city_map byte.
; Draws the zombies standing in that cell (bit 7 says there are some: then
; the records are searched for them, highest index first).  Needs the city
; page at $E000.
;------------------------------------------------------------------------------
zombie_cell:
        bit CELL_ZOMBIE_B,(hl)
        ret z
        ld de,city_map
        or a
        sbc hl,de                       ; the cell's index, row * GRID + x
        ld a,l
        and GRID-1
        ld (zc_x),a
        add hl,hl
        add hl,hl                       ; H = row (GRID = 64)
        ld a,h
        ld (zc_z),a
        push ix
        ld ix,zombies+(NMON-1)*ZREC
        ld b,NMON
.lp:    ld a,(zc_x)
        cp (ix+1)
        jr nz,.nx
        ld a,(zc_z)
        cp (ix+3)
        jr nz,.nx
        push bc
        call zombie_draw                ; (skips a zombie no longer active)
        pop bc
.nx:    ld de,-ZREC
        add ix,de
        djnz .lp
        pop ix
        ret
        ASSERT GRID == 64

; Project and draw zombie IX (or a special monster)
zombie_draw:
        bit 0,(ix+10)
        ret z                           ; killed this frame
        ld a,(ix+15)
        cp ZT_GHOST
        jr nc,.ghost                    ; a flying special monster
        ld hl,0
        ld (fig_y),hl                   ; on the ground
        ld hl,zfig_sel
        ld (fig_sel),hl
        ld a,ZOMBIE_COL
        ld (zspr_rows.col+1),a
        ld a,(ix+15)
        cp ZT_GHOUL
        jp nz,fig_draw
        ld hl,(zh_y)                    ; a ghoul: half the height (its size,
        push hl                         ; and its head when its feet are
        sra h                           ; below the view)
        rr l
        ld (zh_y),hl
        ld hl,(zh_z)
        push hl
        sra h
        rr l
        ld (zh_z),hl
        ld hl,GHOUL_H
        ld (fig_h),hl
        call fig_draw
        ld hl,ZOMBIE_H                  ; back to full height
        ld (fig_h),hl
        pop hl
        ld (zh_z),hl
        pop hl
        ld (zh_y),hl
        ret
.ghost: ld l,(ix+21)                    ; a ghost: at its height, its sheet
        ld h,(ix+22)
        ld (fig_y),hl
        ld hl,gfig_sel
        ld (fig_sel),hl
        ld a,(ix+15)                    ; ghost or banshee: its sprites, colour
        cp ZT_BANSHEE                   ; and fade
        ld hl,gho_ptr
        ld de,gfade
        ld c,GHOST_COL
        jr nz,.gt
        ld hl,bsh_ptr
        ld de,bfade
        ld c,BANSHEE_COL
.gt:    ld (gfs_tab),hl
        ld a,(ix+16)
        cp GM_DYING
        ld a,c
        jr nz,.gcol
        ld a,(ix+17)                    ; fading out: its colour by the
        dec a                           ; frames left (1..GHOST_FADE_FRAMES)
        ex de,hl
        add hl,a
        ld a,(hl)
.gcol:  ld (zspr_rows.col+1),a
        jr fig_draw

; A dying ghost's colour, by its frames left - 1: the last 3 frames dark
; grey, then grey, light grey, and white for the first 3
gfade:      db GHOST_FADE, GHOST_FADE, GHOST_FADE
            db MAP_GHOST_DARK, MAP_GHOST_DARK, MAP_GHOST_DARK
            db MAP_GHOST_MID, MAP_GHOST_MID, MAP_GHOST_MID
            db GHOST_COL, GHOST_COL, GHOST_COL
        ASSERT $ - gfade == GHOST_FADE_FRAMES
bfade:      db BANSHEE_FADE, BANSHEE_FADE, BANSHEE_FADE      ; a banshee's
            db MAP_BANSHEE_DARK, MAP_BANSHEE_DARK, MAP_BANSHEE_DARK
            db MAP_BANSHEE_MID, MAP_BANSHEE_MID, MAP_BANSHEE_MID
            db BANSHEE_COL, BANSHEE_COL, BANSHEE_COL
        ASSERT $ - bfade == GHOST_FADE_FRAMES

; Project and draw a figure whose x, z are at (IX+0..3) like a zombie's:
; feet at height fig_y, sprite frame chosen by the routine at fig_sel (it
; sets zrow and zface, then jumps to zspr_rows), colour patched into
; zspr_rows.  Used for zombies and for humans (human.asm).
fig_draw:
        ld l,(ix+0)
        ld h,(ix+1)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld l,(ix+2)
        ld h,(ix+3)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (zt+0),hl
        call rot_pitch
        ld (zt+2),hl                    ; foot point (X, Y, Z)
        ld (zt+4),de
        ld hl,(fig_y)                   ; raised: + y * (cosP, sinP)
        ld a,h
        or l
        jr z,.gnd
        push hl
        ld de,(cos_p)
        call fmul
        ld de,(zt+2)
        add hl,de
        ld (zt+2),hl
        pop hl
        ld de,(sin_p)
        call fmul
        ld de,(zt+4)
        add hl,de
        ld (zt+4),hl
.gnd:   ld hl,zt
        call calc_oc
        or a
        jr z,.foot
        cp 16
        ret nz                          ; only feet "below the bottom" allowed:
        ld hl,(zt+2)                    ; project the head for the column
        ld de,(zh_y)
        add hl,de
        ld (zt+2),hl
        ld hl,(zt+4)
        ld de,(zh_z)
        add hl,de
        ld (zt+4),hl
        ld hl,zt
        call calc_oc
        or a
        ret nz
        ld hl,zt
        call project
        ld (zsx),a
        ld a,c
        ld (zy),a                       ; head row
        call zsize
        ret c
        ; Keep the feet anchor: the sprite is at most 16 pixels, so it stands
        ; on the (off-screen) feet, top = head + (true height - sprite height),
        ; exactly where the foot-anchored path would put it.
        ld a,(zh)
        ld c,a
        ld a,(zhr)
        sub c
        ld c,a
        ld a,(zy)
        add a,c
        ret c
        cp VIEW_H
        ret nc                          ; whole sprite below the viewport
        ld (zy),a
        jr zspr
.foot:  ld hl,zt
        call project
        ld (zsx),a
        ld a,c
        ld (zy),a
        call zsize
        ret c
        ld a,(zh)
        ld c,a
        ld a,(zy)
        sub c
        inc a
        ld (zy),a                       ; top row = foot - h + 1
        ; fall through

; Draw the sprite: zsx = centre column, zy = top row (rows outside the
; viewport are skipped, so it can be negative or past the bottom)
zspr:
        ld hl,(fig_sel)                 ; choose the frame
        jp (hl)

; Zombie frame: walking, facing from its heading relative to the view
zfig_sel:
        ; facing relative to the view: ((heading*64 - yaw + 32) >> 6) & 3
        ld a,(ix+4)
        rrca
        rrca
        ld hl,yaw
        sub (hl)
        add a,32
        rlca
        rlca
        and 3
        ld hl,face_tab
        add hl,a
        ld a,(hl)
        ld (zface),a
        ; sprite index (facing*4 + frame)*8 + level
        ld a,(ix+7)
        or a
        ld a,0
        jr nz,.still                    ; standing still: hold the frame
        ld a,(ix+15)
        cp ZT_GHOUL
        ld a,(zanim)
        jr z,.still                     ; every frame for a ghoul,
        rrca                            ; every 2 frames for
        bit 0,(ix+15)                   ; a fast zombie (legs keep pace)
        jr nz,.still
        rrca                            ; every 4 for a zombie
.still: add a,(ix+5)
        and 3
        ld c,a
        ld a,(zface)
        and 1
        add a,a
        add a,a
        add a,c
        add a,a
        add a,a
        add a,a
        ld hl,zlvl
        add a,(hl)
        add a,a
        ld hl,spr_ptr
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (zrow),hl
        ; fall through

; Draw rows from zrow, mirrored if zface bit 1, at zsx / zy
zspr_rows:
        ; x0 = centre - w/2
        ld a,(zw)
        srl a
        ld e,a
        ld d,0
        ld a,(zsx)
        ld l,a
        ld h,0
        or a
        sbc hl,de
        ld (zx0),hl
        ld a,(zh)
        ld (zcnt),a
.row:   ld hl,(zrow)
        ld b,(hl)                       ; row bits
        inc hl
        ld (zrow),hl
        ld a,(zy)
        cp VIEW_H
        jr nc,.next                     ; above (negative) or below the viewport
        call seg_map                    ; A = y & 31 (preserves BC, DE, L)
        ld h,a
        ld a,(zface)
        bit 1,a
        jr z,.nm
        ld l,b                          ; mirror: reverse the bits, then
        ld a,h                          ; shift out the unused right columns
        ld h,high bitrev
        ld b,(hl)
        ld h,a
        ld a,(zw)
        sub 8
        jr z,.nm
        neg
        ld c,a
.sh:    sla b
        dec c
        jr nz,.sh
.nm:    ld de,(zx0)
        ld a,(zw)
        ld c,a
.px:    sla b
        jr nc,.skip
        ld a,d
        or a
        jr nz,.skip                     ; off the left or right edge
        ld l,e
.col:   ld (hl),ZOMBIE_COL              ; (colour patched per figure)
.skip:  inc de
        dec c
        jr nz,.px
.next:  ld hl,zy
        inc (hl)
        ld hl,zcnt
        dec (hl)
        jr nz,.row
        ret

; Projected height from the last project's Z -> zlvl, zw, zh.
; Carry set if too small to draw.
zsize:
        ld hl,(fig_h)
        call scale_comp
        ld (zhr),a                      ; true projected height (unclamped)
        cp 3
        ret c
        cp 17
        jr c,.h
        ld a,16
.h:     ld hl,lvl_of_h
        add hl,a
        ld a,(hl)
        ld (zlvl),a
        ld hl,spr_w
        add hl,a
        ld c,(hl)
        ld hl,spr_h
        add hl,a
        ld a,(hl)
        ld (zh),a
        ld a,c
        ld (zw),a
        or a                            ; clear carry
        ret

;------------------------------------------------------------------------------
; Zombie page data
;------------------------------------------------------------------------------
; relative facing (0 walking away, 1 right, 2 towards, 3 left) ->
; bit 0 = left sprite (else forward), bit 1 = mirror
face_tab:   db %10, %11, %00, %01

zspeed:     db ZSPEED_INIT              ; zombie speed, world units per frame
                                        ; in 4.4 fixed point (16 = 1.0, max 119:
                                        ; fast zombies go 2x): raise it on
                                        ; later levels
zsteps:     db ZSTEPS_INIT              ; frames between each zombie's
                                        ; decision checks (1..): zsteps*zspeed*2
                                        ; (fast zombies) must stay under 128*16
                                        ; so none can walk through a junction
zstep:      db 0
zlook:      dw 0
zbias_t:    db 128                      ; junction bias towards the pad (/256)
zcur_i:     db 0                        ; index of the zombie being moved
zatk_flags: ds NMON                    ; per zombie: TRUE while attacking a base
                                        ; tile (its map dot red), else FALSE
zb_mask:    db 0                        ; zbest
zb_h:       db 0
zb_best:    dw 0
zb_dx:      dw 0
zb_dz:      dw 0
zbits:      db 1, 2, 4, 8               ; heading -> bit
zdir_step:  db 0, 1,  1, 0,  0, -1,  -1, 0  ; heading -> (cell dx, dz)
base_hp:    ds (2*TERRACE_R+1)*(2*TERRACE_R+1)  ; hit points, pad and terrace
zlook_fast: dw 0                        ; (fast zombies: twice the walk)
zlook_ghoul: dw 0                       ; (ghouls: five times)
zi_fast:    db 0                        ; zombie_wave: fast zombies still to make
zi_left:    db 0                        ;   and zombies still to place
zombies:    ds NMON*ZREC
zseed:      dw 1
zanim:      db 0
gfs_tab:    dw gho_ptr                  ; gfig_sel: the sprites being drawn
zwave_new:  db 0                        ; 1: a new wave began (spec_update)
zc_x:       db 0                        ; zombie_cell: the cell being drawn
zc_z:       db 0
zh_y:       dw 0
zh_z:       dw 0
zt:         ds 6
zsx:        db 0
zy:         db 0
zx0:        dw 0
zrow:       dw 0
zcnt:       db 0
zlvl:       db 0
zw:         db 0
zh:         db 0
zhr:        db 0
zface:      db 0
fig_y:      dw 0                        ; fig_draw: height of the feet
fig_h:      dw ZOMBIE_H                 ; zsize: the figure's height
fig_sel:    dw zfig_sel                 ; fig_draw: frame chooser
