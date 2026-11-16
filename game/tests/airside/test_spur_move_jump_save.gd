class_name TestSpurMoveJumpSave
extends GdUnitTestSuite
## A pending west spur across a skipped-tick jump and a save (board airside-
## all-around-s7b-side-spurs-move-with-the-build-switch; decision side-spur-
## move-design-s7-stands-carry-lane-x-the-wanted-spur): with C1's first day
## issued and C2's first day due before C1's TAKEOFF, R is C2's TAKEOFF. One
## jump past C1's next issue issues C2's day on the old spur and pair, moves the
## spur at R, and issues C1's next day on the new one. A save taken while the
## spur waits, loaded into a fresh airport on the same grid, runs on exactly as
## the uninterrupted one does.

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
	assert_int(SpurMoveKit.west_gate(_grid, _flights, _gates)).is_not_zero()
	for terms in [
		SpurMoveKit.terms("C1"), SpurMoveKit.terms("C2", SpurMoveKit.straddle_minute(_gates))
	]:
		assert_bool(_flights.accept_contract(terms)).is_true()
	var first := _flights.contract_of("C1")
	_flights.on_tick(FlightTimetable.issue_tick(first, first["first_day"]))
	var built := _grid.apply(SpurMoveKit.floor_at(SpurMoveKit.WING))
	assert_bool(built.ok).override_failure_message(built.reason_text()).is_true()
	assert_bool(_flights.spur_pending("W")).is_true()


## C2's first day: [its contract before the move, the day, its issue tick].
func _second_day() -> Array:
	var second := _flights.contract_of("C2")
	return [second, second["first_day"], FlightTimetable.issue_tick(second, second["first_day"])]


func test_a_skipped_tick_jump_puts_each_occurrence_on_its_side_of_the_release() -> void:
	var first := _flights.contract_of("C1")
	var c1_takeoff := _flights.state_start("C1-d%d" % first["first_day"], FlightSim.State.TAKEOFF)
	var second_day := _second_day()
	var second: Dictionary = second_day[0]
	var released := _flights.spur_release_tick("W")
	var c2_starts := FlightTimetable.starts_for(second, second_day[1])
	var next_day: int = int(first["first_day"]) + 1
	var to := FlightTimetable.issue_tick(first, next_day) + 10
	print(
		(
			"C2 issues %d, C1 takes off %d, R %d (C2's TAKEOFF %d); jump to %d"
			% [second_day[2], c1_takeoff, released, c2_starts[FlightSim.State.TAKEOFF], to]
		)
	)
	assert_int(second_day[2]).is_less(c1_takeoff)
	assert_int(released).is_equal(c2_starts[FlightSim.State.TAKEOFF])
	assert_int(to).is_greater(released)
	_flights.on_tick(to)
	var wanted: float = _gates.spur_wanted["W"]
	var c2 := FlightTimetable.occurrence_id("C2", second_day[1])
	var c1 := FlightTimetable.occurrence_id("C1", next_day)
	print(
		(
			"%s spur %s, %s spur %s; spur now %s"
			% [
				c2,
				_flights.flight_stand(c2).get("lane_x"),
				c1,
				_flights.flight_stand(c1).get("lane_x"),
				_gates.spur_x
			]
		)
	)
	assert_bool(_flights.spur_pending("W")).is_false()
	assert_float(StandPlacement.lane_x_of(_flights.flight_stand(c2))).is_equal(
		-StandPlacement.SIDE_LANE_X
	)
	assert_array(SpurMoveKit.starts(_flights, c2)).is_equal(c2_starts)
	assert_float(StandPlacement.lane_x_of(_flights.flight_stand(c1))).is_equal_approx(
		wanted, 0.0001
	)
	var moved := _flights.contract_of("C1")
	assert_array(moved["taxi"]).is_not_equal(first["taxi"])
	assert_array(SpurMoveKit.starts(_flights, c1)).is_equal(
		FlightTimetable.starts_for(moved, next_day)
	)


## The save while the spur waits loads into a fresh airport on a copy of the
## grid, with the same release forecast; then both run the same ticks and stay
## the same, flights and gates (spurs included), through the move and the next
## days' issues.
func test_a_save_taken_while_pending_loads_into_the_same_run() -> void:
	var gates_data: Dictionary = JSON.parse_string(JSON.stringify(_gates.to_snapshot()))
	var flights_data: Dictionary = JSON.parse_string(JSON.stringify(_flights.to_snapshot()))
	var grid := _grid.clone() as SiteGrid
	var sim := auto_free(FlightSim.new()) as FlightSim
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(grid, sim)
	assert_bool(gates.from_snapshot(gates_data)).is_true()
	assert_bool(sim.from_snapshot(flights_data)).is_true()
	print(
		(
			"saved spurs %s; R %d, loaded R %d"
			% [gates_data["spurs"], _flights.spur_release_tick("W"), sim.spur_release_tick("W")]
		)
	)
	assert_dict(gates.spur_x).is_equal(_gates.spur_x)
	assert_bool(sim.spur_pending("W")).is_true()
	assert_int(sim.spur_release_tick("W")).is_equal(_flights.spur_release_tick("W"))
	var released := _flights.spur_release_tick("W")
	var first := _flights.contract_of("C1")
	var steps: Array[int] = [released - 1, released, released + 1]
	for day in range(int(first["first_day"]) + 1, int(first["first_day"]) + 3):
		steps.append(FlightTimetable.issue_tick(first, day) + 5)
	for at in steps:
		_flights.on_tick(at)
		sim.on_tick(at)
		print(
			(
				"tick %d: spurs %s / %s, flights %s"
				% [at, _gates.spur_x, gates.spur_x, sim.flight_ids()]
			)
		)
		assert_dict(sim.to_snapshot()).is_equal(_flights.to_snapshot())
		assert_dict(gates.to_snapshot()).is_equal(_gates.to_snapshot())
	assert_bool(sim.spur_pending("W")).is_false()
	assert_float(gates.spur_x["W"]).is_equal(_gates.spur_wanted["W"])
