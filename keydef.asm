;==============================================================================
; Z-POLICE - redefine keys screen (8K page PAGE_KEYDEF, runs at $C000 in
; slot 6)
;
; From the main menu (option 9, keydef_go pages it in).  Lists every control
; (K_ACTIONS of them) with its key (key_defs) and its joystick input
; (joy_defs, "-" for none; input.asm).
;   Q / A  move the highlight up / down the list (white; highlighted green)
;   SPACE  "PRESS A KEY OR JOYSTICK", a second's pause, then the next input
;          becomes the highlighted control's key, or its joystick input if
;          it is a joystick's, unless another control already uses it: then
;          "KEY ALREADY IN USE" (for a second) and no change
;   0      every key and joystick input back to its default (key_defaults,
;          joy_defaults)
;   1      back to the main menu (menu_go)
; These keys are fixed (key_code_pressed), whatever the controls are set to.
; Uses the resident text routines (text.asm) and the input page in slot 7.
;==============================================================================

KD_ROW0         equ 1               ; first row of the list (under the title)
KD_NAME_COL     equ 1               ; control names,
KD_KEY_COL      equ 16              ; their keys,
KD_KEY_LEN      equ 7               ;   (key names at most this long)
KD_JOY_COL      equ 24              ; their joystick inputs
KD_JOY_LEN      equ 8               ;   (joystick names at most this long)
        ASSERT KD_KEY_COL + KD_KEY_LEN < KD_JOY_COL && KD_JOY_COL + KD_JOY_LEN <= 32
KD_MSG_ROW      equ 21              ; messages
KD_PAUSE        equ 50              ; a second of 50 Hz frames
        ASSERT KD_ROW0 + K_ACTIONS <= KD_MSG_ROW

keydef_screen:
        ld sp,stack_top
        nextreg CODE_MMU,PAGE_INPUT     ; the input page at $E000
        call menu_clear
        ld hl,kd_text                   ; title and help
.txt:   ld a,(hl)
        cp $FF
        jr z,.go
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld c,(hl)
        inc hl
        call menu_print
        jr .txt
.go:    xor a
        ld (kd_cur),a
.draw:  call kd_draw
.loop:  call menu_frame
        call zrand                      ; (keep stirring the seed)
        call kbd_scan
        ld hl,KB_1                      ; back to the main menu
        call key_code_pressed
        jp nz,menu_go                   ; (zpolice.asm)
        ld hl,KB_0                      ; the defaults
        call key_code_pressed
        jr z,.up
        ld hl,key_defaults              ; (and joy_defaults, after it)
        ld de,key_defs                  ; (and joy_defs)
        ld bc,2*K_ACTIONS*2
        ldir
        jr .draw
.up:    ld hl,KB_Q
        call key_code_pressed
        jr z,.dn
        ld a,(kd_cur)
        or a
        jr z,.dn
        dec a
        ld (kd_cur),a
        jr .draw
.dn:    ld hl,KB_A
        call key_code_pressed
        jr z,.sp
        ld a,(kd_cur)
        inc a
        cp K_ACTIONS
        jr nc,.sp
        ld (kd_cur),a
        jr .draw
.sp:    ld hl,KB_SPACE                  ; change the highlighted one
        call key_code_pressed
        jr z,.loop
        call kd_change
        jr .draw

;------------------------------------------------------------------------------
; SPACE: "PRESS A KEY OR JOYSTICK", a second's pause, then the next input
; becomes the highlighted control's key (or its joystick input, if it is a
; joystick's), if no other control uses it
kd_change:
        ld hl,txt_kd_select
        ld c,MENU_TITLE
        call kd_msg
        ld b,KD_PAUSE                   ; a second (keys still read, so one
.p:     push bc                         ; held now isn't new after it)
        call menu_frame
        call kbd_scan
        pop bc
        djnz .p
.w:     call menu_frame                 ; wait for a key newly pressed
        call zrand
        call kbd_scan
        call kd_new_key
        jr z,.w
        ld (kd_code),de
        ld hl,key_defs                  ; a key, or a joystick input?
        ld a,d
        cp JOY_BANK
        jr c,.t
        ld hl,joy_defs
.t:     ld (kd_table),hl
        ld b,0                          ; in use by another control?
.u:     ld a,(kd_cur)
        cp b
        jr z,.nu                        ; (its own key: fine)
        ld a,(hl)
        cp e
        jr nz,.nu
        inc hl
        ld a,(hl)
        dec hl
        cp d
        jr z,.used
.nu:    inc hl
        inc hl
        inc b
        ld a,b
        cp K_ACTIONS
        jr nz,.u
        ld a,(kd_cur)                   ; free: it's the control's key (or
        add a,a                         ; joystick input) now
        ld hl,(kd_table)
        add hl,a
        ld de,(kd_code)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,txt_kd_blank              ; (the message gone)
        ld c,MENU_ATTR
        jp kd_msg
.used:  ld hl,txt_kd_used               ; already a control's key: no change
        ld c,MENU_BAD
        call kd_msg
        ld b,KD_PAUSE
.q:     push bc
        call menu_frame
        call kbd_scan
        pop bc
        djnz .q
        ld hl,txt_kd_blank
        ld c,MENU_ATTR
        jp kd_msg

; NZ if an input (a key or a joystick's) went down since the last scan: DE =
; its code (bank in D, its bit in E; the lowest bank and bit if several)
kd_new_key:
        ld hl,key_now
        ld d,0
.b:     push hl
        ld a,KEY_BANKS                  ; key_prev, the same bank
        add hl,a
        ld a,(hl)
        cpl                             ; not down before
        pop hl
        and (hl)                        ; and down now
        jr nz,.got
        inc hl
        inc d
        ld a,d
        cp KEY_BANKS
        jr nz,.b
        xor a                           ; none (Z)
        ret
.got:   ld c,a                          ; the lowest bit: A AND -A
        neg
        and c
        ld e,a                          ; (NZ)
        ret

; HL -> message, C = attribute: shown on the message row (cleared first)
kd_msg:
        push hl
        push bc
        ld hl,txt_kd_blank
        ld c,MENU_ATTR
        ld de,KD_MSG_ROW<<8 | 1
        call menu_print
        pop bc
        pop hl
        ld de,KD_MSG_ROW<<8 | 1
        jp menu_print

;------------------------------------------------------------------------------
; The list: each control's name, key and joystick input, the highlighted
; one green
kd_draw:
        xor a
.lp:    ld (kd_i),a
        ld c,MENU_ATTR
        ld hl,kd_cur
        cp (hl)
        jr nz,.c
        ld c,MENU_OK                    ; highlighted: green
.c:     ld a,c
        ld (kd_attr),a
        ld a,(kd_i)                     ; its name
        add a,a
        ld hl,kd_names
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,(kd_i)
        add a,KD_ROW0
        ld d,a
        ld e,KD_NAME_COL
        ld a,(kd_attr)
        ld c,a
        call menu_print
        ld a,(kd_i)                     ; its key
        add a,a
        ld hl,key_defs
        add hl,a
        ld e,KD_KEY_COL
        ld bc,txt_kd_keyblank
        call kd_field
        ld a,(kd_i)                     ; its joystick input
        add a,a
        ld hl,joy_defs
        add hl,a
        ld e,KD_JOY_COL
        ld bc,txt_kd_joyblank
        call kd_field
        ld a,(kd_i)
        inc a
        cp K_ACTIONS
        jr nz,.lp
        ret

; Row kd_i in colour kd_attr: HL -> an input's code, E = column, BC -> the
; field's blanks: the field cleared, then the input's name
kd_field:
        push hl
        ld a,(kd_i)
        add a,KD_ROW0
        ld d,a
        ld (kd_at),de
        ld h,b
        ld l,c
        ld a,(kd_attr)
        ld c,a
        call menu_print                 ; the field cleared
        pop hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        call kd_key_name                ; HL -> its name
        ld de,(kd_at)
        ld a,(kd_attr)
        ld c,a
        jp menu_print

; DE = an input's code (bank D, bit mask E) -> HL -> its name ("-" if none,
; "?" if unknown)
kd_key_name:
        ld a,e
        or a
        jr z,.none                      ; (no input: a mask of 0)
        ld a,d
        cp KEY_BANKS
        jr nc,.unk
        add a,a                         ; bank * 16: 8 names of 2 bytes
        add a,a
        add a,a
        add a,a
        ld hl,kd_keys
        add hl,a
        ld a,e
.bit:   rrca                            ; the bit's number
        jr c,.at
        inc hl
        inc hl
        jr .bit
.at:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
.unk:   ld hl,kn_unk
        ret
.none:  ld hl,kn_none
        ret

;------------------------------------------------------------------------------
; Redefine keys page data
;------------------------------------------------------------------------------
kd_text:
        db 0, KD_NAME_COL, MENU_TITLE   ; the title, over the controls'
        db "REDEFINE KEYS", 0           ; names, and the columns' headings
        db 0, KD_KEY_COL, MENU_TITLE
        db "KEY", 0
        db 0, KD_JOY_COL, MENU_TITLE
        db "JOYSTICK", 0
        db 22, 1, MENU_ATTR
        db "Q A: CHOOSE   SPACE: CHANGE", 0
        db 23, 1, MENU_ATTR
        db "0: DEFAULTS   1: MAIN MENU", 0
        db $FF

txt_kd_select:  db "PRESS A KEY OR JOYSTICK", 0
txt_kd_used:    db "KEY ALREADY IN USE", 0
txt_kd_blank:   db "                              ", 0
txt_kd_keyblank: db "       ", 0
        ASSERT $ - txt_kd_keyblank == KD_KEY_LEN + 1
txt_kd_joyblank: db "        ", 0
        ASSERT $ - txt_kd_joyblank == KD_JOY_LEN + 1

; The controls' names, by K_* (input.asm)
kd_names:   dw kc_0, kc_1, kc_2, kc_3, kc_4, kc_5, kc_6, kc_7, kc_8, kc_9
            dw kc_10, kc_11, kc_12, kc_13, kc_14, kc_15, kc_16, kc_17, kc_18
            dw kc_19
        ASSERT ($ - kd_names)/2 == K_ACTIONS
        ASSERT K_SPEED_UP == 0 && K_FIRE == 9 && K_GUN_UP == 10
        ASSERT K_SLOT1 == 11 && K_GUN_DN == 16 && K_GUN_CTR == 17 && K_PAUSE == 18
        ASSERT K_BOOST == 19
kc_0:   db "SPEED UP", 0
kc_1:   db "SPEED DOWN", 0
kc_2:   db "AIR BRAKE", 0
kc_3:   db "TURN LEFT", 0
kc_4:   db "TURN RIGHT", 0
kc_5:   db "CLIMB", 0
kc_6:   db "DESCEND", 0
kc_7:   db "NOSE UP", 0
kc_8:   db "NOSE DOWN", 0
kc_9:   db "FIRE", 0
kc_10:  db "GUN TILT UP", 0
kc_11:  db "WEAPON SLOT 1", 0
kc_12:  db "WEAPON SLOT 2", 0
kc_13:  db "WEAPON SLOT 3", 0
kc_14:  db "WEAPON SLOT 4", 0
kc_15:  db "WEAPON SLOT 5", 0
kc_16:  db "GUN TILT DOWN", 0
kc_17:  db "GUN CENTRE", 0
kc_18:  db "PAUSE", 0
kc_19:  db "BOOST", 0

; Input names by bank and bit (the KB_* and J1_* / J2_* codes, input.asm):
; 8 per bank
kd_keys:
        dw kn_shift, kn_z, kn_x, kn_c, kn_v, kn_unk, kn_unk, kn_unk          ; 0
        dw kn_a, kn_s, kn_d, kn_f, kn_g, kn_unk, kn_unk, kn_unk              ; 1
        dw kn_q, kn_w, kn_e, kn_r, kn_t, kn_unk, kn_unk, kn_unk              ; 2
        dw kn_1, kn_2, kn_3, kn_4, kn_5, kn_unk, kn_unk, kn_unk              ; 3
        dw kn_0, kn_9, kn_8, kn_7, kn_6, kn_unk, kn_unk, kn_unk              ; 4
        dw kn_p, kn_o, kn_i, kn_u, kn_y, kn_unk, kn_unk, kn_unk              ; 5
        dw kn_enter, kn_l, kn_k, kn_j, kn_h, kn_unk, kn_unk, kn_unk          ; 6
        dw kn_space, kn_sym, kn_m, kn_n, kn_b, kn_unk, kn_unk, kn_unk        ; 7
        dw kn_right, kn_left, kn_down, kn_up, kn_period, kn_comma, kn_quote, kn_semi   ; 8
        dw kn_extend, kn_caps, kn_graph, kn_truevid, kn_invvid, kn_break, kn_edit, kn_delete ; 9
        dw kn_j1r, kn_j1l, kn_j1d, kn_j1u, kn_j1f, kn_j1c, kn_j1a, kn_j1s    ; 10: port $1F
        dw kn_j2r, kn_j2l, kn_j2d, kn_j2u, kn_j2f, kn_j2c, kn_j2a, kn_j2s    ; 11: port $37
        dw kn_j1m, kn_j1y, kn_j1z, kn_j1x, kn_j2m, kn_j2y, kn_j2z, kn_j2x    ; 12: NextReg $B2
        ASSERT $ - kd_keys == KEY_BANKS*16
        ASSERT KB_SHIFT == $0001 && KB_A == $0101 && KB_Q == $0201 && KB_1 == $0301
        ASSERT KB_0 == $0401 && KB_P == $0501 && KB_ENTER == $0601 && KB_SPACE == $0701
        ASSERT KB_RIGHT == $0801 && KB_SEMI == $0880 && KB_EXTEND == $0901 && KB_DELETE == $0980
        ASSERT J1_RIGHT == $0A01 && J1_START == $0A80 && J2_RIGHT == $0B01 && J2_START == $0B80
        ASSERT J1_MODE == $0C01 && J1_X == $0C08 && J2_MODE == $0C10 && J2_X == $0C80
kn_shift:   db "CAPS SH", 0
kn_z:       db "Z", 0
kn_x:       db "X", 0
kn_c:       db "C", 0
kn_v:       db "V", 0
kn_a:       db "A", 0
kn_s:       db "S", 0
kn_d:       db "D", 0
kn_f:       db "F", 0
kn_g:       db "G", 0
kn_q:       db "Q", 0
kn_w:       db "W", 0
kn_e:       db "E", 0
kn_r:       db "R", 0
kn_t:       db "T", 0
kn_1:       db "1", 0
kn_2:       db "2", 0
kn_3:       db "3", 0
kn_4:       db "4", 0
kn_5:       db "5", 0
kn_0:       db "0", 0
kn_9:       db "9", 0
kn_8:       db "8", 0
kn_7:       db "7", 0
kn_6:       db "6", 0
kn_p:       db "P", 0
kn_o:       db "O", 0
kn_i:       db "I", 0
kn_u:       db "U", 0
kn_y:       db "Y", 0
kn_enter:   db "ENTER", 0
kn_l:       db "L", 0
kn_k:       db "K", 0
kn_j:       db "J", 0
kn_h:       db "H", 0
kn_space:   db "SPACE", 0
kn_sym:     db "SYM SH", 0
kn_m:       db "M", 0
kn_n:       db "N", 0
kn_b:       db "B", 0
kn_right:   db "RIGHT", 0
kn_left:    db "LEFT", 0
kn_down:    db "DOWN", 0
kn_up:      db "UP", 0
kn_period:  db ".", 0
kn_comma:   db ",", 0
kn_quote:   db '"', 0
kn_semi:    db ";", 0
kn_extend:  db "EXTEND", 0
kn_caps:    db "CAPS", 0
kn_graph:   db "GRAPH", 0
kn_truevid: db "TRUEVID", 0
kn_invvid:  db "INVVID", 0
kn_break:   db "BREAK", 0
kn_edit:    db "EDIT", 0
kn_delete:  db "DELETE", 0
kn_j1r:     db "J1 RIGHT", 0
kn_j1l:     db "J1 LEFT", 0
kn_j1d:     db "J1 DOWN", 0
kn_j1u:     db "J1 UP", 0
kn_j1f:     db "J1 FIRE", 0
kn_j1c:     db "J1 C", 0
kn_j1a:     db "J1 A", 0
kn_j1s:     db "J1 START", 0
kn_j2r:     db "J2 RIGHT", 0
kn_j2l:     db "J2 LEFT", 0
kn_j2d:     db "J2 DOWN", 0
kn_j2u:     db "J2 UP", 0
kn_j2f:     db "J2 FIRE", 0
kn_j2c:     db "J2 C", 0
kn_j2a:     db "J2 A", 0
kn_j2s:     db "J2 START", 0
kn_j1m:     db "J1 MODE", 0
kn_j1y:     db "J1 Y", 0
kn_j1z:     db "J1 Z", 0
kn_j1x:     db "J1 X", 0
kn_j2m:     db "J2 MODE", 0
kn_j2y:     db "J2 Y", 0
kn_j2z:     db "J2 Z", 0
kn_j2x:     db "J2 X", 0
kn_unk:     db "?", 0
kn_none:    db "-", 0

kd_cur:     db 0                        ; the highlighted control
kd_i:       db 0                        ; kd_draw: the row being drawn
kd_attr:    db 0                        ;   its colour
kd_code:    dw 0                        ; kd_change: the input pressed,
kd_table:   dw 0                        ;   and key_defs or joy_defs for it
kd_at:      dw 0                        ; kd_field: its row and column
