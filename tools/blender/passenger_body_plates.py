"""Six orthographic axis plates of passenger bodies (board 3fcd8e5a), at true scale beside a
1 m reference cube, in the idle's first pose.

Run from WSL (Blender is a Windows program, so it sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python '<repo>\\tools\\blender\\passenger_body_plates.py' -- <glb> [<glb> ...]

The studio, the in-frame proof (PROBE_INVALID when a corner of the subject's bounds falls
outside the frame margin) and the axis cameras are tools/blender/cleaner_body_plates.py's,
loaded without running its main(), which also needs the cleaners' "clean" clip. Plates go
to tools/blender/out/passenger_variety_20261114/six_axis/.
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "tools", "blender", "out", "passenger_variety_20261114", "six_axis")

with open(os.path.join(HERE, "cleaner_body_plates.py"), encoding="utf-8") as f:
    source = f.read()
if not source.rstrip().endswith("main()"):
    raise SystemExit("cleaner_body_plates.py no longer ends with main(); update this script")
plates = {"__file__": os.path.join(HERE, "cleaner_body_plates.py"), "__name__": "cleaner_body_plates"}
exec(compile(source.rstrip()[: -len("main()")], "cleaner_body_plates.py", "exec"), plates)


def main():
    glbs = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if not glbs:
        plates["fail"]("no .glb given")
    os.makedirs(OUT, exist_ok=True)
    for glb in glbs:
        scene, cam = plates["setup"]()
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
        objs = [o for o in bpy.data.objects if o not in before]
        for o in objs:
            # The glTF importer's bone-shape widget is not part of the body.
            if o.type == "MESH" and o.parent is None:
                o.hide_render = True
        arm = next(o for o in objs if o.type == "ARMATURE")
        stem = os.path.splitext(os.path.basename(glb))[0]
        idle = bpy.data.actions.get("idle")
        if idle is None:
            plates["fail"]("%s has no idle action" % stem)
        arm.animation_data_create()
        arm.animation_data.action = idle
        if idle.slots:
            arm.animation_data.action_slot = idle.slots[0]
        scene.frame_set(0)
        mats = sorted({m.name for o in objs if o.type == "MESH" for m in o.data.materials if m})
        images = sorted({i.name for i in bpy.data.images if i.users})
        print("BODY %s objects=%d materials=%s images=%s" % (stem, len(objs), mats, images))
        for axis, (loc, rot) in plates["AXES"].items():
            cam.location = loc
            cam.rotation_euler = rot
            if axis in ("top", "bottom"):
                cam.location.x = 0.45
            else:
                cam.location.x += 0.45 if axis in ("front", "back") else 0.0
            plates["prove_in_frame"](scene, cam, objs, "%s %s" % (stem, axis))
            plates["render"](scene, os.path.join(OUT, "%s_%s.png" % (stem, axis)))


main()
