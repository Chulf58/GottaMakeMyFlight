"""Build the terminal interior kit and export one .glb per piece.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_interior_kit.py' [-- piece ...]

Conventions (they match game/build/build_view.gd so a piece drops in unchanged):
- Blender X is Godot X, Blender -Y is Godot +Z (the grid's +y, the object's front),
  Blender Z is Godot Y. The exporter writes +Y up.
- An object's origin is the centre of its footprint at the walking surface (height 0),
  with its front facing Godot +Z at facing 0.
- A wall's origin is the midpoint of its cell edge at height 0, its long axis Godot X.
- The floor tile's walking surface is at height 0; the slab hangs 0.04 m below it.

Colour comes from the shared palette atlases. Every face is UV-mapped to a measured
swatch (column, row, fraction down the swatch); broad panels span a short vertical part
of the swatch gradient, small fittings take one point. Material names are exactly the
names toon_post_import.gd binds, so Godot assigns the shared toon .tres materials.
The glTF carries no images: the binder replaces every material by name.

Each export is verified by re-reading the WRITTEN file: the GLB JSON (materials,
images, nodes) and a re-import into an empty scene (world bounds, UVs inside their
swatches). Any mismatch prints KIT_FAIL and exits 1.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEXTURES = os.path.join(REPO, "game", "assets", "textures")
OUT_DIR = os.path.join(REPO, "game", "assets", "interior")
BLEND_OUT = os.path.join(REPO, "tools", "blender", "out", "interior_kit", "interior_kit.blend")
POST_IMPORT = "res://assets/toon_post_import.gd"

WALL_H = 2.5
WALL_T = 0.12
TRIM_T = 0.14
DOOR_W = 0.8
DOOR_H = 2.2

# Material name -> (atlas png, columns, rows). Glass uses its own gradient texture.
ATLASES = {
    "TP_Atlas_1A_D": ("tp_atlas_1a_d.png", 32, 16),
    "TP_Atlas_Lights_1A_D": ("tp_atlas_lights_1a_d.png", 16, 8),
    "TP_Glass_1A_D": ("tp_glass_gradient_1a_d.png", 1, 1),
}
# Empty atlas areas: a UV that samples one of these is a mapping error.
EMPTY_RGB = {(51, 51, 51), (0, 0, 0)}

# name -> (material, column, row, fraction from the swatch top, vertical span).
PALETTE = {
    "floor": ("TP_Atlas_1A_D", 14, 14, 0.38, 0.0),
    "wall": ("TP_Atlas_1A_D", 22, 0, 0.12, 0.22),
    "trim": ("TP_Atlas_1A_D", 0, 4, 0.30, 0.0),
    "frame": ("TP_Atlas_1A_D", 6, 4, 0.45, 0.0),
    "dark": ("TP_Atlas_1A_D", 16, 1, 0.40, 0.0),
    "metal": ("TP_Atlas_1A_D", 12, 11, 0.25, 0.15),
    "wood": ("TP_Atlas_1A_D", 19, 0, 0.30, 0.20),
    "top": ("TP_Atlas_1A_D", 11, 14, 0.12, 0.0),
    "white": ("TP_Atlas_1A_D", 11, 14, 0.15, 0.18),
    "blue": ("TP_Atlas_1A_D", 9, 4, 0.25, 0.20),
    "yellow": ("TP_Atlas_1A_D", 1, 13, 0.50, 0.0),
    "glass": ("TP_Glass_1A_D", 0, 0, 0.0, 1.0),
    "screen": ("TP_Atlas_Lights_1A_D", 7, 0, 0.50, 0.0),
    "screen_sky": ("TP_Atlas_Lights_1A_D", 6, 0, 0.50, 0.0),
    "text_white": ("TP_Atlas_Lights_1A_D", 9, 0, 0.50, 0.0),
    "text_yellow": ("TP_Atlas_Lights_1A_D", 1, 0, 0.50, 0.0),
    "lamp_green": ("TP_Atlas_Lights_1A_D", 4, 0, 0.50, 0.0),
}

_images = {}
_materials = {}
FAILS = []


def log(msg):
    print(msg, flush=True)


def fail(msg):
    FAILS.append(msg)
    log("KIT_FAIL " + msg)


# ---------------------------------------------------------------- atlas


def atlas(mat):
    if mat not in _images:
        png, cols, rows = ATLASES[mat]
        img = bpy.data.images.load(os.path.join(TEXTURES, png), check_existing=True)
        _images[mat] = (img, img.size[0], img.size[1], img.pixels[:], cols, rows)
    return _images[mat]


def sample_rgb(mat, u, v):
    _img, w, h, px, _c, _r = atlas(mat)
    x = min(w - 1, max(0, int(u * w)))
    y = min(h - 1, max(0, int(v * h)))
    i = (y * w + x) * 4
    return tuple(round(px[i + k] * 255) for k in range(3))


def swatch_uv(pal, t):
    """UV for palette entry `pal` at t in [0, 1] along its vertical span (0 = top)."""
    mat, col, row, frac, span = PALETTE[pal]
    _img, _w, _h, _px, cols, rows = atlas(mat)
    f = frac + span * t
    return (col + 0.5) / cols, 1.0 - (row + f) / rows


def material(mat):
    if mat in _materials:
        return _materials[mat]
    m = bpy.data.materials.new(mat)
    if hasattr(m, "use_nodes"):
        m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = atlas(mat)[0]
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    if mat == "TP_Glass_1A_D":
        bsdf.inputs["Alpha"].default_value = 0.3
    _materials[mat] = m
    return m


# ---------------------------------------------------------------- geometry


def _finish_mesh(name, bm, pal, parent, coll):
    """Map every loop into the palette swatch: v follows height when the entry spans."""
    uv = bm.loops.layers.uv.verify()
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    for face in bm.faces:
        face.smooth = False
        for loop in face.loops:
            t = 0.0 if z1 - z0 < 1e-6 else (z1 - loop.vert.co.z) / (z1 - z0)
            loop[uv].uv = swatch_uv(pal, t)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(PALETTE[pal][0]))
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = parent
    return ob


def box(name, lo, hi, pal, parent, coll, bevel=0.0, rot_x=0.0, pivot=None):
    """An axis box from lo to hi (Blender metres), optionally tilted about X at pivot."""
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = hi - lo
    centre = (lo + hi) / 2.0
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45),
            segments=1, affect="EDGES", profile=0.5,
        )
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    if rot_x:
        p = Vector(pivot if pivot is not None else centre)
        m = Matrix.Translation(p) @ Matrix.Rotation(math.radians(rot_x), 4, "X") @ Matrix.Translation(-p)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _finish_mesh(name, bm, pal, parent, coll)


def cyl(name, x, y, z0, z1, r, pal, parent, coll, segs=8):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=z1 - z0)
    bmesh.ops.translate(bm, vec=Vector((x, y, (z0 + z1) / 2.0)), verts=bm.verts)
    return _finish_mesh(name, bm, pal, parent, coll)


def bevel_top_slab(name, half, z0, z1, chamfer, pal, parent, coll):
    """A floor slab whose top edges are chamfered, so a seam reads between tiles."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((2 * half, 2 * half, z1 - z0)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, (z0 + z1) / 2.0)), verts=bm.verts)
    top = [e for e in bm.edges if all(abs(v.co.z - z1) < 1e-6 for v in e.verts)]
    bmesh.ops.bevel(bm, geom=top, offset=chamfer, segments=1, affect="EDGES", profile=0.5)
    return _finish_mesh(name, bm, pal, parent, coll)


# ---------------------------------------------------------------- pieces
# Each builder takes (root, coll) and adds its parts. Parts named in KEEP_SEPARATE stay
# their own node (animated or replaceable); the rest join into <Piece>_Body.


def wall_shell(root, c, length_lo=-0.5, length_hi=0.5):
    box("Wall_Skirting", (length_lo, -TRIM_T / 2, 0), (length_hi, TRIM_T / 2, 0.12), "trim", root, c)
    box("Wall_Cap", (length_lo, -TRIM_T / 2, WALL_H - 0.06), (length_hi, TRIM_T / 2, WALL_H), "trim", root, c)


def build_floor_tile(root, c):
    bevel_top_slab("Floor_Slab", 0.5, -0.04, 0.0, 0.015, "floor", root, c)


def build_wall(root, c):
    box("Wall_Panel", (-0.5, -WALL_T / 2, 0.12), (0.5, WALL_T / 2, WALL_H - 0.06), "wall", root, c)
    wall_shell(root, c)


def build_wall_post(root, c):
    box("Post", (-0.08, -0.08, 0), (0.08, 0.08, WALL_H + 0.04), "trim", root, c, bevel=0.015)


def build_wall_glass(root, c):
    box("Glass_Kerb", (-0.5, -TRIM_T / 2, 0), (0.5, TRIM_T / 2, 0.22), "trim", root, c)
    box("Glass_Header", (-0.5, -WALL_T / 2, WALL_H - 0.32), (0.5, WALL_T / 2, WALL_H - 0.06), "wall", root, c)
    box("Glass_Cap", (-0.5, -TRIM_T / 2, WALL_H - 0.06), (0.5, TRIM_T / 2, WALL_H), "trim", root, c)
    for side, x0, x1 in (("L", -0.5, -0.45), ("R", 0.45, 0.5)):
        box("Glass_Mullion_" + side, (x0, -0.05, 0.22), (x1, 0.05, WALL_H - 0.32), "frame", root, c)
    box("Glass_Transom", (-0.45, -0.04, 1.40), (0.45, 0.04, 1.44), "frame", root, c)
    box("Glass_Pane", (-0.45, -0.012, 0.22), (0.45, 0.012, WALL_H - 0.32), "glass", root, c)


def build_wall_door(root, c):
    jamb = (1.0 - DOOR_W) / 2.0 - 0.04
    for side, x0, x1 in (("L", -0.5, -0.5 + jamb), ("R", 0.5 - jamb, 0.5)):
        box("Door_Jamb_" + side, (x0, -WALL_T / 2, 0.12), (x1, WALL_T / 2, DOOR_H + 0.04), "wall", root, c)
        box("Door_Skirting_" + side, (x0, -TRIM_T / 2, 0), (x1, TRIM_T / 2, 0.12), "trim", root, c)
    box("Door_Lintel", (-0.5, -WALL_T / 2, DOOR_H + 0.04), (0.5, WALL_T / 2, WALL_H - 0.06), "wall", root, c)
    box("Door_Cap", (-0.5, -TRIM_T / 2, WALL_H - 0.06), (0.5, TRIM_T / 2, WALL_H), "trim", root, c)
    hw = DOOR_W / 2.0
    for side, x0, x1 in (("L", -hw - 0.04, -hw), ("R", hw, hw + 0.04)):
        box("Door_Frame_" + side, (x0, -0.075, 0), (x1, 0.075, DOOR_H + 0.04), "frame", root, c)
    box("Door_Frame_Top", (-hw - 0.04, -0.075, DOOR_H), (hw + 0.04, 0.075, DOOR_H + 0.04), "frame", root, c)
    box("Door_Threshold", (-hw, -0.075, 0), (hw, 0.075, 0.01), "dark", root, c)
    # Sliding track on the front face (Godot +Z). The leaves park open behind the
    # neighbouring wall faces; they clear skirting, cap and posts (|y| <= 0.08) by 3 cm.
    box("Door_Track", (-0.86, -0.15, DOOR_H + 0.04), (0.86, -0.10, DOOR_H + 0.14), "frame", root, c)
    for side, sign in (("L", -1.0), ("R", 1.0)):
        leaf = bpy.data.objects.new("Door_Leaf_" + side, None)
        c.objects.link(leaf)
        leaf.parent = root
        leaf.empty_display_size = 0.2
        # Open-parked: centre 0.61 m off the door axis. Closed is +-0.21 (travel 0.40 m).
        leaf.location = (sign * 0.61, -0.12, 0.0)
        lw = 0.21
        z0, z1, st = 0.02, DOOR_H + 0.03, 0.04
        box("Door_Leaf_%s_StileA" % side, (-lw, -0.012, z0), (-lw + st, 0.012, z1), "frame", leaf, c)
        box("Door_Leaf_%s_StileB" % side, (lw - st, -0.012, z0), (lw, 0.012, z1), "frame", leaf, c)
        box("Door_Leaf_%s_RailLow" % side, (-lw + st, -0.012, z0), (lw - st, 0.012, z0 + 0.08), "frame", leaf, c)
        box("Door_Leaf_%s_RailTop" % side, (-lw + st, -0.012, z1 - st), (lw - st, 0.012, z1), "frame", leaf, c)
        box("Door_Leaf_%s_Glass" % side, (-lw + st, -0.008, z0 + 0.08), (lw - st, 0.008, z1 - st), "glass", leaf, c)


def build_checkin_desk(root, c):
    # Left cell (x < 0): the counter the passenger stands in front of (interaction cell).
    box("Desk_ToeKick", (-0.88, -0.33, 0), (-0.06, 0.38, 0.08), "dark", root, c)
    box("Desk_Body", (-0.90, -0.38, 0.08), (-0.04, 0.40, 1.0), "wood", root, c)
    box("Desk_Band", (-0.85, -0.395, 0.58), (-0.09, -0.38, 0.74), "blue", root, c)
    box("Desk_Top", (-0.92, -0.42, 1.0), (-0.02, 0.42, 1.08), "top", root, c, bevel=0.015)
    # Agent monitor behind the counter, facing the agent (Godot -Z).
    box("Desk_Monitor_Neck", (-0.50, 0.26, 1.08), (-0.44, 0.30, 1.2), "dark", root, c)
    box("Desk_Monitor", (-0.67, 0.28, 1.18), (-0.27, 0.32, 1.44), "dark", root, c, bevel=0.01)
    box("Desk_Monitor_Face", (-0.64, 0.32, 1.21), (-0.30, 0.33, 1.41), "screen_sky", root, c)
    # Right cell: the bag drop belt, running front to back.
    box("Belt_Body", (0.05, -0.42, 0), (0.92, 0.40, 0.32), "metal", root, c, bevel=0.01)
    box("Belt_Top", (0.12, -0.42, 0.32), (0.85, 0.40, 0.355), "dark", root, c)
    for side, x0, x1 in (("L", 0.05, 0.12), ("R", 0.85, 0.92)):
        box("Belt_Rail_" + side, (x0, -0.42, 0.32), (x1, 0.40, 0.46), "frame", root, c)
    # Desk number sign on a pole standing on the back of the right rail, away from
    # the approach.
    cyl("Sign_Pole", 0.885, 0.32, 0.46, 1.62, 0.025, "frame", root, c)
    box("Sign_Face", (0.56, 0.28, 1.50), (0.92, 0.32, 1.78), "yellow", root, c, bevel=0.012)


def build_security_scanner(root, c):
    # Panels x 0.36..0.42 with 1 cm inner strips: a 0.70 m clear passage.
    for side, s in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((s * 0.36, s * 0.42))
        box("Arch_Panel_" + side, (x0, -0.30, 0), (x1, 0.30, 2.2), "metal", root, c, bevel=0.02)
        xs = sorted((s * 0.36, s * 0.35))
        box("Arch_Strip_" + side, (xs[0], -0.22, 0.30), (xs[1], 0.22, 2.0), "blue", root, c)
        px0, px1 = sorted((s * 0.37, s * 0.42))
        for end, y0, y1 in (("F", -0.92, -0.30), ("B", 0.30, 0.92)):
            ry = -0.895 if end == "F" else 0.895
            box("Rail_Post_%s%s" % (side, end), (px0, ry - 0.025, 0), (px1, ry + 0.025, 0.92), "frame", root, c)
            box("Rail_%s%s" % (side, end), (px0, y0, 0.86), (px1, y1, 0.92), "yellow", root, c)
    box("Arch_Beam", (-0.42, -0.32, 2.2), (0.42, 0.32, 2.42), "frame", root, c, bevel=0.02)
    box("Arch_Lamp", (-0.08, -0.34, 2.27), (0.08, -0.32, 2.35), "lamp_green", root, c)
    box("Scanner_Mat", (-0.35, -0.92, 0), (0.35, 0.92, 0.012), "dark", root, c)


# The sit clips put the seat contact at about 0.53 m (article toon-asset-pipeline):
# the pan top is SEAT_LIFT + 0.46. The backrest top stays at 0.88.
SEAT_LIFT = 0.07


def build_seat_row(root, c):
    box("Seat_Beam", (-1.42, 0.0, SEAT_LIFT + 0.30), (1.42, 0.08, SEAT_LIFT + 0.36), "frame", root, c)
    for i, x in enumerate((-1.2, 0.0, 1.2)):
        box("Seat_Leg_%d" % i, (x - 0.03, 0.01, 0.02), (x + 0.03, 0.07, SEAT_LIFT + 0.30), "frame", root, c)
        box("Seat_Foot_%d" % i, (x - 0.035, -0.25, 0), (x + 0.035, 0.30, 0.03), "dark", root, c)
    for i, x in enumerate((-1.08, -0.36, 0.36, 1.08)):
        box("Seat_Bracket_%d" % i, (x - 0.05, -0.05, SEAT_LIFT + 0.36), (x + 0.05, 0.10, SEAT_LIFT + 0.38), "frame", root, c)
        box("Seat_Pan_%d" % i, (x - 0.285, -0.32, SEAT_LIFT + 0.38), (x + 0.285, 0.18, SEAT_LIFT + 0.46), "blue", root, c, bevel=0.02)
        box(
            "Seat_Back_%d" % i, (x - 0.285, 0.16, SEAT_LIFT + 0.46), (x + 0.285, 0.24, 0.88), "blue", root, c,
            bevel=0.02, rot_x=-8.0, pivot=(x, 0.20, SEAT_LIFT + 0.46),
        )
    for i, x in enumerate((-1.395, -0.72, 0.0, 0.72, 1.395)):
        box("Arm_Post_%d" % i, (x - 0.02, 0.02, SEAT_LIFT + 0.36), (x + 0.02, 0.06, SEAT_LIFT + 0.62), "frame", root, c)
        box("Arm_%d" % i, (x - 0.025, -0.30, SEAT_LIFT + 0.62), (x + 0.025, 0.16, SEAT_LIFT + 0.66), "dark", root, c)


def build_kiosk(root, c):
    box("Kiosk_Plinth", (-0.30, -0.22, 0), (0.30, 0.24, 0.06), "dark", root, c)
    box("Kiosk_Body", (-0.26, -0.18, 0.06), (0.26, 0.20, 1.02), "white", root, c, bevel=0.015)
    box("Kiosk_Band", (-0.265, -0.185, 0.80), (0.265, 0.205, 0.90), "trim", root, c)
    box("Kiosk_Slot", (-0.10, -0.19, 0.55), (0.10, -0.18, 0.58), "dark", root, c)
    pivot = (0.0, -0.02, 1.02)
    box("Kiosk_Head", (-0.27, -0.10, 1.02), (0.27, 0.04, 1.48), "frame", root, c, bevel=0.012, rot_x=-22.0, pivot=pivot)
    box("Kiosk_Screen", (-0.22, -0.11, 1.07), (0.22, -0.10, 1.42), "screen_sky", root, c, rot_x=-22.0, pivot=pivot)
    # A label board behind the tilted head, standing on the back of the body.
    box("Kiosk_Label", (-0.20, 0.20, 1.02), (0.20, 0.24, 1.62), "yellow", root, c, bevel=0.01)


def build_info_screen(root, c):
    for side, x in (("L", -0.34), ("R", 0.34)):
        box("Info_Foot_" + side, (x - 0.05, -0.26, 0), (x + 0.05, 0.26, 0.05), "dark", root, c)
        cyl("Info_Post_" + side, x, 0.0, 0.05, 1.62, 0.03, "frame", root, c)
    box("Info_Housing", (-0.42, -0.06, 1.60), (0.42, 0.06, 2.20), "dark", root, c, bevel=0.015)
    box("Info_Header", (-0.42, -0.065, 2.20), (0.42, 0.065, 2.27), "yellow", root, c)
    # Screen_Face holds the whole display (background and colour bars), so a later
    # viewport texture can replace it as one node. Bars read at distance, not as text.
    face = bpy.data.objects.new("Screen_Face", None)
    c.objects.link(face)
    face.parent = root
    box("Screen_Face_Bg", (-0.39, -0.07, 1.64), (0.39, -0.06, 2.16), "screen", face, c)
    for row in range(5):
        z0 = 2.06 - row * 0.09
        pal = "text_yellow" if row % 2 == 0 else "text_white"
        box("Screen_Face_Bar_%dA" % row, (-0.36, -0.075, z0), (-0.04, -0.07, z0 + 0.045), pal, face, c)
        box("Screen_Face_Bar_%dB" % row, (0.02, -0.075, z0), (0.35, -0.07, z0 + 0.045), "text_white", face, c)


# piece -> (builder, footprint cells (x, y) or "edge", expected Blender bounds lo/hi).
# Furniture stays 0.08 m inside its footprint (half a wall post) so it clears a wall or
# post on any footprint edge: walls are centred on cell edges and reach 0.07-0.08 m in.
PIECES = {
    "floor_tile": (build_floor_tile, (1, 1), (-0.5, -0.5, -0.04), (0.5, 0.5, 0.0)),
    "wall": (build_wall, "edge", (-0.5, -0.07, 0.0), (0.5, 0.07, WALL_H)),
    "wall_post": (build_wall_post, "edge", (-0.08, -0.08, 0.0), (0.08, 0.08, WALL_H + 0.04)),
    "wall_glass": (build_wall_glass, "edge", (-0.5, -0.07, 0.0), (0.5, 0.07, WALL_H)),
    "wall_door": (build_wall_door, "edge", (-0.86, -0.15, 0.0), (0.86, 0.075, WALL_H)),
    "checkin_desk": (build_checkin_desk, (2, 1), (-0.92, -0.42, 0.0), (0.92, 0.42, 1.78)),
    "security_scanner": (build_security_scanner, (1, 2), (-0.42, -0.92, 0.0), (0.42, 0.92, 2.42)),
    "seat_row": (build_seat_row, (3, 1), (-1.42, -0.32, 0.0), (1.42, 0.30, 0.88)),
    "kiosk": (build_kiosk, (1, 1), (-0.30, -0.22, 0.0), (0.30, 0.24, 1.62)),
    "info_screen": (build_info_screen, (1, 1), (-0.42, -0.26, 0.0), (0.42, 0.26, 2.27)),
}
KEEP_SEPARATE = ("Door_Leaf_", "Screen_Face", "Sign_Face")
# Required nodes in each written file, beyond <Piece>_ROOT and <Piece>_Body.
EXTRA_NODES = {
    "wall_door": ["Door_Leaf_L", "Door_Leaf_L_Mesh", "Door_Leaf_R", "Door_Leaf_R_Mesh"],
    "checkin_desk": ["Sign_Face"],
    "info_screen": ["Screen_Face", "Screen_Face_Mesh"],
}
# Godot-frame translations of the animated nodes (open-parked door leaves).
NODE_TRANSLATIONS = {"Door_Leaf_L": (-0.61, 0.0, 0.12), "Door_Leaf_R": (0.61, 0.0, 0.12)}


def join_static(root, c, piece):
    """Join every part that is not animated or replaceable into <Piece>_Body."""
    groups = {}
    for ob in list(c.objects):
        if ob.type != "MESH":
            continue
        owner = ob.parent
        if ob.name.startswith(KEEP_SEPARATE) and owner is root:
            continue
        key = owner.name if owner is not root else root.name
        groups.setdefault(key, []).append(ob)
    for key, objs in groups.items():
        if len(objs) < 2 and objs[0].parent is root:
            objs[0].name = piece_title(piece) + "_Body"
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for ob in objs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = (piece_title(piece) + "_Body") if key == root.name else (key + "_Mesh")


def piece_title(piece):
    return "".join(p.capitalize() for p in piece.split("_"))


def build_piece(piece):
    builder = PIECES[piece][0]
    c = bpy.data.collections.new(piece_title(piece))
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new(piece_title(piece) + "_ROOT", None)
    c.objects.link(root)
    builder(root, c)
    bpy.context.view_layer.update()
    join_static(root, c, piece)
    for ob in c.objects:
        if ob.type == "MESH":
            ob.data.validate()
    bpy.context.view_layer.update()
    return root, c


# ---------------------------------------------------------------- export + verify


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or length != len(data):
        raise RuntimeError("not a GLB: %s" % path)
    clen, _ctype = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + clen].decode("utf-8")), len(data)


def write_scene_import(glb_path):
    path = glb_path + ".import"
    line = 'import_script/path="%s"' % POST_IMPORT
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if line not in text:
            fail("%s exists without the binder line; not overwriting" % path)
        return
    text = (
        '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
        "%s\ngltf/embedded_image_handling=0\n" % line
    )
    with open(path, "w", newline="\n") as f:
        f.write(text)


def export_piece(piece, root, c):
    out = os.path.join(OUT_DIR, piece + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for ob in c.objects:
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


def verify_written(piece, out):
    js, nbytes = parse_glb(out)
    mats = sorted(m["name"] for m in js.get("materials", []))
    nodes = sorted(n.get("name", "?") for n in js.get("nodes", []))
    want = sorted([piece_title(piece) + "_ROOT", piece_title(piece) + "_Body"] + EXTRA_NODES.get(piece, []))
    if nodes != want:
        fail("%s: nodes %s, expected %s" % (piece, nodes, want))
    by_name = {n.get("name"): n for n in js.get("nodes", [])}
    root_node = by_name.get(piece_title(piece) + "_ROOT", {})
    if any(abs(a) > 1e-6 for a in root_node.get("translation", [0, 0, 0])) or "rotation" in root_node:
        fail("%s: root node is not at the origin unrotated: %s" % (piece, root_node))
    for name, t in NODE_TRANSLATIONS.items():
        if name in by_name and max(abs(a - b) for a, b in zip(by_name[name].get("translation", [0, 0, 0]), t)) > 1e-4:
            fail("%s: %s translation %s, expected %s" % (piece, name, by_name[name].get("translation"), t))
    bad = [m for m in mats if m not in ATLASES]
    if bad:
        fail("%s: material names outside the binder map: %s" % (piece, bad))
    if js.get("images"):
        fail("%s: file carries %d images, expected 0" % (piece, len(js["images"])))
    # Re-import the written file into an empty scene: world bounds and UV swatches.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _images.clear()
    _materials.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    loops = 0
    outside = 0
    used = {}
    intended = intended_cells()
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        uvl = ob.data.uv_layers.active
        for poly in ob.data.polygons:
            mname = ob.data.materials[poly.material_index].name.split(".")[0]
            _img, _w, _h, _px, cols, rows = atlas(mname)
            cells = {(int(uvl.data[li].uv[0] * cols), int((1.0 - uvl.data[li].uv[1]) * rows))
                     for li in poly.loop_indices}
            if mname != "TP_Glass_1A_D" and len(cells) != 1:
                outside += len(poly.loop_indices)
            for li in poly.loop_indices:
                u, v = uvl.data[li].uv
                loops += 1
                if mname == "TP_Glass_1A_D":
                    ok = 0.0 <= u <= 1.0 and -1e-4 <= v <= 1.0001
                else:
                    fu, fv = u * cols % 1.0, (1.0 - v) * rows % 1.0
                    rgb = sample_rgb(mname, u, v)
                    cell = (mname, int(u * cols), int((1.0 - v) * rows))
                    ok = (0.0 < u < 1.0 and 0.0 < v < 1.0 and 0.2 < fu < 0.8 and 0.05 < fv < 0.95
                          and rgb not in EMPTY_RGB and cell in intended)
                    used[(mname, int(u * cols), int((1.0 - v) * rows))] = rgb
                if not ok:
                    outside += 1
    exp_lo, exp_hi = Vector(PIECES[piece][2]), Vector(PIECES[piece][3])
    err = max(max(abs(a - b) for a, b in zip(lo, exp_lo)), max(abs(a - b) for a, b in zip(hi, exp_hi)))
    log(
        "ASSET %s file=%s bytes=%d nodes=%s materials=%s images=%d meshes=%d"
        % (piece, os.path.relpath(out, REPO).replace("\\", "/"), nbytes, nodes, mats,
           len(js.get("images", [])), len(js.get("meshes", [])))
    )
    # Godot frame: x = Blender x, y = Blender z, z = -Blender y.
    log(
        "BOUNDS %s godot_min=(%.3f, %.3f, %.3f) godot_max=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f) "
        "max_err_vs_expected=%.4f"
        % (piece, lo.x, lo.z, -hi.y, hi.x, hi.z, -lo.y, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y, err)
    )
    log("UV %s loops=%d outside_swatch=%d swatches=%s" % (piece, loops, outside, sorted(used.items())))
    if err > 0.006:
        fail("%s: written bounds differ from expected by %.4f m" % (piece, err))
    if outside:
        fail("%s: %d UV loops outside their swatch or on an empty area" % (piece, outside))
    if loops == 0:
        fail("%s: no geometry in the written file" % piece)


def intended_cells():
    """The atlas cells PALETTE names, read at check time so a kit extension
    (build_cafe_kit.py) that adds entries is counted."""
    return {(m, c, r) for (m, c, r, _f, _s) in PALETTE.values()}


def report_palette():
    for name, (mat, col, row, frac, span) in PALETTE.items():
        if mat == "TP_Glass_1A_D":
            continue
        top = sample_rgb(mat, *swatch_uv(name, 0.0))
        bot = sample_rgb(mat, *swatch_uv(name, 1.0))
        log("PALETTE %-11s %s c%d r%d frac=%.2f span=%.2f rgb_top=%s rgb_bottom=%s"
            % (name, mat, col, row, frac, span, top, bot))


def main(default_pieces=None, blend_out=None):
    """Build, export and verify `-- piece ...` from the command line, else
    default_pieces, else every piece. A kit extension passes its own pieces and
    .blend path."""
    blend_out = blend_out or BLEND_OUT
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pieces = argv or default_pieces or list(PIECES)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(blend_out), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report_palette()
    written = []
    for piece in pieces:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _images.clear()
        _materials.clear()
        root, c = build_piece(piece)
        written.append((piece, export_piece(piece, root, c)))
    for piece, out in written:
        verify_written(piece, out)
    # The appendable .blend: every piece in its own collection, laid out in a row.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _images.clear()
    _materials.clear()
    x = 0.0
    for piece in pieces:
        root, _c = build_piece(piece)
        root.location.x = x
        x += 3.5
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=blend_out, compress=True)
    log("BLEND saved %s" % blend_out)
    log("KIT done pieces=%d fails=%d" % (len(written), len(FAILS)))
    if FAILS:
        sys.exit(1)
    return written


if __name__ == "__main__":
    main()
