class_name TestNewGame
extends GdUnitTestSuite
## A new game on the real main scene (Economy 7/8): the wallet holds the
## starting budget, the timetable holds the one starter contract, day one has
## a flight, and the HUD shows both. One boot of main.tscn for the file.

const MAIN := "res://main/main.tscn"

var _main: Node


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)


func after() -> void:
	_main.free()


func test_the_wallet_holds_the_starting_budget() -> void:
	var finances: Finances = _main.get_node("Finances")
	assert_int(finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)


func test_the_timetable_holds_one_starter_contract_and_no_one_off_flight() -> void:
	var flights: FlightSim = _main.get_node("FlightSim")
	assert_array(flights.contract_ids()).is_equal([FlightSim.STARTER_TERMS["id"]])
	assert_array(flights.flight_ids()).is_equal(
		[FlightTimetable.occurrence_id(FlightSim.STARTER_TERMS["id"], 0)]
	)
	assert_str(flights.flight_contract_id(flights.flight_ids()[0])).is_equal(
		FlightSim.STARTER_TERMS["id"]
	)


func test_day_one_has_a_flight_that_departs_that_day() -> void:
	var flights: FlightSim = _main.get_node("FlightSim")
	var id := flights.flight_ids()[0]
	var pushback := flights.state_start(id, FlightSim.State.PUSHBACK)
	assert_int(GameCalendar.day_of(pushback)).is_equal(GameCalendar.day_of(0))


func test_the_hud_shows_the_budget_and_the_day_one_departure() -> void:
	var menu: BuildMenu = _main.get_node("BuildMenu")
	var hud: PassengerHud = _main.get_node("PassengerHud")
	assert_str(menu.money_label().text).is_equal("Money  %d" % PriceTable.STARTING_BUDGET)
	var panel := hud.find_child("Departures", true, false) as Label
	assert_str(panel.text).is_equal("07:38  Oslo  Gotta Air  doors close in 1:35")
	# The clock and the timetable replace the elapsed time and the one-flight row.
	var panel_texts := PackedStringArray()
	for label in (hud.find_child("FlightPanel", true, false) as Control).find_children(
		"*", "Label", true, false
	):
		panel_texts.append((label as Label).text)
	var clock_label := hud.find_child("Clock", true, false) as Label
	assert_str(clock_label.text).is_equal("Day 1  06:00")
	assert_array(panel_texts).contains([clock_label.text])
	for text in panel_texts:
		assert_str(text).not_contains("Time ")
		assert_str(text).not_contains("Scheduled")
		assert_str(text).not_contains("GMF101-d0")


func test_day_one_books_the_starter_contract_s_passengers_not_the_default() -> void:
	var sim: PassengerSim = _main.get_node("PassengerSim")
	assert_int(FlightSim.STARTER_TERMS["booked_passengers"]).is_not_equal(
		PassengerSim.DEFAULT_PASSENGERS
	)
	assert_int(sim.pending_spawns()).is_equal(FlightSim.STARTER_TERMS["booked_passengers"])
