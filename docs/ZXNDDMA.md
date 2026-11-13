# zxnDDMA (DMA+) reference

How the Next's DMA and its DMA+ extension (the "blitter", core 3.03.00) are
programmed, for this project. Condensed from the official guide,
`F:\sn-complete-26.11\docs\zxnDDMA\zxnddma.gde` (SpecNext Ltd, 2026-11-05,
CC BY-NC-SA, after Allen Albright and Mike Dailly's zxnDMA document), and its
examples in `F:\sn-complete-26.11\docs\zxnDDMA\examples\`:

| Example | Shows |
|---|---|
| `zxndma_example.asm` | plain zxnDMA copies |
| `dma_extended_example.asm` | the extended commands |
| `zxnddma_examples.asm` | full-screen clear with fill; fill boxes at X,Y; 40 transparent balls with a 7-byte reload each |
| `zxnddma_compare.asm` | detecting DMA+ safely; DMA vs CPU timings |
| `zxnddma_sprites.asm`, `zxnddma_lemmings.asm` | Layer 2 "sprites": transparent 2D copies from a sheet |
| `zxnddma_clip.asm` | clipping a 2D copy to the screen |
| `zxnddma_modes.asm` | 256x192, 320x256, 640x256: boxes and copies in each |
| `zxnddma_scroll.asm`, `zxnddma_scroller.asm` | scrolling with 2D copies |
| `zxnddma_windows.asm` | fill-mode boxes, transparent shadows |

When in doubt, the guide wins; the hardware is `cores/zxnext/src/device/new_dma.vhd`.

## Ports and writing

- Port **$6B**: zxnDMA mode, the only port that takes the DMA+ commands
  (`OUT (C),A` with BC = $006B, or `OUT ($6B),A`). Port $0B is the Zilog-like
  mode: DMA+ commands are dropped there **but their follow bytes are not**
  (they're read as register writes): on a core without DMA+ the same happens,
  so code must know DMA+ is there (this game: `REAL_HARDWARE` builds only).
- No register select: each byte is matched against the patterns below; bits
  in a base byte say which follow bytes come next, in bit order (D0 first).
- Plain zxnDMA (no Zilog pipeline quirks): on $6B a length N moves N bytes
  (0 moves 1).

| Group | Pattern | Sets |
|---|---|---|
| WR0 | `0HLhlDTT` (TT ≠ 00) | D: 1 = A→B; follow: A addr lo (l), hi (h), length lo (L), hi (H) |
| WR1 | `0TMMP100` | port A: MM 00 down, 01 up, 1x fixed; P 1 = I/O; T: timing byte follows |
| WR2 | `0TMMP000` | port B, the same; timing byte, then prescaler if its bit 5 |
| WR3 | `1xxxxx00` | enable (use WR6 $87 instead) |
| WR4 | `1MMIHL01` | mode MM 01 continuous, 10 burst; follow: B addr lo (L), hi (H). **Bit 7 must be 1; bit 4 must be 0** (bit 4 with no address bytes hangs the decoder until reset) |
| WR5 | `10AWR010` | $82 stop at the end, $B2 auto restart |
| WR6 | `1xxxxx11` | commands |

Common bytes: WR0 `$7D` (A→B, A addr + length), `$1D` (A addr only), `$05`
(A→B, nothing follows); WR1 `$14` mem up, `$24` mem fixed; WR2 `$10` mem up;
WR4 `$AD` continuous + B address, `$A1` continuous, no address, `$CD` burst.

Timing byte (WR1/WR2 follow): bits 1:0 = cycle length, 00 = 4, 01 = 3,
10 = 2. After $C3 both ports are 3 cycles: 6 a byte; 2+2 = 4 a byte.

## WR6 commands

| | |
|---|---|
| `$C3` | reset (see below) |
| `$C7` / `$CB` | port A / B timing back to 3 cycles |
| `$CF` | **load**: start addresses (WR0, WR4, $D7, $DB) to the working ones, counters reset. Needed before each `$87` |
| `$D3` | continue: counter reset, addresses kept |
| `$87` / `$83` | enable (start) / disable |
| `$8B`, `$A7`, `$BB nn`, `$BF` | status / read-back (mask order: status, counter lo, hi, A lo, hi, B lo, hi) |

`$C3` clears: the transfer, port timings (to 3), prescaler, auto restart,
**all DMA+ flags** (physical, 2D, transparent, fill, hidden), `$D7`/`$DB`,
row length / rows / strides, transparent colour, fill value. It does **not**
change the start addresses, direction, port types, address modes, transfer
mode, block length or read mask.

## DMA+ commands (port $6B only)

| Command | Follow | Meaning |
|---|---|---|
| `$D7 nn` | 1 | port A address bits 23:16 (physical mode) |
| `$DB nn` | 1 | port B address bits 23:16 |
| `$DF mm [Xlo Xhi Y]` | 1 (+3 with bit 4) | **mode flags**, every one at once (send the whole set) |
| `$E3 ll hh` | 2 | 2D: row length (bytes a row) |
| `$E7 ll hh` | 2 | 2D: number of rows |
| `$EB ll hh` | 2 | 2D: port A stride (row start to row start) |
| `$EF ll hh` | 2 | 2D: port B stride |
| `$F3 nn` | 1 | transparent colour |
| `$F7 nn` | 1 | fill value |
| `$FB` | 0 | gone (ignored) |

`$DF` flags:

| Bit | | |
|---|---|---|
| 0 | PHYSICAL | 22-bit SRAM addresses {ext 5:0, addr 15:0}, no MMU. RAM bank n at $40000 + n×$4000 (8K page p at $40000 + p×$2000). Banks 5 and 7 are block RAM: use MMU addresses for them |
| 1 | 2D | rows: row length × rows bytes (the WR0 block length is not used); 0 still moves one |
| 2 | TRANSPARENT | a source byte equal to `$F3` isn't written (addresses still move) |
| 3 | FILL | no reads, every byte the `$F7` value: twice as fast as a fixed source |
| 4 | XY | Layer 2 X,Y: Xlo Xhi Y follow; the port B address (and `$DB`) is worked out; **port B stride becomes 256** (until `$EF` or `$C3`). Needs PHYSICAL |
| 5 | HIDDEN | with XY: the bank in NextReg $13 (the back buffer) in place of $12 |
| 7:6 | 0 | |

Layer 2 X,Y addresses (NextReg $70 bits 5:4), base = $40000 + bank×$4000:

| $70 | Screen | Address | A 2D "row" |
|---|---|---|---|
| 00 | 256x192 | base + Y×256 + X (Xhi ignored: send 0) | a screen row: row length = width, rows = height |
| 01 | 320x256 | base + X×256 + Y (X 9 bits) | a screen **column**: row length = height, rows = width |
| 10 | 640x256 | as 01, X the byte column 0-319 | column |

Send the XY `$DF` **after WR4**, or use a WR4 with no address bytes (`$A1`):
a WR4 with a port B address overwrites the worked-out one.

Strides are added to the row's 24-bit start, so physical rows can cross 64K.
In physical mode addresses carry into the extended byte at $FFFF; otherwise
they wrap in 64K. Physical mode stays on until the next `$DF` / `$C3`: a later
MMU-address transfer must turn it off.

## Sequences

A full transfer (2.8 in the guide):

```
$83 $C3                  ; stop, reset
[$D7 a23 / $DB b23]      ; physical addresses
[$DF flags]              ; (with XY: after WR4, below)
[$E3 len $E7 rows $EB sa $EF sb]   ; 2D
[$F3 colour] [$F7 value]
WR0 (direction, A address, length)
WR1, WR2                 ; port A, port B
WR4                      ; mode, B address  ($A1: none, for XY)
[$DF flags+XY Xlo Xhi Y] ; the X,Y form here
[WR5 $82]
$CF $87                  ; load, go (continuous: the CPU waits)
```

A fill box at X,Y (zxnddma_examples.asm, example 2), 256x192:

```
db $83,$C3, $05, $14,$10, $A1, $82
db $E3 : dw width          ; row length (256x192: the width)
db $E7 : dw height         ; rows
db $F7, colour
db $DF, %00011011|HIDDEN?  ; PHYSICAL|TWO_D|FILL|XY (|HIDDEN $20)
dw x : db y
db $CF,$87
```

Short reload (settings stay until `$C3`; checked on an issue 5): for many
copies or boxes of the same kind send only what changes: `$E3`/`$E7` (size),
`$F7` (colour), `$1D lo hi` (a new source), then for an X,Y destination
`$DF flags Xlo Xhi Y`, else `$AD lo hi`; then `$CF $87`. `$D7` when the
source moves to another 64K.

## Notes that bite

1. Every setting stays until `$C3`. A fill or transparent flag left on
   applies to the next transfer: reset, or send a new `$DF`, before a
   different kind.
2. WR4 bit 7 = 1 (`$AD`, `$CD`); `$2D` is WR0. WR4 bit 4 = 0.
3. `$CF` before each `$87`, or the last transfer's addresses are used.
4. Hardware IM2: with NextReg $C0 bit 0 and a source chosen in $CC-$CE, the
   DMA waits while that interrupt is pending; under DI it never runs. This
   game keeps $CC-$CE at 0.
5. A long continuous transfer holds the bus: the 50 Hz interrupt waits for it
   (a full 256x128 fill: ~33K bytes). Split very large ones if sound suffers.
6. Speed: the CPU's LDIR is 21 T a byte; the DMA 6 (3+3 cycles), 4 at 2+2;
   fill mode halves it (no reads). Per OUT of the set-up, ~11-16 T (OTIR 21 T
   a byte).

## In this game

- `REAL_HARDWARE` (`build.bat hardware`) builds may use DMA+; the CSpect
  build may not (CSpect has no DMA+). tools/nexsim.py models the DMA+ the game
  uses (full addresses, 2D, transparency, fill, X,Y; `$C3`) and stops on a
  physical address below the RAM; `tests/test_hardware.py` assembles the
  hardware build and draws the render views with it: byte for byte the
  reference.
- Uses (README "Hardware build"):
  - `dma_fill` (layer2_cls.asm): fill mode.
  - The viewport clear (`clear_screen`, city.asm): 2D fill rectangles in
    32-row pieces (`dd_band`, `dd_rect`).
  - The faces' long spans: the DMA left in fill mode (`span_arm`), the
    colour per face by `$F7`; each span reloads length low, WR4 + address,
    `$CF $87`.
  - Block-filled faces (`fill_blocks`, level flight): runs of equal rows as
    `dd_rect` rectangles.
  - The figures (`spr_draw`, spr_rect.asm): one transfer each, `$DF`
    PHYSICAL|2D|TRANSPARENT, `$F3` 0, from ZPDATA/SPRITEHW.ZPG's rectangles
    (source stride the width, `$EB`), clipped by cutting the row length,
    rows and source start; mirrored by port B decrementing (WR2 `$00`): each
    row runs down from its start, the stride still added to the start.
    One per row instead (the plain file's runs) saved only ~2%: rows of at
    most 16 pixels don't pay for a reload each.
- `dd_rect` addresses the buffer being drawn **physically**:
  `$40000 + seg_base * $2000 + y * 256 + x`, port B stride 256 (`$EF`), not
  the X,Y form with HIDDEN: at a level's start the game clears both buffers
  before NextReg $13 is set, and $13 = 0 put the fill over pages 0-2 (the
  code). The X,Y form is only safe when $12 / $13 are certainly the target.
- After rectangles, `dd_spans` sends `$DF` fill alone (physical and 2D off)
  so the spans' MMU addresses work again; `occ_dma` (a memory copy) turns
  fill off round itself and back on.
- Each continuous burst holds the bus and the 50 Hz interrupt: rectangles are
  kept to 32 rows (8K).
- Emulator timing: nexsim charges `DMA_T` T a byte (default 2, fill half); the
  guide's 3+3 cycles are 6: compare designs with `DMA_T=6`.
