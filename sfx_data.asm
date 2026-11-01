;==============================================================================
; Z-POLICE - sound effect data (resident: the main page, slot 5, always
; mapped, so the interrupt routine can read it whatever else is paged in)
;
; Played on AY 2 by sfx_tick (interrupts.asm); the game asks for one with
; ld a,SFX_n / ld (sfx_req),a (the numbers are in audio.asm).  A sound is a
; list of steps, one an interrupt (20 ms): each step is AY register / value
; pairs, ended by SFX_STEP (the next step next interrupt) or SFX_END (over).
; The Next's AYs run at 1.75 MHz: a tone of period P is 109375/P Hz; a
; lower noise period is a brighter hiss.
;==============================================================================

; One step of a zap: channel A at tone period p, channel B 2 periods flat
; (the two beat: a buzz), volumes v and v-2
    MACRO SFX_ZAP p, v
        db AY_TONE_A, low (p), AY_TONE_A+1, high (p)
        db AY_TONE_B, low ((p)+2), AY_TONE_B+1, high ((p)+2)
        db AY_VOL_A, v, AY_VOL_B, (v)-2, SFX_STEP
    ENDM

; One step of a woosh: channel A's noise at period n, volume v
    MACRO SFX_WOOSH n, v
        db AY_NOISE, n, AY_VOL_A, v, SFX_STEP
    ENDM

; An explosion: a deep noise (channel A, darkening: period 16 up to 30) over
; a low rumble (channel B, BOOM_RUMBLE), both from volume peak (B 2 less)
; fading to nothing over len steps.  (A falling level is an exponential fade:
; the AY's levels are logarithmic.)
BOOM_RUMBLE     equ 2735            ; 109375 / 2735 = 40 Hz
    MACRO SFX_BOOM peak, len
        db AY_MIXER, SFX_MIX_BOOM       ; (channel C: the splats', left alone)
        db AY_TONE_B, low BOOM_RUMBLE, AY_TONE_B+1, high BOOM_RUMBLE
BOOM_I  DEFL 0
        DUP len
        db AY_NOISE, 16 + (BOOM_I*15)/(len)
        db AY_VOL_A, ((peak)*((len)-BOOM_I)+(len)-1)/(len)
        db AY_VOL_B, (((peak)-2)*((len)-BOOM_I)+(len)-1)/(len)
        db SFX_STEP
BOOM_I  DEFL BOOM_I+1
        EDUP
        db AY_VOL_A, 0, AY_VOL_B, 0, SFX_END
    ENDM

; One step of a splat: channel C (only: see sfx_tick) at tone period p,
; volume v
    MACRO SFX_SPLAT_STEP p, v
        db AY_TONE_C, low (p), AY_TONE_C+1, high (p), AY_VOL_C, v, SFX_STEP
    ENDM

; The sounds, by number (SFX_*, from 1)
sfx_table:
        dw sfx_mg                       ; SFX_MG
        dw sfx_laser                    ; SFX_LASER
        dw sfx_chain                    ; SFX_CHAIN
        dw sfx_rocket                   ; SFX_ROCKET
        dw sfx_missile                  ; SFX_MISSILE
        dw sfx_bofors                   ; SFX_BOFORS
        dw sfx_boom_rocket              ; SFX_BOOM_ROCKET
        dw sfx_boom_missile             ; SFX_BOOM_MISSILE
        dw sfx_boom_bofors              ; SFX_BOOM_BOFORS
        dw sfx_boom_prox                ; SFX_BOOM_PROX
        dw sfx_splat                    ; SFX_SPLAT
        ASSERT SFX_MG == 1 && SFX_LASER == 2 && SFX_CHAIN == 3
        ASSERT SFX_ROCKET == 4 && SFX_MISSILE == 5 && SFX_BOFORS == 6
        ASSERT SFX_BOOM_ROCKET == 7 && SFX_BOOM_MISSILE == 8
        ASSERT SFX_BOOM_BOFORS == 9 && SFX_BOOM_PROX == 10 && SFX_SPLAT == 11
        ASSERT ($ - sfx_table)/2 == SFX_LAST

; The machine gun, heavy: a sharp crack (bright noise) dropping into a deep
; boom (noise, channel A) over a low thump (about 70 Hz, channel B), gone in
; 80 ms
MG_THUMP        equ 1563            ; tone period: 109375 / 1563 = 70 Hz
sfx_mg:
        db AY_MIXER, SFX_MIX_NOISE_A_TONE_B
        db AY_TONE_B, low MG_THUMP, AY_TONE_B+1, high MG_THUMP
        db AY_VOL_C, 0
        db AY_NOISE, 4, AY_VOL_A, 13, AY_VOL_B, 11, SFX_STEP     ; crack
        db AY_NOISE, 18, AY_VOL_A, 10, AY_VOL_B, 9, SFX_STEP     ; boom
        db AY_NOISE, 26, AY_VOL_A, 6, AY_VOL_B, 5, SFX_STEP
        db AY_VOL_A, 3, AY_VOL_B, 2, SFX_STEP
        db AY_VOL_A, 0, AY_VOL_B, 0, SFX_END

; The chain gun: the machine gun's sound 25% higher in pitch (every period
; 4/5 of it: the thump about 88 Hz).  It fires every game frame, so each
; round cuts the last one's tail: a rattle.
CHAIN_THUMP     equ MG_THUMP*4/5    ; 1250: 87.5 Hz
sfx_chain:
        db AY_MIXER, SFX_MIX_NOISE_A_TONE_B
        db AY_TONE_B, low CHAIN_THUMP, AY_TONE_B+1, high CHAIN_THUMP
        db AY_VOL_C, 0
        db AY_NOISE, 3, AY_VOL_A, 13, AY_VOL_B, 11, SFX_STEP     ; crack
        db AY_NOISE, 14, AY_VOL_A, 10, AY_VOL_B, 9, SFX_STEP     ; boom
        db AY_NOISE, 21, AY_VOL_A, 6, AY_VOL_B, 5, SFX_STEP
        db AY_VOL_A, 3, AY_VOL_B, 2, SFX_STEP
        db AY_VOL_A, 0, AY_VOL_B, 0, SFX_END

; The Bofors cannon (and the proximity cannon, its shells fired the same
; way): the machine gun's sound deeper (the thump 30 Hz, the noise periods
; doubled) and louder (every volume 2 levels up: about twice as loud).  The
; noise period can't go past 31, so the boom's later steps (18, 26 doubled)
; stop there, and the volume at 15.
BOFORS_THUMP    equ 3646            ; 109375 / 3646 = 30 Hz
        ASSERT BOFORS_THUMP < 4096
sfx_bofors:
        db AY_MIXER, SFX_MIX_NOISE_A_TONE_B
        db AY_TONE_B, low BOFORS_THUMP, AY_TONE_B+1, high BOFORS_THUMP
        db AY_VOL_C, 0
        db AY_NOISE, 8, AY_VOL_A, 15, AY_VOL_B, 13, SFX_STEP     ; crack
        db AY_NOISE, 31, AY_VOL_A, 12, AY_VOL_B, 11, SFX_STEP    ; boom
        db AY_NOISE, 31, AY_VOL_A, 8, AY_VOL_B, 7, SFX_STEP
        db AY_VOL_A, 5, AY_VOL_B, 4, SFX_STEP
        db AY_VOL_A, 0, AY_VOL_B, 0, SFX_END

; A rocket leaving, a short woosh: noise only (channel A) swelling and
; fading over 200 ms, brightening then darkening as it goes
sfx_rocket:
        db AY_MIXER, SFX_MIX_NOISE_A
        db AY_VOL_B, 0, AY_VOL_C, 0
        SFX_WOOSH 12, 7
        SFX_WOOSH 9, 11
        SFX_WOOSH 7, 13
        SFX_WOOSH 6, 12
        SFX_WOOSH 6, 11
        SFX_WOOSH 7, 9
        SFX_WOOSH 9, 7
        SFX_WOOSH 12, 5
        SFX_WOOSH 16, 3
        SFX_WOOSH 20, 1
        db AY_VOL_A, 0, SFX_END

; A missile leaving: a longer woosh (320 ms), a little deeper, its roar held
; before it fades
sfx_missile:
        db AY_MIXER, SFX_MIX_NOISE_A
        db AY_VOL_B, 0, AY_VOL_C, 0
        SFX_WOOSH 14, 6
        SFX_WOOSH 11, 10
        SFX_WOOSH 9, 12
        SFX_WOOSH 8, 13
        SFX_WOOSH 8, 13
        SFX_WOOSH 8, 12
        SFX_WOOSH 9, 12
        SFX_WOOSH 9, 11
        SFX_WOOSH 10, 10
        SFX_WOOSH 11, 9
        SFX_WOOSH 12, 8
        SFX_WOOSH 14, 6
        SFX_WOOSH 16, 5
        SFX_WOOSH 19, 3
        SFX_WOOSH 22, 2
        SFX_WOOSH 26, 1
        db AY_VOL_A, 0, SFX_END

; Explosions (rocket_blast, weapons.asm; on AY 3).  Each one's loudness in
; proportion to its blast's size, damage x reach (game units):
;   missile 15 x 256 = 3840, rocket 20 x 64 = 1280, Bofors 4 x 38 = 152,
;   proximity 3 x 25 = 75.
; Sound level is logarithmic (about 2 AY levels each doubling), so the peak
; is 15 + 2*log2(size / the missile's): 15, 12, 6, 4; and the bigger the
; blast the longer it rumbles, 2 steps (40 ms) per level: 600, 480, 240 and
; 160 ms.
sfx_boom_missile:
        SFX_BOOM 15, 30
sfx_boom_rocket:
        SFX_BOOM 12, 24
sfx_boom_bofors:
        SFX_BOOM 6, 12
sfx_boom_prox:
        SFX_BOOM 4, 8
        ASSERT MISSILE_DMG*MISSILE_R == 3840 && BLAST_DMG*BLAST_R == 1280
        ASSERT BOFORS_DMG*BOFORS_R == 152 && PROX_DMG*PROX_R == 75

; A zombie hit, a squelchy splat (zdamage, weapons.asm; AY 3 channel C): a
; tone lurching down and up as it falls, a wet gargle, from about 680 Hz to
; 130 Hz over 160 ms, fading.  Each hit cuts the last one's.
sfx_splat:
        SFX_SPLAT_STEP 160, 12
        SFX_SPLAT_STEP 320, 12
        SFX_SPLAT_STEP 210, 11
        SFX_SPLAT_STEP 450, 9
        SFX_SPLAT_STEP 280, 8
        SFX_SPLAT_STEP 620, 6
        SFX_SPLAT_STEP 400, 4
        SFX_SPLAT_STEP 850, 2
        db AY_VOL_C, 0, SFX_END

; The pulse laser, a zap: a tone sweeping down from about 2.7 kHz to 470 Hz
; (channel A), with a second one a little flat beating against it (channel
; B), fading over 140 ms
sfx_laser:
        db AY_MIXER, SFX_MIX_TONE_AB
        db AY_VOL_C, 0
        SFX_ZAP 40, 13
        SFX_ZAP 55, 13
        SFX_ZAP 75, 12
        SFX_ZAP 100, 11
        SFX_ZAP 135, 9
        SFX_ZAP 180, 6
        SFX_ZAP 235, 3
        db AY_VOL_A, 0, AY_VOL_B, 0, SFX_END
