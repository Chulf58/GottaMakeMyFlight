"""Build the gate desk of the interior kit, one .glb.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_gate_kit.py'

The gate desk (Gates 2/4, board 51bcad8a; user ruling gates-are-placed-gate-desks-each-
desk-links-automatically-to): the 2x1 boarding podium a player places by a north exit to
make a gate. It is unstaffed for now (decision gates-technical-design-gate-desks-link-to-
north-exits-one-st, defaults), so it has no Mount_* nodes. It reads apart from the info
desk (white body, blue band, 'i' totem) at play zoom: a blue body with a yellow band, a
boarding-pass reader with a green lamp on the passenger side, an agent monitor on the
staff side, and a yellow gate board on two posts above head height. The board's faces
(front and back) are the replaceable Sign_Face node: a dark letter box and two dark text
bars, the way the info screen's bars read as text at range.

The piece uses build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, furniture 0.08 m inside its footprint,
every face on a measured Toon atlas swatch, the written file re-read and checked), the
way build_services_kit.py does. register() adds the piece and its required nodes to the
kit's tables; the kit's main() builds, exports and verifies it; then check_written()
re-reads the written file: no Mount_* nodes, its mesh bounds inside the footprint inset,
and the board clear of the agent monitor.

Before anything is built, guard() refuses a name another kit owns and an existing
destination .glb that is not this builder's piece.
"""

import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402  (helpers only; act.register() is never called)
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402  (helpers only; svc.register() is never called)

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "gates-2", "gate_kit.blend")
INSET = 0.08
PIECE = "gate_desk"
FOOTPRINT = (2, 1)

# The board on its posts: Blender x range, y range (the back, staff side), z range.
BOARD_X = 0.86
BOARD_Y = (0.24, 0.36)
BOARD_Z = (1.58, 2.02)
POST_X = 0.80
# The agent monitor (svc.staff_monitor at x = MONITOR_X): x +-0.20, y 0.26..0.33,
# z up to 1.36. It must stay clear of the posts and under the board.
MONITOR_X = -0.15


def build_gate_desk(root, c):
    # The counter: toe kick, blue body, yellow band on the passenger face, light top.
    svc.counter("Desk", -0.90, 0.90, 1.00, "blue", "yellow", "top", root, c)
    # A thin dark rule under the band, so the band reads as a stripe at range.
    cafe.tbox("Desk_Rule", (-0.86, -0.40, 0.60), (0.86, -0.38, 0.62), "dark", root, c)
    # The agent's monitor on the staff side.
    svc.staff_monitor("Desk", MONITOR_X, root, c)
    # The boarding-pass reader on the passenger side: a dark stand, a tilted head
    # facing the passenger, a green lamp on its front.
    cafe.tbox("Reader_Stand", (0.48, -0.36, 1.00), (0.70, -0.16, 1.04), "dark", root, c, bevel=0.008)
    cafe.tbox("Reader_Neck", (0.56, -0.28, 1.04), (0.62, -0.24, 1.12), "metal", root, c)
    pivot = (0.59, -0.26, 1.12)
    cafe.tbox("Reader_Head", (0.50, -0.31, 1.12), (0.68, -0.21, 1.20), "dark", root, c, deg=-20.0,
              pivot=pivot, bevel=0.01)
    cafe.tbox("Reader_Lamp", (0.53, -0.315, 1.14), (0.65, -0.305, 1.18), "lamp_green", root, c, deg=-20.0,
              pivot=pivot)
    # Two posts at the back corners hold the gate board above head height.
    for side, x in (("L", -POST_X), ("R", POST_X)):
        kit.cyl("Board_Post_" + side, x, 0.30, 1.00, BOARD_Z[0], 0.03, "frame", root, c)
    cafe.tbox("Board_Frame", (-BOARD_X, BOARD_Y[0], BOARD_Z[0]), (BOARD_X, BOARD_Y[1], BOARD_Z[1]), "dark",
              root, c, bevel=0.015)
    # Sign_Face holds both faces of the board (yellow, a dark letter box, two text
    # bars), so a later gate letter can replace it as one node.
    face = bpy.data.objects.new("Sign_Face", None)
    c.objects.link(face)
    face.parent = root
    for side, y0, y1, gy0, gy1 in (("Front", 0.234, 0.24, 0.229, 0.234), ("Back", 0.36, 0.366, 0.366, 0.371)):
        cafe.tbox("Sign_Face_%s" % side, (-0.80, y0, 1.62), (0.80, y1, 1.98), "yellow", face, c)
        # Seen from its own side the letter box is on the left: Blender -x from the
        # front, +x from the back.
        lx = -1.0 if side == "Front" else 1.0
        x0, x1 = sorted((lx * 0.74, lx * 0.48))
        cafe.tbox("Sign_Face_%s_Letter" % side, (x0, gy0, 1.67), (x1, gy1, 1.93), "dark", face, c)
        # One thin text bar to the right of the letter box (seen from that side), so
        # most of the face stays yellow and the board reads yellow at play zoom.
        bx0, bx1 = sorted((lx * 0.40, lx * -0.56))
        cafe.tbox("Sign_Face_%s_Text" % side, (bx0, gy0, 1.77), (bx1, gy1, 1.83), "dark", face, c)


# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {PIECE: (build_gate_desk, FOOTPRINT, (-0.92, -0.42, 0.0), (0.92, 0.42, BOARD_Z[1]))}
EXTRA_NODES = {PIECE: ["Sign_Face", "Sign_Face_Mesh"]}


def guard():
    """Refuse before any build: a name another kit owns, or an existing destination .glb
    that does not look like this builder's piece (<Piece>_ROOT plus the required nodes)."""
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES)) & set(PIECES))
    if taken:
        kit.fail("gate names already owned by another kit: %s" % taken)
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
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_written(written):
    """Re-read the written file: no mounts, every vertex inside the footprint inset,
    and the board and its posts clear of the agent monitor."""
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        mounts = [n.get("name") for n in js.get("nodes", []) if n.get("name", "").startswith("Mount_")]
        kit.log("MOUNTS %s %s" % (piece, mounts))
        if mounts:
            kit.fail("%s: the unstaffed gate desk carries mounts %s" % (piece, mounts))
        objs = svc.import_written(out)
        lo, hi = svc.mesh_bounds(objs)
        w, d = FOOTPRINT
        lim_x, lim_z = w / 2.0 - INSET, d / 2.0 - INSET
        gz = (-hi.y, -lo.y)
        over = max(abs(lo.x) - lim_x, hi.x - lim_x, abs(gz[0]) - lim_z, gz[1] - lim_z, -lo.z)
        kit.log("INSET %s footprint=%dx%d limit_x=+-%.3f limit_z=+-%.3f godot_x=[%.3f, %.3f] "
                "godot_z=[%.3f, %.3f] min_y=%.4f overhang=%.4f"
                % (piece, w, d, lim_x, lim_z, lo.x, hi.x, gz[0], gz[1], lo.z, max(over, 0.0)))
        if over > 1e-3:
            kit.fail("%s: written mesh leaves the footprint inset by %.4f m" % (piece, over))
        # The monitor (svc.staff_monitor) spans x MONITOR_X +-0.20 and reaches 1.36 m;
        # the posts stand at +-POST_X and the board starts at BOARD_Z[0].
        gap_x = POST_X - 0.03 - (abs(MONITOR_X) + 0.20)
        gap_z = BOARD_Z[0] - 1.36
        kit.log("CLEAR %s post_to_monitor_x=%.3f monitor_to_board_z=%.3f" % (piece, gap_x, gap_z))
        if gap_x <= 0.0 or gap_z <= 0.0:
            kit.fail("%s: the board or its posts meet the agent monitor" % piece)
        body = [o for o in objs if o.type == "MESH"]
        kit.log("OBJECTS %s %s" % (piece, sorted(o.name for o in body)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    guard()
    register()
    check_written(kit.main(default_pieces=[PIECE], blend_out=BLEND_OUT))
