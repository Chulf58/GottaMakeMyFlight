"""Convert a batch of Toon Series FBX models (Unity-only packs) to .glb in game/assets/.

Run from WSL (Blender is a Windows program, so every path it sees is a Windows path):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\convert_toon_batch.py'

Optional after `--`: asset stems to convert (default: the whole BATCH table).
Then run a Godot `--headless --import`, which binds the toon materials through
game/assets/toon_post_import.gd.

What it does, per asset:
1. Factory-empty scene, import the vendor FBX. Blender's FBX importer applies the
   file's UnitScaleFactor (100 in every file of both packs), so the result is in metres.
2. Rebind the palette atlas. Each FBX material is resolved by (pack, material name) to
   one of five pack-qualified materials, rebuilt as Principled with the atlas PNG that
   this script converts from the vendor PSD. An unknown material name stops the run.
3. Characters: keep only the parts the Unity source prefab enables, drop shape keys,
   join the parts into one skinned mesh, move the idle action from the idle FBX onto the
   character armature, and export only that action, named "idle".
4. Export .glb (Y-up, no vertex colours), then RE-READ THE WRITTEN FILE and check
   materials, images, animations and bounds against the scene. Any mismatch stops the run.
5. Write or patch the .glb.import so Godot runs the post-import material binder.
"""

import json
import math
import os
import re
import struct
import sys

import bpy
from mathutils import Matrix, Vector

REPO = "C:\\Users\\chulf\\Gotta-make-my-flight"
GAME = os.path.join(REPO, "game")
ASSETS = os.path.join(GAME, "assets")
TEX_DIR = os.path.join(ASSETS, "textures")
SRC = "C:\\Users\\chulf\\Assets new\\Toon Series"
TP = os.path.join(SRC, "Toon Planes Pack")
TCP = os.path.join(SRC, "Toon City People")
POST_IMPORT = "res://assets/toon_post_import.gd"

# Vendor PSD -> PNG under game/assets/textures/. (png name, mipmaps)
TEXTURES = {
    os.path.join(TP, "Textures", "TP_Atlas_1A_D.psd"): ("tp_atlas_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Atlas_Lights_1A_D.psd"): ("tp_atlas_lights_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Glass_Gradient_1A_D.psd"): ("tp_glass_gradient_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Toon_Ramp_1D_D.psd"): ("tp_toon_ramp_1d_d.png", False),
    os.path.join(TCP, "Textures", "Atlas_1A_D 1.psd"): ("tcp_atlas_1a_d.png", True),
    os.path.join(TCP, "Textures", "TCP_Toon_Ramp_01D_D.psd"): ("tcp_toon_ramp_01d_d.png", False),
}

# (pack, FBX material name) -> (glTF material name, kind, png). The pairs come from the
# Unity .fbx.meta externalObjects remaps; both packs name their atlas "Atlas_1A_D".
MATERIALS = {
    ("TP", "Atlas_1A_D"): ("TP_Atlas_1A_D", "opaque", "tp_atlas_1a_d.png"),
    ("TP", "Atlas_Simple_1A_D"): ("TP_Atlas_Simple_1A_D", "opaque", "tp_atlas_1a_d.png"),
    ("TP", "Atlas_Lights_1A_D"): ("TP_Atlas_Lights_1A_D", "emissive", "tp_atlas_lights_1a_d.png"),
    ("TP", "Glass_Vehicles_01A_D"): ("TP_Glass_1A_D", "glass", "tp_glass_gradient_1a_d.png"),
    ("TCP", "Atlas_1A_D"): ("TCP_Atlas_1A_D", "opaque", "tcp_atlas_1a_d.png"),
}

# stem -> (pack, category, fbx, idle fbx or None, source prefab or None)
BATCH = {
    "tp_plane_05a": ("TP", "planes", "TP_Plane_05A.fbx", None, None),
    "tp_runway_01a": ("TP", "airside", "TP_Runway_01A.fbx", None, None),
    "tp_runway_02a": ("TP", "airside", "TP_Runway_02A.fbx", None, None),
    "tp_runway_03a": ("TP", "airside", "TP_Runway_03A.fbx", None, None),
    "tp_runway_04a": ("TP", "airside", "TP_Runway_04A.fbx", None, None),
    "tp_runway_05a": ("TP", "airside", "TP_Runway_05A.fbx", None, None),
    "tp_airport_01a": ("TP", "buildings", "TP_Airport_01A.fbx", None, None),
    "tp_loading_truck_01a": ("TP", "vehicles", "TP_Loading_Truck_01A.fbx", None, None),
    "tcp_male_character_01": (
        "TCP",
        "people",
        "TCP_Male_Character_01.fbx",
        "Poses\\TCP_Male_Idle_01.fbx",
        "Prefabs\\Male Character Sources\\TCP_Male_Character_01.prefab",
    ),
    "tcp_female_character_01": (
        "TCP",
        "people",
        "TCP_Female_Character_01.fbx",
        "Poses\\TCP_Female_Idle_01.fbx",
        "Prefabs\\Female Character Sources\\TCP_Female_Character_01.prefab",
    ),
}

REST_TOLERANCE = 1e-3
# The idle rigs' joints sit up to a few cm off the characters' (female: 2.7 cm). Only
# the root bones copy location, so the character keeps its own proportions.
JOINT_TOLERANCE = 0.05
LOCATION_BONES = ("Root", "Hips")
BOUNDS_TOLERANCE = 0.02


def log(*a):
    print("TOON", *a, flush=True)


def die(msg):
    print("TOON_FAIL", msg, flush=True)
    sys.exit(1)


def base_name(name):
    return re.sub(r"\.\d{3}$", "", name)


# ---------------------------------------------------------------- textures


def convert_textures():
    os.makedirs(TEX_DIR, exist_ok=True)
    for src, (png, mipmaps) in TEXTURES.items():
        img = bpy.data.images.load(src)
        if img.size[0] == 0 or img.size[1] == 0:
            die("PSD did not decode: %s" % src)
        dst = os.path.join(TEX_DIR, png)
        img.filepath_raw = dst
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)
        check = bpy.data.images.load(dst)
        log("TEXTURE %s size=%s channels=%d" % (png, tuple(check.size), check.channels))
        if tuple(check.size) == (0, 0):
            die("written PNG unreadable: %s" % dst)
        bpy.data.images.remove(check)
        write_texture_import(dst, mipmaps)


def write_texture_import(png_path, mipmaps):
    """A minimal .import so Godot keeps the atlas lossless (gradient swatches) with mipmaps."""
    path = png_path + ".import"
    if os.path.exists(path):
        return
    with open(path, "w", newline="\n") as f:
        f.write(
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
            "compress/mode=0\nmipmaps/generate=%s\ndetect_3d/compress_to=0\n"
            % ("true" if mipmaps else "false")
        )


# ---------------------------------------------------------------- materials


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
        die("atlas image did not load for %s: %s" % (gltf_name, png))
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    if kind == "glass":
        # Unity Glass_Vehicles_01A_D: URP transparent, base colour 0.85 grey, alpha 0.29.
        bsdf.inputs["Alpha"].default_value = 0.29
        bsdf.inputs["Roughness"].default_value = 0.2
        mat.surface_render_method = "BLENDED"
    elif kind == "emissive":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def rebind_materials(pack, objs):
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            if slot.material is None:
                die("%s has an empty material slot" % o.name)
            key = (pack, base_name(slot.material.name))
            if key not in MATERIALS:
                die("unmapped material %s on %s" % (key, o.name))
            slot.material = build_material(*MATERIALS[key])
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)


# ---------------------------------------------------------------- characters


def prefab_active_names(prefab_path):
    """GameObject names with m_IsActive: 1 in a Unity prefab (YAML)."""
    names = set()
    current = None
    in_go = False
    with open(prefab_path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("GameObject:"):
                in_go, current = True, None
            elif line.startswith("--- "):
                in_go = False
            elif in_go and line.strip().startswith("m_Name:"):
                current = line.split(":", 1)[1].strip()
            elif in_go and line.strip().startswith("m_IsActive:"):
                if line.split(":", 1)[1].strip() == "1" and current:
                    names.add(current)
                in_go = False
    return names



def build_character(stem, idle_fbx, prefab):
    scene_objs = list(bpy.context.scene.objects)
    arms = [o for o in scene_objs if o.type == "ARMATURE"]
    if len(arms) != 1:
        die("%s: expected one armature, found %d" % (stem, len(arms)))
    arm = arms[0]
    active = prefab_active_names(os.path.join(TCP, prefab))
    meshes = [o for o in scene_objs if o.type == "MESH"]
    keep = [o for o in meshes if base_name(o.name) in active]
    drop = [o for o in meshes if o not in keep]
    log("%s prefab active parts: %s" % (stem, sorted(o.name for o in keep)))
    if not keep:
        die("%s: no mesh matches the prefab's active parts" % stem)
    for o in drop:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in keep:
        if o.data.shape_keys:
            o.shape_key_clear()
        if o.animation_data:
            o.animation_data_clear()
        mods = [m for m in o.modifiers if m.type == "ARMATURE"]
        if not mods or mods[0].object != arm:
            die("%s: part %s is not skinned to %s" % (stem, o.name, arm.name))
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = stem + "_body"
    body.data.name = stem + "_body"

    # Idle: import the armature-only FBX. Its rest pose is an arms-down pose, not the
    # character's T-pose, so its fcurves (relative to ITS rest) cannot be assigned to
    # the character armature as they are. Retarget instead: every character bone copies
    # the idle bone's world rotation (the root bones also its location), and the result is baked into a new action.
    before = set(bpy.data.objects)
    actions_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=os.path.join(TCP, "Models", idle_fbx))
    new = [o for o in bpy.data.objects if o not in before]
    idle_arm = next((o for o in new if o.type == "ARMATURE"), None)
    takes = [a for a in bpy.data.actions if a not in actions_before]
    if idle_arm is None or not takes:
        die("%s: idle FBX has no armature or no action" % stem)
    # The idle FBX carries several takes; two are 1-3 frame stubs. Take the longest.
    take = max(takes, key=lambda a: a.frame_range[1] - a.frame_range[0])
    if not idle_arm.animation_data:
        idle_arm.animation_data_create()
    idle_arm.animation_data.action = take
    if hasattr(idle_arm.animation_data, "action_slot") and take.slots:
        idle_arm.animation_data.action_slot = take.slots[0]
    shared = [b.name for b in idle_arm.data.bones if b.name in arm.data.bones]
    only_char = sorted(b.name for b in arm.data.bones if b.name not in idle_arm.data.bones)
    only_idle = sorted(b.name for b in idle_arm.data.bones if b.name not in arm.data.bones)
    parent_mismatch = []
    length_dev = 0.0
    worst_bone = None
    for name in shared:
        pa = arm.data.bones[name].parent
        pb = idle_arm.data.bones[name].parent
        if (pa.name if pa else None) != (pb.name if pb else None):
            parent_mismatch.append(name)
        # Proportions: the joint offset from the parent's head. Blender's bone LENGTH
        # is guessed for leaf bones on FBX import, so it is no measure of the rig.
        dev = abs(joint_offset(arm, name) - joint_offset(idle_arm, name))
        if dev > length_dev:
            length_dev, worst_bone = dev, name
    arm_dev = max(abs(arm.matrix_world[i][j] - idle_arm.matrix_world[i][j]) for i in range(4) for j in range(4))
    weighted_unanimated = sorted(n for n in only_char if n in body.vertex_groups and group_has_weight(body, n))
    log(
        "%s idle take=%s frames=%s takes=%d shared_bones=%d only_character=%s only_idle=%s "
        "joint_offset_max_dev_m=%.4f (%s) armature_matrix_dev=%.6f parent_mismatch=%s weighted_unanimated=%s"
        % (
            stem,
            take.name,
            tuple(round(v) for v in take.frame_range),
            len(takes),
            len(shared),
            only_char,
            only_idle,
            length_dev,
            worst_bone,
            arm_dev,
            parent_mismatch,
            weighted_unanimated,
        )
    )
    if only_idle or parent_mismatch or weighted_unanimated or arm_dev > REST_TOLERANCE or length_dev > JOINT_TOLERANCE:
        die("%s: idle rig does not match the character rig" % stem)

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        if pb.name not in idle_arm.data.bones:
            continue
        c = pb.constraints.new("COPY_TRANSFORMS" if pb.name in LOCATION_BONES else "COPY_ROTATION")
        c.target = idle_arm
        c.subtarget = pb.name
    # only_selected=False below bakes every bone, so no bone selection is needed.
    f0, f1 = int(take.frame_range[0]), int(take.frame_range[1])
    bpy.ops.nla.bake(
        frame_start=f0,
        frame_end=f1,
        step=1,
        only_selected=False,
        visual_keying=True,
        clear_constraints=True,
        use_current_action=False,
        bake_types={"POSE"},
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    action = arm.animation_data.action
    if action is None or tuple(round(v) for v in action.frame_range) != (f0, f1):
        die("%s: bake produced no action over %d..%d" % (stem, f0, f1))
    action.name = "idle"
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a != action:
            bpy.data.actions.remove(a)
    # The FBX armature object carries a 90 degree X rotation. Left in, it becomes a rotated
    # glTF node between the scene root and the Skeleton3D, so the mesh's own space no
    # longer matches where Godot draws it (bounds, rays and a later vertex-animation bake
    # would all read the wrong frame). Apply it: armature space then equals model space.
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if body.parent != arm or any(abs(v) > 1e-6 for v in arm.rotation_euler):
        die("%s: armature rotation was not applied" % stem)
    bpy.context.scene.frame_start = f0
    bpy.context.scene.frame_end = f1
    bpy.context.scene.frame_set(f0)
    return [arm, body]


def joint_offset(arm, name):
    bone = arm.data.bones[name]
    if bone.parent is None:
        return bone.head_local.length
    return (bone.head_local - bone.parent.head_local).length


def group_has_weight(obj, group_name):
    gi = obj.vertex_groups[group_name].index
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == gi and g.weight > 1e-4:
                return True
    return False


# ---------------------------------------------------------------- glb re-read


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a GLB: %s" % path)
    jlen, _jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20 : 20 + jlen])
    return js, len(data)


def node_matrix(nd):
    if "matrix" in nd:
        m = nd["matrix"]
        return Matrix([[m[c * 4 + r] for c in range(4)] for r in range(4)])
    t = nd.get("translation", [0, 0, 0])
    r = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    from mathutils import Quaternion

    q = Quaternion((r[3], r[0], r[1], r[2]))
    return (
        Matrix.Translation(Vector(t))
        @ q.to_matrix().to_4x4()
        @ Matrix.Diagonal(Vector((s[0], s[1], s[2], 1.0)))
    )


def glb_bounds(js):
    """World AABB of every mesh node in the written file (glTF axes, Y up)."""
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    nodes = js.get("nodes", [])
    roots = js["scenes"][js.get("scene", 0)]["nodes"]

    def walk(i, parent):
        nd = nodes[i]
        world = parent @ node_matrix(nd)
        if "mesh" in nd:
            for prim in js["meshes"][nd["mesh"]]["primitives"]:
                acc = js["accessors"][prim["attributes"]["POSITION"]]
                mn, mx = acc["min"], acc["max"]
                for cx in (mn[0], mx[0]):
                    for cy in (mn[1], mx[1]):
                        for cz in (mn[2], mx[2]):
                            w = world @ Vector((cx, cy, cz))
                            for k in range(3):
                                lo[k] = min(lo[k], w[k])
                                hi[k] = max(hi[k], w[k])
        for c in nd.get("children", []):
            walk(c, world)

    for r in roots:
        walk(r, Matrix.Identity(4))
    return lo, hi


def scene_bounds_yup(objs):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            y = Vector((w.x, w.z, -w.y))
            for k in range(3):
                lo[k] = min(lo[k], y[k])
                hi[k] = max(hi[k], y[k])
    return lo, hi


def on_metre(v):
    return abs(v - round(v)) < 0.01


# ---------------------------------------------------------------- import file


def write_scene_import(glb_path):
    """Make Godot run the toon post-import binder on this .glb."""
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


# ---------------------------------------------------------------- main


def convert(stem, spec):
    pack, category, fbx, idle_fbx, prefab = spec
    root = TP if pack == "TP" else TCP
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(root, "Models", fbx))
    bpy.context.view_layer.update()
    objs = list(bpy.context.scene.objects)
    reflected = sorted(o.name for o in objs if o.matrix_world.determinant() < 0)
    if idle_fbx is None:
        for o in objs:
            if o.animation_data:
                o.animation_data_clear()
        for a in list(bpy.data.actions):
            bpy.data.actions.remove(a)
    rebind_materials(pack, objs)
    if idle_fbx is not None:
        objs = build_character(stem, idle_fbx, prefab)
        objs = list(bpy.context.scene.objects)
    bpy.context.view_layer.update()

    mats = sorted({s.material.name for o in objs if o.type == "MESH" for s in o.material_slots})
    imgs = sorted(i.name for i in bpy.data.images if i.users > 0)
    verts = sum(len(o.data.vertices) for o in objs if o.type == "MESH")
    s_lo, s_hi = scene_bounds_yup(objs)

    out_dir = os.path.join(ASSETS, category)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, stem + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    animated = idle_fbx is not None
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
        export_skins=animated,
        export_animations=animated,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_reset_pose_bones=True,
    )

    # Verify against the WRITTEN FILE, never the scene.
    js, nbytes = parse_glb(out)
    f_mats = sorted(m["name"] for m in js.get("materials", []))
    f_imgs = len(js.get("images", []))
    f_anims = [a["name"] for a in js.get("animations", [])]
    f_lo, f_hi = glb_bounds(js)
    size = f_hi - f_lo
    log(
        "ASSET %s file=%s bytes=%d verts=%d nodes=%d meshes=%d skins=%d materials=%s images=%d "
        "animations=%s reflected_parts=%d"
        % (
            stem,
            os.path.relpath(out, REPO).replace("\\", "/"),
            nbytes,
            verts,
            len(js.get("nodes", [])),
            len(js.get("meshes", [])),
            len(js.get("skins", [])),
            f_mats,
            f_imgs,
            f_anims,
            len(reflected),
        )
    )
    log(
        "BOUNDS %s size_xyz_m=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f) "
        "footprint_on_1m_grid=%s"
        % (
            stem,
            size.x,
            size.y,
            size.z,
            f_lo.x,
            f_lo.y,
            f_lo.z,
            f_hi.x,
            f_hi.y,
            f_hi.z,
            all(on_metre(v) for v in (size.x, size.z, f_lo.x, f_lo.z)),
        )
    )
    if f_mats != mats:
        die("%s: file materials %s differ from scene %s" % (stem, f_mats, mats))
    if f_imgs < 1 or f_imgs != len(imgs):
        die("%s: file images %d, scene images %s" % (stem, f_imgs, imgs))
    if animated and f_anims != ["idle"]:
        die("%s: expected exactly one animation 'idle', file has %s" % (stem, f_anims))
    if not animated and f_anims:
        die("%s: a prop carries animations %s" % (stem, f_anims))
    if not animated:
        for k in range(3):
            if abs(f_lo[k] - s_lo[k]) > BOUNDS_TOLERANCE or abs(f_hi[k] - s_hi[k]) > BOUNDS_TOLERANCE:
                die("%s: file bounds %s..%s differ from scene %s..%s" % (stem, f_lo, f_hi, s_lo, s_hi))
    write_scene_import(out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    stems = argv or list(BATCH)
    unknown = [s for s in stems if s not in BATCH]
    if unknown:
        die("unknown stems %s" % unknown)
    convert_textures()
    for stem in stems:
        convert(stem, BATCH[stem])
    log("DONE %d assets" % len(stems))


main()
