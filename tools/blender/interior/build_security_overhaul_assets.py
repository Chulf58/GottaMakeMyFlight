"""Build the Security Overhaul S1 Blender assets and verify/render them.

Assets built and exported (all watertight, grounded at y=0, zero-area=0,
dup_coplanar=0, UV-mapped on measured TP_Atlas_1A_D swatches):
  1. game/assets/interior/security_search_table.glb
  2. game/assets/interior/security_confiscation_bin.glb
  3. game/assets/interior/contraband/gag_snow_globe.glb
  4. game/assets/interior/contraband/gag_syrup_jug.glb
  5. game/assets/interior/contraband/gag_garden_gnome.glb
  6. game/assets/interior/contraband/gag_bowling_ball.glb
  7. game/assets/interior/contraband/gag_flamingo.glb
  8. game/assets/interior/contraband/gag_rubber_duck.glb
  9. game/assets/interior/contraband/gag_giant_wrench.glb
 10. game/assets/interior/contraband/gag_mystery_thermos.glb

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    <repo>/tools/blender/interior/build_security_overhaul_assets.py \
    [-- --plates-dir <dir> [--no-render]]
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402

REPO = kit.REPO
INTERIOR_DIR = os.path.join(REPO, "game", "assets", "interior")
CONTRABAND_DIR = os.path.join(INTERIOR_DIR, "contraband")
TEXTURES = kit.TEXTURES
POST_IMPORT = "res://assets/toon_post_import.gd"
BLEND_OUT_DEFAULT = os.path.join(REPO, "tools", "blender", "out", "security-s1-assets", "security_s1_assets.blend")
PLATES_OUT_DEFAULT = os.path.join(REPO, "tools", "blender", "out", "security-s1-assets", "blender")

# Exact rubber inspection mat top height on security_search_table.glb (Godot Y).
SEARCH_TABLE_SURFACE_Y = 0.830

# Clear bin cavity interior bounds (0.66 x 0.92 x 0.66 m outer, posts +-0.298, glass +-0.310).
BIN_OUTER_HALF = 0.330
BIN_POST_INNER = 0.298
BIN_GLASS_INNER = 0.310
BIN_FLOOR_Y = 0.110
BIN_COLLAR_BOTTOM_Y = 0.830
BIN_TOP_Y = 0.920

# Uniform scale applied to the 8 contraband gag props (~0.22-0.25 m max dimension).
PROP_SCALE = 1.15

# 12 staggered interior prop slot positions (3 layers x 4 slots) inside the bin cavity.
# Every scaled gag prop has height in [0.220, 0.246] m and horizontal radius <= 0.122 m,
# guaranteeing >= 2.0 cm clearance from corner posts (+-0.298) and glass (+-0.310) at any yaw.
BIN_PROP_SLOTS = [
    # Layer 0 (bottom, resting on BIN_FLOOR_Y = 0.110)
    {"name": "Mount_Prop_00", "pos": (-0.140, 0.110, -0.140), "yaw_deg": 18.0},
    {"name": "Mount_Prop_01", "pos": (0.140, 0.110, -0.140), "yaw_deg": -32.0},
    {"name": "Mount_Prop_02", "pos": (-0.140, 0.110, 0.140), "yaw_deg": 145.0},
    {"name": "Mount_Prop_03", "pos": (0.140, 0.110, 0.140), "yaw_deg": -115.0},
    # Layer 1 (middle, y = 0.345, spiral-staggered)
    {"name": "Mount_Prop_04", "pos": (-0.115, 0.345, -0.145), "yaw_deg": 65.0},
    {"name": "Mount_Prop_05", "pos": (0.145, 0.345, -0.115), "yaw_deg": -78.0},
    {"name": "Mount_Prop_06", "pos": (-0.145, 0.345, 0.115), "yaw_deg": -15.0},
    {"name": "Mount_Prop_07", "pos": (0.115, 0.345, 0.145), "yaw_deg": 122.0},
    # Layer 2 (top, y = 0.580, counter-staggered, tops <= 0.826 < 0.830 collar)
    {"name": "Mount_Prop_08", "pos": (-0.145, 0.580, -0.115), "yaw_deg": -45.0},
    {"name": "Mount_Prop_09", "pos": (0.115, 0.580, -0.145), "yaw_deg": 28.0},
    {"name": "Mount_Prop_10", "pos": (-0.115, 0.580, 0.145), "yaw_deg": 165.0},
    {"name": "Mount_Prop_11", "pos": (0.145, 0.580, 0.115), "yaw_deg": -150.0},
]

EMPTY_RGB = {(51, 51, 51), (0, 0, 0)}
MAT_ATLAS = "TP_Atlas_1A_D"
MAT_GLASS = "ConfiscationGlass"

# Measured TP_Atlas_1A_D swatches (col, row, frac, span) verified against tp_atlas_1a_d.png.
SWATCHES = {
    "dark": (16, 1, 0.40, 0.0),         # #342e37 charcoal rubber / dimples
    "slate_dark": (18, 1, 0.40, 0.0),   # #444546 dark slate posts / frame
    "slate_steel": (13, 12, 0.35, 0.0), # #49586b cool slate-steel shelf
    "frame": (6, 4, 0.45, 0.0),         # #7c8384 medium cool frame / rim
    "steel_mid": (11, 11, 0.35, 0.0),   # #939a9a brushed steel mid
    "metal": (12, 11, 0.25, 0.15),      # #bfbfbf bright brushed steel
    "tray_grey": (14, 11, 0.45, 0.0),   # #a3a3a3 security tray grey
    "white": (11, 14, 0.15, 0.18),      # #f0e7db warm crisp white
    "cream": (22, 0, 0.30, 0.0),        # #eddcc7 cream label / stripe
    "blue": (9, 4, 0.25, 0.20),         # #4f78b5 security blue band
    "kid_blue": (25, 0, 0.30, 0.0),     # #353cf1 royal gnome coat blue
    "teal": (26, 1, 0.35, 0.0),         # #027bca glossy bowling-ball teal-blue
    "ice_blue": (4, 10, 0.35, 0.0),     # #60c5ff icy sky-blue snow globe / stripe
    "kid_green": (11, 0, 0.35, 0.0),    # #22a86f emerald thermos green
    "pine_green": (27, 1, 0.35, 0.0),   # #0c8848 deep pine green
    "yellow": (1, 13, 0.50, 0.0),       # #ffdd06 bright hazard yellow
    "sun": (28, 0, 0.30, 0.0),          # #ffd800 sunshine rubber duck yellow
    "gold": (3, 13, 0.30, 0.0),         # #de9e20 warm brass / duck wing gold
    "orange": (29, 0, 0.30, 0.0),       # #f18033 bright duck bill / thermos stripe
    "amber": (10, 0, 0.35, 0.0),        # #d75d00 rich maple syrup amber
    "red": (31, 0, 0.30, 0.0),          # #ec212c bright cap / gnome hat / wrench grip
    "pink": (23, 0, 0.30, 0.0),         # #f13390 hot flamingo pink
    "wood": (19, 0, 0.30, 0.20),        # #b78e56 warm clipboard wood
    "wood_dark": (16, 3, 0.35, 0.0),    # #6c5748 walnut snow globe base
    "peach": (20, 12, 0.35, 0.0),       # #cc987f warm gnome nose/hands
}

_atlas_cache = None
_mat_cache = {}
FAILS = []


def log(msg):
    print(msg, flush=True)


def fail(msg):
    FAILS.append(msg)
    log("ASSET_FAIL " + msg)


def atlas_data():
    global _atlas_cache
    if _atlas_cache is None:
        img = bpy.data.images.load(os.path.join(TEXTURES, "tp_atlas_1a_d.png"), check_existing=True)
        _atlas_cache = (img, img.size[0], img.size[1], img.pixels[:], 32, 16)
    return _atlas_cache


def sample_rgb(u, v):
    _img, w, h, px, _c, _r = atlas_data()
    x = min(w - 1, max(0, int(u * w)))
    y = min(h - 1, max(0, int(v * h)))
    i = (y * w + x) * 4
    return tuple(round(px[i + k] * 255) for k in range(3))


def swatch_uv(pal, t):
    col, row, frac, span = SWATCHES[pal]
    _img, _w, _h, _px, cols, rows = atlas_data()
    f = frac + span * t
    return (col + 0.5) / cols, 1.0 - (row + f) / rows


def get_material(mat_name):
    if mat_name in _mat_cache:
        return _mat_cache[mat_name]
    m = bpy.data.materials.new(mat_name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
    if mat_name == MAT_GLASS:
        bsdf.inputs["Base Color"].default_value = (0.76, 0.92, 1.0, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.12
        bsdf.inputs["Alpha"].default_value = 0.12
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = atlas_data()[0]
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 1.0
    _mat_cache[mat_name] = m
    return m


# ---------------------------------------------------------------- bmesh helpers


def _finish(name, bm, pal, parent, coll, mat_name=MAT_ATLAS, smooth=False):
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=list(bm.edges))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    uv = bm.loops.layers.uv.verify()
    zs = [v.co.z for v in bm.verts]
    z0, z1 = (min(zs), max(zs)) if zs else (0.0, 0.0)
    for face in bm.faces:
        face.smooth = smooth
        for loop in face.loops:
            if mat_name == MAT_GLASS:
                loop[uv].uv = (0.5, 0.5)
            else:
                t = 0.0 if z1 - z0 < 1e-6 else (z1 - loop.vert.co.z) / (z1 - z0)
                loop[uv].uv = swatch_uv(pal, t)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(get_material(mat_name))
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = parent
    return ob


def gbox(name, x_rng, y_rng, z_rng, pal, parent, coll, bevel=0.0, rot_x=0.0, rot_y=0.0, rot_z=0.0, pivot=None, mat_name=MAT_ATLAS):
    """Box specified in Godot (x, y_up, z_front) ranges, converted to Blender (x, -z, y)."""
    x0, x1 = sorted(x_rng)
    y0, y1 = sorted(y_rng)
    z0, z1 = sorted(z_rng)
    lo = Vector((x0, -z1, y0))
    hi = Vector((x1, -z0, y1))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = hi - lo
    centre = (lo + hi) / 2.0
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=min(bevel, min(size) * 0.35),
            segments=1,
            affect="EDGES",
            profile=0.5,
        )
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    if rot_x or rot_y or rot_z:
        gp = Vector((pivot[0], -pivot[2], pivot[1])) if pivot is not None else centre
        # Godot Euler (rx, ry, rz) -> Blender (rx, -rz, ry)
        r = Euler((math.radians(rot_x), math.radians(-rot_z), math.radians(rot_y)), "XYZ").to_matrix().to_4x4()
        m = Matrix.Translation(gp) @ r @ Matrix.Translation(-gp)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _finish(name, bm, pal, parent, coll, mat_name=mat_name)


def gcyl(name, gx, gz, y0, y1, r0, r1, pal, parent, coll, segs=12, rot_x=0.0, rot_y=0.0, rot_z=0.0, pivot=None):
    """Upright tapered cylinder in Godot coords (gx, y0..y1, gz)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=y1 - y0)
    centre = Vector((gx, -gz, (y0 + y1) / 2.0))
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    if rot_x or rot_y or rot_z:
        gp = Vector((pivot[0], -pivot[2], pivot[1])) if pivot is not None else centre
        r = Euler((math.radians(rot_x), math.radians(-rot_z), math.radians(rot_y)), "XYZ").to_matrix().to_4x4()
        m = Matrix.Translation(gp) @ r @ Matrix.Translation(-gp)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _finish(name, bm, pal, parent, coll)


def gball(name, gx, gy, gz, rx, ry, rz, pal, parent, coll, u_segs=12, v_segs=8):
    """Ellipsoid in Godot coords centered at (gx, gy, gz) with Godot radii (rx, ry, rz)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u_segs, v_segments=v_segs, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector((rx, rz, ry)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((gx, -gz, gy)), verts=bm.verts)
    return _finish(name, bm, pal, parent, coll)


def gtorus(name, gx, gy, gz, major_r, minor_r, pal, parent, coll, maj_segs=14, min_segs=8):
    """Horizontal torus in Godot XZ plane centered at (gx, gy, gz)."""
    bm = bmesh.new()
    rings = []
    for i in range(maj_segs):
        theta = 2.0 * math.pi * i / maj_segs
        ct, st = math.cos(theta), math.sin(theta)
        ring = []
        for j in range(min_segs):
            phi = 2.0 * math.pi * j / min_segs
            r = major_r + minor_r * math.cos(phi)
            x = gx + r * ct
            y_b = -gz + r * st
            z_b = gy + minor_r * math.sin(phi)
            ring.append(bm.verts.new((x, y_b, z_b)))
        rings.append(ring)
    for i in range(maj_segs):
        ni = (i + 1) % maj_segs
        for j in range(min_segs):
            nj = (j + 1) % min_segs
            bm.faces.new((rings[i][j], rings[ni][j], rings[ni][nj], rings[i][nj]))
    return _finish(name, bm, pal, parent, coll)


def g_tube_path(name, pts_r, pal, parent, coll, segs=10):
    """Swept circular tube along Godot [(Vector3(x,y,z), radius), ...] with capped ends."""
    bm = bmesh.new()
    rings = []
    n = len(pts_r)
    for idx, (gp, rad) in enumerate(pts_r):
        p = Vector((gp.x, -gp.z, gp.y))
        if idx == 0:
            tangent = Vector((pts_r[1][0].x - gp.x, -(pts_r[1][0].z - gp.z), pts_r[1][0].y - gp.y)).normalized()
        elif idx == n - 1:
            tangent = Vector((gp.x - pts_r[idx - 1][0].x, -(gp.z - pts_r[idx - 1][0].z), gp.y - pts_r[idx - 1][0].y)).normalized()
        else:
            t1 = Vector((gp.x - pts_r[idx - 1][0].x, -(gp.z - pts_r[idx - 1][0].z), gp.y - pts_r[idx - 1][0].y)).normalized()
            t2 = Vector((pts_r[idx + 1][0].x - gp.x, -(pts_r[idx + 1][0].z - gp.z), pts_r[idx + 1][0].y - gp.y)).normalized()
            tangent = (t1 + t2).normalized()
            if tangent.length < 1e-6:
                tangent = t1
        up = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.9 else Vector((0.0, 1.0, 0.0))
        u = tangent.cross(up).normalized()
        v = tangent.cross(u).normalized()
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            ring.append(bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * rad))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(segs):
            nk = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][nk], rings[i][nk]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return _finish(name, bm, pal, parent, coll)


def add_mount(name, gx, gy, gz, yaw_deg, root, coll):
    ob = bpy.data.objects.new(name, None)
    coll.objects.link(ob)
    ob.parent = root
    ob.empty_display_type = "SINGLE_ARROW"
    ob.empty_display_size = 0.25
    ob.location = (gx, -gz, gy)
    ob.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    return ob


# ---------------------------------------------------------------- piece builders


def build_security_search_table(root, coll):
    """Secondary Bag-Search Table (1x1 cell, 0.84 x 0.855 x 0.76 m, mat top at y=0.830)."""
    # 4 legs with rubber foot pads (grounded at y=0.0).
    for i, (lx, lz) in enumerate(((-0.35, -0.31), (0.35, -0.31), (-0.35, 0.31), (0.35, 0.31))):
        gbox("Table_Foot_%d" % i, (lx - 0.032, lx + 0.032), (0.0, 0.030), (lz - 0.032, lz + 0.032), "dark", root, coll)
        gbox("Table_Leg_%d" % i, (lx - 0.024, lx + 0.024), (0.030, 0.680), (lz - 0.024, lz + 0.024), "metal", root, coll)
    # Lower storage shelf holding 2 stacked spare trays and a glove/swab box.
    gbox("Table_Shelf", (-0.34, 0.34), (0.195, 0.220), (-0.30, 0.30), "slate_steel", root, coll)
    for k in range(2):
        by = 0.220 + k * 0.055
        gbox("Shelf_TrayBase_%d" % k, (-0.28, 0.06), (by, by + 0.012), (-0.22, 0.22), "tray_grey", root, coll)
        gbox("Shelf_TrayRimL_%d" % k, (-0.28, -0.265), (by + 0.012, by + 0.052), (-0.22, 0.22), "tray_grey", root, coll)
        gbox("Shelf_TrayRimR_%d" % k, (0.045, 0.06), (by + 0.012, by + 0.052), (-0.22, 0.22), "tray_grey", root, coll)
        gbox("Shelf_TrayRimF_%d" % k, (-0.265, 0.045), (by + 0.012, by + 0.052), (0.205, 0.22), "tray_grey", root, coll)
        gbox("Shelf_TrayRimB_%d" % k, (-0.265, 0.045), (by + 0.012, by + 0.052), (-0.22, -0.205), "tray_grey", root, coll)
    # Glove/swab kit box on right side of shelf.
    gbox("Shelf_GloveBox", (0.11, 0.29), (0.220, 0.310), (-0.18, 0.14), "blue", root, coll, bevel=0.008)
    gbox("Shelf_GloveSlot", (0.14, 0.26), (0.310, 0.318), (-0.08, 0.04), "white", root, coll)

    # Upper apron frame & blue security band.
    gbox("Table_Apron", (-0.380, 0.380), (0.680, 0.780), (-0.345, 0.345), "slate_dark", root, coll)
    gbox("Table_Band", (-0.386, 0.386), (0.710, 0.755), (-0.351, 0.351), "blue", root, coll)

    # Steel tabletop deck (y = 0.780..0.822).
    gbox("Table_Deck", (-0.415, 0.415), (0.780, 0.822), (-0.375, 0.375), "metal", root, coll, bevel=0.006)
    # Dark rubber inspection mat on top (exact top y = SEARCH_TABLE_SURFACE_Y = 0.830).
    gbox("Table_Mat", (-0.365, 0.365), (0.822, SEARCH_TABLE_SURFACE_Y), (-0.335, 0.335), "dark", root, coll)

    # Raised edge lips (L/R/Back up to 0.855, gentle low front ridge 0.840).
    gbox("Table_Lip_L", (-0.415, -0.365), (0.822, 0.855), (-0.375, 0.375), "frame", root, coll, bevel=0.004)
    gbox("Table_Lip_R", (0.365, 0.415), (0.822, 0.855), (-0.375, 0.375), "frame", root, coll, bevel=0.004)
    gbox("Table_Lip_B", (-0.365, 0.365), (0.822, 0.855), (-0.375, -0.335), "frame", root, coll, bevel=0.004)
    gbox("Table_Lip_F", (-0.365, 0.365), (0.822, 0.840), (0.335, 0.375), "frame", root, coll, bevel=0.004)

    # Cozy detail 1: Clipboard & checklist tucked in back-right corner (outside both 0/90 tray bounds).
    gbox("Clip_Board", (0.245, 0.350), (0.830, 0.837), (-0.325, -0.235), "wood", root, coll)
    gbox("Clip_Paper", (0.255, 0.340), (0.837, 0.841), (-0.315, -0.245), "white", root, coll)
    gbox("Clip_Clamp", (0.280, 0.315), (0.841, 0.848), (-0.322, -0.305), "metal", root, coll)
    gbox("Clip_Pen", (0.258, 0.268), (0.841, 0.848), (-0.300, -0.250), "yellow", root, coll)

    # Cozy detail 2: Side wand & swab caddy pocket on outer +X apron (stays within x <= 0.418).
    gbox("Caddy_Pocket", (0.380, 0.418), (0.640, 0.775), (-0.12, 0.12), "slate_steel", root, coll, bevel=0.004)
    gbox("Caddy_Wand_Handle", (0.388, 0.410), (0.720, 0.835), (-0.06, -0.02), "dark", root, coll)
    gbox("Caddy_Wand_Tip", (0.388, 0.410), (0.775, 0.815), (-0.01, 0.04), "yellow", root, coll)

    add_mount("Mount_Inspect", 0.0, SEARCH_TABLE_SURFACE_Y, 0.0, 0.0, root, coll)


def build_security_confiscation_bin(root, coll):
    """Clear-sided glass Confiscation Bin (0.66 x 0.92 x 0.66 m, 12 staggered Mount_Prop_* slots)."""
    # Heavy dark-slate base plinth (y=0..0.110) with non-coplanar bumper & security band.
    gbox("Bin_BasePad", (-0.324, 0.324), (0.0, 0.028), (-0.324, 0.324), "dark", root, coll)
    gbox("Bin_Plinth", (-0.328, 0.328), (0.028, 0.105), (-0.328, 0.328), "slate_dark", root, coll, bevel=0.004)
    gbox("Bin_Band", (-0.330, 0.330), (0.048, 0.082), (-0.330, 0.330), "blue", root, coll)
    # Front badge plaque on plinth.
    gbox("Bin_Badge", (-0.10, 0.10), (0.038, 0.092), (0.325, 0.329), "yellow", root, coll)
    gbox("Bin_Badge_Mark", (-0.055, 0.055), (0.052, 0.078), (0.327, 0.330), "red", root, coll)
    # Inner floor plate at exact BIN_FLOOR_Y = 0.110.
    gbox("Bin_Floor", (-0.300, 0.300), (0.105, BIN_FLOOR_Y), (-0.300, 0.300), "slate_steel", root, coll)

    # 4 corner posts (0.032 m square, y = 0.105..0.832, tucked inside plinth & collar with zero coplanar ends).
    for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x0, x1 = sorted((sx * BIN_POST_INNER, sx * BIN_OUTER_HALF))
        z0, z1 = sorted((sz * BIN_POST_INNER, sz * BIN_OUTER_HALF))
        gbox("Bin_Post_%d" % i, (x0, x1), (0.105, 0.832), (z0, z1), "slate_dark", root, coll, bevel=0.003)

    # 4 translucent clear glass side panels (ConfiscationGlass, spanning strictly between corner posts).
    gbox("Bin_Glass_F", (-0.297, 0.297), (BIN_FLOOR_Y, BIN_COLLAR_BOTTOM_Y), (0.310, 0.320), None, root, coll, mat_name=MAT_GLASS)
    gbox("Bin_Glass_B", (-0.297, 0.297), (BIN_FLOOR_Y, BIN_COLLAR_BOTTOM_Y), (-0.320, -0.310), None, root, coll, mat_name=MAT_GLASS)
    gbox("Bin_Glass_L", (-0.320, -0.310), (BIN_FLOOR_Y, BIN_COLLAR_BOTTOM_Y), (-0.297, 0.297), None, root, coll, mat_name=MAT_GLASS)
    gbox("Bin_Glass_R", (0.310, 0.320), (BIN_FLOOR_Y, BIN_COLLAR_BOTTOM_Y), (-0.297, 0.297), None, root, coll, mat_name=MAT_GLASS)

    # Top hazard collar & open drop chute (y = 0.830..0.920), 4 non-overlapping bar pieces per tier.
    # Lower slate collar skirt (y = 0.830..0.854).
    for tag, xr, zr in (
        ("F", (-0.330, 0.330), (0.255, 0.330)),
        ("B", (-0.330, 0.330), (-0.330, -0.255)),
        ("L", (-0.330, -0.255), (-0.254, 0.254)),
        ("R", (0.255, 0.330), (-0.254, 0.254)),
    ):
        gbox("Bin_CollarLow_%s" % tag, xr, (0.830, 0.854), zr, "slate_dark", root, coll)

    # Bright yellow hazard trim ring (y = 0.854..0.914).
    for tag, xr, zr in (
        ("F", (-0.330, 0.330), (0.246, 0.330)),
        ("B", (-0.330, 0.330), (-0.330, -0.246)),
        ("L", (-0.330, -0.246), (-0.245, 0.245)),
        ("R", (0.246, 0.330), (-0.245, 0.245)),
    ):
        gbox("Bin_HazardRing_%s" % tag, xr, (0.854, 0.914), zr, "yellow", root, coll, bevel=0.005)

    # Dark inner drop-chute rim lip (y = 0.875..0.920, leaving 0.464 x 0.464 m open drop chute).
    for tag, xr, zr in (
        ("F", (-0.246, 0.246), (0.232, 0.246)),
        ("B", (-0.246, 0.246), (-0.246, -0.232)),
        ("L", (-0.246, -0.232), (-0.231, 0.231)),
        ("R", (0.232, 0.246), (-0.231, 0.231)),
    ):
        gbox("Bin_ChuteLip_%s" % tag, xr, (0.875, BIN_TOP_Y), zr, "dark", root, coll)

    # Hazard corner stripe caps on outer collar corners for cozy detail.
    for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x0, x1 = sorted((sx * 0.285, sx * 0.330))
        z0, z1 = sorted((sz * 0.285, sz * 0.330))
        gbox("Bin_CornerBump_%d" % i, (x0, x1), (0.862, 0.898), (z0, z1), "dark", root, coll)

    # 12 interior Mount_Prop_* empties (3 layers x 4 staggered slots).
    for slot in BIN_PROP_SLOTS:
        gx, gy, gz = slot["pos"]
        add_mount(slot["name"], gx, gy, gz, slot["yaw_deg"], root, coll)


def build_gag_snow_globe(root, coll):
    """Snow globe on walnut pedestal with brass collar, icy blue sphere, snow base & pine emblem."""
    gcyl("Globe_BaseLow", 0.0, 0.0, 0.0, 0.025, 0.074, 0.070, "wood_dark", root, coll, segs=12)
    gcyl("Globe_BaseStep", 0.0, 0.0, 0.025, 0.048, 0.066, 0.060, "wood_dark", root, coll, segs=12)
    gcyl("Globe_Collar", 0.0, 0.0, 0.048, 0.060, 0.064, 0.066, "gold", root, coll, segs=12)
    # Chunky snow-mound lower hemisphere ring & icy crystal globe.
    gball("Globe_SnowBand", 0.0, 0.105, 0.0, 0.079, 0.046, 0.079, "white", root, coll, u_segs=14, v_segs=8)
    gball("Globe_Dome", 0.0, 0.130, 0.0, 0.077, 0.077, 0.077, "ice_blue", root, coll, u_segs=14, v_segs=10)
    # Cute miniature pine tree & snowy star finial on front/top silhouette so it screams winter globe.
    gcyl("Globe_Tree_Lower", 0.0, 0.068, 0.088, 0.128, 0.024, 0.004, "pine_green", root, coll, segs=8)
    gcyl("Globe_Tree_Upper", 0.0, 0.068, 0.118, 0.155, 0.018, 0.002, "pine_green", root, coll, segs=8)
    gball("Globe_TopFlake", 0.0, 0.203, 0.0, 0.016, 0.008, 0.016, "white", root, coll, u_segs=8, v_segs=6)


def build_gag_syrup_jug(root, coll):
    """Chunky amber maple-syrup jug with loop handle, cream label & bright red cap."""
    gcyl("Syrup_Base", 0.0, 0.0, 0.0, 0.012, 0.065, 0.067, "dark", root, coll, segs=12)
    gcyl("Syrup_Body", 0.0, 0.0, 0.010, 0.140, 0.068, 0.064, "amber", root, coll, segs=12)
    gcyl("Syrup_Shoulder", 0.0, 0.0, 0.136, 0.172, 0.063, 0.026, "amber", root, coll, segs=12)
    gcyl("Syrup_Neck", 0.0, 0.0, 0.170, 0.186, 0.024, 0.024, "amber", root, coll, segs=10)
    gcyl("Syrup_Cap", 0.0, 0.0, 0.185, 0.208, 0.030, 0.028, "red", root, coll, segs=10)
    # Side loop handle (+X side, well within radius 0.105).
    g_tube_path(
        "Syrup_Handle",
        [
            (Vector((0.022, 0.174, 0.0)), 0.012),
            (Vector((0.068, 0.168, 0.0)), 0.012),
            (Vector((0.088, 0.135, 0.0)), 0.012),
            (Vector((0.076, 0.095, 0.0)), 0.012),
            (Vector((0.056, 0.085, 0.0)), 0.012),
        ],
        "amber",
        root,
        coll,
        segs=8,
    )
    # Cream front label & red leaf badge.
    gbox("Syrup_Label", (-0.038, 0.038), (0.042, 0.112), (0.062, 0.072), "cream", root, coll, bevel=0.003)
    gbox("Syrup_Leaf", (-0.016, 0.016), (0.062, 0.092), (0.070, 0.076), "red", root, coll, rot_z=45.0)


def build_gag_garden_gnome(root, coll):
    """Classic cozy garden gnome: boots, royal-blue coat, fluffy white beard, peach nose, red hat."""
    for side, sx in (("L", -0.028), ("R", 0.028)):
        gbox("Gnome_Boot_" + side, (sx - 0.020, sx + 0.020), (0.0, 0.024), (-0.022, 0.044), "dark", root, coll, bevel=0.005)
    gcyl("Gnome_Coat", 0.0, 0.0, 0.022, 0.105, 0.064, 0.052, "kid_blue", root, coll, segs=12)
    gbox("Gnome_Belt", (-0.058, 0.058), (0.052, 0.066), (-0.058, 0.058), "dark", root, coll, bevel=0.005)
    gbox("Gnome_Buckle", (-0.016, 0.016), (0.050, 0.068), (0.054, 0.064), "gold", root, coll)
    # Arms + peach mittens.
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        gcyl("Gnome_Arm_" + side, sgn * 0.058, 0.012, 0.056, 0.098, 0.016, 0.018, "kid_blue", root, coll, segs=8, rot_z=sgn * 20.0)
        gball("Gnome_Hand_" + side, sgn * 0.066, 0.054, 0.020, 0.017, 0.017, 0.017, "peach", root, coll, u_segs=8, v_segs=6)
    # Head, beard, bulbous nose.
    gball("Gnome_Head", 0.0, 0.118, 0.0, 0.042, 0.036, 0.042, "peach", root, coll, u_segs=10, v_segs=8)
    gball("Gnome_Beard", 0.0, 0.092, 0.032, 0.046, 0.038, 0.032, "white", root, coll, u_segs=10, v_segs=8)
    gball("Gnome_Nose", 0.0, 0.120, 0.046, 0.017, 0.015, 0.018, "peach", root, coll, u_segs=8, v_segs=6)
    # Tall pointy red hat with slight cheeky backward tip.
    gcyl("Gnome_HatRim", 0.0, -0.002, 0.130, 0.146, 0.054, 0.048, "red", root, coll, segs=12)
    gcyl("Gnome_HatCone", 0.0, -0.008, 0.144, 0.210, 0.046, 0.004, "red", root, coll, segs=12, rot_x=-10.0, pivot=(0.0, 0.144, 0.0))


def build_gag_bowling_ball(root, coll):
    """Glossy teal bowling ball resting in a tiny rubber ring with 3 crisp finger-hole sockets."""
    gtorus("Ball_Chock", 0.0, 0.012, 0.0, 0.046, 0.012, "dark", root, coll, maj_segs=12, min_segs=8)
    gball("Ball_Sphere", 0.0, 0.104, 0.0, 0.094, 0.094, 0.094, "teal", root, coll, u_segs=16, v_segs=12)
    # Swirl accent band around equator-tilt for Toon readability.
    gtorus("Ball_Band", 0.0, 0.104, 0.0, 0.091, 0.006, "ice_blue", root, coll, maj_segs=16, min_segs=8)
    # 3 distinct dark finger-hole sockets protruding cleanly 2 mm at top-front so zero coplanar faces.
    holes = [
        (0.0, 0.194, 0.022, 0.013, (12.0, 0.0, 0.0)),
        (-0.020, 0.184, 0.048, 0.011, (26.0, -10.0, 0.0)),
        (0.020, 0.184, 0.048, 0.011, (26.0, 10.0, 0.0)),
    ]
    for idx, (hx, hy, hz, hr, rot) in enumerate(holes):
        gcyl("Ball_Hole_%d" % idx, hx, hz, hy - 0.008, hy + 0.006, hr, hr, "dark", root, coll, segs=8,
             rot_x=rot[0], rot_y=rot[1], rot_z=rot[2], pivot=(hx, hy, hz))


def build_gag_flamingo(root, coll):
    """Bright pink inflatable flamingo swim ring with white wings & yellow/black hooked beak."""
    gtorus("Flamingo_Ring", 0.0, 0.031, 0.0, 0.062, 0.031, "pink", root, coll, maj_segs=14, min_segs=8)
    # Raised tail at -Z.
    gbox("Flamingo_Tail", (-0.020, 0.020), (0.042, 0.090), (-0.088, -0.050), "pink", root, coll, bevel=0.008, rot_x=25.0)
    # Cute white wing strips on outer sides.
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sgn * 0.066, sgn * 0.095))
        gbox("Flamingo_Wing_" + side, (x0, x1), (0.038, 0.064), (-0.040, 0.022), "white", root, coll, bevel=0.006)
    # Curved S-neck rising from front of ring (+Z).
    g_tube_path(
        "Flamingo_Neck",
        [
            (Vector((0.0, 0.052, 0.058)), 0.021),
            (Vector((0.0, 0.094, 0.068)), 0.017),
            (Vector((0.0, 0.140, 0.046)), 0.016),
            (Vector((0.0, 0.176, 0.056)), 0.017),
        ],
        "pink",
        root,
        coll,
        segs=10,
    )
    gball("Flamingo_Head", 0.0, 0.184, 0.060, 0.025, 0.024, 0.027, "pink", root, coll, u_segs=10, v_segs=8)
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        gball("Flamingo_Eye_" + side, sgn * 0.021, 0.190, 0.069, 0.005, 0.006, 0.006, "dark", root, coll, u_segs=6, v_segs=4)
    # Characteristic yellow upper beak + dark hooked lower tip.
    gcyl("Flamingo_BeakTop", 0.0, 0.086, 0.170, 0.186, 0.015, 0.008, "yellow", root, coll, segs=8, rot_x=95.0, pivot=(0.0, 0.178, 0.086))
    gcyl("Flamingo_BeakTip", 0.0, 0.094, 0.146, 0.172, 0.005, 0.010, "dark", root, coll, segs=8, rot_x=15.0, pivot=(0.0, 0.168, 0.094))


def build_gag_rubber_duck(root, coll):
    """Chunky bright-yellow rubber duck with raised tail, gold wings & orange bill."""
    # Rounded belly resting flat on y=0.
    gball("Duck_Body", 0.0, 0.054, -0.004, 0.060, 0.054, 0.074, "sun", root, coll, u_segs=14, v_segs=10)
    gcyl("Duck_BasePad", 0.0, -0.004, 0.0, 0.020, 0.044, 0.050, "sun", root, coll, segs=12)
    # Raised tail wedge at -Z.
    gcyl("Duck_Tail", 0.0, -0.068, 0.058, 0.114, 0.024, 0.006, "sun", root, coll, segs=8, rot_x=-38.0, pivot=(0.0, 0.066, -0.060))
    # Side wings.
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        gball("Duck_Wing_" + side, sgn * 0.056, 0.060, -0.006, 0.017, 0.027, 0.046, "gold", root, coll, u_segs=8, v_segs=6)
    # Neck & round head.
    gcyl("Duck_Neck", 0.0, 0.030, 0.085, 0.125, 0.032, 0.030, "sun", root, coll, segs=10)
    gball("Duck_Head", 0.0, 0.148, 0.032, 0.046, 0.046, 0.046, "sun", root, coll, u_segs=12, v_segs=10)
    # Wide cartoon orange bill.
    gball("Duck_Bill", 0.0, 0.138, 0.076, 0.026, 0.013, 0.022, "orange", root, coll, u_segs=10, v_segs=6)
    # Dark eyes.
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        gball("Duck_Eye_" + side, sgn * 0.025, 0.160, 0.066, 0.007, 0.007, 0.007, "dark", root, coll, u_segs=8, v_segs=6)


def _open_jaw_head(prefix, center_y, tilt_deg, pivot, jaw_up, pal, root, coll):
    """Build a crisp C-shaped open-end wrench jaw in Godot XY tilted with the shaft."""
    s = 1.0 if jaw_up else -1.0
    # Collar heel + 2 flanking prongs leaving an open U-mouth at top/bottom!
    gbox(prefix + "_Heel", (-0.042, 0.042), (center_y - 0.013, center_y + 0.013), (-0.015, 0.015), pal, root, coll,
         bevel=0.004, rot_z=tilt_deg, pivot=pivot)
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * 0.019, sx * 0.044))
        y0, y1 = sorted((center_y + s * 0.009, center_y + s * 0.038))
        gbox("%s_Prong_%s" % (prefix, side), (x0, x1), (y0, y1), (-0.014, 0.014), pal, root, coll,
             bevel=0.004, rot_z=tilt_deg, pivot=pivot)


def build_gag_giant_wrench(root, coll):
    """Oversized steel open-end wrench tilted 14 deg and seated into a dark rubber chock."""
    # Dark rubber cradle block (y=0..0.030) so the lower jaw sits firmly seated with zero air gap.
    gbox("Wrench_StandPad", (-0.052, 0.052), (0.0, 0.028), (-0.034, 0.034), "dark", root, coll, bevel=0.004)
    tilt = 14.0
    pivot = (0.0, 0.046, 0.0)
    # Steel shaft + bright red grip sleeve + top & bottom C-jaws.
    gbox("Wrench_Shaft", (-0.017, 0.017), (0.054, 0.168), (-0.011, 0.011), "metal", root, coll,
         bevel=0.003, rot_z=tilt, pivot=pivot)
    gbox("Wrench_Grip", (-0.022, 0.022), (0.084, 0.138), (-0.015, 0.015), "red", root, coll,
         bevel=0.004, rot_z=tilt, pivot=pivot)
    _open_jaw_head("Wrench_JawTop", 0.172, tilt, pivot, True, "steel_mid", root, coll)
    _open_jaw_head("Wrench_JawBot", 0.054, tilt, pivot, False, "steel_mid", root, coll)


def build_gag_mystery_thermos(root, coll):
    """Oversized colorful insulated flask with emerald body, orange/cream stripes, handle & steel cup lid."""
    gcyl("Thermos_Boot", 0.0, 0.0, 0.0, 0.024, 0.058, 0.056, "dark", root, coll, segs=12)
    gcyl("Thermos_BodyLow", 0.0, 0.0, 0.022, 0.074, 0.054, 0.054, "kid_green", root, coll, segs=12)
    gcyl("Thermos_StripeOrange", 0.0, 0.0, 0.072, 0.104, 0.057, 0.057, "orange", root, coll, segs=12)
    gcyl("Thermos_StripeCream", 0.0, 0.0, 0.103, 0.123, 0.0555, 0.0555, "cream", root, coll, segs=12)
    gcyl("Thermos_BodyTop", 0.0, 0.0, 0.121, 0.156, 0.054, 0.050, "kid_green", root, coll, segs=12)
    gcyl("Thermos_Neck", 0.0, 0.0, 0.154, 0.172, 0.048, 0.042, "steel_mid", root, coll, segs=12)
    gcyl("Thermos_CupLid", 0.0, 0.0, 0.170, 0.210, 0.045, 0.047, "metal", root, coll, segs=12)
    # Chunky side carry handle on +X.
    g_tube_path(
        "Thermos_Handle",
        [
            (Vector((0.052, 0.136, 0.0)), 0.009),
            (Vector((0.080, 0.132, 0.0)), 0.009),
            (Vector((0.082, 0.056, 0.0)), 0.009),
            (Vector((0.052, 0.050, 0.0)), 0.009),
        ],
        "dark",
        root,
        coll,
        segs=8,
    )


# ---------------------------------------------------------------- registry & export

PIECES = {
    "security_search_table": {
        "builder": build_security_search_table,
        "out_dir": INTERIOR_DIR,
        "is_prop": False,
        "footprint": (1, 1),
        "expected_mats": [MAT_ATLAS],
        "expected_mounts": ["Mount_Inspect"],
    },
    "security_confiscation_bin": {
        "builder": build_security_confiscation_bin,
        "out_dir": INTERIOR_DIR,
        "is_prop": False,
        "footprint": (1, 1),
        "expected_mats": [MAT_ATLAS, MAT_GLASS],
        "expected_mounts": [s["name"] for s in BIN_PROP_SLOTS],
    },
    "gag_snow_globe": {"builder": build_gag_snow_globe, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_syrup_jug": {"builder": build_gag_syrup_jug, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_garden_gnome": {"builder": build_gag_garden_gnome, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_bowling_ball": {"builder": build_gag_bowling_ball, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_flamingo": {"builder": build_gag_flamingo, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_rubber_duck": {"builder": build_gag_rubber_duck, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_giant_wrench": {"builder": build_gag_giant_wrench, "out_dir": CONTRABAND_DIR, "is_prop": True},
    "gag_mystery_thermos": {"builder": build_gag_mystery_thermos, "out_dir": CONTRABAND_DIR, "is_prop": True},
}


def piece_title(piece):
    return "".join(p.capitalize() for p in piece.split("_"))


def join_static(root, coll, piece):
    objs = [o for o in coll.objects if o.type == "MESH"]
    if not objs:
        return
    if len(objs) == 1:
        objs[0].name = piece_title(piece) + "_Body"
        return
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = piece_title(piece) + "_Body"


def build_piece(piece):
    spec = PIECES[piece]
    c = bpy.data.collections.new(piece_title(piece))
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new(piece_title(piece) + "_ROOT", None)
    c.objects.link(root)
    spec["builder"](root, c)
    bpy.context.view_layer.update()
    join_static(root, c, piece)
    if spec.get("is_prop"):
        for ob in c.objects:
            if ob.type == "MESH":
                ob.data.transform(Matrix.Scale(PROP_SCALE, 4))
                ob.data.update()
    for ob in c.objects:
        if ob.type == "MESH":
            ob.data.validate()
    bpy.context.view_layer.update()
    return root, c


def write_scene_import(glb_path):
    path = glb_path + ".import"
    line = 'import_script/path="%s"' % POST_IMPORT
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if line in text:
            return
        fail("%s exists without binder line" % path)
        return
    text = (
        '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
        "%s\ngltf/embedded_image_handling=0\n" % line
    )
    with open(path, "w", newline="\n") as f:
        f.write(text)


def export_piece(piece, coll):
    out_dir = PIECES[piece]["out_dir"]
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, piece + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for ob in coll.objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_vertex_color="NONE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
    )
    write_scene_import(out)
    return out


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _v, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or length != len(data):
        raise RuntimeError("not a GLB: %s" % path)
    clen, _t = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + clen].decode("utf-8")), len(data)


def seam_counts(objs):
    """Exact port of test_furniture_catalog.gd _seam_counts() (zero-area and dup coplanar)."""
    zero_area = 0
    tris = []
    for ob in objs:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        me = ob.data
        me.calc_loop_triangles()
        for lt in me.loop_triangles:
            a = mw @ me.vertices[lt.vertices[0]].co
            b = mw @ me.vertices[lt.vertices[1]].co
            c = mw @ me.vertices[lt.vertices[2]].co
            cross = (b - a).cross(c - a)
            area = cross.length * 0.5
            if area < 1e-8:
                zero_area += 1
                continue
            tris.append(((a + b + c) / 3.0, cross.normalized(), area))
    buckets = {}
    for t in tris:
        k = (round(t[0].x * 200.0), round(t[0].y * 200.0), round(t[0].z * 200.0))
        buckets.setdefault(k, []).append(t)
    dup = 0
    for centre, n, area in tris:
        bx, by, bz = round(centre.x * 200.0), round(centre.y * 200.0), round(centre.z * 200.0)
        found = 0
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for oc, on, oa in buckets.get((bx + dx, by + dy, bz + dz), []):
                        if (centre - oc).length < 1e-3 and abs(n.dot(on)) > 0.999 and abs(area - oa) < 1e-4:
                            found += 1
        if found > 1:
            dup += 1
    return zero_area, dup // 2


def verify_written(piece, out):
    global _atlas_cache
    spec = PIECES[piece]
    js, nbytes = parse_glb(out)
    mats = sorted(m["name"] for m in js.get("materials", []))
    nodes = sorted(n.get("name", "?") for n in js.get("nodes", []))
    want_mats = sorted(spec.get("expected_mats", [MAT_ATLAS]))
    if mats != want_mats:
        fail("%s: materials %s != expected %s" % (piece, mats, want_mats))
    if js.get("images"):
        fail("%s: file carries %d images, expected 0" % (piece, len(js["images"])))
    want_nodes = sorted([piece_title(piece) + "_ROOT", piece_title(piece) + "_Body"] + spec.get("expected_mounts", []))
    if nodes != want_nodes:
        fail("%s: nodes %s != expected %s" % (piece, nodes, want_nodes))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    _atlas_cache = None
    _mat_cache.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()

    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts_blender = []
    outside = 0
    loops = 0
    intended = {(c, r) for (c, r, _f, _s) in SWATCHES.values()}
    for ob in mesh_objs:
        mw = ob.matrix_world
        for v in ob.data.vertices:
            pts_blender.append(mw @ v.co)
        uvl = ob.data.uv_layers.active
        for poly in ob.data.polygons:
            mname = ob.data.materials[poly.material_index].name.split(".")[0]
            if mname == MAT_GLASS:
                continue
            if mname != MAT_ATLAS:
                fail("%s: unexpected polygon material %s" % (piece, mname))
                continue
            cells = {(int(uvl.data[li].uv[0] * 32), int((1.0 - uvl.data[li].uv[1]) * 16))
                     for li in poly.loop_indices}
            if len(cells) != 1:
                outside += len(poly.loop_indices)
            for li in poly.loop_indices:
                u, v = uvl.data[li].uv
                loops += 1
                fu, fv = (u * 32) % 1.0, ((1.0 - v) * 16) % 1.0
                rgb = sample_rgb(u, v)
                cell = (int(u * 32), int((1.0 - v) * 16))
                ok = (0.0 < u < 1.0 and 0.0 < v < 1.0 and 0.2 < fu < 0.8 and 0.05 < fv < 0.95
                      and rgb not in EMPTY_RGB and cell in intended)
                if not ok:
                    outside += 1

    # Convert Blender pts (x, y, z) -> Godot (x, z, -y).
    pts_godot = [Vector((p.x, p.z, -p.y)) for p in pts_blender]
    lo = Vector((min(p.x for p in pts_godot), min(p.y for p in pts_godot), min(p.z for p in pts_godot)))
    hi = Vector((max(p.x for p in pts_godot), max(p.y for p in pts_godot), max(p.z for p in pts_godot)))
    size = hi - lo
    zero_area, dup_coplanar = seam_counts(mesh_objs)
    r_max = max(math.hypot(p.x, p.z) for p in pts_godot)

    log(
        "VERIFY %s bytes=%d size=(%.3f, %.3f, %.3f) min_y=%.4f r_max=%.4f zero_area=%d dup_coplanar=%d outside_uv=%d"
        % (piece, nbytes, size.x, size.y, size.z, lo.y, r_max, zero_area, dup_coplanar, outside)
    )
    if abs(lo.y) > 1e-3:
        fail("%s: not grounded at y=0 (min_y=%.4f)" % (piece, lo.y))
    if zero_area > 0 or dup_coplanar > 0:
        fail("%s: seam errors zero_area=%d dup_coplanar=%d" % (piece, zero_area, dup_coplanar))
    if outside > 0 or loops == 0:
        fail("%s: bad UVs outside=%d loops=%d" % (piece, outside, loops))

    if piece == "security_search_table":
        if max(abs(lo.x), abs(hi.x)) > 0.48 or max(abs(lo.z), abs(hi.z)) > 0.48:
            fail("%s: exceeds 1x1 cell bounds (%s..%s)" % (piece, lo, hi))
        if not (0.82 <= hi.y <= 0.87):
            fail("%s: unexpected height %.3f (expected ~0.82-0.86)" % (piece, hi.y))
    elif piece == "security_confiscation_bin":
        if abs(size.x - 0.66) > 0.02 or abs(size.z - 0.66) > 0.02 or abs(size.y - 0.92) > 0.02:
            fail("%s: unexpected bin dims %s" % (piece, size))
    elif spec["is_prop"]:
        max_dim = max(size.x, size.y, size.z)
        if not (0.20 <= max_dim <= 0.26):
            fail("%s: max_dim %.3f outside [0.20, 0.26]" % (piece, max_dim))
        if hi.y < 0.215 or hi.y > 0.255:
            fail("%s: height %.3f outside [0.215, 0.255]" % (piece, hi.y))
        if r_max > 0.125:
            fail("%s: horiz radius %.4f > 0.125 (risks poking through bin post/glass)" % (piece, r_max))
        # Verify >= 2.0 cm air clearance against all 12 bin slots.
        for slot in BIN_PROP_SLOTS:
            sx, sy, sz = slot["pos"]
            if sx + r_max > BIN_POST_INNER - 0.020 or sx - r_max < -BIN_POST_INNER + 0.020:
                fail("%s violates 2cm X margin at %s (r=%.4f)" % (piece, slot["name"], r_max))
            if sz + r_max > BIN_POST_INNER - 0.020 or sz - r_max < -BIN_POST_INNER + 0.020:
                fail("%s violates 2cm Z margin at %s (r=%.4f)" % (piece, slot["name"], r_max))
            if sy + hi.y >= BIN_COLLAR_BOTTOM_Y - 0.002:
                fail("%s violates Y collar at %s" % (piece, slot["name"]))

    return {"lo": lo, "hi": hi, "size": size, "r_max": r_max}


# ---------------------------------------------------------------- Blender verification renders


def plate_bind(objs, label):
    names = set()
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            raw = slot.material.name.split(".")[0]
            names.add(raw)
            if raw == MAT_ATLAS:
                slot.material = rap.toon_material("tp_atlas", "tp_atlas_1a_d.png")
            elif raw == MAT_GLASS:
                slot.material = _plate_glass_material()
            else:
                rap.invalid("%s: unknown material %s" % (label, raw))
    return names


def _plate_glass_material():
    key = "confiscation_glass"
    if key in rap._materials:
        return rap._materials[key]
    m = bpy.data.materials.new("PLATE_ConfiscationGlass")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (0.76, 0.92, 1.0, 1.0)
    emit.inputs["Strength"].default_value = 0.95
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = 0.12
    nt.links.new(clear.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emit.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    rap._materials[key] = m
    return m


def import_plate_glb(path, label, xf=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    plate_bind(new, label)
    if xf is not None:
        holder = bpy.data.objects.new("HOLD_" + label, None)
        bpy.context.scene.collection.objects.link(holder)
        holder.matrix_world = xf
        for o in new:
            if o.parent is None:
                o.parent = holder
    bpy.context.view_layer.update()
    return new


def render_six_axis_sheet(piece, glb_path, out_png, fill_bin=False):
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs = import_plate_glb(glb_path, piece)
    all_subject_objs = list(objs)
    if fill_bin:
        props = [p for p, s in PIECES.items() if s.get("is_prop")]
        for idx, slot in enumerate(BIN_PROP_SLOTS):
            prop_name = props[idx % len(props)]
            gx, gy, gz = slot["pos"]
            xf = Matrix.Translation((gx, -gz, gy)) @ Matrix.Rotation(math.radians(slot["yaw_deg"]), 4, "Z")
            all_subject_objs.extend(import_plate_glb(os.path.join(CONTRABAND_DIR, prop_name + ".glb"), "%s_%d" % (prop_name, idx), xf))
    lo, hi = rap.bounds(all_subject_objs)
    ref = rap.cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
    sub = rap.world_points(all_subject_objs)
    ref_pts = rap.world_points([ref])
    allp = np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in rap.VIEWS:
        inv = np.array(rap.look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * rap.MARGIN - 0.04
    tiles = []
    tmp_dir = os.path.dirname(out_png)
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "%s_%s" % (os.path.basename(out_png), name)
        b_sub = rap.prove_in_frame(label + "_sub", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + "_cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        if not apart:
            rap.invalid("%s: reference cube overlaps subject" % label)
        tile_path = os.path.join(tmp_dir, "_tmp_%s_%s.png" % (piece, name))
        tiles.append(rap.over(rap.render(scene, tile_path), rap.BACKDROP))
        if os.path.exists(tile_path):
            os.remove(tile_path)
        bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 3), out_png)


def render_prop_lineup(out_dir):
    """6-axis + angled hero lineup sheet of all 8 contraband gag props next to a 0.25m ref or 1m ref."""
    scene = rap.reset_scene(1600, 900, 1.5)
    props = [p for p, s in PIECES.items() if s.get("is_prop")]
    all_objs = []
    # Two neat rows of 4 props on a small neutral plinth/floor.
    for i, prop_name in enumerate(props):
        col = i % 4
        row = i // 4
        x = (col - 1.5) * 0.36 + (0.14 if row == 1 else 0.0)
        y = (0.28 if row == 0 else -0.26)
        xf = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(-18.0 if row == 0 else 15.0), 4, "Z")
        objs = import_plate_glb(os.path.join(CONTRABAND_DIR, prop_name + ".glb"), prop_name, xf)
        all_objs.extend(objs)
    rap.floor_plane((-1.4, -1.2), (1.9, 1.6), z=0.0)
    # 1 m reference cube off to the back-right for true scale proof.
    ref = rap.cube((1.15, 0.95, 0.5))
    cam = rap.persp_camera(scene, Vector((0.35, -3.40, 1.75)), Vector((0.28, 0.25, 0.36)), lens=38.0)
    sub = rap.world_points(all_objs)
    rap.prove_in_frame("contraband_lineup props", scene, cam, sub)
    rap.prove_in_frame("contraband_lineup cube", scene, cam, rap.world_points([ref]))
    raw = os.path.join(out_dir, "_tmp_lineup_raw.png")
    arr = rap.render(scene, raw)
    if os.path.exists(raw):
        os.remove(raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(out_dir, "contraband_lineup.png"))

    # Tight macro lineup of the 8 props alone so every silhouette and color reads large.
    bpy.data.objects.remove(ref)
    bpy.data.objects.remove(cam)
    cam_macro = rap.persp_camera(scene, Vector((0.08, -2.15, 0.95)), Vector((0.08, 0.0, 0.10)), lens=45.0)
    rap.prove_in_frame("contraband_macro props", scene, cam_macro, sub)
    raw_m = os.path.join(out_dir, "_tmp_macro_raw.png")
    arr_m = rap.render(scene, raw_m)
    if os.path.exists(raw_m):
        os.remove(raw_m)
    rap.save_array(rap.over(arr_m, rap.BACKDROP), os.path.join(out_dir, "contraband_macro_lineup.png"))

    # Individual 6-axis sheet for every gag prop combined into a 2x4 or individual six-axis sheets.
    for prop_name in props:
        render_six_axis_sheet(
            prop_name,
            os.path.join(CONTRABAND_DIR, prop_name + ".glb"),
            os.path.join(out_dir, "six_axis_%s.png" % prop_name),
            fill_bin=False,
        )


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    plates_dir = PLATES_OUT_DEFAULT
    do_render = True
    i = 0
    while i < len(argv):
        if argv[i] == "--plates-dir" and i + 1 < len(argv):
            plates_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--no-render":
            do_render = False
            i += 1
        else:
            i += 1
    return plates_dir, do_render


def main():
    global _atlas_cache
    plates_dir, do_render = parse_args()
    os.makedirs(INTERIOR_DIR, exist_ok=True)
    os.makedirs(CONTRABAND_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_OUT_DEFAULT), exist_ok=True)
    os.makedirs(plates_dir, exist_ok=True)

    written = []
    for piece in PIECES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _atlas_cache = None
        _mat_cache.clear()
        root, coll = build_piece(piece)
        out = export_piece(piece, coll)
        written.append((piece, out))

    summaries = {}
    for piece, out in written:
        summaries[piece] = verify_written(piece, out)

    # Save appendable .blend file with all 10 assets laid out neatly.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _atlas_cache = None
    _mat_cache.clear()
    x = 0.0
    for piece in PIECES:
        root, _c = build_piece(piece)
        root.location.x = x
        x += 1.4 if not PIECES[piece]["is_prop"] else 0.5
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT_DEFAULT, compress=True)
    log("BLEND saved %s" % BLEND_OUT_DEFAULT)

    if FAILS:
        log("FAILED count=%d" % len(FAILS))
        sys.exit(1)

    if do_render:
        render_six_axis_sheet(
            "security_search_table",
            os.path.join(INTERIOR_DIR, "security_search_table.glb"),
            os.path.join(plates_dir, "six_axis_security_search_table.png"),
            fill_bin=False,
        )
        render_six_axis_sheet(
            "security_confiscation_bin_empty",
            os.path.join(INTERIOR_DIR, "security_confiscation_bin.glb"),
            os.path.join(plates_dir, "six_axis_security_confiscation_bin_empty.png"),
            fill_bin=False,
        )
        render_six_axis_sheet(
            "security_confiscation_bin_filled",
            os.path.join(INTERIOR_DIR, "security_confiscation_bin.glb"),
            os.path.join(plates_dir, "six_axis_security_confiscation_bin_filled.png"),
            fill_bin=True,
        )
        render_prop_lineup(plates_dir)

    log("SECURITY_S1_ASSETS done pieces=%d fails=%d table_surface_y=%.3f slots=%d"
        % (len(written), len(FAILS), SEARCH_TABLE_SURFACE_Y, len(BIN_PROP_SLOTS)))


if __name__ == "__main__":
    main()
