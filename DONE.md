# Z-Police DONE

Completed items moved from TODO.md, under the same headings.

## Graphics

- (Done 2026-11-06: `build.bat release`: a release build with the debug
  settings off, in a `release/` folder that runs as it stands, with a
  short manual, `docs/MANUAL.txt`. See README, "Building and running".)
- (Done 2026-11-06: a HUD sprite editor, `tools/hud_sprite_editor.py`, for the
  16x16 hardware sprites, now in `sprites/hud.json`. See README, "HUD sprites
  and their editor".)
- (Done 2026-11-04: a fancier HUD. The weapon slots show their ammo down a
  bar, hundreds at the top (INF for infinite, red at 000), their slot number
  above it if used; trim round the gauges, the weapon slots and the panel's
  sections; a viewport frame with curved corners, in hardware sprites. See
  README, the HUD sections.)

- (Done 2026-11-02: a sprite editor for the humans and monsters
  (tools/sprite_editor.py), their graphics as JSON (sprites/), 32 colours of
  their own in every palette (entries 192-223), purposes (zombie walking
  front / side / rear, ghoul the same, ghost and banshee floating, human
  waving and running), levels of detail by distance (each with its size
  and nearest Z), built by gengraphics.py into ZPDATA/SPRITES.ZPG and
  loaded by the game at start-up. Humans running to the VTOL now run
  (front, side or rear by their way), not wave. Distant figures use their
  smaller levels. See README "Figures and the sprite editor".)

## Controls and input

- (Done 2026-11-02: the key and joystick definitions are saved to the SD
  card (ZPDATA/KEYS.ZPK) when leaving the redefine keys screen after a
  change, and loaded at start-up if the file fits this game. See README
  "Input".)
- (Done 2026-11-02: quit without saving from the pause screen, X: QUIT, NO
  SAVE. See README "Save games".)

- (Done 2026-10-30: joystick support. Kempston 1/2, Mega Drive 1/2 with
  3 or 6 buttons; each control has a key and a joystick input, both
  redefinable. keys.asm is now input.asm. See README "Input".)
- (Done 2026-10-30: a pause control, BREAK or Mega Drive START by
  default, with a PAUSED box over the view.) (Done 2026-11-01: S while
  paused saves and quits to the main menu; CONTINUE on the main menu. See
  README "Save games".)

## Sound

- (Done 2026-10-30: the VTOL's jet engine sound on AY 1: a roar, a whine
  and a shimmer, pitch and volume rising with speed, idling at zero
  throttle. See README "Engine sound". Since: played by the interrupt
  routine, spooling up and down smoothly; interrupts are now on.)
- (Done 2026-10-30: the sound effect player on AY 2, the machine gun, the
  chain gun, the laser, rockets, missiles and the autocannon / proximity
  cannon, explosions on AY 3 sized to each blast, and a splat when a
  zombie is hit. See README "Sound effects".)

## Gameplay

- (Done 2026-11-04: zombie clusters. CLUSTERS n on a wave's line in a level
  file spawns its zombies in n clusters: n parents at random, the rest in
  turn within 2 tiles of each, on streets. On trial on levels 2 and 4, with
  40 zombies and 4 clusters; and 4 clusters on the middle wave of every 3rd
  level. See README "Waves and level progress".)

- (Done 2026-11-04: the boss, a lich: a skeleton in a crown, twice a
  zombie's height, in the last wave of each city's last level. It walks the
  streets at 4 times a zombie's speed, its map blip flashing red, with 50
  hit points + 25 a city. Fireballs at where the VTOL will be (200 m/s),
  +/-1.5 degrees, within 200 m, every 60 frames, 10 fewer a city, to 10; they
  burst at a building, the ground, the VTOL or after 200 m, for 10 within
  5 m to the VTOL, humans and the base, not monsters. See README "Special
  monsters".)

- (Done 2026-11-03: the linked chain guns. Linked Chain Gun L (salvage 50,
  was a chain gun) fits only slot 4, just left of slot 1 on the HUD;
  Linked Chain Gun R (salvage 55, was a proximity cannon) only slot 5.
  Chain gun stats, firing straight ahead from 2 m to their side, 200 rounds each; either
  selected fires both. A crosshair for each fitted, 8 pixels either side
  of the centre. The proximity cannon moved to 75 (was a chain gun); the
  chain gun at 95 removed. Save game version 5. See README "Linked chain
  guns".)

- (Done 2026-11-03: the lateral thrusters, a salvage reward at 90 in place
  of a pulse laser (and 65 is now night vision, monochrome only). K / L,
  new redefinable controls, strafe sideways while held, 2.5 units (about
  0.2 m) a frame, not while landed; the booster can't start while
  landed either. The redefine keys screen scrolls (23 controls); KEYS.ZPK
  is version 3, the save game version 4. See README "Controls".)
- (Done 2026-11-03: the human status sprites on the left of the HUD moved
  up, the middle one at row 128, 16 pixels apart as before.)

- (Done 2026-11-03: landing. Resting on the road, a roof or the pad, the
  VTOL brakes any speed to 0 as the air brake does, with a shake, and the
  speed keys only bring it back to 0 (no speeding up or reversing there).
  See README "Landing and rescuing humans".)
- (Done 2026-11-03: the bomb, `WPN_BOMB`, a salvage reward at 40 in place
  of a pulse laser. One a pod, released at the VTOL's speed + 20, gliding
  down from 10°, a step (1.4°) steeper every 5 frames; drawn as a white
  streak 2 pixels wide; its blast does 30 to everything within 2 tiles on
  each axis, the VTOL included, with 30 particles. Each frame's drop of a
  round is now rounded, not truncated. Tried in play. See README "Bomb".)
- (Done 2026-11-03, built and tested in the emulator: the vision modes. N (the new
  control `K_VISION`) steps through the night vision green, monochrome and
  thermal modes the VTOL has, then back to normal, swapping in the level's
  palette for each: 4 per level in `ZPDATA/LEVELnn.ZPV`, generated by
  gentables.py (`tools/visionpal.py`), hand-tunable as
  `levels/LEVELnn_NVG.json` and so on. The figures are drawn from a vision
  set made by gengraphics.py (face, core and outline roles), so a thermal
  human has a white face, yellow core and orange outline. KEYS.ZPK is now
  version 2 (21 controls). See README "Vision modes".)
- (Done 2026-11-03: the booster module tested: the salvage reward at 45,
  fitted, its fuel, the boost, the HUD fuel gauge, saved and loaded.)
- (Done 2026-11-02: unloading a weapon on the load-out screen. U empties
  the selected slot, its weapon back into the store. See README, the
  load-out screen under "Waves and level progress".)
- (Done 2026-11-02: guided missiles. With the missile pod selected, a
  square reticule wanders within 40 pixels of the view's centre until a
  monster is seen within 8 tiles, then moves to it and locks after 2
  seconds on it (a double beep; yellow searching, flashing red locking,
  red locked). A missile fires only with a lock, leaves straight ahead and
  turns towards its target at 3 degrees a frame, flying straight on once
  the target is more than 8 tiles away or dead. Settings: `LOCK_RANGE`,
  `LOCK_TIME`, `MISSILE_TURN`, `RET_*` in zpolice.asm.)
- (Done 2026-11-02: human behaviour. Waiting humans stand, and wave while
  the VTOL is within 80 m. On the road they flee the nearest monster
  within 20 m, along the road in a random way away from it; on a roof
  they never flee. A new figure purpose, the human's `stand`. See README
  "Landing and rescuing humans".)
- (Done 2026-11-01: hand-edited level files, `levels/LEVELnn.TXL`: map
  changes, draw distances, waves and specials. See README "Hand-edited
  levels".)

## Performance

- (Done 2026-11-09: occlusion in pitched views, `OCC_PITCHED` (zpolice.asm),
  up to `OCC_PMAX` (18). Measured first (TODO "Front to back"): in pitched
  views, which had no occlusion, buildings that end up wholly overdrawn
  took 15-56% of the frame. The cover rule holds pitched except that a
  building's vertical edges lean on screen, so it now covers only the
  columns of both its top and bottom corners; occ_pretest has bounds of
  its own when pitched (Z and Y from the cell centre over the building's
  height and circle, a margin for rounding). Over 124 random pitched views:
  pixel-identical, frame time -7.7%, median frame 14.9 -> 16.7 fps (by view
  -45% to +18%; past pitch 18 it lost, so it's off there). test_render.py's
  test_pitched_occlusion checks 16 views against the painter's path. See
  README "When it runs".)

- (Done 2026-11-09: fewer cells reaching the transform, all three
  pixel-identical, 2.8% off the frame in all (1,750,943 -> 1,701,843 T a
  frame over the 10 render-test views). Before: the walk tried all 289
  cells of the 17x17 square every frame, 69% of them out of view, and
  occ_pretest was 2,828 T a call.
  - A leaner occ_pretest (city2.asm), 0.5%: the near Z normalised once
    (oz_norm), the far Z the first time it's needed (oz_far), the
    components by oz_sc / oz_sx (vproj's VP_SCALE), no zpatch or
    scale_comp: 2,828 -> 2,504 T a call. The old occ_sx called zpatch
    with A = X's high byte, so for X 0-255 and Z < 256 it took Z as 1 (a
    bound at the screen's edge: safe, but fewer rejections); oz_norm
    always uses Z.
  - The walk's own cull (WALK_TRY, zpolice.asm), 1.25%: draw_row and
    occ_row skip try_cell for a cell whose centre is surely out of view,
    from the walk's registers (level |X| - Z1 >= WALK_R, 320; pitched
    Z1 < -WALK_R). Every cell still stepped. try_cell calls 2,822 -> 1,207.
    320 rather than BLD_R's 256 for figures at a street cell's edge: over
    2,816 figures drawn by zombies at the view's edges, the furthest
    cell was at 141. 280 level and 80 pitched views with zombies at the
    edges are the same with it off (WALK_R 12000).
  - Whole rows skipped (row_cull, city.asm), 1.1%: row_skip, worked out
    once a frame (9,300 T) from the rows' end cells against the left,
    right and behind edges (they're linear along a row), with a margin
    (ROW_M) for rounding; it skips exactly the 39 rows of 170 with no
    cell in view, and their row_start calls with them (340 -> 262).)

- (Done 2026-11-09: a leaner projection for building corners, `vproj` and
  `vproj_y` (city.asm), pixel-identical: the same arithmetic as
  `vtx_proj` / `project` / `zpatch` / `scale_comp`, step for step, in one
  routine, with Z's shift chosen by a branch rather than patched in, X and
  Y made positive and shifted as they're read, the reciprocal kept in BC
  for both, the rounding added first so the 17-bit sum's top bit is the
  carry, and no calls, push / pop or self-patching. Measured in the
  emulator over one frame of each of the 10 render-test views:
  - A corner's projection 1,096 T -> 703 T (-36%), 944 of them over the
    10 frames.
  - The level-flight shortcut (screen y only) 311 T -> 462 T, 198 calls:
    it used to share `scale_comp`'s patched reciprocal with the corner
    below; it now works out Z's shift and reciprocal again (cheaper than
    saving them on every corner).
  - The frame 1,786,178 T -> 1,750,943 T (-2.0%), about +0.3 fps at 16.
  - tests/test_project.py checks 4,064 corners (every shift of Z and the
    frustum's edges) give the same screen x and y as before.)

- (Done 2026-11-03: city drawing 15.5% faster over the ten reference views,
  pixel-identical (level flight 15.0 → 18.2 fps, pitched 11.6 → 13.5): the
  street dots only at corners whose four cells are all road (a building's
  corners are always covered by it), the cell walk's place in the
  alternate registers, the corners' shared sums made once, `div8` by
  reciprocal, the occlusion records copied by DMA, and `scale_comp`'s shift
  patched by `zpatch`. See README "City drawing (2026-11-03)".)
- (Done 2026-11-01: the span loop's per-row overhead trimmed, no
  multiplies by the pitch in level flight, vertical edges walked as a
  fill: 3.7% off the frame time, 4.9-6.5% in level flight. See README
  "Performance".)
- (Done 2026-11-01: rejected buildings made cheaper: the frustum test
  first in draw_bld, and a coarse cover buffer for the occlusion test.
  5.0% off the frame in all, 3-9% at street level. See README
  "Performance".)
- (Done 2026-11-09: No real benefit in testing. A cache of building
  corners by grid point, `GRID_CACHE`, built, measured and removed: each
  grid point's outcode and screen x, y, kept for the frame (top corners by
  their height too) in 256 slots, i + 16 j, and reused by the neighbouring
  buildings. Measured in the emulator over the 10 render-test views:
  - It found what was expected: 352 of 1,554 outcodes (23%) and 272 of
    1,142 projections, ~355,000 T of work saved.
  - But its lookups and stores cost ~460,000 T, ~300 T a corner (every
    corner looked up, every miss kept), so the frame was 0.8% slower
    (1,750,943 -> 1,765,598 T a frame). Even with free lookups, keeping
    every miss would leave under 1%.
  - Not pixel-identical either: the same grid point comes out a unit
    apart in camera space from two neighbours in 46% of repeats (each
    building's corners are made from its own walked centre), and 15
    corners a pixel apart, so views 4, 5 and 9 changed (6-152 bytes).
  The code was deleted.)
- (Measured 2026-11-01, not worth doing: a per-frame cache of projected
  corners, about 0-1% (only 10-24 corners a frame match their row
  neighbour's exactly, and the corners would have to be kept between
  buildings); walking a building's shared vertical edge once, about
  0.5%. See README "Performance".)
- (Tried 2026-11-01, no gain, reverted: in level flight, a top corner
  taking its bottom's near/left/right outcode bits and only the top /
  bottom test; skipping those bits for every corner of a building surely
  inside the near and side planes; and the occlusion pre-test patching
  each Z once (2 zpatch, not 3). All pixel-identical, but the shortcut's
  own tests and bookkeeping cost about what they saved (an outcode's
  near/left/right part is only ~100 T; a zpatch ~200 T): 0.1-0.6%
  slower. See README "Performance".)
- (Done 2026-11-01: faster face drawing: LDI vertex copies, a faster
  divide and a tighter steep-edge walk, all pixel-identical; plus 2D
  (guard-band) clipping of pitched faces and of multi-plane faces in
  level flight, which moves some clipped edges by a pixel. 8.7% off the
  frame in all. The city page then had only about 10 bytes free (since split: city2.asm). See
  README "Performance".)

## Testing

- (Done 2026-11-02: a regression suite in `tests/`, run by build.bat after
  assembling (`notest` skips it): the source data's checks, the renderer
  against reference views, drawing under interrupts, the figures, the key
  definitions, the save game, every level, and crashing into a building.
  See README "Regression tests".)

## Map editor and tools

- (Done 2026-11-03, its code checked: the map editor shows the four palettes
  side by side (normal, night vision green, night vision mono, thermal);
  clicking one's title shows the map in it and edits it. In level mode each
  vision palette has Copy normal, Convert to green / grey / thermal (blues,
  warmer roofs) and Generated, and Save writes `levels/LEVELnn_NVG.json`,
  `_NVM.json`, `_THM.json`. See the editor's notes at the top of
  tools/map_editor.py.)

- (Done 2026-11-01: in the map editor, editing a level's map changes, fill,
  line, box, rectangle, select with copy / paste and mirroring, a "wall
  round out of bounds" helper, level settings, a colour family editor, and
  a preview of the city from a point (tools/preview.py); a check of every
  map and level from the command line (tools/check_maps.py). See README
  "City maps and the map editor".)

## Done 2026-10-27: level configuration files and pre-built city maps

See README "Levels and cities".

- (Done: the zombie, wave, fast-zombie and special-monster counts are used,
  and levels move on after LEVEL COMPLETE. See README "Waves and level
  progress".)
- (Done: after level 50, CONGRATULATIONS, GAME OVER, the main menu.)
- (Done 2026-11-01: hand-made level files, `levels/LEVELnn.TXL`.)

## Ghosts (done 2026-10-27)

- (Done 2026-10-28: the VTOL's hit points are shown on the HUD as
  INTEGRITY, a percentage. At 0 it spins down, then GAME OVER: done.)
- (Done: the banshee, special type `ZT_BANSHEE`.)
- (Done 2026-11-01: specials per wave from the level file, up to 5 types
  and counts a wave, wave 1 the level's start; `LV_SPECIAL_MAX` replaced
  by the types. See README "Special monsters".)

## (Original notes, kept for reference)

**Level configuration files, with pre-built city maps.** (Done 2026-10-27:
see "Done 2026-10-27: level configuration files and pre-built city maps"
above, and README "Levels and cities". Each city is built by gentables.py
into ZPDATA/CITYnn.ZPC, from maps/CITYnn.json, and loaded into the city bank
at each level's start; city_map.asm now holds only the shared constants.)

- Create a configuration file per level, loaded from the SD card with
  `file_handler.asm` (`fh_load`). Each file holds:
  - that level's level table data: the `levels.asm` fields (level number,
    8-character city name, number of zombies, waves, fast zombies, special
    monsters and the highest special monster id);
  - its city map.
- Pre-build each city map (`gentables.py` generates `city_map.asm` today) so
  it can be loaded into a bank of memory instead of being hard-coded in the
  resident page.

Points to settle when we start:

- **File format:** a header with the level table entry, then the 64 × 64 map,
  plus whatever goes with the map. For example the base and pad constants
  (`PAD_X`, `PAD_Z`, `BASE_YAW`), the per-cell colours (`city_col`) and the
  map's Layer 2 picture.
- **Where the loaded map lives:** `city_map` is read from slots 1, 3, 5, 6
  and 7, including the weapons page in slot 6 (see the earlier analysis). So
  a loaded map must sit in an always-mapped place, or the code that reads it
  must change.
- **Build tools:** `gentables.py` (or a new tool) writes one file per level.
- **Start-up:** load level 1's file into its bank before `newGame`, and the
  next level's file at each level change.
- **Constants:** today `gentables.py` emits the map constants as assembler
  equates. They would become data read from the file.

**Done 2026-10-27: zombie and human flags in the city map bytes.** (Kept
here for reference; see README "City map bytes".)

Loading the level's map at the start of each level also resets every cell,
before the zombies, special monsters and humans are placed. So the flags
below always start clear, and the map files are stored with bits 5–7 clear.

| Bits | Meaning |
|---|---|
| 0–4 | cell code: 0 road, 1–15 building height, 16 pad, 17 terrace (as now) |
| 5 | free (later: salvage, pickups, etc.) |
| 6 | a human is in this cell |
| 7 | a zombie or special monster is in this cell; its type comes from its record in the zombie table |

- **Memory:** removes `zcell` (4,096 bytes) and `znext` (20 bytes) from the
  zombie page, and `hum_bits` (512 bytes) from page 7: about 4.6K saved.
- **Speed:** the drawing tests bits 6 and 7 of the map byte it already has,
  instead of a `zcell` lookup plus a `hum_here` call per cell (about 1% of a
  frame saved). Only when a bit is set is the zombie or human list scanned
  for who is there (20 entries at most).
- **Updating:** each frame `zombie_update` clears bit 7 at each zombie's old
  cell and sets it at its new one (correct even with two zombies in one
  cell). Humans set bit 6 when placed, and clear or move it when they run,
  board or die.
- **The risk to cover:** every reader of a map byte must mask with `and $1F`
  first. About 30 places read map bytes, many testing "0 = road" with
  `or a`: the city traversal and occlusion list, collision and `floor_y`,
  zombie walking and junctions, weapons hits, human placement, the HUD map
  and the GRN gauge. Writes must keep the flags (e.g. a destroyed terrace
  tile clears only bits 0–4). Check with the pixel-identical render
  comparisons and the movement, weapons and siege tests.
