"""Census of the Toon Planes pack's runway, plane and airside pieces (board 4101e898).

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 \
        --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\census\\runway_census.py' \
        [-- --table-only]

Read-only on the vendor pack and on game/. For each piece it imports the vendor FBX,
rebinds the Toon palette atlas (vendor PSDs, as tools/blender/convert_toon_batch.py
maps them) and prints one CENSUS line: size, bounds about the file origin, parts and
materials. Planes get length, wingspan, height, nose direction and the stand swing
radius. Then it groups the planes into three classes at the two widest size gaps.

Without --table-only it also renders, under tools/blender/out/runway-assets/ (gitignored):
- per piece an iso, a top and a side orthographic view with a 1 m reference cube;
- one contact sheet per family (runway, planes, buildings, vehicles), five pieces a page;
- a top view of all aircraft side by side at true scale, and one of all runway pieces.
Every view projects the subject's and the cube's bounds into the frame with a margin
and casts rays at the subject and the cube; on a failure it prints PROBE_INVALID and
exits 1.

Axes: every number is printed in Godot axes (x, y up, z), which is what the glTF
export gives: Godot (x, y, z) = Blender (x, z, -y). The calibration step imports the
.glb files already in game/assets and checks the FBX measure matches them.
"""

import math
import os
import re
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.dont_write_bytecode = True
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PACK = "C:\\Users\\chulf\\Assets new\\Toon Series\\Toon Planes Pack"
MODELS = os.path.join(PACK, "Models")
TEXTURES = os.path.join(PACK, "Textures")
OUT = os.path.join(REPO, "tools", "blender", "out", "runway-assets")
MARGIN = 0.02
VIEW_RES = (480, 320)
LABEL_RES = (1440, 56)
PER_PAGE = 5

# FBX material name -> (atlas PSD, kind). The same pairs convert_toon_batch.py takes
# from the Unity .fbx.meta remaps. An unknown name stops the run.
MATERIALS = {
    "Atlas_1A_D": ("TP_Atlas_1A_D.psd", "opaque"),
    "Atlas_Simple_1A_D": ("TP_Atlas_1A_D.psd", "opaque"),
    "Atlas_Lights_1A_D": ("TP_Atlas_Lights_1A_D.psd", "emissive"),
    "Glass_Vehicles_01A_D": ("TP_Glass_Gradient_1A_D.psd", "glass"),
}

FAMILIES = {
    "runway": ["TP_Runway_0%dA" % i for i in range(1, 9)]
    + ["TP_Runway_Addon_0%dA" % i for i in range(1, 6)]
    + ["TP_Runway_Special_01A"],
    "planes": [
        "TP_Plane_%s" % s
        for s in "01A 01B 01C 02A 02B 02C 03A 03B 03C 04A 04B 05A 05B 05C 06A 06B 07A 07B 07C".split()
    ]
    + ["TP_Helicopter_%s" % s for s in "01A 01B 01C 02A 02B".split()],
    "buildings": [
        "TP_Control_Tower_01A",
        "TP_Concrete_Tower_01A",
        "TP_Hangar_01A",
        "TP_Hangar_01B",
        "TP_Hangar_02A",
        "TP_Hangar_02B",
        "TP_Hangar_Addon_01A",
        "TP_Radar_01A",
        "TP_Radar_02A",
        "TP_Pavement_01A_4X4",
        "TP_Pavement_01B_4X4",
        "TP_Pavement_01C_4X4",
        "TP_Pavement_02A_8X8",
        "TP_Pavement_03A_12X12",
        "TP_Pavement_04A_4X4",
        "TP_Metal_Fence_01A",
    ],
    "vehicles": [
        "TP_Loading_Truck_01A",
        "TP_Loading_Truck_01B",
        "TP_Loading_Truck_02A",
        "TP_Loading_Truck_02A_Addon",
        "TP_Loading_Truck_02B",
        "TP_Loading_Truck_02B_Addon",
        "TP_Cistern_01A",
        "TP_Cistern_01B",
        "TP_Cistern_01C",
        "TP_Bus_01A",
        "TP_Bus_01B",
        "TP_Bus_01C",
    ],
}
IN_USE = {"TP_Runway_01A", "TP_Runway_03A", "TP_Plane_05A"}
# The .glb files already converted into game/, measured to check this script's axes.
CALIBRATION = {
    "TP_Plane_05A": "game/assets/planes/tp_plane_05a.glb",
    "TP_Runway_01A": "game/assets/airside/tp_runway_01a.glb",
    "TP_Runway_03A": "game/assets/airside/tp_runway_03a.glb",
}


def log(*a):
    print(*a, flush=True)


def invalid(msg):
    log("PROBE_INVALID", msg)
    sys.exit(1)


def die(msg):
    log("CENSUS_FAIL", msg)
    sys.exit(1)


def b2g(v):
    """Blender -> Godot."""
    return Vector((v.x, v.z, -v.y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.cavity_type = "WORLD"
    sc.display.shading.show_object_outline = True
    sc.display.shading.show_shadows = False
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.color = (0.78, 0.82, 0.86)
    sc.display.shading.background_type = "WORLD"
    return sc


# ---------------------------------------------------------------- import and atlas


_images = {}


def atlas_material(name, psd, kind):
    mat = bpy.data.materials.get("CENSUS_" + name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("CENSUS_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEXTURES, psd), check_existing=True)
    if tex.image.size[0] == 0:
        die("atlas did not decode: %s" % psd)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.nodes.active = tex
    if kind == "glass":
        bsdf.inputs["Alpha"].default_value = 0.29
        mat.surface_render_method = "BLENDED"
    elif kind == "emissive":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def import_piece(sc, stem):
    path = os.path.join(MODELS, stem + ".fbx")
    if not os.path.exists(path):
        die("missing %s" % path)
    before = set(sc.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    bpy.context.view_layer.update()
    objs = [o for o in sc.objects if o not in before]
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        die("%s imported no mesh" % stem)
    src_mats = set()
    for o in meshes:
        for slot in o.material_slots:
            if slot.material is None:
                die("%s: %s has an empty material slot" % (stem, o.name))
            name = re.sub(r"\.\d{3}$", "", slot.material.name)
            if name not in MATERIALS:
                die("%s: unmapped material %s on %s" % (stem, name, o.name))
            src_mats.add(name)
            slot.material = atlas_material(name, *MATERIALS[name])
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    bpy.context.view_layer.update()
    mats = sorted({s.material.name for o in meshes for s in o.material_slots})
    imgs = sorted(i.name for i in bpy.data.images if i.users > 0 and i.size[0] > 0)
    if len(imgs) != len({MATERIALS[n][0] for n in src_mats}):
        die("%s: atlas rebind gave images %s for materials %s" % (stem, imgs, sorted(src_mats)))
    return objs, meshes, sorted(src_mats), mats, imgs


def world_verts(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        pts.extend(mw @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    return np.array([tuple(p) for p in pts])


def bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for k in range(3):
                lo[k] = min(lo[k], w[k])
                hi[k] = max(hi[k], w[k])
    return lo, hi


# ---------------------------------------------------------------- measures


def ceil1(x):
    return math.ceil(x * 10.0 - 1e-6) / 10.0


def part_verts(meshes, pattern):
    hits = [o for o in meshes if re.search(pattern, re.sub(r"\.\d{3}$", "", o.name))]
    return (world_verts(hits), hits) if hits else (None, [])


def plane_measure(verts, meshes):
    """The cockpit yoke (every plane and helicopter here has a Yoke part, a pair side by
    side on the bigger ones) sits on the centreline ahead of the middle: the horizontal
    axis it is farther off the middle along is the length axis, its side is the nose.
    The fuselage part's middle across is the centreline the doors are measured from.
    Fallback when a part is missing: the highest vertex (the fin tip) marks the tail."""
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    mid = (lo + hi) / 2.0
    fus, _ = part_verts(meshes, r"_Fuselage$")
    yoke, _ = part_verts(meshes, r"_Yoke(\.[LR])?$")
    if fus is not None and yoke is not None:
        ymid = yoke.mean(axis=0)
        axis = 1 if abs(ymid[1] - mid[1]) >= abs(ymid[0] - mid[0]) else 0
        tail_sign = -math.copysign(1.0, ymid[axis] - mid[axis])
        method = "fuselage+yoke"
    else:
        top = verts[np.argmax(verts[:, 2])]
        dx, dy = top[0] - mid[0], top[1] - mid[1]
        axis = 1 if abs(dy) >= abs(dx) else 0
        tail_sign = math.copysign(1.0, dy if axis == 1 else dx)
        method = "fin-tip fallback"
    other = 1 - axis
    centre = (fus.min(axis=0)[other] + fus.max(axis=0)[other]) / 2.0 if fus is not None else mid[other]
    length = hi[axis] - lo[axis]
    span = hi[other] - lo[other]
    height = hi[2] - lo[2]
    blender_nose = ("+" if tail_sign < 0 else "-") + "xy"[axis]
    godot_nose = {"+x": "+x", "-x": "-x", "+y": "-z", "-y": "+z"}[blender_nose]
    half_diag = 0.5 * math.hypot(length, span)
    reach = float(np.max(np.hypot(verts[:, 0] - mid[0], verts[:, 1] - mid[1])))
    nose_coord = lo[axis] if tail_sign > 0 else hi[axis]
    nose_from_origin = abs(nose_coord)
    doors = []
    for o in meshes:
        name = re.sub(r"\.\d{3}$", "", o.name)
        part = name.split("_", 3)[-1]
        if "Door" not in part or part in ("Bathroom_Door", "Cabin_Door"):
            continue
        dv = world_verts([o])
        dlo, dhi = dv.min(axis=0), dv.max(axis=0)
        dmid = (dlo + dhi) / 2.0
        aft = abs(dmid[axis] - nose_coord)
        # Godot side: + is the plane's left (port) when the nose points along +z.
        # Godot +x is the plane's left with the nose to +z (Blender -y, span along x).
        k = 1.0 if godot_nose == "+z" else float("nan")
        side = sorted(((dlo[other] - centre) * k, (dhi[other] - centre) * k))
        doors.append((part, aft, side, dlo[2] - lo[2], dhi[2] - dlo[2], dhi[axis] - dlo[axis]))
    return {
        "length": length,
        "span": span,
        "height": height,
        "nose_godot": godot_nose,
        "nose_blender": blender_nose,
        "method": method,
        "half_diag": half_diag,
        "reach": reach,
        "nose_from_origin": nose_from_origin,
        "doors": sorted(doors, key=lambda d: d[1]),
    }


def census_line(family, stem, meshes, src_mats, mats, imgs):
    verts = world_verts(meshes)
    lo_b, hi_b = Vector(verts.min(axis=0)), Vector(verts.max(axis=0))
    glo = b2g(lo_b)
    ghi = b2g(hi_b)
    # z flips sign, so swap its ends.
    glo.z, ghi.z = min(glo.z, ghi.z), max(glo.z, ghi.z)
    size = ghi - glo
    parts = sorted(re.sub(r"\.\d{3}$", "", o.name) for o in meshes)
    rec = {
        "family": family,
        "stem": stem,
        "size": size,
        "glo": glo,
        "ghi": ghi,
        "verts": len(verts),
        "parts": parts,
        "src_mats": src_mats,
        "lights": "Atlas_Lights_1A_D" in src_mats,
    }
    log(
        "CENSUS %-28s %-9s size_m x=%6.2f y=%5.2f z=%6.2f  x[%7.2f,%7.2f] y[%5.2f,%5.2f] z[%7.2f,%7.2f]"
        " verts=%d lights=%s%s"
        % (stem, family, size.x, size.y, size.z, glo.x, ghi.x, glo.y, ghi.y, glo.z, ghi.z, len(verts),
           "yes" if rec["lights"] else "no", " IN_USE" if stem in IN_USE else "")
    )
    log("  PARTS %s %s | fbx_mats=%s rebound=%s images=%s" % (stem, parts, src_mats, mats, imgs))
    if family == "planes":
        pm = plane_measure(verts, meshes)
        rec["plane"] = pm
        log(
            "  PLANE %s length=%.2f span=%.2f height=%.2f nose=godot%s (blender%s, %s)"
            " nose_from_origin=%.2f half_diag=%.2f (ceil %.1f) vertex_reach=%.2f (ceil %.1f)"
            % (stem, pm["length"], pm["span"], pm["height"], pm["nose_godot"], pm["nose_blender"],
               pm["method"], pm["nose_from_origin"], pm["half_diag"], ceil1(pm["half_diag"]),
               pm["reach"], ceil1(pm["reach"]))
        )
        for part, aft, side, sill, tall, wide in pm["doors"]:
            log("  DOOR %s %-14s middle %.2f m aft of nose, across %+.2f..%+.2f m (+ = port/left),"
                " sill %.2f m, %.2f m tall, %.2f m long" % (stem, part, aft, side[0], side[1], sill, tall, wide))
    return rec


# ---------------------------------------------------------------- cameras and proofs


def add_cube(sc, at):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    cube = bpy.context.active_object
    cube.name = "Ref_Cube_1m"
    m = bpy.data.materials.get("cube") or bpy.data.materials.new("cube")
    m.diffuse_color = (0.9, 0.15, 0.1, 1.0)
    cube.data.materials.append(m)
    return cube


def look(cam, loc, target):
    cam.location = loc
    d = (Vector(target) - Vector(loc)).normalized()
    if abs(d.z) > 0.99:
        cam.rotation_euler = (0.0 if d.z < 0 else math.pi, 0.0, 0.0)
    else:
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()


def fit_ortho(sc, cam, lo, hi, direction, res, pad=1.12):
    """Point the camera along -direction at the box and fit the ortho scale to it."""
    mid = (lo + hi) / 2.0
    dist = (hi - lo).length + 50.0
    look(cam, mid + direction.normalized() * dist, mid)
    inv = cam.matrix_world.inverted()
    pts = [inv @ Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    cam.location = cam.matrix_world @ Vector((cx, cy, 0.0))
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    aspect = res[0] / res[1]
    cam.data.ortho_scale = max(w, h * aspect) * pad
    cam.data.clip_end = dist * 2.0 + 100.0
    sc.render.resolution_x, sc.render.resolution_y = res
    bpy.context.view_layer.update()


def new_camera(sc):
    data = bpy.data.cameras.new("cam")
    data.type = "ORTHO"
    data.clip_start = 0.1
    cam = bpy.data.objects.new("cam", data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def ray_hit(sc, cam, target):
    dg = bpy.context.evaluated_depsgraph_get()
    fwd = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
    origin = Vector(target) - fwd * (Vector(target) - cam.matrix_world.translation).dot(fwd)
    hit, loc, n, i, ob, m = sc.ray_cast(dg, origin + fwd * cam.data.clip_start, fwd)
    return ob if hit else None


def in_frame(sc, cam, lo, hi):
    pts = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    uv = [world_to_camera_view(sc, cam, p) for p in pts]
    u0, u1 = min(p.x for p in uv), max(p.x for p in uv)
    v0, v1 = min(p.y for p in uv), max(p.y for p in uv)
    ok = u0 >= MARGIN and v0 >= MARGIN and u1 <= 1 - MARGIN and v1 <= 1 - MARGIN and all(p.z > 0 for p in uv)
    return ok, (u0, u1, v0, v1)


def prove_view(sc, cam, name, lo, hi, meshes, cube):
    clo, chi = bounds([cube])
    alo = Vector(map(min, lo, clo))
    ahi = Vector(map(max, hi, chi))
    ok, (u0, u1, v0, v1) = in_frame(sc, cam, alo, ahi)
    # A 6 x 6 x 6 grid of targets inside the bounds: thin open frames (the hangar add-on)
    # let a coarse grid's rays pass through.
    on_subject = 0
    steps = range(1, 7)
    for i in steps:
        for j in steps:
            for k in steps:
                t = lo + Vector(((hi.x - lo.x) * i / 7, (hi.y - lo.y) * j / 7, (hi.z - lo.z) * k / 7))
                on_subject += int(ray_hit(sc, cam, t) in meshes)
    # Rays at 120 of the subject's own vertices: an arch seen down its axis (the hangar
    # add-on's side view) lets every interior ray through but still shows its rim.
    verts = world_verts(meshes)
    pick = verts[np.linspace(0, len(verts) - 1, 120).astype(int)]
    on_verts = sum(int(ray_hit(sc, cam, Vector(tuple(v))) in meshes) for v in pick)
    cube_seen = ray_hit(sc, cam, cube.location) == cube
    log("  INFRAME %s u=%.3f..%.3f v=%.3f..%.3f rays_on_subject=%d/216 vertex_rays_on_subject=%d/120"
        " cube_visible=%s" % (name, u0, u1, v0, v1, on_subject, on_verts, cube_seen))
    on_subject += on_verts
    if not ok:
        invalid("%s: subject or cube leaves the frame" % name)
    if on_subject == 0:
        invalid("%s: no ray reaches the subject" % name)
    if not cube_seen:
        invalid("%s: the 1 m cube is hidden" % name)


def render(sc, path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def render_label(sc, text, path):
    """A strip of black text on white, rendered far below the subject."""
    bpy.ops.object.text_add(location=(0.0, 0.0, -5000.0))
    t = bpy.context.active_object
    t.data.body = text
    t.data.size = 0.8
    m = bpy.data.materials.new("label")
    m.diffuse_color = (0.02, 0.02, 0.02, 1.0)
    t.data.materials.append(m)
    bg = bpy.data.objects.new("label_bg", bpy.data.meshes.new("label_bg"))
    bg.data.from_pydata([(-30, -2, -5001), (60, -2, -5001), (60, 3, -5001), (-30, 3, -5001)], [], [(0, 1, 2, 3)])
    mb = bpy.data.materials.new("label_bg")
    mb.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    bg.data.materials.append(mb)
    sc.collection.objects.link(bg)
    cam = new_camera(sc)
    scale = 36.0
    cam.data.ortho_scale = scale
    look(cam, Vector((scale / 2.0 - 0.4, 0.25, -4990.0)), Vector((scale / 2.0 - 0.4, 0.25, -5000.0)))
    cam.data.clip_end = 50.0
    sc.render.resolution_x, sc.render.resolution_y = LABEL_RES
    old = sc.display.shading.show_object_outline
    sc.display.shading.show_object_outline = False
    render(sc, path)
    sc.display.shading.show_object_outline = old
    for o in (t, bg, cam):
        bpy.data.objects.remove(o, do_unlink=True)
    return path


def label_text(rec):
    s = rec["size"]
    if "plane" in rec:
        p = rec["plane"]
        return "%s  length %.1f  span %.1f  height %.1f m  nose %s  swing r %.1f m" % (
            rec["stem"], p["length"], p["span"], p["height"], p["nose_godot"], ceil1(p["half_diag"]))
    return "%s  %s  x %.1f  y(up) %.1f  z %.1f m%s" % (
        rec["stem"], rec["family"], s.x, s.y, s.z, "  lights" if rec["lights"] else "")


def piece_views(sc, rec, meshes):
    lo, hi = bounds(meshes)
    ext = hi - lo
    cube = add_cube(sc, Vector((hi.x + 1.5, lo.y - 1.5, lo.z + 0.5)))
    clo, chi = bounds([cube])
    alo = Vector(map(min, lo, clo))
    ahi = Vector(map(max, hi, chi))
    side = Vector((0, -1, 0)) if ext.x >= ext.y else Vector((1, 0, 0))
    views = {"iso": Vector((1.0, -1.0, 0.8)), "top": Vector((0, 0, 1)), "side": side}
    cam = new_camera(sc)
    paths = []
    for name, d in views.items():
        fit_ortho(sc, cam, alo, ahi, d, VIEW_RES)
        tag = "%s_%s" % (rec["stem"].lower(), name)
        prove_view(sc, cam, tag, lo, hi, meshes, cube)
        paths.append(render(sc, os.path.join(OUT, "pieces", tag + ".png")))
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.objects.remove(cube, do_unlink=True)
    label = render_label(sc, label_text(rec), os.path.join(OUT, "pieces", rec["stem"].lower() + "_label.png"))
    return label, paths


# ---------------------------------------------------------------- sheets


def load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def save_px(px, path):
    h, w = px.shape[:2]
    out = bpy.data.images.new("sheet", w, h, alpha=True)
    out.pixels = px.ravel()
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


def contact_sheets(family, tiles):
    vw, vh = VIEW_RES
    lw, lh = LABEL_RES
    gap = 6
    tile_h = lh + vh + gap
    pages = []
    for p0 in range(0, len(tiles), PER_PAGE):
        chunk = tiles[p0 : p0 + PER_PAGE]
        sheet = np.full((tile_h * len(chunk), lw, 4), 0.55, dtype=np.float32)
        sheet[..., 3] = 1.0
        for r, (label, views) in enumerate(chunk):
            top = sheet.shape[0] - r * tile_h  # numpy row 0 is the image bottom
            sheet[top - lh : top, 0:lw] = load_px(label)
            for c, v in enumerate(views):
                sheet[top - lh - vh : top - lh, c * vw : (c + 1) * vw] = load_px(v)
        path = os.path.join(OUT, "sheet_%s_%d.png" % (family, p0 // PER_PAGE + 1))
        save_px(sheet, path)
        log("SHEET %s pieces=%s" % (path, [os.path.basename(t[0]).replace("_label.png", "") for t in chunk]))
        pages.append(path)
    return pages


# ---------------------------------------------------------------- lineups


def text_at(sc, body, loc, size):
    bpy.ops.object.text_add(location=loc)
    t = bpy.context.active_object
    t.data.body = body
    t.data.size = size
    t.data.align_x = "CENTER"
    m = bpy.data.materials.get("lineup_text") or bpy.data.materials.new("lineup_text")
    m.diffuse_color = (0.02, 0.02, 0.02, 1.0)
    t.data.materials.append(m)
    return t


def lineup(name, stems, cols, gap, text_size, res, sort_key=None, recs=None):
    """Every piece at true scale in a grid, viewed from straight above, a label under each
    and a 1 m cube at the bottom left. Godot +z (Blender -y) points down the image."""
    sc = reset()
    groups = []
    for stem in stems:
        objs, meshes, *_ = import_piece(sc, stem)
        root = bpy.data.objects.new(stem + "_ROOT", None)
        sc.collection.objects.link(root)
        for o in objs:
            if o.parent is None:
                o.parent = root
        groups.append((stem, root, meshes))
    if sort_key is not None:
        groups.sort(key=lambda g: sort_key(recs[g[0]]))
    sizes = [bounds(m) for _, _, m in groups]
    cell_w = max(hi.x - lo.x for lo, hi in sizes) + gap
    cell_h = max(hi.y - lo.y for lo, hi in sizes) + gap + text_size * 2.0
    for i, ((stem, root, meshes), (lo, hi)) in enumerate(zip(groups, sizes)):
        r, c = i // cols, i % cols
        cx, cy = c * cell_w, -r * cell_h
        mid = (lo + hi) / 2.0
        root.location = Vector((cx - mid.x, cy - mid.y, -lo.z))
        bpy.context.view_layer.update()
        nlo, nhi = bounds(meshes)
        text_at(sc, stem.replace("TP_", ""), Vector((cx, nlo.y - text_size * 1.4, 0.05)), text_size)
    bpy.context.view_layer.update()
    allm = [m for _, _, ms in groups for m in ms]
    lo, hi = bounds(allm)
    cube = add_cube(sc, Vector((lo.x - 3.0, lo.y - text_size * 2.5, 0.5)))
    texts = [o for o in sc.objects if o.type == "FONT"]
    alo, ahi = bounds(allm + [cube] + texts)
    cam = new_camera(sc)
    fit_ortho(sc, cam, alo, ahi, Vector((0, 0, 1)), res, pad=1.08)
    ok, (u0, u1, v0, v1) = in_frame(sc, cam, alo, ahi)
    seen = []
    for stem, root, meshes in groups:
        plo, phi = bounds(meshes)
        hit = False
        for fx, fy in ((0.5, 0.5), (0.5, 0.25), (0.5, 0.75), (0.25, 0.5), (0.75, 0.5)):
            t = Vector((plo.x + (phi.x - plo.x) * fx, plo.y + (phi.y - plo.y) * fy, phi.z * 0.5))
            if ray_hit(sc, cam, t) in meshes:
                hit = True
                break
        seen.append(hit)
    cube_seen = ray_hit(sc, cam, cube.location) == cube
    px_per_m = res[0] / cam.data.ortho_scale
    log("INFRAME lineup_%s u=%.3f..%.3f v=%.3f..%.3f pieces_hit=%d/%d cube_visible=%s px_per_m=%.2f"
        % (name, u0, u1, v0, v1, sum(seen), len(seen), cube_seen, px_per_m))
    if not ok:
        invalid("lineup_%s leaves the frame" % name)
    if not all(seen):
        invalid("lineup_%s: no ray reaches %s" % (name, [g[0] for g, s in zip(groups, seen) if not s]))
    if not cube_seen:
        invalid("lineup_%s: the 1 m cube is hidden" % name)
    path = render(sc, os.path.join(OUT, "lineup_%s_top.png" % name))
    log("PLATE %s order=%s" % (path, [g[0] for g in groups]))
    return path


# ---------------------------------------------------------------- classes


def plane_classes(recs):
    planes = [r for r in recs.values() if "plane" in r and r["stem"].startswith("TP_Plane")]
    planes.sort(key=lambda r: max(r["plane"]["length"], r["plane"]["span"]))
    keys = [max(r["plane"]["length"], r["plane"]["span"]) for r in planes]
    gaps = sorted(range(1, len(keys)), key=lambda i: keys[i] - keys[i - 1], reverse=True)[:2]
    cuts = sorted(gaps)
    names = ("small", "medium", "large")
    log("CLASSES by the larger of length and span; cut at the two widest gaps:")
    for n, (a, b) in enumerate(zip([0] + cuts, cuts + [len(planes)])):
        members = planes[a:b]
        lo_k, hi_k = keys[a], keys[b - 1]
        worst = max(members, key=lambda r: r["plane"]["half_diag"])
        log(
            "  CLASS %-6s key %.1f..%.1f m  members=%s  max length %.1f span %.1f  stand swing radius %.1f m"
            " (half diagonal of %s)  exit spacing %d m"
            % (names[n], lo_k, hi_k, [r["stem"].replace("TP_Plane_", "") for r in members],
               max(r["plane"]["length"] for r in members), max(r["plane"]["span"] for r in members),
               ceil1(worst["plane"]["half_diag"]), worst["stem"], math.ceil(2.0 * ceil1(worst["plane"]["half_diag"])))
        )
    for i in cuts:
        log("  BOUNDARY between %.1f and %.1f m (gap %.1f m), midpoint %.1f m"
            % (keys[i - 1], keys[i], keys[i] - keys[i - 1], (keys[i - 1] + keys[i]) / 2.0))


# ---------------------------------------------------------------- calibration


def calibrate(recs):
    for stem, rel in CALIBRATION.items():
        sc = reset()
        bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, *rel.split("/")))
        bpy.context.view_layer.update()
        meshes = [o for o in sc.objects if o.type == "MESH"]
        v = world_verts(meshes)
        glo, ghi = b2g(Vector(v.min(axis=0))), b2g(Vector(v.max(axis=0)))
        glo.z, ghi.z = min(glo.z, ghi.z), max(glo.z, ghi.z)
        r = recs[stem]
        d = max(max(abs(a - b) for a, b in zip(glo, r["glo"])), max(abs(a - b) for a, b in zip(ghi, r["ghi"])))
        log("CALIBRATE %s glb x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] vs fbx; max bound difference %.3f m %s"
            % (stem, glo.x, ghi.x, glo.y, ghi.y, glo.z, ghi.z, d, "OK" if d < 0.02 else "MISMATCH"))
        if d >= 0.02:
            die("calibration mismatch for %s" % stem)
    p = recs["TP_Plane_05A"]["plane"]
    # PlaneView model_offset (0, 0, 1.7): the stand point is 1.7 m behind the glb origin.
    nose = p["nose_from_origin"] + 1.7
    tail = p["length"] - p["nose_from_origin"] - 1.7
    game = math.hypot(max(nose, tail), p["span"] / 2.0)
    log("CALIBRATE swing TP_Plane_05A: about the game's stand point nose %.2f tail %.2f half-span %.2f"
        " -> %.3f (ceil %.1f; stand_placement.gd NOSE_M 14.7 TAIL_M 14.85 HALF_SPAN_M 14.2 SWING_RADIUS_M 20.6);"
        " about the box middle %.3f (ceil %.1f)"
        % (nose, tail, p["span"] / 2.0, game, ceil1(game), p["half_diag"], ceil1(p["half_diag"])))


# ---------------------------------------------------------------- main


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    table_only = "--table-only" in args
    os.makedirs(os.path.join(OUT, "pieces"), exist_ok=True)
    recs = {}
    tiles = {f: [] for f in FAMILIES}
    for family, stems in FAMILIES.items():
        for stem in stems:
            sc = reset()
            objs, meshes, src_mats, mats, imgs = import_piece(sc, stem)
            rec = census_line(family, stem, meshes, src_mats, mats, imgs)
            recs[stem] = rec
            if not table_only:
                tiles[family].append(piece_views(sc, rec, meshes))
    calibrate(recs)
    plane_classes(recs)
    if table_only:
        log("CENSUS done %d pieces (table only)" % len(recs))
        return
    plates = []
    for family in FAMILIES:
        plates += contact_sheets(family, tiles[family])
    plates.append(lineup("aircraft", FAMILIES["planes"], 6, 8.0, 2.2, (2400, 1800),
                         sort_key=lambda r: r["plane"]["length"], recs=recs))
    plates.append(lineup("runway", FAMILIES["runway"], 5, 10.0, 4.0, (2400, 1500)))
    log("CENSUS done %d pieces, %d sheets and lineups" % (len(recs), len(plates)))


# plane_offsets.py imports this file for plane_measure() and its helpers.
if __name__ == "__main__":
    main()
