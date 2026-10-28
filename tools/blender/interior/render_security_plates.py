"""Render the plates for the security lane pieces.

Run (headless, reproducible), after build_security_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_security_plates.py' [-- stage ...]

Stages: six, distance, lane (all when none is named). Everything is written under
tools/blender/out/security-lane/ (gitignored); nothing in game/ is touched. The plates
re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube;
- distance_30m.png: every piece in a row with a person for scale, from the game camera
  at 30 m;
- lane_yaw35.png and lane_yaw90.png: one whole lane at facing 0 with its parts on the
  arch's +X side (the RIGHT mirror of game/build/security_lanes.gd), a basic scanner two
  cells to its left, trays and carry-on bags on the three mounts, a passenger unpacking,
  one in the arch and the officer beside the X-ray, from the game camera at 8.5 m.
Each plate proves its subjects are in frame and visible (render_activities_plates'
prove_in_frame and visible_share); on failure PROBE_INVALID and exit 1. A Blender plate
is not the in-engine look: the toon ramp and outline are judged in a windowed Godot run.
"""

import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import build_security_kit as sec  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "security-lane")
# render_baggage_plates writes its six-axis plates and saves under its module OUT.
rbp.OUT = OUT
PIECES = list(sec.PIECES)
LANE_PARTS = ["security_arch", "tray_table", "xray_belt", "pickup_table"]

log = rap.log
invalid = rap.invalid


def save(scene, name):
    arr = rap.render(scene, os.path.join(OUT, name.replace(".png", "_raw.png")))
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, name))


def prop(piece, x, y, z, label):
    objs, _a, _n, _h = rap.import_glb(rbp.glb(piece), label, Matrix.Translation((x, y, z)))
    return objs


def distance_plate(distance, yaw_deg):
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {}
    x = 0.0
    for piece in PIECES:
        subjects[piece] = rbp.place(piece, x + 0.5, 0.0)
        x += 2.0
    subjects["male"] = rbp.person("male", x + 0.5, 0.0, 0.0, "scale")
    rap.floor_plane((-2.0, -4.0), (x + 3.0, 5.0))
    target = Vector(((x + 1.0) / 2.0, 0.0, 0.3))
    cam = rbp.game_camera(scene, target, distance, yaw_deg)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_%dm %s height_px=%.1f width_px=%.1f" % (distance, name, (b[3] - b[1]) * 1080,
                                                              (b[2] - b[0]) * 1920))
        rbp.prove("distance_%dm %s" % (distance, name), scene, cam, objs)
    save(scene, "distance_%dm.png" % distance)


def lane_layout():
    """The lane at facing 0, RIGHT mirror, arch at Blender (3.5, 3.5). Godot cell (x, y)
    of the lane frame is Blender (ax + x, ay - y): Godot +Z is Blender -y."""
    ax, ay = 3.5, 3.5
    subjects = {
        "security_arch": rbp.place("security_arch", ax, ay),
        "tray_table": rbp.place("tray_table", ax + 1, ay - 1),
        "xray_belt": rbp.place("xray_belt", ax + 1, ay),
        "pickup_table": rbp.place("pickup_table", ax + 1, ay + 1),
        "basic_scanner": rbp.place("security_scanner", ax - 2, ay + 0.5),
    }
    # Trays on the three mounts (Godot z -> Blender -y), a bag on two of them.
    top = sec.BELT_TOP
    for name, (gx, gy, gz), cell_y in (("in", sec.SECURITY["tray_table"]["mounts"]["Mount_TrayIn"], ay - 1),
                                       ("scan", sec.SECURITY["xray_belt"]["mounts"]["Mount_TrayScan"], ay),
                                       ("out", sec.SECURITY["pickup_table"]["mounts"]["Mount_TrayOut"], ay + 1)):
        if abs(gy - top) > 1e-6:
            invalid("mount %s is not at belt height" % name)
        subjects["tray_" + name] = prop("security_tray", ax + 1 + gx, cell_y - gz, gy, "tray_" + name)
        if name != "in":
            subjects["bag_" + name] = prop("carry_on_bag", ax + 1 + gx, cell_y - gz, gy + sec.TRAY_BASE,
                                           "bag_" + name)
    subjects["passenger_unpack"] = rbp.person("female", ax, ay - 1, 90.0, "unpack")
    subjects["passenger_arch"] = rbp.person("male", ax, ay, 180.0, "arch")
    subjects["officer"] = rbp.person("male", ax + 2, ay, -90.0, "officer")
    subjects["passenger_basic"] = rbp.person("female", ax - 2, ay - 1.4, 180.0, "basic")
    return subjects, Vector((ax + 0.2, ay, 0.6))


def lane_plate(yaw_deg):
    scene = rap.reset_scene(1600, 900, 1.5)
    rbp.floor_tiles(0, 7, 0, 7)
    subjects, target = lane_layout()
    cube = rap.cube((5.9, 4.4, 0.5))
    cam = rbp.game_camera(scene, target, 8.5, yaw_deg=yaw_deg)
    rap.prove_in_frame("lane_yaw%d cube" % yaw_deg, scene, cam, rap.world_points([cube]))
    for name, objs in subjects.items():
        need = 0.10
        # The bag in the tunnel is meant to be mostly hidden by the housing, and from the
        # side (yaw 90) the arch panel hides the passenger standing in it.
        if name in ("tray_scan", "bag_scan") or (yaw_deg == 90 and name == "passenger_arch"):
            rap.prove_in_frame("lane_yaw%d %s" % (yaw_deg, name), scene, cam, rap.world_points(objs))
            continue
        rbp.prove("lane_yaw%d %s" % (yaw_deg, name), scene, cam, objs, need=need)
    save(scene, "lane_yaw%d.png" % yaw_deg)


def main():
    sec.register()
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance", "lane"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        for piece in PIECES:
            rbp.six_axis(piece)
    if "distance" in stages:
        distance_plate(30, -30.0)
    if "lane" in stages:
        lane_plate(35)
        lane_plate(90)
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
