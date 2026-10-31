"""Six-axis orthographic plates of the WRITTEN crow .glb (game/assets/birds/tfp_crow_01.glb)
at true scale beside a 1 m reference cube, in a perched pose (idle_01) and a flight pose
(fly), plus a distance shot from the game camera's default distance and pitch.

Run from WSL:

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\...\\tools\\blender\\birds_plates.py'

Plates and a contact sheet go to tools/blender/out/birds/ (gitignored). Every plate first
projects the crow's and the cube's bounds into the camera: either one outside the frame
(with a margin) or the two overlapping on screen prints PROBE_INVALID and exits 1.
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(REPO, "game", "assets", "birds", "tfp_crow_01.glb")
OUT = os.path.join(REPO, "tools", "blender", "out", "birds")
MARGIN = 0.03
TILE = 640
# Cube beside the bird on the diagonal, so no axis view puts one behind the other.
CUBE_AT = Vector((1.6, 1.6, 0.5))
# The game camera's default: 80 m from its target, pitch about 50 degrees below level
# (TycoonCamera home_distance 80; pitch eases 35 -> 65 degrees with distance), fov 55.
GAME_DISTANCE = 80.0
GAME_PITCH = math.radians(50.0)
GAME_FOV = math.radians(55.0)
VIEWS = {
    "front": Vector((0, -1, 0)),
    "back": Vector((0, 1, 0)),
    "left": Vector((-1, 0, 0)),
    "right": Vector((1, 0, 0)),
    "top": Vector((0, 0, 1)),
    "bottom": Vector((0, 0, -1)),
}


def log(*a):
    print("PLATE", *a, flush=True)


def invalid(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


def world_box(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        ev = o.evaluated_get(deps)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def corners(lo, hi):
    return [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]


def screen_rect(cam, lo, hi):
    scene = bpy.context.scene
    ps = [world_to_camera_view(scene, cam, c) for c in corners(lo, hi)]
    return min(p.x for p in ps), min(p.y for p in ps), max(p.x for p in ps), max(p.y for p in ps), min(p.z for p in ps)


def prove(cam, name, boxes):
    rects = {}
    for tag, (lo, hi) in boxes.items():
        x0, y0, x1, y1, depth = screen_rect(cam, lo, hi)
        rects[tag] = (x0, y0, x1, y1)
        log("INFRAME %s %s rect=(%.3f, %.3f)-(%.3f, %.3f) min_depth=%.2f" % (name, tag, x0, y0, x1, y1, depth))
        if x0 < MARGIN or y0 < MARGIN or x1 > 1 - MARGIN or y1 > 1 - MARGIN or depth <= 0:
            invalid("%s: %s outside the frame" % (name, tag))
    if "crow" in rects and "cube" in rects:
        a, b = rects["crow"], rects["cube"]
        overlap = not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])
        log("OCCLUSION %s crow_cube_overlap=%s" % (name, overlap))
        if overlap:
            invalid("%s: the cube and the crow overlap on screen" % name)
    return rects


def render(path, w, h):
    scene = bpy.context.scene
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("WROTE %s" % os.path.relpath(path, REPO).replace("\\", "/"))


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_object_outline = True
    shading.show_cavity = False
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("plates")
    scene.world = world
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0.62, 0.72, 0.62)
    arm = next(o for o in scene.objects if o.type == "ARMATURE")
    # The glTF importer adds an "Icosphere" bone display shape; it is not in the file.
    meshes = [o for o in scene.objects if o.type == "MESH" and o.name.startswith("TFP_Crow")]
    imgs = [i.name for i in bpy.data.images]
    mats = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    log("REREAD meshes=%s materials=%s images=%s actions=%s" % (sorted(o.name for o in meshes), mats, imgs, sorted(a.name for a in bpy.data.actions)))
    if not imgs or not mats:
        invalid("the re-read glb has no atlas image or material")
    for o in meshes:
        o.hide_render = o.name != "TFP_Crow_01A"
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=CUBE_AT)
    cube = bpy.context.active_object
    cube.name = "Reference_Cube_1m"
    cmat = bpy.data.materials.new("cube")
    cmat.diffuse_color = (0.85, 0.55, 0.25, 1.0)
    cube.data.materials.append(cmat)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return arm, [m for m in meshes if m.name == "TFP_Crow_01A"], cube, cam


def pose(arm, clip, frac):
    act = bpy.data.actions.get(clip) or next(a for a in bpy.data.actions if a.name.startswith(clip))
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(arm.animation_data, "action_slot") and act.slots:
        arm.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    bpy.context.scene.frame_set(int(round(f0 + (f1 - f0) * frac)))
    bpy.context.view_layer.update()


def aim(cam, at, direction, dist):
    cam.location = at + direction * dist
    forward = -direction
    cam.rotation_euler = forward.to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()


def six_axis(arm, crow, cube, cam, clip, frac):
    pose(arm, clip, frac)
    c_lo, c_hi = world_box(crow)
    k_lo, k_hi = world_box([cube])
    lo = Vector(map(min, c_lo, k_lo))
    hi = Vector(map(max, c_hi, k_hi))
    mid = (lo + hi) / 2
    size = c_hi - c_lo
    log("POSE %s frac=%.2f crow_size_m=(%.3f, %.3f, %.3f) crow_min_z=%.3f" % (clip, frac, size.x, size.y, size.z, c_lo.z))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = (hi - lo).length * 1.1
    paths = []
    for name, d in VIEWS.items():
        aim(cam, mid, d, 10.0)
        prove(cam, "%s_%s" % (clip, name), {"crow": (c_lo, c_hi), "cube": (k_lo, k_hi)})
        p = os.path.join(OUT, "six_axis_%s_%s.png" % (clip, name))
        render(p, TILE, TILE)
        paths.append(p)
    return paths


def distance_shot(arm, crow, cube, cam):
    pose(arm, "idle_01", 0.0)
    c_lo, c_hi = world_box(crow)
    k_lo, k_hi = world_box([cube])
    target = (c_lo + c_hi) / 2
    d = Vector((0.0, -math.cos(GAME_PITCH), math.sin(GAME_PITCH)))
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = GAME_FOV
    aim(cam, target, d, GAME_DISTANCE)
    rects = prove(cam, "distance", {"crow": (c_lo, c_hi), "cube": (k_lo, k_hi)})
    r = rects["crow"]
    log("DISTANCE crow_px_at_1080p w=%.1f h=%.1f (camera %.0f m, pitch %.0f deg, fov %.0f deg)" % ((r[2] - r[0]) * 1920, (r[3] - r[1]) * 1080, GAME_DISTANCE, math.degrees(GAME_PITCH), math.degrees(GAME_FOV)))
    p = os.path.join(OUT, "distance_game_camera.png")
    render(p, 1920, 1080)
    return p


def contact_sheet(paths, cols, out):
    imgs = [bpy.data.images.load(p) for p in paths]
    w, h = imgs[0].size
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, img in enumerate(imgs):
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        r = rows - 1 - i // cols
        c = i % cols
        sheet[r * h : (r + 1) * h, c * w : (c + 1) * w] = px
    out_img = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    out_img.pixels = sheet.ravel()
    out_img.filepath_raw = out
    out_img.file_format = "PNG"
    out_img.save()
    log("SHEET %s tiles=%d" % (os.path.relpath(out, REPO).replace("\\", "/"), len(paths)))


def main():
    os.makedirs(OUT, exist_ok=True)
    arm, crow, cube, cam = setup()
    perched = six_axis(arm, crow, cube, cam, "idle_01", 0.0)
    flying = six_axis(arm, crow, cube, cam, "fly", 0.25)
    contact_sheet(perched + flying, 6, os.path.join(OUT, "six_axis_sheet.png"))
    distance_shot(arm, crow, cube, cam)
    log("DONE")


main()
