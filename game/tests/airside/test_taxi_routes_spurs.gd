class_name TestTaxiRoutesSpurs
extends GdUnitTestSuite
## TaxiRoutes at west and east stands (board airside-all-around-s4): the
## layout gains two two-way spurs south from TaxiWest and TaxiEast, and the
## north lane stays westbound. A west stand's join lies on the west spur, an
## east stand's on the east spur; every route runs on the axes, and Airside
## draws the routes FlightGround plans.

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})


static func _p() -> Dictionary:
	return FlightGround.points()


static func _west() -> Dictionary:
	return StandPlacement.make(0, 0.0, -149.5, StandPlacement.WEST)


static func _east() -> Dictionary:
	return StandPlacement.make(0, 0.0, -129.5, StandPlacement.EAST)


## A join lies on the lane strictly between its ends, or on a spur: at an end's
## x and south of the lane. On an end itself, north of the lane, or beside a
## spur it does not.
func test_a_join_is_on_the_lane_or_on_a_spur() -> void:
	var layout := TaxiRoutes.north_only(_p())
	print("layout %s" % layout)
	assert_float(float(layout["lane_z"])).is_equal(StandPlacement.TAXI_LANE_Z)
	var cases := {
		Vector3(0.0, 0.0, -284.0): StandPlacement.NORTH,
		Vector3(-124.0, 0.0, -200.0): StandPlacement.WEST,
		Vector3(124.0, 0.0, -100.0): StandPlacement.EAST,
	}
	for join: Vector3 in cases:
		(
			assert_bool(TaxiRoutes.joins_lane(join, layout))
			. override_failure_message("%s" % join)
			. is_true()
		)
		assert_str(TaxiRoutes.spur_of(join, layout)).is_equal(cases[join])
	for join in [
		Vector3(-124.0, 0.0, -284.0),
		Vector3(124.0, 0.0, -284.0),
		Vector3(-124.0, 0.0, -300.0),
		Vector3(-123.0, 0.0, -200.0),
		Vector3(130.0, 0.0, -284.0),
	]:
		(
			assert_bool(TaxiRoutes.joins_lane(join, layout))
			. override_failure_message("%s" % join)
			. is_false()
		)
	assert_bool(TaxiRoutes.joins_lane(StandPlacement.lane_join(_west()), layout)).is_true()
	assert_bool(TaxiRoutes.joins_lane(StandPlacement.lane_join(_east()), layout)).is_true()


## The side routes, written out: a west stand taxis in along the whole lane and
## south down the west spur, and out north up it straight on to the west stub;
## an east stand taxis in straight on from the east stub down the east spur,
## and out north up it and west along the lane. A north stand's are unchanged.
func test_side_routes_run_on_the_spurs() -> void:
	var p := _p()
	var layout := TaxiRoutes.north_only(p)
	for stand in [_west(), _east()]:
		var ends := TaxiRoutes.stand_ends(stand)
		var paths := TaxiRoutes.phase_paths(p, ends, PlaneClasses.MEDIUM, layout)
		var want_in := [p[&"RunwayExit"], p[&"TaxiEast"], ends["join"], ends["back"], ends["spot"]]
		var want_out := [ends["back"], ends["join"], p[&"TaxiWest"], p[&"RunwayEntry"]]
		if StandPlacement.side_of(stand) == StandPlacement.WEST:
			want_in.insert(2, p[&"TaxiWest"])
		else:
			want_out.insert(2, p[&"TaxiEast"])
		print(
			(
				"%s in %s out %s"
				% [
					StandPlacement.side_of(stand),
					paths[FlightSim.State.TAXI_IN],
					paths[FlightSim.State.TAXI_OUT]
				]
			)
		)
		assert_array(Array(paths[FlightSim.State.TAXI_IN])).is_equal(want_in)
		assert_array(Array(paths[FlightSim.State.TAXI_OUT])).is_equal(want_out)
		for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]:
			assert_bool(GroundPlanner.axis_aligned(paths[state])).is_true()


## Airside takes west and east gate stands beside a north one, and draws for
## each gate, phase and class the path FlightGround plans.
func test_airside_draws_the_planned_side_routes() -> void:
	var north := StandPlacement.make(0, 40.0, -149.5)
	var stands := {"A": _west(), "B": north, "C": _east()}
	assert_bool(_airside.set_gate_stands(stands)).is_true()
	var compared := 0
	for gate: String in stands:
		for plane_class in PlaneClasses.ORDER:
			var planned := FlightGround.routes(stands[gate], plane_class)
			for state: int in planned:
				var drawn := _airside.phase_path(state, gate, plane_class)
				(
					assert_array(Array(drawn))
					. override_failure_message("gate %s %s state %d" % [gate, plane_class, state])
					. is_equal(Array(planned[state]))
				)
				compared += 1
	print("compared %d phase paths" % compared)
	assert_int(compared).is_equal(3 * 3 * 6)
