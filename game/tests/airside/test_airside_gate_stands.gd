class_name TestAirsideGateStands
extends GdUnitTestSuite
## One stand per gate on main.tscn's airside (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 3): Airside.set_gate_stands()
## gives each gate its own stand waypoints, each joined to the one taxi lane, so
## a plane taxis along the lane past the other gates' joins (TaxiRoutes leaves
## those straight points out); PlaneView draws a gate's flights on that gate's stand; PlaneFleet
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


func test_each_gate_taxis_along_the_lane_to_its_own_join() -> void:
	var a := StandPlacement.stand_point(STAND_A)
	var b := StandPlacement.stand_point(STAND_B)
	var in_a := _airside.phase_path(FlightSim.State.TAXI_IN, "A")
	var in_b := _airside.phase_path(FlightSim.State.TAXI_IN, "B")
	var out_b := _airside.phase_path(FlightSim.State.TAXI_OUT, "B")
	var push_b := _airside.phase_path(FlightSim.State.PUSHBACK, "B")
	print("taxi in A %s\ntaxi in B %s\ntaxi out B %s" % [in_a, in_b, out_b])
	# B (x 18) is east of A (x -26): A's way in runs along the lane over B's
	# join, a straight point the route leaves out.
	assert_array(Array(in_a)).is_equal(
		[
			_at(&"RunwayExit"),
			_at(&"TaxiEast"),
			_lane(STAND_A),
			StandPlacement.pushback_end(STAND_A),
			a
		]
	)
	assert_float(_lane(STAND_B).x).is_between(in_a[2].x, in_a[1].x)
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
	# The way out from B runs west over A's join to the lane's west end.
	assert_array(Array(out_b).slice(0, 3)).is_equal(
		[StandPlacement.pushback_end(STAND_B), _lane(STAND_B), _at(&"TaxiWest")]
	)
	assert_float(_lane(STAND_A).x).is_between(out_b[2].x, out_b[1].x)
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


## While gates have stands, a gate without one (and "") gets no taxi route, so
## no plane is drawn along a stand it was never planned for; its pushback
## still reads the one stand. With no gate stands every gate taxis to the one
## stand. Control: gate A routes.
func test_a_gate_with_no_stand_gets_no_taxi_route_while_gates_have_stands() -> void:
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
		assert_int(_airside.phase_path(state, "C").size()).is_equal(0)
		assert_int(_airside.phase_path(state, "").size()).is_equal(0)
	assert_int(_airside.phase_path(FlightSim.State.TAXI_IN, "A").size()).is_equal(5)
	assert_int(_airside.phase_path(FlightSim.State.PUSHBACK, "C").size()).is_equal(2)
	assert_bool(_airside.routes_gate("C")).is_false()
	assert_bool(_airside.routes_gate("A")).is_true()
	assert_bool(_airside.set_gate_stands({})).is_true()
	assert_bool(_airside.routes_gate("C")).is_true()
	var one_stand := _airside.phase_path(FlightSim.State.TAXI_IN, "")
	assert_int(one_stand.size()).is_equal(5)
	assert_array(Array(_airside.phase_path(FlightSim.State.TAXI_IN, "C"))).is_equal(
		Array(one_stand)
	)


## An airside missing a required waypoint gives empty paths, which a view
## would index; the fleet hands that gate no view, so the plane hides instead.
## Control: before the waypoint goes, the same flight is drawn.
func test_the_fleet_draws_no_plane_for_a_gate_the_airside_cannot_route() -> void:
	var airside := auto_free(TestStandLaneClearance.scene_airside()) as Airside
	add_child(airside)
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["B"] as Array[String]
	var starts := FlightSim.schedule_starts(FIRST)
	assert_bool(sim.add_flight("AT_B", starts, "B")).is_true()
	sim.tick = starts[FlightSim.State.BOARDING] + 10
	var fleet := PlaneFleet.new()
	fleet.sim = sim
	fleet.clock = auto_free(SimClock.new()) as SimClock
	fleet.airside = airside
	var first := PlaneView.new()
	first.sim = sim
	first.clock = fleet.clock
	first.airside = airside
	fleet.add_child(first)
	fleet.views = [first] as Array[PlaneView]
	add_child(fleet)
	auto_free(fleet)
	fleet.update_views()
	first.update_pose()
	print("routable: gates %s, view gate %s, visible %s" % [fleet.gates, first.gate, first.visible])
	assert_array(fleet.gates).is_equal(["B"])
	assert_bool(first.visible).is_true()
	airside.get_node("RunwayExit").free()
	assert_bool(airside.rebuild()).is_false()
	assert_int(airside.phase_path(FlightSim.State.PUSHBACK, "B").size()).is_equal(0)
	fleet.update_views()
	first.update_pose()
	print("unroutable: gates %s, view '%s', visible %s" % [fleet.gates, first.gate, first.visible])
	assert_array(fleet.gates).is_empty()
	assert_str(first.gate).is_equal("")
	assert_bool(first.visible).is_false()
