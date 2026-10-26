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
;   slot 1 $2000  zombie page, always mapped
;   slot 2 $4000  occlusion data
;   slot 3 $6000  city_col; $7000 humans, map (always mapped)
;   slot 4 $8000  ULA screen (page 10, the first half of bank 5)
;   slot 5 $A000  resident main code, variables, stack (page 11, the unused
;                 second half of bank 5)
;   slot 6 $C000  game logic pages, swapped: player, weapons, menu
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

; slot 1: zombie.asm, always mapped
ZOMBIE_SLOT             equ MMU_SLOT_1
ZOMBIE_MMU              equ MMU_SLOT_1_REGISTER
ZOMBIE_ADDR             equ membank1

; slot 2: occlusion buffer, draw list and building records (OCCLUSION_CULL)
OCC_SLOT                equ MMU_SLOT_2
OCC_MMU                 equ MMU_SLOT_2_REGISTER
OCC_ADDR                equ membank2

; slot 3: city_col (tables_col.inc) at $6000, then human.asm and map.asm
; from $7000; always mapped
TABLES_SLOT             equ MMU_SLOT_3
TABLES_MMU              equ MMU_SLOT_3_REGISTER
TABLES_ADDR             equ membank3            ; city_col
HUMAN_ADDR              equ membank3+$1000      ; human.asm onwards

; slot 4: the ULA screen (bank 5's first 8K: bitmap and attributes)
ULA_SLOT                equ MMU_SLOT_4
ULA_MMU                 equ MMU_SLOT_4_REGISTER
ULA_ADDR                equ membank4

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
PAGE_OCC1               equ 7           ; city_col, humans, map (slot 3,
                                        ; always)
PAGE_MENU               equ 8           ; menu.asm: main menu (slot 6)
PAGE_SPR0               equ 9           ; sprite_data.asm: sprite pattern
                                        ; bank 0 (slot 7 while loading);
                                        ; more banks: the next free pages
PAGE_ULA0               equ 10          ; the ULA screen, bank 5 (slot 4)
PAGE_MAIN               equ 11          ; zpolice.asm, resident (slot 5): the
                                        ; second half of bank 5
PAGE_KEYS               equ 12          ; keys.asm: keyboard (slot 7)
PAGE_SPRITES            equ 13          ; sprites.asm: hardware sprites
                                        ; (slot 7)
PAGE_SIN                equ 14          ; sin_tables.asm: the sine table
                                        ; (slot 0, read by get_sin)
PAGE_INIT               equ 15          ; initialise.asm: start-up set-up,
                                        ; initgame (slot 7, once)

; Layer 2 double buffer, in 16K banks (NextReg $12 / $13 take banks; the
; pages are bank * 2).  Layer 2 is clipped to 192 rows, so each buffer
; uses three banks.
L2_BANK_A               equ 9           ; 16K banks 9-11 (pages 18-23)
L2_BANK_B               equ 12          ; 16K banks 12-14 (pages 24-29)
PAGE_L2_A               equ L2_BANK_A*2
PAGE_L2_B               equ L2_BANK_B*2

PAGE_ROM                equ $FF         ; MMU value: ROM in slots 0-1
