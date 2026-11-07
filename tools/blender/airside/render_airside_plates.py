"""Render the Blender plates of the airside props (board 4c08b8e5).

Run (headless, reproducible), after build_airside_props.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\render_airside_plates.py' [-- stage ...]

Stages (all when none is named): six, poses, glyphs, stand, pushback, sheet. Everything
is written under tools/blender/out/airside-props/ (gitignored); nothing in game/ is
touched. The plates re-import the WRITTEN .glb files from game/assets/airside/props/
and the pack's plane 05 from game/assets/planes/tp_plane_05a.glb:
- six_axis/<piece>.png: six orthographic views at one scale, true scale, a 1 m cube;
- poses.png: the bridge from the side at rest, at the medium sill (1.59 m) and at the
  large sills (2.4 m, 2.9 m), each target marked by a red bar, with a 1 m cube;
- glyphs.png: the sign from the front with each letter A-E on both panels and both
  arrows, plus its back;
- stand.png: plane 05 parked at a medium stand (stand_placement.gd geometry: wall line
  z 0, exit x 0, plane origin at (-3.5, 0, -16.9) Godot, nose +z), the bridge docked
  at its measured door by the build script's pose math, a taxi sign by the lead-in,
  a grey placeholder terminal, perspective from about 45 m;
- pushback.png: the plane pushed back 12 m with the tug's towing head on its nose
  wheel, the bridge parked, perspective;
- contact_sheet.png: every plate above, downscaled.
Each plate proves its subjects are in frame (every vertex inside the margin) and
visible (camera rays reach the subject first); on failure PROBE_INVALID and exit 1.
The pose stages print the Mount_Door to door-sill error and the bogie height.
These are Blender plates: the in-engine look needs a windowed Godot render.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

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
# stand_placement.gd: NOSE_GAP_M 2.2 + NOSE_M 14.7, DOOR_SIDE_M 3.5.
STAND_ORIGIN_G = (-3.5, 0.0, -(2.2 + 14.7))


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


def pose_bridge(o, holder, p_world, n_world, label):
    """Apply the pose math of build_airside_props.py so Mount_Door lands on p_world
    with the cab facing -n_world. Returns (yaw, pitch, slide, error, foot_z)."""
    inv = holder.matrix_world.inverted()
    pl = inv @ Vector(p_world)
    nl = inv.to_3x3() @ Vector(n_world)
    # Blender local -> Godot local.
    P = (pl.x, pl.z, -pl.y)
    n = (nl.x, nl.z, -nl.y)
    C = (P[0] + n[0] * bp.MOUNT_DOOR_Z, P[1], P[2] + n[2] * bp.MOUNT_DOOR_Z)
    yaw = math.atan2(C[0], C[2])
    d = math.hypot(C[0], C[2]) - bp.HINGE_Z
    dh = C[1] - bp.ROT_FLOOR
    th = math.atan2(dh, d)
    s = math.hypot(d, dh) - bp.CAB_Z
    h = bp.ROT_FLOOR - bp.TUN_B_SINK * math.cos(th) + (bp.DRIVE_Z + s) * math.sin(th)
    cab = math.atan2(-n[0], -n[2]) - yaw
    for name in ("Tunnel_Yaw", "Tunnel_Pitch", "Tunnel_Slide", "Cab_Level", "Cab_Yaw", "Drive_Level", "Drive_Foot"):
        o[name].rotation_mode = "XYZ"
    o["Tunnel_Yaw"].rotation_euler = (0.0, 0.0, yaw)
    o["Tunnel_Pitch"].rotation_euler = (-th, 0.0, 0.0)
    o["Tunnel_Slide"].location = (0.0, -s, 0.0)
    o["Cab_Level"].rotation_euler = (th, 0.0, 0.0)
    o["Drive_Level"].rotation_euler = (th, 0.0, 0.0)
    o["Cab_Yaw"].rotation_euler = (0.0, 0.0, cab)
    o["Drive_Foot"].location = (0.0, 0.0, -h)
    bpy.context.view_layer.update()
    got = o["Mount_Door"].matrix_world.translation
    err = (got - Vector(p_world)).length
    foot = rap.world_points([o["Drive_Foot_Mesh"]])
    foot_z = float(foot[:, 2].min()) - holder.matrix_world.translation.z
    log("POSE %s yaw=%.1f pitch=%.2f slide=%.3f (0..%.1f) cab_yaw=%.1f drive_h=%.3f mount_err=%.4f "
        "bogie_min_z=%.4f"
        % (label, math.degrees(yaw), math.degrees(th), s, bp.SLIDE_MAX, math.degrees(cab), h, err, foot_z))
    if err > 0.005:
        invalid("%s: Mount_Door is %.4f m off the target" % (label, err))
    if not (-1e-6 <= s <= bp.SLIDE_MAX + 1e-6) or abs(math.degrees(th)) > bp.PITCH_MAX_DEG or h > bp.DRIVE_H_MAX:
        invalid("%s: pose out of reach (slide %.3f, pitch %.2f)" % (label, s, math.degrees(th)))
    if abs(foot_z) > 0.005:
        invalid("%s: the drive bogie is %.4f m off the ground" % (label, foot_z))
    return yaw, th, s, err, foot_z


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


# ---------------------------------------------------------------- poses


def poses():
    """Side view (from Godot +x) of the bridge at rest and at three sills."""
    scene = rap.reset_scene(1800, 800, 1.5)
    reach = bp.HINGE_Z + bp.CAB_Z + bp.MOUNT_DOOR_Z
    targets = [("rest", None), ("medium_05_1.59m", (1.59, reach + 0.6)), ("large_06_2.40m", (2.40, reach + 2.6)),
               ("large_07_2.90m", (2.90, reach + 4.6))]
    allp = []
    groups = {}
    for k, (label, tgt) in enumerate(targets):
        # Rows along Blender z would overlap; stack the four bridges vertically in the
        # side view by lifting each 7 m (a plate layout only; the ground bar shows 0).
        lift = (len(targets) - 1 - k) * 7.0
        objs, holder = place(prop("jet_bridge"), label, (0.0, lift, 0.0))
        o = by_name(objs)
        box_obj("Ground_" + label, g2b(-2.0, lift - 0.05, -3.5), g2b(2.0, lift, reach + 6.5), rap.FLOOR_RGB)
        if tgt is not None:
            sill, z = tgt
            p = g2b(0.0, lift + sill, z)
            # The fuselage is ahead (+z); its outward normal points back at the bridge.
            pose_bridge(o, holder, p, Vector(g2b(0.0, 0.0, -1.0)), label)
            mark = box_obj("Sill_" + label, g2b(-1.0, lift + sill - 0.04, z), g2b(1.0, lift + sill, z + 0.5), MARK_RGB)
            objs = objs + [mark]
        groups[label] = objs
        allp.append(rap.world_points(objs))
    ref = rap.cube(tuple(g2b(0.0, 0.5, -3.0)))
    ref_pts = rap.world_points([ref])
    pts = np.concatenate(allp + [ref_pts])
    rot = rap.look_rot((1.0, 0.0, 0.0), (0.0, 0.0, 1.0))
    inv = np.array(rot.to_matrix().inverted())
    loc = pts @ inv.T
    w = (loc[:, 0].max() - loc[:, 0].min()) / (1.0 - 2 * MARGIN - 0.03)
    hgt = (loc[:, 1].max() - loc[:, 1].min()) / (1.0 - 2 * MARGIN - 0.03)
    scale = max(w, hgt * 1800 / 800)
    cam = rap.ortho_camera(scene, rot, pts, scale)
    for label, objs in groups.items():
        rap.prove_in_frame("poses %s" % label, scene, cam, rap.world_points(objs))
    rap.prove_in_frame("poses cube", scene, cam, ref_pts)
    out = os.path.join(OUT, "poses.png")
    rap.save_array(rap.over(rap.render(scene, os.path.join(OUT, "poses_raw.png")), BACKDROP), out)
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


def stand_scene(pushed_m, with_tug):
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
    # The bridge: its link stub backs onto the wall (root turned 180 degrees, so its
    # -z points at the terminal), the rotunda port of the door, reach mid-range.
    p_door = Vector((skin_x, mid_y, sill_z))
    c = Vector((skin_x + bp.MOUNT_DOOR_Z, mid_y - pushed_m))  # the parked stand door
    rz = -(bp.LINK_Z + 0.3)
    want = bp.HINGE_Z + bp.CAB_Z + 1.5
    dz = rz - (-c.y)
    rx = c.x + math.sqrt(max(want * want - dz * dz, 0.0))
    bridge, bh = place(prop("jet_bridge"), "jet_bridge", (rx, 0.0, rz), 180.0)
    bo = by_name(bridge)
    if pushed_m == 0.0:
        pose_bridge(bo, bh, p_door, Vector((1.0, 0.0, 0.0)), "stand plane_05")
    else:
        bo["Tunnel_Yaw"].rotation_mode = "XYZ"
        bo["Tunnel_Yaw"].rotation_euler = (0.0, 0.0, math.radians(-70.0))
        bpy.context.view_layer.update()
    log("BRIDGE root_godot=(%.2f, 0, %.2f) column_to_exit_x=%.2f link_back_godot_z=%.2f"
        % (rx, rz, rx, -bo["Mount_Link"].matrix_world.translation.y))
    subjects["jet_bridge"] = bridge
    # The taxi sign at the stand's lead-in, north of the bridge, facing the camera side.
    sign, _sh = place(prop("taxi_sign"), "taxi_sign", (13.0, 0.0, -26.0), 125.0)
    subjects["taxi_sign"] = show_glyphs(sign, {"Glyph_Loc_B", "Glyph_Dir_C", "Glyph_Arrow_R"})
    if with_tug:
        wheel = rap.world_points([po["TP_Plane_05A_Wheel_F"]])
        axle = Vector(((wheel[:, 0].min() + wheel[:, 0].max()) / 2, (wheel[:, 1].min() + wheel[:, 1].max()) / 2,
                       (wheel[:, 2].min() + wheel[:, 2].max()) / 2))
        r = (wheel[:, 2].max() - wheel[:, 2].min()) / 2.0
        # The head's front face meets the wheel's front (Godot +z of the plane);
        # the tug faces the plane (yaw 180), the bar pitched down to axle height.
        head = Vector((axle.x, wheel[:, 1].min() - 0.02, axle.z))
        drop = bp.HITCH[1] - head.z
        pitch = math.asin(drop / bp.BAR_LEN)
        reach = bp.BAR_LEN * math.cos(pitch)
        # Facing Godot -z: the hitch is at tug + (0, 0.5, -3.1) Godot -> Blender +y.
        tug_g = (head.x, 0.0, -(head.y) + reach + bp.HITCH[2])
        tug, _th = place(prop("pushback_tug"), "pushback_tug", tug_g, 180.0)
        to = by_name(tug)
        to["Towbar_Pivot"].rotation_mode = "XYZ"
        to["Towbar_Pivot"].rotation_euler = (pitch, 0.0, 0.0)
        bpy.context.view_layer.update()
        sunk = float(rap.world_points([to["Towbar_Wheels_Mesh"]])[:, 2].min())
        # Retract the bar wheels (Towbar_Wheels up along its Godot Y = Blender local z).
        to["Towbar_Wheels"].location.z += max(0.0, -sunk) + 0.04
        bpy.context.view_layer.update()
        lifted = float(rap.world_points([to["Towbar_Wheels_Mesh"]])[:, 2].min())
        log("TOWBAR wheels_min_z hitched_unretracted=%.3f retracted=%.3f" % (sunk, lifted))
        if lifted < 0.0:
            invalid("tug: the bar wheels sink %.3f m into the ground" % -lifted)
        got = to["Mount_NoseGear"].matrix_world.translation
        tug_pts = rap.world_points([to["PushbackTug_Body"]])
        rear_g = float(-tug_pts[:, 1].min())
        log("TUG axle_godot=(%.2f, %.3f, %.2f) wheel_r=%.3f bar_pitch=%.2f mount_err=%.4f tug_rear_godot_z=%.2f "
            "(wall line 0; at the stand it would be %.2f)"
            % (axle.x, axle.z, -axle.y, r, math.degrees(pitch), (got - head).length, rear_g, rear_g + pushed_m))
        if (got - head).length > 0.005:
            invalid("tug: Mount_NoseGear is %.4f m off the nose wheel" % (got - head).length)
        subjects["pushback_tug"] = tug
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
    scene, subjects, _t = stand_scene(0.0, False)
    outs = [shoot("stand", scene, subjects, (-1.0, 1.5, -14.0), 125.0, 40.0, 60.0)]
    # Closer distance shots per prop, the plane in frame beside it.
    outs.append(shoot("stand_bridge", scene, {"jet_bridge": subjects["jet_bridge"]}, (3.0, 2.5, -7.0), 110.0, 30.0,
                      28.0))
    outs.append(shoot("stand_sign", scene, {"taxi_sign": subjects["taxi_sign"]}, (13.0, 0.6, -26.0), 145.0, 25.0,
                      9.0, need=0.10))
    return outs


def pushback():
    scene, subjects, _t = stand_scene(12.0, True)
    outs = [shoot("pushback", scene, {k: v for k, v in subjects.items() if k != "jet_bridge"}, (-4.0, 1.0, -21.0), 125.0, 40.0, 76.0)]
    outs.append(shoot("pushback_tug", scene, {"pushback_tug": subjects["pushback_tug"]}, (-3.5, 0.8, -12.5), 140.0,
                      30.0, 22.0))
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
    known = ["six", "poses", "glyphs", "stand", "pushback", "sheet"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    made = []
    if "six" in stages:
        made.append(six_axis("jet_bridge"))
        made.append(six_axis("pushback_tug"))
        made.append(six_axis("taxi_sign", {"Glyph_Loc_A", "Glyph_Dir_B", "Glyph_Arrow_R"}))
    if "poses" in stages:
        made.append(poses())
    if "glyphs" in stages:
        made.append(glyphs())
    if "stand" in stages:
        made.extend(stand())
    if "pushback" in stages:
        made.extend(pushback())
    if "sheet" in stages:
        names = ["six_axis/jet_bridge.png", "six_axis/pushback_tug.png", "six_axis/taxi_sign.png", "poses.png",
                 "glyphs.png", "stand.png", "stand_bridge.png", "stand_sign.png", "pushback.png", "pushback_tug.png"]
        paths = [os.path.join(OUT, n) for n in names if os.path.exists(os.path.join(OUT, n))]
        sheet(paths)
    log("PLATES done stages=%s made=%d" % (stages, len(made)))


if __name__ == "__main__":
    main()
