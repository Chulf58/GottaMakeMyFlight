class_name TestFlightResultTitle
extends GdUnitTestSuite
## The flight result card's heading names a contract flight by its airline and
## destination ("Sunhop Lisbon result"), not its internal offer id ("O0N3
## result"); a one-off flight such as the starter keeps its flight number
## (smoke playtest 7 friction).

var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(10, 10)
	_port.add_child(mode)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.build_mode = mode
	_port.add_child(_hud)


func after_test() -> void:
	_port.free()
	_world.free_all()


func _contract_terms(id: String, airline: String, destination: String) -> Dictionary:
	var terms := TestFlightContracts.terms(id, 900)
	terms["airline"] = airline
	terms["destination"] = destination
	return terms


func test_a_contract_flight_is_titled_with_its_airline_and_destination() -> void:
	var terms := _contract_terms("O0N3", "Sunhop", "Lisbon")
	assert_bool(_world.flights.open_airport()).is_true()
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	var id := FlightTimetable.occurrence_id("O0N3", _world.flights.start_days["O0N3"])
	assert_str(FlightResultPanel.title_for(_world.flights, id)).is_equal("Sunhop Lisbon")
	_hud.show_result_for(id)
	assert_str(_hud.result_text().split("\n")[0]).is_equal("Sunhop Lisbon result")
	assert_str(_hud.result_text()).not_contains("O0N3")


func test_a_one_off_flight_keeps_its_flight_number_as_the_title() -> void:
	var title := FlightResultPanel.title_for(_world.flights, PassengerTestWorld.FLIGHT)
	assert_str(title).is_equal(PassengerTestWorld.FLIGHT)
	_hud.show_result_for(PassengerTestWorld.FLIGHT)
	assert_str(_hud.result_text().split("\n")[0]).is_equal("GMF101 result")


func test_an_occurrence_of_an_unknown_contract_falls_back_to_its_contract_id() -> void:
	assert_str(FlightResultPanel.title_for(_world.flights, "O9N9-d2")).is_equal("O9N9")
	assert_str(FlightResultPanel.title_for(null, "O9N9-d2")).is_equal("O9N9")


func test_a_summary_title_replaces_the_flight_number_in_the_heading() -> void:
	var summary := {
		"flight": "O0N3-d0", "title": "Sunhop Lisbon", "made": 1, "missed": 0, "reasons": []
	}
	assert_str(FlightResultPanel.text_for(summary).split("\n")[0]).is_equal("Sunhop Lisbon result")
