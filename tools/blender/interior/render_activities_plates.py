"""Render the plates for the activities kit and check the seated fit numerically.

Run (headless, reproducible), after build_activities_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_activities_plates.py'

Everything is written under tools/blender/out/furniture-3/ (gitignored); nothing in
game/ is touched. The plates re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: front, back, left, right, top and bottom orthographic views at
  one scale per piece, true scale, with a 1 m reference cube offset diagonally;
- thumbs/<piece>.png: the build-menu thumbnail framing of render_kit_thumbnails.py
  (front-left 3/4, 256 px, transparent), with its in-frame and share checks, and
  thumbs/contact_sheet.png with each at 64 px on dark and on light;
- distance.png: every piece in a row, perspective, about 25 m out, a person for scale;
- context.png: a room with floor tiles, a back wall, seat_row and checkin_desk for
  scale, both characters (one seated on the sofa, one in the armchair, two standing), the
  vendor TP_SUV_01A on Mount_Car and vendor Metal_Pole_1A posts with chains around
  the podium (placeholder grey: the Toon City materials are not converted yet);
- sit/<piece>_*.png: the characters posed at sit_idle on each seat (front 3/4 and side)
  and sit_down / stand_up strips of five frames at one sofa and one desk seat.
Each plate proves its subjects are in frame (every vertex projected inside a margin)
and, where other objects could hide them, that they are visible (rays from the camera
to camera-facing face-centre samples hit the subject first). On failure: PROBE_INVALID
and exit 1.

Seated fit: for every sit mount and both characters, every frame of sit_down, sit_idle
and stand_up is checked. The furniture is rebuilt part by part with the builder's own
functions (each part a closed convex solid, as written before the join; every written
vertex must sit on a rebuilt one and back), and the posed character is tested against
each part twice: its evaluated vertices for containment, and every polygon the BVH
finds crossing the part, clipped to the part, with its inside portion sampled (corners,
edge midpoints, centroid), so a crossing with no vertex inside is measured too. Depth
is the nearest-face penetration depth. A cushion part (name with "_Seat_" or
"_BackCushion_") may take FIT_SOFT_M, any other part FIT_RIGID_M, and a part the body
enters whose half thickness is within its limit fails, since its depth could never
exceed the limit. Two negative controls
must fail the gate or the run stops: the seated body pushed 0.06 m down, and a triangle
slicing the thickest rigid part with all three corners outside it.

Toon look: copied from tools/blender/thumbnails/render_kit_thumbnails.py (emission-only
copy of toon.gdshader with the vendor ramp, unshaded lights, the glass gradient,
Freestyle outline); that module runs its main() on import and would rewrite
game/assets/ui/thumbnails. These are Blender plates: they are not evidence of the
in-engine look, which needs a windowed Godot render.
"""

import math
import os
import re
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_activities_kit as act  # noqa: E402
import build_interior_kit as kit  # noqa: E402

REPO = kit.REPO
KIT_DIR = kit.OUT_DIR
TEXTURES = kit.TEXTURES
PEOPLE = os.path.join(REPO, "game", "assets", "people")
OUT = os.path.join(REPO, "tools", "blender", "out", "furniture-3")
VENDOR = "C:\\Users\\chulf\\Assets new\\Toon Series"
SUV_FBX = os.path.join(VENDOR, "Toon Planes Pack", "Models", "TP_SUV_01A.fbx")
POLE_FBX = os.path.join(VENDOR, "Toon City", "Models", "Metal_Pole_1A.fbx")
CHAIN_FBX = os.path.join(VENDOR, "Toon City", "Models", "Metal_Pole_Chain_1A.fbx")

PIECES = list(act.PIECES)
SITS = [p for p in PIECES if any(k == "sit_root" for k, _p, _y in act.ACTIVITIES[p]["mounts"].values())]
CHARS = {"male": "tcp_male_character_01.glb", "female": "tcp_female_character_01.glb"}
FIT_SOFT_M = 0.03
FIT_RIGID_M = 0.01

MARGIN = 0.05
SUN = Vector((0.354, -0.612, 0.707)).normalized()
AMBIENT = 0.24
LIGHT_GAIN = 0.76
OUTLINE_RGB = (0.1, 0.1, 0.12)
GLASS_ALPHA = 0.29
GLASS_TINT = 0.85
CUBE_RGB = (0.78, 0.78, 0.80)
FLOOR_RGB = (0.62, 0.63, 0.66)
POLE_RGB = (0.62, 0.64, 0.68)
CHAIN_RGB = (0.30, 0.31, 0.34)
BACKDROP = (0.55, 0.57, 0.60)

# Thumbnail framing, as render_kit_thumbnails.py.
THUMB = 256
THUMB_SS = 2
THUMB_MIN_SHARE = 0.45
CAM_AZIMUTH = math.radians(-35.0)
CAM_ELEVATION = math.radians(30.0)
CLASSES = {
    "1x1": ((1.0, 1.0, 1.0), (0.0, 0.0, 0.5)),
    "2x1": ((2.0, 1.0, 1.6), (0.0, 0.0, 0.8)),
    "2x2": ((2.0, 2.0, 1.2), (0.0, 0.0, 0.6)),
    "6x3": ((6.0, 3.0, 0.6), (0.0, 0.0, 0.3)),
}

FAILS = []


def log(msg):
    print("PLATE " + msg, flush=True)


def invalid(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def base_name(name):
    return re.sub(r"\.\d{3}$", "", name)


# ---------------------------------------------------------------- materials

_images = {}
_materials = {}


def image(png, non_color=False):
    if png not in _images:
        img = bpy.data.images.load(os.path.join(TEXTURES, png), check_existing=True)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        _images[png] = img
    return _images[png]


def toon_material(key, atlas_png=None, ramp_png="tp_toon_ramp_1d_d.png", rgb=None):
    """Emission-only copy of toon.gdshader: albedo * (ramp(half_lambert) + ambient)."""
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new("PLATE_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    if rgb is not None:
        albedo = nt.nodes.new("ShaderNodeRGB")
        albedo.outputs[0].default_value = (*[srgb_to_linear(c) for c in rgb], 1.0)
        albedo_out = albedo.outputs[0]
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image(atlas_png)
        tex.interpolation = "Closest"
        albedo_out = tex.outputs["Color"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = SUN
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    hl = nt.nodes.new("ShaderNodeMath")
    hl.operation = "MULTIPLY_ADD"
    hl.use_clamp = True
    hl.inputs[1].default_value = 0.495
    hl.inputs[2].default_value = 0.5
    nt.links.new(dot.outputs["Value"], hl.inputs[0])
    uv = nt.nodes.new("ShaderNodeCombineXYZ")
    uv.inputs["Y"].default_value = 0.5
    nt.links.new(hl.outputs["Value"], uv.inputs["X"])
    ramp = nt.nodes.new("ShaderNodeTexImage")
    ramp.image = image(ramp_png, non_color=True)
    ramp.interpolation = "Closest"
    ramp.extension = "EXTEND"
    nt.links.new(uv.outputs["Vector"], ramp.inputs["Vector"])
    amb = nt.nodes.new("ShaderNodeVectorMath")
    amb.operation = "MULTIPLY_ADD"
    nt.links.new(ramp.outputs["Color"], amb.inputs[0])
    amb.inputs[1].default_value = (LIGHT_GAIN, LIGHT_GAIN, LIGHT_GAIN)
    amb.inputs[2].default_value = (AMBIENT, AMBIENT, AMBIENT)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(albedo_out, mul.inputs[0])
    nt.links.new(amb.outputs["Vector"], mul.inputs[1])
    nt.links.new(mul.outputs["Vector"], emit.inputs["Color"])
    _materials[key] = m
    return m


def unshaded_material(key, png):
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new("PLATE_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image(png)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _materials[key] = m
    return m


def glass_material(key):
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new("PLATE_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = GLASS_TINT
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image("tp_glass_gradient_1a_d.png")
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = GLASS_ALPHA
    nt.links.new(clear.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emit.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    _materials[key] = m
    return m


def plate_material(name):
    """The plate material for a source material name (kit glb, character glb, or the
    vendor FBX names the converter maps)."""
    n = base_name(name)
    if n in ("TP_Atlas_1A_D", "Atlas_1A_D", "TP_Atlas_Simple_1A_D", "Atlas_Simple_1A_D"):
        return toon_material("tp_atlas", "tp_atlas_1a_d.png")
    if n in ("TP_Atlas_Lights_1A_D", "Atlas_Lights_1A_D"):
        return unshaded_material("tp_lights", "tp_atlas_lights_1a_d.png")
    if n in ("TP_Glass_1A_D", "Glass_Vehicles_01A_D"):
        return glass_material("tp_glass")
    if n == "TCP_Atlas_1A_D":
        return toon_material("tcp_atlas", "tcp_atlas_1a_d.png", "tcp_toon_ramp_01d_d.png")
    return None


def bind(objs, label, placeholder=None):
    """Rebind every material slot; returns the source material names seen."""
    names = set()
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            if slot.material is None:
                invalid("%s: %s has an empty material slot" % (label, o.name))
            names.add(base_name(slot.material.name))
            m = plate_material(slot.material.name)
            if m is None and placeholder is not None:
                m = toon_material("flat_%s" % "_".join("%.2f" % c for c in placeholder), rgb=placeholder)
            if m is None:
                invalid("%s: unmapped material %s on %s" % (label, slot.material.name, o.name))
            slot.material = m
    return names


def flat(rgb):
    return toon_material("flat_%s" % "_".join("%.2f" % c for c in rgb), rgb=rgb)


# ---------------------------------------------------------------- scene


def reset_scene(res_x, res_y, line_px=1.5):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    _images.clear()
    kit._images.clear()
    kit._materials.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.cycles.transparent_max_bounces = 8
    scene.render.film_transparent = True
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("PLATE_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = line_px
    fs = scene.view_layers[0].freestyle_settings
    lineset = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("PLATE_Lines")
    lineset.select_by_visibility = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = True
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("PLATE_Outline")
    lineset.linestyle.color = OUTLINE_RGB
    lineset.linestyle.thickness = line_px
    return scene


def import_glb(path, label, holder_xf=None):
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    acts = [a for a in bpy.data.actions if a not in acts_before]
    names = bind(new, label)
    holder = None
    if holder_xf is not None:
        holder = bpy.data.objects.new("HOLD_" + label, None)
        bpy.context.scene.collection.objects.link(holder)
        holder.matrix_world = holder_xf
        for o in new:
            if o.parent is None:
                o.parent = holder
    bpy.context.view_layer.update()
    return new, acts, names, holder


def import_fbx(path, label, placeholder=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.animation_data:
            o.animation_data_clear()
    names = bind(new, label, placeholder)
    holder = bpy.data.objects.new("HOLD_" + label, None)
    bpy.context.scene.collection.objects.link(holder)
    for o in new:
        if o.parent is None:
            o.parent = holder
    bpy.context.view_layer.update()
    return new, names, holder


def meshes(objs):
    return [o for o in objs if o.type == "MESH"]


def world_points(objs):
    """Evaluated world-space vertices of the mesh objects (posed for skinned ones)."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes(objs):
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        n = len(me.vertices)
        co = np.empty(n * 3, dtype=np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(n, 3)
        m = np.array(mw)
        pts.append(co @ m[:3, :3].T + m[:3, 3])
        ev.to_mesh_clear()
    return np.concatenate(pts) if pts else np.zeros((0, 3))


def bounds(objs):
    p = world_points(objs)
    return Vector(p.min(axis=0)), Vector(p.max(axis=0))


def cube(centre, size=1.0):
    bpy.ops.mesh.primitive_cube_add(size=size, location=centre)
    ob = bpy.context.active_object
    ob.name = "Ref_Cube_1m"
    ob.data.materials.append(flat(CUBE_RGB))
    return ob


def floor_plane(lo, hi, z=0.0):
    sx, sy = hi[0] - lo[0], hi[1] - lo[1]
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, z))
    ob = bpy.context.active_object
    ob.scale = (sx, sy, 1.0)
    ob.name = "Plate_Floor"
    ob.data.materials.append(flat(FLOOR_RGB))
    return ob


def look_rot(direction, up):
    """Camera rotation whose -Z looks along -direction (direction = target to camera)."""
    z = Vector(direction).normalized()
    y = Vector(up) - z * Vector(up).dot(z)
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_quaternion()


def ortho_camera(scene, rot, pts, scale):
    data = bpy.data.cameras.new("PLATE_Cam")
    data.type = "ORTHO"
    cam = bpy.data.objects.new("PLATE_Cam", data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rot
    inv = np.array(rot.to_matrix().inverted())
    loc = pts @ inv.T
    mid = Vector(((loc[:, 0].min() + loc[:, 0].max()) / 2, (loc[:, 1].min() + loc[:, 1].max()) / 2,
                  loc[:, 2].max() + 50.0))
    cam.location = rot.to_matrix() @ mid
    data.ortho_scale = scale
    data.clip_start = 0.1
    data.clip_end = 400.0
    bpy.context.view_layer.update()
    return cam


def persp_camera(scene, location, target, lens=35.0):
    data = bpy.data.cameras.new("PLATE_Cam")
    data.lens = lens
    data.clip_start = 0.1
    data.clip_end = 400.0
    cam = bpy.data.objects.new("PLATE_Cam", data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = location
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = look_rot(Vector(location) - Vector(target), (0.0, 0.0, 1.0))
    bpy.context.view_layer.update()
    return cam


def screen_box(scene, cam, pts):
    xs, ys = [], []
    for p in pts:
        v = world_to_camera_view(scene, cam, Vector(p))
        if v.z <= cam.data.clip_start:
            return None
        xs.append(v.x)
        ys.append(v.y)
    return min(xs), min(ys), max(xs), max(ys)


def prove_in_frame(label, scene, cam, pts, min_share=0.0):
    box = screen_box(scene, cam, pts)
    if box is None:
        invalid("%s: a vertex is behind the camera" % label)
    share = max(box[2] - box[0], box[3] - box[1])
    log("%s in_frame u=[%.3f,%.3f] v=[%.3f,%.3f] share=%.2f margin=%.2f"
        % (label, box[0], box[2], box[1], box[3], share, MARGIN))
    if box[0] < MARGIN or box[1] < MARGIN or box[2] > 1 - MARGIN or box[3] > 1 - MARGIN:
        invalid("%s: subject leaves the frame margin" % label)
    if share < min_share:
        invalid("%s: subject spans only %.2f of the frame" % (label, share))
    return box


def visible_share(label, scene, cam, subject, samples=160, need=0.15):
    """Rays from the camera to the camera-facing surface samples of `subject`; the
    share whose first hit is the subject. Back-facing samples (a post's far side, the
    underside of a base standing on the floor) are invisible by construction and are
    not counted; at 1 cm under the floor they swamped thin subjects such as the posts."""
    dg = bpy.context.evaluated_depsgraph_get()
    own = {o.name for o in subject}
    pts = []
    for o in meshes(subject):
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        # Normals by the inverse transpose, so a non-uniformly scaled part (a stretched
        # chain) keeps them perpendicular to its faces.
        # Samples are face centres with face normals: a vertex on a thin post's
        # silhouette, pushed out along a smoothed normal, gave grazing rays that missed.
        nmat = mw.to_3x3().inverted_safe().transposed()
        step = max(1, len(me.polygons) // max(1, samples // max(1, len(meshes(subject)))))
        for f in (me.polygons[i] for i in range(0, len(me.polygons), step)):
            pts.append((mw @ f.center, (nmat @ f.normal).normalized(), o.name))
        ev.to_mesh_clear()
    origin = cam.matrix_world.translation
    total = len(pts)
    pts = [s for s in pts if s[1].dot(origin - s[0]) > 0.0]
    hit_n = 0
    first_hits = {}
    for p, nrm, _name in pts:
        target = p + nrm * 0.005
        d = target - origin
        dist = d.length
        ok, loc, _n, _i, ob, _m = scene.ray_cast(dg, origin, d.normalized(), distance=dist + 0.02)
        if ok and ob is not None and ob.original.name in own and (loc - target).length < 0.06:
            hit_n += 1
        else:
            key = (ob.original.name if ok and ob is not None else "<nothing>")
            first_hits[key] = first_hits.get(key, 0) + 1
    share = hit_n / max(1, len(pts))
    log("%s visible samples=%d facing=%d hit=%d share=%.2f need=%.2f"
        % (label, total, len(pts), hit_n, share, need))
    if share < need:
        log("%s blocked_by %s" % (label, sorted(first_hits.items(), key=lambda kv: -kv[1])[:8]))
        invalid("%s: only %.2f of the sampled surface is visible" % (label, share))
    return share


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    arr = px.reshape(h, w, 4)
    opaque = int((arr[:, :, 3] > 0.5).sum())
    log("rendered %s size=%dx%d opaque_px=%d" % (os.path.relpath(path, REPO).replace("\\", "/"), w, h, opaque))
    if opaque == 0:
        invalid("%s rendered empty" % path)
    return arr


def over(arr, bg):
    a = arr[:, :, 3:4]
    out = arr.copy()
    out[:, :, :3] = arr[:, :, :3] * a + np.array(bg, dtype=np.float32) * (1 - a)
    out[:, :, 3] = 1.0
    return out


def save_array(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    log("wrote %s size=%dx%d" % (os.path.relpath(path, REPO).replace("\\", "/"), w, h))


def grid(tiles, cols, gap=8, bg=(0.08, 0.08, 0.09)):
    """Tiles (top-left first) into one image; arrays are bottom-up, as Blender's."""
    th = max(t.shape[0] for t in tiles)
    tw = max(t.shape[1] for t in tiles)
    rows = math.ceil(len(tiles) / cols)
    H = rows * th + (rows + 1) * gap
    W = cols * tw + (cols + 1) * gap
    out = np.empty((H, W, 4), dtype=np.float32)
    out[:, :] = (*bg, 1.0)
    for n, t in enumerate(tiles):
        r, c = divmod(n, cols)
        y_top = gap + r * (th + gap)
        x0 = gap + c * (tw + gap)
        y0 = H - y_top - t.shape[0]
        out[y0:y0 + t.shape[0], x0:x0 + t.shape[1]] = t
    return out


def downscale(arr, f):
    h, w = arr.shape[:2]
    return arr[: h - h % f, : w - w % f].reshape(h // f, f, w // f, f, 4).mean(axis=(1, 3))


# ---------------------------------------------------------------- six-axis

VIEWS = (
    ("front", (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)),
    ("back", (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
    ("left", (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
    ("right", (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
    ("top", (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
    ("bottom", (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
)
SIX_PX = 512


def six_axis(piece):
    scene = reset_scene(SIX_PX, SIX_PX, 1.5)
    objs, _a, names, _h = import_glb(os.path.join(KIT_DIR, piece + ".glb"), piece)
    lo, hi = bounds(objs)
    ref = cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
    sub = world_points(objs)
    ref_pts = world_points([ref])
    allp = np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in VIEWS:
        inv = np.array(look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * MARGIN - 0.04
    log("%s six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (piece, sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, SIX_PX / scale))
    tiles = []
    for name, d, up in VIEWS:
        cam = ortho_camera(scene, look_rot(d, up), allp, scale)
        label = "%s six_axis %s" % (piece, name)
        b_sub = prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        path = os.path.join(OUT, "six_axis", "%s_%s.png" % (piece, name))
        tiles.append(over(render(scene, path), BACKDROP))
        bpy.data.objects.remove(cam)
    save_array(grid(tiles, 3), os.path.join(OUT, "six_axis", piece + ".png"))


# ---------------------------------------------------------------- thumbnails


def thumb_class(piece):
    w, d = act.ACTIVITIES[piece]["footprint"]
    return "%dx%d" % (w, d)


def thumbnail(piece):
    scene = reset_scene(THUMB * THUMB_SS, THUMB * THUMB_SS, 1.5 * THUMB_SS)
    objs, _a, names, _h = import_glb(os.path.join(KIT_DIR, piece + ".glb"), piece)
    direction = Vector((math.sin(CAM_AZIMUTH) * math.cos(CAM_ELEVATION),
                        -math.cos(CAM_AZIMUTH) * math.cos(CAM_ELEVATION), math.sin(CAM_ELEVATION)))
    rot = (-direction).to_track_quat("-Z", "Y")
    cls = thumb_class(piece)
    (w, d, h), (cx, cy, cz) = CLASSES[cls]
    inv = rot.to_matrix().inverted()
    xs, ys = [], []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                p = inv @ Vector((cx + sx * w, cy + sy * d, cz + sz * h))
                xs.append(p.x)
                ys.append(p.y)
    nominal = max(max(xs) - min(xs), max(ys) - min(ys)) / (1.0 - 2.0 * MARGIN - 0.04)
    pts = world_points(objs)
    loc = pts @ np.array(inv).T
    actual = max(loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min()) / (1.0 - 2.0 * MARGIN - 0.04)
    if actual > nominal:
        log("CLASS_OVERFLOW %s outgrows class %s: %.2f > %.2f" % (piece, cls, actual, nominal))
    cam = ortho_camera(scene, rot, pts, max(nominal, actual))
    prove_in_frame("%s thumb class=%s materials=%s" % (piece, cls, sorted(names)), scene, cam, pts, THUMB_MIN_SHARE)
    path = os.path.join(OUT, "thumbs", piece + ".png")
    arr = render(scene, path)
    small = downscale(arr, THUMB_SS)
    save_array(small, path)
    corner = float(small[-1, 0, 3])
    log("%s thumb corner_alpha=%.2f" % (piece, corner))
    if corner > 0.01:
        invalid("%s thumbnail background is not transparent" % piece)
    return small


def thumb_sheet(thumbs):
    big = [over(t, (0.16, 0.18, 0.22)) for t in thumbs]
    small = [downscale(t, 4) for t in thumbs]
    dark = [over(s, (0.16, 0.18, 0.22)) for s in small]
    light = [over(s, (0.86, 0.87, 0.84)) for s in small]
    top = grid(big, len(big))
    row_d = grid(dark, len(dark))
    row_l = grid(light, len(light))
    W = top.shape[1]
    pad = lambda a: np.concatenate([a, np.tile(np.array((0.08, 0.08, 0.09, 1.0), np.float32),  # noqa: E731
                                                       (a.shape[0], W - a.shape[1], 1))], axis=1)
    sheet = np.concatenate([pad(row_l), pad(row_d), top], axis=0)
    save_array(sheet, os.path.join(OUT, "thumbs", "contact_sheet.png"))


# ---------------------------------------------------------------- characters


def pose(arm, acts, clip, frame):
    want = [a for a in acts if base_name(a.name) == clip or base_name(a.name).startswith(clip + "_")]
    if not want:
        invalid("no action %s among %s" % (clip, [a.name for a in acts]))
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    ad.action = want[0]
    if hasattr(ad, "action_slot") and ad.action_slot is None and len(want[0].slots):
        ad.action_slot = want[0].slots[0]
    scene = bpy.context.scene
    scene.frame_set(int(frame))
    bpy.context.view_layer.update()
    return want[0]


def clip_range(acts, clip):
    a = [x for x in acts if base_name(x.name) == clip or base_name(x.name).startswith(clip + "_")][0]
    return int(round(a.frame_range[0])), int(round(a.frame_range[1]))


def add_character(who, xf):
    objs, acts, _names, holder = import_glb(os.path.join(PEOPLE, CHARS[who]), who, xf)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    if arm is None:
        invalid("%s has no armature" % who)
    # The glTF importer adds an unskinned Icosphere as the bone display shape; it is
    # not part of the character, so it goes.
    keep = []
    for o in objs:
        skinned = o.parent is arm or any(m.type == "ARMATURE" for m in getattr(o, "modifiers", []))
        if o.type == "MESH" and not skinned:
            bpy.data.objects.remove(o)
        else:
            keep.append(o)
    if not meshes(keep):
        invalid("%s has no skinned mesh" % who)
    return keep, acts, arm, holder


def mount_xf(objs, name):
    m = next((o for o in objs if base_name(o.name) == name), None)
    if m is None:
        invalid("mount %s not found in the written file" % name)
    return m.matrix_world.copy()


# ---------------------------------------------------------------- seated fit


def convex_parts(piece):
    """The piece rebuilt part by part with the builder (world = piece frame): each part
    a closed convex solid, as a list of (name, planes (n x 4), BVH, half thickness).
    The half thickness (half the part's smallest extent across a face normal) is the
    deepest a nearest-face containment depth can ever read in that part."""
    c = bpy.data.collections.new("FIT_" + piece)
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new("FIT_ROOT_" + piece, None)
    c.objects.link(root)
    act.PIECES[piece][0](root, c)
    bpy.context.view_layer.update()
    parts = []
    for o in c.objects:
        if o.type != "MESH":
            continue
        o.hide_render = True
        mw = o.matrix_world
        verts = [mw @ v.co for v in o.data.vertices]
        planes = []
        for poly in o.data.polygons:
            n = (mw.to_3x3() @ poly.normal).normalized()
            if n.length < 0.5:
                continue
            planes.append((n.x, n.y, n.z, n.dot(verts[poly.vertices[0]])))
        tris = [tuple(p.vertices) for p in o.data.polygons]
        planes = np.array(planes)
        vco = np.array([tuple(v) for v in verts])
        half = float((planes[:, 3] - (vco @ planes[:, :3].T)).max(axis=0).min()) / 2.0
        parts.append((o.name, planes, BVHTree.FromPolygons(verts, tris), half))
    return parts, c


def char_mesh(objs):
    """The posed character as one BVH plus its world vertices (n x 3) and polygons."""
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for o in meshes(objs):
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in me.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys), np.array([tuple(v) for v in verts]), polys


def soft(name):
    return "_Seat_" in name or "_BackCushion_" in name


def inside_depth(pts, planes):
    """Penetration depth of points inside a convex part: the distance to its nearest
    face, the shortest move that takes the point out."""
    return -(pts @ planes[:, :3].T - planes[:, 3]).max(axis=1)


def clip_to_part(poly, planes):
    """The part of a polygon (k x 3) inside a convex part (Sutherland-Hodgman)."""
    out = list(poly)
    for nx, ny, nz, d in planes:
        n = np.array((nx, ny, nz))
        src, out = out, []
        for i, a in enumerate(src):
            b = src[(i + 1) % len(src)]
            da, db = float(a @ n - d), float(b @ n - d)
            if da <= 0.0:
                out.append(a)
            if (da <= 0.0) != (db <= 0.0):
                out.append(a + (b - a) * (da / (da - db)))
        if not out:
            return []
    return out


def crossing_depth(poly, planes):
    """The deepest sampled point of a polygon's portion inside the part: the clipped
    corners, edge midpoints and centroid (the depth is concave over the part, so its
    maximum on a flat piece can lie inside it; the centroid covers the slicing case)."""
    clipped = clip_to_part(poly, planes)
    if not clipped:
        return 0.0
    c = np.array(clipped)
    mids = (c + np.roll(c, -1, axis=0)) / 2.0
    samples = np.concatenate([c, mids, c.mean(axis=0, keepdims=True)])
    return float(max(0.0, inside_depth(samples, planes).max()))


def same_geometry(objs, coll):
    """Max distance from each written vertex to the nearest rebuilt vertex, and back."""
    def tree(pts):
        t = KDTree(len(pts))
        for i, p in enumerate(pts):
            t.insert(p, i)
        t.balance()
        return t
    a = world_points(objs)
    b = world_points(list(coll.objects))
    ta, tb = tree(a), tree(b)
    ab = max(tb.find(p)[2] for p in a)
    ba = max(ta.find(p)[2] for p in b)
    return max(ab, ba), len(a), len(b)


def fit_check(piece, mount, who):
    """Every frame of sit_down, sit_idle and stand_up at one mount: vertex and triangle
    penetration per part, with a negative control for each. Returns ok."""
    reset_scene(64, 64)
    objs, _a, _n, _h = import_glb(os.path.join(KIT_DIR, piece + ".glb"), piece)
    for o in objs:
        o.hide_render = True
    xf = mount_xf(objs, mount)
    parts, fit_coll = convex_parts(piece)
    label = "%s %s %s" % (piece, mount, who)
    # The rebuilt parts must be the written piece: every written vertex on a rebuilt one
    # and back, within float32 export rounding.
    err, n_w, n_r = same_geometry(objs, fit_coll)
    log("FIT %s rebuilt_vs_written_vertices max_err=%.6f written=%d rebuilt=%d" % (label, err, n_w, n_r))
    if err > 2e-4:
        invalid("%s: the rebuilt fit parts differ from the written .glb by %.5f m" % (label, err))
    # Depth is the nearest-face penetration depth in every part. It can never exceed a
    # part's half thickness, so any part the body enters must be thicker than twice its
    # limit, or it is not certified. (An exit distance along a support direction was
    # tried for thin cushions; for a dress hem crossing the cushion nose it measured to
    # the cushion top, not the shortest way out. Every cushion is now 0.14 m or more.)
    cobjs, acts, arm, hold = add_character(who, xf)
    # Positive control: the top of the posed mesh drops from idle to sit_idle.
    pose(arm, acts, "idle", clip_range(acts, "idle")[0])
    stand_top = world_points(cobjs)[:, 2].max()
    s0, s1 = clip_range(acts, "sit_idle")
    pose(arm, acts, "sit_idle", (s0 + s1) // 2)
    sit_top = world_points(cobjs)[:, 2].max()
    log("FIT %s control stand_top=%.3f sit_top=%.3f drop=%.3f" % (label, stand_top, sit_top, stand_top - sit_top))
    if stand_top - sit_top < 0.25:
        invalid("%s: the sit pose did not engage (drop %.3f m)" % (label, stand_top - sit_top))
    # Skin height under the seat, binned by distance behind the root, over sit_idle.
    inv = np.array(xf.inverted())
    bins = {}
    for f in range(s0, s1 + 1):
        pose(arm, acts, "sit_idle", f)
        loc = world_points(cobjs) @ inv[:3, :3].T + inv[:3, 3]
        back = loc[:, 1]  # Blender local +y is behind the root (Godot -Z)
        zone = (np.abs(loc[:, 0]) < 0.20) & (loc[:, 2] < 0.75)
        for b in range(20, 60, 5):
            sel = zone & (back >= b / 100) & (back < (b + 5) / 100)
            if sel.any():
                bins[b] = min(bins.get(b, 9.0), float(loc[sel, 2].min()))
    log("FIT %s seat_profile (behind_root_m: min_skin_height_m, below SEAT_TOP %.2f) %s"
        % (label, act.SEAT_TOP,
           " ".join("%.2f-%.2f:%.3f(%+.3f)" % (b / 100, (b + 5) / 100, h, h - act.SEAT_TOP)
                    for b, h in sorted(bins.items()))))

    def frame_depths(cb, verts, polys):
        """part -> (depth, world point, kind) for the parts the body enters this frame:
        contained vertices, then the inside portions of crossing polygons."""
        out = {}
        for name, planes, bvh, _half in parts:
            s = verts @ planes[:, :3].T - planes[:, 3]
            inside = (s < 0).all(axis=1)
            if inside.any():
                d = inside_depth(verts[inside], planes)
                k = int(d.argmax())
                out[name] = (float(d[k]), verts[inside][k], "vertex")
            for ci in {pair[0] for pair in cb.overlap(bvh)}:
                poly = verts[list(polys[ci])]
                d = crossing_depth(poly, planes)
                if d > out.get(name, (0.0,))[0]:
                    out[name] = (d, poly.mean(axis=0), "triangle")
        return out

    worst = {}
    frames = 0
    for clip in ("sit_down", "sit_idle", "stand_up"):
        f0, f1 = clip_range(acts, clip)
        for f in range(f0, f1 + 1):
            pose(arm, acts, clip, f)
            frames += 1
            cb, verts, polys = char_mesh(cobjs)
            for name, (depth, p, kind) in frame_depths(cb, verts, polys).items():
                if depth > worst.get(name, (0.0,))[0]:
                    q = xf.inverted() @ Vector(p)
                    worst[name] = (depth, kind, clip, f, (q.x, q.z, -q.y))
    ok = True
    halves = {name: half for name, _p, _b, half in parts}
    for name, (depth, kind, clip, f, at) in sorted(worst.items(), key=lambda kv: -kv[1][0]):
        limit = FIT_SOFT_M if soft(name) else FIT_RIGID_M
        # A nearest-face depth can never exceed half the part's thickness: a part the
        # body enters that is that thin cannot be failed by depth, so it fails here.
        thin = halves[name] <= limit
        bad = depth > limit or thin
        ok = ok and not bad
        log("FIT %s part=%s depth=%.4f from=%s at %s:%d point_in_mount_frame=(%.3f, %.3f, %.3f) "
            "half_thickness=%.3f limit=%.3f %s"
            % (label, name, depth, kind, clip, f,
               at[0], at[1], at[2], halves[name], limit, "UNCERTIFIED_THIN" if thin else ("FAIL" if bad else "ok")))
    # Negative control 1: the same seated frame pushed 0.06 m down must fail the gate.
    pose(arm, acts, "sit_idle", (s0 + s1) // 2)
    hold.matrix_world = Matrix.Translation((0.0, 0.0, -0.06)) @ xf
    bpy.context.view_layer.update()
    cb, verts, polys = char_mesh(cobjs)
    sunk = frame_depths(cb, verts, polys)
    caught = any(d > (FIT_SOFT_M if soft(n) else FIT_RIGID_M) for n, (d, _p, _k) in sunk.items())
    log("FIT %s negative_control sunk_0.06 deepest=%s caught=%s"
        % (label, sorted(((n, round(d, 3), k) for n, (d, _p, k) in sunk.items()), key=lambda kv: -kv[1])[:3],
           caught))
    if not caught:
        invalid("%s: a seated body sunk 0.06 m passed the fit gate" % label)
    hold.matrix_world = xf
    bpy.context.view_layer.update()
    # Negative control 2: a triangle slicing through the thickest rigid part, its three
    # corners all outside, must read deeper than the rigid limit.
    name, planes, _bvh, half = max((p for p in parts if not soft(p[0])), key=lambda p: p[3])
    corners = np.array([tuple(v.co) for v in fit_coll.objects[name].data.vertices]) @ np.array(
        fit_coll.objects[name].matrix_world)[:3, :3].T + np.array(fit_coll.objects[name].matrix_world)[:3, 3]
    c = corners.mean(axis=0)
    reach = 3.0 * float(np.linalg.norm(corners - c, axis=1).max())
    tri = np.array([c + reach * np.array((math.cos(a), math.sin(a), 0.0)) for a in (0.0, 2.1, 4.2)])
    outside = not ((tri @ planes[:, :3].T - planes[:, 3]) < 0).all(axis=1).any()
    slice_depth = crossing_depth(tri, planes)
    log("FIT %s negative_control slicing_triangle part=%s corners_outside=%s depth=%.4f half_thickness=%.3f"
        % (label, name, outside, slice_depth, half))
    if not outside or slice_depth <= FIT_RIGID_M:
        invalid("%s: a triangle slicing %s with its corners outside passed the fit gate" % (label, name))
    log("FIT %s frames=%d parts=%d deepest=%s result=%s"
        % (label, frames, len(parts), max((v[0] for v in worst.values()), default=0.0), "ok" if ok else "FAIL"))
    return ok


# ---------------------------------------------------------------- sit plates


def sit_scene(piece, seats, res=(768, 512)):
    """The piece with characters seated at sit_idle: seats = [(mount, who)]."""
    scene = reset_scene(res[0], res[1], 1.5)
    objs, _a, _n, _h = import_glb(os.path.join(KIT_DIR, piece + ".glb"), piece)
    chars = []
    for mount, who in seats:
        cobjs, acts, arm, _hold = add_character(who, mount_xf(objs, mount))
        chars.append((cobjs, acts, arm))
    return scene, objs, chars


def set_frame_all(chars, clip, frac):
    for cobjs, acts, arm in chars:
        f0, f1 = clip_range(acts, clip)
        pose(arm, acts, clip, f0 + round((f1 - f0) * frac))


def sit_plates(piece):
    mounts = [m for m, (k, _p, _y) in act.ACTIVITIES[piece]["mounts"].items() if k == "sit_root"]
    combos = ([[(mounts[0], "male"), (mounts[1], "female")]] if len(mounts) == 2
              else [[(mounts[0], "male")], [(mounts[0], "female")]])
    tiles = []
    for n, seats in enumerate(combos):
        scene, objs, chars = sit_scene(piece, seats)
        set_frame_all(chars, "sit_idle", 0.5)
        allobjs = objs + [o for c in chars for o in c[0]]
        pts = world_points(allobjs)
        xs = [act.ACTIVITIES[piece]["mounts"][m][1][0] for m, _w in seats]
        # Front 3/4 must show every character; a side view only the one on its side
        # (the far seat is behind the near one), so each side gets its own view.
        views = [("front34", (-0.45, -0.85, 0.45), [True] * len(seats)),
                 ("side_right", (1.0, 0.0, 0.0), [x >= 0 for x in xs])]
        if any(x < 0 for x in xs):
            views.append(("side_left", (-1.0, 0.0, 0.0), [x < 0 for x in xs]))
        for view, d, must_see in views:
            rot = look_rot(d, (0, 0, 1))
            inv = np.array(rot.to_matrix().inverted())
            loc = pts @ inv.T
            ext = max((loc[:, 0].max() - loc[:, 0].min()) / 1.5, loc[:, 1].max() - loc[:, 1].min())
            cam = ortho_camera(scene, rot, pts, ext * 1.5 / (1.0 - 2.0 * MARGIN - 0.04))
            label = "%s sit %s %s" % (piece, "+".join("%s@%s" % (w, m) for m, w in seats), view)
            prove_in_frame(label, scene, cam, pts)
            for (cobjs, _acts, _arm), see, (m, w) in zip(chars, must_see, seats):
                if see:
                    visible_share("%s %s@%s" % (label, w, m), scene, cam, cobjs, need=0.10)
            path = os.path.join(OUT, "sit", "%s_%d_%s.png" % (piece, n, view))
            tiles.append(over(render(scene, path), BACKDROP))
            bpy.data.objects.remove(cam)
    return tiles


def strip(piece, mount, who, clip):
    scene, objs, chars = sit_scene(piece, [(mount, who)], res=(384, 512))
    cobjs, acts, arm = chars[0]
    # Seen from the mount's own side, so the rest of the piece does not hide the seat.
    side = -1.0 if act.ACTIVITIES[piece]["mounts"][mount][1][0] < 0 else 1.0
    rot = look_rot((side, 0.0, 0.0), (0, 0, 1))
    # One camera for all frames, fitted over the whole clip.
    f0, f1 = clip_range(acts, clip)
    frames = [f0 + round((f1 - f0) * k / 4) for k in range(5)]
    allp = []
    for f in frames:
        pose(arm, acts, clip, f)
        allp.append(world_points(objs + cobjs))
    allp = np.concatenate(allp)
    inv = np.array(rot.to_matrix().inverted())
    loc = allp @ inv.T
    ext = max((loc[:, 0].max() - loc[:, 0].min()) / 0.75, loc[:, 1].max() - loc[:, 1].min())
    cam = ortho_camera(scene, rot, allp, ext / (1.0 - 2.0 * MARGIN - 0.04))
    tiles = []
    for k, f in enumerate(frames):
        pose(arm, acts, clip, f)
        label = "%s strip %s %s %s frame=%d" % (piece, clip, who, mount, f)
        prove_in_frame(label, scene, cam, world_points(objs + cobjs))
        visible_share(label + " character", scene, cam, cobjs, need=0.10)
        path = os.path.join(OUT, "sit", "strip_%s_%s_%s_%d.png" % (piece, clip, who, k))
        tiles.append(over(render(scene, path), BACKDROP))
    save_array(grid(tiles, 5), os.path.join(OUT, "sit", "strip_%s_%s_%s.png" % (piece, clip, who)))


# ---------------------------------------------------------------- distance + context


def place_piece(piece, x, y, label=None):
    objs, _a, _n, holder = import_glb(os.path.join(KIT_DIR, piece + ".glb"), label or piece,
                                      Matrix.Translation((x, y, 0.0)))
    return objs, holder


def distance_shot():
    scene = reset_scene(1600, 900, 1.0)
    subjects = {}
    x = 0.0
    for piece in PIECES:
        w = act.ACTIVITIES[piece]["footprint"][0]
        objs, _h = place_piece(piece, x + w / 2.0, 0.0)
        subjects[piece] = objs
        x += w + 1.0
    man, _acts, _arm, _h = add_character("male", Matrix.Translation((x + 0.5, 0.0, 0.0)))
    subjects["male"] = man
    floor_plane((-2.0, -4.0), (x + 3.0, 4.0))
    centre = Vector(((x + 1.0) / 2.0, 0.0, 0.4))
    direction = Vector((math.sin(CAM_AZIMUTH) * math.cos(math.radians(45)),
                        -math.cos(CAM_AZIMUTH) * math.cos(math.radians(45)), math.sin(math.radians(45))))
    cam = persp_camera(scene, centre + direction * 25.0, centre, lens=35.0)
    log("distance camera_to_centre=%.1f m lens=35" % (cam.location - centre).length)
    for name, objs in subjects.items():
        prove_in_frame("distance %s" % name, scene, cam, world_points(objs))
        visible_share("distance %s" % name, scene, cam, objs)
    arr = render(scene, os.path.join(OUT, "distance_raw.png"))
    save_array(over(arr, BACKDROP), os.path.join(OUT, "distance.png"))


def place_car(xf_mount):
    objs, names, holder = import_fbx(SUV_FBX, "suv")
    lo, hi = bounds(objs)
    size = hi - lo
    log("context suv vendor_size=(%.3f, %.3f, %.3f) materials=%s" % (size.x, size.y, size.z, sorted(names)))
    # Long axis along the mount's +Z (the nose way); the vendor nose end is not known.
    m_loc, m_rot, _s = xf_mount.decompose()
    turn = 0.0 if size.y >= size.x else math.pi / 2
    holder.matrix_world = m_rot.to_matrix().to_4x4() @ Matrix.Rotation(turn, 4, "Z")
    bpy.context.view_layer.update()
    lo, hi = bounds(objs)
    holder.matrix_world = Matrix.Translation((m_loc.x - (lo.x + hi.x) / 2, m_loc.y - (lo.y + hi.y) / 2,
                                              m_loc.z - lo.z)) @ holder.matrix_world
    bpy.context.view_layer.update()
    return objs


def place_stanchions(cx, cy):
    """Metal_Pole_1A posts on the floor, post CENTRES 0.6 m outside the podium edge,
    chains between neighbours."""
    px, py = act.PODIUM_X + 0.6, act.PODIUM_Y + 0.6
    xs = [-px + 2 * px * k / 4 for k in range(5)]
    ring = [(x, -py) for x in xs] + [(px, 0.0)] + [(x, py) for x in reversed(xs)] + [(-px, 0.0)]
    objs = []
    probe, _n, ph = import_fbx(POLE_FBX, "pole_probe", POLE_RGB)
    plo, phi = bounds(probe)
    log("context pole vendor_size=(%.3f, %.3f, %.3f)" % tuple(phi - plo))
    for o in probe + [ph]:
        bpy.data.objects.remove(o)
    for i, (x, y) in enumerate(ring):
        p, _n, h = import_fbx(POLE_FBX, "pole_%d" % i, POLE_RGB)
        lo, hi = bounds(p)
        h.matrix_world = Matrix.Translation((cx + x - (lo.x + hi.x) / 2, cy + y - (lo.y + hi.y) / 2, -lo.z))
        objs += p
    bpy.context.view_layer.update()
    ch, _n, chh = import_fbx(CHAIN_FBX, "chain_probe", CHAIN_RGB)
    clo, chi = bounds(ch)
    csize = chi - clo
    log("context chain vendor_size=(%.3f, %.3f, %.3f) z=[%.3f, %.3f]" % (csize.x, csize.y, csize.z, clo.z, chi.z))
    long_x = csize.x >= csize.y
    length = csize.x if long_x else csize.y
    for o in ch + [chh]:
        bpy.data.objects.remove(o)
    for i in range(len(ring)):
        (x0, y0), (x1, y1) = ring[i], ring[(i + 1) % len(ring)]
        c, _n, h = import_fbx(CHAIN_FBX, "chain_%d" % i, CHAIN_RGB)
        lo, hi = bounds(c)
        mid = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0.0))
        span = math.hypot(x1 - x0, y1 - y0)
        ang = math.atan2(y1 - y0, x1 - x0) - (0.0 if long_x else math.pi / 2)
        h.matrix_world = (Matrix.Translation((cx + (x0 + x1) / 2, cy + (y0 + y1) / 2, 0.0))
                          @ Matrix.Rotation(ang, 4, "Z")
                          @ Matrix.Diagonal(((span / length) if long_x else 1.0, 1.0 if long_x else span / length,
                                             1.0, 1.0))
                          @ Matrix.Translation(-mid))
        objs += c
    bpy.context.view_layer.update()
    return objs, ring


PODIUM_AT = (9.5, 5.5)


def context_shot():
    scene = reset_scene(1920, 1080, 1.2)
    W, D = 14, 10
    # Linked copies of the written floor tile, one per cell; the imported original goes.
    tile, _a, _n, _h = import_glb(os.path.join(KIT_DIR, "floor_tile.glb"), "floor")
    bodies = [(o.data, o.matrix_world.copy()) for o in meshes(tile)]
    for o in tile:
        bpy.data.objects.remove(o)
    for j in range(D):
        for i in range(W):
            for data, mw in bodies:
                dup = bpy.data.objects.new("Floor_%d_%d" % (i, j), data)
                dup.matrix_world = Matrix.Translation((i + 0.5, j + 0.5, 0.0)) @ mw
                scene.collection.objects.link(dup)
    for i in range(W):
        place_piece("wall", i + 0.5, D, "wall_%d" % i)
    layout = {
        "prize_podium": (PODIUM_AT[0], PODIUM_AT[1]),
        "play_slide": (1.0, 8.5),
        "play_blocks": (3.0, 8.0),
        "lounge_sofa": (1.0, 3.5),
        "lounge_armchair": (2.5, 3.5),
        "work_desk": (6.0, 9.0),
        "seat_row": (5.5, 2.5),
        "checkin_desk": (11.0, 1.5),
    }
    subjects = {}
    for piece, (x, y) in layout.items():
        subjects[piece], _h = place_piece(piece, x, y)
    sofa_xf = mount_xf(subjects["lounge_sofa"], "Mount_SitRoot_L")
    # The female sits in the armchair, facing the camera: at the wall desk it sees only
    # her back through the chair. The desk seating is on the sit/ plates and strips.
    chair_xf = mount_xf(subjects["lounge_armchair"], "Mount_SitRoot")
    car_xf = mount_xf(subjects["prize_podium"], "Mount_Car")
    seated_m, acts_m, arm_m, _h1 = add_character("male", sofa_xf)
    seated_f, acts_f, arm_f, _h2 = add_character("female", chair_xf)
    pose(arm_m, acts_m, "sit_idle", sum(clip_range(acts_m, "sit_idle")) // 2)
    pose(arm_f, acts_f, "sit_idle", sum(clip_range(acts_f, "sit_idle")) // 2)
    # Standing at the rope line, looking at the car (characters face -Y at identity).
    spectator, _a3, _arm3, _h3 = add_character(
        "male", Matrix.Translation((9.0, PODIUM_AT[1] - act.PODIUM_Y - 0.6 - 0.55, 0.0))
        @ Matrix.Rotation(math.pi, 4, "Z"))
    kid_watch, _a4, _arm4, _h4 = add_character("female", Matrix.Translation((4.6, 6.4, 0.0)))
    subjects.update({"seated_male": seated_m, "seated_female": seated_f, "spectator": spectator,
                     "standing_female": kid_watch})
    car = place_car(car_xf)
    subjects["suv"] = car
    clo, chi = bounds(car)
    m = car_xf.translation
    log("context suv placed min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % (*clo, *chi))
    deck_x = act.PODIUM_X - 0.07
    deck_y = act.PODIUM_Y - 0.07
    log("context suv deck_margins x_lo=%.3f x_hi=%.3f y_lo=%.3f y_hi=%.3f (carpet edge to car bbox)"
        % ((clo.x - (m.x - deck_x)), ((m.x + deck_x) - chi.x), (clo.y - (m.y - deck_y)), ((m.y + deck_y) - chi.y)))
    posts, _ring = place_stanchions(*PODIUM_AT)
    subjects["stanchions"] = posts
    target = Vector((7.0, 5.0, 0.6))
    direction = Vector((math.sin(math.radians(-20)) * math.cos(math.radians(55)),
                        -math.cos(math.radians(-20)) * math.cos(math.radians(55)), math.sin(math.radians(55))))
    cam = persp_camera(scene, target + direction * 19.0, target, lens=28.0)
    for name, objs in subjects.items():
        prove_in_frame("context %s" % name, scene, cam, world_points(objs))
        visible_share("context %s" % name, scene, cam, objs, need=0.10)
    arr = render(scene, os.path.join(OUT, "context_raw.png"))
    save_array(over(arr, BACKDROP), os.path.join(OUT, "context.png"))


# ---------------------------------------------------------------- main


def main():
    act.register()
    for sub in ("six_axis", "thumbs", "sit"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stages = only or ["fit", "six", "thumbs", "sit", "distance", "context"]
    fit_ok = True
    if "fit" in stages:
        for piece in SITS:
            for mount, (kind, _p, _y) in act.ACTIVITIES[piece]["mounts"].items():
                if kind != "sit_root":
                    continue
                for who in CHARS:
                    fit_ok = fit_check(piece, mount, who) and fit_ok
    if "six" in stages:
        for piece in PIECES:
            six_axis(piece)
    if "thumbs" in stages:
        thumb_sheet([thumbnail(p) for p in PIECES])
    if "sit" in stages:
        for piece in SITS:
            tiles = sit_plates(piece)
            save_array(grid(tiles, 3 if len(tiles) % 3 == 0 else 2), os.path.join(OUT, "sit", piece + ".png"))
        strip("lounge_sofa", "Mount_SitRoot_L", "male", "sit_down")
        strip("lounge_sofa", "Mount_SitRoot_L", "male", "stand_up")
        strip("work_desk", "Mount_SitRoot_L", "female", "sit_down")
        strip("work_desk", "Mount_SitRoot_L", "female", "stand_up")
    if "distance" in stages:
        distance_shot()
    if "context" in stages:
        context_shot()
    log("PLATES done stages=%s fit_ok=%s" % (stages, fit_ok))
    if not fit_ok:
        print("FIT_FAIL a seated pose goes into the furniture beyond its limit", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
