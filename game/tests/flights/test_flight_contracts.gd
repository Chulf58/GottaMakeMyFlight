class_name TestFlightContracts
extends GdUnitTestSuite
## Accepting a contract: captured read-only terms, the first day whose whole
## preparation window is still ahead, and gate reservations that never overlap.

var _sim: FlightSim
var _added: Array[String] = []


func before_test() -> void:
	_added.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.occurrence_added.connect(func(id: String) -> void: _added.append(id))
	# A FlightSim starts closed; these cases are about an open airport.
	_sim.open_airport()


static func terms(id: String, minute: int, gate := "C") -> Dictionary:
	return {
		"id": id,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": minute,
		"gate": gate,
		"plane_size": "medium",
		"booked_passengers": 40,
		"fee_per_passenger": 25,
	}


## 07:38 is 98 game minutes after 06:00: the bootstrap flight pushes back at
## tick 1960, so a contract at 07:38 accepted at tick 0 is the same flight.
func test_a_contract_at_07_38_accepted_at_start_reproduces_the_bootstrap_flight() -> void:
	assert_bool(_sim.accept_contract(terms("GMF101", 458))).is_true()
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


## 08:00 starts its occurrence at tick 440 (08:00 minus 98 minutes is 06:22).
func test_acceptance_after_todays_preparation_start_goes_to_tomorrow() -> void:
	for case in [[439, 0], [440, 0], [441, 1]]:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		sim.on_tick(case[0])
		assert_bool(sim.accept_contract(terms("GMF400", 480))).is_true()
		assert_int(sim.contract_of("GMF400")["first_day"]).is_equal(case[1])
		# Open, so a first_day of 0 is issued at once and a first_day of 1 is not.
		assert_int(sim.flight_ids().size()).is_equal(1 - case[1])
	var late := auto_free(FlightSim.new()) as FlightSim
	late.open_airport()
	late.on_tick(441)
	late.accept_contract(terms("GMF400", 480))
	assert_array(late.flight_ids()).is_empty()
	assert_int(late.state_start("GMF400-d1", FlightSim.State.SCHEDULED)).is_equal(-1)


func test_an_early_morning_contract_accepted_at_start_begins_tomorrow() -> void:
	assert_bool(_sim.accept_contract(terms("GMF500", 390))).is_true()
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


## 23:50 holds gate C from 22:12 to 00:21 the next day (half-open).
func test_gate_reservations_clash_across_midnight() -> void:
	assert_bool(_sim.accept_contract(terms("LATE", 1430))).is_true()
	# 00:30 would start at 22:52 the day before.
	assert_bool(_sim.accept_contract(terms("EARLY", 30))).is_false()
	# 01:58 starts at 00:20, one minute before LATE leaves the gate.
	assert_bool(_sim.accept_contract(terms("TIGHT", 118))).is_false()
	# 01:59 starts at 00:21, the tick LATE's reservation ends.
	assert_bool(_sim.accept_contract(terms("NEXT", 119))).is_true()
	assert_array(_sim.contract_ids()).is_equal(["LATE", "NEXT"])


## 00:10 starts at 22:32 the evening before; 22:40 holds the gate until 23:11.
func test_an_evening_contract_clashes_with_the_next_mornings_early_start() -> void:
	assert_bool(_sim.accept_contract(terms("DAWN", 10))).is_true()
	assert_bool(_sim.accept_contract(terms("DUSK", 1360))).is_false()
	# 22:00 holds the gate until 22:31, the minute before DAWN starts.
	assert_bool(_sim.accept_contract(terms("DUSK", 1320))).is_true()


## The bootstrap flight holds gate C from tick 0 to 2580 (06:00 to 08:09).
func test_a_contract_clashing_with_the_bootstrap_flight_is_refused() -> void:
	assert_bool(_sim.add_default_flight()).is_true()
	assert_bool(_sim.accept_contract(terms("GMF101", 458))).is_false()
	# 09:46 starts at 08:08, 20 ticks before the bootstrap flight departs.
	assert_bool(_sim.accept_contract(terms("GMF800", 586))).is_false()
	assert_bool(_sim.accept_contract(terms("GMF800", 587))).is_true()


func test_a_raw_flight_cannot_take_a_contracts_gate_or_id_namespace() -> void:
	assert_bool(_sim.accept_contract(terms("GMF101", 458))).is_true()
	assert_bool(_sim.add_flight("RAW1", FlightSim.schedule_starts(100))).is_false()
	assert_bool(_sim.add_flight("RAW1", FlightSim.schedule_starts(2580))).is_true()
	# The next day's occurrence starts at tick 28800.
	assert_bool(_sim.add_flight("RAW2", FlightSim.schedule_starts(28000))).is_false()
	assert_bool(_sim.add_flight("AB-d3", FlightSim.schedule_starts(5000))).is_false()
	assert_bool(_sim.add_flight("RAW3", FlightSim.schedule_starts(5000), "A")).is_false()
	assert_array(_sim.flight_ids()).is_equal(["GMF101-d0", "RAW1"])
