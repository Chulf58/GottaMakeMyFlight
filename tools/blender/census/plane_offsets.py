"""Measure the plane, runway and jet bridge .glb files in game/assets/ (board f7ceaeeb).

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 \
        --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\census\\plane_offsets.py'

Read-only. It imports each WRITTEN .glb (never the vendor FBX), takes the true vertex
bounds in Godot axes (x, y up, z) about the file origin and prints one line per model.
For a plane it also prints the numbers game/flights/plane_models.gd records:
- nose and tail about the origin (every plane faces +z; anything else stops the run);
- model_offset, which puts the middle of the plane's box on the pose point, as
  PlaneView's model_offset does (its doc: "so its middle sits on the pose point");
- half-span, and the swing radius about the pose point: the half diagonal of the box,
  rounded up to 0.1 m (the same rule as stand_placement.gd SWING_RADIUS_M);
- one door point per *Door* part (runway_census.plane_measure), in model coordinates:
  the door's middle along the plane, its outer face across, its sill height.
Then GDSCRIPT lines, ready to paste into the table.
"""

import math
import os
import sys

import bpy
import numpy as np

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
import runway_census as census  # noqa: E402

PLANES = ["tp_plane_03a", "tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
PIECES = {
    "tp_runway_01a": "airside",
    "tp_runway_02a": "airside",
    "tp_runway_03a": "airside",
    "tp_runway_04a": "airside",
    "tp_runway_05a": "airside",
    "tp_loading_truck_01a": "vehicles",
}


def log(*a):
    print(*a, flush=True)


def die(msg):
    log("OFFSETS_FAIL", msg)
    sys.exit(1)


def load(rel):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, *rel.split("/")))
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        die("%s has no mesh" % rel)
    empty = [o.name for o in meshes for s in o.material_slots if s.material is None]
    if empty:
        die("%s: empty material slots on %s" % (rel, empty))
    verts = census.world_verts(meshes)
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    # Godot (x, y, z) = Blender (x, z, -y).
    glo = (lo[0], lo[2], -hi[1])
    ghi = (hi[0], hi[2], -lo[1])
    return meshes, verts, glo, ghi


def v3(v):
    return "Vector3(%.2f, %.2f, %.2f)" % tuple(0.0 if abs(c) < 0.005 else c for c in v)


def plane(stem):
    rel = "game/assets/planes/%s.glb" % stem
    meshes, verts, glo, ghi = load(rel)
    pm = census.plane_measure(verts, meshes)
    if pm["nose_godot"] != "+z" or pm["method"] != "fuselage+yoke":
        die("%s: nose %s by %s, expected +z by fuselage+yoke" % (stem, pm["nose_godot"], pm["method"]))
    fus, _ = census.part_verts(meshes, r"_Fuselage$")
    centre = (fus[:, 0].min() + fus[:, 0].max()) / 2.0
    nose = ghi[2]
    tail = -glo[2]
    off = (-(glo[0] + ghi[0]) / 2.0, 0.0, -(glo[2] + ghi[2]) / 2.0)
    length = ghi[2] - glo[2]
    span = ghi[0] - glo[0]
    swing = census.ceil1(math.hypot(length / 2.0, span / 2.0))
    doors = []
    for part, aft, side, sill, tall, _wide in pm["doors"]:
        if side[0] >= 0.0:
            x = centre + side[1]
        elif side[1] <= 0.0:
            x = centre + side[0]
        else:
            die("%s: door %s straddles the centreline %s" % (stem, part, side))
        point = (x, glo[1] + sill, nose - aft)
        # A door split into parts (04A: Door_Upper over Door_Lower) is one door: keep the
        # part with the lowest sill.
        same = [i for i, d in enumerate(doors) if (d[1][0] > 0) == (x > 0) and abs(d[1][2] - point[2]) < 0.1]
        if same:
            kept = doors[same[0]]
            log("  MERGE %s %s into %s" % (stem, part, kept[0]))
            if point[1] < kept[1][1]:
                doors[same[0]] = (part, point, tall)
            continue
        doors.append((part, point, tall))
    if not doors:
        die("%s has no door part" % stem)
    log("PLANE %s length=%.2f span=%.2f height=%.2f nose=%.2f tail=%.2f about the origin; centre_x=%.3f"
        % (stem, length, span, ghi[1] - glo[1], nose, tail, centre))
    log("  POSE %s model_offset=%s -> nose %.2f tail %.2f half_span %.2f swing_radius %.1f"
        % (stem, v3(off), nose + off[2], tail - off[2], span / 2.0, swing))
    for part, p, tall in doors:
        log("  DOOR %s %-14s point %s (%.2f m tall)" % (stem, part, v3(p), tall))
    log("GDSCRIPT\t\"%s\": {" % stem)
    log("GDSCRIPT\t\t\"path\": \"res://assets/planes/%s.glb\"," % stem)
    log("GDSCRIPT\t\t\"aabb\": AABB(%s, %s)," % (v3(glo), v3(np.subtract(ghi, glo))))
    log("GDSCRIPT\t\t\"length\": %.2f," % length)
    log("GDSCRIPT\t\t\"half_span\": %.2f," % (span / 2.0))
    log("GDSCRIPT\t\t\"nose\": %.2f," % nose)
    log("GDSCRIPT\t\t\"tail\": %.2f," % tail)
    log("GDSCRIPT\t\t\"model_offset\": %s," % v3(off))
    log("GDSCRIPT\t\t\"doors\": [%s]," % ", ".join(v3(p) for _, p, _ in doors))
    log("GDSCRIPT\t\t\"swing_radius\": %.1f," % swing)
    log("GDSCRIPT\t},")


def piece(stem, category):
    rel = "game/assets/%s/%s.glb" % (category, stem)
    _, _, glo, ghi = load(rel)
    size = np.subtract(ghi, glo)
    log("PIECE %s size=%s min=%s max=%s" % (stem, v3(size), v3(glo), v3(ghi)))
    log("GDSCRIPT\t\"%s\": {\"path\": \"res://assets/%s/%s.glb\", \"aabb\": AABB(%s, %s)},"
        % (stem, category, stem, v3(glo), v3(size)))


def main():
    for stem in PLANES:
        plane(stem)
    for stem, category in PIECES.items():
        piece(stem, category)
    log("OFFSETS done %d planes, %d pieces" % (len(PLANES), len(PIECES)))


main()
