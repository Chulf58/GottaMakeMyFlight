"""Extract a buildable shell from the Toon terminal (tp_airport_01a.glb).

Run from WSL (Blender is a Windows program, so it sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python \
        'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\terminal_shell\\build_terminal_shell.py'

Optional after `--`: `--out <path.glb>` to write somewhere other than
game/assets/buildings/tp_airport_shell.glb. A relative path is taken from the repo root.
The path must end in .glb, stay inside the repo after symlinks and junctions are resolved,
and not pass through one; the source .glb is refused under any spelling and is only read.

Decision toon-terminal-shell-design-extracted-shell-glb-authored-shel, part 1.
All numbers below are Godot world coordinates with the terminal at (0, 0, -80) as
main.tscn places it (Godot x = Blender x, Godot y = Blender z, Godot z = -Blender y - 80).

What the source is (measured): the main node TP_Airport_01A is one mesh of 3845
loose islands, nearly all single quads. Inside the facade each storey is filled
with "filler": full-depth walls (0.36 m lattice, 0.09-0.11 m mullion walls, 0.23 m
sign-band boxes) whose two long faces run through the facade backdrop and whose
end caps outside it are the visible pilasters, mullions and sign marks; plus
full-footprint slab caps whose rims outside the backdrop are the visible ledges.

Method:
1. Islands. Every island of the main mesh gets one class by first match; every
   signature match is recorded, so a multi-match shows in the census.
   Nominees for deletion: FILLER = a planar vertical island at least 20 m long
   along its plane that has a TWIN (parallel, opposite normal, 0.08-0.40 m away,
   overlapping 90 percent of the longer one along the plane and in height), plus
   the long narrow caps that close such a pair at its top or bottom. SLAB = a
   planar horizontal island of 100 m2 or more. An up-facing SLAB that is not
   covered from above at every sample is a ROOF cap and is NOT a nominee.
   Pole cables (longer than 4 m in z, reaching above 5.5) are classed Upper,
   because they hang from the canopy that Upper carries.
2. Crossings (the only bisects of nominees): the envelope planes x -33.94 and
   32.94, z -95.25, -64.35 and -70.35 (the east setback), and y 5.5 (top of the
   ground storey). Non-nominee facade pieces that cross y 5.5 are cut there too,
   so the ground storey and Upper separate on that line.
3. Deletion by visibility, not by box: the envelope is every non-nominee face,
   the roof caps, the doors, Lights and Road. A nominee face is deleted only when
   no sample on it can see out past the envelope (26 ray directions on its front
   side). Faces that can see out are kept (the stubs and ledge rings); faces that
   are only partly visible are kept and listed as ambiguous. Two exceptions, each
   listed per fragment in the census: every nominee inside the ground-storey
   volume V goes, and an inside fragment that sees out through 10 percent or
   less of its samples goes (a crack between storey bands), except on the east
   setback face, whose rims and stubs stay. Overriding both deletions outside V: a
   fragment that shows in one of the six orthographic views of the ORIGINAL (a sample's
   ray along an axis on its front side, grazing included, escapes the original scene) is
   exterior and stays, such as the sloped soffits over the setback seen edge-on from the
   west, which the 26 directions (d . n > 0.1) never test. After deletion no nominee face
   may remain inside V.
4. Leftovers: a non-nominee island inside the ground-storey volume V goes to the
   Unclassified node and FAILS the build unless UNCLASSIFIED_ALLOWED lists it with a
   reason (the list is empty); non-nominee islands inside the envelope that
   cannot see out are listed as hidden leftovers.
5. Nodes: Facade_<N|S|W|E>_<bay> for the ground storey (bays between pilaster
   centrelines; long facade quads are cut at the seams, small islands go whole to
   the west/north bay), Upper, Porch_1..8 (the door porches), Lot, Poles,
   Door_1..8, Road, Lights (an empty) with Lights_<side>_<bay> for the ground
   storey panels and Lights_Upper, and Unclassified if any.
6. Closures per bay: an inward face 0.25 m inside the backdrop (y 0.3-5.49), a
   top cap at 5.49, end reveals at both bay ends, and ledge end caps at both bay
   ends, all inset 0.03 m from their seam so neighbours never share a plane; plus
   a top cap on every mullion stub cut at y 5.5. Source custom normals are kept;
   closure faces are checked to carry their face normal. The closures seen from inside
   (inward face, top cap, end reveals, doorway wall jambs and lintel) take the interior
   kit's light wall swatch (WALL_SWATCH), not the dark teal backdrop's; the ledge end caps
   and stub caps, seen from outside, keep the swatch of the surface they close.
   Crack caps (step 3): above the ground storey each storey's backdrop starts a few cm
   above the slab top it stands on, so a thin slit runs along the storey line that showed
   the slab top in the original. Of every deleted up-facing slab top that ends on a
   backdrop or setback plane, a CRACK_BAND (0.5 m) strip along that plane is kept: the same
   surface the slit showed, nothing deeper.
   Canopy (step 5): whole source islands move from Upper (or Lot) to the Canopy node:
   islands from the canopy's back fascia plane (z -71.00) outward that reach past z -63.0,
   the back-fascia islands that mirror one of them, and every pole cable.
   Doorways (after step 6): each vestibule (Porch_<n>) is closed at its back by a panel
   that faces out and is culled from inside. At each revolving door that panel is removed
   and an opening of the panel's width (2.30 m, the vestibule's clear width; the drum is
   2.21 m) is cut through the door's facade bay from the floor to OPEN_TOP (3.80, the upper
   ledge top and the porch ceiling). A wall jamb (inward face to backdrop, in the bay), a
   vestibule jamb (backdrop to the old panel, in the porch, covering the cut ledge and
   window ends) on each side and a lintel up to the porch ceiling's inner edge close it;
   81 rays through it must pass, and 2 beside it must first hit the bay's own inward face
   (its node, within 2 mm of its plane). A Doorway_<n> empty marks the floor centre of each opening on the backdrop
   plane, its local -Z pointing outward, with glTF extras door, bay, outward, width, height.
7. Write the .glb.import first (the source's [params]: toon_post_import.gd and
   embedded_image_handling=0, so Godot binds the shared atlases and extracts no
   PNGs), export (same glTF settings as convert_toon_batch.py), and RE-READ THE
   WRITTEN FILE: every node's name, parent and triangle count must match the
   scene; materials, the material-to-image binding and AABBs are reported.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_01a.glb")
OUT_DEFAULT = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_shell.glb")
REPORT_DIR = os.path.join(REPO, "tools", "blender", "out", "toon_shell_extract")

OFFSET_Z = -80.0
BX0, BX1 = -33.94, 32.94  # west / east backdrop planes
BZ0, BZ1 = -95.25, -64.35  # airside / landside backdrop planes
SETBACK_Z = -70.35  # east setback backdrop above the ground storey
GROUND_Y, TOP_Y = 0.3, 5.5  # ground storey floor top and ceiling line
LOT_MAX_Y = 0.31
INNER = 0.25  # inward face offset from the backdrop
INSET = 0.03  # every closure stays this far inside its own bay
LEDGES = ((1.0, 1.3), (3.5, 3.8))  # ground-storey ledge bands (slab rims)
SLAB_OUT = {"N": -95.5, "S": -64.1, "W": -34.2, "E": 33.2}  # ledge outer faces
LONG_SEAMS = [-30.5 + 3.0 * k for k in range(21)]  # pilaster centrelines, N and S
SHORT_SEAMS = [-92.3 + 2.5 * k for k in range(11)]  # pilaster centrelines, W and E
SEAM_SNAP = 0.2  # a small piece this close to a seam goes to the west/north bay
EPS = 1e-3
DOOR_CLEAR = 0.10  # doorway clearance on each side of the revolving door's drum
OPEN_TOP = 3.80  # doorway top: the upper ledge band's top and the porch ceiling
CRACK_BAND = 0.5  # crack caps: kept width of a deleted slab top along the backdrop
CANOPY_BACK_Z = -71.05  # the sloped landside canopy starts at its back fascia (z -71.00)
CANOPY_REACH_Z = -63.0  # and reaches out past the landside facade (ledge rims stop at -64.1)
CONTROL_TOL = 0.002  # doorway control rays: first hit within 2 mm of the inward face plane
# Inside wall colour: the interior kit's "wall" palette entry (PALETTE["wall"] in
# tools/blender/interior/build_interior_kit.py): TP_Atlas_1A_D column 22, row 0, from 0.12
# below the swatch top, spanning 0.22 of it; v follows height, the top of the wall lightest.
# The backdrop's swatch (column 0, row 4) is dark teal and read near-black from inside.
WALL_SWATCH = (22, 0, 0.12, 0.22)  # column, row, fraction from the swatch top, span
ATLAS_GRID = (32, 16)  # TP_Atlas_1A_D swatch columns and rows
WALL_MIN_LUMA = 0.6  # the build fails if the inside wall swatch samples darker than this
# Unclassified islands (non-nominee islands crossing the ground-storey volume V, or facade
# faces with no side) fail the build unless listed here: {source island index: reason}.
# Island indices come from islands_of() over the unmodified source .glb, so they are stable
# while that file is unchanged. Empty: the build area holds no unexplained geometry.
UNCLASSIFIED_ALLOWED = {}

sys.dont_write_bytecode = True


def log(*a):
    print("SHELL", *a, flush=True)


def die(msg):
    print("SHELL_FAIL", msg, flush=True)
    sys.exit(1)


def g(v):
    """Blender world -> Godot world."""
    return Vector((v.x, v.z, -v.y + OFFSET_Z))


def b(x, y, z):
    """Godot world -> Blender world."""
    return Vector((x, -(z - OFFSET_Z), y))


def plane(axis, c):
    """(plane_co, plane_no) in Blender space for a Godot-axis plane."""
    if axis == "x":
        return Vector((c, 0, 0)), Vector((1, 0, 0))
    if axis == "y":
        return Vector((0, 0, c)), Vector((0, 0, 1))
    return Vector((0, -(c - OFFSET_Z), 0)), Vector((0, 1, 0))


def args():
    a = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out = OUT_DEFAULT
    if "--out" in a:
        if a.index("--out") + 1 >= len(a):
            die("--out needs a path")
        out = a[a.index("--out") + 1]
    return checked_out_path(out)


def checked_out_path(raw):
    """The output path, resolved and bound to the repo. A relative path is taken from REPO,
    not from the working directory. Refused: no .glb suffix, a path that leaves the repo,
    a path through a symlink or junction (its real path differs from its spelled path), the
    repo root itself, and the source .glb under any spelling."""
    path = raw if os.path.isabs(raw) else os.path.join(REPO, raw)
    path = os.path.abspath(path)
    real = os.path.realpath(path)
    repo_real = os.path.realpath(REPO)
    if not path.lower().endswith(".glb"):
        die("refusing --out %r: the output must end in .glb" % raw)
    try:
        inside = os.path.commonpath([os.path.normcase(repo_real), os.path.normcase(real)]) == os.path.normcase(repo_real)
    except ValueError:  # different drives
        inside = False
    if not inside or os.path.normcase(real) == os.path.normcase(repo_real):
        die("refusing --out %r: it resolves to %s, outside the repo %s" % (raw, real, repo_real))
    if os.path.islink(path) or os.path.normcase(real) != os.path.normcase(path):
        die("refusing --out %r: the path goes through a symlink or junction (%s is really %s)" % (raw, path, real))
    if os.path.normcase(real) == os.path.normcase(os.path.realpath(SRC)) or (
            os.path.exists(path) and os.path.samefile(path, SRC)):
        die("refusing --out %r: it is the source .glb %s" % (raw, SRC))
    log("OUT %s (from --out %r)" % (path, raw))
    return path


# ------------------------------------------------------------------ source


def load_source():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    bpy.context.view_layer.update()
    objs = {o.name: o for o in bpy.context.scene.objects}
    need = ["TP_Airport_01A", "TP_Airport_01A_Lights", "TP_Airport_01A_Road"]
    need += ["TP_Airport_01A_Door_%d" % i for i in range(1, 9)]
    for n in need:
        if n not in objs:
            die("source node missing: %s" % n)
    mats = sorted(m.name for m in bpy.data.materials)
    imgs = sorted(i.name for i in bpy.data.images)
    log("SOURCE objects=%d materials=%s images=%s" % (len(objs), mats, imgs))
    if len(imgs) != 3 or len(mats) != 4:
        die("source atlas binding is not 4 materials / 3 images")
    return objs


def islands_of(bm):
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, comp = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for v in cur.verts:
                for nf in v.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        out.append(comp)
    return out


def bbox(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def describe(faces):
    pts = [g(v.co) for f in faces for v in f.verts]
    lo, hi = bbox(pts)
    ns = [Vector((f.normal.x, f.normal.z, -f.normal.y)) for f in faces]
    planar = all(n.dot(ns[0]) > 0.999 for n in ns)
    n = ns[0] if planar else None
    return {
        "lo": lo,
        "hi": hi,
        "c": (lo + hi) / 2,
        "area": sum(f.calc_area() for f in faces),
        "n": n,
        "faces": len(faces),
    }


def fmt_box(d):
    return "x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
        d["lo"].x, d["hi"].x, d["lo"].y, d["hi"].y, d["lo"].z, d["hi"].z)


# ------------------------------------------------------------------ nominate


def vertical_axis(d):
    n = d["n"]
    if n is None or abs(n.y) > 0.01:
        return None
    if abs(n.x) > 0.999:
        return "x"
    if abs(n.z) > 0.999:
        return "z"
    return None


def nominate_filler(info):
    """Twin test. Returns {island index: family} for vertical walls with a twin."""
    vert = []
    for i, d in enumerate(info):
        ax = vertical_axis(d)
        if ax is None:
            continue
        along = (d["lo"].z, d["hi"].z) if ax == "x" else (d["lo"].x, d["hi"].x)
        if along[1] - along[0] < 20.0:
            continue
        pos = d["c"].x if ax == "x" else d["c"].z
        sign = 1 if (d["n"].x if ax == "x" else d["n"].z) > 0 else -1
        vert.append((i, ax, pos, sign, along, (d["lo"].y, d["hi"].y)))

    def overlap(a, c):
        inter = min(a[1], c[1]) - max(a[0], c[0])
        return inter / max(1e-6, max(a[1] - a[0], c[1] - c[0]))

    found = {}
    partner = {}
    for k, (i, ax, pos, sign, along, ys) in enumerate(vert):
        for j, ax2, pos2, sign2, along2, ys2 in vert:
            if j == i or ax2 != ax or sign2 == sign:
                continue
            gap = abs(pos2 - pos)
            if not 0.08 <= gap <= 0.40:
                continue
            if overlap(along, along2) < 0.9 or overlap(ys, ys2) < 0.9:
                continue
            fam = "lattice" if gap > 0.30 else ("signbox" if gap > 0.15 else "mullionwall")
            found[i] = fam
            partner[i] = j
            break
    # A long narrow horizontal cap is filler only when it closes a found twin pair:
    # its narrow edges sit on the two walls' planes and it runs along them.
    walls = {i: (ax, pos, along, ys) for i, ax, pos, sign, along, ys in vert if i in found}
    for i, d in enumerate(info):
        n = d["n"]
        if n is None or abs(n.y) < 0.999 or i in found:
            continue
        sx, sz = d["hi"].x - d["lo"].x, d["hi"].z - d["lo"].z
        if max(sx, sz) < 20.0 or min(sx, sz) > 0.40:
            continue
        ax = "x" if sx < sz else "z"
        n0, n1 = (d["lo"].x, d["hi"].x) if ax == "x" else (d["lo"].z, d["hi"].z)
        along = (d["lo"].z, d["hi"].z) if ax == "x" else (d["lo"].x, d["hi"].x)
        # the two edge walls must be one twin pair, and the cap must sit at its top or bottom
        y = d["c"].y
        ok = False
        for wi, (wax, wpos, walong, wys) in walls.items():
            wj = partner.get(wi)
            if wj not in walls or wax != ax or abs(wpos - n0) >= 0.02 or abs(walls[wj][1] - n1) >= 0.02:
                continue
            if overlap(walong, along) < 0.9 or overlap(walls[wj][2], along) < 0.9:
                continue
            if min(abs(y - wys[0]), abs(y - wys[1])) < 0.02:
                ok = True
                break
        if ok:
            found[i] = "boxcap"
    return found


def nominate_slabs(info):
    out = []
    for i, d in enumerate(info):
        n = d["n"]
        if n is not None and abs(n.y) > 0.999 and d["area"] >= 100.0:
            out.append(i)
    return out


def face_samples(f, spacing=1.0, cap=80):
    """Deterministic points spread over a polygon (fan triangles, stratified)."""
    vs = [v.co for v in f.verts]
    c = f.calc_center_median()
    pts = [c]
    for v in vs:
        pts.append(v.lerp(c, 0.08))
    area = f.calc_area()
    n = min(cap, max(4, int(area / (spacing * spacing))))
    tris = [(vs[0], vs[k], vs[k + 1]) for k in range(1, len(vs) - 1)]
    tri_areas = [((t[1] - t[0]).cross(t[2] - t[0])).length / 2 for t in tris]
    tot = sum(tri_areas) or 1.0
    for t, ta in zip(tris, tri_areas):
        m = max(1, int(round(n * ta / tot)))
        side = max(1, int(math.ceil(math.sqrt(2 * m))))
        for a in range(side):
            for bb in range(side - a):
                u = (a + 0.5) / (side + 0.5)
                w = (bb + 0.5) / (side + 0.5)
                if u + w >= 1.0:
                    continue
                pts.append(t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * w)
    return pts


DIRS = [Vector((x, y, z)).normalized() for x in (-1, 0, 1) for y in (-1, 0, 1) for z in (-1, 0, 1)
        if (x, y, z) != (0, 0, 0)]


def box_exit(o, d):
    """Where a ray from o along d leaves the building box (Godot coords)."""
    lo = Vector((-34.2, 0.0, -95.5))
    hi = Vector((33.2, 21.0, -64.1))
    t = 1e9
    for k in range(3):
        if abs(d[k]) > 1e-9:
            t = min(t, ((hi[k] if d[k] > 0 else lo[k]) - o[k]) / d[k])
    return o + d * max(0.0, t)


def sees_out(bvh, f, reach=600.0):
    """(visible samples, total samples) on the front side of face f."""
    n = f.normal
    dirs = [d for d in DIRS if d.dot(n) > 0.1]
    vis = 0
    esc = None
    pts = face_samples(f)
    for p in pts:
        o = p + n * 0.02
        for d in dirs:
            if bvh.ray_cast(o, d, reach)[0] is None:
                vis += 1
                if esc is None:
                    esc = (g(o), Vector((d.x, d.z, -d.y)))
                    esc = esc + (box_exit(esc[0], esc[1]),)
                break
    return vis, len(pts), esc


AXES = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]


def ortho_exposed(bvh, f):
    """The first axis direction (Blender space) along which a sample on the front side of
    face f escapes in bvh, or None. With the ORIGINAL scene as bvh this answers whether the
    face shows in one of the six orthographic views of the original. Unlike sees_out it
    also takes grazing directions (any d with d . n > 0), which is how a nearly horizontal
    soffit shows edge-on from the side."""
    n = f.normal
    dirs = [d for d in AXES if d.dot(n) > 1e-4]
    if not dirs:
        return None
    for p in face_samples(f):
        o = p + n * 0.02
        for d in dirs:
            if bvh.ray_cast(o, d, 600.0)[0] is None:
                return d
    return None


def covered_from_above(bvh, f):
    hits = 0
    pts = face_samples(f, spacing=2.0, cap=60)
    for p in pts:
        if bvh.ray_cast(p + Vector((0, 0, 0.02)), Vector((0, 0, 1)), 600.0)[0] is not None:
            hits += 1
    return hits, len(pts)


# ------------------------------------------------------------------ geometry ops


def bisect_faces(bm, faces, axis, c):
    """Cut the given faces at a Godot-axis plane. Returns how many faces it cut."""
    co, no = plane(axis, c)
    hit = []
    for f in faces:
        if not f.is_valid:
            continue
        ds = [(v.co - co).dot(no) for v in f.verts]
        if min(ds) < -EPS and max(ds) > EPS:
            hit.append(f)
    if not hit:
        return 0
    # Traversal order (dict keeps first-seen order), never a set: a set of BMesh elements
    # orders by object address, which changes run to run and so would the cut result.
    edges = list(dict.fromkeys(e for f in hit for e in f.edges))
    verts = list(dict.fromkeys(v for f in hit for v in f.verts))
    bmesh.ops.bisect_plane(bm, geom=hit + edges + verts, dist=1e-5, plane_co=co, plane_no=no)
    return len(hit)


def in_v(p, m=0.0):
    return (BX0 + m < p.x < BX1 - m and BZ0 + m < p.z < BZ1 - m and GROUND_Y + m < p.y < TOP_Y - m)


def inside_envelope(p):
    """Strictly inside the backdrop planes (the landside line is z -64.35 at every height)."""
    return BX0 + 0.05 < p.x < BX1 - 0.05 and BZ0 + 0.05 < p.z < BZ1 - 0.05 and p.y > GROUND_Y + 0.05


def in_facade_zone(p):
    return -34.45 <= p.x <= 33.45 and -95.75 <= p.z <= -63.85


def side_of(c):
    if c.z >= BZ1 - 0.02:
        return "S"
    if c.z <= BZ0 + 0.02:
        return "N"
    if c.x <= BX0 + 0.02:
        return "W"
    if c.x >= BX1 - 0.02:
        return "E"
    return None


def bay_of(side, c, small):
    seams, key = (LONG_SEAMS, c.x) if side in ("N", "S") else (SHORT_SEAMS, c.z)
    if small:
        for s in seams:
            if abs(key - s) <= SEAM_SNAP:
                key = s - 0.3
                break
    return 1 + sum(1 for s in seams if s < key)


def bay_span(side, bay):
    """Bay extent along its wall (Godot x for N/S, z for W/E), end bays to the backdrop."""
    seams, lo0, hi0 = (LONG_SEAMS, BX0, BX1) if side in ("N", "S") else (SHORT_SEAMS, BZ0, BZ1)
    edges = [lo0] + seams + [hi0]
    return edges[bay - 1], edges[bay]


# ------------------------------------------------------------------ doorways


def wall_uv(y):
    """Atlas UV of the inside wall colour at height y (Godot): WALL_SWATCH's span, top to bottom."""
    col, row, frac, span = WALL_SWATCH
    t = min(1.0, max(0.0, (TOP_Y - y) / (TOP_Y - GROUND_Y)))
    return Vector(((col + 0.5) / ATLAS_GRID[0], 1.0 - (row + frac + span * t) / ATLAS_GRID[1]))


def wall_uvs(corners_g):
    return [wall_uv(p[1]) for p in corners_g]


def gnormal(f):
    return Vector((f.normal.x, f.normal.z, -f.normal.y))


def gbox(f):
    return bbox([g(v.co) for v in f.verts])


def cut_doorways(bm, doors, drum, node_l, uvl, add_quad):
    """Cut an opening through the facade bay at each revolving door, close its jambs and
    lintel, and prove it is open. The opening is as wide as the vestibule's back panel (its
    clear width, which must hold the drum with at most DOOR_CLEAR to spare on each side),
    from the floor (y 0.3) to OPEN_TOP, from the inward face through the wall, and the back
    panel is removed. Returns one record per door for the markers and census."""
    rows = []
    for k in sorted(doors):
        c = doors[k]
        side = "N" if c.z < -80.0 else "S"
        bd = BZ0 if side == "N" else BZ1
        inw = 1.0 if side == "N" else -1.0  # inward is +z on the airside wall, -z landside
        inner = bd + INNER * inw
        outer = SLAB_OUT[side]
        zlo, zhi = min(inner, outer), max(inner, outer)
        # The vestibule (Porch_<n>) is closed at its back by a single-sided panel facing out
        # (culled from inside). The opening takes that panel's width, the vestibule's clear
        # width between its side walls, and the panel goes.
        pkey = ("Porch_%d" % k).encode()
        panel = [f for f in bm.faces if f[node_l] == pkey and abs(gnormal(f).z + inw) < 1e-3
                 and gbox(f)[0].x < c.x < gbox(f)[1].x and gbox(f)[1].y - gbox(f)[0].y > 3.0]
        if not panel:
            die("doorway %d: no vestibule back panel in Porch_%d" % (k, k))
        plo, phi = bbox([p for f in panel for p in gbox(f)])
        x0, x1, pz = plo.x, phi.x, plo.z
        hw = (x1 - x0) / 2
        if abs((x0 + x1) / 2 - c.x) > 0.02:
            die("doorway %d: back panel centre %.3f is off the drum centre %.3f" % (k, (x0 + x1) / 2, c.x))
        if phi.z - plo.z > 1e-3 or x1 - x0 < 2 * drum[k] or x1 - x0 > 2 * (drum[k] + DOOR_CLEAR):
            die("doorway %d: back panel x %.2f..%.2f z %.2f..%.2f against drum %.3f" % (k, x0, x1, plo.z, phi.z, drum[k]))
        wall_uv = {}
        for jx, dirx in ((x0, 1), (x1, -1)):
            side_faces = [f for f in bm.faces if f[node_l] == pkey and abs(gnormal(f).x - dirx) < 1e-3
                          and abs(gbox(f)[0].x - jx) < 1e-3 and abs(gbox(f)[1].x - jx) < 1e-3]
            if not side_faces:
                die("doorway %d: no vestibule side wall at x %.2f" % (k, jx))
            us = [lp[uvl].uv for lp in side_faces[0].loops]
            wall_uv[jx] = Vector((sum(u.x for u in us) / len(us), sum(u.y for u in us) / len(us)))
        floor_y = plo.y
        bay = bay_of(side, c, False)
        node = "Facade_%s_%02d" % (side, bay)
        a, e = bay_span(side, bay)
        if not (a + 0.23 < x0 and x1 < e - 0.23):  # pilasters reach 0.18 m from the seam
            die("doorway %d (x %.2f..%.2f) does not clear the pilasters of %s (%.2f..%.2f)" % (k, x0, x1, node, a, e))
        key = node.encode()

        def bay_faces():
            return [f for f in bm.faces if f[node_l] == key]

        cuts = 0
        for xc in (x0, x1):
            cuts += bisect_faces(bm, [f for f in bay_faces() if gbox(f)[0].y < OPEN_TOP + EPS], "x", xc)
        column = [f for f in bay_faces() if x0 - 1e-4 <= gbox(f)[0].x and gbox(f)[1].x <= x1 + 1e-4]
        cuts += bisect_faces(bm, column, "y", OPEN_TOP)

        def in_box(p):
            return x0 < p.x < x1 and GROUND_Y + 1e-3 < p.y <= OPEN_TOP + 1e-3 and zlo - 1e-3 <= p.z <= zhi + 1e-3

        cand = [f for f in bay_faces() if in_box(g(f.calc_center_median()))]
        for f in cand:
            lo, hi = gbox(f)
            if lo.x < x0 - 1e-4 or hi.x > x1 + 1e-4 or lo.y < GROUND_Y - 1e-4 or hi.y > OPEN_TOP + 1e-4 \
                    or lo.z < zlo - 1e-3 or hi.z > zhi + 1e-3:
                die("doorway %d: face straddles the opening box: %s" % (k, fmt_box(describe([f]))))
        # the porch ceiling must cover the opening's width up to its inner edge
        ceil = [f for f in bm.faces if f[node_l] == ("Porch_%d" % k).encode() and gnormal(f).y < -0.999
                and abs(g(f.calc_center_median()).y - OPEN_TOP) < 2e-3]
        if not ceil:
            die("doorway %d: no porch ceiling at y %.2f" % (k, OPEN_TOP))
        clo, chi = bbox([p for f in ceil for p in bbox([g(v.co) for v in f.verts])])
        edge = chi.z if side == "N" else clo.z
        if clo.x > x0 or chi.x < x1 or not ((edge - bd) * inw > 0 and (inner - edge) * inw > 0):
            die("doorway %d: porch ceiling x %.2f..%.2f edge %.2f does not cover the opening" % (k, clo.x, chi.x, edge))
        bmesh.ops.delete(bm, geom=cand + panel, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

        quads = 0
        for jx, dirx in ((x0, 1), (x1, -1)):
            # wall jamb (inward face to backdrop) in the bay; vestibule jamb (backdrop to the
            # old back panel) continues the vestibule's side wall in the porch. It covers the
            # cut ends of the ledge bands and the window plane, so they get no caps of their own.
            jamb = [(jx, GROUND_Y, inner), (jx, GROUND_Y, bd), (jx, OPEN_TOP, bd), (jx, OPEN_TOP, inner)]
            add_quad(node, jamb, wall_uvs(jamb), (dirx, 0, 0))
            add_quad("Porch_%d" % k, [(jx, floor_y, bd), (jx, floor_y, pz), (jx, OPEN_TOP, pz), (jx, OPEN_TOP, bd)],
                     [wall_uv[jx]] * 4, (dirx, 0, 0))
            quads += 2
        lintel = [(x0, OPEN_TOP, inner), (x1, OPEN_TOP, inner), (x1, OPEN_TOP, edge), (x0, OPEN_TOP, edge)]
        add_quad(node, lintel, wall_uvs(lintel), (0, -1, 0))
        quads += 1

        # proof: rays through the opening from 0.3 m inside to 0.1 m past the ledge front
        # hit nothing; control rays just beside the opening hit the inward face
        bm.normal_update()
        bm.faces.index_update()
        bvh = BVHTree.FromBMesh(bm)
        ray = b(0, 0, -inw) - b(0, 0, 0)
        reach = 0.3 + abs(pz - inner) + 0.1
        clear = blocked = 0
        for i in range(9):
            for j in range(9):
                x = x0 + 0.03 + (x1 - x0 - 0.06) * i / 8
                y = GROUND_Y + 0.05 + (OPEN_TOP - GROUND_Y - 0.1) * j / 8
                hit = bvh.ray_cast(b(x, y, inner + 0.3 * inw), ray, reach)
                if hit[0] is None:
                    clear += 1
                else:
                    blocked += 1
        # Each control ray's FIRST hit must be a face of this bay's node lying on the inward
        # face plane (z = inner, within CONTROL_TOL), 0.3 m from the ray's start.
        bm.faces.ensure_lookup_table()
        control = 0
        control_rows = []
        for x in (x0 - 0.06, x1 + 0.06):
            loc, _nrm, fi, dist = bvh.ray_cast(b(x, 2.0, inner + 0.3 * inw), ray, reach)
            if loc is None:
                die("doorway %d: control ray at x %.3f hits nothing" % (k, x))
            hit_node = bm.faces[fi][node_l].decode()
            hit_z = g(loc).z
            control_rows.append((x, hit_node, hit_z, dist))
            if hit_node != node or abs(hit_z - inner) > CONTROL_TOL:
                die("doorway %d: control ray at x %.3f first hits %s at z %.4f (want %s at z %.4f +- %.3f)"
                    % (k, x, hit_node, hit_z, node, inner, CONTROL_TOL))
            control += 1
        if blocked or control != 2:
            die("doorway %d: %d of 81 rays through the opening are blocked, %d of 2 control rays hit" % (k, blocked, control))
        rows.append({"k": k, "side": side, "node": node, "c": c.copy(), "hw": hw, "bd": bd, "inner": inner,
                     "outer": pz, "edge": edge, "cuts": cuts, "deleted": len(cand), "panel": len(panel),
                     "quads": quads, "clear": clear, "control": control, "control_rows": control_rows,
                     "outward": (0.0, 0.0, -inw)})
    return rows


# ------------------------------------------------------------------ main


def main():
    out_path = args()  # resolved, inside the repo, a .glb, never the source (checked_out_path)
    os.makedirs(REPORT_DIR, exist_ok=True)
    report = []

    def rep(line=""):
        report.append(line)

    objs = load_source()
    main_ob = objs["TP_Airport_01A"]
    uv_name = main_ob.data.uv_layers.active.name
    mat_main = main_ob.material_slots[0].material
    bm = bmesh.new()
    bm.from_mesh(main_ob.data)
    bm.transform(main_ob.matrix_world)
    bm.normal_update()
    uvl = bm.loops.layers.uv[uv_name]
    src_l = bm.faces.layers.int.new("src")
    del_l = bm.faces.layers.int.new("del")  # layers are made up front: a new layer
    frag_l = bm.faces.layers.int.new("frag")  # invalidates held BMFace references
    isl = islands_of(bm)
    info = [describe(fs) for fs in isl]
    for i, fs in enumerate(isl):
        for f in fs:
            f[src_l] = i
    log("ISLANDS main=%d faces=%d" % (len(isl), len(bm.faces)))

    # Occluders that are never edited: doors, Lights, Road (world space).
    other_tris = []
    for n, o in objs.items():
        if o.type == "MESH" and o is not main_ob:
            mw = o.matrix_world
            vs = [mw @ v.co for v in o.data.vertices]
            other_tris.append((vs, [list(p.vertices) for p in o.data.polygons]))

    def bvh_with(keep_face):
        verts, polys = [], []
        for vs, ps in other_tris:
            base = len(verts)
            verts += vs
            polys += [[base + k for k in p] for p in ps]
        vidx = {}
        for f in bm.faces:
            if not keep_face(f):
                continue
            poly = []
            for v in f.verts:
                if v.index not in vidx:
                    vidx[v.index] = len(verts)
                    verts.append(v.co.copy())
                poly.append(vidx[v.index])
            polys.append(poly)
        return BVHTree.FromPolygons(verts, polys)

    bm.verts.index_update()
    full_bvh = bvh_with(lambda f: True)

    # ---- 1. classify islands (source)
    filler = nominate_filler(info)
    slabs = nominate_slabs(info)
    roof, inner_slab, mixed_cap = [], [], []
    for i in slabs:
        if info[i]["hi"].y <= LOT_MAX_Y:
            continue  # ground-level caps are Lot, never slab nominees
        if info[i]["n"].y < 0:
            inner_slab.append(i)
            continue
        hits = tot = 0
        for f in isl[i]:
            h, t = covered_from_above(full_bvh, f)
            hits += h
            tot += t
        if hits == tot:
            inner_slab.append(i)
        elif hits == 0:
            roof.append(i)
        else:
            mixed_cap.append((i, hits, tot))
            roof.append(i)
    inner_slab = [i for i in inner_slab if info[i]["hi"].y > LOT_MAX_Y]  # the ground slab is Lot

    doors = {}
    drum = {}
    for k in range(1, 9):
        o = objs["TP_Airport_01A_Door_%d" % k]
        pts = [g(o.matrix_world @ v.co) for v in o.data.vertices]
        lo, hi = bbox(pts)
        doors[k] = (lo + hi) / 2
        drum[k] = max(math.hypot(p.x - doors[k].x, p.z - doors[k].z) for p in pts)

    def porch_of(d):
        for k, c in doors.items():
            if not (c.x - 2.3 <= d["lo"].x and d["hi"].x <= c.x + 2.3):
                continue
            if d["lo"].y < 0.05 or d["hi"].y > 5.0:
                continue
            if c.z > -80:  # landside
                if d["lo"].z >= -64.45 and d["hi"].z > -64.15 and d["hi"].z <= -60.3:
                    return k
            else:
                if d["hi"].z <= -95.0 and d["lo"].z < -95.45 and d["lo"].z >= -99.2:
                    return k
        return None

    matches = {}
    cls = {}
    for i, d in enumerate(info):
        m = []
        if d["hi"].y <= LOT_MAX_Y:
            m.append("lot")
        if i in filler:
            m.append("filler:" + filler[i])
        if i in inner_slab:
            m.append("slab:inner")
        if i in roof:
            m.append("slab:roof")
        p = porch_of(d)
        if p is not None:
            m.append("porch:%d" % p)
        if d["c"].z > -60.0 and d["hi"].y > LOT_MAX_Y:
            if d["hi"].z - d["lo"].z > 4.0 and d["hi"].y > TOP_Y:
                m.append("cable")
            else:
                m.append("poles")
        if in_facade_zone(d["c"]) and d["lo"].y < TOP_Y - EPS:
            m.append("facade")
        if d["lo"].y >= TOP_Y - EPS or "cable" in m:
            m.append("upper")
        matches[i] = m
        cls[i] = m[0] if m else "other"
        if cls[i] == "cable":
            cls[i] = "upper:cable"
    multi = {i: m for i, m in matches.items() if len(m) > 1}
    nominee = {i for i in range(len(info)) if cls[i].startswith("filler") or cls[i] == "slab:inner"}
    area_before = {}
    for f in bm.faces:
        area_before[f[src_l]] = area_before.get(f[src_l], 0.0) + f.calc_area()

    # Ledge swatches, read before any cut invalidates the source faces.
    ledge_uv = {}
    for i, d in enumerate(info):
        if d["n"] is None or d["faces"] > 2 or abs(d["n"].y) > 0.01:
            continue
        for lo, hi in LEDGES:
            if abs(d["lo"].y - lo) < 0.01 and abs(d["hi"].y - hi) < 0.01 and d["area"] > 5:
                s = side_of(d["c"])
                if s and (s, lo) not in ledge_uv:
                    us = [lp[uvl].uv for lp in isl[i][0].loops]
                    ledge_uv[(s, lo)] = (sum(u.x for u in us) / len(us), sum(u.y for u in us) / len(us))

    # ---- 2. crossings
    cut_log = []
    for axis, c, label in (("x", BX0, "backdrop W x -33.94"), ("x", BX1, "backdrop E x 32.94"),
                           ("z", BZ0, "backdrop N z -95.25"), ("z", BZ1, "backdrop S z -64.35"),
                           ("z", SETBACK_Z, "setback z -70.35"), ("y", TOP_Y, "ground top y 5.5")):
        faces = [f for f in bm.faces if f[src_l] in nominee]
        n = bisect_faces(bm, faces, axis, c)
        cut_log.append(("nominee", label, n))
    y55 = []
    stub_caps = []
    for i, d in enumerate(info):
        if i in nominee or cls[i] != "facade" or d["n"] is None:
            continue
        if not (d["lo"].y < TOP_Y - EPS < TOP_Y + EPS < d["hi"].y):
            continue
        us = [lp[uvl].uv for f in isl[i] for lp in f.loops]
        stub_caps.append((i, d["c"].copy(), d["lo"].copy(), d["hi"].copy(),
                          Vector((sum(u.x for u in us) / len(us), sum(u.y for u in us) / len(us)))))
    facade_cross = [f for f in bm.faces if f[src_l] not in nominee and cls[f[src_l]] in ("facade",)
                    and info[f[src_l]]["lo"].y < TOP_Y - EPS < TOP_Y + EPS < info[f[src_l]]["hi"].y]
    y55_src = sorted({f[src_l] for f in facade_cross})
    n = bisect_faces(bm, facade_cross, "y", TOP_Y)
    cut_log.append(("facade non-nominee", "ground top y 5.5", n))
    y55 = y55_src
    cross_uncut = [i for i, d in enumerate(info) if i not in nominee and i not in y55_src
                   and d["lo"].y < TOP_Y - EPS and d["hi"].y > TOP_Y + EPS]
    area_after = {}
    for f in bm.faces:
        area_after[f[src_l]] = area_after.get(f[src_l], 0.0) + f.calc_area()
    drift = [i for i in area_before if abs(area_before[i] - area_after.get(i, 0.0)) > 1e-3]
    if drift or set(area_after) - set(area_before):
        die("cuts changed per-island area (face attributes not carried): %s" % drift[:10])
    bm.normal_update()
    bm.verts.index_update()
    bm.faces.index_update()

    # ---- 3. visibility against the envelope
    # Pass 1: the envelope is every non-nominee face plus the nominee fragments that lie
    # outside a backdrop plane (stubs and ledge rims are exterior by position).
    # Pass 2 adds the fragments pass 1 found clearly exterior (half or more of their
    # samples see out, such as the setback rims) and re-tests only the doubtful ones.
    def exterior(f):
        c = g(f.calc_center_median())
        return c.x <= BX0 + 1e-4 or c.x >= BX1 - 1e-4 or c.z <= BZ0 + 1e-4 or c.z >= BZ1 - 1e-4

    nom_faces = [f for f in bm.faces if f[src_l] in nominee]
    ext = {f for f in nom_faces if exterior(f)}
    test = [f for f in nom_faces if f not in ext]
    env1 = bvh_with(lambda f: f[src_l] not in nominee or f in ext)
    res = {f: sees_out(env1, f) for f in test}
    sure = {f for f, r in res.items() if r[0] * 2 >= r[1] and r[0] > 0}
    doubt = [f for f, r in res.items() if 0 < r[0] and f not in sure]
    env2 = bvh_with(lambda f: f[src_l] not in nominee or f in ext or f in sure)
    for f in doubt:
        res[f] = sees_out(env2, f)
    delete, kept_vis, partial = [], len(ext), []
    interior_partial, interior_visible = [], []
    crack_deleted = []
    kept_exposed = []
    for f in test:
        vis, tot, esc = res[f]
        cen = g(f.calc_center_median())
        # Exterior exposure: a fragment outside V that shows in one of the six orthographic
        # views of the ORIGINAL (a sample's axis ray escapes the original scene) is part of
        # the outside and is kept, whatever the tolerance or the 26-direction test says.
        if not in_v(cen, 0.02):
            d = ortho_exposed(full_bvh, f)
            if d is not None:
                kept_exposed.append((f[src_l], fmt_box(describe([f])), f.calc_area(), vis, tot,
                                     Vector((d.x, d.z, -d.y))))
                kept_vis += 1
                continue
        # Crack tolerance: an inside fragment that sees out through 10 percent or less of
        # its samples sees through a thin gap between storey bands, not a real face of the
        # envelope; it goes, and the gap is listed. Everything nominated inside V goes.
        on_setback = cen.y > TOP_Y and SETBACK_Z <= cen.z <= SETBACK_Z + 0.3  # setback rims and stubs
        if vis and (in_v(cen, 0.02) or (inside_envelope(cen) and not on_setback and vis <= 0.10 * tot)):
            crack_deleted.append((f[src_l], fmt_box(describe([f])), vis, tot, esc,
                                  "inside V" if in_v(cen, 0.02) else "tolerance"))
            delete.append(f)
            continue
        if vis == 0:
            delete.append(f)
        elif vis == tot:
            kept_vis += 1
            if inside_envelope(g(f.calc_center_median())):
                interior_visible.append((f[src_l], fmt_box(describe([f])), vis, tot, esc))
        else:
            partial.append((f, vis, tot))
            if inside_envelope(g(f.calc_center_median())):
                interior_partial.append((f[src_l], fmt_box(describe([f])), vis, tot, esc))
    vis_passes = (len(ext), len(test), len(sure), len(doubt))
    nominee_faces = len(delete) + kept_vis + len(partial)
    del_area = sum(f.calc_area() for f in delete)
    deleted_by_src = {}
    for f in delete:
        deleted_by_src[f[src_l]] = deleted_by_src.get(f[src_l], 0) + 1
    in_v_kept = []
    for f, vis, tot in partial:
        if in_v(g(f.calc_center_median()), 0.02):
            in_v_kept.append((f, vis, tot))
    for f, r in res.items():
        if r[0] == r[1] and in_v(g(f.calc_center_median()), 0.02):
            in_v_kept.append((f, r[0], r[1]))
    partial_rows = [(f[src_l], fmt_box(describe([f])), vis, tot) for f, vis, tot in partial]

    # Crack caps. Above the ground storey the backdrop of a storey starts a few cm above
    # the slab top it stands on (for example walls from y 14.83 on a slab top at 14.80),
    # so a thin slit runs along the storey line. Through it the original showed the slab
    # top; the shell would show the hollow. The cap is the first CRACK_BAND metres of
    # that deleted slab top, kept along every backdrop or setback plane it ends on: the
    # same surface, UVs and normals the slit showed, and nothing deeper in the building.
    # A ray-diff probe against the original located the slits (W, N and setback at
    # y 14.8, W at 19.3).
    for f in delete:
        f[del_l] = 1
    env_planes = (("x", BX0, 1), ("x", BX1, -1), ("z", BZ0, 1), ("z", BZ1, -1), ("z", SETBACK_Z, -1))
    crack_jobs = []
    for f in delete:
        if f.normal.z < 0.999 or g(f.calc_center_median()).y < TOP_Y + 0.01:
            continue
        pts = [g(v.co) for v in f.verts]
        touch = []
        for axis, c, sgn in env_planes:
            on = [p for p in pts if abs((p.x if axis == "x" else p.z) - c) < 2e-3]
            if len(on) >= 2:
                touch.append((axis, c, sgn))
        if touch:
            crack_jobs.append((f, touch))
    # On the setback plane a strip is kept only where a kept wall stands on it just above
    # the slab top: that plane is also an artificial cut line where no setback wall exists.
    # (Gating the outer backdrop planes too reopened the W slit at y 19.3, where the slab
    # meets the roof edge, so they stay ungated.)
    walls_on = {}
    for f in bm.faces:
        if f[del_l] or abs(f.normal.z) > 0.01:
            continue
        lo, hi = gbox(f)
        for axis, c, sgn in env_planes:
            if axis == "x" and hi.x - lo.x < 1e-3 and abs(lo.x - c) < 0.02:
                walls_on.setdefault((axis, c), []).append((lo.z, hi.z, lo.y))
            if axis == "z" and hi.z - lo.z < 1e-3 and abs(lo.z - c) < 0.02:
                walls_on.setdefault((axis, c), []).append((lo.x, hi.x, lo.y))

    def wall_above(axis, c, a0, a1, y):
        return any(w0 < a1 - 0.01 and w1 > a0 + 0.01 and y - 0.01 <= wy <= y + 0.5
                   for w0, w1, wy in walls_on.get((axis, c), []))

    crack_rows = []
    no_wall = 0
    for k, (f, touch) in enumerate(crack_jobs, start=1):
        src_i = f[src_l]
        f[frag_l] = k
        for axis, c, sgn in touch:
            frags = [ff for ff in bm.faces if ff[frag_l] == k]
            bisect_faces(bm, frags, axis, c + sgn * CRACK_BAND)
        for ff in [ff for ff in bm.faces if ff[frag_l] == k]:
            cen = g(ff.calc_center_median())
            for axis, c, sgn in touch:
                d = ((cen.x if axis == "x" else cen.z) - c) * sgn
                if 0.0 < d < CRACK_BAND:
                    lo, hi = gbox(ff)
                    a0, a1 = (lo.z, hi.z) if axis == "x" else (lo.x, hi.x)
                    if c == SETBACK_Z and not wall_above(axis, c, a0, a1, cen.y):
                        no_wall += 1
                        break
                    ff[del_l] = 0
                    crack_rows.append((src_i, axis, c, fmt_box(describe([ff])), ff.calc_area()))
                    break
    delete = [f for f in bm.faces if f[del_l]]
    for f in bm.faces:
        if not f[del_l] and f[frag_l]:
            lo_y = min(g(v.co).y for v in f.verts)
            if lo_y < TOP_Y:
                die("a crack cap reaches into the ground storey: %s" % fmt_box(describe([f])))
    del_area = sum(f.calc_area() for f in delete)
    deleted_by_src = {}
    for f in delete:
        deleted_by_src[f[src_l]] = deleted_by_src.get(f[src_l], 0) + 1
    bmesh.ops.delete(bm, geom=delete, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    left_in_v = [f for f in bm.faces if f[src_l] in nominee and in_v(g(f.calc_center_median()), 0.02)]
    rep("nominee faces left inside the ground-storey volume V after deletion: %d" % len(left_in_v))
    if left_in_v:
        die("%d nominee faces remain inside V, e.g. %s" % (len(left_in_v), fmt_box(describe(left_in_v[:1]))))
    bm.normal_update()
    bm.verts.index_update()
    bm.faces.index_update()

    # ---- 4. leftovers
    unclassified = set()
    for i, d in enumerate(info):
        if i in nominee or cls[i].startswith("porch"):
            continue
        lo, hi = d["lo"], d["hi"]
        crosses_v = (hi.x > BX0 + 0.02 and lo.x < BX1 - 0.02 and hi.z > BZ0 + 0.02 and lo.z < BZ1 - 0.02
                     and hi.y > GROUND_Y + 0.02 and lo.y < TOP_Y - 0.02)
        if crosses_v:
            unclassified.add(i)
    kept_bvh = bvh_with(lambda f: True)
    hidden_left = []
    by_src = {}
    for f in bm.faces:
        by_src.setdefault(f[src_l], []).append(f)
    for i, fs in by_src.items():
        if i in nominee or cls[i] == "lot":
            continue
        d = info[i]
        if not (BX0 < d["c"].x < BX1 and BZ0 < d["c"].z < BZ1 and d["c"].y > GROUND_Y):
            continue
        if all(sees_out(kept_bvh, f)[0] == 0 for f in fs):
            hidden_left.append(i)

    # ---- 5. node assignment
    node_l = bm.faces.layers.string.new("node")

    def node_for(f):
        i = f[src_l]
        c = cls[i]
        if i in unclassified:
            return "Unclassified"
        if c == "lot":
            return "Lot"
        if c.startswith("porch"):
            return "Porch_%s" % c.split(":")[1]
        if c == "poles":
            return "Poles"
        cen = g(f.calc_center_median())
        if cen.y < TOP_Y - EPS and in_facade_zone(cen):
            side = side_of(cen)
            if side is None:
                return "Unclassified"
            return "facade:" + side
        if c == "facade" and cen.y < TOP_Y - EPS:
            return "Lot"
        if c == "other" and not in_facade_zone(info[i]["c"]) and info[i]["hi"].y <= 7.0:
            return "Lot"  # free-standing street furniture (sign posts)
        if cen.y < TOP_Y - EPS and info[i]["hi"].y <= 4.3:
            return "Lot"
        return "Upper"

    for f in bm.faces:
        f[node_l] = node_for(f).encode()
    # An Unclassified island is geometry in or at the build area that no rule explains: it
    # fails the build unless UNCLASSIFIED_ALLOWED lists it with a reason.
    stray = {}
    for f in bm.faces:
        if f[node_l] == b"Unclassified" and f[src_l] not in UNCLASSIFIED_ALLOWED:
            stray.setdefault(f[src_l], 0)
            stray[f[src_l]] += 1
    if stray:
        for i in sorted(stray):
            log("UNCLASSIFIED island %d (%d faces) %s matches=%s %s" % (
                i, stray[i], cls[i], matches[i], fmt_box(info[i])))
        die("%d unclassified island(s) cross the ground-storey volume V (x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f) "
            "or sit in the facade zone with no side, and are not in UNCLASSIFIED_ALLOWED: %s"
            % (len(stray), BX0, BX1, GROUND_Y, TOP_Y, BZ0, BZ1, sorted(stray)[:20]))

    # Canopy: the sloped landside canopy keeps showing while Upper dissolves, so its
    # islands leave Upper by source island (whole islands, no cuts). Boundary by position:
    # an island from the canopy's back fascia plane (z -71.00) outward that reaches past
    # z -63.0, i.e. more than 1.35 m out from the landside facade; plus each back-fascia
    # island in the plane z -71.00 that mirrors a front-fascia island of that set (same x
    # and y range); plus every pole cable, which hangs from the canopy.
    canopy = {i for i, d in enumerate(info) if cls[i] in ("upper", "other", "slab:roof") and d["lo"].y >= 4.9
              and d["lo"].z >= CANOPY_BACK_Z and d["hi"].z > CANOPY_REACH_Z}
    cables = {i for i in range(len(info)) if cls[i] == "upper:cable"}
    fascia = set()
    for i, d in enumerate(info):
        if i in canopy or abs(d["lo"].z + 71.0) > 0.01 or abs(d["hi"].z + 71.0) > 0.01:
            continue
        twins = [j for j in canopy if all(abs(info[j][k][a] - d[k][a]) < 0.05 for k in ("lo", "hi") for a in (0, 1))]
        if len(twins) == 1:
            fascia.add(i)
        elif len(twins) > 1:
            die("back fascia island %d has %d front twins" % (i, len(twins)))
    canopy |= cables | fascia
    canopy_from = {}
    for f in bm.faces:
        if f[src_l] not in canopy:
            continue
        old = f[node_l].decode()
        if old not in ("Upper", "Lot"):
            die("canopy island %d has a face in node %s at %s" % (f[src_l], old, fmt_box(describe([f]))))
        canopy_from[old] = canopy_from.get(old, 0) + 1
        f[node_l] = b"Canopy"
    # The canopy's soffits over two spans are fragments of storey slabs (y 5.80 and 14.80)
    # cut at the landside backdrop: every Upper face whose centre is more than 0.3 m outside
    # that backdrop goes with the canopy (the upper ledge rims stop 0.25 m out).
    soffit = 0
    for f in bm.faces:
        if f[node_l] == b"Upper" and g(f.calc_center_median()).z > BZ1 + 0.3:
            f[node_l] = b"Canopy"
            soffit += 1
    canopy_from["Upper (soffit fragments)"] = soffit
    low = [i for i in canopy if info[i]["lo"].y < 4.9]
    if low or sum(canopy_from.values()) == 0:
        die("canopy islands below y 4.9 %s, or no canopy faces" % low[:10])

    # Only long facade pieces are cut at the seams. A piece of a small island (a pilaster,
    # a sign mark, a mullion cap) goes whole to one bay instead: cutting it would split
    # faces that carry smooth custom normals and change their shading.
    def small_island(f, side):
        d = info[f[src_l]]
        return ((d["hi"].x - d["lo"].x) if side in ("N", "S") else (d["hi"].z - d["lo"].z)) <= 0.5

    seam_cuts = 0
    for side, axis, seams in (("N", "x", LONG_SEAMS), ("S", "x", LONG_SEAMS),
                              ("W", "z", SHORT_SEAMS), ("E", "z", SHORT_SEAMS)):
        for s in seams:
            faces = [f for f in bm.faces if f[node_l] == ("facade:" + side).encode()
                     and (f[src_l] < 0 or not small_island(f, side))]
            seam_cuts += bisect_faces(bm, faces, axis, s)
    bm.normal_update()

    for f in bm.faces:
        key = f[node_l].decode()
        if not key.startswith("facade:"):
            continue
        side = key.split(":")[1]
        d = info[f[src_l]]
        span = (d["hi"].x - d["lo"].x) if side in ("N", "S") else (d["hi"].z - d["lo"].z)
        small = span <= 0.5
        cen = d["c"] if small else g(f.calc_center_median())
        f[node_l] = ("Facade_%s_%02d" % (side, bay_of(side, cen, small))).encode()

    # ---- 6. closures (new faces: the inside wall swatch, or the ledge and stub swatches)
    backdrops = {}
    for i, d in enumerate(info):
        if d["n"] is None or d["faces"] > 2 or abs(d["lo"].y - GROUND_Y) > 0.01 or abs(d["hi"].y - TOP_Y) > 0.01:
            continue
        s = side_of(d["c"])
        if s and d["area"] > 100:
            backdrops[s] = i
    if sorted(backdrops) != ["E", "N", "S", "W"]:
        die("expected one backdrop quad per side, found %s" % sorted(backdrops))
    # The inside wall swatch must be light in the atlas the closures are drawn with
    # (material slot 0 of the main mesh, which every node mesh gets).
    atlas_img = [nd.image for nd in mat_main.node_tree.nodes if nd.type == "TEX_IMAGE" and nd.image]
    if mat_main.name != "TP_Atlas_1A_D" or len(atlas_img) != 1:
        die("main material is %s with %d images, expected TP_Atlas_1A_D with 1" % (mat_main.name, len(atlas_img)))
    atlas_img = atlas_img[0]
    aw, ah = atlas_img.size
    apx = atlas_img.pixels[:]
    wall_rgb = []
    for yy in (TOP_Y, GROUND_Y):
        uvw = wall_uv(yy)
        k = (min(ah - 1, int(uvw.y * ah)) * aw + min(aw - 1, int(uvw.x * aw))) * 4
        rgb = apx[k:k + 3]
        luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        wall_rgb.append((yy, uvw, tuple(round(c * 255) for c in rgb), luma))
        if luma < WALL_MIN_LUMA:
            die("inside wall swatch at y %.2f samples rgb %s (luma %.2f < %.2f)" % (yy, wall_rgb[-1][2], luma, WALL_MIN_LUMA))

    added = {}
    closure_l = bm.faces.layers.int.new("closure")

    def add_quad(node, corners_g, uvs, outward):
        """One closure quad; its front faces `outward` (a Godot direction)."""
        vs = [bm.verts.new(b(*p)) for p in corners_g]
        f = bm.faces.new(vs)
        f.normal_update()
        want = b(*outward) - b(0, 0, 0)
        if f.normal.dot(want) < 0:
            f.normal_flip()
        if f.normal.dot(want) < 0.99:
            die("closure quad on %s does not face %s" % (node, outward))
        for lp in f.loops:
            lp[uvl].uv = uvs[vs.index(lp.vert)]
        f[node_l] = node.encode()
        f[src_l] = -1
        f[closure_l] = 1
        f.material_index = 0
        f.smooth = False
        added[node] = added.get(node, 0) + 1
        return f

    for side in ("N", "S", "W", "E"):
        nbays = 22 if side in ("N", "S") else 12
        inward = {"N": (0, 0, 1), "S": (0, 0, -1), "W": (1, 0, 0), "E": (-1, 0, 0)}[side]
        outward = tuple(-c for c in inward)
        bd = {"N": BZ0, "S": BZ1, "W": BX0, "E": BX1}[side]
        inner = bd + INNER * (1 if side in ("N", "W") else -1)
        for bay in range(1, nbays + 1):
            node = "Facade_%s_%02d" % (side, bay)
            a, c = bay_span(side, bay)
            # inner face spans the inner rectangle; corners belong to N and S
            if side in ("N", "S"):
                ia = max(a, BX0 + INNER)
                ic = min(c, BX1 - INNER)
            else:
                ia = max(a, BZ0 + INNER)
                ic = min(c, BZ1 - INNER)
            y0, y1 = GROUND_Y, TOP_Y - 0.01

            def P(along, yy, depth):
                if side in ("N", "S"):
                    return (along, yy, depth)
                return (depth, yy, along)

            # inward face
            face = [P(ia, y0, inner), P(ic, y0, inner), P(ic, y1, inner), P(ia, y1, inner)]
            add_quad(node, face, wall_uvs(face), inward)
            # top cap from the inner face to the backdrop (N/S caps also cover the corners)
            ta, tc = (a, c) if side in ("N", "S") else (ia, ic)
            if side in ("N", "S"):
                ta = max(ta, BX0)
                tc = min(tc, BX1)
            cap = [P(ta, y1, inner), P(tc, y1, inner), P(tc, y1, bd), P(ta, y1, bd)]
            add_quad(node, cap, wall_uvs(cap), (0, 1, 0))
            # end reveals, inset into the bay, facing out of the bay along the wall
            lo_end, hi_end = ta + INSET, tc - INSET
            along_dir = (1, 0, 0) if side in ("N", "S") else (0, 0, 1)
            neg_dir = tuple(-k for k in along_dir)
            for e, dirv in ((lo_end, neg_dir), (hi_end, along_dir)):
                reveal = [P(e, y0, inner), P(e, y0, bd), P(e, y1, bd), P(e, y1, inner)]
                add_quad(node, reveal, wall_uvs(reveal), dirv)
                # ledge end caps between the backdrop and the ledge's outer face
                for ly0, ly1 in LEDGES:
                    luv = ledge_uv.get((side, ly0))
                    if luv is None:
                        die("no ledge swatch for %s %.1f" % (side, ly0))
                    add_quad(node, [P(e, ly0, bd), P(e, ly0, SLAB_OUT[side]), P(e, ly1, SLAB_OUT[side]),
                                    P(e, ly1, bd)], [Vector(luv)] * 4, dirv)
    # Tops of the mullion stubs cut at y 5.5: a cap over each stub's footprint, from the
    # backdrop out to the end cap, 2 mm below the cut, owned by the stub's bay.
    stub_cap_count = 0
    for i, c, lo, hi, uvc in stub_caps:
        side = side_of(c)
        if side is None:
            die("cut facade island %d has no side" % i)
        bd = {"N": BZ0, "S": BZ1, "W": BX0, "E": BX1}[side]
        node = "Facade_%s_%02d" % (side, bay_of(side, c, True))
        yy = TOP_Y - 0.002
        if side in ("N", "S"):
            pl = c.z
            corners = [(lo.x, yy, bd), (hi.x, yy, bd), (hi.x, yy, pl), (lo.x, yy, pl)]
        else:
            pl = c.x
            corners = [(bd, yy, lo.z), (bd, yy, hi.z), (pl, yy, hi.z), (pl, yy, lo.z)]
        add_quad(node, corners, [uvc] * 4, (0, 1, 0))
        stub_cap_count += 1
    bm.normal_update()
    doorways = cut_doorways(bm, doors, drum, node_l, uvl, add_quad)

    # ---- census report
    rep("SHELL CENSUS  source %s" % SRC)
    rep("main islands %d, faces before %d" % (len(isl), sum(len(x) for x in isl)))
    counts = {}
    for i in range(len(isl)):
        counts[cls[i]] = counts.get(cls[i], 0) + 1
    rep("")
    rep("class (first match)            islands")
    for k in sorted(counts):
        rep("  %-28s %6d" % (k, counts[k]))
    rep("  %-28s %6d" % ("TOTAL", sum(counts.values())))
    fam = {}
    for i, f in filler.items():
        fam[f] = fam.get(f, 0) + 1
    rep("")
    rep("filler families: %s" % fam)
    rep("slab caps: inner %d, roof %d, partly covered (kept as roof, listed) %d"
        % (len(inner_slab), len(roof), len(mixed_cap)))
    for i, h, t in mixed_cap:
        rep("  PARTLY COVERED CAP island %d  covered %d/%d  %s" % (i, h, t, fmt_box(info[i])))
    rep("")
    rep("multi-match islands (precedence picked the first): %d" % len(multi))
    pairs = {}
    for i, m in multi.items():
        pairs[" > ".join(m)] = pairs.get(" > ".join(m), 0) + 1
    for k in sorted(pairs, key=lambda k: -pairs[k]):
        rep("  %5d  %s" % (pairs[k], k))
    rep("")
    rep("crossings cut")
    for who, label, n in cut_log:
        rep("  %-22s %-24s faces cut %d" % (who, label, n))
    rep("  facade islands cut at y 5.5 (non-nominee): %d" % len(y55))
    for i in y55:
        rep("    island %d  %s" % (i, fmt_box(info[i])))
    rep("  islands crossing y 5.5 left whole (assigned by face centroid): %d" % len(cross_uncut))
    for i in cross_uncut:
        rep("    island %d  %s  %s" % (i, cls[i], fmt_box(info[i])))
    rep("  bay seam cuts (facade faces): %d" % seam_cuts)
    rep("")
    rep("nominee faces after cuts %d: deleted %d (%.1f m2), fully visible kept %d, partly visible kept %d"
        % (nominee_faces, len(delete), del_area, kept_vis, len(partial)))
    rep("nominee islands with deleted faces: %d of %d" % (len(deleted_by_src), len(nominee)))
    rep("deleted under the crack tolerance (<= 10 percent of samples see out) or inside V: %d"
        % len(crack_deleted))
    exits = {}
    for i, box, vis, tot, esc, why in crack_deleted:
        if esc:
            q = esc[2]
            k = "x %4d  y %3d  z %4d" % (round(q.x / 4) * 4, round(q.y), round(q.z / 2) * 2)
            exits[k] = exits.get(k, 0) + 1
    rep("  where those escaping rays leave the building box (4 m / 1 m / 2 m bins):")
    for k in sorted(exits, key=lambda k: -exits[k]):
        rep("    %3d  %s" % (exits[k], k))
    rep("  each of them:")
    for i, box, vis, tot, esc, why in crack_deleted:
        rep("    island %d (%s) %s, visible %d/%d  %s  escape from (%.2f, %.2f, %.2f) toward (%.2f, %.2f, %.2f)"
            % (i, cls[i], why, vis, tot, box, esc[0].x, esc[0].y, esc[0].z, esc[1].x, esc[1].y, esc[1].z))
    rep("visibility passes: exterior by position %d, tested %d, pass-1 clearly exterior %d, re-tested %d"
        % vis_passes)
    rep("partly visible nominee faces kept: %d outside the envelope (stubs, rims; expected), %d inside it"
        % (len(partial) - len(interior_partial), len(interior_partial)))
    rep("fully visible nominee faces inside the envelope (an envelope gap): %d" % len(interior_visible))
    for title, rows in (("INSIDE-ENVELOPE PARTLY VISIBLE (kept, ambiguous)", interior_partial),
                        ("INSIDE-ENVELOPE FULLY VISIBLE (kept, ambiguous)", interior_visible)):
        if rows:
            rep(title + ":")
        for i, box, vis, tot, esc in rows:
            e = "escape from (%.2f, %.2f, %.2f) toward (%.2f, %.2f, %.2f) leaves the box at (%.2f, %.2f, %.2f)" % (
                esc[0].x, esc[0].y, esc[0].z, esc[1].x, esc[1].y, esc[1].z, esc[2].x, esc[2].y, esc[2].z) if esc else ""
            rep("  island %d (%s) visible %d/%d  %s  %s" % (i, cls[i], vis, tot, box, e))
    rep("nominee faces inside V that can see out (left in the build area): %d" % len(in_v_kept))
    rep("KEPT BY EXTERIOR EXPOSURE (outside V, shows in an orthographic view of the original): %d faces, %.2f m2"
        % (len(kept_exposed), sum(r[2] for r in kept_exposed)))
    for i, box, area, vis, tot, d in kept_exposed:
        rep("  island %d (%s) %s  %.2f m2  26-dir visible %d/%d  escapes along (%.0f, %.0f, %.0f)"
            % (i, cls[i], box, area, vis, tot, d.x, d.y, d.z))
    rep("")
    rep("UNCLASSIFIED (non-nominee islands crossing the ground-storey volume V): %d" % len(unclassified))
    for i in sorted(unclassified):
        rep("  island %d  %s  matches=%s  %s" % (i, cls[i], matches[i], fmt_box(info[i])))
    rep("HIDDEN LEFTOVERS (kept non-nominee islands inside the envelope that cannot see out): %d"
        % len(hidden_left))
    for i in sorted(hidden_left):
        rep("  island %d  %s  %s" % (i, cls[i], fmt_box(info[i])))
    rep("")
    rep("closure faces added: %d total (inward faces, top caps, end reveals, ledge end caps, %d stub top caps)"
        % (sum(added.values()), stub_cap_count))
    rep("inside wall swatch (inward faces, top caps, end reveals, doorway wall jambs and lintels): "
        "TP_Atlas_1A_D column %d row %d; %s" % (WALL_SWATCH[0], WALL_SWATCH[1], "; ".join(
            "y %.2f uv (%.4f, %.4f) rgb %s luma %.2f" % (yy, uvw.x, uvw.y, rgb, lu) for yy, uvw, rgb, lu in wall_rgb)))
    rep("")
    rep("CRACK CAPS: %d deleted slab tops above the ground storey end on a backdrop or setback plane; kept a "
        "%.1f m strip of each along that plane (on the setback plane only where a kept wall stands on it): "
        "%d strips, %.1f m2 (%d setback band fragments with no wall above dropped). Counts above this section are the initial deletion decision; "
        "after the caps %d nominee faces are deleted (%.1f m2)" % (
            len(crack_jobs), CRACK_BAND, len(crack_rows), sum(r[4] for r in crack_rows), no_wall,
            len(delete), del_area))
    for i, axis, c, box, area in crack_rows:
        rep("  island %d (%s) along %s %.2f  %s  %.2f m2" % (i, cls[i], axis, c, box, area))
    rep("")
    rep("CANOPY: %d source islands (%d reach past z %.1f from z %.2f, %d back-fascia twins, %d pole cables); "
        "faces moved from %s" % (len(canopy), len(canopy - cables - fascia), CANOPY_REACH_Z, CANOPY_BACK_Z,
                                 len(fascia), len(cables), canopy_from))
    rep("")
    rep("DOORWAYS (opening = the vestibule's back panel width, y %.2f..%.2f, inward face to the old back panel):"
        % (GROUND_Y, OPEN_TOP))
    for dw in doorways:
        rep("  Doorway_%d in %s: x %.3f..%.3f (width %.3f, drum %.3f), z %.2f..%.2f, faces cut %d, deleted %d bay + "
            "%d back panel, closure quads %d (wall and vestibule jambs, lintel to the porch ceiling edge z %.2f); "
            "rays through the opening clear %d/81, control rays beside it hit %d/2" % (
                dw["k"], dw["node"], dw["c"].x - dw["hw"], dw["c"].x + dw["hw"], 2 * dw["hw"], 2 * drum[dw["k"]],
                dw["inner"], dw["outer"], dw["cuts"], dw["deleted"], dw["panel"], dw["quads"], dw["edge"],
                dw["clear"], dw["control"]))
        for x, hit_node, hit_z, dist in dw["control_rows"]:
            rep("    control ray x %.3f: first hit %s at z %.4f (inward face z %.4f), %.3f m from its start"
                % (x, hit_node, hit_z, dw["inner"], dist))

    # ---- 7. split into objects, hierarchy, export
    root = bpy.data.objects.new("TP_Airport_Shell_ROOT", None)
    bpy.context.scene.collection.objects.link(root)
    facade_root = bpy.data.objects.new("Facade", None)
    bpy.context.scene.collection.objects.link(facade_root)
    facade_root.parent = root
    keys = sorted({f[node_l].decode() for f in bm.faces})
    node_faces = {}
    normal_dev = {}
    for key in keys:
        bm2 = bm.copy()
        nl = bm2.faces.layers.string["node"]
        bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if f[nl].decode() != key], context="FACES")
        bmesh.ops.delete(bm2, geom=[v for v in bm2.verts if not v.link_faces], context="VERTS")
        me = bpy.data.meshes.new(key)
        bm2.to_mesh(me)
        bm2.free()
        flags = [0] * len(me.polygons)
        if "closure" in me.attributes:
            me.attributes["closure"].data.foreach_get("value", flags)
        elif key in added:
            die("node %s got closure faces but its mesh has no closure attribute" % key)
        worst_src = worst_new = 0.0
        for poly, flag in zip(me.polygons, flags):
            for li in poly.loop_indices:
                a = me.corner_normals[li].vector.angle(poly.normal, 0.0)
                if flag:
                    worst_new = max(worst_new, a)
                else:
                    worst_src = max(worst_src, a)
        if math.degrees(worst_new) > 1.0:
            die("closure faces on %s do not carry their face normal (%.2f deg)" % (key, math.degrees(worst_new)))
        normal_dev[key] = math.degrees(worst_src)
        for attr in ("src", "node", "closure", "del", "frag"):
            if attr in me.attributes:
                me.attributes.remove(me.attributes[attr])
        me.materials.append(mat_main)
        ob = bpy.data.objects.new(key, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = facade_root if key.startswith("Facade_") else root
        node_faces[key] = len(me.polygons)
    bm.free()
    # Doorway_<n>: an empty on the floor at the centre of each opening, on the backdrop
    # plane, whose local -Z (Godot's forward) points out of the building. glTF extras
    # carry the door, the bay, the outward vector and the opening's size.
    for dw in doorways:
        e = bpy.data.objects.new("Doorway_%d" % dw["k"], None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = root
        e.location = b(dw["c"].x, GROUND_Y, dw["bd"])
        e.rotation_euler = (0.0, 0.0, 0.0 if dw["side"] == "N" else math.pi)
        e["door"] = "Door_%d" % dw["k"]
        e["bay"] = dw["node"]
        e["outward"] = list(dw["outward"])
        e["width"] = round(2 * dw["hw"], 4)
        e["height"] = round(OPEN_TOP - GROUND_Y, 4)
    smooth = sorted((v, k) for k, v in normal_dev.items() if v > 1.0)
    rep("source custom normals kept; closure faces carry their face normal (< 1 deg). Nodes whose source "
        "faces are smooth-shaded (worst corner normal off the face normal): %s"
        % ", ".join("%s %.1f deg" % (k, v) for v, k in reversed(smooth)))
    # Lights: the window glow panels of every storey. The panels above the ground storey
    # must hide with Upper, so the node splits by panel (island) centroid height into
    # Lights_Ground and Lights_Upper under a Lights empty. No panel is cut.
    lights = objs["TP_Airport_01A_Lights"]
    lights_root = bpy.data.objects.new("Lights", None)
    bpy.context.scene.collection.objects.link(lights_root)
    lights_root.parent = root
    lbm = bmesh.new()
    lbm.from_mesh(lights.data)
    lbm.transform(lights.matrix_world)
    lisl = islands_of(lbm)
    lit_rows = []
    def light_node(comp):
        d = describe(comp)
        if d["c"].y >= TOP_Y:
            return "Lights_Upper"
        side = side_of(d["c"])
        if side is None:
            return "Lights_Ground_Other"
        return "Lights_%s_%02d" % (side, bay_of(side, d["c"], False))

    lnode = [light_node(comp) for comp in lisl]
    crossing = 0
    for comp, name in zip(lisl, lnode):
        if name.startswith("Lights_") and name[7:8] in "NSWE" and name[8:9] == "_":
            d = describe(comp)
            side = name[7]
            seams, lo_, hi_ = (LONG_SEAMS, d["lo"].x, d["hi"].x) if side in "NS" else (SHORT_SEAMS, d["lo"].z, d["hi"].z)
            crossing += sum(1 for sm in seams if lo_ < sm < hi_)
    for part in sorted(set(lnode)):
        keep = {f for comp, name in zip(lisl, lnode) if name == part for f in comp}
        bm3 = lbm.copy()
        bm3.faces.ensure_lookup_table()
        idx = {f.index for f in keep}
        bmesh.ops.delete(bm3, geom=[f for f in bm3.faces if f.index not in idx], context="FACES")
        bmesh.ops.delete(bm3, geom=[v for v in bm3.verts if not v.link_faces], context="VERTS")
        me = bpy.data.meshes.new(part)
        bm3.to_mesh(me)
        bm3.free()
        me.materials.append(lights.material_slots[0].material)
        ob = bpy.data.objects.new(part, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = lights_root
        lit_rows.append("%s %d" % (part, sum(1 for name in lnode if name == part)))
    lights_in_v = sum(1 for comp in lisl if in_v(describe(comp)["c"], 0.02))
    lbm.free()
    bpy.data.objects.remove(lights, do_unlink=True)
    rep("Lights split (panels per node): %s" % ", ".join(lit_rows))
    rep("Lights panels inside the ground-storey volume V: %d; ground panels crossing a bay seam: %d"
        % (lights_in_v, crossing))
    renames = {"TP_Airport_01A_Road": "Road"}
    renames.update({"TP_Airport_01A_Door_%d" % k: "Door_%d" % k for k in range(1, 9)})
    for old, new in renames.items():
        o = objs[old]
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw
        o.name = new
        o.data.name = new
    bpy.data.objects.remove(main_ob, do_unlink=True)
    bpy.context.view_layer.update()
    names = sorted(o.name for o in bpy.context.scene.objects)
    for want in ["Upper", "Canopy", "Lot", "Poles", "Lights_Upper", "Road"] + [
            "Door_%d" % k for k in range(1, 9)] + ["Doorway_%d" % k for k in range(1, 9)]:
        if want not in names:
            die("node missing before export: %s" % want)

    bpy.ops.object.select_all(action="SELECT")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    write_import(out_path, rep)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_vertex_color="NONE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=False,
        export_morph=False,
        export_skins=False,
        export_animations=False,
        export_extras=True,
    )
    expected = {}
    for o in bpy.context.scene.objects:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
        expected[o.name] = (o.parent.name if o.parent else None, tris)
    reread(out_path, expected, rep, doorways)
    path = os.path.join(REPORT_DIR, "census.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(report) + "\n")
    for line in report:
        print("CENSUS", line, flush=True)
    log("WROTE %s" % out_path)
    log("REPORT %s" % path)


# ------------------------------------------------------------------ import settings


def write_import(out_path, rep):
    """Give the shell the source's Godot import settings BEFORE the .glb is written, so an
    open editor that reimports it binds the shared toon materials through
    toon_post_import.gd and discards the embedded images (embedded_image_handling=0)
    instead of extracting duplicate atlas PNGs next to the .glb. An existing .import keeps
    its [remap] and [deps] (its uid); only [params] is replaced with the source's."""
    src_imp = SRC + ".import"
    with open(src_imp, encoding="utf-8") as fh:
        src_text = fh.read()
    params = src_text[src_text.index("[params]"):]
    for need in ('import_script/path="res://assets/toon_post_import.gd"', "gltf/embedded_image_handling=0"):
        if need not in params:
            die("source import settings lack %s" % need)
    imp = out_path + ".import"
    if os.path.exists(imp):
        with open(imp, encoding="utf-8") as fh:
            text = fh.read()
        text = text[:text.index("[params]")] + params
        how = "patched [params] of the existing file (uid kept)"
    else:
        text = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n' + params
        how = "written new (Godot adds the uid on import)"
    with open(imp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    rep("import settings: %s, %s; params copied from %s" % (imp, how, os.path.basename(src_imp)))


# ------------------------------------------------------------------ re-read


def node_matrix(nd):
    if "matrix" in nd:
        m = nd["matrix"]
        return Matrix([[m[c * 4 + r] for c in range(4)] for r in range(4)])
    t = nd.get("translation", [0, 0, 0])
    r = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    q = Quaternion((r[3], r[0], r[1], r[2]))
    return Matrix.Translation(Vector(t)) @ q.to_matrix().to_4x4() @ Matrix.Diagonal(Vector((s[0], s[1], s[2], 1.0)))


def reread(path, expected, rep, doorways):
    """Every number here comes from the written file."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, _v, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a GLB: %s" % path)
    jlen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + jlen])
    nodes = js["nodes"]
    mats = [m["name"] for m in js.get("materials", [])]
    imgs = [im.get("name", "?") for im in js.get("images", [])]
    binding = []
    for m in js.get("materials", []):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        img = imgs[js["textures"][t["index"]]["source"]] if t else None
        binding.append("%s->%s" % (m["name"], img))
    rep("")
    rep("RE-READ %s bytes=%d nodes=%d meshes=%d materials=%s images=%s" % (
        path, len(data), len(nodes), len(js.get("meshes", [])), mats, imgs))
    rep("material binding: %s" % binding)
    want_mats = {"TP_Atlas_1A_D", "TP_Atlas_Lights_1A_D", "TP_Atlas_Simple_1A_D", "TP_Glass_1A_D"}
    if set(mats) != want_mats or len(imgs) != 3:
        die("written file has materials %s images %s" % (mats, imgs))
    for bnd in binding:
        if bnd.endswith("->None"):
            die("material without an atlas image: %s" % bnd)
    rows = []
    total = 0

    seen = {}
    empties = {}

    def walk(i, parent, depth, pname=None):
        nonlocal total
        nd = nodes[i]
        world = parent @ node_matrix(nd)
        name = nd.get("name", "?")
        if "mesh" in nd:
            faces = 0
            lo = Vector((math.inf,) * 3)
            hi = Vector((-math.inf,) * 3)
            pm = set()
            for prim in js["meshes"][nd["mesh"]]["primitives"]:
                faces += js["accessors"][prim["indices"]]["count"] // 3
                pm.add(mats[prim["material"]] if "material" in prim else None)
                acc = js["accessors"][prim["attributes"]["POSITION"]]
                for cx in (acc["min"][0], acc["max"][0]):
                    for cy in (acc["min"][1], acc["max"][1]):
                        for cz in (acc["min"][2], acc["max"][2]):
                            w = world @ Vector((cx, cy, cz))
                            for k in range(3):
                                lo[k] = min(lo[k], w[k])
                                hi[k] = max(hi[k], w[k])
            total += faces
            seen[nd.get("name", "?")] = (pname, faces)
            rows.append((depth, name, faces, sorted(m or "-" for m in pm),
                         "x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
                             lo.x, hi.x, lo.y, hi.y, lo.z + OFFSET_Z, hi.z + OFFSET_Z)))
        else:
            seen[name] = (pname, 0)
            empties[name] = (world, nd.get("extras"))
            p = world.to_translation()
            rows.append((depth, name, 0, [], "(empty) at x %.3f y %.3f z %.3f" % (p.x, p.y, p.z + OFFSET_Z)))
        for c in nd.get("children", []):
            walk(c, world, depth + 1, name)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, Matrix.Identity(4), 0)
    rep("node tree (triangles, materials, Godot world AABB with the (0,0,-80) placement):")
    for depth, name, faces, pm, box in rows:
        rep("  %s%-22s tris %6d  %-48s %s" % ("  " * depth, name, faces, ",".join(pm), box))
    rep("total triangles %d" % total)
    names = [r[1] for r in rows]
    for want in ["TP_Airport_Shell_ROOT", "Facade", "Upper", "Lot", "Poles", "Lights",
                 "Lights_Upper", "Road"]:
        if want not in names:
            die("written file lacks node %s" % want)
    bays = {"Facade_%s_%02d" % (sd, k) for sd in "NS" for k in range(1, 23)}
    bays |= {"Facade_%s_%02d" % (sd, k) for sd in "WE" for k in range(1, 13)}
    if {n for n in names if n.startswith("Facade_")} != bays:
        die("written facade bays differ from the 68 expected names")
    if "Unclassified" in names:
        if not UNCLASSIFIED_ALLOWED:
            die("written file has an Unclassified node, and UNCLASSIFIED_ALLOWED is empty")
        rep("NOTE: an Unclassified node was written, holding only allowlisted islands %s"
            % sorted(UNCLASSIFIED_ALLOWED))
    bad = []
    for name, (parent, tris) in expected.items():
        got = seen.get(name)
        if got is None:
            bad.append("%s missing" % name)
        elif got != (parent, tris):
            bad.append("%s expected parent/tris %s got %s" % (name, (parent, tris), got))
    extra = set(seen) - set(expected)
    if bad or extra:
        die("re-read mismatch: %s extra=%s" % (bad[:10], sorted(extra)[:10]))
    rep("re-read matches the scene: %d nodes, names, parents and triangle counts" % len(seen))
    if seen.get("Canopy", (None, 0))[1] == 0 or seen["Canopy"][0] != "TP_Airport_Shell_ROOT":
        die("written file lacks a non-empty Canopy under the root")
    marks = sorted(n for n in seen if n.startswith("Doorway_"))
    if marks != ["Doorway_%d" % dw["k"] for dw in sorted(doorways, key=lambda r: r["k"])] or len(marks) != 8:
        die("written doorway markers %s" % marks)
    for dw in doorways:
        name = "Doorway_%d" % dw["k"]
        world, extras = empties[name]
        p = world.to_translation()
        fwd = -(world.to_3x3() @ Vector((0, 0, 1)))
        want_p = Vector((dw["c"].x, GROUND_Y, dw["bd"] - OFFSET_Z))
        want_f = Vector(dw["outward"])
        scale = world.to_scale()
        ex = extras or {}
        ok = ((p - want_p).length < 1e-3 and (fwd - want_f).length < 1e-4 and (scale - Vector((1, 1, 1))).length < 1e-4
              and seen[name][0] == "TP_Airport_Shell_ROOT" and ex.get("door") == "Door_%d" % dw["k"]
              and ex.get("bay") == dw["node"] and abs(ex.get("width", 0) - 2 * dw["hw"]) < 1e-3
              and abs(ex.get("height", 0) - (OPEN_TOP - GROUND_Y)) < 1e-3
              and (Vector(ex.get("outward", (0, 0, 0))) - want_f).length < 1e-6)
        rep("  %s written at (%.3f, %.3f, %.3f), -Z (%.3f, %.3f, %.3f), extras %s" % (
            name, p.x, p.y, p.z + OFFSET_Z, fwd.x, fwd.y, fwd.z, json.dumps(ex, sort_keys=True)))
        if not ok:
            die("written %s does not match its doorway (position, -Z, scale, parent or extras)" % name)
    other_extras = sorted(nd.get("name", "?") for nd in nodes if nd.get("extras") and
                          not nd.get("name", "").startswith("Doorway_"))
    rep("doorway markers verified in the written file (8); other nodes with extras: %s" % other_extras)


main()
