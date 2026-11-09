"""Blender plates for the jet bridge's stair box and hollow tunnels (board 0adca5c6).

Run (headless, reproducible), after build_airside_props.py has written jet_bridge.glb:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\render_jet_bridge_board.py'

Everything is written under tools/blender/out/jet_bridge_board/ (gitignored). The plates
re-import the WRITTEN game/assets/airside/props/jet_bridge.glb and plane 05:
- six_axis.png (and six_axis_<view>.png): six orthographic views at one true scale with
  a 1 m cube beside the bridge, the tunnel at the docked yaw and half extended (slide 2.5 m)
  so both tunnel sections show, and 1.75 m guest boxes (orange) standing inside tunnel
  A, tunnel B, the cab, the corridor, the stair and the vestibule;
- stand.png: plane 05 docked at a stand (wall line Godot z 0, exit door x 0), the bridge
  rooted at the exit door as JetBridgePose.root_for() places it, guests inside, a grey
  2.5 m terminal behind the wall, seen from about 45 m; stand_close.png from about 22 m.
Every plate proves its subjects lie in the frame margin (render_activities_plates.
prove_in_frame) and the guests are seen: camera rays reach a guest first, passing
through glass panes (TP_Glass_1A_D faces), which a passenger is seen through. A guest
must be seen in at least one six-axis view and in each stand plate; on failure
PROBE_INVALID and exit 1.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "interior"))
import build_airside_props as bp  # noqa: E402
import render_airside_plates as rp  # noqa: E402

rap = rp.rap
kit = bp.kit
OUT = os.path.join(kit.REPO, "tools", "blender", "out", "jet_bridge_board")
GUEST_RGB = (0.95, 0.45, 0.10)
GUEST_W, GUEST_H, GUEST_D = 0.5, 1.75, 0.35
SIX_PX = 900
SLIDE_SIX = 2.5
# Guests: name -> (bridge node the guest stands in, Godot point in that node's frame).
_TUN_B0 = bp.CAB_Z - bp.TUN_B_LEN
_STEP = 8
GUESTS = {
    "tunnel_a": ("Tunnel_Pitch", (0.0, 0.0, 2.6)),
    "tunnel_b": ("Tunnel_Slide", (0.0, -0.02, _TUN_B0 + 2.35)),
    "cab": ("Cab_Yaw", (0.5, 0.0, 0.0)),
    "corridor": ("JetBridge_ROOT", (2.05, bp.ROT_FLOOR, -bp.LINK_Z)),
    "stair": ("JetBridge_ROOT", (bp.STAIR_FOOT_X - (_STEP - 0.5) * bp.TREAD, _STEP * bp.RISE, -bp.LINK_Z)),
    "vestibule": ("JetBridge_ROOT", (bp.EXIT_X, 0.03, -bp.LINK_Z)),
}


def guests(bo):
    """One 1.75 m box per GUESTS entry, parented to its bridge node."""
    out = {}
    for name, (node, at) in GUESTS.items():
        lo = Vector((at[0] - GUEST_W / 2, at[1], at[2] - GUEST_D / 2))
        hi = Vector((at[0] + GUEST_W / 2, at[1] + GUEST_H, at[2] + GUEST_D / 2))
        ob = rp.box_obj("Guest_" + name, rp.g2b(lo.x, lo.y, hi.z), rp.g2b(hi.x, hi.y, lo.z), GUEST_RGB)
        parent = bo[node]
        mw = ob.matrix_world.copy()
        ob.parent = parent
        ob.matrix_world = parent.matrix_world @ mw
        out[name] = ob
    bpy.context.view_layer.update()
    return out


def godot_of(ob):
    t = ob.matrix_world.translation
    return (t.x, t.z, -t.y)


def report_mounts(bo, label):
    for name in bp.WALK_MOUNTS + ["Mount_Door"]:
        g = godot_of(bo[name])
        rap.log("MOUNT %s %-17s godot=(%.3f, %.3f, %.3f)" % (label, name, g[0], g[1], g[2]))


def is_glass(ob, index):
    me = ob.data
    if index < 0 or index >= len(me.polygons):
        return False
    slot = me.polygons[index].material_index
    mat = ob.material_slots[slot].material if slot < len(ob.material_slots) else None
    return mat is not None and "glass" in mat.name.lower()


def seen_share(label, scene, cam, ob, need):
    """Rays from the camera to the camera-facing face centres of `ob`: the share whose
    first opaque hit is `ob`. A hit on a glass face continues past it."""
    dg = bpy.context.evaluated_depsgraph_get()
    mw = ob.matrix_world
    nmat = mw.to_3x3().inverted_safe().transposed()
    view = cam.matrix_world.to_3x3() @ Vector((0.0, 0.0, 1.0))
    ortho = cam.data.type == "ORTHO"
    total = 0
    hits = 0
    blockers = {}
    samples = []
    for f in ob.data.polygons:
        n = (nmat @ f.normal).normalized()
        q = [mw @ ob.data.vertices[i].co for i in f.vertices]
        # A 6 x 6 grid over each quad face: a guest seen only from the shoulders up
        # through a window has no face centre in view.
        for a in range(6):
            for b in range(6):
                s, t = (a + 0.5) / 6.0, (b + 0.5) / 6.0
                samples.append((q[0].lerp(q[1], s).lerp(q[3].lerp(q[2], s), t), n))
    for p, n in samples:
        origin = p + view * 200.0 if ortho else cam.matrix_world.translation
        if n.dot(origin - p) <= 0.0:
            continue
        total += 1
        target = p + n * 0.005
        start = origin
        hit_ob = None
        for _ in range(8):
            d = target - start
            ok, loc, _n, idx, hob, _m = scene.ray_cast(dg, start, d.normalized(), distance=d.length + 0.02)
            if not ok:
                break
            hob = hob.original
            if hob.type == "MESH" and is_glass(hob, idx):
                start = loc + d.normalized() * 0.002
                continue
            hit_ob = hob
            break
        if hit_ob is not None and hit_ob.name == ob.name:
            hits += 1
        else:
            key = hit_ob.name if hit_ob is not None else "<nothing>"
            blockers[key] = blockers.get(key, 0) + 1
    share = hits / max(1, total)
    rap.log("SEEN %s %s facing=%d hit=%d share=%.2f need=%.2f blocked_by=%s"
            % (label, ob.name, total, hits, share, need, sorted(blockers.items(), key=lambda kv: -kv[1])[:4]))
    return share


def set_pose(bo, yaw, pitch, slide, cab_yaw, drive_h):
    for name in ("Tunnel_Yaw", "Tunnel_Pitch", "Tunnel_Slide", "Cab_Level", "Cab_Yaw", "Drive_Level", "Drive_Foot"):
        bo[name].rotation_mode = "XYZ"
    bo["Tunnel_Yaw"].rotation_euler = (0.0, 0.0, yaw)
    bo["Tunnel_Pitch"].rotation_euler = (-pitch, 0.0, 0.0)
    bo["Tunnel_Slide"].location = (0.0, -slide, 0.0)
    bo["Cab_Level"].rotation_euler = (pitch, 0.0, 0.0)
    bo["Drive_Level"].rotation_euler = (pitch, 0.0, 0.0)
    bo["Cab_Yaw"].rotation_euler = (0.0, 0.0, cab_yaw)
    bo["Drive_Foot"].location = (0.0, 0.0, -drive_h)
    bpy.context.view_layer.update()


def six_axis():
    scene = rap.reset_scene(SIX_PX, SIX_PX, 1.5)
    objs, _h = rp.place(rp.prop("jet_bridge"), "jet_bridge")
    bo = rp.by_name(objs)
    # The docked yaw every stand uses: the rotunda's openings are cut for it.
    set_pose(bo, math.radians(bp.YAW_USED[0]), 0.0, SLIDE_SIX, 0.0, bp.ROT_FLOOR - bp.TUN_B_SINK)
    report_mounts(bo, "six_axis")
    gs = guests(bo)
    lo, hi = rap.bounds(objs)
    ref = rap.cube((hi.x + 0.35 + 0.5, lo.y - 0.35 - 0.5, 0.5))
    sub = rap.world_points(objs)
    ref_pts = rap.world_points([ref])
    allp = rp.np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in rap.VIEWS:
        inv = rp.np.array(rap.look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * rp.MARGIN - 0.04
    rap.log("six_axis size_m godot=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
            % (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y, scale, SIX_PX / scale))
    best = {name: 0.0 for name in gs}
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "six_axis %s" % name
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        rap.log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            rap.invalid("%s: the reference cube overlaps the subject on screen" % label)
        for g, ob in gs.items():
            best[g] = max(best[g], seen_share(label, scene, cam, ob, 0.0))
        path = os.path.join(OUT, "six_axis_%s.png" % name)
        tiles.append(rap.over(rap.render(scene, path), rp.BACKDROP))
        bpy.data.objects.remove(cam)
    for g, share in best.items():
        rap.log("GUEST six_axis %s best_share=%.2f" % (g, share))
        if share < 0.15:
            rap.invalid("six_axis: guest %s is not seen through any window in any view" % g)
    out = os.path.join(OUT, "six_axis.png")
    rap.save_array(rap.grid(tiles, 3), out)
    return out


def stand_scene():
    scene = rap.reset_scene(1800, 1100, 1.2)
    ox, oy, oz = rp.STAND_ORIGIN_G
    plane, _ph = rp.place(rp.PLANE, "plane_05", (ox, oy, oz))
    po = rp.by_name(plane)
    door = rap.world_points([po["TP_Plane_05A_Door"]])
    sill_z = float(door[:, 2].min())
    skin_x = float(door[:, 0].max())
    mid_y = float((door[:, 1].min() + door[:, 1].max()) / 2.0)
    rap.log("DOOR plane_05 sill=%.3f skin_x=%.3f mid_godot_z=%.3f" % (sill_z, skin_x, -mid_y))
    # A grey 2.5 m terminal behind the wall line (Godot z 0 .. 14), as tall as the
    # interior kit's walls, with the exit door at x 0.
    rp.box_obj("Terminal", rp.g2b(-26.0, 0.0, 14.0), rp.g2b(26.0, kit.WALL_H, 0.0), rp.TERMINAL_RGB)
    rap.floor_plane((-40.0, -14.0), (40.0, 62.0))
    # The bridge as JetBridgePose.root_for() places it: EXIT_X east of the exit door,
    # ROOT_OUT north of the wall line, turned 180 degrees.
    root_g = (bp.EXIT_X, 0.0, -bp.ROOT_OUT)
    bridge, bh = rp.place(rp.prop("jet_bridge"), "jet_bridge", root_g, 180.0)
    bo = rp.by_name(bridge)
    rp.pose_bridge(bo, bh, Vector((skin_x, mid_y, sill_z)), Vector((1.0, 0.0, 0.0)), "stand plane_05")
    sill = godot_of(bo["Mount_StairBottom"])
    rap.log("EXIT stair_bottom_godot=(%.3f, %.3f, %.3f) exit_door_godot=(0, 0, 0) off=%.4f"
            % (sill[0], sill[1], sill[2], math.sqrt(sum(v * v for v in sill))))
    if math.sqrt(sum(v * v for v in sill)) > 0.005:
        rap.invalid("stand: Mount_StairBottom is not on the exit door's sill")
    report_mounts(bo, "stand")
    gs = guests(bo)
    return scene, {"plane_05": plane, "jet_bridge": bridge}, gs


def shoot(name, scene, subjects, gs, target_g, az_deg, el_deg, dist, lens=35.0, need=0.08):
    t = rp.g2b(*target_g)
    az, el = math.radians(az_deg), math.radians(el_deg)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam = rap.persp_camera(scene, t + direction * dist, t, lens=lens)
    rap.log("%s camera_to_target=%.1f m lens=%.0f" % (name, dist, lens))
    for label, objs in subjects.items():
        rap.prove_in_frame("%s %s" % (name, label), scene, cam, rap.world_points(objs))
    seen = 0
    for g, ob in gs.items():
        rap.prove_in_frame("%s guest %s" % (name, g), scene, cam, rap.world_points([ob]))
        if seen_share(name, scene, cam, ob, need) >= need:
            seen += 1
    rap.log("%s guests_seen=%d of %d" % (name, seen, len(gs)))
    if seen == 0:
        rap.invalid("%s: no guest is seen through a window" % name)
    out = os.path.join(OUT, name + ".png")
    rap.save_array(rap.over(rap.render(scene, os.path.join(OUT, name + "_raw.png")), rp.BACKDROP), out)
    bpy.data.objects.remove(cam)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    made = [six_axis()]
    scene, subjects, gs = stand_scene()
    made.append(shoot("stand", scene, subjects, gs, (1.0, 2.0, -11.0), 140.0, 30.0, 64.0))
    made.append(shoot("stand_close", scene, {"jet_bridge": subjects["jet_bridge"]}, gs, (4.0, 3.0, -4.0), 125.0,
                      18.0, 24.0))
    rp.OUT = OUT
    rp.sheet(made)
    rap.log("PLATES done made=%d fails=%d" % (len(made), len(rap.FAILS)))
    if rap.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    main()
