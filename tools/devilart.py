"""The final boss's starting art: the devil (Quatermass's horned Martian, as
the giant apparition over London: a locust's head, great swept horns, its
eyes on the sides of its head, ghostly white with blue tints), on legs,
DEVIL_W x DEVIL_SRC_H pixels a frame,
drawn from shapes.  gengraphics.py writes it to sprites/devil.json when that
is missing; from then on that file is the devil (edit it by hand or with
the sprite editor's format: tools/spritefile.py has it).

Colours (the figure palette's numbers, drawn in the devil's own palette
entries: spritefile.DEVIL_COLOURS, black in thermal): white, pale blue
shading and horns, blue ribs and feet, a dark blue outline and mouth, and
its eyes DEVIL_EYE_COLOUR (the game's own glowing entry).
"""
import math

import spritefile as sf

W, H = sf.DEVIL_W, sf.DEVIL_SRC_H
BODY, SHADE, DARK, OUTLINE = 2, 21, 12, 13     # white, pale blue, blue, dark blue
HORN, TIP, BONE, MAW = 21, 2, 2, 13
EYE = sf.DEVIL_EYE_COLOUR


class Canvas:
    def __init__(self):
        self.px = [[0] * W for _ in range(H)]

    def put(self, x, y, c):
        # (rounded away from the middle, 31.5: both sides mirror exactly)
        x = math.floor(x + 0.5) if x <= (W - 1) / 2 else math.ceil(x - 0.5)
        y = math.floor(y + 0.5)
        if 0 <= x < W and 0 <= y < H:
            self.px[y][x] = c

    def disc(self, cx, cy, r, c):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.25:
                    self.put(x, y, c)

    def line(self, pts, r0, r1, c):
        """A thick polyline, its radius r0 at the start to r1 at the end."""
        segs = list(zip(pts, pts[1:]))
        total = sum(math.dist(a, b) for a, b in segs) or 1
        done = 0
        for (x0, y0), (x1, y1) in segs:
            n = max(1, int(math.dist((x0, y0), (x1, y1)) * 2))
            for k in range(n + 1):
                t = k / n
                d = (done + t * math.dist((x0, y0), (x1, y1))) / total
                self.disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r0 + (r1 - r0) * d, c)
            done += math.dist((x0, y0), (x1, y1))

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, c)

    def poly(self, pts, c):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(math.ceil(a)), int(math.floor(b)) + 1):
                    self.put(x, y, c)

    def shade_left(self, c_from, c_to, frac=0.3):
        """The left part of each run of c_from pixels in shadow (c_to)."""
        for row in self.px:
            x = 0
            while x < W:
                if row[x] == c_from:
                    e = x
                    while e < W and row[e] == c_from:
                        e += 1
                    for k in range(x, x + max(1, int((e - x) * frac))):
                        row[k] = c_to
                    x = e
                else:
                    x += 1

    def outline(self):
        """Black round the outside: a transparent pixel next to the figure."""
        src = [r[:] for r in self.px]
        for y in range(H):
            for x in range(W):
                if src[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < W and 0 <= yy < H and src[yy][xx] not in (0, OUTLINE):
                        self.px[y][x] = OUTLINE
                        break

    def mirrored(self):
        out = Canvas()
        out.px = [list(reversed(r)) for r in self.px]
        return out


def legs_front(cv, lift_l, lift_r):
    """Two digitigrade legs, front on: a lifted foot is higher, its knee
    out further."""
    for side, lift in ((-1, lift_l), (1, lift_r)):
        hip = (31.5 + side * 5, 76)
        knee = (31.5 + side * (11 + lift / 3), 98 - lift / 2)
        ankle = (31.5 + side * 7, 118 - lift)
        cv.line([hip, knee], 4.0, 3.2, BODY)
        cv.line([knee, ankle], 3.0, 2.0, BODY)
        cv.disc(knee[0], knee[1], 2.4, SHADE)
        foot_y = 127 - lift
        cv.poly([(ankle[0] - 3, ankle[1]), (ankle[0] + 3, ankle[1]),
                 (ankle[0] + 4, foot_y), (ankle[0] - 4, foot_y)], DARK)


def arms_front(cv, swing):
    for side in (-1, 1):
        s = swing * side
        shoulder = (31.5 + side * 15, 39)
        elbow = (31.5 + side * 21, 58 + s)
        wrist = (31.5 + side * 19, 77 + 2 * s)
        cv.line([shoulder, elbow], 3.2, 2.6, BODY)
        cv.line([elbow, wrist], 2.6, 2.0, BODY)
        cv.disc(elbow[0], elbow[1], 2.0, SHADE)
        for k in (-2, 0, 2):            # three claws
            cv.line([(wrist[0] + k, wrist[1] + 1), (wrist[0] + k * 1.6, wrist[1] + 9)], 0.9, 0.4, BONE)


def horns_front(cv):
    """The Martian's great horns: thick at the head's crown, sweeping out
    and up to fine points, a second, smaller pair inside them"""
    for side in (-1, 1):
        base = (31.5 + side * 6, 13)
        cv.line([base, (31.5 + side * 13, 9), (31.5 + side * 19, 4), (31.5 + side * 21, 0)],
                3.2, 0.6, HORN)
        cv.put(31.5 + side * 21, 0, TIP)
        cv.line([(31.5 + side * 3, 12), (31.5 + side * 7, 5), (31.5 + side * 8, 1)],
                1.6, 0.5, HORN)


def torso_front(cv):
    cv.line([(31.5, 30), (31.5, 37)], 3.0, 3.5, SHADE)   # the neck
    cv.poly([(15, 35), (48, 35), (51, 41), (44, 56), (40, 70), (23, 70), (19, 56), (12, 41)], BODY)
    for side in (-1, 1):                                  # shoulder spikes
        cv.line([(31.5 + side * 13, 36), (31.5 + side * 18, 29)], 1.5, 0.4, HORN)
    for y in range(41, 67, 4):                            # the ribs
        half = 14 - (y - 41) * 0.28
        for x in range(int(31.5 - half) + 1, int(31.5 + half)):
            if abs(x - 31.5) > 1.5:
                cv.put(x, y, DARK)
    cv.line([(31.5, 38), (31.5, 68)], 0.7, 0.7, SHADE)   # the breastbone
    cv.poly([(23, 69), (40, 69), (42, 77), (21, 77)], SHADE)  # the hips


def head_front(cv, face=True):
    """A locust's head: broad at the crown, its great eyes bulging on its
    sides, a ridge down its face to a small mouth between mandibles"""
    cv.ellipse(31.5, 21, 11, 11, BODY)
    cv.poly([(23, 24), (40, 24), (35, 37), (28, 37)], BODY)  # narrowing to the jaw
    if not face:
        cv.ellipse(31.5, 21, 7, 8, SHADE)
        cv.line([(31.5, 12), (31.5, 34)], 0.8, 0.8, DARK)
        return
    for side in (-1, 1):                                  # the eyes, on its sides
        cv.ellipse(31.5 + side * 7.5, 20, 3.4, 5, EYE)
    cv.line([(31.5, 12), (31.5, 31)], 1.2, 0.8, SHADE)   # the ridge down its face
    for side in (-1, 1):                                  # shadowed cheeks
        cv.line([(31.5 + side * 4, 27), (31.5 + side * 3, 34)], 0.8, 0.6, SHADE)
    cv.poly([(29.5, 33), (33.5, 33), (32.5, 36), (30.5, 36)], MAW)   # the mouth
    for side in (-1, 1):                                  # mandibles
        cv.line([(31.5 + side * 3, 35), (31.5 + side * 4, 39)], 1.0, 0.5, DARK)


def front(frame):
    cv = Canvas()
    lift = (6, 0) if frame == 0 else (0, 6)
    legs_front(cv, *lift)
    torso_front(cv)
    arms_front(cv, 2 if frame == 0 else -2)
    horns_front(cv)
    head_front(cv)
    cv.shade_left(BODY, SHADE, 0.28)
    cv.outline()
    return cv


def rear(frame):
    cv = Canvas()
    lift = (6, 0) if frame == 0 else (0, 6)
    sway = 3 if frame == 0 else -3
    cv.line([(31.5, 74), (31.5 + sway, 90), (31.5 - sway, 104), (31.5, 112)], 2.2, 0.8, SHADE)  # tail
    cv.poly([(29.5, 112), (33.5, 112), (31.5, 117)], DARK)
    legs_front(cv, *lift)
    torso_front(cv)
    arms_front(cv, -2 if frame == 0 else 2)
    horns_front(cv)
    head_front(cv, face=False)
    for y in range(37, 70, 5):                            # spines down the back
        cv.line([(31.5, y + 3), (31.5, y)], 1.3, 0.4, HORN)
    cv.shade_left(BODY, SHADE, 0.5)
    cv.outline()
    return cv.mirrored()


def side(frame):
    """Side on, facing left (the game mirrors it for right)."""
    cv = Canvas()
    stride = 7 if frame == 0 else -7
    tail = [(38, 72), (47, 82), (53, 97), (51, 110), (55, 116)]
    cv.line(tail, 2.4, 0.7, SHADE)
    for k, (st, col) in enumerate(((-stride, SHADE), (stride, BODY))):  # far leg, then near
        hip = (33, 74)
        knee = (28 - st * 0.6, 97)
        ankle = (35 - st * 0.3, 117 - (4 if (k == 0) == (frame == 0) else 0))
        toe_y = ankle[1] + 10
        cv.line([hip, knee], 4.2 if k else 3.6, 3.0, col)
        cv.line([knee, ankle], 2.8, 2.0, col)
        cv.poly([(ankle[0] - 2, ankle[1]), (ankle[0] + 2, ankle[1]),
                 (ankle[0] + 1, toe_y), (ankle[0] - 7, toe_y)], DARK)
    cv.line([(31, 30), (30, 37)], 3.0, 3.6, SHADE)      # the neck
    cv.poly([(24, 36), (39, 35), (43, 46), (40, 60), (39, 72), (27, 72), (24, 60), (22, 46)], BODY)
    for y in range(40, 68, 4):                            # ribs, side on
        for x in range(25, 33):
            cv.put(x, y, DARK)
    for y in range(37, 70, 5):                            # spines down its back
        cv.line([(40, y + 3), (44, y)], 1.2, 0.4, HORN)
    swing = 6 if frame == 0 else -6                       # the near arm
    cv.line([(30, 39), (27 - swing * 0.5, 58)], 3.2, 2.6, BODY)
    cv.line([(27 - swing * 0.5, 58), (25 - swing, 77)], 2.6, 2.0, BODY)
    for k in (-2, 0, 2):
        cv.line([(25 - swing + k, 78), (24 - swing + k * 1.5, 86)], 0.9, 0.4, BONE)
    for k, dx in enumerate((3, 0)):                       # its horns, swept back
        cv.line([(31 + dx, 13), (39 + dx, 9), (46 + dx, 4), (50 + dx, 0)], 3.0, 0.6,
                DARK if k == 0 else HORN)
        cv.put(50 + dx, 0, TIP)
    cv.ellipse(30, 21, 10, 10, BODY)                      # the locust head, its
    cv.poly([(18, 20), (27, 16), (31, 34), (22, 35)], BODY)   # face sloping down
    cv.ellipse(25, 20, 3.4, 5, EYE)                       # its eye
    cv.line([(19, 25), (24, 34)], 0.8, 0.6, SHADE)       # the face's edge
    cv.poly([(21, 33), (25, 33), (25, 36), (22, 36)], MAW)    # the mouth
    cv.line([(22, 35), (20, 39)], 1.0, 0.5, DARK)        # a mandible
    cv.shade_left(BODY, SHADE, 0.0)
    for row in cv.px:                                     # its back in shadow
        xs = [x for x, v in enumerate(row) if v == BODY]
        for x in xs[-max(1, len(xs) // 4):] if xs else []:
            row[x] = SHADE
    cv.outline()
    return cv


def rows(cv):
    return ["".join(sf.PIXEL_CHARS[v] for v in r) for r in cv.px]


def devil_figure():
    """The devil's figure data (sprites/devil.json's)."""
    make = {"walk_front": front, "walk_side": side, "walk_rear": rear}
    anims = {a: {"frames": [{"lods": [{"min_z": 0, "rows": rows(make[a](f))}]}
                            for f in range(sf.DEVIL_FRAMES_EACH)]}
             for a, _ in sf.DEVIL_ANIMS}
    return {"name": sf.DEVIL, "height": sf.DEVIL_H, "anims": anims}


if __name__ == "__main__":                 # a look at it: python tools/devilart.py
    d = devil_figure()
    for a in d["anims"]:
        print(a)
        fr = d["anims"][a]["frames"]
        for y in range(0, H, 2):
            print("  ".join(fr[f]["lods"][0]["rows"][y] for f in range(len(fr))))
