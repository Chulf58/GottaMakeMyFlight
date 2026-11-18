"""Verification plates of Gotta Air's station manager portrait body (board D3e, decision
the-airline-s-opening-phone-call-shows-a-new-gotta-air-stati).

Run from WSL (Windows paths after `--`):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python '<repo>\\tools\\blender\\station_manager_plates.py' \
        -- <station_manager.glb>

Imports the converted station_manager .glb, rebuilds the base material without glTF's COLOR_0
vertex-colour multiply (matching Godot's tcp_atlas_toon.tres, which reads albedo_texture only),
applies the exact Gotta Air livery split used by game/assets/ui/station_manager_portrait_probe.gd
(COLOR_0 cloth mark, 32x64 swatch cells, SHIRT_ABOVE=0.60 kept white, SUIT_MIN=0.25..DARK_BELOW=0.42
split by connected vertex island height JACKET_FROM=0.57 into LIME #65b70f jacket and TRIM #306003
skirt, plus neckerchief and buttons in TRIM #306003), and writes two multi-panel sheets under
tools/blender/out/gotta-air-portrait/:

1. station_manager_six_axis.png (1920x1280, 3x2 grid of 640x640 orthographic views: front,
   back, left, right, top, bottom at true scale beside an unoccluding 1 m orange reference cube,
   idle at 1.0 s, with in-frame bounds margin >= 0.04 asserted on every view).
2. station_manager_portrait_clay_overview.png (1920x640, 3x1 grid of 640x640 views:
   judging-camera portrait framing head-to-hips, clay render from the same portrait camera,
   and game-angle three-quarter overview beside the 1 m reference cube).
"""

import colorsys
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "tools", "blender", "out", "gotta-air-portrait")
TILE = 640
SWATCH_W, SWATCH_H = 32, 64
SHIRT_ABOVE = 0.60
DARK_BELOW = 0.42
SUIT_MIN = 0.25
JACKET_FROM = 0.57
POSE_FRAME = 25  # 1.0 s at 25 fps (ManagerProbe.POSE_TIME)
FOV_DEG = 24.0
LIME_SRGB = (0x65 / 255.0, 0xB7 / 255.0, 0x0F / 255.0)
TRIM_SRGB = (0x30 / 255.0, 0x60 / 255.0, 0x03 / 255.0)

with open(os.path.join(HERE, "cleaner_body_plates.py"), encoding="utf-8") as f:
    _src = f.read()
if not _src.rstrip().endswith("main()"):
    raise SystemExit("cleaner_body_plates.py no longer ends with main(); update this script")
plates = {"__file__": os.path.join(HERE, "cleaner_body_plates.py"), "__name__": "cleaner_body_plates"}
exec(compile(_src.rstrip()[: -len("main()")], "cleaner_body_plates.py", "exec"), plates)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1.0 / 2.4)) - 0.055


def uf_find(parent, x):
    r = x
    while parent[r] != r:
        r = parent[r]
    while parent[x] != r:
        nxt = parent[x]
        parent[x] = r
        x = nxt
    return r


def recolour_atlas(src_img, name, cells_map, srgb_colour):
    w, h = src_img.size
    cols = w // SWATCH_W
    px = list(src_img.pixels[:])
    is_linear = src_img.colorspace_settings.name.lower() in ("linear", "linear rec.709", "non-color")
    for cell, mean_v in cells_map.items():
        cx = (cell % cols) * SWATCH_W
        top_y = (cell // cols) * SWATCH_H
        by0 = h - top_y - SWATCH_H
        for y in range(by0, by0 + SWATCH_H):
            for x in range(cx, cx + SWATCH_W):
                idx = (y * w + x) * 4
                r, g, b, a = px[idx : idx + 4]
                if not is_linear:
                    sr, sg, sb = r, g, b
                else:
                    sr, sg, sb = linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b)
                v = colorsys.rgb_to_hsv(sr, sg, sb)[2]
                k = max(0.6, min(1.4, v / max(mean_v, 0.01)))
                nr, ng, nb = srgb_colour[0] * k, srgb_colour[1] * k, srgb_colour[2] * k
                if is_linear:
                    px[idx], px[idx + 1], px[idx + 2], px[idx + 3] = (
                        srgb_to_linear(nr),
                        srgb_to_linear(ng),
                        srgb_to_linear(nb),
                        a,
                    )
                else:
                    px[idx], px[idx + 1], px[idx + 2], px[idx + 3] = nr, ng, nb, a
    dst = src_img.copy()
    dst.name = name
    dst.pixels[:] = px
    dst.pack()
    return dst


def build_mat(name, img):
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def apply_livery(body):
    mesh = body.data
    if not mesh.color_attributes:
        plates["fail"]("body has no COLOR_0 cloth attribute")
    col_attr = mesh.color_attributes[0]
    uv_layer = mesh.uv_layers[0].data

    def vert_cloth(vi, li):
        if col_attr.domain == "POINT":
            return col_attr.data[vi].color[0] > 0.5
        return col_attr.data[li].color[0] > 0.5

    imported_mat = mesh.materials[0]
    src_img = next(n.image for n in imported_mat.node_tree.nodes if n.type == "TEX_IMAGE")
    # Replace glTF's COLOR_0-multiplying material with pure atlas lookup (matching Godot's toon shader).
    base_mat = build_mat("TCP_Atlas_Vendor", src_img)
    mesh.materials[0] = base_mat

    w, h = src_img.size
    cols = w // SWATCH_W
    px = src_img.pixels[:]
    is_linear = src_img.colorspace_settings.name.lower() in ("linear", "linear rec.709", "non-color")

    world_pts = [body.matrix_world @ v.co for v in mesh.vertices]
    low = min(p.z for p in world_pts)
    high = max(p.z for p in world_pts)

    parent = list(range(len(mesh.vertices)))
    poly_cloth = []
    for poly in mesh.polygons:
        lis = list(poly.loop_indices)
        vs = [mesh.loops[li].vertex_index for li in lis]
        c = vert_cloth(vs[0], lis[0])
        poly_cloth.append(c)
        if c:
            r0 = uf_find(parent, vs[0])
            for v in vs[1:]:
                parent[uf_find(parent, v)] = r0

    cells = {}
    island_z = {}
    poly_info = []
    for poly, is_c in zip(mesh.polygons, poly_cloth):
        if not is_c:
            poly_info.append((-1, -1))
            continue
        lis = list(poly.loop_indices)
        vs = [mesh.loops[li].vertex_index for li in lis]
        r = uf_find(parent, vs[0])
        u = sum(uv_layer[li].uv.x for li in lis) / len(lis)
        v_top = 1.0 - (sum(uv_layer[li].uv.y for li in lis) / len(lis))
        ix = min(max(int(u * w), 0), w - 1)
        iy_top = min(max(int(v_top * h), 0), h - 1)
        iy_bot = h - 1 - iy_top
        cell = (iy_top // SWATCH_H) * cols + (ix // SWATCH_W)
        pidx = (iy_bot * w + ix) * 4
        cr, cg, cb = px[pidx : pidx + 3]
        if is_linear:
            cr, cg, cb = linear_to_srgb(cr), linear_to_srgb(cg), linear_to_srgb(cb)
        val = colorsys.rgb_to_hsv(cr, cg, cb)[2]
        zs = (sum(world_pts[v].z for v in vs) / len(vs) - low) / (high - low)
        tris = len(vs) - 2
        sv, sc = cells.get(cell, (0.0, 0))
        cells[cell] = (sv + val * tris, sc + tris)
        sz, zc = island_z.get(r, (0.0, 0))
        island_z[r] = (sz + zs * tris, zc + tris)
        poly_info.append((cell, r))

    dyed_cells = {c: sv / sc for c, (sv, sc) in cells.items() if (sv / sc) < SHIRT_ABOVE}
    suit_cells = {c: mv for c, mv in dyed_cells.items() if SUIT_MIN <= mv < DARK_BELOW}
    for c, (sv, sc) in sorted(cells.items()):
        print("BLENDER_LIVERY cell=%d value=%.2f triangles=%d suit=%s dyed=%s" % (c, sv / sc, sc, c in suit_cells, c in dyed_cells))

    lime_mat = build_mat("GottaAir_Jacket_Lime", recolour_atlas(src_img, "atlas_lime", suit_cells, LIME_SRGB))
    trim_mat = build_mat("GottaAir_Trim_Green", recolour_atlas(src_img, "atlas_trim", dyed_cells, TRIM_SRGB))
    mesh.materials.append(lime_mat)
    mesh.materials.append(trim_mat)

    counts = {"rest": 0, "jacket": 0, "trim": 0}
    for poly, (cell, r) in zip(mesh.polygons, poly_info):
        tris = len(poly.vertices) - 2
        if cell in suit_cells:
            hs = island_z[r][0] / island_z[r][1]
            if hs >= JACKET_FROM:
                poly.material_index = 1
                counts["jacket"] += tris
            else:
                poly.material_index = 2
                counts["trim"] += tris
        elif cell in dyed_cells:
            poly.material_index = 2
            counts["trim"] += tris
        else:
            poly.material_index = 0
            counts["rest"] += tris
    print("BLENDER_LIVERY split=%s" % counts)
    if counts["jacket"] == 0 or counts["trim"] == 0:
        plates["fail"]("missing livery part: %s" % counts)
    return [base_mat, lime_mat, trim_mat]


def render_tile(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def stitch_grid(tile_paths, cols, rows, out_path):
    w, h = cols * TILE, rows * TILE
    canvas = [0.0] * (w * h * 4)
    for idx, p in enumerate(tile_paths):
        col = idx % cols
        row = idx // cols
        img = bpy.data.images.load(p)
        if tuple(img.size) != (TILE, TILE):
            plates["fail"]("tile %s size %s != %d" % (p, tuple(img.size), TILE))
        src = img.pixels[:]
        dest_y0 = (rows - 1 - row) * TILE
        dest_x0 = col * TILE
        for ty in range(TILE):
            s0 = ty * TILE * 4
            d0 = ((dest_y0 + ty) * w + dest_x0) * 4
            canvas[d0 : d0 + TILE * 4] = src[s0 : s0 + TILE * 4]
        bpy.data.images.remove(img)
        os.remove(p)
    out_img = bpy.data.images.new("sheet", width=w, height=h, alpha=True)
    out_img.pixels[:] = canvas
    out_img.filepath_raw = out_path
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(out_img)
    chk = bpy.data.images.load(out_path)
    sz = tuple(chk.size)
    bpy.data.images.remove(chk)
    if sz != (w, h):
        plates["fail"]("written sheet %s size %s != (%d, %d)" % (out_path, sz, w, h))
    print("PLATE_SHEET %s size=%s" % (out_path, sz))


def bone_world(arm, name):
    pb = arm.pose.bones.get(name)
    if pb is None:
        plates["fail"]("missing pose bone %s" % name)
    return arm.matrix_world @ pb.head


def set_portrait_camera(scene, cam, arm):
    head = bone_world(arm, "Head")
    hips = bone_world(arm, "Hips")
    centre = Vector((head.x, head.y, hips.z + (head.z - hips.z) * 0.62))
    height = (head.z - hips.z) + 0.55
    fov = math.radians(FOV_DEG)
    dist = height / (2.0 * math.tan(fov / 2.0))
    yaw = math.radians(-22.0)
    view_dir = Vector((math.sin(yaw), -math.cos(yaw), 0.0))
    cam.data.type = "PERSP"
    cam.data.lens_unit = "FOV"
    cam.data.angle = fov
    cam.location = centre + view_dir * dist + Vector((0.0, 0.0, 0.12))
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    for bname, pt in (("Head", head), ("Hips", hips)):
        p = world_to_camera_view(scene, cam, pt)
        print("PORTRAIT_CAM %s world=%s uv=(%.3f, %.3f)" % (bname, tuple(round(v, 3) for v in pt), p.x, p.y))
        if bname == "Head" and not (0.04 <= p.x <= 0.96 and 0.04 <= p.y <= 0.96):
            plates["fail"]("Head outside portrait frame: %s" % ((p.x, p.y),))
        if bname == "Hips" and not (0.04 <= p.x <= 0.96):
            plates["fail"]("Hips outside portrait frame sideways: %s" % ((p.x, p.y),))


def style_ref_cube(cube):
    # Place at (1.05, 1.05, 0.5) so no ±X, ±Y, ±Z or (+X,-Y) overview camera is occluded by the cube.
    cube.location = Vector((1.05, 1.05, 0.5))
    mat = cube.data.materials[0]
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.85, 0.32, 0.14, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85


def main():
    glbs = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(glbs) != 1:
        plates["fail"]("usage: -- <station_manager.glb>")
    os.makedirs(OUT, exist_ok=True)
    scene, cam = plates["setup"]()
    # Add gentle fill from front-left so both sides of face and hair read clearly in EEVEE.
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 1.4
    fill.rotation_euler = (math.radians(65), 0, math.radians(-35))
    scene.collection.objects.link(fill)

    cube = bpy.data.objects["ref_cube_1m"]
    style_ref_cube(cube)

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glbs[0])
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.type == "MESH" and o.parent is None:
            o.hide_render = True
    arm = next(o for o in objs if o.type == "ARMATURE")
    body = next(o for o in objs if o.type == "MESH" and o.parent == arm)
    livery_mats = apply_livery(body)

    idle = bpy.data.actions.get("idle")
    if idle is None:
        plates["fail"]("no idle action in %s" % glbs[0])
    arm.animation_data_create()
    arm.animation_data.action = idle
    if idle.slots:
        arm.animation_data.action_slot = idle.slots[0]
    scene.frame_set(POSE_FRAME)
    bpy.context.view_layer.update()

    # Sheet 1: six orthographic axis views at true scale with the unoccluding 1 m reference cube.
    cube.hide_render = False
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.1
    axis_order = ("front", "back", "left", "right", "top", "bottom")
    axis_tiles = []
    for axis in axis_order:
        loc, rot = plates["AXES"][axis]
        cam.location = loc.copy()
        cam.rotation_euler = rot
        if axis in ("front", "back"):
            cam.location.x = 0.45
        elif axis in ("left", "right"):
            cam.location.y = 0.45
        else:
            cam.location.x = 0.45
            cam.location.y = 0.45
        bpy.context.view_layer.update()
        plates["prove_in_frame"](scene, cam, objs, "station_manager %s" % axis)
        tile = os.path.join(OUT, "_tmp_%s.png" % axis)
        render_tile(scene, tile)
        axis_tiles.append(tile)
    stitch_grid(axis_tiles, 3, 2, os.path.join(OUT, "station_manager_six_axis.png"))

    # Sheet 2: hero portrait framing, clay portrait framing, and game-angle overview with 1 m cube.
    hero_tiles = []
    cube.hide_render = True
    set_portrait_camera(scene, cam, arm)
    tile_hero = os.path.join(OUT, "_tmp_hero.png")
    render_tile(scene, tile_hero)
    hero_tiles.append(tile_hero)

    clay = bpy.data.materials.new("Clay")
    cbsdf = next(n for n in clay.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    cbsdf.inputs["Base Color"].default_value = (0.55, 0.56, 0.58, 1.0)
    cbsdf.inputs["Roughness"].default_value = 0.85
    for i in range(len(body.data.materials)):
        body.data.materials[i] = clay
    tile_clay = os.path.join(OUT, "_tmp_clay.png")
    render_tile(scene, tile_clay)
    hero_tiles.append(tile_clay)

    for i, m in enumerate(livery_mats):
        body.data.materials[i] = m
    cube.hide_render = False
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.4
    cam.location = Vector((4.2, -4.2, 3.6))
    direction = Vector((0.5, 0.5, 0.85)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    plates["prove_in_frame"](scene, cam, objs, "station_manager overview")
    tile_over = os.path.join(OUT, "_tmp_overview.png")
    render_tile(scene, tile_over)
    hero_tiles.append(tile_over)

    stitch_grid(hero_tiles, 3, 1, os.path.join(OUT, "station_manager_portrait_clay_overview.png"))


main()
