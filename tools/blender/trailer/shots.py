"""Six pre-rendered 3D CG story shots for the Gotta Make My Flight AAA teaser trailer (v4 human-motion & IK rebuild).

Timeline (30 fps, 1185 frames = 39.50 seconds total, zero gameplay HUD/UI):
  Shot 1 (f   1..165, 5.50s): Curb Drop-off, Ticking Board ('GOTTA AIR 101 · FINAL CALL!') & Sprint Inside
  Shot 2 (f 166..390, 7.50s): Two Point Terminal Pop-In Ahead of Hero + IK Boarding Pass Handoff
  Shot 3 (f 391..615, 7.50s): Security Two-Hand Suitcase Heave, Stanchion Queue & Emerald Arch Wave
  Shot 4 (f 616..810, 6.50s): Bustling Gate Concourse Sprint, Boarding Pass Flash & Open Gate Doors
  Shot 5 (f 811..1020, 7.00s): Apron Stand Wheeled Airstairs Boarding -> Runway Liftoff & Gear Retraction
  Shot 6 (f 1021..1185, 5.50s): Crisp Golden-Cloud Jet Climb (Gear Stowed) + Option A Logo & Wishlist Badge
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
        tk._set_fcurves_linear(piv)


def _setup_jet_landing_gear(scene, plane_root, plane_by_n, mode="parked", f_roll_start=89, f_retract_start=142, f_retract_end=178, f_end=210):
    """Rig `tp_plane_05a` nose and main landing gear + wheel bay doors for:
    - `parked`: gear down & locked on apron
    - `takeoff_retract`: wheels spin on runway roll, then struts retract cleanly into fuselage bays after liftoff
    - `stowed`: gear 100% retracted & bay doors flush for high-speed sky climb (Shot 6)
    """
    bpy.context.view_layer.update()
    plane_inv = plane_root.matrix_world.inverted()

    def _pivot_part(part_name, local_piv_co):
        ob = plane_by_n.get(part_name)
        if ob is None:
            return None
        mw = ob.matrix_world.copy()
        piv = bpy.data.objects.new("GearPiv_" + part_name, None)
        scene.collection.objects.link(piv)
        piv.parent = plane_root
        piv.location = local_piv_co
        piv.rotation_mode = "XYZ"
        piv.rotation_euler = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        ob.parent = piv
        ob.matrix_world = mw
        return piv

    # Wheel spin pivots (child of their respective gear struts so wheels travel up into bays on retraction!)
    if mode == "takeoff_retract":
        for wname in ("TP_Plane_05A_Wheel_F", "TP_Plane_05A_Wheel_R.L", "TP_Plane_05A_Wheel_R.R"):
            w = plane_by_n.get(wname)
            if w is not None and w.parent is not None:
                wmw = w.matrix_world.copy()
                parent_ob = w.parent
                wpiv = bpy.data.objects.new("SpinWheel_" + wname, None)
                scene.collection.objects.link(wpiv)
                wpiv.parent = parent_ob
                wpiv.matrix_world = Matrix.Translation(wmw.translation)
                bpy.context.view_layer.update()
                w.parent = wpiv
                w.matrix_world = wmw
                tk.key_rot_deg(wpiv, [
                    (1, (0.0, 0.0, 0.0)),
                    (f_roll_start, (0.0, 0.0, 0.0)),
                    (f_retract_start + 8, (-2160.0, 0.0, 0.0)),
                    (f_end, (-2280.0, 0.0, 0.0)),
                ])

    if mode == "parked":
        return

    nose_piv = _pivot_part("TP_Plane_05A_Landing_Gear_F", (0.0, -10.45, 1.55))
    ml_piv = _pivot_part("TP_Plane_05A_Landing_Gear_R.L", (1.65, 2.14, 1.46))
    mr_piv = _pivot_part("TP_Plane_05A_Landing_Gear_R.R", (-1.65, 2.14, 1.46))
    hf_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_F", (0.28, -11.00, 1.44))
    hl_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_R.L", (2.13, 2.20, 1.02))
    hr_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_R.R", (-2.13, 2.20, 1.02))

    if mode == "stowed":
        if nose_piv:
            nose_piv.rotation_euler = (math.radians(96.0), 0.0, 0.0)
        if ml_piv:
            ml_piv.rotation_euler = (0.0, math.radians(88.0), 0.0)
        if mr_piv:
            mr_piv.rotation_euler = (0.0, math.radians(-88.0), 0.0)
        for hname in ("TP_Plane_05A_Hatch_Ext_F", "TP_Plane_05A_Hatch_Ext_R.L", "TP_Plane_05A_Hatch_Ext_R.R",
                      "TP_Plane_05A_Landing_Gear_F", "TP_Plane_05A_Landing_Gear_R.L", "TP_Plane_05A_Landing_Gear_R.R",
                      "TP_Plane_05A_Wheel_F", "TP_Plane_05A_Wheel_R.L", "TP_Plane_05A_Wheel_R.R"):
            ob = plane_by_n.get(hname)
            if ob is not None:
                ob.hide_render = True
                ob.hide_viewport = True
        return

    # Smooth animated retraction after liftoff!
    if nose_piv:
        tk.key_rot_deg(nose_piv, [(1, (0, 0, 0)), (f_retract_start, (0, 0, 0)), (f_retract_end, (96.0, 0, 0)), (f_end, (96.0, 0, 0))])
    if ml_piv:
        tk.key_rot_deg(ml_piv, [(1, (0, 0, 0)), (f_retract_start, (0, 0, 0)), (f_retract_end, (0, 88.0, 0)), (f_end, (0, 88.0, 0))])
    if mr_piv:
        tk.key_rot_deg(mr_piv, [(1, (0, 0, 0)), (f_retract_start, (0, 0, 0)), (f_retract_end, (0, -88.0, 0)), (f_end, (0, -88.0, 0))])
    if hf_piv:
        tk.key_rot_deg(hf_piv, [(1, (0, 0, 0)), (f_retract_end - 8, (0, 0, 0)), (f_retract_end + 8, (0, -85.0, 0)), (f_end, (0, -85.0, 0))])
    if hl_piv:
        tk.key_rot_deg(hl_piv, [(1, (0, 0, 0)), (f_retract_end - 8, (0, 0, 0)), (f_retract_end + 8, (0, 82.0, 0)), (f_end, (0, 82.0, 0))])
    if hr_piv:
        tk.key_rot_deg(hr_piv, [(1, (0, 0, 0)), (f_retract_end - 8, (0, 0, 0)), (f_retract_end + 8, (0, -82.0, 0)), (f_end, (0, -82.0, 0))])


def _attach_towed_roller(hero_root, hero_arm, label, f_ik_ranges, pose_ranges=None):
    """Parent yellow CarryRoller (`bag_scale=1.42`, realistic `0.9x` handle extension) to `hero_root`:
    - `tow`: tilted `rx = -72 deg`, `z = +0.295 m` -> rear wheels sit flush (`+0.001 m`) on `hero_root`'s floor!
    - `stand`: upright `rx = -88 deg`, `z = +0.312 m` -> rear wheels sit flush on floor beside right hip!
    - `carry`: `Pull_Top` retracted flush, `rx = -86 deg`, `z = +0.82 m` -> lifted in right hand `0.51 m` clear above stair steps!
    """
    bag_root, _, bag_by_n = tk.load_roller_bag(
        label,
        extended=True,
        loc=(-0.25, 0.24, 0.295),
        yaw_deg=0.0,
        bag_tint=tk.YELLOW,
        parent=hero_root,
        bag_scale=1.42,
    )
    bag_root.rotation_mode = "XYZ"
    bag_root.rotation_euler = (math.radians(-72.0), 0.0, 0.0)

    if pose_ranges:
        pos_keys = []
        rot_keys = []
        for f0, f1, mode in pose_ranges:
            if mode == "stand":
                pos_keys.extend([(f0, (-0.27, -0.04, 0.312)), (f1, (-0.27, -0.04, 0.312))])
                rot_keys.extend([(f0, (-88.0, 0.0, 0.0)), (f1, (-88.0, 0.0, 0.0))])
                tk.set_roller_handle(bag_by_n, extended=True, frame=f0)
                tk.set_roller_handle(bag_by_n, extended=True, frame=f1)
            elif mode == "carry":
                pos_keys.extend([(f0, (-0.28, -0.04, 0.82)), (f1, (-0.28, -0.04, 0.82))])
                rot_keys.extend([(f0, (-86.0, 0.0, 0.0)), (f1, (-86.0, 0.0, 0.0))])
                tk.set_roller_handle(bag_by_n, extended=False, frame=f0)
                tk.set_roller_handle(bag_by_n, extended=False, frame=f1)
            else:
                pos_keys.extend([(f0, (-0.25, 0.24, 0.295)), (f1, (-0.25, 0.24, 0.295))])
                rot_keys.extend([(f0, (-72.0, 0.0, 0.0)), (f1, (-72.0, 0.0, 0.0))])
                tk.set_roller_handle(bag_by_n, extended=True, frame=f0)
                tk.set_roller_handle(bag_by_n, extended=True, frame=f1)
        tk.key_pos(bag_root, pos_keys)
        tk.key_rot_deg(bag_root, rot_keys)
        tk._set_fcurves_linear(bag_root)

    if f_ik_ranges and "Pull_Top" in bag_by_n:
        tk.bind_hand_ik_to_roller(hero_arm, bag_by_n["Pull_Top"], f_ik_ranges, hand="R")
    return bag_root, bag_by_n


def _make_boarding_pass_card(scene, name="BoardingPass", parent=None):
    holder = bpy.data.objects.new(name, None)
    scene.collection.objects.link(holder)
    if parent is not None:
        holder.parent = parent
    tk.make_box(scene, name + "_Card", (0.28, 0.14, 0.012), (0.0, 0.0, 0.0), tk.emissive_mat("pass_cream", tk.CREAM, 1.25), bevel=0.003, parent=holder, outline=0.003)
    tk.make_box(scene, name + "_Stripe", (0.28, 0.04, 0.015), (0.0, -0.04, 0.002), tk.emissive_mat("pass_lime", tk.GOTTA_LIME, 1.35), bevel=0.002, parent=holder)
    return holder


def _build_departure_board(scene, loc, flip_frame):
    root = bpy.data.objects.new("DepartureBoard_ROOT", None)
    root.location = loc
    scene.collection.objects.link(root)

    navy_m = tk.toon_rgb_mat("board_housing", tk.NAVY)
    deep_m = tk.emissive_mat("board_screen", (0.05, 0.07, 0.14), strength=1.0)
    lime_m = tk.emissive_mat("board_lime", tk.GOTTA_LIME, strength=1.25)
    cream_m = tk.emissive_mat("board_cream", tk.CREAM, strength=1.20)
    amber_m = tk.emissive_mat("board_amber", tk.AMBER, strength=1.30)
    coral_m = tk.emissive_mat("board_coral", tk.ALERT_CORAL, strength=1.35)

    tk.make_box(scene, "Board_Case", (4.60, 0.28, 1.48), (0.0, 0.0, 0.0), navy_m, bevel=0.05, parent=root, outline=0.006)
    tk.make_box(scene, "Board_HeaderBar", (4.42, 0.06, 0.22), (0.0, -0.13, 0.52), lime_m, bevel=0.02, parent=root)
    tk.make_box(scene, "Board_Screen", (4.42, 0.04, 1.08), (0.0, -0.13, -0.10), deep_m, bevel=0.02, parent=root)

    t_top = tk.make_nunito_text_3d(scene, "GOTTA AIR 101 · OSLO", 0.30, 0.009, cream_m, extrude=0.02, parent=root)
    t_top.rotation_euler = (math.radians(90), 0.0, 0.0)
    t_top.location = (0.0, -0.165, 0.16)

    flap_boarding = tk.make_nunito_text_3d(scene, "GATE C · BOARDING", 0.33, 0.010, amber_m, extrude=0.02, parent=root)
    flap_boarding.rotation_euler = (math.radians(90), 0.0, 0.0)
    flap_boarding.location = (0.0, -0.165, -0.34)

    flap_final = bpy.data.objects.new("FlapFinal_Holder", None)
    flap_final.location = (0.0, -0.175, -0.35)
    flap_final.parent = root
    scene.collection.objects.link(flap_final)

    fc_words = tk.make_nunito_text_3d(scene, "FINAL CALL", 0.40, 0.009, coral_m, extrude=0.025, parent=flap_final)
    fc_words.rotation_euler = (math.radians(90), 0.0, 0.0)
    fc_words.location = (-0.11, 0.0, 0.0)
    half_w = max(v.co.x for v in fc_words.data.vertices)
    bang_x = -0.11 + half_w + 0.13
    tk.make_box(scene, "FinalBang_Stem", (0.056, 0.028, 0.185), (bang_x, 0.0, 0.074), coral_m, bevel=0.012, parent=flap_final)
    tk.make_box(scene, "FinalBang_Dot", (0.058, 0.028, 0.056), (bang_x, 0.0, -0.126), coral_m, bevel=0.012, parent=flap_final)

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


def _build_wheeled_airstairs(scene, name="MobileAirstairs_ROOT", loc=(0.0, 0.0, 0.0)):
    """Build a real wheeled mobile airstairs unit with steel frame, 4 rubber tires, yellow angled
    side stringers, 7 dark non-slip treads + upper boarding deck, yellow tubular handrails, and towbar!
    In local space: aircraft cabin threshold is at `x = 0.0` (`z = 1.54m`), foot of steps is at `x = +2.85m` (`z = 0.0m`).
    """
    root = bpy.data.objects.new(name, None)
    root.location = loc
    scene.collection.objects.link(root)

    steel_m = tk.toon_rgb_mat("stair_steel", (0.24, 0.27, 0.34))
    tread_m = tk.toon_rgb_mat("stair_tread", (0.18, 0.20, 0.25))
    yellow_m = tk.toon_rgb_mat("stair_yellow", tk.YELLOW)
    lime_m = tk.toon_rgb_mat("stair_lime", tk.GOTTA_LIME)
    tire_m = tk.toon_rgb_mat("stair_tire", (0.11, 0.12, 0.14))
    hub_m = tk.toon_rgb_mat("stair_hub", (0.82, 0.84, 0.88))

    # Lower steel chassis rails + front/rear support columns
    tk.make_box(scene, "Stair_ChassisL", (2.65, 0.10, 0.12), (1.42, -0.52, 0.28), steel_m, bevel=0.015, parent=root, outline=0.004)
    tk.make_box(scene, "Stair_ChassisR", (2.65, 0.10, 0.12), (1.42, 0.52, 0.28), steel_m, bevel=0.015, parent=root, outline=0.004)
    tk.make_box(scene, "Stair_CrossF", (0.12, 1.14, 0.12), (0.35, 0.0, 0.28), steel_m, bevel=0.015, parent=root)
    tk.make_box(scene, "Stair_CrossR", (0.12, 1.14, 0.12), (2.50, 0.0, 0.28), steel_m, bevel=0.015, parent=root)
    for sy in (-0.52, 0.52):
        tk.make_box(scene, "Stair_Tower_%.2f" % sy, (0.14, 0.10, 1.24), (0.42, sy, 0.90), yellow_m, bevel=0.015, parent=root, outline=0.004)
        tk.make_box(scene, "Stair_DiagBrace_%.2f" % sy, (0.10, 0.08, 1.38), (1.28, sy, 0.72), steel_m, bevel=0.01, parent=root)
        bpy.data.objects["Stair_DiagBrace_%.2f" % sy].rotation_euler = (0.0, math.radians(-42.0), 0.0)

    # 4 rubber wheels with hubs (wheel pivots around local Y so rolling along +X spins them!)
    wheel_pivots = []
    for wx_tag, wx in (("Front", 0.45), ("Rear", 2.42)):
        for wy_tag, wy in (("L", -0.62), ("R", 0.62)):
            wpiv = bpy.data.objects.new("StairWheelPiv_%s_%s" % (wx_tag, wy_tag), None)
            wpiv.location = (wx, wy, 0.24)
            wpiv.parent = root
            scene.collection.objects.link(wpiv)
            bpy.ops.mesh.primitive_cylinder_add(vertices=18, radius=0.24, depth=0.14, location=(0.0, 0.0, 0.0))
            tire = bpy.context.active_object
            tire.name = "StairTire_%s_%s" % (wx_tag, wy_tag)
            tire.rotation_euler = (math.radians(90.0), 0.0, 0.0)
            tire.data.materials.append(tire_m)
            tk.attach_outline(tire, 0.004)
            tire.parent = wpiv
            tk.make_box(scene, "StairHub_%s_%s" % (wx_tag, wy_tag), (0.16, 0.16, 0.06), (0.0, 0.0, 0.0), hub_m, bevel=0.01, parent=wpiv)
            wheel_pivots.append(wpiv)

    # Sloped yellow side stringer cheeks + Gotta Air lime stripe
    for sy_tag, sy in (("L", -0.56), ("R", 0.56)):
        cheek = tk.make_box(scene, "StairStringer_" + sy_tag, (2.55, 0.07, 0.26), (1.68, sy, 0.86), yellow_m, bevel=0.015, parent=root, outline=0.004)
        cheek.rotation_euler = (0.0, math.radians(30.5), 0.0)
        stripe = tk.make_box(scene, "StairStripe_" + sy_tag, (2.45, 0.08, 0.07), (1.68, sy, 0.88), lime_m, bevel=0.008, parent=root)
        stripe.rotation_euler = (0.0, math.radians(30.5), 0.0)

    # Upper horizontal boarding platform + soft black rubber aircraft bumper at x = 0.0..0.82
    tk.make_box(scene, "StairTopDeck", (0.84, 1.16, 0.10), (0.42, 0.0, 1.50), tread_m, bevel=0.015, parent=root, outline=0.004)
    tk.make_box(scene, "StairBumper", (0.10, 1.18, 0.14), (0.02, 0.0, 1.52), tire_m, bevel=0.02, parent=root)

    # 7 crisp non-slip stair treads rising from (x=2.76, z=0.20) to (x=0.96, z=1.36)
    for si in range(7):
        tx = 2.76 - si * 0.30
        tz = 0.20 + si * 0.195
        tk.make_box(scene, "StairTread_%d" % si, (0.32, 1.04, 0.055), (tx, 0.0, tz), tread_m, bevel=0.01, parent=root, outline=0.003)

    # Tubular yellow safety handrails on BOTH sides (vertical stanchions + sloped top & mid rails + platform guardrails!)
    for sy_tag, sy in (("L", -0.58), ("R", 0.58)):
        for pi, (px, pz_base) in enumerate(((0.14, 1.54), (0.82, 1.52), (1.78, 0.90), (2.76, 0.24))):
            tk.make_box(scene, "HandrailPost_%s_%d" % (sy_tag, pi), (0.045, 0.045, 0.88), (px, sy, pz_base + 0.44), yellow_m, bevel=0.01, parent=root, outline=0.003)
        tk.make_box(scene, "TopGuardRail_" + sy_tag, (0.74, 0.05, 0.05), (0.48, sy, 2.38), yellow_m, bevel=0.01, parent=root, outline=0.003)
        slope_top = tk.make_box(scene, "SlopeHandrail_" + sy_tag, (2.30, 0.05, 0.05), (1.80, sy, 1.76), yellow_m, bevel=0.01, parent=root, outline=0.003)
        slope_top.rotation_euler = (0.0, math.radians(31.5), 0.0)
        slope_mid = tk.make_box(scene, "SlopeMidrail_" + sy_tag, (2.25, 0.038, 0.038), (1.80, sy, 1.42), yellow_m, bevel=0.008, parent=root)
        slope_mid.rotation_euler = (0.0, math.radians(31.5), 0.0)

    # Steel towbar coupling extending from x = 2.65 -> x = 3.75 to hitch onto the yellow ground tug!
    tk.make_box(scene, "StairTowbar", (1.20, 0.09, 0.07), (3.18, 0.0, 0.24), yellow_m, bevel=0.01, parent=root, outline=0.003)
    return root, wheel_pivots


# ==============================================================================
# SHOT 1 (165 frames = 5.5s): Curb Drop-off, Ticking Board & Sprint Inside
# ==============================================================================


def build_shot_01(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.12, indoor=False)
    tk.make_box(scene, "LandsideSubRoad", (220.0, 220.0, 0.12), (0.0, 0.0, 0.03), tk.toon_rgb_mat("road_sub", (0.25, 0.27, 0.32)), bevel=0.0)

    ROAD_Z = 0.105
    CURB_Z = 0.20

    _, _, ap_by_n, _ = tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "AirportExt", loc=(0.0, 0.0, 0.0), outline_thickness=0.003)
    tk.load_glb("game/assets/landside/tp_curb_bay_01a.glb", "CurbBay", loc=(15.5, -19.6, 0.11), outline_thickness=0.003)

    # Curbside props tucked neatly along y = -18.35 with planters rotated yaw=90 so the y=-20.0 walkway is 100% obstacle-free!
    pl_l, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantL", loc=(11.8, -18.35, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    pl_r, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantR", loc=(20.2, -18.35, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    tr1, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeL", loc=(5.4, -18.25, CURB_Z), outline_thickness=0.004)
    tr1.scale = (1.50, 1.50, 1.50)
    tr2, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeR", loc=(25.8, -18.25, CURB_Z), outline_thickness=0.004)
    tr2.scale = (1.55, 1.55, 1.55)
    bench_c, _, _, _ = tk.load_glb("game/assets/decor/tc_bench_1a.glb", "CurbBench", loc=(23.0, -18.35, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    bin_c, _, _, _ = tk.load_glb("game/assets/decor/tc_trash_can_1a.glb", "CurbBin", loc=(18.6, -18.35, CURB_Z), outline_thickness=0.004)

    pole_m = tk.toon_rgb_mat("lamp_pole", (0.22, 0.25, 0.32))
    bulb_m = tk.emissive_mat("lamp_bulb", (1.0, 0.92, 0.72), strength=1.8)
    lamp_poles = []
    for lx in (9.0, 22.0):
        lp = tk.make_box(scene, "LampPole_%d" % int(lx), (0.12, 0.12, 3.8), (lx, -20.85, CURB_Z + 1.9), pole_m, bevel=0.02)
        tk.make_box(scene, "LampHead_%d" % int(lx), (0.48, 0.28, 0.16), (lx, -21.05, CURB_Z + 3.82), bulb_m, bevel=0.03)
        lamp_poles.append(lp)

    # Departing SUV in the outer traffic lane (y = -23.9)
    cruiser, _, _, _ = tk.load_glb("game/assets/vehicles/tp_suv_01b.glb", "DepartingSUV", loc=(21.5, -23.9, ROAD_Z), yaw_deg=90.0, outline_thickness=0.003)
    tk.key_pos(cruiser, [(1, (20.8, -23.9, ROAD_Z)), (N, (31.5, -23.9, ROAD_Z))])
    tk._set_fcurves_linear(cruiser)

    # Background travelers strolling on unobstructed front sidewalk with stride-locked feet!
    bg1_r, bg1_a, _, bg1_acts = tk.load_character("tcp_female_character_03", "CurbPax1", cloth_tint=(0.28, 0.65, 0.78), loc=(25.0, -19.95, CURB_Z), yaw_deg=-90.0)
    tk.animate_character_locomotion(bg1_r, bg1_a, bg1_acts, [(1, (25.0, -19.95, CURB_Z)), (N, (17.8, -19.95, CURB_Z))], N, phase_offset=7.0)
    sh_bag, _, _, _ = tk.load_glb("game/assets/interior/carry_shoulder_bag.glb", "CurbPax1Bag", outline_thickness=0.004)
    tk.parent_prop_to_bone(sh_bag, bg1_a, "Spine_02", local_loc=(-0.22, -0.10, 0.0), local_rot_deg=(-90.0, 0.0, 0.0))

    bg2_r, bg2_a, _, bg2_acts = tk.load_character("tcp_male_character_08", "CurbPax2", cloth_tint=(0.45, 0.58, 0.32), loc=(8.6, -19.95, CURB_Z), yaw_deg=-90.0)
    tk.animate_character_locomotion(bg2_r, bg2_a, bg2_acts, [(1, (8.6, -19.95, CURB_Z)), (N, (1.4, -19.95, CURB_Z))], N, phase_offset=14.0)

    flip_f = 52
    board_root = _build_departure_board(scene, (15.85, -19.95, 3.22), flip_frame=flip_f)
    board_root.scale = (0.76, 0.76, 0.76)

    # Slide Terminal Door 6 wide open ahead of Hero's sprint!
    door6 = ap_by_n.get("TP_Airport_01A_Door_6")
    if door6 is not None:
        dloc = Vector(door6.location)
        tk.key_pos(door6, [(1, dloc), (88, dloc), (112, dloc + Vector((1.85, 0.0, 0.0))), (N, dloc + Vector((1.85, 0.0, 0.0)))])

    # Hero Taxi: arrives braking smoothly at f=1..22, opens rear door f=18..26, closes door f=98..110, pulls away f=114..N!
    # (`tp_taxi_01a` has opaque dark-tinted windows; keeping interior unpopulated prevents shoes poking under chassis!)
    taxi_root, taxi_objs, taxi_by_n, _ = tk.load_glb("game/assets/vehicles/tp_taxi_01a.glb", "HeroTaxi", loc=(6.2, -22.15, ROAD_Z), yaw_deg=90.0, outline_thickness=0.003)

    bpy.context.view_layer.update()
    taxi_inv = taxi_root.matrix_world.inverted()
    for wname in ("TP_Taxi_01A_Wheel_F.L", "TP_Taxi_01A_Wheel_F.R", "TP_Taxi_01A_Wheel_R.L", "TP_Taxi_01A_Wheel_R.R"):
        w = taxi_by_n.get(wname)
        if w is not None:
            wmw = w.matrix_world.copy()
            wpiv = bpy.data.objects.new("TaxiWheelPiv_" + wname, None)
            scene.collection.objects.link(wpiv)
            wpiv.parent = taxi_root
            wpiv.location = taxi_inv @ wmw.translation
            wpiv.rotation_mode = "XYZ"
            wpiv.rotation_euler = (0.0, 0.0, 0.0)
            bpy.context.view_layer.update()
            w.parent = wpiv
            w.matrix_world = wmw
            tk.key_rot_deg(wpiv, [
                (1, (0.0, 0.0, 0.0)),
                (23, (760.0, 0.0, 0.0)),
                (110, (760.0, 0.0, 0.0)),
                (N, (1860.0, 0.0, 0.0)),
            ])

    tk.key_pos(taxi_root, [
        (1, (6.2, -22.15, ROAD_Z)),
        (19, (11.15, -22.15, ROAD_Z)),
        (24, (11.45, -22.15, ROAD_Z)),
        (110, (11.45, -22.15, ROAD_Z)),
        (124, (12.40, -22.25, ROAD_Z)),
        (N, (19.20, -22.55, ROAD_Z)),
    ])
    tk.key_rot_deg(taxi_root, [
        (1, (0.0, 0.0, 90.0)),
        (18, (0.0, 0.0, 90.0)),
        (22, (2.2, 0.0, 90.0)),
        (28, (0.0, 0.0, 90.0)),
        (110, (0.0, 0.0, 90.0)),
        (125, (-1.2, 0.0, 92.5)),
        (N, (0.0, 0.0, 91.0)),
    ])
    rdoor = taxi_by_n.get("TP_Taxi_01A_Door_R.L")
    if rdoor is not None:
        tk.key_rot_deg(rdoor, [
            (1, (90.0, 0.0, 0.0)),
            (17, (90.0, 0.0, 0.0)),
            (25, (90.0, 0.0, -64.0)),
            (94, (90.0, 0.0, -64.0)),
            (108, (90.0, 0.0, 0.0)),
        ])

    # Hero passenger: seated at full 1.0 scale inside rear cab seat (f=1..18, z=ROAD_Z-0.38 so head stays well below cab roof!),
    # steps out onto CURB_Z (f=19..40), looks up at FINAL CALL! board (f=42..84) with head TrackTo + surprised left-hand IK,
    # then sprints at realistic ~3.35 m/s straight into the open Door_6 vestibule!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(11.35, -21.05, CURB_Z), yaw_deg=72.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (11.35, -21.05, CURB_Z), 72.0),
            (19, (11.35, -21.05, CURB_Z), 72.0),
            (28, (12.05, -20.20, CURB_Z), 75.0),
            (40, (13.35, -20.20, CURB_Z), 158.0),
            (102, (13.35, -20.20, CURB_Z), 118.0),
            (138, (15.90, -19.10, CURB_Z)),
            (N, (16.00, -17.32, CURB_Z)),
        ],
        frame_end=N,
    )
    # Head + Spine_02 look up at Departure Board via quaternion-safe TRACK_TO!
    tk.bind_head_look_at(
        scene,
        hero_arm,
        "HeroBoardLook",
        target_pos=(15.85, -19.80, 3.22),
        influence_keys=[(1, 0.0), (42, 0.0), (54, 0.72), (94, 0.72), (106, 0.0)],
        include_spine=True,
    )
    # Urgent left-hand "oh no, my flight!" reaction to temple via 2-bone IK on Forearm.L!
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "BoardStartle",
        hand="L",
        parent=hero_root,
        pos_keys=[
            (50, (0.28, -0.05, 1.18)),
            (58, (0.20, -0.18, 1.78)),
            (90, (0.22, -0.16, 1.76)),
            (102, (0.28, -0.05, 1.18)),
        ],
        influence_keys=[(1, 0.0), (50, 0.0), (57, 0.92), (90, 0.92), (102, 0.0)],
    )
    bag01_root, _ = _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller01",
        f_ik_ranges=[(20, N)],
        pose_ranges=[(1, 38, "tow"), (42, 100, "stand"), (106, N, "tow")],
    )
    # Keep Hero + suitcase concealed inside opaque closed taxi until rear door swings open at f=19 (at full 1.0 scale!)
    for vis_ob in list(hero_objs) + [o for o in scene.objects if o.parent == bag01_root or (o.parent and o.parent.parent == bag01_root)]:
        if vis_ob.type == "MESH":
            vis_ob.hide_render = True
            vis_ob.keyframe_insert(data_path="hide_render", frame=1)
            vis_ob.keyframe_insert(data_path="hide_render", frame=18)
            vis_ob.hide_render = False
            vis_ob.keyframe_insert(data_path="hide_render", frame=19)
            vis_ob.keyframe_insert(data_path="hide_render", frame=N)

    cam, target = tk.make_camera(scene, "Shot01Cam", lens=34.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (12.6, -26.8, 1.72)),
        (36, (15.4, -27.2, 1.76)),
        (102, (15.8, -27.0, 1.76)),
        (N, (16.1, -24.8, 1.78)),
    ])
    tk.key_pos(target, [
        (1, (7.4, -21.8, 1.05)),
        (36, (13.8, -20.1, 1.48)),
        (54, (14.85, -19.8, 1.66)),
        (100, (14.95, -19.6, 1.66)),
        (N, (15.95, -17.8, 1.52)),
    ])

    events = [
        {"type": "car_arrive", "frame": g0 + 1, "dur": 24},
        {"type": "car_brake", "frame": g0 + 20},
        {"type": "car_door", "frame": g0 + 21},
        {"type": "board_flip", "frame": g0 + flip_f - 3, "count": 9},
        {"type": "startle_sting", "frame": g0 + flip_f + 2},
        {"type": "door_whoosh", "frame": g0 + 92},
        {"type": "roller", "frame": g0 + 104, "dur": 60},
    ]
    for f in list(range(26, 40, 8)) + list(range(105, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    taxi_body = [taxi_by_n["TP_Taxi_01A_Body"]] if "TP_Taxi_01A_Body" in taxi_by_n else taxi_objs
    prove_targets = [
        ("start_taxi", 1, taxi_body),
        ("mid", 83, hero_objs),
        ("f100", 105, hero_objs),
        ("end", N, hero_objs),
    ]
    motion_spec = {
        "obstacle_roots": [
            ("CurbPlantL", pl_l),
            ("CurbPlantR", pl_r),
            ("CurbTreeL", tr1),
            ("CurbTreeR", tr2),
            ("CurbBench", bench_c),
            ("CurbBin", bin_c),
        ] + [("LampPole_%d" % i, lp) for i, lp in enumerate(lamp_poles)],
        # Building front wall segments flanking the open Door_6 aperture (x = 15.05..16.95)
        "extra_boxes_xy": [
            ("TerminalFacade_W", -40.0, 15.02, -18.25, -16.50),
            ("TerminalFacade_E", 16.98, 40.0, -18.25, -16.50),
        ],
        "seated_exempt": set(),
        "exempt_ranges": {"CHAR_Hero": [(1, 20)]},
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 2 (225 frames = 7.5s): Two Point Pop-In Ahead of Hero + IK Handoff
# ==============================================================================


def build_shot_02(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
    # Enclosed terminal hall WITH an actual open east concourse archway (y=3.35, width=3.4m, height=2.95m) leading to Security!
    tk.build_enclosed_terminal_hall(
        scene,
        x_min=-3.8,
        x_max=6.8,
        y_min=-13.5,
        y_max=7.8,
        ceil_z=3.85,
        glass_side="left",
        open_north_wall=False,
        east_archway=(3.35, 4.20, 3.10),
    )

    # Illuminated overhead 'SECURITY ->' concourse archway sign above x = 6.6!
    sec_sign = bpy.data.objects.new("SecCorridorSign_ROOT", None)
    sec_sign.location = (6.52, 3.35, 3.22)
    sec_sign.rotation_euler = (0.0, 0.0, math.radians(-90.0))
    scene.collection.objects.link(sec_sign)
    tk.make_box(scene, "SecSignBox", (2.55, 0.16, 0.46), (0.0, 0.0, 0.0), tk.toon_rgb_mat("ss_navy", tk.NAVY), bevel=0.025, parent=sec_sign, outline=0.004)
    stxt = tk.make_nunito_text_3d(scene, "SECURITY  >", 0.25, 0.011, tk.emissive_mat("ss_lime", tk.GOTTA_LIME, 1.4), extrude=0.018, parent=sec_sign)
    stxt.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    stxt.location = (0.0, -0.10, 0.0)

    # Background terminal props tucked cleanly out of all concourse walking lanes!
    tk.load_glb("game/assets/interior/wall_door.glb", "EntryDoorBack", loc=(0.0, -13.4, 0.0), yaw_deg=0.0)
    b_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "BackScreen", loc=(3.8, -13.0, 0.0), yaw_deg=0.0)
    b_ksk, _, _, _ = tk.load_glb("game/assets/interior/kiosk.glb", "BackKiosk", loc=(4.8, -8.5, 0.0), yaw_deg=-90.0)

    # Real janitor mopping an actual spill puddle with a 3D wooden mop & yellow bucket!
    tk.load_glb("game/assets/mess/mess_spill.glb", "CoffeeSpill", loc=(-2.25, -8.75, 0.005), yaw_deg=20.0, outline_thickness=0.003)
    bucket_root = tk.make_box(scene, "CleanerBucket", (0.34, 0.28, 0.36), (-2.95, -8.85, 0.18), tk.toon_rgb_mat("mop_bucket", tk.YELLOW), bevel=0.02, outline=0.004)
    cln_r, cln_a, _, cln_acts = tk.load_character("tcp_female_character_10", "HallCleaner", cloth_tint=None, loc=(-2.25, -9.45, 0.0), yaw_deg=175.0)
    tk.set_stationary_clip(cln_a, cln_acts, "clean", N, speed=1.0)
    mop_root = bpy.data.objects.new("CleanerMop", None)
    scene.collection.objects.link(mop_root)
    tk.make_box(scene, "MopStick", (0.032, 0.032, 1.28), (0.0, 0.0, -0.45), tk.toon_rgb_mat("mop_wood", (0.72, 0.52, 0.30)), bevel=0.005, parent=mop_root, outline=0.003)
    tk.make_box(scene, "MopHead", (0.28, 0.14, 0.09), (0.0, 0.0, -1.08), tk.toon_rgb_mat("mop_cotton", tk.CREAM), bevel=0.02, parent=mop_root, outline=0.003)
    tk.parent_prop_to_bone(mop_root, cln_a, "Hand.R", local_loc=(0.0, 0.04, 0.0), local_rot_deg=(22.0, 0.0, 0.0))

    # Two background travelers walking smoothly along unobstructed right-hand concourse lanes (zero bench collisions!)
    bg1_r, bg1_a, _, bg1_acts = tk.load_character("tcp_female_character_05", "HallPax1", cloth_tint=(0.42, 0.62, 0.88), loc=(2.35, -11.4, 0.0), yaw_deg=180.0)
    tk.animate_character_locomotion(bg1_r, bg1_a, bg1_acts, [(1, (2.35, -11.4, 0.0)), (N, (2.35, -1.6, 0.0))], N, phase_offset=5.0)

    bg2_r, bg2_a, _, bg2_acts = tk.load_character("tcp_male_character_02", "HallPax2", cloth_tint=(0.78, 0.56, 0.24), loc=(-1.35, -7.8, 0.0), yaw_deg=0.0)
    tk.animate_character_locomotion(bg2_r, bg2_a, bg2_acts, [(1, (-1.35, -7.8, 0.0)), (N, (-1.35, -12.6, 0.0))], N, phase_offset=18.0)

    events = []
    pop_idx = 0

    def snap(obj, trig_f, drop=1.45):
        nonlocal pop_idx
        tk.animate_snap_pop(obj, trig_f, drop_height=drop)
        if trig_f > 1:
            events.append({"type": "pop", "frame": g0 + trig_f + 3, "pitch": pop_idx})
            pop_idx += 1

    # Two Point / Planet Coaster pop-in wave happening IN FRAME 0.5-0.8s ahead of sprinting Hero!
    # Hero sprints from y=-8.2 (f=1) to y=+3.42 (f=104) -> ~0.113 m/frame!
    for row_i, gy in enumerate(range(-6, 6)):
        row_holder = bpy.data.objects.new("FloorRow_%d" % row_i, None)
        row_holder.location = (0.0, float(gy), 0.015)
        scene.collection.objects.link(row_holder)
        for gx in (-3, -2, -1, 0, 1, 2, 3):
            r, _, _, _ = tk.load_glb("game/assets/interior/floor_tile.glb", "FT_%d_%d" % (gx, gy), loc=(float(gx), 0.0, 0.0), outline_thickness=0.0)
            r.parent = row_holder
        trig = max(2, int((gy - (-7.2)) / 0.113) - 14)
        snap(row_holder, trig, drop=0.80)

    for wi, wy in enumerate(range(-12, 8, 2)):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "WG_%d" % wi, loc=(-3.75, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)
        if wy >= -4:
            snap(wg, max(4, int((wy - (-7.0)) / 0.113) - 16), drop=1.65)

    # Compact concourse bench (`tc_bench_1a`), planters, screen stand, check-in desks & baggage belt popping in ahead!
    st2, _, _, _ = tk.load_glb("game/assets/decor/tc_bench_1a.glb", "SnapBench", loc=(-3.05, -4.8, 0.0), yaw_deg=0.0)
    snap(st2, 16, drop=1.25)
    p1, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SnapPlant1", loc=(-2.95, -1.8, 0.0), yaw_deg=0.0)
    snap(p1, 38, drop=1.45)
    p2, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_2a.glb", "SnapPlant2", loc=(-2.85, 1.2, 0.0))
    p2.scale = (0.65, 0.65, 0.65)
    snap(p2, 62, drop=1.40)
    st1, _, _, _ = tk.load_glb("game/assets/interior/screen_stand.glb", "SnapStand1", loc=(-2.25, 2.85, 0.0), yaw_deg=25.0)
    snap(st1, 70, drop=1.35)

    desk_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk", loc=(0.0, 4.45, 0.0), yaw_deg=0.0)
    snap(desk_root, 76, drop=1.65)
    belt_root, _, _, _ = tk.load_glb("game/assets/interior/baggage_belt.glb", "SnapBagBelt", loc=(1.42, 4.45, 0.0), yaw_deg=0.0)
    snap(belt_root, 82, drop=1.45)
    desk2_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk2", loc=(3.05, 5.45, 0.0), yaw_deg=0.0)
    snap(desk2_root, 88, drop=1.65)
    scr_root, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "CheckinInfo", loc=(-2.25, 4.85, 0.0), yaw_deg=20.0)
    snap(scr_root, 84, drop=1.55)

    # Check-in Clerks NEVER drop from ceiling! CheckinClerk briskly walks up behind the newly popped-in desk
    # and hands the Boarding Pass across the counter via quaternion-safe 2-bone IK on Forearm.R!
    clerk_root, clerk_arm, clerk_objs, clerk_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk", cloth_tint=tk.GOTTA_LIME, loc=(0.95, 6.45, 0.0), yaw_deg=-35.0
    )
    tk.animate_character_locomotion(
        clerk_root,
        clerk_arm,
        clerk_acts,
        waypoints=[
            (1, (0.95, 6.45, 0.0), -35.0),
            (38, (0.95, 6.45, 0.0), -35.0),
            (88, (-0.36, 5.46, 0.0), 4.0),
            (N, (-0.36, 5.46, 0.0), 4.0),
        ],
        frame_end=N,
        phase_offset=11.0,
    )
    tk.bind_hand_ik_target(
        scene,
        clerk_arm,
        "ClerkHandPass",
        hand="R",
        pos_keys=[
            (102, (-0.54, 5.15, 1.18)),
            (116, (-0.35, 4.92, 1.16)),
            (132, (-0.34, 4.92, 1.18)),
            (150, (-0.54, 5.18, 1.14)),
        ],
        influence_keys=[(1, 0.0), (102, 0.0), (114, 0.95), (134, 0.95), (150, 0.0)],
    )

    clerk2_root, clerk2_arm, _, clerk2_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk2", cloth_tint=tk.CLERK_NAVY, loc=(2.75, 6.48, 0.0), yaw_deg=0.0
    )
    tk.set_stationary_clip(clerk2_arm, clerk2_acts, "idle", N, speed=1.05, phase_offset=42.0)

    # 3D Boarding Pass: slides forward across CheckinDesk counter (f=112..130), then locks onto Hero's left hand!
    counter_pass = _make_boarding_pass_card(scene, "CounterPass")
    counter_pass.scale = (0.0001, 0.0001, 0.0001)
    counter_pass.keyframe_insert(data_path="scale", frame=1)
    counter_pass.keyframe_insert(data_path="scale", frame=110)
    counter_pass.scale = (1.0, 1.0, 1.0)
    counter_pass.keyframe_insert(data_path="scale", frame=113)
    counter_pass.keyframe_insert(data_path="scale", frame=131)
    counter_pass.scale = (0.0001, 0.0001, 0.0001)
    counter_pass.keyframe_insert(data_path="scale", frame=132)
    tk.key_pos(counter_pass, [
        (112, (-0.34, 4.65, 1.14)),
        (126, (-0.32, 4.02, 1.14)),
        (132, (-0.30, 3.96, 1.15)),
    ])
    events.append({"type": "stamp_ding", "frame": g0 + 124})

    # Hero passenger: sprints up concourse (f=1..104 at 3.38 m/s), 1.3s pit-stop reaching Forearm.L IK
    # to grab BoardingPass (f=112..140), then pivots right (+90 deg) & sprints out open East Security Archway!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(-0.22, -8.25, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (-0.22, -8.25, 0.0), 180.0),
            (104, (-0.32, 3.46, 0.0), 180.0),
            (136, (-0.32, 3.46, 0.0), 180.0),
            (145, (-0.32, 3.46, 0.0), 90.0),
            (N, (8.65, 3.35, 0.0)),
        ],
        frame_end=N,
    )
    tk.bind_head_look_at(
        scene,
        hero_arm,
        "HeroLookClerk",
        target_pos=(-0.36, 5.2, 1.65),
        influence_keys=[(1, 0.0), (98, 0.0), (108, 0.65), (138, 0.65), (148, 0.0)],
    )
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "HeroGrabPass",
        hand="L",
        pos_keys=[
            (108, (-0.12, 3.62, 1.16)),
            (126, (-0.30, 3.96, 1.15)),
            (132, (-0.30, 3.96, 1.16)),
            (144, (-0.08, 3.55, 1.24)),
        ],
        influence_keys=[(1, 0.0), (108, 0.0), (122, 0.98), (134, 0.98), (146, 0.0)],
    )
    hand_pass = _make_boarding_pass_card(scene, "HeroHeldPass02")
    tk.parent_prop_to_bone(hand_pass, hero_arm, "Hand.L", local_loc=(0.02, 0.06, 0.0), local_rot_deg=(0.0, 90.0, 0.0))
    hand_pass.scale = (0.0001, 0.0001, 0.0001)
    hand_pass.keyframe_insert(data_path="scale", frame=1)
    hand_pass.keyframe_insert(data_path="scale", frame=131)
    hand_pass.scale = (1.0, 1.0, 1.0)
    hand_pass.keyframe_insert(data_path="scale", frame=132)
    hand_pass.keyframe_insert(data_path="scale", frame=N)

    _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller02",
        f_ik_ranges=[(1, N)],
        pose_ranges=[(1, 100, "tow"), (105, 143, "stand"), (148, N, "tow")],
    )

    # Tracking camera leads Hero by +1.8m during f=1..96 so every snapping prop & desk pops IN FRAME ahead of him!
    cam, target = tk.make_camera(scene, "Shot02Cam", lens=32.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.85, -4.4, 1.78)),
        (96, (3.95, 0.35, 1.70)),
        (130, (3.25, 0.95, 1.66)),
        (152, (3.05, 1.45, 1.68)),
        (N, (1.95, 2.75, 1.68)),
    ])
    tk.key_pos(target, [
        (1, (-0.30, -6.6, 1.02)),
        (96, (-0.35, 3.35, 1.02)),
        (130, (-0.34, 4.25, 1.08)),
        (152, (0.45, 3.55, 1.06)),
        (N, (9.45, 3.35, 1.12)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": 102})
    events.append({"type": "roller", "frame": g0 + 146, "dur": 78})
    for f in list(range(4, 102, 7)) + list(range(148, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("start", 1, hero_objs),
        ("mid", 96, hero_objs),
        ("clerk_f311", 128, clerk_objs),
        ("hero_f311", 128, hero_objs),
        ("end", N, hero_objs),
    ]
    motion_spec = {
        "obstacle_roots": [
            ("BackScreen", b_scr),
            ("BackKiosk", b_ksk),
            ("CleanerBucket", bucket_root),
            ("SnapBench", st2),
            ("SnapPlant1", p1),
            ("SnapPlant2", p2),
            ("SnapStand1", st1),
            ("CheckinDesk", desk_root),
            ("SnapBagBelt", belt_root),
            ("CheckinDesk2", desk2_root),
            ("CheckinInfo", scr_root),
        ],
        "extra_boxes_xy": [
            ("WestGlassWall", -4.1, -3.65, -14.0, 8.0),
            ("NorthSolidWall", -4.0, 7.0, 7.65, 8.0),
            ("EastWall_SouthSeg", 6.68, 7.0, -14.0, 1.22),
            ("EastWall_NorthSeg", 6.68, 7.0, 5.48, 8.0),
        ],
        "seated_exempt": set(),
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 3 (225 frames = 7.5s): Security Two-Hand Suitcase Heave & Stanchion Queue
# ==============================================================================


def build_shot_03(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
    # Enclosed terminal hall WITH two real open north concourse doorways at x=+0.30 and x=+2.80!
    tk.build_enclosed_terminal_hall(
        scene,
        x_min=-7.5,
        x_max=4.0,
        y_min=-11.0,
        y_max=9.5,
        ceil_z=3.85,
        glass_side="right",
        open_north_wall=False,
        north_openings=[(0.30, 1.75), (2.80, 1.65)],
    )

    for wy in range(-10, 9, 2):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SWG_%d" % wy, loc=(3.95, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)

    # Open North Exit Doors (leaves slid open so Hero & SecPasserby walk through real open doorways!)
    for dtag, dx in (("SWExitDoor1", 0.30), ("SWExitDoor2", 2.80)):
        _, _, d_bn, _ = tk.load_glb("game/assets/interior/wall_door.glb", dtag, loc=(dx, 9.45, 0.0), yaw_deg=0.0)
        if "Door_Leaf_L" in d_bn:
            d_bn["Door_Leaf_L"].location.x -= 0.58
        if "Door_Leaf_R" in d_bn:
            d_bn["Door_Leaf_R"].location.x += 0.58

    sw_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "SWScreen", loc=(-1.85, 8.85, 0.0), yaw_deg=-15.0)
    sw_plt, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SWPlant", loc=(-3.45, 8.85, 0.0), yaw_deg=90.0)

    events = []
    # Security lane machines ONLY pop in (SecOfficer NEVER drops from ceiling!)
    tt_root, _, _, _ = tk.load_glb("game/assets/interior/tray_table.glb", "TrayTable", loc=(-0.55, -1.15, 0.0))
    xb_root, _, _, _ = tk.load_glb("game/assets/interior/xray_belt.glb", "XrayBelt", loc=(-0.55, 0.0, 0.0))
    pt_root, _, _, _ = tk.load_glb("game/assets/interior/pickup_table.glb", "PickupTable", loc=(-0.55, 1.15, 0.0))
    arch_root, _, _, _ = tk.load_glb("game/assets/interior/security_arch.glb", "SecArch", loc=(0.82, 0.0, 0.0))

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
    beacon.keyframe_insert(data_path="scale", frame=89)
    beacon.scale = (1.28, 1.28, 1.45)
    beacon.keyframe_insert(data_path="scale", frame=94)
    beacon.scale = (1.05, 1.05, 1.10)
    beacon.keyframe_insert(data_path="scale", frame=122)

    g_light_d = bpy.data.lights.new("ArchGreenFlash", "POINT")
    g_light_d.color = tk.srgb_to_lin(tk.SCAN_GREEN)
    g_light_d.shadow_soft_size = 0.5
    g_light = bpy.data.objects.new("ArchGreenFlash", g_light_d)
    g_light.location = (0.0, -0.25, 2.15)
    g_light.parent = arch_root
    scene.collection.objects.link(g_light)
    for f, en in [(1, 0.0), (88, 0.0), (94, 115.0), (114, 45.0), (134, 5.0)]:
        g_light_d.energy = en
        g_light_d.keyframe_insert(data_path="energy", frame=f)

    for idx, (ob, tf) in enumerate([(tt_root, 4), (xb_root, 9), (arch_root, 14), (pt_root, 19)]):
        tk.animate_snap_pop(ob, tf, drop_height=1.40)
        events.append({"type": "pop", "frame": g0 + tf + 3, "pitch": idx + 4})

    # Security Officer standing on duty (100% QUATERNION idle + smooth Forearm.L IK wave-through!)
    off_root, off_arm, off_objs, off_acts = tk.load_character(
        "tcp_male_character_07", "SecOfficer", cloth_tint=tk.OFFICER_BLUE, loc=(1.75, 1.85, 0.0), yaw_deg=-132.0
    )
    tk.set_stationary_clip(off_arm, off_acts, "idle", N, speed=1.08, phase_offset=22.0)
    tk.bind_hand_ik_target(
        scene,
        off_arm,
        "OfficerWaveThrough",
        hand="L",
        parent=off_root,
        pos_keys=[
            (86, (0.28, -0.10, 1.18)),
            (96, (0.34, -0.32, 1.56)),
            (108, (0.16, -0.40, 1.62)),
            (118, (0.32, -0.30, 1.54)),
            (130, (0.28, -0.10, 1.18)),
        ],
        influence_keys=[(1, 0.0), (86, 0.0), (95, 0.92), (118, 0.92), (130, 0.0)],
    )

    # Real Stanchion Queue Lane (`tc_metal_pole_1a` + `tc_metal_pole_chain_1a`) along x = 1.40..2.50!
    stanchions = []
    for si, sy in enumerate((-2.15, -3.90, -5.65)):
        sp, _, _, _ = tk.load_glb("game/assets/decor/tc_metal_pole_1a.glb", "QueuePoleL_%d" % si, loc=(1.38, sy, 0.0), outline_thickness=0.004)
        sp.scale = (0.55, 0.55, 0.68)
        stanchions.append(("QueuePole_%d" % si, sp))
        if si < 2:
            ch, _, _, _ = tk.load_glb("game/assets/decor/tc_metal_pole_chain_1a.glb", "QueueChainL_%d" % si, loc=(1.38, sy + 0.10, -0.12), yaw_deg=0.0, outline_thickness=0.003)
            ch.scale = (0.85, 0.95, 0.85)

    q1_root, q1_arm, _, q1_acts = tk.load_character(
        "tcp_female_character_04", "QueuePax1", cloth_tint=(0.24, 0.68, 0.66), loc=(1.98, -2.60, 0.0), yaw_deg=175.0
    )
    tk.set_stationary_clip(q1_arm, q1_acts, "idle", N, speed=1.05, phase_offset=8.0)
    # Backpack bone-parented vertically flush against QueuePax1's Spine_02 BACK (-Z in bone space!)
    qpack, _, _, _ = tk.load_glb("game/assets/interior/carry_backpack.glb", "Q1Pack", outline_thickness=0.004)
    tk.parent_prop_to_bone(qpack, q1_arm, "Spine_02", local_loc=(0.0, 0.04, -0.09), local_rot_deg=(0.0, 180.0, 0.0))

    q2_root, q2_arm, _, q2_acts = tk.load_character(
        "tcp_male_character_06", "QueuePax2", cloth_tint=(0.76, 0.52, 0.22), loc=(2.02, -3.75, 0.0), yaw_deg=182.0
    )
    tk.set_stationary_clip(q2_arm, q2_acts, "idle", N, speed=0.98, phase_offset=46.0)

    q3_root, q3_arm, _, q3_acts = tk.load_character(
        "tcp_female_character_11", "QueuePax3", cloth_tint=(0.68, 0.34, 0.64), loc=(1.95, -4.90, 0.0), yaw_deg=178.0
    )
    tk.set_stationary_clip(q3_arm, q3_acts, "idle", N, speed=1.02, phase_offset=91.0)

    # Background traveler walking north along open x = +2.80 promenade straight through open SWExitDoor2!
    bg_w, bg_wa, _, bg_wacts = tk.load_character(
        "tcp_male_character_09", "SecPasserby", cloth_tint=(0.35, 0.55, 0.82), loc=(2.80, 0.20, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(bg_w, bg_wa, bg_wacts, [(1, (2.80, 0.20, 0.0)), (N, (2.80, 10.30, 0.0))], N, phase_offset=19.0)

    # Tray + Hero Roller moving through X-ray tunnel!
    tray_root, _, _, _ = tk.load_glb("game/assets/interior/security_tray.glb", "HeroTray", loc=(-0.55, -1.15, 0.74))
    tk.animate_snap_pop(tray_root, 32, drop_height=0.55)
    tk.key_pos(tray_root, [
        (32, (-0.55, -1.15, 0.74)),
        (56, (-0.55, -1.15, 0.74)),
        (132, (-0.55, 1.15, 0.74)),
        (N, (-0.55, 1.15, 0.74)),
    ])
    tk._set_fcurves_linear(tray_root)

    # World-space HeroRoller03 so it rides smoothly from Hero's tow -> two-hand heave -> conveyor -> two-hand snatch -> tow!
    bag_root, _, bag_by_n = tk.load_roller_bag("HeroRoller03", extended=True, loc=(0.55, -4.90, 0.295), bag_tint=tk.YELLOW, bag_scale=1.35)
    tk.set_roller_handle(bag_by_n, extended=True, frame=1)
    tk.set_roller_handle(bag_by_n, extended=True, frame=35)
    tk.set_roller_handle(bag_by_n, extended=False, frame=42)
    tk.set_roller_handle(bag_by_n, extended=False, frame=148)
    tk.set_roller_handle(bag_by_n, extended=True, frame=155)

    # Uncrossed two-hand grip empties on `bag_root` (bag rz=180 -> +Y local is -Y world = Hero's LEFT when facing -X!)
    grip_side_l = bpy.data.objects.new("BagSideGrip_L", None)
    grip_side_l.parent = bag_root
    grip_side_l.location = (0.0, 0.21, 0.14)
    scene.collection.objects.link(grip_side_l)

    grip_side_r = bpy.data.objects.new("BagSideGrip_R", None)
    grip_side_r.parent = bag_root
    grip_side_r.location = (0.0, -0.21, 0.14)
    scene.collection.objects.link(grip_side_r)

    tk.key_pos(bag_root, [
        (1, (0.55, -4.94, 0.285)),
        (34, (0.54, -1.48, 0.285)),
        (40, (0.05, -1.15, 0.42)),
        (46, (-0.22, -1.15, 0.96)),    # Two-hand lift arc up & over tray rim!
        (53, (-0.52, -1.15, 0.80)),    # Settles squarely into HeroTray
        (56, (-0.55, -1.15, 0.80)),
        (132, (-0.55, 1.15, 0.80)),    # Emerges from X-ray onto PickupTable
        (138, (-0.52, 1.15, 0.80)),
        (145, (-0.18, 1.18, 0.94)),    # Lifted off PickupTable with both hands!
        (154, (0.55, 0.84, 0.285)),    # Placed onto floor 0.34m behind Hero's right heel!
        (N, (0.55, 8.56, 0.285)),
    ])
    tk.key_rot_deg(bag_root, [
        (1, (-72.0, 0.0, 180.0)),
        (35, (-72.0, 0.0, 180.0)),
        (46, (-15.0, 0.0, 180.0)),
        (53, (0.0, 0.0, 180.0)),
        (138, (0.0, 0.0, 180.0)),
        (146, (-22.0, 0.0, 180.0)),
        (154, (-72.0, 0.0, 180.0)),
        (N, (-72.0, 0.0, 180.0)),
    ])
    tk._set_fcurves_linear(bag_root)

    # Hero passenger: zero pirouettes, zero moonwalking!
    # f=1..34 sprint to TrayTable -> turn left (-90/270 deg) & two-hand heave -> brisk forward walk (+Y) through SecArch ->
    # stop at PickupTable (0.30, 1.18), turn left & two-hand grab -> sprint forward (+Y) out open SWExitDoor1!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.30, -4.60, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (0.30, -4.60, 0.0), 180.0),
            (34, (0.30, -1.15, 0.0), -90.0),
            (53, (0.30, -1.15, 0.0), -90.0),
            (63, (0.30, -1.15, 0.0), 140.0),
            (76, (0.82, -0.62, 0.0)),
            (114, (0.82, 0.85, 0.0)),
            (132, (0.30, 1.18, 0.0), -90.0),
            (148, (0.30, 1.18, 0.0), -90.0),
            (156, (0.30, 1.18, 0.0), 180.0),
            (N, (0.30, 8.90, 0.0)),
        ],
        frame_end=N,
    )
    # Towed Pull_Top grip during approach (f=1..35) and exit sprint (f=154..N)
    tk.bind_hand_ik_to_roller(hero_arm, bag_by_n["Pull_Top"], [(1, 35), (154, N)], hand="R")
    # Two-hand heave onto tray (f=39..53) AND two-hand snatch off pickup table (f=137..150)!
    two_hand_inf = [
        (1, 0.0),
        (36, 0.0), (40, 0.96), (52, 0.96), (57, 0.0),
        (134, 0.0), (139, 0.96), (149, 0.96), (153, 0.0),
    ]
    tk.bind_hand_ik_target(scene, hero_arm, "HeaveBagL", hand="L", target_obj=grip_side_l, influence_keys=two_hand_inf)
    tk.bind_hand_ik_target(scene, hero_arm, "HeaveBagR", hand="R", target_obj=grip_side_r, influence_keys=two_hand_inf)

    # Subtle head-turns on Officer & Queue passengers watching the frantic Hero!
    for idx_q, q_arm in enumerate((off_arm, q1_arm, q2_arm, q3_arm)):
        tk.bind_head_look_at(scene, q_arm, "WatchHero3_%d" % idx_q, target_obj=hero_root, max_inf=0.52)

    cam, target = tk.make_camera(scene, "Shot03Cam", lens=34.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (-4.35, -4.95, 1.82)),
        (52, (-4.45, -2.35, 1.76)),
        (110, (-4.55, -0.85, 1.74)),
        (155, (-4.45, 0.45, 1.72)),
        (N, (-4.25, 3.65, 1.74)),
    ])
    tk.key_pos(target, [
        (1, (0.35, -3.45, 1.06)),
        (52, (0.05, -0.95, 1.04)),
        (110, (0.55, 0.45, 1.08)),
        (155, (0.05, 1.25, 1.06)),
        (N, (0.30, 7.65, 1.12)),
    ])

    events.extend([
        {"type": "roller", "frame": g0 + 1, "dur": 34},
        {"type": "skid", "frame": g0 + 33},
        {"type": "conveyor", "frame": g0 + 56, "dur": 76},
        {"type": "scanner_beep", "frame": g0 + 92},
        {"type": "bag_snatch", "frame": g0 + 144},
        {"type": "roller", "frame": g0 + 154, "dur": 70},
    ])
    for f in list(range(2, 34, 7)) + list(range(62, 130, 10)) + list(range(155, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("start", 1, hero_objs),
        ("mid", 108, hero_objs),
        ("officer_f503", 108, off_objs),
        ("end", 210, hero_objs),
    ]
    motion_spec = {
        "obstacle_roots": [
            ("SWScreen", sw_scr),
            ("SWPlant", sw_plt),
            ("TrayTable", tt_root),
            ("XrayBelt", xb_root),
            ("PickupTable", pt_root),
        ] + stanchions,
        "extra_boxes_xy": [
            ("EastGlassWall", 3.85, 4.2, -11.5, 10.0),
            ("NorthWall_Left", -7.8, -0.58, 9.35, 9.65),
            ("NorthWall_Mid", 1.18, 1.97, 9.35, 9.65),
            ("NorthWall_Right", 3.63, 4.3, 9.35, 9.65),
        ],
        "seated_exempt": set(),
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 4 (195 frames = 6.5s): Bustling Gate Concourse Sprint & Boarding Pass Flash
# ==============================================================================


def build_shot_04(g0):
    N = 195
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.08, indoor=True)
    tk.build_enclosed_terminal_hall(scene, x_min=-5.2, x_max=8.5, y_min=-13.5, y_max=5.5, ceil_z=3.85, glass_side="left", open_north_wall=True)

    for gx in (-5, -4, -3, -2, 2, 3, 4, 5, 6, 7):
        tk.load_glb("game/assets/interior/wall_glass.glb", "AirGlass_%d" % gx, loc=(float(gx), 5.5, 0.0), yaw_deg=0.0)
    for wx in range(-12, 6, 2):
        wgl, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SideGlassL_%d" % wx, loc=(-5.15, float(wx), 0.0), yaw_deg=90.0)
        wgl.scale = (2.0, 1.0, 1.0)

    # Sunlit Airside Apron + Parked Gotta Air Jet visible right outside the Gate C glass!
    tk.load_glb("game/assets/airside/tp_runway_02a.glb", "OutsideApron", loc=(0.0, 38.0, -0.02), yaw_deg=0.0, outline_thickness=0.0)
    tk.make_box(scene, "OutsideGrass", (260.0, 180.0, 0.08), (0.0, 120.0, -0.06), tk.horizon_grass_mat(), bevel=0.0)
    ext_plane_r, ext_plane_objs, ext_plane_bn, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "OutsideGottaJet", loc=(1.8, 24.5, 0.0), yaw_deg=-68.0, outline_thickness=0.004
    )
    _apply_gotta_air_livery(ext_plane_objs)
    _spin_jet_fans(scene, ext_plane_r, ext_plane_bn, N, deg_per_frame=32.0)
    tk.load_glb("game/assets/airside/props/pushback_tug.glb", "OutsideTug", loc=(-6.5, 16.0, 0.0), yaw_deg=25.0)

    # Cozy concourse interior with real coffee cups, properly oriented cafe patron, and staggered seating!
    cafe_c, _, _, _ = tk.load_glb("game/assets/interior/cafe_counter.glb", "Cafe", loc=(-3.35, -7.2, 0.0), yaw_deg=90.0)
    cafe_t, _, _, _ = tk.load_glb("game/assets/interior/cafe_table.glb", "CafeTbl1", loc=(-2.65, -4.6, 0.0), yaw_deg=90.0)
    # Cozy ceramic coffee mug + saucer on CafeTbl1 right in front of CafeSitPax!
    tk.make_box(scene, "CafeSaucer", (0.15, 0.15, 0.018), (-2.65, -4.74, 0.76), tk.toon_rgb_mat("mug_white", tk.CREAM), bevel=0.006)
    tk.make_box(scene, "CafeMug", (0.095, 0.095, 0.115), (-2.65, -4.74, 0.82), tk.toon_rgb_mat("mug_coral", tk.HERO_CORAL), bevel=0.015, outline=0.003)

    seats1, _, _, _ = tk.load_glb("game/assets/interior/seat_row.glb", "Seats1", loc=(-2.75, -1.8, 0.0), yaw_deg=90.0)
    seats2, _, _, _ = tk.load_glb("game/assets/interior/seat_row.glb", "Seats2", loc=(-2.75, 1.2, 0.0), yaw_deg=90.0)
    in_tree, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "IndoorTree", loc=(-3.55, 3.35, 0.0))
    tk.load_glb("game/assets/interior/wall_door.glb", "BackHallDoor", loc=(0.0, -13.4, 0.0), yaw_deg=0.0)
    df_shelf, _, _, _ = tk.load_glb("game/assets/interior/duty_free_shelf.glb", "DutyFreeBg", loc=(3.2, -9.8, 0.0), yaw_deg=-90.0)

    bar_r, bar_a, _, bar_acts = tk.load_character("tcp_female_character_07", "CafeBarista", cloth_tint=(0.68, 0.36, 0.20), loc=(-4.25, -7.2, 0.0), yaw_deg=90.0)
    tk.set_stationary_clip(bar_a, bar_acts, "idle", N, speed=1.08, phase_offset=15.0)
    c1_r, c1_a, _, c1_acts = tk.load_character("tcp_female_character_08", "CafePax", cloth_tint=(0.78, 0.38, 0.62), loc=(-2.35, -7.2, 0.0), yaw_deg=-90.0)
    tk.set_stationary_clip(c1_a, c1_acts, "idle", N, speed=1.02, phase_offset=52.0)

    # CafeSitPax seated ON Mount_SitRoot_L (-2.65, -5.15) with yaw_deg=180.0 FACING CafeTbl1 (+Y)!
    c2_r, c2_a, _, c2_acts = tk.load_character("tcp_male_character_04", "CafeSitPax", cloth_tint=(0.30, 0.62, 0.54), loc=(-2.65, -5.15, 0.0), yaw_deg=180.0)
    tk.set_stationary_clip(c2_a, c2_acts, "sit_idle", N, speed=1.0, phase_offset=24.0)

    s1_r, s1_a, _, s1_acts = tk.load_character("tcp_female_character_01", "SitPax1", cloth_tint=(0.45, 0.66, 0.92), loc=(-2.42, -2.4, 0.0), yaw_deg=90.0)
    tk.set_stationary_clip(s1_a, s1_acts, "sit_idle", N, speed=0.98, phase_offset=0.0)
    s2_r, s2_a, _, s2_acts = tk.load_character("tcp_male_character_03", "SitPax2", cloth_tint=(0.86, 0.68, 0.25), loc=(-2.42, -1.1, 0.0), yaw_deg=90.0)
    tk.set_stationary_clip(s2_a, s2_acts, "sit_idle", N, speed=1.04, phase_offset=38.0)
    s3_r, s3_a, _, s3_acts = tk.load_character("tcp_female_character_09", "SitPax3", cloth_tint=(0.88, 0.48, 0.42), loc=(-2.42, 0.8, 0.0), yaw_deg=90.0)
    tk.set_stationary_clip(s3_a, s3_acts, "sit_idle", N, speed=0.95, phase_offset=74.0)

    stroll_r, stroll_a, _, stroll_acts = tk.load_character("tcp_male_character_05", "ConcourseStroller", cloth_tint=(0.38, 0.46, 0.72), loc=(-1.18, -11.2, 0.0), yaw_deg=180.0)
    tk.animate_character_locomotion(stroll_r, stroll_a, stroll_acts, [(1, (-1.18, -11.2, 0.0)), (N, (-1.18, -2.6, 0.0))], N, phase_offset=11.0)

    events = [{"type": "pa_chime", "frame": g0 + 6}]

    # Gate Desk, Doors & Overhead Sign pop into place ahead of Hero (GateAgent NEVER drops from ceiling!)
    gd_root, _, _, _ = tk.load_glb("game/assets/interior/gate_desk.glb", "GateDesk", loc=(-2.08, 3.75, 0.0), yaw_deg=-10.0)
    tk.animate_snap_pop(gd_root, 24, drop_height=1.50)
    events.append({"type": "pop", "frame": g0 + 27, "pitch": 8})

    door_root, _, door_by_n, _ = tk.load_glb("game/assets/interior/wall_door.glb", "GateDoor", loc=(0.12, 5.5, 0.0), yaw_deg=0.0)
    door_root.scale = (1.65, 1.0, 1.08)
    tk.animate_snap_pop(door_root, 34, drop_height=1.60)
    events.append({"type": "pop", "frame": g0 + 37, "pitch": 10})

    sign_root = bpy.data.objects.new("GateSign_ROOT", None)
    sign_root.location = (0.12, 5.15, 2.75)
    scene.collection.objects.link(sign_root)
    tk.make_box(scene, "GateSignBox", (2.85, 0.18, 0.56), (0.0, 0.0, 0.0), tk.toon_rgb_mat("gs_navy", tk.NAVY), bevel=0.03, parent=sign_root, outline=0.005)
    gt_txt = tk.make_nunito_text_3d(scene, "GATE C · OSLO", 0.28, 0.013, tk.emissive_mat("gs_lime", tk.GOTTA_LIME, 1.45), extrude=0.02, parent=sign_root)
    gt_txt.rotation_euler = (math.radians(90), 0.0, 0.0)
    gt_txt.location = (0.0, -0.11, 0.0)
    tk.animate_snap_pop(sign_root, 42, drop_height=1.10)
    events.append({"type": "pop", "frame": g0 + 45, "pitch": 12})

    # GateAgent standing beside GateDesk facing the boarding lane (yaw=68 deg) holding out a handheld scanner via Forearm.R IK!
    ga_root, ga_arm, _, ga_acts = tk.load_character(
        "tcp_female_character_07", "GateAgent", cloth_tint=tk.GOTTA_LIME, loc=(-0.62, 4.35, 0.0), yaw_deg=68.0
    )
    tk.set_stationary_clip(ga_arm, ga_acts, "idle", N, speed=1.10, phase_offset=31.0)
    scanner_ob = tk.make_box(scene, "GateScannerGun", (0.06, 0.14, 0.05), (0.0, 0.0, 0.0), tk.toon_rgb_mat("scan_gun", tk.NAVY), bevel=0.01, outline=0.003)
    tk.parent_prop_to_bone(scanner_ob, ga_arm, "Hand.R", local_loc=(0.0, 0.05, 0.0), local_rot_deg=(0.0, 0.0, 0.0))
    tk.bind_hand_ik_target(
        scene,
        ga_arm,
        "AgentScanHold",
        hand="R",
        parent=ga_root,
        pos_keys=[
            (1, (-0.18, -0.26, 1.24)),
            (118, (-0.14, -0.36, 1.32)),
            (145, (-0.12, -0.40, 1.36)),
            (172, (-0.22, -0.34, 1.54)),
            (N, (-0.18, -0.28, 1.30)),
        ],
        influence_keys=[(1, 0.85), (N, 0.85)],
    )

    leaf_l = door_by_n.get("Door_Leaf_L")
    leaf_r = door_by_n.get("Door_Leaf_R")
    if leaf_l and leaf_r:
        ll0, lr0 = Vector(leaf_l.location), Vector(leaf_r.location)
        tk.key_pos(leaf_l, [(1, ll0), (80, ll0), (112, ll0 + Vector((-0.65, 0.0, 0.0))), (N, ll0 + Vector((-0.65, 0.0, 0.0)))])
        tk.key_pos(leaf_r, [(1, lr0), (80, lr0), (112, lr0 + Vector((0.65, 0.0, 0.0))), (N, lr0 + Vector((0.65, 0.0, 0.0)))])
    events.append({"type": "door_whoosh", "frame": g0 + 84})

    # Hero sprints full tilt (3.35 m/s, stride-locked!) from y=-11.2 straight out through open GateDoor onto the apron (y=+10.4),
    # holding BoardingPass in Hand.L and raising Forearm.L IK to flash it past GateAgent's scanner without stopping!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.15, -11.2, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[(1, (0.15, -11.2, 0.0)), (N, (0.12, 10.4, 0.0))],
        frame_end=N,
    )
    _attach_towed_roller(hero_root, hero_arm, "HeroRoller04", f_ik_ranges=[(1, N)])
    pass04 = _make_boarding_pass_card(scene, "HeroHeldPass04")
    tk.parent_prop_to_bone(pass04, hero_arm, "Hand.L", local_loc=(0.02, 0.06, 0.0), local_rot_deg=(0.0, 90.0, 0.0))
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "FlashPassLeft",
        hand="L",
        parent=hero_root,
        pos_keys=[
            (116, (0.26, -0.14, 1.22)),
            (134, (0.42, -0.22, 1.44)),
            (150, (0.40, -0.20, 1.42)),
            (166, (0.26, -0.14, 1.22)),
        ],
        influence_keys=[(1, 0.0), (116, 0.0), (130, 0.92), (150, 0.92), (166, 0.0)],
    )
    events.append({"type": "scanner_beep", "frame": g0 + 140})

    # Seated passengers & GateAgent turn their heads naturally watching Hero sprint past!
    for idx_s, s_arm in enumerate((s1_arm_ref := s1_a, s2_a, s3_a, ga_arm)):
        tk.bind_head_look_at(scene, s_arm, "ConcourseWatch_%d" % idx_s, target_obj=hero_root, max_inf=0.56)

    cam, target = tk.make_camera(scene, "Shot04Cam", lens=32.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.25, -6.2, 1.42)),
        (98, (3.65, -1.2, 1.48)),
        (N, (1.15, 1.85, 1.54)),
    ])
    tk.key_pos(target, [
        (1, (-0.05, -10.4, 1.04)),
        (98, (-0.10, -0.4, 1.10)),
        (N, (0.12, 8.2, 1.18)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": N - 2})
    for f in range(3, N, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("start", 1, hero_objs),
        ("mid", 98, hero_objs),
        ("end", 150, hero_objs),
    ]
    motion_spec = {
        "obstacle_roots": [
            ("Cafe", cafe_c),
            ("IndoorTree", in_tree),
            ("DutyFreeBg", df_shelf),
            ("GateDesk", gd_root),
        ],
        "extra_boxes_xy": [
            ("WestGlassWall", -5.5, -5.05, -14.0, 5.6),
            ("NorthGlassLeft", -5.4, -1.25, 5.38, 5.65),
            ("NorthGlassRight", 1.50, 8.8, 5.38, 5.65),
        ],
        "seated_exempt": {"CHAR_CafeSitPax", "CHAR_SitPax1", "CHAR_SitPax2", "CHAR_SitPax3"},
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 5 (210 frames = 7.0s): Apron Stand Wheeled Airstairs -> Runway Takeoff & Gear Retract
# ==============================================================================


def build_shot_05(g0):
    N = 210
    CUT_F = 89  # f=1..88: Apron Stand Boarding & Tug Stair Pullback | f=89..210: Striped Runway Takeoff & Gear Retraction!
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.18, indoor=False)
    tk.make_box(scene, "AirfieldGrass", (1200.0, 1200.0, 0.12), (0.0, 0.0, -0.07), tk.horizon_grass_mat(), bevel=0.0)
    tk.add_horizon_hills_and_treeline(scene)

    # 1. Paved Concrete Apron Stand on West Side (x = -36..-6, y = -8..+54) right in front of Terminal Building!
    tk.make_box(scene, "ApronConcretePad", (34.0, 64.0, 0.08), (-21.0, 22.0, -0.035), tk.toon_rgb_mat("apron_pad", (0.36, 0.39, 0.44)), bevel=0.0)
    # Yellow stand lead-in line on apron
    tk.make_box(scene, "StandLeadLine", (0.18, 28.0, 0.015), (-22.0, 18.0, 0.01), tk.toon_rgb_mat("stand_yellow", tk.YELLOW), bevel=0.0)

    # 2. Active Striped Runway along x = +18.0 (`tp_runway_02a` spans 64m along Y, separated cleanly from Apron Stand!)
    for ry in (32.0, -32.0, -96.0, -160.0, -224.0, -288.0, -352.0):
        tk.load_glb("game/assets/airside/tp_runway_02a.glb", "Runway_%d" % int(ry), loc=(18.0, ry, 0.0), yaw_deg=90.0, outline_thickness=0.0)

    tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "BgTerminal", loc=(-22.0, 68.0, 0.0), yaw_deg=0.0, outline_thickness=0.004)
    bg_p3_r, bg_p3_objs, _, _ = tk.load_glb("game/assets/planes/tp_plane_03a.glb", "BgPropPlane", loc=(-32.0, 34.0, 0.0), yaw_deg=-25.0, outline_thickness=0.004)
    _apply_gotta_air_livery(bg_p3_objs)
    tk.load_glb("game/assets/vehicles/tp_loading_truck_01a.glb", "BgTruck", loc=(-28.5, 22.0, 0.0), yaw_deg=55.0, outline_thickness=0.004)
    tk.load_glb("game/assets/airside/props/taxi_sign.glb", "TaxiSignShoulder", loc=(51.5, -22.0, 0.0), yaw_deg=-55.0)

    tk.add_toon_clouds(scene, [
        (-75, -320, 56, 3.2),
        (5, -360, 66, 3.6),
        (65, -340, 58, 3.0),
    ])

    # ---- PART A (f = 1..88): APRON STAND BOARDING (-22.0, +18.0) ----
    stand_jet_r, stand_jet_objs, stand_jet_bn, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "StandGottaJet", loc=(-22.0, 18.0, 0.0), yaw_deg=0.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(stand_jet_objs)
    _spin_jet_fans(scene, stand_jet_r, stand_jet_bn, N, deg_per_frame=38.0)
    _setup_jet_landing_gear(scene, stand_jet_r, stand_jet_bn, mode="parked")

    # Dark interior cabin liner placed INSIDE the center aisle (x_local = -0.35) so Hero physically runs
    # 0.85m THROUGH the real open fuselage doorway (x_local = +1.37 -> +0.25) into the dark interior at 1.0 scale!
    tk.make_box(
        scene,
        "CabinInteriorDarkWall",
        (0.12, 3.20, 2.05),
        (-0.35, -7.80, 2.55),
        tk.toon_rgb_mat("cabin_dark_aisle", (0.05, 0.07, 0.13)),
        bevel=0.01,
        parent=stand_jet_r,
    )
    tk.make_box(
        scene,
        "CabinInteriorFloor",
        (1.85, 3.20, 0.08),
        (0.45, -7.80, 1.54),
        tk.toon_rgb_mat("cabin_floor_dark", (0.10, 0.13, 0.20)),
        bevel=0.01,
        parent=stand_jet_r,
    )

    # Real factory fuselage door `TP_Plane_05A_Door`: swings OUTWARD forward (+118 deg) against outer nose fuselage
    # so the dark cabin doorway is 100% open for Hero to run inside, then seals flush at f=58..72!
    s_door = stand_jet_bn.get("TP_Plane_05A_Door")
    if s_door is not None:
        dmw = s_door.matrix_world.copy()
        dpiv = bpy.data.objects.new("StandJetDoorPivot", None)
        scene.collection.objects.link(dpiv)
        dpiv.parent = stand_jet_r
        dpiv.location = (1.36, -9.02, 1.58)
        bpy.context.view_layer.update()
        s_door.parent = dpiv
        s_door.matrix_world = dmw
        tk.key_rot_deg(dpiv, [
            (1, (0.0, 0.0, 118.0)),
            (58, (0.0, 0.0, 118.0)),
            (72, (0.0, 0.0, 0.0)),
            (N, (0.0, 0.0, 0.0)),
        ])

    # Wheeled Mobile Airstairs + Hitched Closed-Cab Yellow Ground Tug (tug pulls stairs back +3.0m at f=68..88!)
    stairs_rig = bpy.data.objects.new("TugAndStairs_Assembly", None)
    stairs_rig.location = (-20.60, 9.38, 0.0)
    scene.collection.objects.link(stairs_rig)

    stairs_root, stair_wheels = _build_wheeled_airstairs(scene, "MobileAirstairs_ROOT", loc=(0.0, 0.0, 0.0))
    stairs_root.parent = stairs_rig

    tug_r, _, _, _ = tk.load_glb("game/assets/airside/props/pushback_tug.glb", "StairTug", loc=(4.85, 0.0, 0.0), yaw_deg=90.0, outline_thickness=0.004)
    tug_r.parent = stairs_rig

    tk.key_pos(stairs_rig, [
        (1, (-20.60, 9.38, 0.0)),
        (68, (-20.60, 9.38, 0.0)),
        (88, (-17.60, 9.38, 0.0)),
        (N, (-17.60, 9.38, 0.0)),
    ])
    for wpiv in stair_wheels:
        tk.key_rot_deg(wpiv, [(1, (0, 0, 0)), (68, (0, 0, 0)), (88, (0, 360.0, 0)), (N, (0, 360.0, 0))])

    # Ramp Marshaller in hi-vis lime waving dual orange marshalling wands via 2-bone IK!
    marsh_r, marsh_a, _, marsh_acts = tk.load_character(
        "tcp_male_character_07", "RampMarshaller", cloth_tint=tk.GOTTA_LIME, loc=(-17.2, 5.2, 0.0), yaw_deg=145.0
    )
    tk.set_stationary_clip(marsh_a, marsh_acts, "idle", N, speed=1.1, phase_offset=5.0)
    wand_m = tk.emissive_mat("marsh_wand", (1.0, 0.42, 0.08), strength=1.8)
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        wand = tk.make_box(scene, "MarshallWand_" + side, (0.04, 0.36, 0.04), (0.0, 0.0, 0.0), wand_m, bevel=0.01, outline=0.003)
        tk.parent_prop_to_bone(wand, marsh_a, "Hand." + side, local_loc=(0.0, 0.16, 0.0))
        tk.bind_hand_ik_target(
            scene,
            marsh_a,
            "MarshallWave",
            hand=side,
            parent=marsh_r,
            pos_keys=[
                (1, (sgn * 0.36, -0.24, 1.62)),
                (22, (sgn * 0.22, -0.28, 1.84)),
                (44, (sgn * 0.40, -0.24, 1.60)),
                (66, (sgn * 0.22, -0.28, 1.84)),
                (88, (sgn * 0.34, -0.20, 1.72)),
            ],
            influence_keys=[(1, 0.92), (N, 0.92)],
        )

    # Hero passenger: sprints across apron to foot of stairs (-17.55, 9.38), retracts handle & lifts suitcase in right hand
    # CLEAR above the 7 treads (`carry` mode!), bounds up to top deck (-20.20, 9.38, 1.54) at f=46, and runs 0.85m
    # physically INSIDE the cabin aisle (-21.85, 9.38 -> -21.95, 10.65, z=1.56) at 1.0 scale!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(-15.35, 11.45, 0.0), yaw_deg=-52.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (-15.35, 11.45, 0.0)),
            (20, (-17.65, 9.38, 0.0)),
            (46, (-20.25, 9.38, 1.54)),
            (54, (-21.75, 9.38, 1.56)),
            (62, (-21.95, 10.55, 1.56), 180.0),
            (N, (-21.95, 10.55, 1.56), 180.0),
        ],
        frame_end=N,
    )
    _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller05",
        f_ik_ranges=[(1, 62)],
        pose_ranges=[(1, 18, "tow"), (22, N, "carry")],
    )

    # ---- PART B (f = 89..210): ACTIVE STRIPED RUNWAY ROLL, LIFTOFF & GEAR RETRACTION (x = +18.0) ----
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "GottaAirJet", loc=(18.0, 8.0, 0.0), yaw_deg=0.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=56.0)
    _setup_jet_landing_gear(scene, plane_root, plane_by_n, mode="takeoff_retract", f_roll_start=CUT_F, f_retract_start=144, f_retract_end=180, f_end=N)

    # Crisp high-speed takeoff roll (~34 m/s average: y = -6 -> -146m over 4.0s!), nose-up rotation & climb to z=22.5m!
    tk.key_pos(plane_root, [
        (1, (18.0, -4.0, 0.0)),
        (CUT_F, (18.0, -4.0, 0.0)),
        (124, (18.0, -38.0, 0.0)),
        (154, (18.0, -76.0, 3.8)),
        (182, (18.0, -112.0, 11.8)),
        (N, (18.0, -150.0, 22.5)),
    ])
    tk.key_rot_deg(plane_root, [
        (1, (0.0, 0.0, 0.0)),
        (120, (0.0, 0.0, 0.0)),
        (150, (-13.5, 0.0, 0.0)),
        (N, (-15.0, 4.0, 0.0)),
    ])
    tk._set_fcurves_linear(plane_root)

    # Camera: crisp CONSTANT cut at f=88 -> f=89 from Apron Stand Boarding Cam to Active Runway Takeoff Tracking Cam!
    cam, target = tk.make_camera(scene, "Shot05Cam", lens=34.0, fstop=3.2)
    tk.key_pos(cam, [
        (1, (-10.8, 3.2, 2.15)),
        (56, (-13.0, 3.8, 2.45)),
        (CUT_F - 1, (-12.2, 3.6, 2.55)),
        (CUT_F, (58.0, -22.0, 4.2)),
        (145, (58.0, -88.0, 8.2)),
        (N, (59.5, -168.0, 19.5)),
    ])
    tk.key_pos(target, [
        (1, (-16.6, 10.4, 1.18)),
        (56, (-20.2, 9.4, 1.98)),
        (CUT_F - 1, (-19.4, 9.4, 1.90)),
        (CUT_F, (18.0, -4.0, 3.2)),
        (124, (18.0, -38.0, 3.6)),
        (154, (18.0, -76.0, 6.2)),
        (N, (18.0, -150.0, 23.0)),
    ])
    # Set CONSTANT interpolation specifically on the cut keyframe (frame 88 -> 89) so zero camera smear across the airfield!
    for ob_c in (cam, target):
        ad = ob_c.animation_data
        if ad and ad.action and hasattr(ad.action, "layers"):
            for layer in ad.action.layers:
                for strip in layer.strips:
                    if hasattr(strip, "channelbags"):
                        for bag in strip.channelbags:
                            for fc in bag.fcurves:
                                for kp in fc.keyframe_points:
                                    kp.interpolation = "CONSTANT" if int(round(kp.co.x)) == (CUT_F - 1) else "LINEAR"

    events = [
        {"type": "jet_idle", "frame": g0 + 1, "dur": 86},
        {"type": "roller", "frame": g0 + 1, "dur": 20},
        {"type": "step_leap", "frame": g0 + 22},
        {"type": "door_seal", "frame": g0 + 68},
        {"type": "jet_spool", "frame": g0 + CUT_F, "dur": N - CUT_F},
        {"type": "takeoff_whoosh", "frame": g0 + 136},
    ]
    for f in range(3, 50, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    plane_core = [plane_by_n["TP_Plane_05A_Fuselage"]]
    prove_targets = [
        ("start_hero", 1, hero_objs),
        ("board_f856", 44, hero_objs),
        ("mid_jet", 115, plane_core),
        ("end_jet", N, plane_core),
    ]
    motion_spec = {
        "obstacle_roots": [],
        "extra_boxes_xy": [],
        "seated_exempt": set(),
        "exempt_ranges": {"CHAR_Hero": [(21, N)]},
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 6 (165 frames = 5.5s): Crisp Sky Climb (Gear Stowed!) + Logo Slam & Wishlist
# ==============================================================================


def build_shot_06(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.22, indoor=False)

    cloud_field = [
        (-52, -78, 16, 3.2),
        (38, -68, 14, 2.9),
        (-12, -96, 12, 3.8),
        (54, -105, 25, 2.9),
        (-68, -118, 26, 3.4),
        (8, -128, 19, 4.0),
        (-24, -52, 11, 2.1),
        (26, -50, 12, 2.2),
    ]
    tk.add_toon_clouds(scene, cloud_field, seed_scale=1.15)

    # Gotta Air Jet with 100% RETRACTED landing gear soaring at crisp ~29.5 m/s (162m over 5.5s!) across the upper golden sky!
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "SkyGottaJet", loc=(54.0, -58.0, 22.0), yaw_deg=-64.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=58.0)
    _setup_jet_landing_gear(scene, plane_root, plane_by_n, mode="stowed")

    vmat = tk.soft_vapor_trail_mat()
    fus = plane_by_n["TP_Plane_05A_Fuselage"]
    for side, wx in (("L", 13.6), ("R", -13.6)):
        rib = tk.make_box(scene, "SoftVapor_" + side, (0.24, 22.0, 0.05), (wx, 17.5, 1.85), vmat, bevel=0.0, parent=plane_root, outline=0.0)
        rib.visible_shadow = False

    # 162.4 meters in 5.50s = 29.5 m/s crisp forward jet climb!
    tk.key_pos(plane_root, [
        (1, (54.0, -58.0, 22.0)),
        (N, (-86.0, -136.0, 44.5)),
    ])
    # Forward direction (-140, -78, +22.5): atan2(-140, 78) = -60.9 deg yaw, nose-up climb rx = -9.5 deg, banking roll ry = -16 -> -8 deg!
    tk.key_rot_deg(plane_root, [
        (1, (-9.5, -16.0, -61.0)),
        (N, (-10.5, -8.0, -61.0)),
    ])
    tk._set_fcurves_linear(plane_root)

    cam, target = tk.make_camera(scene, "Shot06Cam", lens=35.0, fstop=4.0, dof_dist=82.0)
    tk.key_pos(cam, [(1, (18.0, 6.0, 16.5)), (N, (-18.0, -12.0, 22.0))])
    tk.key_pos(target, [(1, (48.0, -58.0, 16.8)), (N, (-78.0, -134.0, 32.5))])
    tk._set_fcurves_linear(cam)
    tk._set_fcurves_linear(target)

    events = [
        {"type": "sky_wind", "frame": g0 + 1, "dur": N},
        {"type": "logo_slam", "frame": g0 + 18},
        {"type": "badge_pop", "frame": g0 + 42},
    ]

    plane_core = [fus]
    prove_targets = [
        ("start", 1, plane_core),
        ("mid", 83, plane_core),
        ("end", N, plane_core),
    ]
    motion_spec = {"obstacle_roots": [], "extra_boxes_xy": [], "seated_exempt": set()}
    return scene, cam, prove_targets, None, events, motion_spec


SHOT_BUILDERS = [
    build_shot_01,
    build_shot_02,
    build_shot_03,
    build_shot_04,
    build_shot_05,
    build_shot_06,
]
