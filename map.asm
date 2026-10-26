;==============================================================================
; Z-POLICE - city map (page 7, after human.asm: kept mapped in slot 3)
;
; Everything that draws the GRID x GRID city map at the right of the
; instrument panel (pixel columns MAP_X.., rows 128-191, one pixel per cell,
; north up):
;   * map_init / map_l2: the map itself, drawn once at start-up into both
;     Layer 2 buffers, and the ULA set-up over it (called from ula_init);
;   * map_player: the player's flashing white dot, on the ULA (draw_hud);
;   * zblip / zblip_off: zombie blips, bright green (zombie.asm, weapons.asm);
;   * hum_dots / hum_dot: humans' flashing blue dots (human.asm);
;   * map_pix / map_under: set one map cell's pixel in both Layer 2 buffers,
;     and the colour the map itself has there.
; Page 7 is always mapped, so all the pages above can call in here.
;==============================================================================

;------------------------------------------------------------------------------
; City map: GRID x GRID cells at one pixel each (64x64), north up, at pixel
; columns MAP_X.. and rows 128-191.  It is drawn on Layer 2, into both
; buffers once (the viewport clear only touches rows 0-127), so each
; building can be its own colour; zombie blips and human dots are written
; into it too.  The ULA above it is transparent paper with white ink for the
; player's flashing dot.
;------------------------------------------------------------------------------
map_init:
        xor a                           ; no player dot drawn yet
        ld (mp_mask),a
        ld hl,ULA_ATTR+16*32+MAP_COL    ; map area: transparent paper,
        ld c,8                          ; white ink
.ar:    ld b,32-MAP_COL
        push hl
.ac:    ld (hl),7
        inc hl
        djnz .ac
        pop hl
        ld de,32
        add hl,de
        dec c
        jr nz,.ar
        ld hl,ULA_BMP+$1000+MAP_COL     ; no panel divider over the map
        ld b,32-MAP_COL
.dv:    ld (hl),0
        inc hl
        djnz .dv
        ld a,L2_BANK_A*2                ; both Layer 2 buffers
        call map_l2
        ld a,L2_BANK_B*2
        ; fall through

; A = first 8K page of a Layer 2 buffer: draw the map into it.  Streets are
; MAP_BG, buildings their colour family's base shade.
map_l2:
        ld (ml_base),a
        ld hl,city_map
        ld de,city_col
        ld c,0                          ; C = j (row), +Z
.row:   ld a,191                        ; y = 191 - j  (north up)
        sub c
        push af
        rlca
        rlca
        rlca
        and 7                           ; its 32-row section
        ld b,a
        ld a,(ml_base)
        add a,b
        nextreg $50,a                   ; paged in at $0000
        pop af
        and 31
        ld ixh,a
        ld ixl,MAP_X
        ld b,GRID
.px:    ld a,(hl)
        or a
        ld a,MAP_BG
        jr z,.st
        ld a,(de)
        or SHADE_FACE
.st:    ld (ix+0),a
        inc ix
        inc hl
        inc de
        djnz .px
        inc c
        ld a,c
        cp GRID
        jr nz,.row
        ret

; D = y, E = x -> HL = ULA byte (screen paged at ULA_BMP), A = pixel mask
ula_pixel:
        pixelad                         ; HL = $4000-based address
        ld a,h
        add a,high (ULA_BMP-$4000)
        ld h,a
        setae                           ; A = $80 >> (x & 7)
        ret

; Flashing player position: undo last frame's XOR, then on alternate frames
; XOR the pixel under the player (1 map pixel per cell).
map_player:
        ld hl,(mp_addr)
        ld a,(mp_mask)
        xor (hl)
        ld (hl),a
        xor a
        ld (mp_mask),a
        ld hl,mp_frame
        inc (hl)
        bit 0,(hl)
        ret z                           ; off this frame
        ld a,(cam_x+2)                  ; cell x: one map pixel per cell
        add a,MAP_X
        ld e,a
        ld a,(cam_z+2)                  ; cell z
        neg
        add a,191                       ; north up
        ld d,a
        call ula_pixel
        ld (mp_addr),hl
        ld (mp_mask),a
        xor (hl)
        ld (hl),a
        ret

;------------------------------------------------------------------------------
; Zombie blips: each zombie is one bright green (MAP_ZOMBIE) pixel at its cell,
; using record bytes +12,+13 (blip cell) and +14 (bit 0: plotted; bits 1-2:
; its place in the shade cycle).  Each time zblip draws it, the blip takes
; the next shade of zshades: bright, mid, dark, mid, bright...  Zombies only
; stand in street cells, so taking a blip off puts the street colour (MAP_BG)
; back.  (When two zombies share a cell and one leaves, the other's blip is
; gone until its own next check.)
;------------------------------------------------------------------------------
; Move zombie IX's street map blip to its current cell, in its next shade
zblip:
        call zblip_off
        ld e,(ix+1)                     ; cell x
        ld d,(ix+3)                     ; cell z
        ld (ix+12),e
        ld (ix+13),d
        ld a,(ix+14)                    ; shade step (bits 1-2), plotted off
        ld c,a
        add a,2                         ; next step, and plotted
        and 6
        inc a
        ld (ix+14),a
        ld a,c
        rrca
        and 3
        ld hl,zshades
        add hl,a
        ld a,(hl)                       ; this step's shade
        jr map_pix

; Take zombie IX's blip off the map
zblip_off:
        bit 0,(ix+14)
        ret z
        res 0,(ix+14)                   ; (keeps its shade step)
        ld e,(ix+12)
        ld d,(ix+13)
        ld a,MAP_BG                     ; a street cell again
        ; fall through

; Set map pixel for cell (E, D) to colour A in both Layer 2 buffers.  Pages
; their section in at $0000 (slot 0, which drawing re-pages as it goes).
map_pix:
        ld c,a
        ld a,191                        ; y = 191 - z  (north up)
        sub d
        ld b,a
        rlca
        rlca
        rlca
        and 7                           ; its 32-row section
        ld d,a
        ld a,b
        and 31
        ld h,a
        ld a,e
        add a,MAP_X
        ld l,a                          ; HL = pixel in the section
        ld a,L2_BANK_A*2
        add a,d
        nextreg $50,a
        ld (hl),c
        ld a,L2_BANK_B*2
        add a,d
        nextreg $50,a
        ld (hl),c
        ret

; Zombie IX attacking: its blip red (MAP_ZOMBIE_ATK) at its current cell,
; until zblip draws it normally again
zblip_red:
        call zblip_off
        ld e,(ix+1)
        ld d,(ix+3)
        ld (ix+12),e
        ld (ix+13),d
        set 0,(ix+14)                   ; plotted (keeps its shade step)
        ld a,MAP_ZOMBIE_ATK
        jp map_pix

;------------------------------------------------------------------------------
; Human dots: flashing blue (HUMAN_BLIP), using record bytes +7,+8 (dot cell)
; and +9 (shown).
;------------------------------------------------------------------------------
; C = 1: show, 0: hide the map dots of all waiting humans
hum_dots:
        ld ix,humans
        ld b,HUMAN_MAX
.lp:    push bc
        ld a,(ix+6)
        or a
        call nz,hum_dot
        ld de,HREC
        add ix,de
        pop bc
        djnz .lp
        ret

; Human IX's map dot: C = 1 show (at its current cell), 0 hide.  Keeps C.
hum_dot:
        push bc
        bit 0,(ix+9)                    ; take the old dot off first
        jr z,.on
        ld (ix+9),0
        ld e,(ix+7)
        ld d,(ix+8)
        call map_under                  ; A = what the map shows there
        call map_pix
.on:    pop bc
        push bc
        bit 0,c
        jr z,.x
        ld e,(ix+1)
        ld d,(ix+3)
        ld (ix+7),e
        ld (ix+8),d
        ld (ix+9),1
        ld a,HUMAN_BLIP
        call map_pix
.x:     pop bc
        ret

; E = cell x, D = cell z -> A = the map colour of that cell.  Keeps DE.
map_under:
        push de
        ld l,d
        ld h,0
        ROWOFS
        ld a,e
        add hl,a
        push hl
        ld de,city_map
        add hl,de
        ld a,(hl)
        pop hl
        or a
        ld a,MAP_BG
        jr z,.x                         ; street
        ld de,city_col
        add hl,de
        ld a,(hl)
        or SHADE_FACE
.x:     pop de
        ret

;==============================================================================
; Map data
;==============================================================================
zshades:    db MAP_ZOMBIE, MAP_ZOMBIE_MID, MAP_ZOMBIE_DARK, MAP_ZOMBIE_MID
mp_addr:    dw ULA_BMP                  ; player dot: ULA byte, mask, flash
mp_mask:    db 0
mp_frame:   db 0
ml_base:    db 0                        ; map_l2: first page of the buffer
