# Z-Police

A 3D vector graphics flight game for the ZX Spectrum Next, written in Z80N
assembler. You fly a VTOL craft around a city of 32×32 blocks, in the spirit
of *Sky Ranger*. Buildings are drawn as white vectors over solid faces, each
building in its own shaded colour, with true hidden line removal, on Layer 2 at
256×192 with 256 colours. The 3D view uses the top two thirds of the screen
(256×128), and the bottom third is an instrument panel.

![boulevard](docs/boulevard.png) ![turning](docs/turning.png) ![overhead](docs/overhead.png)

## Building and running

Requirements: sjasmplus 1.20+ (built with Z80N support) and Python 3. To run
it, use CSpect or real Next hardware.

```
build.bat          # gentables.py -> tables.inc, then sjasmplus -> zpolice.nex
build.bat run      # ...and launch CSpect
```

Manually:

```
python gentables.py
sjasmplus --zxnext zpolice.asm
CSpect.exe -w3 -zxnext -s28 zpolice.nex
```

## Controls

| Key | Action          | Key | Action          |
|-----|-----------------|-----|-----------------|
| Q   | speed up        | A   | slow down / reverse |
| W   | stop            |     |                 |
| S   | turn left       | F   | turn right      |
| E   | nose down       | D   | nose up         |
| T   | climb           | G   | descend         |

The craft moves horizontally along its heading. Pitch only aims the view, as
for a hovering VTOL, and height is set with T/G. A gunsight marks the
centre of the view. The panel below has SPD and ALT gauges; the speed gauge
turns red when reversing. If
you fly into a building the craft stops and the border flashes red.

### Instrument panel (ULA / Layer 1)
The panel in rows 128–191 is drawn on the ULA, which is above Layer 2
(priority S-U-L). The Layer 2 clip window is limited to the viewport (rows
0–127), so Layer 2 never shows there.

* **Fixed contents:** set up once by `ula_init`. That's a dark slate paper,
  a green divider on the top pixel row, and the "SPD" and "ALT" labels.
* **Gauges:** each is a row of 14 attribute cells (112 pixels), coloured
  through ULA attributes.
  * Full cells use the bar colour as paper: green, or red when reversing.
  * The cell where the bar ends keeps the black "empty" paper and uses the
    bar colour as ink, with that many pixels set, so the gauge still moves
    one pixel at a time.
  * `draw_hud` rewrites the 14 attributes and 14×8 bitmap bytes of each
    gauge every frame.
* **City map:** the right-hand 64×64 of the panel (columns 192–255) is a
  map of the whole city, one 2×2 pixel block per grid cell, with north (+Z)
  at the top.
  * Buildings are solid white blocks on black paper, and roads are left
    black. The map has no border.
  * `map_init` draws it once, using the Z80N `PIXELAD`/`SETAE` instructions
    for ULA pixel addressing.
  * Each frame, `map_player` undoes the previous frame's XOR, then on
    alternate frames XORs the pixel under the player (1 map pixel = 128
    world units). The marker flashes and leaves the map intact.
* **Paging:** the ULA screen (bank 5) stays mapped at `$8000` (slots 4–5),
  so no paging is needed for the panel or the FPS text.
* **ULA palette:** the custom entries are paper 0 = `$E3` (transparent, so
  the viewport shows through above the panel), paper 1 = panel, paper 2 =
  empty gauge, and paper/ink 3 = red, paper/ink 4 = green.
* **Border:** the border flash on a collision uses colour 3 (red).

### FPS counter
The frame rate is shown as `nn FPS` in the top left of the ULA screen,
which sits above Layer 2 (layer priority S-U-L, NextReg `$15`). ULA paper
palette entries 16 and 24 are set to the global transparency colour `$E3`,
so only the white text covers the 3D view. Interrupts stay off because the
span filler borrows SP, so time comes from the raster instead:
* `vtick` reads the video line (NextReg `$1E/$1F`) and counts a new 50 Hz
  frame each time the line number goes backwards. It runs between the
  main-loop stages and once per building, so it is sampled more often than
  once per display frame.
* Every 50 display frames (one second), the number of frames rendered is
  shown.

## Files

| File | Purpose |
|------|---------|
| `zpolice.asm` | the game (one source file) |
| `gentables.py` | generates `tables.inc`: sine, reciprocal, log2, horizon and used-corner tables, the city map, the per-cell colour map and the Layer 2 palette |
| `layer2_cls.asm` | zxnDMA equates and the fill command block used by `clear_screen` |
| `tools/nexsim.py` | small headless Z80N emulator used for testing: dumps every flipped frame to PNG and counts T-states per routine |
| `build.bat` | build script |

## Memory map

```
$0000-$7FFF  Layer 2 back buffer viewport, MMU slots 0-3 (4 x 8K pages)
             pixel address = y*256 + x  ->  H = y, L = x  (y 0..127)
$8000-$BFFF  ULA screen, bank 5 (slots 4-5): bitmap $8000, attributes $9800
$C000-$FFFF  code, tables, variables, stack   (bank 0, ~10K used)
```

Layer 2 is clipped to the 128-row viewport, so each buffer only uses its
first two 16K banks. Buffer A is banks 9–10 and buffer B is banks 11–12.
Buffer A's hidden third bank is buffer B's first, so only four banks are used
in total. The buffers are double buffered with the hardware shadow register:
NextReg `$12` is the active (displayed) bank and NextReg `$13` the shadow
bank. Each frame the shadow bank, read back from `$13`, is paged into
`$0000–$7FFF` and drawn. During the vertical blank
`l2_flip` swaps the two registers, so the registers themselves record which
buffer is which. With the screen at
`$0000` a pixel is just `ld h,y : ld l,x : ld (hl),c`, with no address
arithmetic. The ROM is never needed, so interrupts stay disabled. That also
lets the fillers use the stack pointer as a fast write pointer.

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
* Rotate the box edge vectors into camera space once per frame. There are two
  footprints (block 176², tower 96²), so this is `R·(s,0,0)` and
  `R·(0,0,s)`, plus the offset from cell centre to footprint corner. Every
  building then gets its 8 corners from one transformed point and additions.
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
  * Each such face is clipped in 3D against 5 planes with
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
  * Steep edges skip the division entirely.
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

### Performance
Measured with `tools/nexsim.py` (pure T-state count at 28 MHz, no memory
contention, raster derived from T-states) over the scripted flights above.
With per-face shading and `WAIT_FOR_VBLANK`, each frame takes 4–5 display
frames: **about 10–12.5 fps**. The emulator costs DMA transfers at 2 T per
byte (set with the `DMA_T` environment variable), which makes the clear
about 0.1 M per frame. Draw distance is the main lever (`VIEW_R`). Real
hardware adds some wait states at 28 MHz. Movement is per frame, so game speed follows frame rate.

## Tuning

Constants at the top of `zpolice.asm`: `VIEW_R` (draw distance), `NEAR`,
`PMAX` (pitch limit, must match `gentables.py`), speeds and rates, the colours
(Layer 2 RRRGGGBB), `DMA_SPAN_MIN` and the two building footprints. `PMAX` is
kept at 24 (≈34°). At that limit no point behind the camera's horizontal
plane can ever be in view, which the culling relies on.

The city layout, heights and tower placement come from `gentables.py`
(seeded random, with every 8th row and column left open as a boulevard).

Each grid cell also has a colour code in `city_col`, which is stored right
after `city_map` so a cell's colour is its map byte + 1024 (an `ASSERT`
checks this). Roads and open cells hold `GROUND_COL`, and buildings hold a
seeded random colour family.

**Palette:** Layer 2 uses a custom 9-bit palette (`l2_palette`), loaded at
start-up through NextRegs `$43/$40/$44`. It has 64 colour families of four
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

## Testing headless

```
python tools/nexsim.py zpolice.nex out 60 "0:QT,20:F,35:TE,50:"
```

This runs 60 frames, holding Q+T from frame 0, F from frame 20, then T+E,
then nothing. Each frame is written to `out/fNNN.png` along with its T-state
count. Set `PROFILE=zpolice.sym` (after building with `--sym`) for a
per-routine breakdown.
