;==============================================================================
; Z-POLICE - load-out screen (8K page PAGE_LOADOUT, runs at $C000 in slot 6)
;
; Before the first level (newGame) and between levels, after LEVEL COMPLETE
; (loadout_go pages it in).  On the
; left, the store: every weapon type unlocked (wpn_unlocked) with the number
; in store (wpn_stock), even 0 when the only one is fitted.  On the right,
; the VTOL's 5 weapon slots and what is fitted in each.
;   1-5    select a slot (yellow)
;   Q / A  move the highlight up / down the store list.  The highlighted
;          weapon is green if it can be fitted in the selected slot (the
;          slot allows it, wpn_fits, and one is in store), red if not; the
;          rest of the list is white.
;   SPACE  fit the highlighted weapon in the selected slot, if it can be:
;          one comes out of the store, with a full load (WCFG_LOAD), and
;          whatever was fitted there goes back into the store
;   0      done: start the level (next_level)
; Uses the resident text routines (text.asm) and the keys page in slot 7.
;==============================================================================

LO_ROW0         equ 5               ; first row of the lists
LO_NAME_COL     equ 1               ; store: names,
LO_CNT_COL      equ 13              ;   numbers in store
LO_SLOT_COL     equ 18              ; slots: number, then the weapon
LO_NAME_LEN     equ 11              ; names are at most this long
LO_SLOT_STEP    equ 2               ; rows between the slots

loadout_screen:
        ld sp,stack_top
        nextreg CODE_MMU,PAGE_INPUT     ; the input page at $E000
        call menu_clear
        ld hl,lo_text                   ; titles and help
.txt:   ld a,(hl)
        cp $FF
        jr z,.list
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld c,(hl)
        inc hl
        call menu_print
        jr .txt
.list:  ld hl,lo_list               ; the store list: types unlocked, in
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
        jp nz,next_level
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
        ld hl,KB_SPACE                  ; fit it
        call key_code_pressed
        jr z,.loop
        call lo_fit
        jr .draw

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
.st:    ld (lo_i),a
        ld hl,lo_n
        cp (hl)
        jr nc,.slots
        ld hl,lo_list
        add hl,a
        ld a,(hl)
        ld (lo_t),a
        ld c,MENU_ATTR                  ; white
        ld a,(lo_cur)
        ld hl,lo_i
        cp (hl)
        jr nz,.col
        ld a,(lo_t)                     ; highlighted: can it go there?
        call lo_ok
        ld c,MENU_OK
        jr c,.col
        ld c,MENU_BAD
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
        ld c,MENU_ATTR
        ld hl,lo_slot
        cp (hl)
        jr nz,.sc
        ld c,MENU_TITLE                 ; the selected one: yellow
.sc:    ld a,c
        ld (lo_attr),a
        ld a,(lo_i)                     ; row LO_ROW0 + slot * LO_SLOT_STEP
        add a,a
        add a,LO_ROW0
        ld d,a
        ld e,LO_SLOT_COL
        ld a,(lo_attr)
        ld c,a
        ld a,(lo_i)
        add a,'1'
        push de
        call menu_char                  ; its number (key)
        pop de
        ld e,LO_SLOT_COL+2
        ld a,(lo_i)
        add a,a
        ld hl,wpn_slots
        add hl,a
        ld a,(hl)                       ; what is fitted
        call lo_name
        ld a,(lo_i)
        inc a
        cp WPN_SLOTS
        jr nz,.sl
        ret
        ASSERT LO_ROW0 + (WPN_SLOTS-1)*LO_SLOT_STEP < 19

; A = weapon type, D = row, E = column: its name, in lo_attr, padded with
; spaces to LO_NAME_LEN (so a shorter name covers a longer one)
lo_name:
        ld (lo_nt),a
        ld a,(lo_attr)
        ld c,a
        push de
        push bc
        ld hl,lo_blank                  ; clear the field
        call menu_print
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
        jp menu_print

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
        jp menu_print
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
        db 1, 12, MENU_TITLE
        db "LOAD OUT", 0
        db 3, LO_NAME_COL, MENU_TITLE
        db "STORE", 0
        db 3, LO_SLOT_COL, MENU_TITLE
        db "SLOTS", 0
        db 19, 1, MENU_ATTR
        db "Q A: CHOOSE     1-5: SLOT", 0
        db 21, 1, MENU_ATTR
        db "SPACE: FIT      0: START LEVEL", 0
        db $FF

; Weapon names, by WPN_* (at most LO_NAME_LEN characters)
lo_names:   dw lo_n_none, lo_n_gun, lo_n_laser, lo_n_chain
            dw lo_n_rockets, lo_n_missile, lo_n_bomb, lo_n_bofors
            dw lo_n_prox
        ASSERT ($ - lo_names)/2 == WPN_LAST+1
lo_n_none:      db "EMPTY", 0
lo_n_gun:       db "MACHINE GUN", 0
lo_n_laser:     db "LASER", 0
lo_n_chain:     db "CHAIN GUN", 0
lo_n_rockets:   db "ROCKET POD", 0
lo_n_missile:   db "MISSILE POD", 0
lo_n_bomb:      db "BOMB", 0
lo_n_bofors:    db "BOFORS", 0
lo_n_prox:      db "PROXIMITY", 0
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
