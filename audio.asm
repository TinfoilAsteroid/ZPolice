;==============================================================================
; Z-POLICE - audio (8K page PAGE_AUDIO, runs at $E000 in slot 7: page it in
; with nextreg CODE_MMU,PAGE_AUDIO before calling)
;
; Sound devices: the Next's TurboSound, three AY-3-8912 chips.  initgame
; (initialise.asm) has already set the chip mode to AY (NextReg $06),
; turned TurboSound and the internal speaker on (NextReg $08) and the AY
; outputs to stereo (NextReg $09).  init_audio then sets every chip to a
; known, silent state.  Sound effects and music will go on top of this.
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

;------------------------------------------------------------------------------
; Set up the sound devices: each AY chip selected with both outputs, every
; register 0 (silent: all volumes 0), then the mixer to tones only and the
; envelope to attack-and-hold.  AY 1 is left selected.
;------------------------------------------------------------------------------
init_audio:
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
        jr ay_write

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
