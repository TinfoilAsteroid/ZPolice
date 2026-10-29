;==============================================================================
; Z-POLICE - HUD sprites (in the sprites page, PAGE_SPRITES, at $E000 in slot
; 7): the human status column and the compass bar, as hardware sprites on
; the 320 x 256 sprite screen.  hud_sprites sets both and sends the sprite
; table to the hardware; main_loop calls it once a frame, after the flip.
;
; Sprites used: 0..HUMAN_MAX-1 the humans, CSPR_SPR0.. the compass bar's
; marks, CSPR_PTR_SPR its pointer.
;==============================================================================

hud_sprites:
        call hum_hud
        call compass_spr
        jp spr_update

;------------------------------------------------------------------------------
; The compass bar, across the top of the screen in the top border (sprite
; row COMP_SPR_Y): a tape of marks every 16 yaw units (22.5 degrees), at 2
; pixels a yaw unit, centred on the heading at sprite x COMP_SPR_CX, across
; the full 320-pixel width of the sprite screen: 225 degrees (+-COMP_HALF,
; 80 yaw units).  Marks at the very edges are half off the screen (their x
; wraps, as sprite x does).  The letters N,
; E, S, W (red) at 0, 64, 128, 192; a yellow dot at the 45 degree points;
; a small white dot between.  A white pointer under the bar's middle marks
; the heading.  Turning right (yaw up) moves the marks left.
;------------------------------------------------------------------------------
CSPR_SPR0       equ HUMAN_MAX       ; first compass mark sprite (20)
COMP_HALF       equ 80              ; yaw units shown either side: 160 px
CSPR_MARKS      equ 2*COMP_HALF/16+1    ; most marks in view at once (11)
CSPR_PTR_SPR    equ CSPR_SPR0+CSPR_MARKS   ; the pointer's sprite
COMP_SPR_Y      equ 8               ; the bar's sprite row
COMP_PTR_Y      equ COMP_SPR_Y+SPR_SIZE    ; the pointer, under it
COMP_SPR_CX     equ 160             ; the heading's x: the screen's middle
COMP_SPR_X0     equ COMP_SPR_CX-2*COMP_HALF-SPR_SIZE/2  ; x of a mark =
                                    ; this + 2 * (COMP_HALF + mark - yaw)
        ASSERT CSPR_PTR_SPR < SPR_COUNT
        ASSERT CSPR_E == CSPR_N+1 && CSPR_S == CSPR_N+2 && CSPR_W == CSPR_N+3

compass_spr:
        ld a,CSPR_SPR0
        ld (cs_spr),a
        ld c,0                          ; mark k, at yaw k * 16
.lp:    push bc
        ld a,c
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,yaw
        sub (hl)                        ; mark - yaw, signed
        add a,COMP_HALF
        cp 2*COMP_HALF+1
        jr nc,.nx                       ; off the bar: not shown
        ld l,a                          ; x = COMP_SPR_X0 + 2 * that
        ld h,0
        add hl,hl
        ld de,COMP_SPR_X0
        add hl,de
        push hl
        ld a,c                          ; which mark: a letter every 64,
        and 3                           ; a dot every 32, else a tick
        ld a,c
        jr nz,.nl
        rrca
        rrca
        and 3
        add a,CSPR_N
        jr .pat
.nl:    and 1
        ld a,CSPR_DOT
        jr z,.pat
        ld a,CSPR_TICK
.pat:   ld h,a
        ld l,0
        pop bc                          ; BC = x
        ld de,COMP_SPR_Y
        ld a,(cs_spr)
        call spr_set
        ld hl,cs_spr
        inc (hl)
.nx:    pop bc
        inc c
        ld a,c
        cp 16
        jr nz,.lp
        ld a,(cs_spr)                   ; hide the mark sprites not used
.hd:    cp CSPR_SPR0+CSPR_MARKS
        jr nc,.ptr
        push af
        call spr_hide
        pop af
        inc a
        jr .hd
.ptr:   ld a,CSPR_PTR_SPR               ; the pointer
        ld bc,COMP_SPR_CX-SPR_SIZE/2
        ld de,COMP_PTR_Y
        ld hl,CSPR_PTR<<8
        jp spr_set

;------------------------------------------------------------------------------
; The human status HUD: a column of hardware sprites, sprite k for human k,
; HUD_SPR_X pixels in from the left edge of the 320 x 256 sprite screen,
; human 0 at the bottom (HUD_SPR_Y) and each next one HUD_SPR_STEP higher.
; Each shows its human's state with the human status patterns
; (sprite_data.asm): waiting in the city (HSPR_FIELD), aboard the VTOL
; (HSPR_ABOARD), rescued (HSPR_SAVED) or dead (HSPR_DEAD).  Unused humans'
; sprites are hidden.
;------------------------------------------------------------------------------
HUD_SPR_X       equ 8
HUD_SPR_Y       equ 256-8-SPR_SIZE  ; the bottom one: 8 pixels above the edge
HUD_SPR_STEP    equ SPR_SIZE
HUD_SPR_MAX     equ (HUD_SPR_Y+HUD_SPR_STEP)/HUD_SPR_STEP   ; that fit (15)
        ASSERT HSPR_FIELD == HS_WAIT-1 && HSPR_ABOARD == HS_ABOARD-1
        ASSERT HSPR_SAVED == HS_SAVED-1 && HSPR_DEAD == HS_DEAD-1
        ASSERT HUMAN_MAX <= SPR_COUNT
hum_hud:
        ld ix,humans
        ld c,0                          ; human = sprite number
.lp:    push bc
        ld a,(ix+6)
        or a
        jr z,.hide                      ; unused
        ld a,c
        cp HUD_SPR_MAX
        jr nc,.hide                     ; no room on the screen
        add a,a                         ; y = HUD_SPR_Y - human * 16
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,HUD_SPR_Y
        sub e
        ld e,a
        ld d,0
        ld a,(ix+6)
        dec a
        ld h,a                          ; the state's pattern
        ld l,0                          ; no mirror, rotation
        ld a,c
        ld bc,HUD_SPR_X
        call spr_set                    ; (sprites.asm)
        jr .nx
.hide:  ld a,c
        call spr_hide
.nx:    ld de,HREC
        add ix,de
        pop bc
        inc c
        ld a,c
        cp HUMAN_MAX
        jr nz,.lp
        ret


cs_spr:     db 0                        ; compass_spr: the next mark's sprite
