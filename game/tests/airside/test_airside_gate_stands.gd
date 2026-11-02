class_name TestAirsideGateStands
extends GdUnitTestSuite
## One stand per gate on main.tscn's airside (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 3): Airside.set_gate_stands()
## gives each gate its own stand waypoints, joined to the one taxi lane as a
## chain in order of x, so a plane taxis along the lane past the other gates'
## joins; PlaneView draws a gate's flights on that gate's stand; PlaneFleet
## gives every gate with a live flight two views.

const MAIN_SCENE := "res://main/main.tscn"
const FIRST := 3000
## Two stands 44 m apart on the starter row (wall z -98), as the starter
## exit and an exit 44 cells east of it give.
const STAND_A := {"exit": 2, "x": -22.5, "wall_z": -98.0}
const STAND_B := {"exit": 4, "x": 21.5, "wall_z": -98.0}

var _airside: Airside


## Builds the real Airside markers from main.tscn's saved state, without
## instantiating the scene, as test_airside_stand.gd does.
func before() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	_airside = Airside.new()
	for i in state.get_node_count():
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if String(state.get_node_path(i, true)) == "./Airside":
			if state.get_node_type(i) == &"Marker3D":
				var marker := Marker3D.new()
				marker.name = state.get_node_name(i)
				marker.transform = props.get(&"transform", Transform3D.IDENTITY)
				_airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			_airside.links = props[&"links"]
	add_child(_airside)


func after() -> void:
	_airside.free()


func before_test() -> void:
	assert_bool(_airside.set_gate_stands({"A": STAND_A, "B": STAND_B})).is_true()


func after_test() -> void:
	_airside.set_gate_stands({})


func _at(waypoint: StringName) -> Vector3:
	return _airside.graph.position_of(waypoint)


func _lane(stand: Dictionary) -> Vector3:
	return StandPlacement.lane_join(stand)


func test_each_gate_taxis_along_the_lane_past_the_other_gates_join() -> void:
	var a := StandPlacement.stand_point(STAND_A)
	var b := StandPlacement.stand_point(STAND_B)
	var in_a := _airside.phase_path(FlightSim.State.TAXI_IN, "A")
	var in_b := _airside.phase_path(FlightSim.State.TAXI_IN, "B")
	var out_b := _airside.phase_path(FlightSim.State.TAXI_OUT, "B")
	var push_b := _airside.phase_path(FlightSim.State.PUSHBACK, "B")
	print("taxi in A %s\ntaxi in B %s\ntaxi out B %s" % [in_a, in_b, out_b])
	# B (x 18) is east of A (x -26): A's way in passes B's join on the lane.
	assert_array(Array(in_a)).is_equal(
		[
			_at(&"RunwayExit"),
			_at(&"TaxiEast"),
			_lane(STAND_B),
			_lane(STAND_A),
			StandPlacement.pushback_end(STAND_A),
			a
		]
	)
	assert_array(Array(in_b)).is_equal(
		[
			_at(&"RunwayExit"),
			_at(&"TaxiEast"),
			_lane(STAND_B),
			StandPlacement.pushback_end(STAND_B),
			b
		]
	)
	assert_array(Array(push_b)).is_equal([b, StandPlacement.pushback_end(STAND_B)])
	# The way out from B passes A's join on its way west; the scene's own
	# StandLane, on A's x, is off the chain while gates have stands.
	assert_array(Array(out_b).slice(0, 3)).is_equal(
		[StandPlacement.pushback_end(STAND_B), _lane(STAND_B), _lane(STAND_A)]
	)
	assert_vector(out_b[out_b.size() - 1]).is_equal(_at(&"RunwayEntry"))
	for point in out_b.slice(1, out_b.size() - 1):
		assert_float(point.z).is_equal(StandPlacement.TAXI_LANE_Z)


func test_a_gate_dropped_loses_its_waypoints_and_an_unknown_gate_uses_the_one_stand() -> void:
	var moves := _airside.stand_moves
	assert_bool(_airside.set_gate_stands({"B": STAND_B})).is_true()
	print("waypoints of A left: %s" % _airside.graph.has_waypoint(&"Stand_A"))
	assert_int(_airside.stand_moves).is_equal(moves + 1)
	assert_bool(_airside.graph.has_waypoint(&"Stand_A")).is_false()
	assert_object(_airside.get_node_or_null("Stand_A")).is_null()
	assert_bool(_airside.graph.has_waypoint(&"Stand_B")).is_true()
	var legacy := _airside.phase_path(FlightSim.State.PUSHBACK, "C")
	assert_array(Array(legacy)).is_equal([_at(&"Stand"), _at(&"PushbackEnd")])
	# The same stands again change nothing.
	assert_bool(_airside.set_gate_stands({"B": STAND_B})).is_true()
	assert_int(_airside.stand_moves).is_equal(moves + 1)


func test_a_plane_view_draws_its_gates_flight_on_that_gates_stand() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	var starts := FlightSim.schedule_starts(FIRST)
	assert_bool(sim.add_flight("AT_B", starts, "B")).is_true()
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	view.gate = "B"
	add_child(view)
	auto_free(view)
	var parked := float(starts[FlightSim.State.BOARDING]) + 10.0
	var shown := view.sightings(parked)
	var origin: Vector3 = shown[0]["transform"].origin
	print("gate B view: %s at %s" % [shown[0]["id"], origin])
	assert_str(shown[0]["id"]).is_equal("AT_B")
	var b := StandPlacement.stand_point(STAND_B)
	assert_float(origin.x).is_equal_approx(b.x, 0.001)
	assert_float(origin.z).is_equal_approx(b.z, 0.001)
	# A control: the gate A view lists nothing.
	view.gate = "A"
	assert_array(view.sightings(parked)).is_empty()


func test_the_fleet_gives_every_gate_with_a_flight_two_views() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	var fleet := PlaneFleet.new()
	fleet.sim = sim
	fleet.clock = auto_free(SimClock.new()) as SimClock
	fleet.airside = _airside
	var first := PlaneView.new()
	first.sim = sim
	first.clock = fleet.clock
	first.airside = _airside
	fleet.add_child(first)
	fleet.views = [first] as Array[PlaneView]
	add_child(fleet)
	auto_free(fleet)
	fleet.update_views()
	assert_array(fleet.gates).is_empty()
	assert_str(first.gate).is_equal("")
	assert_bool(sim.add_flight("ONE", FlightSim.schedule_starts(FIRST), "B")).is_true()
	assert_bool(sim.add_flight("TWO", FlightSim.schedule_starts(FIRST + 1200), "A")).is_true()
	fleet.update_views()
	var handed: Array = []
	for view in fleet.views:
		handed.append([view.gate, view.slot])
	print("fleet gates %s, views %s" % [fleet.gates, handed])
	assert_array(fleet.gates).is_equal(["A", "B"])
	assert_array(handed).is_equal([["A", 0], ["A", 1], ["B", 0], ["B", 1]])
	assert_object(fleet.views[0]).is_same(first)
