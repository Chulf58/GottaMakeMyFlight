"""Build the retail kit for the duty-free and fashion shops, one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_retail_kit.py' [-- piece ...]

Pieces (Furniture 4/4, F4-R; decision duty-free-and-fashion-shops-get-their-own-blender-retail-kit,
store set from furniture-set-modelled-on-copenhagen-airport-decor-calms-pas, counters and
browse slots from store-mechanics-draw-a-room-then-furnish-it-required-pieces). All 2x1:
- duty_free_shelf: a wall gondola on the back of the footprint whose sides slope back as
  they rise, so each shelf sits behind the one below and its stock shows from the game
  camera. Gift boxes on the plinth, two rows of bottles (body, neck and cap on the
  measured swatches) on the next two shelves, perfume boxes and bottles on the top one,
  a centre divider (one section per browse slot) and a purple header with a gold strip.
  Mount_Browse_0 and _1 are the cells in front of the -x and +x cells, facing the shelf,
  as on kiosk_display (ShopLayout's browse slots).
- duty_free_till: the services kit's counter section with the till on the -x cell; on
  the +x cell a tray of triangular chocolate bars, a stepped perfume tester stand and a
  purple sign board on a post at the back, over the +x half only so the till stays in
  view from behind (as on kiosk_counter). Mount_Order in front of the -x cell facing the
  counter, Mount_Staff behind it facing the customer, as on cafe_counter and
  pharmacy_counter.
- fashion_rail: a chrome rail on two uprights over a low plinth of folded tees. Shirts
  and dresses hang side-on along the middle of the rail, and one garment at each end
  hangs face-out on an arm reaching forward, so the rail reads as clothes from the
  front as well as from the side. A small pink card stands on the rail. Mount_Browse_0
  and _1 as on the shelf.
- fashion_till: the counter section in white with a pink band and a dark top, the till on
  -x; on +x two stacks of folded clothes, a pink shopping bag and a dark sign with a
  hanger mark at the back. Mount_Order and Mount_Staff as on duty_free_till.

The pieces use build_interior_kit.py's helpers and checks (origin at the footprint centre
on the floor, front Godot +Z, every face on a measured atlas swatch, the written file
re-read). register() adds the swatches, pieces and required nodes to the kit's tables;
check_written() then re-reads each written file for its mounts and per-side extents.
It never calls another kit's register() and adds nothing to kit.NODE_TRANSLATIONS.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402  (helpers only; act.register() is never called)
import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_carry_on_kit as carry  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_kiosk_kit as kiosk  # noqa: E402  (helpers only; kiosk.register() is never called)
import build_security_kit as sec  # noqa: E402
import build_services_kit as svc  # noqa: E402
import build_toilet_kit as toilet  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "retail-kit", "retail_kit.blend")

INSET = 0.08
HALF_IN = 0.5 - INSET  # 0.42
WIDE_IN = 1.0 - INSET  # 0.92, the x limit of a 2x1 piece

# Swatches from the activities kit's measured cells (the same atlas cells).
RETAIL_PALETTE = {k: act.ACTIVITIES_PALETTE[k] for k in
                  ("red", "pink", "cream", "gold", "sun", "kid_blue", "kid_green", "orange", "purple", "teal")}

ORDER = ("order", (-0.5, 0.0, 1.0), 180.0)
STAFF = ("staff", (-0.5, 0.0, -1.0), 0.0)
BROWSE = {
    "Mount_Browse_0": ("browse", (-0.5, 0.0, 1.0), 180.0),
    "Mount_Browse_1": ("browse", (0.5, 0.0, 1.0), 180.0),
}
SIDES_2X1 = {"+x": WIDE_IN, "-x": WIDE_IN, "+z": HALF_IN, "-z": HALF_IN}

# piece -> footprint (cells x by z), mounts {name: (kind, Godot position, yaw in
# degrees)}, and the per-side limits of the written mesh. Yaw 0 faces Godot +Z.
RETAIL = {
    "duty_free_shelf": {"footprint": (2, 1), "mounts": dict(BROWSE), "sides": SIDES_2X1},
    "duty_free_till": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
                       "sides": SIDES_2X1},
    "fashion_rail": {"footprint": (2, 1), "mounts": dict(BROWSE), "sides": SIDES_2X1},
    "fashion_till": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
                     "sides": SIDES_2X1},
}

gbox = kiosk.gbox  # a box over Godot ranges, optionally leaned back about a Godot pivot


# ---------------------------------------------------------------- geometry
# Blender frame: x = Godot x, -y = Godot +Z (the front), z = up.


def gcyl(name, gx, gz, y0, y1, r, pal, parent, c, segs=8):
    """An upright cylinder at Godot (gx, gz) from height y0 to y1."""
    return kit.cyl(name, gx, -gz, y0, y1, r, pal, parent, c, segs=segs)


def prism_xz(name, pts, gz0, gz1, pal, parent, c):
    """A convex prism facing Godot +Z: the outline `pts` (Godot x, height) extruded
    between Godot depths gz0 and gz1."""
    bm = bmesh.new()
    a = [bm.verts.new((x, -gz1, y)) for x, y in pts]
    b = [bm.verts.new((x, -gz0, y)) for x, y in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def prism_side(name, pts, x0, x1, pal, parent, c):
    """A convex prism seen side-on: the outline `pts` (Godot z, height) extruded from
    Godot x0 to x1."""
    return svc.prism_yz(name, [(-z, y) for z, y in pts], x0, x1, pal, parent, c)


def garment_outline(cx, top, bottom, half, hem_half, shoulder=0.08, drop=0.07):
    """A shirt or dress silhouette (convex): a neck `shoulder` wide each side of cx,
    shoulders sloping `drop` down to `half`, and the hem `hem_half` wide."""
    return [(cx - shoulder, top), (cx + shoulder, top), (cx + half, top - drop),
            (cx + hem_half, bottom), (cx - hem_half, bottom), (cx - half, top - drop)]


def add_mounts(piece, root, c):
    for name, (_kind, (gx, gy, gz), yaw) in RETAIL[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


def sign_on_post(prefix, board_pal, root, c, x0=0.50, x1=0.90, y0=1.50, y1=1.86, post_x=0.70):
    """A sign board on one post at the back of the +x half (Godot z -0.40..-0.36)."""
    gbox(prefix + "_Post", (post_x - 0.02, post_x + 0.02), (1.00, y0 + 0.02), (-0.40, -0.36), "frame", root, c)
    gbox(prefix + "_Board", (x0, x1), (y0, y1), (-0.40, -0.36), board_pal, root, c, bevel=0.01)


# ---------------------------------------------------------------- duty free

SHELF_LEVELS = (0.10, 0.52, 0.94, 1.36)
SHELF_TOP = 1.78


def shelf_front(y):
    """Godot z of the shelf sides' front edge at height y: +0.34 up to 0.40 m, then
    sloping back to -0.10 at the top."""
    if y <= 0.40:
        return 0.34
    return 0.34 - (y - 0.40) / (SHELF_TOP - 0.40) * 0.44


BOTTLES = ("orange", "kid_green", "white", "dark", "teal", "gold")


def bottle(name, gx, gz, y, pal, cap, root, c, h=0.22, r=0.04):
    gcyl(name + "_Body", gx, gz, y, y + h, r, pal, root, c, segs=6)
    gcyl(name + "_Neck", gx, gz, y + h, y + h + 0.07, r * 0.4, pal, root, c, segs=4)
    gcyl(name + "_Cap", gx, gz, y + h + 0.07, y + h + 0.095, r * 0.45, cap, root, c, segs=4)


def half_xs(step, n):
    """n x centres per half, from the divider outward, mirrored to both halves."""
    xs = [0.09 + i * step for i in range(n)]
    return sorted([-x for x in xs] + xs)


def build_duty_free_shelf(root, c):
    gbox("Shelf_Plinth", (-0.88, 0.88), (0.0, SHELF_LEVELS[0]), (-0.36, 0.30), "dark", root, c)
    gbox("Shelf_Back", (-0.92, 0.92), (0.0, SHELF_TOP), (-0.42, -0.36), "cream", root, c)
    side = [(-0.42, 0.0), (0.34, 0.0), (0.34, 0.40), (-0.10, SHELF_TOP), (-0.42, SHELF_TOP)]
    prism_side("Shelf_Side_L", side, -0.92, -0.88, "purple", root, c)
    prism_side("Shelf_Side_R", side, 0.88, 0.92, "purple", root, c)
    for k, y in enumerate(SHELF_LEVELS[1:], start=1):
        zf = shelf_front(y) - 0.02
        gbox("Shelf_Board_%d" % k, (-0.88, 0.88), (y - 0.03, y), (-0.36, zf), "white", root, c)
        gbox("Shelf_Lip_%d" % k, (-0.88, 0.88), (y - 0.05, y), (zf, zf + 0.012), "gold", root, c)
    gbox("Shelf_Lip_0", (-0.88, 0.88), (0.05, SHELF_LEVELS[0]), (0.30, 0.312), "gold", root, c)
    gbox("Shelf_Divider", (-0.01, 0.01), (SHELF_LEVELS[0], SHELF_TOP), (-0.36, -0.18), "purple", root, c)
    # Plinth: tall gift boxes in two rows.
    gift = ("purple", "red", "gold", "kid_blue", "dark", "teal")
    n = 0
    for row, zc in enumerate((-0.22, 0.16)):
        for i, x in enumerate(half_xs(0.13, 6)):
            h = (0.26, 0.20, 0.30, 0.22)[(i + row) % 4]
            gbox("Gift_%d" % n, (x - 0.05, x + 0.05), (SHELF_LEVELS[0], SHELF_LEVELS[0] + h), (zc - 0.06, zc + 0.06),
                 gift[(i + 2 * row) % 6], root, c)
            n += 1
    # Shelves 1 and 2: two rows of bottles each, a cap colour per row.
    rows = {1: (-0.22, 0.14), 2: (-0.24, 0.06)}
    n = 0
    for k, zs in rows.items():
        for row, zc in enumerate(zs):
            for i, x in enumerate(half_xs(0.12, 7)):
                h = (0.22, 0.18, 0.24, 0.20)[(i + row + k) % 4]
                bottle("Bottle_%d" % n, x, zc, SHELF_LEVELS[k], BOTTLES[(i + 2 * row + 3 * k) % 6],
                       ("gold", "red")[row], root, c, h=h)
                n += 1
    # Shelf 3: perfume boxes at the back, small perfume bottles in front.
    perfume = ("pink", "purple", "gold", "white", "sun", "kid_blue")
    y = SHELF_LEVELS[3]
    for i, x in enumerate(half_xs(0.12, 7)):
        h = (0.14, 0.11, 0.16, 0.12)[i % 4]
        gbox("Perfume_Box_%d" % i, (x - 0.04, x + 0.04), (y, y + h), (-0.29, -0.19), perfume[i % 6], root, c)
        gbox("Perfume_Bottle_%d" % i, (x - 0.025, x + 0.025), (y, y + 0.08), (-0.09, -0.05), perfume[(i + 3) % 6],
             root, c)
        gcyl("Perfume_Cap_%d" % i, x, -0.07, y + 0.08, y + 0.11, 0.012, "gold", root, c, segs=6)
    # Header: purple board with a gold strip and white marks.
    gbox("Header_Board", (-0.92, 0.92), (SHELF_TOP, 1.98), (-0.42, -0.28), "purple", root, c, bevel=0.01)
    gbox("Header_Strip", (-0.90, 0.90), (SHELF_TOP + 0.02, SHELF_TOP + 0.045), (-0.28, -0.275), "gold", root, c)
    for i, x in enumerate((-0.60, -0.36, -0.12, 0.12, 0.36)):
        gbox("Header_Mark_%d" % i, (x, x + 0.18), (1.85, 1.93), (-0.28, -0.275), "white", root, c)
    gbox("Header_Mark_Tag", (0.62, 0.80), (1.84, 1.94), (-0.28, -0.275), "gold", root, c)
    add_mounts("duty_free_shelf", root, c)


def choc_bar(name, x0, x1, zc, y, pal, root, c, base=0.065, h=0.06):
    prism_side(name, [(zc - base / 2, y), (zc + base / 2, y), (zc, y + h)], x0, x1, pal, root, c)


def build_duty_free_till(root, c):
    svc.counter("Till_Counter", -0.90, 0.90, 1.00, "cream", "purple", "wood", root, c)
    svc.till("Till", -0.5, root, c)
    # A tray of triangular chocolate bars at the front of the +x cell.
    gbox("Choc_Tray", (0.08, 0.56), (1.00, 1.02), (0.02, 0.38), "dark", root, c)
    for i in range(5):
        zc = 0.07 + i * 0.065
        choc_bar("Choc_Bar_%d" % i, 0.11, 0.53, zc, 1.02, ("gold", "sun")[i % 2], root, c)
        gbox("Choc_Band_%d" % i, (0.28, 0.36), (1.02, 1.06), (zc - 0.02, zc + 0.02), "red", root, c)
    # A stepped perfume tester stand with three bottles per step.
    gbox("Tester_Step_0", (0.60, 0.88), (1.00, 1.06), (-0.10, 0.30), "white", root, c, bevel=0.006)
    gbox("Tester_Step_1", (0.60, 0.88), (1.06, 1.14), (-0.10, 0.10), "purple", root, c, bevel=0.006)
    pals = ("pink", "kid_blue", "gold", "purple", "teal", "pink")
    for k, (y, zc) in enumerate(((1.06, 0.20), (1.14, 0.00))):
        for i, x in enumerate((0.65, 0.74, 0.83)):
            gbox("Tester_%d%d" % (k, i), (x - 0.025, x + 0.025), (y, y + 0.08), (zc - 0.02, zc + 0.02),
                 pals[i + 3 * k], root, c)
            gcyl("Tester_Cap_%d%d" % (k, i), x, zc, y + 0.08, y + 0.105, 0.012, "gold", root, c, segs=6)
    sign_on_post("Sign", "purple", root, c)
    gbox("Sign_Strip", (0.52, 0.88), (1.53, 1.56), (-0.36, -0.355), "gold", root, c)
    for i, x in enumerate((0.56, 0.68)):
        gbox("Sign_Mark_%d" % i, (x, x + 0.10), (1.64, 1.76), (-0.36, -0.355), "white", root, c)
    gbox("Sign_Mark_Tag", (0.80, 0.86), (1.64, 1.76), (-0.36, -0.355), "gold", root, c)
    add_mounts("duty_free_till", root, c)


# ---------------------------------------------------------------- fashion

RAIL_Y = 1.55
RAIL_Z = -0.10
GARMENTS = ("kid_blue", "pink", "white", "dark", "sun", "teal", "red", "purple", "cream")


def build_fashion_rail(root, c):
    for side, x in (("L", -0.86), ("R", 0.86)):
        gbox("Rail_Foot_" + side, (x - 0.02, x + 0.02), (0.0, 0.04), (-0.38, 0.30), "dark", root, c, bevel=0.008)
        gcyl("Rail_Upright_" + side, x, RAIL_Z, 0.04, RAIL_Y + 0.05, 0.02, "metal", root, c, segs=8)
        cafe.ball("Rail_Knob_" + side, x, -RAIL_Z, RAIL_Y + 0.07, 0.03, "metal", root, c)
    gbox("Rail_Bar", (-0.88, 0.88), (RAIL_Y - 0.015, RAIL_Y + 0.015), (RAIL_Z - 0.015, RAIL_Z + 0.015), "metal",
         root, c, bevel=0.006)
    # Low plinth on the floor between the feet and the uprights, with folded tees.
    gbox("Rail_Plinth", (-0.84, 0.84), (0.0, 0.20), (-0.30, 0.22), "wood", root, c, bevel=0.01)
    tees = ("kid_blue", "white", "pink", "sun", "dark", "teal")
    for s, x in enumerate((-0.62, -0.30, 0.02, 0.34)):
        for k in range(3):
            y = 0.20 + k * 0.035
            gbox("Tee_%d%d" % (s, k), (x, x + 0.26), (y, y + 0.035), (-0.04, 0.16), tees[(s + k) % 6], root, c,
                 bevel=0.008)
    # Side-on garments along the middle of the rail: shirts, dresses and a long coat.
    kinds = ((0.78, 0.24), (0.50, 0.27), (0.78, 0.24), (0.62, 0.25))
    for i in range(9):
        x = -0.32 + i * 0.08
        bottom, hem = kinds[i % 4]
        out = garment_outline(RAIL_Z, RAIL_Y - 0.05, bottom, 0.24, hem)
        prism_side("Garment_%d" % i, out, x - 0.022, x + 0.022, GARMENTS[i], root, c)
        gbox("Hanger_%d" % i, (x - 0.006, x + 0.006), (RAIL_Y - 0.06, RAIL_Y - 0.04), (RAIL_Z - 0.20, RAIL_Z + 0.20),
             "wood", root, c)
        gbox("Hook_%d" % i, (x - 0.004, x + 0.004), (RAIL_Y - 0.04, RAIL_Y + 0.02), (RAIL_Z - 0.006, RAIL_Z + 0.006),
             "metal", root, c)
    # A face-out garment at each end on an arm reaching forward.
    for side, x, bottom, hem, pal in (("L", -0.62, 0.80, 0.20, "red"), ("R", 0.62, 0.56, 0.23, "teal")):
        gbox("Arm_" + side, (x - 0.01, x + 0.01), (RAIL_Y - 0.035, RAIL_Y - 0.01), (RAIL_Z, 0.28), "metal", root, c)
        gbox("Arm_Stop_" + side, (x - 0.012, x + 0.012), (RAIL_Y - 0.035, RAIL_Y + 0.01), (0.27, 0.285), "metal",
             root, c)
        prism_xz("FaceOut_" + side, garment_outline(x, RAIL_Y - 0.07, bottom, 0.20, hem, shoulder=0.07),
                 0.20, 0.24, pal, root, c)
        gbox("FaceOut_Hanger_" + side, (x - 0.17, x + 0.17), (RAIL_Y - 0.08, RAIL_Y - 0.06), (0.235, 0.25), "wood",
             root, c)
        # The hook from the hanger up over the arm.
        gbox("FaceOut_Hook_" + side, (x - 0.004, x + 0.004), (RAIL_Y - 0.06, RAIL_Y - 0.002), (0.236, 0.248), "metal",
             root, c)
    # A small pink card standing on the rail.
    gbox("Card_Stem", (-0.01, 0.01), (RAIL_Y + 0.015, RAIL_Y + 0.07), (RAIL_Z - 0.01, RAIL_Z + 0.01), "metal", root, c)
    gbox("Card_Board", (-0.16, 0.16), (RAIL_Y + 0.07, RAIL_Y + 0.21), (RAIL_Z - 0.015, RAIL_Z + 0.015), "pink", root,
         c, bevel=0.006)
    gbox("Card_Mark", (-0.11, 0.11), (RAIL_Y + 0.11, RAIL_Y + 0.17), (RAIL_Z + 0.015, RAIL_Z + 0.02), "white", root, c)
    add_mounts("fashion_rail", root, c)


def build_fashion_till(root, c):
    svc.counter("Till_Counter", -0.90, 0.90, 1.00, "white", "pink", "dark", root, c)
    svc.till("Till", -0.5, root, c)
    # Two stacks of folded clothes at the front of the +x cell.
    folds = ("kid_blue", "white", "pink", "sun", "teal", "dark", "red", "cream")
    for s, x in enumerate((0.10, 0.40)):
        for k in range(4):
            y = 1.00 + k * 0.035
            gbox("Fold_%d%d" % (s, k), (x, x + 0.26), (y, y + 0.035), (0.12, 0.34), folds[(s * 4 + k) % 8], root, c,
                 bevel=0.006)
    # A shopping bag with a white handle.
    gbox("Bag_Body", (0.72, 0.88), (1.00, 1.22), (0.04, 0.14), "pink", root, c, bevel=0.006)
    gbox("Bag_Fold", (0.72, 0.88), (1.22, 1.24), (0.04, 0.14), "white", root, c)
    for i, x in enumerate((0.76, 0.84)):
        gbox("Bag_Handle_%d" % i, (x - 0.006, x + 0.006), (1.24, 1.32), (0.085, 0.095), "white", root, c)
    gbox("Bag_Handle_Top", (0.754, 0.846), (1.32, 1.332), (0.085, 0.095), "white", root, c)
    # The sign at the back of +x: a dark board with a hanger mark.
    sign_on_post("Sign", "dark", root, c)
    gbox("Sign_Strip", (0.52, 0.88), (1.53, 1.56), (-0.36, -0.355), "pink", root, c)
    yb, cx = 1.62, 0.70
    gbox("Sign_Hanger_Bar", (cx - 0.13, cx + 0.13), (yb, yb + 0.018), (-0.36, -0.355), "white", root, c)
    for i, s in enumerate((-1.0, 1.0)):
        # The hanger's sloped arms: boxes turned about Godot Z (Blender Y) on the board.
        mx = cx + s * 0.065
        cafe.tbox("Sign_Hanger_Arm_%d" % i, (mx - 0.075, 0.355, yb + 0.045), (mx + 0.075, 0.36, yb + 0.063), "white",
                  root, c, axis="Y", deg=s * 33.0, pivot=(mx, 0.3575, yb + 0.054))
    gbox("Sign_Hanger_Neck", (cx - 0.008, cx + 0.008), (yb + 0.09, yb + 0.13), (-0.36, -0.355), "white", root, c)
    gbox("Sign_Hanger_Hook", (cx, cx + 0.04), (yb + 0.13, yb + 0.146), (-0.36, -0.355), "white", root, c)
    add_mounts("fashion_till", root, c)


# ---------------------------------------------------------------- register + checks

# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {
    "duty_free_shelf": (build_duty_free_shelf, (2, 1), (-WIDE_IN, -0.34, 0.0), (WIDE_IN, 0.42, 1.98)),
    "duty_free_till": (build_duty_free_till, (2, 1), (-WIDE_IN, -0.42, 0.0), (WIDE_IN, 0.42, 1.86)),
    "fashion_rail": (build_fashion_rail, (2, 1), (-0.889, -0.30, 0.0), (0.889, 0.38, 1.76)),
    "fashion_till": (build_fashion_till, (2, 1), (-WIDE_IN, -0.42, 0.0), (WIDE_IN, 0.42, 1.86)),
}
EXTRA_NODES = {p: sorted(RETAIL[p]["mounts"]) for p in RETAIL}


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside this kit, a name another kit owns, a
    node name already in kit.NODE_TRANSLATIONS, or an existing destination .glb that
    is not this builder's piece."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the retail kit: %s" % bad)
    others = (set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES) | set(bag.PIECES)
              | set(sec.PIECES) | set(carry.PIECES) | set(toilet.PIECES) | set(kiosk.PIECES))
    taken = sorted(others & set(PIECES))
    if taken:
        kit.fail("retail names already owned by another kit: %s" % taken)
    clash = sorted(set(kit.NODE_TRANSLATIONS) & {n for v in EXTRA_NODES.values() for n in v})
    if clash:
        kit.fail("node names already in kit.NODE_TRANSLATIONS: %s" % clash)
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
    """Add the retail swatches, pieces and required nodes to the kit."""
    kit.PALETTE.update(RETAIL_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_mounts(piece, js):
    """Every mount a unit-scale, upright child of the root at its position and facing."""
    nodes = js.get("nodes", [])
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
    root = nodes[by_name[kit.piece_title(piece) + "_ROOT"]]
    mounts = RETAIL[piece]["mounts"]
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
        q = svc.node_quat(node)
        facing = q @ Vector((0.0, 0.0, 1.0))
        up = q @ Vector((0.0, 1.0, 0.0))
        want = Vector((math.sin(math.radians(yaw)), 0.0, math.cos(math.radians(yaw))))
        kit.log("MOUNT %s %s kind=%s child_of_root=%s pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f) "
                "want_facing=(%.3f, %.3f, %.3f)"
                % (piece, name, kind, child, t[0], t[1], t[2], facing.x, facing.y, facing.z, want.x, want.y, want.z))
        if not child or max(abs(s - 1.0) for s in scale) > 1e-6:
            kit.fail("%s: mount %s is not a unit-scale child of the root" % (piece, name))
        if max(abs(a - b) for a, b in zip(t, pos)) > 1e-4:
            kit.fail("%s: mount %s at %s, expected %s" % (piece, name, t, pos))
        if (facing - want).length > 1e-3 or (up - Vector((0.0, 1.0, 0.0))).length > 1e-3:
            kit.fail("%s: mount %s faces %s up %s, expected %s up +Y" % (piece, name, facing, up, want))


def check_sides(piece, objs):
    """The written mesh per side against its limit, and nothing below the floor."""
    pts = bag.godot_points([o for o in objs if o.type == "MESH"])
    ext = {"+x": max(p.x for p in pts), "-x": -min(p.x for p in pts),
           "+z": max(p.z for p in pts), "-z": -min(p.z for p in pts)}
    limits = RETAIL[piece]["sides"]
    parts = []
    for side in ("+x", "-x", "+z", "-z"):
        parts.append("%s=%.4f/%.3f" % (side, ext[side], limits[side]))
        if ext[side] > limits[side] + 1e-4:
            kit.fail("%s: written mesh reaches %.4f on %s, limit %.3f" % (piece, ext[side], side, limits[side]))
    min_y = min(p.y for p in pts)
    kit.log("SIDES %s %s min_y=%.4f max_y=%.4f" % (piece, " ".join(parts), min_y, max(p.y for p in pts)))
    if min_y < -1e-4:
        kit.fail("%s: mesh below the floor (%.4f)" % (piece, min_y))


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        check_mounts(piece, js)
        objs = toilet.import_written(out)
        check_sides(piece, objs)
    data = {p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in RETAIL.items()}
    kit.log("RETAIL_DATA " + json.dumps(data))
    kit.log("RETAIL done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
