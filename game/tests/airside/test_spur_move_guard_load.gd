class_name TestSpurMoveGuardLoad
extends GdUnitTestSuite
## Review fixes on the starter shell's west gate A (SpurMoveKit): a flight on
## its side's old spur loads although the gate's new stand takes a smaller
## class; the spur band of a flight issued while the clock stands still shows
## in the guard at once; and a click on the band over land the player does not
## own reads as unowned land, not as a plane's apron.

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


func _apron() -> ApronStand:
	var apron := auto_free(ApronStand.new()) as ApronStand
	apron.bind(_grid, SpurMoveKit.SITE, _flights, _gates)
	_grid.guard = apron.edit_problem
	return apron


## A medium flight whose contract has ended: a floor cell on the west edge,
## 11 m south of gate A's stand, lies on the new spur's medium way out but not
## its small one, so once the spur moves gate A takes small planes only. Saved
## at TAKEOFF, before the flight is pruned, it loads: on the old spur, the
## gate's new class does not bind it.
func test_a_flight_on_the_old_spur_loads_after_its_gate_shrinks() -> void:
	var terms := SpurMoveKit.terms("L1")
	assert_str(terms["plane_size"]).is_equal(PlaneClasses.MEDIUM)
	assert_str(_gates.max_class("A")).is_equal(PlaneClasses.MEDIUM)
	assert_bool(_flights.accept_contract(terms)).is_true()
	var contract := _flights.contract_of("L1")
	_flights.on_tick(FlightTimetable.issue_tick(contract, contract["first_day"], 0))
	var flight := FlightTimetable.occurrence_id("L1", contract["first_day"])
	assert_bool(_flights.end_contract("L1")).is_true()
	var row := _grid.world_to_cell(StandPlacement.stand_point(_gates.stands["A"])).y + 11
	var built := _grid.apply(SpurMoveKit.floor_at(Vector2i(0, row)))
	assert_bool(built.ok).override_failure_message(built.reason_text()).is_true()
	_flights.on_tick(_flights.state_start(flight, FlightSim.State.TAKEOFF))
	print(
		(
			"after the move: gate A takes '%s', %s on spur %s, gate stand spur %s"
			% [
				_gates.max_class("A"),
				flight,
				_flights.flight_stand(flight)["lane_x"],
				_gates.stands["A"]["lane_x"]
			]
		)
	)
	assert_bool(_flights.spur_pending("W")).is_false()
	assert_str(_gates.max_class("A")).is_equal(PlaneClasses.SMALL)
	assert_int(_flights.state_of(flight)).is_equal(FlightSim.State.TAKEOFF)
	var gates_data: Dictionary = JSON.parse_string(JSON.stringify(_gates.to_snapshot()))
	var flights_data: Dictionary = JSON.parse_string(JSON.stringify(_flights.to_snapshot()))
	var sim := auto_free(FlightSim.new()) as FlightSim
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(_grid.clone() as SiteGrid, sim)
	assert_bool(gates.from_snapshot(gates_data)).is_true()
	var problem := sim.load_problem(flights_data)
	print("load problem: '%s'" % problem)
	assert_str(problem).is_equal("")
	assert_bool(sim.from_snapshot(flights_data)).is_true()
	assert_dict(sim.flight_stand(flight)).is_equal(_flights.flight_stand(flight))


## With the clock standing still, a contract whose first day is due is issued as
## it is accepted, on the same tick: the guard shows its spur band at once,
## though the guard was worked out on that tick before.
func test_a_flight_issued_on_a_still_tick_guards_its_spur_at_once() -> void:
	var apron := _apron()
	var terms := SpurMoveKit.terms("C1")
	# Issuing is anchored to the departure, whatever the pair.
	var due := GameCalendar.tick_at(0, SpurMoveKit.MINUTE, 0) - FlightTimetable.issue_lead()
	_flights.on_tick(due + 1)
	var on_spur := _grid.world_to_cell(Vector3(-StandPlacement.SIDE_LANE_X, 0.0, -150.0))
	var before := apron.guarded_cells().has(on_spur)
	assert_bool(_flights.accept_contract(terms)).is_true()
	var flight := FlightTimetable.occurrence_id("C1", 0)
	print(
		(
			"tick %d: %s state %d; band cell guarded before %s, after %s"
			% [
				_flights.tick,
				flight,
				_flights.state_of(flight),
				before,
				apron.guarded_cells().has(on_spur)
			]
		)
	)
	assert_bool(before).is_false()
	assert_int(_flights.state_of(flight)).is_equal(FlightSim.State.SCHEDULED)
	assert_bool(apron.guarded_cells().has(on_spur)).is_true()


## On a site with land plots, the spur band at x -124 lies on side land the
## player does not own: a floor there is refused as unowned land. With no land
## plots the same cell is the plane's apron.
func test_the_spur_band_over_unowned_land_reads_as_unowned_land() -> void:
	_grid.land = LandPlots.for_site(SpurMoveKit.SITE)
	var apron := _apron()
	assert_bool(_flights.accept_contract(SpurMoveKit.terms("C1"))).is_true()
	var contract := _flights.contract_of("C1")
	_flights.on_tick(FlightTimetable.issue_tick(contract, contract["first_day"], 0))
	var on_spur := _grid.world_to_cell(Vector3(-StandPlacement.SIDE_LANE_X, 0.0, -150.0))
	assert_bool(apron.guarded_cells().has(on_spur)).is_true()
	var refused := _grid.validate(SpurMoveKit.floor_at(on_spur))
	print("band cell %s: %s" % [on_spur, refused.reason_text()])
	assert_int(refused.reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	# Control: on a grid with every cell owned (no land plots) it is the plane's.
	_grid.land = null
	assert_int(_grid.validate(SpurMoveKit.floor_at(on_spur)).reason).is_equal(
		BuildResult.Reason.PLANE_AREA
	)
