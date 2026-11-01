"""Z-Police city map editor: paint a city's 64 x 64 map (maps/CITYnn.json),
its levels' map changes and settings (levels/LEVELnn.TXL), and its colours.

    python tools/map_editor.py [maps/CITYnn.json]

The map is drawn flat, 8 pixels a cell (View menu: 4, 8 or 12) inside an
8-pixel white border; on the right, what to paint, how to draw it, the
building height and the city's colour families (its palette, read from
ZPDATA/CITYnn.ZPC as built by gentables.py, with any shades set here).

    Left button     draw with the selected draw mode (below)
    Right button    pick up the cell's height and colour
    Ctrl+Z          undo the last change
    Ctrl+A / C / V  select all, copy the selection, paste (click to place)
    Esc             drop the selection, stop pasting or picking a point

What to paint: Building (the selected height and colour), Road, Outer wall
(height 15, the wall's colour family), Landing pad (only 1), Terrace (the
pad's green defences; away from the base, barricades: at most 30, counted
below the map), Out of bounds.

Change (with the Building tool): Both (height and colour, as the cell is
painted), Colour only (buildings keep their height and take the selected
colour) or Height only (buildings keep their colour and take the selected
height); roads and the rest are left alone by those two.  The other tools
always change the whole cell.

Draw modes: Pencil (click or drag), Line, Box (a rectangle's outline),
Rectangle (filled), Fill (the area of cells like the one clicked, joined
side to side), Select (drag a rectangle: then Edit > Copy, Paste, Mirror
left-right / top-bottom).  Each is one change for Ctrl+Z.  Painting never
makes a second landing pad or a 31st barricade (the status line says so).

Edit > Wall round out of bounds: perimeter wall on every cell next to out of
bounds (diagonals too) that isn't wall or out of bounds already.  Edit >
Recolour off-wall wall colour: anything on the wall's colour that isn't
perimeter wall gets a random building colour.

Colour families: each is shown as its 3 shades in palette order, SHADE_DARK
(the family's base entry, family*4: what the game stores), SHADE_FACE,
SHADE_ROOF.  Only the SHADE_DARK swatches of the buildings' families (01-61,
each with a white border) can be picked; 00 is the perimeter wall's (the
Outer wall tool), 62 and 63 the terrace's and the pad's.  "Show bad colours"
flashes red, for 3 seconds, buildings whose colour isn't a building
family's SHADE_DARK and anything on the wall's colour that isn't perimeter
wall.  "Edit colours..." (and Edit > Edit colour family) sets a family's 3
shades by hand (r, g, b 0..7 each), saved with the map ("palette") and laid
over the generated palette by gentables.py; Reset puts the generated shades
back (maps/generated/CITYnn.pal).

Level menu: "Edit a level's map changes" shows the city as one of its levels
changes it; painting then changes that level only (its CHANGES, at most 64,
saved to levels/LEVELnn.TXL by Save), not the city.  "Back to the city map"
returns.  "Level settings" edits a level's zombies, waves, fast zombies,
draw distance and each wave's special monsters.

View > Preview from a point: click the map, give a heading and height, and
the game draws that view in the emulator (tools/preview.py, in the
background): from the map as it is here, saved or not.

Saving checks the map (tools/citymap.py validate) or the level (levelfile
level_check): the problems are shown, and gentables.py won't build one that
has any.  After saving, build.bat makes the ZPDATA files from them.
"""
import glob
import os
import random
import subprocess
import sys
import tempfile
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citymap as cm
import levelfile as lf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "maps")
DATA_DIR = os.path.join(ROOT, "ZPDATA")
LEVEL_DIR = os.path.join(ROOT, "levels")
BORDER = 8
G = cm.GRID
# The palette: each colour family as a group of its 3 shades, PAL_ORDER
# (SHADE_DARK, the family's base entry and the only one to pick, then
# SHADE_FACE and SHADE_ROOF), PAL_COLS families a row
SWATCH = 12                             # a shade's swatch, pixels
PAL_ORDER = (cm.SHADE_DARK, cm.SHADE_FACE, cm.SHADE_ROOF)
SHADE_NAMES = ("SHADE_DARK", "SHADE_FACE", "SHADE_ROOF")
PAL_COLS = 4
PAL_GX = 3 * SWATCH + 6                 # a family group's pitch: across,
PAL_GY = SWATCH + 6                     #   and down
PAL_W = PAL_COLS * PAL_GX
PAL_H = (cm.FAMILIES // PAL_COLS) * PAL_GY
FLASH_MS = 3000                         # Show bad colours: flash this long,
FLASH_STEP = 250                        # on / off every this many ms
TOOLS = [("Building", "bld"), ("Road", "road"), ("Outer wall", "wall"),
         ("Landing pad", "pad"), ("Terrace", "terrace"), ("Out of bounds", "void")]
MODES = [("Pencil", "pencil"), ("Line", "line"), ("Box", "box"), ("Rectangle", "rect"),
         ("Fill", "fill"), ("Select", "select")]
CHANGES = [("Both", "both"), ("Colour only", "colour"), ("Height only", "height")]
AROUND = cm.AROUND


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


def line_cells(x0, z0, x1, z1):
    """The cells of a line from one cell to another (Bresenham)."""
    cells = []
    dx, dz = abs(x1 - x0), -abs(z1 - z0)
    sx, sz = (1 if x0 < x1 else -1), (1 if z0 < z1 else -1)
    err = dx + dz
    while True:
        cells.append((x0, z0))
        if (x0, z0) == (x1, z1):
            return cells
        e2 = 2 * err
        if e2 >= dz:
            err += dz
            x0 += sx
        if e2 <= dx:
            err += dx
            z0 += sz


def level_files(city):
    """The levels of city n with a source file: [(level, path)]."""
    out = []
    for p in sorted(glob.glob(os.path.join(LEVEL_DIR, "LEVEL*.TXL"))):
        try:
            d = lf.read(p)
        except (OSError, ValueError):
            continue
        if d["cn"] == city:
            out.append((d["lv"], p))
    return out


class Editor:
    def __init__(self, root, path=None):
        self.root = root
        self.cell = 8                   # pixels a map cell (View menu: 4, 8, 12)
        self.path = None
        self.city, self.name = 0, ""
        self.cells = [cm.ROAD] * (G * G)
        self.fams = [None] * (G * G)
        self.pal_over = {}              # shades set by hand: family -> 3 (r, g, b)
        self.pal_gen = grey_palette()   # the palette as generated (Reset)
        self.pal = grey_palette()       # as shown: pal_gen with pal_over
        self.dirty = False
        self.undo = []                  # changes: lists of (index, code, family)
        self.stroke = None              # the change being made
        self.level = None               # level mode: the level's number,
        self.base = None                #   and the city as it is without it
        self.tool = tk.StringVar(value="bld")
        self.mode = tk.StringVar(value="pencil")
        self.change = tk.StringVar(value="both")    # Building: what it changes
        self.height = tk.IntVar(value=4)
        self.family = 1
        self.show_heights = tk.BooleanVar(value=False)
        self.invert_roads = tk.BooleanVar(value=False)   # (the view only)
        self.flash = None               # Show bad colours: [steps left, on, red cells, after job]
        self.start = None               # line / box / rectangle / select: the first cell
        self.sel = None                 # the selection: (x0, z0, x1, z1)
        self.clip = None                # copied: rows of (code, family)
        self.pasting = False
        self.picking = False            # Preview: waiting for a click on the map
        self.preview_job = None
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
        fm.add_command(label="Save", command=self.cmd_save, accelerator="Ctrl+S")
        fm.add_command(label="Save map as...", command=self.cmd_save_as)
        fm.add_separator()
        fm.add_command(label="Check", command=self.cmd_check)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.cmd_quit)
        mb.add_cascade(label="File", menu=fm)
        em = tk.Menu(mb, tearoff=0)
        em.add_command(label="Undo", command=self.cmd_undo, accelerator="Ctrl+Z")
        em.add_separator()
        em.add_command(label="Select all", command=self.cmd_select_all, accelerator="Ctrl+A")
        em.add_command(label="Copy the selection", command=self.cmd_copy, accelerator="Ctrl+C")
        em.add_command(label="Paste (click to place)", command=self.cmd_paste, accelerator="Ctrl+V")
        em.add_command(label="Mirror the selection left-right", command=lambda: self.cmd_mirror(True))
        em.add_command(label="Mirror the selection top-bottom", command=lambda: self.cmd_mirror(False))
        em.add_separator()
        em.add_command(label="Wall round out of bounds", command=self.cmd_wall_void)
        em.add_command(label="Recolour off-wall wall colour", command=self.cmd_fix_walls)
        em.add_separator()
        em.add_command(label="Edit colour family...", command=self.cmd_palette)
        mb.add_cascade(label="Edit", menu=em)
        lm = tk.Menu(mb, tearoff=0)
        lm.add_command(label="Edit a level's map changes...", command=self.cmd_level_mode)
        lm.add_command(label="Back to the city map", command=self.cmd_city_mode)
        lm.add_separator()
        lm.add_command(label="Level settings...", command=self.cmd_level_settings)
        mb.add_cascade(label="Level", menu=lm)
        vm = tk.Menu(mb, tearoff=0)
        for n in (4, 8, 12):
            vm.add_command(label=f"{n} pixels a cell", command=lambda n=n: self.set_cell(n))
        vm.add_separator()
        vm.add_checkbutton(label="Show heights (grey)", variable=self.show_heights,
                           command=self.redraw)
        vm.add_checkbutton(label="Invert roads (white)", variable=self.invert_roads,
                           command=self.redraw)
        vm.add_separator()
        vm.add_command(label="Preview from a point...", command=self.cmd_preview)
        mb.add_cascade(label="View", menu=vm)
        r.config(menu=mb)
        r.bind("<Control-o>", lambda e: self.cmd_open())
        r.bind("<Control-s>", lambda e: self.cmd_save())
        r.bind("<Control-z>", lambda e: self.cmd_undo())
        r.bind("<Control-a>", lambda e: self.cmd_select_all())
        r.bind("<Control-c>", lambda e: self.cmd_copy())
        r.bind("<Control-v>", lambda e: self.cmd_paste())
        r.bind("<Escape>", lambda e: self.cmd_escape())
        r.protocol("WM_DELETE_WINDOW", self.cmd_quit)

        main = tk.Frame(r)
        main.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        left = tk.Frame(main)
        left.pack(side=tk.LEFT, anchor=tk.N)
        self.canvas = tk.Canvas(left, bg="white", highlightthickness=0)
        self.canvas.pack(side=tk.TOP, anchor=tk.W)
        self.stats = tk.Label(left, text="", anchor=tk.W, font=("TkDefaultFont", 10))
        self.stats.pack(side=tk.TOP, anchor=tk.W, padx=BORDER)
        self.canvas.bind("<Button-1>", self.on_press)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.canvas.bind("<Button-3>", self.on_pick)
        self.canvas.bind("<Motion>", self.on_move)

        side = tk.Frame(main, padx=8, pady=4)
        side.pack(side=tk.LEFT, anchor=tk.N, fill=tk.Y)
        cols = tk.Frame(side)
        cols.pack(anchor=tk.W)
        c1, c2 = tk.Frame(cols), tk.Frame(cols, padx=10)
        c1.pack(side=tk.LEFT, anchor=tk.N)
        c2.pack(side=tk.LEFT, anchor=tk.N)
        tk.Label(c1, text="Paint", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W)
        for label, key in TOOLS:
            tk.Radiobutton(c1, text=label, variable=self.tool, value=key).pack(anchor=tk.W)
        tk.Label(c2, text="Draw", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W)
        for label, key in MODES:
            tk.Radiobutton(c2, text=label, variable=self.mode, value=key,
                           command=self.mode_changed).pack(anchor=tk.W)
        tk.Label(side, text="Change (Building)", font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W, pady=(8, 0))
        cf = tk.Frame(side)
        cf.pack(anchor=tk.W)
        for label, key in CHANGES:
            tk.Radiobutton(cf, text=label, variable=self.change, value=key,
                           command=lambda: self.tool.set("bld")).pack(side=tk.LEFT)
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
        bf = tk.Frame(side)
        bf.pack(anchor=tk.W, pady=(8, 0))
        tk.Button(bf, text="Show bad colours", command=self.cmd_bad_colours).pack(side=tk.LEFT)
        tk.Button(bf, text="Edit colours...", command=self.cmd_palette).pack(side=tk.LEFT, padx=6)
        self.status = tk.Label(r, text="", anchor=tk.W, relief=tk.SUNKEN)
        self.status.pack(side=tk.BOTTOM, fill=tk.X)
        self.rects = []
        self.make_grid()

    def make_grid(self):
        c = self.cell
        self.canvas.delete("all")
        self.canvas.config(width=G * c + 2 * BORDER, height=G * c + 2 * BORDER)
        self.rects = [self.canvas.create_rectangle(BORDER + x * c, BORDER + z * c,
                                                   BORDER + (x + 1) * c, BORDER + (z + 1) * c,
                                                   width=0)
                      for z in range(G) for x in range(G)]

    def set_cell(self, n):
        self.cell = n
        self.make_grid()
        self.redraw()

    def set_title(self):
        what = os.path.basename(self.path) if self.path else "(new)"
        lv = f" - LEVEL {self.level}'s map changes" if self.level is not None else ""
        self.root.title(f"Z-Police map editor - {what} {self.name}{lv}{' *' if self.dirty else ''}")

    def say(self, text):
        self.status.config(text=text)

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

    def paint(self, i):
        self.canvas.itemconfig(self.rects[i], fill=self.cell_colour(i))

    def redraw(self):
        self.stop_flash()               # (its cells are redrawn anyway)
        for i in range(G * G):
            self.paint(i)
        self.draw_palette()
        self.show_stats()
        self.draw_overlay()

    def changes(self):
        """Level mode: the cells the level changes, (x, z, code, city_col)."""
        out = []
        for i, (c, f) in enumerate(zip(self.cells, self.fams)):
            if (c, f) != (self.base[0][i], self.base[1][i]):
                out.append((i % G, i // G, c, lf.GROUND_IDX if f is None else cm.city_col(f)))
        return out

    def show_stats(self):
        """Below the map: barricades placed out of the most, landing pads,
        and in level mode the level's map changes."""
        nb, npad = len(cm.barricades(self.cells)), len(cm.pads(self.cells))
        text = f"Barricades: {nb} / {cm.MAX_BARRICADES} placed      Landing pad: {npad} / 1"
        over = nb > cm.MAX_BARRICADES or npad != 1
        if self.level is not None:
            nc = len(self.changes())
            text += f"      Level {self.level}: {nc} / {lf.LVF_CHG_MAX} map changes"
            over = over or nc > lf.LVF_CHG_MAX
        self.stats.config(text=text, fg="red" if over else "black")

    def draw_overlay(self):
        """The selection (dashed) over the map."""
        self.canvas.delete("overlay")
        if self.sel:
            x0, z0, x1, z1 = self.sel
            c = self.cell
            self.canvas.create_rectangle(BORDER + x0 * c, BORDER + z0 * c, BORDER + (x1 + 1) * c,
                                         BORDER + (z1 + 1) * c, outline="yellow", dash=(4, 3),
                                         width=2, tags="overlay")

    def draw_palette(self):
        pc = self.pcanvas
        pc.delete("all")
        for f in range(cm.FAMILIES):
            x, y = self.pal_xy(f)
            for k, e in enumerate(PAL_ORDER):   # dark (base), face, roof
                pc.create_rectangle(x + k * SWATCH, y, x + (k + 1) * SWATCH, y + SWATCH,
                                    fill=hex_rgb(self.pal[f * 4 + e]), width=0)
            if self.pickable(f):        # its SHADE_DARK, to pick: a white border
                pc.create_rectangle(x - 1, y - 1, x + SWATCH + 1, y + SWATCH + 1,
                                    outline="white", width=1)
            else:                       # the wall's, terrace's, pad's: not for picking
                pc.create_line(x, y + SWATCH, x + 3 * SWATCH, y, fill="#303030", width=2)
            if f in self.pal_over:      # shades set by hand: a mark under it
                pc.create_line(x, y + SWATCH + 2, x + 3 * SWATCH, y + SWATCH + 2, fill="orange")
        x, y = self.pal_xy(self.family)
        pc.create_rectangle(x - 3, y - 3, x + SWATCH + 3, y + SWATCH + 3, outline="yellow", width=2)
        notes = {cm.WALL_FAMILY: " (the wall's)"}
        hand = ", set by hand" if self.family in self.pal_over else ""
        self.fam_label.config(text=f"family {self.family:02d}{notes.get(self.family, '')}: "
                                   f"SHADE_DARK, entry {cm.city_col(self.family)}{hand}")

    @staticmethod
    def pickable(f):
        """Family f can be picked for a building (not the wall's: the Outer
        wall tool paints that; not the terrace's or pad's)."""
        return f != cm.WALL_FAMILY and cm.is_bld_family(f)

    @staticmethod
    def pal_xy(f):
        """Family f's group in the palette: its top left."""
        return (f % PAL_COLS) * PAL_GX + 3, (f // PAL_COLS) * PAL_GY + 3

    @staticmethod
    def pal_family(x, y):
        """The family whose group (or the gap round it) is at (x, y), and
        the shade there (PAL_ORDER; the gap counts as the nearest); None."""
        c, r = x // PAL_GX, y // PAL_GY
        if 0 <= c < PAL_COLS and 0 <= r < cm.FAMILIES // PAL_COLS:
            k = min(2, max(0, (x - c * PAL_GX - 3) // SWATCH))
            return r * PAL_COLS + c, PAL_ORDER[k]
        return None

    # ------------------------------------------------------- changing cells
    def begin(self):
        """Start a change (one Ctrl+Z): the counts the checks keep up."""
        self.stroke = []
        self.nbarr = len(cm.barricades(self.cells))
        self.npad = len(cm.pads(self.cells))
        self.refused = None

    def put(self, i, code, fam):
        """Cell i to (code, family) in the change being made, unless that
        would make a second landing pad or a 31st barricade (or, in level
        mode, touch the pad).  False if refused."""
        old = (self.cells[i], self.fams[i])
        if old == (code, fam):
            return True
        x, z = i % G, i // G
        base = (x, z) in cm.base_cells()
        if self.level is not None and cm.PAD in (code, old[0]):
            self.refused = "a level can't move or add the landing pad"
            return False
        if code == cm.PAD and self.npad - (old[0] == cm.PAD) >= 1:
            self.refused = (f"only 1 landing pad may be deployed (at {cm.PAD_X}, {cm.PAD_Z}): "
                            "paint the old one over first")
            return False
        was_b = old[0] == cm.TERRACE and not base
        is_b = code == cm.TERRACE and not base
        if is_b and not was_b and self.nbarr >= cm.MAX_BARRICADES:
            self.refused = f"all {cm.MAX_BARRICADES} barricades are placed: remove one first"
            return False
        self.nbarr += is_b - was_b
        self.npad += (code == cm.PAD) - (old[0] == cm.PAD)
        self.stroke.append((i, old[0], old[1]))
        self.cells[i], self.fams[i] = code, fam
        self.paint(i)
        return True

    def end(self, what=None):
        """Finish the change: undoable, the title and stats brought up to
        date, and any refusal or note on the status line."""
        if self.stroke:
            self.undo.append(self.stroke)
            if not self.dirty:
                self.dirty = True
                self.set_title()
        self.stroke = None
        self.show_stats()
        if self.refused:
            self.say(self.refused)
        elif what:
            self.say(what)

    def target(self, i):
        """What painting cell i makes it, (code, family), with Change (the
        Building tool: Colour only keeps a building's height, Height only its
        colour, and both leave other cells alone); None: left alone."""
        code, fam = self.new_value()
        how = self.change.get()
        if self.tool.get() != "bld" or how == "both":
            return code, fam
        c, f = self.cells[i], self.fams[i]
        if not cm.is_building(c):
            return None
        return (c, fam) if how == "colour" else (code, f)

    def put_all(self, points, what=None):
        """Paint each (x, z) with what is selected to paint, as one change."""
        self.begin()
        for x, z in points:
            if 0 <= x < G and 0 <= z < G:
                t = self.target(z * G + x)
                if t:
                    self.put(z * G + x, *t)
        self.end(what)

    # ------------------------------------------------------------- input
    def cell_at(self, ev, clamp=False):
        x, z = (ev.x - BORDER) // self.cell, (ev.y - BORDER) // self.cell
        if clamp:
            return max(0, min(G - 1, x)), max(0, min(G - 1, z))
        if 0 <= x < G and 0 <= z < G:
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

    def mode_changed(self):
        self.start = None
        self.canvas.delete("shape")

    def on_press(self, ev):
        at = self.cell_at(ev)
        if at is None:
            return
        if self.picking:                # Preview: this point
            self.picking = False
            return self.preview_at(*at)
        if self.pasting:
            self.pasting = False
            return self.paste_at(*at)
        m = self.mode.get()
        if m == "pencil":
            self.begin()
            self.on_drag(ev)
        elif m == "fill":
            self.fill(*at)
        else:                           # line, box, rectangle, select: a drag
            self.start = at
            self.on_drag(ev)

    def on_drag(self, ev):
        m = self.mode.get()
        if m == "pencil" and self.stroke is not None:
            at = self.cell_at(ev)
            if at:
                t = self.target(at[1] * G + at[0])
                if t:
                    self.put(at[1] * G + at[0], *t)
                if self.refused:
                    self.say(self.refused)
                self.on_move(ev)
        elif self.start and m in ("line", "box", "rect", "select"):
            x1, z1 = self.cell_at(ev, clamp=True)
            x0, z0 = self.start
            c = self.cell
            self.canvas.delete("shape")
            if m == "line":
                for x, z in line_cells(x0, z0, x1, z1):
                    self.canvas.create_rectangle(BORDER + x * c, BORDER + z * c, BORDER + (x + 1) * c,
                                                 BORDER + (z + 1) * c, outline="yellow", tags="shape")
            else:
                xa, xb, za, zb = min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)
                self.canvas.create_rectangle(BORDER + xa * c, BORDER + za * c, BORDER + (xb + 1) * c,
                                             BORDER + (zb + 1) * c, outline="yellow",
                                             dash=(4, 3) if m == "select" else None, width=2, tags="shape")
            self.say(f"({x0}, {z0}) to ({x1}, {z1})")

    def on_release(self, ev):
        m = self.mode.get()
        if m == "pencil":
            if self.stroke is not None:
                self.end()
            return
        if not self.start or m not in ("line", "box", "rect", "select"):
            return
        x1, z1 = self.cell_at(ev, clamp=True)
        x0, z0 = self.start
        self.start = None
        self.canvas.delete("shape")
        xa, xb, za, zb = min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)
        if m == "select":
            self.sel = (xa, za, xb, zb)
            self.draw_overlay()
            self.say(f"selected ({xa}, {za}) to ({xb}, {zb}): {xb - xa + 1} x {zb - za + 1} "
                     "(Edit: copy, mirror)")
        elif m == "line":
            self.put_all(line_cells(x0, z0, x1, z1))
        elif m == "rect":
            self.put_all([(x, z) for z in range(za, zb + 1) for x in range(xa, xb + 1)])
        else:                           # box: the outline
            pts = [(x, z) for z in range(za, zb + 1) for x in range(xa, xb + 1)
                   if x in (xa, xb) or z in (za, zb)]
            self.put_all(pts)

    def fill(self, x, z):
        """Flood fill: every cell like (x, z) joined to it side to side."""
        i0 = z * G + x
        like = (self.cells[i0], self.fams[i0])
        if self.target(i0) in (None, like):
            return self.say("that area is already this" if self.target(i0) else
                            "Colour / Height only change buildings: that isn't one")
        seen, todo, pts = {i0}, [i0], []
        while todo:
            i = todo.pop()
            pts.append((i % G, i // G))
            cx, cz = i % G, i // G
            for dx, dz in cm.ORTH:
                nx, nz = cx + dx, cz + dz
                j = nz * G + nx
                if 0 <= nx < G and 0 <= nz < G and j not in seen and (self.cells[j], self.fams[j]) == like:
                    seen.add(j)
                    todo.append(j)
        self.put_all(pts, f"filled {len(pts)} cells")

    def on_pick(self, ev):
        at = self.cell_at(ev)
        if at is None:
            return
        i = at[1] * G + at[0]
        code, fam = self.cells[i], self.fams[i]
        tools = {cm.ROAD: "road", cm.PAD: "pad", cm.TERRACE: "terrace", cm.VOID: "void"}
        if cm.is_wall(self.cells, self.fams, at[0], at[1]):
            self.tool.set("wall")
        elif cm.is_building(code):
            self.height.set(code)
            if self.pickable(fam):
                self.family = fam
            self.tool.set("bld")
            self.draw_palette()
        else:
            self.tool.set(tools[code])

    def on_palette(self, ev):
        at = self.pal_family(ev.x, ev.y)
        if at is None:
            return
        f, shade = at
        if f == cm.WALL_FAMILY:
            self.say(f"family {f:02d} is the perimeter wall's: paint the wall with the Outer wall tool")
        elif f >= cm.BLD_FAMILIES:
            whose = "terrace" if f == cm.TERRACE_FAMILY else "landing pad"
            self.say(f"family {f:02d} is the {whose}'s: not a building colour")
        elif shade != cm.SHADE_DARK:
            name = "SHADE_FACE" if shade == cm.SHADE_FACE else "SHADE_ROOF"
            self.say(f"family {f:02d}'s {name} is shown, not picked: pick its "
                     "SHADE_DARK (the first swatch, with the white border)")
        else:
            self.family = f
            self.say(f"family {f:02d}: SHADE_DARK, palette entry {cm.city_col(f)}")
            self.tool.set("bld")
            self.draw_palette()

    def on_move(self, ev):
        at = self.cell_at(ev)
        if at is None:
            self.say("")
            return
        i = at[1] * G + at[0]
        code, fam = self.cells[i], self.fams[i]
        names = {cm.ROAD: "road", cm.PAD: "landing pad", cm.TERRACE: "terrace", cm.VOID: "out of bounds"}
        what = f"building, height {code}" if cm.is_building(code) else names[code]
        if cm.is_building(code) and fam is not None:
            what += f", family {cm.family_text(fam)}"
        if cm.is_building(code) and not cm.is_bld_family(fam):
            what += " (not a building family's SHADE_DARK)"
        elif fam == cm.WALL_FAMILY and i in cm.bad_walls(self.cells, self.fams):
            what += " (the wall's colour, but not perimeter wall)"
        if self.level is not None and (code, fam) != (self.base[0][i], self.base[1][i]):
            what += f"  [changed by level {self.level}]"
        if self.pasting:
            what += "   - click to paste here (Esc: stop)"
        if self.picking:
            what += "   - click where the VTOL should be (Esc: stop)"
        self.say(f"x {at[0]}  z {at[1]}   {what}")

    # ---------------------------------------------------- selection commands
    def cmd_escape(self):
        self.pasting = self.picking = False
        self.sel = None
        self.start = None
        self.canvas.delete("shape")
        self.draw_overlay()
        self.say("")

    def cmd_select_all(self):
        self.sel = (0, 0, G - 1, G - 1)
        self.draw_overlay()
        self.say("selected the whole map")

    def cmd_copy(self):
        if not self.sel:
            return self.say("select an area first (draw mode Select, or Ctrl+A)")
        x0, z0, x1, z1 = self.sel
        self.clip = [[(self.cells[z * G + x], self.fams[z * G + x]) for x in range(x0, x1 + 1)]
                     for z in range(z0, z1 + 1)]
        self.say(f"copied {x1 - x0 + 1} x {z1 - z0 + 1} cells: Ctrl+V, then click to place")

    def cmd_paste(self):
        if not self.clip:
            return self.say("nothing copied yet (select an area, then Ctrl+C)")
        self.pasting = True
        self.say("click where the copy's top left corner goes (Esc: stop)")

    def paste_at(self, x, z):
        self.begin()
        for dz, row in enumerate(self.clip):
            for dx, (code, fam) in enumerate(row):
                if 0 <= x + dx < G and 0 <= z + dz < G:
                    self.put((z + dz) * G + x + dx, code, fam)
        h, w = len(self.clip), len(self.clip[0])
        self.sel = (x, z, min(G - 1, x + w - 1), min(G - 1, z + h - 1))
        self.draw_overlay()
        self.end(f"pasted {w} x {h} at ({x}, {z})")

    def cmd_mirror(self, left_right):
        if not self.sel:
            return self.say("select an area first (draw mode Select, or Ctrl+A)")
        x0, z0, x1, z1 = self.sel
        old = {(x, z): (self.cells[z * G + x], self.fams[z * G + x])
               for z in range(z0, z1 + 1) for x in range(x0, x1 + 1)}
        self.begin()
        for (x, z), v in old.items():
            tx, tz = (x0 + x1 - x, z) if left_right else (x, z0 + z1 - z)
            self.put(tz * G + tx, *v)
        self.end(f"mirrored the selection {'left-right' if left_right else 'top-bottom'}")

    # ------------------------------------------------------------ helpers
    def cmd_wall_void(self):
        """Edit > Wall round out of bounds: perimeter wall on every cell next
        to out of bounds (8 neighbours) that isn't wall or out of bounds."""
        pts = []
        for i, c in enumerate(self.cells):
            x, z = i % G, i // G
            if c == cm.VOID or cm.is_wall(self.cells, self.fams, x, z):
                continue
            if any(0 <= x + dx < G and 0 <= z + dz < G and self.cells[(z + dz) * G + x + dx] == cm.VOID
                   for dx, dz in AROUND):
                pts.append(i)
        if not pts:
            return self.say("every cell next to out of bounds is wall already")
        self.begin()
        for i in pts:
            self.put(i, cm.WALL_H, cm.WALL_FAMILY)
        bw = len(cm.bad_walls(self.cells, self.fams))
        self.end(f"walled {len(pts)} cells round out of bounds"
                 + (f"; {bw} wall cells still break the wall rule (Show bad colours)" if bw else ""))

    def cmd_bad_colours(self):
        """Flash red, for FLASH_MS, the buildings whose colour isn't a
        building family's SHADE_DARK."""
        bad = cm.bad_colours(self.cells, self.fams)
        if not bad:
            return self.say("every building's colour is a building family's "
                            "SHADE_DARK, and only perimeter wall has the wall's")
        nw = len(cm.bad_walls(self.cells, self.fams))
        self.say(f"{len(bad)} bad colours ({len(bad) - nw} not a building family's SHADE_DARK, "
                 f"{nw} the wall's off the perimeter wall): flashing red")
        self.stop_flash()
        self.flash = [FLASH_MS // FLASH_STEP, False, set(), None]
        self.flash_step()

    def cmd_fix_walls(self):
        """Edit > Recolour off-wall wall colour: every cell on the wall's
        colour that isn't perimeter wall (bad_walls) a random building colour
        (01-61), as one undoable change."""
        bad = cm.bad_walls(self.cells, self.fams)
        if not bad:
            return self.say("only perimeter wall has the wall's colour: nothing to recolour")
        self.begin()
        n = 0
        while bad:                      # (recolouring a wall tile can leave
            for i in bad:               # its neighbours short of 2)
                self.put(i, self.cells[i], random.randrange(cm.WALL_FAMILY + 1, cm.BLD_FAMILIES))
            n += len(bad)
            bad = cm.bad_walls(self.cells, self.fams)
        self.end(f"recoloured {n} cells off the perimeter wall (Ctrl+Z undoes)")

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
            self.paint(i)

    def cmd_undo(self):
        if self.stroke:
            self.end()
        if not self.undo:
            return
        for i, code, fam in reversed(self.undo.pop()):
            self.cells[i], self.fams[i] = code, fam
            self.paint(i)
        self.show_stats()
        self.dirty = True
        self.set_title()

    # -------------------------------------------------------- the palette
    def set_palette(self):
        self.pal = cm.apply_palette(list(self.pal_gen), self.pal_over)
        self.redraw()

    def cmd_palette(self):
        """Edit a colour family's 3 shades (Edit colours...)."""
        if self.level is not None:
            return self.say("colours belong to the city: Level > Back to the city map first")
        PaletteDialog(self)

    # -------------------------------------------------------------- levels
    def cmd_level_mode(self):
        """Level > Edit a level's map changes."""
        if self.level is not None and not self.ask_discard():
            return
        if self.level is None and self.dirty:
            if not messagebox.askyesno("Unsaved city map",
                                       "Save the city map first? (A level's changes are made "
                                       "over the city as it is saved.)"):
                return
            self.cmd_save()
            if self.dirty:
                return
        levels = level_files(self.city)
        if not levels:
            return messagebox.showinfo("No levels", f"No level files in {rel(LEVEL_DIR)} for "
                                       f"city {self.city} (run build.bat to make them).")
        nums = [lv for lv, _ in levels]
        lv = simpledialog.askinteger("Level map changes", "Which level? (this city's: "
                                     + ", ".join(map(str, nums)) + ")",
                                     initialvalue=nums[0], parent=self.root)
        if lv is None:
            return
        if lv not in nums:
            return messagebox.showerror("Not this city's", f"Level {lv} isn't one of this city's.")
        path = dict(levels)[lv]
        try:
            d = lf.read(path)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't read the level", f"{rel(path)}: {e}")
        if self.level is not None:      # (from another level: the city back)
            self.cells, self.fams = list(self.base[0]), list(self.base[1])
        self.base = (list(self.cells), list(self.fams))
        for x, z, code, col in d["changes"]:
            if 0 <= x < G and 0 <= z < G:
                self.cells[z * G + x] = code
                self.fams[z * G + x] = None if col == lf.GROUND_IDX else col // 4
        self.level, self.level_path = lv, path
        self.undo, self.dirty, self.sel = [], False, None
        self.redraw()
        self.set_title()
        self.say(f"level {lv}: {len(d['changes'])} map changes; painting changes this level "
                 "only (File > Save writes them to " + rel(path) + ")")

    def cmd_city_mode(self):
        if self.level is None:
            return self.say("already on the city map")
        if not self.ask_discard():
            return
        self.cells, self.fams = list(self.base[0]), list(self.base[1])
        self.level = self.base = None
        self.undo, self.dirty, self.sel = [], False, None
        self.redraw()
        self.set_title()
        self.say("the city map")

    def cmd_level_settings(self):
        levels = level_files(self.city)
        if not levels:
            return messagebox.showinfo("No levels", f"No level files in {rel(LEVEL_DIR)} for "
                                       f"city {self.city} (run build.bat to make them).")
        nums = [lv for lv, _ in levels]
        lv = self.level if self.level is not None else simpledialog.askinteger(
            "Level settings", "Which level? (this city's: " + ", ".join(map(str, nums)) + ")",
            initialvalue=nums[0], parent=self.root)
        if lv is None:
            return
        if lv not in nums:
            return messagebox.showerror("Not this city's", f"Level {lv} isn't one of this city's.")
        LevelDialog(self, lv, dict(levels)[lv])

    def city_for_checks(self):
        """{city: (cells, families)}: the city without any level's changes."""
        cells, fams = (self.base if self.level is not None else (self.cells, self.fams))
        return {self.city: (list(cells), list(fams))}

    # ------------------------------------------------------------- preview
    def cmd_preview(self):
        if not self.city:
            return self.say("load a city map first")
        if not os.path.exists(os.path.join(ROOT, "zpolice.nex")):
            return messagebox.showerror("No game built", "Build the game first (build.bat).")
        self.picking = True
        self.say("click the map where the VTOL should be (Esc: stop)")

    def preview_at(self, x, z):
        heading = simpledialog.askfloat("Preview", "Heading, degrees (0 north, up the map; 90 east):",
                                        initialvalue=0, minvalue=0, maxvalue=360, parent=self.root)
        if heading is None:
            return
        height = simpledialog.askinteger("Preview", "Height, world units (8..192; 128 a height level):",
                                         initialvalue=120, minvalue=8, maxvalue=192, parent=self.root)
        if height is None:
            return
        tmp = tempfile.mkdtemp(prefix="zpolice_map_")
        js, png = os.path.join(tmp, "map.json"), os.path.join(tmp, "preview.png")
        cm.save(js, self.city, self.name, self.cells, self.fams, self.pal_over)
        args = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview.py"),
                js, str(x), str(z), "--heading", str(heading), "--height", str(height), "--out", png]
        if self.level is not None:
            args += ["--level", str(self.level)]
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.say(f"drawing the view from ({x}, {z}), heading {heading:g}, height {height} "
                 "in the emulator...")
        self.root.after(300, lambda: self.preview_wait(proc, png, (x, z, heading, height)))

    def preview_wait(self, proc, png, what):
        if proc.poll() is None:
            self.root.after(300, lambda: self.preview_wait(proc, png, what))
            return
        out, err = proc.communicate()
        if proc.returncode or not os.path.exists(png):
            return messagebox.showerror("Preview failed", (err or out or "no picture")[-800:])
        win = tk.Toplevel(self.root)
        x, z, heading, height = what
        win.title(f"Preview: ({x}, {z}), heading {heading:g}, height {height}")
        img = tk.PhotoImage(file=png).zoom(2)
        lab = tk.Label(win, image=img)
        lab.image = img                 # (keep it)
        lab.pack()
        self.say(f"preview from ({x}, {z}) drawn")

    # ----------------------------------------------------------- the files
    def ask_discard(self):
        what = f"level {self.level}'s map changes" if self.level is not None else "the map"
        return not self.dirty or messagebox.askyesno(
            "Unsaved changes", f"{what[0].upper() + what[1:]} has unsaved changes. Discard them?")

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
        self.pal_over = m["palette"]
        self.level = self.base = self.sel = None
        self.undo, self.dirty = [], False
        zpc = os.path.join(DATA_DIR, f"CITY{self.city:02d}.ZPC")
        gen = cm.read_generated(self.city, MAP_DIR)
        try:
            built = cm.read_palette(zpc)
            note = f"palette from {rel(zpc)}"
        except (OSError, ValueError):
            built = None
            note = f"no {rel(zpc)} yet (run build.bat): grey palette"
        self.pal_gen = gen or built or grey_palette()
        if built and not gen:
            note += " (no maps/generated palette yet: Reset uses the built one)"
        self.set_palette()
        self.set_title()
        self.say(f"loaded {rel(path)}; {note}")

    def cmd_save(self):
        if self.level is not None:
            return self.save_level()
        if self.path is None:
            return self.cmd_save_as()
        self.save(self.path)

    def cmd_save_as(self):
        if self.level is not None:
            return self.say("in level mode Save writes the level's changes; "
                            "Level > Back to the city map to save the map as another file")
        p = filedialog.asksaveasfilename(initialdir=MAP_DIR, title="Save the city map",
                                         defaultextension=".json",
                                         initialfile=f"CITY{self.city:02d}.json" if self.city else "",
                                         filetypes=[("City maps", "*.json")])
        if p:
            self.save(p)

    def save(self, path):
        errs = cm.validate(self.cells, self.fams, self.pal_over)
        try:
            cm.save(path, self.city, self.name, self.cells, self.fams, self.pal_over)
        except OSError as e:
            messagebox.showerror("Can't save the map", str(e))
            return
        self.path, self.dirty = path, False
        self.set_title()
        self.say(f"saved {rel(path)}")
        if errs:
            messagebox.showwarning("Saved, with problems",
                                   "The map is saved, but the game can't use it until these are fixed "
                                   "(build.bat will stop on them):\n\n- " + "\n- ".join(errs))

    def save_level(self):
        """Level mode: the level's map changes into its file (its other
        settings as they are in the file)."""
        try:
            d = lf.read(self.level_path)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't read the level", f"{rel(self.level_path)}: {e}")
        d["changes"] = self.changes()
        errs = lf.level_check(self.level, d, self.city_for_checks())
        try:
            lf.write(self.level_path, d)
        except OSError as e:
            return messagebox.showerror("Can't save the level", str(e))
        self.dirty = False
        self.set_title()
        self.say(f"saved level {self.level}'s {len(d['changes'])} map changes to {rel(self.level_path)}")
        if errs:
            messagebox.showwarning("Saved, with problems",
                                   "The level is saved, but the game can't use it until these are "
                                   "fixed (build.bat will stop on them):\n\n- " + "\n- ".join(errs))

    def cmd_check(self):
        if self.level is not None:
            try:
                d = lf.read(self.level_path)
            except (OSError, ValueError) as e:
                return messagebox.showerror("Can't read the level", str(e))
            d["changes"] = self.changes()
            errs = lf.level_check(self.level, d, self.city_for_checks())
            what = f"Level {self.level}"
        else:
            errs = cm.validate(self.cells, self.fams, self.pal_over)
            what = "The map"
        if errs:
            messagebox.showwarning("Check", "- " + "\n- ".join(errs))
        else:
            messagebox.showinfo("Check", f"No problems: the game can use {what.lower()}.")

    def cmd_quit(self):
        if self.ask_discard():
            self.root.destroy()


class PaletteDialog:
    """A colour family's 3 shades, r g b 0..7 each, set by hand."""

    def __init__(self, ed):
        self.ed = ed
        self.win = w = tk.Toplevel(ed.root)
        w.title("Colour family")
        w.transient(ed.root)
        top = tk.Frame(w, padx=8, pady=8)
        top.pack()
        tk.Label(top, text="Family").grid(row=0, column=0, sticky=tk.W)
        self.fam = tk.IntVar(value=ed.family)
        tk.Spinbox(top, from_=0, to=cm.FAMILIES - 1, width=4, textvariable=self.fam,
                   command=self.load).grid(row=0, column=1, sticky=tk.W)
        self.note = tk.Label(top, text="")
        self.note.grid(row=0, column=2, columnspan=5, sticky=tk.W)
        for j, t in enumerate(("r", "g", "b"), 1):
            tk.Label(top, text=t).grid(row=1, column=j)
        self.vars, self.swatches = [], []
        for k, name in enumerate(SHADE_NAMES):
            tk.Label(top, text=name).grid(row=2 + k, column=0, sticky=tk.W)
            row = []
            for j in range(3):
                v = tk.IntVar()
                tk.Spinbox(top, from_=0, to=7, width=3, textvariable=v,
                           command=self.show).grid(row=2 + k, column=1 + j, padx=2)
                row.append(v)
            self.vars.append(row)
            sw = tk.Canvas(top, width=40, height=18, highlightthickness=1)
            sw.grid(row=2 + k, column=4, padx=6)
            self.swatches.append(sw)
            gen = tk.Canvas(top, width=18, height=18, highlightthickness=1)
            gen.grid(row=2 + k, column=5)
            self.swatches.append(gen)
        tk.Label(top, text="(set / generated)").grid(row=5, column=4, columnspan=2)
        bf = tk.Frame(w, padx=8, pady=6)
        bf.pack()
        tk.Button(bf, text="Apply", command=self.apply).pack(side=tk.LEFT)
        tk.Button(bf, text="Reset to generated", command=self.reset).pack(side=tk.LEFT, padx=6)
        tk.Button(bf, text="Close", command=w.destroy).pack(side=tk.LEFT)
        self.load()

    def family(self):
        try:
            return max(0, min(cm.FAMILIES - 1, int(self.fam.get())))
        except (tk.TclError, ValueError):
            return self.ed.family

    def load(self):
        f = self.family()
        for k in range(3):
            for j, v in enumerate(self.ed.pal[f * 4 + k]):
                self.vars[k][j].set(v)
        self.show()

    def shades(self):
        out = []
        for row in self.vars:
            try:
                out.append(tuple(max(0, min(7, int(v.get()))) for v in row))
            except (tk.TclError, ValueError):
                out.append((0, 0, 0))
        return out

    def show(self):
        f = self.family()
        for k, c in enumerate(self.shades()):
            self.swatches[2 * k].config(bg=hex_rgb(c))
            self.swatches[2 * k + 1].config(bg=hex_rgb(self.ed.pal_gen[f * 4 + k]))
        notes = {cm.WALL_FAMILY: "the wall's (and the sky's)", cm.TERRACE_FAMILY: "the terrace's",
                 cm.PAD_FAMILY: "the landing pad's"}
        hand = "set by hand" if f in self.ed.pal_over else "as generated"
        self.note.config(text=f"  {notes.get(f, 'a building colour')}: {hand}")

    def apply(self):
        f, sh = self.family(), self.shades()
        bad = [SHADE_NAMES[k] for k, c in enumerate(sh) if cm.is_transparent(c)]
        if bad:
            return messagebox.showerror("Transparent", f"{', '.join(bad)}: (7, 0, 6) and (7, 0, 7) are "
                                        "Layer 2's transparent colour, never shown", parent=self.win)
        gen = [tuple(self.ed.pal_gen[f * 4 + k]) for k in range(3)]
        if sh == gen:
            self.ed.pal_over.pop(f, None)       # (as generated: no need to keep it)
        else:
            self.ed.pal_over[f] = sh
        self.changed(f"family {f:02d}'s shades {'set' if f in self.ed.pal_over else 'as generated'}")

    def reset(self):
        f = self.family()
        self.ed.pal_over.pop(f, None)
        self.load()
        self.changed(f"family {f:02d} back to its generated shades")

    def changed(self, what):
        self.ed.dirty = True
        self.ed.set_title()
        self.ed.set_palette()
        self.show()
        self.ed.say(what + " (File > Save keeps it; build.bat puts it in the game)")


class LevelDialog:
    """A level's settings and each wave's special monsters."""

    def __init__(self, ed, lv, path):
        self.ed, self.lv, self.path = ed, lv, path
        try:
            self.d = lf.read(path)
        except (OSError, ValueError) as e:
            messagebox.showerror("Can't read the level", f"{rel(path)}: {e}")
            return
        self.win = w = tk.Toplevel(ed.root)
        w.title(f"Level {lv} settings ({self.d['name'].strip()})")
        w.transient(ed.root)
        top = tk.Frame(w, padx=8, pady=8)
        top.pack(anchor=tk.W)
        zomb, waves, fast, view = self.d["values"]
        self.v = {}
        specs = [("Zombies a wave", "ZOMBIES", 1, lf.NZOMB, zomb),
                 ("Waves", "WAVES", 1, lf.LV_MAX_WAVES, waves),
                 ("Fast zombies", "FAST", 0, lf.NZOMB, fast),
                 ("Draw distance (tiles)", "VIEW", 2, lf.VIEW_R, view)]
        for r, (label, k, lo, hi, val) in enumerate(specs):
            tk.Label(top, text=label).grid(row=r, column=0, sticky=tk.W)
            v = tk.IntVar(value=val)
            tk.Spinbox(top, from_=lo, to=hi, width=4, textvariable=v,
                       command=self.waves_changed if k == "WAVES" else None).grid(row=r, column=1, sticky=tk.W)
            self.v[k] = v
        tk.Label(top, text="(fewer tiles: night or fog)").grid(row=3, column=2, sticky=tk.W)
        tk.Label(w, text="Special monsters each wave (wave 1 is the level's start; at most "
                 f"{lf.NSPEC} at once)", padx=8).pack(anchor=tk.W)
        self.grid = tk.Frame(w, padx=8)
        self.grid.pack(anchor=tk.W)
        self.counts = []                # per wave: {type id: IntVar}
        for sp in self.d["waves_specials"]:
            self.counts.append(self.wave_vars(sp))
        self.draw_grid()
        tk.Label(w, text=f"Map changes: {len(self.d['changes'])} (Level > Edit a level's map changes)",
                 padx=8).pack(anchor=tk.W)
        bf = tk.Frame(w, padx=8, pady=6)
        bf.pack(anchor=tk.W)
        tk.Button(bf, text="Save", command=self.save).pack(side=tk.LEFT)
        tk.Button(bf, text="Cancel", command=w.destroy).pack(side=tk.LEFT, padx=6)

    def wave_vars(self, sp=()):
        counts = {t: 0 for t in range(len(lf.SPEC_NAMES))}
        for t, n in sp:
            counts[t] += n
        return {t: tk.IntVar(value=n) for t, n in counts.items()}

    def draw_grid(self):
        for c in self.grid.winfo_children():
            c.destroy()
        tk.Label(self.grid, text="Wave").grid(row=0, column=0)
        for t, name in enumerate(lf.SPEC_NAMES):
            tk.Label(self.grid, text=name.title()).grid(row=0, column=1 + t, padx=4)
        for w, counts in enumerate(self.counts):
            tk.Label(self.grid, text=str(w + 1)).grid(row=1 + w, column=0)
            for t in range(len(lf.SPEC_NAMES)):
                tk.Spinbox(self.grid, from_=0, to=lf.NSPEC, width=3,
                           textvariable=counts[t]).grid(row=1 + w, column=1 + t, padx=4)

    def waves_changed(self):
        try:
            n = max(1, min(lf.LV_MAX_WAVES, int(self.v["WAVES"].get())))
        except (tk.TclError, ValueError):
            return
        while len(self.counts) < n:
            self.counts.append(self.wave_vars())
        del self.counts[n:]
        self.draw_grid()

    def save(self):
        self.waves_changed()            # (WAVES typed in: the rows to match)
        try:
            values = [int(self.v[k].get()) for k in lf.LEVEL_KEYS]
            ws = [[(t, int(v.get())) for t, v in sorted(c.items()) if int(v.get())] for c in self.counts]
        except (tk.TclError, ValueError):
            return messagebox.showerror("Not a number", "Every field needs a number.", parent=self.win)
        try:
            d = lf.read(self.path)      # (its map changes as saved)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't read the level", str(e), parent=self.win)
        d["values"], d["waves_specials"] = values, ws[:values[1]]
        errs = lf.level_check(self.lv, d, self.ed.city_for_checks())
        if errs:
            return messagebox.showerror("Level settings", "The game can't use these:\n\n- "
                                        + "\n- ".join(errs), parent=self.win)
        try:
            lf.write(self.path, d)
        except OSError as e:
            return messagebox.showerror("Can't save the level", str(e), parent=self.win)
        self.ed.say(f"saved level {self.lv}'s settings to {rel(self.path)} (build.bat puts them in the game)")
        self.win.destroy()


def main():
    root = tk.Tk()
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if path is None and os.path.exists(os.path.join(MAP_DIR, "CITY01.json")):
        path = os.path.join(MAP_DIR, "CITY01.json")
    Editor(root, path)
    root.mainloop()


if __name__ == "__main__":
    main()
