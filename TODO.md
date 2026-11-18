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
- Salvage point change - 1 point per human not killed, 2 points per human rescuded, -5 per killed human: never goes below 0 or removes unlocks, or reactivates locks of player saves more
- Review the levels and waves: there seem to be a lot of zombies early in the
  game. Zombies could also be weaker at the start, while the player hasn't
  unlocked weapons yet.
- Ghosts respawning during a level, not only at the start (also below).
- New monster types, or a boss every 10 levels.
- Add super zombie, big and bulky as wide has 20 hit points.
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
  - Possible later (not needed): the pitched occlusion pre-test is
    3,600-4,500 T a building (5 fmuls on top of the level one's work), and
    it costs where little is hidden (low, steep views: up to +18%; render
    views 4 and 5 +5% and +13%). Per-frame tables of the height terms
    (h sinP, h cosP for the 15 heights) would take 2 of the 5 fmuls off
    each. Choosing per view (the better of on and off) would add only ~1%
    more.
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

## Screens in Layer 2 320x256

All the screens outside the game are done (DONE.md). Maybe still:
- A title picture (see Graphics above), and lower case / more
  punctuation in the large font (59 characters now: space to Z).
- The load-out: red (`SCR_BAD`, a weapon that can't go in the slot) is
  hard to read on the dark blue: maybe a lighter red.

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
3. Outcode and projection in one pass (~1-1.5%): the corner read once, the
   outcode worked out on the way into the projection.
- A larger gain (2-3x) would need drawing front to back, skipping hidden
  buildings before any corner work (the overdraw item under Performance:
  measure overdraw first).

## DMA optimisation (2026-11-07, to review)

DMA+ (the zxnDDMA blitter, core 3.03.00) on real hardware only: each item
goes behind `REAL_HARDWARE` (`build.bat hardware`), keeping the plain zxnDMA
path for CSpect, with its DMA+ commands modelled in tools/nexsim.py (it stops
on any it doesn't model) and checked on a real Next: the frame rate with
`DRAW_FPS`, before and after. Done so far: `dma_fill` uses fill mode, and
NextRegs $CC-$CE are 0 (no interrupt holds a transfer back); items 1-3
below (2026-11-12). The DMA+ reference: docs/ZXNDDMA.md (from the Next
distribution's guide); tests/test_hardware.py checks the hardware build
draws as the plain one.

Estimates below are from the 10 render-test views (399 faces, 291,000
pixels), with DMA costs from the primer (docs/zxnDDMA/zxnddma.gde in the
Next distribution), not measured: filling faces is about 20% of a frame now
(it agrees with the 2026-11-01 profile).

- Items 1-3 (done: DONE.md): check the frame rate on a real Next
  (`DRAW_FPS`) and the sound with the long bursts.
- Item 5 (done: DONE.md): the fading ghost (spr_col: one colour) can't
  be blitted, the CPU draws it, ~20% slower than the plain build. To do:
  fade it by stepping its own palette entries towards the background,
  and blit it too.
4. 2-cycle DMA timing (WR1 / WR2 timing bytes) for the fills: another ~7%
   of the face fill, and the clear down to ~65,000 T, if it is reliable on
   the hardware: to try.

Things to watch:
- A large rectangle is one long DMA burst: with $CC-$CE 0 no interrupt
  breaks into it, so the 50 Hz interrupt can wait up to ~3 ms (a full-view
  wall). The clear already does this in pieces: check the sound.
- Expected gain overall: about 8% of a frame from items 1-4, roughly +1 to
  1.5 fps at 14-18 fps. Projecting corners (~29% of a frame) is still the
  largest cost, and DMA+ doesn't touch it.

## Menu music on the DACs (2026-11-16, to do)

Music on the screens outside the game, from the 8-bit DACs: the DMA
streaming it from the SD card through a 16K ring (docs/DAC.md, "Plan:
music on the main menu").
- [ ] **Create the music (to do: the author).** A track for the menus that
      loops cleanly (its end runs into its start). Any length: it streams
      from the SD card, about 15K a second. Hand it over as a WAV: it's
      turned into `ZPDATA/MENU.ZPM` (raw unsigned 8-bit mono, 15,625 Hz) by
      a tool, so any rate or bit depth will do, but mix it for 8-bit mono
      (no quiet detail that 8 bits would lose; nothing that needs stereo).
- [ ] Until then: a test track (a tone or a beat) to build the player with.
- [ ] Check on CSpect and a real Next: the DMA prescaler's rate, the DMA's
      address read back, the DACs heard (NextReg `$08` bit 3).
- [ ] The DACs on at start-up (`$08` bit 3).
- [ ] The player: the ring in slots 3 and 4, the DMA looping over it
      (burst, prescaler 56, auto restart), refilled from the file each
      `menu_frame`, looping at the file's end.
- [ ] Stop and start it around screen changes (`screen320`: the screens'
      own DMA), loading and saving, and for good when a game starts (slots
      3 and 4 back).
- [ ] Without the file: silence, as now.
- [ ] Model the DAC writes and the DMA's prescaler in tools/nexsim.py, for
      the tests (the music's position stepping on, the refills, the
      stops).

## Timing: real time instead of frame counting (2026-11-15, to review)

See docs/CTC.md. The game logic runs once per rendered frame. Every speed is
in units a frame and every interval is a count of frames, tuned for 14 fps
(`NOMINAL_FPS`). So game time follows the frame rate: a busy view slows the
whole game, and a sparse one speeds it up (facing a wall: 34-46 fps, 2-3
times too fast). The fix is to time things by a real clock.

**The approach: one master clock, software timers. No CTC channel per
feature.**
- There are dozens of timers: one per weapon, per monster, per human, per
  effect. The CTC has 4 channels (8 on some cores), and every interrupt
  costs 100-200 T.
- So use one master tick counter, and a "ready at" time stamp for each
  timer, compared when it matters.
- The clock starts as the 50 Hz frame interrupt's `isr_ticks`, which
  already exists. It moves to a CTC channel only if 20 ms proves too
  coarse.
- CTC channels go only to things that need a rate of their own: the
  sound, and profiling.

**Clock ticks.** A tick is one 50 Hz interrupt, 20 ms (`TICK_HZ` 50).
Intervals are whole numbers of ticks. No fractional ticks.

**`ASSUMED_FPS`** (replaces `NOMINAL_FPS`, 14 to start with) is the frame
rate the current per-frame values were tuned at. A value not given its own
tick count below is converted as:
- ticks = round(frames × `TICK_HZ` / `ASSUMED_FPS`). At 14 fps a frame is
  3.57 ticks.
- distance a tick = the per-frame distance × `ASSUMED_FPS` / `TICK_HZ`.

Real hardware renders faster than the emulator. Re-balancing for it is
then one constant: `ASSUMED_FPS`.

### Still open from §1-§4 (the done parts: DONE.md)
- [ ] The VTOL's collision isn't sub-stepped: at `DT_MAX` a boosted move
  is 125 units, under half a cell, so it can't pass through a building.
  Only needed if `DT_MAX` or the speeds go up.
- [ ] The rounds' performance ideas (§3, Rounds): tile-crossing tests,
  monster tiles only, the ground point.
- [ ] Smoother ghosts, humans and particles at high frame rates: scale
  their moves by fs instead of whole frames' worth.

### 5. CTC channels for specific jobs
- [ ] **Model the CTC in `tools/nexsim.py`** first: the channel ports,
  timer and counter modes, chaining, `$C5` / `$C9`, and hardware IM 2
  mode (`$C0`) with its vectors. Test it against the two worked examples
  in docs/CTC.md.
- [ ] **Hardware IM 2 mode for the game** (`$C0` bit 0):
  - replace the 257-entry, `$xyxy` table with a 32-byte, 16-entry one
    (taylorza's layout): the frame interrupt at entry 11, the CTC
    channels at 3-10. That frees most of a page in the zombie page.
  - Every routine already ends `ei` / `reti`.
  - Check the `$243B` read-back the frame routine relies on, on real
    hardware.
- [ ] **A CTC master clock** (only if 50 Hz is too coarse):
  - channel 0 as a 10 kHz timer, chained into channel 1 counting to 200 Hz
    (5 ms) or 1 kHz;
  - a minimal routine: its own stack, as `im2_routine` (the span filler
    borrows SP), count `game_now`, no paging, `ei` / `reti`;
  - `TICK_HZ` changes, and every interval follows.
  - Decide whether `$CD` lets it interrupt DMA bursts (`dv_flush`, the
    fills): ticks are otherwise merged during a long burst.
- [ ] **Sound on its own CTC channel:**
  - run `engine_tick` / `sfx_tick` at 100 Hz from a CTC channel instead
    of the 50 Hz frame interrupt, for smoother engine slides and finer
    effect steps (sounds rewritten at 10 ms a step);
  - the frame interrupt then only counts frames;
  - later, sample playback (speech, a siren) on a DAC from a CTC channel.
- [ ] **Profiling on real hardware:**
  - a free-running 10 kHz CTC count (or reading a channel's counter
    directly) to time the parts of a frame in 0.1 ms steps;
  - show them with `DRAW_FPS`, to tune the renderer on the real Next
    rather than the emulator.
- [ ] **Measure the CTC clock once on a real Next:** CTC ticks against 50
  frame interrupts, in VGA 0 and HDMI. Confirm 28 MHz.

### Suggested order
1. The game clock on `isr_ticks`, the helpers, the test hooks (§1).
2. The attack rates (`ZHIT_FRAMES` and the specials': the base's
   fairness) and the weapons' rates, reloads and cool-downs (§2, §4). No
   new hardware set-up is needed.
3. The VTOL's and the rounds' movement by `dt` (§3), then the monsters'.
4. CTC in nexsim, hardware IM 2 mode, then a CTC clock or sound channel if
   step 3 shows 50 Hz is too coarse (§5).

## Open points from the level files (2026-10-27)

- More in the level complete (to come).
- A visible sky (`SKY_IS_WALL` off) to show each city's sky colour (also
  under Graphics).
 
