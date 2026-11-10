;==============================================================================
; Z-POLICE - load-out screen (8K page PAGE_LOADOUT, runs at $C000 in slot 6)
;
; Before the first level (newGame) and between levels, after LEVEL COMPLETE
; (loadout_go pages it in).  On the
; left, the store: every weapon type unlocked (wpn_unlocked) with the number
; in store (wpn_stock), even 0 when the only one is fitted.  On the right,
; the VTOL's 5 weapon slots: a schematic of its underside (ZPDATA/VTOL.ZPI,
; read from the SD card as the screen opens: l320_image) with a box and the
; number at each slot's hardpoint (lo_hp), and below it the list of what is
; fitted in each.
;   1-5    select a slot (yellow)
;   Q / A  move the highlight up / down the store list.  The highlighted
;          weapon is green if it can be fitted in the selected slot (the
;          slot allows it, wpn_fits, and one is in store), red if not; the
;          rest of the list is white.
;   SPACE  fit the highlighted weapon in the selected slot, if it can be:
;          one comes out of the store, with a full load (WCFG_LOAD), and
;          whatever was fitted there goes back into the store
;   U      unload the selected slot: its weapon back into the store, the
;          slot EMPTY (lo_unload)
;   0      done: start the level (next_level), only with a weapon in slot 1
;          (the centre slot); while it is empty 0: START LEVEL is red
; Drawn on Layer 2 at 320x256 (screen320, text.asm; layer2-320x256.asm in
; slot 2), with the keys page in slot 7: the title, help and START LEVEL in
; the large font (26 x 25 grid), the headings and lists in the 8x8 one (40
; x 32 grid: they need the columns).
;==============================================================================

LO_TITLE_ROW    equ 1               ; (large font)
LO_HEAD_ROW     equ 4               ; STORE, SLOTS (8x8)
LO_ROW0         equ 6               ; first row of the lists (8x8)
LO_NAME_COL     equ 3               ; store: names,
LO_CNT_COL      equ 16              ;   numbers in store
LO_SLOT_COL     equ 21              ; slots: number, then the weapon (8x8)
LO_SROW0        equ 17              ;   from this row (under the VTOL)
LO_HELP_ROW     equ 19              ; the keys' help, two lines (large)
LO_START_ROW    equ 22              ; 0: START LEVEL (large)
LO_HP_BOX       equ 17              ; the centre slot hard point box (lo_hp)
LO_HP_BOX_H     equ 24              ; the wing hardpoint (lo_hp)
LO_HP_BOX_W     equ 6               ; the wing hardpoint (lo_hp)
LO_HP_X         equ 0               ; lo_hp's entries: the hardpoint (word),
LO_HP_Y         equ 2
LO_HP_LX        equ 3               ;   its number's top-left (x a word),
LO_HP_LY        equ 5
LO_HP_W         equ 6               ;   the box's width and height
LO_HP_H         equ 7
LO_HP_SIZE      equ 8
LO_NAME_LEN     equ 11              ; names are at most this long
LO_SLOT_STEP    equ 1               ; rows between the slots

loadout_screen:
        ld sp,stack_top
        call screen320                  ; (text.asm) the input page in slot 7
        ld hl,lo_text                   ; titles and help
        call l320_print_list
        ld hl,lo_img                    ; the VTOL (none without the file:
        call l320_image                 ; the boxes and numbers still show)
        ld hl,lo_list               ; the store list: types unlocked, in
        ld c,0                          ; type order
        ld b,1                          ; (from the first weapon type)
.ul:    ld a,b
        ld de,wpn_unlocked
        add de,a
        ld a,(de)
        or a
        jr z,.un
        ld (hl),b
        inc hl
        inc c
.un:    inc b
        ld a,b
        cp WPN_LAST+1
        jr nz,.ul
        ld a,c
        ld (lo_n),a
        xor a
        ld (lo_cur),a
        ld a,(wpn_sel)                  ; start on the slot in use
        ld (lo_slot),a
.draw:  call lo_draw
.loop:  call menu_frame
        call zrand                      ; (keep stirring the seed)
        call kbd_scan
        ld hl,KB_0                      ; done
        call key_code_pressed
        jr z,.up
        ld a,(wpn_slots)                ; (not with slot 1 empty)
        or a
        jp nz,next_level
.up:
        ld hl,KB_Q                      ; up the list
        call key_code_pressed
        jr z,.dn
        ld a,(lo_cur)
        or a
        jr z,.dn
        dec a
        ld (lo_cur),a
        jr .draw
.dn:    ld hl,KB_A                      ; down the list
        call key_code_pressed
        jr z,.sl
        ld a,(lo_n)
        ld c,a
        ld a,(lo_cur)
        inc a
        cp c
        jr nc,.sl
        ld (lo_cur),a
        jr .draw
.sl:    ld hl,lo_slot_keys              ; 1-5: a slot
        ld b,0
.sk:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ex de,hl
        call key_code_pressed
        pop hl
        jr z,.sn
        ld a,b
        ld (lo_slot),a
        jr .draw
.sn:    inc b
        ld a,b
        cp WPN_SLOTS
        jr nz,.sk
        ld hl,KB_U                      ; unload the slot
        call key_code_pressed
        jr z,.fit
        call lo_unload
        jp .draw
.fit:   ld hl,KB_SPACE                  ; fit it
        call key_code_pressed
        jp z,.loop
        call lo_fit
        jp .draw

lo_slot_keys:   dw KB_1, KB_2, KB_3, KB_4, KB_5

;------------------------------------------------------------------------------
; Carry set if store weapon A can go in the selected slot (lo_slot): the
; slot allows it and one is in store
lo_ok:
        ld c,a
        ld hl,wpn_stock
        add hl,a
        ld a,(hl)
        or a
        ret z                           ; none in store (carry clear)
        ld a,c
        ld hl,lo_slot
        ld c,(hl)
        jp wpn_fits                     ; (resident)

; SPACE: fit the highlighted weapon in the selected slot, if it can go
; there; whatever was there goes back into the store
lo_fit:
        call lo_cur_type
        ret z                           ; (an empty list)
        ld (lo_t),a
        call lo_ok
        ret nc
        ld a,(lo_slot)                  ; HL -> the slot
        add a,a
        ld hl,wpn_slots
        add hl,a
        ld b,(hl)                       ; B = what was there
        ld a,(lo_t)
        ld (hl),a                       ; fitted,
        inc hl
        push hl
        push bc
        call wpn_cfg_ptr
        ld a,(hl)                       ; with a full load (WCFG_LOAD)
        pop bc
        pop hl
        ld (hl),a
        ld a,(lo_t)                     ; one fewer in store
        ld hl,wpn_stock
        add hl,a
        dec (hl)
        ld a,b                          ; the old one back in store
        or a
        ret z                           ; (the slot was empty)
        ld hl,wpn_stock
        add hl,a
        inc (hl)
        ret nz
        dec (hl)                        ; (at most 255)
        ret

; U: unload the selected slot: its weapon back into the store (its ammo
; with it: refitted, it gets a full load), the slot EMPTY.  If it was the
; slot the game fires (wpn_sel), the first slot still fitted is chosen.
lo_unload:
        ld a,(lo_slot)                  ; HL -> the slot
        add a,a
        ld hl,wpn_slots
        add hl,a
        ld a,(hl)
        or a
        ret z                           ; already empty
        ld (hl),0                       ; EMPTY,
        inc hl
        ld (hl),0                       ;   no ammo
        ld hl,wpn_stock                 ; back in store
        add hl,a
        inc (hl)
        jr nz,.sel
        dec (hl)                        ; (at most 255)
.sel:   ld a,(lo_slot)
        ld hl,wpn_sel
        cp (hl)
        ret nz                          ; not the one in use
        ld b,0                          ; the first slot still fitted
        ld hl,wpn_slots
.f:     ld a,(hl)
        or a
        jr nz,.got
        inc hl
        inc hl
        inc b
        ld a,b
        cp WPN_SLOTS
        jr nz,.f
        ret                             ; none: left as it is
.got:   ld a,b
        ld (wpn_sel),a
        ret

; A = the highlighted store weapon's type; Z if the list is empty
lo_cur_type:
        ld a,(lo_n)
        or a
        ret z
        ld a,(lo_cur)
        ld hl,lo_list
        add hl,a
        ld a,(hl)
        or a                            ; (a type is never 0: NZ)
        ret

;------------------------------------------------------------------------------
; Draw both lists: the store (the highlighted weapon green / red, the rest
; white) and the slots (the selected one yellow)
lo_draw:
        xor a
        ld (l320_font),a                ; (8x8: L320_F8)
        ASSERT L320_F8 == 0
.st:    ld (lo_i),a
        ld hl,lo_n
        cp (hl)
        jr nc,.slots
        ld hl,lo_list
        add hl,a
        ld a,(hl)
        ld (lo_t),a
        ld c,SCR_TEXT                  ; white
        ld a,(lo_cur)
        ld hl,lo_i
        cp (hl)
        jr nz,.col
        ld a,(lo_t)                     ; highlighted: can it go there?
        call lo_ok
        ld c,SCR_OK
        jr c,.col
        ld c,SCR_BAD
.col:   ld a,c
        ld (lo_attr),a
        ld a,(lo_i)
        add a,LO_ROW0
        ld d,a
        ld e,LO_NAME_COL
        ld a,(lo_t)
        call lo_name
        ld a,(lo_i)
        add a,LO_ROW0
        ld d,a
        ld e,LO_CNT_COL
        ld a,(lo_t)
        ld hl,wpn_stock
        add hl,a
        ld a,(hl)
        call lo_num
        ld a,(lo_i)
        inc a
        jr .st
.slots: xor a                           ; the slots
.sl:    ld (lo_i),a
        ld c,SCR_TEXT
        ld hl,lo_slot
        cp (hl)
        jr nz,.sc
        ld c,SCR_TITLE                 ; the selected one: yellow
.sc:    ld a,c
        ld (lo_attr),a
        ld a,(lo_i)                     ; row LO_SROW0 + slot * LO_SLOT_STEP
        ASSERT LO_SLOT_STEP == 1
        add a,LO_SROW0
        ld d,a
        ld e,LO_SLOT_COL
        ld a,(lo_attr)
        ld c,a
        ld a,(lo_i)
        add a,'1'
        push de
        push af
        ld a,c
        ld (l320_ink),a
        call l320_at
        pop af
        call l320_char                  ; its number (key)
        pop de
        ld e,LO_SLOT_COL+2
        ld a,(lo_i)
        add a,a
        ld hl,wpn_slots
        add hl,a
        ld a,(hl)                       ; what is fitted
        call lo_name
        call lo_hpdraw                  ; and on the VTOL
        ld a,(lo_i)
        inc a
        cp WPN_SLOTS
        jr nz,.sl
        ld c,SCR_TEXT                  ; 0: START LEVEL, red while slot 1
        ld a,(wpn_slots)                ; is empty (0 does nothing then)
        or a
        jr nz,.go
        ld c,SCR_BAD
.go:    ld a,L320_F12                   ; (large)
        ld (l320_font),a
        ld d,LO_START_ROW
        ld e,(F12_COLS-14)/2
        ld hl,lo_start
        jp l320_print_at
        ASSERT (LO_ROW0 + WPN_LAST)*8 <= F12_Y0 + LO_HELP_ROW*F12_H
        ASSERT (LO_SROW0 + WPN_SLOTS)*8 <= F12_Y0 + LO_HELP_ROW*F12_H
        ASSERT LO_HEAD_ROW*8 >= F12_Y0 + (LO_TITLE_ROW+1)*F12_H
        ASSERT LO_SLOT_COL + 2 + LO_NAME_LEN <= L320_COLS-1

; Slot lo_i's hardpoint on the VTOL (lo_hp): a box round it (its own width
; and height, centred on the hardpoint), and its number beside it (8x8, over
; the image), yellow if it is the selected slot, else grey and white.  Keeps
; IX.
lo_hpdraw:
        push ix
        ld a,(lo_i)                     ; IX -> its entry
        ld e,a
        ld d,LO_HP_SIZE
        mul d,e
        ld ix,lo_hp
        add ix,de
        ld a,(ix+LO_HP_W)               ; left: x - width/2
        srl a
        ld e,a
        ld d,0
        ld l,(ix+LO_HP_X)
        ld h,(ix+LO_HP_X+1)
        or a
        sbc hl,de
        ld a,(ix+LO_HP_H)               ; top: y - height/2
        srl a
        ld c,a
        ld a,(ix+LO_HP_Y)
        sub c
        ld c,a
        ld e,(ix+LO_HP_W)               ; DE = width, B = height
        ld d,0
        ld b,(ix+LO_HP_H)
        ld a,(lo_attr)                  ; (yellow: selected)
        cp SCR_TITLE
        jr z,.bc
        ld a,SCR_FRAME2
.bc:    call l320_box
        ld l,(ix+LO_HP_LX)              ; the number's place
        ld h,(ix+LO_HP_LX+1)
        ld c,(ix+LO_HP_LY)
        pop ix
        call l320_pos
        ld a,(lo_attr)
        ld (l320_ink),a
        ld a,L320_NOPAPER               ; (over the image)
        ld (l320_paper),a
        ld a,(lo_i)
        add a,'1'
        call l320_char
        ld a,SCR_BG
        ld (l320_paper),a
        ret

; A = weapon type, D = row, E = column: its name, in lo_attr, padded with
; spaces to LO_NAME_LEN (so a shorter name covers a longer one)
lo_name:
        ld (lo_nt),a
        ld a,(lo_attr)
        ld c,a
        push de
        push bc
        ld hl,lo_blank                  ; clear the field
        call l320_print_at
        pop bc
        pop de
        ld a,(lo_nt)                    ; then the name
        add a,a
        ld hl,lo_names
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp l320_print_at

; A = 0-255, D = row, E = column: 3 characters, right-aligned, in lo_attr
lo_num:
        ld hl,lo_nbuf
        ld b,100
        call .dig
        ld b,10
        call .dig
        add a,'0'
        ld (hl),a
        ld hl,lo_nbuf                   ; leading zeros: spaces
        ld a,(hl)
        cp '0'
        jr nz,.pr
        ld (hl),' '
        inc hl
        ld a,(hl)
        cp '0'
        jr nz,.pr
        ld (hl),' '
.pr:    ld a,(lo_attr)
        ld c,a
        ld hl,lo_nbuf
        jp l320_print_at
.dig:   ld (hl),'0'                     ; A = A mod B, (HL) = the digit
.ds:    cp b
        jr c,.dd
        sub b
        inc (hl)
        jr .ds
.dd:    inc hl
        ret

;------------------------------------------------------------------------------
; Load-out page data
;------------------------------------------------------------------------------
; row, column, attribute, text, 0 ... $FF
lo_text:
        db LO_TITLE_ROW, (F12_COLS-8)/2, SCR_TITLE
        db "LOAD OUT", 0
        db LO_HELP_ROW, 2, SCR_HELP
        db "Q A: CHOOSE  1-5: SLOT", 0
        db LO_HELP_ROW+1, 2, SCR_HELP
        db "SPACE: FIT   U: UNLOAD", 0
        db L320_LIST_FONT, L320_F8
        db LO_HEAD_ROW, LO_NAME_COL, SCR_HELP
        db "STORE", 0
        db LO_HEAD_ROW, LO_SLOT_COL, SCR_HELP
        db "SLOTS", 0
        db $FF
lo_start:   db "0: START LEVEL", 0      ; (lo_draw: red with slot 1 empty)
lo_img:     db "ZPDATA/VTOL.ZPI", 0     ; the VTOL (tools/vtol_schematic.py)

; Each slot's hardpoint on the VTOL image (slot 1 first), LO_HP_SIZE bytes:
; its x (word) and y, its number's top-left x (word) and y, and the width
; and height of the box round it (centred on the hardpoint: x - width/2, y -
; height/2).  tools/vtol_schematic.py (HARDPOINTS, LABELS, BOXES) has them
; too: keep them alike (test_l320.py checks).
    MACRO LO_HP_AT x, y, lx, ly, w, h
        dw x
        db y
        dw lx
        db ly
        db w, h
    ENDM
lo_hp:  LO_HP_AT 240,  62, 238,  534, LO_HP_BOX, LO_HP_BOX   ; 1: the centre gun
        LO_HP_AT 220,  89, 187, 105, LO_HP_BOX_W, LO_HP_BOX_H   ; 2: left outer pod
        LO_HP_AT 260,  89, 287, 105, LO_HP_BOX_W, LO_HP_BOX_H    ; 3: right outer pod
        LO_HP_AT 226,  89, 232, 120, LO_HP_BOX_W, LO_HP_BOX_H    ; 4: left inner pod
        LO_HP_AT 254,  89, 26, 120, LO_HP_BOX_W, LO_HP_BOX_H     ; 5: right inner pod
        ASSERT ($ - lo_hp) == WPN_SLOTS*LO_HP_SIZE

; Weapon names, by WPN_* (at most LO_NAME_LEN characters)
lo_names:   dw lo_n_none, lo_n_gun, lo_n_laser, lo_n_chain
            dw lo_n_rockets, lo_n_missile, lo_n_bomb, lo_n_autocannon
            dw lo_n_prox, lo_n_lchain_l, lo_n_lchain_r
        ASSERT ($ - lo_names)/2 == WPN_LAST+1
lo_n_none:      db "EMPTY", 0
lo_n_gun:       db "MACHINE GUN", 0
lo_n_laser:     db "LASER", 0
lo_n_chain:     db "CHAIN GUN", 0
lo_n_rockets:   db "ROCKET POD", 0
lo_n_missile:   db "MISSILE POD", 0
lo_n_bomb:      db "BOMB", 0
lo_n_autocannon: db "AUTOCANNON", 0
lo_n_prox:      db "PROXIMITY", 0
lo_n_lchain_l:  db "LINKED CG L", 0         ; (linked chain guns: slot 4
lo_n_lchain_r:  db "LINKED CG R", 0         ;   only, slot 5 only)
lo_blank:       db "           ", 0
        ASSERT $ - lo_blank == LO_NAME_LEN + 1

lo_n:       db 0                        ; weapon types in the store list
lo_cur:     db 0                        ; the highlighted one
lo_slot:    db 0                        ; the selected slot (0-4)
lo_i:       db 0                        ; lo_draw: the row being drawn
lo_t:       db 0                        ;   its weapon type
lo_attr:    db 0                        ;   its colour
lo_nt:      db 0                        ; lo_name: the type
lo_nbuf:    db "000", 0                 ; lo_num
lo_list:    ds WPN_LAST                 ; the store list: weapon types
