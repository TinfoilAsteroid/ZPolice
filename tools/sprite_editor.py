"""Z-Police figure editor: the humans' and monsters' graphics, sprites/*.json,
and their 32 colours, sprites/palette.json (tools/spritefile.py has the
format).

    python tools/sprite_editor.py [zombie|ghoul|ghost|banshee|human]

On the left: the figure, its purposes (what the game draws it doing: a
zombie walking towards the camera, side on or away; a human waving or
running to the VTOL; ...), the purpose's frames (played in turn) and the
frame's levels of detail (largest first, each drawn from its min_z, the
nearest distance in world units: the game picks the level for the figure's
distance and draws it at its own size).  In the middle the level's pixels,
enlarged; on the right the colours, the tools and a preview, at the game's
size and twice it, playing the frames.

    Left button     paint the left colour      Right button   the right one
    Ctrl+click      pick up the pixel's colour (as the left colour)
    Ctrl+Z          undo                       Ctrl+S         save

Tools: Pencil, Fill (the area of the clicked colour, joined side to side),
Line.  Colour 0 (top left) is transparent.  Edit colour... (or double-click
a swatch) sets a colour's r, g, b (0..7 each): the same colours are in every
city's palette (entries 192-223).

Frame menu: add, duplicate, delete, move.  Level menu: add a level (its
size, and its min_z: blank for automatic, from the figure's height), make
one from the larger level before it (scaled down), resize, set min_z,
delete.  Edit: mirror, flip, shift, clear, copy the previous frame's level,
onion skin (the previous frame faintly under this one).

Save (Ctrl+S) checks the figure (spritefile.problems) and writes its file
and the colours; build.bat (gengraphics.py) then makes ZPDATA/SPRITES.ZPG.
"""
import copy
import os
import sys
import tkinter as tk
from tkinter import messagebox, simpledialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spritefile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWATCH = 22
PREVIEW_MS = 200                        # a preview frame (4 game frames at 20 fps)


def hex_rgb(c):
    return "#%02x%02x%02x" % tuple(round(v * 255 / 7) for v in c)


def blend(c, bg=(4, 4, 4), k=0.35):
    """c faded towards bg (the onion skin)."""
    return tuple(round(bg[i] + (c[i] - bg[i]) * k) for i in range(3))


class Editor:
    def __init__(self, root, fig=None):
        self.root = root
        self.zoom = 14
        self.figs = {}                  # name -> data (as loaded / edited)
        self.dirty = set()              # names changed since saved
        self.pal_dirty = False
        self.undo = []
        self.fig = None
        self.anim = None
        self.frame = 0
        self.lod = 0
        self.left, self.right = 1, 0    # colours of the two buttons
        self.tool = tk.StringVar(value="pencil")
        self.onion = tk.BooleanVar(value=False)
        self.grid = tk.BooleanVar(value=True)
        self.playing = tk.BooleanVar(value=True)
        self.stroke = None
        self.line0 = None
        self.pframe = 0
        try:
            self.pal = sf.load_palette()
        except (OSError, ValueError) as e:
            messagebox.showerror("Colours", f"{e}\n\nRun gengraphics.py (build.bat) to make them.")
            self.pal = [(0, 0, 0)] * sf.COLOURS
        for f in sf.FIGURE_NAMES:
            p = sf.figure_path(f)
            try:
                self.figs[f] = sf.load(p)
            except (OSError, ValueError):
                self.figs[f] = {"name": f, "height": sf.figure_height(f), "anims": {}}
        self.build_ui()
        self.select_fig(fig if fig in self.figs else sf.FIGURE_NAMES[0])
        self.root.after(PREVIEW_MS, self.tick)

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        r = self.root
        mb = tk.Menu(r)
        fm = tk.Menu(mb, tearoff=0)
        fm.add_command(label="Save", command=self.cmd_save, accelerator="Ctrl+S")
        fm.add_command(label="Reload this figure", command=self.cmd_reload)
        fm.add_command(label="Check", command=self.cmd_check)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.cmd_quit)
        mb.add_cascade(label="File", menu=fm)
        em = tk.Menu(mb, tearoff=0)
        em.add_command(label="Undo", command=self.cmd_undo, accelerator="Ctrl+Z")
        em.add_separator()
        em.add_command(label="Mirror left-right", command=lambda: self.edit(sf.mirror))
        em.add_command(label="Flip top-bottom", command=lambda: self.edit(lambda p: p[::-1]))
        for name, dx, dy in (("left", -1, 0), ("right", 1, 0), ("up", 0, -1), ("down", 0, 1)):
            em.add_command(label=f"Shift {name}", command=lambda dx=dx, dy=dy: self.edit(
                lambda p, dx=dx, dy=dy: self.shift(p, dx, dy)))
        em.add_command(label="Clear", command=lambda: self.edit(lambda p: [[0] * len(p[0]) for _ in p]))
        em.add_command(label="Copy the previous frame's level", command=self.cmd_copy_prev)
        em.add_separator()
        em.add_command(label="Edit colour...", command=lambda: self.edit_colour(self.left))
        mb.add_cascade(label="Edit", menu=em)
        frm = tk.Menu(mb, tearoff=0)
        frm.add_command(label="Add a blank frame", command=self.cmd_frame_add)
        frm.add_command(label="Duplicate this frame", command=self.cmd_frame_dup)
        frm.add_command(label="Delete this frame", command=self.cmd_frame_del)
        frm.add_command(label="Move earlier", command=lambda: self.cmd_frame_move(-1))
        frm.add_command(label="Move later", command=lambda: self.cmd_frame_move(1))
        mb.add_cascade(label="Frame", menu=frm)
        lm = tk.Menu(mb, tearoff=0)
        lm.add_command(label="Add a level...", command=self.cmd_lod_add)
        lm.add_command(label="Make the next level from this one (scaled)...", command=self.cmd_lod_make)
        lm.add_command(label="Resize this level...", command=self.cmd_lod_resize)
        lm.add_command(label="Set min_z...", command=self.cmd_lod_minz)
        lm.add_command(label="Delete this level", command=self.cmd_lod_del)
        lm.add_separator()
        lm.add_command(label="Remake every frame's smaller levels from the largest",
                       command=self.cmd_lod_remake_all)
        mb.add_cascade(label="Level", menu=lm)
        vm = tk.Menu(mb, tearoff=0)
        for z in (8, 14, 20):
            vm.add_command(label=f"{z} pixels a pixel", command=lambda z=z: self.set_zoom(z))
        vm.add_checkbutton(label="Grid", variable=self.grid, command=self.redraw)
        vm.add_checkbutton(label="Onion skin (previous frame)", variable=self.onion, command=self.redraw)
        vm.add_checkbutton(label="Play the preview", variable=self.playing)
        mb.add_cascade(label="View", menu=vm)
        r.config(menu=mb)
        r.bind("<Control-s>", lambda e: self.cmd_save())
        r.bind("<Control-z>", lambda e: self.cmd_undo())
        r.protocol("WM_DELETE_WINDOW", self.cmd_quit)

        left = tk.Frame(r, padx=6, pady=6)
        left.pack(side=tk.LEFT, fill=tk.Y)
        tk.Label(left, text="Figure").pack(anchor=tk.W)
        self.figlist = tk.Listbox(left, height=len(sf.FIGURE_NAMES), exportselection=False, width=24)
        for f in sf.FIGURE_NAMES:
            self.figlist.insert(tk.END, f"{f} ({sf.figure_height(f)} units high)")
        self.figlist.pack(anchor=tk.W)
        self.figlist.bind("<<ListboxSelect>>", lambda e: self.on_list(self.figlist, self.select_fig_i))
        tk.Label(left, text="Purpose").pack(anchor=tk.W, pady=(8, 0))
        self.animlist = tk.Listbox(left, height=5, exportselection=False, width=24)
        self.animlist.pack(anchor=tk.W)
        self.animlist.bind("<<ListboxSelect>>", lambda e: self.on_list(self.animlist, self.select_anim_i))
        self.animdesc = tk.Label(left, text="", wraplength=180, justify=tk.LEFT, fg="#404040")
        self.animdesc.pack(anchor=tk.W)
        tk.Label(left, text="Frame").pack(anchor=tk.W, pady=(8, 0))
        self.framelist = tk.Listbox(left, height=6, exportselection=False, width=24)
        self.framelist.pack(anchor=tk.W)
        self.framelist.bind("<<ListboxSelect>>", lambda e: self.on_list(self.framelist, self.select_frame))
        tk.Label(left, text="Level of detail (size, drawn from Z)").pack(anchor=tk.W, pady=(8, 0))
        self.lodlist = tk.Listbox(left, height=6, exportselection=False, width=24)
        self.lodlist.pack(anchor=tk.W)
        self.lodlist.bind("<<ListboxSelect>>", lambda e: self.on_list(self.lodlist, self.select_lod))

        mid = tk.Frame(r, padx=6, pady=6)
        mid.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.canvas = tk.Canvas(mid, bg="#202020", highlightthickness=0, width=600, height=600)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        for b in ("<Button-1>", "<B1-Motion>", "<ButtonRelease-1>",
                  "<Button-3>", "<B3-Motion>", "<ButtonRelease-3>"):
            self.canvas.bind(b, self.on_mouse)
        self.status = tk.Label(mid, text="", anchor=tk.W)
        self.status.pack(fill=tk.X)

        right = tk.Frame(r, padx=6, pady=6)
        right.pack(side=tk.LEFT, fill=tk.Y)
        tk.Label(right, text="Colours (0: transparent)").pack(anchor=tk.W)
        self.pcanvas = tk.Canvas(right, width=8 * (SWATCH + 4), height=4 * (SWATCH + 4),
                                 highlightthickness=0)
        self.pcanvas.pack(anchor=tk.W)
        self.pcanvas.bind("<Button-1>", lambda e: self.on_swatch(e, "left"))
        self.pcanvas.bind("<Button-3>", lambda e: self.on_swatch(e, "right"))
        self.pcanvas.bind("<Double-Button-1>", self.on_swatch_edit)
        self.pick_label = tk.Label(right, text="", justify=tk.LEFT)
        self.pick_label.pack(anchor=tk.W)
        tk.Button(right, text="Edit colour...", command=lambda: self.edit_colour(self.left)).pack(anchor=tk.W)
        tk.Label(right, text="Tool").pack(anchor=tk.W, pady=(8, 0))
        for name, val in (("Pencil", "pencil"), ("Fill", "fill"), ("Line", "line")):
            tk.Radiobutton(right, text=name, variable=self.tool, value=val).pack(anchor=tk.W)
        tk.Label(right, text="Preview (game size, x2)").pack(anchor=tk.W, pady=(8, 0))
        self.preview = tk.Canvas(right, width=200, height=170, bg="#606060", highlightthickness=0)
        self.preview.pack(anchor=tk.W)

    def on_list(self, lb, fn):
        sel = lb.curselection()
        if sel:
            fn(sel[0])

    def say(self, text):
        self.status.config(text=text)

    def set_title(self):
        star = "*" if (self.fig in self.dirty or self.pal_dirty) else ""
        self.root.title(f"Z-Police figures - {self.fig}{star}")

    def set_zoom(self, z):
        self.zoom = z
        self.redraw()

    # ------------------------------------------------------------ selection
    def data(self):
        return self.figs[self.fig]

    def frames(self):
        an = self.data()["anims"].setdefault(self.anim, {"frames": []})
        return an["frames"]

    def cur_lod(self):
        fr = self.frames()
        if not fr or not fr[self.frame]["lods"]:
            return None
        return fr[self.frame]["lods"][self.lod]

    def select_fig_i(self, i):
        self.select_fig(sf.FIGURE_NAMES[i])

    def select_fig(self, f):
        self.fig = f
        self.figlist.selection_clear(0, tk.END)
        self.figlist.selection_set(sf.FIGURE_NAMES.index(f))
        self.animlist.delete(0, tk.END)
        for a, _ in sf.figure_anims(f):
            n = len(self.data()["anims"].get(a, {}).get("frames", []))
            self.animlist.insert(tk.END, f"{a} ({n} frames)")
        self.select_anim_i(0)
        self.set_title()

    def select_anim_i(self, i):
        a, desc = sf.figure_anims(self.fig)[i]
        self.anim = a
        self.animlist.selection_clear(0, tk.END)
        self.animlist.selection_set(i)
        self.animdesc.config(text=desc)
        if not self.frames():
            self.frames().append({"lods": [sf.new_lod(8, 16, 0)]})
        self.frame = min(self.frame, len(self.frames()) - 1)
        self.refresh_frames()
        self.select_frame(self.frame)

    def refresh_frames(self):
        self.framelist.delete(0, tk.END)
        for k, fr in enumerate(self.frames()):
            w, h = sf.lod_size(fr["lods"][0]) if fr["lods"] else (0, 0)
            self.framelist.insert(tk.END, f"frame {k + 1}: {len(fr['lods'])} levels, {w}x{h}")

    def select_frame(self, k):
        self.frame = k
        self.framelist.selection_clear(0, tk.END)
        self.framelist.selection_set(k)
        self.lod = min(self.lod, len(self.frames()[k]["lods"]) - 1)
        self.refresh_lods()
        self.select_lod(max(0, self.lod))

    def refresh_lods(self):
        self.lodlist.delete(0, tk.END)
        zs = sf.min_zs({"height": self.data()["height"],
                        "anims": {self.anim: {"frames": self.frames()}}})[self.anim][self.frame]
        lods = self.frames()[self.frame]["lods"]
        for k, lod in enumerate(lods):
            w, h = sf.lod_size(lod)
            far = f"-{zs[k + 1] - 1}" if k + 1 < len(lods) else " on"
            auto = " (auto)" if k and lod.get("min_z") is None else ""
            self.lodlist.insert(tk.END, f"{w}x{h}: Z {zs[k]}{far}{auto}")

    def select_lod(self, k):
        self.lod = k
        self.lodlist.selection_clear(0, tk.END)
        self.lodlist.selection_set(k)
        self.undo_mark = None
        self.redraw()

    # -------------------------------------------------------------- drawing
    def redraw(self):
        c = self.canvas
        c.delete("all")
        lod = self.cur_lod()
        if lod is None:
            return
        px = sf.pixels(lod)
        w, h = sf.lod_size(lod)
        z = self.zoom
        onion = None
        if self.onion.get() and self.frame > 0:
            prev = self.frames()[self.frame - 1]["lods"]
            if self.lod < len(prev) and sf.lod_size(prev[self.lod]) == (w, h):
                onion = sf.pixels(prev[self.lod])
        for y in range(h):
            for x in range(w):
                v = px[y][x]
                if v:
                    fill = hex_rgb(self.pal[v])
                elif onion and onion[y][x]:
                    fill = hex_rgb(blend(self.pal[onion[y][x]]))
                else:
                    fill = "#505050" if (x + y) % 2 else "#585858"
                c.create_rectangle(x * z, y * z, (x + 1) * z, (y + 1) * z, fill=fill,
                                   outline="#303030" if self.grid.get() and z >= 8 else "")
        c.create_line(w * z / 2, h * z, w * z / 2, h * z + 8, fill="yellow")   # the feet
        c.create_text(4, h * z + 10, anchor=tk.NW, fill="#c0c0c0",
                      text=f"{w}x{h}: the bottom centre (yellow) stands on the figure's feet")
        self.draw_palette()
        self.draw_preview()

    def draw_palette(self):
        pc = self.pcanvas
        pc.delete("all")
        for i, col in enumerate(self.pal):
            x, y = (i % 8) * (SWATCH + 4) + 2, (i // 8) * (SWATCH + 4) + 2
            if i == 0:
                pc.create_rectangle(x, y, x + SWATCH, y + SWATCH, fill="#808080")
                pc.create_line(x, y, x + SWATCH, y + SWATCH, fill="red", width=2)
            else:
                pc.create_rectangle(x, y, x + SWATCH, y + SWATCH, fill=hex_rgb(col))
            if i == self.left:
                pc.create_rectangle(x - 2, y - 2, x + SWATCH + 2, y + SWATCH + 2, outline="yellow", width=2)
            if i == self.right:
                pc.create_rectangle(x - 1, y - 1, x + SWATCH + 1, y + SWATCH + 1, outline="cyan", width=1)
        self.pick_label.config(text=f"left: colour {self.left} (yellow)\nright: colour {self.right} (cyan)")

    def draw_preview(self):
        pv = self.preview
        pv.delete("all")
        frames = self.frames()
        if not frames:
            return
        fr = frames[self.pframe % len(frames)]["lods"]
        lod = fr[min(self.lod, len(fr) - 1)]
        px = sf.pixels(lod)
        w, h = sf.lod_size(lod)
        for scale, ox in ((1, 30), (2, 100)):
            base = 160
            for y in range(h):
                for x in range(w):
                    v = px[y][x]
                    if v:
                        X, Y = ox - (w * scale) // 2 + x * scale, base - (h - y) * scale
                        pv.create_rectangle(X, Y, X + scale, Y + scale, fill=hex_rgb(self.pal[v]), width=0)

    def tick(self):
        if self.playing.get():
            self.pframe += 1
            self.draw_preview()
        self.root.after(PREVIEW_MS, self.tick)

    # -------------------------------------------------------------- editing
    def push_undo(self):
        self.undo.append((self.fig, self.anim, copy.deepcopy(self.frames()), self.frame, self.lod))
        del self.undo[:-100]

    def changed(self):
        self.dirty.add(self.fig)
        self.set_title()

    def set_px(self, px):
        lod = self.cur_lod()
        lod["rows"] = sf.from_pixels(px)["rows"]
        self.changed()
        self.redraw()

    def cell(self, ev):
        lod = self.cur_lod()
        w, h = sf.lod_size(lod)
        x, y = int(self.canvas.canvasx(ev.x) // self.zoom), int(self.canvas.canvasy(ev.y) // self.zoom)
        return (x, y) if 0 <= x < w and 0 <= y < h else None

    def on_mouse(self, ev):
        if self.cur_lod() is None:
            return
        t = str(ev.type)
        btn_right = ev.num == 3 or (ev.state & 0x400)
        colour = self.right if btn_right else self.left
        at = self.cell(ev)
        if t == "ButtonPress" and (ev.state & 0x4):     # Ctrl: pick up
            if at:
                v = sf.pixels(self.cur_lod())[at[1]][at[0]]
                if btn_right:
                    self.right = v
                else:
                    self.left = v
                self.draw_palette()
            return
        tool = self.tool.get()
        if t == "ButtonPress":
            self.push_undo()
            if tool == "fill" and at:
                px = sf.pixels(self.cur_lod())
                self.fill(px, at, colour)
                self.set_px(px)
            elif tool == "line":
                self.line0 = at
            elif at:
                self.paint(at, colour)
        elif t == "Motion" and tool == "pencil" and at:
            self.paint(at, colour)
        elif t == "ButtonRelease" and tool == "line" and self.line0 and at:
            px = sf.pixels(self.cur_lod())
            for x, y in self.line_cells(self.line0, at):
                px[y][x] = colour
            self.line0 = None
            self.set_px(px)

    def paint(self, at, colour):
        px = sf.pixels(self.cur_lod())
        if px[at[1]][at[0]] != colour:
            px[at[1]][at[0]] = colour
            self.set_px(px)

    @staticmethod
    def fill(px, at, colour):
        h, w = len(px), len(px[0])
        old = px[at[1]][at[0]]
        if old == colour:
            return
        todo = [at]
        while todo:
            x, y = todo.pop()
            if 0 <= x < w and 0 <= y < h and px[y][x] == old:
                px[y][x] = colour
                todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]

    @staticmethod
    def line_cells(a, b):
        (x0, y0), (x1, y1) = a, b
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        return {(round(x0 + (x1 - x0) * k / n), round(y0 + (y1 - y0) * k / n)) for k in range(n + 1)}

    @staticmethod
    def shift(px, dx, dy):
        h, w = len(px), len(px[0])
        return [[px[y - dy][x - dx] if 0 <= x - dx < w and 0 <= y - dy < h else 0
                 for x in range(w)] for y in range(h)]

    def edit(self, fn):
        if self.cur_lod() is None:
            return
        self.push_undo()
        self.set_px(fn(sf.pixels(self.cur_lod())))

    def cmd_undo(self):
        if not self.undo:
            return self.say("nothing to undo")
        fig, anim, frames, fr, lod = self.undo.pop()
        self.figs[fig]["anims"][anim]["frames"] = frames
        if fig != self.fig:
            self.select_fig(fig)
        self.anim = anim
        self.frame, self.lod = min(fr, len(frames) - 1), lod
        self.dirty.add(fig)
        self.select_anim_i([a for a, _ in sf.figure_anims(self.fig)].index(anim))
        self.say("undone")

    def cmd_copy_prev(self):
        if self.frame == 0:
            return self.say("this is the first frame")
        prev = self.frames()[self.frame - 1]["lods"]
        if self.lod >= len(prev):
            return self.say("the previous frame has no such level")
        self.push_undo()
        self.frames()[self.frame]["lods"][self.lod] = copy.deepcopy(prev[self.lod])
        self.changed()
        self.select_frame(self.frame)

    # ------------------------------------------------------------- colours
    def swatch_at(self, ev):
        i = (ev.y // (SWATCH + 4)) * 8 + ev.x // (SWATCH + 4)
        return i if 0 <= i < sf.COLOURS else None

    def on_swatch(self, ev, which):
        i = self.swatch_at(ev)
        if i is None:
            return
        setattr(self, which, i)
        self.draw_palette()

    def on_swatch_edit(self, ev):
        i = self.swatch_at(ev)
        if i is not None:
            self.edit_colour(i)

    def edit_colour(self, i):
        if i == 0:
            return messagebox.showinfo("Colour 0", "Colour 0 is transparent: it is never drawn.")
        w = tk.Toplevel(self.root)
        w.title(f"Colour {i}")
        w.transient(self.root)
        vs = []
        for j, name in enumerate("rgb"):
            tk.Label(w, text=name).grid(row=0, column=j)
            v = tk.IntVar(value=self.pal[i][j])
            tk.Spinbox(w, from_=0, to=7, width=3, textvariable=v).grid(row=1, column=j, padx=4)
            vs.append(v)
        sw = tk.Canvas(w, width=40, height=24, bg=hex_rgb(self.pal[i]))
        sw.grid(row=1, column=3, padx=6)

        def ok():
            try:
                c = tuple(max(0, min(7, int(v.get()))) for v in vs)
            except (tk.TclError, ValueError):
                return
            if sf.is_transparent(c):
                return messagebox.showerror("Transparent", f"{c} is Layer 2's transparent colour: "
                                            "it would never show.", parent=w)
            self.pal[i] = c
            self.pal_dirty = True
            self.set_title()
            self.redraw()
            w.destroy()
        tk.Button(w, text="OK", command=ok).grid(row=2, column=0, columnspan=2, pady=6)
        tk.Button(w, text="Cancel", command=w.destroy).grid(row=2, column=2, columnspan=2)

    # -------------------------------------------------------- frames, levels
    def cmd_frame_add(self):
        self.push_undo()
        lods = self.frames()[self.frame]["lods"]
        self.frames().insert(self.frame + 1, {"lods": [
            {"min_z": l.get("min_z"), "rows": ["." * sf.lod_size(l)[0]] * sf.lod_size(l)[1]} for l in lods]})
        self.after_frames(self.frame + 1)

    def cmd_frame_dup(self):
        self.push_undo()
        self.frames().insert(self.frame + 1, copy.deepcopy(self.frames()[self.frame]))
        self.after_frames(self.frame + 1)

    def cmd_frame_del(self):
        if len(self.frames()) == 1:
            return self.say("a purpose needs a frame")
        self.push_undo()
        del self.frames()[self.frame]
        self.after_frames(min(self.frame, len(self.frames()) - 1))

    def cmd_frame_move(self, d):
        k = self.frame + d
        if not 0 <= k < len(self.frames()):
            return
        self.push_undo()
        f = self.frames()
        f[self.frame], f[k] = f[k], f[self.frame]
        self.after_frames(k)

    def after_frames(self, k):
        self.changed()
        self.refresh_frames()
        self.select_frame(k)
        self.select_fig_anim_counts()

    def select_fig_anim_counts(self):
        sel = self.animlist.curselection()
        for i, (a, _) in enumerate(sf.figure_anims(self.fig)):
            n = len(self.data()["anims"].get(a, {}).get("frames", []))
            self.animlist.delete(i)
            self.animlist.insert(i, f"{a} ({n} frames)")
        if sel:
            self.animlist.selection_set(sel[0])

    def ask_size(self, title, w0, h0):
        s = simpledialog.askstring(title, "Width x height, pixels (e.g. 8x16):",
                                   initialvalue=f"{w0}x{h0}", parent=self.root)
        if not s:
            return None
        try:
            w, h = (int(v) for v in s.lower().replace(" ", "").split("x"))
        except ValueError:
            messagebox.showerror(title, "As width x height, e.g. 8x16")
            return None
        if not (1 <= w <= sf.MAX_W and 1 <= h <= sf.MAX_H):
            messagebox.showerror(title, f"1x1 to {sf.MAX_W}x{sf.MAX_H}")
            return None
        return w, h

    def ask_minz(self, initial):
        s = simpledialog.askstring("min_z", "The nearest distance (world units) to draw it from;\n"
                                   "blank: automatic (from the figure's height and this level's)",
                                   initialvalue="" if initial is None else str(initial), parent=self.root)
        if s is None:
            return False, None
        s = s.strip()
        if not s:
            return True, None
        try:
            return True, max(0, int(s))
        except ValueError:
            return False, None

    def sort_lods(self, new):
        """The levels after the largest in size order, tallest first (their
        automatic min_z then rising): the level `new` selected."""
        lods = self.frames()[self.frame]["lods"]
        rest = sorted(lods[1:], key=lambda l: -sf.lod_size(l)[1])
        lods[1:] = rest
        self.changed()
        self.select_frame(self.frame)
        self.select_lod(next(k for k, l in enumerate(lods) if l is new))

    def cmd_lod_add(self):
        lods = self.frames()[self.frame]["lods"]
        w0, h0 = sf.lod_size(lods[-1])
        size = self.ask_size("Add a level", max(1, w0 // 2), max(1, h0 // 2))
        if not size:
            return
        self.push_undo()
        new = sf.new_lod(*size)
        lods.append(new)
        self.sort_lods(new)

    def cmd_lod_make(self):
        lods = self.frames()[self.frame]["lods"]
        src = lods[self.lod]
        w0, h0 = sf.lod_size(src)
        size = self.ask_size("Make the next level", max(1, w0 * 3 // 4), max(1, h0 * 3 // 4))
        if not size:
            return
        self.push_undo()
        new = {"min_z": None, **sf.from_pixels(sf.shrink(sf.pixels(src), *size))}
        same = [k for k, l in enumerate(lods) if k and sf.lod_size(l) == size]
        if same:
            lods[same[0]] = new                     # (that size already: replaced)
        else:
            lods.append(new)
        self.sort_lods(new)

    def cmd_lod_remake_all(self):
        if not messagebox.askyesno("Remake the levels", "Every frame of this purpose: its smaller "
                                   "levels made again from its largest (scaled down, the sizes "
                                   "kept)?  Hand edits to them are lost."):
            return
        self.push_undo()
        for fr in self.frames():
            big = sf.pixels(fr["lods"][0])
            for k in range(1, len(fr["lods"])):
                w, h = sf.lod_size(fr["lods"][k])
                fr["lods"][k]["rows"] = sf.from_pixels(sf.shrink(big, w, h))["rows"]
        self.changed()
        self.select_frame(self.frame)

    def cmd_lod_resize(self):
        lod = self.cur_lod()
        w0, h0 = sf.lod_size(lod)
        size = self.ask_size("Resize this level (the pixels kept, bottom centre)", w0, h0)
        if not size:
            return
        w, h = size
        px = sf.pixels(lod)
        ox, oy = (w - w0) // 2, h - h0           # keep the feet where they are
        out = [[0] * w for _ in range(h)]
        for y in range(h0):
            for x in range(w0):
                if 0 <= x + ox < w and 0 <= y + oy < h:
                    out[y + oy][x + ox] = px[y][x]
        self.push_undo()
        self.set_px(out)
        self.select_frame(self.frame)

    def cmd_lod_minz(self):
        if self.lod == 0:
            return messagebox.showinfo("min_z", "The largest level is drawn from 0 (nearer than "
                                       "the next level's min_z).")
        ok, z = self.ask_minz(self.cur_lod().get("min_z"))
        if not ok:
            return
        self.push_undo()
        self.cur_lod()["min_z"] = z
        self.changed()
        self.select_frame(self.frame)

    def cmd_lod_del(self):
        lods = self.frames()[self.frame]["lods"]
        if len(lods) == 1:
            return self.say("a frame needs a level")
        self.push_undo()
        del lods[self.lod]
        lods[0]["min_z"] = 0
        self.lod = min(self.lod, len(lods) - 1)
        self.changed()
        self.select_frame(self.frame)

    # ---------------------------------------------------------------- files
    def cmd_check(self):
        errs = sf.problems(self.fig, self.data()) + sf.palette_problems(self.pal)
        if errs:
            messagebox.showwarning("Check", "- " + "\n- ".join(errs))
        else:
            messagebox.showinfo("Check", f"No problems: the game can use {self.fig}.")

    def cmd_save(self):
        errs = []
        for f in sorted(self.dirty):
            d = self.figs[f]
            for k, fr in enumerate(d["anims"].values()):
                for f2 in fr["frames"]:
                    if f2["lods"]:
                        f2["lods"][0]["min_z"] = 0
            errs += [f"{f}: {e}" for e in sf.problems(f, d)]
            try:
                sf.save(sf.figure_path(f), d)
            except OSError as e:
                return messagebox.showerror("Can't save", str(e))
        if self.pal_dirty:
            errs += sf.palette_problems(self.pal)
            try:
                sf.save_palette(self.pal)
            except OSError as e:
                return messagebox.showerror("Can't save", str(e))
        saved = sorted(self.dirty) + (["the colours"] if self.pal_dirty else [])
        self.dirty, self.pal_dirty = set(), False
        self.set_title()
        self.say("saved " + (", ".join(saved) if saved else "(nothing changed)")
                 + "; build.bat puts them in the game")
        if errs:
            messagebox.showwarning("Saved, with problems",
                                   "Saved, but the game can't use them until these are fixed "
                                   "(build.bat will stop on them):\n\n- " + "\n- ".join(errs))

    def cmd_reload(self):
        if self.fig in self.dirty and not messagebox.askyesno(
                "Reload", f"Throw away the changes to {self.fig}?"):
            return
        try:
            self.figs[self.fig] = sf.load(sf.figure_path(self.fig))
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't load", str(e))
        self.dirty.discard(self.fig)
        self.select_fig(self.fig)

    def cmd_quit(self):
        if (self.dirty or self.pal_dirty) and not messagebox.askyesno(
                "Unsaved changes", "Quit without saving the changes?"):
            return
        self.root.destroy()


def main():
    root = tk.Tk()
    Editor(root, sys.argv[1] if len(sys.argv) > 1 else None)
    root.mainloop()


if __name__ == "__main__":
    main()
