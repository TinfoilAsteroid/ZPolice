;==============================================================================
; Z-POLICE - interrupt mode 2 (in the zombie page, after map.asm: kept
; mapped in slot 1, so the table and routine are there whatever page is
; swapped in; the ROM replaces slot 1 only during esxDOS calls, when
; interrupts are off)
;
; In IM 2 an interrupt calls the address held in the word at I*256 + the
; byte on the data bus, which can be anything.  So:
;   * im2_table is 256 words, every one the address of im2_routine, at a
;     256-byte boundary (I holds the high byte of its address): any bus
;     byte, even $FF (bytes $FF and $100), reads a word inside it;
;   * an odd bus byte reads a word that straddles two entries, low byte
;     from one and high byte from the next, so im2_routine sits at an
;     address whose high and low bytes are the same (IM2_ROUTINE, $xyxy):
;     read either way round, it's the same address.
; im2_init sets I and IM 2 (start calls it after init_audio).  It doesn't
; enable interrupts: the game still runs with them off (the span filler
; borrows SP, the file handler swaps the ROM in), so EI is for later, once
; the main loop is ready for them.
;==============================================================================

;------------------------------------------------------------------------------
; Point I at the vector table and select interrupt mode 2.  Interrupts stay
; disabled.
;------------------------------------------------------------------------------
im2_init:
        ld a,high im2_table
        ld i,a
        im 2
        ret

        ALIGN 256
im2_table:
        REPT 256
        dw im2_routine
        ENDR

; The routine's address: high byte = low byte, just past the table
IM2_ROUTINE     equ ((high im2_table)+2)*$101
        ASSERT $ <= IM2_ROUTINE
        ds IM2_ROUTINE-$                ; (unused up to it)

;------------------------------------------------------------------------------
; The interrupt routine: a placeholder for now
;------------------------------------------------------------------------------
im2_routine:
        ei
        reti
        ASSERT im2_routine == IM2_ROUTINE
        ASSERT high im2_routine == low im2_routine
