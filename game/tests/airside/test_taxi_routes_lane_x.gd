class_name TestTaxiRoutesLaneX
extends GdUnitTestSuite
## TaxiRoutes with a side stand's own lane_x (decision side-spur-move-design-
## s7-stands-carry-lane-x-the-wanted-spur, slice S7a). The runway stubs stay at
## x -124 / +124; a spur farther out is reached along the lane at z -284 from
## the stub to the spur head at lane_x. At lane_x -124 / +124 the head is the
## stub and is dropped, so every route is the one main ea5e855f built: this
## file builds those with main's own code (_main_paths(), _main_ends()) and
## pins them point for point.

const WIDE := 174.0
## Stands of each side, sills at x 0 (and -20) so each is inside its spur.
const SILLS := [
	["N", Vector2(40.0, -149.5)],
	["N", Vector2(-80.0, -98.0)],
	["W", Vector2(0.0, -149.5)],
	["W", Vector2(-20.0, -109.5)],
	["E", Vector2(0.0, -129.5)],
	["E", Vector2(60.0, -150.0)],
]

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


static func _p() -> Dictionary:
	return FlightGround.points()


static func _stands(lane := NAN) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Array in SILLS:
		var side: String = entry[0]
		var sill: Vector2 = entry[1]
		var lane_x := NAN
		if side != StandPlacement.NORTH and not is_nan(lane):
			lane_x = -lane if side == StandPlacement.WEST else lane
		out.append(StandPlacement.make(0, sill.x, sill.y, side, lane_x))
	return out


## Main's StandPlacement route points for `stand`: a side stand's frame turned
## from a north twin whose sill is as far from the lane as the stand's is from
## x -124 / +124.
static func _main_ends(stand: Dictionary) -> Dictionary:
	var side := StandPlacement.side_of(stand)
	var twin := stand
	if side == StandPlacement.WEST:
		var z := StandPlacement.TAXI_LANE_Z + float(stand["x"]) + StandPlacement.SIDE_LANE_X
		twin = StandPlacement.make(int(stand["exit"]), 0.0, z)
	elif side == StandPlacement.EAST:
		var z := StandPlacement.TAXI_LANE_Z + StandPlacement.SIDE_LANE_X - float(stand["x"])
		twin = StandPlacement.make(int(stand["exit"]), 0.0, z)
	var spot := StandPlacement.stand_point(twin)
	var ends := {
		"spot": spot,
		"back": spot + Vector3(0.0, 0.0, -StandPlacement.PUSHBACK_M),
		"join": Vector3(spot.x, 0.0, StandPlacement.TAXI_LANE_Z),
	}
	if side == StandPlacement.NORTH:
		return ends
	for key: String in ends:
		var point: Vector3 = ends[key]
		var from := Vector3(float(twin["x"]), point.y, float(twin["wall_z"]))
		var sill := Vector3(float(stand["x"]), point.y, float(stand["wall_z"]))
		ends[key] = sill + StandPlacement.turn(stand, point - from)
	return ends


## Main's TaxiRoutes.phase_paths(): the side from the join's x, the lane's
## ends from the layout.
static func _main_paths(
	points: Dictionary, ends: Dictionary, plane_class: String, layout: Dictionary
) -> Dictionary:
	var at := func(base: StringName) -> Vector3:
		return points[Airside.class_point(base, plane_class)]
	var exit: Vector3 = points[&"RunwayExit"]
	var entry: Vector3 = points[&"RunwayEntry"]
	var east: Vector3 = points[&"TaxiEast"]
	var west: Vector3 = points[&"TaxiWest"]
	east.x = layout["east_x"]
	west.x = layout["west_x"]
	var spot: Vector3 = ends["spot"]
	var back: Vector3 = ends["back"]
	var join: Vector3 = ends["join"]
	var taxi_in := PackedVector3Array([exit, east, join, back, spot])
	var taxi_out := PackedVector3Array([back, join, west, entry])
	match TaxiRoutes.spur_of(join, layout):
		StandPlacement.WEST:
			taxi_in = PackedVector3Array([exit, east, west, join, back, spot])
		StandPlacement.EAST:
			taxi_out = PackedVector3Array([back, join, east, west, entry])
	return {
		FlightSim.State.APPROACH:
		PackedVector3Array([at.call(&"ApproachStart"), at.call(&"Touchdown")]),
		FlightSim.State.LANDING: PackedVector3Array([at.call(&"Touchdown"), exit]),
		FlightSim.State.TAXI_IN: taxi_in,
		FlightSim.State.PUSHBACK: PackedVector3Array([spot, back]),
		FlightSim.State.TAXI_OUT: taxi_out,
		FlightSim.State.TAKEOFF:
		PackedVector3Array([entry, at.call(&"Liftoff"), points[&"ClimbEnd"]]),
	}


## At lane_x -124 / +124 every phase path of every class at north, west and
## east stands is main's, point for point: as FlightGround plans it, and as
## Airside draws it.
func test_routes_at_the_floor_are_mains_point_for_point() -> void:
	var p := _p()
	var stands := _stands()
	var gates := {}
	for i in stands.size():
		gates[FlightGround.LETTERS[i]] = stands[i]
	assert_bool(_airside.set_gate_stands(gates)).is_true()
	var compared := 0
	for gate: String in gates:
		var stand: Dictionary = gates[gate]
		var ends := _main_ends(stand)
		for key: String in ends:
			assert_vector(TaxiRoutes.stand_ends(stand)[key]).is_equal(ends[key])
		for plane_class in PlaneClasses.ORDER:
			var want := _main_paths(p, ends, plane_class, TaxiRoutes.north_only(p))
			var planned := FlightGround.routes(stand, plane_class)
			for state: int in TaxiRoutes.MOVING_STATES:
				var why := "gate %s %s %s state %d" % [gate, stand, plane_class, state]
				var main := Array(want[state])
				assert_int(main.size()).override_failure_message(why).is_greater(1)
				assert_array(Array(planned[state])).override_failure_message(why).is_equal(main)
				var drawn := Array(_airside.phase_path(state, gate, plane_class))
				assert_array(drawn).override_failure_message(why).is_equal(main)
				compared += 1
	print("compared %d phase paths with main's" % compared)
	assert_int(compared).is_equal(6 * 3 * 6)


## With the spurs at x -174 / +174 the lane runs on from each stub to the spur
## head: a west stand taxis in along the whole lane, on west past the stub to
## the head and south down the spur, and out north up the spur, east along the
## lane to the stub and down it; an east stand taxis in up the east stub, east
## to the head and down the spur, and out up the spur and west along the whole
## lane. Every leg runs along x or z, and the head is on the lane.
func test_routes_to_a_wider_spur_run_the_lane_on_to_its_head() -> void:
	var p := _p()
	var layout := TaxiRoutes.north_only(p)
	var west: Vector3 = p[&"TaxiWest"]
	var east: Vector3 = p[&"TaxiEast"]
	for stand in _stands(WIDE):
		var side := StandPlacement.side_of(stand)
		if side == StandPlacement.NORTH:
			continue
		var ends := TaxiRoutes.stand_ends(stand)
		var head := Vector3(StandPlacement.lane_x_of(stand), west.y, west.z)
		var paths := TaxiRoutes.phase_paths(p, ends, PlaneClasses.MEDIUM, layout)
		var want_in := [p[&"RunwayExit"], east, head, ends["join"], ends["back"], ends["spot"]]
		var want_out := [ends["back"], ends["join"], head, east, west, p[&"RunwayEntry"]]
		if side == StandPlacement.WEST:
			want_in.insert(2, west)
			want_out.remove_at(3)
		var taxi_in: PackedVector3Array = paths[FlightSim.State.TAXI_IN]
		var taxi_out: PackedVector3Array = paths[FlightSim.State.TAXI_OUT]
		print("%s %s in %s out %s" % [side, stand, taxi_in, taxi_out])
		assert_float(ends["join"].x).is_equal_approx(head.x, 0.0001)
		assert_array(Array(taxi_in)).is_equal(want_in)
		assert_array(Array(taxi_out)).is_equal(want_out)
		for path in [taxi_in, taxi_out]:
			assert_bool(GroundPlanner.axis_aligned(path)).is_true()
		# The way out to the spur grows by the spur's move both ways.
		var at_floor := StandPlacement.make(0, float(stand["x"]), float(stand["wall_z"]), side)
		var near := TaxiRoutes.phase_paths(
			p, TaxiRoutes.stand_ends(at_floor), PlaneClasses.MEDIUM, layout
		)
		var gain := 2.0 * (WIDE - StandPlacement.SIDE_LANE_X)
		for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
			var longer := (
				MovementPlan.path_length(paths[state]) - MovementPlan.path_length(near[state])
			)
			assert_float(longer).is_equal_approx(gain, 0.001)


## The airside's lane layout reaches the gates' spurs, so it takes stands on a
## spur at x -174 / +174 and draws the routes FlightGround plans; a stand on a
## spur other than the one its side's gates use is refused loudly, and so is a
## north join beyond the lane.
func test_the_airside_lane_reaches_the_gates_spurs() -> void:
	var stands := _stands(WIDE)
	var gates := {}
	for i in stands.size():
		gates[FlightGround.LETTERS[i]] = stands[i]
	assert_bool(_airside.set_gate_stands(gates)).is_true()
	var layout := _airside.lane_layout()
	print("layout %s" % layout)
	assert_float(float(layout["west_x"])).is_equal(-WIDE)
	assert_float(float(layout["east_x"])).is_equal(WIDE)
	for gate: String in gates:
		for plane_class in PlaneClasses.ORDER:
			var planned := FlightGround.routes(gates[gate], plane_class)
			for state: int in planned:
				var why := "gate %s %s state %d" % [gate, plane_class, state]
				(
					assert_array(Array(_airside.phase_path(state, gate, plane_class)))
					. override_failure_message(why)
					. is_equal(Array(planned[state]))
				)
	# Two west spurs at once: the one at -124 is off the lane the gates reach.
	var mixed := gates.duplicate()
	mixed["Z"] = StandPlacement.make(0, -60.0, -150.0, StandPlacement.WEST)
	assert_bool(_airside.set_gate_stands(mixed)).is_false()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_IN, "Z").size()).is_equal(0)
	var beyond := {"A": stands[2], "B": StandPlacement.make(0, -190.0, -150.0)}
	assert_bool(_airside.set_gate_stands(beyond)).is_false()
	# Control: the wide west stand alone is taken.
	assert_bool(_airside.set_gate_stands({"A": stands[2]})).is_true()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_IN, "A").size()).is_equal(7)


## The paving follows the routes: the lane strip runs on to the spur heads at
## x -174 / +174 and each spur is a north-south strip there; the runway stubs
## at x -124 / +124 stay paved from the runway to the lane.
func test_the_paving_reaches_the_spur_heads() -> void:
	var stands := _stands(WIDE)
	var gates := {"A": stands[2], "B": stands[4]}
	var classes := {"A": PlaneClasses.LARGE, "B": PlaneClasses.LARGE}
	_airside.set_gate_classes(classes)
	assert_bool(_airside.set_gate_stands(gates)).is_true()
	var half := TaxiPaving.WIDTH_M / 2.0
	var lane := Rect2()
	var spurs := {}
	var stubs := {}
	for strip in _airside.paving.shown:
		var rect: Rect2 = strip["rect"]
		if strip.has("quad"):
			continue
		var x := rect.get_center().x
		if not strip["across_x"] and absf(rect.get_center().y - StandPlacement.TAXI_LANE_Z) < 0.01:
			lane = rect
		if strip["across_x"] and absf(absf(x) - WIDE) < 0.01:
			spurs[signf(x)] = rect
		if strip["across_x"] and absf(absf(x) - StandPlacement.SIDE_LANE_X) < 0.01:
			stubs[signf(x)] = rect
	print("lane %s, spurs %s, stubs %s" % [lane, spurs, stubs])
	assert_float(lane.position.x).is_less_equal(-WIDE + half + 0.01)
	assert_float(lane.end.x).is_greater_equal(WIDE - half - 0.01)
	assert_int(spurs.size()).is_equal(2)
	assert_int(stubs.size()).is_equal(2)
	for rect: Rect2 in stubs.values():
		assert_float(rect.position.y).is_less_equal(StandPlacement.RUNWAY_Z)
		assert_float(rect.end.y).is_greater_equal(StandPlacement.TAXI_LANE_Z - half - 0.01)
	for sign: float in spurs:
		var join := StandPlacement.lane_join(stands[2] if sign < 0.0 else stands[4])
		var rect: Rect2 = spurs[sign]
		assert_float(rect.position.y).is_less_equal(StandPlacement.TAXI_LANE_Z)
		assert_float(rect.end.y).is_greater_equal(join.z)
