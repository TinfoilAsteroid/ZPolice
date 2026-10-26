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
;  Controls: Q/A speed up/down   Z stop      O/P turn left/right
;            W/S climb/descend   E/D nose up/down
;            SPACE fire          1-5 select weapon slot
;            0 change the centre slot's weapon
;
;  Source files: zpolice.asm (resident main code), memory_bank_defs.asm
;  (slots and pages).  Game logic pages, swapped into slot 6 at $C000:
;  player.asm (input/movement), weapons.asm, menu.asm (main menu).  Core
;  function pages, swapped into slot 7 at $E000: city.asm (Layer 2
;  drawing), hud.asm (ULA HUD), keys.asm (redefinable keys), sprites.asm
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
        CSPECTMAP zpolice.map
        OPT --zxnext=cspect --syntax=a --reversepop
;------------------------------------------------------------------------------
; Build options
;------------------------------------------------------------------------------
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

; LEVEL_FAST_PATH: while pitch is 0 (level flight) a building's top corners
; have the same camera X and Z as the bottom corners below them, so each top
; corner reuses its bottom corner's screen x and 1/Z and only works out its
; screen y.  Comment it out to project every corner in full.
; Command line: -DLEVEL_FAST_PATH
        DEFINE LEVEL_FAST_PATH

        INCLUDE "memory_bank_defs.asm"  ; MMU slots, registers, addresses, pages

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
TILE_M          equ 20          ; metres per tile (reference scale)
TILE_UNITS      equ 256         ; world units per tile
HEIGHT_M        equ 10          ; metres per height unit
HEIGHT_UNITS    equ 128         ; world units per height unit
NEAR            equ 16          ; near clip plane: 1.25 m
VIEW_R          equ 6           ; buildings drawn within +/- 6 tiles (120 m)
DOT_R           equ 5           ; street intersection markers radius (tiles)
PMAX            equ 24          ; pitch limit (256 = 360 deg) - match gentables.py
SPEED_MAX       equ 28          ; units/frame: 2.2 m/frame, ~31 m/s (110 km/h)
SPEED_MIN       equ -6          ; reverse: 0.47 m/frame, ~6.6 m/s
YAW_RATE        equ $0180       ; turn per frame, 8.8 fixed (1.5 units;
                                ; 256 units = 360 degrees)
CLIMB_RATE      equ 4           ; units/frame: 0.31 m/frame, ~4.4 m/s
; Pitch damper: with neither E nor D held, the nose eases back to level.
; Every PDAMP_FRAMES frames the 8.8 pitch moves towards 0 by
; max(PDAMP_MIN, |pitch| * PDAMP_K) in 1/256ths of a pitch unit, i.e. by a
; fixed share of what is left, so it slows down as it nears level.
PDAMP_FRAMES    equ 1           ; frames between damping steps
PDAMP_K         equ 43          ; 43/256: about 1/6 of the pitch per step
PDAMP_MIN       equ 32          ; smallest step, 1/8 unit, so it reaches 0
MIN_Y           equ 8           ; lowest flight: 0.6 m
MAX_Y           equ 3*HEIGHT_UNITS/2  ; ceiling 1.5 height units: 15 m
BLD_MAX_H       equ 7*HEIGHT_UNITS  ; tallest building 7.0 height units: 70 m
                                ; (htab level 15, gentables.py; 4.7 m a level)
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
WPN_MISSILE     equ 5           ; guided missile (placeholder)
WPN_BOMB        equ 6           ; bomb (placeholder)

; Machine gun rounds: NBULLETS records of BREC bytes in `bullets`
NBULLETS        equ 24          ; rounds in flight (the chain gun needs most)
BREC            equ 27
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
B_KIND          equ 26          ; 0 = round or beam, BK_ROCKET = rocket
BK_ROCKET       equ 1
NOMINAL_FPS     equ 14          ; frame rate the per-frame speeds assume
BULLET_MS       equ 500         ; muzzle velocity, m/s
BULLET_STEP     equ BULLET_MS*TILE_UNITS/(TILE_M*NOMINAL_FPS)  ; 457 units/frame
GUN_DY          equ -6          ; muzzle 0.5 m below the camera
GUN_INTERVAL    equ 4           ; machine gun: frames between rounds
; Chain gun: 4x the machine gun's rate, one round every CHAIN_INTERVAL
; frames.  Each round's heading and climb are turned by a random
; -CHAIN_DEV..+CHAIN_DEV steps of 1/256 rad (0.22 deg): +/-2 degrees.
CHAIN_INTERVAL  equ 1           ; chain gun: frames between rounds
CHAIN_DEV       equ 9           ; spread: 9/256 rad = 2.01 degrees
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

; Humans to rescue (human.asm)
HUMAN_MAX       equ 20          ; room for this many
HUMANS_INIT     equ 5           ; placed at start
PASSENGER_MAX   equ 5           ; the craft carries this many
RESCUE_R        equ 512         ; 2.0 tiles (40 m): a landed craft this close
HUMAN_ROOF_MAX  equ MAX_Y-HEIGHT_UNITS  ; humans aren't placed on roofs
                                ; taller than the ceiling - 1.0 height unit
HUMAN_RUN       equ TILE_UNITS*10/(TILE_M*NOMINAL_FPS)  ; 10 m/s: 9 units/frame
HUMAN_HP        equ 10          ; hit points (a rocket blast kills)
DISEMBARK       equ NOMINAL_FPS ; landed on the base pad: one off a second

; Zombie burst: a killed zombie sprays NPART_BURST particles for PART_LIFE
; frames, bright green fading to dark (weapons.asm moves them, city.asm
; draws them).  Particle record: +0 age (0 = free, 1..PART_LIFE), +1..+6
; x, y, z (world units), +7..+9 vx, vy, vz (signed units per frame).
NPART           equ 40          ; pool: room for 4 bursts at once
NPART_BURST     equ 10
PART_LIFE       equ 8
PREC            equ 10
PART_Y          equ 13          ; bursts from 1 m up
PART_GRAV       equ 1           ; vy lost per frame (they arc up and fall)

; The level a new game starts on.  Normally 1; DEBUG: 20, to test the
; zombies' attacks on the base (junction bias 48 + 2 * level = 88%).
START_LEVEL     equ 20

; Zombies against the base (zombie.asm)
ZBIAS_BASE      equ 48          ; junction bias towards the pad, percent:
ZBIAS_STEP      equ 2           ; 48 + 2 * level (50% on level 1),
ZBIAS_MAX       equ 95          ; at most 95%
ATTACK_R        equ 26          ; a zombie attacks a base tile from 0.1 tile (2 m)
ZHIT_FRAMES     equ 5           ; one hit every 5 frames, 1 damage each
TERRACE_HP      equ 100         ; hit points of each green terrace tile
PAD_HP          equ 200         ; and of the landing pad (destroyed: game over)
GAME_OVER_FR    equ 500         ; game over screen: 10 s of 50 Hz frames

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
BULLET_COL      equ 31
LASER_COL       equ 35
MAP_BG          equ 39
MAP_ZOMBIE      equ HUD_COL     ; zombie blips on the city map: bright green
HUMAN_COL       equ 43
HUMAN_BLIP      equ 47
MAP_ZOMBIE_MID  equ 51          ; zombie blip shades (bright = MAP_ZOMBIE)
MAP_ZOMBIE_DARK equ 55
MAP_ZOMBIE_ATK  equ HUD_WARN    ; a zombie attacking the base: red
ZOMBIE_COL      equ 27
PANEL_L2        equ 91          ; the ULA panel colour, on Layer 2 (compass)
GAUGE_AMBER     equ 95          ; ground height gauge (Layer 2)
PART_COL0       equ 59          ; zombie burst particles: age 1 (bright) ..
PART_COL1       equ 63
PART_COL2       equ 67
PART_COL3       equ 71
PART_COL4       equ 75
PART_COL5       equ 79
PART_COL6       equ 83
PART_COL7       equ 87          ; .. age 8 (dark); a step of 4 per age

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
C_BLUE          equ 5           ; ink: light blue (empty weapon slot)
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
PAX_COL         equ 5               ; passengers: first character column
; Compass: a 32x8 strip at pixel (COMP_X, COMP_Y) in a 2-pixel frame, on
; Layer 2 behind transparent ULA cells (columns 15-20, character rows 19-20)
COMP_X          equ 128
COMP_Y          equ 156
COMP_BGX        equ 120             ; its 48x16 background patch
COMP_BGY        equ 152
PAX_ROW         equ 17              ; passengers aboard (pixel row 136), and
WPN_LBL         equ 11              ; the weapon slots: "WPN:" at this column,
WPN_COL         equ 15              ; slot digits 1-5 from this one
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

; HL = HL * GRID  (a map row offset)
        MACRO ROWOFS
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ENDM

; dst = src + vec  (three 16-bit components)
        MACRO VADD QD, QS, QV
        ld hl,(QS)
        ld de,(QV)
        add hl,de
        ld (QD),hl
        ld hl,(QS+2)
        ld de,(QV+2)
        add hl,de
        ld (QD+2),hl
        ld hl,(QS+4)
        ld de,(QV+4)
        add hl,de
        ld (QD+4),hl
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
            ds 16                       ; the loader's stack, until start
boot_stack:

        MMU MAIN_SLOT e, PAGE_MAIN, MAIN_ADDR
        ORG MAIN_ADDR
        ; the generated tables (gentables.py); the sine table is in its own
        ; page (PAGE_SIN, slot 0), below
        INCLUDE "htabs.asm"             ; hztab (horizon), htab (heights)
        INCLUDE "city_map.asm"          ; city_map, base / wall constants
        INCLUDE "l2_pallets.asm"        ; l2_palette

;==============================================================================
; Entry
;==============================================================================
start:
        di
        ld sp,stack_top
        nextreg CODE_MMU,PAGE_INIT      ; hardware set-up and memory map
        call initgame                   ; (initialise.asm)

        ; load the shaded Layer 2 palette (first L2 palette, 9-bit entries)
        nextreg $43,%00010000           ; edit Layer 2 palette 0, auto-inc
        nextreg $40,0
        ld hl,l2_palette
        ld b,0                          ; 256 entries
.pal:   ld a,(hl)
        inc hl
        nextreg $44,a                   ; RRRGGGBB
        ld a,(hl)
        inc hl
        nextreg $44,a                   ; low blue bit
        djnz .pal

        ld a,r                          ; random seed (xorshift: non-zero);
        ld l,a                          ; the menu stirs it every frame
        ld h,$A5
        ld (zseed),hl
        nextreg CODE_MMU,PAGE_KEYS
        call kbd_double_off             ; NextReg $68 bit 4 = KBD_STOP_DOUBLING
        nextreg CODE_MMU,PAGE_HUD
        call ula_palette                ; ULA inks and papers (menu and HUD)
        nextreg CODE_MMU,PAGE_SPRITES
        call sprites_init               ; (sprites.asm) on, all hidden
        nextreg CODE_MMU,PAGE_SPR0      ; sprite bank 0: the human status
        call spr_load_bank              ; sprites (sprite_data.asm)
        nextreg LOGIC_MMU,PAGE_MENU     ; (the menu pages the keys in)
        jp main_menu                    ; (menu.asm) -> newGame

;==============================================================================
; New game: start level 1.  Start-up has set the hardware (speed, layers,
; clip window, palettes, memory map), which the menu leaves alone; here the
; game state and the screen contents are set up from scratch, so this also
; works for a second game.
;==============================================================================
newGame:
        ld sp,stack_top                 ; (entered by jp from the menu)
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
        xor a
        ld (game_over),a
        ld hl,0
        ld (salvage_points),hl          ; no salvage yet
        call base_init                  ; the pad and terrace, at full strength
        nextreg LOGIC_MMU,PAGE_WEAPONS
        call weapons_reset

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

;==============================================================================
; Main loop
;==============================================================================
main_loop:
        nextreg CODE_MMU,PAGE_KEYS      ; keys at $E000, while the logic runs
        call kbd_scan                   ; all key banks
        nextreg LOGIC_MMU,PAGE_PLAYER   ; input/movement logic at $C000
        call update_player
        call setup_frame
        call zombie_update              ; walk the zombies (page at $2000)
        nextreg LOGIC_MMU,PAGE_WEAPONS  ; weapons logic at $C000
        call update_weapons             ; fire, move rounds, hits
        call human_update               ; map dots, rescues (page at $7000)
        ld a,(game_over)
        or a
        jr z,.play
        nextreg LOGIC_MMU,PAGE_MENU     ; the pad is destroyed: game over
        jp game_over_screen             ; (menu.asm) -> main menu
.play:
        call map_shadow
    IFDEF DRAW_FPS
        call vtick
    ENDIF
        nextreg CODE_MMU,PAGE_CITY      ; Layer 2 drawing code at $E000
        call clear_screen
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
        call draw_gunsight
        nextreg CODE_MMU,PAGE_HUD       ; ULA HUD code at $E000
        call draw_hud
    IFDEF WAIT_FOR_VBLANK
        call wait_vblank
    ENDIF
        call l2_flip
    IFDEF DRAW_FPS
        call fps_tick                   ; HUD page is still at $E000
    ENDIF
        jp main_loop

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

    IFDEF DRAW_FPS
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
        or a
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
game_over:  db 0                        ; 1: the landing pad was destroyed
salvage_points: dw 0                    ; salvage points, 16-bit (newGame: 0)
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
            db WPN_ROCKETS, ROCKET_SHOTS  ; 1: left outer pylon: rocket pod
            db WPN_NONE, 0              ; 2: left inner pylon
            db WPN_NONE, 0              ; 3: right inner pylon
            db WPN_NONE, 0              ; 4: right outer pylon
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

        MMU CODE_SLOT e, PAGE_HUD, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "hud.asm"
        DISPLAY "HUD end:   ",/A,$

        MMU CODE_SLOT e, PAGE_KEYS, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "keys.asm"
        DISPLAY "Keys end:  ",/A,$

        MMU CODE_SLOT e, PAGE_SPRITES, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "sprites.asm"
        DISPLAY "Sprites end:",/A,$

        MMU CODE_SLOT e, PAGE_INIT, CODE_ADDR
        ORG CODE_ADDR
        INCLUDE "initialise.asm"
        DISPLAY "Init end:  ",/A,$

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

;==============================================================================
; Always mapped
;==============================================================================
        MMU ZOMBIE_SLOT e, PAGE_ZOMBIE, ZOMBIE_ADDR
        ORG ZOMBIE_ADDR
        INCLUDE "zombie.asm"
        DISPLAY "Zombie end:",/A,$

        MMU TABLES_SLOT e, PAGE_OCC1, TABLES_ADDR  ; cell colours, kept mapped
        ORG TABLES_ADDR
        INCLUDE "tables_col.inc"
        DISPLAY "Colours end:",/A,$
        ORG HUMAN_ADDR
        INCLUDE "human.asm"
        DISPLAY "Humans end:",/A,$
        INCLUDE "map.asm"
        DISPLAY "Map end:   ",/A,$
        ASSERT $ <= $8000

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
        SAVENEX OPEN "zpolice.nex", boot, boot_stack
        SAVENEX CORE 3,0,0
        SAVENEX CFG 0
        SAVENEX AUTO
        SAVENEX CLOSE
