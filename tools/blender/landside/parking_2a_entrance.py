"""A level way from the front entrance of the Toon City Parking_2A multi-storey to its
ground-floor stalls (user ruling 2026-10-30 through the question form, "Edit the model in
Blender (Recommended)"; decision multi-storey-car-park-ground-floor-cut-a-level-entrance-thro).

convert_toon_batch.py calls edit() for tc_parking_2a after the FBX import and the atlas
rebind, before the part checks and the export. The model stays at vendor scale and heading.

The vendor model (measured on Parking_2A.fbx; mesh space equals Godot/glTF local space
here, x across, y up, z along the building, the front at z -26):
- The ground floor is one quad at y 0.3. The front wall (1.2 m high) runs z -23.2..-21.9
  with the entrance opening east of x 2.0; behind the opening the ramp to the first deck
  starts at y 0.3 on z -21.9 and climbs 0.2 m by z -15.5 (x 1.7..8.3).
- Between the ramp and the stalls a kerb box (x 1.0..1.7, 0.2 m high over the ramp, its
  three faces running z -21.9..-15.5) blocks every level way to the stalls.

The edit cuts the kerb from the front wall to z GAP_END: its three faces are replaced by
the same faces from GAP_END on, an end cap at GAP_END, and a floor wedge in the gap that
joins the ground floor (y 0.3 at x 1.0) to the ramp's edge (its height at x 1.7). A car
driving west along z -20 then never meets a step: 0.06 m down evenly over 0.7 m. New faces take
their UVs from the faces they continue (kerb sides, kerb top, the ground floor quad), on
every UV layer, and their material slot.

It also adds the paved apron in front of the entrance (board ef2fd76d; decision
car-park-slab-step-cars-climb-a-ramp-in-the-access-lane-data): a separate mesh object,
Parking_2A_Apron, so the building's own bounds (the lot spot's footprint) stay as they
are. It spans the entrance opening (x 2.05..7.95) from under the sidewalk (z -32) to the
slab's front edge (z -26), its top at road height (y 0.1) to z -30 and then rising evenly
to the slab (y 0.3), the same profile as the lot's access and way-out lane points in
starter_landside.tres (lot spot 1 stands at world z -8, so local z -30 is the lanes' foot
at world z -38). Its sides go down to the lawn (y -0.1). Every face takes one UV, the
low end of the car park's own ramp to the first deck, so it is the same paving.
"""

import bmesh
import bpy
from mathutils import Vector

MESH_NAME = "Parking_2A"
KERB_X = (1.0, 1.7)
KERB_Z = (-21.9, -15.5)
# Bottom and top of the kerb at its two ends (y at KERB_Z[0], y at KERB_Z[1]).
KERB_BOTTOM = (0.2, 0.3)
KERB_TOP = (0.5, 0.7)
# The ramp beside the kerb: y 0.3 at z -21.9, 0.5 at z -15.5.
RAMP_Y = (0.3, 0.5)
FLOOR_Y = 0.3
# The gap runs from the front wall to here: 4 m, a 2.5 m car plus 0.75 m either side.
GAP_END = -17.9
WEDGE_STRIPS = 8
TOL = 0.011
# The apron (asset-local, Godot axes). Its x is the entrance opening in the front wall.
APRON_NAME = "Parking_2A_Apron"
APRON_X = (2.05, 7.95)
# From under the sidewalk (world z -40; the sidewalk's back edge is near -39.7, its top
# y 0.2), flat at road height to the lanes' foot, then up to the slab's front edge.
APRON_START_Z = -32.0
APRON_FOOT_Z = -30.0
SLAB_EDGE_Z = -26.0
ROAD_Y = 0.1
LAWN_Y = -0.1
# The ramp to the first deck behind the entrance: x 1.7..8.3 on z -21.9..-15.5.
RAMP_X = (1.7, 8.3)


class Fail(Exception):
    pass


def _lerp_z(pair, z):
    t = (z - KERB_Z[0]) / (KERB_Z[1] - KERB_Z[0])
    return pair[0] + (pair[1] - pair[0]) * t


def _near(a, b):
    return abs(a - b) <= TOL


def _kerb_faces(bm):
    """The kerb's west side, east side and top, or Fail if the vendor file changed."""
    found = {}
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        if len(vs) != 4:
            continue
        xs = sorted({round(v.x, 2) for v in vs})
        zs = sorted({round(v.z, 2) for v in vs})
        if zs != [KERB_Z[0], KERB_Z[1]]:
            continue
        if xs == [KERB_X[0]]:
            found.setdefault("west", []).append(f)
        elif xs == [KERB_X[1]] and all(v.y > KERB_BOTTOM[0] - TOL for v in vs) and max(v.y for v in vs) > 0.6:
            found.setdefault("east", []).append(f)
        elif xs == [KERB_X[0], KERB_X[1]] and min(v.y for v in vs) > KERB_TOP[0] - TOL:
            found.setdefault("top", []).append(f)
    if sorted(found) != ["east", "top", "west"] or any(len(v) != 1 for v in found.values()):
        raise Fail("kerb faces not as measured: %s" % {k: len(v) for k, v in found.items()})
    for f in (found["west"][0], found["east"][0]):
        for v in f.verts:
            want = (_lerp_z(KERB_BOTTOM, v.co.z), _lerp_z(KERB_TOP, v.co.z))
            if not (_near(v.co.y, want[0]) or _near(v.co.y, want[1])):
                raise Fail("kerb side vertex %s off the measured slope" % tuple(v.co))
    return found["west"][0], found["east"][0], found["top"][0]


def _floor_face(bm):
    """The ground-floor quad (y 0.3 over the whole footprint)."""
    hits = []
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        if len(vs) == 4 and all(_near(v.y, FLOOR_Y) for v in vs):
            if min(v.x for v in vs) < -10 and max(v.x for v in vs) > 10 and min(v.z for v in vs) < -25 < 25 < max(v.z for v in vs):
                hits.append(f)
    if len(hits) != 1:
        raise Fail(
            "ground-floor quad: found %d %s"
            % (len(hits), [(f.index, tuple(round(c, 2) for c in f.normal), [tuple(v.co) for v in f.verts]) for f in hits])
        )
    return hits[0]


def _uv_by_height(face, layers):
    """Per UV layer, the UV of the face's bottom and top vertices (a kerb side maps every
    bottom vertex to one UV and every top vertex to another)."""
    out = []
    for layer in layers:
        ys = sorted(loop.vert.co.y for loop in face.loops)
        mid = (ys[0] + ys[-1]) / 2.0
        low = {tuple(round(c, 5) for c in l[layer].uv) for l in face.loops if l.vert.co.y < mid}
        high = {tuple(round(c, 5) for c in l[layer].uv) for l in face.loops if l.vert.co.y >= mid}
        if len(low) != 1 or len(high) != 1:
            raise Fail("kerb side UVs vary along the face: %s %s" % (low, high))
        out.append((low.pop(), high.pop()))
    return out


def _uv_constant(face, layers):
    out = []
    for layer in layers:
        uvs = {tuple(round(c, 5) for c in l[layer].uv) for l in face.loops}
        if len(uvs) != 1:
            raise Fail("kerb top UVs vary: %s" % uvs)
        out.append(uvs.pop())
    return out


def _uv_on_quad(face, layers, x, z):
    """Per layer, the UV at (x, z) on an axis-aligned quad, bilinear between its corners."""
    xs = [l.vert.co.x for l in face.loops]
    zs = [l.vert.co.z for l in face.loops]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    s, t = (x - x0) / (x1 - x0), (z - z0) / (z1 - z0)
    out = []
    for layer in layers:
        corner = {}
        for l in face.loops:
            corner[(_near(l.vert.co.x, x1), _near(l.vert.co.z, z1))] = Vector(l[layer].uv)
        if len(corner) != 4:
            raise Fail("ground-floor quad is not axis-aligned")
        a = corner[(False, False)].lerp(corner[(True, False)], s)
        b = corner[(False, True)].lerp(corner[(True, True)], s)
        out.append(tuple(a.lerp(b, t)))
    return out


def _add_face(bm, points, up, material, uvs, layers, min_dot=0.99):
    """A face through `points` (Godot local), turned so its normal points along `up`;
    uvs[k][i] is layer k's UV for point i."""
    verts = [bm.verts.new(p) for p in points]
    face = bm.faces.new(verts)
    face.material_index = material
    face.normal_update()
    if face.normal.dot(Vector(up)) < 0:
        face.normal_flip()
        face.normal_update()
    by_vert = {v: i for i, v in enumerate(verts)}
    for loop in face.loops:
        i = by_vert[loop.vert]
        for k, layer in enumerate(layers):
            loop[layer].uv = uvs[k][i]
    if face.normal.dot(Vector(up)) < min_dot:
        raise Fail("new face normal %s not along %s" % (tuple(face.normal), up))
    return face


def _ramp_low_uv(bm, layers):
    """Per UV layer, the UV of the low (y 0.3) end of the ramp to the first deck, taken
    from its largest up-facing face; Fail when the ramp is not where it was measured or
    its low end has more than one UV."""
    faces = []
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        if abs(f.normal.y) < 0.9:
            continue
        if not all(RAMP_X[0] - TOL <= v.x <= RAMP_X[1] + TOL and KERB_Z[0] - TOL <= v.z <= KERB_Z[1] + TOL for v in vs):
            continue
        if not all(RAMP_Y[0] - TOL <= v.y <= RAMP_Y[1] + TOL for v in vs):
            continue
        faces.append(f)
    if not faces:
        raise Fail("no ramp face on x %s z %s" % (RAMP_X, KERB_Z))
    face = max(faces, key=lambda f: f.calc_area())
    out = []
    for layer in layers:
        low = {tuple(round(c, 5) for c in l[layer].uv) for l in face.loops if _near(l.vert.co.y, RAMP_Y[0])}
        if len(low) != 1:
            raise Fail("ramp low-end UVs: %s" % low)
        out.append(low.pop())
    return out, face.material_index, len(faces)


def _apron_y(z):
    """The apron's top at z: road height to the lanes' foot, then evenly up to the slab."""
    if z <= APRON_FOOT_Z:
        return ROAD_Y
    return ROAD_Y + (FLOOR_Y - ROAD_Y) * (z - APRON_FOOT_Z) / (SLAB_EDGE_Z - APRON_FOOT_Z)


def _add_apron(o, objs, uv, material):
    """The apron as its own mesh object beside `o`, in `o`'s mesh space and transform,
    with `o`'s UV layers and `material`; appended to `objs` so the converter's part
    checks and export cover it."""
    me = bpy.data.meshes.new(APRON_NAME)
    me.materials.append(material)
    bm = bmesh.new()
    layers = [bm.loops.layers.uv.new(layer.name) for layer in o.data.uv_layers]
    x0, x1 = APRON_X
    za, zf, zs = APRON_START_Z, APRON_FOOT_Z, SLAB_EDGE_Z
    flat = [[uv[k]] * 4 for k in range(len(layers))]
    # Top: the flat run under and behind the sidewalk, then the slope to the slab.
    _add_face(bm, [(x0, ROAD_Y, za), (x1, ROAD_Y, za), (x1, ROAD_Y, zf), (x0, ROAD_Y, zf)], (0, 1, 0), 0, flat, layers)
    _add_face(bm, [(x0, ROAD_Y, zf), (x1, ROAD_Y, zf), (x1, FLOOR_Y, zs), (x0, FLOOR_Y, zs)], (0, 1, 0), 0, flat, layers, min_dot=0.99)
    # The two sides, down to the lawn, and the front (inside the sidewalk).
    for x, out in ((x0, -1), (x1, 1)):
        pts = [(x, LAWN_Y, za), (x, ROAD_Y, za), (x, ROAD_Y, zf), (x, FLOOR_Y, zs), (x, LAWN_Y, zs)]
        _add_face(bm, pts, (out, 0, 0), 0, [[uv[k]] * 5 for k in range(len(layers))], layers)
    _add_face(bm, [(x0, LAWN_Y, za), (x0, ROAD_Y, za), (x1, ROAD_Y, za), (x1, LAWN_Y, za)], (0, 0, -1), 0, flat, layers)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    apron = bpy.data.objects.new(APRON_NAME, me)
    for coll in o.users_collection:
        coll.objects.link(apron)
    apron.parent = o.parent
    apron.matrix_parent_inverse = o.matrix_parent_inverse.copy()
    apron.matrix_basis = o.matrix_basis.copy()
    objs.append(apron)
    return apron


def edit(objs):
    """Cut the kerb gap in Parking_2A and add the apron. Prints one EDIT line with what
    changed and one APRON line."""
    mesh_objs = [o for o in objs if o.type == "MESH" and o.name == MESH_NAME]
    if len(mesh_objs) != 1:
        raise Fail("expected one %s mesh, found %d" % (MESH_NAME, len(mesh_objs)))
    o = mesh_objs[0]
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    layers = list(bm.loops.layers.uv.values())
    if not layers:
        raise Fail("no UV layers")
    west, east, top = _kerb_faces(bm)
    floor = _floor_face(bm)
    side_uv = _uv_by_height(west, layers)
    side_uv_east = _uv_by_height(east, layers)
    top_uv = _uv_constant(top, layers)
    mat_side, mat_top, mat_floor = west.material_index, top.material_index, floor.material_index
    ramp_uv, mat_ramp, ramp_faces = _ramp_low_uv(bm, layers)
    # The slab's front face (y 0 to 0.3, in front of a 0.5 m lip before the floor quad)
    # stands on SLAB_EDGE_Z across the whole apron, so the apron meets it with no gap.
    fronts = [
        f for f in bm.faces
        if all(_near(v.co.z, SLAB_EDGE_Z) for v in f.verts)
        and max(v.co.y for v in f.verts) > FLOOR_Y - TOL
        and min(v.co.x for v in f.verts) < APRON_X[0] and max(v.co.x for v in f.verts) > APRON_X[1]
    ]
    if not fronts:
        raise Fail("no slab front face on z %.2f across x %s" % (SLAB_EDGE_Z, APRON_X))
    faces_before = len(bm.faces)

    x0, x1 = KERB_X
    za, zb = GAP_END, KERB_Z[1]
    bot_a, bot_b = _lerp_z(KERB_BOTTOM, za), KERB_BOTTOM[1]
    top_a, top_b = _lerp_z(KERB_TOP, za), KERB_TOP[1]
    ramp_a = _lerp_z(RAMP_Y, za)

    old = [west, east, top]
    old_verts = {v for f in old for v in f.verts}
    bmesh.ops.delete(bm, geom=old, context="FACES_ONLY")
    loose_edges = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=loose_edges, context="EDGES")
    loose = [v for v in old_verts if v.is_valid and not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")

    def side_uvs(uv, n_bottom_first):
        # points are ordered bottom, top, top, bottom (or as given by the pattern)
        return [[uv[k][0] if b else uv[k][1] for b in n_bottom_first] for k in range(len(layers))]

    # The kerb from GAP_END on: west side, east side, top, and a cap facing the gap.
    pattern = [True, False, False, True]
    _add_face(bm, [(x0, bot_a, za), (x0, top_a, za), (x0, top_b, zb), (x0, bot_b, zb)],
              (-1, 0, 0), mat_side, side_uvs(side_uv, pattern), layers)
    _add_face(bm, [(x1, bot_a, za), (x1, top_a, za), (x1, top_b, zb), (x1, bot_b, zb)],
              (1, 0, 0), mat_side, side_uvs(side_uv_east, pattern), layers)
    _add_face(bm, [(x0, top_a, za), (x1, top_a, za), (x1, top_b, zb), (x0, top_b, zb)],
              (0, 1, 0), mat_top, [[top_uv[k]] * 4 for k in range(len(layers))], layers)
    _add_face(bm, [(x0, bot_a, za), (x0, top_a, za), (x1, top_a, za), (x1, bot_a, za)],
              (0, 0, -1), mat_side, side_uvs(side_uv, pattern), layers)
    # The floor wedge in the gap: the ground floor at its west edge, the ramp's edge at
    # its east edge, so across the gap the floor rises evenly by the ramp's height over
    # the floor there (0 at the wall, 0.125 m at GAP_END). WEDGE_STRIPS strips along z,
    # each two triangles split on the diagonal that rises off the floor, so no part of
    # the wedge lies in the ground-floor plane (no z-fighting).
    zf = KERB_Z[0]
    for n in range(WEDGE_STRIPS):
        z_lo = zf + (za - zf) * n / WEDGE_STRIPS
        z_hi = zf + (za - zf) * (n + 1) / WEDGE_STRIPS
        corners = [(x0, FLOOR_Y, z_lo), (x1, _lerp_z(RAMP_Y, z_lo), z_lo),
                   (x1, _lerp_z(RAMP_Y, z_hi), z_hi), (x0, FLOOR_Y, z_hi)]
        for tri in ((0, 1, 2), (0, 2, 3)):
            pts = [corners[i] for i in tri]
            tri_uv = [[None] * 3 for _ in layers]
            for i, p in enumerate(pts):
                for k, uv in enumerate(_uv_on_quad(floor, layers, p[0], p[2])):
                    tri_uv[k][i] = uv
            _add_face(bm, pts, (0, 1, 0), mat_floor, tri_uv, layers, min_dot=0.95)
    # The ramp's west edge over the gap, from the ground floor up to the ramp: a sliver
    # 0 m high at the wall, (ramp_a - 0.3) m at GAP_END. The wedge covers it from above,
    # so it is not added; the kerb's east side below GAP_END is gone with the kerb.

    faces_after = len(bm.faces)
    bm.normal_update()
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    print(
        "TOON EDIT %s kerb_cut x=%.2f..%.2f z=%.2f..%.2f faces %d -> %d wedge_y=%.3f..%.3f "
        "custom_normals=%s uv_layers=%d"
        % (MESH_NAME, x0, x1, KERB_Z[0], GAP_END, faces_before, faces_after, FLOOR_Y, ramp_a,
           o.data.has_custom_normals, len(layers)),
        flush=True,
    )
    apron = _add_apron(o, objs, ramp_uv, o.data.materials[mat_ramp])
    ys = [v.co.y for v in apron.data.vertices]
    print(
        "TOON EDIT %s x=%.2f..%.2f z=%.2f..%.2f top_y=%.3f..%.3f bottom_y=%.3f faces=%d "
        "material=%s uv_layers=%d uv0=%s ramp_faces_seen=%d"
        % (APRON_NAME, APRON_X[0], APRON_X[1], APRON_START_Z, SLAB_EDGE_Z, _apron_y(APRON_START_Z),
           _apron_y(SLAB_EDGE_Z), min(ys), len(apron.data.polygons), apron.data.materials[0].name,
           len(apron.data.uv_layers), ramp_uv[0], ramp_faces),
        flush=True,
    )
