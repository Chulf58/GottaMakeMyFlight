"""Render the plates for the retail kit (duty-free and fashion shop pieces).

Run (headless, reproducible), after build_retail_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_retail_plates.py' [-- stage ...]

Stages: six, distance, context, sheet (all when none is named). Everything is written
under tools/blender/out/retail-kit/ (gitignored); nothing in game/ is touched. The plates
re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube;
- distance_30m.png: the four pieces and a person from the game camera at 30 m;
- context_front.png: a duty-free room (shelf on the back wall, till in the middle row)
  and a fashion room beside it (rail on the back wall, till in the middle row), with a
  customer at each till's Mount_Order, staff at each Mount_Staff and a browser at a
  browse slot of the shelf and of the rail, from the game camera at 13 m, without the
  left walls, as the wall cutaway lowers the walls facing the camera;
- context_rear.png: the same from behind (yaw 160) without the back and right walls, as
  the wall cutaway lowers them, and without the staff, to show whether a till's sign
  hides its till: nine points on each till screen's back face must be the first hit
  from the camera, and the same rays cast from under the counter top (the blocked
  control) must reach none of them;
- contact_sheet.png: the six-axis sheets, the distance plate and both context plates.
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

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_interior_kit as kit  # noqa: E402
import build_retail_kit as retail  # noqa: E402
import render_activities_plates as rap  # noqa: E402
import render_baggage_plates as rbp  # noqa: E402
import render_kiosk_plates as rkp  # noqa: E402

OUT = os.path.join(kit.REPO, "tools", "blender", "out", "retail-kit")
rbp.OUT = OUT
PIECES = list(retail.PIECES)
TILLS = ("duty_free_till", "fashion_till")

log = rap.log
invalid = rap.invalid


def at_mount(who, objs, mount):
    cobjs, acts, arm, _h = rap.add_character(who, rap.mount_xf(objs, mount))
    f0, f1 = rap.clip_range(acts, "idle")
    rap.pose(arm, acts, "idle", (f0 + f1) // 2)
    return cobjs


def distance_stage():
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {p: rbp.place(p, 2.3 * i, 0.0) for i, p in enumerate(PIECES)}
    subjects["male"] = rbp.person("male", 8.6, 0.0, 0.0, "scale")
    rap.floor_plane((-3.0, -4.0), (11.0, 4.0))
    cam = rbp.game_camera(scene, Vector((4.2, 0.0, 0.6)), 30.0, -30.0)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_30m %s height_px=%.1f width_px=%.1f" % (name, (b[3] - b[1]) * 1080, (b[2] - b[0]) * 1920))
        rbp.prove("distance_30m %s" % name, scene, cam, objs, need=0.10)
    arr = rap.render(scene, os.path.join(OUT, "distance_30m_raw.png"))
    rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, "distance_30m.png"))


def room_walls(x0, back_wall):
    """A 4 x 3 cell room at Blender x x0..x0+4, y 0..3, open at the front (y 0). With
    the back wall standing (the front camera, from the left) the left wall is left out,
    as the wall cutaway lowers a camera-facing wall with floor behind it; from behind
    the back and right walls are left out instead."""
    if back_wall:
        for i in range(4):
            rbp.place("wall", x0 + i + 0.5, 3.0, label="wall_back_%d_%d" % (x0, i))
    for j in range(3):
        if not back_wall:
            rbp.place("wall", x0, j + 0.5, 90.0, label="wall_left_%d_%d" % (x0, j))
        if back_wall:
            rbp.place("wall", x0 + 4.0, j + 0.5, 90.0, label="wall_right_%d_%d" % (x0, j))
    for x, y in ((x0, 3.0), (x0 + 4.0, 3.0), (x0, 0.0), (x0 + 4.0, 0.0)):
        rbp.place("wall_post", x, y, label="post_%d_%.0f_%.0f" % (x0, x, y))


def context_scene(back_wall, staff):
    """The duty-free room at Blender x 0..4 and the fashion room at x 5..9. Each has its
    shelf or rail on the back wall (cells y 2..3) and its till in the middle row (y 1..2),
    so the till's staff cell is the free back row. Piece fronts face Blender -y."""
    scene = rap.reset_scene(1920, 1080, 1.2)
    rbp.floor_tiles(0, 9, -2, 3)
    room_walls(0, back_wall)
    room_walls(5, back_wall)
    subjects = {
        "shelf": rbp.place("duty_free_shelf", 1.0, 2.5, label="shelf"),
        "df_till": rbp.place("duty_free_till", 3.0, 1.5, label="df_till"),
        "rail": rbp.place("fashion_rail", 6.0, 2.5, label="rail"),
        "fa_till": rbp.place("fashion_till", 8.0, 1.5, label="fa_till"),
    }
    subjects["df_customer"] = at_mount("male", subjects["df_till"], "Mount_Order")
    subjects["shelf_browser"] = at_mount("female", subjects["shelf"], "Mount_Browse_0")
    subjects["fa_customer"] = at_mount("female", subjects["fa_till"], "Mount_Order")
    subjects["rail_browser"] = at_mount("male", subjects["rail"], "Mount_Browse_1")
    if staff:
        subjects["df_staff"] = at_mount("female", subjects["df_till"], "Mount_Staff")
        subjects["fa_staff"] = at_mount("male", subjects["fa_till"], "Mount_Staff")
    cube = rap.cube((10.0, -1.5, 0.5))
    return scene, subjects, cube


def till_points(counter, title, side):
    """World points on the till screen's back or front face (a 3 x 3 grid), from
    build_services_kit.till(prefix, -0.5) with its 15 degree lean, in the placed
    counter's frame (Blender coordinates, as till() builds them)."""
    root = next(o for o in counter if rap.base_name(o.name) == title + "_ROOT")
    x, top = -0.5, 1.0
    # The lit face (Blender y -0.165) faces the staff side; the customer side is y -0.20.
    y = -0.165 if side == "back" else -0.20
    p = Vector((x, -0.185, top + 0.05))
    lean = Matrix.Translation(p) @ Matrix.Rotation(math.radians(15.0), 4, "X") @ Matrix.Translation(-p)
    pts = []
    for fx in (0.25, 0.5, 0.75):
        for fz in (0.25, 0.5, 0.75):
            pts.append(root.matrix_world @ (lean @ Vector((x - 0.10 + 0.20 * fx, y, top + 0.05 + 0.17 * fz))))
    return pts


def context_stage():
    for name, back_wall, yaw in (("context_front", True, -20.0), ("context_rear", False, 160.0)):
        scene, subjects, cube = context_scene(back_wall, staff=back_wall)
        cam = rbp.game_camera(scene, Vector((4.6, 1.4, 0.8)), 13.0, yaw)
        rap.prove_in_frame("%s cube" % name, scene, cam, rap.world_points([cube]))
        for label, objs in subjects.items():
            if back_wall or label not in ("shelf", "rail", "df_till", "fa_till"):
                rbp.prove("%s %s" % (name, label), scene, cam, objs, need=0.10)
            else:
                # Static pieces seen from behind: their own fronts hide most of their
                # faces, so only other objects count as blockers.
                rap.prove_in_frame("%s %s" % (name, label), scene, cam, rap.world_points(objs))
                rkp.seen_share("%s %s" % (name, label), scene, cam, objs, need=0.50)
        side = "front" if back_wall else "back"
        for label, piece in (("df_till", "duty_free_till"), ("fa_till", "fashion_till")):
            pts = till_points(subjects[label], kit.piece_title(piece), side)
            share = rkp.till_seen("%s %s till %s" % (name, label, side), scene, cam.matrix_world.translation, pts)
            if not back_wall:
                if share < 1.0:
                    invalid("%s: the %s till is hidden from the rear camera (%.2f)" % (name, label, share))
                under = pts[4] + Vector((0.0, 0.0, -0.5))
                if rkp.till_seen("%s %s till control_under_top" % (name, label), scene, under, pts) > 0.0:
                    invalid("%s: the blocked control reached the %s till" % (name, label))
        arr = rap.render(scene, os.path.join(OUT, name + "_raw.png"))
        rap.save_array(rap.over(arr, rap.BACKDROP), os.path.join(OUT, name + ".png"))


def load_png(path):
    if not os.path.exists(path):
        invalid("contact sheet input missing: %s" % path)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)


def sheet_stage():
    paths = [os.path.join(OUT, "six_axis", p + ".png") for p in PIECES]
    paths += [os.path.join(OUT, n + ".png") for n in ("distance_30m", "context_front", "context_rear")]
    tiles = [rap.downscale(load_png(p), 2) for p in paths]
    rap.save_array(rap.grid(tiles, 2), os.path.join(OUT, "contact_sheet.png"))
    log("sheet tiles=%d" % len(tiles))


def main():
    retail.register()
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "distance", "context", "sheet"]
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
    if "sheet" in stages:
        sheet_stage()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
