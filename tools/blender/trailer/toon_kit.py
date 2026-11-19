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
from mathutils import Matrix, Vector

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
    if indoor:
        e0.position = -0.02
        e1.position = 0.28
        e0.color = srgb_to_lin((0.99, 0.88, 0.70)) + (1.0,)
        e1.color = srgb_to_lin((0.36, 0.68, 0.98)) + (1.0,)
    else:
        e0.position = -0.005
        e0.color = srgb_to_lin((1.00, 0.83, 0.55)) + (1.0,)
        em = ramp.color_ramp.elements.new(0.085)
        em.color = srgb_to_lin((0.76, 0.89, 0.99)) + (1.0,)
        e1.position = 0.24
        e1.color = srgb_to_lin((0.24, 0.58, 0.96)) + (1.0,)
    nt.links.new(elev.outputs["Value"], ramp.inputs["Fac"])
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.88 if indoor else 0.96
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
    """Soft alpha-feathered translucent wingtip condensation ribbon (fades cleanly to 0)."""
    if "SOFT_VAPOR" in _MAT_CACHE:
        return _MAT_CACHE["SOFT_VAPOR"]
    m = bpy.data.materials.new("SOFT_VAPOR")
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    # Generated.Y goes 0 (front at wingtip) -> 1 (back tail): fade alpha smoothly to 0!
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs["Y"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.8
    nt.links.new(inv.outputs["Value"], pw.inputs[0])
    gain = nt.nodes.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = 0.42
    nt.links.new(pw.outputs["Value"], gain.inputs[0])

    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb_to_lin((1.0, 0.98, 0.95)) + (1.0,)
    em.inputs["Strength"].default_value = 1.05
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
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_image("tp_glass_gradient_1a_d.png")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 0.90
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    glass_mix = nt.nodes.new("ShaderNodeMixShader")
    glass_mix.inputs["Fac"].default_value = 0.24  # Clearer windows so exterior tarmac & planes shine through!
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
    mat_names = [m.name for m in obj.data.materials if m]
    if mat_names and all(("Glass" in n or "Lights" in n or "EMIT_" in n or "SOFT_" in n) for n in mat_names):
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


def rebind_materials(objs, label, outline_thickness=0.005):
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
            elif raw in ("TP_Glass_1A_D", "Glass_Vehicles_01A_D"):
                slot.material = glass_mat()
            else:
                fail("%s: unmapped material %r on %s" % (label, raw, o.name))
        if outline_thickness > 0.0:
            attach_outline(o, outline_thickness)
    return seen


# ---------------------------------------------------------------- Enclosed Terminal Shell


def build_enclosed_terminal_hall(scene, x_min=-5.5, x_max=8.5, y_min=-16.0, y_max=12.0, ceil_z=3.85,
                                 glass_side="left", open_north_wall=False):
    """Build a 100% enclosed, warm architectural airport concourse shell (expansive tiled floor,
    back/side/front walls, structural columns, upper soffits, shadow-transparent ceiling slab with
    glowing recessed LED panels, and lush sunlit tarmac/trees outside the glass windows!)."""
    shell = bpy.data.objects.new("TerminalShell_ROOT", None)
    scene.collection.objects.link(shell)

    # 1. Expansive concourse tile floor extending well past any camera frustum
    fl = make_box(scene, "HallTiledFloor", (38.0, 52.0, 0.12), (0.0, 0.0, -0.065), concourse_tile_floor_mat(), bevel=0.0, parent=shell)
    fl.visible_shadow = True

    wall_m = toon_rgb_mat("hall_wall", WALL_CREAM)
    trim_m = toon_rgb_mat("hall_trim", (0.28, 0.33, 0.44))
    col_m = toon_rgb_mat("hall_col", (0.84, 0.82, 0.78))
    ceil_m = toon_rgb_mat("hall_ceil", CEIL_CREAM, shadow_transparent=True)
    led_m = emissive_mat("ceil_led", (1.0, 0.96, 0.86), strength=1.55)

    # 2. Ceiling slab (shadow_transparent=True so warm KeySun still casts crisp shadows inside!)
    w_span = (x_max - x_min) + 6.0
    l_span = (y_max - y_min) + 8.0
    cx = 0.5 * (x_min + x_max)
    cy = 0.5 * (y_min + y_max)
    ceil = make_box(scene, "HallCeiling", (w_span, l_span, 0.22), (cx, cy, ceil_z + 0.11), ceil_m, bevel=0.0, parent=shell)
    ceil.visible_shadow = False

    # Warm recessed ceiling LED light panels & structural ceiling beams every 4m!
    for by in range(int(y_min) + 2, int(y_max) - 1, 4):
        beam = make_box(scene, "CeilBeam_%d" % by, (w_span - 1.0, 0.28, 0.18), (cx, float(by), ceil_z - 0.08), col_m, bevel=0.02, parent=shell)
        beam.visible_shadow = False
        for lx in (x_min + 2.2, 0.0, x_max - 2.2):
            led = make_box(scene, "CeilLED_%d_%d" % (by, int(lx)), (1.35, 1.65, 0.05), (lx, float(by) + 2.0, ceil_z - 0.02), led_m, bevel=0.01, parent=shell)
            led.visible_shadow = False

    # 3. Back Wall at y_min (with entrance doors & flight screens so looking back never shows void!)
    make_box(scene, "BackWallSolid", (w_span, 0.25, ceil_z), (cx, y_min, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
    make_box(scene, "BackBaseboard", (w_span, 0.30, 0.16), (cx, y_min + 0.04, 0.08), trim_m, bevel=0.0, parent=shell)

    # 4. Far camera-behind side wall (at x_max or x_min opposite the glass wall)
    if glass_side == "left":
        # Glass curtain wall on x_min, solid wall far behind camera at x_max
        make_box(scene, "FarSideWall", (0.25, l_span, ceil_z), (x_max, cy, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        # Upper soffit frieze above the 2.5m wall_glass pieces (z = 2.48 .. ceil_z)
        soffit = make_box(scene, "GlassSoffitL", (0.32, l_span, ceil_z - 2.45), (x_min, cy, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        soffit.visible_shadow = False
        for py in range(int(y_min), int(y_max) + 1, 4):
            make_box(scene, "MullionColL_%d" % py, (0.34, 0.34, ceil_z), (x_min, float(py), ceil_z * 0.5), trim_m, bevel=0.02, parent=shell)
        # Exterior world outside x_min glass wall (paved apron + green lawn + trees!)
        make_box(scene, "ExtApronL", (45.0, 90.0, 0.10), (x_min - 23.0, cy, -0.06), toon_rgb_mat("ext_apron", (0.34, 0.37, 0.42)), bevel=0.0, parent=shell)
        make_box(scene, "ExtGrassL", (90.0, 140.0, 0.08), (x_min - 68.0, cy, -0.07), horizon_grass_mat(), bevel=0.0, parent=shell)
        for ty in range(int(y_min) + 3, int(y_max), 7):
            tr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "ExtTreeL_%d" % ty, loc=(x_min - 4.2, float(ty), 0.0), outline_thickness=0.004)
            tr.scale = (1.8, 1.8, 1.8)
            tr.parent = shell
    else:
        # Glass curtain wall on x_max (e.g., Shot 3), solid wall far behind camera at x_min
        make_box(scene, "FarSideWall", (0.25, l_span, ceil_z), (x_min, cy, ceil_z * 0.5), wall_m, bevel=0.0, parent=shell)
        soffit = make_box(scene, "GlassSoffitR", (0.32, l_span, ceil_z - 2.45), (x_max, cy, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        soffit.visible_shadow = False
        for py in range(int(y_min), int(y_max) + 1, 4):
            make_box(scene, "MullionColR_%d" % py, (0.34, 0.34, ceil_z), (x_max, float(py), ceil_z * 0.5), trim_m, bevel=0.02, parent=shell)
        make_box(scene, "ExtApronR", (45.0, 90.0, 0.10), (x_max + 23.0, cy, -0.06), toon_rgb_mat("ext_apron", (0.34, 0.37, 0.42)), bevel=0.0, parent=shell)
        make_box(scene, "ExtGrassR", (90.0, 140.0, 0.08), (x_max + 68.0, cy, -0.07), horizon_grass_mat(), bevel=0.0, parent=shell)
        for ty in range(int(y_min) + 3, int(y_max), 7):
            tr, _, _, _ = load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "ExtTreeR_%d" % ty, loc=(x_max + 4.2, float(ty), 0.0), outline_thickness=0.004)
            tr.scale = (1.8, 1.8, 1.8)
            tr.parent = shell

    # 5. North / Front Wall soffit above y_max
    if open_north_wall:
        # Upper soffit frieze above the 2.5m airside glass wall at y_max
        n_soffit = make_box(scene, "NorthGlassSoffit", (w_span, 0.32, ceil_z - 2.45), (cx, y_max, 2.45 + (ceil_z - 2.45) * 0.5), wall_m, bevel=0.02, parent=shell)
        n_soffit.visible_shadow = False
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

    rebind_materials(new_objs, label, outline_thickness=outline_thickness)
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


def set_nla_clips(arm, acts, segments):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for idx, (clip_name, f0, f1, speed) in enumerate(segments):
        act = acts.get(clip_name)
        if act is None:
            matches = [v for k, v in acts.items() if k.startswith(clip_name)]
            if not matches:
                fail("missing clip %r in %s" % (clip_name, sorted(acts.keys())))
            act = matches[0]
        trk = ad.nla_tracks.new()
        trk.name = "trk_%d_%s" % (idx, clip_name)
        strip = trk.strips.new(clip_name, int(f0), act)
        if hasattr(strip, "action_slot") and len(act.slots):
            strip.action_slot = act.slots[0]
        strip.scale = (25.0 / FPS) / max(0.15, float(speed))
        act_len = max(1.0, (act.frame_range[1] - act.frame_range[0]) * strip.scale)
        needed = max(1.0, float(f1 - f0 + 1))
        strip.repeat = max(1.0, math.ceil(needed / act_len) + 1.0)
        strip.frame_end = float(f1)
        strip.extrapolation = "NOTHING" if len(segments) > 1 else "HOLD"
        if idx > 0:
            strip.blend_in = 4.0
            strip.blend_type = "REPLACE"


def add_pose_override_track(arm, name, bone_keyframes, blend_type="ADD"):
    act = bpy.data.actions.new("ACT_" + name)
    ad = arm.animation_data or arm.animation_data_create()
    prev_action = ad.action
    ad.action = act
    for bname, keys in bone_keyframes.items():
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        pb.rotation_mode = "XYZ"
        for frame, (rx, ry, rz) in keys:
            pb.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
    slot = ad.action_slot if hasattr(ad, "action_slot") else None
    ad.action = prev_action
    trk = ad.nla_tracks.new()
    trk.name = "pose_" + name
    all_f = [f for keys in bone_keyframes.values() for f, _ in keys]
    strip = trk.strips.new(name, min(all_f), act)
    if slot is not None and hasattr(strip, "action_slot"):
        strip.action_slot = slot
    elif hasattr(strip, "action_slot") and len(act.slots):
        strip.action_slot = act.slots[0]
    strip.blend_type = blend_type
    strip.extrapolation = "NOTHING"
    return strip


def bind_hand_ik_to_roller(arm, pull_top_obj, active_ranges, hand="R"):
    """Attach a 2-bone IK constraint on `Forearm.<hand>` targeting `pull_top_obj` so the
    character's wrist/palm locks directly onto the roller suitcase grip bar (0.00 m gap!).
    `active_ranges`: list of (f_start, f_end) where IK influence = 1.0 (0.0 outside)."""
    pb = arm.pose.bones.get("Forearm." + hand)
    if pb is None:
        fail("bind_hand_ik_to_roller: bone Forearm.%s not found on %s" % (hand, arm.name))
    ik = pb.constraints.new("IK")
    ik.name = "GripRollerIK_" + hand
    ik.target = pull_top_obj
    ik.chain_count = 2
    if len(active_ranges) == 1 and active_ranges[0][0] <= 1:
        ik.influence = 1.0
        ik.keyframe_insert(data_path="influence", frame=1)
        ik.keyframe_insert(data_path="influence", frame=active_ranges[0][1])
        if active_ranges[0][1] < bpy.context.scene.frame_end:
            ik.influence = 0.0
            ik.keyframe_insert(data_path="influence", frame=active_ranges[0][1] + 4)
        return ik

    ik.influence = 0.0
    ik.keyframe_insert(data_path="influence", frame=1)
    for f0, f1 in active_ranges:
        if f0 > 2:
            ik.influence = 0.0
            ik.keyframe_insert(data_path="influence", frame=max(1, f0 - 3))
        ik.influence = 1.0
        ik.keyframe_insert(data_path="influence", frame=f0)
        ik.keyframe_insert(data_path="influence", frame=f1)
        if f1 < bpy.context.scene.frame_end:
            ik.influence = 0.0
            ik.keyframe_insert(data_path="influence", frame=f1 + 3)
    return ik


def load_roller_bag(label, extended=True, loc=(0.0, 0.0, 0.0), yaw_deg=0.0, bag_tint=None, parent=None):
    root, objs, by_n, _ = load_glb("game/assets/interior/carry_roller.glb", label, loc=loc, yaw_deg=yaw_deg)
    if bag_tint is not None and "CarryRoller_Body" in by_n:
        mat = toon_rgb_mat("bag_" + label, bag_tint)
        by_n["CarryRoller_Body"].data.materials[0] = mat
        attach_outline(by_n["CarryRoller_Body"], 0.005)
    set_roller_handle(by_n, extended=extended)
    if parent is not None:
        root.parent = parent
    return root, objs, by_n


def set_roller_handle(by_n, extended=True, frame=None):
    reach = by_n.get("Pull_Reach")
    top = by_n.get("Pull_Top")
    if reach is None or top is None:
        return
    if extended:
        # Stretch rod 37x (0.74 m -> 0.96 m from case centre) so Pull_Top sits at natural hand height!
        reach.scale = (1.0, 37.0, 1.0)
        top.location = (0.0, -0.22 - 0.74, 0.03)
    else:
        reach.scale = (1.0, 1.0, 1.0)
        top.location = (0.0, -0.24, 0.03)
    if frame is not None:
        reach.keyframe_insert(data_path="scale", frame=frame)
        top.keyframe_insert(data_path="location", frame=frame)


# ---------------------------------------------------------------- Elastic Snap-In Animation


def animate_snap_pop(obj, trigger_frame, drop_height=1.35, settle_frames=13):
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
    """Cast a ray from `cam` toward `target_pt`, stepping past transparent glass/vapor
    surfaces or hidden/tiny-scaled objects, and return (ok, blocker_name)."""
    dg = bpy.context.evaluated_depsgraph_get()
    origin = cam.matrix_world.translation.copy()
    goal = Vector(target_pt)
    for _ in range(8):
        vec = goal - origin
        dist = vec.length
        if dist < 0.05:
            return True, None
        direction = vec / dist
        hit, loc, _nrm, _idx, ob, _mw = scene.ray_cast(dg, origin, direction, distance=dist - 0.04)
        if not hit or ob is None:
            return True, None
        orig_ob = ob.original if hasattr(ob, "original") and ob.original is not None else ob
        if orig_ob.name in own_names:
            return True, None
        # Step past transparent glass, vapor ribbons, or scaled-zero snap-hidden meshes
        mnames = [m.name for m in getattr(orig_ob.data, "materials", []) if m]
        wscale = ob.matrix_world.to_scale()
        is_transp = orig_ob.hide_render or min(abs(wscale.x), abs(wscale.y), abs(wscale.z)) < 0.02 or any(
            ("Glass" in mn or "SOFT_VAPOR" in mn) for mn in mnames
        )
        if is_transp:
            origin = loc + direction * 0.03
            continue
        # If hit is within 0.38m of target_pt (e.g. character's own hand/collar/prop), count as clear
        if (loc - goal).length < 0.38:
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
        # Include any child props (e.g. parented roller bag) under the same root
        roots = {o.parent for o in objs if o.parent is not None}
        for o in scene.objects:
            if o.parent in roots or (o.parent and o.parent.parent in roots):
                own_names.add(o.name)
        chest_pt = (float(center[0]), float(center[1]), float(lo[2] + 0.62 * span[2]))
        head_pt = (float(center[0]), float(center[1]), float(lo[2] + 0.84 * span[2]))
        ok_c, b_c = _ray_hits_subject_unoccluded(scene, cam, chest_pt, own_names)
        ok_h, b_h = _ray_hits_subject_unoccluded(scene, cam, head_pt, own_names)
        occ_ok = ok_c or ok_h
        blocker = b_h or b_c

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
