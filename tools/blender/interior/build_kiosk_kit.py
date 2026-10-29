"""Build the kiosk shop pieces and the boredom screen stand, one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_kiosk_kit.py' [-- piece ...]

Pieces (Boredom 5/5; decision boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh
for the kiosk, boredom-screens-are-floor-standing-screen-stands-placed-like and
screen-coverage-as-built-a-5-deep-fan-3-then-5-wide-in-front for the screen):
- kiosk_counter (2x1): the till on the -x cell's front edge; Mount_Till is the cell in
  front of it (BuildCatalog's interaction cell), facing the counter. A newspaper stack
  behind the till, a stepped snack rack on the +x cell, and a sign board with a short
  striped canopy over the +x half only, so the till stays in view from behind (the cafe
  counter keeps its menu board to one half for the same reason). Mount_Staff behind the
  -x cell is a reference point only; nothing staffs a kiosk yet.
- kiosk_display (2x1): a three-tier display stand, magazines, snack boxes and souvenirs
  (a plush bear and a toy plane) in two sections split by a low divider, one section per
  browse slot. Mount_Browse_0 and _1 are the cells in front of the -x and +x cells
  (ShopLayout's browse slots, index in footprint order), facing the stand.
- screen_stand (1x1): a widescreen TV on one pole over a foot plate that reaches further
  forward than back, so the facing reads from above. The picture (sky, hills, sun, cloud
  on the lights atlas) is the separate Screen_Face node, as on info_screen, so a later
  viewport texture can replace it. The back is the dark housing with a metal mount plate:
  a picture on the back would suggest coverage behind it. No mounts.

The existing kit pieces were checked first: kiosk.glb is a 1x1 self-service ticket
machine and pharmacy_shelf.glb a 2x1 shelf branded with a green cross, so neither reads
as a kiosk shop.

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
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402  (helpers only; act.register() is never called)
import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402  (helpers only; cafe.register() is never called)
import build_carry_on_kit as carry  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_security_kit as sec  # noqa: E402
import build_services_kit as svc  # noqa: E402
import build_toilet_kit as toilet  # noqa: E402  (helpers only; toilet.register() is never called)

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "kiosk-kit", "kiosk_kit.blend")

INSET = 0.08
HALF_IN = 0.5 - INSET  # 0.42
WIDE_IN = 1.0 - INSET  # 0.92, the x limit of a 2x1 piece

# Swatches: product and stripe colours from the activities kit's measured cells, and
# lights-atlas cells for the TV picture (unshaded in Godot, like the info screen).
KIOSK_PALETTE = {k: act.ACTIVITIES_PALETTE[k] for k in
                 ("red", "pink", "cream", "gold", "sun", "kid_blue", "kid_green", "orange", "purple", "teal")}
KIOSK_PALETTE.update({
    "lit_gold": ("TP_Atlas_Lights_1A_D", 5, 0, 0.50, 0.0),
    "lit_lime": ("TP_Atlas_Lights_1A_D", 9, 1, 0.50, 0.0),
})

# piece -> footprint (cells x by z), mounts {name: (kind, Godot position, yaw in
# degrees)}, and the per-side limits of the written mesh. Yaw 0 faces Godot +Z.
KIOSK = {
    "kiosk_counter": {
        "footprint": (2, 1),
        "mounts": {
            "Mount_Till": ("till", (-0.5, 0.0, 1.0), 180.0),
            "Mount_Staff": ("staff", (-0.5, 0.0, -1.0), 0.0),
        },
        "sides": {"+x": WIDE_IN, "-x": WIDE_IN, "+z": HALF_IN, "-z": HALF_IN},
    },
    "kiosk_display": {
        "footprint": (2, 1),
        "mounts": {
            "Mount_Browse_0": ("browse", (-0.5, 0.0, 1.0), 180.0),
            "Mount_Browse_1": ("browse", (0.5, 0.0, 1.0), 180.0),
        },
        "sides": {"+x": WIDE_IN, "-x": WIDE_IN, "+z": HALF_IN, "-z": HALF_IN},
    },
    "screen_stand": {
        "footprint": (1, 1),
        "mounts": {},
        "sides": {"+x": HALF_IN, "-x": HALF_IN, "+z": HALF_IN, "-z": HALF_IN},
    },
}

STRIPES = ("red", "cream")

# The till screen (Godot ranges, before the lean): render_kiosk_plates.py samples its
# faces to prove the till is in view.
TILL = {"x": (-0.67, -0.47), "y": (1.03, 1.20), "z": (0.13, 0.16), "lean": 15.0, "pivot": (-0.57, 1.03, 0.16)}


# ---------------------------------------------------------------- geometry
# Blender frame: x = Godot x, -y = Godot +Z (the front), z = up. These take Godot ranges.


def gbox(name, xr, yr, zr, pal, parent, c, bevel=0.0, lean=0.0, pivot=None):
    """A box over Godot ranges x, y (up) and z, leaned `lean` degrees back (its top
    toward Godot -Z) about the Godot point `pivot` (default its own centre)."""
    if lean:
        gp = pivot if pivot is not None else ((xr[0] + xr[1]) / 2, (yr[0] + yr[1]) / 2, (zr[0] + zr[1]) / 2)
        bp = (gp[0], -gp[2], gp[1])
        return cafe.tbox(name, (xr[0], -zr[1], yr[0]), (xr[1], -zr[0], yr[1]), pal, parent, c,
                         axis="X", deg=-lean, pivot=bp, bevel=bevel)
    return toilet.gbox(name, xr, yr, zr, pal, parent, c, bevel=bevel)


def disc(name, gx, gy, r, z0, z1, pal, parent, c, clip=None, segs=16):
    """A flat disc facing Godot +Z between depths z0 and z1, centred at (gx, gy),
    optionally clipped to the Godot rectangle clip = (x0, x1, y0, y1)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=z1 - z0)
    # The cone's axis is Blender Z; turn it onto Blender -Y (Godot +Z).
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=Vector((gx, -(z0 + z1) / 2.0, gy)), verts=bm.verts)
    if clip is not None:
        x0, x1, y0, y1 = clip
        for co, no in (((x0, 0, 0), (-1, 0, 0)), ((x1, 0, 0), (1, 0, 0)),
                       ((0, 0, y0), (0, 0, -1)), ((0, 0, y1), (0, 0, 1))):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no), clear_outer=True)
            edges = [e for e in bm.edges if e.is_boundary]
            if edges:
                bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    return kit._finish_mesh(name, bm, pal, parent, c)


def add_mounts(piece, root, c):
    for name, (_kind, (gx, gy, gz), yaw) in KIOSK[piece]["mounts"].items():
        ob = bpy.data.objects.new(name, None)
        c.objects.link(ob)
        ob.parent = root
        ob.empty_display_type = "SINGLE_ARROW"
        ob.empty_display_size = 0.3
        # Godot (x, y, z) is Blender (x, -z, y); a Blender Z turn is a Godot Y turn.
        ob.location = (gx, -gz, gy)
        ob.rotation_euler = (0.0, 0.0, math.radians(yaw))


def stripes(prefix, x0, x1, n, yr, zr, parent, c, lean=0.0, pivot=None):
    """n alternating red and cream bands across x0..x1."""
    w = (x1 - x0) / n
    for i in range(n):
        gbox("%s_%d" % (prefix, i), (x0 + i * w, x0 + (i + 1) * w), yr, zr, STRIPES[i % 2], parent, c,
             lean=lean, pivot=pivot)


# ---------------------------------------------------------------- pieces


def build_kiosk_counter(root, c):
    gbox("Counter_ToeKick", (-0.88, 0.88), (0.0, 0.08), (-0.34, 0.38), "dark", root, c)
    gbox("Counter_Body", (-0.90, 0.90), (0.08, 0.92), (-0.38, 0.40), "cream", root, c)
    gbox("Counter_Band", (-0.86, 0.86), (0.62, 0.76), (0.40, 0.415), "red", root, c)
    gbox("Counter_Top", (-0.92, 0.92), (0.92, 0.98), (-0.42, 0.42), "wood", root, c, bevel=0.015)
    # The till on the -x cell's front edge, its screen turned to the customer.
    # The screen stands on the base, leaned back about its front-bottom edge so that
    # edge rests on the base top and the back edge sinks into it.
    gbox("Till_Base", (-0.70, -0.44), (0.98, 1.03), (0.10, 0.30), "dark", root, c, bevel=0.008)
    t = TILL
    gbox("Till_Screen", t["x"], t["y"], t["z"], "dark", root, c, lean=t["lean"], pivot=t["pivot"])
    gbox("Till_Screen_Face", (-0.65, -0.49), (1.05, 1.18), (t["z"][1], t["z"][1] + 0.005), "screen_sky", root, c,
         lean=t["lean"], pivot=t["pivot"])
    gbox("Till_Reader", (-0.38, -0.30), (0.98, 1.06), (0.20, 0.30), "metal", root, c)
    # A newspaper stack behind the till: grey sheets with a red masthead on top.
    gbox("Paper_Stack", (-0.86, -0.46), (0.98, 1.10), (-0.36, -0.08), "white", root, c)
    gbox("Paper_Masthead", (-0.84, -0.48), (1.10, 1.105), (-0.34, -0.26), "red", root, c)
    gbox("Paper_Stack_Top", (-0.82, -0.50), (1.10, 1.115), (-0.24, -0.10), "metal", root, c)
    # The +x cell: a three-step snack rack with boxes and bars on each step.
    steps = (((0.98, 1.04), (-0.10, 0.36)), ((1.04, 1.16), (-0.26, 0.10)), ((1.16, 1.28), (-0.40, -0.12)))
    pals = ("orange", "kid_blue", "pink", "kid_green", "sun", "purple", "red", "teal")
    n = 0
    for k, (yr, zr) in enumerate(steps):
        gbox("Rack_Step_%d" % k, (0.08, 0.86), yr, zr, "wood" if k % 2 == 0 else "cream", root, c)
        for i in range(4):
            x = 0.13 + i * 0.185
            h = (0.10, 0.07, 0.12, 0.08)[(i + k) % 4]
            z1 = zr[1] - 0.03
            gbox("Snack_%d" % n, (x, x + 0.14), (yr[1], yr[1] + h), (z1 - 0.14, z1), pals[(i + 3 * k) % 8], root, c)
            n += 1
    # The sign and its short striped canopy, over the +x half only, on two back posts.
    for i, x in enumerate((0.10, 0.86)):
        gbox("Sign_Post_%d" % i, (x - 0.02, x + 0.02), (0.98, 1.95), (-0.40, -0.36), "frame", root, c)
    gbox("Sign_Board", (0.08, 0.88), (1.55, 1.85), (-0.40, -0.37), "sun", root, c, bevel=0.01)
    for i, x in enumerate((0.16, 0.36, 0.56)):
        gbox("Sign_Mark_%d" % i, (x, x + 0.14), (1.62, 1.78), (-0.37, -0.365), "red", root, c)
    gbox("Sign_Paper", (0.74, 0.84), (1.62, 1.78), (-0.37, -0.365), "white", root, c)
    stripes("Canopy", 0.06, 0.90, 4, (1.95, 1.99), (-0.42, -0.12), root, c, lean=-18.0, pivot=(0.48, 1.95, -0.42))
    add_mounts("kiosk_counter", root, c)


def plush(name, gx, gy, gz, pal, parent, c):
    """A sitting plush bear: body, head and two ears."""
    cafe.ball(name + "_Body", gx, -gz, gy + 0.07, 0.07, pal, parent, c)
    cafe.ball(name + "_Head", gx, -gz, gy + 0.18, 0.055, pal, parent, c)
    for k, dx in enumerate((-0.04, 0.04)):
        cafe.ball("%s_Ear_%d" % (name, k), gx + dx, -gz, gy + 0.235, 0.02, pal, parent, c)


def toy_plane(name, gx, gy, gz, pal, parent, c):
    """A toy plane on a little stand, nose to +x."""
    gbox(name + "_Stand", (gx - 0.015, gx + 0.015), (gy, gy + 0.08), (gz - 0.015, gz + 0.015), "dark", parent, c)
    gbox(name + "_Body", (gx - 0.14, gx + 0.14), (gy + 0.08, gy + 0.13), (gz - 0.025, gz + 0.025), "white", parent, c)
    gbox(name + "_Wing", (gx - 0.03, gx + 0.04), (gy + 0.095, gy + 0.11), (gz - 0.13, gz + 0.13), pal, parent, c)
    gbox(name + "_Tail", (gx - 0.14, gx - 0.10), (gy + 0.13, gy + 0.20), (gz - 0.008, gz + 0.008), pal, parent, c)


def build_kiosk_display(root, c):
    gbox("Display_Plinth", (-0.90, 0.90), (0.0, 0.08), (-0.40, 0.38), "dark", root, c)
    gbox("Display_Back", (-0.92, 0.92), (0.08, 1.45), (-0.415, -0.36), "cream", root, c)
    gbox("Display_Back_Band", (-0.90, 0.90), (0.95, 1.10), (-0.42, -0.415), "red", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        xr = tuple(sorted((s * 0.88, s * 0.92)))
        gbox("Display_Side_%s_Low" % side, xr, (0.08, 0.43), (-0.36, 0.38), "cream", root, c)
        gbox("Display_Side_%s_High" % side, xr, (0.43, 1.45), (-0.36, 0.18), "cream", root, c)
    tiers = (((0.08, 0.40), 0.36, 0.38), ((0.43, 0.80), 0.16, 0.18), ((0.83, 1.18), -0.04, -0.02))
    for k, (yr, riser_z, board_z) in enumerate(tiers):
        gbox("Tier_Riser_%d" % k, (-0.88, 0.88), yr, (-0.36, riser_z), "cream", root, c)
        gbox("Tier_Board_%d" % k, (-0.88, 0.88), (yr[1], yr[1] + 0.03), (-0.36, board_z), "wood", root, c)
    gbox("Display_Divider", (-0.015, 0.015), (0.43, 1.10), (-0.36, 0.16), "metal", root, c)
    mags = ("red", "kid_blue", "sun", "pink", "teal", "orange")
    snacks = ("orange", "kid_green", "purple", "sun", "red", "kid_blue")
    for sec_i, sx in enumerate((-0.5, 0.5)):
        # Bottom tier: three magazines leaning back on the riser above.
        for i in range(3):
            x = sx - 0.36 + i * 0.25
            gbox("Magazine_%d%d" % (sec_i, i), (x, x + 0.22), (0.43, 0.71), (0.22, 0.24), mags[(i + 3 * sec_i) % 6],
                 root, c, lean=14.0, pivot=(x + 0.11, 0.43, 0.23))
        # Middle tier: three snack boxes.
        for i in range(3):
            x = sx - 0.35 + i * 0.245
            h = (0.20, 0.25, 0.17)[(i + sec_i) % 3]
            gbox("Snack_Box_%d%d" % (sec_i, i), (x, x + 0.19), (0.83, 0.83 + h), (-0.02, 0.13),
                 snacks[(i + 2 * sec_i) % 6], root, c, bevel=0.008)
        # Top tier: a plush bear and a toy plane.
        plush("Plush_%d" % sec_i, sx - 0.20, 1.21, -0.20, ("gold", "pink")[sec_i], root, c)
        toy_plane("Toy_Plane_%d" % sec_i, sx + 0.18, 1.21, -0.20, ("kid_blue", "red")[sec_i], root, c)
    stripes("Header", -0.92, 0.92, 8, (1.45, 1.68), (-0.415, -0.34), root, c)
    add_mounts("kiosk_display", root, c)


SCREEN_X = 0.39
SCREEN_Y = (1.41, 1.85)


def build_screen_stand(root, c):
    gbox("Stand_Foot", (-0.22, 0.22), (0.0, 0.04), (-0.16, 0.30), "dark", root, c, bevel=0.01)
    gbox("Stand_Foot_Accent", (-0.20, 0.20), (0.04, 0.05), (0.22, 0.28), "sun", root, c)
    kit.cyl("Stand_Collar", 0.0, 0.02, 0.04, 0.10, 0.06, "dark", root, c, segs=12)
    kit.cyl("Stand_Pole", 0.0, 0.02, 0.10, 1.42, 0.035, "metal", root, c, segs=12)
    gbox("TV_Mount_Plate", (-0.12, 0.12), (1.48, 1.76), (-0.09, -0.06), "metal", root, c)
    gbox("TV_Housing", (-0.42, 0.42), (1.38, 1.88), (-0.06, 0.02), "dark", root, c, bevel=0.012)
    gbox("TV_Speaker", (-0.30, 0.30), (1.32, 1.37), (-0.05, 0.01), "dark", root, c)
    gbox("TV_Lamp", (0.34, 0.37), (1.385, 1.40), (0.02, 0.024), "lamp_green", root, c)
    # Screen_Face holds the whole picture so a viewport texture can replace it as one node.
    face = bpy.data.objects.new("Screen_Face", None)
    c.objects.link(face)
    face.parent = root
    clip = (-SCREEN_X, SCREEN_X, SCREEN_Y[0], SCREEN_Y[1])
    gbox("Screen_Face_Sky", (-SCREEN_X, SCREEN_X), SCREEN_Y, (0.020, 0.024), "screen_sky", face, c)
    disc("Screen_Face_Sun", 0.22, 1.73, 0.065, 0.024, 0.027, "lit_gold", face, c, clip=clip)
    for i, (x, y, r) in enumerate(((-0.24, 1.75, 0.045), (-0.17, 1.775, 0.06), (-0.10, 1.75, 0.04))):
        z0 = 0.024 + 0.0008 * i
        disc("Screen_Face_Cloud_%d" % i, x, y, r, z0, z0 + 0.003, "text_white", face, c, clip=clip)
    disc("Screen_Face_Hill_0", -0.16, 1.30, 0.30, 0.027, 0.030, "lamp_green", face, c, clip=clip, segs=24)
    disc("Screen_Face_Hill_1", 0.24, 1.28, 0.26, 0.030, 0.033, "lit_lime", face, c, clip=clip, segs=24)


# ---------------------------------------------------------------- register + checks

# piece -> (builder, footprint, expected Blender bounds lo, hi).
PIECES = {
    "kiosk_counter": (build_kiosk_counter, (2, 1), (-WIDE_IN, -0.42, 0.0), (WIDE_IN, 0.42, 1.988)),
    "kiosk_display": (build_kiosk_display, (2, 1), (-WIDE_IN, -0.38, 0.0), (WIDE_IN, 0.42, 1.68)),
    "screen_stand": (build_screen_stand, (1, 1), (-HALF_IN, -0.30, 0.0), (HALF_IN, 0.16, 1.88)),
}
EXTRA_NODES = {p: sorted(KIOSK[p]["mounts"]) for p in KIOSK}
EXTRA_NODES["screen_stand"] = ["Screen_Face", "Screen_Face_Mesh"]


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse before any build: a piece outside this kit, a name another kit owns, a
    node name already in kit.NODE_TRANSLATIONS, or an existing destination .glb that
    is not this builder's piece."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the kiosk kit: %s" % bad)
    others = (set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES) | set(bag.PIECES)
              | set(sec.PIECES) | set(carry.PIECES) | set(toilet.PIECES))
    taken = sorted(others & set(PIECES))
    if taken:
        kit.fail("kiosk names already owned by another kit: %s" % taken)
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
    """Add the kiosk swatches, pieces and required nodes to the kit."""
    kit.PALETTE.update(KIOSK_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)


def check_mounts(piece, js):
    """Every mount a unit-scale, upright child of the root at its position and facing."""
    nodes = js.get("nodes", [])
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
    root = nodes[by_name[kit.piece_title(piece) + "_ROOT"]]
    mounts = KIOSK[piece]["mounts"]
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
    limits = KIOSK[piece]["sides"]
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
    data = {p: {"footprint": s["footprint"], "mounts": s["mounts"]} for p, s in KIOSK.items()}
    kit.log("KIOSK_DATA " + json.dumps(data))
    kit.log("KIOSK done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_written(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
