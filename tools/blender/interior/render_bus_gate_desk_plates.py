"""Render 6-axis ortho and side-by-side comparison plates of bus_gate_desk.glb.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\gmmf-wt\\bus-gate-clarity\\tools\\blender\\interior\\render_bus_gate_desk_plates.py'

Outputs under tools/blender/out/bus-gate-desk/:
- six_axis/bus_gate_desk.png: six orthographic views at one scale with 1 m cube
- distance_compare.png: gate_desk beside bus_gate_desk + a person at play distance (~22 m)
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402

KIT_DIR = kit.OUT_DIR
OUT = os.path.join(kit.REPO, "tools", "blender", "out", "bus-gate-desk")
PIECE = "bus_gate_desk"
MARGIN = rap.MARGIN
BACKDROP = rap.BACKDROP
log = rap.log
invalid = rap.invalid


def glb(piece):
    return os.path.join(KIT_DIR, piece + ".glb")


def place_piece(piece, x, y, label=None, yaw=0.0):
    xf = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(yaw, 4, "Z")
    objs, _a, _n, _h = rap.import_glb(glb(piece), label or piece, xf)
    return objs


def six_axis():
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs, _a, names, _h = rap.import_glb(glb(PIECE), PIECE)
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
    scale /= 1.0 - 2.0 * MARGIN - 0.04
    log(
        "%s six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (PIECE, sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale)
    )
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "%s six_axis %s" % (PIECE, name)
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        path = os.path.join(OUT, "six_axis", "%s_%s.png" % (PIECE, name))
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
        bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 3), os.path.join(OUT, "six_axis", PIECE + ".png"))


def distance_compare():
    scene = rap.reset_scene(1600, 900, 1.0)
    subjects = {}
    subjects["gate_desk"] = place_piece("gate_desk", 0.0, 0.0)
    subjects[PIECE] = place_piece(PIECE, 3.0, 0.0)
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((5.2, 0.0, 0.0)))
    subjects["male"] = man
    rap.floor_plane((-2.5, -3.5), (7.5, 3.5))
    centre = Vector((2.2, 0.0, 0.8))
    az = rap.CAM_AZIMUTH
    el = math.radians(42)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam = rap.persp_camera(scene, centre + direction * 20.0, centre, lens=35.0)
    log("distance_compare camera_to_centre=%.1f m lens=35" % (cam.location - centre).length)
    for name, objs in subjects.items():
        rap.prove_in_frame("compare %s" % name, scene, cam, rap.world_points(objs))
        rap.visible_share("compare %s" % name, scene, cam, objs)
    arr = rap.render(scene, os.path.join(OUT, "distance_compare_raw.png"))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, "distance_compare.png"))


def main():
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    six_axis()
    distance_compare()
    log("PLATES done")


if __name__ == "__main__":
    main()
