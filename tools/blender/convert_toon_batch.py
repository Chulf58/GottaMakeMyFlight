"""Convert a batch of Toon Series FBX models (Unity-only packs) to .glb in game/assets/.

Run from WSL (Blender is a Windows program, so every path it sees is a Windows path):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\convert_toon_batch.py'

Optional after `--`: asset stems to convert (default: the whole BATCH table), and
`--out <dir>` to write the .glb files there for a trial run that leaves game/ unchanged.
Then run a Godot `--headless --import`, which binds the toon materials through
game/assets/toon_post_import.gd.

What it does, per asset:
1. Factory-empty scene, import the vendor FBX. Blender's FBX importer applies the
   file's UnitScaleFactor (100 in every file of both packs), so the result is in metres.
2. Rebind the palette atlas. Each FBX material is resolved by (pack, material name) to
   one of five pack-qualified materials, rebuilt as Principled with the atlas PNG that
   this script converts from the vendor PSD. An unknown material name stops the run.
   A stem listed in VENDOR_EDITS then gets its geometry edit (tc_parking_2a: a level
   way from the entrance to the ground-floor stalls).
3. Characters: keep only the parts the Unity source prefab enables, drop shape keys,
   join the parts into one skinned mesh, retarget the idle action from the idle FBX onto
   the character armature as "idle", then add walk, run, sit_down, sit_idle and stand_up
   (tools/blender/anim/toon_clips.py; it prints SPEED and SIT_CONTRACT lines).
   Before the join each part's vertices get the clothes' mark (CLOTH_ATTR, exported as
   COLOR_0) that PassengerLooks tints by. Then move the vendor UV faults listed in UV_FIXES
   to their target swatch, and stop if any face still samples the vendor magenta ramp.
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

# The checkout this script sits in (tools/blender/ under it), so a run from a worktree
# reads and writes that worktree, never the main checkout.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(REPO, "tools", "blender", "anim"))
sys.path.insert(0, os.path.join(REPO, "tools", "blender", "landside"))
import curb_bay  # noqa: E402
import parking_2a_entrance  # noqa: E402
import toon_clips  # noqa: E402
GAME = os.path.join(REPO, "game")
ASSETS = os.path.join(GAME, "assets")
TEX_DIR = os.path.join(ASSETS, "textures")
SRC = "C:\\Users\\chulf\\Assets new\\Toon Series"
TP = os.path.join(SRC, "Toon Planes Pack")
TCP = os.path.join(SRC, "Toon City People")
TC = os.path.join(SRC, "Toon City")
PACK_ROOTS = {"TP": TP, "TCP": TCP, "TC": TC}
POST_IMPORT = "res://assets/toon_post_import.gd"
# A BATCH "fbx" starting with this is built by a script instead of imported. Its empties
# (MARKERS) are mount points, checked by name and transform in the written file.
AUTHORED = "authored:"
AUTHORED_BUILDERS = {"curb_bay": curb_bay}
MARKERS = {"tp_curb_bay_01a": curb_bay.MARKERS}
MARKER_PARENT = {"tp_curb_bay_01a": curb_bay.MESH_NAME}
# Vendor models edited after the import and atlas rebind, before the part checks and the
# export: stem -> module with edit(objs) and Fail. tc_parking_2a gets a level way from its
# entrance to the ground-floor stalls (tools/blender/landside/parking_2a_entrance.py).
VENDOR_EDITS = {"tc_parking_2a": parking_2a_entrance}

# Vendor PSD -> PNG under game/assets/textures/. (png name, mipmaps)
TEXTURES = {
    os.path.join(TP, "Textures", "TP_Atlas_1A_D.psd"): ("tp_atlas_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Atlas_Lights_1A_D.psd"): ("tp_atlas_lights_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Glass_Gradient_1A_D.psd"): ("tp_glass_gradient_1a_d.png", True),
    os.path.join(TP, "Textures", "TP_Toon_Ramp_1D_D.psd"): ("tp_toon_ramp_1d_d.png", False),
    os.path.join(TCP, "Textures", "Atlas_1A_D 1.psd"): ("tcp_atlas_1a_d.png", True),
    os.path.join(TCP, "Textures", "TCP_Toon_Ramp_01D_D.psd"): ("tcp_toon_ramp_01d_d.png", False),
    # Toon City: one 128x128 albedo per material, and one shared 3-step ramp (128x4, all
    # four rows the same: 0, 0.494, 1.0) that every Toon City .mat names as _TextureRamp.
    os.path.join(TC, "Textures", "Road_1A_D.psd"): ("tc_road_1a_d.png", True),
    os.path.join(TC, "Textures", "Tree_1A_D.psd"): ("tc_tree_1a_d.png", True),
    os.path.join(TC, "Textures", "Tree_3A_D.psd"): ("tc_tree_3a_d.png", True),
    os.path.join(TC, "Textures", "Props_2A_D.psd"): ("tc_props_2a_d.png", True),
    os.path.join(TC, "Textures", "Building_4A_D.psd"): ("tc_building_4a_d.png", True),
    os.path.join(TC, "Textures", "Building_17A_D.psd"): ("tc_building_17a_d.png", True),
    os.path.join(TC, "Textures", "TC_Toon_Ramp_01A_D.psd"): ("tc_toon_ramp_01a_d.png", False),
}

# (pack, FBX material name) -> (glTF material name, kind, png). The pairs come from the
# Unity .fbx.meta externalObjects remaps; both packs name their atlas "Atlas_1A_D".
MATERIALS = {
    ("TP", "Atlas_1A_D"): ("TP_Atlas_1A_D", "opaque", "tp_atlas_1a_d.png"),
    ("TP", "Atlas_Simple_1A_D"): ("TP_Atlas_Simple_1A_D", "opaque", "tp_atlas_1a_d.png"),
    ("TP", "Atlas_Lights_1A_D"): ("TP_Atlas_Lights_1A_D", "emissive", "tp_atlas_lights_1a_d.png"),
    ("TP", "Glass_Vehicles_01A_D"): ("TP_Glass_1A_D", "glass", "tp_glass_gradient_1a_d.png"),
    ("TCP", "Atlas_1A_D"): ("TCP_Atlas_1A_D", "opaque", "tcp_atlas_1a_d.png"),
    # Toon City has no remaps; its prefabs name Road_2A_D.mat, identical to Road_1A_D.
    ("TC", "Road_1A_D"): ("TC_Road_1A_D", "opaque", "tc_road_1a_d.png"),
    ("TC", "Tree_1A_D"): ("TC_Tree_1A_D", "opaque", "tc_tree_1a_d.png"),
    ("TC", "Tree_3A_D"): ("TC_Tree_3A_D", "opaque", "tc_tree_3a_d.png"),
    ("TC", "Props_2A_D"): ("TC_Props_2A_D", "opaque", "tc_props_2a_d.png"),
    ("TC", "Building_4A_D"): ("TC_Building_4A_D", "opaque", "tc_building_4a_d.png"),
    ("TC", "Building_17A_D"): ("TC_Building_17A_D", "opaque", "tc_building_17a_d.png"),
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
    # Decor (decision furniture-set-modelled-on-copenhagen-airport-decor-calms-pas) and
    # the prize car. Vendor scale, except the _indoor stems (see INDOOR).
    "tc_plant_pot_1a": ("TC", "decor", "Plant_Pot_1A.fbx", None, None),
    "tc_plant_pot_2a": ("TC", "decor", "Plant_Pot_2A.fbx", None, None),
    "tc_bush_1a": ("TC", "decor", "Bush_1A.fbx", None, None),
    "tc_bench_1a": ("TC", "decor", "Bench_1A.fbx", None, None),
    "tc_trash_can_1a": ("TC", "decor", "Trash_Can_1A.fbx", None, None),
    "tc_metal_pole_1a": ("TC", "decor", "Metal_Pole_1A.fbx", None, None),
    "tc_metal_pole_chain_1a": ("TC", "decor", "Metal_Pole_Chain_1A.fbx", None, None),
    "tc_tree_3a_indoor": ("TC", "decor", "Tree_3A.fbx", None, None),
    "tc_fountain_1a_indoor": ("TC", "decor", "Fountain_1A.fbx", None, None),
    "tc_statue_1b_indoor": ("TC", "decor", "Statue_1B.fbx", None, None),
    "tc_bench_2a_indoor": ("TC", "decor", "Bench_2A.fbx", None, None),
    "tp_suv_01a": ("TP", "vehicles", "TP_SUV_01A.fbx", None, None),
    # Landside traffic (decision landside-technical-design-arrival-bookings-landsidesim-vehic):
    # taxis, private cars and a van, at vendor scale.
    "tp_taxi_01a": ("TP", "vehicles", "TP_Taxi_01A.fbx", None, None),
    "tp_taxi_01b": ("TP", "vehicles", "TP_Taxi_01B.fbx", None, None),
    "tp_taxi_01c": ("TP", "vehicles", "TP_Taxi_01C.fbx", None, None),
    "tp_suv_01b": ("TP", "vehicles", "TP_SUV_01B.fbx", None, None),
    "tp_suv_01c": ("TP", "vehicles", "TP_SUV_01C.fbx", None, None),
    "tp_van_01a": ("TP", "vehicles", "TP_Van_01A.fbx", None, None),
    # Landside parking (decision landside-parking-kinds-a-cheap-surface-lot-and-an-expensive):
    # the cheap surface lot (Toon Planes, same atlas as the terminal and road; entry and
    # exit barrier arms stay separate nodes on their hinge) and the multi-storey car park.
    # The kerb drop-off bay is authored (tools/blender/landside/curb_bay.py), not an FBX.
    "tp_parking_01a": ("TP", "landside", "TP_Parking_01A.fbx", None, None),
    "tc_parking_2a": ("TC", "landside", "Parking_2A.fbx", None, None),
    "tp_curb_bay_01a": ("TP", "landside", AUTHORED + "curb_bay", None, None),
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
    # Staff (StaffCharacters): the navy skirt suit reads as a check-in agent, the white
    # shirt, tie and dark trousers as a security officer.
    "tcp_female_character_07": (
        "TCP",
        "people",
        "TCP_Female_Character_07.fbx",
        "Poses\\TCP_Female_Idle_01.fbx",
        "Prefabs\\Female Character Sources\\TCP_Female_Character_07.prefab",
    ),
    "tcp_male_character_07": (
        "TCP",
        "people",
        "TCP_Male_Character_07.fbx",
        "Poses\\TCP_Male_Idle_01.fbx",
        "Prefabs\\Male Character Sources\\TCP_Male_Character_07.prefab",
    ),
}
# Passenger bodies beyond 01 (decision comic-life-and-variety-visuals-first-passengers-get-10-more):
# PassengerViews draws a passenger with one of the six bodies of its gender.
PASSENGER_BODIES = {"male": ("02", "03", "06", "08", "09"), "female": ("03", "04", "05", "08", "11")}
for _gender, _numbers in PASSENGER_BODIES.items():
    _g = _gender.capitalize()
    for _n in _numbers:
        BATCH["tcp_%s_character_%s" % (_gender, _n)] = (
            "TCP",
            "people",
            "TCP_%s_Character_%s.fbx" % (_g, _n),
            "Poses\\TCP_%s_Idle_01.fbx" % _g,
            "Prefabs\\%s Character Sources\\TCP_%s_Character_%s.prefab" % (_g, _g, _n),
        )

# Clothing tints. A character's parts whose names hold one of these words are its clothes;
# every other part (skin, head, hair, beard, shoes, legs, jewellery, glasses, bags) keeps the
# vendor colours. The clothes' vertices carry a white CLOTH_ATTR colour (COLOR_0 in the
# .glb), every other vertex black; PassengerLooks moves the clothes onto a tinted atlas.
CLOTH_WORDS = ("Jacket", "Pants", "Shirt", "Skirt", "Dress", "Tie")
CLOTH_ATTR = "Cloth"
# The vendor's magenta ramp (RGB about 225,0,181). A character face whose UV centre samples
# it after the UV fixes stops the run (see UV_FIXES).
MAGENTA = (225, 0, 181)
MAGENTA_TOLERANCE = 24

# Vendor UV faults repaired per asset, after the part join and before export:
# (u0, v0, u1, v1) box the face's UV centroid falls in, the UV every loop of those faces
# moves to, and the face count the vendor file has there. TCP_Male_Shoes_01A maps four
# heel-back quads into a magenta ramp of the shared atlas (RGB about 225,0,181); they move
# to the tan heel band around them (user-ruled "Tan, blend in"): the band swatch is a
# vertical gradient, flat across u 0.625-0.656, and v 0.155 is the shade (157,147,124) the
# band faces beside the patch sample. The atlas itself is shared and stays as it is. A different count stops the run, so a changed vendor file is seen, and the
# written file is re-read for faces left in the box.
UV_FIXES = {
    "tcp_male_character_01": [((0.354, 0.217, 0.360, 0.224), (0.637, 0.155), 4)],
}

# Indoor variants (decision oversized-toon-decor-trees-fountain-statue-tree-bench-is-bui):
# the vendor props are 6.8-10.8 m tall and interior walls are 2.5 m, so they are built
# smaller here and the game never rescales them. Every root object scales by one factor
# about the asset origin, so the parts keep their spacing.
#   "top": the factor puts the highest faced vertex at this height (m).
#   "seat": (part, z0, z1, height): the up-facing faces of that part whose centre lies in
#       z0..z1 at vendor scale are the seat; the factor puts them at this height.
#   "parts": part -> {"top": m}: after the asset factor, that part scales again about
#       its trunk base (its own origin in plan, its lowest vertex in height) so its top
#       lands at this height.
INDOOR = {
    # Conifer in a round stone planter; 2.2 m stays under a 2.5 m wall with room.
    "tc_tree_3a_indoor": {"top": 2.2},
    # Basin, two tiers and a ball (the faced top is about 3.8 m at vendor scale).
    "tc_fountain_1a_indoor": {"top": 1.8},
    # Pedestal and robed figure; 2.4 m keeps the figure about 1.45 m tall.
    "tc_statue_1b_indoor": {"top": 2.4},
    # Round tree bench: the seat ledge (vendor 0.70 m) lands on the 0.53 m seat height of
    # the sit clips, so people can sit on it; the tree alone shrinks to fit under 2.5 m.
    "tc_bench_2a_indoor": {"seat": ("Bench_2A", 0.65, 0.75, 0.53), "parts": {"Bench_2A_Tree": {"top": 2.4}}},
}
INDOOR_CEILING = 2.5
# Reshape before the indoor factor, in vendor metres (user ruling 2026-10-29 through the
# question form, "Reshape in Blender (Recommended)": shrink the four lamp heads and the
# planter so the tree reads as the centre again, seat at 0.53 m, all under 2.5 m).
#   step: top of the seat step; nothing at or below it moves, so the seat stays put.
#   soil, rim: soil level and planter rim; the planter above the step keeps "planter" of
#       its height. Grass blades (islands standing on the soil above the rim) drop with it.
#   lamp: each lamp (one per quadrant) scales by this about the foot of its post.
RESHAPE = {
    "tc_bench_2a_indoor": {
        "base": "Bench_2A",
        "lights": "Bench_2A_Lights",
        "tree": "Bench_2A_Tree",
        "step": 0.85,
        "soil": 1.5,
        "rim": 1.73,
        "planter": 0.5,
        "lamp": 0.5,
        # The vendor file as measured: a changed file stops the run instead of reshaping wrongly.
        "lamp_islands": 19,
        "grass_islands": 62,
    },
}
# Lowest point of each decor prop, in metres above its origin. Everything else stands on
# 0; Bush_1A's root ball is buried 0.30 m (vendor), the chain hangs between posts.
GROUND = {
    "tc_bush_1a": -0.30,
    "tc_metal_pole_chain_1a": 0.74,
    # Road paint lifted off the road it lies on (curb_bay.LIFT), so it never z-fights.
    "tp_curb_bay_01a": 0.02,
}
GROUND_CATEGORIES = ("decor", "vehicles", "landside")
GROUND_TOLERANCE = 0.01
# Part checks: positions (bounds and origins) in metres, rotation matrix entries unitless.
POSITION_TOLERANCE = 1e-3
ROTATION_TOLERANCE = 1e-4

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
    looks = mark_cloth(stem, keep)
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
    # Walk, run and the sit clips go on after the rotation is applied, so the clip
    # module works in armature space == world space (tools/blender/anim/toon_clips.py).
    try:
        durations = toon_clips.add_clips(stem, arm, action)
    except toon_clips.Fail as e:
        die(str(e))
    bpy.context.scene.frame_start = f0
    bpy.context.scene.frame_end = f1
    bpy.context.scene.frame_set(f0)
    return [arm, body], durations, looks


def atlas_image(stem, meshes):
    """The one atlas image bound to a character's parts."""
    imgs = {
        n.image for o in meshes for s in o.material_slots for n in s.material.node_tree.nodes if n.type == "TEX_IMAGE"
    }
    if len(imgs) != 1:
        die("%s: expected one atlas image, found %d" % (stem, len(imgs)))
    return imgs.pop()


def mark_cloth(stem, parts):
    """Give every part a CLOTH_ATTR point colour, white on clothes (see CLOTH_WORDS) and
    black elsewhere, before the parts are joined. Returns the clothes' triangle count."""
    named = {}
    cloth_tris = 0
    for o in parts:
        kind = "cloth" if any(word in base_name(o.name) for word in CLOTH_WORDS) else "other"
        named[base_name(o.name)] = kind
        for attr in list(o.data.color_attributes):
            o.data.color_attributes.remove(attr)
        attr = o.data.color_attributes.new(CLOTH_ATTR, "BYTE_COLOR", "POINT")
        value = (1.0, 1.0, 1.0, 1.0) if kind == "cloth" else (0.0, 0.0, 0.0, 1.0)
        for item in attr.data:
            item.color = value
        o.data.color_attributes.active_color = attr
        if kind == "cloth":
            cloth_tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    log("CLOTH %s cloth_triangles=%d parts=%s" % (stem, cloth_tris, sorted(named.items())))
    if not cloth_tris:
        die("%s: no part is clothing (CLOTH_WORDS)" % stem)
    return cloth_tris


def magenta_faces(stem, objs):
    """Count a character's faces whose UV centre samples the vendor's magenta ramp, after
    the UV fixes, from the bound material's atlas image; any stops the run."""
    meshes = [o for o in objs if o.type == "MESH"]
    img = atlas_image(stem, meshes)
    w, h = img.size
    px = img.pixels[:]
    hits = 0
    for o in meshes:
        uv = o.data.uv_layers[0].data
        for p in o.data.polygons:
            lis = list(p.loop_indices)
            x = min(max(int(sum(uv[li].uv.x for li in lis) / len(lis) * w), 0), w - 1)
            y = min(max(int(sum(uv[li].uv.y for li in lis) / len(lis) * h), 0), h - 1)
            i = (y * w + x) * 4
            rgb = [round(c * 255) for c in px[i : i + 3]]
            if all(abs(a - b) <= MAGENTA_TOLERANCE for a, b in zip(rgb, MAGENTA)):
                hits += 1
    log("MAGENTA %s faces=%d" % (stem, hits))
    if hits:
        die("%s: %d faces sample the vendor magenta ramp; add a UV_FIXES entry" % (stem, hits))


def in_box(box, u, v):
    return box[0] <= u <= box[2] and box[1] <= v <= box[3]


def fix_uvs(stem, objs):
    """Move the UV_FIXES faces of this asset to their target UV (see UV_FIXES). Returns,
    per fix, how many triangles the moved faces make, for the check on the written file."""
    fixes = UV_FIXES.get(stem, [])
    tris = []
    if not fixes:
        return tris
    meshes = [o for o in objs if o.type == "MESH"]
    for box, target, expected in fixes:
        hits = []
        for o in meshes:
            if len(o.data.uv_layers) != 1:
                die("%s: %s has %d UV maps, the UV fix expects one" % (stem, o.name, len(o.data.uv_layers)))
            uv = o.data.uv_layers[0].data
            for p in o.data.polygons:
                lis = list(p.loop_indices)
                cu = sum(uv[li].uv.x for li in lis) / len(lis)
                cv = sum(uv[li].uv.y for li in lis) / len(lis)
                if in_box(box, cu, cv):
                    hits.append((o, lis))
        if len(hits) != expected:
            die("%s: %d faces in UV box %s, expected %d" % (stem, len(hits), box, expected))
        for o, lis in hits:
            for li in lis:
                o.data.uv_layers[0].data[li].uv = target
        left = 0
        for o in meshes:
            uv = o.data.uv_layers[0].data
            for p in o.data.polygons:
                lis = list(p.loop_indices)
                if in_box(box, sum(uv[li].uv.x for li in lis) / len(lis), sum(uv[li].uv.y for li in lis) / len(lis)):
                    left += 1
        log("UVFIX %s box=%s faces_before=%d faces_after=%d target=%s" % (stem, box, len(hits), left, target))
        if left:
            die("%s: %d faces still in UV box %s" % (stem, left, box))
        tris.append(sum(len(lis) - 2 for _o, lis in hits))
    return tris


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


# ---------------------------------------------------------------- static props


def drop_loose(stem, objs):
    """Remove vertices and edges that belong to no face. They are never drawn, glTF does
    not export them, and they would still count in the scene bounds (Fountain_1A has one
    stray vertex 3.7 m above its ball)."""
    import bmesh

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


def world_verts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def scale_about(o, pivot, k):
    o.matrix_world = Matrix.Translation(pivot) @ Matrix.Scale(k, 4) @ Matrix.Translation(-pivot) @ o.matrix_world
    bpy.context.view_layer.update()


def seat_faces(o, z0, z1):
    """Up-facing faces of `o` whose world centre lies in z0..z1."""
    nm = o.matrix_world.to_3x3().inverted().transposed()
    return [
        p.index
        for p in o.data.polygons
        if (nm @ p.normal).normalized().z > 0.9 and z0 <= (o.matrix_world @ p.center).z <= z1
    ]


def faces_height(o, faces):
    """Area-weighted world height of the given faces of `o`."""
    total = 0.0
    acc = 0.0
    for i in faces:
        p = o.data.polygons[i]
        acc += (o.matrix_world @ p.center).z * p.area
        total += p.area
    return acc / total


def islands(o):
    """Connected vertex groups of a mesh, as lists of vertex indices."""
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    out = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        comp = []
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        out.append(comp)
    bm.free()
    return out


def move_world(o, indices, fn):
    """Move the given vertices of `o` through fn(world position) -> world position."""
    mw = o.matrix_world
    inv = mw.inverted()
    for i in indices:
        v = o.data.vertices[i]
        v.co = inv @ fn(mw @ v.co)
    o.data.update()


def reshape_tree_bench(stem, objs):
    """Bench_2A at vendor scale, before the indoor factor (see RESHAPE). The planter above
    the seat step is pressed down to RESHAPE "planter" of its height; the soil, grass and
    tree drop with it; each of the four lamps shrinks to RESHAPE "lamp" about the foot of
    its post and drops with the soil. The seat ring (at or below the step) does not move."""
    spec = RESHAPE.get(stem)
    if spec is None:
        return
    parts = {o.name: o for o in objs if o.type == "MESH"}
    base, lights, tree = parts[spec["base"]], parts[spec["lights"]], parts[spec["tree"]]
    step, soil, k = spec["step"], spec["soil"], spec["planter"]

    def press(z):
        return z if z <= step else step + (z - step) * k

    drop = press(soil) - soil
    grass = 0
    pressed = 0
    for comp in islands(base):
        zs = [(base.matrix_world @ base.data.vertices[i].co).z for i in comp]
        if min(zs) >= soil - 0.01 and max(zs) > spec["rim"] + 0.02:
            # A grass blade standing in the soil: it drops with the soil, keeping its size.
            move_world(base, comp, lambda w: w + Vector((0.0, 0.0, drop)))
            grass += 1
        else:
            move_world(base, comp, lambda w: Vector((w.x, w.y, press(w.z))))
            pressed += 1
    quads = {}
    for comp in islands(lights):
        ws = [lights.matrix_world @ lights.data.vertices[i].co for i in comp]
        cx = sum(w.x for w in ws) / len(ws)
        cy = sum(w.y for w in ws) / len(ws)
        key = (cx > 0.0, cy > 0.0)
        if any((w.x > 0.0) != key[0] or (w.y > 0.0) != key[1] for w in ws):
            die("%s: a lamp island crosses a quadrant boundary near %s" % (stem, (round(cx, 2), round(cy, 2))))
        quads.setdefault(key, []).append((comp, ws))
    if len(quads) != 4:
        die("%s: expected four lamps (one per quadrant), found %d" % (stem, len(quads)))
    if grass != spec["grass_islands"]:
        die("%s: %d grass islands, expected %d" % (stem, grass, spec["grass_islands"]))
    for key, comps in sorted(quads.items()):
        if len(comps) != spec["lamp_islands"]:
            die("%s: lamp %s has %d islands, expected %d" % (stem, key, len(comps), spec["lamp_islands"]))
        pts = [w for _c, ws in comps for w in ws]
        low = min(w.z for w in pts)
        feet = [w for w in pts if w.z < low + 0.01]
        pivot = Vector((sum(w.x for w in feet) / len(feet), sum(w.y for w in feet) / len(feet), low))
        lamp_drop = press(low) - low
        for comp, _ws in comps:
            move_world(
                lights,
                comp,
                lambda w, p=pivot, d=lamp_drop: p + (w - p) * spec["lamp"] + Vector((0.0, 0.0, d)),
            )
        log("RESHAPE %s lamp=%s islands=%d foot=%s" % (stem, key, len(comps), tuple(round(v, 3) for v in pivot)))
    tree_low = min((tree.matrix_world @ v.co).z for v in tree.data.vertices)
    tree_drop = press(tree_low) - tree_low
    move_world(tree, range(len(tree.data.vertices)), lambda w: w + Vector((0.0, 0.0, tree_drop)))
    bpy.context.view_layer.update()
    log(
        "RESHAPE %s planter_factor=%.2f rim=%.3f soil=%.3f drop=%.3f islands_pressed=%d "
        "grass_dropped=%d lamp_factor=%.2f tree_drop=%.3f (vendor metres)"
        % (stem, k, press(spec["rim"]), press(soil), drop, pressed, grass, spec["lamp"], tree_drop)
    )


def report_tree_bench(stem, objs):
    """Final sizes of the reshaped bench in metres: the lamps, one lamp, the tree and its crown."""
    spec = RESHAPE.get(stem)
    if spec is None:
        return
    parts = {o.name: o for o in objs if o.type == "MESH"}
    lamp = world_verts(parts[spec["lights"]])
    one = [w for w in lamp if w.x > 0 and w.y > 0]
    tree = world_verts(parts[spec["tree"]])
    crown_from = min(w.z for w in tree) + 0.3 * (max(w.z for w in tree) - min(w.z for w in tree))
    crown = [w for w in tree if w.z >= crown_from]
    log(
        "BENCH %s lamp_z=(%.3f, %.3f) one_lamp_xy=(%.3f, %.3f) "
        "tree_z=(%.3f, %.3f) crown_xy=(%.3f, %.3f)"
        % (
            stem,
            min(w.z for w in lamp),
            max(w.z for w in lamp),
            max(w.x for w in one) - min(w.x for w in one),
            max(w.y for w in one) - min(w.y for w in one),
            min(w.z for w in tree),
            max(w.z for w in tree),
            max(w.x for w in crown) - min(w.x for w in crown),
            max(w.y for w in crown) - min(w.y for w in crown),
        )
    )


def make_indoor(stem, objs):
    """Scale an INDOOR stem to its indoor size. Returns the seat check (object name, face
    indices, target height) or None."""
    spec = INDOOR.get(stem)
    if spec is None:
        return None
    meshes = {o.name: o for o in objs if o.type == "MESH"}
    seat = None
    if "top" in spec:
        top = max(w.z for o in meshes.values() for w in world_verts(o))
        k = spec["top"] / top
        log("INDOOR %s vendor_top=%.3f target_top=%.3f factor=%.4f" % (stem, top, spec["top"], k))
    else:
        part, z0, z1, height = spec["seat"]
        o = meshes.get(part)
        if o is None:
            die("%s: no part %s for the seat" % (stem, part))
        faces = seat_faces(o, z0, z1)
        if not faces:
            die("%s: no up-facing faces on %s between %.2f and %.2f" % (stem, part, z0, z1))
        vendor = faces_height(o, faces)
        k = height / vendor
        seat = (part, faces, height)
        log("INDOOR %s seat_faces=%d vendor_seat=%.3f target_seat=%.3f factor=%.4f" % (stem, len(faces), vendor, height, k))
    for o in objs:
        if o.parent is None:
            scale_about(o, Vector((0.0, 0.0, 0.0)), k)
    for part, pspec in spec.get("parts", {}).items():
        o = meshes.get(part)
        if o is None:
            die("%s: no part %s" % (stem, part))
        ws = world_verts(o)
        base = min(w.z for w in ws)
        top = max(w.z for w in ws)
        pivot = Vector((o.matrix_world.translation.x, o.matrix_world.translation.y, base))
        e = (pspec["top"] - base) / (top - base)
        scale_about(o, pivot, e)
        log("INDOOR %s part=%s pivot=%s top_before=%.3f top_after=%.3f extra_factor=%.4f" % (
            stem, part, tuple(round(v, 3) for v in pivot), top, max(w.z for w in world_verts(o)), e))
    return seat


def part_state(objs):
    """Per mesh object: world vertex AABB, world origin, world rotation and parent name."""
    out = {}
    for o in objs:
        if o.type != "MESH":
            continue
        ws = world_verts(o)
        lo = Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws)))
        hi = Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))
        loc, rot, _scl = o.matrix_world.decompose()
        out[o.name] = (lo, hi, loc, rot.to_matrix(), o.parent.name if o.parent else None)
    return out


def bake_scale(stem, objs):
    """Bake every object's world scale into its mesh, parents first, keeping each world
    origin and rotation (door hinges, the trunk the tail lights hang on). Objects whose
    scale has magnitude 1 on every axis are not touched, mirrored ones included (the
    plane's TP_Plane_05A_Tables is -1, -1, -1). Returns the baked object names."""
    markers = MARKERS.get(stem, {})
    for o in objs:
        if o.type == "EMPTY" and o.name in markers:
            continue
        if o.type != "MESH":
            die("%s: static prop has a %s object %s; only meshes are handled" % (stem, o.type, o.name))
    for o in objs:
        if o.type == "EMPTY" and any(abs(abs(s) - 1.0) > 1e-6 for s in o.matrix_world.to_scale()):
            die("%s: marker %s has a non-unit scale" % (stem, o.name))
    objs = [o for o in objs if o.type == "MESH"]

    def depth(o):
        d = 0
        while o.parent is not None:
            o, d = o.parent, d + 1
        return d

    order = sorted(objs, key=depth)
    before = {o: o.matrix_world.copy() for o in order}
    baked = []
    for o in order:
        loc, rot, scl = before[o].decompose()
        if all(abs(abs(s) - 1.0) < 1e-6 for s in scl):
            o.matrix_world = before[o]
        else:
            recomposed = Matrix.LocRotScale(loc, rot, scl)
            shear = max(abs(recomposed[i][j] - before[o][i][j]) for i in range(4) for j in range(4))
            if shear > 1e-6:
                die("%s: %s has a sheared transform (%.2e off its TRS); not baked" % (stem, o.name, shear))
            if before[o].determinant() <= 0.0:
                die("%s: %s is mirrored; scale baking expects a positive scale" % (stem, o.name))
            if o.data.users > 1:
                die("%s: %s shares its mesh; cannot bake its scale alone" % (stem, o.name))
            o.data.transform(Matrix.Diagonal(scl).to_4x4())
            o.matrix_world = Matrix.Translation(loc) @ rot.to_matrix().to_4x4()
            baked.append(o.name)
        bpy.context.view_layer.update()
    return baked


def compare_parts(stem, intent, now, what):
    """Each part's bounds, origin, rotation and parent match the intent."""
    if sorted(intent) != sorted(now):
        die("%s: %s parts %s differ from intent %s" % (stem, what, sorted(now), sorted(intent)))
    worst_pos = 0.0
    worst_rot = 0.0
    for name, (lo, hi, loc, rot, parent) in intent.items():
        n_lo, n_hi, n_loc, n_rot, n_parent = now[name]
        if parent != n_parent:
            die("%s: %s %s has parent %s, intended %s" % (stem, what, name, n_parent, parent))
        pos = max(
            max(abs(a - b) for a, b in zip(lo, n_lo)),
            max(abs(a - b) for a, b in zip(hi, n_hi)),
            max(abs(a - b) for a, b in zip(loc, n_loc)),
        )
        turn = max(abs(rot[i][j] - n_rot[i][j]) for i in range(3) for j in range(3))
        worst_pos = max(worst_pos, pos)
        worst_rot = max(worst_rot, turn)
        if pos > POSITION_TOLERANCE or turn > ROTATION_TOLERANCE:
            die("%s: %s part %s moved %.6f m or turned %.6f" % (stem, what, name, pos, turn))
    log("PARTS %s %s parts=%d max_position_dev_m=%.6f max_rotation_dev=%.6f" % (stem, what, len(intent), worst_pos, worst_rot))


def check_seat(stem, seat, objs):
    if seat is None:
        return
    part, faces, target = seat
    o = next(o for o in objs if o.name == part)
    h = faces_height(o, faces)
    log("SEAT %s part=%s faces=%d height=%.3f target=%.3f" % (stem, part, len(faces), h, target))
    if abs(h - target) > GROUND_TOLERANCE:
        die("%s: seat at %.3f, intended %.3f" % (stem, h, target))


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


def glb_accessor(path, js, index):
    """Float values of one accessor in the written .glb, as a list of tuples."""
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    bin_start = 20 + jlen + 8
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    if acc["componentType"] != 5126:
        die("accessor %d is not float" % index)
    stride = view.get("byteStride", 4 * width)
    base = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [struct.unpack_from("<%df" % width, data, base + i * stride) for i in range(acc["count"])]


def glb_indices(path, js, index):
    """Integer values of one index accessor in the written .glb."""
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    bin_start = 20 + jlen + 8
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    fmt = {5121: "B", 5123: "H", 5125: "I"}[acc["componentType"]]
    base = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return list(struct.unpack_from("<%d%s" % (acc["count"], fmt), data, base))


Y_UP = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))


def yup_parts(parts):
    """part_state() output in glTF axes (Y up)."""
    out = {}
    for name, (lo, hi, loc, rot, parent) in parts.items():
        a, b = Y_UP @ lo, Y_UP @ hi
        out[name] = (
            Vector(map(min, a, b)),
            Vector(map(max, a, b)),
            Y_UP @ loc,
            Y_UP @ rot @ Y_UP.transposed(),
            parent,
        )
    return out


def glb_parts(path, js):
    """Per mesh node of the written file: world vertex AABB (from the vertices), world
    origin, world rotation and parent node name, in glTF axes."""
    nodes = js.get("nodes", [])
    parent_of = {c: i for i, nd in enumerate(nodes) for c in nd.get("children", [])}
    out = {}

    def world(i):
        m = node_matrix(nodes[i])
        while i in parent_of:
            i = parent_of[i]
            m = node_matrix(nodes[i]) @ m
        return m

    for i, nd in enumerate(nodes):
        if "mesh" not in nd:
            continue
        m = world(i)
        lo = Vector((math.inf,) * 3)
        hi = Vector((-math.inf,) * 3)
        for prim in js["meshes"][nd["mesh"]]["primitives"]:
            for p in glb_accessor(path, js, prim["attributes"]["POSITION"]):
                w = m @ Vector(p)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        loc, rot, _scl = m.decompose()
        parent = nodes[parent_of[i]].get("name") if i in parent_of else None
        name = nd.get("name", str(i))
        if name in out:
            die("written file has two mesh nodes named %s" % name)
        out[name] = (lo, hi, loc, rot.to_matrix(), parent)
    return out


def check_texcoords(stem, js):
    """Every primitive is triangles with TEXCOORD_0: a face without UVs samples (0, 0)."""
    prims = 0
    for mesh in js.get("meshes", []):
        for prim in mesh["primitives"]:
            prims += 1
            if prim.get("mode", 4) != 4 or "TEXCOORD_0" not in prim["attributes"]:
                die("%s: mesh %s has a primitive without triangles or TEXCOORD_0" % (stem, mesh.get("name")))
    log("TEXCOORD %s primitives=%d all_have_texcoord_0=True" % (stem, prims))


def glb_unit_values(path, js, index):
    """Values of one float or normalized-integer accessor in the written .glb, in 0..1."""
    acc = js["accessors"][index]
    if acc["componentType"] == 5126:
        return glb_accessor(path, js, index)
    with open(path, "rb") as f:
        data = f.read()
    bin_start = 20 + struct.unpack_from("<I", data, 12)[0] + 8
    view = js["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt, size, top = {5121: ("B", 1, 255.0), 5123: ("H", 2, 65535.0)}[acc["componentType"]]
    stride = view.get("byteStride", size * width)
    base = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [
        tuple(v / top for v in struct.unpack_from("<%d%s" % (width, fmt), data, base + i * stride))
        for i in range(acc["count"])
    ]


def check_cloth(stem, path, js, cloth_tris):
    """The written file carries the clothes' mark (COLOR_0, see CLOTH_ATTR): exactly as many
    triangles as the clothes have are white at all three corners, every other triangle is
    black at all three, and none is mixed."""
    white = black = mixed = 0
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            if "COLOR_0" not in prim["attributes"]:
                die("%s: written primitive has no COLOR_0 (the clothes' mark)" % stem)
            cols = glb_unit_values(path, js, prim["attributes"]["COLOR_0"])
            idx = glb_indices(path, js, prim["indices"])
            for t in range(0, len(idx), 3):
                marks = {cols[i][0] > 0.5 for i in idx[t : t + 3]}
                if len(marks) > 1:
                    mixed += 1
                elif True in marks:
                    white += 1
                else:
                    black += 1
    log("CLOTH_FILE %s cloth_triangles=%d other_triangles=%d mixed=%d scene_cloth=%d" % (stem, white, black, mixed, cloth_tris))
    if mixed or white != cloth_tris or not black:
        die("%s: written clothes' mark is wrong" % stem)


def check_uv_fixes(stem, path, js, fixed_tris):
    """No triangle of the written file has its UV centroid in a UV_FIXES box, and exactly
    as many triangles as fix_uvs moved have all three corners on the target UV. glTF
    stores V flipped (v_gltf = 1 - v_blender), so the box and target are flipped to match."""
    for (box, target, _expected), want in zip(UV_FIXES.get(stem, []), fixed_tris):
        tu, tv = target[0], 1.0 - target[1]
        fbox = (box[0], 1.0 - box[3], box[2], 1.0 - box[1])
        in_tris = at_target = 0
        for mesh in js["meshes"]:
            for prim in mesh["primitives"]:
                if prim.get("mode", 4) != 4 or "TEXCOORD_0" not in prim["attributes"]:
                    die("%s: primitive without triangles or TEXCOORD_0" % stem)
                uvs = glb_accessor(path, js, prim["attributes"]["TEXCOORD_0"])
                idx = glb_indices(path, js, prim["indices"])
                for t in range(0, len(idx), 3):
                    cu = sum(uvs[i][0] for i in idx[t : t + 3]) / 3.0
                    cv = sum(uvs[i][1] for i in idx[t : t + 3]) / 3.0
                    if in_box(fbox, cu, cv):
                        in_tris += 1
                    if all(abs(uvs[i][0] - tu) < 1e-4 and abs(uvs[i][1] - tv) < 1e-4 for i in idx[t : t + 3]):
                        at_target += 1
        log(
            "UVFIX_FILE %s box=%s triangles_in_box=%d triangles_at_target=%d moved=%d"
            % (stem, box, in_tris, at_target, want)
        )
        if in_tris or at_target != want:
            die("%s: written file has %d triangles in UV box %s, %d of %d at target" % (stem, in_tris, box, at_target, want))


def check_clips(stem, path, js, durations):
    """The written file carries exactly the clips, each as long as it was baked and
    each with real motion (Root may stay constant, the clip as a whole may not)."""
    anims = js.get("animations", [])
    names = [a["name"] for a in anims]
    if sorted(names) != sorted(toon_clips.CLIPS) or len(anims) != len(toon_clips.CLIPS):
        die("%s: expected animations %s, file has %s" % (stem, sorted(toon_clips.CLIPS), names))
    for a in anims:
        end = max(js["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        start = min(js["accessors"][s["input"]]["min"][0] for s in a["samplers"])
        motion = 0.0
        for s in a["samplers"]:
            vals = glb_accessor(path, js, s["output"])
            for c in range(len(vals[0])):
                col = [v[c] for v in vals]
                motion = max(motion, max(col) - min(col))
        want = durations[a["name"]]
        log(
            "CLIP %s %s duration_s=%.4f baked_s=%.4f channels=%d max_channel_range=%.4f"
            % (stem, a["name"], end - start, want, len(a["channels"]), motion)
        )
        if abs(start) > 1e-4:
            die("%s: clip %s starts at %.4f s, not 0" % (stem, a["name"], start))
        if abs((end - start) - want) > 0.25 / toon_clips.FPS:
            die("%s: clip %s lasts %.4f s, baked %.4f s" % (stem, a["name"], end - start, want))
        if motion < 1e-3:
            die("%s: clip %s carries no motion" % (stem, a["name"]))


def check_markers(stem, js):
    """The declared mount empties are nodes of the written file, by name, at their
    declared position (glTF axes) with identity rotation and unit scale, each once and
    parented to the declared mesh node; no other node without a mesh is in the file."""
    want = MARKERS.get(stem, {})
    nodes = js.get("nodes", [])
    parent_of = {c: i for i, nd in enumerate(nodes) for c in nd.get("children", [])}
    found = {}
    for i, nd in enumerate(nodes):
        if "mesh" in nd:
            continue
        name = nd.get("name", str(i))
        if name not in want:
            die("%s: written file has an unexpected empty node %s" % (stem, name))
        if name in found:
            die("%s: written file has two marker nodes named %s" % (stem, name))
        parent = nodes[parent_of[i]].get("name") if i in parent_of else None
        if parent != MARKER_PARENT[stem]:
            die("%s: marker %s hangs under %s, not %s" % (stem, name, parent, MARKER_PARENT[stem]))
        m = node_matrix(nd)
        j = i
        while j in parent_of:
            j = parent_of[j]
            m = node_matrix(nodes[j]) @ m
        loc, rot, scl = m.decompose()
        found[name] = loc
        off = max(abs(a - b) for a, b in zip(loc, want[name]))
        turn = max(abs(rot.to_matrix()[r][c] - (1.0 if r == c else 0.0)) for r in range(3) for c in range(3))
        log("MARKER %s %s at=(%.3f, %.3f, %.3f) want=%s off_m=%.4f rotation_off=%.2e" % (stem, name, loc.x, loc.y, loc.z, want[name], off, turn))
        if off > POSITION_TOLERANCE or turn > ROTATION_TOLERANCE or any(abs(s - 1.0) > 1e-6 for s in scl):
            die("%s: marker %s is not at its declared transform" % (stem, name))
    if sorted(found) != sorted(want):
        die("%s: written file markers %s, declared %s" % (stem, sorted(found), sorted(want)))


def on_metre(v):
    return abs(v - round(v)) < 0.01


# ---------------------------------------------------------------- import file


def write_scene_import(glb_path, animated=False):
    """Make Godot run the toon post-import binder on this .glb. Characters import their
    clips at the 25 fps they were baked at, so Godot keeps the baked keys as they are."""
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
        if animated:
            fps_line = "animation/fps=%d" % toon_clips.FPS
            if re.search(r"^animation/fps=.*$", text, flags=re.M):
                text = re.sub(r"^animation/fps=.*$", fps_line, text, flags=re.M)
            else:
                text = text.replace("[params]\n", "[params]\n\n%s\n" % fps_line, 1)
    else:
        text = (
            '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
            "%s\ngltf/embedded_image_handling=0\n" % line
        )
        if animated:
            text += "animation/fps=%d\n" % toon_clips.FPS
    with open(path, "w", newline="\n") as f:
        f.write(text)


# ---------------------------------------------------------------- main


def convert(stem, spec, out_root=None):  # out_root None: write into game/assets/
    pack, category, fbx, idle_fbx, prefab = spec
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if fbx.startswith(AUTHORED):
        if idle_fbx is not None or prefab is not None:
            die("%s: an authored asset is a static prop; it takes no idle FBX or prefab" % stem)
        builder = AUTHORED_BUILDERS[fbx[len(AUTHORED) :]]
        try:
            builder.build(os.path.join(TEX_DIR, MATERIALS[(pack, builder.MATERIAL)][2]))
        except builder.Fail as e:
            die("%s: %s" % (stem, e))
    else:
        bpy.ops.import_scene.fbx(filepath=os.path.join(PACK_ROOTS[pack], "Models", fbx))
    bpy.context.view_layer.update()
    objs = list(bpy.context.scene.objects)
    reflected = sorted(o.name for o in objs if o.matrix_world.determinant() < 0)
    if idle_fbx is None:
        for o in objs:
            if o.animation_data:
                o.animation_data_clear()
        for a in list(bpy.data.actions):
            bpy.data.actions.remove(a)
    if idle_fbx is None:
        drop_loose(stem, objs)
    rebind_materials(pack, objs)
    if stem in VENDOR_EDITS:
        try:
            VENDOR_EDITS[stem].edit(objs)
        except VENDOR_EDITS[stem].Fail as e:
            die("%s: %s" % (stem, e))
        bpy.context.view_layer.update()
    durations = {}
    looks = None
    seat = None
    intent = None
    if idle_fbx is not None:
        objs, durations, looks = build_character(stem, idle_fbx, prefab)
        objs = list(bpy.context.scene.objects)
    else:
        # Static props: resize an indoor variant, record the intended parts, bake every
        # non-unit scale into the meshes and check that no part moved.
        reshape_tree_bench(stem, objs)
        seat = make_indoor(stem, objs)
        report_tree_bench(stem, objs)
        intent = part_state(objs)
        baked = bake_scale(stem, objs)
        log("SCALE %s baked=%s" % (stem, baked))
        compare_parts(stem, intent, part_state(objs), "after-bake")
        check_seat(stem, seat, objs)
    fixed_tris = fix_uvs(stem, objs)
    bpy.context.view_layer.update()
    if looks is not None:
        magenta_faces(stem, objs)

    mats = sorted({s.material.name for o in objs if o.type == "MESH" for s in o.material_slots})
    imgs = sorted(i.name for i in bpy.data.images if i.users > 0)
    verts = sum(len(o.data.vertices) for o in objs if o.type == "MESH")
    s_lo, s_hi = scene_bounds_yup(objs)

    out_dir = out_root or os.path.join(ASSETS, category)
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
        # A character's one colour is the clothes' mark (CLOTH_ATTR); props export none.
        export_vertex_color="ACTIVE" if looks is not None else "NONE",
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
    check_texcoords(stem, js)
    check_uv_fixes(stem, out, js, fixed_tris)
    if intent is not None:
        compare_parts(stem, yup_parts(intent), glb_parts(out, js), "written-file")
    if intent is not None:
        check_markers(stem, js)
    if category in GROUND_CATEGORIES:
        want = GROUND.get(stem, 0.0)
        log("GROUND %s bottom=%.3f expected=%.3f top=%.3f" % (stem, f_lo.y, want, f_hi.y))
        if abs(f_lo.y - want) > GROUND_TOLERANCE:
            die("%s: bottom at %.3f, expected %.3f" % (stem, f_lo.y, want))
    if stem in INDOOR and f_hi.y >= INDOOR_CEILING:
        die("%s: indoor variant is %.3f m tall, not under %.1f m" % (stem, f_hi.y, INDOOR_CEILING))
    if animated:
        check_clips(stem, out, js, durations)
        check_cloth(stem, out, js, looks)
    if not animated and f_anims:
        die("%s: a prop carries animations %s" % (stem, f_anims))
    if not animated:
        for k in range(3):
            if abs(f_lo[k] - s_lo[k]) > BOUNDS_TOLERANCE or abs(f_hi[k] - s_hi[k]) > BOUNDS_TOLERANCE:
                die("%s: file bounds %s..%s differ from scene %s..%s" % (stem, f_lo, f_hi, s_lo, s_hi))
    if out_root is None:
        write_scene_import(out, animated)


def out_dir_arg(raw):
    """The --out directory as a resolved Windows path, refused when it is empty, a WSL
    path (this runs under Windows Blender) or inside game/ in any spelling: a \\\\?\\
    prefix, .. segments, other case or a junction all resolve before the comparison."""
    if not raw.strip():
        die("--out needs a directory, got an empty one")
    if re.match(r"^/mnt/[A-Za-z](/|$)", raw):
        die("--out got a WSL path %r; pass the Windows form (C:\\...)" % raw)
    path = raw
    for prefix in ("\\\\?\\", "//?/"):
        if path.startswith(prefix):
            path = path[len(prefix) :]
    path = os.path.realpath(path)
    norm = os.path.normcase(path)
    game = os.path.normcase(os.path.realpath(GAME))
    try:
        inside = os.path.commonpath([norm, game]) == game
    except ValueError:  # different drives
        inside = False
    if inside:
        die("--out must name a directory outside game/, got %r (resolves to %s)" % (raw, path))
    return path


def main():
    """Arguments after `--`: asset stems, and optionally `--out <dir>`. With --out the
    .glb files go to that directory and game/ is left as it is: the atlas PNGs already
    there are read, not rewritten, and no .import file is written."""
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out_root = None
    if "--out" in argv:
        i = argv.index("--out")
        if i + 1 >= len(argv):
            die("--out needs a directory")
        out_root = out_dir_arg(argv[i + 1])
        del argv[i : i + 2]
        if os.path.basename(out_root) in BATCH:
            die("--out was given a stem, not a directory: %r" % out_root)
    stems = argv or list(BATCH)
    unknown = [s for s in stems if s not in BATCH]
    if unknown:
        die("unknown stems %s" % unknown)
    if out_root is None:
        convert_textures()
    else:
        log("OUT %s (game/ is not written)" % out_root)
    for stem in stems:
        convert(stem, BATCH[stem], out_root)
    log("DONE %d assets" % len(stems))


main()
