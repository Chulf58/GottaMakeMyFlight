class_name TestStandTurnEnvelope
extends GdUnitTestSuite
## The drawn plane stays inside the StandEnvelope swing square of its class
## through its whole stand turn (board 13e98b04): the last leg of the taxi in,
## the parked pose, the pushback and its swing, and the start of the taxi out.
## Each model is drawn under FlightPose.pose() at FlightPose.model_position(),
## as PlaneView draws it.

const MAIN_SCENE := "res://main/main.tscn"
## Poses sampled per phase.
const STEPS := 1000
## How far north of the pushback's end the taxi out is followed.
const TAXI_OUT_M := 70.0

var _stand := StandPlacement.make(1, 100.0, 40.0)
var _airside: Airside


## Builds the real Airside markers from main.tscn's saved state, without
## instantiating the scene, for the PlaneView checks.
func before() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	_airside = Airside.new()
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			_airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			_airside.links = props[&"links"]
	add_child(_airside)


func after() -> void:
	_airside.free()


func test_every_model_stays_inside_its_swing_square_through_the_stand_turn() -> void:
	var at := StandPlacement.stand_point(_stand)
	var wall_z := float(_stand["wall_z"])
	for plane_class in PlaneClasses.ORDER:
		var parts := StandEnvelope.rects(_stand, plane_class)
		var swing: Rect2 = parts[0]
		var half := StandEnvelope.radius(plane_class)
		var span := StandEnvelope.half_span(plane_class)
		for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
			var row: Dictionary = PlaneModels.PLANES[model]
			var parked_nose: float = at.z + PlaneClasses.stand_offset(model).z + row["nose"]
			var now := _reach(model, false)
			var before_fix := _reach(model, true)
			print(
				(
					(
						"%s %s: corner reach x %.2f (was %.2f) of half-size %.2f, north of the"
						+ " pushback end %.2f (was %.2f) of %.2f, way x %.2f of %.2f, south z"
						+ " %.2f (parked nose %.2f, square edge %.2f, wall %.2f)"
					)
					% [
						plane_class,
						model,
						now["x"],
						before_fix["x"],
						half,
						now["north"],
						before_fix["north"],
						half,
						now["way_x"],
						span,
						now["south"],
						parked_nose,
						swing.end.y,
						wall_z,
					]
				)
			)
			assert_float(now["x"]).is_less(half)
			assert_float(now["north"]).is_less(half)
			assert_float(now["way_x"]).is_less_equal(span)
			# The turn never reaches further south than the parked plane, which
			# R5 lets pass the square's edge but never the wall line.
			assert_float(now["south"]).is_less_equal(maxf(swing.end.y, parked_nose) + 0.001)
			assert_float(now["south"]).is_less(wall_z)
	# Control: the measure finds the overreach the board item reported with
	# the old pivot (the door-aligned model turned about the stand point).
	var small_was := _reach("tp_plane_03a", true)
	var large_was := _reach("tp_plane_07a", true)
	print("before the fix: 03 reach %.2f, 07 reach %.2f" % [small_was["x"], large_was["x"]])
	assert_float(small_was["x"]).is_greater(15.0)
	assert_float(large_was["x"]).is_greater(38.0)


func test_a_parked_model_keeps_its_door_at_the_stand_door() -> void:
	var at := StandPlacement.stand_point(_stand)
	var door_z := StandPlacement.door_point(_stand).z
	var parked := FlightPose.pose(FlightSim.State.TAXI_IN, 1.0, _taxi_in(), Vector3.BACK)
	for model: String in PlaneModels.PLANES:
		var placed := FlightPose.model_position(model, parked, at, Vector3.BACK)
		var door: Vector3 = parked * (placed + PlaneModels.PLANES[model]["doors"][0])
		print("%s parked at %s, door z %.3f (stand door %.3f)" % [model, placed, door.z, door_z])
		assert_vector(placed).is_equal_approx(PlaneClasses.stand_offset(model), Vector3.ONE * 1e-4)
		# The pushback starts where the taxi in ended.
		var pushed := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, _pushback(), Vector3.BACK)
		var start := FlightPose.model_position(model, pushed, at, Vector3.BACK)
		assert_vector(start).is_equal_approx(placed, Vector3.ONE * 1e-4)


func test_off_the_stand_leg_every_model_is_centred_in_its_own_frame() -> void:
	var at := StandPlacement.stand_point(_stand)
	var back := StandPlacement.pushback_end(_stand)
	var ended := FlightPose.pose(FlightSim.State.PUSHBACK, 1.0, _pushback(), Vector3.BACK)
	var away := Transform3D(Basis(Vector3.UP, 1.1), back + Vector3(30.0, 0.0, -40.0))
	for model: String in PlaneModels.PLANES:
		var centred: Vector3 = PlaneModels.PLANES[model]["model_offset"]
		for pose in [ended, away]:
			var placed := FlightPose.model_position(model, pose, at, Vector3.BACK)
			assert_vector(placed).is_equal_approx(centred, Vector3.ONE * 1e-4)


## A stand facing another way shifts its door in that frame: parked facing -x,
## the model still has its door where stand_offset puts it in its own frame.
func test_the_door_shift_follows_the_stand_heading() -> void:
	var at := Vector3(10.0, 0.0, 5.0)
	var facing := Vector3.LEFT
	var parked := Transform3D(Basis(Vector3.UP, MovementPlan.yaw_of(facing)), at)
	for model: String in PlaneModels.PLANES:
		var placed := FlightPose.model_position(model, parked, at, facing)
		assert_vector(placed).is_equal_approx(PlaneClasses.stand_offset(model), Vector3.ONE * 1e-4)


## The sideways part of the door shift is gone where the pushback swing begins.
func test_the_sideways_shift_is_gone_before_the_swing_starts() -> void:
	var share := MovementPlan.fraction(FlightPose.PUSHBACK_SWING_START)
	print(
		(
			"DOOR_ACROSS_SHARE %.4f, fraction at the swing start %.4f"
			% [FlightPose.DOOR_ACROSS_SHARE, share]
		)
	)
	assert_float(FlightPose.DOOR_ACROSS_SHARE).is_equal_approx(share, 0.001)


## The drawn plane's middle moves one way through each leg: away from the wall
## on the pushback, toward it on the taxi in, never back.
func test_the_drawn_plane_never_moves_backwards_along_the_stand_leg() -> void:
	var at := StandPlacement.stand_point(_stand)
	for model: String in PlaneModels.PLANES:
		var centre: Vector3 = -(PlaneModels.PLANES[model]["model_offset"] as Vector3)
		var legs := [
			[FlightSim.State.TAXI_IN, _taxi_in(), 1.0],
			[FlightSim.State.PUSHBACK, _pushback(), -1.0],
		]
		for leg: Array in legs:
			var last := -INF
			var slowest := INF
			for i in range(STEPS + 1):
				var pose := FlightPose.pose(leg[0], float(i) / STEPS, leg[1], Vector3.BACK)
				var placed := FlightPose.model_position(model, pose, at, Vector3.BACK)
				var middle: float = (pose * (placed + centre)).z * leg[2]
				if i > 0:
					slowest = minf(slowest, middle - last)
				last = middle
			print("%s state %d: smallest step %.5f m" % [model, leg[0], slowest])
			assert_float(slowest).is_greater_equal(-1e-5)


func test_plane_view_parks_door_aligned_and_flies_centred() -> void:
	var view := PlaneView.new()
	view.sim = auto_free(FlightSim.new()) as FlightSim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	add_child(view)
	view.set_process(false)
	auto_free(view)
	var path := _airside.phase_path(FlightSim.State.PUSHBACK, "", PlaneClasses.LARGE)
	var parked := Transform3D(Basis(), path[0])
	for model in ["tp_plane_03a", "tp_plane_07a"]:
		view.show_model(model)
		var centred: Vector3 = PlaneModels.PLANES[model]["model_offset"]
		var at_stand := view.model_position_at(FlightSim.State.BOARDING, parked, PlaneClasses.LARGE)
		var in_sky := view.model_position_at(PlaneView.PHASE_LEAD_IN, parked, PlaneClasses.LARGE)
		print("%s: at the stand %s, in the sky %s" % [model, at_stand, in_sky])
		assert_vector(at_stand).is_equal_approx(
			PlaneClasses.stand_offset(model), Vector3.ONE * 1e-4
		)
		assert_vector(in_sky).is_equal_approx(centred, Vector3.ONE * 1e-4)


## Largest corner reaches of `model` through the stand turn: "x" across from
## the stand point while inside the swing square's length, "north" past the
## pushback's end, "way_x" across once north of the square, "south" the
## southmost z. `old` draws it the way it was before board 13e98b04: door-
## aligned at every pose.
func _reach(model: String, old: bool) -> Dictionary:
	var at := StandPlacement.stand_point(_stand)
	var back := StandPlacement.pushback_end(_stand)
	var plane_class := ""
	for each in PlaneClasses.ORDER:
		if PlaneClasses.CLASSES[each]["models"].has(model):
			plane_class = each
	var square_north := back.z - StandEnvelope.radius(plane_class)
	var box: AABB = PlaneModels.PLANES[model]["aabb"]
	var corners: Array[Vector3] = []
	for i in 4:
		corners.append(
			Vector3(
				box.end.x if i & 1 else box.position.x, 0.0, box.end.z if i & 2 else box.position.z
			)
		)
	var out := {"x": 0.0, "north": -INF, "way_x": 0.0, "south": -INF}
	var legs := [
		[FlightSim.State.TAXI_IN, _taxi_in(), Vector3.BACK],
		[FlightSim.State.PUSHBACK, _pushback(), Vector3.BACK],
		[FlightSim.State.TAXI_OUT, _taxi_out(), Vector3.FORWARD],
	]
	for leg: Array in legs:
		for i in range(STEPS + 1):
			var pose := FlightPose.pose(leg[0], float(i) / STEPS, leg[1], leg[2])
			var placed := PlaneClasses.stand_offset(model)
			if not old:
				placed = FlightPose.model_position(model, pose, at, Vector3.BACK)
			for corner in corners:
				var world := pose * (placed + corner)
				var across := absf(world.x - at.x)
				if world.z >= square_north:
					out["x"] = maxf(out["x"], across)
				else:
					out["way_x"] = maxf(out["way_x"], across)
				if leg[0] != FlightSim.State.TAXI_OUT:
					out["north"] = maxf(out["north"], back.z - world.z)
				out["south"] = maxf(out["south"], world.z)
	return out


## The taxi in's last leg, from the pushback's end to the stand, nose first.
func _taxi_in() -> PackedVector3Array:
	return PackedVector3Array(
		[StandPlacement.pushback_end(_stand), StandPlacement.stand_point(_stand)]
	)


func _pushback() -> PackedVector3Array:
	return PackedVector3Array(
		[StandPlacement.stand_point(_stand), StandPlacement.pushback_end(_stand)]
	)


## The taxi out's first TAXI_OUT_M north of the pushback's end.
func _taxi_out() -> PackedVector3Array:
	var back := StandPlacement.pushback_end(_stand)
	return PackedVector3Array([back, back + Vector3(0.0, 0.0, -TAXI_OUT_M)])
