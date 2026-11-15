class_name TestTaxiGraph
extends GdUnitTestSuite


func test_waypoints_keep_their_positions() -> void:
	var graph := TaxiGraph.new()
	assert_bool(graph.add_waypoint(&"a", Vector3(1, 0, 2))).is_true()
	assert_bool(graph.add_waypoint(&"b", Vector3(10, 0, 0))).is_true()
	assert_bool(graph.has_waypoint(&"a")).is_true()
	assert_that(graph.position_of(&"a")).is_equal(Vector3(1, 0, 2))
	assert_dict(graph.points()).is_equal({&"a": Vector3(1, 0, 2), &"b": Vector3(10, 0, 0)})


func test_a_taken_or_unknown_waypoint_is_refused() -> void:
	var graph := TaxiGraph.new()
	graph.add_waypoint(&"a", Vector3.ONE)
	assert_bool(graph.add_waypoint(&"a", Vector3.ZERO)).is_false()
	assert_that(graph.position_of(&"a")).is_equal(Vector3.ONE)
	assert_bool(graph.has_waypoint(&"nowhere")).is_false()
	assert_that(graph.position_of(&"nowhere")).is_equal(Vector3.ZERO)


## Every required waypoint at x = its name's length, the lane's ends at x -100
## and 100 so StandLane (x 9) lies between them.
func _airside() -> Airside:
	var airside := auto_free(Airside.new()) as Airside
	var lane_x := {&"TaxiWest": -100.0, &"TaxiEast": 100.0}
	for name in Airside.REQUIRED_WAYPOINTS:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = Vector3(lane_x.get(name, float(name.length())), 0.0, 0.0)
		airside.add_child(marker)
	return airside


## The taxi routes come from TaxiRoutes and the marker children, whatever the
## links say: taxi in runs RunwayExit, TaxiEast, StandLane, PushbackEnd, Stand.
func test_airside_routes_its_marker_children_through_taxi_routes() -> void:
	var airside := _airside()
	airside.links = PackedStringArray(
		["RunwayExit>Stand", "Stand>PushbackEnd", "PushbackEnd>RunwayEntry"]
	)
	assert_bool(airside.rebuild()).is_true()
	var at := func(name: StringName) -> Vector3: return airside.graph.position_of(name)
	(
		assert_array(Array(airside.phase_path(FlightSim.State.TAXI_IN)))
		. is_equal(
			[
				at.call(&"RunwayExit"),
				at.call(&"TaxiEast"),
				at.call(&"StandLane"),
				at.call(&"PushbackEnd"),
				at.call(&"Stand"),
			]
		)
	)
	assert_array(Array(airside.phase_path(FlightSim.State.TAXI_OUT))).is_equal(
		[
			at.call(&"PushbackEnd"),
			at.call(&"StandLane"),
			at.call(&"TaxiWest"),
			at.call(&"RunwayEntry")
		]
	)
	assert_int(airside.phase_path(FlightSim.State.BOARDING).size()).is_equal(0)


func test_airside_reports_a_missing_waypoint() -> void:
	var airside := _airside()
	airside.get_node("Stand").free()
	assert_bool(airside.rebuild()).is_false()
	assert_int(airside.phase_path(FlightSim.State.LANDING).size()).is_equal(0)


## An L corner rounded at 100 m: the arc points sit 100 m from the turn's centre
## and the track keeps its ends. A 1000 m radius does not fit and gets the
## widest turn that leaves the 45 m end straights.
func test_round_corners_turns_on_a_circle_that_fits() -> void:
	var corners := PackedVector3Array([Vector3(0, 9, 0), Vector3(0, 9, 300), Vector3(300, 9, 300)])
	var track := Airside.round_corners(corners, 100.0, 45.0, 4.0)
	assert_that(track[0]).is_equal(corners[0])
	assert_that(track[track.size() - 1]).is_equal(corners[2])
	assert_int(track.size()).is_greater(30)
	for i in range(1, track.size() - 1):
		assert_float(track[i].distance_to(Vector3(100, 9, 200))).is_equal_approx(100.0, 0.01)
		assert_float(track[i].y).is_equal(9.0)
	var wide := Airside.round_corners(corners, 1000.0, 45.0, 4.0)
	assert_float(wide[1].distance_to(Vector3(0, 9, 45))).is_less(0.01)
	assert_float(wide[2].distance_to(Vector3(255, 9, 45))).is_equal_approx(255.0, 0.01)


func test_the_airside_gives_both_sky_tracks() -> void:
	var airside := _airside()
	assert_bool(airside.rebuild()).is_true()
	assert_int(airside.lead_in_track().size()).is_greater_equal(5)
	assert_int(airside.climb_out_track().size()).is_greater_equal(3)
