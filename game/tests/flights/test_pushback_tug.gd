class_name TestPushbackTug
extends GdUnitTestSuite
## The towbarless tug (board 4c08b8e5, Runway R11) rides each plane's nose wheel
## through the whole pushback and shows only then. The plane is posed by
## FlightPose.pose(PUSHBACK) on a real gate stand's path and its model placed
## by FlightPose.model_position(), as PlaneView draws it; the tug is placed by
## PlaneProps.follow(), the code PlaneView calls each frame.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
## How far Mount_NoseGear may sit from the nose wheel contact, in metres.
const GEAR_TOLERANCE_M := 0.01
const PROGRESS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
## The least gap between the tug's front and the wall line at pushback start.
const WALL_CLEAR_M := 0.3

var _airside: Airside


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": StandPlacement.make(1, 100.0, -230.0)})).is_true()


func after() -> void:
	_airside.free()


func test_every_model_has_a_nose_wheel_on_its_centreline_ahead_of_its_main_gear() -> void:
	var main_gear := RegEx.create_from_string("_Wheels?_R([._][LR])?$")
	for model: String in PlaneModels.PLANES:
		var plane: Node3D = (PlaneView.PLANE_SCENES[model] as PackedScene).instantiate()
		var box := PlaneProps.nose_gear_bounds(plane)
		var contact := PlaneProps.nose_gear_contact(plane, model)
		var main_z := -INF
		for mesh: MeshInstance3D in plane.find_children("*", "MeshInstance3D", true, false):
			if main_gear.search(String(mesh.name)) != null:
				main_z = maxf(main_z, (PlaneProps._to_model(mesh, plane) * mesh.get_aabb()).end.z)
		var nose: float = PlaneModels.PLANES[model]["nose"]
		print(
			(
				(
					"%s: nose wheel bounds %s, contact %s, main gear front z %.2f, nose %.2f m"
					+ " ahead of the contact"
				)
				% [model, box, contact, main_z, nose - contact.z]
			)
		)
		assert_vector(box.size).is_not_equal(Vector3.ZERO)
		assert_float(absf(contact.x)).is_less(0.05)
		assert_float(absf(contact.y)).is_less(0.05)
		# The main gear was found, so the comparison below is not against -INF.
		assert_bool(is_finite(main_z)).is_true()
		assert_float(contact.z).is_greater(main_z)
		plane.free()


func test_the_tug_holds_the_nose_wheel_through_the_pushback() -> void:
	var path := _airside.phase_path(FlightSim.State.PUSHBACK, "A")
	var entry := FlightPose.exit_dir(_airside.phase_path(FlightSim.State.TAXI_IN, "A"))
	for model: String in PlaneModels.PLANES:
		if PlaneClasses.self_taxis(model):
			continue
		var travelled := 0.0
		var start := Vector3.ZERO
		for t in PROGRESS:
			var pose := FlightPose.pose(FlightSim.State.PUSHBACK, t, path, entry)
			var plane := Kit.posed_model(self, model, pose, path[0], entry)
			var props := PlaneProps.new()
			plane.get_parent().add_child(props)
			props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", null, 0)
			var gear := plane.global_transform * PlaneProps.nose_gear_contact(plane, model)
			var mount := props.tug.find_child("Mount_NoseGear", true, false) as Node3D
			var off := mount.global_position.distance_to(gear)
			var ahead := plane.global_basis.z.slide(Vector3.UP).normalized()
			var facing := props.tug.global_basis.z.slide(Vector3.UP).normalized()
			if t == 0.0:
				start = mount.global_position
			travelled = start.distance_to(mount.global_position)
			print(
				(
					(
						"%s t %.2f: tug %.4f m off the nose wheel, facing dot %.4f, %.1f m from"
						+ " its start"
					)
					% [model, t, off, ahead.dot(facing), travelled]
				)
			)
			assert_bool(props.tug.visible).is_true()
			assert_float(off).is_less(GEAR_TOLERANCE_M)
			assert_float(ahead.dot(facing)).is_greater(0.9999)
			plane.get_parent().free()
		# It rode the pushback: the end is the leg's length from the start.
		assert_float(travelled).is_greater(StandPlacement.PUSHBACK_M - 2.0)


## At the start of pushback, with the plane still parked door-aligned on the
## stand, the tug's front stays at least WALL_CLEAR_M short of the stand's wall
## line (decision plane-04-stops-further-out-with-the-passenger-walk-ending-at;
## R11 measured model 04's tug front 1.19 m through it).
func test_the_tug_starts_its_pushback_clear_of_the_wall_line() -> void:
	var path := _airside.phase_path(FlightSim.State.PUSHBACK, "A")
	var entry := FlightPose.exit_dir(_airside.phase_path(FlightSim.State.TAXI_IN, "A"))
	var wall_z := float(_airside.gate_stands["A"]["wall_z"])
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
	for model: String in PlaneModels.PLANES:
		if PlaneClasses.self_taxis(model):
			continue
		var plane := Kit.posed_model(self, model, pose, path[0], entry)
		var props := PlaneProps.new()
		plane.get_parent().add_child(props)
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", null, 0)
		var box := _world_bounds(props.tug)
		var nose := plane.global_position.z + float(PlaneModels.PLANES[model]["nose"])
		print(
			(
				"%s pushback start: tug front z %.3f, nose z %.3f, wall z %.3f, tug clear by %.3f m"
				% [model, box.end.z, nose, wall_z, wall_z - box.end.z]
			)
		)
		# The tug was found and placed at the nose, so the gap is a real one.
		assert_vector(box.size).is_not_equal(Vector3.ZERO)
		assert_float(box.end.z).is_greater(plane.global_position.z)
		assert_float(wall_z - box.end.z).is_greater_equal(WALL_CLEAR_M)
		plane.get_parent().free()


func test_the_tug_shows_for_approach_pushback_and_early_pullaway_only() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var plane: Node3D = (PlaneView.PLANE_SCENES["tp_plane_05a"] as PackedScene).instantiate()
	holder.add_child(plane)
	var props := PlaneProps.new()
	holder.add_child(props)
	var active_states := [FlightSim.State.DOORS_CLOSED, FlightSim.State.PUSHBACK]
	for state in FlightSim.STATE_COUNT:
		props.follow(true, plane, "tp_plane_05a", state, "A", null, 0, 0.5)
		assert_bool(props.tug.visible).is_equal(active_states.has(state))
	props.follow(true, plane, "tp_plane_05a", FlightSim.State.TAXI_OUT, "A", null, 0, 0.02)
	assert_bool(props.tug.visible).is_true()
	props.follow(
		true, plane, "tp_plane_05a", FlightSim.State.TAXI_OUT, "A", null, 0, PlaneProps.PULLAWAY_END
	)
	assert_bool(props.tug.visible).is_false()
	props.follow(false, plane, "tp_plane_05a", FlightSim.State.PUSHBACK, "A", null, 0)
	assert_bool(props.tug.visible).is_false()
	holder.free()


func test_tug_approach_and_pullaway_are_continuous_and_clear_bridge_and_wall() -> void:
	var path := _airside.phase_path(FlightSim.State.PUSHBACK, "A")
	var entry := FlightPose.exit_dir(_airside.phase_path(FlightSim.State.TAXI_IN, "A"))
	var wall_z := float(_airside.gate_stands["A"]["wall_z"])
	var bridge := _airside.props.bridges["A"]["node"] as Node3D
	for model: String in ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]:
		# Approach: DOORS_CLOSED t 0..1 -> PUSHBACK t = 0
		var dock_pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
		var plane := Kit.posed_model(self, model, dock_pose, path[0], entry)
		var props := PlaneProps.new()
		plane.get_parent().add_child(props)
		var prev_pos := Vector3.ZERO
		for step in 11:
			var t := step / 10.0
			props.follow(true, plane, model, FlightSim.State.DOORS_CLOSED, "A", _airside, 1, t)
			assert_bool(props.tug.visible).is_true()
			var box := _world_bounds(props.tug)
			assert_float(wall_z - box.end.z).is_greater_equal(WALL_CLEAR_M)
			assert_int(Kit.crossings(props.tug, bridge)["count"]).is_equal(0)
			if step > 0:
				assert_float(prev_pos.distance_to(props.tug.global_position)).is_less(2.5)
			prev_pos = props.tug.global_position
		var end_approach := props.tug.global_transform
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1, 0.0)
		assert_float(end_approach.origin.distance_to(props.tug.global_position)).is_less(0.001)
		assert_float(end_approach.basis.z.dot(props.tug.global_basis.z)).is_greater(0.9999)
		plane.get_parent().free()

		# Pull-away: PUSHBACK t = 1 -> TAXI_OUT t in [0, PULLAWAY_END)
		var uncouple_pose := FlightPose.pose(FlightSim.State.PUSHBACK, 1.0, path, entry)
		plane = Kit.posed_model(self, model, uncouple_pose, path[0], entry)
		props = PlaneProps.new()
		plane.get_parent().add_child(props)
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1, 1.0)
		var end_push := props.tug.global_transform
		prev_pos = end_push.origin
		for step in 10:
			var t := PlaneProps.PULLAWAY_END * (step / 10.0)
			props.follow(
				true,
				plane,
				model,
				FlightSim.State.TAXI_OUT,
				"A",
				_airside,
				1,
				t,
				plane.global_transform
			)
			assert_bool(props.tug.visible).is_true()
			var pull_box := _world_bounds(props.tug)
			assert_float(wall_z - pull_box.end.z).is_greater_equal(WALL_CLEAR_M)
			assert_int(Kit.crossings(props.tug, bridge)["count"]).is_equal(0)
			if step == 0:
				assert_float(end_push.origin.distance_to(props.tug.global_position)).is_less(0.001)
				assert_float(end_push.basis.z.dot(props.tug.global_basis.z)).is_greater(0.9999)
			else:
				assert_float(prev_pos.distance_to(props.tug.global_position)).is_less(2.5)
			prev_pos = props.tug.global_position
		assert_float(end_push.origin.distance_to(prev_pos)).is_greater(8.0)
		props.follow(
			true,
			plane,
			model,
			FlightSim.State.TAXI_OUT,
			"A",
			_airside,
			1,
			PlaneProps.PULLAWAY_END,
			plane.global_transform
		)
		assert_bool(props.tug.visible).is_false()
		plane.get_parent().free()


func test_plane_view_uncouple_and_reload_continuity_across_tugged_models() -> void:
	var wall_z := float(_airside.gate_stands["A"]["wall_z"])
	var bridge := _airside.props.bridges["A"]["node"] as Node3D
	var specs := [
		["Gotta Air", PlaneClasses.MEDIUM, "tp_plane_04a"],
		["SkyHop", PlaneClasses.MEDIUM, "tp_plane_05a"],
		["Polar Jet", PlaneClasses.LARGE, "tp_plane_06a"],
		["SkyHop", PlaneClasses.LARGE, "tp_plane_07a"],
	]
	for spec: Array in specs:
		var sim := FlightSim.new()
		sim.gate_source = func() -> Array[String]: return ["A"]
		sim.open_airport()
		var booked := 30 if spec[1] == PlaneClasses.MEDIUM else 60
		var terms := {
			"id": "CTUG",
			"airline": spec[0],
			"destination": "Oslo",
			"departure_minute": 9 * 60,
			"plane_size": spec[1],
			"booked_passengers": booked,
			"fee_per_passenger": 20,
		}
		assert_bool(sim.accept_contract(terms)).is_true()
		var fid := ""
		for id in sim.flight_ids():
			if sim.flight_contract_id(id) == "CTUG":
				fid = id
				break
		assert_str(fid).is_not_empty()
		var push_end := sim.state_start(fid, FlightSim.State.TAXI_OUT)
		var taxi_end := sim.state_start(fid, FlightSim.State.TAKEOFF)

		var view_a := _make_plane_view(sim)
		assert_str(view_a.model_of(fid)).is_equal(spec[2])
		sim.tick = push_end
		view_a.clock._accumulator = 0.9999 * SimClock.STEP
		view_a.update_pose()
		assert_int(view_a.phase).is_equal(FlightSim.State.PUSHBACK)
		var props_a := view_a.get_node("Props") as PlaneProps
		var model_a := view_a.get_node("Pivot").get_child(0) as Node3D
		assert_bool(props_a.tug.is_visible_in_tree()).is_true()
		var end_push_model := model_a.global_transform
		var end_push_tug := props_a.tug.global_transform
		view_a.free()

		# Freshly constructed (reloaded) PlaneView enters TAXI_OUT cleanly from uncouple pose.
		var view_b := _make_plane_view(sim)
		sim.tick = push_end + 1
		view_b.clock._accumulator = 0.0
		view_b.update_pose()
		assert_int(view_b.phase).is_equal(FlightSim.State.TAXI_OUT)
		var uncouple_xform := view_b._uncouple_model_xform()
		assert_float(uncouple_xform.origin.distance_to(end_push_model.origin)).is_less(0.005)
		assert_float(uncouple_xform.basis.z.dot(end_push_model.basis.z)).is_greater(0.9999)
		var props_b := view_b.get_node("Props") as PlaneProps
		assert_bool(props_b.tug.is_visible_in_tree()).is_true()
		assert_float(props_b.tug.global_position.distance_to(end_push_tug.origin)).is_less(0.005)
		assert_float(props_b.tug.global_basis.z.dot(end_push_tug.basis.z)).is_greater(0.9999)
		var pull_box := _world_bounds(props_b.tug)
		assert_float(wall_z - pull_box.end.z).is_greater_equal(WALL_CLEAR_M)
		assert_int(Kit.crossings(props_b.tug, bridge)["count"]).is_equal(0)

		# Step into pull-away and past PULLAWAY_END.
		var mid_pull := push_end + int(ceilf((taxi_end - push_end) * PlaneProps.PULLAWAY_END * 0.5))
		sim.tick = mid_pull + 1
		view_b.clock.alpha = 0.0
		view_b.update_pose()
		assert_bool(props_b.tug.is_visible_in_tree()).is_true()
		pull_box = _world_bounds(props_b.tug)
		assert_float(wall_z - pull_box.end.z).is_greater_equal(WALL_CLEAR_M)
		assert_int(Kit.crossings(props_b.tug, bridge)["count"]).is_equal(0)

		var past_pull := push_end + int(ceilf((taxi_end - push_end) * PlaneProps.PULLAWAY_END)) + 1
		sim.tick = past_pull + 1
		view_b.clock.alpha = 0.0
		view_b.update_pose()
		assert_bool(props_b.tug.is_visible_in_tree()).is_false()
		view_b.free()
		sim.free()


func _make_plane_view(sim: FlightSim) -> PlaneView:
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	view.gate = "A"
	add_child(view)
	view.set_process(false)
	return view


func test_a_self_taxiing_plane_never_shows_the_tug() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var plane: Node3D = (PlaneView.PLANE_SCENES["tp_plane_03a"] as PackedScene).instantiate()
	holder.add_child(plane)
	var props := PlaneProps.new()
	holder.add_child(props)
	for state in FlightSim.STATE_COUNT:
		for progress in [0.0, 0.02, 0.5, 1.0]:
			props.follow(true, plane, "tp_plane_03a", state, "A", null, 0, progress)
			assert_bool(props.tug.visible).is_false()
	holder.free()


## The merged world bounds of every mesh under `node`.
func _world_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part := mesh.global_transform * mesh.get_aabb()
		box = part if not found else box.merge(part)
		found = true
	return box
