class_name TestAirsideBadLink
extends GdUnitTestSuite
## A link naming an unknown waypoint fails rebuild() and takes the taxi routes
## with it (taxiroutes-as-built, board item taxiroutes-residual-edge-cases-on-
## malformed-scenes): routes_gate() is false, so the fleet draws no plane
## along a route the scene never validly gave it.

var _airside: Airside


func before_test() -> void:
	_airside = auto_free(TestStandLaneClearance.scene_airside()) as Airside
	add_child(_airside)


func test_a_bad_link_leaves_the_gate_unroutable_and_the_planes_hidden() -> void:
	assert_bool(_airside.rebuild()).is_true()
	assert_bool(_airside.routes_gate("")).is_true()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_OUT).size()).is_greater(0)
	_airside.links = _airside.links + PackedStringArray(["TaxiWest>NoSuchWaypoint"])
	var rebuilt := _airside.rebuild()
	print(
		(
			"bad link: rebuild %s, routes_gate %s, taxi out %d points"
			% [
				rebuilt,
				_airside.routes_gate(""),
				_airside.phase_path(FlightSim.State.TAXI_OUT).size()
			]
		)
	)
	assert_bool(rebuilt).is_false()
	assert_bool(_airside.routes_gate("")).is_false()
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
		assert_int(_airside.phase_path(state).size()).is_equal(0)
	var fleet := auto_free(PlaneFleet.new()) as PlaneFleet
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["B"] as Array[String]
	fleet.sim = sim
	fleet.airside = _airside
	assert_bool(sim.add_flight("F1", FlightSim.schedule_starts(3000), "B")).is_true()
	(
		assert_error(func() -> void: fleet.update_views())
		. is_push_error("PlaneFleet: gate B has no taxi route; its planes are not drawn")
	)
	assert_array(fleet.gates).is_empty()
