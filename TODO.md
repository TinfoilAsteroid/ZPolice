# Z-Police TODO

## Before a release

- Set `DEBUG_KILLALL equ 0` in `zpolice.asm`: it takes out the debug keys
  (0: kill all, 9: next city). See README "Controls".

## Done 2026-10-27: level configuration files and pre-built city maps

See README "Levels and cities". Left for later:

- (Done: the zombie, wave, fast-zombie and special-monster counts are used,
  and levels move on after LEVEL COMPLETE. See README "Waves and level
  progress".)
- (Done: after level 50, CONGRATULATIONS, GAME OVER, the main menu.)
- More in the level complete (to come).
- Hand-made level files: map changes, different draw distances for night
  or fog.
- A visible sky (`SKY_IS_WALL` off) to show each city's sky colour.

## Ghosts (done 2026-10-27): open points

- (Done 2026-10-28: the VTOL's hit points are shown on the HUD as
  INTEGRITY, a percentage. At 0 it spins down, then GAME OVER: done.)
- Ghosts are placed at the level's start only; they don't respawn.
- (Done: the banshee, special type `ZT_BANSHEE`, spawned on even waves.)
  `LV_SPECIAL_MAX` is still not used: banshees follow the wave rule, not
  the level file.

## (Original notes, kept for reference)

**Level configuration files, with pre-built city maps.**

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
