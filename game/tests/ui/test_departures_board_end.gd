class_name TestDeparturesBoardEnd
extends GdUnitTestSuite
## The End button on each running contract's Departures row (decision
## end-contract-button-in-the-departures-list-lets-the-player-e): it asks "End
## this contract?", the confirm calls FlightSim.end_contract, the flights
## already booked for today still fly, and an end that FlightSim.end_refusal()
## refuses is not made: the row says which flight would be left with no taxi
## plan. Settings go to a per-run file (anti-pattern 1639342a, HudFlagSetting
## shields the real one under a script-driven run).
##
## Tick 0 is 06:00. X leaves at 10:00 and Y at 11:00; the strand cases add
## A (10:00), B (11:00) and C (15:00).

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard


## Greedy planning is not monotone: while B runs and A does not, C gets no
## plan (the stub of test_flight_planner_wiring). `strand` turns that off.
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


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)


func _accept(spec: Array) -> void:
	var terms := TestFlightContracts.terms(spec[0], spec[1])
	terms["destination"] = spec[2]
	assert_bool(_sim.accept_contract(terms)).is_true()


## Accepts the contracts and builds the board.
func _build(specs: Array) -> void:
	for spec: Array in specs:
		_accept(spec)
	add_child(_board)
	_board.refresh()


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


func test_each_running_contract_row_has_an_end_button() -> void:
	_x_and_y()
	for id in ["X", "Y"]:
		for day in [0, 1]:
			print("end button ", id, " day ", day, ": ", _board.end_button(id, day))
			assert_object(_board.end_button(id, day)).is_not_null()
	assert_str(_board.end_button("X", 0).text).is_equal("End")
	assert_object(_board.confirm_end_button()).is_null()


func test_pressing_end_asks_and_keep_leaves_the_contract_running() -> void:
	_x_and_y()
	_press(_board.end_button("X", 0))
	assert_object(_board.confirm_end_button()).is_not_null()
	assert_array(_sim.active_contract_ids()).is_equal(["X", "Y"])
	_press(_board.keep_button())
	print(
		"after keep: confirm=", _board.confirm_end_button(), " active=", _sim.active_contract_ids()
	)
	assert_object(_board.confirm_end_button()).is_null()
	assert_array(_sim.active_contract_ids()).is_equal(["X", "Y"])
	assert_object(_board.end_button("X", 0)).is_not_null()


func test_pressing_end_again_closes_the_question() -> void:
	_x_and_y()
	_press(_board.end_button("X", 0))
	_press(_board.end_button("X", 0))
	assert_object(_board.confirm_end_button()).is_null()


func test_confirming_ends_the_contract_and_it_leaves_the_list() -> void:
	_x_and_y()
	_press(_board.end_button("X", 0))
	_press(_board.confirm_end_button())
	print(
		"ended: active=",
		_sim.active_contract_ids(),
		" end day=",
		_sim.contract_end_day("X"),
		" message=",
		_board.message_text()
	)
	assert_array(_sim.active_contract_ids()).is_equal(["Y"])
	# Accepting issued day 0 at once, so X ends from day 1 and day 0 still flies.
	assert_int(_sim.contract_end_day("X")).is_equal(1)
	assert_str(_board.message_text()).is_equal(DeparturesBoard.ENDED_TEXT % "Oslo")
	assert_object(_board.confirm_end_button()).is_null()
	assert_object(_board.end_button("X", 0)).is_null()
	assert_object(_board.end_button("X", 1)).is_null()
	assert_object(_board.end_button("Y", 0)).is_not_null()
	# Tomorrow lists Y alone.
	assert_array(DepartureList.rows_for_day(_sim, 1)).has_size(1)
	assert_int(_board.shown_lines().size()).is_equal(5)
	assert_str("\n".join(_board.shown_lines().slice(3))).not_contains("Oslo")


func test_a_flight_already_booked_for_today_still_flies() -> void:
	_x_and_y()
	for t in range(1, FlightTimetable.issue_tick(_sim.contract_of("X"), 0) + 1):
		_sim.on_tick(t)
	_clock.tick = _sim.tick
	_board.refresh()
	assert_array(_sim.flight_ids()).contains(["X-d0"])
	_press(_board.end_button("X", 0))
	_press(_board.confirm_end_button())
	print("flies: ", _sim.flight_ids(), " lines=", _board.shown_lines())
	assert_array(_sim.flight_ids()).contains(["X-d0"])
	assert_str("\n".join(_board.shown_lines())).contains("10:00  Oslo  Gotta Air")
	assert_object(_board.end_button("X", 0)).is_null()
	assert_object(_board.end_button("X", 1)).is_null()


func test_a_refused_end_shows_the_reason_in_the_row_and_ends_nothing() -> void:
	_strand_world()
	assert_dict(_sim.end_refusal("A")).is_not_empty()
	_press(_board.end_button("A", 0))
	var shown := _board.message_text()
	print("refused: ", shown)
	assert_str(shown).is_equal(
		DeparturesBoard.END_REFUSED_TEXT % "the 15:00 Gotta Air flight to Paris"
	)
	assert_bool(shown.contains("C-d")).is_false()
	assert_object(_board.confirm_end_button()).is_null()
	assert_array(_sim.active_contract_ids()).is_equal(["A", "B", "C"])
	assert_int(_sim.contract_end_day("A")).is_equal(-1)
	# B strands nobody, so it asks as usual.
	_press(_board.end_button("B", 0))
	assert_object(_board.confirm_end_button()).is_not_null()
	assert_str(_board.message_text()).is_empty()


func test_a_world_that_changed_while_asking_is_refused_at_the_confirm() -> void:
	var plans := _strand_world()
	plans.strand = false
	_press(_board.end_button("A", 0))
	assert_object(_board.confirm_end_button()).is_not_null()
	plans.strand = true
	_press(_board.confirm_end_button())
	print("late refusal: ", _board.message_text(), " active=", _sim.active_contract_ids())
	assert_str(_board.message_text()).starts_with("Can't end this contract")
	assert_array(_sim.active_contract_ids()).is_equal(["A", "B", "C"])
	assert_object(_board.confirm_end_button()).is_null()


func test_a_load_closes_the_open_question() -> void:
	_x_and_y()
	var saved := _sim.to_snapshot()
	_press(_board.end_button("X", 0))
	assert_object(_board.confirm_end_button()).is_not_null()
	assert_bool(_sim.from_snapshot(saved)).is_true()
	assert_object(_board.confirm_end_button()).is_null()
	assert_array(_sim.active_contract_ids()).is_equal(["X", "Y"])
