"""Build the baggage pieces of the interior kit and export one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_baggage_kit.py' [-- piece ...]

Ruling baggage-rides-a-player-built-belt-from-check-in-to-a-bag-roo: bags dropped at
check-in ride a belt the player builds to a bag room, then are loaded onto the plane;
there are no sorting routes. The pieces:
- baggage_belt (1x1): a straight belt along Godot Z.
- baggage_belt_corner (1x1): a quarter turn from the +Z edge to the +X edge.
- baggage_belt_feed (1x1): a merge. A collector runs along X and an inlet joins from
  the +Z edge, so a check-in desk's belt (its +x cell runs front to back) drops onto
  the feed placed behind it. Merging is not sorting: the bag sim picks one exit.
- baggage_belt_end (1x1): the end of the line in the bag room, and the piece a bag-room
  type can require. The belt runs onto a slide that drops toward a bumper; a bag rests
  on the slide at Mount_BagRest. A beacon stands on the back corner.
- baggage_cart (1x2): a baggage dolly with a canopy; its suitcases are the separate
  node Cart_Bags, so the game can show the cart empty or loaded.
- baggage_bag: one suitcase lying flat, origin at its bottom centre, for bags riding
  the belts. It has no grid footprint.

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, every face on a measured Toon atlas
swatch, the written file re-read and checked). Belts are the one exception to the
0.08 m furniture inset: a side with a belt opening (a port) reaches the cell edge so
belts chain, and every closed side keeps the inset. check_sides() reads the written
file per side, and check_ports() proves each port's belt surface reaches the edge at
full lane width and belt height.

Belt heights match the check-in desk's belt: body to 0.32 m, belt top 0.355 m, rails
to 0.46 m. The belt surface of every belt piece is the separate node Belt_Surface (for
a swap or hide; its UVs sit in one swatch, so a UV scroll would change colour, not move
the belt). Ports are Mount_Belt_F/B/L/R empties at belt-top height on each open edge's
midpoint, +Z pointing out of the piece (an edge normal, not a flow direction). BAGGAGE
records each piece's footprint, ports and the paths a bag can take through it; it is
printed as BAGGAGE_DATA. checkin_desk's belt (build_interior_kit.py) has the same
cross-section and runs to its cell's back edge, so a feed behind the desk joins it.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "baggage_kit", "baggage_kit.blend")

INSET = 0.08
EDGE = 0.5
HALF_IN = EDGE - INSET  # 0.42
BODY_TOP = 0.32
BELT_TOP = 0.355
RAIL_TOP = 0.46
LANE = 0.35  # belt surface half width; rails from LANE to HALF_IN
TOE = 0.06
BAND = (0.22, 0.28)
BAND_T = 0.005

# The slide of baggage_belt_end (Blender y, z): from the belt end down to the bumper.
SLIDE_A = (-0.25, BELT_TOP)
SLIDE_B = (0.38, 0.20)
SLIDE_DEG = math.degrees(math.atan2(SLIDE_B[1] - SLIDE_A[1], SLIDE_B[0] - SLIDE_A[0]))  # about -17.9

# Suitcase (lying flat): width x, length y, height z in Blender metres.
BAG = (0.38, 0.55, 0.22)

# Swatches the cafe kit measured, reused for bag colours.
BAGGAGE_PALETTE = {k: cafe.CAFE_PALETTE[k] for k in ("red", "sage", "coffee", "pink", "cream")}


PAD_FACE = SLIDE_B[0] - 0.012  # Blender y of the bumper pad's front face
ROLLER_R = 0.012
ROLLER_SINK = 0.008  # roller centres sit this far below the slide surface
ROLLER_PROUD = ROLLER_R - ROLLER_SINK


def _bag_rest():
    """Godot position and +Z of a suitcase resting on the end slide: its bottom on the
    roller tops (ROLLER_PROUD above the slide plate) and its top back corner (the bag
    leans with the slide) 5 mm short of the bumper pad. Refuses a slide too short to
    hold the whole bag."""
    ay, az = SLIDE_A
    by, bz = SLIDE_B
    length = math.hypot(by - ay, bz - az)
    dy, dz = (by - ay) / length, (bz - az) / length
    ny, nz = -dz, dy  # the slide's up normal (Blender y, z)
    # s: distance up the slide from SLIDE_B to the bag's bottom back edge.
    s = (by - PAD_FACE + 0.005 + ny * (ROLLER_PROUD + BAG[2])) / dy
    if s + BAG[1] > length:
        raise RuntimeError("slide %.3f m is too short for a %.2f m bag starting %.3f m up" % (length, BAG[1], s))
    back = s + BAG[1] / 2.0
    y = by - dy * back + ny * ROLLER_PROUD
    z = bz - dz * back + nz * ROLLER_PROUD
    return (0.0, round(z, 4), round(-y, 4)), (0.0, ny, dy)


BAG_REST_POS, BAG_REST_DIR = _bag_rest()

F = ("Mount_Belt_F", (0.0, BELT_TOP, EDGE), 0.0)
B = ("Mount_Belt_B", (0.0, BELT_TOP, -EDGE), 180.0)
L = ("Mount_Belt_L", (-EDGE, BELT_TOP, 0.0), -90.0)
R = ("Mount_Belt_R", (EDGE, BELT_TOP, 0.0), 90.0)

# piece -> footprint, ports (name, Godot position, yaw; yaw 0 faces +Z), paths between
# ports, other mounts {name: (Godot position, Godot +Z direction)}, and the Godot sides
# open to the cell edge (every other side keeps the 0.08 m inset).
BAGGAGE = {
    "baggage_belt": {"footprint": (1, 1), "ports": [F, B], "paths": [["F", "B"]], "mounts": {}},
    "baggage_belt_corner": {"footprint": (1, 1), "ports": [F, R], "paths": [["F", "R"]], "mounts": {}},
    "baggage_belt_feed": {
        "footprint": (1, 1), "ports": [F, L, R], "paths": [["F", "L"], ["F", "R"], ["L", "R"]], "mounts": {},
    },
    "baggage_belt_end": {
        "footprint": (1, 1), "ports": [F], "paths": [["F", "BagRest"]],
        "mounts": {"Mount_BagRest": (BAG_REST_POS, BAG_REST_DIR)},
    },
    "baggage_cart": {"footprint": (1, 2), "ports": [], "paths": [], "mounts": {}},
    "baggage_bag": {"footprint": None, "ports": [], "paths": [], "mounts": {}},
}
SIDE_OF = {"Mount_Belt_F": "+z", "Mount_Belt_B": "-z", "Mount_Belt_L": "-x", "Mount_Belt_R": "+x"}


# ---------------------------------------------------------------- geometry


def tbox(*a, **k):
    return cafe.tbox(*a, **k)


def group(name, root, c):
    return cafe.group(name, root, c)


def cyl_x(name, x0, x1, y, z, r, pal, parent, c, segs=8):
    """A cylinder along Blender x from x0 to x1, axis at (y, z); a vertex sits at the bottom."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=abs(x1 - x0))
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(90.0), 4, "Y"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(((x0 + x1) / 2.0, y, z)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def arc_slab(name, r0, r1, z0, z1, pal, parent, c, segs=8, pivot=(EDGE, -EDGE)):
    """A quarter ring between radii r0 and r1 about `pivot` (Blender x, y), from the
    Godot +Z edge (direction -x) to the Godot +X edge (direction +y)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs + 1):
        a = math.radians(90.0 * i / segs)
        d = Vector((-math.cos(a), math.sin(a), 0.0))
        p = Vector((pivot[0], pivot[1], 0.0))
        rings.append([bm.verts.new(p + d * r + Vector((0, 0, z))) for r, z in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
    for i in range(segs):
        a, b = rings[i], rings[i + 1]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def suitcase(prefix, x, y, z, size, pal, parent, c, standing=False, handle=True):
    """A suitcase with two straps, a handle and a tag; (x, y, z) is its bottom centre and
    size its (x, y, z) extent. Standing, the handle is on top and the straps go round.
    A bag with another stacked on it has no handle or tag (handle=False)."""
    sx, sy, sz = size
    tbox(prefix + "_Body", (x - sx / 2, y - sy / 2, z), (x + sx / 2, y + sy / 2, z + sz), pal, parent, c,
         bevel=0.03)
    for i, f in enumerate((-0.22, 0.22)):
        if standing:
            zc = z + sz / 2 + f * sz
            tbox("%s_Strap_%d" % (prefix, i), (x - sx / 2 - 0.006, y - sy / 2 - 0.006, zc - 0.02),
                 (x + sx / 2 + 0.006, y + sy / 2 + 0.006, zc + 0.02), "dark", parent, c)
        else:
            yc = y + f * sy
            tbox("%s_Strap_%d" % (prefix, i), (x - sx / 2 - 0.006, yc - 0.02, z),
                 (x + sx / 2 + 0.006, yc + 0.02, z + sz + 0.006), "dark", parent, c)
    if not handle:
        return
    top = z + sz + 0.006
    hw = min(sx, sy) * 0.18
    tbox(prefix + "_Handle", (x - hw, y - 0.015, top), (x + hw, y + 0.015, top + 0.03), "dark", parent, c)
    tbox(prefix + "_Tag", (x + hw + 0.01, y - 0.02, top), (x + hw + 0.05, y + 0.02, top + 0.01), "yellow", parent, c)


def run_x(prefix, x0, x1, root, c, front=True, back=True):
    """Straight belt structure along Blender x between x0 and x1, centred on y = 0; the
    front (Blender -y) or back rail and band can be left out where an inlet joins."""
    tbox(prefix + "_ToeKick", (x0, -HALF_IN + 0.04, 0), (x1, HALF_IN - 0.04, TOE), "dark", root, c)
    tbox(prefix + "_Body", (x0, -HALF_IN + BAND_T, TOE), (x1, HALF_IN - BAND_T, BODY_TOP), "metal", root, c)
    sides = [("B", 1.0)] if back else []
    sides += [("F", -1.0)] if front else []
    for side, s in sides:
        y0, y1 = sorted((s * (HALF_IN - BAND_T), s * HALF_IN))
        tbox("%s_Band_%s" % (prefix, side), (x0, y0, BAND[0]), (x1, y1, BAND[1]), "yellow", root, c)
        r0, r1 = sorted((s * LANE, s * HALF_IN))
        tbox("%s_Rail_%s" % (prefix, side), (x0, r0, BODY_TOP), (x1, r1, RAIL_TOP), "frame", root, c)


def run_y(prefix, y0, y1, root, c, surface):
    """Straight belt structure along Blender y between y0 and y1, centred on x = 0."""
    tbox(prefix + "_ToeKick", (-HALF_IN + 0.04, y0, 0), (HALF_IN - 0.04, y1, TOE), "dark", root, c)
    tbox(prefix + "_Body", (-HALF_IN + BAND_T, y0, TOE), (HALF_IN - BAND_T, y1, BODY_TOP), "metal", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * (HALF_IN - BAND_T), s * HALF_IN))
        tbox("%s_Band_%s" % (prefix, side), (x0, y0, BAND[0]), (x1, y1, BAND[1]), "yellow", root, c)
        r0, r1 = sorted((s * LANE, s * HALF_IN))
        tbox("%s_Rail_%s" % (prefix, side), (r0, y0, BODY_TOP), (r1, y1, RAIL_TOP), "frame", root, c)
    tbox(prefix + "_Belt", (-LANE, y0, BODY_TOP), (LANE, y1, BELT_TOP), "dark", surface, c)


def add_mounts(piece, root, c):
    spec = BAGGAGE[piece]
    for name, (gx, gy, gz), yaw in spec["ports"]:
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))
    for name, ((gx, gy, gz), _d) in spec["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        ob.location = (gx, -gz, gy)
        # Mount_BagRest: +Z (Blender -y) tilted up the slide, toward the belt.
        ob.rotation_euler = (math.radians(SLIDE_DEG), 0.0, 0.0)


# ---------------------------------------------------------------- pieces


def build_baggage_belt(root, c):
    surface = group("Belt_Surface", root, c)
    run_y("Belt", -EDGE, EDGE, root, c, surface)
    # A second surface part: thin dark seams across the belt at a third and two thirds,
    # so the belt reads as jointed rubber and the run reads in the belt direction.
    for i, y in enumerate((-EDGE / 3.0, EDGE / 3.0)):
        tbox("Belt_Seam_%d" % i, (-LANE, y - 0.008, BELT_TOP), (LANE, y + 0.008, BELT_TOP + 0.002), "metal",
             surface, c)
    add_mounts("baggage_belt", root, c)


def build_baggage_belt_corner(root, c):
    surface = group("Belt_Surface", root, c)
    r_in, r_out = EDGE - HALF_IN, EDGE + HALF_IN  # 0.08, 0.92
    r_lane_in, r_lane_out = EDGE - LANE, EDGE + LANE  # 0.15, 0.85
    arc_slab("Corner_ToeKick", r_in + 0.04, r_out - 0.04, 0.0, TOE, "dark", root, c)
    arc_slab("Corner_Body", r_in + BAND_T, r_out - BAND_T, TOE, BODY_TOP, "metal", root, c)
    arc_slab("Corner_Band_In", r_in, r_in + BAND_T, BAND[0], BAND[1], "yellow", root, c)
    arc_slab("Corner_Band_Out", r_out - BAND_T, r_out, BAND[0], BAND[1], "yellow", root, c)
    arc_slab("Corner_Rail_In", r_in, r_lane_in, BODY_TOP, RAIL_TOP, "frame", root, c)
    arc_slab("Corner_Rail_Out", r_lane_out, r_out, BODY_TOP, RAIL_TOP, "frame", root, c)
    arc_slab("Corner_Belt", r_lane_in, r_lane_out, BODY_TOP, BELT_TOP, "dark", surface, c)
    # Two seams across the belt at 30 and 60 degrees.
    for i, deg in enumerate((-30.0, -60.0)):
        tbox("Corner_Seam_%d" % i, (EDGE - r_lane_out, -EDGE - 0.008, BELT_TOP),
             (EDGE - r_lane_in, -EDGE + 0.008, BELT_TOP + 0.002), "metal", surface, c,
             axis="Z", deg=deg, pivot=(EDGE, -EDGE, 0.0))
    add_mounts("baggage_belt_corner", root, c)


def build_baggage_belt_feed(root, c):
    surface = group("Belt_Surface", root, c)
    # Collector along X, edge to edge; its front rail and band stop where the inlet joins.
    run_x("Collector", -EDGE, EDGE, root, c, front=False)
    for side, x0, x1 in (("L", -EDGE, -LANE), ("R", LANE, EDGE)):
        tbox("Collector_Rail_F" + side, (x0, -HALF_IN, BODY_TOP), (x1, -LANE, RAIL_TOP), "frame", root, c)
    for side, x0, x1 in (("L", -EDGE, -HALF_IN), ("R", HALF_IN, EDGE)):
        tbox("Collector_Band_F" + side, (x0, -HALF_IN, BAND[0]), (x1, -HALF_IN + BAND_T, BAND[1]), "yellow",
             root, c)
    tbox("Collector_Belt", (-EDGE, -LANE, BODY_TOP), (EDGE, LANE, BELT_TOP), "dark", surface, c)
    # Inlet from the Godot +Z edge (Blender -y), between the collector and the edge.
    tbox("Inlet_ToeKick", (-HALF_IN + 0.04, -EDGE, 0), (HALF_IN - 0.04, -HALF_IN + 0.04, TOE), "dark", root, c)
    tbox("Inlet_Body", (-HALF_IN + BAND_T, -EDGE, TOE), (HALF_IN - BAND_T, -HALF_IN + BAND_T, BODY_TOP), "metal",
         root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * (HALF_IN - BAND_T), s * HALF_IN))
        tbox("Inlet_Band_" + side, (x0, -EDGE, BAND[0]), (x1, -HALF_IN, BAND[1]), "yellow", root, c)
        r0, r1 = sorted((s * LANE, s * HALF_IN))
        tbox("Inlet_Rail_" + side, (r0, -EDGE, BODY_TOP), (r1, -HALF_IN, RAIL_TOP), "frame", root, c)
    tbox("Inlet_Belt", (-LANE, -EDGE, BODY_TOP), (LANE, -LANE, BELT_TOP), "dark", surface, c)
    add_mounts("baggage_belt_feed", root, c)


def build_baggage_belt_end(root, c):
    surface = group("Belt_Surface", root, c)
    ay = SLIDE_A[0]
    # Level belt from the Godot +Z edge to the slide.
    run_y("End", -EDGE, ay, root, c, surface)
    seam_y = (-EDGE + ay) / 2.0
    tbox("End_Seam", (-LANE, seam_y - 0.008, BELT_TOP), (LANE, seam_y + 0.008, BELT_TOP + 0.002), "metal", surface, c)
    # Under the slide: a low base, side guards to rail height and the bumper at the back.
    tbox("Slide_Base", (-HALF_IN + 0.04, ay, 0), (HALF_IN - 0.04, HALF_IN, TOE), "dark", root, c)
    tbox("Slide_Box", (-LANE, ay, TOE), (LANE, SLIDE_B[0], SLIDE_B[1] - 0.03), "metal", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * LANE, s * HALF_IN))
        tbox("Slide_Guard_" + side, (x0, ay, TOE), (x1, HALF_IN, RAIL_TOP), "frame", root, c, bevel=0.01)
        b0, b1 = sorted((s * (HALF_IN - BAND_T), s * HALF_IN))
        tbox("Slide_Band_" + side, (b0, ay, BAND[0]), (b1, HALF_IN - 0.01, BAND[1]), "yellow", root, c)
    length = math.hypot(SLIDE_B[0] - SLIDE_A[0], SLIDE_B[1] - SLIDE_A[1])
    tbox("Slide_Plate", (-LANE, ay, BELT_TOP - 0.03), (LANE, ay + length, BELT_TOP), "white", root, c,
         axis="X", deg=SLIDE_DEG, pivot=(0.0, ay, BELT_TOP))
    # Rollers across the top of the slide, every 0.12 m, standing ROLLER_PROUD above it.
    dy, dz = (SLIDE_B[0] - ay) / length, (SLIDE_B[1] - SLIDE_A[1]) / length
    for i in range(5):
        t = 0.06 + i * 0.12
        cyl_x("Slide_Roller_%d" % i, -LANE + 0.02, LANE - 0.02, ay + dy * t + dz * ROLLER_SINK,
              SLIDE_A[1] + dz * t - dy * ROLLER_SINK, ROLLER_R, "metal", root, c)
    tbox("Slide_Bumper", (-LANE, SLIDE_B[0], TOE), (LANE, HALF_IN, 0.36), "yellow", root, c, bevel=0.01)
    tbox("Slide_Bumper_Pad", (-LANE + 0.02, PAD_FACE, 0.22), (LANE - 0.02, SLIDE_B[0], 0.32), "dark",
         root, c)
    # Beacon on the back right guard.
    kit.cyl("Beacon_Post", 0.385, 0.385, RAIL_TOP, 1.18, 0.018, "frame", root, c)
    kit.cyl("Beacon_Base", 0.385, 0.385, 1.18, 1.21, 0.034, "dark", root, c)
    kit.cyl("Beacon_Lamp", 0.385, 0.385, 1.21, 1.30, 0.03, "text_yellow", root, c)
    add_mounts("baggage_belt_end", root, c)


def build_baggage_cart(root, c):
    # Chassis and wheels.
    for i, (x, y) in enumerate(((-0.33, -0.62), (0.33, -0.62), (-0.33, 0.62), (0.33, 0.62))):
        s = -1.0 if x < 0 else 1.0
        x0, x1 = sorted((x - s * 0.04, x + s * 0.04))
        cyl_x("Cart_Wheel_%d" % i, x0, x1, y, 0.13, 0.13, "dark", root, c)
        h0, h1 = sorted((x + s * 0.04, x + s * 0.05))
        cyl_x("Cart_Hub_%d" % i, h0, h1, y, 0.13, 0.05, "metal", root, c)
    tbox("Cart_Axle_F", (-0.29, -0.645, 0.11), (0.29, -0.595, 0.15), "frame", root, c)
    tbox("Cart_Axle_B", (-0.29, 0.595, 0.11), (0.29, 0.645, 0.15), "frame", root, c)
    tbox("Cart_Chassis", (-0.22, -0.84, 0.15), (0.22, 0.84, 0.28), "frame", root, c)
    tbox("Cart_Deck", (-HALF_IN, -0.86, 0.28), (HALF_IN, 0.86, 0.36), "metal", root, c, bevel=0.01)
    tbox("Cart_Deck_Band_L", (-HALF_IN, -0.86, 0.30), (-HALF_IN + BAND_T, 0.86, 0.34), "yellow", root, c)
    tbox("Cart_Deck_Band_R", (HALF_IN - BAND_T, -0.86, 0.30), (HALF_IN, 0.86, 0.34), "yellow", root, c)
    # End boards, side rails, posts and the canopy roof.
    for end, s in (("F", -1.0), ("B", 1.0)):
        y0, y1 = sorted((s * 0.86, s * 0.82))
        tbox("Cart_EndBoard_" + end, (-0.40, y0, 0.36), (0.40, y1, 0.72), "blue", root, c, bevel=0.01)
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.37, s * 0.41))
        tbox("Cart_SideRail_" + side, (x0, -0.82, 0.52), (x1, 0.82, 0.56), "frame", root, c)
        for end, t in (("F", -1.0), ("B", 1.0)):
            y0, y1 = sorted((t * 0.86, t * 0.82))
            tbox("Cart_Post_%s%s" % (side, end), (x0, y0, 0.36), (x1, y1, 1.55), "frame", root, c)
    tbox("Cart_Roof", (-HALF_IN, -0.90, 1.55), (HALF_IN, 0.90, 1.62), "blue", root, c, bevel=0.02)
    tbox("Cart_Roof_Trim", (-0.40, -0.88, 1.52), (0.40, 0.88, 1.55), "white", root, c)
    # Tow bar folded up against the front end board (Godot +Z), with a ring handle.
    tbox("Cart_Hitch", (-0.05, -0.90, 0.20), (0.05, -0.84, 0.26), "dark", root, c)
    tbox("Cart_TowBar", (-0.025, -0.90, 0.26), (0.025, -0.87, 0.98), "frame", root, c)
    tbox("Cart_TowRing", (-0.08, -0.90, 0.98), (0.08, -0.87, 1.04), "yellow", root, c)
    # Suitcases on the deck: one node, so the game can show the cart empty or loaded.
    bags = group("Cart_Bags", root, c)
    deck = 0.36
    # Bags 0 and 1 are the same height and carry no handles; bag 2 lies across both,
    # on their straps (0.22 + 0.006).
    suitcase("Cart_Bag_0", -0.17, -0.50, deck, (0.34, 0.52, 0.22), "red", bags, c, handle=False)
    suitcase("Cart_Bag_1", 0.18, -0.48, deck, (0.36, 0.56, 0.22), "sage", bags, c, handle=False)
    suitcase("Cart_Bag_2", 0.00, -0.47, deck + 0.226, (0.40, 0.50, 0.18), "blue", bags, c)
    suitcase("Cart_Bag_3", -0.16, 0.12, deck, (0.36, 0.24, 0.58), "yellow", bags, c, standing=True)
    suitcase("Cart_Bag_4", 0.18, 0.14, deck, (0.30, 0.22, 0.50), "coffee", bags, c, standing=True)
    suitcase("Cart_Bag_5", 0.00, 0.58, deck, (0.62, 0.40, 0.24), "pink", bags, c)


def build_baggage_bag(root, c):
    suitcase("Bag", 0.0, 0.0, 0.0, BAG, "red", root, c)


# piece -> (builder, footprint, expected Blender bounds lo/hi).
PIECES = {
    "baggage_belt": (build_baggage_belt, (1, 1), (-HALF_IN, -EDGE, 0.0), (HALF_IN, EDGE, RAIL_TOP)),
    "baggage_belt_corner": (build_baggage_belt_corner, (1, 1), (-HALF_IN, -EDGE, 0.0), (EDGE, HALF_IN, RAIL_TOP)),
    "baggage_belt_feed": (build_baggage_belt_feed, (1, 1), (-EDGE, -EDGE, 0.0), (EDGE, HALF_IN, RAIL_TOP)),
    "baggage_belt_end": (build_baggage_belt_end, (1, 1), (-HALF_IN, -EDGE, 0.0), (HALF_IN, HALF_IN, 1.30)),
    "baggage_cart": (build_baggage_cart, (1, 2), (-HALF_IN, -0.90, 0.0), (HALF_IN, 0.90, 1.62)),
    "baggage_bag": (build_baggage_bag, None, (-0.196, -0.275, 0.0), (0.196, 0.275, 0.256)),
}


def extra_nodes(piece):
    spec = BAGGAGE[piece]
    names = [p[0] for p in spec["ports"]] + list(spec["mounts"])
    if spec["ports"]:
        names += ["Belt_Surface", "Belt_Surface_Mesh"]
    if piece == "baggage_cart":
        names += ["Cart_Bags", "Cart_Bags_Mesh"]
    return sorted(names)


EXTRA_NODES = {p: extra_nodes(p) for p in PIECES}


# ---------------------------------------------------------------- register + checks


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside this kit, a name another kit owns, a
    mount name another kit pins elsewhere, or an existing destination .glb that is not
    this builder's piece (recognised by its <Piece>_ROOT and required nodes)."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the baggage kit: %s" % bad)
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES)) & set(PIECES))
    if taken:
        kit.fail("baggage names already owned by another kit: %s" % taken)
    ours = {n for v in EXTRA_NODES.values() for n in v if n.startswith("Mount_")}
    clash = sorted(ours & (set(kit.NODE_TRANSLATIONS) | {n for v in svc.EXTRA_NODES.values() for n in v}
                           | {n for v in act.EXTRA_NODES.values() for n in v}))
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
    """Add the baggage swatches, pieces, required nodes and mount positions to the kit."""
    kit.PALETTE.update(BAGGAGE_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    for spec in BAGGAGE.values():
        for name, pos, _yaw in spec["ports"]:
            kit.NODE_TRANSLATIONS[name] = pos
        for name, (pos, _d) in spec["mounts"].items():
            kit.NODE_TRANSLATIONS[name] = pos


def check_mounts(piece, js):
    """Every port and mount in the written file at its position, its +Z the stated way."""
    by_name = {n.get("name"): n for n in js.get("nodes", [])}
    spec = BAGGAGE[piece]
    want = {name: (pos, Vector((math.sin(math.radians(yaw)), 0.0, math.cos(math.radians(yaw)))))
            for name, pos, yaw in spec["ports"]}
    want.update({name: (pos, Vector(d)) for name, (pos, d) in spec["mounts"].items()})
    for name, (pos, wdir) in want.items():
        node = by_name.get(name)
        if node is None:
            kit.fail("%s: mount %s missing from the written file" % (piece, name))
            continue
        t = node.get("translation", [0.0, 0.0, 0.0])
        x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        facing = Quaternion((w, x, y, z)) @ Vector((0.0, 0.0, 1.0))
        kit.log("MOUNT %s %s pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f) want_facing=(%.3f, %.3f, %.3f)"
                % (piece, name, t[0], t[1], t[2], facing.x, facing.y, facing.z, wdir.x, wdir.y, wdir.z))
        if (facing - wdir).length > 1e-3 or max(abs(a - b) for a, b in zip(t, pos)) > 1e-4:
            kit.fail("%s: mount %s at %s facing %s, expected %s facing %s" % (piece, name, t, facing, pos, wdir))


def import_written(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def godot_points(objs):
    """World vertices of `objs` in the Godot frame (x, y up, z = -Blender y)."""
    pts = []
    for ob in objs:
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            pts.append(Vector((w.x, w.z, -w.y)))
    return pts


def check_sides(piece, objs):
    """Per side: a port side reaches the cell edge, a closed side keeps the inset."""
    fp = BAGGAGE[piece]["footprint"]
    if fp is None:
        kit.log("SIDES %s no grid footprint (a prop)" % piece)
        return
    w, d = fp
    open_sides = {SIDE_OF[p[0]] for p in BAGGAGE[piece]["ports"]}
    pts = godot_points(objs)
    ext = {"+x": max(p.x for p in pts), "-x": -min(p.x for p in pts),
           "+z": max(p.z for p in pts), "-z": -min(p.z for p in pts)}
    half = {"+x": w / 2.0, "-x": w / 2.0, "+z": d / 2.0, "-z": d / 2.0}
    min_y = min(p.y for p in pts)
    parts = []
    for side in ("+x", "-x", "+z", "-z"):
        limit = half[side] if side in open_sides else half[side] - INSET
        parts.append("%s=%.4f/%s%.3f" % (side, ext[side], "open" if side in open_sides else "closed", limit))
        if ext[side] > limit + 1e-3:
            kit.fail("%s: written mesh reaches %.4f on %s, limit %.3f" % (piece, ext[side], side, limit))
        if side in open_sides and ext[side] < limit - 1e-3:
            kit.fail("%s: port side %s stops at %.4f, short of the edge %.3f" % (piece, side, ext[side], limit))
    kit.log("SIDES %s footprint=%dx%d %s min_y=%.4f" % (piece, w, d, " ".join(parts), min_y))
    if min_y < -1e-4:
        kit.fail("%s: mesh below the floor (%.4f)" % (piece, min_y))


def check_ports(piece, objs):
    """Each port: the Belt_Surface mesh reaches the edge with a top at belt height
    spanning the full lane width, so two pieces placed edge to edge join."""
    surf = [o for o in objs if o.name.startswith("Belt_Surface_Mesh")]
    if not BAGGAGE[piece]["ports"]:
        return
    if len(surf) != 1:
        kit.fail("%s: expected one Belt_Surface_Mesh, found %d" % (piece, len(surf)))
        return
    pts = godot_points(surf)
    for name, (px, _py, pz), _yaw in BAGGAGE[piece]["ports"]:
        on_x = abs(px) > 0.25
        edge_pts = [p for p in pts if (abs(p.x - px) < 1e-3 if on_x else abs(p.z - pz) < 1e-3)
                    and abs(p.y - BELT_TOP) < 1e-3]
        across = [p.z if on_x else p.x for p in edge_pts]
        span = (min(across), max(across)) if across else (0.0, 0.0)
        kit.log("PORT %s %s edge_top_vertices=%d across=[%.3f, %.3f] top=%.3f"
                % (piece, name, len(edge_pts), span[0], span[1], BELT_TOP))
        if span[0] > -LANE + 1e-3 or span[1] < LANE - 1e-3:
            kit.fail("%s: %s belt surface at the edge spans %s, not the lane +-%.2f" % (piece, name, span, LANE))


def check_rest(objs):
    """A suitcase box at Mount_BagRest (bag frame: x +-0.196, y +-0.275, z 0..0.256) must
    not cross any face of the written belt end (rollers, slide, bumper pad, guards):
    every face is clipped to the box shrunk 0.5 mm and must come out empty. Control:
    the same box 1 cm lower must be caught."""
    mount = next((o for o in bpy.context.scene.objects if o.name.startswith("Mount_BagRest")), None)
    if mount is None:
        kit.fail("baggage_belt_end: Mount_BagRest missing on re-import")
        return
    inv = mount.matrix_world.inverted()
    lo, hi = Vector((-0.196, -0.275, 0.0)), Vector((0.196, 0.275, 0.256))
    polys = []
    for ob in objs:
        mw = ob.matrix_world
        for p in ob.data.polygons:
            polys.append([inv @ (mw @ ob.data.vertices[i].co) for i in p.vertices])
    clash = sum(1 for p in polys if svc.clip_to_box(p, lo, hi, 5e-4))
    drop = Vector((0.0, 0.0, 0.01))
    caught = sum(1 for p in polys if svc.clip_to_box(p, lo - drop, hi - drop, 5e-4))
    kit.log("REST baggage_belt_end faces=%d crossing_bag_box=%d control_1cm_lower_crossing=%d"
            % (len(polys), clash, caught))
    if clash or not caught:
        kit.fail("baggage_belt_end: the resting bag crosses the piece (or the control was missed)")


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        check_mounts(piece, js)
        objs = import_written(out)
        check_sides(piece, objs)
        check_ports(piece, objs)
        if piece == "baggage_belt_end":
            check_rest(objs)
    data = {p: {"footprint": s["footprint"], "ports": {n: {"pos": pos, "yaw": yaw} for n, pos, yaw in s["ports"]},
                "paths": s["paths"], "mounts": {n: {"pos": pos, "plus_z": d} for n, (pos, d) in s["mounts"].items()}}
            for p, s in BAGGAGE.items()}
    kit.log("BAGGAGE_DATA " + json.dumps(data))
    kit.log("BAGGAGE done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
