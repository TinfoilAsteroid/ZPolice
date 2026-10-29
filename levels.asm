;==============================================================================
; Z-POLICE - the current level's settings (resident, so any page can read
; them)
;
; level_cur holds the record of the level being played, loaded from its file
; ZPDATA/LEVELnn.ZPL by load_level (level_load.asm).  LV_SIZE bytes:
;   +0  LV_NUM          level number
;   +1  LV_NAME         city name, 8 characters (ASCII, space padded)
;   +9  LV_ZOMBIES      number of zombies (at most NZOMB)
;   +10 LV_WAVES        number of zombie waves
;   +11 LV_FAST         number of fast zombies (of LV_ZOMBIES)
;   +12 LV_SPECIAL      number of special monsters
;   +13 LV_SPECIAL_MAX  highest special monster id that may appear
;   +14 LV_VIEW_R       draw distance in tiles, 2..VIEW_R (fewer: night or
;                       fog); load_level sets view_r / dot_r from it
; The levels and their cities are made by gentables.py (ZPDATA/); a level
; file can be replaced by a hand-made one.  The zombie, wave and special
; counts are not used by the game yet.
;==============================================================================

LV_NUM          equ 0
LV_NAME         equ 1
LV_NAME_LEN     equ 8
LV_ZOMBIES      equ LV_NAME+LV_NAME_LEN
LV_WAVES        equ LV_ZOMBIES+1
LV_FAST         equ LV_WAVES+1
LV_SPECIAL      equ LV_FAST+1
LV_SPECIAL_MAX  equ LV_SPECIAL+1
LV_VIEW_R       equ LV_SPECIAL_MAX+1
LV_SIZE         equ LV_VIEW_R+1         ; 15 bytes

; -> HL = the current level's record
level_entry:
        ld hl,level_cur
        ret

level_cur:  ds LV_SIZE                  ; the level being played (load_level)
