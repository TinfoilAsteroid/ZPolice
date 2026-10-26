;==============================================================================
; Z-POLICE - level table (in the zombie page, slot 1: always mapped, so any
; page can read it)
;
; One LV_SIZE-byte entry per level, levels 1..LEVEL_COUNT in order:
;   +0  LV_NUM          level number
;   +1  LV_NAME         city name, 8 characters (ASCII, space padded)
;   +9  LV_ZOMBIES      number of zombies (at most NZOMB)
;   +10 LV_WAVES        number of zombie waves
;   +11 LV_FAST         number of fast zombies (of LV_ZOMBIES)
;   +12 LV_SPECIAL      number of special monsters
;   +13 LV_SPECIAL_MAX  highest special monster id that may appear
; level_entry (A = level) gives the entry's address.  Not used by the game
; yet: the values below are placeholders to tune.
;==============================================================================

LV_NUM          equ 0
LV_NAME         equ 1
LV_NAME_LEN     equ 8
LV_ZOMBIES      equ LV_NAME+LV_NAME_LEN
LV_WAVES        equ LV_ZOMBIES+1
LV_FAST         equ LV_WAVES+1
LV_SPECIAL      equ LV_FAST+1
LV_SPECIAL_MAX  equ LV_SPECIAL+1
LV_SIZE         equ LV_SPECIAL_MAX+1    ; 14 bytes

; One entry: level, "8-char name", zombies, waves, fast, specials, max id
        MACRO LEVEL lnum, lname, lzomb, lwaves, lfast, lspec, lmaxid
.e:     db lnum
        db lname
        ASSERT $ - .e == LV_ZOMBIES     ; the name is exactly 8 characters
        db lzomb, lwaves, lfast, lspec, lmaxid
        ASSERT lzomb <= NZOMB
        ASSERT lfast <= lzomb
        ENDM

; A = level (1..) -> HL = its entry.  Levels past the table use the last
; entry.
level_entry:
        dec a
        cp LEVEL_COUNT
        jr c,.ok
        ld a,LEVEL_COUNT-1
.ok:    ld d,a
        ld e,LV_SIZE
        mul d,e
        ld hl,levels
        add hl,de
        ret

levels:
        ;     level  city name  zombies waves fast specials max-id
        LEVEL  1, "LONDON  ", 12, 2,  1, 0, 0
        LEVEL  2, "PARIS   ", 13, 2,  1, 0, 0
        LEVEL  3, "BERLIN  ", 14, 3,  2, 0, 0
        LEVEL  4, "MADRID  ", 15, 3,  2, 0, 0
        LEVEL  5, "ROME    ", 16, 3,  3, 1, 0
        LEVEL  6, "VIENNA  ", 17, 4,  3, 1, 1
        LEVEL  7, "PRAGUE  ", 18, 4,  4, 2, 1
        LEVEL  8, "WARSAW  ", 19, 4,  4, 2, 1
        LEVEL  9, "OSLO    ", 20, 5,  5, 3, 1
        LEVEL 10, "DUBLIN  ", 20, 5,  5, 3, 1
        LEVEL 11, "LISBON  ", 20, 5,  6, 4, 2
        LEVEL 12, "ATHENS  ", 20, 6,  6, 4, 2
        LEVEL 13, "CAIRO   ", 20, 6,  7, 5, 2
        LEVEL 14, "TOKYO   ", 20, 6,  7, 5, 2
        LEVEL 15, "SEOUL   ", 20, 7,  8, 5, 2
        LEVEL 16, "SYDNEY  ", 20, 7,  8, 5, 3
        LEVEL 17, "TORONTO ", 20, 7,  9, 5, 3
        LEVEL 18, "CHICAGO ", 20, 8,  9, 5, 3
        LEVEL 19, "BOSTON  ", 20, 8, 10, 5, 3
        LEVEL 20, "NEW YORK", 20, 8, 10, 5, 3
levels_end:
LEVEL_COUNT     equ (levels_end-levels)/LV_SIZE
        ASSERT LEVEL_COUNT*LV_SIZE == levels_end-levels
