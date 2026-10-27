"""Build the food, drink and services pieces of the interior kit, one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_services_kit.py' [-- piece ...]

Pieces (decision food-and-drink-cafe-bar-sit-down-restaurant-and-grab-and-go): a bar
counter with two stools, a restaurant table and a restaurant booth (four seats each),
a grab-and-go stall, an info desk, a currency exchange booth, an ATM, a pharmacy
counter and shelf, a shower cubicle and a nap pod. The cafe counter and cafe table are
build_cafe_kit.py's and are not built here.

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, furniture 0.08 m inside its footprint,
every face on a measured Toon atlas swatch, the written file re-read and checked), the
way build_activities_kit.py does. register() adds the swatches, pieces and required
nodes to the kit's tables; the kit's main() builds, exports and verifies them; then
check_written() re-reads each written file: its Mount_* nodes, its mesh bounds against
the footprint inset, and the shower door's hinge. It never calls the cafe or
activities register() and never adds to kit.NODE_TRANSLATIONS.

Before anything is built, guard() refuses a piece outside SERVICES, a SERVICES name
another kit owns, and an existing destination .glb that is not this builder's piece.

Mounts are Mount_* empties in the piece's own frame (Godot axes, metres), unit scale,
upright, +Z the way the passenger faces. Kinds: "sit_root" (where a seated passenger's
ROOT goes, feet on the floor), "order" (a customer standing at the counter), "staff"
(the server behind it), "use" (a passenger using a machine or cubicle), "browse" (a
passenger at a shelf). A seated root is the seat cell's centre plus SIT_FORWARD toward
the cell the passenger faces (passenger_sim SIT_FORWARD_M); the seated-fit check holds
the root fixed, so the shuffle from the faced cell is not checked here.

Seats are shaped from the measured sit clips (both characters, every frame of sit_down,
sit_idle and stand_up): the body reaches up to 0.26 m in front of the root at 0.6-0.7 m
height and 0.24 m at 1.0-1.3 m, heels and calves reach 0.245 m behind it down to the
floor, the seated back reaches 0.59-0.73 m behind it, the elbows 0.314 m to the side,
and the female thigh sits at 0.509-0.52 m between 0.25 and 0.35 m behind it.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402  (helpers only; act.register() is never called)
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_interior_kit as kit  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "furniture-3b", "services_kit.blend")

SEAT_TOP = cafe.SEAT_TOP
SIT_FORWARD = 0.45
INSET = 0.08

# Swatches copied from the cafe and activities kits (the same measured cells).
SERVICES_PALETTE = {k: act.ACTIVITIES_PALETTE[k] for k in
                    ("red", "pink", "cream", "gold", "sun", "kid_blue", "kid_green", "orange", "purple", "teal")}
SERVICES_PALETTE.update({k: cafe.CAFE_PALETTE[k] for k in ("coffee", "sage")})

ORDER = ("order", (-0.5, 0.0, 1.0), 180.0)
STAFF = ("staff", (-0.5, 0.0, -1.0), 0.0)
TABLE_ROOT_Z = 1.0 - SIT_FORWARD  # seat row z = +-1, faces the table row
BAR_ROOT_Z = 0.5 - SIT_FORWARD  # stool row z = +0.5, faces the counter row
POD_ROOT_Z = 0.0 + SIT_FORWARD  # seat cell z = 0, faces +Z


def four_seats():
    return {
        "Mount_SitRoot_FL": ("sit_root", (-0.5, 0.0, TABLE_ROOT_Z), 180.0),
        "Mount_SitRoot_FR": ("sit_root", (0.5, 0.0, TABLE_ROOT_Z), 180.0),
        "Mount_SitRoot_BL": ("sit_root", (-0.5, 0.0, -TABLE_ROOT_Z), 0.0),
        "Mount_SitRoot_BR": ("sit_root", (0.5, 0.0, -TABLE_ROOT_Z), 0.0),
    }


# piece -> footprint (cells x by z), mounts {name: (kind, Godot position, yaw in
# degrees)}. Yaw 0 faces Godot +Z.
SERVICES = {
    "bar_counter": {
        # Counter in the back row, stools in the front row facing it; the server
        # stands in the cell behind the counter, as at cafe_counter.
        "footprint": (2, 2),
        "mounts": {
            "Mount_SitRoot_L": ("sit_root", (-0.5, 0.0, BAR_ROOT_Z), 180.0),
            "Mount_SitRoot_R": ("sit_root", (0.5, 0.0, BAR_ROOT_Z), 180.0),
            "Mount_Staff": ("staff", (-0.5, 0.0, -1.5), 0.0),
        },
    },
    "restaurant_table": {"footprint": (2, 3), "mounts": four_seats()},
    "restaurant_booth": {"footprint": (2, 3), "mounts": four_seats()},
    "grab_and_go_stall": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF}},
    "info_desk": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF}},
    "currency_exchange": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF}},
    "atm": {"footprint": (1, 1), "mounts": {"Mount_Use": ("use", (0.0, 0.0, 1.0), 180.0)}},
    "pharmacy_counter": {"footprint": (2, 1), "mounts": {"Mount_Order": ORDER, "Mount_Staff": STAFF}},
    "pharmacy_shelf": {"footprint": (2, 1), "mounts": {"Mount_Browse": ("browse", (-0.5, 0.0, 1.0), 180.0)}},
    "shower_cubicle": {"footprint": (1, 1), "mounts": {"Mount_Use": ("use", (0.0, 0.0, 1.0), 180.0)}},
    "nap_pod": {"footprint": (1, 1), "mounts": {"Mount_SitRoot": ("sit_root", (0.0, 0.0, POD_ROOT_Z), 0.0)}},
}

# The shower door: a hinge empty (Godot position), leaf width, and the turn about
# Godot +Y that opens it outward (the free edge swings to +Z).
DOOR_HINGE = (-0.365, 0.0, 0.37)
DOOR_W = 0.73
DOOR_OPEN_DEG = -90.0


# ---------------------------------------------------------------- geometry
# Blender frame: x = Godot x, -y = Godot +Z (the front), z = up.


def tbox(*a, **k):
    return cafe.tbox(*a, **k)


def cyl(name, x, y, z0, z1, r, pal, parent, c, segs=8):
    return kit.cyl(name, x, y, z0, z1, r, pal, parent, c, segs=segs)


def cyl_y(name, x, z, y0, y1, r, pal, parent, c, segs=12):
    """A cylinder along Blender y (Godot z), from y0 to y1, axis at (x, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=abs(y1 - y0))
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(90.0), 4, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((x, (y0 + y1) / 2.0, z)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def prism_yz(name, pts, x0, x1, pal, parent, c):
    """A convex prism: the 2D outline `pts` (Blender y, z) extruded from x0 to x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in pts]
    b = [bm.verts.new((x1, y, z)) for y, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def seat_y(rz, s, b):
    """Blender y of a point b metres behind a seated root at Godot z = rz. s = +1 when
    the seat faces Godot -Z (behind is Godot +Z), -1 when it faces Godot +Z."""
    return -(rz + s * b)


def yr(rz, s, b0, b1):
    return tuple(sorted((seat_y(rz, s, b0), seat_y(rz, s, b1))))


def sbox(name, x0, x1, rz, s, b0, b1, z0, z1, pal, root, c, bevel=0.0, lean=0.0, pivot_b=None, pivot_z=None):
    """A box given in seat terms: x range, b range behind the root, height range;
    `lean` degrees tilts its top back (away from the faced cell) about (pivot_b, pivot_z)."""
    y0, y1 = yr(rz, s, b0, b1)
    pivot = None
    if lean:
        pivot = ((x0 + x1) / 2.0, seat_y(rz, s, pivot_b), pivot_z)
    return tbox(name, (x0, y0, z0), (x1, y1, z1), pal, root, c, axis="X", deg=s * lean, pivot=pivot, bevel=bevel)


def add_mounts(piece, root, c):
    for name, (_kind, (gx, gy, gz), yaw) in SERVICES[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


def counter(prefix, x0, x1, top, body, band, top_pal, root, c):
    """A standing counter across x0..x1 (cafe_counter's section): toe kick, body,
    customer band, top. The customer side is Blender -y (Godot +Z)."""
    tbox(prefix + "_ToeKick", (x0 + 0.02, -0.34, 0.0), (x1 - 0.02, 0.38, 0.08), "dark", root, c)
    tbox(prefix + "_Body", (x0, -0.38, 0.08), (x1, 0.40, top - 0.06), body, root, c)
    tbox(prefix + "_Band", (x0 + 0.04, -0.395, top - 0.38), (x1 - 0.04, -0.38, top - 0.24), band, root, c)
    tbox(prefix + "_Top", (x0 - 0.02, -0.42, top - 0.06), (x1 + 0.02, 0.42, top), top_pal, root, c, bevel=0.015)


def till(prefix, x, root, c, top=1.0):
    tbox(prefix + "_Base", (x - 0.13, -0.34, top), (x + 0.13, -0.14, top + 0.05), "dark", root, c, bevel=0.008)
    pivot = (x, -0.185, top + 0.05)
    tbox(prefix + "_Screen", (x - 0.10, -0.20, top + 0.05), (x + 0.10, -0.17, top + 0.22), "dark", root, c,
         deg=15.0, pivot=pivot)
    tbox(prefix + "_Screen_Lit", (x - 0.08, -0.17, top + 0.07), (x + 0.08, -0.165, top + 0.20), "screen_sky",
         root, c, deg=15.0, pivot=pivot)


def staff_monitor(prefix, x, root, c, top=1.0):
    tbox(prefix + "_Neck", (x - 0.03, 0.26, top), (x + 0.03, 0.30, top + 0.12), "dark", root, c)
    tbox(prefix + "_Monitor", (x - 0.20, 0.28, top + 0.10), (x + 0.20, 0.32, top + 0.36), "dark", root, c, bevel=0.01)
    tbox(prefix + "_Monitor_Lit", (x - 0.17, 0.32, top + 0.13), (x + 0.17, 0.33, top + 0.33), "screen_sky", root, c)


# ---------------------------------------------------------------- seats


def stool(side, x, rz, root, c):
    """A backless bar stool facing Godot -Z from a root at Godot z = rz. The 0.14 m
    cushion runs 0.22-0.62 m behind the root with a 0.06 m chamfered nose (the female
    thigh sits at 0.509-0.52 m 0.25-0.35 m behind the root); everything below the seat
    stays 0.27 m or more behind the root, where the heels reach 0.245 m."""
    s = 1.0
    sbox("Stool_Seat_" + side, x - 0.20, x + 0.20, rz, s, 0.22, 0.62, SEAT_TOP - 0.14, SEAT_TOP, "red", root, c,
         bevel=0.06)
    sbox("Stool_Pan_" + side, x - 0.17, x + 0.17, rz, s, 0.27, 0.57, SEAT_TOP - 0.17, SEAT_TOP - 0.14, "dark",
         root, c)
    py = seat_y(rz, s, 0.42)
    cyl("Stool_Post_" + side, x, py, 0.03, SEAT_TOP - 0.17, 0.035, "metal", root, c)
    cyl("Stool_Base_" + side, x, py, 0.0, 0.03, 0.15, "metal", root, c, segs=12)
    # A square foot rest on a crossbar through the post.
    for k, (b0, b1) in enumerate(((0.29, 0.31), (0.53, 0.55))):
        sbox("Stool_FootBar_%s%d" % (side, k), x - 0.15, x + 0.15, rz, s, b0, b1, 0.20, 0.23, "metal", root, c)
    for k, (x0, x1) in enumerate(((x - 0.15, x - 0.13), (x + 0.13, x + 0.15))):
        sbox("Stool_FootSide_%s%d" % (side, k), x0, x1, rz, s, 0.29, 0.55, 0.20, 0.23, "metal", root, c)
    sbox("Stool_FootCross_" + side, x - 0.15, x + 0.15, rz, s, 0.405, 0.435, 0.20, 0.23, "metal", root, c)


def chair(side, x, rz, s, seat, back, root, c):
    """work_desk's chair (build_activities_kit.build_work_desk) in seat terms: a 0.14 m
    cushion with a 0.06 m chamfered nose on a rigid pan that stops 0.30 m behind the
    root, legs, and a back at 0.64-0.68 m tilted 10 degrees. The cushion nose starts
    0.22 m behind the root, not work_desk's 0.20: at 0.20 the female dress hem crossed
    the nose 0.0288 m deep (limit 0.03); at 0.22, as on the sofa and stool, 0.0207."""
    b0, b1, tilt = 0.64, 0.68, 10.0
    pan_top = SEAT_TOP - 0.14
    sbox("Chair_Pan_" + side, x - 0.21, x + 0.21, rz, s, 0.30, b1, pan_top - 0.03, pan_top, "dark", root, c)
    sbox("Chair_Seat_" + side, x - 0.20, x + 0.20, rz, s, 0.22, b1 - 0.01, pan_top, SEAT_TOP, seat, root, c,
         bevel=0.06)
    for k, (lx, lb) in enumerate(((-0.17, 0.33), (0.17, 0.33), (-0.17, b0), (0.17, b0))):
        sbox("Chair_Leg_%s%d" % (side, k), x + lx - 0.015, x + lx + 0.015, rz, s, lb - 0.015, lb + 0.015,
             0.0, pan_top - 0.03, "dark", root, c)
    pb = (b0 + b1) / 2.0
    for k, lx in enumerate((-0.17, 0.17)):
        sbox("Chair_BackPost_%s%d" % (side, k), x + lx - 0.015, x + lx + 0.015, rz, s, b0, b1, pan_top, 0.90,
             "dark", root, c, lean=tilt, pivot_b=pb, pivot_z=SEAT_TOP)
    sbox("Chair_Back_" + side, x - 0.20, x + 0.20, rz, s, b0, b1, 0.72, 0.92, back, root, c, bevel=0.01,
         lean=tilt, pivot_b=pb, pivot_z=SEAT_TOP)


def bench(row, rz, s, root, c):
    """A booth bench across x -0.92..0.92 in seat terms: lounge_sofa's section (base set
    back to 0.27 m behind the roots, cushions 0.22-0.65 m behind with a 0.06 m nose,
    back cushions tilted 8 degrees) with a high back panel and high end panels."""
    sbox("Booth_Plinth_" + row, -0.84, 0.84, rz, s, 0.29, 0.85, 0.0, 0.10, "dark", root, c)
    sbox("Booth_Base_" + row, -0.86, 0.86, rz, s, 0.27, 0.87, 0.10, 0.38, "wood", root, c, bevel=0.02)
    for i, (x0, x1) in enumerate(((-0.85, -0.01), (0.01, 0.85))):
        sbox("Booth_Seat_%s%d" % (row, i), x0, x1, rz, s, 0.22, 0.65, 0.38, SEAT_TOP, "teal", root, c, bevel=0.06)
        sbox("Booth_BackCushion_%s%d" % (row, i), x0 + 0.02, x1 - 0.02, rz, s, 0.63, 0.75, SEAT_TOP, 1.05, "teal",
             root, c, bevel=0.035, lean=8.0, pivot_b=0.69, pivot_z=SEAT_TOP)
    sbox("Booth_Back_" + row, -0.86, 0.86, rz, s, 0.76, 0.87, 0.10, 1.15, "wood", root, c, bevel=0.02)
    outline = [(seat_y(rz, s, b), z) for b, z in ((0.15, 0.10), (0.87, 0.10), (0.87, 1.15), (0.50, 1.15),
                                                   (0.15, 0.66))]
    for side, x0, x1 in (("L", -0.92, -0.86), ("R", 0.86, 0.92)):
        prism_yz("Booth_End_%s%s" % (row, side), outline, x0, x1, "wood", root, c)


def table_2x3(prefix, top_pal, root, c):
    """The restaurant table in the middle row: top 0.74-0.78 m, edges 0.22 m in front of
    the roots, one central pedestal well clear of the feet (toes reach 0.35 m forward)."""
    tbox(prefix + "_Top", (-0.84, -0.33, 0.74), (0.84, 0.33, 0.78), top_pal, root, c, bevel=0.01)
    tbox(prefix + "_Pedestal", (-0.06, -0.06, 0.03), (0.06, 0.06, 0.74), "dark", root, c)
    tbox(prefix + "_Foot", (-0.35, -0.12, 0.0), (0.35, 0.12, 0.03), "dark", root, c)
    # Place settings: plates 0.37 m and glasses 0.32 m in front of the roots (the body
    # reaches 0.20 m forward at table height).
    for i, (x, s) in enumerate(((-0.5, 1), (0.5, 1), (-0.5, -1), (0.5, -1))):
        cyl("%s_Plate_%d" % (prefix, i), x, s * 0.18, 0.78, 0.795, 0.09, "white", root, c, segs=12)
        cyl("%s_Glass_%d" % (prefix, i), x + 0.17, s * 0.20, 0.78, 0.89, 0.03, "glass", root, c)
    cyl(prefix + "_Vase", 0.0, 0.0, 0.78, 0.92, 0.04, "kid_blue", root, c)
    cafe.ball(prefix + "_Flower", 0.0, 0.0, 0.96, 0.05, "pink", root, c)
    cyl(prefix + "_Candle", 0.18, 0.0, 0.78, 0.86, 0.022, "cream", root, c)


# ---------------------------------------------------------------- pieces


def build_bar_counter(root, c):
    # Back row (Godot z -0.92..-0.20, Blender y 0.20..0.92): a guest ledge at 0.78 m
    # whose edge is 0.25 m in front of the roots, the counter body 0.47 m in front, and
    # a raised staff top at 1.05 m 0.45 m in front (the head reaches 0.24 m forward).
    tbox("Bar_ToeKick", (-0.88, 0.46, 0.0), (0.88, 0.90, 0.08), "dark", root, c)
    tbox("Bar_Body", (-0.90, 0.42, 0.08), (0.90, 0.92, 1.01), "coffee", root, c)
    tbox("Bar_Band", (-0.86, 0.415, 0.48), (0.86, 0.42, 0.56), "gold", root, c)
    tbox("Bar_Ledge", (-0.92, 0.20, 0.74), (0.92, 0.44, 0.78), "wood", root, c, bevel=0.01)
    for side, x0, x1 in (("L", -0.88, -0.84), ("R", 0.84, 0.88)):
        tbox("Bar_Bracket_" + side, (x0, 0.24, 0.60), (x1, 0.42, 0.74), "dark", root, c)
    tbox("Bar_Top", (-0.92, 0.40, 1.01), (0.92, 0.92, 1.05), "wood", root, c, bevel=0.012)
    # Beer taps on the staff half, handles toward the server.
    cyl("Tap_Tower", 0.0, 0.62, 1.05, 1.38, 0.04, "metal", root, c, segs=12)
    tbox("Tap_Bar", (-0.17, 0.58, 1.32), (0.17, 0.66, 1.40), "metal", root, c, bevel=0.01)
    for i, (x, pal) in enumerate(((-0.11, "red"), (0.0, "gold"), (0.11, "kid_green"))):
        tbox("Tap_Spout_%d" % i, (x - 0.012, 0.66, 1.28), (x + 0.012, 0.70, 1.32), "dark", root, c)
        tbox("Tap_Handle_%d" % i, (x - 0.02, 0.64, 1.40), (x + 0.02, 0.68, 1.54), pal, root, c, bevel=0.008)
    # A stepped bottle display along the back edge, facing the guests.
    tbox("Bottle_Step_Low", (-0.86, 0.78, 1.05), (0.86, 0.92, 1.13), "coffee", root, c)
    tbox("Bottle_Step_High", (-0.86, 0.85, 1.13), (0.86, 0.92, 1.23), "coffee", root, c)
    pals = ("kid_green", "gold", "red", "teal", "cream", "coffee", "orange")
    k = 0
    for row, (y, z0) in enumerate(((0.815, 1.13), (0.885, 1.23))):
        for i in range(9):
            x = -0.76 + i * 0.19 + (0.095 if row else 0.0)
            if x > 0.80:
                continue
            pal = pals[(i + 3 * row) % len(pals)]
            cyl("Bottle_%d" % k, x, y, z0, z0 + 0.20, 0.03, pal, root, c)
            cyl("Bottle_Neck_%d" % k, x, y, z0 + 0.20, z0 + 0.27, 0.012, pal, root, c)
            k += 1
    for i, x in enumerate((-0.68, 0.30)):
        cyl("Bar_Glass_%d" % i, x, 0.30, 0.78, 0.90, 0.032, "glass", root, c)
        cyl("Bar_Beer_%d" % i, x, 0.30, 0.78, 0.87, 0.027, "gold", root, c)
    for side, x in (("L", -0.5), ("R", 0.5)):
        stool(side, x, BAR_ROOT_Z, root, c)
    add_mounts("bar_counter", root, c)


def build_restaurant_table(root, c):
    table_2x3("Table", "wood", root, c)
    for row, s in (("F", 1.0), ("B", -1.0)):
        for side, x in (("L", -0.5), ("R", 0.5)):
            chair(row + side, x, s * TABLE_ROOT_Z, s, "red", "red", root, c)
    add_mounts("restaurant_table", root, c)


def build_restaurant_booth(root, c):
    table_2x3("Booth_Table", "wood", root, c)
    for row, s in (("F", 1.0), ("B", -1.0)):
        bench(row, s * TABLE_ROOT_Z, s, root, c)
    add_mounts("restaurant_booth", root, c)


def build_grab_and_go_stall(root, c):
    # -x cell: the till counter (the order cell) with a fruit basket.
    counter("Till", -0.90, -0.06, 1.00, "cream", "orange", "wood", root, c)
    till("Till", -0.58, root, c)
    cafe.cone("Basket", -0.24, -0.16, 1.00, 1.07, 0.09, 0.12, "wood", root, c)
    for i, (x, y, pal) in enumerate(((-0.28, -0.18, "red"), (-0.20, -0.20, "orange"), (-0.24, -0.11, "kid_green"),
                                     (-0.19, -0.12, "red"))):
        cafe.ball("Fruit_%d" % i, x, y, 1.10, 0.04, pal, root, c)
    # +x cell: an open-front chiller, the customer takes from it.
    tbox("Chiller_Toe", (0.06, -0.28, 0.0), (0.90, 0.40, 0.08), "dark", root, c)
    tbox("Chiller_Back", (0.04, 0.36, 0.08), (0.92, 0.42, 1.60), "white", root, c)
    for side, x0, x1 in (("L", 0.04, 0.08), ("R", 0.88, 0.92)):
        tbox("Chiller_Side_" + side, (x0, -0.30, 0.08), (x1, 0.42, 1.60), "white", root, c)
    tbox("Chiller_Deck", (0.08, -0.30, 0.08), (0.88, 0.36, 0.40), "white", root, c)
    tbox("Chiller_Kick", (0.08, -0.305, 0.12), (0.88, -0.30, 0.34), "kid_green", root, c)
    tbox("Chiller_Canopy", (0.04, -0.30, 1.50), (0.92, 0.42, 1.60), "kid_green", root, c)
    tbox("Chiller_Light", (0.08, -0.305, 1.52), (0.88, -0.30, 1.58), "text_white", root, c)
    for k, z in enumerate((0.70, 1.00, 1.28)):
        tbox("Chiller_Shelf_%d" % k, (0.08, -0.26, z - 0.02), (0.88, 0.36, z), "metal", root, c)
    drinks = ("red", "kid_green", "orange", "kid_blue", "red", "sun")
    for i in range(6):
        x = 0.16 + i * 0.135
        cyl("Drink_%d" % i, x, -0.12, 0.40, 0.60, 0.035, drinks[i], root, c)
        cyl("Drink_Cap_%d" % i, x, -0.12, 0.60, 0.63, 0.018, "white", root, c)
    for i in range(4):
        x = 0.20 + i * 0.19
        # A sandwich wedge: bread, filling, bread.
        tbox("Sandwich_Bread_%d" % i, (x - 0.07, -0.20, 0.70), (x + 0.07, -0.02, 0.73), "cream", root, c)
        tbox("Sandwich_Fill_%d" % i, (x - 0.07, -0.20, 0.73), (x + 0.07, -0.02, 0.75), "kid_green", root, c)
        tbox("Sandwich_Top_%d" % i, (x - 0.07, -0.20, 0.75), (x + 0.07, -0.02, 0.78), "cream", root, c)
        cyl("Salad_%d" % i, x, -0.10, 1.00, 1.07, 0.07, "kid_green", root, c, segs=12)
        cyl("Salad_Lid_%d" % i, x, -0.10, 1.07, 1.08, 0.072, "glass", root, c, segs=12)
        tbox("Snack_%d" % i, (x - 0.06, -0.16, 1.28), (x + 0.06, -0.04, 1.42), ("orange", "red", "sun", "purple")[i],
             root, c)
    # A striped awning on two back posts, sloping down to the front, with a header.
    for side, x0, x1 in (("L", -0.92, -0.88), ("R", 0.88, 0.92)):
        tbox("Awning_Post_" + side, (x0, 0.36, 0.0), (x1, 0.40, 2.25), "frame", root, c)
    for i in range(6):
        x0 = -0.92 + i * (1.84 / 6.0)
        tbox("Awning_Stripe_%d" % i, (x0, -0.42, 2.21), (x0 + 1.84 / 6.0, 0.40, 2.25), ("red", "cream")[i % 2],
             root, c, deg=12.0, pivot=(x0, 0.40, 2.23))
    face = cafe.group("Sign_Face", root, c)
    # The board's top runs up into the awning's underside (about 2.04 m at the front).
    tbox("Sign_Face_Board", (-0.80, -0.415, 1.84), (0.80, -0.38, 2.06), "dark", face, c)
    tbox("Sign_Face_Title", (-0.50, -0.42, 1.90), (0.50, -0.415, 1.96), "text_yellow", face, c)
    for i, x in enumerate((-0.66, 0.66)):
        tbox("Sign_Face_Dot_%d" % i, (x - 0.04, -0.42, 1.89), (x + 0.04, -0.415, 1.97), "text_white", face, c)
    add_mounts("grab_and_go_stall", root, c)


def build_info_desk(root, c):
    counter("Desk", -0.90, 0.90, 1.00, "white", "blue", "top", root, c)
    tbox("Desk_Stripe", (-0.86, -0.40, 0.84), (0.86, -0.38, 0.88), "yellow", root, c)
    staff_monitor("Desk", -0.5, root, c)
    tbox("Desk_Bell_Base", (-0.56, -0.30, 1.00), (-0.44, -0.20, 1.02), "dark", root, c)
    cafe.ball("Desk_Bell", -0.50, -0.25, 1.04, 0.035, "gold", root, c)
    # Leaflets in a rack on the customer face.
    tbox("Leaflet_Rack", (0.10, -0.42, 0.50), (0.70, -0.38, 0.54), "frame", root, c)
    for i, pal in enumerate(("pink", "sun", "kid_green", "kid_blue")):
        x = 0.16 + i * 0.14
        tbox("Leaflet_%d" % i, (x - 0.05, -0.415, 0.54), (x + 0.05, -0.39, 0.72), pal, root, c)
    # The 'i' totem: a post on the back corner and a lit sign above head height.
    cyl("Totem_Post", 0.78, 0.30, 1.00, 1.64, 0.03, "frame", root, c)
    tbox("Totem_Sign", (0.56, 0.24, 1.62), (0.92, 0.36, 2.02), "blue", root, c, bevel=0.015)
    for side, y0, y1 in (("Front", 0.234, 0.24), ("Back", 0.36, 0.366)):
        tbox("Totem_Dot_" + side, (0.71, y0, 1.86), (0.77, y1, 1.92), "text_white", root, c)
        tbox("Totem_Stem_" + side, (0.71, y0, 1.68), (0.77, y1, 1.83), "text_white", root, c)
    add_mounts("info_desk", root, c)


def build_currency_exchange(root, c):
    counter("Exchange", -0.90, 0.90, 1.00, "white", "gold", "dark", root, c)
    # A glass screen on the front edge with a pass-through tray under each window.
    for i, x in enumerate((-0.88, 0.0, 0.88)):
        tbox("Screen_Post_%d" % i, (x - 0.02, -0.36, 1.00), (x + 0.02, -0.32, 1.86), "frame", root, c)
    # Back posts carry the header over the staff side.
    for i, x in enumerate((-0.88, 0.88)):
        tbox("Header_Post_%d" % i, (x - 0.02, 0.24, 1.00), (x + 0.02, 0.28, 1.86), "frame", root, c)
    for i, (x0, x1) in enumerate(((-0.86, -0.02), (0.02, 0.86))):
        tbox("Screen_Glass_%d" % i, (x0, -0.345, 1.12), (x1, -0.335, 1.86), "glass", root, c)
        xm = (x0 + x1) / 2.0
        tbox("Screen_Tray_%d" % i, (xm - 0.16, -0.42, 1.00), (xm + 0.16, -0.26, 1.03), "metal", root, c)
    staff_monitor("Exchange", 0.5, root, c)
    # Header with the rate board: flags, rate bars and coins, one replaceable node.
    tbox("Exchange_Header", (-0.92, -0.38, 1.86), (0.92, 0.30, 2.16), "blue", root, c, bevel=0.012)
    face = cafe.group("Sign_Face", root, c)
    tbox("Sign_Face_Board", (-0.88, -0.40, 1.89), (0.88, -0.38, 2.13), "screen", face, c)
    flags = ("red", "kid_blue", "sun")
    for row in range(3):
        z0 = 2.06 - row * 0.07
        tbox("Sign_Face_Flag_%d" % row, (-0.82, -0.42, z0), (-0.72, -0.40, z0 + 0.045), flags[row], face, c)
        tbox("Sign_Face_Rate_%d" % row, (-0.66, -0.42, z0 + 0.01), (0.30, -0.40, z0 + 0.035),
             ("text_yellow", "text_white")[row % 2], face, c)
    for i, x in enumerate((0.48, 0.64, 0.80)):
        cyl_y("Sign_Face_Coin_%d" % i, x, 2.01 - 0.03 * (i % 2), -0.42, -0.40, 0.065, "gold", face, c)
    add_mounts("currency_exchange", root, c)


def build_atm(root, c):
    # Godot z -0.42..0.10 cabinet; the keypad shelf reaches z 0.22.
    tbox("Atm_Plinth", (-0.30, -0.10, 0.0), (0.30, 0.42, 0.06), "dark", root, c)
    tbox("Atm_Body", (-0.28, -0.08, 0.06), (0.28, 0.42, 1.50), "metal", root, c, bevel=0.015)
    tbox("Atm_Fascia", (-0.26, -0.10, 0.62), (0.26, -0.08, 1.48), "blue", root, c)
    tbox("Atm_Screen_Frame", (-0.19, -0.13, 1.12), (0.19, -0.10, 1.42), "dark", root, c, deg=-10.0,
         pivot=(0.0, -0.10, 1.27))
    tbox("Atm_Screen", (-0.16, -0.135, 1.15), (0.16, -0.13, 1.39), "screen_sky", root, c, deg=-10.0,
         pivot=(0.0, -0.10, 1.27))
    tbox("Atm_Shelf", (-0.22, -0.22, 0.98), (0.22, -0.08, 1.03), "dark", root, c, bevel=0.008)
    for r in range(3):
        for k in range(3):
            x = -0.06 + k * 0.05
            y = -0.19 + r * 0.035
            tbox("Atm_Key_%d%d" % (r, k), (x - 0.017, y - 0.012, 1.03), (x + 0.017, y + 0.012, 1.04), "white", root, c)
    tbox("Atm_Card_Slot", (0.10, -0.115, 1.06), (0.20, -0.10, 1.09), "lamp_green", root, c)
    tbox("Atm_Cash_Lip", (-0.15, -0.13, 0.84), (0.15, -0.10, 0.86), "frame", root, c)
    tbox("Atm_Cash_Slot", (-0.13, -0.105, 0.86), (0.13, -0.10, 0.92), "dark", root, c)
    tbox("Atm_Header", (-0.30, -0.14, 1.50), (0.30, 0.42, 1.78), "blue", root, c, bevel=0.012)
    tbox("Atm_Header_Lit", (-0.24, -0.145, 1.55), (0.24, -0.14, 1.73), "text_white", root, c)
    for i, x in enumerate((-0.14, 0.0, 0.14)):
        tbox("Atm_Header_Mark_%d" % i, (x - 0.035, -0.15, 1.58), (x + 0.035, -0.145, 1.70), "lamp_green", root, c)
    add_mounts("atm", root, c)


def green_cross(prefix, x, y0, y1, zc, size, root, c):
    arm, bar = size / 2.0, size / 6.0
    tbox(prefix + "_V", (x - bar, y0, zc - arm), (x + bar, y1, zc + arm), "lamp_green", root, c)
    tbox(prefix + "_H", (x - arm, y0, zc - bar), (x + arm, y1, zc + bar), "lamp_green", root, c)


def build_pharmacy_counter(root, c):
    counter("Pharm", -0.90, 0.90, 1.00, "white", "kid_green", "top", root, c)
    till("Pharm_Till", -0.5, root, c)
    # A small medicine shelf on the staff edge, facing the customer.
    tbox("Med_Shelf_Back", (-0.86, 0.36, 1.00), (0.40, 0.40, 1.42), "white", root, c)
    for side, x0, x1 in (("L", -0.86, -0.83), ("R", 0.37, 0.40)):
        tbox("Med_Shelf_Side_" + side, (x0, 0.22, 1.00), (x1, 0.40, 1.42), "white", root, c)
    tbox("Med_Shelf_Board", (-0.83, 0.22, 1.20), (0.37, 0.36, 1.22), "white", root, c)
    tbox("Med_Shelf_Top", (-0.86, 0.22, 1.40), (0.40, 0.40, 1.43), "kid_green", root, c)
    pals = ("kid_blue", "pink", "orange", "white", "purple", "sun")
    for row, z in enumerate((1.00, 1.22)):
        for i in range(6):
            x = -0.74 + i * 0.19
            h = 0.12 if (i + row) % 2 else 0.09
            tbox("Med_Box_%d%d" % (row, i), (x - 0.07, 0.25, z), (x + 0.07, 0.34, z + h), pals[(i + row) % 6], root, c)
    # The green cross sign on a post at the +x end, lit on both faces.
    cyl("Cross_Post", 0.74, 0.30, 1.00, 1.60, 0.025, "frame", root, c)
    tbox("Cross_Plate", (0.56, 0.27, 1.58), (0.92, 0.33, 1.94), "white", root, c, bevel=0.012)
    green_cross("Cross_Front", 0.74, 0.265, 0.27, 1.76, 0.28, root, c)
    green_cross("Cross_Back", 0.74, 0.33, 0.335, 1.76, 0.28, root, c)
    add_mounts("pharmacy_counter", root, c)


def build_pharmacy_shelf(root, c):
    # A 0.5 m deep wall shelf on the back of the footprint (Godot z -0.42..0.08).
    tbox("Shelf_Back", (-0.88, 0.38, 0.0), (0.88, 0.42, 1.75), "white", root, c)
    for side, x0, x1 in (("L", -0.92, -0.88), ("R", 0.88, 0.92)):
        tbox("Shelf_Side_" + side, (x0, -0.08, 0.0), (x1, 0.42, 1.75), "white", root, c)
    tbox("Shelf_Plinth", (-0.88, -0.06, 0.0), (0.88, 0.38, 0.10), "kid_green", root, c)
    levels = (0.10, 0.51, 0.89, 1.27)
    for k, z in enumerate(levels[1:]):
        tbox("Shelf_Board_%d" % k, (-0.88, -0.08, z - 0.03), (0.88, 0.38, z), "white", root, c)
    tbox("Shelf_Top", (-0.92, -0.08, 1.72), (0.92, 0.42, 1.75), "white", root, c)
    pals = ("kid_blue", "pink", "orange", "white", "kid_green", "purple", "sun", "red")
    n = 0
    for row, z in enumerate(levels):
        x = -0.84
        i = 0
        while True:
            w = (0.12, 0.16, 0.10, 0.14)[(i + row) % 4]
            h = (0.22, 0.16, 0.26, 0.19)[(i + 2 * row) % 4]
            if x + w > 0.84:
                break
            tbox("Product_%d" % n, (x + 0.01, -0.04, z), (x + w - 0.01, 0.24, z + h), pals[(i + 3 * row) % 8], root, c)
            x += w
            i += 1
            n += 1
    # Header board with the green cross.
    tbox("Shelf_Header", (-0.92, 0.30, 1.75), (0.92, 0.42, 1.98), "white", root, c, bevel=0.01)
    green_cross("Shelf_Cross", -0.72, 0.295, 0.30, 1.865, 0.18, root, c)
    tbox("Shelf_Header_Bar", (-0.56, 0.295, 1.84), (0.70, 0.30, 1.89), "kid_green", root, c)
    add_mounts("pharmacy_shelf", root, c)


def build_shower_cubicle(root, c):
    tbox("Shower_Tray", (-0.42, -0.42, 0.0), (0.42, 0.42, 0.10), "white", root, c, bevel=0.01)
    cyl("Shower_Drain", 0.0, 0.0, 0.10, 0.105, 0.04, "dark", root, c)
    tbox("Shower_Wall", (-0.38, 0.36, 0.10), (0.38, 0.42, 2.10), "white", root, c)
    for i, z in enumerate((1.00, 1.70)):
        tbox("Shower_Tile_Band_%d" % i, (-0.38, 0.355, z), (0.38, 0.36, z + 0.12), "kid_blue", root, c)
    for i, (x, y) in enumerate(((-0.40, -0.40), (0.40, -0.40), (-0.40, 0.40), (0.40, 0.40))):
        tbox("Shower_Post_%d" % i, (x - 0.02, y - 0.02, 0.10), (x + 0.02, y + 0.02, 2.16), "frame", root, c)
    for side, x0, x1 in (("L", -0.405, -0.395), ("R", 0.395, 0.405)):
        tbox("Shower_Side_Glass_" + side, (x0, -0.38, 0.12), (x1, 0.38, 2.10), "glass", root, c)
    tbox("Shower_Head_Front", (-0.42, -0.42, 2.10), (0.42, -0.38, 2.16), "frame", root, c)
    tbox("Shower_Head_Back", (-0.42, 0.38, 2.10), (0.42, 0.42, 2.16), "frame", root, c)
    for side, x0, x1 in (("L", -0.42, -0.38), ("R", 0.38, 0.42)):
        tbox("Shower_Head_Side_" + side, (x0, -0.38, 2.10), (x1, 0.38, 2.16), "frame", root, c)
    # Riser, arm and rose on the back wall; a mixer knob.
    cyl("Shower_Riser", 0.20, 0.34, 1.00, 1.95, 0.015, "metal", root, c)
    tbox("Shower_Arm", (0.185, 0.20, 1.93), (0.215, 0.35, 1.96), "metal", root, c)
    cyl("Shower_Rose", 0.20, 0.20, 1.88, 1.93, 0.07, "metal", root, c, segs=12)
    cyl_y("Shower_Mixer", 0.20, 1.10, 0.31, 0.36, 0.04, "metal", root, c)
    # The door: a hinge empty on the front-left post, the leaf in hinge-local coordinates
    # (Blender x 0..DOOR_W, y +-0.01). Turning the empty DOOR_OPEN_DEG about Godot +Y
    # (Blender +Z) swings the free edge out to +Z.
    hinge = bpy.data.objects.new("Door_Leaf_Shower", None)
    c.objects.link(hinge)
    hinge.parent = root
    hinge.empty_display_size = 0.2
    hinge.location = (DOOR_HINGE[0], -DOOR_HINGE[2], DOOR_HINGE[1])
    w = DOOR_W
    tbox("Door_Leaf_Shower_StileA", (0.0, -0.01, 0.12), (0.03, 0.01, 2.08), "frame", hinge, c)
    tbox("Door_Leaf_Shower_StileB", (w - 0.03, -0.01, 0.12), (w, 0.01, 2.08), "frame", hinge, c)
    tbox("Door_Leaf_Shower_RailLow", (0.03, -0.01, 0.12), (w - 0.03, 0.01, 0.16), "frame", hinge, c)
    tbox("Door_Leaf_Shower_RailTop", (0.03, -0.01, 2.04), (w - 0.03, 0.01, 2.08), "frame", hinge, c)
    tbox("Door_Leaf_Shower_Glass", (0.03, -0.006, 0.16), (w - 0.03, 0.006, 2.04), "glass", hinge, c)
    # The handle on the outside face (Godot +Z), reaching Godot z 0.42.
    tbox("Door_Leaf_Shower_Handle", (w - 0.08, -0.05, 0.95), (w - 0.05, -0.03, 1.25), "metal", hinge, c)
    for k, z in enumerate((0.98, 1.20)):
        tbox("Door_Leaf_Shower_Standoff_%d" % k, (w - 0.075, -0.03, z), (w - 0.055, -0.01, z + 0.03), "metal",
             hinge, c)
    add_mounts("shower_cubicle", root, c)


def build_nap_pod(root, c):
    rz, s = POD_ROOT_Z, -1.0  # faces Godot +Z
    sbox("Pod_Toe", -0.40, 0.40, rz, s, 0.29, 0.85, 0.0, 0.06, "dark", root, c)
    # Base, back shell, roof and trim sit between the side shells (|x| 0.35), so no
    # face lies in the shells' outer planes.
    sbox("Pod_Base", -0.35, 0.35, rz, s, 0.27, 0.87, 0.06, 0.38, "white", root, c, bevel=0.02)
    sbox("Pod_Seat_0", -0.33, 0.33, rz, s, 0.22, 0.65, 0.38, SEAT_TOP, "teal", root, c, bevel=0.06)
    sbox("Pod_BackCushion_0", -0.31, 0.31, rz, s, 0.63, 0.73, SEAT_TOP, 1.45, "teal", root, c, bevel=0.035,
         lean=8.0, pivot_b=0.68, pivot_z=SEAT_TOP)
    sbox("Pod_Shell_Back", -0.35, 0.35, rz, s, 0.80, 0.87, 0.38, 1.74, "white", root, c)
    # Side shells: a slanted front edge from the arm (0.70 m) up to the roof lip; their
    # inner faces at |x| 0.35 clear the elbows (0.314 m).
    outline = [(seat_y(rz, s, b), z) for b, z in ((0.15, 0.10), (0.87, 0.10), (0.87, 1.82), (0.45, 1.82),
                                                   (0.15, 0.70))]
    for side, x0, x1 in (("L", -0.42, -0.35), ("R", 0.35, 0.42)):
        prism_yz("Pod_Shell_" + side, outline, x0, x1, "white", root, c)
    # The roof lip starts 0.45 m behind the root, underside 1.74 m (the head reaches
    # 1.68 m between 0.4 and 0.5 m behind the root while sitting down and standing up).
    sbox("Pod_Roof", -0.35, 0.35, rz, s, 0.45, 0.87, 1.74, 1.82, "white", root, c)
    sbox("Pod_Trim", -0.35, 0.35, rz, s, 0.45, 0.47, 1.70, 1.74, "teal", root, c)
    sbox("Pod_Lamp", -0.08, 0.08, rz, s, 0.70, 0.78, 1.70, 1.74, "text_yellow", root, c)
    for i, x in enumerate((-0.22, 0.22)):
        sbox("Pod_Status_%d" % i, x - 0.03, x + 0.03, rz, s, 0.442, 0.45, 1.765, 1.795, "lamp_green", root, c)
    add_mounts("nap_pod", root, c)


# ---------------------------------------------------------------- register + checks

# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {
    "bar_counter": (build_bar_counter, (2, 2), (-0.92, -0.67, 0.0), (0.92, 0.92, 1.54)),
    "restaurant_table": (build_restaurant_table, (2, 3), (-0.84, -1.296, 0.0), (0.84, 1.296, 1.01)),
    "restaurant_booth": (build_restaurant_booth, (2, 3), (-0.92, -1.42, 0.0), (0.92, 1.42, 1.15)),
    "grab_and_go_stall": (build_grab_and_go_stall, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 2.25)),
    "info_desk": (build_info_desk, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 2.02)),
    "currency_exchange": (build_currency_exchange, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 2.16)),
    "atm": (build_atm, (1, 1), (-0.30, -0.22, 0.0), (0.30, 0.42, 1.78)),
    "pharmacy_counter": (build_pharmacy_counter, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 1.94)),
    "pharmacy_shelf": (build_pharmacy_shelf, (2, 1), (-0.92, -0.08, 0.0), (0.92, 0.42, 1.98)),
    "shower_cubicle": (build_shower_cubicle, (1, 1), (-0.42, -0.42, 0.0), (0.42, 0.42, 2.16)),
    "nap_pod": (build_nap_pod, (1, 1), (-0.42, -0.30, 0.0), (0.42, 0.42, 1.82)),
}
EXTRA_NODES = {p: sorted(SERVICES[p]["mounts"]) for p in SERVICES}
EXTRA_NODES["grab_and_go_stall"] += ["Sign_Face", "Sign_Face_Mesh"]
EXTRA_NODES["currency_exchange"] += ["Sign_Face", "Sign_Face_Mesh"]
EXTRA_NODES["shower_cubicle"] += ["Door_Leaf_Shower", "Door_Leaf_Shower_Mesh"]


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside SERVICES, a name another kit owns, or an
    existing destination .glb that does not look like this builder's piece (recognised
    by structure, <Piece>_ROOT plus the required nodes; the exporter writes no marker)."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the services kit: %s" % bad)
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES)) & set(PIECES))
    if taken:
        kit.fail("services names already owned by another kit: %s" % taken)
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
        kit.log("GUARD %s existing file own=%s nodes=%s" % (p, own, sorted(names)))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    if kit.FAILS:
        sys.exit(1)


def register():
    """Add the services swatches, pieces and required nodes to the kit."""
    kit.PALETTE.update(SERVICES_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def node_quat(node):
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    return Quaternion((w, x, y, z))


def check_mounts(piece, js):
    nodes = js.get("nodes", [])
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
    root = nodes[by_name[kit.piece_title(piece) + "_ROOT"]]
    if max(abs(s - 1.0) for s in root.get("scale", [1.0, 1.0, 1.0])) > 1e-6 or "matrix" in root:
        kit.fail("%s: root node is not unit scale: %s" % (piece, root))
    mounts = SERVICES[piece]["mounts"]
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
        q = node_quat(node)
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


def import_written(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    return list(bpy.context.scene.objects)


def mesh_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in objs:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def check_inset(piece, objs):
    """Every written mesh vertex inside the footprint less the 0.08 m inset (mounts are
    empties and are not counted; staff and use mounts lie outside on purpose)."""
    w, d = SERVICES[piece]["footprint"]
    lo, hi = mesh_bounds(objs)
    lim_x, lim_z = w / 2.0 - INSET, d / 2.0 - INSET
    # Godot frame: x = Blender x, z = -Blender y.
    gx = (lo.x, hi.x)
    gz = (-hi.y, -lo.y)
    over = max(abs(gx[0]) - lim_x, gx[1] - lim_x, abs(gz[0]) - lim_z, gz[1] - lim_z, -lo.z)
    kit.log("INSET %s footprint=%dx%d limit_x=+-%.3f limit_z=+-%.3f godot_x=[%.3f, %.3f] godot_z=[%.3f, %.3f] "
            "min_y=%.4f overhang=%.4f" % (piece, w, d, lim_x, lim_z, gx[0], gx[1], gz[0], gz[1], lo.z, max(over, 0.0)))
    if over > 1e-3:
        kit.fail("%s: written mesh leaves the footprint inset by %.4f m" % (piece, over))


def check_door(objs):
    """The re-imported shower door: the hinge empty at DOOR_HINGE, its leaf mesh a child;
    turned DOOR_OPEN_DEG about Godot +Y the hinge-edge vertices stay put and the free
    edge swings out to +Z by the leaf width."""
    hinge = next((o for o in objs if o.name == "Door_Leaf_Shower"), None)
    leaf = next((o for o in objs if o.name == "Door_Leaf_Shower_Mesh"), None)
    if hinge is None or leaf is None or leaf.parent is not hinge:
        kit.fail("shower_cubicle: hinge %s leaf %s parent %s" % (hinge, leaf, getattr(leaf, "parent", None)))
        return
    hp = hinge.matrix_world.translation
    g = (hp.x, hp.z, -hp.y)
    kit.log("DOOR hinge_godot=(%.3f, %.3f, %.3f) want=%s" % (g + (DOOR_HINGE,)))
    if max(abs(a - b) for a, b in zip(g, DOOR_HINGE)) > 1e-4:
        kit.fail("shower_cubicle: hinge at %s, expected %s" % (g, DOOR_HINGE))

    def verts():
        bpy.context.view_layer.update()
        return [leaf.matrix_world @ v.co for v in leaf.data.vertices]

    closed = verts()
    near = [i for i, v in enumerate(closed) if abs(v.x - hp.x) < 1e-3 and abs(v.y - hp.y) < 0.011]
    far = max(range(len(closed)), key=lambda i: closed[i].x)
    rest = hinge.matrix_world.copy()
    # Turn the hinge about the vertical axis through its own origin (Godot +Y is
    # Blender +Z, the same sense).
    hinge.matrix_world = (Matrix.Translation(hp) @ Matrix.Rotation(math.radians(DOOR_OPEN_DEG), 4, "Z")
                          @ Matrix.Translation(-hp) @ rest)
    opened = verts()
    hinge.matrix_world = rest
    bpy.context.view_layer.update()
    # A turn about the hinge axis keeps every vertex's height and distance from the axis;
    # the hinge-edge vertices (0.01 m off the axis, the leaf's half thickness) move at
    # most 0.01 * sqrt(2).
    def axis_dist(v):
        return math.hypot(v.x - hp.x, v.y - hp.y)
    rigid = max(max(abs(axis_dist(a) - axis_dist(b)), abs(a.z - b.z)) for a, b in zip(closed, opened))
    kit.log("DOOR axis_distance_and_height_change_max=%.6f" % rigid)
    if rigid > 1e-4:
        kit.fail("shower_cubicle: the leaf does not turn about the hinge axis (%.5f m)" % rigid)
    moved_near = max((opened[i] - closed[i]).length for i in near) if near else 9.0
    moved_near = max(0.0, moved_near - 0.01 * math.sqrt(2.0))
    f0, f1 = closed[far], opened[far]
    olo = Vector((min(v.x for v in opened), min(v.y for v in opened), min(v.z for v in opened)))
    ohi = Vector((max(v.x for v in opened), max(v.y for v in opened), max(v.z for v in opened)))
    kit.log("DOOR hinge_edge_vertices=%d move_beyond_0.0141=%.6f free_edge_closed_godot=(%.3f, %.3f, %.3f) "
            "free_edge_open_godot=(%.3f, %.3f, %.3f) open_godot_x=[%.3f, %.3f] open_godot_z=[%.3f, %.3f]"
            % (len(near), moved_near, f0.x, f0.z, -f0.y, f1.x, f1.z, -f1.y, olo.x, ohi.x, -ohi.y, -olo.y))
    if not near or moved_near > 1e-4:
        kit.fail("shower_cubicle: hinge-edge vertices moved %.5f m beyond their 0.0141 m arc when the door opened"
                 % moved_near)
    if (-f1.y) - (-f0.y) < DOOR_W - 0.02 or abs(f1.x - hp.x) > 0.02:
        kit.fail("shower_cubicle: the free edge did not swing out to +Z (closed %s open %s)" % (f0, f1))
    # The open leaf stays out of the front-left post (Blender x -0.42..-0.38, y
    # -0.42..-0.38, z 0.10..2.16): every leaf face clipped to the post's interior (shrunk
    # 0.1 mm) must come out empty, so a face crossing the post with its corners outside
    # is caught too. A control triangle slicing the post with its corners outside must
    # be caught.
    post_lo, post_hi = Vector((-0.42, -0.42, 0.10)), Vector((-0.38, -0.38, 2.16))
    polys = [[opened[i] for i in p.vertices] for p in leaf.data.polygons]
    clash = sum(1 for p in polys if clip_to_box(p, post_lo, post_hi, 1e-4))
    c0 = (post_lo + post_hi) / 2.0
    control = [c0 + Vector((0.5, 0.0, 0.0)), c0 + Vector((-0.3, 0.4, 0.0)), c0 + Vector((-0.3, -0.4, 0.0))]
    caught = bool(clip_to_box(control, post_lo, post_hi, 1e-4))
    kit.log("DOOR open_leaf_faces_crossing_front_left_post=%d of %d control_slicing_triangle_caught=%s"
            % (clash, len(polys), caught))
    if clash or not caught:
        kit.fail("shower_cubicle: the open leaf passes through the front-left post (or the control was missed)")


def clip_to_box(poly, lo, hi, shrink):
    """The part of a polygon inside an axis box shrunk by `shrink` (Sutherland-Hodgman)."""
    out = list(poly)
    for axis in range(3):
        for sign, bound in ((1.0, lo[axis] + shrink), (-1.0, hi[axis] - shrink)):
            src, out = out, []
            for i, a in enumerate(src):
                b = src[(i + 1) % len(src)]
                da, db = sign * (a[axis] - bound), sign * (b[axis] - bound)
                if da >= 0.0:
                    out.append(a)
                if (da >= 0.0) != (db >= 0.0):
                    out.append(a + (b - a) * (da / (da - db)))
            if not out:
                return []
    return out


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        check_mounts(piece, js)
        objs = import_written(out)
        check_inset(piece, objs)
        if piece == "shower_cubicle":
            check_door(objs)
    data = {p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in SERVICES.items()}
    kit.log("SERVICES_DATA " + json.dumps(data))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
