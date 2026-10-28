"""Render the plates for the toilet kit and check the stall and sink fits numerically.

Run (headless, reproducible), after build_toilet_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_toilet_plates.py' [-- stage ...]

Stages: six, fit, walk, sink, door, distance, context (all when none is named).
Everything is written under tools/blender/out/toilet-kit/ (gitignored); nothing in
game/ is touched. The plates re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube;
- fit: render_services_plates.fit_check at the stall's Mount_Use for both characters
  (every frame of sit_down, sit_idle and stand_up, doors closed, two negative
  controls), then the same frames against the door leaves turned fully open;
- walk: each character walking the walk clip from Mount_Approach to Mount_Turn facing
  the toilet, turning round there and stepping back onto Mount_Use (idle pose; there
  is no turn or back-step clip), doors open, against every rebuilt stall part. Only
  the open leaves may be brushed, by at most WALK_BRUSH past their inner face; prints
  the largest hand reach from the path and the head height under the headrail;
- sink: both characters' idle frames at the sink's Mount_Use: no contact with any sink
  part, and the travel to contact along the facing kept 0.01-0.06 m for both.
  Hand-to-basin reach is not checked (no wash clip);
Every numeric stage rebuilds the piece with its builder and first checks it against
the written .glb (vertices and mounts within 0.2 mm).
- door/door_strip.png: the stall with its leaves at 0, 30, 60 and 90 degrees;
- distance_30m.png: both pieces and a person from the game camera at 30 m;
- context.png: a toilet room (three stalls in a row, the left one against a side wall,
  two sinks), a passenger seated in an open stall, one at an approach cell, one at a
  sink, from the game camera at 9 m.
Each plate proves its subjects are in frame and visible; on failure PROBE_INVALID and
exit 1. A Blender plate is not the in-engine look: the toon ramp and outline are judged
in a windowed Godot run.
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
import build_toilet_kit as toilet  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402
import render_services_plates as rsp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "toilet-kit")
rbp.OUT = OUT
PIECES = list(toilet.PIECES)
STALL, SINK = "toilet_stall", "toilet_sink"
CHARS = list(rap.CHARS)
LIMIT = rap.FIT_RIGID_M  # 0.01 m for every rigid part
# A walker's hand may pass the open leaf's inner face by this much (the 7.5 mm brush
# agreed in the Astra design review: 0.845 m between open leaves, hands swing to 0.43).
WALK_BRUSH = 0.01

log = rap.log
invalid = rap.invalid


def setup():
    """The kit tables: toilet swatches for the rebuilds, and the toilet builders where
    render_services_plates' fit check looks them up."""
    toilet.register()
    svc.PIECES.update(toilet.PIECES)


def gpos(xf):
    t = xf.translation
    return (t.x, t.z, -t.y)


# ---------------------------------------------------------------- rebuilt parts


def part_of(o):
    """A closed convex solid as (name, planes, BVH, half thickness), with the checks of
    rsp.convex_parts: every edge on two faces, no degenerate face, every vertex on or
    inside every face plane, not collapsed. The world matrix is a rigid turn and move
    (the builder bakes every scale into the mesh), so normals transform with it."""
    mw = o.matrix_world
    me = o.data
    verts = [mw @ v.co for v in me.vertices]
    edge_faces = {}
    for poly in me.polygons:
        for ek in poly.edge_keys:
            edge_faces[ek] = edge_faces.get(ek, 0) + 1
    open_edges = sum(1 for n in edge_faces.values() if n != 2)
    degenerate = sum(1 for p in me.polygons if p.area < 1e-9 or p.normal.length < 0.5)
    planes = []
    for poly in me.polygons:
        n = (mw.to_3x3() @ poly.normal).normalized()
        planes.append((n.x, n.y, n.z, n.dot(verts[poly.vertices[0]])))
    planes = np.array(planes)
    vco = np.array([tuple(v) for v in verts])
    outside = float((vco @ planes[:, :3].T - planes[:, 3]).max())
    half = float((planes[:, 3] - (vco @ planes[:, :3].T)).max(axis=0).min()) / 2.0
    if open_edges or degenerate or outside > rsp.CONVEX_EPS or half < 1e-3:
        invalid("part %s is not a closed convex solid (open edges %d, degenerate faces %d, vertex outside a "
                "plane by %.6f, half thickness %.5f)" % (o.name, open_edges, degenerate, outside, half))
    polys = [tuple(p.vertices) for p in me.polygons]
    return (rap.base_name(o.name), planes, BVHTree.FromPolygons(verts, polys), half)


def rebuilt(piece, open_frac=0.0):
    """The piece rebuilt with its builder at the origin, checked against the WRITTEN
    .glb (every vertex and every mount within 0.2 mm, doors closed), then the stall
    leaves turned open_frac of the way open: {"parts": [...], "mounts": {name: world
    matrix}}. A stale export or a builder edit not yet exported stops the run."""
    written, _a, _n, _h = rap.import_glb(rbp.glb(piece), "written_" + piece)
    for o in written:
        o.hide_render = True
    c = bpy.data.collections.new("REBUILD_%s_%.2f" % (piece, open_frac))
    bpy.context.scene.collection.children.link(c)
    root = bpy.data.objects.new("REBUILD_ROOT", None)
    c.objects.link(root)
    toilet.PIECES[piece][0](root, c)
    bpy.context.view_layer.update()
    err, n_w, n_r = rap.same_geometry(written, c)
    mounts = {o.name.split(".")[0]: o.matrix_world.copy() for o in c.objects if o.name.startswith("Mount_")}
    # Full transforms (position, facing, scale), element by element.
    m_err = max(max(abs(a - b) for ra, rb_ in zip(mounts[n], rap.mount_xf(written, n)) for a, b in zip(ra, rb_))
                for n in mounts)
    log("REBUILD %s vs_written vertices max_err=%.6f written=%d rebuilt=%d mounts=%s mount_err=%.6f"
        % (piece, err, n_w, n_r, sorted(mounts), m_err))
    if err > 2e-4 or m_err > 2e-4:
        invalid("%s: the rebuilt piece differs from the written .glb (%.5f m, mounts %.5f m)" % (piece, err, m_err))
    for o in written:
        bpy.data.objects.remove(o)
    for o in c.objects:
        for side in ("L", "R"):
            if o.type == "EMPTY" and o.name.startswith("Door_Leaf_Stall_" + side):
                o.rotation_euler = (0.0, 0.0, math.radians(toilet.DOOR_OPEN_DEG[side] * open_frac))
    bpy.context.view_layer.update()
    parts = []
    for o in c.objects:
        if o.type == "MESH":
            o.hide_render = True
            parts.append(part_of(o))
    return {"parts": parts, "mounts": mounts, "coll": c}


def depths(parts, cobjs):
    cb, verts, polys = rap.char_mesh(cobjs)
    return rsp.frame_depths(parts, cb, verts, polys), verts


def merge_worst(worst, found, tag):
    for name, (d, _p, kind) in found.items():
        if d > worst.get(name, (0.0,))[0]:
            worst[name] = (d, kind, tag)


def touched_bad(d, half, limit=LIMIT):
    """As rsp.fit_check: deeper than the limit fails, and so does any contact with a part
    no thicker than twice the limit, whose depth can never exceed it."""
    return d > limit or half <= limit


def report(label, worst, halves, limit=LIMIT):
    ok = True
    for name, (d, kind, tag) in sorted(worst.items(), key=lambda kv: -kv[1][0]):
        thin = halves[name] <= limit
        bad = touched_bad(d, halves[name], limit)
        ok = ok and not bad
        log("%s part=%s depth=%.4f via=%s at=%s half_thickness=%.4f limit=%.3f %s"
            % (label, name, d, kind, tag, halves[name], limit,
               "UNCERTIFIED_THIN" if thin else ("FAIL" if bad else "ok")))
    log("%s parts_touched=%d result=%s" % (label, len(worst), "ok" if ok else "FAIL"))
    return ok


# ---------------------------------------------------------------- fit


def fit_stage():
    ok = True
    for who in CHARS:
        good, worst = rsp.fit_check(STALL, "Mount_Use", who)
        log("FIT %s Mount_Use %s closed_doors result=%s worst=%s" % (STALL, who, "ok" if good else "FAIL", worst))
        ok = ok and good
    # The same frames against the leaves turned fully open.
    for who in CHARS:
        rap.reset_scene(64, 64)
        rb = rebuilt(STALL, 1.0)
        leaves = [p for p in rb["parts"] if p[0].startswith("Door_Leaf_Stall_")]
        if len(leaves) != 6:
            invalid("expected 6 leaf parts (panel and two knuckles per leaf), got %d" % len(leaves))
        xf = rb["mounts"]["Mount_Use"]
        cobjs, acts, arm, _h = rap.add_character(who, xf)
        worst, frames = {}, 0
        for clip in ("sit_down", "sit_idle", "stand_up"):
            f0, f1 = rap.clip_range(acts, clip)
            for f in range(f0, f1 + 1):
                rap.pose(arm, acts, clip, f)
                found, _v = depths(leaves, cobjs)
                merge_worst(worst, found, "%s:%d" % (clip, f))
                frames += 1
        # Control: the same body moved onto an open leaf must be caught.
        lx = -toilet.HINGE_X
        rap.pose(arm, acts, "sit_idle", sum(rap.clip_range(acts, "sit_idle")) // 2)
        _h.matrix_world = Matrix.Translation((lx, -0.70, 0.0)) @ xf
        bpy.context.view_layer.update()
        hit, _v = depths(leaves, cobjs)
        halves = {p[0]: p[3] for p in leaves}
        caught = any(touched_bad(d, halves[n]) for n, (d, _p, _k) in hit.items())
        log("FIT %s %s open_doors frames=%d control_body_on_open_leaf=%s caught=%s"
            % (STALL, who, frames, sorted((n, round(d, 4)) for n, (d, _p, _k) in hit.items()), caught))
        if not caught:
            invalid("the open-leaf control was not caught")
        ok = report("FIT %s %s open_doors" % (STALL, who), worst, halves) and ok
    if not ok:
        invalid("the stall's seated fit failed")


# ---------------------------------------------------------------- walk


def walk_stage():
    """Approach -> Mount_Turn walking (every walk frame at every 5 cm), the turn in
    place at Mount_Turn (15-degree steps, idle frames), and the step back onto
    Mount_Use facing out (idle pose slid back in 5 cm steps: there is no back-step
    clip). Doors open. Every other part is held to report()'s rule (10 mm on a rigid
    part, any contact on a thin one). The open leaf panels may be brushed by a reach
    no more than WALK_BRUSH past their inner face (the doorway plane, not penetration
    depth, which saturates at the 7.5 mm half thickness)."""
    ok = True
    leaf_face = toilet.HINGE_X - toilet.LEAF_T / 2.0
    for who in CHARS:
        rap.reset_scene(64, 64)
        rb = rebuilt(STALL, 1.0)
        halves = {p[0]: p[3] for p in rb["parts"]}
        start = rb["mounts"]["Mount_Approach"].translation.copy()
        mid = rb["mounts"]["Mount_Turn"].translation.copy()
        end = rb["mounts"]["Mount_Use"].translation.copy()
        cobjs, acts, arm, hold = rap.add_character(who, rb["mounts"]["Mount_Approach"])
        f0, f1 = rap.clip_range(acts, "walk")
        i0, i1 = rap.clip_range(acts, "idle")
        # Root motion: the body's mean y over the clip at a fixed holder.
        drift = []
        for f in (f0, (f0 + f1) // 2, f1):
            rap.pose(arm, acts, "walk", f)
            drift.append(float(rap.char_mesh(cobjs)[1][:, 1].mean()))
        log("WALK %s clip frames=%d-%d body_mean_y=%s (in-place if near constant)"
            % (who, f0, f1, ["%.3f" % d for d in drift]))
        if max(drift) - min(drift) > 0.15:
            invalid("%s walk clip carries root motion (%.3f m); the walk check assumes in-place"
                    % (who, max(drift) - min(drift)))
        poses = []  # (phase, position, yaw radians about Blender Z, clip, frame)
        back = math.pi  # facing the toilet: Godot -Z (Blender +y)
        steps = int(round((start - mid).length / 0.05))
        for i in range(steps + 1):
            for f in range(f0, f1 + 1):
                poses.append(("walk", start.lerp(mid, i / steps), back, "walk", f))
        for k in range(13):
            for f in range(i0, i1 + 1, 15):
                poses.append(("turn", mid, back * (1.0 - k / 12.0), "idle", f))
        steps = int(round((mid - end).length / 0.05))
        for i in range(steps + 1):
            for f in range(i0, i1 + 1, 15):
                poses.append(("back", mid.lerp(end, i / steps), 0.0, "idle", f))
        worst, reach, head, brush_reach = {}, 0.0, 0.0, 0.0
        for phase, p, yaw, clip, f in poses:
            hold.matrix_world = Matrix.Translation(p) @ Matrix.Rotation(yaw, 4, "Z")
            rap.pose(arm, acts, clip, f)
            found, verts = depths(rb["parts"], cobjs)
            lateral = float(np.abs(verts[:, 0] - p.x).max())
            merge_worst(worst, found, "%s z=%.2f %s:%d" % (phase, -p.y, clip, f))
            if any(name.startswith("Door_Leaf_Stall_") for name in found):
                brush_reach = max(brush_reach, lateral)
            reach = max(reach, lateral)
            head = max(head, float(verts[:, 2].max()))
        brush = max(0.0, brush_reach - leaf_face)
        log("WALK %s poses=%d (walk %.2f -> %.2f, turn at %.2f, back to %.2f) max_reach_from_path=%.4f "
            "open_leaf_face=%.4f partition_face=%.3f leaf_brush_past_face=%.4f allowed=%.3f head_top=%.3f "
            "headrail_underside=%.2f" % (who, len(poses), -start.y, -mid.y, -mid.y, -end.y, reach, leaf_face,
                                         toilet.PARTITION_IN, brush, WALK_BRUSH, head, toilet.RAIL_Y[0]))
        unexpected = {k: v for k, v in worst.items() if not (k.startswith("Door_Leaf_Stall_") and "Panel" in k)}
        ok = report("WALK %s other_parts" % who, unexpected, halves) and ok
        for name, (d, kind, tag) in worst.items():
            if name not in unexpected:
                log("WALK %s leaf_brush part=%s depth=%.4f at=%s brush_past_face=%.4f %s"
                    % (who, name, d, tag, brush, "ok" if brush <= WALK_BRUSH else "FAIL"))
        ok = ok and brush <= WALK_BRUSH and head < toilet.RAIL_Y[0]
    if not ok:
        invalid("the walk in, turn and step back touch the stall beyond the agreed leaf brush")


# ---------------------------------------------------------------- sink


def sink_stage():
    """Both characters' idle frames at the sink's Mount_Use: no contact with any sink
    part, and the sampled vertex travel (the shortest ray from a body vertex along the
    facing to any sink part, every fifth frame) kept 0.01-0.06 m for both. It can miss
    an edge or face that touches first, so it is a sampled clearance, not an exact
    sweep. The band is the Mount_Use z range giving that travel for both."""
    bands, clear = [], True
    for who in CHARS:
        rap.reset_scene(64, 64)
        rb = rebuilt(SINK)
        halves = {p[0]: p[3] for p in rb["parts"]}
        xf = rb["mounts"]["Mount_Use"]
        cobjs, acts, arm, _h = rap.add_character(who, xf)
        verts_all, polys_all = [], []
        for o in rb["coll"].objects:
            if o.type == "MESH":
                base = len(verts_all)
                verts_all += [o.matrix_world @ v.co for v in o.data.vertices]
                polys_all += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
        bvh = BVHTree.FromPolygons(verts_all, polys_all)
        # The mount's Godot +Z (Blender -y in its own frame), in Blender world axes.
        facing = (xf.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
        f0, f1 = rap.clip_range(acts, "idle")
        worst, travel, hit_at = {}, 9.0, None
        for f in range(f0, f1 + 1):
            rap.pose(arm, acts, "idle", f)
            found, verts = depths(rb["parts"], cobjs)
            merge_worst(worst, found, "idle:%d" % f)
            if (f - f0) % 5:
                continue
            for v in verts:
                loc, _n, _i, dist = bvh.ray_cast(Vector(v), facing, 0.5)
                if loc is not None and dist < travel:
                    travel, hit_at = dist, (f, tuple(round(c, 3) for c in v), tuple(round(c, 3) for c in loc))
        if hit_at is None:
            invalid("%s at the sink: no ray from the body reaches the sink within 0.5 m" % who)
        z_now = gpos(xf)[2]
        # Moving the root toward the sink by dz cuts the travel by dz.
        lo, hi = z_now - travel + 0.01, z_now - travel + 0.06
        bands.append((lo, hi))
        log("SINK %s idle frames=%d facing_blender=(%.2f, %.2f, %.2f) travel_to_contact=%.4f at frame %d body %s "
            "hits %s mount_z=%.3f band_for_0.01-0.06=[%.3f, %.3f]"
            % (who, f1 - f0 + 1, facing.x, facing.y, facing.z, travel, hit_at[0], hit_at[1], hit_at[2], z_now,
               lo, hi))
        clear = report("SINK %s" % who, worst, halves) and clear
    if not clear:
        invalid("a standing passenger at the sink touches it")
    lo, hi = max(b[0] for b in bands), min(b[1] for b in bands)
    z = toilet.SINK_USE_Z
    log("SINK band_both=[%.3f, %.3f] mount_z=%.3f inside=%s" % (lo, hi, z, lo <= z <= hi))
    if lo > hi or not lo <= z <= hi:
        invalid("the sink's Mount_Use z %.3f is outside the band [%.3f, %.3f]" % (z, lo, hi))


# ---------------------------------------------------------------- door strip


def door_stage():
    tiles = []
    for deg in (0, 30, 60, 90):
        scene = rap.reset_scene(640, 640, 1.5)
        objs = rbp.place(STALL, 0.0, 0.0, label="stall_%d" % deg)
        for o in objs:
            for side in ("L", "R"):
                if o.type == "EMPTY" and rap.base_name(o.name) == "Door_Leaf_Stall_" + side:
                    o.matrix_basis = o.matrix_basis @ Matrix.Rotation(
                        math.radians(toilet.DOOR_OPEN_DEG[side] * deg / 90.0), 4, "Z")
        bpy.context.view_layer.update()
        cube = rap.cube((1.3, -0.6, 0.5))
        target = Vector((0.3, 0.0, 1.0))
        az, el = math.radians(-25.0), math.radians(40.0)
        d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
        cam = rap.persp_camera(scene, target + d * 5.0, target, lens=35.0)
        rap.prove_in_frame("door %d stall" % deg, scene, cam, rap.world_points(objs))
        rap.prove_in_frame("door %d cube" % deg, scene, cam, rap.world_points([cube]))
        rap.visible_share("door %d stall" % deg, scene, cam, objs)
        tiles.append(rap.over(rap.render(scene, os.path.join(OUT, "door", "door_%d.png" % deg)), rap.BACKDROP))
    rap.save_array(rap.grid(tiles, 4), os.path.join(OUT, "door", "door_strip.png"))


# ---------------------------------------------------------------- distance + context


def distance_stage():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {STALL: rbp.place(STALL, 0.5, 0.0), SINK: rbp.place(SINK, 2.5, 0.0)}
    subjects["male"] = rbp.person("male", 4.0, 0.0, 0.0, "scale")
    rap.floor_plane((-2.0, -4.0), (6.0, 4.0))
    cam = rbp.game_camera(scene, Vector((2.2, 0.0, 0.6)), 30.0, -30.0)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_30m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_30m %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "distance_30m_raw.png"))
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, "distance_30m.png"))


def open_doors(objs):
    for o in objs:
        for side in ("L", "R"):
            if o.type == "EMPTY" and rap.base_name(o.name) == "Door_Leaf_Stall_" + side:
                o.matrix_basis = o.matrix_basis @ Matrix.Rotation(math.radians(toilet.DOOR_OPEN_DEG[side]), 4, "Z")
    bpy.context.view_layer.update()


def at_mount(who, objs, mount, clip):
    cobjs, acts, arm, _h = rap.add_character(who, rap.mount_xf(objs, mount))
    f0, f1 = rap.clip_range(acts, clip)
    rap.pose(arm, acts, clip, (f0 + f1) // 2)
    return cobjs


def context_stage():
    """A 5 x 4 cell room, Blender x 0..5, y 0..4, back wall at y 4, side walls at x 0
    and 5; piece fronts face Blender -y, toward the camera."""
    scene = rap.reset_scene(1920, 1080, 1.2)
    rbp.floor_tiles(0, 5, 0, 4)
    for i in range(5):
        rbp.place("wall", i + 0.5, 4.0, label="wall_back_%d" % i)
    for j in range(4):
        rbp.place("wall", 0.0, j + 0.5, 90.0, label="wall_left_%d" % j)
        rbp.place("wall", 5.0, j + 0.5, 90.0, label="wall_right_%d" % j)
    for x, y in ((0.0, 4.0), (5.0, 4.0), (0.0, 0.0), (5.0, 0.0)):
        rbp.place("wall_post", x, y, label="post_%.0f_%.0f" % (x, y))
    subjects = {}
    for i, x in enumerate((0.5, 1.5, 2.5)):
        subjects["stall_%d" % i] = rbp.place(STALL, x, 3.0, label="stall_%d" % i)
    for i, x in enumerate((3.5, 4.5)):
        subjects["sink_%d" % i] = rbp.place(SINK, x, 3.5, label="sink_%d" % i)
    open_doors(subjects["stall_0"])
    open_doors(subjects["stall_2"])
    subjects["sitter"] = at_mount("female", subjects["stall_0"], "Mount_Use", "sit_idle")
    subjects["approacher"] = at_mount("male", subjects["stall_2"], "Mount_Approach", "idle")
    subjects["washer"] = at_mount("female", subjects["sink_1"], "Mount_Use", "idle")
    cube = rap.cube((4.3, 0.9, 0.5))
    cam = rbp.game_camera(scene, Vector((2.5, 2.4, 0.8)), 9.0, -20.0)
    rap.prove_in_frame("context cube", scene, cam, rap.world_points([cube]))
    for name, objs in subjects.items():
        rbp.prove("context %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "context_raw.png"))
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, "context.png"))


# ---------------------------------------------------------------- main


def main():
    setup()
    for sub in ("six_axis", "door"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "fit", "walk", "sink", "door", "distance", "context"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        for piece in PIECES:
            rbp.six_axis(piece)
    if "fit" in stages:
        fit_stage()
    if "walk" in stages:
        walk_stage()
    if "sink" in stages:
        sink_stage()
    if "door" in stages:
        door_stage()
    if "distance" in stages:
        distance_stage()
    if "context" in stages:
        context_stage()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
