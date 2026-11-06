"""Z-Police HUD sprite editor: the 16 x 16 hardware sprites (Layer 3) of the HUD,
sprites/hud.json: the human status icons, the compass marks and the viewport
frame (tools/hudsprites.py has the format).  The figures in the 3D view are
tools/sprite_editor.py's.

    python tools/hud_sprite_editor.py [SPRITE NAME]

On the left: the sprites, by name and as a sheet.  In the middle the pixels,
enlarged.  On the right the 256 colours (RRRGGGBB, numbered in hex, $E3 is
transparent), the tools and previews: the sprite at the game's size and twice
it, and what the game makes of it: the human icons together, the compass bar,
the frame's corners and stretched edges.

    Left button     paint the left colour      Right button    the right one
    Ctrl+click      pick up the pixel's colour, for that button
    Ctrl+Z, Ctrl+Y  undo, redo                 Ctrl+S          save
    Ctrl+C, Ctrl+V  copy this sprite, paste over it
    Arrow keys      shift the sprite, wrapping round

Tools: Pencil, Fill (the area of the clicked colour, joined side to side),
Line, Box (an outline).  Edit menu: mirror, flip, rotate, shift, replace the
right colour with the left, clear.  Sprite menu: add one (its name is the
assembler's), delete one that was added.

Save checks them (hudsprites.problems) and writes the file; build.bat
(gentables.py) then puts them in the game.
"""
import copy
import os
import sys
import tkinter as tk
from tkinter import messagebox, simpledialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hudsprites as hs

SIZE = hs.SIZE
T = hs.TRANSPARENT
SWATCH = 14                             # a colour's square, with its gap
SHEET_COLS = 4
SHEET_CELL = 40
BACKGROUNDS = (("Black", "#000000"), ("Panel", hs.hex_rgb(0x6D)), ("Sky", "#6088c8"))
USE_W, USE_H = 236, 128
CHECK = ("#32243c", "#3c2c48")          # transparent: not a colour the sprites use


def compass_layout(names):
    """The bar as the game lays it out: a mark every 32 pixels, the pointer
    under the middle one."""
    marks = ["CSPR_N", "CSPR_TICK", "CSPR_DOT", "CSPR_TICK", "CSPR_E", "CSPR_TICK", "CSPR_DOT"]
    out = [(m, 2 + 32 * k - 32 * (k > 3), 40 if k > 3 else 8, 1, 1, False, False)
           for k, m in enumerate(marks)]
    return out + [("CSPR_PTR", 2 + 32 * 1, 24, 1, 1, False, False)]


def human_layout(names):
    return [(n, 8 + 54 * k, 16, 2, 2, False, False) for k, n in enumerate(hs.REQUIRED_NAMES[:4])]


def frame_layout(names):
    """The frame at the game's size, with its long edges shortened (frame_tab,
    hud_sprites.asm): corner, edges at their scales, mirrored to fit."""
    L, R, T_, B = 8, 8 + 16 + 160, 4, 4 + 16 + 64
    return [("FRM_H", L + 16, T_, 8, 1, False, False), ("FRM_H", L + 16 + 32, T_, 8, 1, False, False),
            ("FRM_V", L, T_ + 16, 1, 4, False, False), ("FRM_V", R, T_ + 16, 1, 4, True, False),
            ("FRM_CRN", L, T_, 1, 1, False, False), ("FRM_CRN", R, T_, 1, 1, True, False),
            ("FRM_CRN_P", L, B, 1, 1, False, True), ("FRM_CRN_P", R, B, 1, 1, True, True),
            ("FRM_CRN_S", L, B + 16, 1, 1, False, True), ("FRM_CRN_S", R, B + 16, 1, 1, True, True)]


def usage(name):
    """(what the In the game preview shows, its layout) for a sprite."""
    if name.startswith("HSPR_"):
        return "the human icons, at twice size", human_layout
    if name.startswith("CSPR_"):
        return "the compass bar (split in two)", compass_layout
    if name.startswith("FRM_"):
        return "the viewport frame (shortened)", frame_layout
    return None, None


class Editor:
    def __init__(self, root, start=None, path=hs.HUD_FILE):
        self.root = root
        self.path = path
        self.zoom = 24
        self.sprites = hs.load(path)
        self.cur = 0
        self.dirty = False
        self.undo, self.redo = [], []
        self.clip = None
        self.left, self.right = 0xFF, T
        self.tool = tk.StringVar(value="pencil")
        self.grid = tk.BooleanVar(value=True)
        self.bg = tk.StringVar(value=BACKGROUNDS[0][1])
        self.btn = None                 # the button held down, on the canvas
        self.start = None               # where a line or box began
        self.last = None                # the pencil's last cell
        self.images = {}                # the previews' PhotoImages: tk needs them kept
        self.sheet_imgs = []
        self.build_ui()
        self.refresh_list()
        names = [s["name"] for s in self.sprites]
        self.select(names.index(start) if start in names else 0)

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        r = self.root
        mb = tk.Menu(r)
        fm = tk.Menu(mb, tearoff=0)
        fm.add_command(label="Save", command=self.cmd_save, accelerator="Ctrl+S")
        fm.add_command(label="Reload", command=self.cmd_reload)
        fm.add_command(label="Check", command=self.cmd_check)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.cmd_quit)
        mb.add_cascade(label="File", menu=fm)
        em = tk.Menu(mb, tearoff=0)
        em.add_command(label="Undo", command=self.cmd_undo, accelerator="Ctrl+Z")
        em.add_command(label="Redo", command=self.cmd_redo, accelerator="Ctrl+Y")
        em.add_separator()
        em.add_command(label="Copy this sprite", command=self.cmd_copy, accelerator="Ctrl+C")
        em.add_command(label="Paste over this sprite", command=self.cmd_paste, accelerator="Ctrl+V")
        em.add_separator()
        em.add_command(label="Mirror left-right", command=lambda: self.edit(hs.mirror))
        em.add_command(label="Flip top-bottom", command=lambda: self.edit(hs.flip))
        em.add_command(label="Rotate a quarter turn", command=lambda: self.edit(hs.rotate))
        for name, dx, dy in (("left", -1, 0), ("right", 1, 0), ("up", 0, -1), ("down", 0, 1)):
            em.add_command(label=f"Shift {name}", command=lambda dx=dx, dy=dy: self.cmd_shift(dx, dy))
        em.add_separator()
        em.add_command(label="Replace the right colour with the left",
                       command=lambda: self.edit(lambda p: hs.replace(p, self.right, self.left)))
        em.add_command(label="Clear", command=lambda: self.edit(lambda p: hs.blank()))
        mb.add_cascade(label="Edit", menu=em)
        sm = tk.Menu(mb, tearoff=0)
        sm.add_command(label="Add a sprite...", command=self.cmd_add)
        sm.add_command(label="Delete this sprite", command=self.cmd_delete)
        mb.add_cascade(label="Sprite", menu=sm)
        vm = tk.Menu(mb, tearoff=0)
        for z in (16, 24, 32):
            vm.add_command(label=f"{z} pixels a pixel", command=lambda z=z: self.set_zoom(z))
        vm.add_checkbutton(label="Grid", variable=self.grid, command=self.draw_pixels)
        mb.add_cascade(label="View", menu=vm)
        r.config(menu=mb)
        for key, fn in (("<Control-s>", self.cmd_save), ("<Control-z>", self.cmd_undo),
                        ("<Control-y>", self.cmd_redo), ("<Control-c>", self.cmd_copy),
                        ("<Control-v>", self.cmd_paste)):
            r.bind(key, lambda e, fn=fn: fn())
        for key, dx, dy in (("<Left>", -1, 0), ("<Right>", 1, 0), ("<Up>", 0, -1), ("<Down>", 0, 1)):
            r.bind(key, lambda e, dx=dx, dy=dy: self.cmd_shift(dx, dy))
        r.protocol("WM_DELETE_WINDOW", self.cmd_quit)

        left = tk.Frame(r, padx=6, pady=6)
        left.pack(side=tk.LEFT, fill=tk.Y)
        tk.Label(left, text="Sprites").pack(anchor=tk.W)
        self.list = tk.Listbox(left, height=hs.MAX_SPRITES // 2 + 1, exportselection=False, width=24)
        self.list.pack(anchor=tk.W)
        self.list.bind("<<ListboxSelect>>", self.on_list)
        self.sheet = tk.Canvas(left, width=SHEET_COLS * SHEET_CELL, height=4 * SHEET_CELL,
                               bg="#000000", highlightthickness=0)
        self.sheet.pack(anchor=tk.W, pady=(8, 0))
        self.sheet.bind("<Button-1>", self.on_sheet)

        mid = tk.Frame(r, padx=6, pady=6)
        mid.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.desc = tk.Label(mid, text="", anchor=tk.W, justify=tk.LEFT, wraplength=SIZE * 24)
        self.desc.pack(fill=tk.X)
        self.canvas = tk.Canvas(mid, bg="#202020", highlightthickness=0,
                                width=SIZE * 24, height=SIZE * 24)
        self.canvas.pack(anchor=tk.NW)
        for b in ("<Button-1>", "<B1-Motion>", "<ButtonRelease-1>",
                  "<Button-3>", "<B3-Motion>", "<ButtonRelease-3>"):
            self.canvas.bind(b, self.on_mouse)
        self.canvas.bind("<Motion>", self.on_hover)
        self.status = tk.Label(mid, text="", anchor=tk.W)
        self.status.pack(fill=tk.X)

        right = tk.Frame(r, padx=6, pady=6)
        right.pack(side=tk.LEFT, fill=tk.Y)
        tk.Label(right, text="Colours ($00-$FF; the crossed one, $E3, is transparent)").pack(anchor=tk.W)
        self.pal = tk.Canvas(right, width=16 * SWATCH + 2, height=16 * SWATCH + 2, highlightthickness=0)
        self.pal.pack(anchor=tk.W)
        self.pal.bind("<Button-1>", lambda e: self.on_swatch(e, "left"))
        self.pal.bind("<Button-3>", lambda e: self.on_swatch(e, "right"))
        for v in range(256):
            x, y = (v & 15) * SWATCH + 1, (v >> 4) * SWATCH + 1
            if v == T:
                self.pal.create_rectangle(x, y, x + SWATCH, y + SWATCH, fill="#808080", width=0)
                self.pal.create_line(x, y, x + SWATCH, y + SWATCH, fill="#ff0000", width=2)
            else:
                self.pal.create_rectangle(x, y, x + SWATCH, y + SWATCH, fill=hs.hex_rgb(v), width=0)
        row = tk.Frame(right)
        row.pack(anchor=tk.W, pady=(4, 0))
        self.lchip = tk.Canvas(row, width=26, height=20, highlightthickness=1)
        self.rchip = tk.Canvas(row, width=26, height=20, highlightthickness=1)
        self.lchip.grid(row=0, column=0)
        self.pick_l = tk.Label(row, text="", width=8, anchor=tk.W)
        self.pick_l.grid(row=0, column=1)
        self.rchip.grid(row=0, column=2)
        self.pick_r = tk.Label(row, text="", width=8, anchor=tk.W)
        self.pick_r.grid(row=0, column=3)
        tk.Button(row, text="Hex...", command=self.cmd_hex).grid(row=0, column=4, padx=(6, 0))
        tk.Label(right, text="In this sprite").pack(anchor=tk.W, pady=(6, 0))
        self.used = tk.Canvas(right, width=16 * SWATCH + 2, height=2 * SWATCH + 2, highlightthickness=0)
        self.used.pack(anchor=tk.W)
        self.used.bind("<Button-1>", lambda e: self.on_used(e, "left"))
        self.used.bind("<Button-3>", lambda e: self.on_used(e, "right"))
        tools = tk.Frame(right)
        tools.pack(anchor=tk.W, pady=(6, 0))
        tk.Label(tools, text="Tool").pack(side=tk.LEFT)
        for name, val in (("Pencil", "pencil"), ("Fill", "fill"), ("Line", "line"), ("Box", "box")):
            tk.Radiobutton(tools, text=name, variable=self.tool, value=val).pack(side=tk.LEFT)
        bgs = tk.Frame(right)
        bgs.pack(anchor=tk.W)
        tk.Label(bgs, text="Behind it").pack(side=tk.LEFT)
        for name, val in BACKGROUNDS:
            tk.Radiobutton(bgs, text=name, variable=self.bg, value=val,
                           command=self.draw_previews).pack(side=tk.LEFT)
        self.preview = tk.Canvas(right, width=USE_W, height=36, highlightthickness=0)
        self.preview.pack(anchor=tk.W)
        self.use_label = tk.Label(right, text="", anchor=tk.W)
        self.use_label.pack(anchor=tk.W, pady=(6, 0))
        self.use = tk.Canvas(right, width=USE_W, height=USE_H, highlightthickness=0)
        self.use.pack(anchor=tk.W)

    def say(self, text):
        self.status.config(text=text)

    def set_title(self):
        star = "*" if self.dirty else ""
        self.root.title(f"Z-Police HUD sprites - {self.sprites[self.cur]['name']}{star}")

    def set_zoom(self, z):
        self.zoom = z
        self.canvas.config(width=SIZE * z, height=SIZE * z)
        self.draw_pixels()

    # ------------------------------------------------------------ selection
    def px(self):
        return self.sprites[self.cur]["pixels"]

    def refresh_list(self):
        self.list.delete(0, tk.END)
        for k, s in enumerate(self.sprites):
            self.list.insert(tk.END, f"{k:2d}  {s['name']}")
        self.sheet.config(height=((len(self.sprites) + SHEET_COLS - 1) // SHEET_COLS) * SHEET_CELL)

    def on_list(self, ev):
        sel = self.list.curselection()
        if sel:
            self.select(sel[0])

    def on_sheet(self, ev):
        k = ev.y // SHEET_CELL * SHEET_COLS + ev.x // SHEET_CELL
        if 0 <= k < len(self.sprites):
            self.select(k)

    def select(self, k):
        self.cur = k
        self.list.selection_clear(0, tk.END)
        self.list.selection_set(k)
        self.list.see(k)
        self.desc.config(text=hs.description(self.sprites[k]["name"]))
        self.set_title()
        self.redraw()

    # -------------------------------------------------------------- drawing
    def redraw(self):
        self.draw_pixels()
        self.draw_sheet()
        self.draw_previews()
        self.draw_colours()

    def draw_pixels(self):
        c, z, px = self.canvas, self.zoom, self.px()
        c.delete("all")
        outline = "#303030" if self.grid.get() else ""
        for y in range(SIZE):
            for x in range(SIZE):
                v = px[y][x]
                fill = CHECK[(x + y) % 2] if v == T else hs.hex_rgb(v)
                c.create_rectangle(x * z, y * z, (x + 1) * z, (y + 1) * z, fill=fill, outline=outline)
        if self.grid.get():             # the middle, to centre things by
            c.create_line(8 * z, 0, 8 * z, 16 * z, fill="#606060")
            c.create_line(0, 8 * z, 16 * z, 8 * z, fill="#606060")

    def image(self, w, h, bg, items):
        """A w x h PhotoImage of bg with items laid on it: (pixels, x, y, x
        scale, y scale, x mirror, y mirror)."""
        rows = [[bg] * w for _ in range(h)]
        for px, x0, y0, sx, sy, mx, my in items:
            for y in range(SIZE):
                for x in range(SIZE):
                    v = px[SIZE - 1 - y if my else y][SIZE - 1 - x if mx else x]
                    if v == T:
                        continue
                    col = hs.hex_rgb(v)
                    for dy in range(sy):
                        Y = y0 + y * sy + dy
                        if 0 <= Y < h:
                            row = rows[Y]
                            for dx in range(sx):
                                X = x0 + x * sx + dx
                                if 0 <= X < w:
                                    row[X] = col
        img = tk.PhotoImage(width=w, height=h)
        img.put(" ".join("{" + " ".join(r) + "}" for r in rows))
        return img

    def draw_sheet(self):
        s = self.sheet
        s.delete("all")
        self.sheet_imgs = []
        for k, sp in enumerate(self.sprites):
            x = k % SHEET_COLS * SHEET_CELL
            y = k // SHEET_COLS * SHEET_CELL
            img = self.image(32, 32, "#000000", [(sp["pixels"], 0, 0, 2, 2, False, False)])
            self.sheet_imgs.append(img)
            s.create_image(x + 4, y + 4, image=img, anchor=tk.NW)
            if k == self.cur:
                s.create_rectangle(x + 1, y + 1, x + SHEET_CELL - 2, y + SHEET_CELL - 2, outline="#ffff00")

    def draw_previews(self):
        bg = self.bg.get()
        px = self.px()
        pv = self.preview
        pv.delete("all")
        self.images["size"] = self.image(USE_W, 36, bg, [(px, 8, 10, 1, 1, False, False),
                                                         (px, 48, 2, 2, 2, False, False)])
        pv.create_image(0, 0, image=self.images["size"], anchor=tk.NW)
        name = self.sprites[self.cur]["name"]
        text, layout = usage(name)
        self.use.delete("all")
        self.use_label.config(text=f"In the game: {text}" if layout else "In the game: not used yet")
        if layout:
            by = {s["name"]: s["pixels"] for s in self.sprites}
            items = [(by[n], x, y, sx, sy, mx, my) for n, x, y, sx, sy, mx, my in layout(by)]
            self.images["use"] = self.image(USE_W, USE_H, bg, items)
            self.use.create_image(0, 0, image=self.images["use"], anchor=tk.NW)

    def draw_colours(self):
        self.pal.delete("mark")
        for v, col, wide in ((self.right, "#00ffff", 1), (self.left, "#ffff00", 2)):
            x, y = (v & 15) * SWATCH + 1, (v >> 4) * SWATCH + 1
            self.pal.create_rectangle(x, y, x + SWATCH, y + SWATCH, outline=col, width=wide, tags="mark")
        for chip, v, lab, side in ((self.lchip, self.left, self.pick_l, "left"),
                                   (self.rchip, self.right, self.pick_r, "right")):
            chip.delete("all")
            chip.config(bg="#808080" if v == T else hs.hex_rgb(v))
            if v == T:
                chip.create_line(0, 0, 28, 22, fill="#ff0000", width=2)
            lab.config(text=f"{side}: ${v:02X}")
        self.used.delete("all")
        self.used_cols = sorted({v for r in self.px() for v in r})
        for k, v in enumerate(self.used_cols[:32]):
            x, y = (k & 15) * SWATCH + 1, (k >> 4) * SWATCH + 1
            self.used.create_rectangle(x, y, x + SWATCH, y + SWATCH, width=1, outline="#000000",
                                       fill="#808080" if v == T else hs.hex_rgb(v))
            if v == T:
                self.used.create_line(x, y, x + SWATCH, y + SWATCH, fill="#ff0000", width=2)

    # -------------------------------------------------------------- colours
    def on_swatch(self, ev, which):
        v = (min(15, ev.y // SWATCH) << 4) | min(15, ev.x // SWATCH)
        setattr(self, which, v)
        self.draw_colours()

    def on_used(self, ev, which):
        k = (ev.y // SWATCH) * 16 + ev.x // SWATCH
        if 0 <= k < len(self.used_cols):
            setattr(self, which, self.used_cols[k])
            self.draw_colours()

    def cmd_hex(self):
        s = simpledialog.askstring("Left colour", "RRRGGGBB, in hex (E3: transparent):",
                                   initialvalue=f"{self.left:02X}", parent=self.root)
        if not s:
            return
        try:
            v = int(s.strip().lstrip("$"), 16)
        except ValueError:
            v = -1
        if not 0 <= v <= 255:
            return messagebox.showerror("Left colour", "Two hex digits, 00 to FF")
        self.left = v
        self.draw_colours()

    # -------------------------------------------------------------- editing
    def push_undo(self):
        self.undo.append((self.cur, copy.deepcopy(self.px())))
        del self.undo[:-200]
        self.redo.clear()

    def changed(self):
        self.dirty = True
        self.set_title()
        self.redraw()

    def edit(self, fn):
        self.push_undo()
        self.sprites[self.cur]["pixels"] = fn(self.px())
        self.changed()

    def cmd_shift(self, dx, dy):
        self.edit(lambda p: hs.shift(p, dx, dy))

    def swap(self, src, dst):
        k, px = src.pop()
        dst.append((k, self.sprites[k]["pixels"]))
        self.sprites[k]["pixels"] = px
        self.dirty = True
        self.select(k)

    def cmd_undo(self):
        if not self.undo:
            return self.say("nothing to undo")
        self.swap(self.undo, self.redo)
        self.say("undone")

    def cmd_redo(self):
        if not self.redo:
            return self.say("nothing to redo")
        self.swap(self.redo, self.undo)
        self.say("redone")

    def cmd_copy(self):
        self.clip = copy.deepcopy(self.px())
        self.say(f"copied {self.sprites[self.cur]['name']}")

    def cmd_paste(self):
        if self.clip is None:
            return self.say("nothing copied")
        self.edit(lambda p: copy.deepcopy(self.clip))

    def cell(self, ev):
        x, y = ev.x // self.zoom, ev.y // self.zoom
        return (x, y) if 0 <= x < SIZE and 0 <= y < SIZE else None

    def on_hover(self, ev):
        at = self.cell(ev)
        if at:
            v = self.px()[at[1]][at[0]]
            self.say(f"x {at[0]}, y {at[1]}: " + ("transparent" if v == T else f"${v:02X}"))

    def on_mouse(self, ev):
        t = ev.type.name                # (str() of it is the number on Python 3.11 on)
        at = self.cell(ev)
        if t == "ButtonPress":
            self.btn = "right" if ev.num == 3 else "left"
            if ev.state & 0x4:          # Ctrl: pick up
                self.btn = None
                if at:
                    setattr(self, "right" if ev.num == 3 else "left", self.px()[at[1]][at[0]])
                    self.draw_colours()
                return
        if self.btn is None:
            return
        colour = getattr(self, self.btn)
        tool = self.tool.get()
        if t == "ButtonPress":
            self.push_undo()
            if tool == "fill":
                if at:
                    self.sprites[self.cur]["pixels"] = hs.fill(self.px(), at, colour)
                    self.changed()
            elif tool == "pencil":
                self.last = at
                if at:
                    self.plot({at}, colour)
            else:
                self.start = at
        elif t == "Motion":
            if tool == "pencil" and at:
                self.plot(hs.line_cells(self.last or at, at), colour)
                self.last = at
            elif tool in ("line", "box") and self.start and at:
                self.rubber(self.shape(tool, at))
        elif t == "ButtonRelease":
            self.canvas.delete("rubber")
            if tool in ("line", "box") and self.start and at:
                self.plot(self.shape(tool, at), colour)
            self.start = self.last = self.btn = None

    def shape(self, tool, at):
        return (hs.line_cells if tool == "line" else hs.rect_cells)(self.start, at)

    def plot(self, cells, colour):
        px = self.px()
        hit = [(x, y) for x, y in cells if px[y][x] != colour]
        for x, y in hit:
            px[y][x] = colour
        if hit:
            self.changed()

    def rubber(self, cells):
        c, z = self.canvas, self.zoom
        c.delete("rubber")
        for x, y in cells:
            c.create_rectangle(x * z + 1, y * z + 1, (x + 1) * z - 1, (y + 1) * z - 1,
                               outline="#ffff00", width=2, tags="rubber")

    # -------------------------------------------------------------- sprites
    def cmd_add(self):
        if len(self.sprites) >= hs.MAX_SPRITES:
            return messagebox.showerror("Add a sprite", f"A bank holds {hs.MAX_SPRITES} sprites.")
        name = simpledialog.askstring("Add a sprite", "Its name, for the assembler\n"
                                      "(capitals, digits and _, e.g. HUD_BOMB):", parent=self.root)
        if not name:
            return
        name = name.strip()
        if not hs.valid_name(name):
            return messagebox.showerror("Add a sprite", "Capitals, digits and _, from a capital.")
        if name in [s["name"] for s in self.sprites]:
            return messagebox.showerror("Add a sprite", f"There's already a {name}.")
        self.sprites.append(hs.new_sprite(name))
        self.dirty = True
        self.refresh_list()
        self.select(len(self.sprites) - 1)

    def cmd_delete(self):
        name = self.sprites[self.cur]["name"]
        if name in hs.REQUIRED_NAMES:
            return messagebox.showinfo("Delete", f"The game uses {name}: it can be cleared, not deleted.")
        if not messagebox.askyesno("Delete", f"Delete {name}?  (This can't be undone.)"):
            return
        del self.sprites[self.cur]
        self.undo.clear()               # (they name sprites by number)
        self.redo.clear()
        self.dirty = True
        self.refresh_list()
        self.select(min(self.cur, len(self.sprites) - 1))

    # ---------------------------------------------------------------- files
    def cmd_check(self):
        errs = hs.problems(self.sprites)
        if errs:
            messagebox.showwarning("Check", "- " + "\n- ".join(errs))
        else:
            messagebox.showinfo("Check", "No problems: the game can use them.")

    def cmd_save(self):
        errs = hs.problems(self.sprites)
        try:
            hs.save(self.sprites, self.path)
        except OSError as e:
            return messagebox.showerror("Can't save", str(e))
        self.dirty = False
        self.set_title()
        self.say("saved; build.bat puts them in the game")
        if errs:
            messagebox.showwarning("Saved, with problems", "Saved, but build.bat will stop on these:\n\n- "
                                   + "\n- ".join(errs))

    def cmd_reload(self):
        if self.dirty and not messagebox.askyesno("Reload", "Throw away the changes?"):
            return
        try:
            self.sprites = hs.load(self.path)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't load", str(e))
        self.undo.clear()
        self.redo.clear()
        self.dirty = False
        self.refresh_list()
        self.select(min(self.cur, len(self.sprites) - 1))

    def cmd_quit(self):
        if self.dirty and not messagebox.askyesno("Unsaved changes", "Quit without saving the changes?"):
            return
        self.root.destroy()


def main():
    root = tk.Tk()
    Editor(root, sys.argv[1] if len(sys.argv) > 1 else None)
    root.mainloop()


if __name__ == "__main__":
    main()
