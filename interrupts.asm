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
; touches only the AY ports (never $243B, the main code's NextReg port), and
; only while the engines are on (eng_on): code outside the interrupt writes
; the AY chips only with eng_on 0 (init_audio, engine_start).
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
; The interrupt routine, each video frame (50 a second): the engines' sound
; (engine_tick) and the sound effects (sfx_tick).  On its own stack: SP may
; be the span filler's.
;------------------------------------------------------------------------------
im2_routine:
        ld (isr_sp),sp                  ; its own stack at once (no PUSH on
        ld sp,isr_stack                 ; a borrowed one)
        push af
        push bc
        push de
        push hl
        call engine_tick
        call sfx_tick
        pop hl
        pop de
        pop bc
        pop af
        ld sp,(isr_sp)
        ei
        reti
        ASSERT im2_routine == IM2_ROUTINE
        ASSERT high im2_routine == low im2_routine

;------------------------------------------------------------------------------
; The VTOL's engines (audio.asm has the sound's constants and engine_start):
; jet turbines, on AY 1.  eng_cur is the speed the engines sound at, in
; 1/ENG_FRAC steps; each interrupt it follows the VTOL's, n = |speed| (at
; least 1: zero throttle idles as speed 1), by at most ENG_SPIN_UP going up
; and ENG_SPIN_DOWN going down: the turbines spool up, and down more slowly,
; instead of jumping.  From it:
;   A  noise, the roar: period ENG_NOISE0 - m*13/16, volume ENG_ROAR_VOL0 +
;      m*ENG_VOL_MUL/32
;      (m = eng_cur/ENG_FRAC, whole steps)
;   B  tone, the turbine whine: period ENG_WHINE0 - eng_cur*ENG_WHINE_STEP/
;      ENG_FRAC (sliding smoothly), volume ENG_WHINE_VOL0 + m*ENG_VOL_MUL/32
;   C  the same whine ENG_DETUNE periods lower and ENG_SHIMMER_VOL quieter:
;      the two beat, the turbines' shimmer
; Written only when eng_cur moves.  Nothing while eng_on is 0 (menus).
;------------------------------------------------------------------------------
engine_tick:
        ld a,(eng_on)
        or a
        ret z
        ld a,(speed)
        or a
        jp p,.pos
        neg                             ; reversing: its size
.pos:   or a
        jr nz,.n
        inc a                           ; zero throttle: idle, as speed 1
.n:     cp SPEED_MAX+1
        jr c,.nm
        ld a,SPEED_MAX                  ; (boosting: as flat out)
.nm:    ld e,a
        ld d,ENG_FRAC
        mul d,e                         ; DE = the target, in 1/ENG_FRAC steps
        ld hl,(eng_cur)
        or a
        sbc hl,de                       ; HL = eng_cur - target
        ret z                           ; there: nothing changes
        jr c,.up
        ld bc,-ENG_SPIN_DOWN            ; above: down a step
        add hl,bc
        jr nc,.tgt                      ; (less than a step away: there)
        add hl,de
        jr .set
.up:    ld bc,ENG_SPIN_UP               ; below: up a step
        add hl,bc
        jr c,.tgt                       ; (reached it)
        add hl,de
        jr .set
.tgt:   ex de,hl
.set:   ld (eng_cur),hl
        ld a,AY_SELECT|AY_LEFT|AY_RIGHT|AY_CHIP_1
        ld bc,AY_CTRL_PORT
        out (c),a
        push hl
        ld d,h                          ; B: the whine's period
        ld e,l
        add hl,hl
        add hl,de                       ; eng_cur * ENG_WHINE_STEP
        ex de,hl
        ld b,4
        bsrl de,b                       ; / ENG_FRAC
        ASSERT ENG_WHINE_STEP == 3 && ENG_FRAC == 16
        ld a,ENG_WHINE0
        sub e
        ld l,a                          ; L = the whine's period
        ld e,a
        ld a,AY_TONE_B
        call isr_ay
        ld a,AY_TONE_B+1
        ld e,0
        call isr_ay
        ld a,l                          ; C: a little lower, to beat with B
        add a,ENG_DETUNE
        ld e,a
        ld a,AY_TONE_C
        call isr_ay
        ld a,AY_TONE_C+1
        ld e,0
        call isr_ay
        pop de                          ; m = eng_cur / ENG_FRAC
        ld b,4
        bsrl de,b
        ld h,e                          ; H = m
        ld d,h                          ; A: the roar's noise period
        ld e,ENG_NOISE_MUL
        mul d,e
        ld b,4
        bsrl de,b                       ; m*13/16
        ld a,ENG_NOISE0
        sub e
        ld e,a
        ld a,AY_NOISE
        call isr_ay
        ld d,h                          ; the volumes: louder with speed
        ld e,ENG_VOL_MUL
        mul d,e
        ld b,5
        bsrl de,b
        ld a,e
        ld l,a                          ; L = m*ENG_VOL_MUL/32
        add a,ENG_ROAR_VOL0
        ld e,a
        ld a,AY_VOL_A
        call isr_ay
        ld a,l
        add a,ENG_WHINE_VOL0
        ld e,a
        ld a,AY_VOL_B
        call isr_ay
        ld a,e
        sub ENG_SHIMMER_VOL
        ld e,a
        ld a,AY_VOL_C
        ; fall through

; A = register, E = value: write it to the selected AY chip (here: the
; interrupt's own, as ay_write is in a page that may not be in).  Keeps D,
; E, HL.
isr_ay:
        ld bc,AY_CTRL_PORT
        out (c),a
        ld b,high AY_DATA_PORT
        out (c),e
        ret

;------------------------------------------------------------------------------
; Sound effects, three voices: the weapons on AY 2 (sfx_req), explosions on
; AY 3's channels A and B (sfx2_req), and splats on AY 3's channel C
; (sfx3_req: a tone only, as the chip's noise is the explosions'), so none
; cuts another.  (The splats write only channel C's tone and volume, and
; the explosions leave channel C alone, its tone kept on in the mixer.)  The
; engines have AY 1.  The game asks for a sound by putting its number in a
; voice's request byte (SFX_*, audio.asm): one byte, so safe from any page
; at any time; only the interrupt writes the AY chips.  Each voice plays one
; sound at a time: a new one cuts the last.  A sound is a list of steps, one
; an interrupt (20 ms): each step is AY register / value pairs, ended by
; SFX_STEP (the next step next interrupt) or SFX_END (the sound is over).
; Nothing while eng_on is 0 (menus).
;------------------------------------------------------------------------------
sfx_tick:
        ld a,(eng_on)
        or a
        ret z
        ld hl,sfx_req                   ; the weapons, AY 2
        ld a,AY_SELECT|AY_LEFT|AY_RIGHT|AY_CHIP_2
        call sfx_voice
        ld hl,sfx2_req                  ; explosions, AY 3 (A, B)
        ld a,AY_SELECT|AY_LEFT|AY_RIGHT|AY_CHIP_3
        call sfx_voice
        ld hl,sfx3_req                  ; splats, AY 3 (C)
        ld a,AY_SELECT|AY_LEFT|AY_RIGHT|AY_CHIP_3
        ; fall through

; HL -> a voice (its request byte, then its sound's next step, a word: 0
; none), A = its AY chip's select value: start a sound asked for, and play
; the next step
sfx_voice:
        ld (sv_sel),a
        ld a,(hl)                       ; a new sound asked for?
        or a
        jr z,.play
        ld (hl),0                       ; (taken)
        push hl
        ld hl,sfx_table-2
        add a,a
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE -> it
        pop hl
        inc hl
        ld (hl),e                       ; it starts now (cutting any other)
        inc hl
        ld (hl),d
        dec hl
        dec hl
.play:  inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE -> the next step; HL -> its high byte
        ld a,d
        or e
        ret z                           ; nothing playing
        push hl
        ld a,(sv_sel)
        ld bc,AY_CTRL_PORT
        out (c),a
        ex de,hl
.lp:    ld a,(hl)                       ; this step's register / value pairs
        inc hl
        cp SFX_STEP
        jr z,.step
        cp SFX_END
        jr z,.end
        ld e,(hl)
        inc hl
        call isr_ay
        jr .lp
.end:   ld hl,0                         ; over
.step:  ex de,hl                        ; (the next step, next interrupt)
        pop hl
        ld (hl),d
        dec hl
        ld (hl),e
        ret

; (The sounds themselves are in the resident page: sfx_data.asm.)

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
isr_sp:     dw 0                        ; the interrupted SP
            ds 32                       ; the interrupt's stack
isr_stack:
        ASSERT $ <= $4000                ; (the end of slot 1)
