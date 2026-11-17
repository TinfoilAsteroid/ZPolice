"""Z-Police tile editor: the VTOL console's tilemap tiles, their 16 colours
and where they go round the view (sprites/console_tiles.json;
tools/consoletiles.py has the format, build.bat puts them in the game).

    python tools/tile_editor.py

On the left: the tiles (at most 112: 64-175), by number and name.  In the middle the
selected tile's 8 x 8 pixels, enlarged; under it the 16 colours (index 0 is
see-through), the tools, and the tile at its size, twice, and repeated 3 x 3
(to see its edges meet).  On the right the whole console, 40 x 32 cells
round the view (the view and the ULA panel's 32 x 24 cells are outlined:
tiles there are drawn over them).

Colours: 9-bit (r, g, b 0-7 each), in banks of 16; each tile uses one
bank (its Bank, under the tile), so different tiles can have different
colours: up to 15 banks.  The Banks menu adds one (a copy of this tile's)
or deletes this tile's (its tiles go to bank 0).

Pixels:
    Left button     paint the left colour      Right button    the right one
    Ctrl+click      pick up the pixel's colour for that button
    Double-click a colour   change it (r, g, b 0-7: the tile's bank's)
    Arrow keys      shift the tile, wrapping round
    Ctrl+Z, Ctrl+Y  undo, redo                 Ctrl+S          save
    Ctrl+C, Ctrl+V  copy this tile's pixels, paste over them

The console (right):
    Left button     put the selected tile (drag to paint), with the ticked
                    Mirror X, Mirror Y and Rotate (above the console; X, Y
                    and R toggle them)
    Shift+left      put it with Mirror X the other way
    Right button    delete the tile under the cursor: the cell empty,
                    see-through (drag to delete more)
    Ctrl+right      pick up the cell's tile and its mirrors and rotation
    ULA over (U)    put tiles with the ULA drawn over them (where the ULA
                    isn't see-through: the panel's grey covers them); such
                    cells have a yellow mark at the top left
    Ctrl+left       empty the cell too

Tools: Pencil, Fill (the area of the clicked colour, joined side to side).
Edit menu: mirror, flip, rotate, replace the right colour with the left,
clear.  Tile menu: add, duplicate, rename (the console follows), delete
(its cells emptied), move up / down.  View menu: the console's zoom (x1 to
x4; scrolled when it doesn't fit), the
HUD's guides (the compass band, the humans column).

Save checks it all (consoletiles.problems) and writes the file; build.bat
(gentables.py) then makes tables_console.inc from it.
"""
import copy
import os
import sys
import tkinter as tk
from tkinter import messagebox, simpledialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import consoletiles as ct  # noqa: E402

COLS, ROWS = ct.COLS, ct.ROWS
PIX = 36                                # a pixel in the editor
SEE = "#3c003c"                         # see-through, shown dark magenta
VIEW = (4, 4, 36, 28)                   # the view and panel: cells c0, r0, c1, r1
LAY_MAX_W, LAY_MAX_H = 960, 768         # the console's view at most (scrolled)


def rel(p):
    try:
        return os.path.relpath(p)
    except ValueError:                  # (another drive)
        return p


def hexc(c):
    """A 9-bit colour -> #rrggbb"""
    r, g, b = ct.rgb9(c)
    return f"#{r:02x}{g:02x}{b:02x}"


class Editor:
    def __init__(self, root, path=ct.FILE):
        self.root, self.path = root, path
        try:
            self.d = ct.load(path)
        except (OSError, ValueError) as e:
            messagebox.showerror("Can't read the tiles", str(e))
            self.d = ct.default()
        self.sel = 0
        self.fg, self.bg = 4, 0
        self.tool = tk.StringVar(value="pencil")
        self.zoom = tk.IntVar(value=2)
        self.guides = tk.BooleanVar(value=True)
        self.undo, self.redo = [], []
        self.dirty = False
        self.clip = None
        self.cache = {}                 # (name, flags, zoom) -> PhotoImage
        self.fx = tk.BooleanVar(value=False)    # the flags tiles are put with:
        self.fy = tk.BooleanVar(value=False)    # mirror x, mirror y, rotate
        self.fr = tk.BooleanVar(value=False)
        self.fu = tk.BooleanVar(value=False)    # and the ULA over them
        self.drag = None
        self.build_ui()
        self.refresh_all()

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        r = self.root
        mb = tk.Menu(r)
        fm = tk.Menu(mb, tearoff=0)
        fm.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        fm.add_command(label="Reload", command=self.reload)
        fm.add_command(label="Preview PNG...", command=self.cmd_png)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.quit)
        mb.add_cascade(label="File", menu=fm)
        em = tk.Menu(mb, tearoff=0)
        em.add_command(label="Undo", accelerator="Ctrl+Z", command=self.cmd_undo)
        em.add_command(label="Redo", accelerator="Ctrl+Y", command=self.cmd_redo)
        em.add_separator()
        em.add_command(label="Copy tile", accelerator="Ctrl+C", command=self.cmd_copy)
        em.add_command(label="Paste over tile", accelerator="Ctrl+V", command=self.cmd_paste)
        em.add_separator()
        em.add_command(label="Mirror left-right", command=lambda: self.edit_px(lambda p: [row[::-1] for row in p]))
        em.add_command(label="Flip top-bottom", command=lambda: self.edit_px(lambda p: p[::-1]))
        em.add_command(label="Rotate clockwise",
                       command=lambda: self.edit_px(lambda p: [[p[7 - x][y] for x in range(8)] for y in range(8)]))
        em.add_command(label="Replace right colour with left", command=self.cmd_replace)
        em.add_command(label="Clear (right colour)",
                       command=lambda: self.edit_px(lambda p: [[self.bg] * 8 for _ in range(8)]))
        mb.add_cascade(label="Edit", menu=em)
        tm = tk.Menu(mb, tearoff=0)
        tm.add_command(label="Add", command=self.cmd_add)
        tm.add_command(label="Duplicate", command=lambda: self.cmd_add(dup=True))
        tm.add_command(label="Rename...", command=self.cmd_rename)
        tm.add_command(label="Delete", command=self.cmd_delete)
        tm.add_separator()
        tm.add_command(label="Move up", command=lambda: self.cmd_move(-1))
        tm.add_command(label="Move down", command=lambda: self.cmd_move(1))
        mb.add_cascade(label="Tile", menu=tm)
        bm = tk.Menu(mb, tearoff=0)
        bm.add_command(label="Add a bank (a copy of this tile's)", command=self.cmd_add_bank)
        bm.add_command(label="Delete this tile's bank", command=self.cmd_del_bank)
        mb.add_cascade(label="Banks", menu=bm)
        vm = tk.Menu(mb, tearoff=0)
        for z in (1, 2, 3, 4):
            vm.add_radiobutton(label=f"Console x{z}", variable=self.zoom, value=z, command=self.draw_layout)
        vm.add_checkbutton(label="HUD guides", variable=self.guides, command=self.draw_layout)
        mb.add_cascade(label="View", menu=vm)
        r.config(menu=mb)
        for k, fn in (("<Control-s>", self.save), ("<Control-z>", self.cmd_undo), ("<Control-y>", self.cmd_redo),
                      ("<Control-c>", self.cmd_copy), ("<Control-v>", self.cmd_paste)):
            r.bind(k, lambda e, f=fn: f())
        for k, dx, dy in (("<Left>", -1, 0), ("<Right>", 1, 0), ("<Up>", 0, -1), ("<Down>", 0, 1)):
            r.bind(k, lambda e, a=dx, b=dy: self.cmd_shift(a, b))
        r.protocol("WM_DELETE_WINDOW", self.quit)

        left = tk.Frame(r, padx=4, pady=4)
        left.pack(side=tk.LEFT, fill=tk.Y)
        tk.Label(left, text="Tiles").pack(anchor=tk.W)
        self.lst = tk.Listbox(left, width=16, height=34, exportselection=False)
        self.lst.pack(fill=tk.Y, expand=True)
        self.lst.bind("<<ListboxSelect>>", self.on_list)

        mid = tk.Frame(r, padx=4, pady=4)
        mid.pack(side=tk.LEFT, fill=tk.Y)
        self.title = tk.Label(mid, font=("TkDefaultFont", 11, "bold"))
        self.title.pack(anchor=tk.W)
        self.cv = tk.Canvas(mid, width=8 * PIX, height=8 * PIX, bg=SEE, highlightthickness=0)
        self.cv.pack(anchor=tk.W)
        for ev in ("<Button-1>", "<B1-Motion>"):
            self.cv.bind(ev, lambda e: self.on_pixel(e, "fg"))
        for ev in ("<Button-3>", "<B3-Motion>"):
            self.cv.bind(ev, lambda e: self.on_pixel(e, "bg"))
        self.cv.bind("<ButtonRelease-1>", self.end_stroke)
        self.cv.bind("<ButtonRelease-3>", self.end_stroke)
        bf = tk.Frame(mid)
        bf.pack(anchor=tk.W, pady=(6, 0))
        tk.Label(bf, text="This tile's bank:").pack(side=tk.LEFT)
        self.bank_var = tk.IntVar(value=0)
        self.bank_spin = tk.Spinbox(bf, from_=0, to=0, width=4, textvariable=self.bank_var,
                                    command=self.on_bank)
        self.bank_spin.pack(side=tk.LEFT, padx=4)
        self.bank_spin.bind("<Return>", lambda e: self.on_bank())
        self.bank_info = tk.Label(bf, fg="#606060")
        self.bank_info.pack(side=tk.LEFT)
        tk.Label(mid, text="Its colours (double-click to change; 0 is see-through)").pack(anchor=tk.W, pady=(6, 0))
        self.pal = tk.Canvas(mid, width=8 * PIX, height=2 * 22 + 4, highlightthickness=0)
        self.pal.pack(anchor=tk.W)
        self.pal.bind("<Button-1>", lambda e: self.on_swatch(e, "fg"))
        self.pal.bind("<Button-3>", lambda e: self.on_swatch(e, "bg"))
        self.pal.bind("<Double-Button-1>", self.on_swatch_edit)
        self.lr = tk.Label(mid, anchor=tk.W)
        self.lr.pack(anchor=tk.W, fill=tk.X)
        tf = tk.Frame(mid)
        tf.pack(anchor=tk.W, pady=4)
        for t in ("pencil", "fill"):
            tk.Radiobutton(tf, text=t.title(), variable=self.tool, value=t).pack(side=tk.LEFT)
        tk.Label(mid, text="Its size, x2, and repeated").pack(anchor=tk.W, pady=(6, 0))
        self.pv = tk.Canvas(mid, width=8 * PIX, height=64, bg="#202020", highlightthickness=0)
        self.pv.pack(anchor=tk.W)

        right = tk.Frame(r, padx=4, pady=4)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tk.Label(right, text="The console: left puts the tile (Shift: mirror X the other way), right "
                 "deletes it, Ctrl+right picks one up").pack(anchor=tk.W)
        ff = tk.Frame(right)
        ff.pack(anchor=tk.W)
        tk.Label(ff, text="Put with:").pack(side=tk.LEFT)
        for text, var, key in (("Mirror X", self.fx, "x"), ("Mirror Y", self.fy, "y"), ("Rotate", self.fr, "r"),
                               ("ULA over", self.fu, "u")):
            tk.Checkbutton(ff, text=f"{text} ({key.upper()})", variable=var,
                           command=self.draw_tile).pack(side=tk.LEFT)
            self.root.bind(f"<KeyPress-{key}>", lambda e, v=var: self.toggle_flag(v))
        self.flag_pv = tk.Canvas(ff, width=40, height=20, bg="#202020", highlightthickness=0)
        self.flag_pv.pack(side=tk.LEFT, padx=6)
        lf = tk.Frame(right)                    # (scrolled: at x3 and x4 it's big)
        lf.pack(anchor=tk.NW, fill=tk.BOTH, expand=True)
        self.lay = tk.Canvas(lf, bg=SEE, highlightthickness=0)
        ys = tk.Scrollbar(lf, orient=tk.VERTICAL, command=self.lay.yview)
        xs = tk.Scrollbar(lf, orient=tk.HORIZONTAL, command=self.lay.xview)
        self.lay.config(xscrollcommand=xs.set, yscrollcommand=ys.set)
        self.lay.grid(row=0, column=0, sticky=tk.NSEW)
        ys.grid(row=0, column=1, sticky=tk.NS)
        xs.grid(row=1, column=0, sticky=tk.EW)
        lf.rowconfigure(0, weight=1)
        lf.columnconfigure(0, weight=1)
        self.lay.bind("<Button-1>", lambda e: self.on_cell(e, "put"))
        self.lay.bind("<B1-Motion>", lambda e: self.on_cell(e, "put", drag=True))
        self.lay.bind("<Button-3>", lambda e: self.on_cell(e, "pick" if e.state & 0x4 else "del"))
        self.lay.bind("<B3-Motion>", lambda e: self.on_cell(e, "del", drag=True))
        self.lay.bind("<ButtonRelease-1>", self.end_stroke)
        self.lay.bind("<ButtonRelease-3>", self.end_stroke)
        self.status = tk.Label(r, anchor=tk.W, relief=tk.SUNKEN)
        self.status.pack(side=tk.BOTTOM, fill=tk.X)

    def say(self, text):
        self.status.config(text=text)

    def set_title(self):
        star = "*" if self.dirty else ""
        self.root.title(f"Z-Police tile editor{star}: {rel(self.path)}")

    # ------------------------------------------------------------ helpers
    def tiles(self):
        return self.d["tiles"]

    def names(self):
        return [t["name"] for t in self.tiles()]

    def cur(self):
        return self.tiles()[self.sel]

    def px(self, t=None):
        """the tile's pixels as 8 lists of colour indices"""
        t = t or self.cur()
        return [[int(ch, 16) for ch in row] for row in t["rows"]]

    def set_px(self, p, t=None):
        t = t or self.cur()
        t["rows"] = ["".join(f"{v:x}" for v in row) for row in p]

    def flags(self):
        """The flags tiles are put with (the ticks)"""
        return ((ct.MIRROR_X if self.fx.get() else 0) | (ct.MIRROR_Y if self.fy.get() else 0)
                | (ct.ROTATE if self.fr.get() else 0) | (ct.ULA_OVER if self.fu.get() else 0))

    def toggle_flag(self, var):
        if isinstance(self.root.focus_get(), (tk.Entry, tk.Spinbox)):
            return
        var.set(not var.get())
        self.draw_tile()

    def image(self, name, flags, scale):
        """A tile as a PhotoImage at scale (see-through as SEE)"""
        flags &= ~ct.ULA_OVER                   # (not in the picture)
        key = (name, flags, scale)
        if key in self.cache:
            return self.cache[key]
        t = next(t for t in self.tiles() if t["name"] == name)
        p = self.px(t)
        bank = self.d["banks"][t.get("bank", 0)]
        img = tk.PhotoImage(width=8 * scale, height=8 * scale)
        rows = []
        for v in range(8):
            line = []
            for u in range(8):
                su, sv = ct.source(u, v, flags)
                i = p[sv][su]
                c = SEE if i == 0 else hexc(bank[i])
                line += [c] * scale
            rows += ["{" + " ".join(line) + "}"] * scale
        img.put(" ".join(rows))
        self.cache[key] = img
        return img

    def forget(self, name=None):
        """Drop cached images (one tile's, or all when the colours change)"""
        self.cache = {k: v for k, v in self.cache.items() if name is not None and k[0] != name}

    # ------------------------------------------------------------- drawing
    def refresh_all(self):
        self.forget()
        self.refresh_list()
        self.draw_tile()
        self.draw_palette()
        self.draw_layout()
        self.set_title()

    def refresh_list(self):
        self.lst.delete(0, tk.END)
        for k, n in enumerate(self.names()):
            used = sum(1 for row in self.d["layout"] for c in row if c.split("|")[0] == n)
            self.lst.insert(tk.END, f"{ct.FIRST + k:3d} {n}  ({used})")
        self.lst.selection_clear(0, tk.END)
        self.lst.selection_set(self.sel)
        self.lst.see(self.sel)

    def draw_tile(self):
        self.title.config(text=f"Tile {ct.FIRST + self.sel}: {self.cur()['name']}")
        self.cv.delete("all")
        p = self.px()
        for v in range(8):
            for u in range(8):
                i = p[v][u]
                c = SEE if i == 0 else hexc(self.bank()[i])
                self.cv.create_rectangle(u * PIX, v * PIX, (u + 1) * PIX, (v + 1) * PIX, fill=c, outline="#303030")
                if i == 0:
                    self.cv.create_line(u * PIX + 4, v * PIX + 4, (u + 1) * PIX - 4, (v + 1) * PIX - 4, fill="#602060")
        self.pv.delete("all")
        n = self.cur()["name"]
        self.pv.create_image(4, 4, image=self.image(n, 0, 1), anchor=tk.NW)
        self.pv.create_image(20, 4, image=self.image(n, 0, 2), anchor=tk.NW)
        img = self.image(n, 0, 2)
        for a in range(3):
            for b in range(3):
                self.pv.create_image(48 + a * 16, 4 + b * 16 if b < 3 else 4, image=img, anchor=tk.NW)
        self.pv.config(height=4 + 3 * 16 + 4)
        if hasattr(self, "flag_pv"):            # as it will be put
            self.flag_pv.delete("all")
            self.flag_pv.create_image(2, 2, image=self.image(n, self.flags(), 2), anchor=tk.NW)

    def bank(self):
        """The selected tile's bank's 16 colours"""
        return self.d["banks"][self.cur().get("bank", 0)]

    def draw_palette(self):
        self.pal.delete("all")
        k = self.cur().get("bank", 0)
        nb = len(self.d["banks"])
        self.bank_spin.config(to=nb - 1)
        self.bank_var.set(k)
        users = sum(1 for t in self.tiles() if t.get("bank", 0) == k)
        self.bank_info.config(text=f"of {nb} (0-{nb - 1}); {users} tile{'s' if users != 1 else ''} use it")
        for i, c in enumerate(self.bank()):
            x, y = (i % 8) * PIX, (i // 8) * 24
            fill = SEE if i == 0 else hexc(c)
            self.pal.create_rectangle(x + 2, y + 2, x + PIX - 2, y + 22, fill=fill, outline="#000")
            txt = "see" if i == 0 else f"{i:x}"
            self.pal.create_text(x + PIX // 2, y + 12, text=txt, fill="#fff" if sum(ct.rgb9(c)) < 380 else "#000",
                                 font=("TkDefaultFont", 7))
            if i == self.fg:
                self.pal.create_rectangle(x, y, x + PIX, y + 24, outline="#ffff00", width=2)
            if i == self.bg:
                self.pal.create_rectangle(x + 3, y + 3, x + PIX - 3, y + 21, outline="#00ffff", width=2)
        self.lr.config(text=f"Left (yellow): {self.colour_text(self.fg)}\n"
                            f"Right (cyan): {self.colour_text(self.bg)}", justify=tk.LEFT)

    def colour_text(self, i):
        """Colour i of the tile's bank: 9-bit, its r, g, b and RGB in hex"""
        if i == 0:
            return "0, see-through"
        c = self.bank()[i]
        r, g, b = ct.rgb9(c)
        return (f"{i:x}  ${c:03X}  (r {c >> 6}, g {c >> 3 & 7}, b {c & 7})  "
                f"RGB #{r:02X}{g:02X}{b:02X}")

    def draw_layout(self):
        z = self.zoom.get()
        cell = 8 * z
        self.lay.delete("all")
        self.lay.config(width=min(COLS * cell, LAY_MAX_W), height=min(ROWS * cell, LAY_MAX_H),
                        scrollregion=(0, 0, COLS * cell, ROWS * cell))
        c0, r0, c1, r1 = VIEW
        self.lay.create_rectangle(c0 * cell, r0 * cell, c1 * cell, r1 * cell, fill="#202030", outline="")
        self.lay.create_text((c0 + c1) * cell // 2, (r0 + r1) * cell // 2, fill="#606080",
                             text="the view and the ULA panel\n(tiles here are drawn over them)", justify=tk.CENTER)
        self.items = {}
        for r in range(ROWS):
            for c in range(COLS):
                self.draw_cell(r, c)
        self.lay.create_rectangle(c0 * cell, r0 * cell, c1 * cell, r1 * cell, outline="#8080ff", dash=(4, 3))
        if self.guides.get():
            # the compass marks (sprite rows 8-23), its pointer (152-167, 24-39),
            # the humans column (x 8-23)
            for (x0, y0, x1, y1, t) in ((0, 8, 320, 24, "compass"), (152, 24, 168, 40, ""),
                                        (8, 32, 24, 224, "humans")):
                self.lay.create_rectangle(x0 * z, y0 * z, x1 * z, y1 * z, outline="#ffff00", dash=(2, 4))
                if t:
                    self.lay.create_text(x1 * z - 4, y0 * z + 2, text=t, anchor=tk.NE, fill="#ffff00",
                                         font=("TkDefaultFont", 7))

    def draw_cell(self, r, c):
        z = self.zoom.get()
        cell = 8 * z
        for old in self.items.pop((r, c), ()):
            self.lay.delete(old)
        v = self.d["layout"][r][c]
        if not v:
            return
        n, flags = ct.cell_parts(v)
        if n not in self.names():
            return
        ids = [self.lay.create_image(c * cell, r * cell, image=self.image(n, flags, z), anchor=tk.NW)]
        if flags & ct.ULA_OVER:                 # the ULA over it: a mark
            m = max(2, cell // 3)
            ids.append(self.lay.create_polygon(c * cell, r * cell, c * cell + m, r * cell, c * cell,
                                               r * cell + m, fill="#ffff00", outline="#000000"))
        self.items[(r, c)] = ids

    def redraw_tile_cells(self, name):
        self.forget(name)
        for r in range(ROWS):
            for c in range(COLS):
                if self.d["layout"][r][c].split("|")[0] == name:
                    self.draw_cell(r, c)

    # --------------------------------------------------------------- edits
    def push_undo(self):
        self.undo.append(copy.deepcopy(self.d))
        del self.undo[:-100]
        self.redo.clear()

    def changed(self):
        self.dirty = True
        self.set_title()

    def edit_px(self, fn):
        self.push_undo()
        self.set_px(fn(self.px()))
        self.after_px()

    def after_px(self):
        self.changed()
        self.draw_tile()
        self.redraw_tile_cells(self.cur()["name"])

    def cmd_shift(self, dx, dy):
        if self.root.focus_get() is self.lst:
            return
        self.edit_px(lambda p: [[p[(y - dy) % 8][(x - dx) % 8] for x in range(8)] for y in range(8)])

    def cmd_replace(self):
        self.edit_px(lambda p: [[self.fg if v == self.bg else v for v in row] for row in p])

    def cmd_undo(self):
        if not self.undo:
            return self.say("nothing to undo")
        self.redo.append(copy.deepcopy(self.d))
        self.d = self.undo.pop()
        self.sel = min(self.sel, len(self.tiles()) - 1)
        self.changed()
        self.refresh_all()

    def cmd_redo(self):
        if not self.redo:
            return self.say("nothing to redo")
        self.undo.append(copy.deepcopy(self.d))
        self.d = self.redo.pop()
        self.sel = min(self.sel, len(self.tiles()) - 1)
        self.changed()
        self.refresh_all()

    def cmd_copy(self):
        self.clip = list(self.cur()["rows"])
        self.say(f"copied {self.cur()['name']}")

    def cmd_paste(self):
        if not self.clip:
            return self.say("nothing copied")
        self.push_undo()
        self.cur()["rows"] = list(self.clip)
        self.after_px()

    # pixels
    def on_pixel(self, ev, which):
        u, v = ev.x // PIX, ev.y // PIX
        if not (0 <= u < 8 and 0 <= v < 8):
            return
        p = self.px()
        if ev.state & 0x4:                      # Ctrl: pick up
            setattr(self, which, p[v][u])
            self.draw_palette()
            return
        colour = self.fg if which == "fg" else self.bg
        if self.drag is None:
            self.push_undo()
            self.drag = "px"
        if self.tool.get() == "fill":
            old = p[v][u]
            if old == colour:
                return
            todo = [(u, v)]
            while todo:
                x, y = todo.pop()
                if 0 <= x < 8 and 0 <= y < 8 and p[y][x] == old:
                    p[y][x] = colour
                    todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        else:
            if p[v][u] == colour:
                return
            p[v][u] = colour
        self.set_px(p)
        self.after_px()

    def end_stroke(self, ev=None):
        self.drag = None

    # colours
    def on_swatch(self, ev, which):
        i = (ev.y // 24) * 8 + ev.x // PIX
        if 0 <= i < 16:
            setattr(self, which, i)
            self.draw_palette()
            self.say(f"{'left' if which == 'fg' else 'right'} colour: {self.colour_text(i)}")

    def on_swatch_edit(self, ev):
        i = (ev.y // 24) * 8 + ev.x // PIX
        if not 1 <= i < 16:
            return self.say("colour 0 is see-through: it is never drawn")
        c = self.bank()[i]
        w = tk.Toplevel(self.root)
        w.title(f"Colour {i:x} of bank {self.cur().get('bank', 0)}")
        w.transient(self.root)
        vs = []
        for k, (lab, val, hi) in enumerate((("Red", c >> 6, 7), ("Green", c >> 3 & 7, 7), ("Blue", c & 7, 7))):
            tk.Label(w, text=f"{lab} (0-{hi})").grid(row=k, column=0, sticky=tk.W, padx=6)
            v = tk.IntVar(value=val)
            tk.Spinbox(w, from_=0, to=hi, width=4, textvariable=v).grid(row=k, column=1, padx=6, pady=2)
            vs.append(v)

        def ok():
            try:
                r, g, b = (min(max(int(v.get()), 0), 7) for v in vs)
            except (tk.TclError, ValueError):
                return messagebox.showerror("Not a number", "r, g and b are numbers.", parent=w)
            self.push_undo()
            self.bank()[i] = r << 6 | g << 3 | b
            w.destroy()
            self.changed()
            self.forget()
            self.draw_palette()
            self.draw_tile()
            self.draw_layout()
        tk.Button(w, text="OK", command=ok).grid(row=3, column=0, pady=6)
        tk.Button(w, text="Cancel", command=w.destroy).grid(row=3, column=1, pady=6)

    # banks
    def on_bank(self):
        try:
            k = int(self.bank_var.get())
        except (tk.TclError, ValueError):
            return
        k = min(max(k, 0), len(self.d["banks"]) - 1)
        if k == self.cur().get("bank", 0):
            return
        self.push_undo()
        self.cur()["bank"] = k
        self.changed()
        self.draw_palette()
        self.draw_tile()
        self.redraw_tile_cells(self.cur()["name"])
        self.say(f"{self.cur()['name']}: bank {k}")

    def cmd_add_bank(self):
        if len(self.d["banks"]) >= ct.MAX_BANKS:
            return messagebox.showinfo("Banks", f"At most {ct.MAX_BANKS} banks.")
        self.push_undo()
        self.d["banks"].append(list(self.bank()))
        self.cur()["bank"] = len(self.d["banks"]) - 1
        self.changed()
        self.forget(self.cur()["name"])
        self.draw_palette()
        self.draw_tile()
        self.say(f"bank {len(self.d['banks']) - 1} added (a copy), and {self.cur()['name']} in it")

    def cmd_del_bank(self):
        k = self.cur().get("bank", 0)
        if len(self.d["banks"]) <= 1:
            return messagebox.showinfo("Banks", "The last bank stays.")
        users = [t["name"] for t in self.tiles() if t.get("bank", 0) == k]
        if not messagebox.askyesno("Delete bank", f"Delete bank {k}? Its {len(users)} tile(s) go to bank 0 "
                                   "(the banks after it move down one)."):
            return
        self.push_undo()
        del self.d["banks"][k]
        for t in self.tiles():
            b = t.get("bank", 0)
            t["bank"] = 0 if b == k else (b - 1 if b > k else b)
        self.changed()
        self.forget()
        self.draw_palette()
        self.draw_tile()
        self.draw_layout()

    # the console
    def on_cell(self, ev, what, drag=False):
        z = self.zoom.get()
        c = int(self.lay.canvasx(ev.x)) // (8 * z)          # (scrolled)
        r = int(self.lay.canvasy(ev.y)) // (8 * z)
        if not (0 <= c < COLS and 0 <= r < ROWS):
            return
        cur = self.d["layout"][r][c]
        if what == "pick":
            if not cur:
                return self.say(f"cell {c},{r}: empty")
            n, flags = ct.cell_parts(cur)
            self.fx.set(bool(flags & ct.MIRROR_X))
            self.fy.set(bool(flags & ct.MIRROR_Y))
            self.fr.set(bool(flags & ct.ROTATE))
            self.fu.set(bool(flags & ct.ULA_OVER))
            self.select(self.names().index(n))
            return self.say(f"cell {c},{r}: {cur}")
        if what == "del" or ev.state & 0x4:     # deleted (right), or Ctrl+left
            new = ""
        else:
            new = ct.cell_text(self.cur()["name"], self.flags() ^ (ct.MIRROR_X if ev.state & 0x1 else 0))
        if new == cur:
            return
        if self.drag is None:
            self.push_undo()
            self.drag = "lay"
        self.d["layout"][r][c] = new
        self.changed()
        self.draw_cell(r, c)
        c0, r0, c1, r1 = VIEW
        inside = c0 <= c < c1 and r0 <= r < r1
        self.say(f"cell {c},{r}: {new or 'empty'}" + ("  (over the view or panel)" if inside and new else ""))
        if not drag:
            self.refresh_list()

    # tiles
    def on_list(self, ev):
        s = self.lst.curselection()
        if s:
            self.select(s[0])

    def select(self, k):
        self.sel = k
        self.refresh_list()
        self.draw_tile()
        self.draw_palette()

    def cmd_add(self, dup=False):
        if len(self.tiles()) >= ct.MAX_TILES:
            return messagebox.showinfo("Full", f"At most {ct.MAX_TILES} tiles ({ct.FIRST}-{ct.FIRST + ct.MAX_TILES - 1}).")
        base = self.cur()["name"] + "_2" if dup else "TILE"
        name, k = base, 1
        while name in self.names():
            k += 1
            name = f"{base}{k}"
        name = simpledialog.askstring("New tile", "Its name (letters, digits, _):", initialvalue=name,
                                      parent=self.root)
        if not name:
            return
        if name in self.names() or not all(ch.isalnum() or ch == "_" for ch in name):
            return messagebox.showerror("Name", f"{name!r}: a new name of letters, digits and _.")
        self.push_undo()
        rows = list(self.cur()["rows"]) if dup else ["0" * 8] * 8
        self.tiles().insert(self.sel + 1, {"name": name, "bank": self.cur().get("bank", 0) if dup else 0,
                                           "rows": rows})
        self.sel += 1
        self.changed()
        self.refresh_all()

    def cmd_rename(self):
        old = self.cur()["name"]
        name = simpledialog.askstring("Rename", "Its new name:", initialvalue=old, parent=self.root)
        if not name or name == old:
            return
        if name in self.names() or not all(ch.isalnum() or ch == "_" for ch in name):
            return messagebox.showerror("Name", f"{name!r}: a new name of letters, digits and _.")
        self.push_undo()
        self.cur()["name"] = name
        for row in self.d["layout"]:
            for c, v in enumerate(row):
                n, sep, m = v.partition("|")      # (flags kept)
                if n == old:
                    row[c] = name + sep + m
        self.changed()
        self.refresh_all()

    def cmd_delete(self):
        if len(self.tiles()) <= 1:
            return messagebox.showinfo("Delete", "The last tile stays.")
        n = self.cur()["name"]
        used = sum(1 for row in self.d["layout"] for c in row if c.split("|")[0] == n)
        if used and not messagebox.askyesno("Delete", f"{n} is in {used} cells of the console: "
                                            "empty them and delete it?"):
            return
        self.push_undo()
        for row in self.d["layout"]:
            for c, v in enumerate(row):
                if v.split("|")[0] == n:
                    row[c] = ""
        del self.tiles()[self.sel]
        self.sel = min(self.sel, len(self.tiles()) - 1)
        self.changed()
        self.refresh_all()

    def cmd_move(self, d):
        k = self.sel + d
        if not 0 <= k < len(self.tiles()):
            return
        self.push_undo()
        t = self.tiles()
        t[self.sel], t[k] = t[k], t[self.sel]
        self.sel = k
        self.changed()
        self.refresh_list()
        self.draw_tile()

    # ------------------------------------------------------------- files
    def save(self):
        errs = ct.problems(self.d)
        if errs:
            return messagebox.showerror("Can't save", "The game can't use them:\n\n- " + "\n- ".join(errs))
        try:
            ct.save(self.d, self.path)
        except OSError as e:
            return messagebox.showerror("Can't save", str(e))
        self.dirty = False
        self.set_title()
        inside = [(c, r) for r in range(VIEW[1], VIEW[3]) for c in range(VIEW[0], VIEW[2])
                  if self.d["layout"][r][c]]
        warn = f"; {len(inside)} cells over the view or panel" if inside else ""
        self.say(f"saved {rel(self.path)} (build.bat puts it in the game){warn}")

    def reload(self):
        if self.dirty and not messagebox.askyesno("Reload", "Forget the changes?"):
            return
        try:
            self.d = ct.load(self.path)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't read", str(e))
        self.undo.clear()
        self.redo.clear()
        self.sel = 0
        self.dirty = False
        self.refresh_all()

    def cmd_png(self):
        from tkinter import filedialog
        p = filedialog.asksaveasfilename(defaultextension=".png", initialfile="console_tiles.png")
        if p:
            ct.preview(p, d=self.d)
            self.say(f"wrote {p}")

    def quit(self):
        if self.dirty and not messagebox.askyesno("Quit", "The tiles have changed: quit without saving?"):
            return
        self.root.destroy()


def main():
    root = tk.Tk()
    Editor(root)
    root.mainloop()


if __name__ == "__main__":
    main()
