"""Render the Blender plates of the gate desk.

Run (headless, reproducible), after build_gate_kit.py has written the piece:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_gate_plates.py' [-- stage ...]

Stages: six, distance, context (all when none is named). Everything is written under
tools/blender/out/gates-2/ (gitignored); nothing in game/ is touched. The plates
re-import the WRITTEN game/assets/interior/gate_desk.glb:
- six_axis/gate_desk.png: six orthographic views at one scale, true scale, with a 1 m
  reference cube beside it;
- distance.png: the gate desk beside the info desk and the check-in desk it must read
  apart from, perspective, about 30 m out, a person for scale;
- context.png: the gate desk in a room by a wall with an exit door, a passenger at its
  reader, seats beside it.
Each plate proves its subjects are in frame and visible (render_activities_plates'
prove_in_frame and visible_share); on failure PROBE_INVALID and exit 1. The Blender
view is not the authority on how it looks in the game: the windowed Godot plates are.
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
OUT = os.path.join(kit.REPO, "tools", "blender", "out", "gates-2")
PIECE = "gate_desk"
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
    log("%s six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (PIECE, sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale))
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


def distance_shot():
    scene = rap.reset_scene(1600, 900, 1.0)
    subjects = {}
    x = 0.0
    for piece in ("checkin_desk", "info_desk", PIECE):
        subjects[piece] = place_piece(piece, x + 1.0, 0.0)
        x += 3.0
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((x + 0.5, 0.0, 0.0)))
    subjects["male"] = man
    rap.floor_plane((-2.0, -4.0), (x + 3.0, 4.0))
    centre = Vector(((x + 1.0) / 2.0, 0.0, 0.6))
    az = rap.CAM_AZIMUTH
    el = math.radians(45)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam = rap.persp_camera(scene, centre + direction * 30.0, centre, lens=35.0)
    log("distance camera_to_centre=%.1f m lens=35" % (cam.location - centre).length)
    for name, objs in subjects.items():
        rap.prove_in_frame("distance %s" % name, scene, cam, rap.world_points(objs))
        rap.visible_share("distance %s" % name, scene, cam, objs)
    arr = rap.render(scene, os.path.join(OUT, "distance_raw.png"))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, "distance.png"))


def context_shot():
    scene = rap.reset_scene(1600, 1000, 1.2)
    W, D = 9, 7
    tile, _a, _n, _h = rap.import_glb(glb("floor_tile"), "floor")
    bodies = [(o.data, o.matrix_world.copy()) for o in rap.meshes(tile)]
    for o in tile:
        bpy.data.objects.remove(o)
    for j in range(D):
        for i in range(W):
            for data, mw in bodies:
                dup = bpy.data.objects.new("Floor_%d_%d" % (i, j), data)
                dup.matrix_world = Matrix.Translation((i + 0.5, j + 0.5, 0.0)) @ mw
                scene.collection.objects.link(dup)
    # The back wall (Blender +y) with an exit door in its middle cell.
    door_x = 4
    for i in range(W):
        place_piece("wall_door" if i == door_x else "wall", i + 0.5, D, "wall_%d" % i)
    subjects = {}
    # The desk two cells in front of the exit, its front (Godot +Z, Blender -y)
    # toward the room and the camera; seats beside it.
    subjects[PIECE] = place_piece(PIECE, door_x + 1.0, D - 2.5)
    subjects["seat_row"] = place_piece("seat_row", 1.5, 2.5)
    who_xf = Matrix.Translation((door_x + 1.5, D - 3.5, 0.0)) @ Matrix.Rotation(math.pi, 4, "Z")
    person, acts, arm, _h = rap.add_character("female", who_xf)
    f0, f1 = rap.clip_range(acts, "idle")
    rap.pose(arm, acts, "idle", (f0 + f1) // 2)
    subjects["passenger"] = person
    target = Vector((W / 2.0, D / 2.0, 0.6))
    direction = Vector((math.sin(math.radians(-25)) * math.cos(math.radians(50)),
                        -math.cos(math.radians(-25)) * math.cos(math.radians(50)), math.sin(math.radians(50))))
    cam = rap.persp_camera(scene, target + direction * 13.0, target, lens=28.0)
    for name, objs in subjects.items():
        rap.prove_in_frame("context %s" % name, scene, cam, rap.world_points(objs))
        rap.visible_share("context %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "context_raw.png"))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, "context.png"))


def main():
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance", "context"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        six_axis()
    if "distance" in stages:
        distance_shot()
    if "context" in stages:
        context_shot()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
