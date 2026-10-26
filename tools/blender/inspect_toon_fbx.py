"""Inspect Toon Series FBX files: unit scale, bounds, materials, images, armatures.

Run: blender --background --python tools/blender/inspect_toon_fbx.py -- <fbx> [<fbx> ...]
Prints one INSPECT line per file. Read-only on the sources.
"""

import re
import sys

import bpy
from mathutils import Vector


def unit_scale_factor(path):
    with open(path, "rb") as f:
        data = f.read()
    m = re.search(rb"UnitScaleFactor.{0,40}?([0-9]+(?:\.[0-9]+)?)", data)
    if not m:
        # Binary FBX stores the property as 'UnitScaleFactor' then type codes then a double.
        i = data.find(b"UnitScaleFactor")
        if i < 0:
            return None
        import struct

        j = data.find(b"D", i + 15)
        while j > 0 and j < i + 120:
            try:
                v = struct.unpack("<d", data[j + 1 : j + 9])[0]
                if 0.0001 < v < 100000:
                    return v
            except struct.error:
                pass
            j = data.find(b"D", j + 1)
        return None
    return float(m.group(1))


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def main():
    paths = sys.argv[sys.argv.index("--") + 1 :]
    for p in paths:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=p)
        bpy.context.view_layer.update()
        objs = list(bpy.context.scene.objects)
        lo, hi = world_bounds(objs)
        size = hi - lo
        mats = sorted({s.material.name for o in objs if o.type == "MESH" for s in o.material_slots if s.material})
        imgs = sorted({i.name + ":" + i.filepath for i in bpy.data.images})
        arm = [o for o in objs if o.type == "ARMATURE"]
        scales = sorted({tuple(round(v, 3) for v in o.matrix_world.to_scale()) for o in objs})
        verts = sum(len(o.data.vertices) for o in objs if o.type == "MESH")
        print(
            "INSPECT",
            p.split("/")[-1],
            "usf=%s" % unit_scale_factor(p),
            "size=(%.2f, %.2f, %.2f)" % tuple(size),
            "min=(%.2f, %.2f, %.2f)" % tuple(lo),
            "verts=%d" % verts,
            "objs=%d" % len(objs),
            "scales=%s" % scales,
            "mats=%s" % mats,
            "imgs=%s" % imgs,
            "arm=%s" % [(a.name, len(a.data.bones)) for a in arm],
            "actions=%s" % [(a.name, tuple(round(x) for x in a.frame_range)) for a in bpy.data.actions],
        )


main()
