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
;   * the city's palette and sky colour into the Layer 2 palette;
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
LEVEL_VERSION   equ 2               ; the files' format versions (+4): the
CITY_VERSION    equ 1               ;   level file's 2 (specials by wave)
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
        nextreg $43,%00010000           ; edit Layer 2 palette 0, auto-inc
        nextreg $40,0
        ld hl,ll_cbuf+CTF_PAL
        ld b,0                          ; 256 entries
.pl:    ld a,(hl)
        inc hl
        nextreg $44,a                   ; RRRGGGBB
        ld a,(hl)
        inc hl
        nextreg $44,a                   ; low blue bit
        djnz .pl
        nextreg $40,SKY_COL
        ld a,(ll_cbuf+CTF_SKY)
        nextreg $44,a
        ld a,(ll_cbuf+CTF_SKY+1)
        nextreg $44,a
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

;==============================================================================
; Level loading data
;==============================================================================
ll_level:   db "ZPDATA/LEVEL00.ZPL", 0  ; digits at +12, +13
ll_city:    db "ZPDATA/CITY00.ZPC", 0   ; digits at +11, +12
ll_lmagic:  db "ZPLV"
ll_cmagic:  db "ZPCY"
ll_lbuf:    ds LVF_MAX                  ; the level file
ll_cbuf:    ds CTF_DATA                 ; the city file's header and palette
