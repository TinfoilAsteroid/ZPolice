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
; im2_init sets I and IM 2 (start calls it after init_audio); start enables
; interrupts just before the main menu, and they stay on, 50 a second, except:
;   * over esxDOS calls (fh_rom_in / fh_rom_out): the ROM covers slot 1, this
;     page, so they are off and put back as they were;
;   * the span filler borrows SP (city.asm: PUSHes into Layer 2, slot 0).  An
;     interrupt there pushes its return address just below SP: into the
;     part of the span still to be filled, which the PUSHes then overwrite.
;     Interrupts are off from just before a span's last PUSH until SP is
;     back (push_blk), and a 1-pixel span doesn't borrow SP at all.
; The routine switches to its own stack at once, keeps every register, and
; touches the AY ports only while the engines are on (eng_on): code outside
; the interrupt writes the AY chips only with eng_on 0 (init_audio,
; engine_start).  Then it also borrows slot 7 for the sound page, and the
; NextReg ports ($243B, $253B) to find what's there: both put back as they
; were (the selected NextReg too).
;==============================================================================

;------------------------------------------------------------------------------
; Point I at the vector table and select interrupt mode 2.  (start enables
; interrupts later.)
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
; The interrupt routine, each video frame (50 a second): a tick counted
; (isr_ticks), and with the engines on (eng_on), the engines' sound
; (engine_tick) and the sound effects (sfx_tick): in the audio page
; (sound.asm), mapped into slot 7 meanwhile and the page there put back
; after.  The page there is read through the NextReg ports, so the main
; code's selected NextReg ($243B, which it may have set and not yet read
; or written through $253B) is read first and put back last.  On its own stack: SP may
; be the span filler's.  It must never use the alternate registers (EXX,
; EX AF,AF'): the city's cell walks keep their place in HL', DE' across
; the whole drawing (draw_row, city.asm).
;------------------------------------------------------------------------------
im2_routine:
        ld (isr_sp),sp                  ; its own stack at once (no PUSH on
        ld sp,isr_stack                 ; a borrowed one)
        push af
        push bc
        push de
        push hl
        ld hl,(isr_ticks)               ; the frames counted (wave_prepare)
        inc hl
        ld (isr_ticks),hl
        ld a,(eng_on)                   ; nothing to play: the AYs alone
        or a
        jr z,.out
        ld bc,$243B                     ; the NextReg the main code has
        in a,(c)                        ; selected (it may be between its OUT
        ld (isr_sel),a                  ; and its IN): put back after
        ld a,CODE_MMU                   ; slot 7's page, to put back after
        out (c),a
        inc b
        in a,(c)
        ld (isr_mmu7),a
        nextreg CODE_MMU,PAGE_AUDIO     ; the sound page (sound.asm)
        call engine_tick
        call sfx_tick
        ld a,(isr_mmu7)                 ; slot 7 as it was,
        nextreg CODE_MMU,a
        ld bc,$243B                     ; and the NextReg selection
        ld a,(isr_sel)
        out (c),a
.out:   pop hl
        pop de
        pop bc
        pop af
        ld sp,(isr_sp)
        ei
        reti
        ASSERT im2_routine == IM2_ROUTINE
        ASSERT high im2_routine == low im2_routine

; (The engines' and the sound effects' players are in the audio page:
; sound.asm, mapped into slot 7 for them, im2_routine.)


eng_on:     db 0                        ; 1: the engines run and sound
                                        ; effects play (engine_start); 0: the
                                        ; interrupt leaves the AYs alone
sfx_req:    db 0                        ; voice 1 (AY 2, weapons): a sound asked
sfx_ptr:    dw 0                        ;   for (SFX_*, 0: none), the playing
                                        ;   one's next step (0: none)
sfx2_req:   db 0                        ; voice 2 (AY 3 A/B, explosions): the same
sfx2_ptr:   dw 0
sfx3_req:   db 0                        ; voice 3 (AY 3 C, splats): the same
sfx3_ptr:   dw 0
sv_sel:     db 0                        ; sfx_voice: its AY chip
eng_cur:    dw 0                        ; the engines' speed, 1/ENG_FRAC steps
isr_sel:    db 0                        ; the main code's selected NextReg,
isr_mmu7:   db 0                        ;   and slot 7's page (put back)
isr_sp:     dw 0                        ; the interrupted SP
isr_ticks:  dw 0                        ; +1 each interrupt (50 a second):
                                        ; a timer, set by whoever uses it
            ds 32                       ; the interrupt's stack
isr_stack:
        ASSERT $ <= $4000                ; (the end of slot 1)
