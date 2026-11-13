;==============================================================================
; Z-POLICE - input: keyboard and joysticks (8K page PAGE_INPUT, runs at
; $E000 in slot 7: main_loop and the menu page it in, and the game logic
; pages in slot 6 call it)
;
; Redefinable controls.  An input (a key, or a joystick direction or button)
; is a 16-bit code: high byte = input bank, low byte = bit mask within it.
;   banks 0-7: the ZX Spectrum keyboard half-rows (port $xxFE, address line
;              A8+bank low): read 0 = pressed
;   bank 8:    NextReg $B0, Extended Keys 0: read 1 = pressed
;   bank 9:    NextReg $B1, Extended Keys 1: read 1 = pressed
;   bank 10:   port $1F, Kempston 1 / Mega Drive 1 (J1_*): read 1 = pressed
;   bank 11:   port $37, Kempston 2 / Mega Drive 2 (J2_*): read 1 = pressed
;   bank 12:   NextReg $B2, the 6-button Mega Drive pads' X, Y, Z and MODE
;              (left connector J1_*, right J2_*): read 1 = pressed
; A joystick bank is read only while a joystick is set (NextReg $05, the
; Next's joystick modes) to the port it reads, else it is 0: so an unused
; port can't read as everything pressed.  Joysticks in Sinclair or Cursor
; mode enter keys (6-0, 1-5, 5-8) and are read as keys.
; kbd_scan, once per frame at the top of the main loop, reads all the banks
; into key_now, inverting the ZX rows so that every bank holds 1 = pressed,
; and keeps the previous scan in key_prev.  The game asks about actions
; (K_FIRE, K_LEFT, ...), not inputs: each action has a key (key_defs) and a
; joystick input (joy_defs; 0 = none), either of which works, so both can
; be redefined (key_define) at any time.
;   key_held    A = action -> NZ if its key or joystick input is down
;   key_pressed A = action -> NZ if its key or joystick input went down
;               since the last scan
;   key_find    -> NZ and HL = code of an input that is down (for a
;               redefine screen); Z if none
;   key_code_pressed  HL = key code -> NZ if that key went down
; The Next normally also enters the extended keys into the 8x5 matrix (e.g.
; cursor LEFT as CAPS SHIFT + 5).  NextReg $68 bit 4 stops that: set it with
; kbd_double_on (KBD_STOP_DOUBLING = TRUE), clear it with kbd_double_off
; (FALSE, the default).
;==============================================================================

; --- key codes: bank << 8 | mask ---------------------------------------------
KB_SHIFT    equ $0001                   ; bank 0: $FEFE
KB_Z        equ $0002
KB_X        equ $0004
KB_C        equ $0008
KB_V        equ $0010
KB_A        equ $0101                   ; bank 1: $FDFE
KB_S        equ $0102
KB_D        equ $0104
KB_F        equ $0108
KB_G        equ $0110
KB_Q        equ $0201                   ; bank 2: $FBFE
KB_W        equ $0202
KB_E        equ $0204
KB_R        equ $0208
KB_T        equ $0210
KB_1        equ $0301                   ; bank 3: $F7FE
KB_2        equ $0302
KB_3        equ $0304
KB_4        equ $0308
KB_5        equ $0310
KB_0        equ $0401                   ; bank 4: $EFFE
KB_9        equ $0402
KB_8        equ $0404
KB_7        equ $0408
KB_6        equ $0410
KB_P        equ $0501                   ; bank 5: $DFFE
KB_O        equ $0502
KB_I        equ $0504
KB_U        equ $0508
KB_Y        equ $0510
KB_ENTER    equ $0601                   ; bank 6: $BFFE
KB_L        equ $0602
KB_K        equ $0604
KB_J        equ $0608
KB_H        equ $0610
KB_SPACE    equ $0701                   ; bank 7: $7FFE
KB_SYM      equ $0702
KB_M        equ $0704
KB_N        equ $0708
KB_B        equ $0710
KB_RIGHT    equ $0801                   ; bank 8: NextReg $B0
KB_LEFT     equ $0802
KB_DOWN     equ $0804
KB_UP       equ $0808
KB_PERIOD   equ $0810
KB_COMMA    equ $0820
KB_QUOTE    equ $0840
KB_SEMI     equ $0880
KB_EXTEND   equ $0901                   ; bank 9: NextReg $B1
KB_CAPSLOCK equ $0902
KB_GRAPH    equ $0904
KB_TRUEVID  equ $0908
KB_INVVID   equ $0910
KB_BREAK    equ $0920
KB_EDIT     equ $0940
KB_DELETE   equ $0980
JOY_BANK    equ 10                      ; the first joystick bank
J1_RIGHT    equ $0A01                   ; bank 10: port $1F (Kempston 1 /
J1_LEFT     equ $0A02                   ;   Mega Drive 1)
J1_DOWN     equ $0A04
J1_UP       equ $0A08
J1_FIRE     equ $0A10                   ; (Mega Drive: B)
J1_C        equ $0A20                   ; Mega Drive C, A, START
J1_A        equ $0A40
J1_START    equ $0A80
J2_RIGHT    equ $0B01                   ; bank 11: port $37 (Kempston 2 /
J2_LEFT     equ $0B02                   ;   Mega Drive 2)
J2_DOWN     equ $0B04
J2_UP       equ $0B08
J2_FIRE     equ $0B10
J2_C        equ $0B20
J2_A        equ $0B40
J2_START    equ $0B80
J1_MODE     equ $0C01                   ; bank 12: NextReg $B2, 6-button
J1_Y        equ $0C02                   ;   pads (left connector)
J1_Z        equ $0C04
J1_X        equ $0C08
J2_MODE     equ $0C10                   ;   (right connector)
J2_Y        equ $0C20
J2_Z        equ $0C40
J2_X        equ $0C80
KEY_BANKS   equ 13
JP_1F_B     equ 0                       ; joystick ports in use (joy_ports):
JP_37_B     equ 1                       ;   $1F, $37, the 6-button extras
JP_MD_B     equ 2
FALSE       equ 0
TRUE        equ 1

; --- actions: index into key_defs --------------------------------------------
K_SPEED_UP  equ 0
K_SPEED_DN  equ 1
K_AIRBRAKE  equ 2                       ; air brake: rapid stop
K_LEFT      equ 3
K_RIGHT     equ 4
K_CLIMB     equ 5
K_DESCEND   equ 6
K_NOSE_UP   equ 7
K_NOSE_DN   equ 8
K_FIRE      equ 9
K_GUN_UP    equ 10                      ; tilt the centre gun up,
K_SLOT1     equ 11                      ; select weapon slots 1-5
K_GUN_DN    equ 16                      ; down,
K_GUN_CTR   equ 17                      ; and back to the centre
K_PAUSE     equ 18                      ; pause / resume (main_loop)
K_BOOST     equ 19                      ; the booster on / off (player.asm)
K_VISION    equ 20                      ; the next vision mode (vis_cycle)
K_STRAFE_L  equ 21                      ; a lateral thrusters pulse left,
K_STRAFE_R  equ 22                      ;   right (player.asm strafe)
K_TARGET    equ 23                      ; the missile lock's next target
                                        ;   (weapons.asm lk_next)
K_ACTIONS   equ 24

;------------------------------------------------------------------------------
; Read all the input banks: key_prev = last scan, key_now = this one, every
; bit 1 = pressed
;------------------------------------------------------------------------------
kbd_scan:
        ld hl,key_now
        ld de,key_prev
        ld bc,KEY_BANKS
        ldir
        ld hl,key_now
        ld bc,$FEFE                     ; banks 0-7: half-rows $FE..$7F
.row:   in a,(c)
        cpl                             ; 0 = pressed -> 1 = pressed
        and %00011111
        ld (hl),a
        inc hl
        rlc b                           ; next half-row
        jr c,.row                       ; (stops after $7F)
        ld bc,$243B                     ; banks 8, 9: NextRegs $B0, $B1
        ld a,$B0
        out (c),a
        inc b
        in a,(c)                        ; already 1 = pressed
        ld (hl),a
        inc hl
        dec b
        ld a,$B1
        out (c),a
        inc b
        in a,(c)
        ld (hl),a
        inc hl
        ; banks 10-12, the joysticks: only the ports a joystick is set to
        ; (NextReg $05), so an unused port can't read as all pressed
        dec b                           ; (BC = $243B)
        ld a,$05
        out (c),a
        inc b
        in e,(c)                        ; the joystick modes
        ld a,e                          ; joystick 1: bits 7-6, and bit 3
        rlca
        rlca
        and 3
        bit 3,e
        jr z,.j1
        or 4
.j1:    call joy_ports
        ld d,a                          ; D: the ports in use (JP_*)
        ld a,e                          ; joystick 2: bits 5-4, and bit 1
        rrca
        rrca
        rrca
        rrca
        and 3
        bit 1,e
        jr z,.j2
        or 4
.j2:    call joy_ports
        or d
        ld d,a
        xor a                           ; bank 10: port $1F
        bit JP_1F_B,d
        jr z,.p1
        in a,($1F)
        call joy_sane
.p1:    ld (hl),a
        inc hl
        xor a                           ; bank 11: port $37
        bit JP_37_B,d
        jr z,.p2
        in a,($37)
        call joy_sane
.p2:    ld (hl),a
        inc hl
        xor a                           ; bank 12: NextReg $B2, the 6-button
        bit JP_MD_B,d                   ; pads' extra buttons
        jr z,.p3
        ld bc,$243B
        ld a,$B2
        out (c),a
        inc b
        in a,(c)
.p3:    ld (hl),a
        ret
        ASSERT KEY_BANKS == 13 && JOY_BANK == 10

; A = a joystick mode (NextReg $05: 0 Sinclair 2, 1 Kempston 1, 2 Cursor,
; 3 Sinclair 1, 4 Kempston 2, 5 Mega Drive 1, 6 Mega Drive 2, 7 I/O) -> A =
; the ports it is read through (JP_* bits).  Keeps DE, HL.
joy_ports:
        push hl
        ld hl,joy_mode_ports
        add hl,a
        ld a,(hl)
        pop hl
        ret

joy_mode_ports:
        db 0, 1<<JP_1F_B, 0, 0, 1<<JP_37_B
        db 1<<JP_1F_B | 1<<JP_MD_B, 1<<JP_37_B | 1<<JP_MD_B, 0

; A = a Kempston / Mega Drive port read -> A, or 0 if it reads left and
; right at once (no stick can: nothing there).  Uses C.
joy_sane:
        ld c,a
        and %00000011
        cp %00000011
        ld a,c
        ret nz
        xor a
        ret

; Stop the extended keys also appearing in the 8x5 matrix:
; KBD_STOP_DOUBLING = TRUE, NextReg $68 bit 4 = 1
kbd_double_on:
        ld a,TRUE
        jr kbd_double

; Let the extended keys also appear in the 8x5 matrix (the default):
; KBD_STOP_DOUBLING = FALSE, NextReg $68 bit 4 = 0
kbd_double_off:
kdb_double_off:                         ; (alias: the name as first asked for)
        xor a                           ; FALSE

; A = TRUE / FALSE: store it, and set NextReg $68 bit 4 to match, keeping
; the register's other bits
kbd_double:
        ld (KBD_STOP_DOUBLING),a
        ld bc,$243B
        ld a,$68
        out (c),a
        inc b
        in a,(c)                        ; current NextReg $68
        res 4,a
        ld hl,KBD_STOP_DOUBLING
        bit 0,(hl)
        jr z,.w
        set 4,a
.w:     out (c),a                       ; ($253B: still selects $68)
        ret

; A = action -> NZ if its key or its joystick input is down.  Preserves BC,
; DE, HL.
key_held:
        push hl
        push bc
        ld c,a
        call key_def
        and (hl)
        jr nz,.x
        ld a,c
        call joy_def
        and (hl)
.x:     pop bc
        pop hl
        ret

; A = action -> NZ if its key or its joystick input is down now but wasn't
; at the last scan.  Preserves BC, DE, HL.
key_pressed:
        push hl
        push bc
        ld b,a
        call key_def
        call def_new
        jr nz,.x
        ld a,b
        call joy_def
        call def_new
.x:     pop bc
        pop hl
        ret

; HL -> key_now[bank], A = mask -> NZ if down now but not at the last scan
; (a mask of 0, no input: never).  Uses C.
def_new:
        ld c,a
        and (hl)
        ret z                           ; not down
        ld a,c
        push de
        ld de,KEY_BANKS
        add hl,de                       ; key_prev, same bank
        and (hl)
        pop de
        xor c                           ; down before: Z; new: NZ
        ret

; HL = a key code (KB_...) -> NZ if that key went down since the last scan
; (for fixed keys, such as the menu's).  Preserves BC, DE, HL.
key_code_pressed:
        push hl
        push bc
        ld c,l                          ; mask
        ld a,h                          ; bank
        ld hl,key_now
        add hl,a
        ld a,c
        and (hl)
        jr z,.x                         ; not down
        push de
        ld de,KEY_BANKS
        add hl,de                       ; key_prev, same bank
        and (hl)
        pop de
        xor c                           ; down before: Z; new: NZ
.x:     pop bc
        pop hl
        ret

; A = action -> HL -> key_now[its key's bank], A = its key's mask
key_def:
        ld hl,key_defs
        ; fall through

; HL = key_defs or joy_defs, A = action -> HL -> key_now[the bank], A = mask
def_at:
        add a,a
        add hl,a
        ld a,(hl)                       ; mask
        inc hl
        push af
        ld a,(hl)                       ; bank
        ld hl,key_now
        add hl,a
        pop af
        ret

; A = action -> HL -> key_now[its joystick input's bank], A = its mask (0:
; none)
joy_def:
        ld hl,joy_defs
        jr def_at

; A = action, HL = an input's code: redefine the action's key, or its
; joystick input if the code is a joystick's (bank JOY_BANK on).  Uses B.
key_define:
        ex de,hl
        add a,a
        ld hl,key_defs
        ld b,a
        ld a,d
        cp JOY_BANK
        ld a,b
        jr c,.k
        ld hl,joy_defs
.k:     add hl,a
        ld (hl),e
        inc hl
        ld (hl),d
        ex de,hl
        ret

; -> NZ and HL = code of an input that is down (lowest bank, lowest bit); Z
; if none.  For a redefine screen.
key_find:
        ld hl,key_now
        ld c,0                          ; bank
.b:     ld a,(hl)
        or a
        jr nz,.got
        inc hl
        inc c
        ld a,c
        cp KEY_BANKS
        jr nz,.b
        xor a                           ; Z: nothing down
        ret
.got:   ld b,1                          ; lowest bit set
.m:     rra
        jr c,.f
        sla b
        jr .m
.f:     ld h,c
        ld l,b
        or 1                            ; NZ
        ret

;==============================================================================
; Input data
;==============================================================================
KBD_STOP_DOUBLING:
            db FALSE                    ; TRUE: NextReg $68 bit 4 set, extended
                                        ; keys kept out of the 8x5 matrix
key_now:    ds KEY_BANKS                ; this scan, 1 = pressed
key_prev:   ds KEY_BANKS                ; the scan before (must follow key_now)
; The key and the joystick input of each action, by K_*: the defaults
; (key_defaults, joy_defaults), and the ones in use (key_defs, joy_defs:
; redefinable on the redefine keys screen, keydef.asm, which can put the
; defaults back).  Each set in that order: key_defs, joy_defs, key_defaults,
; joy_defaults, one after another (keydef.asm copies all four as one).
    MACRO KEY_DEFAULTS
            dw KB_Q                     ; K_SPEED_UP
            dw KB_A                     ; K_SPEED_DN
            dw KB_Z                     ; K_AIRBRAKE
            dw KB_O                     ; K_LEFT
            dw KB_P                     ; K_RIGHT
            dw KB_W                     ; K_CLIMB
            dw KB_S                     ; K_DESCEND
            dw KB_E                     ; K_NOSE_UP
            dw KB_D                     ; K_NOSE_DN
            dw KB_SPACE                 ; K_FIRE
            dw KB_R                     ; K_GUN_UP
            dw KB_1, KB_2, KB_3, KB_4, KB_5     ; K_SLOT1..5
            dw KB_F                     ; K_GUN_DN
            dw KB_V                     ; K_GUN_CTR
            dw KB_BREAK                 ; K_PAUSE
            dw KB_X                     ; K_BOOST
            dw KB_N                     ; K_VISION
            dw KB_K, KB_L               ; K_STRAFE_L, K_STRAFE_R
            dw KB_M                     ; K_TARGET
    ENDM
; The joystick defaults: the stick flies (left / right turn, up / down climb
; and descend), FIRE (Mega Drive B) fires; a Mega Drive pad's C / A are
; speed up / down, START pauses, and a 6-button pad's X is the air brake,
; Y / Z nose up / down, MODE the boost.  0: none.
    MACRO JOY_DEFAULTS
            dw J1_C                     ; K_SPEED_UP
            dw J1_A                     ; K_SPEED_DN
            dw J1_X                     ; K_AIRBRAKE
            dw J1_LEFT                  ; K_LEFT
            dw J1_RIGHT                 ; K_RIGHT
            dw J1_UP                    ; K_CLIMB
            dw J1_DOWN                  ; K_DESCEND
            dw J1_Y                     ; K_NOSE_UP
            dw J1_Z                     ; K_NOSE_DN
            dw J1_FIRE                  ; K_FIRE
            dw 0                        ; K_GUN_UP
            dw 0, 0, 0, 0, 0            ; K_SLOT1..5
            dw 0                        ; K_GUN_DN
            dw 0                        ; K_GUN_CTR
            dw J1_START                 ; K_PAUSE
            dw J1_MODE                  ; K_BOOST (a 6-button pad's MODE)
            dw 0                        ; K_VISION
            dw 0, 0                     ; K_STRAFE_L, K_STRAFE_R
            dw 0                        ; K_TARGET
    ENDM
key_defs:   KEY_DEFAULTS
            ASSERT $ - key_defs == K_ACTIONS*2
joy_defs:   JOY_DEFAULTS
            ASSERT $ - joy_defs == K_ACTIONS*2
key_defaults: KEY_DEFAULTS
joy_defaults: JOY_DEFAULTS
            ASSERT key_defaults == key_defs + 2*K_ACTIONS*2
            ASSERT $ - key_defaults == 2*K_ACTIONS*2
