;==============================================================================
; Z-POLICE - start-up initialisation (8K page PAGE_INIT, runs at $E000 in
; slot 7)
;
; Code needed only once, at start-up, kept out of the resident page: start
; (zpolice.asm) pages this in with nextreg CODE_MMU,PAGE_INIT and calls
; initgame, then slot 7 is free for the other core pages.
;==============================================================================

; Hardware set-up: 28MHz, Layer 2 mode, transparency, layer priority, Layer
; 2 scroll and clip window, the memory map of the always-mapped slots, and
; a black border.
initgame:
        nextreg $07,3                   ; 28MHz
        nextreg $70,0                   ; Layer 2 256x192 mode
        nextreg $14,$E3                 ; global transparency colour
        nextreg $15,%00001000           ; priority S U L (ULA over L2); sprites
                                        ; off until sprites_init
        nextreg $16,0                   ; Layer 2 scroll X
        nextreg $17,0                   ; Layer 2 scroll Y
        nextreg $1C,%00000001           ; reset L2 clip index
        nextreg $18,0                   ; Layer 2 clip: x 0..255,
        nextreg $18,255
        nextreg $18,0                   ; y 0..191: the viewport, and the
        nextreg $18,191                 ; city map through the ULA panel
        nextreg ULA_MMU,PAGE_ULA0       ; ULA screen (bank 5) at $8000
        nextreg ZOMBIE_MMU,PAGE_ZOMBIE  ; zombie code/data stays at $2000
        nextreg OCC_MMU,PAGE_OCC0       ; occlusion data at $4000-$5FFF,
        nextreg TABLES_MMU,PAGE_OCC1    ; city_col at $6000-$6FFF
        xor a
        out ($FE),a                     ; black border
        ret
