;==============================================================================
; Z-POLICE - the sound players (in the audio page, PAGE_AUDIO, with
; audio.asm and the sounds, sfx_data.asm): called by the interrupt routine
; (im2_routine, interrupts.asm) 50 times a second with this page mapped
; into slot 7 for them (the page there put back after).  The game asks for
; a sound through the resident request bytes (sfx_req, sfx2_req, sfx3_req:
; interrupts.asm), so any page can.
;==============================================================================

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

