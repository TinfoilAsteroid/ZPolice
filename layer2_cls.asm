
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

l2_cls_byte	            DB 0
; ">DMA Command BLOCK"

l2_fill                 DB DMA_DISABLE,  DMA_RESET, DMA_RESET_PORT_A_TIMING, DMA_RESET_PORT_B_TIMING ,DMA_WRO_BLOCK_PORTA_A2B_XFR
l2_fill_astrt           DW l2_cls_byte
l2_fill_length          DB $00,$C0
                        DB DMA_WR1_P1FIXED_MEMORY ,DMA_WR2_P2INC_MEMORY ,DMA_WR4_CONT_MODE 
l2_fill_bstrt           DB $00,$00
                        DB DMA_STOP_AT_END, DMA_LOAD, DMA_FORCE_READY, DMA_ENABLE
l2_fill_cmd_len	        EQU $ - l2_fill


; ">l2_cls_dma_bank sets a bank to"  
l2_cls        
.set_colour:            ld (l2_cls_byte),a
.write_dma:             ld hl, l2_fill
                        ld b, l2_fill_cmd_len
                        ld	c,IO_DATAGEAR_DMA_PORT
                        otir
                        ret
