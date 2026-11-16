class_name TestTaxiwayWorksHover
extends GdUnitTestSuite
## The hover text of the works over a pending side spur (board ecd67e67, S8b
## phase 2; Sol finding on S7b: the hover must show the forecast move time) on
## the starter shell with a booked west or east gate A (SpurMoveKit): building on
## that side's grid edge pushes the wanted spur out, the works show over that
## side only, and their hover text says the taxiway moves when the side is quiet
## at the clock time FlightSim.spur_release_tick() forecasts, the issued flight's
## TAKEOFF. West and east are tested separately; with nothing pending there are
## no works and no text.

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _airside: Airside
var _view: TaxiwayWorksView


func before() -> void:
	_base = SpurMoveKit.base_grid()
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_gates = auto_free(GateDesks.new()) as GateDesks
	_view = TaxiwayWorksView.new()
	# In the tree, so the props it adds in a test are not orphans.
	add_child(_view)


func after_test() -> void:
	_view.free()
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


## Books gate A's contract C1, issues its first day, builds `wing` and paves the
## airside for the gate's stand. Returns the issued flight's TAKEOFF tick.
func _pend(wing: Vector2i) -> int:
	assert_bool(_flights.accept_contract(SpurMoveKit.terms("C1"))).is_true()
	var contract := _flights.contract_of("C1")
	var day: int = contract["first_day"]
	_flights.on_tick(FlightTimetable.issue_tick(contract, day))
	var flight := FlightTimetable.occurrence_id("C1", day)
	var takeoff := _flights.state_start(flight, FlightSim.State.TAKEOFF)
	var built := _grid.apply(SpurMoveKit.floor_at(wing))
	assert_bool(built.ok).override_failure_message(built.reason_text()).is_true()
	_airside.set_gate_classes({"A": PlaneClasses.LARGE})
	assert_bool(_airside.set_gate_stands(_gates.stands)).is_true()
	_view.bind(_flights, _airside)
	_view.refresh()
	return takeoff


func _check(side: String, other: String, named: String, takeoff: int) -> void:
	var release := _flights.spur_release_tick(side)
	var text: String = _view.texts.get(side, "")
	print(
		"%s works: R %d, takeoff %d, now %d: '%s'" % [side, release, takeoff, _flights.tick, text]
	)
	assert_bool(_flights.spur_pending(side)).is_true()
	assert_int(release).is_equal(takeoff)
	assert_bool(_view.layouts.has(side)).is_true()
	assert_bool(_view.layouts.has(other)).is_false()
	assert_int(_view.layouts[side]["props"].size()).is_greater(0)
	assert_str(text).is_equal(
		(
			"Taxiway works: the taxiway moves when the %s side is quiet, forecast at %s"
			% [named, GameCalendar.clock_text(release)]
		)
	)
	assert_str(text).contains(GameCalendar.clock_text(takeoff))


func test_the_west_works_hover_shows_the_forecast_move_time() -> void:
	assert_int(SpurMoveKit.west_gate(_grid, _flights, _gates)).is_not_zero()
	var takeoff := _pend(SpurMoveKit.WING)
	_check(StandPlacement.WEST, StandPlacement.EAST, "west", takeoff)


func test_the_east_works_hover_shows_the_forecast_move_time() -> void:
	assert_int(SpurMoveKit.east_gate(_grid, _flights, _gates)).is_not_zero()
	var takeoff := _pend(SpurMoveKit.WING_EAST)
	_check(StandPlacement.EAST, StandPlacement.WEST, "east", takeoff)


func test_no_pending_spur_shows_no_works() -> void:
	assert_int(SpurMoveKit.west_gate(_grid, _flights, _gates)).is_not_zero()
	_airside.set_gate_classes({"A": PlaneClasses.LARGE})
	assert_bool(_airside.set_gate_stands(_gates.stands)).is_true()
	_view.bind(_flights, _airside)
	_view.refresh()
	assert_bool(_flights.spur_pending(StandPlacement.WEST)).is_false()
	assert_dict(_view.layouts).is_empty()
	assert_dict(_view.texts).is_empty()


func test_the_works_text_without_a_forecast_has_no_time() -> void:
	assert_str(SideSpurs.works_text(StandPlacement.WEST)).is_equal(
		"Taxiway works: the taxiway moves when the west side is quiet"
	)
	var tomorrow := GameCalendar.day_start(1) + 5 * GameCalendar.TICKS_PER_MINUTE
	assert_str(SideSpurs.works_text(StandPlacement.EAST, tomorrow, 0)).is_equal(
		"Taxiway works: the taxiway moves when the east side is quiet, forecast tomorrow at 00:05"
	)
