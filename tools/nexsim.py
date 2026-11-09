"""Minimal Z80N emulator for headless testing of zpolice.nex.

Runs the NEX, captures every Layer 2 buffer flip (NextReg $12 write) to PNG,
and reports approximate T-states per frame. Only what the game needs is
modelled: 8K MMU paging, NextReg writes/reads, keyboard port $FE, raster
line read ($1E/$1F is derived from the T-state count, so vsync waits and
raster timing behave as on hardware).

usage: python tools/nexsim.py zpolice.nex outdir frames [keyscript]
  keyscript: comma list of "frame:keys", keys from QWERTASDFG held from that
  frame on (e.g. "0:Q,20:,30:F" = hold Q at frame 0, release at 20, F at 30)
"""
import os
import re
import struct
import sys
import zlib

# ----------------------------------------------------------------------------
# Flags
FC, FN, FPV, F3, FH, F5, FZ, FS = 1, 2, 4, 8, 16, 32, 64, 128
PARITY = [0] * 256
for _i in range(256):
    PARITY[_i] = FPV if bin(_i).count("1") % 2 == 0 else 0
SZP = [(_i & FS) | (FZ if _i == 0 else 0) | PARITY[_i] for _i in range(256)]

KEYROWS = {  # half-row address byte -> keys bits 0..4
    0xFB: "QWERT",
    0xFD: "ASDFG",
    0x7F: " $MNB",                      # SPACE, SYM SHIFT, M, N, B
    0xEF: "09876",
    0xF7: "12345",
    0xDF: "POIUY",
    0xBF: "~LKJH",                      # ENTER, L, K, J, H
    0xFE: "^ZXCV",                      # CAPS SHIFT, Z, X, C, V
}


# Estimated zxnDMA cost per byte for a memory->memory transfer (CPU halted).
DMA_T_PER_BYTE = int(os.environ.get("DMA_T", "2"))
DDMA_FILL = 0x08                                        # DMA+ mode ($DF) flag


# Video timing at 28MHz, 50Hz: 312 lines of 1792 T (raster from T-states).
T_PER_LINE = 1792
LINES_PER_FRAME = 312


class Halt(Exception):
    pass


class Cpu:
    def __init__(self):
        self.pages = {}
        self.mmu = [0xFF, 0xFF, 10, 11, 4, 5, 0, 1]
        self.slot = [None] * 8
        for s in range(8):
            self._map(s, self.mmu[s])
        self.r = [0] * 8          # B C D E H L F A  (index 6 = F)
        self.ix = self.iy = 0
        self.sp = self.pc = 0
        self.alt = [0] * 8
        self.t = 0
        self.nr_sel = 0
        self.nextreg = {}
        self.keys = set()
        self.joy = {}                   # Kempston / Mega Drive ports $1F, $37: byte, 1 = pressed
        self.on_flip = None
        self.iff = 0
        self.palettes = {}              # sel -> {index: 9-bit RGB333}
        self.l2clip, self.l2clip_i = [0, 255, 0, 191], 0
        self.border = 0
        # hardware sprites: 128 x 5 attribute bytes, 16K pattern memory
        self.spr_attr = [[0] * 5 for _ in range(128)]
        self.spr_pat = bytearray(16384)
        self.spr_slot = self.spr_abyte = self.spr_pidx = 0
        # TurboSound: AY chips by select value (3 = AY 1, 2 = AY 2, 1 = AY 3)
        self.ay, self.ay_pans = {}, {}
        self.ay_chip, self.ay_pan, self.ay_reg = 3, 3, 0
        self.pal_idx = self.pal_phase = self.pal_hi = 0
        self.dma = {"pending": [], "a": 0, "b": 0, "len": 0, "a2b": True,
                    "amode": 1, "bmode": 1, "atiming": 0, "btiming": 0, "mask": 0,
                    "ddma": 0, "fill": 0}

    # --- memory -------------------------------------------------------------
    def page(self, n):
        p = self.pages.get(n)
        if p is None:
            p = bytearray(8192)
            self.pages[n] = p
        return p

    def _map(self, s, n):
        self.mmu[s] = n
        self.slot[s] = self.page(n)

    def rd(self, a):
        return self.slot[a >> 13][a & 0x1FFF]

    def wr(self, a, v):
        if self.mmu[a >> 13] == 0xFF:
            raise Halt(f"write to ROM {a:04X} pc={self.pc:04X}")
        self.slot[a >> 13][a & 0x1FFF] = v & 0xFF

    def rd16(self, a):
        return self.rd(a) | (self.rd((a + 1) & 0xFFFF) << 8)

    def wr16(self, a, v):
        self.wr(a, v & 0xFF)
        self.wr((a + 1) & 0xFFFF, v >> 8)

    def fetch(self):
        v = self.rd(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetch16(self):
        v = self.rd16(self.pc)
        self.pc = (self.pc + 2) & 0xFFFF
        return v

    def disp(self):
        d = self.fetch()
        return d - 256 if d > 127 else d

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        self.wr16(self.sp, v)

    def pop(self):
        v = self.rd16(self.sp)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    # --- io -----------------------------------------------------------------
    def set_nextreg(self, reg, val):
        self.nextreg[reg] = val
        if 0x50 <= reg <= 0x57:
            self._map(reg - 0x50, val)
        elif reg == 0x18:
            self.l2clip[self.l2clip_i] = val
            self.l2clip_i = (self.l2clip_i + 1) & 3
        elif reg == 0x1C and val & 1:
            self.l2clip_i = 0
        elif reg == 0x40:
            self.pal_idx, self.pal_phase = val, 0
        elif reg == 0x41 or (reg == 0x44 and self.pal_phase == 1):
            if reg == 0x41:
                rgb = (val << 1) | (1 if val & 3 else 0)
            else:
                rgb = (self.pal_hi << 1) | (val & 1)
            sel = (self.nextreg.get(0x43, 0) >> 4) & 7
            self.palettes.setdefault(sel, {})[self.pal_idx] = rgb
            self.pal_idx = (self.pal_idx + 1) & 0xFF
            self.pal_phase = 0
        elif reg == 0x44:
            self.pal_hi, self.pal_phase = val, 1
        elif reg == 0x12 and self.on_flip:
            self.on_flip(val)

    def port_in(self, port):
        lo = port & 0xFF
        if lo == 0xFE:
            hi = port >> 8
            v = 0x1F
            for row, keys in KEYROWS.items():
                if ~hi & ~row & 0xFF:          # row's address line is low
                    for bit, k in enumerate(keys):
                        if k in self.keys:
                            v &= ~(1 << bit)
            return v | 0xE0
        if lo in (0x1F, 0x37):                  # joysticks (Kempston / Mega Drive)
            return self.joy.get(lo, 0)
        if port == 0x253B:
            line = (self.t // T_PER_LINE) % LINES_PER_FRAME
            if self.nr_sel == 0x1E:
                return line >> 8
            if self.nr_sel == 0x1F:
                return line & 0xFF
            return self.nextreg.get(self.nr_sel, 0)
        return 0xFF

    # --- zxnDMA (enough for memory->memory transfers), and of DMA+ (zxnDDMA)
    # only what the game uses, fill mode.  Any other DMA+ command stops the
    # run: a transfer it doesn't model must not pass as a plain copy.
    def dma_write(self, v):
        d = self.dma
        if d["pending"]:
            reg, field = d["pending"].pop(0)
            d[field] = (d[field] & ~(0xFF << (8 * reg))) | (v << (8 * reg)) if reg < 2 else v
            return
        p = []
        if v & 0x80 == 0:
            if v & 3:                                   # WR0
                d["a2b"] = bool(v & 4)
                for bit, (reg, field) in ((3, (0, "a")), (4, (1, "a")), (5, (0, "len")), (6, (1, "len"))):
                    if v & (1 << bit):
                        p.append((reg, field))
            elif v & 7 == 4:                            # WR1 port A
                d["amode"] = (v >> 4) & 3
                if v & 0x40:
                    p.append((2, "atiming"))
            elif v & 7 == 0:                            # WR2 port B
                d["bmode"] = (v >> 4) & 3
                if v & 0x40:
                    p.append((2, "btiming"))
        else:
            if v & 3 == 1:                              # WR4
                for bit, (reg, field) in ((2, (0, "b")), (3, (1, "b"))):
                    if v & (1 << bit):
                        p.append((reg, field))
            elif v & 3 == 3:                            # WR6 command
                if v == 0xBB:
                    p.append((2, "mask"))
                elif v == 0x87:
                    self.dma_run()
                elif v == 0xC3:
                    d["ddma"] = d["fill"] = 0
                elif v == 0xDF:
                    p.append((2, "ddma"))
                elif v == 0xF7:
                    p.append((2, "fill"))
                elif v in (0xD7, 0xDB, 0xE3, 0xE7, 0xEB, 0xEF, 0xF3):
                    raise NotImplementedError(f"DMA+ command {v:02X}")
            # WR3 / WR5 ignored
        d["pending"] = p

    def dma_run(self):
        d = self.dma
        n = d["len"] or 0x10000
        src, dst = (d["a"], d["b"]) if d["a2b"] else (d["b"], d["a"])
        sm, dm = (d["amode"], d["bmode"]) if d["a2b"] else (d["bmode"], d["amode"])
        step = {0: -1, 1: 1, 2: 0, 3: 0}
        if d["ddma"] & ~DDMA_FILL:
            raise NotImplementedError(f"DMA+ mode {d['ddma']:02X}")
        if d["ddma"]:                                   # fill: no reads
            for _ in range(n):
                self.wr(dst, d["fill"])
                dst = (dst + step[dm]) & 0xFFFF
            self.t += n * DMA_T_PER_BYTE // 2
            return
        for _ in range(n):
            self.wr(dst, self.rd(src))
            src = (src + step[sm]) & 0xFFFF
            dst = (dst + step[dm]) & 0xFFFF
        self.t += n * DMA_T_PER_BYTE

    def port_out(self, port, v):
        if (port & 0xFF) == 0xFE:
            self.border = v & 7
            return
        if (port & 0xFF) == 0x6B:
            self.dma_write(v)
            return
        if port == 0xFFFD:              # TurboSound: chip or register select
            if v & 0x80 and (v & 0x1C) == 0x1C:
                self.ay_chip, self.ay_pan = v & 3, (v >> 5) & 3
            elif v < 16:
                self.ay_reg = v
            return
        if port == 0xBFFD:              # the selected AY register's value
            self.ay.setdefault(self.ay_chip, [0] * 16)[self.ay_reg] = v
            self.ay_pans[self.ay_chip] = self.ay_pan
            return
        if port == 0x303B:              # sprite / pattern slot
            self.spr_slot, self.spr_abyte = v & 0x7F, 0
            self.spr_pidx = (v & 0x3F) * 256 + (128 if v & 0x80 else 0)
            return
        if (port & 0xFF) == 0x57:       # sprite attributes, auto-advancing
            a = self.spr_attr[self.spr_slot]
            a[self.spr_abyte] = v
            self.spr_abyte += 1
            if self.spr_abyte == 4 and not (a[3] & 0x40):
                a[4] = 0                # 4-byte form: byte 4 is zero
                self.spr_abyte = 5
            if self.spr_abyte == 5:
                self.spr_slot, self.spr_abyte = (self.spr_slot + 1) & 0x7F, 0
            return
        if (port & 0xFF) == 0x5B:       # sprite pattern bytes
            self.spr_pat[self.spr_pidx] = v
            self.spr_pidx = (self.spr_pidx + 1) & 0x3FFF
            return
        if port == 0x243B:
            self.nr_sel = v
        elif port == 0x253B:
            self.set_nextreg(self.nr_sel, v)

    # --- register helpers ---------------------------------------------------
    @property
    def hl(self):
        return (self.r[4] << 8) | self.r[5]

    def get_rp(self, p, idx):
        if p == 0:
            return (self.r[0] << 8) | self.r[1]
        if p == 1:
            return (self.r[2] << 8) | self.r[3]
        if p == 2:
            if idx == 1:
                return self.ix
            if idx == 2:
                return self.iy
            return self.hl
        return self.sp

    def set_rp(self, p, v, idx):
        v &= 0xFFFF
        if p == 0:
            self.r[0], self.r[1] = v >> 8, v & 0xFF
        elif p == 1:
            self.r[2], self.r[3] = v >> 8, v & 0xFF
        elif p == 2:
            if idx == 1:
                self.ix = v
            elif idx == 2:
                self.iy = v
            else:
                self.r[4], self.r[5] = v >> 8, v & 0xFF
        else:
            self.sp = v

    def get_rp2(self, p, idx):
        if p == 3:
            return (self.r[7] << 8) | self.r[6]
        return self.get_rp(p, idx)

    def set_rp2(self, p, v, idx):
        if p == 3:
            self.r[7], self.r[6] = (v >> 8) & 0xFF, v & 0xFF
        else:
            self.set_rp(p, v, idx)

    def get_r(self, i, idx, addr):
        """r[i]; i==6 -> memory at addr; H/L map to IXH/IXL when idx and addr is None."""
        if i == 6:
            return self.rd(addr)
        if i == 7:
            return self.r[7]
        if idx and addr is None and i in (4, 5):
            v = self.ix if idx == 1 else self.iy
            return (v >> 8) if i == 4 else (v & 0xFF)
        return self.r[i]

    def set_r(self, i, v, idx, addr):
        v &= 0xFF
        if i == 6:
            self.wr(addr, v)
        elif i == 7:
            self.r[7] = v
        elif idx and addr is None and i in (4, 5):
            if idx == 1:
                self.ix = (v << 8 | (self.ix & 0xFF)) if i == 4 else ((self.ix & 0xFF00) | v)
            else:
                self.iy = (v << 8 | (self.iy & 0xFF)) if i == 4 else ((self.iy & 0xFF00) | v)
        else:
            self.r[i] = v

    def idx_addr(self, idx):
        base = self.ix if idx == 1 else self.iy
        return (base + self.disp()) & 0xFFFF

    # --- alu ----------------------------------------------------------------
    def alu(self, op, v):
        a = self.r[7]
        f = self.r[6]
        if op in (0, 1):  # ADD ADC
            c = (f & FC) if op == 1 else 0
            res = a + v + c
            r8 = res & 0xFF
            fl = (r8 & FS) | (FZ if r8 == 0 else 0)
            if (a & 0xF) + (v & 0xF) + c > 0xF:
                fl |= FH
            if ((a ^ ~v) & (a ^ r8)) & 0x80:
                fl |= FPV
            if res > 0xFF:
                fl |= FC
            self.r[7], self.r[6] = r8, fl
        elif op in (2, 3, 7):  # SUB SBC CP
            c = (f & FC) if op == 3 else 0
            res = a - v - c
            r8 = res & 0xFF
            fl = FN | (r8 & FS) | (FZ if r8 == 0 else 0)
            if (a & 0xF) - (v & 0xF) - c < 0:
                fl |= FH
            if ((a ^ v) & (a ^ r8)) & 0x80:
                fl |= FPV
            if res < 0:
                fl |= FC
            self.r[6] = fl
            if op != 7:
                self.r[7] = r8
        elif op == 4:
            r8 = a & v
            self.r[7], self.r[6] = r8, SZP[r8] | FH
        elif op == 5:
            r8 = a ^ v
            self.r[7], self.r[6] = r8, SZP[r8]
        elif op == 6:
            r8 = a | v
            self.r[7], self.r[6] = r8, SZP[r8]

    def inc8(self, v):
        r8 = (v + 1) & 0xFF
        fl = (self.r[6] & FC) | (r8 & FS) | (FZ if r8 == 0 else 0)
        if (v & 0xF) == 0xF:
            fl |= FH
        if v == 0x7F:
            fl |= FPV
        self.r[6] = fl
        return r8

    def dec8(self, v):
        r8 = (v - 1) & 0xFF
        fl = (self.r[6] & FC) | FN | (r8 & FS) | (FZ if r8 == 0 else 0)
        if (v & 0xF) == 0:
            fl |= FH
        if v == 0x80:
            fl |= FPV
        self.r[6] = fl
        return r8

    def rot(self, y, v):
        f = self.r[6]
        c = f & FC
        if y == 0:   # RLC
            co = v >> 7
            r8 = ((v << 1) | co) & 0xFF
        elif y == 1:  # RRC
            co = v & 1
            r8 = (v >> 1) | (co << 7)
        elif y == 2:  # RL
            co = v >> 7
            r8 = ((v << 1) | c) & 0xFF
        elif y == 3:  # RR
            co = v & 1
            r8 = (v >> 1) | (c << 7)
        elif y == 4:  # SLA
            co = v >> 7
            r8 = (v << 1) & 0xFF
        elif y == 5:  # SRA
            co = v & 1
            r8 = (v >> 1) | (v & 0x80)
        elif y == 6:  # SLL
            co = v >> 7
            r8 = ((v << 1) | 1) & 0xFF
        else:        # SRL
            co = v & 1
            r8 = v >> 1
        self.r[6] = SZP[r8] | (FC if co else 0)
        return r8

    def cond(self, y):
        f = self.r[6]
        return [not f & FZ, f & FZ, not f & FC, f & FC,
                not f & FPV, f & FPV, not f & FS, f & FS][y]

    # --- execute ------------------------------------------------------------
    # --- interrupts (raised by a test: there's no frame timer) ---------------
    def interrupt(self, bus=0xFF):
        """Accept a maskable interrupt now if enabled: IM 2 calls the word at
        I*256 + bus; IM 1 calls $0038.  Returns False if interrupts are off."""
        if not self.iff:
            return False
        self.iff = 0
        self.sp = (self.sp - 2) & 0xFFFF
        self.wr16(self.sp, self.pc)
        if getattr(self, "im", 0) == 2:
            self.pc = self.rd16(((getattr(self, "i", 0) << 8) | bus) & 0xFFFF)
            self.t += 19
        else:
            self.pc = 0x0038
            self.t += 13
        return True

    # --- esxDOS (RST $08 with the ROM paged in) -----------------------------
    # Set cpu.esx_root to a host folder to emulate the file calls there.
    ESX_ERR_NOFILE, ESX_ERR_EXISTS, ESX_ERR_BADHANDLE = 5, 18, 11
    def esx_call(self):
        ret = self.rd16(self.sp)
        fn = self.rd(ret)
        self.sp = (self.sp + 2) & 0xFFFF
        self.pc = (ret + 1) & 0xFFFF
        if not hasattr(self, "esx_files"):
            self.esx_files, self.esx_next, self.esx_log = {}, 1, []
        A = self.r[7]
        bc = (self.r[0] << 8) | self.r[1]
        de = (self.r[2] << 8) | self.r[3]
        def name_at(a):
            s = bytearray()
            while self.rd(a):
                s.append(self.rd(a)); a += 1
            return os.path.join(self.esx_root, s.decode())
        def ok(a=None):
            self.r[6] &= ~FC
            if a is not None:
                self.r[7] = a & 0xFF
        def err(code):
            self.r[6] |= FC
            self.r[7] = code
        def set_bc(v):
            self.r[0], self.r[1] = (v >> 8) & 0xFF, v & 0xFF
        def set_bcde(v):
            set_bc(v >> 16); self.r[2], self.r[3] = (v >> 8) & 0xFF, v & 0xFF
        self.esx_log.append((fn, self.mmu[0], self.mmu[1], self.iff))
        if fn == 0x89:                                  # M_GETSETDRV
            ok(ord('C'))
        elif fn == 0x9A:                                # F_OPEN
            path, mode = name_at(self.ix), self.r[0]
            exists = os.path.exists(path)
            if (mode & 0x0C) == 0x00 and not exists: return err(self.ESX_ERR_NOFILE)
            if (mode & 0x0C) == 0x04 and exists: return err(self.ESX_ERR_EXISTS)
            fm = "r+b" if exists and (mode & 0x0C) != 0x0C else "w+b"
            if (mode & 0x0C) == 0x00 and not (mode & 2): fm = "rb"
            try:
                f = open(path, fm)
            except OSError:                             # (no such folder, ...)
                return err(self.ESX_ERR_NOFILE)
            h = self.esx_next; self.esx_next += 1
            self.esx_files[h] = f
            ok(h)
        elif fn in (0x9B, 0x9D, 0x9E, 0x9F, 0xA1):
            f = self.esx_files.get(A)
            if f is None: return err(self.ESX_ERR_BADHANDLE)
            if fn == 0x9B:                              # F_CLOSE
                f.close(); del self.esx_files[A]; ok(0)
            elif fn == 0x9D:                            # F_READ
                data = f.read(bc)
                for i, v in enumerate(data): self.wr((self.ix + i) & 0xFFFF, v)
                set_bc(len(data)); ok()
            elif fn == 0x9E:                            # F_WRITE
                f.write(bytes(self.rd((self.ix + i) & 0xFFFF) for i in range(bc)))
                set_bc(bc); ok()
            elif fn == 0x9F:                            # F_SEEK
                off, mode = (bc << 16) | de, self.ix & 0xFF
                f.seek(off if mode == 0 else (f.tell() + off if mode == 1 else f.tell() - off))
                set_bcde(f.tell()); ok()
            else:                                       # F_FSTAT
                size = os.fstat(f.fileno()).st_size
                for i in range(11): self.wr(self.ix + i, 0)
                for i in range(4): self.wr(self.ix + 7 + i, (size >> (8 * i)) & 0xFF)
                ok()
        elif fn == 0xAD:                                # F_UNLINK
            path = name_at(self.ix)
            if not os.path.exists(path): return err(self.ESX_ERR_NOFILE)
            os.remove(path); ok()
        else:
            raise Halt(f"esxDOS function {fn:02X} not modelled")

    def step(self):
        if self.pc == 0x0008 and self.mmu[0] == 0xFF and getattr(self, "esx_root", None):
            self.t += 1000
            return self.esx_call()
        op = self.fetch()
        idx = 0
        t_extra = 0
        while op in (0xDD, 0xFD):
            idx = 1 if op == 0xDD else 2
            t_extra = 4
            op = self.fetch()
        if op == 0xCB:
            self.exec_cb(idx)
        elif op == 0xED:
            self.exec_ed()
        else:
            self.exec_main(op, idx)
        self.t += t_extra

    def exec_cb(self, idx):
        if idx:
            addr = self.idx_addr(idx)
            op = self.fetch()
            self.t += 19
        else:
            op = self.fetch()
            addr = self.hl
            self.t += 8 if (op & 7) != 6 else 15
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        src = 6 if idx else z
        v = self.get_r(src, 0, addr)
        if x == 0:
            res = self.rot(y, v)
        elif x == 1:
            f = (self.r[6] & FC) | FH
            if not v & (1 << y):
                f |= FZ | FPV
            if y == 7 and v & 0x80:
                f |= FS
            self.r[6] = f
            return
        elif x == 2:
            res = v & ~(1 << y)
        else:
            res = v | (1 << y)
        self.set_r(src, res, 0, addr)
        if idx and z != 6:
            self.set_r(z, res, 0, None)

    def exec_ed(self):
        op = self.fetch()
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        p, q = y >> 1, y & 1
        r = self.r
        if op == 0x30:      # MUL D,E
            v = r[2] * r[3]
            r[2], r[3] = v >> 8, v & 0xFF
            self.t += 8
            return
        if op == 0x31:      # ADD HL,A
            v = (self.hl + r[7]) & 0xFFFF
            r[4], r[5] = v >> 8, v & 0xFF
            self.t += 8
            return
        if op == 0x32:      # ADD DE,A
            v = ((r[2] << 8 | r[3]) + r[7]) & 0xFFFF
            r[2], r[3] = v >> 8, v & 0xFF
            self.t += 8
            return
        if 0x28 <= op <= 0x2C:  # barrel shifts on DE by B
            de = (r[2] << 8) | r[3]
            n = r[0] & 31
            if op == 0x28:
                v = (de << n) & 0xFFFF if n < 16 else 0
            elif op == 0x29:
                sd = de - 65536 if de & 0x8000 else de
                v = (sd >> min(n, 15)) & 0xFFFF
            elif op == 0x2A:
                v = de >> n if n < 16 else 0
            elif op == 0x2B:
                v = ((de | (0xFFFF0000 if de & 0x8000 else 0) | 0xFFFF0000) >> n) & 0xFFFF
            else:
                n &= 15
                v = ((de << n) | (de >> (16 - n))) & 0xFFFF
            r[2], r[3] = v >> 8, v & 0xFF
            self.t += 8
            return
        if op == 0x94:      # PIXELAD: HL = ULA address of pixel (D=y, E=x)
            d, e = r[2], r[3]
            v = 0x4000 | ((d & 0xC0) << 5) | ((d & 7) << 8) | ((d & 0x38) << 2) | (e >> 3)
            r[4], r[5] = v >> 8, v & 0xFF
            self.t += 8
            return
        if op == 0x95:      # SETAE: A = $80 >> (E & 7)
            r[7] = 0x80 >> (r[3] & 7)
            self.t += 8
            return
        if op == 0x91:      # NEXTREG n,n
            reg = self.fetch()
            val = self.fetch()
            self.set_nextreg(reg, val)
            self.t += 20
            return
        if op == 0x92:      # NEXTREG n,A
            reg = self.fetch()
            self.set_nextreg(reg, r[7])
            self.t += 17
            return
        if x == 1:
            if z == 0:
                v = self.port_in((r[0] << 8) | r[1])
                if y != 6:
                    r[y] = v
                r[6] = (r[6] & FC) | SZP[v]
                self.t += 12
            elif z == 1:
                self.port_out((r[0] << 8) | r[1], 0 if y == 6 else r[y])
                self.t += 12
            elif z == 2:
                hl = self.hl
                v = self.get_rp(p, 0)
                c = r[6] & FC
                if q == 0:
                    res = hl - v - c
                    r16 = res & 0xFFFF
                    f = FN | ((r16 >> 8) & FS) | (FZ if r16 == 0 else 0)
                    if ((hl ^ v) & (hl ^ r16)) & 0x8000:
                        f |= FPV
                    if res < 0:
                        f |= FC
                    if (hl & 0xFFF) - (v & 0xFFF) - c < 0:
                        f |= FH
                else:
                    res = hl + v + c
                    r16 = res & 0xFFFF
                    f = ((r16 >> 8) & FS) | (FZ if r16 == 0 else 0)
                    if ((hl ^ ~v) & (hl ^ r16)) & 0x8000:
                        f |= FPV
                    if res > 0xFFFF:
                        f |= FC
                r[4], r[5] = r16 >> 8, r16 & 0xFF
                r[6] = f
                self.t += 15
            elif z == 3:
                nn = self.fetch16()
                if q == 0:
                    self.wr16(nn, self.get_rp(p, 0))
                else:
                    self.set_rp(p, self.rd16(nn), 0)
                self.t += 20
            elif z == 4:
                a = r[7]
                r[7] = 0
                self.alu(2, a)
                self.t += 8
            elif z == 5:
                self.pc = self.pop()
                self.t += 14
            elif z == 6:                                # IM 0/1/2
                self.im = (0, 0, 1, 2)[y & 3]
                self.t += 8
            else:
                if y == 0:                              # LD I,A
                    self.i = r[7]
                elif y == 2:                            # LD A,I: P/V = IFF2
                    a = getattr(self, "i", 0)
                    r[7] = a
                    r[6] = (r[6] & FC) | (a & FS) | (FZ if a == 0 else 0) | (FPV if self.iff else 0)
                self.t += 9
            return
        if x == 2 and y in (4, 6) and z == 3:   # OUTI OTIR
            while True:
                v = self.rd(self.hl)
                r[0] = (r[0] - 1) & 0xFF
                self.port_out((r[0] << 8) | r[1], v)
                hl = (self.hl + 1) & 0xFFFF
                r[4], r[5] = hl >> 8, hl & 0xFF
                self.t += 21 if (y == 6 and r[0]) else 16
                if y == 4 or r[0] == 0:
                    break
            r[6] = (r[6] & FC) | FN | (FZ if r[0] == 0 else 0)
            return
        if x == 2 and y >= 4 and z == 0:   # LDI LDD LDIR LDDR
            while True:
                hl = self.hl
                de = (r[2] << 8) | r[3]
                bc = (r[0] << 8) | r[1]
                self.wr(de, self.rd(hl))
                step = 1 if y in (4, 6) else -1
                hl = (hl + step) & 0xFFFF
                de = (de + step) & 0xFFFF
                bc = (bc - 1) & 0xFFFF
                r[4], r[5], r[2], r[3], r[0], r[1] = hl >> 8, hl & 0xFF, de >> 8, de & 0xFF, bc >> 8, bc & 0xFF
                self.t += 21
                if y < 6 or bc == 0:
                    break
            r[6] = (r[6] & (FS | FZ | FC)) | (FPV if bc else 0)
            return
        raise Halt(f"unimplemented ED {op:02X} at {self.pc - 2:04X}")

    def exec_main(self, op, idx):
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        p, q = y >> 1, y & 1
        r = self.r
        if x == 1:
            if y == 6 and z == 6:
                raise Halt(f"HALT at {self.pc - 1:04X}")
            if idx and (y == 6 or z == 6):
                addr = self.idx_addr(idx)
                self.set_r(y, self.get_r(z, 0, addr), 0, addr)
                self.t += 15
            else:
                addr = self.hl if (y == 6 or z == 6) else None
                self.set_r(y, self.get_r(z, idx, addr), idx, addr)
                self.t += 7 if addr is not None else 4
            return
        if x == 2:
            if z == 6:
                addr = self.idx_addr(idx) if idx else self.hl
                self.alu(y, self.rd(addr))
                self.t += 15 if idx else 7
            else:
                self.alu(y, self.get_r(z, idx, None))
                self.t += 4
            return
        if x == 0:
            if z == 0:
                if y == 0:
                    self.t += 4
                elif y == 1:
                    a, f = r[7], r[6]
                    r[7], r[6] = self.alt[7], self.alt[6]
                    self.alt[7], self.alt[6] = a, f
                    self.t += 4
                elif y == 2:
                    d = self.disp()
                    r[0] = (r[0] - 1) & 0xFF
                    if r[0]:
                        self.pc = (self.pc + d) & 0xFFFF
                        self.t += 13
                    else:
                        self.t += 8
                else:
                    d = self.disp()
                    if y == 3 or self.cond(y - 4):
                        self.pc = (self.pc + d) & 0xFFFF
                        self.t += 12
                    else:
                        self.t += 7
            elif z == 1:
                if q == 0:
                    self.set_rp(p, self.fetch16(), idx)
                    self.t += 10
                else:
                    a = self.get_rp(2, idx)
                    b = self.get_rp(p, idx)
                    res = a + b
                    f = r[6] & (FS | FZ | FPV)
                    if res > 0xFFFF:
                        f |= FC
                    if (a & 0xFFF) + (b & 0xFFF) > 0xFFF:
                        f |= FH
                    r[6] = f
                    self.set_rp(2, res, idx)
                    self.t += 11
            elif z == 2:
                if p == 0:
                    a = (r[0] << 8) | r[1]
                elif p == 1:
                    a = (r[2] << 8) | r[3]
                else:
                    a = self.fetch16()
                if q == 0:
                    if p == 2:
                        self.wr16(a, self.get_rp(2, idx))
                        self.t += 16
                    else:
                        self.wr(a, r[7])
                        self.t += 13 if p == 3 else 7
                else:
                    if p == 2:
                        self.set_rp(2, self.rd16(a), idx)
                        self.t += 16
                    else:
                        r[7] = self.rd(a)
                        self.t += 13 if p == 3 else 7
            elif z == 3:
                v = self.get_rp(p, idx)
                self.set_rp(p, v + (1 if q == 0 else -1), idx)
                self.t += 6
            elif z in (4, 5):
                if y == 6:
                    addr = self.idx_addr(idx) if idx else self.hl
                    v = self.rd(addr)
                    self.wr(addr, self.inc8(v) if z == 4 else self.dec8(v))
                    self.t += 19 if idx else 11
                else:
                    v = self.get_r(y, idx, None)
                    self.set_r(y, self.inc8(v) if z == 4 else self.dec8(v), idx, None)
                    self.t += 4
            elif z == 6:
                if y == 6:
                    addr = self.idx_addr(idx) if idx else self.hl
                    self.wr(addr, self.fetch())
                    self.t += 15 if idx else 10
                else:
                    self.set_r(y, self.fetch(), idx, None)
                    self.t += 7
            else:
                a, f = r[7], r[6]
                if y == 0:
                    c = a >> 7
                    a = ((a << 1) | c) & 0xFF
                    f = (f & (FS | FZ | FPV)) | c
                elif y == 1:
                    c = a & 1
                    a = (a >> 1) | (c << 7)
                    f = (f & (FS | FZ | FPV)) | c
                elif y == 2:
                    c = a >> 7
                    a = ((a << 1) | (f & FC)) & 0xFF
                    f = (f & (FS | FZ | FPV)) | c
                elif y == 3:
                    c = a & 1
                    a = (a >> 1) | ((f & FC) << 7)
                    f = (f & (FS | FZ | FPV)) | c
                elif y == 4:
                    raise Halt("DAA not modelled")
                elif y == 5:
                    a ^= 0xFF
                    f |= FH | FN
                elif y == 6:
                    f = (f & (FS | FZ | FPV)) | FC
                else:
                    f = (f & (FS | FZ | FPV)) | ((f & FC) ^ FC)
                r[7], r[6] = a, f
                self.t += 4
            return
        # x == 3
        if z == 0:
            if self.cond(y):
                self.pc = self.pop()
                self.t += 11
            else:
                self.t += 5
        elif z == 1:
            if q == 0:
                self.set_rp2(p, self.pop(), idx)
                self.t += 10
            elif p == 0:
                self.pc = self.pop()
                self.t += 10
            elif p == 1:
                for i in (0, 1, 2, 3, 4, 5):
                    r[i], self.alt[i] = self.alt[i], r[i]
                self.t += 4
            elif p == 2:
                self.pc = self.get_rp(2, idx)
                self.t += 4
            else:
                self.sp = self.get_rp(2, idx)
                self.t += 6
        elif z == 2:
            nn = self.fetch16()
            if self.cond(y):
                self.pc = nn
            self.t += 10
        elif z == 3:
            if y == 0:
                self.pc = self.fetch16()
                self.t += 10
            elif y == 2:
                self.port_out((r[7] << 8) | self.fetch(), r[7])
                self.t += 11
            elif y == 3:
                r[7] = self.port_in((r[7] << 8) | self.fetch())
                self.t += 11
            elif y == 4:
                v = self.rd16(self.sp)
                self.wr16(self.sp, self.get_rp(2, idx))
                self.set_rp(2, v, idx)
                self.t += 19
            elif y == 5:
                r[2], r[4] = r[4], r[2]
                r[3], r[5] = r[5], r[3]
                self.t += 4
            elif y == 6:
                self.iff = 0
                self.t += 4
            elif y == 7:
                self.iff = 1
                self.t += 4
            else:
                raise Halt("bad CB path")
        elif z == 4:
            nn = self.fetch16()
            if self.cond(y):
                self.push(self.pc)
                self.pc = nn
                self.t += 17
            else:
                self.t += 10
        elif z == 5:
            if q == 0:
                self.push(self.get_rp2(p, idx))
                self.t += 11
            elif p == 0:
                nn = self.fetch16()
                self.push(self.pc)
                self.pc = nn
                self.t += 17
            else:
                raise Halt(f"bad prefix {op:02X}")
        elif z == 6:
            self.alu(y, self.fetch())
            self.t += 7
        else:
            self.push(self.pc)
            self.pc = y * 8
            self.t += 11


# ----------------------------------------------------------------------------
def load_nex(cpu, path):
    data = open(path, "rb").read()
    assert data[:4] == b"Next", "not a NEX file"
    sp = struct.unpack_from("<H", data, 12)[0]
    pc = struct.unpack_from("<H", data, 14)[0]
    banks = data[18:18 + 112]
    order = [5, 2, 0, 1, 3, 4, 6, 7] + list(range(8, 112))
    off = 512
    for b in order:
        if banks[b]:
            chunk = data[off:off + 16384]
            cpu.page(b * 2)[:] = chunk[:8192]
            cpu.page(b * 2 + 1)[:] = chunk[8192:16384]
            off += 16384
    cpu.pc, cpu.sp = pc, sp
    if not getattr(cpu, "esx_root", None):
        cpu.esx_root = os.path.dirname(os.path.abspath(path))   # the SD card:
                                        # the NEX's folder, as when launched


# Default ULA palette (8-bit RRRGGGBB): ink 0-7, bright ink 8-15,
# paper 16-23, bright paper 24-31.
ULA_DEFAULT = [0x00, 0x02, 0xA0, 0xA2, 0x14, 0x16, 0xB4, 0xB6,
               0x00, 0x03, 0xE0, 0xE7, 0x1C, 0x1F, 0xFC, 0xFF] * 2


def to9(c8):
    return (c8 << 1) | (1 if c8 & 3 else 0)


def write_png(path, bank, cpu):
    """Composite as the Next does with priority S-U-L: ULA pixel unless its
    colour is the global transparency ($E3), then Layer 2 inside its clip
    window, else black.  Layer 2 256x192 is row-major; 320x256 is
    column-major (pixel x*256+y) and covers the border area too, with the
    ULA screen at (32,32).  Hardware sprites (8-bit patterns, mirrors,
    rotation, scale, wrap at 512) are drawn on top when NextReg $15 bit 0 is
    set; with bit 1 (over the border) the image is the full 320x256."""
    mode320 = ((cpu.nextreg.get(0x70, 0) >> 4) & 3) == 1
    nr15 = cpu.nextreg.get(0x15, 0)
    full = mode320 or (nr15 & 3) == 3
    w, h = (320, 256) if full else (256, 192)
    ox, oy = (32, 32) if full else (0, 0)
    spr = {}
    if nr15 & 1:
        spal = cpu.palettes.get(2, {})
        strans = cpu.nextreg.get(0x4B, 0xE3)
        for a in cpu.spr_attr:          # sprite 0 first: higher ones on top
            if not a[3] & 0x80:
                continue
            ext = a[3] & 0x40
            sx = a[0] | (a[2] & 1) << 8
            sy = a[1] | ((a[4] & 1) << 8 if ext else 0)
            pat = (a[3] & 0x3F) * 256
            xs = 1 << ((a[4] >> 3) & 3) if ext else 1
            ys = 1 << ((a[4] >> 1) & 3) if ext else 1
            for py in range(16 * ys):
                for px in range(16 * xs):
                    u, v = px // xs, py // ys
                    if a[2] & 2:        # rotate 90 clockwise, then mirror
                        u, v = v, 15 - u
                    if a[2] & 8:
                        u = 15 - u
                    if a[2] & 4:
                        v = 15 - v
                    c = cpu.spr_pat[pat + v * 16 + u]
                    if c == strans:
                        continue
                    c = (c + (a[2] & 0xF0)) & 0xFF
                    X, Y = (sx + px) & 511, (sy + py) & 511
                    if not nr15 & 2 and not (32 <= X < 288 and 32 <= Y < 224):
                        continue        # (clip window ignored otherwise)
                    spr[(X, Y)] = spal.get(c, to9(c))
    npages = 10 if mode320 else 6
    buf = b"".join(bytes(cpu.page(bank * 2 + i)) for i in range(npages))
    ula = bytes(cpu.page(10)) + bytes(cpu.page(11))     # bank 5
    ula_above = (cpu.nextreg.get(0x15, 0) >> 2) & 7 in (2, 4, 5)
    l2pal = cpu.palettes.get(5 if cpu.nextreg.get(0x43, 0) & 4 else 1, {})   # (second: $43 bit 2)
    upal = [to9(c) for c in ULA_DEFAULT]
    for k, v in cpu.palettes.get(0, {}).items():
        if k < 32:
            upal[k] = v
    trans = cpu.nextreg.get(0x14, 0xE3)
    x1, x2, y1, y2 = cpu.l2clip
    if mode320:
        x1, x2 = x1 * 2, x2 * 2 + 1
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            ux, uy = x - ox, y - oy
            if 0 <= ux < 256 and 0 <= uy < 192:
                a = ula[0x1800 + (uy >> 3) * 32 + (ux >> 3)]
                bit = ula[((uy & 0xC0) << 5) | ((uy & 7) << 8) | ((uy & 0x38) << 2) | (ux >> 3)] & (0x80 >> (ux & 7))
                bright = 8 if a & 0x40 else 0
                v9 = upal[(a & 7) + bright] if bit else upal[16 + ((a >> 3) & 7) + bright]
            else:
                v9 = upal[16 + cpu.border]          # border; transparent ->
                if (v9 >> 1) == cpu.nextreg.get(0x14, 0xE3):  # the fallback
                    v9 = to9(cpu.nextreg.get(0x4A, 0))       # colour ($4A)
            if not ula_above or (v9 >> 1) == trans:
                lx, ly = (x, y) if mode320 else (ux, uy)
                if x1 <= lx <= x2 and y1 <= ly <= y2 and (mode320 or (0 <= ux < 256 and 0 <= uy < 192)):
                    c = buf[x * 256 + y] if mode320 else buf[uy * 256 + ux]
                    v9 = l2pal.get(c, to9(c))
                elif 0 <= ux < 256 and 0 <= uy < 192:
                    v9 = 0
            sv = spr.get((x + 32 - ox, y + 32 - oy))
            if sv is not None:
                v9 = sv
            rr, gg, bb = v9 >> 6, (v9 >> 3) & 7, v9 & 7
            raw += bytes((rr * 255 // 7, gg * 255 // 7, bb * 255 // 7))
    def chunk(tag, d):
        return struct.pack(">I", len(d)) + tag + d + struct.pack(">I", zlib.crc32(tag + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    nex, outdir, nframes = sys.argv[1], sys.argv[2], int(sys.argv[3])
    script = {}
    if len(sys.argv) > 4 and sys.argv[4]:
        for item in sys.argv[4].split(","):
            f, k = item.split(":")
            script[int(f)] = set(k.upper())
    save_every = int(os.environ.get("SAVE_EVERY", "1"))
    os.makedirs(outdir, exist_ok=True)
    cpu = Cpu()
    load_nex(cpu, nex)
    state = {"frame": 0, "t0": 0}

    def flip(bank):
        f = state["frame"]
        dt = cpu.t - state["t0"]
        state["t0"] = cpu.t
        if f > 0:
            print(f"frame {f:3d}: {dt:8d} T  ({28e6 / dt:5.1f} fps @28MHz)  keys={''.join(sorted(cpu.keys))}")
            if f % save_every == 0 or f == nframes:
                write_png(os.path.join(outdir, f"f{f:03d}.png"), bank, cpu)
        state["frame"] = f + 1
        if f + 1 in script:
            cpu.keys = script[f + 1]
        if f >= nframes:
            raise Halt("done")

    cpu.on_flip = flip
    prof = None
    if os.environ.get("PROFILE"):
        import bisect
        syms = []
        for line in open(os.environ["PROFILE"]):
            m = re.match(r"(\w+):\s+EQU\s+0x([0-9A-F]+)", line)
            if m and "." not in m.group(1):
                syms.append((int(m.group(2), 16), m.group(1)))
        syms.sort()
        addrs = [a for a, _ in syms]
        prof = {}
        hits = {a: 0 for a, _ in syms}
    if 0 in script:
        cpu.keys = script[0]
    try:
        while True:
            if prof is None:
                cpu.step()
            else:
                pc, t = cpu.pc, cpu.t
                if pc in hits:
                    hits[pc] += 1
                cpu.step()
                i = bisect.bisect_right(addrs, pc) - 1
                name = syms[i][1] if i >= 0 else "?"
                prof[name] = prof.get(name, 0) + cpu.t - t
    except Halt as e:
        if str(e) != "done":
            print("HALT:", e)
            raise
    if prof:
        tot = sum(prof.values())
        for k, v in sorted(prof.items(), key=lambda kv: -kv[1])[:25]:
            print(f"{k:16s} {v:10d} {100 * v / tot:5.1f}%")
        names = dict(syms)
        print("calls:", ", ".join(f"{names[a]}={n}" for a, n in sorted(hits.items(), key=lambda kv: -kv[1]) if n)[:600])


if __name__ == "__main__":
    main()
