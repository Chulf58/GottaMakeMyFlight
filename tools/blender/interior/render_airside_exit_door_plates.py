"""Render Blender plates for airside_exit_door.glb.

Writes under tools/blender/out/arrivals-assets/ (gitignored):
- six_axis_airside_exit_door.png: 6-axis orthographic views at true scale + 1 m cube
- airside_exit_door_hero.png: front (airside approach) & back (landside) doors mounted
  between plain walls + posts with passengers at 7.5 m game camera
- airside_exit_door_distance.png: tycoon camera 28 m distance readability shot

Run from repo root (or worktree root):
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/render_airside_exit_door_plates.py < /dev/null
"""

import os
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_airside_exit_door as aed  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = str(Path(kit.REPO, "tools", "blender", "out", "arrivals-assets").resolve())
rbp.OUT = OUT
log = rap.log
invalid = rap.invalid


def p_out(*parts):
    return str(Path(OUT, *parts).resolve())


def six_axis():
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs, _a, names, _h = rap.import_glb(rbp.glb("airside_exit_door"), "airside_exit_door")
    lo, hi = rap.bounds(objs)
    ref = rap.cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
    sub = rap.world_points(objs)
    ref_pts = rap.world_points([ref])
    allp = np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in rap.VIEWS:
        inv = np.array(rap.look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * rap.MARGIN - 0.04
    log(
        "airside_exit_door six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale)
    )
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "airside_exit_door six_axis %s" % name
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        raw = p_out("six_axis_airside_exit_door_%s.png" % name)
        tiles.append(rap.over(rap.render(scene, raw), rap.BACKDROP))
        if os.path.exists(raw):
            os.remove(raw)
        bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 3), p_out("six_axis_airside_exit_door.png"))


def _stage_pair():
    # Two wall lines side-by-side: left shows Airside approach face (yaw 0),
    # right shows Landside back face (yaw 180) beside regular wall_door for comparison.
    rbp.floor_tiles(-3, 5, -2, 3)
    subjects = {}
    subjects["door_front"] = rbp.place("airside_exit_door", -1.5, 0.0, 0.0, "door_front")
    rbp.place("wall", -2.5, 0.0)
    rbp.place("wall", -0.5, 0.0)
    rbp.place("wall_post", -3.0, 0.0)

    subjects["door_back"] = rbp.place("airside_exit_door", 1.5, 0.0, 180.0, "door_back")
    rbp.place("wall", 0.5, 0.0)
    rbp.place("wall", 2.5, 0.0)
    rbp.place("wall_post", 0.0, 0.0)
    rbp.place("wall_post", 3.0, 0.0)

    subjects["wall_door_ref"] = rbp.place("wall_door", 3.5, 0.0, 0.0, "wall_door_ref")
    rbp.place("wall", 4.5, 0.0)
    rbp.place("wall_post", 5.0, 0.0)

    subjects["pax_front"] = rbp.person("male", -2.15, -0.95, 180.0, "pax_front")
    subjects["pax_back"] = rbp.person("female", 2.15, -0.95, 180.0, "pax_back")
    return subjects


def hero_plate():
    scene = rap.reset_scene(1920, 1080, 1.5)
    subjects = _stage_pair()
    target = Vector((0.4, 0.0, 1.25))
    cam = rbp.game_camera(scene, target, 8.0, yaw_deg=-18.0)
    for name in ("door_front", "door_back", "wall_door_ref", "pax_front", "pax_back"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("hero %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("hero " + name, scene, cam, objs, need=0.10)
    raw = p_out("airside_exit_door_hero_raw.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), p_out("airside_exit_door_hero.png"))
    if os.path.exists(raw):
        os.remove(raw)


def distance_plate():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = _stage_pair()
    target = Vector((0.8, 0.0, 1.0))
    cam = rbp.game_camera(scene, target, 20.0, yaw_deg=-25.0)
    for name in ("door_front", "door_back", "wall_door_ref", "pax_front", "pax_back"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_20m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_20m " + name, scene, cam, objs, need=0.10)
    raw = p_out("airside_exit_door_distance_raw.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), p_out("airside_exit_door_distance.png"))
    if os.path.exists(raw):
        os.remove(raw)


def main():
    aed.register()
    os.makedirs(OUT, exist_ok=True)
    six_axis()
    hero_plate()
    distance_plate()
    log("AIRSIDE_EXIT_DOOR_PLATES done")


if __name__ == "__main__":
    main()
