# Z-Police TODO

## Today (2026-11-03)

- Vision modes (built and tested in the emulator: the rest is in DONE.md):
  - Check the colours in CSpect in each mode, in play.
  - The panel's city map changes colour with the mode (it draws cells in
    their building colours): keep it, or give the map its own colours.
  - The terrace round the pad is magenta in thermal (its top counts as a
    roof): keep it, or keep the terrace and pad families cold.
  - Try the map editor's palettes by hand (its code is checked, not its
    window): Edit colours on a vision palette, Save in level mode.

## Before a release

- `build.bat release` turns off the debug settings and makes `release/`: see
  README "Building and running".

## Suggested features, enhancements and optimisations (2026-10-30, to review)

Items marked "(also below)" repeat an open point further down this file.

### Controls and input

- Optional mouse aiming for the centre gun.

### Graphics

- Draw the figures' real art in the sprite editor (tools/sprite_editor.py):
  they are still the original stick men, coloured, at 4 levels of detail
  (16, 12, 8, 4 rows). Larger levels for close figures (up to 64x64).
- Better monster graphics: more animation frames, a death animation (a new
  purpose: spritefile.FIGURES and the game's chooser), distinct ghoul,
  ghost and banshee art, and perhaps hardware sprites for close monsters.
- Better menu graphics: a Layer 2 title picture or logo, animated
  backgrounds, consistent fonts and panels for the load-out and redefine
  screens.
- Better human graphics, including boarding and leaving animations.
- A visible sky (`SKY_IS_WALL` off), with each city's sky colour and perhaps
  a skyline or clouds (also below).
- VTOL effects: a damage smoke trail, a landing-pad beacon and rotor or jet
  wash.
- Explosion polish: screen shake, a flash and debris on hits to buildings.
- Night and fog cities: a darker palette, searchlights and a limited draw
  distance (the per-level draw distance already exists).
- HUD polish: weapon icons in place of letters, an ammo bar per slot, and a
  warning flash at low integrity.
- Screens outside the game in Layer 2 320x256: see "Screens in Layer 2
  320x256" below.

### Sound

- AY sound effects for monster attacks, rescues and alarms (weapons and
  explosions are done: see DONE.md).
- Title and in-game music using the Next's three AY chips (TurboSound).
- Spatial cues: a monster's attack louder when close, and a
  base-under-attack alarm.

### Gameplay
- Missile lock, add a key to cycle through targets near by to select a different target
- Add aim assist to twn linked chain guns
- Salvage point change - 1 point per human not killed, 2 points per human rescuded, -5 per killed human: never goes below 0 or removes unlocks, or reactivates locks of player saves more
- Review the levels and waves: there seem to be a lot of zombies early in the
  game. Zombies could also be weaker at the start, while the player hasn't
  unlocked weapons yet.
- Ghosts respawning during a level, not only at the start (also below).
- New monster types, or a boss every 10 levels.
- Add super zombie, big and bulky as wide has 20 hit points.
- At the final city we want something like an entrance to hell where the zombies come from
  this will be represented by a large road section as a circle, a boss monster will spawn in the road and attempt to destroy the landing pad
- Barricade gameplay: rebuild or place barricades, or repair them at the
  pad, using salvage.
- When a weapon slot's ammo runs out, flash its 000 (it shows red now)
- Salvage points can be used to repair barriers. Before moving to VTOL load out page
  salvage points can be used at 1 point to generate a pool of 25 hit points.On the repair screen a mini map will be displayed and the damage status listed for each barrier and terrace as a simple list.
  When the player navigates down the list the barrier or terrace will highlight red.
  Pressing 0 applies 5 repair points from the pool each time it is pressed to the highlighted location. Any unspent repair points are carried between levels.
- More uses for salvage: armour, fuel, a faster reload, a bigger passenger
  cabin.
- A score, a high-score table saved to SD, and a results screen per level
  (time, kills, humans lost).
- Difficulty settings: easy, normal, hard.
- Level objectives beyond "clear all waves", such as escort, defend the base
  for N minutes, or rescue a VIP.

### Performance

- Speed up building rendering, which runs at about 14-18 fps in busy views.
  Profile (2026-11-01): transforming and projecting corners ~29% of a
  frame, filling spans ~19% (per-row overhead ~10%), walking edges ~8.5%,
  clipping ~7%, occlusion ~6%. Every change to be checked pixel-identical
  against the frames before it (the same views rendered with the old and
  new builds, Layer 2 compared byte for byte).
  - Still to look at, if anything: scale_comp itself (3-4% of a frame in
    corner projections), and occ_record (5-11% in level flight).
  - (Done 2026-11-09: front to back looked at, occlusion pitched on;
    closed, it looks fine in play. See DONE.md.) Front to back, measured
    in the emulator over the 10 render-test views: every write to the
    view's pixels counted, by what wrote it.
    - Level flight is already nearly there: the occlusion pass and the cut
      rows leave an overdraw of only 1.00-1.32 (face writes / pixels
      kept). Drawing the faces' visible runs only (an ideal span buffer,
      60 T a row) would save 0-1.3% of a frame: not worth a rewrite.
    - Pitched views have no occlusion (OCCLUSION_CULL is level flight
      only): overdraw 1.3-1.9, and buildings that end up wholly overdrawn
      take 15-56% of the frame (view 8, pitch -20: 40 of 47 buildings,
      56%).
    - The clear: only 33% of its pixels survive, but clearing just the
      gaps would cost about what the one DMA fill does.
    - Tried: occlusion at any pitch (`OCC_PITCHED`, zpolice.asm, off).
      The cover rule still holds pitched (no roll, camera above the
      ground), except that the vertical edges lean, so only the columns
      of both a building's top and bottom corners are covered from its
      top down (the first try, the whole span, changed 50 of 124 views).
      With that: pixel-identical over 124 random pitched views (and the
      render test's 4), frame time -5.4% (median -3.4%; -31.6% to +9.6%
      by view). It drops 74% of the wholly overdrawn buildings, but
      every one is still transformed (occ_pretest's bounds are level
      flight only, so it's skipped when pitched) and recorded: in view 8
      it saves 424K T of faces and spends ~420K T more on the pass.
    - (Done 2026-11-09: a pitch-aware occ_pretest, and `OCC_PITCHED` on up
      to `OCC_PMAX` (18): -7.7% over the 124 pitched views, pixel-identical.
      See DONE.md.)
    - Possible later (not needed): the pitched pre-test is 3,600-4,500 T a building (5
      fmuls on top of the level one's work), and it costs where little is
      hidden (low, steep views: up to +18%; render views 4 and 5 +5% and
      +13%). Per-frame tables of the height terms (h sinP, h cosP for the
      15 heights) would take 2 of the 5 fmuls off each. Choosing per view
      (the better of on and off) would add only ~1% more.
  - Not to do: keeping SP borrowed for a whole polygon (saves the per-span
    SP restore and DI / EI, ~3%) would hold interrupts off long enough to
    miss some (the engines' sound); and clamping x instead of clipping the
    left / right planes needs proof the spans come out the same.
- Faster occlusion when facing the wall (the one view where occlusion is
  slower).
- Spread zombie path decisions over more frames when waves are large.
- Faster loading with a single combined city-and-level file.
- DMA+ blitter work: see "DMA optimisation" below.
- Corner transform and projection: see "Projection optimisation" below.

Completed items are in DONE.md.

## Screens in Layer 2 320x256 (2026-11-09)

Move the screens outside the game from the ULA (`text.asm`: 32x24
characters, attribute colours) to Layer 2 320x256 (40x32 characters, any
colour). The graphics page is done and tested: `layer2-320x256.asm`
(`PAGE_L320`, in slot 2 over the occlusion page), test_l320.py; see README.
The game start already switches back to 256x192 and puts the occlusion page
back (`l2_game_mode`).

Each screen, in place of `menu_clear` / `menu_print`:
- `nextreg L320_MMU,PAGE_L320`, `l320_cls`, `l320_mode320` (clear before
  switching, so the old contents never show).
- Its text tables (row, column, colour, text) through `l320_print_list`,
  with the colours as RRRGGGBB (`L320_WHITE`, `L320_YELLOW`, ...) in place
  of the `MENU_*` attributes, re-laid out for 40x32.
- Highlights (the selected option, a fit / can't-fit colour) with
  `l320_recolour`, or by printing again in the new colour.
- Panels and frames with `l320_box` / `l320_fill`.

1. (Done 2026-11-10) Main menu: its own page now (`mainmenu.asm`,
   `PAGE_MAINMENU`, page 36), and its NO SAVED GAME message.
2. Game over (`game_over_screen`, menu.asm).
3. (Done 2026-11-10) Level complete: its own page now (`levelend.asm`,
   `PAGE_LEVELEND`, page 37), with the salvage and its rewards and its own
   PRESS SPACE (`le_space`). Still to do: game complete
   (`game_complete_screen`, menu.asm).
4. Load error (`load_error_screen`, menu.asm).
5. (Done 2026-11-10) VTOL load-out (`loadout_screen`, loadout.asm). Since:
   a schematic of the VTOL's underside with the slots' hardpoints
   (ZPDATA/VTOL.ZPI, read when the screen opens; tools/screen_editor.py,
   tools/vtol_schematic.py). Red
   (`SCR_BAD`, a weapon that can't go in the slot) is hard to read on the
   dark blue: maybe a lighter red.
6. (Done 2026-11-10) Redefine keys (`keydef_screen`, keydef.asm): all 23
   controls show at once now (no scrolling).
7. Then: check that nothing still uses `menu_clear` / `menu_print` /
   `menu_char` (the pause screen, in flight, stays on the ULA) and remove
   what isn't used from the resident page. test_gameover.py reads the ULA
   screen (page 10) to see the game over screen: it would read Layer 2
   instead.
8. (Done 2026-11-10) A large font for these screens: 12x10 cells in
   colour gradients, ZPDATA/FONT12.ZPF, loaded at start-up, edited with
   tools/font_editor.py. The 8x8 font in the same style too, FONT8.ZPF
   (every text screen and the HUD). Maybe still: a title picture (see Graphics above),
   and lower case / more punctuation in the font (59 characters now:
   space to Z).

## Projection optimisation (2026-11-07, to review)

Transforming and projecting building corners is about 27% of a frame, spread
over a dozen steps of 1-9% each: about 1,550 T for every corner that reaches
the screen (outcode ~450, projection ~1,100) and about 1,000 T for every
building considered. Profiled in the emulator (its instruction timings are
exact) over one frame of each of the 10 render-test views, 1.79 million T a
frame on average. Every change pixel-identical: the render test compares the
frames byte for byte. These help CSpect and the hardware alike.

Where the time goes (share of a frame):
- Projecting corners ~8.6%: 1,015 full projections (vtx_proj / project) at
  ~1,100 T each, the level shortcut (proj_y) and the loop round them.
- Occlusion pre-test 4.2% (occ_pretest: rough screen bounds per building).
- Outcodes 3.9%: 1,554 at ~450 T (vtx_oc / calc_oc).
- Corners from the edge vectors and rot_pitch 2.7% (draw_bld's VBOX code).
- The cell frustum cull and draw_bld's set-up 2.5% (every cell in range).
- row_start's yaw rotation 2.4% (4 fmuls, twice a row).
- Back faces and neighbour cover (nb_cover) 1.6%; shading and masks ~1%.

Why a projection is ~1,100 T: X, Y, Z read from memory; zpatch normalises Z
(barrel shift, table) and patches the reciprocal into scale_comp (227 T);
scale_comp twice, x and y (213 T each: sign, shift, two MULs, the 9-bit
range, rounding); clamping to the screen; and ~300 T of push / pop / store
in vtx_proj and project. calc_oc then reads X, Y, Z again (338 T).

Repeats (neighbouring buildings share their grid corners), over the 10
frames: bottom-corner projections 493 for 320 corners (35% repeats), top
corners 522 for 405 (22%), outcodes 1,554 for 1,192 (23%). The level
shortcut (only Y for a top corner) did 198 of 720 top corners: it needs
level flight and the bottom corner on screen, so pitched views get none.

To do, roughly 6-8% of a frame together (estimates; item 1 done, 2.0%;
item 2 done, no benefit; item 4 done, 2.8%):
1. (Done 2026-11-09: a leaner projection, `vproj`: 36% off a corner's
   projection, 2.0% off the frame. See DONE.md.)
2. (Done 2026-11-09: No real benefit in testing. See DONE.md.)
   The street dots (draw_dots, 4.2% of a
   frame) project grid points too, but likely couldn't have shared it
   with the buildings: a dot is only worked out for a corner with no building next
   to it, when drawing a floor tile, so the two sets of points barely
   meet. A cache of the dots' own among the floor tiles is still open: a
   dot already cached for the frame when a tile gets ready to project it means that
   dot is already drawn, so the tile can skip it (no second projection,
   no second draw).
3. Outcode and projection in one pass (~1-1.5%): the corner read once, the
   outcode worked out on the way into the projection.
4. (Done 2026-11-09: fewer cells reaching the transform, a leaner
   occ_pretest, the walk's own cull and whole rows skipped: 2.8% off the
   frame, pixel-identical. See DONE.md.)
- A larger gain (2-3x) would need drawing front to back, skipping hidden
  buildings before any corner work (the overdraw item under Performance:
  measure overdraw first).

## DMA optimisation (2026-11-07, to review)

DMA+ (the zxnDDMA blitter, core 3.03.00) on real hardware only: each item
goes behind `REAL_HARDWARE` (`build.bat hardware`), keeping the plain zxnDMA
path for CSpect, with its DMA+ commands modelled in tools/nexsim.py (it stops
on any it doesn't model) and checked on a real Next: the frame rate with
`DRAW_FPS`, before and after. Done so far: `dma_fill` uses fill mode, and
NextRegs $CC-$CE are 0 (no interrupt holds a transfer back).

Estimates below are from the 10 render-test views (399 faces, 291,000
pixels), with DMA costs from the primer (docs/zxnDDMA/zxnddma.gde in the
Next distribution), not measured: filling faces is about 20% of a frame now
(it agrees with the 2026-11-01 profile).

1. Clear screen as two rectangles, sky and ground: fill mode, 2D, at a
   Layer 2 X,Y in the hidden screen (NextReg $13, the back buffer), so no
   paging of the sections. Small gain itself (~4,000 T a frame: the fill
   mode's halving is already in), but the first proof on hardware of X,Y,
   hidden screen and 2D, before the buildings rely on them.
   - The clear's costs: plain DMA ~197,000 T (11% of a frame), fill mode
     ~98,000 T (now, hardware build), 2-cycle timing ~65,000 T.
2. Long spans (`DMA_SPAN_MIN`, 20 pixels, and up) in fill mode: the fill
   value set once per face in place of `l2_cls_byte`; fs_loop's reload
   stays as it is. The face fill about -20%. The fill flag stays on for
   the spans: `occ_dma` (a memory copy) turns it off round itself and
   back on.
3. Block fill buildings: exact rectangles. Wherever rows of a face have
   the same left and right x (TA / TB, after the edge walk), at least 4
   rows and 16 wide, draw them as one DMA+ rectangle (2D, X,Y, hidden
   screen, fill), the other rows as now. Pixel-identical, so the render
   test still holds. 56% of face pixels qualify (walls facing us when
   level most, but even pitched views: -14% to -58% by view). The plain
   DMA set-up for the spans put back after each face's rectangles (~300 T).
   - Alone about -30%; with item 2 about -38% (~12% of a frame from ~20%).
   - Looked at and not worth it: the largest inner rectangle with the
     slivers each side by the CPU. It covers 75% of the pixels but saves
     no more (every row still needs its slivers), for more code.
4. 2-cycle DMA timing (WR1 / WR2 timing bytes) for the fills: another ~7%
   of the face fill, and the clear down to ~65,000 T, if it is reliable on
   the hardware: to try.
5. Draw the figures with DMA+. A block transfer to a Layer 2 X,Y needs no
   paging of the screen, and it has a transparent colour (pixel value 0,
   as the data has now), so it can replace spr_draw's pixel loops, still
   clipping: cut the row length, the number of rows and the start of the
   source to the view. The stored rows would have to become rectangles,
   with a fixed stride, in place of each row's start and count. The vision
   modes are already by palette, so one set of graphics serves every mode.
   - The fading ghost (spr_col: every pixel one colour) can't be blitted:
     fade it by stepping its own palette entries towards the background
     instead.

Things to watch:
- A large rectangle is one long DMA burst: with $CC-$CE 0 no interrupt
  breaks into it, so the 50 Hz interrupt can wait up to ~3 ms (a full-view
  wall). The clear already does this in pieces: check the sound.
- Expected gain overall: about 8% of a frame from items 1-4, roughly +1 to
  1.5 fps at 14-18 fps. Projecting corners (~29% of a frame) is still the
  largest cost, and DMA+ doesn't touch it.

## Open points from the level files (2026-10-27)

- More in the level complete (to come).
- A visible sky (`SKY_IS_WALL` off) to show each city's sky colour (also
  under Graphics).
 