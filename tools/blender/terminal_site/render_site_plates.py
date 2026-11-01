"""Plates for the airport site (tp_airport_site.glb), rendered from the WRITTEN .glb files.

Run from WSL (Blender sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python \
        'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\terminal_site\\render_site_plates.py'

Plates go to tools/blender/out/terminal-site/ (gitignored): six true-scale orthographic views
of the site (N, S, W, E, top, bottom; 20 px per metre) with a 1 m red reference cube, and
three perspective views of the site and of the shell side by side: the game camera's Home
view (80 m from (-0.5, 0, -79.8), pitch 57.0 degrees, vertical fov 55, as tycoon_camera.gd
computes it), the farthest zoom (300 m, pitch 65) and a low close look at the cleared plot.
contact_sheet.png stacks them all. Workbench with back-face culling on, because the game's
toon surface shader culls back faces.

Every plate first proves its subject is in frame (its box corners project inside the image
with a 1 percent margin), that the 1 m cube is in frame and is the first thing a ray from
the camera hits, and, on the site plates, that a ray to the plot centre (0, 0.2, -80) first
hits Lot (the plot is paved there and nothing stands over it). Otherwise it prints
PROBE_INVALID and exits 1. Coordinates are Godot world coordinates with the asset at
(0, 0, -80).
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SITE = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_site.glb")
SHELL = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_shell.glb")
OUT = os.path.join(REPO, "tools", "blender", "out", "terminal-site")
OFFSET_Z = -80.0
PX_PER_M = 20.0
SITE_BOX = (-43.0, 43.0, -0.1, 3.0, -100.0, -40.0)
PLOT_BOX = (-43.0, 43.0, 0.0, 0.3, -100.0, -60.0)
PLOT_CENTRE = (0.0, 0.2, -80.0)


def b(x, y, z):
    return Vector((x, -(z - OFFSET_Z), y))


def fail(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sh.show_object_outline = False
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


def aim(cam, eye, target, ortho=None, vfov=None):
    cam.location = b(*eye)
    d = b(*target) - b(*eye)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = 2000
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(vfov)


def corners(bx):
    x0, x1, y0, y1, z0, z1 = bx
    return [b(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def first_hit(scene, cam, target):
    if cam.data.type == "ORTHO":
        fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        origin = target - fwd * 900
    else:
        origin = cam.matrix_world.translation
    hit = scene.ray_cast(bpy.context.view_layer.depsgraph, origin, (target - origin).normalized())
    return hit[4].name if hit[4] else None


def prove(scene, cam, tag, subject, cube, size, plot_check):
    scene.render.resolution_x, scene.render.resolution_y = size
    bpy.context.view_layer.update()
    co = [world_to_camera_view(scene, cam, p) for p in corners(subject)]
    xs, ys = [c.x for c in co], [c.y for c in co]
    print("INFRAME %s subject x %.3f..%.3f y %.3f..%.3f" % (tag, min(xs), max(xs), min(ys), max(ys)), flush=True)
    if min(xs) < 0.01 or max(xs) > 0.99 or min(ys) < 0.01 or max(ys) > 0.99 or min(c.z for c in co) <= 0:
        fail("%s subject out of frame" % tag)
    c = world_to_camera_view(scene, cam, cube.location)
    first = first_hit(scene, cam, cube.location)
    print("REFCUBE %s uv %.3f %.3f first hit %s" % (tag, c.x, c.y, first), flush=True)
    if not (0.02 < c.x < 0.98 and 0.02 < c.y < 0.98):
        fail("%s cube out of frame" % tag)
    if first != cube.name:
        fail("%s cube occluded by %s" % (tag, first))
    if plot_check:
        hit = first_hit(scene, cam, b(*PLOT_CENTRE))
        print("PLOTCENTRE %s first hit %s" % (tag, hit), flush=True)
        if hit != "Lot":
            fail("%s plot centre first hits %s, not Lot" % (tag, hit))


def render(scene, tag):
    path = os.path.join(OUT, tag + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    print("PLATE", path, flush=True)
    return px


def ortho_views():
    # name, eye, target, cube base, frame width and height in metres, fixed euler
    views = [
        ("N", (0, 1.5, -500), (0, 1.5, -70), (-44.5, 0.0, -101.5), 96, 8, None),
        ("S", (0, 1.5, 400), (0, 1.5, -70), (-44.5, 0.0, -38.0), 96, 8, None),
        ("W", (-500, 1.5, -70), (0, 1.5, -70), (-46.0, 0.0, -98.0), 66, 8, None),
        ("E", (500, 1.5, -70), (0, 1.5, -70), (46.0, 0.0, -98.0), 66, 8, None),
        ("top", (0, 500, -70), (0, 0, -70), (-45.5, 0.0, -64.0), 96, 66, (0.0, 0.0, 0.0)),
        ("bottom", (0, -500, -70), (0, 0, -70), (-45.5, 0.0, -64.0), 96, 66, (math.pi, 0.0, 0.0)),
    ]
    plates = []
    for view, eye, tgt, cpos, wm, hm, euler in views:
        scene, cam, red = load(SITE)
        scene.display.render_aa = "OFF"
        cube = cube_at(red, *cpos)
        aim(cam, eye, tgt, ortho=max(wm, hm))
        if euler is not None:
            cam.rotation_euler = euler
            cam.location = b(*eye)
        size = (int(round(wm * PX_PER_M)), int(round(hm * PX_PER_M)))
        tag = "ortho_%s" % view
        # A side view sees the plot edge-on: its centre is behind the near paving, so only
        # the top and bottom views take the plot-centre ray.
        prove(scene, cam, tag, SITE_BOX, cube, size, plot_check=view == "top")
        plates.append((tag, render(scene, tag)))
    return plates


def persp_views():
    def eye_for(focus, dist, pitch_deg):
        p = math.radians(pitch_deg)
        return (focus[0], focus[1] + dist * math.sin(p), focus[2] + dist * math.cos(p))

    home = (-0.5, 0.0, -79.8)
    views = [
        # tag, eye, target, subject box, cube base
        ("home", eye_for(home, 80.0, 57.0), home, PLOT_BOX, (-45.5, 0.0, -62.0)),
        ("far", eye_for(home, 300.0, 65.0), home, SITE_BOX, (-45.5, 0.0, -62.0)),
        ("plot_low", (-60.0, 9.0, -48.0), (0.0, 0.0, -82.0), (-30.0, 30.0, 0.0, 0.3, -95.0, -65.0),
         (-38.0, 0.2, -66.0)),
    ]
    plates = []
    for tag, eye, tgt, subject, cpos in views:
        row = []
        for kind, path in (("site", SITE), ("shell", SHELL)):
            scene, cam, red = load(path)
            cube = cube_at(red, *cpos)
            aim(cam, eye, tgt, vfov=55.0)
            name = "persp_%s_%s" % (tag, kind)
            # The shell's plot centre is under its roof, so only the site takes the ray.
            prove(scene, cam, name, subject, cube, (1600, 900), plot_check=kind == "site")
            row.append((name, render(scene, name)))
        plates.extend(row)
    return plates


def contact_sheet(plates):
    width = 1600
    rows = []
    for _tag, px in plates:
        h, w = px.shape[:2]
        scale = width / w
        nh = max(1, int(round(h * scale)))
        ys = np.minimum((np.arange(nh) / scale).astype(int), h - 1)
        xs = np.minimum((np.arange(width) / scale).astype(int), w - 1)
        rows.append(px[ys][:, xs])
        rows.append(np.ones((8, width, 4), dtype=np.float32))
    sheet = np.concatenate(rows[::-1], axis=0)  # Blender pixels run bottom-up
    im = bpy.data.images.new("sheet", width, sheet.shape[0], alpha=True)
    im.pixels = sheet.ravel()
    im.filepath_raw = os.path.join(OUT, "contact_sheet.png")
    im.file_format = "PNG"
    im.save()
    print("PLATE", im.filepath_raw, flush=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    plates = ortho_views() + persp_views()
    contact_sheet(plates)
    print("PLATES_DONE %d" % len(plates), flush=True)


main()
