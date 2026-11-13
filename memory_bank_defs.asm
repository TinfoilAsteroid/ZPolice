;==============================================================================
; Z-POLICE - memory bank definitions
;
; The Next maps its RAM into the Z80's 64K as eight 8K MMU slots, each set by
; a NextReg ($50-$57) to an 8K page (page n = half of 16K bank n/2).  This
; file names the slots, their registers and addresses, what each slot is
; used for, and which page holds what.  Use:
;   nextreg CODE_MMU,PAGE_CITY            ; page the city code in at $E000
;   MMU CODE_SLOT e, PAGE_CITY, CODE_ADDR ; (sjasmplus) assemble into it
;
; Memory map (see README.md):
;   slot 0 $0000  Layer 2 sections (32 rows each) while drawing; the sine
;                 table (PAGE_SIN) whenever get_sin reads it
;   slot 1 $2000  zombie page, always mapped: zombies, humans, the HUD
;                 map, the IM 2 table
;   slot 2 $4000  occlusion data; the 320x256 graphics (PAGE_L320) on the
;                 screens outside the game
;   slot 3 $6000  the city bank (always mapped): city_col at $6000,
;                 city_map at $7000, loaded from the level's city file
;   slot 4 $8000  ULA screen (page 10, the first half of bank 5)
;   slot 5 $A000  resident main code, variables, stack (page 11, the unused
;                 second half of bank 5)
;   slot 6 $C000  game logic pages, swapped: player, weapons, menus, level
;                 loading
;   slot 7 $E000  core function pages, swapped: city (Layer 2 drawing), HUD,
;                 keys, sprites; a sprite bank while it is loaded; the
;                 start-up set-up (initialise.asm) once
; So game logic in slot 6 can call any core page in slot 7: main_loop pages
; the keys in at $E000 while the player and weapons pages run at $C000.
; At start-up the NEX loader's default mapping is in place (slot 6 = page
; 0), so the entry point is a stub in PAGE_BOOT at $C000 (boot, zpolice.asm)
; that maps the resident page into slot 5 and jumps to start.
;==============================================================================

;------------------------------------------------------------------------------
; MMU slots: number, NextReg, address
;------------------------------------------------------------------------------
MEMBANK_SIZE            equ $2000       ; 8K a slot / page

MMU_SLOT_0              equ 0
MMU_SLOT_1              equ 1
MMU_SLOT_2              equ 2
MMU_SLOT_3              equ 3
MMU_SLOT_4              equ 4
MMU_SLOT_5              equ 5
MMU_SLOT_6              equ 6
MMU_SLOT_7              equ 7

MMU_SLOT_0_REGISTER     equ $50
MMU_SLOT_1_REGISTER     equ $51
MMU_SLOT_2_REGISTER     equ $52
MMU_SLOT_3_REGISTER     equ $53
MMU_SLOT_4_REGISTER     equ $54
MMU_SLOT_5_REGISTER     equ $55
MMU_SLOT_6_REGISTER     equ $56
MMU_SLOT_7_REGISTER     equ $57

membank0                equ $0000
membank1                equ $2000
membank2                equ $4000
membank3                equ $6000
membank4                equ $8000
membank5                equ $A000
membank6                equ $C000
membank7                equ $E000

;------------------------------------------------------------------------------
; What each slot is used for: <use>_SLOT, <use>_MMU (its NextReg) and
; <use>_ADDR (the ORG of code or data assembled for it)
;------------------------------------------------------------------------------
; slot 0: one 32-row section of a Layer 2 buffer at a time (seg_map etc.)
L2SEC_SLOT              equ MMU_SLOT_0
L2SEC_MMU               equ MMU_SLOT_0_REGISTER
L2SEC_ADDR              equ membank0
; slot 0 also: the sine table, paged in by get_sin (resident).  Only the
; game logic calls it, never the drawing, and every Layer 2 writer maps its
; own section first, so the two never meet.  Nothing may write to
; $0000-$1FFF while it is mapped.
SIN_SLOT                equ MMU_SLOT_0
SIN_MMU                 equ MMU_SLOT_0_REGISTER
SIN_ADDR                equ membank0

; slot 1: zombie.asm, human.asm, map.asm, interrupts.asm, always mapped
ZOMBIE_SLOT             equ MMU_SLOT_1
ZOMBIE_MMU              equ MMU_SLOT_1_REGISTER
ZOMBIE_ADDR             equ membank1

; slot 2: occlusion buffer, draw list and building records (OCCLUSION_CULL)
OCC_SLOT                equ MMU_SLOT_2
OCC_MMU                 equ MMU_SLOT_2_REGISTER
OCC_ADDR                equ membank2
; slot 2 also: the 320x256 Layer 2 graphics (layer2-320x256.asm), for the
; screens outside the game (menus, load-out, level complete, game over),
; which never draw the city.  The occlusion page goes back before the game
; (l2_game_mode).
L320_SLOT               equ MMU_SLOT_2
L320_MMU                equ MMU_SLOT_2_REGISTER
L320_ADDR               equ membank2

; slot 3: the city bank, always mapped: city_col at $6000, city_map at
; $7000, read from the level's city file (level_load.asm) in one go
TABLES_SLOT             equ MMU_SLOT_3
TABLES_MMU              equ MMU_SLOT_3_REGISTER
TABLES_ADDR             equ membank3            ; city_col
CITYMAP_ADDR            equ membank3+$1000      ; city_map

; slot 4: the ULA screen (bank 5's first 8K: bitmap and attributes)
ULA_SLOT                equ MMU_SLOT_4
ULA_MMU                 equ MMU_SLOT_4_REGISTER
ULA_ADDR                equ membank4
; slot 4 also: the second city page (city2.asm), over the ULA screen while
; main_loop draws the city (nothing then uses the ULA screen)
CITY2_SLOT              equ MMU_SLOT_4
CITY2_MMU               equ MMU_SLOT_4_REGISTER
CITY2_ADDR              equ membank4

; slot 5: resident main code (zpolice.asm), tables, variables, stack
MAIN_SLOT               equ MMU_SLOT_5
MAIN_MMU                equ MMU_SLOT_5_REGISTER
MAIN_ADDR               equ membank5

; slot 6: game logic pages, swapped (player, weapons, menu)
LOGIC_SLOT              equ MMU_SLOT_6
LOGIC_MMU               equ MMU_SLOT_6_REGISTER
LOGIC_ADDR              equ membank6
; slot 6 at start-up: the boot stub (the NEX loader maps page 0 there)
BOOT_SLOT               equ MMU_SLOT_6
BOOT_ADDR               equ membank6

; slot 7: core function pages, swapped (city / Layer 2, HUD, keys, sprites)
CODE_SLOT               equ MMU_SLOT_7
CODE_MMU                equ MMU_SLOT_7_REGISTER
CODE_ADDR               equ membank7
; slot 7 also: a sprite pattern bank (sprite_data.asm), paged in to run
; its own loader, spr_load_bank
SPRBANK_SLOT            equ MMU_SLOT_7
SPRBANK_MMU             equ MMU_SLOT_7_REGISTER
SPRBANK_ADDR            equ membank7

;------------------------------------------------------------------------------
; 8K pages
;------------------------------------------------------------------------------
PAGE_BOOT               equ 0           ; the NEX entry stub (slot 6 at load)
PAGE_CITY               equ 1           ; city.asm: Layer 2 drawing (slot 7)
PAGE_HUD                equ 2           ; hud.asm: ULA (Layer 1) HUD (slot 7)
PAGE_PLAYER             equ 3           ; player.asm: input, movement,
                                        ; collision (slot 6)
PAGE_WEAPONS            equ 4           ; weapons.asm: player weapons (slot 6)
PAGE_ZOMBIE             equ 5           ; zombie.asm (slot 1, always)
PAGE_OCC0               equ 6           ; occlusion buffer, draw list and
                                        ; building records (slot 2)
PAGE_OCC1               equ 7           ; the city bank: city_col and
                                        ; city_map (slot 3, always)
PAGE_MENU               equ 8           ; menu.asm: game over, game complete,
                                        ; the load error (slot 6)
PAGE_SPR0               equ 9           ; sprite_data.asm: sprite pattern
                                        ; bank 0 (slot 7 while loading);
                                        ; more banks: the next free pages
PAGE_ULA0               equ 10          ; the ULA screen, bank 5 (slot 4)
PAGE_MAIN               equ 11          ; zpolice.asm, resident (slot 5): the
                                        ; second half of bank 5
PAGE_INPUT              equ 12          ; input.asm: keyboard, joysticks (slot 7)
PAGE_SPRITES            equ 13          ; sprites.asm: hardware sprites
                                        ; (slot 7)
PAGE_SIN                equ 14          ; sin_tables.asm: the sine table
                                        ; (slot 0, read by get_sin)
PAGE_INIT               equ 15          ; initialise.asm: start-up set-up,
                                        ; initgame (slot 7, once)
PAGE_FILE               equ 16          ; file_handler.asm: SD card loading
                                        ; and saving (slot 7)
PAGE_AUDIO              equ 17          ; audio.asm: sound set-up (slot 7)
PAGE_SPECIAL            equ 31          ; specials.asm: special monsters
                                        ; (slot 6)
PAGE_LOADOUT            equ 32          ; loadout.asm: the load-out screen
                                        ; between levels (slot 6)
PAGE_KEYDEF             equ 33          ; keydef.asm: the redefine keys
                                        ; screen (slot 6)
PAGE_CITY2              equ 34          ; city2.asm: more Layer 2 drawing
                                        ; (slot 4, with the city page)
PAGE_L320               equ 35          ; layer2-320x256.asm: Layer 2 320x256
                                        ; graphics for the menu screens (slot 2)
PAGE_MAINMENU           equ 36          ; mainmenu.asm: the main menu (slot 6)
PAGE_LEVELEND           equ 37          ; levelend.asm: level complete (slot 6)
PAGE_L320_BG            equ 86          ; 86-95: a copy of a 320x256 screen's
                                        ; background (l320_bg_save), to put back
                                        ; under text that changes (l320_restore).
                                        ; Shared: the figures' last 10 pages
                                        ; (shared_pg; gfx_reload puts them back)
PAGE_GFX0               equ 38          ; the figures' graphics (pages 38-95,
                                        ; GFX_PAGES_MAX at most), loaded from
                                        ; ZPDATA/SPRITES.ZPG at start-up; each
                                        ; mapped at $C000 (slot 6) to draw
GFX_SHARED              equ PAGE_L320_BG - PAGE_GFX0    ; (its first shared page)
PAGE_LEVEL              equ 30          ; level_load.asm: level and city
                                        ; files (slot 6); pages 18-29 are
                                        ; the Layer 2 buffers

; Layer 2 double buffer, in 16K banks (NextReg $12 / $13 take banks; the
; pages are bank * 2).  Layer 2 is clipped to 192 rows, so each buffer
; uses three banks.
L2_BANK_A               equ 9           ; 16K banks 9-11 (pages 18-23)
L2_BANK_B               equ 12          ; 16K banks 12-14 (pages 24-29)
PAGE_L2_A               equ L2_BANK_A*2
PAGE_L2_B               equ L2_BANK_B*2

PAGE_ROM                equ $FF         ; MMU value: ROM in slots 0-1
