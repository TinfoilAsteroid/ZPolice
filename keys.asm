;==============================================================================
; Z-POLICE - keyboard (8K page PAGE_KEYS, runs at $E000 in slot 7: main_loop
; and the menu page it in, and the game logic pages in slot 6 call it)
;
; Redefinable keys.  A key is a 16-bit code: high byte = key bank, low byte
; = bit mask within that bank.
;   banks 0-7: the ZX Spectrum keyboard half-rows (port $xxFE, address line
;              A8+bank low): read 0 = pressed
;   bank 8:    NextReg $B0, Extended Keys 0: read 1 = pressed
;   bank 9:    NextReg $B1, Extended Keys 1: read 1 = pressed
; kbd_scan, once per frame at the top of the main loop, reads all ten banks
; into key_now, inverting the ZX rows so that every bank holds 1 = pressed,
; and keeps the previous scan in key_prev.  The game asks about actions
; (K_FIRE, K_LEFT, ...), not keys: key_defs holds the key code of each
; action, so keys can be redefined (key_define) at any time.
;   key_held    A = action -> NZ if its key is down
;   key_pressed A = action -> NZ if its key went down since the last scan
;   key_find    -> NZ and HL = code of a key that is down (for a redefine
;               screen); Z if none
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
KEY_BANKS   equ 10
FALSE       equ 0
TRUE        equ 1

; --- actions: index into key_defs --------------------------------------------
K_SPEED_UP  equ 0
K_SPEED_DN  equ 1
K_STOP      equ 2
K_LEFT      equ 3
K_RIGHT     equ 4
K_CLIMB     equ 5
K_DESCEND   equ 6
K_NOSE_UP   equ 7
K_NOSE_DN   equ 8
K_FIRE      equ 9
K_WEAPON    equ 10                      ; cycle the centre slot's weapon
K_SLOT1     equ 11                      ; select weapon slots 1-5
K_ACTIONS   equ 16

;------------------------------------------------------------------------------
; Read all ten key banks: key_prev = last scan, key_now = this one, every bit
; 1 = pressed
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

; A = action -> NZ if its key is down.  Preserves BC, DE, HL.
key_held:
        push hl
        call key_def
        and (hl)
        pop hl
        ret

; A = action -> NZ if its key is down now but wasn't at the last scan.
; Preserves BC, DE, HL.
key_pressed:
        push hl
        push bc
        call key_def
        ld c,a
        and (hl)
        jr z,.x                         ; not down
        ld a,c
        push de
        ld de,KEY_BANKS
        add hl,de                       ; key_prev, same bank
        and (hl)
        pop de
        xor c                           ; down before: Z; new: NZ
.x:     pop bc
        pop hl
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

; A = action -> HL -> key_now[its bank], A = its mask
key_def:
        add a,a
        ld hl,key_defs
        add hl,a
        ld a,(hl)                       ; mask
        inc hl
        push af
        ld a,(hl)                       ; bank
        ld hl,key_now
        add hl,a
        pop af
        ret

; A = action, HL = key code: redefine the action's key
key_define:
        ex de,hl
        add a,a
        ld hl,key_defs
        add hl,a
        ld (hl),e
        inc hl
        ld (hl),d
        ex de,hl
        ret

; -> NZ and HL = code of a key that is down (lowest bank, lowest bit); Z if
; none.  For a redefine screen.
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
; Keyboard data
;==============================================================================
KBD_STOP_DOUBLING:
            db FALSE                    ; TRUE: NextReg $68 bit 4 set, extended
                                        ; keys kept out of the 8x5 matrix
key_now:    ds KEY_BANKS                ; this scan, 1 = pressed
key_prev:   ds KEY_BANKS                ; the scan before (must follow key_now)
key_defs:                               ; the key of each action (redefinable)
            dw KB_Q                     ; K_SPEED_UP
            dw KB_A                     ; K_SPEED_DN
            dw KB_Z                     ; K_STOP
            dw KB_O                     ; K_LEFT
            dw KB_P                     ; K_RIGHT
            dw KB_W                     ; K_CLIMB
            dw KB_S                     ; K_DESCEND
            dw KB_E                     ; K_NOSE_UP
            dw KB_D                     ; K_NOSE_DN
            dw KB_SPACE                 ; K_FIRE
            dw KB_0                     ; K_WEAPON
            dw KB_1, KB_2, KB_3, KB_4, KB_5     ; K_SLOT1..5
            ASSERT $ - key_defs == K_ACTIONS*2
