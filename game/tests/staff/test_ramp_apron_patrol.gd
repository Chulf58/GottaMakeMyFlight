class_name TestRampApronPatrol
extends GdUnitTestSuite
## Regression tests for deterministic airside apron patrol, clipboard check
## pauses, stagger, safe stand margins, clock rollback reset (6d949060), and
## job pose/transition preservation for idle Role.RAMP agents.

const RAMP := StaffMember.Role.RAMP
const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld
var _views: StaffCharacters
var _dispatch: RampDispatch
var _finances: Finances
var _rating: AirportRating


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null
	_dispatch = null
	_finances = null
	_rating = null


func _idle_starts() -> Array[int]:
	return [0, 0, 0, 0, 0, 100, 5000, 6200, 6260, 6380, 6680, 6880]


func _setup_world(starts: Array[int] = []) -> String:
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	var timing := starts if not starts.is_empty() else _idle_starts()
	_world = PassengerTestWorld.make(grid, timing, 17)
	_world.sim.site = SITE
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_world.sim.wallet = _finances.wallet
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)
	var fid := "RAMP-0"
	_world.flights.runway.size = PlaneClasses.MEDIUM
	var terms := {
		"id": "RAMP",
		"airline": "Nordic Jet",
		"destination": "Bergen",
		"departure_minute": 480,
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": 30,
		"fee_per_passenger": 30,
	}
	_world.flights._contracts.append(
		_world.flights._candidate(terms, "C", _world.flights.gate_grounds())
	)
	_world.flights._insert(_world.flights._record(fid, timing, "C", "RAMP", 0))
	_world.flights._changed()
	_views = StaffCharacters.new()
	_views.clock = _world.clock
	_views.staff = _world.staff
	_views.flights = _world.flights
	add_child(_views)
	return fid


func _add_second_stand(stands: Dictionary, gate_id: String, door_x: float, wall_z: float) -> void:
	stands[gate_id] = {
		"stand": StandPlacement.make(9001, door_x, wall_z),
		"max_class": PlaneClasses.MEDIUM,
	}


func test_idle_ramp_agent_patrols_waypoints_with_clipboard_pauses_and_walk_yaw() -> void:
	_setup_world()
	var ramp_id := _world.staff.hire(RAMP)
	_views.sync(true)
	_views.draw()
	var node := _views.node_for(ramp_id)
	assert_object(node).is_not_null()

	var distinct_positions: Array[Vector3] = []
	var saw_idle_clipboard := false
	var saw_walk_clip := false
	var walk_yaw_ok := false
	var prev_walk_pos := Vector3.ZERO
	var had_prev_walk := false

	for _i in 360:
		_world.step()
		_views.draw()
		var pos := node.position
		var is_new := true
		for seen_pos in distinct_positions:
			if Vector2(seen_pos.x, seen_pos.z).distance_to(Vector2(pos.x, pos.z)) < 1.2:
				is_new = false
				break
		if is_new:
			distinct_positions.append(pos)
		var clip := String(node.get_meta(&"clip", ""))
		var prop := _views.hand_prop_of(ramp_id)
		if clip == "idle" and prop == StaffHandProps.PropKind.CLIPBOARD:
			saw_idle_clipboard = true
		if clip == "walk":
			saw_walk_clip = true
			assert_int(prop).is_equal(StaffHandProps.PropKind.NONE)
			if had_prev_walk:
				var delta := pos - prev_walk_pos
				var flat := Vector2(delta.x, delta.z)
				if flat.length() > 0.02:
					var expected_yaw := atan2(flat.x, flat.y)
					var yaw_diff := absf(angle_difference(node.rotation.y, expected_yaw))
					assert_float(yaw_diff).is_less(0.35)
					walk_yaw_ok = true
			prev_walk_pos = pos
			had_prev_walk = true
		else:
			had_prev_walk = false

	assert_int(distinct_positions.size()).is_greater_equal(3)
	assert_bool(saw_walk_clip).is_true()
	assert_bool(walk_yaw_ok).is_true()
	assert_bool(saw_idle_clipboard).is_true()


func _assert_clear_of_stands(pos: Vector3, stands: Dictionary, check_wall := true) -> void:
	var cell := _world.grid.world_to_cell(pos)
	assert_bool(_world.grid.is_indoor(cell)).is_false()
	for gate_key: String in stands:
		var s: Dictionary = stands[gate_key]["stand"]
		var local := StandPlacement.to_frame(s, pos)
		var twin := StandPlacement.north_twin(s)
		var pt := StandPlacement.stand_point(twin)
		var wall_z := float(twin["wall_z"])
		if check_wall:
			assert_float(local.z).is_less_equal(wall_z - 1.4)
		if local.z >= wall_z - 32.0:
			var dx := absf(local.x - pt.x)
			var dz := local.z
			var nose_limit := (wall_z - 0.5) if check_wall else (wall_z - 1.8)
			var in_fuselage := dx < 2.1 and dz > pt.z - 16.5 and dz < nose_limit
			var in_wings := dx < 14.5 and dz < wall_z - 5.2 and dz > pt.z - 14.0
			assert_bool(in_fuselage).is_false()
			assert_bool(in_wings).is_false()


func test_multiple_idle_ramp_agents_stay_separated_across_patrol() -> void:
	_setup_world()
	var stands := _world.flights.gate_grounds()
	var ids: Array[int] = []
	for _i in 5:
		ids.append(_world.staff.hire(RAMP))
	_views.sync(true)
	_views.draw()

	var nodes: Array[Node3D] = []
	for id in ids:
		nodes.append(_views.node_for(id))
	var min_sep := INF
	for _i in 300:
		_world.step()
		_views.draw()
		for i in nodes.size():
			_assert_clear_of_stands(nodes[i].position, stands)
			for j in range(i + 1, nodes.size()):
				min_sep = minf(min_sep, nodes[i].position.distance_to(nodes[j].position))
	assert_float(min_sep).is_greater(1.0)


func test_patrol_stays_clear_of_fuselages_wings_and_terminal_across_multiple_stands() -> void:
	_setup_world()
	var base_stand := StandPlacement.starter_stand(_world.grid, SITE)
	var stands := {
		"C": {"stand": base_stand, "max_class": PlaneClasses.MEDIUM},
	}
	_add_second_stand(stands, "D", float(base_stand["x"]) + 44.0, float(base_stand["wall_z"]))
	_world.flights.gate_source = func() -> Array[String]: return ["C", "D"]
	_world.flights.stand_source = func() -> Dictionary: return stands

	var ramp_id := _world.staff.hire(RAMP)
	_views.sync(true)
	_views.draw()
	var node := _views.node_for(ramp_id)

	var visited_near_d := false
	for _i in 1800:
		_world.step()
		_views.draw()
		var pos := node.position
		_assert_clear_of_stands(pos, stands)
		if absf(pos.x - (float(base_stand["x"]) + 44.0)) < 14.0:
			visited_near_d = true
	assert_bool(visited_near_d).is_true()


func test_zero_stand_fallback_respects_airside_clearance_including_side_exits() -> void:
	var grid := BuildGrid.new(Vector2i(24, 20))
	var edits: Array[BuildEdit] = []
	for y in range(6, 14):
		for x in range(8, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	var exit_cell := Vector2i(8, 10)
	PassengerTestWorld.place(grid, &"exit_door", exit_cell, 3)
	_world = PassengerTestWorld.make(grid, _idle_starts(), 17)
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_world.flights.gate_source = func() -> Array[String]: return []
	var door_w := grid.cell_to_world(exit_cell)

	var loop := RampPatrol.build_loop(_world.flights, grid, _world.staff)
	var pts: Array = loop["points"]
	assert_int(pts.size()).is_greater_equal(1)
	for i in pts.size():
		var p: Vector3 = pts[i]["pos"]
		var nxt: Vector3 = pts[(i + 1) % pts.size()]["pos"]
		assert_bool(grid.is_indoor(grid.world_to_cell(p))).is_false()
		assert_float(p.x).is_less(door_w.x - 1.0)
		assert_bool(BaggageShuttle.segment_hits_wall(grid, p, nxt)).is_false()


func test_blocked_detour_between_stands_never_emits_straight_line_through_obstacle() -> void:
	_setup_world()
	var base_stand := StandPlacement.starter_stand(_world.grid, SITE)
	var stands := {
		"C": {"stand": base_stand, "max_class": PlaneClasses.MEDIUM},
	}
	_add_second_stand(stands, "D", float(base_stand["x"]) + 44.0, float(base_stand["wall_z"]))
	_world.flights.gate_source = func() -> Array[String]: return ["C", "D"]
	_world.flights.stand_source = func() -> Dictionary: return stands

	# Seal a walled enclosure around stand D's staging cell so no route exists to D.
	var d_pt := StandPlacement.stand_point(stands["D"]["stand"])
	var d_p0 := Vector3(d_pt.x - 3.8, 0.0, float(base_stand["wall_z"]) - 2.0)
	var box_c := _world.grid.world_to_cell(d_p0)
	var floor_edits: Array[BuildEdit] = []
	for y in range(box_c.y - 2, box_c.y + 3):
		for x in range(box_c.x - 2, box_c.x + 3):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in _world.grid.apply_batch(floor_edits):
		assert_bool(res.ok).is_true()
	EnclosureKit.close_floor(_world.grid)

	var c_pt := StandPlacement.stand_point(base_stand)
	var c_p0 := Vector3(c_pt.x - 3.8, 0.0, float(base_stand["wall_z"]) - 2.0)
	var ret := RampPatrol.plan_return_path(c_p0, d_p0, _world.flights, _world.grid)
	assert_bool(ret["ok"]).is_false()

	var loop := RampPatrol.build_loop(_world.flights, _world.grid, _world.staff)
	var pts: Array = loop["points"]
	assert_int(pts.size()).is_greater_equal(1)
	for i in pts.size():
		var a: Vector3 = pts[i]["pos"]
		var b: Vector3 = pts[(i + 1) % pts.size()]["pos"]
		assert_bool(_world.grid.is_indoor(_world.grid.world_to_cell(a))).is_false()
		assert_bool(BaggageShuttle.segment_hits_wall(_world.grid, a, b)).is_false()


func test_clock_rollback_and_snap_restore_deterministic_patrol_state() -> void:
	_setup_world()
	var ramp_id := _world.staff.hire(RAMP)
	_views.sync(true)
	_views.draw()
	var node := _views.node_for(ramp_id)

	for _i in 120:
		_world.step()
		_views.draw()
	var snap_tick := _world.clock.tick
	_views.sync(true)
	_views.draw()
	var snap_pos := node.position
	var snap_yaw := node.rotation.y
	var snap_clip := String(node.get_meta(&"clip", ""))

	for _i in 100:
		_world.step()
		_views.draw()

	# Roll clock back and snap-sync (6d949060).
	_world.clock.tick = snap_tick
	_views.sync(true)
	_views.draw()
	assert_vector(node.position).is_equal_approx(snap_pos, Vector3(0.01, 0.01, 0.01))
	assert_float(absf(angle_difference(node.rotation.y, snap_yaw))).is_less(0.01)
	assert_str(String(node.get_meta(&"clip", ""))).is_equal(snap_clip)
	assert_int(_views.hand_prop_of(ramp_id)).is_equal(StaffHandProps.PropKind.NONE)


func test_active_marshal_and_pushback_preserved_with_smooth_walk_back_to_patrol() -> void:
	var starts := PassengerTestWorld.starts_with(200, 300)
	var fid := _setup_world(starts)
	var ramp_id := _world.staff.hire(RAMP)
	_views.sync(true)
	var worker := _world.staff.get_member(ramp_id)
	var node := _views.node_for(ramp_id)

	var taxi_in := _world.flights.state_start(fid, FlightSim.State.TAXI_IN)
	_world.run_to(taxi_in + int(StaffStationPose.EASE_TICKS) + 2)
	_views.draw()
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	var stand := _world.flights.flight_stand(fid)
	var twin := StandPlacement.north_twin(stand)
	var pt := StandPlacement.stand_point(twin)
	var expected_marshal := (
		StandPlacement
		. to_world(
			stand,
			Vector3(
				pt.x - StaffCharacters.MARSHAL_SIDE_M,
				0.0,
				float(twin["wall_z"]) - StaffCharacters.MARSHAL_WALL_GAP_M,
			),
		)
	)
	(
		assert_float(
			Vector2(node.position.x, node.position.z).distance_to(
				Vector2(expected_marshal.x, expected_marshal.z)
			)
		)
		. is_less(0.05)
	)
	assert_int(_views.hand_prop_of(ramp_id)).is_equal(StaffHandProps.PropKind.MARSHAL_WANDS)

	# Release from MARSHAL -> smoothly walks clear of aircraft until rejoining patrol.
	var at_stand := _world.flights.state_start(fid, FlightSim.State.AT_STAND)
	_world.run_to(at_stand)
	_views.draw()
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_float(node.position.distance_to(expected_marshal)).is_less(0.5)
	assert_str(String(node.get_meta(&"clip", ""))).is_equal("walk")
	var stands := _world.flights.gate_grounds()
	var rejoined := false
	for _i in 120:
		_world.step()
		_views.draw()
		_assert_clear_of_stands(node.position, stands, false)
		if String(node.get_meta(&"clip", "")) == "idle":
			rejoined = true
			break
	assert_bool(rejoined).is_true()

	# Pushback job preserves exact tug pose + MARSHAL_WANDS during RAMP_GUIDE.
	var pushback := _world.flights.state_start(fid, FlightSim.State.PUSHBACK)
	_world.run_to(pushback + int(StaffStationPose.EASE_TICKS) + 2)
	_views.draw()
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_int(_views.hand_prop_of(ramp_id)).is_equal(StaffHandProps.PropKind.MARSHAL_WANDS)
	var model := PlaneClasses.flight_model(_world.flights, fid)
	var nose_z := pt.z + float(PlaneModels.PLANES.get(model, {}).get("nose", StandPlacement.NOSE_M))
	var expected_pushback := StandPlacement.to_world(
		stand, Vector3(pt.x, 0.0, nose_z) + StaffCharacters.PUSHBACK_TUG_OFFSET
	)
	(
		assert_float(
			Vector2(node.position.x, node.position.z).distance_to(
				Vector2(expected_pushback.x, expected_pushback.z)
			)
		)
		. is_less(0.05)
	)

	# OFF_SHIFT hides/releases the agent cleanly.
	worker.state = StaffMember.State.OFF_SHIFT
	_views.sync(false)
	_views.draw()
	assert_object(_views.node_for(ramp_id)).is_null()


func test_shuttle_pose_and_smooth_return_preserved() -> void:
	var bag_world := BagTestWorld.make(self, 600)
	PassengerTestWorld.place(bag_world.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var staff := auto_free(StaffSim.new()) as StaffSim
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	pax.clock = bag_world.clock
	pax.flights = bag_world.flights
	pax.grid = bag_world.grid
	pax.layout = TerminalLayout.new()
	pax.layout.rebuild(bag_world.grid)
	pax.staff = staff
	staff.sim = pax
	var finances := auto_free(Finances.new()) as Finances
	finances.clock = bag_world.clock
	finances.start_new_game()
	var dispatch := auto_free(RampDispatch.new()) as RampDispatch
	dispatch.bind(bag_world.clock, staff, bag_world.sim, bag_world.flights, finances, null)
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	chars.clock = bag_world.clock
	chars.staff = staff
	chars.baggage = bag_world.sim
	chars.flights = bag_world.flights
	add_child(chars)

	var ramp_id := staff.hire(RAMP)
	var bag := bag_world.sim.check_in(1, BagTestWorld.FLIGHT, bag_world.line())
	bag_world.run_to(bag.cutoff_tick)
	var shuttle := bag_world.sim.shuttles()[0]
	chars.sync(true)
	chars.draw()
	var node := chars.node_for(ramp_id)
	var expected_out := (
		shuttle.pose_at(bag_world.sim.tick, bag_world.grid) * StaffCharacters.SHUTTLE_OFFSET
	)
	(
		assert_float(
			Vector2(node.position.x, node.position.z).distance_to(
				Vector2(expected_out.x, expected_out.z)
			)
		)
		. is_less(0.05)
	)
	assert_str(String(node.get_meta(&"clip", ""))).is_equal("walk")

	bag_world.run_to(shuttle.arrive_tick)
	chars.draw()
	assert_str(String(node.get_meta(&"clip", ""))).is_equal("idle")

	bag_world.run_to(shuttle.return_tick)
	chars.draw()
	assert_int(staff.get_member(ramp_id).ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_bool(node.visible).is_true()
