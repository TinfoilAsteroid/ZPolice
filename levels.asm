;==============================================================================
; Z-POLICE - the current level's settings (resident, so any page can read
; them)
;
; level_cur holds the record of the level being played, loaded from its file
; ZPDATA/LEVELnn.ZPL by load_level (level_load.asm).  LV_SIZE bytes:
;   +0  LV_NUM          level number
;   +1  LV_NAME         city name, 8 characters (ASCII, space padded)
;   +9  LV_ZOMBIES      number of zombies a wave (at most NZOMB)
;   +10 LV_WAVES        number of zombie waves (1..LV_MAX_WAVES)
;   +11 LV_FAST         number of fast zombies (of LV_ZOMBIES)
;   +12 LV_VIEW_R       draw distance in tiles, 2..VIEW_R (fewer: night or
;                       fog); load_level sets view_r / dot_r from it
;   +13 LV_WAVE_DATA    the special monsters of each wave, waves 1 to
;                       LV_MAX_WAVES (wave 1 is the level's start), LV_WAVE_REC
;                       bytes each:
;         +0  LV_SPECIAL_ID   LV_SPEC_SLOTS special types (SPEC_*;
;                             SPEC_NONE, 255: none in that place)
;         +5  LV_SPECIAL      how many of each (in the same places)
; The levels and their cities are made by gentables.py (ZPDATA/); a level
; file can be replaced by a hand-made one (or its text form, .TXL, edited).
;==============================================================================

LV_NUM          equ 0
LV_NAME         equ 1
LV_NAME_LEN     equ 8
LV_ZOMBIES      equ LV_NAME+LV_NAME_LEN
LV_WAVES        equ LV_ZOMBIES+1
LV_FAST         equ LV_WAVES+1
LV_VIEW_R       equ LV_FAST+1
LV_WAVE_DATA    equ LV_VIEW_R+1
LV_MAX_WAVES    equ 10              ; waves a level can have specials for
LV_SPEC_SLOTS   equ 5               ; special types a wave
LV_SPECIAL_ID   equ 0               ; (in a wave's data) the types,
LV_SPECIAL      equ LV_SPEC_SLOTS   ;   then how many of each
LV_WAVE_REC     equ 2*LV_SPEC_SLOTS
LV_SIZE         equ LV_WAVE_DATA+LV_MAX_WAVES*LV_WAVE_REC   ; 113 bytes
        ASSERT LV_SIZE == 113           ; (gentables.py writes it)
; Special monster types in the level files (specials.asm: spec_types)
SPEC_GHOST      equ 0
SPEC_BANSHEE    equ 1
SPEC_GHOUL      equ 2
SPEC_LICH       equ 3
SPEC_DEVIL      equ 4               ; the final boss (devil.asm): alone, last
SPEC_IDS        equ 5               ; (how many types)
SPEC_CLUSTER    equ 5               ; not a monster: the wave's zombies spawn in
                                    ; this many clusters (zcluster, zombie.asm)
        ASSERT SPEC_CLUSTER >= SPEC_IDS ; (spec_wave skips it)
SPEC_NONE       equ 255

; -> HL = the current level's record
level_entry:
        ld hl,level_cur
        ret

level_cur:  ds LV_SIZE                  ; the level being played (load_level)
