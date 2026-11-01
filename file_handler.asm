;==============================================================================
; Z-POLICE - file handling: loading and saving on the SD card (8K page
; PAGE_FILE, runs at $E000 in slot 7: page it in with nextreg
; CODE_MMU,PAGE_FILE before calling)
;
; General-purpose routines over the esxDOS / NextZXOS file API (RST $08 with
; a function code after it).  Game-specific loading and saving (save games,
; high scores, settings) go on top of these.
;
; The ROM: the divMMC only traps RST $08 while the ROM is paged in at
; $0000-$3FFF, but the game keeps other pages there (slot 0: a Layer 2
; section or the sine table; slot 1: the zombie page).  So every call pages
; the ROM into slots 0 and 1 (fh_rom_in), makes the RST $08, then puts the
; game's pages back (fh_rom_out).  Interrupts are off over the call (the
; game's IM 2 routine is in slot 1, covered by the ROM, and IY is in use and
; slot 2 holds game data, so the ROM's routine must not run either), and
; fh_rom_out turns them back on if they were on.
;
; Rules for callers:
;   * page this in at $E000 (slot 7) first, and call from outside slot 7:
;     resident code or a game logic page in slot 6;
;   * file names and data buffers must be in $4000-$DFFF: not in slots 0-1
;     (the ROM and esxDOS are there during a call) nor slot 7 (this page);
;   * file names end with a 0 byte.
;
; Every routine returns carry clear on success; carry set on failure with
; A = the esxDOS error code.  A file that was opened is closed again on
; any error in fh_load / fh_save.
;
; Routines:
;   fh_init      get the default drive (call once, before the others)
;   fh_open      HL = name, B = mode (FA_*)      -> A = handle
;   fh_close     A = handle
;   fh_read      A = handle, HL = address, BC = length -> BC = bytes read
;   fh_write     A = handle, HL = address, BC = length -> BC = bytes written
;   fh_seek      A = handle, BCDE = offset, L = SEEK_* -> BCDE = position
;   fh_size      A = handle                      -> BCDE = file size
;   fh_load      HL = name, DE = address, BC = most bytes -> BC = bytes read
;   fh_save      HL = name, DE = address, BC = length (created / replaced)
;   fh_exists    HL = name -> carry clear if the file exists
;   fh_delete    HL = name
;==============================================================================

; esxDOS function codes (the byte after RST $08)
M_GETSETDRV     equ $89             ; A = 0: get the default drive
F_OPEN          equ $9A
F_CLOSE         equ $9B
F_READ          equ $9D
F_WRITE         equ $9E
F_SEEK          equ $9F
F_FSTAT         equ $A1
F_UNLINK        equ $AD

; F_OPEN modes (B)
FA_READ         equ $01             ; read
FA_WRITE        equ $02             ; write
FA_OPEN_EX      equ $00             ; open an existing file only
FA_OPEN_AL      equ $08             ; open, or create if it doesn't exist
FA_CREATE_NEW   equ $04             ; create, fail if it exists
FA_CREATE_AL    equ $0C             ; create, replacing any existing file
FA_OVERWRITE    equ FA_WRITE|FA_CREATE_AL   ; for saving a whole file

; F_SEEK modes (L)
SEEK_START      equ 0               ; from the start of the file
SEEK_FWD        equ 1               ; forwards from the current position
SEEK_BACK       equ 2               ; backwards from the current position

FSTAT_SIZE      equ 7               ; F_FSTAT buffer: file size, 4 bytes
FSTAT_LEN       equ 11              ; F_FSTAT buffer length

ESX_DEFAULT     equ '*'             ; drive: the default drive

; An esxDOS call: the ROM in at $0000-$3FFF for the RST $08, the game's
; pages back after.  Registers in and out are the function's own; flags
; and A come back from esxDOS (carry set = error, A = code).
        MACRO ESXDOS fn
        call fh_rom_in
        rst $08
        db fn
        call fh_rom_out
        ENDM

;------------------------------------------------------------------------------
; Get the default drive into fh_drive (else the '*' default is used)
;------------------------------------------------------------------------------
fh_init:
        xor a                           ; A = 0: get
        ESXDOS M_GETSETDRV
        ret c
        ld (fh_drive),a
        ret

;------------------------------------------------------------------------------
; HL -> file name, B = mode (FA_*) -> A = handle (also in fh_handle)
;------------------------------------------------------------------------------
fh_open:
        push ix
        push hl
        pop ix                          ; IX = HL = the name (both
        ld a,(fh_drive)                 ; conventions: programs, dot
        ESXDOS F_OPEN                   ; commands)
        pop ix
        ret c
        ld (fh_handle),a
        ret

;------------------------------------------------------------------------------
; A = handle: close it
;------------------------------------------------------------------------------
fh_close:
        ESXDOS F_CLOSE
        ret

;------------------------------------------------------------------------------
; A = handle, HL = address, BC = length -> BC = bytes read (fewer at the end
; of the file)
;------------------------------------------------------------------------------
fh_read:
        push ix
        push hl
        pop ix
        ESXDOS F_READ
        pop ix
        ret

;------------------------------------------------------------------------------
; A = handle, HL = address, BC = length -> BC = bytes written
;------------------------------------------------------------------------------
fh_write:
        push ix
        push hl
        pop ix
        ESXDOS F_WRITE
        pop ix
        ret

;------------------------------------------------------------------------------
; A = handle, BCDE = offset (32-bit), L = mode (SEEK_*) -> BCDE = position
;------------------------------------------------------------------------------
fh_seek:
        push ix
        push hl
        push hl
        pop ix                          ; mode in IXL (programs) and L
        ESXDOS F_SEEK
        pop hl
        pop ix
        ret

;------------------------------------------------------------------------------
; A = handle -> BCDE = file size (32-bit)
;------------------------------------------------------------------------------
fh_size:
        push ix
        push hl
        ld hl,fh_stat
        push hl
        pop ix
        ESXDOS F_FSTAT
        jr c,.x
        ld hl,(fh_stat+FSTAT_SIZE)
        ex de,hl                        ; DE = low word
        ld hl,(fh_stat+FSTAT_SIZE+2)
        ld b,h                          ; BC = high word
        ld c,l
        or a
.x:     pop hl
        pop ix
        ret

;------------------------------------------------------------------------------
; Load a file: HL -> name, DE = address, BC = most bytes to read
; -> BC = bytes read.  The file is opened, read and closed.
;------------------------------------------------------------------------------
fh_load:
        push de
        push bc
        ld b,FA_READ|FA_OPEN_EX
        call fh_open
        pop bc
        pop hl                          ; HL = address
        ret c                           ; couldn't open (A = error)
        call fh_read
        jr fh_done                      ; close it, keeping any error

;------------------------------------------------------------------------------
; Save a file: HL -> name, DE = address, BC = length.  The file is created,
; replacing any file of that name.
;------------------------------------------------------------------------------
fh_save:
        push de
        push bc
        ld b,FA_OVERWRITE
        call fh_open
        pop bc
        pop hl
        ret c
        call fh_write
        ; fall through

; After a read / write on fh_handle: close the file.  Carry and A as from
; that read / write if it failed, else as from the close.
fh_done:
        push af
        ld a,(fh_handle)
        call fh_close
        jr c,.cerr
        pop af                          ; the read / write's result
        ret
.cerr:  pop hl                          ; the close failed: if the read /
        bit 0,l                         ; write had already failed, report
        jr z,.ce                        ; that, else the close's error
        ld a,h
.ce:    scf
        ret

;------------------------------------------------------------------------------
; HL -> name: carry clear if the file exists (it can be opened to read)
;------------------------------------------------------------------------------
fh_exists:
        ld b,FA_READ|FA_OPEN_EX
        call fh_open
        ret c
        jp fh_close

;------------------------------------------------------------------------------
; HL -> name: delete the file
;------------------------------------------------------------------------------
fh_delete:
        push ix
        push hl
        pop ix
        ld a,(fh_drive)
        ESXDOS F_UNLINK
        pop ix
        ret

;------------------------------------------------------------------------------
; Page the ROM into slots 0 and 1 for RST $08, remembering the game's pages
; (fh_rom_in), and put them back (fh_rom_out).  Interrupts are off in
; between (the ROM covers the interrupt routine, slot 1), and back on after
; if they were on before.  Both keep every register and flag.
;------------------------------------------------------------------------------
fh_rom_in:
        push af
        ld a,i                          ; P/V: interrupts on (IFF2)
        di
        ld a,0
        jp po,.off
        inc a
.off:   ld (fh_ints),a
        push bc
        ld bc,$243B
        ld a,MMU_SLOT_0_REGISTER        ; slot 0's page now
        out (c),a
        inc b
        in a,(c)
        ld (fh_mmu0),a
        dec b
        ld a,MMU_SLOT_1_REGISTER        ; slot 1's
        out (c),a
        inc b
        in a,(c)
        ld (fh_mmu1),a
        nextreg MMU_SLOT_0_REGISTER,PAGE_ROM
        nextreg MMU_SLOT_1_REGISTER,PAGE_ROM
        pop bc
        pop af
        ret

fh_rom_out:
        di                              ; (in case esxDOS enabled them)
        push af
        ld a,(fh_mmu0)
        nextreg MMU_SLOT_0_REGISTER,a
        ld a,(fh_mmu1)
        nextreg MMU_SLOT_1_REGISTER,a
        ld a,(fh_ints)
        or a
        jr z,.off
        pop af
        ei                              ; on again, as they were
        ret
.off:   pop af
        ret

;==============================================================================
; File handler data
;==============================================================================
fh_drive:   db ESX_DEFAULT              ; drive for F_OPEN (fh_init)
fh_handle:  db 0                        ; the last file opened
fh_mmu0:    db 0                        ; the game's slot 0 / 1 pages during
fh_mmu1:    db 0                        ; an esxDOS call
fh_ints:    db 0                        ; 1: interrupts were on before it
fh_stat:    ds FSTAT_LEN                ; F_FSTAT buffer (fh_size)
