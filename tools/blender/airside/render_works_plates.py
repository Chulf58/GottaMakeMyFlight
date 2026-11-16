"""Blender plates of the construction-works props (board ecd67e67, S8b phase 1).

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\airside\\render_works_plates.py' [-- stage ...]

Stages (all but survey when none is named): survey, six, distance, lineup, sheet.
Everything is written under tools/blender/out/s8b_assets/ (gitignored); nothing in
game/ is touched.
- survey_small.png, survey_large.png: the vendor candidates straight from the FBX
  (cones, barriers, fences, brick piles; excavators, dump trailers) in a row with a
  male passenger and a 1 m cube, for picking one of each. Order is logged (SURVEY).
- six_axis/<stem>.png: the WRITTEN .glb from game/assets/airside/props/works/ in six
  orthographic views at one scale, true scale, with a 1 m cube.
- distance/<stem>.png: the written prop beside a male passenger and a 1 m cube from
  60 m at 35 degrees elevation.
- lineup.png: all six written props in a row beside the loading truck
  (game/assets/vehicles/tp_loading_truck_01a.glb) and a passenger, from 45 m.
- contact_sheet.png: every plate above, downscaled.
Each plate proves its subjects are in frame (every vertex inside the margin) and the
perspective plates that the subjects are visible (camera rays reach them first); on
failure PROBE_INVALID and exit 1. These are Blender plates (an emission copy of the
toon shader and a Freestyle outline); the in-engine look needs a windowed Godot render.
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
import convert_works_props as cw  # noqa: E402
import render_activities_plates as rap  # noqa: E402

OUT = os.path.join(cw.REPO, "tools", "blender", "out", "s8b_assets")
TRUCK = os.path.join(cw.REPO, "game", "assets", "vehicles", "tp_loading_truck_01a.glb")
TC_RAMP = os.path.join(cw.GAME_TEXTURES, "tc_toon_ramp_01a_d.png")
TFP_RAMP = os.path.join(cw.BIRDS, "tfp_toon_ramp_1f.png")
TI_RAMP_PNG = os.path.join(cw.OUT_DIR, "ti_toon_ramp_1a.png")
TI_RAMP_PSD = os.path.join(cw.INDUSTRIES, "Textures", "TI_Toon_Ramp_1A.psd")
EXC_PNG = cw.ATLAS["TI_Excavator_1A_D"]
EXC_PSD = os.path.join(cw.INDUSTRIES, "Textures", "Excavator_1A_D.psd")
MARGIN = rap.MARGIN
BACKDROP = rap.BACKDROP
log = rap.log
invalid = rap.invalid
STEMS = list(cw.PROPS)
SURVEY_SMALL = [
    ("Toon City", "Traffic_Cone_1A"), ("Toon City", "Traffic_Cone_2A"), ("Toon City", "Traffic_Cone_2B"),
    ("Toon City", "Concrete_Barrier_1A"), ("Toon City", "Concrete_Barrier_2A"),
    ("Toon City", "Metal_Fence_2A"), ("Toon City", "Metal_Fence_2B"), ("Toon City", "Metal_Fence_2C"),
    ("Toon City", "Metal_Fence_3A"), ("Toon City", "Metal_Fence_3B"),
    ("Toon Industries", "Brick_Pile_1A"), ("Toon Industries", "Brick_Pile_1B"), ("Toon Industries", "Brick_Pile_1C"),
    ("Toon Industries", "Brick_Pile_1D"), ("Toon Industries", "Brick_Pile_1E"),
]
SURVEY_LARGE = [
    ("Toon Industries", "Excavator_1A"), ("Toon Industries", "Excavator_1B"),
    ("Toon Farm Pack", "TFP_Dump_Trailer_01A"), ("Toon Farm Pack", "TFP_Dump_Trailer_01B"),
]
# The Toon Industries fences sample that pack's own Road_1A_D.psd (a different file
# from the Toon City one), so the fence survey binds it while INDUSTRIES_ROAD is set.
SURVEY_FENCE = [("Toon Industries", "Traffic_Cone_1B")] + [
    ("Toon Industries", "Metal_Fence_%s" % v) for v in ("1A", "1B", "1C", "1D", "2A", "2B", "2C", "2D", "3A", "3B")
]
INDUSTRIES_ROAD = {"on": False}
_base_plate_material = rap.plate_material


def first(*paths):
    return next((p for p in paths if os.path.exists(p)), paths[-1])


def works_material(name):
    """Plate materials for the works props, by game or vendor material name."""
    n = rap.base_name(name)
    if n == "Road_1A_D" and INDUSTRIES_ROAD["on"]:
        return rap.toon_material("ti_road", os.path.join(cw.INDUSTRIES, "Textures", "Road_1A_D.psd"),
                                 first(TI_RAMP_PNG, TI_RAMP_PSD))
    if n in ("Road_1A_D", "TC_Road_1A_D"):
        return rap.toon_material("tc_road", cw.ATLAS["TC_Road_1A_D"], TC_RAMP)
    if n in ("Props_2A_D", "TC_Props_2A_D"):
        return rap.toon_material("tc_props", cw.ATLAS["TC_Props_2A_D"], TC_RAMP)
    if n in ("Excavator_1A_D", "TI_Excavator_1A_D"):
        return rap.toon_material("ti_excavator", first(EXC_PNG, EXC_PSD), first(TI_RAMP_PNG, TI_RAMP_PSD))
    if n in ("TFP_Atlas_1A", "TFP_Atlas_1A_D", "TFP_Atlas_Logos_1A"):
        return rap.toon_material("tfp_atlas", cw.ATLAS["TFP_Atlas_1A_D"], TFP_RAMP)
    city = os.path.join(cw.CITY, "Textures", n + ".psd")
    if os.path.exists(city):
        return rap.toon_material("city_" + n, city, TC_RAMP)
    return _base_plate_material(name)


rap.plate_material = works_material


def glb(stem):
    return os.path.join(cw.OUT_DIR, stem + ".glb")


def place_glb(path, label, x=0.0, y=0.0, yaw_deg=0.0):
    xf = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    objs, _a, names, _h = rap.import_glb(path, label, xf)
    log("%s imported materials=%s objects=%d" % (label, sorted(names), len(objs)))
    return objs


def ground_rect(objs):
    lo, hi = rap.bounds(objs)
    return lo, hi


def view_dir(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))


def shoot(name, scene, subjects, centre, az_deg, el_deg, dist, lens=35.0, need=0.10):
    cam = rap.persp_camera(scene, centre + view_dir(az_deg, el_deg) * dist, centre, lens=lens)
    log("%s camera_to_centre=%.1f m az=%.0f el=%.0f lens=%.0f" % (name, (cam.location - centre).length, az_deg, el_deg, lens))
    for label, objs in subjects.items():
        rap.prove_in_frame("%s %s" % (name, label), scene, cam, rap.world_points(objs))
        rap.visible_share("%s %s" % (name, label), scene, cam, objs, need=need)
    path = os.path.join(OUT, name + ".png")
    arr = rap.render(scene, os.path.join(OUT, "raw", name + ".png"))
    rap.save_array(rap.over(arr, BACKDROP), path)
    bpy.data.objects.remove(cam)
    return path


# ---------------------------------------------------------------- survey


def survey(name, picks, gap):
    scene = rap.reset_scene(1800, 700, 1.2)
    subjects = {}
    x = 0.0
    for pack, model in picks:
        fbx = os.path.join(cw.SERIES, pack, "Models", model + ".fbx")
        objs, names, holder = rap.import_fbx(fbx, model, placeholder=(0.9, 0.2, 0.8))
        for o in list(objs):
            if "_LOD1" in o.name or "_LOD2" in o.name:
                objs.remove(o)
                bpy.data.objects.remove(o, do_unlink=True)
        bpy.context.view_layer.update()
        lo, hi = rap.bounds(objs)
        holder.location.x = x - lo.x
        holder.location.y = -(lo.y + hi.y) / 2
        bpy.context.view_layer.update()
        log("SURVEY %s %s at_x=%.2f size_m=(%.2f, %.2f, %.2f) materials=%s"
            % (name, model, x, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, sorted(names)))
        subjects[model] = objs
        x += hi.x - lo.x + gap
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((x + 0.3, 0.0, 0.0)))
    subjects["male"] = man
    rap.cube((x + 1.8, 0.0, 0.5))
    x += 2.5
    rap.floor_plane((-2.0, -6.0), (x + 1.0, 6.0))
    centre = Vector((x / 2.0, 0.0, 1.0))
    dist = (x / 2.0 + 3.0) * 2.3
    return shoot(name, scene, subjects, centre, -20.0, 22.0, dist, lens=35.0, need=0.05)


# ---------------------------------------------------------------- six-axis


def six_axis(stem):
    scene = rap.reset_scene(rap.SIX_PX, rap.SIX_PX, 1.5)
    objs = place_glb(glb(stem), stem)
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
    log("%s six_axis size_m godot_xyz=(%.3f, %.3f, %.3f) blender_min=(%.3f, %.3f, %.3f) ortho=%.3f px_per_m=%.1f"
        % (stem, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y, lo.x, lo.y, lo.z, scale, rap.SIX_PX / scale))
    tiles = []
    for name, d, up in rap.VIEWS:
        cam = rap.ortho_camera(scene, rap.look_rot(d, up), allp, scale)
        label = "%s six_axis %s" % (stem, name)
        b_sub = rap.prove_in_frame(label + " subject", scene, cam, sub)
        b_ref = rap.prove_in_frame(label + " cube", scene, cam, ref_pts)
        apart = b_ref[0] > b_sub[2] or b_ref[2] < b_sub[0] or b_ref[1] > b_sub[3] or b_ref[3] < b_sub[1]
        log("%s cube_disjoint=%s" % (label, apart))
        if not apart:
            invalid("%s: the reference cube overlaps the subject on screen" % label)
        path = os.path.join(OUT, "six_axis", "%s_%s.png" % (stem, name))
        tiles.append(rap.over(rap.render(scene, path), BACKDROP))
        bpy.data.objects.remove(cam)
    out = os.path.join(OUT, "six_axis", stem + ".png")
    rap.save_array(rap.grid(tiles, 3), out)
    return out


# ---------------------------------------------------------------- distance and lineup


def distance(stem):
    scene = rap.reset_scene(1280, 720, 1.0)
    objs = place_glb(glb(stem), stem)
    lo, hi = rap.bounds(objs)
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((hi.x + 1.0, (lo.y + hi.y) / 2, 0.0)))
    rap.cube((hi.x + 2.6, (lo.y + hi.y) / 2, 0.5))
    rap.floor_plane((lo.x - 12.0, lo.y - 12.0), (hi.x + 14.0, hi.y + 12.0))
    centre = Vector(((lo.x + hi.x + 3.0) / 2, (lo.y + hi.y) / 2, 0.5))
    return shoot("distance/" + stem, scene, {stem: objs, "male": man}, centre, -35.0, 35.0, 60.0, need=0.05)


def lineup():
    scene = rap.reset_scene(1600, 900, 1.0)
    subjects = {}
    truck = place_glb(TRUCK, "tp_loading_truck_01a")
    lo, hi = rap.bounds(truck)
    holder = next(o for o in bpy.data.objects if o.name.startswith("HOLD_tp_loading_truck"))
    holder.location.x -= hi.x
    holder.location.y -= (lo.y + hi.y) / 2
    bpy.context.view_layer.update()
    subjects["truck"] = truck
    x = 2.0
    for stem in STEMS:
        objs = place_glb(glb(stem), stem)
        lo, hi = rap.bounds(objs)
        h = next(o for o in bpy.data.objects if o.name == "HOLD_" + stem)
        h.location.x = x - lo.x
        h.location.y = -(lo.y + hi.y) / 2
        bpy.context.view_layer.update()
        lo2, hi2 = rap.bounds(objs)
        log("LINEUP %s x=[%.2f, %.2f] y=[%.2f, %.2f] top=%.2f" % (stem, lo2.x, hi2.x, lo2.y, hi2.y, hi2.z))
        subjects[stem] = objs
        x += hi.x - lo.x + 1.5
    man, _acts, _arm, _h = rap.add_character("male", Matrix.Translation((x + 0.3, 0.0, 0.0)))
    subjects["male"] = man
    rap.cube((x + 1.8, 0.0, 0.5))
    rap.floor_plane((-14.0, -10.0), (x + 6.0, 10.0))
    centre = Vector(((x - 10.0) / 2, 0.0, 1.0))
    return shoot("lineup", scene, subjects, centre, -25.0, 35.0, 45.0, need=0.05)


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
        canvas[th - t.shape[0]:, : t.shape[1]] = t
        padded.append(canvas)
    rap.save_array(rap.grid(padded, 3), os.path.join(OUT, "contact_sheet.png"))


def main():
    for sub in ("six_axis", "distance", "raw", os.path.join("raw", "distance")):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    known = ["survey", "six", "distance", "lineup", "sheet"]
    unknown = [s for s in only if s not in known]
    if unknown:
        invalid("unknown stages %s; known: %s" % (unknown, known))
    stages = only or known[1:]
    made = []
    if "survey" in stages:
        made.append(survey("survey_small", SURVEY_SMALL, 1.2))
        made.append(survey("survey_large", SURVEY_LARGE, 2.0))
        INDUSTRIES_ROAD["on"] = True
        made.append(survey("survey_fence", SURVEY_FENCE, 1.2))
        INDUSTRIES_ROAD["on"] = False
    if "six" in stages:
        made.extend(six_axis(s) for s in STEMS)
    if "distance" in stages:
        made.extend(distance(s) for s in STEMS)
    if "lineup" in stages:
        made.append(lineup())
    if "sheet" in stages:
        names = ["six_axis/%s.png" % s for s in STEMS] + ["distance/%s.png" % s for s in STEMS] + ["lineup.png"]
        paths = [os.path.join(OUT, n) for n in names if os.path.exists(os.path.join(OUT, n))]
        sheet(paths)
    log("PLATES done stages=%s made=%d" % (stages, len(made)))


if __name__ == "__main__":
    main()
