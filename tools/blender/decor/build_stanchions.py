"""Build Toon-style indoor airport retractable-belt stanchions and export to game/assets/decor/.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\.claude\\worktrees\\indoor-stanchions\\tools\\blender\\decor\\build_stanchions.py' \
    [-- --plates <out_dir>]

Exports:
- game/assets/decor/tc_metal_pole_1a.glb (1x1 single retractable-belt stanchion, 1.00 m tall)
- game/assets/decor/tc_metal_pole_chain_1a.glb (1x3 taut dark-navy retractable belt with
  silver clip heads spanning 2.0 m between InteriorKit.OBJECT_POSTS at (0,0,0) and (0,0,2))

Conventions:
- Blender X = Godot X, Blender -Y = Godot +Z, Blender Z = Godot Y (up).
- Origin at center bottom (y = 0.0 in Godot / z = 0.0 in Blender).
- Every face is UV-mapped to a measured swatch of TP_Atlas_1A_D (tp_atlas_1a_d.png);
  the GLB carries 0 embedded images and one material named "TP_Atlas_1A_D" so
  game/assets/toon_post_import.gd binds tp_atlas_toon.tres and bakes CUSTOM0 normals.
- Verifies every written .glb by re-reading the GLB JSON and re-importing into a blank
  scene: bounds, material/image counts, UV swatches, zero-area and coplanar triangle checks,
  and cassette-to-belt attachment geometry.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEXTURES = os.path.join(REPO, "game", "assets", "textures")
OUT_DIR = os.path.join(REPO, "game", "assets", "decor")
BLEND_OUT = os.path.join(REPO, "tools", "blender", "out", "indoor-stanchions", "blender", "stanchions.blend")
DEFAULT_PLATES_DIR = os.path.join(REPO, "tools", "blender", "out", "indoor-stanchions", "blender")
POST_IMPORT = "res://assets/toon_post_import.gd"

MAT_NAME = "TP_Atlas_1A_D"
ATLAS_PNG = "tp_atlas_1a_d.png"
RAMP_PNG = "tp_toon_ramp_1d_d.png"
ATLAS_COLS = 32
ATLAS_ROWS = 16
EMPTY_RGB = {(0, 0, 0), (51, 51, 51)}

# Swatches in TP_Atlas_1A_D (col, row, frac_top, vertical_span).
# Verified against game/assets/textures/tp_atlas_1a_d.png:
# - chrome: brushed light silver (col 12 row 11, same swatch as build_interior_kit "metal")
# - steel: medium steel silver for clip heads & cassette bezels (col 14 row 11)
# - slate: cool dark slate/charcoal for weighted base & cassette housing (col 12 row 15)
# - rubber: dark charcoal rubber rim on base bottom (col 3 row 15)
# - navy: dark navy fabric for retractable belt & cassette belt-slot band (col 20 row 15)
PALETTE = {
    "chrome": (12, 11, 0.18, 0.14),
    "steel": (14, 11, 0.36, 0.14),
    "slate": (12, 15, 0.32, 0.14),
    "rubber": (3, 15, 0.46, 0.10),
    "navy": (20, 15, 0.22, 0.14),
}

# Stanchion dimensions (metres).
SEGS = 16
POLE_HEIGHT = 1.000
BASE_RADIUS = 0.162
POLE_RADIUS = 0.032
CASSETTE_RADIUS = 0.0445
BAND_RADIUS = 0.0455
BELT_Z_LO = 0.840
BELT_Z_HI = 0.900
BELT_HALF_T = 0.0085
POST_SPAN = 2.000

# Lighting / toon preview constants matching render_kit_thumbnails.py.
SUN = Vector((0.354, -0.612, 0.707)).normalized()
SKY_UP = (0.1446, 0.1929, 0.2770)
SKY_SIDE = (0.1175, 0.1342, 0.1666)
SKY_DOWN = (0.0337, 0.0249, 0.0166)
AMBIENT_SCALE = 2.7
FILMIC_WHITE = 1.2
OUTLINE_RGB = (0.1, 0.1, 0.12)

_images = {}
_materials = {}
FAILS = []


def log(msg):
    print("STANCHION " + msg, flush=True)


def fail(msg):
    FAILS.append(msg)
    log("FAIL " + msg)


def atlas_info():
    if "atlas" not in _images:
        img = bpy.data.images.load(os.path.join(TEXTURES, ATLAS_PNG), check_existing=True)
        _images["atlas"] = (img, img.size[0], img.size[1], img.pixels[:])
    return _images["atlas"]


def sample_rgb(u, v):
    _img, w, h, px = atlas_info()
    x = min(w - 1, max(0, int(u * w)))
    y = min(h - 1, max(0, int(v * h)))
    i = (y * w + x) * 4
    return tuple(round(px[i + k] * 255) for k in range(3))


def swatch_uv(pal, t):
    col, row, frac, span = PALETTE[pal]
    f = frac + span * t
    return (col + 0.5) / ATLAS_COLS, 1.0 - (row + f) / ATLAS_ROWS


def get_material():
    if MAT_NAME not in _materials:
        m = bpy.data.materials.new(MAT_NAME)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = atlas_info()[0]
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 1.0
        _materials[MAT_NAME] = m
    return _materials[MAT_NAME]


def _finish_mesh(name, bm, pal, parent, coll):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
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
    me.materials.append(get_material())
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = parent
    return ob


def _lathe_solid(name, profile, pal, parent, coll, segs=SEGS):
    """Build a watertight solid of revolution from (radius, z) rings bottom-to-top.

    Outer rings have r > 0; bottom and top close with manifold triangle fans
    so there are zero internal horizontal caps and zero coplanar faces.
    """
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for s in range(segs):
            ang = (2.0 * math.pi * s) / segs
            ring.append(bm.verts.new((r * math.cos(ang), r * math.sin(ang), z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(segs):
            ns = (s + 1) % segs
            bm.faces.new((r0[s], r0[ns], r1[ns], r1[s]))
    # Bottom cap
    bot_c = bm.verts.new((0.0, 0.0, profile[0][1]))
    for s in range(segs):
        ns = (s + 1) % segs
        bm.faces.new((bot_c, rings[0][ns], rings[0][s]))
    # Top cap
    top_c = bm.verts.new((0.0, 0.0, profile[-1][1]))
    for s in range(segs):
        ns = (s + 1) % segs
        bm.faces.new((top_c, rings[-1][s], rings[-1][ns]))
    return _finish_mesh(name, bm, pal, parent, coll)


def _bevel_box(name, lo, hi, pal, parent, coll, bevel=0.0):
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = hi - lo
    centre = (lo + hi) / 2.0
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=min(bevel, min(size) * 0.42),
            segments=1,
            affect="EDGES",
            profile=0.5,
        )
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _finish_mesh(name, bm, pal, parent, coll)


def build_stanchion_post(coll):
    """Single 1x1 airport retractable-belt stanchion at origin (0,0,0), height 1.00 m."""
    root = bpy.data.objects.new("Stanchion_ROOT", None)
    coll.objects.link(root)

    # Every sub-mesh penetrates its neighbour slightly with distinct Z cap heights
    # so zero faces are ever coplanar and zero gaps appear at any camera angle.
    _lathe_solid(
        "Stanchion_Base_Rim",
        [(BASE_RADIUS, 0.000), (BASE_RADIUS - 0.002, 0.016)],
        "rubber",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Base_Shell",
        [
            (BASE_RADIUS - 0.006, 0.012),
            (BASE_RADIUS - 0.010, 0.024),
            (0.128, 0.044),
            (0.056, 0.058),
        ],
        "slate",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Base_Collar",
        [(0.046, 0.052), (0.042, 0.068), (0.036, 0.084)],
        "steel",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Pole",
        [(POLE_RADIUS, 0.070), (POLE_RADIUS, 0.795)],
        "chrome",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_Lower",
        [(0.035, 0.782), (CASSETTE_RADIUS, 0.806)],
        "steel",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_LowerDrum",
        [(CASSETTE_RADIUS, 0.802), (CASSETTE_RADIUS, 0.842)],
        "slate",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_BeltBand",
        [(BAND_RADIUS, BELT_Z_LO - 0.002), (BAND_RADIUS, BELT_Z_HI + 0.002)],
        "navy",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_UpperDrum",
        [(CASSETTE_RADIUS, 0.898), (CASSETTE_RADIUS, 0.958)],
        "slate",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_UpperBezel",
        [(CASSETTE_RADIUS, 0.954), (0.039, 0.974)],
        "steel",
        root,
        coll,
    )
    _lathe_solid(
        "Stanchion_Cassette_Cap",
        [(0.039, 0.970), (0.038, 0.980), (0.028, 0.993), (0.012, POLE_HEIGHT)],
        "chrome",
        root,
        coll,
    )
    return root


def build_queue_belt(coll):
    """1x3 taut dark-navy retractable belt spanning 2.0 m between posts at (0,0,0) and (0,-2,0)."""
    root = bpy.data.objects.new("QueueBelt_ROOT", None)
    coll.objects.link(root)

    # Belt fabric spans between clip heads, recessed 6 mm inside each clip head so
    # there are zero coplanar faces and zero gap.
    _bevel_box(
        "QueueBelt_Strap",
        (-BELT_HALF_T, -POST_SPAN + 0.056, BELT_Z_LO),
        (BELT_HALF_T, -0.056, BELT_Z_HI),
        "navy",
        root,
        coll,
        bevel=0.002,
    )
    # Clip heads sit flush into each stanchion's cassette band (r = 0.0455 m) at y = 0 and -2.0.
    for tag, y0, y1 in (
        ("Start", -0.064, -0.036),
        ("End", -POST_SPAN + 0.036, -POST_SPAN + 0.064),
    ):
        _bevel_box(
            "QueueBelt_Clip_%s" % tag,
            (-0.016, y0, BELT_Z_LO - 0.008),
            (0.016, y1, BELT_Z_HI + 0.008),
            "steel",
            root,
            coll,
            bevel=0.003,
        )
        _bevel_box(
            "QueueBelt_ClipLatch_%s" % tag,
            (-0.011, y0 + 0.005, BELT_Z_HI + 0.004),
            (0.011, y1 - 0.005, BELT_Z_HI + 0.016),
            "slate",
            root,
            coll,
            bevel=0.002,
        )
    return root


PIECES = {
    "tc_metal_pole_1a": (
        build_stanchion_post,
        (-BASE_RADIUS, -BASE_RADIUS, 0.0),
        (BASE_RADIUS, BASE_RADIUS, POLE_HEIGHT),
    ),
    "tc_metal_pole_chain_1a": (
        build_queue_belt,
        (-0.016, -POST_SPAN + 0.036, BELT_Z_LO - 0.008),
        (0.016, -0.036, BELT_Z_HI + 0.016),
    ),
}


def export_piece(stem, builder, coll):
    out = os.path.join(OUT_DIR, stem + ".glb")
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
    imp_path = out + ".import"
    if not os.path.exists(imp_path):
        fail("%s missing .import file" % imp_path)
    else:
        with open(imp_path, encoding="utf-8") as f:
            if ('import_script/path="%s"' % POST_IMPORT) not in f.read():
                fail("%s missing toon_post_import.gd binder" % imp_path)
    return out


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    clen, _ = struct.unpack_from("<II", data, 12)
    return json.loads(data[20 : 20 + clen].decode("utf-8")), len(data)


def _seam_counts(objs):
    """Count zero-area and duplicate coplanar triangles across exported mesh objects."""
    zero_area = 0
    tris = []
    for ob in objs:
        if ob.type != "MESH":
            continue
        me = ob.data
        me.calc_loop_triangles()
        xf = ob.matrix_world
        for lt in me.loop_triangles:
            a = xf @ me.vertices[lt.vertices[0]].co
            b = xf @ me.vertices[lt.vertices[1]].co
            c = xf @ me.vertices[lt.vertices[2]].co
            cross = (b - a).cross(c - a)
            area = 0.5 * cross.length
            if area < 1e-8:
                zero_area += 1
                continue
            tris.append(((a + b + c) / 3.0, cross.normalized(), area))
    buckets = {}
    for t in tris:
        key = tuple(round(v * 200.0) for v in t[0])
        buckets.setdefault(key, []).append(t)
    dup = 0
    for centre, n, area in tris:
        base = tuple(round(v * 200.0) for v in centre)
        matches = 0
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for oc, on, oa in buckets.get((base[0] + dx, base[1] + dy, base[2] + dz), ()):
                        if (centre - oc).length < 1e-3 and abs(n.dot(on)) > 0.999 and abs(area - oa) < 1e-4:
                            matches += 1
        if matches > 1:
            dup += 1
    return zero_area, dup // 2


def verify_written(stem, out):
    js, nbytes = parse_glb(out)
    mats = sorted(m["name"] for m in js.get("materials", []))
    imgs = js.get("images", [])
    nodes = [n.get("name", "?") for n in js.get("nodes", [])]
    if mats != [MAT_NAME]:
        fail("%s: materials %s != [%s]" % (stem, mats, MAT_NAME))
    if imgs:
        fail("%s: expected 0 embedded images, got %d" % (stem, len(imgs)))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    _images.clear()
    _materials.clear()
    bpy.ops.import_scene.gltf(filepath=out)
    bpy.context.view_layer.update()

    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    loops = 0
    outside = 0
    used_swatches = {}
    allowed_cells = {(c, r) for c, r, _f, _s in PALETTE.values()}
    for ob in objs:
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        uvl = ob.data.uv_layers.active
        for poly in ob.data.polygons:
            for li in poly.loop_indices:
                u, v = uvl.data[li].uv
                loops += 1
                rgb = sample_rgb(u, v)
                cell = (int(u * ATLAS_COLS), int((1.0 - v) * ATLAS_ROWS))
                if not (0.0 < u < 1.0 and 0.0 < v < 1.0) or rgb in EMPTY_RGB or cell not in allowed_cells:
                    outside += 1
                else:
                    used_swatches[cell] = rgb

    zero_area, dup_coplanar = _seam_counts(objs)
    exp_lo, exp_hi = Vector(PIECES[stem][1]), Vector(PIECES[stem][2])
    err = max(max(abs(a - b) for a, b in zip(lo, exp_lo)), max(abs(a - b) for a, b in zip(hi, exp_hi)))
    log(
        "ASSET %s bytes=%d meshes=%d materials=%s images=%d loops=%d outside_uv=%d "
        "zero_area=%d dup_coplanar=%d err=%.5f godot_min=(%.3f,%.3f,%.3f) godot_max=(%.3f,%.3f,%.3f) "
        "swatches=%s"
        % (
            stem,
            nbytes,
            len(objs),
            mats,
            len(imgs),
            loops,
            outside,
            zero_area,
            dup_coplanar,
            err,
            lo.x,
            lo.z,
            -hi.y,
            hi.x,
            hi.z,
            -lo.y,
            sorted(used_swatches.items()),
        )
    )
    if err > 0.002:
        fail("%s: bounds err %.5f > 0.002" % (stem, err))
    if outside > 0:
        fail("%s: %d UV loops outside allowed swatches" % (stem, outside))
    if zero_area > 0 or dup_coplanar > 0:
        fail("%s: zero_area=%d dup_coplanar=%d" % (stem, zero_area, dup_coplanar))


def verify_assembly():
    """Re-read both written GLBs together as InteriorKit places them and verify zero gap / zero poke-through."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
    post1 = [o for o in bpy.context.scene.objects if o.parent is None]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
    post2 = [o for o in bpy.data.objects if o not in before and o.parent is None]
    for r in post2:
        r.location.y = -POST_SPAN
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_chain_1a.glb"))
    belt = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.context.view_layer.update()

    # Check clip ends relative to each post center and cassette radius.
    belt_ys = [ (o.matrix_world @ v.co).y for o in belt for v in o.data.vertices ]
    belt_zs = [ (o.matrix_world @ v.co).z for o in belt for v in o.data.vertices ]
    clip_y_max = max(belt_ys)   # near y=0 post: must be in (-BAND_RADIUS, 0.0)
    clip_y_min = min(belt_ys)   # near y=-2 post: must be in (-2.0, -2.0 + BAND_RADIUS)
    log(
        "ASSEMBLY post1_y=0.000 post2_y=-%.3f belt_y=[%.4f, %.4f] belt_z=[%.4f, %.4f] cassette_r=%.4f"
        % (POST_SPAN, clip_y_min, clip_y_max, min(belt_zs), max(belt_zs), BAND_RADIUS)
    )
    if not (-BAND_RADIUS < clip_y_max < 0.0):
        fail("near clip y=%.4f does not engage post 1 cassette (-%.4f..0)" % (clip_y_max, BAND_RADIUS))
    if not (-POST_SPAN < clip_y_min < -POST_SPAN + BAND_RADIUS):
        fail("far clip y=%.4f does not engage post 2 cassette" % clip_y_min)
    _ = post1


# ---------------------------------------------------------------- Blender plates

def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _filmic_curve(v):
    a, b, c, d, e, f = 0.88, 0.60, 0.10, 0.20, 0.01, 0.30
    return (v * (a * v + c * b) + d * e) / (v * (a * v + b) + d * f) - e / f


def _filmic_rgb(rgb):
    w = _filmic_curve(FILMIC_WHITE)
    return tuple(max(0.0, _filmic_curve(_srgb_to_linear(c)) / w) for c in rgb)


def _setup_preview_toon_material(name, rgb=None):
    m = bpy.data.materials.new("PREV_" + name)
    m.use_nodes = True
    m.line_color = (*_filmic_rgb(OUTLINE_RGB), 1.0)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    if rgb is not None:
        albedo = nt.nodes.new("ShaderNodeRGB")
        albedo.outputs[0].default_value = (*[_srgb_to_linear(c) for c in rgb], 1.0)
        albedo_out = albedo.outputs[0]
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(TEXTURES, ATLAS_PNG), check_existing=True)
        tex.interpolation = "Linear"
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
    rimg = bpy.data.images.load(os.path.join(TEXTURES, RAMP_PNG), check_existing=True)
    rimg.colorspace_settings.name = "Non-Color"
    ramp.image = rimg
    ramp.interpolation = "Closest"
    ramp.extension = "EXTEND"
    nt.links.new(uv.outputs["Vector"], ramp.inputs["Vector"])

    light = nt.nodes.new("ShaderNodeVectorMath")
    light.operation = "MULTIPLY_ADD"
    nt.links.new(ramp.outputs["Color"], light.inputs[0])
    light.inputs[1].default_value = (1.0, 1.0, 1.0)
    light.inputs[2].default_value = (
        SKY_SIDE[0] * AMBIENT_SCALE,
        SKY_SIDE[1] * AMBIENT_SCALE,
        SKY_SIDE[2] * AMBIENT_SCALE,
    )
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(albedo_out, mul.inputs[0])
    nt.links.new(light.outputs["Vector"], mul.inputs[1])
    nt.links.new(mul.outputs["Vector"], emit.inputs["Color"])
    return m


def _setup_preview_scene(res_x=512, res_y=512):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 1
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("PREV_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.76, 0.78, 0.81, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 1.5
    fs = scene.view_layers[0].freestyle_settings
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("PREV_Lines")
    ls.select_by_visibility = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("PREV_Outline")
    ls.linestyle.color = OUTLINE_RGB
    ls.linestyle.thickness = 1.5
    return scene


def _add_ref_cube(loc):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    me = bpy.data.meshes.new("RefCube_1m")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(_setup_preview_toon_material("RefCube", (0.85, 0.42, 0.25)))
    ob = bpy.data.objects.new("RefCube_1m", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _add_floor_slab(x0, x1, y0, y1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((x1 - x0, y1 - y0, 0.04)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(((x0 + x1) * 0.5, (y0 + y1) * 0.5, -0.02)), verts=bm.verts)
    me = bpy.data.meshes.new("FloorPad")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(_setup_preview_toon_material("Floor", (0.88, 0.86, 0.82)))
    ob = bpy.data.objects.new("FloorPad", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _prove_in_frame_and_visible(tag, scene, cam, subjects, blockers):
    """Prove every vertex of subjects projects inside margin and raycasts hit subject."""
    margin = 0.03
    xs, ys = [], []
    for o in subjects:
        for v in o.data.vertices:
            p = world_to_camera_view(scene, cam, o.matrix_world @ v.co)
            xs.append(p.x)
            ys.append(p.y)
            if p.z <= cam.data.clip_start:
                print("PROBE_INVALID %s behind camera" % tag, flush=True)
                sys.exit(1)
    u0, v0, u1, v1 = min(xs), min(ys), max(xs), max(ys)
    share = max(u1 - u0, v1 - v0)
    if u0 < margin or v0 < margin or u1 > 1.0 - margin or v1 > 1.0 - margin or share < 0.15:
        print(
            "PROBE_INVALID %s out of frame u=[%.3f,%.3f] v=[%.3f,%.3f] share=%.2f"
            % (tag, u0, u1, v0, v1, share),
            flush=True,
        )
        sys.exit(1)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    cam_dir = (cam.matrix_world.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()
    hits = 0
    for o in subjects:
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        mid = sum(pts, Vector((0, 0, 0))) / len(pts)
        if cam.data.type == "ORTHO":
            origin = mid - cam_dir * 10.0
            direction = cam_dir
        else:
            origin = cam.matrix_world.translation
            direction = (mid - origin).normalized()
        ok, _loc, _n, _idx, hit_obj, _mat = scene.ray_cast(depsgraph, origin, direction)
        if ok and hit_obj in subjects:
            hits += 1
        elif ok and hit_obj in blockers:
            log("NOTE %s center ray hit %s before %s" % (tag, hit_obj.name, o.name))
    if hits == 0:
        print("PROBE_INVALID %s zero unoccluded hits on subjects" % tag, flush=True)
        sys.exit(1)
    log("IN_FRAME %s u=[%.3f,%.3f] v=[%.3f,%.3f] share=%.2f ray_hits=%d/%d" % (tag, u0, u1, v0, v1, share, hits, len(subjects)))


def _ortho_shot(scene, subjects, all_objs, view_name, cam_dir, up_vec, out_path):
    cam_data = bpy.data.cameras.new("PREV_Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("PREV_Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    rot = (-Vector(cam_dir)).to_track_quat("-Z", "Y")
    # Adjust roll so camera +Y aligns cleanly with desired up_vec when viewing horizontally.
    if abs(Vector(cam_dir).z) < 0.9:
        forward = Vector(cam_dir).normalized()
        right = forward.cross(Vector(up_vec)).normalized()
        up = right.cross(forward).normalized()
        m = Matrix((right, up, -forward)).transposed().to_4x4()
        rot = m.to_quaternion()
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rot
    bpy.context.view_layer.update()

    inv = rot.to_matrix().inverted()
    pts = [inv @ (o.matrix_world @ v.co) for o in all_objs for v in o.data.vertices]
    span_x = max(p.x for p in pts) - min(p.x for p in pts)
    span_y = max(p.y for p in pts) - min(p.y for p in pts)
    cam_data.ortho_scale = max(span_x, span_y) / 0.86
    mid = Vector((
        (min(p.x for p in pts) + max(p.x for p in pts)) * 0.5,
        (min(p.y for p in pts) + max(p.y for p in pts)) * 0.5,
        max(p.z for p in pts) + 15.0,
    ))
    cam.location = rot.to_matrix() @ mid
    cam_data.clip_start = 0.1
    cam_data.clip_end = 50.0
    bpy.context.view_layer.update()

    _prove_in_frame_and_visible(view_name, scene, cam, subjects, [o for o in all_objs if o not in subjects])
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_data)


def _assemble_contact_sheet(paths, out_path, cols=3, cell_w=512, cell_h=512, gap=12):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rows = math.ceil(len(paths) / cols)
    W = cols * cell_w + (cols + 1) * gap
    H = rows * cell_h + (rows + 1) * gap
    canvas = [0.12, 0.13, 0.16, 1.0] * (W * H)
    for idx, p in enumerate(paths):
        img = bpy.data.images.load(p)
        img.colorspace_settings.name = "sRGB"
        px = img.pixels[:]
        r, c = divmod(idx, cols)
        x0 = gap + c * (cell_w + gap)
        y0 = gap + r * (cell_h + gap)
        for yy in range(cell_h):
            dst_row = H - 1 - (y0 + yy)
            src_row = cell_h - 1 - yy
            for xx in range(cell_w):
                s = (src_row * cell_w + xx) * 4
                d = (dst_row * W + x0 + xx) * 4
                canvas[d : d + 4] = px[s : s + 4]
        bpy.data.images.remove(img)
    out = bpy.data.images.new("sheet", W, H, alpha=True)
    out.pixels[:] = canvas
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    log("SHEET %s %dx%d panels=%d" % (out_path, W, H, len(paths)))


def render_plates(plates_dir):
    os.makedirs(plates_dir, exist_ok=True)
    six_axes = (
        ("front", (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
        ("back", (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)),
        ("left", (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
        ("right", (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
        ("top", (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
        ("bottom", (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)),
    )
    configs = [
        ("post", False, (0.72, 0.72, 0.5)),
        ("belt_assembled", True, (0.72, 0.72, 0.5)),
    ]
    sheet_inputs = []
    for label, with_belt, cube_loc in configs:
        scene = _setup_preview_scene(512, 512)
        prev_mat = _setup_preview_toon_material("Atlas")
        subjects = []
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
        subjects += [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        if with_belt:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
            p2 = [o for o in bpy.data.objects if o not in before]
            for o in p2:
                if o.parent is None:
                    o.location.y = -POST_SPAN
            subjects += [o for o in p2 if o.type == "MESH"]
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_chain_1a.glb"))
            subjects += [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        for o in subjects:
            for slot in o.material_slots:
                slot.material = prev_mat
        cube = _add_ref_cube(cube_loc)
        all_objs = subjects + [cube]
        for axis_name, cdir, cup in six_axes:
            out_png = os.path.join(plates_dir, "%s_%s.png" % (label, axis_name))
            _ortho_shot(scene, subjects, all_objs, "%s_%s" % (label, axis_name), cdir, cup, out_png)
            sheet_inputs.append(out_png)
        _assemble_contact_sheet(
            sheet_inputs[-6:],
            os.path.join(plates_dir, "six_axis_%s_sheet.png" % label),
        )

    # Distance + hero 3/4 view with floor slab and 1 m reference cube.
    scene = _setup_preview_scene(960, 640)
    prev_mat = _setup_preview_toon_material("Atlas")
    subjects = []
    # 1 single stanchion at x=-1.2, y=0; 1 assembled 1x3 queue belt at x=0.4, y=0..-2.0
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
    s_single = [o for o in bpy.data.objects if o not in before]
    for o in s_single:
        if o.parent is None:
            o.location = Vector((-1.1, -1.0, 0.0))
    subjects += [o for o in s_single if o.type == "MESH"]

    for py in (0.0, -POST_SPAN):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_1a.glb"))
        p = [o for o in bpy.data.objects if o not in before]
        for o in p:
            if o.parent is None:
                o.location = Vector((0.35, py, 0.0))
        subjects += [o for o in p if o.type == "MESH"]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "tc_metal_pole_chain_1a.glb"))
    b = [o for o in bpy.data.objects if o not in before]
    for o in b:
        if o.parent is None:
            o.location = Vector((0.35, 0.0, 0.0))
    subjects += [o for o in b if o.type == "MESH"]

    for o in subjects:
        for slot in o.material_slots:
            slot.material = prev_mat
    cube = _add_ref_cube((1.65, 0.15, 0.5))
    _add_floor_slab(-2.0, 2.5, -2.8, 1.0)

    cam_data = bpy.data.cameras.new("Hero_Cam")
    cam_data.lens = 45.0
    cam = bpy.data.objects.new("Hero_Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = Vector((2.9, -4.3, 2.2))
    direction = Vector((-0.05, -0.8, 0.42)) - cam.location
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = direction.to_track_quat("-Z", "Y")
    bpy.context.view_layer.update()
    _prove_in_frame_and_visible("blender_hero_distance", scene, cam, subjects, [cube])
    hero_path = os.path.join(plates_dir, "stanchions_hero_distance.png")
    scene.render.filepath = hero_path
    bpy.ops.render.render(write_still=True)


def save_blend():
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _images.clear()
    _materials.clear()
    c_post = bpy.data.collections.new("tc_metal_pole_1a")
    bpy.context.scene.collection.children.link(c_post)
    r_post = build_stanchion_post(c_post)
    r_post.location = Vector((-1.0, 0.0, 0.0))

    c_belt = bpy.data.collections.new("tc_metal_pole_chain_1a")
    bpy.context.scene.collection.children.link(c_belt)
    r_belt = build_queue_belt(c_belt)
    r_belt.location = Vector((1.0, 1.0, 0.0))

    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=True)
    log("BLEND saved %s" % BLEND_OUT)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    do_plates = "--plates" in argv
    plates_dir = DEFAULT_PLATES_DIR
    if do_plates:
        idx = argv.index("--plates")
        if idx + 1 < len(argv) and not argv[idx + 1].startswith("--"):
            plates_dir = argv[idx + 1]

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for stem, (builder, _lo, _hi) in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _images.clear()
        _materials.clear()
        coll = bpy.data.collections.new(stem)
        bpy.context.scene.collection.children.link(coll)
        builder(coll)
        out = export_piece(stem, builder, coll)
        written.append((stem, out))

    for stem, out in written:
        verify_written(stem, out)
    verify_assembly()
    save_blend()
    if do_plates:
        render_plates(plates_dir)

    log("DONE pieces=%d fails=%d" % (len(written), len(FAILS)))
    if FAILS:
        sys.exit(1)


if __name__ == "__main__":
    main()
