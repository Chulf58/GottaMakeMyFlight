"""Render the plates for the baggage kit.

Run (headless, reproducible), after build_baggage_kit.py has written the pieces:
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\render_baggage_plates.py' [-- stage ...]

Stages: six, join, distance, context (all when none is named). Everything is written
under tools/blender/out/baggage_kit/ (gitignored); nothing in game/ is touched. The
plates re-import the WRITTEN .glb files from game/assets/interior/:
- six_axis/<piece>.png: six orthographic views at true scale with a 1 m reference cube;
- join.png: check-in desk -> feed -> collector straight -> corner -> straight -> end,
  close up from the game camera at 6 m, with the desk-to-feed gap measured and logged;
- distance_30m.png and distance_80m.png: every piece in a row with a person for scale,
  from the game camera at 30 m and at its 80 m home distance;
- context.png: two check-in desks feeding a collector that runs into a bag room with
  the belt end, a loaded and an empty cart, bags riding the belts, passengers at the
  desks and a handler in the bag room, from the game camera at 20 m.
The game camera is the tycoon camera's own framing (game/camera/tycoon_camera.gd and
.tscn): 55 degree vertical field of view, pitch from pitch_for_distance (35 degrees at
6 m to 65 at 300 m, smoothstep on the log of the distance).
Each plate proves its subjects are in frame and visible (render_activities_plates'
prove_in_frame and visible_share); on failure PROBE_INVALID and exit 1. A Blender plate
is not the in-engine look: the toon ramp and outline are judged in a windowed Godot run.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_baggage_kit as bag  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import render_activities_plates as rap  # noqa: E402

REPO = kit.REPO
KIT_DIR = kit.OUT_DIR
OUT = os.path.join(REPO, "tools", "blender", "out", "baggage_kit")
PIECES = list(bag.PIECES)
MARGIN = rap.MARGIN
BACKDROP = rap.BACKDROP
ROOM_RGB = (0.55, 0.66, 0.74)

# The tycoon camera (game/camera/tycoon_camera.gd, tycoon_camera.tscn).
CAM_FOV_Y = 55.0
CAM_MIN_D, CAM_MAX_D = 6.0, 300.0
CAM_NEAR_PITCH, CAM_FAR_PITCH = 35.0, 65.0

log = rap.log
invalid = rap.invalid


def glb(piece):
    return os.path.join(KIT_DIR, piece + ".glb")


def pitch_for_distance(d):
    t = (math.log(d) - math.log(CAM_MIN_D)) / (math.log(CAM_MAX_D) - math.log(CAM_MIN_D))
    t = min(1.0, max(0.0, t))
    s = t * t * (3.0 - 2.0 * t)
    return CAM_NEAR_PITCH + (CAM_FAR_PITCH - CAM_NEAR_PITCH) * s


def game_camera(scene, target, distance, yaw_deg=0.0):
    """The tycoon camera orbiting `target` (Blender) at `distance`. Yaw 0 looks along
    Godot -Z (Blender +y), so piece fronts face the camera."""
    pitch = math.radians(pitch_for_distance(distance))
    yaw = math.radians(yaw_deg)
    direction = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam = rap.persp_camera(scene, Vector(target) + direction * distance, target)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(CAM_FOV_Y)
    bpy.context.view_layer.update()
    log("game_camera distance=%.1f pitch=%.1f yaw=%.1f fov_y=%.0f" % (distance, math.degrees(pitch), yaw_deg,
                                                                      CAM_FOV_Y))
    return cam


def place(piece, x, y, yaw_deg=0.0, label=None):
    """Import a written piece with its origin at Blender (x, y), turned yaw_deg about Z
    (a Godot facing turn)."""
    objs, _a, _n, _h = rap.import_glb(glb(piece), label or "%s_%.1f_%.1f" % (piece, x, y),
                                      Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    return objs


def bag_on(x, y, z, yaw_deg, label, pitch_deg=0.0):
    xf = (Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
          @ Matrix.Rotation(math.radians(pitch_deg), 4, "X"))
    objs, _a, _n, _h = rap.import_glb(glb("baggage_bag"), label, xf)
    return objs


def person(who, x, y, yaw_deg, label):
    objs, acts, arm, _h = rap.add_character(who, Matrix.Translation((x, y, 0.0))
                                            @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    f0, f1 = rap.clip_range(acts, "idle")
    rap.pose(arm, acts, "idle", (f0 + f1) // 2)
    log("person %s %s at (%.2f, %.2f) yaw=%.0f" % (label, who, x, y, yaw_deg))
    return objs


def floor_tiles(x0, x1, y0, y1):
    tile, _a, _n, _h = rap.import_glb(os.path.join(KIT_DIR, "floor_tile.glb"), "floor")
    bodies = [(o.data, o.matrix_world.copy()) for o in rap.meshes(tile)]
    for o in tile:
        bpy.data.objects.remove(o)
    scene = bpy.context.scene
    for j in range(y0, y1):
        for i in range(x0, x1):
            for data, mw in bodies:
                dup = bpy.data.objects.new("Floor_%d_%d" % (i, j), data)
                dup.matrix_world = Matrix.Translation((i + 0.5, j + 0.5, 0.0)) @ mw
                scene.collection.objects.link(dup)


def room_tint(lo, hi):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, 0.004))
    ob = bpy.context.active_object
    ob.scale = (hi[0] - lo[0], hi[1] - lo[1], 1.0)
    ob.name = "Plate_BagRoom"
    ob.data.materials.append(rap.flat(ROOM_RGB))
    return ob


def prove(label, scene, cam, objs, need=0.15):
    rap.prove_in_frame(label, scene, cam, rap.world_points(objs))
    rap.visible_share(label, scene, cam, objs, need=need)


def save(scene, name):
    arr = rap.render(scene, os.path.join(OUT, name.replace(".png", "_raw.png")))
    rap.save_array(rap.over(arr, BACKDROP), os.path.join(OUT, name))


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


# ---------------------------------------------------------------- assemblies


def line_layout(desks):
    """Desks with their fronts at Blender -y on row y = 1.5; each desk's belt cell gets a
    feed behind it, straights fill the collector between feeds and run on to a corner,
    two straights carry the belt into the bag room and the end piece closes it.
    Returns {label: objs} and the Blender points of interest."""
    subjects = {}
    feeds = []
    for i, dx in enumerate(desks):
        subjects["desk_%d" % i] = place("checkin_desk", dx, 1.5)
        feeds.append(dx + 0.5)
        subjects["feed_%d" % i] = place("baggage_belt_feed", dx + 0.5, 2.5)
    x = feeds[0] + 1.0
    n = 0
    while x < feeds[-1] + 2.0:
        if x not in feeds:
            subjects["collector_%d" % n] = place("baggage_belt", x, 2.5, 90.0)
            n += 1
        x += 1.0
    corner_x = x
    subjects["corner"] = place("baggage_belt_corner", corner_x, 2.5, 180.0)
    subjects["run_0"] = place("baggage_belt", corner_x, 3.5)
    subjects["run_1"] = place("baggage_belt", corner_x, 4.5)
    subjects["end"] = place("baggage_belt_end", corner_x, 5.5)
    return subjects, corner_x


def join_gap(subjects):
    """The desk belt's back end (largest Blender y of its belt rails) against the feed
    inlet's front (smallest Blender y of the feed)."""
    desk_pts = [p for p in rap.world_points(subjects["desk_0"]) if p[0] > 2.0 + 0.05 and p[2] < 0.47]
    feed_pts = rap.world_points(subjects["feed_0"])
    back = max(p[1] for p in desk_pts)
    front = min(p[1] for p in feed_pts)
    desk_x = [p[0] for p in desk_pts]
    log("JOIN desk_belt_back_y=%.3f feed_front_y=%.3f gap_m=%.3f desk_belt_x=[%.3f, %.3f] feed_lane_x=[%.3f, %.3f]"
        % (back, front, front - back, min(desk_x), max(desk_x), 2.5 - bag.HALF_IN, 2.5 + bag.HALF_IN))
    return front - back


def join_plate():
    scene = rap.reset_scene(1600, 900, 1.5)
    floor_tiles(0, 6, 0, 7)
    subjects, corner_x = line_layout([2.0])
    join_gap(subjects)
    subjects["bag_desk"] = bag_on(2.5, 1.55, bag.BELT_TOP, 0.0, "bag_desk")
    subjects["bag_feed"] = bag_on(2.5, 2.55, bag.BELT_TOP, 90.0, "bag_feed")
    subjects["bag_corner"] = bag_on(corner_x - 0.15, 2.65, bag.BELT_TOP, 135.0, "bag_corner")
    rest = bag.BAG_REST_POS
    subjects["bag_rest"] = bag_on(corner_x, 5.5 - rest[2], rest[1], 0.0, "bag_rest", pitch_deg=bag.SLIDE_DEG)
    target = Vector((corner_x - 1.2, 3.4, 0.3))
    cam = game_camera(scene, target, 8.0, yaw_deg=-30.0)
    for name, objs in subjects.items():
        prove("join %s" % name, scene, cam, objs, need=0.10)
    save(scene, "join.png")


def distance_plate(distance, yaw_deg):
    scene = rap.reset_scene(1920, 1080, 1.0)
    subjects = {}
    x = 0.0
    for piece in PIECES:
        w = (bag.BAGGAGE[piece]["footprint"] or (1, 1))[0]
        subjects[piece] = place(piece, x + w / 2.0, 0.0)
        x += w + 1.0
    subjects["male"] = person("male", x + 0.5, 0.0, 0.0, "scale")
    rap.floor_plane((-2.0, -4.0), (x + 3.0, 5.0))
    target = Vector(((x + 1.0) / 2.0, 0.0, 0.3))
    cam = game_camera(scene, target, distance, yaw_deg)
    for name, objs in subjects.items():
        b = rap.screen_box(scene, cam, rap.world_points(objs))
        log("distance_%dm %s height_px=%.1f width_px=%.1f" % (distance, name, (b[3] - b[1]) * 1080,
                                                              (b[2] - b[0]) * 1920))
        prove("distance_%dm %s" % (distance, name), scene, cam, objs)
    save(scene, "distance_%dm.png" % distance)


def context_plate():
    scene = rap.reset_scene(1920, 1080, 1.2)
    floor_tiles(0, 14, 0, 10)
    for i in range(14):
        rap.import_glb(os.path.join(KIT_DIR, "wall.glb"), "wall_%d" % i, Matrix.Translation((i + 0.5, 10.0, 0.0)))
    room_lo, room_hi = (7.0, 5.0), (13.0, 10.0)
    room_tint(room_lo, room_hi)
    subjects, corner_x = line_layout([2.0, 4.0, 6.0])
    subjects["cart_loaded"] = place("baggage_cart", corner_x + 2.5, 7.0, 90.0)
    cart_empty = place("baggage_cart", corner_x + 2.5, 8.8, 90.0)
    hidden = [o for o in cart_empty if rap.base_name(o.name).startswith("Cart_Bags")]
    for o in hidden:
        o.hide_render = True
        o.hide_set(True)
    subjects["cart_empty"] = [o for o in cart_empty if o not in hidden]
    log("context cart_empty hid %d Cart_Bags objects" % len(hidden))
    for i, (bx, by, yaw) in enumerate(((2.5, 1.35, 0.0), (4.5, 2.5, 90.0), (6.2, 2.5, 90.0), (corner_x, 4.1, 0.0))):
        subjects["bag_%d" % i] = bag_on(bx, by, bag.BELT_TOP, yaw, "bag_%d" % i)
    rest = bag.BAG_REST_POS
    subjects["bag_rest"] = bag_on(corner_x, 5.5 - rest[2], rest[1], 0.0, "bag_rest", pitch_deg=bag.SLIDE_DEG)
    # Passengers in front of each desk's counter cell, facing the desk (Blender +y).
    for i, dx in enumerate((2.0, 4.0, 6.0)):
        subjects["passenger_%d" % i] = person("female" if i % 2 else "male", dx - 0.5, 0.5, 180.0, "p%d" % i)
    subjects["handler"] = person("male", corner_x + 0.9, 5.6, -90.0, "handler")
    target = Vector((6.5, 4.6, 0.4))
    cam = game_camera(scene, target, 20.0, yaw_deg=-20.0)
    for name, objs in subjects.items():
        prove("context %s" % name, scene, cam, objs, need=0.10)
    save(scene, "context.png")


def main():
    bag.register()
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["six", "join", "distance", "context"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known
    if "six" in stages:
        for piece in PIECES:
            six_axis(piece)
    if "join" in stages:
        join_plate()
    if "distance" in stages:
        distance_plate(30, -30.0)
        distance_plate(80, 0.0)
    if "context" in stages:
        context_plate()
    log("PLATES done stages=%s" % stages)


if __name__ == "__main__":
    main()
