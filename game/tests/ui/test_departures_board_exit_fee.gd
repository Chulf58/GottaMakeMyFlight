class_name TestDeparturesBoardExitFee
extends GdUnitTestSuite
## The Exit fee in the shared End prompt/outcome (DeparturesBoard.end_prompt,
## DeparturesBoard.end_outcome; tested on FlightPlanner in
## test_flight_planner_exit_fee.gd) and on the offer cards.

const BIG := {"up": "loyal_airline", "down": "exit_fee", "level": 2}
const ODD := {"up": "loyal_airline", "down": "odd_hours", "level": 1}
const GATES: Array[String] = ["C", "A"]

var _sim: FlightSim
var _ended: Array = []


func before_test() -> void:
	_ended.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()
	_sim.ended_by_player.connect(func(id: String, fee: int) -> void: _ended.append([id, fee]))


func _accept(id: String, minute: int, traits: Dictionary) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["traits"] = traits
	assert_bool(_sim.accept_contract(terms)).is_true()


func test_the_end_prompt_and_outcome_charge_exit_fee_within_term() -> void:
	_accept("X", 600, BIG)
	_accept("Y", 660, {})
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).is_equal("End this contract? Exit fee $120")
	assert_str(DeparturesBoard.end_prompt(_sim, "Y")).is_equal(DeparturesBoard.END_PROMPT)
	assert_str(DeparturesBoard.end_outcome(_sim, "X")).is_equal(
		DeparturesBoard.ENDED_TEXT.format({"destination": "Oslo"})
	)
	assert_str(DeparturesBoard.end_outcome(_sim, "Y")).is_equal(
		DeparturesBoard.ENDED_TEXT.format({"destination": "Oslo"})
	)
	assert_array(_ended).is_equal([["X", 120], ["Y", 0]])


func test_after_the_term_the_confirm_asks_without_a_fee() -> void:
	_accept("X", 600, BIG)
	_sim.tick = GameCalendar.tick_at(_sim.contract_of("X")["first_day"] + 6, 1380, 0)
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).contains("$120")
	_sim.tick = GameCalendar.tick_at(_sim.contract_of("X")["first_day"] + 7, 60, 0)
	assert_str(DeparturesBoard.end_prompt(_sim, "X")).is_equal(DeparturesBoard.END_PROMPT)
	assert_str(DeparturesBoard.end_outcome(_sim, "X")).is_equal(
		DeparturesBoard.ENDED_TEXT.format({"destination": "Oslo"})
	)
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
