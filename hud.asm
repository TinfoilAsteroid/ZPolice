;==============================================================================
; Z-POLICE - HUD page (8K page PAGE_HUD, runs at $E000)
;
; ULA (Layer 1) code: panel set-up, FPS text, speed/altitude gauges and the
; city map with the flashing player marker.  Paged in by main_loop with
; nextreg $57,PAGE_HUD.  Shared variables live in zpolice.asm.
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

ula_init:
        ld hl,ULA_BMP
        ld de,ULA_BMP+1
        ld bc,$1800-1
        ld (hl),0
        ldir                            ; bitmap: all paper
        ld hl,ULA_ATTR
        ld de,ULA_ATTR+1
        ld bc,16*32-1
        ld (hl),%01000111               ; viewport: bright, paper 0, ink 7
        ldir
        ld hl,ULA_ATTR+16*32
        ld de,ULA_ATTR+16*32+1
        ld bc,8*32-1
        ld (hl),ATTR_PANEL              ; panel
        ldir
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

        ld a,$FF                        ; the HUD's "last drawn" values:
        ld (pax_shown),a                ; none, so everything is drawn
        ld (wsel_shown),a
        ld a,GLYPH_S                    ; gauge labels: S (speed) and
        ld de,ULA_ROW_LBL+SPD_GCOL      ; A (altitude | ground)
        call print_glyph_at
        ld a,GLYPH_A
        ld de,ULA_ROW_LBL+ALT_GCOL
        call print_glyph_at
        ld hl,ULA_ATTR + 17*32 + SPD_GCOL  ; the gauges' cells: transparent,
        ld b,GAUGE_H/8                  ; showing the Layer 2 bars
.ga:    ld (hl),0
        ld a,ALT_GCOL-SPD_GCOL
        add hl,a
        ld (hl),0
        ld a,32-(ALT_GCOL-SPD_GCOL)
        add hl,a
        djnz .ga
        ld hl,lbl_wpn                   ; "WPN:" and the slot digits
        ld de,ULA_ROW_PAX+WPN_LBL
        call print_label
        ld a,GLYPH_COLON
        ld de,ULA_ROW_PAX+WPN_LBL+3
        call print_glyph_at
        ld c,0
.wd:    ld a,c
        push bc
        ld b,0
        call wpn_digit
        pop bc
        inc c
        ld a,c
        cp WPN_SLOTS
        jr nz,.wd
        call map_init
        call compass_init
    IFDEF DRAW_FPS
        jp fps_draw                     ; initial " 0 FPS"
    ELSE
        ret
    ENDIF

;------------------------------------------------------------------------------
; Compass: a horizontal strip, 32x8 pixels in a 2-pixel frame, centred on the
; current heading.  Layer 2 (per-pixel colour: red N/E/S/W, yellow NE/SE/
; SW/NW) under transparent ULA cells.  compass_tape (gentables.py) covers a
; full turn at 4 yaw units a pixel; each frame the 32 columns centred on yaw
; are copied into the back buffer.
;------------------------------------------------------------------------------
; New game: the ULA cells over the compass transparent (paper 0, no ink),
; and the frame and background drawn into both Layer 2 buffers
compass_init:
        ld hl,ULA_ATTR + 19*32 + 15
        ld b,6
.a1:    ld (hl),0
        inc hl
        djnz .a1
        ld hl,ULA_ATTR + 20*32 + 15
        ld b,6
.a2:    ld (hl),0
        inc hl
        djnz .a2
        ld a,L2_BANK_A*2
        call .buf
        ld a,L2_BANK_B*2
.buf:   ld (cp_base),a                  ; A = first page of a buffer
        ld hl,compass_bg
        ld c,COMP_BGY                   ; row
.row:   ld a,c
        rlca
        rlca
        rlca
        and 7                           ; its 32-row section
        ld b,a
        ld a,(cp_base)
        add a,b
        nextreg $50,a
        ld a,c
        and 31
        ld d,a
        ld e,COMP_BGX
        push bc
        ld bc,48
        ldir
        pop bc
        inc c
        ld a,c
        cp COMP_BGY+16
        jr nz,.row
        ret

; Each frame: the 32 columns of the tape centred on the heading
draw_compass:
        ld a,(yaw)
        rrca
        rrca
        and 63                          ; centre column (4 yaw units a pixel)
        sub 16
        and 63                          ; left edge
        ld (cp_col),a
        ld c,0                          ; tape row
.row:   ld a,c                          ; screen row COMP_Y + c
        add a,COMP_Y
        ld b,a
        rlca
        rlca
        rlca
        and 7
        ld e,a
        ld a,(seg_base)                 ; the back buffer's section
        add a,e
        nextreg $50,a
        ld a,b
        and 31
        push bc
        ld b,a                          ; DE -> the row in the section
        ld d,c
        ld e,96
        mul d,e                         ; tape row * 96
        ld hl,compass_tape
        add hl,de
        ld a,(cp_col)
        add hl,a
        ld d,b
        ld e,COMP_X
        ld bc,32
        ldir
        pop bc
        inc c
        ld a,c
        cp 8
        jr nz,.row
        ret

;------------------------------------------------------------------------------
; Weapon slots, right of the passengers: "WPN:" and the digits 1-5.  A digit
; is green if its slot holds a weapon, light blue if it is empty; the
; selected slot's digit has a box round it.  An empty slot that was asked
; for flashes yellow / blue (WFLASH frames each, 3 times, ending blue).
;------------------------------------------------------------------------------
draw_wpn:
        ld a,(wpn_sel)                  ; move the box when the selection changes
        ld hl,wsel_shown
        cp (hl)
        jr z,.col
        ld c,(hl)
        ld (hl),a
        ld a,c
        cp WPN_SLOTS
        jr nc,.new                      ; nothing boxed yet
        ld b,0
        call wpn_digit                  ; the old one: plain
.new:   ld a,(wpn_sel)
        ld b,1
        call wpn_digit                  ; the new one: boxed
.col:   ld hl,ULA_ATTR + PAX_ROW*32 + WPN_COL
        ld de,wpn_slots
        ld b,0
.lp:    ld c,P_PANEL<<3 | C_OK          ; fitted: green
        ld a,(de)
        or a
        jr nz,.fl
        ld c,P_PANEL<<3 | C_BLUE        ; empty: blue
.fl:    ld a,(wflash_t)                 ; flashing this one?
        or a
        jr z,.st
        ld a,(wflash_slot)
        cp b
        jr nz,.st
        ld a,(wflash_t)                 ; phase (t-1)/WFLASH: odd = yellow
        dec a
        push bc
        ld b,-1
.dv:    inc b
        sub WFLASH
        jr nc,.dv
        bit 0,b
        pop bc
        jr z,.st
        ld c,P_PANEL<<3 | C_YEL
.st:    ld (hl),c
        inc hl
        inc de
        inc de
        inc b
        ld a,b
        cp WPN_SLOTS
        jr nz,.lp
        ld hl,wflash_t                  ; count the flash down
        ld a,(hl)
        or a
        ret z
        dec (hl)
        ret

; A = slot: draw its digit (slot + 1); B = 1: with a box round it
wpn_digit:
        ld e,a
        add a,low (ULA_ROW_PAX + WPN_COL)
        ld l,a
        ld h,high (ULA_ROW_PAX + WPN_COL)
        push hl
        ld a,e
        inc a                           ; glyph = digit
        ex de,hl
        push bc
        call print_glyph_at
        pop bc
        pop hl
        bit 0,b
        ret z
        ld a,(hl)                       ; box: top and bottom rows, and
        or $FF                          ; both sides between (the digits
        ld (hl),a                       ; keep clear of the cell's edge)
        ld b,6
.sd:    inc h
        ld a,(hl)
        or $81
        ld (hl),a
        djnz .sd
        inc h
        ld (hl),$FF
        ret

;------------------------------------------------------------------------------
; Passengers: PASSENGER_MAX 8x8 cells on the panel's top row.  From the left:
; a green stick man for each human saved (delivered to the base), a white
; one for each human aboard, and an empty seat (a hollow square) for the rest.
;------------------------------------------------------------------------------
draw_pax:
        ld de,ULA_ROW_PAX + PAX_COL
        ld hl,ULA_ATTR + PAX_ROW*32 + PAX_COL
        ld b,0                          ; cell
.lp:    push bc
        push de
        push hl
        ld a,(saved)
        ld c,a
        ld a,b
        cp c
        jr nc,.ab
        ld (hl),P_PANEL<<3 | C_OK       ; saved: green man
        ld a,GLYPH_MAN
        jr .g
.ab:    ld (hl),ATTR_PANEL              ; white
        ld a,(passengers)
        add a,c
        ld c,a                          ; saved + aboard
        ld a,b
        cp c
        ld a,GLYPH_SEAT
        jr nc,.g                        ; empty seat
        ld a,GLYPH_MAN                  ; aboard
.g:     call print_glyph_at
        pop hl
        inc hl
        pop de
        inc e
        pop bc
        inc b
        ld a,b
        cp PASSENGER_MAX
        jr nz,.lp
        ret

; HL -> 3 glyph codes, DE = first ULA cell
print_label:
        ld b,3
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
; HUD: weapons, compass, passengers, and the speed, altitude and ground
; height gauges.  The gauges are vertical bars on Layer 2 (in the back
; buffer, every frame) behind transparent ULA cells, as the compass is: the
; altitude and ground bars share one 8-pixel cell column, which ULA
; attributes couldn't colour (green, amber and black in one cell).
;==============================================================================
draw_hud:
        call draw_wpn
        call draw_compass
        ; passengers: redrawn when the number aboard or saved changes
        ld a,(saved)                    ; (human.asm, page 7)
        add a,a
        add a,a
        add a,a
        ld hl,passengers
        add a,(hl)
        ld hl,pax_shown
        cp (hl)
        jr z,.pxok
        ld (hl),a
        call draw_pax
.pxok:

        call draw_gauges
        jp map_player

; The gauges, GAUGE_H (48) pixels tall:
;   S  speed, 8 wide: (speed * 55) / 32 pixels, so SPEED_MAX 28 fills it;
;      green, red when reversing
;   A  left 4 pixels: altitude, green; right 4: the height of the city tile
;      under the craft (0 on a road), amber.  Both 1 pixel per 4 units, so
;      the ceiling (MAX_Y 1.5 height units, 192) fills the bar; the ground
;      under the craft is always lower, so the gap between them is the
;      clearance.
draw_gauges:
        ld a,(speed)
        ld c,HUD_COL
        bit 7,a
        jr z,.sp
        neg
        ld c,HUD_WARN
.sp:    ld d,a
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
        nextreg $50,a
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
        inc c
        ld a,c
        cp GAUGE_H
        jr nz,.row
        ret

; HL = height (world units) -> A = HL / 4, at most GAUGE_H
g_px:
        srl h
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
pax_shown:  db $FF                      ; passengers last drawn ($FF: not yet)
wsel_shown: db $FF                      ; weapon slot boxed ($FF: none yet)
g_spd:      db 0                        ; draw_gauges: bar heights (pixels)
g_spdc:     db 0                        ;   and the speed bar's colour
g_alt:      db 0
g_gnd:      db 0
cp_col:     db 0                        ; compass: tape column at the left edge
cp_base:    db 0                        ; compass_init: buffer being drawn

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
GLYPH_W     equ 23
GLYPH_COLON equ 24
; ULA bitmap cell addresses (pixel line 0) of the gauge rows
ULA_ROW_LBL equ ULA_BMP + (GAUGE_LROW/8)*$800 + (GAUGE_LROW&7)*32
ULA_ROW_PAX equ ULA_BMP + (PAX_ROW/8)*$800 + (PAX_ROW&7)*32
lbl_wpn:    db GLYPH_W,GLYPH_P,GLYPH_N
        INCLUDE "tables_compass.inc"    ; compass_tape, compass_bg
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
        db $00,$42,$42,$42,$5A,$66,$42,$00     ; W
        db $00,$00,$18,$18,$00,$18,$18,$00     ; colon
