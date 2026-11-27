"""Build airside_exit_door.glb in the Toon Series interior kit.

Tier-1 one-way Airside Exit door matching wall_door.glb's cell-edge wall frame
footprint (1.0 m edge, 0.80 m x 2.20 m clear opening, origin at edge midpoint on
floor y=0, front +Z Godot / -Y Blender).

Orientation in Godot at facing 0:
- Front (+Z Godot / -Y Blender) = airside approach face (green EXIT sign + white
  EXIT silhouette + green threshold chevron + green jamb light bars).
- Back (-Z Godot / +Y Blender) = landside back face (red DO NOT ENTER sign bar +
  red/amber warning lintel stripe + red jamb light bars + red stop line).
- Open-parked double aluminum/glass sliding leaves sit on Door_Track (Door_Leaf_L
  at (-0.61, 0, 0.12), Door_Leaf_R at (+0.61, 0, 0.12)) matching wall_door.glb.

Run from repo root (or worktree root):
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/build_airside_exit_door.py < /dev/null
"""

import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402

PIECE = "airside_exit_door"
BLEND_OUT = str(
    Path(kit.REPO, "tools", "blender", "out", "airside-exit-door", "airside_exit_door.blend").resolve()
)

SIGN_Z0 = 2.34
SIGN_Z1 = 2.66
SIGN_HALF_W = 0.46
SIGN_Y_FRONT = -0.17
SIGN_Y_BACK = 0.10

DOOR_PALETTE = {
    "pine_green": ("TP_Atlas_1A_D", 27, 1, 0.35, 0.0),
    "exit_green": ("TP_Atlas_1A_D", 11, 0, 0.35, 0.0),
    "slate_dark": ("TP_Atlas_1A_D", 18, 1, 0.40, 0.0),
    "red": ("TP_Atlas_1A_D", 31, 0, 0.30, 0.0),
    "orange": ("TP_Atlas_1A_D", 29, 0, 0.30, 0.0),
    "lamp_red": ("TP_Atlas_Lights_1A_D", 3, 0, 0.50, 0.0),
    "lamp_amber": ("TP_Atlas_Lights_1A_D", 2, 1, 0.50, 0.0),
}


def _exit_letters(y0, y1, root, c):
    """Block letters E X I T + exit chevron in text_white on the front sign face."""
    z0, z1 = 2.41, 2.57
    zm = (z0 + z1) / 2.0
    t = 0.025
    # E
    cafe.tbox("Sign_E_V", (-0.37, y0, z0), (-0.37 + t, y1, z1), "text_white", root, c)
    cafe.tbox("Sign_E_T", (-0.37 + t, y0, z1 - t), (-0.28, y1, z1), "text_white", root, c)
    cafe.tbox("Sign_E_M", (-0.37 + t, y0, zm - t * 0.45), (-0.295, y1, zm + t * 0.45), "text_white", root, c)
    cafe.tbox("Sign_E_B", (-0.37 + t, y0, z0), (-0.28, y1, z0 + t), "text_white", root, c)
    # X (two diagonal strokes around x=-0.18)
    for deg in (32.0, -32.0):
        cafe.tbox(
            "Sign_X_%+d" % int(deg),
            (-0.193, y0, z0 - 0.005),
            (-0.167, y1, z1 + 0.005),
            "text_white",
            root,
            c,
            axis="Y",
            deg=deg,
            pivot=(-0.18, (y0 + y1) * 0.5, zm),
        )
    # I
    cafe.tbox("Sign_I", (-0.065, y0, z0), (-0.065 + t, y1, z1), "text_white", root, c)
    # T
    cafe.tbox("Sign_T_Top", (0.01, y0, z1 - t), (0.14, y1, z1), "text_white", root, c)
    cafe.tbox("Sign_T_Stem", (0.075 - t * 0.5, y0, z0), (0.075 + t * 0.5, y1, z1 - t), "text_white", root, c)
    # Bold right-hand downward arrow pointing into the doorway
    cafe.tbox("Sign_Arrow_Shaft", (0.28 - 0.016, y0, 2.465), (0.28 + 0.016, y1, z1), "text_white", root, c)
    # Stepped triangular/chevron head (clean horizontal bars tapering to tip at z=2.41)
    for k, (hw_step, za, zb) in enumerate(((0.068, 2.455, 2.478), (0.044, 2.432, 2.455), (0.020, 2.410, 2.432))):
        cafe.tbox("Sign_Arrow_Head_%d" % k, (0.28 - hw_step, y0, za), (0.28 + hw_step, y1, zb), "text_white", root, c)


def build_airside_exit_door(root, c):
    hw = kit.DOOR_W / 2.0
    jamb = (1.0 - kit.DOOR_W) / 2.0 - 0.04  # 0.06 m

    # Wall jambs & skirting matching wall_door.glb
    for side, x0, x1 in (("L", -0.5, -0.5 + jamb), ("R", 0.5 - jamb, 0.5)):
        cafe.tbox("Door_Skirting_" + side, (x0, -kit.TRIM_T / 2.0, 0.0), (x1, kit.TRIM_T / 2.0, 0.12), "trim", root, c)
        cafe.tbox(
            "Door_Jamb_" + side, (x0, -kit.WALL_T / 2.0, 0.12), (x1, kit.WALL_T / 2.0, kit.DOOR_H + 0.04), "wall", root, c
        )

    # Wall lintel & split caps around the raised EXIT sign housing so zero faces coplanar-overlap
    cafe.tbox("Door_Lintel", (-0.5, -kit.WALL_T / 2.0, kit.DOOR_H + 0.04), (0.5, kit.WALL_T / 2.0, SIGN_Z0), "wall", root, c)
    for side, x0, x1 in (("L", -0.5, -SIGN_HALF_W), ("R", SIGN_HALF_W, 0.5)):
        cafe.tbox(
            "Door_Lintel_End_" + side,
            (x0, -kit.WALL_T / 2.0, SIGN_Z0),
            (x1, kit.WALL_T / 2.0, kit.WALL_H - 0.06),
            "wall",
            root,
            c,
        )
        cafe.tbox("Door_Cap_" + side, (x0, -kit.TRIM_T / 2.0, kit.WALL_H - 0.06), (x1, kit.TRIM_T / 2.0, kit.WALL_H), "trim", root, c)

    # Brushed aluminum door frame (0.80 m x 2.20 m clear opening)
    for side, x0, x1 in (("L", -hw - 0.04, -hw), ("R", hw, hw + 0.04)):
        cafe.tbox("Door_Frame_" + side, (x0, -0.075, 0.0), (x1, 0.075, kit.DOOR_H + 0.04), "metal", root, c, bevel=0.003)
    cafe.tbox("Door_Frame_Top", (-hw - 0.04, -0.075, kit.DOOR_H), (hw + 0.04, 0.075, kit.DOOR_H + 0.04), "metal", root, c, bevel=0.003)
    cafe.tbox("Door_Threshold", (-hw, -0.075, 0.0), (hw, 0.075, 0.008), "metal", root, c)

    # Airside approach face (+Z Godot / -Y Blender): green jamb indicator strips & overhead sensor pod
    for side, x0, x1 in (("L", -hw - 0.032, -hw - 0.008), ("R", hw + 0.008, hw + 0.032)):
        cafe.tbox("Airside_Jamb_Glow_" + side, (x0, -0.080, 1.05), (x1, -0.075, 1.92), "lamp_green", root, c)
    cafe.tbox("Airside_Sensor_Pod", (-0.14, -0.095, 2.20), (0.14, -0.075, 2.26), "slate_dark", root, c, bevel=0.004)
    cafe.tbox("Airside_Sensor_Lens", (-0.09, -0.098, 2.215), (0.09, -0.095, 2.245), "lamp_green", root, c)

    # Airside approach threshold arrow mat (-Y Blender, <= 8 mm tall so footsteps clear smoothly)
    cafe.tbox("Airside_Mat", (-0.36, -0.20, 0.0), (0.36, -0.075, 0.005), "dark", root, c)
    cafe.tbox("Airside_Floor_Arrow_Shaft", (-0.04, -0.185, 0.005), (0.04, -0.115, 0.008), "lamp_green", root, c)
    for tag, sx, deg in (("L", -0.055, -38.0), ("R", 0.055, 38.0)):
        cafe.tbox(
            "Airside_Floor_Arrow_Wing_" + tag,
            (sx - 0.018, -0.13, 0.005),
            (sx + 0.018, -0.085, 0.008),
            "lamp_green",
            root,
            c,
            axis="Z",
            deg=deg,
            pivot=(0.0, -0.092, 0.0065),
        )

    # Landside back face (-Z Godot / +Y Blender): red/amber DO NOT ENTER cues
    for side, x0, x1 in (("L", -hw - 0.032, -hw - 0.008), ("R", hw + 0.008, hw + 0.032)):
        cafe.tbox("Landside_Jamb_Glow_" + side, (x0, 0.075, 1.05), (x1, 0.080, 1.92), "lamp_red", root, c)
    # Red + amber warning bar across the back lintel above the frame
    cafe.tbox("Landside_Warn_Bar", (-0.42, 0.06, 2.245), (0.42, 0.076, 2.33), "red", root, c)
    for side, x0, x1 in (("L", -0.42, -0.32), ("R", 0.32, 0.42)):
        cafe.tbox("Landside_Warn_Tip_" + side, (x0, 0.076, 2.245), (x1, 0.082, 2.33), "orange", root, c)
    cafe.tbox("Landside_Warn_Mid", (-0.28, 0.076, 2.275), (0.28, 0.082, 2.300), "text_white", root, c)
    # Thin red stop line at landside threshold
    cafe.tbox("Landside_Stop_Mat", (-0.38, 0.075, 0.0), (0.38, 0.13, 0.006), "red", root, c)

    # Sliding track matching wall_door.glb (-0.86..0.86, y in -0.15..-0.10, z in 2.24..2.34)
    cafe.tbox("Door_Track", (-0.86, -0.15, kit.DOOR_H + 0.04), (0.86, -0.10, SIGN_Z0), "slate_dark", root, c)

    # Prominent Overhead Illuminated EXIT Sign Box (z in 2.34..2.66 -> proud above 2.50 wall cap!)
    cafe.tbox("Sign_Housing", (-SIGN_HALF_W, SIGN_Y_FRONT, SIGN_Z0), (SIGN_HALF_W, SIGN_Y_BACK, SIGN_Z1), "slate_dark", root, c, bevel=0.01)
    # Balanced top indicator strips: airside half green, landside half red, separated by housing
    cafe.tbox("Sign_Top_Green", (-0.42, SIGN_Y_FRONT + 0.02, SIGN_Z1), (0.42, -0.045, SIGN_Z1 + 0.004), "lamp_green", root, c)
    cafe.tbox("Sign_Top_Red", (-0.42, -0.025, SIGN_Z1), (0.42, SIGN_Y_BACK - 0.02, SIGN_Z1 + 0.004), "lamp_red", root, c)

    # Front EXIT face (-Y Blender / +Z Godot)
    cafe.tbox("Sign_Front_Bg", (-0.42, SIGN_Y_FRONT - 0.005, SIGN_Z0 + 0.03), (0.42, SIGN_Y_FRONT, SIGN_Z1 - 0.05), "lamp_green", root, c)
    _exit_letters(SIGN_Y_FRONT - 0.010, SIGN_Y_FRONT - 0.005, root, c)

    # Back DO NOT ENTER face (+Y Blender / -Z Godot)
    cafe.tbox("Sign_Back_Bg", (-0.42, SIGN_Y_BACK, SIGN_Z0 + 0.03), (0.42, SIGN_Y_BACK + 0.005, SIGN_Z1 - 0.05), "lamp_red", root, c)
    cafe.tbox("Sign_Back_Bar", (-0.28, SIGN_Y_BACK + 0.005, 2.465), (0.28, SIGN_Y_BACK + 0.011, 2.515), "text_white", root, c)
    for side, x0, x1 in (("L", -0.38, -0.32), ("R", 0.32, 0.38)):
        cafe.tbox("Sign_Back_Warn_" + side, (x0, SIGN_Y_BACK + 0.005, SIGN_Z0 + 0.05), (x1, SIGN_Y_BACK + 0.010, SIGN_Z1 - 0.07), "lamp_amber", root, c)

    # Open-parked double aluminum & glass leaves on Door_Track (exact wall_door.glb positions +-0.61)
    for side, sign in (("L", -1.0), ("R", 1.0)):
        leaf = bpy.data.objects.new("Door_Leaf_" + side, None)
        c.objects.link(leaf)
        leaf.parent = root
        leaf.empty_display_size = 0.2
        leaf.location = (sign * 0.61, -0.12, 0.0)
        lw = 0.21
        z0, z1, st = 0.02, kit.DOOR_H + 0.03, 0.04
        cafe.tbox("Door_Leaf_%s_StileA" % side, (-lw, -0.012, z0), (-lw + st, 0.012, z1), "metal", leaf, c)
        cafe.tbox("Door_Leaf_%s_StileB" % side, (lw - st, -0.012, z0), (lw, 0.012, z1), "metal", leaf, c)
        cafe.tbox("Door_Leaf_%s_RailLow" % side, (-lw + st, -0.012, z0), (lw - st, 0.012, z0 + 0.08), "metal", leaf, c)
        cafe.tbox("Door_Leaf_%s_RailTop" % side, (-lw + st, -0.012, z1 - st), (lw - st, 0.012, z1), "metal", leaf, c)
        cafe.tbox("Door_Leaf_%s_Glass" % side, (-lw + st, -0.008, z0 + 0.08), (lw - st, 0.008, z1 - st), "glass", leaf, c)
        # Green push/safety bar across each leaf
        cafe.tbox("Door_Leaf_%s_PushBar" % side, (-lw + st, -0.018, 0.96), (lw - st, 0.018, 1.03), "pine_green", leaf, c)


PIECES = {
    PIECE: (
        build_airside_exit_door,
        "edge",
        (-0.86, -0.20, 0.0),
        (0.86, 0.13, SIGN_Z1 + 0.004),
    )
}
EXTRA_NODES = {
    PIECE: ["Door_Leaf_L", "Door_Leaf_L_Mesh", "Door_Leaf_R", "Door_Leaf_R_Mesh"],
}


def guard():
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES)) & set(PIECES))
    if taken:
        kit.fail("airside_exit_door name clash: %s" % taken)
    out = os.path.join(kit.OUT_DIR, PIECE + ".glb")
    if os.path.exists(out):
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(PIECE) + "_ROOT" in names and set(EXTRA_NODES[PIECE]) <= names
        kit.log("GUARD %s existing file own=%s" % (PIECE, own))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    else:
        kit.log("GUARD %s new file %s" % (PIECE, out))
    if kit.FAILS:
        sys.exit(1)


def register():
    kit.PALETTE.update(DOOR_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    kit.NODE_TRANSLATIONS["Door_Leaf_L"] = (-0.61, 0.0, 0.12)
    kit.NODE_TRANSLATIONS["Door_Leaf_R"] = (0.61, 0.0, 0.12)


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        objs = svc.import_written(out)
        lo, hi = svc.mesh_bounds(objs)
        kit.log(
            "CLEARANCE %s godot_x=[%.3f, %.3f] godot_y=[%.3f, %.3f] godot_z=[%.3f, %.3f]"
            % (piece, lo.x, hi.x, lo.z, hi.z, -hi.y, -lo.y)
        )
        # Prove clear 0.80 m x 2.20 m doorway opening has zero crossing polygons (and negative control hits jamb/frame)
        open_lo = Vector((-0.395, -0.070, 0.015))
        open_hi = Vector((0.395, 0.070, 2.195))
        polys = []
        for ob in objs:
            if ob.type != "MESH":
                continue
            mw = ob.matrix_world
            for p in ob.data.polygons:
                polys.append([mw @ ob.data.vertices[i].co for i in p.vertices])
        clash = sum(1 for p in polys if svc.clip_to_box(p, open_lo, open_hi, 1e-4))
        ctrl_lo = Vector((-0.45, -0.070, 0.50))
        ctrl_hi = Vector((-0.39, 0.070, 1.50))
        ctrl_hit = sum(1 for p in polys if svc.clip_to_box(p, ctrl_lo, ctrl_hi, 1e-4))
        kit.log("OPENING %s clear_crossing=%d control_jamb_hit=%d" % (piece, clash, ctrl_hit))
        if clash or not ctrl_hit:
            kit.fail("%s: doorway opening blocked (%d) or jamb control missed (%d)" % (piece, clash, ctrl_hit))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    kit.log("AIRSIDE_EXIT_DOOR REPO=%s OUT_DIR=%s" % (kit.REPO, kit.OUT_DIR))
    guard()
    register()
    check_written(kit.main(default_pieces=[PIECE], blend_out=BLEND_OUT))
