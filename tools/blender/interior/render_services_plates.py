"""Render the plates for the services kit and check the seated fit numerically.

Run (headless, reproducible), after build_services_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_services_plates.py' [-- stage ...]

Stages: fit, six, thumbs, sit, door, distance, context (all when none is named).
Everything is written under tools/blender/out/furniture-3b/ (gitignored); nothing in
game/ is touched. The plates re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at one scale per piece, true scale,
  with a 1 m reference cube;
- thumbs/<piece>.png and thumbs/contact_sheet.png: the build-menu thumbnail framing;
- sit/<piece>.png: characters at sit_idle on every seat (both characters at every seat
  across two plates), front and back 3/4 and both sides; sit/strip_*.png: sit_down and
  stand_up strips of five frames; sit/worst_*.png: each seat at its deepest-contact
  frame from the fit check;
- door/shower_closed.png and door/shower_open.png: the shower door turned on its hinge;
- distance.png: every piece, perspective, about 30 m out, a person for scale;
- context.png: a room with floor tiles and a back wall, the pieces in use, characters
  seated at the bar, table, booth and nap pod, and standing at the counters and ATM.
Each plate proves its subjects are in frame and visible (render_activities_plates'
prove_in_frame and visible_share); on failure PROBE_INVALID and exit 1.

Seated fit: render_activities_plates' method (every frame of sit_down, sit_idle and
stand_up at every sit mount for both characters; vertex containment and clipped
crossing polygons against each part rebuilt with the builder; two negative controls),
with the root held at the mount, so the game's shuffle from the faced cell is not
covered. Every rebuilt part must be a closed convex solid: each edge on exactly two
faces and every vertex on or inside every face plane, or the run stops.

The generic helpers (scene, materials, cameras, framing, visibility, character posing,
the fit maths) are imported from render_activities_plates.py, whose main() does not run
on import; the piece-dependent stages are written here.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import build_services_kit as svc  # noqa: E402
import render_activities_plates as rap  # noqa: E402

REPO = kit.REPO
KIT_DIR = kit.OUT_DIR
OUT = os.path.join(REPO, "tools", "blender", "out", "furniture-3b")

PIECES = list(svc.PIECES)
SITS = [p for p in PIECES if any(k == "sit_root" for k, _p, _y in svc.SERVICES[p]["mounts"].values())]
CHARS = rap.CHARS
FIT_SOFT_M = rap.FIT_SOFT_M
FIT_RIGID_M = rap.FIT_RIGID_M
MARGIN = rap.MARGIN
BACKDROP = rap.BACKDROP
CONVEX_EPS = 1e-5

THUMB_CLASSES = {
    "1x1_tall": ((1.0, 1.0, 2.3), (0.0, 0.0, 1.15)),
    "2x1_tall": ((2.0, 1.0, 2.3), (0.0, 0.0, 1.15)),
    "2x2": ((2.0, 2.0, 1.6), (0.0, 0.0, 0.8)),
    "2x3": ((2.0, 3.0, 1.2), (0.0, 0.0, 0.6)),
}
THUMB_CLASS = {
    "bar_counter": "2x2", "restaurant_table": "2x3", "restaurant_booth": "2x3",
    "grab_and_go_stall": "2x1_tall", "info_desk": "2x1_tall", "currency_exchange": "2x1_tall",
    "pharmacy_counter": "2x1_tall", "pharmacy_shelf": "2x1_tall",
    "atm": "1x1_tall", "shower_cubicle": "1x1_tall", "nap_pod": "1x1_tall",
}

log = rap.log
invalid = rap.invalid


def glb(piece):
    return os.path.join(KIT_DIR, piece + ".glb")


def sit_mounts(piece):
    return [(m, pos, yaw) for m, (k, pos, yaw) in svc.SERVICES[piece]["mounts"].items() if k == "sit_root"]


# ---------------------------------------------------------------- six-axis


def six_axis(piece):
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs, _a, names, _h = rap.import_glb(glb(piece), piece)
    lo, hi = rap.bounds(objs)
    ref = rap.cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
    sub = rap.world_points(objs)
    ref_pts = rap.world_points([ref])
    allp = np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in rap.VIEWS:
        inv = np.array(rap.look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * MARGIN - 0.04
    log("%s six_axis materials=%s size_m=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (piece, sorted(names), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale, rap.SIX_PX / scale))
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "%s six_axis %s" % (piece, name)
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        path = os.path.join(OUT, "six_axis", "%s_%s.png" % (piece, name))
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
        bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 3), os.path.join(OUT, "six_axis", piece + ".png"))


# ---------------------------------------------------------------- thumbnails


def thumbnail(piece):
    ss = rap.THUMB_SS
    scene = rap.reset_scene(rap.THUMB * ss, rap.THUMB * ss, 1.5 * ss)
    objs, _a, names, _h = rap.import_glb(glb(piece), piece)
    az, el = rap.CAM_AZIMUTH, rap.CAM_ELEVATION
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    rot = (-direction).to_track_quat("-Z", "Y")
    cls = THUMB_CLASS[piece]
    (w, d, h), (cx, cy, cz) = THUMB_CLASSES[cls]
    inv = rot.to_matrix().inverted()
    xs, ys = [], []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                p = inv @ Vector((cx + sx * w, cy + sy * d, cz + sz * h))
                xs.append(p.x)
                ys.append(p.y)
    fit = 1.0 - 2.0 * MARGIN - 0.04
    nominal = max(max(xs) - min(xs), max(ys) - min(ys)) / fit
    pts = rap.world_points(objs)
    loc = pts @ np.array(inv).T
    actual = max(loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min()) / fit
    if actual > nominal:
        log("CLASS_OVERFLOW %s outgrows class %s: %.2f > %.2f" % (piece, cls, actual, nominal))
    cam = rap.ortho_camera(scene, rot, pts, max(nominal, actual))
    rap.prove_in_frame("%s thumb class=%s materials=%s" % (piece, cls, sorted(names)), scene, cam, pts,
                       rap.THUMB_MIN_SHARE)
    path = os.path.join(OUT, "thumbs", piece + ".png")
    small = rap.downscale(rap.render(scene, path), ss)
    rap.save_array(small, path)
    corner = float(small[-1, 0, 3])
    log("%s thumb corner_alpha=%.2f" % (piece, corner))
    if corner > 0.01:
        invalid("%s thumbnail background is not transparent" % piece)
    return small


def thumb_sheet(thumbs):
    big = [rap.over(t, (0.16, 0.18, 0.22)) for t in thumbs]
    small = [rap.downscale(t, 4) for t in thumbs]
    rows = [rap.grid([rap.over(s, (0.86, 0.87, 0.84)) for s in small], len(small)),
            rap.grid([rap.over(s, (0.16, 0.18, 0.22)) for s in small], len(small))]
    top = rap.grid(big, 6)
    W = max(top.shape[1], max(r.shape[1] for r in rows))

    def pad(a):
        fill = np.tile(np.array((0.08, 0.08, 0.09, 1.0), np.float32), (a.shape[0], W - a.shape[1], 1))
        return np.concatenate([a, fill], axis=1)

    sheet = np.concatenate([pad(top)] + [pad(r) for r in reversed(rows)], axis=0)
    rap.save_array(sheet, os.path.join(OUT, "thumbs", "contact_sheet.png"))


# ---------------------------------------------------------------- seated fit


def convex_parts(piece):
    """The piece rebuilt part by part with the builder, each part checked to be a closed
    convex solid: (name, planes (n x 4), BVH, half thickness)."""
    c = bpy.data.collections.new("FIT_" + piece)
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new("FIT_ROOT_" + piece, None)
    c.objects.link(root)
    svc.PIECES[piece][0](root, c)
    bpy.context.view_layer.update()
    parts = []
    worst_convex = 0.0
    thinnest = 0.0
    for o in c.objects:
        if o.type != "MESH":
            continue
        o.hide_render = True
        mw = o.matrix_world
        me = o.data
        verts = [mw @ v.co for v in me.vertices]
        edge_faces = {}
        for poly in me.polygons:
            for ek in poly.edge_keys:
                edge_faces[ek] = edge_faces.get(ek, 0) + 1
        open_edges = sum(1 for n in edge_faces.values() if n != 2)
        # A degenerate face (no area, no normal) or a collapsed solid would pass the
        # plane test with fewer planes, so both stop the run.
        degenerate = [p.index for p in me.polygons if p.area < 1e-9 or p.normal.length < 0.5]
        if degenerate:
            invalid("%s: part %s has %d degenerate faces" % (piece, o.name, len(degenerate)))
        planes = []
        for poly in me.polygons:
            n = (mw.to_3x3() @ poly.normal).normalized()
            planes.append((n.x, n.y, n.z, n.dot(verts[poly.vertices[0]])))
        planes = np.array(planes)
        vco = np.array([tuple(v) for v in verts])
        outside = float((vco @ planes[:, :3].T - planes[:, 3]).max())
        worst_convex = max(worst_convex, outside)
        if open_edges or outside > CONVEX_EPS:
            invalid("%s: part %s is not a closed convex solid (edges not on two faces=%d, vertex outside a face "
                    "plane by %.6f m)" % (piece, o.name, open_edges, outside))
        polys = [tuple(p.vertices) for p in me.polygons]
        half = float((planes[:, 3] - (vco @ planes[:, :3].T)).max(axis=0).min()) / 2.0
        if half < 1e-3:
            invalid("%s: part %s is collapsed (half thickness %.6f m)" % (piece, o.name, half))
        thinnest = min(thinnest, half) if parts else half
        parts.append((o.name, planes, BVHTree.FromPolygons(verts, polys), half))
    log("FIT %s convex_parts=%d all_closed_convex=True degenerate_faces=0 worst_vertex_outside_plane=%.2e "
        "thinnest_half_thickness=%.4f" % (piece, len(parts), worst_convex, thinnest))
    return parts, c


def frame_depths(parts, cb, verts, polys):
    """part -> (depth, world point, kind) for the parts the body enters this frame."""
    out = {}
    for name, planes, bvh, _half in parts:
        s = verts @ planes[:, :3].T - planes[:, 3]
        inside = (s < 0).all(axis=1)
        if inside.any():
            d = rap.inside_depth(verts[inside], planes)
            k = int(d.argmax())
            out[name] = (float(d[k]), verts[inside][k], "vertex")
        for ci in {pair[0] for pair in cb.overlap(bvh)}:
            poly = verts[list(polys[ci])]
            d = rap.crossing_depth(poly, planes)
            if d > out.get(name, (0.0,))[0]:
                out[name] = (d, poly.mean(axis=0), "triangle")
    return out


def limit_of(name):
    return FIT_SOFT_M if rap.soft(name) else FIT_RIGID_M


def fit_check(piece, mount, who):
    """Every frame of sit_down, sit_idle and stand_up at one mount, with both negative
    controls. Returns (ok, worst (depth, part, clip, frame) or None)."""
    rap.reset_scene(64, 64)
    objs, _a, _n, _h = rap.import_glb(glb(piece), piece)
    for o in objs:
        o.hide_render = True
    xf = rap.mount_xf(objs, mount)
    parts, fit_coll = convex_parts(piece)
    label = "%s %s %s" % (piece, mount, who)
    err, n_w, n_r = rap.same_geometry(objs, fit_coll)
    log("FIT %s rebuilt_vs_written_vertices max_err=%.6f written=%d rebuilt=%d" % (label, err, n_w, n_r))
    if err > 2e-4:
        invalid("%s: the rebuilt fit parts differ from the written .glb by %.5f m" % (label, err))
    cobjs, acts, arm, hold = rap.add_character(who, xf)
    rap.pose(arm, acts, "idle", rap.clip_range(acts, "idle")[0])
    stand_top = rap.world_points(cobjs)[:, 2].max()
    s0, s1 = rap.clip_range(acts, "sit_idle")
    rap.pose(arm, acts, "sit_idle", (s0 + s1) // 2)
    sit_top = rap.world_points(cobjs)[:, 2].max()
    log("FIT %s control stand_top=%.3f sit_top=%.3f drop=%.3f" % (label, stand_top, sit_top, stand_top - sit_top))
    if stand_top - sit_top < 0.25:
        invalid("%s: the sit pose did not engage (drop %.3f m)" % (label, stand_top - sit_top))
    worst = {}
    frames = 0
    for clip in ("sit_down", "sit_idle", "stand_up"):
        f0, f1 = rap.clip_range(acts, clip)
        for f in range(f0, f1 + 1):
            rap.pose(arm, acts, clip, f)
            frames += 1
            cb, verts, polys = rap.char_mesh(cobjs)
            for name, (depth, p, kind) in frame_depths(parts, cb, verts, polys).items():
                if depth > worst.get(name, (0.0,))[0]:
                    q = xf.inverted() @ Vector(p)
                    worst[name] = (depth, kind, clip, f, (q.x, q.z, -q.y))
    ok = True
    halves = {name: half for name, _p, _b, half in parts}
    for name, (depth, kind, clip, f, at) in sorted(worst.items(), key=lambda kv: -kv[1][0]):
        limit = limit_of(name)
        thin = halves[name] <= limit
        bad = depth > limit or thin
        ok = ok and not bad
        log("FIT %s part=%s depth=%.4f from=%s at %s:%d point_in_mount_frame=(%.3f, %.3f, %.3f) "
            "half_thickness=%.3f limit=%.3f %s"
            % (label, name, depth, kind, clip, f, at[0], at[1], at[2], halves[name], limit,
               "UNCERTIFIED_THIN" if thin else ("FAIL" if bad else "ok")))
    # Negative control 1: the seated frame pushed 0.06 m down must fail the gate.
    rap.pose(arm, acts, "sit_idle", (s0 + s1) // 2)
    hold.matrix_world = Matrix.Translation((0.0, 0.0, -0.06)) @ xf
    bpy.context.view_layer.update()
    cb, verts, polys = rap.char_mesh(cobjs)
    sunk = frame_depths(parts, cb, verts, polys)
    caught = any(d > limit_of(n) for n, (d, _p, _k) in sunk.items())
    log("FIT %s negative_control sunk_0.06 deepest=%s caught=%s"
        % (label, sorted(((n, round(d, 3), k) for n, (d, _p, k) in sunk.items()), key=lambda kv: -kv[1])[:3],
           caught))
    if not caught:
        invalid("%s: a seated body sunk 0.06 m passed the fit gate" % label)
    hold.matrix_world = xf
    bpy.context.view_layer.update()
    # Negative control 2: a triangle slicing the thickest rigid part, corners outside.
    name, planes, _bvh, half = max((p for p in parts if not rap.soft(p[0])), key=lambda p: p[3])
    ob = fit_coll.objects[name]
    corners = np.array([tuple(ob.matrix_world @ v.co) for v in ob.data.vertices])
    centre = corners.mean(axis=0)
    reach = 3.0 * float(np.linalg.norm(corners - centre, axis=1).max())
    tri = np.array([centre + reach * np.array((math.cos(a), math.sin(a), 0.0)) for a in (0.0, 2.1, 4.2)])
    outside = not ((tri @ planes[:, :3].T - planes[:, 3]) < 0).all(axis=1).any()
    # Through the same detection path as the body: the triangle as the "character"
    # mesh, against every part, so the polygon-overlap branch of frame_depths is tested.
    tri_hits = frame_depths(parts, BVHTree.FromPolygons([Vector(p) for p in tri], [(0, 1, 2)]), tri, [(0, 1, 2)])
    slice_depth, _p, slice_kind = tri_hits.get(name, (0.0, None, "none"))
    log("FIT %s negative_control slicing_triangle part=%s corners_outside=%s depth=%.4f via=%s half_thickness=%.3f"
        % (label, name, outside, slice_depth, slice_kind, half))
    if not outside or slice_kind != "triangle" or slice_depth <= FIT_RIGID_M:
        invalid("%s: a triangle slicing %s with its corners outside passed the fit gate" % (label, name))
    deepest = max(worst.items(), key=lambda kv: kv[1][0] / limit_of(kv[0]), default=None)
    log("FIT %s frames=%d parts=%d deepest=%s result=%s"
        % (label, frames, len(parts), max((v[0] for v in worst.values()), default=0.0), "ok" if ok else "FAIL"))
    if deepest is None:
        return ok, None
    pname, (depth, _kind, clip, f, _at) = deepest
    return ok, (depth, pname, clip, f)


# ---------------------------------------------------------------- sit plates


def sit_scene(piece, seats, res=(768, 512)):
    scene = rap.reset_scene(res[0], res[1], 1.5)
    objs, _a, _n, _h = rap.import_glb(glb(piece), piece)
    chars = []
    for mount, who in seats:
        cobjs, acts, arm, _hold = rap.add_character(who, rap.mount_xf(objs, mount))
        chars.append((cobjs, acts, arm))
    return scene, objs, chars


def fit_ortho(scene, rot, pts, aspect=1.5):
    inv = np.array(rot.to_matrix().inverted())
    loc = pts @ inv.T
    ext = max((loc[:, 0].max() - loc[:, 0].min()) / aspect, loc[:, 1].max() - loc[:, 1].min())
    return rap.ortho_camera(scene, rot, pts, ext * max(aspect, 1.0) / (1.0 - 2.0 * MARGIN - 0.04))


def sit_plates(piece):
    mounts = sit_mounts(piece)
    names = [m for m, _p, _y in mounts]
    if len(names) == 1:
        combos = [[(names[0], "male")], [(names[0], "female")]]
    else:
        whos = ["male", "female"] * (len(names) // 2)
        combos = [list(zip(names, whos)), list(zip(names, whos[1:] + whos[:1]))]
    info = {m: (pos, yaw) for m, pos, yaw in mounts}
    tiles = []
    for n, seats in enumerate(combos):
        scene, objs, chars = sit_scene(piece, seats)
        for cobjs, acts, arm in chars:
            f0, f1 = rap.clip_range(acts, "sit_idle")
            rap.pose(arm, acts, "sit_idle", (f0 + f1) // 2)
        pts = rap.world_points(objs + [o for c in chars for o in c[0]])
        xs = [info[m][0][0] for m, _w in seats]
        faces_front = [abs(info[m][1]) < 1.0 for m, _w in seats]  # yaw 0: faces Godot +Z, Blender -y
        views = [("front34", (-0.45, -0.85, 0.75), faces_front),
                 ("back34", (0.45, 0.85, 0.75), [not f for f in faces_front]),
                 ("side_right", (1.0, 0.0, 0.15), [x > 0.01 for x in xs]),
                 ("side_left", (-1.0, 0.0, 0.15), [x < -0.01 for x in xs])]
        for view, d, must_see in views:
            rot = rap.look_rot(d, (0, 0, 1))
            cam = fit_ortho(scene, rot, pts)
            label = "%s sit %s %s" % (piece, "+".join("%s@%s" % (w, m) for m, w in seats), view)
            rap.prove_in_frame(label, scene, cam, pts)
            for (cobjs, _acts, _arm), see, (m, w) in zip(chars, must_see, seats):
                if see:
                    rap.visible_share("%s %s@%s" % (label, w, m), scene, cam, cobjs, need=0.10)
            path = os.path.join(OUT, "sit", "%s_%d_%s.png" % (piece, n, view))
            tiles.append(rap.over(rap.render(scene, path), BACKDROP))
            bpy.data.objects.remove(cam)
    rap.save_array(rap.grid(tiles, 4), os.path.join(OUT, "sit", piece + ".png"))


def strip(piece, mount, who, clip, view):
    scene, objs, chars = sit_scene(piece, [(mount, who)], res=(384, 512))
    cobjs, acts, arm = chars[0]
    rot = rap.look_rot(view, (0, 0, 1))
    f0, f1 = rap.clip_range(acts, clip)
    frames = [f0 + round((f1 - f0) * k / 4) for k in range(5)]
    allp = []
    for f in frames:
        rap.pose(arm, acts, clip, f)
        allp.append(rap.world_points(objs + cobjs))
    cam = fit_ortho(scene, rot, np.concatenate(allp), aspect=0.75)
    tiles = []
    for k, f in enumerate(frames):
        rap.pose(arm, acts, clip, f)
        label = "%s strip %s %s %s frame=%d" % (piece, clip, who, mount, f)
        rap.prove_in_frame(label, scene, cam, rap.world_points(objs + cobjs))
        rap.visible_share(label + " character", scene, cam, cobjs, need=0.10)
        path = os.path.join(OUT, "sit", "strip_%s_%s_%s_%s_%d.png" % (piece, mount, who, clip, k))
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
    rap.save_array(rap.grid(tiles, 5), os.path.join(OUT, "sit", "strip_%s_%s_%s_%s.png" % (piece, mount, who, clip)))


def worst_plate(piece, mount, who, worst):
    """The seat at its deepest-contact frame (relative to the part's limit), seen from
    the seat's open side and from the front 3/4."""
    depth, part, clip, f = worst
    scene, objs, chars = sit_scene(piece, [(mount, who)], res=(512, 512))
    cobjs, acts, arm = chars[0]
    rap.pose(arm, acts, clip, f)
    pos, yaw = next((p, y) for m, p, y in sit_mounts(piece) if m == mount)
    # Facing in Blender: yaw 0 faces Godot +Z, Blender -y.
    fx, fy = math.sin(math.radians(yaw)), -math.cos(math.radians(yaw))
    side = -1.0 if pos[0] < -0.01 else 1.0
    tiles = []
    for view, d in (("side", (side * 0.9 + fx * 0.3, fy * 0.3, 0.25)), ("front34", (fx * 0.8 - 0.4, fy * 0.8, 0.5))):
        rot = rap.look_rot(d, (0, 0, 1))
        pts = rap.world_points(objs + cobjs)
        cam = fit_ortho(scene, rot, pts, aspect=1.0)
        label = "%s worst %s %s %s:%d part=%s depth=%.4f %s" % (piece, mount, who, clip, f, part, depth, view)
        rap.prove_in_frame(label, scene, cam, pts)
        rap.visible_share(label + " character", scene, cam, cobjs, need=0.10)
        path = os.path.join(OUT, "sit", "worst_%s_%s_%s_%s.png" % (piece, mount, who, view))
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
        bpy.data.objects.remove(cam)
    return tiles


# ---------------------------------------------------------------- shower door


def door_plates():
    tiles = []
    for state, deg in (("closed", 0.0), ("open", svc.DOOR_OPEN_DEG)):
        scene = rap.reset_scene(512, 640, 1.5)
        objs, _a, _n, _h = rap.import_glb(glb("shower_cubicle"), "shower")
        hinge = next(o for o in objs if rap.base_name(o.name) == "Door_Leaf_Shower")
        leaf = [o for o in objs if rap.base_name(o.name) == "Door_Leaf_Shower_Mesh"]
        hp = hinge.matrix_world.translation.copy()
        hinge.matrix_world = (Matrix.Translation(hp) @ Matrix.Rotation(math.radians(deg), 4, "Z")
                              @ Matrix.Translation(-hp) @ hinge.matrix_world)
        bpy.context.view_layer.update()
        man, _acts, _arm, _hh = rap.add_character("male", rap.mount_xf(objs, "Mount_Use") if state == "closed"
                                                   else Matrix.Translation((0.55, -1.3, 0.0)))
        lo, hi = rap.bounds(leaf)
        log("door %s leaf_godot_x=[%.3f, %.3f] leaf_godot_z=[%.3f, %.3f]" % (state, lo.x, hi.x, -hi.y, -lo.y))
        pts = rap.world_points(objs + man)
        rot = rap.look_rot((0.75, -0.9, 0.55), (0, 0, 1))
        cam = fit_ortho(scene, rot, pts, aspect=0.8)
        label = "shower door %s" % state
        rap.prove_in_frame(label, scene, cam, pts)
        rap.visible_share(label + " leaf", scene, cam, leaf, need=0.10)
        rap.visible_share(label + " person", scene, cam, man, need=0.10)
        path = os.path.join(OUT, "door", "shower_%s.png" % state)
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
    rap.save_array(rap.grid(tiles, 2), os.path.join(OUT, "door", "shower_door.png"))


# ---------------------------------------------------------------- distance + context


def place_piece(piece, x, y, label=None, yaw=0.0):
    objs, _a, _n, holder = rap.import_glb(glb(piece) if piece in svc.PIECES else os.path.join(KIT_DIR, piece + ".glb"),
                                          label or piece, Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(yaw, 4, "Z"))
    return objs


def distance_shot():
    scene = rap.reset_scene(1600, 900, 1.0)
    subjects = {}
    rows = (PIECES[:6], PIECES[6:])
    for r, row in enumerate(rows):
        x = 0.0
        for piece in row:
            w, d = svc.SERVICES[piece]["footprint"]
            subjects[piece] = place_piece(piece, x + w / 2.0, r * 5.0)
            x += w + 1.0
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((x + 0.5, 5.0, 0.0)))
    subjects["male"] = man
    span = max(sum(svc.SERVICES[p]["footprint"][0] + 1.0 for p in row) for row in rows)
    rap.floor_plane((-2.0, -4.0), (span + 2.0, 9.0))
    centre = Vector((span / 2.0, 2.5, 0.4))
    az = rap.CAM_AZIMUTH
    el = math.radians(45)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam = rap.persp_camera(scene, centre + direction * 30.0, centre, lens=35.0)
    log("distance camera_to_centre=%.1f m lens=35" % (cam.location - centre).length)
    for name, objs in subjects.items():
        rap.prove_in_frame("distance %s" % name, scene, cam, rap.world_points(objs))
        rap.visible_share("distance %s" % name, scene, cam, objs)
    arr = rap.render(scene, os.path.join(OUT, "distance_raw.png"))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, "distance.png"))


def context_shot():
    scene = rap.reset_scene(1920, 1080, 1.2)
    W, D = 15, 10
    tile, _a, _n, _h = rap.import_glb(os.path.join(KIT_DIR, "floor_tile.glb"), "floor")
    bodies = [(o.data, o.matrix_world.copy()) for o in rap.meshes(tile)]
    for o in tile:
        bpy.data.objects.remove(o)
    for j in range(D):
        for i in range(W):
            for data, mw in bodies:
                dup = bpy.data.objects.new("Floor_%d_%d" % (i, j), data)
                dup.matrix_world = Matrix.Translation((i + 0.5, j + 0.5, 0.0)) @ mw
                scene.collection.objects.link(dup)
    for i in range(W):
        place_piece("wall", i + 0.5, D, "wall_%d" % i)
    # Blender (x, y): the piece's front (Godot +Z) faces Blender -y, toward the camera.
    layout = {
        "bar_counter": (2.0, 7.5),
        "restaurant_table": (5.0, 7.5),
        "restaurant_booth": (7.5, 7.5),
        "grab_and_go_stall": (10.5, 8.5),
        "pharmacy_shelf": (13.0, 9.5),
        "pharmacy_counter": (13.0, 7.0),
        "info_desk": (2.0, 3.0),
        "currency_exchange": (5.0, 3.0),
        "atm": (6.5, 3.5),
        "shower_cubicle": (8.5, 3.5),
        "nap_pod": (10.5, 3.5),
        "seat_row": (13.5, 2.5),
    }
    subjects = {}
    for piece, (x, y) in layout.items():
        subjects[piece] = place_piece(piece, x, y)
    people = (
        ("bar_male", "male", "bar_counter", "Mount_SitRoot_L", "sit_idle"),
        ("bar_staff", "female", "bar_counter", "Mount_Staff", "idle"),
        ("table_female", "female", "restaurant_table", "Mount_SitRoot_BR", "sit_idle"),
        ("table_male", "male", "restaurant_table", "Mount_SitRoot_FL", "sit_idle"),
        ("booth_male", "male", "restaurant_booth", "Mount_SitRoot_BL", "sit_idle"),
        ("pod_female", "female", "nap_pod", "Mount_SitRoot", "sit_idle"),
        ("info_customer", "male", "info_desk", "Mount_Order", "idle"),
        ("atm_user", "female", "atm", "Mount_Use", "idle"),
        ("pharmacy_customer", "female", "pharmacy_counter", "Mount_Order", "idle"),
        ("stall_customer", "male", "grab_and_go_stall", "Mount_Order", "idle"),
    )
    for name, who, piece, mount, clip in people:
        cobjs, acts, arm, _h = rap.add_character(who, rap.mount_xf(subjects[piece], mount))
        f0, f1 = rap.clip_range(acts, clip)
        rap.pose(arm, acts, clip, (f0 + f1) // 2)
        subjects[name] = cobjs
    target = Vector((7.5, 5.0, 0.6))
    direction = Vector((math.sin(math.radians(-20)) * math.cos(math.radians(55)),
                        -math.cos(math.radians(-20)) * math.cos(math.radians(55)), math.sin(math.radians(55))))
    cam = rap.persp_camera(scene, target + direction * 19.0, target, lens=26.0)
    for name, objs in subjects.items():
        rap.prove_in_frame("context %s" % name, scene, cam, rap.world_points(objs))
        rap.visible_share("context %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "context_raw.png"))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, "context.png"))


# ---------------------------------------------------------------- main

STRIPS = (
    # piece, mount, character, camera direction (Blender, toward the camera)
    ("bar_counter", "Mount_SitRoot_L", "female", (-1.0, 0.0, 0.15)),
    ("restaurant_table", "Mount_SitRoot_FR", "male", (1.0, 0.0, 0.15)),
    ("restaurant_booth", "Mount_SitRoot_BL", "female", (-0.5, -0.5, 0.7)),
    ("nap_pod", "Mount_SitRoot", "female", (0.5, -0.85, 0.3)),
)


def main():
    svc.register()
    for sub in ("six_axis", "thumbs", "sit", "door"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["fit", "six", "thumbs", "sit", "door", "distance", "context"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    fit_ok = None  # None: the fit stage did not run
    worsts = []
    if "fit" in stages:
        fit_ok = True
        runs = 0
        for piece in SITS:
            for mount, _pos, _yaw in sit_mounts(piece):
                for who in CHARS:
                    ok, worst = fit_check(piece, mount, who)
                    runs += 1
                    fit_ok = ok and fit_ok
                    if worst is None:
                        log("FIT worst_plate %s %s %s no contact in any frame" % (piece, mount, who))
                    else:
                        worsts.append((piece, mount, who, worst))
        log("FIT summary runs=%d fit_ok=%s" % (runs, fit_ok))
        # A deepest-contact plate for every seat and character that touched a part: the
        # frame whose part came closest to its limit.
        tiles = []
        for piece, mount, who, worst in worsts:
            log("FIT worst_plate %s %s %s part=%s depth=%.4f share_of_limit=%.2f at %s:%d"
                % (piece, mount, who, worst[1], worst[0], worst[0] / limit_of(worst[1]), worst[2], worst[3]))
            tiles += worst_plate(piece, mount, who, worst)
        if tiles:
            rap.save_array(rap.grid(tiles, 6), os.path.join(OUT, "sit", "worst_contact.png"))
    if "six" in stages:
        for piece in PIECES:
            six_axis(piece)
    if "thumbs" in stages:
        thumb_sheet([thumbnail(p) for p in PIECES])
    if "sit" in stages:
        for piece in SITS:
            sit_plates(piece)
        for piece, mount, who, view in STRIPS:
            for clip in ("sit_down", "stand_up"):
                strip(piece, mount, who, clip, view)
    if "door" in stages:
        door_plates()
    if "distance" in stages:
        distance_shot()
    if "context" in stages:
        context_shot()
    log("PLATES done stages=%s fit_ok=%s" % (stages, "not_run" if fit_ok is None else fit_ok))
    if fit_ok is False:
        print("FIT_FAIL a seated pose goes into the furniture beyond its limit", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
