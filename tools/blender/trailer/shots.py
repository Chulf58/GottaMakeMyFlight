"""Six pre-rendered 3D CG story shots for the Gotta Make My Flight AAA teaser trailer (v5 post-audit rebuild).

Timeline (30 fps, 1185 frames = 39.50 seconds total, zero gameplay HUD/UI):
  Shot 1 (f   1..165, 5.50s): Curb Drop-off, Ticking Board ('GOTTA AIR 101 · FINAL CALL!') & Sprint Inside
  Shot 2 (f 166..390, 7.50s): Two Point Terminal Pop-In Ahead of Hero + Direct Hand-to-Hand Pass Handoff
  Shot 3 (f 391..615, 7.50s): Security Two-Hand Suitcase Heave, Stanchion Queue & Emerald Arch Wave
  Shot 4 (f 616..810, 6.50s): Bustling Gate Concourse Sprint, Boarding Pass Flash & Open Gate Doors
  Shot 5 (f 811..1020, 7.00s): Apron Integrated Airstair Boarding -> Accelerating Left-to-Right Takeoff
  Shot 6 (f 1021..1185, 5.50s): Crisp Left-to-Right Sky Climb (Gear Stowed) + Option A Logo & Wishlist Badge
"""

import math
import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

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
    STRICTLY to exterior airframe meshes (preserving cabin seats, tables, toilet, yokes, levers,
    wheels, landing gear struts, and inner bay doors, `F-14`)."""
    gmat = tk.gotta_air_plane_mat()
    tp_base = tk.toon_atlas_mat("tp_atlas_1a_d.png")
    for o in plane_objs:
        if o.type != "MESH" or not tk.is_exterior_airframe_mesh(o.name):
            continue
        for slot in o.material_slots:
            if slot.material == tp_base:
                slot.material = gmat


def _spin_jet_fans(scene, plane_root, plane_by_name, f_end, deg_per_frame=48.0):
    """Spin TP_Plane_05A_Fan.L and Fan.R around their local Y (forward-aft) turbofan axis."""
    bpy.context.view_layer.update()
    pinv = plane_root.matrix_world.inverted()
    for side, sign in (("L", 1.0), ("R", -1.0)):
        fan = plane_by_name.get("TP_Plane_05A_Fan." + side)
        if fan is None:
            continue
        mw = fan.matrix_world.copy()
        piv = bpy.data.objects.new("FanSpinPivot_" + side, None)
        scene.collection.objects.link(piv)
        piv.parent = plane_root
        piv.location = pinv @ mw.translation
        bpy.context.view_layer.update()
        fan.parent = piv
        fan.matrix_world = mw
        piv.rotation_mode = "XYZ"
        piv.rotation_euler = (0.0, 0.0, 0.0)
        piv.keyframe_insert(data_path="rotation_euler", frame=1)
        piv.rotation_euler = (0.0, math.radians(sign * deg_per_frame * f_end), 0.0)
        piv.keyframe_insert(data_path="rotation_euler", frame=f_end)
        tk._set_fcurves_linear(piv)


def _setup_jet_landing_gear(
    scene,
    plane_root,
    plane_by_n,
    mode="parked",
    f_roll_start=89,
    f_retract_start=144,
    f_retract_end=178,
    f_end=210,
):
    """Rig `tp_plane_05a` nose and main landing gear + ALL 6 wheel bay doors (`Hatch_Ext_*` AND `Hatch_Int_*`)
    around their measured hull-seam hinges (`F-09`):
    - `parked`: gear down & locked on apron; inner transit hatches closed flush so nothing hangs under belly.
    - `takeoff_retract`: wheels spin on runway roll, struts retract cleanly into bays after liftoff, all 6
      bay doors close flush with belly contour, and internal wheels/struts hide once stowed inside.
    - `stowed`: all 6 bay doors visible & flush (`0` belly holes, `0` tire bulges) for Shot 6 sky climb.
    """
    bpy.context.view_layer.update()

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
                    (f_retract_start + 8, (2160.0, 0.0, 0.0)),
                    (f_end, (2280.0, 0.0, 0.0)),
                ])

    # Exact hull-seam hinge pivots and closed flush angles measured on `tp_plane_05a.glb`:
    ext_f_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_F", (0.26, -10.95, 1.455))
    ext_l_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_R.L", (2.11, 2.20, 1.035))
    ext_r_piv = _pivot_part("TP_Plane_05A_Hatch_Ext_R.R", (-2.11, 2.20, 1.035))
    int_f_piv = _pivot_part("TP_Plane_05A_Hatch_Int_F", (0.0, -10.08, 1.425))
    int_l_piv = _pivot_part("TP_Plane_05A_Hatch_Int_R.L", (1.33, 2.20, 0.830))
    int_r_piv = _pivot_part("TP_Plane_05A_Hatch_Int_R.R", (-1.33, 2.20, 0.830))

    EXT_F_CL = (0.0, -59.0, 0.0)
    EXT_L_CL = (0.0, -15.0, 0.0)
    EXT_R_CL = (0.0, 15.0, 0.0)
    INT_F_CL = (-57.0, 0.0, 0.0)
    INT_L_CL = (0.0, 5.0, 0.0)
    INT_R_CL = (0.0, -5.0, 0.0)

    if mode == "parked":
        # Close inner transit bay doors flush so nothing dangles under parked aircraft belly (`frame_0892` fix!)
        for piv_p, cl_deg in ((int_f_piv, INT_F_CL), (int_l_piv, INT_L_CL), (int_r_piv, INT_R_CL)):
            if piv_p is not None:
                piv_p.rotation_euler = tuple(math.radians(a) for a in cl_deg)
        return

    nose_piv = _pivot_part("TP_Plane_05A_Landing_Gear_F", (0.0, -10.45, 1.55))
    ml_piv = _pivot_part("TP_Plane_05A_Landing_Gear_R.L", (1.65, 2.14, 1.46))
    mr_piv = _pivot_part("TP_Plane_05A_Landing_Gear_R.R", (-1.65, 2.14, 1.46))

    if mode == "stowed":
        if nose_piv:
            nose_piv.rotation_euler = (math.radians(96.0), 0.0, 0.0)
        if ml_piv:
            ml_piv.rotation_euler = (0.0, math.radians(88.0), 0.0)
        if mr_piv:
            mr_piv.rotation_euler = (0.0, math.radians(-88.0), 0.0)
        for piv_s, cl_deg in (
            (ext_f_piv, EXT_F_CL),
            (ext_l_piv, EXT_L_CL),
            (ext_r_piv, EXT_R_CL),
            (int_f_piv, INT_F_CL),
            (int_l_piv, INT_L_CL),
            (int_r_piv, INT_R_CL),
        ):
            if piv_s is not None:
                piv_s.rotation_euler = tuple(math.radians(a) for a in cl_deg)
        # Hide ONLY internal struts & tires; keep all outer & inner bay doors VISIBLE and flush!
        for hname in (
            "TP_Plane_05A_Landing_Gear_F",
            "TP_Plane_05A_Landing_Gear_R.L",
            "TP_Plane_05A_Landing_Gear_R.R",
            "TP_Plane_05A_Wheel_F",
            "TP_Plane_05A_Wheel_R.L",
            "TP_Plane_05A_Wheel_R.R",
        ):
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

    for piv_e, cl_deg in ((ext_f_piv, EXT_F_CL), (ext_l_piv, EXT_L_CL), (ext_r_piv, EXT_R_CL)):
        if piv_e is not None:
            tk.key_rot_deg(piv_e, [
                (1, (0.0, 0.0, 0.0)),
                (f_retract_end - 6, (0.0, 0.0, 0.0)),
                (f_retract_end + 6, cl_deg),
                (f_end, cl_deg),
            ])

    for piv_i, cl_deg in ((int_f_piv, INT_F_CL), (int_l_piv, INT_L_CL), (int_r_piv, INT_R_CL)):
        if piv_i is not None:
            tk.key_rot_deg(piv_i, [
                (1, cl_deg),
                (f_retract_start - 6, cl_deg),
                (f_retract_start + 2, (0.0, 0.0, 0.0)),
                (f_retract_end - 2, (0.0, 0.0, 0.0)),
                (f_retract_end + 6, cl_deg),
                (f_end, cl_deg),
            ])

    # Hide internal struts & wheels once retracted inside the closed bay (`f >= f_retract_end + 3`)
    for gname in (
        "TP_Plane_05A_Landing_Gear_F",
        "TP_Plane_05A_Landing_Gear_R.L",
        "TP_Plane_05A_Landing_Gear_R.R",
        "TP_Plane_05A_Wheel_F",
        "TP_Plane_05A_Wheel_R.L",
        "TP_Plane_05A_Wheel_R.R",
    ):
        gob = plane_by_n.get(gname)
        if gob is not None:
            gob.hide_render = False
            gob.keyframe_insert(data_path="hide_render", frame=1)
            gob.keyframe_insert(data_path="hide_render", frame=f_retract_end + 2)
            gob.hide_render = True
            gob.keyframe_insert(data_path="hide_render", frame=f_retract_end + 3)


def _rig_integrated_jet_airstair(scene, plane_root, plane_by_n, tag, close_frames=None, frame_end=210):
    """Fold `TP_Plane_05A_Door` down around its true bottom Y-hinge `(0.78, -8.6172, 1.5774)` (`ry = +137°`)
    as the jet's integrated business-jet airstair (`z_min == 0.000 m`, 6 horizontal treads, `0` non-seam
    fuselage BVH overlap!) with fold-out cable handrails and recessed cabin aisle (`F-05`, `F-16`, `F-23`).
    """
    bpy.context.view_layer.update()
    # Clear interior tables right behind the doorway so Hero turns naturally down the cabin aisle!
    tbl = plane_by_n.get("TP_Plane_05A_Tables")
    if tbl is not None:
        tbl.hide_render = True
        tbl.hide_viewport = True

    tk.make_box(
        scene,
        tag + "_CabinBackWall",
        (0.06, 4.00, 1.90),
        (-0.76, -7.20, 2.57),
        tk.toon_rgb_mat("cabin_liner_" + tag, (0.09, 0.12, 0.20)),
        bevel=0.008,
        parent=plane_root,
    )
    tk.make_box(
        scene,
        tag + "_CabinAisleFloor",
        (1.14, 4.00, 0.04),
        (0.00, -7.20, 1.535),
        tk.toon_rgb_mat("cabin_floor_" + tag, (0.12, 0.15, 0.23)),
        bevel=0.005,
        parent=plane_root,
    )

    s_door = plane_by_n.get("TP_Plane_05A_Door")
    dpiv = bpy.data.objects.new(tag + "_AirstairPivot", None)
    scene.collection.objects.link(dpiv)
    dpiv.parent = plane_root
    dpiv.location = (0.78, -8.6172, 1.5774)
    dpiv.rotation_mode = "XYZ"
    dpiv.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    if s_door is not None:
        dmw = s_door.matrix_world.copy()
        s_door.parent = dpiv
        s_door.matrix_world = dmw

    # Fold-out cable/tubular airstair handrails parented to `dpiv` (in closed door local space:
    # door rises +Z `0..2.05m`, inner face `-X`; when `dpiv` rotates `ry = +137°`, `-X_dpiv` points UP-OUTWARD!)
    rail_holder = bpy.data.objects.new(tag + "_Handrails_ROOT", None)
    rail_holder.parent = dpiv
    scene.collection.objects.link(rail_holder)
    steel_m = tk.toon_rgb_mat("jet_rail_steel", (0.78, 0.82, 0.88))
    yellow_m = tk.toon_rgb_mat("jet_rail_yellow", tk.YELLOW)
    rail_meshes = []
    for side_tag, dy in (("L", -0.37), ("R", 0.37)):
        # Two stanchion posts normal to stair slope (`-X_dpiv` points upward perpendicular to the open stair slope!)
        for pi, z_d in enumerate((0.48, 1.68)):
            post = tk.make_box(
                scene,
                "%s_RailPost_%s_%d" % (tag, side_tag, pi),
                (0.68, 0.032, 0.032),
                (-0.36, dy, z_d),
                steel_m,
                bevel=0.006,
                parent=rail_holder,
                outline=0.002,
            )
            rail_meshes.append(post)
        top_cable = tk.make_box(
            scene,
            "%s_TopRail_%s" % (tag, side_tag),
            (0.040, 0.040, 1.52),
            (-0.70, dy, 1.08),
            yellow_m,
            bevel=0.008,
            parent=rail_holder,
            outline=0.002,
        )
        mid_cable = tk.make_box(
            scene,
            "%s_MidCable_%s" % (tag, side_tag),
            (0.024, 0.024, 1.46),
            (-0.42, dy, 1.08),
            steel_m,
            bevel=0.004,
            parent=rail_holder,
        )
        rail_meshes.extend([top_cable, mid_cable])

    if close_frames is None:
        dpiv.rotation_euler = (0.0, math.radians(137.0), 0.0)
    else:
        f_c0, f_c1 = int(close_frames[0]), int(close_frames[1])
        tk.key_rot_deg(dpiv, [
            (1, (0.0, 137.0, 0.0)),
            (f_c0, (0.0, 137.0, 0.0)),
            (f_c1, (0.0, 0.0, 0.0)),
            (frame_end, (0.0, 0.0, 0.0)),
        ])
        tk._set_fcurves_linear(dpiv)
        # Fold handrails cleanly flat into the inner stairwell (`scale.x -> 0.15`) as door closes!
        rail_holder.scale = (1.0, 1.0, 1.0)
        rail_holder.keyframe_insert(data_path="scale", frame=1)
        rail_holder.keyframe_insert(data_path="scale", frame=f_c0)
        rail_holder.scale = (0.12, 1.0, 0.85)
        rail_holder.keyframe_insert(data_path="scale", frame=f_c1 - 2)
        for rm in rail_meshes:
            rm.hide_render = False
            rm.keyframe_insert(data_path="hide_render", frame=1)
            rm.keyframe_insert(data_path="hide_render", frame=f_c1 - 1)
            rm.hide_render = True
            rm.keyframe_insert(data_path="hide_render", frame=f_c1)

    return dpiv, s_door, rail_meshes


def _build_fuselage_non_seam_bvh(plane_root, fus):
    """Build static BVH of `TP_Plane_05A_Fuselage` excluding only the 6cm doorway jamb seam ring
    where `TP_Plane_05A_Door` latches flush at `ry = 0°`, catching any nose-cone or hull slice (`F-05`)."""
    bpy.context.view_layer.update()
    pinv = plane_root.matrix_world.inverted()
    mw = fus.matrix_world
    w_verts = [mw @ v.co for v in fus.data.vertices]
    l_verts = [pinv @ p for p in w_verts]
    keep_polys = []
    for poly in fus.data.polygons:
        if all(
            (0.65 <= l_verts[vi].x <= 1.42 and -9.08 <= l_verts[vi].y <= -8.16 and 1.48 <= l_verts[vi].z <= 3.74)
            for vi in poly.vertices
        ):
            continue
        keep_polys.append(list(poly.vertices))
    from mathutils.bvhtree import BVHTree
    return BVHTree.FromPolygons(w_verts, keep_polys)


def _build_world_wingtip_vapor_trails(scene, plane_root, fus, cam, frame_end):
    """Build world-space wingtip condensation ribbons (`SoftVapor_L`, `SoftVapor_R`) locked to the
    exact evaluated winglet-tip vertices (`max/min x`) of `TP_Plane_05A_Fuselage`, billboarded toward
    `Shot06Cam` so they read cleanly from the side, and trailing the true historical world flight path
    via per-frame Shape Keys (`0.000 m` tip error, `F-19`)."""
    scene.frame_set(1)
    bpy.context.view_layer.update()
    pinv1 = plane_root.matrix_world.inverted()
    fmw1 = fus.matrix_world
    local_pts = [(i, pinv1 @ (fmw1 @ v.co)) for i, v in enumerate(fus.data.vertices)]
    idx_l = max(local_pts, key=lambda t: t[1].x)[0]
    idx_r = min(local_pts, key=lambda t: t[1].x)[0]

    hist = {"L": {}, "R": {}}
    cam_hist = {}
    for f in range(1, frame_end + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        fmw = fus.matrix_world
        hist["L"][f] = (fmw @ fus.data.vertices[idx_l].co).copy()
        hist["R"][f] = (fmw @ fus.data.vertices[idx_r].co).copy()
        cam_hist[f] = cam.matrix_world.translation.copy()

    # Extrapolate pre-roll frames f <= 0 along initial velocity vector so trail is full-length at f=1!
    vel_l = hist["L"][2] - hist["L"][1]
    vel_r = hist["R"][2] - hist["R"][1]
    n_rows = 36
    for fk in range(-n_rows - 1, 1):
        hist["L"][fk] = hist["L"][1] + vel_l * float(fk - 1)
        hist["R"][fk] = hist["R"][1] + vel_r * float(fk - 1)

    def _ribbon_cross(side_k, k_row, cur_cam):
        p0 = hist[side_k][k_row]
        p1 = hist[side_k][k_row + 1] if (k_row + 1) in hist[side_k] else (p0 + (vel_l if side_k == "L" else vel_r))
        tang = p1 - p0
        tang = tang.normalized() if tang.length > 1e-5 else Vector((-1.0, 0.0, 0.0))
        cdir = (cur_cam - p0)
        perp = cdir.cross(tang)
        return perp.normalized() if perp.length > 1e-5 else Vector((0.0, 0.0, 1.0))

    vmat = tk.soft_vapor_trail_mat()
    tips_and_ribbons = []
    for side, v_idx in (("L", idx_l), ("R", idx_r)):
        me = bpy.data.meshes.new("SoftVaporMesh_" + side)
        bm = bmesh.new()
        uv_layer = bm.loops.layers.uv.new("UVMap")
        row_verts = []
        for r_i in range(n_rows + 1):
            frac = r_i / float(n_rows)
            half_w = 0.06 + 0.48 * frac
            p_c = hist[side][1 - r_i]
            lat = _ribbon_cross(side, 1 - r_i, cam_hist[1])
            v0 = bm.verts.new(p_c - lat * half_w)
            v1 = bm.verts.new(p_c + lat * half_w)
            row_verts.append((v0, v1, frac))
        bm.verts.ensure_lookup_table()
        for r_i in range(n_rows):
            (a0, a1, fa), (b0, b1, fb) = row_verts[r_i], row_verts[r_i + 1]
            face = bm.faces.new((a0, a1, b1, b0))
            face.smooth = True
            uvs = ((0.0, fa), (1.0, fa), (1.0, fb), (0.0, fb))
            for loop, uv_co in zip(face.loops, uvs):
                loop[uv_layer].uv = uv_co
        bm.to_mesh(me)
        bm.free()
        me.materials.append(vmat)

        rib = bpy.data.objects.new("SoftVapor_" + side, me)
        rib.visible_shadow = False
        scene.collection.objects.link(rib)

        rib.shape_key_add(name="Basis", from_mix=False)
        for f in range(1, frame_end + 1):
            sk = rib.shape_key_add(name="F_%03d" % f, from_mix=False)
            c_pos = cam_hist[f]
            for r_i in range(n_rows + 1):
                frac = r_i / float(n_rows)
                half_w = 0.06 + 0.48 * frac
                p_c = hist[side][f - r_i]
                lat = _ribbon_cross(side, f - r_i, c_pos)
                sk.data[2 * r_i].co = p_c - lat * half_w
                sk.data[2 * r_i + 1].co = p_c + lat * half_w
            sk.value = 0.0
            if f > 1:
                sk.keyframe_insert(data_path="value", frame=f - 1)
            sk.value = 1.0
            sk.keyframe_insert(data_path="value", frame=f)
            if f < frame_end:
                sk.value = 0.0
                sk.keyframe_insert(data_path="value", frame=f + 1)
        if me.shape_keys and me.shape_keys.animation_data:
            tk._set_fcurves_linear(me.shape_keys)
        tips_and_ribbons.append((v_idx, rib))

    scene.frame_set(1)
    return tips_and_ribbons


def _attach_towed_roller(
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
    return tk.setup_world_roller_and_grip(
        bpy.context.scene,
        hero_root,
        hero_arm,
        label,
        f_ik_ranges=f_ik_ranges,
        pose_ranges=pose_ranges,
        ground_z=ground_z,
        custom_world_poses=custom_world_poses,
        override_grip_fn=override_grip_fn,
        fist_inf_keys=fist_inf_keys,
        ik_inf_keys=ik_inf_keys,
    )


def _make_boarding_pass_card(scene, name="BoardingPass", parent=None):
    holder = bpy.data.objects.new(name, None)
    scene.collection.objects.link(holder)
    if parent is not None:
        holder.parent = parent
    tk.make_box(scene, name + "_Card", (0.24, 0.11, 0.008), (0.0, 0.0, 0.0), tk.emissive_mat("pass_cream", tk.CREAM, 1.25), bevel=0.002, parent=holder, outline=0.002)
    tk.make_box(scene, name + "_Stripe", (0.24, 0.032, 0.010), (0.0, -0.032, 0.001), tk.emissive_mat("pass_lime", tk.GOTTA_LIME, 1.35), bevel=0.0015, parent=holder)
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
    for sx_s in (-1.65, 1.65):
        tk.make_box(scene, "Board_Strut_%.2f" % sx_s, (0.11, 0.11, 1.65), (sx_s, 0.04, 1.48), navy_m, bevel=0.015, parent=root, outline=0.004)
        tk.make_box(scene, "Board_WallArm_%.2f" % sx_s, (0.11, 1.85, 0.11), (sx_s, 0.96, 0.52), navy_m, bevel=0.015, parent=root, outline=0.004)

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


# ==============================================================================
# SHOT 1 (165 frames = 5.5s): Curb Drop-off, Ticking Board & Sprint Inside
# ==============================================================================


def build_shot_01(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.12, indoor=False)
    tk.make_box(scene, "LandsideSubRoad", (220.0, 220.0, 0.12), (0.0, 0.0, 0.03), tk.toon_rgb_mat("road_sub", (0.25, 0.27, 0.32)), bevel=0.0)

    ROAD_Z = 0.105
    CURB_Z = 0.20

    _, ap_objs, ap_by_n, _ = tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "AirportExt", loc=(0.0, 0.0, 0.0), outline_thickness=0.003)
    tk.warm_exterior_facade_windows(ap_objs)

    # Shift ONLY whole connected `(P)` parking sign + pole mesh islands inside `TP_Airport_01A_Road`
    # (`x=13.4..14.7, y=-20.6..-19.5, z=0.0..3.0`) 6.8m west to `x = 7.2` so zero edges stretch across the curb (`F-11`)!
    ap_road = ap_by_n.get("TP_Airport_01A_Road")
    orig_road_edge_lens = []
    orig_road_max_edge = 0.0
    if ap_road is not None and ap_road.type == "MESH":
        from collections import deque
        ap_road.data = ap_road.data.copy()
        rmw = ap_road.matrix_world
        rinv = rmw.inverted()
        bm_road = bmesh.new()
        bm_road.from_mesh(ap_road.data)
        bm_road.verts.ensure_lookup_table()
        bm_road.edges.ensure_lookup_table()
        orig_road_edge_lens = [
            float(((rmw @ e.verts[0].co) - (rmw @ e.verts[1].co)).length) for e in bm_road.edges
        ]
        orig_road_max_edge = max(orig_road_edge_lens) if orig_road_edge_lens else 0.0
        seen_v = set()
        moved_sign_islands = 0
        for v0 in bm_road.verts:
            if v0.index in seen_v:
                continue
            q_v = deque([v0])
            seen_v.add(v0.index)
            comp = []
            while q_v:
                cv = q_v.popleft()
                comp.append(cv)
                for ed in cv.link_edges:
                    ov = ed.other_vert(cv)
                    if ov.index not in seen_v:
                        seen_v.add(ov.index)
                        q_v.append(ov)
            comp_wps = [rmw @ cv.co for cv in comp]
            if (
                all(13.4 <= wp.x <= 14.7 and -20.6 <= wp.y <= -19.5 for wp in comp_wps)
                and max(wp.z for wp in comp_wps) > 1.0
            ):
                for cv, wp in zip(comp, comp_wps):
                    cv.co = rinv @ Vector((wp.x - 6.80, wp.y, wp.z))
                moved_sign_islands += 1
        if moved_sign_islands == 0:
            tk.fail("shot_01: found 0 connected `(P)` sign islands in TP_Airport_01A_Road!")
        bm_road.to_mesh(ap_road.data)
        bm_road.free()
        ap_road.data.update()

    curb_bay_r, _, _, _ = tk.load_glb("game/assets/landside/tp_curb_bay_01a.glb", "CurbBay", loc=(11.5, -19.6, 0.11), outline_thickness=0.003)

    # Curbside props & bench visibly framed along the upper sidewalk (`y = -17.75`), 100% clear of sidewalk strollers & Hero!
    pl_l, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantL", loc=(10.2, -17.75, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    pl_r, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "CurbPlantR", loc=(23.6, -17.75, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    tr1, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeL", loc=(5.4, -17.75, CURB_Z), outline_thickness=0.004)
    tr1.scale = (1.50, 1.50, 1.50)
    tr2, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "CurbTreeR", loc=(25.8, -17.75, CURB_Z), outline_thickness=0.004)
    tr2.scale = (1.55, 1.55, 1.55)
    bench_c, _, _, _ = tk.load_glb("game/assets/decor/tc_bench_1a.glb", "CurbBench", loc=(12.2, -17.72, CURB_Z), yaw_deg=90.0, outline_thickness=0.004)
    bin_c, _, _, _ = tk.load_glb("game/assets/decor/tc_trash_can_1a.glb", "CurbBin", loc=(18.2, -17.75, CURB_Z), outline_thickness=0.004)

    pole_m = tk.toon_rgb_mat("lamp_pole", (0.22, 0.25, 0.32))
    bulb_m = tk.emissive_mat("lamp_bulb", (1.0, 0.92, 0.72), strength=1.8)
    lamp_poles = []
    for lx in (5.4, 22.0):
        lp = tk.make_box(scene, "LampPole_%d" % int(lx), (0.12, 0.12, 3.8), (lx, -20.85, CURB_Z + 1.9), pole_m, bevel=0.02)
        tk.make_box(scene, "LampHead_%d" % int(lx), (0.48, 0.28, 0.16), (lx, -21.05, CURB_Z + 3.82), bulb_m, bevel=0.03)
        lamp_poles.append(lp)

    # Departing SUV visibly passing in the outer foreground traffic lane (`y = -24.8`, east of Hero so zero occlusion, `F-24`)!
    cruiser, _, _, _ = tk.load_glb("game/assets/vehicles/tp_suv_01b.glb", "DepartingSUV", loc=(15.2, -24.8, ROAD_Z), yaw_deg=90.0, outline_thickness=0.003)
    tk.key_pos(cruiser, [(1, (15.2, -24.8, ROAD_Z)), (62, (25.8, -24.8, ROAD_Z)), (N, (29.5, -24.8, ROAD_Z))])
    tk._set_fcurves_linear(cruiser)

    # Deep warm lit terminal lobby inside Door_6 (`y = -17.65 .. -12.5`) with tiled concourse floor, ceiling LEDs & interior depth props (`F-03`)!
    tk.make_box(scene, "Door6LobbyFloor", (8.5, 5.4, 0.08), (16.0, -15.05, CURB_Z - 0.035), tk.concourse_tile_floor_mat(), bevel=0.0)
    tk.make_box(scene, "Door6WarmVestibule", (7.6, 0.20, 3.9), (16.0, -12.50, 2.05), tk.emissive_mat("foyer_warm_glow", (0.96, 0.91, 0.80), 0.98), bevel=0.0)
    tk.make_box(scene, "ExtLobbyBackdrop", (68.0, 0.4, 8.5), (4.0, -12.1, 4.25), tk.emissive_mat("lobby_warm_wall", (0.98, 0.92, 0.78), 1.02), bevel=0.0)
    for ly_lob in (-16.2, -14.2):
        led_l = tk.make_box(scene, "Door6LobbyLED_%d" % abs(int(ly_lob)), (1.5, 1.2, 0.05), (16.0, ly_lob, 3.62), tk.emissive_mat("lob_led", (1.0, 0.96, 0.86), 1.5), bevel=0.01)
        led_l.visible_shadow = False
    lob_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "LobbyDepthScreen", loc=(14.55, -14.2, CURB_Z), yaw_deg=20.0)
    lob_plt, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "LobbyDepthPlant", loc=(17.35, -14.4, CURB_Z), yaw_deg=-90.0)

    # Background travelers visibly strolling inside Shot01Cam's frustum (`y = -18.85`, >0.60m clear of facade & curb props) without occluding Hero (`F-24`)!
    bg1_r, bg1_a, _, bg1_acts = tk.load_character("tcp_female_character_03", "CurbPax1", cloth_tint=(0.28, 0.65, 0.78), loc=(21.2, -18.85, CURB_Z), yaw_deg=-90.0)
    tk.animate_character_locomotion(bg1_r, bg1_a, bg1_acts, [(1, (21.2, -18.85, CURB_Z)), (N, (19.3, -18.85, CURB_Z))], N, phase_offset=7.0)
    sh_bag, _, _, _ = tk.load_glb("game/assets/interior/carry_shoulder_bag.glb", "CurbPax1Bag", outline_thickness=0.004)
    tk.parent_prop_to_bone(sh_bag, bg1_a, "Spine_02", local_loc=(-0.22, -0.10, 0.0), local_rot_deg=(-90.0, 0.0, 0.0))

    bg2_r, bg2_a, _, bg2_acts = tk.load_character("tcp_male_character_08", "CurbPax2", cloth_tint=(0.45, 0.58, 0.32), loc=(7.2, -18.85, CURB_Z), yaw_deg=90.0)
    tk.animate_character_locomotion(bg2_r, bg2_a, bg2_acts, [(1, (7.2, -18.85, CURB_Z)), (N, (9.4, -18.85, CURB_Z))], N, phase_offset=14.0)

    flip_f = 52
    board_root = _build_departure_board(scene, (15.85, -19.95, 3.22), flip_frame=flip_f)
    board_root.scale = (0.76, 0.76, 0.76)

    # Replace 4-wing revolving cross `TP_Airport_01A_Door_6` with a clean telescopic bi-parting automatic glass door unit
    # fitted strictly inside `[14.88, 17.12]` above the `z = 0.203 m` threshold slab clear of both concrete columns (`0` BVH overlap, `F-03`)!
    door6 = ap_by_n.get("TP_Airport_01A_Door_6")
    if door6 is not None:
        door6.hide_render = True
        door6.hide_viewport = True
    door6_unit, _ = tk.make_sliding_glass_door_unit(
        scene,
        "Door6SlidingUnit",
        loc=(16.00, -17.65, CURB_Z + 0.008),
        yaw_deg=0.0,
        clear_width=1.52,
        total_width=2.22,
        height=2.45,
        total_height=3.45,
        open_keys=[(1, 0.0), (86, 0.0), (110, 1.0), (N, 1.0)],
        telescopic=True,
    )

    # Hero Taxi: opaque dark-tinted windows via `vehicle_glass_mat()`, upright rear door `rx = 0°`,
    # holds parked at `x = 10.55` until `f = 150` AFTER Hero enters the terminal so zero occlusion (`F-04`, `F-11`)!
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
                (22, (740.0, 0.0, 0.0)),
                (150, (740.0, 0.0, 0.0)),
                (N, (1080.0, 0.0, 0.0)),
            ])

    rdoor = taxi_by_n.get("TP_Taxi_01A_Door_R.L")
    rdoor_rest_zmax = tk.mesh_world_aabb([rdoor])[5] if rdoor is not None else 1.67
    if rdoor is not None:
        rd_mw = rdoor.matrix_world.copy()
        rd_piv = bpy.data.objects.new("TaxiDoorPiv_RL", None)
        scene.collection.objects.link(rd_piv)
        rd_piv.parent = taxi_root
        rd_piv.location = taxi_inv @ rd_mw.translation
        rd_piv.rotation_mode = "XYZ"
        rd_piv.rotation_euler = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        rdoor.parent = rd_piv
        rdoor.matrix_world = rd_mw
        tk.key_rot_deg(rd_piv, [
            (1, (0.0, 0.0, 0.0)),
            (14, (0.0, 0.0, 0.0)),
            (22, (0.0, 0.0, -66.0)),
            (92, (0.0, 0.0, -66.0)),
            (104, (0.0, 0.0, 0.0)),
            (N, (0.0, 0.0, 0.0)),
        ])

    tk.key_pos(taxi_root, [
        (1, (6.5, -22.25, ROAD_Z)),
        (17, (8.25, -22.25, ROAD_Z)),
        (22, (8.45, -22.25, ROAD_Z)),
        (150, (8.45, -22.25, ROAD_Z)),
        (N, (11.20, -22.40, ROAD_Z)),
    ])
    tk.key_rot_deg(taxi_root, [
        (1, (0.0, 0.0, 90.0)),
        (16, (0.0, 0.0, 90.0)),
        (20, (2.0, 0.0, 90.0)),
        (26, (0.0, 0.0, 90.0)),
        (150, (0.0, 0.0, 90.0)),
        (N, (-0.8, 0.0, 91.5)),
    ])
    scene.frame_set(1)
    bpy.context.view_layer.update()

    # Hero passenger: steps laterally north-east out of the open rear doorway (`x = 7.75 -> 9.65, y = -21.10 -> -20.05`)
    # in full 3/4 view past the parked taxi's front fender (`100%` unoccluded from `f = 25..165`, `F-04`, `F-11`)!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(7.75, -21.10, CURB_Z), yaw_deg=135.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (7.75, -21.10, CURB_Z), 135.0),
            (20, (7.75, -21.10, CURB_Z), 135.0),
            (29, (9.45, -20.05, CURB_Z)),
            (50, (12.80, -20.05, CURB_Z), 165.0),
            (88, (12.80, -20.05, CURB_Z), 165.0),
            (93, (12.80, -20.05, CURB_Z), 112.0),
            (118, (14.65, -19.55, CURB_Z)),
            (136, (15.76, -18.75, CURB_Z)),
            (N, (15.80, -16.25, CURB_Z)),
        ],
        frame_end=N,
    )

    tk.bind_head_look_at(
        scene,
        hero_arm,
        "HeroBoardLook",
        target_pos=(15.85, -19.80, 3.22),
        influence_keys=[(1, 0.0), (48, 0.0), (56, 0.72), (86, 0.72), (95, 0.0)],
        include_spine=True,
    )
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "BoardStartle",
        hand="L",
        parent=hero_root,
        pos_keys=[
            (50, (0.24, -0.08, 1.24)),
            (58, (0.20, -0.16, 1.68)),
            (84, (0.21, -0.15, 1.67)),
            (94, (0.24, -0.08, 1.24)),
        ],
        influence_keys=[(1, 0.0), (50, 0.0), (57, 0.92), (84, 0.92), (94, 0.0)],
        pole_parent=hero_root,
        pole_loc=(0.38, 0.35, 0.85),
    )

    bag01_root, bag01_by_n = _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller01",
        f_ik_ranges=[(21, N)],
        pose_ranges=[(1, 46, "walk_tow"), (52, 91, "stand"), (97, N, "tow")],
        ground_z=CURB_Z,
    )
    for ho in hero_objs:
        if ho.type == "MESH":
            ho.hide_render = True
            ho.keyframe_insert(data_path="hide_render", frame=1)
            ho.keyframe_insert(data_path="hide_render", frame=20)
            ho.hide_render = False
            ho.keyframe_insert(data_path="hide_render", frame=21)
    for bo in bag01_root.children_recursive:
        if bo.type == "MESH":
            bo.hide_render = True
            bo.keyframe_insert(data_path="hide_render", frame=1)
            bo.keyframe_insert(data_path="hide_render", frame=22)
            bo.hide_render = False
            bo.keyframe_insert(data_path="hide_render", frame=23)

    cam, target = tk.make_camera(scene, "Shot01Cam", lens=31.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (13.8, -26.4, 2.38)),
        (28, (14.6, -26.2, 2.36)),
        (52, (15.0, -26.8, 2.02)),
        (94, (15.4, -26.6, 1.94)),
        (N, (16.0, -25.6, 1.90)),
    ])
    tk.key_pos(target, [
        (1, (8.4, -21.4, 1.08)),
        (28, (9.6, -20.4, 1.24)),
        (52, (13.9, -19.8, 1.62)),
        (94, (14.75, -19.5, 1.68)),
        (N, (15.85, -17.6, 1.72)),
    ])

    events = [
        {"type": "car_arrive", "frame": g0 + 1, "dur": 22},
        {"type": "car_brake", "frame": g0 + 19},
        {"type": "car_door", "frame": g0 + 16},
        {"type": "board_flip", "frame": g0 + flip_f - 3, "count": 9},
        {"type": "startle_sting", "frame": g0 + flip_f + 2},
        {"type": "door_whoosh", "frame": g0 + 90},
        {"type": "car_door", "frame": g0 + 104},
        {"type": "roller", "frame": g0 + 24, "dur": 24},
        {"type": "roller", "frame": g0 + 95, "dur": 68},
    ]
    for f in list(range(22, 48, 8)) + list(range(95, N, 6)):
        events.append({"type": "footstep", "frame": g0 + f})

    taxi_body = [taxi_by_n["TP_Taxi_01A_Body"]] if "TP_Taxi_01A_Body" in taxi_by_n else taxi_objs
    prove_targets = [("start_taxi", 1, taxi_body)] + [
        ("hero_f%03d" % fl, fl, hero_objs) for fl in range(25, N + 1, 5)
    ]

    ap_main = [ap_by_n["TP_Airport_01A"]] if "TP_Airport_01A" in ap_by_n else []
    door6_leaf_meshes = [
        m for c in door6_unit.children if "Leaf_" in c.name for m in c.children_recursive if m.type == "MESH"
    ]
    motion_spec = {
        "obstacle_roots": [
            ("CurbBay", curb_bay_r),
            ("CurbPlantL", pl_l),
            ("CurbPlantR", pl_r),
            ("CurbTreeL", tr1),
            ("CurbTreeR", tr2),
            ("CurbBench", bench_c),
            ("CurbBin", bin_c),
            ("LobbyDepthScreen", lob_scr),
            ("LobbyDepthPlant", lob_plt),
        ] + [("LampPole_%d" % i, lp) for i, lp in enumerate(lamp_poles)],
        "extra_boxes_xy": [
            ("TerminalFacade_W", -40.0, 14.95, -18.25, -16.50),
            ("TerminalFacade_E", 17.05, 40.0, -18.25, -16.50),
            ("ParkingSignPole", 6.90, 7.45, -20.45, -19.85),
        ],
        "seated_exempt": set(),
        "exempt_ranges": {"CHAR_Hero": [(1, 21)]},
        "forbid_char_boxes": [
            ("TaxiClosedZone", 1, 18, 4.0, 12.0, -23.8, -20.6, 0.10, 3.50),
            ("TaxiRoofZone", 1, 20, 4.0, 12.0, -23.4, -21.1, 1.46, 3.50),
        ],
        "pulled_rollers": [
            (hero_root, hero_arm, bag01_by_n["CarryRoller_Body"], CURB_Z, [(24, 45), (98, N)]),
        ],
        "roller_grip_checks": [
            (hero_root, hero_arm, bag01_root, bag01_by_n["Pull_Top"], [(23, N)]),
        ],
        "door_checks": [
            {"kind": "taxi_door_upright", "door": rdoor, "rest_z_max": rdoor_rest_zmax},
            {
                "kind": "bvh_zero_overlap",
                "label": "Door6Leaves_vs_AirportColumns",
                "objs_a": door6_leaf_meshes,
                "objs_b": ap_main,
            },
        ],
        "prop_checks": [
            {
                "kind": "mesh_max_edge_stretch",
                "label": "TP_Airport_01A_Road",
                "mesh_obj": ap_road,
                "orig_max_edge_len": orig_road_max_edge,
                "orig_edge_lens": orig_road_edge_lens,
                "max_ratio": 1.5,
                "frames": (1, 1),
            },
        ],
        "shot_continuity_checks": [
            {"kind": "require_bg_pedestrian"},
        ],
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 2 (225 frames = 7.5s): Two Point Pop-In Ahead of Hero + Direct Handoff
# ==============================================================================


def build_shot_02(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
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
        south_openings=[(0.0, 2.80)],
    )

    # Overhead signs anchored with vertical navy suspension struts to the z=3.85m ceiling (`F-18`)!
    sec_sign, sec_sign_core = tk.make_hanging_terminal_sign(
        scene, "SecCorridorSign_ROOT", "SECURITY  >", loc=(6.65, 3.35, 2.18), yaw_deg=-90.0, width=2.35, height=0.40, ceil_z=3.85, text_size=0.22
    )

    ec_plant, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "EastCorrPlant", loc=(9.6, 1.72, 0.0), yaw_deg=90.0)
    ec_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "EastCorrScreen", loc=(11.9, 1.68, 0.0), yaw_deg=180.0)

    # Closed flush bi-parting glass door fitted into the south vestibule opening (`0` center gap, `0` drywall inside doorway, `F-06`)!
    tk.make_sliding_glass_door_unit(
        scene,
        "EntryDoorBack",
        loc=(0.0, -13.5, 0.0),
        yaw_deg=0.0,
        clear_width=1.36,
        total_width=2.80,
        height=2.22,
        total_height=2.45,
        open_keys=[(1, 0.0)],
    )
    b_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "BackScreen", loc=(3.8, -13.0, 0.0), yaw_deg=0.0)
    b_ksk, _, _, _ = tk.load_glb("game/assets/interior/kiosk.glb", "BackKiosk", loc=(4.8, -8.5, 0.0), yaw_deg=-90.0)

    # Janitor mopping CoffeeSpill in WORLD SPACE (`MopHead` flat on floor `z_min` in `[0..0.03]`, BOTH hands locked to shaft, `F-08`)!
    tk.load_glb("game/assets/mess/mess_spill.glb", "CoffeeSpill", loc=(-2.25, -8.75, 0.005), yaw_deg=20.0, outline_thickness=0.003)
    bucket_root = tk.make_box(scene, "CleanerBucket", (0.34, 0.28, 0.36), (-2.98, -8.85, 0.18), tk.toon_rgb_mat("mop_bucket", tk.YELLOW), bevel=0.02, outline=0.004)
    cln_r, cln_a, _, cln_acts = tk.load_character("tcp_female_character_10", "HallCleaner", cloth_tint=None, loc=(-2.25, -9.12, 0.0), yaw_deg=180.0)
    tk.set_stationary_clip(cln_a, cln_acts, "idle", N, speed=1.0)
    _, mop_head, mop_stick = tk.rig_two_hand_floor_mop(scene, cln_r, cln_a, spill_xy=(-2.25, -8.75), frame_end=N)

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

    runner_navy = tk.toon_rgb_mat("runner_navy", tk.NAVY)
    runner_lime = tk.toon_rgb_mat("runner_lime", tk.GOTTA_LIME)
    for row_i, gy in enumerate(range(-6, 5, 2)):
        row_holder = bpy.data.objects.new("CarpetSeg_%d" % row_i, None)
        row_holder.location = (-0.32, float(gy) + 0.5, 0.018)
        scene.collection.objects.link(row_holder)
        tk.make_box(scene, "CarpetMain_%d" % row_i, (1.62, 1.92, 0.022), (0.0, 0.0, 0.0), runner_navy, bevel=0.005, parent=row_holder, outline=0.003)
        tk.make_box(scene, "CarpetTrimL_%d" % row_i, (0.14, 1.92, 0.026), (-0.74, 0.0, 0.002), runner_lime, bevel=0.003, parent=row_holder)
        tk.make_box(scene, "CarpetTrimR_%d" % row_i, (0.14, 1.92, 0.026), (0.74, 0.0, 0.002), runner_lime, bevel=0.003, parent=row_holder)
        trig = max(4, 8 + row_i * 10)
        snap(row_holder, trig, drop=1.15)

    pop_posts = []
    for pi_s, py_s in enumerate((-3.2, -0.8, 1.6)):
        sp_c, _, _, _ = tk.load_glb("game/assets/decor/tc_metal_pole_1a.glb", "CheckinRopePole_%d" % pi_s, loc=(-1.42, py_s, 0.0), outline_thickness=0.004)
        sp_c.scale = (0.55, 0.55, 0.68)
        snap(sp_c, 18 + pi_s * 14, drop=1.35)
        pop_posts.append(("CheckinPole_%d" % pi_s, sp_c))

    ci_banner, ci_banner_core = tk.make_hanging_terminal_sign(
        scene, "CheckinBanner_ROOT", "CHECK-IN", loc=(0.0, 4.35, 2.24), yaw_deg=0.0, width=2.75, height=0.46, ceil_z=3.85, text_size=0.26
    )
    snap(ci_banner, 60, drop=1.05)

    for wi, wy in enumerate(range(-12, 8, 2)):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "WG_%d" % wi, loc=(-3.75, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)

    st2, _, _, _ = tk.load_glb("game/assets/decor/tc_bench_1a.glb", "SnapBench", loc=(-3.05, -4.8, 0.0), yaw_deg=0.0)
    snap(st2, 14, drop=1.25)
    p1, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SnapPlant1", loc=(-2.95, -1.8, 0.0), yaw_deg=0.0)
    snap(p1, 30, drop=1.45)
    p2, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_2a.glb", "SnapPlant2", loc=(-2.85, 1.2, 0.0))
    p2.scale = (0.65, 0.65, 0.65)
    snap(p2, 46, drop=1.40)
    st1, _, _, _ = tk.load_glb("game/assets/interior/screen_stand.glb", "SnapStand1", loc=(-2.25, 2.85, 0.0), yaw_deg=25.0)
    snap(st1, 52, drop=1.35)

    # Pop CheckinDesk (`l=40`, settled by `l=53`) and CheckinDesk2 (`l=50`, settled by `l=63`) BEFORE clerks walk in (`F-20`)!
    desk_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk", loc=(0.0, 4.45, 0.0), yaw_deg=0.0)
    snap(desk_root, 40, drop=1.65)
    belt_root, _, _, _ = tk.load_glb("game/assets/interior/baggage_belt.glb", "SnapBagBelt", loc=(1.42, 4.45, 0.0), yaw_deg=0.0)
    snap(belt_root, 46, drop=1.45)
    desk2_root, _, _, _ = tk.load_glb("game/assets/interior/checkin_desk.glb", "CheckinDesk2", loc=(3.05, 5.45, 0.0), yaw_deg=0.0)
    snap(desk2_root, 50, drop=1.65)
    scr_root, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "CheckinInfo", loc=(-2.25, 4.85, 0.0), yaw_deg=20.0)
    snap(scr_root, 56, drop=1.55)

    # Clerks start in the off-screen east staff corridor and briskly walk via the clear rear aisle behind their ALREADY-SETTLED desks (`F-20`)!
    clerk_root, clerk_arm, clerk_objs, clerk_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk", cloth_tint=tk.GOTTA_LIME, loc=(7.55, 3.60, 0.0), yaw_deg=-90.0
    )
    tk.animate_character_locomotion(
        clerk_root,
        clerk_arm,
        clerk_acts,
        waypoints=[
            (1, (7.55, 3.60, 0.0), -90.0),
            (28, (7.55, 3.60, 0.0), -90.0),
            (48, (4.70, 3.85, 0.0)),
            (66, (4.65, 6.55, 0.0)),
            (84, (-0.28, 6.50, 0.0)),
            (96, (-0.28, 4.99, 0.0), 0.0),
            (N, (-0.28, 4.99, 0.0), 0.0),
        ],
        frame_end=N,
        phase_offset=11.0,
    )
    tk.bind_head_look_at(
        scene,
        clerk_arm,
        "ClerkLookHero",
        target_pos=(-0.28, 3.99, 1.48),
        influence_keys=[(1, 0.0), (96, 0.0), (108, 0.65), (140, 0.65), (154, 0.0)],
        include_spine=True,
    )

    clerk2_root, clerk2_arm, _, clerk2_acts = tk.load_character(
        "tcp_female_character_07", "CheckinClerk2", cloth_tint=tk.CLERK_NAVY, loc=(8.35, 3.60, 0.0), yaw_deg=-90.0
    )
    tk.animate_character_locomotion(
        clerk2_root,
        clerk2_arm,
        clerk2_acts,
        waypoints=[
            (1, (8.35, 3.60, 0.0), -90.0),
            (46, (8.35, 3.60, 0.0), -90.0),
            (68, (5.15, 3.85, 0.0)),
            (86, (5.05, 6.60, 0.0)),
            (102, (3.05, 6.50, 0.0), 0.0),
            (N, (3.05, 6.50, 0.0), 0.0),
        ],
        frame_end=N,
        phase_offset=42.0,
    )

    # Direct hand-to-hand BoardingPass transfer (`F-07`, zero telekinetic desk slide, zero wrist impalement!):
    # Clerk (`y = 4.99`, `Arm.R` at `x = -0.46`) & Hero (`y = 3.99`, `Arm.L` at `x = -0.46`) meet directly along `x = -0.45`!
    tk.bind_hand_ik_target(
        scene,
        clerk_arm,
        "ClerkHandPass",
        hand="R",
        pos_keys=[
            (100, (-0.45, 4.86, 1.32)),
            (116, (-0.45, 4.63, 1.34)),
            (128, (-0.45, 4.63, 1.34)),
            (146, (-0.45, 4.86, 1.32)),
        ],
        influence_keys=[(1, 0.0), (100, 0.0), (114, 0.96), (129, 0.96), (146, 0.0)],
        pole_parent=clerk_root,
        pole_loc=(-0.38, 0.35, 0.85),
    )
    clerk_pass = _make_boarding_pass_card(scene, "ClerkHeldPass02")
    tk.bind_card_in_pinch(
        scene,
        clerk_pass,
        clerk_arm,
        hand="R",
        name="ClerkPassPinch",
        influence_keys=[(1, 0.0), (96, 0.0), (102, 1.0), (127, 1.0), (134, 0.0)],
    )
    for cm_o in clerk_pass.children_recursive:
        if cm_o.type == "MESH":
            cm_o.hide_render = True
            cm_o.keyframe_insert(data_path="hide_render", frame=1)
            cm_o.keyframe_insert(data_path="hide_render", frame=97)
            cm_o.hide_render = False
            cm_o.keyframe_insert(data_path="hide_render", frame=98)
            cm_o.keyframe_insert(data_path="hide_render", frame=126)
            cm_o.hide_render = True
            cm_o.keyframe_insert(data_path="hide_render", frame=127)
    events.append({"type": "stamp_ding", "frame": g0 + 125})

    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(-0.22, -8.25, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (-0.22, -8.25, 0.0), 180.0),
            (104, (-0.28, 3.99, 0.0), 180.0),
            (135, (-0.28, 3.99, 0.0), 180.0),
            (145, (-0.28, 3.99, 0.0), 115.0),
            (158, (0.75, 3.35, 0.0)),
            (N, (8.65, 3.35, 0.0)),
        ],
        frame_end=N,
    )
    tk.bind_head_look_at(
        scene,
        hero_arm,
        "HeroLookClerk",
        target_pos=(-0.28, 4.99, 1.48),
        influence_keys=[(1, 0.0), (98, 0.0), (108, 0.72), (136, 0.72), (146, 0.0)],
        include_spine=True,
    )
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "HeroGrabPass",
        hand="L",
        pos_keys=[
            (110, (-0.44, 4.08, 1.32)),
            (122, (-0.45, 4.33, 1.34)),
            (130, (-0.45, 4.33, 1.34)),
            (144, (-0.42, 4.06, 1.30)),
        ],
        influence_keys=[(1, 0.0), (110, 0.0), (120, 0.96), (131, 0.96), (144, 0.0)],
        pole_parent=hero_root,
        pole_loc=(0.38, 0.35, 0.85),
    )
    hand_pass = _make_boarding_pass_card(scene, "HeroHeldPass02")
    tk.bind_card_in_pinch(
        scene,
        hand_pass,
        hero_arm,
        hand="L",
        name="HeroPassPinch02",
        influence_keys=[(1, 0.0), (120, 0.0), (126, 1.0), (N, 1.0)],
    )
    for hm_o in hand_pass.children_recursive:
        if hm_o.type == "MESH":
            hm_o.hide_render = True
            hm_o.keyframe_insert(data_path="hide_render", frame=1)
            hm_o.keyframe_insert(data_path="hide_render", frame=126)
            hm_o.hide_render = False
            hm_o.keyframe_insert(data_path="hide_render", frame=127)

    bag02_root, bag02_by_n = _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller02",
        f_ik_ranges=[(1, N)],
        pose_ranges=[(1, 100, "tow"), (106, 143, "stand"), (147, N, "tow")],
    )

    cam, target = tk.make_camera(scene, "Shot02Cam", lens=30.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.85, -4.4, 1.78)),
        (96, (3.95, 0.35, 1.72)),
        (132, (3.45, -0.10, 1.74)),
        (172, (2.25, -0.85, 1.76)),
        (202, (1.65, 1.25, 1.74)),
        (N, (2.15, 2.75, 1.70)),
    ])
    tk.key_pos(target, [
        (1, (-0.30, -6.4, 1.02)),
        (96, (-0.35, 3.45, 1.08)),
        (132, (-0.32, 4.15, 1.12)),
        (172, (2.35, 3.42, 0.92)),
        (202, (5.20, 3.35, 0.88)),
        (N, (9.45, 3.35, 1.18)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": 102})
    events.append({"type": "roller", "frame": g0 + 148, "dur": 76})
    for f in list(range(4, 102, 7)) + list(range(148, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("hero_f%03d" % fl, fl, hero_objs) for fl in range(1, N + 1, 15)
    ] + [
        ("end", N, hero_objs),
        ("clerk_f293", 128, clerk_objs),
        ("checkin_sign", 104, ci_banner_core),
        ("security_sign", 210, sec_sign_core),
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
            ("CheckinDesk", desk_root, 0.02),
            ("SnapBagBelt", belt_root),
            ("CheckinDesk2", desk2_root),
            ("CheckinInfo", scr_root),
            ("EastCorrPlant", ec_plant),
            ("EastCorrScreen", ec_scr),
        ] + pop_posts,
        "extra_boxes_xy": [
            ("WestGlassWall", -4.1, -3.65, -14.0, 8.0),
            ("NorthSolidWall", -4.0, 7.0, 7.65, 8.0),
            ("EastWall_SouthSeg", 6.68, 7.0, -14.0, 1.22),
            ("EastWall_NorthSeg", 6.68, 7.0, 5.48, 8.0),
        ],
        "seated_exempt": set(),
        "pulled_rollers": [
            (hero_root, hero_arm, bag02_by_n["CarryRoller_Body"], 0.0, [(1, 98), (150, N)]),
        ],
        "roller_grip_checks": [
            (hero_root, hero_arm, bag02_root, bag02_by_n["Pull_Top"], [(1, N)]),
        ],
        "prop_checks": [
            {"kind": "mop_floor_and_hands", "mop_head": mop_head, "mop_stick": mop_stick, "arm": cln_a},
            {"kind": "boarding_pass_pinch", "card": clerk_pass, "holders": [(clerk_root, clerk_arm, "R")], "frames": (102, 126)},
            {"kind": "boarding_pass_pinch", "card": hand_pass, "holders": [(hero_root, hero_arm, "L")], "frames": (127, N)},
        ],
        "shot_continuity_checks": [
            {"kind": "workstation_settle_before_staff", "settle_frame": 53, "staff_root": clerk_root, "desk_xy": (0.0, 4.45)},
            {"kind": "workstation_settle_before_staff", "settle_frame": 63, "staff_root": clerk2_root, "desk_xy": (3.05, 5.45)},
        ],
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 3 (225 frames = 7.5s): Security Two-Hand Suitcase Heave & Stanchion Queue
# ==============================================================================


def build_shot_03(g0):
    N = 225
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.02, indoor=True)
    tk.build_enclosed_terminal_hall(
        scene,
        x_min=-7.5,
        x_max=4.0,
        y_min=-11.0,
        y_max=9.5,
        ceil_z=3.85,
        glass_side="right",
        open_north_wall=False,
        north_openings=[(0.15, 2.40), (2.85, 2.20)],
    )

    for wy in range(-10, 9, 2):
        wg, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SWG_%d" % wy, loc=(3.95, float(wy), 0.0), yaw_deg=90.0)
        wg.scale = (2.0, 1.0, 1.0)

    # Flush sliding glass exit doors in the north concourse wall (`0` center gap when closed, `0` leaves outside frame, `F-06`)!
    tk.make_sliding_glass_door_unit(
        scene,
        "SWExitDoor1",
        loc=(0.15, 9.50, 0.0),
        yaw_deg=0.0,
        clear_width=1.22,
        total_width=2.40,
        height=2.22,
        total_height=2.45,
        open_keys=[(1, 0.0), (160, 0.0), (182, 1.0), (N, 1.0)],
    )
    tk.make_sliding_glass_door_unit(
        scene,
        "SWExitDoor2",
        loc=(2.85, 9.50, 0.0),
        yaw_deg=0.0,
        clear_width=1.10,
        total_width=2.20,
        height=2.22,
        total_height=2.45,
        open_keys=[(1, 1.0)],
    )

    # Framed glass security barrier partition (`x = 1.44 .. 3.96, y = 0.0`) so `SecArch` is the sole airside passage (`F-21`)!
    part_root = bpy.data.objects.new("SecGlassPartition_ROOT", None)
    scene.collection.objects.link(part_root)
    alu_m = tk.toon_rgb_mat("sec_part_alu", (0.22, 0.27, 0.36))
    tk.make_box(scene, "SecPartPostL", (0.06, 0.10, 2.35), (1.47, 0.0, 1.175), alu_m, bevel=0.008, parent=part_root, outline=0.003)
    tk.make_box(scene, "SecPartPostR", (0.06, 0.10, 2.35), (3.90, 0.0, 1.175), alu_m, bevel=0.008, parent=part_root, outline=0.003)
    tk.make_box(scene, "SecPartTopRail", (2.48, 0.08, 0.07), (2.685, 0.0, 2.315), alu_m, bevel=0.006, parent=part_root, outline=0.002)
    tk.make_box(scene, "SecPartBotRail", (2.48, 0.10, 0.12), (2.685, 0.0, 0.06), alu_m, bevel=0.006, parent=part_root, outline=0.002)
    tk.make_box(scene, "SecPartGlass", (2.38, 0.02, 2.16), (2.685, 0.0, 1.20), tk.glass_mat(), bevel=0.0, parent=part_root)

    sw_scr, _, _, _ = tk.load_glb("game/assets/interior/info_screen.glb", "SWScreen", loc=(-1.85, 8.85, 0.0), yaw_deg=-15.0)
    sw_plt, _, _, _ = tk.load_glb("game/assets/decor/tc_plant_pot_1a.glb", "SWPlant", loc=(-3.45, 8.85, 0.0), yaw_deg=90.0)

    events = []
    tt_root, _, _, _ = tk.load_glb("game/assets/interior/tray_table.glb", "TrayTable", loc=(-0.55, -1.15, 0.0))
    xb_root, xb_objs, xb_bn, _ = tk.load_glb("game/assets/interior/xray_belt.glb", "XrayBelt", loc=(-0.55, 0.0, 0.0))
    pt_root, pt_objs, _, _ = tk.load_glb("game/assets/interior/pickup_table.glb", "PickupTable", loc=(-0.55, 1.15, 0.0))
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

    # `SecOfficer` stationed on the CLEAR AIRSIDE side `(1.68, +1.65)` facing `-135°` with explicit elbow pole
    # so neither `SecArch` nor Hero occludes him or his wave-through gesture (`F-22`)!
    off_root, off_arm, off_objs, off_acts = tk.load_character(
        "tcp_male_character_07", "SecOfficer", cloth_tint=tk.OFFICER_BLUE, loc=(1.68, 1.65, 0.0), yaw_deg=-132.0
    )
    tk.set_stationary_clip(off_arm, off_acts, "idle", N, speed=1.08, phase_offset=22.0)
    tk.bind_hand_ik_target(
        scene,
        off_arm,
        "OfficerWaveThrough",
        hand="R",
        parent=off_root,
        pos_keys=[
            (86, (-0.28, -0.14, 1.20)),
            (96, (-0.34, -0.36, 1.58)),
            (108, (-0.18, -0.44, 1.64)),
            (118, (-0.32, -0.34, 1.56)),
            (130, (-0.28, -0.14, 1.20)),
        ],
        influence_keys=[(1, 0.0), (86, 0.0), (95, 0.92), (118, 0.92), (130, 0.0)],
        pole_parent=off_root,
        pole_loc=(-0.38, 0.35, 0.85),
    )

    # Stanchion poles & chains precisely matched to pole collar rings (`1.68m` pole spacing, `F-21`)!
    # `tc_metal_pole_chain_1a` raw y span is `[-1.8754, -0.1180]` (len `1.7574m`). With `scale.y = 0.91`,
    # chain span is `[-1.7066, -0.1074]` (`1.599m`), mating right onto pole collars (`±0.04m`) at `dy = 1.68m`!
    stanchions = []
    pole_objs_s3 = []
    chain_specs_s3 = []
    pole_ys = (-2.15, -3.83, -5.51)
    for si, sy in enumerate(pole_ys):
        sp, _, _, _ = tk.load_glb("game/assets/decor/tc_metal_pole_1a.glb", "QueuePoleL_%d" % si, loc=(1.38, sy, 0.0), outline_thickness=0.004)
        sp.scale = (0.55, 0.55, 0.68)
        stanchions.append(("QueuePole_%d" % si, sp))
        pole_objs_s3.append(sp)
    for si in range(2):
        y_hi = pole_ys[si]
        ch, _, _, _ = tk.load_glb(
            "game/assets/decor/tc_metal_pole_chain_1a.glb",
            "QueueChainL_%d" % si,
            loc=(1.38, y_hi + 0.067, -0.02),
            yaw_deg=0.0,
            outline_thickness=0.003,
        )
        ch.scale = (0.65, 0.91, 0.68)
        chain_specs_s3.append((ch, pole_objs_s3[si + 1], pole_objs_s3[si]))

    q1_root, q1_arm, q1_objs, q1_acts = tk.load_character(
        "tcp_female_character_04", "QueuePax1", cloth_tint=(0.24, 0.68, 0.66), loc=(2.02, -2.60, 0.0), yaw_deg=175.0
    )
    tk.set_stationary_clip(q1_arm, q1_acts, "idle", N, speed=1.05, phase_offset=8.0)
    # Offset `Q1Pack` cleanly outside `QueuePax1`'s dorsal Spine_02 surface (`z_local = -0.165`, `0` BVH overlap, `F-08`)!
    qpack, qpack_objs, _, _ = tk.load_glb("game/assets/interior/carry_backpack.glb", "Q1Pack", outline_thickness=0.004)
    tk.parent_prop_to_bone(qpack, q1_arm, "Spine_02", local_loc=(0.0, 0.03, -0.165), local_rot_deg=(0.0, 180.0, 0.0))

    q2_root, q2_arm, _, q2_acts = tk.load_character(
        "tcp_male_character_06", "QueuePax2", cloth_tint=(0.76, 0.52, 0.22), loc=(2.05, -3.75, 0.0), yaw_deg=182.0
    )
    tk.set_stationary_clip(q2_arm, q2_acts, "idle", N, speed=0.98, phase_offset=46.0)

    q3_root, q3_arm, _, q3_acts = tk.load_character(
        "tcp_female_character_11", "QueuePax3", cloth_tint=(0.68, 0.34, 0.64), loc=(2.00, -4.90, 0.0), yaw_deg=178.0
    )
    tk.set_stationary_clip(q3_arm, q3_acts, "idle", N, speed=1.02, phase_offset=91.0)

    # `SecPasserby` strolling strictly on the AIRSIDE side (`y = +1.85 -> +10.20`, never bypassing security, `F-21`)!
    bg_w, bg_wa, _, bg_wacts = tk.load_character(
        "tcp_male_character_09", "SecPasserby", cloth_tint=(0.35, 0.55, 0.82), loc=(2.85, 1.85, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(bg_w, bg_wa, bg_wacts, [(1, (2.85, 1.85, 0.0)), (N, (2.85, 10.20, 0.0))], N, phase_offset=19.0)

    # Trays centered strictly on `x = -0.55` conveyor centerline, starting stacked on `TrayTable` from `l = 4`
    # (zero mid-air pop!) and stopping well inside `PickupTable`'s `y = 1.50` lip (`0` tunnel/barrier overlap, `F-12`)!
    tray_root, tray_objs, _, _ = tk.load_glb("game/assets/interior/security_tray.glb", "HeroTray", loc=(-0.55, -0.98, 0.742))
    tray_root.scale = (1.12, 1.12, 1.0)
    tk.animate_snap_pop(tray_root, 5, drop_height=1.40)
    tk.key_pos(tray_root, [
        (18, (-0.55, -0.98, 0.742)),
        (56, (-0.55, -0.98, 0.742)),
        (132, (-0.55, 0.96, 0.742)),
        (N, (-0.55, 0.96, 0.742)),
    ])
    tk._set_fcurves_linear(tray_root)

    # Boarding pass continuity in Shot 3 (`F-07`): placed into `HeroTray` at `l = 35` and re-pinched in `Hand.L` at `l = 149`!
    tray_pass = _make_boarding_pass_card(scene, "TrayPass03", parent=tray_root)
    tray_pass.location = (0.12, -0.18, 0.025)
    tray_pass.rotation_euler = (0.0, 0.0, math.radians(78.0))
    for tm_o in tray_pass.children_recursive:
        if tm_o.type == "MESH":
            tm_o.hide_render = True
            tm_o.keyframe_insert(data_path="hide_render", frame=1)
            tm_o.keyframe_insert(data_path="hide_render", frame=24)
            tm_o.hide_render = False
            tm_o.keyframe_insert(data_path="hide_render", frame=25)
            tm_o.keyframe_insert(data_path="hide_render", frame=155)
            tm_o.hide_render = True
            tm_o.keyframe_insert(data_path="hide_render", frame=156)

    gag_tray, gag_objs, _, _ = tk.load_glb("game/assets/interior/security_tray.glb", "ComedyDuckTray", loc=(-0.55, -1.38, 0.742))
    gag_tray.scale = (0.68, 0.68, 0.88)
    duck_y = tk.toon_rgb_mat("duck_yellow", (1.0, 0.86, 0.12))
    duck_o = tk.toon_rgb_mat("duck_beak", (1.0, 0.44, 0.08))
    mug_r = tk.toon_rgb_mat("thermos_red", tk.ALERT_CORAL)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.12, location=(0.04, -0.05, 0.13))
    d_body = bpy.context.active_object
    d_body.name = "GagDuck_Body"
    d_body.scale = (1.12, 0.92, 0.82)
    d_body.data.materials.append(duck_y)
    tk.attach_outline(d_body, 0.004)
    d_body.parent = gag_tray
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=0.085, location=(0.10, -0.05, 0.24))
    d_head = bpy.context.active_object
    d_head.name = "GagDuck_Head"
    d_head.data.materials.append(duck_y)
    tk.attach_outline(d_head, 0.004)
    d_head.parent = gag_tray
    tk.make_box(scene, "GagDuck_Beak", (0.08, 0.07, 0.04), (0.18, -0.05, 0.23), duck_o, bevel=0.01, parent=gag_tray, outline=0.003)
    tk.make_box(scene, "GagThermos", (0.10, 0.10, 0.24), (-0.10, 0.08, 0.14), mug_r, bevel=0.025, parent=gag_tray, outline=0.004)
    gag_objs.extend([d_body, d_head])
    tk.animate_snap_pop(gag_tray, 6, drop_height=1.40)
    tk.key_pos(gag_tray, [
        (19, (-0.55, -1.38, 0.742)),
        (62, (-0.55, -1.38, 0.742)),
        (132, (-0.55, 1.32, 0.742)),
        (N, (-0.55, 1.32, 0.742)),
    ])
    tk._set_fcurves_linear(gag_tray)

    # Hero stands at `x = +0.02` (`0.19m` clear of `TrayTable` `x_max = -0.17`) and stoops `+42°` around `Spine` `+X` BEFORE grip solve!
    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.22, -4.60, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (0.22, -4.60, 0.0), 180.0),
            (28, (0.04, -0.96, 0.0), 205.0),
            (36, (0.04, -0.96, 0.0), -90.0),
            (55, (0.04, -0.96, 0.0), -90.0),
            (63, (0.04, -0.96, 0.0), 125.0),
            (74, (0.85, -0.38, 0.0)),
            (88, (0.85, 0.48, 0.0)),
            (114, (0.85, 0.90, 0.0)),
            (131, (0.04, 0.96, 0.0), -90.0),
            (144, (0.04, 0.96, 0.0), -90.0),
            (152, (0.04, 0.96, 0.0), 178.0),
            (168, (0.14, 2.05, 0.0)),
            (N, (0.15, 8.90, 0.0)),
        ],
        frame_end=N,
    )
    tk.bind_spine_stoop(
        scene,
        hero_arm,
        "SecTrayStoop",
        deg_x=36.5,
        influence_keys=[
            (1, 0.0),
            (28, 0.0), (34, 1.0), (50, 1.0), (55, 0.0),
            (130, 0.0), (135, 1.0), (142, 1.0), (147, 0.0),
        ],
    )
    tk.bind_head_look_at(
        scene,
        hero_arm,
        "HeroStoopBag",
        target_pos=[
            (1, (-0.55, -0.98, 0.65)),
            (60, (-0.55, -0.98, 0.65)),
            (130, (-0.55, 0.96, 0.65)),
            (N, (-0.55, 0.96, 0.65)),
        ],
        influence_keys=[
            (1, 0.0),
            (30, 0.0), (36, 0.70), (52, 0.70), (60, 0.0),
            (130, 0.0), (135, 0.70), (148, 0.70), (155, 0.0),
        ],
        include_spine=False,
    )

    held_pass_03 = _make_boarding_pass_card(scene, "HeroHeldPass03")
    tk.bind_card_in_pinch(
        scene,
        held_pass_03,
        hero_arm,
        hand="L",
        name="HeroPassPinch03",
        influence_keys=[(1, 1.0), (23, 1.0), (25, 0.0), (154, 0.0), (157, 1.0), (N, 1.0)],
    )
    for hp3_m in held_pass_03.children_recursive:
        if hp3_m.type == "MESH":
            hp3_m.hide_render = False
            hp3_m.keyframe_insert(data_path="hide_render", frame=1)
            hp3_m.keyframe_insert(data_path="hide_render", frame=24)
            hp3_m.hide_render = True
            hp3_m.keyframe_insert(data_path="hide_render", frame=25)
            hp3_m.keyframe_insert(data_path="hide_render", frame=155)
            hp3_m.hide_render = False
            hp3_m.keyframe_insert(data_path="hide_render", frame=156)

    # Custom security put-down / conveyor / snatch world trajectory for `HeroRoller03` (`l = 31..150`):
    # - Keep `HeroRoller03` in `rot.z = 180°..209°` throughout (no 180° suitcase spin!) with `"security"` handle notch
    #   (`top.y = -0.35`, `10.5cm` clear of `CarryRoller_Body` -> `0` finger-in-body BVH overlap!).
    # - Swing wide south-west around `(-0.36, -1.56)` -> `(-0.52, -1.18)` (put-down) and `(-0.52, +0.68)` -> `(-0.18, +0.30)` (snatch)
    #   so `CarryRoller_Body` stays `>= 0.20m` clear of Hero's `Hips` and `Quad.L/R`, with seamless two-hand pass on `Pull_Top`!
    sec_wps = [
        (31, (0.72, -1.36, 0.48), (-36.0, 0.0, 218.0)),
        (33, (0.52, -1.42, 0.82), (-34.0, 0.0, 220.0)),
        (35, (0.02, -1.62, 0.90), (-12.0, 0.0, 196.0)),
        (37, (-0.38, -1.52, 0.92), (-8.0, 0.0, 185.0)),
        (40, (-0.52, -1.16, 0.88), (-4.0, 0.0, 180.0)),
        (45, (-0.55, -0.98, 0.775), (0.0, 0.0, 180.0)),
        (56, (-0.55, -0.98, 0.775), (0.0, 0.0, 180.0)),
        (132, (-0.55, 0.96, 0.775), (0.0, 0.0, 180.0)),
        (138, (-0.55, 0.96, 0.775), (0.0, 0.0, 180.0)),
        (141, (-0.52, 0.68, 0.88), (-6.0, 0.0, 182.0)),
        (144, (-0.14, 0.30, 0.92), (-14.0, 0.0, 194.0)),
        (146, (0.24, 0.36, 0.90), (-26.0, 0.0, 206.0)),
        (148, (0.56, 0.42, 0.78), (-34.0, 0.0, 210.0)),
        (150, (0.66, 0.32, 0.30), (-38.0, 0.0, 208.0)),
    ]
    custom_s3 = {}
    for idx_w in range(len(sec_wps) - 1):
        fa_w, pa_w, ra_w = sec_wps[idx_w]
        fb_w, pb_w, rb_w = sec_wps[idx_w + 1]
        va, vb = Vector(pa_w), Vector(pb_w)
        for fm_w in range(fa_w, fb_w + 1):
            u_w = 0.0 if fb_w == fa_w else (fm_w - fa_w) / float(fb_w - fa_w)
            # Smoothstep only within moving heave/snatch arcs; keep conveyor (56..132) strictly linear!
            s_w = u_w if (fa_w == 56) else (u_w * u_w * (3.0 - 2.0 * u_w))
            vp = va.lerp(vb, s_w)
            vr = tuple(ra_w[k] + (rb_w[k] - ra_w[k]) * s_w for k in range(3))
            custom_s3[fm_w] = ((float(vp.x), float(vp.y), float(vp.z)), vr)

    bag_ref_holder = {}

    def _s3_left_override(f):
        if 41 <= f <= 56 or 132 <= f <= 140:
            br = bag_ref_holder.get("bag")
            if br is None:
                return None
            bmw = br.matrix_world
            bm3 = bmw.to_3x3()
            # Clasp the Hero-facing (`+X_world` = `local -X`) south-upper side rail (`(-0.188, +0.14, +0.14)`)
            # directly beneath `Arm.L` (`30cm` clear of `XrayBelt`, vertical natural arm, `0` BVH overlap!)
            front_out = (bm3 @ Vector((-1.0, 0.0, 0.0))).normalized()
            p_surf = bmw @ Vector((-0.188, 0.14, 0.14))
            z_h = -front_out
            x_h = (bm3 @ Vector((0.0, -1.0, 0.0))).normalized()
            y_h = z_h.cross(x_h).normalized()
            rm = Matrix(((x_h.x, y_h.x, z_h.x), (x_h.y, y_h.y, z_h.y), (x_h.z, y_h.z, z_h.z)))
            rel_d = 0.0
            if f > 50:
                rel_d = 0.11 * ((f - 50) / 6.0)
            elif 132 <= f < 136:
                rel_d = 0.11 * ((136 - f) / 4.0)
            pw_side = p_surf + front_out * (0.086 + rel_d) - y_h * 0.088
            q_side = rm.to_quaternion()
            # Smooth quadratic clearance arc (`+14cm` toward Hero, `+12cm` up) between `Pull_Top` and front-south clasp (`0` body overlap)!
            if 41 <= f <= 43 or 138 <= f <= 140:
                pt_ob = bag_by_n["Pull_Top"]
                p_pt = pt_ob.matrix_world @ Vector((0.0, -0.018, 0.004)) + Vector((0.06, 0.0, 0.10))
                w_s = (f - 40) / 4.0 if f <= 43 else (141 - f) / 4.0
                mid_arc = 0.5 * (p_pt + pw_side) + front_out * 0.25 + Vector((0.0, 0.0, 0.20))
                p_bez = ((1.0 - w_s) ** 2) * p_pt + (2.0 * (1.0 - w_s) * w_s) * mid_arc + (w_s ** 2) * pw_side
                return p_bez, q_side
            return pw_side, q_side
        return None

    def _s3_right_override(f):
        """Keep `Hand.R` naturally poised in front of Hero's right waist during the 4-frame south-side
        handoff (`35..39`, `142..145`) so `Arm.R` never drops to unconstrained stooped FK above his shoulder!"""
        if 35 <= f <= 39 or 142 <= f <= 145:
            hmw = hero_root.matrix_world
            hm3 = hmw.to_3x3()
            pw = hmw @ Vector((-0.24, -0.28, 0.98))
            xh = (hm3 @ Vector((-1.0, 0.0, 0.0))).normalized()
            yh = (hm3 @ Vector((0.0, -0.70, -0.71))).normalized()
            zh = xh.cross(yh).normalized()
            yh = zh.cross(xh).normalized()
            rm = Matrix(((xh.x, yh.x, zh.x), (xh.y, yh.y, zh.y), (xh.z, yh.z, zh.z)))
            return pw, rm.to_quaternion()
        return None

    r_ik_inf = [
        (1, 1.0), (50, 1.0), (55, 0.0),
        (131, 0.0), (135, 1.0), (N, 1.0),
    ]
    r_fist_inf = [
        (1, 1.0), (34, 1.0), (36, 0.25), (38, 0.25), (40, 1.0), (50, 1.0), (55, 0.0),
        (131, 0.0), (135, 1.0), (141, 1.0), (143, 0.25), (144, 0.25), (146, 1.0), (N, 1.0),
    ]

    bag_root, bag_by_n = _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller03",
        f_ik_ranges=[],
        pose_ranges=[(1, 30, "tow"), (31, 150, "custom"), (151, N, "tow")],
        custom_world_poses=custom_s3,
    )
    bag_ref_holder["bag"] = bag_root
    tk.set_roller_handle(bag_by_n, extended="tow", frame=1)
    tk.set_roller_handle(bag_by_n, extended="tow", frame=30)
    tk.set_roller_handle(bag_by_n, extended="tray", frame=33)
    tk.set_roller_handle(bag_by_n, extended="security", frame=36)
    tk.set_roller_handle(bag_by_n, extended="security", frame=144)
    tk.set_roller_handle(bag_by_n, extended="tray", frame=147)
    tk.set_roller_handle(bag_by_n, extended="tow", frame=150)
    tk.set_roller_handle(bag_by_n, extended="tow", frame=151)
    if bag_by_n.get("Pull_Reach"):
        tk._set_fcurves_linear(bag_by_n["Pull_Reach"])
    if bag_by_n.get("Pull_Top"):
        tk._set_fcurves_linear(bag_by_n["Pull_Top"])

    s3_bar_off = lambda f: (0.0, -0.056, 0.014) if (f <= 30 or f >= 151) else (0.0, -0.018, 0.004)
    tk.solve_roller_bar_grip_targets(
        scene,
        hero_root,
        hero_arm,
        bag_root,
        bag_by_n["Pull_Top"],
        "HeroRoller03",
        active_ranges=[(1, 50), (135, N)],
        hand="R",
        bind_ik=True,
        override_world_fn=_s3_right_override,
        fist_inf_keys=r_fist_inf,
        ik_inf_keys=r_ik_inf,
        bar_local_offset=s3_bar_off,
    )

    # `Hand.L` carries `Pull_Top` across the south swing (`34..40`, `141..146`) and smoothly clasps the front-south edge (`41..50`, `135..140`) with anatomical low outward elbow pole!
    l_ik_inf = [
        (1, 0.0),
        (32, 0.0), (34, 1.0), (50, 1.0), (55, 0.0),
        (130, 0.0), (135, 1.0), (146, 1.0), (149, 0.0),
    ]
    l_fist_inf = [
        (1, 0.0),
        (32, 0.0), (34, 1.0), (40, 1.0), (43, 0.22), (50, 0.22), (54, 0.0),
        (132, 0.0), (136, 0.22), (138, 0.22), (141, 1.0), (146, 1.0), (148, 0.0),
    ]
    tk.solve_roller_bar_grip_targets(
        scene,
        hero_root,
        hero_arm,
        bag_root,
        bag_by_n["Pull_Top"],
        "HeroRoller03_L",
        active_ranges=[(34, 50), (136, 146)],
        hand="L",
        bind_ik=True,
        override_world_fn=_s3_left_override,
        fist_inf_keys=l_fist_inf,
        ik_inf_keys=l_ik_inf,
        bar_local_offset=(0.0, -0.018, 0.004),
    )

    tk.bind_head_look_at(
        scene,
        off_arm,
        "OfficerMonitorDoubleTake",
        target_pos=(-0.55, 0.0, 1.42),
        influence_keys=[(1, 0.0), (68, 0.0), (76, 0.88), (88, 0.88), (94, 0.0)],
        include_spine=True,
    )
    for idx_q, q_arm in enumerate((off_arm, q1_arm, q2_arm, q3_arm)):
        tk.bind_head_look_at(scene, q_arm, "WatchHero3_%d" % idx_q, target_obj=hero_root, max_inf=0.48)

    cam, target = tk.make_camera(scene, "Shot03Cam", lens=33.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (-4.35, -4.95, 1.92)),
        (52, (-4.45, -1.85, 2.26)),
        (90, (-4.25, 0.55, 2.34)),
        (120, (-4.35, 0.85, 2.30)),
        (155, (-4.45, 0.75, 2.18)),
        (N, (-4.25, 3.65, 1.84)),
    ])
    tk.key_pos(target, [
        (1, (0.35, -3.45, 1.06)),
        (52, (-0.10, -0.95, 1.04)),
        (110, (0.55, 0.55, 1.12)),
        (155, (-0.10, 1.25, 1.06)),
        (N, (0.15, 7.65, 1.12)),
    ])

    events.extend([
        {"type": "roller", "frame": g0 + 1, "dur": 28},
        {"type": "skid", "frame": g0 + 29},
        {"type": "conveyor", "frame": g0 + 56, "dur": 76},
        {"type": "scanner_beep", "frame": g0 + 92},
        {"type": "bag_snatch", "frame": g0 + 140},
        {"type": "roller", "frame": g0 + 158, "dur": 66},
        {"type": "door_whoosh", "frame": g0 + 162},
    ])
    for f in list(range(2, 30, 7)) + list(range(62, 130, 10)) + list(range(158, N, 7)):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("hero_f%03d" % fl, fl, hero_objs) for fl in range(1, 212, 15)
    ] + [
        ("officer_f495", 105, off_objs),
        ("end", 210, hero_objs),
    ]

    xb_wall_meshes = [xb_bn["XrayBelt_Body"], xb_bn["Screen_Face_Mesh"]] if "XrayBelt_Body" in xb_bn else xb_objs
    bag3_meshes = [m for m in bag_root.children_recursive if m.type == "MESH"]
    motion_spec = {
        "obstacle_roots": [
            ("SWScreen", sw_scr),
            ("SWPlant", sw_plt),
            ("TrayTable", tt_root, 0.12),
            ("XrayBelt", xb_root),
            ("PickupTable", pt_root, 0.12),
            ("SecGlassPartition", part_root),
        ] + stanchions,
        "extra_boxes_xy": [
            ("EastGlassWall", 3.85, 4.2, -11.5, 10.0),
            ("NorthWall_Left", -7.8, -1.05, 9.35, 9.65),
            ("NorthWall_Mid", 1.35, 1.75, 9.35, 9.65),
            ("NorthWall_Right", 3.95, 4.3, 9.35, 9.65),
        ],
        "seated_exempt": set(),
        "pulled_rollers": [
            (hero_root, hero_arm, bag_by_n["CarryRoller_Body"], 0.0, [(1, 28), (153, N)]),
        ],
        "roller_grip_checks": [
            (hero_root, hero_arm, bag_root, bag_by_n["Pull_Top"], [(1, 28), (153, N)]),
        ],
        "door_checks": [
            {"kind": "bvh_zero_overlap", "label": "Q1Pack_vs_QueuePax1", "objs_a": qpack_objs, "objs_b": q1_objs, "frames": (1, 10)},
            {"kind": "bvh_zero_overlap", "label": "Bag_vs_XrayBeltWalls", "objs_a": bag3_meshes, "objs_b": xb_wall_meshes, "frames": (56, 132)},
            {
                "kind": "bvh_zero_overlap",
                "label": "DuckTray_vs_XrayWalls",
                "objs_a": [m for m in gag_objs if m.type == "MESH"],
                "objs_b": xb_wall_meshes,
                "frames": (62, 132),
            },
        ],
        "prop_checks": [
            {"kind": "unheld_bag_stationary", "bag_root": bag_root, "arm": hero_arm, "conveyor_frames": (56, 132)},
            {"kind": "boarding_pass_pinch", "card": held_pass_03, "holders": [(hero_root, hero_arm, "L")], "frames": (1, 23)},
            {"kind": "boarding_pass_pinch", "card": held_pass_03, "holders": [(hero_root, hero_arm, "L")], "frames": (157, N)},
        ],
        "shot_continuity_checks": [
            {"kind": "unoccluded_bone_at_frame", "frame": 105, "char_root": off_root, "arm": off_arm, "bone": "Hand.R"},
            {"kind": "stanchion_chain_fit", "chains": chain_specs_s3},
            {"kind": "arm_elbows_below_shoulders", "char_root": hero_root, "arm": hero_arm, "hands": ("L", "R"), "frames": (34, 55), "min_drop_m": 0.045},
            {"kind": "arm_elbows_below_shoulders", "char_root": hero_root, "arm": hero_arm, "hands": ("L", "R"), "frames": (134, 150), "min_drop_m": 0.045},
        ],
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 4 (195 frames = 6.5s): Bustling Gate Concourse Sprint & Boarding Pass Flash
# ==============================================================================


def build_shot_04(g0):
    N = 195
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.08, indoor=True)
    tk.build_enclosed_terminal_hall(
        scene,
        x_min=-5.2,
        x_max=8.5,
        y_min=-13.5,
        y_max=5.5,
        ceil_z=3.85,
        glass_side="left",
        open_north_wall=True,
        south_openings=[(0.0, 2.80)],
    )

    for gx in (-5, -4, -3, -2, 2, 3, 4, 5, 6, 7):
        tk.load_glb("game/assets/interior/wall_glass.glb", "AirGlass_%d" % gx, loc=(float(gx), 5.5, 0.0), yaw_deg=0.0)
    for wx in range(-12, 6, 2):
        wgl, _, _, _ = tk.load_glb("game/assets/interior/wall_glass.glb", "SideGlassL_%d" % wx, loc=(-5.15, float(wx), 0.0), yaw_deg=90.0)
        wgl.scale = (2.0, 1.0, 1.0)

    # Airside Apron + `OutsideGottaJet` matching Shot 5 Part A (`yaw_deg = 0.0`, open integrated fold-down airstair + handrails + marshaller, `F-14`, `F-23`)!
    tk.load_glb("game/assets/airside/tp_runway_02a.glb", "OutsideApron", loc=(0.0, 38.0, -0.02), yaw_deg=0.0, outline_thickness=0.0)
    tk.make_box(scene, "OutsideGrass", (260.0, 180.0, 0.08), (0.0, 120.0, -0.06), tk.horizon_grass_mat(), bevel=0.0)
    ext_plane_r, ext_plane_objs, ext_plane_bn, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "OutsideGottaJet", loc=(-1.4, 28.5, 0.0), yaw_deg=0.0, outline_thickness=0.004
    )
    _apply_gotta_air_livery(ext_plane_objs)
    _spin_jet_fans(scene, ext_plane_r, ext_plane_bn, N, deg_per_frame=32.0)
    _setup_jet_landing_gear(scene, ext_plane_r, ext_plane_bn, mode="parked")
    _rig_integrated_jet_airstair(scene, ext_plane_r, ext_plane_bn, "OutsideJet", close_frames=None, frame_end=N)

    tk.load_glb("game/assets/airside/props/pushback_tug.glb", "OutsideTug", loc=(-7.5, 18.0, 0.0), yaw_deg=25.0)
    ext_marsh_r, ext_marsh_a, _, ext_marsh_acts = tk.load_character(
        "tcp_male_character_07", "OutsideMarshaller", cloth_tint=tk.GOTTA_LIME, loc=(2.8, 16.5, 0.0), yaw_deg=145.0
    )
    tk.set_stationary_clip(ext_marsh_a, ext_marsh_acts, "idle", N, speed=1.05, phase_offset=12.0)

    cafe_c, _, _, _ = tk.load_glb("game/assets/interior/cafe_counter.glb", "Cafe", loc=(-3.35, -7.2, 0.0), yaw_deg=90.0)
    cafe_t, _, _, _ = tk.load_glb("game/assets/interior/cafe_table.glb", "CafeTbl1", loc=(-2.65, -4.6, 0.0), yaw_deg=90.0)
    tk.make_box(scene, "CafeSaucer", (0.15, 0.15, 0.018), (-2.65, -4.74, 0.858), tk.toon_rgb_mat("mug_white", tk.CREAM), bevel=0.006)
    tk.make_box(scene, "CafeMug", (0.095, 0.095, 0.115), (-2.65, -4.74, 0.918), tk.toon_rgb_mat("mug_coral", tk.HERO_CORAL), bevel=0.015, outline=0.003)

    seats1, _, _, _ = tk.load_glb("game/assets/interior/seat_row.glb", "Seats1", loc=(-2.75, -1.8, 0.0), yaw_deg=90.0)
    seats2, _, _, _ = tk.load_glb("game/assets/interior/seat_row.glb", "Seats2", loc=(-2.75, 1.2, 0.0), yaw_deg=90.0)
    in_tree, _, _, _ = tk.load_glb("game/assets/decor/tc_tree_3a_indoor.glb", "IndoorTree", loc=(-3.55, 3.35, 0.0))
    tk.make_sliding_glass_door_unit(
        scene,
        "BackHallDoor",
        loc=(0.0, -13.5, 0.0),
        yaw_deg=0.0,
        clear_width=1.36,
        total_width=2.80,
        height=2.22,
        total_height=2.45,
        open_keys=[(1, 0.0)],
    )
    df_shelf, _, _, _ = tk.load_glb("game/assets/interior/duty_free_shelf.glb", "DutyFreeBg", loc=(3.2, -9.8, 0.0), yaw_deg=-90.0)

    bar_r, bar_a, _, bar_acts = tk.load_character("tcp_female_character_07", "CafeBarista", cloth_tint=(0.68, 0.36, 0.20), loc=(-4.25, -7.2, 0.0), yaw_deg=90.0)
    tk.set_stationary_clip(bar_a, bar_acts, "idle", N, speed=1.08, phase_offset=15.0)
    c1_r, c1_a, _, c1_acts = tk.load_character("tcp_female_character_08", "CafePax", cloth_tint=(0.78, 0.38, 0.62), loc=(-2.35, -7.2, 0.0), yaw_deg=-90.0)
    tk.set_stationary_clip(c1_a, c1_acts, "idle", N, speed=1.02, phase_offset=52.0)

    # All 4 seated passengers snapped to exact measured seat-pan centers (`0` armrest/chair/table BVH overlap, `F-13`)!
    c2_r, c2_a, _, c2_acts = tk.load_character("tcp_male_character_04", "CafeSitPax", cloth_tint=(0.30, 0.62, 0.54), loc=(-2.65, -5.01, 0.0), yaw_deg=180.0)
    tk.set_stationary_clip(c2_a, c2_acts, "sit_idle", N, speed=1.0, phase_offset=24.0)

    s1_r, s1_a, _, s1_acts = tk.load_character("tcp_female_character_01", "SitPax1", cloth_tint=(0.45, 0.66, 0.92), loc=(-2.09, -2.80, 0.032), yaw_deg=90.0)
    tk.set_stationary_clip(s1_a, s1_acts, "sit_idle", N, speed=0.98, phase_offset=0.0)
    s2_r, s2_a, _, s2_acts = tk.load_character("tcp_male_character_03", "SitPax2", cloth_tint=(0.86, 0.68, 0.25), loc=(-2.10, -0.80, 0.025), yaw_deg=90.0)
    tk.set_stationary_clip(s2_a, s2_acts, "sit_idle", N, speed=1.04, phase_offset=38.0)
    s3_r, s3_a, _, s3_acts = tk.load_character("tcp_female_character_09", "SitPax3", cloth_tint=(0.88, 0.48, 0.42), loc=(-2.10, 1.20, 0.025), yaw_deg=90.0)
    tk.set_stationary_clip(s3_a, s3_acts, "sit_idle", N, speed=0.95, phase_offset=74.0)

    stroll_r, stroll_a, _, stroll_acts = tk.load_character("tcp_male_character_05", "ConcourseStroller", cloth_tint=(0.38, 0.46, 0.72), loc=(-1.18, -11.2, 0.0), yaw_deg=180.0)
    tk.animate_character_locomotion(stroll_r, stroll_a, stroll_acts, [(1, (-1.18, -11.2, 0.0)), (N, (-1.18, -2.6, 0.0))], N, phase_offset=11.0)

    events = [{"type": "pa_chime", "frame": g0 + 6}]

    gd_root, _, _, _ = tk.load_glb("game/assets/interior/gate_desk.glb", "GateDesk", loc=(-2.30, 3.75, 0.0), yaw_deg=-10.0)
    tk.animate_snap_pop(gd_root, 24, drop_height=1.50)
    events.append({"type": "pop", "frame": g0 + 27, "pitch": 8})

    # `GateDoor` centered at `x = 0.0` spanning `[-1.50, +1.50]` x `[0.0, 2.45]` flush with `AirGlass_-2`, `AirGlass_2`, and `NorthGlassSoffit` (`F-06`)!
    door_root, _ = tk.make_sliding_glass_door_unit(
        scene,
        "GateDoor",
        loc=(0.0, 5.50, 0.0),
        yaw_deg=0.0,
        clear_width=1.42,
        total_width=3.00,
        height=2.22,
        total_height=2.45,
        open_keys=[(1, 0.0), (80, 0.0), (112, 1.0), (N, 1.0)],
    )
    tk.animate_snap_pop(door_root, 34, drop_height=1.60)
    events.append({"type": "pop", "frame": g0 + 37, "pitch": 10})
    events.append({"type": "door_whoosh", "frame": g0 + 84})

    # `GateSign_ROOT` lowered to `z = 2.22 m` with ceiling suspension struts so 100% of text stays inside safe frame (`F-18`)!
    sign_root, sign_core = tk.make_hanging_terminal_sign(
        scene, "GateSign_ROOT", "GATE C · OSLO", loc=(-0.22, 5.15, 2.22), yaw_deg=0.0, width=2.45, height=0.44, ceil_z=3.85, text_size=0.24
    )
    tk.animate_snap_pop(sign_root, 42, drop_height=1.05)
    events.append({"type": "pop", "frame": g0 + 45, "pitch": 12})

    # `GateAgent` holding `GateScannerGun` along `Hand.R.x_axis` inside a `+X` curled fist with forward reach & explicit pole (`F-08`, `F-22`)!
    ga_root, ga_arm, _, ga_acts = tk.load_character(
        "tcp_female_character_07", "GateAgent", cloth_tint=tk.GOTTA_LIME, loc=(-0.74, 4.45, 0.0), yaw_deg=68.0
    )
    tk.set_stationary_clip(ga_arm, ga_acts, "idle", N, speed=1.10, phase_offset=31.0)
    scanner_ob = tk.make_box(scene, "GateScannerGun", (0.042, 0.16, 0.048), (0.0, 0.0, 0.0), tk.toon_rgb_mat("scan_gun", tk.NAVY), bevel=0.008, outline=0.003)
    tk.bind_prop_in_palm(
        scene,
        scanner_ob,
        ga_arm,
        hand="R",
        name="AgentScannerGrip",
        local_loc=(-0.03, 0.096, 0.036),
        local_rot_deg=(0.0, 0.0, 90.0),
    )
    tk.bind_hand_ik_target(
        scene,
        ga_arm,
        "AgentScanHold",
        hand="R",
        parent=ga_root,
        pos_keys=[
            (1, (-0.18, -0.38, 1.24)),
            (118, (-0.14, -0.44, 1.30)),
            (145, (-0.12, -0.46, 1.34)),
            (172, (-0.20, -0.40, 1.48)),
            (N, (-0.18, -0.38, 1.28)),
        ],
        influence_keys=[(1, 0.90), (N, 0.90)],
        pole_parent=ga_root,
        pole_loc=(-0.38, 0.35, 0.85),
    )

    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(0.02, -11.2, 0.0), yaw_deg=180.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[(1, (0.02, -11.2, 0.0)), (N, (-0.08, 10.4, 0.0))],
        frame_end=N,
    )
    bag04_root, bag04_by_n = _attach_towed_roller(hero_root, hero_arm, "HeroRoller04", f_ik_ranges=[(1, N)])
    pass04 = _make_boarding_pass_card(scene, "HeroHeldPass04")
    tk.bind_card_in_pinch(scene, pass04, hero_arm, hand="L", name="HeroPassPinch04")
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "FlashPassLeft",
        hand="L",
        parent=hero_root,
        pos_keys=[
            (116, (0.26, -0.18, 1.22)),
            (134, (0.38, -0.28, 1.42)),
            (150, (0.36, -0.26, 1.40)),
            (166, (0.26, -0.18, 1.22)),
        ],
        influence_keys=[(1, 0.0), (116, 0.0), (130, 0.92), (150, 0.92), (166, 0.0)],
        pole_parent=hero_root,
        pole_loc=(0.38, 0.35, 0.85),
    )
    events.append({"type": "scanner_beep", "frame": g0 + 140})

    for idx_s, s_arm in enumerate((s1_a, s2_a, s3_a, ga_arm)):
        tk.bind_head_look_at(scene, s_arm, "ConcourseWatch_%d" % idx_s, target_obj=hero_root, max_inf=0.56)

    cam, target = tk.make_camera(scene, "Shot04Cam", lens=30.0, fstop=2.8)
    tk.key_pos(cam, [
        (1, (3.45, -6.5, 1.46)),
        (98, (3.95, -1.8, 1.54)),
        (N, (1.35, 1.15, 1.58)),
    ])
    tk.key_pos(target, [
        (1, (-0.05, -10.4, 1.00)),
        (98, (-0.15, -0.4, 1.04)),
        (N, (-0.10, 8.2, 1.12)),
    ])

    events.append({"type": "roller", "frame": g0 + 1, "dur": N - 2})
    for f in range(3, N, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    prove_targets = [
        ("hero_f%03d" % fl, fl, hero_objs) for fl in range(1, 162, 15)
    ] + [
        ("gate_sign", 120, sign_core),
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
            ("NorthGlassLeft", -5.4, -0.75, 5.38, 5.65),
            ("NorthGlassRight", 0.75, 8.8, 5.38, 5.65),
        ],
        "seated_exempt": {"CHAR_CafeSitPax", "CHAR_SitPax1", "CHAR_SitPax2", "CHAR_SitPax3", "CHAR_OutsideMarshaller"},
        "seated_mounts": [
            (c2_r, cafe_t, (-2.68, -5.55)),
            (s1_r, seats1, (-2.65, -2.83)),
            (s2_r, seats1, (-2.65, -0.83)),
            (s3_r, seats2, (-2.65, 1.17)),
        ],
        "pulled_rollers": [
            (hero_root, hero_arm, bag04_by_n["CarryRoller_Body"], 0.0, [(1, N)]),
        ],
        "roller_grip_checks": [
            (hero_root, hero_arm, bag04_root, bag04_by_n["Pull_Top"], [(1, N)]),
        ],
        "prop_checks": [
            {"kind": "boarding_pass_pinch", "card": pass04, "holders": [(hero_root, hero_arm, "L")]},
            {"kind": "staff_prop_palm", "arm": ga_arm, "hand": "R", "prop": scanner_ob, "shaft_axis": (0.0, 1.0, 0.0)},
        ],
        "aircraft_checks": [
            {
                "kind": "cabin_floor_containment",
                "plane_root": ext_plane_r,
                "fuselage": ext_plane_bn["TP_Plane_05A_Fuselage"],
                "cabin_floor": scene.objects["OutsideJet_CabinAisleFloor"],
                "max_local_x": 0.76,
                "frames": (1, 1),
            },
        ],
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 5 (210 frames = 7.0s): Integrated Airstair Boarding -> Left-to-Right Takeoff
# ==============================================================================


def build_shot_05(g0):
    N = 210
    CUT_F = 89  # f=1..88: Apron Stand Integrated Airstair Boarding & Door Seal | f=89..210: Left-to-Right Takeoff!
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.18, indoor=False)
    tk.make_box(scene, "AirfieldGrass", (1200.0, 1200.0, 0.12), (0.0, 0.0, -0.07), tk.horizon_grass_mat(), bevel=0.0)
    tk.add_horizon_hills_and_treeline(scene)

    tk.make_box(scene, "ApronConcretePad", (78.0, 190.0, 0.08), (-22.0, 84.0, -0.035), tk.toon_rgb_mat("apron_pad", (0.36, 0.39, 0.44)), bevel=0.0)
    tk.make_box(scene, "StandLeadLine", (0.18, 28.0, 0.015), (-22.0, 18.0, 0.01), tk.toon_rgb_mat("stand_yellow", tk.YELLOW), bevel=0.0)

    # Active Striped Runway along x = +24.0 (viewed from west camera at x = -18.0 so jet rolls & climbs LEFT-TO-RIGHT, `F-15`!)
    for ry in (32.0, -32.0, -96.0, -160.0, -224.0, -288.0, -352.0):
        tk.load_glb("game/assets/airside/tp_runway_02a.glb", "Runway_%d" % int(ry), loc=(24.0, ry, 0.0), yaw_deg=90.0, outline_thickness=0.0)

    # Warm exterior facade glazing on `BgTerminal` (`F-17`) and placed at `y = 172.0` so the entire `"AIRPORT"` roof sign sits cleanly inside frame (`v_ndc <= 0.88`, `F-26`)!
    _, bg_ap_objs, _, _ = tk.load_glb("game/assets/buildings/tp_airport_01a.glb", "BgTerminal", loc=(-22.0, 172.0, 0.0), yaw_deg=0.0, outline_thickness=0.004)
    tk.warm_exterior_facade_windows(bg_ap_objs)

    bg_p3_r, bg_p3_objs, bg_p3_bn, _ = tk.load_glb("game/assets/planes/tp_plane_03a.glb", "BgPropPlane", loc=(-32.0, 38.0, 0.0), yaw_deg=-25.0, outline_thickness=0.004)
    _apply_gotta_air_livery(bg_p3_objs)
    tk.add_plane_wheel_chocks(scene, bg_p3_r, bg_p3_bn, "BgProp")

    tk.load_glb("game/assets/vehicles/tp_loading_truck_01a.glb", "BgTruck", loc=(-28.5, 24.0, 0.0), yaw_deg=55.0, outline_thickness=0.004)
    tk.load_glb("game/assets/airside/props/taxi_sign.glb", "TaxiSignShoulder", loc=(36.0, -22.0, 0.0), yaw_deg=125.0)

    tk.add_toon_clouds(scene, [
        (85, -180, 58, 3.2),
        (95, -90, 66, 3.6),
        (88, -20, 56, 3.0),
    ])

    # ---- PART A (f = 1..88): APRON STAND INTEGRATED AIRSTAIR BOARDING (-22.0, +18.0) ----
    stand_jet_r, stand_jet_objs, stand_jet_bn, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "StandGottaJet", loc=(-22.0, 18.0, 0.0), yaw_deg=0.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(stand_jet_objs)
    _spin_jet_fans(scene, stand_jet_r, stand_jet_bn, N, deg_per_frame=38.0)
    _setup_jet_landing_gear(scene, stand_jet_r, stand_jet_bn, mode="parked")
    _, stand_door, stand_rail_meshes = _rig_integrated_jet_airstair(
        scene, stand_jet_r, stand_jet_bn, "StandJet", close_frames=(70, 82), frame_end=N
    )
    fus_non_seam_bvh = _build_fuselage_non_seam_bvh(stand_jet_r, stand_jet_bn["TP_Plane_05A_Fuselage"])

    # Ramp Marshaller holding dual orange marshalling wands along `Hand.L/R.x_axis` inside `+X` curled fists (`F-08`, `F-22`)!
    marsh_r, marsh_a, marsh_objs, marsh_acts = tk.load_character(
        "tcp_male_character_07", "RampMarshaller", cloth_tint=tk.GOTTA_LIME, loc=(-16.8, 5.2, 0.0), yaw_deg=145.0
    )
    tk.set_stationary_clip(marsh_a, marsh_acts, "idle", N, speed=1.1, phase_offset=5.0)
    wand_m = tk.emissive_mat("marsh_wand", (1.0, 0.42, 0.08), strength=1.8)
    wand_objs = []
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        wand = tk.make_box(scene, "MarshallWand_" + side, (0.036, 0.36, 0.036), (0.0, 0.0, 0.0), wand_m, bevel=0.008, outline=0.003)
        wand_objs.append(wand)
        tk.bind_prop_in_palm(
            scene,
            wand,
            marsh_a,
            hand=side,
            name="MarshallWandGrip_" + side,
            local_loc=(0.10 if side == "L" else -0.10, 0.096, 0.036),
            local_rot_deg=(0.0, 0.0, 90.0),
        )
        tk.bind_hand_ik_target(
            scene,
            marsh_a,
            "MarshallWave",
            hand=side,
            parent=marsh_r,
            pos_keys=[
                (1, (sgn * 0.34, -0.26, 1.58)),
                (22, (sgn * 0.22, -0.30, 1.78)),
                (44, (sgn * 0.36, -0.26, 1.56)),
                (66, (sgn * 0.22, -0.30, 1.78)),
                (88, (sgn * 0.32, -0.24, 1.66)),
            ],
            influence_keys=[(1, 0.92), (CUT_F - 1, 0.92), (CUT_F, 0.0)],
            pole_parent=marsh_r,
            pole_loc=(sgn * 0.38, 0.35, 0.85),
        )

    # Exact surface elevation profile of `TP_Plane_05A_Door` folded down at `ry = +137°` (`StandGottaJet.x = -22.0`):
    # Bottom step starts at `x_plane = 2.08` (`x_world = -19.92, z = 0.00`), rising linearly across the 6 horizontal treads
    # to the cabin threshold `x_plane = 0.86` (`x_world = -21.14, z = 1.54`)!
    def _stair_surf_z(hx_w):
        xl = float(hx_w) - (-22.0)
        if xl >= 2.12:
            return 0.0
        if xl > 1.92:
            return 0.228 * ((2.12 - xl) / 0.20)
        if xl > 0.86:
            return 0.228 + (1.540 - 0.228) * ((1.92 - xl) / (1.92 - 0.86))
        return 1.540

    hero_root, hero_arm, hero_objs, hero_acts = tk.load_character(
        "tcp_male_character_01", "Hero", cloth_tint=tk.HERO_CORAL, loc=(-16.20, 10.05, 0.0), yaw_deg=-68.0
    )
    tk.animate_character_locomotion(
        hero_root,
        hero_arm,
        hero_acts,
        waypoints=[
            (1, (-16.20, 10.05, 0.0)),
            (18, (-19.78, 9.34, 0.0)),
            (35, (-20.78, 9.34, 1.40)),
            (49, (-22.58, 9.34, 1.54)),
            (59, (-22.58, 10.75, 1.54)),
            (N, (-22.58, 10.75, 1.54)),
        ],
        frame_end=N,
    )

    z_keys_s5 = []
    slope_weights = {}
    for f_s5 in range(1, N + 1):
        scene.frame_set(f_s5)
        hx_s5, hy_s5, _ = hero_root.location
        hx_f = float(hx_s5)
        w_up = max(0.0, min(1.0, (-19.65 - hx_f) / 0.25))
        w_dn = max(0.0, min(1.0, (hx_f - (-21.16)) / 0.22))
        sw = min(w_up, w_dn)
        slope_weights[f_s5] = sw
        sz_root = _stair_surf_z(hx_f) - 0.036 * sw
        z_keys_s5.append((f_s5, (hx_f, float(hy_s5), sz_root)))
    scene.frame_set(1)
    tk.key_pos(hero_root, z_keys_s5)
    tk._set_fcurves_linear(hero_root)

    # Boarding pass continuity into Shot 5 (`F-07`): carried in `Hand.L` on apron run (`l = 1..17`), tucked into jacket
    # right as `Hand.L` grasps the left airstair handrail (`l = 19..50`, `F-16`)!
    pass05 = _make_boarding_pass_card(scene, "HeroHeldPass05")
    tk.bind_card_in_pinch(
        scene,
        pass05,
        hero_arm,
        hand="L",
        name="HeroPassPinch05",
        influence_keys=[(1, 1.0), (16, 1.0), (19, 0.0)],
    )
    for p5_m in pass05.children_recursive:
        if p5_m.type == "MESH":
            p5_m.hide_render = False
            p5_m.keyframe_insert(data_path="hide_render", frame=1)
            p5_m.keyframe_insert(data_path="hide_render", frame=17)
            p5_m.hide_render = True
            p5_m.keyframe_insert(data_path="hide_render", frame=18)

    # Sliding `Hand.L` IK along the left fold-out airstair handrail (`y_world ≈ 9.01`) during climb (`l = 19..49`, `F-16`)!
    rail_ik_keys = []
    for f_rk in range(18, 52):
        scene.frame_set(f_rk)
        hx_rk = float(hero_root.location.x)
        rx_w = hx_rk - 0.14
        rz_w = _stair_surf_z(rx_w) + 0.88
        rail_ik_keys.append((f_rk, (rx_w, 9.02, min(2.38, rz_w))))
    scene.frame_set(1)
    tk.bind_hand_fist_curl(
        scene,
        hero_arm,
        "StairRailFistL",
        hand="L",
        influence_keys=[(1, 0.0), (18, 0.0), (21, 1.0), (47, 1.0), (52, 0.0)],
        mode="fist",
    )
    tk.bind_hand_ik_target(
        scene,
        hero_arm,
        "StairHandrailSlide",
        hand="L",
        pos_keys=rail_ik_keys,
        influence_keys=[(1, 0.0), (18, 0.0), (21, 0.94), (47, 0.94), (52, 0.0)],
        pole_parent=hero_root,
        pole_loc=(0.38, 0.35, 0.85),
    )

    ankle_keys = {"L": [], "R": []}
    toe_keys = {"L": [], "R": []}
    for f_s5 in range(1, N + 1):
        scene.frame_set(f_s5)
        bpy.context.view_layer.update()
        hx_f = float(hero_root.location.x)
        hz_f = float(hero_root.location.z)
        sw = slope_weights[f_s5]
        stride_scale = 1.0 - 0.52 * sw
        for side in ("L", "R"):
            pb_f = hero_arm.pose.bones["Foot." + side]
            aw = hero_arm.matrix_world @ pb_f.head
            ax = hx_f + stride_scale * (float(aw.x) - hx_f)
            ay = float(aw.y)
            fk_h = float(aw.z) - (hz_f + 0.036 * sw)
            h_sw = max(0.0, fk_h - 0.095) * 0.24
            surf_f = max(_stair_surf_z(ax), _stair_surf_z(ax - 0.22))
            ankle_keys[side].append((f_s5, (ax, ay, surf_f + 0.132 + h_sw)))
            toe_x = ax - 0.24
            toe_keys[side].append((f_s5, (toe_x, ay, max(surf_f, _stair_surf_z(toe_x)) + 0.072 + 0.5 * h_sw)))
    scene.frame_set(1)
    for side in ("L", "R"):
        ag = bpy.data.objects.new("StairAnkleGoal_" + side, None)
        scene.collection.objects.link(ag)
        tk.key_pos(ag, ankle_keys[side])
        tk._set_fcurves_linear(ag)
        tg = bpy.data.objects.new("StairToeGoal_" + side, None)
        scene.collection.objects.link(tg)
        tk.key_pos(tg, toe_keys[side])
        tk._set_fcurves_linear(tg)

        pb_shin = hero_arm.pose.bones["Shin." + side]
        pb_shin.rotation_mode = "QUATERNION"
        ik_leg = pb_shin.constraints.new("IK")
        ik_leg.name = "IK_Stair_" + side
        ik_leg.target = ag
        ik_leg.chain_count = 2
        for fk_i, iv in ((1, 0.0), (15, 0.0), (18, 1.0), (59, 1.0), (61, 0.0)):
            ik_leg.influence = iv
            ik_leg.keyframe_insert(data_path="influence", frame=fk_i)

        pb_foot = hero_arm.pose.bones["Foot." + side]
        pb_foot.rotation_mode = "QUATERNION"
        dt_foot = pb_foot.constraints.new("DAMPED_TRACK")
        dt_foot.name = "LevelFoot_Stair_" + side
        dt_foot.target = tg
        dt_foot.track_axis = "TRACK_Y"
        for fk_i, iv in ((1, 0.0), (15, 0.0), (18, 0.95), (59, 0.95), (61, 0.0)):
            dt_foot.influence = iv
            dt_foot.keyframe_insert(data_path="influence", frame=fk_i)

    # Carry roller outboard up the lower stairs (`19..25`), then swing to right-rear hip (`cabin_carry`, `31..59`) BEFORE the 0.99m doorway!
    bag05_root, bag05_by_n = _attach_towed_roller(
        hero_root,
        hero_arm,
        "HeroRoller05",
        f_ik_ranges=[(1, 59)],
        pose_ranges=[(1, 11, "tow"), (19, 25, "carry"), (31, N, "cabin_carry")],
    )

    # Hero walks straight `-X` to `x = -21.95` before turning aft to `y = 10.65` behind the opaque fuselage wall (`hide_render` at `l = 60`, `F-16`)!
    for ho_s5 in list(hero_objs) + list(bag05_root.children_recursive):
        if ho_s5.type == "MESH":
            ho_s5.hide_render = False
            ho_s5.keyframe_insert(data_path="hide_render", frame=1)
            ho_s5.keyframe_insert(data_path="hide_render", frame=59)
            ho_s5.hide_render = True
            ho_s5.keyframe_insert(data_path="hide_render", frame=60)

    stand_hide_meshes = [
        o for o in (list(stand_jet_r.children_recursive) + list(marsh_objs) + wand_objs)
        if o.type == "MESH"
    ]
    for sm in stand_hide_meshes:
        if sm in stand_rail_meshes:
            continue
        sm.hide_render = False
        sm.keyframe_insert(data_path="hide_render", frame=1)
        sm.keyframe_insert(data_path="hide_render", frame=CUT_F - 1)
        sm.hide_render = True
        sm.keyframe_insert(data_path="hide_render", frame=CUT_F)

    # ---- PART B (f = 89..210): SMOOTH ACCELERATING LEFT-TO-RIGHT RUNWAY TAKEOFF & GEAR RETRACTION ----
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "GottaAirJet", loc=(24.0, 8.0, 0.0), yaw_deg=0.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=56.0)
    _setup_jet_landing_gear(scene, plane_root, plane_by_n, mode="takeoff_retract", f_roll_start=CUT_F, f_retract_start=146, f_retract_end=178, f_end=N)

    # Smooth quadratic takeoff acceleration (`v_0 = 11.5 m/s` ramping monotonically `a = 9.0 m/s^2` to `44 m/s`, `F-17`)
    # AND rear-main-wheel axle (`y_local = +2.142 m`) pitch compensation so wheels stay tangent (`z_min >= -0.008 m`, `F-09`)!
    jet_pos_keys = [(1, (24.0, -2.0, 0.015))]
    jet_rot_keys = [(1, (0.0, 0.0, 0.0))]
    y_cur = -2.0
    v_cur = 11.5
    for fl_b in range(CUT_F, N + 1):
        dt_f = 1.0 / tk.FPS
        if fl_b > CUT_F:
            accel = 9.5 if fl_b <= 145 else 4.0
            v_cur += accel * dt_f
            y_cur -= v_cur * dt_f

        # Smooth nose-up rotation starting l=120, liftoff at l=134
        if fl_b <= 120:
            rx_deg = 0.0
        elif fl_b <= 152:
            u_r = (fl_b - 120) / 32.0
            s_r = u_r * u_r * (3.0 - 2.0 * u_r)
            rx_deg = -13.5 * s_r
        else:
            u_r2 = (fl_b - 152) / float(N - 152)
            rx_deg = -13.5 - 1.5 * u_r2

        roll_deg = 0.0 if fl_b <= 155 else -4.0 * ((fl_b - 155) / float(N - 155))
        # Rear-gear axle z compensation (`2.142 * sin(|rx|)`) + smooth climb after liftoff (`fl_b > 132`)!
        z_axle = 0.014 + 2.15 * math.sin(abs(math.radians(rx_deg)))
        if fl_b <= 132:
            z_jet = z_axle
        else:
            t_air = (fl_b - 132) / float(N - 132)
            z_jet = z_axle + 22.8 * (t_air ** 1.65)
        jet_pos_keys.append((fl_b, (24.0, float(y_cur), float(z_jet))))
        jet_rot_keys.append((fl_b, (float(rx_deg), float(roll_deg), 0.0)))

    tk.key_pos(plane_root, jet_pos_keys)
    tk.key_rot_deg(plane_root, jet_rot_keys)
    tk._set_fcurves_linear(plane_root)

    # Camera: Part A (`1..88`) frames integrated airstair climb cleanly below `BgTerminal`'s roof sign (`F-27`);
    # Part B (`89..210`) views from the WEST (`x = -16.5`) looking EAST (`+X`) so `-Y` runway takeoff moves
    # **LEFT-TO-RIGHT** (`du > 0`), matching Shot 6 & the 2D white airplane icon in `logo_a_sticker.png` (`F-15`)!
    cam, target = tk.make_camera(scene, "Shot05Cam", lens=35.0, fstop=3.2)
    tk.key_pos(cam, [
        (1, (-11.6, 3.2, 2.05)),
        (56, (-14.2, 3.8, 2.25)),
        (CUT_F - 1, (-13.6, 3.6, 2.30)),
        (CUT_F, (-16.5, -18.0, 4.2)),
        (145, (-16.5, -72.0, 8.2)),
        (N, (-18.0, -148.0, 19.5)),
    ])
    tk.key_pos(target, [
        (1, (-17.2, 9.8, 1.08)),
        (56, (-20.8, 9.4, 1.62)),
        (CUT_F - 1, (-20.4, 9.4, 1.58)),
        (CUT_F, (24.0, -4.0, 3.0)),
        (124, (24.0, -25.0, 3.4)),
        (154, (24.0, -56.0, 6.4)),
        (N, (24.0, float(y_cur) + 4.0, 24.0)),
    ])
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
        {"type": "roller", "frame": g0 + 1, "dur": 18},
        {"type": "step_leap", "frame": g0 + 20},
        {"type": "door_seal", "frame": g0 + 80},
        {"type": "jet_spool", "frame": g0 + CUT_F, "dur": N - CUT_F},
        {"type": "takeoff_whoosh", "frame": g0 + 136},
    ]
    for f in range(3, 68, 7):
        events.append({"type": "footstep", "frame": g0 + f})

    plane_core = [plane_by_n["TP_Plane_05A_Fuselage"]]
    prove_targets = [
        ("start_hero", 1, hero_objs),
        ("step_f829", 19, hero_objs),
        ("board_f845", 35, hero_objs),
        ("mid_jet", 115, plane_core),
        ("end_jet", N, plane_core),
    ]

    jet_wheels = [plane_by_n[wn] for wn in ("TP_Plane_05A_Wheel_F", "TP_Plane_05A_Wheel_R.L", "TP_Plane_05A_Wheel_R.R") if wn in plane_by_n]
    ext_hatches = [plane_by_n[hn] for hn in ("TP_Plane_05A_Hatch_Ext_F", "TP_Plane_05A_Hatch_Ext_R.L", "TP_Plane_05A_Hatch_Ext_R.R") if hn in plane_by_n]
    all_gear_h = [o for o in plane_objs if o.type == "MESH" and any(k in o.name for k in ("Gear", "Wheel", "Hatch"))]
    bag5_meshes = [m for m in bag05_root.children_recursive if m.type == "MESH"]

    motion_spec = {
        "obstacle_roots": [],
        "extra_boxes_xy": [],
        "seated_exempt": set(),
        "exempt_ranges": {"CHAR_Hero": [(56, N)], "CHAR_RampMarshaller": [(CUT_F, N)]},
        "pulled_rollers": [
            (hero_root, hero_arm, bag05_by_n["CarryRoller_Body"], 0.0, [(1, 11)]),
        ],
        "roller_grip_checks": [
            (hero_root, hero_arm, bag05_root, bag05_by_n["Pull_Top"], [(1, 11), (19, 59)]),
        ],
        "stair_foot_checks": [
            (hero_root, 19, 48, _stair_surf_z),
        ],
        "door_checks": [
            {
                "kind": "bvh_zero_overlap",
                "label": "StandJetDoor_vs_Fuselage",
                "objs_a": [stand_door],
                "static_bvh_b": fus_non_seam_bvh,
                "frames": (1, CUT_F - 1),
            },
            {
                "kind": "bvh_zero_overlap",
                "label": "HeroBag05_vs_Fuselage",
                "objs_a": bag5_meshes,
                "static_bvh_b": fus_non_seam_bvh,
                "frames": (1, 59),
            },
        ],
        "prop_checks": [
            {"kind": "boarding_pass_pinch", "card": pass05, "holders": [(hero_root, hero_arm, "L")], "frames": (1, 16)},
            {"kind": "staff_prop_palm", "arm": marsh_a, "hand": "L", "prop": wand_objs[0], "shaft_axis": (0.0, 1.0, 0.0), "frames": (1, CUT_F - 1)},
            {"kind": "staff_prop_palm", "arm": marsh_a, "hand": "R", "prop": wand_objs[1], "shaft_axis": (0.0, 1.0, 0.0), "frames": (1, CUT_F - 1)},
        ],
        "aircraft_checks": [
            {
                "kind": "cabin_floor_containment",
                "plane_root": stand_jet_r,
                "fuselage": stand_jet_bn["TP_Plane_05A_Fuselage"],
                "cabin_floor": scene.objects["StandJet_CabinAisleFloor"],
                "max_local_x": 0.76,
                "frames": (1, 1),
            },
            {"kind": "ground_roll_wheels", "plane_root": plane_root, "wheels": jet_wheels, "frames": (CUT_F, 134)},
            {"kind": "stowed_belly_clean", "plane_root": plane_root, "ext_hatches": ext_hatches, "all_gear_and_hatches": all_gear_h, "frames": (185, N)},
        ],
        "shot_continuity_checks": [
            {"kind": "occluded_before_hide", "last_vis_frame": 59, "objs": hero_objs, "label": "Shot05_HeroCabinEntry"},
        ],
    }
    return scene, cam, prove_targets, hero_arm, events, motion_spec


# ==============================================================================
# SHOT 6 (165 frames = 5.5s): Left-to-Right Sky Climb + World Wingtip Vapor + Logo
# ==============================================================================


def build_shot_06(g0):
    N = 165
    scene, _sun = tk.init_shot_scene(N, golden_strength=1.22, indoor=False)

    cloud_field = [
        (-52, -78, 12, 3.2),
        (38, -68, 10, 2.9),
        (-12, -96, 9, 3.8),
        (54, -105, 18, 2.9),
        (-68, -118, 19, 3.4),
        (8, -128, 14, 4.0),
        (-24, -52, 8, 2.1),
        (26, -50, 9, 2.2),
    ]
    tk.add_toon_clouds(scene, cloud_field, seed_scale=1.15)

    # Gotta Air Jet climbing LEFT-TO-RIGHT in the clean upper-third azure sky (`>= 95 px` above Logo & Dotted Arc, `F-15`, `F-25`)
    # with all 6 bay doors flush (`mode='stowed'`, `F-09`) and exterior-only livery (`F-14`)!
    plane_root, plane_objs, plane_by_n, _ = tk.load_glb(
        "game/assets/planes/tp_plane_05a.glb", "SkyGottaJet", loc=(54.0, -58.0, 29.5), yaw_deg=-61.0, outline_thickness=0.005
    )
    _apply_gotta_air_livery(plane_objs)
    _spin_jet_fans(scene, plane_root, plane_by_n, N, deg_per_frame=58.0)
    _setup_jet_landing_gear(scene, plane_root, plane_by_n, mode="stowed")

    tk.key_pos(plane_root, [
        (1, (54.0, -58.0, 29.5)),
        (N, (-86.0, -136.0, 53.5)),
    ])
    tk.key_rot_deg(plane_root, [
        (1, (-9.5, -15.0, -61.0)),
        (N, (-10.5, -7.0, -61.0)),
    ])
    tk._set_fcurves_linear(plane_root)

    cam, target = tk.make_camera(scene, "Shot06Cam", lens=34.0, fstop=4.0, dof_dist=88.0)
    tk.key_pos(cam, [(1, (22.0, 12.0, 15.5)), (N, (-18.0, -6.0, 20.5))])
    tk.key_pos(target, [(1, (48.0, -58.0, 20.0)), (N, (-78.0, -134.0, 36.5))])
    tk._set_fcurves_linear(cam)
    tk._set_fcurves_linear(target)

    fus = plane_by_n["TP_Plane_05A_Fuselage"]
    tips_and_ribbons = _build_world_wingtip_vapor_trails(scene, plane_root, fus, cam, N)

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
    ext_hatches6 = [plane_by_n[hn] for hn in ("TP_Plane_05A_Hatch_Ext_F", "TP_Plane_05A_Hatch_Ext_R.L", "TP_Plane_05A_Hatch_Ext_R.R") if hn in plane_by_n]
    all_gear6 = [o for o in plane_objs if o.type == "MESH" and any(k in o.name for k in ("Gear", "Wheel", "Hatch"))]
    motion_spec = {
        "obstacle_roots": [],
        "extra_boxes_xy": [],
        "seated_exempt": set(),
        "aircraft_checks": [
            {"kind": "stowed_belly_clean", "plane_root": plane_root, "ext_hatches": ext_hatches6, "all_gear_and_hatches": all_gear6},
            {"kind": "wingtip_vapor_lock", "fuselage": fus, "tips_and_ribbons": tips_and_ribbons},
        ],
    }
    return scene, cam, prove_targets, None, events, motion_spec


SHOT_BUILDERS = [
    build_shot_01,
    build_shot_02,
    build_shot_03,
    build_shot_04,
    build_shot_05,
    build_shot_06,
]
