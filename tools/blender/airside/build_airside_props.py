"""Build the airside props (board 4c08b8e5, Runway R11) and export one .glb each.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\build_airside_props.py' [-- piece ...]

Pieces (written to game/assets/airside/props/<piece>.glb):
- jet_bridge: a fixed telescoping passenger bridge, visual only. One rig serves the
  medium sill (plane 05, 1.59 m) and the large sills (06 at 2.4 m, 07 at 2.9 m) and
  every reach from REACH_MIN to REACH_MAX (see the pose math below).
- pushback_tug: a low conventional tug with a tow bar on a yaw pivot at its front
  hitch; Mount_NoseGear is where the bar's towing head meets the nose gear.
- taxi_sign: a two-panel taxiway sign on short legs: a location panel (yellow letter
  and border on black) and a direction panel (black letter and arrow on yellow). Every
  glyph is its own node, so the wiring shows one letter per panel and one arrow.

The builder reuses tools/blender/interior/build_interior_kit.py: its box and cylinder
helpers, the measured palette atlas swatches (every face on one swatch of
TP_Atlas_1A_D or TP_Atlas_Lights_1A_D; material names exactly the ones
game/assets/toon_post_import.gd binds), its export and its verify_written() re-read
of the WRITTEN file (materials, zero images, node names, world bounds, UVs inside
their swatches). check_rig() then re-reads each written GLB's node tree and checks
every pivot's parent, rest translation and rest rotation against the constants here.

Axes. Every dimension below is in Godot axes (x right, y up, z = the piece's front),
converted once by gb()/gbox(): Blender x = Godot x, Blender y = -Godot z, Blender z =
Godot y. Each piece's origin is on the ground; the bridge's is on its column axis.

Jet bridge rig (all empties export with zero rest rotation):
  JetBridge_ROOT
    JetBridge_Body        column, rotunda drum, roof, fixed-link stub (static)
    Mount_Link            at (0, ROT_FLOOR, -LINK_Z): the stub's back face, floor
                          level, where a link corridor or the terminal wall meets it
    Tunnel_Yaw            at (0, ROT_FLOOR, 0): rotate about Y to aim the tunnel
      Tunnel_Pitch        at (0, 0, HINGE_Z) on the drum face, floor height: rotate
                          about X to slope the tunnel; its mesh is tunnel A
        Tunnel_Slide      at (0, 0, 0): translate along +Z by s in [0, SLIDE_MAX];
                          its mesh is tunnel B, the larger cab-side section
          Drive_Level     at (0, -TUN_B_SINK, DRIVE_Z) under tunnel B: counter-pitch
                          so it stays upright; its mesh is the cross beam and sleeve
            Drive_Foot    at (0, -(ROT_FLOOR - TUN_B_SINK), 0): its origin is the wheel
                          contact; set y so the bogie stands on the ground
          Cab_Level       at (0, 0, CAB_Z), B's outer end on the floor line:
                          counter-pitch so the cab floor is level
            Cab_Yaw       at (0, 0, 0): rotate about Y to face the fuselage; its mesh is
                          the cab, roof and bellows
              Mount_Door  at (0, 0, MOUNT_DOOR_Z): the bellows' front, floor level;
                          the wiring puts it on the aircraft door sill

Pose math (Godot, in the bridge root's frame). Given the door sill point P (the
fuselage skin at the door's middle, sill height) and the horizontal unit normal n
pointing out of the fuselage toward the bridge:
  C   = P + n * MOUNT_DOOR_Z                 (Cab_Yaw origin, C.y = P.y)
  yaw = atan2(C.x, C.z)                      Tunnel_Yaw.rotation.y
  d   = hypot(C.x, C.z) - HINGE_Z            horizontal hinge-to-cab distance
  dh  = C.y - ROT_FLOOR
  th  = atan2(dh, d)                         Tunnel_Pitch.rotation.x = -th
  s   = hypot(d, dh) - CAB_Z                 Tunnel_Slide.position.z = s, 0..SLIDE_MAX
  Cab_Level.rotation.x = th; Drive_Level.rotation.x = th
  Cab_Yaw.rotation.y = atan2(-n.x, -n.z) - yaw
  h   = ROT_FLOOR - TUN_B_SINK * cos(th) + (DRIVE_Z + s) * sin(th)
  Drive_Foot.position.y = -h
A pose with s outside [0, SLIDE_MAX], |th| above PITCH_MAX_DEG or h above DRIVE_H_MAX
(where the drive leg would leave its sleeve) is out of reach.
render_airside_plates.py applies exactly this math and prints the Mount_Door error.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "interior"))
import build_interior_kit as kit  # noqa: E402

kit.OUT_DIR = os.path.join(kit.REPO, "game", "assets", "airside", "props")
BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "airside-props", "airside_props.blend")

# Extra measured swatches: name -> (material, column, row, fraction from the swatch
# top, vertical span). Sampled by tools/blender/out/airside-props/sample.py and
# printed again by report_palette() at every build.
kit.PALETTE.update({
    "sign_yellow": ("TP_Atlas_1A_D", 9, 13, 0.45, 0.0),
    "ink": ("TP_Atlas_1A_D", 3, 15, 0.85, 0.0),
    "concrete": ("TP_Atlas_1A_D", 2, 15, 0.30, 0.0),
    "light_grey": ("TP_Atlas_1A_D", 12, 11, 0.20, 0.0),
    "window": ("TP_Atlas_1A_D", 13, 12, 0.55, 0.0),
    "red": ("TP_Atlas_1A_D", 31, 0, 0.50, 0.0),
    "tug_yellow": ("TP_Atlas_1A_D", 1, 13, 0.45, 0.0),
})

# ---------------------------------------------------------------- jet bridge
ROT_FLOOR = 2.75        # rotunda and tunnel floor line at rest, above the ground
DRUM_R = 1.70
HINGE_Z = DRUM_R        # the pitch hinge sits on the drum face
TUN_A_LEN = 6.5         # tunnel A, hinge-local z from -0.6 (sunk in the drum) to 6.5
TUN_A_HALF_W = 1.20
TUN_A_H = 2.50
TUN_B_LEN = 6.0         # tunnel B (larger, slides over A), rest z 0.8 .. 6.8
TUN_B_HALF_W = 1.35
TUN_B_H = 2.75
TUN_B_SINK = 0.30       # B's floor slab underside below the floor line
CAB_Z = TUN_A_LEN + 0.3  # B's outer end = the cab pivot at rest
SLIDE_MAX = 5.0
DRIVE_H_MAX = 2.90       # the leg top (foot + 2.25) stays 0.10 m inside the sleeve (bottom -0.75)
DRIVE_Z = CAB_Z - 1.6
CAB_HALF = 1.50
CAB_TOP = 2.85
BELLOWS_D = 0.60
MOUNT_DOOR_Z = CAB_HALF + BELLOWS_D
PITCH_MAX_DEG = 9.0
REACH_MIN = HINGE_Z + CAB_Z
REACH_MAX = REACH_MIN + SLIDE_MAX
BOGIE_TOP = 0.60
LINK_Z = DRUM_R + 0.9   # the stub's back face behind the column axis

# ---------------------------------------------------------------- pushback tug
TUG_HALF_L = 3.0
TUG_HALF_W = 1.45
HITCH = (0.0, 0.50, TUG_HALF_L + 0.10)
BAR_LEN = 4.0           # pivot to the towing head's front face
BAR_WHEEL_Z = 1.5
BAR_WHEEL_R = 0.16

# ---------------------------------------------------------------- taxi sign
SIGN_HALF_W = 1.20
SIGN_Y = (0.30, 1.12)   # housing bottom and top
FACE_Y = (0.35, 1.07)
FACE_Z = 0.12           # housing front face; panel faces sit on it
LOC_X = (-1.15, -0.35)
DIR_X = (-0.30, 1.15)
LEGEND_H = 0.46         # FAA size 3: 18 in legend on a 30 in panel
LEGEND_W = 0.34
STROKE = 0.075
ARROW_W = 0.42
LETTERS = "ABCDE"

PIVOTS = {}  # piece -> {node: (parent, godot translation)} for check_rig()


def gb(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


def gbox(name, lo, hi, pal, parent, c, bevel=0.0):
    """An axis box between Godot corners lo and hi."""
    return kit.box(name, (lo[0], -hi[2], lo[1]), (hi[0], -lo[2], hi[1]), pal, parent, c, bevel=bevel)


def gcyl_y(name, x, z, y0, y1, r, pal, parent, c, segs=12):
    """An upright cylinder on Godot (x, z) from height y0 to y1."""
    return kit.cyl(name, x, -z, y0, y1, r, pal, parent, c, segs=segs)


def gcyl_x(name, x0, x1, y, z, r, pal, parent, c, segs=12):
    """A cylinder along Godot X (a wheel or an axle) centred on height y, depth z."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=x1 - x0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    bmesh.ops.translate(bm, vec=Vector(gb((x0 + x1) / 2.0, y, z)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def prism(name, quad, z0, z1, pal, parent, c, ox=0.0, oy=0.0):
    """A convex 2D polygon in the Godot XY plane (offset ox, oy) extruded from z0 to z1."""
    bm = bmesh.new()
    front = [bm.verts.new(gb(ox + u, oy + v, z1)) for u, v in quad]
    back = [bm.verts.new(gb(ox + u, oy + v, z0)) for u, v in quad]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(quad)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def empty(name, parent, c, at):
    ob = bpy.data.objects.new(name, None)
    c.objects.link(ob)
    ob.parent = parent
    ob.location = gb(*at)
    ob.empty_display_size = 0.3
    return ob


def pivot(piece, name, parent, c, at):
    PIVOTS.setdefault(piece, {})[name] = (parent.name, at)
    return empty(name, parent, c, at)


# ---------------------------------------------------------------- jet bridge


def build_jet_bridge(root, c):
    p = "jet_bridge"
    # Static: plinth, column, rotunda drum with a window band, roof.
    gbox("Plinth", (-0.7, 0.0, -0.7), (0.7, 0.15, 0.7), "concrete", root, c, bevel=0.03)
    gcyl_y("Column", 0.0, 0.0, 0.15, ROT_FLOOR - 0.25, 0.45, "concrete", root, c)
    gcyl_y("Drum_Floor", 0.0, 0.0, ROT_FLOOR - 0.25, ROT_FLOOR, DRUM_R + 0.05, "metal", root, c)
    gcyl_y("Drum_Wall", 0.0, 0.0, ROT_FLOOR, ROT_FLOOR + 2.35, DRUM_R, "white", root, c)
    gcyl_y("Drum_Windows", 0.0, 0.0, ROT_FLOOR + 1.0, ROT_FLOOR + 1.6, DRUM_R + 0.02, "window", root, c)
    gcyl_y("Drum_Roof", 0.0, 0.0, ROT_FLOOR + 2.35, ROT_FLOOR + 2.55, DRUM_R + 0.15, "light_grey", root, c)
    # The fixed-link stub on the back (Godot -z), toward the terminal; Mount_Link is its
    # back face at floor level, where a link corridor or the terminal wall meets it.
    gbox("Link_Stub", (-1.0, ROT_FLOOR - 0.25, -LINK_Z), (1.0, ROT_FLOOR + 2.4, -DRUM_R + 0.4), "white", root, c,
         bevel=0.03)
    gbox("Link_Band", (-1.02, ROT_FLOOR - 0.25, -LINK_Z - 0.02), (1.02, ROT_FLOOR + 0.05, -DRUM_R + 0.4), "blue",
         root, c)
    pivot(p, "Mount_Link", root, c, (0.0, ROT_FLOOR, -LINK_Z))

    yaw = pivot(p, "Tunnel_Yaw", root, c, (0.0, ROT_FLOOR, 0.0))
    pitch = pivot(p, "Tunnel_Pitch", yaw, c, (0.0, 0.0, HINGE_Z))
    # Tunnel A, hinge-local: starts inside the drum so its corners stay sunk at any yaw.
    w, h = TUN_A_HALF_W, TUN_A_H
    gbox("TunA_Shell", (-w, -0.20, -0.6), (w, h, TUN_A_LEN), "white", pitch, c, bevel=0.04)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * w, sx * (w + 0.02)))
        gbox("TunA_Window_%d" % sx, (x0, 1.0, 0.1), (x1, 1.75, TUN_A_LEN - 0.2), "window", pitch, c)
        gbox("TunA_Band_%d" % sx, (x0, -0.20, -0.3), (x1, 0.12, TUN_A_LEN), "blue", pitch, c)

    slide = pivot(p, "Tunnel_Slide", pitch, c, (0.0, 0.0, 0.0))
    w, h, b0 = TUN_B_HALF_W, TUN_B_H, CAB_Z - TUN_B_LEN
    gbox("TunB_Shell", (-w, -TUN_B_SINK, b0), (w, h, CAB_Z), "white", slide, c, bevel=0.04)
    gbox("TunB_Mouth", (-w - 0.03, -TUN_B_SINK - 0.03, b0), (w + 0.03, h + 0.03, b0 + 0.15), "light_grey",
         slide, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * w, sx * (w + 0.02)))
        gbox("TunB_Window_%d" % sx, (x0, 1.05, b0 + 0.4), (x1, 1.85, CAB_Z - 1.7), "window", slide, c)
        gbox("TunB_Band_%d" % sx, (x0, -TUN_B_SINK, b0 + 0.15), (x1, 0.08, CAB_Z), "blue", slide, c)

    drive = pivot(p, "Drive_Level", slide, c, (0.0, -TUN_B_SINK, DRIVE_Z))
    gbox("Drive_Beam", (-1.15, -0.22, -0.25), (1.15, 0.0, 0.25), "metal", drive, c)
    gbox("Drive_Sleeve", (-0.17, -0.75, -0.17), (0.17, -0.22, 0.17), "metal", drive, c)
    foot = pivot(p, "Drive_Foot", drive, c, (0.0, -(ROT_FLOOR - TUN_B_SINK), 0.0))
    gbox("Drive_Leg", (-0.12, BOGIE_TOP - 0.05, -0.12), (0.12, 2.25, 0.12), "light_grey", foot, c)
    gbox("Drive_Bogie", (-0.95, 0.32, -0.28), (0.95, BOGIE_TOP, 0.28), "tug_yellow", foot, c, bevel=0.03)
    for sx in (-1, 1):
        gcyl_x("Drive_Wheel_%d" % sx, sx * 0.62 - 0.14, sx * 0.62 + 0.14, 0.32, 0.0, 0.32, "ink", foot, c, segs=12)
        gcyl_x("Drive_Hub_%d" % sx, sx * 0.62 - 0.16, sx * 0.62 + 0.16, 0.32, 0.0, 0.13, "light_grey",
               foot, c, segs=8)

    level = pivot(p, "Cab_Level", slide, c, (0.0, 0.0, CAB_Z))
    cab = pivot(p, "Cab_Yaw", level, c, (0.0, 0.0, 0.0))
    k = CAB_HALF
    gbox("Cab_Shell", (-k, -0.35, -k), (k, CAB_TOP, k), "white", cab, c, bevel=0.05)
    gbox("Cab_Roof", (-k - 0.05, CAB_TOP, -k - 0.05), (k + 0.05, CAB_TOP + 0.13, k + 0.05), "light_grey",
         cab, c, bevel=0.03)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * k, sx * (k + 0.02)))
        gbox("Cab_Window_%d" % sx, (x0, 1.15, -1.1), (x1, 2.05, 1.1), "window", cab, c)
    gbox("Cab_Window_Back", (-1.1, 1.15, -k - 0.02), (1.1, 2.05, -k), "window", cab, c)
    gbox("Cab_Band", (-k - 0.02, -0.35, -k - 0.02), (k + 0.02, 0.05, k + 0.02), "blue", cab, c)
    # The bellows: five accordion folds, alternating big and small, dark.
    step = BELLOWS_D / 5.0
    for i in range(5):
        z0 = k + i * step
        big = i % 2 == 0
        e = 0.0 if big else 0.08
        gbox("Bellows_%d" % i, (-1.42 + e, -0.28 + e, z0), (1.42 - e, CAB_TOP - 0.05 - e, z0 + step),
             "ink" if big else "dark", cab, c)
    pivot(p, "Mount_Door", cab, c, (0.0, 0.0, MOUNT_DOOR_Z))


# ---------------------------------------------------------------- pushback tug


def build_pushback_tug(root, c):
    p = "pushback_tug"
    L, W = TUG_HALF_L, TUG_HALF_W
    gbox("Chassis", (-1.33, 0.35, -L + 0.2), (1.33, 0.95, L - 0.2), "tug_yellow", root, c, bevel=0.06)
    gbox("Deck", (-1.20, 0.95, -L + 0.45), (0.0, 1.03, L - 0.6), "frame", root, c, bevel=0.02)
    for sz, name in ((1, "Front"), (-1, "Rear")):
        z0, z1 = sorted((sz * (L - 0.2), sz * L))
        gbox("Bumper_" + name, (-1.30, 0.28, z0), (1.30, 0.78, z1), "ink", root, c, bevel=0.03)
        for sx in (-1, 1):
            zl0, zl1 = sorted((sz * L, sz * (L + 0.01)))
            gbox("Lamp_%s_%d" % (name, sx), (sx * 1.0 - 0.12, 0.55, zl0), (sx * 1.0 + 0.12, 0.70, zl1),
                 "text_white" if sz > 0 else "red", root, c)
    # Low cab on the left (Godot +x when facing +z), the driver looks both ways.
    gbox("Cab_Body", (0.15, 0.95, 0.10), (1.30, 1.22, 2.05), "tug_yellow", root, c, bevel=0.03)
    gbox("Cab_Glass", (0.19, 1.22, 0.14), (1.26, 1.44, 2.01), "window", root, c)
    gbox("Cab_Roof", (0.12, 1.44, 0.07), (1.33, 1.52, 2.08), "white", root, c, bevel=0.02)
    gcyl_y("Beacon", 0.72, 1.07, 1.52, 1.62, 0.08, "text_yellow", root, c, segs=8)
    # Four tyres with grey hubs, the outer faces at +-TUG_HALF_W.
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, x1 = sorted((sx * (W - 0.36), sx * W))
            gcyl_x("Tyre_%d_%d" % (sx, sz), x0, x1, 0.45, sz * 1.85, 0.45, "ink", root, c, segs=12)
            hx0, hx1 = sorted((sx * (W - 0.35), sx * (W + 0.01)))
            gcyl_x("Hub_%d_%d" % (sx, sz), hx0, hx1, 0.45, sz * 1.85, 0.20, "light_grey", root, c, segs=8)
    gbox("Hitch", (-0.14, 0.42, L), (0.14, 0.58, HITCH[2] + 0.05), "metal", root, c)

    bar = pivot(p, "Towbar_Pivot", root, c, HITCH)
    gbox("Bar_Eye", (-0.10, -0.06, -0.08), (0.10, 0.06, 0.25), "metal", bar, c)
    gbox("Bar_Tube", (-0.08, -0.08, 0.2), (0.08, 0.08, BAR_LEN - 0.25), "red", bar, c, bevel=0.02)
    gbox("Bar_Head", (-0.32, -0.08, BAR_LEN - 0.25), (0.32, 0.08, BAR_LEN - 0.12), "ink", bar, c)
    for sx in (-1, 1):
        gbox("Bar_Lug_%d" % sx, (sx * 0.24 - 0.04, -0.06, BAR_LEN - 0.12), (sx * 0.24 + 0.04, 0.06, BAR_LEN),
             "metal", bar, c)
    # Two small bar wheels on a fork, on their own pivot under the bar: at rest they
    # touch the ground; hitched, the bar pitches down and the wiring raises
    # Towbar_Wheels along Y (retracts them) so they never sink into the ground.
    wheels = pivot(p, "Towbar_Wheels", bar, c, (0.0, 0.0, BAR_WHEEL_Z))
    wy = BAR_WHEEL_R - HITCH[1]
    gbox("Bar_Fork", (-0.26, wy, -0.04), (0.26, -0.06, 0.04), "metal", wheels, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.20, sx * 0.30))
        gcyl_x("Bar_Wheel_%d" % sx, x0, x1, wy, 0.0, BAR_WHEEL_R, "ink", wheels, c, segs=8)
    pivot(p, "Mount_NoseGear", bar, c, (0.0, 0.0, BAR_LEN))


# ---------------------------------------------------------------- taxi sign


def stroke_quad(p0, p1, w, ext):
    """The quad around segment p0-p1, half width w/2, each end extended by ext."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    nx, ny = -uy * w / 2.0, ux * w / 2.0
    a = (p0[0] - ux * ext, p0[1] - uy * ext)
    b = (p1[0] + ux * ext, p1[1] + uy * ext)
    return [(a[0] - nx, a[1] - ny), (b[0] - nx, b[1] - ny), (b[0] + nx, b[1] + ny), (a[0] + nx, a[1] + ny)]


def glyph_quads(ch):
    """Block letters on a LEGEND_W x LEGEND_H box, origin at its bottom-left."""
    W, H, s = LEGEND_W, LEGEND_H, STROKE
    h = s / 2.0
    segs = []
    if ch == "A":
        segs = [((h, 0.0), (W / 2, H - h)), ((W - h, 0.0), (W / 2, H - h)), ((W * 0.2, H * 0.34), (W * 0.8, H * 0.34))]
    elif ch == "B":
        segs = [((h, 0.0), (h, H)), ((0.0, H - h), (W * 0.7, H - h)), ((0.0, H / 2), (W * 0.74, H / 2)),
                ((0.0, h), (W * 0.74, h)), ((W * 0.7, H - h), (W - h - 0.02, H * 0.83)),
                ((W - h - 0.02, H * 0.83), (W - h - 0.02, H * 0.66)), ((W - h - 0.02, H * 0.66), (W * 0.74, H / 2)),
                ((W * 0.74, H / 2), (W - h, H * 0.36)), ((W - h, H * 0.36), (W - h, H * 0.15)),
                ((W - h, H * 0.15), (W * 0.74, h))]
    elif ch == "C":
        pts = [(W, H * 0.80), (W * 0.74, H - h), (W * 0.28, H - h), (h, H * 0.76), (h, H * 0.24),
               (W * 0.28, h), (W * 0.74, h), (W, H * 0.20)]
        segs = list(zip(pts, pts[1:]))
    elif ch == "D":
        pts = [(0.0, H - h), (W * 0.58, H - h), (W - h, H * 0.74), (W - h, H * 0.26), (W * 0.58, h), (0.0, h)]
        segs = [((h, 0.0), (h, H))] + list(zip(pts, pts[1:]))
    elif ch == "E":
        segs = [((h, 0.0), (h, H)), ((0.0, H - h), (W, H - h)), ((0.0, H / 2), (W * 0.82, H / 2)), ((0.0, h), (W, h))]
    quads = [stroke_quad(a, b, s, 0.0) for a, b in segs]
    # A point two strokes share gets an octagon of in-radius s/2: it fills the wedge
    # between their flat ends with a round joint, so no corner spikes out.
    ends = {}
    for a, b in segs:
        for p in (a, b):
            key = (round(p[0], 6), round(p[1], 6))
            ends[key] = ends.get(key, 0) + 1
    # In-radius 0.98 h: no octagon edge lies exactly on a stroke edge (a coincident
    # edge left a sliver notch after the exact boolean and dissolve).
    r = 0.98 * h / math.cos(math.pi / 8.0)
    for (x, y), n in ends.items():
        if n > 1:
            quads.append([(x + r * math.cos(math.pi / 8.0 + k * math.pi / 4.0),
                           y + r * math.sin(math.pi / 8.0 + k * math.pi / 4.0)) for k in range(8)])
    return quads


def arrow_quads(right):
    """An arrow on an ARROW_W x LEGEND_H box pointing right (or left), origin bottom-left."""
    H, s = LEGEND_H, STROKE * 1.2
    shaft = [(0.0, H / 2 - s / 2), (ARROW_W - 0.16, H / 2 - s / 2), (ARROW_W - 0.16, H / 2 + s / 2),
             (0.0, H / 2 + s / 2)]
    head = [(ARROW_W - 0.20, H / 2 - 0.19), (ARROW_W, H / 2), (ARROW_W - 0.20, H / 2 + 0.19)]
    if not right:
        shaft = [(ARROW_W - u, v) for u, v in reversed(shaft)]
        head = [(ARROW_W - u, v) for u, v in reversed(head)]
    return [shaft, head]


def glyph(piece, name, quads, ox, pal, root, c, back_cx=None, box_w=LEGEND_W):
    """One glyph node. Its strokes stand 0.020 m proud of the panel face and sink
    0.002 m into it (the face is 0.006 m thick). With back_cx the node also carries the
    same glyph on the back face centred on back_cx, mirrored so it reads from behind."""
    holder = empty(name, root, c, (0.0, 0.0, 0.0))
    PIVOTS.setdefault(piece, {})[name] = (root.name, (0.0, 0.0, 0.0))
    oy = (FACE_Y[0] + FACE_Y[1]) / 2.0 - LEGEND_H / 2.0
    z0, z1 = FACE_Z + 0.004, FACE_Z + 0.024
    front = [prism("%s_%d" % (name, i), q, z0, z1, pal, holder, c, ox=ox, oy=oy) for i, q in enumerate(quads)]
    union(front)
    if back_cx is not None:
        # Seen from behind, screen right is Godot -x: u maps to back_cx + box_w/2 - u.
        back = [prism("%s_back_%d" % (name, i), [(back_cx + box_w / 2.0 - u, v) for u, v in reversed(q)],
                      -z1, -z0, pal, holder, c, ox=0.0, oy=oy) for i, q in enumerate(quads)]
        union(back)


def union(objs):
    """Boolean-union overlapping stroke prisms into the first one and delete the rest,
    then merge coplanar faces, so a letter is one closed shell with no inner edges
    (an inverted-hull outline would otherwise draw every stroke's border)."""
    base = objs[0]
    for other in objs[1:]:
        mod = base.modifiers.new("U_" + other.name, "BOOLEAN")
        mod.operation = "UNION"
        mod.solver = "EXACT"
        mod.object = other
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    base.modifiers.clear()
    old = base.data
    base.data = me
    bpy.data.meshes.remove(old)
    for other in objs[1:]:
        data = other.data
        bpy.data.objects.remove(other)
        bpy.data.meshes.remove(data)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts, edges=bm.edges)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = False
    return base


def join_groups(root, c, piece):
    """kit.join_static with one difference: a lone mesh under a pivot is renamed
    <pivot>_Mesh instead of being passed to the join operator on its own."""
    groups = {}
    for ob in list(c.objects):
        if ob.type == "MESH":
            groups.setdefault(ob.parent.name, []).append(ob)
    for key, objs in groups.items():
        name = (kit.piece_title(piece) + "_Body") if key == root.name else (key + "_Mesh")
        if len(objs) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for ob in objs:
                ob.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.join()
        objs[0].name = name


def build_piece(piece):
    """kit.build_piece with join_groups()."""
    c = bpy.data.collections.new(kit.piece_title(piece))
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new(kit.piece_title(piece) + "_ROOT", None)
    c.objects.link(root)
    PIECES[piece][0](root, c)
    bpy.context.view_layer.update()
    join_groups(root, c, piece)
    for ob in c.objects:
        if ob.type == "MESH":
            ob.data.validate()
    bpy.context.view_layer.update()
    return root, c


def location_panel(prefix, x0, x1, back, root, c):
    """A black panel with a yellow border on the front face (or the back face)."""
    y0, y1 = FACE_Y
    s = -1.0 if back else 1.0

    def zr(a, b):
        return tuple(sorted((s * (FACE_Z + a), s * (FACE_Z + b))))

    fz = zr(0.0, 0.006)
    gbox(prefix + "_Face", (x0, y0, fz[0]), (x1, y1, fz[1]), "ink", root, c)
    t, i = 0.035, 0.04
    bz = zr(0.004, 0.016)
    strips = [gbox("%s_Border_%s" % (prefix, name), (lo[0], lo[1], bz[0]), (hi[0], hi[1], bz[1]), "sign_yellow",
                   root, c)
              for name, lo, hi in (("T", (x0 + i, y1 - i - t), (x1 - i, y1 - i)),
                                   ("B", (x0 + i, y0 + i), (x1 - i, y0 + i + t)),
                                   ("L", (x0 + i, y0 + i), (x0 + i + t, y1 - i)),
                                   ("R", (x1 - i - t, y0 + i), (x1 - i, y1 - i)))]
    # One shell, so the outline draws no seams where the strips overlap at the corners.
    union(strips)


def build_taxi_sign(root, c):
    p = "taxi_sign"
    # Two legs on base plates, the dark housing.
    for sx in (-1, 1):
        gbox("Leg_%d" % sx, (sx * 0.85 - 0.04, 0.0, -0.04), (sx * 0.85 + 0.04, SIGN_Y[0], 0.04), "metal", root, c)
        gbox("Foot_%d" % sx, (sx * 0.85 - 0.12, 0.0, -0.12), (sx * 0.85 + 0.12, 0.03, 0.12), "concrete", root, c)
    gbox("Housing", (-SIGN_HALF_W, SIGN_Y[0], -FACE_Z), (SIGN_HALF_W, SIGN_Y[1], FACE_Z), "ink", root, c,
         bevel=0.015)
    # Front: the location panel on the left, the direction panel (yellow) on the right.
    # Back: one location panel in the middle, so the sign reads from either side.
    location_panel("Loc", LOC_X[0], LOC_X[1], False, root, c)
    half = (LOC_X[1] - LOC_X[0]) / 2.0
    location_panel("Back_Loc", -half, half, True, root, c)
    y0, y1 = FACE_Y
    gbox("Dir_Face", (DIR_X[0], y0, FACE_Z), (DIR_X[1], y1, FACE_Z + 0.006), "sign_yellow", root, c)
    loc_cx = (LOC_X[0] + LOC_X[1]) / 2.0
    dir_cx = (DIR_X[0] + DIR_X[1]) / 2.0
    for ch in LETTERS:
        glyph(p, "Glyph_Loc_" + ch, glyph_quads(ch), loc_cx - LEGEND_W / 2.0, "sign_yellow", root, c, back_cx=0.0)
        glyph(p, "Glyph_Dir_" + ch, glyph_quads(ch), dir_cx - LEGEND_W / 2.0, "ink", root, c)
    gap = 0.08
    glyph(p, "Glyph_Arrow_L", arrow_quads(False), dir_cx - LEGEND_W / 2.0 - gap - ARROW_W, "ink", root, c)
    glyph(p, "Glyph_Arrow_R", arrow_quads(True), dir_cx + LEGEND_W / 2.0 + gap, "ink", root, c)


# ---------------------------------------------------------------- tables


def blender_bounds(lo_g, hi_g):
    """Godot bounds -> the Blender bounds kit.verify_written compares."""
    return (lo_g[0], -hi_g[2], lo_g[1]), (hi_g[0], -lo_g[2], hi_g[1])


def drum_extent(r, segs=12):
    """create_cone puts vertices at k * 360/segs degrees from +x: the x and y extents."""
    angs = [2.0 * math.pi * k / segs for k in range(segs)]
    return max(r * math.cos(a) for a in angs), max(r * math.sin(a) for a in angs)


_rx, _ry = drum_extent(DRUM_R + 0.15)
BRIDGE_LO = (-_rx, 0.0, -LINK_Z - 0.02)
BRIDGE_HI = (_rx, ROT_FLOOR + CAB_TOP + 0.13, HINGE_Z + CAB_Z + MOUNT_DOOR_Z)
TUG_LO = (-TUG_HALF_W - 0.01, 0.0, -TUG_HALF_L - 0.01)
TUG_HI = (TUG_HALF_W + 0.01, 1.62, HITCH[2] + BAR_LEN)
SIGN_LO = (-SIGN_HALF_W, 0.0, -FACE_Z - 0.024)
SIGN_HI = (SIGN_HALF_W, SIGN_Y[1], FACE_Z + 0.024)

PIECES = {
    "jet_bridge": (build_jet_bridge, (0, 0)) + blender_bounds(BRIDGE_LO, BRIDGE_HI),
    "pushback_tug": (build_pushback_tug, (0, 0)) + blender_bounds(TUG_LO, TUG_HI),
    "taxi_sign": (build_taxi_sign, (0, 0)) + blender_bounds(SIGN_LO, SIGN_HI),
}
EXTRA_NODES = {
    "jet_bridge": ["Tunnel_Yaw", "Tunnel_Pitch", "Tunnel_Pitch_Mesh", "Tunnel_Slide", "Tunnel_Slide_Mesh",
                   "Drive_Level", "Drive_Level_Mesh", "Drive_Foot", "Drive_Foot_Mesh", "Cab_Level", "Cab_Yaw",
                   "Cab_Yaw_Mesh", "Mount_Door", "Mount_Link"],
    "pushback_tug": ["Towbar_Pivot", "Towbar_Pivot_Mesh", "Towbar_Wheels", "Towbar_Wheels_Mesh", "Mount_NoseGear"],
    "taxi_sign": [n for ch in LETTERS for n in ("Glyph_Loc_" + ch, "Glyph_Loc_%s_Mesh" % ch,
                                                 "Glyph_Dir_" + ch, "Glyph_Dir_%s_Mesh" % ch)]
    + ["Glyph_Arrow_L", "Glyph_Arrow_L_Mesh", "Glyph_Arrow_R", "Glyph_Arrow_R_Mesh"],
}


def check_rig(written):
    """Re-read each written GLB's node tree: every pivot's parent, rest translation
    (Godot axes, the glTF frame) and a zero rest rotation; print the hierarchy."""
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        nodes = js.get("nodes", [])
        parent = {}
        for i, nd in enumerate(nodes):
            for ch in nd.get("children", []):
                parent[ch] = i
        by_name = {nd.get("name"): i for i, nd in enumerate(nodes)}

        def path(i):
            names = []
            while i is not None:
                names.append(nodes[i].get("name"))
                i = parent.get(i)
            return "/".join(reversed(names))

        for i, nd in enumerate(nodes):
            kit.log("NODE %s %s t=%s r=%s mesh=%s" % (piece, path(i), [round(v, 4) for v in nd.get("translation", [0, 0, 0])],
                                                      nd.get("rotation", "none"), nd.get("mesh", "-")))
        for name, (want_parent, want_t) in PIVOTS.get(piece, {}).items():
            i = by_name.get(name)
            if i is None:
                kit.fail("%s: pivot %s missing from the written file" % (piece, name))
                continue
            nd = nodes[i]
            got_parent = nodes[parent[i]].get("name") if i in parent else None
            t = nd.get("translation", [0.0, 0.0, 0.0])
            err = max(abs(a - b) for a, b in zip(t, want_t))
            rot = nd.get("rotation", [0.0, 0.0, 0.0, 1.0])
            rot_err = max(abs(a - b) for a, b in zip(rot, [0.0, 0.0, 0.0, 1.0]))
            kit.log("PIVOT %s %s parent=%s t=%s want=%s err=%.5f rot_err=%.5f"
                    % (piece, name, got_parent, [round(v, 4) for v in t], list(want_t), err, rot_err))
            if got_parent != want_parent or err > 1e-4 or rot_err > 1e-5:
                kit.fail("%s: pivot %s parent %s t %s, expected %s at %s" % (piece, name, got_parent, t, want_parent,
                                                                             want_t))
        # Every mesh node hangs on the node it is named after (<pivot>_Mesh on <pivot>,
        # <Piece>_Body on the root), with no offset, so it turns about that pivot. The
        # names come from join_groups(), which names a mesh by the parent it was built
        # under; this checks the written file kept that pairing.
        title = kit.piece_title(piece)
        for i, nd in enumerate(nodes):
            if "mesh" not in nd:
                continue
            owner = nodes[parent[i]].get("name") if i in parent else None
            want = title + "_ROOT" if nd.get("name") == title + "_Body" else nd.get("name", "")[:-len("_Mesh")]
            off = any(abs(v) > 1e-5 for v in nd.get("translation", [0, 0, 0])) or "rotation" in nd
            if owner != want or off:
                kit.fail("%s: mesh %s hangs on %s (expected %s) offset=%s" % (piece, nd.get("name"), owner, want, off))
    kit.log("RIG reach_min=%.2f reach_max=%.2f mount_door_z=%.2f slide_max=%.2f rot_floor=%.2f hinge_z=%.2f "
            "cab_z=%.2f drive_z=%.2f tun_b_sink=%.2f bar_len=%.2f hitch=%s"
            % (REACH_MIN, REACH_MAX, MOUNT_DOOR_Z, SLIDE_MAX, ROT_FLOOR, HINGE_Z, CAB_Z, DRIVE_Z, TUN_B_SINK, BAR_LEN,
               HITCH))


def guard(pieces):
    """Refuse a name another kit owns, or an existing .glb that is not this builder's."""
    taken = sorted(set(kit.PIECES) & set(pieces))
    if taken:
        kit.fail("airside prop names already owned by the interior kit: %s" % taken)
    for piece in pieces:
        out = os.path.join(kit.OUT_DIR, piece + ".glb")
        if os.path.exists(out):
            js, _n = kit.parse_glb(out)
            names = {n.get("name") for n in js.get("nodes", [])}
            own = kit.piece_title(piece) + "_ROOT" in names
            kit.log("GUARD %s existing own=%s" % (piece, own))
            if not own:
                kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
        else:
            kit.log("GUARD %s new file %s" % (piece, os.path.relpath(out, kit.REPO)))
    if kit.FAILS:
        sys.exit(1)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pieces = argv or list(PIECES)
    unknown = [p for p in pieces if p not in PIECES]
    if unknown:
        kit.fail("unknown pieces %s; known %s" % (unknown, list(PIECES)))
        sys.exit(1)
    guard(pieces)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    os.makedirs(kit.OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.report_palette()
    written = []
    for piece in pieces:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        kit._images.clear()
        kit._materials.clear()
        PIVOTS.pop(piece, None)
        root, c = build_piece(piece)
        nmat = len(bpy.data.materials)
        nimg = len(bpy.data.images)
        kit.log("BUILT %s objects=%d materials=%d (%s) images=%d (%s)"
                % (piece, len(c.objects), nmat, sorted(m.name for m in bpy.data.materials), nimg,
                   sorted(i.name for i in bpy.data.images)))
        written.append((piece, kit.export_piece(piece, root, c)))
    for piece, out in written:
        kit.verify_written(piece, out)
    check_rig(written)
    # The appendable .blend: every piece in its own collection, side by side.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._images.clear()
    kit._materials.clear()
    x = 0.0
    for piece in pieces:
        root, _c = build_piece(piece)
        root.location.x = x
        x += 8.0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=True)
    kit.log("BLEND saved %s" % os.path.relpath(BLEND_OUT, kit.REPO))
    kit.log("AIRSIDE done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    main()
