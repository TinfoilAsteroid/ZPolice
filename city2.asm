;==============================================================================
; Z-POLICE - the second city page (8K page PAGE_CITY2, runs at $8000 in slot
; 4: CITY2_MMU)
;
; More of the Layer 2 drawing, paged in beside the city page (slot 7) for the
; city part of each frame: main_loop maps it over the ULA screen after
; clear_screen and puts the ULA screen back before draw_hud.  Nothing in that
; part of the frame uses the ULA screen (the video hardware shows it from
; bank 5 whatever the CPU has mapped), and the interrupt routine uses only
; slots 1 and 5, so interrupts stay on.  Both pages are mapped together, so
; code and data in either call or use the other directly (labels are global).
;
; Here: the street dots, the bullets, rockets and particles, the gunsight and
; the occlusion culling.  Their variables stay in the city page.  Anything
; that calls into this page from outside main_loop's city part must map it
; first (nextreg CITY2_MMU,PAGE_CITY2) and put the ULA screen back after.
;==============================================================================

;==============================================================================
; Street intersection markers - one dot per grid corner near the camera
; whose 4 cells are all open: no building, terrace or pad cell touches it
; (out of bounds counts as open: it is never drawn).  A corner a building
; touches is always drawn over by it (its faces cover their own corners, and
; the box hides those behind it), so it isn't worked out at all.
;   A row's corners have cells j-1 above and j below; each corner shares its
; left pair of cells with the corner before, so one pair is read a corner.
; An open corner's (X, Z1) is its row's first corner's (worked out once, by
; full rotation, only if the row has an open corner) + k (cosY, sinY), k its
; column in the row: exactly what stepping +256 world units k times gives.
;==============================================================================
draw_dots:
        ld a,(cz)
        ld hl,dot_r
        sub (hl)
        ld (dot_j),a
        ld a,(dot_r)
        add a,a
        add a,2
        ld (dot_rows),a
.row:   ld a,(dot_j)
        cp GRID+1
        jp nc,.nrow
        ; the rows of cells above and below the corners (0: off the map)
        ld hl,0
        or a
        jr z,.pa                        ; j = 0: none above
        dec a
        ld l,a
        ROWOFS
        ld de,city_map
        add hl,de
.pa:    ld (dot_pa),hl
        ld hl,0
        ld a,(dot_j)
        cp GRID
        jr nc,.pb                       ; j = GRID: none below
        ld l,a
        ROWOFS
        ld de,city_map
        add hl,de
.pb:    ld (dot_pb),hl
        ld a,(cx)
        ld hl,dot_r
        sub (hl)
        ld (dot_i),a
        ld (dot_i0),a
        xor a
        ld (dot_k),a
        ld (dot_rs),a                   ; (the row's start: not worked out)
        ld a,(dot_r)
        add a,a
        add a,2
        ld (dot_cols),a                 ; corners in the row
    IFNDEF DOTS_ALL
        ; Away from the map's edges (both rows of cells on the map, and the
        ; row's cell columns i0-1 .. i0+cols-1): the cells walked with two
        ; pointers, no bounds to check (the usual case)
        ld hl,(dot_pa)
        ld a,h
        or a
        jr z,.slow
        ld hl,(dot_pb)
        ld a,h
        or a
        jr z,.slow
        ld a,(dot_i0)
        dec a
        cp GRID
        jr nc,.slow                     ; (the first cell column: before 0)
        ld e,a
        ld a,(dot_cols)
        ld b,a                          ; B = corners left
        add a,e
        cp GRID
        jr nc,.slow                     ; the last past the map
        ld a,e
        add hl,a                        ; HL -> cell (i0-1, j) below
        ex de,hl
        ld hl,(dot_pa)
        add hl,a                        ; HL -> cell (i0-1, j-1) above
        ld c,$FF                        ; C: the left pair open?
        ld a,(hl)
        and CELL_CODE
        jr z,.f0a
        cp VOID_CODE
        jr nz,.f0c
.f0a:   ld a,(de)
        and CELL_CODE
        jr z,.fl
        cp VOID_CODE
        jr z,.fl
.f0c:   ld c,0
.fl:    inc hl                          ; the corner's right pair
        inc de
        ld a,(hl)
        and CELL_CODE
        jr z,.fa                        ; road above
        cp VOID_CODE
        jr nz,.fc                       ; a building above: covered
.fa:    ld a,(de)
        and CELL_CODE
        jr z,.fo
        cp VOID_CODE
        jr z,.fo
.fc:    ld c,0                          ; covered (and the next's left pair)
        djnz .fl
        jp .nrow
.fo:    ld a,c                          ; the right pair open: the corner is
        ld c,$FF                        ; if its left pair was
        or a
        jr z,.fn
        push hl
        push de
        push bc
        ld a,(dot_cols)
        sub b
        ld (dot_k),a                    ; its column in the row
        call dot_at
        pop bc
        pop de
        pop hl
.fn:    djnz .fl
        jp .nrow
        ASSERT 2*VIEW_R+1 < GRID        ; (a row's cells fit the map)
.slow:
    ENDIF
        ld a,(dot_i)
        dec a
        call dot_pair                   ; the first corner's left cells
        sbc a,a
        ld c,a                          ; C = $FF: open
        ld a,(dot_cols)
        ld b,a                          ; corners in the row
.col:   ld a,(dot_i)
        call dot_pair                   ; its right cells (keeps BC)
        sbc a,a
        ld e,a
        and c                           ; both pairs open?
        ld c,e                          ; (the right pair: the next's left)
        jr z,.nx
        ld a,(dot_i)
        cp GRID+1
        jr nc,.nx                       ; past the map
        push bc
        call dot_at                     ; work it out, plot it if in view
        pop bc
.nx:    ld hl,dot_i
        inc (hl)
        ld hl,dot_k
        inc (hl)
        djnz .col
.nrow:  ld hl,dot_j
        inc (hl)
        ld hl,dot_rows
        dec (hl)
        jp nz,.row
        ret

; A = cell column x: carry set if cells (x, j-1) and (x, j) are both open
; (none a building, terrace or pad; off the map is open).  Keeps BC.
; (DOTS_ALL, for testing: every corner open, as before the skip.)
dot_pair:
    IFDEF DOTS_ALL
        scf
        ret
    ENDIF
        cp GRID
        jr nc,.open                     ; (x = -1 wraps to 255: off the map)
        ld e,a
        ld d,0
        ld hl,(dot_pa)
        ld a,h
        or a
        jr z,.b                         ; no row above
        add hl,de
        ld a,(hl)
        and CELL_CODE
        jr z,.b                         ; road
        cp VOID_CODE
        jr z,.b                         ; out of bounds: not drawn
        or a                            ; covered (carry clear)
        ret
.b:     ld hl,(dot_pb)
        ld a,h
        or a
        jr z,.open                      ; no row below
        add hl,de
        ld a,(hl)
        and CELL_CODE
        jr z,.open
        cp VOID_CODE
        jr z,.open
        or a
        ret
.open:  scf
        ret
        ASSERT high city_map != 0       ; (0: no row)

; The open corner dot_k along the row: (X, Z1) = the row's first corner's
; + dot_k (cosY, sinY) into (t_x, t_z1), then plot it
dot_at:
        ld a,(dot_rs)
        or a
        jr nz,.st
        ; the row's first corner (dot_i0, dot_j) by full rotation
        ld a,(dot_i0)
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
        ld (dot_x0),hl
        ld hl,(t_z1)
        ld (dot_z0),hl
        ld a,1
        ld (dot_rs),a
.st:    ld hl,(cos_y)
        call dot_kmul
        ld de,(dot_x0)
        add hl,de
        ld (t_x),hl
        ld hl,(sin_y)
        call dot_kmul
        ld de,(dot_z0)
        add hl,de
        ld (t_z1),hl
        ; fall through

; Plot the ground point (t_x, t_z1)
plot_dot:
        ld hl,(t_x)
        ld (tmpv+0),hl
        call abs_hl
        ld a,(pitch)
        or a
        jr z,.lv                        ; level flight: cull_c is exactly 1.0
        ld de,(cull_c)
        call fmul
.lv:    ld de,(t_z1)
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
        ld l,a
        ld a,c
        call seg_map
        ld h,a
        ld (hl),DOT_COL
        ret

; HL = v -> HL = v * dot_k, modulo 65536 (as v added dot_k times)
dot_kmul:
        ld a,(dot_k)
        jp kmul                         ; (city.asm)

dot_pa:     dw 0                        ; draw_dots: the row of cells above
dot_pb:     dw 0                        ;   and below the corners (0: none),
dot_i0:     db 0                        ;   the row's first corner column,
dot_k:      db 0                        ;   the corner's column in the row,
dot_rs:     db 0                        ;   1: its start worked out,
dot_x0:     dw 0                        ;   its first corner's X, Z1
dot_z0:     dw 0
;==============================================================================
; Rounds and the laser beam (`bullets`, laser_rec; moved by weapons.asm): a
; line along the path each covered this frame, from where it started to
; where it is.  A fresh round's path starts at the muzzle, below and behind
; the view, so its start is moved along the line to where it enters the
; view and pinned to that screen edge: the shot rises from the bottom row.
; Drawn over the city; a line whose end is outside the view is skipped.
;==============================================================================
draw_bullets:
        ld ix,bullets                   ; the rounds, then the laser beam
        ld b,NBULLETS+1
.lp:    push bc
        ld a,(ix+B_STATE)
        or a
        jr z,.nx
        ld a,(ix+B_KIND)
        cp BK_BOMB
        jr z,.rkt                       ; a bomb: as a rocket
        cp BK_FIREBALL
        jr nz,.nfb
        call draw_fireball
        jr .nx
.nfb:   cp BK_ROCKET
        jr c,.rnd                       ; a round (or an autocannon shell)
        cp BK_MISSILE+1
        jr nc,.rnd
.rkt:   call draw_rocket                ; a rocket, a missile or a bomb
        jr .nx
.rnd:   ld a,(ix+B_STATE)
        cp 3                            ; 3: laser beam
        ld a,BULLET_COL
        jr nz,.col
        ld a,LASER_COL
.col:   ld (line_col),a
        push ix                         ; end: where it is now
        pop hl
        inc hl                          ; -> B_X, B_Y, B_Z
        call bul_cam
        jr nz,.nx                       ; not in view
        ld (bl_x),a
        ld a,c
        ld (bl_y),a
        ld hl,tmpv
        ld de,bh_cam
        ld bc,6
        ldir
        push ix                         ; start of this frame's path
        pop hl
        ld de,B_PX
        add hl,de
        call bul_cam
        call nz,bul_clip                ; outside: where the line enters
        ld e,a
        ld d,c
        ld a,(bl_x)
        ld l,a
        ld a,(bl_y)
        ld h,a
        call draw_line
.nx:    ld de,BREC
        add ix,de
        pop bc
        djnz .lp
        ret

; Fireball IX: a ball of fire 5 pixels across, with a trail back along its
; path.  Drawn only when its middle is in view, the trail if its end is.
draw_fireball:
        push ix
        pop hl
        inc hl                          ; head: B_X, B_Y, B_Z
        call bul_cam
        ret nz
        ld (bl_x),a
        ld a,c
        ld (bl_y),a
        ld a,FB_TRAIL
        call rk_back
        call bul_cam
        jr nz,.ball
        ld e,a
        ld d,c
        ld a,(bl_x)
        ld l,a
        ld a,(bl_y)
        ld h,a
        ld a,FB_TRAIL_COL
        ld (line_col),a
        call draw_line
.ball:  ld a,(bl_x)                     ; (the ball whole, or not at all)
        sub 2
        cp 256-4
        ret nc
        ld a,(bl_y)
        sub 2
        cp VIEW_H-4
        ret nc
        ld a,FB_COL
        ld (line_col),a
        ld a,(bl_y)                     ; its rows, widest in the middle
        dec a
        ld c,1
        call .row
        ld a,(bl_y)
        ld c,2
        call .row
        ld a,(bl_y)
        inc a
        ld c,1
        call .row
        ld a,(bl_y)                     ; and its top and bottom
        sub 2
        ld h,a
        add a,4
        ld d,a
        ld a,(bl_x)
        ld l,a
        ld e,a
        jp draw_line
.row:   ld h,a                          ; row A, C pixels each side
        ld d,a
        ld a,(bl_x)
        ld e,a
        sub c
        ld l,a
        ld a,e
        add a,c
        ld e,a
        jp draw_line

; Rocket IX: a white streak ROCKET_LEN (1 m) long from its head back along
; its path, then a yellow trail to ROCKET_TRAIL (1.5 m) behind the head.  A
; bomb (BK_BOMB): the streak only, no trail, 2 pixels wide.  Drawn only when
; every point drawn is in view (it's tiny: no clipping).
draw_rocket:
        push ix
        pop hl
        inc hl                          ; head: B_X, B_Y, B_Z
        call bul_cam
        ret nz                          ; not in view
        ld (bl_x),a
        ld a,c
        ld (bl_y),a
        ld a,ROCKET_LEN                 ; the tail of the streak
        call rk_back
        call bul_cam
        jr nz,.head                     ; out of view: the head pixel only
        ld (rk_sx),a
        ld a,c
        ld (rk_sy),a
        ld a,(ix+B_KIND)                ; a bomb: no trail
        cp BK_BOMB
        jr z,.white
        ld a,ROCKET_TRAIL               ; the end of the trail
        call rk_back
        call bul_cam
        jr nz,.white
        ld e,a                          ; yellow trail first, so the white
        ld d,c                          ; streak stays on top
        ld a,(rk_sx)
        ld l,a
        ld a,(rk_sy)
        ld h,a
        ld a,TRAIL_COL
        ld (line_col),a
        call draw_line
.white: ld a,(rk_sx)
        ld e,a
        ld a,(rk_sy)
        ld d,a
        jr .line
.head:  ld a,(bl_x)
        ld e,a
        ld a,(bl_y)
        ld d,a
.line:  ld a,(bl_x)
        ld l,a
        ld a,(bl_y)
        ld h,a
        ld a,ROCKET_COL
        ld (line_col),a
        push de
        push hl
        call draw_line
        pop hl
        pop de
        ld a,(ix+B_KIND)                ; a bomb: twice as wide, the same
        cp BK_BOMB                      ; line a pixel to the right
        ret nz
        ld a,l
        inc a
        ret z                           ; (at the right edge)
        ld l,a
        ld a,e
        inc a
        ret z
        ld e,a
        jp draw_line

; A = distance d (units) -> HL -> rk_pt = rocket IX's head - d * (sin, slope,
; cos): d back along its path
rk_back:
        ld (rk_d),a
        ld e,(ix+B_SIN)
        ld d,(ix+B_SIN+1)
        ld bc,B_X
        call .ax
        ld (rk_pt),hl
        ld e,(ix+B_SLOPE)
        ld d,(ix+B_SLOPE+1)
        ld bc,B_Y
        call .ax
        ld (rk_pt+2),hl
        ld e,(ix+B_COS)
        ld d,(ix+B_COS+1)
        ld bc,B_Z
        call .ax
        ld (rk_pt+4),hl
        ld hl,rk_pt
        ret
; DE = S7.8 component, BC = offset of the coordinate -> HL = coord - d * DE
.ax:    push bc
        ld a,(rk_d)
        ld l,a
        ld h,0
        call fmul
        ex de,hl
        push ix
        pop hl
        pop bc
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,de
        ret

;==============================================================================
; Zombie burst particles: one pixel each, coloured by age (PART_COL0 + 4 per
; frame of age, bright to dark green), drawn over the city
;==============================================================================
draw_particles:
        ld ix,particles
        ld b,NPART
.lp:    push bc
        ld a,(ix+0)
        or a
        jr z,.nx
        push ix
        pop hl
        inc hl                          ; -> x, y, z
        call bul_cam
        jr nz,.nx                       ; not in view
        ld l,a                          ; x
        ld a,c
        call seg_map                    ; row's section -> A = y & 31
        ld h,a
        ld a,(ix+0)                     ; colour: its age-1 colour (+10)
        dec a                           ; + (age-1)*4
        add a,a
        add a,a
        add a,(ix+10)
        ld (hl),a
.nx:    ld de,PREC
        add ix,de
        pop bc
        djnz .lp
        ret

; HL -> world x, y, z: camera space into tmpv; A = outcode, Z set if in view
; (then A = screen x, C = screen y)
bul_cam:
        ld de,bp_x
        ld bc,6
        ldir
        ld hl,(bp_x)
        ld de,(cam_x+1)
        or a
        sbc hl,de
        ld (t_dx),hl
        ld hl,(bp_z)
        ld de,(cam_z+1)
        or a
        sbc hl,de
        ld (t_dz),hl
        call rot_yaw
        ld (tmpv+0),hl
        call rot_pitch                  ; at ground level
        ld (tmpv+2),hl
        ld (tmpv+4),de
        ld hl,(bp_y)                    ; + height * (cosP, sinP)
        ld de,(cos_p)
        call fmul
        ld de,(tmpv+2)
        add hl,de
        ld (tmpv+2),hl
        ld hl,(bp_y)
        ld de,(sin_p)
        call fmul
        ld de,(tmpv+4)
        add hl,de
        ld (tmpv+4),hl
        ld hl,tmpv
        call calc_oc
        or a
        ret nz
        ld hl,tmpv
        call project
        cp a                            ; Z set
        ret

; tmpv = the start, outside the planes in A; bh_cam = the end, in view.
; -> A = screen x, C = screen y where the line enters the view, pinned to
; the edge it crosses.
bul_clip:
        push ix
        ld (bc_oc),a
        ld hl,0
        ld (bc_t),hl
        ld c,1                          ; each plane the start is outside
.pl:    ld a,(bc_oc)
        and c
        jr z,.np
        ld a,c
        ld (clip_plane),a
        push bc
        ld ix,tmpv
        call plane_dist                 ; start: < 0
        push hl
        ld ix,bh_cam
        call plane_dist                 ; end: >= 0
        pop de
        or a
        sbc hl,de                       ; fe - fs
        ex de,hl
        call neg_hl                     ; -fs
        call div_frac                   ; t = -fs / (fe - fs)
        push ix
        pop hl
        ld de,(bc_t)                    ; the latest crossing counts
        or a
        sbc hl,de
        pop bc
        jr c,.np
        add hl,de
        ld (bc_t),hl
        ld a,c
        ld (bc_pl),a
.np:    sla c
        ld a,c
        cp 32
        jr nz,.pl
        ld ix,tmpv                      ; start += t * (end - start)
        ld b,3
.lc:    push bc
        ld l,(ix+bh_cam-tmpv)           ; end - start
        ld h,(ix+bh_cam-tmpv+1)
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        push de
        ld de,(bc_t)
        call mul_frac
        pop de
        add hl,de
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop bc
        djnz .lc
        pop ix
        ld hl,tmpv
        call project
        ld e,a
        ld a,(bc_pl)                    ; pin to the edge it crossed
        cp 16
        jr nz,.t
        ld c,VIEW_H-1                   ; bottom
.t:     cp 8
        jr nz,.l
        ld c,0                          ; top
.l:     cp 2
        jr nz,.r
        ld e,0                          ; left
.r:     cp 4
        jr nz,.d
        ld e,255                        ; right
.d:     ld a,e
        ret

;==============================================================================
; Gunsight in the Layer 2 viewport: the crosshairs in sight_mask (gun_aim,
; weapons.asm): the centre one at (sight_ax, sight_ay), where the aim assist
; turns its rounds (aim_probe; on row sight_y, the centre gun's tilt, without
; it), and the linked chain guns' LINK_SIGHT_DX either side of the view's
; centre on row sight_y
;==============================================================================
draw_gunsight:
        ld a,HUD_COL
        ld (line_col),a
        ld a,(sight_ay)
        ld (gs_row),a
        ld a,(sight_mask)
        rra
        push af
        ld a,(sight_ax)
        call c,gs_cross
        ld a,(sight_y)
        ld (gs_row),a
        pop af
        rra
        push af
        ld a,128-LINK_SIGHT_DX
        call c,gs_cross
        pop af
        rra
        ret nc
        ld a,128+LINK_SIGHT_DX
        ; fall through
        ASSERT SM_CENTRE == 1 && SM_LINK_L == 2 && SM_LINK_R == 4

; A = x: a crosshair centred at (x, gs_row), its arms 3..6 pixels out
gs_cross:
        ld (sight_x),a
        ld a,(gs_row)
        ld h,a
        ld d,a
        ld a,(sight_x)
        sub 6
        ld l,a
        add a,3
        ld e,a
        call draw_line
        ld a,(gs_row)
        ld h,a
        ld d,a
        ld a,(sight_x)
        add a,3
        ld l,a
        add a,3
        ld e,a
        call draw_line
        ld a,(gs_row)
        sub 6
        ld h,a
        add a,3
        ld d,a
        ld a,(sight_x)
        ld l,a
        ld e,a
        call draw_line
        ld a,(gs_row)
        add a,3
        ld h,a
        add a,3
        ld d,a
        ld a,(sight_x)
        ld l,a
        ld e,a
        jp draw_line

;==============================================================================
; The missile lock's reticule (lock_update, weapons.asm): a square at
; (ret_x, ret_y), yellow while searching, flashing red while locking, red
; when locked
;==============================================================================
draw_reticule:
        ld a,(ret_on)
        or a
        ret z
        ld a,(lock_state)
        cp 2
        ld a,LASER_COL                  ; locked
        jr z,.col
        ld a,(lock_state)
        or a
        ld a,BULLET_COL                 ; searching
        jr z,.col
        ld a,(lock_t)                   ; locking: flashing
        and 4
        ld a,BULLET_COL
        jr z,.col
        ld a,LASER_COL
.col:   ld (line_col),a
        ld a,(ret_y)                    ; the top
        sub RET_HALF
        ld h,a
        ld d,a
        call .row
        ld a,(ret_y)                    ; the bottom
        add a,RET_HALF
        ld h,a
        ld d,a
        call .row
        ld a,(ret_x)                    ; the left
        sub RET_HALF
        call .col2
        ld a,(ret_x)                    ; the right
        add a,RET_HALF
.col2:  ld l,a
        ld e,a
        ld a,(ret_y)
        sub RET_HALF
        ld h,a
        add a,2*RET_HALF
        ld d,a
        jp draw_line
.row:   ld a,(ret_x)
        sub RET_HALF
        ld l,a
        add a,2*RET_HALF
        ld e,a
        jp draw_line

    IFDEF OCCLUSION_CULL
;==============================================================================
; Occlusion culling (OCCLUSION_CULL; pitched too with OCC_PITCHED, up to
; OCC_PMAX: then the columns are tilted, see occ_test and occ_pretest.pit)
;
; In level flight every screen column is a vertical slice of the world through
; the camera.  The cells are walked in exactly the reverse of the painter's
; order, i.e. front to back.  Each building is transformed as usual, then
; tested against OCC_YBUF, which holds per column the row from which the
; screen is known to be covered down to the ground:
;   * hidden - in every column it spans, its highest point is no higher than
;     that row - it is dropped;
;   * otherwise it lowers the row across its columns to its lowest top
;     corner, and its corners and face settings are kept in a record.
; The kept buildings and the zombie cells are then drawn back to front.
; This is safe because buildings that share a column meet the walk front to
; back (the grid order guarantees it), the camera is above the ground (what
; is behind sits higher on screen), the cover row is the lowest top corner
; (an underestimate) and bounds are clamped inwards to the screen.  A
; building with a corner behind the camera is never dropped and never covers.
;==============================================================================
OCC_YBUF        equ $4000       ; per column: covered from this row down
OCC_YBUF8       equ $4200       ; per 8 columns: at least the most of
                                ; OCC_YBUF's 8 (its own page, before the
                                ; records), so a hidden test can pass 8
                                ; columns at once
OCC_LIST        equ $4100       ; kept buildings and zombie cells, 2 bytes each
OCC_REC0        equ $43         ; the records' first page; two records a
OCC_RECN        equ $60         ; page (128 bytes each, at +0 and +128), up
                                ; to $5F: 58 records ($6000 on: city_col).
                                ; The busiest street view at the full draw
                                ; distance (8 tiles) keeps 35.
; Record: copy of vtx's 8 corners, bytes 0-8 of each 16 (X, Y, Z, outcode,
; sx, sy), at the same offsets from the record's start, and in the first
; corner's spare bytes
OR_VIS          equ 9           ; bld_vis, bld_mx, bld_mz, col_x, col_z, col_top,
OR_N            equ 7           ;   bld_cut
        ASSERT OR_VIS + OR_N <= 16
        ASSERT bld_cut == bld_vis + OR_N - 1
        ASSERT low OCC_YBUF8 == 0       ; (occ_cut: the low byte is the group)
; A record in a page's upper half is drawn with the +128 corner lists
; (face_set = FACE_SET2, city.asm).
; A list entry is a record's address ($4300-$5FFF), a cell with humans as
; its city_col address ($6000-$6FFF) or a cell with zombies as its city_map
; address ($7000-$7FFF).

; Start of the city: occlusion on in level flight (and with OCC_PITCHED
; up to OCC_PMAX)
occ_begin:
        xor a
        ld (occ_on),a
        ld (occ_full),a
    IFNDEF OCC_PITCHED
        ld a,(pitch)
        or a
        ret nz
    ELSE
        ld a,(pitch)                    ; pitched past OCC_PMAX: the plain way
        bit 7,a                         ; (the sides lean too far, the bounds
        jr z,.pp                        ; are loose: it costs more than it
        neg                             ; saves)
.pp:    cp OCC_PMAX+1
        ret nc
        ld hl,2*OCC_R                   ; occ_pretest's pitched bounds
        ld de,(cos_p)
        call fmul
        ld (o_kc),hl                    ; 2R cosP
        ld hl,2*OCC_R
        ld de,(sin_p)
        call fmul
        bit 7,h
        jr nz,.ks
        ld hl,0
.ks:    ld (o_ks),hl                    ; min(0, 2R sinP)
        xor a
    ENDIF
        inc a
        ld (occ_on),a
        ld hl,OCC_LIST
        ld (occ_lp),hl
        ld hl,OCC_REC0*256
        ld (occ_rp),hl
        ld hl,OCC_YBUF                  ; nothing covered yet: by DMA (about
        ld bc,256                       ; 1,500 T less than an LDIR), then
        ld a,VIEW_H                     ; the DMA left ready for the spans
        call dma_fill
        call clear_screen.spans
        ld hl,OCC_YBUF8                 ; (and so in every group of 8)
        ld (hl),VIEW_H
        ld de,OCC_YBUF8+1
        ld bc,31
        ldir
        ret

; The cells of draw_cells in exactly the reverse order.  Each half row
; starts from the same cell as draw_row and steps the same way, so every
; cell gets bit-identical yaw-space coordinates.
occ_cells:
        ld a,(cz)
        ld (cell_j),a
        call occ_row                    ; camera row first
        ld a,(view_r)
        ld b,a
.f:     push bc
        ld hl,cell_j
        inc (hl)
        call occ_row                    ; then cz+1 .. cz+R
        pop bc
        djnz .f
        ld a,(cz)
        ld (cell_j),a
        ld a,(view_r)
        ld b,a
.n:     push bc
        ld hl,cell_j
        dec (hl)
        call occ_row                    ; then cz-1 .. cz-R
        pop bc
        djnz .n
        ret

; One row front to back.  (X, Z1) is the walk's, in HL', DE' (as draw_row's,
; city.asm), stepped one cell at a time by (cosY, sinY) patched in by
; walk_patch.  Each half starts where draw_row's does and gets to the camera
; column by k steps at once (walk_back, walk_fwd: exactly k single steps).
occ_row:
        ld a,(cell_j)
        cp GRID
        ret nc
        ld hl,cz                        ; a row wholly out of view (row_cull):
        sub (hl)                        ; nothing in it to try
        ld hl,view_r
        add a,(hl)
        ld hl,row_skip
        add hl,a
        ld a,(hl)
        or a
        ret nz
        ld a,(cell_j)
        call row_base
        ; right half, as draw_row: start at cx+R, back R cells to cx
        ld a,(cx)
        ld hl,view_r
        add a,(hl)
        ld (cell_i),a
        call row_start
        ld a,(view_r)
        call walk_back
        ld a,(cx)
        ld (cell_i),a
        call try_cell                   ; camera column first
        ld a,(view_r)
        ld b,a
.r:     push bc
        ld hl,cell_i
        inc (hl)
        exx                             ; one cell +x
.cp:    ld bc,0                         ; (cosY: walk_patch)
        add hl,bc
        ex de,hl
.sp:    ld bc,0                         ; (sinY)
        add hl,bc
        ex de,hl
        exx
        WALK_TRY                        ; then cx+1 .. cx+R
        pop bc
        djnz .r
        ; left half, as draw_row: start at cx-R, on R-1 cells to cx-1
        ld a,(cx)
        ld hl,view_r
        sub (hl)
        ld (cell_i),a
        call row_start
        ld a,(view_r)
        dec a
        call walk_fwd
        ld a,(cx)
        dec a
        ld (cell_i),a
        WALK_TRY                        ; then cx-1 .. cx-R
        ld a,(view_r)
        dec a
        ld b,a
.l:     push bc
        ld hl,cell_i
        dec (hl)
        exx                             ; one cell -x
.cm:    ld bc,0                         ; (cosY)
        or a
        sbc hl,bc
        ex de,hl
.sm:    ld bc,0                         ; (sinY)
        or a
        sbc hl,bc
        ex de,hl
        exx
        WALK_TRY
        pop bc
        djnz .l
        ret
        ASSERT VIEW_R >= 2              ; (view_r - 1 > 0: the djnz counts)

; A = k: the walk's (X, Z1) (HL', DE') + k (cosY, sinY), or - for
; walk_back: the same as k single steps (kmul's products are modulo 65536,
; as the steps' sums are)
walk_fwd:
        ld b,a
        ld hl,(cos_y)
        call kmul                       ; (keeps BC)
        push hl                         ; k cosY
        ld a,b
        ld hl,(sin_y)
        call kmul
        push hl                         ; k sinY
        exx
        ex de,hl
        pop bc
        add hl,bc                       ; Z1 + k sinY
        ex de,hl
        pop bc
        add hl,bc                       ; X + k cosY
        exx
        ret
walk_back:
        ld b,a
        ld hl,(cos_y)
        call kmul
        push hl                         ; k cosY
        ld a,b
        ld hl,(sin_y)
        call kmul
        push hl                         ; k sinY
        exx
        ex de,hl
        pop bc
        or a
        sbc hl,bc                       ; Z1 - k sinY
        ex de,hl
        pop bc
        or a
        sbc hl,bc                       ; X - k cosY
        exx
        ret

; HL -> a city_map byte: list the cell (as its city_col address) if humans
; stand there (bit 6)
occ_human:
        bit CELL_HUMAN_B,(hl)
        ret z
        ld de,city_col-city_map
        add hl,de
        ex de,hl
        ld hl,(occ_lp)
        ld (hl),e
        inc l
        ld (hl),d
        inc l
        ld (occ_lp),hl
        ret

; HL -> a city_map byte: list the cell if zombies stand there, or special
; monsters fly over it (bit 7)
occ_zombie:
        bit CELL_ZOMBIE_B,(hl)
        ret z
        ex de,hl
        ld hl,(occ_lp)
        ld (hl),e
        inc l
        ld (hl),d
        inc l
        ld (occ_lp),hl
        ret

; draw_cell tail in level flight: drop the building if it is hidden,
; otherwise make it a cover and keep it (corners in vtx, face settings)
occ_record:
        ld a,(occ_full)
        or a
        ret nz
        ld a,(occ_rp+1)
        cp OCC_RECN
        jr c,.room
        ld a,1                          ; out of records: give up this frame
        ld (occ_full),a
        ret
.room:
        ; screen bounds of the corners of the drawn faces
        xor a
        ld (o_xmax),a
        ld (o_tcov),a
    IFDEF OCC_PITCHED
        ld (o_bx1),a
        ld (o_tx1),a
    ENDIF
        dec a
        ld (o_xmin),a
        ld (o_ymin),a
    IFDEF OCC_PITCHED
        ld (o_bx0),a
        ld (o_tx0),a
    ENDIF
        ld a,(bld_used0)
        ld (o_used),a
        ld ix,vtx
        ld b,8
.cl:    push bc
        ld a,(o_used)
        rrca
        ld (o_used),a
        jr nc,.nx                       ; corner not on a drawn face
        ld a,(ix+6)
        bit 0,a
        jr nz,.keep                     ; behind the near plane: no bounds
        or a
        call nz,vtx_proj                ; off screen: clamped projection
        ld a,(ix+7)                     ; sx
        ld hl,o_xmin
        cp (hl)
        jr nc,.x1
        ld (hl),a
.x1:    ld hl,o_xmax
        cp (hl)
        jr c,.x2
        ld (hl),a
.x2:    ld a,(ix+8)                     ; sy
        ld hl,o_ymin
        cp (hl)
        jr nc,.y1
        ld (hl),a
.y1:    pop bc
        push bc
    IFDEF OCC_PITCHED
        ; the bottom corners' columns and the top corners' (pitched, the
        ; sides lean: only columns in both are covered from the top down)
        ld hl,o_bx0
        ld a,b
        cp 5
        jr nc,.bt
        ld hl,o_tx0
.bt:    ld a,(ix+7)
        cp (hl)
        jr nc,.b1
        ld (hl),a
.b1:    inc hl
        cp (hl)
        jr c,.b2
        ld (hl),a
.b2:    ld a,b
    ELSE
        ld a,b
    ENDIF
        cp 5
        jr nc,.nx                       ; corners 0-3 are the bottom ones
        ld a,(ix+6)
        and 16
        ld a,VIEW_H                     ; top corner below the screen:
        jr nz,.tc                       ; covers nothing
        ld a,(ix+8)
.tc:    ld hl,o_tcov
        cp (hl)
        jr c,.nx
        ld (hl),a                       ; lowest top corner
.nx:    ld de,16
        add ix,de
        pop bc
        djnz .cl
        call occ_cut                    ; rows hidden by nearer buildings
        ld (bld_cut),a
        call occ_test
        ret c                           ; hidden: dropped
        jr .store
.keep:  pop bc                          ; no bounds: keep, but no cover
        ld a,VIEW_H                     ; (and nothing cut)
        ld (bld_cut),a
.store: ; the corners: vtx's 8 x 16 bytes into the record, at the same
        ; offsets from its start (vtx is page aligned, the record at +0 or
        ; +128 in its page), by one DMA transfer; then the DMA put back as
        ; fill_spans needs it (port A the fixed colour byte, length high 0:
        ; clear_screen.spans).  (Only bytes 0-8 of each corner are used:
        ; X, Y, Z, oc, sx, sy; the first's 9-15 are written next.)
        ld hl,(occ_rp)
        ld (occ_dma_dst),hl
        ld hl,occ_dma
        ld bc,occ_dma_n<<8 | IO_DATAGEAR_DMA_PORT
        otir                            ; (the CPU waits while it copies)
        ld de,(occ_rp)
        ld a,e
        add a,OR_VIS
        ld e,a
        ld hl,bld_vis                   ; bld_vis .. bld_cut: record order
        ld bc,OR_N
        ldir
        ld de,(occ_rp)
        ld hl,(occ_lp)                  ; keep it on the list
        ld (hl),e
        inc l
        ld (hl),d
        inc l
        ld (occ_lp),hl
        ld hl,128                       ; the next record
        add hl,de
        ld (occ_rp),hl
        ret

; occ_record's copy: vtx's 128 bytes to the record (occ_dma_dst), memory to
; memory, both addresses counting up; then port A back on the fixed colour
; byte and the length's high byte 0, as the spans need (clear_screen.spans)
occ_dma:    db DMA_DISABLE
            db DMA_WRO_BLOCK_PORTA_A2B_XFR  ; port A start, length:
            dw vtx
            dw 128
            db DMA_WR1_P1INC_MEMORY         ; port A counts up,
            db DMA_WR2_P2INC_MEMORY         ; port B counts up
            db DMA_WR4_CONT_MODE            ; continuous, port B start:
occ_dma_dst: dw 0
            db DMA_LOAD, DMA_ENABLE
            db DMA_WRO_BLOCK_PORTA_A2B_XFR  ; and back: port A, length
            dw l2_cls_byte
            dw 0
            db DMA_WR1_P1FIXED_MEMORY       ; port A fixed
occ_dma_n   equ $ - occ_dma
        ASSERT low vtx == 0 && OR_VIS + OR_N <= 16

; Before the transform: rough screen bounds of the building from its cell
; centre (t_x, t_z1; at pitch 0 camera Z = Z1), a circle of radius OCC_R
; around it and its height, each widened by a pixel for rounding.
; Carry set if those bounds are already hidden.
OCC_R           equ 188             ; half the cell diagonal (181) + rounding
OP_M            equ 8               ; pitched bounds' margin (occ_pretest.pit)
OCC_PMAX        equ 18              ; OCC_PITCHED: occlusion up to this |pitch|
occ_pretest:
        ld a,(occ_full)
        or a
        ret nz                          ; not keeping any more: no point
    IFDEF OCC_PITCHED
        ld a,(pitch)
        or a
        jp nz,.pit                      ; pitched: bounds of its own
    ENDIF
        ld hl,(t_z1)
        ld de,-OCC_R-NEAR
        add hl,de
        bit 7,h
        jp nz,.no                       ; may reach the near plane
        ld hl,(t_z1)
        ld de,-OCC_R
        add hl,de
        ld (o_zmin),hl
        ld de,2*OCC_R
        add hl,de
        ld (o_zmax),hl                  ; (for oz_far)
        ld hl,(o_zmin)
.zs:    ld de,oz_min
        call oz_norm                    ; the near Z: always needed
        xor a
        ld (oz_maxok),a                 ; the far Z: when first needed
        ; left edge: X-R, over the far Z if positive, the near Z if negative
        ld hl,(t_x)
        ld de,-OCC_R
        add hl,de
        ld de,oz_min
        bit 7,h
        call z,oz_far
        call oz_sx
        or a
        jr z,.l2
        dec a
.l2:    ld (o_xmin),a
        ; right edge: X+R, over the near Z if positive, the far Z if negative
        ld hl,(t_x)
        ld de,OCC_R
        add hl,de
        ld de,oz_min
        bit 7,h
        call nz,oz_far
        call oz_sx
        inc a
        jr nz,.r2
        dec a
.r2:    ld (o_xmax),a
        ; top: height above the eye over the near Z, or below it over the far Z
    IFDEF OCC_PITCHED
        ld a,(pitch)
        or a
        jr z,.lvt
        ld hl,(o_ytop)                  ; pitched: the most Y (.pit)
        jr .tp
.lvt:
    ENDIF
        ld hl,(bld_h)
        ld de,(cam_y)
        or a
        sbc hl,de
.tp:    bit 7,h
        jr nz,.below
        ld de,oz_min
        call oz_sc                      ; A = 128 * (h - camY) / Zmin
        ld c,a
        ld a,VIEW_CY-1
        sub c
        jr nc,.ty
        xor a
        jr .ty
.below: call oz_far                     ; (keeps HL)
        call oz_sc                      ; A = 128 * (camY - h) / Zmax
        add a,VIEW_CY-1
        jr nc,.ty
        ld a,255
.ty:    ld (o_ymin),a
        jp occ_hidden
.no:    or a
        ret
    IFDEF OCC_PITCHED
; Pitched: the building's camera-space bounds from its yaw-space ones, the
; circle round its centre (Z1 = t_z1 -/+ OCC_R, X = t_x -/+ OCC_R) and its
; height above the eye (Yw = -camY .. h - camY):
;   Z = Yw sinP + Z1 cosP:  Zmin = min(Yw sinP) + (t_z1 - R) cosP - OP_M,
;                           Zmax = max(Yw sinP) + (t_z1 - R) cosP + 2R cosP + OP_M
;   Y = Yw cosP - Z1 sinP:  Ymax = (h - camY) cosP - min(Z1 sinP) + OP_M
; (cosP > 0; 2R cosP and min(0, 2R sinP) once a frame, occ_begin).  OP_M
; covers fmul's rounding and the transform's.  Then as in level flight,
; with Ymax for the top.
.pit:   ld hl,(cam_y)
        call neg_hl
        ld de,(sin_p)
        call fmul
        push hl                         ; -camY sinP
        ld hl,(bld_h)
        ld de,(cam_y)
        or a
        sbc hl,de
        ld (o_ytop),hl                  ; (h - camY, for Ymax)
        ld de,(sin_p)
        call fmul                       ; (h - camY) sinP
        pop de
        push hl
        or a
        sbc hl,de
        pop hl
        jp p,.mm                        ; HL >= DE: HL the most, DE the least
        ex de,hl
.mm:    push hl                         ; max(Yw sinP)
        push de                         ; min(Yw sinP)
        ld hl,(t_z1)
        ld de,-OCC_R
        add hl,de
        push hl
        ld de,(cos_p)
        call fmul                       ; (t_z1 - R) cosP
        ex de,hl
        pop hl                          ; t_z1 - R
        ex (sp),hl                      ; HL = min(Yw sinP), stack t_z1 - R
        add hl,de
        ld bc,-OP_M
        add hl,bc                       ; Zmin
        ld (o_zmin),hl
        ld bc,-NEAR
        add hl,bc
        bit 7,h
        jr nz,.pno                      ; may reach the near plane
        pop bc                          ; t_z1 - R
        pop hl                          ; max(Yw sinP)
        add hl,de
        ld de,(o_kc)
        add hl,de
        ld de,OP_M
        add hl,de
        ld (o_zmax),hl                  ; Zmax
        ld h,b
        ld l,c
        ld de,(sin_p)
        call fmul                       ; (t_z1 - R) sinP
        ld de,(o_ks)
        add hl,de                       ; min(Z1 sinP)
        push hl
        ld hl,(o_ytop)
        ld de,(cos_p)
        call fmul                       ; (h - camY) cosP
        pop de
        or a
        sbc hl,de
        ld de,OP_M
        add hl,de
        ld (o_ytop),hl                  ; Ymax
        ld hl,(o_zmin)
        jp .zs
.pno:   pop bc
        pop bc
        or a
        ret
    ENDIF

; occ_pretest's projections: as zpatch / scale_comp (and its old occ_sx),
; the same arithmetic step for step, but each Z normalised once (oz_norm)
; into a state (shift count, 0 right / 1 left, reciprocal) that oz_sc reads,
; the product by VP_SCALE, and no self-patching.

; DE = oz_max, the far Z's state (o_zmax), normalised the first
; time it's needed in a pretest (oz_maxok).  Keeps HL.
oz_far:
        ld de,oz_max
        ld a,(oz_maxok)
        or a
        ret nz
        inc a
        ld (oz_maxok),a
        push hl
        ld hl,(o_zmax)
        ld de,oz_max
        push de
        call oz_norm
        pop de
        pop hl
        ret

; HL = Z (>= NEAR), DE -> a state: its zpatch shift (count, direction) and
; reciprocal (rtab, from Zn - 256)
oz_norm:
        ld a,h
        ld bc,0                         ; right by 0: as it is
        cp 2
        jr nc,.r
        or a
        jr nz,.n
        push de                         ; Z < 256: left by 8 - log2(L)
        ld e,l
        ld d,high lgtab
        ld a,(de)
        sub 8
        neg
        ld b,a
        ex de,hl
        bsla de,b
        ex de,hl
        pop de
        inc c
        jr .n
.r:     push de                         ; Z >= 512: right by log2(H)
        ld e,a
        ld d,high lgtab
        ld a,(de)
        ld b,a
        ex de,hl
        bsrl de,b
        ex de,hl
        pop de
.n:     ex de,hl                        ; L(E) = Zn - 256
        ld (hl),b
        inc hl
        ld (hl),c
        inc hl
        ld d,high rtab_lo
        ld a,(de)
        ld (hl),a
        inc hl
        inc d
        ld a,(de)
        ld (hl),a
        ret

; HL = X, DE -> a Z's state -> A = screen x (128 + 128 X / Z), clamped to
; 0..255
oz_sx:
        bit 7,h
        jr nz,.n
        call oz_sc
        add a,128
        ret nc
        ld a,255
        ret
.n:     call oz_sc
        ld c,a
        ld a,128
        sub c
        ret nc
        xor a
        ret

; HL = a signed component, DE -> a Z's state -> A = round(|HL| * 128 / Z),
; as scale_comp after zpatch for that Z
oz_sc:
        bit 7,h
        jr z,.p
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
.p:     ex de,hl                        ; DE = |component|, HL -> the state
        ld b,(hl)
        inc hl
        ld a,(hl)
        inc hl
        or a
        jr nz,.l
        bsrl de,b
        jr .s
.l:     bsla de,b
.s:     ld c,(hl)
        inc hl
        ld b,(hl)                       ; BC = R
        ex de,hl
        VP_SCALE
        ret

; Bounds o_xmin/o_xmax/o_ymin against the cover buffer: carry set if hidden
; in every column; otherwise lower the cover to o_tcov over those columns.
occ_test:
        call occ_hidden
        ret c
    IFDEF OCC_PITCHED
        ; pitched: the vertical edges lean on screen, so a building's
        ; outermost columns are only partly covered.  Only the columns of
        ; both its top and its bottom corners are covered from its lowest
        ; top corner down (its outline is convex).  Level flight: the same
        ; columns as its corners (each vertical edge is one column).
        ld a,(pitch)
        or a
        jr z,.lv
        ld a,(o_bx0)
        ld hl,o_tx0
        cp (hl)
        jr nc,.c0
        ld a,(hl)                       ; the larger first column
.c0:    ld e,a
        ld (o_xmin),a
        ld a,(o_bx1)
        ld hl,o_tx1
        cp (hl)
        jr c,.c1
        ld a,(hl)                       ; the smaller last column
.c1:    ld (o_xmax),a
        sub e
        jr c,.none                      ; no column in both: no cover
        inc a
        ld b,a                          ; columns (0 = all 256)
        ld h,high OCC_YBUF
.lv:
    ENDIF
        ld a,(o_tcov)
        cp VIEW_H
        jr nc,.none                     ; covers nothing
        ld c,a
        ld l,e
.u:     ld a,(hl)
        cp c
        jr c,.un                        ; already covered higher up
        ld (hl),c
.un:    inc l
        djnz .u
        ; and OCC_YBUF8 over those columns' groups: a group wholly inside
        ; them now has at most C (its 8, each lowered to C), so its bound
        ; becomes C if that is less.  A group at either end keeps its bound:
        ; still at least its most, as cover only ever goes down.
        ld a,(o_xmin)
        ld e,a
        ld a,(o_xmax)
        ld d,a
        rrca
        rrca
        rrca
        and 31
        ld b,a                          ; last group
        ld a,e
        rrca
        rrca
        rrca
        and 31                          ; first group
        ld l,a
        ld a,b
        sub l
        inc a
        ld b,a                          ; groups
        ld a,l
        add a,low OCC_YBUF8
        ld l,a
        ld h,high OCC_YBUF8
.g:     ld a,l
        sub low OCC_YBUF8
        add a,a
        add a,a
        add a,a                         ; the group's first column
        cp e
        jr c,.edge                      ; starts before the span
        add a,7
        cp d
        jr z,.full
        jr nc,.gn                       ; ends after it
.full:  ld a,(hl)
        cp c
        jr c,.gn                        ; already less
        ld (hl),c
.edge:
.gn:    inc l
        djnz .g
.none:  or a                            ; visible (carry clear)
        ret


; Carry set if o_xmin..o_xmax are all covered from o_ymin or higher.
; Leaves E = o_xmin, B = column count, H = high OCC_YBUF.  Whole groups of 8
; columns are passed at once if their bound (OCC_YBUF8, at least the most of
; the 8) is covered; if it isn't, the 8 are looked at one by one, so the
; answer is exactly the column-by-column one.
occ_hidden:
        ld a,(o_xmin)
        ld e,a
        ld a,(o_xmax)
        sub e
        inc a
        ld b,a                          ; columns (0 = all 256)
        ld a,(o_ymin)
        inc a
        ld c,a                          ; hidden where cover <= ymin
        ld h,high OCC_YBUF
        ld l,e
        ld d,high OCC_YBUF8
        push bc
        ld a,l
        and 7
        jr nz,.one                      ; not at a group's start
.grp:   ld a,b
        dec a                           ; (B = 0: all 256 left)
        cp 7
        jr c,.one                       ; fewer than 8 columns left
        ld a,l
        rrca
        rrca
        rrca                            ; the group (L's low 3 bits are 0)
        add a,low OCC_YBUF8
        ld e,a
        ld a,(de)
        cp c
        jr nc,.g8                       ; maybe not: look at the 8
        ld a,l
        add a,8
        ld l,a
        ld a,b
        sub 8
        ld b,a
        jr nz,.grp
        jr .hid
.g8:    ld e,8                          ; the group's 8, one by one
.g8l:   ld a,(hl)
        cp c
        jr nc,.vis
        inc l
        dec b
        dec e
        jr nz,.g8l
        ld a,b
        or a
        jr nz,.grp
        jr .hid
.one:   ld a,(hl)                       ; one column
        cp c
        jr nc,.vis
        inc l
        dec b
        jr z,.hid
        ld a,l
        and 7
        jr nz,.one
        jr .grp                         ; at a group's start
.hid:   pop bc
        ld a,(o_xmin)
        ld e,a
        scf
        ret
.vis:   pop bc
        ld a,(o_xmin)
        ld e,a
        or a
        ret

; Draw the kept buildings and zombie cells, back to front (list backwards)
occ_draw_list:
        ld hl,(occ_lp)
.l:     ld a,l
        or a
        jr z,.end
        dec l
        ld d,(hl)
        dec l
        ld e,(hl)
        push hl
        ld a,d
        cp $60
        jr c,.bld                       ; < $60: a building record
        ex de,hl
        cp high city_map
        jr nc,.zom
        ld de,city_map-city_col         ; $60-$6F: humans (city_col address)
        add hl,de
        call human_cell
        jr .nx
.zom:   call zombie_cell                ; $70-$7F: zombies (city_map address)
        jr .nx
.bld:   ld h,d                          ; record D
        ld a,e
        add a,OR_VIS
        ld l,a
        ld de,bld_vis
        ld bc,OR_N
        ldir
        ld a,h
        ld (vtx_hi),a
        ld a,l                          ; (bit 7: in the page's upper half)
        and $80
        jr z,.lo
        ld a,FACE_SET2                  ; its corners at +128
.lo:    ld (face_set),a
        call draw_faces
        xor a
        ld (face_set),a
        ld a,high vtx
        ld (vtx_hi),a
.nx:    pop hl
        jr .l
.end:   ld a,VIEW_H                     ; (the next frame's plain drawing,
        ld (bld_cut),a                  ; pitched: nothing cut)
        ret

; A = a row from which every column o_xmin..o_xmax is hidden by the
; buildings recorded so far (nearer: the walk is front to back), so filling
; can stop above it: the most of the OCC_YBUF8 bounds of the groups of 8
; those columns are in (each at least the most of its 8 cover rows, so never
; too high; the end groups' other columns only make it a little lower).
; (VIEW_H: nothing hidden.)
occ_cut:
        ld a,(o_xmax)
        rrca
        rrca
        rrca
        and 31
        ld b,a                          ; last group
        ld a,(o_xmin)
        rrca
        rrca
        rrca
        and 31
        ld l,a                          ; first group
        ld h,high OCC_YBUF8
        ld a,b
        sub l
        inc a
        ld b,a                          ; groups
        ld c,0                          ; the most so far
.lp:    ld a,(hl)
        cp c
        jr c,.n
        ld c,a
        cp VIEW_H
        ret z                           ; (nothing hidden: no higher)
.n:     inc l
        djnz .lp
        ld a,c
        ret
    ENDIF

;==============================================================================
; The figures (zombies, special monsters, humans): their graphics are in
; pages PAGE_GFX0 on (ZPDATA/SPRITES.ZPG, loaded at start-up: gfx_load,
; level_load.asm; tools/spritefile.py has the format), each mapped at $C000
; (slot 6: the game logic's, free while the city is drawn) when needed.
; fig_draw (zombie page) projects the figure and calls spr_lod for its
; size, then spr_draw.
;==============================================================================
        ASSERT GFX_ENTRIES*4 <= 256     ; (the purpose table in one 256 bytes)
        ASSERT GFX_ENTRIES == GFX_ANIMS ; (no vision set: the palettes recolour)
        ASSERT low GFX_DIR == 0
        ASSERT GFX_MIN_H == 3           ; (fig_size draws from 3 rows)
        ASSERT PAGE_GFX0+GFX_PAGES_MAX <= 96    ; (a 1 MB Next has 96 pages)

; The figure's size: fig_anim's frame fig_frame (wrapped round its frames) at
; its projected height zhr (at least GFX_MIN_H, fig_size), one level to every
; row up to the frame's largest (in every vision mode: its palette recolours
; them).  Sets zw, zh, spr_pg and spr_ptr, and leaves the frame's page in
; slot 6.  Carry set if there are no graphics.
spr_lod:
        ld a,(gfx_ok)
        or a
        scf
        ret z
        nextreg LOGIC_MMU,PAGE_GFX0     ; the directory
        ld a,(fig_anim)
        add a,a
        add a,a
        ld l,a
        ld h,high GFX_DIR
        ld c,(hl)                       ; its frames
        inc l
        inc l
        ld e,(hl)
        inc l
        ld d,(hl)                       ; DE -> their list
        ld a,(fig_frame)
.md:    cp c
        jr c,.fr
        sub c
        jr .md
.fr:    ld l,a                          ; 3 bytes each: page, address
        add a,a
        add a,l
        ex de,hl
        add hl,a
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        add a,PAGE_GFX0
        nextreg LOGIC_MMU,a             ; the frame's table of levels
        ex de,hl
        ld a,(zhr)                      ; the level, the largest if past it
        sub GFX_MIN_H
        cp (hl)
        jr c,.lv
        ld a,(hl)
        dec a
.lv:    inc hl
        ld e,a
        add a,GFX_MIN_H
        ld (zh),a
        ld d,4
        mul d,e
        add hl,de                       ; width, page, address
        ld a,(hl)
        ld (zw),a
        inc hl
        ld a,(hl)
        add a,PAGE_GFX0
        ld (spr_pg),a
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (spr_ptr),hl
        or a                            ; (carry clear)
        ret

; Draw the level spr_lod chose: zw x zh, centred on column zsx, top row zy
; (rows off the view skipped: it can be negative or past the bottom),
; mirrored if zface bit 1, each pixel its own colour, or spr_col if that
; isn't 0.  A row is its first drawn pixel's column, a count, then each
; pixel's palette entry (0: transparent).  A row wholly on screen goes
; through the quick loop (patched for mirroring and spr_col); one across a
; screen edge checks each pixel.
spr_draw:
        ld a,(spr_pg)
        nextreg LOGIC_MMU,a
        ld a,(zface)
        bit 1,a
        ld a,$2C                        ; inc l
        jr z,.m
        ld a,$2D                        ; dec l
.m:     ld (.step),a
        ld a,(spr_col)
        or a
        ld a,$77                        ; ld (hl),a
        jr z,.o
        ld a,$71                        ; ld (hl),c
.o:     ld (.put),a
        ld a,(zw)                       ; x0 = centre - w/2
        srl a
        ld e,a
        ld d,0
        ld a,(zsx)
        ld l,a
        ld h,0
        or a
        sbc hl,de
        ld (zx0),hl
        ld de,(spr_ptr)
        ld a,(zh)
        ld (zcnt),a
.row:   ld a,(de)                       ; the row: its first pixel's column
        inc de
        ld (sp_skip),a
        ld a,(de)                       ; and count
        inc de
        ld (sp_len),a
        or a
        jp z,.next                      ; (none)
        ld a,(zy)
        cp VIEW_H
        jp nc,.pass                     ; above or below the view
        ld hl,(zx0)                     ; the first pixel's x: x0 + skip (or
        ld a,(zface)                    ; mirrored x0 + w-1 - skip)
        bit 1,a
        ld a,(sp_skip)
        jr z,.x
        ld b,a
        ld a,(zw)
        dec a
        sub b
.x:     add hl,a
        ld (sp_x),hl
        ld a,(sp_len)                   ; on screen, the whole row?
        dec a
        ld c,a
        ld b,0                          ; BC = count - 1
        ld a,h
        or a
        jr nz,.slow                     ; the first pixel off screen
        ld a,(zface)
        bit 1,a
        jr nz,.xm
        add hl,bc                       ; the last: x + count-1
        jr .xe
.xm:    or a
        sbc hl,bc                       ; mirrored: x - (count-1)
.xe:    ld a,h
        or a
        jr nz,.slow                     ; the last off screen
        ld a,(zy)                       ; the quick loop
        call seg_map                    ; A = y & 31 (keeps BC, DE, L)
        ld h,a
        ld a,(sp_x)
        ld l,a
        ld a,(sp_len)
        ld b,a
        ld a,(spr_col)
        ld c,a
.px:    ld a,(de)
        inc de
        or a
        jr z,.step                      ; (transparent)
.put:   ld (hl),a                       ; (patched: ld (hl),c)
.step:  inc l                           ; (patched: dec l)
        djnz .px
        jr .next
.slow:  ld a,(zy)                       ; across an edge: each pixel's x
        call seg_map
        ld (sp_hi),a
        ld hl,(sp_x)
        ld a,(sp_len)
        ld b,a
.sp:    ld a,(de)
        inc de
        or a
        jr z,.sn
        ld c,a
        ld a,h
        or a
        jr nz,.sn                       ; off screen
        push hl
        ld a,(sp_hi)
        ld h,a
        ld a,(spr_col)
        or a
        jr z,.sc
        ld c,a
.sc:    ld (hl),c
        pop hl
.sn:    ld a,(zface)
        bit 1,a
        jr nz,.sd
        inc hl
        jr .sk
.sd:    dec hl
.sk:    djnz .sp
        jr .next
.pass:  ld a,(sp_len)                   ; off the view: past its pixels
        add a,e
        ld e,a
        adc a,d
        sub e
        ld d,a
.next:  ld hl,zy
        inc (hl)
        ld hl,zcnt
        dec (hl)
        jp nz,.row
        ret

sp_skip:    db 0                        ; spr_draw: the row's first pixel,
sp_len:     db 0                        ;   its count,
sp_x:       dw 0                        ;   the first's x,
sp_hi:      db 0                        ;   and its row's address high byte
