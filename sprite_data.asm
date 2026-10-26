;==============================================================================
; Z-POLICE - sprite pattern banks (8K pages, assembled at $0000)
;
; Hardware sprite patterns are only needed when they are loaded into the
; sprite pattern memory, so they live in their own pages, out of the way.
; spr_load_bank (sprites.asm) maps a bank into slot 0 ($0000, otherwise
; used for paging Layer 2 sections), copies its patterns, then puts slot 0
; back.
;
; Each bank starts with a 2-byte header, then its patterns:
;   +0  SPRB_COUNT  number of patterns (1..31: 256 bytes each, 8-bit 16x16)
;   +1  SPRB_FIRST  the pattern number the first one loads to (0..63)
;   +2  SPRB_DATA   the patterns, one after another
; More sprites: add a bank (the next free page, its own PAGE_SPRn in
; zpolice.asm and a block here) and load it with spr_load_bank.
;==============================================================================

SPRB_COUNT      equ 0
SPRB_FIRST      equ 1
SPRB_DATA       equ 2

;------------------------------------------------------------------------------
; Bank 0 (PAGE_SPR0): the human status sprites, patterns 0-3
;------------------------------------------------------------------------------
        MMU 0 e, PAGE_SPR0, $0000
        ORG $0000
spr_bank0:
        db HSPR_COUNT                   ; SPRB_COUNT
        db 0                            ; SPRB_FIRST
        INCLUDE "tables_hspr.inc"       ; hspr_patterns (gentables.py):
                                        ; HSPR_FIELD, _ABOARD, _SAVED, _DEAD
        ASSERT hspr_patterns == spr_bank0 + SPRB_DATA
        ASSERT $ <= $2000
        DISPLAY "Sprite bank 0 end:",/A,$
