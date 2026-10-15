# Z-Police

A 3D vector graphics flight game for the ZX Spectrum Next, written in Z80N
assembler. You fly a VTOL craft around a city of 32×32 blocks, in the spirit
of *Sky Ranger*. Buildings are drawn as white vectors over solid black faces,
with true hidden line removal, on Layer 2 at 256×192 with 256 colours.

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
for a hovering VTOL, and height is set with T/G. The HUD shows a gunsight, a
speed bar (bottom left, red when reversing) and an altitude bar (right). If
you fly into a building the craft stops and the border flashes red.

## Files

| File | Purpose |
|------|---------|
| `zpolice.asm` | the game (one source file) |
| `gentables.py` | generates `tables.inc`: sine, reciprocal, log2, horizon, silhouette tables and the city map |
| `tools/nexsim.py` | small headless Z80N emulator used for testing: dumps every flipped frame to PNG and counts T-states per routine |
| `layer2_cls.asm` | zxnDMA equates and the fill command block used by `clear_screen` |
| `build.bat` | build script |

## Memory map

```
$0000-$BFFF  Layer 2 back buffer, MMU slots 0-5 (6 x 8K pages)
             pixel address = y*256 + x  ->  H = y, L = x
$C000-$FFFF  code, tables, variables, stack   (bank 0, ~9K used)
```

Two 48K Layer 2 buffers (16K banks 9-11 and 12-14) are double buffered.
Each frame the back buffer is paged into the bottom 48K, drawn, and then
shown by writing NextReg `$12` during the vertical blank. With the screen at
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
  the projector is already inside the frustum, |X| ≤ Z and |Y| ≤ 0.75Z, so
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
* Look up the horizon row from a `96 + 128·tan(pitch)` table. Rows above it
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
  `|X|·c ≤ Z1`, where `c = cosP − 0.75|sinP|`. The building's bounding circle
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

### 4. Hidden line removal
Each building is painted as **solid black faces with white edges**. The
painter's order from step 2 means nearer buildings overwrite both the fills
and the lines of those behind. There are two paths:

* **Silhouette path (building wholly on screen):**
  * A table indexed by the visible-face mask gives the silhouette as a 4–6
    vertex cycle, plus 0–3 interior edges.
  * The silhouette is filled once (a convex polygon) and outlined, then the
    interior edges are drawn as lines.
  * The table is generated from the box's edge and face adjacency: an edge
    with one visible neighbour face is on the silhouette, an edge with two is
    interior.
  * One fill per building replaces two or three overlapping face fills.
* **Clip path (building crosses the frustum):**
  * Each visible face is clipped in 3D against 5 planes with
    Sutherland–Hodgman. The planes are near `Z=16`, `X=±Z` (90° horizontal
    field of view) and `Y=±0.75Z`.
  * Intersection parameters use a 32/16 fixed-point divide, and new points
    are snapped exactly onto the clip plane.
  * Every vertex carries an "edge is real" flag. Edges created along a clip
    plane are filled but not outlined, so the screen border never gets a
    false line.
  * Edges shared between faces are outlined only once, using per-face edge
    masks.

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
    leaves it configured (fixed source byte = fill colour, length high byte
    0), so each span reloads only length, destination, LOAD and ENABLE:
    7 `OUT`s, about 150 T plus 2 T per pixel, against about 90 T plus 5.5 T
    per pixel for `PUSH`.
* **Lines:** Bresenham with self-modified `INC/DEC L` and `INC/DEC H`
  steps, which works because a pixel address is just `H = y, L = x`.

### Performance
Measured with `tools/nexsim.py` (pure T-state count at 28 MHz, no memory
contention) over the scripted flights above: **1.8–2.9 M T-states per frame,
about 10–15 fps**. The emulator costs DMA transfers at 2 T per byte (set
with the `DMA_T` environment variable), which makes the clear about 0.1 M
per frame. Draw
distance is the main lever: at `VIEW_R` = 5 it is about 14–18 fps, and at
`VIEW_R` = 7 about 9–11 fps. Real hardware adds some wait states at 28 MHz.
Movement is per frame, so game speed follows frame rate.

## Tuning

Constants at the top of `zpolice.asm`: `VIEW_R` (draw distance), `NEAR`,
`PMAX` (pitch limit, must match `gentables.py`), speeds and rates, the colours
(Layer 2 RRRGGGBB) and the two building footprints. `PMAX` is kept at 24
(≈34°). At that limit no point behind the camera's horizontal plane can ever
be in view, which the culling relies on.

The city layout, heights and tower placement come from `gentables.py`
(seeded random, with every 8th row and column left open as a boulevard).

## Testing headless

```
python tools/nexsim.py zpolice.nex out 60 "0:QT,20:F,35:TE,50:"
```

This runs 60 frames, holding Q+T from frame 0, F from frame 20, then T+E,
then nothing. Each frame is written to `out/fNNN.png` along with its T-state
count. Set `PROFILE=zpolice.sym` (after building with `--sym`) for a
per-routine breakdown.
