#!/usr/bin/env python3
"""Sea Battle's own interface icons: one atlas of white masks (the game tints them with ImageColor3).

Every glyph is drawn here from simple geometry (circles, rounded strokes, polygons, Bezier curves) on a
128-unit grid, rendered 8x larger and scaled down for smooth edges. Nothing is traced or copied from
another game: the shapes are written below. Run:

    python3 tools/make_icons.py            # writes assets/ui/icons.png and assets/ui/icons_preview.png

Then upload assets/ui/icons.png to Roblox (Studio's upload_image) and write its id with
    python3 tools/make_icons.py --asset rbxassetid://<id>
which updates src/shared/IconAtlas.luau (names -> cells) and assets/ui/icons.json (hash -> id).
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui")
CELL = 128          # px per icon in the atlas
COLS = 8
SS = 8              # supersampling
U = CELL * SS / 128  # px per design unit at render size


class Glyph:
    """A mask drawn in design units (0..128); `cut` draws in black (holes)."""

    def __init__(self):
        self.im = Image.new("L", (CELL * SS, CELL * SS), 0)
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def p(x, y):
        return (x * U, y * U)

    def poly(self, pts, cut=False):
        self.d.polygon([self.p(x, y) for x, y in pts], fill=0 if cut else 255)

    def circle(self, cx, cy, r, cut=False):
        self.d.ellipse([self.p(cx - r, cy - r), self.p(cx + r, cy + r)], fill=0 if cut else 255)

    def ellipse(self, cx, cy, rx, ry, cut=False):
        self.d.ellipse([self.p(cx - rx, cy - ry), self.p(cx + rx, cy + ry)], fill=0 if cut else 255)

    def rrect(self, x0, y0, x1, y1, r, cut=False):
        self.d.rounded_rectangle([self.p(x0, y0), self.p(x1, y1)], radius=r * U, fill=0 if cut else 255)

    def line(self, pts, w, cut=False):
        """Polyline with round caps and joins."""
        col = 0 if cut else 255
        sp = [self.p(x, y) for x, y in pts]
        if len(sp) > 1:
            self.d.line(sp, fill=col, width=max(1, int(w * U)), joint="curve")
        r = w / 2
        for x, y in pts:
            self.circle(x, y, r, cut)

    def ring(self, cx, cy, r, w, cut=False):
        self.d.ellipse([self.p(cx - r - w / 2, cy - r - w / 2), self.p(cx + r + w / 2, cy + r + w / 2)],
                       fill=0 if cut else 255)
        if not cut:
            self.d.ellipse([self.p(cx - r + w / 2, cy - r + w / 2), self.p(cx + r - w / 2, cy + r - w / 2)], fill=0)

    def arc(self, cx, cy, r, a0, a1, w, cut=False, steps=64):
        """Arc in degrees (0 = right, clockwise as y grows down)."""
        pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
                cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps))) for i in range(steps + 1)]
        self.line(pts, w, cut)
        return pts

    def pie(self, cx, cy, r, a0, a1, cut=False):
        self.d.pieslice([self.p(cx - r, cy - r), self.p(cx + r, cy + r)], a0, a1, fill=0 if cut else 255)

    fit = None

    def done(self):
        im = self.im
        if self.fit:
            # Scale the drawing up so its larger side spans `fit` units, centred in the cell.
            box = im.getbbox()
            if box:
                part = im.crop(box)
                w, h = part.size
                k = self.fit * U / max(w, h)
                part = part.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
                im = Image.new("L", self.im.size, 0)
                im.paste(part, ((im.size[0] - part.size[0]) // 2, (im.size[1] - part.size[1]) // 2))
        return im.resize((CELL, CELL), Image.LANCZOS)


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def rot(pts, ang, cx=64, cy=64):
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def mirror(pts, cx=64):
    """A left half (top to bottom) closed with its mirror image."""
    return pts + [(2 * cx - x, y) for x, y in reversed(pts)]


ICONS: dict[str, callable] = {}


def icon(name):
    def reg(fn):
        ICONS[name] = fn
        return fn
    return reg


# --- economy and stats -------------------------------------------------------------------------------
@icon("anchor")
def _(g):
    g.ring(64, 24, 10, 9)
    g.line([(64, 34), (64, 108)], 10)
    g.line([(44, 48), (84, 48)], 9)
    g.arc(64, 66, 40, 25, 155, 10)
    for sx in (1, -1):
        tip = (64 + sx * 40 * math.cos(math.radians(25)), 66 + 40 * math.sin(math.radians(25)))
        g.poly([(tip[0] + sx * 8, tip[1] - 16), (tip[0] + sx * 12, tip[1] + 6), (tip[0] - sx * 10, tip[1] + 2)])


@icon("coins")
def _(g):
    # two coins seen from the front: the back one peeks out to the upper right
    g.circle(78, 50, 36)
    g.circle(52, 76, 42, cut=True)
    g.circle(52, 76, 37)
    g.ring(52, 76, 26, 6, cut=False)
    g.circle(52, 76, 26, cut=True)
    g.ring(52, 76, 26, 6)
    g.poly([(52, 58), (64, 76), (52, 94), (40, 76)])

@icon("trend")
def _(g):
    g.line([(18, 96), (48, 64), (70, 82), (100, 46)], 12)
    g.poly([(110, 30), (112, 64), (80, 38)])


@icon("swords")
def _(g):
    for ang in (45, -45):
        g.poly(rot([(57, 16), (71, 16), (71, 80), (57, 80)], ang))
        g.poly(rot([(57, 16), (71, 16), (64, 4)], ang))
        g.line(rot([(44, 84), (84, 84)], ang), 11)
        g.line(rot([(64, 88), (64, 104)], ang), 10)
        g.circle(*rot([(64, 112)], ang)[0], 8)

@icon("target")
def _(g):
    g.ring(64, 64, 46, 10)
    g.ring(64, 64, 26, 10)
    g.circle(64, 64, 9)


@icon("shield")
def _(g):
    left = [(64, 10)] + bez((64, 10), (48, 20), (30, 22), (18, 22)) + bez((18, 22), (16, 70), (36, 98), (64, 118))
    g.poly(mirror(left))
    inner = [(64, 26)] + bez((64, 26), (52, 33), (40, 35), (31, 35)) + bez((31, 35), (31, 70), (44, 90), (64, 103))
    g.poly(mirror(inner), cut=True)
    g.poly(mirror([(64, 36)] + bez((64, 36), (55, 41), (47, 43), (41, 43)) + bez((41, 43), (42, 70), (50, 84), (64, 93))))


@icon("clock")
def _(g):
    g.ring(64, 64, 46, 11)
    g.line([(64, 38), (64, 66), (84, 78)], 10)


@icon("ship")
def _(g):
    g.poly([(10, 72), (118, 72), (100, 102), (28, 102)])
    g.rrect(36, 50, 82, 72, 4)
    g.rrect(48, 34, 70, 52, 3)
    g.rrect(86, 56, 96, 72, 2)
    for x in (44, 58):
        g.circle(x, 61, 3.5, cut=True)


# --- buildings ---------------------------------------------------------------------------------------
@icon("plane")
def _(g):
    pts = [(64, 8)] + bez((64, 8), (70, 8), (72, 18), (72, 30)) + [(72, 46), (118, 70), (118, 82), (72, 70), (72, 96),
           (88, 108), (88, 116), (64, 110)]
    pts = pts + [(128 - x, y) for x, y in reversed(pts[:-1])]
    g.poly(rot(pts, 45))


@icon("jet")
def _(g):
    half = [(64, 6), (70, 22), (72, 44), (112, 86), (112, 96), (74, 84), (74, 98), (90, 112), (90, 120), (64, 112)]
    g.poly(half + [(128 - x, y) for x, y in reversed(half[:-1])])
    g.poly([(64, 26), (68, 38), (64, 50), (60, 38)], cut=True)


@icon("drop")
def _(g):
    pts = [(64, 8)] + bez((64, 8), (84, 40), (104, 60), (104, 80)) + bez((104, 80), (104, 102), (86, 118), (64, 118))
    g.poly(mirror(pts))
    g.arc(64, 80, 26, 100, 160, 8, cut=True)


@icon("flame")
def _(g):
    outer = bez((64, 6), (40, 36), (22, 56), (22, 80)) + bez((22, 80), (22, 104), (42, 120), (64, 120)) + \
        bez((64, 120), (88, 120), (106, 104), (106, 80)) + bez((106, 80), (106, 62), (96, 48), (88, 36)) + \
        bez((88, 36), (86, 52), (80, 58), (74, 60)) + bez((74, 60), (76, 40), (72, 22), (64, 6))
    g.poly(outer)
    inner = bez((64, 62), (52, 78), (44, 88), (44, 98)) + bez((44, 98), (44, 110), (54, 116), (64, 116)) + \
        bez((64, 116), (74, 116), (84, 110), (84, 98)) + bez((84, 98), (84, 88), (76, 78), (64, 62))
    g.poly(inner, cut=True)


@icon("radar")
def _(g):
    # Missile defence: a shield with an interceptor rocket rising through it, cut out
    left = [(64, 8)] + bez((64, 8), (48, 18), (28, 20), (14, 20)) + bez((14, 20), (12, 70), (34, 100), (64, 120))
    g.poly(mirror(left))
    g.poly(mirror([(64, 26)] + bez((64, 26), (72, 34), (75, 44), (75, 56)) + [(75, 88), (64, 88)]), cut=True)
    g.poly([(53, 70), (42, 92), (53, 88)], cut=True)
    g.poly([(75, 70), (86, 92), (75, 88)], cut=True)
    g.poly([(56, 92), (72, 92), (64, 106)], cut=True)
    g.fit = 116

@icon("radiation")
def _(g):
    for a in (-90, 30, 150):
        g.pie(64, 64, 54, a - 32, a + 32)
    g.circle(64, 64, 22, cut=True)
    g.circle(64, 64, 13)


@icon("rocket")
def _(g):
    body = [(64, 6)] + bez((64, 6), (78, 20), (82, 38), (82, 56)) + [(82, 92), (64, 92)]
    pts = mirror(body)
    fins = [(46, 66), (30, 88), (30, 104), (46, 94)]
    shape = rot(pts, 40, 64, 64)
    g.poly(shape)
    g.poly(rot(fins, 40, 64, 64))
    g.poly(rot([(128 - x, y) for x, y in fins], 40, 64, 64))
    g.circle(*rot([(64, 42)], 40, 64, 64)[0], 9, cut=True)
    g.poly(rot([(54, 96), (74, 96), (64, 120)], 40, 64, 64))


@icon("burst")
def _(g):
    pts = []
    for i in range(24):
        r = 58 if i % 2 == 0 else 34
        a = math.radians(i * 15 - 90)
        pts.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
    g.poly(pts)
    pts2 = []
    for i in range(16):
        r = 26 if i % 2 == 0 else 15
        a = math.radians(i * 22.5 - 90 + 11)
        pts2.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
    g.poly(pts2, cut=True)


@icon("mirv")
def _(g):
    # three slim warheads side by side, the middle one ahead
    for dx, dy in ((-34, 14), (0, 0), (34, 14)):
        war = mirror([(64, 12)] + bez((64, 12), (71, 20), (73, 30), (73, 42)) + [(73, 92), (64, 92)])
        g.poly([(x + dx, y + dy) for x, y in war])
        g.poly([(55 + dx, 76 + dy), (49 + dx, 100 + dy), (55 + dx, 96 + dy)])
        g.poly([(73 + dx, 76 + dy), (79 + dx, 100 + dy), (73 + dx, 96 + dy)])

@icon("factory")
def _(g):
    g.poly([(12, 116), (12, 60), (40, 76), (40, 60), (68, 76), (68, 60), (96, 76), (96, 20), (116, 20), (116, 116)])
    for x in (24, 52, 80):
        g.rrect(x, 90, x + 14, 104, 2, cut=True)


# --- actions and interface ---------------------------------------------------------------------------
@icon("trophy")
def _(g):
    cup = [(30, 14), (98, 14)] + bez((98, 14), (98, 58), (84, 74), (64, 76)) + bez((64, 76), (44, 74), (30, 58), (30, 14))
    g.poly(cup)
    g.arc(30, 36, 16, 90, 270, 8)
    g.arc(98, 36, 16, -90, 90, 8)
    g.rrect(56, 74, 72, 98, 2)
    g.rrect(36, 96, 92, 114, 5)


@icon("restart")
def _(g):
    g.arc(64, 66, 40, -60, 230, 12)
    a = math.radians(-60)
    tip = (64 + 40 * math.cos(a), 66 + 40 * math.sin(a))
    g.poly([(tip[0] + 18, tip[1] - 14), (tip[0] + 6, tip[1] + 22), (tip[0] - 20, tip[1] - 2)])


@icon("alliance")
def _(g):
    # two linked rings: the left passes over the right at the top, under it at the bottom
    g.ring(82, 64, 26, 11)
    g.ring(46, 64, 26, 11)
    g.circle(64, 45.2, 9.5, cut=True)
    g.arc(46, 64, 26, -62, -30, 11)
    g.circle(64, 82.8, 9.5, cut=True)
    g.arc(82, 64, 26, 118, 150, 11)

@icon("waves")
def _(g):
    for y in (44, 72, 100):
        pts = [(14 + i * 2.5, y + 8 * math.sin(i * 2.5 / 100 * 2 * math.pi * 1.25)) for i in range(41)]
        g.line(pts, 10)


@icon("help")
def _(g):
    g.arc(64, 44, 24, 180, 405, 13)
    g.line([(64 + 24 * math.cos(math.radians(405)), 44 + 24 * math.sin(math.radians(405))), (64, 76), (64, 84)], 13)
    g.circle(64, 108, 9)


@icon("check")
def _(g):
    g.line([(22, 66), (52, 94), (106, 36)], 15)


@icon("close")
def _(g):
    g.line([(30, 30), (98, 98)], 15)
    g.line([(98, 30), (30, 98)], 15)


@icon("people")
def _(g):
    g.circle(84, 40, 16)
    g.pie(84, 108, 34, 180, 360)
    g.circle(46, 46, 19, cut=True)
    g.pie(46, 118, 42, 180, 360, cut=True)
    g.circle(46, 46, 15)
    g.pie(46, 116, 36, 180, 360)


@icon("gear")
def _(g):
    pts = []
    for i in range(16):
        a = math.radians(i * 22.5 + 11.25)
        r = 54 if (i // 1) % 2 == 0 else 40
        a0, a1 = a - math.radians(9), a + math.radians(9)
        pts += [(64 + r * math.cos(a0), 64 + r * math.sin(a0)), (64 + r * math.cos(a1), 64 + r * math.sin(a1))]
    g.poly(pts)
    g.circle(64, 64, 17, cut=True)


@icon("menu")
def _(g):
    for y in (34, 64, 94):
        g.line([(24, y), (104, y)], 13)


@icon("globe")
def _(g):
    g.ring(64, 64, 48, 9)
    g.line([(64, 18), (64, 110)], 7)
    g.line([(18, 64), (110, 64)], 7)
    g.d.arc([g.p(40, 16), g.p(88, 112)], 0, 360, fill=255, width=int(7 * U))
    for y, half in ((40, 40), (88, 40)):
        g.line([(64 - half, y), (64 + half, y)], 6)


@icon("eye")
def _(g):
    top = bez((8, 64), (36, 24), (92, 24), (120, 64))
    bot = bez((120, 64), (92, 104), (36, 104), (8, 64))
    g.poly(top + bot)
    g.circle(64, 64, 23, cut=True)
    g.circle(64, 64, 14)


@icon("pin")
def _(g):
    pts = [(64, 120)] + bez((64, 120), (50, 96), (22, 74), (22, 50)) + bez((22, 50), (22, 24), (42, 8), (64, 8))
    g.poly(mirror(list(reversed(pts))))
    g.circle(64, 50, 15, cut=True)


@icon("dice")
def _(g):
    g.rrect(16, 16, 112, 112, 20)
    for x, y in ((40, 40), (88, 40), (64, 64), (40, 88), (88, 88)):
        g.circle(x, y, 9, cut=True)


@icon("home")
def _(g):
    g.poly([(64, 12), (120, 62), (106, 62), (106, 116), (22, 116), (22, 62), (8, 62)])
    g.rrect(52, 80, 76, 116, 3, cut=True)


@icon("search")
def _(g):
    g.ring(54, 54, 32, 12)
    g.line([(78, 78), (110, 110)], 16)


@icon("fish")
def _(g):
    g.ellipse(56, 64, 40, 26)
    g.poly([(88, 64), (120, 38), (114, 64), (120, 90)])
    g.circle(36, 58, 6, cut=True)
    g.arc(56, 64, 22, -60, 60, 5, cut=True)


@icon("fin")
def _(g):
    fin = bez((22, 88), (44, 70), (62, 40), (84, 10)) + bez((84, 10), (80, 40), (84, 68), (106, 88))
    g.poly(fin)
    pts = [(8 + i * 2.8, 98 + 6 * math.sin(i * 2.8 / 112 * 2 * math.pi * 2)) for i in range(41)]
    g.line(pts, 9)

@icon("star")
def _(g):
    pts = []
    for i in range(10):
        r = 56 if i % 2 == 0 else 23
        a = math.radians(i * 36 - 90)
        pts.append((64 + r * math.cos(a), 68 + r * math.sin(a)))
    g.poly(pts)


@icon("crane")
def _(g):
    g.line([(30, 116), (30, 20), (108, 20)], 9)
    g.line([(30, 34), (52, 20)], 6)
    g.line([(14, 20), (30, 20)], 9)
    g.line([(92, 20), (92, 58)], 4)
    g.rrect(80, 58, 104, 76, 3)
    g.rrect(12, 108, 52, 120, 3)


@icon("gamepad")
def _(g):
    pts = bez((30, 34), (14, 34), (6, 70), (14, 92)) + bez((14, 92), (20, 106), (34, 104), (44, 88)) + [(84, 88)] + \
        bez((84, 88), (94, 104), (108, 106), (114, 92)) + bez((114, 92), (122, 70), (114, 34), (98, 34))
    g.poly(pts)
    g.line([(28, 62), (48, 62)], 8, cut=True)
    g.line([(38, 52), (38, 72)], 8, cut=True)
    g.circle(88, 56, 6, cut=True)
    g.circle(100, 68, 6, cut=True)


@icon("rocket_up")
def _(g):
    body = [(64, 8)] + bez((64, 8), (80, 22), (84, 40), (84, 58)) + [(84, 92), (64, 92)]
    g.poly(mirror(body))
    g.poly([(44, 64), (26, 90), (26, 104), (44, 94)])
    g.poly([(84, 64), (102, 90), (102, 104), (84, 94)])
    g.circle(64, 42, 9, cut=True)
    g.poly([(54, 96), (74, 96), (64, 122)])


@icon("avatar")
def _(g):
    # a default avatar head for bots that play as people: a rounded block with two eyes and a smile
    g.rrect(20, 22, 108, 110, 22)
    g.rrect(44, 50, 56, 74, 6, cut=True)
    g.rrect(72, 50, 84, 74, 6, cut=True)
    g.arc(64, 70, 22, 30, 150, 8, cut=True)



@icon("pause")
def _(g):
    g.rrect(32, 22, 56, 106, 7)
    g.rrect(72, 22, 96, 106, 7)


def _speaker(g):
    g.rrect(10, 46, 40, 82, 4)
    g.poly([(36, 46), (68, 18), (68, 110), (36, 82)])


@icon("sound")
def _(g):
    _speaker(g)
    g.arc(70, 64, 22, -50, 50, 9)
    g.arc(70, 64, 42, -50, 50, 9)


@icon("mute")
def _(g):
    _speaker(g)
    g.line([(82, 46), (116, 82)], 10)
    g.line([(116, 46), (82, 82)], 10)


@icon("exit")
def _(g):
    # an open door frame and an arrow leaving it
    g.line([(70, 18), (22, 18), (22, 110), (70, 110)], 11)
    g.line([(46, 64), (100, 64)], 11)
    g.poly([(90, 40), (120, 64), (90, 88)])

# --- account, shop ------------------------------------------------------------------------------------
@icon("gift")
def _(g):
    # a box with a lid, a ribbon and a bow
    g.rrect(22, 58, 106, 112, 8)
    g.rrect(14, 38, 114, 60, 7)
    g.line([(64, 40), (64, 112)], 12, cut=True)
    g.line([(22, 60), (106, 60)], 5, cut=True)
    g.ring(48, 26, 11, 8)
    g.ring(80, 26, 11, 8)


@icon("shop")
def _(g):
    # a shopping bag with two handles
    g.rrect(24, 44, 104, 114, 12)
    g.arc(64, 44, 20, 180, 360, 9)
    g.circle(46, 62, 6, cut=True)
    g.circle(82, 62, 6, cut=True)


@icon("lock")
def _(g):
    g.arc(64, 50, 22, 180, 360, 12)
    g.line([(42, 50), (42, 62)], 12)
    g.line([(86, 50), (86, 62)], 12)
    g.rrect(26, 58, 102, 114, 12)
    g.circle(64, 82, 8, cut=True)
    g.line([(64, 84), (64, 98)], 7, cut=True)


@icon("flag")
def _(g):
    # a pennant on a mast
    g.line([(34, 16), (34, 114)], 10)
    g.poly([(40, 22), (108, 34), (84, 50), (108, 68), (40, 76)])


@icon("pattern")
def _(g):
    # three wavy lines: a pattern laid over the water
    for y in (36, 64, 92):
        g.line(bez((16, y), (40, y - 22), (56, y + 22), (64, y)) + bez((64, y), (72, y - 22), (88, y + 22), (112, y)), 10)


@icon("bolt")
def _(g):
    g.poly([(72, 10), (26, 72), (58, 72), (48, 118), (102, 52), (68, 52)])


# --- arsenal -----------------------------------------------------------------------------------------
@icon("cannon")
def _(g):
    # a coastal gun: a barrel on a round mount with a base
    g.poly(rot([(56, 50), (118, 50), (118, 70), (56, 70)], -24, 56, 60))
    g.circle(50, 66, 26)
    g.rrect(14, 92, 96, 110, 6)
    g.circle(50, 66, 9, cut=True)


@icon("depth")
def _(g):
    # a depth charge: a drum with bands, sinking under a wave line
    g.rrect(40, 44, 88, 112, 12)
    g.line([(40, 66), (88, 66)], 6, cut=True)
    g.line([(40, 90), (88, 90)], 6, cut=True)
    g.line(bez((14, 26), (34, 8), (46, 44), (64, 26)) + bez((64, 26), (82, 8), (94, 44), (114, 26)), 9)


@icon("cluster")
def _(g):
    # one big burst and four small ones around it
    g.circle(64, 64, 24)
    for cx, cy in ((22, 28), (106, 28), (22, 100), (106, 100)):
        g.circle(cx, cy, 12)
    g.circle(64, 64, 9, cut=True)


@icon("bomber")
def _(g):
    # a wide-winged aircraft seen from above, with a bomb under it
    g.poly([(64, 8), (74, 40), (120, 62), (120, 74), (74, 66), (70, 92), (84, 102), (84, 110), (44, 110), (44, 102), (58, 92), (54, 66), (8, 74), (8, 62), (54, 40)])
    g.circle(64, 122, 6)


@icon("reload")
def _(g):
    # two arrows chasing each other in a circle
    g.arc(64, 64, 40, 200, 340, 11)
    g.arc(64, 64, 40, 20, 160, 11)
    g.poly([(96, 30), (120, 52), (88, 62)])
    g.poly([(32, 98), (8, 76), (40, 66)])


@icon("muster")
def _(g):
    # a ship's hull with a plus over it: more fleet at once
    g.poly([(12, 78), (116, 78), (98, 112), (30, 112)])
    g.line([(64, 14), (64, 62)], 12)
    g.line([(40, 38), (88, 38)], 12)


# (added last, so the cells of the icons before it stay where the uploaded atlas has them)
@icon("torpedo")
def _(g):
    # a torpedo under a wave line: a long rounded body, a cross of fins and a propeller at the back
    g.line(bez((14, 24), (34, 6), (46, 42), (64, 24)) + bez((64, 24), (82, 6), (94, 42), (114, 24)), 9)
    g.rrect(26, 62, 112, 90, 14)
    g.poly([(30, 66), (12, 52), (12, 100), (30, 86)])
    g.line([(4, 64), (4, 88)], 7)
    g.line([(84, 62), (84, 90)], 5, cut=True)


@icon("chest")
def _(g):
    # a treasure chest: a rounded lid over a box, a band down the middle and a lock
    g.rrect(14, 30, 114, 62, 16)
    g.rrect(14, 66, 114, 112, 6)
    g.line([(14, 64), (114, 64)], 6, cut=True)
    g.rrect(54, 50, 74, 82, 4, cut=True)
    g.rrect(58, 54, 70, 78, 3)
    g.line([(36, 34), (36, 108)], 4, cut=True)
    g.line([(92, 34), (92, 108)], 4, cut=True)


def _notes(g):
    # two beamed eighth notes
    g.ellipse(36, 94, 16, 12)
    g.ellipse(88, 84, 16, 12)
    g.line([(50, 92), (50, 28)], 8)
    g.line([(102, 82), (102, 18)], 8)
    g.poly([(46, 24), (106, 12), (106, 32), (46, 44)])


@icon("music")
def _(g):
    _notes(g)


@icon("music_off")
def _(g):
    # the notes struck through
    _notes(g)
    g.line([(14, 18), (114, 112)], 18, cut=True)
    g.line([(18, 20), (110, 110)], 8)


ORDER = list(ICONS.keys())


def build():
    rows = math.ceil(len(ORDER) / COLS)
    atlas = Image.new("RGBA", (CELL * COLS, CELL * rows), (255, 255, 255, 0))
    cells = {}
    for i, name in enumerate(ORDER):
        g = Glyph()
        ICONS[name](g)
        mask = g.done()
        x, y = (i % COLS) * CELL, (i // COLS) * CELL
        white = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 255))
        white.putalpha(mask)
        atlas.paste(white, (x, y))
        cells[name] = [x, y]
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "icons.png")
    atlas.save(path, optimize=True)
    # A preview on a dark panel colour, to look at the set as the game will show it.
    prev = Image.new("RGBA", atlas.size, (23, 37, 48, 255))
    prev.alpha_composite(atlas)
    prev.save(os.path.join(OUT_DIR, "icons_preview.png"))
    return path, cells


RT_CELL = 48  # px per icon in the copy embedded in code (drawn at run time: no uploaded image needed)


def write_pixels(path):
    """src/shared/IconPixels.luau: the atlas's alpha at RT_CELL px per icon, run-length coded, so the game
    can build the atlas itself in an EditableImage. Uploaded images can stay unavailable to players (a
    moderation placeholder on phones, 2026-11-07) while Studio shows them to their author."""
    atlas = Image.open(path)
    k = RT_CELL / CELL
    small = atlas.resize((int(atlas.width * k), int(atlas.height * k)), Image.LANCZOS)
    alpha = small.split()[3].tobytes()
    out = []
    i, n = 0, len(alpha)
    while i < n:
        q = alpha[i] >> 4
        j = i + 1
        limit = 4096 if q == 0 else 16
        while j < n and j - i < limit and alpha[j] >> 4 == q:
            j += 1
        run = j - i
        if q == 0 and run > 16:
            out.append("z%03x" % (run - 1))      # a long transparent run: z + 3 hex digits
        else:
            out.append("%x%x" % (q, run - 1))   # level (0..15) and run length (1..16)
        i = j
    data = "".join(out)
    lines = ["--!nonstrict",
             "-- GENERATED by tools/make_icons.py - do not edit by hand.",
             f"-- The icon atlas's alpha at {RT_CELL} px per icon (white mask), run-length coded: pairs of hex digits",
             "-- (level 0..15, run length 1..16) and 'z' + 3 hex digits for long transparent runs.",
             "return {",
             f"\twidth = {small.width},",
             f"\theight = {small.height},",
             f"\tcell = {RT_CELL},",
             f'\tdata = "{data}",',
             "}", ""]
    with open(os.path.join(ROOT, "src", "shared", "IconPixels.luau"), "w") as f:
        f.write("\n".join(lines))
    return len(data)


def write_module(asset, cells, digest):
    lines = ["--!nonstrict",
             "-- GENERATED by tools/make_icons.py - do not edit by hand.",
             "-- Sea Battle's interface icons: white masks on one atlas (tint them with ImageColor3).",
             "return {",
             f'\tid = "{asset}",',
             f"\tcell = {CELL},",
             "\tcells = {"]
    for name in ORDER:
        x, y = cells[name]
        lines.append(f"\t\t{name} = {{ {x}, {y} }},")
    lines += ["\t},", "}", ""]
    with open(os.path.join(ROOT, "src", "shared", "IconAtlas.luau"), "w") as f:
        f.write("\n".join(lines))
    with open(os.path.join(OUT_DIR, "icons.json"), "w") as f:
        json.dump({"sha256": digest, "asset": asset, "cell": CELL, "icons": ORDER}, f, indent=1)


def main():
    path, cells = build()
    embedded = write_pixels(path)
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    asset = None
    if "--asset" in sys.argv:
        asset = sys.argv[sys.argv.index("--asset") + 1]
    else:
        meta = os.path.join(OUT_DIR, "icons.json")
        if os.path.exists(meta):
            old = json.load(open(meta))
            if old.get("sha256") == digest:
                asset = old.get("asset")
    if asset:
        write_module(asset, cells, digest)
        print(json.dumps({"atlas": path, "icons": len(ORDER), "asset": asset, "embeddedChars": embedded}))
    else:
        print(json.dumps({"atlas": path, "icons": len(ORDER), "asset": None,
                          "next": "upload assets/ui/icons.png, then run with --asset rbxassetid://<id>"}))


if __name__ == "__main__":
    main()
