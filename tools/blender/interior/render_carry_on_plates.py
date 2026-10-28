"""Render the plates for the carry-on bag kinds.

Run (headless, reproducible), after build_carry_on_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_carry_on_plates.py' [-- stage ...]

Stages: six, distance (both when none is named). Everything is written under
tools/blender/out/carry-on-kinds/ (gitignored); nothing in game/ is touched. The plates
re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube,
  for each kind and the hard case (carry_on_bag) beside them;
- distance_12m.png: the four kinds lying in a row beside a person for scale, from the
  game camera at 12 m.
Each plate proves its subjects are in frame and visible; on failure PROBE_INVALID and
exit 1. Retracted straps and pull handles are drawn as built; the stretched, carried
look is judged in a windowed Godot run.
"""

import os
import sys

from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_carry_on_kit as carry  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "carry-on-kinds")
rbp.OUT = OUT
PIECES = ["carry_on_bag"] + list(carry.PIECES)

log = rap.log


def distance_plate(distance, yaw_deg):
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {}
    x = 0.0
    for piece in PIECES:
        subjects[piece] = rbp.place(piece, x, 0.0)
        x += 0.8
    subjects["male"] = rbp.person("male", x + 0.3, 0.0, 0.0, "scale")
    rap.floor_plane((-2.0, -3.0), (x + 2.0, 3.0))
    target = Vector((x / 2.0, 0.0, 0.3))
    cam = rbp.game_camera(scene, target, distance, yaw_deg)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_%dm %s height_px=%.1f width_px=%.1f" % (distance, name, (b[3] - b[1]) * 1080,
                                                              (b[2] - b[0]) * 1920))
        rbp.prove("distance_%dm %s" % (distance, name), scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "distance_%dm_raw.png" % distance))
    rap.save_array(rap.over(arr, rbp.BACKDROP), os.path.join(OUT, "distance_%dm.png" % distance))


def main():
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance"]
    unknown = [s for s in only if s not in known]
    if unknown:
        rap.invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        for piece in PIECES:
            rbp.six_axis(piece)
    if "distance" in stages:
        distance_plate(12, -30.0)
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
