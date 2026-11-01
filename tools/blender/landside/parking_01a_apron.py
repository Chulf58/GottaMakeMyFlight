"""A paved apron in front of the Toon Planes surface car park TP_Parking_01A (board
297c9eb8), so the cars and walkers that leave the sidewalk for the lot stay on paving
instead of crossing a strip of lawn. The same idea as Parking_2A_Apron on the
multi-storey (parking_2a_entrance.py, board 0b82b7e4).

convert_toon_batch.py calls edit() for tp_parking_01a after the FBX import and the atlas
rebind, before the part checks and the export. The model stays at vendor scale.

The vendor model (measured on the converted tp_parking_01a.glb; mesh space equals
Godot/glTF local space, x from the entrance (-x) to the back, y up, z across):
- The lot's floor is at y 0.1. At its entrance the floor runs out to x -7.0 across
  z -4.75..4.75 (the throat; its floor faces run on to z +-5.0 under the islands), between
  two kerbed islands (y 0.2, z 4.75..6.15 either side, from x -7.0) that curve back to
  the side kerbs.
- The barrier posts stand on x -7 at z +-7 (their bases x -7.3..-6.7, y 0..0.5), outside
  the islands, on the lawn.

In the game LandsidePlaces turns the lot so local -x faces the road and puts the
barrier line (local x -7) on the gate of lot spot 0 (world z -37.5). The road's sidewalk
behind the kerb is world z -41.25..-40.0, top y 0.2, and the lawn (the main scene's
ground plane) is at y -0.1. So there is 2.5 m of lawn between the sidewalk's back edge
(local x -9.5) and the lot.

The apron is a separate mesh object, TP_Parking_01A_Apron, so the lot's own bounds (the
lot spot's footprint, checked by test_landside_geometry.gd) stay as they are. Its top is
at road and lot height (y 0.1), flat, from under the sidewalk (local x -9.7) to the lot's
front edge (x -7.0), across z -7.7..7.7 (both barrier posts and 0.4 m past them), with a
tab under each post's base to x -6.5 (z 6.3..7.7 either side; the islands end at z 6.15),
so the posts stand on paving. Its sides go down to the lawn (y -0.1). Its face at x -7.0
is left out: it would lie inside the lot's floor slab. Every face takes one UV, the
middle of the lot's own floor face in the throat, so it is the same asphalt.
"""

import bmesh
import bpy
from mathutils import Vector

MESH_NAME = "TP_Parking_01A"
APRON_NAME = "TP_Parking_01A_Apron"
FLOOR_Y = 0.1
LAWN_Y = -0.1
# The throat's floor faces at the entrance, as measured (they run under the islands' inner edge).
THROAT_X = (-7.0, -5.06)
THROAT_Z = 5.0
# The apron, in asset-local Godot axes.
APRON_START_X = -9.7
FRONT_X = -7.0
APRON_HALF_Z = 7.7
TAB_END_X = -6.5
TAB_INNER_Z = 6.3
# The islands' outer edge at the front (z +-6.15, x -7.0..-6.23): the tabs keep clear of it.
ISLAND_OUTER_Z = 6.15
TOL = 0.011


class Fail(Exception):
    pass


def _near(a, b):
    return abs(a - b) <= TOL


def _throat_floor(bm):
    """The largest up-facing floor face (y 0.1) inside the throat at the entrance; Fail
    if the vendor file changed."""
    faces = []
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        if f.normal.y < 0.99 or not all(_near(v.y, FLOOR_Y) for v in vs):
            continue
        if not all(THROAT_X[0] - TOL <= v.x <= THROAT_X[1] + TOL and abs(v.z) <= THROAT_Z + TOL for v in vs):
            continue
        faces.append(f)
    if not faces:
        raise Fail("no floor face in the throat x %s |z| <= %.2f" % (THROAT_X, THROAT_Z))
    front = [f for f in faces if any(_near(v.co.x, FRONT_X) for v in f.verts)]
    if not front:
        raise Fail("the throat floor does not reach x %.2f" % FRONT_X)
    return max(faces, key=lambda f: f.calc_area()), len(faces)


def _islands_clear(bm):
    """Fail when anything over the floor stands where the tabs go (between the islands'
    outer edge and the posts, in front of x TAB_END_X), so a changed vendor file never
    gets an apron cut through it."""
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        if max(v.y for v in vs) <= FLOOR_Y + TOL:
            continue
        for v in vs:
            inside_x = FRONT_X + TOL < v.x < TAB_END_X - TOL
            inside_z = ISLAND_OUTER_Z + TOL < abs(v.z) < TAB_INNER_Z - TOL
            if inside_x and inside_z:
                raise Fail("vertex %s stands between an island and a post" % (tuple(round(c, 3) for c in v),))


def _uv_middle(face, layers):
    """Per UV layer, the mean UV of the face's corners, and the largest distance of a
    corner from it (the swatch's spread)."""
    out = []
    spread = 0.0
    for layer in layers:
        uvs = [Vector(l[layer].uv) for l in face.loops]
        mid = sum(uvs, Vector((0.0, 0.0))) / len(uvs)
        spread = max(spread, max((u - mid).length for u in uvs))
        out.append(tuple(mid))
    return out, spread


def _add_face(bm, verts, up, uvs, layers):
    """A face through `verts`, turned so its normal points along `up`, every corner on
    layer k's UV uvs[k]."""
    face = bm.faces.new(verts)
    face.material_index = 0
    face.normal_update()
    if face.normal.dot(Vector(up)) < 0:
        face.normal_flip()
        face.normal_update()
    if face.normal.dot(Vector(up)) < 0.99:
        raise Fail("new face normal %s not along %s" % (tuple(face.normal), up))
    for loop in face.loops:
        for k, layer in enumerate(layers):
            loop[layer].uv = uvs[k]
    return face


def _build(bm, layers, uv):
    """The apron's faces: the top in five quads (the main run split at the tabs, and the
    two tabs), and the walls round its outline down to the lawn."""
    xs = (APRON_START_X, FRONT_X, TAB_END_X)
    zs = (-APRON_HALF_Z, -TAB_INNER_Z, TAB_INNER_Z, APRON_HALF_Z)
    top = {}
    low = {}

    def vert(table, x, z, y):
        key = (x, z)
        if key not in table:
            table[key] = bm.verts.new((x, y, z))
        return table[key]

    def quad(x0, x1, z0, z1):
        return [vert(top, x0, z0, FLOOR_Y), vert(top, x1, z0, FLOOR_Y), vert(top, x1, z1, FLOOR_Y), vert(top, x0, z1, FLOOR_Y)]

    for k in range(3):
        _add_face(bm, quad(xs[0], xs[1], zs[k], zs[k + 1]), (0, 1, 0), uv, layers)
    _add_face(bm, quad(xs[1], xs[2], zs[0], zs[1]), (0, 1, 0), uv, layers)
    _add_face(bm, quad(xs[1], xs[2], zs[2], zs[3]), (0, 1, 0), uv, layers)
    # The outline, going round; each wall faces out of the apron. The run along x -7.0
    # between the tabs (inside the lot's floor slab) is left out.
    outline = [
        ((xs[0], zs[3]), (xs[0], zs[0]), (-1, 0, 0)),
        ((xs[0], zs[0]), (xs[2], zs[0]), (0, 0, -1)),
        ((xs[2], zs[0]), (xs[2], zs[1]), (1, 0, 0)),
        ((xs[2], zs[1]), (xs[1], zs[1]), (0, 0, 1)),
        ((xs[1], zs[2]), (xs[2], zs[2]), (0, 0, -1)),
        ((xs[2], zs[2]), (xs[2], zs[3]), (1, 0, 0)),
        ((xs[2], zs[3]), (xs[0], zs[3]), (0, 0, 1)),
    ]
    for a, b, out in outline:
        verts = [vert(top, *a, FLOOR_Y), vert(top, *b, FLOOR_Y), vert(low, *b, LAWN_Y), vert(low, *a, LAWN_Y)]
        _add_face(bm, verts, out, uv, layers)


def edit(objs):
    """Add the apron beside TP_Parking_01A. Prints one TOON EDIT line with what it added."""
    mesh_objs = [o for o in objs if o.type == "MESH" and o.name == MESH_NAME]
    if len(mesh_objs) != 1:
        raise Fail("expected one %s mesh, found %d" % (MESH_NAME, len(mesh_objs)))
    o = mesh_objs[0]
    src = bmesh.new()
    src.from_mesh(o.data)
    src.normal_update()
    layers_src = list(src.loops.layers.uv.values())
    if not layers_src:
        raise Fail("no UV layers")
    floor, floor_faces = _throat_floor(src)
    _islands_clear(src)
    uv, spread = _uv_middle(floor, layers_src)
    mat = o.data.materials[floor.material_index]
    src.free()

    me = bpy.data.meshes.new(APRON_NAME)
    me.materials.append(mat)
    bm = bmesh.new()
    layers = [bm.loops.layers.uv.new(layer.name) for layer in o.data.uv_layers]
    _build(bm, layers, uv)
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
    ys = [v.co.y for v in me.vertices]
    print(
        "TOON EDIT %s x=%.2f..%.2f (tabs to %.2f) z=%.2f..%.2f top_y=%.3f bottom_y=%.3f faces=%d "
        "material=%s uv_layers=%d uv0=(%.4f, %.4f) uv_swatch_spread=%.4f throat_faces=%d"
        % (APRON_NAME, APRON_START_X, FRONT_X, TAB_END_X, -APRON_HALF_Z, APRON_HALF_Z, max(ys), min(ys),
           len(me.polygons), mat.name, len(me.uv_layers), uv[0][0], uv[0][1], spread, floor_faces),
        flush=True,
    )
    return apron
