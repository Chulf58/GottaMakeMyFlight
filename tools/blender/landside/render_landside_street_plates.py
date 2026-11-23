"""Render verification plates from the WRITTEN landside street GLB files.

Run from repo root (WSL -> Windows Blender):
    timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python-exit-code 1 \
        --python tools/blender/landside/render_landside_street_plates.py < /dev/null

Outputs under tools/blender/out/landside_overhaul/ (gitignored):
  - portal_ortho_{N,S,W,E,top,bottom}.png + portal_6axis_sheet.png
  - portal_persp_hero.png + portal_persp_mouth.png
  - road_ext_ortho_{N,S,W,E,top,bottom}.png + road_ext_6axis_sheet.png
  - props_ortho_{N,S,W,E,top,bottom}.png + props_6axis_sheet.png + props_hero_lineup.png
  - incontext_seam_closeup.png + incontext_east_assembly.png
"""

import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Quaternion, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ASSETS = os.path.join(REPO, "game", "assets", "landside")
DECOR = os.path.join(REPO, "game", "assets", "decor")
BUILDINGS = os.path.join(REPO, "game", "assets", "buildings")
VEHICLES = os.path.join(REPO, "game", "assets", "vehicles")
OUT = os.path.join(REPO, "tools", "blender", "out", "landside_overhaul")


def g2b(gx, gy, gz):
    """Godot (X east, Y up, Z south) -> Blender (X, -Z, Y)."""
    return Vector((gx, -gz, gy))


def die(msg):
    print("PROBE_INVALID", msg, flush=True)
    sys.exit(1)


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sh.show_object_outline = False
    sh.show_cavity = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.76, 0.84, 0.92)
    scene.display.render_aa = "FXAA"
    scene.render.image_settings.file_format = "PNG"

    cam = bpy.data.objects.new("PlateCam", bpy.data.cameras.new("PlateCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam

    red = bpy.data.materials.new("RefCubeRed")
    red.diffuse_color = (0.90, 0.08, 0.08, 1.0)
    return scene, cam, red


def import_glb_placed(path, prefix, gx=0.0, gy=0.0, gz=0.0, rot_y_rad=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [o for o in bpy.data.objects if o not in before]
    for o in added:
        o.name = "%s__%s" % (prefix, o.name)
    roots = [o for o in added if o.parent is None]
    for r in roots:
        r.location = g2b(gx, gy, gz)
        if abs(rot_y_rad) > 1e-6:
            q_world_up = Quaternion((0.0, 0.0, 1.0), rot_y_rad)
            if r.rotation_mode == "QUATERNION":
                r.rotation_quaternion = q_world_up @ r.rotation_quaternion
            else:
                q_cur = r.rotation_euler.to_quaternion()
                r.rotation_euler = (q_world_up @ q_cur).to_euler(r.rotation_mode)
    bpy.context.view_layer.update()
    return added


def add_ref_cube(red, gx, gy, gz):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(gx, gy + 0.5, gz))
    cube = bpy.context.active_object
    cube.name = "RefCube_1m"
    cube.data.materials.append(red)
    bpy.context.view_layer.update()
    return cube


def aim(cam, eye, target, ortho_scale=None, vfov_deg=45.0, ortho_euler=None):
    cam.location = g2b(*eye)
    if ortho_euler is not None:
        cam.rotation_euler = ortho_euler
    else:
        d = g2b(*target) - g2b(*eye)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_start = 0.2
    cam.data.clip_end = 2000.0
    if ortho_scale is not None:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho_scale
    else:
        cam.data.type = "PERSP"
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(vfov_deg)
    bpy.context.view_layer.update()


def box_corners_godot(bx):
    x0, x1, y0, y1, z0, z1 = bx
    return [g2b(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def first_hit(scene, cam, b_point):
    if cam.data.type == "ORTHO":
        fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
        origin = b_point - fwd * 900.0
    else:
        origin = cam.matrix_world.translation
    direction = (b_point - origin).normalized()
    res = scene.ray_cast(bpy.context.view_layer.depsgraph, origin, direction)
    return res[4].name if res[0] and res[4] else None


def prove_and_render(scene, cam, tag, subject_box, cube, size, ray_checks=()):
    scene.render.resolution_x, scene.render.resolution_y = size
    bpy.context.view_layer.update()

    co = [world_to_camera_view(scene, cam, p) for p in box_corners_godot(subject_box)]
    xs, ys, zs = [c.x for c in co], [c.y for c in co], [c.z for c in co]
    print(
        "INFRAME %s x=%.3f..%.3f y=%.3f..%.3f zmin=%.2f"
        % (tag, min(xs), max(xs), min(ys), max(ys), min(zs)),
        flush=True,
    )
    if min(xs) < 0.01 or max(xs) > 0.99 or min(ys) < 0.01 or max(ys) > 0.99 or min(zs) <= 0.0:
        die("%s subject out of frame" % tag)

    if cube is not None:
        c = world_to_camera_view(scene, cam, cube.location)
        hit = first_hit(scene, cam, cube.location)
        print("REFCUBE %s uv=(%.3f,%.3f) hit=%s" % (tag, c.x, c.y, hit), flush=True)
        if not (0.015 < c.x < 0.985 and 0.015 < c.y < 0.985):
            die("%s cube out of frame" % tag)
        if hit != cube.name:
            die("%s cube occluded by %s" % (tag, hit))

    for label, g_pt, expected_substr in ray_checks:
        hit = first_hit(scene, cam, g2b(*g_pt))
        print("RAYCHECK %s %s hit=%s" % (tag, label, hit), flush=True)
        if not hit or expected_substr not in hit:
            die("%s raycheck %s got %s expected %s" % (tag, label, hit, expected_substr))

    path = os.path.join(OUT, tag + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    print("PLATE %s (%dx%d)" % (path, w, h), flush=True)
    return px


def make_grid_sheet(name, tiles, cols=2, tile_w=780):
    """Assemble labeled tiles into a crisp cols-wide contact sheet without huge vertical bloat."""
    resized = []
    for _tag, px in tiles:
        h, w = px.shape[:2]
        scale = tile_w / float(w)
        nh = max(1, int(round(h * scale)))
        ys = np.minimum((np.arange(nh) / scale).astype(int), h - 1)
        xs = np.minimum((np.arange(tile_w) / scale).astype(int), w - 1)
        resized.append(px[ys][:, xs])

    pad = 8
    rows_out = []
    for i in range(0, len(resized), cols):
        chunk = resized[i : i + cols]
        while len(chunk) < cols:
            chunk.append(np.ones_like(chunk[0]))
        max_h = max(c.shape[0] for c in chunk)
        padded = []
        for c in chunk:
            if c.shape[0] < max_h:
                bg = np.ones((max_h, tile_w, 4), dtype=np.float32) * 0.92
                bg[: c.shape[0], :, :] = c
                padded.append(bg)
            else:
                padded.append(c)
        row_img = padded[0]
        for p in padded[1:]:
            row_img = np.concatenate([row_img, np.ones((max_h, pad, 4), dtype=np.float32), p], axis=1)
        rows_out.append(row_img)
        rows_out.append(np.ones((pad, row_img.shape[1], 4), dtype=np.float32))

    sheet = np.concatenate(rows_out[::-1], axis=0)
    out_path = os.path.join(OUT, name)
    im = bpy.data.images.new(name, sheet.shape[1], sheet.shape[0], alpha=True)
    im.pixels = sheet.ravel()
    im.filepath_raw = out_path
    im.file_format = "PNG"
    im.save()
    print("PLATE %s (%dx%d)" % (out_path, sheet.shape[1], sheet.shape[0]), flush=True)


# ------------------------------------------------------------ 1. Portal plates


def render_portal_plates():
    box = (-4.45, 25.5, -0.12, 6.81, -11.5, 11.5)
    views = [
        # tag, eye, target, cube_gpos, ortho_scale, size, euler
        ("portal_ortho_N", (10.5, 3.3, -200), (10.5, 3.3, 0), (-5.5, 0.0, -12.3), 38.0, (900, 420), None),
        ("portal_ortho_S", (10.5, 3.3, 200), (10.5, 3.3, 0), (-5.5, 0.0, 12.3), 38.0, (900, 420), None),
        ("portal_ortho_W", (-200, 3.3, 0), (10.5, 3.3, 0), (-5.8, 0.0, -7.2), 28.0, (800, 420), None),
        ("portal_ortho_E", (200, 3.3, 0), (10.5, 3.3, 0), (26.6, 0.0, 0.0), 28.0, (800, 420), None),
        ("portal_ortho_top", (10.5, 200, 0), (10.5, 0, 0), (-5.8, 0.0, 0.0), 38.0, (900, 650), Euler((0.0, 0.0, 0.0))),
        ("portal_ortho_bottom", (10.5, -200, 0), (10.5, 0, 0), (-5.8, -1.3, 0.0), 38.0, (900, 650), Euler((math.pi, 0.0, 0.0))),
    ]
    tiles = []
    for tag, eye, tgt, cpos, osc, size, euler in views:
        scene, cam, red = setup_scene()
        scene.display.render_aa = "OFF"
        import_glb_placed(os.path.join(ASSETS, "landside_tunnel_portal.glb"), "Portal")
        cube = add_ref_cube(red, *cpos)
        aim(cam, eye, tgt, ortho_scale=osc, ortho_euler=euler)
        # In W view (looking into tunnel mouth), verify ray down the centre hits solid Portal_Interior backstop.
        checks = [("mouth_backstop", (19.2, 2.0, 0.0), "Portal_Interior")] if tag == "portal_ortho_W" else ()
        tiles.append((tag, prove_and_render(scene, cam, tag, box, cube, size, checks)))
    make_grid_sheet("portal_6axis_sheet.png", tiles, cols=2, tile_w=780)

    # 3/4 hero + straight mouth shot
    for tag, eye, tgt, cpos, checks in (
        ("portal_persp_hero", (-22.0, 12.5, 22.0), (8.0, 2.6, 0.0), (-5.8, 0.0, 8.2), ()),
        ("portal_persp_mouth", (-22.0, 2.2, 1.5), (12.0, 2.2, 0.0), (-5.8, 0.0, -7.2), [("backstop", (19.2, 2.0, 0.0), "Portal_Interior")]),
    ):
        scene, cam, red = setup_scene()
        import_glb_placed(os.path.join(ASSETS, "landside_tunnel_portal.glb"), "Portal")
        cube = add_ref_cube(red, *cpos)
        aim(cam, eye, tgt, vfov_deg=44.0)
        prove_and_render(scene, cam, tag, box, cube, (1280, 720), checks)


# ------------------------------------------------------------ 2. Road extension plates


def render_road_ext_plates():
    box = (0.0, 113.0, 0.0, 0.20, -6.0, 6.0)
    views = [
        ("road_ext_ortho_N", (56.5, 0.0, -300), (56.5, 0.0, 0), (-1.5, 0.0, -7.0), 124.0, (1200, 220), None, box),
        ("road_ext_ortho_S", (56.5, 0.0, 300), (56.5, 0.0, 0), (-1.5, 0.0, 7.0), 124.0, (1200, 220), None, box),
        ("road_ext_ortho_W", (-120, 0.4, 0), (10, 0.0, 0), (-1.2, 0.0, -7.2), 18.0, (900, 280), None, (0.0, 20.0, 0.0, 0.20, -6.0, 6.0)),
        ("road_ext_ortho_E", (220, 0.4, 0), (100, 0.0, 0), (114.5, 0.0, 0.0), 18.0, (900, 280), None, (95.0, 113.0, 0.0, 0.20, -6.0, 6.0)),
        ("road_ext_ortho_top", (56.5, 300, 0), (56.5, 0, 0), (56.5, 0.0, -7.2), 124.0, (1200, 240), Euler((0.0, 0.0, 0.0)), box),
        ("road_ext_ortho_bottom", (56.5, -300, 0), (56.5, 0, 0), (56.5, -1.3, -7.2), 124.0, (1200, 240), Euler((math.pi, 0.0, 0.0)), box),
    ]
    tiles = []
    for tag, eye, tgt, cpos, osc, size, euler, sbox in views:
        scene, cam, red = setup_scene()
        scene.display.render_aa = "OFF"
        import_glb_placed(os.path.join(ASSETS, "landside_road_ext.glb"), "RoadExt")
        cube = add_ref_cube(red, *cpos)
        aim(cam, eye, tgt, ortho_scale=osc, ortho_euler=euler)
        tiles.append((tag, prove_and_render(scene, cam, tag, sbox, cube, size)))
    make_grid_sheet("road_ext_6axis_sheet.png", tiles, cols=2, tile_w=780)


# ------------------------------------------------------------ 3. Street props lineup


def render_props_plates():
    # Ordered west-to-east with clear spacing so zero overlap on N/S/top/bottom,
    # plus staggered Z slightly on W/E? Wait: keep Z=0 for N/S/top/bottom exact elevation!
    lineup = [
        ("Bollard", ASSETS, "landside_bollard.glb", -14.0, 0.0, 0.0),
        ("Trash", DECOR, "tc_trash_can_1a.glb", -11.5, 0.0, 0.0),
        ("Bench", DECOR, "tc_bench_1a.glb", -9.0, 0.0, 0.0),
        ("Sign", ASSETS, "tp_signpost_01a.glb", -6.0, 0.0, 0.0),
        ("Light1A", ASSETS, "tc_streetlight_1a.glb", -2.5, 0.0, 0.0),
        ("Light2A", ASSETS, "tc_streetlight_2a.glb", 2.0, 0.0, 0.0),
        ("Bush2A", ASSETS, "tc_bush_2a.glb", 5.0, 0.0, 0.0),
        ("Tree2D", ASSETS, "tc_tree_2d.glb", 8.5, 0.0, 0.0),
        ("Tree3A", ASSETS, "tc_tree_3a.glb", 12.5, 0.0, 0.0),
        ("Pine02A", ASSETS, "tp_pine_tree_02a.glb", 16.5, 0.0, 0.0),
    ]
    box = (-15.0, 18.2, 0.0, 6.3, -2.0, 2.0)

    def load_lineup(red, cpos):
        scene, cam, _r = setup_scene()
        for prefix, folder, fname, gx, gy, gz in lineup:
            import_glb_placed(os.path.join(folder, fname), prefix, gx, gy, gz)
        cube = add_ref_cube(red, *cpos)
        return scene, cam, cube

    # 6-axis ortho views of the whole lineup (with 1 m RefCube between Light1A and Bollard/Trash or at x=-15.8)
    ortho_specs = [
        ("props_ortho_N", (1.6, 3.0, -200), (1.6, 3.0, 0), (-15.6, 0.0, 0.0), 38.0, (1200, 320), None),
        ("props_ortho_S", (1.6, 3.0, 200), (1.6, 3.0, 0), (-15.6, 0.0, 0.0), 38.0, (1200, 320), None),
        ("props_ortho_W", (-200, 3.0, 0), (1.6, 3.0, 0), (-16.0, 0.0, -3.2), 12.0, (700, 560), None),
        ("props_ortho_E", (200, 3.0, 0), (1.6, 3.0, 0), (19.0, 0.0, -3.2), 12.0, (700, 560), None),
        ("props_ortho_top", (1.6, 200, 0), (1.6, 0, 0), (-15.6, 0.0, 0.0), 38.0, (1200, 260), Euler((0.0, 0.0, 0.0))),
        ("props_ortho_bottom", (1.6, -200, 0), (1.6, 0, 0), (-15.6, -1.2, 0.0), 38.0, (1200, 260), Euler((math.pi, 0.0, 0.0))),
    ]
    tiles = []
    for tag, eye, tgt, cpos, osc, size, euler in ortho_specs:
        scene, cam, red = setup_scene()
        scene.display.render_aa = "OFF"
        for prefix, folder, fname, gx, gy, gz in lineup:
            import_glb_placed(os.path.join(folder, fname), prefix, gx, gy, gz)
        cube = add_ref_cube(red, *cpos)
        aim(cam, eye, tgt, ortho_scale=osc, ortho_euler=euler)
        tiles.append((tag, prove_and_render(scene, cam, tag, box, cube, size)))
    make_grid_sheet("props_6axis_sheet.png", tiles, cols=2, tile_w=780)

    # Perspective hero lineup with 1 m reference cube clearly visible next to bollard & bench
    scene, cam, red = setup_scene()
    for prefix, folder, fname, gx, gy, gz in lineup:
        import_glb_placed(os.path.join(folder, fname), prefix, gx, gy, gz)
    cube = add_ref_cube(red, -16.0, 0.0, 1.5)
    aim(cam, (2.0, 8.5, 32.0), (1.6, 2.4, 0.0), vfov_deg=40.0)
    prove_and_render(scene, cam, "props_hero_lineup", box, cube, (1400, 620))


# ------------------------------------------------------------ 4. In-context seam & portal+car assembly


def render_incontext_plates():
    # A. Seam close-up at x = +43.0 where tp_airport_site.glb Road meets landside_road_ext.glb
    scene, cam, red = setup_scene()
    import_glb_placed(os.path.join(BUILDINGS, "tp_airport_site.glb"), "Site", 0.0, 0.0, -80.0)
    import_glb_placed(os.path.join(ASSETS, "landside_road_ext.glb"), "EastExt", 43.0, 0.0, -46.0)
    import_glb_placed(os.path.join(ASSETS, "landside_crosswalk.glb"), "Xwalk", -2.0, 0.1, 0.0)
    import_glb_placed(os.path.join(ASSETS, "tc_streetlight_2a.glb"), "LightEast", 52.0, 0.2, -51.4, math.pi * 0.5)
    import_glb_placed(os.path.join(ASSETS, "landside_bollard.glb"), "Bollard", 36.0, 0.2, -59.0)
    cube = add_ref_cube(red, 43.0, 0.2, -51.2)
    aim(cam, (32.0, 12.0, -24.0), (44.0, 0.2, -47.0), vfov_deg=44.0)
    prove_and_render(
        scene, cam, "incontext_seam_closeup",
        (35.0, 55.0, 0.0, 6.0, -59.2, -40.0),
        cube, (1280, 720),
        ray_checks=[("ext_asphalt", (50.0, 0.10, -48.0), "EastExt__Road_Ext")],
    )

    # B. East Portal + Road_Ext + Taxis entering/exiting at x = 136.5 & 140.4 + flanking trees/lights/sign
    scene, cam, red = setup_scene()
    import_glb_placed(os.path.join(ASSETS, "landside_road_ext.glb"), "EastExt", 43.0, 0.0, -46.0)
    import_glb_placed(os.path.join(ASSETS, "landside_tunnel_portal.glb"), "EastPortal", 136.0, 0.0, -46.0)
    import_glb_placed(os.path.join(VEHICLES, "tp_taxi_01a.glb"), "TaxiIn", 136.5, 0.1, -48.25, -math.pi * 0.5)
    import_glb_placed(os.path.join(VEHICLES, "tp_taxi_01a.glb"), "TaxiOut", 140.4, 0.1, -43.6, math.pi * 0.5)
    import_glb_placed(os.path.join(ASSETS, "tp_signpost_01a.glb"), "Sign", 122.0, 0.2, -51.35, math.pi)
    import_glb_placed(os.path.join(ASSETS, "tc_streetlight_2a.glb"), "Lamp1", 118.0, 0.2, -51.4, math.pi * 0.5)
    import_glb_placed(os.path.join(ASSETS, "tc_tree_2d.glb"), "Tree2D", 126.0, -0.1, -55.0)
    import_glb_placed(os.path.join(ASSETS, "tp_pine_tree_02a.glb"), "Pine1", 129.0, -0.1, -37.2)
    cube = add_ref_cube(red, 128.0, 0.2, -51.5)
    aim(cam, (92.0, 17.5, -14.0), (138.0, 2.2, -46.0), vfov_deg=46.0)
    prove_and_render(
        scene, cam, "incontext_east_assembly",
        (117.0, 161.5, 0.0, 6.8, -57.5, -34.5),
        cube, (1280, 720),
        ray_checks=[("portal_structure", (136.0, 4.8, -46.0), "EastPortal__Portal_Structure")],
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    render_portal_plates()
    render_road_ext_plates()
    render_props_plates()
    render_incontext_plates()
    print("LANDSIDE_PLATES_DONE", flush=True)


main()
