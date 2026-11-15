# CTC timers on the ZX Spectrum Next

A summary of the Next's CTC (counter/timer) and its interrupts, written to
answer one question for Z-Police: can hardware timers give better timing
than frame counters, and take work off the CPU (weapon cool-downs, movement
speeds, rates of fire and attack)?

Sources: the SpecNext wiki pages
[CTC](https://wiki.specnext.dev/CTC),
[Board feature control](https://wiki.specnext.dev/Board_feature_control) and
the register pages it links to (Interrupt Control $C0, Interrupt Enable
$C4-$C6, Interrupt Status $C8-$CA, DMA interrupt enable $CC-$CE, Hw IM2
mode, Video Line Interrupt $22/$23, CPU Speed $07, Video Timing $11). The
wiki says the CTC is "a standard Zilog part" and points to Zilog's Z80 CTC
manual (UM0081, ps0181.pdf) for the rest. Also Mike Dailly's CSpect
example, `C:\CSpect\Z80Timers\timer.asm` (reviewed below), a CTC timer
interrupting a DMA transfer, and taylorza's
[`ctctest.asm`](https://gist.github.com/taylorza/5e0cd21acaba43e5369bb5270ed29d33),
a beeper tone from a CTC interrupt. Facts marked *(Zilog)* come from
that standard part, not from the Next wiki. Facts marked *(unconfirmed)*
are not stated anywhere I read and should be checked on a real Next.

## In short

- The Next has a Z80 CTC: up to 8 down-counting channels on ports
  `$183B`-`$1F3B`. The wiki also says it is "temporarily reduced to four
  channels". Use channels 0-3 to be safe.
- A channel can interrupt when it reaches zero. CTC interrupts are **off by
  default**: NextReg `$C5` is 0 after a reset. Our start-up code does not
  turn them off; it never writes `$C5`. Writing `$CD` = 0 only stops a CTC
  interrupt from breaking into a DMA transfer.
- The CTC clock does not follow the CPU speed (NextReg `$07`). It is the
  28 MHz system clock: the CSpect worked example (`timer.asm`, reviewed
  below) works its time constants out from 28,000,000. That clock is
  28.0 MHz in the standard and HDMI timing, and up to 33 MHz in the VGA 1-6
  timings.
- **For Z-Police, a timer would not save CPU time.** A cool-down countdown
  costs a few T-states a frame, so there is little to take off the CPU. The
  real benefit is **timing that doesn't depend on the frame rate**. The game
  logic runs once per rendered frame, and its speeds assume 14 fps
  (`NOMINAL_FPS`). Where the frame rate drops, the whole game slows down.
  Where it rises, everything speeds up: facing a wall it runs at 34-46 fps,
  2-3 times too fast.
- **The game already has a real-time clock**: `isr_ticks`, counted at 50 Hz
  by the frame interrupt. The devil's charge and the PREPARE FOR COMBAT
  pause already use it. A 20 ms resolution is fine for cool-downs and
  attack rates. A CTC is only needed for finer timing: smoother movement at
  high frame rates, profiling, or sound updated more often than 50 Hz.

## The CTC

### Channels and ports

| Channel | Port |
|---|---|
| 0 | `$183B` |
| 1 | `$193B` |
| 2 | `$1A3B` |
| 3 | `$1B3B` |
| 4-7 | `$1C3B`-`$1F3B` (if the core has 8) |

The port mask is `%0001 1XXX 0011 1011`, read and write, so address bits
10-8 select the channel. Writing to a channel's port sends it a control
word or a time constant. Reading the port returns the channel's current
down-counter *(Zilog)*.

### Clock

- "The rate of clock input to the CTC's timer is not affected by the value
  in the NextReg 7": 3.5, 7, 14 and 28 MHz CPU all give the same timer
  rate.
- The wiki gives no CTC clock frequency. The CSpect example's formula is
  `value = (28000000/16)/freq` or `(28000000/256)/freq`: a 28 MHz input,
  the system clock clk28. That clock depends on the video timing (NextReg
  `$11`, set in config mode only):

  | `$11` | Timing | clk28 |
  |---|---|---|
  | 0 | Base VGA (HDMI compatible) | 28,000,000 Hz |
  | 1 | VGA 1 (HDMI compatible) | 28,571,429 Hz |
  | 2 | VGA 2 | 29,464,286 Hz |
  | 3 | VGA 3 | 30,000,000 Hz |
  | 4 | VGA 4 | 31,000,000 Hz |
  | 5 | VGA 5 | 32,000,000 Hz |
  | 6 | VGA 6 | 33,000,000 Hz |

  So a timer runs up to 18% fast on a VGA 6 machine (assuming the CTC
  follows clk28 in every timing; the wiki doesn't say). The video frame rate changes with the timing too:
  the wiki measured 49.3 Hz to 58.1 Hz in 50 Hz mode across VGA 0 to 6. So
  neither the frame interrupt nor the CTC is an exact clock. For a game
  that doesn't matter, but measure the CTC against the frame interrupt once
  on real hardware to confirm its clock.

### Control word *(Zilog, the bits the Next wiki doesn't list)*

A byte written to a channel with bit 0 set is a control word:

| Bit | Name | 0 | 1 |
|---|---|---|---|
| 7 | Interrupt | off | on: interrupt when the count reaches 0 (ZC/TO) |
| 6 | Mode | timer: counts the prescaled system clock | counter: counts edges on CLK/TRG |
| 5 | Prescaler (timer mode) | ÷16 | ÷256 |
| 4 | Clock/trigger edge | falling | rising |
| 3 | Timer trigger | starts as soon as the time constant is loaded | waits for a CLK/TRG edge |
| 2 | Time constant follows | no | yes: the next byte written is the time constant |
| 1 | Reset | carry on | software reset: stop the channel |
| 0 | Control word | 0: an interrupt vector byte (see below) | 1: control word |

- **Time constant:** the byte after a control word with bit 2 set: 1-255,
  with 0 meaning 256 *(Zilog)*. The channel counts down from it and
  reloads it each time it reaches 0. Each time it reaches 0 it gives one
  ZC/TO pulse and, if bit 7 is set, an interrupt.
- **Timer period** = prescaler × time constant clock cycles. At 28 MHz:
  - ÷16 gives 1.75 MHz, so 1 tick from 1.75 MHz down to 6,836 Hz (constant 256).
  - ÷256 gives 109,375 Hz, so down to 427.2 Hz (constant 256).

  Slower rates than about 427 Hz need two channels chained (below).
- **Vector byte:** on a real Z80 CTC a byte with bit 0 = 0 sets the IM 2
  vector. On the Next, hardware IM 2 mode makes the vector itself (see
  "Interrupts"), so there is no need to send one.

The Next wiki adds these points about resets:
- After a hard reset, a channel ignores control words until it gets one
  with bit 2 = 1.
- A control word with bit 1 = 1 is a soft reset. With bit 2 = 0 the channel
  stops (hard reset). With bit 2 = 1 it waits for a time constant, then
  runs.
- Changing bit 4 (the edge) counts as a clock edge: a timer waiting for a
  trigger starts, and a counter counts one.
- ZC/TO is asserted for one clock cycle, not for as long as the count is 0.
- To put a channel of unknown state into a known one, write a soft reset
  control word **twice** with bit 2 = 0.

### Chaining channels

"The ZC/TO output of each channel is fed into the CLK/TRG input of the
succeeding channel so that time and count periods can be cascaded."
Channel 0 as a timer can drive channel 1 as a counter, and so on.
(Channel 3's ZC/TO, halved, also clocks the joystick in its IO mode.)

Example rates at 28 MHz (all exact). The period is prescaler × constant /
28 MHz, and the rate is 28 MHz / (prescaler × constant):

| Rate | Channel 0 (timer) | Channel 1 (counter) |
|---|---|---|
| 7,812.5 Hz (0.128 ms, about every 2 scan lines) | ÷256, constant 14: the CSpect example | (not needed) |
| 625 Hz | ÷256, constant 175 | (not needed) |
| 10 kHz | ÷16, constant 175 | (not needed) |
| 1 kHz | ÷16, constant 175 (10 kHz) | constant 10 |
| 200 Hz | ÷16, constant 175 (10 kHz) | constant 50 |
| 100 Hz | ÷16, constant 175 (10 kHz) | constant 100 |
| 50 Hz | ÷16, constant 175 (10 kHz) | constant 200 |

### Example: a 1 kHz tick on channel 1

```
CTC0            equ $183B
CTC1            equ $193B

ctc_init:
        ld bc,CTC0                      ; channel 0: a 10 kHz timer, no
        ld a,%00000011                  ; interrupt (reset twice: a known
        out (c),a                       ; state)
        out (c),a
        ld a,%00000111                  ; timer, /16, auto, constant follows,
        out (c),a                       ; reset, control word
        ld a,175                        ; 1.75 MHz / 175 = 10 kHz
        out (c),a
        ld bc,CTC1                      ; channel 1: counts channel 0's
        ld a,%00000011                  ; pulses
        out (c),a
        out (c),a
        ld a,%11000111                  ; interrupt, counter, constant
        out (c),a                       ; follows, reset, control word
        ld a,10                         ; 10 kHz / 10 = 1 kHz
        out (c),a
        nextreg $C5,%00000010           ; CTC channel 1's interrupt on
        ret
```

To stop it, write `%00000011` (a reset) to the channel and clear its bit
in `$C5`.

Its interrupt routine should clear the channel's status bit:
`nextreg $C9,%00000010` for channel 1, writing 1 to clear. The CSpect
example does this first thing in its routine. In hardware IM 2 mode the
status otherwise stays set.

## The CSpect worked example (`C:\CSpect\Z80Timers\timer.asm`)

This is Mike Dailly's CSpect example of a CTC timer interrupting a running
DMA transfer:
- channel 0 interrupts about every 2 scan lines and flips the border
  colour;
- meanwhile the main loop restarts a DMA copy of a screen image every
  frame.

What it does, with notes:

| Line | Code | What it does |
|---|---|---|
| 27 | `NextReg 7,3` | 28 MHz CPU. The CTC's rate doesn't depend on it. |
| 29-33 | `$C0` = (old `$C0` and 8) or `%10100001` | **Hardware IM 2 mode** (bit 0), vector base `$A0` (bits 7-5 = 101), the stackless NMI setting kept (bit 3). |
| 35 | `$C4` = 2 | Only the line interrupt on (bit 1). The ULA frame interrupt and the expansion bus are off. (The comment says "disable all".) |
| 36-38 | `$C5`, `$C6` = 0 | CTC and UART interrupt enables cleared. `$C7` is not a documented register. |
| 40-43 | `$C8` = 3, `$C9`-`$CB` = `$FF` | Clear any pending status (write 1 to clear). `$CB` is not a documented register. |
| 45-47 | `$CC` = 2, `$CD` = 1, `$CE` = 0 | The line interrupt and **CTC channel 0 may interrupt a DMA transfer**. This is the point of the example: without it, the ticks would wait for the 6,912-byte copy to finish. |
| 50-51 | `$23` = `$80`, `$22` = 6 | Line interrupt at line 128 (bit 1), the ULA interrupt disabled (bit 2). |
| 53-56 | `I` = `$D0`, `IM 2`, `EI` | A 257-entry table at `$D000`, every entry `$D2D2`, which jumps to `ctc_irq`: the same trick as Z-Police's table. So every source runs the same routine. |
| 60-62 | control word `%10100011` | Bit 7 interrupt on, bit 6 = 0 timer, bit 5 = 1 ÷256, bit 1 soft reset, bit 0 control word. |
| 64-65 | time constant 14 | 14 × 256 / 28 MHz = 0.128 ms. |
| 174 | `nextreg $c9,255` in the routine | Clears every CTC channel's status first. |
| 189-190 | `ei` / `reti` | Ends with RETI, which hardware IM 2 mode needs. |

**Corrections to the example's comments:**
- **The rate:** 14 × 256 / 28,000,000 = 0.000128 s = **0.128 ms**, so the
  rate is 1 / 0.128 ms = **7,812.5 Hz**, not 7,850 Hz. "About every 2
  scan lines" is right: a line is 64 µs.
- **"time constant = 256 (0)"** is a stale comment: the constant written
  is 14.
- **The bit comments for the control word are swapped:**
  - "Bit6(1)=timer mode" is wrong: bit 6 = 0 is the timer, and the value
    has bit 6 = 0.
  - "Bit5(0)=prescaler of *256" is wrong: bit 5 = 1 is ÷256, and the
    value has bit 5 = 1.

  The value itself is right: a timer with the ÷256 prescaler.
- **Bit 2 (time constant follows) is 0** in `%10100011`, yet a time
  constant follows. In the Zilog part, and by the Next wiki's reset rules
  (a soft reset with bit 2 = 0 is a hard reset: the channel stops), the
  `14` would then be taken as a vector byte (bit 0 = 0) and the channel
  would stay stopped. The comment "Bit1(1)= Soft reset (constant must
  follow)" suggests CSpect treats bit 1 as "a constant follows". **On real
  hardware set bit 2 too: `%10100111`.** That is right either way.
- **`$C5` is written 0 before the channel starts,** and the interrupts
  still come. Either CSpect doesn't check `$C5`, or the control word's bit
  7 and the channel's `$C5` bit are the same enable *(unconfirmed)*. Set
  both, as `ctc_init` above does.

**The vectors in this example.** With base `$A0` the vectors are:
- line interrupt `$A0`;
- CTC channel 0 `$A6` (source 3 × 2);
- ULA `$B6`.

All three land in the 257-entry table on `$D2D2`, so the one routine
can't tell them apart. The line interrupt it enables also flips the
border. To give the CTC its own routine, put a different address in the
table's word at `I`×256 + `$A6`.

## A second example: a beeper tone from CTC channel 0

[taylorza's `ctctest.asm`](https://gist.github.com/taylorza/5e0cd21acaba43e5369bb5270ed29d33)
(gist "ZX Spectrum Next Samples") is a minimal, clean set-up:
- channel 0 interrupts about 439 times a second;
- its routine flips the beeper bit (bit 4 of port `$FE`) each time, which
  plays a square-wave tone.

It is a better model than the CSpect example in several ways.

**Set-up, in order:**

| Code | What it does |
|---|---|
| `nextreg 7,0` | A 3.5 MHz CPU. The tone is the same at any CPU speed: the CTC's clock doesn't follow `$07`. |
| `nextreg $c0,(ivt & %11100000) \| 1` | Hardware IM 2 mode. The vector base comes from the table's own address (its low byte's top 3 bits), so the table can sit anywhere 32-byte aligned. |
| `nextreg $c4,%00000000` | The ULA frame interrupt and the expansion bus off: only the CTC interrupts. |
| `nextreg $c5,%00000001` | CTC channel 0's interrupt **enabled in `$C5`**, explicitly. The CSpect example cleared `$C5` and relied on the control word. |
| `nextreg $c6,%00000000` | UART interrupts off. |
| `out ($183B),1` | "Disable channel 0": a control word with no bits but bit 0. |
| `out ($183B),%10100101` | Bit 7 interrupt, bit 6 = 0 **timer**, bit 5 = 1 ÷256, bit 2 a time constant follows, bit 0 control word. Bit 1 (reset) = 0. |
| `out ($183B),249` | Time constant 249. |
| `ld i,high ivt` / `im 2` / `ei` | The table's page in `I`, then IM 2. |

**The table:**

```
        align 32
ivt:    dw inthandler           ; 0  line interrupt
        dw inthandler           ; 1  UART0 Rx
        dw inthandler           ; 2  UART1 Rx
        dw ctc0handler          ; 3  CTC channel 0
        dw inthandler           ; 4-10  CTC channels 1-7
        ...                     ; 11 ULA, 12-13 UART Tx, 14-15 spare
```

It has 16 words (32 bytes), one per source in the hardware IM 2 order.
In hardware IM 2 mode the vector is always even and within the 32 bytes
from the base, so this replaces the 257-entry, `$xyxy` trick that pulse
mode needs. The unused entries point at a routine that is just `ei` /
`reti`.

**The routine:**
- `push af`;
- flip bit 4 of a stored border/beeper byte and `out ($FE),a`;
- `pop af`;
- `ei` / `reti`.

**The numbers:**
- interrupt rate: 28,000,000 / (256 × 249) = **439.3 Hz**, one every
  2.28 ms;
- tone: each interrupt flips the beeper, so the square wave is half that,
  **219.6 Hz**, close to A3 (220 Hz). 249 was clearly chosen for that note.

**Notes:**
- **The comment on the control word says "counter mode",** but bit 6 is 0:
  it is a timer, as it should be, counting the prescaled system clock.
  (Counter mode would count CLK/TRG edges, which for channel 0 come from
  nothing.) The comment also lists more fields than there are bits; go by
  the value.
- **The "disable" byte `1`** is a control word with bit 1 (reset) clear.
  To be sure of stopping a channel in an unknown state, the wiki's recipe
  is a soft reset, `%00000011`, written twice. `%10100101` then starts it,
  because it has bit 2 set and a time constant follows.
- **It doesn't clear `$C9`** in its routine, and works. In hardware IM 2
  mode the RETI is what lets the channel interrupt again. Clearing the
  status bit, as the CSpect example does, is still harmless and keeps
  `$C9` meaningful if anything polls it.
- **This is how the Next can play tones or samples on the beeper (or a
  DAC) without the frame interrupt.** For Z-Police the AY chips are
  better, but the same pattern is how a CTC tick would drive sound at a
  rate of its own.

### What the two examples agree on

- Hardware IM 2 mode: `$C0` bit 0 = 1, with the vector base in bits 7-5.
- Every routine ends `ei` / `reti`.
- Time constants worked out from a 28 MHz clock: rate = 28,000,000 /
  (prescaler × constant), whatever the CPU speed.
- For the control word, go by the values (timer = bit 6 clear, ÷256 = bit
  5 set), not the comments: both examples' comments get these bits wrong.
- Enable the channel in `$C5` **and** set bit 7 of its control word, and
  set bit 2 whenever a time constant follows.

## Interrupts

### Two modes (NextReg `$C0`, bit 0)

- **Pulse mode** (`$C0` bit 0 = 0, the default, and what Z-Police uses):
  every source pulls /INT low for about 30 cycles. In IM 2 the vector is
  whatever byte is on the bus, which is why Z-Police has a full 256-word
  table pointing at one routine. With CTC interrupts on as well, that one
  routine would run for the ULA frame and for the CTC alike. It could only
  tell them apart by reading the status registers ($C8, $C9). It would
  also count `isr_ticks` and play the sound at the CTC's rate as well.
- **Hardware IM 2 mode** (`$C0` bit 0 = 1): each source has its own vector
  and its own state machine. The vector is:

  | Bits 7-5 | Bits 4-1 | Bit 0 |
  |---|---|---|
  | `$C0` bits 7-5 | the source | 0 |

  | Source (bits 4-1) | Vector with `$C0` bits 7-5 = 0 | Priority |
  |---|---|---|
  | 0 line interrupt | `$00` | highest |
  | 1 UART0 Rx | `$02` | |
  | 2 UART1 Rx | `$04` | |
  | 3-10 CTC channels 0-7 | `$06`-`$14` | |
  | 11 ULA (the frame) | `$16` | |
  | 12 UART0 Tx | `$18` | |
  | 13 UART1 Tx | `$1A` | lowest |

  (The expansion bus is lowest of all; with no vector from it, `$FF`.)

  In this mode:
  - A source interrupts on an edge, then waits for the **RETI** that ends
    its routine before it can interrupt again. Every routine must end with
    `RETI`, not `RET`. Z-Police's routine already ends `ei` / `reti`.
  - Further events from the same source while its routine hasn't returned
    don't stack: "you're not going to see more than the one current
    interrupt". A tick that comes while interrupts are off, or during a long
    DMA transfer, is lost if a second one follows before it's taken.

The wiki's `$C0` layout (soft reset value `$00`):

| Bits | Meaning |
|---|---|
| 7-5 | the programmable part of the IM 2 vector |
| 4 | reserved, must be 0 |
| 3 | stackless NMI (the return address goes to `$C2`/`$C3`) |
| 2-1 | the current interrupt mode (read only) |
| 0 | 1: hardware IM 2 mode, 0: pulse mode |

### Enables, status and DMA

| NextReg | Name | Bits | Default |
|---|---|---|---|
| `$C4` | Interrupt Enable 0 | 7 expansion bus /INT, 1 line, 0 ULA | `$81` |
| `$C5` | Interrupt Enable 1 | bit n: CTC channel n ZC/TO | `$00`: all CTC interrupts off |
| `$C6` | Interrupt Enable 2 | UART Rx/Tx bits | `$00` |
| `$C8` | Interrupt Status 0 | 1 line, 0 ULA | not stated |
| `$C9` | Interrupt Status 1 | bit n: CTC channel n | not stated |
| `$CA` | Interrupt Status 2 | the UART bits | not stated |
| `$CC` | DMA interrupt enable 0 | 7 NMI, 1 line, 0 ULA | `$00` |
| `$CD` | DMA interrupt enable 1 | bit n: CTC channel n | `$00` |
| `$CE` | DMA interrupt enable 2 | the UART bits | `$00` |

- **Status registers:** a bit set means the source interrupted, or one is
  pending. Write 1 to a bit to clear it. In hardware IM 2 mode it reads set
  until the pending interrupt is taken.
- **Polled mode:** a source with its interrupt disabled "enters a polled
  mode". Its status bit still sets, so the main loop can see that a channel
  has reached 0 at least once since the bit was cleared, without
  interrupts. That tells you it happened, not how many times.
- **DMA:**
  - `$CC`-`$CE` choose which interrupts may stop a DMA transfer, in
    hardware IM 2 mode only. Z-Police sets all three to 0, so a long DMA
    burst delays every interrupt.
  - Several CTC interrupts during one transfer arrive as one. Z-Police
    keeps bursts short for the sound's sake: `DV_RUN_MAX`, 8K at most.
  - If a CTC channel may interrupt DMA, each interruption lets the main
    program run one instruction, and the DMA can't take the bus back until
    the routine's RETI.
- **Line interrupt** (`$22`, `$23`): a raster interrupt at a chosen line,
  9 bits (`$22` bit 0 high, `$23` low), on with `$22` bit 1, aliased in
  `$C4`. It's another real-time source, but tied to the display.

## What it would mean for Z-Police

### How the game keeps time now

The main loop renders as fast as it can: about 13-15 fps in the streets,
more when little is in view. The game logic runs once per rendered frame:
- Speeds are units per frame at the 14 fps the game was tuned for
  (`NOMINAL_FPS`: `BULLET_STEP`, `ROCKET_STEP`, `FB_STEP`, the zombies'
  steps, `HUMAN_RUN`).
- Rates are counts of frames:
  - `gun_wait` with `GUN_INTERVAL` 4, `CHAIN_INTERVAL` 1, `ROCKET_INTERVAL`
    7, `BOMB_INTERVAL`;
  - the reloads (`ROCKET_RELOAD` 15 ...);
  - the zombies' hits (`ZHIT_FRAMES` 5);
  - a lich's shots (`LICH_WAIT`/`LICH_FRAMES`);
  - landing (`DISEMBARK`);
  - particle lives (`PART_LIFE`).

So game time runs at the frame rate. A busy view slows everything: the
zombies, the rounds and the cool-downs. A sparse one speeds it up: at 28
fps everything happens twice as fast.

There is already one real-time clock: the 50 Hz frame interrupt counts
`isr_ticks`. The devil's charge (`DV_T0`) and PREPARE FOR COMBAT
(`WPREP_TICKS`) use it.

### Will timers take work off the CPU?

Hardly. A timer only counts. The work (moving, drawing, testing hits) still
runs on the CPU, and drawing takes most of the frame. Counting down a
cool-down costs a few T-states a frame. Moving countdowns into interrupt
routines only moves that cost. A 1 kHz interrupt costs roughly 100-200 T
each, 0.4-0.7% of a 28 MHz CPU, so it isn't free either.

The small real saving is replacing countdowns kept per record (decremented
for every monster every frame) with **time stamps**: "ready at tick N",
compared only when it matters.

### What real-time timing would fix

Gameplay speed would no longer depend on the frame rate. In order of value
for effort:

1. **Rates and cool-downs from `isr_ticks` (no CTC needed).** Keep a "ready
   at" tick instead of a frame countdown:

   ```
   ; fire if now - ready >= 0 (16-bit, safe across the wrap while the
   ; times are within 32767 ticks: 11 minutes at 50 Hz)
           ld hl,(isr_ticks)
           ld de,(gun_ready)
           or a
           sbc hl,de
           jp m,.not_yet
           ...fire...
           ld hl,(isr_ticks)
           ld de,GUN_TICKS                 ; the interval in 20 ms ticks
           add hl,de
           ld (gun_ready),hl
   ```

   A 20 ms resolution is finer than any interval used today: at 14 fps a
   frame is 71 ms. This would cover rates of fire, reloads, the zombies'
   hits, a lich's shots, disembarking, wave timings and the attack rates.
   Read `isr_ticks` with interrupts off, or read it twice and compare, so
   the two bytes match.
2. **Movement by elapsed time.** Each frame:
   - work out the ticks since the last frame (`dt`), clamped to, say, 1-8
     at 50 Hz so a stall doesn't teleport anything;
   - move each thing by speed × `dt`, with speeds now in units per tick
     (`MUL D,E` is cheap on the Z80N).

   At 14 fps `dt` is mostly 3 or 4 ticks at 50 Hz: the 20 ms grain is
   uneven against a 71 ms frame, so movement jitters about ±15%. A **CTC
   tick at 200 Hz-1 kHz** smooths that: ±1-4%.

   Caution: fast things move further per frame at low frame rates, so the
   hit tests must sweep the whole step, as the rounds' already do.
3. **Profiling on real hardware.** A free-running 10 kHz CTC tick (or
   reading a channel's counter) times parts of the frame in 0.1 ms steps
   without the emulator. It would add to `DRAW_FPS`.
4. **Sound.** The players run at the 50 Hz frame rate. A CTC channel could
   drive smoother envelopes, or sample playback, at a rate of its own.

### What would have to change to use a CTC tick

- **Hardware IM 2 mode** (`nextreg $C0,%xxx00001`), so the CTC has its own
  vector:
  - In `im2_table` (256 words at `I`×256), put the CTC routine's address
    in the channel's entry: with `$C0` bits 7-5 = 0, channel 1 is vector
    `$08`, the word at `im2_table+8`.
  - The frame interrupt keeps `im2_routine` at `$16`.
  - The other entries can stay as they are. Or replace the 257-entry
    table with a 32-byte, 16-entry one, as in taylorza's example, which
    frees most of a page in the zombie page.
- **A minimal CTC routine,** resident in the zombie page with the table:
  - switch to its own stack first, as `im2_routine` does, because the span
    filler borrows SP;
  - count a word, `ctc_ticks`;
  - no paging, no alternate registers;
  - end with `ei` / `reti`.
- **The places interrupts are off,** where ticks are lost or late:
  - the span filler's last PUSH (very short);
  - esxDOS calls (loading: no game time passes anyway);
  - long DMA bursts. Allow channel n in `$CD` if a tick must never be
    dropped, at the cost of the DMA giving way.

  At 1 kHz a tick is about 28,000 T at 28 MHz, so the short windows are
  safe.
- **The CTC must be stopped and its interrupt turned off** wherever the
  game leaves the play loop, if the menus shouldn't count, or else the
  counter just runs on harmlessly.
- **Check the clock on real hardware:** count CTC ticks over 50 frame
  interrupts (expect 1000 at 1 kHz on 28 MHz, VGA 0).

### Suggested order

1. Move the weapon rates, reloads and attack rates to `isr_ticks` time
   stamps. This needs no new hardware set-up and is testable in the
   emulator.
2. Move movement to elapsed ticks, first with `isr_ticks`. If 50 Hz proves
   too coarse, add a CTC channel at 200 Hz-1 kHz in hardware IM 2 mode,
   and model it in `tools/nexsim.py` first.
3. Keep the CTC for profiling and, later, sound.
