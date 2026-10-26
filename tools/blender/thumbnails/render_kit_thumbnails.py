"""Render one square build-menu thumbnail per placeable build item.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\thumbnails\\render_kit_thumbnails.py' \
    [-- --force] [-- item ...]

Each item is drawn from its interior kit .glb in game/assets/interior/ (the pieces
game/build/view/interior_kit.gd uses), framed by one orthographic 3/4 camera at a
fixed direction, at one scale per footprint class, on a transparent background.
Writes 256x256 PNGs to game/assets/ui/thumbnails/<item>.png and a manifest of the
source .glb hashes there; an item re-renders only when a source hash (or STYLE)
changes, or with --force. The contact sheet goes to
tools/blender/out/thumbnails/contact_sheet.png (gitignored).

Toon look: the glTF carries no images, so every material is rebound by name to its
atlas in game/assets/textures/. Surfaces are shaded with an emission-only node tree
that copies game/shaders/toon.gdshader: albedo times (the vendor ramp looked up at
the half-Lambert term of the game's sun direction, plus a flat ambient). No specular,
no PBR. Lights are unshaded, glass is the atlas gradient at the game's 0.29 alpha.
The outline is Freestyle at a fixed pixel width in the game's outline colour.

Every thumbnail proves its subject is in frame (all vertices projected inside a
margin) and big enough before it is saved; otherwise PROBE_INVALID and exit 1.
"""

import hashlib
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "game", "assets", "interior")
TEXTURES = os.path.join(REPO, "game", "assets", "textures")
OUT_DIR = os.path.join(REPO, "game", "assets", "ui", "thumbnails")
MANIFEST = os.path.join(OUT_DIR, "manifest.json")
SHEET_DIR = os.path.join(REPO, "tools", "blender", "out", "thumbnails")
SHEET = os.path.join(SHEET_DIR, "contact_sheet.png")

# Bump when the look or framing changes, so every thumbnail re-renders.
STYLE = 3
SIZE = 256
SUPERSAMPLE = 2  # render at SIZE * SUPERSAMPLE, scale down: smoother outline
MARGIN = 0.05  # every vertex lands this far inside the frame (fraction)
MIN_SHARE = 0.45  # the subject spans at least this much of the frame's width or height

# Camera: front-left 3/4, looking down 30 degrees. Godot +Z (the front) is Blender -Y.
CAM_AZIMUTH = math.radians(-35.0)  # from the front (-Y), towards -X
CAM_ELEVATION = math.radians(30.0)
# Toward the light, from the game's Sun (main.tscn) converted to Blender axes.
SUN = Vector((0.354, -0.612, 0.707)).normalized()
AMBIENT = 0.24  # flat stand-in for the game sky ambient
LIGHT_GAIN = 0.76  # sun share; lit faces land at albedo x 1.0 with no tonemapper
OUTLINE_RGB = (0.1, 0.1, 0.12)  # toon_outline outline_color
OUTLINE_PX = 1.5  # toon_outline outline_px, at the final size

ATLAS_PNG = {
    "TP_Atlas_1A_D": "tp_atlas_1a_d.png",
    "TP_Atlas_Lights_1A_D": "tp_atlas_lights_1a_d.png",
    "TP_Glass_1A_D": "tp_glass_gradient_1a_d.png",
}
RAMP_PNG = "tp_toon_ramp_1d_d.png"
GLASS_ALPHA = 0.29  # tp_glass.tres albedo alpha
GLASS_TINT = 0.85

# Footprint class -> nominal box (width X, depth Y, height Z) in metres, with the
# box centre's offset from the piece origin. One class, one camera scale.
CLASSES = {
    "tile": ((1.0, 1.0, 0.25), (0.0, 0.0, 0.0)),
    "edge": ((1.2, 0.2, 2.6), (0.0, 0.0, 1.3)),
    "door_1x1": ((1.1, 1.1, 2.5), (0.0, 0.0, 1.25)),
    "2x1": ((2.0, 1.0, 1.6), (0.0, 0.0, 0.8)),
    "1x2": ((1.0, 2.0, 2.3), (0.0, 0.0, 1.15)),
    "3x1": ((3.0, 1.0, 1.0), (0.0, 0.0, 0.5)),
}

# Catalog colours (build_catalog.gd), sRGB.
ENTRANCE_RGB = (0.35, 0.7, 0.4)
EXIT_RGB = (0.3, 0.55, 0.85)
REMOVE_RGB = (0.86, 0.18, 0.16)

# item -> (footprint class, main piece, extras). Extras are glyphs this script
# builds. Entrance and exit draw wall_door on their back edge (Godot -Z 0.5, Blender
# +Y 0.5), as InteriorKit.OBJECT_OFFSETS does, over a floor tile.
ITEMS = {
    "floor": ("tile", ["floor_tile"], []),
    "wall": ("edge", ["wall"], []),
    "glass": ("edge", ["wall_glass"], []),
    "door": ("edge", ["wall_door"], []),
    "desk": ("2x1", ["checkin_desk"], []),
    "scanner": ("1x2", ["security_scanner"], []),
    "seats": ("3x1", ["seat_row"], []),
    "entrance": ("door_1x1", ["floor_tile", ("wall_door", (0.0, 0.5, 0.0))], ["arrow_in"]),
    "exit": ("door_1x1", ["floor_tile", ("wall_door", (0.0, 0.5, 0.0))], ["arrow_out"]),
    "remove": ("tile", ["floor_tile"], ["cross"]),
}
ORDER = list(ITEMS)


def log(msg):
    print("THUMB " + msg, flush=True)


def invalid(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def piece_name(entry):
    return entry if isinstance(entry, str) else entry[0]


def source_hashes(item):
    names = sorted({piece_name(e) for e in ITEMS[item][1]})
    return {n + ".glb": sha256(os.path.join(KIT_DIR, n + ".glb")) for n in names}


# ---------------------------------------------------------------- materials

_images = {}


def image(png, non_color=False):
    if png not in _images:
        img = bpy.data.images.load(os.path.join(TEXTURES, png), check_existing=True)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        _images[png] = img
    return _images[png]


def toon_material(name, rgb=None):
    """Emission-only copy of toon.gdshader: albedo * (ramp(half_lambert) + ambient)."""
    m = bpy.data.materials.new("THUMB_" + name)
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
        tex.image = image(ATLAS_PNG[name])
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
    ramp.image = image(RAMP_PNG, non_color=True)
    ramp.interpolation = "Closest"
    ramp.extension = "EXTEND"
    nt.links.new(uv.outputs["Vector"], ramp.inputs["Vector"])
    # Colour maths as vector maths: the Mix node shares socket names across types.
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
    return m


def unshaded_material(name):
    m = bpy.data.materials.new("THUMB_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image(ATLAS_PNG[name])
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return m


def glass_material(name):
    m = bpy.data.materials.new("THUMB_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = GLASS_TINT
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image(ATLAS_PNG[name])
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = GLASS_ALPHA
    nt.links.new(clear.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emit.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


_materials = {}


def kit_material(name):
    if name not in _materials:
        if name == "TP_Atlas_1A_D":
            _materials[name] = toon_material(name)
        elif name == "TP_Atlas_Lights_1A_D":
            _materials[name] = unshaded_material(name)
        elif name == "TP_Glass_1A_D":
            _materials[name] = glass_material(name)
        else:
            invalid("unmapped kit material '%s'" % name)
    return _materials[name]


# ---------------------------------------------------------------- scene


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    _images.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.cycles.transparent_max_bounces = 8
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE * SUPERSAMPLE
    scene.render.resolution_y = SIZE * SUPERSAMPLE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("THUMB_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    if not hasattr(scene.render, "use_freestyle"):
        invalid("this Blender has no Freestyle; the outline cannot be drawn")
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = OUTLINE_PX * SUPERSAMPLE
    fs = scene.view_layers[0].freestyle_settings
    lineset = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("THUMB_Lines")
    lineset.select_by_visibility = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = True
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("THUMB_Outline")
    lineset.linestyle.color = OUTLINE_RGB
    lineset.linestyle.thickness = OUTLINE_PX * SUPERSAMPLE
    return scene


def import_piece(name, offset):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(KIT_DIR, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for r in roots:
        r.location = Vector(offset) + r.location
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        invalid("%s.glb imported no meshes" % name)
    names = set()
    for o in meshes:
        for slot in o.material_slots:
            if slot.material is None:
                invalid("%s: %s has an empty material slot" % (name, o.name))
            names.add(slot.material.name.split(".")[0])
            slot.material = kit_material(slot.material.name.split(".")[0])
    return meshes, names


def glyph_mesh(name, polys, rgb, z0, z1):
    """Prism meshes from 2D outlines (Blender XY), between heights z0 and z1."""
    verts, faces = [], []
    for poly in polys:
        n = len(poly)
        base = len(verts)
        verts += [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
        faces.append(tuple(base + i for i in reversed(range(n))))
        faces.append(tuple(base + n + i for i in range(n)))
        for i in range(n):
            j = (i + 1) % n
            faces.append((base + i, base + j, base + n + j, base + n + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(toon_material(name, rgb))
    return obj


def arrow(direction):
    """Flat arrow on the tile, pointing Blender -Y (into the hall) or +Y (out)."""
    s = 1.0 if direction == "out" else -1.0
    shaft = [(-0.16, -0.46 * s), (0.16, -0.46 * s), (0.16, 0.02 * s), (-0.16, 0.02 * s)]
    head = [(-0.44, 0.0), (0.44, 0.0), (0.0, 0.46 * s)]
    if s < 0:
        shaft = [p for p in reversed(shaft)]
        head = [p for p in reversed(head)]
    return [shaft, head]


def cross():
    """An X that reads as an X on screen, not a plus: each bar sits at the plan angle
    that the camera's tilt foreshortens to 45 degrees off the screen's horizontal."""
    w, r = 0.09, 0.4
    view = math.degrees(math.atan(1.0 / math.sin(CAM_ELEVATION)))
    right = math.degrees(CAM_AZIMUTH)  # the camera's right axis in plan
    bars = []
    for ang in (right + view, right - view):
        a = math.radians(ang)
        c, s = math.cos(a), math.sin(a)
        rect = [(-r, -w), (r, -w), (r, w), (-r, w)]
        bars.append([(x * c - y * s, x * s + y * c) for x, y in rect])
    return bars


def add_glyphs(extras):
    objs = []
    for g in extras:
        if g == "arrow_in":
            objs.append(glyph_mesh("Glyph_Arrow_In", arrow("in"), ENTRANCE_RGB, 0.0, 0.07))
        elif g == "arrow_out":
            objs.append(glyph_mesh("Glyph_Arrow_Out", arrow("out"), EXIT_RGB, 0.0, 0.07))
        elif g == "cross":
            objs.append(glyph_mesh("Glyph_Cross", cross(), REMOVE_RGB, 0.0, 0.08))
    return objs


def class_scale(cls, cam_rot):
    """Ortho scale fitting the class's nominal box in the frame with the margin."""
    (w, d, h), (cx, cy, cz) = CLASSES[cls]
    inv = cam_rot.to_matrix().inverted()
    xs, ys = [], []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                p = inv @ Vector((cx + sx * w, cy + sy * d, cz + sz * h))
                xs.append(p.x)
                ys.append(p.y)
    extent = max(max(xs) - min(xs), max(ys) - min(ys))
    return extent / (1.0 - 2.0 * MARGIN - 0.04)


def setup_camera(scene, cls, objs):
    cam_data = bpy.data.cameras.new("THUMB_Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("THUMB_Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    direction = Vector(
        (
            math.sin(CAM_AZIMUTH) * math.cos(CAM_ELEVATION),
            -math.cos(CAM_AZIMUTH) * math.cos(CAM_ELEVATION),
            math.sin(CAM_ELEVATION),
        )
    )
    rot = (-direction).to_track_quat("-Z", "Y")
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rot
    # Centre on the subject's own bounds in camera space. The scale is the class's;
    # a subject bigger than its class box widens it and says so.
    bpy.context.view_layer.update()
    inv = rot.to_matrix().inverted()
    pts = [inv @ (o.matrix_world @ v.co) for o in objs for v in o.data.vertices]
    span = max(
        max(p.x for p in pts) - min(p.x for p in pts),
        max(p.y for p in pts) - min(p.y for p in pts),
    )
    nominal = class_scale(cls, rot)
    actual = span / (1.0 - 2.0 * MARGIN - 0.04)
    if actual > nominal:
        log("CLASS_OVERFLOW %s outgrows its class box: %.2f > %.2f" % (cls, actual, nominal))
    cam_data.ortho_scale = max(nominal, actual)
    mid = Vector(
        (
            (min(p.x for p in pts) + max(p.x for p in pts)) / 2,
            (min(p.y for p in pts) + max(p.y for p in pts)) / 2,
            max(p.z for p in pts) + 20.0,
        )
    )
    cam.location = rot.to_matrix() @ mid
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    bpy.context.view_layer.update()
    return cam


def prove_in_frame(item, scene, cam, objs):
    xs, ys = [], []
    for o in objs:
        for v in o.data.vertices:
            p = world_to_camera_view(scene, cam, o.matrix_world @ v.co)
            xs.append(p.x)
            ys.append(p.y)
            if p.z <= cam.data.clip_start:
                invalid("%s: vertex behind the camera" % item)
    box = (min(xs), min(ys), max(xs), max(ys))
    share = max(box[2] - box[0], box[3] - box[1])
    log(
        "%s in_frame u=[%.3f,%.3f] v=[%.3f,%.3f] share=%.2f margin=%.2f ortho=%.2f"
        % (item, box[0], box[2], box[1], box[3], share, MARGIN, cam.data.ortho_scale)
    )
    if box[0] < MARGIN or box[1] < MARGIN or box[2] > 1 - MARGIN or box[3] > 1 - MARGIN:
        invalid("%s: subject leaves the frame margin" % item)
    if share < MIN_SHARE:
        invalid("%s: subject spans only %.2f of the frame" % (item, share))
    # Occlusion: the scene holds only the subject, so nothing can stand in front.
    others = [o for o in scene.objects if o.type == "MESH" and o not in objs]
    if others:
        invalid("%s: stray meshes in the scene: %s" % (item, [o.name for o in others]))


def render_item(item, path):
    scene = reset_scene()
    cls, pieces, extras = ITEMS[item]
    objs, mats = [], set()
    for entry in pieces:
        name = piece_name(entry)
        offset = (0.0, 0.0, 0.0) if isinstance(entry, str) else entry[1]
        meshes, names = import_piece(name, offset)
        objs += meshes
        mats |= names
    objs += add_glyphs(extras)
    images = sorted(i.name for i in bpy.data.images if i.users)
    log(
        "%s class=%s pieces=%s meshes=%d kit_materials=%s images=%s"
        % (item, cls, [piece_name(e) for e in pieces], len(objs), sorted(mats), images)
    )
    if not any(n in ATLAS_PNG for n in mats):
        invalid("%s: no atlas material bound" % item)
    cam = setup_camera(scene, cls, objs)
    prove_in_frame(item, scene, cam, objs)
    tmp = path + ".full.png"
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    img.scale(SIZE, SIZE)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    os.remove(tmp)
    check = bpy.data.images.load(path)
    w, h = check.size
    px = check.pixels[:]
    opaque = sum(1 for i in range(3, len(px), 4) if px[i] > 0.5)
    corner = px[3]
    bpy.data.images.remove(check)
    log("%s wrote %s size=%dx%d opaque_px=%d corner_alpha=%.2f" % (item, path, w, h, opaque, corner))
    if (w, h) != (SIZE, SIZE) or opaque == 0 or corner > 0.01:
        invalid("%s: written PNG is wrong (size, empty, or opaque background)" % item)


# ---------------------------------------------------------------- contact sheet


def contact_sheet(items):
    """Row 1-2: the thumbnails at 256 on a dark card. Row 3: each at 64 px on dark,
    then on light, to judge legibility at card size."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cols, gap, small = 5, 8, 64
    rows = math.ceil(len(items) / cols)
    W = cols * SIZE + (cols + 1) * gap
    small_h = 2 * small + 3 * gap
    H = rows * (SIZE + gap) + gap + small_h
    dark, light = (0.16, 0.18, 0.22), (0.86, 0.87, 0.84)
    sheet = [0.0] * (W * H * 4)
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 4
            sheet[i : i + 4] = [0.08, 0.08, 0.09, 1.0]

    def blit(pixels, w, h, x0, y0, bg):
        # y0 is from the top; Blender pixel rows run bottom-up.
        for yy in range(h):
            dst_row = H - 1 - (y0 + yy)
            src_row = h - 1 - yy
            for xx in range(w):
                s = (src_row * w + xx) * 4
                a = pixels[s + 3]
                d = (dst_row * W + x0 + xx) * 4
                for c in range(3):
                    sheet[d + c] = pixels[s + c] * a + bg[c] * (1 - a)
                sheet[d + 3] = 1.0

    for n, item in enumerate(items):
        img = bpy.data.images.load(os.path.join(OUT_DIR, item + ".png"))
        img.colorspace_settings.name = "sRGB"
        px = img.pixels[:]
        r, c = divmod(n, cols)
        blit(px, SIZE, SIZE, gap + c * (SIZE + gap), gap + r * (SIZE + gap), dark)
        img.scale(small, small)
        spx = img.pixels[:]
        y_small = rows * (SIZE + gap) + gap
        blit(spx, small, small, gap + n * (small + gap), y_small, dark)
        blit(spx, small, small, gap + n * (small + gap), y_small + small + gap, light)
        bpy.data.images.remove(img)
    out = bpy.data.images.new("contact_sheet", W, H, alpha=True)
    out.pixels[:] = sheet
    out.filepath_raw = SHEET
    out.file_format = "PNG"
    out.save()
    log("contact sheet %s size=%dx%d order=%s" % (SHEET, W, H, items))


# ---------------------------------------------------------------- main


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    force = "--force" in argv
    wanted = [a for a in argv if not a.startswith("--")] or ORDER
    unknown = [a for a in wanted if a not in ITEMS]
    if unknown:
        invalid("unknown items %s; known: %s" % (unknown, ORDER))
    ramp = bpy.data.images.load(os.path.join(TEXTURES, RAMP_PNG))
    rpx = ramp.pixels[:]
    steps = sorted({round(rpx[i], 3) for i in range(0, len(rpx), 4)})
    log("ramp %s %dx%d red steps=%s" % (RAMP_PNG, ramp.size[0], ramp.size[1], steps))
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(SHEET_DIR, exist_ok=True)
    manifest = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    entries = manifest.get("items", {})
    rendered, skipped = [], []
    for item in wanted:
        hashes = source_hashes(item)
        path = os.path.join(OUT_DIR, item + ".png")
        prev = entries.get(item, {})
        fresh = (
            prev.get("sources") == hashes
            and prev.get("style") == STYLE
            and os.path.exists(path)
        )
        if fresh and not force:
            skipped.append(item)
            continue
        render_item(item, path)
        entries[item] = {
            "png": item + ".png",
            "class": ITEMS[item][0],
            "style": STYLE,
            "sources": hashes,
        }
        rendered.append(item)
    manifest = {
        "generator": "tools/blender/thumbnails/render_kit_thumbnails.py",
        "style": STYLE,
        "size": SIZE,
        "items": {k: entries[k] for k in ORDER if k in entries},
    }
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
    log("rendered=%s skipped=%s" % (rendered, skipped))
    have = [k for k in ORDER if os.path.exists(os.path.join(OUT_DIR, k + ".png"))]
    contact_sheet(have)
    log("THUMBS_OK %d thumbnails" % len(have))


main()
