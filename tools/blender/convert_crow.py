"""Convert the Toon Farm Pack crow (TFP_Crow_01.fbx, rigged, ten takes) to
game/assets/birds/tfp_crow_01.glb for the ambient bird flock.

Run from WSL (Blender is a Windows program, so every path it sees is a Windows path):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\convert_crow.py'

Optional after `--`: `--out <dir>` writes the .glb there instead of game/assets/birds/
(the atlas PNGs in game/ are then read, not rewritten, and no .import file is written).
Then run a Godot `--headless --import`, which binds the toon material through
game/assets/birds/bird_post_import.gd.

Kept apart from convert_toon_batch.py: that script's character path retargets a pose
FBX onto a TCP body and adds generated clips; the crow brings its own ten takes on its
own rig, and every take is exported as it is, only renamed.

What it does:
1. Converts TFP_Atlas_1A.psd and the pack's ramp TFP_Toon_Ramp_1F.psd (the ramp that
   Models/Materials/TFP_Atlas_1A.mat names as _TextureRamp) to PNG under
   game/assets/birds/.
2. Imports the FBX (UnitScaleFactor 100, so metres). It holds one armature and three
   skinned meshes, TFP_Crow_01A/B/C, the colour variants of the Unity prefabs
   Prefabs/Animals/Crows/TFP_Crow_01A/B/C. All three are kept; the flock shows one.
3. Rebinds the palette atlas: the FBX material TFP_Atlas_1A becomes TFP_Atlas_1A_D, a
   Principled material on the converted atlas. Only the first UV layer is kept (Unity
   uv0); the second (an unused lightmap channel) is dropped so the file has one
   TEXCOORD per primitive.
4. Renames the takes to short clip names (CLIPS) and prints, per clip, the lowest
   vertex at its first and last frame and the Root bone's travel (CONTACT lines): the
   flock reads these to put the feet on the perch. The armature's 90 degree X rotation
   stays a node in the file (see main()).
5. Exports .glb, RE-READS THE WRITTEN FILE and checks clips (names, durations, motion),
   materials, images, meshes, skins, texcoords and bounds. Any mismatch stops the run.
"""

import json
import os
import struct
import sys

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.dont_write_bytecode = True
GAME = os.path.join(REPO, "game")
OUT_DIR = os.path.join(GAME, "assets", "birds")
FARM = "C:\\Users\\chulf\\Assets new\\Toon Series\\Toon Farm Pack"
FBX = os.path.join(FARM, "Models", "TFP_Crow_01.fbx")
STEM = "tfp_crow_01"
POST_IMPORT = "res://assets/birds/bird_post_import.gd"
FPS = 30
# Vendor PSD -> (PNG under game/assets/birds/, mipmaps).
TEXTURES = {
    os.path.join(FARM, "Textures", "TFP_Atlas_1A.psd"): ("tfp_atlas_1a_d.png", True),
    os.path.join(FARM, "Textures", "TFP_Toon_Ramp_1F.psd"): ("tfp_toon_ramp_1f.png", False),
}
VENDOR_MATERIAL = "TFP_Atlas_1A"
MATERIAL = "TFP_Atlas_1A_D"
ATLAS_PNG = "tfp_atlas_1a_d.png"
VARIANTS = ("TFP_Crow_01A", "TFP_Crow_01B", "TFP_Crow_01C")
ARMATURE = "RIG_Crow_01"
# FBX take (after the "RIG_Crow_01|" prefix) -> clip name in the .glb.
CLIPS = {
    "RIG_TFP_Crow_01_Idle_01": "idle_01",
    "RIG_TFP_Crow_01_Idle_02": "idle_02",
    "RIG_TFP_Crow_01_Idle_03": "idle_03",
    "RIG_TFP_Crow_01_Walk": "walk",
    "RIG_TFP_Crow_01_Hop": "hop",
    "RIG_TFP_Crow_01_Takeoff": "takeoff",
    "RIG_TFP_Crow_01_Fly": "fly",
    "RIG_TFP_Crow_01_Soar": "soar",
    "RIG_TFP_Crow_01_Land": "land",
    "RIG_TFP_Crow_Eat": "eat",
}
BOUNDS_TOLERANCE = 0.02


def log(*a):
    print("CROW", *a, flush=True)


def die(msg):
    print("CROW_FAIL", msg, flush=True)
    sys.exit(1)


def convert_textures():
    os.makedirs(OUT_DIR, exist_ok=True)
    for src, (png, mipmaps) in TEXTURES.items():
        img = bpy.data.images.load(src)
        if img.size[0] == 0 or img.size[1] == 0:
            die("PSD did not decode: %s" % src)
        dst = os.path.join(OUT_DIR, png)
        img.filepath_raw = dst
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)
        check = bpy.data.images.load(dst)
        log("TEXTURE %s size=%s channels=%d" % (png, tuple(check.size), check.channels))
        if tuple(check.size) == (0, 0):
            die("written PNG unreadable: %s" % dst)
        bpy.data.images.remove(check)
        imp = dst + ".import"
        if not os.path.exists(imp):
            with open(imp, "w", newline="\n") as f:
                f.write(
                    '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                    "compress/mode=0\nmipmaps/generate=%s\ndetect_3d/compress_to=0\n"
                    % ("true" if mipmaps else "false")
                )


def rebind(meshes):
    mat = bpy.data.materials.new(MATERIAL)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(OUT_DIR, ATLAS_PNG), check_existing=True)
    if tex.image.size[0] == 0:
        die("atlas image did not load: %s" % ATLAS_PNG)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    for o in meshes:
        if len(o.material_slots) != 1 or o.material_slots[0].material is None:
            die("%s: expected one material slot, has %d" % (o.name, len(o.material_slots)))
        name = o.material_slots[0].material.name
        if name != VENDOR_MATERIAL:
            die("%s: unmapped material %s" % (o.name, name))
        o.material_slots[0].material = mat
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)


def uv_report(meshes):
    """Drop every UV layer but the first; print how the variants differ in it (the colour
    variants share geometry and differ only in where their faces sample the atlas)."""
    for o in meshes:
        layers = [u.name for u in o.data.uv_layers]
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])
        o.data.uv_layers[0].active = True
        o.data.uv_layers[0].active_render = True
        log("UV %s layers_in=%s kept=%s" % (o.name, layers, o.data.uv_layers[0].name))
    base = meshes[0]
    for o in meshes[1:]:
        if len(o.data.loops) != len(base.data.loops):
            die("%s: loop count %d differs from %s" % (o.name, len(o.data.loops), base.name))
        a = base.data.uv_layers[0].data
        b = o.data.uv_layers[0].data
        moved = sum(1 for i in range(len(a)) if (a[i].uv - b[i].uv).length > 1e-4)
        geo = max((base.data.vertices[i].co - o.data.vertices[i].co).length for i in range(len(o.data.vertices)))
        log("VARIANT %s vs %s uv_loops_moved=%d of %d max_vertex_dev_m=%.6f" % (o.name, base.name, moved, len(a), geo))


def set_action(arm, action):
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and action.slots:
        arm.animation_data.action_slot = action.slots[0]


def clip_contacts(arm, meshes, actions):
    """Per clip: the lowest evaluated vertex (world Z) at its first and last frame and over
    all frames, the Root bone's travel, and the duration. Only the A mesh is measured; B
    and C share its geometry."""
    deps = bpy.context.evaluated_depsgraph_get()
    body = meshes[0]
    durations = {}
    for act in actions:
        set_action(arm, act)
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        lows = []
        root = []
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            deps.update()
            ev = body.evaluated_get(deps)
            me = ev.to_mesh()
            lows.append(min((ev.matrix_world @ v.co).z for v in me.vertices))
            ev.to_mesh_clear()
            root.append(arm.matrix_world @ arm.pose.bones["Root"].head)
        travel = root[-1] - root[0]
        rise = max(r.z for r in root) - min(r.z for r in root)
        durations[act.name] = (f1 - f0) / FPS
        log(
            "CONTACT %s frames=%d..%d duration_s=%.4f low_first=%.3f low_last=%.3f low_min=%.3f low_max=%.3f "
            "root_travel=(%.3f, %.3f, %.3f) root_rise=%.3f"
            % (act.name, f0, f1, durations[act.name], lows[0], lows[-1], min(lows), max(lows), travel.x, travel.y, travel.z, rise)
        )
    return durations


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a GLB: %s" % path)
    jlen, _jtype = struct.unpack_from("<II", data, 12)
    return json.loads(data[20 : 20 + jlen]), data


def accessor(js, data, index):
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    if acc["componentType"] != 5126:
        die("accessor %d is not float" % index)
    bin_start = 20 + struct.unpack_from("<I", data, 12)[0] + 8
    start = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 4 * width)
    return [struct.unpack_from("<%df" % width, data, start + i * stride) for i in range(acc["count"])]


def check_file(path, durations, scene_size):
    js, data = parse_glb(path)
    mats = [m["name"] for m in js.get("materials", [])]
    imgs = len(js.get("images", []))
    meshes = [m["name"] for m in js.get("meshes", [])]
    skins = len(js.get("skins", []))
    anims = [a["name"] for a in js.get("animations", [])]
    nodes = [n.get("name") for n in js.get("nodes", [])]
    texcoords = sorted({k for m in js.get("meshes", []) for p in m["primitives"] for k in p["attributes"] if k.startswith("TEXCOORD")})
    colours = sorted({k for m in js.get("meshes", []) for p in m["primitives"] for k in p["attributes"] if k.startswith("COLOR")})
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for m in js["meshes"]:
        for p in m["primitives"]:
            acc = js["accessors"][p["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    size = [h - l for h, l in zip(hi, lo)]
    log(
        "FILE %s bytes=%d materials=%s images=%d meshes=%s skins=%d nodes=%d texcoords=%s colours=%s"
        % (os.path.relpath(path, REPO).replace("\\", "/"), len(data), mats, imgs, meshes, skins, len(nodes), texcoords, colours)
    )
    log("FILE_BOUNDS size_xyz_m=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % tuple(size + lo + hi))
    log("FILE_CLIPS %s" % sorted(anims))
    if mats != [MATERIAL]:
        die("file materials %s, expected [%s]" % (mats, MATERIAL))
    if imgs != 1:
        die("file images %d, expected 1 (the atlas)" % imgs)
    if sorted(meshes) != sorted(VARIANTS):
        die("file meshes %s, expected %s" % (meshes, VARIANTS))
    if skins < 1:
        die("file has no skin")
    if texcoords != ["TEXCOORD_0"] or colours:
        die("file texcoords %s colours %s, expected TEXCOORD_0 only" % (texcoords, colours))
    if sorted(anims) != sorted(CLIPS.values()):
        die("file clips %s, expected %s" % (sorted(anims), sorted(CLIPS.values())))
    if any(abs(a - b) > BOUNDS_TOLERANCE for a, b in zip(size, scene_size)):
        die("file size %s differs from scene rest size %s" % (size, scene_size))
    for a in js["animations"]:
        start = min(js["accessors"][s["input"]]["min"][0] for s in a["samplers"])
        end = max(js["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        motion = 0.0
        for s in a["samplers"]:
            vals = accessor(js, data, s["output"])
            for c in range(len(vals[0])):
                col = [v[c] for v in vals]
                motion = max(motion, max(col) - min(col))
        want = durations[a["name"]]
        log("CLIP %s duration_s=%.4f expected_s=%.4f channels=%d max_channel_range=%.4f" % (a["name"], end - start, want, len(a["channels"]), motion))
        if abs(start) > 1e-4 or abs((end - start) - want) > 0.5 / FPS:
            die("clip %s spans %.4f..%.4f s, expected 0..%.4f" % (a["name"], start, end, want))
        if motion < 1e-3:
            die("clip %s carries no motion" % a["name"])


def write_scene_import(glb_path):
    path = glb_path + ".import"
    if os.path.exists(path):
        log("IMPORT_FILE kept %s" % os.path.basename(path))
        return
    with open(path, "w", newline="\n") as f:
        f.write(
            '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
            'import_script/path="%s"\ngltf/embedded_image_handling=0\nanimation/fps=%d\n' % (POST_IMPORT, FPS)
        )


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out_dir = OUT_DIR
    if "--out" in argv:
        out_dir = argv[argv.index("--out") + 1]
        if os.path.normcase(os.path.realpath(out_dir)).startswith(os.path.normcase(os.path.realpath(GAME))):
            die("--out must be outside game/")
    if out_dir == OUT_DIR:
        convert_textures()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.fbx(filepath=FBX)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    objs = list(bpy.context.scene.objects)
    arm = bpy.data.objects.get(ARMATURE)
    meshes = [bpy.data.objects.get(n) for n in VARIANTS]
    if arm is None or any(m is None for m in meshes):
        die("expected %s and %s, found %s" % (ARMATURE, VARIANTS, [o.name for o in objs]))
    extra = [o.name for o in objs if o != arm and o not in meshes]
    for o in objs:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    if [n for n in extra if bpy.data.objects.get(n) is not None]:
        die("unexpected objects %s" % extra)
    for m in meshes:
        mods = [x for x in m.modifiers if x.type == "ARMATURE"]
        if m.parent != arm or not mods or mods[0].object != arm:
            die("%s is not skinned to %s" % (m.name, ARMATURE))
    for m in meshes:
        m.data.name = m.name  # glTF mesh names come from the mesh data (vendor "Plane.024")
    rebind(meshes)
    uv_report(meshes)

    actions = []
    for act in list(bpy.data.actions):
        take = act.name.split("|")[-1]
        if take not in CLIPS:
            die("unknown take %s" % act.name)
        act.name = CLIPS[take]
        act.use_fake_user = True
        actions.append(act)
    if sorted(a.name for a in actions) != sorted(CLIPS.values()):
        die("takes %s, expected %s" % (sorted(a.name for a in actions), sorted(CLIPS.values())))
    actions.sort(key=lambda a: a.name)

    # The armature keeps its 90 degree X rotation: applying it moved sampled bones by up
    # to 1.05 m on the vendor takes (their bone-local keys do not survive the re-rolled
    # rest), so the rotated RIG_Crow_01 node stays above the Skeleton3D in the file.
    log("ARMATURE %s rotation_euler=%s kept" % (arm.name, tuple(round(v, 4) for v in arm.rotation_euler)))

    durations = clip_contacts(arm, meshes, actions)
    idle = next(a for a in actions if a.name == "idle_01")
    set_action(arm, idle)
    bpy.context.scene.frame_set(int(idle.frame_range[0]))

    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for m in meshes:
        for v in m.data.vertices:
            w = m.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    rest = hi - lo
    # Blender Z-up -> glTF Y-up: (x, y, z) -> (x, z, y) in extent.
    scene_size = [rest.x, rest.z, rest.y]
    log("REST size_m length_y=%.3f width_x=%.3f height_z=%.3f min_z=%.4f" % (rest.y, rest.x, rest.z, lo.z))
    log("SCENE materials=%s images=%s" % (sorted(m.name for m in bpy.data.materials), sorted(i.name for i in bpy.data.images)))

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, STEM + ".glb")
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
        export_morph=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        # The takes start on frame 1; without the slide every clip starts 1/30 s late.
        export_anim_slide_to_zero=True,
        export_reset_pose_bones=True,
    )
    check_file(out, durations, scene_size)
    if out_dir == OUT_DIR:
        write_scene_import(out)
    log("DONE %s" % out)


main()
