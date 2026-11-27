"""Render Blender plates for claim_carousel.glb.

Writes under tools/blender/out/arrivals-assets/ (gitignored):
- six_axis_claim_carousel.png: 6-axis orthographic views at true scale + 1 m cube
- claim_carousel_hero.png: 3/4 tycoon hero shot (9.5 m) with plugged-in baggage_belt,
  wall_belt_hatch, circling suitcases on the exact TRACK_Y = 0.355 m stadium loop,
  and waiting passengers around the 3 open sides
- claim_carousel_distance.png: 30 m tycoon-distance in-context shot with airside_exit_door,
  belts, bags, and passengers

Run from repo root (or worktree root):
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/render_claim_carousel_plates.py < /dev/null
"""

import math
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
import build_claim_carousel as cc  # noqa: E402
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
    objs, _a, names, _h = rap.import_glb(rbp.glb("claim_carousel"), "claim_carousel")
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
        "claim_carousel six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale)
    )
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "claim_carousel six_axis %s" % name
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        raw = p_out("six_axis_claim_carousel_%s.png" % name)
        tiles.append(rap.over(rap.render(scene, raw), rap.BACKDROP))
        if os.path.exists(raw):
            os.remove(raw)
        bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 3), p_out("six_axis_claim_carousel.png"))


def _place_loop_bags(subjects):
    # Place 6 suitcases riding around the stadium centerline at TRACK_Y = 0.355 m + 1 entering via belt
    pts = cc._track_samples(12)
    for k, idx in enumerate((0, 2, 4, 6, 8, 10)):
        px, py, tx, ty, _nx, _ny = pts[idx]
        yaw = math.degrees(math.atan2(ty, tx)) - 90.0
        subjects["bag_%d" % k] = rbp.bag_on(px, py, cc.TRACK_Y, yaw, "bag_%d" % k)
    subjects["bag_inlet"] = rbp.bag_on(cc.INLET_X, 1.50, cc.TRACK_Y, 0.0, "bag_inlet")


def _stage_claim_room(include_exit_wall=True, cutaway_north=False):
    rbp.floor_tiles(-4, 5, -3, 5)
    subjects = {}
    subjects["carousel"] = rbp.place("claim_carousel", 0.0, 0.0, 0.0, "carousel")
    # Inbound belt plugged straight into Mount_Belt_B at (0.5, 1.0) in Blender -> belt cell centered at (0.5, 1.5), (0.5, 2.5)
    subjects["belt_0"] = rbp.place("baggage_belt", 0.5, 1.5, 0.0, "belt_0")
    subjects["belt_1"] = rbp.place("baggage_belt", 0.5, 2.5, 0.0, "belt_1")
    subjects["hatch"] = rbp.place("wall_belt_hatch", 0.5, 2.0, 0.0, "hatch")
    for wx in (-3.5, -2.5, -1.5, -0.5, 1.5, 2.5, 3.5):
        wobjs = rbp.place("wall", wx, 2.0)
        if cutaway_north:
            for o in wobjs:
                o.scale.z = 0.30 / 2.50
    rbp.place("wall_post", -4.0, 2.0)
    rbp.place("wall_post", 4.0, 2.0)

    _place_loop_bags(subjects)

    # Waiting passengers around front (+Z -> Blender -Y) and ends (+X / -X)
    subjects["pax_0"] = rbp.person("male", -0.8, -1.4, 180.0, "pax_0")
    subjects["pax_1"] = rbp.person("female", 0.8, -1.4, 180.0, "pax_1")
    subjects["pax_2"] = rbp.person("male", -2.35, 0.0, 90.0, "pax_2")

    if include_exit_wall:
        # Divider wall on west side: airside_exit_door faces -X airside approach, +X into claim hall
        subjects["exit_door"] = rbp.place("airside_exit_door", -3.0, 0.5, -90.0, "exit_door")
        rbp.place("wall", -3.0, 1.5, 90.0)
        rbp.place("wall", -3.0, -0.5, 90.0)
        rbp.place("wall", -3.0, -1.5, 90.0)
        rbp.place("wall_post", -3.0, 2.0)
        rbp.place("wall_post", -3.0, -2.0)
        subjects["pax_exit"] = rbp.person("female", -2.35, 0.7, 90.0, "pax_exit")
    return subjects


def hero_plate():
    scene = rap.reset_scene(1920, 1080, 1.5)
    subjects = _stage_claim_room(include_exit_wall=False)
    target = Vector((0.0, 0.25, 0.70))
    cam = rbp.game_camera(scene, target, 7.5, yaw_deg=-38.0)
    for name in ("carousel", "belt_0", "hatch", "bag_0", "bag_4", "pax_0", "pax_1", "pax_2"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("hero %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("hero " + name, scene, cam, objs, need=0.10)
    raw = p_out("claim_carousel_hero_raw.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), p_out("claim_carousel_hero.png"))
    if os.path.exists(raw):
        os.remove(raw)


def inlet_plate():
    scene = rap.reset_scene(1920, 1080, 1.5)
    subjects = _stage_claim_room(include_exit_wall=False, cutaway_north=True)
    target = Vector((0.35, 1.10, 0.45))
    cam = rbp.game_camera(scene, target, 6.2, yaw_deg=135.0)
    for name in ("carousel", "belt_0", "belt_1", "bag_inlet"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("inlet %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("inlet " + name, scene, cam, objs, need=0.10)
    raw = p_out("claim_carousel_inlet_raw.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), p_out("claim_carousel_inlet.png"))
    if os.path.exists(raw):
        os.remove(raw)


def distance_plate():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = _stage_claim_room(include_exit_wall=True)
    target = Vector((-0.6, 0.3, 0.6))
    cam = rbp.game_camera(scene, target, 24.0, yaw_deg=-35.0)
    for name in ("carousel", "exit_door", "belt_0", "bag_0", "pax_0", "pax_exit"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_24m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_24m " + name, scene, cam, objs, need=0.08)
    raw = p_out("claim_carousel_distance_raw.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), p_out("claim_carousel_distance.png"))
    if os.path.exists(raw):
        os.remove(raw)


def main():
    aed.register()
    cc.register()
    os.makedirs(OUT, exist_ok=True)
    six_axis()
    hero_plate()
    inlet_plate()
    distance_plate()
    log("CLAIM_CAROUSEL_PLATES done")


if __name__ == "__main__":
    main()
