"""Six pre-rendered 3D CG story shots for the Gotta Make My Flight AAA teaser trailer (v2 AAA polish).

Timeline (30 fps, 1185 frames = 39.50 seconds total, zero gameplay HUD/UI):
  Shot 1 (f   1..165, 5.50s): Curb Drop-off & Ticking Board ('GOTTA AIR 101 · FINAL CALL!')
  Shot 2 (f 166..390, 7.50s): Enclosed Terminal Snapping Into Place + Boarding Pass Handoff
  Shot 3 (f 391..615, 7.50s): Security Scanner Tray Comedy + Emerald Arch Flash
  Shot 4 (f 616..810, 6.50s): Bustling Gate Concourse Sprint + Gotta Air Jet Outside Glass
  Shot 5 (f 811..1020, 7.00s): Apron Dash, Airstairs Boarding & Sleek Gotta Air Jet Takeoff
  Shot 6 (f 1021..1185, 5.50s): Golden Cloud Climb + Option A Logo Slam & 'WISHLIST ON STEAM'
"""

import math
import bpy
from mathutils import Matrix, Vector

import toon_kit as tk

SHOT_SPECS = [
    {"id": "shot_01", "title": "Curb Drop-off & Ticking Board", "frames": 165},
    {"id": "shot_02", "title": "Terminal Snapping Into Place", "frames": 225},
    {"id": "shot_03", "title": "Security Scanner Tray Comedy", "frames": 225},
    {"id": "shot_04", "title": "Gate Sprint Through Bustling Terminal", "frames": 195},
    {"id": "shot_05", "title": "Apron Dash & Gotta Air Takeoff", "frames": 210},
    {"id": "shot_06", "title": "Title Slam & Wishlist Callout", "frames": 165},
]


def _apply_gotta_air_livery(plane_objs):
    """Apply seamless shader-level Gotta Air Lime (#65B70F) & Dark Green (#306003) livery
    to TP_Atlas_1A_D slots on fixed-wing aircraft."""
    gmat = tk.gotta_air_plane_mat()
    tp_base = tk.toon_atlas_mat("tp_atlas_1a_d.png")
    for o in plane_objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            if slot.material == tp_base:
                slot.material = gmat


def _spin_jet_fans(scene, plane_root, plane_by_name, f_end, deg_per_frame=48.0):
    """Spin TP_Plane_05A_Fan.L and Fan.R around their world Y (forward-aft) turbofan axis."""
    bpy.context.view_layer.update()
    for side, sign in (("L", 1.0), ("R", -1.0)):
        fan = plane_by_name.get("TP_Plane_05A_Fan." + side)
        if fan is None:
            continue
        mw = fan.matrix_world.copy()
        piv = bpy.data.objects.new("FanSpinPivot_" + side, None)
        scene.collection.objects.link(piv)
        piv.parent = plane_root
        piv.matrix_world = Matrix.Translation(mw.translation)
        bpy.context.view_layer.update()
        fan.parent = piv
        fan.matrix_world = mw
        piv.rotation_mode = "XYZ"
        piv.rotation_euler = (0.0, 0.0, 0.0)
        piv.keyframe_insert(data_path="rotation_euler", frame=1)
        piv.rotation_euler = (0.0, math.radians(sign * deg_per_frame * f_end), 0.0)
        piv.keyframe_insert(data_path="rotation_euler", frame=f_end)


def _attach_towed_roller(hero_root, hero_arm, label, f_tow_ranges, stand_ranges=None):
    """Parent yellow CarryRoller directly to `hero_root` so Hero's posed right hand (`Arm.R`)
    visibly grips `Pull_Top` while running, and stands it neatly beside him when paused!"""
    for f0, f1 in f_tow_ranges:
        tk.pose_arm_towing_roller(hero_arm, f0, f1, hand="R")

    # In hero_root local space: -Y is forward, -X is Right hand (`x=-0.24`), +Y is behind heels
    bag_root, _, bag_by_n = tk.load_roller_bag(
        label,
        extended=True,
        loc=(-0.24, 0.44, 0.18),
        yaw_deg=0.0,
        bag_tint=tk.YELLOW,
        parent=hero_root,
    )
    bag_root.rotation_mode = "XYZ"
    bag_root.rotation_euler = (math.radians(-42.0), 0.0, 0.0)

    if stand_ranges:
        pos_keys = []
        rot_keys = []
        for f0, f1, mode in stand_ranges:
            if mode == "stand":
                pos_keys.extend([(f0, (-0.34, 0.08, 0.22)), (f1, (-0.34, 0.08, 0.22))])
                rot_keys.extend([(f0, (-86.0, 0.0, 0.0)), (f1, (-86.0, 0.0, 0.0))])
            else:
                pos_keys.extend([(f0, (-0.24, 0.44, 0.18)), (f1, (-0.24, 0.44, 0.18))])
                rot_keys.extend([(f0, (-42.0, 0.0, 0.0)), (f1, (-42.0, 0.0, 0.0))])
        tk.key_pos(bag_root, pos_keys)
        tk.key_rot_deg(bag_root, rot_keys)
    return bag_root, bag_by_n


def _build_departure_board(scene, loc, flip_frame):
    root = bpy.data.objects.new("DepartureBoard_ROOT", None)
    root.location = loc
    scene.collection.objects.link(root)

    navy_m = tk.toon_rgb_mat("board_housing", tk.NAVY)
    deep_m = tk.emissive_mat("board_screen", (0.05, 0.07, 0.14), strength=1.0)
    lime_m = tk.emissive_mat("board_lime", tk.GOTTA_LIME, strength=1.25)
    cream_m = tk.emissive_mat("board_cream", tk.CREAM, strength=1.20)
    amber_m = tk.emissive_mat("board_amber", tk.AMBER, strength=1.35)
    coral_m = tk.emissive_mat("board_coral", tk.ALERT_CORAL, strength=1.65)

    tk.make_box(scene, "Board_Case", (4.60, 0.28, 1.48), (0.0, 0.0, 0.0), navy_m, bevel=0.05, parent=root, outline=0.006)
    tk.make_box(scene, "Board_HeaderBar", (4.42, 0.06, 0.22), (0.0, -0.13, 0.52), lime_m, bevel=0.02, parent=root)
    tk.make_box(scene, "Board_Screen", (4.42, 0.04, 1.08), (0.0, -0.13, -0.10), deep_m, bevel=0.02, parent=root)

    t_top = tk.make_nunito_text_3d(scene, "GOTTA AIR 101 · OSLO", 0.31, 0.014, cream_m, extrude=0.02, parent=root)
    t_top.rotation_euler = (math.radians(90), 0.0, 0.0)
    t_top.location = (0.0, -0.165, 0.16)

    flap_boarding = tk.make_nunito_text_3d(scene, "GATE C · BOARDING", 0.34, 0.016, amber_m, extrude=0.02, parent=root)
    flap_boarding.rotation_euler = (math.radians(90), 0.0, 0.0)
    flap_boarding.location = (0.0, -0.165, -0.34)

    flap_final = tk.make_nunito_text_3d(scene, "FINAL CALL!", 0.42, 0.020, coral_m, extrude=0.025, parent=root)
    flap_final.rotation_euler = (math.radians(90), 0.0, 0.0)
    flap_final.location = (0.0, -0.175, -0.35)

    flap_boarding.scale = (1.0, 1.0, 1.0)
    flap_boarding.keyframe_insert(data_path="scale", frame=1)
    flap_boarding.keyframe_insert(data_path="scale", frame=flip_frame - 2)
    flap_boarding.scale = (0.0001, 0.0001, 0.0001)
    flap_boarding.keyframe_insert(data_path="scale", frame=flip_frame)

    flap_final.scale = (0.0001, 0.0001, 0.0001)
    flap_final.keyframe_insert(data_path="scale", frame=1)
    flap_final.keyframe_insert(data_path="scale", frame=flip_frame - 1)
    flap_final.scale = (1.18, 1.18, 1.18)
    flap_final.keyframe_insert(data_path="scale", frame=flip_frame + 3)
    flap_final.scale = (0.96, 0.96, 0.96)
    flap_final.keyframe_insert(data_path="scale", frame=flip_frame + 6)
    flap_final.scale = (1.0, 1.0, 1.0)
    flap_final.keyframe_insert(data_path="scale", frame=flip_frame + 9)
    for pf in range(flip_frame + 18, flip_frame + 75, 16):
        flap_final.scale = (1.06, 1.06, 1.06)
        flap_final.keyframe_insert(data_path="scale", frame=pf)
        flap_final.scale = (1.0, 1.0, 1.0)
        flap_final.keyframe_insert(data_path="scale", frame=pf + 8)

    return root


# ==============================================================================
# SHOT 1 (165 frames = 5.5s): Curb Drop-off & Ticking Board
# ==============================================================================


def build_shot_01(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.12, indoor=False)
    tk.make_box(scene, "LandsideSubRoad", (220.0, 220.0, 0.12), (0.0, 0.0, 0.03), tk.toon_rgb_mat("road_sub", (0.25, 0.27, 0.32)), bevel=0.0)

    # TP_Airport_01A_Road top surface measured by raycast at z = +0.10m; sidewalk sill at z = +0.20m!
    ROAD_Z = 0.105
    CURB_Z = 0.20

    _, _, ap_by_n, _ = tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "AirportExt", loc=(0.0, 0.0, 0.0), outline_thickness=0.003)
    tk.load_glb("game/assets/landside/tp_curb_bay_01a.glb", "CurbBay", loc=(15.5, -19.6, 0.11), outline_thickness=0.003)

    # Rich curbside streetscape: planters, outdoor trees, bench, trash can, glowing streetlamps & traffic!
    tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantL", loc=(12.2, -18.3, CURB_Z), outline_thickness=0.004)
    tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantR", loc=(20.6, -18.3, CURB_Z), outline_thickness=0.004)
    tr1, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeL", loc=(6.5, -18.5, CURB_Z), outline_thickness=0.004)
    tr1.scale = (1.65, 1.65, 1.65)
    tr2, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeR", loc=(23.2, -18.5, CURB_Z), outline_thickness=0.004)
    tr2.scale = (1.65, 1.65, 1.65)
    tk.load_glb("game/assets/decor/tc_bench_1a.glb", "CurbBench", loc=(22.0, -18.3, CURB_Z), yaw_deg=0.0, outline_thickness=0.004)
    tk.load_glb("game/assets/decor/tc_trash_can_1a.glb", "CurbBin", loc=(19.1, -18.3, CURB_Z), outline_thickness=0.004)

    # Warm glowing curbside streetlamps
    pole_m = tk.toon_rgb_mat("lamp_pole", (0.22, 0.25, 0.32))
    bulb_m = tk.emissive_mat("lamp_bulb", (1.0, 0.92, 0.72), strength=1.8)
    for lx in (9.2, 21.8):
        tk.make_box(scene, "LampPole_%d" % int(lx), (0.12, 0.12, 3.8), (lx, -20.2, CURB_Z + 1.9), pole_m, bevel=0.02)
        tk.make_box(scene, "LampHead_%d" % int(lx), (0.48, 0.28, 0.16), (lx, -20.45, CURB_Z + 3.82), bulb_m, bevel=0.03)

    # Second SUV pulling away ahead down the curb lane (never crosses between Shot01Cam and Hero!)
    cruiser, _, _, _ = tk.load_glb("game/assets/vehicles/tp_suv_01b.glb", "DepartingSUV", loc=(21.5, -22.1, ROAD_Z), yaw_deg=90.0, outline_thickness=0.003)
    tk.key_pos(cruiser, [(1, (20.8, -22.1, ROAD_Z)), (N, (29.5, -22.1, ROAD_Z))])

    # Bustling curbside travelers strolling cleanly along the front sidewalk (clear of planters!)
    bg1_r, bg1_a, _, bg1_acts = tk.load_character("tcp_female_character_03", "CurbPax1", cloth_tint=(0.28, 0.65, 0.78), loc=(22.2, -20.1, CURB_Z), yaw_deg=-90.0)
    tk.set_nla_clips(bg1_a, bg1_acts, [("walk", 1, N, 1.0)])
    tk.key_pos(bg1_r, [(1, (22.4, -20.1, CURB_Z)), (N, (18.2, -20.1, CURB_Z))])

    bg2_r, bg2_a, _, bg2_acts = tk.load_character("tcp_male_character_08", "CurbPax2", cloth_tint=(0.45, 0.58, 0.32), loc=(9.2, -19.8, CURB_Z), yaw_deg=90.0)
    tk.set_nla_clips(bg2_a, bg2_acts, [("walk", 1, N, 0.95)])
    tk.key_pos(bg2_r, [(1, (8.2, -19.8, CURB_Z)), (N, (11.6, -19.8, CURB_Z))])

    flip_f = 58
    board_root = _build_departure_board(scene, (16.15, -19.95, 3.22), flip_frame=flip_f)
    board_root.scale = (0.76, 0.76, 0.76)

    door6 = ap_by_n.get("TP_Airport_01A_Door_6")
    if door6 is not None:
        dloc = Vector(door6.location)
        tk.key_pos(door6, [(1, dloc), (92, dloc), (118, dloc + Vector((1.55, 0.0, 0.0))), (N, dloc + Vector((1.55, 0.0, 0.0)))])

    # Yellow Hero Taxi riding flush ON the z=0.105 asphalt road!
    taxi_root, _, taxi_by_n, _ = tk.load_glb("game/assets/vehicles/tp_taxi_01a.glb", "HeroTaxi", loc=(7.2, -22.1, ROAD_Z), yaw_deg=90.0, outline_thickness=0.003)
    tk.key_pos(taxi_root, [
        (1, (7.2, -22.1, ROAD_Z)),
        (26, (12.4, -22.1, ROAD_Z)),
        (32, (12.75, -22.1, ROAD_Z)),
        (N, (12.75, -22.1, ROAD_Z)),
    ])
    tk.key_rot_deg(taxi_root, [
        (1, (0.0, 0.0, 90.0)),
        (22, (0.0, 0.0, 90.0)),
        (28, (2.6, 0.0, 90.0)),
        (36, (0.0, 0.0, 90.0)),
    ])
    for wname in ("TP_Taxi_01A_Wheel_F.L", "TP_Taxi_01A_Wheel_F.R", "TP_Taxi_01A_Wheel_R.L", "TP_Taxi_01A_Wheel_R.R"):
        w = taxi_by_n.get(wname)
        if w is not None:
            tk.key_rot_deg(w, [(1, (0.0, 0.0, 0.0)), (30, (-540.0, 0.0, 0.0)), (N, (-540.0, 0.0, 0.0))])
    rdoor = taxi_by_n.get("TP_Taxi_01A_Door_R.L")
    if rdoor is not None:
        tk.key_rot_deg(rdoor, [(1, (0.0, 0.0, 0.0)), (27, (0.0, 0.0, 0.0)), (37, (0.0, 0.0, -62.0)), (98, (0.0, 0.0, -62.0)), (112, (0.0, 0.0, 0.0))])

    # Hero passenger + attached gripped yellow roller suitcase!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(8.8, -21.4, ROAD_Z), yaw_deg=90.0
    )
    tk.set_nla_clips(hero_arm, hero_acts, [
        ("run", 1, 46, 1.15),
        ("idle", 47, 96, 1.0),
        ("run", 97, N, 1.35),
    ])
    tk.add_pose_override_track(hero_arm, "BoardShock", {
        "Head": [(46, (0, 0, 0)), (58, (-28, 0, 0)), (88, (-26, 0, 0)), (100, (0, 0, 0))],
        "Spine_02": [(46, (0, 0, 0)), (60, (-12, 0, 0)), (88, (-10, 0, 0)), (100, (0, 0, 0))],
    })
    _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller01",
        f_tow_ranges=[(98, N)],
        stand_ranges=[(1, 42, "tow"), (46, 96, "stand"), (102, N, "tow")],
    )
    tk.key_pos(hero_root, [
        (1, (8.8, -21.4, ROAD_Z)),
        (26, (13.4, -21.3, ROAD_Z)),
        (36, (15.35, -20.45, CURB_Z)),
        (46, (15.65, -20.15, CURB_Z)),
        (96, (15.65, -20.15, CURB_Z)),
        (N, (16.00, -17.35, CURB_Z)),
    ])
    tk.key_rot_deg(hero_root, [
        (1, (0.0, 0.0, 90.0)),
        (34, (0.0, 0.0, 45.0)),
        (48, (0.0, 0.0, 175.0)),
        (96, (0.0, 0.0, 178.0)),
        (N, (0.0, 0.0, 180.0)),
    ])

    cam, target = tk.make_camera(scene, "Shot01Cam", lens=34.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (11.2, -28.8, 1.72)),
        (44, (16.8, -28.0, 1.75)),
        (100, (16.7, -27.4, 1.75)),
        (N, (16.5, -26.4, 1.78)),
    ])
    tk.key_pos(target, [
        (1, (9.2, -21.4, 1.22)),
        (44, (15.75, -19.8, 1.62)),
        (96, (15.80, -19.6, 1.66)),
        (N, (16.00, -18.2, 1.62)),
    ])

    events = [
        {"type": "car_arrive", "frame": g0 + 1, "dur": 28},
        {"type": "car_brake", "frame": g0 + 24},
        {"type": "car_door", "frame": g0 + 30},
        {"type": "board_flip", "frame": g0 + flip_f - 3, "count": 9},
        {"type": "startle_sting", "frame": g0 + flip_f + 2},
        {"type": "door_whoosh", "frame": g0 + 98},
        {"type": "roller", "frame": g0 + 100, "dur": 64},
    ]
    for f in range(100, N, 8):
        events.append({"type": "footstep", "frame": g0 + f})

    return scene, cam, hero_objs, hero_arm, events


# ==============================================================================
# SHOT 2 (225 frames = 7.5s): Enclosed Terminal Snapping Into Place
# ==============================================================================


def build_shot_02(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
    # 100% enclosed terminal hall with recessed ceiling LEDs, back/side walls, & outdoor trees!
    tk.build_enclosed_terminal_hall(scene, x_min=-3.8, x_max=8.5, y_min=-13.5, y_max=7.5, ceil_z=3.85, glass_side="left", open_north_wall=False)

    # Background terminal life on the entry concourse behind/beside Hero!
    tk.load_glb("game/assets/interior/wall_door.glb", "EntryDoorBack", loc=(0.0, -13.4, 0.0), yaw_deg=0.0)
    tk.load_glb("game/assets/interior/info_screen.glb", "BackScreen", loc=(2.4, -13.1, 0.0), yaw_deg=0.0)
    tk.load_glb("game/assets/interior/kiosk.glb", "BackKiosk", loc=(2.6, -8.5, 0.0), yaw_deg=-90.0)

    cln_r, cln_a, _, cln_acts = tk.load_character("tcp_female_character_10", "HallCleaner", cloth_tint=None, loc=(-2.4, -9.2, 0.0), yaw_deg=35.0)
    tk.set_nla_clips(cln_a, cln_acts, [("clean", 1, N, 1.0)])
    bg1_r, bg1_a, _, bg1_acts = tk.load_character("tcp_female_character_05", "HallPax1", cloth_tint=(0.42, 0.62, 0.88), loc=(2.1, -9.5, 0.0), yaw_deg=180.0)
    tk.set_nla_clips(bg1_a, bg1_acts, [("walk", 1, N, 1.0)])
    tk.key_pos(bg1_r, [(1, (2.1, -10.8, 0.0)), (N, (2.1, -4.2, 0.0))])
    bg2_r, bg2_a, _, bg2_acts = tk.load_character("tcp_male_character_02", "HallPax2", cloth_tint=(0.78, 0.56, 0.24), loc=(-1.6, -11.5, 0.0), yaw_deg=170.0)
    tk.set_nla_clips(bg2_a, bg2_acts, [("walk", 1, N, 0.95)])
    tk.key_pos(bg2_r, [(1, (-1.6, -12.0, 0.0)), (N, (-1.4, -5.8, 0.0))])

    events = []
    pop_idx = 0

    def snap(obj, trig_f, drop=1.45):
        nonlocal pop_idx
        tk.animate_snap_pop(obj, trig_f, drop_height=drop)
        if trig_f > 1:
            events.append({"type": "pop", "frame": g0 + trig_f + 3, "pitch": pop_idx})
            pop_idx += 1

    # Central concourse tile strips (z=+0.015) ripple-snapping into place right ahead of Hero's feet!
    for row_i, gy in enumerate(range(-4, 6)):
        row_holder = bpy.data.objects.new("FloorRow_%d" % row_i, None)
        row_holder.location = (0.0, float(gy), 0.015)
        scene.collection.objects.link(row_holder)
        for gx in (-3, -2, -1, 0, 1, 2, 3):
            r, _, _, _ = tk.load_glb("game/assets/interior/floor_tile.glb", "FT_%d_%d" % (gx, gy), loc=(float(gx), 0.0, 0.0), outline_thickness=0.0)
            r.parent = row_holder
        snap(row_holder, 4 + (gy + 4) * 9, drop=0.85)

    # Sunlit glass curtain wall panels along x = -3.8 snapping in ahead!
    for wi, wy in enumerate(range(-12, 8, 2)):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "WG_%d" % wi, loc=(-3.75, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)
        if wy >= -2:
            snap(wg, 10 + (wy + 2) * 5, drop=1.7)

    p1, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SnapPlant1", loc=(-2.3, -1.8, 0.0))
    snap(p1, 24, drop=1.5)
    p2, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_2a.glb", "SnapPlant2", loc=(-2.3, 1.2, 0.0))
    snap(p2, 44, drop=1.5)
    st1, _, _, _ = tk.load_glb("game/assets/interior/screen_stand.glb", "SnapStand1", loc=(-1.75, 2.8, 0.0), yaw_deg=25.0)
    snap(st1, 58, drop=1.4)
    st2, _, _, _ = tk.load_glb("game/assets/decor/tc_bench_2a_indoor.glb", "SnapBench", loc=(-2.55, -4.6, 0.0), yaw_deg=90.0)
    snap(st2, 16, drop=1.3)

    # Staffed Check-In Desk + Second Adjacent Desk + Info Screen + Gotta Air Clerk snapping in!
    desk_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk", loc=(0.0, 4.4, 0.0), yaw_deg=0.0)
    snap(desk_root, 76, drop=1.7)
    desk2_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk2", loc=(2.6, 5.4, 0.0), yaw_deg=0.0)
    snap(desk2_root, 88, drop=1.7)
    scr_root, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "CheckinInfo", loc=(-2.1, 4.8, 0.0), yaw_deg=20.0)
    snap(scr_root, 84, drop=1.6)

    clerk_root, clerk_arm, _, clerk_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk", cloth_tint=tk.GOTTA_LIME, loc=(0.0, 5.15, 0.0), yaw_deg=0.0
    )
    tk.set_nla_clips(clerk_arm, clerk_acts, [("idle", 1, N, 1.15)])
    tk.add_pose_override_track(clerk_arm, "ClerkStamp", {
        "Arm.R": [(120, (0, 0, 0)), (138, (48, 0, -15)), (152, (62, 0, 10)), (172, (0, 0, 0))],
    })
    snap(clerk_root, 82, drop=1.5)

    clerk2_root, clerk2_arm, _, clerk2_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk2", cloth_tint=tk.CLERK_NAVY, loc=(2.6, 6.15, 0.0), yaw_deg=0.0
    )
    tk.set_nla_clips(clerk2_arm, clerk2_acts, [("idle", 1, N, 1.05)])
    snap(clerk2_root, 92, drop=1.5)

    # Crisp 3D Boarding Pass card popping onto counter & into Hero's hand!
    pass_holder = bpy.data.objects.new("BoardingPass", None)
    scene.collection.objects.link(pass_holder)
    tk.make_box(scene, "PassCard", (0.34, 0.18, 0.015), (0.0, 0.0, 0.0), tk.emissive_mat("pass_cream", tk.CREAM, 1.3), bevel=0.004, parent=pass_holder, outline=0.003)
    tk.make_box(scene, "PassStripe", (0.34, 0.05, 0.018), (0.0, -0.05, 0.002), tk.emissive_mat("pass_lime", tk.GOTTA_LIME, 1.4), bevel=0.002, parent=pass_holder)
    pass_holder.scale = (0.0001, 0.0001, 0.0001)
    pass_holder.keyframe_insert(data_path="scale", frame=1)
    pass_holder.keyframe_insert(data_path="scale", frame=140)
    pass_holder.scale = (1.35, 1.35, 1.35)
    pass_holder.keyframe_insert(data_path="scale", frame=146)
    pass_holder.scale = (1.0, 1.0, 1.0)
    pass_holder.keyframe_insert(data_path="scale", frame=152)
    pass_holder.scale = (0.0001, 0.0001, 0.0001)
    pass_holder.keyframe_insert(data_path="scale", frame=175)
    tk.key_pos(pass_holder, [
        (140, (0.0, 4.35, 1.16)),
        (152, (0.0, 3.85, 1.24)),
        (170, (0.15, 3.45, 1.18)),
    ])
    events.append({"type": "stamp_ding", "frame": g0 + 146})

    # Hero passenger with gripped towed roller suitcase!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.0, -7.2, 0.0), yaw_deg=180.0
    )
    tk.set_nla_clips(hero_arm, hero_acts, [
        ("run", 1, 126, 1.32),
        ("idle", 127, 170, 1.25),
        ("run", 171, N, 1.38),
    ])
    _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller02",
        f_tow_ranges=[(1, 125), (171, N)],
        stand_ranges=[(1, 122, "tow"), (127, 169, "stand"), (174, N, "tow")],
    )
    tk.key_pos(hero_root, [
        (1, (0.0, -7.2, 0.0)),
        (124, (0.0, 3.15, 0.0)),
        (170, (0.0, 3.15, 0.0)),
        (N, (3.25, 3.35, 0.0)),
    ])
    tk.key_rot_deg(hero_root, [
        (1, (0.0, 0.0, 180.0)),
        (166, (0.0, 0.0, 180.0)),
        (180, (0.0, 0.0, 90.0)),
        (N, (0.0, 0.0, 90.0)),
    ])

    cam, target = tk.make_camera(scene, "Shot02Cam", lens=34.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.65, -2.4, 1.78)),
        (110, (4.35, 1.4, 1.74)),
        (145, (4.45, 2.0, 1.66)),
        (175, (4.45, 2.0, 1.66)),
        (N, (6.45, -0.4, 1.72)),
    ])
    tk.key_pos(target, [
        (1, (-0.1, -6.6, 1.05)),
        (110, (0.0, 2.5, 1.08)),
        (145, (0.0, 3.65, 1.12)),
        (175, (0.15, 3.55, 1.12)),
        (N, (2.85, 3.35, 1.08)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": 124})
    events.append({"type": "roller", "frame": g0 + 172, "dur": 52})
    for f in list(range(4, 122, 8)) + list(range(174, N, 8)):
        events.append({"type": "footstep", "frame": g0 + f})

    return scene, cam, hero_objs, hero_arm, events


# ==============================================================================
# SHOT 3 (225 frames = 7.5s): Security Scanner Tray Comedy (Zero Float, Zero Clip!)
# ==============================================================================


def build_shot_03(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
    tk.build_enclosed_terminal_hall(scene, x_min=-7.5, x_max=3.8, y_min=-11.0, y_max=9.5, ceil_z=3.85, glass_side="right", open_north_wall=False)

    for wy in range(-10, 9, 2):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SWG_%d" % wy, loc=(3.75, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)
    tk.load_glb("game/assets/interior/wall_door.glb", "SWExitDoor", loc=(-0.6, 9.4, 0.0), yaw_deg=0.0)
    tk.load_glb("game/assets/interior/info_screen.glb", "SWScreen", loc=(1.6, 9.2, 0.0), yaw_deg=0.0)
    tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SWPlant", loc=(2.6, 5.2, 0.0))

    events = []
    # Security lane snapping in: Belt at x = -0.45, Arch at x = +0.75, Primary & Helper Officers at x = +1.85!
    tt_root, _, _, _ = tk.load_glb("game/assets/interior/tray_table.glb", "TrayTable", loc=(-0.45, -1.05, 0.0))
    xb_root, _, _, _ = tk.load_glb("game/assets/interior/xray_belt.glb", "XrayBelt", loc=(-0.45, 0.0, 0.0))
    pt_root, _, _, _ = tk.load_glb("game/assets/interior/pickup_table.glb", "PickupTable", loc=(-0.45, 1.05, 0.0))
    arch_root, _, _, _ = tk.load_glb("game/assets/interior/security_arch.glb", "SecArch", loc=(0.75, 0.0, 0.0))

    # Emerald-green arch beacon PARENTED to arch_root AND hidden (scale 0.0001) until f=96!
    # Zero floating green rectangle before arch drops in!
    beacon = tk.make_box(
        scene,
        "ArchGreenBeacon",
        (0.76, 0.22, 0.14),
        (0.0, 0.0, 2.46),
        tk.emissive_mat("scan_green", tk.SCAN_GREEN, 2.4),
        bevel=0.02,
        parent=arch_root,
        outline=0.004,
    )
    beacon.scale = (0.0001, 0.0001, 0.0001)
    beacon.keyframe_insert(data_path="scale", frame=1)
    beacon.keyframe_insert(data_path="scale", frame=95)
    beacon.scale = (1.28, 1.28, 1.45)
    beacon.keyframe_insert(data_path="scale", frame=100)
    beacon.scale = (1.05, 1.05, 1.10)
    beacon.keyframe_insert(data_path="scale", frame=125)

    g_light_d = bpy.data.lights.new("ArchGreenFlash", "POINT")
    g_light_d.color = tk.srgb_to_lin(tk.SCAN_GREEN)
    g_light_d.shadow_soft_size = 0.5
    g_light = bpy.data.objects.new("ArchGreenFlash", g_light_d)
    g_light.location = (0.0, -0.25, 2.15)
    g_light.parent = arch_root
    scene.collection.objects.link(g_light)
    for f, en in [(1, 0.0), (94, 0.0), (100, 110.0), (118, 45.0), (138, 5.0)]:
        g_light_d.energy = en
        g_light_d.keyframe_insert(data_path="energy", frame=f)

    off_root, off_arm, _, off_acts = tk.load_character(
        "tcp_male_character_07", "SecOfficer", cloth_tint=tk.OFFICER_BLUE, loc=(1.95, 0.15, 0.0), yaw_deg=-95.0
    )
    tk.set_nla_clips(off_arm, off_acts, [("idle", 1, N, 1.15)])
    tk.add_pose_override_track(off_arm, "OfficerWave", {
        "Arm.L": [(92, (0, 0, 0)), (108, (65, 0, 25)), (135, (0, 0, 0))],
    })

    for idx, (ob, tf) in enumerate([(tt_root, 4), (xb_root, 9), (arch_root, 14), (pt_root, 19), (off_root, 23)]):
        tk.animate_snap_pop(ob, tf, drop_height=1.45)
        events.append({"type": "pop", "frame": g0 + tf + 3, "pitch": idx + 4})

    # Bustling security queue & background travelers!
    q1_root, q1_arm, _, q1_acts = tk.load_character(
        "tcp_female_character_04", "QueuePax1", cloth_tint=(0.24, 0.68, 0.66), loc=(0.85, -2.95, 0.0), yaw_deg=175.0
    )
    tk.set_nla_clips(q1_arm, q1_acts, [("idle", 1, N, 1.2)])
    qpack, _, _, _ = tk.load_glb("game/assets/interior/carry_backpack.glb", "Q1Pack", loc=(0.85, -3.12, 1.28), yaw_deg=0.0)
    qpack.rotation_euler = (math.radians(-90.0), 0.0, math.radians(180.0))

    q2_root, q2_arm, _, q2_acts = tk.load_character(
        "tcp_male_character_06", "QueuePax2", cloth_tint=(0.76, 0.52, 0.22), loc=(0.05, -3.75, 0.0), yaw_deg=185.0
    )
    tk.set_nla_clips(q2_arm, q2_acts, [("idle", 1, N, 1.1)])

    q3_root, q3_arm, _, q3_acts = tk.load_character(
        "tcp_female_character_11", "QueuePax3", cloth_tint=(0.68, 0.34, 0.64), loc=(0.65, -4.65, 0.0), yaw_deg=178.0
    )
    tk.set_nla_clips(q3_arm, q3_acts, [("idle", 1, N, 1.05)])

    bg_w, bg_wa, _, bg_wacts = tk.load_character(
        "tcp_male_character_09", "SecPasserby", cloth_tint=(0.35, 0.55, 0.82), loc=(2.4, 3.0, 0.0), yaw_deg=180.0
    )
    tk.set_nla_clips(bg_wa, bg_wacts, [("walk", 1, N, 1.0)])
    tk.key_pos(bg_w, [(1, (2.4, 2.2, 0.0)), (N, (2.2, 7.6, 0.0))])

    # Tray + Hero Roller zipping through the X-ray tunnel!
    tray_root, _, _, _ = tk.load_glb("game/assets/interior/security_tray.glb", "HeroTray", loc=(-0.45, -1.05, 0.74))
    tk.animate_snap_pop(tray_root, 38, drop_height=0.6)
    tk.key_pos(tray_root, [
        (38, (-0.45, -1.05, 0.74)),
        (56, (-0.45, -1.05, 0.74)),
        (132, (-0.45, 1.05, 0.74)),
        (N, (-0.45, 1.05, 0.74)),
    ])

    bag_root, _, bag_by_n = tk.load_roller_bag("HeroRoller03", extended=True, loc=(0.85, -3.15, 0.18), bag_tint=tk.YELLOW)
    tk.set_roller_handle(bag_by_n, extended=True, frame=1)
    tk.set_roller_handle(bag_by_n, extended=True, frame=42)
    tk.set_roller_handle(bag_by_n, extended=False, frame=48)
    tk.set_roller_handle(bag_by_n, extended=False, frame=144)
    tk.set_roller_handle(bag_by_n, extended=True, frame=152)
    tk.key_pos(bag_root, [
        (1, (0.82, -3.10, 0.18)),
        (38, (0.05, -1.45, 0.18)),
        (48, (-0.45, -1.05, 0.78)),   # Laid flat into security_tray
        (56, (-0.45, -1.05, 0.78)),
        (132, (-0.45, 1.05, 0.78)),   # Exits X-ray onto pickup_table
        (145, (-0.45, 1.05, 0.78)),
        (156, (-0.98, 2.05, 0.18)),   # Snatched onto open floor ~0.70m in front of table!
        (N, (-0.82, 5.10, 0.18)),
    ])
    tk.key_rot_deg(bag_root, [
        (1, (-42.0, 0.0, 180.0)),
        (42, (-42.0, 0.0, 180.0)),
        (48, (0.0, 0.0, 180.0)),
        (145, (0.0, 0.0, 180.0)),
        (156, (-42.0, 0.0, 180.0)),
        (N, (-42.0, 0.0, 180.0)),
    ])

    # Hero passenger: walks through arch at x=+0.75, then curves WIDE around pickup_table
    # (y=1.85, x=-1.18 — 0.73m closer to camera & 0.40m past table end!) so shins NEVER clip!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.60, -2.65, 0.0), yaw_deg=180.0
    )
    tk.set_nla_clips(hero_arm, hero_acts, [
        ("run", 1, 38, 1.30),
        ("idle", 39, 64, 1.35),
        ("walk", 65, 138, 1.75),
        ("idle", 139, 154, 1.40),
        ("run", 155, N, 1.42),
    ])
    tk.pose_arm_towing_roller(hero_arm, 156, N, hand="R")
    tk.key_pos(hero_root, [
        (1, (0.58, -2.65, 0.0)),
        (38, (0.25, -1.25, 0.0)),
        (64, (0.75, -1.00, 0.0)),
        (100, (0.75, 0.0, 0.0)),      # Through Security Arch
        (124, (0.55, 1.72, 0.0)),     # Clears +Y end of pickup_table (y=1.47) BEFORE crossing -X!
        (140, (-1.15, 1.95, 0.0)),    # Steps 0.70m toward camera in front of table, zero shin overlap!
        (154, (-1.15, 2.05, 0.0)),
        (N, (-0.98, 5.50, 0.0)),
    ])
    tk.key_rot_deg(hero_root, [
        (1, (0.0, 0.0, 180.0)),
        (42, (0.0, 0.0, -105.0)),
        (66, (0.0, 0.0, 180.0)),
        (126, (0.0, 0.0, -65.0)),     # Curves around table toward camera
        (142, (0.0, 0.0, 65.0)),      # Reaches back to snatch bag off pickup_table
        (156, (0.0, 0.0, 180.0)),     # Sprints forward +Y with bag gripped in right hand!
        (N, (0.0, 0.0, 180.0)),
    ])

    cam, target = tk.make_camera(scene, "Shot03Cam", lens=34.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (-4.45, -4.85, 1.78)),
        (95, (-4.65, -1.65, 1.75)),
        (150, (-4.75, 0.15, 1.70)),
        (N, (-4.65, 2.35, 1.68)),
    ])
    tk.key_pos(target, [
        (1, (0.35, -2.25, 1.04)),
        (95, (0.20, -0.05, 1.08)),
        (150, (-0.55, 1.65, 1.06)),
        (N, (-0.65, 4.75, 1.08)),
    ])

    events.extend([
        {"type": "skid", "frame": g0 + 34},
        {"type": "conveyor", "frame": g0 + 56, "dur": 76},
        {"type": "scanner_beep", "frame": g0 + 98},
        {"type": "bag_snatch", "frame": g0 + 148},
        {"type": "roller", "frame": g0 + 156, "dur": 68},
    ])
    for f in list(range(2, 36, 8)) + list(range(68, 136, 10)) + list(range(156, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    return scene, cam, hero_objs, hero_arm, events


# ==============================================================================
# SHOT 4 (195 frames = 6.5s): Bustling Gate Concourse + Gotta Air Jet Outside Glass!
# ==============================================================================


def build_shot_04(g0):
    N = 195
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.08, indoor=True)
    # 100% enclosed concourse hall with recessed LED ceiling, back wall, & north airside glass!
    tk.build_enclosed_terminal_hall(scene, x_min=-4.8, x_max=8.5, y_min=-13.5, y_max=5.5, ceil_z=3.85, glass_side="left", open_north_wall=True)

    # Airside glass wall at y = +5.5 + sunlit tarmac & parked Gotta Air Jet visible right outside!
    for gx in (-5, -4, -3, -2, 2, 3, 4, 5, 6, 7):
        tk.load_glb("game/assets/interior/wall_glass.glb", "AirGlass_%d" % gx, loc=(float(gx), 5.5, 0.0), yaw_deg=0.0)
    for wx in range(-12, 6, 2):
        wgl, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SideGlassL_%d" % wx, loc=(-4.75, float(wx), 0.0), yaw_deg=90.0)
        wgl.scale = (2.0, 1.0, 1.0)

    # Sunlit Airside Apron + Parked Gotta Air Fixed-Wing Jet right outside the Gate C boarding doors!
    tk.load_glb("game/assets/airside/tp_runway_02a.glb", "OutsideApron", loc=(0.0, 38.0, -0.02), yaw_deg=0.0, outline_thickness=0.0)
    tk.make_box(scene, "OutsideGrass", (260.0, 180.0, 0.08), (0.0, 120.0, -0.06), tk.horizon_grass_mat(), bevel=0.0)
    ext_plane_r, ext_plane_objs, ext_plane_bn, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "OutsideGottaJet", loc=(1.5, 23.5, 0.0), yaw_deg=-68.0, outline_thickness=0.004
    )
    _apply_gotta_air_livery(ext_plane_objs)
    _spin_jet_fans(scene, ext_plane_r, ext_plane_bn, N, deg_per_frame=32.0)
    tk.load_glb("game/assets/airside/props/pushback_tug.glb", "OutsideTug", loc=(-7.5, 15.0, 0.0), yaw_deg=25.0)

    # Bustling cozy concourse interior: Cafe + Barista + Customers + Seated Passengers + Strollers!
    tk.load_glb("game/assets/interior/cafe_counter.glb", "Cafe", loc=(-3.4, -7.2, 0.0), yaw_deg=90.0)
    tk.load_glb("game/assets/interior/cafe_table.glb", "CafeTbl1", loc=(-2.5, -4.6, 0.0), yaw_deg=90.0)
    tk.load_glb("game/assets/interior/seat_row.glb", "Seats1", loc=(-2.6, -1.8, 0.0), yaw_deg=90.0)
    tk.load_glb("game/assets/interior/seat_row.glb", "Seats2", loc=(-2.6, 1.2, 0.0), yaw_deg=90.0)
    tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "IndoorTree", loc=(-3.1, 3.3, 0.0))
    tk.load_glb("game/assets/interior/wall_door.glb", "BackHallDoor", loc=(0.0, -13.4, 0.0), yaw_deg=0.0)
    tk.load_glb("game/assets/interior/duty_free_shelf.glb", "DutyFreeBg", loc=(2.8, -9.8, 0.0), yaw_deg=-90.0)

    bar_r, bar_a, _, bar_acts = tk.load_character("tcp_female_character_07", "CafeBarista", cloth_tint=(0.68, 0.36, 0.20), loc=(-4.15, -7.2, 0.0), yaw_deg=90.0)
    tk.set_nla_clips(bar_a, bar_acts, [("idle", 1, N, 1.15)])
    c1_r, c1_a, _, c1_acts = tk.load_character("tcp_female_character_08", "CafePax", cloth_tint=(0.78, 0.38, 0.62), loc=(-2.35, -6.9, 0.0), yaw_deg=-90.0)
    tk.set_nla_clips(c1_a, c1_acts, [("idle", 1, N, 1.1)])
    c2_r, c2_a, _, c2_acts = tk.load_character("tcp_male_character_04", "CafeSitPax", cloth_tint=(0.30, 0.62, 0.54), loc=(-2.5, -5.15, 0.0), yaw_deg=0.0)
    tk.set_nla_clips(c2_a, c2_acts, [("sit_idle", 1, N, 1.0)])

    s1_r, s1_a, _, s1_acts = tk.load_character("tcp_female_character_01", "SitPax1", cloth_tint=(0.45, 0.66, 0.92), loc=(-2.22, -2.4, 0.0), yaw_deg=90.0)
    tk.set_nla_clips(s1_a, s1_acts, [("sit_idle", 1, N, 1.0)])
    s2_r, s2_a, _, s2_acts = tk.load_character("tcp_male_character_03", "SitPax2", cloth_tint=(0.86, 0.68, 0.25), loc=(-2.22, -1.1, 0.0), yaw_deg=90.0)
    tk.set_nla_clips(s2_a, s2_acts, [("sit_idle", 1, N, 1.05)])
    s3_r, s3_a, _, s3_acts = tk.load_character("tcp_female_character_09", "SitPax3", cloth_tint=(0.88, 0.48, 0.42), loc=(-2.22, 0.8, 0.0), yaw_deg=90.0)
    tk.set_nla_clips(s3_a, s3_acts, [("sit_idle", 1, N, 0.95)])

    stroll_r, stroll_a, _, stroll_acts = tk.load_character("tcp_male_character_05", "ConcourseStroller", cloth_tint=(0.38, 0.46, 0.72), loc=(-1.35, -9.8, 0.0), yaw_deg=180.0)
    tk.set_nla_clips(stroll_a, stroll_acts, [("walk", 1, N, 1.0)])
    tk.key_pos(stroll_r, [(1, (-1.35, -10.5, 0.0)), (N, (-1.35, -3.5, 0.0))])

    events = [{"type": "pa_chime", "frame": g0 + 6}]

    # Gate Desk, Overhead 'GATE C · OSLO' Sign & Boarding Doors snapping into place ahead of Hero!
    gd_root, _, _, _ = tk.load_glb("game/assets/interior/gate_desk.glb", "GateDesk", loc=(-1.65, 3.85, 0.0), yaw_deg=-12.0)
    tk.animate_snap_pop(gd_root, 26, drop_height=1.55)
    events.append({"type": "pop", "frame": g0 + 29, "pitch": 8})

    door_root, _, door_by_n, _ = tk.load_glb("game/assets/interior/wall_door.glb", "GateDoor", loc=(0.0, 5.5, 0.0), yaw_deg=0.0)
    door_root.scale = (1.55, 1.0, 1.08)
    tk.animate_snap_pop(door_root, 36, drop_height=1.65)
    events.append({"type": "pop", "frame": g0 + 39, "pitch": 10})

    sign_root = bpy.data.objects.new("GateSign_ROOT", None)
    sign_root.location = (0.0, 5.15, 2.75)
    scene.collection.objects.link(sign_root)
    tk.make_box(scene, "GateSignBox", (2.85, 0.18, 0.56), (0.0, 0.0, 0.0), tk.toon_rgb_mat("gs_navy", tk.NAVY), bevel=0.03, parent=sign_root, outline=0.005)
    gt_txt = tk.make_nunito_text_3d(scene, "GATE C · OSLO", 0.28, 0.013, tk.emissive_mat("gs_lime", tk.GOTTA_LIME, 1.45), extrude=0.02, parent=sign_root)
    gt_txt.rotation_euler = (math.radians(90), 0.0, 0.0)
    gt_txt.location = (0.0, -0.11, 0.0)
    tk.animate_snap_pop(sign_root, 44, drop_height=1.1)
    events.append({"type": "pop", "frame": g0 + 47, "pitch": 12})

    ga_root, ga_arm, _, ga_acts = tk.load_character(
        "tcp_female_character_07", "GateAgent", cloth_tint=tk.GOTTA_LIME, loc=(-0.92, 4.35, 0.0), yaw_deg=-32.0
    )
    tk.set_nla_clips(ga_arm, ga_acts, [("idle", 1, N, 1.25)])
    wave_keys = []
    for wf in range(35, N, 12):
        wave_keys.append((wf, (125.0, 0.0, -18.0)))
        wave_keys.append((wf + 6, (125.0, 0.0, 26.0)))
    tk.add_pose_override_track(ga_arm, "AgentWave", {"Arm.R": wave_keys})
    tk.animate_snap_pop(ga_root, 32, drop_height=1.45)

    leaf_l = door_by_n.get("Door_Leaf_L")
    leaf_r = door_by_n.get("Door_Leaf_R")
    if leaf_l and leaf_r:
        ll0, lr0 = Vector(leaf_l.location), Vector(leaf_r.location)
        tk.key_pos(leaf_l, [(1, ll0), (92, ll0), (125, ll0 + Vector((-0.62, 0.0, 0.0))), (N, ll0 + Vector((-0.62, 0.0, 0.0)))])
        tk.key_pos(leaf_r, [(1, lr0), (92, lr0), (125, lr0 + Vector((0.62, 0.0, 0.0))), (N, lr0 + Vector((0.62, 0.0, 0.0)))])
    events.append({"type": "door_whoosh", "frame": g0 + 96})

    # Hero passenger sprinting full tilt with gripped roller bag!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.15, -7.8, 0.0), yaw_deg=180.0
    )
    tk.set_nla_clips(hero_arm, hero_acts, [("run", 1, N, 1.44)])
    _attach_towed_roller(hero_root, hero_arm, "HeroRoller04", f_tow_ranges=[(1, N)])
    tk.key_pos(hero_root, [
        (1, (0.15, -7.8, 0.0)),
        (N, (0.05, 4.35, 0.0)),
    ])

    cam, target = tk.make_camera(scene, "Shot04Cam", lens=32.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.15, -3.2, 1.38)),
        (98, (4.35, -0.6, 1.44)),
        (N, (3.65, -0.1, 1.54)),
    ])
    tk.key_pos(target, [
        (1, (-0.10, -7.4, 1.02)),
        (98, (-0.15, -1.5, 1.06)),
        (N, (-0.15, 4.15, 1.18)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": N - 2})
    for f in range(3, N, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    return scene, cam, hero_objs, hero_arm, events


# ==============================================================================
# SHOT 5 (210 frames = 7.0s): Apron Dash & Sleek Gotta Air Fixed-Wing Takeoff
# ==============================================================================


def build_shot_05(g0):
    N = 210
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.18, indoor=False)
    # Distance-misted airfield ground + rolling horizon hills & treeline (zero flat green edge!)
    tk.make_box(scene, "AirfieldGrass", (1200.0, 1200.0, 0.12), (0.0, 0.0, -0.07), tk.horizon_grass_mat(), bevel=0.0)
    tk.add_horizon_hills_and_treeline(scene)

    # Wide paved apron + 500m striped runway along -Y (`tp_runway_02a` rotated 90 deg spans x = -32..+32)
    for ry in (32.0, -32.0, -96.0, -160.0, -224.0, -288.0, -352.0):
        tk.load_glb("game/assets/airside/tp_runway_02a.glb", "Runway_%d" % int(ry), loc=(0.0, ry, 0.0), yaw_deg=90.0, outline_thickness=0.0)

    # Terminal building, background regional prop plane (`tp_plane_03a`), loading truck & tug!
    tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "BgTerminal", loc=(-20.0, 62.0, 0.0), yaw_deg=0.0, outline_thickness=0.004)
    bg_p3_r, bg_p3_objs, _, _ = tk.load_glb("game/assets/planes/tp_plane_03a.glb", "BgPropPlane", loc=(-24.0, 26.0, 0.0), yaw_deg=-25.0, outline_thickness=0.004)
    _apply_gotta_air_livery(bg_p3_objs)
    tk.load_glb("game/assets/vehicles/tp_loading_truck_01a.glb", "BgTruck", loc=(-16.5, 31.0, 0.0), yaw_deg=55.0, outline_thickness=0.004)
    tk.load_glb("game/assets/airside/props/pushback_tug.glb", "ParkedTug", loc=(-12.5, 14.0, 0.0), yaw_deg=35.0, outline_thickness=0.004)

    # Taxiway sign placed cleanly OFF the runway pavement onto the +X grass shoulder (x = 33.8)!
    tk.load_glb("game/assets/airside/props/taxi_sign.glb", "TaxiSignShoulder", loc=(33.8, -22.0, 0.0), yaw_deg=-55.0)

    # High distant sky clouds ONLY (y <= -310, z >= 52 so NO cloud ever touches the climbing nose!)
    tk.add_toon_clouds(scene, [
        (-85, -320, 56, 3.2),
        (-25, -360, 66, 3.6),
        (45, -340, 58, 3.0),
    ])

    # Starring Sleek Fixed-Wing Commercial Jet `tp_plane_05a.glb` in Gotta Air Lime & White!
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "GottaAirJet", loc=(0.0, 0.0, 0.0), yaw_deg=0.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=52.0)

    # Port passenger door `TP_Plane_05A_Door` at (1.37, -8.62, 1.58): open during boarding, closes at f=58..74!
    door = plane_by_n.get("TP_Plane_05A_Door")
    if door is not None:
        dmw = door.matrix_world.copy()
        dpiv = bpy.data.objects.new("JetDoorPivot", None)
        scene.collection.objects.link(dpiv)
        dpiv.parent = plane_root
        dpiv.matrix_world = Matrix.Translation(dmw.translation)
        bpy.context.view_layer.update()
        door.parent = dpiv
        door.matrix_world = dmw
        tk.key_rot_deg(dpiv, [
            (1, (0.0, 0.0, -72.0)),
            (56, (0.0, 0.0, -72.0)),
            (74, (0.0, 0.0, 0.0)),
            (N, (0.0, 0.0, 0.0)),
        ])

    # Mobile Gotta Air yellow/lime 6-step airstair unit docked at port door (x=1.45..3.85, y=-8.62, z=0..1.55)
    steps_root = bpy.data.objects.new("MobileAirstairs", None)
    scene.collection.objects.link(steps_root)
    for si in range(6):
        h = 0.255 * (si + 1)
        sx = 3.65 - si * 0.42
        tk.make_box(
            scene,
            "AirStep_%d" % si,
            (0.44, 1.05, h),
            (sx, -8.62, h * 0.5),
            tk.toon_rgb_mat("astep_%d" % si, tk.YELLOW if si < 4 else tk.GOTTA_LIME),
            bevel=0.02,
            parent=steps_root,
            outline=0.004,
        )
    tk.key_pos(steps_root, [(1, (0.0, 0.0, 0.0)), (55, (0.0, 0.0, 0.0)), (82, (8.5, 4.0, 0.0)), (N, (8.5, 4.0, 0.0))])

    # Hero passenger sprints across apron towing his yellow roller, bounds up airstairs & boards at f=54!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(6.8, -6.2, 0.0), yaw_deg=-65.0
    )
    tk.set_nla_clips(hero_arm, hero_acts, [("run", 1, 58, 1.48)])
    _attach_towed_roller(hero_root, hero_arm, "HeroRoller05", f_tow_ranges=[(1, 56)])
    tk.key_pos(hero_root, [
        (1, (6.8, -6.2, 0.0)),
        (28, (3.85, -8.62, 0.0)),
        (46, (1.75, -8.62, 1.48)),
        (54, (0.85, -8.62, 1.62)),
    ])
    tk.key_rot_deg(hero_root, [(1, (0.0, 0.0, -65.0)), (26, (0.0, 0.0, -90.0)), (56, (0.0, 0.0, -90.0))])
    hero_root.scale = (1.0, 1.0, 1.0)
    hero_root.keyframe_insert(data_path="scale", frame=1)
    hero_root.keyframe_insert(data_path="scale", frame=52)
    hero_root.scale = (0.0001, 0.0001, 0.0001)
    hero_root.keyframe_insert(data_path="scale", frame=55)

    # Takeoff roll down -Y (f=76..138) & nose-up rotation (rx = -13.5 deg lifts -Y nose UP!) into golden sky!
    tk.key_pos(plane_root, [
        (1, (0.0, 0.0, 0.0)),
        (76, (0.0, 0.0, 0.0)),
        (106, (0.0, -14.0, 0.0)),
        (138, (0.0, -44.0, 0.0)),
        (170, (0.0, -86.0, 5.2)),
        (N, (0.0, -142.0, 18.5)),
    ])
    tk.key_rot_deg(plane_root, [
        (1, (0.0, 0.0, 0.0)),
        (130, (0.0, 0.0, 0.0)),
        (166, (-13.0, 0.0, 0.0)),
        (N, (-15.0, 4.0, 0.0)),
    ])
    for wname in ("TP_Plane_05A_Wheel_F", "TP_Plane_05A_Wheel_R.L", "TP_Plane_05A_Wheel_R.R"):
        w = plane_by_n.get(wname)
        if w is not None:
            wmw = w.matrix_world.copy()
            wpiv = bpy.data.objects.new("WheelPiv_" + wname, None)
            scene.collection.objects.link(wpiv)
            wpiv.parent = plane_root
            wpiv.matrix_world = Matrix.Translation(wmw.translation)
            bpy.context.view_layer.update()
            w.parent = wpiv
            w.matrix_world = wmw
            tk.key_rot_deg(wpiv, [(76, (0.0, 0.0, 0.0)), (160, (-1440.0, 0.0, 0.0)), (N, (-1620.0, 0.0, 0.0))])

    # Sweeping chase camera: frames Hero bounding up airstairs into Gotta Air Jet, paces takeoff roll & climb!
    cam, target = tk.make_camera(scene, "Shot05Cam", lens=32.0, fstop=3.2)
    tk.key_pos(cam, [
        (1, (26.5, -21.5, 3.8)),
        (58, (27.5, -22.5, 4.0)),
        (106, (30.5, -36.0, 4.5)),
        (160, (32.0, -104.0, 8.2)),
        (N, (33.5, -166.0, 17.5)),
    ])
    tk.key_pos(target, [
        (1, (0.8, -1.5, 3.2)),
        (58, (0.2, -1.0, 3.4)),
        (106, (0.0, -13.0, 3.6)),
        (160, (0.0, -82.0, 8.5)),
        (N, (0.0, -138.0, 21.5)),
    ])

    events = [
        {"type": "prop_idle", "frame": g0 + 1, "dur": 74},
        {"type": "step_leap", "frame": g0 + 30},
        {"type": "door_seal", "frame": g0 + 72},
        {"type": "prop_rev", "frame": g0 + 76, "dur": 134},
        {"type": "takeoff_whoosh", "frame": g0 + 142},
    ]
    for f in range(4, 48, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    plane_core = [plane_by_n["TP_Plane_05A_Fuselage"]]
    return scene, cam, plane_core, hero_arm, events


# ==============================================================================
# SHOT 6 (165 frames = 5.5s): Sleek Gotta Air Jet Climb + Logo Slam & Wishlist
# ==============================================================================


def build_shot_06(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.22, indoor=False)

    cloud_field = [
        (-28, -58, 13, 2.7),
        (28, -60, 14, 2.8),
        (-8, -76, 11, 3.4),
        (36, -82, 22, 2.6),
        (-36, -84, 24, 2.8),
        (5, -96, 17, 3.6),
        (-18, -42, 11, 1.9),
        (20, -44, 12, 2.0),
    ]
    tk.add_toon_clouds(scene, cloud_field, seed_scale=1.12)

    # Sleek Fixed-Wing Gotta Air Commercial Jet (`tp_plane_05a`) banking left-to-right across the upper golden sky!
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "SkyGottaJet", loc=(10.5, -72.0, 29.0), yaw_deg=-92.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=55.0)

    # Soft translucent alpha-faded wingtip vapor ribbons (feathered smoothly to 0, no rigid sticks!)
    vmat = tk.soft_vapor_trail_mat()
    fus = plane_by_n["TP_Plane_05A_Fuselage"]
    for side, wx in (("L", 13.6), ("R", -13.6)):
        rib = tk.make_box(scene, "SoftVapor_" + side, (0.22, 18.0, 0.05), (wx, 15.5, 1.85), vmat, bevel=0.0, parent=plane_root, outline=0.0)
        rib.visible_shadow = False

    tk.key_pos(plane_root, [
        (1, (10.5, -72.0, 29.2)),
        (N, (-10.5, -72.0, 32.0)),
    ])
    tk.key_rot_deg(plane_root, [
        (1, (-9.0, -16.0, -92.0)),
        (N, (-11.0, -13.0, -88.0)),
    ])

    cam, target = tk.make_camera(scene, "Shot06Cam", lens=36.0, fstop=4.0, dof_dist=72.0)
    tk.key_pos(cam, [(1, (0.0, 0.0, 16.5)), (N, (0.0, -1.5, 17.0))])
    tk.key_pos(target, [(1, (0.0, -72.0, 22.8)), (N, (0.0, -72.0, 23.6))])

    events = [
        {"type": "sky_wind", "frame": g0 + 1, "dur": N},
        {"type": "logo_slam", "frame": g0 + 18},
        {"type": "badge_pop", "frame": g0 + 42},
    ]

    plane_core = [fus]
    return scene, cam, plane_core, None, events


SHOT_BUILDERS = [
    build_shot_01,
    build_shot_02,
    build_shot_03,
    build_shot_04,
    build_shot_05,
    build_shot_06,
]
