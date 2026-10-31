"""Build the mess floor props and the full-bin variant, export them, and render their plates.

Run (headless, reproducible), build and export first, then the plates:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\build_mess_props.py'
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\build_mess_props.py' -- plates

The look is decision cleaner-staff-and-messes-visits-leave-messes-bins-fill-pooled-cleaners-
nearest-mess, answer 7: small flat low-poly toon floor props per mess type, readable at the
default zoom, visibly larger when grown. A grid cell is 1 m (CELL_MM in game/baggage/bag.gd
and game/passengers/standing_spots.gd).

Pieces, written to game/assets/mess/ (one .glb each, a normal and a grown size):
- mess_spill, mess_spill_grown: a cafe drink spill. A coffee-brown puddle with a darker
  rim, white wet highlights, and a tipped paper cup at the edge (two cups when grown).
- mess_litter, mess_litter_grown: crumpled wrappers, flat wrappers and a crushed cup in
  bright colours; the grown pile adds a fries carton with spilled fries.
- mess_smear, mess_smear_grown: the toilet and shower room mess. A pale dirty-water
  puddle with olive-brown smear streaks, dark flecks and a trail of muddy footprints.
Normal props fit inside one cell (0.7-1.0 m across); grown props span 1.5-2.0 m.
Everything is at most MAX_H tall (thin, so a passenger's foot passes through without a
visible block), starts at 1 mm above the floor (no z-fighting with the floor tile), and
never needs to block a path.

The full bin, written to game/assets/decor/tc_trash_can_1a_full.glb: the existing
tc_trash_can_1a.glb re-imported unchanged (its atlas rebound on import) with rubbish
heaped on the lid, wrappers hanging from under the lid brim, a tied sack and loose
wrappers on the floor beside it. Same origin and facing as the empty bin, so the game can
swap one for the other.

Conventions are build_interior_kit.py's (origin at the footprint centre on the floor,
Blender -Y is Godot +Z, every face UV-mapped onto a measured swatch of the shared atlas,
material names exactly the ones toon_post_import.gd binds, no images in the glTF). Each
written file is re-read: GLB JSON (materials, images, nodes) and a re-import (bounds
against the built scene, UVs inside their swatches). Any mismatch prints KIT_FAIL and
exits 1.

The plates (tools/blender/out/mess-props/, gitignored) re-import the WRITTEN files:
six_axis/<piece>.png (six orthographic views at true scale with a 1 m reference cube),
distance_80m.png (the tycoon camera at its 80 m home distance, every prop on the real
floor tiles, with a 4x nearest-neighbour crop distance_80m_crop.png), distance_30m.png
(passengers standing in the grown props), close_<piece>.png (the camera at 6 m, a
passenger standing in each grown prop and beside the full bin) and contact_sheet.png.
Each plate proves its subjects in frame and visible (render_activities_plates'
prove_in_frame and visible_share) or prints PROBE_INVALID and exits 1. A Blender plate
is not the in-engine look: the toon ramp and outline are judged in a windowed Godot run.
"""

import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "interior"))
import build_interior_kit as kit  # noqa: E402

MESS_DIR = os.path.join(kit.REPO, "game", "assets", "mess")
DECOR_DIR = os.path.join(kit.REPO, "game", "assets", "decor")
OUT = os.path.join(kit.REPO, "tools", "blender", "out", "mess-props")
BLEND_OUT = os.path.join(OUT, "mess_props.blend")
BIN_SRC = os.path.join(DECOR_DIR, "tc_trash_can_1a.glb")
BIN_FULL = "tc_trash_can_1a_full"
BIN_MAT = "TC_Building_4A_D"
BIN_PNG = "tc_building_4a_d.png"

MAX_H = 0.05  # the tallest part of any floor prop (the crushed cup), metres
Z0 = 0.001  # every floor part starts 1 mm above the walking surface
# Across-size bands (the larger of the two horizontal extents), metres.
BANDS = {"normal": (0.70, 1.00), "grown": (1.50, 2.00)}

# Swatches (TP_Atlas_1A_D column, row, fraction down the swatch), sampled by
# tools/blender/out/mess-props/atlas_grid.py. The floor tile is c14 r14 (about d5cec3),
# so every mess colour is darker or more saturated than it.
MESS_PALETTE = {
    "coffee": ("TP_Atlas_1A_D", 8, 14, 0.40, 0.0),  # mid brown, about 8a6a50
    "coffee_dark": ("TP_Atlas_1A_D", 8, 14, 0.80, 0.0),  # dark brown rim, about 5a3a2a
    "white": kit.PALETTE["white"],
    "red": ("TP_Atlas_1A_D", 31, 0, 0.30, 0.0),
    "sun": ("TP_Atlas_1A_D", 28, 0, 0.30, 0.0),
    "kid_blue": ("TP_Atlas_1A_D", 25, 0, 0.30, 0.0),
    "kid_green": ("TP_Atlas_1A_D", 27, 0, 0.30, 0.0),
    "water": ("TP_Atlas_1A_D", 4, 5, 0.30, 0.0),  # dull dirty teal, about 629ca1
    "olive": ("TP_Atlas_1A_D", 24, 2, 0.50, 0.0),  # murky olive, about 6b7212
    "olive_dark": ("TP_Atlas_1A_D", 24, 3, 0.75, 0.0),  # dark olive, about 454c1f
    "sack": ("TP_Atlas_1A_D", 3, 15, 0.35, 0.0),  # bin-bag grey, about 444444
}


# ---------------------------------------------------------------- geometry
# Blender frame: x = Godot x, -y = Godot +Z, z = up.


def blob(rng, rx, ry, n=24, amps=((2, 0.10), (3, 0.08), (5, 0.05))):
    """An irregular closed outline (counter-clockwise from above) of radii rx by ry."""
    terms = [(k, a * rng.uniform(0.6, 1.0), rng.uniform(0.0, 2.0 * math.pi)) for k, a in amps]
    pts = []
    for i in range(n):
        t = 2.0 * math.pi * i / n
        f = 1.0 + sum(a * math.cos(k * t + ph) for k, a, ph in terms)
        f = max(0.55, f)
        pts.append((rx * f * math.cos(t), ry * f * math.sin(t)))
    return pts


def place2d(pts, x, y, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    return [(x + px * c - py * s, y + px * s + py * c) for px, py in pts]


def prism(name, pts, z0, z1, pal, parent, c):
    """A flat slab: the outline `pts` (Blender xy) extruded from z0 to z1."""
    area = sum(pts[i][0] * pts[i - 1][1] - pts[i - 1][0] * pts[i][1] for i in range(len(pts)))
    if area > 0.0:  # the shoelace sum above is negative for counter-clockwise
        pts = list(reversed(pts))
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return kit._finish_mesh(name, bm, pal, parent, c)


def lump(name, rng, x, y, z_base, r, h, pal, parent, c, subdiv=1, jitter=0.22, sink=0.0, xf=None):
    """A crumpled ball or a sack: a jittered icosphere r wide and h tall, its lowest point
    at z_base - sink. `xf` (a 3x3) tilts it before placing."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in bm.verts:
        v.co = v.co * (1.0 + rng.uniform(-jitter, jitter))
    bmesh.ops.scale(bm, vec=Vector((r, r * rng.uniform(0.8, 1.0), h / 2.0)), verts=bm.verts)
    rot = Matrix.Rotation(rng.uniform(0.0, 2.0 * math.pi), 3, "Z")
    if xf is not None:
        rot = xf @ rot
    bmesh.ops.transform(bm, matrix=rot.to_4x4(), verts=bm.verts)
    zmin = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, vec=Vector((x, y, z_base - sink - zmin)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def cup_lying(name, x, y, yaw, length, r_base, r_mouth, flat, pal, band, parent, c):
    """A crushed paper cup on its side: a frustum along the floor, squashed to `flat` of
    its round height, with a coloured band near the mouth. Returns the body."""
    out = []
    for part, (z0, z1, rb, rm, p) in {
        "Body": (0.0, length, r_base, r_mouth, pal),
        "Band": (length * 0.62, length * 0.86, r_base + (r_mouth - r_base) * 0.62 + 0.003,
                 r_base + (r_mouth - r_base) * 0.86 + 0.003, band),
    }.items():
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=rb, radius2=rm, depth=z1 - z0)
        bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, (z0 + z1) / 2.0 - length / 2.0)), verts=bm.verts)
        m = (Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(yaw, 4, "Z")
             @ Matrix.Diagonal((1.0, 1.0, flat, 1.0)) @ Matrix.Rotation(math.pi / 2.0, 4, "Y"))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        out.append((name + "_" + part, bm, p))
    zmin = min(v.co.z for _n, bm, _p in out for v in bm.verts)
    for n, bm, p in out:
        bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, Z0 - zmin)), verts=bm.verts)
        kit._finish_mesh(n, bm, p, parent, c)


def wrapper(name, rng, x, y, length, width, pal, parent, c, z0=Z0, label=True):
    """A flat crinkled wrapper: a jagged rectangle 4 mm thick with a white label stripe."""
    hl, hw = length / 2.0, width / 2.0
    pts = [(-hl, -hw), (0.0, -hw * 1.1), (hl, -hw), (hl * 1.08, 0.0), (hl, hw), (0.0, hw * 0.95),
           (-hl, hw), (-hl * 1.1, 0.0)]
    pts = [(px + rng.uniform(-0.12, 0.12) * width, py + rng.uniform(-0.12, 0.12) * width) for px, py in pts]
    yaw = rng.uniform(0.0, math.pi)
    prism(name, place2d(pts, x, y, yaw), z0, z0 + 0.004, pal, parent, c)
    if label:
        stripe = [(-hl * 0.55, -hw * 0.35), (hl * 0.55, -hw * 0.35), (hl * 0.55, hw * 0.35), (-hl * 0.55, hw * 0.35)]
        prism(name + "_Label", place2d(stripe, x, y, yaw), z0, z0 + 0.0065, "white", parent, c)


def footprint(name, x, y, yaw, pal, parent, c):
    """A muddy shoe print: a sole and a separate heel, 0.26 m long."""
    sole = [(0.02 + 0.07 * math.cos(t), 0.042 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 10, endpoint=False)]
    heel = [(-0.085 + 0.035 * math.cos(t), 0.036 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
    prism(name + "_Sole", place2d(sole, x, y, yaw), Z0, Z0 + 0.003, pal, parent, c)
    prism(name + "_Heel", place2d(heel, x, y, yaw), Z0, Z0 + 0.003, pal, parent, c)


# ---------------------------------------------------------------- floor props


def build_spill(root, c, grown):
    rng = random.Random(11 if grown else 7)
    r = 0.80 if grown else 0.40
    rim = blob(rng, r, r * 0.82, n=28)
    prism("Spill_Rim", rim, Z0, 0.008, "coffee_dark", root, c)
    prism("Spill_Pool", [(px * 0.86, py * 0.86) for px, py in rim], Z0, 0.011, "coffee", root, c)
    # Splash droplets round the edge.
    for i in range(7 if grown else 4):
        t = rng.uniform(0.0, 2.0 * math.pi)
        d = r * rng.uniform(1.04, 1.16)
        s = r * rng.uniform(0.05, 0.09)
        prism("Spill_Drop_%d" % i, place2d(blob(rng, s, s * 0.8, n=10), d * math.cos(t), 0.82 * d * math.sin(t), t),
              Z0, 0.008, "coffee_dark", root, c)
    # Wet highlights.
    for i, (hx, hy, hr) in enumerate([(-0.30, 0.28, 0.12), (-0.10, 0.38, 0.06), (0.25, -0.20, 0.07)]):
        prism("Spill_Shine_%d" % i, place2d(blob(rng, hr * r, hr * r * 0.45, n=10, amps=((2, 0.05),)),
                                            hx * r, hy * r, 0.5), Z0, 0.013, "white", root, c)
    # The tipped cup at the edge, mouth toward the pool.
    cups = [(math.radians(-35.0))] + ([math.radians(150.0)] if grown else [])
    for i, t in enumerate(cups):
        d = r * 0.95
        cup_lying("Spill_Cup_%d" % i, d * math.cos(t), 0.82 * d * math.sin(t), t + math.pi, 0.16, 0.030, 0.042,
                  0.50, "white", "red", root, c)


def build_litter(root, c, grown):
    rng = random.Random(23 if grown else 5)
    spread = 0.75 if grown else 0.36
    colours = ["red", "sun", "kid_blue", "white", "kid_green"]
    spots = []

    def spot(clear):
        for _try in range(200):
            t = rng.uniform(0.0, 2.0 * math.pi)
            d = spread * math.sqrt(rng.uniform(0.0, 1.0))
            p = (d * math.cos(t), d * math.sin(t))
            if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 > (clear + qc) ** 2 for q, qc in spots):
                spots.append((p, clear))
                return p
        raise RuntimeError("litter: no free spot")

    n_ball, n_wrap = (7, 7) if grown else (3, 3)
    for i in range(n_ball):
        x, y = spot(0.09)
        lump("Litter_Ball_%d" % i, rng, x, y, Z0, rng.uniform(0.07, 0.09), 0.038, colours[i % len(colours)],
             root, c)
    for i in range(n_wrap):
        x, y = spot(0.13)
        wrapper("Litter_Wrap_%d" % i, rng, x, y, rng.uniform(0.22, 0.28), rng.uniform(0.14, 0.18),
                colours[(i + 2) % len(colours)], root, c)
    for i in range(2 if grown else 1):
        x, y = spot(0.10)
        cup_lying("Litter_Cup_%d" % i, x, y, rng.uniform(0.0, 2.0 * math.pi), 0.16, 0.030, 0.042, 0.50,
                  "white", "kid_blue" if i else "red", root, c)
    if grown:
        # A fries carton on its side with fries spilled out of it.
        x, y = spot(0.16)
        yaw = rng.uniform(0.0, 2.0 * math.pi)
        box = [(-0.07, -0.05), (0.07, -0.05), (0.07, 0.05), (-0.07, 0.05)]
        prism("Litter_Carton", place2d(box, x, y, yaw), Z0, 0.04, "red", root, c)
        for k in range(6):
            fx, fy = 0.10 + rng.uniform(0.0, 0.10), rng.uniform(-0.07, 0.07)
            stick = place2d([(-0.05, -0.011), (0.05, -0.011), (0.05, 0.011), (-0.05, 0.011)], fx, fy,
                            rng.uniform(-0.8, 0.8))
            prism("Litter_Fry_%d" % k, place2d(stick, x, y, yaw), Z0, 0.012, "sun", root, c)


def build_smear(root, c, grown):
    rng = random.Random(31 if grown else 3)
    rx, ry = (0.70, 0.50) if grown else (0.36, 0.26)
    water = blob(rng, rx, ry, n=28, amps=((2, 0.12), (3, 0.10), (4, 0.06)))
    prism("Smear_Water", water, Z0, 0.006, "water", root, c)
    # Smear streaks: long olive blobs across the water, as if wiped or trodden.
    n_streak = 6 if grown else 3
    for i in range(n_streak):
        t = (i + 0.5) / n_streak
        x = (t - 0.5) * rx * 1.3 + rng.uniform(-0.05, 0.05)
        y = rng.uniform(-0.35, 0.35) * ry
        ln = rx * rng.uniform(0.32, 0.45)
        prism("Smear_Streak_%d" % i, place2d(blob(rng, ln, ln * 0.22, n=14, amps=((2, 0.06), (3, 0.08))), x, y,
                                             rng.uniform(-0.5, 0.5)), Z0, 0.010, "olive", root, c)
    for i in range(8 if grown else 4):
        t = rng.uniform(0.0, 2.0 * math.pi)
        d = rng.uniform(0.2, 0.85)
        s = rng.uniform(0.025, 0.045)
        prism("Smear_Fleck_%d" % i, place2d(blob(rng, s, s * 0.8, n=8), d * rx * math.cos(t), d * ry * math.sin(t),
                                            t), Z0, 0.012, "olive_dark", root, c)
    # Muddy footprints walking out of the puddle toward Godot +X.
    steps = 3 if grown else 2
    for i in range(steps):
        x = (0.40 + i * 0.30) if grown else (0.12 + i * 0.26)
        y = (0.07 if i % 2 else -0.07)
        footprint("Smear_Print_%d" % i, x, y, 0.0, "olive_dark", root, c)


PROPS = {
    "mess_spill": (build_spill, False),
    "mess_spill_grown": (build_spill, True),
    "mess_litter": (build_litter, False),
    "mess_litter_grown": (build_litter, True),
    "mess_smear": (build_smear, False),
    "mess_smear_grown": (build_smear, True),
}


def register():
    """Add the mess swatches and pieces to the kit's tables (bounds filled at build)."""
    kit.PALETTE.update(MESS_PALETTE)
    for piece, (builder, grown) in PROPS.items():
        kit.PIECES[piece] = ((lambda b, g: lambda root, c: b(root, c, g))(builder, grown), (1, 1), None, None)


def mesh_bounds(objs):
    pts = [o.matrix_world @ v.co for o in objs if o.type == "MESH" for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def check_band(piece, lo, hi):
    size = hi - lo
    across = max(size.x, size.y)
    band = BANDS["grown" if piece.endswith("_grown") else "normal"]
    kit.log("MESS %s across=%.3f band=%s height=%.4f max_h=%.3f bottom=%.4f"
            % (piece, across, band, hi.z, MAX_H, lo.z))
    if not band[0] <= across <= band[1]:
        kit.fail("%s: %.3f m across, outside the %s band" % (piece, across, band))
    if hi.z > MAX_H or lo.z < 0.0:
        kit.fail("%s: height %.4f..%.4f outside 0..%.3f" % (piece, lo.z, hi.z, MAX_H))


# ---------------------------------------------------------------- the full bin
# The empty bin, measured by re-import (tools/blender/out/mess-props/bin_probe.py): body
# r 0.385 at the floor to 0.465 at 0.918, a lid brim r 0.532 from 0.918 to 1.104, a dome
# to r 0.322 at 1.265 and a cap r 0.161 to 1.392.
BIN_BRIM_Z = (0.918, 1.104)
BIN_TOP_Z = 1.265
BIN_TOP_R = 0.322
BIN_BRIM_R = 0.514
BIN_MAX_H = 1.60


def lid_surface(r):
    if r <= BIN_TOP_R:
        return BIN_TOP_Z
    f = min(1.0, (r - BIN_TOP_R) / (BIN_BRIM_R - BIN_TOP_R))
    return BIN_TOP_Z + (BIN_BRIM_Z[1] - BIN_TOP_Z) * f


def import_bin():
    """Import the written empty bin and rebind its atlas; returns its mesh object."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BIN_SRC)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    if len(meshes) != 1:
        kit.fail("bin: %d meshes in %s, expected 1" % (len(meshes), BIN_SRC))
    ob = meshes[0]
    mats = [m for m in ob.data.materials]
    if [m.name for m in mats] != [BIN_MAT]:
        kit.fail("bin: materials %s, expected [%s]" % ([m.name for m in mats], BIN_MAT))
    img = bpy.data.images.load(os.path.join(kit.TEXTURES, BIN_PNG), check_existing=True)
    rebound = 0
    for m in mats:
        for node in m.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                node.image = img
                node.interpolation = "Closest"
                rebound += 1
    kit.log("REBIND bin material=%s tex_nodes=%d image=%s images_in_file=%d materials_in_file=%d"
            % (BIN_MAT, rebound, img.name, len(bpy.data.images), len(bpy.data.materials)))
    if rebound == 0:
        kit.fail("bin: no image node to rebind on %s" % BIN_MAT)
    return ob


# The heap over the lid: (radius, height) rings from its foot, sunk just inside the dome
# below the brim top, to its crown, which clears the cap (1.392) by about 0.1 m.
HEAP_RINGS = ((0.49, 1.10), (0.40, 1.30), (0.22, 1.44), (0.0, 1.49))


def heap_surface(r):
    for (r0, z0), (r1, z1) in zip(HEAP_RINGS, HEAP_RINGS[1:]):
        if r1 <= r <= r0:
            return z1 + (z0 - z1) * (r - r1) / (r0 - r1)
    return lid_surface(r)


def mound(name, rng, rings, segs, pal, parent, c):
    """A jittered low-poly pile: rings of (radius, height), the last one the apex."""
    bm = bmesh.new()
    loops = []
    for r, z in rings[:-1]:
        loops.append([bm.verts.new((r * (1.0 + rng.uniform(-0.08, 0.08)) * math.cos(2 * math.pi * k / segs + 0.3 * z),
                                    r * (1.0 + rng.uniform(-0.08, 0.08)) * math.sin(2 * math.pi * k / segs + 0.3 * z),
                                    z + rng.uniform(-0.015, 0.015))) for k in range(segs)])
    apex = bm.verts.new((0.0, 0.0, rings[-1][1]))
    bm.faces.new(list(reversed(loops[0])))
    for a, b in zip(loops, loops[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((a[k], a[j], b[j], b[k]))
    for k in range(segs):
        bm.faces.new((loops[-1][k], loops[-1][(k + 1) % segs], apex))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return kit._finish_mesh(name, bm, pal, parent, c)


def build_bin_rubbish(root, c):
    rng = random.Random(41)
    colours = ["red", "sun", "kid_blue", "coffee", "kid_green"]  # no white on the white heap
    mound("Rubbish_Heap", rng, HEAP_RINGS, 10, "white", root, c)  # paper, light against the dark bin
    # Crumpled wrappers on the heap and down to the brim.
    for i in range(16):
        t = 2.0 * math.pi * i / 16 + rng.uniform(-0.2, 0.2)
        r = rng.uniform(0.10, 0.46)
        lump("Rubbish_Ball_%d" % i, rng, r * math.cos(t), r * math.sin(t), heap_surface(r),
             rng.uniform(0.08, 0.11), 0.09, colours[i % len(colours)], root, c, sink=0.03)
    # Wrappers caught under the lid brim, hanging out and down.
    for i, deg in enumerate((25.0, 140.0, 215.0, 305.0)):
        t = math.radians(deg)
        bm = bmesh.new()
        hl, hw = 0.10, 0.065
        pts = [(-hl, -hw), (hl, -hw * 1.1), (hl * 1.05, hw), (-hl, hw * 0.9)]
        bot = [bm.verts.new((px, py, -0.002)) for px, py in pts]
        top = [bm.verts.new((px, py, 0.002)) for px, py in pts]
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for k in range(4):
            j = (k + 1) % 4
            bm.faces.new((bot[k], bot[j], top[j], top[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # Long axis radial, tipped 60 degrees down, the inner end tucked under the brim.
        m = (Matrix.Translation((0.0, 0.0, BIN_BRIM_Z[0] - 0.02)) @ Matrix.Rotation(t, 4, "Z")
             @ Matrix.Translation((BIN_BRIM_R + 0.02, 0.0, 0.0)) @ Matrix.Rotation(math.radians(60.0), 4, "Y"))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        kit._finish_mesh("Rubbish_Hang_%d" % i, bm, colours[(i + 1) % len(colours)], root, c)
    # A tied sack at the front-right corner (Godot +x, +z), leaning on the bin.
    lump("Rubbish_Sack", rng, 0.36, -0.36, Z0, 0.17, 0.34, "sack", root, c, subdiv=2, jitter=0.10)
    kit.cyl("Rubbish_Sack_Tie", 0.36, -0.36, 0.30, 0.38, 0.03, "sack", root, c)
    # Loose litter at the front-left corner.
    lump("Rubbish_Floor_Ball", rng, -0.36, -0.40, Z0, 0.06, 0.038, "red", root, c)
    wrapper("Rubbish_Floor_Wrap", rng, -0.42, -0.25, 0.17, 0.11, "sun", root, c)


def build_full_bin():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    bin_ob = import_bin()
    src_lo, src_hi = mesh_bounds([bin_ob])
    src_polys = len(bin_ob.data.polygons)
    c = bpy.data.collections.new("TrashCan1AFull")
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new("TrashCan1AFull_ROOT", None)
    c.objects.link(root)
    for coll in list(bin_ob.users_collection):
        coll.objects.unlink(bin_ob)
    c.objects.link(bin_ob)
    mw = bin_ob.matrix_world.copy()
    bin_ob.parent = root
    bin_ob.matrix_world = mw
    build_bin_rubbish(root, c)
    bpy.context.view_layer.update()
    parts = [o for o in c.objects if o.type == "MESH" and o is not bin_ob]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    rubbish = bpy.context.view_layer.objects.active
    rubbish.name = "Bin_Rubbish"
    rubbish.data.validate()
    # Drop leftover empties the import made (none expected; the glb has one node).
    for o in list(bpy.data.objects):
        if o.type == "EMPTY" and o is not root:
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    lo, hi = mesh_bounds([bin_ob, rubbish])
    kit.log("BUILT %s bin_polys=%d rubbish_verts=%d bounds_lo=%s bounds_hi=%s"
            % (BIN_FULL, src_polys, len(rubbish.data.vertices), tuple(round(a, 3) for a in lo),
               tuple(round(a, 3) for a in hi)))
    if hi.z > BIN_MAX_H:
        kit.fail("%s: %.3f m tall, over %.2f" % (BIN_FULL, hi.z, BIN_MAX_H))
    out_dir = kit.OUT_DIR
    kit.OUT_DIR = DECOR_DIR
    out = kit.export_piece(BIN_FULL, root, c)
    kit.OUT_DIR = out_dir
    return out, (src_lo, src_hi, src_polys), (lo, hi)


def verify_full_bin(out, src, built):
    src_lo, src_hi, src_polys = src
    js, nbytes = kit.parse_glb(out)
    mats = sorted(m["name"] for m in js.get("materials", []))
    nodes = sorted(n.get("name", "?") for n in js.get("nodes", []))
    kit.log("ASSET %s file=%s bytes=%d nodes=%s materials=%s images=%d meshes=%d"
            % (BIN_FULL, os.path.relpath(out, kit.REPO).replace("\\", "/"), nbytes, nodes, mats,
               len(js.get("images", [])), len(js.get("meshes", []))))
    if nodes != sorted(["TrashCan1AFull_ROOT", "Trash_Can_1A", "Bin_Rubbish"]):
        kit.fail("%s: nodes %s" % (BIN_FULL, nodes))
    if mats != sorted([BIN_MAT, "TP_Atlas_1A_D"]):
        kit.fail("%s: materials %s" % (BIN_FULL, mats))
    if js.get("images"):
        kit.fail("%s: %d images, expected 0" % (BIN_FULL, len(js["images"])))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    by = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
    can, rub = by.get("Trash_Can_1A"), by.get("Bin_Rubbish")
    if can is None or rub is None:
        kit.fail("%s: re-import lacks the bin or the rubbish mesh: %s" % (BIN_FULL, sorted(by)))
        return
    c_lo, c_hi = mesh_bounds([can])
    err = max(max(abs(a - b) for a, b in zip(c_lo, src_lo)), max(abs(a - b) for a, b in zip(c_hi, src_hi)))
    kit.log("BIN %s can_polys=%d (source %d) can_bounds_err_vs_source=%.5f"
            % (BIN_FULL, len(can.data.polygons), src_polys, err))
    if len(can.data.polygons) != src_polys or err > 0.001:
        kit.fail("%s: the bin mesh changed in the export" % BIN_FULL)
    lo, hi = mesh_bounds([can, rub])
    b_err = max(max(abs(a - b) for a, b in zip(lo, built[0])), max(abs(a - b) for a, b in zip(hi, built[1])))
    kit.log("BOUNDS %s godot_min=(%.3f, %.3f, %.3f) godot_max=(%.3f, %.3f, %.3f) err_vs_built=%.4f"
            % (BIN_FULL, lo.x, lo.z, -hi.y, hi.x, hi.z, -lo.y, b_err))
    if b_err > 0.006:
        kit.fail("%s: written bounds differ from the built scene by %.4f m" % (BIN_FULL, b_err))
    # Rubbish UVs inside the intended swatches.
    intended = kit.intended_cells()
    uvl = rub.data.uv_layers.active
    loops = outside = 0
    used = {}
    for poly in rub.data.polygons:
        mname = rub.data.materials[poly.material_index].name.split(".")[0]
        _img, _w, _h, _px, cols, rows = kit.atlas(mname)
        for li in poly.loop_indices:
            u, v = uvl.data[li].uv
            loops += 1
            cell = (mname, int(u * cols), int((1.0 - v) * rows))
            rgb = kit.sample_rgb(mname, u, v)
            used[cell] = rgb
            if cell not in intended or rgb in kit.EMPTY_RGB:
                outside += 1
    kit.log("UV %s rubbish loops=%d outside_swatch=%d swatches=%s" % (BIN_FULL, loops, outside, sorted(used.items())))
    if outside or loops == 0:
        kit.fail("%s: %d rubbish UV loops outside their swatch (of %d)" % (BIN_FULL, outside, loops))


# ---------------------------------------------------------------- build main


def build_main():
    register()
    os.makedirs(MESS_DIR, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    kit.OUT_DIR = MESS_DIR
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.report_palette()
    written = []
    for piece in PROPS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        kit._images.clear()
        kit._materials.clear()
        root, c = kit.build_piece(piece)
        lo, hi = mesh_bounds(list(c.objects))
        check_band(piece, lo, hi)
        builder, foot = kit.PIECES[piece][:2]
        kit.PIECES[piece] = (builder, foot, tuple(lo), tuple(hi))
        written.append((piece, kit.export_piece(piece, root, c)))
    for piece, out in written:
        kit.verify_written(piece, out)
    bin_out, src, built = build_full_bin()
    verify_full_bin(bin_out, src, built)
    # The appendable .blend: the floor props in a row.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    for i, piece in enumerate(PROPS):
        root, _c = kit.build_piece(piece)
        root.location.x = i * 2.5
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=True)
    kit.log("BLEND saved %s" % BLEND_OUT)
    kit.log("KIT done pieces=%d fails=%d" % (len(written) + 1, len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


# ---------------------------------------------------------------- plates


def plates_main():
    import render_activities_plates as rap  # noqa: E402  (plate helpers)
    import render_baggage_plates as rbp  # noqa: E402

    log = rap.log
    base_plate_material = rap.plate_material

    def plate_material(name):
        if rap.base_name(name) == BIN_MAT:
            return rap.toon_material("tc_building_4a", BIN_PNG, "tc_toon_ramp_01a_d.png")
        return base_plate_material(name)

    rap.plate_material = plate_material
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)

    def glb(piece):
        return os.path.join(DECOR_DIR if piece.startswith("tc_") else MESS_DIR, piece + ".glb")

    def place(piece, x, y):
        objs, _a, _n, _h = rap.import_glb(glb(piece), "%s_%.1f_%.1f" % (piece, x, y), Matrix.Translation((x, y, 0.0)))
        return objs

    def save(scene, name):
        arr = rap.render(scene, os.path.join(OUT, name.replace(".png", "_raw.png")))
        out = rap.over(arr, rbp.BACKDROP)
        rap.save_array(out, os.path.join(OUT, name))
        return out

    def six_axis(piece):
        scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
        objs, _a, names, _h = rap.import_glb(glb(piece), piece)
        lo, hi = rap.bounds(objs)
        ref = rap.cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
        sub = rap.world_points(objs)
        ref_pts = rap.world_points([ref])
        allp = np.concatenate([sub, ref_pts])
        scale = 0.0
        for _n, d, up in rap.VIEWS:
            inv = np.array(rap.look_rot(d, up).to_matrix().inverted())
            loc = allp @ inv.T
            scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
        scale /= 1.0 - 2.0 * rap.MARGIN - 0.04
        log("%s six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
            % (piece, sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale))
        tiles = []
        for name, d, up in rap.VIEWS:
            cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
            label = "%s six_axis %s" % (piece, name)
            b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
            b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
            apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
            log("%s cube_disjoint=%s" % (label, apart))
            if not apart:
                rap.invalid("%s: the reference cube overlaps the subject on screen" % label)
            if name == "top":
                # The full bin hides its own lid under the heap, so its bar is lower.
                rap.visible_share(label, scene, cam, objs, need=0.3 if piece == BIN_FULL else 0.5)
            path = os.path.join(OUT, "six_axis", "%s_%s.png" % (piece, name))
            tiles.append(rap.over(rap.render(scene, path), rbp.BACKDROP))
            bpy.data.objects.remove(cam)
        sheet = rap.grid(tiles, 3)
        rap.save_array(sheet, os.path.join(OUT, "six_axis", piece + ".png"))
        return sheet

    # The row layout shared by the distance plates: type columns, normal behind grown.
    columns = [("mess_spill", 1.5), ("mess_litter", 5.0), ("mess_smear", 8.5)]

    def layout(people):
        subjects = {}
        for stem, x in columns:
            subjects[stem] = place(stem, x, 2.5)
            subjects[stem + "_grown"] = place(stem + "_grown", x, -0.5)
        subjects[BIN_FULL] = place(BIN_FULL, 11.5, 2.5)
        subjects["tc_trash_can_1a"] = place("tc_trash_can_1a", 11.5, -0.5)
        if people:
            for stem, x in columns:
                subjects["person_" + stem] = rbp.person("male" if stem != "mess_litter" else "female", x + 0.15,
                                                        -0.45, 20.0, stem)
        rbp.floor_tiles(-1, 14, -3, 5)
        return subjects

    def distance(dist, name, people, need):
        scene = rap.reset_scene(1920, 1080, 1.0)
        subjects = layout(people)
        cam = rbp.game_camera(scene, Vector((6.5, 1.0, 0.0)), dist, 0.0)
        boxes = {}
        for label, objs in subjects.items():
            b = rap.screen_box(scene, cam, rap.world_points(objs))
            boxes[label] = b
            log("%s %s width_px=%.1f height_px=%.1f" % (name, label, (b[2] - b[0]) * 1920, (b[3] - b[1]) * 1080))
            rbp.prove("%s %s" % (name, label), scene, cam, objs, need=need if not label.startswith("person") else 0.3)
        return save(scene, name + ".png"), boxes

    def crop(arr, boxes, factor, name):
        u0 = min(b[0] for b in boxes.values()) - 0.01
        u1 = max(b[2] for b in boxes.values()) + 0.01
        v0 = min(b[1] for b in boxes.values()) - 0.01
        v1 = max(b[3] for b in boxes.values()) + 0.01
        h, w = arr.shape[:2]
        sub = arr[int(v0 * h):int(math.ceil(v1 * h)), int(u0 * w):int(math.ceil(u1 * w))]
        big = np.repeat(np.repeat(sub, factor, axis=0), factor, axis=1)
        log("%s crop px=(%d, %d) scaled x%d" % (name, sub.shape[1], sub.shape[0], factor))
        rap.save_array(big, os.path.join(OUT, name))
        return big

    def close(piece, x_off):
        scene = rap.reset_scene(1280, 720, 1.5)
        subjects = {piece: place(piece, 0.0, 0.0)}
        subjects["person"] = rbp.person("male", x_off, 0.05, 25.0, piece)
        rbp.floor_tiles(-3, 4, -3, 4)
        cam = rbp.game_camera(scene, Vector((0.0, 0.0, 0.3)), 6.0, -20.0)
        for label, objs in subjects.items():
            rbp.prove("close %s %s" % (piece, label), scene, cam, objs, need=0.25)
        return save(scene, "close_%s.png" % piece)

    sheets = [six_axis(p) for p in list(PROPS) + [BIN_FULL]]
    far, far_boxes = distance(80.0, "distance_80m", False, 0.5)
    far_crop = crop(far, {k: v for k, v in far_boxes.items()}, 4, "distance_80m_crop.png")
    mid, _b = distance(30.0, "distance_30m", True, 0.3)
    closes = [close(p, 0.12) for p in ("mess_spill_grown", "mess_litter_grown", "mess_smear_grown")]
    closes.append(close(BIN_FULL, 0.85))
    tiles = [rap.downscale(s, 2) for s in sheets] + [rap.downscale(far_crop, 2), rap.downscale(mid, 2)]
    tiles += [rap.downscale(t, 2) for t in closes]
    rap.save_array(rap.grid(tiles, 4), os.path.join(OUT, "contact_sheet.png"))
    log("contact_sheet tiles=%d" % len(tiles))
    if rap.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv == ["plates"]:
        register()
        plates_main()
    else:
        build_main()
