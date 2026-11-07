#!/usr/bin/env python3
"""Draws the 7 map thumbnails (assets/maps/map_<id>.png) used by the map picker.

The pictures are illustrations of the real map layouts (same sizes, colours and obstacles as
scripts/map_builder.gd) seen from a raised camera. Run:  python3 tools/gen_map_thumbs.py
Needs Pillow only. Output: 480x270 PNG.
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

W, H = 960, 540           # drawn at 2x, saved at 480x270
K = 0.55                  # vertical squash of the ground plane (camera elevation)

PALETTE = [(255, 217, 31), (255, 107, 184), (51, 217, 242), (158, 92, 242), (255, 143, 41), (115, 230, 77)]
ORANGE = (255, 153, 51)
PURPLE_SIDE = (128, 89, 179)
WHITE = (255, 255, 255)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


class Scene:
    def __init__(self, scale, cy, cx=W / 2):
        self.img = Image.new("RGB", (W, H))
        self.d = ImageDraw.Draw(self.img)
        self.S, self.cy, self.cx = scale, cy, cx
        self._sky()

    def P(self, x, z, y=0.0):
        return (self.cx + x * self.S, self.cy + z * self.S * K - y * self.S * 0.95)

    def _sky(self):
        top, bot = (52, 140, 250), (196, 228, 255)
        for yy in range(H):
            t = yy / (H - 1)
            self.d.line([(0, yy), (W, yy)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
        rng = random.Random(5)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for _ in range(9):
            cx, cy = rng.randint(0, W), rng.randint(300, H)
            for _ in range(4):
                rx, ry = rng.randint(50, 110), rng.randint(18, 34)
                ox, oy = rng.randint(-70, 70), rng.randint(-12, 12)
                ld.ellipse([cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy + ry], fill=(255, 255, 255, 170))
        for _ in range(5):
            cx, cy = rng.randint(0, W), rng.randint(20, 150)
            for _ in range(3):
                rx, ry = rng.randint(40, 80), rng.randint(14, 24)
                ox = rng.randint(-50, 50)
                ld.ellipse([cx + ox - rx, cy - ry, cx + ox + rx, cy + ry], fill=(255, 255, 255, 110))
        self.img.paste(layer, (0, 0), layer)
        self.d = ImageDraw.Draw(self.img)

    # ---- primitives
    def ellipse_pts(self, x, z, r, y=0.0, n=72):
        return [self.P(x + r * math.cos(a), z + r * math.sin(a), y) for a in [i * math.tau / n for i in range(n)]]

    def disc(self, x, z, r, top, side, thick=1.0, rock=True):
        d = self.d
        if rock:
            pts = [self.P(x + r * math.cos(a), z + r * math.sin(a), -thick) for a in [i * math.pi / 36 for i in range(37)]]
            apex = self.P(x, z, -thick - r * 1.1)
            d.polygon(pts + [apex], fill=shade(side, 0.7))
        steps = 8
        for i in range(steps, -1, -1):
            d.polygon(self.ellipse_pts(x, z, r, -thick * i / steps), fill=shade(side, 0.85 + 0.15 * (1 - i / steps)))
        d.polygon(self.ellipse_pts(x, z, r), fill=top)
        d.line(self.ellipse_pts(x, z, r - 0.15) + [self.P(x + r - 0.15, z)], fill=WHITE, width=3)

    def quad(self, cx, cz, hx, hz, ang, y, fill, outline=None):
        c, s = math.cos(ang), math.sin(ang)
        pts = []
        for lx, lz in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)):
            pts.append(self.P(cx + lx * c - lz * s, cz + lx * s + lz * c, y))
        self.d.polygon(pts, fill=fill, outline=outline)
        return pts

    def slab(self, cx, cz, hx, hz, ang, thick, top, side=None):
        side = side or shade(top, 0.62)
        for i in range(6, 0, -1):
            self.quad(cx, cz, hx, hz, ang, -thick * i / 6, side)
        self.quad(cx, cz, hx, hz, ang, 0.0, top)

    def checker(self, r, cell):
        n = int(math.ceil(r / cell)) + 1
        for ix in range(-n, n + 1):
            for iz in range(-n, n + 1):
                px, pz = ix * cell, iz * cell
                if math.hypot(px, pz) + cell * 0.7 > r:
                    continue
        # draw back-to-front
        cells = []
        for ix in range(-n, n + 1):
            for iz in range(-n, n + 1):
                px, pz = ix * cell, iz * cell
                if math.hypot(px, pz) + cell * 0.7 > r:
                    continue
                ring = int(math.hypot(px, pz) / (cell * 1.6))
                cells.append((pz, px, PALETTE[(ring + abs(ix + iz)) % len(PALETTE)]))
        for pz, px, col in sorted(cells):
            self.quad(px, pz, cell * 0.475, cell * 0.475, 0, 0.0, col)

    def tile_ring(self, count, radius, size, col_fn=None):
        items = []
        for i in range(count):
            a = i * math.tau / count
            items.append((radius * math.sin(a), a, i))
        for _, a, i in sorted(items):
            self.slab(radius * math.cos(a), radius * math.sin(a), size[0] / 2, size[1] / 2, a, 0.45, PALETTE[i % len(PALETTE)])

    def bar(self, x, z, length, ang, color, y=0.6, width=0.9):
        """Rotating bar seen from above: a thick segment (sweeper / hammer arm)."""
        c, s = math.cos(ang), math.sin(ang)
        a = self.P(x - c * length, z - s * length, y)
        b = self.P(x + c * length, z + s * length, y)
        w = max(4, int(width * self.S * 0.55))
        self.d.line([a, b], fill=shade(color, 0.6), width=w + 4)
        self.d.line([a, b], fill=color, width=w)
        for p in (a, b):
            self.d.ellipse([p[0] - w * 0.75, p[1] - w * 0.75, p[0] + w * 0.75, p[1] + w * 0.75], fill=color, outline=shade(color, 0.6))

    def pole(self, x, z, h, color=(235, 235, 245)):
        a, b = self.P(x, z, 0), self.P(x, z, h)
        w = max(4, int(self.S * 0.35))
        self.d.line([a, b], fill=color, width=w)
        self.d.ellipse([b[0] - w, b[1] - w, b[0] + w, b[1] + w], fill=WHITE, outline=(120, 120, 150))

    def sweeper(self, x, z, arm, color, ang=0.55):
        self.pole(x, z, 0.3)
        self.bar(x, z, arm, ang, color, y=0.55, width=1.1)
        self.pole(x, z, 2.2)

    def hammer(self, x, z, arm, color, ang=1.0):
        c, s = math.cos(ang), math.sin(ang)
        base, top = self.P(x, z, 0), self.P(x, z, 2.0)
        w = max(4, int(self.S * 0.3))
        self.d.line([base, top], fill=(230, 230, 240), width=w)
        e = self.P(x + c * arm, z + s * arm, 1.4)
        self.d.line([top, e], fill=(200, 200, 215), width=w)
        r = max(8, int(self.S * 0.62))
        self.d.ellipse([e[0] - r, e[1] - r, e[0] + r, e[1] + r], fill=color, outline=shade(color, 0.55), width=3)
        self.d.ellipse([e[0] - r * 0.5, e[1] - r * 0.7, e[0] - r * 0.05, e[1] - r * 0.25], fill=shade(color, 1.35))

    def balloons(self, ring, rng):
        cols = [(255, 107, 184), (255, 217, 31), (51, 217, 242), (115, 230, 77)]
        for i in range(6):
            a = i * math.tau / 6 + 0.3
            p = self.P(ring * math.cos(a), ring * math.sin(a), 4.0 + (i % 3) * 1.5)
            r = self.S * 0.9
            self.d.line([p, (p[0], p[1] + r * 2.4)], fill=(255, 255, 255), width=2)
            self.d.ellipse([p[0] - r, p[1] - r * 1.2, p[0] + r, p[1] + r * 1.2], fill=cols[i % 4], outline=shade(cols[i % 4], 0.7), width=2)
            self.d.ellipse([p[0] - r * 0.5, p[1] - r * 0.8, p[0] - r * 0.15, p[1] - r * 0.3], fill=shade(cols[i % 4], 1.4))

    def save(self, name):
        out = self.img.resize((W // 2, H // 2), Image.LANCZOS)
        out.save(name, optimize=True)


# ---------------------------------------------------------------- arena maps
def map_cloud():
    s = Scene(15.2, 290)
    # far islands + bridges
    for sx, col in ((1, (115, 230, 77)), (-1, (255, 107, 184))):
        s.slab(sx * 19.5, 0, 2.5, 1.7, 0, 0.5, (158, 92, 242))
        s.disc(sx * 26, 0, 3.6, col, ORANGE, 0.9)
        s.pole(sx * 26, -2.2, 3.4)
    s.disc(0, 0, 13, ORANGE, PURPLE_SIDE, 1.2)
    s.checker(13, 2.0)
    s.d.polygon(s.ellipse_pts(0, 0, 1.6), fill=WHITE)
    s.tile_ring(32, 14.5, (2.75, 2.8))
    s.sweeper(0, 0, 4.0, (255, 143, 41), 0.5)
    for i, (col, ang) in enumerate([((242, 69, 69), 0.4), ((158, 92, 242), 2.2), ((51, 217, 242), 4.1)]):
        a = i * math.tau / 3 + math.pi / 2
        s.hammer(9 * math.cos(a), 9 * math.sin(a), 3.0, col, ang)
    s.balloons(20, None)
    s.save("assets/maps/map_0.png")


def map_ring():
    s = Scene(30, 280)
    s.disc(0, 0, 8, (51, 191, 230), (89, 77, 153), 1.2)
    s.checker(8, 2.0)
    s.tile_ring(22, 9.6, (2.9, 2.9))
    s.sweeper(0, 0, 3.2, (255, 115, 51), 0.35)
    s.hammer(5.6, 0, 1.9, (242, 69, 69), 1.9)
    s.hammer(-5.6, 0, 1.9, (158, 92, 242), 5.0)
    s.balloons(16, None)
    s.save("assets/maps/map_1.png")


def map_tiles():
    s = Scene(23, 300)
    cell = 3.2
    s.slab(0, 0, cell * 1.5, cell * 1.5, 0, 1.0, ORANGE)
    cells = []
    for ix in range(-4, 5):
        for iz in range(-4, 5):
            inner = abs(ix) <= 1 and abs(iz) <= 1
            idx = (abs(ix) * 2 + abs(iz) + 1) if inner else (abs(ix) + abs(iz))
            cells.append((iz, ix, inner, PALETTE[idx % 6]))
    for iz, ix, inner, col in sorted(cells):
        if inner:
            s.quad(ix * cell, iz * cell, cell * 0.47, cell * 0.47, 0, 0.1, col)
        else:
            s.slab(ix * cell, iz * cell, (cell - 0.18) / 2, (cell - 0.18) / 2, 0, 0.4, col)
    s.sweeper(0, 0, 3.3, (242, 69, 69), 0.7)
    s.balloons(24, None)
    s.save("assets/maps/map_2.png")


def map_islands():
    s = Scene(21.5, 285)
    cols = [(255, 107, 184), (51, 217, 242), (255, 217, 31), (158, 92, 242)]
    items = []
    for i in range(4):
        a = i * math.tau / 4 + math.pi / 4
        items.append((19 * math.sin(a), i, a))
    for _, i, a in sorted(items):
        dx, dz = math.cos(a), math.sin(a)
        s.slab(dx * 11.4, dz * 11.4, 2.6, 1.7, a, 0.5, (158, 92, 242))
        s.disc(dx * 19, dz * 19, 3.6, cols[i], ORANGE, 0.9)
        s.pole(dx * 19, dz * 19, 3.0)
    s.disc(0, 0, 6, (115, 230, 77), (140, 102, 191), 1.0)
    s.checker(6, 2.0)
    s.sweeper(0, 0, 2.6, (255, 143, 41), 0.4)
    s.balloons(26, None)
    s.save("assets/maps/map_3.png")


def map_donut():
    s = Scene(28, 290)
    mid, width, segs = 9.0, 6.0, 30
    # tall pillar in the void
    a, b = s.P(0, 0, 0), s.P(0, 0, -14)
    s.d.polygon([(a[0] - 10, a[1]), (a[0] + 10, a[1]), (b[0] + 20, b[1]), (b[0] - 20, b[1])], fill=(158, 92, 242))
    seg_len = math.tau * mid / segs * 1.12
    order = sorted(range(segs), key=lambda i: math.sin(i * math.tau / segs))
    for i in order:
        a = i * math.tau / segs
        x, z = mid * math.cos(a), mid * math.sin(a)
        s.slab(x, z, width / 2, seg_len / 2, a, 1.0, ORANGE, (128, 89, 179))
        s.quad(x, z, (width - 0.5) / 2, seg_len * 0.46, a, 0.08, PALETTE[i % 6])
    s.hammer(0, mid, 2.4, (242, 69, 69), 0.6)
    s.hammer(0, -mid, 2.4, (51, 217, 242), 3.6)
    s.balloons(19, None)
    s.save("assets/maps/map_4.png")


# ---------------------------------------------------------------- houses
FLOORS = {"living": (219, 184, 128), "bedroom": (184, 158, 219), "kitchen": (230, 230, 199),
          "bathroom": (153, 217, 235), "office": (179, 209, 168), "storage": (199, 179, 158)}
CYCLE = ["living", "bedroom", "kitchen", "bathroom", "office", "bedroom", "storage", "living", "bathroom", "kitchen", "bedroom", "office"]
FURN = [(150, 90, 60), (90, 120, 200), (200, 80, 90), (230, 200, 90), (120, 170, 110), (170, 120, 190)]


def house(cols, rows, rw, rd, seed, scale, cy, name):
    rng = random.Random(seed)
    s = Scene(scale, cy)
    tw, td = cols * rw, rows * rd
    ox, oz = -tw / 2, -td / 2
    wall_h = 1.7
    wall_col = (226, 204, 168)
    # connectivity
    door_h, door_v = set(), set()
    seen = {(0, 0)}
    stack = [(0, 0)]
    while stack:
        cur = stack[-1]
        opts = [(cur[0] + dx, cur[1] + dz) for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= cur[0] + dx < cols and 0 <= cur[1] + dz < rows and (cur[0] + dx, cur[1] + dz) not in seen]
        if not opts:
            stack.pop()
            continue
        nxt = rng.choice(opts)
        seen.add(nxt)
        if nxt[1] == cur[1]:
            door_h.add((min(cur[0], nxt[0]), cur[1]))
        else:
            door_v.add((cur[0], min(cur[1], nxt[1])))
        stack.append(nxt)
    for _ in range(max(2, cols * rows // 3)):
        rx, rz = rng.randrange(cols), rng.randrange(rows)
        if rng.random() < 0.5 and rx + 1 < cols:
            door_h.add((rx, rz))
        elif rz + 1 < rows:
            door_v.add((rx, rz))
    # ground
    g = [s.P(ox - 7, oz - 7), s.P(ox + tw + 7, oz - 7), s.P(ox + tw + 7, oz + td + 7), s.P(ox - 7, oz + td + 7)]
    s.d.polygon(g, fill=(115, 199, 97), outline=(80, 160, 70))
    # floors
    rooms = []
    for rz in range(rows):
        for rx in range(cols):
            idx = rz * cols + rx
            t = "living" if idx == 0 else CYCLE[idx % len(CYCLE)]
            cx, cz = ox + (rx + 0.5) * rw, oz + (rz + 0.5) * rd
            fc = FLOORS[t]
            s.quad(cx, cz, rw / 2 - 0.05, rd / 2 - 0.05, 0, 0.0, fc)
            s.quad(cx, cz, rw * 0.175, rd * 0.175, 0, 0.02, shade(fc, 0.8))
            rooms.append((cx, cz, t))
    # drawables sorted back to front
    items = []

    def wall(x0, z0, x1, z1):
        items.append((max(z0, z1), "w", (x0, z0, x1, z1)))

    for rx in range(cols):
        cx = ox + (rx + 0.5) * rw
        wall(cx - rw / 2, oz, cx + rw / 2, oz)
        wall(cx - rw / 2, oz + td, cx + rw / 2, oz + td)
    for rz in range(rows):
        cz = oz + (rz + 0.5) * rd
        wall(ox, cz - rd / 2, ox, cz + rd / 2)
        wall(ox + tw, cz - rd / 2, ox + tw, cz + rd / 2)
    dw = 1.9
    for rz in range(rows):
        for rx in range(cols):
            cx, cz = ox + (rx + 0.5) * rw, oz + (rz + 0.5) * rd
            if rx < cols - 1:
                x = cx + rw / 2
                if (rx, rz) in door_h:
                    wall(x, cz - rd / 2, x, cz - dw / 2)
                    wall(x, cz + dw / 2, x, cz + rd / 2)
                else:
                    wall(x, cz - rd / 2, x, cz + rd / 2)
            if rz < rows - 1:
                z = cz + rd / 2
                if (rx, rz) in door_v:
                    wall(cx - rw / 2, z, cx - dw / 2, z)
                    wall(cx + dw / 2, z, cx + rw / 2, z)
                else:
                    wall(cx - rw / 2, z, cx + rw / 2, z)
    # furniture
    for i, (cx, cz, t) in enumerate(rooms):
        n = 1 if i == 0 else rng.randint(2, 3)
        spots = [(-1, -1), (1, -1), (-1, 1), (1, 1), (0, -1), (0, 1), (-1, 0), (1, 0)]
        rng.shuffle(spots)
        for k in range(n):
            sx, sz = spots[k]
            fx, fz = cx + sx * (rw / 2 - 1.5), cz + sz * (rd / 2 - 1.5)
            items.append((fz + 0.6, "f", (fx, fz, rng.uniform(0.55, 0.95), rng.uniform(0.55, 0.95), rng.uniform(0.7, 1.4), rng.choice(FURN))))
    # trees
    for t in range(10):
        a = t * math.tau / 10
        r = max(tw, td) * 0.5 + 8
        items.append((r * math.sin(a), "t", (r * math.cos(a) * 1.0, r * math.sin(a) * 0.9)))
    for _, kind, v in sorted(items, key=lambda it: it[0]):
        if kind == "w":
            x0, z0, x1, z1 = v
            s.d.polygon([s.P(x0, z0, 0), s.P(x1, z1, 0), s.P(x1, z1, wall_h), s.P(x0, z0, wall_h)], fill=wall_col, outline=(150, 125, 95))
            s.d.line([s.P(x0, z0, wall_h), s.P(x1, z1, wall_h)], fill=(255, 252, 240), width=5)
        elif kind == "f":
            fx, fz, hx, hz, h, col = v
            s.d.polygon([s.P(fx - hx, fz + hz, 0), s.P(fx + hx, fz + hz, 0), s.P(fx + hx, fz + hz, h), s.P(fx - hx, fz + hz, h)], fill=shade(col, 0.75))
            s.d.polygon([s.P(fx - hx, fz - hz, h), s.P(fx + hx, fz - hz, h), s.P(fx + hx, fz + hz, h), s.P(fx - hx, fz + hz, h)], fill=col)
        else:
            tx, tz = v
            b, top = s.P(tx, tz, 0), s.P(tx, tz, 4.2)
            s.d.line([b, top], fill=(128, 84, 51), width=int(s.S * 0.6))
            r = s.S * 2.0
            s.d.ellipse([top[0] - r, top[1] - r, top[0] + r, top[1] + r], fill=(77, 184, 89), outline=(50, 140, 65), width=3)
    s.save(name)


def main():
    os.makedirs("assets/maps", exist_ok=True)
    map_cloud()
    map_ring()
    map_tiles()
    map_islands()
    map_donut()
    house(4, 3, 8.0, 8.0, 7771, 25, 290, "assets/maps/map_5.png")   # Villa
    house(3, 2, 7.0, 7.0, 4242, 29, 290, "assets/maps/map_6.png")   # Apartment
    print("done")


if __name__ == "__main__":
    main()
