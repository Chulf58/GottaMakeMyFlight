"""Render the Blender plates of the airside props (board 4c08b8e5).

Run (headless, reproducible), after build_airside_props.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\render_airside_plates.py' [-- stage ...]

Stages (all when none is named): six, glyphs, stand, pushback, sheet. Everything
is written under tools/blender/out/airside-props/ (gitignored); nothing in game/ is
touched. The plates re-import the WRITTEN .glb files from game/assets/airside/props/
and the pack's plane 05 from game/assets/planes/tp_plane_05a.glb:
- six_axis/<piece>.png: six orthographic views at one scale, true scale, a 1 m cube;
- glyphs.png: the sign from the front with each letter A-E on both panels and both
  arrows, plus its back;
- stand.png: plane 05 parked at a medium stand (stand_placement.gd geometry: wall line
  z 0, exit x 0, stand point (-3.5, 0, -16.9) Godot plus plane_view.gd model_offset 1.7 m, nose +z), the bridge docked
  at its measured door by the build script's pose math, a taxi sign by the lead-in,
  a grey placeholder terminal, perspective from about 45 m;
- pushback.png: pushback start: the towbarless tug cradling plane 05's nose wheel at
  the stand, the bridge parked; pushback_tug.png and pushback_tug_side.png close up
  (the side view is level, to show the gap under the fuselage). place_tug() checks
  the reach past the nose (limit 2.0 m), the wall gap and a BVH overlap with the
  plane (with a lifted-tug positive control);
- contact_sheet.png: every plate above, downscaled.
Each plate proves its subjects are in frame (every vertex inside the margin) and
visible (camera rays reach the subject first); on failure PROBE_INVALID and exit 1.
The stand stage prints the Mount_Door to door-sill error of the docked nose-loader.
These are Blender plates: the in-engine look needs a windowed Godot render.
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
sys.path.insert(0, os.path.join(HERE, "..", "interior"))
import build_airside_props as bp  # noqa: E402
import render_activities_plates as rap  # noqa: E402

kit = bp.kit
OUT = os.path.join(kit.REPO, "tools", "blender", "out", "airside-props")
PROPS = os.path.join(kit.REPO, "game", "assets", "airside", "props")
PLANE = os.path.join(kit.REPO, "game", "assets", "planes", "tp_plane_05a.glb")
MARGIN = rap.MARGIN
BACKDROP = rap.BACKDROP
log = rap.log
invalid = rap.invalid
TERMINAL_RGB = (0.80, 0.78, 0.74)
MARK_RGB = (0.85, 0.15, 0.15)
# stand_placement.gd: NOSE_GAP_M 2.2 + NOSE_M 14.7, DOOR_SIDE_M 3.5; plane_view.gd
# then shifts the model by model_offset (0, 0, 1.7), so 05's nose sits 2.21 m off the wall.
MODEL_OFFSET_Z = 1.7
STAND_ORIGIN_G = (-3.5, 0.0, -(2.2 + 14.7) + MODEL_OFFSET_Z)


def g2b(x, y, z):
    return Vector((x, -z, y))


def by_name(objs):
    return {rap.base_name(o.name): o for o in objs}


def place(path, label, at_g=(0.0, 0.0, 0.0), yaw_deg=0.0):
    xf = Matrix.Translation(g2b(*at_g)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    objs, _a, names, holder = rap.import_glb(path, label, xf)
    log("%s imported materials=%s objects=%d" % (label, sorted(names), len(objs)))
    return objs, holder


def prop(piece):
    return os.path.join(PROPS, piece + ".glb")


def show_glyphs(objs, keep):
    """Hide every sign glyph except those named in keep; returns the visible objects."""
    vis = []
    for o in objs:
        n = rap.base_name(o.name)
        if n.startswith("Glyph_") and n.endswith("_Mesh"):
            on = n[:-5] in keep
            o.hide_render = not on
            if on:
                vis.append(o)
        else:
            vis.append(o)
    return vis


def box_obj(name, lo, hi, rgb):
    """A flat-coloured placeholder box between Blender corners lo and hi."""
    lo, hi = Vector(lo), Vector(hi)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lo + hi) / 2.0)
    ob = bpy.context.active_object
    ob.scale = hi - lo
    ob.name = name
    ob.data.materials.append(rap.flat(rgb))
    bpy.context.view_layer.update()
    return ob


# ---------------------------------------------------------------- bridge pose


def set_bridge(o, slide, height, yaw, extend):
    """Set the nose-loader's joints as JetBridgePose.apply() does."""
    for name in ("Walk_Slide", "Stair_Rise", "Curtain_Low", "Floor_Lift", "Curtain_High", "Cab_Yaw",
                 "Bellows_Extend"):
        o[name].rotation_mode = "XYZ"
    o["Walk_Slide"].location = (0.0, -slide, 0.0)
    o["Stair_Rise"].scale = (1.0, 1.0, height)
    o["Curtain_Low"].scale = (1.0, 1.0, max(height - bp.CURTAIN_GAP, bp.CURTAIN_MIN))
    o["Floor_Lift"].location = (0.0, 0.0, height)
    over = bp.BOX_TOP - bp.SKIN_T - height - (bp.CAB_IN + bp.CURTAIN_GAP)
    o["Curtain_High"].scale = (1.0, 1.0, max(over, bp.CURTAIN_MIN))
    o["Cab_Yaw"].rotation_euler = (0.0, 0.0, yaw)
    o["Bellows_Extend"].location = (0.0, -extend, 0.0)
    bpy.context.view_layer.update()


def park_bridge(o):
    """The parked pose (JetBridgePose.parked())."""
    set_bridge(o, 0.0, bp.H_PARK, math.pi / 2.0, bp.E_MIN)


def pose_bridge(o, holder, p_world, n_world, label):
    """JetBridgePose.solve(): slide, lift, turn and extend the nose-loader so
    Mount_Door lands on p_world with the cab facing -n_world. Returns (slide,
    height, yaw, extend, error)."""
    inv = holder.matrix_world.inverted()
    pl = inv @ Vector(p_world)
    nl = inv.to_3x3() @ Vector(n_world)
    # Blender local -> Godot local.
    P = (pl.x, pl.z, -pl.y)
    f = (-nl.x, 0.0, nl.y)
    flen = math.hypot(f[0], f[2])
    f = (f[0] / flen, 0.0, f[2] / flen)
    yaw = math.atan2(f[0], f[2])
    extend = P[0] / f[0] - bp.MOUNT_DOOR_Z
    slide = P[2] - f[2] * (bp.MOUNT_DOOR_Z + extend) - bp.CAB_Z
    height = P[1]
    set_bridge(o, slide, height, yaw, extend)
    err = (o["Mount_Door"].matrix_world.translation - Vector(p_world)).length
    log("POSE %s slide=%.3f (0..%.2f) height=%.3f (%.2f..%.2f) cab_yaw=%.1f extend=%.3f mount_err=%.4f"
        % (label, slide, bp.SLIDE_MAX, height, bp.H_MIN, bp.H_MAX, math.degrees(yaw), extend, err))
    if err > 0.005:
        invalid("%s: Mount_Door is %.4f m off the target" % (label, err))
    if (not -1e-4 <= slide <= bp.SLIDE_MAX + 1e-4 or not bp.H_MIN - 1e-4 <= height <= bp.H_MAX + 1e-4
            or not bp.E_MIN - 1e-4 <= extend <= bp.E_MAX + 1e-4):
        invalid("%s: pose out of reach (slide %.3f, height %.3f, extend %.3f)" % (label, slide, height, extend))
    return slide, height, yaw, extend, err


# ---------------------------------------------------------------- six-axis


def six_axis(piece, keep=None):
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs, _h = place(prop(piece), piece)
    if keep is not None:
        objs = show_glyphs(objs, keep)
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
    log("%s six_axis size_m godot=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (piece, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y, scale, rap.SIX_PX / scale))
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
    out = os.path.join(OUT, "six_axis", piece + ".png")
    rap.save_array(rap.grid(tiles, 3), out)
    return out

# ---------------------------------------------------------------- glyphs


def glyphs():
    scene = rap.reset_scene(640, 360, 1.2)
    tiles = []
    combos = [("A", "A", "L"), ("B", "B", "R"), ("C", "C", "L"), ("D", "D", "R"), ("E", "E", "L")]
    objs, _h = place(prop("taxi_sign"), "taxi_sign")
    for view, (loc_ch, dir_ch, arrow) in [("front", c) for c in combos] + [("back", ("C", "C", "L"))]:
        keep = {"Glyph_Loc_" + loc_ch, "Glyph_Dir_" + dir_ch, "Glyph_Arrow_" + arrow}
        vis = show_glyphs(objs, keep)
        d = (0.0, -1.0, 0.0) if view == "front" else (0.0, 1.0, 0.0)
        pts = rap.world_points(vis)
        cam = rap.ortho_camera(scene, rap.look_rot(d, (0.0, 0.0, 1.0)), pts, 2.4 / (1.0 - 2 * MARGIN - 0.04))
        label = "glyphs %s loc=%s dir=%s arrow=%s" % (view, loc_ch, dir_ch, arrow)
        rap.prove_in_frame(label, scene, cam, pts)
        tiles.append(rap.over(rap.render(scene, os.path.join(OUT, "glyphs", "%s_%s%s%s.png"
                                                             % (view, loc_ch, dir_ch, arrow))), BACKDROP))
        bpy.data.objects.remove(cam)
    out = os.path.join(OUT, "glyphs.png")
    rap.save_array(rap.grid(tiles, 2), out)
    return out


# ---------------------------------------------------------------- stand scenes


def world_bvh(objs):
    """One BVH over the world-space polygons of the mesh objects."""
    verts, polys = [], []
    for o in rap.meshes(objs):
        mw = o.matrix_world
        base = len(verts)
        verts.extend(mw @ v.co for v in o.data.vertices)
        polys.extend([base + i for i in p.vertices] for p in o.data.polygons)
    return BVHTree.FromPolygons(verts, polys)


def place_tug(po, plane, pushed_m):
    """The towbarless tug with its origin (Mount_NoseGear) on plane 05's nose wheel
    ground contact, facing the plane's way. Checks, on the placed meshes: the mount on
    the contact point, how far the tug reaches past the nose and toward the wall, a
    BVH overlap test against every plane mesh (with a positive control: the same tug
    lifted 1 m must overlap), and the vertical gap under the fuselage."""
    wheel = rap.world_points([po["TP_Plane_05A_Wheel_F"]])
    axle = Vector(((wheel[:, 0].min() + wheel[:, 0].max()) / 2, (wheel[:, 1].min() + wheel[:, 1].max()) / 2,
                   (wheel[:, 2].min() + wheel[:, 2].max()) / 2))
    r = (wheel[:, 2].max() - wheel[:, 2].min()) / 2.0
    contact = Vector((axle.x, axle.y, 0.0))
    tug, holder = place(prop("pushback_tug"), "pushback_tug", (contact.x, 0.0, -contact.y), 0.0)
    to = by_name(tug)
    err = (to["Mount_NoseGear"].matrix_world.translation - contact).length
    plane_pts = rap.world_points(plane)
    tug_pts = rap.world_points(tug)
    nose_g = float(-plane_pts[:, 1].min())
    front_g = float(-tug_pts[:, 1].min())
    plane_origin_g = STAND_ORIGIN_G[2] - pushed_m
    past = front_g - nose_g
    log("TUG wheel_x=[%.3f, %.3f] wheel_godot_z=[%.3f, %.3f]" % (wheel[:, 0].min(), wheel[:, 0].max(),
                                                               -wheel[:, 1].max(), -wheel[:, 1].min()))
    log("TUG axle_godot=(%.2f, %.3f, %.2f) wheel_r=%.3f mount_err=%.4f nose_godot_z=%.3f (%.2f ahead of the plane "
        "origin, axle %.2f ahead) tug_front_godot_z=%.3f past_nose=%.3f (limit 2.0) wall_gap=%.3f (the wall line is z 0)"
        % (axle.x, axle.z, -axle.y, r, err, nose_g, nose_g - plane_origin_g, -axle.y - plane_origin_g, front_g, past,
           -front_g))
    if err > 0.005:
        invalid("tug: Mount_NoseGear is %.4f m off the nose wheel contact" % err)
    if past > 2.0:
        invalid("tug: reaches %.3f m past the nose (limit 2.0)" % past)
    if front_g > 0.0:
        invalid("tug: reaches %.3f m into the terminal" % front_g)
    tug_bvh = world_bvh(tug)
    hits = {}
    for o in rap.meshes(plane):
        n = len(tug_bvh.overlap(world_bvh([o])))
        if n:
            hits[rap.base_name(o.name)] = n
    holder.location.z += 1.0
    bpy.context.view_layer.update()
    control = len(world_bvh(tug).overlap(world_bvh(plane)))
    holder.location.z -= 1.0
    bpy.context.view_layer.update()
    # The vertical gap: plane vertices over the tug's footprint (the nose gear, which
    # stands in the slot, left out) against the tug's height under the plane's length.
    lo, hi = tug_pts.min(axis=0), tug_pts.max(axis=0)
    body = [o for o in rap.meshes(plane) if not any(k in o.name for k in ("Wheel_F", "Landing_Gear_F", "Hatch_"))]
    bp_pts = rap.world_points(body)
    over = bp_pts[(bp_pts[:, 0] > lo[0]) & (bp_pts[:, 0] < hi[0]) & (bp_pts[:, 1] > lo[1]) & (bp_pts[:, 1] < hi[1])]
    under = tug_pts[tug_pts[:, 1] > plane_pts[:, 1].min()]
    fus_min = float(over[:, 2].min()) if len(over) else float("nan")
    doors = [o for o in rap.meshes(plane) if "Hatch_" in o.name]
    dp = rap.world_points(doors)
    dp = dp[(dp[:, 0] > lo[0]) & (dp[:, 0] < hi[0]) & (dp[:, 1] > lo[1]) & (dp[:, 1] < hi[1])]
    door_min = float(dp[:, 2].min()) if len(dp) else float("nan")
    tug_max = float(under[:, 2].max()) if len(under) else float("nan")
    log("TUG overlap_with_plane=%s control_lifted_1m_overlaps=%d fuselage_min_height_over_footprint=%.3f "
        "tug_max_height_under_plane=%.3f vertical_gap=%.3f gear_door_min_height_over_footprint=%.3f gap_to_doors=%.3f"
        % (hits or "none", control, fus_min, tug_max, fus_min - tug_max, door_min, door_min - tug_max))
    if control == 0:
        invalid("tug: the overlap test found nothing even with the tug lifted into the fuselage")
    if hits:
        invalid("tug: intersects the plane %s" % hits)
    return tug


def stand_scene(pushed_m, with_tug, docked):
    scene = rap.reset_scene(1800, 1100, 1.2)
    ox, oy, oz = STAND_ORIGIN_G
    plane, _ph = place(PLANE, "plane_05", (ox, oy, oz - pushed_m))
    po = by_name(plane)
    door = rap.world_points([po["TP_Plane_05A_Door"]])
    # Blender: +x is port (Godot +x), -y is forward (Godot +z).
    sill_z = float(door[:, 2].min())
    skin_x = float(door[:, 0].max())
    mid_y = float((door[:, 1].min() + door[:, 1].max()) / 2.0)
    log("DOOR plane_05 pushed=%.1f sill=%.3f skin_x=%.3f mid_godot_z=%.3f height=%.3f length=%.3f"
        % (pushed_m, sill_z, skin_x, -mid_y, door[:, 2].max() - sill_z, door[:, 1].max() - door[:, 1].min()))
    # A grey placeholder terminal behind the wall line (Godot z 0 .. 14, 5.2 m tall).
    term = box_obj("Terminal", g2b(-26.0, 0.0, 14.0), g2b(26.0, 5.2, 0.0), TERMINAL_RGB)
    rap.floor_plane((-40.0, -14.0), (40.0, 62.0))
    subjects = {"plane_05": plane}
    # The nose-loader as JetBridgePose.root_for() places it (board 0adca5c6): rooted on
    # the exit door's sill (x 0 on the wall line), turned 180 degrees.
    p_door = Vector((skin_x, mid_y, sill_z))
    bridge, bh = place(prop("jet_bridge"), "jet_bridge", (0.0, 0.0, 0.0), 180.0)
    bo = by_name(bridge)
    if docked:
        pose_bridge(bo, bh, p_door, Vector((1.0, 0.0, 0.0)), "stand plane_05")
    else:
        park_bridge(bo)
    log("BRIDGE root_godot=(0, 0, 0) docked=%s" % docked)
    subjects["jet_bridge"] = bridge
    # The taxi sign at the stand's lead-in, north of the bridge, facing the camera side.
    sign, _sh = place(prop("taxi_sign"), "taxi_sign", (13.0, 0.0, -26.0), 125.0)
    subjects["taxi_sign"] = show_glyphs(sign, {"Glyph_Loc_B", "Glyph_Dir_C", "Glyph_Arrow_R"})
    if with_tug:
        subjects["pushback_tug"] = place_tug(po, plane, pushed_m)
    return scene, subjects, term


def shoot(name, scene, subjects, target_g, az_deg, el_deg, dist, lens=35.0, need=0.10):
    t = g2b(*target_g)
    az, el = math.radians(az_deg), math.radians(el_deg)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam = rap.persp_camera(scene, t + direction * dist, t, lens=lens)
    log("%s camera_to_target=%.1f m lens=%.0f" % (name, dist, lens))
    for label, objs in subjects.items():
        vis = [o for o in objs if not o.hide_render]
        rap.prove_in_frame("%s %s" % (name, label), scene, cam, rap.world_points(vis))
        rap.visible_share("%s %s" % (name, label), scene, cam, vis, need=need)
    out = os.path.join(OUT, name + ".png")
    rap.save_array(rap.over(rap.render(scene, os.path.join(OUT, name + "_raw.png")), BACKDROP), out)
    bpy.data.objects.remove(cam)
    return out


def stand():
    scene, subjects, _t = stand_scene(0.0, False, True)
    outs = [shoot("stand", scene, subjects, (-1.0, 1.5, -14.0), 125.0, 40.0, 60.0)]
    # Closer distance shots per prop, the plane in frame beside it.
    outs.append(shoot("stand_bridge", scene, {"jet_bridge": subjects["jet_bridge"]}, (3.0, 2.5, -7.0), 110.0, 30.0,
                      28.0))
    outs.append(shoot("stand_sign", scene, {"taxi_sign": subjects["taxi_sign"]}, (13.0, 0.6, -26.0), 145.0, 25.0,
                      9.0, need=0.10))
    return outs


def pushback():
    scene, subjects, _t = stand_scene(0.0, True, False)
    keep = {k: v for k, v in subjects.items() if k in ("plane_05", "pushback_tug")}
    outs = [shoot("pushback", scene, keep, (-2.0, 1.0, -12.0), 125.0, 40.0, 62.0)]
    # Close: the tug under the nose, the terminal wall behind it.
    outs.append(shoot("pushback_tug", scene, {"pushback_tug": subjects["pushback_tug"]}, (-3.5, 0.8, -4.5), 125.0,
                      28.0, 14.0))
    outs.append(shoot("pushback_tug_side", scene, {"pushback_tug": subjects["pushback_tug"]}, (-3.5, 0.9, -4.5),
                      90.0, 6.0, 13.0, need=0.05))
    return outs


def sheet(paths):
    tiles = []
    for p in paths:
        img = bpy.data.images.load(p)
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        bpy.data.images.remove(img)
        arr = px.reshape(h, w, 4)
        f = max(1, int(math.ceil(max(w / 900.0, h / 560.0))))
        tiles.append(rap.downscale(arr, f))
    th = max(t.shape[0] for t in tiles)
    tw = max(t.shape[1] for t in tiles)
    padded = []
    for t in tiles:
        canvas = np.empty((th, tw, 4), dtype=np.float32)
        canvas[:, :] = (0.08, 0.08, 0.09, 1.0)
        canvas[th - t.shape[0]:, :t.shape[1]] = t
        padded.append(canvas)
    rap.save_array(rap.grid(padded, 3), os.path.join(OUT, "contact_sheet.png"))


def main():
    for sub in ("six_axis", "glyphs"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "glyphs", "stand", "pushback", "sheet"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    made = []
    if "six" in stages:
        made.append(six_axis("jet_bridge"))
        made.append(six_axis("pushback_tug"))
        made.append(six_axis("taxi_sign", {"Glyph_Loc_A", "Glyph_Dir_B", "Glyph_Arrow_R"}))
    if "glyphs" in stages:
        made.append(glyphs())
    if "stand" in stages:
        made.extend(stand())
    if "pushback" in stages:
        made.extend(pushback())
    if "sheet" in stages:
        names = ["six_axis/jet_bridge.png", "six_axis/pushback_tug.png", "six_axis/taxi_sign.png",
                 "glyphs.png", "stand.png", "stand_bridge.png", "stand_sign.png", "pushback.png", "pushback_tug.png", "pushback_tug_side.png"]
        paths = [os.path.join(OUT, n) for n in names if os.path.exists(os.path.join(OUT, n))]
        sheet(paths)
    log("PLATES done stages=%s made=%d" % (stages, len(made)))


if __name__ == "__main__":
    main()
