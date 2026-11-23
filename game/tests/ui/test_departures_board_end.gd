class_name TestDeparturesBoardEnd
extends GdUnitTestSuite
## Ending a contract now lives exclusively in FlightPlanner (P) (decision
## departures-live-ops-drawer-and-actionable-on-time-hud-stat, 35d321c7),
## sharing DeparturesBoard's static end_prompt, end_outcome, and
## end_refusal_words helpers. DeparturesBoard rows have no inline End buttons.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _planner: FlightPlanner


class StrandPlans:
	extends FlightPlans
	var strand := true

	func plan_day(world: Dictionary, day: int) -> Dictionary:
		var out := {}
		var ids := {}
		for req: Dictionary in FlightPlans.requests(world, day):
			ids[FlightTimetable.parse_occurrence(req["id"])["contract"]] = true
		for req: Dictionary in FlightPlans.requests(world, day):
			var contract: String = FlightTimetable.parse_occurrence(req["id"])["contract"]
			var stranded: bool = strand and contract == "C" and ids.has("B") and not ids.has("A")
			out[req["id"]] = {
				"ok": not stranded,
				"reason": GroundPlanner.TAXI_BUSY if stranded else "",
				"pauses": {},
				"bookings": [],
			}
		return out


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_end")
	_board.flights = _sim
	_board.clock = _clock
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	_planner.free()
	DirAccess.remove_absolute(path)


func _accept(spec: Array) -> void:
	var terms := TestFlightContracts.terms(spec[0], spec[1])
	terms["destination"] = spec[2]
	assert_bool(_sim.accept_contract(terms)).is_true()


func _build(specs: Array) -> void:
	for spec: Array in specs:
		_accept(spec)
	add_child(_board)
	_board.set_shown(true)
	add_child(_planner)
	_planner.open()


func _press(button: Button) -> void:
	assert_object(button).is_not_null()
	button.pressed.emit()


func _x_and_y() -> void:
	_build([["X", 600, "Oslo"], ["Y", 660, "Rome"]])


func _strand_world() -> StrandPlans:
	var plans := StrandPlans.new()
	_sim._plans = plans
	_build([["A", 600, "Oslo"], ["B", 660, "Rome"], ["C", 900, "Paris"]])
	return plans


func test_departures_rows_have_no_end_buttons() -> void:
	_x_and_y()
	assert_array(_board.find_children("End_*", "Button", true, false)).is_empty()
	assert_object(_planner.bar_button("X", 0)).is_not_null()


func test_a_flight_already_booked_for_today_still_flies_after_planner_end() -> void:
	_x_and_y()
	for t in range(1, FlightTimetable.issue_tick(_sim.contract_of("X"), 0, 0) + 1):
		_sim.on_tick(t)
	_clock.tick = _sim.tick
	_board.refresh()
	_planner.refresh()
	assert_array(_sim.flight_ids()).contains(["X-d0"])
	_press(_planner.bar_button("X", 0))
	_press(_planner.part("EndContract") as Button)
	_press(_planner.part("ConfirmEnd") as Button)
	_board.refresh()
	assert_array(_sim.flight_ids()).contains(["X-d0"])
	assert_str("\n".join(_board.shown_lines())).contains("10:00  Oslo  Gotta Air")


func test_a_refused_end_shows_the_reason_in_planner_and_ends_nothing() -> void:
	_strand_world()
	assert_dict(_sim.end_refusal("A")).is_not_empty()
	_press(_planner.bar_button("A", 0))
	_press(_planner.part("EndContract") as Button)
	var shown := _planner.message_text()
	print("refused: ", shown)
	assert_str(shown).is_equal(
		DeparturesBoard.END_REFUSED_TEXT.format(
			{"time": "15:00", "airline": "Gotta Air", "city": "Paris"}
		)
	)
	assert_bool(shown.contains("C-d")).is_false()
	assert_object(_planner.part("ConfirmEnd")).is_null()
	assert_array(_sim.active_contract_ids()).is_equal(["A", "B", "C"])
	assert_int(_sim.contract_end_day("A")).is_equal(-1)


func test_a_refused_end_is_one_translated_sentence() -> void:
	_strand_world()
	var german := Translation.new()
	german.locale = TranslationServer.get_locale()
	german.add_message(
		DeparturesBoard.END_REFUSED_TEXT,
		"Vertrag nicht beendet: der {airline}-Flug um {time} nach {city} hätte keinen Rollplan"
	)
	TranslationServer.add_translation(german)
	var shown := DeparturesBoard.end_refusal_words(_sim, "A")
	TranslationServer.remove_translation(german)
	print("refused (run-time translation): ", shown)
	assert_str(shown).is_equal(
		"Vertrag nicht beendet: der Gotta Air-Flug um 15:00 nach Paris hätte keinen Rollplan"
	)


func test_a_world_that_changed_while_asking_is_refused_at_the_confirm() -> void:
	var plans := _strand_world()
	plans.strand = false
	_press(_planner.bar_button("A", 0))
	_press(_planner.part("EndContract") as Button)
	assert_object(_planner.part("ConfirmEnd")).is_not_null()
	plans.strand = true
	_press(_planner.part("ConfirmEnd") as Button)
	print("late refusal: ", _planner.message_text(), " active=", _sim.active_contract_ids())
	assert_str(_planner.message_text()).starts_with("Can't end this contract")
	assert_array(_sim.active_contract_ids()).is_equal(["A", "B", "C"])
	assert_object(_planner.part("ConfirmEnd")).is_null()
