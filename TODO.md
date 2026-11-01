# Z-Police TODO

## Before a release

- Set `DEBUG_KILLALL equ 0` in `zpolice.asm`: it takes out the debug keys
  (0: kill all, 9: next city, 8: change the centre gun). See README
  "Controls".
- Set `DEBUG_LOADOUT equ 0` in `zpolice.asm`: a new game would otherwise
  start with 4 of every weapon in store.

## Suggested features, enhancements and optimisations (2026-10-30, to review)

Items marked "(also below)" repeat an open point further down this file.

### Controls and input

- (Done 2026-10-30: joystick support. Kempston 1/2, Mega Drive 1/2 with
  3 or 6 buttons; each control has a key and a joystick input, both
  redefinable. keys.asm is now input.asm. See README "Input".)
- Save the key and joystick definitions to the SD card and load them at
  start-up.
- (Done 2026-10-30: a pause control, BREAK or Mega Drive START by
  default, with a PAUSED box over the view.) (Done 2026-11-01: S while
  paused saves and quits to the main menu; CONTINUE on the main menu. See
  README "Save games".) Still to do: quit without saving.
- Optional mouse aiming for the centre gun.

### Graphics

- Better monster graphics: more animation frames, a death animation,
  distinct ghoul, ghost and banshee art, and perhaps hardware sprites for
  close monsters.
- Better menu graphics: a Layer 2 title picture or logo, animated
  backgrounds, consistent fonts and panels for the load-out and redefine
  screens.
- Better human graphics, including boarding and leaving animations.
- Add run animation for humans boarding so they run without waving their arms
- A visible sky (`SKY_IS_WALL` off), with each city's sky colour and perhaps
  a skyline or clouds (also below).
- VTOL effects: a damage smoke trail, a landing-pad beacon and rotor or jet
  wash.
- Explosion polish: screen shake, a flash and debris on hits to buildings.
- Night and fog cities: a darker palette, searchlights and a limited draw
  distance (the per-level draw distance already exists).
- HUD polish: weapon icons in place of letters, an ammo bar per slot, and a
  warning flash at low integrity.

### Sound

- (Done 2026-10-30: the VTOL's jet engine sound on AY 1: a roar, a whine
  and a shimmer, pitch and volume rising with speed, idling at zero
  throttle. See README "Engine sound". Since: played by the interrupt
  routine, spooling up and down smoothly; interrupts are now on.)
- AY sound effects for each weapon, explosions, monster attacks, rescues and
  alarms. (Done 2026-10-30: the sound effect player on AY 2, the machine
  gun, the chain gun, the laser, rockets, missiles and the Bofors /
  proximity cannon, explosions on AY 3 sized to each blast, and a splat
  when a zombie is hit. See README "Sound effects".)
- Title and in-game music using the Next's three AY chips (TurboSound).
- Spatial cues: a monster's attack louder when close, and a
  base-under-attack alarm.

### Gameplay

- Use the bomb weapon type (`WPN_BOMB` is defined but not used).
- An "EMPTY" option on the load-out screen to remove a weapon.
- Ghosts respawning during a level, not only at the start (also below).
- New monster types, or a boss every 10 levels.
- Add super zombie, big and bulky as wide has 20 hit points.
- At the end of each city will be a boss monster/wave
- Barricade gameplay: rebuild or place barricades, or repair them at the
  pad, using salvage.
- Salvage points can be used to repair barriers. Before moving to VTOL load out page
  salvage points can be used at 1 point to generate a pool of 25 hit points.On the repair screen a mini map will be displayed and the damage status listed for each barrier and terrace as a simple list.
  When the player navigates down the list the barrier or terrace will highlight red.
  Pressing 0 applies 5 repair points from the pool each time it is pressed to the highlighted location. Any unspent repair points are carried between levels.
- More uses for salvage: armour, fuel, a faster reload, a bigger passenger
  cabin.
- Vision modules, unlocked by salvage (as the booster module): thermal and
  high vision, with a key to cycle through the views (normal, thermal,
  high vision; only the ones unlocked). This changes how the colour palette
  switches: today each level loads its city's one Layer 2 palette (with its
  time-of-day tint); each view would need its own palette for the city
  (e.g. thermal: buildings dark, zombies, humans and ghosts bright), made by
  gentables.py and swapped in when the view changes, with the fixed colours
  (HUD, blips, particles) kept the same in every one.
- A score, a high-score table saved to SD, and a results screen per level
  (time, kills, humans lost).
- Difficulty settings: easy, normal, hard.
- (Done 2026-11-01: hand-edited level files, `levels/LEVELnn.TXL`: map
  changes, draw distances, waves and specials. See README "Hand-edited
  levels".)
- Level objectives beyond "clear all waves", such as escort, defend the base
  for N minutes, or rescue a VIP.
- Human behaviour: humans flee from nearby zombies and wave when the VTOL is
  close.

### Performance

- Speed up building rendering, which runs at about 14-18 fps in busy views.
  Profile (2026-11-01): transforming and projecting corners ~29% of a
  frame, filling spans ~19% (per-row overhead ~10%), walking edges ~8.5%,
  clipping ~7%, occlusion ~6%. Every change to be checked pixel-identical
  against the frames before it (the same views rendered with the old and
  new builds, Layer 2 compared byte for byte).
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
  - Still to look at, if anything: scale_comp itself (3-4% of a frame in
    corner projections), and occ_record (5-11% in level flight).
  - Measure overdraw (writes per pixel, in the emulator). If it's high,
    draw front to back, keeping per screen column how far down it is
    already filled (for boxes standing on flat ground, the same picture as
    the painter's order). A big rewrite: only if overdraw justifies it.
  - Not to do: keeping SP borrowed for a whole polygon (saves the per-span
    SP restore and DI / EI, ~3%) would hold interrupts off long enough to
    miss some (the engines' sound); and clamping x instead of clipping the
    left / right planes needs proof the spans come out the same.
- Draw distant monsters with fewer pixels or as simple blips.
- Faster occlusion when facing the wall (the one view where occlusion is
  slower).
- Spread zombie path decisions over more frames when waves are large.
- Faster loading with a single combined city-and-level file.

### Map editor and tools

- (Done 2026-11-01: in the map editor, editing a level's map changes, fill,
  line, box, rectangle, select with copy / paste and mirroring, a "wall
  round out of bounds" helper, level settings, a colour family editor, and
  a preview of the city from a point (tools/preview.py); a check of every
  map and level from the command line (tools/check_maps.py). See README
  "City maps and the map editor".)

### Testing and release

- Turn the scratchpad emulator tests into a regression suite in the
  repository (`tests/`), run from build.bat.
- A release build switch that turns off `DEBUG_KILLALL` and the other test
  settings.
- Packaging: a distribution folder for the .nex file and ZPDATA, plus a
  short manual.


## Done 2026-10-27: level configuration files and pre-built city maps

See README "Levels and cities". Left for later:

- (Done: the zombie, wave, fast-zombie and special-monster counts are used,
  and levels move on after LEVEL COMPLETE. See README "Waves and level
  progress".)
- (Done: after level 50, CONGRATULATIONS, GAME OVER, the main menu.)
- More in the level complete (to come).
- (Done 2026-11-01: hand-made level files, `levels/LEVELnn.TXL`.)
- A visible sky (`SKY_IS_WALL` off) to show each city's sky colour.

## Ghosts (done 2026-10-27): open points

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
