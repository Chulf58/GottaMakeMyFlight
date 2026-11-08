class_name TestFlightContracts
extends GdUnitTestSuite
## Accepting a contract: captured read-only terms, the first day whose whole
## preparation window is still ahead, and gate reservations that never overlap.

## Game minutes from an occurrence's first state to its departure (133 with the
## present timetable), and the minutes it holds its gate (195). The cases below
## work out their clock times from these, so a change to the phase lengths moves
## them and not the cases.
var _offset_minutes := _minutes(FlightTimetable.departure_offset())
var _held_minutes := _minutes(FlightTimetable.reserved_ticks())

var _sim: FlightSim
var _added: Array[String] = []


static func _minutes(ticks: int) -> int:
	@warning_ignore("integer_division")
	return ticks / GameCalendar.TICKS_PER_MINUTE


## The minute of the day the bootstrap flight (first state at tick 0, 06:00)
## departs: 08:13.
static func bootstrap_minute() -> int:
	return 6 * 60 + _minutes(FlightTimetable.departure_offset())


func before_test() -> void:
	_added.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.occurrence_added.connect(func(id: String) -> void: _added.append(id))
	# A FlightSim starts closed; these cases are about an open airport.
	_sim.open_airport()


## Offer terms: no gate, since FlightSim gives the contract one on accept.
static func terms(id: String, minute: int) -> Dictionary:
	return {
		"id": id,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": minute,
		"plane_size": "medium",
		"booked_passengers": 40,
		"fee_per_passenger": 25,
	}


## 08:13 is 133 game minutes after 06:00: the bootstrap flight pushes back at
## tick 2660, so a contract at 08:13 accepted at tick 0 is the same flight.
func test_a_contract_at_08_13_accepted_at_start_reproduces_the_bootstrap_flight() -> void:
	assert_bool(_sim.accept_contract(terms("GMF101", bootstrap_minute()))).is_true()
	assert_array(_sim.flight_ids()).is_equal(["GMF101-d0"])
	var expected := FlightSim.schedule_starts(0)
	for state in FlightSim.STATE_COUNT:
		assert_int(_sim.state_start("GMF101-d0", state)).is_equal(expected[state])
	assert_int(_sim.state_of("GMF101-d0")).is_equal(FlightSim.State.SCHEDULED)
	assert_str(_sim.flight_contract_id("GMF101-d0")).is_equal("GMF101")
	assert_int(_sim.contract_of("GMF101")["first_day"]).is_equal(0)
	assert_array(_added).is_equal(["GMF101-d0"])


func test_the_contract_is_a_read_only_copy_of_the_terms() -> void:
	var offer := terms("GMF300", 600)
	assert_bool(_sim.accept_contract(offer)).is_true()
	offer["fee_per_passenger"] = 999
	var contract := _sim.contract_of("GMF300")
	assert_bool(contract.is_read_only()).is_true()
	assert_int(contract["fee_per_passenger"]).is_equal(25)
	assert_str(contract["airline"]).is_equal("Gotta Air")
	assert_int(contract["booked_passengers"]).is_equal(40)
	assert_str(contract["plane_size"]).is_equal("medium")
	assert_array(_sim.contract_ids()).is_equal(["GMF300"])


## 08:20 starts its occurrence at tick 140 (08:20 minus 133 minutes is 06:07).
func test_acceptance_after_todays_preparation_start_goes_to_tomorrow() -> void:
	var start := GameCalendar.tick_at(0, 500) - FlightTimetable.departure_offset()
	assert_int(start).is_equal(140)
	for case in [[start - 1, 0], [start, 0], [start + 1, 1]]:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		sim.on_tick(case[0])
		assert_bool(sim.accept_contract(terms("GMF400", 500))).is_true()
		assert_int(sim.contract_of("GMF400")["first_day"]).is_equal(case[1])
		# Open, so a first_day of 0 is issued at once and a first_day of 1 is not.
		assert_int(sim.flight_ids().size()).is_equal(1 - case[1])
	var late := auto_free(FlightSim.new()) as FlightSim
	late.open_airport()
	late.on_tick(start + 1)
	late.accept_contract(terms("GMF400", 500))
	assert_array(late.flight_ids()).is_empty()
	assert_int(late.state_start("GMF400-d1", FlightSim.State.SCHEDULED)).is_equal(-1)


func test_an_early_morning_contract_accepted_at_start_begins_tomorrow() -> void:
	assert_bool(_sim.accept_contract(terms("GMF500", 420))).is_true()
	assert_int(_sim.contract_of("GMF500")["first_day"]).is_equal(1)
	assert_array(_added).is_empty()


func test_bad_terms_are_refused() -> void:
	var cases: Array[Dictionary] = []
	var missing := terms("GMF600", 600)
	missing.erase("airline")
	cases.append(missing)
	var extra := terms("GMF600", 600)
	extra["first_day"] = 0
	cases.append(extra)
	var changes := [
		["departure_minute", 1440],
		["departure_minute", -1],
		["departure_minute", 600.5],
		["gate", "A"],
		["plane_size", "huge"],
		["fee_per_passenger", -1],
		["booked_passengers", 3.5],
		["id", "GMF-1"],
		["id", ""],
		["airline", ""],
		["destination", 7],
	]
	for change in changes:
		var bad := terms("GMF600", 600)
		bad[change[0]] = change[1]
		cases.append(bad)
	for bad in cases:
		assert_bool(_sim.accept_contract(bad)).override_failure_message(str(bad)).is_false()
	assert_array(_sim.contract_ids()).is_empty()
	assert_array(_added).is_empty()


func test_json_numbers_are_accepted_as_whole_ints() -> void:
	var offer: Dictionary = JSON.parse_string(JSON.stringify(terms("GMF601", 600)))
	assert_bool(_sim.accept_contract(offer)).is_true()
	assert_int(typeof(_sim.contract_of("GMF601")["departure_minute"])).is_equal(TYPE_INT)


func test_a_contract_id_is_used_once() -> void:
	assert_bool(_sim.accept_contract(terms("GMF700", 600))).is_true()
	assert_bool(_sim.accept_contract(terms("GMF700", 900))).is_false()
	assert_array(_sim.contract_ids()).is_equal(["GMF700"])


## 10:00 holds gate C from 07:47 to 11:02 (half-open): a contract whose gate
## time starts a minute before that is refused, one starting on that tick fits.
func test_gate_reservations_are_half_open() -> void:
	assert_bool(_sim.accept_contract(terms("FIRST", 600))).is_true()
	var next := 600 + _held_minutes
	assert_bool(_sim.accept_contract(terms("TIGHT", next - 1))).is_false()
	assert_bool(_sim.accept_contract(terms("NEXT", next))).is_true()
	assert_array(_sim.contract_ids()).is_equal(["FIRST", "NEXT"])


## A departure outside 07:00 to 21:00 would take away the quiet night the taxi
## planner restarts on, so it is refused (decision runway-and-taxi-technical-
## design-movement-plan-analytic-bookings-planned-pauses, section 6).
func test_a_departure_in_the_quiet_night_is_refused() -> void:
	for minute in [0, 419, 1261, 1439]:
		var id := "N%d" % minute
		assert_str(_sim.accept_problem(terms(id, minute))).is_equal(FlightSim.QUIET_NIGHT_TEXT)
		var refusal := _sim.accept_refusal(terms(id, minute))
		assert_str(refusal["reason"]).is_equal(GroundPlanner.QUIET_NIGHT)
	assert_str(_sim.accept_problem(terms("D420", 420))).is_empty()
	assert_str(_sim.accept_problem(terms("D1260", 1260))).is_empty()
	assert_array(_sim.contract_ids()).is_empty()


## The bootstrap flight holds gate C from tick 0 to 3900 (06:00 to 09:15).
func test_a_contract_clashing_with_the_bootstrap_flight_is_refused() -> void:
	assert_bool(_sim.add_default_flight()).is_true()
	assert_bool(_sim.accept_contract(terms("GMF101", bootstrap_minute()))).is_false()
	# 11:27 starts at 09:14, 20 ticks before the bootstrap flight leaves the gate.
	var clash := 6 * 60 + _held_minutes - 1 + _offset_minutes
	assert_int(clash).is_equal(11 * 60 + 27)
	assert_bool(_sim.accept_contract(terms("GMF800", clash))).is_false()
	assert_bool(_sim.accept_contract(terms("GMF800", clash + 1))).is_true()


func test_a_raw_flight_cannot_take_a_contracts_gate_or_id_namespace() -> void:
	assert_bool(_sim.accept_contract(terms("GMF101", bootstrap_minute()))).is_true()
	assert_bool(_sim.add_flight("RAW1", FlightSim.schedule_starts(100))).is_false()
	var free_from := FlightTimetable.reserved_ticks()
	assert_bool(_sim.add_flight("RAW1", FlightSim.schedule_starts(free_from))).is_true()
	# The next day's occurrence starts at tick 28800.
	assert_bool(_sim.add_flight("RAW2", FlightSim.schedule_starts(28000))).is_false()
	assert_bool(_sim.add_flight("AB-d3", FlightSim.schedule_starts(5000))).is_false()
	assert_bool(_sim.add_flight("RAW3", FlightSim.schedule_starts(5000), "A")).is_false()
	assert_array(_sim.flight_ids()).is_equal(["GMF101-d0", "RAW1"])
