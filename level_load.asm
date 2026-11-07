;==============================================================================
; Z-POLICE - level loading (8K page PAGE_LEVEL, game logic: runs at $C000 in
; slot 6; it pages the file handler, PAGE_FILE, into slot 7)
;
; Each level is a file, ZPDATA/LEVELnn.ZPL, naming its city, ZPDATA/CITYnn.ZPC
; (both made by gentables.py; the formats are described there).  A city is
; played for several levels.  load_level reads both:
;   * the level record into level_cur (levels.asm): city name, zombie and
;     wave counts, the draw distance, ...;
;   * the city into the city bank (page 7, slot 3): city_col at $6000 and
;     city_map at $7000, one 8K read;
;   * the level's own map changes (x, z, cell code, city_col), for hand-made
;     layouts;
;   * the city's palette and sky colour into the Layer 2 palette, then the
;     level's own palette over it, if it has one (ZPDATA/LEVELnn.ZPP);
;   * view_r / dot_r from the draw distance (2..VIEW_R tiles).
; Loading the map also clears every cell's zombie and human marks.  The
; files must be in the ZPDATA folder beside zpolice.nex on the SD card.
;==============================================================================

; Level file
LVF_CITY        equ 5               ; city number
LVF_REC         equ 6               ; the level record (LV_SIZE bytes)
LVF_NCHG        equ LVF_REC+LV_SIZE ; number of map changes,
LVF_CHG         equ LVF_NCHG+1      ; then x, z, cell code, city_col each
LVF_CHG_MAX     equ 64
LVF_MAX         equ LVF_CHG+4*LVF_CHG_MAX
; City file
CTF_SKY         equ 14              ; sky colour: RRRGGGBB, low blue bit
CTF_PAL         equ 32              ; the palette, 256 pairs
CTF_DATA        equ CTF_PAL+512     ; then city_col, city_map
; Level palette file (ZPDATA/LEVELnn.ZPP, optional: tools/levelpal.py)
LPF_PAL         equ 8               ; the palette, 256 pairs
LPF_SIZE        equ LPF_PAL+512
LEVEL_VERSION   equ 2               ; the files' format versions (+4): the
CITY_VERSION    equ 1               ;   level file's 2 (specials by wave)
LPAL_VERSION    equ 1
; Vision palette file (ZPDATA/LEVELnn.ZPV: tools/visionpal.py)
VPF_PAL         equ 8               ; 4 palettes (VM_MODES), 256 pairs each
VPF_SIZE        equ VPF_PAL+4*512
VPAL_VERSION    equ 1
LDERR_BADFILE   equ 255             ; error code: not a valid file

;------------------------------------------------------------------------------
; A = level (1..99): load it.  Carry set on failure, A = the esxDOS error
; code or LDERR_BADFILE.  Leaves PAGE_FILE in slot 7.
;------------------------------------------------------------------------------
load_level:
        ld c,'0'-1                      ; the level's two digits
.tens:  inc c
        sub 10
        jr nc,.tens
        add a,'0'+10
        ld (ll_level+13),a
        ld a,c
        ld (ll_level+12),a
        nextreg CODE_MMU,PAGE_FILE
        ld hl,ll_level                  ; the level file
        ld de,ll_lbuf
        ld bc,LVF_MAX
        call fh_load
        ret c
        ld hl,ll_lbuf
        ld de,ll_lmagic
        ld c,LEVEL_VERSION
        call ll_check
        ret c
        ld hl,ll_lbuf+LVF_REC           ; its record
        ld de,level_cur
        ld bc,LV_SIZE
        ldir
        ld a,(ll_lbuf+LVF_CITY)         ; its city file: two digits
        ld c,'0'-1
.ctens: inc c
        sub 10
        jr nc,.ctens
        add a,'0'+10
        ld (ll_city+12),a
        ld a,c
        ld (ll_city+11),a
        ld hl,ll_city
        ld b,FA_READ|FA_OPEN_EX
        call fh_open
        ret c
        ld hl,ll_cbuf                   ; header and palette
        ld bc,CTF_DATA
        call fh_read
        jp c,.cerr
        ld a,(fh_handle)                ; city_col and city_map: the whole
        ld hl,city_col                  ; city bank, in one read
        ld bc,2*GRID*GRID
        call fh_read
        jp c,.cerr
        ld a,b                          ; all of it?
        cp high (2*GRID*GRID)
        ld a,LDERR_BADFILE
        scf
        jp nz,.cerr
        ld a,(fh_handle)
        call fh_close
        ret c
        ld hl,ll_cbuf
        ld de,ll_cmagic
        ld c,CITY_VERSION
        call ll_check
        ret c
        ; the level's map changes
        ld a,(ll_lbuf+LVF_NCHG)
        cp LVF_CHG_MAX+1
        ld a,LDERR_BADFILE
        ccf
        ret c
        ld a,(ll_lbuf+LVF_NCHG)
        or a
        jr z,.pal
        ld b,a
        ld ix,ll_lbuf+LVF_CHG
.chg:   ld l,(ix+1)                     ; row z
        ld h,0
        ROWOFS
        ld a,(ix+0)                     ; column x
        add hl,a
        ld de,city_map
        add hl,de
        ld a,(ix+2)
        ld (hl),a                       ; the cell code
        ld de,city_col-city_map
        add hl,de
        ld a,(ix+3)
        ld (hl),a                       ; and its colour
        ld de,4
        add ix,de
        djnz .chg
.pal:   ; the city's palette (the first Layer 2 palette), then its sky
        ld hl,ll_cbuf+CTF_PAL
        call ll_palette
        nextreg $40,SKY_COL
        ld a,(ll_cbuf+CTF_SKY)
        nextreg $44,a
        ld a,(ll_cbuf+CTF_SKY+1)
        nextreg $44,a
        ; the level's own palette, if it has one (ZPDATA/LEVELnn.ZPP, from
        ; levels/LEVELnn_PAL.json): in place of the city's.  None, or not a
        ; whole palette file: the city's stays.  (Into ll_cbuf: the city's
        ; header is done with.)
        ld a,(ll_level+12)
        ld (ll_lpal+12),a
        ld a,(ll_level+13)
        ld (ll_lpal+13),a
        ld hl,ll_lpal
        ld de,ll_cbuf
        ld bc,LPF_SIZE
        call fh_load
        jr c,.view                      ; (none)
        ld hl,-LPF_SIZE
        add hl,bc
        ld a,h
        or l
        jr nz,.view                     ; (not all of it)
        ld hl,ll_cbuf
        ld de,ll_pmagic
        ld c,LPAL_VERSION
        call ll_check
        jr c,.view
        ld hl,ll_cbuf+LPF_PAL
        call ll_palette
.view:  call vis_load                   ; its vision palettes
        ; the draw distance, 2..VIEW_R tiles; the ground dots one less
        ld a,(level_cur+LV_VIEW_R)
        cp 2
        jr nc,.v1
        ld a,2
.v1:    cp VIEW_R+1
        jr c,.v2
        ld a,VIEW_R
.v2:    ld (view_r),a
        dec a
        ld (dot_r),a
        or a                            ; carry clear: loaded
        ret
.cerr:  push af                         ; an error with the city file open:
        ld a,(fh_handle)                ; close it, keep the error
        call fh_close
        pop af
        scf
        ret

;------------------------------------------------------------------------------
; The vision modes' palettes (tools/visionpal.py has the format):
; ZPDATA/LEVELnn.ZPV, the level's 4 palettes (normal, night vision green,
; night vision monochrome, thermal), kept in ll_vbuf.  vis_ok = 1 if it is
; there and whole (without it, only normal vision).  Every level starts in
; normal vision (vision_mode 0).
; (load_level: the file handler in slot 7.)
;------------------------------------------------------------------------------
vis_load:
        xor a
        ld (vis_ok),a
        ld a,(ll_level+12)
        ld (ll_vpal+12),a
        ld a,(ll_level+13)
        ld (ll_vpal+13),a
        ld hl,ll_vpal
        ld de,ll_vbuf
        ld bc,VPF_SIZE+1                ; (one more: a longer file isn't one)
        call fh_load
        jr c,.none
        ld hl,-VPF_SIZE
        add hl,bc
        ld a,h
        or l
        jr nz,.none                     ; (not all of it)
        ld hl,ll_vbuf
        ld de,ll_vmagic
        ld c,VPAL_VERSION
        call ll_check
        jr c,.none
        ld a,1
        ld (vis_ok),a
.none:  xor a                           ; each level starts in normal vision
        ld (vision_mode),a              ; (its palette is in already)
        ret

; K_VISION pressed (main_loop, this page in slot 6): the next vision mode
; the VTOL has (vision_owned), or back to normal after the last; its
; palette into the Layer 2 palette.  Nothing without the level's vision
; palettes, or with no vision mode.
vis_cycle:
        ld a,(vis_ok)
        or a
        ret z
        ld a,(vision_owned)
        and (1<<(VM_MODES-1))-1
        ret z                           ; none yet
        ld a,(vision_mode)
.nx:    inc a
        cp VM_MODES
        jr nc,.norm                     ; past the last: normal
        ld b,a                          ; has it?  bit (mode - 1)
        ld c,1
.bit:   dec b
        jr z,.tst
        sla c
        jr .bit
.tst:   ld b,a
        ld a,(vision_owned)
        and c
        ld a,b
        jr z,.nx
        jr .set
.norm:  xor a
.set:   ld (vision_mode),a
        ; fall through

; The vision mode's palette (vision_mode, 0..VM_MODES-1, from ll_vbuf) into
; the Layer 2 palette
vis_apply:
        ld a,(vision_mode)
        add a,a                         ; * 512: high byte * 2
        ld h,a
        ld l,0
        ld de,ll_vbuf+VPF_PAL
        add hl,de
        ; fall through
        ASSERT VM_MODES*512 == VPF_SIZE-VPF_PAL

; HL -> 256 palette pairs (RRRGGGBB, low blue bit): into Layer 2 palette 0
ll_palette:
        nextreg $43,%00010000           ; edit Layer 2 palette 0, auto-inc
        nextreg $40,0
        ld b,0                          ; 256 entries
.pl:    ld a,(hl)
        inc hl
        nextreg $44,a                   ; RRRGGGBB
        ld a,(hl)
        inc hl
        nextreg $44,a                   ; low blue bit
        djnz .pl
        ret

; HL -> a file's first bytes, DE -> its 4-byte magic: carry clear if they
; match and the version byte after them is C (LEVEL_ / CITY_VERSION), else carry set
; and A = LDERR_BADFILE
ll_check:
        ld b,4
.lp:    ld a,(de)
        cp (hl)
        jr nz,.bad
        inc de
        inc hl
        djnz .lp
        ld a,(hl)
        cp c
        ret z                           ; (carry clear)
.bad:   ld a,LDERR_BADFILE
        scf
        ret

;------------------------------------------------------------------------------
; At start-up (this page in slot 6, the file handler set up): the figures'
; graphics, ZPDATA/SPRITES.ZPG (gengraphics.py; tools/spritefile.py has the
; format), into pages PAGE_GFX0 on, each read through slot 4 (the ULA
; screen's, put back after: the screen still shows).  gfx_ok = 1 if they are
; all there and fit this game (magic, version, pages, purposes); else 0, and
; the figures aren't drawn.  Leaves the file handler in slot 7.
;------------------------------------------------------------------------------
gfx_load:
        xor a
        ld (gfx_ok),a
        nextreg CODE_MMU,PAGE_FILE
        ld hl,gfx_name
        ld b,FA_READ|FA_OPEN_EX
        call fh_open
        ret c                           ; (none)
        ld hl,ll_cbuf                   ; the header
        ld bc,GFX_HEADER
        call fh_read
        jr c,.cl
        ld hl,ll_cbuf
        ld de,gfx_magic
        ld c,GFX_VERSION
        call ll_check
        jr c,.cl
        ld a,(ll_cbuf+5)                ; pages: 1..GFX_PAGES_MAX
        or a
        jr z,.cl
        cp GFX_PAGES_MAX+1
        jr nc,.cl
        ld (gl_n),a
        ld a,(ll_cbuf+6)                ; the game's purposes, and their
        cp GFX_ENTRIES                  ;   (no vision set)
        jr nz,.cl
        ld a,PAGE_GFX0
        ld (gl_pg),a
.pg:    ld a,(gl_pg)                    ; each page, 8K, through slot 4
        nextreg ULA_MMU,a
        ld a,(fh_handle)
        ld hl,ULA_ADDR
        ld bc,MEMBANK_SIZE
        call fh_read
        nextreg ULA_MMU,PAGE_ULA0       ; (the flags kept)
        jr c,.cl
        ld a,b
        cp high MEMBANK_SIZE
        jr nz,.cl                       ; (not all of it)
        ld hl,gl_pg
        inc (hl)
        ld hl,gl_n
        dec (hl)
        jr nz,.pg
        ld a,1
        ld (gfx_ok),a
.cl:    ld a,(fh_handle)
        jp fh_close

gfx_name:   db "ZPDATA/SPRITES.ZPG", 0
gfx_magic:  db "ZPGF"
gl_pg:      db 0                        ; gfx_load: the page being read,
gl_n:       db 0                        ;   pages left
        ASSERT GFX_HEADER <= CTF_DATA
        ASSERT MEMBANK_SIZE == $2000

;==============================================================================
; Level loading data
;==============================================================================
ll_level:   db "ZPDATA/LEVEL00.ZPL", 0  ; digits at +12, +13
ll_city:    db "ZPDATA/CITY00.ZPC", 0   ; digits at +11, +12
ll_lpal:    db "ZPDATA/LEVEL00.ZPP", 0  ; digits at +12, +13 (as ll_level's)
ll_lmagic:  db "ZPLV"
ll_cmagic:  db "ZPCY"
ll_pmagic:  db "ZPPL"
ll_vpal:    db "ZPDATA/LEVEL00.ZPV", 0  ; digits at +12, +13 (as ll_level's)
ll_vmagic:  db "ZPVS"
ll_vbuf:    ds VPF_SIZE+1               ; the level's vision palettes (vis_load)
ll_lbuf:    ds LVF_MAX                  ; the level file
ll_cbuf:    ds CTF_DATA                 ; the city file's header and palette;
                                        ; then the level's palette file
        ASSERT LPF_SIZE <= CTF_DATA
