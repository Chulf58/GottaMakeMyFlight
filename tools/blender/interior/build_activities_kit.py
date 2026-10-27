"""Build the activities pieces of the interior kit and export one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_activities_kit.py' [-- piece ...]

Pieces (decision furniture-set-modelled-on-copenhagen-airport-decor-calms-pas): a kids
play area (play_blocks, play_slide, each on its own soft mat), a lounge sofa and
armchair, a charging and work desk, and the prize-car podium.

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, furniture 0.08 m inside its footprint,
every face on a measured Toon atlas swatch, the written file re-read and checked).
register() adds the activities swatches, pieces and required nodes to the kit's
tables; the kit's main() builds, exports and verifies them, and check_mounts() then
re-reads each written file's Mount_* nodes. It never calls build_cafe_kit.register()
and never adds mounts to kit.NODE_TRANSLATIONS, which is keyed by node name alone:
the sofa and the desk both carry Mount_SitRoot_L/R at different positions.

Before anything is built, guard() refuses a piece outside ACTIVITIES, an ACTIVITIES
name the kit or the cafe kit already uses, and an existing destination .glb that is
not this builder's own piece (its root node must be <Piece>_ROOT with the activity
mounts), so no other piece's file can be written.

Interaction points are Mount_* empties in the .glb, in the piece's own frame (Godot
axes, metres), unit scale, upright. Kind "sit_root": where a seated passenger's ROOT
goes (feet on the floor), +Z the way the passenger faces. Kind "vehicle": where the
prize car goes, its horizontal bounding-box centre over the mount and its lowest
wheel point at the mount's height, +Z the way the car's nose points. ACTIVITIES below
is the machine-readable record of each piece's footprint and mounts.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_interior_kit as kit  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "furniture-3", "activities_kit.blend")

# The sit contract (article toon-asset-pipeline): seat top 0.53 m, seat contact
# 0.385-0.427 m behind the root, knees within 0.06 m of it. The game's seat rule puts
# the root 0.45 m from the seat cell's centre toward the cell the passenger faces
# (passenger_sim SIT_FORWARD_M).
SEAT_TOP = cafe.SEAT_TOP
SIT_FORWARD = 0.45

# New swatches: (material, column, row, fraction from the swatch top, span). The
# cafe's red, pink, cream and gold are copied, not registered through the cafe kit.
ACTIVITIES_PALETTE = {
    "red": cafe.CAFE_PALETTE["red"],
    "pink": cafe.CAFE_PALETTE["pink"],
    "cream": cafe.CAFE_PALETTE["cream"],
    "gold": cafe.CAFE_PALETTE["gold"],
    "sun": ("TP_Atlas_1A_D", 28, 0, 0.30, 0.0),
    "kid_blue": ("TP_Atlas_1A_D", 25, 0, 0.30, 0.0),
    "kid_green": ("TP_Atlas_1A_D", 27, 0, 0.30, 0.0),
    "orange": ("TP_Atlas_1A_D", 29, 0, 0.30, 0.0),
    "purple": ("TP_Atlas_1A_D", 24, 0, 0.30, 0.0),
    "teal": ("TP_Atlas_1A_D", 29, 6, 0.30, 0.0),
}

# Seated roots: the seat cell's centre plus SIT_FORWARD toward the faced cell.
SOFA_ROOT_Z = 0.0 + SIT_FORWARD  # seat cell z = 0, faces +Z
DESK_ROOT_Z = 0.5 - SIT_FORWARD  # chair cell z = +0.5, faces -Z (the desk row)

# piece -> footprint (cells x by z), mounts {name: (kind, Godot position, yaw in
# degrees)}. Yaw 0 faces Godot +Z.
ACTIVITIES = {
    "play_blocks": {"footprint": (2, 2), "mounts": {}},
    "play_slide": {"footprint": (2, 1), "mounts": {}},
    "lounge_sofa": {
        "footprint": (2, 1),
        "mounts": {
            "Mount_SitRoot_L": ("sit_root", (-0.5, 0.0, SOFA_ROOT_Z), 0.0),
            "Mount_SitRoot_R": ("sit_root", (0.5, 0.0, SOFA_ROOT_Z), 0.0),
        },
    },
    "lounge_armchair": {
        "footprint": (1, 1),
        "mounts": {"Mount_SitRoot": ("sit_root", (0.0, 0.0, SOFA_ROOT_Z), 0.0)},
    },
    "work_desk": {
        # Desk in the back row (z < 0), chairs in the front row facing it.
        "footprint": (2, 2),
        "mounts": {
            "Mount_SitRoot_L": ("sit_root", (-0.5, 0.0, DESK_ROOT_Z), 180.0),
            "Mount_SitRoot_R": ("sit_root", (0.5, 0.0, DESK_ROOT_Z), 180.0),
        },
    },
    "prize_podium": {
        # Deck top 0.30 m. Yaw -90: the car's long axis runs along X, nose to -X.
        "footprint": (6, 3),
        "mounts": {"Mount_Car": ("vehicle", (0.0, 0.30, 0.0), -90.0)},
    },
}


# ---------------------------------------------------------------- geometry


def tbox(*a, **k):
    return cafe.tbox(*a, **k)


def prism_xz(name, pts, y0, y1, pal, parent, c):
    """A convex prism: the 2D outline `pts` (Blender x, z) extruded from y0 to y1."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y0, z)) for x, z in pts]
    back = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def add_mounts(piece, root, c):
    for name, (_kind, (gx, gy, gz), yaw) in ACTIVITIES[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


# ---------------------------------------------------------------- pieces
# Blender frame: x = Godot x, -y = Godot +Z (the front), z = up.

MAT_TOP = 0.04  # play_blocks mat
SLIDE_MAT = 0.03  # play_slide mat
SLIDE_TOP = 0.55  # platform height


def build_play_blocks(root, c):
    # A 2x2 soft-play island: four foam mat squares in a checker, foam shapes on top.
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x0, x1 = sorted((sx * 0.01, sx * 0.92))
        y0, y1 = sorted((sy * 0.01, sy * 0.92))
        pal = "kid_green" if sx == sy else "sun"
        tbox("Mat_Tile_%d" % i, (x0, y0, 0.0), (x1, y1, MAT_TOP), pal, root, c, bevel=0.015)
    t = MAT_TOP
    # Back left: a big cube with a small one turned on top.
    tbox("Block_Cube_Big", (-0.78, 0.30, t), (-0.36, 0.72, t + 0.42), "red", root, c, bevel=0.035)
    tbox("Block_Cube_Small", (-0.70, 0.38, t + 0.42), (-0.44, 0.64, t + 0.68), "kid_blue", root, c,
         axis="Z", deg=22.0, bevel=0.03)
    # Back right: a drum.
    kit.cyl("Block_Drum", 0.48, 0.50, t, t + 0.32, 0.17, "orange", root, c, segs=12)
    kit.cyl("Block_Drum_Top", 0.48, 0.50, t + 0.32, t + 0.34, 0.14, "sun", root, c, segs=12)
    # Front right: a ramp rising toward +x.
    prism_xz("Block_Ramp", ((0.12, t), (0.78, t), (0.78, t + 0.30)), -0.78, -0.30, "purple", root, c)
    # Front left: two soft steps.
    tbox("Block_Step_Low", (-0.78, -0.76, t), (-0.22, -0.30, t + 0.15), "pink", root, c, bevel=0.03)
    tbox("Block_Step_High", (-0.78, -0.53, t + 0.15), (-0.22, -0.30, t + 0.30), "kid_blue", root, c, bevel=0.03)
    # Two balls in the middle.
    cafe.ball("Ball_0", 0.02, 0.06, t + 0.11, 0.11, "red", root, c)
    cafe.ball("Ball_1", 0.22, -0.16, t + 0.09, 0.09, "kid_green", root, c)


def build_play_slide(root, c):
    m = SLIDE_MAT
    tbox("Slide_Mat", (-0.92, -0.42, 0.0), (0.92, 0.42, m), "kid_blue", root, c, bevel=0.012)
    # Three solid steps up the -x end, the third tread level with the platform.
    rise = (SLIDE_TOP - m) / 3.0
    for k in range(3):
        top = SLIDE_TOP if k == 2 else m + rise * (k + 1)
        tbox("Slide_Step_%d" % k, (-0.92 + 0.12 * k, -0.25, m), (-0.56, 0.25, top), "kid_green", root, c, bevel=0.012)
    tbox("Slide_Platform", (-0.56, -0.30, m), (-0.10, 0.30, SLIDE_TOP), "red", root, c, bevel=0.015)
    for side, y0, y1 in (("L", 0.25, 0.30), ("R", -0.30, -0.25)):
        tbox("Slide_Wall_" + side, (-0.56, y0, SLIDE_TOP), (-0.10, y1, SLIDE_TOP + 0.35), "purple", root, c, bevel=0.012)
    # The chute: 29.5 degrees from the platform edge down to a runout that tapers from
    # 0.12 m to a 0.015 m lip on the mat, so the exit has no step down.
    xa, xb, za, zb = -0.10, 0.66, SLIDE_TOP, 0.12
    prism_xz("Slide_Chute", ((xa, za), (xa, za - 0.04), (xb, zb - 0.04), (xb, zb)), -0.22, 0.22, "sun", root, c)
    for side, y0, y1 in (("L", 0.22, 0.26), ("R", -0.26, -0.22)):
        prism_xz("Slide_Lip_" + side, ((xa, za + 0.08), (xa, za - 0.04), (xb, zb - 0.04), (xb, zb + 0.08)),
                 y0, y1, "orange", root, c)
    prism_xz("Slide_Runout", ((xb, m), (0.92, m), (0.92, m + 0.015), (xb, zb)), -0.22, 0.22, "sun", root, c)
    # One support panel under the chute.
    xs = 0.30
    under = za - (xs + 0.02 - xa) / (xb - xa) * (za - zb) - 0.04
    tbox("Slide_Support", (xs - 0.02, -0.18, m), (xs + 0.02, 0.18, under), "purple", root, c)


def sofa_section(root, c, half_w, body, cushion, prefix):
    """A lounge seat section across x in [-half_w, half_w]: base, arms, back and one
    seat cushion per 1 m cell (the sofa has two, the armchair one)."""
    # The seated root is at Godot z = SOFA_ROOT_Z. The cushion stops 0.22 m behind it
    # (Godot z 0.23), top at SEAT_TOP, and the base is set back under it (Godot z
    # 0.18), so the thighs clear the front edge and the calves the base: a cushion
    # reaching z 0.37 put the calves 0.07-0.11 m into the base. The cushion's 0.06 m
    # chamfer rounds its nose: the female thigh dips to 0.49 m about 0.04 m behind the
    # front edge, which a 0.03 m chamfer met 0.036 m deep, and her dress hem crossed a
    # nose at 0.20 m 0.032 m deep.
    front = SOFA_ROOT_Z - 0.22
    arm = 0.12
    for i, (sx, y) in enumerate(((-1, -0.15), (1, -0.15), (-1, 0.35), (1, 0.35))):
        cafe.cone("%s_Foot_%d" % (prefix, i), sx * (half_w - 0.07), y, 0.0, 0.10, 0.022, 0.03, "wood", root, c)
    tbox(prefix + "_Base", (-half_w, -(front - 0.05), 0.10), (half_w, 0.42, 0.38), body, root, c, bevel=0.02)
    for side, x0, x1 in (("L", -half_w, -half_w + arm), ("R", half_w - arm, half_w)):
        tbox("%s_Arm_%s" % (prefix, side), (x0, -0.30, 0.10), (x1, 0.42, 0.66), body, root, c, bevel=0.03)
    tbox(prefix + "_Back", (-half_w, 0.28, 0.38), (half_w, 0.42, 0.86), body, root, c, bevel=0.03)
    inner = half_w - arm
    seats = [(-inner, inner)] if half_w < 0.6 else [(-inner, -0.01), (0.01, inner)]
    for i, (x0, x1) in enumerate(seats):
        tbox("%s_Seat_%d" % (prefix, i), (x0, -front, 0.38), (x1, 0.20, SEAT_TOP), cushion, root, c, bevel=0.06)
        tbox("%s_BackCushion_%d" % (prefix, i), (x0 + 0.02, 0.18, SEAT_TOP), (x1 - 0.02, 0.30, 0.82), cushion,
             root, c, bevel=0.035, axis="X", deg=-8.0, pivot=((x0 + x1) / 2, 0.24, SEAT_TOP))


def build_lounge_sofa(root, c):
    sofa_section(root, c, 0.92, "teal", "cream", "Sofa")
    add_mounts("lounge_sofa", root, c)


def build_lounge_armchair(root, c):
    sofa_section(root, c, 0.42, "gold", "cream", "Armchair")
    add_mounts("lounge_armchair", root, c)


def build_work_desk(root, c):
    # Desk in the back row: Godot z -0.92..-0.20 (Blender y 0.20..0.92), top 0.78.
    tbox("Desk_Top", (-0.92, 0.20, 0.74), (0.92, 0.92, 0.78), "wood", root, c, bevel=0.01)
    for side, x0, x1 in (("L", -0.90, -0.86), ("R", 0.86, 0.90)):
        tbox("Desk_Leg_" + side, (x0, 0.26, 0.0), (x1, 0.86, 0.74), "dark", root, c)
    tbox("Desk_Modesty", (-0.86, 0.82, 0.36), (0.86, 0.85, 0.74), "dark", root, c)
    # The charging spine on the back edge: a socket plate and a green lamp per seat.
    tbox("Charge_Spine", (-0.80, 0.78, 0.78), (0.80, 0.90, 0.98), "white", root, c, bevel=0.012)
    for i, x in enumerate((-0.5, 0.5)):
        tbox("Charge_Socket_%d" % i, (x - 0.08, 0.772, 0.82), (x + 0.08, 0.78, 0.92), "dark", root, c)
        tbox("Charge_Lamp_%d" % i, (x - 0.02, 0.766, 0.935), (x + 0.02, 0.772, 0.955), "lamp_green", root, c)
    tbox("Charge_Sign", (-0.14, 0.82, 0.98), (0.14, 0.86, 1.20), "yellow", root, c, bevel=0.01)
    tbox("Charge_Sign_Bolt", (-0.03, 0.812, 1.02), (0.03, 0.82, 1.16), "dark", root, c, axis="Y", deg=-20.0)
    # A chair per seat in the front row, placed from the seated root: a 0.14 m cushion
    # with a 0.06 m chamfered nose on a rigid pan, 0.20-0.68 m behind the root (toward
    # Godot +Z, Blender -y), and the back at 0.64-0.68 m tilted 10 degrees. With the cafe
    # chair's numbers (back at 0.54-0.58 m, 6 degrees) the seated backs went 0.02 m into
    # it, and at 0.60-0.64 m and 8 degrees still 0.017 m. The female thigh dips to about
    # 0.49 m just behind the cushion nose, as on the sofa. The rigid pan stops 0.30 m
    # behind the root, under the cushion: flush with the nose, the hem of the female's
    # dress cut through it.
    ry = -DESK_ROOT_Z  # root in Blender y
    b0, b1, tilt = 0.64, 0.68, 10.0
    pan_top = SEAT_TOP - 0.14
    for side, x in (("L", -0.5), ("R", 0.5)):
        y0, y1 = ry - b1, ry - 0.20
        tbox("Chair_Pan_" + side, (x - 0.21, y0, pan_top - 0.03), (x + 0.21, ry - 0.30, pan_top), "dark", root, c)
        tbox("Chair_Seat_" + side, (x - 0.20, y0 + 0.01, pan_top), (x + 0.20, y1, SEAT_TOP), "teal", root, c,
             bevel=0.06)
        for k, (lx, ly) in enumerate(((-0.17, 0.33), (0.17, 0.33), (-0.17, b0), (0.17, b0))):
            tbox("Chair_Leg_%s%d" % (side, k), (x + lx - 0.015, ry - ly - 0.015, 0.0),
                 (x + lx + 0.015, ry - ly + 0.015, pan_top - 0.03), "dark", root, c)
        pivot = (x, ry - (b0 + b1) / 2, SEAT_TOP)
        for k, lx in enumerate((-0.17, 0.17)):
            tbox("Chair_BackPost_%s%d" % (side, k), (x + lx - 0.015, ry - b1, pan_top),
                 (x + lx + 0.015, ry - b0, 0.90), "dark", root, c, axis="X", deg=tilt, pivot=pivot)
        tbox("Chair_Back_" + side, (x - 0.20, ry - b1, 0.72), (x + 0.20, ry - b0, 0.92), "teal", root, c,
             axis="X", deg=tilt, pivot=pivot, bevel=0.01)
    add_mounts("work_desk", root, c)


PODIUM_X, PODIUM_Y, DECK = 2.92, 1.40, 0.30


def build_prize_podium(root, c):
    X, Y = PODIUM_X, PODIUM_Y
    tbox("Podium_Toe", (-X + 0.06, -Y + 0.06, 0.0), (X - 0.06, Y - 0.06, 0.05), "dark", root, c)
    tbox("Podium_Glow", (-X + 0.04, -Y + 0.04, 0.05), (X - 0.04, Y - 0.04, 0.08), "text_yellow", root, c)
    tbox("Podium_Body", (-X, -Y, 0.08), (X, Y, 0.26), "white", root, c, bevel=0.02)
    tbox("Podium_Trim", (-X, -Y, 0.26), (X, Y, 0.29), "gold", root, c, bevel=0.01)
    tbox("Podium_Carpet", (-X + 0.07, -Y + 0.07, 0.29), (X - 0.07, Y - 0.07, DECK), "red", root, c)
    # The raffle banner on the front fascia: one replaceable node, placeholder bars.
    face = cafe.group("Sign_Face", root, c)
    tbox("Sign_Face_Board", (-1.40, -Y - 0.015, 0.10), (1.40, -Y, 0.25), "dark", face, c)
    tbox("Sign_Face_Title", (-0.90, -Y - 0.02, 0.155), (0.90, -Y - 0.015, 0.195), "text_yellow", face, c)
    for i, x in enumerate((-1.15, 1.15)):
        tbox("Sign_Face_Star_%d" % i, (x - 0.07, -Y - 0.02, 0.14), (x + 0.07, -Y - 0.015, 0.21), "text_white", face, c)
    add_mounts("prize_podium", root, c)


# ---------------------------------------------------------------- register + checks

# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {
    "play_blocks": (build_play_blocks, (2, 2), (-0.92, -0.92, 0.0), (0.92, 0.92, MAT_TOP + 0.68)),
    "play_slide": (build_play_slide, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, SLIDE_TOP + 0.35)),
    "lounge_sofa": (build_lounge_sofa, (2, 1), (-0.92, -0.30, 0.0), (0.92, 0.42, 0.86)),
    "lounge_armchair": (build_lounge_armchair, (1, 1), (-0.42, -0.30, 0.0), (0.42, 0.42, 0.86)),
    "work_desk": (build_work_desk, (2, 2), (-0.92, -0.797, 0.0), (0.92, 0.92, 1.20)),
    "prize_podium": (build_prize_podium, (6, 3), (-2.92, -1.42, 0.0), (2.92, 1.40, 0.30)),
}
EXTRA_NODES = {
    "lounge_sofa": ["Mount_SitRoot_L", "Mount_SitRoot_R"],
    "lounge_armchair": ["Mount_SitRoot"],
    "work_desk": ["Mount_SitRoot_L", "Mount_SitRoot_R"],
    "prize_podium": ["Mount_Car", "Sign_Face", "Sign_Face_Mesh"],
}


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside ACTIVITIES, a name another kit owns,
    or an existing destination .glb that does not look like this builder's piece. The
    last test recognises the file by structure (<Piece>_ROOT plus the piece's required
    nodes); it is not proof of authorship, since the kit's exporter writes no marker."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the activities kit: %s" % bad)
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES)) & set(PIECES))
    if taken:
        kit.fail("activities names already owned by another kit: %s" % taken)
    clash = sorted(set(kit.NODE_TRANSLATIONS) & {m for s in ACTIVITIES.values() for m in s["mounts"]})
    if clash:
        kit.fail("mount names already in kit.NODE_TRANSLATIONS: %s" % clash)
    for p in pieces:
        out = os.path.join(kit.OUT_DIR, p + ".glb")
        if not os.path.exists(out):
            kit.log("GUARD %s new file %s" % (p, out))
            continue
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(p) + "_ROOT" in names and set(EXTRA_NODES.get(p, [])) <= names
        kit.log("GUARD %s existing file own=%s nodes=%s" % (p, own, sorted(names)))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    if kit.FAILS:
        sys.exit(1)


def register():
    """Add the activities swatches, pieces and required nodes to the kit."""
    kit.PALETTE.update(ACTIVITIES_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_mounts(written):
    """Re-read each written file: every mount a child of the root, unit scale, at its
    position, its +Z the stated way and its +Y up."""
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        nodes = js.get("nodes", [])
        by_name = {n.get("name"): i for i, n in enumerate(nodes)}
        root = nodes[by_name[kit.piece_title(piece) + "_ROOT"]]
        # kit.verify_written checks the root's translation and rotation, not its scale.
        if max(abs(s - 1.0) for s in root.get("scale", [1.0, 1.0, 1.0])) > 1e-6 or "matrix" in root:
            kit.fail("%s: root node is not unit scale: %s" % (piece, root))
        mounts = ACTIVITIES[piece]["mounts"]
        found = sorted(n.get("name") for n in nodes if n.get("name", "").startswith("Mount_"))
        if found != sorted(mounts):
            kit.fail("%s: mounts %s, expected %s" % (piece, found, sorted(mounts)))
        for name, (kind, pos, yaw) in mounts.items():
            if name not in by_name:
                kit.fail("%s: mount %s missing from the written file" % (piece, name))
                continue
            node = nodes[by_name[name]]
            child = by_name[name] in root.get("children", [])
            scale = node.get("scale", [1.0, 1.0, 1.0])
            t = node.get("translation", [0.0, 0.0, 0.0])
            x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
            q = Quaternion((w, x, y, z))
            facing = q @ Vector((0.0, 0.0, 1.0))
            up = q @ Vector((0.0, 1.0, 0.0))
            want = Vector((math.sin(math.radians(yaw)), 0.0, math.cos(math.radians(yaw))))
            kit.log("MOUNT %s %s kind=%s child_of_root=%s scale=%s pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f) "
                    "want_facing=(%.3f, %.3f, %.3f) up=(%.3f, %.3f, %.3f)"
                    % (piece, name, kind, child, scale, t[0], t[1], t[2], facing.x, facing.y, facing.z,
                       want.x, want.y, want.z, up.x, up.y, up.z))
            if not child or max(abs(s - 1.0) for s in scale) > 1e-6:
                kit.fail("%s: mount %s is not a unit-scale child of the root" % (piece, name))
            if max(abs(a - b) for a, b in zip(t, pos)) > 1e-4:
                kit.fail("%s: mount %s at %s, expected %s" % (piece, name, t, pos))
            if (facing - want).length > 1e-3 or (up - Vector((0.0, 1.0, 0.0))).length > 1e-3:
                kit.fail("%s: mount %s faces %s up %s, expected %s up +Y" % (piece, name, facing, up, want))
    data = {p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in ACTIVITIES.items()}
    kit.log("ACTIVITIES_DATA " + json.dumps(data))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_mounts(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
