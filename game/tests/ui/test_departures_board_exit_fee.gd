class_name TestDeparturesBoardExitFee
extends GdUnitTestSuite
## The Exit fee in the End confirm and on the offer card (decision odd-hours-and-
## exit-fee-offer-traits-odd-hours-widens-the-dep): an Exit fee contract within
## its term asks "End this contract? Exit fee $120" (DeparturesBoard.end_prompt,
## which the flight planner's confirm can share), any other asks END_PROMPT, and
## confirming ends the contract as the player, so ended_by_player carries the
## fee. The offer cards show "Exit fee $120" and "Odd hours" with its 06:00
## departure. Settings go to a per-run file (anti-pattern 1639342a).
##
## Tick 0 is 06:00 on day 0.

const BIG := {"up": "loyal_airline", "down": "exit_fee", "level": 2}
const ODD := {"up": "loyal_airline", "down": "odd_hours", "level": 1}
const GATES: Array[String] = ["C", "A"]

var _sim: FlightSim
var _board: DeparturesBoard
var _ended: Array = []


func before_test() -> void:
	_ended.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()
	_sim.ended_by_player.connect(func(id: String, fee: int) -> void: _ended.append([id, fee]))


func after_test() -> void:
	if _board == null:
		return
	var path := _board.settings_path
	_board.free()
	_board = null
	DirAccess.remove_absolute(path)


## The board in the tree, on a per-run settings file.
func _add_board() -> void:
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_exit_fee")
	_board.flights = _sim
	_board.clock = auto_free(SimClock.new()) as SimClock
	add_child(_board)
	_board.refresh()


func _accept(id: String, minute: int, traits: Dictionary) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["traits"] = traits
	assert_bool(_sim.accept_contract(terms)).is_true()


func _prompt() -> String:
	var confirm := _board.find_child("EndConfirm", true, false)
	assert_object(confirm).is_not_null()
	return (confirm.get_node("EndPrompt") as Label).text


func test_the_end_confirm_shows_the_exit_fee_and_ending_charges_it() -> void:
	_accept("X", 600, BIG)
	_accept("Y", 660, {})
	_add_board()
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).is_equal("End this contract? Exit fee $120")
	assert_str(DeparturesBoard.end_prompt(_sim, "Y")).is_equal(DeparturesBoard.END_PROMPT)
	_board.end_button("X", 0).pressed.emit()
	print("confirm for X: ", _prompt())
	assert_str(_prompt()).is_equal("End this contract? Exit fee $120")
	_board.confirm_end_button().pressed.emit()
	assert_array(_sim.active_contract_ids()).is_equal(["Y"])
	_board.end_button("Y", 0).pressed.emit()
	assert_str(_prompt()).is_equal(DeparturesBoard.END_PROMPT)
	_board.confirm_end_button().pressed.emit()
	assert_array(_ended).is_equal([["X", 120], ["Y", 0]])


func test_after_the_term_the_confirm_asks_without_a_fee() -> void:
	_accept("X", 600, BIG)
	_sim.tick = GameCalendar.tick_at(_sim.contract_of("X")["first_day"] + 6, 1380)
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).contains("$120")
	_sim.tick = GameCalendar.tick_at(_sim.contract_of("X")["first_day"] + 7, 60)
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).is_equal(DeparturesBoard.END_PROMPT)
	assert_str(DeparturesBoard.end_outcome(_sim, "X")).is_equal(DeparturesBoard.ENDED_TEXT % "Oslo")
	assert_array(_ended).is_equal([["X", 0]])


func test_the_offer_cards_show_the_exit_fee_and_odd_hours() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)
	var desk := OfferDesk.new()
	desk.runway = Runway.new(PlaneClasses.LARGE)
	port.add_child(desk)
	var records := TestOfferBoard.day_records(0, [360, 720, 1320])
	records[0]["traits"] = ODD
	records[1]["traits"] = BIG
	records[2]["traits"] = ODD
	assert_bool(desk.board.from_snapshot(TestOfferBoard.save_of(records))).is_true()
	var panel := OfferPanel.new()
	panel.desk = desk
	panel.flights = _sim
	port.add_child(panel)
	panel.open()
	var odd_text := panel.card_text("O0N1")
	var fee_text := panel.card_text("O0N2")
	print("odd hours card:\n%s\nexit fee card:\n%s" % [odd_text, fee_text])
	assert_str((panel.trait_row("O0N1").get_node("Down") as Label).text).is_equal("Odd hours")
	assert_str(odd_text).contains("06:00")
	assert_str(panel.card_text("O0N3")).contains("22:00")
	var fee_label := panel.trait_row("O0N2").get_node("Down") as Label
	assert_str(fee_label.text).is_equal("Exit fee $120")
	assert_str(fee_label.tooltip_text).contains("7 days")
	assert_str(fee_label.theme_type_variation).is_equal("HudProblemText")
	port.free()
