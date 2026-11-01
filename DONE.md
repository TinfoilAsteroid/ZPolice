# Z-Police DONE

Completed items moved from TODO.md, under the same headings.

## Controls and input

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
  chain gun, the laser, rockets, missiles and the Bofors / proximity
  cannon, explosions on AY 3 sized to each blast, and a splat when a
  zombie is hit. See README "Sound effects".)

## Gameplay

- (Done 2026-11-01: hand-edited level files, `levels/LEVELnn.TXL`: map
  changes, draw distances, waves and specials. See README "Hand-edited
  levels".)

## Performance

- (Done 2026-11-01: the span loop's per-row overhead trimmed, no
  multiplies by the pitch in level flight, vertical edges walked as a
  fill: 3.7% off the frame time, 4.9-6.5% in level flight. See README
  "Performance".)
- (Done 2026-11-01: rejected buildings made cheaper: the frustum test
  first in draw_bld, and a coarse cover buffer for the occlusion test.
  5.0% off the frame in all, 3-9% at street level. See README
  "Performance".)
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
  frame in all. The city page now has only about 10 bytes free. See
  README "Performance".)

## Map editor and tools

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
