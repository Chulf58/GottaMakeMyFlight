class_name TestOfferPanelFitRefresh
extends GdUnitTestSuite
## The open sheet's fit lines follow the planning state (decision airline-
## offers-2-a-day-fit-the-free-gate-slots-1-needs-more, point 6): a change to
## the gates, a gate's stand, the runway works or the runway's size makes
## FlightSim say planning_changed, and the cards are rewritten on the next
## frame, while the clock stays paused under the sheet.

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _panel: OfferPanel
var _planning_changes := 0


func before_test() -> void:
	_planning_changes = 0
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_sim = FlightSim.new()
	_sim.open_airport()
	_port.add_child(_desk)
	_port.add_child(_sim)
	if _sim.has_signal("planning_changed"):
		_sim.connect("planning_changed", func() -> void: _planning_changes += 1)


func after_test() -> void:
	_port.free()


## Loads day 0's offers at `minutes`, all of `size`, and opens the sheet on them.
func _open(minutes: Array, size := PlaneClasses.SMALL) -> void:
	var offers := TestOfferBoard.day_records(0, minutes)
	for offer: Dictionary in offers:
		offer["plane_size"] = size
		offer["booked_passengers"] = 40 if size == PlaneClasses.MEDIUM else 12
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_panel.open()


func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_new_gate_rewrites_the_cards_while_the_sheet_is_open() -> void:
	assert_bool(_sim.accept_contract(TestFlightFit.terms("K10", 600))).is_true()
	_open([1200, 720, 1260])
	assert_str(_panel.fit_text("O0N2")).is_equal(FlightFit.ANOTHER_GATE_TEXT)
	_sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	await _frame()
	print("after gate D: '%s', planning_changed %d" % [_panel.fit_text("O0N2"), _planning_changes])
	assert_str(_panel.fit_text("O0N2")).is_equal(FlightFit.FITS_TEXT)
	assert_int(_planning_changes).is_equal(1)


func test_a_smaller_stand_rewrites_the_cards_while_the_sheet_is_open() -> void:
	_open([600, 720, 1200], PlaneClasses.MEDIUM)
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.FITS_TEXT)
	var stand: Dictionary = FlightGround.fallback("C")["stand"]
	_sim.stand_source = func() -> Dictionary:
		return {"C": {"stand": stand, "max_class": PlaneClasses.SMALL}}
	await _frame()
	print("after a small stand: '%s'" % _panel.fit_text("O0N1"))
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.STAND_TEXT % PlaneClasses.MEDIUM)
	assert_int(_planning_changes).is_equal(1)


func test_a_runway_size_change_rewrites_the_cards_while_the_sheet_is_open() -> void:
	_open([600, 720, 1200], PlaneClasses.MEDIUM)
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.FITS_TEXT)
	_sim.runway.size = PlaneClasses.SMALL
	await _frame()
	print("after a small runway: '%s'" % _panel.fit_text("O0N1"))
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.RUNWAY_TEXT % PlaneClasses.MEDIUM)
	assert_int(_planning_changes).is_equal(1)


## Works booked from 03:00 on day 1 hold the runway till 05:00, when the 07:00 flight
## lands, so its card stops saying it fits.
func test_runway_works_rewrite_the_cards_while_the_sheet_is_open() -> void:
	_sim.runway.size = PlaneClasses.MEDIUM
	_sim.tick = GameCalendar.tick_at(1, 3 * 60)
	_open([420, 720, 1200])
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.FITS_TEXT)
	var changes_before := _planning_changes
	assert_bool(_sim.start_works(PlaneClasses.LARGE)).is_true()
	await _frame()
	print(
		(
			"works %d..%d: 07:00 says '%s'"
			% [_sim.runway.works.start, _sim.runway.works.finish, _panel.fit_text("O0N1")]
		)
	)
	assert_str(_panel.fit_text("O0N1")).is_not_equal(FlightFit.FITS_TEXT)
	assert_int(_planning_changes - changes_before).is_equal(1)


## With nothing changed, frames go by and nothing is said or rewritten.
func test_no_change_says_nothing() -> void:
	_open([600, 720, 1200])
	await _frame()
	await _frame()
	assert_int(_planning_changes).is_equal(0)
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.FITS_TEXT)
