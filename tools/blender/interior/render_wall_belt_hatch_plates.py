"""Render Blender plates for wall_belt_hatch.glb.

Run (headless, reproducible), after build_wall_belt_hatch.py:
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/render_wall_belt_hatch_plates.py < /dev/null

Writes under tools/blender/out/wall-belt-hatch/ (gitignored):
- six_axis/wall_belt_hatch.png: 6-axis orthographic views at true scale + 1 m cube
- blender_distance.png: 7.5 m game-camera context shot with walls, posts, belt, bags, person
- blender_closeup.png: close-up of the hatch frame, rubber strip flaps, belt and rails
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "wall-belt-hatch")
rbp.OUT = OUT
log = rap.log


def _place_shifted(piece, x, y, z=0.0, yaw_deg=0.0):
    objs = rbp.place(piece, x, y)
    roots = set()
    for ob in objs:
        cur = ob
        while cur.parent is not None:
            cur = cur.parent
        roots.add(cur)
    for root in roots:
        root.location = Vector((x, y, z))
        root.rotation_euler = Euler((0.0, 0.0, math.radians(yaw_deg)))
    bpy.context.view_layer.update()
    return objs


def _stage_context():
    hatch = rbp.place("wall_belt_hatch", 0.0, 0.0)
    wall_l = rbp.place("wall", -1.0, 0.0)
    wall_r = rbp.place("wall", 1.0, 0.0)
    post_l = rbp.place("wall_post", -1.5, 0.0)
    post_r = rbp.place("wall_post", 1.5, 0.0)
    belt_in = rbp.place("baggage_belt", 0.0, -0.5)
    belt_in_far = rbp.place("baggage_belt", 0.0, -1.5)
    belt_out = rbp.place("baggage_belt", 0.0, 0.5)
    belt_out_far = rbp.place("baggage_belt", 0.0, 1.5)
    belt_out_tip = rbp.place("baggage_belt", 0.0, 2.5)
    bag_in = _place_shifted("baggage_bag", 0.0, -0.62, 0.355)
    bag_out = _place_shifted("baggage_bag", 0.0, 2.15, 0.355)
    rap.floor_plane((-2.5, -2.5), (2.5, 3.2))
    return {
        "wall_belt_hatch": hatch,
        "wall_l": wall_l,
        "wall_r": wall_r,
        "post_l": post_l,
        "post_r": post_r,
        "belt_in": belt_in,
        "belt_in_far": belt_in_far,
        "belt_out": belt_out,
        "belt_out_far": belt_out_far,
        "belt_out_tip": belt_out_tip,
        "bag_in": bag_in,
        "bag_out": bag_out,
    }


def distance_plate(distance=7.5, yaw_deg=-58.0):
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = _stage_context()
    subjects["person"] = rbp.person("male", 1.15, -0.85, 0.0, "scale")
    target = Vector((0.0, 0.0, 0.75))
    cam = rbp.game_camera(scene, target, distance, yaw_deg)
    for name in ("wall_belt_hatch", "belt_in", "belt_out_tip", "bag_in", "bag_out", "person"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("blender_distance %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("blender_distance " + name, scene, cam, objs, need=0.08)
    raw = os.path.join(OUT, "blender_distance_raw.png")
    out = os.path.join(OUT, "blender_distance.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rbp.BACKDROP), out)
    if os.path.exists(raw):
        os.remove(raw)


def closeup_plate():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = _stage_context()
    target = Vector((0.0, -0.15, 1.05))
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam_data = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cam_data)
        scene.collection.objects.link(cam)
    cam.data.lens = 28.0
    cam.location = Vector((-2.30, -4.55, 1.60))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()
    for name in ("wall_belt_hatch", "belt_in", "bag_in"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("blender_closeup %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("blender_closeup " + name, scene, cam, objs, need=0.10)
    raw = os.path.join(OUT, "blender_closeup_raw.png")
    out = os.path.join(OUT, "blender_closeup.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rbp.BACKDROP), out)
    if os.path.exists(raw):
        os.remove(raw)


def main():
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance", "closeup"]
    unknown = [s for s in only if s not in known]
    if unknown:
        rap.invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        rbp.six_axis("wall_belt_hatch")
    if "distance" in stages:
        distance_plate()
    if "closeup" in stages:
        closeup_plate()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
