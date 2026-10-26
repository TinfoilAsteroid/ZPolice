;==============================================================================
; Z-POLICE - hardware sprites, Layer 3 (8K page PAGE_SPRITES, runs at $E000
; in slot 7: page it in with nextreg CODE_MMU,PAGE_SPRITES before calling)
;
; The Next has 128 hardware sprites, each 16x16 pixels from a pattern in the
; sprite pattern memory (16K, separate from the Z80's: 64 8-bit patterns of
; 256 bytes, one byte per pixel, row by row).  A pattern byte is an index
; into the sprite palette; SPR_TRANS ($E3, NextReg $4B) is transparent.  The
; sprite palette starts as the identity, so until spr_palette changes it a
; pattern byte is simply its RRRGGGBB colour.
;
; Sprites are drawn above Layer 2 and the ULA (priority S U L) and, with
; NextReg $15 bit 1 set, over the border as well, so the sprite screen is
; 320 x 256 pixels:
;
;     x 0..319, y 0..255;  (SPR_SCREEN_X, SPR_SCREEN_Y) = (32, 32) is the top
;     left of the 256x192 Layer 2 / ULA screen, (288, 224) its bottom right
;
; A sprite's position is its top left pixel.  Coordinates are 9 bits and
; wrap round at 512, so they may be negative (two's complement): a sprite at
; x = -8 shows its right half at the left edge.  With overlapping sprites,
; the higher numbered one is drawn on top.
;
; Use: sprites_init once (start-up), load patterns with spr_patterns or
; from a sprite bank (sprite_data.asm: page the bank into slot 7 and call
; its spr_load_bank, from outside slot 7), and a palette with spr_palette
; if wanted, then set up sprites in the shadow
; table with spr_set / spr_pos / spr_pattern / spr_flags / spr_scale /
; spr_hide / spr_show / spr_hide_all, and copy the table to the hardware
; once a frame with spr_update.  The table holds the first SPR_COUNT sprites;
; the rest stay hidden.
;
; Attributes, SPR_ATTR (5) bytes a sprite, kept in the table as they are
; sent (the 5-byte form):
;   +0  x bits 0-7
;   +1  y bits 0-7
;   +2  bits 7-4 palette offset (added to the pattern byte's top nibble),
;       bit 3 x mirror, 2 y mirror, 1 rotate 90 degrees clockwise, 0 x bit 8
;   +3  bit 7 visible, bit 6 = 1 (byte +4 follows), bits 5-0 pattern
;   +4  bits 4-3 x scale, bits 2-1 y scale (0..3 = x1, x2, x4, x8), 0 y bit 8
;==============================================================================

SPR_COUNT       equ 32          ; sprites in the shadow table (max 128)
SPR_HW          equ 128         ; hardware sprites
SPR_ATTR        equ 5           ; attribute bytes per sprite
SPR_PATTERNS    equ 64          ; 8-bit 16x16 patterns in pattern memory
SPR_SIZE        equ 16          ; pixels, each way (at scale x1)
SPR_SCREEN_X    equ 32          ; sprite coordinates of the 256x192
SPR_SCREEN_Y    equ 32          ; screen's top left pixel
SPR_TRANS       equ $E3         ; transparent pattern byte (NextReg $4B)

SPRF_PAL        equ $10         ; flags (attribute +2): palette offset x 16,
SPRF_XMIRROR    equ $08         ; mirror left-right,
SPRF_YMIRROR    equ $04         ; mirror top-bottom,
SPRF_ROT        equ $02         ; rotate 90 degrees clockwise

SPR_SLOT_PORT   equ $303B       ; write: select sprite / pattern slot
SPR_ATTR_PORT   equ $57         ; write: attributes, from the selected sprite
SPR_PAT_PORT    equ $5B         ; write: pattern bytes, from the selected slot

;------------------------------------------------------------------------------
; Start-up: sprites on, shown over the border too (the full 320 x 256),
; priority S U L; the transparent index; every hardware sprite hidden and the shadow table cleared (all hidden,
; pattern 0, at 0,0).
;------------------------------------------------------------------------------
sprites_init:
        nextreg $15,%00001011           ; priority S U L, sprites over the
                                        ; border (bit 1), visible (bit 0)
        nextreg $4B,SPR_TRANS
        ld bc,SPR_SLOT_PORT             ; from sprite 0, the 4-byte form
        xor a                           ; (+3 bit 6 clear): all hidden
        out (c),a
        ld c,SPR_ATTR_PORT
        ld de,SPR_HW*4
.hw:    out (c),a
        dec de
        ld a,d
        or e
        ld a,0
        jr nz,.hw
        ld hl,spr_shadow
        ld b,SPR_COUNT
.sh:    ld (hl),a                       ; x, y, flags 0
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),$40                     ; hidden, 5-byte form, pattern 0
        inc hl
        ld (hl),a                       ; scale x1
        inc hl
        djnz .sh
        ; fall through: send it

;------------------------------------------------------------------------------
; Copy the shadow table to sprites 0..SPR_COUNT-1.  Once a frame, after the
; changes (best just after the frame flip, so a move doesn't show half done).
;------------------------------------------------------------------------------
spr_update:
        ld bc,SPR_SLOT_PORT
        xor a
        out (c),a                       ; from sprite 0
        ld hl,spr_shadow
        ld c,SPR_ATTR_PORT
        ld d,SPR_COUNT
.lp:    ld b,SPR_ATTR
        otir
        dec d
        jr nz,.lp
        ret

;------------------------------------------------------------------------------
; Load B 8-bit patterns (256 bytes each) from HL into pattern memory, from
; pattern A (0..63).  HL ends past them.
;------------------------------------------------------------------------------
spr_patterns:
        ld d,b
        ld bc,SPR_SLOT_PORT
        out (c),a
        ld c,SPR_PAT_PORT
.lp:    ld b,0                          ; 256 bytes
        otir
        dec d
        jr nz,.lp
        ret

;------------------------------------------------------------------------------
; Load B colours (8-bit RRRGGGBB) from HL into the sprite palette, from
; index A.  (It starts as the identity: only needed for other colours.)
;------------------------------------------------------------------------------
spr_palette:
        nextreg $43,%00100000           ; edit the first sprite palette
        nextreg $40,a
.lp:    ld a,(hl)
        nextreg $41,a
        inc hl
        djnz .lp
        ret

;------------------------------------------------------------------------------
; Sprite A (0..SPR_COUNT-1) in the shadow table.  BC = x, DE = y (sprite
; screen, signed 9 bits), H = pattern (0..63), L = flags (SPRF_*).  Shows it.
;------------------------------------------------------------------------------
spr_set:
        ld (spr_pf),hl
        push af
        call spr_pos
        pop af
        call spr_addr
        inc hl
        inc hl                          ; +2: the flags, keeping x bit 8
        ld a,(spr_pf)
        and $FE
        ld e,a
        ld a,(hl)
        and 1
        or e
        ld (hl),a
        inc hl                          ; +3: visible, 5-byte form, pattern
        ld a,(spr_pf+1)
        and $3F
        or $C0
        ld (hl),a
        ret

; Sprite A: move to BC = x, DE = y (signed 9 bits)
spr_pos:
        push de
        call spr_addr
        pop de
        ld (hl),c                       ; +0 x bits 0-7
        inc hl
        ld (hl),e                       ; +1 y bits 0-7
        inc hl
        ld a,b                          ; +2 bit 0: x bit 8
        and 1
        ld b,a
        ld a,(hl)
        and $FE
        or b
        ld (hl),a
        inc hl
        inc hl
        ld a,d                          ; +4 bit 0: y bit 8
        and 1
        ld d,a
        ld a,(hl)
        and $FE
        or d
        ld (hl),a
        ret

; Sprite A: pattern E (0..63), keeping whether it is shown
spr_pattern:
        call spr_addr
        ld a,l
        add a,3
        ld l,a
        ld a,(hl)
        and $C0
        or e
        ld (hl),a
        ret

; Sprite A: flags E (SPRF_*: palette offset, mirrors, rotation)
spr_flags:
        call spr_addr
        inc hl
        inc hl
        ld a,e
        and $FE
        ld e,a
        ld a,(hl)
        and 1
        or e
        ld (hl),a
        ret

; Sprite A: scale E across, D down (0..3 = x1, x2, x4, x8)
spr_scale:
        push de
        call spr_addr
        pop de
        ld a,l
        add a,4
        ld l,a
        ld a,e
        and 3
        rlca
        rlca
        ld e,a
        ld a,d
        and 3
        or e
        rlca                            ; x scale bits 4-3, y scale 2-1
        ld e,a
        ld a,(hl)
        and 1                           ; (keep y bit 8)
        or e
        ld (hl),a
        ret

; Sprite A: hide / show
spr_hide:
        call spr_addr3
        res 7,(hl)
        ret
spr_show:
        call spr_addr3
        set 7,(hl)
        ret

; Hide every sprite in the table
spr_hide_all:
        ld hl,spr_shadow+3
        ld de,SPR_ATTR
        ld b,SPR_COUNT
.lp:    res 7,(hl)
        add hl,de
        djnz .lp
        ret

; A = sprite -> HL -> its attributes in the table, +3 for spr_addr3.
; (The table doesn't cross a 256-byte boundary, so +n is just L + n.)
spr_addr3:
        call spr_addr
        inc hl
        inc hl
        inc hl
        ret
spr_addr:
        ld d,a
        ld e,SPR_ATTR
        mul d,e
        ld hl,spr_shadow
        add hl,de
        ret

;==============================================================================
; Sprite data
;==============================================================================
; The patterns themselves are in the sprite banks (sprite_data.asm).
; Bank 0 has the human status sprites, loaded as patterns 0-3 by
; sprites_init, after the HUD's passenger markers:
;   HSPR_FIELD   0  waiting in the field, not yet rescued: an empty square
;   HSPR_ABOARD  1  aboard the VTOL: a person sitting in a chair
;   HSPR_SAVED   2  rescued: a green person standing
;   HSPR_DEAD    3  dead: a white person with a red cross over them

spr_pf:     dw 0                        ; spr_set: flags, pattern
        ALIGN 256
spr_shadow: ds SPR_COUNT*SPR_ATTR       ; attributes, as sent (5-byte form)
        ASSERT SPR_COUNT*SPR_ATTR <= 256
