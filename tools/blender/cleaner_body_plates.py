"""Plates of the cleaner bodies (StaffCharacters role CLEANER) and their "clean" clip.

Run from WSL (Blender is a Windows program, so it sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python '<repo>\\tools\\blender\\cleaner_body_plates.py' -- <glb> [<glb> ...]

Each .glb is imported (as written by tools/blender/convert_toon_batch.py) and drawn at
true scale beside a 1 m reference cube: six orthographic axis views at the idle's first
pose, then a strip of the "clean" clip at five times. Every plate first projects the
subject's bounds into the camera and stops with PROBE_INVALID when a corner falls
outside the frame margin. Plates go to tools/blender/out/cleaner-views/body/.
"""

import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "tools", "blender", "out", "cleaner-views", "body")
MARGIN = 0.04
STRIP_S = (0.0, 1.0, 2.0, 3.0, 4.0)
AXES = {
    "front": (Vector((0, -6, 1)), (math.radians(90), 0, 0)),
    "back": (Vector((0, 6, 1)), (math.radians(90), 0, math.radians(180))),
    "left": (Vector((-6, 0, 1)), (math.radians(90), 0, math.radians(-90))),
    "right": (Vector((6, 0, 1)), (math.radians(90), 0, math.radians(90))),
    "top": (Vector((0, 0, 8)), (0, 0, 0)),
    "bottom": (Vector((0, 0, -8)), (math.radians(180), 0, 0)),
}


def fail(msg):
    print("PROBE_INVALID " + msg)
    sys.stdout.flush()
    os._exit(1)


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
        e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
    ] else "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.color = (0.75, 0.78, 0.82)
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.82, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
    scene.collection.objects.link(sun)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.9, 0, 0.5))
    cube = bpy.context.active_object
    cube.name = "ref_cube_1m"
    mat = bpy.data.materials.new("cube")
    mat.diffuse_color = (0.9, 0.35, 0.2, 1)
    cube.data.materials.append(mat)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.6
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene, cam


def bounds(objs):
    pts = []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type != "MESH" or o.parent is None:
            continue
        ev = o.evaluated_get(dg)
        mesh = ev.to_mesh()
        pts.extend(ev.matrix_world @ v.co for v in mesh.vertices)
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def prove_in_frame(scene, cam, objs, label):
    lo, hi = bounds(objs)
    worst = 1.0
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                p = world_to_camera_view(scene, cam, Vector((x, y, z)))
                worst = min(worst, p.x, p.y, 1.0 - p.x, 1.0 - p.y)
    print("IN_FRAME %s bounds=%s..%s height_m=%.3f worst_margin=%.3f" % (label, tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), hi.z - lo.z, worst))
    if worst < MARGIN:
        fail("%s subject leaves the frame (margin %.3f)" % (label, worst))


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PLATE " + path)


def main():
    glbs = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if not glbs:
        fail("no .glb given")
    os.makedirs(OUT, exist_ok=True)
    for glb in glbs:
        scene, cam = setup()
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
        objs = [o for o in bpy.data.objects if o not in before]
        print("IMPORTED %s" % [(o.name, o.type, tuple(round(v, 3) for v in o.dimensions)) for o in objs])
        for o in objs:
            # The glTF importer's bone-shape widget is not part of the body.
            if o.type == "MESH" and o.parent is None:
                o.hide_render = True
        arm = next(o for o in objs if o.type == "ARMATURE")
        stem = os.path.splitext(os.path.basename(glb))[0]
        clean = bpy.data.actions.get("clean")
        idle = bpy.data.actions.get("idle")
        if clean is None or idle is None:
            fail("%s has no clean or idle action" % stem)
        arm.animation_data_create()
        arm.animation_data.action = idle
        if idle.slots:
            arm.animation_data.action_slot = idle.slots[0]
        scene.frame_set(0)
        for axis, (loc, rot) in AXES.items():
            cam.location = loc
            cam.rotation_euler = rot
            if axis in ("top", "bottom"):
                cam.location.x = 0.45
            else:
                cam.location.x += 0.45 if axis in ("front", "back") else 0.0
            prove_in_frame(scene, cam, objs, "%s %s" % (stem, axis))
            render(scene, os.path.join(OUT, "%s_%s.png" % (stem, axis)))
        arm.animation_data.action = clean
        if clean.slots:
            arm.animation_data.action_slot = clean.slots[0]
        cam.location, cam.rotation_euler = Vector((4.2, -4.2, 1.0)), (math.radians(90), 0, math.radians(45))
        cam.data.ortho_scale = 3.4
        # The strip's three-quarter camera would see the cube in front of the body.
        bpy.data.objects["ref_cube_1m"].hide_render = True
        for t in STRIP_S:
            scene.frame_set(int(round(t * 25)))
            prove_in_frame(scene, cam, objs, "%s clean t=%.1f" % (stem, t))
            render(scene, os.path.join(OUT, "%s_clean_%02d.png" % (stem, int(t * 10))))


main()
