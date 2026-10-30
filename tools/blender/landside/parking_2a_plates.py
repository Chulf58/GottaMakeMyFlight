"""Plates of the multi-storey car park tc_parking_2a.glb as written, with the level way from
its entrance to the ground-floor stalls (tools/blender/landside/parking_2a_entrance.py).

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 --python 'C:\\...\\tools\\blender\\landside\\parking_2a_plates.py'

Reads the written game/assets/landside/tc_parking_2a.glb (never the build scene) and, for
the before/after close-ups, the vendor Parking_2A.fbx. Writes PNGs and one contact sheet to
tools/blender/out/parking_2a/plates/ (gitignored):
- six orthographic views along the axes at true scale, with a 1 m reference cube beside
  the front-right corner;
- a distance shot from the road side;
- a plan section of the ground floor (an orthographic camera under the first deck);
- the gap close up from the stalls and from the ramp landing, after and before the edit.
Every plate projects its subject's bounds into the frame (with a margin) and casts a ray
from the camera to the subject's middle before it is saved; on a failure it prints
PROBE_INVALID and exits 1.

Axes: the glTF importer turns Godot/glTF local (x, y, z) into Blender (x, -z, y), so the
building's front (Godot z -26) is Blender y +26.
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
GLB = os.path.join(REPO, "game", "assets", "landside", "tc_parking_2a.glb")
FBX = "C:\\Users\\chulf\\Assets new\\Toon Series\\Toon City\\Models\\Parking_2A.fbx"
OUT = os.path.join(REPO, "tools", "blender", "out", "parking_2a", "plates")
MARGIN = 0.02
RES = (1600, 1000)


def g2b(x, y, z):
    """Godot local -> Blender world."""
    return Vector((x, -z, y))


# The gap in Godot local: kerb x 1.0..1.7, z -21.9..-17.9, floor 0.3..0.43.
GAP_LO = g2b(1.0, 0.3, -17.9)
GAP_HI = g2b(1.7, 0.45, -21.9)
GAP_MID = g2b(1.35, 0.36, -19.9)


def invalid(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


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
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.color = (0.78, 0.82, 0.86)
    sc.display.shading.background_type = "WORLD"
    return sc


def load(kind):
    sc = reset()
    if kind == "glb":
        bpy.ops.import_scene.gltf(filepath=GLB)
    else:
        bpy.ops.import_scene.fbx(filepath=FBX)
        # The FBX keeps its vendor material; give it the same texture so before and after
        # compare on colour as well as shape.
        img = bpy.data.images.load(os.path.join(REPO, "game", "assets", "textures", "tc_building_17a_d.png"))
        for o in sc.objects:
            for s in getattr(o, "material_slots", []):
                m = s.material
                m.use_nodes = True
                tex = m.node_tree.nodes.new("ShaderNodeTexImage")
                tex.image = img
                bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                # Workbench draws the active image node in TEXTURE colour mode.
                m.node_tree.nodes.active = tex
    bpy.context.view_layer.update()
    meshes = [o for o in sc.objects if o.type == "MESH"]
    mats = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    imgs = sorted(i.name for i in bpy.data.images if i.users > 0)
    print("PLATE_SCENE %s meshes=%d materials=%s images=%s" % (kind, len(meshes), mats, imgs), flush=True)
    if not meshes or not imgs:
        invalid("%s: no mesh or no texture image" % kind)
    return sc, meshes


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


def add_cube(sc, at):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    cube = bpy.context.active_object
    cube.name = "Ref_Cube_1m"
    m = bpy.data.materials.new("cube")
    m.diffuse_color = (0.9, 0.15, 0.1, 1.0)
    cube.data.materials.append(m)
    return cube


def camera(sc, loc, target, ortho=None, lens=35.0, clip_start=0.1):
    data = bpy.data.cameras.new("cam")
    if ortho is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    else:
        data.lens = lens
    data.clip_start = clip_start
    data.clip_end = 2000.0
    cam = bpy.data.objects.new("cam", data)
    sc.collection.objects.link(cam)
    cam.location = loc
    d = (Vector(target) - Vector(loc)).normalized()
    if abs(d.z) > 0.99:
        # Straight down (or up): the long side of the building (Blender y) across the frame.
        cam.rotation_euler = (0.0 if d.z < 0 else math.pi, 0.0, math.pi / 2.0)
    else:
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    bpy.context.view_layer.update()
    return cam


def prove(sc, cam, name, lo, hi, target, subjects=None):
    """The subject's bounds project inside the frame with a margin, and a ray from the
    camera toward `target` is not blocked: it lands within 0.6 m of the target, or, for
    a whole-building view (`subjects` given), on the building itself."""
    pts = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    uv = [world_to_camera_view(sc, cam, p) for p in pts]
    umin, umax = min(p.x for p in uv), max(p.x for p in uv)
    vmin, vmax = min(p.y for p in uv), max(p.y for p in uv)
    ok = umin >= MARGIN and vmin >= MARGIN and umax <= 1 - MARGIN and vmax <= 1 - MARGIN
    ok = ok and all(p.z > 0 for p in uv)
    if not ok:
        print("INFRAME %s u=%.3f..%.3f v=%.3f..%.3f" % (name, umin, umax, vmin, vmax), flush=True)
        invalid("%s: subject leaves the frame" % name)
    if subjects is None:
        hit, ob, reach = ray_to(sc, cam, target)
        print(
            "INFRAME %s u=%.3f..%.3f v=%.3f..%.3f occlusion_hit=%s hit_to_target_m=%.2f"
            % (name, umin, umax, vmin, vmax, ob.name if hit else None, reach),
            flush=True,
        )
        if not hit or reach > 0.6:
            invalid("%s: the ray to the subject stops %.2f m short (on %s)" % (name, reach, ob.name if hit else None))
        return
    # A whole-building view: rays at 27 points inside the bounds; each first hit must be
    # the building (or nothing, through an open storey), and some must hit it.
    on_subject = 0
    others = []
    for i in (1, 2, 3):
        for j in (1, 2, 3):
            for k in (1, 2, 3):
                t = lo + Vector(((hi.x - lo.x) * i / 4, (hi.y - lo.y) * j / 4, (hi.z - lo.z) * k / 4))
                hit, ob, reach = ray_to(sc, cam, t)
                if hit and ob in subjects:
                    on_subject += 1
                elif hit:
                    others.append(ob.name)
    print(
        "INFRAME %s u=%.3f..%.3f v=%.3f..%.3f rays_on_subject=%d/27 rays_on_other=%s"
        % (name, umin, umax, vmin, vmax, on_subject, others),
        flush=True,
    )
    if on_subject == 0 or others:
        invalid("%s: rays reach the building %d times, other objects %s" % (name, on_subject, others))


def ray_to(sc, cam, target):
    """The first hit of a ray from the camera toward `target` (an orthographic camera
    shoots along its view axis from its image plane): (hit, object, metres from target)."""
    dg = bpy.context.evaluated_depsgraph_get()
    origin = cam.matrix_world.translation
    if cam.data.type == "ORTHO":
        fwd = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
        origin = Vector(target) - fwd * (Vector(target) - origin).dot(fwd)
    d = (Vector(target) - origin).normalized()
    hit, loc, n, i, ob, m = sc.ray_cast(dg, origin + d * cam.data.clip_start, d)
    return hit, ob, ((loc - Vector(target)).length if hit else float("inf"))


def render(sc, name):
    path = os.path.join(OUT, name + ".png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PLATE saved %s" % path, flush=True)
    return path


def six_axis(plates):
    sc, meshes = load("glb")
    lo, hi = bounds(meshes)
    size = hi - lo
    print("BOUNDS_WRITTEN size_m=(%.3f, %.3f, %.3f)" % tuple(size), flush=True)
    # Beside the front-right corner (Godot x 13.5, z -27).
    cube = add_cube(sc, g2b(13.5, 0.5, -27.0))
    lo2, hi2 = bounds(meshes + [cube])
    mid = (lo2 + hi2) / 2.0
    far = 200.0
    views = {
        "axis_pos_x": Vector((1, 0, 0)),
        "axis_neg_x": Vector((-1, 0, 0)),
        "axis_front": Vector((0, 1, 0)),  # Blender +y = Godot front (-z), the road side
        "axis_back": Vector((0, -1, 0)),
        "axis_top": Vector((0, 0, 1)),
        "axis_bottom": Vector((0, 0, -1)),
    }
    ext = hi2 - lo2
    aspect = RES[0] / RES[1]
    for name, d in views.items():
        if abs(d.z) > 0.5:
            # Top and bottom: turned so the long side (Blender y) runs across the frame.
            scale = max(ext.y, ext.x * aspect) * 1.12
        else:
            horiz = ext.y if abs(d.x) > 0.5 else ext.x
            scale = max(horiz, ext.z * aspect) * 1.12
        cam = camera(sc, mid + d * far, mid, ortho=scale)
        prove(sc, cam, name, lo2, hi2, mid, subjects=meshes)
        plates.append(render(sc, name))
        bpy.data.objects.remove(cam, do_unlink=True)


def distance(plates):
    sc, meshes = load("glb")
    lo, hi = bounds(meshes)
    cube = add_cube(sc, g2b(13.5, 0.5, -27.0))
    target = g2b(0.0, 8.0, 0.0)
    cam = camera(sc, g2b(55.0, 40.0, -110.0), target, lens=50.0)
    prove(sc, cam, "distance", lo, hi, g2b(0.0, 14.0, -26.0), subjects=meshes)
    plates.append(render(sc, "distance"))


def section(plates):
    sc, meshes = load("glb")
    cube = add_cube(sc, g2b(-6.5, 0.8, -24.5))
    # Under the first deck (its underside is about 5 m up), looking down at the front half
    # of the ground floor: the entrance, the ramp foot, the gap and the stalls.
    target = g2b(0.0, 0.3, -16.0)
    cam = camera(sc, g2b(0.0, 4.6, -16.0), target, ortho=26.0, clip_start=0.05)
    prove(sc, cam, "ground_plan_section", GAP_LO, GAP_HI, GAP_MID)
    plates.append(render(sc, "ground_plan_section"))


def close_ups(plates, kind):
    sc, meshes = load(kind)
    shots = {
        # From the stalls, looking east through the gap at the ramp landing.
        "gap_from_stalls": (g2b(-5.0, 1.7, -19.0), GAP_MID),
        # From the ramp landing just inside the entrance, looking west at the gap.
        "gap_from_landing": (g2b(6.5, 1.8, -16.5), GAP_MID),
    }
    for name, (loc, target) in shots.items():
        cam = camera(sc, loc, target, lens=24.0)
        prove(sc, cam, "%s_%s" % (name, kind), GAP_LO, GAP_HI, GAP_MID)
        plates.append(render(sc, "%s_%s" % (name, "after" if kind == "glb" else "before")))
        bpy.data.objects.remove(cam, do_unlink=True)


def contact_sheet(paths):
    tile_w, tile_h, cols = 640, 400, 3
    rows = (len(paths) + cols - 1) // cols
    sheet = np.ones((rows * tile_h, cols * tile_w, 4), dtype=np.float32)
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        ys = (np.arange(tile_h) * h / tile_h).astype(int)
        xs = (np.arange(tile_w) * w / tile_w).astype(int)
        tile = px[ys][:, xs]
        r, c = i // cols, i % cols
        # Blender pixel rows run bottom-up; the sheet's first row is the top.
        y0 = (rows - 1 - r) * tile_h
        sheet[y0 : y0 + tile_h, c * tile_w : (c + 1) * tile_w] = tile
        bpy.data.images.remove(img)
    out = bpy.data.images.new("sheet", cols * tile_w, rows * tile_h, alpha=True)
    out.pixels = sheet.ravel()
    path = os.path.join(OUT, "contact_sheet.png")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print("SHEET %s order=%s" % (path, [os.path.basename(p) for p in paths]), flush=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    plates = []
    six_axis(plates)
    distance(plates)
    section(plates)
    close_ups(plates, "glb")
    close_ups(plates, "fbx")
    contact_sheet(plates)
    print("PLATES done %d" % len(plates), flush=True)


main()
