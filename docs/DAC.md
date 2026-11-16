# The ZX Spectrum Next's 8-bit DACs

What the Next's DACs are, how samples get to them, by the CPU, a CTC
interrupt, the DMA or the Copper, and what that would mean for Z-Police.
It is the companion to docs/CTC.md (timers and interrupts) and
docs/ZXNDDMA.md (the DMA).

Sources:
- the SpecNext wiki: [SpecDrum/DAC](https://wiki.specnext.dev/SpecDrum/DAC),
  NextRegs `$2C`, `$2D`, `$2E` (the DAC mirrors), `$08` (Peripheral 3) and
  [DMA](https://wiki.specnext.dev/DMA);
- em00k's examples, linked from the wiki:
  - [zxnext-simple-dma](https://github.com/em00k/zxnext-simple-dma)
    (`dms_sample_bank.asm`): samples played by the DMA;
  - [playwav32](https://github.com/em00k/playwav32) (`src/main.asm`,
    `src/interrupts.asm`): a stereo WAV played from the SD card by CTC
    interrupts;
- the Klive IDE book's [DAC chapter](https://kliveide.net/en/book/18-dac/).
  Its text could only be read as a summary, and the chapter calls itself
  unfinished. Its claims are marked *(Klive, unconfirmed)* where they
  aren't in the other sources.

Facts marked *(inferred)* are worked out here, not stated by a source.

## In short

- **The hardware:** four 8-bit DACs: A and B on the left, C and D on the
  right.
  - **Feeding them:** each is fed by writing a byte to its port, or to a
    "mirror" NextReg (`$2C` left, `$2D` A+D, `$2E` right).
  - **Enabling them:** they are off until NextReg `$08` bit 3 is set.
    That bit is 0 at a hard reset, and Z-Police never sets it.
  - **Samples:** unsigned: `$80` is silence.
- **Sample rate:** the DAC has no clock of its own. The sample rate is the
  rate the bytes are written at. Four ways:
  1. **A CPU loop:** simplest, and it uses the whole CPU.
  2. **A CTC interrupt** writing one sample (or a stereo pair) each time:
     playwav32 plays 31,250 Hz stereo this way. It's independent of the
     CPU speed and leaves the DMA and Copper free, but costs an interrupt
     per sample.
  3. **The DMA**, in burst mode, its own prescaler setting the rate
     (`875 kHz / prescaler`): almost no CPU, but it needs the DMA to
     itself while it plays.
  4. **The Copper** writing `$2D` per raster line: tied to the video
     timing. The wiki's example is "TBC".
- **"The CTC controlling the DMA":** in the working examples the CTC and
  the DMA don't drive each other directly:
  - **Per-sample pacing:** the DMA's prescaler sets the rate itself.
  - **The CTC's jobs** are to time the work around it (refilling or
    restarting a buffer). Separately, NextReg `$CD` can let a CTC
    interrupt break into a running DMA transfer, so a CTC-timed player
    keeps time while the DMA is busy.
  - **The Klive claim** that a CTC channel's pulse *triggers* the DMA
    through `$CD` is unconfirmed: the wiki documents `$CD` as "CTC
    interrupts that can override DMA", not as a trigger.

## The DACs

### Channels, ports and mirrors

"The Spectrum Next has 4 8-bit DAC ports" (the wiki): DACs A and B on the
left, C and D on the right ("SoundDrive ... 2 x Left 2 x Right"). Writing
a byte to a port sets the DAC(s) it reaches:

| Ports | DAC | Side |
|---|---|---|
| `$1F`, `$F1`, `$3F` | A | left |
| `$0F`, `$F3` | B | left |
| `$4F`, `$F9` | C | right |
| `$5F` | D | right |
| `$DF` (Specdrum), `$FB` (Covox) | A and D | both: mono |
| `$B3` | B and C | both: mono |

- **The ports' decoding:** the wiki gives only the low byte. The DMA
  example writes to `$FFDF` (16-bit). With `out (c),a` keep B set, as
  for any port.
- **Compatible modes:** the wiki doesn't say which compatible mode
  (Soundrive 1/2, GS Covox) each port belongs to. Writing to `$DF` / `$FB`
  is the simple mono choice.

The **mirror NextRegs** (`nextreg reg,a`, or the Copper's MOVE):

| NextReg | Writes | Reads | Soft reset |
|---|---|---|---|
| `$2C` | DAC B (left) | the current I2S (Pi) left sample's MSB | `$80` |
| `$2D` | DACs A and D (mono; "the Specdrum port $DF") | the I2S sample's latched LSB | `$80` |
| `$2E` | DAC C (right) | the current I2S right sample's MSB | `$80` |

So the stereo pair the mirrors give is B (`$2C`, left) and C (`$2E`,
right).

playwav32's comments call `$2E` "left" and `$2C` "right", the other way
round from the wiki's register names. Check by ear which way round it is.

### Enabling them

NextReg `$08` (Peripheral 3) bit 3: "Enable 8-bit DACs (A,B,C,D) (hard
reset = 0)". Its other sound bits:
- bit 4: the internal speaker (1 at a hard reset);
- bit 1: TurboSound;
- bit 5: AY stereo ABC / ACB.

Z-Police's `initgame` ORs `%01010010` into `$08`: no contention, the
speaker, TurboSound. So **the DACs are off**: playing samples needs
`%00001000` too.

Neither em00k example writes `$08`: they rely on it being set already,
or, more likely, on the menu or NextZXOS having set it *(inferred)*.

### Samples

- Unsigned 8-bit: `$80` is the middle, silence.
- "The Next is capable of playing 8 bit mono or stereo wav files at up to
  32 KHz sample rate" (the wiki).
- Make them with ffmpeg: `ffmpeg -i input.wav -f wav -acodec pcm_u8 -ac 1
  -ar 15625 output.wav` (`-ac 2` for stereo). Strip the WAV header (44
  bytes) for raw data, or skip it when loading.
- Memory: at 15.6 kHz, a second of mono is 15.6K, about two 8K pages.

## Playing samples

The DAC plays whatever was written last, so the rate is the rate of
writing.

### 1. A CPU loop

Write a byte, wait a counted number of T-states, repeat. Simple and
exact, but the CPU does nothing else, and the count depends on the CPU
speed (NextReg `$07`) and on contention. Only for a title jingle, or a
sound while the screen is static.

### 2. A CTC interrupt per sample (playwav32)

A CTC channel interrupts at the sample rate, and the routine writes the
next sample (a stereo pair) and steps the pointer.

playwav32, "8Bit 31250Hz Stereo":
- **The timer:** channel 0 at `$183B`, control word `%10000101`
  (interrupt, timer, ÷16, time constant follows), time constant
  `sampletiming` = 56: "1750000 / 31250 = 56, 1750000 / 15625 = 112".
  So the ÷16 timer counts 1.75 MHz (28 MHz / 16).
- **The interrupts:**
  - `$C0` = `%00001001` (hardware IM 2 mode, stackless NMI);
  - `$C5` = `%00000001` (CTC channel 0);
  - `$C4` = the line interrupt.
  - `$CC`-`$CE` = 0: "No DMA".
- **The routine (`ctc0`):** `nextreg $2E,a` then `nextreg $2C,a`: two
  bytes, left and right, each interrupt. Mono would be one `nextreg $2D,a`.
- **Streaming:** a 2K ring at `$C000`, two 1K halves.
  - When the pointer crosses into one half, the other is flagged for
    reloading.
  - A second channel (channel 1, ÷256, constant 192: about 569 Hz) reads
    the flagged half from the file with esxDOS `F_READ`.
  - So the sound plays straight off the SD card, for any length.
- **Stopping:** `di`, the CTC's interrupt off (`$C5` = 0), `$C0` and `$C4`
  back as they were.

**Rates:** the rate is 1,750,000 / constant (÷16), or 109,375 / constant
(÷256), at 28 MHz, whatever the CPU speed (docs/CTC.md):

| Rate | ÷16 constant |
|---|---|
| 31,250 Hz | 56 |
| 21,875 Hz | 80 |
| 15,625 Hz | 112 |
| 10,938 Hz | 160 |
| 7,813 Hz | 224 |

**Cost:** an interrupt, a `nextreg` or two and the pointer, about 100-150
T-states a sample *(inferred)*. At 15.6 kHz that's 1.6-2.3 million
T-states a second, 6-8% of a 28 MHz CPU. At 31.25 kHz stereo, double.

**Pitfalls:**
- With interrupts off a sample is late, and in hardware IM 2 mode a second
  one in that time is lost: a click.
- During a long DMA transfer no interrupt is taken at all, unless `$CD`
  lets that CTC channel break into it (docs/CTC.md, "Enables, status and
  DMA").

### 3. The DMA with its prescaler (zxnext-simple-dma)

The zxnDMA (port `$6B`) copies the sample from memory to the DAC port, a
byte at a time, paced by its own **prescaler**:

> "The rate of transfer is given by the formula 'Frate = 875kHz /
> prescalar' ... selecting a sample rate of 16kHz would mean setting the
> prescalar value to 55." "This sample period is constant across changes
> in CPU speed." (the wiki)

- **The 875 kHz:** this is 28 MHz / 32 *(inferred)*, "a nominal value
  assuming a 28MHz system clock". It varies with the video timing (NextReg
  `$11`), as the CTC's clock does.
- **Burst mode:** "the DMA will give up any waiting time to the CPU so
  that the CPU can run while the DMA is idle". So between samples the CPU
  runs. In continuous mode it holds the bus throughout. Use burst.

The DMA program, sent with `otir` to port `$6B` (em00k's
`dms_sample_bank.asm`, his comments):

| Byte(s) | Register | Meaning |
|---|---|---|
| `$C3` | WR6 | reset |
| `$C7` | WR6 | reset port A timing |
| `$CA` | | "port B timing same as port A" (by its bits, a WR5-style byte: unclear) |
| `$7D`, `dw start`, `dw length` | WR0 | A → B, port A's start, the length |
| `$54`, `$02` | WR1 | port A memory, incrementing; its timing byte |
| `$68`, `$22`, prescaler | WR2 | port B fixed (an I/O port); timing "2t with pre-escaler"; the **prescaler** |
| `$CD`, `dw $FFDF` | WR4 | **burst mode**; port B = the DAC port (Covox / Specdrum `$DF`) |
| `$82` or `$B2` | WR5 | stop at the end (one shot), or **auto restart** (loop: bit 5) |
| `$BB`, `$08` | WR6 | read mask: port A's high byte |
| `$CF` | WR6 | load |
| `$B3` | WR6 | force ready |
| `$87` | WR6 | enable: it plays |

- **Stopping:** `$83` (disable). A reset (`$C3`) also resets the
  prescaler.
- **Playing another sound:** send the program again, with the new start
  and length.
- **Its samples:** they live in an 8K page in slot 7 (`nextreg $57`), "5512
  Hz" by its header. But its prescalers (144, or 96 by default) give
  about 6,076 or 9,115 Hz by the formula. Check the formula on a real
  Next before relying on exact rates.

**Prescalers** (875 kHz / prescaler, rounded):

| Rate | Prescaler |
|---|---|
| 8 kHz | 109 |
| 11,025 Hz | 79 |
| 15,625 Hz | 56 |
| 16 kHz | 55 |
| 22,050 Hz | 40 |
| 31,250 Hz | 28 |

- **Cost:** one bus cycle of memory read and I/O write per sample (a few
  T-states). The CPU is otherwise free. The DMA's own speed follows the
  CPU's, but the prescaler fixes the period.
- **The catch:** the DMA is busy for the whole sound. "This also requires
  exclusive use of the DMA" (the wiki). Any other DMA transfer meanwhile
  stops the sample, or the sample program has to be saved and restarted
  around it.

### 4. The Copper

The Copper can `MOVE` to NextReg `$2D` ("This port can be used to generate
mono audio using the copper"): a sample a raster line.
- That is about 15.6 kHz (a 64 µs line), fed the samples each frame:
  the Copper list holds the values.
- No CPU and no DMA while it plays, but the Copper list has to be
  rewritten each frame. The wiki's example is "TBC".

### The CTC and the DMA together

The ways they really combine, from the sources:
- **The DMA plays and the CTC organises:**
  - The DMA plays a buffer at its prescaler's rate, with auto restart
    (WR5 bit 5) looping it.
  - A CTC interrupt, at a slow rate (playwav32's second channel is ~569
    Hz), refills the half the DMA has finished with from the SD card, or
    restarts the DMA on the next sound.
  - This is the double buffer of playwav32 with the DMA doing the
    per-sample work *(inferred: no source shows this exact combination)*.
- **The CTC plays and the DMA is allowed to be interrupted:**
  - A CTC-per-sample player (method 2) next to other DMA work (fills,
    copies).
  - NextReg `$CD` bit n lets CTC channel n's interrupt break into a running
    DMA transfer: in hardware IM 2 mode, the DMA gives up the bus, the
    sample is written, and after the `RETI` the DMA carries on. Without it
    a long transfer delays the samples.
  - From the wiki's `$CC` notes: each break lets the main program run one
    instruction too, and the DMA can't take the bus back until the
    routine's `RETI`.
- **The CTC triggering the DMA** *(Klive, unconfirmed)*:
  - The Klive chapter's summary describes channel 3 (`$1B3B`, ÷16,
    constant 80: 21,875 Hz) with `$CD` = `%00001000`, "the CTC ZC/TO
    pulse triggering the DMA" in burst mode with no prescaler, port B
    `$00DF`.
  - The wiki doesn't describe a trigger; `$CD` there is which CTC
    interrupts may *override* a DMA transfer.
  - The DMA example's port is `$FFDF`, not `$00DF`.
  - Treat it as a lead to test on a real Next, not a method.

## For Z-Police

The game's sound is all AY: three chips, the engines on AY 1, the effects
on AY 2 and 3 (README, "Sound effects"). Samples could add an explosion,
the devil's roar, a voice ("wave complete", "base under attack") or a
siren.
- **The DMA method doesn't fit.** The renderer uses the DMA every frame:
  the screen clear, the spans' block fills, the devil's DMA+ drawing on
  real hardware, the occlusion copies (docs/ZXNDDMA.md). A sample on the
  DMA would be cut short by each of them, or block them.
- **The CTC-per-sample method fits,** at a cost:
  - one channel at about 8-11 kHz mono (`nextreg $2D,a`);
  - 3-5% of the CPU while a sound plays, nothing otherwise (the channel
    stopped).
  - It needs hardware IM 2 mode and a small resident routine with its own
    stack, as the frame interrupt has (TODO.md, "Timing", §5).
  - `$CD` should let it break into the long DMA bursts (`dv_flush`, the
    fills), or the samples stutter during drawing.
  - The samples would sit in their own pages, mapped into a slot only
    the routine uses, or copied into a small resident ring buffer by
    the frame interrupt.
- **The Copper method** is free of the CPU but only one sound at a time
  and a Copper list to keep. The game doesn't use the Copper yet.
- **The emulator:** tools/nexsim.py doesn't model the DACs, the CTC or
  hardware IM 2 mode. A player would need those first, for the tests.
- **CSpect:** whether it emulates the DACs and the CTC fully is to be
  checked.
- **First:** set NextReg `$08` bit 3, and check by ear on a real Next
  which mirror is left and which right.


## Plan: music on the main menu

Decided (2026-11-16): the DACs play music on the screens outside the game,
not in it. There the DMA isn't needed for drawing each frame, and the CPU
mostly waits for the next frame (`menu_frame`). In the game the AY chips
keep the sound.

**The method: the DMA, streaming from the SD card.** The music is too long
to keep in memory: at 15,625 Hz mono, 30 s is 469K, 58 pages. So it plays
from a small ring, refilled from the file as it goes, the way playwav32
does with the CTC:
- **The file:** `ZPDATA/MENU.ZPM`: raw unsigned 8-bit mono at 15,625 Hz
  (DMA prescaler 56). It's made with ffmpeg (`-acodec pcm_u8 -ac 1 -ar
  15625`, the WAV header stripped) by a tool, as the other ZPDATA files
  are.
- **The ring:** 16K at `$6000`-`$9FFF`, two 8K halves, each about 0.52 s.
  - Slots 3 and 4 are free on these screens: slot 3 holds the city map
    and slot 4 the ULA screen, neither used there. They're put back
    before a level starts.
  - The ring is two pages of its own, or two the game only uses in a
    level (shared, then reloaded, as `shared_pg` does).
- **The DMA:** the whole ring, port B the DAC (`$FFDF`, or `$DF`), burst
  mode, prescaler 56, **auto restart** (WR5 bit 5): it loops over the ring
  forever. Mono to DACs A and D, so both speakers.
- **The refill:**
  - Each `menu_frame` (50 Hz) reads where the DMA is: its port A address,
    through the read mask `$BB`, as em00k's example sets up.
  - When it has crossed into one half, the other is read from the file
    (esxDOS `F_READ`, 8K: well under the half's 0.52 s).
  - At the end of the file it seeks back to the start: the music loops.
- **Pauses:**
  - **Screen changes:** the screens use the DMA too (`dma_fill`, the
    screen clears in `l320_cls`). `screen320` stops the music first (`$83`,
    keeping where it was) and starts it again after (the program re-sent
    from there).
  - **Starting a game:** stops the music for good (the DAC to `$80`),
    puts slots 3 and 4 back, and takes the ring's pages back if they were
    shared.
  - **The SD card:** loading and saving (a save game, the keys) read the
    card the music is streaming from: stop the music around them.
- **The DACs on:** NextReg `$08` bit 3 at start-up, with the other sound
  bits.

**Checks first, on CSpect and a real Next:**
- that the DMA prescaler plays at 875 kHz / 56 (open point 1 below);
- that the DMA's address reads back through the read mask, to know which
  half is playing;
- that CSpect plays the DACs and the DMA's prescaler. If it doesn't, the
  CTC method (an interrupt per sample, as playwav32) plays from the same
  ring and the same refill.

**Not chosen:**
- **The CTC per sample:** it's the fallback. In the menus the CPU is idle,
  so its cost wouldn't matter, but it needs hardware IM 2 mode set up
  first.
- **The music in memory:** too many pages.
- **The Copper:** a list to rewrite every frame.

### Open points to check on a real Next

1. The DMA prescaler's rate: the formula against em00k's "5512 Hz"
   comment.
2. Whether a CTC channel can trigger the DMA (the Klive claim).
3. `$2C` / `$2E`: left and right.
4. The DACs heard with `$08` bit 3 clear: are they silent?
5. Clicks from a CTC player during the game's DMA bursts, with and without
   `$CD`.
