;==============================================================================
; Z-POLICE - HUD sprites (in the sprites page, PAGE_SPRITES, at $E000 in slot
; 7): the human status column and the compass bar, as hardware sprites on
; the 320 x 256 sprite screen.  hud_sprites sets both and sends the sprite
; table to the hardware; main_loop calls it once a frame, after the flip.
;
; Sprites used: 0..HUMAN_MAX-1 the humans, CSPR_SPR0.. the compass bar's
; marks, CSPR_PTR_SPR its pointer, FRM_SPR0.. the viewport's frame.
;==============================================================================

hud_sprites:
        ld a,(frm_on)                   ; the frame, once (they stay set)
        or a
        call z,frame_spr
        call hum_hud
        call compass_spr
        jp spr_update

;------------------------------------------------------------------------------
; The viewport's frame: curved corners and edges in hardware sprites, over
; Layer 2 and the border, so nothing is drawn into the view.  Set once after
; the sprites are hidden (frm_on; spr_hide_all clears it).  frame_tab: x, y,
; pattern and flags, then scale across and down: the edges are 1-row patterns
; stretched, FRM_H across (two at x8 overlapping, 224 pixels) and FRM_V down
; (two at x4 overlapping, 96).  The panel's bottom corners are rounded too.
;------------------------------------------------------------------------------
FRM_SPR0        equ CSPR_PTR_SPR+1  ; the frame's sprites (12)
FRM_L           equ SPR_SCREEN_X
FRM_R           equ SPR_SCREEN_X+256-SPR_SIZE
FRM_T           equ SPR_SCREEN_Y
FRM_B           equ SPR_SCREEN_Y+VIEW_H-SPR_SIZE
FRM_PB          equ SPR_SCREEN_Y+192-SPR_SIZE   ; the panel's bottom corners
FRM_X8          equ 3               ; (scale codes)
FRM_X4          equ 2
FRM_REC         equ 8

frame_tab:
        dw FRM_L, FRM_T
        db FRM_CRN, 0, 0, 0
        dw FRM_R, FRM_T
        db FRM_CRN, SPRF_XMIRROR, 0, 0
        dw FRM_L, FRM_B
        db FRM_CRN_P, SPRF_YMIRROR, 0, 0
        dw FRM_R, FRM_B
        db FRM_CRN_P, SPRF_XMIRROR|SPRF_YMIRROR, 0, 0
        dw FRM_L, FRM_PB
        db FRM_CRN_S, SPRF_YMIRROR, 0, 0
        dw FRM_R, FRM_PB
        db FRM_CRN_S, SPRF_XMIRROR|SPRF_YMIRROR, 0, 0
        dw FRM_L+SPR_SIZE, FRM_T                ; the top edge
        db FRM_H, 0, FRM_X8, 0
        dw FRM_R-16*8, FRM_T
        db FRM_H, 0, FRM_X8, 0
        dw FRM_L, FRM_T+SPR_SIZE                ; the left edge
        db FRM_V, 0, 0, FRM_X4
        dw FRM_L, FRM_B-16*4
        db FRM_V, 0, 0, FRM_X4
        dw FRM_R, FRM_T+SPR_SIZE                ; the right edge
        db FRM_V, SPRF_XMIRROR, 0, FRM_X4
        dw FRM_R, FRM_B-16*4
        db FRM_V, SPRF_XMIRROR, 0, FRM_X4
frame_tab_end:
FRM_COUNT       equ (frame_tab_end-frame_tab)/FRM_REC
        ASSERT FRM_SPR0+FRM_COUNT == SPR_COUNT

frame_spr:
        ld a,1
        ld (frm_on),a
        ld ix,frame_tab
        ld a,FRM_SPR0
.lp:    push af
        ld c,(ix+0)
        ld b,(ix+1)
        ld e,(ix+2)
        ld d,(ix+3)
        ld h,(ix+4)
        ld l,(ix+5)
        call spr_set
        pop af
        push af
        ld e,(ix+6)
        ld d,(ix+7)
        call spr_scale
        ld de,FRM_REC
        add ix,de
        pop af
        inc a
        cp FRM_SPR0+FRM_COUNT
        jr nz,.lp
        ret

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
; human 0 at the bottom and each next one HUD_SPR_STEP higher, the column
; centred on the screen: its middle sprite (human (nhumans - 1) / 2) at row
; HUD_SPR_MID.  Each shows its human's state with the human status patterns
; (sprite_data.asm): waiting in the city (HSPR_FIELD), aboard the VTOL
; (HSPR_ABOARD), rescued (HSPR_SAVED) or dead (HSPR_DEAD).  Unused humans'
; sprites are hidden, and any that would go off the top.
;------------------------------------------------------------------------------
HUD_SPR_X       equ 8
HUD_SPR_MID     equ 128             ; the middle sprite's row
HUD_SPR_STEP    equ SPR_SIZE
HUD_SPR_LOW     equ 256-8-SPR_SIZE  ; the lowest the bottom one goes
        ASSERT HUD_SPR_STEP == 16       ; (* 16: four shifts)
        ASSERT HSPR_FIELD == HS_WAIT-1 && HSPR_ABOARD == HS_ABOARD-1
        ASSERT HSPR_SAVED == HS_SAVED-1 && HSPR_DEAD == HS_DEAD-1
        ASSERT HUMAN_MAX <= SPR_COUNT
hum_hud:
        ld a,(nhumans)                  ; the bottom sprite's row: the
        dec a                           ; middle's + (nhumans - 1) / 2 steps
        srl a
        cp (HUD_SPR_LOW-HUD_SPR_MID)/HUD_SPR_STEP+1
        jr c,.m
        ld a,(HUD_SPR_LOW-HUD_SPR_MID)/HUD_SPR_STEP     ; (no lower than that)
.m:     add a,a
        add a,a
        add a,a
        add a,a
        add a,HUD_SPR_MID
        ld (hh_base),a
        ld ix,humans
        ld c,0                          ; human = sprite number
.lp:    push bc
        ld a,(ix+6)
        or a
        jr z,.hide                      ; unused
        ld a,c
        cp 256/HUD_SPR_STEP
        jr nc,.hide                     ; (off the top, surely)
        add a,a                         ; y = the bottom's - human * 16
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,(hh_base)
        sub e
        jr c,.hide                      ; off the top
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
frm_on:     db 0                        ; 1: the frame's sprites are set
hh_base:    db 0                        ; hum_hud: the bottom sprite's row
