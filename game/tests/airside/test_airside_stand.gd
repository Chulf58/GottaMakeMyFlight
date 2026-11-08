class_name TestAirsideStand
extends GdUnitTestSuite
## main.tscn's airside (decision runway-and-taxi-technical-design-movement-
## plan-analytic-bookings-planned-pauses, points 1 and 4, which moves the
## airside of decision plane-stand-design-airside-moves-110-m-north-stand-
## snaps-to 28 m further north): the runway at z -338, the taxi lane at z -284
## with its ends at x +-124, per-class touchdown, liftoff and approach points,
## the hold lines on the two stubs, the lead-in pass kept at z -8 and its turns
## at x -760; every taxi route runs strictly west; the taxi graph and PlaneView
## follow Airside.set_stand(); and the peak taxi speed on the longest route a
## legal stand gives stays at or under 16 m/s for every class, with no pause
## and with the longest pause. On the ground the plane rides on the site's
## paving (y 0.2) and at y 0 off it, with no step where it crosses the site's
## edge.

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


func test_the_runway_sits_at_z_minus_338_and_the_taxi_lane_at_minus_284() -> void:
	assert_float(StandPlacement.RUNWAY_Z).is_equal(-338.0)
	assert_float(StandPlacement.TAXI_LANE_Z).is_equal(-284.0)
	for waypoint in [&"RunwayExit", &"RunwayEntry", &"ArrivalTurnNorth", &"ArrivalStraightIn"]:
		assert_float(_at(waypoint).z).is_equal(StandPlacement.RUNWAY_Z)
	for plane_class in PlaneClasses.ORDER:
		for base in [&"ApproachStart", &"Touchdown", &"Liftoff"]:
			assert_float(_at(Airside.class_point(base, plane_class)).z).is_equal(-338.0)
	for waypoint in [&"TaxiEast", &"TaxiWest", &"StandLane"]:
		assert_float(_at(waypoint).z).is_equal(StandPlacement.TAXI_LANE_Z)
	# The lane's ends and the stubs to the runway.
	assert_float(_at(&"TaxiEast").x).is_equal(124.0)
	assert_float(_at(&"RunwayExit").x).is_equal(124.0)
	assert_float(_at(&"TaxiWest").x).is_equal(-124.0)
	assert_float(_at(&"RunwayEntry").x).is_equal(-124.0)
	# The lead-in pass that shadows the terminal stays; its turns are at x -760.
	assert_float(_at(&"ArrivalPass").z).is_equal(-8.0)
	assert_float(_at(&"ArrivalTurnWest").z).is_equal(-8.0)
	assert_float(_at(&"ArrivalTurnWest").x).is_equal(-760.0)
	assert_float(_at(&"ArrivalTurnNorth").x).is_equal(-760.0)


## Small planes touch down later and lift off sooner than medium, and large
## ones touch down earlier and lift off later, all on the runway's 384 m
## (x -192 to 192) and between its ends and the exits. Every approach starts
## 230 m before its touchdown at the same height.
func test_each_class_has_its_own_touchdown_liftoff_and_approach() -> void:
	var touch: Array[float] = []
	var lift: Array[float] = []
	for plane_class in PlaneClasses.ORDER:
		var down := _at(Airside.class_point(&"Touchdown", plane_class))
		var up := _at(Airside.class_point(&"Liftoff", plane_class))
		var approach := _at(Airside.class_point(&"ApproachStart", plane_class))
		print("%s: approach %s, touchdown %s, liftoff %s" % [plane_class, approach, down, up])
		touch.append(down.x)
		lift.append(up.x)
		assert_float(down.x).is_greater(-192.0).is_less(_at(&"RunwayExit").x)
		assert_float(up.x).is_greater(_at(&"RunwayEntry").x).is_less(192.0)
		assert_float(down.x - approach.x).is_equal(230.0)
		assert_float(approach.y).is_equal(45.0)
		var landing := _airside.phase_path(FlightSim.State.LANDING, "", plane_class)
		assert_array(Array(landing)).is_equal([down, _at(&"RunwayExit")])
		var takeoff := _airside.phase_path(FlightSim.State.TAKEOFF, "", plane_class)
		assert_array(Array(takeoff)).is_equal([_at(&"RunwayEntry"), up, _at(&"ClimbEnd")])
	assert_float(touch[0]).is_greater(touch[1])
	assert_float(touch[1]).is_greater(touch[2])
	assert_float(lift[0]).is_less(lift[1])
	assert_float(lift[1]).is_less(lift[2])


## A plane stopped on a hold line, heading along its stub, keeps the reference
## footprint off the runway band: HoldIn on the east stub (heading south, away
## from the runway), HoldRunway on the west stub (heading north, towards it).
func test_the_hold_lines_sit_on_the_stubs_clear_of_the_runway() -> void:
	var runway := StandPlacement.runway_zone()
	var stubs := {
		&"HoldIn": [&"RunwayExit", &"TaxiEast", Basis.IDENTITY],
		&"HoldRunway": [&"TaxiWest", &"RunwayEntry", Basis(Vector3.UP, PI)],
	}
	for hold: StringName in stubs:
		var stub: Array = stubs[hold]
		var at := _at(hold)
		var a := _at(stub[0])
		var b := _at(stub[1])
		assert_float(at.x).is_equal(a.x)
		assert_float(at.z).is_between(minf(a.z, b.z), maxf(a.z, b.z))
		var shape := TestSharedGroundHolds.footprint(Transform3D(stub[2], at))
		var gap := INF
		for point in shape:
			gap = minf(gap, point.y - runway.end.y)
		print("%s at %s: footprint %.2f m south of the runway band" % [hold, at, gap])
		assert_bool(TestSharedGroundHolds.on_zone(shape, runway)).is_false()
		assert_float(gap).is_greater(0.5)
		# Control: 5 m nearer the runway the footprint is on it.
		var near := Transform3D(stub[2], at + Vector3(0.0, 0.0, -5.0))
		(
			assert_bool(
				TestSharedGroundHolds.on_zone(TestSharedGroundHolds.footprint(near), runway)
			)
			. is_true()
		)


## Every taxi route runs strictly west from the runway exit to the stand and
## from the stand to the runway entry, for stands across the whole site and
## for two gates at once: each step along the lane goes west (x falls), and
## every other step (the stubs and each stand's way north) runs straight
## north or south (x stays). Returns the metres walked along the lane.
func _assert_westbound(path: PackedVector3Array) -> float:
	var along_lane := 0.0
	for i in range(1, path.size()):
		var on_lane := (
			path[i - 1].z == StandPlacement.TAXI_LANE_Z and path[i].z == StandPlacement.TAXI_LANE_Z
		)
		if on_lane:
			assert_float(path[i].x).is_less(path[i - 1].x)
			along_lane += path[i - 1].x - path[i].x
		else:
			assert_float(path[i].x).is_equal(path[i - 1].x)
	return along_lane


func test_every_taxi_route_runs_strictly_west() -> void:
	var low := SITE.grid_origin
	var high := SITE.grid_origin + Vector3(SITE.grid_size.x, 0.0, SITE.grid_size.y)
	var checked := 0
	var lane_metres := 0.0
	for door_x in [low.x + 0.5, 0.5, high.x - 0.5]:
		for wall_z in [low.z, high.z - 1.0]:
			assert_bool(_airside.set_stand(StandPlacement.make(1, door_x, wall_z))).is_true()
			for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
				lane_metres += _assert_westbound(_airside.phase_path(state))
				checked += 1
	var gates := {
		"A": StandPlacement.make(1, -30.5, low.z), "B": StandPlacement.make(2, 20.5, low.z)
	}
	assert_bool(_airside.set_gate_stands(gates)).is_true()
	for gate: String in gates:
		for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
			lane_metres += _assert_westbound(_airside.phase_path(state, gate))
			checked += 1
	assert_bool(_airside.set_gate_stands({})).is_true()
	print("%d westbound routes, %.0f m along the lane" % [checked, lane_metres])
	assert_int(checked).is_equal(16)
	assert_float(lane_metres).is_greater(1000.0)


## A join at or east of TaxiEast would make a route turn back along the lane
## or add a zero-length step, so the graph refuses it. Control: a join 1 m
## inside the end is fine.
func test_a_join_off_the_lane_ends_is_refused() -> void:
	var east := _at(&"TaxiEast").x
	var inside := StandPlacement.make(1, east - 1.0 + StandPlacement.DOOR_SIDE_M, -150.0)
	assert_bool(_airside.set_stand(inside)).is_true()
	for over in [0.0, 1.0]:
		var outside := StandPlacement.make(1, east + over + StandPlacement.DOOR_SIDE_M, -150.0)
		assert_bool(_airside.set_stand(outside)).is_false()
		assert_int(_airside.phase_path(FlightSim.State.TAXI_IN).size()).is_equal(0)


## A link naming a lane waypoint that does not exist is refused, not passed
## over as a lane link. Control: the scene's links rebuild.
func test_a_link_to_a_misspelt_lane_waypoint_is_refused() -> void:
	var links := _airside.links
	assert_bool(_airside.rebuild()).is_true()
	_airside.links = links + PackedStringArray(["TaxiEast>StandLane_typo"])
	assert_bool(_airside.rebuild()).is_false()
	_airside.links = links
	assert_bool(_airside.rebuild()).is_true()


## The same gate stands that failed to rebuild fail again on a retry, rather
## than counting as already set. Control: good stands rebuild.
func test_a_failed_set_gate_stands_fails_again_on_retry() -> void:
	var east := _at(&"TaxiEast").x
	var bad := {"A": StandPlacement.make(1, east + 5.0 + StandPlacement.DOOR_SIDE_M, -210.0)}
	assert_bool(_airside.set_gate_stands(bad)).is_false()
	assert_bool(_airside.set_gate_stands(bad)).is_false()
	var good := {"A": StandPlacement.make(1, 0.5, -210.0)}
	assert_bool(_airside.set_gate_stands(good)).is_true()
	assert_bool(_airside.set_gate_stands(good)).is_true()
	assert_bool(_airside.set_gate_stands({})).is_true()


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
		[_at(&"RunwayExit"), _at(&"TaxiEast"), Vector3(at.x, 0, -284), back, at]
	)
	assert_array(Array(pushback)).is_equal([at, back])
	assert_array(Array(taxi_out)).is_equal(
		[back, Vector3(at.x, 0, -284), _at(&"TaxiWest"), _at(&"RunwayEntry")]
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
	# Parked on the site's paving, so ground_height over the stand point.
	var on_paving := Vector3.UP * SITE.ground_height
	assert_vector(before_move.origin).is_equal_approx(starter + on_paving, Vector3.ONE * 0.001)
	assert_vector(after_move.origin).is_equal_approx(
		StandPlacement.stand_point(stand) + on_paving, Vector3.ONE * 0.001
	)
	# Parked nose-in: the nose points +z, towards the terminal.
	assert_float(after_move.basis.z.z).is_greater(0.99)


func test_the_plane_rides_on_the_paving_on_the_site_and_at_y_0_off_it() -> void:
	var view := PlaneView.new()
	view.sim = auto_free(FlightSim.new()) as FlightSim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	add_child(view)
	auto_free(view)
	var starts := FlightSim.schedule_starts(FIRST)
	var parked: Transform3D = (
		view.pose_at(starts, float(starts[FlightSim.State.AT_STAND]) + 5.0)["transform"]
	)
	var lane_time := float(starts[FlightSim.State.TAXI_IN]) + 1.0
	var lane: Transform3D = view.pose_at(starts, lane_time)["transform"]
	print("at the stand %s, on the lane %s" % [parked.origin, lane.origin])
	var starter := StandPlacement.stand_point(StandPlacement.starter_stand(_grid, SITE))
	(
		assert_float(
			Vector2(parked.origin.x, parked.origin.z).distance_to(Vector2(starter.x, starter.z))
		)
		. is_less(0.01)
	)
	assert_float(parked.origin.y).is_equal_approx(0.2, 0.0001)
	assert_float(lane.origin.z).is_less(SITE.grid_origin.z - PlaneView.PAVING_RAMP_M)
	assert_float(lane.origin.y).is_equal_approx(0.0, 0.0001)
	# Every tick of the taxi in and out: the height climbs to the paving and
	# back with no step bigger than the ramp allows at taxi speed.
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
		var last := NAN
		var biggest := 0.0
		var high := 0.0
		for t in range(starts[state], starts[state + 1] + 1):
			var y: float = (view.pose_at(starts, float(t))["transform"] as Transform3D).origin.y
			if not is_nan(last):
				biggest = maxf(biggest, absf(y - last))
			high = maxf(high, y)
			last = y
		print("state %d: highest %.3f, biggest step per tick %.4f m" % [state, high, biggest])
		assert_float(high).is_equal_approx(0.2, 0.0001)
		assert_float(biggest).is_greater(0.0).is_less(0.05)


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


## The fastest a MovementPlan of `state` along `path` moves when it pauses
## MAX_PAUSE_TICKS at `hold_s`, in m/s, sampled every tick.
func _peak_paused(state: int, path: PackedVector3Array, hold_s: float) -> float:
	var pause := {"hold_s": hold_s, "ticks": MovementPlan.MAX_PAUSE_TICKS}
	var plan := MovementPlan.taxi(path, FlightSim.PHASE_TICKS[state], pause)
	assert_bool(MovementPlan.is_valid(plan)).is_true()
	var peak := 0.0
	var last := MovementPlan.position_at(plan, 0.0)
	for tick in range(1, FlightSim.PHASE_TICKS[state] + 1):
		var now := MovementPlan.position_at(plan, tick)
		peak = maxf(peak, now.distance_to(last) * TICKS_PER_SECOND)
		last = now
	return peak


## Taxi routes are the same for every class (the class changes only the
## runway points), so each class's longest route is the same; it is checked
## per class all the same. The longest pause sits at the route's hold line:
## HoldIn on the way in, HoldRunway on the way out.
func test_taxi_peak_speed_stays_under_16_m_s_on_the_longest_legal_route() -> void:
	var low := SITE.grid_origin
	var high := SITE.grid_origin + Vector3(SITE.grid_size.x, 0.0, SITE.grid_size.y)
	var hold_in := _at(&"RunwayExit").distance_to(_at(&"HoldIn"))
	var hold_out := _at(&"RunwayEntry").distance_to(_at(&"HoldRunway"))
	var worst := 0.0
	var worst_paused := 0.0
	for plane_class in PlaneClasses.ORDER:
		var class_worst := 0.0
		var class_paused := 0.0
		for door_x in [low.x + 0.5, high.x - 0.5]:
			# Wall lines from the grid's north edge to its southmost row's.
			for wall_z in [low.z, high.z - 1.0]:
				_airside.set_stand(StandPlacement.make(1, door_x, wall_z))
				var landing := _airside.phase_path(FlightSim.State.LANDING, "", plane_class)
				var taxi_in := _airside.phase_path(FlightSim.State.TAXI_IN, "", plane_class)
				var taxi_out := _airside.phase_path(FlightSim.State.TAXI_OUT, "", plane_class)
				assert_array(Array(taxi_in)).is_equal(
					Array(_airside.phase_path(FlightSim.State.TAXI_IN))
				)
				assert_array(Array(taxi_out)).is_equal(
					Array(_airside.phase_path(FlightSim.State.TAXI_OUT))
				)
				var peak_in := _peak_speed(FlightSim.State.TAXI_IN, FlightPose.exit_dir(landing))
				var peak_out := _peak_speed(FlightSim.State.TAXI_OUT, Vector3.FORWARD)
				var length_out := FlightPose.path_length(taxi_out)
				var paused_in := _peak_paused(FlightSim.State.TAXI_IN, taxi_in, hold_in)
				var paused_out := _peak_paused(
					FlightSim.State.TAXI_OUT, taxi_out, length_out - hold_out
				)
				print(
					(
						(
							"%s door x %.1f wall %.1f: taxi in %.1f m peak %.2f / paused %.2f m/s, "
							+ "taxi out %.1f m peak %.2f / paused %.2f m/s"
						)
						% [
							plane_class,
							door_x,
							wall_z,
							FlightPose.path_length(taxi_in),
							peak_in,
							paused_in,
							length_out,
							peak_out,
							paused_out
						]
					)
				)
				class_worst = maxf(class_worst, maxf(peak_in, peak_out))
				class_paused = maxf(class_paused, maxf(paused_in, paused_out))
		print(
			(
				"TAXI_PEAK %s %.2f m/s, with the longest pause %.2f m/s (limit %.1f)"
				% [plane_class, class_worst, class_paused, TAXI_PEAK_LIMIT]
			)
		)
		worst = maxf(worst, class_worst)
		worst_paused = maxf(worst_paused, class_paused)
	assert_float(worst).is_greater(5.0)
	assert_float(worst).is_less_equal(TAXI_PEAK_LIMIT)
	# The pause makes the legs faster, and still no faster than the limit.
	assert_float(worst_paused).is_greater(worst)
	assert_float(worst_paused).is_less_equal(TAXI_PEAK_LIMIT)
