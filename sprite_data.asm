;==============================================================================
; Z-POLICE - sprite pattern banks (8K pages, assembled at $E000)
;
; Hardware sprite patterns are only needed when they are loaded into the
; sprite pattern memory, so they live in their own pages, out of the way,
; each with its own loader so that no resident memory is used:
;
;       nextreg CODE_MMU,PAGE_SPR0      ; the bank into slot 7
;       call spr_load_bank              ; copy its patterns
;
; Call it from outside slot 7 (resident code or a game logic page in slot
; 6), and page back whatever slot 7 had afterwards if it is still needed.
; spr_load_bank is the same address ($E000) in every bank.
;
; Each bank (SPRBANK_ADDR = $E000):
;   +0          spr_load_bank: the loader (SPRB_LOADER), the same in each
;   SPRB_COUNT  number of patterns (1..31: 256 bytes each, 8-bit 16x16)
;   SPRB_FIRST  the pattern number the first one loads to (0..63)
;   SPRB_DATA   the patterns, one after another
; More sprites: add a bank (the next free page, its own PAGE_SPRn in
; memory_bank_defs.asm, the MMU / ORG lines in zpolice.asm and a block here
; starting with SPRB_LOADER).
;==============================================================================

; Copy this bank's patterns into the sprite pattern memory.  Runs from the
; bank itself: reads only, so it needs no variables.
        MACRO SPRB_LOADER
        ld a,(SPRBANK_ADDR+SPRB_FIRST)  ; from this pattern
        ld bc,SPR_SLOT_PORT
        out (c),a
        ld a,(SPRBANK_ADDR+SPRB_COUNT)
        ld d,a
        ld hl,SPRBANK_ADDR+SPRB_DATA
        ld c,SPR_PAT_PORT
.lp:    ld b,0                          ; 256 bytes a pattern
        otir
        dec d
        jr nz,.lp
        ret
        ENDM

spr_load_bank   equ SPRBANK_ADDR        ; the loader, in every bank
SPRB_COUNT      equ spr_bank0_hdr-spr_bank0
SPRB_FIRST      equ SPRB_COUNT+1
SPRB_DATA       equ SPRB_COUNT+2

;------------------------------------------------------------------------------
; Bank 0 (PAGE_SPR0): the human status sprites, patterns 0-3
; (zpolice.asm maps PAGE_SPR0 to SPRBANK_SLOT, ORG SPRBANK_ADDR, first)
;------------------------------------------------------------------------------
spr_bank0:
        SPRB_LOADER
spr_bank0_hdr:
        db HSPR_COUNT                   ; SPRB_COUNT
        db 0                            ; SPRB_FIRST
        INCLUDE "tables_hspr.inc"       ; hspr_patterns (gentables.py):
                                        ; HSPR_FIELD, _ABOARD, _SAVED, _DEAD
        ASSERT spr_bank0 == spr_load_bank
        ASSERT hspr_patterns == spr_bank0 + SPRB_DATA
        ASSERT $ <= SPRBANK_ADDR+MEMBANK_SIZE
