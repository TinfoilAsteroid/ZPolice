
IO_DATAGEAR_DMA_PORT 		            EQU $6B
DMA_WRO_BLOCK_PORTA_A2B_XFR  equ $7D
DMA_WRO_BLOCK_PORTA_B2A_XFR  equ $79
DMA_WR1_P1FIXED_MEMORY       equ $24
DMA_WR1_P1DEC_MEMORY         equ $04
DMA_WR1_P1INC_MEMORY         equ $14
DMA_WR2_P2FIXED_MEMORY       equ $20
DMA_WR2_P2DEC_MEMORY         equ $00
DMA_WR2_P2INC_MEMORY         equ $10
DMA_WR4_CONT_MODE            equ $AD
DMA_WR4_BURST_MODE           equ $CD
DMA_RESET                    equ $c3
DMA_RESET_PORT_A_TIMING      equ $c7
DMA_RESET_PORT_B_TIMING      equ $cb
DMA_LOAD                     equ $cf
DMA_CONTINUE                 equ $d3
DMA_DISABLE_INTERUPTS        equ $af
DMA_ENABLE_INTERUPTS         equ $ab
DMA_RESET_DISABLE_INTERUPTS  equ $a3
DMA_ENABLE_AFTER_RETI        equ $b7
DMA_READ_STATUS_BYTE         equ $bf
DMA_REINIT_STATUS_BYTE       equ $8b
DMA_START_READ_SEQUENCE      equ $a7
DMA_FORCE_READY              equ $b3
DMA_STOP_AT_END		     equ $82
DMA_DISABLE                  equ $83  
DMA_ENABLE                   equ $87
DMA_WRITE_REGISTER_COMMAND   equ $bb
DMA_BURST                    equ $cd
DMA_CONTINUOUS               equ $ad
ZXN_DMA_PORT                 equ $6b
; DMA+ (zxnDDMA, core 3.03.00, port $6B only; REAL_HARDWARE builds):
; docs/ZXNDDMA.md
DDMA_MODE                    equ $df    ; then the flags: each sets them all
                                        ; (with DDMA_FLAG_XY: X lo, X hi, Y)
DDMA_FILL_VALUE              equ $f7    ; then the value
DDMA_ROW_LEN                 equ $e3    ; 2D: then bytes a row (word)
DDMA_ROWS                    equ $e7    ; 2D: then the rows (word)
DDMA_B_STRIDE                equ $ef    ; 2D: then port B's stride (word)
DDMA_A_EXT                   equ $d7    ; then port A address bits 23:16
DDMA_B_EXT                   equ $db    ; then port B address bits 23:16
DDMA_A_STRIDE                equ $eb    ; 2D: then port A's stride (word)
DDMA_TRANS_COL               equ $f3    ; then the transparent colour
DDMA_FLAG_PHYS               equ %00000001  ; 22-bit physical addresses
DDMA_FLAG_2D                 equ %00000010  ; rows (row length, rows, strides)
DDMA_FLAG_TRANS              equ %00000100  ; source bytes = the colour skipped
DDMA_FLAG_FILL               equ %00001000  ; no reads: the fill value
DDMA_FLAG_XY                 equ %00010000  ; port B from a Layer 2 X,Y
DDMA_FLAG_HIDDEN             equ %00100000  ;   on the hidden screen ($13)
; A filled rectangle in the buffer being drawn, by its physical address
; (seg_base's pages): no paging (dd_rect, city.asm)
DDMA_RECT                    equ DDMA_FLAG_PHYS|DDMA_FLAG_2D|DDMA_FLAG_FILL

l2_cls_byte	            DB 0
; ">DMA Command BLOCK"

l2_fill                 DB DMA_DISABLE,  DMA_RESET, DMA_RESET_PORT_A_TIMING, DMA_RESET_PORT_B_TIMING
    IFDEF REAL_HARDWARE
                        DB DDMA_FILL_VALUE      ; DMA+ fill: no reads, so twice
l2_fill_value           DB 0                    ; as fast as a fixed source
                        DB DDMA_MODE, DDMA_FLAG_FILL
    ENDIF
                        DB DMA_WRO_BLOCK_PORTA_A2B_XFR
l2_fill_astrt           DW l2_cls_byte
l2_fill_length          DB $00,$C0
                        DB DMA_WR1_P1FIXED_MEMORY ,DMA_WR2_P2INC_MEMORY ,DMA_WR4_CONT_MODE 
l2_fill_bstrt           DB $00,$00
                        DB DMA_STOP_AT_END, DMA_LOAD, DMA_FORCE_READY, DMA_ENABLE
    IFDEF REAL_HARDWARE
                        DB DDMA_MODE, 0         ; the mode off again: fill_spans
    ENDIF                                       ; and occ_dma are plain copies
l2_fill_cmd_len	        EQU $ - l2_fill


; DMA fill: HL = destination, BC = length (non-zero), A = the byte.  Any
; memory mapped in now (the Layer 2 sections in slot 0, the occlusion page,
; the ULA screen).  Resident (the main page, with this block), so the city,
; HUD and menu pages all use it.  It leaves the length's high byte set:
; fill_spans needs it 0 (clear_screen.spans), so the city page restores it
; after a fill of its own.
dma_fill:
        ld (l2_cls_byte),a
    IFDEF REAL_HARDWARE
        ld (l2_fill_value),a
    ENDIF
        ld (l2_fill_bstrt),hl
        ld (l2_fill_length),bc
        ld hl,l2_fill
        ld b,l2_fill_cmd_len
        ld c,IO_DATAGEAR_DMA_PORT
        otir                            ; CPU waits while the DMA runs
        ret
