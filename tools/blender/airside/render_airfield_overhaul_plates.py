"""Render Blender verification plates for the airfield visual overhaul.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\render_airfield_overhaul_plates.py'

Re-imports the WRITTEN .glb files from:
- game/assets/airside/props/ (taxi_edge_light, runway_edge_light_white,
  runway_edge_light_amber, runway_threshold_light, papi_light_bank, windsock)
- game/assets/airside/landmarks/ (tp_control_tower_01a, tp_radar_01a, tp_hangar_01a,
  tp_hangar_02a, tp_metal_fence_01a, tp_cistern_01a, tp_loading_truck_02a,
  tp_bus_01a, tp_pick_up_01a)

Outputs under tools/blender/out/airfield_overhaul/ (gitignored):
- six_axis/<stem>.png (6 orthographic views + 1 m reference cube)
- distance_fixtures.png (all authored lights + windsock + 1 m cube in a row)
- distance_vehicles.png (all 4 GSE vehicles + fence + 1 m cube in a row)
- context_complex.png (North Operations Complex layout with tp_plane_05a + 1 m cube)
- contact_sheet.png (combined contact sheet of the batch)
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "interior"))
import render_activities_plates as rap  # noqa: E402

REPO = rap.REPO
PROPS_DIR = os.path.join(REPO, "game", "assets", "airside", "props")
LANDMARKS_DIR = os.path.join(REPO, "game", "assets", "airside", "landmarks")
PLANE_05 = os.path.join(REPO, "game", "assets", "planes", "tp_plane_05a.glb")
OUT = os.path.join(REPO, "tools", "blender", "out", "airfield_overhaul")

FIXTURES = [
    "taxi_edge_light",
    "runway_edge_light_white",
    "runway_edge_light_amber",
    "runway_threshold_light",
    "papi_light_bank",
    "windsock",
]

LANDMARKS = [
    "tp_control_tower_01a",
    "tp_radar_01a",
    "tp_hangar_01a",
    "tp_hangar_02a",
    "tp_metal_fence_01a",
    "tp_cistern_01a",
    "tp_loading_truck_02a",
    "tp_bus_01a",
    "tp_pick_up_01a",
]


def g2b(x, y, z):
    return Vector((x, -z, y))


def place(path, label, at_g=(0.0, 0.0, 0.0), yaw_deg=0.0):
    xf = Matrix.Translation(g2b(*at_g)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    objs, _a, names, holder = rap.import_glb(path, label, xf)
    rap.log("%s imported materials=%s objects=%d" % (label, sorted(names), len(objs)))
    return objs, holder


def six_axis(glb_path, stem, line_px=1.2):
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, line_px)
    objs, _h = place(glb_path, stem)
    lo, hi = rap.bounds(objs)
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 1.0)
    gap = max(0.35, min(3.0, span * 0.08))
    ref = rap.cube((hi.x + gap + 0.5, lo.y - gap - 0.5, 0.5))
    sub = rap.world_points(objs)
    ref_pts = rap.world_points([ref])
    allp = np.concatenate([sub, ref_pts])
    scale = 0.0
    for _n, d, up in rap.VIEWS:
        inv = np.array(rap.look_rot(d, up).to_matrix().inverted())
        loc = allp @ inv.T
        scale = max(scale, loc[:, 0].max() - loc[:, 0].min(), loc[:, 1].max() - loc[:, 1].min())
    scale /= 1.0 - 2.0 * rap.MARGIN - 0.04
    rap.log("%s six_axis size_b=(%.2f, %.2f, %.2f) ortho=%.2f" % (stem, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, scale))
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        cam.data.clip_end = 800.0
        label = "%s six_axis %s" % (stem, name)
        rap.prove_in_frame(label + " subject", scene, cam, sub)
        rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        path = os.path.join(OUT, "six_axis", "%s_%s.png" % (stem, name))
        tiles.append(rap.over(rap.render(scene, path), rap.BACKDROP))
        bpy.data.objects.remove(cam)
    out = os.path.join(OUT, "six_axis", stem + ".png")
    rap.save_array(rap.grid(tiles, 3), out)
    return out


def distance_fixtures():
    scene = rap.reset_scene(1280, 640, 1.2)
    items = [
        ("taxi_edge_light", (-5.5, 0.0, 0.0)),
        ("runway_edge_light_white", (-4.2, 0.0, 0.0)),
        ("runway_edge_light_amber", (-2.9, 0.0, 0.0)),
        ("runway_threshold_light", (-1.5, 0.0, 0.0)),
        ("papi_light_bank", (3.2, 0.0, 0.0)),
        ("windsock", (8.5, 0.0, 0.0)),
    ]
    placed = []
    for stem, at_g in items:
        objs, _h = place(os.path.join(PROPS_DIR, stem + ".glb"), stem, at_g)
        placed.append((stem, objs))
    ref = rap.cube((-7.2, 0.0, 0.5))
    rap.floor_plane((-9.5, -4.0), (11.5, 6.0), z=0.0)
    all_pts = np.concatenate([rap.world_points(o) for _, o in placed] + [rap.world_points([ref])])
    cam = rap.persp_camera(scene, g2b(1.2, 10.5, 24.0), g2b(1.2, 2.4, 0.5), lens=32.0)
    cam.data.clip_end = 500.0
    rap.prove_in_frame("distance_fixtures all", scene, cam, all_pts, min_share=0.35)
    for stem, objs in placed:
        rap.visible_share("distance_fixtures " + stem, scene, cam, objs, samples=96, need=0.20)
    rap.visible_share("distance_fixtures cube", scene, cam, [ref], samples=64, need=0.20)
    out = os.path.join(OUT, "distance_fixtures.png")
    rap.save_array(rap.over(rap.render(scene, out), rap.BACKDROP), out)
    return out


def distance_vehicles():
    scene = rap.reset_scene(1280, 640, 1.2)
    items = [
        ("tp_metal_fence_01a", (-15.0, 0.0, 0.0), 15.0),
        ("tp_pick_up_01a", (-7.5, 0.0, 0.0), 35.0),
        ("tp_cistern_01a", (-1.5, 0.0, 0.0), 35.0),
        ("tp_loading_truck_02a", (5.5, 0.0, 0.0), 35.0),
        ("tp_bus_01a", (13.5, 0.0, 0.0), 35.0),
    ]
    placed = []
    for stem, at_g, yaw in items:
        objs, _h = place(os.path.join(LANDMARKS_DIR, stem + ".glb"), stem, at_g, yaw)
        placed.append((stem, objs))
    ref = rap.cube((-20.5, 0.0, 0.5))
    rap.floor_plane((-23.0, -10.0), (20.0, 10.0), z=0.0)
    all_pts = np.concatenate([rap.world_points(o) for _, o in placed] + [rap.world_points([ref])])
    cam = rap.persp_camera(scene, g2b(-1.5, 17.0, 47.0), g2b(-1.5, 1.8, 0.0), lens=32.0)
    cam.data.clip_end = 500.0
    rap.prove_in_frame("distance_vehicles all", scene, cam, all_pts, min_share=0.45)
    for stem, objs in placed:
        rap.visible_share("distance_vehicles " + stem, scene, cam, objs, samples=160, need=0.15)
    rap.visible_share("distance_vehicles cube", scene, cam, [ref], samples=64, need=0.20)
    out = os.path.join(OUT, "distance_vehicles.png")
    rap.save_array(rap.over(rap.render(scene, out), rap.BACKDROP), out)
    return out


def context_complex():
    """Verify the North Operations Complex layout in Blender before wiring Godot."""
    scene = rap.reset_scene(1600, 900, 1.0)
    # Local coords shifted by +410 in Godot Z so scene sits near origin.
    OZ = 410.0
    layout = [
        (LANDMARKS_DIR, "tp_control_tower_01a", (-92.0, 0.0, -422.0 + OZ), 0.0),
        (LANDMARKS_DIR, "tp_radar_01a", (-126.0, 0.0, -415.0 + OZ), 20.0),
        (LANDMARKS_DIR, "tp_hangar_01a", (12.0, 0.0, -422.0 + OZ), 0.0),
        (LANDMARKS_DIR, "tp_hangar_02a", (96.0, 0.0, -428.0 + OZ), 0.0),
        (PROPS_DIR, "windsock", (-56.0, 0.0, -390.0 + OZ), 90.0),
        (LANDMARKS_DIR, "tp_cistern_01a", (-52.0, 0.0, -412.0 + OZ), 15.0),
        (LANDMARKS_DIR, "tp_bus_01a", (-32.0, 0.0, -398.0 + OZ), 90.0),
        (LANDMARKS_DIR, "tp_loading_truck_02a", (62.0, 0.0, -398.0 + OZ), -75.0),
        (LANDMARKS_DIR, "tp_pick_up_01a", (-65.0, 0.0, -402.0 + OZ), -25.0),
        (PROPS_DIR, "papi_light_bank", (-100.0, 0.0, -372.5 + OZ), -90.0),
    ]
    placed = []
    for folder, stem, at_g, yaw in layout:
        objs, _h = place(os.path.join(folder, stem + ".glb"), stem, at_g, yaw)
        placed.append((stem, objs))
    # Add a row of fence segments along west flank of north edge and Plane 05 on runway for scale.
    for k in range(4):
        place(os.path.join(LANDMARKS_DIR, "tp_metal_fence_01a.glb"), "fence_%d" % k, (-175.0 + k * 7.85, 0.0, -380.0 + OZ), 0.0)
    plane_objs, _h = place(PLANE_05, "tp_plane_05a", (12.0, 0.0, -352.0 + OZ), 90.0)
    placed.append(("tp_plane_05a", plane_objs))
    ref = rap.cube((-45.0, 38.0, 0.5))
    rap.floor_plane((-190.0, -65.0), (145.0, 65.0), z=0.0)

    all_pts = np.concatenate([rap.world_points(o) for _, o in placed] + [rap.world_points([ref])])
    cam = rap.persp_camera(scene, g2b(-15.0, 185.0, 290.0), g2b(-12.0, 12.0, -5.0), lens=24.0)
    cam.data.clip_end = 1500.0
    rap.prove_in_frame("context_complex all", scene, cam, all_pts, min_share=0.45)
    for stem, objs in placed:
        rap.visible_share("context_complex " + stem, scene, cam, objs, samples=96, need=0.15)
    out = os.path.join(OUT, "context_complex.png")
    rap.save_array(rap.over(rap.render(scene, out), rap.BACKDROP), out)
    return out


def make_contact_sheet(paths):
    tiles = []
    for p in paths:
        img = bpy.data.images.load(p)
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        bpy.data.images.remove(img)
        arr = px.reshape(h, w, 4)
        f = max(1, int(math.ceil(max(w / 640.0, h / 420.0))))
        tiles.append(rap.downscale(arr, f))
    th = max(t.shape[0] for t in tiles)
    tw = max(t.shape[1] for t in tiles)
    padded = []
    for t in tiles:
        canvas = np.empty((th, tw, 4), dtype=np.float32)
        canvas[:, :] = (0.08, 0.08, 0.09, 1.0)
        canvas[th - t.shape[0]:, :t.shape[1]] = t
        padded.append(canvas)
    out = os.path.join(OUT, "contact_sheet.png")
    rap.save_array(rap.grid(padded, 4), out)
    rap.log("CONTACT_SHEET saved %s tiles=%d" % (out, len(tiles)))
    return out


def main():
    os.makedirs(os.path.join(OUT, "six_axis"), exist_ok=True)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    skip_six = "skip-six" in argv
    paths = []
    for stem in FIXTURES:
        p = os.path.join(OUT, "six_axis", stem + ".png")
        if skip_six and os.path.exists(p):
            paths.append(p)
        else:
            paths.append(six_axis(os.path.join(PROPS_DIR, stem + ".glb"), stem, line_px=1.4))
    for stem in LANDMARKS:
        p = os.path.join(OUT, "six_axis", stem + ".png")
        if skip_six and os.path.exists(p):
            paths.append(p)
        else:
            paths.append(six_axis(os.path.join(LANDMARKS_DIR, stem + ".glb"), stem, line_px=1.0))
    paths.append(distance_fixtures())
    paths.append(distance_vehicles())
    paths.append(context_complex())
    make_contact_sheet(paths)
    rap.log("PLATES_DONE count=%d" % len(paths))


if __name__ == "__main__":
    main()
