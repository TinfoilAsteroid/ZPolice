"""Z-Police font editor: the screens' fonts (tools/fontfile.py has the
format), loaded by the game at start-up:
  ZPDATA/FONT8.ZPF   the 8x8 font: every text screen (the ULA ones and the
                     HUD in one colour, the 320x256 ones in its gradients)
  ZPDATA/FONT12.ZPF  the large font (12x10 cells): the 320x256 screens'
                     titles, help and messages

    python tools/font_editor.py [8 | 12 | file]       (the large font: none)

File > Edit the 8x8 font / Edit the large font switches between them.

On the left the characters (lower case is drawn as upper case).  In the
middle the selected character's cell, enlarged: the shaded column(s) and row
are the gap to the next character and line (the 8x8 font: the top row and
last column), so leave them clear unless the glyph should touch its
neighbour.  On the right the gradients: each text colour the screens print
in (its base colour) is drawn as a ramp, one colour for each row of the
cell, top first (the ULA draws the 8x8 font in one colour: its gradients are
for the 320x256 screens).  Below, a preview of every character and a sample
line in each gradient, at twice the game's size, on the screens'
background.

    Left button     ink                         Right button   clear
    Ctrl+Z          undo                        Ctrl+S         save
    Ctrl+C / Ctrl+V copy / paste a character    arrow keys     move the glyph

Gradients: click a row's swatch to set its colour (r, g 0-7, b 0-3: the
screens' RRRGGGBB colours).  Ramp from base makes a new ramp from the base
colour; Add and Delete add a gradient for another base colour (at most 8) or
remove one.  Text printed in a colour with no gradient is drawn flat.
"""
import copy
import os
import sys
import tkinter as tk
from tkinter import messagebox, simpledialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fontfile as ff  # noqa: E402

PZ = 2                                  # the preview's pixel
BG = 0x02                               # the screens' background (SCR_BG)
SAMPLE = "Z-POLICE 0123456789: PRESS SPACE"


def hexc(c):
    r, g, b = ff.rgb(c)
    return "#%02x%02x%02x" % (r * 255 // 7, g * 255 // 7, b * 255 // 7)


class Editor:
    def __init__(self, root, spec, path=None):
        self.root = root
        self.open(spec, path)

    def open(self, spec, path=None):
        """Edit a font: spec (ff.F8, ff.F12), from path (its file)"""
        self.spec, self.path = spec, path or spec.PATH
        self.z = 36 if spec.W <= 8 else 28      # an enlarged pixel
        if os.path.exists(self.path):
            try:
                self.font = ff.Font.load(self.path, spec)
            except ValueError as e:
                messagebox.showwarning("Font", f"{self.path}: {e}\nStarting from the default design.")
                self.font = ff.Font.default(spec)
        else:
            self.font = ff.Font.default(spec)
        self.ch = "A"
        self.gi = 0
        self.undo = []
        self.clip = None
        self.dirty = False
        self.paint = None
        for w in self.root.winfo_children():
            w.destroy()
        self.build()
        self.refresh()

    def switch(self, spec):
        if spec is self.spec:
            return
        if self.dirty and not messagebox.askyesno("Font", "Leave this font without saving the changes?"):
            return
        self.open(spec)

    # --- layout -------------------------------------------------------------
    def build(self):
        r = self.root
        menu = tk.Menu(r)
        fm = tk.Menu(menu, tearoff=0)
        fm.add_command(label="Edit the 8x8 font", command=lambda: self.switch(ff.F8))
        fm.add_command(label="Edit the large font (12x10)", command=lambda: self.switch(ff.F12))
        fm.add_separator()
        fm.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        fm.add_command(label="Revert to the file", command=self.revert)
        fm.add_command(label="Reset to the default design", command=self.reset)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.quit)
        menu.add_cascade(label="File", menu=fm)
        em = tk.Menu(menu, tearoff=0)
        em.add_command(label="Undo", accelerator="Ctrl+Z", command=self.do_undo)
        em.add_command(label="Copy character", accelerator="Ctrl+C", command=self.copy)
        em.add_command(label="Paste character", accelerator="Ctrl+V", command=self.paste)
        em.add_command(label="Clear character", command=self.clear)
        em.add_command(label="Character back to the default design", command=self.default_char)
        menu.add_cascade(label="Edit", menu=em)
        r.config(menu=menu)

        top = tk.Frame(r)
        top.pack(side="top", fill="both")
        chars = tk.Frame(top)
        chars.pack(side="left", padx=6, pady=6, anchor="n")
        self.cbtn = {}
        for i in range(self.spec.COUNT):
            c = chr(self.spec.FIRST + i)
            b = tk.Button(chars, text=c if c != " " else "SP", width=3,
                          command=lambda c=c: self.select(c))
            b.grid(row=i // 6, column=i % 6)
            self.cbtn[c] = b

        mid = tk.Frame(top)
        mid.pack(side="left", padx=6, pady=6, anchor="n")
        self.title = tk.Label(mid, font=("TkDefaultFont", 12, "bold"))
        self.title.pack()
        self.grid = tk.Canvas(mid, width=self.spec.W * self.z + 1, height=self.spec.H * self.z + 1, bg="#202020",
                              highlightthickness=0)
        self.grid.pack()
        for ev in ("<Button-1>", "<B1-Motion>"):
            self.grid.bind(ev, lambda e: self.click(e, True))
        for ev in ("<Button-3>", "<B3-Motion>"):
            self.grid.bind(ev, lambda e: self.click(e, False))
        self.grid.bind("<ButtonRelease-1>", lambda e: self.release())
        self.grid.bind("<ButtonRelease-3>", lambda e: self.release())
        mv = tk.Frame(mid)
        mv.pack(pady=4)
        for t, d in (("Left", (-1, 0)), ("Right", (1, 0)), ("Up", (0, -1)), ("Down", (0, 1))):
            tk.Button(mv, text=t, command=lambda d=d: self.move(*d)).pack(side="left")

        right = tk.Frame(top)
        right.pack(side="left", padx=6, pady=6, anchor="n")
        tk.Label(right, text="Gradients (base colour)").pack(anchor="w")
        self.glist = tk.Listbox(right, height=ff.GRAD_MAX, exportselection=False, width=22)
        self.glist.pack(anchor="w")
        self.glist.bind("<<ListboxSelect>>", lambda e: self.pick_grad())
        gb = tk.Frame(right)
        gb.pack(anchor="w", pady=2)
        tk.Button(gb, text="Add", command=self.add_grad).pack(side="left")
        tk.Button(gb, text="Delete", command=self.del_grad).pack(side="left")
        tk.Button(gb, text="Base colour", command=self.set_base).pack(side="left")
        tk.Button(gb, text="Ramp from base", command=self.reramp).pack(side="left")
        tk.Label(right, text="Rows (click to set)").pack(anchor="w", pady=(6, 0))
        self.rows = tk.Canvas(right, width=200, height=self.spec.H * 20, highlightthickness=0)
        self.rows.pack(anchor="w")
        self.rows.bind("<Button-1>", self.click_row)

        self.prev = tk.Canvas(r, height=10, bg=hexc(BG), highlightthickness=0)
        self.prev.pack(side="top", fill="x", padx=6, pady=6)
        self.status = tk.Label(r, anchor="w")
        self.status.pack(side="bottom", fill="x")

        r.bind("<Control-s>", lambda e: self.save())
        r.bind("<Control-z>", lambda e: self.do_undo())
        r.bind("<Control-c>", lambda e: self.copy())
        r.bind("<Control-v>", lambda e: self.paste())
        for k, d in (("Left", (-1, 0)), ("Right", (1, 0)), ("Up", (0, -1)), ("Down", (0, 1))):
            r.bind(f"<{k}>", lambda e, d=d: self.move(*d))
        r.protocol("WM_DELETE_WINDOW", self.quit)

    # --- drawing ------------------------------------------------------------
    def grad_for(self, i):
        return self.font.grads[i][1] if self.font.grads else [0xFF] * self.spec.H

    def refresh(self):
        self.title.config(text=f"'{self.ch}'  (ASCII {ord(self.ch)})")
        for c, b in self.cbtn.items():
            b.config(relief="sunken" if c == self.ch else "raised")
        g = self.grid
        g.delete("all")
        cols = self.grad_for(self.gi)
        rows = self.font.glyphs[self.ch]
        for y in range(self.spec.H):
            for x in range(self.spec.W):
                if self.spec.W <= 8:        # 8x8: row 0, column 7
                    gap = x == self.spec.W - 1 or y == 0
                else:                       # large: the last 2 columns, last row
                    gap = x >= self.spec.W - 2 or y == self.spec.H - 1
                fill = hexc(cols[y]) if rows[y][x] else ("#3a3a48" if gap else hexc(BG))
                g.create_rectangle(x * self.z, y * self.z, x * self.z + self.z, y * self.z + self.z, fill=fill, outline="#555")
        self.glist.delete(0, "end")
        for base, _ in self.font.grads:
            self.glist.insert("end", f"${base:02X}  r{ff.rgb(base)[0]} g{ff.rgb(base)[1]} b{base & 3}")
        if self.font.grads:
            self.glist.selection_set(self.gi)
        self.rows.delete("all")
        for y, c in enumerate(cols):
            self.rows.create_rectangle(0, y * 20, 60, y * 20 + 18, fill=hexc(c), outline="#888")
            r_, g_, _ = ff.rgb(c)
            self.rows.create_text(70, y * 20 + 9, anchor="w", text=f"row {y}: ${c:02X}  r{r_} g{g_} b{c & 3}")
        self.draw_preview()
        self.status.config(text=self.path + ("  (changed)" if self.dirty else ""))
        self.root.title(f"Z-Police font editor: the {self.spec.label}" + (" *" if self.dirty else ""))

    def text(self, cv, s, x, y, cols):
        for ch in s:
            ch = ch.upper()
            rows = self.font.glyphs.get(ch, self.font.glyphs[" "])
            for yy in range(self.spec.H):
                for xx in range(self.spec.W):
                    if rows[yy][xx]:
                        cv.create_rectangle(x + xx * PZ, y + yy * PZ, x + xx * PZ + PZ - 1,
                                            y + yy * PZ + PZ - 1, fill=hexc(cols[yy]), width=0)
            x += self.spec.W * PZ

    def draw_preview(self):
        cv = self.prev
        cv.delete("all")
        y = 6
        allc = "".join(chr(self.spec.FIRST + i) for i in range(self.spec.COUNT))
        for k in range(0, len(allc), 32):
            self.text(cv, allc[k:k + 32], 6, y, self.grad_for(self.gi))
            y += self.spec.H * PZ + 4
        for i in range(len(self.font.grads)):
            self.text(cv, SAMPLE, 6, y, self.grad_for(i))
            y += self.spec.H * PZ + 4
        cv.config(height=y + 4, width=max(6 + 32 * self.spec.W * PZ, 900))

    # --- glyph editing ------------------------------------------------------
    def snapshot(self):
        self.undo.append(copy.deepcopy((self.font.glyphs, self.font.grads)))
        del self.undo[:-100]

    def changed(self):
        self.dirty = True
        self.refresh()

    def select(self, c):
        self.ch = c
        self.refresh()

    def click(self, e, on):
        x, y = e.x // self.z, e.y // self.z
        if not (0 <= x < self.spec.W and 0 <= y < self.spec.H):
            return
        if self.paint is None:
            self.snapshot()
            self.paint = True
        if self.font.glyphs[self.ch][y][x] != on:
            self.font.glyphs[self.ch][y][x] = on
            self.changed()

    def release(self):
        self.paint = None

    def move(self, dx, dy):
        self.snapshot()
        old = self.font.glyphs[self.ch]
        new = [[False] * self.spec.W for _ in range(self.spec.H)]
        for y in range(self.spec.H):
            for x in range(self.spec.W):
                if old[y][x] and 0 <= x + dx < self.spec.W and 0 <= y + dy < self.spec.H:
                    new[y + dy][x + dx] = True
        self.font.glyphs[self.ch] = new
        self.changed()

    def clear(self):
        self.snapshot()
        self.font.glyphs[self.ch] = [[False] * self.spec.W for _ in range(self.spec.H)]
        self.changed()

    def default_char(self):
        self.snapshot()
        self.font.glyphs[self.ch] = copy.deepcopy(ff.Font.default(self.spec).glyphs[self.ch])
        self.changed()

    def copy(self):
        self.clip = copy.deepcopy(self.font.glyphs[self.ch])

    def paste(self):
        if self.clip is not None:
            self.snapshot()
            self.font.glyphs[self.ch] = copy.deepcopy(self.clip)
            self.changed()

    def do_undo(self):
        if self.undo:
            self.font.glyphs, self.font.grads = self.undo.pop()
            self.gi = min(self.gi, max(0, len(self.font.grads) - 1))
            self.changed()

    # --- gradients ----------------------------------------------------------
    def pick_grad(self):
        s = self.glist.curselection()
        if s:
            self.gi = s[0]
            self.refresh()

    def ask_colour(self, title, c):
        r, g, b = ff.rgb(c)
        s = simpledialog.askstring(title, "r g b  (r, g 0-7; b 0-3)", initialvalue=f"{r} {g} {c & 3}",
                                   parent=self.root)
        if not s:
            return None
        try:
            r, g, b = (int(v) for v in s.split())
        except ValueError:
            messagebox.showerror(title, "three numbers: r g b")
            return None
        if not (0 <= r <= 7 and 0 <= g <= 7 and 0 <= b <= 3):
            messagebox.showerror(title, "r and g 0-7, b 0-3")
            return None
        c = r << 5 | g << 2 | b
        if c == 0xE3:
            messagebox.showerror(title, "$E3 is the transparency colour: never drawn")
            return None
        return c

    def click_row(self, e):
        y = e.y // 20
        if not self.font.grads or not 0 <= y < self.spec.H:
            return
        c = self.ask_colour(f"Row {y}", self.font.grads[self.gi][1][y])
        if c is not None:
            self.snapshot()
            self.font.grads[self.gi][1][y] = c
            self.changed()

    def add_grad(self):
        if len(self.font.grads) >= ff.GRAD_MAX:
            messagebox.showinfo("Gradients", f"at most {ff.GRAD_MAX}")
            return
        c = self.ask_colour("Base colour of the new gradient", 0xFF)
        if c is None:
            return
        if any(b == c for b, _ in self.font.grads):
            messagebox.showinfo("Gradients", f"${c:02X} has one already")
            return
        self.snapshot()
        self.font.grads.append([c, ff.ramp(c, self.spec.H)])
        self.gi = len(self.font.grads) - 1
        self.changed()

    def del_grad(self):
        if len(self.font.grads) <= 1:
            messagebox.showinfo("Gradients", "the font needs one at least")
            return
        self.snapshot()
        del self.font.grads[self.gi]
        self.gi = max(0, self.gi - 1)
        self.changed()

    def set_base(self):
        if not self.font.grads:
            return
        c = self.ask_colour("Base colour (the text colour it is for)", self.font.grads[self.gi][0])
        if c is not None:
            self.snapshot()
            self.font.grads[self.gi][0] = c
            self.changed()

    def reramp(self):
        if self.font.grads:
            self.snapshot()
            self.font.grads[self.gi][1] = ff.ramp(self.font.grads[self.gi][0], self.spec.H)
            self.changed()

    # --- file ---------------------------------------------------------------
    def save(self):
        try:
            self.font.save(self.path)
        except (OSError, ValueError) as e:
            messagebox.showerror("Save", str(e))
            return
        self.dirty = False
        self.refresh()

    def revert(self):
        if os.path.exists(self.path) and messagebox.askyesno("Revert", "Forget the changes since the last save?"):
            self.font = ff.Font.load(self.path, self.spec)
            self.undo.clear()
            self.dirty = False
            self.gi = 0
            self.refresh()

    def reset(self):
        if messagebox.askyesno("Reset", "Every character and gradient back to the default design?"):
            self.snapshot()
            d = ff.Font.default(self.spec)
            self.font.glyphs, self.font.grads = d.glyphs, d.grads
            self.gi = 0
            self.changed()

    def quit(self):
        if self.dirty and not messagebox.askyesno("Quit", "Quit without saving the changes?"):
            return
        self.root.destroy()


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "12"
    root = tk.Tk()
    if arg in ("8", "12"):
        Editor(root, ff.F8 if arg == "8" else ff.F12)
    else:
        with open(arg, "rb") as fh:
            spec = ff.spec_of(fh.read())
        Editor(root, spec, arg)
    root.mainloop()


if __name__ == "__main__":
    main()
