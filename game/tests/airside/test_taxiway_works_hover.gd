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
	_flights.on_tick(FlightTimetable.issue_tick(contract, day, 0))
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
			% [named, GameCalendar.clock_text(release, 0)]
		)
	)
	assert_str(text).contains(GameCalendar.clock_text(takeoff, 0))


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
	var tomorrow := GameCalendar.day_start(1, 0) + 5 * GameCalendar.TICKS_PER_MINUTE
	assert_str(SideSpurs.works_text(StandPlacement.EAST, tomorrow, 0)).is_equal(
		"Taxiway works: the taxiway moves when the east side is quiet, forecast tomorrow at 00:05"
	)


## Gate A on `side` with its spur held pending `move_m` out from where it is (a
## FlightSim.spur_source stub over GateDesks' spurs), the airside paved for it,
## the view refreshed and a camera looking down on the yard. Returns the yard.
func _short_move(side: String, move_m: float) -> Rect2:
	var spurs := _gates.spurs()
	var now := float(spurs[side]["x"])
	spurs[side] = {"x": now, "wanted": now + float(SideSpurs.OUT[side]) * move_m}
	_flights.spur_source = func() -> Dictionary: return spurs
	_airside.set_gate_classes({"A": PlaneClasses.LARGE})
	assert_bool(_airside.set_gate_stands(_gates.stands)).is_true()
	_view.bind(_flights, _airside)
	_view.refresh()
	var layout: Dictionary = _view.layouts.get(side, {})
	assert_bool(layout.is_empty()).is_false()
	var yard: Rect2 = layout.get("yard", Rect2())
	var kinds := {}
	for item: Dictionary in layout.get("props", []):
		kinds[item["kind"]] = kinds.get(item["kind"], 0) + 1
		if item["kind"] in ["fence", "loader", "trailer", "bricks"]:
			assert_bool(yard.encloses((item["rect"] as Rect2).grow(-0.01))).is_true()
	var live := TaxiwayWorks.live_rects(_airside.paving.shown, _airside.paving.pads, Runway.SMALL)
	for live_rect in live:
		assert_bool(yard.intersects(live_rect.grow(TaxiwayWorks.CLEAR_M))).is_false()
	print(
		(
			"%s moves %.0f m: pieces %d, props %s, yard %s"
			% [side, move_m, layout.get("ground", []).size(), kinds, yard]
		)
	)
	assert_bool(yard.has_area()).is_true()
	assert_int(kinds.get("bricks", 0)).is_equal(1)
	assert_int(kinds.get("loader", 0)).is_equal(1)
	assert_int(kinds.get("trailer", 0)).is_equal(1)
	assert_int(kinds.get("fence", 0)).is_equal(10)
	return yard


## The view's hover provider gives a sign for `side`'s yard, with the forecast.
func _check_sign(side: String, yard: Rect2) -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var middle := Vector3(yard.get_center().x, 0.0, yard.get_center().y)
	camera.look_at_from_position(middle + Vector3(0.0, 80.0, 40.0), middle)
	camera.make_current()
	var signs := _view.hover_signs()
	camera.free()
	var found: Array[Dictionary] = []
	for entry in signs:
		if entry["key"] == side:
			found.append(entry)
	print("%s signs %s" % [side, found])
	assert_array(found).has_size(1)
	assert_bool((found[0]["rect"] as Rect2).has_area()).is_true()
	assert_str(found[0]["text"]).contains("forecast at")


func test_a_short_west_move_still_shows_a_yard_and_its_hover_sign() -> void:
	assert_int(SpurMoveKit.west_gate(_grid, _flights, _gates)).is_not_zero()
	for move_m in [1.0, 2.0, 7.0]:
		_check_sign(StandPlacement.WEST, _short_move(StandPlacement.WEST, move_m))


func test_a_short_east_move_still_shows_a_yard_and_its_hover_sign() -> void:
	assert_int(SpurMoveKit.east_gate(_grid, _flights, _gates)).is_not_zero()
	for move_m in [1.0, 2.0, 7.0]:
		_check_sign(StandPlacement.EAST, _short_move(StandPlacement.EAST, move_m))
