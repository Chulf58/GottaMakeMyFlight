"""Render the plates for the kiosk kit and the screen stand.

Run (headless, reproducible), after build_kiosk_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_kiosk_plates.py' [-- stage ...]

Stages: six, distance, context (all when none is named). Everything is written under
tools/blender/out/boredom-art/ (gitignored); nothing in game/ is touched. The plates
re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube;
- distance_30m.png: the three pieces and a person from the game camera at 30 m;
- context_front.png: a kiosk room (walls on three sides, the counter and the display
  along the back wall) with a passenger at the till and one at each browse slot, and
  beside it a screen stand facing a seat row and two standing passengers, from the
  game camera at 11 m;
- context_rear.png: the same from behind (yaw 160), with the back and right walls left out as
  the game's wall cutaway lowers the walls facing the camera, to show whether the
  counter's sign hides the till: nine points on the till screen's back face must be
  the first hit from the camera, and the same rays cast from under the counter top
  (the blocked control) must reach none of them.
Each plate proves its subjects are in frame and visible; on failure PROBE_INVALID and
exit 1. A Blender plate is not the in-engine look: the toon ramp and outline are judged
in a windowed Godot run.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import build_kiosk_kit as kiosk  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "boredom-art")
rbp.OUT = OUT
PIECES = list(kiosk.PIECES)

log = rap.log
invalid = rap.invalid


def at_mount(who, objs, mount):
    cobjs, acts, arm, _h = rap.add_character(who, rap.mount_xf(objs, mount))
    f0, f1 = rap.clip_range(acts, "idle")
    rap.pose(arm, acts, "idle", (f0 + f1) // 2)
    return cobjs


def distance_stage():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {
        "kiosk_counter": rbp.place("kiosk_counter", 0.0, 0.0),
        "kiosk_display": rbp.place("kiosk_display", 2.5, 0.0),
        "screen_stand": rbp.place("screen_stand", 4.5, 0.0),
    }
    subjects["male"] = rbp.person("male", 6.0, 0.0, 0.0, "scale")
    rap.floor_plane((-3.0, -4.0), (8.0, 4.0))
    cam = rbp.game_camera(scene, Vector((3.0, 0.0, 0.6)), 30.0, -30.0)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_30m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_30m %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "distance_30m_raw.png"))
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, "distance_30m.png"))


def context_scene(back_wall):
    """A 4 x 3 cell kiosk room, Blender x 0..4, y 0..3, back wall at y 3, side walls at
    x 0 and 4, open at the front; a gate corner to its right with a screen stand facing
    a seat row. Piece fronts face Blender -y."""
    scene = rap.reset_scene(1920, 1080, 1.2)
    rbp.floor_tiles(0, 9, -2, 3)
    if back_wall:
        for i in range(4):
            rbp.place("wall", i + 0.5, 3.0, label="wall_back_%d" % i)
    for j in range(3):
        rbp.place("wall", 0.0, j + 0.5, 90.0, label="wall_left_%d" % j)
        if back_wall:
            rbp.place("wall", 4.0, j + 0.5, 90.0, label="wall_right_%d" % j)
    for x, y in ((0.0, 3.0), (4.0, 3.0), (0.0, 0.0), (4.0, 0.0)):
        rbp.place("wall_post", x, y, label="post_%.0f_%.0f" % (x, y))
    subjects = {
        "counter": rbp.place("kiosk_counter", 1.0, 2.5, label="counter"),
        "display": rbp.place("kiosk_display", 3.0, 2.5, label="display"),
        "screen": rbp.place("screen_stand", 6.5, 2.5, label="screen"),
        "seats": rbp.place("seat_row", 6.5, -0.5, 180.0, label="seats"),
    }
    subjects["till_guest"] = at_mount("male", subjects["counter"], "Mount_Till")
    subjects["browser_0"] = at_mount("female", subjects["display"], "Mount_Browse_0")
    subjects["browser_1"] = at_mount("male", subjects["display"], "Mount_Browse_1")
    subjects["watcher_0"] = rbp.person("female", 5.4, 1.0, 180.0, "watcher_0")
    subjects["watcher_1"] = rbp.person("male", 7.6, 0.9, 180.0, "watcher_1")
    cube = rap.cube((8.5, -1.5, 0.5))
    return scene, subjects, cube


def seen_share(label, scene, cam, subject, need):
    """The share of the subject's camera-facing face centres whose first hit from the
    camera is the subject itself, at any depth. rap.visible_share counts a face hidden
    by the subject's own front as unseen, which fails a piece seen from behind (the
    display's products behind its back panel) though its back is in plain view; here
    only OTHER objects count as occluders. Prints the blockers either way."""
    dg = bpy.context.evaluated_depsgraph_get()
    own = {o.name for o in subject}
    origin = cam.matrix_world.translation
    facing, hit, blockers = 0, 0, {}
    for o in rap.meshes(subject):
        nmat = o.matrix_world.to_3x3().inverted_safe().transposed()
        for f in o.data.polygons:
            p = o.matrix_world @ f.center
            if (nmat @ f.normal).dot(origin - p) <= 0.0:
                continue
            facing += 1
            d = p - origin
            ok, _loc, _n, _i, ob, _m = scene.ray_cast(dg, origin, d.normalized(), distance=d.length + 0.02)
            name = ob.original.name if ok and ob is not None else "<nothing>"
            if name in own:
                hit += 1
            else:
                blockers[name] = blockers.get(name, 0) + 1
    share = hit / max(1, facing)
    log("%s seen facing=%d hit_self=%d share=%.2f need=%.2f blockers=%s"
        % (label, facing, hit, share, need, sorted(blockers.items(), key=lambda kv: -kv[1])[:6]))
    if share < need:
        invalid("%s: only %.2f of the camera-facing surface is unblocked" % (label, share))


def till_points(counter, side):
    """World points on the till screen's back or front face (a 3 x 3 grid), from
    build_kiosk_kit.TILL with its lean, in the placed counter's frame."""
    t = kiosk.TILL
    root = next(o for o in counter if rap.base_name(o.name) == "KioskCounter_ROOT")
    z = t["z"][0] if side == "back" else t["z"][1] + 0.005
    px, py, pz = t["pivot"]
    pb = Vector((px, -pz, py))
    lean = Matrix.Translation(pb) @ Matrix.Rotation(math.radians(-t["lean"]), 4, "X") @ Matrix.Translation(-pb)
    pts = []
    for fx in (0.25, 0.5, 0.75):
        for fy in (0.25, 0.5, 0.75):
            gx = t["x"][0] + fx * (t["x"][1] - t["x"][0])
            gy = t["y"][0] + fy * (t["y"][1] - t["y"][0])
            pts.append(root.matrix_world @ (lean @ Vector((gx, -z, gy))))
    return pts


def till_seen(label, scene, origin, pts):
    """The share of `pts` whose first hit along the ray from `origin` lands on the
    point itself (within 2 cm): a hit on the canopy, the sign or a passenger fails it,
    unlike seen_share, which counts any part of the counter."""
    dg = bpy.context.evaluated_depsgraph_get()
    hit = 0
    for p in pts:
        d = p - origin
        ok, loc, _n, _i, ob, _m = scene.ray_cast(dg, origin, d.normalized(), distance=d.length + 0.05)
        if ok and (loc - p).length < 0.02:
            hit += 1
    share = hit / len(pts)
    log("%s till_points=%d on_target=%d share=%.2f" % (label, len(pts), hit, share))
    return share


def context_stage():
    for name, back_wall, yaw in (("context_front", True, -20.0), ("context_rear", False, 160.0)):
        scene, subjects, cube = context_scene(back_wall)
        cam = rbp.game_camera(scene, Vector((4.3, 1.0, 0.8)), 11.0, yaw)
        rap.prove_in_frame("%s cube" % name, scene, cam, rap.world_points([cube]))
        for label, objs in subjects.items():
            if back_wall or label not in ("counter", "display"):
                rbp.prove("%s %s" % (name, label), scene, cam, objs, need=0.10)
            else:
                # Static kit pieces seen from behind: their own fronts hide most of
                # their faces, so only other objects count as blockers.
                rap.prove_in_frame("%s %s" % (name, label), scene, cam, rap.world_points(objs))
                seen_share("%s %s" % (name, label), scene, cam, objs, need=0.50)
        # The till itself: from behind, its back face must be in view (the sign and
        # canopy stand on the other half). The control casts the same rays from under
        # the counter top and must be blocked.
        side = "front" if back_wall else "back"
        pts = till_points(subjects["counter"], side)
        share = till_seen("%s till %s" % (name, side), scene, cam.matrix_world.translation, pts)
        if not back_wall:
            if share < 0.5:
                invalid("%s: the till is hidden from the rear camera (%.2f)" % (name, share))
            under = pts[4] + Vector((0.0, 0.0, -0.5))
            if till_seen("%s till control_under_top" % name, scene, under, pts) > 0.0:
                invalid("%s: the blocked control reached the till" % name)
        arr = rap.render(scene, os.path.join(OUT, name + "_raw.png"))
        rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, name + ".png"))


def main():
    kiosk.register()
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance", "context"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        for piece in PIECES:
            rbp.six_axis(piece)
    if "distance" in stages:
        distance_stage()
    if "context" in stages:
        context_stage()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
