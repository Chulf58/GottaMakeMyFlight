class_name TestFlightPlannerSheets
extends GdUnitTestSuite
## The planner and the Offers sheet share the clock's exclusive turn. Opening one
## while the other is open closes the other at once and takes its turn, in both
## directions, leaving exactly one hold on the clock.

var _port: SubViewport
var _clock: SimClock
var _sim: FlightSim
var _desk: OfferDesk
var _offers: OfferPanel
var _planner: FlightPlanner


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_sim = FlightSim.new()
	_port.add_child(_sim)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.clock = _clock
	_port.add_child(_desk)
	(
		assert_bool(
			_desk.board.from_snapshot(
				TestOfferBoard.save_of(TestOfferBoard.day_records(0, [600, 660, 1200]))
			)
		)
		. is_true()
	)
	_offers = OfferPanel.new()
	_offers.desk = _desk
	_offers.flights = _sim
	_offers.clock = _clock
	_port.add_child(_offers)
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	_port.add_child(_planner)


func after_test() -> void:
	_port.free()


func test_opening_the_planner_over_offers_closes_offers_and_takes_the_turn() -> void:
	_offers.open()
	assert_bool(_offers.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_planner.open()
	print(
		(
			"offers open %s planner open %s holds %d"
			% [_offers.is_open(), _planner.is_open(), _clock.holds.count()]
		)
	)
	assert_bool(_offers.is_open()).is_false()
	assert_bool(_planner.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	assert_bool(_clock.paused).is_true()


func test_opening_offers_over_the_planner_closes_the_planner_and_takes_the_turn() -> void:
	_planner.open()
	assert_bool(_planner.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_offers.open()
	print(
		(
			"offers open %s planner open %s holds %d"
			% [_offers.is_open(), _planner.is_open(), _clock.holds.count()]
		)
	)
	assert_bool(_planner.is_open()).is_false()
	assert_bool(_offers.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	assert_bool(_clock.paused).is_true()


func test_closing_the_last_sheet_releases_the_clock() -> void:
	_offers.open()
	_planner.open()
	_planner.close()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()
