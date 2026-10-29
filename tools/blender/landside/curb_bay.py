"""The authored kerb drop-off bay: road markings for two berths, painted on the road
baked into game/assets/buildings/tp_airport_shell.glb.

convert_toon_batch.py calls build() for its "authored:curb_bay" BATCH entry instead of
importing an FBX, then runs the same export and written-file checks as for every other
asset. The bay is marking geometry only, so it never depends on the shell's canopy (the
roof group that shell_view.gd dissolves):

- Flat, single-sided, up-facing quads LIFT m above the asset origin. There are no side or
  bottom faces, so nothing is coplanar with the road and the toon outline hull (culled
  front faces of a normal-extruded copy) has no visible part.
- Frame (Godot/glTF axes): origin at the centre of the kerb line at road-top height
  (the shell's road and sidewalk top are one plane, y 0.107 in the shell's frame);
  x runs along the kerb, +z points away from the kerb into the road. The bay covers
  x -8..8, z 0..3.
- Two berths of 6.5 m between line centres (taxi 5.0 m, SUV 5.2 m, van 5.0 m long; van
  2.47 m wide in a 3.0 m bay), with a 1.5 m hatched end zone at each end. The kerb-side
  long edge has no line: the sidewalk edge is the boundary.
- Mount_Berth_1 and Mount_Berth_2 are empties at the berth centres (-3.25, 0, 1.5) and
  (3.25, 0, 1.5), identity rotation. They give stopping positions only; travel direction
  belongs to the landside lanes, and the markings are symmetric.
- Colour: every loop's UV is the road-line swatch of TP_Atlas_1A_D, the texel the shell's
  own road lines use (measured on the shell's Road mesh: UV (0.682, 0.99), RGB
  252,251,128). build() samples the atlas and stops if the texel has moved.
"""

import os

import bpy
from mathutils import Vector

STEM = "tp_curb_bay_01a"
MESH_NAME = "TP_Curb_Bay_01A"
# The FBX-side name, so the converter's TP rebind maps it to TP_Atlas_Simple_1A_D.
MATERIAL = "Atlas_Simple_1A_D"
LIFT = 0.02
LINE = 0.25
BERTH = 6.5
END_ZONE = 1.5
DEPTH = 3.0
HALF = BERTH + END_ZONE  # 8.0: half the bay length
HATCH_BAR = 0.2
HATCH_PITCH = 0.55
SWATCH_UV = (0.682, 0.99)
SWATCH_RGB = (252, 251, 128)
SWATCH_TOLERANCE = 12
# name -> (x, y, z) in Godot/glTF axes (the converter checks them in the written file).
MARKERS = {
    "Mount_Berth_1": (-BERTH / 2.0, 0.0, DEPTH / 2.0),
    "Mount_Berth_2": (BERTH / 2.0, 0.0, DEPTH / 2.0),
}


class Fail(Exception):
    pass


def _rect(x0, x1, z0, z1):
    """An axis-aligned rectangle in Godot (x, z), counter-clockwise seen from above."""
    return [(x0, z0), (x0, z1), (x1, z1), (x1, z0)]


def _clip(poly, x0, x1, z0, z1):
    """Sutherland-Hodgman clip of a convex polygon to the rectangle x0..x1, z0..z1."""
    edges = [
        (lambda p: p[0] >= x0, lambda a, b: (x0, a[1] + (b[1] - a[1]) * (x0 - a[0]) / (b[0] - a[0]))),
        (lambda p: p[0] <= x1, lambda a, b: (x1, a[1] + (b[1] - a[1]) * (x1 - a[0]) / (b[0] - a[0]))),
        (lambda p: p[1] >= z0, lambda a, b: (a[0] + (b[0] - a[0]) * (z0 - a[1]) / (b[1] - a[1]), z0)),
        (lambda p: p[1] <= z1, lambda a, b: (a[0] + (b[0] - a[0]) * (z1 - a[1]) / (b[1] - a[1]), z1)),
    ]
    for inside, cross in edges:
        out = []
        for i, cur in enumerate(poly):
            prev = poly[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cross(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cross(prev, cur))
        poly = out
        if not poly:
            break
    return poly


def _polygons():
    """Every marking polygon in Godot (x, z). Lines meet edge to edge, never overlap."""
    inner = DEPTH - LINE  # the road-side line covers z inner..DEPTH
    polys = [_rect(-HALF, HALF, inner, DEPTH)]
    # Cross lines below the road-side line: the two outer ends, the two end-zone limits
    # and the divider between the berths.
    for xc in (-HALF + LINE / 2.0, -BERTH, 0.0, BERTH, HALF - LINE / 2.0):
        polys.append(_rect(xc - LINE / 2.0, xc + LINE / 2.0, 0.0, inner))
    # Hatch bars at 45 degrees, clipped to the open part of each end zone.
    for side in (-1, 1):
        zx0 = -HALF + LINE if side < 0 else BERTH + LINE / 2.0
        zx1 = -BERTH - LINE / 2.0 if side < 0 else HALF - LINE
        k = 0
        start = zx0 - inner
        while start + k * HATCH_PITCH < zx1:
            a = start + k * HATCH_PITCH
            bar = [(a, 0.0), (a + inner, inner), (a + inner + HATCH_BAR, inner), (a + HATCH_BAR, 0.0)]
            if side > 0:  # mirror the slant so the two ends read as a pair
                bar = [(zx0 + zx1 - x, z) for x, z in reversed(bar)]
            clipped = _clip(bar, zx0, zx1, 0.0, inner)
            if len(clipped) >= 3:
                polys.append(clipped)
            k += 1
    return polys


def _check_swatch(atlas_png):
    img = bpy.data.images.load(atlas_png, check_existing=True)
    w, h = img.size
    if w == 0:
        raise Fail("atlas did not load: %s" % atlas_png)
    px = int(SWATCH_UV[0] * w) + int(SWATCH_UV[1] * h) * w
    rgb = tuple(round(c * 255) for c in img.pixels[px * 4 : px * 4 + 3])
    print("TOON BAY swatch uv=%s rgb=%s expected=%s" % (SWATCH_UV, rgb, SWATCH_RGB), flush=True)
    if any(abs(a - b) > SWATCH_TOLERANCE for a, b in zip(rgb, SWATCH_RGB)):
        raise Fail("road-line swatch at %s is %s, expected about %s" % (SWATCH_UV, rgb, SWATCH_RGB))


def build(atlas_png):
    """Build the bay into the (empty) current scene. Returns the created objects."""
    _check_swatch(atlas_png)
    verts, faces = [], []
    for poly in _polygons():
        base = len(verts)
        # Godot (x, z) -> Blender (x, -z). The polygons run clockwise in (x, z), which is
        # counter-clockwise from above in Blender, so the faces point up.
        for x, z in poly:
            verts.append((x, -z, LIFT))
        faces.append(list(range(base, base + len(poly))))
    me = bpy.data.meshes.new(MESH_NAME)
    me.from_pydata(verts, [], faces)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    for loop in uv.data:
        loop.uv = SWATCH_UV
    mat = bpy.data.materials.new(MATERIAL)
    me.materials.append(mat)
    obj = bpy.data.objects.new(MESH_NAME, me)
    bpy.context.scene.collection.objects.link(obj)
    down = [p.index for p in me.polygons if p.normal.z < 0.999]
    if down:
        raise Fail("%d bay faces do not point up" % len(down))
    created = [obj]
    for name, (x, y, z) in MARKERS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "ARROWS"
        e.location = Vector((x, -z, y))
        e.parent = obj
        bpy.context.scene.collection.objects.link(e)
        created.append(e)
    bpy.context.view_layer.update()
    area = sum(p.area for p in me.polygons)
    print("TOON BAY faces=%d verts=%d paint_area_m2=%.2f markers=%s" % (len(me.polygons), len(me.vertices), area, sorted(MARKERS)), flush=True)
    return created
