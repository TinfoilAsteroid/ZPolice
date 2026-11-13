;==============================================================================
; Z-POLICE  -  3D vector city flight for the ZX Spectrum Next
;
;  Z80N assembler (sjasmplus --zxnext).  Layer 2 256x192x8bpp, double buffered.
;  The 3D viewport is the top 256x128; the bottom third is an instrument panel.
;  Maths: world positions are 16-bit integers (one city cell = 256 units),
;         trig values are S7.8 fixed point (1.0 = $0100).
;  Hidden line removal: painter's algorithm. Buildings are walked over the
;  grid far-to-near (no sort needed). Each visible face is filled in its
;  shade (roof lighter, side turned away darker) and optionally outlined, so
;  nearer buildings overwrite those behind them. Faces with every corner on
;  screen use cached projections; faces crossing the view frustum are
;  clipped in 3D (Sutherland-Hodgman, 5 planes). Rasterisation then only
;  ever sees on-screen 8-bit coordinates.
;
;  Controls: Q/A speed up/down   Z air brake O/P turn left/right
;            W/S climb/descend   E/D nose up/down
;            SPACE fire          1-5 select weapon slot
;            0 change the centre slot's weapon
;
;  Source files: zpolice.asm (resident main code), memory_bank_defs.asm
;  (slots and pages).  Game logic pages, swapped into slot 6 at $C000:
;  player.asm (input/movement), weapons.asm, menu.asm (main menu).  Core
;  function pages, swapped into slot 7 at $E000: city.asm (Layer 2
;  drawing), hud.asm (ULA HUD), input.asm (redefinable keys, joysticks), sprites.asm
;  (hardware sprites).  Always mapped: zombie.asm at $2000, human.asm and
;  map.asm (the city map) at $7000.
;
;  Memory while running:
;    $0000-$1FFF  Layer 2 back buffer, one 8K section at a time (slot 0)
;    $2000-$3FFF  zombie page (slot 1)
;    $4000-$7FFF  occlusion data; cell colours, humans, map (slots 2-3)
;    $8000-$9FFF  ULA screen (slot 4)
;    $A000-$BFFF  resident code, tables, variables, stack (slot 5)
;    $C000-$DFFF  game logic page (slot 6)
;    $E000-$FFFF  core function page (slot 7)
;==============================================================================

        DEVICE ZXSPECTRUMNEXT
        SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
    IFDEF RELEASE
        CSPECTMAP "release_tmp/zpolice.map"
    ELSE
        CSPECTMAP zpolice.map
    ENDIF
        OPT --zxnext=cspect --syntax=a --reversepop
;------------------------------------------------------------------------------
; Build options
;------------------------------------------------------------------------------
; RELEASE: the build for players (-DRELEASE: build.bat release).  Turns off
; everything for testing, whatever is set below: the DEBUG_ settings, DRAW_FPS
; and DOTS_ALL, a START_LEVEL_SET, a START_SALVAGE.  It's assembled into
; release_tmp/, so the debug build's files (and the tests') stay as they are.

; REAL_HARDWARE: the build for a real Next (-DREAL_HARDWARE: build.bat
; hardware), which may use DMA+ (the zxnDDMA, the blitter of core 3.03.00, see
; layer2_cls.asm).  Off, the DMA routines use only the plain zxnDMA, as CSpect
; doesn't have DMA+ yet.  The .nex then also asks for core 3.03.00: on an older
; core DMA+'s commands would be misread, not ignored.
        ;DEFINE REAL_HARDWARE
    IFDEF REAL_HARDWARE                 ; (said in the build's output)
        DISPLAY "REAL_HARDWARE set: the build for a real Next (DMA+, core 3.03.00 or later)"
    ELSE
        DISPLAY "REAL_HARDWARE not set: the CSpect build (plain zxnDMA, no DMA+)"
    ENDIF

; DRAW_LINES: outline building faces with EDGE_COL vectors.  Comment it out for solid-colour buildings only; the HUD
; is always drawn.  Can also be set from the command line: -DDRAW_LINES
        ;DEFINE DRAW_LINES

; WAIT_FOR_VBLANK: wait for the raster to leave the display area before
; flipping the Layer 2 buffers (no tearing).  Comment it out to flip as soon
; as a frame is drawn: faster, but the flip may tear mid-screen.
; Command line: -DWAIT_FOR_VBLANK
        ;DEFINE WAIT_FOR_VBLANK

; DRAW_FPS: measure frames per second from the raster (vtick) and show it at
; the top left of the ULA screen.  Comment it out to drop the measuring and
; the display.  Command line: -DDRAW_FPS
        ;DEFINE DRAW_FPS

; SKY_IS_WALL: the camera can never rise above the perimeter wall, so fill
; the sky in the wall's colour and draw wall cells only up to camera height
; (their top edge is then exactly the horizon).  No sky is ever seen.
; Command line: -DSKY_IS_WALL
        DEFINE SKY_IS_WALL

; OCCLUSION_CULL: in level flight, record the buildings, then cull those
; completely hidden behind nearer ones (a per-column cover buffer, front to
; back) before drawing the rest.  Uses pages PAGE_OCC0/1 at $4000-$7FFF.
; Command line: -DOCCLUSION_CULL
        DEFINE OCCLUSION_CULL

; OCC_PITCHED: OCCLUSION_CULL pitched too, up to OCC_PMAX (18, city2.asm;
; past it the plain way).  Pitched, occ_pretest has bounds of its own
; (occ_pretest.pit), and a building covers only the columns of both its top
; and bottom corners (its vertical edges lean).  Pixel-identical (124 random
; pitched views; test_render.py checks 16 against the painter's path).
; Comment it out for level flight only.  Command line: -DOCC_PITCHED
        DEFINE OCC_PITCHED

; LEVEL_FAST_PATH: while pitch is 0 (level flight) a building's top corners
; have the same camera X and Z as the bottom corners below them, so each top
; corner reuses its bottom corner's screen x and 1/Z and only works out its
; screen y.  Comment it out to project every corner in full.
; Command line: -DLEVEL_FAST_PATH
        DEFINE LEVEL_FAST_PATH

; CLIP_2D: a face that crosses only the screen's sides, top or bottom, and is
; within a guard band (|X| <= 2Z, |Y| <= Z), has its corners projected to
; 16-bit screen coordinates and is clipped against the screen in 2D, not in
; 3D (no new points to project, one multiply per new point, not three).
; Faces crossing the near plane, or outside the guard band, are clipped in
; 3D as before.  Comment it out to clip every face in 3D.
; Command line: -DCLIP_2D
        DEFINE CLIP_2D

    IFDEF RELEASE
      IFDEF DRAW_FPS
        UNDEFINE DRAW_FPS
      ENDIF
      IFDEF DOTS_ALL
        UNDEFINE DOTS_ALL
      ENDIF
      IFDEF START_LEVEL_SET
        UNDEFINE START_LEVEL_SET
      ENDIF
    ENDIF

        INCLUDE "memory_bank_defs.asm"  ; MMU slots, registers, addresses, pages
        INCLUDE "gfx_ids.inc"           ; the figures' purposes (gengraphics.py)

;------------------------------------------------------------------------------
; Tuning constants
;------------------------------------------------------------------------------
; Scale: one map tile (cell) is 20 m x 20 m = 256 world units, and one
; height unit (building heights, the ceiling, the pad) is 10 m = 128 world
; units.  World units are the same size on every axis, so 1 m = 12.8 units
; and 1 unit = 7.8 cm.  The city is 64 x 64 tiles = 1280 m.
; Speeds are per rendered frame, so real speed depends on the frame rate
; (figures below are at 14 fps).
GRID            equ 64          ; the city is GRID x GRID tiles (gentables.py)
; A city_map byte: bits 0-4 the cell code (0 road, 1-15 building height
; level, PAD_CODE, TERRACE_CODE, VOID_CODE: out of bounds), bit 6 set while a human waits in the cell
; (human.asm, hum_flags), bit 7 while a zombie or special monster stands in
; it (zombie.asm, zflags; its type is in its record).  Bit 5 is free.  So
; every reader masks with CELL_CODE before testing for road or a code.
CELL_CODE       equ %00011111
CELL_FLAGS      equ %11100000       ; (the marks, kept when the code changes)
CELL_HUMAN_B    equ 6
CELL_ZOMBIE_B   equ 7
CELL_HUMAN      equ 1<<CELL_HUMAN_B
CELL_ZOMBIE     equ 1<<CELL_ZOMBIE_B
TILE_M          equ 20          ; metres per tile (reference scale)
TILE_UNITS      equ 256         ; world units per tile
HEIGHT_M        equ 10          ; metres per height unit
HEIGHT_UNITS    equ 128         ; world units per height unit
NEAR            equ 16          ; near clip plane: 1.25 m
VIEW_R          equ 8           ; most draw distance: buildings within +/- 8
                                ; tiles (160 m).  Each level sets its own,
                                ; 2..VIEW_R (view_r; night, fog), and the
                                ; street dots' radius one less (dot_r)
PMAX            equ 24          ; pitch limit (256 = 360 deg) - match gentables.py
SPEED_MAX       equ 28          ; units/frame: 2.2 m/frame, ~31 m/s (110 km/h)
SPEED_MIN       equ -6          ; reverse: 0.47 m/frame, ~6.6 m/s
YAW_RATE        equ $0180       ; turn per frame, 8.8 fixed (1.5 units;
                                ; 256 units = 360 degrees)
YAW_FINE        equ 256*256/360 ; the first frame of a turn: 1 degree
                                ; (182: 0.711 units, 8.8 fixed)
CLIMB_RATE      equ 4           ; units/frame: 0.31 m/frame, ~4.4 m/s
SPEED_STEP      equ 1           ; Q / A: speed change a frame, units/frame
                                ; (1.1 m/s; player.asm uses inc / dec)
        ASSERT SPEED_STEP == 1
; Air brake (Z): the speed falls by twice the Q / A step every frame, to 0
AIRBRAKE_STEP   equ 2*SPEED_STEP    ; 2 units/frame (2.2 m/s)
; Booster module (a salvage reward, fitted at once: boost_fitted).  The
; boost control (K_BOOST, X) puts the speed straight to BOOST_SPEED, twice
; SPEED_MAX, if going forwards at BOOST_MIN or more with fuel left; again,
; or out of fuel, puts back the speed it had (boost_spd).  Q, A and Z don't
; change the speed while boosting.  Each boosted frame burns 1 fuel
; (boost_fuel, at most BOOST_FUEL_MAX); landed on the pad it refuels 1 a
; frame (pad_service).  HUD: the B gauge, and the speed bar amber.
BOOST_SPEED     equ 2*SPEED_MAX     ; 56 units/frame
BOOST_MIN       equ SPEED_MAX/2     ; 14: at least half speed, forwards
BOOST_FUEL_MAX  equ 200
        ASSERT BOOST_SPEED < 128 && BOOST_FUEL_MAX < 256
; Pitch damper: with neither E nor D held, the nose eases back to level.
; Every PDAMP_FRAMES frames the 8.8 pitch moves towards 0 by
; max(PDAMP_MIN, |pitch| * PDAMP_K) in 1/256ths of a pitch unit.  With
; PDAMP_K 0 that is a steady PDAMP_MIN a frame: half a pitch unit, half the
; rate of the nose keys (1 unit a frame), however far it is from level.  (A
; PDAMP_K above 0 adds a share of what is left, faster when far off: 43, as
; it was, returned up to 4 units a frame from full pitch.)
PDAMP_FRAMES    equ 1           ; frames between damping steps
PDAMP_K         equ 0           ; no share: a steady rate
PDAMP_MIN       equ 128         ; 128/256: half a pitch unit a frame
MIN_Y           equ 8           ; lowest flight: 0.6 m
MAX_Y           equ 7*HEIGHT_UNITS/5  ; ceiling 1.4 height units: 14 m, 179.
                                ; Never a roof's resting height (height +
                                ; COLL_H + 1: 192 is level 3's): the VTOL
                                ; would land there and couldn't climb off
MAX_Y_THRUST    equ 3*HEIGHT_UNITS  ; with the vertical thrusters (a salvage
                                ; reward, vthrust_fitted): 3.0 height units, 30 m
BLD_MAX_H       equ 7*HEIGHT_UNITS  ; tallest building 7.0 height units: 70 m
                                ; (htab level 15, gentables.py; 4.7 m a level)
        ASSERT MAX_Y_THRUST < BLD_MAX_H ; (below the perimeter wall: SKY_IS_WALL)
WORLD_MIN       equ 64
WORLD_MAX       equ GRID*256-64
DMA_SPAN_MIN    equ 20          ; spans this wide or wider are filled by DMA
; The VTOL (the player's craft): 10 m long by 3 m wide.  Its position
; (cam_x, cam_z, the camera) is its centre; the hit box against buildings is
; that rectangle turned to the heading (vtol_ground), and the camera stays
; COLL_H above any roof under it.
VTOL_LEN_M      equ 10
VTOL_WID_M      equ 3
VTOL_HL         equ VTOL_LEN_M*TILE_UNITS/(TILE_M*2)  ; half length: 64 units
VTOL_HW         equ VTOL_WID_M*TILE_UNITS/(TILE_M*2)  ; half width: 19 units
COLL_H          equ 12          ; clearance above a roof: 0.94 m

; Weapons: 5 slots, 2 bytes each (type, ammo) in wpn_slots.  Slot 0 is the
; centre gun; slots 1-4 are the wing pylon hard points (limited ammo).
WPN_SLOTS       equ 5
WPN_CENTRE      equ 0           ; slot index of the centre gun
WPN_PYLON1      equ 1           ; first of the 4 wing pylons (slots 1-4)
WPN_TYPE        equ 0           ; offset of the type byte in a slot
WPN_AMMO        equ 1           ; offset of the ammo counter in a slot
AMMO_INF        equ 255         ; ammo counter 255 = infinite ammo (never
                                ; decremented); 0 = empty
; weapon types (placeholders until the weapons exist)
WPN_NONE        equ 0           ; empty slot / nothing fitted
WPN_GUN         equ 1           ; machine gun (centre slot)
WPN_LASER       equ 2           ; pulse laser (centre slot)
WPN_CHAIN       equ 3           ; chain gun (centre slot)
WPN_ROCKETS     equ 4           ; unguided rocket pod (wing pylons)
WPN_MISSILE     equ 5           ; missile pod (wing pylons)
WPN_BOMB        equ 6           ; bomb (placeholder)
WPN_AUTOCANNON  equ 7           ; autocannon (wing pylons)
WPN_PROX        equ 8           ; proximity cannon (wing pylons)
WPN_LCHAIN_L    equ 9           ; linked chain gun L (WPN_LINK_L only)
WPN_LCHAIN_R    equ 10          ; linked chain gun R (WPN_LINK_R only)
WPN_LAST        equ WPN_LCHAIN_R    ; (the highest type: the tables by type)
; The slots either side of the centre one (as the HUD shows them, keys
; 2 4 1 5 3): the linked chain guns' (gun_fire, weapons.asm)
WPN_LINK_L      equ 3           ; key 4: just left of the centre slot
WPN_LINK_R      equ 4           ; key 5: just right of it
; Weapon type details: wpn_cfg, WCFG_SIZE bytes per type (wpn_cfg_ptr)
WCFG_LOAD       equ 0           ; full load (AMMO_INF: infinite)
WCFG_RELOAD     equ 1           ; frames to reload a shot on the pad (0: none)
WCFG_SLOTS      equ 2           ; the slots it may be fitted in: bit n =
                                ; slot n (0 = the centre slot, key 1)
WCFG_SIZE       equ 3
WS_CENTRE       equ %00001      ; slot masks: the centre slot (key 1),
WS_PYLONS       equ %11110      ;   the wing pylons (keys 2-5),
WS_ANY          equ %11111      ;   any slot
WS_LINK_L       equ 1<<WPN_LINK_L   ;   the linked chain guns' own slots
WS_LINK_R       equ 1<<WPN_LINK_R

; Machine gun rounds: NBULLETS records of BREC bytes in `bullets`
NFIRE           equ 2           ; the last are a lich's fireballs'
NBULLETS        equ 24+NFIRE    ; rounds in flight (the chain gun needs most)
BREC            equ 32
B_STATE         equ 0           ; 0 free, 1 in flight, 2 hit (shown, then freed),
                                ; 3 laser beam; bit 7: fresh (fired this frame)
B_X             equ 1           ; position, world units
B_Y             equ 3
B_Z             equ 5
B_SIN           equ 7           ; heading sinY, cosY (S7.8) when fired
B_COS           equ 9
B_SLOPE         equ 11          ; tan(pitch) when fired (S7.8)
B_S             equ 13          ; horizontal distance per frame
B_PX            equ 15          ; start of this frame's path (drawn from here
B_PY            equ 17          ; to the position; the muzzle on its first)
B_PZ            equ 19
B_TDX           equ 21          ; path distance between x / z cell boundaries
B_TDZ           equ 23          ; (0 = not worked out yet)
B_DMG           equ 25          ; damage to a zombie it hits directly
B_KIND          equ 26          ; 0 = round or beam, BK_ROCKET = rocket,
BK_ROCKET       equ 1           ; BK_MISSILE = missile (both burst)
BK_MISSILE      equ 2
BK_AUTOCANNON   equ 3           ; an autocannon shell: drawn as a round, bursts
BK_PROX         equ 4           ; a proximity shell: as autocannon, and bursts
                                ; passing near a monster (PROX_R)
BK_BOMB         equ 5           ; a bomb: dives, drawn as a rocket, bursts
BK_FIREBALL     equ 6           ; a lich's fireball: lich_update, weapons.asm
B_TGT           equ 27          ; a missile: the monster it tracks ($FF none);
                                ; a bomb: its length along its path a frame;
                                ; a fireball: its frames left
B_YAW           equ 28          ;   its heading, 8.8 (yaw units: 256 a turn)
B_PIT           equ 30          ;   and climb, 8.8 signed (as pitch)
NOMINAL_FPS     equ 14          ; frame rate the per-frame speeds assume
BULLET_MS       equ 500         ; muzzle velocity, m/s
BULLET_STEP     equ BULLET_MS*TILE_UNITS/(TILE_M*NOMINAL_FPS)  ; 457 units/frame
GUN_DY          equ -6          ; muzzle 0.5 m below the camera
GUN_INTERVAL    equ 4           ; machine gun: frames between rounds
; Chain gun: 4x the machine gun's rate, one round every CHAIN_INTERVAL
; frames.  Each round's heading and climb are turned by a random
; -CHAIN_DEV..+CHAIN_DEV steps of 1/256 rad (0.22 deg): +/-0.9 degrees
; (half the +/-2 it was, 9 steps, 2026-11-10: 4.5 can't be).
CHAIN_INTERVAL  equ 1           ; chain gun: frames between rounds
; Linked chain guns (WPN_LCHAIN_L / _R, slots WPN_LINK_L / _R only): chain
; guns, firing straight ahead (no centre gun tilt) from LINK_OFF to the
; left / right of the centre line.  Either selected fires every one fitted.
; Their gunsights: one crosshair each, in place of the centre one
; (sight_mask), where its rounds are SIGHT_RANGE ahead: LINK_SIGHT_DX either
; side of the view's centre, GUN_SIGHT_DY below it; each moved by its own aim
; assist (aim_probe, as the centre gun's).
LINK_OFF        equ 26          ; 2 m (25.6 units)
LINK_SHOTS      equ 200         ; rounds each
LINK_RELOAD     equ 1           ; frames a round, reloading on the pad
; The gunsights show where the rounds are SIGHT_RANGE ahead (the projection:
; 128 pixels * offset / distance): the muzzles are GUN_DY below the camera
; (and the linked guns LINK_OFF to the side), so the crosshairs sit that
; much off the view's centre, more the nearer the range.
SIGHT_RANGE     equ 640         ; 50 m (12.8 units a metre)
GUN_SIGHT_DY    equ (128*(-GUN_DY) + SIGHT_RANGE/2) / SIGHT_RANGE  ; 1 pixel down
LINK_SIGHT_DX   equ (128*LINK_OFF + SIGHT_RANGE/2) / SIGHT_RANGE   ; 5 pixels
        ASSERT GUN_SIGHT_DY == 1 && LINK_SIGHT_DX == 5
; Centre gun tilt (gun_tilt, signed, 256 = 360 deg): R / F tilt the centre
; slot's weapon up / down GUN_TILT_STEP a frame, at most GUN_TILT_UP up
; (11: 15.5 deg, the nearest step to 15) and GUN_TILT_DN down (32: 45 deg);
; V brings it back to the centre at twice the rate.  Its rounds (and laser)
; fire at pitch + tilt; the gunsight moves to show where (sight_y).
GUN_TILT_STEP   equ 1           ; 1.4 deg a frame
GUN_TILT_UP     equ 11
GUN_TILT_DN     equ 32
GUN_CTR_STEP    equ 2*GUN_TILT_STEP
SIGHT_MARGIN    equ 6           ; the gunsight's arms stay in the view
; Integrity panel (hud.asm draw_integrity): under the weapon bars,
; "INTEGRITY" on character row INT_ROW, the VTOL's hit points as a
; percentage below it (INT_ROW+1)
INT_ROW         equ 22
INT_COL         equ 11              ; the label's column (under the slots)
INT_PCT_COL     equ 12              ; "nnn%" from this column
INT_WARN        equ 50              ; below this percentage: amber,
INT_DANGER      equ 25              ;   below this: red (else green)
CHAIN_DEV       equ 4           ; spread: 4/256 rad = 0.90 degrees
; Aim assist (aim_assist, weapons.asm): a centre slot shot, or a linked
; chain gun's (each from its own muzzle, on its own), turns to the middle
; of the nearest monster within AIM_DEV steps of 1/256 rad either way of it,
; as long as the monster was drawn last frame.  The view's 256 headings are
; 1.4 degrees apart, so without it a far monster can lie between two of them.
AIM_DEV         equ 8           ; 8/256 rad = 1.8 degrees: tune this
AIM_COLS        equ AIM_DEV/2+12    ; only monsters drawn this near the gun's
                                    ; crosshair column are measured: the cone,
                                    ; then a frame's turn and a close one's box
        ASSERT AIM_DEV > 0 && AIM_DEV < 64
; Pulse laser: the beam is on for LASER_ON frames (0.1 s), then cools for
; LASER_COOL frames (0.25 s) before it can fire again; holding SPACE repeats.
; (Frame counts as specified; at 14 fps they last 0.21 s and 0.57 s.)  Each
; beam frame it is traced from the muzzle along the view direction to the
; first thing it meets, at most LASER_RANGE away.
LASER_ON        equ 3           ; beam frames
LASER_COOL      equ 8           ; cool-down frames
LASER_RANGE     equ 1536        ; 120 m (the draw distance)
ZHIT_R          equ 3           ; zombie hit box: 0.5 m wide (half 3.2 units)
ZHIT_H          equ 26          ; and 2 m tall

; Damage, in hit points (zombies: ZHP / ZHP_FAST in zombie.asm; the base
; tiles TERRACE_HP / PAD_HP; humans HUMAN_HP)
GUN_DMG         equ 4           ; machine gun, per round
CHAIN_DMG       equ 2           ; chain gun, per round
LASER_DMG       equ 1           ; pulse laser, per beam frame on a target

; Rocket pod (WPN_ROCKETS, on a wing pylon): ROCKET_SHOTS rockets, one every
; ROCKET_INTERVAL frames while SPACE is held, flying straight along the view
; direction at 150 m/s.  Where one hits anything (a building, the ground, a
; zombie) it bursts: BLAST_DMG to every zombie, human and base tile within
; BLAST_R on each of the x, y and z axes (a box, not a sphere: cheaper, and
; near enough).  A direct hit does no extra damage.
ROCKET_SHOTS    equ 12          ; a full pod
ROCKET_MS       equ 150         ; m/s
ROCKET_STEP     equ ROCKET_MS*TILE_UNITS/(TILE_M*NOMINAL_FPS)  ; 137 units/frame
ROCKET_INTERVAL equ 7           ; frames between rockets (0.5 s)
ROCKET_LEN      equ 13          ; drawn 1 m long (white),
ROCKET_TRAIL    equ 19          ; then a yellow trail to 1.5 m behind it
BLAST_R         equ 64          ; 5 m
BLAST_DMG       equ 20
BLAST_PARTS     equ 10          ; its burst: orange particles (FIRE_LIFE frames)

; Missile pod (WPN_MISSILE, on a wing pylon): MISSILE_SHOTS missiles, fired
; and flying as rockets but at half the speed (75 m/s).  The burst is bigger:
; MISSILE_DMG to everything within MISSILE_R (1.0 tile) on each of the x, y
; and z axes, and MISSILE_PARTS orange particles.
MISSILE_SHOTS   equ 4           ; a full pod
MISSILE_MS      equ ROCKET_MS/2 ; m/s
MISSILE_STEP    equ MISSILE_MS*TILE_UNITS/(TILE_M*NOMINAL_FPS)  ; 68 units/frame
MISSILE_INTERVAL equ ROCKET_INTERVAL    ; frames between missiles
MISSILE_R       equ TILE_UNITS  ; 1.0 tile (20 m)
MISSILE_DMG     equ 15
MISSILE_PARTS   equ 20
; Bomb (WPN_BOMB, on a wing pylon): BOMB_SHOTS bombs.  Released straight
; ahead at the VTOL's speed + BOMB_SPEED units a frame (at least 1), it
; glides down from BOMB_ANGLE (10 degrees below level), steeper by one angle
; step (1.4 degrees) every BOMB_STEEPEN frames (to MSL_PITCH_MAX), its speed
; kept, until it hits something (a building, a monster, the ground).  Its
; burst does BOMB_DMG to everything within BOMB_R (2 tiles) on each of the
; x, y and z axes, the VTOL too (and the terrace, barricades and pad), and
; sprays BOMB_PARTS particles.
BOMB_SHOTS      equ 1           ; a pod holds one
BOMB_RELOAD     equ 30          ; frames to reload it on the pad
BOMB_INTERVAL   equ 14          ; frames between bombs (about a second)
BOMB_SPEED      equ 20          ; units a frame more than the VTOL's speed
BOMB_ANGLE      equ 7           ; 10 degrees below level at the start: 7
                                ; angle steps of 1.4 (9.8 degrees)
BOMB_STEEPEN    equ 5           ; frames between steps steeper
BOMB_R          equ 2*TILE_UNITS    ; 2 tiles (40 m)
BOMB_DMG        equ 30
BOMB_PARTS      equ 30
; A lich's fireballs (lich_update, weapons.asm): at FB_MS, up to FB_RANGE
; (10 tiles), bursting for FB_DMG within FB_R (5 m) on each axis
FB_MS           equ 200         ; m/s
FB_STEP         equ FB_MS*TILE_UNITS/(TILE_M*NOMINAL_FPS)  ; 182 units/frame
FB_RANGE        equ 10*TILE_UNITS   ; 200 m: its flight, and the lich's range
FB_FRAMES       equ (FB_RANGE+FB_STEP/2)/FB_STEP    ; 14
FB_R            equ 5*TILE_UNITS/TILE_M ; 5 m: 64 units
FB_DMG          equ 10
FB_PARTS        equ 15
FB_DEV          equ 7           ; its spread: 7/256 rad = 1.57 degrees
FB_HIT_R        equ 24          ; it hits the VTOL this near its path: 1.9 m
        ASSERT FB_FRAMES <= NFIRE*LICH_RATE_MIN ; (a record free for each shot)
LICH_HP_HI      equ 23          ; a lich's record: its hit points' high byte,
LICH_WAIT       equ 24          ;   frames to its next shot,
LICH_FRAMES     equ 25          ;   frames between shots
LICH_MOUTH      equ 3*LICH_H/4  ; fireballs start this high: its head
; Missile lock (lock_update, weapons.asm): with the missile pod selected, a
; square reticule wanders near the view's centre (RET_WANDER_R) until a
; monster is seen within LOCK_RANGE
; tiles; it then moves to it (RET_STEP pixels a frame), and after LOCK_TIME
; frames on it the target is locked (the lock tone).  A missile fires only
; with a lock.  It leaves straight ahead, then turns towards its target at
; MISSILE_TURN a frame (3 degrees), sideways and up or down; if the target
; is more than LOCK_RANGE tiles away (along x or z) it stops tracking and
; flies straight on.
LOCK_RANGE      equ 8*TILE_UNITS    ; 8 tiles (160 m)
LOCK_TIME       equ 2*NOMINAL_FPS   ; frames on the target to lock (2 s)
MISSILE_TURN    equ 546         ; 3 degrees a frame (8.8: 3*256*256/360)
MSL_PITCH_MAX   equ 56          ; its climb kept within +-79 degrees
MSL_AIM_Y       equ ZOMBIE_H/2  ; aimed at the target's middle (feet + 1 m)
RET_HALF        equ 6           ; the reticule: a square 2*RET_HALF+1 wide
RET_STEP        equ 4           ;   pixels a frame moving to a target
RET_WANDER      equ 2           ;   and wandering,
RET_WANDER_R    equ 40          ;   within this many pixels of the view's
                                ;   centre (along x and y) until it sees one
LOCK_NEAR       equ 3           ;   on the target within this many pixels

; Autocannon (WPN_AUTOCANNON, on a wing pylon): AUTOCANNON_SHOTS shells,
; fired as the machine gun's rounds (500 m/s, drawn as tracers) at a quarter
; of its rate.  Each shell bursts where it hits anything: AUTOCANNON_DMG to
; everything within AUTOCANNON_R (3 m) on each axis, and AUTOCANNON_PARTS
; orange particles.
AUTOCANNON_SHOTS equ 50         ; a full magazine
AUTOCANNON_INTERVAL equ GUN_INTERVAL*4  ; frames between shells (16)
AUTOCANNON_R    equ 3*TILE_UNITS/TILE_M ; 3 m: 38 units
AUTOCANNON_DMG  equ 4
AUTOCANNON_PARTS equ 3

; Proximity cannon (WPN_PROX, on a wing pylon): the autocannon, but its
; shells also burst when they pass within PROX_R (2 m) of a zombie or
; special monster, on each axis from its x, z and feet (cell_zombies: the
; burst's own box, so the monster is always in it), where the shell comes
; nearest it.  The burst: PROX_DMG within PROX_R on each axis.
PROX_SHOTS      equ AUTOCANNON_SHOTS
PROX_INTERVAL   equ AUTOCANNON_INTERVAL
PROX_R          equ 2*TILE_UNITS/TILE_M ; 2 m: 25 units
PROX_DMG        equ 3
PROX_PARTS      equ AUTOCANNON_PARTS

; Landed on the base pad (vtol_landed, the cell under it PAD_CODE) the VTOL
; is repaired and its pods reloaded (pad_service, weapons.asm): 1 hit point
; every REPAIR_FRAMES frames up to VTOL_HP, and each slot's weapon 1 shot
; every its reload frames (wpn_cfg, WCFG_RELOAD) up to its full load.
REPAIR_FRAMES   equ 5
ROCKET_RELOAD   equ 15          ; frames a rocket
MISSILE_RELOAD  equ 30          ; frames a missile
AUTOCANNON_RELOAD equ 7         ; frames an autocannon shell
PROX_RELOAD     equ AUTOCANNON_RELOAD   ; and a proximity shell

; Humans to rescue (human.asm)
HUMAN_MAX       equ 20          ; room for this many
HUMANS_INIT     equ 5           ; placed at start
PASSENGER_MAX   equ 5           ; the craft carries this many
RESCUE_R        equ 512         ; 2.0 tiles (40 m): a landed craft this close
HUMAN_ROOF_MAX  equ HEIGHT_UNITS/2  ; humans aren't placed on roofs taller
                                ; than 0.5 height units (level 1's)
HUMAN_RUN       equ TILE_UNITS*10/(TILE_M*NOMINAL_FPS)  ; 10 m/s: 9 units/frame
HUMAN_HP        equ 10          ; hit points (a rocket blast kills)
WAVE_R          equ 4*TILE_UNITS    ; 80 m: the VTOL this near (x and z), a
                                ; waiting human waves; farther, stands
FLEE_R          equ TILE_UNITS  ; 20 m: a monster this near (x and z), a
                                ; human on the road runs from it
FLEE_TIME       equ NOMINAL_FPS ; for this many frames (a second), then
                                ; looks again
FLEE_EVERY      equ 4           ; a standing human looks for monsters
                                ; every this many frames (staggered)
HUMAN_FLEE      equ HUMAN_RUN   ; units a frame (10 m/s)
VTOL_HP         equ 50          ; the VTOL's hit points (ghosts attack it)
; At 0 hit points the VTOL is destroyed (vtol_dead): out of control, it
; spins DEAD_SPIN (8.8 yaw) a frame as it falls, faster each frame up to
; DEAD_FALL_MAX units, until it hits the ground (the road or roof under it).
; DEAD_PAUSE frames later the game is over: the GAME OVER screen, then the
; main menu.
DEAD_SPIN       equ $0800           ; 8 yaw units a frame: a turn in 32
DEAD_FALL_MAX   equ 8               ; units a frame (11 m/s at 14 fps)
DEAD_PAUSE      equ 50              ; frames on the ground before GAME OVER (was 100)
; The crash (wreck_fx, weapons.asm): fire bursts (fire_burst) WRECK_AHEAD in
; front of the camera, so they're seen: WRECK_BOOM particles as it is
; destroyed (and a shake), WRECK_DEBRIS every other frame as it falls (the
; spin trails them round the view), WRECK_IMPACT and the heavy shake
; (shake_big) when it hits the ground, then WRECK_EMBERS every 4th frame
; until GAME OVER.
WRECK_AHEAD     equ 48              ; 3.75 m (past NEAR)
WRECK_BOOM      equ 24
WRECK_DEBRIS    equ 3
WRECK_IMPACT    equ 32
WRECK_EMBERS    equ 2
WRECK_DROP      equ 26              ; the debris 2 m below the eye,
WRECK_EYE       equ 6               ;   the explosion 0.5 m
WRECK_LOW       equ 4               ;   but never under this (the ground)
        ASSERT WRECK_AHEAD > NEAR && WRECK_IMPACT <= NPART
DISEMBARK       equ NOMINAL_FPS ; landed on the base pad: one off a second

; Particles (weapons.asm moves them, city.asm draws them).  A killed zombie
; sprays NPART_BURST for PART_LIFE frames, bright green fading to dark; a
; rocket or missile burst sprays orange ones (FIRE_COL0..) for FIRE_LIFE
; frames.  Particle record: +0 age (0 = free, 1..its life), +1..+6 x, y, z
; (world units), +7..+9 vx, vy, vz (signed units per frame), +10 its colour
; at age 1 (each age after is 4 palette entries on), +11 its life (frames).
NPART           equ 60          ; pool: a missile burst and 4 zombie bursts
NPART_BURST     equ 10
PART_LIFE       equ 8
FIRE_LIFE       equ 10
PREC            equ 12
PART_Y          equ 13          ; bursts from 1 m up
PART_GRAV       equ 1           ; vy lost per frame (they arc up and fall)

; The level a new game starts on: 1 (for testing, another level with
; -DSTART_LEVEL_SET=n on the command line)
    IFDEF START_LEVEL_SET               ; (command line: -DSTART_LEVEL_SET=n)
START_LEVEL     equ START_LEVEL_SET
    ELSE
START_LEVEL     equ 1
    ENDIF
; The salvage a new game starts with (newGame, game_reset).  The rewards at
; or below it (salvage_tab, menu.asm) are never given: only totals passed
; after it count.  Always 0 in a release.
    IFDEF RELEASE
START_SALVAGE   equ 0
    ELSE
START_SALVAGE   equ 0
    ENDIF

; DEBUG_UNLOCK_ALL: a new game starts with every upgrade the salvage gives
; (game_reset): the booster module (its tank full), the vertical thrusters
; and all three vision modes.  Weapons: DEBUG_LOADOUT.  Off in a release.
; Command line: -DDEBUG_UNLOCK_ALL
    IFNDEF RELEASE
        DEFINE DEBUG_UNLOCK_ALL
    ENDIF

; Debug: key 0 kills every monster and rescues every human left, so the
; next wave starts (after the last, the level ends); key 9 the same, on to
; the next level; key 8 the same, on to the final boss (the last level's
; last wave).  Key 7 changes the centre gun.  Off in a release.
    IFDEF RELEASE
DEBUG_KILLALL   equ 0
    ELSE
DEBUG_KILLALL   equ 1
    ENDIF

; Debug: a new game starts with every weapon unlocked and DEBUG_STOCK of each
; in store, to try them on the load-out screen.  Off in a release.
    IFDEF RELEASE
DEBUG_LOADOUT   equ 0
    ELSE
DEBUG_LOADOUT   equ 1
    ENDIF
DEBUG_STOCK     equ 4

; Zombies against the base (zombie.asm)
ZBIAS_BASE      equ 48          ; junction bias towards the pad, percent:
ZBIAS_STEP      equ 2           ; 48 + 2 * level (50% on level 1),
ZBIAS_MAX       equ 95          ; at most 95%
ATTACK_R        equ 26          ; a zombie attacks a base tile from 0.1 tile (2 m)
ZHIT_FRAMES     equ 5           ; one hit every 5 frames, 1 damage each
TERRACE_HP      equ 100         ; hit points of each green terrace tile
NBARR           equ 30          ; barricades (terrace away from the base): at
BARR_REC        equ 3           ;   most this many, each x, z, hit points
                                ;   (barr_tab; TERRACE_HP each)
PAD_HP          equ 200         ; and of the landing pad (destroyed: game over)

BLD_SIZE        equ 256         ; buildings fill their whole grid cell;
                                ; streets are the empty cells

; Layer 2 colours (RRRGGGBB). Avoid $E3 (global transparency).
; Layer 2 uses a custom palette (l2_palette from gentables.py) arranged in
; families of four: family*4 + SHADE_*.  The +3 slots hold the fixed colours.
SKY_COL         equ 3
GROUND_COL      equ 7
EDGE_COL        equ 11
HUD_COL         equ 15
HUD_WARN        equ 19
DOT_COL         equ 23
ROCKET_COL      equ EDGE_COL    ; rockets: white streak,
TRAIL_COL       equ BULLET_COL  ; yellow trail
FB_COL          equ FIRE_COL2   ; a lich's fireball, and its trail
FB_TRAIL_COL    equ FIRE_COL6
FB_TRAIL        equ 26          ; 2 m behind it
BULLET_COL      equ 31
LASER_COL       equ 35
DEVIL_EYE       equ 171         ; the devil's eyes (set as they charge: devil.asm)
DEVIL_COL0      equ 188         ; the devil's own colours (family 47): white,
DEVIL_COL1      equ 189         ;   pale blue,
DEVIL_COL2      equ 190         ;   blue,
DEVIL_COL3      equ 191         ;   its dark blue outline (black in thermal)
BOLT_COL        equ 175         ; its lightning: the core,
BOLT_COL2       equ 179         ;   and the glow
MAP_BG          equ 39
MAP_ZOMBIE      equ HUD_COL     ; zombie blips on the city map: bright green
HUMAN_COL       equ 43
HUMAN_BLIP      equ 47          ; humans on the city map: bright blue,
HUM_FLASH       equ 2           ;   on this many frames, off as many (half
                                ;   the VTOL's dot's rate: 2 on, 2 off)
MAP_ZOMBIE_MID  equ 51          ; zombie blip shades (bright = MAP_ZOMBIE)
MAP_ZOMBIE_DARK equ 55
MAP_ZOMBIE_ATK  equ HUD_WARN    ; a zombie attacking the base: red
ZOMBIE_COL      equ 27
PANEL_L2        equ 91          ; (unused: was the ULA panel colour)
GAUGE_AMBER     equ 95          ; ground height gauge (Layer 2)
GHOST_COL       equ 99          ; ghosts (white); their map blip's first shade
MAP_GHOST_MID   equ 103         ; ghost map blip shades: light grey,
MAP_GHOST_DARK  equ 107         ; grey
GHOST_FADE      equ 111         ; dark grey: a dying ghost's last fade step
BANSHEE_COL     equ 115         ; banshees (yellow); their map blip's first shade
MAP_BANSHEE_MID equ 119         ; banshee blip shades and fade steps
MAP_BANSHEE_DARK equ 123
BANSHEE_FADE    equ 127         ; a dying banshee's last fade step
PART_COL0       equ 59          ; zombie burst particles: age 1 (bright) ..
PART_COL1       equ 63
PART_COL2       equ 67
PART_COL3       equ 71
PART_COL4       equ 75
PART_COL5       equ 79
PART_COL6       equ 83
PART_COL7       equ 87          ; .. age 8 (dark); a step of 4 per age
FIRE_COL0       equ 131         ; rocket / missile burst particles: age 1
FIRE_COL1       equ 135
FIRE_COL2       equ 139
FIRE_COL3       equ 143
FIRE_COL4       equ 147
FIRE_COL5       equ 151
FIRE_COL6       equ 155
FIRE_COL7       equ 159
FIRE_COL8       equ 163
FIRE_COL9       equ 167
                                ; (yellow-orange) .. age 10 (FIRE_COL0+36,
                                ; dark red-brown), a step of 4 per age

; Screen split: the 3D viewport is Layer 2, top two thirds (256x128, rows
; 0-127).  The bottom third (rows 128-191) is an instrument panel drawn on the
; ULA (Layer 1), which sits above Layer 2.  The ULA screen (bank 5) stays
; paged in at $8000 (slot 4): bitmap ULA_BMP, attributes ULA_ATTR.
VIEW_H          equ 128         ; viewport height
VIEW_CY         equ 64          ; viewport centre row
ULA_BMP         equ $8000
ULA_ATTR        equ $9800

; ULA palette indices used by the panel (custom colours set in ula_init)
P_PANEL         equ 1           ; paper: panel background
C_WARN          equ 3           ; ink/paper: red (reversing)
C_OK            equ 4           ; ink/paper: green
C_YEL           equ 2           ; ink: yellow (weapon slot flash)
C_GROOVE        equ 5           ; ink: light grey (the panel's grooves)
C_TRIM          equ 1           ; ink: dark green (the panel's lines, labels)
C_AMBER         equ 6           ; ink/paper: amber (weapon slot flash)
P_EMPTY         equ 2           ; paper: black (an empty gauge, an unused slot)
ATTR_PANEL      equ P_PANEL<<3 | 7

; Gauges: vertical bars on Layer 2 behind transparent ULA cells, filled
; from the bottom, pixel rows GAUGE_TOP..GAUGE_TOP+GAUGE_H-1 (character rows
; 17-22), labelled on character row 23.  Speed ("S") is 8 pixels wide at
; character column SPD_GCOL; altitude and ground height ("A") share the cell
; column ALT_GCOL, 4 pixels each.
GAUGE_TOP       equ 136
GAUGE_H         equ 48
GAUGE_LROW      equ 23              ; label row
SPD_GCOL        equ 1
ALT_GCOL        equ 3
BST_GCOL        equ 5               ; the booster's fuel ("B"), once fitted
; (The compass is a bar of hardware sprites: hud_sprites.asm)
WPN_NUM_ROW     equ 17              ; the weapon slots, each a column from
WPN_ROW         equ WPN_NUM_ROW+1   ; WPN_COL0, every 2nd: its slot number,
WPN_BAR         equ 3               ; an 8x24 bar of its ammo, one digit a row,
WPN_LTR_ROW     equ WPN_ROW+WPN_BAR ; then its weapon's letter
WPN_COL0        equ 11
WFLASH          equ 5               ; empty slot requested: flash frames

; City map on the right of the panel: 32x32 cells at 2x2 pixels = 64x64,
; pixel columns MAP_X..MAP_X+63, rows 128..191.  North (+Z) is up.
MAP_X           equ 192
MAP_COL         equ MAP_X/8
SHADE_DARK      equ 0           ; side turned away from the player
SHADE_FACE      equ 1           ; side facing the player (base colour)
SHADE_ROOF      equ 2           ; roof, lighter

; Layer 2 banks (L2_BANK_A / _B) and the 8K pages: memory_bank_defs.asm


; zxnDMA WR0 (transfer A->B) with only the length low / high byte following
DMA_WR0_LEN_LO  equ %00100101
DMA_WR0_LEN_HI  equ %01000101

; Self-modified opcodes for the line drawer
OP_INC_L        equ $2C
OP_DEC_L        equ $2D
OP_INC_H        equ $24
OP_DEC_H        equ $25
; and for scale_comp's barrel shift (the second byte, after $ED: zpatch)
OP_BSLA         equ $28             ; bsla de,b
OP_BSRL         equ $2A             ; bsrl de,b

; HL = HL * GRID  (a map row offset)
; DE = -DE (vproj)
        MACRO NEG_DE
        xor a
        sub e
        ld e,a
        sbc a,a
        sub d
        ld d,a
        ENDM

; HL = n (>= 0), BC = R (zpatch's reciprocal for Z) -> A = round(n * 128 /
; Z) as scale_comp, after its shift: n over 511 clamped; P = n_lo R / 256 +
; 256 (the rounding, first: at most 65535), plus R if bit 8 of n is set (the
; carry bit 16); A = bits 9-16 of P.  Uses DE.  (vproj)
        MACRO VP_SCALE
        ld a,h
        cp 2
        jr c,$+5
        ld hl,511
        ld d,l
        ld e,c
        mul d,e                         ; n_lo Rl
        ld a,d
        ld d,l
        ld e,b
        mul d,e                         ; n_lo Rh
        add a,e
        ld e,a
        ld a,d
        adc a,1
        ld d,a                          ; DE = n_lo R / 256 + 256, carry 0
        bit 0,h
        jr z,$+5
        ex de,hl
        add hl,bc                       ; + 256 n_hi R / 256: carry = bit 16
        ex de,hl
        ld a,d
        rra
        ENDM

; The cell walks' call of try_cell (draw_row, occ_row), skipped for a cell
; whose centre (the walk's yaw-space X, Z1 in HL', DE') is surely out of
; view: in level flight |X| - Z1 >= WALK_R (outside the left or right
; edge), pitched Z1 < -WALK_R (behind: no multiply by draw_bld's cull_c).
; WALK_R is over draw_bld's BLD_R, so every building it skips draw_bld
; would reject, and the 64 over leaves room for a figure standing at a
; street cell's edge (an off-screen figure draws nothing and notes
; nothing: fig_draw returns before fig_seen).  The walk still steps every
; cell, so the cells drawn have the same positions.  Uses A, BC'.
WALK_R          equ 320
        MACRO WALK_TRY
        exx
        ld a,(pitch)
        or a
        jr nz,.pt
        ld b,h
        ld c,l
        bit 7,b
        jr z,.ap
        xor a
        sub c
        ld c,a
        sbc a,a
        sub b
        ld b,a                          ; |X|
.ap:    ld a,c
        sub e
        ld c,a
        ld a,b
        sbc a,d
        ld b,a                          ; |X| - Z1
        ld a,c
        sub low WALK_R
        ld a,b
        sbc a,high WALK_R
        exx
        jp p,.out                       ; |X| - Z1 >= WALK_R
        jr .try
.pt:    ld a,e
        add a,low WALK_R
        ld a,d
        adc a,high WALK_R
        exx
        jp m,.out                       ; Z1 + WALK_R < 0
.try:   call try_cell
.out:
        ENDM

        MACRO ROWOFS
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ENDM

; A building's 8 corners (vtx, 16 bytes each; index = x + 2*z + 4*top) from
; corner 0, component C (0 X, 2 Y, 4 Z) at a time: v1 = v0 + vx, v3 = v1 +
; vz, v2 = v0 + vz (vx, vz: vecs0, its edge vectors), and each top corner
; its bottom corner + vy (vy_vec, the vertical edge).  The sums the corners
; share are made once, in registers (draw_bld, city.asm).
        MACRO VBOX C
        ld hl,(vtx+C)                   ; v0
        ld de,(vecs0+C)                 ; vx
        ld bc,(vecs0+6+C)               ; vz
        push hl
        add hl,de
        ld (vtx+16+C),hl                ; v1 = v0 + vx
        push hl
        add hl,bc
        ld (vtx+48+C),hl                ; v3 = v1 + vz
        ld de,(vy_vec+C)                ; vy
        add hl,de
        ld (vtx+112+C),hl               ; v7 = v3 + vy
        pop hl
        add hl,de
        ld (vtx+80+C),hl                ; v5 = v1 + vy
        pop hl
        add hl,bc
        ld (vtx+32+C),hl                ; v2 = v0 + vz
        add hl,de
        ld (vtx+96+C),hl                ; v6 = v2 + vy
        ld hl,(vtx+C)
        add hl,de
        ld (vtx+64+C),hl                ; v4 = v0 + vy
        ENDM
; The same for a component of vy that is 0 (X always; Z in level flight):
; each top corner is its bottom corner
        MACRO VBOX0 C
        ld hl,(vtx+C)                   ; v0
        ld (vtx+64+C),hl                ; v4 = v0
        ld de,(vecs0+C)
        ld bc,(vecs0+6+C)
        push hl
        add hl,de
        ld (vtx+16+C),hl                ; v1 = v0 + vx
        ld (vtx+80+C),hl                ; v5
        add hl,bc
        ld (vtx+48+C),hl                ; v3 = v1 + vz
        ld (vtx+112+C),hl               ; v7
        pop hl
        add hl,bc
        ld (vtx+32+C),hl                ; v2 = v0 + vz
        ld (vtx+96+C),hl                ; v6
        ENDM

; Copy cached screen corner of face vertex (HL)+ into p2buf (DE)+ with the
; outline flag for edge bit EB taken from df_mask.  B = high vtx.
        MACRO FACEVTX EB
        ld a,(hl)
        inc hl
        add a,7
        ld c,a
        ld a,(bc)
        ld (de),a
        inc e
        inc c
        ld a,(bc)
        ld (de),a
        inc e
        ld a,(df_mask)
        and EB
        ld (de),a
        inc e
        inc e
        ENDM

;==============================================================================
; NEX entry: the loader leaves its default mapping (slot 6 = page 0, slot 5
; = page 5), so the entry point is this stub in PAGE_BOOT at $C000.  It maps
; the resident page into slot 5 and jumps to start.
;==============================================================================
        MMU BOOT_SLOT e, PAGE_BOOT, BOOT_ADDR
        ORG BOOT_ADDR
boot:
        di
        ld sp,boot_stack
        nextreg MAIN_MMU,PAGE_MAIN
        jp start
boot_stack_bottom:        
            ds 16                       ; the loader's stack, until start
boot_stack:

        MMU MAIN_SLOT e, PAGE_MAIN, MAIN_ADDR
        ORG MAIN_ADDR
        ; the generated tables (gentables.py); the sine table is in its own
        ; page (PAGE_SIN, slot 0), below
        INCLUDE "htabs.asm"             ; hztab (horizon), htab (heights)
        INCLUDE "city_map.asm"          ; city_map, base / wall constants
        INCLUDE "l2_pallets.asm"        ; (checks on the fixed colour slots)
        INCLUDE "levels.asm"            ; the current level's record
        INCLUDE "text.asm"              ; text screens: menu, load-out
        INCLUDE "layer2_cls.asm"        ; zxnDMA equates, the fill block, dma_fill

;==============================================================================
; Entry
;==============================================================================
start:
        di
        ld sp,stack_top
        nextreg CODE_MMU,PAGE_INIT      ; hardware set-up and memory map
        call initgame                   ; (initialise.asm)
        nextreg CODE_MMU,PAGE_AUDIO     ; the AY chips silent, stereo
        call init_audio                 ; (audio.asm)
        call im2_init                   ; I -> the IM 2 vector table, IM 2
                                        ; (interrupts.asm; still disabled)
        nextreg CODE_MMU,PAGE_FILE      ; the SD card's default drive
        call fh_init                    ; (file_handler.asm)
    IFDEF REAL_HARDWARE
        ld hl,sg_home                   ; the save game's folder, made if it
        call fh_mkdir                   ; isn't there (/home first: the
        ld hl,sg_folder                 ; folder's parent must be; an error,
        call fh_mkdir                   ; it's there already, is fine)
    ENDIF
        nextreg LOGIC_MMU,PAGE_LEVEL    ; the figures' graphics
        call gfx_load                   ; (level_load.asm)
        nextreg LOGIC_MMU,PAGE_KEYDEF   ; the saved key and joystick
        call kd_load                    ; definitions, if any (keydef.asm)
        ; (the Layer 2 palette: each city's own, loaded with the level)

        ld a,r                          ; random seed (xorshift: non-zero);
        ld l,a                          ; the menu stirs it every frame
        ld h,$A5
        ld (zseed),hl
        nextreg L320_MMU,PAGE_L320      ; the fonts' files, if any (layer2-
        call fonts_load                 ; 320x256.asm; after the seed: R
        nextreg OCC_MMU,PAGE_OCC0       ; counts the code before it)
        nextreg CODE_MMU,PAGE_INPUT     ; the extended keys only in their own
        call kbd_double_on              ; banks (BREAK, the pause key, not
                                        ; also CAPS SHIFT + SPACE, fire)
        nextreg CODE_MMU,PAGE_HUD
        call ula_palette                ; ULA inks and papers (menu and HUD)
        nextreg CODE_MMU,PAGE_SPRITES
        call sprites_init               ; (sprites.asm) on, all hidden
        nextreg CODE_MMU,PAGE_SPR0      ; sprite bank 0: the human status
        call spr_load_bank              ; sprites (sprite_data.asm)
        ei                              ; interrupts on, from now on (the
                                        ; engines' sound: interrupts.asm)
        jp menu_go                      ; the main menu -> newGame

;==============================================================================
; New game: start level 1.  Start-up has set the hardware (speed, layers,
; clip window, palettes, memory map), which the menu leaves alone; here the
; game state and the screen contents are set up from scratch, so this also
; works for a second game.
;==============================================================================
newGame:
        ld sp,stack_top                 ; (entered by jp from the menu)
        call game_reset
        jp loadout_go                   ; the load-out screen first, then the
                                        ; first level (next_level)

; A new game's state: the player, weapons, store, salvage, booster (and the
; debug load-out), level START_LEVEL.  (CONTINUE lays a save game over it:
; continue_game.)
game_reset:
        call shake_off
        ld hl,start_state               ; player, weapon slots, selection
        ld de,cam_x
        ld bc,start_state_end-start_state
        ldir
        ld hl,bullets                   ; no rounds or beam in flight
        ld de,bullets+1
        ld bc,(NBULLETS+1)*BREC+NPART*PREC-1    ; and no particles
        ld (hl),0
        ldir
        ld a,START_LEVEL
        ld (level),a
        ld a,VTOL_HP
        ld (vtol_hp),a                  ; the VTOL undamaged
        ld a,DEAD_PAUSE
        ld (dead_wait),a
        xor a
        ld (vtol_dead),a
        ld (dead_down),a
        ld (dead_vy),a
        ld hl,START_SALVAGE
        ld (salvage_points),hl          ; the salvage to start with
        ld hl,wpn_stock                 ; and no weapons in store or
        ld b,2*(WPN_LAST+1)             ; unlocked (wpn_unlocked follows)
.ws:    ld (hl),0
        inc hl
        djnz .ws
        ld hl,wpn_slots                 ; but those fitted at the start
        ld b,WPN_SLOTS
.wu:    ld a,(hl)
        ld de,wpn_unlocked
        add de,a
        ld a,1
        ld (de),a
        inc hl
        inc hl
        djnz .wu
        xor a
        ld (wpn_unlocked+WPN_NONE),a    ; (an empty slot isn't a weapon)
        ld (boost_fitted),a             ; no booster (a salvage reward)
        ld (boost_fuel),a
        ld (boost_on),a
        ld (vision_owned),a             ; no vision modes (salvage rewards)
        ld (vthrust_fitted),a           ; no vertical thrusters (salvage)
        ld (lthrust_fitted),a           ; nor lateral ones
        ld (vision_mode),a              ; normal vision
    IF DEBUG_LOADOUT
        ld hl,wpn_stock+1               ; debug: every weapon unlocked, and
        ld b,WPN_LAST                   ; DEBUG_STOCK of each in store
.dbg:   ld a,WPN_LAST+1
        sub b                           ; (the type)
        ld (hl),DEBUG_STOCK
        ld de,wpn_unlocked-wpn_stock
        add hl,de
        ld (hl),1
        or a
        sbc hl,de
.dbn:   inc hl
        djnz .dbg
        ld a,1                          ; and the booster fitted, full
        ld (boost_fitted),a
        ld a,BOOST_FUEL_MAX
        ld (boost_fuel),a
    ENDIF
    IFDEF DEBUG_UNLOCK_ALL
        ld a,1                          ; debug: every upgrade: the booster
        ld (boost_fitted),a             ; (full), the vertical and lateral
        ld (vthrust_fitted),a           ; thrusters, and the vision modes
        ld (lthrust_fitted),a
        ld a,BOOST_FUEL_MAX
        ld (boost_fuel),a
        ld a,VIS_NV_GREEN | VIS_NV_MONO | VIS_THERMAL
        ld (vision_owned),a
    ENDIF
        ret

;==============================================================================
; Start the level `level`: from the load-out screen, after newGame and after
; each level completed (level_complete_screen).  The VTOL goes back onto the base pad, level and
; still; its hit points, weapons and ammo carry on.  The level's files are
; loaded and everything in the city is set up afresh.
;==============================================================================
next_level:
        ld sp,stack_top
        call shake_off                  ; (a crash's shake cut short)
        ld hl,start_state               ; position, heading, pitch, speed
        ld de,cam_x
        ld bc,speed+1-cam_x
        ldir
        ld hl,bullets                   ; no rounds or beam in flight
        ld de,bullets+1
        ld bc,(NBULLETS+1)*BREC+NPART*PREC-1    ; and no particles
        ld (hl),0
        ldir
        ld a,(resume_wave)              ; the level's first zombie wave (or a
        ld (wave_number),a              ; save game's: continue_game)
        ld a,1
        ld (resume_wave),a              ; (once)
        xor a
        ld (boost_on),a                 ; (not boosting: start_state's speed)
        ld (level_done),a
        ld (game_over),a
        nextreg LOGIC_MMU,PAGE_LEVEL    ; the level's files: its record, its
        ld a,(level)                    ; city's map, colours and palette,
        call load_level                 ; the draw distance (level_load.asm)
        jr nc,.loaded
        nextreg LOGIC_MMU,PAGE_MENU     ; couldn't: say so, back to the menu
        jp load_error_screen            ; (menu.asm)
.loaded:
        ld a,(level_cur+LV_WAVES)       ; (a save game's wave: within the
        ld hl,wave_number               ; level's waves)
        cp (hl)
        jr nc,.wok
        ld (hl),a
.wok:   nextreg CODE_MMU,PAGE_AUDIO     ; the engines on (audio.asm; the
        call engine_start               ; interrupt plays them)
        call base_init                  ; the pad and terrace, at full strength
        nextreg LOGIC_MMU,PAGE_WEAPONS
        call weapons_reset
        call l2_game_mode               ; Layer 2 256x192 again, if a screen
                                        ; had it at 320x256
        ; clear both buffers
        nextreg CODE_MMU,PAGE_CITY
        ld a,VIEW_CY
        ld (horizon),a
        ld a,PAGE_L2_A
        ld (seg_base),a
        call clear_screen
        ld a,PAGE_L2_B
        ld (seg_base),a
        call clear_screen
        nextreg $12,L2_BANK_A           ; Layer 2 active (displayed) bank
        nextreg $13,L2_BANK_B           ; Layer 2 shadow bank (drawn into)
        ld bc,$123B
        ld a,%00000010                  ; Layer 2 visible (the menu hid it)
        out (c),a
        nextreg CODE_MMU,PAGE_HUD
        call ula_init                   ; ULA: FPS overlay, panel, city map
        call zombie_init                ; place the zombies on the streets
        call human_init                 ; and the humans to rescue
        ld a,1<<WP_START                ; PREPARE FOR COMBAT after the first
        ld (wave_prep),a                ; frame (wave_prepare; the devil adds
                                        ; its graphics, WP_DEVIL)
        nextreg LOGIC_MMU,PAGE_SPECIAL  ; and the level's special monsters
        call spec_init                  ; (specials.asm)
        call gfx_stale                  ; figure pages to read back: no
        jr c,.gk                        ; figures until they are
        xor a
        ld (gfx_ok),a
.gk:

;==============================================================================
; Main loop
;==============================================================================
main_loop:
        nextreg CODE_MMU,PAGE_INPUT     ; input at $E000, while the logic runs
        call kbd_scan                   ; all key and joystick banks
        ld a,K_PAUSE                    ; paused until the pause control is
        call key_pressed                ; pressed again
        call nz,game_pause
        ld a,K_VISION                   ; the next vision mode the VTOL has
        call key_pressed                ; (level_load.asm: its palettes are
        jr z,.nv                        ; there)
        nextreg LOGIC_MMU,PAGE_LEVEL
        call vis_cycle
.nv:
        nextreg LOGIC_MMU,PAGE_PLAYER   ; input/movement logic at $C000
        call update_player
        call setup_frame
        call zombie_update              ; walk the zombies (page at $2000)
        nextreg LOGIC_MMU,PAGE_SPECIAL  ; and fly the special monsters
        call spec_update                ; (specials.asm)
        ld a,(dv_dark_req)              ; the devil hurt: the palette darker
        or a                            ; (level_load.asm)
        jr z,.nd
        xor a
        ld (dv_dark_req),a
        nextreg LOGIC_MMU,PAGE_LEVEL
        call vis_dark
.nd:
        nextreg LOGIC_MMU,PAGE_WEAPONS  ; weapons logic at $C000
        call update_weapons             ; fire, move rounds, hits
        call human_update               ; map dots, rescues (page at $7000)
        ld a,(game_over)
        or a
        jr z,.play
        nextreg LOGIC_MMU,PAGE_MENU     ; the VTOL or the pad destroyed:
        jp game_over_screen             ; GAME OVER over the view (menu.asm)
.play:  ld a,(level_done)
        or a
        jr z,.go
        nextreg LOGIC_MMU,PAGE_LEVELEND ; the last wave wiped out: level
        jp level_complete_screen        ; complete (levelend.asm) -> next_level
.go:
        call map_shadow
    IFDEF DRAW_FPS
        call vtick
    ENDIF
        nextreg CODE_MMU,PAGE_CITY      ; Layer 2 drawing code at $E000
        nextreg CITY2_MMU,PAGE_CITY2    ; and more at $8000, over the ULA
        call clear_screen               ;   screen (city2.asm)
    IFDEF DRAW_FPS
        call vtick
    ENDIF
        call draw_dots
    IFDEF DRAW_FPS
        call vtick
    ENDIF
        call draw_city                  ; also calls vtick once per building
        call draw_bullets               ; machine gun tracers
        call draw_particles             ; zombie bursts
        call draw_bolt                  ; the devil's lightning (city2.asm)
        call draw_gunsight
        call draw_reticule              ; the missile lock (city2.asm)
        nextreg ULA_MMU,PAGE_ULA0       ; the ULA screen back at $8000
        nextreg CODE_MMU,PAGE_HUD       ; ULA HUD code at $E000
        call draw_hud
    IFDEF WAIT_FOR_VBLANK
        call wait_vblank
    ENDIF
        call l2_flip
        call shake_tick                 ; a crash: the view shaken
    IFDEF DRAW_FPS
        call fps_tick                   ; HUD page is still at $E000
    ENDIF
        nextreg CODE_MMU,PAGE_SPRITES   ; the HUD sprites (humans, compass)
        call hud_sprites                ; (hud_sprites.asm), with the new frame
        ld a,(wave_prep)                ; a level's first frame, or the
        or a                            ; devil's wave: PREPARE FOR COMBAT,
        call nz,wave_prepare            ; the graphics
        jp main_loop

;------------------------------------------------------------------------------
; After a frame (its view shown) that started a level (WP_START: no figures
; drawn if their pages are being read back) or the devil's wave (WP_DEVIL:
; it isn't drawn yet): PREPARE FOR COMBAT over the view (as PAUSED is)
; while
;   * at a level's start, the figures' pages a screen's background copy
;     (shared_pg) or the devil's graphics (devil_gfx) went over are read
;     back from the figures' file (gfx_stale, gfx_reload);
;   * in the devil's wave, its graphics go over the other monsters' pages
;     (devil_load: from the figures' kept pages on, gfx_keep);
; (one can't be read: the SD card's at fault, the load error screen), and
; for WPREP_TICKS interrupts (2 s) at least from its start (isr_ticks; the
; interrupts are off while the SD card is read, so a long read adds to it).
; Then the box goes and the game runs.
;------------------------------------------------------------------------------
WPREP_ROW       equ 7               ; ULA character row and column of the box
WPREP_COL       equ 6
WPREP_TICKS     equ 100             ; at least 2 s (interrupts)
WP_START        equ 0               ; wave_prep bits: a level's start,
WP_DEVIL        equ 1               ;   the devil's wave
wave_prepare:
        ld a,(wave_prep)
        ld (wp_what),a
        xor a
        ld (wave_prep),a
        ld hl,0
        ld (isr_ticks),hl               ; (one instruction: no tearing)
        ld hl,txt_wprep
        ld de,WPREP_ROW<<8 | WPREP_COL
        ld c,PAUSE_ATTR
        call menu_print
        nextreg LOGIC_MMU,PAGE_LEVEL    ; (level_load.asm)
        ld a,(wp_what)
        bit WP_START,a
        jr z,.dv
        call gfx_stale                  ; pages to read back?
        jr c,.fresh
        call gfx_reload
        jr c,.err
.fresh: xor a                           ; the figures' pages all theirs
        ld (shared_pg),a
        ld (devil_gfx),a
.dv:    ld a,(wp_what)
        bit WP_DEVIL,a
        jr z,wp_wait
        call devil_load                 ; its graphics over the others'
        jr nc,wp_wait
.err:   nextreg LOGIC_MMU,PAGE_MENU     ; couldn't: the SD card's at fault
        jp load_error_screen            ; (menu.asm)
wp_wait:                                ; (tests: zptest skips the wait here)
        ld hl,(isr_ticks)
        ld de,WPREP_TICKS
        or a
        sbc hl,de
        jr c,wp_wait
        ld hl,txt_wprep_off             ; the box gone: the view again
        ld de,WPREP_ROW<<8 | WPREP_COL
        ld c,VIEW_ATTR
        jp menu_print

txt_wprep:      db " PREPARE FOR COMBAT ", 0
txt_wprep_off:  db "                    ", 0
        ASSERT txt_wprep_off - txt_wprep == $ - txt_wprep_off
wave_prep:      db 0                    ; wave_prepare after this frame: bits
                                        ; WP_START, WP_DEVIL
wp_what:        db 0                    ; (wave_prepare: what it's for)

; A = the first figure page to read back from the figures' file at a
; level's start: a screen's background copy took the shared ones
; (shared_pg), the devil's graphics went over those from the kept ones on
; (devil_gfx, gfx_keep).  Carry set if none (or no graphics at all).
gfx_stale:
        ld c,GFX_PAGES_MAX
        ld a,(shared_pg)
        or a
        jr z,.d
        ld c,GFX_SHARED
.d:     ld a,(devil_gfx)
        or a
        jr z,.c
        ld a,(gfx_keep)
        cp c
        jr nc,.c
        ld c,a
.c:     ld a,(gfx_pages)
        or a
        scf
        ret z                           ; (no graphics)
        dec a                           ; its last page before the first stale
        cp c                            ; one: carry, none to read
        ld a,c
        ret

;==============================================================================
; Frames per second, shown on the ULA layer above Layer 2.
;
; Interrupts stay off (the span filler borrows SP), so time is taken from the
; raster: vtick reads the current video line and counts a new 50Hz video
; frame whenever the line number has gone backwards.  It must be called at
; least once per video frame (~560K T at 28MHz); the main loop and draw_cell
; do that.  Every 50 video frames (1 second) the number of frames rendered
; becomes the FPS figure.
;==============================================================================
    IFDEF DRAW_FPS
vtick:
        ld bc,$243B
        ld a,$1E
        out (c),a
        inc b
        in d,(c)                        ; line MSB
        dec b
        ld a,$1F
        out (c),a
        inc b
        in e,(c)                        ; line LSB
        dec b
        ld a,$1E
        out (c),a
        inc b
        in a,(c)
        cp d
        jr nz,vtick                     ; MSB changed mid-read: try again
        and 1
        ld d,a                          ; DE = video line 0..311
        ld hl,(fps_line)
        ld (fps_line),de
        or a
        sbc hl,de                       ; previous - current
        ret c
        ret z
        ld hl,fps_vframes               ; line went backwards: new frame
        inc (hl)
        ret

; Once per rendered frame, after the flip
fps_tick:
        call vtick
        ld hl,fps_count
        inc (hl)
        ld a,(fps_vframes)
        cp 50
        ret c
        sub 50
        ld (fps_vframes),a
        ld a,(fps_count)
        ld (fps_value),a
        xor a
        ld (fps_count),a
        jp fps_draw                     ; HUD page (paged in by main_loop)
    ENDIF

; A = NextReg number -> A = its value
read_nextreg:
        ld bc,$243B
        out (c),a
        inc b
        in a,(c)
        ret

; Select the shadow Layer 2 buffer for drawing: remember the 8K page of its
; first row.  Sections are then paged in on demand by seg_map / line_seg.
map_shadow:
        ld a,$13
        call read_nextreg
        add a,a                         ; 16K bank -> 8K page
        ld (seg_base),a
        ret

; Back from the screens outside the game (320x256, layer2-320x256.asm) to
; the game's Layer 2, 256x192 and hidden, and the occlusion page back in
; slot 2 where the 320x256 page was.  (Nothing changes if it wasn't.)
l2_game_mode:
        nextreg L320_MMU,PAGE_L320
        call l320_mode256
        nextreg OCC_MMU,PAGE_OCC0
        ret

; Show the shadow buffer and make the old active buffer the new shadow
l2_flip:
        ld a,$12
        call read_nextreg
        ld e,a                          ; old active
        ld a,$13
        call read_nextreg
        nextreg $12,a                   ; shadow -> active
        ld a,e
        nextreg $13,a                   ; old active -> shadow
        ret

;------------------------------------------------------------------------------
; Layer 2 writes go through MMU slot 0 ($0000-$1FFF) only.  Each 8K page of
; the buffer is a 32-row section, so row y is page seg_base + y/32 and its
; pixels are at (y & 31)*256 + x.  Sections are paged in as drawing reaches
; them.  Slots 4-5 keep the ULA screen.
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; Screen shake, when the VTOL hits a building (player.asm sets shake_t to
; SHAKE_LEN), and heavier when a wreck hits the ground (shake_big:
; SHAKE_BIG_LEN of shake_big_xy, up to 4 pixels).  Each rendered frame, as it
; is shown, the Layer 2 view is offset by the next pair of the table
; (shake_tab) through the scroll registers, dying away; the last pair (0, 0)
; puts it back, and the table back to shake_xy.  Only
; Layer 2 moves: the HUD is on the ULA.  (X wraps at 256, Y at 192: -n is
; 256-n and 192-n.  An edge row or column of the view shows the far side's
; meanwhile.)
;------------------------------------------------------------------------------
SHAKE_LEN       equ 6               ; rendered frames (about half a second)
SHAKE_BIG_LEN   equ 16              ; a wreck's (over a second)
shake_tick:
        ld a,(shake_t)
        or a
        ret z
        dec a
        ld (shake_t),a
        ld hl,(shake_tab)
        jr nz,.t
        ld de,shake_xy                  ; (the last: the usual table again)
        ld (shake_tab),de
.t:     add a,a
        add hl,a
        ld a,(hl)
        nextreg $16,a                   ; Layer 2 scroll X
        inc hl
        ld a,(hl)
        nextreg $17,a                   ; Layer 2 scroll Y
        ret

; The heavy shake (a wreck hitting the ground), over any going
shake_big:
        ld hl,shake_big_xy
        ld (shake_tab),hl
        ld a,SHAKE_BIG_LEN
        ld (shake_t),a
        ret

; Stop any shake: the view back in place
shake_off:
        ld hl,shake_xy
        ld (shake_tab),hl
        xor a
        ld (shake_t),a
        nextreg $16,0
        nextreg $17,0
        ret

; (x, y) pixels, used from the last pair back to the first
shake_xy:   db 0,0, 1,0, 256-1,192-1, 1,1, 256-2,192-1, 2,1
        ASSERT $ - shake_xy == 2*SHAKE_LEN
shake_big_xy:
        db 0,0, 1,0, 256-1,1, 1,192-1, 256-2,1, 2,192-1, 256-2,2, 2,192-2
        db 256-3,2, 3,192-2, 256-3,3, 3,192-3, 256-4,3, 4,192-3, 256-4,4, 4,192-4
        ASSERT $ - shake_big_xy == 2*SHAKE_BIG_LEN
shake_tab:  dw shake_xy                 ; the table shake_tick uses
shake_t:    db 0                        ; frames of shake left (0: none)
gfx_ok:     db 0                        ; 1: the figures' graphics are loaded
gfx_pages:  db 0                        ;   in this many pages (gfx_load),
gfx_keep:   db 0                        ;   the kept figures' in those before
                                        ;   this one (the devil's go after)
devil_gfx:  db 0                        ; 1: the devil's graphics are over the
                                        ; other monsters' (devil_load)
dv_dark:    db 0                        ; the normal palette's darkening (the
dv_dark_req: db 0                       ;   devil hurt), 1: to apply (vis_dark)
dv_hum:     db 0                        ; 1: the devil's charging whine plays
                                        ; (on the splats' voice: they wait)
bolt_up:    db 0                        ; 1: it went up into the sky (out of range)
bolt_hit:   db 0                        ; 1: it stopped at a building, at
bolt_end:   dw 0, 0, 0                  ;   (x, y, z): the VTOL behind it safe
bolt_spd:   db 0                        ; its hit: the speed braked down to
bolt_t:     db 0                        ; the devil's lightning: frames to draw
                                        ; it (draw_bolt; devil.asm)
spin_rate:  dw 0                        ; its hit: the VTOL's spin a frame (8.8,
spin_t:     db 0                        ;   signed), frames of it left, and
bolt_brake: db 0                        ;   1: braked to bolt_spd (player.asm)
shared_pg:  db 0                        ; 1: the load-out's background copy has
                                        ; the figures' last pages (PAGE_L320_BG)

;------------------------------------------------------------------------------
; Wait until the raster is outside the display area (line >= 192)
;------------------------------------------------------------------------------
wait_vblank:
        ld bc,$243B
        ld a,$1E
        out (c),a
        inc b
        in a,(c)
        and 1
        ret nz                          ; line >= 256
        dec b
        ld a,$1F
        out (c),a
        inc b
        in a,(c)
        cp 192
        jr c,wait_vblank
        ret

; HL -> map byte for the cell the camera is in
cam_cell_ptr:
        ld a,(cam_z+2)
        ld l,a
        ld h,0
        ROWOFS
        ld a,(cam_x+2)
        add hl,a
        ld de,city_map
        add hl,de
        ret

; A = damage to the VTOL (a building crash, a ghost): its hit points
; (vtol_hp) fall by that, not below 0.  At 0 it is destroyed (vtol_dead): it
; spins down out of control (vtol_wreck, player.asm), then the game is over.
vtol_damage:
        or a
        ret z
        ld c,a
        ld a,(vtol_hp)
        sub c
        jr nc,.hp
        xor a
.hp:    ld (vtol_hp),a
        ret nz
        ld a,1
        ld (vtol_dead),a
        ret

; HL = the height the VTOL rests at: MIN_Y when its whole footprint is over
; road, or just clear (COLL_H) of the highest roof under it
floor_y:
        call vtol_ground
        ld hl,MIN_Y
        ret z
        ld hl,(vg_max)
        ld de,COLL_H+1
        add hl,de
        ret

; Weapon type details, by WPN_*: its full load, reload frames a shot (0:
; doesn't reload; the AMMO_INF weapons) and the slots it may be fitted in
; (resident, for the weapons page and the load-out screen)
wpn_cfg:    db 0, 0, WS_ANY                             ; WPN_NONE (empty)
            db AMMO_INF, 0, WS_CENTRE                   ; WPN_GUN
            db AMMO_INF, 0, WS_CENTRE                   ; WPN_LASER
            db AMMO_INF, 0, WS_CENTRE                   ; WPN_CHAIN
            db ROCKET_SHOTS, ROCKET_RELOAD, WS_PYLONS   ; WPN_ROCKETS
            db MISSILE_SHOTS, MISSILE_RELOAD, WS_PYLONS ; WPN_MISSILE
            db BOMB_SHOTS, BOMB_RELOAD, WS_PYLONS       ; WPN_BOMB
            db AUTOCANNON_SHOTS, AUTOCANNON_RELOAD, WS_PYLONS ; WPN_AUTOCANNON
            db PROX_SHOTS, PROX_RELOAD, WS_PYLONS       ; WPN_PROX
            db LINK_SHOTS, LINK_RELOAD, WS_LINK_L       ; WPN_LCHAIN_L
            db LINK_SHOTS, LINK_RELOAD, WS_LINK_R       ; WPN_LCHAIN_R
        ASSERT LINK_SHOTS < AMMO_INF
        ASSERT WPN_ROCKETS == 4 && WPN_MISSILE == 5 && WPN_AUTOCANNON == 7
        ASSERT WPN_PROX == 8 && WPN_LCHAIN_L == 9 && WPN_LCHAIN_R == 10
        ASSERT $ - wpn_cfg == WCFG_SIZE*(WPN_LAST+1)

; A = weapon type -> HL = its wpn_cfg entry.  Preserves BC, DE.
wpn_cfg_ptr:
        ld l,a
        add a,a
        add a,l                         ; * WCFG_SIZE
        ld hl,wpn_cfg
        add hl,a
        ret
        ASSERT WCFG_SIZE == 3

; A = weapon type, C = slot (0 = the centre slot): carry set if the weapon
; may be fitted in that slot (WCFG_SLOTS).  Preserves DE.
wpn_fits:
        call wpn_cfg_ptr
        ld a,WCFG_SLOTS
        add hl,a
        ld a,(hl)
        ld b,c
        inc b
.sh:    rrca                            ; bit C into carry
        djnz .sh
        ret

;------------------------------------------------------------------------------
; From the LEVEL COMPLETE screen (levelend.asm, slot 6): page the load-out screen
; into slot 6 (from here, resident) and show it; it goes on to next_level
;------------------------------------------------------------------------------
loadout_go:
        nextreg LOGIC_MMU,PAGE_LOADOUT
        jp loadout_screen

; From LEVEL COMPLETE after the last level (levelend.asm, slot 6): the game
; complete screen (menu.asm)
game_done_go:
        nextreg LOGIC_MMU,PAGE_MENU
        jp game_complete_screen

; From the main menu (mainmenu.asm, slot 6): the redefine keys screen
keydef_go:
        nextreg LOGIC_MMU,PAGE_KEYDEF
        jp keydef_screen

; The main menu (its own page, mainmenu.asm), from start-up and from another
; slot 6 page (the redefine keys and end screens), or the pause
menu_go:
        nextreg LOGIC_MMU,PAGE_MAINMENU
        jp main_menu

;------------------------------------------------------------------------------
; Paused (main_loop: the pause control, K_PAUSE, BREAK or a Mega Drive pad's
; START by default): PAUSED over the view, white on an opaque black ULA box,
; and under it S: SAVE AND QUIT and X: QUIT, NO SAVE, until the pause control
; is pressed again.  Nothing moves meanwhile and the screen keeps its last
; frame.  S (fixed: only while paused) saves the game (save_game) and goes
; back to the main menu; if it can't be saved, SAVE FAILED, and it stays
; paused.  (Not in a wreck: nothing to save.)  X (fixed too) goes back to
; the main menu without saving: the game is lost, and any save game is left
; as it was.  Needs the input page in slot 7.
;------------------------------------------------------------------------------
PAUSE_ROW       equ 7               ; ULA character row and column of the box
PAUSE_COL       equ 12
PAUSE_ROW2      equ 9               ; and of the save line
PAUSE_COL2      equ 7
PAUSE_ROW3      equ 10              ; and of the quit line
PAUSE_ATTR      equ 2<<3 | 7        ; paper 2 (opaque black), ink 7 (white)
VIEW_ATTR       equ %01000111       ; the viewport's own (ula_init): transparent
game_pause:
        ld hl,txt_paused
        ld de,PAUSE_ROW<<8 | PAUSE_COL
        ld c,PAUSE_ATTR
        call menu_print
        ld hl,txt_pause_quit
        ld de,PAUSE_ROW3<<8 | PAUSE_COL2
        ld c,PAUSE_ATTR
        call menu_print
        ld a,(vtol_dead)
        or a
        jr nz,.w                        ; (a wreck: no saving)
        ld hl,txt_pause_save
        ld de,PAUSE_ROW2<<8 | PAUSE_COL2
        ld c,PAUSE_ATTR
        call menu_print
.w:     call menu_frame
        call kbd_scan
        ld a,(vtol_dead)
        or a
        jr nz,.np
        ld hl,KB_S                      ; save and quit
        call key_code_pressed
        jr nz,.save
.np:    ld hl,KB_X                      ; quit, no save
        call key_code_pressed
        jr nz,.quit
        ld a,K_PAUSE
        call key_pressed
        jr z,.w
        ld hl,txt_unpaused              ; the box gone: the view again
        ld de,PAUSE_ROW<<8 | PAUSE_COL
        ld c,VIEW_ATTR
        call menu_print
        ld hl,txt_unpaused2
        ld de,PAUSE_ROW3<<8 | PAUSE_COL2
        ld c,VIEW_ATTR
        call menu_print
        ld hl,txt_unpaused2
        ld de,PAUSE_ROW2<<8 | PAUSE_COL2
        ld c,VIEW_ATTR
        jp menu_print
.save:  call save_game                  ; (pages the file handler in)
        jr c,.fail
.quit:  ld sp,stack_top                  ; saved, or quit: the main menu
        jp menu_go
.fail:  nextreg CODE_MMU,PAGE_INPUT     ; couldn't: say so, still paused
        ld hl,txt_save_fail
        ld de,PAUSE_ROW2<<8 | PAUSE_COL2
        ld c,PAUSE_ATTR
        call menu_print
        jr .w

txt_paused:     db " PAUSED ", 0
txt_unpaused:   db "        ", 0
        ASSERT txt_unpaused - txt_paused == $ - txt_unpaused
txt_pause_save: db " S: SAVE AND QUIT ", 0
txt_save_fail:  db "   SAVE FAILED    ", 0
txt_unpaused2:  db "                  ", 0
        ASSERT txt_save_fail - txt_pause_save == txt_unpaused2 - txt_save_fail
        ASSERT txt_unpaused2 - txt_save_fail == $ - txt_unpaused2
txt_pause_quit: db " X: QUIT, NO SAVE ", 0
        ASSERT $ - txt_pause_quit == txt_save_fail - txt_pause_save

    IFNDEF RELEASE
;------------------------------------------------------------------------------
; Debug, key 9 (debug_killall, weapons.asm): pick a level.  LEVEL SELECT nn
; over the view, as PAUSED is, from the next level (this one if the last).
; Q up, A down (fixed keys; held, they repeat), 1 to LEVEL_LAST.  SPACE goes
; there: the load-out screen, then the level from its first wave (the one
; being played is left, no level complete).  9 again carries on with this
; one.  Nothing moves meanwhile.  Needs the input page in slot 7.
;------------------------------------------------------------------------------
DLS_ROW         equ 7               ; ULA character row and column of the box
DLS_COL         equ (32-(txt_dls_end-txt_dls))/2
DLS_ROW2        equ 9               ; and of the keys' line
DLS_COL2        equ (32-(txt_dls_keys_end-txt_dls_keys))/2
DLS_REPEAT      equ 20              ; Q / A held: frames before repeating,
DLS_RATE        equ 3               ; then a level every this many frames

debug_level_select:
        ld a,(level)                    ; from the next level
        cp LEVEL_LAST
        jr nc,.l
        inc a
.l:     ld (dls_level),a
        xor a
        ld (dls_hold),a
.draw:  call dls_show
.w:     call menu_frame
        call kbd_scan
        ld hl,KB_9                      ; carry on with this level
        call key_code_pressed
        jr nz,.back
        ld hl,KB_SPACE                  ; go
        call key_code_pressed
        jr nz,.go
        ld hl,KB_Q
        call dls_key
        jr z,.dn
        ld a,(dls_level)
        cp LEVEL_LAST
        jr nc,.w
        inc a
        ld (dls_level),a
        jr .draw
.dn:    ld hl,KB_A
        call dls_key
        jr z,.w
        ld a,(dls_level)
        cp 2
        jr c,.w
        dec a
        ld (dls_level),a
        jr .draw
.go:    ld a,(dls_level)                ; that level, from its first wave
        ld (level),a
        ld a,1
        ld (resume_wave),a
        ld sp,stack_top
        jp loadout_go
.back:  ld hl,txt_dls_off               ; the box gone: the view again
        ld de,DLS_ROW<<8 | DLS_COL
        ld c,VIEW_ATTR
        call menu_print
        ld hl,txt_dls_keys_off
        ld de,DLS_ROW2<<8 | DLS_COL2
        ld c,VIEW_ATTR
        jp menu_print

; The box, with dls_level's number
dls_show:
        ld a,(dls_level)
        ld b,'0'
.t:     cp 10
        jr c,.u
        sub 10
        inc b
        jr .t
.u:     add a,'0'
        ld hl,dls_num
        ld (hl),b
        inc hl
        ld (hl),a
        ld hl,txt_dls
        ld de,DLS_ROW<<8 | DLS_COL
        ld c,PAUSE_ATTR
        call menu_print
        ld hl,txt_dls_keys
        ld de,DLS_ROW2<<8 | DLS_COL2
        ld c,PAUSE_ATTR
        jp menu_print

; HL = a key code (KB_...): NZ to step a level: just pressed, or held
; DLS_REPEAT frames, then every DLS_RATE.  Z: not.
dls_key:
        call key_code_pressed
        jr z,.held
        xor a
        ld (dls_hold),a
        inc a                           ; (NZ)
        ret
.held:  ld a,h                          ; down?
        ld de,key_now
        add de,a
        ld a,(de)
        and l
        ret z
        ld a,(dls_hold)
        inc a
        cp DLS_REPEAT
        jr c,.wait
        ld a,DLS_REPEAT-DLS_RATE        ; step, then DLS_RATE more frames
        ld (dls_hold),a
        or a                            ; (NZ)
        ret
.wait:  ld (dls_hold),a
        xor a
        ret

txt_dls:        db " LEVEL SELECT "
dls_num:        db "00 ", 0
txt_dls_end:
txt_dls_off:    db "                 ", 0
        ASSERT $ - txt_dls_off == txt_dls_end - txt_dls
txt_dls_keys:   db " Q/A: LEVEL  SPACE: GO  9: BACK ", 0
txt_dls_keys_end:
txt_dls_keys_off: db "                                ", 0
        ASSERT $ - txt_dls_keys_off == txt_dls_keys_end - txt_dls_keys
dls_level:      db 0                    ; the level shown
dls_hold:       db 0                    ; frames Q / A held (dls_key)
    ENDIF

;------------------------------------------------------------------------------
; Save games: ZPDATA/SAVEGAME.ZPS (beside the level files), one game.  Written
; by save and quit (game_pause: save_game), read by CONTINUE on the main menu
; (load_save, continue_game).  "ZPSV", SG_VERSION, then the fields in
; sg_fields, in order: the level and wave, the salvage, the VTOL's integrity
; (vtol_hp), its weapon slots (type and ammo each) and the selected one, the
; store (wpn_stock, wpn_unlocked), the booster (fitted, fuel), and the
; vision modes (vision_owned), and the vertical and lateral thrusters
; (vthrust_fitted, lthrust_fitted).  Files of an older version (1: before
; the vision modes, 2: before the vertical thrusters, 3: before the lateral
; ones, 4: before the linked chain guns, a longer store) are refused, as any
; other version.
; Continued, the level starts afresh at the saved wave: its zombies, the
; humans (and this level's rescues so far) and the base are new.
;------------------------------------------------------------------------------
SG_VERSION      equ 5
sg_fields:      ; address, bytes
        dw level
        db 1
        dw wave_number
        db 1
        dw salvage_points
        db 2
        dw vtol_hp
        db 1
        dw wpn_slots
        db WPN_SLOTS*2
        dw wpn_sel
        db 1
        dw wpn_stock
        db WPN_LAST+1
        dw wpn_unlocked
        db WPN_LAST+1
        dw boost_fitted                 ; (and boost_fuel, after it)
        db 2
        dw vision_owned
        db 1
        dw vthrust_fitted
        db 1
        dw lthrust_fitted
        db 1
        dw 0                            ; (the end)
        ASSERT boost_fuel == boost_fitted+1
SG_SIZE         equ 5+1+1+2+1+WPN_SLOTS*2+1+2*(WPN_LAST+1)+2+1+1+1

; Copy the fields: A = 0 the game's into sg_buf, 1 sg_buf's into the game
sg_copy:
        ld (sg_dir),a
        ld ix,sg_fields
        ld de,sg_buf+5
.lp:    ld l,(ix+0)
        ld h,(ix+1)
        ld a,h
        or l
        ret z
        ld c,(ix+2)
        ld b,0
        ld a,(sg_dir)
        or a
        jr z,.out
        ex de,hl                        ; into the game: HL = sg_buf
        ldir
        ex de,hl
        jr .nx
.out:   ldir                            ; out of it: HL = the field
.nx:    ld bc,3
        add ix,bc
        jr .lp

; Save the game.  Carry set (A = the esxDOS error) if it couldn't be
; written.  Leaves the file handler in slot 7.
save_game:
        ld hl,sg_magic
        ld de,sg_buf
        ld bc,4
        ldir
        ld a,SG_VERSION
        ld (de),a
        xor a
        call sg_copy
        nextreg CODE_MMU,PAGE_FILE
        ld hl,sg_name
        ld de,sg_buf
        ld bc,SG_SIZE
        jp fh_save

; Read the save game into sg_buf: carry set if there's none, or it isn't a
; save game this version can use (its level out of range too).  Leaves the
; file handler in slot 7.
load_save:
        nextreg CODE_MMU,PAGE_FILE
        ld hl,sg_name
        ld de,sg_buf
        ld bc,SG_SIZE
        call fh_load
        ret c
        ld hl,-SG_SIZE                  ; all of it?
        add hl,bc
        ld a,h
        or l
        jr nz,.bad
        ld hl,sg_buf
        ld de,sg_magic
        ld b,4
.m:     ld a,(de)
        cp (hl)
        jr nz,.bad
        inc hl
        inc de
        djnz .m
        ld a,(hl)
        cp SG_VERSION
        jr nz,.bad
        ld a,(sg_buf+5)                 ; its level (sg_fields' first)
        or a
        jr z,.bad
        cp LEVEL_LAST+1
        jr nc,.bad
        or a                            ; usable: carry clear
        ret
.bad:   scf
        ret

; CONTINUE (main menu, after load_save): a new game with the save game's
; fields over it, into its level at its wave
continue_game:
        ld sp,stack_top
        call game_reset
        ld a,1
        call sg_copy
        ld a,(wave_number)
        or a
        jr nz,.w
        inc a
.w:     ld (resume_wave),a
        jp next_level

    IFDEF REAL_HARDWARE                 ; (a real Next: in the home folder,
sg_home:    db "/home", 0               ;   made at start-up if need be)
sg_folder:  db "/home/ZPSave", 0
sg_name:    db "/home/ZPSave/SAVEGAME.ZPS", 0
    ELSE
sg_name:    db "ZPDATA/SAVEGAME.ZPS", 0
    ENDIF
sg_magic:   db "ZPSV"
sg_dir:     db 0
resume_wave: db 1                       ; next_level's first wave (1, or a
                                        ; save game's: continue_game)
sg_buf:     ds SG_SIZE

; Z if the VTOL is landed: speed 0 and resting on the floor under it (the
; road, the landing pad or a roof: floor_y), and not a wreck.  Landed, its
; weapons don't fire (update_weapons) and humans can board or get off
; (human_update).
vtol_landed:
        ld a,(vtol_dead)
        or a
        ret nz                          ; a wreck
        ld a,(speed)
        or a
        ret nz                          ; moving
        ; fall through

; Z if the VTOL rests on the floor under it (floor_y), at any speed: on the
; ground, or a roof or the pad (update_player then brakes it to a stop)
vtol_on_floor:
        call floor_y
        ld de,(cam_y)
        or a
        sbc hl,de                       ; Z: resting on it
        ret

; The VTOL's footprint: the corners and the long-side midpoints of its
; VTOL_HL x VTOL_HW (half size) rectangle, turned to the heading, round
; (cam_x, cam_z).  The rectangle is smaller than a tile, so these six points
; find every cell it overlaps (to within a tile corner nicking a long side).
; HL = vg_max = the highest ground under them; Z if all road (0).
vtol_ground:
        ld a,(yaw)                      ; forward (sin, cos), right (cos, -sin)
        call get_sin
        ld (vg_sin),hl
        ld a,(yaw)
        add a,64
        call get_sin
        ld (vg_cos),hl
        ex de,hl
        ld hl,VTOL_HL
        call fmul
        ld (vg_fz),hl                   ; nose offset z = HL cos
        ld de,(vg_cos)
        ld hl,VTOL_HW
        call fmul
        ld (vg_rx),hl                   ; side offset x = HW cos
        ld de,(vg_sin)
        ld hl,VTOL_HL
        call fmul
        ld (vg_fx),hl                   ; nose offset x = HL sin
        ld de,(vg_sin)
        ld hl,VTOL_HW
        call fmul
        call neg_hl
        ld (vg_rz),hl                   ; side offset z = -HW sin
        ld hl,0
        ld (vg_max),hl
        ld hl,(vg_fx)                   ; nose: the front corners
        ld de,(vg_fz)
        call .side
        ld hl,0                         ; the long-side midpoints
        ld de,0
        call .side
        ld hl,(vg_fx)                   ; tail: the back corners
        call neg_hl
        push hl
        ld hl,(vg_fz)
        call neg_hl
        ex de,hl
        pop hl
        call .side
        ld hl,(vg_max)
        ld a,h
        or l
        ret
; HL, DE = an offset along the length (x, z): the points it +- the side offset
.side:  push hl
        push de
        ld bc,(vg_rx)
        add hl,bc
        ex de,hl
        ld bc,(vg_rz)
        add hl,bc
        ex de,hl
        call .pt
        pop de
        pop hl
        ld bc,(vg_rx)
        or a
        sbc hl,bc
        ex de,hl
        ld bc,(vg_rz)
        or a
        sbc hl,bc
        ex de,hl
; HL, DE = offset (x, z) from the centre: vg_max = max(vg_max, its ground)
.pt:    ld bc,(cam_x+1)
        add hl,bc
        ld a,h                          ; column
        ex de,hl
        ld bc,(cam_z+1)
        add hl,bc
        ld l,h                          ; row
        ld h,0
        ROWOFS
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        and CELL_CODE
        ret z                           ; road
        call bld_height
        ld de,(vg_max)
        or a
        sbc hl,de
        ret c                           ; lower than the highest so far
        add hl,de
        ld (vg_max),hl
        ret

; A = map byte -> HL = height in world units (levels 0-15, PAD_CODE = the
; base landing pad, TERRACE_CODE = the terrace round it)
bld_height:
        and 31
        add a,a
        ld hl,htab
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

;==============================================================================
; Per-frame view setup: trig, rotated building edge vectors, horizon
;==============================================================================
setup_frame:
        ld a,(yaw)
        call get_sin
        ld (sin_y),hl
        ld a,(yaw)
        add a,64
        call get_sin
        ld (cos_y),hl
        ld a,(pitch)
        call get_sin
        ld (sin_p),hl
        ld a,(pitch)
        add a,64
        call get_sin
        ld (cos_p),hl

        ; ground plane relative to camera: dy = -camY
        ld hl,(cam_y)
        call neg_hl
        push hl
        ld de,(cos_p)
        call fmul
        ld (yb),hl                      ; Y contribution of ground
        pop hl
        ld de,(sin_p)
        call fmul
        ld (zb),hl                      ; Z contribution of ground

        ; frustum cull factor c = cosP - 0.5|sinP|
        ld hl,(sin_p)
        call abs_hl
        call zhalf
        ex de,hl
        ld hl,(cos_p)
        or a
        sbc hl,de
        ld (cull_c),hl

        ld hl,BLD_SIZE
        ld ix,vecs0
        call make_vecs

        ld a,(cam_x+2)
        ld (cx),a
        ld a,(cam_z+2)
        ld (cz),a

        ld a,(pitch)
        add a,PMAX
        ld hl,hztab
        add hl,a
        ld a,(hl)
        ld (horizon),a
        ret

; A = angle -> HL = sin (S7.8).  Pages the sine table into slot 0 (PAGE_SIN):
; call it only outside the Layer 2 drawing (it is: setup_frame, the player,
; vtol_ground), never between a section's paging and its writes.
get_sin:
        nextreg SIN_MMU,PAGE_SIN        ; the table at $0000 (slot 0)
        ld l,a
        ld h,high sin_lo
        ld a,(hl)
        inc h
        ld h,(hl)
        ld l,a
        ret

; Rotate the building edge vectors (s,0,0) and (0,0,s) into camera space.
; HL = s, IX -> 16 bytes: VX(X,Y,Z) VZ(X,Y,Z) corner offset (X,Z1)
make_vecs:
        ld (mv_s),hl
        ld de,(cos_y)
        call fmul
        ld (mv_c),hl                    ; s*cosY
        ld hl,(mv_s)
        ld de,(sin_y)
        call fmul
        ld (mv_n),hl                    ; s*sinY
        ; VX = ( s cosY, -s sinY sinP, s sinY cosP )
        ld hl,(mv_c)
        ld (ix+0),l
        ld (ix+1),h
        ld hl,(mv_n)
        ld de,(sin_p)
        call fmul
        call neg_hl
        ld (ix+2),l
        ld (ix+3),h
        ld hl,(mv_n)
        ld de,(cos_p)
        call fmul
        ld (ix+4),l
        ld (ix+5),h
        ; VZ = ( -s sinY, -s cosY sinP, s cosY cosP )
        ld hl,(mv_n)
        call neg_hl
        ld (ix+6),l
        ld (ix+7),h
        ld hl,(mv_c)
        ld de,(sin_p)
        call fmul
        call neg_hl
        ld (ix+8),l
        ld (ix+9),h
        ld hl,(mv_c)
        ld de,(cos_p)
        call fmul
        ld (ix+10),l
        ld (ix+11),h
        ; cell centre -> footprint corner (-s/2,-s/2) in yaw space
        ld hl,(mv_n)
        ld de,(mv_c)
        or a
        sbc hl,de
        sra h
        rr l
        ld (ix+12),l                    ; X: s/2 (sinY - cosY)
        ld (ix+13),h
        ld hl,(mv_n)
        ld de,(mv_c)
        add hl,de
        sra h
        rr l
        call neg_hl
        ld (ix+14),l                    ; Z1: -s/2 (sinY + cosY)
        ld (ix+15),h
        ret

;==============================================================================
; Fixed point maths
;==============================================================================

; HL = -HL
neg_hl:
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; HL = |HL|
abs_hl:
        bit 7,h
        ret z
        jr neg_hl

; fmul: HL = HL * DE >> 8
;   HL = signed 16-bit integer, DE = S7.8 factor in -1.0..+1.0
;   Sign/magnitude using two 8x8 MUL D,E.  Preserves IX, IY.
fmul:
        ld a,h
        xor d
        push af                         ; result sign in bit 7
        bit 7,h
        jr z,.ap
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.ap:    bit 7,d
        jr z,.bp
        xor a
        sub e
        ld e,a
        sbc a,a
        sub d
        ld d,a
.bp:    ld a,d
        or a
        jr nz,.one                      ; |factor| == 1.0
        ld a,e
        ld d,l
        mul d,e                         ; lo * f
        ld c,d
        ld d,h
        ld e,a
        mul d,e                         ; hi * f
        ld a,e
        add a,c
        ld l,a
        ld a,d
        adc a,0
        ld h,a
.one:   pop af
        ret p
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; HL = 0.5 * HL (signed): the top/bottom frustum slope, VIEW_CY/128
zhalf:
        sra h
        rr l
        ret

;==============================================================================
; Shared data (resident: used by the main code and by both pages)
;==============================================================================
; --- player state ---
; (cam_x .. wflash_t are set from start_state by newGame)
cam_x:      ds 3                        ; frac, integer lo, hi
cam_z:      ds 3
cam_y:      ds 2
yaw_frac:   ds 1                        ; fraction below yaw (keep together:
yaw:        ds 1                        ; yaw_frac/yaw is one 8.8 word)
pitch_frac: ds 1                        ; fraction below pitch (keep together:
pitch:      ds 1                        ; pitch_frac/pitch is one signed 8.8
                                        ; word; drawing uses pitch only)
speed:      ds 1
; weapon slots: type, ammo (AMMO_INF = 255 = infinite).  Address of slot n
; is wpn_slots + n*2.
wpn_slots:  ds WPN_SLOTS*2
wpn_sel:    ds 1                        ; selected slot (keys 1-5), fires on SPACE
wflash_slot: ds 1                       ; empty slot requested: which, and
wflash_t:   ds 1                        ; frames of yellow/blue flash left
level:      db START_LEVEL              ; current level (newGame: START_LEVEL)
view_r:     db VIEW_R                   ; draw distance, tiles (load_level)
dot_r:      db VIEW_R-1                 ; street dots' radius (load_level)
vtol_hp:    db VTOL_HP                  ; the VTOL's hit points (newGame)
vtol_dead:  db 0                        ; 1: destroyed (hit points 0)
dead_down:  db 0                        ; 1: the wreck has hit the ground
dead_vy:    db 0                        ; its falling speed, units a frame
dead_wait:  db DEAD_PAUSE               ; frames on the ground to GAME OVER
level_done: db 0                        ; 1: the level's last wave is wiped out
wave_number: db 1                       ; current zombie wave of the level,
                                        ; 1..LV_WAVES (newGame: 1)
game_over:  db 0                        ; 1: the landing pad was destroyed
salvage_points: dw 0                    ; salvage points, 16-bit (newGame: 0)
gun_tilt:   db 0                        ; centre gun tilt, signed (weapons_reset)
barr_n:     db 0                        ; barricades in barr_tab (barricade_init)
barr_tab:   ds NBARR*BARR_REC           ; barricades: x, z, hit points
sight_y:    db VIEW_CY+GUN_SIGHT_DY     ; the gunsight's row (gun_aim)
SM_CENTRE       equ 1               ; sight_mask: the crosshairs drawn: the
SM_LINK_L       equ 2               ;   centre one, the linked chain guns'
SM_LINK_R       equ 4               ;   left and right (gun_aim)
sight_mask: db SM_CENTRE
sight_ax:   db 128                      ; the centre crosshair: where the
sight_ay:   db VIEW_CY+GUN_SIGHT_DY     ;   aim assist turns its rounds
sight_lx:   db 128-LINK_SIGHT_DX        ; the linked chain guns' crosshairs:
sight_ly:   db VIEW_CY+GUN_SIGHT_DY     ;   left (x, y) and right, where their
sight_rx:   db 128+LINK_SIGHT_DX        ;   aim assist turns their rounds
sight_ry:   db VIEW_CY+GUN_SIGHT_DY     ;   (aim_probe; gun_aim: without it)
sight_x:       db 128                      ; draw_gunsight: a crosshair's centre
gs_row:     db VIEW_CY                  ;   and row
; The missile lock (lock_update, weapons.asm; drawn by draw_reticule)
ret_on:     db 0                        ; 1: the reticule is shown
ret_x:      db 128                      ;   its centre (view pixels)
ret_y:      db VIEW_CY
lock_state: db 0                        ; 0 searching, 1 locking, 2 locked
lock_tgt:   db $FF                      ; the monster (record index; $FF none)
lock_t:     db 0                        ; frames on it so far
wnd_x:      db 128                      ; where the reticule wanders to
wnd_y:      db VIEW_CY
; Weapons unlocked by salvage (salvage_award, menu.asm), not yet fitted: a
; count per weapon type (WPN_*), for the load-out page (newGame: none)
wpn_stock:  ds WPN_LAST+1
; 1: the weapon type has been unlocked (fitted at the start, or by salvage):
; the load-out screen lists it, even with none in store (newGame)
wpn_unlocked: ds WPN_LAST+1
; Vision modes the VTOL has (salvage rewards, fitted at once): VIS_* bits.
; Saved in the save game.  (Using them is still to come.)
VIS_NV_GREEN    equ 1<<0            ; night vision, green
VIS_NV_MONO     equ 1<<1            ; night vision, monochrome
VIS_THERMAL     equ 1<<2            ; thermal vision
vision_owned: db 0                      ; (newGame: none)
; 1: the vertical thrusters (a salvage reward, part of the VTOL from then
; on, no fuel): it climbs to MAX_Y_THRUST instead of MAX_Y.  Saved.
vthrust_fitted: db 0
; 1: the lateral thrusters (a salvage reward, part of the VTOL from then
; on): the strafe controls each give a sideways pulse (player.asm).  Saved.
lthrust_fitted: db 0
; The vision mode in use (K_VISION steps through the ones the VTOL has:
; vis_cycle, level_load.asm): its palette is in the Layer 2 palette, which
; recolours the figures too (sprites/palette.json's "vision").  Not saved.
VM_NORMAL       equ 0
VM_NV_GREEN     equ 1                   ; (VIS_NV_GREEN)
VM_NV_MONO      equ 2                   ; (VIS_NV_MONO)
VM_THERMAL      equ 3                   ; (VIS_THERMAL): mode n has bit n-1
VM_MODES        equ 4                   ;   of vision_owned
        ASSERT VIS_NV_GREEN == 1<<(VM_NV_GREEN-1) && VIS_NV_MONO == 1<<(VM_NV_MONO-1)
        ASSERT VIS_THERMAL == 1<<(VM_THERMAL-1)
vision_mode: db VM_NORMAL
vis_ok:     db 0                        ; 1: this level's vision palettes loaded
boost_fitted: db 0                      ; 1: the booster module (salvage)
boost_fuel: db 0                        ; its fuel, 0..BOOST_FUEL_MAX
boost_on:   db 0                        ; 1: boosting (speed BOOST_SPEED)
boost_spd:  db 0                        ; the speed before the boost
        ASSERT wpn_unlocked == wpn_stock + WPN_LAST + 1
vg_sin:     dw 0                        ; vtol_ground: heading sin, cos,
vg_cos:     dw 0
vg_fx:      dw 0                        ; nose offset (x, z),
vg_fz:      dw 0
vg_rx:      dw 0                        ; side offset (x, z),
vg_rz:      dw 0
vg_max:     dw 0                        ; and the highest ground found

; The start of a game: copied over cam_x .. wflash_t by newGame
start_state:
            db 0, $80, PAD_X            ; cam_x: landed on the base pad
            db 0, $80, PAD_Z            ; cam_z  (gentables.py)
            dw PAD_H+COLL_H+1           ; cam_y: resting on it
            db 0, BASE_YAW              ; yaw: facing the city centre
            db 0, 0                     ; pitch: level
            db 0                        ; speed
            db WPN_GUN, AMMO_INF        ; slot 0: centre gun, infinite
            db WPN_NONE, 0              ; 1 (key 2): left outer pylon: empty
            db WPN_NONE, 0              ; 2 (key 3): right outer pylon: empty
            db WPN_NONE, 0              ; 3 (key 4): left inner pylon: empty
            db WPN_NONE, 0              ; 4 (key 5): right inner pylon: empty
            db WPN_CENTRE               ; wpn_sel
            db 0, 0                     ; wflash_slot, wflash_t
start_state_end:
            ASSERT start_state_end - start_state == wflash_t + 1 - cam_x
bullets:    ds NBULLETS*BREC            ; machine gun rounds (weapons.asm)
laser_rec:  ds BREC                     ; laser beam, drawn like a round
                                        ; (state 3); must follow bullets
particles:  ds NPART*PREC               ; zombie burst particles (must follow
                                        ; laser_rec: newGame clears them all)

; --- view, set up each frame by setup_frame ---
horizon:    db VIEW_CY
sin_y:      dw 0
cos_y:      dw 0
sin_p:      dw 0
cos_p:      dw 0
yb:         dw 0
zb:         dw 0
vecs0:      ds 16
cull_c:     dw 0
mv_s:       dw 0
mv_c:       dw 0
mv_n:       dw 0
cx:         db 0
cz:         db 0
seg_base:   db 0                        ; 8K page of row 0 of the draw buffer

; --- fps ---
fps_line:   dw 0
fps_vframes: db 0
fps_count:  db 0
fps_value:  db 0


            ds 256                      ; stack (must stay resident)
stack_top:

        DISPLAY "Main end:  ",/A,$
        ASSERT $ <= MAIN_ADDR+MEMBANK_SIZE

;==============================================================================
; Core function pages: assembled at $E000, swapped into slot 7
;==============================================================================
        MMU CODE_SLOT e, PAGE_CITY, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "city.asm"
        DISPLAY "City end:  ",/A,$

; The second city page: assembled at $8000, mapped into slot 4 (over the ULA
; screen) beside the city page while the city is drawn
        MMU CITY2_SLOT e, PAGE_CITY2, CITY2_ADDR
        ORG CITY2_ADDR
        INCLUDE "city2.asm"
        DISPLAY "City2 end: ",/A,$
        ASSERT $ <= CITY2_ADDR+MEMBANK_SIZE

; The 320x256 Layer 2 graphics for the screens outside the game: assembled
; at $4000, mapped into slot 2 (over the occlusion page) while they're up
        MMU L320_SLOT e, PAGE_L320, L320_ADDR
        ORG L320_ADDR
        INCLUDE "layer2-320x256.asm"
        DISPLAY "L320 end:  ",/A,$
        ASSERT $ <= L320_ADDR+MEMBANK_SIZE

        MMU CODE_SLOT e, PAGE_HUD, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "hud.asm"
        DISPLAY "HUD end:   ",/A,$

        MMU CODE_SLOT e, PAGE_INPUT, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "input.asm"
        DISPLAY "Input end: ",/A,$

        MMU CODE_SLOT e, PAGE_SPRITES, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "sprites.asm"
        INCLUDE "hud_sprites.asm"       ; the human column, the compass bar
        DISPLAY "Sprites end:",/A,$

        MMU CODE_SLOT e, PAGE_INIT, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "initialise.asm"
        DISPLAY "Init end:  ",/A,$

        MMU CODE_SLOT e, PAGE_FILE, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "file_handler.asm"
        DISPLAY "File end:  ",/A,$

        MMU CODE_SLOT e, PAGE_AUDIO, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "audio.asm"
        INCLUDE "sound.asm"             ; the players (the interrupt calls them)
        INCLUDE "sfx_data.asm"          ; the sound effects (sfx_tick plays them)
        DISPLAY "Audio end: ",/A,$

;==============================================================================
; Game logic pages: assembled at $C000, swapped into slot 6.  They may call
; the core page in slot 7 (main_loop has the keys there while they run).
;==============================================================================
        MMU LOGIC_SLOT e, PAGE_PLAYER, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "player.asm"
        DISPLAY "Player end:",/A,$

        MMU LOGIC_SLOT e, PAGE_WEAPONS, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "weapons.asm"
        DISPLAY "Weapons end:",/A,$

        MMU LOGIC_SLOT e, PAGE_MENU, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "menu.asm"
        DISPLAY "Menu end:  ",/A,$

        MMU LOGIC_SLOT e, PAGE_MAINMENU, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "mainmenu.asm"
        DISPLAY "Main menu end:",/A,$

        MMU LOGIC_SLOT e, PAGE_LEVELEND, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "levelend.asm"
        DISPLAY "Level end screen end:",/A,$

        MMU LOGIC_SLOT e, PAGE_LEVEL, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "level_load.asm"
        DISPLAY "Level end: ",/A,$

        MMU LOGIC_SLOT e, PAGE_LOADOUT, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "loadout.asm"
        DISPLAY "Loadout end:",/A,$

        MMU LOGIC_SLOT e, PAGE_KEYDEF, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "keydef.asm"
        DISPLAY "Keydef end:",/A,$

        MMU LOGIC_SLOT e, PAGE_SPECIAL, LOGIC_ADDR
        ORG LOGIC_ADDR
        INCLUDE "specials.asm"
        DISPLAY "Specials end:",/A,$

;==============================================================================
; Always mapped
;==============================================================================
        MMU ZOMBIE_SLOT e, PAGE_ZOMBIE, ZOMBIE_ADDR
        ORG ZOMBIE_ADDR
        INCLUDE "zombie.asm"
        DISPLAY "Zombie end:",/A,$
        INCLUDE "human.asm"
        DISPLAY "Humans end:",/A,$
        INCLUDE "map.asm"
        DISPLAY "Map end:   ",/A,$
        INCLUDE "interrupts.asm"        ; IM 2 vector table and routine
        DISPLAY "IM2 end:   ",/A,$
        ASSERT $ <= ZOMBIE_ADDR+MEMBANK_SIZE

; The city bank (page 7, always mapped in slot 3): the current city, read
; from its file by load_level.  Indexed alike: row * GRID + column.
        MMU TABLES_SLOT e, PAGE_OCC1, TABLES_ADDR
        ORG TABLES_ADDR
city_col:   ds GRID*GRID                ; colour family of each cell (*4)
city_map:   ds GRID*GRID                ; each cell's code and marks
        ASSERT city_map == CITYMAP_ADDR
        ASSERT $ == TABLES_ADDR+MEMBANK_SIZE

; The sine table: its own page, read at $0000 (slot 0) by get_sin.  $0000
; is 256-byte aligned, as sin_lo / sin_hi need.
        MMU SIN_SLOT e, PAGE_SIN, SIN_ADDR
        ORG SIN_ADDR
        INCLUDE "sin_tables.asm"
        DISPLAY "Sine end:  ",/A,$

; Sprite pattern banks, swapped into slot 7 ($E000) while they load
        MMU SPRBANK_SLOT e, PAGE_SPR0, SPRBANK_ADDR
        ORG SPRBANK_ADDR
        INCLUDE "sprite_data.asm"
        DISPLAY "Spr bank 0 end:",/A,$

;------------------------------------------------------------------------------
    IFDEF RELEASE
        SAVENEX OPEN "release_tmp/zpolice.nex", boot, boot_stack
    ELSE
      IFDEF TEST_HW                     ; (tests/test_hardware.py's build)
        SAVENEX OPEN "tests/hw.nex", boot, boot_stack
      ELSE
        SAVENEX OPEN "zpolice.nex", boot, boot_stack
      ENDIF
    ENDIF
    IFDEF REAL_HARDWARE
        SAVENEX CORE 3,3,0
    ELSE
        SAVENEX CORE 3,0,0
    ENDIF
        SAVENEX CFG 0
        SAVENEX AUTO
        SAVENEX CLOSE
