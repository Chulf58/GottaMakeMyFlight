class_name TestFlightPlannerExitFee
extends GdUnitTestSuite
## The flight planner's End confirm asks the Departures question
## (DeparturesBoard.end_prompt; decision odd-hours-and-exit-fee-offer-traits-
## odd-hours-widens-the-dep): "End this contract? Exit fee $120" for a big Exit
## fee contract within its term, END_PROMPT for a plain one, and ending it there
## reports the fee to Settlement through ended_by_player.

const GATES: Array[String] = ["C", "A", "B"]
const BIG := {"up": "loyal_airline", "down": "exit_fee", "level": 2}

var _sim: FlightSim
var _planner: FlightPlanner
var _ended: Array = []


func before_test() -> void:
	_ended.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.ended_by_player.connect(func(id: String, fee: int) -> void: _ended.append([id, fee]))
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = auto_free(SimClock.new()) as SimClock
	add_child(_planner)


func after_test() -> void:
	_planner.free()


func _accept(id: String, minute: int, traits: Dictionary) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["traits"] = traits
	assert_bool(_sim.accept_contract(terms)).is_true()


func _press(button: Button) -> void:
	assert_object(button).is_not_null()
	button.pressed.emit()


## Selects `id`'s bar, presses End and returns the confirm's question.
func _confirm_text(id: String) -> String:
	_press(_planner.bar_button(id, 0))
	_press(_planner.part("EndContract") as Button)
	var prompt := _planner.part("EndPrompt") as Label
	assert_object(prompt).is_not_null()
	return prompt.text if prompt != null else ""


func test_the_end_confirm_shows_the_exit_fee_and_a_plain_contract_asks_plainly() -> void:
	_accept("X", 600, BIG)
	_accept("Y", 660, {})
	_planner.open()
	var fee_text := _confirm_text("X")
	print("planner confirm for X: ", fee_text)
	assert_str(fee_text).is_equal("End this contract? Exit fee $120")
	_press(_planner.part("ConfirmEnd") as Button)
	assert_array(_ended).is_equal([["X", 120]])
	var plain_text := _confirm_text("Y")
	print("planner confirm for Y: ", plain_text)
	assert_str(plain_text).is_equal(DeparturesBoard.END_PROMPT)
	_press(_planner.part("ConfirmEnd") as Button)
	assert_array(_ended).is_equal([["X", 120], ["Y", 0]])
