;==============================================================================
; Z-POLICE - audio (8K page PAGE_AUDIO, runs at $E000 in slot 7: page it in
; with nextreg CODE_MMU,PAGE_AUDIO before calling)
;
; Sound devices: the Next's TurboSound, three AY-3-8912 chips.  initgame
; (initialise.asm) has already set the chip mode to AY (NextReg $06),
; turned TurboSound and the internal speaker on (NextReg $08) and the AY
; outputs to stereo (NextReg $09).  init_audio then sets every chip to a
; known, silent state (at start-up, and on every menu screen: menu_clear).
; AY 1 is the VTOL's engines: engine_start here, then the interrupt routine
; plays them (engine_tick, interrupts.asm).  AY 2 is the weapons' sound
; effects, AY 3 explosions: the game asks for one with ld a,SFX_n / ld
; (sfx_req),a (AY 2), ld (sfx2_req),a (AY 3's A and B) or ld (sfx3_req),a
; (AY 3's C), and the interrupt plays it (sfx_tick).  (Music would need AY 3
; back.)  The interrupt writes the AY ports while eng_on is 1,
; so code here writes them only with eng_on 0 (or interrupts off).
;
; TurboSound ports:
;   $FFFD write %1LR111cc: select AY chip cc (AY_CHIP_1..3) with its left
;         (L) and right (R) outputs on;
;         any value 0..15: select that register of the selected chip
;   $BFFD write: the value of the selected register
;==============================================================================

AY_CTRL_PORT    equ $FFFD           ; chip / register select
AY_DATA_PORT    equ $BFFD           ; register value

; Chip select ($FFFD): AY_SELECT | AY_LEFT | AY_RIGHT | AY_CHIP_n
AY_SELECT       equ %10011100       ; bit 7 and bits 4-2 must be set
AY_LEFT         equ %01000000       ; left output on
AY_RIGHT        equ %00100000       ; right output on
AY_CHIP_1       equ %11
AY_CHIP_2       equ %10
AY_CHIP_3       equ %01

; AY registers
AY_TONE_A       equ 0               ; channel A tone period: fine, coarse (4)
AY_TONE_B       equ 2
AY_TONE_C       equ 4
AY_NOISE        equ 6               ; noise period (5 bits)
AY_MIXER        equ 7               ; tone / noise enable, 0 = on:
AY_NO_TONE_A    equ %00000001       ;   bits 0-2 tone A-C off,
AY_NO_TONE_B    equ %00000010
AY_NO_TONE_C    equ %00000100
AY_NO_NOISE_A   equ %00001000       ;   bits 3-5 noise A-C off
AY_NO_NOISE_B   equ %00010000
AY_NO_NOISE_C   equ %00100000
AY_VOL_A        equ 8               ; amplitude 0-15 (bit 4: use envelope)
AY_VOL_B        equ 9
AY_VOL_C        equ 10
AY_ENV_FINE     equ 11              ; envelope period
AY_ENV_COARSE   equ 12
AY_ENV_SHAPE    equ 13              ; envelope shape
AY_REGS         equ 14

AY_ENV_ATTACK_HOLD equ %1101        ; envelope: rise once, then hold
AY_MIXER_INIT   equ AY_NO_NOISE_A|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; tones on, noise off

; The engines (AY 1): jet turbines, from n = |speed| (at least 1: the idle,
; at zero throttle, sounds as speed 1), 1..SPEED_MAX
ENG_MIXER       equ AY_NO_TONE_A|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; A noise only, B and C tone only
ENG_NOISE0      equ 29              ; A, the roar: noise period 29 - n*13/16
ENG_NOISE_MUL   equ 13              ;   (29 at idle, a rumble; 7 flat out, a hiss)
ENG_ROAR_VOL0   equ 4               ;   volume 4 + n*7/32 (4..10)
ENG_WHINE0      equ 222             ; B, the turbine whine: period 222 - 3n
ENG_WHINE_STEP  equ 3               ;   (~500 Hz at idle, ~790 Hz flat out)
ENG_WHINE_VOL0  equ 2               ;   volume 2 + n*7/32 (2..8)
ENG_VOL_MUL     equ 7               ; the volumes rise by n*7/32 (0..6)
ENG_DETUNE      equ 2               ; C, the same whine 2 periods lower: the
ENG_SHIMMER_VOL equ 2               ;   two beat (the turbines' shimmer), 2 quieter
; Sound effects (sfx_tick, interrupts.asm): their numbers, and the step codes
SFX_MG          equ 1               ; the machine gun: one round
SFX_LASER       equ 2               ; the pulse laser: one pulse (a zap)
SFX_CHAIN       equ 3               ; the chain gun: one round
SFX_ROCKET      equ 4               ; a rocket fired: a short woosh
SFX_MISSILE     equ 5               ; a missile fired: a longer woosh
SFX_BOFORS      equ 6               ; the Bofors / proximity cannon: one shell
SFX_BOOM_ROCKET equ 7               ; explosions (AY 3, sfx2_req): a rocket's,
SFX_BOOM_MISSILE equ 8              ;   a missile's,
SFX_BOOM_BOFORS equ 9               ;   a Bofors shell's,
SFX_BOOM_PROX   equ 10              ;   a proximity shell's
SFX_SPLAT       equ 11              ; a zombie hit (AY 3 channel C, sfx3_req)
SFX_LAST        equ 11              ; (sfx_table, sfx_data.asm)
SFX_STEP        equ $FE             ; end of a step: the next, next interrupt
SFX_END         equ $FF             ; end of the sound
SFX_MIX_NOISE_A_TONE_B equ AY_NO_TONE_A|AY_NO_TONE_C|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; mixer: A noise only, B tone only
SFX_MIX_TONE_AB equ AY_NO_TONE_C|AY_NO_NOISE_A|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; mixer: A and B tones only
SFX_MIX_NOISE_A equ AY_NO_TONE_A|AY_NO_TONE_B|AY_NO_TONE_C|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; mixer: A noise only
SFX_MIX_BOOM    equ AY_NO_TONE_A|AY_NO_NOISE_B|AY_NO_NOISE_C
                                    ; AY 3's mixer: A noise, B tone (the
                                    ; explosions), C tone (the splats)
        ASSERT AY_REGS < SFX_STEP

ENG_FRAC        equ 16              ; the engines' speed (eng_cur) in 1/16 steps:
ENG_SPIN_UP     equ 4               ;   up by at most 4/16 an interrupt (12.5 steps
ENG_SPIN_DOWN   equ 2               ;   a second), down by 2/16 (6.25 a second)
        ASSERT ENG_SPIN_UP > 0 && ENG_SPIN_DOWN > 0
        ASSERT -SPEED_MIN <= SPEED_MAX
        ASSERT ENG_WHINE0 - SPEED_MAX*ENG_WHINE_STEP > 0 && ENG_WHINE0 + ENG_DETUNE < 256
        ASSERT ENG_NOISE0 < 32 && ENG_NOISE0 - (SPEED_MAX*ENG_NOISE_MUL)/16 >= 1
        ASSERT ENG_ROAR_VOL0 + SPEED_MAX*ENG_VOL_MUL/32 <= 15 && ENG_WHINE_VOL0 + SPEED_MAX*ENG_VOL_MUL/32 <= 15
        ASSERT SPEED_MAX*ENG_VOL_MUL < 256
        ASSERT ENG_WHINE_VOL0 >= ENG_SHIMMER_VOL

;------------------------------------------------------------------------------
; Set up the sound devices: each AY chip selected with both outputs, every
; register 0 (silent: all volumes 0), then the mixer to tones only and the
; envelope to attack-and-hold.  AY 1 is left selected.
;------------------------------------------------------------------------------
init_audio:
        xor a                           ; the engines off first: the interrupt
        ld (eng_on),a                   ; leaves the AYs alone (interrupts.asm)
        ld (sfx_req),a                  ; and no sound effect asked for or
        ld (sfx2_req),a                 ; playing, on any voice
        ld (sfx3_req),a
        ld h,a
        ld l,a
        ld (sfx_ptr),hl
        ld (sfx2_ptr),hl
        ld (sfx3_ptr),hl
        ld a,AY_CHIP_3
        call ay_init_chip
        ld a,AY_CHIP_2
        call ay_init_chip
        ld a,AY_CHIP_1
        ; fall through

; A = chip (AY_CHIP_n): select it in stereo, clear it, mixer and envelope
ay_init_chip:
        call ay_select
        ld d,AY_REGS-1                  ; registers 13..0 = 0
.clr:   ld a,d
        ld e,0
        call ay_write
        dec d
        jp p,.clr
        ld a,AY_MIXER
        ld e,AY_MIXER_INIT
        call ay_write
        ld a,AY_ENV_SHAPE
        ld e,AY_ENV_ATTACK_HOLD
        jp ay_write

;------------------------------------------------------------------------------
; The VTOL's engines: jet turbines, not rotors, so a steady roar and whine
; rather than a chop.  AY 1, all three channels, kept for them.  They never
; stop in play: at zero throttle they idle, as at speed 1.  The interrupt
; routine plays them, 50 times a second (engine_tick, interrupts.asm): the
; sound's speed spools towards the VTOL's, so pitch and volume rise and fall
; smoothly.  (The Next's AYs run at 1.75 MHz: a tone of period P is
; 109375/P Hz.)
;------------------------------------------------------------------------------
; Start of each level (next_level): AY 1's mixer for the engines, the sound's
; speed 0 (they spool up to the idle), and the interrupt playing them
engine_start:
        xor a
        ld (eng_on),a                   ; (the interrupt off AY 1 meanwhile)
        ld hl,0
        ld (eng_cur),hl
        ld a,AY_CHIP_1
        call ay_select
        ld a,AY_MIXER
        ld e,ENG_MIXER
        call ay_write
        ld a,1
        ld (eng_on),a                   ; the interrupt plays them now
        ret

;------------------------------------------------------------------------------
; A = chip (AY_CHIP_n): select it, with both outputs on
;------------------------------------------------------------------------------
ay_select:
        or AY_SELECT|AY_LEFT|AY_RIGHT
        ld bc,AY_CTRL_PORT
        out (c),a
        ret

;------------------------------------------------------------------------------
; A = register, E = value: write it to the selected chip.  Keeps D, E, HL.
;------------------------------------------------------------------------------
ay_write:
        ld bc,AY_CTRL_PORT
        out (c),a
        ld b,high AY_DATA_PORT
        out (c),e
        ret
