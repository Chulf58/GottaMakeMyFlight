class_name TestAirsideStand
extends GdUnitTestSuite
## main.tscn's airside after the move north (decision plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, points 1, 5 and 6): the runway at
## z -310, the taxi lane at z -256, the lead-in pass kept at z -8; the taxi
## graph and PlaneView follow Airside.set_stand(); and the peak taxi speed on
## the longest route a legal stand gives stays at or under about 16 m/s.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
const FIRST := 3000
## Peak speed allowed on a taxi phase, m/s.
const TAXI_PEAK_LIMIT := 16.0
const TICKS_PER_SECOND := 20.0

var _airside: Airside
var _grid: BuildGrid


## Builds the real Airside markers from main.tscn's saved state, without
## instantiating the scene, and keeps them in the tree for the whole file.
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
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func after() -> void:
	_airside.free()


func before_test() -> void:
	assert_bool(_airside.set_stand(StandPlacement.starter_stand(_grid, SITE))).is_true()


func _at(waypoint: StringName) -> Vector3:
	return _airside.graph.position_of(waypoint)


func test_the_runway_sits_at_z_minus_310_and_the_taxi_lane_at_minus_256() -> void:
	for waypoint in [&"ApproachStart", &"Touchdown", &"RunwayExit", &"RunwayEntry", &"Liftoff"]:
		assert_float(_at(waypoint).z).is_equal(-310.0)
	for waypoint in [&"TaxiEast", &"TaxiWest", &"StandLane"]:
		assert_float(_at(waypoint).z).is_equal(StandPlacement.TAXI_LANE_Z)
	# The lead-in pass that shadows the terminal stays.
	assert_float(_at(&"ArrivalPass").z).is_equal(-8.0)
	assert_float(_at(&"ArrivalTurnWest").z).is_equal(-8.0)


func test_the_scene_markers_start_on_the_starter_stand() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var starter := StandPlacement.starter_stand(_grid, SITE)
	var expected := {
		"Stand": StandPlacement.stand_point(starter),
		"PushbackEnd": StandPlacement.pushback_end(starter),
		"StandLane": StandPlacement.lane_join(starter),
	}
	for i in state.get_node_count():
		var name := String(state.get_node_name(i))
		if String(state.get_node_path(i, true)) == "./Airside" and expected.has(name):
			var xf := Transform3D.IDENTITY
			for k in state.get_node_property_count(i):
				if state.get_node_property_name(i, k) == &"transform":
					xf = state.get_node_property_value(i, k)
			print("%s in the scene at %s" % [name, xf.origin])
			assert_vector(xf.origin).is_equal_approx(expected[name], Vector3.ONE * 0.001)
			expected.erase(name)
	assert_dict(expected).is_empty()


func test_set_stand_moves_the_taxi_routes() -> void:
	var moves := _airside.stand_moves
	var stand := StandPlacement.make(7, 10.5, -150.0)
	assert_bool(_airside.set_stand(stand)).is_true()
	var at := StandPlacement.stand_point(stand)
	var back := StandPlacement.pushback_end(stand)
	var taxi_in := _airside.phase_path(FlightSim.State.TAXI_IN)
	var pushback := _airside.phase_path(FlightSim.State.PUSHBACK)
	var taxi_out := _airside.phase_path(FlightSim.State.TAXI_OUT)
	print("taxi in %s\npushback %s\ntaxi out %s" % [taxi_in, pushback, taxi_out])
	assert_int(_airside.stand_moves).is_equal(moves + 1)
	assert_array(Array(taxi_in)).is_equal(
		[_at(&"RunwayExit"), _at(&"TaxiEast"), Vector3(at.x, 0, -256), back, at]
	)
	assert_array(Array(pushback)).is_equal([at, back])
	assert_array(Array(taxi_out)).is_equal(
		[back, Vector3(at.x, 0, -256), _at(&"TaxiWest"), _at(&"RunwayEntry")]
	)


func test_plane_view_reads_its_paths_again_after_the_stand_moves() -> void:
	var view := PlaneView.new()
	view.sim = auto_free(FlightSim.new()) as FlightSim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	add_child(view)
	auto_free(view)
	var starts := FlightSim.schedule_starts(FIRST)
	var parked := float(starts[FlightSim.State.BOARDING]) + 10.0
	var before_move: Transform3D = view.pose_at(starts, parked)["transform"]
	var stand := StandPlacement.make(7, 10.5, -150.0)
	_airside.set_stand(stand)
	var after_move: Transform3D = view.pose_at(starts, parked)["transform"]
	print("parked before %s, after %s" % [before_move.origin, after_move.origin])
	var starter := StandPlacement.stand_point(StandPlacement.starter_stand(_grid, SITE))
	assert_vector(before_move.origin).is_equal_approx(starter, Vector3.ONE * 0.001)
	assert_vector(after_move.origin).is_equal_approx(
		StandPlacement.stand_point(stand), Vector3.ONE * 0.001
	)
	# Parked nose-in: the nose points +z, towards the terminal.
	assert_float(after_move.basis.z.z).is_greater(0.99)


## The fastest the plane moves over `state`, in m/s, sampled every tick.
func _peak_speed(state: int, entry: Vector3) -> float:
	var path := _airside.phase_path(state)
	var ticks := FlightSim.PHASE_TICKS[state]
	var peak := 0.0
	var last := FlightPose.pose(state, 0.0, path, entry).origin
	for tick in range(1, ticks + 1):
		var now := FlightPose.pose(state, tick / float(ticks), path, entry).origin
		peak = maxf(peak, now.distance_to(last) * TICKS_PER_SECOND)
		last = now
	return peak


func test_taxi_peak_speed_stays_under_16_m_s_on_the_longest_legal_route() -> void:
	var low := SITE.grid_origin
	var high := SITE.grid_origin + Vector3(SITE.grid_size.x, 0.0, SITE.grid_size.y)
	var worst := 0.0
	for door_x in [low.x + 0.5, high.x - 0.5]:
		# Wall lines from the grid's north edge to its southmost row's.
		for wall_z in [low.z, high.z - 1.0]:
			_airside.set_stand(StandPlacement.make(1, door_x, wall_z))
			var landing := _airside.phase_path(FlightSim.State.LANDING)
			var taxi_in := _airside.phase_path(FlightSim.State.TAXI_IN)
			var taxi_out := _airside.phase_path(FlightSim.State.TAXI_OUT)
			var peak_in := _peak_speed(FlightSim.State.TAXI_IN, FlightPose.exit_dir(landing))
			var peak_out := _peak_speed(FlightSim.State.TAXI_OUT, Vector3.FORWARD)
			print(
				(
					"door x %.1f wall %.1f: taxi in %.1f m peak %.2f m/s, taxi out %.1f m peak %.2f m/s"
					% [
						door_x,
						wall_z,
						FlightPose.path_length(taxi_in),
						peak_in,
						FlightPose.path_length(taxi_out),
						peak_out
					]
				)
			)
			worst = maxf(worst, maxf(peak_in, peak_out))
	print("TAXI_PEAK %.2f m/s (limit %.1f)" % [worst, TAXI_PEAK_LIMIT])
	assert_float(worst).is_greater(5.0)
	assert_float(worst).is_less_equal(TAXI_PEAK_LIMIT)
