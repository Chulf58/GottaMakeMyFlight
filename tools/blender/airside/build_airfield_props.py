"""Build newly authored Toon airside airfield fixtures and export one .glb each.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\build_airfield_props.py' [-- piece ...]

Pieces (written to game/assets/airside/props/<piece>.glb):
- taxi_edge_light: low-profile ground-flush taxiway blue edge light (0.38 m tall).
- runway_edge_light_white: low-profile white runway edge light (0.40 m tall).
- runway_edge_light_amber: low-profile amber runway caution-zone edge light (0.40 m tall).
- runway_threshold_light: low-profile bidirectional green/red threshold wingbar light (0.34 m tall).
- papi_light_bank: 4-unit PAPI glidepath indicator bank (2 red / 2 white, 0.42 m tall).
- windsock: 6.5 m red-and-white mast with 5-band orange-and-white tapered windsock.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "interior"))
import build_interior_kit as kit  # noqa: E402

kit.OUT_DIR = os.path.join(kit.REPO, "game", "assets", "airside", "props")
BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "airfield_overhaul", "airfield_props.blend")

kit.PALETTE.update({
    "sign_yellow": ("TP_Atlas_1A_D", 9, 13, 0.45, 0.0),
    "ink": ("TP_Atlas_1A_D", 3, 15, 0.85, 0.0),
    "concrete": ("TP_Atlas_1A_D", 2, 15, 0.30, 0.0),
    "red": ("TP_Atlas_1A_D", 31, 0, 0.40, 0.20),
    "windsock_orange": ("TP_Atlas_1A_D", 15, 5, 0.30, 0.25),
    "light_blue": ("TP_Atlas_Lights_1A_D", 1, 2, 0.50, 0.0),
    "light_white": ("TP_Atlas_Lights_1A_D", 9, 0, 0.50, 0.0),
    "light_amber": ("TP_Atlas_Lights_1A_D", 3, 1, 0.50, 0.0),
    "light_green": ("TP_Atlas_Lights_1A_D", 4, 0, 0.50, 0.0),
    "light_red": ("TP_Atlas_Lights_1A_D", 3, 0, 0.50, 0.0),
})


def gb(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


def gbox(name, lo, hi, pal, parent, c, bevel=0.0):
    return kit.box(name, (lo[0], -hi[2], lo[1]), (hi[0], -lo[2], hi[1]), pal, parent, c, bevel=bevel)


def gfrustum(name, x, z, y0, y1, r0, r1, pal, parent, c, segs=12):
    """Vertical frustum/cylinder on Godot (x, z) from height y0 to y1 with radii r0..r1."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=y1 - y0,
    )
    bmesh.ops.translate(bm, vec=Vector((x, -z, (y0 + y1) / 2.0)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def gtube_segment(name, p0_g, p1_g, r0, r1, pal, parent, c, segs=12):
    """Tapered hollow-or-solid tube segment between two Godot points p0_g -> p1_g."""
    a = Vector(gb(*p0_g))
    b = Vector(gb(*p1_g))
    axis = b - a
    length = axis.length
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
    )
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=(a + b) * 0.5, verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def build_edge_light(lens_pal, total_h, base_r, stem_r, lens_r, root, c):
    """Reusable low-profile airfield edge light fixture."""
    gfrustum("BasePad", 0.0, 0.0, 0.0, 0.04, base_r, base_r * 0.94, "concrete", root, c, segs=12)
    gfrustum("CollarLow", 0.0, 0.0, 0.04, 0.075, base_r * 0.68, base_r * 0.62, "ink", root, c, segs=12)
    stem_top = total_h * 0.48
    gfrustum("Stem", 0.0, 0.0, 0.075, stem_top, stem_r, stem_r * 0.95, "sign_yellow", root, c, segs=10)
    bezel_top = stem_top + 0.04
    gfrustum("Bezel", 0.0, 0.0, stem_top, bezel_top, lens_r * 1.12, lens_r * 1.10, "ink", root, c, segs=12)
    lens_top = total_h - 0.035
    gfrustum("LensBody", 0.0, 0.0, bezel_top, lens_top - 0.03, lens_r, lens_r * 0.95, lens_pal, root, c, segs=12)
    gfrustum("LensCrown", 0.0, 0.0, lens_top - 0.03, lens_top, lens_r * 0.95, lens_r * 0.55, lens_pal, root, c, segs=12)
    gfrustum("RainCap", 0.0, 0.0, lens_top, total_h, lens_r * 0.85, lens_r * 0.30, "ink", root, c, segs=12)


def build_taxi_edge_light(root, c):
    build_edge_light("light_blue", 0.38, 0.16, 0.055, 0.095, root, c)


def build_runway_edge_light_white(root, c):
    build_edge_light("light_white", 0.40, 0.18, 0.06, 0.105, root, c)


def build_runway_edge_light_amber(root, c):
    build_edge_light("light_amber", 0.40, 0.18, 0.06, 0.105, root, c)


def build_runway_threshold_light(root, c):
    """Low-profile bidirectional threshold wingbar: green facing +Z (approach), red facing -Z (runway)."""
    gbox("FootPad", (-0.27, 0.0, -0.13), (0.27, 0.045, 0.13), "concrete", root, c)
    gbox("Housing", (-0.24, 0.045, -0.10), (0.24, 0.29, 0.10), "ink", root, c, bevel=0.01)
    gbox("TopCap", (-0.25, 0.29, -0.11), (0.25, 0.34, 0.11), "sign_yellow", root, c, bevel=0.008)
    for sx in (-0.12, 0.12):
        gbox("GreenLens_%+.2f" % sx, (sx - 0.075, 0.10, 0.10), (sx + 0.075, 0.24, 0.125), "light_green", root, c)
        gbox("RedLens_%+.2f" % sx, (sx - 0.075, 0.10, -0.125), (sx + 0.075, 0.24, -0.10), "light_red", root, c)


def build_papi_light_bank(root, c):
    """4-unit PAPI glidepath indicator bar facing +Z (2 red on left, 2 white on right)."""
    gbox("ConcretePad", (-3.50, 0.0, -0.60), (3.50, 0.06, 0.60), "concrete", root, c)
    xs = (-2.55, -0.85, 0.85, 2.55)
    for idx, cx in enumerate(xs):
        for lx in (cx - 0.42, cx + 0.42):
            gbox("LegF_%d_%+.2f" % (idx, lx), (lx - 0.05, 0.06, 0.25), (lx + 0.05, 0.12, 0.35), "ink", root, c)
            gbox("LegB_%d_%+.2f" % (idx, lx), (lx - 0.05, 0.06, -0.35), (lx + 0.05, 0.12, -0.25), "ink", root, c)
        gbox("BoxBody_%d" % idx, (cx - 0.55, 0.12, -0.45), (cx + 0.55, 0.39, 0.38), "sign_yellow", root, c, bevel=0.015)
        gbox("HoodTop_%d" % idx, (cx - 0.56, 0.38, 0.30), (cx + 0.56, 0.42, 0.54), "ink", root, c)
        gbox("HoodSideL_%d" % idx, (cx - 0.56, 0.13, 0.36), (cx - 0.51, 0.39, 0.52), "ink", root, c)
        gbox("HoodSideR_%d" % idx, (cx + 0.51, 0.13, 0.36), (cx + 0.56, 0.39, 0.52), "ink", root, c)
        gbox("Faceplate_%d" % idx, (cx - 0.51, 0.14, 0.37), (cx + 0.51, 0.37, 0.40), "ink", root, c)
        lens_pal = "light_red" if idx < 2 else "light_white"
        for ox in (-0.23, 0.23):
            gbox("Lens_%d_%+.2f" % (idx, ox), (cx + ox - 0.17, 0.17, 0.40), (cx + ox + 0.17, 0.34, 0.43), lens_pal, root, c)


def build_windsock(root, c):
    """6.5 m red-and-white striped pole with tapered 5-band orange/white windsock."""
    gbox("Plinth", (-0.55, 0.0, -0.55), (0.55, 0.14, 0.55), "concrete", root, c, bevel=0.02)
    gfrustum("BaseCollar", 0.0, 0.0, 0.14, 0.32, 0.24, 0.17, "ink", root, c, segs=12)
    bands = 6
    y0 = 0.32
    y_top = 6.20
    for i in range(bands):
        a = y0 + (y_top - y0) * (i / bands)
        b = y0 + (y_top - y0) * ((i + 1) / bands)
        ra = 0.14 + (0.09 - 0.14) * (i / bands)
        rb = 0.14 + (0.09 - 0.14) * ((i + 1) / bands)
        pal = "red" if i % 2 == 0 else "white"
        gfrustum("Mast_%d" % i, 0.0, 0.0, a, b, ra, rb, pal, root, c, segs=12)
    gfrustum("TopCap", 0.0, 0.0, 6.20, 6.32, 0.12, 0.12, "ink", root, c, segs=12)
    gfrustum("TopBeacon", 0.0, 0.0, 6.32, 6.50, 0.09, 0.04, "light_red", root, c, segs=10)

    # Swivel assembly + 5-band orange-and-white tapered sock cone (slightly drooped along +Z).
    gtube_segment("SwivelArm", (0.0, 6.08, 0.0), (0.0, 6.08, 0.58), 0.035, 0.035, "metal", root, c, segs=8)
    gtube_segment("HoopRing", (0.0, 6.08, 0.55), (0.0, 6.08, 0.62), 0.43, 0.43, "ink", root, c, segs=14)
    # Two stay struts from arm to hoop rim.
    gtube_segment("StayTop", (0.0, 6.08, 0.20), (0.0, 6.46, 0.58), 0.02, 0.02, "metal", root, c, segs=6)
    gtube_segment("StayBot", (0.0, 6.08, 0.20), (0.0, 5.70, 0.58), 0.02, 0.02, "metal", root, c, segs=6)
    sock_pts = [
        (0.0, 6.08, 0.58, 0.41),
        (0.0, 5.98, 1.22, 0.36),
        (0.0, 5.82, 1.86, 0.31),
        (0.0, 5.62, 2.50, 0.25),
        (0.0, 5.40, 3.14, 0.20),
        (0.0, 5.16, 3.76, 0.16),
    ]
    for i in range(len(sock_pts) - 1):
        p0 = sock_pts[i][:3]
        p1 = sock_pts[i + 1][:3]
        r0 = sock_pts[i][3]
        r1 = sock_pts[i + 1][3]
        pal = "windsock_orange" if i % 2 == 0 else "white"
        gtube_segment("Sock_%d" % i, p0, p1, r0, r1, pal, root, c, segs=14)


def blender_bounds(lo_g, hi_g):
    return (lo_g[0], -hi_g[2], lo_g[1]), (hi_g[0], -lo_g[2], hi_g[1])


PIECES = {
    "taxi_edge_light": (build_taxi_edge_light, (0, 0)) + blender_bounds((-0.16, 0.0, -0.16), (0.16, 0.38, 0.16)),
    "runway_edge_light_white": (build_runway_edge_light_white, (0, 0)) + blender_bounds((-0.18, 0.0, -0.18), (0.18, 0.40, 0.18)),
    "runway_edge_light_amber": (build_runway_edge_light_amber, (0, 0)) + blender_bounds((-0.18, 0.0, -0.18), (0.18, 0.40, 0.18)),
    "runway_threshold_light": (build_runway_threshold_light, (0, 0)) + blender_bounds((-0.27, 0.0, -0.13), (0.27, 0.34, 0.13)),
    "papi_light_bank": (build_papi_light_bank, (0, 0)) + blender_bounds((-3.50, 0.0, -0.60), (3.50, 0.42, 0.60)),
    "windsock": (build_windsock, (0, 0)) + blender_bounds((-0.55, 0.0, -0.55), (0.55, 6.510, 3.818)),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pieces = argv or list(PIECES)
    unknown = [p for p in pieces if p not in PIECES]
    if unknown:
        kit.fail("unknown pieces %s; known %s" % (unknown, list(PIECES)))
        sys.exit(1)
    kit.PIECES.clear()
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.clear()
    os.makedirs(kit.OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.report_palette()
    written = []
    for piece in pieces:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        kit._images.clear()
        kit._materials.clear()
        root, c = kit.build_piece(piece)
        kit.log(
            "BUILT %s objects=%d materials=%d (%s) images=%d"
            % (piece, len(c.objects), len(bpy.data.materials), sorted(m.name for m in bpy.data.materials), len(bpy.data.images))
        )
        written.append((piece, kit.export_piece(piece, root, c)))
    for piece, out in written:
        kit.verify_written(piece, out)
    # Save appendable .blend side by side.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    x = 0.0
    for piece in pieces:
        root, _c = kit.build_piece(piece)
        root.location.x = x
        x += 8.0 if piece == "papi_light_bank" else 4.0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=True)
    kit.log("BLEND saved %s" % os.path.relpath(BLEND_OUT, kit.REPO))
    kit.log("AIRFIELD_PROPS done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    main()
