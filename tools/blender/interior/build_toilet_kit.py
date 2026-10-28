"""Build the toilet pieces of the interior kit, one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_toilet_kit.py' [-- piece ...]

Pieces (decision toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 1:
a toilet room is furnished with stall pieces and a sink; each stall is one use slot a
passenger walks into, uses for a dwell, and leaves):
- toilet_stall (1x2, one cell wide, two deep, the door at the front). One cell deep
  cannot hold a seated passenger (0.73 m behind the root, 0.26 m in front, a door).
  The side partitions reach |x| 0.495, past the usual 0.08 m inset but inside the
  cell (as the security arch does, SIDE_LIMITS), so the 2 m Toon passengers, whose
  hands swing out to 0.43 m from the centre line when they walk, clear them. Two
  stalls side by side leave 1 cm between their partitions; against a side wall the
  partition sits inside the wall panel. Front and back keep the inset.
  The door is two half-leaves (Door_Leaf_Stall_L and _R, hinge empties at the front
  pilasters), closed at rest, each opening 90 degrees INWARD to lie along its side.
  A full-width leaf would sweep through a seated or standing occupant, and an outward
  one through the approach cell and the aisle. The hinges sit at |x| 0.43 so an open
  leaf stays out of a side wall (its in-cell face is at 0.44); between open leaves
  there is 0.845 m, so a walker's hand brushes them by about 7.5 mm.
  The headrail's underside is at 2.18 m, above the characters.
  Mount_Use is the seated root (rear cell centre plus SIT_FORWARD toward the door),
  facing out; the toilet is shaped from the sit contract (build_services_kit.py).
  Mount_Approach is the cell in front, facing the stall. Mount_Turn (0.40 m in front
  of the use root, facing the toilet) is where a walker coming in stops and turns
  round: walking on to the use root facing the toilet puts the stride into the bowl.
  The sequence approach -> turn -> step back onto Mount_Use is measured by
  render_toilet_plates.py (stage walk); the game lane owns the choreography.
- toilet_sink (1x1): a vanity with a vessel basin, tap, soap and a mirror. Mount_Use is
  where a passenger stands at it (in the front cell, close to the counter; the plates
  measure it for both characters), Mount_Approach the front cell's centre.

The pieces use build_interior_kit.py's helpers, conventions and checks (origin at the
footprint centre on the floor, front Godot +Z, every face on a measured Toon atlas
swatch, the written file re-read and checked). register() adds the swatches, pieces and
required nodes to the kit's tables; the kit's main() builds, exports and verifies them;
check_written() then re-reads each written file: mounts, per-side extents, and the
stall door's hinges and sweep. It never calls another kit's register() and never adds
to kit.NODE_TRANSLATIONS (Mount_Use and Mount_Approach differ per piece).

Mounts are Mount_* empties in the piece's own frame (Godot axes, metres), unit scale,
upright; a mount is where a passenger's ROOT goes (feet on the floor) and its +Z is the
way the passenger faces.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402  (helpers only; act.register() is never called)
import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_carry_on_kit as carry  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_security_kit as sec  # noqa: E402
import build_services_kit as svc  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "toilet-kit", "toilet_kit.blend")

SEAT_TOP = cafe.SEAT_TOP  # 0.53, the sit clips' seat contact height
SIT_FORWARD = svc.SIT_FORWARD  # 0.45
INSET = 0.08
HALF_IN = 0.5 - INSET  # 0.42

# The stall (Godot metres). Partitions and pilasters reach STALL_OUTER on +-x.
STALL_OUTER = 0.495
PARTITION_IN = 0.475
PILASTER_IN = 0.445
FRONT_Z = 1.0 - INSET  # 0.92, the pilasters' front face
BACK_Z = -(1.0 - INSET)  # -0.92, the back panel's back face
PILASTER_Z = (0.86, 0.90)
PARTITION_Y = (0.15, 2.00)
RAIL_Y = (2.18, 2.22)
HINGE_X = 0.43
HINGE_Z = 0.89
LEAF_W = 0.425  # each leaf; a 10 mm seam between the two
LEAF_T = 0.015
LEAF_Y = (0.15, 1.90)
KNUCKLE_R = 0.009
KNUCKLE_Y = ((0.30, 0.40), (1.60, 1.70))
DOOR_OPEN_DEG = {"L": 90.0, "R": -90.0}  # about Godot +Y: the free edge swings to -Z
SWEEP_MIN = 0.45  # the moving leaf stays this far (horizontally) from the use root
USE_ROOT_Z = -0.5 + SIT_FORWARD  # -0.05: the rear cell's centre plus SIT_FORWARD
# Where a walker coming in from Mount_Approach stops and turns round: walking on to
# the use root facing the toilet puts the stride into the bowl (render_toilet_plates
# measures the walk to here, the turn, and the step back onto the root).
TURN_Z = USE_ROOT_Z + 0.40

# The sink. SINK_USE_Z is measured by render_toilet_plates.py (stage sink): the idle
# body of both characters 0.01-0.06 m clear of the nearest sink part.
SINK_TOP = 0.90
SINK_USE_Z = 0.65

# Swatches copied from the activities kit (the same measured cells).
TOILET_PALETTE = {k: act.ACTIVITIES_PALETTE[k] for k in ("teal", "kid_green", "cream")}

# piece -> footprint (cells x by z), mounts {name: (kind, Godot position, yaw in
# degrees)}, and the per-side limits of the written mesh. Yaw 0 faces Godot +Z.
TOILET = {
    "toilet_stall": {
        "footprint": (1, 2),
        "mounts": {
            "Mount_Use": ("sit_root", (0.0, 0.0, USE_ROOT_Z), 0.0),
            "Mount_Turn": ("turn", (0.0, 0.0, TURN_Z), 180.0),
            "Mount_Approach": ("approach", (0.0, 0.0, 1.5), 180.0),
        },
        "sides": {"+x": STALL_OUTER, "-x": STALL_OUTER, "+z": FRONT_Z, "-z": -BACK_Z},
    },
    "toilet_sink": {
        "footprint": (1, 1),
        "mounts": {
            "Mount_Use": ("use", (0.0, 0.0, SINK_USE_Z), 180.0),
            "Mount_Approach": ("approach", (0.0, 0.0, 1.0), 180.0),
        },
        "sides": {"+x": HALF_IN, "-x": HALF_IN, "+z": HALF_IN, "-z": HALF_IN},
    },
}


# ---------------------------------------------------------------- geometry
# Blender frame: x = Godot x, -y = Godot +Z (the front), z = up. gbox takes Godot ranges.


def gbox(name, xr, yr, zr, pal, parent, c, bevel=0.0):
    """A box over Godot ranges x, y (up) and z."""
    return cafe.tbox(name, (xr[0], -zr[1], yr[0]), (xr[1], -zr[0], yr[1]), pal, parent, c, bevel=bevel)


def gcone(name, gx, gz, y0, y1, r0, r1, pal, parent, c, segs=12):
    return cafe.cone(name, gx, -gz, y0, y1, r0, r1, pal, parent, c, segs=segs)


def oval(name, gx, gz, y0, y1, rx, rz, pal, parent, c, segs=12):
    """An upright oval slab, Godot radii rx and rz; the scale is baked into the mesh."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=rz, radius2=rz, depth=y1 - y0)
    bmesh.ops.scale(bm, vec=Vector((rx / rz, 1.0, 1.0)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((gx, -gz, (y0 + y1) / 2.0)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def add_mounts(piece, root, c):
    for name, (_kind, (gx, gy, gz), yaw) in TOILET[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


# ---------------------------------------------------------------- pieces


def stall_leaf(side, root, c):
    """A hinge empty at the front pilaster; the leaf in hinge-local Godot terms runs
    toward the seam (+x for L, -x for R), 15 mm thick, centred on the hinge line."""
    s = -1.0 if side == "L" else 1.0
    hinge = bpy.data.objects.new("Door_Leaf_Stall_" + side, None)
    c.objects.link(hinge)
    hinge.parent = root
    hinge.empty_display_size = 0.2
    hinge.location = (s * HINGE_X, -HINGE_Z, 0.0)
    x0, x1 = sorted((0.0, -s * LEAF_W))
    t = LEAF_T / 2.0
    gbox("Door_Leaf_Stall_%s_Panel" % side, (x0, x1), LEAF_Y, (-t, t), "blue", hinge, c)
    # Two hinge knuckles round the axis; fixed brackets on the pilaster meet them.
    for k, (y0, y1) in enumerate(KNUCKLE_Y):
        kit.cyl("Door_Leaf_Stall_%s_Knuckle_%d" % (side, k), 0.0, 0.0, y0, y1, KNUCKLE_R, "metal", hinge, c)


def hinge_brackets(side):
    """Godot boxes (x, y, z ranges) of the fixed brackets from the pilaster's inner face
    to the knuckles, on the outward side of the hinge axis where the leaf never goes."""
    s = -1.0 if side == "L" else 1.0
    xr = tuple(sorted((s * (HINGE_X + KNUCKLE_R), s * PILASTER_IN)))
    return [(xr, y, (HINGE_Z - 0.005, HINGE_Z + 0.005)) for y in KNUCKLE_Y]


def build_toilet_stall(root, c):
    o, p = STALL_OUTER, PARTITION_IN
    for side, s in (("L", -1.0), ("R", 1.0)):
        xr = tuple(sorted((s * p, s * o)))
        gbox("Stall_Partition_" + side, xr, PARTITION_Y, (BACK_Z + 0.02, PILASTER_Z[0]), "teal", root, c)
        xr = tuple(sorted((s * PILASTER_IN, s * o)))
        gbox("Stall_Pilaster_" + side, xr, (0.0, RAIL_Y[0]), PILASTER_Z, "metal", root, c)
        for k, (bx, by, bz) in enumerate(hinge_brackets(side)):
            gbox("Stall_Hinge_%s%d" % (side, k), bx, by, bz, "metal", root, c)
        stall_leaf(side, root, c)
    gbox("Stall_Headrail", (-o, o), RAIL_Y, PILASTER_Z, "metal", root, c)
    gbox("Stall_Back", (-o, o), (0.0, PARTITION_Y[1]), (BACK_Z, BACK_Z + 0.02), "teal", root, c)
    # The toilet, placed from the seated root (b = metres behind it): the seat runs b
    # 0.22-0.62 at the sit contract's 0.53 m, the bowl below it keeps behind b 0.28
    # (heels reach 0.245), the slim cistern starts at b 0.75 (the seated back reaches
    # 0.73) and stands on the back panel.
    rz = USE_ROOT_Z
    oval("Toilet_Seat_0", 0.0, rz - 0.42, SEAT_TOP - 0.08, SEAT_TOP, 0.18, 0.20, "white", root, c)
    gcone("Toilet_Bowl", 0.0, rz - 0.45, 0.0, SEAT_TOP - 0.08, 0.13, 0.17, "white", root, c)
    gbox("Toilet_Neck", (-0.07, 0.07), (0.28, SEAT_TOP - 0.10), (rz - 0.75, rz - 0.58), "white", root, c)
    gbox("Toilet_Cistern", (-0.20, 0.20), (0.40, 0.95), (rz - 0.85, rz - 0.75), "white", root, c, bevel=0.01)
    gbox("Toilet_Flush", (-0.06, 0.06), (0.95, 0.965), (rz - 0.83, rz - 0.77), "metal", root, c)
    add_mounts("toilet_stall", root, c)


def build_toilet_sink(root, c):
    h = HALF_IN
    # A deep toe recess (0.15 m under the cabinet front): standing feet reach 0.35 m
    # in front of the root, the body above them only 0.14-0.21 m.
    gbox("Sink_ToeKick", (-0.40, 0.40), (0.0, 0.12), (-0.40, 0.25), "dark", root, c)
    gbox("Sink_Cabinet", (-h, h), (0.12, SINK_TOP - 0.04), (-h, 0.40), "cream", root, c)
    gbox("Sink_Cabinet_Seam", (-0.005, 0.005), (0.18, SINK_TOP - 0.10), (0.40, 0.405), "dark", root, c)
    for k, x in enumerate((-0.06, 0.06)):
        gbox("Sink_Knob_%d" % k, (x - 0.015, x + 0.015), (0.66, 0.70), (0.40, 0.415), "metal", root, c)
    gbox("Sink_Top", (-h, h), (SINK_TOP - 0.04, SINK_TOP), (-h, h), "top", root, c, bevel=0.012)
    # Vessel basin at the front of the top, its bowl a darker disc.
    gcone("Sink_Basin", 0.0, 0.18, SINK_TOP, SINK_TOP + 0.12, 0.12, 0.17, "white", root, c)
    kit.cyl("Sink_Basin_Bowl", 0.0, -0.18, SINK_TOP + 0.12, SINK_TOP + 0.125, 0.145, "metal", root, c, segs=12)
    # Tap behind the basin, its spout over the bowl.
    kit.cyl("Sink_Tap_Riser", 0.0, 0.04, SINK_TOP, SINK_TOP + 0.26, 0.02, "metal", root, c)
    gbox("Sink_Tap_Spout", (-0.015, 0.015), (SINK_TOP + 0.23, SINK_TOP + 0.26), (-0.04, 0.10), "metal", root, c)
    gbox("Sink_Tap_Lever", (-0.01, 0.01), (SINK_TOP + 0.26, SINK_TOP + 0.30), (-0.08, -0.02), "metal", root, c)
    gbox("Sink_Soap", (0.26, 0.32), (SINK_TOP, SINK_TOP + 0.14), (-0.30, -0.22), "kid_green", root, c, bevel=0.008)
    # Splashback with a framed mirror on its front face.
    gbox("Sink_Splash", (-h, h), (SINK_TOP, 1.95), (-h, -0.38), "white", root, c)
    gbox("Sink_Mirror_Frame", (-0.36, 0.36), (1.12, 1.88), (-0.38, -0.37), "trim", root, c)
    gbox("Sink_Mirror", (-0.33, 0.33), (1.15, 1.85), (-0.37, -0.365), "blue", root, c)
    add_mounts("toilet_sink", root, c)


# ---------------------------------------------------------------- register + checks

# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {
    "toilet_stall": (build_toilet_stall, (1, 2), (-STALL_OUTER, -PILASTER_Z[1], 0.0),
                     (STALL_OUTER, -BACK_Z, RAIL_Y[1])),
    "toilet_sink": (build_toilet_sink, (1, 1), (-HALF_IN, -HALF_IN, 0.0), (HALF_IN, HALF_IN, 1.95)),
}
EXTRA_NODES = {p: sorted(TOILET[p]["mounts"]) for p in TOILET}
EXTRA_NODES["toilet_stall"] = sorted(EXTRA_NODES["toilet_stall"] + [
    "Door_Leaf_Stall_L", "Door_Leaf_Stall_L_Mesh", "Door_Leaf_Stall_R", "Door_Leaf_Stall_R_Mesh"])


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside this kit, a name another kit owns, a
    node name already in kit.NODE_TRANSLATIONS, or an existing destination .glb that
    is not this builder's piece."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the toilet kit: %s" % bad)
    others = (set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES) | set(bag.PIECES)
              | set(sec.PIECES) | set(carry.PIECES))
    taken = sorted(others & set(PIECES))
    if taken:
        kit.fail("toilet names already owned by another kit: %s" % taken)
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
    """Add the toilet swatches, pieces and required nodes to the kit."""
    kit.PALETTE.update(TOILET_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_mounts(piece, js):
    """Every mount a unit-scale, upright child of the root at its position and facing."""
    nodes = js.get("nodes", [])
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
    root = nodes[by_name[kit.piece_title(piece) + "_ROOT"]]
    mounts = TOILET[piece]["mounts"]
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
                "want_facing=(%.3f, %.3f, %.3f) up=(%.3f, %.3f, %.3f)"
                % (piece, name, kind, child, t[0], t[1], t[2], facing.x, facing.y, facing.z,
                   want.x, want.y, want.z, up.x, up.y, up.z))
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
    limits = TOILET[piece]["sides"]
    parts = []
    for side in ("+x", "-x", "+z", "-z"):
        parts.append("%s=%.4f/%.3f" % (side, ext[side], limits[side]))
        if ext[side] > limits[side] + 1e-4:
            kit.fail("%s: written mesh reaches %.4f on %s, limit %.3f" % (piece, ext[side], side, limits[side]))
    min_y = min(p.y for p in pts)
    kit.log("SIDES %s %s min_y=%.4f" % (piece, " ".join(parts), min_y))
    if min_y < -1e-4:
        kit.fail("%s: mesh below the floor (%.4f)" % (piece, min_y))


def turned_from(rest, hp, deg):
    """A hinge world matrix `rest` turned `deg` about Godot +Y (Blender +Z) through hp."""
    return Matrix.Translation(hp) @ Matrix.Rotation(math.radians(deg), 4, "Z") @ Matrix.Translation(-hp) @ rest


def leaf_polys(leaf):
    bpy.context.view_layer.update()
    mw = leaf.matrix_world
    return [[mw @ leaf.data.vertices[i].co for i in p.vertices] for p in leaf.data.polygons]


def check_doors(objs):
    """The re-imported stall door. Per leaf: the hinge empty where it should be with its
    mesh a child; turned to open, every vertex keeps its height and distance from the
    hinge axis, the free edge swings to -Z by about the leaf width, and the open leaf
    stays inside |x| 0.44 (a side wall's face). Through the whole swing (0-90 degrees,
    5-degree steps) no leaf face enters a pilaster, partition or hinge bracket (each a
    box whose corners are written vertices, each with a slicing control), and the
    bound hinge-to-root distance minus the leaf's largest radius from
    the hinge axis keeps the moving leaf SWEEP_MIN from the use root at every angle."""
    by = {o.name: o for o in objs}
    root_g = TOILET["toilet_stall"]["mounts"]["Mount_Use"][1]
    root_b = Vector((root_g[0], -root_g[2]))
    static = {}
    for side, s in (("L", -1.0), ("R", 1.0)):
        xr = sorted((s * PILASTER_IN, s * STALL_OUTER))
        static["pilaster_" + side] = (Vector((xr[0], -PILASTER_Z[1], 0.0)), Vector((xr[1], -PILASTER_Z[0], RAIL_Y[0])))
        xr = sorted((s * PARTITION_IN, s * STALL_OUTER))
        static["partition_" + side] = (Vector((xr[0], -PILASTER_Z[0], PARTITION_Y[0])),
                                       Vector((xr[1], -(BACK_Z + 0.02), PARTITION_Y[1])))
        for k, (bx, by_, bz) in enumerate(hinge_brackets(side)):
            static["hinge_%s%d" % (side, k)] = (Vector((bx[0], -bz[1], by_[0])), Vector((bx[1], -bz[0], by_[1])))
    # The obstacle boxes are the written mesh's: every box corner is a vertex of the
    # re-imported body, so a later edit to the builder cannot leave them stale.
    body = by.get("ToiletStall_Body")
    bverts = [body.matrix_world @ v.co for v in body.data.vertices] if body else []
    for name, (lo, hi) in static.items():
        corners = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
        missing = sum(1 for q in corners if not any((q - v).length < 1e-4 for v in bverts))
        if missing:
            kit.fail("toilet_stall: obstacle %s has %d corners that are not written vertices" % (name, missing))
    kit.log("DOOR obstacles=%d all_corners_written=%s" % (len(static), not any(
        "obstacle" in f for f in kit.FAILS)))
    for name, (lo, hi) in static.items():
        c0 = (lo + hi) / 2.0
        reach = (hi - lo).length * 2.0
        control = [c0 + Vector((reach, 0.0, 0.0)), c0 + Vector((-reach, reach, 0.0)), c0 + Vector((-reach, -reach, 0.0))]
        if not svc.clip_to_box(control, lo, hi, 1e-4):
            kit.fail("toilet_stall: the slicing control missed %s" % name)
    for side in ("L", "R"):
        hinge, leaf = by.get("Door_Leaf_Stall_" + side), by.get("Door_Leaf_Stall_%s_Mesh" % side)
        if hinge is None or leaf is None or leaf.parent is not hinge:
            kit.fail("toilet_stall: hinge %s leaf %s parent %s" % (hinge, leaf, getattr(leaf, "parent", None)))
            continue
        hp = hinge.matrix_world.translation.copy()
        g = (hp.x, hp.z, -hp.y)
        want = ((-1.0 if side == "L" else 1.0) * HINGE_X, 0.0, HINGE_Z)
        if max(abs(a - b) for a, b in zip(g, want)) > 1e-4:
            kit.fail("toilet_stall: hinge %s at %s, expected %s" % (side, g, want))
        rest = hinge.matrix_world.copy()
        closed = [v for p in leaf_polys(leaf) for v in p]
        radius = max(math.hypot(v.x - hp.x, v.y - hp.y) for v in closed)
        bound = (root_b - Vector((hp.x, hp.y))).length - radius
        far_i = max(range(len(closed)), key=lambda i: abs(closed[i].x - hp.x))
        worst_clash, rigid = 0, 0.0
        opened = closed
        for k in range(0, 19):
            deg = DOOR_OPEN_DEG[side] * k / 18.0
            hinge.matrix_world = turned_from(rest, hp, deg)
            polys = leaf_polys(leaf)
            verts = [v for p in polys for v in p]
            rigid = max(rigid, max(max(abs(math.hypot(a.x - hp.x, a.y - hp.y) - math.hypot(b.x - hp.x, b.y - hp.y)),
                                       abs(a.z - b.z)) for a, b in zip(closed, verts)))
            for name, (lo, hi) in static.items():
                worst_clash += sum(1 for p in polys if svc.clip_to_box(p, lo, hi, 1e-4))
            opened = verts
        hinge.matrix_world = rest
        bpy.context.view_layer.update()
        f0, f1 = closed[far_i], opened[far_i]
        swing = (-f1.y) - (-f0.y)  # Godot z change of the free edge (Blender -y)
        open_x = (min(v.x for v in opened), max(v.x for v in opened))
        kit.log("DOOR %s hinge_godot=(%.3f, %.3f, %.3f) leaf_radius=%.4f root_distance=%.4f sweep_bound=%.4f "
                "rigid_err=%.6f free_edge_godot_z %.3f -> %.3f (swing %.3f) open_x=[%.4f, %.4f] "
                "faces_crossing_an_obstacle_over_19_angles=%d"
                % (side, g[0], g[1], g[2], radius, (root_b - Vector((hp.x, hp.y))).length, bound, rigid,
                   -f0.y, -f1.y, swing, open_x[0], open_x[1], worst_clash))
        if rigid > 1e-4:
            kit.fail("toilet_stall: leaf %s does not turn rigidly about its hinge (%.5f m)" % (side, rigid))
        if swing > -(LEAF_W - 0.02) or abs(f1.x - hp.x) > 0.02:
            kit.fail("toilet_stall: leaf %s free edge did not swing in to -Z" % side)
        if max(abs(open_x[0]), abs(open_x[1])) > 0.44 - 1e-4:
            kit.fail("toilet_stall: open leaf %s reaches |x| %.4f, into a side wall" % (side, max(map(abs, open_x))))
        if worst_clash:
            kit.fail("toilet_stall: leaf %s crosses a pilaster, partition or bracket during its swing" % side)
        if bound < SWEEP_MIN:
            kit.fail("toilet_stall: leaf %s sweeps within %.3f m of the use root" % (side, bound))


def import_written(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    return list(bpy.context.scene.objects)


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        check_mounts(piece, js)
        objs = import_written(out)
        check_sides(piece, objs)
        if piece == "toilet_stall":
            check_doors(objs)
    data = {p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in TOILET.items()}
    kit.log("TOILET_DATA " + json.dumps(data))
    kit.log("TOILET done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
