"""Build the bus_gate_desk piece of the interior kit and export its .glb.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\gmmf-wt\\bus-gate-clarity\\tools\\blender\\interior\\build_bus_gate_desk.py'

Matches gate_desk's 2x1 footprint, 0.08 m inset, origin, zero Mount_* nodes,
2.02 m height, Sign_Face replaceable board node, and TP_Atlas_1A_D /
TP_Atlas_Lights_1A_D materials, while adding a wrap-around yellow + amber
shuttle stripe, amber post collars, amber board crown, and a front/back shuttle
bus pictogram so players immediately tell Bus Gate Desks apart from regular
Gate Desks.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "bus-gate-desk", "bus_gate_desk.blend")
INSET = 0.08
PIECE = "bus_gate_desk"
FOOTPRINT = (2, 1)

BOARD_X = 0.86
BOARD_Y = (0.24, 0.36)
BOARD_Z = (1.54, 1.94)
CAP_Z = (1.94, 2.02)
POST_X = 0.80
MONITOR_X = -0.15

BUS_PALETTE = {
    "orange": act.ACTIVITIES_PALETTE["orange"],
}


def build_bus_gate_desk(root, c):
    # Counter: dark toe kick, blue body slightly recessed inside +-0.89 / -0.37 so
    # wrap-around yellow/amber shuttle stripes sit flush without coplanar overlap.
    cafe.tbox("Desk_ToeKick", (-0.88, -0.34, 0.0), (0.88, 0.38, 0.08), "dark", root, c)
    cafe.tbox("Desk_Body", (-0.89, -0.37, 0.08), (0.89, 0.39, 0.94), "blue", root, c)

    # Wrap-around shuttle stripes (front + both ends): yellow upper band, dark rule,
    # warm amber lower stripe.
    for z0, z1, pal, tag in (
        (0.68, 0.80, "yellow", "StripeYellow"),
        (0.64, 0.68, "dark", "StripeRule"),
        (0.50, 0.64, "orange", "StripeAmber"),
    ):
        cafe.tbox("Desk_%s_F" % tag, (-0.902, -0.392, z0), (0.902, -0.37, z1), pal, root, c)
        cafe.tbox("Desk_%s_L" % tag, (-0.902, -0.37, z0), (-0.89, 0.39, z1), pal, root, c)
        cafe.tbox("Desk_%s_R" % tag, (0.89, -0.37, z0), (0.902, 0.39, z1), pal, root, c)

    cafe.tbox("Desk_Top", (-0.92, -0.42, 0.94), (0.92, 0.42, 1.00), "top", root, c, bevel=0.015)

    # Front shuttle accent badge on left counter face below the amber stripe.
    cafe.tbox("Desk_Badge_Bg", (-0.76, -0.384, 0.22), (-0.30, -0.37, 0.40), "yellow", root, c)
    cafe.tbox("Desk_Badge_Bus", (-0.72, -0.392, 0.26), (-0.34, -0.384, 0.37), "orange", root, c)
    cafe.tbox("Desk_Badge_Win", (-0.69, -0.398, 0.31), (-0.37, -0.392, 0.355), "screen_sky", root, c)
    for tag, wx0, wx1 in (("L", -0.68, -0.60), ("R", -0.46, -0.38)):
        cafe.tbox("Desk_Badge_Whl_%s" % tag, (wx0, -0.398, 0.235), (wx1, -0.392, 0.27), "dark", root, c)

    # Agent monitor on staff side and boarding pass reader on passenger side.
    svc.staff_monitor("Desk", MONITOR_X, root, c)
    cafe.tbox("Reader_Stand", (0.48, -0.36, 1.00), (0.70, -0.16, 1.04), "dark", root, c, bevel=0.008)
    cafe.tbox("Reader_Neck", (0.56, -0.28, 1.04), (0.62, -0.24, 1.12), "metal", root, c)
    pivot = (0.59, -0.26, 1.12)
    cafe.tbox(
        "Reader_Head",
        (0.50, -0.31, 1.12),
        (0.68, -0.21, 1.20),
        "dark",
        root,
        c,
        deg=-20.0,
        pivot=pivot,
        bevel=0.01,
    )
    cafe.tbox(
        "Reader_Lamp",
        (0.53, -0.315, 1.14),
        (0.65, -0.305, 1.18),
        "lamp_green",
        root,
        c,
        deg=-20.0,
        pivot=pivot,
    )

    # Posts with amber shuttle collars supporting the overhead board and amber canopy cap.
    for side, x in (("L", -POST_X), ("R", POST_X)):
        kit.cyl("Board_Post_" + side, x, 0.30, 1.00, BOARD_Z[0], 0.03, "frame", root, c)
        kit.cyl("Board_Collar_" + side, x, 0.30, 1.12, 1.38, 0.044, "orange", root, c)

    cafe.tbox(
        "Board_Frame",
        (-BOARD_X, BOARD_Y[0], BOARD_Z[0]),
        (BOARD_X, BOARD_Y[1], BOARD_Z[1]),
        "dark",
        root,
        c,
        bevel=0.012,
    )
    cafe.tbox(
        "Board_Cap",
        (-0.88, BOARD_Y[0] - 0.02, CAP_Z[0]),
        (0.88, BOARD_Y[1] + 0.02, CAP_Z[1]),
        "orange",
        root,
        c,
        bevel=0.012,
    )

    # Overhead shuttle bus pictogram on left wing of the board (front & back).
    for side, y0, y1, y2, y3, y4 in (
        ("Front", 0.234, 0.24, 0.228, 0.234, 0.223),
        ("Back", 0.36, 0.366, 0.366, 0.372, 0.377),
    ):
        a0, a1 = sorted((y0, y1))
        b0, b1 = sorted((y2, y3))
        c0, c1 = sorted((y3, y4))
        cafe.tbox("BusBadge_%s_Bg" % side, (-0.81, a0, 1.60), (-0.41, a1, 1.88), "yellow", root, c)
        cafe.tbox("BusBadge_%s_Bus" % side, (-0.77, b0, 1.66), (-0.45, b1, 1.83), "orange", root, c)
        cafe.tbox("BusBadge_%s_Win" % side, (-0.74, c0, 1.75), (-0.48, c1, 1.805), "screen_sky", root, c)
        for tag, wx0, wx1 in (("L", -0.73, -0.65), ("R", -0.57, -0.49)):
            cafe.tbox("BusBadge_%s_Whl_%s" % (side, tag), (wx0, c0, 1.625), (wx1, c1, 1.675), "dark", root, c)

    # Replaceable Sign_Face to the right of the bus pictogram on both front and back.
    face = bpy.data.objects.new("Sign_Face", None)
    c.objects.link(face)
    face.parent = root
    for side, y0, y1, gy0, gy1 in (("Front", 0.234, 0.24, 0.229, 0.234), ("Back", 0.36, 0.366, 0.366, 0.371)):
        cafe.tbox("Sign_Face_%s" % side, (-0.36, y0, 1.60), (0.80, y1, 1.88), "yellow", face, c)
        if side == "Front":
            cafe.tbox("Sign_Face_%s_Letter" % side, (-0.30, gy0, 1.64), (-0.06, gy1, 1.84), "dark", face, c)
            cafe.tbox("Sign_Face_%s_Text" % side, (0.02, gy0, 1.71), (0.72, gy1, 1.77), "dark", face, c)
        else:
            cafe.tbox("Sign_Face_%s_Letter" % side, (0.48, gy0, 1.64), (0.72, gy1, 1.84), "dark", face, c)
            cafe.tbox("Sign_Face_%s_Text" % side, (-0.28, gy0, 1.71), (0.40, gy1, 1.77), "dark", face, c)


PIECES = {PIECE: (build_bus_gate_desk, FOOTPRINT, (-0.92, -0.42, 0.0), (0.92, 0.42, CAP_Z[1]))}
EXTRA_NODES = {PIECE: ["Sign_Face", "Sign_Face_Mesh"]}


def guard():
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES)) & set(PIECES))
    if taken:
        kit.fail("bus gate names already owned by another kit: %s" % taken)
    out = os.path.join(kit.OUT_DIR, PIECE + ".glb")
    if os.path.exists(out):
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(PIECE) + "_ROOT" in names and set(EXTRA_NODES[PIECE]) <= names
        kit.log("GUARD %s existing file own=%s nodes=%s" % (PIECE, own, sorted(names)))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    else:
        kit.log("GUARD %s new file %s" % (PIECE, out))
    if kit.FAILS:
        sys.exit(1)


def register():
    kit.PALETTE.update(BUS_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        mounts = [n.get("name") for n in js.get("nodes", []) if n.get("name", "").startswith("Mount_")]
        kit.log("MOUNTS %s %s" % (piece, mounts))
        if mounts:
            kit.fail("%s: bus gate desk carries mounts %s" % (piece, mounts))
        objs = svc.import_written(out)
        lo, hi = svc.mesh_bounds(objs)
        w, d = FOOTPRINT
        lim_x, lim_z = w / 2.0 - INSET, d / 2.0 - INSET
        gz = (-hi.y, -lo.y)
        over = max(abs(lo.x) - lim_x, hi.x - lim_x, abs(gz[0]) - lim_z, gz[1] - lim_z, -lo.z)
        kit.log(
            "INSET %s footprint=%dx%d limit_x=+-%.3f limit_z=+-%.3f godot_x=[%.3f, %.3f] "
            "godot_z=[%.3f, %.3f] min_y=%.4f overhang=%.4f"
            % (piece, w, d, lim_x, lim_z, lo.x, hi.x, gz[0], gz[1], lo.z, max(over, 0.0))
        )
        if over > 1e-3:
            kit.fail("%s: written mesh leaves the footprint inset by %.4f m" % (piece, over))
        gap_x = POST_X - 0.044 - (abs(MONITOR_X) + 0.20)
        gap_z = BOARD_Z[0] - 1.36
        kit.log("CLEAR %s collar_to_monitor_x=%.3f monitor_to_board_z=%.3f" % (piece, gap_x, gap_z))
        if gap_x <= 0.0 or gap_z <= 0.0:
            kit.fail("%s: board/collars meet the agent monitor" % piece)
        body = [o for o in objs if o.type == "MESH"]
        kit.log("OBJECTS %s %s" % (piece, sorted(o.name for o in body)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    guard()
    register()
    check_written(kit.main(default_pieces=[PIECE], blend_out=BLEND_OUT))
