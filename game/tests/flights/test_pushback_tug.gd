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


func test_the_tug_shows_only_during_pushback() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var plane: Node3D = (PlaneView.PLANE_SCENES["tp_plane_05a"] as PackedScene).instantiate()
	holder.add_child(plane)
	var props := PlaneProps.new()
	holder.add_child(props)
	var shown := 0
	for state in FlightSim.STATE_COUNT:
		props.follow(true, plane, "tp_plane_05a", state, "A", null, 0)
		shown += 1 if props.tug.visible else 0
		assert_bool(props.tug.visible).is_equal(state == FlightSim.State.PUSHBACK)
	props.follow(false, plane, "tp_plane_05a", FlightSim.State.PUSHBACK, "A", null, 0)
	assert_bool(props.tug.visible).is_false()
	assert_int(shown).is_equal(1)
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
