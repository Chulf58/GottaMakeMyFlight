"""Plates of the surface car park tp_parking_01a.glb as written, with its paved apron
TP_Parking_01A_Apron (tools/blender/landside/parking_01a_apron.py, board 297c9eb8).

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 --python 'C:\\...\\tools\\blender\\landside\\parking_01a_plates.py'

Reads the written game/assets/landside/tp_parking_01a.glb (never the build scene) and,
for the in-place shots, game/assets/buildings/tp_airport_site.glb. Writes PNGs and one
contact sheet to tools/blender/out/car-park-lot0/blender/ (gitignored):
- six orthographic views of the whole asset along the axes at true scale, with a 1 m
  reference cube in front of the apron;
- the apron alone on the six axes with the 1 m cube;
- in place as main.tscn has it (the site at z -80, the lot turned and moved as
  LandsidePlaces.lot_transform does for lot spot 0, a lawn plane at y -0.1): low from
  the road side across the apron, and a distance shot.
Every plate projects its subject's bounds into the frame (with a margin) and casts rays
from the camera into the subject before it is saved; on a failure it prints
PROBE_INVALID and exits 1.

Axes: the glTF importer turns Godot/glTF (x, y, z) into Blender (x, -z, y).
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
GLB = os.path.join(REPO, "game", "assets", "landside", "tp_parking_01a.glb")
SITE = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_site.glb")
OUT = os.path.join(REPO, "tools", "blender", "out", "car-park-lot0", "blender")
APRON = "TP_Parking_01A_Apron"
MARGIN = 0.02
RES = (1600, 1000)
# main.tscn: the site at Godot z -80; lot spot 0 (starter_landside.tres) centre x 31.7,
# its gate at z -37.5, the lot's barrier line local x -7, turned -90 degrees about y.
SITE_Z = -80.0
LOT_ORIGIN = (31.7, 0.0, -30.5)
LOT_YAW = -math.pi / 2.0


def g2b(x, y, z):
    """Godot -> Blender."""
    return Vector((x, -z, y))


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
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.color = (0.78, 0.82, 0.86)
    sc.display.shading.background_type = "WORLD"
    return sc


def load_lot(sc):
    before = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=GLB)
    bpy.context.view_layer.update()
    lot = [o for o in sc.objects if o not in before]
    meshes = [o for o in lot if o.type == "MESH"]
    mats = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    imgs = sorted(i.name for i in bpy.data.images if i.users > 0)
    print("PLATE_SCENE meshes=%s materials=%s images=%s" % (sorted(o.name for o in meshes), mats, imgs), flush=True)
    if APRON not in [o.name for o in meshes] or not imgs:
        invalid("no %s or no texture image in %s" % (APRON, GLB))
    return lot, meshes


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


def add_cube(at):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    cube = bpy.context.active_object
    cube.name = "Ref_Cube_1m"
    m = bpy.data.materials.new("cube")
    m.diffuse_color = (0.9, 0.15, 0.1, 1.0)
    cube.data.materials.append(m)
    return cube


def camera(sc, loc, target, ortho=None, lens=35.0):
    data = bpy.data.cameras.new("cam")
    if ortho is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    else:
        data.lens = lens
    data.clip_start = 0.1
    data.clip_end = 2000.0
    cam = bpy.data.objects.new("cam", data)
    sc.collection.objects.link(cam)
    cam.location = loc
    d = (Vector(target) - Vector(loc)).normalized()
    if abs(d.z) > 0.99:
        cam.rotation_euler = (0.0 if d.z < 0 else math.pi, 0.0, 0.0)
    else:
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    bpy.context.view_layer.update()
    return cam


def ray_to(sc, cam, target):
    dg = bpy.context.evaluated_depsgraph_get()
    origin = cam.matrix_world.translation
    if cam.data.type == "ORTHO":
        fwd = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
        origin = Vector(target) - fwd * (Vector(target) - origin).dot(fwd)
    d = (Vector(target) - origin).normalized()
    hit, loc, n, i, ob, m = sc.ray_cast(dg, origin + d * cam.data.clip_start, d)
    return hit, ob


def prove(sc, cam, name, lo, hi, subjects):
    """The bounds project inside the frame with a margin, and of 27 rays into the bounds
    (kept low, 0.2, 0.6 and 1.5 m over its bottom, since the subject is mostly a slab 0.2 m
    high) some first hit a subject (the rest may pass by it, onto the ground or nothing)."""
    pts = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    uv = [world_to_camera_view(sc, cam, p) for p in pts]
    umin, umax = min(p.x for p in uv), max(p.x for p in uv)
    vmin, vmax = min(p.y for p in uv), max(p.y for p in uv)
    inside = umin >= MARGIN and vmin >= MARGIN and umax <= 1 - MARGIN and vmax <= 1 - MARGIN
    inside = inside and all(p.z > 0 for p in uv)
    on_subject = 0
    for i in (1, 2, 3):
        for j in (1, 2, 3):
            for k in (1, 2, 3):
                t = lo + Vector(((hi.x - lo.x) * i / 4, (hi.y - lo.y) * j / 4, min((0.2, 0.6, 1.5)[k - 1], (hi.z - lo.z) * k / 4)))
                hit, ob = ray_to(sc, cam, t)
                on_subject += int(hit and ob in subjects)
    print("INFRAME %s u=%.3f..%.3f v=%.3f..%.3f rays_on_subject=%d/27" % (name, umin, umax, vmin, vmax, on_subject), flush=True)
    if not inside:
        invalid("%s: subject leaves the frame" % name)
    if on_subject == 0:
        invalid("%s: no ray reaches the subject" % name)


def render(sc, name):
    path = os.path.join(OUT, name + ".png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PLATE saved %s" % path, flush=True)
    return path


def six_axis(plates, only=None, prefix=""):
    sc = reset()
    lot, meshes = load_lot(sc)
    if only is not None:
        for o in [o for o in meshes if o.name != only]:
            bpy.data.objects.remove(o, do_unlink=True)
        meshes = [o for o in sc.objects if o.type == "MESH"]
    lo, hi = bounds(meshes)
    print("BOUNDS_WRITTEN %s size_m=(%.3f, %.3f, %.3f)" % (only or "asset", *(hi - lo)), flush=True)
    # In front of the apron (Godot local x -11), beside its middle.
    cube = add_cube(g2b(-11.0, 0.5, 0.0))
    lo2, hi2 = bounds(meshes + [cube])
    mid = (lo2 + hi2) / 2.0
    ext = hi2 - lo2
    aspect = RES[0] / RES[1]
    views = {
        "axis_pos_x": Vector((1, 0, 0)),
        "axis_neg_x": Vector((-1, 0, 0)),
        "axis_pos_y": Vector((0, 1, 0)),
        "axis_neg_y": Vector((0, -1, 0)),
        "axis_top": Vector((0, 0, 1)),
        "axis_bottom": Vector((0, 0, -1)),
    }
    for name, d in views.items():
        if abs(d.z) > 0.5:
            scale = max(ext.x, ext.y * aspect) * 1.12
        else:
            horiz = ext.y if abs(d.x) > 0.5 else ext.x
            scale = max(horiz, ext.z * aspect) * 1.12
        cam = camera(sc, mid + d * 200.0, mid, ortho=scale)
        prove(sc, cam, prefix + name, lo2, hi2, meshes)
        plates.append(render(sc, prefix + name))
        bpy.data.objects.remove(cam, do_unlink=True)


def in_place(plates):
    """The lot and the site as main.tscn places them, with a lawn plane."""
    sc = reset()
    before = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=SITE)
    for o in sc.objects:
        if o not in before and o.parent is None:
            o.location += g2b(0.0, 0.0, SITE_Z)
    lot, meshes = load_lot(sc)
    pivot = bpy.data.objects.new("LotPivot", None)
    sc.collection.objects.link(pivot)
    pivot.location = g2b(*LOT_ORIGIN)
    pivot.rotation_euler = (0.0, 0.0, LOT_YAW)
    for o in lot:
        if o.parent is None:
            o.parent = pivot
    bpy.ops.mesh.primitive_plane_add(size=400.0, location=g2b(30.0, -0.1, -40.0))
    lawn = bpy.data.materials.new("lawn")
    lawn.diffuse_color = (0.35, 0.6, 0.3, 1.0)
    bpy.context.active_object.data.materials.append(lawn)
    bpy.context.view_layer.update()
    apron = [o for o in meshes if o.name == APRON]
    lo, hi = bounds(apron)
    print("BOUNDS_IN_PLACE apron godot x %.2f..%.2f z %.2f..%.2f y %.3f..%.3f"
          % (lo.x, hi.x, -hi.y, -lo.y, lo.z, hi.z), flush=True)
    add_cube(g2b(22.5, 0.4, -39.0))
    shots = {
        # Low from over the road, a little west of the middle, across the apron to the gate.
        "in_place_low": (g2b(29.0, 3.0, -53.0), g2b(31.7, 0.2, -38.6), 24.0),
        # From over the far side of the road, the lot, its apron and the sidewalk.
        "in_place_distance": (g2b(10.0, 22.0, -85.0), g2b(31.7, 0.2, -32.0), 50.0),
    }
    for name, (loc, target, lens) in shots.items():
        cam = camera(sc, loc, target, lens=lens)
        prove(sc, cam, name, lo, hi, apron)
        plates.append(render(sc, name))
        bpy.data.objects.remove(cam, do_unlink=True)


def contact_sheet(paths):
    tile_w, tile_h, cols = 640, 400, 4
    rows = (len(paths) + cols - 1) // cols
    sheet = np.ones((rows * tile_h, cols * tile_w, 4), dtype=np.float32)
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        ys = (np.arange(tile_h) * h / tile_h).astype(int)
        xs = (np.arange(tile_w) * w / tile_w).astype(int)
        r, c = i // cols, i % cols
        y0 = (rows - 1 - r) * tile_h
        sheet[y0 : y0 + tile_h, c * tile_w : (c + 1) * tile_w] = px[ys][:, xs]
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
    six_axis(plates, only=APRON, prefix="apron_")
    in_place(plates)
    contact_sheet(plates)
    print("PLATES done %d" % len(plates), flush=True)


main()
