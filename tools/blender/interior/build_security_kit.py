"""Build the security lane pieces of the interior kit and export one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_security_kit.py' [-- piece ...]

Ruling proper-security-is-a-full-security-lane-tray-table-carry-on: a security lane is a
tray table, an X-ray belt beside a walk-through arch, and a pickup table, each placed
as its own 1x1 part (security-lane-parts-are-placed-separately-tray-table-x-ray-b). The
cells are named by the geometry contract at the top of game/build/security_lanes.gd: at
facing 0 the arch is at (0, 0), the tray table at (1, 1), the X-ray belt at (1, 0) and
the pickup table at (1, -1), and passengers and bags both move toward Godot -Z. A part
stores only its facing, never the lane's mirror, so every piece is symmetric across X
and serves a lane with its parts on either side of the arch. The pieces:
- security_arch (1x1): a walk-through arch with a 0.91 m clear passage (ARCH_CLEAR_HALF),
  wider than the basic scanner's 0.70 m: the 2 m Toon passengers swing their hands out
  to 0.43 m from the centre line when they walk, so the opening keeps 2.5 cm either
  side (Security 7/8). Thin posts reach 0.495 m, past the usual inset but inside the
  cell, so its +x and -x sides have their own limit (SIDE_LIMITS).
- xray_belt (1x1): a belt cabinet with a tunnel over the middle. The belt runs to the
  front and back cell edges (ports, as the baggage belts) so tray table, X-ray and
  pickup table read as one conveyor; the cabinet keeps the 0.08 m inset. Short curtain
  strips hang at both tunnel mouths, clear of a loaded tray. A low console on the roof
  carries two screens tilted up and out to +X and -X, so the officer standing beside
  the belt (on its outer side, either mirror) faces one. Screen_Face holds both panels
  so a later X-ray picture can replace them.
- tray_table (1x1): a tray dispenser cabinet. Its steel top and a transfer lip reach the
  back edge (toward the X-ray) at belt height; the cabinet body keeps the inset. A broad
  opening in its front face shows a stack of nested grey trays.
- pickup_table (1x1): an open-legged roller bed with a transfer plate on the front edge
  (toward the X-ray) at belt height, a full-width yellow stop at the back and a shelf
  of returned grey trays below.
- security_tray: a grey tray, origin at its bottom centre. No grid footprint.
- carry_on_bag: a small cabin bag lying flat, sized to the tray. No grid footprint.

Belt height is 0.74 m on every part. Mount_TrayIn, Mount_TrayScan and Mount_TrayOut are
empties on the tray table, the X-ray belt and the pickup table at belt height, where a
tray's bottom centre rests; their +Z is the piece's front (identity rotation).

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, every face on a measured Toon atlas
swatch, the written file re-read and checked). check_sides() reads the written file per
side: a port side reaches the cell edge, every other side keeps the inset. check_ports()
proves each port carries a surface at belt height across the tray width at the edge.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402
import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "security-lane", "security_kit.blend")

INSET = 0.08
EDGE = 0.5
HALF_IN = EDGE - INSET  # 0.42
# The arch's clear half-width, its posts' inner panel face and outer face (see the
# module docstring).
ARCH_CLEAR_HALF = 0.455
ARCH_PANEL_IN = 0.465
ARCH_OUTER = 0.495
# Per piece, sides whose closed-side limit is not HALF_IN.
SIDE_LIMITS = {"security_arch": {"+x": ARCH_OUTER, "-x": ARCH_OUTER}}
BELT_TOP = 0.74
# The tray (Godot x by z by y): 0.44 x 0.60 x 0.08, walls 0.015, base 0.012.
TRAY = (0.44, 0.60, 0.08)
TRAY_WALL = 0.015
TRAY_BASE = 0.012
# Half the tray width: a port surface must span at least this across the edge.
TRAY_HALF = TRAY[0] / 2.0
# Cabin bag lying flat (Blender x, y, z).
BAG = (0.34, 0.48, 0.19)
# The visible front of a dispenser tray: from the cabinet front (-0.385) to just in
# front of the recess back (-0.105).
STACK_DEPTH = 0.275

# A mid-grey for the trays: TP_Atlas_1A_D column 14, row 11 runs from cbcaca to 505150.
SECURITY_PALETTE = {"tray_grey": ("TP_Atlas_1A_D", 14, 11, 0.45, 0.0)}

# piece -> footprint (cells), port sides open to the cell edge (Godot), mounts
# {name: Godot position}.
SECURITY = {
    "security_arch": {"footprint": (1, 1), "ports": [], "mounts": {}},
    "xray_belt": {"footprint": (1, 1), "ports": ["+z", "-z"], "mounts": {"Mount_TrayScan": (0.0, BELT_TOP, 0.0)}},
    "tray_table": {"footprint": (1, 1), "ports": ["-z"], "mounts": {"Mount_TrayIn": (0.0, BELT_TOP, -0.08)}},
    "pickup_table": {"footprint": (1, 1), "ports": ["+z"], "mounts": {"Mount_TrayOut": (0.0, BELT_TOP, 0.04)}},
    "security_tray": {"footprint": None, "ports": [], "mounts": {}},
    "carry_on_bag": {"footprint": None, "ports": [], "mounts": {}},
}


def tbox(*a, **k):
    return cafe.tbox(*a, **k)


def group(name, root, c):
    return cafe.group(name, root, c)


def add_mounts(piece, root, c):
    for name, (gx, gy, gz) in SECURITY[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y).
        ob.location = (gx, -gz, gy)


def tray(prefix, x, y, z, parent, c, pal="tray_grey", depth=TRAY[1]):
    """A tray (TRAY) with its bottom centre at Blender (x, y, z): a base and four walls."""
    w, d, h = TRAY[0], depth, TRAY[2]
    hx, hy = w / 2.0, d / 2.0
    t = TRAY_WALL
    tbox(prefix + "_Base", (x - hx, y - hy, z), (x + hx, y + hy, z + TRAY_BASE), pal, parent, c)
    tbox(prefix + "_Wall_F", (x - hx, y - hy, z), (x + hx, y - hy + t, z + h), pal, parent, c)
    tbox(prefix + "_Wall_B", (x - hx, y + hy - t, z), (x + hx, y + hy, z + h), pal, parent, c)
    tbox(prefix + "_Wall_L", (x - hx, y - hy + t, z), (x - hx + t, y + hy - t, z + h), pal, parent, c)
    tbox(prefix + "_Wall_R", (x + hx - t, y - hy + t, z), (x + hx, y + hy - t, z + h), pal, parent, c)


# ---------------------------------------------------------------- pieces


def build_security_arch(root, c):
    # Panels x ARCH_PANEL_IN..ARCH_OUTER with 1 cm inner strips; the strips' inner face
    # is the clear passage's edge (ARCH_CLEAR_HALF), cut to one cell.
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * ARCH_PANEL_IN, s * ARCH_OUTER))
        tbox("Arch_Panel_" + side, (x0, -0.30, 0), (x1, 0.30, 2.2), "metal", root, c, bevel=0.01)
        xs = sorted((s * ARCH_PANEL_IN, s * ARCH_CLEAR_HALF))
        tbox("Arch_Strip_" + side, (xs[0], -0.22, 0.30), (xs[1], 0.22, 2.0), "blue", root, c)
        # The feet stop at the strips' inner face, keeping the passage clear.
        f0, f1 = sorted((s * ARCH_CLEAR_HALF, s * ARCH_OUTER))
        tbox("Arch_Foot_" + side, (f0, -0.40, 0), (f1, 0.40, 0.04), "frame", root, c)
    tbox("Arch_Beam", (-ARCH_OUTER, -0.32, 2.2), (ARCH_OUTER, 0.32, 2.42), "frame", root, c, bevel=0.02)
    tbox("Arch_Lamp", (-0.08, -0.34, 2.27), (0.08, -0.32, 2.35), "lamp_green", root, c)
    mat = ARCH_CLEAR_HALF - 0.01
    tbox("Arch_Mat", (-mat, -0.42, 0), (mat, 0.42, 0.012), "dark", root, c)


def build_xray_belt(root, c):
    # Cabinet, inset on every side.
    tbox("Xray_ToeKick", (-0.32, -0.40, 0), (0.32, 0.40, 0.06), "dark", root, c)
    tbox("Xray_Cabinet", (-0.34, -0.415, 0.06), (0.34, 0.415, 0.66), "white", root, c, bevel=0.01)
    tbox("Xray_Band", (-0.345, -0.42, 0.50), (0.345, 0.42, 0.58), "blue", root, c)
    # Belt bed, belt and lips run to both cell edges (the ports).
    tbox("Xray_BeltBed", (-0.30, -EDGE, 0.66), (0.30, EDGE, 0.72), "metal", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.25, s * 0.30))
        tbox("Xray_Lip_" + side, (x0, -EDGE, 0.72), (x1, EDGE, 0.77), "frame", root, c)
    surface = group("Belt_Surface", root, c)
    tbox("Belt_Surface_Top", (-0.25, -EDGE, 0.72), (0.25, EDGE, BELT_TOP), "dark", surface, c)
    # Tunnel over the middle: walls, roof, a dark lining, a blue band, warning labels.
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.30, s * 0.40))
        tbox("Tunnel_Wall_" + side, (x0, -0.30, 0.66), (x1, 0.30, 1.16), "white", root, c)
        l0, l1 = sorted((s * 0.27, s * 0.30))
        tbox("Tunnel_Lining_" + side, (l0, -0.295, 0.77), (l1, 0.295, 1.16), "dark", root, c)
        k0, k1 = sorted((s * 0.40, s * 0.405))
        tbox("Tunnel_Label_" + side, (k0, -0.08, 0.86), (k1, 0.08, 1.02), "yellow", root, c)
    tbox("Tunnel_Roof", (-0.40, -0.30, 1.16), (0.40, 0.30, 1.32), "white", root, c, bevel=0.015)
    tbox("Tunnel_Ceiling", (-0.27, -0.295, 1.15), (0.27, 0.295, 1.16), "dark", root, c)
    tbox("Tunnel_Band", (-0.405, -0.305, 1.22), (0.405, 0.305, 1.27), "blue", root, c)
    # Curtain strips at both mouths: 1.16 down to 1.06, clear of a loaded tray (0.24).
    for end, (y0, y1) in (("F", (-0.308, -0.300)), ("B", (0.300, 0.308))):
        for i in range(6):
            x = -0.25 + i * 0.086
            tbox("Curtain_%s%d" % (end, i), (x, y0, 1.06), (x + 0.07, y1, 1.16), "dark", root, c)
    # Low roof console: one block with two screens leaning back to back, faces up and
    # out to +-X.
    tbox("Console_Base", (-0.16, -0.20, 1.32), (0.16, 0.10, 1.38), "frame", root, c, bevel=0.01)
    tbox("Console_Body", (-0.11, -0.18, 1.38), (0.11, 0.08, 1.43), "frame", root, c)
    face = group("Screen_Face", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        deg = -20.0 * s
        x0, x1 = sorted((s * 0.10, s * 0.14))
        pivot = (s * 0.12, 0.0, 1.36)
        tbox("Console_Monitor_" + side, (x0, -0.18, 1.36), (x1, 0.08, 1.46), "frame", root, c,
             axis="Y", deg=deg, pivot=pivot, bevel=0.008)
        f0, f1 = sorted((s * 0.14, s * 0.146))
        tbox("Screen_Face_" + side, (f0, -0.16, 1.37), (f1, 0.06, 1.45), "screen_sky", face, c,
             axis="Y", deg=deg, pivot=pivot)
    add_mounts("xray_belt", root, c)


def build_tray_table(root, c):
    tbox("Tray_ToeKick", (-0.33, -0.40, 0), (0.33, 0.40, 0.06), "dark", root, c)
    # Cabinet with a recess in its front face (Blender -y) holding the tray stack.
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.30, s * 0.355))
        tbox("Tray_Side_" + side, (x0, -0.415, 0.06), (x1, 0.415, 0.70), "white", root, c)
    tbox("Tray_Block", (-0.30, -0.10, 0.06), (0.30, 0.415, 0.70), "white", root, c)
    tbox("Tray_Sill", (-0.30, -0.415, 0.06), (0.30, -0.10, 0.10), "white", root, c)
    tbox("Tray_Header", (-0.30, -0.415, 0.56), (0.30, -0.10, 0.70), "white", root, c)
    tbox("Tray_Recess", (-0.30, -0.105, 0.10), (0.30, -0.10, 0.56), "dark", root, c)
    tbox("Tray_Band", (-0.36, -0.42, 0.60), (0.36, 0.42, 0.66), "blue", root, c)
    # Dispenser slots seen through the opening: the front of each tray (the part in
    # front of the recess back), resting on two runners.
    for i in range(4):
        z0 = 0.11 + i * 0.105
        tray("Stack_%d" % i, 0.0, -0.385 + STACK_DEPTH / 2.0, z0, root, c, depth=STACK_DEPTH)
        for side, s in (("L", -1.0), ("R", 1.0)):
            r0, r1 = sorted((s * 0.20, s * 0.30))
            tbox("Runner_%d%s" % (i, side), (r0, -0.415, z0 - 0.012), (r1, -0.105, z0), "metal", root, c)
    # Steel top at belt height; it and a transfer lip reach the back edge (+y).
    tbox("Tray_Top", (-0.38, -0.42, 0.70), (0.38, 0.42, BELT_TOP), "metal", root, c, bevel=0.008)
    tbox("Tray_Lip", (-0.30, 0.42, 0.70), (0.30, EDGE, BELT_TOP), "metal", root, c)
    add_mounts("tray_table", root, c)


def build_pickup_table(root, c):
    for i, (x, y) in enumerate(((-0.32, -0.38), (0.32, -0.38), (-0.32, 0.38), (0.32, 0.38))):
        tbox("Pickup_Leg_%d" % i, (x - 0.02, y - 0.02, 0.02), (x + 0.02, y + 0.02, 0.62), "frame", root, c)
        tbox("Pickup_Foot_%d" % i, (x - 0.03, y - 0.03, 0), (x + 0.03, y + 0.03, 0.02), "dark", root, c)
    tbox("Pickup_Shelf", (-0.30, -0.38, 0.14), (0.30, 0.38, 0.17), "metal", root, c)
    # Returned trays stacked on the shelf, each on the rims of the one below.
    for i in range(3):
        tray("Shelf_Tray_%d" % i, 0.0, 0.0, 0.17 + i * TRAY[2], root, c)
    # Roller bed: side rails from the front edge (-y) to the stop, seven rollers, a
    # transfer plate on the front edge at belt height.
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.30, s * 0.34))
        tbox("Pickup_Rail_" + side, (x0, -EDGE, 0.62), (x1, 0.42, 0.76), "frame", root, c)
    tbox("Pickup_Brace_F", (-0.30, -0.40, 0.62), (0.30, -0.36, 0.66), "frame", root, c)
    tbox("Pickup_Brace_B", (-0.30, 0.30, 0.62), (0.30, 0.34, 0.66), "frame", root, c)
    r = 0.025
    for i in range(7):
        y = -0.43 + i * 0.12
        bag.cyl_x("Roller_%d" % i, -0.30, 0.30, y, BELT_TOP - r, r, "metal", root, c)
    tbox("Pickup_Plate", (-0.30, -EDGE, BELT_TOP - 0.02), (0.30, -0.46, BELT_TOP), "metal", root, c)
    tbox("Pickup_Stop", (-0.36, 0.36, 0.62), (0.36, 0.42, 0.86), "yellow", root, c, bevel=0.01)
    add_mounts("pickup_table", root, c)


def build_security_tray(root, c):
    tray("Tray", 0.0, 0.0, 0.0, root, c)


def build_carry_on_bag(root, c):
    bag.suitcase("Bag", 0.0, 0.0, 0.0, BAG, "blue", root, c)


# piece -> (builder, footprint, expected Blender bounds lo/hi).
PIECES = {
    "security_arch": (build_security_arch, (1, 1), (-ARCH_OUTER, -0.42, 0.0), (ARCH_OUTER, 0.42, 2.42)),
    "xray_belt": (build_xray_belt, (1, 1), (-0.405, -EDGE, 0.0), (0.405, EDGE, 1.458)),
    "tray_table": (build_tray_table, (1, 1), (-0.38, -0.42, 0.0), (0.38, EDGE, BELT_TOP)),
    "pickup_table": (build_pickup_table, (1, 1), (-0.36, -EDGE, 0.0), (0.36, 0.42, 0.86)),
    "security_tray": (build_security_tray, None, (-0.22, -0.30, 0.0), (0.22, 0.30, 0.08)),
    "carry_on_bag": (build_carry_on_bag, None, (-0.176, -0.24, 0.0), (0.176, 0.24, 0.226)),
}


def extra_nodes(piece):
    names = list(SECURITY[piece]["mounts"])
    if piece == "xray_belt":
        names += ["Belt_Surface", "Belt_Surface_Mesh", "Screen_Face", "Screen_Face_Mesh"]
    return sorted(names)


EXTRA_NODES = {p: extra_nodes(p) for p in PIECES}


# ---------------------------------------------------------------- register + checks


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside this kit, a name another kit owns, a
    mount name another kit uses, or an existing destination .glb that is not this
    builder's piece."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the security kit: %s" % bad)
    others = set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES) | set(bag.PIECES)
    taken = sorted(others & set(PIECES))
    if taken:
        kit.fail("security names already owned by another kit: %s" % taken)
    ours = {n for v in EXTRA_NODES.values() for n in v if n.startswith("Mount_")}
    used = (set(kit.NODE_TRANSLATIONS) | {n for v in svc.EXTRA_NODES.values() for n in v}
            | {n for v in act.EXTRA_NODES.values() for n in v} | {n for v in bag.EXTRA_NODES.values() for n in v})
    clash = sorted(ours & used)
    if clash:
        kit.fail("mount names already used by another kit: %s" % clash)
    for p in pieces:
        out = os.path.join(kit.OUT_DIR, p + ".glb")
        if not os.path.exists(out):
            kit.log("GUARD %s new file %s" % (p, out))
            continue
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(p) + "_ROOT" in names and set(EXTRA_NODES.get(p, [])) <= names
        kit.log("GUARD %s existing file own=%s" % (p, own))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    if kit.FAILS:
        sys.exit(1)


def register():
    """Add the security swatch, pieces, required nodes and mount positions to the kit."""
    kit.PALETTE.update(SECURITY_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    for spec in SECURITY.values():
        for name, pos in spec["mounts"].items():
            kit.NODE_TRANSLATIONS[name] = pos


def check_mounts(piece, js):
    """Every mount in the written file at its position, its +Z the piece's front."""
    by_name = {n.get("name"): n for n in js.get("nodes", [])}
    for name, pos in SECURITY[piece]["mounts"].items():
        node = by_name.get(name)
        if node is None:
            kit.fail("%s: mount %s missing from the written file" % (piece, name))
            continue
        t = node.get("translation", [0.0, 0.0, 0.0])
        x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        facing = Quaternion((w, x, y, z)) @ Vector((0.0, 0.0, 1.0))
        kit.log("MOUNT %s %s pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f)"
                % (piece, name, t[0], t[1], t[2], facing.x, facing.y, facing.z))
        if (facing - Vector((0.0, 0.0, 1.0))).length > 1e-3 or max(abs(a - b) for a, b in zip(t, pos)) > 1e-4:
            kit.fail("%s: mount %s at %s facing %s, expected %s facing +Z" % (piece, name, t, facing, pos))


def check_sides(piece, objs):
    """Per side: a port side reaches the cell edge, a closed side keeps the inset."""
    fp = SECURITY[piece]["footprint"]
    if fp is None:
        kit.log("SIDES %s no grid footprint (a prop)" % piece)
        return
    pts = bag.godot_points(objs)
    ext = {"+x": max(p.x for p in pts), "-x": -min(p.x for p in pts),
           "+z": max(p.z for p in pts), "-z": -min(p.z for p in pts)}
    parts = []
    for side in ("+x", "-x", "+z", "-z"):
        is_port = side in SECURITY[piece]["ports"]
        limit = EDGE if is_port else SIDE_LIMITS.get(piece, {}).get(side, HALF_IN)
        parts.append("%s=%.4f/%s%.3f" % (side, ext[side], "port" if is_port else "closed", limit))
        if ext[side] > limit + 1e-3:
            kit.fail("%s: written mesh reaches %.4f on %s, limit %.3f" % (piece, ext[side], side, limit))
        if is_port and ext[side] < limit - 1e-3:
            kit.fail("%s: port side %s stops at %.4f, short of the edge %.3f" % (piece, side, ext[side], limit))
    min_y = min(p.y for p in pts)
    kit.log("SIDES %s %s min_y=%.4f" % (piece, " ".join(parts), min_y))
    if min_y < -1e-4:
        kit.fail("%s: mesh below the floor (%.4f)" % (piece, min_y))


def edge_cover(objs, z_edge, drop_centre=False):
    """The x intervals (Godot) along the edge z = z_edge covered by upward faces lying
    at belt height that touch that edge, merged. drop_centre leaves out every face
    that crosses x = 0 (the negative control)."""
    spans = []
    for ob in objs:
        mw = ob.matrix_world
        rot = mw.to_3x3()
        for poly in ob.data.polygons:
            up = (rot @ poly.normal).normalized().z  # Blender z is Godot y
            ws = [mw @ ob.data.vertices[i].co for i in poly.vertices]
            gs = [Vector((w.x, w.z, -w.y)) for w in ws]
            if up < 0.99 or any(abs(g.y - BELT_TOP) > 1e-3 for g in gs):
                continue
            on_edge = [g.x for g in gs if abs(g.z - z_edge) < 1e-3]
            if len(on_edge) < 2:
                continue
            lo, hi = min(on_edge), max(on_edge)
            if drop_centre and lo < 0.0 < hi:
                continue
            spans.append((lo, hi))
    merged = []
    for lo, hi in sorted(spans):
        if merged and lo <= merged[-1][1] + 1e-4:
            merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
        else:
            merged.append((lo, hi))
    return merged


def covers(merged):
    return any(lo <= -TRAY_HALF + 1e-4 and hi >= TRAY_HALF - 1e-4 for lo, hi in merged)


def check_ports(piece, objs):
    """Each port: upward faces at belt height touching the cell edge cover the tray width
    without a gap, so a tray passes from one part to the next at one height. Control:
    the same check without the faces crossing the centre must fail."""
    for side in SECURITY[piece]["ports"]:
        z = EDGE if side == "+z" else -EDGE
        merged = edge_cover(objs, z)
        control = edge_cover(objs, z, drop_centre=True)
        kit.log("PORT %s %s belt_top=%.3f covered=%s tray_half=%.2f control_without_centre=%s"
                % (piece, side, BELT_TOP, [(round(a, 3), round(b, 3)) for a, b in merged], TRAY_HALF,
                   [(round(a, 3), round(b, 3)) for a, b in control]))
        if not covers(merged):
            kit.fail("%s: port %s has no belt-height surface across the tray width" % (piece, side))
        if covers(control):
            kit.fail("%s: port %s control without the centre faces still passed" % (piece, side))


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        check_mounts(piece, js)
        objs = bag.import_written(out)
        check_sides(piece, objs)
        check_ports(piece, objs)
    data = {p: {"footprint": s["footprint"], "ports": s["ports"], "mounts": s["mounts"]} for p, s in SECURITY.items()}
    kit.log("SECURITY_DATA " + json.dumps(data))
    kit.log("SECURITY done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
