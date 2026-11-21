"""Shared Toon Series kit, enclosed terminal architecture, materials, rig helpers,
cinematic bloom/vignette post-grade, logo/badge builder, and frame probes for the
Gotta Make My Flight AAA 3D CG trailer pipeline (Blender 5.2 LTS).
"""

import math
import os
import re
import sys

import bmesh
import bpy
import numpy as np
import OpenImageIO as oiio
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(REPO, "game", "assets")
TEXTURES = os.path.join(ASSETS, "textures")
FONT_PATH = os.path.join(REPO, "game", "ui", "fonts", "Nunito-Variable.ttf")
OUT_DIR = os.path.join(REPO, "tools", "blender", "out", "aaa-trailer")

FPS = 30
RES_W = 1920
RES_H = 1080
IN_FRAME_LO = 0.05
IN_FRAME_HI = 0.95

# Brand & Toon palette (sRGB)
GOTTA_LIME = (0.396, 0.718, 0.059)       # #65B70F
GOTTA_DARK = (0.188, 0.376, 0.012)       # #306003
HERO_CORAL = (0.93, 0.34, 0.21)
CLERK_NAVY = (0.16, 0.24, 0.46)
OFFICER_BLUE = (0.17, 0.31, 0.56)
CREAM = (0.99, 0.97, 0.92)
WALL_CREAM = (0.95, 0.92, 0.85)
CEIL_CREAM = (0.92, 0.90, 0.86)
YELLOW = (1.00, 0.84, 0.44)
AMBER = (1.00, 0.68, 0.16)
ALERT_CORAL = (1.00, 0.36, 0.26)
SCAN_GREEN = (0.18, 0.95, 0.42)
NAVY = (0.10, 0.13, 0.26)
NAVY_DEEP = (0.055, 0.07, 0.15)
OUTLINE_SRGB = (0.07, 0.09, 0.16)

ATLAS_MAP = {
    "TP_Atlas_1A_D": "tp_atlas_1a_d.png",
    "Atlas_1A_D": "tp_atlas_1a_d.png",
    "TP_Atlas_Simple_1A_D": "tp_atlas_1a_d.png",
    "Atlas_Simple_1A_D": "tp_atlas_1a_d.png",
    "TCP_Atlas_1A_D": "tcp_atlas_1a_d.png",
    "TC_Road_1A_D": "tc_road_1a_d.png",
    "TC_Tree_1A_D": "tc_tree_1a_d.png",
    "TC_Tree_3A_D": "tc_tree_3a_d.png",
    "TC_Props_2A_D": "tc_props_2a_d.png",
    "TC_Building_4A_D": "tc_building_4a_d.png",
    "TC_Building_17A_D": "tc_building_17a_d.png",
}

_IMG_CACHE = {}
_MAT_CACHE = {}


def fail(msg):
    print("PROBE_INVALID " + str(msg), flush=True)
    sys.exit(1)


def log(msg):
    print(msg, flush=True)


def srgb_to_lin(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def base_name(name):
    return re.sub(r"\.\d{3}$", "", name)


def clear_caches():
    _IMG_CACHE.clear()
    _MAT_CACHE.clear()


def get_image(filename, non_color=False):
    key = (filename, non_color)
    if key not in _IMG_CACHE:
        path = os.path.join(TEXTURES, filename)
        if not os.path.isfile(path):
            fail("missing texture: %s" % path)
        img = bpy.data.images.load(path, check_existing=True)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        _IMG_CACHE[key] = img
    return _IMG_CACHE[key]


# ---------------------------------------------------------------- Scene & AAA Toon Lighting


def init_shot_scene(frame_end, golden_strength=1.0, indoor=False):
    """Reset Blender to a clean 1920x1080 30fps EEVEE cinematic scene with warm/cool contrast."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    clear_caches()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = RES_W
    scene.render.resolution_y = RES_H
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = frame_end
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.eevee.taa_render_samples = 14
    if hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = False

    # Stylized warm golden-horizon to crisp Toon azure sky world
    world = bpy.data.worlds.new("TrailerWorld")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    geo_w = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo_w.outputs["Incoming"], sep.inputs["Vector"])
    elev = nt.nodes.new("ShaderNodeMath")
    elev.operation = "MULTIPLY"
    elev.inputs[1].default_value = -1.0
    nt.links.new(sep.outputs["Z"], elev.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    e0 = ramp.color_ramp.elements[0]
    e1 = ramp.color_ramp.elements[1]
    # Cohesive warm golden-hour morning sky dome across BOTH exterior and terminal window views!
    e0.position = -0.005
    e0.color = srgb_to_lin((1.00, 0.85, 0.58)) + (1.0,)
    em = ramp.color_ramp.elements.new(0.09)
    em.color = srgb_to_lin((0.78, 0.90, 0.99)) + (1.0,)
    e1.position = 0.25
    e1.color = srgb_to_lin((0.26, 0.60, 0.97)) + (1.0,)
    nt.links.new(elev.outputs["Value"], ramp.inputs["Fac"])
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.96
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    wout = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], wout.inputs["Surface"])
    scene.world = world

    # 1. Warm Golden-Hour Key Sun (casts crisp Toon shadows)
    sun_data = bpy.data.lights.new("KeySun", "SUN")
    sun_data.color = srgb_to_lin((1.0, 0.89, 0.72))
    sun_data.energy = 3.25 * golden_strength
    sun_data.angle = math.radians(3.0)
    sun_data.use_shadow = True
    sun = bpy.data.objects.new("KeySun", sun_data)
    sun.rotation_euler = (math.radians(54 if not indoor else 45), math.radians(-16), math.radians(36))
    scene.collection.objects.link(sun)

    # 2. Cool Sky Bounce Fill (shadowless cool azure contrast in shadow side!)
    fill_data = bpy.data.lights.new("SkyFill", "SUN")
    fill_data.color = srgb_to_lin((0.66, 0.82, 1.0))
    fill_data.energy = 1.12
    fill_data.use_shadow = False
    fill = bpy.data.objects.new("SkyFill", fill_data)
    fill.rotation_euler = (math.radians(50), math.radians(18), math.radians(-142))
    scene.collection.objects.link(fill)

    # 3. Crisp Golden Rim Backlight (separates characters & silhouettes like Two Point CG!)
    rim_data = bpy.data.lights.new("GoldenRim", "SUN")
    rim_data.color = srgb_to_lin((1.0, 0.80, 0.48))
    rim_data.energy = 1.05
    rim_data.use_shadow = False
    rim = bpy.data.objects.new("GoldenRim", rim_data)
    rim.rotation_euler = (math.radians(72), math.radians(0), math.radians(168))
    scene.collection.objects.link(rim)

    return scene, sun


# ---------------------------------------------------------------- Materials


def outline_material():
    if "TOON_OUTLINE" in _MAT_CACHE:
        return _MAT_CACHE["TOON_OUTLINE"]
    m = bpy.data.materials.new("TOON_OUTLINE")
    m.use_backface_culling = True
    if hasattr(m, "use_backface_culling_shadow"):
        m.use_backface_culling_shadow = True
    nt = m.node_tree
    nt.nodes.clear()
    lp = nt.nodes.new("ShaderNodeLightPath")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = srgb_to_lin(OUTLINE_SRGB) + (1.0,)
    emit.inputs["Strength"].default_value = 1.0
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Shadow Ray"], mix.inputs["Fac"])
    nt.links.new(emit.outputs["Emission"], mix.inputs[1])
    nt.links.new(transp.outputs["BSDF"], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    _MAT_CACHE["TOON_OUTLINE"] = m
    return m


def _build_toon_shaded_tree(nt, albedo_socket, shadow_transparent=False):
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(diff.outputs["BSDF"], s2r.inputs["Shader"])

    rgb2bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(s2r.outputs["Color"], rgb2bw.inputs["Color"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    c0 = ramp.color_ramp.elements[0]
    c0.position = 0.0
    c0.color = (0.46, 0.49, 0.59, 1.0)  # Cool sky-tinted shadow band
    c1 = ramp.color_ramp.elements.new(0.28)
    c1.color = (0.50, 0.53, 0.62, 1.0)
    c2 = ramp.color_ramp.elements.new(0.32)
    c2.color = (0.84, 0.82, 0.80, 1.0)  # Mid warm-neutral toon band
    c3 = ramp.color_ramp.elements.new(0.62)
    c3.color = (0.88, 0.86, 0.83, 1.0)
    c4 = ramp.color_ramp.elements[1]
    c4.position = 0.66
    c4.color = (1.09, 1.04, 0.96, 1.0)  # Rich warm sunlit highlight band
    nt.links.new(rgb2bw.outputs["Val"], ramp.inputs["Fac"])

    tint_mix = nt.nodes.new("ShaderNodeMix")
    tint_mix.data_type = "RGBA"
    tint_mix.blend_type = "MIX"
    tint_mix.inputs["Factor"].default_value = 0.28
    cols_t = [s for s in tint_mix.inputs if s.type == "RGBA"]
    nt.links.new(ramp.outputs["Color"], cols_t[0])
    nt.links.new(s2r.outputs["Color"], cols_t[1])
    shade_out = [s for s in tint_mix.outputs if s.type == "RGBA"][0]

    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    cols = [s for s in mul.inputs if s.type == "RGBA"]
    nt.links.new(albedo_socket, cols[0])
    nt.links.new(shade_out, cols[1])
    mul_out = [s for s in mul.outputs if s.type == "RGBA"][0]

    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(mul_out, emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if shadow_transparent:
        lp = nt.nodes.new("ShaderNodeLightPath")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        smix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(lp.outputs["Is Shadow Ray"], smix.inputs["Fac"])
        nt.links.new(emit.outputs["Emission"], smix.inputs[1])
        nt.links.new(tr.outputs["BSDF"], smix.inputs[2])
        nt.links.new(smix.outputs["Shader"], out.inputs["Surface"])
    else:
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])


def toon_atlas_mat(atlas_png):
    key = ("ATLAS", atlas_png)
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new("TOON_" + atlas_png)
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image(atlas_png)
    tex.interpolation = "Closest"
    _build_toon_shaded_tree(nt, tex.outputs["Color"])
    _MAT_CACHE[key] = m
    return m


def toon_rgb_mat(name, srgb, shadow_transparent=False):
    key = ("RGB", name, tuple(round(x, 4) for x in srgb), shadow_transparent)
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new("TOON_RGB_" + name)
    nt = m.node_tree
    nt.nodes.clear()
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = srgb_to_lin(srgb) + (1.0,)
    _build_toon_shaded_tree(nt, rgb.outputs[0], shadow_transparent=shadow_transparent)
    _MAT_CACHE[key] = m
    return m


def concourse_tile_floor_mat():
    """Procedural warm limestone 1m x 1m airport concourse tile shader so expansive floors
    never show bare untiled seams or grey void."""
    if "CONCOURSE_TILE_FLOOR" in _MAT_CACHE:
        return _MAT_CACHE["CONCOURSE_TILE_FLOOR"]
    m = bpy.data.materials.new("TOON_ConcourseTileFloor")
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.015
    brick.inputs["Mortar Smooth"].default_value = 0.05
    brick.inputs["Bias"].default_value = 0.0
    brick.inputs["Brick Width"].default_value = 1.0
    brick.inputs["Row Height"].default_value = 1.0
    brick.inputs["Color1"].default_value = srgb_to_lin((0.88, 0.85, 0.79)) + (1.0,)
    brick.inputs["Color2"].default_value = srgb_to_lin((0.85, 0.82, 0.76)) + (1.0,)
    brick.inputs["Mortar"].default_value = srgb_to_lin((0.73, 0.70, 0.65)) + (1.0,)
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    _build_toon_shaded_tree(nt, brick.outputs["Color"])
    _MAT_CACHE["CONCOURSE_TILE_FLOOR"] = m
    return m


def horizon_grass_mat():
    """Distance-faded warm golden-mist airfield grass so the horizon never shows a harsh
    neon-green edge!"""
    if "HORIZON_GRASS" in _MAT_CACHE:
        return _MAT_CACHE["HORIZON_GRASS"]
    m = bpy.data.materials.new("TOON_HorizonGrass")
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    # Distance from origin (0..450m) -> blend cozy green grass into warm golden horizon mist!
    vlen = nt.nodes.new("ShaderNodeVectorMath")
    vlen.operation = "LENGTH"
    nt.links.new(geo.outputs["Position"], vlen.inputs[0])
    mapr = nt.nodes.new("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = 95.0
    mapr.inputs["From Max"].default_value = 380.0
    nt.links.new(vlen.outputs["Value"], mapr.inputs["Value"])

    grass_col = nt.nodes.new("ShaderNodeRGB")
    grass_col.outputs[0].default_value = srgb_to_lin((0.44, 0.65, 0.30)) + (1.0,)
    mist_col = nt.nodes.new("ShaderNodeRGB")
    mist_col.outputs[0].default_value = srgb_to_lin((0.97, 0.84, 0.62)) + (1.0,)

    # Shade grass first, then mix into emissive horizon mist at far distance
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(diff.outputs["BSDF"], s2r.inputs["Shader"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 0.35
    mc = [s for s in mul.inputs if s.type == "RGBA"]
    nt.links.new(grass_col.outputs[0], mc[0])
    nt.links.new(s2r.outputs["Color"], mc[1])
    shaded_grass = [s for s in mul.outputs if s.type == "RGBA"][0]

    fmix = nt.nodes.new("ShaderNodeMix")
    fmix.data_type = "RGBA"
    nt.links.new(mapr.outputs["Result"], fmix.inputs["Factor"])
    fc = [s for s in fmix.inputs if s.type == "RGBA"]
    nt.links.new(shaded_grass, fc[0])
    nt.links.new(mist_col.outputs[0], fc[1])
    fout = [s for s in fmix.outputs if s.type == "RGBA"][0]

    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(fout, emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _MAT_CACHE["HORIZON_GRASS"] = m
    return m


def soft_vapor_trail_mat():
    """Soft UV-driven alpha-feathered translucent wingtip condensation ribbon (fades cleanly to 0)."""
    if "SOFT_VAPOR" in _MAT_CACHE:
        return _MAT_CACHE["SOFT_VAPOR"]
    m = bpy.data.materials.new("SOFT_VAPOR")
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["UV"], sep.inputs["Vector"])
    # UV.Y goes 0 (front at wingtip) -> 1 (back tail): ramp in softly over 0..0.14 so distant winglet never draws a hard cap over nose, then fade to 0!
    lead = nt.nodes.new("ShaderNodeMath")
    lead.operation = "MULTIPLY"
    lead.inputs[1].default_value = 7.5
    lead.use_clamp = True
    nt.links.new(sep.outputs["Y"], lead.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs["Y"], inv.inputs[1])
    inv.use_clamp = True
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.8
    nt.links.new(inv.outputs["Value"], pw.inputs[0])
    long_env = nt.nodes.new("ShaderNodeMath")
    long_env.operation = "MULTIPLY"
    nt.links.new(lead.outputs["Value"], long_env.inputs[0])
    nt.links.new(pw.outputs["Value"], long_env.inputs[1])
    # Soft lateral feather across ribbon width UV.X in [0..1]: 4 * x * (1 - x)
    inv_x = nt.nodes.new("ShaderNodeMath")
    inv_x.operation = "SUBTRACT"
    inv_x.inputs[0].default_value = 1.0
    inv_x.use_clamp = True
    nt.links.new(sep.outputs["X"], inv_x.inputs[1])
    lat = nt.nodes.new("ShaderNodeMath")
    lat.operation = "MULTIPLY"
    nt.links.new(sep.outputs["X"], lat.inputs[0])
    nt.links.new(inv_x.outputs["Value"], lat.inputs[1])
    lat4 = nt.nodes.new("ShaderNodeMath")
    lat4.operation = "MULTIPLY"
    lat4.inputs[1].default_value = 3.6
    lat4.use_clamp = True
    nt.links.new(lat.outputs["Value"], lat4.inputs[0])
    prof = nt.nodes.new("ShaderNodeMath")
    prof.operation = "MULTIPLY"
    nt.links.new(long_env.outputs["Value"], prof.inputs[0])
    nt.links.new(lat4.outputs["Value"], prof.inputs[1])
    gain = nt.nodes.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = 0.68
    nt.links.new(prof.outputs["Value"], gain.inputs[0])

    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb_to_lin((1.0, 0.99, 0.97)) + (1.0,)
    em.inputs["Strength"].default_value = 1.25
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(gain.outputs["Value"], mix.inputs["Fac"])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[1])
    nt.links.new(em.outputs["Emission"], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    _MAT_CACHE["SOFT_VAPOR"] = m
    return m


def gotta_air_plane_mat():
    """Recolour fixed-wing aircraft (tp_plane_05a / tp_plane_03a) saturated blue & red trim
    swatches in TP_Atlas_1A_D into Gotta Air Lime (#65B70F) & Dark Forest Green (#306003),
    leaving the bright white fuselage and grey engines spotless!"""
    if "GOTTA_PLANE" in _MAT_CACHE:
        return _MAT_CACHE["GOTTA_PLANE"]
    m = bpy.data.materials.new("TOON_GottaAirPlane")
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image("tp_atlas_1a_d.png")
    tex.interpolation = "Closest"

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], sep.inputs["Color"])

    sub_br = nt.nodes.new("ShaderNodeMath")
    sub_br.operation = "SUBTRACT"
    nt.links.new(sep.outputs["Blue"], sub_br.inputs[0])
    nt.links.new(sep.outputs["Red"], sub_br.inputs[1])
    is_blue = nt.nodes.new("ShaderNodeMath")
    is_blue.operation = "GREATER_THAN"
    is_blue.inputs[1].default_value = 0.08
    nt.links.new(sub_br.outputs["Value"], is_blue.inputs[0])

    sub_rg = nt.nodes.new("ShaderNodeMath")
    sub_rg.operation = "SUBTRACT"
    nt.links.new(sep.outputs["Red"], sub_rg.inputs[0])
    nt.links.new(sep.outputs["Green"], sub_rg.inputs[1])
    is_red = nt.nodes.new("ShaderNodeMath")
    is_red.operation = "GREATER_THAN"
    is_red.inputs[1].default_value = 0.28
    nt.links.new(sub_rg.outputs["Value"], is_red.inputs[0])

    lime_node = nt.nodes.new("ShaderNodeRGB")
    lime_node.outputs[0].default_value = srgb_to_lin(GOTTA_LIME) + (1.0,)
    dark_node = nt.nodes.new("ShaderNodeRGB")
    dark_node.outputs[0].default_value = srgb_to_lin(GOTTA_DARK) + (1.0,)

    mix1 = nt.nodes.new("ShaderNodeMix")
    mix1.data_type = "RGBA"
    nt.links.new(is_blue.outputs["Value"], mix1.inputs["Factor"])
    c1 = [s for s in mix1.inputs if s.type == "RGBA"]
    nt.links.new(tex.outputs["Color"], c1[0])
    nt.links.new(lime_node.outputs[0], c1[1])
    out1 = [s for s in mix1.outputs if s.type == "RGBA"][0]

    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    nt.links.new(is_red.outputs["Value"], mix2.inputs["Factor"])
    c2 = [s for s in mix2.inputs if s.type == "RGBA"]
    nt.links.new(out1, c2[0])
    nt.links.new(dark_node.outputs[0], c2[1])
    out2 = [s for s in mix2.outputs if s.type == "RGBA"][0]

    _build_toon_shaded_tree(nt, out2)
    _MAT_CACHE["GOTTA_PLANE"] = m
    return m


def emissive_mat(name, srgb, strength=1.0):
    key = ("EMIT", name, tuple(round(x, 4) for x in srgb), round(strength, 2))
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new("EMIT_" + name)
    nt = m.node_tree
    nt.nodes.clear()
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = srgb_to_lin(srgb) + (1.0,)
    emit.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _MAT_CACHE[key] = m
    return m


def lights_atlas_mat():
    if "TP_LIGHTS" in _MAT_CACHE:
        return _MAT_CACHE["TP_LIGHTS"]
    m = bpy.data.materials.new("TOON_TP_Lights")
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image("tp_atlas_lights_1a_d.png")
    tex.interpolation = "Closest"
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.25
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _MAT_CACHE["TP_LIGHTS"] = m
    return m


def glass_mat():
    """Crystal-clear warm sunlit architectural window glass (86% transparent + 14% sky tint)
    so terminal windows clearly show the sunny golden-hour apron, grass, trees, and aircraft outside!"""
    if "TP_GLASS" in _MAT_CACHE:
        return _MAT_CACHE["TP_GLASS"]
    m = bpy.data.materials.new("TOON_TP_Glass")
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    if hasattr(m, "use_backface_culling_shadow"):
        m.use_backface_culling_shadow = True
    nt = m.node_tree
    nt.nodes.clear()
    lp = nt.nodes.new("ShaderNodeLightPath")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = srgb_to_lin((0.82, 0.92, 1.00)) + (1.0,)
    emit.inputs["Strength"].default_value = 0.95
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    glass_mix = nt.nodes.new("ShaderNodeMixShader")
    glass_mix.inputs["Fac"].default_value = 0.14
    nt.links.new(transp.outputs["BSDF"], glass_mix.inputs[1])
    nt.links.new(emit.outputs["Emission"], glass_mix.inputs[2])
    shad_mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Shadow Ray"], shad_mix.inputs["Fac"])
    nt.links.new(glass_mix.outputs["Shader"], shad_mix.inputs[1])
    nt.links.new(transp.outputs["BSDF"], shad_mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(shad_mix.outputs["Shader"], out.inputs["Surface"])
    _MAT_CACHE["TP_GLASS"] = m
    return m


def exterior_lobby_glass_mat():
    """Warm golden-hour morning facade glass for exterior `TP_Airport_01A` curtain walls so Shot 1
    matches Shots 2-5's sunlit morning warmth instead of dark dusk slate."""
    if "TP_EXT_LOBBY_GLASS" in _MAT_CACHE:
        return _MAT_CACHE["TP_EXT_LOBBY_GLASS"]
    m = bpy.data.materials.new("TOON_TP_ExtLobbyGlass")
    nt = m.node_tree
    nt.nodes.clear()
    geom = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geom.outputs["Position"], sep.inputs["Vector"])
    map_z = nt.nodes.new("ShaderNodeMapRange")
    map_z.inputs["From Min"].default_value = 0.4
    map_z.inputs["From Max"].default_value = 5.2
    nt.links.new(sep.outputs["Z"], map_z.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = srgb_to_lin((0.99, 0.90, 0.70)) + (1.0,)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = srgb_to_lin((0.66, 0.85, 1.00)) + (1.0,)
    nt.links.new(map_z.outputs["Result"], ramp.inputs["Fac"])
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.02
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _MAT_CACHE["TP_EXT_LOBBY_GLASS"] = m
    return m


def warm_exterior_facade_windows(objs):
    """Rebind dark-slate window polygons baked into `tp_atlas_1a_d.png` on `tp_airport_01a` to
    `exterior_lobby_glass_mat()` while preserving concrete mullions, pillars, roof, and signage."""
    img = get_image("tp_atlas_1a_d.png")
    iw, ih = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(ih, iw, 4)
    ext_m = exterior_lobby_glass_mat()
    tp_base = toon_atlas_mat("tp_atlas_1a_d.png")

    for ao in objs:
        if ao.type != "MESH" or "Door_6" in ao.name or not ao.data.uv_layers:
            continue
        me = ao.data
        uv_data = me.uv_layers.active.data
        win_polys = []
        for poly in me.polygons:
            if poly.material_index < len(me.materials) and me.materials[poly.material_index] == tp_base:
                u = sum(uv_data[li].uv[0] for li in poly.loop_indices) / len(poly.loop_indices)
                v = sum(uv_data[li].uv[1] for li in poly.loop_indices) / len(poly.loop_indices)
                ix = max(0, min(iw - 1, int((u % 1.0) * iw)))
                iy = max(0, min(ih - 1, int((v % 1.0) * ih)))
                r_c, g_c, b_c, _ = px[iy, ix]
                if b_c > r_c + 0.045 and r_c < 0.28 and b_c < 0.45:
                    win_polys.append(poly.index)
        if win_polys:
            me.materials.append(ext_m)
            slot_idx = len(me.materials) - 1
            for pi in win_polys:
                me.polygons[pi].material_index = slot_idx


def vehicle_glass_mat():
    """Sleek dark-tinted vehicle cab windshield/window material (`Glass_Vehicles_01A_D`)."""
    if "VEH_GLASS" in _MAT_CACHE:
        return _MAT_CACHE["VEH_GLASS"]
    m = bpy.data.materials.new("TOON_Vehicle_Glass")
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image("tp_glass_gradient_1a_d.png")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 0.95
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _MAT_CACHE["VEH_GLASS"] = m
    return m


def character_mat(tag, cloth_tint_srgb=None, attr_name="Color"):
    key = ("CHAR", tag, cloth_tint_srgb, attr_name)
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new("TOON_CHAR_" + tag)
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image("tcp_atlas_1a_d.png")
    tex.interpolation = "Closest"

    if cloth_tint_srgb is None:
        albedo_sock = tex.outputs["Color"]
    else:
        vcol = nt.nodes.new("ShaderNodeAttribute")
        vcol.attribute_name = attr_name
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        nt.links.new(tex.outputs["Color"], bw.inputs["Color"])
        remap = nt.nodes.new("ShaderNodeMath")
        remap.operation = "MULTIPLY_ADD"
        remap.inputs[1].default_value = 0.65
        remap.inputs[2].default_value = 0.42
        nt.links.new(bw.outputs["Val"], remap.inputs[0])

        tint_rgb = nt.nodes.new("ShaderNodeRGB")
        tint_rgb.outputs[0].default_value = srgb_to_lin(cloth_tint_srgb) + (1.0,)

        cloth_col = nt.nodes.new("ShaderNodeMix")
        cloth_col.data_type = "RGBA"
        cloth_col.blend_type = "MULTIPLY"
        cloth_col.inputs["Factor"].default_value = 1.0
        cc_in = [s for s in cloth_col.inputs if s.type == "RGBA"]
        nt.links.new(tint_rgb.outputs[0], cc_in[0])
        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(remap.outputs["Value"], comb.inputs["Red"])
        nt.links.new(remap.outputs["Value"], comb.inputs["Green"])
        nt.links.new(remap.outputs["Value"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], cc_in[1])
        cloth_out = [s for s in cloth_col.outputs if s.type == "RGBA"][0]

        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MIX"
        nt.links.new(vcol.outputs["Fac"], mix.inputs["Factor"])
        m_in = [s for s in mix.inputs if s.type == "RGBA"]
        nt.links.new(tex.outputs["Color"], m_in[0])
        nt.links.new(cloth_out, m_in[1])
        albedo_sock = [s for s in mix.outputs if s.type == "RGBA"][0]

    _build_toon_shaded_tree(nt, albedo_sock)
    _MAT_CACHE[key] = m
    return m


def attach_outline(obj, thickness=0.006):
    if obj.type != "MESH" or thickness <= 0.0:
        return
    mat_names = [m.name if m else "" for m in obj.data.materials]
    is_skip_slot = [any(k in n for k in ("TP_Glass", "Lights", "EMIT_", "SOFT_")) for n in mat_names]
    if mat_names and all(is_skip_slot):
        return
    if any("TP_Glass" in n for n in mat_names):
        return

    omat = outline_material()
    existing = [i for i, m in enumerate(obj.data.materials) if m == omat]
    if existing:
        idx = existing[0]
    else:
        obj.data.materials.append(omat)
        idx = len(obj.data.materials) - 1
    if any(mod.name == "ToonOutline" for mod in obj.modifiers):
        return
    mod = obj.modifiers.new("ToonOutline", "SOLIDIFY")
    mod.thickness = -abs(thickness)
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.use_even_offset = False
    mod.material_offset = idx


PLANE_INTERIOR_SKIP_TOKENS = (
    "Seat",
    "Table",
    "Toilet",
    "Bathroom",
    "Yoke",
    "Lever",
    "Wheel",
    "Landing_Gear",
    "Hatch_Int",
)


def is_exterior_airframe_mesh(obj_name):
    bn = base_name(obj_name)
    return not any(tok in bn for tok in PLANE_INTERIOR_SKIP_TOKENS)


def rebind_materials(objs, label, outline_thickness=0.005, is_vehicle=False):
    seen = set()
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        for slot in o.material_slots:
            if slot.material is None:
                fail("%s: %s has empty material slot" % (label, o.name))
            raw = base_name(slot.material.name)
            seen.add(raw)
            if raw in ATLAS_MAP:
                slot.material = toon_atlas_mat(ATLAS_MAP[raw])
            elif raw in ("TP_Atlas_Lights_1A_D", "Atlas_Lights_1A_D"):
                slot.material = lights_atlas_mat()
            elif raw == "TP_Glass_1A_D":
                slot.material = vehicle_glass_mat() if is_vehicle else glass_mat()
            elif raw == "Glass_Vehicles_01A_D":
                slot.material = vehicle_glass_mat()
            else:
                fail("%s: unmapped material %r on %s" % (label, raw, o.name))
        if outline_thickness > 0.0:
            attach_outline(o, outline_thickness)
    return seen


# ---------------------------------------------------------------- Architectural Doors, Signs & Wheel Chocks


def make_sliding_glass_door_unit(
    scene,
    name,
    loc,
    yaw_deg=0.0,
    clear_width=1.52,
    total_width=3.00,
    height=2.22,
    total_height=2.45,
    open_keys=None,
    telescopic=False,
    parent=None,
):
    """Build a clean bi-parting automatic glass door assembly (`<name>_ROOT`):
    - Closed (`open_frac = 0.0`): left and right leaves meet flush at `x = 0.0` (`0.000 m` gap).
    - Open (`open_frac = 1.0`): leaves slide strictly into the unit's enclosed side pocket/sidelite
      bays `[-total_width/2, +total_width/2]` (never protruding outside the jambs or slicing pillars).
    - When `telescopic=True`, uses 2-stage telescopic leaves per side so narrow masonry openings
      (like Shot 1 `Door_6`) achieve a generous clear width without exceeding the outer jambs.
    """
    root = bpy.data.objects.new("ROOT_" + name, None)
    root.location = loc
    root.rotation_mode = "XYZ"
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    scene.collection.objects.link(root)
    if parent is not None:
        root.parent = parent

    frame_m = toon_rgb_mat("door_frame_alu", (0.22, 0.27, 0.36))
    dark_m = toon_rgb_mat("door_seal_dark", (0.12, 0.15, 0.22))
    lime_m = emissive_mat("door_sensor_lime", GOTTA_LIME, strength=1.2)
    g_mat = glass_mat()

    half_tot = 0.5 * float(total_width)
    half_clr = 0.5 * float(clear_width)
    jamb_w = 0.06
    transom_h = max(0.10, float(total_height) - float(height))

    # Outer jamb posts & full-width overhead transom/operator header
    make_box(scene, name + "_JambL", (jamb_w, 0.16, total_height), (-half_tot + jamb_w * 0.5, 0.0, total_height * 0.5), frame_m, bevel=0.008, parent=root, outline=0.003)
    make_box(scene, name + "_JambR", (jamb_w, 0.16, total_height), (half_tot - jamb_w * 0.5, 0.0, total_height * 0.5), frame_m, bevel=0.008, parent=root, outline=0.003)
    make_box(scene, name + "_Header", (total_width, 0.18, transom_h), (0.0, 0.0, height + transom_h * 0.5), frame_m, bevel=0.01, parent=root, outline=0.003)
    make_box(scene, name + "_Sensor", (0.34, 0.20, 0.045), (0.0, 0.0, height + 0.04), lime_m, bevel=0.006, parent=root)

    # Fixed sidelite pocket bays (`y = +0.038` plane so sliding leaves at `y = -0.018` glide cleanly in front)
    pocket_w = max(0.08, (half_tot - jamb_w) - half_clr)
    for side_tag, sgn in (("L", -1.0), ("R", 1.0)):
        px_mid = sgn * (half_clr + pocket_w * 0.5)
        make_box(scene, "%s_Mullion_%s" % (name, side_tag), (0.045, 0.14, height), (sgn * half_clr, 0.035, height * 0.5), frame_m, bevel=0.006, parent=root, outline=0.003)
        if pocket_w > 0.10:
            make_box(scene, "%s_SideliteTop_%s" % (name, side_tag), (pocket_w, 0.05, 0.07), (px_mid, 0.038, height - 0.035), frame_m, bevel=0.005, parent=root)
            make_box(scene, "%s_SideliteBot_%s" % (name, side_tag), (pocket_w, 0.05, 0.09), (px_mid, 0.038, 0.045), frame_m, bevel=0.005, parent=root)
            make_box(scene, "%s_SideliteGlass_%s" % (name, side_tag), (max(0.04, pocket_w - 0.03), 0.018, height - 0.16), (px_mid, 0.038, height * 0.5 + 0.01), g_mat, bevel=0.0, parent=root)

    def _build_leaf_panel(leaf_parent, pname, x0, x1, y_plane, z_h):
        w_p = abs(x1 - x0)
        cx_p = 0.5 * (x0 + x1)
        stile = 0.042
        z_bot = 0.008
        span_h = z_h - z_bot
        # Top/bottom rails + left/right stiles + central glass pane (gliding 8mm clear above floor sill)
        make_box(scene, pname + "_TopRail", (w_p, 0.038, 0.065), (cx_p, y_plane, z_h - 0.0325), frame_m, bevel=0.004, parent=leaf_parent, outline=0.002)
        make_box(scene, pname + "_BotRail", (w_p, 0.038, 0.088), (cx_p, y_plane, z_bot + 0.044), frame_m, bevel=0.004, parent=leaf_parent, outline=0.002)
        make_box(scene, pname + "_StileIn", (stile, 0.040, span_h), (x1 - stile * 0.5 if x1 <= 0.001 else x0 + stile * 0.5, y_plane, z_bot + span_h * 0.5), dark_m, bevel=0.004, parent=leaf_parent)
        make_box(scene, pname + "_StileOut", (stile, 0.038, span_h), (x0 + stile * 0.5 if x1 <= 0.001 else x1 - stile * 0.5, y_plane, z_bot + span_h * 0.5), frame_m, bevel=0.004, parent=leaf_parent)
        gw = max(0.05, w_p - 2.0 * stile)
        make_box(scene, pname + "_Glass", (gw, 0.016, span_h - 0.155), (cx_p, y_plane, z_bot + span_h * 0.5 + 0.012), g_mat, bevel=0.0, parent=leaf_parent)

    leaf_l = bpy.data.objects.new(name + "_Leaf_L", None)
    leaf_l.parent = root
    scene.collection.objects.link(leaf_l)
    leaf_r = bpy.data.objects.new(name + "_Leaf_R", None)
    leaf_r.parent = root
    scene.collection.objects.link(leaf_r)

    extra_leaves = []
    max_pocket_reach = half_tot - jamb_w - 0.015
    if telescopic:
        # Outer slow panel [-half_clr .. -half_clr*0.5] + inner fast panel [-half_clr*0.5 .. 0.0]
        w_sub = half_clr * 0.5 + 0.015
        leaf_l_outer = bpy.data.objects.new(name + "_Leaf_L_Outer", None)
        leaf_l_outer.parent = root
        scene.collection.objects.link(leaf_l_outer)
        leaf_r_outer = bpy.data.objects.new(name + "_Leaf_R_Outer", None)
        leaf_r_outer.parent = root
        scene.collection.objects.link(leaf_r_outer)
        _build_leaf_panel(leaf_l_outer, name + "_PanelLO", -half_clr, -half_clr + w_sub, 0.008, height)
        _build_leaf_panel(leaf_r_outer, name + "_PanelRO", half_clr - w_sub, half_clr, 0.008, height)
        _build_leaf_panel(leaf_l, name + "_PanelLI", -w_sub, 0.0, -0.024, height)
        _build_leaf_panel(leaf_r, name + "_PanelRI", 0.0, w_sub, -0.024, height)
        max_travel_in = max(0.0, max_pocket_reach - w_sub)
        max_travel_out = max(0.0, max_pocket_reach - half_clr)
        extra_leaves = [(leaf_l_outer, -max_travel_out), (leaf_r_outer, max_travel_out)]
        slide_dist = min(half_clr - 0.04, max_travel_in)
    else:
        _build_leaf_panel(leaf_l, name + "_PanelL", -half_clr, 0.0, -0.018, height)
        _build_leaf_panel(leaf_r, name + "_PanelR", 0.0, half_clr, -0.018, height)
        slide_dist = min(half_clr - 0.04, max(0.0, max_pocket_reach - half_clr))

    if not open_keys:
        open_keys = [(1, 0.0)]
    for f_k, frac in open_keys:
        fr = max(0.0, min(1.0, float(frac)))
        leaf_l.location = (-slide_dist * fr, 0.0, 0.0)
        leaf_l.keyframe_insert(data_path="location", frame=int(f_k))
        leaf_r.location = (slide_dist * fr, 0.0, 0.0)
        leaf_r.keyframe_insert(data_path="location", frame=int(f_k))
        for ex_ob, ex_d in extra_leaves:
            ex_ob.location = (ex_d * fr, 0.0, 0.0)
            ex_ob.keyframe_insert(data_path="location", frame=int(f_k))
    for ob_l in [leaf_l, leaf_r] + [e[0] for e in extra_leaves]:
        _set_fcurves_linear(ob_l)

    root["sliding_door_total_width"] = float(total_width)
    root["sliding_door_clear_width"] = float(clear_width)
    s_keys = sorted((int(fk), max(0.0, min(1.0, float(fr)))) for fk, fr in open_keys)
    closed_all = []
    for f_eval in range(1, int(scene.frame_end) + 1):
        if f_eval <= s_keys[0][0]:
            f_val = s_keys[0][1]
        elif f_eval >= s_keys[-1][0]:
            f_val = s_keys[-1][1]
        else:
            f_val = 1.0
            for idx_k in range(len(s_keys) - 1):
                ka, va = s_keys[idx_k]
                kb, vb = s_keys[idx_k + 1]
                if ka <= f_eval <= kb:
                    f_val = va if kb == ka else (va + (vb - va) * ((f_eval - ka) / float(kb - ka)))
                    break
        if f_val <= 0.005:
            closed_all.append(f_eval)
    root["sliding_door_closed_frames"] = closed_all
    return root, {"Leaf_L": leaf_l, "Leaf_R": leaf_r}


def make_hanging_terminal_sign(
    scene,
    name,
    text,
    loc,
    yaw_deg=0.0,
    width=2.85,
    height=0.48,
    ceil_z=3.85,
    text_size=0.26,
    parent=None,
):
    """Build an illuminated overhead concourse sign (`<name>`) with two vertical navy steel
    suspension struts anchored up to `ceil_z` so indoor signs never float in mid-air (`F-18`)."""
    root = bpy.data.objects.new(name, None)
    root.location = loc
    root.rotation_mode = "XYZ"
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    scene.collection.objects.link(root)
    if parent is not None:
        root.parent = parent

    navy_m = toon_rgb_mat("sign_navy_" + name, NAVY)
    rod_m = toon_rgb_mat("sign_rod_" + name, (0.20, 0.25, 0.36))
    lime_m = emissive_mat("sign_lime_" + name, GOTTA_LIME, 1.45)

    box = make_box(scene, name + "_Box", (width, 0.18, height), (0.0, 0.0, 0.0), navy_m, bevel=0.03, parent=root, outline=0.005)
    txt = make_nunito_text_3d(scene, text, text_size, 0.012, lime_m, extrude=0.02, parent=root)
    txt.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    txt.location = (0.0, -0.11, 0.0)

    strut_h = max(0.25, float(ceil_z) - float(loc[2]) - height * 0.5 + 0.04)
    sx_off = width * 0.36
    for tag_s, sx in (("L", -sx_off), ("R", sx_off)):
        make_box(
            scene,
            "%s_Strut_%s" % (name, tag_s),
            (0.055, 0.055, strut_h),
            (sx, 0.0, height * 0.5 + strut_h * 0.5 - 0.02),
            rod_m,
            bevel=0.008,
            parent=root,
            outline=0.003,
        )
        make_box(
            scene,
            "%s_CeilPlate_%s" % (name, tag_s),
            (0.16, 0.16, 0.04),
            (sx, 0.0, float(ceil_z) - float(loc[2]) - 0.02),
            navy_m,
            bevel=0.006,
            parent=root,
        )
    return root, [box, txt]


def add_plane_wheel_chocks(scene, plane_root, plane_by_n, tag="Chock"):
    """Place paired yellow rubber wheel chocks fore and aft of `Wheel_F` on cold-parked aircraft (`F-26`)."""
    wf = next((v for k, v in plane_by_n.items() if "Wheel_F" in k and v.type == "MESH"), None)
    if wf is None:
        return None
    bpy.context.view_layer.update()
    pinv = plane_root.matrix_world.inverted()
    pts = [pinv @ (wf.matrix_world @ v.co) for v in wf.data.vertices]
    cx = 0.5 * (min(p.x for p in pts) + max(p.x for p in pts))
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    w_span = max(0.18, (max(p.x for p in pts) - min(p.x for p in pts)) * 1.25)
    ym = toon_rgb_mat("wheel_chock_yellow", YELLOW)
    holder = bpy.data.objects.new(tag + "_WheelChocks", None)
    holder.parent = plane_root
    scene.collection.objects.link(holder)
    make_box(scene, tag + "_ChockFore", (w_span, 0.11, 0.085), (cx, y0 - 0.07, 0.045), ym, bevel=0.012, parent=holder, outline=0.003)
    make_box(scene, tag + "_ChockAft", (w_span, 0.11, 0.085), (cx, y1 + 0.07, 0.045), ym, bevel=0.012, parent=holder, outline=0.003)
    return holder


# ---------------------------------------------------------------- Enclosed Terminal Shell


def build_enclosed_terminal_hall(scene, x_min=-5.5, x_max=8.5, y_min=-16.0, y_max=12.0, ceil_z=3.85,
                                 glass_side="left", open_north_wall=False, east_archway=None, north_openings=None,
                                 south_openings=None):
    """Build a 100% enclosed, warm architectural airport concourse shell (expansive tiled floor,
    back/side/front walls, optional open concourse archways/doorways with lit continuation corridors,
    shadow-transparent ceiling slab with glowing recessed LED panels, and sunlit tarmac/trees outside!)."""
    shell = bpy.data.objects.new("TerminalShell_ROOT", None)
    scene.collection.objects.link(shell)

    # 1. Expansive concourse tile floor extending well past any camera frustum & continuation halls
    fl = make_box(scene, "HallTiledFloor", (48.0, 62.0, 0.12), (0.0, 0.0, -0.065), concourse_tile_floor_mat(), bevel=0.0, parent=shell)
    fl.visible_shadow = True

    wall_m = toon_rgb_mat("hall_wall", WALL_CREAM)
    trim_m = toon_rgb_mat("hall_trim", (0.28, 0.33, 0.44))
    col_m = toon_rgb_mat("hall_col", (0.84, 0.82, 0.78))
    ceil_m = toon_rgb_mat("hall_ceil", CEIL_CREAM, shadow_transparent=True)
    led_m = emissive_mat("ceil_led", (1.0, 0.96, 0.86), strength=1.55)

    # 2. Ceiling slab (shadow_transparent=True so warm KeySun still casts crisp shadows inside!)
    w_span = (x_max - x_min) + 14.0
    l_span = (y_max - y_min) + 14.0
    cx = 0.5 * (x_min + x_max)
    cy = 0.5 * (y_min + y_max)
    ceil = make_box(scene, "HallCeiling", (w_span, l_span, 0.22), (cx, cy, ceil_z + 0.11), ceil_m, bevel=0.0, parent=shell)
    ceil.visible_shadow = False

    # Warm recessed ceiling LED light panels & structural ceiling beams every 4m!
    for by in range(int(y_min) + 2, int(y_max) + 3, 4):
        beam = make_box(scene, "CeilBeam_%d" % by, (w_span - 1.0, 0.28, 0.18), (cx, float(by), ceil_z - 0.08), col_m, bevel=0.02, parent=shell)
        beam.visible_shadow = False
        for lx in (x_min + 2.2, 0.0, x_max - 2.2, x_max + 2.2):
            led = make_box(scene, "CeilLED_%d_%d" % (by, int(lx)), (1.35, 1.65, 0.05), (lx, float(by) + 2.0, ceil_z - 0.02), led_m, bevel=0.01, parent=shell)
            led.visible_shadow = False

    # 3. Back Wall at y_min (with optional south_openings=[(sx, sw), ...] cutouts + warm lit vestibule!)
    if south_openings:
        s_gaps = sorted(south_openings, key=lambda g: g[0])
        cur_sx = cx - w_span * 0.5
        s_end = cx + w_span * 0.5
        for idx_s, (sx, sw) in enumerate(s_gaps):
            seg_sw = (sx - sw * 0.5) - cur_sx
            if seg_sw > 0.05:
                make_box(scene, "BackWallSeg_%d" % idx_s, (seg_sw, 0.25, ceil_z), (cur_sx + seg_sw * 0.5, y_min, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
                make_box(scene, "BackBaseSeg_%d" % idx_s, (seg_sw, 0.30, 0.16), (cur_sx + seg_sw * 0.5, y_min + 0.04, 0.08), trim_m, bevel=0.0, parent=shell)
            make_box(scene, "BackDoorHeader_%d" % idx_s, (sw + 0.08, 0.26, ceil_z - 2.45), (sx, y_min, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
            # Warm lit vestibule recess behind south doorway so glass doors never reveal uncut drywall or void!
            make_box(scene, "SouthVestWallL_%d" % idx_s, (0.22, 3.4, ceil_z), (sx - sw * 0.5 - 0.11, y_min - 1.7, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "SouthVestWallR_%d" % idx_s, (0.22, 3.4, ceil_z), (sx + sw * 0.5 + 0.11, y_min - 1.7, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "SouthVestBack_%d" % idx_s, (sw + 0.6, 0.24, ceil_z), (sx, y_min - 3.3, ceil_z * 0.5), emissive_mat("south_vest_glow", (0.95, 0.91, 0.82), 0.95), bevel=0.0, parent=shell)
            sled = make_box(scene, "SouthVestLED_%d" % idx_s, (1.2, 1.2, 0.05), (sx, y_min - 1.6, ceil_z - 0.04), led_m, bevel=0.01, parent=shell)
            sled.visible_shadow = False
            cur_sx = sx + sw * 0.5
        rem_sw = s_end - cur_sx
        if rem_sw > 0.05:
            make_box(scene, "BackWallSeg_end", (rem_sw, 0.25, ceil_z), (cur_sx + rem_sw * 0.5, y_min, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "BackBaseSeg_end", (rem_sw, 0.30, 0.16), (cur_sx + rem_sw * 0.5, y_min + 0.04, 0.08), trim_m, bevel=0.0, parent=shell)
    else:
        make_box(scene, "BackWallSolid", (w_span, 0.25, ceil_z), (cx, y_min, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        make_box(scene, "BackBaseboard", (w_span, 0.30, 0.16), (cx, y_min + 0.04, 0.08), trim_m, bevel=0.0, parent=shell)

    # 4. Far side wall (with optional open east_archway=(ay, aw, ah) leading into a rich windowed concourse!)
    apron_sun_m = toon_rgb_mat("ext_apron_sun", (0.56, 0.58, 0.62))
    hill_m = toon_rgb_mat("ext_hill_warm", (0.58, 0.72, 0.46))
    if glass_side == "left":
        if east_archway is not None:
            ay, aw, ah = east_archway
            y_lo_seg = (ay - aw * 0.5) - (y_min - 4.0)
            if y_lo_seg > 0.2:
                make_box(scene, "FarSideWall_S", (0.25, y_lo_seg, ceil_z), (x_max, (y_min - 4.0) + y_lo_seg * 0.5, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            y_hi_seg = (y_max + 4.0) - (ay + aw * 0.5)
            if y_hi_seg > 0.2:
                make_box(scene, "FarSideWall_N", (0.25, y_hi_seg, ceil_z), (x_max, (ay + aw * 0.5) + y_hi_seg * 0.5, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "FarSideArchHeader", (0.30, aw + 0.4, ceil_z - ah), (x_max, ay, ah + (ceil_z - ah) * 0.5), wall_m, bevel=0.02, parent=shell)
            make_box(scene, "FarArchJamb_S", (0.36, 0.24, ah), (x_max, ay - aw * 0.5, ah * 0.5), trim_m, bevel=0.02, parent=shell)
            make_box(scene, "FarArchJamb_N", (0.36, 0.24, ah), (x_max, ay + aw * 0.5, ah * 0.5), trim_m, bevel=0.02, parent=shell)

            # Detailed windowed east concourse (x = x_max .. x_max + 10.5) with glass curtain wall, baseboards,
            # ceiling beams, planters, open double concourse doors, and security checkpoint vista beyond!
            corr_len = 10.5
            y_s = ay - aw * 0.5 - 0.1
            y_n = ay + aw * 0.5 + 0.1
            make_box(scene, "EastCorrWall_S", (corr_len, 0.22, ceil_z), (x_max + corr_len * 0.5, y_s, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "EastCorrBase_S", (corr_len, 0.28, 0.16), (x_max + corr_len * 0.5, y_s + 0.04, 0.08), trim_m, bevel=0.0, parent=shell)
            # North side of East Corridor: sunlit transparent glass curtain wall + upper soffit + mullions!
            make_box(scene, "EastCorrSoffit_N", (corr_len, 0.28, ceil_z - 2.45), (x_max + corr_len * 0.5, y_n, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
            for cwx in range(int(x_max) + 1, int(x_max + corr_len), 2):
                cwg, _, _, _ = load_glb("game/assets/interior/wall_glass.glb", "EastCorrWG_%d" % cwx, loc=(float(cwx), y_n - 0.05, 0.0), yaw_deg=0.0)
                cwg.scale = (2.0, 1.0, 1.0)
                cwg.parent = shell
            for cbx in range(int(x_max) + 3, int(x_max + corr_len), 3):
                cbeam = make_box(scene, "EastCorrBeam_%d" % cbx, (0.26, aw + 0.4, 0.18), (float(cbx), ay, ceil_z - 0.08), col_m, bevel=0.02, parent=shell)
                cbeam.visible_shadow = False
                cled = make_box(scene, "EastCorrLED_%d" % cbx, (1.4, 1.2, 0.05), (float(cbx) - 1.2, ay, ceil_z - 0.02), led_m, bevel=0.01, parent=shell)
                cled.visible_shadow = False
                make_box(scene, "EastCorrMullion_%d" % cbx, (0.28, 0.28, ceil_z), (float(cbx), y_n, ceil_z * 0.5), trim_m, bevel=0.02, parent=shell)
            # Exterior lawn & trees outside East Corridor glass!
            make_box(scene, "ExtApronNE", (22.0, 28.0, 0.10), (x_max + 11.2, y_n + 15.0, -0.05), apron_sun_m, bevel=0.0, parent=shell)
            make_box(scene, "ExtLawnNE", (22.0, 8.0, 0.09), (x_max + 11.2, y_n + 4.2, -0.04), horizon_grass_mat(), bevel=0.0, parent=shell)
            for etx in (x_max + 2.5, x_max + 6.5, x_max + 10.5):
                etr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "EastExtTree_%d" % int(etx), loc=(etx, y_n + 3.2, 0.0), outline_thickness=0.004)
                etr.scale = (1.7, 1.7, 1.7)
                etr.parent = shell
            # End of corridor at x_max + 7.4: clean bi-parting sliding glass door unit (100% enclosed pockets) + Security Arch beyond!
            door_x = x_max + 7.4
            make_sliding_glass_door_unit(
                scene,
                "EastCorrEndDoor",
                loc=(door_x, ay, 0.0),
                yaw_deg=90.0,
                clear_width=1.84,
                total_width=aw + 0.20,
                height=2.22,
                total_height=2.45,
                open_keys=[(1, 1.0)],
                parent=shell,
            )
            make_box(scene, "EastDoorSoffit", (0.28, aw + 0.4, ceil_z - 2.45), (door_x, ay, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
            # Visible Security Arch & X-ray belt right beyond the open doorway + warm back wall at x_max + corr_len!
            sa_vis, _, _, _ = load_glb("game/assets/interior/security_arch.glb", "EastVistaSecArch", loc=(door_x + 1.85, ay + 0.35, 0.0), yaw_deg=90.0)
            sa_vis.parent = shell
            xb_vis, _, _, _ = load_glb("game/assets/interior/xray_belt.glb", "EastVistaXray", loc=(door_x + 1.85, ay - 0.75, 0.0), yaw_deg=90.0)
            xb_vis.parent = shell
            make_box(scene, "EastCorrEndWall", (0.25, aw + 1.0, ceil_z), (x_max + corr_len, ay, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        else:
            make_box(scene, "FarSideWall", (0.25, l_span, ceil_z), (x_max, cy, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        soffit = make_box(scene, "GlassSoffitL", (0.32, l_span, ceil_z - 2.45), (x_min, cy, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        soffit.visible_shadow = False
        for py in range(int(y_min), int(y_max) + 1, 4):
            make_box(scene, "MullionColL_%d" % py, (0.34, 0.34, ceil_z), (x_min, float(py), ceil_z * 0.5), trim_m, bevel=0.02, parent=shell)
        # Cohesive sunlit exterior outside x_min glass wall (warm concrete apron + lawn + trees + Gotta Air plane + hills!)
        make_box(scene, "ExtLawnStripL", (5.5, 90.0, 0.09), (x_min - 3.2, cy, -0.04), horizon_grass_mat(), bevel=0.0, parent=shell)
        make_box(scene, "ExtApronL", (42.0, 90.0, 0.10), (x_min - 26.5, cy, -0.05), apron_sun_m, bevel=0.0, parent=shell)
        make_box(scene, "ExtGrassL", (90.0, 160.0, 0.08), (x_min - 85.0, cy, -0.06), horizon_grass_mat(), bevel=0.0, parent=shell)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(x_min - 95.0, cy, -2.0))
        ehl = bpy.context.active_object
        ehl.name = "ExtHillL"
        ehl.scale = (28.0, 95.0, 12.0)
        ehl.data.materials.append(hill_m)
        ehl.visible_shadow = False
        ehl.parent = shell
        ext_pl, ext_pl_objs, ext_pl_bn, _ = load_glb("game/assets/planes/tp_plane_03a.glb", "ExtWindowPlaneL", loc=(x_min - 18.5, cy + 1.5, 0.0), yaw_deg=20.0, outline_thickness=0.004)
        gmat = gotta_air_plane_mat()
        tp_b = toon_atlas_mat("tp_atlas_1a_d.png")
        for po in ext_pl_objs:
            if po.type == "MESH" and is_exterior_airframe_mesh(po.name):
                for sl in po.material_slots:
                    if sl.material == tp_b:
                        sl.material = gmat
        add_plane_wheel_chocks(scene, ext_pl, ext_pl_bn, "ExtPlaneL")
        ext_pl.parent = shell
        for ty in range(int(y_min) + 3, int(y_max), 6):
            tr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "ExtTreeL_%d" % ty, loc=(x_min - 3.6, float(ty), 0.0), outline_thickness=0.004)
            tr.scale = (1.65, 1.65, 1.65)
            tr.parent = shell
    else:
        make_box(scene, "FarSideWall", (0.25, l_span, ceil_z), (x_min, cy, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        soffit = make_box(scene, "GlassSoffitR", (0.32, l_span, ceil_z - 2.45), (x_max, cy, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        soffit.visible_shadow = False
        for py in range(int(y_min), int(y_max) + 1, 4):
            make_box(scene, "MullionColR_%d" % py, (0.34, 0.34, ceil_z), (x_max, float(py), ceil_z * 0.5), trim_m, bevel=0.02, parent=shell)
        make_box(scene, "ExtLawnStripR", (5.5, 90.0, 0.09), (x_max + 3.2, cy, -0.04), horizon_grass_mat(), bevel=0.0, parent=shell)
        make_box(scene, "ExtApronR", (42.0, 90.0, 0.10), (x_max + 26.5, cy, -0.05), apron_sun_m, bevel=0.0, parent=shell)
        make_box(scene, "ExtGrassR", (90.0, 160.0, 0.08), (x_max + 85.0, cy, -0.06), horizon_grass_mat(), bevel=0.0, parent=shell)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(x_max + 95.0, cy, -2.0))
        ehr = bpy.context.active_object
        ehr.name = "ExtHillR"
        ehr.scale = (28.0, 95.0, 12.0)
        ehr.data.materials.append(hill_m)
        ehr.visible_shadow = False
        ehr.parent = shell
        ext_pr, ext_pr_objs, ext_pr_bn, _ = load_glb("game/assets/planes/tp_plane_03a.glb", "ExtWindowPlaneR", loc=(x_max + 18.5, cy + 1.0, 0.0), yaw_deg=-160.0, outline_thickness=0.004)
        gmat = gotta_air_plane_mat()
        tp_b = toon_atlas_mat("tp_atlas_1a_d.png")
        for po in ext_pr_objs:
            if po.type == "MESH" and is_exterior_airframe_mesh(po.name):
                for sl in po.material_slots:
                    if sl.material == tp_b:
                        sl.material = gmat
        add_plane_wheel_chocks(scene, ext_pr, ext_pr_bn, "ExtPlaneR")
        ext_pr.parent = shell
        for ty in range(int(y_min) + 3, int(y_max), 6):
            tr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "ExtTreeR_%d" % ty, loc=(x_max + 3.6, float(ty), 0.0), outline_thickness=0.004)
            tr.scale = (1.65, 1.65, 1.65)
            tr.parent = shell

    # 5. North / Front Wall at y_max (open glass, open doorways with continuation hall, or solid)
    if open_north_wall:
        n_soffit = make_box(scene, "NorthGlassSoffit", (w_span, 0.32, ceil_z - 2.45), (cx, y_max, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        n_soffit.visible_shadow = False
    elif north_openings:
        gaps = sorted(north_openings, key=lambda g: g[0])
        cur_x = x_min - 4.0
        for idx_g, (gx, gw) in enumerate(gaps):
            seg_w = (gx - gw * 0.5) - cur_x
            if seg_w > 0.15:
                make_box(scene, "NorthWallSeg_%d" % idx_g, (seg_w, 0.25, ceil_z), (cur_x + seg_w * 0.5, y_max, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
                make_box(scene, "NorthBaseSeg_%d" % idx_g, (seg_w, 0.30, 0.16), (cur_x + seg_w * 0.5, y_max - 0.04, 0.08), trim_m, bevel=0.0, parent=shell)
            make_box(scene, "NorthDoorHeader_%d" % idx_g, (gw + 0.2, 0.26, ceil_z - 2.45), (gx, y_max, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
            cur_x = gx + gw * 0.5
        rem_w = (x_max + 4.0) - cur_x
        if rem_w > 0.15:
            make_box(scene, "NorthWallSeg_end", (rem_w, 0.25, ceil_z), (cur_x + rem_w * 0.5, y_max, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
            make_box(scene, "NorthBaseSeg_end", (rem_w, 0.30, 0.16), (cur_x + rem_w * 0.5, y_max - 0.04, 0.08), trim_m, bevel=0.0, parent=shell)
        # Warm lit north concourse backdrop 5.5m beyond y_max so open doorways show real terminal depth!
        make_box(scene, "NorthBeyondWall", (w_span, 0.25, ceil_z), (cx, y_max + 5.5, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
    else:
        make_box(scene, "NorthSolidWall", (w_span, 0.25, ceil_z), (cx, y_max, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        make_box(scene, "NorthBaseboard", (w_span, 0.30, 0.16), (cx, y_max - 0.04, 0.08), trim_m, bevel=0.0, parent=shell)

    return shell


# ---------------------------------------------------------------- GLB & Character Loaders


def load_glb(rel_path, label, loc=(0.0, 0.0, 0.0), yaw_deg=0.0, outline_thickness=0.005):
    full = os.path.join(REPO, *rel_path.split("/"))
    if not os.path.isfile(full):
        fail("missing glb: %s" % full)
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=full)
    new_objs = [o for o in bpy.data.objects if o not in before]
    new_acts = [a for a in bpy.data.actions if a not in acts_before]

    stem = os.path.splitext(os.path.basename(rel_path))[0]
    if stem == "jet_bridge":
        for o in new_objs:
            if base_name(o.name) == "Fold_Cap_Mesh":
                o.hide_render = True
                o.hide_viewport = True
    elif stem == "taxi_sign":
        keep = {"Glyph_Loc_A", "Glyph_Dir_C", "Glyph_Arrow_R"}
        for o in new_objs:
            bn = base_name(o.name)
            if bn.startswith("Glyph_") and bn.endswith("_Mesh") and bn[:-5] not in keep:
                o.hide_render = True
                o.hide_viewport = True
    elif stem.startswith("tp_runway_"):
        # Strip baked tiny colored approach-light confetti polygons (< 0.85 m^2) while keeping
        # 100% of the asphalt slabs and large white runway threshold/centerline markings!
        for o in new_objs:
            if o.type == "MESH":
                bm = bmesh.new()
                bm.from_mesh(o.data)
                tiny = [f for f in bm.faces if f.calc_area() < 0.85]
                if tiny:
                    bmesh.ops.delete(bm, geom=tiny, context="FACES")
                    bm.to_mesh(o.data)
                    o.data.update()
                bm.free()

    root = bpy.data.objects.new("ROOT_" + label, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = loc
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    for o in new_objs:
        if o.parent is None:
            o.parent = root

    is_veh = stem.startswith(("tp_taxi", "tp_suv", "tp_loading_truck", "pushback_tug"))
    rebind_materials(new_objs, label, outline_thickness=outline_thickness, is_vehicle=is_veh)
    bpy.context.view_layer.update()
    by_n = {base_name(o.name): o for o in new_objs}
    return root, new_objs, by_n, new_acts


def load_character(stem, label, cloth_tint=None, loc=(0.0, 0.0, 0.0), yaw_deg=0.0):
    rel = "game/assets/people/%s.glb" % stem
    full = os.path.join(REPO, *rel.split("/"))
    if not os.path.isfile(full):
        fail("missing character glb: %s" % full)
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=full)
    raw_objs = [o for o in bpy.data.objects if o not in before]
    acts = {base_name(a.name): a for a in bpy.data.actions if a not in acts_before}

    arm = next((o for o in raw_objs if o.type == "ARMATURE"), None)
    if arm is None:
        fail("%s: no armature found" % label)

    keep = []
    for o in raw_objs:
        skinned = o.parent is arm or any(m.type == "ARMATURE" for m in getattr(o, "modifiers", []))
        if o.type == "MESH" and not skinned:
            bpy.data.objects.remove(o)
        else:
            keep.append(o)

    root = bpy.data.objects.new("CHAR_" + label, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = loc
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    for o in keep:
        if o.parent is None:
            o.parent = root

    for o in keep:
        if o.type == "MESH":
            attr = o.data.color_attributes[0].name if len(o.data.color_attributes) else "Color"
            cmat = character_mat(label, cloth_tint_srgb=cloth_tint, attr_name=attr)
            for slot in o.material_slots:
                slot.material = cmat
            attach_outline(o, thickness=0.005)

    bpy.context.view_layer.update()
    return root, arm, keep, acts


_STRIDE_CACHE = {}


def _find_action(acts, clip_name):
    act = acts.get(clip_name)
    if act is not None:
        return act
    matches = [v for k, v in acts.items() if k.startswith(clip_name)]
    if not matches:
        fail("missing clip %r in %s" % (clip_name, sorted(acts.keys())))
    return matches[0]


def measure_clip_stride_rate(arm, act):
    """Measure stance-foot ground speed (meters per action frame) directly from `Foot.L`
    during floor contact so `strip_time = s(f) / rate` locks feet to the floor with zero slip."""
    key = (arm.data.name.split(".")[0], base_name(act.name))
    if key in _STRIDE_CACHE:
        return _STRIDE_CACHE[key]

    scene = bpy.context.scene
    prev_frame = scene.frame_current
    ad = arm.animation_data or arm.animation_data_create()
    prev_act = ad.action
    ad.action = act
    if hasattr(ad, "action_slot") and len(act.slots):
        ad.action_slot = act.slots[0]

    f0 = int(round(act.frame_range[0]))
    f1 = int(round(act.frame_range[1]))
    samples = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        pb = arm.pose.bones.get("Foot.L")
        if pb is not None:
            samples.append((f, float(pb.head.y), float(pb.head.z)))

    ad.action = prev_act
    scene.frame_set(prev_frame)
    bpy.context.view_layer.update()

    if len(samples) < 4:
        _STRIDE_CACHE[key] = 0.08
        return 0.08

    z_min = min(s[2] for s in samples)
    stance_dys = []
    for i in range(1, len(samples)):
        if samples[i - 1][2] <= z_min + 0.028 and samples[i][2] <= z_min + 0.028:
            dy = samples[i][1] - samples[i - 1][1]
            if dy > 0.01:
                stance_dys.append(dy)
    rate = float(np.median(stance_dys)) if stance_dys else 0.08
    _STRIDE_CACHE[key] = rate
    return rate


def _make_animated_nla_strip(ad, name, act, frame_end, blend_type="REPLACE"):
    trk = ad.nla_tracks.new()
    trk.name = "loco_" + name
    strip = trk.strips.new(name, 1, act)
    if hasattr(strip, "action_slot") and len(act.slots):
        strip.action_slot = act.slots[0]
    strip.frame_start = 1.0
    strip.frame_end = float(frame_end)
    strip.extrapolation = "HOLD"
    strip.blend_type = blend_type
    strip.use_animated_time = True
    strip.use_animated_time_cyclic = True
    strip.use_animated_influence = True
    return strip


def _set_fcurves_linear(anim_owner):
    """Force LINEAR keyframe interpolation on an Object or NlaStrip so motion never eases to 0."""
    fcurves = getattr(anim_owner, "fcurves", None)
    if fcurves is None:
        ad = getattr(anim_owner, "animation_data", None)
        act = getattr(ad, "action", None) if ad else None
        if act is not None:
            if hasattr(act, "layers") and len(act.layers):
                for layer in act.layers:
                    for strip in layer.strips:
                        if hasattr(strip, "channelbags"):
                            for bag in strip.channelbags:
                                for fc in bag.fcurves:
                                    for kp in fc.keyframe_points:
                                        kp.interpolation = "LINEAR"
            elif hasattr(act, "fcurves"):
                fcurves = act.fcurves
    if fcurves is not None:
        for fc in fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"


def set_stationary_clip(arm, acts, clip_name, frame_end, speed=1.0, phase_offset=0.0):
    """Play a single looping quaternion NLA clip (`idle`, `sit_idle`, `clean`) with phase offset."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    act = _find_action(acts, clip_name)
    st = _make_animated_nla_strip(ad, clip_name, act, frame_end)
    rate = (25.0 / FPS) * float(speed)
    for f in range(1, frame_end + 1):
        st.strip_time = float(phase_offset) + (f - 1) * rate
        st.keyframe_insert(data_path="strip_time", frame=f)
        st.influence = 1.0
        st.keyframe_insert(data_path="influence", frame=f)
    _set_fcurves_linear(st)


def _trapezoid_alpha(t, total_t, r_in, r_out):
    """Exact integral of trapezoidal speed profile with linear accel `r_in`, constant cruise,
    and linear decel `r_out` so travel segments are strictly LINEAR in cruise with smooth 6f starts/stops."""
    if total_t <= 1e-6:
        return 1.0
    r_in = float(min(r_in, total_t * 0.45))
    r_out = float(min(r_out, total_t * 0.45))
    area_total = total_t - 0.5 * r_in - 0.5 * r_out
    if area_total <= 1e-6:
        return t / total_t

    def area_at(x):
        x = max(0.0, min(total_t, float(x)))
        if x <= r_in and r_in > 0.0:
            return 0.5 * (x * x) / r_in
        a = 0.5 * r_in
        t_cruise_end = total_t - r_out
        if x <= t_cruise_end:
            return a + (x - r_in)
        a += max(0.0, t_cruise_end - r_in)
        rem = x - t_cruise_end
        if r_out > 0.0:
            a += rem - 0.5 * (rem * rem) / r_out
        return a

    return area_at(t) / area_total


def animate_character_locomotion(
    char_root,
    arm,
    acts,
    waypoints,
    frame_end,
    phase_offset=0.0,
    idle_speed=1.0,
    max_turn_deg_per_frame=13.5,
    corner_smooth_frames=2,
    seated_ranges=None,
):
    """Deterministic human locomotion controller:
    - Keeps 100% of armature PoseBones in `QUATERNION` mode (zero Euler T-pose overrides).
    - Evaluates piecewise linear travel waypoints with short 6-frame accel/decel ramps at rest boundaries.
    - Drives `walk` and `run` NLA `strip_time` strictly from cumulative ground distance `s(f) / stride_rate`
      so feet NEVER slide on the floor at any speed, and crossfades to `idle` (`v == 0`) with zero skating.
    - Computes unwrapped shortest-angle facing yaw from forward velocity tangent `atan2(dx, -dy)`
      (or explicit stop yaw `(frame, (x,y,z), yaw_deg)`), eliminating moonwalking and wrap-around spins.
    """
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    # Normalize waypoints to [(frame, Vector, explicit_yaw_or_None)]
    wps = []
    for item in waypoints:
        if len(item) == 2:
            f_w, p_w = item
            y_w = None
        else:
            f_w, p_w, y_w = item
        wps.append((int(f_w), Vector((float(p_w[0]), float(p_w[1]), float(p_w[2]))), y_w))
    wps.sort(key=lambda x: x[0])
    if wps[0][0] > 1:
        wps.insert(0, (1, wps[0][1].copy(), wps[0][2]))
    if wps[-1][0] < frame_end:
        wps.append((frame_end, wps[-1][1].copy(), wps[-1][2]))

    n_seg = len(wps) - 1
    seg_moving = [(wps[i + 1][1] - wps[i][1]).xy.length > 0.015 for i in range(n_seg)]

    raw_pos = [wps[0][1].copy() for _ in range(frame_end + 1)]
    hold_yaw = [None] * (frame_end + 1)

    for i in range(n_seg):
        f0, p0, y0 = wps[i]
        f1, p1, y1 = wps[i + 1]
        dur = max(1, f1 - f0)
        if not seg_moving[i]:
            for f in range(f0, f1 + 1):
                raw_pos[f] = p0.copy()
                hold_yaw[f] = y1 if y1 is not None else y0
        else:
            prev_stopped = (i > 0) and (not seg_moving[i - 1])
            next_stopped = (i + 1 < n_seg) and (not seg_moving[i + 1])
            r_in = 6.0 if prev_stopped else 0.0
            r_out = 6.0 if next_stopped else 0.0
            for f in range(f0, f1 + 1):
                a = _trapezoid_alpha(f - f0, float(dur), r_in, r_out)
                raw_pos[f] = p0.lerp(p1, a)
                if y1 is not None and f == f1 and next_stopped:
                    hold_yaw[f] = y1

    # Gentle corner rounding across moving-to-moving waypoints (preserves exact stopped frames!)
    pos = [p.copy() for p in raw_pos]
    if corner_smooth_frames > 0:
        rad = int(corner_smooth_frames)
        for f in range(2, frame_end):
            if hold_yaw[f] is not None:
                continue
            d_prev = (raw_pos[f] - raw_pos[f - 1]).xy.length
            d_next = (raw_pos[f + 1] - raw_pos[f]).xy.length
            if d_prev > 0.005 and d_next > 0.005:
                lo_f = max(1, f - rad)
                hi_f = min(frame_end, f + rad)
                acc = Vector((0.0, 0.0, 0.0))
                for k in range(lo_f, hi_f + 1):
                    acc += raw_pos[k]
                pos[f] = acc / float(hi_f - lo_f + 1)

    def _is_seated(fr):
        if not seated_ranges:
            return False
        return any(s0 <= fr <= s1 for s0, s1 in seated_ranges)

    # Compute per-frame horizontal step, 3D stride step (including stair climbs), and unwrapped yaw!
    ds_xy = [0.0] * (frame_end + 1)
    ds_stride = [0.0] * (frame_end + 1)
    for f in range(2, frame_end + 1):
        d = pos[f] - pos[f - 1]
        ds_xy[f] = d.xy.length
        ds_stride[f] = math.hypot(d.xy.length, max(0.0, d.z) * 0.65)
    ds_xy[1] = ds_xy[2] if frame_end >= 2 else 0.0
    ds_stride[1] = ds_stride[2] if frame_end >= 2 else 0.0

    # Determine initial yaw at frame 1
    init_yaw = wps[0][2]
    if init_yaw is None:
        for f in range(2, frame_end + 1):
            v = (pos[f] - pos[1]).xy
            if v.length > 0.02:
                init_yaw = math.degrees(math.atan2(v.x, -v.y))
                break
    if init_yaw is None:
        init_yaw = math.degrees(char_root.rotation_euler.z)

    yaws = [float(init_yaw)] * (frame_end + 1)
    for f in range(2, frame_end + 1):
        # Centered tangent when moving on foot
        f_a = max(1, f - 2)
        f_b = min(frame_end, f + 2)
        tang = (pos[f_b] - pos[f_a]).xy
        if (not _is_seated(f)) and ds_xy[f] > 0.004 and tang.length > 0.012:
            target_yaw = math.degrees(math.atan2(tang.x, -tang.y))
        elif hold_yaw[f] is not None:
            target_yaw = float(hold_yaw[f])
        else:
            target_yaw = yaws[f - 1]
        delta = ((target_yaw - yaws[f - 1] + 180.0) % 360.0) - 180.0
        step_deg = max(-max_turn_deg_per_frame, min(max_turn_deg_per_frame, delta))
        yaws[f] = yaws[f - 1] + step_deg

    # Measure true stance foot rates BEFORE creating NLA tracks
    act_idle = _find_action(acts, "idle")
    act_walk = _find_action(acts, "walk")
    act_run = acts.get("run") or next((v for k, v in acts.items() if k.startswith("run")), None)
    act_sit = acts.get("sit_idle") or next((v for k, v in acts.items() if k.startswith("sit_idle")), None)
    walk_rate = measure_clip_stride_rate(arm, act_walk)
    run_rate = measure_clip_stride_rate(arm, act_run) if act_run is not None else walk_rate * 2.2

    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)

    st_idle = _make_animated_nla_strip(ad, "idle", act_idle, frame_end)
    st_sit = _make_animated_nla_strip(ad, "sit_idle", act_sit, frame_end) if (seated_ranges and act_sit) else None
    st_walk = _make_animated_nla_strip(ad, "walk", act_walk, frame_end)
    Peak_v = max(ds_stride[f] * FPS for f in range(1, frame_end + 1) if not _is_seated(f)) if frame_end >= 1 else 0.0
    st_run = _make_animated_nla_strip(ad, "run", act_run, frame_end) if (act_run is not None and Peak_v > 1.95) else None

    char_root.rotation_mode = "XYZ"
    s_walk = 0.0
    s_run = 0.0
    w_inf_smooth = 0.0
    r_inf_smooth = 0.0

    for f in range(1, frame_end + 1):
        char_root.location = pos[f]
        char_root.keyframe_insert(data_path="location", frame=f)
        char_root.rotation_euler = (0.0, 0.0, math.radians(yaws[f]))
        char_root.keyframe_insert(data_path="rotation_euler", frame=f)

        seated = _is_seated(f)
        v_mps = 0.0 if seated else (ds_stride[f] * FPS)
        dyaw_f = 0.0 if (f <= 1 or seated) else abs(yaws[f] - yaws[f - 1])
        ds_turn = math.radians(dyaw_f) * 0.28 if dyaw_f > 1.1 else 0.0
        if f > 1 and not seated:
            s_walk += max(ds_stride[f], ds_turn)
            s_run += ds_stride[f]

        # Smooth NLA crossfade weights (natural stepping on stationary pivots, zero skating in idle!)
        turn_w = min(0.62, dyaw_f / 14.0) if dyaw_f > 1.1 else 0.0
        target_w = max(turn_w, 0.0 if v_mps < 0.08 else min(1.0, (v_mps - 0.08) / 0.42))
        target_r = 0.0 if v_mps < 1.95 else min(1.0, (v_mps - 1.95) / 0.60)
        w_inf_smooth = target_w if f == 1 else (0.62 * w_inf_smooth + 0.38 * target_w)
        r_inf_smooth = target_r if f == 1 else (0.65 * r_inf_smooth + 0.35 * target_r)
        if v_mps < 0.04 and dyaw_f < 0.8:
            w_inf_smooth = 0.0
            r_inf_smooth = 0.0

        st_idle.strip_time = float(phase_offset) + (f - 1) * (25.0 / FPS) * float(idle_speed)
        st_idle.keyframe_insert(data_path="strip_time", frame=f)
        st_idle.influence = 1.0
        st_idle.keyframe_insert(data_path="influence", frame=f)

        if st_sit is not None:
            st_sit.strip_time = float(phase_offset) + (f - 1) * (25.0 / FPS)
            st_sit.keyframe_insert(data_path="strip_time", frame=f)
            st_sit.influence = 1.0 if seated else 0.0
            st_sit.keyframe_insert(data_path="influence", frame=f)

        st_walk.strip_time = float(phase_offset) + (s_walk / walk_rate)
        st_walk.keyframe_insert(data_path="strip_time", frame=f)
        st_walk.influence = float(round(w_inf_smooth, 4))
        st_walk.keyframe_insert(data_path="influence", frame=f)

        if st_run is not None:
            st_run.strip_time = float(phase_offset) + (s_run / run_rate)
            st_run.keyframe_insert(data_path="strip_time", frame=f)
            st_run.influence = float(round(r_inf_smooth, 4))
            st_run.keyframe_insert(data_path="influence", frame=f)

    _set_fcurves_linear(char_root)
    for st in (st_idle, st_sit, st_walk, st_run):
        if st is not None:
            _set_fcurves_linear(st)


def bind_hand_ik_target(
    scene,
    arm,
    name,
    hand="R",
    target_obj=None,
    parent=None,
    pos_keys=None,
    influence_keys=None,
    pole_parent=None,
    pole_loc=None,
    pole_angle_deg=None,
):
    """Drive `Forearm.<hand>` with a 2-bone IK constraint + mandatory anatomical elbow pole
    while keeping `rotation_mode == 'QUATERNION'` (`F-22`)."""
    pb = arm.pose.bones.get("Forearm." + hand)
    if pb is None:
        fail("bind_hand_ik_target: Forearm.%s missing on %s" % (hand, arm.name))
    pb.rotation_mode = "QUATERNION"
    if target_obj is None:
        target_obj = bpy.data.objects.new("IKGoal_%s_%s" % (name, hand), None)
        scene.collection.objects.link(target_obj)
        if parent is not None:
            target_obj.parent = parent
    if pos_keys:
        key_pos(target_obj, pos_keys)
        _set_fcurves_linear(target_obj)

    if pole_parent is None:
        pole_parent = arm.parent
    if pole_loc is None:
        pole_loc = (-0.38, 0.35, 0.85) if hand == "R" else (0.38, 0.35, 0.85)
    if pole_angle_deg is None:
        pole_angle_deg = 30.0 if hand == "R" else 150.0

    ik = pb.constraints.new("IK")
    ik.name = "IK_%s_%s" % (name, hand)
    ik.target = target_obj
    ik.chain_count = 2
    pole_ob = bpy.data.objects.new("IKPole_%s_%s" % (name, hand), None)
    scene.collection.objects.link(pole_ob)
    if pole_parent is not None:
        pole_ob.parent = pole_parent
    pole_ob.location = pole_loc
    ik.pole_target = pole_ob
    ik.pole_angle = math.radians(float(pole_angle_deg))
    if influence_keys:
        for f, val in influence_keys:
            ik.influence = float(val)
            ik.keyframe_insert(data_path="influence", frame=int(f))
    else:
        ik.influence = 1.0
    return ik, target_obj


def _build_active_inf_keys(active_ranges, frame_end):
    inf_keys = []
    if len(active_ranges) == 1 and active_ranges[0][0] <= 1:
        f1 = active_ranges[0][1]
        inf_keys = [(1, 1.0), (f1, 1.0)]
        if f1 < frame_end:
            inf_keys.append((min(frame_end, f1 + 4), 0.0))
    else:
        inf_keys.append((1, 0.0))
        for f0, f1 in active_ranges:
            if f0 > 2:
                inf_keys.append((max(1, f0 - 4), 0.0))
            inf_keys.append((f0, 1.0))
            inf_keys.append((f1, 1.0))
            if f1 < frame_end:
                inf_keys.append((min(frame_end, f1 + 4), 0.0))
    return inf_keys


def bind_hand_fist_curl(scene, arm, name, hand="R", influence_keys=None, mode="fist"):
    """Pose `Fingers.<hand>`, `Fingertips.<hand>`, `Thumb.<hand>`, and `Thumb_Tip.<hand>` around
    true knuckle hinge **local `+X`** (`+72°` / `+78°`, NEVER local Z) + palmar `+Z` thumb opposition
    (`mode='fist'`), or thumb-index card pinch (`mode='pinch'`), overriding NLA finger Z-splay cleanly
    while keeping `rotation_mode == 'QUATERNION'` (`F-02`, `F-07`, `F-08`)."""
    sgn_t = -1.0 if hand == "R" else 1.0
    if mode == "pinch":
        curl_specs = [
            ("Fingers." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(38.0))),
            ("Fingertips." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(34.0))),
            ("Thumb." + hand, Quaternion((0.0, 0.0, sgn_t), math.radians(48.0)) @ Quaternion((1.0, 0.0, 0.0), math.radians(26.0))),
            ("Thumb_Tip." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(30.0))),
        ]
    elif mode == "flat":
        curl_specs = [
            ("Fingers." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(14.0))),
            ("Fingertips." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(12.0))),
            ("Thumb." + hand, Quaternion((0.0, 0.0, sgn_t), math.radians(22.0)) @ Quaternion((1.0, 0.0, 0.0), math.radians(10.0))),
            ("Thumb_Tip." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(12.0))),
        ]
    else:
        curl_specs = [
            ("Fingers." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(78.0))),
            ("Fingertips." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(84.0))),
            ("Thumb." + hand, Quaternion((0.0, 0.0, sgn_t), math.radians(44.0)) @ Quaternion((1.0, 0.0, 0.0), math.radians(24.0))),
            ("Thumb_Tip." + hand, Quaternion((1.0, 0.0, 0.0), math.radians(48.0))),
        ]
    for bname, q_loc in curl_specs:
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        emp = bpy.data.objects.new("FistCurl_%s_%s" % (name, bname), None)
        emp.rotation_mode = "QUATERNION"
        emp.rotation_quaternion = q_loc
        scene.collection.objects.link(emp)
        cns = pb.constraints.new("COPY_ROTATION")
        cns.name = "Fist_%s_%s" % (name, bname)
        cns.target = emp
        cns.target_space = "WORLD"
        cns.owner_space = "LOCAL"
        cns.mix_mode = "REPLACE"
        if influence_keys:
            for f, v in influence_keys:
                cns.influence = float(v)
                cns.keyframe_insert(data_path="influence", frame=int(f))
            _set_fcurves_linear(arm)
        else:
            cns.influence = 1.0


def bind_prop_in_palm(
    scene,
    prop_obj,
    arm,
    hand="R",
    name="PalmProp",
    local_loc=None,
    local_rot_deg=(0.0, 0.0, 90.0),
    influence_keys=None,
):
    """Mount a cylindrical tool/wand/scanner inside the `+Z` palmar curl hollow aligned along
    `Hand.<hand>.x_axis` (knuckle row) and curl fingers `+72°/+78°` around `+X` (`F-08`)."""
    if local_loc is None:
        local_loc = (-0.01, 0.096, 0.036) if hand == "R" else (0.01, 0.096, 0.036)
    parent_prop_to_bone(prop_obj, arm, "Hand." + hand, local_loc=local_loc, local_rot_deg=local_rot_deg)
    bind_hand_fist_curl(scene, arm, name, hand=hand, influence_keys=influence_keys, mode="fist")


def bind_card_in_pinch(scene, card_obj, arm, hand="L", name="PinchCard", influence_keys=None):
    """Mount a thin `BoardingPass` card cleanly between `Thumb_Tip.<hand>` and `Fingers.<hand>`
    with `0` wrist/forearm penetration (`F-07`)."""
    # Place card edge right inside thumb-index pinch hollow (~15 cm distal from wrist, +Z palmar side)
    # extending outward/forward clear of forearm & palm!
    x_off = 0.135 if hand == "L" else -0.135
    parent_prop_to_bone(
        card_obj,
        arm,
        "Hand." + hand,
        local_loc=(x_off, 0.168, 0.044),
        local_rot_deg=(14.0, 0.0, 0.0),
    )
    bind_hand_fist_curl(scene, arm, name, hand=hand, influence_keys=influence_keys, mode="pinch")


def rig_two_hand_floor_mop(scene, char_root, arm, spill_xy=(-2.25, -8.75), frame_end=225):
    """Build world-space `CleanerMop` with `MopHead` sliding flat across the floor (`z_min` in `[0.0, 0.03 m]`)
    and BOTH `Hand.R` (upper shaft) and `Hand.L` (mid shaft) locked onto the stick via 2-bone IK +
    `Hand.x_axis` shaft alignment + `+X` closed-fist curl (`F-08`)."""
    mop_root = bpy.data.objects.new("CleanerMop", None)
    scene.collection.objects.link(mop_root)

    head_ob = make_box(
        scene,
        "MopHead",
        (0.28, 0.14, 0.042),
        (0.0, 0.0, 0.023),
        toon_rgb_mat("mop_cotton", CREAM),
        bevel=0.012,
        parent=mop_root,
        outline=0.003,
    )
    shaft_piv = bpy.data.objects.new("MopShaftPivot", None)
    shaft_piv.location = (0.0, 0.0, 0.042)
    shaft_piv.parent = mop_root
    scene.collection.objects.link(shaft_piv)

    stick_ob = make_box(
        scene,
        "MopStick",
        (0.030, 0.030, 1.38),
        (0.0, 0.0, 0.69),
        toon_rgb_mat("mop_wood", (0.72, 0.52, 0.30)),
        bevel=0.005,
        parent=shaft_piv,
        outline=0.003,
    )

    sx, sy = float(spill_xy[0]), float(spill_xy[1])
    chest_pt = char_root.matrix_world @ Vector((0.0, -0.22, 1.18))
    mop_pos_keys = []
    piv_rot_keys = []
    for f in range(1, int(frame_end) + 1):
        ph = 2.0 * math.pi * (f - 1) / 48.0
        mx = sx + 0.16 * math.sin(ph)
        my = sy + 0.07 * math.cos(2.0 * ph)
        mop_pos_keys.append((f, (mx, my, 0.0)))
        # Aim shaft_piv +Z axis from mop head up toward cleaner's chest!
        v_up = (chest_pt - Vector((mx, my, 0.042))).normalized()
        rx = math.degrees(math.asin(max(-0.85, min(0.85, -v_up.y))))
        ry = math.degrees(math.atan2(v_up.x, v_up.z))
        piv_rot_keys.append((f, (rx, ry, 0.0)))

    key_pos(mop_root, mop_pos_keys)
    _set_fcurves_linear(mop_root)
    key_rot_deg(shaft_piv, piv_rot_keys)
    _set_fcurves_linear(shaft_piv)

    bind_hand_fist_curl(scene, arm, "MopFistR", hand="R")
    bind_hand_fist_curl(scene, arm, "MopFistL", hand="L")

    goal_r = bpy.data.objects.new("MopWristGoal_R", None)
    goal_l = bpy.data.objects.new("MopWristGoal_L", None)
    rot_r = bpy.data.objects.new("MopHandRot_R", None)
    rot_l = bpy.data.objects.new("MopHandRot_L", None)
    rot_r.rotation_mode = "QUATERNION"
    rot_l.rotation_mode = "QUATERNION"
    for ob_m in (goal_r, goal_l, rot_r, rot_l):
        scene.collection.objects.link(ob_m)

    bind_hand_ik_target(scene, arm, "MopHoldR", hand="R", target_obj=goal_r, pole_parent=char_root, pole_loc=(-0.38, 0.35, 0.85))
    bind_hand_ik_target(scene, arm, "MopHoldL", hand="L", target_obj=goal_l, pole_parent=char_root, pole_loc=(0.38, 0.35, 0.85))

    for _it in range(2):
        kr_pos, kl_pos, kr_q, kl_q = [], [], [], []
        prev_qr = prev_ql = None
        for f in range(1, int(frame_end) + 1):
            scene.frame_set(f)
            bpy.context.view_layer.update()
            smw = shaft_piv.matrix_world
            shaft_up = (smw.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
            p_grip_r = smw @ Vector((0.0, 0.0, 1.20))
            p_grip_l = smw @ Vector((0.0, 0.0, 0.96))

            for side, p_g, kpos, kq, prev_q, x_sgn in (
                ("R", p_grip_r, kr_pos, kr_q, prev_qr, -1.0),
                ("L", p_grip_l, kl_pos, kl_q, prev_ql, 1.0),
            ):
                # Align Hand.x_axis strictly along shaft (`x_sgn * shaft_up` -> thumb points up shaft!)
                x_h = (shaft_up * x_sgn).normalized()
                sh_w = arm.matrix_world @ arm.pose.bones["Arm." + side].head
                y_raw = (p_g - sh_w).normalized()
                y_proj = y_raw - x_h * y_raw.dot(x_h)
                y_h = y_proj.normalized() if y_proj.length > 1e-4 else Vector((0.0, 1.0, 0.0))
                z_h = x_h.cross(y_h).normalized()
                rm = Matrix(((x_h.x, y_h.x, z_h.x), (x_h.y, y_h.y, z_h.y), (x_h.z, y_h.z, z_h.z)))
                qh = rm.to_quaternion()
                if prev_q is not None and prev_q.dot(qh) < 0.0:
                    qh = Quaternion((-qh.w, -qh.x, -qh.y, -qh.z))
                if side == "R":
                    prev_qr = qh
                else:
                    prev_ql = qh
                pw = p_g - y_h * 0.096 - z_h * 0.032
                kpos.append((f, (float(pw.x), float(pw.y), float(pw.z))))
                kq.append((f, qh))
        key_pos(goal_r, kr_pos)
        key_pos(goal_l, kl_pos)
        _set_fcurves_linear(goal_r)
        _set_fcurves_linear(goal_l)

    for ob_q, qlist in ((rot_r, kr_q), (rot_l, kl_q)):
        for f, qv in qlist:
            ob_q.rotation_quaternion = qv
            ob_q.keyframe_insert(data_path="rotation_quaternion", frame=f)
        _set_fcurves_linear(ob_q)

    for side, ob_q in (("R", rot_r), ("L", rot_l)):
        pb_h = arm.pose.bones["Hand." + side]
        pb_h.rotation_mode = "QUATERNION"
        cr = pb_h.constraints.new("COPY_ROTATION")
        cr.name = "LockMopWrist_" + side
        cr.target = ob_q
        cr.target_space = "WORLD"
        cr.owner_space = "WORLD"

    bind_head_look_at(scene, arm, "CleanerLookMop", target_obj=head_ob, max_inf=0.55, include_spine=True)
    scene.frame_set(1)
    return mop_root, head_ob, stick_ob


def solve_roller_bar_grip_targets(
    scene,
    char_root,
    arm,
    bag_root,
    pull_top,
    label,
    active_ranges,
    hand="R",
    bind_ik=True,
    override_world_fn=None,
    fist_inf_keys=None,
    ik_inf_keys=None,
    bar_local_offset=None,
):
    """Solve converged per-frame palm-hollow wrist IK goal + locked overhand `Hand.<hand>` `COPY_ROTATION`:
    - Aligns knuckle row (`Hand.x_axis`) parallel to `±bag_x` (`|dot| == 1.0`).
    - Orthogonalizes `Hand.y_axis` along forearm->hand and points palm normal (`Hand.z_axis`)
      perpendicular into `Pull_Top` so the bar rests inside the `+Z` palmar curl hollow with
      zero dorsal penetration (`F-02`).
    - Optional `override_world_fn(f)` returns `(p_wrist, q_hand)` on custom side/end-clasp frames (Shot 3).
    """
    N = int(scene.frame_end)
    inf_keys = ik_inf_keys if ik_inf_keys is not None else _build_active_inf_keys(active_ranges, N)
    bind_hand_fist_curl(
        scene,
        arm,
        label,
        hand=hand,
        influence_keys=fist_inf_keys if fist_inf_keys is not None else inf_keys,
        mode="fist",
    )

    wrist_goal = bpy.data.objects.new("RollerWristGoal_" + label, None)
    scene.collection.objects.link(wrist_goal)
    hand_rot = bpy.data.objects.new("RollerHandRot_" + label, None)
    hand_rot.rotation_mode = "QUATERNION"
    scene.collection.objects.link(hand_rot)

    init_keys = []
    for f in range(1, N + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        ov_res = override_world_fn(f) if override_world_fn is not None else None
        if ov_res is not None:
            pw0 = ov_res[0]
            init_keys.append((f, (float(pw0.x), float(pw0.y), float(pw0.z))))
        else:
            if callable(bar_local_offset):
                boff0 = bar_local_offset(f)
            elif bar_local_offset is not None:
                boff0 = bar_local_offset
            else:
                boff0 = (0.0, -0.018, 0.004) if float(pull_top.location.y) > -0.40 else (0.0, -0.056, 0.014)
            p_bar = pull_top.matrix_world @ Vector(boff0)
            init_keys.append((f, (float(p_bar.x), float(p_bar.y), float(p_bar.z) + 0.088)))
    key_pos(wrist_goal, init_keys)
    _set_fcurves_linear(wrist_goal)

    ik = None
    if bind_ik:
        # Low posterior-medial elbow pole (`(-0.22, 0.52, 0.68)`, `78°` for R) and anatomical downward/outward pole (`(0.42, -0.22, 0.45)`, `105°` for L)
        p_loc = (-0.22, 0.52, 0.68) if hand == "R" else (0.42, -0.22, 0.45)
        p_ang = 78.0 if hand == "R" else 105.0
        ik, _ = bind_hand_ik_target(
            scene,
            arm,
            "GripRoller_" + label,
            hand=hand,
            target_obj=wrist_goal,
            influence_keys=inf_keys,
            pole_parent=char_root,
            pole_loc=p_loc,
            pole_angle_deg=p_ang,
        )

    for _it in range(3):
        wg_keys = []
        hr_quats = []
        prev_q = None
        for f in range(1, N + 1):
            scene.frame_set(f)
            bpy.context.view_layer.update()
            ov_res = override_world_fn(f) if override_world_fn is not None else None
            if ov_res is not None:
                p_wrist, q_hand = ov_res
            else:
                pt_mw = pull_top.matrix_world
                bm3 = bag_root.matrix_world.to_3x3()
                bag_x = (bm3 @ Vector((1.0, 0.0, 0.0))).normalized()
                if callable(bar_local_offset):
                    boff = bar_local_offset(f)
                elif bar_local_offset is not None:
                    boff = bar_local_offset
                else:
                    boff = (0.0, -0.018, 0.004) if float(pull_top.location.y) > -0.40 else (0.0, -0.056, 0.014)
                p_bar = pt_mw @ Vector(boff)

                fa = arm.pose.bones["Forearm." + hand]
                fa_dir = (arm.matrix_world.to_3x3() @ fa.y_axis).normalized()
                rod_front = (bm3 @ Vector((0.0, 0.0, 1.0))).normalized()

                # Knuckle row `x_hand` aligned strictly parallel to crossbar (`-bag_x` for Hand.R overhand so thumb is inward `+bag_x`)
                x_hand = (-bag_x if hand == "R" else bag_x).normalized()
                y_proj = fa_dir - x_hand * fa_dir.dot(x_hand)
                y_hand = y_proj.normalized() if y_proj.length > 1e-4 else rod_front
                z_hand = x_hand.cross(y_hand).normalized()
                rot_m = Matrix((
                    (x_hand.x, y_hand.x, z_hand.x),
                    (x_hand.y, y_hand.y, z_hand.y),
                    (x_hand.z, y_hand.z, z_hand.z),
                ))
                q_hand = rot_m.to_quaternion()
                p_wrist = p_bar - y_hand * 0.096 - z_hand * 0.034

            if prev_q is not None and prev_q.dot(q_hand) < 0.0:
                q_hand = Quaternion((-q_hand.w, -q_hand.x, -q_hand.y, -q_hand.z))
            prev_q = q_hand
            wg_keys.append((f, (float(p_wrist.x), float(p_wrist.y), float(p_wrist.z))))
            hr_quats.append((f, q_hand))

        key_pos(wrist_goal, wg_keys)
        _set_fcurves_linear(wrist_goal)

    for f, qh in hr_quats:
        hand_rot.rotation_quaternion = qh
        hand_rot.keyframe_insert(data_path="rotation_quaternion", frame=f)
    _set_fcurves_linear(hand_rot)

    pb_hand = arm.pose.bones["Hand." + hand]
    pb_hand.rotation_mode = "QUATERNION"
    cr_cns = pb_hand.constraints.new("COPY_ROTATION")
    cr_cns.name = "LockWrist_" + label
    cr_cns.target = hand_rot
    cr_cns.target_space = "WORLD"
    cr_cns.owner_space = "WORLD"
    for f, v in inf_keys:
        cr_cns.influence = float(v)
        cr_cns.keyframe_insert(data_path="influence", frame=int(f))
    scene.frame_set(1)
    return ik, wrist_goal, hand_rot


def setup_world_roller_and_grip(
    scene,
    hero_root,
    hero_arm,
    label,
    f_ik_ranges,
    pose_ranges=None,
    ground_z=0.0,
    custom_world_poses=None,
    override_grip_fn=None,
    fist_inf_keys=None,
    ik_inf_keys=None,
):
    """Spawn `CarryRoller` in WORLD SPACE (`parent=None`) with:
    - Outboard hitch (`x_local <= -0.50 m` on body, `<= -0.40 m` on rods) completely clear of
      Hero's `run` right-leg back-kick (`F-01`).
    - Hip-clear `"stand"` (`(-0.49, -0.06, 0.0)`) and `"carry"` (`(-0.46, -0.04, 0.78)` with `-14°` outward roll).
    - Hero-local polar coordinate interpolation (`side_radius >= 0.48 m`) across all mode/turn transitions
      so the suitcase never chords through legs or pelvis (`F-01`).
    - Shared `solve_roller_bar_grip_targets` (`F-02`).
    """
    N = int(scene.frame_end)
    if not pose_ranges:
        pose_ranges = [(1, N, "tow")]

    bag_root, _, bag_by_n = load_roller_bag(
        label,
        extended="tow",
        loc=(0.0, 0.0, float(ground_z) + 0.198),
        yaw_deg=0.0,
        bag_tint=YELLOW,
        parent=None,
        bag_scale=1.12,
    )
    bag_root.rotation_mode = "XYZ"

    for f0, f1, mode in pose_ranges:
        if mode == "custom":
            continue
        ext_m = "security" if mode in ("carry", "cabin_carry") else mode
        set_roller_handle(bag_by_n, extended=ext_m, frame=f0)
        set_roller_handle(bag_by_n, extended=ext_m, frame=f1)
    if bag_by_n.get("Pull_Reach"):
        _set_fcurves_linear(bag_by_n["Pull_Reach"])
    if bag_by_n.get("Pull_Top"):
        _set_fcurves_linear(bag_by_n["Pull_Top"])

    hero_samples = {}
    for f in range(1, N + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        hmw = hero_root.matrix_world.copy()
        hfwd = (hmw.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
        hright = (hmw.to_3x3() @ Vector((-1.0, 0.0, 0.0))).normalized()
        hyaw = math.degrees(math.atan2(hfwd.x, -hfwd.y))
        sh_w = hero_arm.matrix_world @ hero_arm.pose.bones["Arm.R"].head
        hero_samples[f] = (hmw, hfwd, hright, hyaw, float(sh_w.z), sh_w.copy())

    def _unwrap_deg(prev_d, target_d):
        return prev_d + (((target_d - prev_d + 180.0) % 360.0) - 180.0)

    bag_pos = {}
    bag_rot = {}
    bag_xy = None
    bag_yaw = None
    theta_deg = 58.0

    for f0, f1, mode in pose_ranges:
        for f in range(int(f0), int(f1) + 1):
            hmw, hfwd, hright, hyaw, sh_z, sh_w = hero_samples[f]
            h_loc = hmw.translation
            if bag_yaw is None:
                bag_yaw = hyaw
            if mode == "custom" and custom_world_poses and f in custom_world_poses:
                cp_p, cp_r = custom_world_poses[f]
                bag_pos[f] = Vector(cp_p)
                bag_yaw = _unwrap_deg(bag_yaw, cp_r[2])
                bag_rot[f] = (float(cp_r[0]), float(cp_r[1]), bag_yaw)
                bag_xy = Vector((float(cp_p[0]), float(cp_p[1])))
            elif mode in ("tow", "walk_tow"):
                # Place wheels cleanly outboard (`x_hero = -0.62`, `0` Quad.R/leg/pelvis BVH overlap) and trail at
                # `y_hero = 0.610..0.645` with `+29.0°` inward handle yaw + `d_sh = 0.555m` reach so `Arm.R + Forearm.R`
                # (`0.5125m` bone sum + `0.096m` palm) hangs naturally (`sh_z - el_z >= 0.13m`, `kink <= 31.5°`, `ike == 0`)!
                lx = -0.62
                ly = 0.610 if mode == "walk_tow" else 0.645
                w_corr = hmw @ Vector((lx, ly, 0.0))
                if bag_xy is None or f == int(f0):
                    bag_xy = Vector((float(w_corr.x), float(w_corr.y)))
                    bag_yaw = _unwrap_deg(bag_yaw, hyaw + 29.0)
                else:
                    bag_xy = bag_xy.lerp(Vector((float(w_corr.x), float(w_corr.y))), 0.80)
                    bag_yaw = bag_yaw + 0.65 * ((((hyaw + 29.0) - bag_yaw + 180.0) % 360.0) - 180.0)
                    h_inv = hmw.inverted()
                    loc_in_h = h_inv @ Vector((float(bag_xy.x), float(bag_xy.y), float(h_loc.z)))
                    cx_h = max(-0.64, min(-0.60, float(loc_in_h.x)))
                    cy_h = max(0.58 if mode == "walk_tow" else 0.62, min(0.67, float(loc_in_h.y)))
                    wc2 = hmw @ Vector((cx_h, cy_h, 0.0))
                    bag_xy = Vector((float(wc2.x), float(wc2.y)))

                rel_yaw = ((bag_yaw - hyaw + 180.0) % 360.0) - 180.0
                if rel_yaw < 27.0 or rel_yaw > 31.0:
                    bag_yaw = hyaw + max(27.0, min(31.0, rel_yaw))

                # Solve handle tilt `theta_deg` in `[24°, 66°]` so `p_bar` sits at `d_sh ~ 0.556m`, `dz_sh >= 0.530m`
                # below `Arm.R.head` (`p_wrist` ~ `0.47m` from shoulder <= `0.5125m` 2-bone arm length)!
                L_bar = 1.12 * (0.916 if mode == "walk_tow" else 0.906)
                bfwd_3d = Vector((math.sin(math.radians(bag_yaw)), -math.cos(math.radians(bag_yaw)), 0.0))
                best_th = 40.0
                best_cost = 999.0
                for th_try in range(24, 67, 2):
                    th_r = math.radians(th_try)
                    bz_t = float(ground_z) + 0.2464 * math.sin(th_r) + 0.004
                    p_b_try = Vector((float(bag_xy.x), float(bag_xy.y), bz_t)) + bfwd_3d * (L_bar * math.cos(th_r)) + Vector((0.0, 0.0, L_bar * math.sin(th_r)))
                    d_sh = float((p_b_try - sh_w).length)
                    dz_sh = float(sh_w.z - p_b_try.z)
                    cost = abs(d_sh - 0.556) * 5.0 + (6.0 if d_sh > 0.576 else 0.0) + (6.5 if dz_sh < 0.530 else 0.0)
                    if cost < best_cost:
                        best_cost = cost
                        best_th = float(th_try)
                theta_deg = best_th if f == int(f0) else (0.52 * theta_deg + 0.48 * best_th)

                bz = float(ground_z) + 0.2464 * math.sin(math.radians(theta_deg)) + 0.004
                bag_pos[f] = Vector((float(bag_xy.x), float(bag_xy.y), bz))
                bag_rot[f] = (-theta_deg, 0.0, bag_yaw)
            elif mode == "stand":
                sp = hmw @ Vector((-0.47, 0.20, 0.0))
                bag_xy = Vector((float(sp.x), float(sp.y)))
                bag_yaw = _unwrap_deg(bag_yaw, hyaw + 38.0)
                theta_deg = 68.0
                bag_pos[f] = Vector((float(sp.x), float(sp.y), float(ground_z) + 0.238))
                bag_rot[f] = (-68.0, 10.0, bag_yaw)
            elif mode == "carry":
                cp = hmw @ Vector((-0.54, 0.12, 0.68))
                bag_xy = Vector((float(cp.x), float(cp.y)))
                bag_yaw = _unwrap_deg(bag_yaw, hyaw + 20.0)
                theta_deg = 78.0
                bag_pos[f] = Vector((float(cp.x), float(cp.y), float(cp.z)))
                bag_rot[f] = (-78.0, -12.0, bag_yaw)
            elif mode == "cabin_carry":
                # High rear-hip carry (`(-0.16, +0.51, 0.74)`): clear of doorway jamb, clear of Shin/Quad back-kick, AND zero IK gap!
                cp = hmw @ Vector((-0.16, 0.51, 0.74))
                bag_xy = Vector((float(cp.x), float(cp.y)))
                bag_yaw = _unwrap_deg(bag_yaw, hyaw + 16.0)
                bag_pos[f] = Vector((float(cp.x), float(cp.y), float(cp.z)))
                bag_rot[f] = (-78.0, -6.0, bag_yaw)

    # Fill transition gaps in HERO-LOCAL POLAR COORDINATES around Hero's right side (`side_radius >= 0.54 m`)!
    for i in range(len(pose_ranges) - 1):
        fa_end = int(pose_ranges[i][1])
        fb_beg = int(pose_ranges[i + 1][0])
        if fb_beg > fa_end + 1 and fa_end in bag_pos and fb_beg in bag_pos:
            hmw0 = hero_samples[fa_end][0]
            hmw1 = hero_samples[fb_beg][0]
            lp0 = hmw0.inverted() @ bag_pos[fa_end]
            lp1 = hmw1.inverted() @ bag_pos[fb_beg]
            r0_p = math.hypot(lp0.x, lp0.y)
            r1_p = math.hypot(lp1.x, lp1.y)
            # Angle phi around Hero's right side: phi=0 is pure right (-X_hero), +phi is rear-right (+Y_hero), -phi is front-right (-Y_hero)
            phi0 = math.atan2(lp0.y, max(0.05, -lp0.x))
            phi1 = math.atan2(lp1.y, max(0.05, -lp1.x))
            rot0, rot1 = bag_rot[fa_end], bag_rot[fb_beg]
            y1_u = _unwrap_deg(rot0[2], rot1[2])
            dy_shift = y1_u - rot1[2]
            if abs(dy_shift) > 1e-3:
                for fk in range(fb_beg, N + 1):
                    if fk in bag_rot:
                        bag_rot[fk] = (bag_rot[fk][0], bag_rot[fk][1], bag_rot[fk][2] + dy_shift)
            span = float(fb_beg - fa_end)
            min_r = 0.49
            is_lift_carry = (pose_ranges[i + 1][2] == "carry")
            for fm in range(fa_end + 1, fb_beg):
                u = (fm - fa_end) / span
                s = u * u * (3.0 - 2.0 * u)
                sz = (1.0 - (1.0 - u) * (1.0 - u)) if is_lift_carry else s
                r_m = max(min_r, r0_p + (r1_p - r0_p) * s)
                phi_m = phi0 + (phi1 - phi0) * s
                z_loc_m = lp0.z + (lp1.z - lp0.z) * sz
                hmw_m = hero_samples[fm][0]
                wp_m = hmw_m @ Vector((-r_m * math.cos(phi_m), r_m * math.sin(phi_m), z_loc_m))
                # Never allow transition to dip wheels below ground_z!
                min_bz = float(ground_z) + 0.205
                bag_pos[fm] = Vector((float(wp_m.x), float(wp_m.y), max(min_bz, float(wp_m.z))))
                bag_rot[fm] = (
                    rot0[0] + (rot1[0] - rot0[0]) * s,
                    rot0[1] + (rot1[1] - rot0[1]) * s,
                    rot0[2] + (y1_u - rot0[2]) * s,
                )

    key_pos(bag_root, [(f, (float(bag_pos[f].x), float(bag_pos[f].y), float(bag_pos[f].z))) for f in sorted(bag_pos)])
    key_rot_deg(bag_root, [(f, bag_rot[f]) for f in sorted(bag_rot)])
    _set_fcurves_linear(bag_root)

    if f_ik_ranges and "Pull_Top" in bag_by_n:
        solve_roller_bar_grip_targets(
            scene,
            hero_root,
            hero_arm,
            bag_root,
            bag_by_n["Pull_Top"],
            label,
            f_ik_ranges,
            hand="R",
            bind_ik=True,
            override_world_fn=override_grip_fn,
            fist_inf_keys=fist_inf_keys,
            ik_inf_keys=ik_inf_keys,
        )
    scene.frame_set(1)
    return bag_root, bag_by_n


def bind_head_look_at(
    scene,
    arm,
    name,
    target_obj=None,
    target_pos=None,
    influence_keys=None,
    max_inf=0.62,
    include_spine=False,
):
    """Turn `Head` (and optionally `Spine_02`) naturally toward a target via `TRACK_TO` (`TRACK_Z`, `UP_Y`),
    preserving `QUATERNION` rotation mode on every bone."""
    if target_obj is None:
        target_obj = bpy.data.objects.new("LookGoal_" + name, None)
        scene.collection.objects.link(target_obj)
        if target_pos is not None:
            if isinstance(target_pos, list):
                key_pos(target_obj, target_pos)
            else:
                target_obj.location = target_pos

    if include_spine == "deep":
        bones = [("Head", 1.0), ("Spine_02", 0.48), ("Spine_01", 0.36)]
    elif include_spine:
        bones = [("Head", 1.0), ("Spine_02", 0.34)]
    else:
        bones = [("Head", 1.0)]
    for bname, mult in bones:
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        if bname == "Head":
            cns = pb.constraints.new("TRACK_TO")
            cns.name = "Look_%s_%s" % (name, bname)
            cns.target = target_obj
            cns.track_axis = "TRACK_Z"
            cns.up_axis = "UP_Y"
        else:
            cns = pb.constraints.new("DAMPED_TRACK")
            cns.name = "Look_%s_%s" % (name, bname)
            cns.target = target_obj
            cns.track_axis = "TRACK_Z"
        if influence_keys:
            for f, v in influence_keys:
                cns.influence = float(v) * mult
                cns.keyframe_insert(data_path="influence", frame=int(f))
        else:
            cns.influence = float(max_inf) * mult
    return target_obj


def bind_spine_stoop(scene, arm, name, deg_x=42.0, influence_keys=None):
    """Flex `Spine_01`, `Spine_02`, and `Spine_03` forward around anatomical local `+X` while preserving `QUATERNION` mode."""
    q_bend = Quaternion((1.0, 0.0, 0.0), math.radians(float(deg_x)))
    for bname in ("Spine_01", "Spine_02", "Spine_03"):
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        emp = bpy.data.objects.new("SpineStoop_%s_%s" % (name, bname), None)
        emp.rotation_mode = "QUATERNION"
        emp.rotation_quaternion = q_bend
        scene.collection.objects.link(emp)
        cns = pb.constraints.new("COPY_ROTATION")
        cns.name = "Stoop_%s_%s" % (name, bname)
        cns.target = emp
        cns.target_space = "WORLD"
        cns.owner_space = "LOCAL"
        cns.mix_mode = "REPLACE"
        if influence_keys:
            for f, v in influence_keys:
                cns.influence = float(v)
                cns.keyframe_insert(data_path="influence", frame=int(f))
            _set_fcurves_linear(arm)
        else:
            cns.influence = 1.0


def parent_prop_to_bone(prop_obj, arm, bone_name, local_loc=(0.0, 0.0, 0.0), local_rot_deg=(0.0, 0.0, 0.0)):
    """Parent a 3D prop (backpack, boarding pass, mop, wand, scanner) directly to an armature bone
    so it moves organically with the character's body and never floats in world space."""
    if bone_name not in arm.data.bones:
        fail("parent_prop_to_bone: bone %r missing on %s" % (bone_name, arm.name))
    prop_obj.parent = arm
    prop_obj.parent_type = "BONE"
    prop_obj.parent_bone = bone_name
    prop_obj.rotation_mode = "XYZ"
    prop_obj.location = local_loc
    prop_obj.rotation_euler = tuple(math.radians(v) for v in local_rot_deg)


def load_roller_bag(label, extended="tow", loc=(0.0, 0.0, 0.0), yaw_deg=0.0, bag_tint=None, parent=None, bag_scale=1.12):
    root, objs, by_n, _ = load_glb("game/assets/interior/carry_roller.glb", label, loc=loc, yaw_deg=yaw_deg)
    root.scale = (bag_scale, bag_scale, bag_scale)
    if bag_tint is not None and "CarryRoller_Body" in by_n:
        mat = toon_rgb_mat("bag_" + label, bag_tint)
        by_n["CarryRoller_Body"].data.materials[0] = mat
        attach_outline(by_n["CarryRoller_Body"], 0.005)
    # Proportion adult T-handle crossbar & telescopic rods on the 36.7cm suitcase (`±0.095` outer span, matte charcoal grip)
    # so an adult Toon People closed fist (`13.4cm` wide) wraps cleanly inside the crossbar with zero rod/cap clipping!
    if "Pull_Top_Mesh" in by_n:
        ptm = by_n["Pull_Top_Mesh"]
        ptm.data = ptm.data.copy()
        ptm.data.materials[0] = toon_rgb_mat("roller_grip_" + label, (0.15, 0.17, 0.22))
        for v in ptm.data.vertices:
            ax = abs(v.co.x)
            sgn = 1.0 if v.co.x >= 0.0 else -1.0
            v.co.x = sgn * (0.075 if ax < 0.05 else 0.095)
            v.co.z *= 0.75
    if "Pull_Reach_Mesh" in by_n:
        prm = by_n["Pull_Reach_Mesh"]
        prm.data = prm.data.copy()
        for v in prm.data.vertices:
            sgn = 1.0 if v.co.x >= 0.0 else -1.0
            v.co.x = sgn * (0.080 if abs(v.co.x) < 0.062 else 0.093)
            v.co.z = 0.03 + (v.co.z - 0.03) * 0.75
    set_roller_handle(by_n, extended=extended)
    if parent is not None:
        root.parent = parent
    return root, objs, by_n


def set_roller_handle(by_n, extended="tow", frame=None):
    reach = by_n.get("Pull_Reach")
    top = by_n.get("Pull_Top")
    if reach is None or top is None:
        return
    if extended == "stand":
        reach.scale = (1.0, 26.2, 1.0)
        top.location = (0.0, -0.74, 0.03)
    elif extended == "tray":
        reach.scale = (1.0, 13.5, 1.0)
        top.location = (0.0, -0.44, 0.03)
    elif extended == "security":
        reach.scale = (1.0, 8.3, 1.0)
        top.location = (0.0, -0.355, 0.062)
    elif extended == "walk_tow":
        reach.scale = (1.0, 31.8, 1.0)
        top.location = (0.0, -0.86, 0.03)
    elif extended:
        reach.scale = (1.0, 31.2, 1.0)
        top.location = (0.0, -0.85, 0.03)
    else:
        reach.scale = (1.0, 1.0, 1.0)
        top.location = (0.0, -0.24, 0.03)
    if frame is not None:
        reach.keyframe_insert(data_path="scale", frame=int(frame))
        top.keyframe_insert(data_path="location", frame=int(frame))


def build_bvh_from_objects(objs, dg=None):
    """Build a world-space `BVHTree` from visible, non-zero-scaled mesh objects."""
    verts = []
    polys = []
    off = 0
    for o in objs:
        if o is None or o.type != "MESH" or o.hide_render:
            continue
        sc = o.matrix_world.to_scale()
        if min(abs(sc.x), abs(sc.y), abs(sc.z)) < 0.02:
            continue
        if dg is not None:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            mw = ev.matrix_world
            for v in me.vertices:
                verts.append(mw @ v.co)
            for p in me.polygons:
                polys.append([off + vi for vi in p.vertices])
            off += len(me.vertices)
            ev.to_mesh_clear()
        else:
            mw = o.matrix_world
            for v in o.data.vertices:
                verts.append(mw @ v.co)
            for p in o.data.polygons:
                polys.append([off + vi for vi in p.vertices])
            off += len(o.data.vertices)
    if not polys:
        return None
    return BVHTree.FromPolygons(verts, polys)


def mesh_world_aabb(objs, dg=None):
    xs, ys, zs = [], [], []
    for o in objs:
        if o is None or o.type != "MESH" or o.hide_render:
            continue
        sc = o.matrix_world.to_scale()
        if min(abs(sc.x), abs(sc.y), abs(sc.z)) < 0.02:
            continue
        if dg is not None:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            mw = ev.matrix_world
            for v in me.vertices:
                wp = mw @ v.co
                xs.append(float(wp.x))
                ys.append(float(wp.y))
                zs.append(float(wp.z))
            ev.to_mesh_clear()
        else:
            mw = o.matrix_world
            for v in o.data.vertices:
                wp = mw @ v.co
                xs.append(float(wp.x))
                ys.append(float(wp.y))
                zs.append(float(wp.z))
    if not xs:
        return None
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def verify_human_motion(
    scene,
    shot_id,
    n_frames,
    obstacle_roots=None,
    extra_boxes_xy=None,
    seated_exempt=None,
    exempt_ranges=None,
    pulled_rollers=None,
    roller_grip_checks=None,
    forbid_char_boxes=None,
    stair_foot_checks=None,
    seated_mounts=None,
    door_checks=None,
    prop_checks=None,
    aircraft_checks=None,
    shot_continuity_checks=None,
    events=None,
    g0=0,
    min_clearance=0.45,
):
    """Automated per-frame physical, BVH & animation audit across frames 1..n_frames:
    1. Every PoseBone on every character armature MUST keep `rotation_mode == 'QUATERNION'`.
    2. Every character root (`CHAR_*`) MUST stay at `scale == (1, 1, 1)`.
    3. Every walking/running character MUST use `use_animated_time` (`strip_time` driven by distance `s(f)`),
       have 0 skating in `idle`, 0 moonwalking (`forward . velocity > 0`), and 0 Euler wrap spins (`|dyaw| <= 24 deg`).
    4. Every human MUST maintain `>= min_clearance` (0.45 m) XY clearance from obstacles & other humans.
    5. Every active arm IK constraint (`influence >= 0.85`) MUST have an explicit `pole_target` (`F-22`)
       and place `Forearm.tail` within `<= 0.08 m` of its target.
    6. FULL-RANGE (`1..n_frames`) BVH zero-overlap check (`F-01`): `[CarryRoller_Body, Pull_Reach_Mesh]`
       vs EVERY character body mesh MUST have `overlap_count == 0` on EVERY frame (not just `tow_ranges`!).
    7. Non-tautological roller palm & finger-curl checks (`F-02`): `|dot(Hand.x, bag_x)| >= 0.90`,
       `dot(Hand.z, to_bar) >= 0.70`, `Fingertips.tail` wrapped opposite `Fingers.head` around `p_bar`,
       and zero dorsal hand penetration.
    8. Door closed-seal, open-pocket, wall-clearance, taxi-door upright, and aircraft-door BVH checks (`F-03..F-06`).
    9. Boarding pass pinch & wrist zero-overlap (`F-07`), mop floor-plane & two-hand shaft alignment (`F-08`),
       backpack zero-overlap (`F-08`), staff prop shaft alignment (`F-08`), two-hand suitcase zero-overlap &
       zero unheld bag motion (`F-10`), tray/belt/pickup BVH zero-overlap (`F-12`), stanchion chain collar fit (`F-21`),
       seated mount `Hips` center & zero chair/armrest/table overlap (`F-13`), aircraft livery, ground wheel Z,
       monotonic takeoff roll acceleration, stowed outer hatch visibility & belly contour, wingtip vapor lock (`F-09..F-19`),
       workstation pop-before-staff order (`F-20`), cabin occlusion before `hide_render` (`F-16`), and foley sync (`F-28`).
    """
    seated_exempt = set(seated_exempt or [])
    exempt_ranges = dict(exempt_ranges or {})
    char_roots = sorted([o for o in scene.objects if o.name.startswith("CHAR_")], key=lambda o: o.name)
    char_arms = {}
    char_body_meshes = {}
    for cr in char_roots:
        arm = next((c for c in cr.children if c.type == "ARMATURE"), None)
        if arm is None:
            fail("%s: character %s missing armature" % (shot_id, cr.name))
        char_arms[cr.name] = arm
        char_body_meshes[cr.name] = [
            o for o in cr.children_recursive if o.type == "MESH" and ("body" in o.name.lower() or "char" in o.name.lower())
        ]
        for pb in arm.pose.bones:
            if pb.rotation_mode != "QUATERNION":
                fail("%s: %s bone %s rotation_mode=%s (MUST be QUATERNION!)" % (shot_id, cr.name, pb.name, pb.rotation_mode))
            for cns in pb.constraints:
                if cns.type == "IK" and pb.name.startswith("Forearm.") and cns.pole_target is None:
                    fail("%s: %s %s IK %s missing pole_target (F-22)!" % (shot_id, cr.name, pb.name, cns.name))

    # Static aircraft livery check (`F-14`): interior parts must NEVER use TOON_GottaAirPlane!
    for o in scene.objects:
        if o.type == "MESH" and o.name.startswith("TP_Plane_") and not is_exterior_airframe_mesh(o.name):
            for sl in o.material_slots:
                if sl.material and "GottaAirPlane" in sl.material.name:
                    fail("%s: interior/gear aircraft mesh %s has exterior livery %s (F-14)!" % (shot_id, o.name, sl.material.name))

    # Collect 2D XY obstacle AABBs at settled frame `n_frames`
    scene.frame_set(n_frames)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    obs_boxes = []
    for eb in (extra_boxes_xy or []):
        if len(eb) == 5:
            obs_boxes.append((eb[0], eb[1], eb[2], eb[3], eb[4], float(min_clearance)))
        else:
            obs_boxes.append((eb[0], eb[1], eb[2], eb[3], eb[4], float(eb[5])))

    if obstacle_roots:
        for item in obstacle_roots:
            req_clear = float(min_clearance)
            if isinstance(item, tuple):
                tag, root_ob = item[0], item[1]
                if len(item) >= 3:
                    req_clear = float(item[2])
            else:
                tag, root_ob = item.name, item
            if root_ob is None:
                continue
            meshes = [root_ob] if root_ob.type == "MESH" else []
            for o in scene.objects:
                if o.type == "MESH" and not o.hide_render:
                    p = o.parent
                    while p is not None:
                        if p == root_ob:
                            meshes.append(o)
                            break
                        p = p.parent
            xs, ys = [], []
            for mo in meshes:
                ev = mo.evaluated_get(dg)
                me = ev.to_mesh()
                mw = ev.matrix_world
                for v in me.vertices:
                    wp = mw @ v.co
                    if 0.16 <= wp.z <= 1.85:
                        xs.append(float(wp.x))
                        ys.append(float(wp.y))
                ev.to_mesh_clear()
            if xs and ys:
                obs_boxes.append((tag, min(xs), max(xs), min(ys), max(ys), req_clear))

    # Seated mounts check (`F-13`) on settled frame!
    if seated_mounts:
        scene.frame_set(min(n_frames, 50))
        bpy.context.view_layer.update()
        dg_sm = bpy.context.evaluated_depsgraph_get()
        for cr_sm, seat_root_sm, expected_hips_xy in seated_mounts:
            arm_sm = char_arms[cr_sm.name]
            hips_w = arm_sm.matrix_world @ arm_sm.pose.bones["Hips"].head
            d_hips = math.hypot(float(hips_w.x) - float(expected_hips_xy[0]), float(hips_w.y) - float(expected_hips_xy[1]))
            if d_hips > 0.085:
                fail(
                    "%s: seated %s Hips (%.3f,%.3f) off seat-pan center (%.3f,%.3f) by %.3fm > 0.085m (F-13)!"
                    % (shot_id, cr_sm.name, hips_w.x, hips_w.y, expected_hips_xy[0], expected_hips_xy[1], d_hips)
                )
            seat_meshes = [o for o in seat_root_sm.children_recursive if o.type == "MESH"]
            bvh_char_s = build_bvh_from_objects(char_body_meshes[cr_sm.name], dg_sm)
            bvh_seat_s = build_bvh_from_objects(seat_meshes, dg_sm)
            if bvh_char_s and bvh_seat_s:
                ov_sm = bvh_char_s.overlap(bvh_seat_s)
                if ov_sm:
                    fail("%s: seated %s intersects %s (%d tris, F-13)!" % (shot_id, cr_sm.name, seat_root_sm.name, len(ov_sm)))

    # Discover all roller bags in scene for full-range `1..n_frames` BVH zero-overlap check (`F-01`)
    roller_roots = [o for o in scene.objects if "Roller" in o.name and o.type == "EMPTY" and o.name.startswith("ROOT_")]
    roller_non_top_meshes = {
        rr.name: [m for m in rr.children_recursive if m.type == "MESH" and "Pull_Top" not in m.name]
        for rr in roller_roots
    }

    # Discover all sliding door units built by `make_sliding_glass_door_unit` (`F-03`, `F-06`)
    sliding_doors = [o for o in scene.objects if "sliding_door_total_width" in o]

    min_obs_d = 999.0
    min_table_d = 999.0
    min_char_d = 999.0
    max_yaw_step = 0.0
    max_ik_err = 0.0
    max_roller_hollow_err = 0.0
    min_roller_wrist_clear = 999.0
    max_roller_kink_deg = 0.0
    min_bar_knuckle_dot = 1.0
    min_bar_palm_dot = 1.0
    roller_rod_slot_hits = 0
    bag_body_overlap_total = 0
    min_stair_margin = 999.0
    stair_gaps = []
    prev_xy = {}
    prev_yaw = {}
    bg_ped_in_frustum = False
    jet_roll_positions = {}
    closed_door_checks_passed = 0
    max_closed_door_seam_err = 0.0
    road_max_edge_len_m = None
    road_max_edge_stretch_ratio = None
    cabin_floor_x_max_m = None
    cabin_floor_protrusion_m = None
    min_elbow_drop_by_hand = {}

    hand_r_vmap = {}
    if roller_grip_checks:
        r_vgs = {"Hand.R", "Fingers.R", "Fingertips.R", "Thumb.R", "Thumb_Tip.R"}
        for cr_g, _, _, _, _ in roller_grip_checks:
            if cr_g.name not in hand_r_vmap:
                entries = []
                for mo in cr_g.children_recursive:
                    if mo.type == "MESH" and ("body" in mo.name.lower() or "char" in mo.name.lower()):
                        vg_names = {vg.index: vg.name for vg in mo.vertex_groups}
                        v_idxs = [
                            v.index
                            for v in mo.data.vertices
                            if any(vg_names.get(g.group) in r_vgs and g.weight > 0.25 for g in v.groups)
                        ]
                        if v_idxs:
                            entries.append((mo, v_idxs))
                hand_r_vmap[cr_g.name] = entries

    for f in range(1, n_frames + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        dg_f = bpy.context.evaluated_depsgraph_get()
        cur_positions = []

        # Full-range `1..n_frames` BVH overlap check between every roller bag+rods and every character (`F-01`)!
        for rr in roller_roots:
            rm_list = [m for m in roller_non_top_meshes[rr.name] if not m.hide_render]
            if not rm_list:
                continue
            bvh_bag = build_bvh_from_objects(rm_list, dg_f)
            if bvh_bag is None:
                continue
            for cr in char_roots:
                cm_list = [m for m in char_body_meshes[cr.name] if not m.hide_render]
                if not cm_list:
                    continue
                bvh_ch = build_bvh_from_objects(cm_list, dg_f)
                if bvh_ch is not None:
                    ov_bh = bvh_bag.overlap(bvh_ch)
                    if ov_bh:
                        bag_body_overlap_total += len(ov_bh)
                        fail(
                            "%s f=%d (global %d): %s [CarryRoller_Body/Pull_Reach] intersects %s (%d overlapping tris, F-01)!"
                            % (shot_id, f, g0 + f, rr.name, cr.name, len(ov_bh))
                        )

        # Sliding door closed-seal & open-pocket bounds check (`F-03`, `F-06`)
        for sd_root in sliding_doors:
            half_tot_sd = 0.5 * float(sd_root["sliding_door_total_width"]) + 0.02
            closed_fs = set(sd_root.get("sliding_door_closed_frames", []))
            sd_inv = sd_root.matrix_world.inverted()
            ll_ob = next((c for c in sd_root.children if c.name.endswith("_Leaf_L")), None)
            lr_ob = next((c for c in sd_root.children if c.name.endswith("_Leaf_R")), None)
            if ll_ob and lr_ob:
                ll_xs, lr_xs = [], []
                for sub_l, dst_x in ((ll_ob, ll_xs), (lr_ob, lr_xs)):
                    for mo_d in sub_l.children_recursive:
                        if mo_d.type == "MESH" and not mo_d.hide_render:
                            mw_d = mo_d.matrix_world
                            for vd in mo_d.data.vertices:
                                lp_d = sd_inv @ (mw_d @ vd.co)
                                dst_x.append(float(lp_d.x))
                for c_all in sd_root.children:
                    if "Leaf_" in c_all.name:
                        for mo_d in c_all.children_recursive:
                            if mo_d.type == "MESH" and not mo_d.hide_render:
                                mw_d = mo_d.matrix_world
                                for vd in mo_d.data.vertices:
                                    lp_d = sd_inv @ (mw_d @ vd.co)
                                    if abs(float(lp_d.x)) > half_tot_sd:
                                        fail(
                                            "%s f=%d: %s leaf %s protruded outside frame pocket (x_local=%.3f > %.3f, F-06)!"
                                            % (shot_id, f, sd_root.name, mo_d.name, lp_d.x, half_tot_sd)
                                        )
                is_closed_f = (f in closed_fs) or (
                    abs(float(ll_ob.location.x)) <= 1e-4 and abs(float(lr_ob.location.x)) <= 1e-4
                )
                if is_closed_f and ll_xs and lr_xs:
                    seam_err = abs(max(ll_xs) - min(lr_xs))
                    closed_door_checks_passed += 1
                    max_closed_door_seam_err = max(max_closed_door_seam_err, seam_err)
                    if seam_err > 0.025:
                        fail(
                            "%s f=%d: closed door %s center seam gap/overlap %.4fm > 0.025m (Leaf_L.max=%.4f, Leaf_R.min=%.4f, F-06)!"
                            % (shot_id, f, sd_root.name, max(ll_xs) - min(lr_xs), max(ll_xs), min(lr_xs))
                        )

        # Shot-specific door & prop & aircraft per-frame checks
        if door_checks:
            for dcheck in door_checks:
                dkind = dcheck["kind"]
                if dkind == "taxi_door_upright":
                    td = dcheck["door"]
                    rest_zmax = float(dcheck["rest_z_max"])
                    ta = mesh_world_aabb([td], dg_f)
                    if ta and abs(ta[5] - rest_zmax) > 0.035:
                        fail("%s f=%d: taxi door %s flipped/pitched (z_max=%.3f vs rest=%.3f, F-04)!" % (shot_id, f, td.name, ta[5], rest_zmax))
                elif dkind == "bvh_zero_overlap":
                    f0_d, f1_d = dcheck.get("frames", (1, n_frames))
                    if f0_d <= f <= f1_d:
                        b1 = build_bvh_from_objects(dcheck["objs_a"], dg_f)
                        b2 = dcheck.get("static_bvh_b") or build_bvh_from_objects(dcheck["objs_b"], dg_f)
                        if b1 and b2:
                            ov_d = b1.overlap(b2)
                            if ov_d:
                                fail("%s f=%d: door/prop BVH overlap %s (%d tris)!" % (shot_id, f, dcheck["label"], len(ov_d)))

        if prop_checks:
            for pcheck in prop_checks:
                pkind = pcheck["kind"]
                f0_p, f1_p = pcheck.get("frames", (1, n_frames))
                if not (f0_p <= f <= f1_p):
                    continue
                if pkind == "mop_floor_and_hands":
                    mh = pcheck["mop_head"]
                    ms = pcheck["mop_stick"]
                    ma = mesh_world_aabb([mh], dg_f)
                    if not ma or not (0.0 <= ma[4] <= 0.030):
                        fail("%s f=%d: CleanerMop head left floor plane (z_min=%s outside [0..0.03]m, F-08)!" % (shot_id, f, ma[4] if ma else None))
                    arm_m = pcheck["arm"]
                    s_up = (ms.matrix_world.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
                    for s_h in ("R", "L"):
                        hx = (arm_m.matrix_world.to_3x3() @ arm_m.pose.bones["Hand." + s_h].x_axis).normalized()
                        ang_m = math.degrees(math.acos(max(0.0, min(1.0, abs(hx.dot(s_up))))))
                        if ang_m > 15.0:
                            fail("%s f=%d: CleanerMop Hand.%s x_axis misaligned %.1fdeg > 15deg from stick (F-08)!" % (shot_id, f, s_h, ang_m))
                elif pkind == "staff_prop_palm":
                    arm_sp = pcheck["arm"]
                    hand_sp = pcheck["hand"]
                    prop_sp = pcheck["prop"]
                    shaft_local = Vector(pcheck.get("shaft_axis", (0.0, 1.0, 0.0)))
                    p_ax = (prop_sp.matrix_world.to_3x3() @ shaft_local).normalized()
                    hx = (arm_sp.matrix_world.to_3x3() @ arm_sp.pose.bones["Hand." + hand_sp].x_axis).normalized()
                    ang_sp = math.degrees(math.acos(max(0.0, min(1.0, abs(hx.dot(p_ax))))))
                    if ang_sp > 15.0:
                        fail("%s f=%d: %s shaft misaligned %.1fdeg > 15deg from Hand.%s.x_axis (F-08)!" % (shot_id, f, prop_sp.name, ang_sp, hand_sp))
                elif pkind == "boarding_pass_pinch":
                    card_root = pcheck["card"]
                    card_meshes = [m for m in card_root.children_recursive if m.type == "MESH" and not m.hide_render]
                    ca = mesh_world_aabb(card_meshes, dg_f)
                    if ca is not None:
                        bvh_card = build_bvh_from_objects(card_meshes, dg_f)
                        holders = pcheck["holders"]
                        min_pinch_d = 999.0
                        for h_cr, h_arm, h_side in holders:
                            pb_th = h_arm.pose.bones["Thumb_Tip." + h_side]
                            pb_fg = h_arm.pose.bones["Fingers." + h_side]
                            pinch_pt = 0.5 * ((h_arm.matrix_world @ pb_th.tail) + (h_arm.matrix_world @ pb_fg.tail))
                            # Closest vertex on card mesh to pinch_pt
                            for cm_o in card_meshes:
                                mw_c = cm_o.matrix_world
                                for vc in cm_o.data.vertices:
                                    min_pinch_d = min(min_pinch_d, float(((mw_c @ vc.co) - pinch_pt).length))
                            # Check zero wrist/forearm overlap (`Forearm` vertex group!)
                            for bmo in char_body_meshes[h_cr.name]:
                                ev_bm = bmo.evaluated_get(dg_f)
                                me_bm = ev_bm.to_mesh()
                                mw_bm = ev_bm.matrix_world
                                vgs_b = {vg.index: vg.name for vg in bmo.vertex_groups}
                                fa_vset = {
                                    v.index for v in bmo.data.vertices
                                    if any(vgs_b.get(g.group) == ("Forearm." + h_side) and g.weight > 0.35 for g in v.groups)
                                }
                                fa_polys = [list(p.vertices) for p in me_bm.polygons if all(vi in fa_vset for vi in p.vertices)]
                                if fa_polys and bvh_card:
                                    bvh_fa = BVHTree.FromPolygons([mw_bm @ v.co for v in me_bm.vertices], fa_polys)
                                    if bvh_card.overlap(bvh_fa):
                                        ev_bm.to_mesh_clear()
                                        fail("%s f=%d: %s impales %s Forearm.%s (F-07)!" % (shot_id, f, card_root.name, h_cr.name, h_side))
                                ev_bm.to_mesh_clear()
                        if min_pinch_d > 0.038:
                            fail("%s f=%d: %s unheld/floating (min_pinch_dist=%.3fm > 0.038m, F-07)!" % (shot_id, f, card_root.name, min_pinch_d))
                elif pkind == "unheld_bag_stationary":
                    bag_r_u = pcheck["bag_root"]
                    arm_u = pcheck["arm"]
                    conv_f0, conv_f1 = pcheck["conveyor_frames"]
                    if not (conv_f0 <= f <= conv_f1) and f > 1:
                        cur_bp = bag_r_u.matrix_world.translation.copy()
                        scene.frame_set(f - 1)
                        bpy.context.view_layer.update()
                        prev_bp = bag_r_u.matrix_world.translation.copy()
                        scene.frame_set(f)
                        bpy.context.view_layer.update()
                        dg_f = bpy.context.evaluated_depsgraph_get()
                        bv_step = float((cur_bp - prev_bp).length)
                        if bv_step > 0.004:
                            # Bag moved outside conveyor -> at least one hand must be within <= 0.04m of bag/grip surface!
                            bag_u_meshes = [bm_u for bm_u in bag_r_u.children_recursive if bm_u.type == "MESH" and not bm_u.hide_render]
                            bvh_u = build_bvh_from_objects(bag_u_meshes, dg_f)
                            p_r = arm_u.matrix_world @ arm_u.pose.bones["Fingers.R"].tail
                            p_l = arm_u.matrix_world @ arm_u.pose.bones["Fingers.L"].tail
                            dr = float(bvh_u.find_nearest(p_r)[3]) if bvh_u is not None else 9.9
                            dl = float(bvh_u.find_nearest(p_l)[3]) if bvh_u is not None else 9.9
                            if min(dr, dl) > 0.040:
                                fail(
                                    "%s f=%d: unheld bag %s moved %.4fm while hands were (%.3fm, %.3fm) away (F-10)!"
                                    % (shot_id, f, bag_r_u.name, bv_step, dr, dl)
                                )
                elif pkind == "mesh_max_edge_stretch":
                    m_ob = pcheck["mesh_obj"]
                    if m_ob is not None and m_ob.type == "MESH":
                        orig_max_e = float(pcheck["orig_max_edge_len"])
                        orig_lens = pcheck.get("orig_edge_lens") or []
                        max_ratio = float(pcheck.get("max_ratio", 1.5))
                        mw_e = m_ob.matrix_world
                        verts_e = m_ob.data.vertices
                        cur_lens = [
                            float(((mw_e @ verts_e[ed.vertices[0]].co) - (mw_e @ verts_e[ed.vertices[1]].co)).length)
                            for ed in m_ob.data.edges
                        ]
                        cur_max_e = max(cur_lens) if cur_lens else 0.0
                        stretch_r = (
                            max(cl / max(1e-6, ol) for cl, ol in zip(cur_lens, orig_lens))
                            if (orig_lens and len(cur_lens) == len(orig_lens))
                            else (cur_max_e / max(1e-6, orig_max_e))
                        )
                        road_max_edge_len_m = round(cur_max_e, 4)
                        road_max_edge_stretch_ratio = round(stretch_r, 4)
                        if cur_max_e > max_ratio * orig_max_e or stretch_r > max_ratio:
                            fail(
                                "%s f=%d: %s stretched mesh edge detected (max_edge=%.3fm vs orig=%.3fm, stretch_ratio=%.3fx > %.2fx)!"
                                % (shot_id, f, pcheck.get("label", m_ob.name), cur_max_e, orig_max_e, stretch_r, max_ratio)
                            )

        if aircraft_checks:
            for acheck in aircraft_checks:
                akind = acheck["kind"]
                f0_a, f1_a = acheck.get("frames", (1, n_frames))
                if not (f0_a <= f <= f1_a):
                    continue
                if akind == "ground_roll_wheels":
                    wa = mesh_world_aabb(acheck["wheels"], dg_f)
                    if wa and wa[4] < -0.015:
                        fail("%s f=%d: aircraft wheels sank below runway (z_min=%.4fm < -0.015m, F-09)!" % (shot_id, f, wa[4]))
                    jet_roll_positions[f] = acheck["plane_root"].matrix_world.translation.copy()
                elif akind == "stowed_belly_clean":
                    pr_a = acheck["plane_root"]
                    pinv_a = pr_a.matrix_world.inverted()
                    for eh in acheck["ext_hatches"]:
                        if eh.hide_render:
                            fail("%s f=%d: outer gear bay door %s is hidden in stowed flight (F-09)!" % (shot_id, f, eh.name))
                    for gh in acheck["all_gear_and_hatches"]:
                        if gh.hide_render:
                            continue
                        mw_gh = gh.matrix_world
                        for vg_h in gh.data.vertices:
                            lp_h = pinv_a @ (mw_gh @ vg_h.co)
                            # Local belly contour: nose [-12..-9.5] z>=1.36, main [0.5..3.8] z>=0.65 + 0.12*max(0, |x|-1.2)
                            belly_floor = 1.36 if lp_h.y < -8.0 else (0.65 + 0.12 * max(0.0, abs(lp_h.x) - 1.2))
                            if float(lp_h.z) < belly_floor - 0.025:
                                fail(
                                    "%s f=%d: retracted gear/hatch %s vertex protruded below belly contour (z_loc=%.3f < %.3f, F-09)!"
                                    % (shot_id, f, gh.name, lp_h.z, belly_floor)
                                )
                elif akind == "wingtip_vapor_lock":
                    fus_v = acheck["fuselage"]
                    for v_idx, rib_ob in acheck["tips_and_ribbons"]:
                        w_tip = fus_v.matrix_world @ fus_v.data.vertices[v_idx].co
                        ev_rib = rib_ob.evaluated_get(dg_f)
                        me_rib = ev_rib.to_mesh()
                        head_mid = 0.5 * ((rib_ob.matrix_world @ me_rib.vertices[0].co) + (rib_ob.matrix_world @ me_rib.vertices[1].co))
                        ev_rib.to_mesh_clear()
                        d_tip = float((head_mid - w_tip).length)
                        if d_tip > 0.080:
                            fail("%s f=%d: %s head drifted %.3fm > 0.080m from winglet tip (F-19)!" % (shot_id, f, rib_ob.name, d_tip))
                elif akind == "cabin_floor_containment":
                    pr_cf = acheck["plane_root"]
                    fus_cf = acheck["fuselage"]
                    cf_ob = acheck["cabin_floor"]
                    max_lim_x = float(acheck.get("max_local_x", 0.76))
                    pinv_cf = pr_cf.matrix_world.inverted()
                    ev_cf = cf_ob.evaluated_get(dg_f)
                    me_cf = ev_cf.to_mesh()
                    mw_cf = ev_cf.matrix_world
                    cf_lpts = [pinv_cf @ (mw_cf @ v.co) for v in me_cf.vertices]
                    ev_cf.to_mesh_clear()
                    cf_xmax = max(float(p.x) for p in cf_lpts)
                    cf_xmin = min(float(p.x) for p in cf_lpts)
                    cf_ymin = min(float(p.y) for p in cf_lpts)
                    cf_ymax = max(float(p.y) for p in cf_lpts)
                    cf_zmin = min(float(p.z) for p in cf_lpts)
                    cf_zmax = max(float(p.z) for p in cf_lpts)
                    fmw_cf = fus_cf.matrix_world
                    fus_band_pts = [
                        pinv_cf @ (fmw_cf @ fv.co)
                        for fv in fus_cf.data.vertices
                        if (cf_ymin - 0.15) <= float((pinv_cf @ (fmw_cf @ fv.co)).y) <= (cf_ymax + 0.15)
                        and (cf_zmin - 0.04) <= float((pinv_cf @ (fmw_cf @ fv.co)).z) <= (cf_zmax + 0.04)
                    ]
                    hull_outer_x = max((abs(float(p.x)) for p in fus_band_pts), default=max_lim_x)
                    # Conservative narrowest outer hull half-width at the bottom face of the floor slab (`z <= cf_zmin + 0.01`):
                    low_pts = [abs(float(p.x)) for p in fus_band_pts if float(p.z) <= cf_zmin + 0.015]
                    if low_pts:
                        hull_outer_x = min(hull_outer_x, max(low_pts))
                    protrusion_m = max(0.0, max(abs(cf_xmax), abs(cf_xmin)) - (hull_outer_x - 0.02))
                    cabin_floor_x_max_m = round(cf_xmax, 4)
                    cabin_floor_protrusion_m = round(protrusion_m, 4)
                    if cf_xmax > max_lim_x or abs(cf_xmin) > max_lim_x or protrusion_m > 0.0:
                        fail(
                            "%s f=%d: %s protrudes past fuselage hull (local_x=[%.3f, %.3f], limit=%.3f, hull_x=%.3f, protrusion=%.3fm)!"
                            % (shot_id, f, cf_ob.name, cf_xmin, cf_xmax, max_lim_x, hull_outer_x, protrusion_m)
                        )

        for cr in char_roots:
            cname = cr.name
            sc = cr.matrix_world.to_scale()
            if max(abs(sc.x - 1.0), abs(sc.y - 1.0), abs(sc.z - 1.0)) > 0.01:
                fail("%s f=%d: %s scale=(%.4f,%.4f,%.4f) != 1.0 (humans must NEVER pop/balloon!)" % (shot_id, f, cname, sc.x, sc.y, sc.z))

            mw = cr.matrix_world
            cx, cy, cz = float(mw.translation.x), float(mw.translation.y), float(mw.translation.z)
            fwd_3d = (mw.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
            yaw_deg = math.degrees(math.atan2(fwd_3d.x, -fwd_3d.y))
            in_ex_range = any(r0 <= f <= r1 for r0, r1 in exempt_ranges.get(cname, ()))
            is_exempt = cname in seated_exempt or (cr.parent is not None) or in_ex_range

            if cname != "CHAR_Hero" and scene.camera is not None and not any(m.hide_render for m in char_body_meshes[cname]):
                ndc_bg = world_to_camera_view(scene, scene.camera, Vector((cx, cy, cz + 1.0)))
                if 0.08 <= ndc_bg.x <= 0.92 and 0.08 <= ndc_bg.y <= 0.92 and ndc_bg.z > 0.5:
                    bg_ped_in_frustum = True

            arm = char_arms[cname]
            if not any(mo.hide_render for mo in cr.children_recursive if mo.type == "MESH"):
                for b_ik_name in ("Forearm.L", "Forearm.R"):
                    pb_ik = arm.pose.bones.get(b_ik_name)
                    if pb_ik is None:
                        continue
                    for cns in pb_ik.constraints:
                        if cns.type == "IK" and cns.target is not None and float(cns.influence) >= 0.85:
                            hand_tip = arm.matrix_world @ pb_ik.tail
                            grip_pos = cns.target.matrix_world.translation
                            ik_err = float((hand_tip - grip_pos).length)
                            max_ik_err = max(max_ik_err, ik_err)
                            if ik_err > 0.080:
                                fail(
                                    "%s f=%d: %s %s IK %s fell short of target %s (dist=%.3fm > 0.080m, inf=%.2f!)"
                                    % (shot_id, f, cname, b_ik_name, cns.name, cns.target.name, ik_err, cns.influence)
                                )

            if cname in prev_xy and not is_exempt:
                dx = cx - prev_xy[cname][0]
                dy = cy - prev_xy[cname][1]
                ds = math.hypot(dx, dy)
                v_mps = ds * FPS
                dyaw = abs(((yaw_deg - prev_yaw[cname] + 180.0) % 360.0) - 180.0)
                max_yaw_step = max(max_yaw_step, dyaw)
                if dyaw > 25.0:
                    fail("%s f=%d: %s spun %.1f deg in 1 frame (pirouette defect!)" % (shot_id, f, cname, dyaw))
                if v_mps > 0.40:
                    dot_fwd = (dx * fwd_3d.x + dy * fwd_3d.y) / ds
                    if dot_fwd < 0.35:
                        fail("%s f=%d: %s moving at %.2fm/s while facing away (dot=%.2f, moonwalk!)" % (shot_id, f, cname, v_mps, dot_fwd))

                ad = arm.animation_data
                strips = [s for trk in (ad.nla_tracks if ad else []) for s in trk.strips]
                if v_mps > 0.25:
                    active_loco = [s for s in strips if ("walk" in s.name or "run" in s.name) and s.influence > 0.08]
                    if not active_loco:
                        fail("%s f=%d: %s skating at %.2fm/s with 0 walk/run influence!" % (shot_id, f, cname, v_mps))
                    if not all(s.use_animated_time for s in active_loco):
                        fail("%s f=%d: %s walk/run strip not using distance-driven strip_time!" % (shot_id, f, cname))

            prev_xy[cname] = (cx, cy)
            prev_yaw[cname] = yaw_deg

            if not is_exempt and cz < 0.45:
                cur_positions.append((cname, cx, cy))
                for otag, x0, x1, y0, y1, req_c in obs_boxes:
                    qx = max(x0, min(cx, x1))
                    qy = max(y0, min(cy, y1))
                    dist = math.hypot(cx - qx, cy - qy)
                    if req_c >= min_clearance - 1e-4:
                        min_obs_d = min(min_obs_d, dist)
                    else:
                        min_table_d = min(min_table_d, dist)
                    if dist < req_c:
                        fail(
                            "%s f=%d: %s at (%.2f,%.2f) collided with %s [%.2f..%.2f, %.2f..%.2f] (clearance=%.3fm < %.2fm)"
                            % (shot_id, f, cname, cx, cy, otag, x0, x1, y0, y1, dist, req_c)
                        )

        for i in range(len(cur_positions)):
            for j in range(i + 1, len(cur_positions)):
                n1, x1, y1 = cur_positions[i]
                n2, x2, y2 = cur_positions[j]
                cd = math.hypot(x1 - x2, y1 - y2)
                min_char_d = min(min_char_d, cd)
                if cd < 0.60:
                    fail("%s f=%d: %s and %s collided (dist=%.3fm < 0.60m)" % (shot_id, f, n1, n2, cd))

        # 5. Forbidden character vertex zones (e.g. Shot 1 f<=20 no human vertex above closed taxi roof!)
        if forbid_char_boxes:
            for ftag, f0_b, f1_b, bx0, bx1, by0, by1, bz0, bz1 in forbid_char_boxes:
                if f0_b <= f <= f1_b:
                    for cr in char_roots:
                        for mo in cr.children_recursive:
                            if mo.type == "MESH" and not mo.hide_render:
                                ev_m = mo.evaluated_get(dg_f).to_mesh()
                                mw_m = mo.matrix_world
                                for v in ev_m.vertices:
                                    wp = mw_m @ v.co
                                    if bx0 <= wp.x <= bx1 and by0 <= wp.y <= by1 and bz0 <= wp.z <= bz1:
                                        mo.evaluated_get(dg_f).to_mesh_clear()
                                        fail("%s f=%d: %s vertex (%.2f,%.2f,%.2f) entered forbidden box %s!" % (shot_id, f, cr.name, wp.x, wp.y, wp.z, ftag))
                                mo.evaluated_get(dg_f).to_mesh_clear()

        # 6. Grounded pulled-roller suitcase & relaxed-elbow kinematics check!
        if pulled_rollers:
            for hero_r, hero_a, bag_body_ob, ground_z, tow_ranges in pulled_rollers:
                if any(r0 <= f <= r1 for r0, r1 in tow_ranges):
                    mw_b = bag_body_ob.matrix_world
                    pts_b = [mw_b @ v.co for v in bag_body_ob.data.vertices]
                    wheel_h = min(p.z for p in pts_b) - float(ground_z)
                    if not (-0.012 <= wheel_h <= 0.030):
                        fail("%s f=%d: pulled roller %s floating/sinking (wheel_h=%.3fm outside [-0.012..0.030]m!)" % (shot_id, f, bag_body_ob.name, wheel_h))
                    hx, hy = float(hero_r.matrix_world.translation.x), float(hero_r.matrix_world.translation.y)
                    min_leg_xy = min(math.hypot(p.x - hx, p.y - hy) for p in pts_b)
                    if min_leg_xy < 0.38:
                        fail("%s f=%d: pulled roller %s too close to Hero legs (xy=%.3fm < 0.38m, shin clip!)" % (shot_id, f, bag_body_ob.name, min_leg_xy))
                    sh_z = float((hero_a.matrix_world @ hero_a.pose.bones["Arm.R"].head).z)
                    el_z = float((hero_a.matrix_world @ hero_a.pose.bones["Forearm.R"].head).z)
                    if (sh_z - el_z) < 0.12:
                        fail("%s f=%d: Hero chicken-wing high elbow (sh_z=%.3f, el_z=%.3f, diff=%.3fm < 0.12m!)" % (shot_id, f, sh_z, el_z, sh_z - el_z))

        # 6b. Non-tautological Roller-Bar Palm-Orientation, `+X` Finger-Curl, Wrist Kink & Rod-Slot Check (`F-02`)!
        if roller_grip_checks:
            for cr_g, arm_g, bag_r_g, pull_top_g, grip_ranges in roller_grip_checks:
                if any(r0 <= f <= r1 for r0, r1 in grip_ranges):
                    if any(mo.hide_render for mo in cr_g.children_recursive if mo.type == "MESH"):
                        continue
                    boff_chk = (0.0, -0.018, 0.004) if float(pull_top_g.location.y) > -0.40 else (0.0, -0.056, 0.014)
                    p_bar = pull_top_g.matrix_world @ Vector(boff_chk)
                    bag_x_w = (bag_r_g.matrix_world.to_3x3() @ Vector((1.0, 0.0, 0.0))).normalized()
                    m3_g = arm_g.matrix_world.to_3x3()
                    hd_g = arm_g.pose.bones["Hand.R"]
                    fa_g = arm_g.pose.bones["Forearm.R"]
                    fg_g = arm_g.pose.bones["Fingers.R"]
                    ft_g = arm_g.pose.bones["Fingertips.R"]
                    p_wrist = arm_g.matrix_world @ hd_g.head
                    yw_g = (m3_g @ hd_g.y_axis).normalized()
                    xw_g = (m3_g @ hd_g.x_axis).normalized()
                    zw_g = (m3_g @ hd_g.z_axis).normalized()
                    fa_yw = (m3_g @ fa_g.y_axis).normalized()

                    knuckle_dot = abs(float(xw_g.dot(bag_x_w)))
                    p_palm_surf = p_wrist + yw_g * 0.096 + zw_g * 0.008
                    to_bar = p_bar - p_palm_surf
                    palm_dot = float(zw_g.dot(to_bar.normalized())) if to_bar.length > 1e-4 else 1.0
                    min_bar_knuckle_dot = min(min_bar_knuckle_dot, knuckle_dot)
                    min_bar_palm_dot = min(min_bar_palm_dot, palm_dot)
                    if knuckle_dot < 0.90:
                        fail(
                            "%s f=%d: %s Hand.R knuckle row misaligned with roller bar (|dot|=%.3f < 0.90, F-02)!"
                            % (shot_id, f, cr_g.name, knuckle_dot)
                        )
                    if palm_dot < 0.70:
                        fail(
                            "%s f=%d: %s Hand.R palm normal not facing roller bar (dot=%.3f < 0.70, F-02)!"
                            % (shot_id, f, cr_g.name, palm_dot)
                        )
                    # Check true `+X` wrap: `Fingers.head` and `Fingertips.tail` must straddle opposite `Hand.z` sides of `p_bar`!
                    z_kn = float((arm_g.matrix_world @ fg_g.head - p_bar).dot(zw_g))
                    z_tip = float((arm_g.matrix_world @ ft_g.tail - p_bar).dot(zw_g))
                    if not (z_kn < -0.008 and z_tip > 0.015):
                        fail(
                            "%s f=%d: %s fingers not wrapped around roller bar (z_kn=%.3f, z_tip=%.3f, sideways curl F-02)!"
                            % (shot_id, f, cr_g.name, z_kn, z_tip)
                        )

                    p_hollow = p_wrist + yw_g * 0.096 + zw_g * 0.034
                    hol_err = float((p_hollow - p_bar).length)
                    wr_clear = float((p_wrist - p_bar).length)
                    kink_d = math.degrees(fa_yw.angle(yw_g))
                    max_roller_hollow_err = max(max_roller_hollow_err, hol_err)
                    min_roller_wrist_clear = min(min_roller_wrist_clear, wr_clear)
                    max_roller_kink_deg = max(max_roller_kink_deg, kink_d)
                    if hol_err > 0.022:
                        fail("%s f=%d: %s palm hollow missed roller bar (err=%.4fm > 0.022m!)" % (shot_id, f, cr_g.name, hol_err))
                    if wr_clear < 0.055:
                        fail("%s f=%d: %s wrist joint impaled on roller bar (dist=%.4fm < 0.055m!)" % (shot_id, f, cr_g.name, wr_clear))
                    if kink_d > 34.0:
                        fail("%s f=%d: %s wrist kink %.1fdeg > 34.0deg on roller bar!" % (shot_id, f, cr_g.name, kink_d))
                    pt_meshes = [c for c in pull_top_g.children if c.type == "MESH" and not c.hide_render]
                    if pt_meshes:
                        bvh_pt = build_bvh_from_objects(pt_meshes, dg_f)
                        if bvh_pt is not None:
                            d_pt = float(bvh_pt.find_nearest(arm_g.matrix_world @ fg_g.tail)[3])
                            if d_pt > 0.028:
                                fail("%s f=%d: %s Hand.R fingers floating %.3fm > 0.028m off Pull_Top_Mesh (F-02)!" % (shot_id, f, cr_g.name, d_pt))
                    top_y_loc = float(pull_top_g.location.y)
                    if top_y_loc < -0.35:
                        bag_inv_g = bag_r_g.matrix_world.inverted()
                        for mo_g, v_idxs in hand_r_vmap.get(cr_g.name, ()):
                            ev_obj_g = mo_g.evaluated_get(dg_f)
                            ev_g = ev_obj_g.to_mesh()
                            mw_g = mo_g.matrix_world
                            hit_bp = None
                            for vi in v_idxs:
                                bp = bag_inv_g @ (mw_g @ ev_g.vertices[vi].co)
                                if (top_y_loc + 0.032) <= bp.y <= -0.220 and abs(bp.x) <= 0.072 and 0.010 <= bp.z <= 0.050:
                                    hit_bp = bp
                                    break
                            ev_obj_g.to_mesh_clear()
                            if hit_bp is not None:
                                roller_rod_slot_hits += 1
                                fail(
                                    "%s f=%d: %s Hand.R/finger vertex intruded into telescopic rod slot (bag_xyz=(%.3f,%.3f,%.3f), top_y=%.3f)!"
                                    % (shot_id, f, cr_g.name, hit_bp.x, hit_bp.y, hit_bp.z, top_y_loc)
                                )

        # 8. Stair-tread & upper-deck per-vertex foot-elevation check!
        if stair_foot_checks:
            for cr_s, fs0, fs1, surf_fn in stair_foot_checks:
                if fs0 <= f <= fs1:
                    worst_margin = 999.0
                    worst_pt = None
                    for mo in cr_s.children_recursive:
                        if mo.type == "MESH" and not mo.hide_render and ("body" in mo.name.lower() or "char" in mo.name.lower()):
                            ev_s = mo.evaluated_get(dg_f).to_mesh()
                            mw_s = mo.matrix_world
                            for v in ev_s.vertices:
                                wp = mw_s @ v.co
                                m_v = float(wp.z) - float(surf_fn(float(wp.x)))
                                if m_v < worst_margin:
                                    worst_margin = m_v
                                    worst_pt = (float(wp.x), float(wp.z), float(surf_fn(float(wp.x))))
                            mo.evaluated_get(dg_f).to_mesh_clear()
                    if worst_pt is not None:
                        min_stair_margin = min(min_stair_margin, worst_margin)
                        stair_gaps.append(worst_margin)
                        if worst_margin < -0.018:
                            fail(
                                "%s f=%d: %s boot vertex sank into stairs/deck at x=%.2f (vz=%.3fm < surf_z=%.3fm - 0.018m!)"
                                % (shot_id, f, cr_s.name, worst_pt[0], worst_pt[1], worst_pt[2])
                            )
                        if worst_margin > 0.095:
                            fail(
                                "%s f=%d: %s boots floating %.3fm in mid-air above stairs/deck at x=%.2f (vz=%.3fm vs surf_z=%.3fm!)"
                                % (shot_id, f, cr_s.name, worst_margin, worst_pt[0], worst_pt[1], worst_pt[2])
                            )

    if stair_gaps:
        stance_grounded = sum(1 for g in stair_gaps if g <= 0.042) / float(len(stair_gaps))
        med_gap = float(np.median(stair_gaps))
        if stance_grounded < 0.65 or med_gap > 0.038:
            fail(
                "%s: stair climb boots floating above treads (median_gap=%.3fm, grounded_ratio=%.2f < 0.65!)"
                % (shot_id, med_gap, stance_grounded)
            )

    # Monotonic runway takeoff acceleration check (`F-17`)
    if len(jet_roll_positions) >= 30:
        r_frames = sorted(jet_roll_positions.keys())
        for rf in r_frames:
            if (rf + 1) in jet_roll_positions and (rf + 11) in jet_roll_positions and rf <= r_frames[0] + 35:
                v_now = float((jet_roll_positions[rf + 1] - jet_roll_positions[rf]).length) * FPS
                v_lat = float((jet_roll_positions[rf + 11] - jet_roll_positions[rf + 10]).length) * FPS
                if v_lat <= v_now + 0.05:
                    fail("%s f=%d: runway takeoff roll failed monotonic acceleration (v_now=%.2f, v_plus10=%.2f m/s, F-17)!" % (shot_id, rf, v_now, v_lat))

    if shot_continuity_checks:
        for ccheck in shot_continuity_checks:
            ckind = ccheck["kind"]
            if ckind == "require_bg_pedestrian" and not bg_ped_in_frustum:
                fail("%s: zero background pedestrians entered [0.08..0.92] camera NDC (F-24)!" % shot_id)
            elif ckind == "workstation_settle_before_staff":
                f_settle = int(ccheck["settle_frame"])
                staff_ob = ccheck["staff_root"]
                desk_xy = ccheck["desk_xy"]
                for fs_w in range(1, f_settle):
                    scene.frame_set(fs_w)
                    bpy.context.view_layer.update()
                    sp_w = staff_ob.matrix_world.translation
                    if math.hypot(float(sp_w.x) - float(desk_xy[0]), float(sp_w.y) - float(desk_xy[1])) < 1.50:
                        fail("%s f=%d: %s stood at workstation before desk settled at f=%d (F-20)!" % (shot_id, fs_w, staff_ob.name, f_settle))
            elif ckind == "unoccluded_bone_at_frame":
                scene.frame_set(int(ccheck["frame"]))
                bpy.context.view_layer.update()
                arm_ub = ccheck["arm"]
                pt_ub = arm_ub.matrix_world @ arm_ub.pose.bones[ccheck["bone"]].tail
                own_ub = {o.name for o in ccheck["char_root"].children_recursive}
                ok_ub, blk_ub = _ray_hits_subject_unoccluded(scene, scene.camera, pt_ub, own_ub)
                if not ok_ub:
                    fail("%s f=%d: %s %s occluded by %r (F-22)!" % (shot_id, ccheck["frame"], ccheck["char_root"].name, ccheck["bone"], blk_ub))
            elif ckind == "occluded_before_hide":
                # On the last visible frame right before hide_render turns True, Hero must already be occluded inside cabin!
                scene.frame_set(int(ccheck["last_vis_frame"]))
                bpy.context.view_layer.update()
                pts_oh = subject_world_points(ccheck["objs"])
                c_oh = 0.5 * (pts_oh.min(axis=0) + pts_oh.max(axis=0))
                own_oh = {o.name for o in ccheck["objs"]}
                ok_oh, _ = _ray_hits_subject_unoccluded(scene, scene.camera, (float(c_oh[0]), float(c_oh[1]), float(c_oh[2])), own_oh)
                if ok_oh:
                    fail("%s f=%d: %s still directly visible from camera right before hide_render pop-out (F-16)!" % (shot_id, ccheck["last_vis_frame"], ccheck["label"]))
            elif ckind == "stanchion_chain_fit":
                scene.frame_set(1)
                bpy.context.view_layer.update()
                dg_sc = bpy.context.evaluated_depsgraph_get()
                for ch_ob, p_a, p_b in ccheck["chains"]:
                    ch_aabb = mesh_world_aabb(list(ch_ob.children_recursive), dg_sc)
                    pa_aabb = mesh_world_aabb(list(p_a.children_recursive), dg_sc)
                    pb_aabb = mesh_world_aabb(list(p_b.children_recursive), dg_sc)
                    y_lo_pole = min(0.5 * (pa_aabb[2] + pa_aabb[3]), 0.5 * (pb_aabb[2] + pb_aabb[3]))
                    y_hi_pole = max(0.5 * (pa_aabb[2] + pa_aabb[3]), 0.5 * (pb_aabb[2] + pb_aabb[3]))
                    # Pole collar radius is ~0.04m around pole center
                    if abs(ch_aabb[2] - (y_lo_pole + 0.04)) > 0.06 or abs(ch_aabb[3] - (y_hi_pole - 0.04)) > 0.06:
                        fail("%s: stanchion chain %s endpoints [%.3f,%.3f] miss pole collars [%.3f,%.3f] (F-21)!" % (shot_id, ch_ob.name, ch_aabb[2], ch_aabb[3], y_lo_pole, y_hi_pole))
            elif ckind == "arm_elbows_below_shoulders":
                arm_eb = ccheck["arm"]
                cr_eb = ccheck["char_root"]
                f0_eb, f1_eb = ccheck["frames"]
                min_drop_eb = float(ccheck.get("min_drop_m", 0.045))
                for fe in range(int(f0_eb), int(f1_eb) + 1):
                    scene.frame_set(fe)
                    bpy.context.view_layer.update()
                    amw_e = arm_eb.matrix_world
                    for hs_e in ccheck.get("hands", ("L", "R")):
                        sh_e = amw_e @ arm_eb.pose.bones["Arm." + hs_e].head
                        el_e = amw_e @ arm_eb.pose.bones["Forearm." + hs_e].head
                        drop_e = float(sh_e.z - el_e.z)
                        min_elbow_drop_by_hand[hs_e] = round(min(min_elbow_drop_by_hand.get(hs_e, 999.0), drop_e), 4)
                        if drop_e < min_drop_eb:
                            fail(
                                "%s f=%d (global %d): %s Arm.%s elbow rose above/near shoulder (sh_z=%.3f, el_z=%.3f, drop=%.3fm < %.3fm)!"
                                % (shot_id, fe, g0 + fe, cr_eb.name, hs_e, sh_e.z, el_e.z, drop_e, min_drop_eb)
                            )

    # Real foley-sync verification reading `events` across every shot (`F-27`, `F-28`)!
    known_foley_types = {
        "car_arrive", "car_brake", "car_door", "board_flip", "startle_sting", "pop",
        "footstep", "roller", "stamp_ding", "skid", "conveyor", "scanner_beep",
        "bag_snatch", "pa_chime", "door_whoosh", "jet_idle", "prop_idle", "step_leap",
        "door_seal", "jet_spool", "prop_rev", "takeoff_whoosh", "sky_wind", "logo_slam", "badge_pop",
    }
    if not events:
        fail("%s: verify_human_motion received empty events list (F-28)!" % shot_id)
    local_evs = []
    foley_checks_passed = 0
    for ev in events:
        etype = ev.get("type")
        lf = int(ev.get("frame", -999)) - int(g0)
        edur = int(ev.get("dur", 1))
        if etype not in known_foley_types:
            fail("%s: unknown foley event type %r (F-28)!" % (shot_id, etype))
        if not (1 <= lf <= n_frames) or edur < 1:
            fail("%s: foley event %r out of shot frame bounds [1..%d] (local_f=%d, dur=%d, F-28)!" % (shot_id, etype, n_frames, lf, edur))
        local_evs.append((etype, lf, edur))
        foley_checks_passed += 1

    def _has_ev(et, lo_f=1, hi_f=n_frames):
        return [lf for t, lf, _ in local_evs if t == et and lo_f <= lf <= hi_f]

    def _roller_overlaps(lo_f, hi_f):
        return [
            (lf, lf + d - 1)
            for t, lf, d in local_evs
            if t == "roller" and not ((lf + d - 1) < lo_f or lf > hi_f)
        ]

    if shot_id == "shot_01":
        if not _has_ev("car_arrive", 1, 5) or not _has_ev("car_door", 14, 22) or not _has_ev("car_door", 98, 108):
            fail("shot_01: missing car_arrive or open/close car_door foley events (F-27)!")
        if not _has_ev("board_flip", 46, 56) or not _has_ev("door_whoosh", 85, 105) or len(_has_ev("footstep")) < 10:
            fail("shot_01: missing board_flip, door_whoosh, or curb footsteps!")
        if _roller_overlaps(52, 92):
            fail("shot_01: roller foley active during stationary board-gaze pause [52..92]: %s!" % (_roller_overlaps(52, 92),))
        foley_checks_passed += 6
    elif shot_id == "shot_02":
        if len(_has_ev("pop")) < 10 or not _has_ev("stamp_ding", 118, 132) or len(_has_ev("footstep")) < 15:
            fail("shot_02: missing snap-pop, stamp_ding, or concourse footstep foley!")
        if _roller_overlaps(106, 145):
            fail("shot_02: roller foley active while stationary at check-in counter [106..145]!")
        foley_checks_passed += 4
    elif shot_id == "shot_03":
        if _roller_overlaps(56, 132):
            fail("shot_03: roller foley active during X-ray belt ride [56..132]: %s (F-27)!" % (_roller_overlaps(56, 132),))
        if not _has_ev("conveyor", 54, 58) or not _has_ev("scanner_beep", 88, 100) or not _has_ev("bag_snatch", 136, 146) or not _has_ev("door_whoosh", 158, 180):
            fail("shot_03: missing conveyor, scanner_beep, bag_snatch, or door_whoosh foley!")
        foley_checks_passed += 5
    elif shot_id == "shot_04":
        if not _has_ev("pa_chime", 1, 15) or not _has_ev("door_whoosh", 80, 95) or not _has_ev("scanner_beep", 130, 150) or len(_has_ev("footstep")) < 20:
            fail("shot_04: missing pa_chime, door_whoosh, scanner_beep, or sprint footsteps!")
        foley_checks_passed += 4
    elif shot_id == "shot_05":
        if len(_has_ev("footstep", 18, 50)) < 4:
            fail("shot_05: missing stair-climb footstep foley across [18..50] (found %d)!" % len(_has_ev("footstep", 18, 50)))
        if not _has_ev("jet_idle", 1, 5) or not _has_ev("step_leap", 18, 24) or not _has_ev("door_seal", 72, 84) or not _has_ev("jet_spool", 88, 92) or not _has_ev("takeoff_whoosh", 130, 145):
            fail("shot_05: missing jet_idle, step_leap, door_seal, jet_spool, or takeoff_whoosh foley!")
        if _has_ev("footstep", 89, n_frames) or _roller_overlaps(89, n_frames):
            fail("shot_05: footstep/roller foley leaked into runway takeoff cut [89..%d]!" % n_frames)
        foley_checks_passed += 7
    elif shot_id == "shot_06":
        if not _has_ev("sky_wind", 1, 5) or not _has_ev("logo_slam", 16, 20) or not _has_ev("badge_pop", 40, 44):
            fail("shot_06: missing sky_wind, logo_slam, or badge_pop foley!")
        foley_checks_passed += 3

    summary = {
        "shot": shot_id,
        "characters": len(char_roots),
        "obstacles": len(obs_boxes),
        "min_obstacle_clearance_m": round(min_obs_d, 3) if min_obs_d < 900 else None,
        "min_table_clearance_m": round(min_table_d, 3) if min_table_d < 900 else None,
        "min_character_sep_m": round(min_char_d, 3) if min_char_d < 900 else None,
        "max_yaw_step_deg": round(max_yaw_step, 2),
        "max_ik_grip_err_m": round(max_ik_err, 4),
        "bag_vs_char_bvh_overlaps": bag_body_overlap_total,
        "min_bar_knuckle_dot": round(min_bar_knuckle_dot, 4) if roller_grip_checks else None,
        "min_bar_palm_dot": round(min_bar_palm_dot, 4) if roller_grip_checks else None,
        "max_roller_hollow_err_m": round(max_roller_hollow_err, 4) if roller_grip_checks else None,
        "min_roller_wrist_clear_m": round(min_roller_wrist_clear, 4) if min_roller_wrist_clear < 900 else None,
        "max_roller_wrist_kink_deg": round(max_roller_kink_deg, 2) if roller_grip_checks else None,
        "roller_rod_slot_hits": roller_rod_slot_hits if roller_grip_checks else None,
        "min_stair_foot_margin_m": round(min_stair_margin, 3) if min_stair_margin < 900 else None,
        "median_stair_foot_gap_m": round(float(np.median(stair_gaps)), 3) if stair_gaps else None,
        "max_stair_foot_gap_m": round(float(max(stair_gaps)), 3) if stair_gaps else None,
        "closed_door_checks_passed": closed_door_checks_passed,
        "max_closed_door_seam_err_m": round(max_closed_door_seam_err, 4) if closed_door_checks_passed else None,
        "road_max_edge_len_m": road_max_edge_len_m,
        "road_max_edge_stretch_ratio": road_max_edge_stretch_ratio,
        "cabin_floor_x_max_m": cabin_floor_x_max_m,
        "cabin_floor_protrusion_m": cabin_floor_protrusion_m,
        "min_elbow_drop_m": min_elbow_drop_by_hand if min_elbow_drop_by_hand else None,
        "foley_sync_checked": True,
        "foley_event_count": len(local_evs),
        "foley_checks_passed": foley_checks_passed,
        "quaternion_only": True,
        "unit_human_scale": True,
    }
    log(
        "PROBE human_motion %s chars=%d obs=%d bag_bvh_ov=%d min_obs_clear=%.3fm min_char_sep=%.3fm max_ik_err=%.3fm max_yaw_step=%.1fdeg quat=OK scale1=OK"
        % (
            shot_id,
            len(char_roots),
            len(obs_boxes),
            bag_body_overlap_total,
            min_obs_d if min_obs_d < 900 else 9.99,
            min_char_d if min_char_d < 900 else 9.99,
            max_ik_err,
            max_yaw_step,
        )
    )
    return summary


# ---------------------------------------------------------------- Elastic Snap-In Animation


def animate_snap_pop(obj, trigger_frame, drop_height=1.35, settle_frames=13):
    if obj.name.startswith("CHAR_") or obj.type == "ARMATURE" or any(c.type == "ARMATURE" for c in obj.children):
        fail("animate_snap_pop forbidden on human character %r (humans must NEVER drop/squash from ceiling!)" % obj.name)
    base_loc = Vector(obj.location)
    base_scale = Vector(obj.scale)
    t0 = int(trigger_frame)

    if t0 <= 1:
        obj.location = base_loc
        obj.scale = base_scale
        return

    pts = [
        (1, base_loc + Vector((0, 0, drop_height)), Vector((0.0001, 0.0001, 0.0001))),
        (t0 - 1, base_loc + Vector((0, 0, drop_height)), Vector((0.0001, 0.0001, 0.0001))),
        (t0, base_loc + Vector((0, 0, drop_height)), Vector((0.45, 0.45, 1.25))),
        (t0 + 4, base_loc, Vector((1.20, 1.20, 0.78))),
        (t0 + 7, base_loc + Vector((0, 0, 0.08)), Vector((0.92, 0.92, 1.12))),
        (t0 + 10, base_loc, Vector((1.04, 1.04, 0.96))),
        (t0 + settle_frames, base_loc, Vector((1.0, 1.0, 1.0))),
    ]
    for f, loc, sc in pts:
        obj.location = loc
        obj.scale = Vector((base_scale.x * sc.x, base_scale.y * sc.y, base_scale.z * sc.z))
        obj.keyframe_insert(data_path="location", frame=f)
        obj.keyframe_insert(data_path="scale", frame=f)


# ---------------------------------------------------------------- Camera, Clouds, Hills & Primitives


def make_camera(scene, name="ShotCam", lens=36.0, fstop=2.8, dof_dist=6.5):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_start = 0.15
    cam_data.clip_end = 1200.0
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = fstop
    cam_data.dof.focus_distance = dof_dist
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    target = bpy.data.objects.new(name + "_Target", None)
    scene.collection.objects.link(target)
    cns = cam.constraints.new("TRACK_TO")
    cns.target = target
    cns.track_axis = "TRACK_NEGATIVE_Z"
    cns.up_axis = "UP_Y"
    cam_data.dof.focus_object = target
    return cam, target


def key_pos(obj, keys):
    for f, pos in keys:
        obj.location = pos
        obj.keyframe_insert(data_path="location", frame=int(f))


def key_rot_deg(obj, keys):
    obj.rotation_mode = "XYZ"
    for f, (rx, ry, rz) in keys:
        obj.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
        obj.keyframe_insert(data_path="rotation_euler", frame=int(f))


def make_box(scene, name, size, loc, mat, bevel=0.02, parent=None, outline=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    scene.collection.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    if bevel > 0.0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 2
    if outline > 0.0:
        attach_outline(ob, outline)
    return ob


def add_toon_clouds(scene, centres, seed_scale=1.0):
    cloud_mat = toon_rgb_mat("cloud_cream", (1.0, 0.96, 0.90))
    root = bpy.data.objects.new("Clouds_ROOT", None)
    scene.collection.objects.link(root)
    puffs = [
        ((0.0, 0.0, 0.0), (3.4, 2.2, 1.6)),
        ((-2.2, 0.3, -0.3), (2.3, 1.8, 1.2)),
        ((2.3, -0.2, -0.25), (2.5, 1.9, 1.3)),
        ((0.7, 0.5, 0.7), (2.1, 1.6, 1.3)),
        ((-0.9, -0.4, 0.55), (1.9, 1.5, 1.1)),
    ]
    for idx, (cx, cy, cz, s) in enumerate(centres):
        holder = bpy.data.objects.new("Cloud_%d" % idx, None)
        holder.location = (cx, cy, cz)
        holder.parent = root
        scene.collection.objects.link(holder)
        for j, (off, rad) in enumerate(puffs):
            bpy.ops.mesh.primitive_ico_sphere_add(
                subdivisions=2,
                radius=1.0,
                location=(off[0] * s * seed_scale, off[1] * s * seed_scale, off[2] * s * seed_scale),
            )
            sp = bpy.context.active_object
            sp.name = "CloudPuff_%d_%d" % (idx, j)
            sp.scale = (rad[0] * s * seed_scale, rad[1] * s * seed_scale, rad[2] * s * seed_scale)
            for poly in sp.data.polygons:
                poly.use_smooth = True
            sp.data.materials.append(cloud_mat)
            sp.visible_shadow = False
            sp.parent = holder
    return root


def add_horizon_hills_and_treeline(scene):
    """Build warm golden-mist rolling hills & distant treelines around the airfield perimeter
    so Shot 5 never shows a flat green plane horizon edge!"""
    root = bpy.data.objects.new("HorizonScenery_ROOT", None)
    scene.collection.objects.link(root)
    hill_near = toon_rgb_mat("hill_near", (0.55, 0.69, 0.44))
    hill_far = emissive_mat("hill_far_mist", (0.86, 0.82, 0.72), strength=0.92)

    hills = [
        ((-125, -240, -2.0), (95, 55, 18), hill_near),
        ((-65, -340, -3.0), (130, 65, 24), hill_far),
        ((35, -360, -3.0), (140, 70, 22), hill_far),
        ((-175, -120, -2.0), (75, 95, 16), hill_near),
        ((-190, -20, -2.0), (80, 95, 15), hill_near),
        ((-160, 90, -2.0), (95, 70, 19), hill_far),
    ]
    for idx, (loc, rad, mat) in enumerate(hills):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=loc)
        h = bpy.context.active_object
        h.name = "HorizonHill_%d" % idx
        h.scale = rad
        for poly in h.data.polygons:
            poly.use_smooth = True
        h.data.materials.append(mat)
        h.visible_shadow = False
        h.parent = root

    # Distant treeline along the airfield's west (-X) perimeter
    for ty in range(-220, 80, 24):
        tr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "AirTree_%d" % ty, loc=(-54.0, float(ty), 0.0), outline_thickness=0.0)
        s = 2.6 + 0.5 * ((ty * 7) % 3)
        tr.scale = (s, s, s)
        tr.parent = root
    return root


# ---------------------------------------------------------------- AAA Post Grade (Bloom + Vignette)


def apply_cinematic_grade(rgba):
    """Apply soft linear-light Highlight Bloom/Glow + Subtle Lens Vignette + Warm Filmic S-Curve
    using OpenImageIO + NumPy (~12 ms/frame, 100% temporal-flicker-free!)."""
    rgb = np.clip(rgba[:, :, :3], 0.0, 1.0)
    # Approximate sRGB -> linear
    lin = np.power(rgb, 2.2)

    # 1. Soft Highlight Bloom (recessed LEDs, golden sun rims, departure board, emerald arch flash!)
    luma = 0.2126 * lin[:, :, 0] + 0.7152 * lin[:, :, 1] + 0.0722 * lin[:, :, 2]
    bright_mask = np.clip((luma - 0.58) / 0.42, 0.0, 1.0)[:, :, None]
    bright = (lin * bright_mask).astype(np.float32)

    # Downsample 8x -> smooth Gaussian blur in OIIO -> upsample back to 1920x1080
    H, W = lin.shape[:2]
    sw, sh = W // 8, H // 8
    b_src = oiio.ImageBuf(oiio.ImageSpec(W, H, 3, oiio.FLOAT))
    b_src.set_pixels(oiio.ROI(), np.ascontiguousarray(bright))
    b_small = oiio.ImageBufAlgo.resize(b_src, roi=oiio.ROI(0, sw, 0, sh, 0, 1, 0, 3))
    k = oiio.ImageBufAlgo.make_kernel("gaussian", 9.0, 9.0)
    b_blur = oiio.ImageBufAlgo.convolve(b_small, k)
    b_up = oiio.ImageBufAlgo.resize(b_blur, roi=oiio.ROI(0, W, 0, H, 0, 1, 0, 3))
    bloom = np.clip(b_up.get_pixels(oiio.FLOAT), 0.0, 2.0)

    lin = lin + 0.22 * bloom

    # 2. Subtle Cinematic Lens Vignette (focuses eye on center subject)
    yy = np.linspace(-1.0, 1.0, H, dtype=np.float32)[:, None]
    xx = np.linspace(-1.0, 1.0, W, dtype=np.float32)[None, :]
    r2 = 0.65 * (xx * xx) + 0.85 * (yy * yy)
    vig = np.clip(1.0 - 0.14 * (r2 ** 1.35), 0.78, 1.0)[:, :, None]
    lin = lin * vig

    # Back to sRGB + gentle crisp S-curve contrast
    out_srgb = np.power(np.clip(lin, 0.0, 1.0), 1.0 / 2.2)
    out_srgb = np.clip(0.5 + (out_srgb - 0.5) * 1.06, 0.0, 1.0)

    out = rgba.copy()
    out[:, :, :3] = out_srgb
    out[:, :, 3] = 1.0
    return out


# ---------------------------------------------------------------- SDF Nunito Text & Logo


def _embolden_node_group(radius, mat):
    ng = bpy.data.node_groups.new("nunito_sdf", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n = ng.nodes
    gin = n.new("NodeGroupInput")
    gout = n.new("NodeGroupOutput")
    voxel = max(0.004, radius / 4.5)
    sdf = n.new("GeometryNodeMeshToSDFGrid")
    sdf.inputs["Voxel Size"].default_value = voxel
    sdf.inputs["Band Width"].default_value = int(math.ceil(radius / voxel)) + 4
    grow = n.new("GeometryNodeSDFGridOffset")
    grow.inputs["Distance"].default_value = radius
    tomesh = n.new("GeometryNodeGridToMesh")
    tomesh.inputs["Threshold"].default_value = 0.0
    smooth = n.new("GeometryNodeSetShadeSmooth")
    setmat = n.new("GeometryNodeSetMaterial")
    setmat.inputs["Material"].default_value = mat
    lk = ng.links
    lk.new(gin.outputs[0], sdf.inputs["Mesh"])
    lk.new(sdf.outputs[0], grow.inputs["Grid"])
    lk.new(grow.outputs[0], tomesh.inputs["Grid"])
    lk.new(tomesh.outputs[0], smooth.inputs["Geometry"])
    lk.new(smooth.outputs[0], setmat.inputs["Geometry"])
    lk.new(setmat.outputs[0], gout.inputs[0])
    return ng


def make_nunito_text_3d(scene, text, size, weight, mat, extrude=0.02, spacing=1.06, parent=None):
    font = bpy.data.fonts.load(FONT_PATH, check_existing=True)
    cu = bpy.data.curves.new("CU_" + text[:16], "FONT")
    cu.body = text
    cu.font = font
    cu.size = size
    cu.fill_rule = "NONZERO"
    cu.extrude = max(extrude, 0.012)
    cu.space_character = spacing
    cu.space_word = 1.12
    cu.resolution_u = 20
    tmp = bpy.data.objects.new("TMP_" + text[:16], cu)
    scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    if len(me.polygons) == 0:
        fail("Nunito text %r produced 0 polygons" % text)
    src_w = max(v.co.x for v in me.vertices) - min(v.co.x for v in me.vertices)

    ob = bpy.data.objects.new("TXT_" + text[:18], me)
    scene.collection.objects.link(ob)
    mod = ob.modifiers.new("embolden", "NODES")
    mod.node_group = _embolden_node_group(weight, mat)
    bpy.context.view_layer.update()
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    ev_me = ev.to_mesh()
    xs = [v.co.x for v in ev_me.vertices]
    ys = [v.co.y for v in ev_me.vertices]
    zs = [v.co.z for v in ev_me.vertices]
    grown = (max(xs) - min(xs)) - src_w
    if grown < 1.35 * weight:
        fail("SDF embolden failed on %r: grown=%.4f expected>=%.4f" % (text, grown, 1.35 * weight))
    cx = 0.5 * (min(xs) + max(xs))
    cy = 0.5 * (min(ys) + max(ys))
    cz = 0.5 * (min(zs) + max(zs))
    baked = bpy.data.meshes.new("BAKED_" + text[:18])
    bm = bmesh.new()
    bm.from_mesh(ev_me)
    bmesh.ops.translate(bm, vec=(-cx, -cy, -cz), verts=bm.verts)
    bm.to_mesh(baked)
    bm.free()
    ev.to_mesh_clear()
    baked.materials.append(mat)
    ob.modifiers.clear()
    ob.data = baked
    if parent is not None:
        ob.parent = parent
    return ob


def ensure_branding_pngs(ui_dir):
    os.makedirs(ui_dir, exist_ok=True)
    logo_path = os.path.join(ui_dir, "logo_a_sticker.png")
    badge_path = os.path.join(ui_dir, "wishlist_badge.png")
    logo_script = os.path.join(REPO, "tools", "blender", "logo", "build_logos.py")
    src_mtime = max(os.path.getmtime(logo_script), os.path.getmtime(__file__))
    if (
        os.path.isfile(logo_path)
        and os.path.isfile(badge_path)
        and os.path.getmtime(logo_path) >= src_mtime
        and os.path.getmtime(badge_path) >= src_mtime
    ):
        log("PROBE brand reusing fresh %s and %s" % (os.path.basename(logo_path), os.path.basename(badge_path)))
        return logo_path, badge_path

    with open(logo_script, "r", encoding="utf-8") as fh:
        src = fh.read()
    ns = {"__file__": logo_script, "__name__": "build_logos_lib"}
    cut_idx = src.rfind("\ndef main():")
    if cut_idx < 0:
        fail("could not locate def main() in build_logos.py")
    exec(compile(src[:cut_idx], logo_script, "exec"), ns)

    raw_dir = os.path.join(ui_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)

    scene, font = ns["new_scene"]()
    main_objs, under_objs, style = ns["build_a"](scene, font)
    ppu = ns["frame_camera"](scene, main_objs + under_objs, style)
    for o in under_objs:
        o.hide_render = True
    main_exr = ns["render_exr"](scene, os.path.join(raw_dir, "logo_main.exr"))
    for o in under_objs:
        o.hide_render = False
    for o in main_objs:
        o.hide_render = True
    under_exr = ns["render_exr"](scene, os.path.join(raw_dir, "logo_under.exr"))
    comp = ns["composite"](main_exr, under_exr, style, ppu)
    y0, y1, x0, x1 = ns["alpha_bbox"](comp)
    tight = comp[y0:y1, x0:x1]
    pad = int(round(0.03 * tight.shape[1]))
    padded = np.zeros((tight.shape[0] + 2 * pad, tight.shape[1] + 2 * pad, 4), np.float32)
    padded[pad : pad + tight.shape[0], pad : pad + tight.shape[1]] = tight
    logo_w = 1480
    logo_h = int(round(padded.shape[0] * logo_w / padded.shape[1]))
    ns["write_png"](logo_path, ns["encode"](ns["resize"](padded, logo_w, logo_h)))
    log("PROBE brand logo_a_sticker.png size=%dx%d" % (logo_w, logo_h))

    scene2, font2 = ns["new_scene"]()
    txt = ns["text_obj"](scene2, font2, "WISHLIST ON STEAM", 0.72, 0.032, ns["flat_mat"]("navy_txt", NAVY), spacing=1.08)
    ns["place"](txt, 0.0, 0.0)
    bx0, bx1, by0, by1 = ns["local_bounds"](txt)
    bw = (bx1 - bx0) + 0.90
    bh = (by1 - by0) + 0.56
    pill = ns["poly_obj"](scene2, "pill_bg", ns["rounded_rect"](0.0, 0.0, bw, bh, bh * 0.48, seg=14),
                          ns["flat_mat"]("cream_pill", CREAM), z=-0.05)
    dot_l = ns["poly_obj"](scene2, "dot_l", ns["circle"](bx0 - 0.22, 0.0, 0.085), ns["flat_mat"]("lime_d", GOTTA_LIME), z=0.01)
    dot_r = ns["poly_obj"](scene2, "dot_r", ns["circle"](bx1 + 0.22, 0.0, 0.085), ns["flat_mat"]("lime_d2", GOTTA_LIME), z=0.01)
    b_objs = [txt, pill, dot_l, dot_r]
    b_style = {"outline": 0.065, "shadow": (0.018, -0.075)}
    bppu = ns["frame_camera"](scene2, b_objs, b_style)
    b_exr = ns["render_exr"](scene2, os.path.join(raw_dir, "badge_main.exr"))
    b_comp = ns["composite"](b_exr, None, b_style, bppu)
    by0, by1, bx0, bx1 = ns["alpha_bbox"](b_comp)
    btight = b_comp[by0:by1, bx0:bx1]
    bpad = int(round(0.03 * btight.shape[1]))
    bpadded = np.zeros((btight.shape[0] + 2 * bpad, btight.shape[1] + 2 * bpad, 4), np.float32)
    bpadded[bpad : bpad + btight.shape[0], bpad : bpad + btight.shape[1]] = btight
    badge_w = 820
    badge_h = int(round(bpadded.shape[0] * badge_w / bpadded.shape[1]))
    ns["write_png"](badge_path, ns["encode"](ns["resize"](bpadded, badge_w, badge_h)))
    log("PROBE brand wishlist_badge.png size=%dx%d" % (badge_w, badge_h))

    return logo_path, badge_path


# ---------------------------------------------------------------- In-Frame & Image Probes


def subject_world_points(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        if len(me.vertices):
            n = len(me.vertices)
            co = np.empty(n * 3, dtype=np.float64)
            me.vertices.foreach_get("co", co)
            co = co.reshape(n, 3)
            mw = np.array(ev.matrix_world)
            pts.append(co @ mw[:3, :3].T + mw[:3, 3])
        ev.to_mesh_clear()
    if not pts:
        fail("subject_world_points: subject has 0 visible mesh vertices")
    return np.concatenate(pts, axis=0)


def _ray_hits_subject_unoccluded(scene, cam, target_pt, own_names):
    """Cast a ray from `cam` toward `target_pt`, stepping past genuinely transparent glass/vapor
    polygons (checking the hit polygon's OWN material slot, never treating opaque vehicle/facade
    multi-material meshes as transparent!) or hidden/zero-scaled objects."""
    dg = bpy.context.evaluated_depsgraph_get()
    origin = cam.matrix_world.translation.copy()
    goal = Vector(target_pt)
    for _ in range(12):
        vec = goal - origin
        dist = vec.length
        if dist < 0.05:
            return True, None
        direction = vec / dist
        hit, loc, _nrm, poly_idx, ob, _mw = scene.ray_cast(dg, origin, direction, distance=dist - 0.04)
        if not hit or ob is None:
            return True, None
        orig_ob = ob.original if hasattr(ob, "original") and ob.original is not None else ob
        if orig_ob.name in own_names:
            return True, None
        wscale = ob.matrix_world.to_scale()
        hit_mat_name = ""
        mats = getattr(orig_ob.data, "materials", [])
        polys = getattr(orig_ob.data, "polygons", [])
        if mats and 0 <= poly_idx < len(polys):
            mi = polys[poly_idx].material_index
            if 0 <= mi < len(mats) and mats[mi] is not None:
                hit_mat_name = mats[mi].name
        # ONLY `TOON_TP_Glass` (86% transparent architectural window glass) and `SOFT_VAPOR` are see-through;
        # `TOON_Vehicle_Glass` and `TOON_TP_ExtLobbyGlass` are 100% opaque!
        is_transp = (
            orig_ob.hide_render
            or min(abs(wscale.x), abs(wscale.y), abs(wscale.z)) < 0.02
            or ("TOON_TP_Glass" in hit_mat_name)
            or ("SOFT_VAPOR" in hit_mat_name)
        )
        if is_transp:
            origin = loc + direction * 0.03
            continue
        # If hit is within 0.24m of target_pt (character's own raised hand/prop right at chest/head), count as clear
        if (loc - goal).length < 0.24:
            return True, None
        return False, orig_ob.name
    return True, None


def prove_subject_in_frame(scene, cam, objs, label, lo_bound=IN_FRAME_LO, hi_bound=IN_FRAME_HI, check_occlusion=True):
    bpy.context.view_layer.update()
    pts = subject_world_points(objs)
    lo = pts.min(axis=0)
    hi = pts.max(axis=0)
    center = 0.5 * (lo + hi)
    span = hi - lo
    core_lo = lo + 0.14 * span
    core_hi = hi - 0.14 * span
    us, vs, zs = [], [], []
    for x in (core_lo[0], center[0], core_hi[0]):
        for y in (core_lo[1], center[1], core_hi[1]):
            for z in (core_lo[2], center[2], core_hi[2]):
                ndc = world_to_camera_view(scene, cam, Vector((float(x), float(y), float(z))))
                us.append(float(ndc.x))
                vs.append(float(ndc.y))
                zs.append(float(ndc.z))
    c_ndc = world_to_camera_view(scene, cam, Vector(tuple(float(v) for v in center)))
    u_min, u_max = min(us), max(us)
    v_min, v_max = min(vs), max(vs)

    occ_ok = True
    blocker = None
    if check_occlusion:
        own_names = {o.name for o in objs}
        roots = {o.parent for o in objs if o.parent is not None}
        for o in scene.objects:
            if o.parent in roots or (o.parent and o.parent.parent in roots):
                own_names.add(o.name)
        is_human_subj = any(r.name.startswith("CHAR_") or r.type == "ARMATURE" for r in roots)
        if is_human_subj:
            chest_pt = (float(center[0]), float(center[1]), float(lo[2] + 0.62 * span[2]))
            head_pt = (float(center[0]), float(center[1]), float(lo[2] + 0.84 * span[2]))
            ok_c, b_c = _ray_hits_subject_unoccluded(scene, cam, chest_pt, own_names)
            ok_h, b_h = _ray_hits_subject_unoccluded(scene, cam, head_pt, own_names)
            # Require BOTH chest AND head unoccluded (`ok_c and ok_h`, never `or`!) (`F-11`)
            occ_ok = bool(ok_c and ok_h)
            blocker = b_c if not ok_c else b_h
        else:
            mid_pt = (float(center[0]), float(center[1]), float(center[2]))
            ok_m, b_m = _ray_hits_subject_unoccluded(scene, cam, mid_pt, own_names)
            occ_ok = bool(ok_m)
            blocker = b_m

    log(
        "PROBE in_frame %s center=(%.3f,%.3f) depth=%.2fm core_u=[%.3f,%.3f] core_v=[%.3f,%.3f] unoccluded=%s"
        % (label, c_ndc.x, c_ndc.y, c_ndc.z, u_min, u_max, v_min, v_max, occ_ok)
    )
    if min(zs) <= cam.data.clip_start:
        fail("%s: hero subject behind camera (min_z=%.3f)" % (label, min(zs)))
    if not (lo_bound <= c_ndc.x <= hi_bound and lo_bound <= c_ndc.y <= hi_bound):
        fail("%s: hero center (%.3f, %.3f) outside [%.2f..%.2f]" % (label, c_ndc.x, c_ndc.y, lo_bound, hi_bound))
    if u_min < lo_bound or u_max > hi_bound or v_min < lo_bound or v_max > hi_bound:
        fail(
            "%s: hero core box u=[%.3f,%.3f] v=[%.3f,%.3f] leaves [%.2f..%.2f]"
            % (label, u_min, u_max, v_min, v_max, lo_bound, hi_bound)
        )
    if not occ_ok:
        fail("%s: hero subject is occluded from camera by %r" % (label, blocker))
    return {
        "label": label,
        "center": [round(float(c_ndc.x), 4), round(float(c_ndc.y), 4)],
        "u": [round(u_min, 4), round(u_max, 4)],
        "v": [round(v_min, 4), round(v_max, 4)],
        "depth_m": round(float(c_ndc.z), 2),
        "unoccluded": occ_ok,
    }


def read_png_float(path):
    inp = oiio.ImageInput.open(path)
    if not inp:
        fail("cannot read PNG %s: %s" % (path, oiio.geterror()))
    spec = inp.spec()
    arr = inp.read_image("uint8")
    inp.close()
    if arr is None:
        fail("empty read of %s" % path)
    arr = arr.reshape(spec.height, spec.width, spec.nchannels).astype(np.float32) / 255.0
    if spec.nchannels == 3:
        arr = np.concatenate([arr, np.ones((spec.height, spec.width, 1), np.float32)], axis=2)
    return arr[:, :, :4]


def write_png_float(path, arr_rgba):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    arr8 = (np.clip(arr_rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    h, w, c = arr8.shape
    spec = oiio.ImageSpec(w, h, c, oiio.UINT8)
    out = oiio.ImageOutput.create(path)
    if not out or not out.open(path, spec):
        fail("cannot write PNG %s: %s" % (path, oiio.geterror()))
    out.write_image(np.ascontiguousarray(arr8))
    out.close()


def verify_frame_not_black_and_skin(arr_rgba, label, skin_uv=None):
    rgb = arr_rgba[:, :, :3]
    mean_luma = float(rgb.mean())
    std_luma = float(rgb.std())
    dark_frac = float((rgb.max(axis=2) < 0.03).mean())
    if mean_luma < 0.08 or std_luma < 0.03 or dark_frac > 0.70:
        fail("%s: black or flat frame (mean=%.3f std=%.3f dark_frac=%.3f)" % (label, mean_luma, std_luma, dark_frac))
    if skin_uv is not None:
        u, v = skin_uv
        h, w = rgb.shape[:2]
        cx = int(np.clip(round(u * w), 8, w - 9))
        cy = int(np.clip(round((1.0 - v) * h), 8, h - 9))
        patch = rgb[cy - 7 : cy + 8, cx - 7 : cx + 8]
        warm = patch[(patch[:, :, 0] > 0.28) & (patch[:, :, 0] > patch[:, :, 2] * 1.05)]
        peak_r = float(patch[:, :, 0].max())
        log("PROBE skin_check %s uv=(%.3f,%.3f) patch_peak_r=%.3f warm_px=%d" % (label, u, v, peak_r, len(warm)))
        if peak_r < 0.22:
            fail("%s: character head region looks black/untextured (peak_r=%.3f)" % (label, peak_r))
    return mean_luma, std_luma


def head_ndc(scene, cam, arm):
    bpy.context.view_layer.update()
    pb = arm.pose.bones.get("Head")
    if pb is None:
        return None
    world_head = arm.matrix_world @ ((pb.head + pb.tail) * 0.5)
    char_fwd = (arm.matrix_world.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
    to_cam = (cam.matrix_world.translation - world_head).normalized()
    if char_fwd.dot(to_cam) < -0.10:
        return None
    ndc = world_to_camera_view(scene, cam, world_head)
    if 0.04 < ndc.x < 0.96 and 0.04 < ndc.y < 0.96 and ndc.z > 0.2:
        return (float(ndc.x), float(ndc.y))
    return None
