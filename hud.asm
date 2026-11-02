;==============================================================================
; Z-POLICE - HUD page (8K page PAGE_HUD, runs at $E000)
;
; ULA (Layer 1) code: panel set-up, FPS text, speed/altitude gauges and the
; city map with the flashing player marker.  Paged in by main_loop with
; nextreg CODE_MMU,PAGE_HUD.  Shared variables live in zpolice.asm.
;==============================================================================

    IFDEF DRAW_FPS
; Print "nn FPS" at the top left of the ULA screen
fps_draw:
        ld a,(fps_value)
        cp 100
        jr c,.ok
        ld a,99
.ok:    ld c,0
.ten:   cp 10
        jr c,.unit
        sub 10
        inc c
        jr .ten
.unit:  push af                         ; units
        ld a,c
        or a
        jr nz,.t
        ld a,GLYPH_SPACE                ; no leading zero
.t:     ld e,0
        call print_glyph
        pop af
        ld e,1
        call print_glyph
        ld a,GLYPH_SPACE
        ld e,2
        call print_glyph
        ld a,GLYPH_F
        ld e,3
        call print_glyph
        ld a,GLYPH_P
        ld e,4
        call print_glyph
        ld a,GLYPH_S
        ld e,5
        jp print_glyph
    ENDIF

; A = glyph, E = character column on ULA row 0
print_glyph:
        ld d,high ULA_BMP               ; ULA row 0

; A = glyph, DE = ULA character cell address
print_glyph_at:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,font
        add hl,bc
        ld b,8
.l:     ld a,(hl)
        ld (de),a
        inc hl
        inc d                           ; next pixel line of the cell
        djnz .l
        ret

;------------------------------------------------------------------------------
; ULA (Layer 1) setup.  Rows 0-127: paper 0 is made transparent, so only the
; FPS text shows over the Layer 2 viewport.  Rows 128-191: opaque instrument
; panel with a green divider, gauge labels and the gauge tracks.
;------------------------------------------------------------------------------
; ULA palette: the panel colours and inks.  Set once at start-up (the menu
; uses them too).
ula_palette:
        nextreg $43,%00000000           ; edit ULA palette 1, auto-increment
        nextreg $40,C_YEL               ; ink 2
        nextreg $41,$FC                 ;   yellow
        nextreg $40,C_BLUE              ; ink 5
        nextreg $41,$4B                 ;   light blue
        nextreg $40,3                   ; ink 3, ink 4
        nextreg $41,$E0                 ;   red
        nextreg $41,$1C                 ;   green
        nextreg $40,6                   ; ink 6, ink 7
        nextreg $41,$F4                 ;   amber
        nextreg $41,$FF                 ;   white
        nextreg $40,16                  ; paper 0..4
        nextreg $41,$E3                 ;   transparent (= NextReg $14)
        nextreg $41,$25                 ;   panel (dark slate)
        nextreg $41,$00                 ;   empty gauge (black, opaque)
        nextreg $41,$E0                 ;   red
        nextreg $41,$1C                 ;   green
        nextreg $40,22                  ; paper 6
        nextreg $41,$F4                 ;   amber
        nextreg $40,24                  ; bright paper 0
        nextreg $41,$E3                 ;   transparent
        ret

ula_init:                               ; (the fills by DMA: layer2_cls.asm)
        ld hl,ULA_BMP
        ld bc,$1800
        xor a
        call dma_fill                   ; bitmap: all paper
        ld hl,ULA_ATTR
        ld bc,16*32
        ld a,%01000111                  ; viewport: bright, paper 0, ink 7
        call dma_fill
        ld hl,ULA_ATTR+16*32
        ld bc,8*32
        ld a,ATTR_PANEL                 ; panel
        call dma_fill
        ld hl,ULA_ATTR+16*32            ; divider: top pixel row of the panel
        ld b,32
.dv:    ld (hl),P_PANEL<<3 | C_OK
        inc hl
        djnz .dv
        ld hl,ULA_BMP+$1000             ; char row 16, pixel line 0
        ld b,32
.dl:    ld (hl),$FF
        inc hl
        djnz .dl

        ld a,GLYPH_S                    ; gauge labels: S (speed) and
        ld de,ULA_ROW_LBL+SPD_GCOL      ; A (altitude | ground)
        call print_glyph_at
        ld a,GLYPH_A
        ld de,ULA_ROW_LBL+ALT_GCOL
        call print_glyph_at
        ld a,(boost_fitted)             ; the booster's fuel, once fitted: B,
        or a                            ; and its cells transparent too
        jr z,.nb
        ld a,GLYPH_B
        ld de,ULA_ROW_LBL+BST_GCOL
        call print_glyph_at
        ld hl,ULA_ATTR + 17*32 + BST_GCOL
        ld b,GAUGE_H/8
.gb:    ld (hl),0
        ld a,32
        add hl,a
        djnz .gb
.nb:
        ld hl,ULA_ATTR + 17*32 + SPD_GCOL  ; the gauges' cells: transparent,
        ld b,GAUGE_H/8                  ; showing the Layer 2 bars
.ga:    ld (hl),0
        ld a,ALT_GCOL-SPD_GCOL
        add hl,a
        ld (hl),0
        ld a,32-(ALT_GCOL-SPD_GCOL)
        add hl,a
        djnz .ga
        ld hl,lbl_int                   ; INTEGRITY (the percentage: drawn
        ld de,ULA_ROW_INT+INT_COL       ; by draw_integrity)
        ld b,9
        call print_glyphs
        ld a,$FF
        ld (int_shown),a                ; (drawn next frame)
        call map_init
    IFDEF DRAW_FPS
        jp fps_draw                     ; initial " 0 FPS"
    ELSE
        ret
    ENDIF

;------------------------------------------------------------------------------
; Weapon slots (placeholders): an 8x16 box for each, 2 character cells on
; rows WPN_ROW, WPN_ROW+1, at columns WPN_COL0, +2, ... in the order
; wpn_order (as numbered on keys 1-5: 2 4 1 5 3).  A box is green if its
; slot holds a weapon, red if it is empty; the selected slot has a white
; outline.  An empty slot that was asked for flashes amber / red (WFLASH
; frames each, 3 times, ending red).  Under an occupied slot, on row
; WPN_ROW+2, the letter of its weapon (wpn_glyph): M, L, C or R.
; Redrawn every frame.
;------------------------------------------------------------------------------
WPN_ATTR_ON     equ C_OK<<3 | 7         ; paper green, ink white (outline)
WPN_ATTR_OFF    equ C_WARN<<3 | 7       ; paper red
WPN_ATTR_FLASH  equ C_AMBER<<3 | 7      ; paper amber
WPN_BMP         equ ULA_BMP + (WPN_ROW/8)*$800 + (WPN_ROW&7)*32 + WPN_COL0
        ASSERT WPN_ROW/8 == (WPN_ROW+2)/8       ; the 3 rows in one third
        ASSERT WPN_COL0 + 2*(WPN_SLOTS-1) < MAP_COL

draw_wpn:
        ld c,$FF                        ; the slot flashing amber this frame
        ld a,(wflash_t)
        or a
        jr z,.nf
        dec a                           ; phase (t-1)/WFLASH: odd = amber
        ld b,-1
.dv:    inc b
        sub WFLASH
        jr nc,.dv
        bit 0,b
        jr z,.nf
        ld a,(wflash_slot)
        ld c,a
.nf:    ld a,c
        ld (wd_flash),a
        ld hl,wflash_t                  ; count the flash down
        ld a,(hl)
        or a
        jr z,.go
        dec (hl)
.go:    ld b,0                          ; box position, left to right
.lp:    push bc
        ld a,b
        add a,a
        ld (wd_col),a                   ; its column offset
        ld hl,wpn_order
        ld a,b
        add hl,a
        ld c,(hl)                       ; C = its slot (0 = the centre gun)
        ld a,c
        add a,a
        ld hl,wpn_slots+WPN_TYPE
        add hl,a
        ld a,(hl)
        ld (wd_type),a
        ld e,WPN_ATTR_ON                ; fitted: green
        or a
        jr nz,.pc
        ld e,WPN_ATTR_OFF               ; empty: red, or amber while flashing
        ld a,(wd_flash)
        cp c
        jr nz,.pc
        ld e,WPN_ATTR_FLASH
.pc:    ld a,(wd_col)                   ; the box's two cells
        ld hl,ULA_ATTR + WPN_ROW*32 + WPN_COL0
        add hl,a
        ld (hl),e
        ld a,32
        add hl,a
        ld (hl),e
        ld a,(wpn_sel)                  ; outline if selected, else clear
        cp c
        ld de,$FF81                     ; D: top / bottom line, E: sides
        jr z,.bx
        ld de,0
.bx:    ld a,(wd_col)
        ld hl,WPN_BMP
        add hl,a
        push hl
        ld (hl),d                       ; upper cell: top line, then sides
        ld b,7
.b1:    inc h
        ld (hl),e
        djnz .b1
        pop hl
        ld a,32
        add hl,a
        push hl
        ld b,7                          ; lower cell: sides, then bottom line
.b2:    ld (hl),e
        inc h
        djnz .b2
        ld (hl),d
        pop hl
        ld a,32                         ; the cell below: its weapon's letter
        add hl,a
        ex de,hl
        ld a,(wd_type)
        ld hl,wpn_glyph
        add hl,a
        ld a,(hl)
        call print_glyph_at
        pop bc
        inc b
        ld a,b
        cp WPN_SLOTS
        jr nz,.lp
        ret

;------------------------------------------------------------------------------
; Integrity: the VTOL's hit points as a percentage of VTOL_HP, "nnn%" on row
; INT_ROW+1 under the INTEGRITY label.  VTOL_HP is 50, so the percentage is
; just vtol_hp * 2 (a shift left).  Green, amber below INT_WARN, red below
; INT_DANGER.  Redrawn only when it changes (int_shown).
;------------------------------------------------------------------------------
draw_integrity:
        ld a,(vtol_hp)
        add a,a                         ; percent = hp * 2
        ld hl,int_shown
        cp (hl)
        ret z                           ; unchanged
        ld (hl),a
        ld c,P_PANEL<<3 | C_OK          ; its colour
        cp INT_WARN
        jr nc,.col
        ld c,P_PANEL<<3 | C_AMBER
        cp INT_DANGER
        jr nc,.col
        ld c,P_PANEL<<3 | C_WARN
.col:   ld hl,ULA_ATTR + (INT_ROW+1)*32 + INT_PCT_COL
        ld b,4
.at:    ld (hl),c
        inc hl
        djnz .at
        ld hl,int_txt                   ; the digits, no leading zeros
        ld b,100
        call .dig
        ld b,10
        call .dig
        ld (hl),a                       ; units
        ld a,(int_txt)
        or a
        jr nz,.pr
        ld a,GLYPH_SPACE
        ld (int_txt),a
        ld a,(int_txt+1)
        or a
        jr nz,.pr
        ld a,GLYPH_SPACE
        ld (int_txt+1),a
.pr:    ld hl,int_txt
        ld de,ULA_ROW_INT+32+INT_PCT_COL
        ld b,4
        jr print_glyphs
.dig:   ld (hl),0                       ; A = A mod B, (HL) = A / B
.ds:    cp b
        jr c,.dd
        sub b
        inc (hl)
        jr .ds
.dd:    inc hl
        ret
        ASSERT VTOL_HP == 50            ; (percent = hp * 2)
        ASSERT INT_PCT_COL+3 < MAP_COL && INT_COL+8 < MAP_COL

; HL -> B glyph codes, DE = first ULA cell: print them along the row
print_glyphs:
.l:     push bc
        push de
        ld a,(hl)
        inc hl
        push hl
        call print_glyph_at
        pop hl
        pop de
        inc e
        pop bc
        djnz .l
        ret

;------------------------------------------------------------------------------
; Layer 2 double buffering with the hardware shadow register.
;   NextReg $12 = active bank (on screen), NextReg $13 = shadow bank.
; The game always draws into the shadow bank; l2_flip swaps the two during
; vertical blank, so the registers themselves record which buffer is which.
;------------------------------------------------------------------------------

;==============================================================================
; HUD: the weapon slots, and the speed, altitude and ground height gauges
; (the humans and the compass are hardware sprites: hud_sprites.asm).  The
; gauges are vertical bars on Layer 2 (in the back buffer, every frame)
; behind transparent ULA cells: the
; altitude and ground bars share one 8-pixel cell column, which ULA
; attributes couldn't colour (green, amber and black in one cell).
;==============================================================================
draw_hud:
        call draw_wpn
        call draw_integrity
        ; (the humans' states: hardware sprites, hum_hud in human.asm)

        call draw_gauges
        jp map_player

; The gauges, GAUGE_H (48) pixels tall:
;   S  speed, 8 wide: (speed * 55) / 32 pixels, so SPEED_MAX 28 fills it;
;      green, red when reversing, amber while boosting (full: BOOST_SPEED is
;      past the top)
;   A  left 4 pixels: altitude, green; right 4: the height of the city tile
;      under the craft (0 on a road), amber.  Both 1 pixel per 4 units, so
;      the ceiling (MAX_Y 1.5 height units, 192) fills the bar; with the
;      vertical thrusters 1 per 8, so their ceiling (MAX_Y_THRUST, 384) does.
;      A tile taller than the bar's top fills it.  The ground under the
;      craft is always lower, so the gap between them is the clearance.
;   B  the booster's fuel, 8 wide: fuel * 62 / 256 pixels, so BOOST_FUEL_MAX
;      (200) fills it; green.  Drawn always, but its cells are opaque panel
;      until the booster is fitted (ula_init).
draw_gauges:
        ld a,(boost_fuel)
        ld d,a
        ld e,62
        mul d,e
        ld a,d
        call g_clamp
        ld (g_fuel),a
        ASSERT BOOST_FUEL_MAX*62/256 >= GAUGE_H
        ld a,(speed)
        ld c,HUD_COL
        bit 7,a
        jr z,.sp
        neg
        ld c,HUD_WARN
.sp:    ld b,a
        ld a,(boost_on)
        or a
        ld a,b
        jr z,.nbo
        ld c,GAUGE_AMBER                ; boosting
.nbo:   ld d,a
        ld e,55
        mul d,e
        ld b,5
        bsrl de,b
        ld a,c
        ld (g_spdc),a
        ld a,e
        call g_clamp
        ld (g_spd),a
        ld hl,(cam_y)
        call g_px
        ld (g_alt),a
        call cam_cell_ptr
        ld a,(hl)
        call bld_height                 ; HL = height of this tile
        call g_px
        ld (g_gnd),a
        ld c,0                          ; row from the top
.row:   ld a,c
        add a,GAUGE_TOP
        ld b,a
        rlca
        rlca
        rlca
        and 7                           ; its 32-row section
        ld e,a
        ld a,(seg_base)                 ; (the back buffer)
        add a,e
        nextreg L2SEC_MMU,a
        ld a,b
        and 31
        ld h,a
        ld l,SPD_GCOL*8
        ld a,GAUGE_H
        sub c
        ld b,a                          ; this row's level: GAUGE_H..1
        ld a,(g_spd)                    ; speed: filled up to its level?
        cp b
        ld a,(g_spdc)
        jr nc,.s
        ld a,MAP_BG                     ; empty: black
.s:     REPT 8
        ld (hl),a
        inc l
        ENDR
        ld l,ALT_GCOL*8
        ld a,(g_alt)
        cp b
        ld a,HUD_COL
        jr nc,.a
        ld a,MAP_BG
.a:     REPT 4
        ld (hl),a
        inc l
        ENDR
        ld a,(g_gnd)
        cp b
        ld a,GAUGE_AMBER
        jr nc,.g
        ld a,MAP_BG
.g:     REPT 4
        ld (hl),a
        inc l
        ENDR
        ld l,BST_GCOL*8                 ; the booster's fuel
        ld a,(g_fuel)
        cp b
        ld a,HUD_COL
        jr nc,.f
        ld a,MAP_BG
.f:     REPT 8
        ld (hl),a
        inc l
        ENDR
        inc c
        ld a,c
        cp GAUGE_H
        jr nz,.row
        ret

; HL = height (world units) -> A = HL / 4, at most GAUGE_H
g_px:
        ld a,(vthrust_fitted)           ; the thrusters' ceiling: half scale
        or a
        jr z,.s
        srl h
        rr l
.s:     srl h
        rr l
        srl h
        rr l
        ld a,h
        or a
        ld a,GAUGE_H
        ret nz
        ld a,l
g_clamp:
        cp GAUGE_H+1
        ret c
        ld a,GAUGE_H
        ret

;==============================================================================
; HUD page data
;==============================================================================
int_shown:  db $FF                      ; draw_integrity: the percentage shown
int_txt:    db 0, 0, 0, GLYPH_PCT       ;   its glyphs: digits, %
lbl_int:    db GLYPH_I, GLYPH_N, GLYPH_T, GLYPH_E, GLYPH_G, GLYPH_R, GLYPH_I
            db GLYPH_T, GLYPH_Y         ; INTEGRITY
wd_flash:   db $FF                      ; draw_wpn: the slot flashing amber,
wd_col:     db 0                        ;   the box's column offset,
wd_type:    db 0                        ;   and its slot's weapon
; the boxes' slots, left to right (keys 2 4 1 5 3)
wpn_order:  db 1, 3, 0, 4, 2
        ASSERT $ - wpn_order == WPN_SLOTS
; weapon type (WPN_*) -> its letter under the box
wpn_glyph:  db GLYPH_SPACE              ; WPN_NONE
            db GLYPH_M                  ; WPN_GUN: machine gun
            db GLYPH_L                  ; WPN_LASER
            db GLYPH_C                  ; WPN_CHAIN: chain gun
            db GLYPH_R                  ; WPN_ROCKETS: rocket pod
            db GLYPH_S                  ; WPN_MISSILE: missile pod
            db GLYPH_SPACE              ; WPN_BOMB (none yet)
            db GLYPH_A                  ; WPN_AUTOCANNON: autocannon
            db GLYPH_P                  ; WPN_PROX: proximity cannon
        ASSERT $ - wpn_glyph == WPN_LAST + 1
g_spd:      db 0                        ; draw_gauges: bar heights (pixels)
g_spdc:     db 0                        ;   and the speed bar's colour
g_alt:      db 0
g_gnd:      db 0
g_fuel:     db 0

; 8x8 glyphs: digits 0-9, then F, P, S, space
GLYPH_F     equ 10
GLYPH_P     equ 11
GLYPH_S     equ 12
GLYPH_SPACE equ 13
GLYPH_D     equ 14
GLYPH_A     equ 15
GLYPH_L     equ 16
GLYPH_T     equ 17
GLYPH_G     equ 18
GLYPH_R     equ 19
GLYPH_N     equ 20
GLYPH_MAN   equ 21
GLYPH_SEAT  equ 22
GLYPH_M     equ 23
GLYPH_C     equ 24
GLYPH_B     equ 25
GLYPH_I     equ 26
GLYPH_E     equ 27
GLYPH_Y     equ 28
GLYPH_PCT   equ 29
; ULA bitmap cell addresses (pixel line 0) of the gauge rows
ULA_ROW_LBL equ ULA_BMP + (GAUGE_LROW/8)*$800 + (GAUGE_LROW&7)*32
ULA_ROW_INT equ ULA_BMP + (INT_ROW/8)*$800 + (INT_ROW&7)*32
        ASSERT INT_ROW/8 == (INT_ROW+1)/8       ; (+32: the next row)
font:
        db $00,$3C,$46,$4A,$52,$62,$3C,$00     ; 0
        db $00,$18,$28,$08,$08,$08,$3E,$00     ; 1
        db $00,$3C,$42,$02,$3C,$40,$7E,$00     ; 2
        db $00,$3C,$42,$0C,$02,$42,$3C,$00     ; 3
        db $00,$08,$18,$28,$48,$7E,$08,$00     ; 4
        db $00,$7E,$40,$7C,$02,$42,$3C,$00     ; 5
        db $00,$3C,$40,$7C,$42,$42,$3C,$00     ; 6
        db $00,$7E,$02,$04,$08,$10,$10,$00     ; 7
        db $00,$3C,$42,$3C,$42,$42,$3C,$00     ; 8
        db $00,$3C,$42,$42,$3E,$02,$3C,$00     ; 9
        db $00,$7E,$40,$7C,$40,$40,$40,$00     ; F
        db $00,$7C,$42,$42,$7C,$40,$40,$00     ; P
        db $00,$3C,$40,$3C,$02,$42,$3C,$00     ; S
        db $00,$00,$00,$00,$00,$00,$00,$00     ; space
        db $00,$78,$44,$42,$42,$44,$78,$00     ; D
        db $00,$3C,$42,$42,$7E,$42,$42,$00     ; A
        db $00,$40,$40,$40,$40,$40,$7E,$00     ; L
        db $00,$FE,$10,$10,$10,$10,$10,$00     ; T
        db $00,$3C,$42,$40,$4E,$42,$3C,$00     ; G
        db $00,$7C,$42,$42,$7C,$44,$42,$00     ; R
        db $00,$42,$62,$52,$4A,$46,$42,$00     ; N
        db $18,$18,$7E,$18,$18,$24,$24,$66     ; stick man (passenger aboard)
        db $00,$7E,$42,$42,$42,$42,$7E,$00     ; empty seat: hollow 6x6 square
        db $00,$42,$66,$5A,$42,$42,$42,$00     ; M
        db $00,$3C,$42,$40,$40,$42,$3C,$00     ; C
        db $00,$7C,$42,$7C,$42,$42,$7C,$00     ; B
        db $00,$3E,$08,$08,$08,$08,$3E,$00     ; I
        db $00,$7E,$40,$7C,$40,$40,$7E,$00     ; E
        db $00,$42,$24,$18,$08,$08,$08,$00     ; Y
        db $00,$62,$64,$08,$10,$26,$46,$00     ; %
