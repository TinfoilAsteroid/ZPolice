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

- Save the key and joystick definitions to the SD card and load them at
  start-up.
- Quit without saving from the pause screen (S already saves and quits).
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

- AY sound effects for monster attacks, rescues and alarms (weapons and
  explosions are done: see DONE.md).
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

### Testing and release

- Turn the scratchpad emulator tests into a regression suite in the
  repository (`tests/`), run from build.bat.
- A release build switch that turns off `DEBUG_KILLALL` and the other test
  settings.
- Packaging: a distribution folder for the .nex file and ZPDATA, plus a
  short manual.

Completed items are in DONE.md.

## Open points from the level files (2026-10-27)

- More in the level complete (to come).
- A visible sky (`SKY_IS_WALL` off) to show each city's sky colour (also
  under Graphics).
