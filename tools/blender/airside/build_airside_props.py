"""Build the airside props (board 4c08b8e5, Runway R11) and export one .glb each.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\build_airside_props.py' [-- piece ...]

Pieces (written to game/assets/airside/props/<piece>.glb):
- jet_bridge: a nose-loader (pedestal) passenger bridge at a gate's exit door (board
  0adca5c6; rulings jet-bridges-are-nose-loader-pedestal-bridges-an-enclosed-wal,
  nose-loader-bridge-design-stair-landing-and-cab-share-one-fl and plane-03-boards-
  on-foot-from-the-apron-plane-04-docks-the-no). Visual only.
- pushback_tug: a low towbarless tug (user ruling 2026-11-07) that cradles the nose
  wheel in a slot at its rear and runs forward under and past the nose; its origin
  and Mount_NoseGear are the nose wheel's ground contact, and Cradle_Lift raises the
  cradle along Y.
- taxi_sign: a two-panel taxiway sign on short legs: a location panel (yellow letter
  and border on black) and a direction panel (black letter and arrow on yellow). Every
  glyph is its own node, so the wiring shows one letter per panel and one arrow.
- airstairs: a mobile low-poly Toon airstairs unit (decisions 94ae5894, 710a78b4) on
  four tyres and grounded stabilizer pads, with an articulated/telescopic upper flight
  bridging port (+X) aircraft door sills from 0.63 m (04a) to 2.91 m (07a). Rests in
  the .glb at ~1.58 m medium sill height (05a). Every pivot exports with zero rest
  rotation; Stair_Pivot pitches the stair beam, Upper_Stairs slides along the beam
  direction, Top_Platform and Step_L_*/Step_U_* counter-rotate to stay level, and
  Lift_Base/Lift_Rod keep the twin hydraulic rams pinned between chassis and Lower_Stairs.

The builder reuses tools/blender/interior/build_interior_kit.py: its box and cylinder
helpers, the measured palette atlas swatches (every face on one swatch of
TP_Atlas_1A_D or TP_Atlas_Lights_1A_D, glass on TP_Glass_1A_D; material names exactly
the ones game/assets/toon_post_import.gd binds), its export and its verify_written()
re-read of the WRITTEN file (materials, zero images, node names, world bounds, UVs
inside their swatches). check_rig() then re-reads each written GLB's node tree and
checks every pivot's parent, rest translation and rest rotation against the constants
here, and walk_report() prints every walk mount from the written file.

Axes. Every dimension below is in Godot axes (x right, y up, z = the piece's front),
converted once by gb()/gbox(): Blender x = Godot x, Blender y = -Godot z, Blender z =
Godot y. Each piece's origin is on the ground.

Jet bridge. The root is the exit door's sill on the terminal's wall line; +z points
out from the wall (JetBridgePose.root_for() turns the root 180 degrees, so +z is north
and +x is west, toward the plane's port door). A glazed vestibule stands on the exit
door with a ground-floor apron door on its west side (plane 03's passengers walk out of
it). A glazed stair enclosure runs straight out from it; the stair rises to a short
level landing on a pedestal and the cab stands at the landing's end. The stair, the
landing and the cab share one floor height H, the docked plane's door sill (0.63 to
2.91 m): the stair keeps its tread count and its rise per step is H / RISERS. The cab
turns to face the plane door and its bellows reach the door sill; its roof top is
H + CAB_TOP (2.25 m), 2.1 m inside. All walls carry real window openings with glass.
Rig (all empties export with zero rest rotation and unit scale):
  JetBridge_ROOT
    JetBridge_Body        the collar at the exit door and the vestibule (static)
    Mount_ExitSill        (0, 0, 0): the exit door's sill on the wall line
    Mount_ApronDoor       (VEST_HALF, 0, APRON_Z): the vestibule's apron door, outside
    Vest_Full             (0, 0, 0): never moves; its mesh is the full-height vestibule
                          (walls, front, ring, roof), hidden while folded
    Fold_Cap              (0, 0, 0): never moves; its mesh is the folded box, the
                          vestibule's ground floor FOLD_TOP high with the exit and
                          apron doors, shown only while folded (board b564cda3)
    Walk_Slide           (0, 0, 0): translate along +z by D in [0, SLIDE_MAX], so the
                          cab reaches a plane door further out (model 04); its mesh is
                          the stair enclosure, its ground floor and the pedestal base under the cab
      Mount_StairFoot     (0, 0, STAIR_Z0 - STEP_OFF): before the first step
      Stair_Rise          (0, 0, 0): scale y = H; its mesh is the stair for a 1 m rise
                          and the cab's pedestal post
      Curtain_Low         (0, 0, LANDING_END - CURTAIN_T): scale y = H - CURTAIN_GAP;
                          closes the enclosure's open end under the cab
      Floor_Lift          (0, 0, 0): translate y = H; its mesh is the landing
        Mount_StairTop    (0, 0, STAIR_Z1 + STEP_OFF): past the top step
        Curtain_High      (0, CAB_IN + CURTAIN_GAP, LANDING_END - CURTAIN_T): scale y =
                          BOX_TOP - SKIN_T - H - (CAB_IN + CURTAIN_GAP), at least
                          CURTAIN_MIN; closes the enclosure's open end over the cab
        Cab_Yaw           (0, 0, CAB_Z): rotate about y to face the door; its mesh is
                          the cab, entered from its +x side
          Mount_CabFloor  (0, 0, 0): the cab floor's centre
          Bellows_Extend  (0, 0, 0): translate along +z by E in [E_MIN, E_MAX]; its mesh
                          is the bellows
            Mount_Door    (0, 0, MOUNT_DOOR_Z): the bellows' front at floor level; the
                          wiring puts it on the plane's door sill
JetBridgePose (game/airside/jet_bridge_pose.gd) solves D, H, the cab yaw and E from the
door and its normal, and returns every walk mount in world space.
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
    "navy": ("TP_Atlas_1A_D", 30, 5, 0.50, 0.0),
})

# ---------------------------------------------------------------- jet bridge
SKIN_T = 0.08           # wall, roof and end-wall thickness of every hollow part
COLLAR_GAP = 0.16       # the exit door collar stops this short of the wall line
COLLAR_TOP = 2.25       # under the terminal roof's fascia (0.25 m out, 2.3 m up)
COLLAR_DOOR_TOP = 2.12
DOOR_HALF = 0.55        # the exit door opening
DOOR_OPEN_TOP = 2.30
BOX_GAP = 0.30          # the vestibule's terminal face off the wall line
VEST_HALF = 1.10        # the vestibule's outer half width
VEST_END = 2.30         # the vestibule's far end, out from the wall
VEST_TOP = 5.30
FOLD_TOP = 2.50          # the folded box's roof top: the vestibule's ground floor
FOLD_WIN = (0.90, 2.00)  # its one window row
APRON_Z = 0.80          # the apron door's middle, out from the wall: the walk to it stays
                        # short of the first riser (STAIR_Z0)
APRON_HALF = 0.40
APRON_TOP = 2.20
BOX_HALF = 1.00         # the sliding stair enclosure's outer half width
BOX_Z0 = BOX_GAP        # its near end, inside the vestibule
BOX_TOP = 5.20          # its roof top: under plane 04's rotor disc (5.46 m)
RISERS = 16
TREADS = RISERS - 1
TREAD = 0.25
STAIR_Z0 = 0.80
STAIR_Z1 = STAIR_Z0 + TREADS * TREAD
STEP_OFF = 0.10         # the stair mounts stand this far off the first and last riser
CAB_HALF = 1.50
CAB_Z = 6.30            # the cab pivot at D = 0
LANDING_END = CAB_Z - CAB_HALF
CAB_IN = 2.10           # the cab's inside height and its door openings
CAB_TOP = 2.25          # the cab's roof top above its floor
CAB_LOW = 0.30          # the cab's underside below its floor
# The pedestal post stands under the cab's near side, clear of plane 03's wing (its
# leading edge 6.0 m out, under the parked cab).
POST_Z = CAB_Z - 1.10
BELLOWS_D = 0.60
MOUNT_DOOR_Z = CAB_HALF + BELLOWS_D
CURTAIN_T = 0.04
CURTAIN_GAP = 0.10
CURTAIN_MIN = 0.01
SLIDE_MAX = 1.90
E_MIN, E_MAX = -0.15, 0.30
H_MIN, H_MAX = 0.63, 2.91
H_PARK = 3.05           # parked: over plane 03's wing (2.57 m), under 04's rotor (5.46 m)
WIN_LOW = (0.90, 2.90)
WIN_HIGH = (3.10, 4.90)
# The walk from the exit door to the plane door, in walk order, and plane 03's way
# out to the apron.
WALK_MOUNTS = ["Mount_ExitSill", "Mount_StairFoot", "Mount_StairTop", "Mount_CabFloor", "Mount_Door"]
APRON_MOUNTS = ["Mount_ExitSill", "Mount_ApronDoor"]

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

# ---------------------------------------------------------------- airstairs
# Mobile Toon airstairs unit: +z is toward the aircraft door (Mount_TopDoor), -z is the
# rear ground entry (Mount_BottomEntry). Built in the 05a medium rest pose (1.58 m).
AS_HALF_W = 0.88
AS_BODY_HALF = 0.84
AS_PAD_OUT = 1.00
AS_TYRE_R = 0.27
AS_TYRE_Z = (-1.05, 1.05)
AS_Z_REAR = -1.92
AS_Z_FRONT = 1.54
AS_PIVOT_Y = 0.14
AS_PIVOT_Z = -1.25
AS_REST_DEG = 28.0
AS_REST_RAD = math.radians(AS_REST_DEG)
AS_REST_SLIDE = 0.59
AS_L_LOW = 2.15
AS_L_UP = 2.15
AS_UPPER_N = 0.175
AS_PLAT_D = 0.96
AS_PLAT_HALF = 0.66
AS_RAIL_H = 0.94
AS_STEPS = 7
AS_STEP_SP = 0.29
AS_STEP_FIRST = 0.14
AS_LIFT_A = (0.0, 0.16, 0.95)
AS_LIFT_B_S = 1.20
AS_LIFT_B_N = -0.06
AS_LIFT_BARREL = 0.90
AS_LIFT_ROD = 0.85
AS_H_REST = (AS_PIVOT_Y + (AS_REST_SLIDE + AS_L_UP) * math.sin(AS_REST_RAD)
             + AS_UPPER_N * math.cos(AS_REST_RAD))
AS_Z_HINGE_REST = (AS_PIVOT_Z + (AS_REST_SLIDE + AS_L_UP) * math.cos(AS_REST_RAD)
                   - AS_UPPER_N * math.sin(AS_REST_RAD))
AS_Z_DOOR_REST = AS_Z_HINGE_REST + AS_PLAT_D

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


# ---------------------------------------------------------------- jet bridge


def glazed_walls(name, half, z0, z1, y_top, holes_by_side, pal, parent, c, rows=None):
    """The two long walls (x = +-half, thickness SKIN_T inward) from z0 to z1, ground to
    y_top, each with `rows` of windows (WIN_LOW and WIN_HIGH unless given) plus that side's extra holes
    (holes_by_side[+1] for +x, [-1] for -x)."""
    spans = panels(z0 + 0.15, z1 - 0.1, 0.9, 0.15)
    for sx in (-1, 1):
        holes = list(holes_by_side.get(sx, []))
        blocked = [(h[0], h[1]) for h in holes]
        for v0, v1 in rows or (WIN_LOW, WIN_HIGH):
            for a, b in spans:
                # A window that would meet an extra opening stays shut.
                if v0 < APRON_TOP and any(a < hb and b > ha for ha, hb in blocked):
                    continue
                holes.append((a, b, v0, v1, True))
        x0, x1 = sorted((sx * (half - SKIN_T), sx * half))
        holed_wall("%s_%d" % (name, sx), "x", (z0, z1), (0.0, y_top), (x0, x1), holes, pal, parent, c)


def build_jet_bridge(root, c):
    p = "jet_bridge"
    pivot(p, "Mount_ExitSill", root, c, (0.0, 0.0, 0.0))
    pivot(p, "Mount_ApronDoor", root, c, (VEST_HALF, 0.0, APRON_Z))
    # The collar at the exit door, under the roof fascia.
    for sx in (-1, 1):
        x0, x1 = sorted((sx * DOOR_HALF, sx * (DOOR_HALF + 0.15)))
        gbox("Collar_%d" % sx, (x0, 0.0, COLLAR_GAP), (x1, COLLAR_TOP, BOX_GAP), "frame", root, c)
    gbox("Collar_Top", (-DOOR_HALF, COLLAR_DOOR_TOP, COLLAR_GAP), (DOOR_HALF, COLLAR_TOP, BOX_GAP), "frame", root, c)
    # The vestibule: a glazed box over the exit door, the apron door on its +x (west)
    # side, its far end a frame round the sliding stair enclosure. Its walls and roof
    # hang on Vest_Full, hidden while the bridge is folded; its floor and base bands
    # stay on the root, shared with the folded box.
    full = pivot(p, "Vest_Full", root, c, (0.0, 0.0, 0.0))
    vtop = VEST_TOP - SKIN_T
    apron = (APRON_Z - APRON_HALF, APRON_Z + APRON_HALF, 0.0, APRON_TOP, False)
    glazed_walls("Vest_Wall", VEST_HALF, BOX_GAP, VEST_END, vtop, {1: [apron]}, "white", full, c)
    holed_wall("Vest_Front", "z", (-VEST_HALF, VEST_HALF), (0.0, vtop), (BOX_GAP, BOX_GAP + SKIN_T),
               [(-DOOR_HALF, DOOR_HALF, 0.0, DOOR_OPEN_TOP, False), (-0.5, 0.5, WIN_HIGH[0], WIN_HIGH[1], True)],
               "white", full, c)
    holed_wall("Vest_Ring", "z", (-VEST_HALF, VEST_HALF), (0.0, vtop), (VEST_END - SKIN_T, VEST_END),
               [(-BOX_HALF - 0.01, BOX_HALF + 0.01, 0.0, BOX_TOP + 0.01, False)], "white", full, c)
    gbox("Vest_Roof", (-VEST_HALF - 0.04, vtop, BOX_GAP), (VEST_HALF + 0.04, VEST_TOP, VEST_END + 0.04), "light_grey",
         full, c)
    gbox("Vest_Floor", (-VEST_HALF + SKIN_T, 0.0, BOX_GAP + SKIN_T), (VEST_HALF - SKIN_T, 0.02, VEST_END - SKIN_T),
         "floor", root, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * VEST_HALF, sx * (VEST_HALF + 0.02)))
        # The band stops either side of the apron door, so its sill is level.
        spans = [(BOX_GAP, VEST_END)] if sx < 0 else [(BOX_GAP, APRON_Z - APRON_HALF),
                                                      (APRON_Z + APRON_HALF, VEST_END)]
        for k, (z0, z1) in enumerate(spans):
            gbox("Vest_Band_%d_%d" % (sx, k), (x0, 0.0, z0), (x1, 0.12, z1), "blue", root, c)
    # The folded box (board b564cda3; ruling small-planes-the-jet-bridge-folds-back-
    # against-the-terminal, v2): the vestibule's ground floor alone, FOLD_TOP high, with
    # the same exit and apron doors, one low window row and a closed far end. Shown only
    # while the walkway is drawn retracted (JetBridgePose.apply() hides Walk_Slide and
    # Vest_Full then).
    cap = pivot(p, "Fold_Cap", root, c, (0.0, 0.0, 0.0))
    ftop = FOLD_TOP - SKIN_T
    glazed_walls("Fold_Wall", VEST_HALF, BOX_GAP, VEST_END, ftop, {1: [apron]}, "white", cap, c, rows=(FOLD_WIN,))
    holed_wall("Fold_Front", "z", (-VEST_HALF, VEST_HALF), (0.0, ftop), (BOX_GAP, BOX_GAP + SKIN_T),
               [(-DOOR_HALF, DOOR_HALF, 0.0, DOOR_OPEN_TOP, False)], "white", cap, c)
    end_win = panels(-VEST_HALF + SKIN_T + 0.1, VEST_HALF - SKIN_T - 0.1, 0.9, 0.15)
    holed_wall("Fold_End", "z", (-VEST_HALF, VEST_HALF), (0.0, ftop), (VEST_END - SKIN_T, VEST_END),
               window_row(end_win, *FOLD_WIN), "white", cap, c)
    gbox("Fold_Roof", (-VEST_HALF - 0.04, ftop, BOX_GAP), (VEST_HALF + 0.04, FOLD_TOP, VEST_END + 0.04), "light_grey",
         cap, c)

    # The sliding stair enclosure, its ground floor and the pedestal base. Walk_Slide is
    # hidden whenever the apron door is used (Fold_Cap shows instead), so Box_Wall has no
    # apron cutout that would slide outside Vest_Wall on low-sill docks (04a), and Box_Band
    # extends back by SLIDE_MAX inside Vest_Wall so no baseboard gap appears when slid out.
    slide = pivot(p, "Walk_Slide", root, c, (0.0, 0.0, 0.0))
    pivot(p, "Mount_StairFoot", slide, c, (0.0, 0.0, STAIR_Z0 - STEP_OFF))
    btop = BOX_TOP - SKIN_T
    glazed_walls("Box_Wall", BOX_HALF, BOX_Z0, LANDING_END, btop, {}, "white", slide, c)
    gbox("Box_Roof", (-BOX_HALF, btop, BOX_Z0), (BOX_HALF, BOX_TOP, LANDING_END), "light_grey", slide, c)
    inner = BOX_HALF - SKIN_T
    gbox("Box_Floor", (-inner, 0.0, BOX_Z0), (inner, 0.03, STAIR_Z0), "floor", slide, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * BOX_HALF, sx * (BOX_HALF + 0.02)))
        gbox("Box_Band_%d" % sx, (x0, 0.0, VEST_END - SLIDE_MAX), (x1, 0.12, LANDING_END), "blue", slide, c)
    gbox("Pedestal_Base", (-0.35, 0.0, POST_Z - 0.35), (0.35, 0.25, POST_Z + 0.35), "concrete", slide, c)

    # The stair, built for a 1 m rise and scaled to H by Stair_Rise.
    rise = pivot(p, "Stair_Rise", slide, c, (0.0, 0.0, 0.0))
    for i in range(1, RISERS):
        z0 = STAIR_Z0 + (i - 1) * TREAD
        gbox("Step_%02d" % i, (-inner, 0.0, z0), (inner, i / float(RISERS), z0 + TREAD), "metal", rise, c)
    # The pedestal post under the cab's near side scales with the stair from the ground to
    # 0.95 H, inside the cab's floor band (H - 0.30 to H - 0.08) at every height.
    gbox("Pedestal_Post", (-0.18, 0.0, POST_Z - 0.18), (0.18, 0.95, POST_Z + 0.18), "concrete", rise, c)

    # The curtains close the enclosure's open end under and over the cab.
    low = pivot(p, "Curtain_Low", slide, c, (0.0, 0.0, LANDING_END - CURTAIN_T))
    gbox("Curtain_Low_Panel", (-inner, 0.0, -CURTAIN_T), (inner, 1.0, CURTAIN_T), "white", low, c)

    lift = pivot(p, "Floor_Lift", slide, c, (0.0, 0.0, 0.0))
    pivot(p, "Mount_StairTop", lift, c, (0.0, 0.0, STAIR_Z1 + STEP_OFF))
    gbox("Landing", (-inner, -0.25, STAIR_Z1), (inner, 0.0, LANDING_END), "metal", lift, c)
    high = pivot(p, "Curtain_High", lift, c, (0.0, CAB_IN + CURTAIN_GAP, LANDING_END - CURTAIN_T))
    gbox("Curtain_High_Panel", (-inner, 0.0, -CURTAIN_T), (inner, 1.0, CURTAIN_T), "white", high, c)

    # The cab: hollow, entered from its +x side, its front (+z) open into the bellows.
    cab = pivot(p, "Cab_Yaw", lift, c, (0.0, 0.0, CAB_Z))
    pivot(p, "Mount_CabFloor", cab, c, (0.0, 0.0, 0.0))
    k = CAB_HALF
    wall_top = CAB_IN + 0.07
    gbox("Cab_Floor", (-k, -0.08, -k), (k, 0.0, k), "metal", cab, c)
    gbox("Cab_Band", (-k - 0.02, -CAB_LOW, -k - 0.02), (k + 0.02, -0.08, k + 0.02), "blue", cab, c)
    gbox("Cab_Ceiling", (-k, CAB_IN, -k), (k, wall_top, k), "white", cab, c)
    gbox("Cab_Roof", (-k - 0.05, wall_top, -k - 0.05), (k + 0.05, CAB_TOP, k + 0.05), "light_grey", cab, c,
         bevel=0.02)
    window = (1.0, 1.9)
    door = (-0.9, 0.9, 0.0, CAB_IN, False)
    holed_wall("Cab_Entry", "x", (-k, k), (0.0, wall_top), (k - SKIN_T, k), [door], "white", cab, c)
    holed_wall("Cab_Side", "x", (-k, k), (0.0, wall_top), (-k, -k + SKIN_T), [(-1.1, 1.1) + window + (True,)],
               "white", cab, c)
    holed_wall("Cab_Back", "z", (-k + SKIN_T, k - SKIN_T), (0.0, wall_top), (-k, -k + SKIN_T),
               [(-1.1, 1.1) + window + (True,)], "white", cab, c)
    holed_wall("Cab_Front", "z", (-k + SKIN_T, k - SKIN_T), (0.0, wall_top), (k - SKIN_T, k), [door], "white", cab, c)
    # The bellows: five accordion folds round the door opening, on Bellows_Extend.
    bel = pivot(p, "Bellows_Extend", cab, c, (0.0, 0.0, 0.0))
    step = BELLOWS_D / 5.0
    for i in range(5):
        z0 = k + i * step
        e = 0.0 if i % 2 == 0 else 0.08
        holed_wall("Bellows_%d" % i, "z", (-1.42 + e, 1.42 - e), (-0.28 + e, CAB_IN + 0.10 - e), (z0, z0 + step),
                   [door], "ink" if i % 2 == 0 else "dark", bel, c)
    pivot(p, "Mount_Door", bel, c, (0.0, 0.0, MOUNT_DOOR_Z))


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


# ---------------------------------------------------------------- airstairs


def _beam_pt(s, n, ox=0.0):
    """Godot (x, y, z) from stair beam coordinate (s along slope, n perpendicular up) in
    Stair_Pivot local space (rest angle AS_REST_RAD)."""
    ca, sa = math.cos(AS_REST_RAD), math.sin(AS_REST_RAD)
    return (ox, s * sa + n * ca, s * ca - n * sa)


def _beam_box(name, x0, x1, s0, s1, n0, n1, pal, parent, c, ox=0.0, oy=0.0, oz=0.0):
    """An oriented stair-beam box spanning [x0, x1] across and [s0, s1] x [n0, n1] in the
    beam plane, shifted by (ox, oy, oz) in Godot axes."""
    bm = bmesh.new()
    verts = []
    for x in (x0, x1):
        for s in (s0, s1):
            for n in (n0, n1):
                px, py, pz = _beam_pt(s, n, x)
                verts.append(bm.verts.new(gb(px + ox, py + oy, pz + oz)))
    faces = (
        (0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
        (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5),
    )
    for f in faces:
        bm.faces.new([verts[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def _beam_cyl(name, x, s, n0, n1, r, pal, parent, c, segs=8, ox=0.0, oy=0.0, oz=0.0):
    """A cylinder along the beam normal (a stanchion post) centred on (x, s) from n0 to n1."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=n1 - n0)
    # Default cone is along Blender Z (= Godot Y). Rotate in Blender YZ (about X) by -AS_REST_RAD
    # so Blender Z aligns with beam normal N (Godot y=cos, z=-sin -> Blender y=sin, z=cos).
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-AS_REST_RAD, 3, "X"))
    px, py, pz = _beam_pt(s, (n0 + n1) / 2.0, x)
    bmesh.ops.translate(bm, vec=Vector(gb(px + ox, py + oy, pz + oz)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def _pin_cyl(name, x, p0, p1, r, pal, parent, c, segs=10):
    """A cylinder spanning from Godot (x, p0[0], p0[1]) to (x, p1[0], p1[1]) where p=(y, z)."""
    dy, dz = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dy, dz)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=length)
    # Tilt Blender +Z (Godot +Y) toward (dy, dz): in Blender (y=-z, z=y), angle around X from +Z.
    tilt = math.atan2(dz, dy)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-tilt, 3, "X"))
    my, mz = (p0[0] + p1[0]) / 2.0, (p0[1] + p1[1]) / 2.0
    bmesh.ops.translate(bm, vec=Vector(gb(x, my, mz)), verts=bm.verts)
    return kit._finish_mesh(name, bm, pal, parent, c)


def _add_step(piece, name, w_half, at_g, parent, c):
    """One level tread pivot with metal tread plate and yellow anti-slip nosing."""
    sp = pivot(piece, name, parent, c, at_g)
    gbox(name + "_Plate", (-w_half, -0.035, -0.11), (w_half, 0.0, 0.085), "metal", sp, c)
    gbox(name + "_Nose", (-w_half, -0.032, 0.085), (w_half, 0.003, 0.115), "tug_yellow", sp, c)
    return sp


def build_airstairs(root, c):
    p = "airstairs"
    W, B = AS_HALF_W, AS_BODY_HALF
    pivot(p, "Mount_BottomEntry", root, c, (0.0, 0.0, AS_Z_REAR))
    # Rear ground entry ramp/threshold plate, side curb brackets and safety nose strip.
    gbox("Entry_Ramp", (-0.52, 0.0, AS_Z_REAR + 0.08), (0.52, 0.12, -1.32), "metal", root, c)
    gbox("Entry_Lip", (-0.52, 0.0, AS_Z_REAR), (0.52, 0.125, AS_Z_REAR + 0.08), "tug_yellow", root, c)
    # Rear entry side rails outboard of Lower_Stairs handrails, anchored cleanly to ground pad & Cowl_R.
    for sx in (-1, 1):
        x = sx * 0.68
        px0, px1 = sorted((sx * 0.52, sx * 0.73))
        gbox("Entry_Pad_%d" % sx, (px0, 0.0, AS_Z_REAR + 0.04), (px1, 0.12, -1.52), "dark", root, c)
        gcyl_y("Entry_PostA_%d" % sx, x, AS_Z_REAR + 0.12, 0.10, 0.90, 0.024, "metal", root, c, segs=8)
        gcyl_y("Entry_PostB_%d" % sx, x, -1.44, 0.54, 0.90, 0.024, "metal", root, c, segs=8)
        gbox("Entry_Rail_%d" % sx, (x - 0.024, 0.87, AS_Z_REAR + 0.08), (x + 0.024, 0.92, -1.40),
             "tug_yellow", root, c)

    # Low well chassis frame + side sponsons split around the front and rear wheel arches.
    gbox("Chassis_Cross_F", (-0.64, 0.08, 0.78), (0.64, 0.22, 1.46), "dark", root, c)
    gbox("Chassis_Cross_R", (-0.64, 0.06, -1.42), (0.64, 0.10, -1.29), "dark", root, c)
    gbox("Axle_F", (-0.70, AS_TYRE_R - 0.04, AS_TYRE_Z[1] - 0.05),
         (0.70, AS_TYRE_R + 0.04, AS_TYRE_Z[1] + 0.05), "dark", root, c)
    gbox("Axle_R", (-0.70, AS_TYRE_R - 0.04, AS_TYRE_Z[0] - 0.05),
         (0.70, AS_TYRE_R + 0.04, AS_TYRE_Z[0] + 0.05), "dark", root, c)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.64, sx * B))
        nx0, nx1 = sorted((sx * (B - 0.01), sx * (B + 0.015)))
        # Side cowls (front cap, mid sponson, rear cap, wheel arch brows).
        gbox("Cowl_F_%d" % sx, (x0, 0.16, 1.37), (x1, 0.64, 1.51), "white", root, c, bevel=0.02)
        gbox("Cowl_M_%d" % sx, (x0, 0.18, -0.73), (x1, 0.66, 0.73), "white", root, c, bevel=0.02)
        gbox("Cowl_R_%d" % sx, (x0, 0.16, -1.52), (x1, 0.56, -1.37), "white", root, c, bevel=0.02)
        gbox("Fender_F_%d" % sx, (x0, 0.58, 0.73), (x1, 0.66, 1.37), "white", root, c, bevel=0.015)
        gbox("Fender_R_%d" % sx, (x0, 0.57, -1.37), (x1, 0.65, -0.73), "white", root, c, bevel=0.015)
        # Airline navy livery stripe on side cowls.
        gbox("Stripe_M_%d" % sx, (nx0, 0.36, -0.71), (nx1, 0.48, 0.71), "navy", root, c)
        gbox("Stripe_F_%d" % sx, (nx0, 0.36, 1.38), (nx1, 0.48, 1.49), "navy", root, c)
        # Four tyres and hubcaps.
        for wname, wz in (("R", AS_TYRE_Z[0]), ("F", AS_TYRE_Z[1])):
            tx0, tx1 = sorted((sx * (W - 0.22), sx * W))
            gcyl_x("Tyre_%s_%d" % (wname, sx), tx0, tx1, AS_TYRE_R, wz, AS_TYRE_R, "ink", root, c)
            hx0, hx1 = sorted((sx * (W - 0.21), sx * (W + 0.01)))
            gcyl_x("Hub_%s_%d" % (wname, sx), hx0, hx1, AS_TYRE_R, wz, 0.13, "light_grey", root, c, segs=8)
        # Four grounded stabilizer outriggers + yellow jack pads.
        for pname, pz in (("R", -1.45), ("F", 1.43)):
            ax0, ax1 = sorted((sx * 0.74, sx * 0.95))
            gbox("Jack_Arm_%s_%d" % (pname, sx), (ax0, 0.18, pz - 0.05), (ax1, 0.26, pz + 0.05), "dark", root, c)
            gcyl_y("Jack_Leg_%s_%d" % (pname, sx), sx * 0.92, pz, 0.04, 0.26, 0.04, "metal", root, c, segs=8)
            px0, px1 = sorted((sx * 0.84, sx * AS_PAD_OUT))
            gbox("Jack_Pad_%s_%d" % (pname, sx), (px0, 0.0, pz - 0.09), (px1, 0.04, pz + 0.09),
                 "tug_yellow", root, c)

    # Front bumper, headlights, rear tail lamps, operator console and amber safety beacon.
    gbox("Bumper_F", (-B, 0.14, 1.49), (B, 0.28, AS_Z_FRONT), "tug_yellow", root, c, bevel=0.02)
    for sx in (-1, 1):
        cx0, cx1 = sorted((sx * (B - 0.16), sx * (B + 0.02)))
        gbox("Bumper_F_Corner_%d" % sx, (cx0, 0.13, 1.46), (cx1, 0.29, AS_Z_FRONT + 0.01), "ink", root, c)
        gbox("Headlight_%d" % sx, (sx * 0.74 - 0.07, 0.42, 1.51), (sx * 0.74 + 0.07, 0.50, 1.52),
             "text_white", root, c)
        gbox("Taillight_%d" % sx, (sx * 0.74 - 0.06, 0.36, -1.53), (sx * 0.74 + 0.06, 0.44, -1.52),
             "red", root, c)
    gbox("Console_Base", (0.65, 0.66, 0.18), (0.83, 0.92, 0.54), "navy", root, c, bevel=0.01)
    gbox("Console_Top", (0.64, 0.92, 0.17), (0.84, 0.97, 0.55), "dark", root, c)
    gbox("Console_Btn_G", (0.71, 0.97, 0.26), (0.77, 1.00, 0.32), "lamp_green", root, c)
    gbox("Console_Btn_R", (0.71, 0.97, 0.40), (0.77, 1.00, 0.46), "red", root, c)
    gcyl_y("Beacon_Stem", 0.74, 1.24, 0.66, 0.74, 0.03, "dark", root, c, segs=8)
    gcyl_y("Beacon", 0.74, 1.24, 0.74, 0.86, 0.065, "text_yellow", root, c, segs=8)

    # Hydraulic lift cylinder barrels (Lift_Base on root) and piston rods (Lift_Rod on Lower_Stairs).
    ax, ay, az = AS_LIFT_A
    _, by_rel, bz_rel = _beam_pt(AS_LIFT_B_S, AS_LIFT_B_N)
    by, bz = AS_PIVOT_Y + by_rel, AS_PIVOT_Z + bz_rel
    dy, dz = by - ay, bz - az
    dist = math.hypot(dy, dz)
    uy, uz = dy / dist, dz / dist
    lift_base = pivot(p, "Lift_Base", root, c, AS_LIFT_A)
    for sx in (-1, 1):
        _pin_cyl("Lift_Barrel_%d" % sx, sx * 0.32, (0.0, 0.0), (uy * AS_LIFT_BARREL, uz * AS_LIFT_BARREL),
                 0.048, "dark", lift_base, c, segs=10)

    # Articulated stair assembly: Stair_Pivot -> Lower_Stairs -> Upper_Stairs -> Top_Platform.
    spiv = pivot(p, "Stair_Pivot", root, c, (0.0, AS_PIVOT_Y, AS_PIVOT_Z))
    low = pivot(p, "Lower_Stairs", spiv, c, (0.0, 0.0, 0.0))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.54, sx * 0.62))
        nx0, nx1 = sorted((sx * 0.615, sx * 0.63))
        _beam_box("Low_Stringer_%d" % sx, x0, x1, -0.02, AS_L_LOW, -0.05, 0.16, "white", low, c)
        _beam_box("Low_Trim_%d" % sx, nx0, nx1, 0.02, AS_L_LOW - 0.04, 0.01, 0.10, "navy", low, c)
        for k, s in enumerate((0.08, 0.72, 1.38, 2.02)):
            _beam_cyl("Low_Post_%d_%d" % (sx, k), sx * 0.58, s, 0.15, 0.94, 0.022, "metal", low, c, segs=8)
        _beam_box("Low_Rail_%d" % sx, sx * 0.58 - 0.024, sx * 0.58 + 0.024, 0.04, AS_L_LOW - 0.04,
                  0.92, 0.97, "tug_yellow", low, c)
    _beam_box("Low_Soffit", -0.54, 0.54, 0.0, AS_L_LOW - 0.04, -0.05, -0.02, "dark", low, c)
    _beam_box("Low_Lift_Beam", -0.40, 0.40, AS_LIFT_B_S - 0.08, AS_LIFT_B_S + 0.08, -0.08, -0.04,
              "dark", low, c)
    lift_rod = pivot(p, "Lift_Rod", low, c, (0.0, by_rel, bz_rel))
    for sx in (-1, 1):
        _pin_cyl("Lift_Piston_%d" % sx, sx * 0.32, (0.0, 0.0), (-uy * AS_LIFT_ROD, -uz * AS_LIFT_ROD),
                 0.032, "metal", lift_rod, c, segs=10)
    for i in range(AS_STEPS):
        _add_step(p, "Step_L_%02d" % (i + 1), 0.535, _beam_pt(AS_STEP_FIRST + i * AS_STEP_SP, 0.0), low, c)

    # Telescopic Upper_Stairs resting at AS_REST_SLIDE along Lower_Stairs beam.
    up_rest = _beam_pt(AS_REST_SLIDE, 0.0)
    up = pivot(p, "Upper_Stairs", low, c, up_rest)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.47, sx * 0.53))
        nx0, nx1 = sorted((sx * 0.525, sx * 0.538))
        _beam_box("Up_Stringer_%d" % sx, x0, x1, -0.02, AS_L_UP, 0.055, 0.28, "white", up, c)
        _beam_box("Up_Trim_%d" % sx, nx0, nx1, 0.02, AS_L_UP - 0.04, 0.11, 0.21, "navy", up, c)
        for k, s in enumerate((0.08, 0.75, 1.42, 2.08)):
            _beam_cyl("Up_Post_%d_%d" % (sx, k), sx * 0.50, s, 0.27, 1.10, 0.022, "metal", up, c, segs=8)
        _beam_box("Up_Rail_%d" % sx, sx * 0.50 - 0.024, sx * 0.50 + 0.024, 0.04, AS_L_UP + 0.18,
                  1.085, 1.135, "tug_yellow", up, c)
    _beam_box("Up_Soffit", -0.47, 0.47, 0.0, AS_L_UP - 0.02, 0.055, 0.095, "dark", up, c)
    for i in range(AS_STEPS):
        _add_step(p, "Step_U_%02d" % (i + 1), 0.465, _beam_pt(AS_STEP_FIRST + i * AS_STEP_SP, AS_UPPER_N),
                  up, c)

    # Self-leveling Top_Platform hinged at the top of Upper_Stairs.
    plat_at = _beam_pt(AS_L_UP, AS_UPPER_N)
    plat = pivot(p, "Top_Platform", up, c, plat_at)
    PH = AS_PLAT_HALF
    gbox("Plat_Deck", (-PH + 0.08, -0.08, -0.10), (PH - 0.08, 0.0, AS_PLAT_D - 0.05), "metal", plat, c)
    gbox("Plat_Lip", (-0.44, -0.03, AS_PLAT_D - 0.05), (0.44, 0.004, AS_PLAT_D), "tug_yellow", plat, c)
    gbox("Plat_Skirt_L", (-PH, -0.22, -0.10), (-PH + 0.08, 0.0, AS_PLAT_D - 0.05), "navy", plat, c)
    gbox("Plat_Skirt_R", (PH - 0.08, -0.22, -0.10), (PH, 0.0, AS_PLAT_D - 0.05), "navy", plat, c)
    gbox("Plat_Skirt_Rear", (-PH + 0.08, -0.22, -0.10), (PH - 0.08, -0.08, 0.04), "navy", plat, c)
    for sx in (-1, 1):
        rx = sx * 0.60
        for k, pz in enumerate((-0.44, 0.02, 0.46, AS_PLAT_D - 0.06)):
            y0 = 0.25 if pz < -0.1 else 0.0
            gcyl_y("Plat_Post_%d_%d" % (sx, k), rx, pz, y0, AS_RAIL_H, 0.024, "metal", plat, c, segs=8)
        gbox("Plat_Rail_Top_%d" % sx, (rx - 0.025, AS_RAIL_H - 0.04, -0.48),
             (rx + 0.025, AS_RAIL_H + 0.02, AS_PLAT_D - 0.02), "tug_yellow", plat, c)
        gbox("Plat_Rail_Mid_%d" % sx, (rx - 0.02, 0.46, 0.0),
             (rx + 0.02, 0.50, AS_PLAT_D - 0.06), "light_grey", plat, c)
        # Rear extension bracket connecting z=-0.44 post back to z=0.0 platform corner.
        gbox("Plat_Bracket_%d" % sx, (rx - 0.02, 0.24, -0.46), (rx + 0.02, 0.29, 0.02), "metal", plat, c)
        # Rubber docking bumpers at the front (+z) corners facing the aircraft skin.
        bx0, bx1 = sorted((sx * 0.44, sx * (PH + 0.02)))
        gbox("Dock_Bumper_Lo_%d" % sx, (bx0, -0.22, AS_PLAT_D - 0.05), (bx1, 0.02, AS_PLAT_D), "ink", plat, c)
        px0, px1 = sorted((sx * 0.56, sx * (PH + 0.02)))
        gbox("Dock_Bumper_Hi_%d" % sx, (px0, 0.02, AS_PLAT_D - 0.04), (px1, AS_RAIL_H - 0.02, AS_PLAT_D),
             "ink", plat, c)
    pivot(p, "Mount_TopDoor", plat, c, (0.0, 0.0, AS_PLAT_D))


# ---------------------------------------------------------------- tables


def blender_bounds(lo_g, hi_g):
    """Godot bounds -> the Blender bounds kit.verify_written compares."""
    return (lo_g[0], -hi_g[2], lo_g[1]), (hi_g[0], -lo_g[2], hi_g[1])


# At rest (D 0, the landing at y 0, a 1 m stair, the cab facing +z): the cab roof on x,
# the cab's underside below the landing, the vestibule roof on top, the collar toward
# the terminal and the bellows' front along +z.
BRIDGE_LO = (-CAB_HALF - 0.05, -CAB_LOW, COLLAR_GAP)
BRIDGE_HI = (CAB_HALF + 0.05, VEST_TOP, CAB_Z + MOUNT_DOOR_Z)
TUG_LO = (-TUG_HALF_W - 0.01, 0.0, TUG_REAR - 0.07)
TUG_HI = (TUG_HALF_W + 0.01, TUG_TOP, TUG_FRONT + 0.01)
SIGN_LO = (-SIGN_HALF_W, 0.0, -FACE_Z - 0.024)
SIGN_HI = (SIGN_HALF_W, SIGN_Y[1], FACE_Z + 0.024)
AIRSTAIRS_LO = (-AS_PAD_OUT, 0.0, AS_Z_REAR)
_AS_RAIL_TOP = max(
    AS_H_REST + AS_RAIL_H + 0.02,
    AS_PIVOT_Y + (AS_REST_SLIDE + AS_L_UP + 0.18) * math.sin(AS_REST_RAD) + 1.135 * math.cos(AS_REST_RAD),
)
AIRSTAIRS_HI = (AS_PAD_OUT, _AS_RAIL_TOP, AS_Z_DOOR_REST)

PIECES = {
    "jet_bridge": (build_jet_bridge, (0, 0)) + blender_bounds(BRIDGE_LO, BRIDGE_HI),
    "pushback_tug": (build_pushback_tug, (0, 0)) + blender_bounds(TUG_LO, TUG_HI),
    "taxi_sign": (build_taxi_sign, (0, 0)) + blender_bounds(SIGN_LO, SIGN_HI),
    "airstairs": (build_airstairs, (0, 0)) + blender_bounds(AIRSTAIRS_LO, AIRSTAIRS_HI),
}
EXTRA_NODES = {
    "jet_bridge": ["Walk_Slide", "Walk_Slide_Mesh", "Stair_Rise", "Stair_Rise_Mesh", "Curtain_Low",
                   "Curtain_Low_Mesh", "Floor_Lift", "Floor_Lift_Mesh", "Curtain_High", "Curtain_High_Mesh",
                   "Cab_Yaw", "Cab_Yaw_Mesh", "Bellows_Extend", "Bellows_Extend_Mesh", "Mount_ApronDoor",
                   "Fold_Cap", "Fold_Cap_Mesh", "Vest_Full", "Vest_Full_Mesh"]
    + WALK_MOUNTS,
    "pushback_tug": ["Cradle_Lift", "Cradle_Lift_Mesh", "Mount_NoseGear"],
    "taxi_sign": [n for ch in LETTERS for n in ("Glyph_Loc_" + ch, "Glyph_Loc_%s_Mesh" % ch,
                                                 "Glyph_Dir_" + ch, "Glyph_Dir_%s_Mesh" % ch)]
    + ["Glyph_Arrow_L", "Glyph_Arrow_L_Mesh", "Glyph_Arrow_R", "Glyph_Arrow_R_Mesh"],
    "airstairs": ["Mount_BottomEntry", "Lift_Base", "Lift_Base_Mesh", "Stair_Pivot", "Lower_Stairs",
                  "Lower_Stairs_Mesh", "Lift_Rod", "Lift_Rod_Mesh", "Upper_Stairs", "Upper_Stairs_Mesh",
                  "Top_Platform", "Top_Platform_Mesh", "Mount_TopDoor"]
    + [n for i in range(1, AS_STEPS + 1)
       for n in ("Step_L_%02d" % i, "Step_L_%02d_Mesh" % i, "Step_U_%02d" % i, "Step_U_%02d" % i + "_Mesh")],
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
    kit.log("BRIDGE risers=%d tread=%.2f stair_z=%.2f..%.2f landing_end=%.2f cab_z=%.2f cab_in=%.2f cab_top=%.2f "
            "mount_door_z=%.2f h=%.2f..%.2f h_park=%.2f slide_max=%.2f extend=%.2f..%.2f box_top=%.2f vest_top=%.2f"
            % (RISERS, TREAD, STAIR_Z0, STAIR_Z1, LANDING_END, CAB_Z, CAB_IN, CAB_TOP, MOUNT_DOOR_Z, H_MIN, H_MAX,
               H_PARK, SLIDE_MAX, E_MIN, E_MAX, BOX_TOP, VEST_TOP))
    kit.log("TUG tug_front=%.2f tug_rear=%.2f deck_top=%.2f cab_z0=%.2f" % (TUG_FRONT, TUG_REAR, DECK_TOP, CAB_Z0))
    walk_report(written)
    airstairs_report(written)


def airstairs_report(written):
    for piece, out in written:
        if piece != "airstairs":
            continue
        js, _n = kit.parse_glb(out)
        nodes = js.get("nodes", [])
        parent = {ch: i for i, nd in enumerate(nodes) for ch in nd.get("children", [])}
        by_name = {nd.get("name"): i for i, nd in enumerate(nodes)}
        for name in ("Mount_BottomEntry", "Stair_Pivot", "Lower_Stairs", "Upper_Stairs",
                     "Top_Platform", "Mount_TopDoor", "Lift_Base", "Lift_Rod"):
            i = by_name.get(name)
            if i is None:
                kit.fail("airstairs: node %s missing from the written file" % name)
                continue
            at = Vector((0.0, 0.0, 0.0))
            chain = []
            cur = i
            while cur is not None:
                at += Vector(nodes[cur].get("translation", [0.0, 0.0, 0.0]))
                chain.append(nodes[cur].get("name"))
                cur = parent.get(cur)
            kit.log("AIRSTAIRS %-18s rest_root=(%.4f, %.4f, %.4f) chain=%s"
                    % (name, at.x, at.y, at.z, "/".join(reversed(chain))))
        kit.log("AIRSTAIRS rest_h=%.4f rest_door_z=%.4f rest_deg=%.1f rest_slide=%.2f l_low=%.2f l_up=%.2f plat_d=%.2f"
                % (AS_H_REST, AS_Z_DOOR_REST, AS_REST_DEG, AS_REST_SLIDE, AS_L_LOW, AS_L_UP, AS_PLAT_D))


def walk_report(written):
    """Re-read the written jet_bridge.glb: every walk mount's parent chain and its
    position in the root's frame at rest (D 0, the landing at y 0, the cab facing +z)."""
    for piece, out in written:
        if piece != "jet_bridge":
            continue
        js, _n = kit.parse_glb(out)
        nodes = js.get("nodes", [])
        parent = {ch: i for i, nd in enumerate(nodes) for ch in nd.get("children", [])}
        by_name = {nd.get("name"): i for i, nd in enumerate(nodes)}
        for name in WALK_MOUNTS + APRON_MOUNTS[1:]:
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
            kit.log("WALK %-16s rest_root=(%.3f, %.3f, %.3f) chain=%s"
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
