"""Minimal Z80N emulator for headless testing of zpolice.nex.

Runs the NEX, captures every Layer 2 buffer flip (NextReg $12 write) to PNG,
and reports approximate T-states per frame. Only what the game needs is
modelled: 8K MMU paging, NextReg writes/reads, keyboard port $FE, raster
line read ($1E/$1F always reports line 192 so vsync waits return at once).

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
}


# Estimated zxnDMA cost per byte for a memory->memory transfer (CPU halted).
DMA_T_PER_BYTE = int(os.environ.get("DMA_T", "2"))


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
        self.on_flip = None
        self.iff = 0
        self.dma = {"pending": [], "a": 0, "b": 0, "len": 0, "a2b": True,
                    "amode": 1, "bmode": 1, "atiming": 0, "btiming": 0, "mask": 0}

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
        if port == 0x253B:
            if self.nr_sel == 0x1E:
                return 0
            if self.nr_sel == 0x1F:
                return 192
            return self.nextreg.get(self.nr_sel, 0)
        return 0xFF

    # --- zxnDMA (enough for memory->memory transfers) ------------------------
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
            # WR3 / WR5 ignored
        d["pending"] = p

    def dma_run(self):
        d = self.dma
        n = d["len"] or 0x10000
        src, dst = (d["a"], d["b"]) if d["a2b"] else (d["b"], d["a"])
        sm, dm = (d["amode"], d["bmode"]) if d["a2b"] else (d["bmode"], d["amode"])
        step = {0: -1, 1: 1, 2: 0, 3: 0}
        for _ in range(n):
            self.wr(dst, self.rd(src))
            src = (src + step[sm]) & 0xFFFF
            dst = (dst + step[dm]) & 0xFFFF
        self.t += n * DMA_T_PER_BYTE

    def port_out(self, port, v):
        if (port & 0xFF) == 0x6B:
            self.dma_write(v)
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
    def step(self):
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
            elif z == 6:
                self.t += 8
            else:
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


def write_png(path, bank, cpu):
    w, h = 256, 192
    raw = bytearray()
    buf = b"".join(bytes(cpu.page(bank * 2 + i)) for i in range(6))
    for y in range(h):
        raw.append(0)
        for x in range(w):
            c = buf[y * 256 + x]
            rr = (c >> 5) & 7
            gg = (c >> 2) & 7
            b2 = c & 3
            bb = (b2 << 1) | (1 if b2 else 0)
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
