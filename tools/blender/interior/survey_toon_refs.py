"""Read-only survey of the reference assets for the interior kit.

Imports tp_airport_01a and the two characters from game/assets, prints their
bounds, and lists which TP_Atlas_1A_D swatches (32 columns by 16 rows) the
terminal's faces use, by UV area, with the swatch colour sampled from the PNG.

Run:
  blender.exe --background --factory-startup --python tools/blender/interior/survey_toon_refs.py
"""

import os
from collections import defaultdict

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GAME = os.path.join(ROOT, "game", "assets")
COLS, ROWS = 32, 16


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in objs:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    return [o for o in bpy.data.objects if o not in before]


atlas = bpy.data.images.load(os.path.join(GAME, "textures", "tp_atlas_1a_d.png"))
W, H = atlas.size
px = list(atlas.pixels)


def sample(u, v):
    x = min(W - 1, max(0, int(u * W)))
    y = min(H - 1, max(0, int(v * H)))
    i = (y * W + x) * 4
    return tuple(round(px[i + k] * 255) for k in range(3))


for name in ("buildings/tp_airport_01a.glb", "people/tcp_male_character_01.glb",
             "people/tcp_female_character_01.glb"):
    objs = import_glb(os.path.join(GAME, name))
    lo, hi = bounds(objs)
    print("BOUNDS %s lo=%s hi=%s size=%s" % (name, tuple(round(a, 3) for a in lo),
          tuple(round(a, 3) for a in hi), tuple(round(a, 3) for a in hi - lo)))
    if "airport" not in name:
        continue
    area = defaultdict(float)
    vspan = defaultdict(list)
    for ob in objs:
        if ob.type != "MESH" or not ob.data.uv_layers:
            continue
        me = ob.data
        uv = me.uv_layers.active.data
        for poly in me.polygons:
            us = [uv[li].uv for li in poly.loop_indices]
            cu = sum(p.x for p in us) / len(us)
            cv = sum(p.y for p in us) / len(us)
            mat = me.materials[poly.material_index].name if me.materials else "?"
            col = int(cu * COLS) % COLS
            row = int((1.0 - cv) * ROWS) % ROWS
            area[(mat, col, row)] += poly.area
            vspan[(mat, col, row)].append(max(p.y for p in us) - min(p.y for p in us))
    total = sum(area.values())
    for key, a in sorted(area.items(), key=lambda kv: -kv[1])[:40]:
        mat, col, row = key
        u = (col + 0.5) / COLS
        v = 1.0 - (row + 0.5) / ROWS
        spans = vspan[key]
        print("SWATCH mat=%s col=%d row=%d share=%.3f rgb=%s mean_vspan=%.4f" % (
            mat, col, row, a / total, sample(u, v), sum(spans) / len(spans)))
