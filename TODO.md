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

## Console LEDs and warnings (2026-11-17, done 2026-11-18)

All in hud.asm `draw_leds` (every frame; each LED's tile written only when
it changes, `set_led`; reset at each level's start), tests in
tests/test_tiles.py. Flashing keeps time on the 50 Hz clock (`dt`).
- [x] **Speed LED** (row 29 column 5, under S): green; amber from 3/4 of
      SPEED_MAX (`SPEED_AMBER`) or reversing; red while boosting.
      *(The bands were mine to choose: change them if you like.)*
- [x] **Wall proximity LED** (the middle one on the right, row 13 column
      37): amber; flashes LED_A_BRIGHT / LED_A a second each while within
      0.20 of a cell (`WALL_NEAR`, 51/256) of an edge with a building past
      it the VTOL isn't clear of (roof + COLL_H above it), or the city's
      edge.
- [x] **Integrity LED and beeps** (row 26 column 25, right of the
      percentage): green; amber below 25% with a mid beep (SFX_WARN_MID);
      red below 10% with three high beeps (new SFX_WARN_HIGH). Once on
      crossing each; again after a repair lifts it back.
- [x] **Human nearby LED** (the top one on the right, row 10 column 37):
      green; flashes LED_G_BRIGHT / LED_G a second each while a human
      waiting to be rescued is within 2 cells on both axes.
- [x] **Enemy LED** (the bottom one on the right, row 16 column 37): red;
      a lich's fireball, the devil's bolt at the VTOL or a ghost's blow
      (`enemy_alert`) flash LED_R_BRIGHT / LED_R a second each, 3 times;
      another attack starts the 3 again.

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

### Done so far
- [x] (2026-11-15) The research: `docs/CTC.md` covers the CTC, the Next's
  interrupt registers, hardware IM 2 mode, and reviews of the CSpect and
  taylorza examples.
- [x] (2026-11-16) Zombie decisions spread one record a frame, with every
  step checked: see §3, Zombies.
- [x] (2026-11-16) §1-§4 done, on the 50 Hz clock (README, "Game time";
  tests/test_timing.py; all 28 test files pass). How, where it differs from
  the plan below:
  - **No "ready at" time stamps:** intervals count down by dt, the
    overshoot carried so a rate holds (`gun_rearm`, the zombies' blows).
    Countdowns are relative, so save games needed no change.
  - **dt with no fraction, as planned:** movement is scaled by `fs`
    (dt × `ASSUMED_FPS` / 50, 8.8, from `fs_tab` made at assembly) rather
    than a table per speed: one table serves every speed.
  - **Whole frames' worth (`fsteps`)** for discrete steps and frame-tuned
    behaviour: the speed and nose keys, air brake, damper, boost fuel, gun
    tilt; ghosts and banshees, humans, the devil's walk and sinking,
    particles, the shake, a zombie's stuck wait, the walk cycle, a lich's
    reload. Those keep their tuning exactly; at high frame rates they move
    in whole frames' steps (0 some frames).
  - **Values that didn't fit a byte as ticks** stay frames' worth: a
    lich's reload (150 frames = 536 ticks), `ZWAIT` (100 frames).
  - **Your tick values are in:** the linked guns 4, the laser 10 on 6
    off and 1 damage a tick, reloads 2 / 50 / 100 / 20 / 150, repairs 2 a
    point, lock 100, the slot flash 5. Disembarking: one a second
    (`DISEMBARK`, 14 frames' worth). The devil's spin is 32 ticks (256 /
    `SPIN_FR` must be whole).
  - **The tests** run with `clk_test`: 4 ticks and exactly one frame's
    worth a frame.
- Still open from §1-§4:
  - [ ] The VTOL's collision isn't sub-stepped: at `DT_MAX` a boosted move
    is 125 units, under half a cell, so it can't pass through a building.
    Only needed if `DT_MAX` or the speeds go up.
  - [ ] The rounds' performance ideas (§3, Rounds): tile-crossing tests,
    monster tiles only, the ground point.
  - [x] The wreck's fire and debris (`wreck_fx`) come every 2nd / 4th
    rendered frame (visual only): left so (decided 2026-11-16). It's the
    crash before GAME OVER, so its timing doesn't matter.
  - [ ] Smoother ghosts, humans and particles at high frame rates: scale
    their moves by fs instead of whole frames' worth.

### 1. Foundation
- [x] **The game clock** (resident, `game_now`):
  - a 16-bit tick count advanced by the interrupt only while playing;
  - stopped while paused, on the menu screens, in the debug level select,
    on the load-out screen, and while a level loads;
  - a `TICK_HZ` constant, and an `MS n` macro that turns milliseconds into
    ticks, so that changing the clock (50 Hz `isr_ticks`, later a 200 Hz
    or 1 kHz CTC tick) re-scales every interval at build time;
  - reading it atomically: DI/EI around the two bytes, or read twice and
    compare.
- [x] **Timer helpers:**
  - `TIMER_SET var, ticks` (`var = now + ticks`);
  - `TIMER_DUE var`: carry clear when `now - var >= 0`, a signed 16-bit
    compare that is safe across the wrap. That allows intervals up to
    32767 ticks: 11 minutes at 50 Hz, 32 s at 1 kHz.
  - For rates (gunfire), add the interval to the old ready time, not to
    `now`, so the average rate holds when frames are long.
- [x] **The frame's elapsed time** `dt`:
  - a 16-bit integer: the ticks since the last rendered frame, worked out
    once a frame in `main_loop`;
  - the counter rolls over (new < last). A plain 16-bit `new - last`
    (`or a` / `sbc hl,de`) gives the right answer across the roll-over
    too: it is 65536 - last + new. (`(65535 - last) + new` would be one
    tick short.)
  - clamped to 1..`DT_MAX` (about 8 ticks, 160 ms), so a long stall (a
    load, a debug key) doesn't teleport anything;
  - no fraction. Movement uses **look-up tables precalculated at build
    time** (gentables.py), one per speed: dt ticks -> distance, from the
    per-frame speeds and `ASSUMED_FPS`.
  - Logic timed in ticks (intervals, cool-downs) uses dt, or the clock,
    as a whole number of ticks.
- [x] **Tests:**
  - give the emulator's tests a way to drive `game_now` themselves (poke
    it, or a mode where it advances a fixed amount a frame), so that the
    tests stay deterministic;
  - add a test helper, `zp.advance(cpu, ms)`.
- [x] **Save games:** store timers as time remaining, not as absolute
  ticks, or restart them on loading. Bump `SG_VERSION`.
### 2. Weapons: rate of fire, cool-down, reloading
- [x] **`gun_wait`** becomes a "ready at" time, with the intervals in ms:
  - `GUN_INTERVAL` 4 frames: 285 ms;
  - `CHAIN_INTERVAL` 1: 71 ms;
  - `ROCKET_INTERVAL` / `MISSILE_INTERVAL` 7: 500 ms;
  - `AUTOCANNON_INTERVAL` / `PROX_INTERVAL` 16: 1.14 s;
  - `BOMB_INTERVAL` 14: 1 s.

  The chain gun is the case to watch: at 14 fps it fires once a frame. At
  a lower frame rate a fixed rate means firing 2 rounds some frames, or
  capping at 1 a frame. Decide which.
- [x] **The linked chain guns:** a round every **4 ticks** (80 ms),
  alternating sides (`lk_fired`) as now.
- [x] **Pulse laser:** **10 ticks on** (200 ms) and **6 ticks off**
  (120 ms) (`LASER_ON`, `LASER_COOL`; now 3 and 8 frames: 214 ms on, 570
  ms off). That is a much higher duty cycle: 63% on, against 27% now.
  - While it's on, check every frame whether the beam hits a target.
  - **Damage: 1 point a clock tick** of beam on the target (`LASER_DMG`
    1). A frame's hit does 1 × dt (the ticks since the last frame,
    counting only the on phase), so a 10-tick pulse does 10 points
    whatever the frame rate.
- [x] **Reloading on the pad** (`pad_service`), ticks a shot:

  | Load | Now | New |
  |---|---|---|
  | `WCFG_RELOAD`, `LINK_RELOAD` | 1 frame | **2 ticks** |
  | `ROCKET_RELOAD` | 15 frames (1.07 s) | **50 ticks** (1 s) |
  | `MISSILE_RELOAD` | 30 (2.1 s) | **100 ticks** (2 s) |
  | `AUTOCANNON_RELOAD` | 7 (0.5 s) | **20 ticks** (0.4 s) |
  | `BOMB_RELOAD` | 30 (2.1 s) | **150 ticks** (3 s) |
  | Repairs | a point a frame | **2 ticks a point** |
  | `DISEMBARK` | a passenger a second (14 frames) | **one a second: 50 ticks** |
- [x] **Missile lock:** `LOCK_TIME` **100 ticks** (2 s, as now: 28
  frames). `RET_STEP` / `RET_WANDER` (the reticule's pixels a frame) by
  dt.
- [x] **Weapon slot flash** `WFLASH`: **5 ticks** (100 ms; now 5 frames,
  357 ms). Implement it on the clock.
### 3. Movement (by `dt`)
- [x] **The VTOL** (player.asm) first, because the player feels it most:
  - `SPEED_MAX` / `SPEED_MIN` / `BOOST_SPEED` (units a frame),
    `CLIMB_RATE`, `YAW_RATE` / `YAW_FINE`, the strafe
    (`STRAFE_D_HALVES`);
  - the acceleration per frame of the speed keys (`SPEED_STEP`,
    `AIRBRAKE_STEP`);
  - the pitch damper (`PDAMP_FRAMES`, `PDAMP_MIN`), `GUN_TILT_STEP`.
  - Convert them all to per-tick values from the current per-frame ones at
    14 fps, through `ASSUMED_FPS` (so they can be re-balanced for real
    hardware later), with dt -> distance tables (gentables.py).
  Its building collisions test one frame's move. With a long `dt`, test
  in sub-steps of at most a normal frame's move, so it can't pass through
  a wall.
- [x] **Rounds:**
  - `BULLET_STEP` 457, `ROCKET_STEP` 137, `MISSILE_STEP` 68 and `FB_STEP`
    182 units a frame;
  - Performance, with the longer paths:
    - test a building hit only when the path crosses a tile boundary;
    - test the monsters only in tiles that have one (`CELL_ZOMBIE`), a
      quick way to rule out a hit;
    - a new height below 0 means the round has hit the ground: the point
      on the path where y = 0 is where it lands.
  - `BOMB_SPEED` and `BOMB_STEEPEN` (5 frames a step);
  - `MISSILE_TURN` (3 degrees a frame);
  - the fireball's flight (14 frames) and the rounds' range (in frames).

  Their hit tests already sweep the frame's whole path (`B_PX`): keep
  that with the longer paths.
- [x] **Zombie decisions** (done 2026-11-16): taken one record a frame
  (`zdec_i`, round the NMON = 48 records: each walker every 48 frames,
  ghouls and a lich included), with every step checked against the next
  tile. A building or the map's edge within `ZMARGIN`: it stops and turns
  90 degrees at random; a base tile: it goes for it. So none walks into a
  building between decisions. Map blips also move on a cell change.
  tests/test_zombie_moves.py. This spreads a CPU cost over the frames, so
  it stays per frame; only the walking below goes by dt.
- [x] **Zombies' walking:**
  - `zspeed` (`ZSPEED_INIT`, units a frame), and `zsteps` (now only the
    decision's look-ahead: 10 frames of walking);
  - standing still when stuck, `ZWAIT` 100 frames (7 s);
  - their walking animation steps.
- [x] **Specials:**
  - ghosts: `GHOST_CLIMB`, `GHOST_DECIDE` (30 frames), roaming;
  - banshees' and ghouls' speeds (`zcalc_step`);
  - the lich (4 × a zombie's speed);
  - the devil: `DV_STEP_FR` (24 frames a step), `DV_STEP_U`, `DV_SINK`.
- [x] **Humans:** `HUMAN_RUN` / `HUMAN_FLEE` (9 units a frame),
  `FLEE_TIME` (a second).
- [x] **The wreck:** `DEAD_SPIN`, `DEAD_FALL_MAX`.
- [x] **Particles:** velocities and `PART_GRAV` per frame. They are visual
  only, so this is the lowest priority: they could stay per rendered
  frame.

### 4. Attacks and the monsters' timing
- [x] **Zombies hitting** the base, barricades and humans: `ZHIT_FRAMES`
  5 (357 ms). This is the base's real damage rate: at 30 fps the base
  takes twice the damage per second it does at 14. It is the first of
  these to fix: it affects fairness the most.

Every interval in this section: ticks = round(frames × `TICK_HZ` /
`ASSUMED_FPS`), computed at build time (an `equ` from the frame value, so
changing `ASSUMED_FPS` re-scales them all). At 14 fps:

| Value | Frames | Ticks |
|---|---|---|
| `ZHIT_FRAMES` | 5 | 18 |
| `GHOST_HIT_FRAMES` | 10 | 36 |
| `LICH_RATE` / `LICH_RATE_STEP` | 150 / 5 | 536 / 18 |
| `BOLT_FRAMES` | 4 | 14 |
| `SPIN_FR` | 8 | 29 |
| `DV_DIE_FR` | 40 | 143 |
| `DEAD_PAUSE` | 50 | 179 |
| `SHAKE_LEN` | 6 | 21 |
| `GHOST_FADE_FRAMES` (a step) | 3 | 11 |
| `HUM_FLASH` | 2 | 7 |

- [x] **Ghosts' blows:** `GHOST_HIT_FRAMES` 10 (714 ms).
- [x] **Banshees' attack rate** and anything else counted per frame in
  specials.asm.
- [x] **A lich's shots:** `LICH_WAIT` / `LICH_FRAMES` (now `LICH_RATE` 150
  frames less 5 a city: 10.7 s down to 7.5 s at 14 fps). Make them ms.
  (Did the 150 frames mean 3 s? At 14 fps they are 10.7 s.)
- [x] **The devil:**
  - `DV_CHARGE_T` / `DV_HUM_T` already count `isr_ticks` (real time);
  - `BOLT_FRAMES`, `SPIN_FR` (the VTOL's spin when hit), `DV_DIE_FR` and
    `DV_DIE_PARTS` are per frame: make the spin and the death last a fixed
    time.
- [x] **Waves and levels:**
  - `DEAD_PAUSE` (50 frames on the ground before GAME OVER: 3.6 s at 14
    fps, meant as about 2 s?);
  - the screen shake (`SHAKE_LEN` 6 frames, `shake_big`) as time;
  - `HUM_FLASH` (the humans' status flash);
  - `GHOST_FADE_FRAMES`;
  - `PREPARE FOR COMBAT` already uses `isr_ticks` (`WPREP_TICKS`).

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
 
