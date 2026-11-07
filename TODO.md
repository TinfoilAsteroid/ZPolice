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
  - Measure overdraw (writes per pixel, in the emulator). If it's high,
    draw front to back, keeping per screen column how far down it is
    already filled (for boxes standing on flat ground, the same picture as
    the painter's order). A big rewrite: only if overdraw justifies it.
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

To do, roughly 6-8% of a frame together (estimates):
1. A leaner projection (~2-3%): vtx_proj / project / scale_comp as one
   routine for building corners, in registers, Z's reciprocal set up once
   for both coordinates, no self-patching, calls or push / pop. Perhaps
   30-40% off a projection.
2. A projection cache for grid corners (~2.5%): each lattice point's
   outcode and screen position, the first time in a frame, reused by its
   neighbours and by roofs of the same height (a small table round the
   camera, marked with the frame). The street dots (draw_dots, 4.2% of a
   frame) project grid points too: check whether they could share it.
3. Outcode and projection in one pass (~1-1.5%): the corner read once, the
   outcode worked out on the way into the projection.
4. Fewer buildings reaching the transform: the cull and the occlusion
   pre-test cost 6.7% themselves, so a cheaper rejection of cells that
   are plainly hidden or out of view helps every frame. The least
   certain of the four.
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
 