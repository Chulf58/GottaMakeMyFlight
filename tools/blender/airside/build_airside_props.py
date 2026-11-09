"""Build the airside props (board 4c08b8e5, Runway R11) and export one .glb each.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\build_airside_props.py' [-- piece ...]

Pieces (written to game/assets/airside/props/<piece>.glb):
- jet_bridge: a fixed telescoping passenger bridge, visual only. One rig serves the
  medium sill (plane 05, 1.59 m) and the large sills (06 at 2.4 m, 07 at 2.9 m) and
  every reach from REACH_MIN to REACH_MAX (see the pose math below).
- pushback_tug: a low towbarless tug (user ruling 2026-11-07) that cradles the nose
  wheel in a slot at its rear and runs forward under and past the nose; its origin
  and Mount_NoseGear are the nose wheel's ground contact, and Cradle_Lift raises the
  cradle along Y.
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

Jet bridge rig (all empties export with zero rest rotation). Board 0adca5c6 roots it
at the gate's exit door: the terminal wall line is z = -ROOT_OUT and the exit door's
centre x = EXIT_X in the root's frame (JetBridgePose.root_for() turns the root 180
degrees, so +x is west, toward the door). The tunnels, the cab and the stair box are
hollow with real window openings (glass panes, TP_Glass_1A_D), so a passenger inside
shows through them. The rotunda is hollow too, its wall open where tunnel A and the stub pass.
  JetBridge_ROOT
    JetBridge_Body        column, rotunda drum and roof (static)
    StairBox              at the origin: the stair box at the exit door (vestibule,
                          RISERS steps, apron door), the link corridor along the wall
                          and the stub into the rotunda (static, StairBox_Mesh)
    Mount_StairBottom     (EXIT_X, 0, -ROOT_OUT): the exit door's sill on the wall line
    Mount_Vestibule       (EXIT_X, 0, -LINK_Z): in the vestibule on the corridor axis
    Mount_StairFoot       (STAIR_FOOT_X + STEP_OFF, 0, -LINK_Z): before the first step
    Mount_StairTop        (STAIR_TOP_X - STEP_OFF, ROT_FLOOR, -LINK_Z): past the top step
    Mount_Link            (0, ROT_FLOOR, -LINK_Z): the corridor at the stub
    Mount_Rotunda         (0, ROT_FLOOR, 0): the rotunda's centre, floor level
    Tunnel_Yaw            at (0, ROT_FLOOR, 0): rotate about Y to aim the tunnel; its mesh is the two drum skirts
      Tunnel_Pitch        at (0, 0, HINGE_Z) on the drum face, floor height: rotate
                          about X to slope the tunnel; its mesh is tunnel A
        Mount_TunnelA     at (0, 0, 0): tunnel A's floor at the hinge
        Tunnel_Slide      at (0, 0, 0): translate along +Z by s in [0, SLIDE_MAX];
                          its mesh is tunnel B, the larger cab-side section
          Mount_TunnelB   at (0, 0, CAB_Z - TUN_B_LEN): tunnel B's mouth, floor line
          Drive_Level     at (0, -TUN_B_SINK, DRIVE_Z) under tunnel B: counter-pitch
                          so it stays upright; its mesh is the cross beam and sleeve
            Drive_Foot    at (0, -(ROT_FLOOR - TUN_B_SINK), 0): its origin is the wheel
                          contact; set y so the bogie stands on the ground
          Cab_Level       at (0, 0, CAB_Z), B's outer end on the floor line:
                          counter-pitch so the cab floor is level
            Cab_Yaw       at (0, 0, 0): rotate about Y to face the fuselage; its mesh is
                          the cab, roof and bellows
              Mount_CabFloor  at (0, 0, 0): the cab floor's centre
              Mount_Door  at (0, 0, MOUNT_DOOR_Z): the bellows' front, floor level;
                          the wiring puts it on the aircraft door sill
The walk from the exit door to the plane runs through WALK_MOUNTS then Mount_Door;
walk_report() prints them from the written file.

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
DRIVE_H_MAX = 2.90       # the leg top (foot + LEG_TOP) stays 0.08 m inside the sleeve (bottom -SLEEVE_LOW)
# The drive leg telescopes into the sleeve. Tunnel B is hollow, so at the lowest drive
# height the game uses (1.50 m, plane 05 docked) the leg top must stay inside B's floor
# slab (0.28 m over Drive_Level): LEG_TOP - 1.50 <= 0.24. At low heights the sleeve
# bottom sinks into the bogie, which is wider than the sleeve both ways.
LEG_TOP = 1.74
SLEEVE_LOW = 1.24
DRIVE_Z = CAB_Z - 1.6
CAB_HALF = 1.50
CAB_TOP = 2.85
BELLOWS_D = 0.60
MOUNT_DOOR_Z = CAB_HALF + BELLOWS_D
PITCH_MAX_DEG = 9.0
REACH_MIN = HINGE_Z + CAB_Z
REACH_MAX = REACH_MIN + SLIDE_MAX
BOGIE_TOP = 0.60
SKIN_T = 0.08           # wall, roof and end-wall thickness of every hollow part
# The stair box and link (board 0adca5c6; rulings jet-bridge-starts-at-the-gate-s-exit-
# door-passengers-step-fr and jet-bridge-boarding-design-stair-box-at-the-exit-door-
# real-w). The terminal is at -z, the gate's exit door at +x: the bridge root stands
# ROOT_OUT out from the wall line and EXIT_X along it from the exit door's centre.
ROOT_OUT = 4.0
EXIT_X = 9.7
BOX_GAP = 0.3           # the box's terminal-side face off the wall line
BOX_D = 1.8             # the box and link corridor depth (outer)
BOX_Z0 = -(ROOT_OUT - BOX_GAP)
BOX_Z1 = BOX_Z0 + BOX_D
LINK_Z = -(BOX_Z0 + BOX_Z1) / 2.0   # the corridor's axis behind the column axis
BOX_TOP = ROT_FLOOR + 2.5
VEST_HALF = 1.0         # the ground-floor vestibule either side of the exit door
RISERS = 16
RISE = ROT_FLOOR / RISERS
TREAD = 0.27
STAIR_FOOT_X = EXIT_X - VEST_HALF
STAIR_TOP_X = STAIR_FOOT_X - (RISERS - 1) * TREAD
STEP_OFF = 0.1          # the stair mounts stand this far off the first and last riser
BOX_END_X = EXIT_X + VEST_HALF       # the box's far end, past the exit door
LINK_END_X = -1.1                    # the corridor's closed end past the stub
STUB_HALF = 0.75
STUB_END = 1.45         # the stub's far end inside the rotunda, clear of the skirts
DOOR_HALF = 0.55        # the openings for the exit door and the apron door
DOOR_TOP = 2.3
COLLAR_GAP = 0.16
COLLAR_Z0 = -(ROOT_OUT - COLLAR_GAP)  # the exit door collar stops short of the wall
# The terminal roof (RoofView) has a fascia 0.25 m out from the wall line from 2.3 m up
# to 5.2 m, so the collar stays under 2.3 m and the box (0.3 m out) has no roof
# overhang on the terminal side.
COLLAR_TOP = 2.25
COLLAR_DOOR_TOP = 2.12
# The rotunda: a static outer wall (DRUM_IN..DRUM_R) open where tunnel A passes at the
# yaws the game uses (75.1 degrees docked and parked at every stand, 90 swung clear;
# tunnel A spans +-DRUM_TUN_HALF at the outer face) and where the stub enters, and two
# skirts under Tunnel_Yaw (SKIRT_IN..SKIRT_OUT, relative +-SKIRT_ARC) that close the
# part of the tunnel opening the tunnel leaves bare at either yaw.
DRUM_IN = 1.62
YAW_USED = (75.1, 90.0)
DRUM_TUN_HALF = 46.0      # tunnel A's band (1.22 m out) where it leaves the drum (r 1.70)
DRUM_STUB_HALF = math.degrees(math.asin(STUB_HALF / DRUM_IN))
SKIRT_IN, SKIRT_OUT = 1.54, 1.60
SKIRT_ARC = (48.5, 64.0)
WIN_LOW = (1.0, 3.3)    # box windows along the stair
WIN_HIGH = (ROT_FLOOR + 0.85, ROT_FLOOR + 2.05)
# The walkable floor points from the exit door to the plane door, in walk order:
# the first six are static (under the root), the rest ride the tunnel and the cab.
WALK_MOUNTS = ["Mount_StairBottom", "Mount_Vestibule", "Mount_StairFoot", "Mount_StairTop", "Mount_Link",
               "Mount_Rotunda", "Mount_TunnelA", "Mount_TunnelB", "Mount_CabFloor"]

# ---------------------------------------------------------------- pushback tug
# A towbarless tug; z is measured from the nose wheel's ground contact (the origin).
# Plane 05: the nose is 2.15 m ahead of its nose axle, so the front at 4.0 m stands
# 1.85 m past the nose (the ruling allows 2.0 m) and the cab starts 0.40 m past it.
TUG_HALF_W = 1.40
CRADLE_HALF = 0.55      # the slot for the nose wheel and gear strut, x +-0.55
TUG_REAR = -0.75        # the arms' rear ends (the clamp gate)
CRADLE_FRONT = 0.55     # the stop pad's front, where the main body starts
TUG_FRONT = 4.00
TUG_BUMPER = 0.12
ARM_TOP = 0.55
DECK_TOP = 0.70         # everything that can sit under the fuselage stays this low
CAB_Z0 = 2.55
CAB_GLASS_Y = 1.05
CAB_ROOF_Y = 1.32
TUG_TOP = 1.48          # the beacon top
TYRE_R = 0.30
TYRE_Z = (-0.25, 3.25)

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


def panels(a, b, width, gap):
    """As many (u0, u1) spans of `width` with `gap` between them as fit in [a, b],
    centred in it."""
    n = int((b - a + gap) // (width + gap))
    start = a + (b - a - (n * width + (n - 1) * gap)) / 2.0
    return [(start + i * (width + gap), start + i * (width + gap) + width) for i in range(n)]


def holed_wall(name, axis, u_rng, v_rng, w_rng, holes, pal, parent, c):
    """One closed wall slab with rectangular openings, built on a shared-vertex grid
    so the outline draws only its rim and the openings' edges (no seams between
    panels). axis "x": the wall's normal is Godot x (it runs along z, u = z); axis
    "z": its normal is z (it runs along x, u = x). v is height, w the thickness
    range. holes: (u0, u1, v0, v1, glass); a glass opening gets a pane in the
    middle of the wall, named <name>_Glass_<i>."""
    def at(u, v, w):
        return gb(w, v, u) if axis == "x" else gb(u, v, w)

    us = sorted({u_rng[0], u_rng[1]} | {h[k] for h in holes for k in (0, 1)})
    vs = sorted({v_rng[0], v_rng[1]} | {h[k] for h in holes for k in (2, 3)})
    nu, nv = len(us) - 1, len(vs) - 1

    def solid(i, j):
        if i < 0 or j < 0 or i >= nu or j >= nv:
            return False
        um, vm = (us[i] + us[i + 1]) / 2.0, (vs[j] + vs[j + 1]) / 2.0
        return not any(h[0] < um < h[1] and h[2] < vm < h[3] for h in holes)

    bm = bmesh.new()
    verts = {}

    def vert(i, j, side):
        key = (i, j, side)
        if key not in verts:
            verts[key] = bm.verts.new(at(us[i], vs[j], w_rng[side]))
        return verts[key]

    for i in range(nu):
        for j in range(nv):
            if not solid(i, j):
                continue
            bm.faces.new([vert(i, j, 1), vert(i + 1, j, 1), vert(i + 1, j + 1, 1), vert(i, j + 1, 1)])
            bm.faces.new([vert(i, j + 1, 0), vert(i + 1, j + 1, 0), vert(i + 1, j, 0), vert(i, j, 0)])
            # A side face on every cell edge that borders an opening or the rim.
            for (di, dj), (a, b) in (((0, -1), ((i, j), (i + 1, j))), ((1, 0), ((i + 1, j), (i + 1, j + 1))),
                                     ((0, 1), ((i + 1, j + 1), (i, j + 1))), ((-1, 0), ((i, j + 1), (i, j)))):
                if not solid(i + di, j + dj):
                    bm.faces.new([vert(*a, 1), vert(*a, 0), vert(*b, 0), vert(*b, 1)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    wall = kit._finish_mesh(name, bm, pal, parent, c)
    mid = (w_rng[0] + w_rng[1]) / 2.0
    for k, h in enumerate(holes):
        if not h[4]:
            continue
        lo, hi = (mid - 0.008, h[2], h[0]), (mid + 0.008, h[3], h[1])
        if axis == "z":
            lo, hi = (h[0], h[2], mid - 0.008), (h[1], h[3], mid + 0.008)
        gbox("%s_Glass_%d" % (name, k), lo, hi, "glass", parent, c)
    return wall


def window_row(spans, v0, v1):
    return [(a, b, v0, v1, True) for a, b in spans]


def arc_wall(name, a0, a1, r0, r1, y0, y1, pal, parent, c, step=12.0):
    """A closed curved wall about the Godot y axis from yaw a0 to a1 (degrees from +z
    toward +x), radii r0..r1, heights y0..y1."""
    n = max(1, int(math.ceil((a1 - a0) / step)))
    bm = bmesh.new()
    rings = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        s, co = math.sin(a), math.cos(a)
        rings.append([bm.verts.new(gb(r * s, y, r * co)) for r, y in ((r0, y0), (r1, y0), (r1, y1), (r0, y1))])
    for i in range(n):
        p, q = rings[i], rings[i + 1]
        for k in range(4):
            bm.faces.new([p[k], q[k], q[(k + 1) % 4], p[(k + 1) % 4]])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def drum_closed():
    """The yaw spans (degrees) where the rotunda's outer wall stands: everything but
    the tunnel opening and the stub opening (centred on 180, the -z side)."""
    t0, t1 = YAW_USED[0] - DRUM_TUN_HALF, YAW_USED[1] + DRUM_TUN_HALF
    s0, s1 = 180.0 - DRUM_STUB_HALF, 180.0 + DRUM_STUB_HALF
    return [(t1, s0), (s1, t0 + 360.0)]


# ---------------------------------------------------------------- jet bridge


def build_jet_bridge(root, c):
    p = "jet_bridge"
    # Static: plinth, column, rotunda drum with a window band, roof. The rotunda is
    # closed: a passenger walks into it from the link stub and out into tunnel A.
    gbox("Plinth", (-0.7, 0.0, -0.7), (0.7, 0.15, 0.7), "concrete", root, c, bevel=0.03)
    gcyl_y("Column", 0.0, 0.0, 0.15, ROT_FLOOR - 0.25, 0.45, "concrete", root, c)
    gcyl_y("Drum_Floor", 0.0, 0.0, ROT_FLOOR - 0.25, ROT_FLOOR, DRUM_R + 0.05, "metal", root, c)
    # The rotunda is hollow: its wall stands only where nothing passes through it, and
    # its painted window band runs on the same spans.
    for i, (a0, a1) in enumerate(drum_closed()):
        arc_wall("Drum_Wall_%d" % i, a0, a1, DRUM_IN, DRUM_R, ROT_FLOOR, ROT_FLOOR + 2.35, "white", root, c)
        arc_wall("Drum_Windows_%d" % i, a0, a1, DRUM_R, DRUM_R + 0.02, ROT_FLOOR + 1.0, ROT_FLOOR + 1.6, "window",
                 root, c)
    gcyl_y("Drum_Roof", 0.0, 0.0, ROT_FLOOR + 2.35, ROT_FLOOR + 2.55, DRUM_R + 0.15, "light_grey", root, c)
    build_stair_box(p, root, c)

    yaw = pivot(p, "Tunnel_Yaw", root, c, (0.0, ROT_FLOOR, 0.0))
    # The skirts turn with the tunnel and close the rotunda's tunnel opening beside it.
    for sx in (-1, 1):
        a0, a1 = sorted((sx * SKIRT_ARC[0], sx * SKIRT_ARC[1]))
        arc_wall("Drum_Skirt_%d" % sx, a0, a1, SKIRT_IN, SKIRT_OUT, 0.0, 2.35, "white", yaw, c)
    pitch = pivot(p, "Tunnel_Pitch", yaw, c, (0.0, 0.0, HINGE_Z))
    pivot(p, "Mount_TunnelA", pitch, c, (0.0, 0.0, 0.0))
    # Tunnel A, hinge-local: hollow, starts inside the drum so its corners stay sunk at
    # any yaw, open at both ends. Its floor top is the floor line.
    w, h, z0 = TUN_A_HALF_W, TUN_A_H, -0.6
    gbox("TunA_Floor", (-w, -0.12, z0), (w, 0.0, TUN_A_LEN), "metal", pitch, c)
    gbox("TunA_Roof", (-w, h - SKIN_T, z0), (w, h, TUN_A_LEN), "white", pitch, c, bevel=0.02)
    wins = window_row(panels(0.3, TUN_A_LEN - 0.3, 1.0, 0.25), 0.95, 1.95)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (w - SKIN_T), sx * w))
        holed_wall("TunA_Wall_%d" % sx, "x", (z0, TUN_A_LEN), (-0.12, h - SKIN_T), (x0, x1), wins, "white", pitch, c)
        b0, b1 = sorted((sx * w, sx * (w + 0.02)))
        gbox("TunA_Band_%d" % sx, (b0, -0.12, -0.3), (b1, 0.12, TUN_A_LEN), "blue", pitch, c)

    slide = pivot(p, "Tunnel_Slide", pitch, c, (0.0, 0.0, 0.0))
    # Tunnel B: hollow, larger, slides over A; its floor top sits 0.02 m under the
    # floor line, so A's floor covers it where they overlap.
    w, h, b0 = TUN_B_HALF_W, TUN_B_H, CAB_Z - TUN_B_LEN
    pivot(p, "Mount_TunnelB", slide, c, (0.0, 0.0, b0))
    gbox("TunB_Floor", (-w, -TUN_B_SINK, b0), (w, -0.02, CAB_Z), "metal", slide, c)
    gbox("TunB_Roof", (-w, h - SKIN_T, b0), (w, h, CAB_Z), "white", slide, c, bevel=0.02)
    wins = window_row(panels(b0 + 0.4, CAB_Z - 1.7, 1.0, 0.25), 1.0, 2.0)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (w - SKIN_T), sx * w))
        holed_wall("TunB_Wall_%d" % sx, "x", (b0, CAB_Z), (-TUN_B_SINK, h - SKIN_T), (x0, x1), wins, "white", slide,
                   c)
        e0, e1 = sorted((sx * w, sx * (w + 0.02)))
        gbox("TunB_Band_%d" % sx, (e0, -TUN_B_SINK, b0 + 0.15), (e1, 0.08, CAB_Z), "blue", slide, c)
    # The mouth: a ring round B's open inner end, clear of tunnel A inside it.
    m0, m1 = b0, b0 + 0.15
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (w - 0.11), sx * (w + 0.03)))
        gbox("TunB_Mouth_%d" % sx, (x0, -TUN_B_SINK - 0.03, m0), (x1, h + 0.03, m1), "light_grey", slide, c)
    gbox("TunB_Mouth_Top", (-w - 0.03, h - 0.11, m0), (w + 0.03, h + 0.03, m1), "light_grey", slide, c)
    gbox("TunB_Mouth_Low", (-w - 0.03, -TUN_B_SINK - 0.03, m0), (w + 0.03, -0.16, m1), "light_grey", slide, c)

    drive = pivot(p, "Drive_Level", slide, c, (0.0, -TUN_B_SINK, DRIVE_Z))
    gbox("Drive_Beam", (-1.15, -0.22, -0.25), (1.15, 0.0, 0.25), "metal", drive, c)
    gbox("Drive_Sleeve", (-0.17, -SLEEVE_LOW, -0.17), (0.17, -0.22, 0.17), "metal", drive, c)
    foot = pivot(p, "Drive_Foot", drive, c, (0.0, -(ROT_FLOOR - TUN_B_SINK), 0.0))
    gbox("Drive_Leg", (-0.12, BOGIE_TOP - 0.05, -0.12), (0.12, LEG_TOP, 0.12), "light_grey", foot, c)
    gbox("Drive_Bogie", (-0.95, 0.32, -0.28), (0.95, BOGIE_TOP, 0.28), "tug_yellow", foot, c, bevel=0.03)
    for sx in (-1, 1):
        gcyl_x("Drive_Wheel_%d" % sx, sx * 0.62 - 0.14, sx * 0.62 + 0.14, 0.32, 0.0, 0.32, "ink", foot, c, segs=12)
        gcyl_x("Drive_Hub_%d" % sx, sx * 0.62 - 0.16, sx * 0.62 + 0.16, 0.32, 0.0, 0.13, "light_grey",
               foot, c, segs=8)

    level = pivot(p, "Cab_Level", slide, c, (0.0, 0.0, CAB_Z))
    cab = pivot(p, "Cab_Yaw", level, c, (0.0, 0.0, 0.0))
    pivot(p, "Mount_CabFloor", cab, c, (0.0, 0.0, 0.0))
    k = CAB_HALF
    # The cab: hollow, open at the back where tunnel B enters it, with a door
    # opening at the front into the bellows. Its floor top is the floor line.
    gbox("Cab_Floor", (-k, -0.08, -k), (k, 0.0, k), "metal", cab, c)
    gbox("Cab_Band", (-k - 0.02, -0.35, -k - 0.02), (k + 0.02, -0.08, k + 0.02), "blue", cab, c)
    gbox("Cab_Ceiling", (-k, CAB_TOP - SKIN_T, -k), (k, CAB_TOP, k), "white", cab, c)
    gbox("Cab_Roof", (-k - 0.05, CAB_TOP, -k - 0.05), (k + 0.05, CAB_TOP + 0.13, k + 0.05), "light_grey",
         cab, c, bevel=0.03)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (k - SKIN_T), sx * k))
        holed_wall("Cab_Wall_%d" % sx, "x", (-k, k), (0.0, CAB_TOP - SKIN_T), (x0, x1),
                   [(-1.1, 1.1, 1.15, 2.05, True)], "white", cab, c)
    holed_wall("Cab_Front", "z", (-k + SKIN_T, k - SKIN_T), (0.0, CAB_TOP - SKIN_T), (k - SKIN_T, k),
               [(-0.9, 0.9, 0.0, DOOR_TOP, False)], "white", cab, c)
    # The bellows: five accordion folds, alternating big and small, dark, each a
    # ring round the same opening.
    step = BELLOWS_D / 5.0
    for i in range(5):
        z0 = k + i * step
        e = 0.0 if i % 2 == 0 else 0.08
        holed_wall("Bellows_%d" % i, "z", (-1.42 + e, 1.42 - e), (-0.28 + e, CAB_TOP - 0.05 - e), (z0, z0 + step),
                   [(-0.9, 0.9, 0.0, DOOR_TOP, False)], "ink" if i % 2 == 0 else "dark", cab, c)
    pivot(p, "Mount_Door", cab, c, (0.0, 0.0, MOUNT_DOOR_Z))


def build_stair_box(p, root, c):
    """The stair box at the gate's exit door and the link corridor to the rotunda,
    static, under their own StairBox node. In the root's frame the terminal wall
    line is z = -ROOT_OUT and the exit door's centre x = EXIT_X. A passenger steps
    out of the exit door into a ground-floor vestibule (which also has a door out to
    the apron, for the planes the bridge cannot dock), climbs RISERS steps toward
    the column to the corridor floor at ROT_FLOOR, walks the corridor to the stub
    and through the stub into the rotunda. The walk mounts (Mount_*) are named in
    walk order; check_rig() reads them back from the written file."""
    box = pivot(p, "StairBox", root, c, (0.0, 0.0, 0.0))
    for name, at in (("Mount_StairBottom", (EXIT_X, 0.0, -ROOT_OUT)),
                     ("Mount_Vestibule", (EXIT_X, 0.0, -LINK_Z)),
                     ("Mount_StairFoot", (STAIR_FOOT_X + STEP_OFF, 0.0, -LINK_Z)),
                     ("Mount_StairTop", (STAIR_TOP_X - STEP_OFF, ROT_FLOOR, -LINK_Z)),
                     ("Mount_Link", (0.0, ROT_FLOOR, -LINK_Z)),
                     ("Mount_Rotunda", (0.0, ROT_FLOOR, 0.0))):
        pivot(p, name, root, c, at)
    zi0, zi1 = BOX_Z0 + SKIN_T, BOX_Z1 - SKIN_T     # the inside faces of the long walls
    deck = ROT_FLOOR - 0.25
    gbox("Box_Floor", (STAIR_FOOT_X, 0.0, zi0), (BOX_END_X - SKIN_T, 0.03, zi1), "floor", box, c)
    for i in range(1, RISERS):
        gbox("Box_Step_%02d" % i, (STAIR_FOOT_X - i * TREAD, 0.0, zi0), (STAIR_FOOT_X - (i - 1) * TREAD, i * RISE, zi1),
             "metal", box, c)
    gbox("Link_Floor", (LINK_END_X, deck, zi0), (STAIR_TOP_X, ROT_FLOOR, zi1), "metal", box, c)
    gbox("Box_Under", (STAIR_TOP_X - SKIN_T, 0.0, BOX_Z0), (STAIR_TOP_X, deck, BOX_Z1), "white", box, c)
    gbox("Box_Roof", (LINK_END_X - 0.05, BOX_TOP - 0.1, BOX_Z0), (BOX_END_X + 0.05, BOX_TOP, BOX_Z1 + 0.05),
         "light_grey", box, c, bevel=0.02)
    top = BOX_TOP - 0.1
    under = (LINK_END_X, STAIR_TOP_X, 0.0, deck, False)
    high = (WIN_HIGH[0], WIN_HIGH[1])
    stair_low = window_row(panels(STAIR_TOP_X + 0.15, STAIR_FOOT_X - 0.1, 1.0, 0.22), *WIN_LOW)
    # The terminal side: the exit door opening, windows along the stair and the
    # corridor above the terminal wall.
    south = ([under, (EXIT_X - DOOR_HALF, EXIT_X + DOOR_HALF, 0.0, DOOR_TOP, False)] + stair_low
             + window_row(panels(LINK_END_X + 0.3, BOX_END_X - 0.3, 1.0, 0.22), *high))
    holed_wall("Box_Wall_South", "z", (LINK_END_X, BOX_END_X), (0.0, top), (BOX_Z0, BOX_Z0 + SKIN_T), south, "white",
               box, c)
    # The apron side: the apron door in the vestibule, the stub opening, windows.
    north = ([under, (EXIT_X - DOOR_HALF, EXIT_X + DOOR_HALF, 0.0, DOOR_TOP, False),
              (-STUB_HALF + SKIN_T, STUB_HALF - SKIN_T, ROT_FLOOR, ROT_FLOOR + 2.3, False)] + stair_low
             + window_row(panels(STUB_HALF + 0.25, BOX_END_X - 0.3, 1.0, 0.22), *high))
    holed_wall("Box_Wall_North", "z", (LINK_END_X, BOX_END_X), (0.0, top), (BOX_Z1 - SKIN_T, BOX_Z1), north, "white",
               box, c)
    holed_wall("Box_Wall_End", "x", (BOX_Z0, BOX_Z1), (0.0, top), (BOX_END_X - SKIN_T, BOX_END_X),
               window_row(panels(BOX_Z0 + 0.3, BOX_Z1 - 0.3, 1.0, 0.2), *high), "white", box, c)
    holed_wall("Link_Wall_End", "x", (BOX_Z0, BOX_Z1), (deck, top), (LINK_END_X, LINK_END_X + SKIN_T), [], "white",
               box, c)
    for name, z0, z1 in (("South", BOX_Z0 - 0.02, BOX_Z0), ("North", BOX_Z1, BOX_Z1 + 0.02)):
        gbox("Box_Band_" + name, (LINK_END_X, deck, z0), (BOX_END_X, ROT_FLOOR + 0.05, z1), "blue", box, c)
    # The exit door collar: a frame from the box's terminal face toward the wall.
    for sx in (-1, 1):
        x0, x1 = sorted((EXIT_X + sx * DOOR_HALF, EXIT_X + sx * (DOOR_HALF + 0.15)))
        gbox("Box_Collar_%d" % sx, (x0, 0.0, COLLAR_Z0), (x1, COLLAR_TOP, BOX_Z0), "frame", box, c)
    gbox("Box_Collar_Top", (EXIT_X - DOOR_HALF, COLLAR_DOOR_TOP, COLLAR_Z0), (EXIT_X + DOOR_HALF, COLLAR_TOP, BOX_Z0),
         "frame", box, c)
    # The stub from the corridor into the rotunda: hollow, its far end inside the drum.
    s0, s1 = BOX_Z1 - SKIN_T, -STUB_END
    gbox("Stub_Floor", (-STUB_HALF, deck, s0), (STUB_HALF, ROT_FLOOR, s1), "metal", box, c)
    gbox("Stub_Roof", (-STUB_HALF, ROT_FLOOR + 2.3, s0), (STUB_HALF, ROT_FLOOR + 2.4, s1), "white", box, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (STUB_HALF - SKIN_T), sx * STUB_HALF))
        gbox("Stub_Wall_%d" % sx, (x0, ROT_FLOOR, s0), (x1, ROT_FLOOR + 2.3, s1), "white", box, c)
    # One post under the corridor.
    gbox("Link_Post", (1.65, 0.0, -LINK_Z - 0.15), (1.95, deck, -LINK_Z + 0.15), "concrete", box, c)


# ---------------------------------------------------------------- pushback tug


def build_pushback_tug(root, c):
    """A towbarless tug. The origin is the nose wheel's ground contact in the cradle;
    the body runs forward (+z) under and past the aircraft's nose, the cradle slot is
    open at the rear (-z) for the wheel and the gear strut."""
    p = "pushback_tug"
    W, S = TUG_HALF_W, CRADLE_HALF
    zr, z1, zf = TUG_REAR, CRADLE_FRONT, TUG_FRONT - TUG_BUMPER
    # Two cradle arms either side of the slot, then the low main body ahead of it.
    for sx in (-1, 1):
        x0, x1 = sorted((sx * S, sx * (W - 0.2)))
        gbox("Arm_%d" % sx, (x0, 0.14, zr), (x1, ARM_TOP, z1), "tug_yellow", root, c, bevel=0.04)
        gbox("Arm_Cap_%d" % sx, (x0 + 0.02, 0.10, zr - 0.06), (x1 - 0.02, ARM_TOP - 0.08, zr), "ink", root, c)
    gbox("Body", (-(W - 0.2), 0.14, z1), (W - 0.2, DECK_TOP, zf), "tug_yellow", root, c, bevel=0.05)
    gbox("Deck", (-(W - 0.32), DECK_TOP, z1 + 0.12), (-0.05, DECK_TOP + 0.04, CAB_Z0 - 0.1), "frame", root, c)
    gbox("Bumper_Front", (-(W - 0.25), 0.12, zf), (W - 0.25, 0.62, TUG_FRONT), "ink", root, c, bevel=0.03)
    for sx in (-1, 1):
        gbox("Lamp_Front_%d" % sx, (sx * 0.9 - 0.12, 0.40, TUG_FRONT), (sx * 0.9 + 0.12, 0.52, TUG_FRONT + 0.01),
             "text_white", root, c)
        gbox("Lamp_Rear_%d" % sx, (sx * (W - 0.45) - 0.08, 0.34, zr - 0.07), (sx * (W - 0.45) + 0.08, 0.44, zr - 0.06),
             "red", root, c)
    # A low cab on the port side, wholly ahead of the aircraft nose (CAB_Z0).
    gbox("Cab_Body", (0.0, DECK_TOP, CAB_Z0), (W - 0.22, CAB_GLASS_Y, zf - 0.05), "tug_yellow", root, c, bevel=0.03)
    gbox("Cab_Glass", (0.04, CAB_GLASS_Y, CAB_Z0 + 0.04), (W - 0.26, CAB_ROOF_Y, zf - 0.09), "window", root, c)
    gbox("Cab_Roof", (-0.03, CAB_ROOF_Y, CAB_Z0 - 0.03), (W - 0.19, CAB_ROOF_Y + 0.08, zf - 0.02), "white", root, c,
         bevel=0.02)
    gcyl_y("Beacon", (W - 0.22) / 2.0, (CAB_Z0 + zf) / 2.0, CAB_ROOF_Y + 0.08, TUG_TOP, 0.08, "text_yellow", root,
           c, segs=8)
    # Four small tyres, the outer faces at +-TUG_HALF_W.
    for sx in (-1, 1):
        for name, z in (("Rear", TYRE_Z[0]), ("Front", TYRE_Z[1])):
            x0, x1 = sorted((sx * (W - 0.24), sx * W))
            gcyl_x("Tyre_%s_%d" % (name, sx), x0, x1, TYRE_R, z, TYRE_R, "ink", root, c)
            hx0, hx1 = sorted((sx * (W - 0.23), sx * (W + 0.01)))
            gcyl_x("Hub_%s_%d" % (name, sx), hx0, hx1, TYRE_R, z, 0.14, "light_grey", root, c, segs=8)
    # The cradle on its lift pivot: a stop pad ahead of the wheel and a clamp gate
    # behind it, both clear of a resting wheel up to about 0.44 m radius (nothing sits
    # under the tyre, which touches the ground). Cradle_Lift translates up (Y).
    lift = pivot(p, "Cradle_Lift", root, c, (0.0, 0.0, 0.0))
    gbox("Cradle_Stop", (-S + 0.04, 0.07, z1 - 0.10), (S - 0.04, 0.42, z1), "ink", lift, c)
    gbox("Cradle_Gate", (-S, 0.14, zr), (S, 0.26, zr + 0.10), "ink", lift, c)
    pivot(p, "Mount_NoseGear", lift, c, (0.0, 0.0, 0.0))


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
# At rest: the drum roof on -x, the stair box's far end on +x, the exit door collar
# toward the terminal, the bellows' front along +z.
BRIDGE_LO = (-_rx, 0.0, COLLAR_Z0)
BRIDGE_HI = (BOX_END_X + 0.05, ROT_FLOOR + CAB_TOP + 0.13, HINGE_Z + CAB_Z + MOUNT_DOOR_Z)
TUG_LO = (-TUG_HALF_W - 0.01, 0.0, TUG_REAR - 0.07)
TUG_HI = (TUG_HALF_W + 0.01, TUG_TOP, TUG_FRONT + 0.01)
SIGN_LO = (-SIGN_HALF_W, 0.0, -FACE_Z - 0.024)
SIGN_HI = (SIGN_HALF_W, SIGN_Y[1], FACE_Z + 0.024)

PIECES = {
    "jet_bridge": (build_jet_bridge, (0, 0)) + blender_bounds(BRIDGE_LO, BRIDGE_HI),
    "pushback_tug": (build_pushback_tug, (0, 0)) + blender_bounds(TUG_LO, TUG_HI),
    "taxi_sign": (build_taxi_sign, (0, 0)) + blender_bounds(SIGN_LO, SIGN_HI),
}
EXTRA_NODES = {
    "jet_bridge": ["Tunnel_Yaw", "Tunnel_Yaw_Mesh", "Tunnel_Pitch", "Tunnel_Pitch_Mesh", "Tunnel_Slide",
                   "Tunnel_Slide_Mesh",
                   "Drive_Level", "Drive_Level_Mesh", "Drive_Foot", "Drive_Foot_Mesh", "Cab_Level", "Cab_Yaw",
                   "Cab_Yaw_Mesh", "Mount_Door", "StairBox", "StairBox_Mesh"] + WALK_MOUNTS,
    "pushback_tug": ["Cradle_Lift", "Cradle_Lift_Mesh", "Mount_NoseGear"],
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
            "cab_z=%.2f drive_z=%.2f tun_b_sink=%.2f tug_front=%.2f tug_rear=%.2f deck_top=%.2f cab_z0=%.2f"
            % (REACH_MIN, REACH_MAX, MOUNT_DOOR_Z, SLIDE_MAX, ROT_FLOOR, HINGE_Z, CAB_Z, DRIVE_Z, TUN_B_SINK, TUG_FRONT,
               TUG_REAR, DECK_TOP, CAB_Z0))
    kit.log("STAIRBOX root_out=%.2f exit_x=%.2f link_z=%.2f box_z=%.2f..%.2f box_top=%.2f stair_foot_x=%.2f "
            "stair_top_x=%.2f risers=%d rise=%.4f tread=%.2f box_end_x=%.2f link_end_x=%.2f"
            % (ROOT_OUT, EXIT_X, LINK_Z, BOX_Z0, BOX_Z1, BOX_TOP, STAIR_FOOT_X, STAIR_TOP_X, RISERS, RISE, TREAD,
               BOX_END_X, LINK_END_X))
    walk_report(written)


def walk_report(written):
    """Re-read the written jet_bridge.glb: every walk mount's parent chain and its
    position in the root's frame at rest (tunnel along +z, level, retracted)."""
    for piece, out in written:
        if piece != "jet_bridge":
            continue
        js, _n = kit.parse_glb(out)
        nodes = js.get("nodes", [])
        parent = {ch: i for i, nd in enumerate(nodes) for ch in nd.get("children", [])}
        by_name = {nd.get("name"): i for i, nd in enumerate(nodes)}
        for name in WALK_MOUNTS + ["Mount_Door"]:
            i = by_name.get(name)
            if i is None:
                kit.fail("jet_bridge: walk mount %s missing from the written file" % name)
                continue
            at = Vector((0.0, 0.0, 0.0))
            chain = []
            while i is not None:
                at += Vector(nodes[i].get("translation", [0.0, 0.0, 0.0]))
                chain.append(nodes[i].get("name"))
                i = parent.get(i)
            kit.log("WALK %-17s rest_root=(%.3f, %.3f, %.3f) chain=%s"
                    % (name, at.x, at.y, at.z, "/".join(reversed(chain))))


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
