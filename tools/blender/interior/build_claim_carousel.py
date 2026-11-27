"""Build claim_carousel.glb in the Toon Series interior kit.

Tier-2 compact 4x2 cell (4.0 m x 2.0 m) oval/racetrack baggage claim carousel.
Origin at footprint centre on the floor (y = 0), front facing Godot +Z
(Blender -Y), back facing Godot -Z (Blender +Y).

Geometry & Slice A1/A3 contracts (all in Godot metres, piece local frame):
- Footprint: 4x2 cells (x in [-2.0, +2.0], z in [-1.0, +1.0]).
- Furniture inset: 0.08 m on +X, -X, +Z and closed -Z edges; belt inlet port
  on cell (2, 0) side "B" extends cleanly to the -Z cell edge (z = -1.0) at
  x = +0.50 m matching baggage_belt.glb (BELT_TOP = 0.355 m, LANE = 0.35 m,
  HALF_IN = 0.42 m, RAIL_TOP = 0.46 m).
- Mount_Belt_B: pos = (0.5, 0.355, -1.0), yaw = 180.0 (facing -Z out of port).
- Belt_Surface: separate node spanning inlet lane [-0.35, +0.35] around x=+0.50
  up to z = -1.0 at y = 0.355 m.
- Track centerline (stadium/racetrack at constant height TRACK_Y = 0.355 m):
  - center = (0.0, 0.355, 0.0)
  - half_straight_x = 1.00 m (straights along x in [-1.00, +1.00] at z = +-0.61)
  - curve_radius = 0.61 m (semicircles centered at (-1.00, 0.355, 0.0) and (+1.00, 0.355, 0.0))
  - overall semi-axes: rx = 1.61 m, rz = 0.61 m, total path length = 7.8327 m.
  - Suitcases (baggage_bag.glb, 0.38 x 0.55 x 0.22 m) ride flat at y = 0.355 m
    and clear both the central island (r = 0.36 m) and outer bumper rail
    (r = 0.87..0.92 m, top 0.335 m) plus the tunnel arch (z_clear = 0.76 m).

Run from repo root (or worktree root):
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/build_claim_carousel.py < /dev/null
"""

import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402

PIECE = "claim_carousel"
FOOTPRINT = (4, 2)
INSET = 0.08
BLEND_OUT = str(
    Path(kit.REPO, "tools", "blender", "out", "claim-carousel", "claim_carousel.blend").resolve()
)

# Stadium track geometry (Blender X, Y with Y = -Godot Z)
HALF_STRAIGHT = 1.00
R_ISLAND = 0.36
R_TRACK_IN = 0.36
R_TRACK_CENTER = 0.61
R_TRACK_FLAT_OUT = 0.82
R_TRACK_APRON_OUT = 0.88
R_BUMPER_IN = 0.87
R_BUMPER_OUT = 0.92
R_BASE = 0.86
R_TOE = 0.81

TRACK_Y = bag.BELT_TOP  # 0.355 m (exact match to baggage_belt.glb!)
APRON_EDGE_Z = 0.312
BUMPER_Z0 = 0.24
BUMPER_Z1 = 0.335
ISLAND_TOP = 0.58
SIGN_Z0 = 1.44
SIGN_Z1 = 1.88

# Belt inlet port at cell (2, 0) side "B" -> Godot (+0.5, 0.355, -1.0)
INLET_X = 0.50
PORT_POS_GODOT = (INLET_X, TRACK_Y, -1.0)
PORT_YAW = 180.0

CAROUSEL_PALETTE = {
    "red": cafe.CAFE_PALETTE["red"],
    "slate_dark": ("TP_Atlas_1A_D", 18, 1, 0.40, 0.0),
    "steel_mid": ("TP_Atlas_1A_D", 11, 11, 0.35, 0.0),
    "pine_green": ("TP_Atlas_1A_D", 27, 1, 0.35, 0.0),
}


def _stadium_pts(r, n_arc=16, half_straight=HALF_STRAIGHT):
    """Closed CCW loop of 2D (x, y) points around a stadium along X."""
    pts = []
    # Right semicircle (+half_straight, 0), angle -90..+90
    for i in range(n_arc + 1):
        a = -math.pi / 2.0 + math.pi * i / n_arc
        pts.append((half_straight + r * math.cos(a), r * math.sin(a)))
    # Left semicircle (-half_straight, 0), angle +90..+270
    for i in range(n_arc + 1):
        a = math.pi / 2.0 + math.pi * i / n_arc
        pts.append((-half_straight + r * math.cos(a), r * math.sin(a)))
    return pts


def _stadium_prism(name, r0, r1, z0, z1, pal, parent, c, n_arc=16):
    """Solid prism from a stadium ring (if r0 > 0) or filled disc (if r0 == 0)."""
    bm = bmesh.new()
    if r0 <= 0.0:
        ring = _stadium_pts(r1, n_arc=n_arc)
        bot = [bm.verts.new((x, y, z0)) for x, y in ring]
        top = [bm.verts.new((x, y, z1)) for x, y in ring]
        n = len(ring)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bot[i], bot[j], top[j], top[i]))
        bm.faces.new(list(reversed(bot)))
        bm.faces.new(top)
    else:
        inner = _stadium_pts(r0, n_arc=n_arc)
        outer = _stadium_pts(r1, n_arc=n_arc)
        n = len(inner)
        vb0 = [bm.verts.new((x, y, z0)) for x, y in inner]
        vb1 = [bm.verts.new((x, y, z0)) for x, y in outer]
        vt1 = [bm.verts.new((x, y, z1)) for x, y in outer]
        vt0 = [bm.verts.new((x, y, z1)) for x, y in inner]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((vb0[i], vb1[i], vb1[j], vb0[j]))  # bottom
            bm.faces.new((vt0[i], vt0[j], vt1[j], vt1[i]))  # top
            bm.faces.new((vb1[i], vt1[i], vt1[j], vb1[j]))  # outer wall
            bm.faces.new((vb0[i], vb0[j], vt0[j], vt0[i]))  # inner wall
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def _stadium_ring_profile(name, profile, pal, parent, c, n_arc=16, skip_back_gap=None):
    """Sweep a closed cross-section profile [(r, z), ...] CCW around the stadium.

    If `skip_back_gap = (gx0, gx1)` is given, segments along the back straight
    (y > 0) whose midpoint x lies in [gx0, gx1] are omitted and capped cleanly,
    leaving an open slot for the belt inlet port.
    """
    bm = bmesh.new()
    # Build ordered path samples [(px, py, nx, ny)] with outward unit normal (nx, ny)
    samples = []
    # Right arc: (-90 -> +90)
    for i in range(n_arc + 1):
        a = -math.pi / 2.0 + math.pi * i / n_arc
        samples.append((HALF_STRAIGHT, 0.0, math.cos(a), math.sin(a)))
    # Back straight (+Y): subdivided cleanly if a gap is present
    if skip_back_gap is not None:
        gx0, gx1 = skip_back_gap
        xs = sorted({HALF_STRAIGHT, gx1, gx0, -HALF_STRAIGHT}, reverse=True)
        for x in xs[1:-1]:
            samples.append((x, 0.0, 0.0, 1.0))
    # Left arc: (+90 -> +270)
    for i in range(n_arc + 1):
        a = math.pi / 2.0 + math.pi * i / n_arc
        samples.append((-HALF_STRAIGHT, 0.0, math.cos(a), math.sin(a)))

    n_pts = len(samples)
    m_prof = len(profile)
    # Create segment spans skipping any back-straight span inside skip_back_gap
    spans = []
    for i in range(n_pts):
        j = (i + 1) % n_pts
        ax, ay, anx, any_ = samples[i]
        bx, by, bnx, bny_ = samples[j]
        if skip_back_gap is not None and any_ > 0.99 and bny_ > 0.99:
            mid_x = 0.5 * (ax + bx)
            if skip_back_gap[0] < mid_x < skip_back_gap[1]:
                continue
        spans.append((i, j))

    # Build contiguous runs from spans
    runs = []
    cur_run = []
    for i, j in spans:
        if not cur_run:
            cur_run = [i, j]
        elif cur_run[-1] == i:
            cur_run.append(j)
        else:
            runs.append(cur_run)
            cur_run = [i, j]
    if cur_run:
        if len(runs) > 1 and cur_run[-1] == runs[0][0]:
            runs[0] = cur_run[:-1] + runs[0]
        else:
            runs.append(cur_run)

    for run in runs:
        closed = run[0] == run[-1]
        ring_idx = run[:-1] if closed else run
        rings = []
        for idx in ring_idx:
            px, py, nx, ny = samples[idx]
            rings.append([bm.verts.new((px + nx * r, py + ny * r, z)) for r, z in profile])
        nr = len(rings)
        seg_count = nr if closed else nr - 1
        for s in range(seg_count):
            a = rings[s]
            b = rings[(s + 1) % nr]
            for k in range(m_prof):
                kn = (k + 1) % m_prof
                bm.faces.new((a[k], a[kn], b[kn], b[k]))
        if not closed:
            bm.faces.new(list(reversed(rings[0])))
            bm.faces.new(rings[-1])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._finish_mesh(name, bm, pal, parent, c)


def _track_samples(count=48):
    """Uniformly spaced (px, py, tx, ty, nx, ny) points around the stadium track centerline."""
    arc_len = math.pi * R_TRACK_CENTER
    straight_len = 2.0 * HALF_STRAIGHT
    total = 2.0 * straight_len + 2.0 * arc_len
    out = []
    for i in range(count):
        s = (i / count) * total
        if s < straight_len:
            x = -HALF_STRAIGHT + s
            out.append((x, -R_TRACK_CENTER, 1.0, 0.0, 0.0, -1.0))
        elif s < straight_len + arc_len:
            a = -math.pi / 2.0 + (s - straight_len) / R_TRACK_CENTER
            cx = HALF_STRAIGHT + R_TRACK_CENTER * math.cos(a)
            cy = R_TRACK_CENTER * math.sin(a)
            out.append((cx, cy, -math.sin(a), math.cos(a), math.cos(a), math.sin(a)))
        elif s < 2.0 * straight_len + arc_len:
            x = HALF_STRAIGHT - (s - straight_len - arc_len)
            out.append((x, R_TRACK_CENTER, -1.0, 0.0, 0.0, 1.0))
        else:
            a = math.pi / 2.0 + (s - 2.0 * straight_len - arc_len) / R_TRACK_CENTER
            cx = -HALF_STRAIGHT + R_TRACK_CENTER * math.cos(a)
            cy = R_TRACK_CENTER * math.sin(a)
            out.append((cx, cy, -math.sin(a), math.cos(a), math.cos(a), math.sin(a)))
    return out


def _slat_ribs(root, c):
    """48 crisp rubber slat segments & metal joints on top of the flat deck (top exactly TRACK_Y)."""
    pts = _track_samples(48)
    for i, (px, py, tx, ty, nx, ny) in enumerate(pts):
        ang = math.degrees(math.atan2(ty, tx))
        cx = px + nx * (0.5 * (R_TRACK_IN + R_TRACK_FLAT_OUT) - R_TRACK_CENTER)
        cy = py + ny * (0.5 * (R_TRACK_IN + R_TRACK_FLAT_OUT) - R_TRACK_CENTER)
        half_w = 0.5 * (R_TRACK_FLAT_OUT - R_TRACK_IN) - 0.01
        cafe.tbox(
            "Track_Slat_%02d" % i,
            (cx - 0.058, cy - half_w, TRACK_Y - 0.005),
            (cx + 0.058, cy + half_w, TRACK_Y),
            "dark" if i % 4 != 0 else "slate_dark",
            root,
            c,
            axis="Z",
            deg=ang,
            pivot=(cx, cy, TRACK_Y),
        )


def _tunnel_flap(name, x0, x1, y_pos, z0, root, c):
    cafe.tbox(name + "_Clamp", (x0, y_pos - 0.015, 0.72), (x1, y_pos + 0.015, 0.76), "metal", root, c)
    cafe.tbox(name, (x0, y_pos - 0.010, z0), (x1, y_pos + 0.010, 0.72), "dark", root, c, bevel=0.002)


def _suitcase_icon(prefix, x_center, y0, y1, z_center, root, c):
    """Flat Toon suitcase pictogram on a baggage-claim sign face."""
    sw, sh = 0.24, 0.17
    cafe.tbox(prefix + "_Bag", (x_center - sw / 2, y0, z_center - sh / 2), (x_center + sw / 2, y1, z_center + sh / 2), "yellow", root, c)
    # Handle on top
    cafe.tbox(prefix + "_Handle", (x_center - 0.05, y0, z_center + sh / 2), (x_center + 0.05, y1, z_center + sh / 2 + 0.032), "dark", root, c)
    # Two vertical straps proud by 2 mm
    py0, py1 = (y0 - 0.003, y0) if y0 < 0 else (y1, y1 + 0.003)
    for tag, sx in (("L", -0.06), ("R", 0.06)):
        cafe.tbox(
            prefix + "_Strap_" + tag,
            (x_center + sx - 0.014, py0, z_center - sh / 2),
            (x_center + sx + 0.014, py1, z_center + sh / 2),
            "dark",
            root,
            c,
        )


def build_claim_carousel(root, c):
    # 1. Base housing: recessed dark toe kick, brushed steel body, yellow safety band
    _stadium_prism("Base_ToeKick", 0.0, R_TOE, 0.0, bag.TOE, "dark", root, c)
    _stadium_prism("Base_Housing", 0.0, R_BASE, bag.TOE, 0.28, "metal", root, c)
    # Yellow band leaves gap [INLET_X - 0.42, INLET_X + 0.42] on back straight
    gap = (INLET_X - bag.HALF_IN, INLET_X + bag.HALF_IN)
    _stadium_ring_profile(
        "Base_YellowBand",
        [(R_BASE, 0.14), (R_BASE + 0.006, 0.14), (R_BASE + 0.006, 0.20), (R_BASE, 0.20)],
        "yellow",
        root,
        c,
        skip_back_gap=gap,
    )

    # 2. Slat track base + sloped outer apron (flat riding surface at TRACK_Y = 0.355 m!)
    _stadium_prism("Track_SubDeck", R_TRACK_IN, R_TRACK_FLAT_OUT, 0.28, TRACK_Y - 0.005, "slate_dark", root, c)
    _stadium_ring_profile(
        "Track_OuterApron",
        [
            (R_TRACK_FLAT_OUT, 0.28),
            (R_TRACK_APRON_OUT, 0.28),
            (R_TRACK_APRON_OUT, APRON_EDGE_Z),
            (R_TRACK_FLAT_OUT, TRACK_Y),
        ],
        "dark",
        root,
        c,
    )
    _slat_ribs(root, c)

    # 3. Brushed-metal outer bumper rail (top 0.335 m < 0.355 m track, open at belt inlet port)
    _stadium_ring_profile(
        "Outer_Bumper",
        [
            (R_BUMPER_IN, BUMPER_Z0),
            (R_BUMPER_OUT, BUMPER_Z0),
            (R_BUMPER_OUT, BUMPER_Z1),
            (R_BUMPER_IN, BUMPER_Z1),
        ],
        "white",
        root,
        c,
        skip_back_gap=gap,
    )

    # 4. Raised central island
    _stadium_prism("Island_Core", 0.0, R_ISLAND, TRACK_Y - 0.005, ISLAND_TOP - 0.04, "white", root, c)
    _stadium_ring_profile(
        "Island_Band",
        [(R_ISLAND, 0.42), (R_ISLAND + 0.006, 0.42), (R_ISLAND + 0.006, 0.50), (R_ISLAND, 0.50)],
        "blue",
        root,
        c,
    )
    _stadium_prism("Island_Cap", 0.0, R_ISLAND + 0.02, ISLAND_TOP - 0.04, ISLAND_TOP, "frame", root, c)

    # 5. Central Baggage-Claim Sign Pillar (twin brushed metal posts + double-sided sign board)
    for side, x in (("L", -0.40), ("R", 0.40)):
        kit.cyl("Sign_Post_" + side, x, 0.0, ISLAND_TOP, SIGN_Z0, 0.028, "metal", root, c)
        kit.cyl("Sign_Collar_" + side, x, 0.0, ISLAND_TOP, ISLAND_TOP + 0.08, 0.045, "dark", root, c)
    cafe.tbox("Sign_Board_Frame", (-0.54, -0.065, SIGN_Z0), (0.54, 0.065, SIGN_Z1), "slate_dark", root, c, bevel=0.01)
    cafe.tbox("Sign_Board_Cap", (-0.56, -0.075, SIGN_Z1), (0.56, 0.075, SIGN_Z1 + 0.045), "yellow", root, c, bevel=0.01)
    for side, y0, y1, fy0, fy1 in (("Front", -0.070, -0.065, -0.074, -0.070), ("Back", 0.065, 0.070, 0.070, 0.074)):
        cafe.tbox("Sign_Panel_%s" % side, (-0.50, y0, SIGN_Z0 + 0.03), (0.50, y1, SIGN_Z1 - 0.03), "blue", root, c)
        sx = -0.30 if side == "Front" else 0.30
        bx0, bx1 = sorted((sx - 0.16, sx + 0.16))
        cafe.tbox("Sign_Badge_%s" % side, (bx0, fy0, SIGN_Z0 + 0.05), (bx1, fy1, SIGN_Z1 - 0.05), "white", root, c)
        _suitcase_icon("Sign_Bag_%s" % side, sx, fy0 - 0.004 if side == "Front" else fy1, fy0 if side == "Front" else fy1 + 0.004, 0.5 * (SIGN_Z0 + SIGN_Z1) - 0.01, root, c)
        tx0, tx1 = sorted((-0.08, 0.44)) if side == "Front" else sorted((-0.44, 0.08))
        cafe.tbox("Sign_TextTop_%s" % side, (tx0, fy0, SIGN_Z0 + 0.24), (tx1, fy1, SIGN_Z0 + 0.31), "text_yellow", root, c)
        cafe.tbox("Sign_TextSub_%s" % side, (tx0, fy0, SIGN_Z0 + 0.12), (tx1 - (0.14 if side == "Front" else 0.0), fy1, SIGN_Z0 + 0.18), "text_white", root, c)

    # 6. Inbound belt spur + Luggage Tunnel Arch at cell (2, 0) back edge (x = +0.50, y_blender = +1.00)
    surface = cafe.group("Belt_Surface", root, c)
    y_in_start = 0.80
    y_in_end = 1.00
    cafe.tbox(
        "Inlet_Belt_Surface",
        (INLET_X - bag.LANE, y_in_start, bag.BODY_TOP),
        (INLET_X + bag.LANE, y_in_end, TRACK_Y),
        "dark",
        surface,
        c,
    )
    cafe.tbox(
        "Inlet_Belt_Seam",
        (INLET_X - bag.LANE, 0.90 - 0.008, TRACK_Y),
        (INLET_X + bag.LANE, 0.90 + 0.008, TRACK_Y + 0.002),
        "metal",
        surface,
        c,
    )
    # Spur support & rails flush with baggage_belt.glb at y = 1.00
    cafe.tbox("Inlet_ToeKick", (INLET_X - bag.HALF_IN + 0.04, 0.86, 0.0), (INLET_X + bag.HALF_IN - 0.04, y_in_end, bag.TOE), "dark", root, c)
    cafe.tbox("Inlet_Body", (INLET_X - bag.HALF_IN + bag.BAND_T, 0.86, bag.TOE), (INLET_X + bag.HALF_IN - bag.BAND_T, y_in_end, bag.BODY_TOP), "metal", root, c)
    for side, s in (("L", -1.0), ("R", 1.0)):
        rx0, rx1 = sorted((INLET_X + s * bag.LANE, INLET_X + s * bag.HALF_IN))
        bx0, bx1 = sorted((INLET_X + s * (bag.HALF_IN - bag.BAND_T), INLET_X + s * bag.HALF_IN))
        cafe.tbox("Inlet_Rail_" + side, (rx0, 0.88, bag.BODY_TOP), (rx1, y_in_end, bag.RAIL_TOP), "frame", root, c)
        cafe.tbox("Inlet_Band_" + side, (bx0, 0.88, bag.BAND[0]), (bx1, y_in_end, bag.BAND[1]), "yellow", root, c)

    # Tunnel arch housing (side pillars stay in y >= 0.875 -> 7.5 cm clear of circling bags at y <= 0.80!)
    for side, x0, x1 in (("L", INLET_X - 0.48, INLET_X - 0.42), ("R", INLET_X + 0.42, INLET_X + 0.48)):
        cafe.tbox("Tunnel_Post_" + side, (x0, 0.875, 0.0), (x1, y_in_end, 0.88), "slate_dark", root, c, bevel=0.008)
        cafe.tbox("Tunnel_Stripe_" + side, (x0 - 0.004, 0.88, 0.50), (x1 + 0.004, y_in_end, 0.58), "yellow", root, c)
    # Tunnel hood clears bag tops (0.355 + 0.256 = 0.611 m) by >= 15 cm
    cafe.tbox("Tunnel_Roof", (INLET_X - 0.48, 0.80, 0.76), (INLET_X + 0.48, y_in_end - 0.006, 0.96), "metal", root, c, bevel=0.015)
    cafe.tbox("Tunnel_Fascia_In", (INLET_X - 0.44, 0.794, 0.80), (INLET_X + 0.44, 0.80, 0.92), "blue", root, c)
    cafe.tbox("Tunnel_Fascia_Out", (INLET_X - 0.44, y_in_end - 0.006, 0.80), (INLET_X + 0.44, y_in_end, 0.92), "blue", root, c)
    cafe.tbox("Tunnel_Beacon", (INLET_X - 0.09, 0.86, 0.96), (INLET_X + 0.09, 0.94, 1.03), "lamp_green", root, c)

    # Hanging rubber curtain flaps inside tunnel portal (y = 0.94)
    _tunnel_flap("Tunnel_Flap_Rail_L", INLET_X - 0.415, INLET_X - 0.352, 0.94, bag.RAIL_TOP + 0.008, root, c)
    _tunnel_flap("Tunnel_Flap_Rail_R", INLET_X + 0.352, INLET_X + 0.415, 0.94, bag.RAIL_TOP + 0.008, root, c)
    for i, dx in enumerate((-0.276, -0.138, 0.0, 0.138, 0.276)):
        _tunnel_flap("Tunnel_Flap_%d" % i, INLET_X + dx - 0.061, INLET_X + dx + 0.061, 0.94, TRACK_Y + 0.008, root, c)

    # 7. Mount_Belt_B empty on the back inlet edge (Godot frame: +Z points OUT of port -> yaw 180 deg)
    mount = bpy.data.objects.new("Mount_Belt_B", None)
    c.objects.link(mount)
    mount.parent = root
    mount.empty_display_type = "SINGLE_ARROW"
    mount.empty_display_size = 0.3
    gx, gy, gz = PORT_POS_GODOT
    mount.location = (gx, -gz, gy)
    mount.rotation_euler = (0.0, 0.0, math.radians(PORT_YAW))


PIECES = {
    PIECE: (
        build_claim_carousel,
        FOOTPRINT,
        (-1.92, -0.92, 0.0),
        (1.92, 1.000, SIGN_Z1 + 0.045),
    )
}
EXTRA_NODES = {
    PIECE: ["Belt_Surface", "Belt_Surface_Mesh", "Mount_Belt_B"],
}


def guard():
    taken = sorted((set(kit.PIECES) | set(cafe.PIECES)) & set(PIECES))
    if taken:
        kit.fail("claim_carousel name clash: %s" % taken)
    out = os.path.join(kit.OUT_DIR, PIECE + ".glb")
    if os.path.exists(out):
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(PIECE) + "_ROOT" in names and set(EXTRA_NODES[PIECE]) <= names
        kit.log("GUARD %s existing file own=%s" % (PIECE, own))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    else:
        kit.log("GUARD %s new file %s" % (PIECE, out))
    if kit.FAILS:
        sys.exit(1)


def register():
    kit.PALETTE.update(CAROUSEL_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    kit.NODE_TRANSLATIONS["Mount_Belt_B"] = PORT_POS_GODOT


def check_written(written):
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        by_name = {n.get("name"): n for n in js.get("nodes", [])}
        node = by_name.get("Mount_Belt_B")
        if node is None:
            kit.fail("%s: Mount_Belt_B missing" % piece)
        else:
            t = node.get("translation", [0.0, 0.0, 0.0])
            x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
            facing = Quaternion((w, x, y, z)) @ Vector((0.0, 0.0, 1.0))
            kit.log(
                "MOUNT %s Mount_Belt_B pos=(%.3f, %.3f, %.3f) facing=(%.3f, %.3f, %.3f)"
                % (piece, t[0], t[1], t[2], facing.x, facing.y, facing.z)
            )
            if max(abs(a - b) for a, b in zip(t, PORT_POS_GODOT)) > 1e-4 or (facing - Vector((0, 0, -1))).length > 1e-3:
                kit.fail("%s: Mount_Belt_B mismatch" % piece)

        objs = bag.import_written(out)
        pts = bag.godot_points(objs)
        lo_x, hi_x = min(p.x for p in pts), max(p.x for p in pts)
        lo_y, hi_y = min(p.y for p in pts), max(p.y for p in pts)
        lo_z, hi_z = min(p.z for p in pts), max(p.z for p in pts)
        # Closed-side 0.08 m inset check (+X, -X, +Z) and port-side (-Z) check
        non_port_z = [-p.z for p in pts if abs(p.x - INLET_X) > 0.49]
        max_non_port_neg_z = max(non_port_z) if non_port_z else 0.0
        kit.log(
            "INSET %s godot_x=[%.3f, %.3f] godot_y=[%.3f, %.3f] godot_z=[%.3f, %.3f] non_port_neg_z=%.3f"
            % (piece, lo_x, hi_x, lo_y, hi_y, lo_z, hi_z, max_non_port_neg_z)
        )
        if abs(lo_x) > 1.921 or hi_x > 1.921 or hi_z > 0.921 or max_non_port_neg_z > 0.921 or lo_y < -1e-4:
            kit.fail("%s: inset violated" % piece)

        # Verify Belt_Surface edge alignment at z_godot = -1.0 (x in [0.15, 0.85], y = 0.355)
        surf = [o for o in objs if o.name.startswith("Belt_Surface_Mesh")]
        spts = bag.godot_points(surf)
        edge_x = [p.x for p in spts if abs(p.z - (-1.0)) < 1e-3 and abs(p.y - TRACK_Y) < 1e-3]
        span = (min(edge_x), max(edge_x)) if edge_x else (0.0, 0.0)
        kit.log("PORT %s Mount_Belt_B edge_verts=%d span_x=[%.3f, %.3f] y=%.3f" % (piece, len(edge_x), span[0], span[1], TRACK_Y))
        if abs(span[0] - (INLET_X - bag.LANE)) > 1e-3 or abs(span[1] - (INLET_X + bag.LANE)) > 1e-3:
            kit.fail("%s: Belt_Surface edge span mismatch %s" % (piece, span))

        # Sweep suitcase box (0.38 x 0.55 x 0.22) around 36 loop samples + tunnel entry at y = TRACK_Y + 0.002
        body = [o for o in objs if o.type == "MESH" and not o.name.startswith("Belt_Surface_Mesh")]
        polys = []
        rigid_polys = []
        for ob in body:
            mw = ob.matrix_world
            for p in ob.data.polygons:
                wverts = [mw @ ob.data.vertices[i].co for i in p.vertices]
                polys.append(wverts)
                mid = sum(wverts, Vector()) / len(wverts)
                is_curtain = 0.92 < mid.y < 0.96 and mid.z < 0.725 and abs(mid.x - INLET_X) < 0.42
                if not is_curtain:
                    rigid_polys.append(wverts)

        bag_lo = Vector((-0.19, -0.275, 0.002))
        bag_hi = Vector((0.19, 0.275, 0.222))
        loop_samples = [(px, py, math.degrees(math.atan2(ty, tx)) - 90.0) for px, py, tx, ty, _nx, _ny in _track_samples(36)]
        tunnel_samples = [(INLET_X, 0.98, 0.0), (INLET_X, 0.88, 0.0), (INLET_X, 0.78, 0.0)]

        clashes = 0
        ctrl_clashes = 0
        for px, py, yaw in loop_samples:
            xf = Matrix.Translation((px, py, TRACK_Y)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
            inv = xf.inverted()
            local_polys = [[inv @ v for v in poly] for poly in polys]
            clashes += sum(1 for lp in local_polys if svc.clip_to_box(lp, bag_lo, bag_hi, 1e-3))
            ctrl_clashes += sum(
                1 for lp in local_polys if svc.clip_to_box(lp, bag_lo - Vector((0, 0, 0.025)), bag_hi - Vector((0, 0, 0.025)), 1e-3)
            )
        for px, py, yaw in tunnel_samples:
            xf = Matrix.Translation((px, py, TRACK_Y)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
            inv = xf.inverted()
            local_rigid = [[inv @ v for v in poly] for poly in rigid_polys]
            clashes += sum(1 for lp in local_rigid if svc.clip_to_box(lp, bag_lo, bag_hi, 1e-3))
        kit.log(
            "CAROUSEL_SWEEP %s loop_samples=%d tunnel_samples=%d clashes=%d control_lower_clashes=%d"
            % (piece, len(loop_samples), len(tunnel_samples), clashes, ctrl_clashes)
        )
        if clashes or not ctrl_clashes:
            kit.fail("%s: circling/entering suitcase clipped geometry (%d) or control missed (%d)" % (piece, clashes, ctrl_clashes))

        track_spec = {
            "footprint": [4, 2],
            "belt_port": {"cell": [2, 0], "side": "B", "godot_pos": list(PORT_POS_GODOT), "yaw_deg": PORT_YAW},
            "track_loop": {
                "shape": "stadium",
                "center": [0.0, TRACK_Y, 0.0],
                "half_straight_x": HALF_STRAIGHT,
                "curve_radius": R_TRACK_CENTER,
                "rx": HALF_STRAIGHT + R_TRACK_CENTER,
                "rz": R_TRACK_CENTER,
                "track_y": TRACK_Y,
                "length_m": round(4.0 * HALF_STRAIGHT + 2.0 * math.pi * R_TRACK_CENTER, 4),
            },
        }
        kit.log("CAROUSEL_SPEC " + json.dumps(track_spec))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    kit.log("CLAIM_CAROUSEL REPO=%s OUT_DIR=%s" % (kit.REPO, kit.OUT_DIR))
    guard()
    register()
    check_written(kit.main(default_pieces=[PIECE], blend_out=BLEND_OUT))
