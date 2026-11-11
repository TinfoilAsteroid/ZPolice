"""Z-Police screen editor: images for the 320x256 screens, ZPDATA/*.ZPI
(tools/imagefile.py has the format), drawn by the game from the SD card when
a screen needs one (the load-out's VTOL.ZPI).

    python tools/screen_editor.py [file]          (ZPDATA/VTOL.ZPI: none)

The whole 320x256 screen, enlarged (View: 1x to 4x, 8x, 16x).  Nothing drawn is
CLEAR (shown as the screens' background, or the underlay): the game leaves
the screen as it is there.  The file keeps only the box round what is
drawn, at its place on the screen.

    Left button     the left colour            Right button   the right one
    Ctrl+click      pick up the pixel's colour (as the left colour)
    Ctrl+Z          undo                       Ctrl+S         save

Tools: Pencil, Line, Box, Filled box, Ellipse, Filled ellipse, Fill (the
area of the clicked colour, joined side to side), Select.  Lines, shapes and
selections are dragged from corner to corner.  The palette is every colour
the screens have (RRRGGGBB); the top-right swatch (marked) is CLEAR, to rub
out.

Copy and paste (Edit menu): drag a rectangle with Select, Ctrl+C copies it;
Ctrl+V picks it up, to follow the mouse (its top-left corner at the
pointer), and each left click puts a copy down there; right click or Esc
puts it away (so does choosing a tool).  CLEAR pixels in the copy leave
what is under them, unless Edit > Paste clear pixels too is ticked.  Each
paste can be undone.

View: grids of the screens' text cells (8x8, the large font's 12x10 from
(4, 3)) and the frame, and an underlay: a PNG of a screen (a screenshot of
the game, tests/zptest's nexsim.write_png) shown wherever the image is
CLEAR, to draw against.  Move (Image menu) shifts the whole image.
"""
import os
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imagefile as imf  # noqa: E402

SW, SH, CLEAR = imf.SW, imf.SH, imf.CLEAR
BG = 0x02                               # the screens' background (SCR_BG)
TOOLS = ("Pencil", "Line", "Box", "Filled box", "Ellipse", "Filled ellipse", "Fill", "Select")
SW_Z = 14                               # a palette swatch
ZOOMS = (1, 2, 3, 4, 8, 16)             # the view's enlargements


class Editor:
    def __init__(self, root, path):
        self.root, self.path = root, path
        self.im = imf.Image()
        if os.path.exists(path):
            try:
                self.im = imf.Image.load(path)
            except ValueError as e:
                messagebox.showwarning("Image", f"{path}: {e}\nStarting empty.")
        self.z = 3
        self.cols = [0xBF, CLEAR]       # left, right
        self.tool = tk.StringVar(value="Pencil")
        self.grid8 = tk.BooleanVar(value=False)
        self.grid12 = tk.BooleanVar(value=False)
        self.frame = tk.BooleanVar(value=True)
        self.under = None               # the underlay: [y][x] "#rrggbb", or None
        self.undo = []
        self.dirty = False
        self.drag = None
        self.sel = None                 # the selection: (x0, y0, x1, y1), inclusive
        self.clip = None                # the copy: (width, height, pixels row by row)
        self.pasting = None             # pasting: where the copy is ((x, y)), or None
        self.paste_clear = tk.BooleanVar(value=False)
        self.build()
        self.redraw()

    # --- layout -------------------------------------------------------------
    def build(self):
        r = self.root
        menu = tk.Menu(r)
        fm = tk.Menu(menu, tearoff=0)
        fm.add_command(label="New", command=self.new)
        fm.add_command(label="Open...", command=self.open)
        fm.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        fm.add_command(label="Save as...", command=self.save_as)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.quit)
        menu.add_cascade(label="File", menu=fm)
        cm = tk.Menu(menu, tearoff=0)
        cm.add_command(label="Undo", accelerator="Ctrl+Z", command=self.do_undo)
        cm.add_separator()
        cm.add_command(label="Copy the selection", accelerator="Ctrl+C", command=self.copy)
        cm.add_command(label="Paste", accelerator="Ctrl+V", command=self.paste)
        cm.add_checkbutton(label="Paste clear pixels too", variable=self.paste_clear,
                           command=self.paste_changed)
        cm.add_command(label="Select none", accelerator="Esc", command=self.escape)
        menu.add_cascade(label="Edit", menu=cm)
        em = tk.Menu(menu, tearoff=0)
        em.add_command(label="Clear all", command=self.clear_all)
        for t, d in (("Move left", (-1, 0)), ("Move right", (1, 0)), ("Move up", (0, -1)), ("Move down", (0, 1))):
            em.add_command(label=t, command=lambda d=d: self.move(*d))
        menu.add_cascade(label="Image", menu=em)
        vm = tk.Menu(menu, tearoff=0)
        for z in ZOOMS:
            vm.add_command(label=f"{z}x", command=lambda z=z: self.zoom(z))
        vm.add_separator()
        vm.add_checkbutton(label="8x8 text grid", variable=self.grid8, command=self.redraw)
        vm.add_checkbutton(label="Large font grid (12x10)", variable=self.grid12, command=self.redraw)
        vm.add_checkbutton(label="The screens' frame", variable=self.frame, command=self.redraw)
        vm.add_separator()
        vm.add_command(label="Underlay PNG...", command=self.load_under)
        vm.add_command(label="No underlay", command=self.no_under)
        menu.add_cascade(label="View", menu=vm)
        r.config(menu=menu)

        side = tk.Frame(r)
        side.pack(side="left", fill="y", padx=6, pady=6)
        for t in TOOLS:
            tk.Radiobutton(side, text=t, variable=self.tool, value=t, indicatoron=False,
                           width=14, command=self.end_paste).pack(anchor="w")
        tk.Label(side, text="Left / right colour").pack(anchor="w", pady=(8, 0))
        self.lr = tk.Canvas(side, width=16 * SW_Z, height=26, highlightthickness=0)
        self.lr.pack(anchor="w")
        self.pal = tk.Canvas(side, width=16 * SW_Z, height=16 * SW_Z, highlightthickness=0)
        self.pal.pack(anchor="w", pady=4)
        for i in range(256):
            x, y = (i % 16) * SW_Z, (i // 16) * SW_Z
            if i == CLEAR:
                self.pal.create_rectangle(x, y, x + SW_Z, y + SW_Z, fill="#808080", outline="")
                self.pal.create_line(x, y, x + SW_Z, y + SW_Z, fill="white")
                self.pal.create_line(x + SW_Z, y, x, y + SW_Z, fill="white")
            else:
                self.pal.create_rectangle(x, y, x + SW_Z, y + SW_Z, fill=imf.hexc(i), outline="")
        self.pal.bind("<Button-1>", lambda e: self.pick_pal(e, 0))
        self.pal.bind("<Button-3>", lambda e: self.pick_pal(e, 1))
        self.status = tk.Label(side, anchor="w", justify="left", width=30)
        self.status.pack(anchor="w", pady=6)

        main = tk.Frame(r)
        main.pack(side="left", fill="both", expand=True)
        self.cv = tk.Canvas(main, bg="#202020", highlightthickness=0,
                            xscrollincrement=1, yscrollincrement=1)
        hs = tk.Scrollbar(main, orient="horizontal", command=self.cv.xview)
        vs = tk.Scrollbar(main, orient="vertical", command=self.cv.yview)
        self.cv.config(xscrollcommand=hs.set, yscrollcommand=vs.set)
        hs.pack(side="bottom", fill="x")
        vs.pack(side="right", fill="y")
        self.cv.pack(side="left", fill="both", expand=True)
        self.photo = None
        for b, i in (("1", 0), ("3", 1)):
            self.cv.bind(f"<Button-{b}>", lambda e, i=i: self.press(e, i))
            self.cv.bind(f"<B{b}-Motion>", lambda e, i=i: self.motion(e, i))
            self.cv.bind(f"<ButtonRelease-{b}>", lambda e, i=i: self.release(e, i))
        self.cv.bind("<Motion>", self.hover)
        r.bind("<Control-s>", lambda e: self.save())
        r.bind("<Control-z>", lambda e: self.do_undo())
        r.bind("<Control-c>", lambda e: self.copy())
        r.bind("<Control-v>", lambda e: self.paste())
        r.bind("<Escape>", lambda e: self.escape())
        r.protocol("WM_DELETE_WINDOW", self.quit)
        r.geometry("1300x860")

    # --- drawing the view ---------------------------------------------------
    def shown(self, x, y):
        c = self.im.px[y * SW + x]
        if c != CLEAR:
            return imf.hexc(c)
        if self.under:
            return self.under[y][x]
        return imf.hexc(BG)

    def redraw(self):
        z = self.z
        base = tk.PhotoImage(width=SW, height=SH)   # the screen at 1x, then
        base.put(" ".join("{" + " ".join(self.shown(x, y) for x in range(SW)) + "}"
                          for y in range(SH)))
        self.photo = base.zoom(z) if z > 1 else base  # enlarged by Tk (fast)
        self.cv.delete("all")
        self.cv.create_image(0, 0, anchor="nw", image=self.photo)
        if self.grid8.get():
            for x in range(0, SW + 1, 8):
                self.cv.create_line(x * z, 0, x * z, SH * z, fill="#405060")
            for y in range(0, SH + 1, 8):
                self.cv.create_line(0, y * z, SW * z, y * z, fill="#405060")
        if self.grid12.get():
            for k in range(27):
                x = (4 + 12 * k) * z
                self.cv.create_line(x, 3 * z, x, 253 * z, fill="#606030")
            for k in range(26):
                y = (3 + 10 * k) * z
                self.cv.create_line(4 * z, y, 316 * z, y, fill="#606030")
        if self.frame.get():
            for k in (0, 2):
                self.cv.create_rectangle(k * z, k * z, (SW - k) * z, (SH - k) * z, outline="#b0b0b0")
        b = self.im.box()
        if b:
            x, y, w, h = b
            self.cv.create_rectangle(x * z, y * z, (x + w) * z, (y + h) * z, outline="#ff60ff", dash=(3, 3))
        self.cv.config(scrollregion=(0, 0, SW * z, SH * z))
        self.draw_sel()
        self.draw_paste()
        self.draw_lr()
        self.root.title(f"Z-Police screen editor: {os.path.basename(self.path)}" + (" *" if self.dirty else ""))

    def draw_sel(self):
        self.cv.delete("sel")
        if self.sel:
            z = self.z
            x0, y0, x1, y1 = self.sel
            for col, dash in (("black", ()), ("white", (4, 4))):
                self.cv.create_rectangle(x0 * z, y0 * z, (x1 + 1) * z, (y1 + 1) * z,
                                         outline=col, dash=dash, tags="sel")

    def paste_photo(self):
        """The copy as an image at the view's size: CLEAR pixels see-through
        (or the background, if they are pasted too)"""
        w, h, px = self.clip
        base = tk.PhotoImage(width=w, height=h)
        opaque = self.paste_clear.get()
        base.put(" ".join("{" + " ".join(imf.hexc(BG if px[y * w + x] == CLEAR else px[y * w + x])
                                         for x in range(w)) + "}" for y in range(h)))
        if not opaque:
            for k, v in enumerate(px):
                if v == CLEAR:
                    base.transparency_set(k % w, k // w, True)
        self.paste_img = base.zoom(self.z) if self.z > 1 else base

    def draw_paste(self):
        self.cv.delete("paste")
        if self.pasting is None:
            return
        self.paste_photo()
        z = self.z
        x, y = self.pasting
        w, h, _ = self.clip
        self.cv.create_image(x * z, y * z, anchor="nw", image=self.paste_img, tags="paste")
        self.cv.create_rectangle(x * z, y * z, (x + w) * z, (y + h) * z, outline="#ffff00",
                                 dash=(2, 2), tags="paste")

    def put_px(self, x, y):
        z = self.z
        self.photo.put(self.shown(x, y), to=(x * z, y * z, x * z + z, y * z + z))

    def draw_lr(self):
        self.lr.delete("all")
        for i, c in enumerate(self.cols):
            x = i * 8 * SW_Z
            fill = "#808080" if c == CLEAR else imf.hexc(c)
            self.lr.create_rectangle(x, 0, x + 8 * SW_Z - 4, 24, fill=fill, outline="white")
            self.lr.create_text(x + 4, 12, anchor="w", text=("CLEAR" if c == CLEAR else f"${c:02X}"),
                                fill="black" if c != CLEAR and sum(imf.rgb(c)) > 9 else "white")

    # --- input --------------------------------------------------------------
    def at(self, e):
        x = int(self.cv.canvasx(e.x)) // self.z
        y = int(self.cv.canvasy(e.y)) // self.z
        return x, y

    def hover(self, e):
        x, y = self.at(e)
        if self.pasting is not None and (x, y) != self.pasting:
            z = self.z
            dx, dy = (x - self.pasting[0]) * z, (y - self.pasting[1]) * z
            self.cv.move("paste", dx, dy)
            self.pasting = (x, y)
        if 0 <= x < SW and 0 <= y < SH:
            c = self.im.get(x, y)
            b = self.im.box()
            self.status.config(text=f"x {x}  y {y}\n8x8 cell: row {y // 8}, column {x // 8}\n"
                               + ("CLEAR" if c == CLEAR else f"colour ${c:02X}  r{imf.rgb(c)[0]} g{imf.rgb(c)[1]} b{c & 3}")
                               + (f"\nbox ({b[0]}, {b[1]}) {b[2]} x {b[3]}" if b else "\n(nothing drawn)"))

    def pick_pal(self, e, i):
        k = (e.y // SW_Z) * 16 + e.x // SW_Z
        if 0 <= k < 256:
            self.cols[i] = k
            self.draw_lr()

    def snapshot(self):
        self.undo.append(self.im.copy())
        del self.undo[:-50]

    def press(self, e, i):
        x, y = self.at(e)
        if not (0 <= x < SW and 0 <= y < SH):
            return
        if self.pasting is not None:    # pasting: left puts it down, right stops
            if i == 0:
                self.stamp(x, y)
            else:
                self.end_paste()
            return
        if e.state & 0x4:               # Ctrl: pick up the colour
            self.cols[0] = self.im.get(x, y)
            self.draw_lr()
            return
        t = self.tool.get()
        if t == "Select":
            self.drag = (x, y)
            return
        self.snapshot()
        if t == "Fill":
            self.im.fill(x, y, self.cols[i])
            self.changed(full=True)
        elif t == "Pencil":
            self.drag = (x, y)
            self.im.set(x, y, self.cols[i])
            self.put_px(x, y)
            self.dirty = True
        else:
            self.drag = (x, y)
            self.base = self.im.copy()

    def motion(self, e, i):
        if self.drag is None:
            return
        x, y = self.at(e)
        t = self.tool.get()
        if t == "Pencil":
            x0, y0 = self.drag
            tmp = imf.Image()
            tmp.line(x0, y0, x, y, 1)
            for k, v in enumerate(tmp.px):
                if v == 1:
                    self.im.px[k] = self.cols[i]
                    self.put_px(k % SW, k // SW)
            self.drag = (x, y)
        else:
            self.cv.delete("rubber")
            z = self.z
            x0, y0 = self.drag
            if t == "Select":
                self.cv.create_rectangle(min(x0, x) * z, min(y0, y) * z, (max(x0, x) + 1) * z,
                                         (max(y0, y) + 1) * z, outline="white", dash=(4, 4),
                                         tags="rubber")
            elif t == "Line":
                self.cv.create_line(x0 * z + z // 2, y0 * z + z // 2, x * z + z // 2, y * z + z // 2,
                                    fill="white", tags="rubber")
            elif "box" in t.lower():
                self.cv.create_rectangle(min(x0, x) * z, min(y0, y) * z, (max(x0, x) + 1) * z,
                                         (max(y0, y) + 1) * z, outline="white", tags="rubber")
            else:
                self.cv.create_oval(min(x0, x) * z, min(y0, y) * z, (max(x0, x) + 1) * z,
                                    (max(y0, y) + 1) * z, outline="white", tags="rubber")

    def release(self, e, i):
        if self.drag is None:
            return
        x, y = self.at(e)
        x, y = max(0, min(SW - 1, x)), max(0, min(SH - 1, y))
        x0, y0 = self.drag
        self.drag = None
        t, c = self.tool.get(), self.cols[i]
        if t == "Select":
            self.cv.delete("rubber")
            self.sel = (min(x0, x), min(y0, y), max(x0, x), max(y0, y))
            self.draw_sel()
            return
        if t == "Pencil":
            self.changed(full=True)
            return
        if t == "Line":
            self.im.line(x0, y0, x, y, c)
        elif t == "Box":
            self.im.rect(x0, y0, x, y, c)
        elif t == "Filled box":
            self.im.rect(x0, y0, x, y, c, filled=True)
        elif t == "Ellipse":
            self.im.ellipse(x0, y0, x, y, c)
        elif t == "Filled ellipse":
            self.im.ellipse(x0, y0, x, y, c, filled=True)
        self.changed(full=True)

    def changed(self, full=False):
        self.dirty = True
        if full:
            self.redraw()

    # --- copy and paste -----------------------------------------------------
    def copy(self):
        """The selection's pixels (CLEAR ones too) to the copy"""
        if not self.sel:
            self.root.bell()
            return
        x0, y0, x1, y1 = self.sel
        w, h = x1 - x0 + 1, y1 - y0 + 1
        self.clip = (w, h, bytes(self.im.get(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)))
        self.status.config(text=f"copied {w} x {h} from ({x0}, {y0})")

    def paste(self):
        """Pick the copy up: it follows the mouse until put away"""
        if self.clip is None:
            self.root.bell()
            return
        self.pasting = self.sel[:2] if self.sel else (0, 0)
        self.draw_paste()

    def paste_changed(self):
        if self.pasting is not None:
            self.draw_paste()

    def stamp(self, x, y):
        """The copy put down with its top-left at (x, y)"""
        w, h, px = self.clip
        self.snapshot()
        opaque = self.paste_clear.get()
        for j in range(h):
            for i in range(w):
                v = px[j * w + i]
                if v != CLEAR or opaque:
                    self.im.set(x + i, y + j, v)
        self.pasting = (x, y)
        self.changed(full=True)

    def end_paste(self):
        if self.pasting is not None:
            self.pasting = None
            self.cv.delete("paste")

    def escape(self):
        if self.pasting is not None:
            self.end_paste()
        else:
            self.sel = None
            self.draw_sel()

    # --- commands -----------------------------------------------------------
    def do_undo(self):
        if self.undo:
            self.im = self.undo.pop()
            self.changed(full=True)

    def clear_all(self):
        if messagebox.askyesno("Clear", "Clear the whole image?"):
            self.snapshot()
            self.im = imf.Image()
            self.changed(full=True)

    def move(self, dx, dy):
        self.snapshot()
        new = imf.Image()
        for y in range(SH):
            for x in range(SW):
                c = self.im.px[y * SW + x]
                if c != CLEAR:
                    new.set(x + dx, y + dy, c)
        self.im = new
        self.changed(full=True)

    def zoom(self, z):
        """Enlarge the view z times, the same part of the screen in its middle"""
        w, h = max(1, self.cv.winfo_width()), max(1, self.cv.winfo_height())
        cx = (self.cv.canvasx(w / 2)) / self.z      # the screen pixel in the middle
        cy = (self.cv.canvasy(h / 2)) / self.z
        self.z = z
        self.redraw()
        self.cv.xview_moveto(max(0.0, (cx * z - w / 2) / (SW * z)))
        self.cv.yview_moveto(max(0.0, (cy * z - h / 2) / (SH * z)))

    def load_under(self):
        p = filedialog.askopenfilename(title="Underlay (a 320x256 PNG)", filetypes=[("PNG", "*.png")])
        if not p:
            return
        try:
            ph = tk.PhotoImage(file=p)
        except tk.TclError as e:
            messagebox.showerror("Underlay", str(e))
            return
        if (ph.width(), ph.height()) != (SW, SH):
            messagebox.showerror("Underlay", f"{ph.width()} x {ph.height()}: not 320 x 256")
            return
        self.under = [["#%02x%02x%02x" % ph.get(x, y) for x in range(SW)] for y in range(SH)]
        self.redraw()

    def no_under(self):
        self.under = None
        self.redraw()

    def ok_to_leave(self):
        return not self.dirty or messagebox.askyesno("Image", "Leave without saving the changes?")

    def new(self):
        if self.ok_to_leave():
            self.im = imf.Image()
            self.undo.clear()
            self.dirty = False
            self.path = os.path.join(imf.DATA, "NEW.ZPI")
            self.sel = self.pasting = None
            self.redraw()

    def open(self):
        if not self.ok_to_leave():
            return
        p = filedialog.askopenfilename(initialdir=imf.DATA, filetypes=[("Screen images", "*.ZPI"), ("All", "*")])
        if not p:
            return
        try:
            self.im = imf.Image.load(p)
        except (OSError, ValueError) as e:
            messagebox.showerror("Open", str(e))
            return
        self.path = p
        self.undo.clear()
        self.dirty = False
        self.sel = self.pasting = None
        self.redraw()

    def save(self):
        try:
            self.im.save(self.path)
        except (OSError, ValueError) as e:
            messagebox.showerror("Save", str(e))
            return
        self.dirty = False
        self.redraw()

    def save_as(self):
        p = filedialog.asksaveasfilename(initialdir=imf.DATA, defaultextension=".ZPI",
                                         filetypes=[("Screen images", "*.ZPI")])
        if p:
            self.path = p
            self.save()

    def quit(self):
        if self.ok_to_leave():
            self.root.destroy()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(imf.DATA, "VTOL.ZPI")
    root = tk.Tk()
    Editor(root, path)
    root.mainloop()


if __name__ == "__main__":
    main()
