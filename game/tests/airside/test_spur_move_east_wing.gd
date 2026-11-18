class_name TestSpurMoveEastWing
extends GdUnitTestSuite
## The east spur moves with the build, mirroring test_spur_move_west_wing.gd's
## first case on an east gate A (SpurMoveKit.east_gate()): a floor cell on the
## grid's east edge pushes the wanted spur out to x +149.8, the spur moves at
## the issued flight's TAKEOFF with nothing issued changed, and the next day
## flies the new stand on its new pair.

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


func before() -> void:
	_base = SpurMoveKit.base_grid()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_gates = auto_free(GateDesks.new()) as GateDesks
	assert_int(SpurMoveKit.east_gate(_grid, _flights, _gates)).is_not_zero()


func test_the_east_spur_moves_at_the_first_quiet_tick() -> void:
	assert_str(StandPlacement.side_of(_gates.stands["A"])).is_equal(StandPlacement.EAST)
	assert_bool(_flights.accept_contract(SpurMoveKit.terms("C1"))).is_true()
	var contract := _flights.contract_of("C1")
	var day: int = contract["first_day"]
	_flights.on_tick(FlightTimetable.issue_tick(contract, day, 0))
	var flight := FlightTimetable.occurrence_id("C1", day)
	var starts := SpurMoveKit.starts(_flights, flight)
	var stand := _flights.flight_stand(flight)
	var plan := _flights.taxi_plan(flight)
	var built := _grid.apply(SpurMoveKit.floor_at(SpurMoveKit.WING_EAST))
	assert_bool(built.ok).override_failure_message(built.reason_text()).is_true()
	var wanted := _grid.origin.x + _grid.size.x + SideSpurs.build_clearance()
	var takeoff := starts[FlightSim.State.TAKEOFF]
	print(
		(
			"east spur %s -> %s, R %d, %s takes off %d"
			% [
				_gates.spur_x["E"],
				_gates.spur_wanted["E"],
				_flights.spur_release_tick("E"),
				flight,
				takeoff
			]
		)
	)
	assert_float(_gates.spur_wanted["E"]).is_equal_approx(wanted, 0.0001)
	assert_bool(_flights.spur_pending("E")).is_true()
	assert_bool(_flights.spur_pending("W")).is_false()
	assert_int(_flights.spur_release_tick("E")).is_equal(takeoff)
	_flights.on_tick(takeoff - 1)
	assert_float(_gates.spur_x["E"]).is_equal(StandPlacement.SIDE_LANE_X)
	_flights.on_tick(takeoff)
	assert_bool(_flights.spur_pending("E")).is_false()
	assert_float(StandPlacement.lane_x_of(_gates.stands["A"])).is_equal_approx(wanted, 0.0001)
	assert_array(SpurMoveKit.starts(_flights, flight)).is_equal(starts)
	assert_dict(_flights.flight_stand(flight)).is_equal(stand)
	assert_dict(_flights.taxi_plan(flight)).is_equal(plan)
	var moved := _flights.contract_of("C1")
	print("pair %s -> %s" % [contract["taxi"], moved["taxi"]])
	assert_array(moved["taxi"]).is_not_equal(contract["taxi"])
	_flights.on_tick(FlightTimetable.issue_tick(moved, day + 1, 0))
	var next := FlightTimetable.occurrence_id("C1", day + 1)
	assert_float(StandPlacement.lane_x_of(_flights.flight_stand(next))).is_equal_approx(
		wanted, 0.0001
	)
	assert_array(SpurMoveKit.starts(_flights, next)).is_equal(
		FlightTimetable.starts_for(moved, day + 1, 0)
	)
