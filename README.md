# Z-Police

A 3D vector graphics flight game for the ZX Spectrum Next, written in Z80N
assembler. You fly a VTOL craft around a city of 32×32 blocks, in the spirit
of *Sky Ranger*. Buildings fill whole grid cells, so the city is solid blocks
between one-cell-wide streets. Buildings are drawn as white vectors over solid faces, each
building in its own shaded colour, with true hidden line removal, on Layer 2 at
256×192 with 256 colours. The 3D view uses the top two thirds of the screen
(256×128), and the bottom third is an instrument panel.

![boulevard](docs/boulevard.png) ![turning](docs/turning.png) ![overhead](docs/overhead.png)

## Building and running

Requirements: sjasmplus 1.20+ (built with Z80N support) and Python 3. To run
it, use CSpect or real Next hardware.

```
build.bat          # gengraphics.py, gentables.py -> the generated tables and ZPDATA/, then sjasmplus -> zpolice.nex, then the tests
build.bat run      # ...and launch CSpect (sound off: CSpect's -sound)
build.bat runsound # ...and launch CSpect with sound on
build.bat notest   # ...without the regression tests (also: build.bat run notest)
```

A failing test stops the build before CSpect is launched (see "Regression
tests").

**The game needs its data files.** The levels and cities are files in the
`ZPDATA` folder, made by `gentables.py`. Copy the folder to the SD card
beside `zpolice.nex`. Without it, New Game shows "CANNOT LOAD LEVEL" and
returns to the menu.

**Start level:** for testing, assemble with `-DSTART_LEVEL_SET=n` to start
on level n. Otherwise `START_LEVEL` (1) is used.

Manually:

```
python gentables.py
sjasmplus --zxnext zpolice.asm
CSpect.exe -w3 -zxnext -s28 zpolice.nex
```

### Build options
These are set with `DEFINE` near the top of `zpolice.asm`, or with `-D` on
the sjasmplus command line:

| Option | Default | Effect |
|--------|---------|--------|
| `DRAW_LINES` | off | outline building faces in white |
| `WAIT_FOR_VBLANK` | off | flip buffers only in vertical blank (no tearing, slower) |
| `DRAW_FPS` | off | measure and show frames per second on the ULA |
| `SKY_IS_WALL` | on | fill the sky in the perimeter wall's colour and draw the wall only up to camera height, below |
| `LEVEL_FAST_PATH` | on | shortcuts for level flight (pitch 0), below |
| `OCCLUSION_CULL` | on | in level flight, skip buildings completely hidden behind nearer ones, below |

**`OCCLUSION_CULL`:** at street level most buildings in view end up
completely hidden behind the ones lining the street. Measured before this
option, they took 31–47% of the frame, yet the painter's algorithm still
transformed, clipped and filled them. In level flight every screen column is
a vertical slice of the world through the camera, which allows a cheap,
exact test:
* **Front to back:** the cells are walked in exactly the reverse of the
  painter's order (`occ_cells`). Each half row starts from the same cell
  and steps the same way, so the coordinates are bit-identical.
* **Cover buffer:** `OCC_YBUF` (256 bytes) holds, for each column, the row
  from which the screen is known to be covered down to the ground.
* **Test before the transform:** `occ_pretest` estimates a building's screen
  box from its cell centre, a circle of radius 188, its height, and the
  nearest and farthest depth, widened by a pixel. If every column of that
  box is already covered from its top down, the building is dropped before
  any transform.
* **Exact test after the transform:** otherwise, after the transform, the
  same test runs on the exact corners of the faces that will be drawn
  (`occ_record`). A hidden building is still dropped. A visible one lowers
  the cover to its lowest top corner across its columns. Its corners
  (9 of each 16 bytes) and face settings (`OR_VIS`, in the first corner's
  spare bytes) go into a 128-byte record.
* **Two records a page:** a record sits at `+0` or `+128` in a 256-byte
  page, with its corners at the same offsets as in `vtx`. The face drawer
  reads corners as `vtx_hi`:offset, so for a record in the upper half
  `draw_face` uses a second set of corner lists with 128 added (`face_hi`;
  `face_set` = `FACE_SET2`, set by `occ_draw_list`). No corner read changes.
  The 3D clipper keeps a cached corner as its offset / 2, which stays below
  `$80`, the mark of a new point. The cost is about 0.1% of a frame.
* **Cut rows (partly hidden buildings):** when a building is recorded,
  the cover buffer holds only the nearer buildings', which are drawn after
  it. So in its columns, rows from the most of their cover rows down are
  hidden in every column. `occ_cut` finds that row from the `OCC_YBUF8`
  bounds of the groups of 8 the building spans (never too high, so exact).
  It is kept with the record (`bld_cut`, the 7th setting).
  * `fill_poly` fills no row from it down, and skips a face that starts
    below it. The picture is unchanged: those rows are painted over later.
  * Over the ten test views it saves 0.3% in all, up to 2.2% at street
    level; one level view (view 0) is 0.3% slower, as its cut rows save
    less than finding them costs. Pitched views (no occlusion) pay about
    0.1% for the check.
  * A first version scanned the end groups column by column for a lower
    cut, but cost more than it saved.
  * Tried and reverted (2026-11-02): a cut per face, from each drawn face's
    own columns (the x side, the z side and the roof, worked out when the
    building is recorded, kept in the record's spare bytes). It cuts more
    rows (3–20% of the faces' rows in the street views, against fewer per
    building), but the up to three searches per building (about 500 T each,
    even with the corners unrolled and the range in registers) cost more:
    every street view was 0.1–1.5% slower than with one cut per building.
* **Draw back to front:** the kept buildings and the cells with zombies
  are then drawn in painter's order (`occ_draw_list`). `draw_face` reads
  corners from the record via `vtx_hi`. A list entry is the record's
  address.
* **Memory:** the cover buffer (`$4000`), the list (`$4100`), `OCC_YBUF8`
  (`$4200`) and the records (`$4300`–`$5FFF`, 58) live in page 6
  (`PAGE_OCC0`, slot 2). The busiest test view at the full draw distance
  (8 tiles) keeps 35. If they ever run out, that frame is drawn the plain
  way (every building again, in painter's order).
* **When it runs:** only in level flight. With the nose pitched the plain
  painter's path runs unchanged.

Why it can't hide something visible:
* Buildings that share a column reach the test front to back; the grid
  order guarantees this.
* The camera is above the ground, so anything behind sits higher on the
  screen.
* Each cover row is the lowest top corner, which underestimates the cover.
* Screen bounds are clamped inwards.
* A building with a corner behind the camera is never dropped and never
  used as cover.

To make the claims hold to the pixel, vertices the clipper puts on a screen
edge plane are now pinned exactly to that edge: row 0, row 127, column 0 or
column 255. Before, projection rounding could leave them one pixel inside,
which showed slivers of farther buildings along the top row.

With occlusion on and off, 300 frames of six flights and 42 frames of seven
views are pixel-identical. Frames per second, off → on:

| Run | Off | On |
|-----|-----|----|
| Street flight | 14.75 | 18.29 |
| Turning flights | 14.78 / 14.15 | 17.22 / 18.96 |
| Climb to the ceiling, then fly / then turn | 13.62 / 13.34 | 18.02 / 16.61 |
| Pitching flight (mostly pitched) | 13.81 | 15.00 |
| City centre, fixed views | 12.33 / 12.69 / 12.18 | 18.28 / 17.48 / 15.88 |
| Facing the wall (little to hide) | 30.60 | 27.43 |

**`SKY_IS_WALL`:** the ceiling (`MAX_Y`, 1.5; 3.0 with the vertical
thrusters, `MAX_Y_THRUST`) is far below the perimeter wall (7.0), so the
wall rises above the horizon in every direction.
* The sky fill uses the wall's colour (`WALL_FAMILY`, base shade), and
  includes the horizon row itself. At the horizon it is all distant wall,
  and this also hides a 1-row rounding gap when pitched.
* Wall cells are drawn as buildings of height `cam_y`. A point at camera
  height always projects onto the horizon, at any pitch, so only the strip
  of wall below the horizon is filled.
* All of a wall cell's sides use the base shade, to match the fill.
* No real sky is ever seen.

| View (fixed, 3 frames) | Off | On |
|------|-----|----|
| Facing the wall, 2 cells away | 34.0 fps | 46.3 fps |
| Facing the wall, 3 cells away | 21.5 | 30.7 |
| Diagonal towards the wall | 17.2 | 23.3 |
| Near the ceiling, facing the wall | 20.3 | 25.3 |
| Nose up / nose down, facing the wall | 14.9 / 17.0 | 21.4 / 22.2 |
| City centre (wall out of draw range) | 12.45 | 12.39 |

With `DRAW_LINES` on, the wall's top edge is outlined along the horizon.

With no roll and pitch at 0, a vertical building edge has the same camera X
and Z all the way up. `LEVEL_FAST_PATH` uses that in two places:
* **Corners:** each top corner reuses the screen x and 1/Z of the bottom
  corner below it, and only works out its own screen y.
* **Clipper:** where a vertical edge crosses the top or bottom of the view,
  the crossing point is simply (X, ±0.5Z, Z). It needs no divide and no
  interpolation. Vertical edges can't cross the near or side planes at
  pitch 0, so that covers every crossing they make.
* **No multiplies by the pitch** (always, not a switch): at pitch 0, cosP is
  exactly 1.0 (256) and sinP 0, so `draw_bld` takes the frustum test's
  |X|·c as |X|, the vertical edge vector as (0, h, 0), and `rot_pitch`
  gives Y = yb, Z = zb + Z1, with no `fmul` (5 a building).

Separately, at any pitch, building corners that pass through the clipper
unchanged and are already on screen reuse their cached projection, rather
than being projected again.

The images are identical with or without these. Measured over 50 frames,
compared with the corner-only fast path:

| Flight | Before | Now |
|--------|--------|-----|
| Level, street height | 14.61 fps | 14.94 fps |
| Level, at altitude | 13.38 fps | 13.80 fps |
| Pitching down and back to level | 13.88 fps | 14.13 fps |

Over a 20-frame street flight, 237 of 688 clip intersections skip the
divide, and 385 projections are replaced by cached ones.

## Main menu (`menu.asm`)
After start-up the game shows a main menu:

| Key | Option |
|-----|--------|
| 1 | **New game**: the load-out screen, then level 1 (`newGame` in `zpolice.asm`) |
| 2 | **Continue saved game**: the game saved with save and quit, at its level and wave (NO SAVED GAME if there isn't one) |
| 9 | Redefine keys (`keydef.asm`) |

## Save games
**Save and quit:** pause (BREAK), then **S** (shown as S: SAVE AND QUIT under
PAUSED). The game is saved to `ZPDATA/SAVEGAME.ZPS` on the SD card and the
main menu comes back. If it can't be written, SAVE FAILED shows and the game
stays paused. A wreck can't be saved. There is one save: saving again
replaces it.

**Quit without saving:** pause, then **X** (X: QUIT, NO SAVE, under the
save line). The main menu comes back at once and the game is lost. Any save
game on the SD card is left as it was, so CONTINUE still goes back to it.
X works in a wreck too.
* **Saved** (`sg_fields`, zpolice.asm): the level and wave, the salvage, the
  VTOL's integrity (`vtol_hp`), its weapon slots (type and ammo each) and
  the selected one, the store (`wpn_stock`, `wpn_unlocked`), the
  booster (fitted, fuel), the vision modes (`vision_owned`: `VIS_*`
  bits), the vertical thrusters (`vthrust_fitted`) and the lateral
  thrusters (`lthrust_fitted`). The file is "ZPSV", a version byte
  (`SG_VERSION`, 5), then those fields: 48 bytes (the store grew by the
  two linked chain guns at version 5). An older file (version
  1, from before the vision modes, 2, before the vertical thrusters, 3,
  before the lateral thrusters, or 4, before the linked chain guns) is
  refused as having no save game.
* **Continue** (main menu 2): `load_save` reads and checks the file (its
  size, "ZPSV", the version, the level 1–50), then `continue_game` starts a
  new game (`game_reset`, as `newGame` without the load-out screen), lays
  the saved fields over it (`sg_copy`) and starts the saved level at the
  saved wave (`resume_wave`, which `next_level` uses once; kept within the
  level's waves).
* **Not saved:** the level carries on afresh at that wave: its zombies and
  specials are placed new, as are the humans, and this level's rescues so
  far start again from 0 (restoring them with new humans would let the same
  ones be rescued twice). The base is at full strength, as at any level's
  start.

**Game over:** when the landing pad is destroyed, the main loop goes to
`game_over_screen` (`menu.asm`). It shows GAME OVER for `GAME_OVER_FR` (500)
video frames, 10 seconds, and then returns to the main menu. The menu
times frames from the raster line. It reads NextRegs `$1E`, `$1F`, `$1E`
and retries if the high byte changed, because a read straddling line 256
would otherwise look like line 0 and end a frame early.

* **Drawing:** the menu is in its own page (`PAGE_MENU`, page 8, at
  `$C000` in slot 6). It's drawn on the ULA screen with opaque paper, with Layer 2
  hidden, using an 8×8 font generated by `gentables.py` (`tables_font.inc`:
  space, digits, A–Z, `. - :`).
* **Seeding:** each frame it waits for the next video frame and calls the
  random number generator (`zrand`). It's seeded once from the R register
  at power-on. How long you wait before pressing a key changes where the
  zombies and humans are placed: a different wait gives a different
  layout.
* **Start-up vs `newGame`:** start-up sets the hardware once: 28 MHz,
  Layer 2 mode, clip window, layer priority, memory map, the ULA palette,
  `$68` and the SD card's default drive (`fh_init`). The Layer 2 palette is
  each city's own, loaded with the level. The menu leaves those alone, so they aren't redone. `newGame`
  resets everything else, so it also works for a second game:
  * the player state from `start_state`: position on the base pad,
    heading, pitch, speed, weapon slots, selected slot, slot flash;
  * no rounds or laser beam, the gun and laser timers, `level` =
    `START_LEVEL`, `salvage_points` = `START_SALVAGE` (a 16-bit score, 0);
  * the level's files (`load_level`): its record, its city's map, colours
    and palette, its draw distance. See "Levels and cities".
  * both Layer 2 buffers cleared and Layer 2 made visible again;
  * the ULA panel and the city map (`ula_init`, which also makes the HUD
    redraw its passenger and weapon rows);
  * zombies and humans (passengers and saved = 0). Each first clears its
    marks in `city_map` (bits 7 and 6), since a new game reuses the map.

## Engine sound

The VTOL's engines are jet turbines, so they make a steady roar and whine
rather than a rotor's chop. They have AY 1 to themselves, all three
channels (`audio.asm`); AY 2 and 3 are free for sound effects and music.
* **Never off in play:** at zero throttle the engines idle, sounding as at
  speed 1. Reversing sounds by the speed's size.
* **Pitch and volume rise with speed.** From n = |speed|, at least 1 and at
  most `SPEED_MAX` (28):
  * **Channel A, the roar:** noise, period 29 − n×13/16 (29 at idle, a
    rumble; 7 flat out, a hiss), volume 4 + n×7/32 (4 to 10).
  * **Channel B, the turbine whine:** a tone of period 222 − 3n, about
    500 Hz at idle to 790 Hz flat out (the Next's AYs run at 1.75 MHz: a
    period P is 109375/P Hz), volume 2 + n×7/32 (2 to 8).
  * **Channel C, the shimmer:** the same whine 2 periods lower and 2
    quieter (silent at idle). The two beat against each other, as twin
    turbines do.
  * (Since the first version: the top pitch is down from 1.9 kHz to 985 Hz,
    then to 790 Hz, 80% of that. Every volume is 2 levels lower, about half
    as loud, and the full-speed volume a further level lower, about 80%:
    the AY's levels are roughly 2–3 dB apart. The rise with speed is
    `ENG_VOL_MUL`/32 a step.)
* **Spooling up and down:** the interrupt routine plays the engines, 50
  times a second (`engine_tick`, interrupts.asm). `eng_cur` is the speed
  the engines sound at, in sixteenths of a speed step (`ENG_FRAC`). Each
  interrupt it moves towards the VTOL's n by at most `ENG_SPIN_UP` (4/16)
  going up and `ENG_SPIN_DOWN` (2/16) going down. So the turbines spool up
  over about 2 seconds from idle to full speed, and run down more slowly,
  about 4 seconds, instead of jumping with the speed.
  * The whine's period uses the fractions, so it glides; the roar's noise
    and the volumes use the whole steps (m = `eng_cur` / 16) in the
    formulas above, in place of n.
  * At the start of a level `eng_cur` is 0, so the engines spool up to the
    idle.
* **When:** `next_level` calls `engine_start`: AY 1's mixer (A noise only, B
  and C tones only), `eng_cur` 0, then `eng_on` 1. The interrupt writes the
  registers only when `eng_cur` moves, and nothing while `eng_on` is 0.
  Every menu screen silences all three chips (`menu_clear` calls
  `init_audio`, which first sets `eng_on` to 0).
* **Tuning:** the `ENG_*` constants at the top of `audio.asm`, with
  `ASSERT`s that keep periods and volumes in range.
* While paused the engines keep the sound they had.

## Sound effects

Sound effects play from the interrupt routine (`sfx_tick`, interrupts.asm),
on three voices, so none cuts another: the weapons on AY 2, explosions on
AY 3's channels A and B, and splats on AY 3's channel C. The engines keep
AY 1. (Music would need AY 3 back.)
* **Asking for one:** the game puts the sound's number in a voice's request
  byte: `sfx_req` for the weapons, `sfx2_req` for explosions, `sfx3_req` for
  splats (`ld a,SFX_MG` / `ld (sfx_req),a`). That's one byte, so it is safe from any page at any time,
  and only the interrupt writes the AY chips (see "Interrupts"). Each voice
  plays one sound at a time: a new one cuts the last (`sfx_voice`).
* **Format:** a sound is a list of steps, one per interrupt (20 ms). Each
  step is AY register / value pairs, ended by `SFX_STEP` (the next step at
  the next interrupt) or `SFX_END` (the sound is over). `sfx_table` lists
  the sounds by number (`SFX_*`, audio.asm). The sounds are in
  `sfx_data.asm`, in the resident main page (slot 5, always mapped, so the
  interrupt can read them whatever else is paged in).
* **Silent in menus:** nothing plays while `eng_on` is 0, and `init_audio`
  clears any request or sound in progress.
* **Machine gun (`SFX_MG`, `sfx_mg`):** a heavy machine gun, one short sound
  per round (`gun_fire`, weapons.asm), 80 ms long:
  * channel A: noise, a sharp crack (noise period 4, volume 13) dropping
    into a deep boom (period 18, then 26) as it fades;
  * channel B: a low thump, a tone of about 70 Hz (period 1563), fading
    with it (11, 9, 5, 2);
  * then silent. The gun fires every `GUN_INTERVAL` (4) game frames, about
    a quarter of a second apart, so each round's sound is over before the
    next.
* **Chain gun (`SFX_CHAIN`, `sfx_chain`):** the machine gun's sound 25%
  higher in pitch: every period 4/5 of it (the thump about 88 Hz, period
  1250; noise 3, 14, 21). It fires every game frame, so each round cuts the
  last one's tail after 3 or 4 steps: a rattle.
* **Laser (`SFX_LASER`, `sfx_laser`):** a zap at the start of each pulse
  (`laser_update`): a tone sweeping down from about 2.7 kHz to 470 Hz
  (periods 40 to 235) on channel A, with a second one 2 periods flat on
  channel B, beating against it as a buzz. It fades over 140 ms (the
  `SFX_ZAP` macro builds each step). Pulses come about 0.7 s apart.
* **Autocannon (`SFX_AUTOCANNON`, `sfx_autocannon`):** the machine gun's sound,
  deeper and louder: the thump 30 Hz (period 3646), the noise periods
  doubled, and every volume 2 levels up, about twice as loud (crack 15 /
  13, then 12 / 11, 8 / 7, 5 / 4). The AY's noise period stops at 31, so
  the boom's later steps (18 and 26 doubled) are 31, and its volume at
  15. The proximity cannon fires its shells
  the same way, so it has this sound too.
* **Rocket (`SFX_ROCKET`, `sfx_rocket`):** a short woosh, 200 ms: noise only
  on channel A, swelling (7 to 13) and fading, brightening (noise period 12
  to 6) then darkening (to 20) as it goes. The `SFX_WOOSH` macro builds
  each step.
* **Missile (`SFX_MISSILE`, `sfx_missile`):** a longer woosh, 320 ms, a
  little deeper (period 14 to 8 to 26), its roar held at its loudest (13)
  for longer before it fades.
* **Explosions (`SFX_BOOM_*`, on AY 3):** wherever a rocket, missile,
  autocannon or proximity shell bursts (`rocket_blast`). A deep noise darkening
  as it goes (period 16 to 30) over a low rumble (about 40 Hz), fading to
  nothing. The `SFX_BOOM` macro builds each from its peak and length.
  * Loudness is in proportion to the blast's size, damage × reach (game
    units): missile 15 × 256 = 3840, rocket 20 × 64 = 1280, autocannon 4 × 38
    = 152, proximity 3 × 25 = 75. The AY's levels are logarithmic, about 2
    levels each doubling, so the peak is 15 + 2·log₂(size ÷ the
    missile's): 15, 12, 6 and 4.
  * The bigger the blast, the longer it rumbles: 2 steps (40 ms) per level,
    600, 480, 240 and 160 ms.
  * The levels fall in a straight line, which on the AY's logarithmic scale
    is an exponential fade.
* **Splat (`SFX_SPLAT`, `sfx_splat`, on AY 3 channel C):** whenever a
  zombie, fast zombie or ghoul takes damage (`zdamage`: a round, a laser
  beam frame or a blast); not ghosts or banshees. A squelch: a tone lurching
  down and up as it falls (periods 160, 320, 210, 450, 280, 620, 400, 850:
  about 680 Hz to 130 Hz), a wet gargle, fading from 12 over 160 ms. Each
  hit cuts the last one's splat, so a chain gun raking zombies restarts it
  each time. (`SFX_SPLAT_STEP` builds each step.)
  * Channel C shares AY 3 with the explosions, and the chip's noise
    generator is theirs, so the splat is a tone only. It writes only
    channel C's tone and volume, and the explosions set AY 3's mixer with
    C's tone on (`SFX_MIX_BOOM`) and leave channel C alone, so the two play
    together.
* **Crash (`SFX_CRASH`, `sfx_crash`, on AY 3 A and B, the explosions'
  voice):** when the VTOL hits a building (`player.asm`, with the screen
  shake: see "HUD", "Screen shake"). A low crunch, like a missile's blast
  but deeper and shorter:
  * a cracking hit (noise period 12, volume 15), then the crunch (22, 28);
  * then the deepest noise (31) over a 27 Hz rumble (tone period
    `CRASH_RUMBLE` 4000, channel B; the blasts' is 40 Hz);
  * fading from 13 over 10 steps: 260 ms in all.

  It replaces any explosion playing.
* **Room:** the player is in slot 1 with the interrupt routine (about 100
  bytes left); the sounds are in the resident page.

## Interrupts

Interrupts are on from the main menu onwards, in IM 2 (`interrupts.asm`),
50 a second. The routine plays the engines (see "Engine sound").
* **Its own stack:** `im2_routine` saves SP and switches to `isr_stack` at
  once, before any PUSH, then keeps every register it uses.
* **The span filler borrows SP** (city.asm): it points SP into a Layer 2
  span and fills it with PUSHes. An interrupt there pushes its return
  address just below SP, into the part of the span still to be filled,
  which the PUSHes then overwrite. That fails only after the last PUSH, so
  interrupts are off (`push_blk`: a `DI` before the last PUSH, `EI` once SP
  is back) for those few instructions. One arriving meanwhile waits: the
  interrupt line is held far longer. A 1-pixel span doesn't borrow SP at
  all (`push_next`).
* **File loads:** `fh_rom_in` turns interrupts off over esxDOS calls (the
  ROM covers slot 1, where the routine is), and `fh_rom_out` turns them
  back on if they were on.
* **Shared hardware:** the routine writes only the AY ports, never `$243B`
  (the main code's NextReg select), so the main code's NextReg reads are
  safe. Code outside the routine writes the AY chips only while `eng_on`
  is 0 (`init_audio`, `engine_start`); future sound effects on AY 2 and 3
  must do the same, or turn interrupts off around their writes.
* **Tested** in the emulator: with interrupts at 50 Hz, and with over
  60,000 interrupts in 30 frames (one every ~2,000 T-states, and 25,000
  forced at the last moment before the `DI`), every frame's Layer 2 was
  identical to a run with none. (The emulator enables interrupts at `EI`
  at once; the test allows for the Z80's one-instruction delay.)

## Controls

| Key | Action          | Key | Action          |
|-----|-----------------|-----|-----------------|
| Q   | speed up        | A   | slow down / reverse |
| Z   | air brake       |     |                 |
| O   | turn left       | P   | turn right      |
| W   | climb           | S   | descend         |
| E   | nose up         | D   | nose down       |
| SPACE | fire the selected weapon (hold) | 1–5 | select weapon slot: 1 = centre, 2–5 = wing pylons |
| R   | tilt the centre gun up | F   | tilt the centre gun down |
| V   | recentre the centre gun | 0 / 9 | debug: kill all / next city (see below) |
| 8   | debug: change the centre gun (see below) | N | next vision mode (once one is fitted: see below) |
| BREAK | pause / resume | X | boost on / off (once the booster is fitted: see below) |
| K   | strafe left (once the lateral thrusters are fitted: see below) | L | strafe right |

**Joystick:** Kempston or Mega Drive (3 or 6 buttons), in either joystick
port, set up in the Next's own joystick settings. By default joystick 1's
stick turns and climbs or descends and FIRE fires. On a Mega Drive pad, C and
A are speed up and down and START pauses; on a 6-button pad, X is the air
brake, Y / Z nose up and down, and MODE the boost. Every control can be given any key and any
joystick input on the redefine keys screen (main menu, 9). See "Input" below.

**Debug kill all (keys 0 and 9, `DEBUG_KILLALL` in `zpolice.asm`):** pressing 0
in flight wipes out the wave at once:
* every monster record goes inactive: zombies, ghouls, ghosts and
  banshees, including any still fading out. Their map blips go off and
  nothing is left attacking the base or a barricade.
* every human still waiting in the city or aboard the VTOL counts as
  rescued (`saved`), and the VTOL is left with no passengers.
* the next frame, `zombie_update` finds no monster active and starts the
  next wave, with its specials. After the last wave, the level is complete
  (salvage, then the load-out screen).

**Key 9** does the same, but ends the level and moves on to the first
level of the next city (`CITY_LEVELS`, 5 levels each): level 2 goes to 6,
5 to 6, 6 to 11. It sets `level` to the current city's last level and
`wave_number` to the level's last wave, so the level complete screen
follows at once and moves `level` on by one as usual. From the last city
(levels 46–50) it goes to the game complete screen.

**Key 8** changes the gun in the centre slot (slot 1): machine gun, then
laser, then chain gun, then the machine gun again. Anything else there
becomes the machine gun. The new gun has its full (infinite) load, and the
centre slot is selected, so SPACE fires it at once (`debug_gun_cycle`).

The keys are fixed (`KB_0`, `KB_9`, `KB_8`, read with `key_code_pressed`,
in `debug_killall` and `debug_gun_cycle`, weapons.asm). They aren't on the
redefine keys screen, so don't define 0, 8 or 9 as a control while they are
on. Set `DEBUG_KILLALL equ 0` for a release: the code and the keys go.

**Debug load-out (`DEBUG_LOADOUT` in `zpolice.asm`):** a new game starts with
every weapon unlocked and `DEBUG_STOCK` (4) of each in store, so they can all
be fitted on the load-out screen before level 1, the bomb too. The machine
gun is still fitted in slot 1 as
well. Set `DEBUG_LOADOUT equ 0` for a release, and a new game starts with
the machine gun only.

**Input (`input.asm`): keyboard and joysticks.** Every control is
redefinable. The game asks about *actions* (`K_FIRE`, `K_LEFT`, …). Each
action has a key (`key_defs`) and a joystick input (`joy_defs`, 0 for
none), and either one works.
* **Input codes:** an input is a 16-bit code (`KB_Q`, `KB_UP`, `J1_FIRE`,
  …): the input bank in the high byte, the bit mask in the low byte.
  * Banks 0–7 are the ZX Spectrum half-rows (port `$xxFE`, address line
    A8+bank low): `$FEFE` SHIFT Z X C V up to `$7FFE` SPACE SYM M N B.
    These read 0 = pressed.
  * Bank 8 is NextReg `$B0`, Extended Keys 0: RIGHT, LEFT, DOWN, UP, `.`,
    `,`, `"`, `;` (bits 0–7).
  * Bank 9 is NextReg `$B1`, Extended Keys 1: EXTEND, CAPS LOCK, GRAPH,
    TRUE VIDEO, INV VIDEO, BREAK, EDIT, DELETE.
  * Bank 10 is port `$1F`, Kempston 1 or Mega Drive 1 (`J1_*`): RIGHT,
    LEFT, DOWN, UP, FIRE (Mega Drive B), C, A, START (bits 0–7).
  * Bank 11 is port `$37`, Kempston 2 or Mega Drive 2 (`J2_*`), the same.
  * Bank 12 is NextReg `$B2`, the 6-button Mega Drive pads' extra buttons:
    MODE, Y, Z, X of the left connector (`J1_*`, bits 0–3), then of the
    right (`J2_*`, bits 4–7).
  * Banks 8–12 read 1 = pressed.
* **Which joysticks:** the Next's own joystick settings choose each
  joystick's mode (NextReg `$05`, set in the Next's set-up, not by the
  game).
  * Kempston 1 and Mega Drive 1 are read through port `$1F`; Kempston 2 and
    Mega Drive 2 through `$37`. A Mega Drive mode also reads `$B2`.
  * `kbd_scan` reads a joystick bank only while some joystick is in a mode
    that uses it; otherwise the bank is 0. A port that reads left and
    right at once (no stick can) is taken as nothing there and also reads
    0. So an unused port can't read as every button pressed.
  * Sinclair 1 and 2 and Cursor modes enter keys (6–0, 1–5, 5–8), so those
    joysticks are read as keys and are defined in the KEY column.
* **Joystick defaults** (`JOY_DEFAULTS`), on joystick 1:
  * the stick turns (left, right) and climbs and descends (up, down);
  * FIRE (Mega Drive B) fires;
  * Mega Drive C is speed up, A speed down, and START pauses;
  * a 6-button pad's X is the air brake, Y nose up, Z nose down and MODE
    the boost;
  * the gun tilt and weapon slots have no joystick input by default.
* **Scan:** `kbd_scan`, at the top of the main loop, reads all 13 banks
  into `key_now`, keeping the previous scan in `key_prev`. It inverts the
  ZX rows, so every bank holds 1 = pressed.
* **Tests:** `key_held` (A = action) is NZ while its key or joystick input
  is down. `key_pressed` is NZ only on the frame either goes down.
* **Redefining:** `key_define` (A = action, HL = input code) changes an
  action's key, or its joystick input if the code is a joystick's (bank 10
  on). `key_find` returns the code of any input being held.
* **Defaults:** `key_defaults` and `joy_defaults` hold the defaults. The
  `KEY_DEFAULTS` and `JOY_DEFAULTS` macros build both sets. The four tables
  sit one after another, `key_defs`, `joy_defs`, `key_defaults`,
  `joy_defaults`, so putting the defaults back is one copy.
* **Redefine keys screen (`keydef_screen`, keydef.asm, `PAGE_KEYDEF` page
  33 in slot 6):** option 9 on the main menu (`keydef_go`, resident, pages
  it in). It lists every control (23, STRAFE RIGHT the last) with its key
  and joystick input ("-" for none): white, the highlighted one green. The
  title shares the top row with the KEY and JOYSTICK headings, and the
  keys' help is one line at the bottom (row 23; messages on row 22).
  21 rows of controls show at once (`KD_VIS`); the list scrolls to keep
  the highlight in view (`kd_top`, the first one shown).
  * **Q / A** move the highlight up and down, scrolling the list at its
    top and bottom.
  * **SPACE** shows PRESS A KEY OR JOYSTICK and waits a second. The next
    input (any bank: `kd_new_key`) then becomes the control's key, or its
    joystick input if it came from a joystick. If another control already
    uses it, KEY ALREADY IN USE shows (red, for a second) and nothing
    changes. A control's own input can be pressed again.
  * **0** puts every key and joystick input back to its default.
  * **1** goes back to the main menu (`menu_go`, resident), saving the
    definitions first if anything changed (`kd_save`). If they can't be
    saved, KEYS NOT SAVED (SD CARD?) shows for a second.
  * These keys are fixed, whatever the controls are set to.
  * **Saved definitions:** `ZPDATA/KEYS.ZPK`, beside the level files:
    "ZPKY", a version byte (`KF_VERSION`, 3), the number of controls (23),
    then `key_defs` and `joy_defs` (2 bytes a control): 98 bytes. An
    older file (version 1, 20 controls, from before the vision control,
    or 2, 21, before the strafe controls) isn't used: the defaults load
    instead, once. The
    definitions are in the input page, in slot 7, where the file handler
    goes too, so they go through a buffer in the redefine page (`kd_buf`).
  * **Loaded at start-up:** `start` pages the redefine page into slot 6 and
    calls `kd_load` after `fh_init`. It uses the file only if it is all
    there and fits this game: its size, magic, version and number of
    controls, and every input either none or in a known bank. Otherwise the
    defaults stay, as with no file.
* **Pause (`K_PAUSE`):** BREAK, or a Mega Drive pad's START, by default.
  * `main_loop` checks it after each scan. `game_pause` (resident) puts
    PAUSED, white in an opaque black ULA box, over the view, and waits,
    reading the input each video frame, until the pause control is pressed
    again. Then it puts the viewport's transparent cells back.
  * Nothing moves while paused, and the screen keeps its last frame.
  * **S** while paused saves and quits to the main menu (see "Save games").
    S is fixed there, whatever the controls are.
* **Doubling:** the Next normally also enters the extended keys into the
  ordinary rows (cursor LEFT shows up as CAPS SHIFT + 5, BREAK as CAPS
  SHIFT + SPACE).
  * `kbd_double_on` stops this: it sets `KBD_STOP_DOUBLING` to `TRUE` and
    NextReg `$68` bit 4 to 1. Start-up calls it. Otherwise BREAK, the pause
    key, would also fire (SPACE), and the redefine screen would take it as
    CAPS SHIFT.
  * `kbd_double_off` (alias `kdb_double_off`) sets it back to `FALSE` and
    bit 4 to 0.
  * Both keep `$68`'s other bits.

The craft moves horizontally along its heading. Pitch only aims the view, as
for a hovering VTOL, and height is set with W/S. A gunsight marks the
centre of the view. At the left of the panel below are vertical gauges,
filled from the bottom:
* **S:** speed, turning red when reversing and amber while boosting.
* **A:** split in two. The left half is the altitude (green). The right
  half is the height of the city tile under the craft (amber), on the same
  scale, and is empty over a road. The gap between the two tops is your
  clearance.
* **B:** the booster's fuel (green), 200 filling it. It appears once the
  booster module is fitted (`ula_init` makes its cells see-through and
  labels it); until then the panel covers it.

**Lateral thrusters:** a salvage reward at 90 points, fitted at once
(`lthrust_fitted`; `strafe` in player.asm).
* **K / L** (`K_STRAFE_L`, `K_STRAFE_R`, redefinable), held, move the
  VTOL sideways, square to the heading: 2.5 world units a frame
  (`STRAFE_D_HALVES`, 5 halves), about 0.2 m (10 m/s).
* The move is checked for collisions as any other.
* Not while landed (`vtol_on_floor`): nothing happens.

**Booster module:** a salvage reward at 45 points, fitted at once with a
full tank (`boost_fitted`, `boost_fuel`; constants `BOOST_*` in
zpolice.asm). It can't be turned on while landed.
* **X** (the boost control, `K_BOOST`, redefinable) turns it on if the VTOL
  is going forwards at half speed or more (`BOOST_MIN`, 14) and there's
  fuel. The speed jumps at once to twice the top speed (`BOOST_SPEED`, 56
  units a frame, about 4.4 m).
* While boosting, Q, A and Z don't change the speed, and each frame burns 1
  fuel.
* **X** again turns it off, and the speed goes back to what it was before
  (`boost_spd`). Running out of fuel does the same. Without fuel, X does
  nothing.
* A collision that stops the VTOL ends the boost (the speed is no longer
  `BOOST_SPEED`), and a wreck has none.
* **Refuelling:** landed on the base pad, 1 fuel a frame up to 200
  (`pad_service`, with the repairs and reloads).
* The engines' sound tops out at `SPEED_MAX` (the boost sounds flat out),
  and a crash at boost speed does 56 ÷ 4 = 14 damage.
* `DEBUG_LOADOUT` also fits the booster with a full tank, for testing.

**Vision modes:** salvage rewards fitted at once (`vision_owned`): night
vision green at 25, night vision monochrome at 65, thermal at 85.
* **N** (the vision control, `K_VISION`, redefinable) steps to the next
  mode the VTOL has, then back to normal after the last (`vis_cycle`,
  level_load.asm). With none fitted it does nothing. The mode in use is
  `vision_mode` (`VM_*`); every level starts in normal vision, and it
  isn't saved.
* **Palettes:** each level has 4, in `ZPDATA/LEVELnn.ZPV` (made by
  gentables.py: `tools/visionpal.py` has the format and the rules), loaded
  with the level into `ll_vbuf` (`vis_load`). A mode's palette goes into
  the Layer 2 palette when it is chosen; each level starts with its normal
  palette.
  * Night vision green: every colour's brightness as a green (1 to 7), the
    roads (0, 1, 0). Monochrome: white to grey. Thermal: the buildings in
    cold blues, their roofs warmer (towards magenta and red), the roads
    (0, 0, 1).
  * Only the 3D view changes: the HUD's and city map's colours, the
    gunsight, the missile reticule, tracers, the laser and the particles
    keep their normal colours (`visionpal.KEEP`).
  * Hand-tuned: a level's own `levels/LEVELnn_NVG.json`, `_NVM.json`,
    `_THM.json` (the format of `levels/LEVELnn_PAL.json`), if it has one,
    is used in place of the generated one. Make them in the map editor
    (level mode): its four palettes side by side, each with Copy normal,
    Convert to green / grey / thermal and Generated. gentables also writes
    the generated ones to `levels/generated/`, for reference.
* **Figures:** in a vision mode they are drawn from their vision set
  (`spr_lod`: the directory's entries `GFX_ANIMS` on), made by
  gengraphics.py from the normal figures (`spritefile.vision_pixels`): each
  pixel is its figure's face (the top quarter), core, or outline (an edge
  next to the core), each one palette entry the vision palettes colour.

  | Figure | Night vision green | Monochrome | Thermal |
  |--------|--------------------|------------|---------|
  | human | bright green | white | white face, yellow core, orange outline |
  | zombie, ghoul | mid green | mid grey | orange face, red body |
  | ghost, banshee | black | black | red body, white outline |

  A ghost fading out keeps its normal fade colours (shared with the map).

**The VTOL:** the player's craft is 10 m long and 3 m wide (`VTOL_LEN_M`,
`VTOL_WID_M`). Its position (`cam_x`, `cam_z`, the camera) is its centre.
* **Hit box:** the 10 × 3 m rectangle, turned to the heading
  (`vtol_ground`). Six points are tested: the four corners and the middles
  of the long sides (half length `VTOL_HL` 64 units, half width `VTOL_HW`
  19). The rectangle is smaller than a tile, so these find every cell it
  overlaps, except for a tile corner just nicking a long side.
* **Collision:** if any of those points is over a roof less than `COLL_H`
  (12 units, 0.94 m) below the camera, the VTOL stops, the border flashes
  red, and the position and heading go back to the last frame's. The
  heading is restored too, because turning swings the nose and tail.
* **Crash damage:** the VTOL takes |speed| ÷ 4 (a 2-bit shift right,
  rounded down) as damage (`vtol_damage`), from its speed when it hit. So
  full speed (28) costs 7 of its 50 hit points, half speed 3, and full
  reverse (−6) 1. Below 4 units a frame it's 0, as when a turn or climb
  bumps a wall. At 0 hit points it's destroyed (see "The VTOL destroyed").

Turning (O/P) moves 1.5 angle units per frame (`YAW_RATE`, 8.8 fixed point,
256 units = 360°). On the frame the key is first pressed it turns only
1° (`YAW_FINE`, 0.711 units), so a tap gives a fine correction; held, the turn carries on at the full rate.

**Air brake (Z, `K_AIRBRAKE`):** while held, the speed falls by
`AIRBRAKE_STEP` every frame, twice the Q / A step (`SPEED_STEP`): 2 units
a frame (2.2 m/s) until it
reaches 0, going forwards or backwards. Each braking frame also tips the
nose one pitch step, as a nose-key press does: up when braking forward
motion, down when braking reverse. From full speed (28) that's 14 frames,
about 1 s at 14 fps, with the nose up 14 steps. The pitch damper waits while
the brake acts, then brings the nose back to level.

**Pitch damper:** with neither E nor D held, the nose eases back to level.
Pitch is a signed 8.8 value (`pitch_frac`/`pitch`). The renderer uses only
the whole part, so the level fast path still applies once it reaches 0.
* Every `PDAMP_FRAMES` (1) frame, the pitch moves towards 0 by
  `max(PDAMP_MIN, |pitch|·PDAMP_K)`. With `PDAMP_K` 0 that is a steady
  `PDAMP_MIN`, 128/256: half a pitch unit a frame, half the rate of the
  nose keys (1 unit a frame), however far the nose is from level.
* It never overshoots, and it stops exactly at 0. From full pitch (±24) it
  takes 48 frames to level, twice as long as pitching up took.
* (Before: `PDAMP_K` 43, about 1/6 of what is left a frame, so from full
  pitch it came back at up to 4 units a frame, slowing as it neared level.
  Setting `PDAMP_K` above 0 again brings that back.)
* The step is calculated with the Z80N `MUL` rather than read from a table.
  It's just as fast, and the curve stays adjustable through the equates.
* While E or D is held, pitch moves in whole steps as before, and the
  damper waits a full interval after the key is let go.

### The base
The player's base is a 7×7 central plaza (`PLAZA` in `gentables.py`),
laid over the normal city layout as near the city's centre as the grid
allows.
* **Position:** the centre is the corner between cells 31 and 32, so the
  plaza covers cells 29–35 on both axes. It sits on the crossing of the two
  middle boulevards, which open onto it from all four sides.
* **Layout:** it's all open road (level 0) except the centre cell, (32,
  32). That cell is the landing pad: map code `PAD_CODE` (16), 0.5 height
  units (`PAD_H`, 64 units, 5 m) high, in colour family 63, which is reserved and
  white.
* **Terrace:** around the pad, every cell 1 or 2 tiles from it
  (`TERRACE_R`, the 5×5 square less the pad) is a green terrace: map code
  `TERRACE_CODE` (17), 0.25 height units (32 units) high, in colour family 62,
  which is reserved and green. Ordinary buildings use families 1–15 (0 is the
  perimeter wall's); 16–61 are kept free for the HUD and monsters later. The
  plaza's outer ring, 3 tiles out, stays road, so the streets still join up
  round the base. The terrace can be landed on like any low roof.
* **No humans on the base:** humans never spawn on the pad or the terrace
  (any map code 16 or above).
* **Pad height:** `htab` has the pad's and the terrace's heights as
  entries 16 and 17, so `bld_height` (masking 5 bits) handles them like
  any building. The pad
  shows white on the map.
* **Start:** you start landed on the pad (`PAD_X`, `PAD_Z`), facing north
  up the middle boulevard (`BASE_YAW` = 0).
* **Disembarking:** when landed on the pad (speed 0, resting on it), the
  passengers get off one every `DISEMBARK` frames (1 s at 14 fps). Each one
  counts as `saved`. The first gets off a second after landing.

### Landing and rescuing humans (`human.asm`)
Inspired by *Defender*: humans wait around the city to be picked up.
* **Humans:** there is room for `HUMAN_MAX` (20), and `nhumans`
  (`HUMANS_INIT`, 5) are placed at random at start-up, never on the
  perimeter wall.
  * They stand on a road, or on a roof no taller than `HUMAN_ROOF_MAX` =
    `MAX_Y` − 1.0 height unit. With the ceiling at 1.5 height units
    (15 m), that's 0.5 (5 m), so only level-1 roofs (4.7 m).
  * They move only to run to a landed VTOL (below) or from a monster.
  * **Waving:** a waiting human stands facing you (`ANIM_HUMAN_STAND`)
    while the VTOL is far off, and waves (`ANIM_HUMAN_WAVE`, a new frame
    every 4 frames) while it is within `WAVE_R` (4 tiles, 80 m) along both
    x and z, whatever its height.
  * **Fleeing** (`hum_flee`, after the rescues each frame): a human on the
    road with a monster (any type) within `FLEE_R` (1 tile, 20 m, along x
    and z) runs from the nearest one.
    * Its way is picked at random from the two that take it away from the
      monster: along x, or along z.
    * It runs at `HUMAN_FLEE` (10 m/s) for `FLEE_TIME` frames (a second),
      then looks again.
    * It runs only along roads. If the way it picked is blocked (a
      building, the base, the perimeter wall) it takes the other, and if
      both are blocked it stands. If its way becomes blocked as it runs, it
      stops and looks again.
    * A human on a roof never flees.
    * A standing human looks every `FLEE_EVERY` (4) frames, the humans
      taking turns (`hum_near`), to keep the cost down.
    * Running to a landed VTOL comes first: a human doing that doesn't
      flee.
  * **Drawing:** record +13 says how it's drawn each frame: standing,
    waving, or running (`ANIM_HUMAN_RUN_*`, a new frame every 2) seen from
    the front, the side or behind by the way it runs. It is set by
    `hum_rescue` and `hum_flee`. See "Figures and the sprite editor".
* **Map:** each human is a blue dot (`HUMAN_BLIP`), flashing 3 frames on
  and 3 off, written into the Layer 2 map like the zombie blips.
* **Landing:** descending stops at the floor under the VTOL (`floor_y`):
  `MIN_Y` (0.6 m) when its whole footprint is over road, or just clear,
  `COLL_H` + 1 (about 1 m), of the highest roof under any part of it. Setting down there isn't a collision, so
  there's no border flash. You're *landed* when speed is 0 and you're
  resting at that height.
  * **Setting down moving** (`update_player`): while resting at that
    height (`vtol_on_floor`) the VTOL can't keep moving. Any speed is
    braked away as the air brake does, as if Z were held (`AIRBRAKE_STEP` a
    frame towards 0, the nose tipping), with a screen shake. A boost on as
    it sets down ends.
  * The speed keys only bring it back to 0 there: Q only while reversing,
    A only while going forwards. So it can't speed up or reverse along the
    ground, a roof or the pad; climb off first. (Skimming the road at the
    lowest height, `MIN_Y`, counts as resting on it.)
* **Rescue:** every frame (`human_update`), while landed and carrying fewer
  than `PASSENGER_MAX` (5), each human checks two things. It must be at
  the same height as the floor under the craft: the road with the road, a
  roof with a roof of the same height. And it must be within `RESCUE_R`
  (2.0 tiles, 20 m, by a max + 3/8 min distance estimate).
  * A human that passes both runs straight to the craft at 10 m/s
    (`HUMAN_RUN`, 18 units a frame at 14 fps; about 17 after rounding).
  * When it gets there it climbs in: `passengers` goes up by one, and its
    dot and figure go.
  * A human on a roof can't reach a craft on the road, or on a roof of a
    different height. When the craft is full, nobody runs.

**Drawing:** zombies and humans share one figure drawer (`fig_draw` in
`zombie.asm`). It takes the feet's height (`fig_y`), a frame chooser
(`fig_sel`) and a patched colour.
* A cell holds humans when bit 6 (`CELL_HUMAN`) of its `city_map` byte is
  set. `hum_flags` keeps these marks: it is called whenever humans are
  placed, run, board or die. Each human record remembers the cell it marked
  (+11, +12), so the old mark can be taken off. `HREC` is 13.
* In a street cell, humans are drawn after its zombies. On a building,
  they're drawn after the building, so the roof doesn't cover them.
* With `OCCLUSION_CULL`, the cell goes on the draw list as its `city_col`
  address (`$6000–$6FFF`), listed before the building so it's drawn after
  it.
* The humans' code and records sit in the zombie page (slot 1), which is
  always mapped; their graphics are the figures' (pages 35 on).

**Not yet:** shots don't hit humans.

### Weapon slots
The helicopter has 5 weapon slots, held in `wpn_slots` in the resident
player state as 2 bytes each: a type byte, then an ammo counter byte.
* Slot 0 is the centre gun. It starts as `WPN_GUN` with infinite ammo.
* Slots 1–4 are the wing pylon hard points, which have limited ammo.
  They start empty (`WPN_NONE`, 0): a new game has only the machine gun.
  Other weapons are unlocked by salvage and fitted on the load-out screen
  between levels.
* An ammo counter of 255 (`AMMO_INF`) means infinite ammo and is never
  counted down. 0 means empty.
* The types are `WPN_NONE` 0, `WPN_GUN` 1 (machine gun), `WPN_LASER` 2
  (pulse laser), `WPN_CHAIN` 3 (chain gun), `WPN_ROCKETS` 4 (rocket
  pod), `WPN_MISSILE` 5 (missile pod), `WPN_AUTOCANNON` 7 (autocannon) and
  `WPN_PROX` 8 (proximity cannon), `WPN_LCHAIN_L` 9 and `WPN_LCHAIN_R` 10
  (the linked chain guns; `WPN_LAST`), and `WPN_BOMB` 6 (bomb). They are
  defined at the top of `zpolice.asm`.
* Slot indexes and keys: 0 is key 1 (the centre), 1 key 2 (left outer
  pylon), 2 key 3 (right outer), 3 key 4 (left inner, `WPN_LINK_L`) and 4
  key 5 (right inner, `WPN_LINK_R`), as the HUD shows them left to right:
  2 4 1 5 3.
* **Weapon type details (`wpn_cfg`, resident in zpolice.asm):**
  `WCFG_SIZE` (3) bytes per type: its full load (`WCFG_LOAD`), frames to
  reload a shot on the pad (`WCFG_RELOAD`, 0 for none) and the slots it
  may be fitted in (`WCFG_SLOTS`: bit n = slot n, bit 0 the centre slot).
  `wpn_cfg_ptr` (A = type → HL = its entry) and `wpn_fits` (A = type,
  C = slot → carry if allowed) read it from any page, ready for a load-out
  page.

  | Weapon | Slots (keys) | Full load | Reload |
  |--------|--------------|-----------|--------|
  | Machine gun | 1 | infinite | – |
  | Pulse laser | 1 | infinite | – |
  | Chain gun | 1 | infinite | – |
  | Rocket pod | 2–5 | 12 | 1 every 15 frames |
  | Missile pod | 2–5 | 4 | 1 every 30 frames |
  | Autocannon | 2–5 | 50 | 1 every 7 frames |
  | Proximity cannon | 2–5 | 50 | 1 every 7 frames |
  | Bomb | 2–5 | 1 | 1 every 30 frames |
  | Linked chain gun L | 4 | 200 | 1 every frame |
  | Linked chain gun R | 5 | 200 | 1 every frame |

  The masks are `WS_CENTRE`, `WS_PYLONS`, `WS_ANY`, `WS_LINK_L` and
  `WS_LINK_R`. An empty slot fits
  anywhere; the placeholder bomb fits nowhere yet. Nothing enforces the
  rules yet: the load-out page will use `wpn_fits`.
* Keys 1–5 select which slot SPACE fires (`wpn_sel`): 1 is the centre
  slot, 2–5 the pylons. The guns, the laser and the ammo count use the
  selected slot. An empty slot (`WPN_NONE`) can't be selected; the HUD
  flashes it instead. Changing slot stops any laser beam or cool-down.
* **Landed, no firing:** while the VTOL is landed (`vtol_landed`: speed 0
  and resting on the floor under it, whether road, landing pad or roof)
  no weapon fires and any laser beam stops. Slots can still be selected,
  and rounds already in flight carry on. Once it lifts off or moves, the
  weapons work again. Humans use the same test to board or get off.
* **Repair and reload on the base pad (`pad_service`):** landed on the
  landing pad (the cell under it `PAD_CODE`), the VTOL gains 1 hit point
  every `REPAIR_FRAMES` (5) frames up to `VTOL_HP` (50). Each slot's weapon
  gains a shot every its reload frames, up to its full load. The table is
  `wpn_cfg` (weapons.asm: full load and frames a shot per weapon type):
  rockets 1 every 15 frames (`ROCKET_RELOAD`) up to 12, missiles 1 every
  30 (`MISSILE_RELOAD`) up to 4, autocannon and proximity shells 1 every 7
  (`AUTOCANNON_RELOAD`, `PROX_RELOAD`) up to 50. The centre guns have infinite ammo and
  don't reload. The counts start afresh each landing, so the first hit
  point or shot takes the whole interval. Landing on a road or roof
  doesn't repair or reload.
* **Centre gun tilt (`gun_aim`, weapons.asm):** R and F tilt slot 1's
  weapon up and down by `GUN_TILT_STEP` (1 angle unit, 1.4°) a frame, as
  far as `GUN_TILT_UP` (11 units, 15.5°: the nearest step to 15°) up and
  `GUN_TILT_DN` (32 units, 45°) down. V brings it back to level at twice
  the rate (`GUN_CTR_STEP`). The tilt is the signed byte `gun_tilt`
  (resident; level again at each level's start, `weapons_reset`).
  * Rounds and the laser fired from slot 1 leave at the view's pitch plus
    the tilt (`spawn_round` takes sin and cos of it from `get_sin`). The
    wing pylons always fire straight ahead.
  * The gunsight moves to show it: `sight_y` = the view's centre row −
    128 × tan(tilt) (`tilt_rows`, the projection's scale), kept 6 rows
    inside the view. Past about 24° down that's the bottom of the view,
    so the sight stays there.
* Limited ammo counts down one per round (`take_ammo`). (Key 0 no longer
  cycles the centre slot's weapon.)

### Machine gun (`weapons.asm`)
The gun is the centre slot's `WPN_GUN`, with infinite ammo (`AMMO_INF`).
`weapons.asm` is its own code page (`PAGE_WEAPONS`, page 4, at `$C000`),
run each frame after the zombies move.
* **Firing:** hold SPACE to fire one round every `GUN_INTERVAL` (4) frames.
  Up to `NBULLETS` (20) rounds, shared with the chain gun, can be in
  flight.
* **Path:** rounds leave the ship's centre line 0.5 m below the camera
  (`GUN_DY`). They fly straight along the view direction, including pitch,
  at 500 m/s.
* **Speed per frame:** like every other speed, this is applied per frame,
  at the nominal 14 fps (`NOMINAL_FPS`): `BULLET_STEP` = 457 units, 36 m
  per frame.

**Collision:** each frame a round's path from its old position to its new
one is walked cell by cell through the grid, in order. The walk is a 2D DDA
on the horizontal distance along the path. The first thing met ends it:
* **Building cell:** a wall hit where the path enters the cell below the
  roof, or a roof hit where it drops below the roof. These use the real
  heights, so the perimeter wall is 70 m even with `SKY_IS_WALL`.
* **Street cell:** if its `CELL_ZOMBIE` bit is set, the zombies standing in
  it, found by searching the zombie records. Each is a box 0.5 m wide and
  2 m tall (`ZHIT_R`, `ZHIT_H`), tested by distance
  along and across the path. The nearest along the path is hit.
* **Ground:** where the path reaches height 0.
* **Map edge:** a round that leaves the 64 × 64 map is simply removed.

A round that hits is moved to the impact point, drawn there once, then
freed. A zombie that is hit loses the round's damage (see *Damage*
below); when its hit points run out it is killed: its map blip is removed
and its record made inactive.

**Tracers:** `draw_bullets` in the city page draws, for each round, a line
along the path it covered this frame: from where it started (`B_PX..`) to
where it is now. It uses `BULLET_COL`, over the city and before the
gunsight.
* **First frame:** a fresh round's path starts at the muzzle, 0.5 m below
  the camera, which is below and behind the view. The line's start is
  moved along it to where it enters the view (`bul_clip`) and pinned to
  the screen edge it crosses, as the face clipper does. Each shot therefore
  rises from the bottom row (127), as if fired from under the craft. The
  chain gun's half-stepped round keeps its muzzle start too.
* **Later frames:** the path is far ahead and seen almost end-on, so it
  shows as a dot near the centre.
* **Skipped lines:** a line whose end is outside the view isn't drawn.
* **Speed:** shots fly along the view direction, so any speed gives the
  same picture: a line from the bottom edge towards the centre on the
  first frame. The 500 m/s is kept.

### Zombie bursts
A zombie that is killed, by gun, laser, rocket or missile, sprays
`NPART_BURST` (10) particles from its body, 1 m up (`PART_Y`).
* **Motion:** each particle gets a random velocity: sideways −8…7 units a
  frame in x and z, and 3…10 up. Each frame it moves by that velocity,
  gravity (`PART_GRAV`, 2) takes off upward speed, and it stops on the
  ground. So the spray rises to about 2 m, spreads about 3.5 m, and falls
  back.
* **Colour:** it starts bright green and gets darker every frame:
  `PART_COL0`…`PART_COL7`, palette entries 59–87, from (1,7,1) to (0,1,0).
  After `PART_LIFE` (8) frames it is removed.
* **Pool:** particles are kept in a resident pool of `NPART` (60), room for
  a missile burst and 4 zombie bursts at once; a burst uses whatever is
  free. Each particle holds its own colour at age 1 (+10) and its life in
  frames (+11), so zombie and rocket bursts share the pool, `part_spray`,
  `part_update` and `draw_particles`. `part_update` (in
  `update_weapons`, before firing) ages and moves them. `draw_particles` (in
  the city page, after the tracers) draws each as one pixel over the city.
  `newGame` clears them.

### Chain gun
Weapon type 3 (`WPN_CHAIN`), in the centre slot. It's the machine gun at 4×
the rate of fire, with a random spread.
* **Rate:** one round every `CHAIN_INTERVAL` (1) frame while SPACE is
  held, against the machine gun's one every 4.
* **Spread:** each round's heading and climb are each turned by a random
  −`CHAIN_DEV`…+`CHAIN_DEV` (9) steps of 1/256 rad, about ±2°.
  * The heading is rotated by `(sin, cos) += d/256 · (cos, −sin)`, rounded
    (`dmul`). The climb adds `d` to the slope (tan).
  * Measured over 200 rounds heading along an axis: −2.01°…+2.01° each way,
    all 19 steps used. At a 45° heading the stored direction is coarser:
    ±1.9° sideways, in 13 distinct values.
* Everything else (500 m/s, collisions, drawing) is shared with the
  machine gun.

**Performance:** the distance a round travels between cell boundaries
depends only on its direction. It is worked out once, with two divides, on
the round's first step and kept in the round (`B_TDX`, `B_TDZ`). Each
frame's first boundary is then a hardware `MUL`, not a divide.

| Firing (street, 30 frames) | fps |
|-----------------|-----|
| Nothing | 21.5 |
| Pulse laser | 21.4 |
| Machine gun | 21.0 |
| Chain gun | 19.9 |

Most of the chain gun's remaining cost is projecting up to 20 tracers a
frame.

### Linked chain guns
Weapon types 9 (`WPN_LCHAIN_L`, salvage 50) and 10 (`WPN_LCHAIN_R`,
salvage 55): a pair of chain guns either side of the centre gun. L fits
only slot 4 (`WPN_LINK_L`, just left of slot 1 on the HUD), R only slot 5
(`WPN_LINK_R`, just right of it). The load-out screen calls them LINKED
CG L and LINKED CG R.
* **Stats:** as the chain gun (a round every frame, `CHAIN_DMG`, the same
  ±2° spread), but each has its own `LINK_SHOTS` (200) rounds, taken from
  its own slot (`take_slot_ammo`). One run dry, the other fires on alone.
  They reload on the pad 1 round a frame (`LINK_RELOAD`), and every level
  end fills them.
* **Straight ahead:** each fires along the view direction (the centre
  gun's tilt doesn't apply), from `LINK_OFF` (26 units, 2 m) to its side
  of the centre line, square to the heading (`round_side`).
* **Linked:** selecting either slot (`.linked` in `gun_fire`) fires every
  linked gun fitted, both together when both are. With one fitted, only
  that one fires.
* **Gunsight:** while one is selected, the centre crosshair is replaced by
  a crosshair for each linked gun fitted, `LINK_SIGHT_DX` (8) pixels to
  its side of the view's centre. `gun_aim` sets `sight_mask`
  (`SM_CENTRE`, `SM_LINK_L`, `SM_LINK_R`) and `draw_gunsight` (city2.asm)
  draws one crosshair (`gs_cross`) per bit.
* Both share the 24 rounds in flight (`NBULLETS`) with every other gun, so
  two at once can find none free sooner.

### Pulse laser
Weapon type 2 (`WPN_LASER`), in the centre slot, with infinite ammo.
* **Firing:** hold SPACE. The beam is on for `LASER_ON` (3) frames, then
  cools for `LASER_COOL` (8) frames, and repeats while SPACE is held.
  That's 0.1 s and 0.25 s as specified at 30 fps; at 14 fps it is 0.21 s
  and 0.57 s.
* **Hitting:** each beam frame, the beam is traced from the muzzle along
  the current view direction with the machine gun's grid walk, so it
  follows the aim. The range is `LASER_RANGE` (120 m, the draw distance).
  It stops at the first building, ground or zombie, and does 1 damage
  to a zombie it reaches on each beam frame.
* **Drawing:** the beam is kept in `laser_rec` in the same form as a round
  (state 3), with its path running from the muzzle to where it stops. So
  `draw_bullets` draws it the same way, as a red line (`LASER_COL`) rising
  from the bottom row of the view to the end of the beam.

**Note:** in level flight from the start (landed on the pad, camera 6 m
up), the muzzle is 5.5 m up, so rounds pass over the zombies' 2 m boxes. Fly lower or pitch
the nose down to hit them. The same applies to the laser.

### Rocket pod
Weapon type 4 (`WPN_ROCKETS`), on a wing pylon. A pod holds 12 rockets
(`ROCKET_SHOTS`). Fitted in slot 2, key 2 selects it (the HUD letter R).
* **Firing:** hold SPACE for one rocket every `ROCKET_INTERVAL` (7) frames.
  Each uses one of the pod's ammo.
* **Flight:** rockets are rounds in the `bullets` pool, marked by `B_KIND`
  = `BK_ROCKET`. They fly straight along the view direction at 150 m/s
  (`ROCKET_STEP` = 137 units a frame at 14 fps), with the machine gun's
  grid walk and collisions.
* **Drawing (`draw_rocket`):** a white streak (`ROCKET_COL`) from the head
  1 m back along its path (`ROCKET_LEN`), then a yellow trail
  (`TRAIL_COL`) to 1.5 m behind the head (`ROCKET_TRAIL`). Both are real
  lengths, projected. Up close that's a short line of a pixel or two, and
  further off a single white pixel. The yellow is drawn first, so the white
  stays on top.
* **Blast (`rocket_blast`):** wherever a rocket stops (a building, the
  ground or a zombie), it bursts. Everything within `BLAST_R` (5 m, 64
  units) of the burst on each of the x, y and z axes takes `BLAST_DMG` (20):
  * zombies (height measured from their feet);
  * humans waiting to be rescued. They have `HUMAN_HP` (10), so a blast
    kills them, removing their figure and map dot;
  * the base tiles: the terrace and the landing pad. Each tile the box
    overlaps is hit if the burst is no more than 5 m above its top.
    Destroying the pad ends the game, as when zombies destroy it.

  It's a box test, not a sphere: anything more than 5 m away on any one
  axis is skipped, using plain integer compares. A direct hit does no extra
  damage; the blast does it all.
* **Burst (`fire_burst`):** `BLAST_PARTS` (10) orange particles from the
  burst point, lasting `FIRE_LIFE` (10) frames. They fly out faster than a
  zombie's (−8…7 units a frame in x and z, −2…5 in y) and fade from
  yellow-orange to dark red-brown: `FIRE_COL0`…`FIRE_COL9`, palette
  entries 131–167.

### Autocannon
Weapon type 7 (`WPN_AUTOCANNON`), on a wing pylon. It holds 50 shells
(`AUTOCANNON_SHOTS`); the HUD letter A.
* **Firing:** a slow machine gun: one shell every `AUTOCANNON_INTERVAL` (16)
  frames while SPACE is held, a quarter of the machine gun's rate. Each
  uses one shell.
* **Flight and drawing:** the machine gun's rounds (500 m/s, `BULLET_STEP`,
  drawn as yellow tracers), marked `B_KIND` = `BK_AUTOCANNON`.
* **Burst:** wherever a shell stops, `rocket_blast` does `AUTOCANNON_DMG` (4) to
  every zombie, human and base tile within `AUTOCANNON_R` (3 m, 38 units) on
  each axis, and sprays `AUTOCANNON_PARTS` (3) orange particles for 10 frames.
  A direct hit does no extra damage: the burst does it all.

### Proximity cannon
Weapon type 8 (`WPN_PROX`), on a wing pylon. It is the autocannon
(50 shells, one every 16 frames, tracers, 1 every 7 frames reloaded on the
pad), with `B_KIND` = `BK_PROX`; the HUD letter P.
* **Proximity fuse:** a shell bursts when it passes within `PROX_R` (2 m,
  25 units) of a zombie or special monster on each axis: sideways from its
  x and z, and up or down from its feet (`+21`). `bullet_step` sets `b_pr`
  for the shell, and `cell_zombies` then uses that box instead of the
  monster's hit box. It is the same box the burst measures, so the monster
  that sets the shell off is always in its burst. The burst is where the
  shell comes nearest the monster along its path.
* **Burst:** `PROX_DMG` (3) to everything within `PROX_R` (2 m) on each
  axis, and 3 orange particles. It also bursts on a building or the
  ground, as an autocannon shell.
* **Limit:** the fuse only checks monsters in the cells the shell's path
  crosses (the round walk), so one 2 m away across a cell edge, in a cell
  the path doesn't enter, doesn't set it off.

### Missile pod
Weapon type 5 (`WPN_MISSILE`), on a wing pylon. A pod holds 4 missiles
(`MISSILE_SHOTS`); the HUD letter S.
* **Firing and flight:** as the rockets (`MISSILE_INTERVAL` 7 frames,
  `B_KIND` = `BK_MISSILE`, drawn by `draw_rocket`) but at half the speed:
  75 m/s, `MISSILE_STEP` = 68 units a frame.
* **Blast:** `rocket_blast` with a bigger reach and damage: everything
  within `MISSILE_R` (1.0 tile, 256 units) on each of the x, y and z axes
  takes `MISSILE_DMG` (15): zombies, humans and base tiles, as for a rocket.
  `rocket_blast` takes the reach, damage and particle count from the
  burst's kind (`rb_r`, `rb_dmg`, `rb_parts`).
* **Burst:** `MISSILE_PARTS` (20) orange particles for 10 frames.

### Bomb
Weapon type 6 (`WPN_BOMB`), on a wing pylon. A pod holds 1 bomb
(`BOMB_SHOTS`), reloaded on the pad in 30 frames (`BOMB_RELOAD`); the HUD
letter B. A salvage reward at 40.
* **Dropping (`bomb_drop`):** SPACE releases one, straight ahead at the
  VTOL's speed + `BOMB_SPEED` (20) units a frame (at least 1: reversing,
  less). At most one every `BOMB_INTERVAL` (14) frames.
* **Glide:** it leaves at `BOMB_ANGLE` below level, 10° (7 of the angle's
  1.4° steps: 9.8°), keeps its speed, and every `BOMB_STEEPEN` (5) frames
  dives one step steeper (`bomb_steer`: the low byte of `B_PIT` counts the
  frames; its direction afresh, `rnd_dir`), to 79°, until it hits a
  building, a monster or the ground (`B_KIND` = `BK_BOMB`). From 15 m,
  hovering, it lands about 710 units ahead 39 frames later, at about 18°.
* **Drawing:** the rocket's white streak (`draw_rocket`) without its
  yellow trail, 2 pixels wide.
* **Heights:** a round's height (`b_y_at`) rounds each frame's drop to the
  nearest unit. Truncated, a slow round lost up to a unit a frame: the
  bomb's glide came out at half its angle.
* **Blast:** `rocket_blast`: `BOMB_DMG` (30) to everything within `BOMB_R`
  (2 tiles, 512 units) on each of the x, y and z axes: monsters, humans,
  the terrace, barricades and the landing pad, and the VTOL (`rb_vtol`).
  The missile's boom, and `BOMB_PARTS` (30) orange particles.
* **Danger:** hovering at 15 m, the bomb lands beyond the blast's reach.
  Flying on after it, the VTOL closes the gap, so it can be inside the
  blast and take 30. Low down (40 units up), the bomb lands about 180 units
  ahead, well within reach.

### Damage
Weapons do damage in hit points:

| Weapon | Damage |
|--------|--------|
| Machine gun (`GUN_DMG`) | 4 per round |
| Chain gun (`CHAIN_DMG`) | 2 per round |
| Pulse laser (`LASER_DMG`) | 1 per beam frame on a target |
| Rocket blast (`BLAST_DMG`) | 20 to everything in range |
| Missile blast (`MISSILE_DMG`) | 15 to everything within 1.0 tile |
| Bomb blast (`BOMB_DMG`) | 30 to everything within 2 tiles, the VTOL too |
| Autocannon shell burst (`AUTOCANNON_DMG`) | 4 to everything within 3 m |
| Proximity shell burst (`PROX_DMG`) | 3 to everything within 2 m |

* **Rounds:** each round carries its damage in `B_DMG`. `zdamage` takes
  it off the zombie and kills the zombie at 0.
* **Hit points:** zombies keep theirs at +18 of their record. On level 1
  a zombie has `ZHP` (5) and a fast zombie `ZHP_FAST` (4).
  * The machine gun kills a zombie in 2 rounds and a fast zombie in 1.
  * The chain gun takes 3 rounds, and the laser 5 beam frames.
  * Humans have `HUMAN_HP` (10). The terrace tiles have `TERRACE_HP`
    (100) and the pad `PAD_HP` (200), each taking 20 from a blast and 1
    from a zombie's blow (`base_damage`).

### Special monsters: the ghost, the banshee and the ghoul (`specials.asm`)
Special monsters use the zombie records after the zombies' own: records
`NZOMB`–`NMON`−1, up to `NSPEC` (8) of them. So they share the zombies'
drawing, cell marks, map blips, weapon hits and `zdamage`. The record's
type (+15) says which monster it is: `ZT_GHOUL` (2), `ZT_GHOST` (3) or
`ZT_BANSHEE` (4). Types below `ZT_GHOST` walk as zombies; from it up they fly.
* **How many, and when:** from the level file, wave by wave. Each wave's
  data (`LV_WAVE_DATA`, `LV_WAVE_REC` 10 bytes, for up to `LV_MAX_WAVES`
  10 waves) holds up to 5 special types (`LV_SPECIAL_ID`: `SPEC_GHOST` 0,
  `SPEC_BANSHEE` 1, `SPEC_GHOUL` 2; `SPEC_NONE` 255 for none) and how many
  of each (`LV_SPECIAL`). The level's start is wave 1, like any other:
  `spec_init` makes every special record inactive and calls `spec_wave`,
  which `spec_update` also calls when a new wave starts (`zwave_new`). It
  places each type's count into free special records (`spec_place`; at
  most `NSPEC`, 8, at once), mapping the type to the record's (`spec_types`:
  `ZT_GHOST`, `ZT_BANSHEE`, `ZT_GHOUL`). All of them count as part of the
  wave: it isn't wiped out until they are dead too.
* **The generated levels** (gentables.py) keep the old built-in rules: in
  wave 1, ghosts from level 5 (1, rising to 5 by level 13); a banshee on
  every even wave (2 from level 11, 3 from 31); ghouls on every odd wave
  from level 21 (2 from 30, 3 from 40). Edit a level's file to change
  them.
* **Each frame:** `spec_update` moves them, after `zombie_update`, from
  its own game logic page (`PAGE_SPECIAL`). `g_params` sets the monster's
  speed, attack reach, damage and whether it goes for the base, so both
  flying types share the same code. Ghouls are skipped here: they walk in
  `zombie_update`.

**The ghost** (`ZT_GHOST`): a white sheet (`ANIM_GHOST_FLOAT`), floating
at its own height. Fading out, it is drawn all in one colour, by the frames
left.
* **Movement:** it flies at twice the zombies' speed, at any angle, up and
  down between the ground and the VTOL's ceiling (`MAX_Y`). It passes over
  buildings lower than its feet. It can't attack the base.
* **Roaming:** it flies a random direction, with a random climb, until it
  hits a building taller than it or the map edge (then a new random
  direction at once). Its decision check comes every `GHOST_DECIDE` (30)
  frames, staggered between ghosts: a human or the VTOL within
  `GHOST_SEE` (3 tiles) that it can see makes it chase.
* **Chasing:** it flies straight at the nearest, climbing or descending to
  its height, and aims again every `GHOST_TRACK` (5) frames. It goes back
  to roaming (a new random direction, the 30-frame cycle) if:
  * the target is gone;
  * it loses sight of it: the line between them is sampled at 7 points,
    each against the roof under it, so a taller building in between hides
    the target;
  * it runs into a building.
* **Attacking:** within 0.1 tile (`ATTACK_R`) of its target on every axis,
  it stops and takes 1 hit point every `GHOST_HIT_FRAMES` (10) frames.
  * A human has 10, so dies after 100 frames. The ghost then roams again.
  * The VTOL has `VTOL_HP` (50, `vtol_hp`); at 0 it is destroyed (see
    "The VTOL destroyed" below).
  * Its map blip is red while it attacks (`zatk_flags`, `zblip_red`), as
    an attacking zombie's. If the target moves out of reach, it chases
    again.
* **Map blip:** its own shades, white, light grey, grey, light grey
  (`gshades`), changed every 8 frames.
* **Damage:** it has `GHOST_HP` (10) hit points, and any weapon hurts it:
  3 machine-gun rounds, or one rocket blast within 5 m of its height.
* **Death:** killed, it doesn't burst like a zombie. It fades out where it
  is, white to near black in 4 steps of 3 frames (`GHOST_FADE_FRAMES`):
  white, light grey, grey, dark grey (`GHOST_FADE`).
  * While it fades (`GM_DYING`) it does nothing, and rounds and blasts
    pass through it.
  * `zdamage` starts the fade, `zombie_draw` colours it by the frames left
    (`gfade`), and `g_dying` frees the record at the end.
  * Hits allow for its height: the rounds test the box from its feet
    (+21, +22), and the rocket blast uses that height.
  * Ghosts over a building are drawn after it (`draw_cell`). Rounds
    crossing the cell can hit them above the roof, before the round would
    reach the building.

**The banshee** (`ZT_BANSHEE`): a thinner sheet with trailing arms, in
yellow (`ANIM_BANSHEE_FLOAT`). It behaves as a
ghost (roaming, sight, chasing, attacking, fading out), except:
* **Speed:** twice the ghost's (4× the zombies').
* **Reach:** it attacks within 0.5 tile (`BANSHEE_R`) on every axis, for
  `BANSHEE_DMG` (5) hit points every 10 frames: a human dies in 2 blows.
* **Targets:** humans, the VTOL, and the base. Each base tile still
  standing (`base_hp` > 0) is a target (`TG_BASE` + tile index, 0–24) at
  the centre of its top; a blow goes through `base_damage`, as a
  zombie's. The line-of-sight check ignores samples over the target's own
  cell, so a tile's top doesn't hide itself.
* **Hit points:** `BANSHEE_HP` (8).
* **Spawning:** with the waves the level file gives it (see "How many, and
  when" above): the generated levels have 1 banshee on each even wave up to
  level 10, 2 up to level 30, then 3. They go into free special records
  (there may be fewer if others fill them).
* **Map blip:** yellow shades (`bshades`). Its death fade runs yellow to
  dark (`bfade`, `BANSHEE_FADE`).

**The ghoul** (`ZT_GHOUL`): a half-height zombie. It is placed by
`specials.asm` but is otherwise a zombie in a special record:
* **Movement:** `zombie_update` walks it with `zmove`, like the zombies
  (streets, junctions, going for and hitting the base), at 5 times their
  speed (`zcalc_step`; a look-ahead of 5 times the walk, `zlook_ghoul`).
  `ZSPEED_INIT`×5 must fit the 4.4 step (an `ASSERT`).
* **Drawing:** the zombie sprite in the zombie colour, at `GHOUL_H` (half
  `ZOMBIE_H`, 1 m): `zsize` takes the height from `fig_h`, and its legs
  change frame every frame.
* **Hits:** its box is half as tall (`ZHIT_H`/2). It has `GHOUL_HP` (5, as
  a zombie), and killed it bursts like one. Its map blip is a zombie's.
* **Spawning:** with the waves the level file gives it: the generated
  levels have ghouls on each odd wave (wave 1 included), 1 on levels 21–29,
  2 on 30–39, 3 from 40, into free special records (`ghoul_init`, placing
  it with `zplace`, zombie.asm).

### The VTOL destroyed
At 0 hit points (`vtol_hp`: ghost attacks, building crashes; both through
`vtol_damage`) the VTOL is destroyed (`vtol_dead`):
* **Out of control:** the controls do nothing, its speed is 0, and the
  weapons don't fire (any laser beam stops). Humans don't run to the wreck
  or get off it.
* **Falling:** each frame it spins `DEAD_SPIN` (8 yaw units, a turn every
  32 frames) and falls, a unit a frame faster each frame up to
  `DEAD_FALL_MAX` (8 units, 11 m/s), until it hits the ground under it.
  That's the road, or the highest roof under its footprint (`floor_y`).
  From the 15 m ceiling it falls in about 2 seconds.
* **Game over:** once on the ground (`dead_down`) it lies there for
  `DEAD_PAUSE` (100) frames. Then the game is over: the GAME OVER screen
  for 10 seconds, then the main menu.
* **Where:** `vtol_wreck` in `player.asm`. `newGame` resets it all.

### Instrument panel (ULA / Layer 1)
The panel in rows 128–191 is drawn on the ULA, which is above Layer 2
(priority S-U-L). Layer 2 shows through only where the ULA cells are made
transparent: the city map and the gauges.

* **Fixed contents:** set up once by `ula_init`. That's a dark slate paper,
  a green divider on the top pixel row, and the gauge labels "S" and "A".
* **Gauges:** two vertical bars at the left, `GAUGE_H` (48) pixels tall
  (pixel rows 136–183, character rows 17–22), filled from the bottom and
  labelled on row 23.
  * **S** (speed) is 8 pixels wide in character column 1 (`SPD_GCOL`). It
    is (speed × 55) / 32 pixels, so `SPEED_MAX` 28 fills it. It's green,
    or red when reversing.
  * **A** shares character column 3 (`ALT_GCOL`). The left 4 pixels are the
    altitude (green), and the right 4 the height of the city tile under the
    craft (amber, `GAUGE_AMBER`), read via `cam_cell_ptr` and `bld_height`.
    Both are 1 pixel per 4 world units, so the 15 m ceiling (`MAX_Y` 192)
    fills the bar. With the vertical thrusters fitted (`vthrust_fitted`)
    both are 1 per 8, so their 30 m ceiling (`MAX_Y_THRUST` 384) fills it. The ground under the craft is always lower than the
    craft, so it never overflows.
  * **Why Layer 2:** the two halves of A need green, amber and black in one
    8×8 cell, which ULA attributes can't do. So the bars are drawn on Layer
    2 behind transparent ULA cells (attribute 0), like the city map.
    `draw_gauges` writes the 48 rows into the back buffer every frame.
* **Humans (hardware sprites):** a column of 16 × 16 sprites, one per
  human (sprite k for human k), 8 pixels in from the left edge of the
  320 × 256 sprite screen, over the border. Human 0 is at the bottom and
  each next one 16 pixels higher, the column placed so its middle sprite
  (human (`nhumans` − 1) / 2) is at y 128 (`HUD_SPR_MID`): with 5 humans,
  y 160 down to 96. The bottom one goes no lower than y 232, and any that
  would go off the top are hidden. Each shows its human's state (record +6, `HS_*`) with the human
  status patterns (`sprite_data.asm`):

| State | Sprite |
|-------|--------|
| `HS_WAIT`: waiting in the city | `HSPR_FIELD`: an empty square |
| `HS_ABOARD`: aboard the VTOL | `HSPR_ABOARD`: a person sitting in a chair |
| `HS_SAVED`: rescued, off at the landing pad | `HSPR_SAVED`: a green person standing |
| `HS_DEAD`: killed (a rocket blast, a ghost) | `HSPR_DEAD`: a white person with a red cross |

  * `hum_hud` (hud_sprites.asm) sets them once a frame, after the flip, with
    `PAGE_SPRITES` paged in. Unused humans' sprites are hidden.
  * The menu screens hide them all (`menu_clear`).
  * Disembarking at the pad marks the first human aboard as rescued.
* **Integrity (`draw_integrity`, hud.asm):** under the weapon slots,
  "INTEGRITY" on character row 21 (`INT_ROW`, from column 11) and the
  VTOL's hit points as a percentage below it, "nnn%" from column 12.
  * `VTOL_HP` is 50, so the percentage is `vtol_hp` × 2: one `add a,a`
    (an `ASSERT` checks `VTOL_HP` is still 50).
  * Green from 50% (`INT_WARN`), amber below it, red below 25%
    (`INT_DANGER`), as the cells' ink.
  * Redrawn only when it changes (`int_shown`); `ula_init` prints the
    label at each level's start. The HUD font gained I, E, Y and %.
* **Weapon slots (placeholders):** five 8×16-pixel boxes, each two ULA
  character cells on rows 17–18 (`WPN_ROW`), at columns 11, 13, 15, 17
  and 19 (from `WPN_COL0`). Left to right they show the slots keys 2, 4, 1,
  5 and 3 select (`wpn_order`: the centre gun in the middle).
  * A box's paper is green if its slot holds a weapon and red if it's
    empty (ULA papers 4 and 3, `C_OK`, `C_WARN`).
  * Under an occupied slot, on row 19, is its weapon's letter
    (`wpn_glyph`): M machine gun, L laser, C chain gun (the linked chain
    guns too), R rocket pod.
  * The selected slot's box has a white outline (ink 7 in the bitmap).
  * Asking for an empty slot (a new press of its key) doesn't select it.
    The current slot is kept, and the asked-for box flashes amber and red,
    `WFLASH` (5) frames each, 3 times, ending red (`C_AMBER`, paper 6).
  * `draw_wpn` redraws the five boxes and letters every frame.
  * The flash state (`wflash_slot`, `wflash_t`) is resident, since the
    weapons page sets it and the HUD page shows it.
* **Compass (hardware sprites, `hud_sprites.asm`):** a bar across the top
  of the screen, in the top border at sprite row 8, centred on the heading.
  * **Scale:** 2 pixels per yaw unit, across the full 320-pixel width of
    the sprite screen (over the side borders too): 225°, ±80 yaw units
    (`COMP_HALF`) either side. Marks at the very edges are half off it.
  * **Marks:** one every 16 yaw units (22.5°): the letters N, E, S, W in
    red, a yellow dot at the 45° points, a small white dot between. At most
    11 are in view, using sprites 20–30.
  * **Pointer:** a white pointer under the middle (sprite 31) marks the
    heading.
  * **Images:** the letters are the menu font's, doubled. They and the dots
    and pointer are patterns `CSPR_*` in sprite bank 0, after the human
    status ones (`gentables.py`).
  * **Drawing:** each frame `compass_spr` places each mark within ±80 yaw
    units at x = 160 + 2 × (mark − yaw). `hud_sprites` does this with the
    human column, after the flip. Turning right moves the marks left.
* **City map:** the right-hand 64×64 of the panel (columns 192–255) is a
  map of the whole 64×64-cell city, one pixel per cell, with north (+Z) at
  the top.
  * The map is drawn on Layer 2, so each building pixel is the base
    colour of its building's colour family. Streets are black (`MAP_BG`),
    and the perimeter wall shows as the border.
  * Zombie blips are bright green pixels (`MAP_ZOMBIE`) written into the
    Layer 2 map.
  * The ULA attributes over the map are transparent paper with white ink,
    so Layer 2 shows through. The ULA draws only the player's flashing
    white dot on top.
  * The Layer 2 clip window covers all 192 rows. Elsewhere in rows
    128–191 the panel's ULA paper is opaque and hides Layer 2.
  * `map_init` draws the map once into both Layer 2 buffers (`map_l2`).
    The viewport clear only touches rows 0–127, so it stays.
  * Each frame, `map_player` undoes the previous frame's XOR, then on
    alternate frames XORs the pixel under the player (its cell). The
    marker flashes and leaves the map intact.
* **Paging:** the ULA screen (bank 5) stays mapped at `$8000` (slots 4–5),
  so no paging is needed for the panel or the FPS text.
* **ULA palette:** the custom entries are paper 0 = `$E3` (transparent, so
  the viewport shows through above the panel), paper 1 = panel, paper 2 =
  empty gauge, paper/ink 3 = red, paper/ink 4 = green and paper/ink 6 =
  amber.
* **Border:** the border flash on a collision uses colour 3 (red).
* **Screen shake:** a collision with a building also shakes the view, and
  plays the crash sound (`SFX_CRASH`).
  * For the next `SHAKE_LEN` (6) rendered frames, about half a second,
    `shake_tick` (resident, called by `main_loop` after the flip) sets
    Layer 2's scroll registers (NextReg `$16` X, `$17` Y). It uses the
    next pair from `shake_xy`, dying away: (2, 1), (−2, −1), (1, 1),
    (−1, −1), (1, 0), then (0, 0) to put it back.
  * Only Layer 2 moves, so the HUD (the ULA) stays still. While the view is
    offset, a row or column at its edge shows the far side's.
  * Held against a wall, the VTOL bumps again and again. A new shake and
    crunch start only once the last shake is over. The damage and the
    border flash still come with every bump.
  * `next_level` and `game_reset` stop any shake (`shake_off`).

### Hardware sprites (`sprites.asm`, Layer 3)
Support for the Next's 128 hardware sprites. Nothing in the game uses them
yet.
* **Screen:** sprites are drawn above Layer 2 and the ULA (priority S U L).
  `sprites_init` also shows them over the border (NextReg `$15` bits 0 and
  1), so they can go anywhere on the 320 × 256 sprite screen.
  * x runs 0–319 and y 0–255. (`SPR_SCREEN_X`, `SPR_SCREEN_Y`) = (32, 32)
    is the top left of the 256 × 192 screen.
  * A position is the sprite's top-left pixel.
  * Coordinates are 9 bits and wrap at 512, so they can be negative: x = −8
    shows a sprite's right half at the left edge.
  * Where sprites overlap, the higher number is on top.
* **Patterns:** 16 × 16, one byte per pixel (8-bit), 256 bytes each, up
  to 64 in the sprite pattern memory. Byte `$E3` (`SPR_TRANS`, NextReg
  `$4B`) is transparent. The sprite palette starts as the identity, so a
  pattern byte is its own RRRGGGBB colour until `spr_palette` changes it.
* **Shadow table:** the routines change a table of the first `SPR_COUNT`
  (32) sprites' attributes (`spr_shadow`, 5 bytes each). `spr_update` sends
  it to the hardware, once a frame. The other sprites stay hidden.
* **Routines** (`PAGE_SPRITES` at `$E000`: page it in with `nextreg
  CODE_MMU,PAGE_SPRITES` first; game logic in slot 6 can then call them):

| Routine | In | Does |
|---------|----|------|
| `sprites_init` | – | sprites on, over the border; all 128 hidden; table cleared (called by `start`) |
| `spr_update` | – | send the table to sprites 0 … `SPR_COUNT` − 1 |
| `spr_patterns` | HL = data, A = first pattern, B = count | load 8-bit patterns |
| `spr_palette` | HL = colours, A = first index, B = count | load sprite palette colours (RRRGGGBB) |
| `spr_set` | A = sprite, BC = x, DE = y, H = pattern, L = flags | place it, set its pattern and flags, and show it |
| `spr_pos` | A, BC = x, DE = y | move it |
| `spr_pattern` | A, E = pattern | change its pattern |
| `spr_flags` | A, E = flags | `SPRF_XMIRROR`, `SPRF_YMIRROR`, `SPRF_ROT` (90° clockwise), palette offset × `SPRF_PAL` |
| `spr_scale` | A, E = x scale, D = y scale | 0–3 = ×1, ×2, ×4, ×8 |
| `spr_hide`, `spr_show` | A | hide or show it |
| `spr_hide_all` | – | hide every sprite in the table |

**Sprite banks (`sprite_data.asm`):** pattern data is only needed while it
is loaded into the sprite pattern memory, so it's kept in its own 8K pages
rather than in the sprite code's page.
* **Bank layout:** each bank is a page assembled at `$E000`, swapped
  into MMU slot 7 like a code page (`SPRBANK_SLOT`). In order, it holds:
  * its own loader, `spr_load_bank`, at `$E000`. The `SPRB_LOADER` macro
    puts the same loader in every bank, so it's the same address in each;
  * `SPRB_COUNT`, the number of patterns;
  * `SPRB_FIRST`, the pattern number the first one loads to;
  * the patterns (up to 31 of 256 bytes).
* **Loading:** page the bank into slot 7, then call its loader:

  ```
  nextreg CODE_MMU,PAGE_SPR0
  call spr_load_bank
  ```
  * The loader only reads its own page, so it needs no variables and no
    resident memory.
  * Call it from outside slot 7: resident code, or a game logic page in
    slot 6. Afterwards, page back whatever slot 7 needs.
* **Bank 0:** `PAGE_SPR0` (page 9, beside the menu's page 8) holds the
  human status sprites. `start` loads it, after `sprites_init`.
* **More sprites:** add a bank in the next free page, with its own
  `PAGE_SPRn`, its `MMU` / `ORG` lines in `zpolice.asm`, and a block in
  `sprite_data.asm` that starts with `SPRB_LOADER`.

**Human status sprites:** bank 0 holds four 16 × 16 patterns
(`tables_hspr.inc`, from `gentables.py`), loaded as patterns 0–3. They're based on
the HUD's passenger markers, for showing what has become of each human:

| Pattern | Name | Means | Picture |
|---------|------|-------|---------|
| 0 | `HSPR_FIELD` | in the field, not yet rescued | an empty white square (the HUD's empty seat, doubled) |
| 1 | `HSPR_ABOARD` | aboard the VTOL | a white person sitting in a grey chair, side on |
| 2 | `HSPR_SAVED` | rescued | a green person standing (the HUD's man, doubled) |
| 3 | `HSPR_DEAD` | dead | a white person with a red cross over them |

They use the identity sprite palette (white `$FF`, green `$1C`, red `$E0`,
grey `$92`). Show one with, for example, `spr_set` with H = `HSPR_SAVED`.

The emulator (`tools/nexsim.py`) draws the sprites too: the ports
`$303B`, `$57` and `$5B`, mirrors, rotation, scale and wrapping. With
sprites over the border its PNGs are the full 320 × 256.

### FPS counter
The frame rate is shown as `nn FPS` in the top left of the ULA screen,
which sits above Layer 2 (layer priority S-U-L, NextReg `$15`). ULA paper
palette entries 16 and 24 are set to the global transparency colour `$E3`,
so only the white text covers the 3D view. Time comes from the raster (it
was written when interrupts were off; the interrupt routine now leaves the
NextReg select alone, so this still works):
* `vtick` reads the video line (NextReg `$1E/$1F`) and counts a new 50 Hz
  frame each time the line number goes backwards. It runs between the
  main-loop stages and once per building, so it is sampled more often than
  once per display frame.
* Every 50 display frames (one second), the number of frames rendered is
  shown.

## Files

| File | Purpose |
|------|---------|
| `zpolice.asm` | resident main code at `$A000` (page 11, slot 5): the boot stub, start-up, main loop, per-frame setup, fixed-point maths, frame timing, shared variables and tables, stack. Includes the pages below. |
| `memory_bank_defs.asm` | memory bank definitions, included by `zpolice.asm`: the MMU slots (`MMU_SLOT_n`), their NextRegs (`MMU_SLOT_n_REGISTER`, `$50`–`$57`) and addresses (`membank0`–`membank7`); what each slot is used for (`<use>_SLOT`, `<use>_MMU`, `<use>_ADDR`, e.g. `LOGIC_MMU` / `LOGIC_ADDR` for the game logic pages at `$C000`, `CODE_MMU` / `CODE_ADDR` for the core function pages at `$E000`); and the 8K pages (`PAGE_*`, `L2_BANK_A` / `_B`) |
| `city.asm` | city page (`PAGE_CITY`, runs at `$E000`): the Layer 2 drawing (with `city2.asm`), its tables and variables |
| `city2.asm` | second city page (`PAGE_CITY2`, page 34, runs at `$8000` in slot 4, over the ULA screen, beside the city page while the city is drawn): the street dots, bullets, rockets, particles, gunsight and the occlusion culling. See "Code pages" |
| `hud.asm` | HUD page (`PAGE_HUD`, runs at `$E000`): all ULA (Layer 1) code, font and labels |
| `zombie.asm` | zombie page (`PAGE_ZOMBIE`, stays mapped at `$2000`): zombie records, seeding, walking, the zombie marks in `city_map` (`zflags`), and projecting the figures (`fig_draw`; `spr_lod` and `spr_draw` in `city2.asm` draw them) |
| `gengraphics.py` | builds the figures' graphics: `sprites/*.json` (the sprite editor's files) into `ZPDATA/SPRITES.ZPG`, and `gfx_ids.inc` (the `ANIM_*` purposes). Run by `build.bat` before `gentables.py` |
| `sprites/` | the figures' sources: `palette.json` (their 32 colours) and one file per figure (`zombie`, `ghoul`, `ghost`, `banshee`, `human`.json). Edit with `tools/sprite_editor.py` |
| `tools/spritefile.py` | the figure files' format, checks, scaling and packing (shared by the editor and `gengraphics.py`) |
| `tools/sprite_editor.py` | the figure editor (tkinter) |
| `menu.asm` | main menu page (`PAGE_MENU`, page 8, game logic at `$C000`): menu screen, per-frame random seed stirring, starts `newGame` |
| `input.asm` | input engine (`PAGE_INPUT`, page 12, core function at `$E000`): scans the 8 ZX half-rows, the 2 Next extended-key registers and the joysticks (ports `$1F`, `$37`, NextReg `$B2`) each frame; redefinable action keys and joystick inputs, the pause control |
| `sprites.asm` | hardware sprites, Layer 3 (`PAGE_SPRITES`, page 13, core function at `$E000`): set-up, pattern and palette loading, a shadow attribute table and its per-frame upload, positions on the 320 × 256 sprite screen |
| `levels.asm` | the current level's record, `level_cur` (resident): level number, 8-character city name, the numbers of zombies a wave, waves and fast zombies, the draw distance, and each wave's special monsters (up to 5 types and counts, 10 waves) (`LV_SIZE` 113 bytes); the special type ids (`SPEC_*`); `level_entry` → HL = it. Loaded from the level's file. The current wave is `wave_number` (resident, 1 at a new game) |
| `specials.asm` | special monsters (`PAGE_SPECIAL`, page 31, game logic at `$C000`): the ghost and banshee behaviour, `spec_init` (wave 1), `spec_wave` (each wave's specials from the level file) and `spec_update` |
| `keydef.asm` | redefine keys screen (`PAGE_KEYDEF`, page 33, game logic at `$C000`): list the controls with their keys and joystick inputs, change one, put the defaults back |
| `loadout.asm` | load-out screen (`PAGE_LOADOUT`, page 32, game logic at `$C000`): before the first level and between levels, fit unlocked weapons from the store into the 5 slots |
| `text.asm` | text screens (resident): `menu_clear`, `menu_print`, `menu_char`, `menu_frame` and the menu font, shared by the menu and load-out pages; `MENU_ATTR`, `MENU_TITLE`, `MENU_OK`, `MENU_BAD` |
| `level_load.asm` | level loading (`PAGE_LEVEL`, page 30, game logic at `$C000`): `load_level` (A = level) reads `ZPDATA/LEVELnn.ZPL` and its city's `ZPDATA/CITYnn.ZPC` with the file handler: the record, the city bank, the level's map changes, the palette and sky colour, the draw distance |
| `ZPDATA/` | the level and city data files, made by `gentables.py`: `LEVEL01`–`LEVEL50.ZPL`, `CITY01`–`CITY10.ZPC`. Copy beside `zpolice.nex` |
| `file_handler.asm` | SD card file handling (`PAGE_FILE`, page 16, at `$E000` in slot 7), general purpose over the esxDOS / NextZXOS API (`RST $08`): `fh_init`, `fh_open`, `fh_close`, `fh_read`, `fh_write`, `fh_seek`, `fh_size`, `fh_load`, `fh_save`, `fh_exists`, `fh_delete`. Carry set on error with A = the esxDOS error code. Each call pages the ROM into slots 0–1 for the `RST $08` (the divMMC only traps it then) and puts the game's pages back. Call from outside slot 7; names and buffers in `$4000`–`$DFFF`. The emulator (`tools/nexsim.py`) models these calls on a host folder (`cpu.esx_root`) |
| `interrupts.asm` | interrupt mode 2 (page 7 after `map.asm`, always mapped): `im2_table`, 256 words at a 256-byte boundary all pointing at `im2_routine`, which sits at an address with equal high and low bytes (`$xyxy`) so any data-bus byte, odd or even, reaches it; `im2_init` (I = the table's high byte, `IM 2`), called by `start` after `init_audio`. `start` enables interrupts before the main menu. `im2_routine` (50 a second) switches to its own stack and plays the engines (`engine_tick`, with its own AY writer `isr_ay`). See "Interrupts" |
| `audio.asm` | sound (`PAGE_AUDIO`, page 17, at `$E000` in slot 7): `init_audio`, called by `start` after `initgame` and by every menu screen (`menu_clear`), puts the three TurboSound AY chips in a known silent state (both outputs on, every register 0, then the mixer to tones only with noise off and the envelope to attack-and-hold), leaving AY 1 selected. The VTOL's engines on AY 1 (`engine_start`, `engine_sound`: see "Engine sound"). Helpers: `ay_select` (A = `AY_CHIP_n`), `ay_write` (A = register, E = value). The emulator records AY register writes (`cpu.ay`) |
| `initialise.asm` | start-up set-up (`PAGE_INIT`, page 15, at `$E000` in slot 7): `initgame`, called once by `start`, sets the CPU speed, Layer 2 mode, transparency, layer priority, Layer 2 scroll and clip window, the always-mapped slots and the border |
| `sprite_data.asm` | sprite pattern banks (8K pages from `PAGE_SPR0`, page 9, assembled at `$E000` and swapped into slot 7 to load): a count, a first pattern number and the patterns; bank 0 has the human status sprites |
| `map.asm` | the city map (page 7 after `human.asm`, always mapped): drawing it into both Layer 2 buffers, the ULA set-up over it, the player's flashing dot, zombie blips, human dots |
| `human.asm` | humans to rescue (page 7 at `$7000`, always mapped): placement, map dots, drawing, landing rescue |
| `weapons.asm` | weapons page (`PAGE_WEAPONS`, game logic at `$C000`): machine gun firing, round movement and collision with buildings, ground and zombies |
| `player.asm` | player page (`PAGE_PLAYER`, game logic at `$C000`): `update_player`, which handles keyboard input, movement, world-edge clamping and building collision |
| `sin_tables.asm` | generated: the sine table (`sin_lo`, `sin_hi`), in its own page (`PAGE_SIN`, page 14) at `$0000`, so it is 256-byte aligned with no padding. `get_sin` pages it into slot 0 on each call; only the game logic calls it, never the drawing |
| `htabs.asm` | generated: `hztab` (horizon row per pitch) and `htab` (building height per map code), resident |
| `city_map.asm` | generated: the constants every city shares: the base and perimeter wall (`PAD_*`, `TERRACE_*`, `BASE_YAW`, `WALL_FAMILY`). The maps themselves are in the city files |
| `l2_pallets.asm` | generated: checks on the fixed Layer 2 colour slots. The palettes themselves are in the city files |
| `gentables.py` | generates `sin_tables.asm`, `htabs.asm`, `city_map.asm` and `l2_pallets.asm` (above), the data files in `ZPDATA/` (cities and levels), `tables_city.inc` (reciprocals, log2, used corners) and `tables_hspr.inc` (the human status hardware sprite patterns) |
| `layer2_cls.asm` | zxnDMA equates, the fill command block and `dma_fill` (resident, in the main page): used by `clear_screen`, the occlusion buffer's reset (`occ_begin`), `menu_clear` and `ula_init` |
| `tools/nexsim.py` | small headless Z80N emulator used for testing: dumps every flipped frame to PNG and counts T-states per routine |
| `build.bat` | build script: the generators, sjasmplus, then the regression tests |
| `tests/` | the regression tests (`run_tests.py` runs them; `zptest.py` the shared helpers; `ref/render.ref` the renderer's reference views). See "Regression tests" |

## Memory map

```
$0000-$1FFF  one 8K section (32 rows) of the Layer 2 back buffer, slot 0
             pixel address = (y & 31)*256 + x  ->  H = y & 31, L = x
             (outside the drawing: the sine table, PAGE_SIN = page 14,
             sin_tables.asm, paged in by get_sin)
$2000-$3FFF  PAGE_ZOMBIE (page 5) - always mapped (slot 1): zombie.asm,
             then the humans (human.asm), the HUD map code (map.asm) and
             the IM 2 vector table and routine (interrupts.asm)
$4000-$5FFF  occlusion data (page 6, OCCLUSION_CULL)
$6000-$7FFF  the city bank (page 7) - always mapped (slot 3): city_col
             ($6000, cell colour families) and city_map ($7000, cell
             codes and marks), read from the level's city file
$8000-$9FFF  ULA screen (page 10, the first half of bank 5, slot 4):
             bitmap $8000, attributes $9800
             (while main_loop draws the city: PAGE_CITY2, page 34,
             city2.asm, the second city page)
$A000-$BFFF  resident main code, shared variables and tables, the
             current level's record, stack (PAGE_MAIN = page 11, the
             unused second half of bank 5, slot 5; ~2.5K)
$C000-$DFFF  game logic page, swapped with NextReg $56 (LOGIC_MMU):
               PAGE_PLAYER  (page 3)  player.asm  - input/movement
               PAGE_WEAPONS (page 4)  weapons.asm - weapons
               PAGE_MENU    (page 8)  menu.asm    - main menu, game over
               PAGE_LEVEL   (page 30) level_load.asm - level and city files
               PAGE_SPECIAL (page 31) specials.asm - special monsters
               PAGE_LOADOUT (page 32) loadout.asm - load-out screen
               PAGE_KEYDEF  (page 33) keydef.asm  - redefine keys screen
             (at start-up: the boot stub, PAGE_BOOT = page 0)
$E000-$FFFF  core function page, swapped with NextReg $57 (CODE_MMU):
               PAGE_CITY    (page 1)  city.asm    - Layer 2 drawing
               PAGE_HUD     (page 2)  hud.asm     - ULA HUD
               PAGE_INPUT   (page 12) input.asm   - keyboard, joysticks
               PAGE_SPRITES (page 13) sprites.asm - hardware sprites
               PAGE_SPR0    (page 9)  sprite_data.asm - a sprite bank, while
                                      spr_load_bank copies its patterns
               PAGE_INIT    (page 15) initialise.asm - start-up set-up
                                      (initgame), once
               PAGE_FILE    (page 16) file_handler.asm - SD card files
               PAGE_AUDIO   (page 17) audio.asm - sound set-up, engines
```

**Code pages:** the names are in `memory_bank_defs.asm`.
* **Two swapped slots:** game logic runs in slot 6 (`$C000`) and core
  functions in slot 7 (`$E000`), so logic can call a core page directly.
  `main_loop`:
  1. pages `PAGE_INPUT` into slot 7 and calls `kbd_scan`, and pauses
     (`game_pause`) if the pause control was pressed;
  2. runs `PAGE_PLAYER` and then `PAGE_WEAPONS` in slot 6. They test keys
     with `key_held` / `key_pressed`, which are still in slot 7.
  3. pages `PAGE_CITY` into slot 7, and `PAGE_CITY2` into slot 4 over
     the ULA screen, for the clear, the dots, the city, the rounds and the
     gunsight;
  4. puts the ULA screen back in slot 4 and pages `PAGE_HUD` into slot 7,
     for the gauges, the map marker and the FPS text.
* **The second city page (`city2.asm`):** the city code outgrew its 8K
  page. Part of it is now in `PAGE_CITY2`, assembled at `$8000` and
  mapped into slot 4 for step 3 only. That part is the street dots, the
  bullets, rockets and particles, the gunsight and the occlusion culling,
  about 1.9K, with 6.3K left.
  * Nothing in step 3 uses the ULA screen. The video hardware shows it
    from bank 5 whatever the CPU has mapped, so it stays on screen.
  * The interrupt routine uses only slots 1 and 5, so interrupts stay on.
    It must never use the alternate registers either: the cell walks keep
    their place in HL', DE' through the whole drawing (see "City drawing
    (2026-11-03)" under "Performance").
  * Both pages are mapped together, so their code and variables call and
    use each other directly. Their variables stay in the city page.
  * The cost is 2 `nextreg`s a frame (40 T).
  * Code that calls into `PAGE_CITY2` from outside step 3 must map it
    itself and put the ULA screen back after (`nextreg CITY2_MMU,PAGE_CITY2`
    / `nextreg ULA_MMU,PAGE_ULA0`). `clear_screen`, used at a level's
    start, stays in the city page.
* **Menu:** the menu (slot 6) pages the keys into slot 7 itself.
* **Sprites:** callers page `PAGE_SPRITES` into slot 7 before using the
  sprite routines.
* **Boot:** the resident code is in page 11 at `$A000`, but the NEX loader
  starts with its default mapping, where slot 5 is page 5. So the NEX entry
  point is a stub, `boot`, in `PAGE_BOOT` (page 0) at `$C000`, which is
  slot 6 by default. It maps page 11 into slot 5 and jumps to `start`.
* **Calls:** code in any page may call the resident main code, the zombie
  page and page 7. A core page never calls a logic page.
* The zombie page is the exception to swapping: it stays mapped at `$2000`
  (slot 1, set at start-up). `main_loop` calls `zombie_update` from there,
  and the city page jumps into `zombie_cell` while it draws. The zombie
  page in turn calls the city page's rotation, projection and `seg_map`.
* Variables shared between the pages (camera, view set-up, `seg_base`,
  FPS counters, `city_map`) stay in the main code. Everything else is local
  to its page.
* The stack lives in resident memory, since `$C000–$FFFF` changes
  underneath it.

Each Layer 2 buffer is three 16K banks (rows 0–191). The viewport is rows
0–127, and the city map sits in rows 128–191. Buffer A is banks 9–11 and
buffer B is banks 12–14. The buffers are double buffered with the hardware shadow register:
NextReg `$12` is the active (displayed) bank and NextReg `$13` the shadow
bank. Each frame `map_shadow` reads the shadow bank back from `$13` and
records the 8K page of its first row (`seg_base`). During the vertical blank
`l2_flip` swaps the two registers, so the registers themselves record which
buffer is which.

Layer 2 is written through MMU slot 0 only, one 8K section at a time, paged
in as drawing reaches it. Each section holds 32 rows, so row y is page
`seg_base + y/32`, and within the paged section a pixel is just
`ld h,y&31 : ld l,x : ld (hl),c`.
* `seg_map` pages in the section for a row.
* The polygon filler pages once per polygon, then again inline when a span
  row crosses a 32-row boundary. It can't call a routine there because SP is
  borrowed for `PUSH` writes.
* The line drawer checks `bit 5,h` after each y step. On a crossing,
  `line_seg` pages in the next or previous section and wraps H.
* The clear fills section by section with the DMA, and each ground dot pages
  its own section.

The ROM is never needed, so interrupts stay disabled. That also lets the
fillers use the stack pointer as a fast write pointer.

## Scale
One map tile is 20 m × 20 m and one height unit is 10 m (`TILE_M`,
`HEIGHT_M` in `zpolice.asm`). A tile is 256 world units and a height unit
128 (`TILE_UNITS`, `HEIGHT_UNITS`), so world units are the same size on
every axis: 1 m = 12.8 units and 1 unit ≈ 7.8 cm. The renderer, the
rounds' slopes and the distance tests need no scaling between axes.
Building heights, the ceiling, the pad and the terrace are given in height
units.

| Quantity | Units | Metres |
|----------|-------|--------|
| City (64 × 64 tiles) | 16384 | 1280 m |
| Draw distance (`VIEW_R` 8 tiles) | 2048 | 160 m |
| Building height per level (15 levels) | 60 | 4.7 m |
| Tallest building / perimeter wall (7.0 height units) | 896 | 70 m |
| Flight floor / ceiling (`MIN_Y` / `MAX_Y`, 1.5 height units) | 8 / 192 | 0.6 m / 15 m |
| Ceiling with the vertical thrusters (`MAX_Y_THRUST`, 3.0 height units) | 384 | 30 m |
| VTOL, length × width (`VTOL_HL`, `VTOL_HW` are halves) | 128 × 38 | 10 m × 3 m |
| Clearance above a roof (`COLL_H`) | 12 | 0.94 m |
| Zombie height (`ZOMBIE_H`) | 26 | 2 m |
| Zombie hit box (`ZHIT_R` either side, `ZHIT_H`) | 6 × 26 | 0.5 m × 2 m |
| Rescue range (`RESCUE_R`, 2.0 tiles) | 512 | 40 m |

Speeds are applied once per rendered frame, so in real time they scale with
the frame rate. At 14 fps:

| Speed | Units/frame | m/frame | m/s |
|-------|-------------|---------|-----|
| Top speed (`SPEED_MAX`) | 28 | 2.19 | ≈ 31 (110 km/h) |
| Full reverse (`SPEED_MIN`) | −6 | 0.47 | ≈ 6.6 |
| Climb / descend (`CLIMB_RATE`) | 4 | 0.31 | ≈ 4.4 |
| Zombie walk (`zspeed` 10 = 0.63) | 0.63 | 0.049 | ≈ 0.7 |
| Machine gun round (`BULLET_STEP`) | 457 | 35.7 | 500 |
| Human running to the VTOL (`HUMAN_RUN`) | 9 | 0.70 | ≈ 10 |

## Figures and the sprite editor

The humans and monsters (zombies, ghouls, ghosts, banshees) are drawn from
graphics made with the sprite editor, in their own colours, at sizes that
suit their distance.

* **Colours:** 32 Layer 2 palette entries, 192–223 (families 48–55: no
  building or fixed colour uses them), set in `sprites/palette.json`.
  * Colour 0 is transparent, so 31 are usable.
  * `gentables.py` puts them in every city's palette and every level's own
    (`spritefile.apply_palette`), so the figures look the same everywhere.
* **Figures** (`sprites/NAME.json`, one per figure; the format is in
  `tools/spritefile.py`):
  * Each has its height in world units (the zombie's 26: 2 m; the ghoul's
    13), and one animation per **purpose** the game draws it for.
  * The purposes are fixed by the game (`spritefile.FIGURES`, numbered
    `ANIM_*` in `gfx_ids.inc`): zombie and ghoul `walk_front`, `walk_side`,
    `walk_rear`; ghost and banshee `float`; human `wave`, `run_front`,
    `run_side`, `run_rear`, `stand`. A side view faces left: the game mirrors it for
    a figure facing right.
  * A purpose is a list of frames, played in turn. Each frame has one or
    more **levels of detail**, largest first: each its own pixels (any size
    up to 64×64) and `min_z`, the nearest distance it's drawn from (the
    first from 0). Left blank, `min_z` is worked out from the figure's
    height: the distance at which its projected height is the level's
    (`128 × height / level height`).
  * The game draws the level whose `min_z` is the largest not past the
    figure's distance, at its own size (no scaling), its bottom centre on
    the figure's feet.
* **The editor** (`python tools/sprite_editor.py [figure]`): the figure, its
  purposes, the purpose's frames and the frame's levels on the left; the
  level's pixels, enlarged, in the middle; the colours, the tools and a
  preview (game size and twice it, playing the frames) on the right.
  * Paint with the left and right buttons (two colours), Ctrl+click picks
    a colour up, and the tools are Pencil, Fill and Line. Undo is Ctrl+Z.
  * Edit: mirror, flip, shift, clear, copy the previous frame's level, and
    edit a colour (or double-click its swatch). The view menu has an onion
    skin, the previous frame faintly under this one.
  * Frame: add, duplicate, delete, move. Level: add, make the next from
    this one (scaled down, each pixel the most common colour it covers),
    remake every frame's smaller levels from its largest, resize (keeping
    the feet), set `min_z`, delete. Levels stay in size order.
  * Save (Ctrl+S) checks the figure and writes it and the colours.
* **Build:** `gengraphics.py` (run by `build.bat`, first) checks the files
  and packs them into `ZPDATA/SPRITES.ZPG`.
  * A figure without a file is made from the original stick figures, in
    colour, at 4 levels (16, 12, 8 and 4 rows high).
  * Up to 4 pages of 8K (`GFX_PAGES_MAX`): the directory (per purpose its
    frames; per frame its levels, farthest first: `min_z`, size, page,
    address), then the pixels, a row at a time: its first drawn pixel's
    column, a count, and each pixel's palette entry (0: transparent).
  * The starting figures take 2 pages (10K).
* **In the game:**
  * **Loading:** at start-up `gfx_load` (`level_load.asm`) reads the file
    into pages 35 on (`PAGE_GFX0`), each through slot 4, and checks it
    fits this game (magic, version, pages, purposes). Without it
    (`gfx_ok` 0) the figures aren't drawn.
  * **Drawing:** while the city is drawn, the graphics pages are mapped in
    slot 6 (the game logic's slot, unused then) as needed.
    * `fig_draw` (zombie page) projects the figure. The figure's chooser
      (`zfig_sel`, `gfig_sel`, `hum_sel`) sets its purpose, frame and
      mirroring.
    * `spr_lod` (`city2.asm`) picks the level for its distance, and
      `spr_draw` draws it.
    * A row wholly on screen goes through a quick loop, patched for
      mirroring and for drawing all in one colour (`spr_col`: a fading
      ghost). A row across a screen edge is clipped per pixel; rows off
      the view are skipped.

## Levels and cities

Levels and cities are data files in `ZPDATA/`, read from the SD card when a
level starts (`load_level`, `level_load.asm`). Nothing about a city is built
into the program except what all cities share: the base plaza and landing
pad in the centre, and the perimeter wall.

* **City maps (`maps/CITYnn.json`) and the map editor:** each city's
  layout is a JSON file in `maps/`, the source `gentables.py` builds the
  city's `CITYnn.ZPC` from (a city without one is generated from its seeds
  and its JSON written, once). The format, loading, saving and checks are
  in `tools/citymap.py`, shared by `gentables.py` and the editor:
  * `"map"`: 64 strings of 64 characters, one per cell: `.` road, `1`–`9`
    `A`–`F` building height levels, `P` landing pad, `T` terrace, `X` out
    of bounds. `"colours"`: 64 strings of 64 fields, each cell's colour
    family `00`–`63`, or `..` for none (road, out of bounds).
  * **Checks (`validate`):** the map's edge is all wall (`F`) or out of
    bounds; the landing pad is at (32, 32) and nowhere else (the game's
    base is fixed there); every building has
    a colour; out of bounds only touches out of bounds or wall, so the
    wall closes it off. Terrace (`T`) can go anywhere: away from the base
    it's an improvised barricade, at most 30 (`MAX_BARRICADES`). (In the
    game the 5 × 5 base is always set to pad and terrace at each level's
    start, `base_init`.) `gentables.py` (`build.bat`) stops on a map that
    fails.
  * **Editor (`python tools/map_editor.py [maps/CITYnn.json]`,
    tkinter):** the map drawn flat at 8 pixels a cell (View menu: 4 or 12)
    in an 8-pixel white border, and on the right the tools, the building
    height (1–15) and the city's 64 colour families, read from its built
    `ZPDATA/CITYnn.ZPC` (grey until it's built).
    * Paint: Building (the selected height and colour family), Road, Outer
      wall (height 15, the wall's family), Landing pad, Terrace, Out of
      bounds.
    * Change (with the Building tool): **Both** (height and colour, as
      before), **Colour only** (buildings keep their height and take the
      selected colour family) or **Height only** (buildings keep their
      colour and take the selected height). Roads, terrace, the pad and out
      of bounds are left alone by Colour only and Height only; the other
      tools always change the whole cell. It works with every draw mode
      (Fill too: a road clicked with Colour only says so).
    * Draw (how): Pencil (click or drag), Line, Box (a rectangle's
      outline), Rectangle (filled), Fill (the area of cells like the one
      clicked, joined side to side), Select (drag a rectangle). Each is one
      change for Ctrl+Z, and none makes a second pad or a 31st barricade.
    * Edit menu: Select all (Ctrl+A), Copy the selection (Ctrl+C), Paste
      (Ctrl+V, then click where its top left goes), Mirror the selection
      left-right or top-bottom; Esc drops the selection or stops pasting.
    * Edit > Wall round out of bounds: perimeter wall on every cell next to
      out of bounds (diagonals too) that isn't wall or out of bounds
      already, then says if any wall still breaks the wall rule.
    * Colours: "Edit colours..." (or Edit > Edit colour family) sets a
      family's 3 shades by hand, r g b 0–7 each, beside the generated ones.
      They're saved in the map file (`"palette"`) and `gentables.py` lays
      them over the generated palette; Reset puts the generated shades back
      (`maps/generated/CITYnn.pal`, written by the build). Layer 2's
      transparent colour can't be used. A family set by hand has an orange
      line under it in the palette.
    * Level colours: in level mode (below), "Edit colours..." changes that
      level's own palette, not the city's.
      * It starts from the city's colours. Reset puts a family back to the
        city's shades, and the orange line marks families that differ from
        the city's.
      * Save writes the whole palette to `levels/LEVELnn_PAL.json` (format
        in `tools/levelpal.py`: 64 families of 4 colours, r g b 0–7), along
        with the level's map changes.
      * If no family differs from the city's, Save removes the file. Level >
        **Use the city's colours** drops it for the whole level.
      * `gentables.py` checks each palette file and makes
        `ZPDATA/LEVELnn.ZPP` from it: `"ZPPL"`, version 1, the level number,
        2 reserved bytes, then the 512-byte Layer 2 palette. When the palette
        file is gone, the build deletes the `.ZPP`.
      * The game's `load_level` sets the city's palette and sky. Then, if
        the level has a `.ZPP`, it loads it into `ll_cbuf` and puts it in the
        city palette's place (`ll_palette`). A missing or bad file leaves the
        city's colours.
      * The preview draws the level in its own colours, saved or not
        (`preview.py --palette`). `tools/check_maps.py` checks the palette
        files too.
    * Level menu: **Edit a level's map changes** shows the city as one of
      its levels changes it; painting then changes that level only, and
      Save writes its `CHANGES` (at most 64; counted below the map) to
      `levels/LEVELnn.TXL`, not the city. The landing pad can't be touched
      there. **Back to the city map** returns. **Level settings** edits a
      level's zombies, waves, fast zombies, draw distance and each wave's
      special monsters (ghosts, banshees, ghouls), checked before saving.
    * View > **Preview from a point**: click the map, give a heading and a
      height, and the game draws that view in the emulator, in the
      background (`tools/preview.py`), from the map as it is in the editor,
      saved or not (in level mode, with the level's changes).
    * Below the map: "Barricades: n / 30 placed" and "Landing pad: n / 1"
      (red when over). Painting won't place a 31st barricade or a second
      landing pad (the status line says why).
    * View > Invert roads draws roads white, to pick them out. It only
      changes the view, not the palette or the saved map.
    * Colour families: each is shown as a group of its 3 shades in palette
      order: `SHADE_DARK` (family×4+0, the family's base entry), then
      `SHADE_FACE` (+1), then `SHADE_ROOF` (+2). There are 4 families a
      row, in family order (00–03 on the top row). The map itself still
      shows each building's facing side (`SHADE_FACE`), as it looks in the
      game.
    * Only the `SHADE_DARK` swatch of the buildings' families, 01–15
      (`BLD_FAMILIES`), can be picked. Each has a white border, and the
      selected one a yellow one. The game stores a cell's colour as that
      entry (`city_col` = family×4) and adds the shade bits when drawing,
      so any other entry would draw the wrong colours. Clicking a face or
      roof swatch only says to pick the dark one. 16–61 (kept free for the
      HUD and monsters), 62 (the terrace's) and 63 (the pad's) have a line
      through them; clicking them only says whose they are.
    * Building colours are limited to families 01–15 (`BLD_FAMILIES` = 16,
      in `tools/citymap.py` and `gentables.py`). A building on any other
      family fails the check (`validate`) and the build.
    * `tools/remap_families.py` moved every map's buildings onto 01–15
      (2026-11-01). Each building on family 16 or above took the family
      among 01–15 whose dark, face and roof shades are nearest in r g b, in
      the city's built palette. The levels' map changes are remapped the
      same way (none needed it). Run it again if `BLD_FAMILIES` changes
      (`--dry-run` only reports).
    * A building (heights 1–15, walls included) whose colour isn't the
      `SHADE_DARK` of a building family is invalid. That's family 62 or 63,
      none (".."), or a field that isn't a family at all, such as a
      hand-typed "64" or "7x". The check (`citymap.bad_colours`, in
      `validate`) stops saving cleanly and `build.bat`; gentables also
      asserts every building's `city_col` is such an entry
      (`citymap.is_bld_col`). The "Show bad colours" button flashes those
      buildings red for 3 seconds; one repainted meanwhile stops flashing.
    * Only the perimeter wall may use the wall's colour (family 00,
      `WALL_FAMILY`), since the game draws the sky in it. Family 00 can't be
      picked for a building; the Outer wall tool paints it. A cell on family
      00 is a perimeter wall tile only if (`citymap.bad_walls`):
      * it is height F;
      * at least 2 of the tiles left, right, above and below it are wall
        (height F on family 00), so the wall runs on; and
      * unless it is in the map's first or last row or column, at least 1 of
        its 8 neighbours is out of bounds (diagonals count, for the corners
        round an out of bounds area).

      Anything else on family 00 is an error, flashed by "Show bad colours".
      Edit > Recolour off-wall wall colour gives all such cells random
      building colours (01–15) in one undoable step. It repeats until none
      are left, since recolouring a wall tile can leave its neighbours with
      fewer than 2. Right-clicking a perimeter wall tile selects the Outer
      wall tool. gentables no longer gives generated buildings family 00.
    * An unreadable colour field no longer stops a map loading. It is kept
      as it was typed, so you can find it, and saved back unchanged. Such
      a building is drawn magenta, and hovering over it shows the field,
      for example "family 7x (not a building family's SHADE_DARK)".
    * Left button paints (click or drag); right button picks up a cell's
      height and colour; Ctrl+Z undoes a stroke; View > Show heights
      shades buildings grey by height.
    * File menu: Load map, Save, Save map as, Check. Saving checks the map
      (or in level mode the level) and lists any problems (it saves anyway,
      so work can be kept). Then `build.bat` makes the game's files from it.
  * **Preview from the command line:** `python tools/preview.py
    maps/CITYnn.json X Z [--heading DEG] [--height UNITS] [--level N]
    [--out FILE.png]` draws the game's view from cell (X, Z) (heading 0
    north, up the map; 90 east) into a PNG. It builds a temporary SD card
    with that map in place of the built city, starts the game in the
    emulator and puts the VTOL there. The game must be built.
  * **Check everything:** `python tools/check_maps.py` checks every city map
    (`citymap.validate`, with its hand-set shades) and every level file
    (`levelfile.level_check`, the map changes against their city), prints
    each file's problems or OK, and exits 1 if any has problems.
  * **Shared code:** `tools/citymap.py` (the map files), `tools/levelfile.py`
    (the level files' text and binary forms and their checks), used by
    `gentables.py`, the editor and the tools.
* **Text forms (for editing):** beside each binary file, `gentables.py`
  writes a plain text copy holding exactly the same data: `CITYnn.TXC` for
  `CITYnn.ZPC` and `LEVELnn.TXL` for `LEVELnn.ZPL`. They're the start of a
  city layout editor. The game only reads the binary files.
  * **`CITYnn.TXC` (about 19 KB):** `CITY`, `NAME`, `TIME`, `SKY r g b`;
    `PALETTE`: 64 lines, one colour family each (`Fnn`, then its 4
    palette entries as `r g b`, 0–7); `MAP`: 64 lines of 64 characters,
    one per cell (`.` road, `1`–`9` `A`–`F` building heights 1–15, `P`
    the landing pad, `T` its terrace); `COLOURS`: 64 lines of 64 fields,
    each cell's colour family `00`–`63` or `..` for a road; `END`.
  * **`LEVELnn.TXL`:** `LEVEL`, `CITY`, `NAME`, `ZOMBIES`, `WAVES`, `FAST`,
    `VIEW`; then a line for each wave, `WAVE n` and up to 5 type / count
    pairs (`GHOST`, `BANSHEE`, `GHOUL`), e.g. `WAVE 1 GHOST 5 GHOUL 2`;
    then `CHANGES n` and n lines
    `x z code family` (the map cells changed for the level, in the same
    characters as the city file); `END`.
  * Lines starting `;` are comments. `city_from_text` and
    `level_from_text` (gentables.py) turn a text file back into its
    binary file's bytes; every file written is checked to convert back
    exactly.
* **Cities:** `CITYnn.ZPC` (8,736 bytes). Each city is played for 5 levels
  (`CITY_LEVELS`). A city file holds:
  * a header with the city's name and its sky colour;
  * its own Layer 2 palette, for its time of day. A city can also have a
    colour style (`CITY_STYLE` in gentables.py): the building colour
    families whose main face is one of its hues are replaced with its
    materials (`restyle`). London's green, blue, cyan, red and indigo
    families become brick reds and concrete greys, in turn (30 of 62
    families, the perimeter wall's included);
  * `city_col` and `city_map`, loaded in one 8K read into the city bank.

| City | Levels | Time of day |
|------|--------|-------------|
| 1 London | 1–5 | day: the original city and colours |
| 2 Paris | 6–10 | dusk: warmer, darker |
| 3 Tokyo | 11–15 | night: dark and blue |
| 4 New York | 16–20 | dawn: pale and misty |
| 5 Berlin | 21–25 | day |
| 6 Rome | 26–30 | dusk |
| 7 Moscow | 31–35 | night |
| 8 Sydney | 36–40 | dawn |
| 9 Cairo | 41–45 | day |
| 10 Chicago | 46–50 | night |

* **Levels:** `LEVELnn.ZPL`. Each holds:
  * its city's number;
  * the level record (`levels.asm`, 113 bytes): the city name, the numbers
    of zombies a wave, waves and fast zombies, the draw distance, and each
    wave's special monsters (up to 5 types and how many of each, for up to
    10 waves; wave 1 is the level's start). The level file is format
    version 2 (`LEVEL_VERSION`; the city file stays 1, `CITY_VERSION`);
  * a list of map changes (x, z, cell code, colour, up to 64), applied after
    the city loads, for hand-made layout changes on that level.
* **Draw distance:** 2–8 tiles (`view_r`; the street dots' radius `dot_r`
  is one less). Fewer tiles stand in for night or fog. Every level uses 8
  (`VIEW_R`) for now.
* **Making them:** `gentables.py` makes the cities from seeds (city 1 keeps
  the original seeds, so it's the original city) and writes the 50 level
  files. The file formats are described at the top of its "Cities and
  levels" section.
* **Hand-edited levels:** each level's source is `levels/LEVELnn.TXL`, the
  text form (below), edited by hand as the city maps are in `maps/`.
  * A level without one is generated from the rules (the old level table's
    values, as placeholders) and its source written once; from then on
    `gentables.py` reads the file, so edits stay.
  * Set the draw distance (`VIEW`, 2–8 tiles) for night or fog, the
    zombies, waves and fast zombies, each wave's specials (`WAVE n` lines),
    and map changes for that level only (`CHANGES n`, then `x z code
    family` lines, e.g. `32 40 T 62` for a terrace barricade, `20 20 6 12`
    for a height-6 building in colour family 12, `5 9 . ..` for road).
  * `level_check` stops the build on anything the game can't use, saying
    which file and what: a level number that isn't the file's, a city that
    doesn't exist, zombies over 30, waves outside 1–10, more fast zombies
    than zombies, a draw distance outside 2–8, an unknown special type,
    over 5 types or 8 specials in a wave, over 64 map changes, a change
    outside the map, on or adding a landing pad, or in the wrong colour
    for its cell (a building in a building colour, a road or out of bounds
    in none, terrace in its own), and, with the changes made, over 30
    barricades or the wall's colour off the perimeter wall.
  * `ZPDATA/LEVELnn.TXL` is a copy of the source, beside the binary
    `LEVELnn.ZPL` the game loads. The build says how many levels differ
    from the rules.
  * To regenerate a level from the rules, delete its source and build.
* **Sky colour:** it's written to palette slot `SKY_COL`. While
  `SKY_IS_WALL` is on, the sky area is filled with the perimeter wall's
  colour instead, which is tinted with the city.

### Waves and level progress
* **Zombies a wave:** the level record's `LV_ZOMBIES`, at most 30
  (`NZOMB`, the zombie records). Over each city's 5 levels it's 10, 15, 20,
  25, 30, then the cycle repeats in the next city.
* **Waves:** `LV_WAVES` is 1 on the first city's levels, plus one more for
  each city after: 2 on levels 6–10, up to 10 on levels 46–50.
  `LV_FAST` of a wave's zombies are fast. (`gentables.py` writes these
  into the level files.)
* **Each frame:** `zombie_update` first checks for a wave wiped out (no
  monster record active, `NMON`: zombies, ghosts and banshees; a dying
  special counts until it has faded).
  * If waves remain, it counts the next (`wave_number`) and `zombie_wave`
    places a new wave of `LV_ZOMBIES` at random street positions.
  * After the last wave, it sets `level_done`.
  * The level's ghosts are placed with the first wave, so it lasts until
    they are killed. Banshees spawned with an even wave belong to it.
* **Level complete:** `main_loop` shows LEVEL COMPLETE
  (`level_complete_screen`, menu.asm), with PRESS SPACE TO CONTINUE on the
  bottom row, until SPACE is pressed: a new press, so SPACE held down for
  firing as the level ended doesn't skip it. Then the load-out screen
  (below). Then it starts the next level (`next_level`,
  zpolice.asm) with the level's files loaded and the city set up afresh.
  * The VTOL goes back onto the pad, level and still.
  * Its hit points and weapons carry on. Its ammunition is replenished:
    `rearm_all` gives every slot its weapon's full load (`WCFG_LOAD`).
  * Everyone still aboard the VTOL counts as rescued (`hum_unload_all`,
    human.asm): off the VTOL (`passengers` 0), state `HS_SAVED`, and added
    to `saved`, before the salvage is worked out.
  * **Salvage (`salvage_award`, menu.asm):** each human saved in the level
    (`saved`) adds 1 to `salvage_points`. Every total in `salvage_tab`
    reached gives its rewards: a weapon unlocked (one more in `wpn_stock`,
    a resident count per weapon type, for the load-out screen) and/or
    a full repair (`vtol_hp` = `VTOL_HP`, `SA_REPAIR`) or the booster module
    (`SA_BOOSTER`). After 145 (`SALVAGE_TAIL`),
    every 5 more points is a full repair. The screen shows the humans
    saved, the salvage, AMMUNITION REPLENISHED and a line for each reward.
    SALVAGE.md lists every reward score by score.

    | Salvage | Reward |
    |---------|--------|
    | 10 | laser |
    | 40 | bomb (was a laser) |
    | 65 | night vision, monochrome (no longer a laser) |
    | 90 | lateral thrusters (was a laser) |
    | 20 | chain gun (75 and 95 removed) |
    | 50 | linked chain gun L (was a chain gun) |
    | 55 | linked chain gun R and full repair (was a proximity cannon) |
    | 30, 60, 80 | rocket pod |
    | 15 | full repair |
    | 35 | vertical thrusters: climb to 30 m (was a full repair) |
    | 70 | proximity cannon and full repair |
    | 75 | proximity cannon (was a chain gun) |
    | 25 | night vision, green (was a full repair) |
    | 45 | booster module (was a full repair) |
    | 85 | thermal vision (was a full repair) |
    | 100 | rocket pod and full repair |
    | 105, 110, 120, 125 | autocannon and full repair |
    | 115, 130, 135, 140 | missile pod and full repair |
    | 145 | full repair (the missile pod removed) |
    | 150, 155, ... | full repair |

    `newGame` clears the stock and sets the salvage to `START_SALVAGE` (0;
    raised only to test the rewards). Rewards at or below the starting
    salvage are never given. With `DEBUG_UNLOCK_ALL` defined (a test
    setting: comment it out for a release), a new game starts with every
    upgrade: the booster (full), the vertical thrusters and all three
    vision modes.
  * **Load-out screen (`loadout_screen`, loadout.asm, `PAGE_LOADOUT` page
    32 in slot 6):** before the first level (`newGame` ends with `jp
    loadout_go`) and after each LEVEL COMPLETE, `loadout_go` (resident)
    pages it in. At the start of a game the store has only the machine gun,
    already fitted (0 in store), as other weapons are unlocked by salvage. On the left, the store: every weapon type unlocked
    (`wpn_unlocked`: fitted at the start of the game, or unlocked by
    salvage) with the number in store (`wpn_stock`), shown even at 0 when
    the only one is fitted. On the right, the 5 slots and what's fitted.
    * **1–5** select a slot (shown yellow).
    * **Q / A** move the highlight up and down the store list. The list is
      white; the highlighted weapon is green if it can go in the selected
      slot (`wpn_fits`, and one is in store), red if not.
    * **SPACE** fits the highlighted weapon in the selected slot, if it can
      go there. One comes out of the store with a full load, and whatever
      was fitted goes back into the store.
    * **U** unloads the selected slot (`lo_unload`): its weapon goes back
      into the store and the slot shows EMPTY. Its ammo isn't kept: fitted
      again, it gets a full load, as any weapon from the store does. If it
      was the slot the game fires (`wpn_sel`), the first slot still fitted
      is chosen instead.
    * **0** confirms the load-out and starts the level (START LEVEL), but
      only with a weapon in slot 1 (the centre slot). While slot 1 is empty,
      0 does nothing and "0: START LEVEL" is drawn red.
    * It uses the text routines shared with the menu (`text.asm`,
      resident: `menu_clear`, `menu_print`, `menu_char`, `menu_frame`,
      font8) and the keys page in slot 7.
  * `newGame` sets up the game, then falls into `next_level` for the first
    level.
* **The last level:** after level 50 (`LEVEL_LAST`, from `gentables.py`)
  comes no LEVEL COMPLETE. Instead `game_complete_screen` shows
  CONGRATULATIONS ("ALL 50 LEVELS COMPLETE", "THE CITIES ARE SAFE") for
  10 seconds, then GAME OVER for 10 seconds, then the main menu.

## City map bytes

Each cell of `city_map` (64 × 64) is one byte:

| Bits | Meaning |
|---|---|
| 0–4 (`CELL_CODE`) | cell code: 0 road, 1–15 building height level, 16 the landing pad (`PAD_CODE`), 17 the terrace (`TERRACE_CODE`), 18 out of bounds (`VOID_CODE`) |
| 5 | free (for later: salvage, pickups, etc.) |
| 6 (`CELL_HUMAN`) | a human waits in this cell (`hum_flags`, human.asm) |
| 7 (`CELL_ZOMBIE`) | a zombie or special monster stands in this cell (`zflags`, zombie.asm); its type is in its zombie record |

**Barricades:** terrace tiles (`TERRACE_CODE`) away from the base, as
improvised barricades. Each has its own hit points.
* `barricade_init` (zombie.asm, at the end of `base_init`, so after the
  level's map changes) scans the map and fills `barr_tab` (resident):
  up to `NBARR` (30) entries of x, z, hit points (`TERRACE_HP`, 100);
  `barr_n` counts them. Any more than 30 stay on the map but can't be
  destroyed (the map editor and `build.bat` keep a city to 30).
* To zombies a barricade is a base tile (`zbase`), so one that walks into
  it attacks it, 1 hit point every 5 frames. Rocket, missile and shell
  blasts damage it too.
* `base_damage` sends a tile outside the 5 × 5 base to `barr_damage`,
  which finds it in the table. At 0 hit points it's removed from the map:
  road, as a destroyed base terrace tile (its colour and map dot too), and
  the zombie walks on.

**Out of bounds (`VOID_CODE`, 18):** cells outside the city's perimeter
wall, so a city can be another shape than the full 64 × 64 map (none of
the generated cities use it yet).
* Never drawn: `draw_cell` skips them.
* Black on the HUD map, like a road (`map_init`, and the blip restore in
  map.asm).
* Nothing is placed there. Zombies, ghosts, banshees and ghouls are only
  placed on roads, and humans not on codes from `PAD_CODE` up, so they
  were already kept off.
* Its height (`htab` entry 18) is the wall's, `BLD_MAX_H`, so anything
  that tests heights (the VTOL's collisions, rounds, the monsters' sight
  and flight) finds it as solid as the wall. The perimeter wall keeps
  everything out anyway.
* In the city text files it is `X`. Its `city_col` is `GROUND_IDX` (`..`).

* **Reading the code:** every reader masks with `and CELL_CODE` before
  testing for road (0) or a code. `bld_height` masks for itself.
* **Changing the code:** keep the marks (`CELL_FLAGS`). For example, a
  destroyed terrace tile clears only bits 0–4.
* **Why:** the marks replace the old per-cell tables, `zcell` (4K, with
  `znext`) and `hum_bits` (512 bytes). `draw_cell` and the rounds' grid
  walk test them on the map byte they have already read.

## Maths

* **World coordinates:** 16-bit integers. One city cell is 256 units, so
  the cell index is simply the high byte of a coordinate. Camera X/Z
  positions carry an extra fraction byte so slow movement is smooth.
* **Trig values:** S7.8 fixed point (`$0100` = 1.0) from a 256-entry sine
  table, with 8-bit angles where 256 = 360°.
* **`fmul`:** integer × S7.8 → integer. It works in sign/magnitude using two
  `MUL D,E` (8×8) instructions.
* **Perspective divide:** there is no divide. Z is normalised to 9 bits
  (256..511) with the Z80N barrel shifter, using a log2 table for the shift
  count. The same shift is applied to X and Y, which are then multiplied by a
  16-bit reciprocal `2^24/Zn` from a table. Because every vertex reaching
  the projector is already inside the frustum, |X| ≤ Z and |Y| ≤ 0.5Z, so
  the normalised values fit in 9 bits. The result is rounded and accurate to
  within half a pixel.

## The viewport renderer

Everything is designed so that the expensive per-pixel stages only ever see
8-bit on-screen coordinates.

### 1. Per-frame setup
* Compute sin/cos for yaw and pitch.
* Rotate the box edge vectors into camera space once per frame. Every
  building fills its cell (`BLD_SIZE` = 256), so this is `R·(256,0,0)` and
  `R·(0,0,256)`, plus the offset from cell centre to corner. Every building
  then gets its 8 corners from one transformed point and additions.
* **Viewport:** 256×128 at rows 0–127, centre row 64, so `sy = 64 − 128·Y/Z`
  with a 90°×53° field of view.
* Look up the horizon row from a `64 + 128·tan(pitch)` table. Rows above it
  are cleared to sky and rows below to ground by two zxnDMA fills. These
  reuse the command block from `layer2_cls.asm`, patching the destination and
  length, with a fixed source byte.

### 2. Back-to-front traversal without sorting
For axis-aligned boxes sitting in separate grid cells, a box can only hide
another box if it lies between that box and the camera. Every sight line from
the camera to cell (i,j) passes only through cells whose indices lie between
the camera cell and (i,j). So box A can hide box B only if A's offsets from
the camera cell are no larger than B's on both axes, in the same quadrant.
That gives a fixed drawing order: rows from the far edges inwards, columns
within each row from the far edges inwards, and the camera's own row and
column last. This order is a correct painter's order for any view direction,
with no depth sort. The view covers ±`VIEW_R` cells.

### 3. Per-building transform and culling
* **Yaw rotation per row:** the yaw rotation of the cell centre is
  computed once per row segment. Stepping one cell in x adds exactly the raw
  `(cosY, sinY)` to `(X, Z1)`.
* **Conservative frustum cull at any pitch:** a visible point satisfies
  `|X|·c ≤ Z1`, where `c = cosP − 0.5|sinP|`. The building's bounding circle
  is tested against this before any per-vertex work.
* **Pitch and corners:** the corner is pitch-rotated (2 multiplies). The
  other 7 corners come from adding the precomputed edge vectors, and the
  height vector `h·(0, cosP, sinP)`.
* **Back-face culling:** done in world space, where it is exact for an
  axis-aligned box. For example, the −X face is visible when `camX < x0`.
  A wall against a neighbouring building at least as tall is dropped too
  (`nb_cover`), since the neighbour covers it completely.
  The result is a 5-bit visible-face mask.
* **Corner selection:** only corners belonging to visible faces get an
  outcode (near, left, right, top, bottom) and a projection. A building whose
  corners are all outside one plane is rejected.

### 4. Hidden surface and line removal, and shading
Each visible face of a building is filled in its own shade and, when
`DRAW_LINES` is defined, outlined in white. The painter's order from step 2
means nearer buildings overwrite both the fills and the lines of those
behind.

* **Shading:** each building has a colour family (see Tuning).
  * The roof uses the lighter shade.
  * When two sides are visible, the one the camera sees more squarely (the
    camera is further from its plane) uses the base colour, and the other
    the darker shade.
  * With one side visible, that side uses the base colour.
* **Faces fully on screen:** fill and outline straight from the cached
  projected corners.
* **Faces crossing the frustum:**
  * With `CLIP_2D`, pitched faces, and level-flight faces crossing two or
    more planes, are clipped on screen in 2D, provided they don't cross the
    near plane and stay within a guard band. See "Performance", "Face
    drawing".
  * Otherwise the face is clipped in 3D against 5 planes with
    Sutherland–Hodgman. The planes are near `Z=16`, `X=±Z` (90° horizontal
    field of view) and `Y=±0.5Z` (the 128-row viewport).
  * Intersection parameters use a 32/16 fixed-point divide, and new points
    are snapped exactly onto the clip plane.
  * Every vertex carries an "edge is real" flag. Edges created along a clip
    plane are filled but not outlined, so the screen border never gets a
    false line.
* **Shared edges:** edges shared between faces are outlined only once,
  using per-face edge masks.

### 5. Rasterisation (8-bit, on screen only)
* **Convex fill:**
  * Each edge is walked into one of two x tables: downward edges into one,
    upward edges into the other. Because of that, polygon winding never
    matters.
  * The walk is an exact integer DDA: quotient plus a remainder carried in a
    biased byte, so the carry flag is the error test. It hits endpoints
    exactly and matches the Bresenham outline.
  * Steep edges skip the division entirely, and exactly vertical ones
    (every wall edge in level flight) just write the same x into each row
    (`walk_edge.vert`).
  * Per row, the span loop (`fs_loop`) keeps its overhead down: the stack
    pointer is held in IY (`ld sp,iy` to put it back), the rows are counted
    down in IXH, a DMA span goes straight on to the next row (SP was never
    borrowed), and the edge table that is the left one at the polygon's
    middle row is read first (`fill_spans` patches `fs_loop`), so the
    left/right swap is mostly skipped. The swap is still made when a row
    needs it: a sliver's edges can cross.
  * Short spans are written two pixels per `PUSH DE`, by pointing SP at the
    right end of the span and jumping into an unrolled block of 128 pushes.
  * Spans of `DMA_SPAN_MIN` (20) pixels or more go to the zxnDMA. The clear
    leaves it configured with the length high byte at 0, and `fill_poly`
    puts the building colour in the fixed source byte. Each span then
    reloads only length, destination, LOAD and ENABLE: 7 `OUT`s, about
    150 T plus 2 T per pixel, against about 90 T plus 5.5 T per pixel for
    `PUSH`.
* **Lines:** Bresenham with self-modified `INC/DEC L` and `INC/DEC H`
  steps, which works because a pixel address is just `H = y, L = x`.

### 6. Zombies
Up to 30 placeholder zombies a wave walk the streets. They are Layer 2 silhouettes,
so buildings in front of them hide them correctly.
* **State:** each zombie has an x and z position in 8.8 fixed point in cell
  units, so the high byte is the cell and the low byte the position inside
  it (the same numbers as world units). It also has a heading (+z, +x, −z
  or −x) and a walk phase.
* **Heading for the base:** at a junction, with probability `zbias_t` a
  zombie takes whichever road (ahead, left or right) points most towards
  the landing pad (`zbest`: the largest dot product with the way to the
  pad). Otherwise it decides as before. The same biased choice is used
  when it's blocked and must turn left or right.
  * The level is the byte `level`, set by `newGame` to `START_LEVEL`. That
    is normally 1, but is **20 for debugging** (88% bias); set it back
    to 1 in `zpolice.asm`. Measured over 6,000 frames: 69.3% of 264
    decisions biased at level 10, 55.5% of 245 at level 1.
  * The bias is 50% on level 1 and rises 2% a level up to 95%:
    `min(ZBIAS_MAX, ZBIAS_BASE + ZBIAS_STEP·level)`. It's set as a 0–255
    threshold by `zombie_init`.
  * Over 4,000 frames on level 1, the zombies' mean distance from the pad
    fell from 23 to 17 tiles.
* **Attacking the base:** a zombie blocked by a base tile (terrace or pad)
  doesn't turn away. Junction and dead-end choices count a base tile as an
  option, alongside streets. Without that, the road towards the pad from
  the plaza's ring road was never a choice, and zombies circled the
  terrace without attacking it.
  * It walks on until it is `ATTACK_R` (0.1 tile, 26 units) from the
    tile's edge, then stops and hits it every `ZHIT_FRAMES` (5) frames for
    1 damage.
  * Terrace tiles have `TERRACE_HP` (100) hit points, the pad `PAD_HP`
    (200), kept in `base_hp`.
  * A destroyed terrace tile becomes road, on the map and in 3D, and the
    zombie walks on towards the pad.
  * Destroying the pad sets `game_over`.
  * **Attack flags:** `zatk_flags` has one byte per zombie, `FALSE` by
    default. It is set `TRUE` when the zombie starts attacking a tile,
    and its map dot is then drawn red (`MAP_ZOMBIE_ATK`, `zblip_red`) at
    its current cell. When the tile is destroyed the flag is cleared and
    the dot goes back to its usual green shades. A zombie killed while
    attacking also has its flag cleared.
  * Record bytes +16 (mode: walking, going for a base tile, attacking) and
    +17 (hit timer) hold this. `ZREC` is 31: +18 holds the hit points,
    +19, +20 the cell marked in `city_map`, +21, +22 the height of its feet
    (0 for zombies), and +23–+30 the special monsters' own fields.
  * `base_init`, called by `newGame`, rebuilds the pad and terrace and
    their hit points.
  * One zombie took 500 frames per terrace tile and 1,000 for the pad.
* **Fast zombies:** an enemy type that walks at twice the speed.
  * A zombie's record byte +15 holds its type: 0 = zombie, `ZT_FAST` (1) =
    fast zombie.
  * The level record's `LV_FAST` gives the number a wave. `zombie_wave`
    makes that many of the wave's zombies fast.
  * A fast zombie adds `zspeed` twice per frame. It covers twice the
    distance between its decision checks, so it uses a longer look-ahead
    (`zlook_fast`) and keeps the same clearance from walls.
  * Its walk cycle runs twice as fast. It's drawn and shot just like a
    zombie.
  * Because the speed doubles, `zspeed` must stay at 119 or less.
* **Seeding:** `zombie_init` picks random cells until it finds a street
  (empty `city_map` cell), then places the zombie 64–191 units into it, so
  it never starts on or against a building. The seed comes from the R
  register.
* **Speed:** `zspeed` (in the zombie page) is world units per frame in 4.4
  fixed point, so 16 = 1.0. It starts at `ZSPEED_INIT` = 10 (0.63) and can
  be raised for later levels. Each zombie keeps the leftover fraction, so
  slow speeds still average out exactly.
* **Staggered decisions:** `zsteps` (in the zombie page, 10 for the first
  level) sets how often each zombie checks for junctions and obstacles: once
  every `zsteps` frames. The zombies' check frames are spread out at
  start-up, so with 20 zombies only about 2 check on any one frame. Between
  checks a zombie just walks. Each zombie has an active flag, and zombies
  that are gone are not moved, checked or drawn.
* **Junctions:** once per cell, when a zombie is 0.25–0.75 of the way
  through the cell along its heading, it checks the cells to its left and
  right for a road. Left is tested first: if there is a road there, it turns
  left with a 1 in 2 chance. If it didn't turn left, the right gets the same
  test. The cell is then marked as decided and not tested again. Only the
  last decided cell is remembered, so the zombie decides afresh when it
  comes back to a cell later.
* **Blocked:** if a building or the map edge is within `zlook` units
  ahead, the zombie turns left if there is a road there, otherwise right.
  If neither side has a road, it turns round and stands still for `ZWAIT`
  (100) frames, with its animation frozen, before it moves or tests again.
* **Look-ahead:** `zlook` = `ZMARGIN` (32) + `zsteps`·`zspeed`/16, worked
  out each frame. It covers the distance walked between checks, so zombies
  never enter building cells and stay at least 32 units from any wall, at
  any speed. Keep `zsteps`·`zspeed` under 2048 (128 units between checks),
  or a zombie could walk through a junction's 0.25–0.75 window without
  checking it.
* **Map blips:** each zombie is a single green pixel at its cell on the
  city map. Each time its blip is drawn, on its decision-check frames, it
  takes the next shade of `zshades`: bright (`MAP_ZOMBIE`, the gunsight's
  green), mid (`MAP_ZOMBIE_MID`), dark (`MAP_ZOMBIE_DARK`), mid, then
  bright again. The step is kept in bits 1–2 of the blip byte.
  * The map is on Layer 2, so a blip is written into both buffers
    (`map_pix`).
  * Zombies only stand in street cells, so taking a blip off just puts the
    street colour (`MAP_BG`) back.
  * A blip moves only on its zombie's decision-check frames.
  * When two zombies share a cell and one leaves, the other's blip
    disappears until its own next check.
  * Call `zblip_off` before marking a zombie as gone; the weapons do this
    when they kill one.
* **Drawing in painter's order:** `draw_cell` jumps to `zombie_cell` for
  every empty cell it visits, but only when bit 7 (`CELL_ZOMBIE`) of the
  cell's `city_map` byte says zombies are there. Then the zombie records are
  searched for that cell (highest index first). So an empty street costs
  one bit test on the map byte `draw_cell` has already read.
  * `zflags`, at the end of `zombie_update`, keeps the marks. First it takes
    the mark off the cell each record last marked (+19, +20). Then it marks
    the cell of each active zombie. Doing it in two passes means two zombies
    in one cell keep the cell marked, and a zombie killed since the last
    pass loses its mark. A zombie is drawn at
  its cell's place in the back-to-front order, so nearer buildings
  overwrite it.
* **Projection:** the zombie's feet are yaw and pitch rotated with the city
  routines, then projected. Its height on screen is
  `ZOMBIE_H·128/Z` (`ZOMBIE_H` = 26, 2 m); under 3 pixels it isn't drawn.
  Its size on screen is the level of detail for its distance (see "Figures
  and the sprite editor"). If the feet
  are below the bottom of the viewport, the head is projected instead, but
  the sprite still stands on the off-screen feet, a full projected height
  below the head. That is where the feet-anchored case would put it, so the
  zombie slides smoothly off the bottom of the screen. Rows outside the viewport and columns off
  the side are clipped per pixel.
* **Graphics:** the facing comes from the zombie's heading relative to the
  camera yaw (`face_tab`): towards the camera `ANIM_ZOMBIE_WALK_FRONT`,
  away `_REAR`, side on `_SIDE` (facing left, mirrored for right); a ghoul
  its own (`ANIM_GHOUL_*`). A new walk frame every 4 frames (fast zombies
  2, ghouls 1). See "Figures and the sprite editor".
* **Cost:** about 1–2% of frame time (`zombie_update` averages about 20K T a
  frame for 20 zombies, with at most 2 decision checks in any frame).

### Performance
Measured with `tools/nexsim.py` (pure T-state count at 28 MHz, no memory
contention, vblank wait off; the emulator costs DMA at 2 T per byte, set
with the `DMA_T` environment variable):

| Flight | fps |
|--------|-----|
| Straight down a boulevard at street level | 13.6 |
| Climbing and pitching down over the blocks | 11.1 |

Draw distance is the main lever (`VIEW_R`). Real hardware adds some wait
states at 28 MHz. Movement is per frame, so game speed follows frame rate.

**Profile (2026-11-01, five busy views):** transforming and projecting
corners ~29% of a frame, filling spans ~19% (of which the per-row overhead
~10%, DMA ~6%, PUSH writes ~3%), walking edges ~8.5%, clipping ~7%,
occlusion ~6%, ground dots ~3%. The span loop's overhead, the level-flight
multiplies and vertical edges were then trimmed (above): over ten fixed
views the frame time fell 3.7% (4.9–6.5% level, 1.1–2.1% pitched), every
view pixel-identical to before, also with interrupts (see "Interrupts").

**Rejected buildings (2026-11-01):** of the 90–106 buildings tried a frame,
62–74 were rejected by the frustum test (855 T each, 3–5% of a frame) and,
in level flight, up to 21 by the occlusion pre-test (about 5,000 T each, up
to 9% at street level, mostly its column-by-column cover check). So:
* `draw_bld` does the frustum test first, from the cell's centre alone
  (the walk's X, Z1, radius `BLD_R`), before reading its colour and height
  or setting up its corners: the same test on the same numbers.
* The occlusion cover buffer has a coarse partner, `OCC_YBUF8`: per 8
  columns, a bound at least the most of their 8 cover rows. `occ_hidden`
  passes a whole group at once when its bound is covered, and otherwise
  looks at its 8 columns one by one, so the answer is exactly the
  column-by-column one. When a kept building lowers the cover, groups
  wholly inside its columns take the new row as their bound if lower; the
  groups at its ends keep theirs (still a bound: cover only goes down).
  It sat in record 0's unused tail (`$42E0`); since records are two a page
  it has its own page (`$4200`).
* Over the ten views the frame time fell a further 1.3% (3.1–5.3% at street
  level): 5.0% in all against the first profile. Every view pixel-identical
  to the old build, and 24 more random views (48 frames) identical in
  lockstep with it, game state included.
* Tried and reverted (no gain, though pixel-identical): in level flight,
  top corners reusing their bottom's near/left/right outcode bits; skipping
  those bits for every corner of a building surely inside the near and side
  planes; and the occlusion pre-test patching each Z once (2 `zpatch`
  rather than 3). The shortcuts' own tests and bookkeeping cost about what
  they saved: an outcode's near/left/right part is only about 100 T, a
  `zpatch` about 200 T. Measured: 0.1–0.6% slower.
* Measured and not done: a per-frame cache of projected corners (only
  10–24 corners a frame have exactly the same numbers as their row
  neighbour's, out of 100–150, and the previous building's corners would
  have to be kept: about 0–1% at best) and walking a building's shared
  vertical edge once (about 0.5%: vertical edges already take the fast
  fill).

**Face drawing (2026-11-01):** a further 3.7% off the frame, 8.7% in all
against the first profile (ten views: 17,039,249 → 15,564,686 T).
* Exact (pixel-identical) changes, 2.7%:
  * The clipper copies vertices with `LDI`.
  * `div_frac` is unrolled 8 steps at a time (about 1,050 T rather than
    1,550).
  * `walk_edge` keeps a steep edge's accumulator in A and its step in E
    rather than IXL.
  * `lerp_c` was looked at and left alone (about 60 T an intersection).
* 2D clipping (`CLIP_2D`), 1.1% more, up to 4.3% in pitched views. The
  following faces are clipped on screen rather than in 3D (`clip2d`):
  * every face, when pitched;
  * in level flight, faces crossing two or more planes.

  In both cases a face that crosses the near plane, or has a corner outside
  the guard band |X| ≤ 2Z, |Y| ≤ Z, is still clipped in 3D.

  How the 2D clip works:
  * The off-screen corners are projected to 16-bit screen coordinates
    (`guard_proj`, `scomp16`).
  * `clip_poly` then runs with `clip_plane = $80`, so `plane_dist` and
    `clip_isect` work on x ≥ 0, x ≤ 255, y ≥ 0 and y ≤ 127. It runs only
    against the planes some corner is outside.
  * Each new point is exactly on the screen edge. One coordinate is worked
    out with one multiply, from the edge's inside end, so a shared edge is
    cut at the same point whichever way it runs. An edge parallel to the
    plane needs no divide.

  Level-flight faces crossing a single plane stay in 3D. There the
  vertical-edge shortcut makes them as cheap, with no off-screen corners to
  project.

  Results:
  * Not pixel-identical. The pitched views differ in 14–145 pixels (0.04–0.44%),
    all of them 1-pixel shifts along clipped edges.
  * A thin strip that the 3D clip broke into dashes is now drawn whole.
  * The level views are unchanged.
  * Identical with and without interrupts.
  * To make room in the city page:
    * clipA and the small variables sit in the two `ALIGN 256` gaps;
    * `clip_poly` swaps its own buffers;
    * four unused variables (`pj_x`, `pj_y`, `pj_sh`, `pj_r`) were removed.
  * About 10 bytes of the page were left. (Since then the DMA fill moved to the main page and part of the city code to a second page, `city2.asm`: see "Code pages".)

**City drawing (2026-11-03):** 15.5% off the frame over the ten views
(20,774,778 → 17,564,747 T): level flight 1,867K → 1,541K T a frame (15.0
→ 18.2 fps), pitched 2,422K → 2,079K (11.6 → 13.5 fps). Every view
pixel-identical to before, and each change also compared with the build
before it over 151 random views with the camera over a road (every level's
city): identical.
* **Street dots** (`draw_dots`, 13% of a frame before, 4–5% now): a dot is
  worked out only at a corner whose four cells are all open (road, or out of
  bounds). A corner a building, terrace or pad cell touches is always drawn
  over by it (its faces cover their own corners; the box hides those behind
  it): over the ten views all 551 such dots drawn were covered.
  * The four cells are read as two pairs, each shared with the next corner;
    away from the map's edges with two pointers and no bounds checks.
  * An open corner's (X, Z1) is its row's first corner's + k (cosY, sinY),
    k its column (`kmul`): exactly the old step-by-step sums. The row's
    first corner is rotated only if the row has an open corner.
  * In level flight the frustum cull skips its multiply (`cull_c` is
    exactly 1.0).
  * Compared with drawing every corner (the test switch `DOTS_ALL`) over 227
    random views: 55 differ, by 1–5 pixels, each a dot that peeked a pixel
    out from the foot of a building corner (the dot's and the building's
    corner are worked out differently).
* **Cell walk** (`draw_row`, `occ_row`): the cell's yaw-space centre (X, Z1)
  lives in the alternate registers HL', DE' for the whole walk (nothing else
  uses the alternate set: the interrupt routine must not either), stepped by
  (cosY, sinY) patched into the steps each frame (`walk_patch`); `draw_bld`
  reads it from there. `draw_cell` finds its map byte from the row's base
  (`row_base`, `cell_row`) rather than j × 64 + i. The occlusion walk gets
  to the camera column with one exact multiply (`walk_back`, `walk_fwd`)
  rather than up to 8 single steps.
* **Corners** (`VBOX`, `VBOX0`, zpolice.asm): the 8 corners a component at a
  time, the sums the corners share made once in registers; a component of
  the vertical edge that is 0 (X always, Z in level flight) copies the
  bottom corners to the top. The edge vectors are read from `vecs0` itself
  (no copy a building).
* **`div8`** (a sloped edge's x step): by reciprocal, q = (A × R) >> 16 with
  R = ⌈65536 / C⌉ (`rcp8`, gentables.py, which checks it exact for every A
  0–255 and C 2–127), and the remainder A − qC: about 180 T rather than 410.
* **Occlusion records** (`occ_record`): the corners copied by one 128-byte
  DMA transfer (`occ_dma`) rather than 72 `LDI`s, the DMA then put back as
  the spans need it.
* **`scale_comp`**: `zpatch` patches the barrel shift's count and its opcode
  (`BSRL` or `BSLA`, `OP_BSRL`, `OP_BSLA`), so the shift runs straight
  through (a right shift by 0 for a Z already normalised).
* Looked at and not used: the alternate registers in the span filler, the
  edge walker and the occlusion tests (an `EXX` costs more than the memory
  traffic it would save there), and reusing the buildings' projected
  corners for the dots (the roads aren't drawn as polygons, so no road
  corner is ever projected; the building corners that are, are exactly the
  dots the buildings cover).

## Tuning

Constants at the top of `zpolice.asm`: `VIEW_R` (the largest draw
distance; each level sets its own), `NEAR`,
`PMAX` (pitch limit, must match `gentables.py`), speeds and rates, the colours
(Layer 2 RRRGGGBB), `DMA_SPAN_MIN` and `BLD_SIZE`. `PMAX` is
kept at 24 (≈34°). At that limit no point behind the camera's horizontal
plane can ever be in view, which the culling relies on.

**Heights:** these are in height units, where 1.0 = 128 world units =
10 m. Buildings reach 7.0 (`BLD_MAX_H` = 896): `htab` scales the 15
height levels linearly up to it. The craft's ceiling is 1.5 (`MAX_Y` =
192), so the tallest towers can't be overflown. `gentables.py` emits an
`ASSERT` that its `BLD_MAX_H` matches `zpolice.asm`.

The city layout and heights come from `gentables.py` (seeded random). Every
8th row and column, and about 10% of other cells, are left empty as
one-cell-wide streets and plazas. Every other cell is a building filling the
cell. The outer rows and columns are a perimeter wall of maximum
height (level 15, 7.0) buildings, all in one colour family (`WALL_FAMILY` in
`gentables.py`). The wall is applied after the random layout, so the
interior cells and their colours are the same as without it.

**Rat runs:** after the layout, each 7×7 building block between the
boulevards may get a narrow street cut through it (its own seeded
generator, `rrng`):

| Kind | Chance | Shape |
|------|--------|-------|
| none | 35% | |
| straight | 25% | right across the block, east–west or north–south |
| L | 25% | in from the west or east side, turning to leave by the north or south side |
| crossroads | 15% | one run each way |

* **Position:** each run sits at a random row and column 2–6 into its
  block, not centred, so the streets look uneven. Never 1 or 7, so a run
  doesn't merge with a boulevard into a double-width road.
* **Ends:** runs open onto boulevards at both ends, except where they meet
  the perimeter wall, which closes them.
* **Settings:** the chances are `RAT_P` in `gentables.py`, and the
  generator prints the count of each kind when it runs.

The city is `GRID` × `GRID` (64 × 64) cells: `city_map` is 4K in the city
bank (page 7, `$7000`), loaded from the city's file. Downtown (taller
buildings near the centre) scales with the grid.
Code multiplies by a row with the `ROWOFS` macro and checks cells against
`GRID`.

Each grid cell also has a colour code in `city_col`, in the same order as
`city_map`, just before it in the city bank (`$6000`). Roads and open
cells hold `GROUND_COL`, and buildings hold a seeded random colour family.

**Palette:** Layer 2 uses a custom 9-bit palette, each city its own, loaded
with the level through NextRegs `$43/$40/$44`. It has 64 colour families of four
entries each:

| Entry | Use |
|-------|-----|
| `family*4 + 0` | darker side (`SHADE_DARK`) |
| `family*4 + 1` | side facing the player, the base colour (`SHADE_FACE`) |
| `family*4 + 2` | lighter roof (`SHADE_ROOF`) |
| `family*4 + 3` | fixed colours: sky 3, ground 7, edges 11, HUD 15, warning 19, ground dots 23; black otherwise |

A face's colour is therefore just `family | shade`, with no lookup table.
`gentables.py` derives the shades from a random base colour (dark ≈ 68%,
roof 35% towards white). It avoids any shade that would match the
transparent colour `$E3`, and emits `ASSERT`s that keep the fixed indices
in step with `zpolice.asm`.

## Regression tests

`tests/` holds the regression suite: Python scripts that run the built
`zpolice.nex` on the emulator (`tools/nexsim.py`) and check what it does.
`build.bat` runs them all after assembling (about 40 seconds; `notest`
skips them), and stops if one fails.

```
python tests/run_tests.py             # all of them, at the same time
python tests/run_tests.py render keys # only test_render.py and test_keys.py
python tests/test_figures.py          # one file
python tests/test_keys.py pause_quit  # one test in it
```

Each test prints PASS or FAIL, with a reason. Every test runs the game on
a temporary copy of `ZPDATA` (the SD card) with no `KEYS.ZPK` or
`SAVEGAME.ZPS`, so nothing is written to the repository and a file saved
by playing doesn't change the results.

| File | What it checks |
|------|----------------|
| `test_data.py` | every city map, level and level palette passes `tools/check_maps.py`; every figure and the figure colours pass the sprite editor's checks; `ZPDATA/SPRITES.ZPG` is up to date with `sprites/` |
| `test_render.py` | ten fixed views of level 1 (high, low, pitched up and down) are drawn byte for byte as the reference `tests/ref/render.ref`; prints each view's frame time against the reference's (reported, not a failure) |
| `test_interrupts.py` | 30 frames of flight drawn the same with no interrupts, with the 50 Hz interrupt, and under stress (an interrupt every ~2,000 T-states, and in the window before `push_end`'s DI with SP in Layer 2) |
| `test_figures.py` | `SPRITES.ZPG` is loaded into the graphics pages; a waiting human waves, and a running one is drawn from the front, the side (mirrored or not) or behind by the way it runs; without the file the game runs and draws no figures |
| `test_keys.py` | the default keys without `KEYS.ZPK`; a redefined key is saved on leaving the redefine screen and loaded at the next start; a file of the wrong version is ignored; X on the pause screen returns to the menu without saving |
| `test_save.py` | CONTINUE without a save game stays on the menu; S on the pause screen saves, and CONTINUE brings back the level, weapons, stock, hit points, salvage and booster |
| `test_levels.py` | every `ZPDATA/LEVELnn.ZPL` starts and flies a few frames (the levels at the same time, a process each) |
| `test_flight.py` | flying into a building stops the VTOL, costs hit points, shakes the screen and requests the crunch |
| `test_linked.py` | each linked chain gun fits only its own slot; with both fitted, selecting either fires both, from 26 units (2 m) either side, with both crosshairs; each has 200 rounds, a round off each a frame, and with L empty R fires alone; one alone fires one, with its crosshair; the centre slot keeps the centre crosshair |
| `test_landing.py` | landed, Q and A can't speed it up or reverse it; a speed it sets down with is braked to 0, with a shake; Q from reverse stops at 0; in the air Q speeds up as before; strafing moves 2.5 units sideways a frame while held in the air and none while landed, and K undoes L; no strafe without the lateral thrusters |
| `test_vision.py` | each level's vision palettes load; N steps through the modes the VTOL has (all three, or thermal only), each one's palette swapped in, and does nothing with none; in a vision mode a human is drawn from the vision set |
| `test_humans.py` | a waiting human stands while the VTOL is far off and waves when it's near; on the road it flees a monster along the road, taking the open way when one is blocked; on a roof it never flees |

**When the picture is meant to change** (the renderer, the figures, level
1's city or palette), `test_render.py` fails until the reference is saved
again. Check the new views first (for example with `tools/preview.py` or
the PNGs from `tools/nexsim.py`), then:

```
python tests/test_render.py --save
```

**Adding a test:** a function `test_NAME()` in a `tests/test_*.py` file,
ending with `zp.main(globals())` under `if __name__ == "__main__":`. The
helpers are in `tests/zptest.py`: `SD()` (the temporary SD card),
`machine()`, `start_game()` (through the menu and loadout to `main_loop`,
any level), `frames()`, `set_camera()`, `run_until()`, `check()`, `note()`,
and `sym` (`zpolice.sym`). `run_tests.py` finds new files itself.

## Testing headless

The game starts at the main menu, so a flight script has to press 1 first:
for example `"0:1,1:,4:Q"`.

```
python tools/nexsim.py zpolice.nex out 60 "0:QT,20:F,35:TE,50:"
```

This runs 60 frames, holding Q+T from frame 0, F from frame 20, then T+E,
then nothing. Each frame is written to `out/fNNN.png` along with its T-state
count. Set `PROFILE=zpolice.sym` (after building with `--sym`) for a
per-routine breakdown.
