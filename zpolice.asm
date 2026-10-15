;==============================================================================
; Z-POLICE  -  3D vector city flight for the ZX Spectrum Next
;
;  Z80N assembler (sjasmplus --zxnext).  Layer 2 256x192x8bpp, double buffered.
;  Maths: world positions are 16-bit integers (one city cell = 256 units),
;         trig values are S7.8 fixed point (1.0 = $0100).
;  Hidden line removal: painter's algorithm. Buildings are walked over the
;  grid far-to-near (no sort needed). Each visible face is filled in its
;  shade (roof lighter, side turned away darker) and optionally outlined, so
;  nearer buildings overwrite those behind them. Faces with every corner on
;  screen use cached projections; faces crossing the view frustum are
;  clipped in 3D (Sutherland-Hodgman, 5 planes). Rasterisation then only
;  ever sees on-screen 8-bit coordinates.
;
;  Controls: Q/A speed up/down   W stop      S/F turn left/right
;            E/D nose down/up    T/G climb/descend
;
;  Memory while running:
;    $0000-$BFFF  Layer 2 back buffer (MMU slots 0-5), address = y*256+x
;    $C000-$FFFF  code, tables, variables, stack (16K bank 0)
;==============================================================================

        DEVICE ZXSPECTRUMNEXT
        SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
        CSPECTMAP zpolice.map
        OPT --zxnext=cspect --syntax=a --reversepop
;------------------------------------------------------------------------------
; Build options
;------------------------------------------------------------------------------
; DRAW_LINES: outline building faces with EDGE_COL vectors.  Comment it out for solid-colour buildings only; the HUD
; is always drawn.  Can also be set from the command line: -DDRAW_LINES
        ;DEFINE DRAW_LINES

; WAIT_FOR_VBLANK: wait for the raster to leave the display area before
; flipping the Layer 2 buffers (no tearing).  Comment it out to flip as soon
; as a frame is drawn: faster, but the flip may tear mid-screen.
; Command line: -DWAIT_FOR_VBLANK
        DEFINE WAIT_FOR_VBLANK

;------------------------------------------------------------------------------
; Tuning constants
;------------------------------------------------------------------------------
NEAR            equ 16          ; near clip plane (world units)
VIEW_R          equ 6           ; buildings drawn within +/- this many cells
DOT_R           equ 5           ; street intersection markers radius (cells)
PMAX            equ 24          ; pitch limit (256 = 360 deg) - match gentables.py
SPEED_MAX       equ 56
SPEED_MIN       equ -12
YAW_RATE        equ 3
CLIMB_RATE      equ 8
MIN_Y           equ 16
MAX_Y           equ 900
WORLD_MIN       equ 64
WORLD_MAX       equ 8128
DMA_SPAN_MIN    equ 20          ; spans this wide or wider are filled by DMA
COLL_M          equ 24          ; collision margin around buildings

INSET0          equ 40          ; block footprint
SIZE0           equ 176
INSET1          equ 80          ; tower footprint
SIZE1           equ 96

; Layer 2 colours (RRRGGGBB). Avoid $E3 (global transparency).
; Layer 2 uses a custom palette (l2_palette from gentables.py) arranged in
; families of four: family*4 + SHADE_*.  The +3 slots hold the fixed colours.
SKY_COL         equ 3
GROUND_COL      equ 7
EDGE_COL        equ 11
HUD_COL         equ 15
HUD_WARN        equ 19
DOT_COL         equ 23
SHADE_DARK      equ 0           ; side turned away from the player
SHADE_FACE      equ 1           ; side facing the player (base colour)
SHADE_ROOF      equ 2           ; roof, lighter

L2_BANK_A       equ 9           ; 16K banks 9-11
L2_BANK_B       equ 12          ; 16K banks 12-14

; zxnDMA WR0 (transfer A->B) with only the length low / high byte following
DMA_WR0_LEN_LO  equ %00100101
DMA_WR0_LEN_HI  equ %01000101

; Self-modified opcodes for the line drawer
OP_INC_L        equ $2C
OP_DEC_L        equ $2D
OP_INC_H        equ $24
OP_DEC_H        equ $25

; dst = src + vec  (three 16-bit components)
        MACRO VADD QD, QS, QV
        ld hl,(QS)
        ld de,(QV)
        add hl,de
        ld (QD),hl
        ld hl,(QS+2)
        ld de,(QV+2)
        add hl,de
        ld (QD+2),hl
        ld hl,(QS+4)
        ld de,(QV+4)
        add hl,de
        ld (QD+4),hl
        ENDM

; Copy cached screen corner of face vertex (HL)+ into p2buf (DE)+ with the
; outline flag for edge bit EB taken from df_mask.  B = high vtx.
        MACRO FACEVTX EB
        ld a,(hl)
        inc hl
        add a,7
        ld c,a
        ld a,(bc)
        ld (de),a
        inc e
        inc c
        ld a,(bc)
        ld (de),a
        inc e
        ld a,(df_mask)
        and EB
        ld (de),a
        inc e
        inc e
        ENDM

        ORG $C000

;==============================================================================
; Entry
;==============================================================================
start:
        di
        ld sp,stack_top
        nextreg $07,3                   ; 28MHz
        nextreg $70,0                   ; Layer 2 256x192 mode
        nextreg $14,$E3                 ; global transparency colour
        nextreg $15,%00001000           ; sprites off, priority S U L (ULA over L2)
        nextreg $16,0                   ; Layer 2 scroll X
        nextreg $17,0                   ; Layer 2 scroll Y
        nextreg $1C,%00000001           ; reset L2 clip index
        nextreg $18,0
        nextreg $18,255
        nextreg $18,0
        nextreg $18,191
        xor a
        out ($FE),a                     ; black border
        ld bc,$123B
        ld a,%00000010                  ; Layer 2 visible, no write paging
        out (c),a

        ; load the shaded Layer 2 palette (first L2 palette, 9-bit entries)
        nextreg $43,%00010000           ; edit Layer 2 palette 0, auto-inc
        nextreg $40,0
        ld hl,l2_palette
        ld b,0                          ; 256 entries
.pal:   ld a,(hl)
        inc hl
        nextreg $44,a                   ; RRRGGGBB
        ld a,(hl)
        inc hl
        nextreg $44,a                   ; low blue bit
        djnz .pal

        ; clear both buffers once
        ld a,96
        ld (horizon),a
        ld a,L2_BANK_A
        call map_bank
        call clear_screen
        ld a,L2_BANK_B
        call map_bank
        call clear_screen
        nextreg $12,L2_BANK_A           ; Layer 2 active (displayed) bank
        nextreg $13,L2_BANK_B           ; Layer 2 shadow bank (drawn into)
        call ula_init                   ; transparent ULA overlay for the FPS

;==============================================================================
; Main loop
;==============================================================================
main_loop:
        call update_player
        call setup_frame
        call map_shadow
        call vtick
        call clear_screen
        call vtick
        call draw_dots
        call vtick
        call draw_city                  ; also calls vtick once per building
        call draw_hud
    IFDEF WAIT_FOR_VBLANK
        call wait_vblank
    ENDIF
        call l2_flip
        call fps_tick                   ; may page the ULA screen into $4000
        jp main_loop

;==============================================================================
; Frames per second, shown on the ULA layer above Layer 2.
;
; Interrupts stay off (the span filler borrows SP), so time is taken from the
; raster: vtick reads the current video line and counts a new 50Hz video
; frame whenever the line number has gone backwards.  It must be called at
; least once per video frame (~560K T at 28MHz); the main loop and draw_cell
; do that.  Every 50 video frames (1 second) the number of frames rendered
; becomes the FPS figure.
;==============================================================================
vtick:
        ld bc,$243B
        ld a,$1E
        out (c),a
        inc b
        in d,(c)                        ; line MSB
        dec b
        ld a,$1F
        out (c),a
        inc b
        in e,(c)                        ; line LSB
        dec b
        ld a,$1E
        out (c),a
        inc b
        in a,(c)
        cp d
        jr nz,vtick                     ; MSB changed mid-read: try again
        and 1
        ld d,a                          ; DE = video line 0..311
        ld hl,(fps_line)
        ld (fps_line),de
        or a
        sbc hl,de                       ; previous - current
        ret c
        ret z
        ld hl,fps_vframes               ; line went backwards: new frame
        inc (hl)
        ret

; Once per rendered frame, after the flip
fps_tick:
        call vtick
        ld hl,fps_count
        inc (hl)
        ld a,(fps_vframes)
        cp 50
        ret c
        sub 50
        ld (fps_vframes),a
        ld a,(fps_count)
        ld (fps_value),a
        xor a
        ld (fps_count),a
        ; fall through

; Print "nn FPS" at the top left of the ULA screen
fps_draw:
        nextreg $52,10                  ; ULA screen (bank 5) at $4000;
                                        ; map_shadow restores slot 2
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

; A = glyph, E = character column on ULA row 0 (ULA screen paged at $4000)
print_glyph:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,font
        add hl,bc
        ld d,$40
        ld b,8
.l:     ld a,(hl)
        ld (de),a
        inc hl
        inc d                           ; next pixel line of the cell
        djnz .l
        ret

; Clear the ULA screen to paper, white ink, and make paper transparent so
; only the text shows over Layer 2.
ula_init:
        nextreg $52,10
        ld hl,$4000
        ld de,$4001
        ld bc,$1800-1
        ld (hl),0
        ldir                            ; bitmap: all paper
        ld hl,$5800
        ld de,$5801
        ld bc,$300-1
        ld (hl),%01000111               ; bright, paper 0, ink 7
        ldir
        nextreg $43,%00000000           ; edit ULA palette 1
        nextreg $40,16                  ; paper 0
        nextreg $41,$E3                 ; = global transparency colour
        nextreg $40,24                  ; bright paper 0
        nextreg $41,$E3
        jp fps_draw

;------------------------------------------------------------------------------
; Layer 2 double buffering with the hardware shadow register.
;   NextReg $12 = active bank (on screen), NextReg $13 = shadow bank.
; The game always draws into the shadow bank; l2_flip swaps the two during
; vertical blank, so the registers themselves record which buffer is which.
;------------------------------------------------------------------------------

; A = NextReg number -> A = its value
read_nextreg:
        ld bc,$243B
        out (c),a
        inc b
        in a,(c)
        ret

; Page the shadow Layer 2 buffer into $0000-$BFFF for drawing
map_shadow:
        ld a,$13
        call read_nextreg
        jr map_bank

; Show the shadow buffer and make the old active buffer the new shadow
l2_flip:
        ld a,$12
        call read_nextreg
        ld e,a                          ; old active
        ld a,$13
        call read_nextreg
        nextreg $12,a                   ; shadow -> active
        ld a,e
        nextreg $13,a                   ; old active -> shadow
        ret

;------------------------------------------------------------------------------
; Map the 48K Layer 2 buffer starting at 16K bank A into $0000-$BFFF
;------------------------------------------------------------------------------
map_bank:
        add a,a                         ; 8K page
        nextreg $50,a
        inc a
        nextreg $51,a
        inc a
        nextreg $52,a
        inc a
        nextreg $53,a
        inc a
        nextreg $54,a
        inc a
        nextreg $55,a
        ret

;------------------------------------------------------------------------------
; Wait until the raster is outside the display area (line >= 192)
;------------------------------------------------------------------------------
wait_vblank:
        ld bc,$243B
        ld a,$1E
        out (c),a
        inc b
        in a,(c)
        and 1
        ret nz                          ; line >= 256
        dec b
        ld a,$1F
        out (c),a
        inc b
        in a,(c)
        cp 192
        jr c,wait_vblank
        ret

;==============================================================================
; Player input and movement
;==============================================================================
update_player:
        xor a
        out ($FE),a                     ; border back to black
        ; remember position in case we fly into something
        ld hl,cam_x
        ld de,old_pos
        ld bc,8                         ; cam_x(3) cam_z(3) cam_y(2)
        ldir

        ld bc,$FBFE                     ; Q W E R T
        in a,(c)
        cpl
        ld (keys1),a
        ld bc,$FDFE                     ; A S D F G
        in a,(c)
        cpl
        ld (keys2),a

        ; --- speed ---
        ld a,(keys1)
        bit 0,a                         ; Q
        jr z,.nq
        ld a,(speed)
        cp SPEED_MAX
        jr z,.nq
        inc a
        ld (speed),a
.nq:    ld a,(keys2)
        bit 0,a                         ; A
        jr z,.na
        ld a,(speed)
        cp (SPEED_MIN) & $FF
        jr z,.na
        dec a
        ld (speed),a
.na:    ld a,(keys1)
        bit 1,a                         ; W
        jr z,.nw
        xor a
        ld (speed),a
.nw:
        ; --- yaw ---
        ld a,(keys2)
        bit 1,a                         ; S - left
        jr z,.ns
        ld a,(yaw)
        sub YAW_RATE
        ld (yaw),a
.ns:    ld a,(keys2)
        bit 3,a                         ; F - right
        jr z,.nf
        ld a,(yaw)
        add a,YAW_RATE
        ld (yaw),a
.nf:
        ; --- pitch ---
        ld a,(keys1)
        bit 2,a                         ; E - nose down
        jr z,.ne
        ld a,(pitch)
        cp (-PMAX) & $FF
        jr z,.ne
        dec a
        ld (pitch),a
.ne:    ld a,(keys2)
        bit 2,a                         ; D - nose up
        jr z,.nd
        ld a,(pitch)
        cp PMAX
        jr z,.nd
        inc a
        ld (pitch),a
.nd:
        ; --- height ---
        ld a,(keys1)
        bit 4,a                         ; T - up
        jr z,.nt
        ld hl,(cam_y)
        ld de,CLIMB_RATE
        add hl,de
        ld de,MAX_Y
        call min_hl_de
        ld (cam_y),hl
.nt:    ld a,(keys2)
        bit 4,a                         ; G - down
        jr z,.ng
        ld hl,(cam_y)
        ld de,-CLIMB_RATE
        add hl,de
        ld de,MIN_Y
        call max_hl_de
        ld (cam_y),hl
.ng:
        ; --- move along heading: pos += speed * (sin, cos) ---
        ld a,(speed)
        or a
        jr z,.moved
        ld a,(yaw)
        call get_sin
        ex de,hl
        ld a,(speed)
        ld h,a
        ld l,0
        call fmul                       ; HL = speed*sin in 1/256 units
        ld ix,cam_x
        call add_pos
        ld a,(yaw)
        add a,64
        call get_sin
        ex de,hl
        ld a,(speed)
        ld h,a
        ld l,0
        call fmul
        ld ix,cam_z
        call add_pos
.moved:
        call check_collision
        ret z
        ; crashed - restore and stop
        ld hl,old_pos
        ld de,cam_x
        ld bc,8
        ldir
        xor a
        ld (speed),a
        ld a,2
        out ($FE),a                     ; red border flash
        ret

; IX -> 24-bit position (frac, lo, hi). HL = signed delta in 1/256 units.
; Clamps the integer part to WORLD_MIN..WORLD_MAX.
add_pos:
        ld a,h
        rla
        sbc a,a
        ld c,a                          ; sign extension
        ld a,(ix+0)
        add a,l
        ld (ix+0),a
        ld a,(ix+1)
        adc a,h
        ld (ix+1),a
        ld a,(ix+2)
        adc a,c
        ld (ix+2),a
        ld l,(ix+1)
        ld h,(ix+2)
        bit 7,h
        jr nz,.lo
        ld de,WORLD_MIN
        or a
        sbc hl,de
        jr c,.lo
        ld l,(ix+1)
        ld h,(ix+2)
        ld de,WORLD_MAX
        call min_hl_de
        ld (ix+1),l
        ld (ix+2),h
        ret
.lo:    ld (ix+1),WORLD_MIN & $FF
        ld (ix+2),WORLD_MIN >> 8
        ret

; Unsigned 16-bit clamps
min_hl_de:
        push hl
        or a
        sbc hl,de
        pop hl
        ret c
        ex de,hl
        ret
max_hl_de:
        push hl
        or a
        sbc hl,de
        pop hl
        ret nc
        ex de,hl
        ret

; Returns NZ if the camera is inside a building (+margin)
check_collision:
        call cam_cell_ptr
        ld a,(hl)
        or a
        ret z
        ld c,a
        call bld_dims                   ; B = inset, E = size
        ld a,b
        sub COLL_M
        ld d,a                          ; lo bound
        ld a,b
        add a,e
        add a,COLL_M
        ld e,a                          ; hi bound
        ld a,(cam_x+1)
        cp d
        jr c,.no
        cp e
        jr nc,.no
        ld a,(cam_z+1)
        cp d
        jr c,.no
        cp e
        jr nc,.no
        ld a,c
        call bld_height                 ; HL = height
        ld de,COLL_M
        add hl,de
        ld de,(cam_y)
        or a
        sbc hl,de                       ; height+M - camY
        jr c,.no
        jr z,.no
        or 1                            ; NZ
        ret
.no:    xor a
        ret

; HL -> map byte for the cell the camera is in
cam_cell_ptr:
        ld a,(cam_z+2)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(cam_x+2)
        add hl,a
        ld de,city_map
        add hl,de
        ret

; C = map byte -> B = inset, E = size
bld_dims:
        bit 4,c
        jr nz,.t
        ld b,INSET0
        ld e,SIZE0
        ret
.t:     ld b,INSET1
        ld e,SIZE1
        ret

; A = map byte -> HL = height in world units
bld_height:
        and 15
        add a,a
        ld hl,htab
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

;==============================================================================
; Per-frame view setup: trig, rotated building edge vectors, horizon
;==============================================================================
setup_frame:
        ld a,(yaw)
        call get_sin
        ld (sin_y),hl
        ld a,(yaw)
        add a,64
        call get_sin
        ld (cos_y),hl
        ld a,(pitch)
        call get_sin
        ld (sin_p),hl
        ld a,(pitch)
        add a,64
        call get_sin
        ld (cos_p),hl

        ; ground plane relative to camera: dy = -camY
        ld hl,(cam_y)
        call neg_hl
        push hl
        ld de,(cos_p)
        call fmul
        ld (yb),hl                      ; Y contribution of ground
        pop hl
        ld de,(sin_p)
        call fmul
        ld (zb),hl                      ; Z contribution of ground

        ; frustum cull factor c = cosP - 0.75|sinP|
        ld hl,(sin_p)
        call abs_hl
        call z34
        ex de,hl
        ld hl,(cos_p)
        or a
        sbc hl,de
        ld (cull_c),hl

        ld hl,SIZE0
        ld ix,vecs0
        call make_vecs
        ld hl,SIZE1
        ld ix,vecs1
        call make_vecs

        ld a,(cam_x+2)
        ld (cx),a
        ld a,(cam_z+2)
        ld (cz),a

        ld a,(pitch)
        add a,PMAX
        ld hl,hztab
        add hl,a
        ld a,(hl)
        ld (horizon),a
        ret

; A = angle -> HL = sin (S7.8)
get_sin:
        ld l,a
        ld h,high sin_lo
        ld a,(hl)
        inc h
        ld h,(hl)
        ld l,a
        ret

; Rotate the building edge vectors (s,0,0) and (0,0,s) into camera space.
; HL = s, IX -> 16 bytes: VX(X,Y,Z) VZ(X,Y,Z) corner offset (X,Z1)
make_vecs:
        ld (mv_s),hl
        ld de,(cos_y)
        call fmul
        ld (mv_c),hl                    ; s*cosY
        ld hl,(mv_s)
        ld de,(sin_y)
        call fmul
        ld (mv_n),hl                    ; s*sinY
        ; VX = ( s cosY, -s sinY sinP, s sinY cosP )
        ld hl,(mv_c)
        ld (ix+0),l
        ld (ix+1),h
        ld hl,(mv_n)
        ld de,(sin_p)
        call fmul
        call neg_hl
        ld (ix+2),l
        ld (ix+3),h
        ld hl,(mv_n)
        ld de,(cos_p)
        call fmul
        ld (ix+4),l
        ld (ix+5),h
        ; VZ = ( -s sinY, -s cosY sinP, s cosY cosP )
        ld hl,(mv_n)
        call neg_hl
        ld (ix+6),l
        ld (ix+7),h
        ld hl,(mv_c)
        ld de,(sin_p)
        call fmul
        call neg_hl
        ld (ix+8),l
        ld (ix+9),h
        ld hl,(mv_c)
        ld de,(cos_p)
        call fmul
        ld (ix+10),l
        ld (ix+11),h
        ; cell centre -> footprint corner (-s/2,-s/2) in yaw space
        ld hl,(mv_n)
        ld de,(mv_c)
        or a
        sbc hl,de
        sra h
        rr l
        ld (ix+12),l                    ; X: s/2 (sinY - cosY)
        ld (ix+13),h
        ld hl,(mv_n)
        ld de,(mv_c)
        add hl,de
        sra h
        rr l
        call neg_hl
        ld (ix+14),l                    ; Z1: -s/2 (sinY + cosY)
        ld (ix+15),h
        ret

;==============================================================================
; Fixed point maths
;==============================================================================

; HL = -HL
neg_hl:
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; HL = |HL|
abs_hl:
        bit 7,h
        ret z
        jr neg_hl

; fmul: HL = HL * DE >> 8
;   HL = signed 16-bit integer, DE = S7.8 factor in -1.0..+1.0
;   Sign/magnitude using two 8x8 MUL D,E.  Preserves IX, IY.
fmul:
        ld a,h
        xor d
        push af                         ; result sign in bit 7
        bit 7,h
        jr z,.ap
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.ap:    bit 7,d
        jr z,.bp
        xor a
        sub e
        ld e,a
        sbc a,a
        sub d
        ld d,a
.bp:    ld a,d
        or a
        jr nz,.one                      ; |factor| == 1.0
        ld a,e
        ld d,l
        mul d,e                         ; lo * f
        ld c,d
        ld d,h
        ld e,a
        mul d,e                         ; hi * f
        ld a,e
        add a,c
        ld l,a
        ld a,d
        adc a,0
        ld h,a
.one:   pop af
        ret p
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; HL = (HL * DE) >> 16   HL signed, DE unsigned 0.16 fraction
mul_frac:
        ld a,h
        ld (mf_sign),a
        call abs_hl
        ld b,h                          ; ah
        ld c,l                          ; al
        push de
        ld d,c
        mul d,e                         ; al*tl
        ld l,d
        ld h,0
        pop de
        push de
        ld e,d
        ld d,c
        mul d,e                         ; al*th
        add hl,de
        ld a,0
        adc a,a
        pop de
        push de
        ld d,b
        mul d,e                         ; ah*tl
        add hl,de
        adc a,0                         ; A:HL = middle sum
        ld l,h
        ld h,a
        pop de
        ld e,d
        ld d,b
        mul d,e                         ; ah*th
        add hl,de
        ld a,(mf_sign)
        bit 7,a
        ret z
        jp neg_hl

; IX = (HL << 16) / DE   with HL < DE (unsigned) -> 0.16 fraction
div_frac:
        ld ix,0
        ld a,16
.lp:    add ix,ix
        add hl,hl
        jr c,.sub
        or a
        sbc hl,de
        jr nc,.set
        add hl,de
        jr .nx
.sub:   or a
        sbc hl,de
.set:   inc ix
.nx:    dec a
        jr nz,.lp
        ret

; E = A / C, A = A mod C  (8-bit unsigned)
div8:
        ld e,a
        xor a
        ld b,8
.lp:    sla e
        rla
        jr c,.s
        cp c
        jr c,.n
.s:     sub c
        inc e
.n:     djnz .lp
        ret

;==============================================================================
; Perspective projection
;   in : HL -> X,Y,Z (camera space, inside the view frustum, Z > 0)
;   out: A = screen x (0..255), C = screen y (0..191)
;   sx = 128 + 128*X/Z,  sy = 96 - 128*Y/Z   (90 degree horizontal FOV)
;   Z is normalised to 9 bits (256..511) with a barrel shift (count from a
;   log2 table) that is also applied to X and Y, which are then multiplied
;   by a 16-bit reciprocal from rtab.  |X| <= Z keeps Xn within 9 bits.
;==============================================================================
project:
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl                          ; BC = X
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl                          ; DE = Y
        push de
        push bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = Z
        bit 7,h
        jr nz,.z1
        or h
        jr nz,.zok
.z1:    ld hl,1
.zok:   ld a,h
        cp 2
        jr c,.lt512
        ld e,a                          ; Z >= 512: shift right by log2(H)
        ld d,high lgtab
        ld a,(de)
        ld b,a
        ex de,hl
        bsrl de,b
        ex de,hl
        jr .nrm
.lt512: ld b,0
        or a
        jr nz,.nrm                      ; 256..511 already normalised
        ld e,l                          ; Z < 256: shift left by 8-log2(L)
        ld d,high lgtab
        ld a,(de)
        sub 8
        ld c,a                          ; negative shift count
        neg
        ld b,a
        ex de,hl
        bsla de,b
        ex de,hl
        ld b,c
.nrm:   ld a,b                          ; patch shift and reciprocal into
        ld (scale_comp.sh+1),a                  ; scale_comp's immediates
        ld h,high rtab_lo               ; L = Zn - 256
        ld a,(hl)
        ld (scale_comp.rl+1),a
        ld (scale_comp.r16+1),a
        inc h
        ld a,(hl)
        ld (scale_comp.rh+1),a
        ld (scale_comp.r16+2),a

        pop hl                          ; X
        ld a,h
        push af
        call scale_comp
        ld c,a
        pop af
        rla
        jr c,.xn
        ld a,128
        add a,c
        jr nc,.xd
        ld a,255
        jr .xd
.xn:    ld a,128
        sub c
        jr nc,.xd
        xor a
.xd:    ld (pj_sx),a

        pop hl                          ; Y
        ld a,h
        push af
        call scale_comp
        ld c,a
        pop af
        rla
        jr c,.yn
        ld a,96
        sub c
        jr nc,.yd
        xor a
        jr .yd
.yn:    ld a,96
        add a,c
        jr c,.yc
        cp 192
        jr c,.yd
.yc:    ld a,191
.yd:    ld c,a
        ld a,(pj_sx)
        ret

; HL = signed component -> A = round(|HL| * 128 / Z)
; The shift and reciprocal for this Z are patched in by project.
scale_comp:
        bit 7,h
        jr z,.ap
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.ap:
.sh:    ld a,0
        or a
        jr z,.sd
        ex de,hl
        jp m,.l
        ld b,a
        bsrl de,b
        ex de,hl
        jr .sd
.l:     neg
        ld b,a
        bsla de,b
        ex de,hl
.sd:    ld a,h
        cp 2
        jr nc,.big
.ok:    ld b,h                          ; bit 8 of Xn
        ld d,l
.rl:    ld e,0
        mul d,e                         ; Xl*Rl
        ld c,d
        ld d,l
.rh:    ld e,0
        mul d,e                         ; Xl*Rh
        ld a,c
        add a,e
        ld l,a
        ld a,d
        adc a,0
        ld h,a                          ; HL = (Xl*R) >> 8
        ld c,0
        dec b
        jr nz,.nh
.r16:   ld de,0
        add hl,de                       ; + (256*R) >> 8
        rl c
.nh:    inc h                           ; + rounding (0.5 after >>9)
        jr nz,.nr
        inc c
.nr:    ld a,c
        rra
        ld a,h
        rra                             ; A = (C:H) >> 1  = P >> 9
        ret
.big:   ld hl,511                       ; clamp (rounding at frustum edge)
        jr .ok

;==============================================================================
; Outcode: HL -> vertex (X,Y,Z) -> A = bits
;   1 near (Z<NEAR)  2 left (X<-Z)  4 right (X>Z)
;   8 top (Y>0.75Z)  16 bottom (Y<-0.75Z)
;==============================================================================
calc_oc:
        ld e,(hl)
        inc hl
        ld d,(hl)                       ; DE = X
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)                       ; BC = Y
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = Z
        bit 7,h
        jr nz,.nr
        ld a,h
        or a
        ld a,0
        jr nz,.n1
        ld a,l
        cp NEAR
        ld a,0
        jr nc,.n1
.nr:    ld a,1
.n1:    push hl
        add hl,de                       ; Z+X
        bit 7,h
        jr z,.n2
        or 2
.n2:    pop hl
        push hl
        or a
        sbc hl,de                       ; Z-X
        bit 7,h
        jr z,.n3
        or 4
.n3:    pop hl
        ld d,h
        ld e,l
        sra d
        rr e
        sra d
        rr e
        or a
        sbc hl,de                       ; 0.75Z
        push hl
        or a
        sbc hl,bc                       ; 0.75Z-Y
        bit 7,h
        jr z,.n4
        or 8
.n4:    pop hl
        add hl,bc                       ; 0.75Z+Y
        bit 7,h
        ret z
        or 16
        ret

; HL = 0.75 * HL (signed)
z34:
        ld d,h
        ld e,l
        sra d
        rr e
        sra d
        rr e
        or a
        sbc hl,de
        ret

; Signed distance of vertex IX to clip plane (clip_plane bit). >= 0 is inside.
plane_dist:
        ld l,(ix+4)
        ld h,(ix+5)
        ld a,(clip_plane)
        cp 1
        jr nz,.p2
        ld de,-NEAR
        add hl,de
        ret
.p2:    ld e,(ix+0)
        ld d,(ix+1)
        cp 2
        jr nz,.p3
        add hl,de
        ret
.p3:    cp 4
        jr nz,.p4
        or a
        sbc hl,de
        ret
.p4:    push af
        call z34
        pop af
        ld e,(ix+2)
        ld d,(ix+3)
        cp 8
        jr nz,.p5
        or a
        sbc hl,de
        ret
.p5:    add hl,de
        ret

;==============================================================================
; Sutherland-Hodgman clip of clip_src (clip_n verts) against clip_plane into
; clip_dst.  Vertex = X,Y,Z,flag,pad (8 bytes).  flag=1 means the edge from
; this vertex to the next is a real building edge (gets outlined); edges
; created along a clip plane get flag=0 so the screen border isn't outlined.
;==============================================================================
clip_poly:
        ld a,(clip_n)
        dec a
        add a,a
        add a,a
        add a,a
        ld hl,(clip_src)
        add hl,a
        ld (clip_s),hl
        push hl
        pop ix
        call plane_dist
        ld (clip_ds),hl
        ld hl,(clip_src)
        ld (clip_e),hl
        ld iy,(clip_dst)
        xor a
        ld (clip_on),a
        ld a,(clip_n)
        ld (clip_cnt),a
.loop:  ld ix,(clip_e)
        call plane_dist
        ld (clip_de),hl
        bit 7,h
        jr nz,.eout
        ld a,(clip_ds+1)
        bit 7,a
        jr z,.ein
        ; S out, E in: intersection carries S's edge flag
        ld ix,(clip_s)
        ld a,(ix+6)
        ld (clip_if),a
        call clip_isect
.ein:   ld ix,(clip_e)
        ld b,7
.cpy:   ld a,(ix+0)
        ld (iy+0),a
        inc ix
        inc iy
        djnz .cpy
        inc iy
        ld hl,clip_on
        inc (hl)
        jr .next
.eout:  ld a,(clip_ds+1)
        bit 7,a
        jr nz,.next
        ; S in, E out: intersection starts a clip-plane edge
        xor a
        ld (clip_if),a
        call clip_isect
.next:  ld hl,(clip_e)
        ld (clip_s),hl
        ld de,8
        add hl,de
        ld (clip_e),hl
        ld hl,(clip_de)
        ld (clip_ds),hl
        ld hl,clip_cnt
        dec (hl)
        jr nz,.loop
        ld a,(clip_on)
        ld (clip_n),a
        ret

; Output S + t*(E-S) at IY, t = dS/(dS-dE)
clip_isect:
        ld hl,(clip_ds)
        call abs_hl
        ld (ci_a),hl
        ld hl,(clip_de)
        call abs_hl
        ld de,(ci_a)
        add hl,de
        ex de,hl                        ; DE = |dS|+|dE|, HL = |dS|
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.dv
        ld ix,$FFFF
        jr .t
.dv:    call div_frac
.t:     ld (ci_t),ix
        xor a
        call lerp_c
        ld (iy+0),l
        ld (iy+1),h
        ld a,2
        call lerp_c
        ld (iy+2),l
        ld (iy+3),h
        ld a,4
        call lerp_c
        ld (iy+4),l
        ld (iy+5),h
        ; snap the point exactly onto the plane so rounding can't leave a
        ; gap between the polygon and the screen edge
        ld l,(iy+4)
        ld h,(iy+5)                     ; Z
        ld a,(clip_plane)
        cp 1
        jr nz,.s2
        ld (iy+4),NEAR                  ; near:   Z = NEAR
        ld (iy+5),0
        jr .nz
.s2:    cp 2
        jr nz,.s4
        call neg_hl                     ; left:   X = -Z
        jr .sx
.s4:    cp 4
        jr z,.sx                        ; right:  X = Z
        push af
        call z34
        pop af
        cp 8
        jr z,.sy                        ; top:    Y = 0.75Z
        call neg_hl                     ; bottom: Y = -0.75Z
.sy:    ld (iy+2),l
        ld (iy+3),h
        jr .nz
.sx:    ld (iy+0),l
        ld (iy+1),h
.nz:    ld a,(clip_if)
        ld (iy+6),a
        ld bc,8
        add iy,bc
        ld hl,clip_on
        inc (hl)
        ret

; A = coordinate offset -> HL = S.c + (E.c - S.c) * t
lerp_c:
        ld hl,(clip_e)
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(clip_s)
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        ex de,hl
        or a
        sbc hl,de
        ld de,(ci_t)
        call mul_frac
        pop de
        add hl,de
        ret

;==============================================================================
; Draw one face of the current building
;   HL -> 4 vertex offsets into vtx[] (index*16), df_mask = edges to outline
;   (bit k = edge from corner k to corner k+1)
;==============================================================================
draw_face:
        ld (df_ptr),hl
        ld bc,$FF00                     ; B = AND of outcodes, C = OR
        ld d,high vtx
        REPT 4
        ld a,(hl)
        inc hl
        add a,6
        ld e,a
        ld a,(de)
        ld e,a
        and b
        ld b,a
        ld a,e
        or c
        ld c,a
        ENDR
        ld a,b
        or a
        ret nz                          ; wholly outside one plane
        ld a,c
        or a
        jr nz,.clip

        ; fast path - every corner on screen, use cached projections
        ld hl,(df_ptr)
        ld de,p2buf
        ld b,high vtx
        FACEVTX 1
        FACEVTX 2
        FACEVTX 4
        FACEVTX 8
        ld a,4
        ld (p2n),a
        jp .render

.clip:  ld (df_or),a
        ld a,(df_mask)
        ld (df_m),a
        ld hl,(df_ptr)
        ld iy,clipA
        ld b,4
.cp:    ld a,(hl)
        inc hl
        ld ixl,a
        ld a,high vtx
        ld ixh,a
        ld c,6
.cpb:   ld a,(ix+0)
        ld (iy+0),a
        inc ix
        inc iy
        dec c
        jr nz,.cpb
        ld a,(df_m)
        ld e,a
        and 1
        ld (iy+0),a                     ; edge flag from mask
        ld a,e
        rrca
        ld (df_m),a
        inc iy
        inc iy
        djnz .cp
        ld a,4
        ld (clip_n),a
        ld hl,clipA
        ld (clip_src),hl
        ld hl,clipB
        ld (clip_dst),hl
        ld a,1
.pl:    ld (clip_plane),a
        ld hl,df_or
        and (hl)
        jr z,.skip
        call clip_poly
        ld a,(clip_n)
        cp 3
        ret c
        ld hl,(clip_src)
        ld de,(clip_dst)
        ld (clip_src),de
        ld (clip_dst),hl
.skip:  ld a,(clip_plane)
        add a,a
        cp 32
        jr nz,.pl

        ld ix,(clip_src)
        ld iy,p2buf
        ld a,(clip_n)
        ld (p2n),a
        ld b,a
.pj:    push bc
        push ix
        pop hl
        call project
        ld (iy+0),a
        ld (iy+1),c
        ld a,(ix+6)
        ld (iy+2),a
        ld bc,8
        add ix,bc
        ld bc,4
        add iy,bc
        pop bc
        djnz .pj

.render:
        ; close the polygon: copy vertex 0 after the last
        ld a,(p2n)
        add a,a
        add a,a
        ld hl,p2buf
        add hl,a
        ld a,(p2buf)
        ld (hl),a
        inc hl
        ld a,(p2buf+1)
        ld (hl),a
    IFDEF DRAW_LINES
        call fill_poly
        ld a,EDGE_COL
        ld (line_col),a
        jp outline_poly
    ELSE
        jp fill_poly                    ; solid faces only
    ENDIF

;==============================================================================
; Convex polygon fill from p2buf (8-bit screen coords).
;   Each edge is walked with an exact integer DDA into one of two x tables:
;   downward edges -> TA, upward edges -> TB.  For a convex polygon every row
;   then has one entry in each, and the span between them is filled.
;   Winding doesn't matter.
;==============================================================================
fill_poly:
        ld a,(p2n)
        ld b,a
        ld hl,p2buf+1
        ld c,255
        ld d,0
.mm:    ld a,(hl)
        cp c
        jr nc,.m1
        ld c,a
.m1:    cp d
        jr c,.m2
        ld d,a
.m2:    inc hl
        inc hl
        inc hl
        inc hl
        djnz .mm
        ld a,c
        cp d
        ret z                           ; zero height - outline only
        ld (fy0),a
        ld a,d
        ld (fy1),a

        ld ix,p2buf
        ld a,(p2n)
        ld (fe_cnt),a
.ed:    ld d,(ix+0)
        ld e,(ix+1)
        ld b,(ix+4)
        ld c,(ix+5)
        ld a,e
        cp c
        jr z,.nx                        ; horizontal edge
        jr c,.down
        ld a,d                          ; going up: swap ends, use TB
        ld d,b
        ld b,a
        ld a,e
        ld e,c
        ld c,a
        ld a,high TB
        jr .walk
.down:  ld a,high TA
.walk:  push ix
        call walk_edge
        pop ix
.nx:    ld bc,4
        add ix,bc
        ld hl,fe_cnt
        dec (hl)
        jr nz,.ed

        ld a,(face_col)                 ; shaded colour of this face
        ld (l2_cls_byte),a              ; DMA source byte for long spans
        ld d,a
        ld e,a                          ; PUSH pair for short spans
        jp fill_spans

; Walk an edge (D=xa, E=ya) -> (B=xb, C=yb), yb > ya, into table page A.
; Bresenham style: x += q each row, fractional r/dy accumulated in a biased
; byte (carry == wrap), so the end point is hit exactly.
walk_edge:
        ld h,a
        ld l,e
        ld a,c
        sub e
        ld c,a                          ; C = dy (1..191)
        ld a,b
        sub d                           ; dx
        jr c,.neg
        cp c
        jr nc,.pdv
        ld ixl,a                        ; steep: q = 0, r = dx
        call .setup
        jr .p0
.pdv:   call div8                       ; E = q, A = r
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.p0
.pl:    ld (hl),d
        inc l
        ld a,d
        add a,ixh
        ld d,a
        ld a,e
        add a,ixl
        jr nc,.pl1
        add a,c
        inc d
.pl1:   ld e,a
        djnz .pl
        ret
.p0:    ld (hl),d
        inc l
        ld a,e
        add a,ixl
        jr nc,.p01
        add a,c
        inc d
.p01:   ld e,a
        djnz .p0
        ret

.neg:   neg
        cp c
        jr nc,.ndv
        ld ixl,a
        call .setup
        jr .n0
.ndv:   call div8
        ld ixh,e
        ld ixl,a
        call .setup
        ld a,ixh
        or a
        jr z,.n0
.nl:    ld (hl),d
        inc l
        ld a,d
        sub ixh
        ld d,a
        ld a,e
        add a,ixl
        jr nc,.nl1
        add a,c
        dec d
.nl1:   ld e,a
        djnz .nl
        ret
.n0:    ld (hl),d
        inc l
        ld a,e
        add a,ixl
        jr nc,.n01
        add a,c
        dec d
.n01:   ld e,a
        djnz .n0
        ret

; B = dy+1 rows, E = biased accumulator (dy/2 - dy), C = -dy
.setup: ld b,c
        inc b
        ld a,c
        srl a
        sub c
        ld e,a
        ld a,c
        neg
        ld c,a
        ret

;==============================================================================
; Span filler.  Rows fy0..fy1, x from TA/TB.  DE = colour pair.
; Short spans use the stack pointer as a 2-byte write pointer into the frame
; buffer (interrupts are disabled), jumping into an unrolled block of PUSH DE.
; Spans of DMA_SPAN_MIN pixels or more are written by the zxnDMA, which only
; needs its length and destination reloaded (see clear_screen).
;==============================================================================
fill_spans:
        ld (saved_sp),sp
        ld a,(fy0)
        ld b,a
        ld a,(fy1)
        ld ixl,a
fs_loop:
        ld h,high TA
        ld l,b
        ld a,(hl)
        inc h
        ld c,(hl)
        cp c
        jr c,.ord
        ld l,c
        ld c,a
        ld a,l
.ord:   ld l,a                          ; A = left x, C = right x
        ld h,b
        ld a,c
        sub l                           ; width-1
        cp DMA_SPAN_MIN-1
        jr nc,.dma
.push:  srl a
        jr c,.even
        ld (hl),e                       ; odd width: single pixel first
        jr .go
.even:  inc a
.go:    ld l,c
        inc hl                          ; one past right edge (may be $C000)
        ld sp,hl
        ld l,a
        ld a,low push_end
        sub l
        ld l,a
        ld h,high push_end
        jp (hl)

        ; Long span: zxnDMA from the fixed colour byte (port A) to HL.
        ; Everything but length and destination was set up by clear_screen.
.dma:   inc a
        jr z,.push                      ; 256 wide: length needs the high byte
        ld c,a
        ld a,DMA_WR0_LEN_LO
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,c
        out (IO_DATAGEAR_DMA_PORT),a    ; length = width
        ld a,DMA_WR4_CONT_MODE
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,l
        out (IO_DATAGEAR_DMA_PORT),a    ; port B = y*256 + x
        ld a,h
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,DMA_LOAD
        out (IO_DATAGEAR_DMA_PORT),a
        ld a,DMA_ENABLE
        out (IO_DATAGEAR_DMA_PORT),a    ; CPU waits until the span is written
        jp push_end

;==============================================================================
; Outline the polygon in p2buf, skipping edges flagged 0 (clip edges)
;==============================================================================
outline_poly:
        ld ix,p2buf
        ld a,(p2n)
        ld b,a
.lp:    push bc
        ld a,(ix+2)
        or a
        jr z,.sk
        ld l,(ix+0)
        ld h,(ix+1)
        ld e,(ix+4)
        ld d,(ix+5)
        call draw_line
.sk:    ld bc,4
        add ix,bc
        pop bc
        djnz .lp
        ret

;==============================================================================
; Bresenham line, on-screen 8-bit coordinates.
;   L = x0, H = y0, E = x1, D = y1, colour in line_col.  Preserves IX, IY.
;==============================================================================
draw_line:
        ld a,(line_col)
        ld c,a
        ld a,e
        sub l
        jr nc,.xp
        neg
        ld b,OP_DEC_L
        jr .xd
.xp:    ld b,OP_INC_L
.xd:    ld e,a                          ; |dx|
        ld a,b
        ld (.smx1),a
        ld (.smx2),a
        ld a,d
        sub h
        jr nc,.yp
        neg
        ld b,OP_DEC_H
        jr .yd
.yp:    ld b,OP_INC_H
.yd:    ld d,a                          ; |dy|
        ld a,b
        ld (.smy1),a
        ld (.smy2),a
        ld a,e
        cp d
        jr c,.ymaj
        ld b,e
        inc b
        srl a
.xl:    ld (hl),c
.smx1:  inc l
        sub d
        jr nc,.xs
.smy1:  inc h
        add a,e
.xs:    djnz .xl
        ret
.ymaj:  ld b,d
        inc b
        ld a,d
        srl a
.yl:    ld (hl),c
.smy2:  inc h
        sub e
        jr nc,.ys
.smx2:  inc l
        add a,d
.ys:    djnz .yl
        ret

;==============================================================================
; Clear the back buffer with the zxnDMA: sky above the horizon row, ground
; below.  Two fills reuse the l2_fill command block from layer2_cls.asm,
; patching its destination (port B) and length; the source (port A) is the
; fixed byte l2_cls_byte.  A zero-length fill is skipped.
;==============================================================================
clear_screen:
        ld a,(horizon)
        or a
        jr z,.ground                    ; no sky rows
        ld b,a                          ; sky: $0000, horizon*256 bytes
        ld c,0
        ld hl,0
        ld a,SKY_COL
        call dma_fill
.ground:
        ld a,(horizon)
        cp 192
        jr z,.spans                     ; no ground rows
        ld h,a                          ; ground: horizon*256 .. $BFFF
        ld l,0
        ld b,a
        ld a,192
        sub b
        ld b,a
        ld c,0
        ld a,GROUND_COL
        call dma_fill
        ; Leave the DMA ready for fill_spans: length high byte 0, so each span
        ; only reloads length low, destination, LOAD and ENABLE.  fill_poly
        ; puts each building's colour in the source byte l2_cls_byte.
.spans: ld a,DMA_WR0_LEN_HI
        out (IO_DATAGEAR_DMA_PORT),a
        xor a
        out (IO_DATAGEAR_DMA_PORT),a
        ret

; DMA fill: HL = destination, BC = length (non-zero), A = colour
dma_fill:
        ld (l2_cls_byte),a
        ld (l2_fill_bstrt),hl
        ld (l2_fill_length),bc
        ld hl,l2_fill
        ld b,l2_fill_cmd_len
        ld c,IO_DATAGEAR_DMA_PORT
        otir                            ; CPU waits while the DMA runs
        ret

;==============================================================================
; City traversal - back to front without sorting.
;   For grid-aligned boxes in separate cells, a box can only hide boxes whose
;   cell offsets from the camera cell are larger (or equal) on both axes in
;   the same quadrant.  So: rows from the far edges inwards, and within each
;   row columns from the far edges inwards, the camera row/column last.
;==============================================================================
draw_city:
        ld a,(cz)
        sub VIEW_R
        ld (cell_j),a
.b:     ld a,(cell_j)
        ld hl,cz
        cp (hl)
        jr z,.f
        call draw_row
        ld hl,cell_j
        inc (hl)
        jr .b
.f:     ld a,(cz)
        add a,VIEW_R
        ld (cell_j),a
.f2:    ld a,(cell_j)
        ld hl,cz
        cp (hl)
        jr z,draw_row                   ; camera row last
        call draw_row
        ld hl,cell_j
        dec (hl)
        jr .f2

draw_row:
        ld a,(cell_j)
        cp 32
        ret nc
        ld a,(cx)
        sub VIEW_R
        ld (cell_i),a
        call row_start
.l:     ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jr z,.r
        call try_cell
        ld hl,cell_i
        inc (hl)
        ld hl,(row_x)                   ; one cell +x: (X,Z1) += (cosY,sinY)
        ld de,(cos_y)
        add hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        add hl,de
        ld (row_z1),hl
        jr .l
.r:     ld a,(cx)
        add a,VIEW_R
        ld (cell_i),a
        call row_start
.r2:    ld a,(cell_i)
        ld hl,cx
        cp (hl)
        jr z,try_cell                   ; camera column last
        call try_cell
        ld hl,cell_i
        dec (hl)
        ld hl,(row_x)                   ; one cell -x
        ld de,(cos_y)
        or a
        sbc hl,de
        ld (row_x),hl
        ld hl,(row_z1)
        ld de,(sin_y)
        or a
        sbc hl,de
        ld (row_z1),hl
        jr .r2

; Yaw-rotated centre of cell (cell_i, cell_j) -> row_x, row_z1.  Moving one
; cell (256 units) in x then changes (X, Z1) by exactly the raw (cosY, sinY).
row_start:
        ld a,(cell_i)
        ld h,a
        ld l,128
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld a,(cell_j)
        ld h,a
        ld l,128
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (row_x),hl
        ld hl,(t_z1)
        ld (row_z1),hl
        ret

try_cell:
        ld a,(cell_i)
        cp 32
        ret nc
        call vtick                      ; keep the FPS clock sampling
        ; fall through

;------------------------------------------------------------------------------
; Transform and draw the building in (cell_i, cell_j)
;------------------------------------------------------------------------------
draw_cell:
        ld a,(cell_j)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(cell_i)
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(hl)
        or a
        ret z
        ld c,a
        inc h
        inc h
        inc h
        inc h                           ; +1024 -> city_col
        ld a,(hl)
        and %11111100
        ld (bld_col),a                  ; colour family (shade bits clear)
        ld a,c
        call bld_height
        ld (bld_h),hl
        call bld_dims                   ; B = inset, E = size
        ; world corners
        ld a,(cell_i)
        ld h,a
        ld l,b
        ld (bld_x0),hl
        ld a,e
        add hl,a
        ld (bld_x1),hl
        ld a,(cell_j)
        ld h,a
        ld l,b
        ld (bld_z0),hl
        ld a,e
        add hl,a
        ld (bld_z1),hl

        ld hl,vecs0
        ld de,177                       ; block radius 125 * sqrt2
        bit 4,c
        jr z,.v0
        ld hl,vecs1
        ld de,96                        ; tower radius 68 * sqrt2
.v0:    ld (bld_vecs),hl
        ld (bld_r),de

        ; yaw-space centre of this cell, kept up to date by draw_row
        ld hl,(row_z1)
        ld (t_z1),hl
        ld hl,(row_x)
        ld (t_x),hl
        ; Horizontal frustum cull, valid at any pitch: a visible point has
        ; |X|*c <= Z1 with c = cosP - 0.75|sinP|. Reject the bounding circle.
        call abs_hl
        ld de,(cull_c)
        call fmul
        ld de,(t_z1)
        or a
        sbc hl,de
        ld de,(bld_r)
        or a
        sbc hl,de
        ret p
        ; centre -> corner (x0,z0), still in yaw space
        ld ix,(bld_vecs)
        ld l,(ix+12)
        ld h,(ix+13)
        ld de,(t_x)
        add hl,de
        ld (vtx+0),hl
        ld l,(ix+14)
        ld h,(ix+15)
        ld de,(t_z1)
        add hl,de
        ld (t_z1),hl
        call rot_pitch
        ld (vtx+2),hl
        ld (vtx+4),de
        ld hl,(bld_vecs)
        ld de,cur_vx
        ld bc,12
        ldir                            ; cur_vx, cur_vz

        ; vertical edge vector (0, h cosP, h sinP)
        ld hl,(bld_h)
        ld de,(cos_p)
        call fmul
        ld (vy_vec+2),hl
        ld hl,(bld_h)
        ld de,(sin_p)
        call fmul
        ld (vy_vec+4),hl

        ; vertices: index = x + 2*z + 4*top  (box edges are shared vectors)
        VADD vtx+16, vtx+0,  cur_vx
        VADD vtx+32, vtx+0,  cur_vz
        VADD vtx+48, vtx+16, cur_vz
        VADD vtx+64, vtx+0,  vy_vec
        VADD vtx+80, vtx+16, vy_vec
        VADD vtx+96, vtx+32, vy_vec
        VADD vtx+112,vtx+48, vy_vec

        ; Back face culling is exact in world space for an axis aligned box.
        ; C = visible faces: bit0 -X, bit1 +X, bit2 -Z, bit3 +Z, bit4 top
        ld c,0
        ld hl,(cam_x+1)
        ld de,(bld_x0)
        or a
        sbc hl,de
        jr nc,.v1
        set 0,c
.v1:    ld hl,(bld_x1)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        jr nc,.v2
        set 1,c
.v2:    ld hl,(cam_z+1)
        ld de,(bld_z0)
        or a
        sbc hl,de
        jr nc,.v3
        set 2,c
.v3:    ld hl,(bld_z1)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        jr nc,.v4
        set 3,c
.v4:    ld hl,(bld_h)
        ld de,(cam_y)
        or a
        sbc hl,de
        jr nc,.v5
        set 4,c
.v5:    ld a,c
        ld (bld_vis),a
        or a
        ret z                           ; camera inside the footprint
        ld hl,used_tab
        add hl,a
        ld a,(hl)
        ld (bld_used),a                 ; corners belonging to visible faces

        ; outcodes, trivial reject, project the on-screen corners
        ld a,$FF
        ld (and_oc),a
        ld ix,vtx
        ld b,8
.ocl:   push bc
        ld a,(bld_used)
        rrca
        ld (bld_used),a
        jr nc,.np                       ; hidden corner: not needed
        push ix
        pop hl
        call calc_oc
        ld (ix+6),a                     ; outcode
        ld hl,and_oc
        and (hl)
        ld (hl),a
        ld a,(ix+6)
        or a
        jr nz,.np
        push ix
        pop hl
        call project
        ld (ix+7),a                     ; sx
        ld (ix+8),c                     ; sy
.np:    ld de,16
        add ix,de
        pop bc
        djnz .ocl
        ld a,(and_oc)
        or a
        ret nz

        ; Shading: the roof is lighter; of the visible sides, the one the
        ; camera sees most squarely (furthest from its plane) is the base
        ; colour and the other is darker.
        ld a,(bld_col)
        or SHADE_ROOF
        ld (col_top),a
        ld a,(bld_col)
        or SHADE_FACE
        ld (col_x),a
        ld (col_z),a
        ld a,(bld_vis)
        and %00000011
        jr z,.shd                       ; only a Z side (or none)
        ld a,(bld_vis)
        and %00001100
        jr z,.shd                       ; only an X side
        ; both an X and a Z side: compare camera distances to the planes
        ld hl,(bld_x0)
        ld de,(cam_x+1)
        or a
        sbc hl,de                       ; x0 - camX  (> 0 when -X visible)
        ld a,(bld_vis)
        rra
        jr c,.dx
        ld hl,(cam_x+1)
        ld de,(bld_x1)
        or a
        sbc hl,de                       ; camX - x1
.dx:    push hl
        ld hl,(bld_z0)
        ld de,(cam_z+1)
        or a
        sbc hl,de                       ; z0 - camZ
        ld a,(bld_vis)
        bit 2,a
        jr nz,.dz
        ld hl,(cam_z+1)
        ld de,(bld_z1)
        or a
        sbc hl,de                       ; camZ - z1
.dz:    pop de                          ; DE = X distance, HL = Z distance
        or a
        sbc hl,de
        ld a,(bld_col)                  ; SHADE_DARK = 0
        jr c,.zdark                     ; Z side is further round: darker
        ld (col_x),a
        jr .shd
.zdark: ld (col_z),a
.shd:   ld a,(bld_vis)
        ld c,a
        ; An edge shared with a face drawn later is left to that face:
        ; X faces skip their top edge if the roof shows and the vertical
        ; edge shared with a visible Z face; Z faces skip the top edge.
        ld b,$0F
        bit 4,c
        jr z,.m1
        res 2,b
.m1:    ld a,b
        ld (bld_mz),a
        bit 3,c
        jr z,.m2
        res 1,b
.m2:    bit 2,c
        jr z,.m3
        res 3,b
.m3:    ld a,b
        ld (bld_mx),a

        ld a,(bld_vis)
        bit 0,a
        jr z,.f1
        ld a,(bld_mx)
        ld (df_mask),a
        ld a,(col_x)
        ld (face_col),a
        ld hl,face_nx
        call draw_face
.f1:    ld a,(bld_vis)
        bit 1,a
        jr z,.f2
        ld a,(bld_mx)
        ld (df_mask),a
        ld a,(col_x)
        ld (face_col),a
        ld hl,face_px
        call draw_face
.f2:    ld a,(bld_vis)
        bit 2,a
        jr z,.f3
        ld a,(bld_mz)
        ld (df_mask),a
        ld a,(col_z)
        ld (face_col),a
        ld hl,face_nz
        call draw_face
.f3:    ld a,(bld_vis)
        bit 3,a
        jr z,.f4
        ld a,(bld_mz)
        ld (df_mask),a
        ld a,(col_z)
        ld (face_col),a
        ld hl,face_pz
        call draw_face
.f4:    ld a,(bld_vis)
        bit 4,a
        ret z
        ld a,$0F
        ld (df_mask),a
        ld a,(col_top)
        ld (face_col),a
        ld hl,face_top
        jp draw_face

; Yaw rotation of (t_dx, t_dz):  Z1 = dx sinY + dz cosY -> t_z1
;                               X  = dx cosY - dz sinY -> HL
rot_yaw:
        ld hl,(t_dx)
        ld de,(sin_y)
        call fmul
        push hl
        ld hl,(t_dz)
        ld de,(cos_y)
        call fmul
        pop de
        add hl,de
        ld (t_z1),hl
        ld hl,(t_dz)
        ld de,(sin_y)
        call fmul
        push hl
        ld hl,(t_dx)
        ld de,(cos_y)
        call fmul
        pop de
        or a
        sbc hl,de
        ret

; Pitch rotation of a ground point at t_z1:
;   HL = Y = yb - Z1 sinP     DE = Z = zb + Z1 cosP
rot_pitch:
        ld hl,(t_z1)
        ld de,(sin_p)
        call fmul
        ex de,hl
        ld hl,(yb)
        or a
        sbc hl,de
        push hl
        ld hl,(t_z1)
        ld de,(cos_p)
        call fmul
        ld de,(zb)
        add hl,de
        ex de,hl
        pop hl
        ret

;==============================================================================
; Street intersection markers - one dot per grid corner near the camera
;==============================================================================
draw_dots:
        ld a,(cz)
        sub DOT_R
        ld (dot_j),a
        ld a,2*DOT_R+2
        ld (dot_rows),a
.row:   ld a,(dot_j)
        cp 33
        jr nc,.nrow
        ; first corner of the row by full rotation, then step along x:
        ; +256 world units in x adds exactly (cosY, sinY) to (X, Z1)
        ld a,(cx)
        sub DOT_R
        ld (dot_i),a
        ld h,a
        ld l,0
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld a,(dot_j)
        ld h,a
        ld l,0
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (t_x),hl
        ld a,2*DOT_R+2
        ld (dot_cols),a
.col:   ld a,(dot_i)
        cp 33
        call c,plot_dot
        ld hl,(t_x)
        ld de,(cos_y)
        add hl,de
        ld (t_x),hl
        ld hl,(t_z1)
        ld de,(sin_y)
        add hl,de
        ld (t_z1),hl
        ld hl,dot_i
        inc (hl)
        ld hl,dot_cols
        dec (hl)
        jr nz,.col
.nrow:  ld hl,dot_j
        inc (hl)
        ld hl,dot_rows
        dec (hl)
        jr nz,.row
        ret

; Plot the ground point (t_x, t_z1)
plot_dot:
        ld hl,(t_x)
        ld (tmpv+0),hl
        call abs_hl
        ld de,(cull_c)
        call fmul
        ld de,(t_z1)
        or a
        sbc hl,de
        ret p                           ; outside horizontal frustum / behind
        call rot_pitch
        ld (tmpv+2),hl
        ld (tmpv+4),de
        ld hl,tmpv
        call calc_oc
        or a
        ret nz
        ld hl,tmpv
        call project
        ld h,c
        ld l,a
        ld (hl),DOT_COL
        ret

;==============================================================================
; HUD: gunsight, speed bar (bottom left), altitude bar (right)
;==============================================================================
draw_hud:
        ld a,HUD_COL
        ld (line_col),a
        ld hl,96*256+122
        ld de,96*256+125
        call draw_line
        ld hl,96*256+131
        ld de,96*256+134
        call draw_line
        ld hl,90*256+128
        ld de,93*256+128
        call draw_line
        ld hl,99*256+128
        ld de,102*256+128
        call draw_line

        ; speed
        ld a,(speed)
        or a
        jr z,.alt
        ld c,HUD_COL
        bit 7,a
        jr z,.sp
        neg
        ld c,HUD_WARN
.sp:    add a,a
        add a,8
        ld e,a
        ld a,c
        ld (line_col),a
        push de
        ld hl,186*256+8
        ld d,186
        call draw_line
        pop de
        ld hl,187*256+8
        ld d,187
        call draw_line

        ; altitude: 1 pixel per 8 units
.alt:   ld a,HUD_COL
        ld (line_col),a
        ld hl,(cam_y)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,186
        sub l
        ld d,a
        push de
        ld e,248
        ld hl,186*256+248
        call draw_line
        pop de
        ld e,249
        ld hl,186*256+249
        jp draw_line

;==============================================================================
; Data
;==============================================================================
; Faces as vertex offsets (index*16); vertex index = x + 2*z + 4*top.
; Side faces list bottom edge first, then the z1/x1 vertical, top, z0/x0.
face_nx:  db 0*16,2*16,6*16,4*16
face_px:  db 1*16,3*16,7*16,5*16
face_nz:  db 0*16,1*16,5*16,4*16
face_pz:  db 2*16,3*16,7*16,6*16
face_top: db 4*16,5*16,7*16,6*16

; --- player state ---
cam_x:      db 0, $80, $08              ; frac, integer lo, hi  (x = 2176)
cam_z:      db 0, $80, $03              ; z = 896, on boulevard x=8
cam_y:      dw 100
old_pos:    ds 8
yaw:        db 0
pitch:      db 0
speed:      db 0
keys1:      db 0
keys2:      db 0

horizon:    db 96

; --- view ---
sin_y:      dw 0
cos_y:      dw 0
sin_p:      dw 0
cos_p:      dw 0
yb:         dw 0
zb:         dw 0
vecs0:      ds 16
vecs1:      ds 16
cur_vx:     ds 6
cur_vz:     ds 6
cull_c:     dw 0
vy_vec:     dw 0,0,0
mv_s:       dw 0
mv_c:       dw 0
mv_n:       dw 0

; --- building ---
cx:         db 0
cz:         db 0
cell_i:     db 0
cell_j:     db 0
bld_h:      dw 0
bld_col:    db 0
col_x:      db 0
col_z:      db 0
col_top:    db 0
face_col:   db 0
bld_vecs:   dw 0
bld_x0:     dw 0
bld_x1:     dw 0
bld_z0:     dw 0
bld_z1:     dw 0
t_dx:       dw 0
t_dz:       dw 0
t_z1:       dw 0
t_x:        dw 0
row_x:      dw 0
row_z1:     dw 0
bld_used:   db 0
bld_r:      dw 0
and_oc:     db 0
dot_i:      db 0
dot_j:      db 0
dot_rows:   db 0
dot_cols:   db 0
tmpv:       ds 8

; --- projection ---
pj_x:       dw 0
pj_y:       dw 0
pj_sh:      db 0
pj_r:       dw 0
pj_sx:      db 0
mf_sign:    db 0

; --- clipping ---
df_ptr:     dw 0
df_or:      db 0
df_mask:    db 0
df_m:       db 0
bld_vis:    db 0
bld_mx:     db 0
bld_mz:     db 0
clip_n:     db 0
clip_on:    db 0
clip_cnt:   db 0
clip_plane: db 0
clip_src:   dw 0
clip_dst:   dw 0
clip_s:     dw 0
clip_e:     dw 0
clip_ds:    dw 0
clip_de:    dw 0
clip_if:    db 0
ci_a:       dw 0
ci_t:       dw 0
clipA:      ds 8*12
clipB:      ds 8*12

; --- polygon ---
p2n:        db 0
fy0:        db 0
fy1:        db 0
fe_cnt:     db 0
line_col:   db 0
saved_sp:   dw 0

; --- fps ---
fps_line:   dw 0
fps_vframes: db 0
fps_count:  db 0
fps_value:  db 0

; 8x8 glyphs: digits 0-9, then F, P, S, space
GLYPH_F     equ 10
GLYPH_P     equ 11
GLYPH_S     equ 12
GLYPH_SPACE equ 13
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

;------------------------------------------------------------------------------
; Page aligned blocks
;------------------------------------------------------------------------------
        ALIGN 256
vtx:        ds 8*16                     ; X,Y,Z,oc,sx,sy + pad
p2buf:      ds 4*16                     ; x,y,edge flag,pad

        ALIGN 256
; Unrolled span writer: entry = push_end - pairs
push_blk:
        REPT 128
        push de
        ENDR
push_end:
        ld a,b
        inc b
        cp ixl
        jp nz,fs_loop
        ld sp,(saved_sp)
        ret

        ALIGN 256
TA:         ds 256                      ; x of downward edges per row
TB:         ds 256                      ; x of upward edges per row

        INCLUDE "layer2_cls.asm"         ; zxnDMA equates + fill command block

        INCLUDE "tables.inc"

            ds 256
stack_top:

        DISPLAY "Code+data end: ",/A,$
        ASSERT $ <= $10000
        ASSERT city_col == city_map + 1024   ; draw_cell reaches colours via +1024

;------------------------------------------------------------------------------
        SAVENEX OPEN "zpolice.nex", start, stack_top
        SAVENEX CORE 3,0,0
        SAVENEX CFG 0
        SAVENEX AUTO
        SAVENEX CLOSE
