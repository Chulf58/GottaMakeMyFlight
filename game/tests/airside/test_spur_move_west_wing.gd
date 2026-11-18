class_name TestSpurMoveWestWing
extends GdUnitTestSuite
## The west spur moves with the build (board airside-all-around-s7b-side-spurs-
## move-with-the-build-switch; decision side-spur-move-design-s7-stands-carry-
## lane-x-the-wanted-spur), on the starter shell with a booked west gate A
## (SpurMoveKit): building on the grid's west edge pushes the wanted spur out,
## and the spur moves at the first quiet tick, the issued flight's TAKEOFF,
## with no issued flight's starts, stand or plan changed and the later days re-
## timed on the new stand's pair; accepting a contract that straddles the
## release moves it later and ending that contract moves it back earlier; a
## build that would strand a flight is refused with SPUR_STRANDS naming it; and
## the issued flight's spur is guarded until its TAKEOFF.

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _moved: Array[String] = []


func before() -> void:
	_base = SpurMoveKit.base_grid()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_gates = auto_free(GateDesks.new()) as GateDesks
	assert_int(SpurMoveKit.west_gate(_grid, _flights, _gates)).is_not_zero()
	_moved = []
	_flights.spur_moved.connect(func(side: String) -> void: _moved.append(side))


func _accept(id: String, minute := SpurMoveKit.MINUTE) -> void:
	var terms := SpurMoveKit.terms(id, minute)
	assert_str(_flights.accept_problem(terms)).is_equal("")
	assert_bool(_flights.accept_contract(terms)).is_true()
	assert_str(_flights.contract_of(id)["gate"]).is_equal("A")


## Issues contract `id`'s first day and returns its occurrence id.
func _issue_first(id: String) -> String:
	var contract := _flights.contract_of(id)
	_flights.on_tick(FlightTimetable.issue_tick(contract, contract["first_day"]))
	var flight := FlightTimetable.occurrence_id(id, contract["first_day"])
	assert_int(_flights.state_of(flight)).is_equal(FlightSim.State.SCHEDULED)
	return flight


func _build_wing() -> void:
	var built := _grid.apply(SpurMoveKit.floor_at(SpurMoveKit.WING))
	assert_bool(built.ok).override_failure_message(built.reason_text()).is_true()


func test_the_spur_moves_at_the_first_quiet_tick_and_later_days_are_re_timed() -> void:
	_accept("C1")
	var flight := _issue_first("C1")
	var old_pair: Array = _flights.contract_of("C1")["taxi"]
	var starts := SpurMoveKit.starts(_flights, flight)
	var stand := _flights.flight_stand(flight)
	var plan := _flights.taxi_plan(flight)
	_build_wing()
	var wanted := _grid.origin.x - SideSpurs.build_clearance()
	var takeoff := starts[FlightSim.State.TAKEOFF]
	print(
		(
			"spur now %s, wanted %s, R %d, %s takes off %d"
			% [_gates.spur_x, _gates.spur_wanted, _flights.spur_release_tick("W"), flight, takeoff]
		)
	)
	assert_float(_gates.spur_wanted["W"]).is_equal_approx(wanted, 0.0001)
	assert_float(_gates.spur_x["W"]).is_equal(-StandPlacement.SIDE_LANE_X)
	assert_bool(_flights.spur_pending("W")).is_true()
	assert_bool(_flights.spur_pending("E")).is_false()
	assert_int(_flights.spur_release_tick("W")).is_equal(takeoff)
	# The build changes nothing issued.
	assert_array(SpurMoveKit.starts(_flights, flight)).is_equal(starts)
	assert_dict(_flights.flight_stand(flight)).is_equal(stand)
	assert_dict(_flights.taxi_plan(flight)).is_equal(plan)
	_flights.on_tick(takeoff - 1)
	assert_bool(_flights.spur_pending("W")).is_true()
	assert_float(StandPlacement.lane_x_of(_gates.stands["A"])).is_equal(-StandPlacement.SIDE_LANE_X)
	assert_array(_moved).is_empty()
	_flights.on_tick(takeoff)
	var new_pair: Array = _flights.contract_of("C1")["taxi"]
	print(
		(
			"at %d: moved %s, spur %s, pair %s -> %s"
			% [takeoff, _moved, _gates.spur_x, old_pair, new_pair]
		)
	)
	assert_array(_moved).is_equal(["W"])
	assert_bool(_flights.spur_pending("W")).is_false()
	assert_float(_gates.spur_x["W"]).is_equal_approx(wanted, 0.0001)
	assert_float(StandPlacement.lane_x_of(_gates.stands["A"])).is_equal_approx(wanted, 0.0001)
	assert_array(new_pair).is_equal(TaxiTimes.for_stand(_gates.stands["A"]))
	assert_array(new_pair).is_not_equal(old_pair)
	# The issued flight keeps its starts, its stand on the old spur and its plan.
	assert_array(SpurMoveKit.starts(_flights, flight)).is_equal(starts)
	assert_dict(_flights.flight_stand(flight)).is_equal(stand)
	assert_dict(_flights.taxi_plan(flight)).is_equal(plan)
	# The next day flies the new stand on the new pair: re-timed.
	var contract := _flights.contract_of("C1")
	var day := int(contract["first_day"]) + 1
	_flights.on_tick(FlightTimetable.issue_tick(contract, day))
	var next := FlightTimetable.occurrence_id("C1", day)
	var on_old := FlightTimetable.starts_for(
		FlightContract.make(_with_taxi(contract, old_pair)), day
	)
	print(
		"%s first state %d (on the old pair: %d)" % [next, _flights.state_start(next, 0), on_old[0]]
	)
	assert_array(SpurMoveKit.starts(_flights, next)).is_equal(
		FlightTimetable.starts_for(contract, day)
	)
	assert_int(_flights.state_start(next, 0)).is_less(on_old[0])
	assert_float(StandPlacement.lane_x_of(_flights.flight_stand(next))).is_equal_approx(
		wanted, 0.0001
	)
	assert_array(_moved).is_equal(["W"])


static func _with_taxi(contract: Dictionary, pair: Array) -> Dictionary:
	var fields := contract.duplicate()
	fields["taxi"] = pair
	return fields


## A contract accepted while the spur waits, whose first day is issued before
## the issued flight's TAKEOFF, is not refused: it moves R to its own TAKEOFF.
## Ending it moves R back to the issued flight's TAKEOFF.
func test_a_straddling_accept_moves_the_release_and_ending_it_moves_it_back() -> void:
	_accept("C1")
	var flight := _issue_first("C1")
	_build_wing()
	var takeoff := _flights.state_start(flight, FlightSim.State.TAKEOFF)
	assert_int(_flights.spur_release_tick("W")).is_equal(takeoff)
	_accept("C2", SpurMoveKit.straddle_minute(_gates))
	var second := _flights.contract_of("C2")
	var day: int = second["first_day"]
	var issue := FlightTimetable.issue_tick(second, day)
	var later := FlightTimetable.starts_for(second, day)[FlightSim.State.TAKEOFF]
	print(
		(
			"C2 issues %d (before %d), takes off %d: R %d"
			% [issue, takeoff, later, _flights.spur_release_tick("W")]
		)
	)
	assert_int(issue).is_less(takeoff)
	assert_int(_flights.spur_release_tick("W")).is_equal(later)
	assert_bool(_flights.end_contract("C2")).is_true()
	print("after ending C2: R %d" % _flights.spur_release_tick("W"))
	assert_int(_flights.spur_release_tick("W")).is_equal(takeoff)
	assert_bool(_flights.spur_pending("W")).is_true()


## A floor cell on the west edge in gate A's row would put it on the new spur's
## way out for every class, leaving booked C1 no stand once the spur moves: the
## build is refused with SPUR_STRANDS, naming the flight. With nothing booked
## the same cell is built, so the refusal is the flight's.
func test_a_build_that_would_strand_a_flight_is_refused_naming_it() -> void:
	_accept("C1")
	var row := _grid.world_to_cell(StandPlacement.stand_point(_gates.stands["A"])).y
	var cell := Vector2i(0, row)
	var refused := _grid.validate(SpurMoveKit.floor_at(cell))
	var words := FlightLabel.of(_flights, false, "C1")
	print("cell %s: %s (%s); C1 reads '%s'" % [cell, refused.reason_text(), refused.detail, words])
	assert_bool(refused.ok).is_false()
	assert_int(refused.reason).is_equal(BuildResult.Reason.SPUR_STRANDS)
	assert_str(refused.detail).is_equal(words)
	assert_str(refused.detail).contains("Gotta Air").contains("Oslo")
	assert_array(refused.detail_args["flights"]).is_equal(
		[FlightLabel.label_args(_flights, false, "C1")]
	)
	assert_str(refused.reason_text()).ends_with(": %s" % words)
	assert_bool(_flights.spur_pending("W")).is_false()
	# Control: with C1 ended and none of its days issued, the cell is built.
	assert_bool(_flights.end_contract("C1")).is_true()
	var built := _grid.apply(SpurMoveKit.floor_at(cell))
	print("with C1 ended: %s" % built.reason_text())
	assert_bool(built.ok).is_true()
	assert_bool(_flights.spur_pending("W")).is_true()


## While an issued flight at gate A has not taken off, ApronStand guards its
## spur from the taxi lane to the stand's join, and a build there is refused
## with PLANE_AREA; from its TAKEOFF the band is gone.
func test_the_spur_of_an_issued_flight_is_guarded_until_takeoff() -> void:
	var apron := auto_free(ApronStand.new()) as ApronStand
	apron.bind(_grid, SpurMoveKit.SITE, _flights, _gates)
	_grid.guard = apron.edit_problem
	_accept("C1")
	var flight := _issue_first("C1")
	var bands := apron.spur_rects()
	print("bands %s" % [bands])
	assert_int(bands.size()).is_equal(1)
	assert_float(bands[0].get_center().x).is_equal(-StandPlacement.SIDE_LANE_X)
	var on_spur := _grid.world_to_cell(Vector3(-StandPlacement.SIDE_LANE_X, 0.0, -150.0))
	var refused := _grid.validate(SpurMoveKit.floor_at(on_spur))
	print("cell %s on the spur: %s" % [on_spur, refused.reason_text()])
	assert_int(refused.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	_flights.on_tick(_flights.state_start(flight, FlightSim.State.TAKEOFF))
	assert_array(apron.spur_rects()).is_empty()
