class_name TestAirfieldHangarLife
extends GdUnitTestSuite
## Verifies the view-local, SimClock-synced Living Operations Apron:
## maintenance plane + cones + tug grounded & clear on the hangar lead-in line,
## pulsing red beacons & warm hangar bay glow accents using GLOW_MATERIAL,
## rotating radar dish & swaying windsock sock, closed-loop vehicle patrols,
## rigged mechanic walk/inspect cycles, pause freeze, and fail-loud clock fallback.

const STATIC_LANDMARKS := [
	{"name": "tower", "rect": Rect2(-101.52, -442.97, 19.04, 34.61)},
	{"name": "radar", "rect": Rect2(-129.54, -416.66, 7.08, 3.32)},
	{"name": "hangar_01a", "rect": Rect2(-20.00, -455.81, 64.00, 67.62)},
	{"name": "hangar_02a", "rect": Rect2(64.00, -445.00, 64.00, 34.00)},
	{"name": "windsock", "rect": Rect2(-56.55, -390.55, 4.37, 1.10)},
	{"name": "cistern_1", "rect": Rect2(-54.85, -417.51, 4.33, 7.39)},
	{"name": "cistern_2", "rect": Rect2(-46.85, -417.51, 4.33, 7.39)},
	{"name": "pickup_parked", "rect": Rect2(-67.10, -402.89, 4.41, 5.75)},
	{"name": "bus_parked", "rect": Rect2(-35.98, -399.86, 13.31, 3.33)},
	{"name": "truck_1", "rect": Rect2(55.61, -400.51, 11.36, 5.77)},
	{"name": "truck_2", "rect": Rect2(80.53, -401.10, 3.06, 11.85)},
]

var _clock: SimClock
var _airside: Airside
var _flights: FlightSim
var _backdrop: AirfieldBackdrop
var _life: AirfieldOperationsLife


func before() -> void:
	_clock = SimClock.new()
	_clock.paused = true
	_airside = TestStandLaneClearance.scene_airside()
	_flights = FlightSim.new()
	_flights.clock = _clock
	_flights.runway.size = Runway.SMALL
	_backdrop = AirfieldBackdrop.new()
	_backdrop.airside = _airside
	_backdrop.flights = _flights
	add_child(_clock)
	add_child(_flights)
	add_child(_airside)
	add_child(_backdrop)
	_life = _backdrop.get_node("OperationsLife") as AirfieldOperationsLife


func before_test() -> void:
	_clock.tick = 0
	_clock.speed = 1
	_clock.paused = false
	_clock._accumulator = 0.0
	_life.sync_to_clock()


func after() -> void:
	_backdrop.free()
	_airside.free()
	_flights.free()
	_clock.free()


func test_maintenance_plane_cones_and_tug_grounded_and_north_safe() -> void:
	assert_object(_life).is_not_null()
	assert_object(_life.clock).is_same(_clock)

	var plane := _life.get_node("MaintenancePlane") as Node3D
	assert_object(plane).is_not_null()
	var plane_box := _world_aabb(plane)
	assert_float(absf(plane_box.position.y)).is_less_equal(0.05)
	assert_float(plane_box.end.z).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
	assert_float(plane_box.end.z).is_less_equal(AirfieldBackdrop.NORTH_SAFE_Z_MAX)
	assert_bool(_xz_inside_apron(plane_box)).is_true()
	# Clear south of tp_hangar_02a (z_max = -411.0).
	assert_float(plane_box.position.z).is_greater(-411.0)
	_assert_tinted_plane_glass(plane)

	var cones := _life.get_node("MaintenanceCones") as Node3D
	assert_int(cones.get_child_count()).is_equal(6)
	for cone in cones.get_children():
		var cbox := _world_aabb(cone as Node3D)
		assert_float(absf(cbox.position.y)).is_less_equal(0.05)
		assert_float(cbox.end.z).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
		assert_bool(_xz_inside_apron(cbox)).is_true()

	var tug := _life.get_node("MaintenanceTug") as Node3D
	assert_object(tug).is_not_null()
	var tbox := _world_aabb(tug)
	assert_float(absf(tbox.position.y)).is_less_equal(0.05)
	assert_float(tbox.end.z).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
	assert_bool(_xz_inside_apron(tbox)).is_true()


func test_beacons_and_bay_lights_use_glow_material_and_pulse_with_sim_clock() -> void:
	var glows := _life.get_node("ApronGlows") as MultiMeshInstance3D
	assert_object(glows).is_not_null()
	assert_object(glows.material_override).is_same(AirfieldBackdrop.GLOW_MATERIAL)
	var mm := glows.multimesh
	var beacon_count := AirfieldOperationsLife.obstruction_beacon_specs().size()
	var bay_count := AirfieldOperationsLife.hangar_bay_glow_specs().size()
	assert_int(beacon_count).is_equal(8)
	assert_int(bay_count).is_equal(6)
	assert_int(mm.instance_count).is_equal(beacon_count + bay_count)

	for i in mm.instance_count:
		var pos := _life.glow_transform(i).origin
		assert_float(pos.z).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
		if i >= beacon_count:
			assert_float(pos.y).is_greater_equal(13.0)

	_life.sync_to_clock()
	var c0 := _life.glow_color(0)
	_advance_clock(0.35)
	_life.sync_to_clock()
	var c_peak := _life.glow_color(0)
	assert_float(absf(c_peak.a - c0.a)).is_greater(0.50)

	_advance_clock(0.70)
	_life.sync_to_clock()
	var c_trough := _life.glow_color(0)
	assert_float(absf(c_peak.a - c_trough.a)).is_greater(0.75)

	_clock.paused = true
	_advance_clock(0.35)
	_life._process(0.35)
	assert_float(_life.glow_color(0).a).is_equal_approx(c_trough.a, 0.0001)


func test_radar_dish_rotates_and_windsock_sways_on_sim_clock() -> void:
	var pivot := _backdrop.find_child("RadarDishPivot", true, false) as Node3D
	var dish := _backdrop.find_child("TP_Radar_01A_Dish", true, false) as MeshInstance3D
	var swivel := _backdrop.find_child("Windsock_Swivel", true, false) as Node3D
	var plinth := _backdrop.find_child("Windsock_Body", true, false) as Node3D
	assert_object(pivot).is_not_null()
	assert_object(dish).is_not_null()
	assert_object(swivel).is_not_null()
	assert_object(plinth).is_not_null()

	# Verify dish stays centered atop radar mast (-126, -415) across full 360 deg rotation.
	var mast_xz := Vector2(-126.0, -415.0)
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		pivot.rotation.y = angle
		var dish_box := _world_aabb(dish)
		var dish_center := dish_box.get_center()
		assert_float(Vector2(dish_center.x, dish_center.z).distance_to(mast_xz)).is_less_equal(1.0)
		assert_float(dish_center.y).is_greater(23.0)
	_life.sync_to_clock()

	var dish_yaw_0 := pivot.rotation.y
	var sock_yaw_0 := swivel.rotation.y
	var plinth_rot_0 := plinth.rotation
	_advance_clock(1.2)
	_life.sync_to_clock()
	assert_float(absf(pivot.rotation.y - dish_yaw_0)).is_greater(0.5)
	assert_float(absf(swivel.rotation.y - sock_yaw_0)).is_greater(0.05)
	assert_vector(plinth.rotation).is_equal_approx(plinth_rot_0, Vector3(0.0001, 0.0001, 0.0001))

	var dish_paused := pivot.rotation.y
	var sock_paused := swivel.rotation.y
	_clock.paused = true
	_advance_clock(1.2)
	_life._process(1.2)
	assert_float(pivot.rotation.y).is_equal_approx(dish_paused, 0.0001)
	assert_float(swivel.rotation.y).is_equal_approx(sock_paused, 0.0001)


func test_patrol_vehicles_sweep_full_loop_north_safe_with_stops_and_pause() -> void:
	var routes := AirfieldOperationsLife.patrol_routes()
	assert_int(routes.size()).is_equal(2)
	var static_obstacles := _all_static_rects()

	for r_idx in routes.size():
		var spec := routes[r_idx]
		var track := AirfieldOperationsLife.build_patrol_track(spec)
		var cycle_s: float = track["cycle_s"]
		var is_truck := String(spec["stem"]) == "tp_loading_truck_02a"
		var hx := 1.59 if is_truck else 1.39
		var hz := 5.93 if is_truck else 2.83
		var saw_moving := false
		var saw_paused := false
		var step := 0.25
		var t := 0.0
		while t <= cycle_s + 0.01:
			var pose := AirfieldOperationsLife.sample_patrol_track(track, t)
			if pose["moving"]:
				saw_moving = true
			else:
				saw_paused = true
			var box := _rotated_rect_xz(pose["pos"], pose["yaw"], hx, hz)
			assert_bool(AirfieldBackdrop.APRON_RECT.encloses(box)).is_true()
			assert_float(box.end.y).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
			assert_float(box.end.y).is_less_equal(AirfieldBackdrop.NORTH_SAFE_Z_MAX)
			for obs: Dictionary in static_obstacles:
				var min_d := _rect_distance(box, obs["rect"])
				(
					assert_float(min_d)
					. override_failure_message(
						(
							"%s collided with %s at t=%.2f dist=%.2f"
							% [spec["name"], obs["name"], t, min_d]
						)
					)
					. is_greater_equal(0.95)
				)
			t += step
		assert_bool(saw_moving).is_true()
		assert_bool(saw_paused).is_true()

	var pickup := _life.get_node("PatrolVehicles/WestApronPickup") as Node3D
	var p0 := pickup.position
	_advance_clock(4.0)
	_life.sync_to_clock()
	var d_1x := pickup.position.distance_to(p0)
	assert_float(d_1x).is_greater(5.0)

	_clock.paused = true
	var p_paused := pickup.position
	_advance_clock(2.0)
	_life._process(2.0)
	assert_vector(pickup.position).is_equal_approx(p_paused, Vector3(0.0001, 0.0001, 0.0001))

	_clock.paused = false
	_clock.speed = 3
	var p_before_3x := pickup.position
	_advance_clock(1.0)
	_life.sync_to_clock()
	assert_float(pickup.position.distance_to(p_before_3x)).is_greater(10.0)


func test_mechanics_walk_and_inspect_synced_to_sim_clock() -> void:
	var schedules := AirfieldOperationsLife.mechanic_schedules()
	assert_int(schedules.size()).is_equal(3)
	var mech_root := _life.get_node("Mechanics") as Node3D
	assert_int(mech_root.get_child_count()).is_equal(3)

	var static_obstacles := _all_static_rects()
	for s_idx in schedules.size():
		var spec := schedules[s_idx]
		var tl := AirfieldOperationsLife.build_mechanic_timeline(spec)
		var cycle_s: float = tl["cycle_s"]
		var saw_walk := false
		var saw_idle := false
		var t := 0.0
		while t <= cycle_s + 0.01:
			var pose := AirfieldOperationsLife.sample_mechanic_timeline(tl, t)
			if pose["clip"] == "walk":
				saw_walk = true
			elif pose["clip"] == "idle":
				saw_idle = true
			var pos: Vector3 = pose["pos"]
			assert_float(pos.z).is_less_equal(AirfieldOperationsLife.SAFE_Z_LIMIT)
			assert_float(pos.z).is_less_equal(AirfieldBackdrop.NORTH_SAFE_Z_MAX)
			assert_bool(AirfieldBackdrop.APRON_RECT.has_point(Vector2(pos.x, pos.z))).is_true()
			var m_rect := Rect2(pos.x - 0.30, pos.z - 0.30, 0.60, 0.60)
			for obs: Dictionary in static_obstacles:
				if String(spec["name"]) == "MechanicHangarBay" and obs["name"] == "hangar_01a":
					continue
				assert_float(_rect_distance(m_rect, obs["rect"])).is_greater_equal(0.45)
			t += 0.25
		assert_bool(saw_walk).is_true()
		assert_bool(saw_idle).is_true()

	var m0 := mech_root.get_child(0) as Node3D
	var p0 := m0.position
	var player0 := m0.get_node("AnimationPlayer") as AnimationPlayer
	var saw_walk_live := false
	var saw_idle_live := false
	for _i in 35:
		_advance_clock(0.5)
		_life.sync_to_clock()
		if player0.current_animation == "walk":
			saw_walk_live = true
		elif player0.current_animation == "idle":
			saw_idle_live = true
	assert_bool(saw_walk_live).is_true()
	assert_bool(saw_idle_live).is_true()
	assert_float(m0.position.distance_to(p0)).is_greater(1.0)

	_clock.speed = 3
	_life.sync_to_clock()
	assert_float(player0.speed_scale).is_greater(2.0)

	_clock.paused = true
	var frozen_pos := m0.position
	_advance_clock(1.0)
	_life._process(1.0)
	assert_float(player0.speed_scale).is_equal_approx(0.0, 0.0001)
	assert_vector(m0.position).is_equal_approx(frozen_pos, Vector3(0.0001, 0.0001, 0.0001))

	# Backward clock jump / load reset restores exact mechanic pose and AnimationPlayer phase.
	_clock.paused = false
	_clock.speed = 1
	_clock.tick = 70
	_clock._accumulator = 0.0
	_life.sync_to_clock()
	var pos_at_70 := m0.position
	var clip_at_70 := player0.current_animation
	var anim_pos_at_70 := player0.current_animation_position
	assert_str(clip_at_70).is_equal("walk")
	assert_float(anim_pos_at_70).is_greater(0.1)

	_clock.tick = 240
	_life.sync_to_clock()
	assert_float(m0.position.distance_to(pos_at_70)).is_greater(1.0)

	_clock.tick = 70
	_life.sync_to_clock()
	assert_vector(m0.position).is_equal_approx(pos_at_70, Vector3(0.0001, 0.0001, 0.0001))
	assert_str(player0.current_animation).is_equal(clip_at_70)
	assert_float(player0.current_animation_position).is_equal_approx(anim_pos_at_70, 0.01)


func _advance_clock(real_seconds: float) -> void:
	var step := 0.1
	var count := roundi(real_seconds / step)
	var rem := real_seconds - float(count) * step
	for _i in count:
		_clock.advance(step)
	if rem > 1e-4:
		_clock.advance(rem)


func test_missing_clock_fails_loud_and_runs_degraded_cleanly() -> void:
	var bare := AirfieldOperationsLife.new()
	(
		assert_error(func() -> void: add_child(bare))
		. is_push_error("AirfieldOperationsLife: missing clock; operations apron runs degraded")
	)
	var pickup := bare.get_node("PatrolVehicles/WestApronPickup") as Node3D
	var p0 := pickup.position
	bare._process(1.5)
	assert_float(pickup.position.distance_to(p0)).is_greater(1.0)
	remove_child(bare)
	bare.free()


func _all_static_rects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in STATIC_LANDMARKS:
		out.append(item)
	var ppos: Vector3 = AirfieldOperationsLife.maintenance_plane_spec()["pos"]
	out.append({"name": "plane_wings", "rect": Rect2(ppos.x - 7.06, ppos.z - 0.50, 14.12, 1.70)})
	out.append({"name": "plane_fuselage", "rect": Rect2(ppos.x - 1.65, ppos.z - 6.46, 3.30, 10.68)})
	out.append({"name": "plane_tail", "rect": Rect2(ppos.x - 2.25, ppos.z - 5.47, 4.50, 0.88)})
	var cones := AirfieldOperationsLife.maintenance_cone_specs()
	for i in cones.size():
		var cpos: Vector3 = cones[i]["pos"]
		out.append({"name": "cone_%d" % i, "rect": Rect2(cpos.x - 0.44, cpos.z - 0.44, 0.88, 0.88)})
	var tspec := AirfieldOperationsLife.maintenance_tug_spec()
	var tpos: Vector3 = tspec["pos"]
	out.append({"name": "maint_tug", "rect": Rect2(tpos.x - 3.85, tpos.z - 3.85, 5.45, 5.45)})
	return out


static func _rotated_rect_xz(pos: Vector3, yaw_rad: float, hx: float, hz: float) -> Rect2:
	var c := absf(cos(yaw_rad))
	var s := absf(sin(yaw_rad))
	var rx := c * hx + s * hz
	var rz := s * hx + c * hz
	return Rect2(pos.x - rx, pos.z - rz, 2.0 * rx, 2.0 * rz)


static func _rect_distance(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dz).length()


static func _xz_inside_apron(box: AABB) -> bool:
	var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return AirfieldBackdrop.APRON_RECT.encloses(r)


static func _world_aabb(root_node: Node3D) -> AABB:
	var out := AABB()
	var has := false
	var root_xf := root_node.global_transform if root_node.is_inside_tree() else root_node.transform
	var stack: Array = [[root_node, root_xf]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var b := xf * mi.mesh.get_aabb()
				out = b if not has else out.merge(b)
				has = true
		for child in node.get_children():
			var cxf := xf * (child as Node3D).transform if child is Node3D else xf
			stack.append([child, cxf])
	return out


func _assert_tinted_plane_glass(plane: Node3D) -> void:
	var found := 0
	for mi in plane.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		for s in mesh_inst.mesh.get_surface_count():
			var base_mat := mesh_inst.mesh.surface_get_material(s)
			if base_mat != null and base_mat.resource_name == PlaneView.GLASS_MATERIAL_NAME:
				var ov := mesh_inst.get_surface_override_material(s)
				assert_object(ov).is_same(PlaneView.TINTED_GLASS_MATERIAL)
				found += 1
	assert_int(found).is_greater(0)
