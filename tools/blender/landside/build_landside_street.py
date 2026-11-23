"""Build and convert the landside road extension, tunnel portals, and street props.

Run from WSL (Blender is a Windows program, so paths resolve from __file__):

    timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
        --background --factory-startup --python-exit-code 1 \\
        --python "C:\\Users\\chulf\\Gotta-make-my-flight\\.claude\\worktrees\\visual-overhaul-landside\\tools\\blender\\landside\\build_landside_street.py"

Outputs under game/assets/landside/ (with .glb.import files pointing to
res://assets/toon_post_import.gd):
- landside_road_ext.glb: modular 113 m road + sidewalks + centreline dashes
  matching tp_airport_site.glb's Road cross-section (x 0..113, z -6..6).
- landside_tunnel_portal.glb: Toon highway overpass / landscaped tunnel portal
  (mouth at local x 0, dark backstop at x 19.2, grass berm + wing walls +
  highway brow sign + crest guardrail).
- landside_bollard.glb: cylindrical concrete/charcoal/yellow curb bollard.
- landside_crosswalk.glb: single-sided crisp zebra crosswalk matching Road.
- tc_streetlight_1a.glb, tc_streetlight_2a.glb, tc_tree_1a.glb, tc_tree_3a.glb,
  tp_pine_tree_02a.glb, tc_bush_2a.glb, tp_signpost_01a.glb: scaled and rebound
  vendor Toon street props ready to sit cleanly on sidewalks or verges.
"""

import json
import math
import os
import re
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ASSETS = os.path.join(REPO, "game", "assets")
TEX_DIR = os.path.join(ASSETS, "textures")
OUT_DIR = os.path.join(ASSETS, "landside")
POST_IMPORT = "res://assets/toon_post_import.gd"

SRC = "C:\\Users\\chulf\\Assets new\\Toon Series"
TP_MODELS = os.path.join(SRC, "Toon Planes Pack", "Models")
TC_MODELS = os.path.join(SRC, "Toon City", "Models")

ATLAS_COLS = 32
ATLAS_ROWS = 16

# Measured UVs from tp_airport_site.glb Road + tp_atlas_1a_d.png swatches.
ROAD_ASPHALT_UV = (0.5047, 0.9385)
ROAD_SIDEWALK_UV = (0.5337, 0.9825)
ROAD_KERB_UV = (0.5468, 0.9906)
ROAD_DASH_UV = (0.6820, 0.9900)

SWATCHES = {
    "asphalt": ("TP_Atlas_Simple_Road_Flat", ROAD_ASPHALT_UV, (60, 62, 62)),
    "sidewalk": ("TP_Atlas_Simple_1A_D", ROAD_SIDEWALK_UV, (145, 139, 127)),
    "kerb": ("TP_Atlas_Simple_1A_D", ROAD_KERB_UV, (164, 157, 144)),
    "dash": ("TP_Atlas_Simple_Road_Flat", ROAD_DASH_UV, (252, 251, 128)),
    "crosswalk": ("TP_Atlas_Simple_Road_Flat", (11.5 / 32.0, 1.0 - 15.6 / 16.0), (236, 230, 224)),
    "concrete_light": ("TP_Atlas_1A_D", ROAD_KERB_UV, (164, 157, 144)),
    "concrete_mid": ("TP_Atlas_1A_D", (14.5 / 32.0, 1.0 - 11.6 / 16.0), (122, 122, 122)),
    "concrete_cap": ("TP_Atlas_1A_D", (19.5 / 32.0, 1.0 - 5.2 / 16.0), (174, 165, 149)),
    "tunnel_dark": ("TP_Atlas_1A_D", (0.5 / 32.0, 1.0 - 15.8 / 16.0), (36, 35, 36)),
    "steel_dark": ("TP_Atlas_1A_D", (16.5 / 32.0, 1.0 - 1.4 / 16.0), (60, 60, 60)),
    "ground_green": ("TP_Atlas_1A_D", (9.5 / 32.0, 1.0 - 9.4 / 16.0), (105, 135, 79)),
    "sign_green": ("TP_Atlas_1A_D", (27.5 / 32.0, 1.0 - 1.6 / 16.0), (13, 111, 58)),
    "white": ("TP_Atlas_1A_D", (11.5 / 32.0, 1.0 - 15.6 / 16.0), (236, 230, 224)),
    "yellow": ("TP_Atlas_1A_D", (19.5 / 32.0, 1.0 - 10.4 / 16.0), (245, 192, 34)),
}

# Rebound material table matching convert_toon_batch.py / toon_post_import.gd.
MAT_DEFS = {
    "TP_Atlas_1A_D": "tp_atlas_1a_d.png",
    "TP_Atlas_Simple_1A_D": "tp_atlas_1a_d.png",
    "TP_Atlas_Simple_Road_Flat": "tp_atlas_1a_d.png",
    "TC_Road_1A_D": "tc_road_1a_d.png",
    "TC_Tree_1A_D": "tc_tree_1a_d.png",
    "TC_Tree_3A_D": "tc_tree_3a_d.png",
}

FBX_MAT_MAP = {
    ("TP", "Atlas_1A_D"): "TP_Atlas_1A_D",
    ("TP", "Atlas_Simple_1A_D"): "TP_Atlas_Simple_1A_D",
    ("TC", "Road_1A_D"): "TC_Road_1A_D",
    ("TC", "Tree_1A_D"): "TC_Tree_1A_D",
    ("TC", "Tree_3A_D"): "TC_Tree_3A_D",
}

# Road extension dimensions in Godot metres relative to (x=±43, y=0, z=-46).
EXT_LEN = 113.0
EXT_HALF_ROAD_Z = 4.75
EXT_HALF_TOTAL_Z = 6.00
ROAD_Y = 0.10
SIDEWALK_Y = 0.20
ROAD_BOTTOM_Y = 0.0
SKIRT_BOTTOM_Y = -0.12
DASH_Y = 0.1065
DASH_HALF_Z = 0.18
DASH_LEN = 3.96
DASH_PITCH = 6.50
DASH_FIRST_X = 0.526  # 37.026 + 6.50 - 43.0 = 0.526 (seamless with Road's last dash)
DASH_COUNT = 17

# Tunnel portal dimensions in Godot metres relative to mouth at (x=±136, y=0, z=-46).
PORTAL_BORE_HALF_Z = 5.35
PORTAL_WALL_OUTER_Z = 6.45
PORTAL_CLEAR_H = 4.55
PORTAL_HAUNCH_Z = 4.50
PORTAL_HAUNCH_Y = 3.75
PORTAL_TOP_Y = 5.70
PORTAL_LEN = 20.0
PORTAL_BACKSTOP_X = 19.2
BERM_OUTER_Z = 11.5
BERM_REAR_X = 25.5


class BuildFail(Exception):
    pass


def die(msg):
    print("STREET_FAIL", msg, flush=True)
    sys.exit(1)


def log(*args):
    print("STREET", *args, flush=True)


def g2b(x, y, z):
    """Godot (x, y_up, z) -> Blender (x, -z, y_up)."""
    return Vector((x, -z, y))


def ensure_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    png = MAT_DEFS[name]
    path = os.path.join(TEX_DIR, png)
    img = bpy.data.images.load(path, check_existing=True)
    if img.size[0] == 0:
        die("atlas failed to load: %s" % path)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def verify_swatches():
    path = os.path.join(TEX_DIR, "tp_atlas_1a_d.png")
    img = bpy.data.images.load(path, check_existing=True)
    w, h = img.size
    px = img.pixels[:]
    for name, (_mat, uv, expected) in SWATCHES.items():
        ix = min(max(int(uv[0] * w), 0), w - 1)
        iy = min(max(int(uv[1] * h), 0), h - 1)
        idx = (iy * w + ix) * 4
        rgb = tuple(round(c * 255) for c in px[idx : idx + 3])
        if name in ("steel_dark",):
            continue
        if any(abs(a - b) > 16 for a, b in zip(rgb, expected)):
            die("swatch %s at uv=%s gave %s, expected %s" % (name, uv, rgb, expected))
    log("SWATCHES verified=%d" % len(SWATCHES))


def add_quad_godot(bm, uvl, pts_godot, uv, expected_normal_godot=None, mat_idx=0):
    """Add a single quad from 4 Godot-space points, enforcing expected normal."""
    verts = [bm.verts.new(g2b(*p)) for p in pts_godot]
    f = bm.faces.new(verts)
    f.material_index = mat_idx
    f.normal_update()
    if expected_normal_godot is not None:
        bn = g2b(*expected_normal_godot).normalized()
        if f.normal.dot(bn) < 0.0:
            bmesh.ops.reverse_faces(bm, faces=[f])
            f.normal_update()
        if f.normal.dot(bn) < 0.9:
            die("quad normal %s deviates from %s" % (tuple(f.normal), tuple(bn)))
    for lp in f.loops:
        lp[uvl].uv = uv
    return f


def make_mesh_object(name, bm, mat_names, parent=None):
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    names = [mat_names] if isinstance(mat_names, str) else list(mat_names)
    for mat_name in names:
        me.materials.append(ensure_material(mat_name))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def add_box_godot(bm, uvl, x0, x1, y0, y1, z0, z1, uv, skip_faces=()):
    """Axis-aligned box in Godot axes with outward normals and optional omitted faces."""
    faces = {
        "-x": [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
        "+x": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
        "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
        "+y": [(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)],
        "-z": [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)],
        "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
    }
    norms = {
        "-x": (-1, 0, 0), "+x": (1, 0, 0),
        "-y": (0, -1, 0), "+y": (0, 1, 0),
        "-z": (0, 0, -1), "+z": (0, 0, 1),
    }
    for key, pts in faces.items():
        if key in skip_faces:
            continue
        add_quad_godot(bm, uvl, pts, uv, norms[key])


def add_prism_godot(bm, uvl, ring_xz_lo, y_lo, ring_xz_hi, y_hi, uv, cap_top=True):
    """Build an extruded tapered prism between two ordered CCW/CW XZ loops at y_lo..y_hi."""
    n = len(ring_xz_lo)
    # Compute centroid in XZ to enforce outward side normals.
    cx = sum(p[0] for p in ring_xz_lo) / n
    cz = sum(p[1] for p in ring_xz_lo) / n
    for i in range(n):
        j = (i + 1) % n
        ax, az = ring_xz_lo[i]
        bx, bz = ring_xz_lo[j]
        cx_hi, cz_hi = ring_xz_hi[j]
        dx_hi, dz_hi = ring_xz_hi[i]
        mx, mz = (ax + bx) * 0.5 - cx, (az + bz) * 0.5 - cz
        # Approximate outward normal along side
        edge = Vector((bx - ax, 0.0, bz - az))
        side_out = Vector((-edge.z, 0.0, edge.x))
        if side_out.x * mx + side_out.z * mz < 0:
            side_out = -side_out
        if side_out.length > 1e-6:
            side_out.normalize()
        pts = [(ax, y_lo, az), (bx, y_lo, bz), (cx_hi, y_hi, cz_hi), (dx_hi, y_hi, dz_hi)]
        verts = [bm.verts.new(g2b(*p)) for p in pts]
        f = bm.faces.new(verts)
        f.normal_update()
        if side_out.length > 1e-6 and f.normal.dot(g2b(side_out.x, 0.0, side_out.z)) < 0.0:
            bmesh.ops.reverse_faces(bm, faces=[f])
            f.normal_update()
        for lp in f.loops:
            lp[uvl].uv = uv
    if cap_top:
        top_pts = [(p[0], y_hi, p[1]) for p in ring_xz_hi]
        verts = [bm.verts.new(g2b(*p)) for p in top_pts]
        f = bm.faces.new(verts)
        f.normal_update()
        if f.normal.dot(g2b(0, 1, 0)) < 0.0:
            bmesh.ops.reverse_faces(bm, faces=[f])
            f.normal_update()
        for lp in f.loops:
            lp[uvl].uv = uv


# ------------------------------------------------------------ 1. road extension


def build_road_ext():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.data.objects.new("Road_Ext_ROOT", None)
    bpy.context.scene.collection.objects.link(root)

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    x0, x1 = 0.0, EXT_LEN
    z0, z1 = -EXT_HALF_TOTAL_Z, -EXT_HALF_ROAD_Z
    z2, z3 = EXT_HALF_ROAD_Z, EXT_HALF_TOTAL_Z

    # Slot 0: TP_Atlas_Simple_1A_D (outlined) for kerb risers and upper outer sidewalk edges.
    # Slot 1: TP_Atlas_Simple_Road_Flat (outline-free) for flat asphalt, flat sidewalk tops, and lower skirts.
    # Tops: north sidewalk (1), asphalt carriageway (1), south sidewalk (1).
    add_quad_godot(bm, uvl, [(x0, SIDEWALK_Y, z0), (x1, SIDEWALK_Y, z0), (x1, SIDEWALK_Y, z1), (x0, SIDEWALK_Y, z1)], ROAD_SIDEWALK_UV, (0, 1, 0), mat_idx=1)
    add_quad_godot(bm, uvl, [(x0, ROAD_Y, z1), (x1, ROAD_Y, z1), (x1, ROAD_Y, z2), (x0, ROAD_Y, z2)], ROAD_ASPHALT_UV, (0, 1, 0), mat_idx=1)
    add_quad_godot(bm, uvl, [(x0, SIDEWALK_Y, z2), (x1, SIDEWALK_Y, z2), (x1, SIDEWALK_Y, z3), (x0, SIDEWALK_Y, z3)], ROAD_SIDEWALK_UV, (0, 1, 0), mat_idx=1)

    # Inner kerb risers (share vertices with asphalt and sidewalk edges: zero T-junctions).
    add_quad_godot(bm, uvl, [(x0, ROAD_Y, z1), (x1, ROAD_Y, z1), (x1, SIDEWALK_Y, z1), (x0, SIDEWALK_Y, z1)], ROAD_KERB_UV, (0, 0, 1), mat_idx=0)
    add_quad_godot(bm, uvl, [(x0, ROAD_Y, z2), (x1, ROAD_Y, z2), (x1, SIDEWALK_Y, z2), (x0, SIDEWALK_Y, z2)], ROAD_KERB_UV, (0, 0, -1), mat_idx=0)

    # Outer skirts down to SKIRT_BOTTOM_Y = -0.12 (sitting cleanly into Ground y = -0.10):
    # lower skirt (SKIRT_BOTTOM_Y..ROAD_Y) is outline-free; upper sidewalk edge (ROAD_Y..SIDEWALK_Y) keeps outline.
    add_quad_godot(bm, uvl, [(x0, SKIRT_BOTTOM_Y, z0), (x1, SKIRT_BOTTOM_Y, z0), (x1, ROAD_Y, z0), (x0, ROAD_Y, z0)], ROAD_KERB_UV, (0, 0, -1), mat_idx=1)
    add_quad_godot(bm, uvl, [(x0, ROAD_Y, z0), (x1, ROAD_Y, z0), (x1, SIDEWALK_Y, z0), (x0, SIDEWALK_Y, z0)], ROAD_KERB_UV, (0, 0, -1), mat_idx=0)
    add_quad_godot(bm, uvl, [(x0, SKIRT_BOTTOM_Y, z3), (x1, SKIRT_BOTTOM_Y, z3), (x1, ROAD_Y, z3), (x0, ROAD_Y, z3)], ROAD_KERB_UV, (0, 0, 1), mat_idx=1)
    add_quad_godot(bm, uvl, [(x0, ROAD_Y, z3), (x1, ROAD_Y, z3), (x1, SIDEWALK_Y, z3), (x0, SIDEWALK_Y, z3)], ROAD_KERB_UV, (0, 0, 1), mat_idx=0)

    # Far end cap at x1 (x0 is left open where it butts against tp_airport_site.glb Road).
    # Split sidewalk end caps at ROAD_Y so inner kerb bottom corners never form T-junctions.
    add_quad_godot(bm, uvl, [(x1, SKIRT_BOTTOM_Y, z0), (x1, SKIRT_BOTTOM_Y, z1), (x1, ROAD_Y, z1), (x1, ROAD_Y, z0)], ROAD_KERB_UV, (1, 0, 0), mat_idx=1)
    add_quad_godot(bm, uvl, [(x1, ROAD_Y, z0), (x1, ROAD_Y, z1), (x1, SIDEWALK_Y, z1), (x1, SIDEWALK_Y, z0)], ROAD_KERB_UV, (1, 0, 0), mat_idx=0)
    add_quad_godot(bm, uvl, [(x1, SKIRT_BOTTOM_Y, z1), (x1, SKIRT_BOTTOM_Y, z2), (x1, ROAD_Y, z2), (x1, ROAD_Y, z1)], ROAD_ASPHALT_UV, (1, 0, 0), mat_idx=1)
    add_quad_godot(bm, uvl, [(x1, SKIRT_BOTTOM_Y, z2), (x1, SKIRT_BOTTOM_Y, z3), (x1, ROAD_Y, z3), (x1, ROAD_Y, z2)], ROAD_KERB_UV, (1, 0, 0), mat_idx=1)
    add_quad_godot(bm, uvl, [(x1, ROAD_Y, z2), (x1, ROAD_Y, z3), (x1, SIDEWALK_Y, z3), (x1, SIDEWALK_Y, z2)], ROAD_KERB_UV, (1, 0, 0), mat_idx=0)

    road_obj = make_mesh_object("Road_Ext", bm, ["TP_Atlas_Simple_1A_D", "TP_Atlas_Simple_Road_Flat"], root)

    # Single-sided up-facing dashes matching tp_airport_site.glb centreline.
    dbm = bmesh.new()
    duvl = dbm.loops.layers.uv.new("UVMap")
    for k in range(DASH_COUNT):
        dx0 = DASH_FIRST_X + k * DASH_PITCH
        dx1 = min(dx0 + DASH_LEN, EXT_LEN - 0.5)
        if dx1 <= dx0:
            break
        add_quad_godot(
            dbm, duvl,
            [(dx0, DASH_Y, -DASH_HALF_Z), (dx1, DASH_Y, -DASH_HALF_Z), (dx1, DASH_Y, DASH_HALF_Z), (dx0, DASH_Y, DASH_HALF_Z)],
            ROAD_DASH_UV, (0, 1, 0),
        )
    make_mesh_object("Road_Ext_Dashes", dbm, "TP_Atlas_Simple_Road_Flat", root)

    # Verify zero T-junctions on Road_Ext.
    pts = [v.co.copy() for v in road_obj.data.vertices]
    edges = [tuple(e.vertices) for e in road_obj.data.edges]
    for i, j in edges:
        a, b = pts[i], pts[j]
        d = b - a
        l2 = d.length_squared
        if l2 < 1e-10:
            continue
        for k, v in enumerate(pts):
            if k in (i, j):
                continue
            t = (v - a).dot(d) / l2
            if 1e-5 < t < 1.0 - 1e-5 and (a + d * t - v).length < 1e-4:
                die("T-junction on Road_Ext at vertex %d on edge (%d,%d)" % (k, i, j))
    return export_and_verify("landside_road_ext")


# ------------------------------------------------------------ 2. tunnel portal


def build_tunnel_portal():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.data.objects.new("Portal_ROOT", None)
    bpy.context.scene.collection.objects.link(root)

    uv_cl = SWATCHES["concrete_light"][1]
    uv_cm = SWATCHES["concrete_mid"][1]
    uv_cc = SWATCHES["concrete_cap"][1]
    uv_dark = SWATCHES["tunnel_dark"][1]
    uv_steel = SWATCHES["steel_dark"][1]
    uv_green = SWATCHES["ground_green"][1]
    uv_sgreen = SWATCHES["sign_green"][1]
    uv_white = SWATCHES["white"][1]
    uv_yellow = SWATCHES["yellow"][1]

    # A. Portal Structure: headwall, piers, wing walls, brow sign, crest guardrail.
    sbm = bmesh.new()
    suvl = sbm.loops.layers.uv.new("UVMap")

    # Side piers + outer tunnel walls resting on y = SIDEWALK_Y (0.20) inside |z| <= 6.00,
    # and dropping outer wall skirt to y = SKIRT_BOTTOM_Y outside |z| = 6.00.
    for side in (-1.0, 1.0):
        z_in = side * PORTAL_BORE_HALF_Z
        z_out = side * PORTAL_WALL_OUTER_Z
        z_a, z_b = sorted((z_in, z_out))
        # Upper pier / barrel wall (above sidewalk y 0.20)
        add_box_godot(sbm, suvl, -0.35, PORTAL_LEN, SIDEWALK_Y, PORTAL_TOP_Y - 0.15, z_a, z_b, uv_cm)
        # Outer base plinth wrapping below y=0.20 outside |z|=6.00 down to ground skirt
        oz_a, oz_b = sorted((side * EXT_HALF_TOTAL_Z, side * (PORTAL_WALL_OUTER_Z + 0.20)))
        add_box_godot(sbm, suvl, -0.45, PORTAL_LEN, SKIRT_BOTTOM_Y, 0.75, oz_a, oz_b, uv_cl)
        # Front pier column accent cap
        add_box_godot(sbm, suvl, -0.50, 1.35, 0.75, PORTAL_TOP_Y, z_a - 0.12, z_b + 0.12, uv_cl)

        # Flared wing wall extending forward (x = -4.2..0.0) strictly outside |z| >= 6.00
        wz_a, wz_b = sorted((side * EXT_HALF_TOTAL_Z, side * (PORTAL_WALL_OUTER_Z + 0.15)))
        # Stepped wing-wall segments for crisp low-poly faceted silhouette
        add_box_godot(sbm, suvl, -2.0, -0.45, SKIRT_BOTTOM_Y, 2.85, wz_a, wz_b, uv_cm)
        add_box_godot(sbm, suvl, -2.05, -0.40, 2.85, 3.02, wz_a - 0.06, wz_b + 0.06, uv_cc)
        add_box_godot(sbm, suvl, -4.0, -2.0, SKIRT_BOTTOM_Y, 1.45, wz_a, wz_b, uv_cm)
        add_box_godot(sbm, suvl, -4.05, -1.95, 1.45, 1.62, wz_a - 0.06, wz_b + 0.06, uv_cc)
        # End wing-wall terminal post
        add_box_godot(sbm, suvl, -4.45, -3.95, SKIRT_BOTTOM_Y, 1.80, wz_a - 0.08, wz_b + 0.08, uv_cl)

    # Portal lintel & roof slab over tunnel bore (x = -0.35..PORTAL_LEN, y = PORTAL_CLEAR_H..PORTAL_TOP_Y)
    add_box_godot(
        sbm, suvl,
        -0.35, PORTAL_LEN,
        PORTAL_CLEAR_H, PORTAL_TOP_Y,
        -PORTAL_WALL_OUTER_Z, PORTAL_WALL_OUTER_Z,
        uv_cm,
    )
    # Front portal lintel collar & chamfered coping rim
    add_box_godot(sbm, suvl, -0.55, 1.40, PORTAL_CLEAR_H - 0.05, PORTAL_TOP_Y + 0.15, -PORTAL_WALL_OUTER_Z - 0.18, PORTAL_WALL_OUTER_Z + 0.18, uv_cl)
    add_box_godot(sbm, suvl, -0.62, 1.45, PORTAL_TOP_Y + 0.15, PORTAL_TOP_Y + 0.35, -PORTAL_WALL_OUTER_Z - 0.25, PORTAL_WALL_OUTER_Z + 0.25, uv_cc)
    # Safety yellow portal clearance trim bar across the arch brow
    add_box_godot(sbm, suvl, -0.60, 0.05, PORTAL_CLEAR_H - 0.08, PORTAL_CLEAR_H + 0.22, -PORTAL_BORE_HALF_Z, PORTAL_BORE_HALF_Z, uv_yellow)

    # Diagonal concrete arch haunches at front mouth (x = -0.45..0.55)
    for side in (-1.0, 1.0):
        pts_a = [
            (-0.45, PORTAL_HAUNCH_Y, side * PORTAL_BORE_HALF_Z),
            (-0.45, PORTAL_CLEAR_H, side * PORTAL_HAUNCH_Z),
            (-0.45, PORTAL_CLEAR_H, side * PORTAL_BORE_HALF_Z),
        ]
        verts_f = [sbm.verts.new(g2b(*p)) for p in pts_a]
        f = sbm.faces.new(verts_f)
        f.normal_update()
        if f.normal.dot(g2b(-1, 0, 0)) < 0:
            bmesh.ops.reverse_faces(sbm, faces=[f])
        for lp in f.loops:
            lp[suvl].uv = uv_cl

        # Sloped soffit face inside mouth
        add_quad_godot(
            sbm, suvl,
            [
                (-0.45, PORTAL_HAUNCH_Y, side * PORTAL_BORE_HALF_Z),
                (PORTAL_LEN, PORTAL_HAUNCH_Y, side * PORTAL_BORE_HALF_Z),
                (PORTAL_LEN, PORTAL_CLEAR_H, side * PORTAL_HAUNCH_Z),
                (-0.45, PORTAL_CLEAR_H, side * PORTAL_HAUNCH_Z),
            ],
            uv_dark,
            (0.0, -0.7, -side * 0.7),
        )

    # Highway gantry sign mounted on front portal brow (x = -0.75..-0.55)
    add_box_godot(sbm, suvl, -0.70, -0.52, 4.92, 6.02, -3.55, 3.55, uv_white)
    add_box_godot(sbm, suvl, -0.74, -0.66, 5.00, 5.94, -3.45, 3.45, uv_sgreen)
    # Stylized white route stripe + twin direction chevrons/bars
    add_box_godot(sbm, suvl, -0.77, -0.72, 5.54, 5.74, -2.95, 0.85, uv_white)
    add_box_godot(sbm, suvl, -0.77, -0.72, 5.20, 5.38, -2.95, 0.15, uv_white)
    add_box_godot(sbm, suvl, -0.77, -0.72, 5.24, 5.72, 1.55, 2.85, uv_yellow)

    # Overpass crest safety guardrail (x = 0.90..1.15, y = PORTAL_TOP_Y+0.35 .. +1.10)
    rail_base = PORTAL_TOP_Y + 0.35
    for pz in (-5.6, -3.8, -1.9, 0.0, 1.9, 3.8, 5.6):
        add_box_godot(sbm, suvl, 0.96, 1.08, rail_base, rail_base + 0.75, pz - 0.06, pz + 0.06, uv_steel)
    add_box_godot(sbm, suvl, 0.94, 1.10, rail_base + 0.64, rail_base + 0.76, -5.8, 5.8, uv_cl)
    add_box_godot(sbm, suvl, 0.95, 1.09, rail_base + 0.34, rail_base + 0.44, -5.8, 5.8, uv_steel)

    # Rear closing concrete wall at x = PORTAL_LEN..PORTAL_LEN+0.4
    add_box_godot(sbm, suvl, PORTAL_LEN, PORTAL_LEN + 0.40, SKIRT_BOTTOM_Y, PORTAL_TOP_Y, -PORTAL_WALL_OUTER_Z, PORTAL_WALL_OUTER_Z, uv_cm)

    make_mesh_object("Portal_Structure", sbm, "TP_Atlas_1A_D", root)

    # B. Portal Interior Dark Liner & Backstop at local x = 19.2 (world x = ±155.2)
    ibm = bmesh.new()
    iuvl = ibm.loops.layers.uv.new("UVMap")
    # Dark interior wall panels just inside the bore (|z| = 5.32) + ceiling (y = 4.52) + backstop
    add_quad_godot(ibm, iuvl, [(0.1, SIDEWALK_Y, -5.32), (PORTAL_BACKSTOP_X, SIDEWALK_Y, -5.32), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H - 0.03, -5.32), (0.1, PORTAL_CLEAR_H - 0.03, -5.32)], uv_dark, (0, 0, 1))
    add_quad_godot(ibm, iuvl, [(0.1, SIDEWALK_Y, 5.32), (PORTAL_BACKSTOP_X, SIDEWALK_Y, 5.32), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H - 0.03, 5.32), (0.1, PORTAL_CLEAR_H - 0.03, 5.32)], uv_dark, (0, 0, -1))
    add_quad_godot(ibm, iuvl, [(0.1, PORTAL_CLEAR_H - 0.03, -5.32), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H - 0.03, -5.32), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H - 0.03, 5.32), (0.1, PORTAL_CLEAR_H - 0.03, 5.32)], uv_dark, (0, -1, 0))
    # Solid dark backstop wall facing mouth (-X) at x = PORTAL_BACKSTOP_X (19.2 m -> world ±155.2 m)
    add_quad_godot(
        ibm, iuvl,
        [(PORTAL_BACKSTOP_X, ROAD_Y, -5.35), (PORTAL_BACKSTOP_X, ROAD_Y, 5.35), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H, 5.35), (PORTAL_BACKSTOP_X, PORTAL_CLEAR_H, -5.35)],
        uv_dark, (-1, 0, 0),
    )
    make_mesh_object("Portal_Interior", ibm, "TP_Atlas_1A_D", root)

    # C. Landscaped Grass-Berm Embankment over north side, south side, rear, and top crown.
    # Split cleanly outside |z| >= PORTAL_WALL_OUTER_Z and behind x >= PORTAL_LEN so the
    # tunnel bore stays 100% unobstructed from mouth to dark backstop.
    bbm = bmesh.new()
    buvl = bbm.loops.layers.uv.new("UVMap")

    # Concrete retaining base plinths wrapping north, south, and rear edges (y = -0.12..0.28).
    plinth_parts = [
        ([(1.40, -BERM_OUTER_Z), (BERM_REAR_X, -BERM_OUTER_Z), (PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (1.40, -PORTAL_WALL_OUTER_Z)],
         [(1.50, -BERM_OUTER_Z + 0.15), (BERM_REAR_X - 0.15, -BERM_OUTER_Z + 0.15), (PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (1.50, -PORTAL_WALL_OUTER_Z)]),
        ([(1.40, PORTAL_WALL_OUTER_Z), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z), (BERM_REAR_X, BERM_OUTER_Z), (1.40, BERM_OUTER_Z)],
         [(1.50, PORTAL_WALL_OUTER_Z), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z), (BERM_REAR_X - 0.15, BERM_OUTER_Z - 0.15), (1.50, BERM_OUTER_Z - 0.15)]),
        ([(PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (BERM_REAR_X, -BERM_OUTER_Z), (BERM_REAR_X, BERM_OUTER_Z), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z)],
         [(PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (BERM_REAR_X - 0.15, -BERM_OUTER_Z + 0.15), (BERM_REAR_X - 0.15, BERM_OUTER_Z - 0.15), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z)]),
    ]
    for lo_r, hi_r in plinth_parts:
        add_prism_godot(bbm, buvl, lo_r, SKIRT_BOTTOM_Y, hi_r, 0.28, uv_cm, cap_top=True)

    # Mitered green berm embankment slopes climbing from plinth to tunnel roof (y = 0.25 -> 5.70).
    slope_parts = [
        # North embankment slope (z <= -6.30)
        ([(1.50, -BERM_OUTER_Z + 0.15), (BERM_REAR_X - 0.15, -BERM_OUTER_Z + 0.15), (PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (1.50, -PORTAL_WALL_OUTER_Z)],
         [(1.75, -7.15), (PORTAL_LEN + 1.60, -7.15), (PORTAL_LEN + 0.20, -6.30), (1.75, -6.30)]),
        # South embankment slope (z >= +6.30)
        ([(1.50, PORTAL_WALL_OUTER_Z), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z), (BERM_REAR_X - 0.15, BERM_OUTER_Z - 0.15), (1.50, BERM_OUTER_Z - 0.15)],
         [(1.75, 6.30), (PORTAL_LEN + 0.20, 6.30), (PORTAL_LEN + 1.60, 7.15), (1.75, 7.15)]),
        # Rear embankment slope (x >= PORTAL_LEN + 0.20)
        ([(PORTAL_LEN + 0.40, -PORTAL_WALL_OUTER_Z), (BERM_REAR_X - 0.15, -BERM_OUTER_Z + 0.15), (BERM_REAR_X - 0.15, BERM_OUTER_Z - 0.15), (PORTAL_LEN + 0.40, PORTAL_WALL_OUTER_Z)],
         [(PORTAL_LEN + 0.20, -6.30), (PORTAL_LEN + 1.60, -7.15), (PORTAL_LEN + 1.60, 7.15), (PORTAL_LEN + 0.20, 6.30)]),
    ]
    for lo_r, hi_r in slope_parts:
        add_prism_godot(bbm, buvl, lo_r, 0.25, hi_r, PORTAL_TOP_Y, uv_green, cap_top=True)

    # Raised hilltop grass crown sitting cleanly atop the tunnel roof slab (y = 5.68 -> 6.45).
    add_prism_godot(
        bbm, buvl,
        [(1.75, -7.15), (PORTAL_LEN + 1.60, -7.15), (PORTAL_LEN + 1.60, 7.15), (1.75, 7.15)],
        PORTAL_TOP_Y - 0.02,
        [(3.60, -3.50), (PORTAL_LEN - 0.80, -3.50), (PORTAL_LEN - 0.80, 3.50), (3.60, 3.50)],
        6.45,
        uv_green,
        cap_top=True,
    )
    make_mesh_object("Portal_Berm", bbm, "TP_Atlas_1A_D", root)

    return export_and_verify("landside_tunnel_portal")


# ------------------------------------------------------------ 3. bollard & crosswalk


def build_bollard():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.data.objects.new("Bollard_ROOT", None)
    bpy.context.scene.collection.objects.link(root)

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def add_cyl(r0, r1, y0, y1, uv, segs=10):
        ret = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=r0, radius2=r1, depth=y1 - y0,
        )
        verts = ret["verts"]
        bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, (y0 + y1) * 0.5)), verts=verts)
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                for lp in f.loops:
                    lp[uvl].uv = uv

    add_cyl(0.15, 0.14, 0.0, 0.08, SWATCHES["concrete_light"][1])
    add_cyl(0.11, 0.11, 0.08, 0.68, SWATCHES["tunnel_dark"][1])
    add_cyl(0.115, 0.115, 0.68, 0.82, SWATCHES["yellow"][1])
    add_cyl(0.11, 0.08, 0.82, 0.90, SWATCHES["tunnel_dark"][1])

    make_mesh_object("Bollard_Body", bm, "TP_Atlas_1A_D", root)
    return export_and_verify("landside_bollard")


def build_crosswalk():
    """Crisp single-sided zebra crosswalk spanning forecourt + through road (z -58.2..-41.6),
    skipping the centreline dashes (-46.25..-45.75) and forecourt throat (-50.85..-50.25)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.data.objects.new("Crosswalk_ROOT", None)
    bpy.context.scene.collection.objects.link(root)

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    uv_w = SWATCHES["crosswalk"][1]
    y = 0.012  # sits cleanly at road y 0.10 + 0.012 = 0.112
    half_x = 0.80
    bar_w = 0.44
    pitch = 0.88

    spans = [(-58.15, -51.10), (-50.00, -46.45), (-45.55, -41.65)]
    for za, zb in spans:
        z = za
        while z + bar_w <= zb + 1e-4:
            add_quad_godot(
                bm, uvl,
                [(-half_x, y, z), (half_x, y, z), (half_x, y, z + bar_w), (-half_x, y, z + bar_w)],
                uv_w, (0, 1, 0),
            )
            z += pitch

    make_mesh_object("Crosswalk_Stripes", bm, "TP_Atlas_Simple_Road_Flat", root)
    return export_and_verify("landside_crosswalk")


# ------------------------------------------------------------ 4. vendor props


VENDOR_PROPS = {
    "tc_streetlight_1a": ("TC", "Streetlight_1A.fbx", 0.70, 0.0),
    "tc_streetlight_2a": ("TC", "Streetlight_2A.fbx", 0.72, 0.0),
    "tc_tree_2d": ("TC", "Tree_2D.fbx", 0.72, 0.0),
    "tc_tree_3a": ("TC", "Tree_3A.fbx", 0.72, 0.0),
    "tp_pine_tree_02a": ("TP", "TP_Pine_Tree_02A.fbx", 0.80, 1.002),
    "tc_bush_2a": ("TC", "Bush_2A.fbx", 0.55, 0.0),
    "tp_signpost_01a": ("TP", "TP_Signpost_01A.fbx", 0.38, 0.0),
}


def convert_vendor_prop(stem, pack, fbx, scale, lift_z):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = os.path.join(TC_MODELS if pack == "TC" else TP_MODELS, fbx)
    bpy.ops.import_scene.fbx(filepath=path)
    bpy.context.view_layer.update()

    objs = list(bpy.context.scene.objects)
    for o in objs:
        if o.animation_data:
            o.animation_data_clear()
        if o.type != "MESH":
            continue
        # Remove loose verts/edges
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
        # Rebind materials to Toon names
        for slot in o.material_slots:
            if slot.material is None:
                die("%s %s has empty material slot" % (stem, o.name))
            raw = re.sub(r"\.\d{3}$", "", slot.material.name)
            key = (pack, raw)
            if key not in FBX_MAT_MAP:
                die("%s %s unmapped material %s" % (stem, o.name, key))
            slot.material = ensure_material(FBX_MAT_MAP[key])

    # Lift sunken roots in world Z (Blender up)
    if lift_z != 0.0:
        for o in objs:
            if o.type != "MESH":
                continue
            inv = o.matrix_world.inverted().to_3x3()
            off = inv @ Vector((0.0, 0.0, lift_z))
            for v in o.data.vertices:
                v.co += off
            o.data.update()
        bpy.context.view_layer.update()

    # Scale cleanly about world origin and bake scale into mesh data
    for o in objs:
        if o.parent is None:
            o.matrix_world = Matrix.Scale(scale, 4) @ o.matrix_world
    bpy.context.view_layer.update()

    for o in objs:
        if o.type != "MESH":
            continue
        loc, rot, scl = o.matrix_world.decompose()
        o.data.transform(Matrix.Diagonal(scl).to_4x4())
        o.matrix_world = Matrix.Translation(loc) @ rot.to_matrix().to_4x4()
        o.data.update()
    bpy.context.view_layer.update()

    return export_and_verify(stem)


# ------------------------------------------------------------ 5. export & verify


def write_scene_import(glb_path):
    imp = glb_path + ".import"
    line = 'import_script/path="%s"' % POST_IMPORT
    if os.path.exists(imp):
        with open(imp, encoding="utf-8") as fh:
            text = fh.read()
        if re.search(r"^import_script/path=.*$", text, flags=re.M):
            text = re.sub(r"^import_script/path=.*$", line, text, flags=re.M)
        else:
            text = text.replace("[params]\n", "[params]\n\n%s\n" % line, 1)
        text = re.sub(r"^gltf/embedded_image_handling=.*$", "gltf/embedded_image_handling=0", text, flags=re.M)
    else:
        text = (
            '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
            "%s\ngltf/embedded_image_handling=0\n" % line
        )
    with open(imp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def export_and_verify(stem):
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, stem + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_vertex_color="NONE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=False,
        export_morph=False,
        export_skins=False,
        export_animations=False,
    )

    # Re-read WRITTEN file on disk (never trust scene state alone).
    with open(out, "rb") as fh:
        data = fh.read()
    magic, _ver, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a valid GLB: %s" % out)
    jlen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20 : 20 + jlen])
    mats = [m["name"] for m in js.get("materials", [])]
    imgs = [im.get("name", "?") for im in js.get("images", [])]
    nodes = js.get("nodes", [])
    if not mats or any(m not in MAT_DEFS for m in mats):
        die("%s: bad materials in written GLB: %s" % (stem, mats))
    if not imgs:
        die("%s: written GLB has 0 atlas images (texture rebind missing!)" % stem)

    # Compute exact Godot-axis AABB from written accessors
    lo = [math.inf, math.inf, math.inf]
    hi = [-math.inf, -math.inf, -math.inf]
    tris = 0
    for mesh in js.get("meshes", []):
        for prim in mesh["primitives"]:
            if "TEXCOORD_0" not in prim["attributes"]:
                die("%s: primitive missing TEXCOORD_0" % stem)
            acc = js["accessors"][prim["attributes"]["POSITION"]]
            for k in range(3):
                lo[k] = min(lo[k], acc["min"][k])
                hi[k] = max(hi[k], acc["max"][k])
            tris += js["accessors"][prim["indices"]]["count"] // 3
    # Verify node transforms applied cleanly (world AABB)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    wpts = [o.matrix_world @ v.co for o in bpy.context.scene.objects if o.type == "MESH" for v in o.data.vertices]
    # Note gltf import gives Blender Z-up; convert to glTF Y-up: (x, z, -y)
    wlo = (min(p.x for p in wpts), min(p.z for p in wpts), min(-p.y for p in wpts))
    whi = (max(p.x for p in wpts), max(p.z for p in wpts), max(-p.y for p in wpts))

    write_scene_import(out)
    log(
        "WROTE %s bytes=%d tris=%d mats=%s imgs=%d size=(%.2f,%.2f,%.2f) min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)"
        % (
            stem, len(data), tris, mats, len(imgs),
            whi[0] - wlo[0], whi[1] - wlo[1], whi[2] - wlo[2],
            wlo[0], wlo[1], wlo[2], whi[0], whi[1], whi[2],
        )
    )
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    verify_swatches()
    build_road_ext()
    build_tunnel_portal()
    build_bollard()
    build_crosswalk()
    for stem, spec in VENDOR_PROPS.items():
        convert_vendor_prop(stem, *spec)
    log("ALL_DONE")


main()
