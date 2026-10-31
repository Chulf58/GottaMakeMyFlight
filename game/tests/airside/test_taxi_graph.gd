class_name TestTaxiGraph
extends GdUnitTestSuite


func _graph() -> TaxiGraph:
	var graph := TaxiGraph.new()
	graph.add_waypoint(&"a", Vector3(0, 0, 0))
	graph.add_waypoint(&"b", Vector3(10, 0, 0))
	graph.add_waypoint(&"c", Vector3(10, 0, 10))
	graph.add_waypoint(&"far", Vector3(100, 0, 100))
	graph.add_waypoint(&"island", Vector3(-50, 0, 0))
	graph.link(&"a", &"b")
	graph.link(&"b", &"c")
	graph.link(&"a", &"far")
	graph.link(&"c", &"far")
	return graph


func test_route_follows_links_in_order() -> void:
	var route := _graph().route(&"a", &"c")
	assert_array(Array(route)).is_equal([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])


func test_route_is_symmetric_taxiways_run_both_ways() -> void:
	var back := _graph().route(&"c", &"a")
	assert_array(Array(back)).is_equal([Vector3(10, 0, 10), Vector3(10, 0, 0), Vector3(0, 0, 0)])


func test_route_picks_the_shorter_way_round() -> void:
	var route := _graph().route(&"a", &"far")
	assert_int(route.size()).is_equal(2)


func test_unknown_or_unreachable_waypoints_give_an_empty_route() -> void:
	var graph := _graph()
	assert_int(graph.route(&"a", &"nowhere").size()).is_equal(0)
	assert_int(graph.route(&"a", &"island").size()).is_equal(0)


func test_linking_an_unknown_waypoint_is_refused() -> void:
	var graph := _graph()
	assert_bool(graph.link(&"a", &"nowhere")).is_false()
	assert_bool(graph.add_waypoint(&"a", Vector3.ONE)).is_false()
	assert_that(graph.position_of(&"a")).is_equal(Vector3.ZERO)


func _airside() -> Airside:
	var airside := auto_free(Airside.new()) as Airside
	for name in Airside.REQUIRED_WAYPOINTS:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = Vector3(float(name.length()), 0.0, 0.0)
		airside.add_child(marker)
	return airside


func test_airside_builds_its_graph_from_marker_children() -> void:
	var airside := _airside()
	airside.links = PackedStringArray(
		["RunwayExit>Stand", "Stand>PushbackEnd", "PushbackEnd>RunwayEntry"]
	)
	assert_bool(airside.rebuild()).is_true()
	assert_int(airside.phase_path(FlightSim.State.TAXI_IN).size()).is_equal(2)
	assert_int(airside.phase_path(FlightSim.State.TAXI_OUT).size()).is_equal(2)
	assert_int(airside.phase_path(FlightSim.State.BOARDING).size()).is_equal(0)


func test_airside_reports_a_missing_waypoint() -> void:
	var airside := _airside()
	airside.get_node("Stand").free()
	assert_bool(airside.rebuild()).is_false()


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
