"""Render three logotype options for "Gotta Make My Flight" (board item D6).

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\logo\\build_logos.py'

Options:
  a_sticker  chunky rounded two-line wordmark, navy outline and drop shadow, a small
             plane at the end of a dotted flight path.
  b_board    split-flap departure board: one letter per navy tile on a teal housing,
             a yellow plane tile closing the second row.
  c_toon3d   extruded 3D letters shaded with flat toon bands (front, inner navy line,
             two side tones), navy silhouette outline and drop shadow.

Font: Nunito (SIL Open Font License 1.1), read in place from
game/ui/fonts/Nunito-Variable.ttf, licence text in game/ui/fonts/OFL.txt. Blender loads
the variable font at its default ExtraLight instance, so the weight is added here. The
font's contours overlap (a variable-font trait), so curve bevel and curve offset both
throw mitre spikes and crossing lines at the hidden overlap corners. Instead each text
is filled by the font engine with the nonzero rule, turned into a mesh, and a geometry
nodes modifier takes the union of spheres of the weight radius over its surface (points
to volume, volume to mesh). That thickens every stroke evenly with round ends and
rounded 3D edges, and the overlaps melt into one surface.

Pipeline: each option renders in EEVEE with emission-only materials (exact palette
colours, Standard view transform) to a transparent linear EXR at 3840 px wide. The
outline is a disk dilation of the coverage mask and the shadow is that dilation moved
down; both are composited under the render in linear premultiplied RGBA. Everything
then goes down by area filtering, which antialiases the outline.

Outputs under tools/blender/out/logo/ (gitignored):
  logo_<opt>.png             transparent library logo, 1280 px wide
  capsule_small_<opt>.png    the logo on a 462x174 sky-blue small-capsule mock
  header_<opt>.png           the logo on a 920x430 sky-blue header mock
  contact_sheet.png          all three options side by side, left to right a, b, c

Every render proves its subject is inside the camera frame with a margin, and every
written PNG is read back and checked (size, clear border, transparent corners);
otherwise PROBE_INVALID and exit 1.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
import OpenImageIO as oiio
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FONT_PATH = os.path.join(REPO, "game", "ui", "fonts", "Nunito-Variable.ttf")
OUT = os.path.join(REPO, "tools", "blender", "out", "logo")
RAW = os.path.join(OUT, "raw")

MASTER_W = 3840
LOGO_W = 1280

# Palette (sRGB), from game/ui/hud_theme.tres and the HUD look ruling
# hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale.
NAVY = (0.10, 0.13, 0.26)
NAVY_DEEP = (0.055, 0.07, 0.15)
NAVY_TILE = (0.17, 0.21, 0.38)
CREAM = (0.99, 0.97, 0.92)
YELLOW = (1.00, 0.84, 0.44)
CORAL = (0.92, 0.45, 0.40)
CORAL_MID = (0.80, 0.36, 0.33)
CORAL_DARK = (0.62, 0.26, 0.27)
TEAL = (0.25, 0.68, 0.68)
TEAL_MID = (0.20, 0.55, 0.57)
TEAL_DARK = (0.15, 0.42, 0.46)
SKY = (0.55, 0.80, 0.93)

MOCKS = (
    # name, width, height, fraction of width and height the logo may fill
    ("capsule_small", 462, 174, 0.92, 0.86),
    ("header", 920, 430, 0.72, 0.62),
)


def fail(msg):
    print("PROBE_INVALID", msg)
    sys.exit(1)


def to_lin(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)


# ---------------------------------------------------------------- scene helpers


def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.eevee.taa_render_samples = 32
    scene.render.resolution_percentage = 100
    world = bpy.data.worlds.new("World")
    world.color = (0, 0, 0)
    scene.world = world
    font = bpy.data.fonts.load(FONT_PATH)
    return scene, font


def flat_mat(name, srgb):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = to_lin(srgb) + (1.0,)
    emit.inputs["Strength"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


def _mix(nt, fac, a, b):
    node = nt.nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    nt.links.new(fac, node.inputs[0])
    cols = [s for s in node.inputs if s.type == "RGBA"]
    for sock, val in ((cols[0], a), (cols[1], b)):
        if isinstance(val, tuple):
            sock.default_value = to_lin(val) + (1.0,)
        else:
            nt.links.new(val, sock)
    return [s for s in node.outputs if s.type == "RGBA"][0]


def _greater(nt, value, threshold):
    node = nt.nodes.new("ShaderNodeMath")
    node.operation = "GREATER_THAN"
    nt.links.new(value, node.inputs[0])
    node.inputs[1].default_value = threshold
    return node.outputs[0]


def toon_mat(name, front, side_mid, side_dark):
    """Flat toon bands from the object-space normal: front face, a navy inner line on
    the bevel, and two side tones (the right-facing sides darker)."""
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    coords = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coords.outputs["Normal"], sep.inputs[0])
    nx, nz = sep.outputs[0], sep.outputs[2]
    side = _mix(nt, _greater(nt, nx, 0.45), side_mid, side_dark)
    lined = _mix(nt, _greater(nt, nz, 0.50), side, NAVY)
    col = _mix(nt, _greater(nt, nz, 0.86), lined, front)
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(col, emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


def link(scene, obj, parent=None):
    scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def text_obj(scene, font, body, size, weight, mat, extrude=0.0, spacing=1.0, parent=None):
    cu = bpy.data.curves.new(body, "FONT")
    cu.body = body
    cu.font = font
    cu.size = size
    cu.fill_rule = "NONZERO"
    cu.extrude = max(extrude, 0.01)  # a closed solid, so the distance field has a sign
    cu.space_character = spacing
    cu.space_word = 1.1
    cu.resolution_u = 24
    tmp = bpy.data.objects.new(body + "_src", cu)
    scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    if len(me.polygons) == 0:
        fail("text %r produced no faces" % body)
    obj = link(scene, bpy.data.objects.new(body, me), parent)
    mod = obj.modifiers.new("embolden", "NODES")
    mod.node_group = embolden_group(weight, mat)
    # Positive control: the emboldened glyphs must be wider than the source by about
    # twice the weight, or the offset did nothing (or shrank them).
    src_w = max(v.co.x for v in me.vertices) - min(v.co.x for v in me.vertices)
    x0, x1, _, _ = local_bounds(obj)
    grown = (x1 - x0) - src_w
    print("PROBE embolden %r src_w=%.3f grown=%.3f expected=%.3f" % (body, src_w, grown, 2 * weight))
    if grown < 1.5 * weight:
        fail("emboldening did not grow %r" % body)
    return obj


def _sock(node, name, value):
    if name not in node.inputs:
        fail("node %s has no input %r (has %s)" % (node.bl_idname, name, [s.name for s in node.inputs]))
    node.inputs[name].default_value = value


def embolden_group(radius, mat):
    """Offset the mesh's signed distance field outward by `radius` (mesh to SDF grid,
    SDF grid offset, grid to mesh): an even, round-ended stroke thickening with rounded
    3D edges that ignores overlapping contours."""
    ng = bpy.data.node_groups.new("embolden", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n = ng.nodes
    gin = n.new("NodeGroupInput")
    gout = n.new("NodeGroupOutput")
    voxel = radius / 10.0
    sdf = n.new("GeometryNodeMeshToSDFGrid")
    _sock(sdf, "Voxel Size", voxel)
    _sock(sdf, "Band Width", int(math.ceil(radius / voxel)) + 4)
    grow = n.new("GeometryNodeSDFGridOffset")
    _sock(grow, "Distance", radius)
    tomesh = n.new("GeometryNodeGridToMesh")
    _sock(tomesh, "Threshold", 0.0)
    smooth = n.new("GeometryNodeSetShadeSmooth")
    setmat = n.new("GeometryNodeSetMaterial")
    _sock(setmat, "Material", mat)
    links = ng.links
    links.new(gin.outputs[0], sdf.inputs["Mesh"])
    links.new(sdf.outputs[0], grow.inputs["Grid"])
    links.new(grow.outputs[0], tomesh.inputs["Grid"])
    links.new(tomesh.outputs[0], smooth.inputs["Geometry"])
    links.new(smooth.outputs[0], setmat.inputs["Geometry"])
    links.new(setmat.outputs[0], gout.inputs[0])
    return ng


def poly_obj(scene, name, pts, mat, z=0.0, parent=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, z)) for x, y in pts]
    bm.faces.new(verts)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return link(scene, bpy.data.objects.new(name, me), parent)


def rounded_rect(cx, cy, w, h, r, seg=10):
    pts = []
    corners = ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
               (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270))
    for ox, oy, start in corners:
        for i in range(seg + 1):
            a = math.radians(start + 90 * i / seg)
            pts.append((cx + ox + r * math.cos(a), cy + oy + r * math.sin(a)))
    return pts


def circle(cx, cy, r, seg=20):
    return [(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg))
            for i in range(seg)]


# Top-view plane silhouette, nose at +x, length 2 (x from -1 to 1).
_PLANE_HALF = [(0.96, 0.06), (0.86, 0.11), (0.24, 0.11), (-0.12, 0.80), (-0.30, 0.80),
               (-0.20, 0.11), (-0.68, 0.09), (-0.86, 0.36), (-0.99, 0.36), (-0.93, 0.05)]


def plane_pts(cx, cy, half_len, angle_deg):
    outline = [(1.0, 0.0)] + _PLANE_HALF + [(-1.0, 0.0)]
    outline += [(x, -y) for x, y in reversed(_PLANE_HALF)]
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + half_len * (x * ca - y * sa), cy + half_len * (x * sa + y * ca)) for x, y in outline]


def local_bounds(obj):
    """Bounds of the evaluated object in its parent's space (no rotation applied)."""
    bpy.context.view_layer.update()
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    xs = [c[0] * obj.scale.x + obj.location.x for c in ev.bound_box]
    ys = [c[1] * obj.scale.y + obj.location.y for c in ev.bound_box]
    return min(xs), max(xs), min(ys), max(ys)


def place(obj, cx, cy):
    x0, x1, y0, y1 = local_bounds(obj)
    obj.location.x += cx - (x0 + x1) / 2
    obj.location.y += cy - (y0 + y1) / 2


def world_corners(objs):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in objs:
        ev = obj.evaluated_get(deps)
        pts += [obj.matrix_world @ Vector(c) for c in ev.bound_box]
    return pts


# ---------------------------------------------------------------- the three options


def build_a(scene, font):
    """Chunky rounded sticker wordmark with a plane on a dotted flight path."""
    l1 = text_obj(scene, font, "Gotta Make", 1.0, 0.050, flat_mat("cream", CREAM), spacing=1.10)
    l2 = text_obj(scene, font, "My Flight", 1.32, 0.066, flat_mat("yellow", YELLOW), spacing=1.10)
    place(l2, 0.0, 0.0)
    _, _, _, l2_top = local_bounds(l2)
    x0, x1, y0, y1 = local_bounds(l1)
    place(l1, -0.10, l2_top + 0.02 + (y1 - y0) / 2)
    x0, x1, y0, y1 = local_bounds(l1)
    # Flight path: starts just above the "G", rises clear of the cap line and ends at
    # the plane's tail above "Make". No dot sits behind a letter, so none is left
    # floating on its own.
    p0 = Vector((x0 + 0.05, y1 + 0.12))
    p1 = Vector((0.0, y1 + 0.42))
    p2 = Vector((x1 + 0.10, y1 + 0.32))
    heading = (p2 - p1).normalized()
    half = 0.48
    centre = p2 + heading * (half + 0.12)
    plane = poly_obj(scene, "plane", plane_pts(centre.x, centre.y, half, math.degrees(math.atan2(heading.y, heading.x)) + 8),
                     flat_mat("plane", CREAM))
    under = []
    dot_mat = flat_mat("trail", NAVY)
    n = 15
    for i in range(n):
        t = i / (n - 1) * 0.93
        p = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2
        under.append(poly_obj(scene, "dot%d" % i, circle(p.x, p.y, 0.055), dot_mat, z=-0.5))
    style = {"outline": 0.075, "shadow": (0.02, -0.085)}
    return [l1, l2, plane], under, style


def build_b(scene, font):
    """Split-flap departure board, one letter per tile."""
    tile_w, tile_h, gap, space_w, row_gap = 0.74, 1.0, 0.07, 0.30, 0.12
    tile_mat = flat_mat("tile", NAVY_TILE)
    split_mat = flat_mat("split", NAVY_DEEP)
    rows = (("GOTTA MAKE", flat_mat("cream", CREAM)), ("MY FLIGHT>", flat_mat("yellow", YELLOW)))
    objs = []
    widths = []
    for text, _ in rows:
        widths.append(sum(space_w if ch == " " else tile_w for ch in text) + gap * (len(text) - 1))
    for r, (text, letter_mat) in enumerate(rows):
        cy = (tile_h + row_gap) / 2 if r == 0 else -(tile_h + row_gap) / 2
        x = -widths[r] / 2
        for i, ch in enumerate(text):
            w = space_w if ch == " " else tile_w
            cx = x + w / 2
            x += w + gap
            if ch == " ":
                continue
            if ch == ">":
                objs.append(poly_obj(scene, "plane_tile", rounded_rect(cx, cy, tile_w, tile_h, 0.10),
                                     flat_mat("plane_tile", YELLOW), z=0.01))
                objs.append(poly_obj(scene, "plane", plane_pts(cx, cy, 0.33, 40), flat_mat("plane", NAVY), z=0.03))
                continue
            objs.append(poly_obj(scene, "tile%d_%d" % (r, i), rounded_rect(cx, cy, tile_w, tile_h, 0.10), tile_mat, z=0.01))
            glyph = text_obj(scene, font, ch, 0.86, 0.034, letter_mat)
            glyph.location.z = 0.02
            place(glyph, cx, cy)
            objs.append(glyph)
            objs.append(poly_obj(scene, "split%d_%d" % (r, i),
                                 [(cx - tile_w / 2, cy - 0.016), (cx + tile_w / 2, cy - 0.016),
                                  (cx + tile_w / 2, cy + 0.016), (cx - tile_w / 2, cy + 0.016)],
                                 split_mat, z=0.04))
    pad = 0.14
    house_w = max(widths) + 2 * pad
    house_h = 2 * tile_h + row_gap + 2 * pad
    objs.append(poly_obj(scene, "housing", rounded_rect(0, 0, house_w, house_h, 0.24), flat_mat("teal", TEAL), z=-0.02))
    style = {"outline": 0.065, "shadow": (0.02, -0.08)}
    return objs, [], style


def build_c(scene, font):
    """Extruded 3D toon letters, tilted so the bottom and right sides show."""
    root = bpy.data.objects.new("root", None)
    link(scene, root)
    l1 = text_obj(scene, font, "GOTTA MAKE", 0.82, 0.050, toon_mat("t_cream", CREAM, TEAL_MID, TEAL_DARK),
                  extrude=0.13, spacing=1.08, parent=root)
    l2 = text_obj(scene, font, "MY FLIGHT", 1.30, 0.072, toon_mat("t_yellow", YELLOW, CORAL_MID, CORAL_DARK),
                  extrude=0.20, spacing=1.06, parent=root)
    place(l2, 0.0, 0.0)
    _, _, _, l2_top = local_bounds(l2)
    _, _, y0, y1 = local_bounds(l1)
    place(l1, 0.0, l2_top + 0.10 + (y1 - y0) / 2)
    root.rotation_euler = (math.radians(-24), math.radians(-16), math.radians(3))
    style = {"outline": 0.06, "shadow": (0.02, -0.07)}
    return [l1, l2], [], style


# ---------------------------------------------------------------- render and composite


def frame_camera(scene, objs, style):
    pts = world_corners(objs)
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    reach = style["outline"] + max(abs(style["shadow"][0]), abs(style["shadow"][1]))
    pad = reach * 1.6 + 0.10
    cam_w, cam_h = w + 2 * pad, h + 2 * pad
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = cam_w
    cam_data.clip_end = 100
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, 20)
    scene.camera = cam
    scene.render.resolution_x = MASTER_W
    scene.render.resolution_y = int(round(MASTER_W * cam_h / cam_w))
    bpy.context.view_layer.update()
    margin = pad * 0.5 / cam_w
    proj = [world_to_camera_view(scene, cam, p) for p in pts]
    lo = (min(p.x for p in proj), min(p.y for p in proj))
    hi = (max(p.x for p in proj), max(p.y for p in proj))
    print("PROBE in_frame bounds_ndc lo=(%.3f,%.3f) hi=(%.3f,%.3f) margin=%.3f" % (lo + hi + (margin,)))
    if min(lo) < margin or max(hi) > 1 - margin:
        fail("subject outside the frame margin")
    return MASTER_W / cam_w  # pixels per world unit


def render_exr(scene, path):
    st = scene.render.image_settings
    try:
        st.media_type = "IMAGE"
    except (AttributeError, TypeError):
        pass
    st.file_format = "OPEN_EXR"
    st.color_mode = "RGBA"
    st.color_depth = "16"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    buf = oiio.ImageBuf(path)
    arr = buf.get_pixels(oiio.FLOAT)
    if arr is None or arr.ndim != 3 or arr.shape[2] < 4:
        fail("could not read render %s" % path)
    return np.ascontiguousarray(arr[:, :, :4])


def shifted(mask, dx, dy):
    out = np.zeros_like(mask)
    h, w = mask.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = mask[ys, xs]
    return out


def dilate(mask, radius):
    """Disk dilation, built from repeated small disks (their Minkowski sum is a disk)."""
    steps = max(1, int(math.ceil(radius / 4.0)))
    rr = radius / steps
    ri = int(math.ceil(rr))
    offs = [(dx, dy) for dx in range(-ri, ri + 1) for dy in range(-ri, ri + 1)
            if (dx or dy) and dx * dx + dy * dy <= rr * rr]
    m = mask
    for _ in range(steps):
        acc = m.copy()
        for dx, dy in offs:
            acc |= shifted(m, dx, dy)
        m = acc
    return m


def solid(mask, srgb):
    out = np.zeros(mask.shape + (4,), np.float32)
    out[mask] = to_lin(srgb) + (1.0,)
    return out


def over(top, bottom):
    return top + bottom * (1.0 - top[:, :, 3:4])


def composite(main, under, style, px_per_unit):
    mask = main[:, :, 3] > 0.5
    r_px = style["outline"] * px_per_unit
    outline = dilate(mask, r_px)
    sdx = int(round(style["shadow"][0] * px_per_unit))
    sdy = int(round(-style["shadow"][1] * px_per_unit))  # image rows grow downwards
    shadow = shifted(outline, sdx, sdy)
    print("PROBE composite outline_px=%.1f shadow_px=(%d,%d) mask_px=%d" % (r_px, sdx, sdy, int(mask.sum())))
    canvas = under if under is not None else np.zeros_like(main)
    canvas = over(solid(shadow, NAVY_DEEP), canvas)
    canvas = over(solid(outline, NAVY), canvas)
    return over(main, canvas)


def alpha_bbox(img, thresh=0.004):
    rows = np.where(img[:, :, 3].max(axis=1) > thresh)[0]
    cols = np.where(img[:, :, 3].max(axis=0) > thresh)[0]
    if rows.size == 0:
        fail("empty image")
    return rows[0], rows[-1] + 1, cols[0], cols[-1] + 1


def resize(img, w, h):
    src = oiio.ImageBuf(oiio.ImageSpec(img.shape[1], img.shape[0], img.shape[2], oiio.FLOAT))
    src.set_pixels(oiio.ROI(), np.ascontiguousarray(img, dtype=np.float32))
    dst = oiio.ImageBufAlgo.resize(src, filtername="blackman-harris",
                                   roi=oiio.ROI(0, w, 0, h, 0, 1, 0, img.shape[2]))
    return np.clip(dst.get_pixels(oiio.FLOAT), 0.0, None)


def encode(img_premul):
    """Linear premultiplied RGBA float to straight sRGB uint8."""
    a = np.clip(img_premul[:, :, 3:4], 0.0, 1.0)
    rgb = np.where(a > 1e-6, img_premul[:, :, :3] / np.maximum(a, 1e-6), 0.0)
    out = np.concatenate([to_srgb(rgb), a], axis=2)
    return (out * 255.0 + 0.5).astype(np.uint8)


def write_png(path, arr8):
    h, w, c = arr8.shape
    spec = oiio.ImageSpec(w, h, c, oiio.UINT8)
    spec.attribute("oiio:UnassociatedAlpha", 1)
    out = oiio.ImageOutput.create(path)
    if not out or not out.open(path, spec):
        fail("cannot open %s for writing: %s" % (path, oiio.geterror()))
    out.write_image(np.ascontiguousarray(arr8))
    out.close()


def read_png(path):
    cfg = oiio.ImageSpec()
    cfg.attribute("oiio:UnassociatedAlpha", 1)
    inp = oiio.ImageInput.open(path, cfg)
    if not inp:
        fail("cannot read back %s" % path)
    nch = inp.spec().nchannels
    arr = inp.read_image("uint8")
    inp.close()
    if arr is None:
        fail("empty read of %s" % path)
    arr = arr.reshape(arr.shape[0], arr.shape[1], nch)
    return arr


def verify_logo(path):
    arr = read_png(path)
    h, w, c = arr.shape
    a = arr[:, :, 3]
    border = max(a[:4].max(), a[-4:].max(), a[:, :4].max(), a[:, -4:].max())
    corners = (a[0, 0], a[0, -1], a[-1, 0], a[-1, -1])
    opaque = float((a == 255).mean())
    edge = float(((a > 0) & (a < 255)).mean())
    y0, y1, x0, x1 = alpha_bbox(arr.astype(np.float32) / 255.0)
    print("PROBE readback %s size=%dx%dx%d corners_alpha=%s border_alpha_max=%d opaque=%.3f edge=%.4f bbox=x%d-%d,y%d-%d"
          % (os.path.basename(path), w, h, c, corners, border, opaque, edge, x0, x1, y0, y1))
    if w != LOGO_W or h > 720 or c != 4 or border != 0 or max(corners) != 0 or opaque < 0.1:
        fail("logo readback check failed for %s" % path)
    return arr


def verify_mock(path, w, h, logo_box):
    arr = read_png(path)
    if arr.shape[0] != h or arr.shape[1] != w:
        fail("mock %s has size %s" % (path, arr.shape))
    x0, y0, lw, lh = logo_box
    print("PROBE readback %s size=%dx%d logo_box=x%d,y%d %dx%d fill_w=%.2f fill_h=%.2f"
          % (os.path.basename(path), w, h, x0, y0, lw, lh, lw / w, lh / h))
    if x0 < 2 or y0 < 2 or x0 + lw > w - 2 or y0 + lh > h - 2:
        fail("logo leaves the mock %s" % path)
    return arr


def build_option(key, builder):
    scene, font = new_scene()
    main_objs, under_objs, style = builder(scene, font)
    ppu = frame_camera(scene, main_objs + under_objs, style)
    for o in under_objs:
        o.hide_render = True
    main = render_exr(scene, os.path.join(RAW, "%s_main.exr" % key))
    under = None
    if under_objs:
        for o in under_objs:
            o.hide_render = False
        for o in main_objs:
            o.hide_render = True
        under = render_exr(scene, os.path.join(RAW, "%s_under.exr" % key))
    img = composite(main, under, style, ppu)
    y0, y1, x0, x1 = alpha_bbox(img)
    hh, ww = img.shape[:2]
    if y0 < 2 or x0 < 2 or y1 > hh - 2 or x1 > ww - 2:
        fail("composited %s touches the render edge" % key)
    tight = img[y0:y1, x0:x1]
    # Library logo: tight crop plus a 2% margin, scaled to 1280 wide.
    m = int(round(0.02 * tight.shape[1]))
    padded = np.zeros((tight.shape[0] + 2 * m, tight.shape[1] + 2 * m, 4), np.float32)
    padded[m:m + tight.shape[0], m:m + tight.shape[1]] = tight
    lh = int(round(padded.shape[0] * LOGO_W / padded.shape[1]))
    logo_path = os.path.join(OUT, "logo_%s.png" % key)
    write_png(logo_path, encode(resize(padded, LOGO_W, lh)))
    verify_logo(logo_path)
    for name, mw, mh, fw, fh in MOCKS:
        s = min(fw * mw / tight.shape[1], fh * mh / tight.shape[0])
        lw2, lh2 = int(round(tight.shape[1] * s)), int(round(tight.shape[0] * s))
        small = resize(tight, lw2, lh2)
        bg = np.zeros((mh, mw, 4), np.float32)
        bg[:, :] = to_lin(SKY) + (1.0,)
        ox, oy = (mw - lw2) // 2, (mh - lh2) // 2
        bg[oy:oy + lh2, ox:ox + lw2] = over(small, bg[oy:oy + lh2, ox:ox + lw2])
        path = os.path.join(OUT, "%s_%s.png" % (name, key))
        write_png(path, encode(bg)[:, :, :3])
        verify_mock(path, mw, mh, (ox, oy, lw2, lh2))


def contact_sheet(keys):
    col_w, gut = 920, 40
    cols = []
    for key in keys:
        logo = read_png(os.path.join(OUT, "logo_%s.png" % key)).astype(np.float32) / 255.0
        lw, lh = col_w, int(round(logo.shape[0] * col_w / logo.shape[1]))
        lin = np.concatenate([np.power(logo[:, :, :3], 2.2) * logo[:, :, 3:4], logo[:, :, 3:4]], axis=2)
        small = resize(lin, lw, lh)
        yy, xx = np.mgrid[0:lh, 0:lw]
        checker = np.where(((yy // 20 + xx // 20) % 2)[:, :, None] == 0, 0.80, 0.62).astype(np.float32)
        base = np.concatenate([np.repeat(checker, 3, axis=2) ** 2.2, np.ones((lh, lw, 1), np.float32)], axis=2)
        logo_on = to_srgb(over(small, base)[:, :, :3])
        header = read_png(os.path.join(OUT, "header_%s.png" % key)).astype(np.float32) / 255.0
        capsule = read_png(os.path.join(OUT, "capsule_small_%s.png" % key)).astype(np.float32) / 255.0
        cols.append((logo_on, header, capsule))
    row_h = (max(c[0].shape[0] for c in cols), 430, 174)
    sheet_w = len(keys) * col_w + (len(keys) + 1) * gut
    sheet_h = sum(row_h) + 4 * gut
    sheet = np.full((sheet_h, sheet_w, 3), 0.93, np.float32)
    for i, parts in enumerate(cols):
        x = gut + i * (col_w + gut)
        y = gut
        for part, rh in zip(parts, row_h):
            ph, pw = part.shape[:2]
            ox = x + (col_w - pw) // 2
            sheet[y:y + ph, ox:ox + pw] = part[:, :, :3]
            y += rh + gut
    path = os.path.join(OUT, "contact_sheet.png")
    write_png(path, (np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8))
    back = read_png(path)
    print("PROBE readback contact_sheet.png size=%dx%d" % (back.shape[1], back.shape[0]))


def main():
    os.makedirs(RAW, exist_ok=True)
    if not os.path.isfile(FONT_PATH):
        fail("font missing: %s" % FONT_PATH)
    options = (("a_sticker", build_a), ("b_board", build_b), ("c_toon3d", build_c))
    for key, builder in options:
        print("OPTION", key)
        build_option(key, builder)
    contact_sheet([k for k, _ in options])
    print("DONE")


main()
