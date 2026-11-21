"""Convert the airside construction-works props (board ecd67e67, S8b phase 1) from the
Toon Series Unity FBX packs to game/assets/airside/props/works/<stem>.glb.

Run from WSL (Blender is a Windows program, so every path it sees is a Windows path):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 --python \
        'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\convert_works_props.py' [-- stem ...]

Optional after `--`: stems to convert (all when none), and `--out <dir>` to write the
.glb files outside game/ (no PNG and no .import file is then written).
Then run a Godot `--headless --import`, which binds the toon materials through
game/assets/airside/props/works/works_post_import.gd.

Kept apart from convert_toon_batch.py (at its line cap) in the way convert_crow.py is:
these props come from three packs (Toon City, Toon Industries, Toon Farm), and two of
those packs are used by nothing else in the game.

What it does, per prop in PROPS:
1. Converts the pack textures this set needs that the game does not have yet (the
   Toon Industries excavator albedo and the Toon Industries ramp) to PNG beside the
   assets. The Toon City road and props atlases and the Toon Farm atlas are already in
   game/ and are read, not rewritten.
2. Imports the FBX (UnitScaleFactor 100, so metres), clears the vendor's one-frame
   takes, keeps only the LOD0 objects (the dump trailer ships LOD0-2) and drops the
   faces of any material listed in "drop" (the farm-brand logo decals).
3. Rebinds the palette atlas: every vendor material becomes the named game material
   in "materials", a Principled material on the converted atlas PNG. An unmapped name
   stops the run. Only the first UV layer is kept, loose vertices are removed.
4. Measures the rest bounds (REST line) and requires the lowest vertex within
   FLOOR_TOLERANCE_M of the ground.
5. Exports .glb, RE-READS THE WRITTEN FILE and checks materials, images, texcoords,
   vertex colours, animations and world bounds (node transforms applied). Any
   mismatch stops the run. The log prints SCENE (materials and images in Blender) and
   FILE lines (what the written file holds).
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.dont_write_bytecode = True
GAME = os.path.join(REPO, "game")
OUT_DIR = os.path.join(GAME, "assets", "airside", "props", "works")
POST_IMPORT = "res://assets/airside/props/works/works_post_import.gd"
SERIES = "C:\\Users\\chulf\\Assets new\\Toon Series"
CITY = os.path.join(SERIES, "Toon City")
INDUSTRIES = os.path.join(SERIES, "Toon Industries")
FARM = os.path.join(SERIES, "Toon Farm Pack")
GAME_TEXTURES = os.path.join(GAME, "assets", "textures")
BIRDS = os.path.join(GAME, "assets", "birds")
# Vendor PSD -> (PNG under OUT_DIR, mipmaps). Only what game/ does not have yet.
TEXTURES = {
    os.path.join(INDUSTRIES, "Textures", "Excavator_1A_D.psd"): ("ti_excavator_1a_d.png", True),
    os.path.join(INDUSTRIES, "Textures", "TI_Toon_Ramp_1A.psd"): ("ti_toon_ramp_1a.png", False),
    os.path.join(INDUSTRIES, "Textures", "Road_1A_D.psd"): ("ti_road_1a_d.png", True),
}
# Game material name -> the atlas PNG its Blender material samples (the glb carries it;
# Godot discards it and binds the shared .tres by name, see works_post_import.gd).
ATLAS = {
    "TC_Road_1A_D": os.path.join(GAME_TEXTURES, "tc_road_1a_d.png"),
    "TC_Props_2A_D": os.path.join(GAME_TEXTURES, "tc_props_2a_d.png"),
    "TI_Excavator_1A_D": os.path.join(OUT_DIR, "ti_excavator_1a_d.png"),
    "TI_Road_1A_D": os.path.join(OUT_DIR, "ti_road_1a_d.png"),
    "TFP_Atlas_1A_D": os.path.join(BIRDS, "tfp_atlas_1a_d.png"),
}
# The picks for the works (one of each the layout needs; survey plates from
# render_works_plates.py survey). Toon City Road_1A_D is the texture
# game/assets/textures/tc_road_1a_d.png was made from; the Toon Industries Road_1A_D is
# a different file, so the Toon City barrier binds TC_Road_1A_D and the Toon Industries
# fence binds its own TI_Road_1A_D. The fence is the corrugated hoarding Metal_Fence_1A
# (conductor ruling on the plates: Toon City Metal_Fence_2A read as a road sign on one
# post). The Toon Industries Props_2A_D.psd is byte-identical to the Toon City one (md5
# b4469acf...), so the cone and the brick pile bind the existing TC_Props_2A_D
# material. Toon City's Traffic_Cone_2A/2B are drums; Toon Industries Traffic_Cone_1B
# is the plain cone (the same mesh as Toon City Traffic_Cone_1A, whose Building_1A_D
# atlas the game lacks).
PROPS = {
    "ti_traffic_cone_1b": {
        "fbx": os.path.join(INDUSTRIES, "Models", "Traffic_Cone_1B.fbx"),
        "materials": {"Props_2A_D": "TC_Props_2A_D"},
    },
    "tc_concrete_barrier_1a": {
        "fbx": os.path.join(CITY, "Models", "Concrete_Barrier_1A.fbx"),
        "materials": {"Road_1A_D": "TC_Road_1A_D"},
    },
    "ti_metal_fence_1a": {
        "fbx": os.path.join(INDUSTRIES, "Models", "Metal_Fence_1A.fbx"),
        "materials": {"Road_1A_D": "TI_Road_1A_D"},
    },
    "ti_excavator_1a": {
        "fbx": os.path.join(INDUSTRIES, "Models", "Excavator_1A.fbx"),
        "materials": {"Excavator_1A_D": "TI_Excavator_1A_D"},
        "ground_min_z": True,
    },
    "ti_brick_pile_1c": {
        "fbx": os.path.join(INDUSTRIES, "Models", "Brick_Pile_1C.fbx"),
        "materials": {"Props_2A_D": "TC_Props_2A_D"},
    },
    "tfp_dump_trailer_01a": {
        "fbx": os.path.join(FARM, "Models", "TFP_Dump_Trailer_01A.fbx"),
        "materials": {"TFP_Atlas_1A": "TFP_Atlas_1A_D"},
        "drop": ["TFP_Atlas_Logos_1A"],
        # Blender's FBX importer gives the LOD0 meshes under the Container, Tailgate and
        # Wheel empties a -90 degree X rotation (the chassis mesh has none; the vendor
        # prefab has identity on all of them). With it the tub lies on its side, the
        # tailgate hangs out 1.3 m beside the rear and the wheel discs lie flat, 0.28 m
        # off the ground. At identity the wheels (radius 0.62 m) touch the ground under
        # their 0.611 m axles, the tub opens upward and the tailgate spans the rear.
        "upright_lod0": True,
    },
}
FLOOR_TOLERANCE_M = 0.05
BOUNDS_TOLERANCE_M = 0.02


def log(*a):
    print("WORKS", *a, flush=True)


def die(msg):
    print("WORKS_FAIL", msg, flush=True)
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


def game_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    png = ATLAS[name]
    if not os.path.exists(png):
        die("atlas PNG missing for %s: %s" % (name, png))
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(png, check_existing=True)
    if tex.image.size[0] == 0:
        die("atlas image did not load: %s" % png)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def keep_lod0(objs):
    """Delete the LOD1/LOD2 objects and strip the _LOD0 suffix from the rest."""
    dropped = 0
    for o in list(objs):
        if "_LOD1" in o.name or "_LOD2" in o.name:
            if any(c for c in o.children if "_LOD0" in c.name):
                die("%s holds a LOD0 child" % o.name)
            bpy.data.objects.remove(o, do_unlink=True)
            dropped += 1
    for o in bpy.context.scene.objects:
        if o.name.endswith("_LOD0"):
            # The LOD group empty already holds the bare name; the mesh under it
            # becomes <name>_Mesh rather than a Blender-made "<name>.001".
            base = o.name[: -len("_LOD0")]
            o.name = base + "_Mesh" if bpy.data.objects.get(base) else base
    return dropped


def drop_faces(o, names):
    """Delete the faces of o that use a material in names; return how many."""
    slots = {i for i, s in enumerate(o.material_slots) if s.material and s.material.name.split(".")[0] in names}
    if not slots:
        return 0
    bm = bmesh.new()
    bm.from_mesh(o.data)
    doomed = [f for f in bm.faces if f.material_index in slots]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    for i in sorted(slots, reverse=True):
        for p in o.data.polygons:
            if p.material_index > i:
                p.material_index -= 1
        o.data.materials.pop(index=i)
    o.data.update()
    return len(doomed)


def rebind(o, table):
    """Point every slot at its game material, then merge slots that now share one."""
    for s in o.material_slots:
        if s.material is None:
            die("%s: empty material slot" % o.name)
        vendor = s.material.name.split(".")[0]
        if vendor not in table:
            die("%s: unmapped material %s" % (o.name, s.material.name))
        s.material = game_material(table[vendor])
    first = {}
    remap = {}
    for i, s in enumerate(o.material_slots):
        first.setdefault(s.material.name, i)
        remap[i] = first[s.material.name]
    for p in o.data.polygons:
        p.material_index = remap[p.material_index]
    keep = sorted(set(remap.values()))
    for i in reversed(range(len(o.material_slots))):
        if i not in keep:
            o.active_material_index = i
            o.data.materials.pop(index=i)


def clean_mesh(o):
    while len(o.data.uv_layers) > 1:
        o.data.uv_layers.remove(o.data.uv_layers[-1])
    if len(o.data.uv_layers) != 1:
        die("%s: no UV layer" % o.name)
    while o.data.color_attributes:
        o.data.color_attributes.remove(o.data.color_attributes[0])
    bm = bmesh.new()
    bm.from_mesh(o.data)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.name = o.name  # glTF mesh names come from the mesh data
    return len(loose)


def rest_bounds():
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


# ---------------------------------------------------------------- written-file checks


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a GLB: %s" % path)
    jlen, _jtype = struct.unpack_from("<II", data, 12)
    return json.loads(data[20 : 20 + jlen]), data


def node_matrix(n):
    if "matrix" in n:
        m = n["matrix"]
        return Matrix([m[0:4], m[4:8], m[8:12], m[12:16]]).transposed()
    t = Matrix.Translation(n.get("translation", (0.0, 0.0, 0.0)))
    q = n.get("rotation", (0.0, 0.0, 0.0, 1.0))
    r = Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
    s = n.get("scale", (1.0, 1.0, 1.0))
    return t @ r @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))


def file_bounds(js):
    """World (glTF Y-up) bounds of every mesh's POSITION min/max box, node transforms applied."""
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    nodes = js["nodes"]

    def walk(i, parent):
        n = nodes[i]
        m = parent @ node_matrix(n)
        if "mesh" in n:
            for p in js["meshes"][n["mesh"]]["primitives"]:
                acc = js["accessors"][p["attributes"]["POSITION"]]
                a, b = acc["min"], acc["max"]
                for x in (a[0], b[0]):
                    for y in (a[1], b[1]):
                        for z in (a[2], b[2]):
                            w = m @ Vector((x, y, z))
                            lo[:] = tuple(map(min, lo, w))
                            hi[:] = tuple(map(max, hi, w))
        for c in n.get("children", []):
            walk(c, m)

    for root in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(root, Matrix.Identity(4))
    return lo, hi


def check_file(stem, path, expected_materials, scene_lo, scene_hi):
    js, data = parse_glb(path)
    mats = sorted(m["name"] for m in js.get("materials", []))
    imgs = [i.get("name", "?") for i in js.get("images", [])]
    meshes = [m["name"] for m in js.get("meshes", [])]
    nodes = [n.get("name") for n in js.get("nodes", [])]
    anims = js.get("animations", [])
    attrs = {k for m in js.get("meshes", []) for p in m["primitives"] for k in p["attributes"]}
    texcoords = sorted(k for k in attrs if k.startswith("TEXCOORD"))
    colours = sorted(k for k in attrs if k.startswith("COLOR"))
    tris = {}
    for m in js["meshes"]:
        for p in m["primitives"]:
            name = js["materials"][p["material"]]["name"] if "material" in p else "<none>"
            tris[name] = tris.get(name, 0) + js["accessors"][p["indices"]]["count"] // 3
    lo, hi = file_bounds(js)
    size = hi - lo
    log(
        "FILE %s bytes=%d materials=%s images=%d %s meshes=%d nodes=%s animations=%d texcoords=%s colours=%s"
        % (stem, len(data), mats, len(imgs), imgs, len(meshes), nodes, len(anims), texcoords, colours)
    )
    log("FILE_TRIS %s %s" % (stem, tris))
    log(
        "FILE_BOUNDS %s size_godot_xyz_m=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)"
        % ((stem,) + tuple(size) + tuple(lo) + tuple(hi))
    )
    if mats != sorted(expected_materials):
        die("%s: file materials %s, expected %s" % (stem, mats, sorted(expected_materials)))
    if len(imgs) != len(expected_materials):
        die("%s: file images %d, expected %d (one atlas per material)" % (stem, len(imgs), len(expected_materials)))
    if texcoords != ["TEXCOORD_0"] or colours:
        die("%s: texcoords %s colours %s, expected TEXCOORD_0 only" % (stem, texcoords, colours))
    if anims:
        die("%s: file carries %d animations, expected none" % (stem, len(anims)))
    if any("LOD" in (n or "") for n in nodes):
        die("%s: a LOD node survived: %s" % (stem, nodes))
    # Blender Z-up -> glTF Y-up: (x, y, z) -> (x, z, -y).
    want_lo = Vector((scene_lo.x, scene_lo.z, -scene_hi.y))
    want_hi = Vector((scene_hi.x, scene_hi.z, -scene_lo.y))
    err = max(max(abs(a - b) for a, b in zip(lo, want_lo)), max(abs(a - b) for a, b in zip(hi, want_hi)))
    log("FILE_VS_SCENE %s max_bound_err_m=%.4f" % (stem, err))
    if err > BOUNDS_TOLERANCE_M:
        die("%s: file bounds %s..%s differ from scene %s..%s" % (stem, tuple(lo), tuple(hi), tuple(want_lo), tuple(want_hi)))
    return size


def write_scene_import(glb_path):
    path = glb_path + ".import"
    if os.path.exists(path):
        log("IMPORT_FILE kept %s" % os.path.basename(path))
        return
    with open(path, "w", newline="\n") as f:
        f.write(
            '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
            'import_script/path="%s"\ngltf/embedded_image_handling=0\n' % POST_IMPORT
        )
    log("IMPORT_FILE wrote %s" % os.path.basename(path))


def convert(stem, spec, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=spec["fbx"])
    # The dump trailer's wheels and tailgate carry one-frame takes. The file keeps the
    # imported rest transforms (as the survey plates show them) and drops the takes;
    # the log says how far each take's pose sits from that rest.
    animated = [o for o in bpy.context.scene.objects if o.animation_data and o.animation_data.action]
    rest = {o.name: o.matrix_basis.copy() for o in bpy.context.scene.objects}
    if animated:
        bpy.context.scene.frame_set(min(int(o.animation_data.action.frame_range[0]) for o in animated))
        bpy.context.view_layer.update()
    for o in animated:
        d = rest[o.name].to_quaternion().rotation_difference(o.matrix_basis.to_quaternion()).angle
        log("TAKE %s %s take_vs_rest_deg=%.1f (rest kept)" % (stem, o.name, math.degrees(d)))
    for o in bpy.context.scene.objects:
        if o.animation_data:
            o.animation_data_clear()
        o.matrix_basis = rest[o.name]
    bpy.context.view_layer.update()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if spec.get("upright_lod0"):
        for o in bpy.context.scene.objects:
            if o.type != "MESH" or not o.name.endswith("_LOD0"):
                continue
            before = tuple(round(math.degrees(v), 1) for v in o.rotation_euler)
            o.rotation_mode = "XYZ"
            o.rotation_euler = (0.0, 0.0, 0.0)
            log("UPRIGHT %s %s rotation_deg %s -> (0, 0, 0)" % (stem, o.name, before))
        bpy.context.view_layer.update()
    dropped_lods = keep_lod0(list(bpy.context.scene.objects))
    bpy.context.view_layer.update()
    objs = list(bpy.context.scene.objects)
    meshes = [o for o in objs if o.type == "MESH"]
    vendor = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    log("IMPORT %s objects=%d meshes=%d lods_dropped=%d vendor_materials=%s" % (stem, len(objs), len(meshes), dropped_lods, vendor))
    for o in objs:
        if o.type not in ("MESH", "EMPTY"):
            die("%s: unexpected object type %s (%s)" % (stem, o.type, o.name))
        if any(abs(c - 1.0) > 1e-4 for c in o.scale):
            # Toon Industries Metal_Fence_1A is a unit-1 FBX with object scale 0.01;
            # bake it into the mesh so the file holds metre vertices and unit nodes.
            if o.type != "MESH" or o.children:
                die("%s: %s has scale %s and cannot be baked" % (stem, o.name, tuple(o.scale)))
            o.data.transform(Matrix.Diagonal(tuple(o.scale) + (1.0,)))
            log("BAKE_SCALE %s %s scale %s -> 1" % (stem, o.name, tuple(round(c, 4) for c in o.scale)))
            o.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    drop = spec.get("drop", [])
    for o in meshes:
        n = drop_faces(o, drop)
        if n:
            log("DROP %s %s faces=%d materials=%s" % (stem, o.name, n, drop))
    for o in list(meshes):
        if len(o.data.polygons) == 0:
            if o.children:
                die("%s: %s lost every face but has children" % (stem, o.name))
            log("DROP %s object %s (no faces left)" % (stem, o.name))
            meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        rebind(o, spec["materials"])
        loose = clean_mesh(o)
        log(
            "PART %s %s parent=%s verts=%d faces=%d loose_removed=%d materials=%s loc=(%.3f, %.3f, %.3f)"
            % (
                stem, o.name, o.parent.name if o.parent else None, len(o.data.vertices), len(o.data.polygons), loose,
                [s.material.name for s in o.material_slots], *o.matrix_world.translation,
            )
        )
        zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
        log("PART_Z %s %s low_z=%.3f high_z=%.3f" % (stem, o.name, min(zs), max(zs)))
    for me in list(bpy.data.meshes):
        if me.users == 0:  # the deleted LOD1/LOD2 objects' mesh data
            bpy.data.meshes.remove(me)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    bpy.context.view_layer.update()
    lo, hi = rest_bounds()
    if spec.get("ground_min_z") and abs(lo.z) > 1e-4:
        lift = -lo.z
        for o in bpy.context.scene.objects:
            if o.parent is None:
                o.location.z += lift
        bpy.context.view_layer.update()
        lo, hi = rest_bounds()
        log("GROUND_SHIFT %s lift=%.4f new_min_z=%.4f" % (stem, lift, lo.z))
    size = hi - lo
    log(
        "REST %s size_m width_x=%.3f depth_y=%.3f height_z=%.3f min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)"
        % ((stem, size.x, size.y, size.z) + tuple(lo) + tuple(hi))
    )
    if abs(lo.z) > FLOOR_TOLERANCE_M:
        die("%s: lowest vertex at z %.3f, not on the ground" % (stem, lo.z))
    expected = sorted(set(spec["materials"].values()) & {m.name for m in bpy.data.materials})
    log("SCENE %s materials=%s images=%s" % (stem, sorted(m.name for m in bpy.data.materials), sorted(i.name for i in bpy.data.images)))
    if len(bpy.data.images) != len(expected):
        die("%s: %d images for %d materials" % (stem, len(bpy.data.images), len(expected)))
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, stem + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_vertex_color="NONE",
        export_morph=False,
        export_skins=False,
        export_animations=False,
    )
    check_file(stem, out, expected, lo, hi)
    if out_dir == OUT_DIR:
        write_scene_import(out)
    log("DONE %s" % out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out_dir = OUT_DIR
    if "--out" in argv:
        i = argv.index("--out")
        out_dir = argv[i + 1]
        argv = argv[:i] + argv[i + 2 :]
        if os.path.normcase(os.path.realpath(out_dir)).startswith(os.path.normcase(os.path.realpath(GAME))):
            die("--out must be outside game/")
    unknown = [s for s in argv if s not in PROPS]
    if unknown:
        die("unknown stems %s; known %s" % (unknown, sorted(PROPS)))
    stems = argv or list(PROPS)
    if out_dir == OUT_DIR:
        convert_textures()
    for stem in stems:
        convert(stem, PROPS[stem], out_dir)
    log("ALL done props=%d out=%s" % (len(stems), out_dir))


if __name__ == "__main__":
    main()
