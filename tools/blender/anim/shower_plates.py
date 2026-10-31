"""Check and plate the "shower" clip from the WRITTEN .glb files.

    blender.exe --background --factory-startup --python shower_plates.py -- <out dir> <glb> [<glb> ...]

For each file: re-reads the clip list (name, frame count, duration), then steps the
shower clip frame by frame on the skinned mesh and prints, per frame, the hands' clearance
from the head and torso skin (mesh-on-mesh intersections, the hand joints' nearest
distance, the hand vertices' signed distance), the forearms' intersections with the head
and torso, the hands' offset from the body's centre line below the shoulders, how far the
feet move, and the loop seam (frame 0 against the last frame). Then renders front and side
frame strips with a 1 m cube and the 1 x 1 m shower tray, proving the subject is in frame
and unoccluded before each plate is saved (PROBE_INVALID and exit 1 otherwise), and tiles
them into one contact sheet per view.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

FPS = 25
CLIP = "shower"
STRIP = 10
TILE_W, TILE_H = 480, 640
TORSO = ("Hips", "Spine_01", "Spine_02", "Spine_03", "Neck", "Clavicle.L", "Clavicle.R")
HAND = ("Hand", "Fingers", "Fingertips", "Thumb", "Thumb_Tip")
JOINTS = ("Hand", "Fingers", "Fingertips", "Thumb_Tip")


def log(*a):
    print("SHOWER_CHECK", *a, flush=True)


def invalid(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    return scene


def load(path):
    scene = reset()
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in scene.objects if o.type == "ARMATURE")
    body = next(o for o in scene.objects if o.type == "MESH" and o.find_armature() == arm)
    return scene, arm, body


def clip_list(stem, arm):
    for a in sorted(bpy.data.actions, key=lambda a: a.name):
        f0, f1 = a.frame_range
        log("CLIPLIST %s %s frames=%d duration_s=%.3f" % (stem, a.name, round(f1 - f0), (f1 - f0) / FPS))


def play(arm, name):
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    if act.slots:
        arm.animation_data.action_slot = act.slots[0]
    return round(act.frame_range[1] - act.frame_range[0])


def tree(verts, polys, keep):
    sel = [p for p in polys if keep(p)]
    return BVHTree.FromPolygons(verts, sel), len(sel)


def check(stem, scene, arm, body):
    frames = play(arm, CLIP)
    groups = {g.index: g.name for g in body.vertex_groups}
    dom = []
    for v in body.data.vertices:
        g = max(v.groups, key=lambda g: g.weight) if v.groups else None
        dom.append(groups[g.group] if g else "")
    polys = [tuple(p.vertices) for p in body.data.polygons]

    def is_in(names):
        return lambda p: any(dom[i] in names for i in p)

    hand_names = {s: tuple(h + s for h in HAND) for s in (".L", ".R")}
    hand_verts = {s: [i for i, g in enumerate(dom) if g in hand_names[s]] for s in hand_names}
    worst = {}

    def note(key, value, frame, bigger=True):
        cur = worst.get(key)
        if cur is None or (value > cur[0] if bigger else value < cur[0]):
            worst[key] = (value, frame)

    feet0 = None
    mats0 = None
    for k in range(frames + 1):
        scene.frame_set(k)
        dg = bpy.context.evaluated_depsgraph_get()
        me = body.evaluated_get(dg).to_mesh()
        verts = [body.matrix_world @ v.co for v in me.vertices]
        body.evaluated_get(dg).to_mesh_clear()
        head, _ = tree(verts, polys, is_in(("Head",)))
        torso, _ = tree(verts, polys, is_in(TORSO))
        pb = {b.name: arm.matrix_world @ b.matrix for b in arm.pose.bones}
        hips = pb["Hips"].translation
        row = []
        for s in (".L", ".R"):
            hand, _ = tree(verts, polys, is_in(hand_names[s]))
            fore, _ = tree(verts, polys, lambda p, s=s: all(dom[i] == "Forearm" + s for i in p))
            for name, surf in (("head", head), ("torso", torso)):
                hx, fx = len(hand.overlap(surf)), len(fore.overlap(surf))
                note("hand%s_x_%s_tris" % (s, name), hx, k)
                note("forearm%s_x_%s_tris" % (s, name), fx, k)
                joint_min = min(surf.find_nearest(pb[j + s].translation)[3] for j in JOINTS)
                note("hand%s_joint_to_%s_min_m" % (s, name), joint_min, k, bigger=False)
                vert_min = min(surf.find_nearest(verts[i])[3] for i in hand_verts[s])
                note("hand%s_vertex_to_%s_min_m" % (s, name), vert_min, k, bigger=False)
                row.append("%s%s/%s x%d fx%d j%.3f v%.3f" % ("hand", s, name, hx, fx, joint_min, vert_min))
            shoulder_z = pb["Arm" + s].translation.z
            for j in ("Hand", "Fingertips"):
                p = pb[j + s].translation
                if p.z < shoulder_z:
                    note("%s%s_lateral_below_shoulder_max_m" % (j, s), abs(p.x - hips.x), k)
                    note("%s%s_radial_below_shoulder_max_m" % (j, s), Vector((p.x - hips.x, p.y - hips.y)).length, k)
        log("FRAME %s %03d %s" % (stem, k, " | ".join(row)))
        feet = {n: pb[n].translation.copy() for n in ("Foot.L", "Foot.R", "Toes.L", "Toes.R")}
        if feet0 is None:
            feet0, mats0 = feet, pb
        note("feet_move_max_m", max((feet[n] - feet0[n]).length for n in feet), k)
    seam_pos = max((pb[n].translation - mats0[n].translation).length for n in pb)
    seam_rot = max(math.degrees(pb[n].to_quaternion().rotation_difference(mats0[n].to_quaternion()).angle) for n in pb)
    for key in sorted(worst):
        log("WORST %s %s=%.4f at_frame=%d" % (stem, key, worst[key][0], worst[key][1]))
    log("SEAM %s frame0_vs_frame%d max_pos_m=%.5f max_rot_deg=%.4f" % (stem, frames, seam_pos, seam_rot))
    return frames


def setup_stage(scene):
    mat = bpy.data.materials.new("ref_grey")
    mat.diffuse_color = (0.72, 0.72, 0.76, 1.0)
    # One 1 m cube per view, standing behind the figure so the figure can fill the tile.
    cubes = {}
    for view, loc in (("front", (0.0, 1.3, 0.5)), ("side", (-1.3, 0.0, 0.5))):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        cube = bpy.context.object
        cube.name = "ref_cube_1m_" + view
        cube.data.materials.append(mat)
        cubes[view] = cube
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, -0.01))
    tray = bpy.context.object
    tray.name = "tray_1x1m"
    tray.scale = (1.0, 1.0, 0.02)
    tray.data.materials.append(mat)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_object_outline = True
    scene.render.resolution_x, scene.render.resolution_y = TILE_W, TILE_H
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.92, 0.92, 0.9)
    views = {}
    for view, loc, rot in (
        ("front", (0.0, -6.0, 1.08), (math.radians(90), 0.0, 0.0)),
        ("side", (6.0, 0.0, 1.08), (math.radians(90), 0.0, math.radians(90))),
    ):
        cam_data = bpy.data.cameras.new(view)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 2.4
        cam = bpy.data.objects.new("cam_" + view, cam_data)
        scene.collection.objects.link(cam)
        cam.location, cam.rotation_euler = loc, rot
        views[view] = (cam, cubes)
    return views


def prove(stem, scene, cam, body, view, k):
    from bpy_extras.object_utils import world_to_camera_view

    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [body.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    uv = [world_to_camera_view(scene, cam, Vector((x, y, z))) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    umin, umax = min(p.x for p in uv), max(p.x for p in uv)
    vmin, vmax = min(p.y for p in uv), max(p.y for p in uv)
    centre = (lo + hi) * 0.5
    direction = (cam.matrix_world.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()
    hit, _loc, _n, _i, obj, _m = scene.ray_cast(dg, centre - direction * 5.0, direction)
    obj_name = obj.name if obj else None
    log("INFRAME %s %s frame=%d u=%.3f..%.3f v=%.3f..%.3f centre_ray_hits=%s" % (stem, view, k, umin, umax, vmin, vmax, obj_name))
    if umin < 0.02 or umax > 0.98 or vmin < 0.02 or vmax > 0.98:
        invalid("%s %s frame %d: subject outside the frame" % (stem, view, k))
    if obj is None or obj.name != body.name:
        invalid("%s %s frame %d: subject occluded by %s" % (stem, view, k, obj_name))


def plates(stem, scene, arm, body, frames, out_dir):
    views = setup_stage(scene)
    picks = [round(frames * i / (STRIP - 1)) for i in range(STRIP)]
    log("STRIP %s frames=%s (left to right, top row then bottom row)" % (stem, picks))
    for view, (cam, cubes) in views.items():
        scene.camera = cam
        for name, cube in cubes.items():
            cube.hide_render = name != view
        tiles = []
        for k in picks:
            scene.frame_set(k)
            prove(stem, scene, cam, body, view, k)
            path = os.path.join(out_dir, "frames", "%s_%s_%03d.png" % (stem, view, k))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(path)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(TILE_H, TILE_W, 4)
            bpy.data.images.remove(img)
            px[:3, :, :3] = 0.2
            px[:, :3, :3] = 0.2
            tiles.append(px)
        cols = STRIP // 2
        rows = [np.concatenate(tiles[r * cols:(r + 1) * cols], axis=1) for r in (1, 0)]
        sheet = np.concatenate(rows, axis=0)
        h, w = sheet.shape[:2]
        out = bpy.data.images.new("sheet", w, h, alpha=True)
        out.pixels = sheet.ravel()
        out.filepath_raw = os.path.join(out_dir, "%s_shower_%s_sheet.png" % (stem, view))
        out.file_format = "PNG"
        out.save()
        log("PLATE %s" % out.filepath_raw)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir, paths = argv[0], argv[1:]
    os.makedirs(os.path.join(out_dir, "frames"), exist_ok=True)
    for path in paths:
        stem = os.path.splitext(os.path.basename(path))[0]
        scene, arm, body = load(path)
        clip_list(stem, arm)
        if CLIP not in bpy.data.actions:
            invalid("%s has no %s clip" % (stem, CLIP))
        frames = check(stem, scene, arm, body)
        if os.environ.get("SHOWER_PLATES", "1") == "1" and ("male_character_01" in stem):
            plates(stem, scene, arm, body, frames, out_dir)


main()
