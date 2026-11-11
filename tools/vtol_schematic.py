"""The load-out screen's VTOL: a schematic of its underside, the weapon slots'
hardpoints marked, drawn into ZPDATA/VTOL.ZPI (tools/imagefile.py has the
format; tools/screen_editor.py edits it after).

    python tools/vtol_schematic.py

Seen from below with the nose up, drawn as the HUD shows the slots (the
pilot's left on the left): the centre gun (slot 1) under the fuselage, and a
pod under each wing for slots 4 and 5 (the inner pair, the linked chain
guns') and 2 and 3 (the outer pair).  The game draws a box round each
hardpoint and its slot number (the selected slot yellow): HARDPOINTS,
LABELS and BOXES here and lo_hp (loadout.asm) must agree (test_l320.py
checks them).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imagefile as imf  # noqa: E402

PATH = os.path.join(imf.DATA, "VTOL.ZPI")
CX = 240                                # the centre line

# slot (key) -> (x, y) of its hardpoint, of its number's top-left, and the
# (width, height) of the game's box round it (centred on the hardpoint)
HARDPOINTS = {1: (CX, 62), 2: (220, 89), 3: (260, 89), 4: (226, 89), 5: (254, 89)}
LABELS = {1: (238, 34), 2: (212, 108), 3: (261, 108), 4: (222, 64), 5: (252, 64)}
BOXES = {1: (17, 17), 2: (6, 24), 3: (6, 24), 4: (6, 24), 5: (6, 24)}

OUT = 0xBF                              # outlines: light cyan
FILL = 0x01                             # inside: darker than the screen
DETAIL = 0x6E                           # panel lines: grey-blue
MARK = 0x49                             # the hardpoints


def mirror(pts):
    return [(2 * CX - x, y) for x, y in pts]


def shape(im, pts, both=True):
    for p in ([pts, mirror(pts)] if both else [pts]):
        im.polygon(p, FILL, filled=True)
        im.polygon(p, OUT)


def draw():
    im = imf.Image()
    shape(im, [(232, 74), (174, 86), (174, 98), (232, 100)])            # wings
    shape(im, [(234, 118), (212, 126), (212, 131), (234, 129)])         # tailplanes
    shape(im, [(170, 70), (178, 70), (181, 74), (181, 110), (178, 113),  # engine
               (170, 113), (167, 110), (167, 74)])                       # nacelles
    for x in (174, 2 * CX - 174):
        im.ellipse(x - 4, 76, x + 4, 84, DETAIL)                          # their fans
        im.line(x - 3, 104, x + 3, 104, DETAIL)
    shape(im, [(CX, 36), (CX + 6, 42), (CX + 10, 52), (CX + 10, 118), (CX + 6, 130),
               (CX - 6, 130), (CX - 10, 118), (CX - 10, 52), (CX - 6, 42)], both=False)
    for y in (58, 116):                                                   # panel lines
        im.line(CX - 9, y, CX + 9, y, DETAIL)
    im.rect(CX - 4, 64, CX + 4, 82, DETAIL)                               # gear doors
    im.line(CX, 64, CX, 82, DETAIL)
    for slot, (x, y) in HARDPOINTS.items():
        if slot == 1:                                                     # the gun turret
            im.ellipse(x - 5, y - 5, x + 5, y + 5, FILL, filled=True)
            im.ellipse(x - 5, y - 5, x + 5, y + 5, OUT)
            im.line(x, y - 6, x, y - 13, OUT)
        else:                                                             # a wing pod
            pod = [(x, y - 12), (x + 3, y - 8), (x + 3, y + 8), (x + 1, y + 10),
                   (x - 1, y + 10), (x - 3, y + 8), (x - 3, y - 8)]
            im.polygon(pod, FILL, filled=True)
            im.polygon(pod, OUT)
        im.rect(x - 1, y - 1, x + 1, y + 1, MARK, filled=True)
    return im


if __name__ == "__main__":
    im = draw()
    im.save(PATH)
    print("wrote", PATH, "box", im.box())
