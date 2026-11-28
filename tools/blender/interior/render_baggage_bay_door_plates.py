"""Render Blender plates for baggage_bay_door.glb.

Writes under tools/blender/out/baggage-bay-door/ (gitignored):
- six_axis_baggage_bay_door.png: 6-axis orthographic views at true scale + 1 m cube
- baggage_bay_door_hero.png: exterior apron side (left) + interior Bag Room side (right)
  mounted between plain walls + posts, with baggage_cart, baggage_belt_end & handler at 8.5 m
- baggage_bay_door_distance.png: tycoon camera 24 m distance readability shot
- baggage_bay_door_contact_sheet.png: combined batch contact sheet

Run from repo/worktree root:
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/render_baggage_bay_door_plates.py < /dev/null
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

import build_baggage_bay_door as bbd  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = str(Path(kit.REPO, "tools", "blender", "out", "baggage-bay-door").resolve())
rbp.OUT = OUT
log = rap.log
invalid = rap.invalid
APRON_RGB = (0.50, 0.52, 0.55)


def p_out(*parts):
    return str(Path(OUT, *parts).resolve())


def apron_slab(x0, x1, y0, y1):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=((x0 + x1) / 2.0, (y0 + y1) / 2.0, -0.002))
    ob = bpy.context.active_object
    ob.scale = (x1 - x0, y1 - y0, 1.0)
    ob.name = "Plate_Apron"
    ob.data.materials.append(rap.flat(APRON_RGB))
    return ob


def six_axis():
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs, _a, names, _h = rap.import_glb(rbp.glb("baggage_bay_door"), "baggage_bay_door")
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
        "baggage_bay_door six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale)
    )
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "baggage_bay_door six_axis %s" % name
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        raw = p_out("six_axis_%s.png" % name)
        tiles.append(rap.over(rap.render(scene, raw), rap.BACKDROP))
        if os.path.exists(raw):
            os.remove(raw)
        bpy.data.objects.remove(cam)
    path = p_out("six_axis_baggage_bay_door.png")
    rap.save_array(rap.grid(tiles, 3), path)
    return path


def _stage_context():
    # Left bay (x in [-4, 0]): exterior apron side faces camera (-Y world, yaw 180) over apron slab.
    # Right bay (x in [1, 5]): interior Bag Room side faces camera (-Y world, yaw 0) over floor tiles.
    rbp.floor_tiles(-4, 0, 0, 3)
    apron_slab(-4.5, 0.3, -3.5, 0.0)

    rbp.floor_tiles(1, 5, -3, 0)
    apron_slab(0.7, 5.3, 0.0, 3.0)

    subjects = {}
    subjects["bay_exterior"] = rbp.place("baggage_bay_door", -2.0, 0.0, 180.0, "bay_exterior")
    rbp.place("wall", -3.5, 0.0)
    rbp.place("wall", -0.5, 0.0)
    rbp.place("wall_post", -4.0, 0.0)
    rbp.place("wall_post", -3.0, 0.0)
    rbp.place("wall_post", -1.0, 0.0)
    rbp.place("wall_post", 0.0, 0.0)

    subjects["bay_interior"] = rbp.place("baggage_bay_door", 3.0, 0.0, 0.0, "bay_interior")
    rbp.place("wall", 1.5, 0.0)
    rbp.place("wall", 4.5, 0.0)
    rbp.place("wall_post", 1.0, 0.0)
    rbp.place("wall_post", 2.0, 0.0)
    rbp.place("wall_post", 4.0, 0.0)
    rbp.place("wall_post", 5.0, 0.0)

    # Scale cues: baggage cart parked alongside apron approach, belt end inside right Bag Room.
    subjects["cart_apron"] = rbp.place("baggage_cart", -2.95, -2.05, 165.0, "cart_apron")
    subjects["belt_inside"] = rbp.place("baggage_belt_end", 1.75, -1.35, 0.0, "belt_inside")
    subjects["handler"] = rbp.person("male", -0.85, -1.15, 155.0, "handler")
    return subjects


def hero_plate():
    scene = rap.reset_scene(1920, 1080, 1.5)
    subjects = _stage_context()
    target = Vector((0.5, -0.2, 1.15))
    cam = rbp.game_camera(scene, target, 10.2, yaw_deg=-20.0)
    for name in ("bay_exterior", "bay_interior", "cart_apron", "belt_inside", "handler"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("hero %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("hero " + name, scene, cam, objs, need=0.10)
    raw = p_out("baggage_bay_door_hero_raw.png")
    out = p_out("baggage_bay_door_hero.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), out)
    if os.path.exists(raw):
        os.remove(raw)
    return out


def distance_plate():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = _stage_context()
    target = Vector((0.5, 0.0, 1.0))
    cam = rbp.game_camera(scene, target, 24.0, yaw_deg=-25.0)
    for name in ("bay_exterior", "bay_interior", "cart_apron", "handler"):
        objs = subjects[name]
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_24m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_24m " + name, scene, cam, objs, need=0.10)
    raw = p_out("baggage_bay_door_distance_raw.png")
    out = p_out("baggage_bay_door_distance.png")
    arr = rap.render(scene, raw)
    rap.save_array(rap.over(arr, rap.BACKDROP), out)
    if os.path.exists(raw):
        os.remove(raw)
    return out


def _fit_tile(path, w=960, h=540):
    img = bpy.data.images.load(path)
    img.scale(w, h)
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return arr


def contact_sheet(six_path, hero_path, dist_path):
    tiles = [_fit_tile(hero_path), _fit_tile(dist_path), _fit_tile(six_path, 960, 540)]
    blank = np.full((540, 960, 4), (*rap.BACKDROP, 1.0), dtype=np.float32)
    tiles.append(blank)
    out = p_out("baggage_bay_door_contact_sheet.png")
    rap.save_array(rap.grid(tiles, 2), out)
    return out


def main():
    bbd.register()
    os.makedirs(OUT, exist_ok=True)
    six_path = six_axis()
    hero_path = hero_plate()
    dist_path = distance_plate()
    sheet_path = contact_sheet(six_path, hero_path, dist_path)
    log("BAGGAGE_BAY_DOOR_PLATES done sheet=%s" % sheet_path)


if __name__ == "__main__":
    main()
