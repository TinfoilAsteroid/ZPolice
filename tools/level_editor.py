"""Z-Police level editor: every level's settings and monster waves
(levels/LEVELnn.TXL), in one window.

    python tools/level_editor.py

On the left, the levels (number, city name, waves, zombies a wave, fast
zombies, draw distance), each opening to its waves and their special
monsters.  Click a level or a wave to edit it on the right:

  Level      zombies a wave, waves, fast zombies, draw distance (the city
             and its map changes are the map editor's: tools/map_editor.py).
             Changing Waves adds empty waves at the end or drops the last.
  Wave       how many of each special monster (Ghost, Banshee, Ghoul, Lich,
             Devil, Clusters); wave 1 is the level's start.  Add wave (an
             empty one after it), Copy wave (a copy after it), Delete wave,
             Move up / down.

The level's problems (levelfile.level_check: the game's limits, e.g. at most
8 specials at once, the devil alone in the last wave) are listed under the
editor as you type; levels with any are marked "!" in the list, changed
ones "*".  File > Save (Ctrl+S) writes the changed levels that have no
problems; Revert level puts the selected one back as saved.  After saving,
build.bat makes ZPDATA/LEVELnn.ZPL from them.
"""
import glob
import os
import sys
import tkinter as tk
from tkinter import messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citymap as cm  # noqa: E402
import levelfile as lf  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL_DIR = os.path.join(ROOT, "levels")
MAP_DIR = os.path.join(ROOT, "maps")
NTYPES = len(lf.SPEC_NAMES)


def rel(p):
    try:
        return os.path.relpath(p, ROOT)
    except ValueError:                  # (another drive)
        return p


def wave_text(sp):
    """A wave's specials, e.g. "3 ghosts, 1 lich" ("zombies only" if none)."""
    if not sp:
        return "zombies only"
    out = []
    for t, n in sp:
        name = lf.SPEC_NAMES[t].lower()
        out.append(f"{n} {name if n == 1 or name.endswith('s') else name + 's'}")
    return ", ".join(out)


def set_count(sp, t, n):
    """A wave's (type, count) pairs with type t's count set to n, keeping the
    others' order (a new type goes at the end; 0 removes it)."""
    out, done = [], False
    for tt, nn in sp:
        if tt == t:
            if n and not done:
                out.append((t, n))
            done = True
        else:
            out.append((tt, nn))
    if not done and n:
        out.append((t, n))
    return out


def counts(sp):
    c = [0] * NTYPES
    for t, n in sp:
        c[t] += n
    return c


def load_cities(map_dir=MAP_DIR):
    """{city: (cells, families)} for level_check (no level's changes)."""
    out = {}
    for p in sorted(glob.glob(os.path.join(map_dir, "CITY*.json"))):
        try:
            m = cm.load(p)
        except (OSError, ValueError, KeyError):
            continue
        n = int(os.path.basename(p)[4:6])
        out[n] = (m["cells"], m["fams"])
    return out


class Level:
    def __init__(self, path):
        self.path = path
        self.d = lf.read(path)
        self.lv = self.d["lv"]
        self.dirty = False


class Editor:
    def __init__(self, root, level_dir=LEVEL_DIR, map_dir=MAP_DIR):
        self.root, self.level_dir = root, level_dir
        self.cities = load_cities(map_dir)
        self.levels = {}
        bad = []
        for p in sorted(glob.glob(os.path.join(level_dir, "LEVEL*.TXL"))):
            try:
                L = Level(p)
            except (OSError, ValueError) as e:
                bad.append(f"{rel(p)}: {e}")
                continue
            self.levels[L.lv] = L
        self.cur_lv, self.cur_wave = None, None
        self.loading = False
        self.build_ui()
        self.fill_tree()
        if bad:
            messagebox.showerror("Can't read", "Not shown (fix them by hand):\n\n" + "\n".join(bad))
        if self.levels:
            self.select(min(self.levels), 0)

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        r = self.root
        r.title("Z-Police level editor")
        r.geometry("980x640")
        mb = tk.Menu(r)
        fm = tk.Menu(mb, tearoff=0)
        fm.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        fm.add_command(label="Revert level", command=self.revert)
        fm.add_separator()
        fm.add_command(label="Quit", command=self.quit)
        mb.add_cascade(label="File", menu=fm)
        r.config(menu=mb)
        r.bind("<Control-s>", lambda e: self.save())
        r.protocol("WM_DELETE_WINDOW", self.quit)

        pw = tk.PanedWindow(r, orient=tk.HORIZONTAL, sashwidth=5)
        pw.pack(fill=tk.BOTH, expand=True)
        left = tk.Frame(pw)
        cols = ("waves", "zombies", "fast", "view")
        self.tree = ttk.Treeview(left, columns=cols, selectmode="browse")
        self.tree.heading("#0", text="Level / wave")
        self.tree.column("#0", width=330)
        for c, w in zip(cols, (50, 60, 40, 40)):
            self.tree.heading(c, text=c.title())
            self.tree.column(c, width=w, anchor=tk.CENTER)
        sb = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.bind("<<TreeviewSelect>>", self.on_select)
        pw.add(left, width=540)

        right = tk.Frame(pw, padx=10, pady=8)
        pw.add(right)
        self.title = tk.Label(right, font=("TkDefaultFont", 12, "bold"))
        self.title.pack(anchor=tk.W)

        lvf = tk.LabelFrame(right, text="Level", padx=8, pady=4)
        lvf.pack(anchor=tk.W, fill=tk.X, pady=4)
        self.v = {}
        specs = [("Zombies a wave", "ZOMBIES", 1, lf.NZOMB),
                 ("Waves", "WAVES", 1, lf.LV_MAX_WAVES),
                 ("Fast zombies", "FAST", 0, lf.NZOMB),
                 ("Draw distance (tiles)", "VIEW", 2, lf.VIEW_R)]
        for i, (label, k, lo, hi) in enumerate(specs):
            tk.Label(lvf, text=label).grid(row=i, column=0, sticky=tk.W)
            v = tk.StringVar()
            tk.Spinbox(lvf, from_=lo, to=hi, width=5, textvariable=v).grid(row=i, column=1, sticky=tk.W)
            v.trace_add("write", lambda *a, k=k: self.level_changed(k))
            self.v[k] = v
        tk.Label(lvf, text="(fewer tiles: night or fog)").grid(row=3, column=2, sticky=tk.W, padx=6)
        self.changes_lbl = tk.Label(lvf, fg="grey30")
        self.changes_lbl.grid(row=4, column=0, columnspan=3, sticky=tk.W)

        self.wvf = tk.LabelFrame(right, text="Wave", padx=8, pady=4)
        self.wvf.pack(anchor=tk.W, fill=tk.X, pady=4)
        self.wv = []
        for t, name in enumerate(lf.SPEC_NAMES):
            tk.Label(self.wvf, text=name.title()).grid(row=t, column=0, sticky=tk.W)
            v = tk.StringVar()
            tk.Spinbox(self.wvf, from_=0, to=lf.NSPEC, width=5, textvariable=v).grid(row=t, column=1,
                                                                                    sticky=tk.W)
            v.trace_add("write", lambda *a, t=t: self.wave_changed(t))
            self.wv.append(v)
        self.wave_sum = tk.Label(self.wvf, fg="grey30")
        self.wave_sum.grid(row=NTYPES, column=0, columnspan=3, sticky=tk.W)
        bf = tk.Frame(self.wvf)
        bf.grid(row=NTYPES + 1, column=0, columnspan=3, sticky=tk.W, pady=4)
        for text, cmd in (("Add wave", self.add_wave), ("Copy wave", self.copy_wave),
                          ("Delete wave", self.delete_wave), ("Move up", lambda: self.move_wave(-1)),
                          ("Move down", lambda: self.move_wave(1))):
            tk.Button(bf, text=text, command=cmd).pack(side=tk.LEFT, padx=(0, 4))

        tk.Label(right, text="Problems").pack(anchor=tk.W, pady=(8, 0))
        self.probs = tk.Text(right, height=8, width=60, wrap=tk.WORD, state=tk.DISABLED)
        self.probs.pack(anchor=tk.W, fill=tk.BOTH, expand=True)
        self.status = tk.Label(r, anchor=tk.W, relief=tk.SUNKEN, padx=4)
        self.status.pack(side=tk.BOTTOM, fill=tk.X)
        self.say(f"{len(self.levels)} levels from {rel(self.level_dir)}")

    def say(self, text):
        self.status.config(text=text)

    # ---------------------------------------------------------------- tree
    def errors(self, L):
        return lf.level_check(L.lv, L.d, self.cities)

    def level_label(self, L):
        mark = ("*" if L.dirty else "") + ("!" if self.errors(L) else "")
        return f"{mark} Level {L.lv:2d}  {L.d['name'].strip()}".strip()

    def fill_tree(self):
        self.tree.delete(*self.tree.get_children())
        for lv in sorted(self.levels):
            self.tree.insert("", tk.END, iid=f"L{lv}")
            self.refresh_level(lv)

    def refresh_level(self, lv):
        L = self.levels[lv]
        iid = f"L{lv}"
        zomb, waves, fast, view = L.d["values"]
        self.tree.item(iid, text=self.level_label(L), values=(waves, zomb, fast, view))
        kids = self.tree.get_children(iid)
        ws = L.d["waves_specials"]
        for w, sp in enumerate(ws):
            wid = f"L{lv}W{w}"
            text = f"Wave {w + 1}: {wave_text(sp)}"
            if w < len(kids):
                self.tree.item(wid, text=text)
            else:
                self.tree.insert(iid, tk.END, iid=wid, text=text)
        for wid in kids[len(ws):]:
            self.tree.delete(wid)

    def on_select(self, _e=None):
        sel = self.tree.selection()
        if not sel:
            return
        iid = sel[0]
        if "W" in iid:
            lv, w = iid[1:].split("W")
            self.show(int(lv), int(w))
        else:
            self.show(int(iid[1:]), 0)

    def select(self, lv, w):
        self.tree.item(f"L{lv}", open=True)
        wid = f"L{lv}W{w}"
        self.tree.selection_set(wid)
        self.tree.see(wid)
        self.show(lv, w)

    def show(self, lv, w):
        L = self.levels[lv]
        self.cur_lv, self.cur_wave = lv, min(w, len(L.d["waves_specials"]) - 1)
        self.loading = True
        for k, val in zip(lf.LEVEL_KEYS, L.d["values"]):
            self.v[k].set(str(val))
        self.loading = False
        self.title.config(text=f"Level {lv}: {L.d['name'].strip()} (city {L.d['cn']})"
                          + ("  - changed" if L.dirty else ""))
        self.changes_lbl.config(text=f"Map changes: {len(L.d['changes'])} (tools/map_editor.py)")
        self.show_wave()
        self.show_problems()

    def show_wave(self):
        L = self.levels[self.cur_lv]
        sp = L.d["waves_specials"][self.cur_wave]
        self.wvf.config(text=f"Wave {self.cur_wave + 1} of {len(L.d['waves_specials'])}"
                        + (" (the level's start)" if self.cur_wave == 0 else ""))
        self.loading = True
        for t, n in enumerate(counts(sp)):
            self.wv[t].set(str(n))
        self.loading = False
        self.wave_sum.config(text=wave_text(sp))

    def show_problems(self):
        errs = self.errors(self.levels[self.cur_lv])
        self.probs.config(state=tk.NORMAL)
        self.probs.delete("1.0", tk.END)
        self.probs.insert(tk.END, "\n".join("- " + e for e in errs) if errs else "None.")
        self.probs.config(state=tk.DISABLED, fg="red" if errs else "darkgreen")

    # --------------------------------------------------------------- edits
    def changed(self, structure=False):
        L = self.levels[self.cur_lv]
        L.dirty = True
        self.refresh_level(self.cur_lv)
        self.title.config(text=f"Level {L.lv}: {L.d['name'].strip()} (city {L.d['cn']})  - changed")
        self.show_problems()
        if structure:
            self.select(self.cur_lv, self.cur_wave)

    def level_changed(self, k):
        if self.loading or self.cur_lv is None:
            return
        try:
            n = int(self.v[k].get())
        except ValueError:
            return                      # (still typing)
        L = self.levels[self.cur_lv]
        i = lf.LEVEL_KEYS.index(k)
        if L.d["values"][i] == n:
            return
        if k == "WAVES":
            if not 1 <= n <= lf.LV_MAX_WAVES:
                return
            ws = L.d["waves_specials"]
            while len(ws) < n:
                ws.append([])
            del ws[n:]
            self.cur_wave = min(self.cur_wave, n - 1)
        L.d["values"][i] = n
        self.changed(structure=(k == "WAVES"))

    def wave_changed(self, t):
        if self.loading or self.cur_lv is None:
            return
        try:
            n = int(self.wv[t].get())
        except ValueError:
            return
        if not 0 <= n <= 255:
            return
        ws = self.levels[self.cur_lv].d["waves_specials"]
        sp = ws[self.cur_wave]
        if counts(sp)[t] == n:
            return
        ws[self.cur_wave] = set_count(sp, t, n)
        self.wave_sum.config(text=wave_text(ws[self.cur_wave]))
        self.changed()

    def set_waves(self, ws, w):
        L = self.levels[self.cur_lv]
        L.d["waves_specials"] = ws
        L.d["values"][1] = len(ws)
        self.cur_wave = w
        self.loading = True
        self.v["WAVES"].set(str(len(ws)))
        self.loading = False
        self.changed(structure=True)

    def add_wave(self, copy=False):
        ws = self.levels[self.cur_lv].d["waves_specials"]
        if len(ws) >= lf.LV_MAX_WAVES:
            return self.say(f"at most {lf.LV_MAX_WAVES} waves a level")
        new = list(ws[self.cur_wave]) if copy else []
        self.set_waves(ws[:self.cur_wave + 1] + [new] + ws[self.cur_wave + 1:], self.cur_wave + 1)

    def copy_wave(self):
        self.add_wave(copy=True)

    def delete_wave(self):
        ws = self.levels[self.cur_lv].d["waves_specials"]
        if len(ws) <= 1:
            return self.say("a level has at least one wave")
        w = self.cur_wave
        self.set_waves(ws[:w] + ws[w + 1:], min(w, len(ws) - 2))

    def move_wave(self, d):
        ws = list(self.levels[self.cur_lv].d["waves_specials"])
        w, w2 = self.cur_wave, self.cur_wave + d
        if not 0 <= w2 < len(ws):
            return
        ws[w], ws[w2] = ws[w2], ws[w]
        self.set_waves(ws, w2)

    # ----------------------------------------------------------- save etc.
    def save(self):
        dirty = [L for L in self.levels.values() if L.dirty]
        if not dirty:
            return self.say("nothing changed")
        saved, held = [], []
        for L in sorted(dirty, key=lambda L: L.lv):
            if self.errors(L):
                held.append(L.lv)
                continue
            try:
                lf.write(L.path, L.d)
            except OSError as e:
                messagebox.showerror("Can't save", f"{rel(L.path)}: {e}")
                held.append(L.lv)
                continue
            L.dirty = False
            saved.append(L.lv)
            self.refresh_level(L.lv)
        if self.cur_lv is not None:
            self.show(self.cur_lv, self.cur_wave)
        msg = f"saved level(s) {', '.join(map(str, saved))}" if saved else "nothing saved"
        if held:
            msg += f"; not saved, with problems: {', '.join(map(str, held))}"
            messagebox.showwarning("Not saved", f"Levels {', '.join(map(str, held))} have problems "
                                   "(marked !): fix them, then save again.")
        self.say(msg + (" (build.bat puts them in the game)" if saved else ""))
        return not held

    def revert(self):
        if self.cur_lv is None:
            return
        L = self.levels[self.cur_lv]
        try:
            self.levels[L.lv] = Level(L.path)
        except (OSError, ValueError) as e:
            return messagebox.showerror("Can't read", str(e))
        self.refresh_level(L.lv)
        self.select(L.lv, 0)
        self.say(f"level {L.lv} as saved")

    def quit(self):
        dirty = sorted(L.lv for L in self.levels.values() if L.dirty)
        if dirty:
            a = messagebox.askyesnocancel("Unsaved changes", f"Levels {', '.join(map(str, dirty))} "
                                          "have changed. Save them first?")
            if a is None or (a and not self.save()):
                return
        self.root.destroy()


def main():
    root = tk.Tk()
    Editor(root)
    root.mainloop()


if __name__ == "__main__":
    main()
