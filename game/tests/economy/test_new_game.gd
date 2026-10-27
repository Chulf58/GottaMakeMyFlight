class_name TestNewGame
extends GdUnitTestSuite
## A new game on the real main scene (Economy 7/8, decision airport-opening-
## design-stays-open-once-opened-starter-flight-placed-after-opening): the
## wallet holds the starting budget, and the airport starts closed with no
## contract and no flight, the HUD saying so. Once it has the starter terminal
## and staff on duty it opens on the next tick and accepts the starter
## contract, whose first flight starts ISSUE_LEAD_TICKS after the opening and
## books the starter's passengers. One boot of main.tscn for the file;
## before() records what each case reads.

const MAIN := "res://main/main.tscn"

var _main: Node
var _boot := {}
var _opened := {}


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	var clock: SimClock = _main.get_node("SimClock")
	clock.set_paused(true)
	var flights: FlightSim = _main.get_node("FlightSim")
	var hud: PassengerHud = _main.get_node("PassengerHud")
	var panel: StaffPanel = _main.get_node("StaffPanel")
	_boot = {
		"contracts": flights.contract_ids(),
		"flights": flights.flight_ids(),
		"opened_tick": flights.opened_tick,
		"departures": (hud.find_child("Departures", true, false) as Label).text,
		"clock": (hud.find_child("Clock", true, false) as Label).text,
		"hint": panel.hint_label().text,
	}
	_open(clock, flights, hud, panel)
	_opened["panel_texts"] = _panel_texts(hud)
	_opened["clock"] = (hud.find_child("Clock", true, false) as Label).text


static func _panel_texts(hud: PassengerHud) -> PackedStringArray:
	hud.refresh()
	var texts := PackedStringArray()
	for label in (hud.find_child("FlightPanel", true, false) as Control).find_children(
		"*", "Label", true, false
	):
		texts.append((label as Label).text)
	return texts


func after() -> void:
	_main.free()


## Builds the starter terminal, seats staff at every station and steps to the
## starter's first issue.
func _open(clock: SimClock, flights: FlightSim, hud: PassengerHud, panel: StaffPanel) -> void:
	hud.press_starter_terminal()
	_opened["hint_built"] = panel.hint_label().text
	StaffTestKit.staff_all(_main.get_node("Staff"))
	clock.set_paused(false)
	clock.advance(SimClock.STEP)
	_opened["opened_tick"] = flights.opened_tick
	_opened["contracts"] = flights.contract_ids()
	_opened["hint_open"] = panel.hint_label().text
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	_opened["flights_before_issue"] = flights.flight_ids()
	while not flights.flight_ids().has(first) and clock.tick < 100:
		clock.advance(SimClock.STEP)
	clock.set_paused(true)
	_opened["issued_at"] = clock.tick
	_opened["flights"] = flights.flight_ids()
	_opened["first_start"] = flights.state_start(first, FlightSim.State.SCHEDULED)
	_opened["pushback"] = flights.state_start(first, FlightSim.State.PUSHBACK)
	_opened["departures"] = DepartureList.text(flights, clock.tick)
	_opened["pending"] = (_main.get_node("PassengerSim") as PassengerSim).pending_spawns()


func test_the_wallet_holds_the_starting_budget() -> void:
	var finances: Finances = _main.get_node("Finances")
	var menu: BuildMenu = _main.get_node("BuildMenu")
	assert_int(finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)
	assert_str(menu.money_label().text).is_equal("Money  %d" % PriceTable.STARTING_BUDGET)


func test_a_new_game_is_closed_with_no_contract_and_no_flight() -> void:
	assert_int(_boot["opened_tick"]).is_equal(-1)
	assert_array(_boot["contracts"]).is_empty()
	assert_array(_boot["flights"]).is_empty()
	assert_str(_boot["departures"]).is_equal(DepartureList.EMPTY_TEXT)
	assert_str(_boot["clock"]).is_equal("Day 1  06:00")


## The empty grid has no path; with the starter terminal the blocker is the
## missing check-in agent.
func test_the_staff_hint_names_what_keeps_the_airport_closed() -> void:
	assert_str(_boot["hint"]).is_equal(StaffPanel.CLOSED_HINTS[AirportGate.Blocker.NO_PATH])
	assert_str(_opened["hint_built"]).is_equal(
		(
			"Airport closed: no check-in agent at a desk\n"
			+ "Hire a check-in agent\nHire a security officer"
		)
	)
	assert_str(_opened["hint_open"]).is_equal("")


## Opened at tick 1, the starter's first state is at 2420 (the lead, rounded
## up to a whole minute), issued at 20, departing 09:39 on day one.
func test_staffed_it_opens_on_the_next_tick_with_the_starter_contract() -> void:
	assert_int(_opened["opened_tick"]).is_equal(1)
	assert_array(_opened["contracts"]).is_equal([FlightSim.DEFAULT_ID])
	assert_array(_opened["flights_before_issue"]).is_empty()
	assert_int(_opened["issued_at"]).is_equal(20)
	assert_array(_opened["flights"]).is_equal(
		[FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)]
	)
	assert_int(_opened["first_start"]).is_equal(20 + FlightTimetable.ISSUE_LEAD_TICKS)
	assert_int(GameCalendar.day_of(_opened["pushback"])).is_equal(0)
	assert_str(_opened["departures"]).starts_with("09:39  Oslo  Gotta Air  doors close in ")


## The clock and the timetable replace the elapsed time and the one-flight row.
func test_the_flight_panel_shows_the_clock_and_no_flight_id() -> void:
	var texts: PackedStringArray = _opened["panel_texts"]
	assert_array(texts).contains([_opened["clock"], _opened["departures"]])
	for text in texts:
		assert_str(text).not_contains("Time ")
		assert_str(text).not_contains("Scheduled")
		assert_str(text).not_contains("GMF101-d0")


func test_the_starter_flight_books_the_starter_contract_s_passengers() -> void:
	assert_int(FlightSim.STARTER_TERMS["booked_passengers"]).is_not_equal(
		PassengerSim.DEFAULT_PASSENGERS
	)
	assert_int(_opened["pending"]).is_equal(FlightSim.STARTER_TERMS["booked_passengers"])
