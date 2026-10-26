"""Build the cafe pieces of the interior kit and export one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_cafe_kit.py' [-- piece ...]

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, furniture 0.08 m inside its footprint,
every face on a measured Toon atlas swatch, the written file re-read and checked).
register() adds the cafe swatches, pieces and required nodes to the kit's tables;
the kit's main() builds, exports and verifies them, and check_mounts() then re-reads
each written file's Mount_* nodes for position and facing.

Interaction points are Mount_* empties in the .glb, in the piece's own frame (Godot
axes, metres). A mount is where a passenger's ROOT goes (the feet on the floor), and
its +Z is the way the passenger faces. CAFE below is the machine-readable record of
each piece's footprint and mounts.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_interior_kit as kit  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "cafe-kit", "cafe_kit.blend")

# Sit contract (article toon-asset-pipeline, SIT_CONTRACT lines of toon_clips.py): the
# seat top is 0.53 m and the seat contact sits 0.385 m (male) to 0.427 m (female) behind
# the character root, with the knees within 0.06 m of the root.
SEAT_TOP = 0.53
# Seated root distance from the table centre: the table stands in the middle cell of
# three and each chair in an outer cell, and 0.55 is the game's own seat rule
# (passenger_sim SIT_FORWARD_M: the root 0.45 m in front of the seat cell centre).
# Standing at the root clears the 0.35 m table top, so sit_down and stand_up need no
# root shuffle; a 2x1 table with the root at 0.28 put the standing body through the top.
# Seat contact lands 0.94-0.98 m out, on the chair pan (0.75-1.13 m).
SIT_ROOT_X = 0.55

# New swatches: (material, column, row, fraction from the swatch top, span).
CAFE_PALETTE = {
    "cream": ("TP_Atlas_1A_D", 22, 0, 0.30, 0.0),
    "coffee": ("TP_Atlas_1A_D", 8, 14, 0.50, 0.0),
    "sage": ("TP_Atlas_1A_D", 4, 7, 0.30, 0.0),
    "red": ("TP_Atlas_1A_D", 31, 0, 0.30, 0.0),
    "gold": ("TP_Atlas_1A_D", 3, 13, 0.30, 0.0),
    "pink": ("TP_Atlas_1A_D", 23, 0, 0.30, 0.0),
}

# piece -> footprint (cells x by y), mounts {name: (Godot position, yaw in degrees)},
# and what each mount means. Yaw 0 faces Godot +Z.
CAFE = {
    "cafe_counter": {
        "footprint": (2, 1),
        "mounts": {
            # The cell in front of the -x cell (the till), facing the counter.
            "Mount_Order": ((-0.5, 0.0, 1.0), 180.0),
            # The cell behind the -x cell, facing the counter.
            "Mount_Staff": ((-0.5, 0.0, -1.0), 0.0),
        },
    },
    "cafe_table": {
        "footprint": (3, 1),
        "mounts": {
            # Seated roots (feet on the floor), facing each other across the table;
            # each chair stands in an outer cell, the table in the middle cell.
            "Mount_SitRoot_L": ((-SIT_ROOT_X, 0.0, 0.0), 90.0),
            "Mount_SitRoot_R": ((SIT_ROOT_X, 0.0, 0.0), -90.0),
        },
    },
}


# ---------------------------------------------------------------- geometry


def tbox(name, lo, hi, pal, parent, c, axis="X", deg=0.0, pivot=None, bevel=0.0):
    """An axis box from lo to hi (Blender metres), optionally turned about `axis`."""
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = hi - lo
    centre = (lo + hi) / 2.0
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45),
            segments=1, affect="EDGES", profile=0.5,
        )
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    if deg:
        p = Vector(pivot if pivot is not None else centre)
        m = Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def cone(name, x, y, z0, z1, r0, r1, pal, parent, c, segs=8):
    """A tapered cylinder standing on z0 with radius r0 at the bottom, r1 at the top."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=z1 - z0)
    bmesh.ops.translate(bm, vec=Vector((x, y, (z0 + z1) / 2.0)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def ball(name, x, y, z, r, pal, parent, c):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=r)
    bmesh.ops.translate(bm, vec=Vector((x, y, z)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def group(name, root, c):
    """An empty under the root whose mesh children join into <name>_Mesh."""
    ob = bpy.data.objects.new(name, None)
    c.objects.link(ob)
    ob.parent = root
    ob.empty_display_size = 0.2
    return ob


def add_mounts(piece, root, c):
    for name, ((gx, gy, gz), yaw) in CAFE[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


# ---------------------------------------------------------------- pieces


def build_cafe_counter(root, c):
    # Counter body across both cells; the customer side is Blender -Y (Godot +Z).
    tbox("Counter_ToeKick", (-0.88, -0.34, 0), (0.88, 0.38, 0.08), "dark", root, c)
    tbox("Counter_Body", (-0.90, -0.38, 0.08), (0.90, 0.40, 0.92), "cream", root, c)
    tbox("Counter_Band", (-0.86, -0.395, 0.62), (0.86, -0.38, 0.76), "coffee", root, c)
    tbox("Counter_Top", (-0.92, -0.42, 0.92), (0.92, 0.42, 0.98), "wood", root, c, bevel=0.015)
    # Left (-x) cell, the order cell: espresso machine on the staff half, till at the front.
    tbox("Espresso_Body", (-0.80, 0.02, 0.98), (-0.32, 0.36, 1.30), "metal", root, c, bevel=0.02)
    tbox("Espresso_Tray", (-0.78, 0.04, 1.30), (-0.34, 0.34, 1.32), "dark", root, c)
    tbox("Espresso_Badge", (-0.74, 0.012, 1.14), (-0.38, 0.02, 1.22), "red", root, c)
    for i, x in enumerate((-0.68, -0.44)):
        tbox("Espresso_Head_%d" % i, (x - 0.04, 0.36, 1.10), (x + 0.04, 0.40, 1.16), "dark", root, c)
    tbox("Espresso_Drip", (-0.76, 0.36, 0.98), (-0.36, 0.42, 1.02), "dark", root, c)
    for i, x in enumerate((-0.70, -0.56, -0.42)):
        cyl("Espresso_Cup_%d" % i, x, 0.19, 1.32, 1.38, 0.03, "white", root, c)
    tbox("Grinder_Body", (-0.26, 0.10, 0.98), (-0.12, 0.26, 1.18), "dark", root, c, bevel=0.01)
    cone("Grinder_Hopper", -0.19, 0.18, 1.18, 1.30, 0.035, 0.06, "coffee", root, c)
    tbox("Till_Base", (-0.70, -0.34, 0.98), (-0.44, -0.14, 1.03), "dark", root, c, bevel=0.008)
    pivot = (-0.57, -0.185, 1.03)
    tbox("Till_Screen", (-0.67, -0.20, 1.03), (-0.47, -0.17, 1.20), "dark", root, c, deg=15.0, pivot=pivot)
    tbox("Till_Screen_Face", (-0.65, -0.17, 1.05), (-0.49, -0.165, 1.18), "screen_sky", root, c,
         deg=15.0, pivot=pivot)
    # Right (+x) cell: the pastry case, a stepped deck under glass.
    tbox("Pastry_Deck", (0.10, -0.36, 0.98), (0.84, 0.20, 1.00), "white", root, c)
    tbox("Pastry_Step", (0.10, -0.06, 1.00), (0.84, 0.20, 1.06), "white", root, c)
    for i, x in enumerate((0.25, 0.47, 0.69)):
        cyl("Donut_%d" % i, x, 0.07, 1.06, 1.085, 0.05, "gold", root, c)
        cyl("Donut_Icing_%d" % i, x, 0.07, 1.085, 1.10, 0.045, "pink", root, c)
        cyl("Donut_Hole_%d" % i, x, 0.07, 1.10, 1.102, 0.016, "coffee", root, c)
    for i, x in enumerate((0.32, 0.62)):
        cone("Muffin_Case_%d" % i, x, -0.22, 1.00, 1.05, 0.035, 0.045, "coffee", root, c)
        ball("Muffin_Top_%d" % i, x, -0.22, 1.06, 0.045, "gold", root, c)
    tbox("Pastry_Glass", (0.10, -0.36, 1.00), (0.84, 0.20, 1.24), "glass", root, c)
    for i, (x, y) in enumerate(((0.10, -0.36), (0.84, -0.36), (0.10, 0.20), (0.84, 0.20))):
        tbox("Pastry_Post_%d" % i, (x - 0.008, y - 0.008, 1.00), (x + 0.008, y + 0.008, 1.25), "frame", root, c)
    # Menu board over the pastry half, on two posts at the counter's back edge, so the
    # espresso machine keeps its silhouette.
    for i, x in enumerate((0.14, 0.80)):
        tbox("Menu_Post_%d" % i, (x - 0.02, 0.38, 0.98), (x + 0.02, 0.42, 1.50), "frame", root, c)
    face = group("Menu_Face", root, c)
    tbox("Menu_Face_Board", (0.08, 0.36, 1.50), (0.86, 0.40, 1.96), "dark", face, c)
    for side, z0, z1 in (("Top", 1.94, 1.98), ("Bottom", 1.48, 1.52)):
        tbox("Menu_Face_Frame" + side, (0.06, 0.355, z0), (0.88, 0.405, z1), "wood", face, c)
    for side, x0, x1 in (("L", 0.06, 0.10), ("R", 0.84, 0.88)):
        tbox("Menu_Face_Frame" + side, (x0, 0.355, 1.52), (x1, 0.405, 1.94), "wood", face, c)
    tbox("Menu_Face_Title", (0.22, 0.354, 1.85), (0.72, 0.36, 1.90), "gold", face, c)
    for row in range(4):
        z0 = 1.76 - row * 0.065
        tbox("Menu_Face_Item_%d" % row, (0.14, 0.354, z0), (0.50 - 0.05 * (row % 2), 0.36, z0 + 0.03),
             "cream", face, c)
        tbox("Menu_Face_Price_%d" % row, (0.68, 0.354, z0), (0.80, 0.36, z0 + 0.03), "cream", face, c)
    add_mounts("cafe_counter", root, c)


def cyl(name, x, y, z0, z1, r, pal, parent, c, segs=8):
    return kit.cyl(name, x, y, z0, z1, r, pal, parent, c, segs=segs)


def build_cafe_table(root, c, root_x=SIT_ROOT_X, piece="cafe_table"):
    # Round table on the footprint centre (the middle cell of three).
    cyl("Table_Base", 0.0, 0.0, 0.0, 0.025, 0.16, "dark", root, c, segs=12)
    cyl("Table_Stem", 0.0, 0.0, 0.025, 0.75, 0.035, "dark", root, c)
    cyl("Table_Top", 0.0, 0.0, 0.75, 0.78, 0.35, "wood", root, c, segs=12)
    for side, s in (("L", -1.0), ("R", 1.0)):
        cx = s * 0.17
        cyl("Saucer_" + side, cx, 0.0, 0.78, 0.79, 0.06, "white", root, c)
        cyl("Cup_" + side, cx, 0.0, 0.79, 0.85, 0.035, "white", root, c)
        # A chair at each end, facing the table, placed from the seated root: the pan
        # runs 0.20-0.58 m behind the root, the back is on the outside.
        x0, x1 = sorted((s * (root_x + 0.20), s * (root_x + 0.58)))
        tbox("Chair_Pan_" + side, (x0, -0.20, SEAT_TOP - 0.04), (x1, 0.20, SEAT_TOP), "sage", root, c, bevel=0.012)
        legs = ((0.23, -0.17), (0.23, 0.17), (0.55, -0.17), (0.55, 0.17))
        for k, (lx, ly) in enumerate(legs):
            x = s * (root_x + lx)
            tbox("Chair_Leg_%s%d" % (side, k), (x - 0.015, ly - 0.015, 0.0), (x + 0.015, ly + 0.015, SEAT_TOP - 0.04),
                 "dark", root, c)
        bx0, bx1 = sorted((s * (root_x + 0.54), s * (root_x + 0.58)))
        pivot = (s * (root_x + 0.56), 0.0, SEAT_TOP)
        for k, ly in enumerate((-0.17, 0.17)):
            tbox("Chair_BackPost_%s%d" % (side, k), (bx0, ly - 0.015, SEAT_TOP), (bx1, ly + 0.015, 0.90), "dark",
                 root, c, axis="Y", deg=s * 6.0, pivot=pivot)
        tbox("Chair_Back_" + side, (bx0, -0.19, 0.72), (bx1, 0.19, 0.92), "sage", root, c,
             axis="Y", deg=s * 6.0, pivot=pivot, bevel=0.01)
    add_mounts(piece, root, c)


# ---------------------------------------------------------------- register + checks

PIECES = {
    "cafe_counter": (build_cafe_counter, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 1.98)),
    "cafe_table": (build_cafe_table, (3, 1), (-1.170, -0.35, 0.0), (1.170, 0.35, 0.919)),
}
EXTRA_NODES = {
    "cafe_counter": ["Menu_Face", "Menu_Face_Mesh", "Mount_Order", "Mount_Staff"],
    "cafe_table": ["Mount_SitRoot_L", "Mount_SitRoot_R"],
}


def register():
    """Add the cafe swatches, pieces, required nodes and mount positions to the kit."""
    kit.PALETTE.update(CAFE_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    for spec in CAFE.values():
        for name, (pos, _yaw) in spec["mounts"].items():
            kit.NODE_TRANSLATIONS[name] = pos


def check_mounts(written):
    """Re-read each written file: every mount at its position, its +Z the stated way."""
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        by_name = {n.get("name"): n for n in js.get("nodes", [])}
        for name, (pos, yaw) in CAFE[piece]["mounts"].items():
            node = by_name.get(name)
            if node is None:
                kit.fail("%s: mount %s missing from the written file" % (piece, name))
                continue
            t = node.get("translation", [0.0, 0.0, 0.0])
            x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
            facing = Quaternion((w, x, y, z)) @ Vector((0.0, 0.0, 1.0))
            want = Vector((math.sin(math.radians(yaw)), 0.0, math.cos(math.radians(yaw))))
            kit.log("MOUNT %s %s pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f) want_facing=(%.3f, %.3f, %.3f)"
                    % (piece, name, t[0], t[1], t[2], facing.x, facing.y, facing.z, want.x, want.y, want.z))
            if (facing - want).length > 1e-3 or max(abs(a - b) for a, b in zip(t, pos)) > 1e-4:
                kit.fail("%s: mount %s at %s facing %s, expected %s facing %s" % (piece, name, t, facing, pos, want))
    kit.log("CAFE_DATA " + json.dumps({p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in CAFE.items()}))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    register()
    check_mounts(kit.main(default_pieces=list(PIECES), blend_out=BLEND_OUT))
