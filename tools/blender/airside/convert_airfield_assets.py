"""Convert Toon Planes Pack landmarks, perimeter fence and GSE vehicles to game/assets/airside/landmarks/<stem>.glb.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\convert_airfield_assets.py' [-- stem ...]
"""

import json
import os
import re
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.dont_write_bytecode = True
GAME = os.path.join(REPO, "game")
TEX_DIR = os.path.join(GAME, "assets", "textures")
OUT_DIR = os.path.join(GAME, "assets", "airside", "landmarks")
POST_IMPORT = "res://assets/toon_post_import.gd"
TP_MODELS = "C:\\Users\\chulf\\Assets new\\Toon Series\\Toon Planes Pack\\Models"

MATERIALS = {
    "Atlas_1A_D": ("TP_Atlas_1A_D", "opaque", "tp_atlas_1a_d.png"),
    "Atlas_Simple_1A_D": ("TP_Atlas_Simple_1A_D", "opaque", "tp_atlas_1a_d.png"),
    "Atlas_Lights_1A_D": ("TP_Atlas_Lights_1A_D", "emissive", "tp_atlas_lights_1a_d.png"),
    "Glass_Vehicles_01A_D": ("TP_Glass_1A_D", "glass", "tp_glass_gradient_1a_d.png"),
}

ASSETS = {
    "tp_control_tower_01a": {
        "fbx": "TP_Control_Tower_01A.fbx",
        "drop_objects": ["TP_Control_Tower_01A_Road"],
        "ground_lift": 0.10,
    },
    "tp_radar_01a": {"fbx": "TP_Radar_01A.fbx"},
    "tp_hangar_01a": {"fbx": "TP_Hangar_01A.fbx"},
    "tp_hangar_02a": {"fbx": "TP_Hangar_02A.fbx"},
    "tp_metal_fence_01a": {
        "fbx": "TP_Metal_Fence_01A.fbx",
        "ground_lift": 0.20,
    },
    "tp_cistern_01a": {"fbx": "TP_Cistern_01A.fbx"},
    "tp_loading_truck_02a": {"fbx": "TP_Loading_Truck_02A.fbx"},
    "tp_bus_01a": {"fbx": "TP_Bus_01A.fbx"},
    "tp_pick_up_01a": {"fbx": "TP_Pick_Up_01A.fbx"},
}

FLOOR_TOLERANCE_M = 0.02
BOUNDS_TOLERANCE_M = 0.02


def log(*a):
    print("AIRFIELD_ASSET", *a, flush=True)


def die(msg):
    print("AIRFIELD_ASSET_FAIL", msg, flush=True)
    sys.exit(1)


def base_name(name):
    return re.sub(r"\.\d{3}$", "", name)


def build_material(gltf_name, kind, png):
    mat = bpy.data.materials.get(gltf_name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(gltf_name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX_DIR, png), check_existing=True)
    if tex.image.size[0] == 0:
        die("atlas image failed to load: %s" % png)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    if kind == "glass":
        bsdf.inputs["Alpha"].default_value = 0.29
        bsdf.inputs["Roughness"].default_value = 0.2
        mat.surface_render_method = "BLENDED"
    elif kind == "emissive":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def rebind_materials(stem, objs):
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            if slot.material is None:
                die("%s: %s has empty material slot" % (stem, o.name))
            key = base_name(slot.material.name)
            if key not in MATERIALS:
                die("%s: unmapped material '%s' on %s" % (stem, key, o.name))
            slot.material = build_material(*MATERIALS[key])
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    used_imgs = {
        n.image
        for o in objs
        if o.type == "MESH"
        for s in o.material_slots
        if s.material and s.material.use_nodes
        for n in s.material.node_tree.nodes
        if n.type == "TEX_IMAGE" and n.image is not None
    }
    for img in list(bpy.data.images):
        if img not in used_imgs:
            img.use_fake_user = False
            bpy.data.images.remove(img)


def drop_loose(stem, objs):
    removed = 0
    for o in objs:
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        edges = [e for e in bm.edges if not e.link_faces]
        bmesh.ops.delete(bm, geom=edges, context="EDGES")
        verts = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=verts, context="VERTS")
        removed += len(verts)
        bm.to_mesh(o.data)
        bm.free()
    bpy.context.view_layer.update()
    log("LOOSE %s removed_verts=%d" % (stem, removed))


def apply_ground_lift(stem, objs, dz):
    if abs(dz) < 1e-6:
        return
    offset = Vector((0.0, 0.0, dz))
    for o in objs:
        if o.type != "MESH":
            continue
        local_off = o.matrix_world.inverted().to_3x3() @ offset
        for v in o.data.vertices:
            v.co += local_off
        o.data.update()
    bpy.context.view_layer.update()
    log("GROUND_LIFT %s dz=%.3f" % (stem, dz))


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or length != len(data):
        die("%s: invalid GLB header" % path)
    clen, _ctype = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + clen].decode("utf-8")), len(data)


def glb_accessor(path, js, acc_idx):
    acc = js["accessors"][acc_idx]
    bv = js["bufferViews"][acc["bufferView"]]
    with open(path, "rb") as f:
        f.seek(20)
        clen = struct.unpack_from("<I", f.read(4), 0)[0]
        f.seek(20 + clen + 8 + bv.get("byteOffset", 0) + acc.get("byteOffset", 0))
        blob = f.read(bv["byteLength"])
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
    stride = bv.get("byteStride", comps * struct.calcsize(fmt))
    out = []
    for k in range(acc["count"]):
        vals = struct.unpack_from("<" + fmt * comps, blob, k * stride)
        out.append(vals[0] if comps == 1 else vals)
    return out


def node_matrix(nd):
    if "matrix" in nd:
        m = nd["matrix"]
        return Matrix((m[0::4], m[1::4], m[2::4], m[3::4]))
    t = Matrix.Translation(Vector(nd.get("translation", [0.0, 0.0, 0.0])))
    q = nd.get("rotation", [0.0, 0.0, 0.0, 1.0])
    from mathutils import Quaternion
    r = Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
    s = nd.get("scale", [1.0, 1.0, 1.0])
    sc = Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    return t @ r @ sc


def glb_bounds(js):
    nodes = js.get("nodes", [])
    parent = {ch: i for i, nd in enumerate(nodes) for ch in nd.get("children", [])}
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for i, nd in enumerate(nodes):
        if "mesh" not in nd:
            continue
        m = node_matrix(nd)
        j = i
        while j in parent:
            j = parent[j]
            m = node_matrix(nodes[j]) @ m
        mesh = js["meshes"][nd["mesh"]]
        for prim in mesh["primitives"]:
            pos_acc = js["accessors"][prim["attributes"]["POSITION"]]
            pmin, pmax = pos_acc["min"], pos_acc["max"]
            for dx in (pmin[0], pmax[0]):
                for dy in (pmin[1], pmax[1]):
                    for dz in (pmin[2], pmax[2]):
                        w = m @ Vector((dx, dy, dz))
                        lo = Vector(map(min, lo, w))
                        hi = Vector(map(max, hi, w))
    return lo, hi


def scene_bounds_yup(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            g = Vector((w.x, w.z, -w.y))
            lo = Vector(map(min, lo, g))
            hi = Vector(map(max, hi, g))
    return lo, hi


def write_scene_import(glb_path):
    path = glb_path + ".import"
    line = 'import_script/path="%s"' % POST_IMPORT
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
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
    with open(path, "w", newline="\n") as f:
        f.write(text)


def convert(stem, spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(TP_MODELS, spec["fbx"]))
    bpy.context.view_layer.update()

    for drop_name in spec.get("drop_objects", []):
        victims = [o for o in bpy.context.scene.objects if base_name(o.name) == drop_name]
        if not victims:
            die("%s: expected object '%s' to drop, not found" % (stem, drop_name))
        for v in victims:
            bpy.data.objects.remove(v, do_unlink=True)
        log("DROPPED %s object=%s count=%d" % (stem, drop_name, len(victims)))

    objs = list(bpy.context.scene.objects)
    for o in objs:
        if o.animation_data:
            o.animation_data_clear()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)

    drop_loose(stem, objs)
    rebind_materials(stem, objs)
    apply_ground_lift(stem, objs, spec.get("ground_lift", 0.0))

    reflected = [o.name for o in objs if o.matrix_world.determinant() <= 0.0]
    if reflected:
        die("%s: negative determinant objects %s" % (stem, reflected))

    mats = sorted({s.material.name for o in objs if o.type == "MESH" for s in o.material_slots})
    imgs = sorted({
        n.image.name
        for o in objs
        if o.type == "MESH"
        for s in o.material_slots
        if s.material and s.material.use_nodes
        for n in s.material.node_tree.nodes
        if n.type == "TEX_IMAGE" and n.image is not None
    })
    verts = sum(len(o.data.vertices) for o in objs if o.type == "MESH")
    s_lo, s_hi = scene_bounds_yup(objs)

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

    js, nbytes = parse_glb(out)
    f_mats = sorted(m["name"] for m in js.get("materials", []))
    f_imgs = len(js.get("images", []))
    f_anims = [a["name"] for a in js.get("animations", [])]
    f_lo, f_hi = glb_bounds(js)
    size = f_hi - f_lo
    log(
        "ASSET %s file=%s bytes=%d verts=%d nodes=%d meshes=%d materials=%s images=%d"
        % (stem, os.path.relpath(out, REPO).replace("\\", "/"), nbytes, verts,
           len(js.get("nodes", [])), len(js.get("meshes", [])), f_mats, f_imgs)
    )
    log(
        "BOUNDS %s size=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)"
        % (stem, size.x, size.y, size.z, f_lo.x, f_lo.y, f_lo.z, f_hi.x, f_hi.y, f_hi.z)
    )
    if f_mats != mats:
        die("%s: file materials %s differ from scene %s" % (stem, f_mats, mats))
    if f_imgs < 1 or f_imgs != len(imgs):
        die("%s: file images %d, scene images %s" % (stem, f_imgs, imgs))
    if f_anims:
        die("%s: unexpected animations %s" % (stem, f_anims))
    for k in range(3):
        if abs(f_lo[k] - s_lo[k]) > BOUNDS_TOLERANCE_M or abs(f_hi[k] - s_hi[k]) > BOUNDS_TOLERANCE_M:
            die("%s: written bounds %s..%s differ from scene %s..%s" % (stem, f_lo, f_hi, s_lo, s_hi))
    if abs(f_lo.y) > FLOOR_TOLERANCE_M:
        die("%s: floor min_y=%.3f expected ~0.0" % (stem, f_lo.y))
    write_scene_import(out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stems = argv or list(ASSETS)
    unknown = [s for s in stems if s not in ASSETS]
    if unknown:
        die("unknown stems %s" % unknown)
    for stem in stems:
        convert(stem, ASSETS[stem])
    log("DONE %d assets" % len(stems))


if __name__ == "__main__":
    main()
