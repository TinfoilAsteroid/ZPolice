"""Z-Police city map editor: paint a city's 64 x 64 map (maps/CITYnn.json).

    python tools/map_editor.py [maps/CITYnn.json]

The map is drawn flat, 8 pixels a cell (View menu: 4, 8 or 12) inside an
8-pixel white border; on the right, the tools, the building height and the
city's colour families (its palette, read from ZPDATA/CITYnn.ZPC, as built
by gentables.py).

    Left button (click or drag)  paint with the selected tool
    Right button                 pick up the cell's height and colour
    Ctrl+Z                       undo the last stroke
    File menu                    load / save a map (JSON)

Tools: Building (the selected height and colour), Road, Outer wall (height
15, the wall's colour family), Landing pad (only 1), Terrace (the pad's green
defences; away from the base, barricades: at most 30, counted below the
map), Out of bounds.  View > Invert roads shows roads white (the view only:
not the palette or the saved map).

Colour families: each is shown as its 3 shades, the base colour (the facing
side), the shaded side, the roof.  Only the buildings' families (00-61, each
with a white border) can be picked; 62 and 63 are the terrace's and the pad's.
A building on any other colour (or none) is invalid: "Show bad colours"
flashes them red for 3 seconds.  Saving checks the map (tools/citymap.py validate):
the problems are shown, and gentables.py won't build a map that has any.
After saving, build.bat (gentables.py) makes the city's ZPDATA files from it.
"""
import os
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citymap as cm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "maps")
DATA_DIR = os.path.join(ROOT, "ZPDATA")
BORDER = 8
# The palette: each colour family as a group of its 3 shades, PAL_ORDER
# (the base colour: the facing side, then the shaded side, then the roof;
# entries +1, +0, +2 of the family's 4), PAL_COLS families a row
SWATCH = 12                             # a shade's swatch, pixels
PAL_ORDER = (1, 0, 2)
PAL_COLS = 4
PAL_GX = 3 * SWATCH + 6                 # a family group's pitch: across,
PAL_GY = SWATCH + 6                     #   and down
PAL_W = PAL_COLS * PAL_GX
PAL_H = (cm.FAMILIES // PAL_COLS) * PAL_GY
FLASH_MS = 3000                         # Show bad colours: flash this long,
FLASH_STEP = 250                        # on / off every this many ms
TOOLS = [("Building", "bld"), ("Road", "road"), ("Outer wall", "wall"),
         ("Landing pad", "pad"), ("Terrace", "terrace"), ("Out of bounds", "void")]


def rel(path):
    """A path for messages: relative to the project when it can be."""
    try:
        return os.path.relpath(path, ROOT)
    except ValueError:                  # (another drive)
        return path


def hex_rgb(c):
    """(r, g, b) 0..7 -> '#rrggbb'."""
    return "#%02x%02x%02x" % tuple(round(v * 255 / 7) for v in c)


def grey_palette():
    """A stand-in palette when the city's ZPC isn't built yet."""
    pal = [(2, 2, 2)] * 256
    for f in range(cm.FAMILIES):
        v = 2 + f % 5
        pal[f * 4:f * 4 + 4] = [(v - 1, v - 1, v - 1), (v, v, v), (v + 1, v + 1, v + 1), (v, v, v)]
    return pal


class Editor:
    def __init__(self, root, path=None):
        self.root = root
        self.cell = 8                   # pixels a map cell (View menu: 4, 8, 12)
        self.path = None
        self.city, self.name = 0, ""
        self.cells = [cm.ROAD] * (cm.GRID * cm.GRID)
        self.fams = [None] * (cm.GRID * cm.GRID)
        self.pal = grey_palette()
        self.dirty = False
        self.undo = []                  # strokes: lists of (index, code, family)
        self.stroke = None
        self.tool = tk.StringVar(value="bld")
        self.height = tk.IntVar(value=4)
        self.family = 1
        self.show_heights = tk.BooleanVar(value=False)
        self.invert_roads = tk.BooleanVar(value=False)   # (the view only)
        self.flash = None               # Show bad colours: [steps left, on, red cells, after job]
        self.build_ui()
        if path:
            self.load(path)
        else:
            self.redraw()
            self.set_title()

    # ---------------------------------------------------------------- UI
    def build_ui(self):
        r = self.root
        mb = tk.Menu(r)
        fm = tk.Menu(mb, tearoff=0)
        fm.add_command(label="Load map...", command=self.cmd_open, accelerator="Ctrl+O")
        fm.add_command(label="Save map", command=self.cmd_save, accelerator="Ctrl+S")
        fm.add_command(label="Save map as...", command=self.cmd_save_as)
        fm.add_separator()
        fm.add_command(label="Check map", command=self.cmd_check)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.cmd_quit)
        mb.add_cascade(label="File", menu=fm)
        em = tk.Menu(mb, tearoff=0)
        em.add_command(label="Undo", command=self.cmd_undo, accelerator="Ctrl+Z")
        mb.add_cascade(label="Edit", menu=em)
        vm = tk.Menu(mb, tearoff=0)
        for n in (4, 8, 12):
            vm.add_command(label=f"{n} pixels a cell", command=lambda n=n: self.set_cell(n))
        vm.add_separator()
        vm.add_checkbutton(label="Show heights (grey)", variable=self.show_heights,
                           command=self.redraw)
        vm.add_checkbutton(label="Invert roads (white)", variable=self.invert_roads,
                           command=self.redraw)
        mb.add_cascade(label="View", menu=vm)
        r.config(menu=mb)
        r.bind("<Control-o>", lambda e: self.cmd_open())
        r.bind("<Control-s>", lambda e: self.cmd_save())
        r.bind("<Control-z>", lambda e: self.cmd_undo())
        r.protocol("WM_DELETE_WINDOW", self.cmd_quit)

        main = tk.Frame(r)
        main.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        left = tk.Frame(main)
        left.pack(side=tk.LEFT, anchor=tk.N)
        self.canvas = tk.Canvas(left, bg="white", highlightthickness=0)
        self.canvas.pack(side=tk.TOP, anchor=tk.W)
        self.stats = tk.Label(left, text="", anchor=tk.W, font=("TkDefaultFont", 10))
        self.stats.pack(side=tk.TOP, anchor=tk.W, padx=BORDER)
        self.canvas.bind("<Button-1>", self.on_paint)
        self.canvas.bind("<B1-Motion>", self.on_paint)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.canvas.bind("<Button-3>", self.on_pick)
        self.canvas.bind("<Motion>", self.on_move)

        side = tk.Frame(main, padx=8, pady=4)
        side.pack(side=tk.LEFT, anchor=tk.N, fill=tk.Y)
        tk.Label(side, text="Tool", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W)
        for label, key in TOOLS:
            tk.Radiobutton(side, text=label, variable=self.tool, value=key).pack(anchor=tk.W)
        tk.Label(side, text="Height (building)", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W, pady=(8, 0))
        tk.Scale(side, from_=1, to=15, orient=tk.HORIZONTAL, variable=self.height,
                 length=PAL_W, command=lambda v: self.tool.set("bld")).pack(anchor=tk.W)
        tk.Label(side, text="Colour family", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W, pady=(8, 0))
        self.pcanvas = tk.Canvas(side, width=PAL_W, height=PAL_H,
                                 bg="#303030", highlightthickness=0)
        self.pcanvas.pack(anchor=tk.W)
        self.pcanvas.bind("<Button-1>", self.on_palette)
        self.fam_label = tk.Label(side, text="")
        self.fam_label.pack(anchor=tk.W)
        tk.Button(side, text="Show bad colours", command=self.cmd_bad_colours).pack(
            anchor=tk.W, pady=(8, 0))
        self.status = tk.Label(r, text="", anchor=tk.W, relief=tk.SUNKEN)
        self.status.pack(side=tk.BOTTOM, fill=tk.X)
        self.rects = []
        self.make_grid()

    def make_grid(self):
        c, n = self.cell, cm.GRID
        self.canvas.delete("all")
        self.canvas.config(width=n * c + 2 * BORDER, height=n * c + 2 * BORDER)
        self.rects = [self.canvas.create_rectangle(BORDER + x * c, BORDER + z * c,
                                                   BORDER + (x + 1) * c, BORDER + (z + 1) * c,
                                                   width=0)
                      for z in range(n) for x in range(n)]

    def set_cell(self, n):
        self.cell = n
        self.make_grid()
        self.redraw()

    def set_title(self):
        what = os.path.basename(self.path) if self.path else "(new)"
        self.root.title(f"Z-Police map editor - {what} {self.name}{' *' if self.dirty else ''}")

    # ------------------------------------------------------------ drawing
    def cell_colour(self, i):
        code, fam = self.cells[i], self.fams[i]
        if code == cm.VOID:
            return "#000000"
        if code == cm.ROAD:
            if self.invert_roads.get():
                return "#ffffff"        # (just the view: roads stand out)
            return hex_rgb(self.pal[cm.GROUND_IDX])
        if self.show_heights.get():
            if code == cm.PAD:
                return "#ffffff"
            if code == cm.TERRACE:
                return "#40a040"
            v = 60 + code * 13
            return "#%02x%02x%02x" % (v, v, v)
        fam = cm.family_for(code, fam)
        if not isinstance(fam, int):    # none, or an unreadable field
            return "#ff00ff"
        return hex_rgb(self.pal[fam * 4 + 1])

    def redraw(self):
        self.stop_flash()               # (its cells are redrawn anyway)
        for i, rid in enumerate(self.rects):
            self.canvas.itemconfig(rid, fill=self.cell_colour(i))
        self.draw_palette()
        self.show_stats()

    def show_stats(self):
        """Below the map: barricades placed out of the most, landing pads."""
        nb, npad = len(cm.barricades(self.cells)), len(cm.pads(self.cells))
        self.stats.config(
            text=f"Barricades: {nb} / {cm.MAX_BARRICADES} placed      Landing pad: {npad} / 1",
            fg="red" if nb > cm.MAX_BARRICADES or npad != 1 else "black")

    def draw_palette(self):
        pc = self.pcanvas
        pc.delete("all")
        for f in range(cm.FAMILIES):
            x, y = self.pal_xy(f)
            for k, e in enumerate(PAL_ORDER):   # base, shaded side, roof
                pc.create_rectangle(x + k * SWATCH, y, x + (k + 1) * SWATCH, y + SWATCH,
                                    fill=hex_rgb(self.pal[f * 4 + e]), width=0)
            if f < cm.BLD_FAMILIES:     # a building colour: a white border
                pc.create_rectangle(x - 1, y - 1, x + 3 * SWATCH + 1, y + SWATCH + 1,
                                    outline="white", width=1)
            else:                       # the terrace's, the pad's: not for picking
                pc.create_line(x, y + SWATCH, x + 3 * SWATCH, y, fill="#303030", width=2)
        x, y = self.pal_xy(self.family)
        pc.create_rectangle(x - 3, y - 3, x + 3 * SWATCH + 3, y + SWATCH + 3, outline="yellow", width=2)
        notes = {cm.WALL_FAMILY: " (the wall's)"}
        self.fam_label.config(text=f"family {self.family:02d}{notes.get(self.family, '')}: "
                                   "base, side, roof")

    @staticmethod
    def pal_xy(f):
        """Family f's group in the palette: its top left."""
        return (f % PAL_COLS) * PAL_GX + 3, (f // PAL_COLS) * PAL_GY + 3

    @staticmethod
    def pal_family(x, y):
        """The family whose group (or the gap round it) is at (x, y); None."""
        c, r = x // PAL_GX, y // PAL_GY
        if 0 <= c < PAL_COLS and 0 <= r < cm.FAMILIES // PAL_COLS:
            return r * PAL_COLS + c
        return None

    # ------------------------------------------------------------- input
    def cell_at(self, ev):
        x, z = (ev.x - BORDER) // self.cell, (ev.y - BORDER) // self.cell
        if 0 <= x < cm.GRID and 0 <= z < cm.GRID:
            return x, z
        return None

    def new_value(self):
        t = self.tool.get()
        if t == "bld":
            return self.height.get(), self.family
        if t == "road":
            return cm.ROAD, None
        if t == "wall":
            return cm.WALL_H, cm.WALL_FAMILY
        if t == "pad":
            return cm.PAD, cm.PAD_FAMILY
        if t == "terrace":
            return cm.TERRACE, cm.TERRACE_FAMILY
        return cm.VOID, None

    def on_paint(self, ev):
        at = self.cell_at(ev)
        if at is None:
            return
        i = at[1] * cm.GRID + at[0]
        code, fam = self.new_value()
        if (self.cells[i], self.fams[i]) == (code, fam):
            return
        if code == cm.PAD and cm.pads(self.cells):
            self.status.config(text="only 1 landing pad may be deployed (at "
                               f"{cm.PAD_X}, {cm.PAD_Z}): paint the old one over first")
            return
        if (code == cm.TERRACE and (at[0], at[1]) not in cm.base_cells()
                and len(cm.barricades(self.cells)) >= cm.MAX_BARRICADES):
            self.status.config(text=f"all {cm.MAX_BARRICADES} barricades are placed: "
                               "remove one first")
            return
        if self.stroke is None:
            self.stroke = []
        self.stroke.append((i, self.cells[i], self.fams[i]))
        self.cells[i], self.fams[i] = code, fam
        self.canvas.itemconfig(self.rects[i], fill=self.cell_colour(i))
        self.show_stats()
        if not self.dirty:
            self.dirty = True
            self.set_title()
        self.on_move(ev)

    def on_release(self, ev):
        if self.stroke:
            self.undo.append(self.stroke)
        self.stroke = None

    def on_pick(self, ev):
        at = self.cell_at(ev)
        if at is None:
            return
        i = at[1] * cm.GRID + at[0]
        code, fam = self.cells[i], self.fams[i]
        tools = {cm.ROAD: "road", cm.PAD: "pad", cm.TERRACE: "terrace", cm.VOID: "void"}
        if cm.is_building(code):
            self.height.set(code)
            if cm.is_bld_family(fam):
                self.family = fam
            self.tool.set("bld")
            self.draw_palette()
        else:
            self.tool.set(tools[code])

    def on_palette(self, ev):
        f = self.pal_family(ev.x, ev.y)
        if f is None:
            return
        if f >= cm.BLD_FAMILIES:
            whose = "terrace" if f == cm.TERRACE_FAMILY else "landing pad"
            self.status.config(text=f"family {f:02d} is the {whose}'s: not a building colour")
        else:
            self.family = f
            self.tool.set("bld")
            self.draw_palette()

    def on_move(self, ev):
        at = self.cell_at(ev)
        if at is None:
            self.status.config(text="")
            return
        i = at[1] * cm.GRID + at[0]
        code, fam = self.cells[i], self.fams[i]
        names = {cm.ROAD: "road", cm.PAD: "landing pad", cm.TERRACE: "terrace", cm.VOID: "out of bounds"}
        what = f"building, height {code}" if cm.is_building(code) else names[code]
        if cm.is_building(code) and fam is not None:
            what += f", family {cm.family_text(fam)}"
        if cm.is_building(code) and not cm.is_bld_family(fam):
            what += " (not a valid base colour)"
        self.status.config(text=f"x {at[0]}  z {at[1]}   {what}")

    # ---------------------------------------------------------- commands
    def cmd_bad_colours(self):
        """Flash the buildings without a valid base colour red, for FLASH_MS."""
        bad = cm.bad_colours(self.cells, self.fams)
        if not bad:
            self.status.config(text="every building has a valid base colour (family 00-"
                               f"{cm.BLD_FAMILIES - 1:02d})")
            return
        self.status.config(text=f"{len(bad)} buildings without a valid base colour: flashing red")
        self.stop_flash()
        self.flash = [FLASH_MS // FLASH_STEP, False, set(), None]
        self.flash_step()

    def flash_step(self):
        """One step of the flash: the bad cells (looked for afresh, so one
        repainted meanwhile stops flashing) red, or their own colours."""
        left, on, shown, _ = self.flash
        on = not on and left > 1        # (ends showing the true colours)
        bad = set(cm.bad_colours(self.cells, self.fams)) if on else set()
        for i in shown | bad:
            self.canvas.itemconfig(self.rects[i], fill="#ff0000" if i in bad else self.cell_colour(i))
        if left > 1:
            job = self.root.after(FLASH_STEP, self.flash_step)
            self.flash = [left - 1, on, bad, job]
        else:
            self.flash = None

    def stop_flash(self):
        """Stop a flash, its cells back to their own colours."""
        if self.flash is None:
            return
        _, _, shown, job = self.flash
        self.flash = None
        if job:
            self.root.after_cancel(job)
        for i in shown:
            self.canvas.itemconfig(self.rects[i], fill=self.cell_colour(i))

    def cmd_undo(self):
        if self.stroke:
            self.on_release(None)
        if not self.undo:
            return
        for i, code, fam in reversed(self.undo.pop()):
            self.cells[i], self.fams[i] = code, fam
            self.canvas.itemconfig(self.rects[i], fill=self.cell_colour(i))
        self.show_stats()
        self.dirty = True
        self.set_title()

    def ask_discard(self):
        return not self.dirty or messagebox.askyesno(
            "Unsaved changes", "The map has unsaved changes. Discard them?")

    def cmd_open(self):
        if not self.ask_discard():
            return
        p = filedialog.askopenfilename(initialdir=MAP_DIR, title="Load a city map",
                                       filetypes=[("City maps", "*.json"), ("All files", "*.*")])
        if p:
            self.load(p)

    def load(self, path):
        try:
            m = cm.load(path)
        except (OSError, ValueError, KeyError) as e:
            messagebox.showerror("Can't load the map", str(e))
            return
        self.path = path
        self.city, self.name = m["city"], m["name"]
        self.cells, self.fams = m["cells"], m["fams"]
        self.undo, self.dirty = [], False
        zpc = os.path.join(DATA_DIR, f"CITY{self.city:02d}.ZPC")
        try:
            self.pal = cm.read_palette(zpc)
            note = f"palette from {rel(zpc)}"
        except (OSError, ValueError):
            self.pal = grey_palette()
            note = f"no {rel(zpc)} yet (run build.bat): grey palette"
        self.redraw()
        self.set_title()
        self.status.config(text=f"loaded {rel(path)}; {note}")

    def cmd_save(self):
        if self.path is None:
            return self.cmd_save_as()
        self.save(self.path)

    def cmd_save_as(self):
        p = filedialog.asksaveasfilename(initialdir=MAP_DIR, title="Save the city map",
                                         defaultextension=".json",
                                         initialfile=f"CITY{self.city:02d}.json" if self.city else "",
                                         filetypes=[("City maps", "*.json")])
        if p:
            self.save(p)

    def save(self, path):
        errs = cm.validate(self.cells, self.fams)
        try:
            cm.save(path, self.city, self.name, self.cells, self.fams)
        except OSError as e:
            messagebox.showerror("Can't save the map", str(e))
            return
        self.path, self.dirty = path, False
        self.set_title()
        self.status.config(text=f"saved {rel(path)}")
        if errs:
            messagebox.showwarning("Saved, with problems",
                                   "The map is saved, but the game can't use it until these are fixed "
                                   "(build.bat will stop on them):\n\n- " + "\n- ".join(errs))

    def cmd_check(self):
        errs = cm.validate(self.cells, self.fams)
        if errs:
            messagebox.showwarning("Map check", "- " + "\n- ".join(errs))
        else:
            messagebox.showinfo("Map check", "No problems: the game can use this map.")

    def cmd_quit(self):
        if self.ask_discard():
            self.root.destroy()


def main():
    root = tk.Tk()
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if path is None and os.path.exists(os.path.join(MAP_DIR, "CITY01.json")):
        path = os.path.join(MAP_DIR, "CITY01.json")
    Editor(root, path)
    root.mainloop()


if __name__ == "__main__":
    main()
