# Z-Police memory map

The Next maps RAM into the Z80's 64K as eight 8K MMU slots. Each slot is set
by a NextReg (`$50`–`$57`) to an 8K page, where page n is half of 16K bank
n/2. The names used below (`CODE_MMU`, `PAGE_CITY`, …) are defined in
`memory_bank_defs.asm`. Page contents are placed in `zpolice.asm` with
`MMU <slot> e, <page>, <address>` and `ORG`.

"End" is the first free address after the code, as shown by the build
(`DISPLAY`). Each page holds at most 8K.

## MMU 0: `$0000`–`$1FFF` (NextReg `$50`)

At start-up this slot holds the ROM (`PAGE_ROM` = `$FF`). In the game it has
two uses:

| Page | Contents | Mapped by |
|------|----------|-----------|
| 14 `PAGE_SIN` | `sin_tables.asm`: sine table (end `$0200`) | `get_sin` (resident), `nextreg SIN_MMU,PAGE_SIN` |
| 18–23 `PAGE_L2_A` | Layer 2 buffer A (16K banks 9–11), one 32-row section at a time | `seg_map` / `line_seg` (city.asm), hud.asm, map.asm, via `L2SEC_MMU` |
| 24–29 `PAGE_L2_B` | Layer 2 buffer B (16K banks 12–14), the same way | as above |

The Layer 2 buffers aren't loaded from files: they are drawn into each frame.

## MMU 1: `$2000`–`$3FFF` (NextReg `$51`), always mapped

At start-up this slot holds the ROM. From then on it always holds the zombie
page.

| Page | File | Range |
|------|------|-------|
| 5 `PAGE_ZOMBIE` | `zombie.asm` | `$2000`–`$3488` |
| | `human.asm` | to `$3A34` |
| | `map.asm` (the HUD map) | to `$3BE1` |
| | `interrupts.asm` (IM 2 table at `$3C00`, the ISR; the sound players are in the audio page) | to `$3F99` |

## MMU 2: `$4000`–`$5FFF` (NextReg `$52`)

`initialise.asm` maps the occlusion page in. The screens outside the game
(the main menu, redefine keys, load-out and level complete now; later game
over) map the 320x256 graphics page over it; `l2_game_mode` puts the occlusion page back before the game.

| Page | Contents |
|------|----------|
| 6 `PAGE_OCC0` | Occlusion data, used by city.asm. Not assembled: it is filled each frame. |
| 35 `PAGE_L320` | `layer2-320x256.asm`: Layer 2 320x256 graphics (switching, DMA clear, text in the 8x8 and large fonts, recolouring, lines, boxes) for the screens outside the game; the fonts' files (`ZPDATA/FONT8.ZPF`, up to 596 bytes, and `FONT12.ZPF`, up to 1,280) are loaded into `f8_buf` and `f12_buf` here at start-up (`fonts_load`; FONT8.ZPF's glyphs then go over `font8` in the main page); `img_buf` (2K): a screen image's columns as `l320_image` reads them. The screen itself is banks 9–13 (pages 18–27: buffer A and part of B). |

The occlusion data is laid out as follows:
- `OCC_YBUF` `$4000`: the cover row of each screen column.
- `OCC_LIST` `$4100`: the draw list.
- Building records `$4300`–`$5FFF`: 128 bytes each, two a page, 58 records.
- `OCC_YBUF8` `$4200`: per 8 columns (32 bytes of its own page).

## MMU 3: `$6000`–`$7FFF` (NextReg `$53`), always mapped: the city bank

`initialise.asm` maps this page in.

| Page | Contents |
|------|----------|
| 7 `PAGE_OCC1` | Space reserved in `zpolice.asm`: `city_col` (`ds 4096`) at `$6000` and `city_map` (`ds 4096`) at `$7000` |

**Loaded from a file:**

| File | Page | Address | Loaded by |
|------|------|---------|-----------|
| `ZPDATA/CITYnn.ZPC`: the cell colours and map, the 8K after its header and palette | 7 | `$6000`–`$7FFF` (`city_col`, then `city_map`), in one read | `load_level` (`level_load.asm`), at each level's start |

The level file's map changes are then written over `city_map` / `city_col`
in place.

## MMU 4: `$8000`–`$9FFF` (NextReg `$54`), always mapped

`initialise.asm` maps this page in.

| Page | Contents |
|------|----------|
| 10 `PAGE_ULA0` | ULA screen: the first half of bank 5, bitmap and attributes; used for the HUD (`hud.asm`, Layer 1). Not assembled. |
| 34 `PAGE_CITY2` | `city2.asm`, the second city page (end `$8A3B`, about 5.6K free): the street dots, bullets, rockets, particles, gunsight and occlusion culling. Mapped here over the ULA screen only while `main_loop` draws the city, beside the city page in MMU 7; the ULA screen goes back before `draw_hud`. |

## MMU 5: `$A000`–`$BFFF` (NextReg `$55`), resident

The boot stub maps this page in.

| Page | File | Notes |
|------|------|-------|
| 11 `PAGE_MAIN` | `zpolice.asm` | main code, variables, stack (`stack_top`); end `$B584` |
| | `htabs.asm` | horizon and height tables (generated) |
| | `city_map.asm` | shared map constants (generated) |
| | `l2_pallets.asm` | fixed colour slot checks |
| | `levels.asm` | the current level's record, `level_cur` (`$A05B`) |
| | `text.asm` | text screens: menu, load-out |
| | `layer2_cls.asm` | the zxnDMA fill block and `dma_fill` (used by the city, HUD and menu pages) |

**Loaded from a file:**

| File | Page | Address | Loaded by |
|------|------|---------|-----------|
| `ZPDATA/SAVEGAME.ZPS` (41 bytes) | 11 | `sg_buf`, `$ABA1` | `load_save` (CONTINUE); `save_game` writes it from there |
| `ZPDATA/LEVELnn.ZPL`: the level record part (copied, not read here) | 11 | `level_cur`, `$A05B` | `load_level` copies it out of `ll_lbuf` (see MMU 6) |

## MMU 6: `$C000`–`$DFFF` (NextReg `$56`): game logic pages, swapped

At load, the NEX loader maps page 0 here, so the entry stub is assembled
for this slot.

| Page               | File             | End     |
|--------------------|------------------|---------|
| 0 `PAGE_BOOT`      | entry stub `boot` (in `zpolice.asm`) | — |
| 3 `PAGE_PLAYER`    | `player.asm`     | `$C2F2` |
| 4 `PAGE_WEAPONS`   | `weapons.asm`    | `$CCF7` |
| 8 `PAGE_MENU`      | `menu.asm` (game over, game complete, load error) | `$C126` |
| 30 `PAGE_LEVEL`    | `level_load.asm` | `$C536` |
| 31 `PAGE_SPECIAL`  | `specials.asm`   | `$C75C` |
| 32 `PAGE_LOADOUT`  | `loadout.asm`    | `$C368` |
| 33 `PAGE_KEYDEF`   | `keydef.asm`     | `$C75C` |
| 36 `PAGE_MAINMENU` | `mainmenu.asm`   | `$C09B` |
| 37 `PAGE_LEVELEND` | `levelend.asm`   | `$C436` |
| 38–67 `PAGE_GFX0` on (at most 48 pages, to 85) | the figures' graphics: no code (`ZPDATA/SPRITES.ZPG`, made by `gengraphics.py`) | — |
| 86–95 `PAGE_L320_BG` | the background copy of a 320x256 screen (`l320_bg_save`): the load-out's picture, put back under text that changes (`l320_restore`), through slot 4 | — |

The figures' graphics pages are mapped here only while the city is drawn
(the game logic doesn't run then): `spr_lod` maps page 38 (the directory),
then the frame's page (its table of sizes), `spr_draw` the page of the size
it draws. `main_loop` maps the logic pages
back before they run.

**Loaded from a file:**

| File | Page | Address | Loaded by |
|------|------|---------|-----------|
| `ZPDATA/LEVELnn.ZPL`: whole file, at most 376 bytes | 30 | `ll_lbuf`, `$C19F` | `load_level` |
| `ZPDATA/CITYnn.ZPC`: header and palette, the first 544 bytes | 30 | `ll_cbuf`, `$C317` | `load_level` |
| `ZPDATA/LEVELnn.ZPP`: the level's own palette (only if it has one), 520 bytes | 30 | `ll_cbuf`, `$C317` (once the city's header is used) | `load_level` |
| `ZPDATA/LEVELnn.ZPV`: the level's 4 vision palettes (normal, night vision green and monochrome, thermal), 2,056 bytes | 30 | `ll_vbuf` (kept there: `vis_cycle` swaps one into the Layer 2 palette in flight, with this page mapped) | `load_level` (`vis_load`) |
| `ZPDATA/SPRITES.ZPG`: the figures' graphics (one set: the vision modes recolour them by palette), a 16-byte header then 1–48 pages of 8K (30 now) | 38 on (`PAGE_GFX0`) | each read at `$8000` (slot 4, the ULA screen's page put back after); used at `$C000` (slot 6) | `gfx_load`, at start-up (the header into `ll_cbuf`) |

`load_level` then sends the palette to the Layer 2 palette (NextReg `$44`).
The rest of the city file goes to MMU 3.

## MMU 7: `$E000`–`$FFFF` (NextReg `$57`): core function pages, swapped

| Page               | File             | End     |
|--------------------|------------------|---------|
| 1 `PAGE_CITY`      | `city.asm` (includes `tables_city.inc`: the projection's and `div8`'s reciprocals, log2, used corners) | `$F956`: about 1,700 bytes free |
| 2 `PAGE_HUD`       | `hud.asm`        | `$E402` |
| 9 `PAGE_SPR0`      | `sprite_data.asm`: sprite pattern bank 0, paged in only to run its own loader\
                                        | `$EB1A` |
| 12 `PAGE_INPUT`    | `input.asm`      | `$E20F` |
| 13 `PAGE_SPRITES`  | `sprites.asm`,
                       `hud_sprites.asm`| `$E352` |
| 15 `PAGE_INIT`     | `initialise.asm` (run once at start-up) 
                                        | `$E059` |
| 16 `PAGE_FILE`     | `file_handler.asm` (SD card load / save) 
                                        | `$E125` |
| 17 `PAGE_AUDIO`    | `audio.asm`, `sound.asm`, `sfx_data.asm` | `$E98F` |

## Page summary

| Page  | Slot    | Contents                                                                           |
|-------|---------|------------------------------------------------------------------------------------|
| 18–23 | 0 $0000 | Layer 2 buffer A                                                                   |
| 24–29 | 0 $0000 | Layer 2 buffer B                                                                   |
| 14    | 0 $0000 | sin_tables.asm                                                                     |
| 5     | 1 $2000 | zombie.asm, human.asm, map.asm, interrupts.asm - Never paged out                   |
| 6     | 2 $4000 | occlusion data                                                                     |
| 35    | 2 $4000 | layer2-320x256.asm (on the screens outside the game, over the occlusion data)      |
| 7     | 3 $6000 | city bank (CITYnn.ZPC loaded here)                                                 |
| 10    | 4 $8000 | ULA screen                                                                         |
| 11    | 5 $A000 | zpolice.asm and its includes (SAVEGAME.ZPS loaded here)                            |
| 30    | 6 $C000 | level_load.asm (LEVELnn.ZPL and the CITYnn.ZPC header loaded here)                 |
| 31    | 6 $C000 | specials.asm                                                                       |
| 32    | 6 $C000 | loadout.asm                                                                        |
| 33    | 6 $C000 | keydef.asm                                                                         |
| 0     | 6 $C000 | boot stub                                                                          |
| 8     | 6 $C000 | menu.asm (game over, game complete, load error)                                    |
| 37    | 6 $C000 | levelend.asm (level complete)                                                      |
| 36    | 6 $C000 | mainmenu.asm                                                                       |
| 3     | 6 $C000 | player.asm                                                                         |
| 4     | 6 $C000 | weapons.asm                                                                        |
| 1     | 7 $E000 | city.asm                                                                           |
| 34    | 4 $8000 | city2.asm (while the city is drawn, over the ULA screen)                           |
| 12    | 7 $E000 | input.asm                                                                          |
| 2     | 7 $E000 | hud.asm                                                                            |
| 9     | 7 $E000 | sprite_data.asm                                                                    |
| 13    | 7 $E000 | sprites.asm, hud_sprites.asm                                                       |
| 15    | 7 $E000 | initialise.asm                                                                     |
| 16    | 7 $E000 | file_handler.asm                                                                   |
| 17    | 7 $E000 | audio.asm                                                                          |

## Resident code (never paged out)

Two pages of code stay mapped for the whole game, from `start` onwards.
Code in them can be called from any page, and is the only place for code
that must run whatever is in slots 6 and 7. For example, a routine that
swaps pages and then calls into them has to be resident.

### MMU 5: `$A000`–`$BFFF`, page 11 `PAGE_MAIN` (end `$B584`)

- **Files:** `zpolice.asm`, with `htabs.asm`, `city_map.asm`,
  `l2_pallets.asm`, `levels.asm` and `text.asm`.
- **Main flow:**
  - `start` (`$A76B`): set-up, then the main menu.
  - `main_loop` (`$A8DB`): pages in each game page in turn and calls it.
  - `game_reset`, `next_level`.
  - `menu_go`, `loadout_go`, `keydef_go`: jumps into the menu pages.
- **Frame and video:** `vtick`, `fps_tick`, `wait_vblank`, `l2_flip`,
  `map_shadow`, `read_nextreg`, `setup_frame`, `make_vecs`.
- **Shared maths:**
  - `get_sin` (`$AD33`, pages the sine table into slot 0);
  - `neg_hl` (`$ADDE`), `abs_hl`, `fmul` (`$ADEA`), `zhalf`.
- **Game helpers:** `cam_cell_ptr`, `floor_y`, `bld_height`,
  `vtol_landed`, `vtol_ground`, `vtol_damage`, `wpn_cfg_ptr`, `wpn_fits`.
- **Pause and save games:** `game_pause`, `save_game`, `load_save`,
  `continue_game`, `sg_copy`. The save buffer is `sg_buf` (`$ABA1`).
- **Text screens:** `text.asm`: menu and load-out text, `menu_clear`.
- **Shared state:** the camera, weapons, level, wave, salvage and booster
  variables; the bullets and particles; `level_cur` (`$A05B`).
- **Stack:** 256 bytes below `stack_top` (`$B585`).

### MMU 1: `$2000`–`$3FFF`, page 5 `PAGE_ZOMBIE` (end `$3F99`)

- **Monsters and humans:** `zombie.asm` (e.g. `zombie_update`, `$2607`)
  and `human.asm`.
- **HUD map:** `map.asm`, which pages Layer 2 sections into slot 0 itself.
- **Interrupts:** `interrupts.asm`:
  - the IM 2 vector table `im2_table` (`$3C00`);
  - the routine `im2_routine` (`$3E3E`), with its own stack `isr_stack`
    (`$3F9A`);
  - the sound's resident state: the request bytes (`sfx_req`, `sfx2_req`,
    `sfx3_req`), the playing sounds' pointers, `eng_on`, `eng_cur`.

  The table and routine must be resident, because an interrupt can arrive
  whatever pages are in slots 6 and 7. With the engines on, the routine
  maps the audio page (`PAGE_AUDIO`: `sound.asm`'s `engine_tick`,
  `sfx_tick`, `sfx_voice`, `isr_ay`, and `sfx_data.asm`) into slot 7 to
  play the sound, then puts back the page that was there and the main
  code's selected NextReg ($243B, read first).

### Always-mapped data (no code)

- **MMU 2, page 6:** the occlusion data (page 35, the 320x256 graphics, over it on the screens outside the game).
- **MMU 3, page 7:** the city bank, `city_col` and `city_map`.
- **MMU 4, page 10:** the ULA screen.
