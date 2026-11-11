#!/usr/bin/env python3
"""Illustrations for maps 20-22 (Ice Rink, Conveyor Mill, Wind Tunnel). Same look as gen_map_thumbs.py.
Run from the project root:  python3 tools/gen_hazard_thumbs.py   (needs Pillow)"""
import importlib.util, math, os, sys
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("gmt", os.path.join(here, "gen_map_thumbs.py"))
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
Scene, shade = g.Scene, g.shade


def bumper(s, x, z, col):
    top = s.P(x, z, 1.2)
    base = s.P(x, z, 0.0)
    r = s.S * 0.75
    s.d.polygon([(base[0] - r, base[1]), (base[0] + r, base[1]), (top[0] + r, top[1]), (top[0] - r, top[1])], fill=shade(col, 0.8))
    s.d.ellipse([base[0] - r, base[1] - r * 0.4, base[0] + r, base[1] + r * 0.4], fill=shade(col, 0.8))
    s.d.ellipse([top[0] - r, top[1] - r * 0.4, top[0] + r, top[1] + r * 0.4], fill=col)


def ice_rink():
    s = Scene(28, 300)
    s.disc(0, 0, 9, (199, 237, 255), (64, 102, 179), 1.2)
    s.quad(0, 0, 3.2, 3.2, 0, 0.02, (150, 225, 255), (255, 255, 255))
    for i in range(4):
        s.d.line([s.P(-2.6 + i * 1.2, -2.0 + i * 1.0, 0.03), s.P(-1.2 + i * 1.2, -1.2 + i * 1.0, 0.03)], fill=(255, 255, 255), width=3)
    for a in (math.pi / 2, math.pi / 2 + math.tau / 3, math.pi / 2 + 2 * math.tau / 3):
        bumper(s, 5.85 * math.cos(a), 5.85 * math.sin(a), (77, 191, 255))
    s.sweeper(0, 0, 3.0, (242, 69, 69), 0.6)
    s.save("assets/maps/map_20.png")


def conveyor_mill():
    s = Scene(23, 300)
    s.slab(0, 0, 10, 10, 0, 1.0, (140, 153, 179))
    s.slab(0, 0, 7, 7, 0, 0.1, (166, 178, 199))
    s.quad(0, 0, 4.6, 4.6, 0, 0.0, (190, 200, 218))
    belts = [(0, -5.5, 0.0), (5.5, 0, math.pi / 2), (0, 5.5, math.pi), (-5.5, 0, -math.pi / 2)]
    for cx, cz, ang in belts:
        s.quad(cx, cz, 4.3, 1.3, ang if ang in (0.0, math.pi) else ang, 0.03, (56, 61, 77))
        c, sn = math.cos(ang), math.sin(ang)
        # arrow chevrons along the direction of travel (clockwise)
        dx, dz = (1, 0) if cx == 0 and cz < 0 else (0, 1) if cx > 0 else (-1, 0) if cz > 0 else (0, -1)
        for k in (-2.4, -0.4, 1.6):
            px, pz = cx + dx * k, cz + dz * k
            tip = s.P(px + dx * 0.7, pz + dz * 0.7, 0.05)
            a1 = s.P(px - dx * 0.2 + dz * 0.7, pz - dz * 0.2 + dx * 0.7, 0.05)
            a2 = s.P(px - dx * 0.2 - dz * 0.7, pz - dz * 0.2 - dx * 0.7, 0.05)
            s.d.line([a1, tip, a2], fill=(255, 217, 38), width=5)
    s.sweeper(0, 0, 3.0, (242, 69, 69), 0.5)
    s.save("assets/maps/map_21.png")


def wind_tunnel():
    s = Scene(26, 300)
    s.disc(0, 0, 9.5, (128, 217, 179), (51, 102, 115), 1.2)
    fans = [(-8.3, -3.8, 1, 0), (3.8, -8.3, 0, 1), (8.3, 3.8, -1, 0), (-3.8, 8.3, 0, -1)]
    for fx, fz, dx, dz in fans:
        for k in range(1, 5):
            for off in (-1.2, 0, 1.2):
                a = s.P(fx + dx * (1 + k * 2.4) - dz * off, fz + dz * (1 + k * 2.4) + dx * off, 0.8)
                b = s.P(fx + dx * (2.2 + k * 2.4) - dz * off, fz + dz * (2.2 + k * 2.4) + dx * off, 0.8)
                s.d.line([a, b], fill=(235, 250, 255), width=4)
        p = s.P(fx, fz, 1.3)
        r = s.S * 0.95
        s.d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(217, 51, 51), outline=(255, 255, 255), width=3)
        s.d.ellipse([p[0] - r * 0.7, p[1] - r * 0.7, p[0] + r * 0.7, p[1] + r * 0.7], fill=(240, 240, 250))
    s.hammer(0, 0, 2.2, (242, 69, 69), 1.0)
    s.save("assets/maps/map_22.png")


if __name__ == "__main__":
    os.makedirs("assets/maps", exist_ok=True)
    ice_rink(); conveyor_mill(); wind_tunnel()
    print("done")
