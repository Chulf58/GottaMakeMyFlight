"""Plates for the extracted Toon terminal shell, rendered from the WRITTEN .glb files.

Run from WSL (Blender sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python \
        'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\terminal_shell\\render_shell_plates.py'

Optional after `--`: `--shell <path.glb>` (default game/assets/buildings/tp_airport_shell.glb).
Plates go to tools/blender/out/toon_shell_extract/ (gitignored). Workbench with back-face
culling on, because the game's toon surface shader culls back faces. Every plate first
proves its subject and its 1 m reference cube are in frame and that the cube is the first
thing a ray from the camera hits; otherwise it prints PROBE_INVALID and exits 1.
Coordinates in this file are Godot world coordinates with the terminal at (0, 0, -80).
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = "C:\\Users\\chulf\\Gotta-make-my-flight"
SRC = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_01a.glb")
SHELL = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_shell.glb")
OUT = os.path.join(REPO, "tools", "blender", "out", "toon_shell_extract")
OFFSET_Z = -80.0


def b(x, y, z):
    return Vector((x, -(z - OFFSET_Z), y))


def fail(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


def load(path, outline=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    # Workbench object outlines are drawn per object, so they would mark every node split
    # and say nothing about the game's inverted-hull outline: off on every plate.
    sh.show_object_outline = outline
    sh.show_cavity = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.75, 0.82, 0.9)
    scene.render.image_settings.file_format = "PNG"
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    red = bpy.data.materials.new("RefRed")
    red.diffuse_color = (0.9, 0.05, 0.05, 1)
    return scene, cam, red


def cube_at(red, gx, gy, gz):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=b(gx, gy + 0.5, gz))
    c = bpy.context.active_object
    c.name = "RefCube_1m"
    c.data.materials.append(red)
    return c


def aim(cam, eye, target, lens=None, ortho=None):
    cam.location = b(*eye)
    d = b(*target) - b(*eye)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens or 35
    cam.data.clip_end = 1000


def prove(scene, cam, tag, subject_pts, cube, size):
    scene.render.resolution_x, scene.render.resolution_y = size
    bpy.context.view_layer.update()
    co = [world_to_camera_view(scene, cam, p) for p in subject_pts]
    xs, ys = [c.x for c in co], [c.y for c in co]
    print("INFRAME %s subject x %.3f..%.3f y %.3f..%.3f" % (tag, min(xs), max(xs), min(ys), max(ys)), flush=True)
    if min(xs) < 0.01 or max(xs) > 0.99 or min(ys) < 0.01 or max(ys) > 0.99 or min(c.z for c in co) <= 0:
        fail("%s subject out of frame" % tag)
    c = world_to_camera_view(scene, cam, cube.location)
    if cam.data.type == "ORTHO":
        fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        origin = cube.location - fwd * 400
    else:
        origin = cam.matrix_world.translation
    hit = scene.ray_cast(bpy.context.view_layer.depsgraph, origin, (cube.location - origin).normalized())
    first = hit[4].name if hit[4] else None
    print("REFCUBE %s uv %.3f %.3f first hit %s" % (tag, c.x, c.y, first), flush=True)
    if not (0.02 < c.x < 0.98 and 0.02 < c.y < 0.98):
        fail("%s cube out of frame" % tag)
    if first != cube.name:
        fail("%s cube occluded by %s" % (tag, first))


def render(scene, tag):
    path = os.path.join(OUT, tag + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    print("PLATE", path, flush=True)
    return px


def show_all():
    for o in bpy.context.scene.objects:
        o.hide_render = False
        o.hide_viewport = False


def hide(names):
    for o in bpy.context.scene.objects:
        if o.name in names or any(o.name.startswith(n + ".") for n in names):
            o.hide_render = True
            o.hide_viewport = True
            for c in o.children_recursive:
                c.hide_render = True
                c.hide_viewport = True


def box(x0, x1, y0, y1, z0, z1):
    return [b(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def main():
    shell = SHELL
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--shell" in a:
        shell = a[a.index("--shell") + 1]
    os.makedirs(OUT, exist_ok=True)
    building = box(-34.2, 33.2, 0.0, 20.8, -95.5, -64.1)
    dist_eye, dist_tgt = (75, 55, -10), (0, 6, -76)

    # 1-2: distance shot, original against shell, same camera; then three more exterior
    # comparisons (airside, west, a close landside view) that are measured, not saved.
    views = [("distance", dist_eye, dist_tgt, (3.0, 0.1, -46.0), 35),
             ("airside", (-60, 40, -150), (0, 6, -82), (0.0, 0.0, -104.0), 35),
             ("west", (-95, 30, -95), (-30, 6, -80), (-42.0, 0.2, -97.0), 35),
             ("landside_close", (8, 9, -50), (8, 4, -64.3), (8.0, 0.2, -63.0), 30)]
    shots = {}
    for view, eye, tgt, cpos, lens in views:
        for kind, path in (("original", SRC), ("shell", shell)):
            scene, cam, red = load(path)
            cube = cube_at(red, *cpos)
            aim(cam, eye, tgt, lens=lens)
            tag = ("01_distance_original" if kind == "original" else "02_distance_shell") if view == "distance" \
                else "diff_%s_%s" % (view, kind)
            prove(scene, cam, tag, building if view != "landside_close" else [b(8, 2, -64.3)], cube, (1600, 1000))
            if view == "distance":
                shots[(view, kind)] = render(scene, tag)
            else:
                scene.render.filepath = os.path.join(OUT, "_scratch_%s.png" % kind)
                bpy.ops.render.render(write_still=True)
                img = bpy.data.images.load(scene.render.filepath)
                w, h = img.size
                shots[(view, kind)] = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
                os.remove(scene.render.filepath)
        dd = np.abs(shots[(view, "original")][..., :3] - shots[(view, "shell")][..., :3]).max(axis=2)
        print("DIFF %s: mean abs %.5f, pixels differing > 0.08: %d of %d (%.4f%%)"
              % (view, dd.mean(), int((dd > 0.08).sum()), dd.size, 100.0 * (dd > 0.08).sum() / dd.size), flush=True)
        if view != "distance":
            ov = shots[(view, "shell")] * 0.35
            ov[..., 3] = 1.0
            ov[dd > 0.08] = (1.0, 0.0, 1.0, 1.0)
            im = bpy.data.images.new("diff_" + view, ov.shape[1], ov.shape[0], alpha=True)
            im.pixels = ov.ravel()
            im.filepath_raw = os.path.join(OUT, "03_diff_%s.png" % view)
            im.file_format = "PNG"
            im.save()
            print("PLATE", im.filepath_raw, flush=True)
    shots["01_distance_original"] = shots[("distance", "original")]
    shots["02_distance_shell"] = shots[("distance", "shell")]
    d = np.abs(shots["01_distance_original"][..., :3] - shots["02_distance_shell"][..., :3]).max(axis=2)
    mask = np.zeros_like(shots["02_distance_shell"])
    mask[..., 0] = (d > 0.08)
    mask[..., 3] = 1.0
    keep = shots["02_distance_shell"] * 0.35
    keep[..., 3] = 1.0
    keep[d > 0.08] = (1.0, 0.0, 1.0, 1.0)
    im = bpy.data.images.new("diff", keep.shape[1], keep.shape[0], alpha=True)
    im.pixels = keep.ravel()
    im.filepath_raw = os.path.join(OUT, "03_distance_diff.png")
    im.file_format = "PNG"
    im.save()
    print("PLATE", im.filepath_raw, flush=True)

    # 4-5: ground storey with Upper hidden, from above and oblique
    scene, cam, red = load(shell)
    hide(["Upper", "Lights_Upper"])
    cube = cube_at(red, 0.0, 0.3, -80.0)
    floor = box(-33.94, 32.94, 0.3, 5.5, -95.25, -64.35)
    aim(cam, (0, 120, -79.8), (0, 0, -79.8001), ortho=72)
    cam.rotation_euler = (0, 0, 0)
    prove(scene, cam, "04_roof_off_top", floor, cube, (1600, 900))
    render(scene, "04_roof_off_top")
    aim(cam, (-50, 60, -28), (-1, 0, -80), lens=26)
    prove(scene, cam, "05_roof_off_oblique", floor, cube, (1600, 1000))
    render(scene, "05_roof_off_oblique")

    # 6-9: inside views toward each facade (Upper hidden), cube 1.5 m in front of the wall
    views = {
        "06_inside_S": ((0, 9, -88), (0, 2.5, -64.6), (0.0, 0.3, -66.6), box(-14, 14, 0.3, 5.5, -64.6, -64.35)),
        "07_inside_N": ((0, 9, -71), (0, 2.5, -95.0), (0.0, 0.3, -93.5), box(-14, 14, 0.3, 5.5, -95.25, -95.0)),
        "08_inside_W": ((-18, 9, -80), (-33.7, 2.5, -80), (-31.7, 0.3, -80.0), box(-33.94, -33.69, 0.3, 5.5, -88, -72)),
        "09_inside_E": ((17, 9, -80), (32.7, 2.5, -80), (30.7, 0.3, -80.0), box(32.69, 32.94, 0.3, 5.5, -88, -72)),
    }
    for tag, (eye, tgt, cpos, subj) in views.items():
        cube.location = b(cpos[0], cpos[1] + 0.5, cpos[2])
        aim(cam, eye, tgt, lens=24)
        prove(scene, cam, tag, subj, cube, (1600, 900))
        render(scene, tag)

    # 10: one bay hidden (Facade_S_10, which has ground Lights panels), seen from outside on the landside: the
    # neighbours' end reveals and ledge end caps must close the cut.
    show_all()
    hide(["Facade_S_10", "Lights_S_10"])
    cube.location = b(-5.0, 0.6, -62.5)
    aim(cam, (-5, 7, -55.5), (-5, 2.0, -64.5), lens=24)
    prove(scene, cam, "10_bay_S10_hidden", box(-9.5, -0.5, 0.3, 5.5, -64.6, -64.1), cube, (1600, 900))
    render(scene, "10_bay_S10_hidden")

    # 11: the same bay hidden with Upper hidden too, seen from above at an angle, so the
    # wall-top caps, end reveals, ledge end caps and stub caps at the cut all show.
    hide(["Upper", "Lights_Upper"])
    aim(cam, (-5, 12, -57), (-5, 3.0, -64.5), lens=24)
    prove(scene, cam, "11_bay_S10_hidden_roof_off", box(-9.5, -0.5, 0.3, 5.5, -64.6, -64.1), cube, (1600, 900))
    render(scene, "11_bay_S10_hidden_roof_off")

    # contact sheet (3 columns)
    names = sorted(f for f in os.listdir(OUT) if f[:2].isdigit() and f[:2] != "00" and f.endswith(".png"))
    tiles = []
    for n in names:
        img = bpy.data.images.load(os.path.join(OUT, n))
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        ys = np.linspace(0, h - 1, 360).astype(int)
        xs = np.linspace(0, w - 1, 600).astype(int)
        tiles.append(px[ys][:, xs])
    while len(tiles) % 3:
        tiles.append(np.ones_like(tiles[0]))
    rows = [np.concatenate(tiles[i:i + 3], axis=1) for i in range(0, len(tiles), 3)]
    sheet = np.concatenate(rows[::-1], axis=0)
    im = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    im.pixels = sheet.ravel()
    im.filepath_raw = os.path.join(OUT, "00_contact_sheet.png")
    im.file_format = "PNG"
    im.save()
    print("SHEET", names, flush=True)


main()
