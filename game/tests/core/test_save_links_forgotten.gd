class_name TestSaveLinksForgotten
extends GdUnitTestSuite
## SaveLinks' flight-id rule after FlightSim stopped rebuilding pruned
## occurrences (flight save version 9): an id whose holder asks FlightSim about
## it as the game runs (a passenger's flight, a pending spawn, a scheduled
## flight) must be live or landed in the saved flights, while ids kept only as
## records (no-shows, flight results, the rating's pending list) may name any
## issued occurrence. A passenger on X-d0 on day 3 was issued but is forgotten:
## after a load it would wait for doors that never close, so it is refused.
##
## Beside test_save_game_links.gd, which checks the same links on a whole-world
## save of main.tscn on day 0. A whole world played to day 3 takes minutes, so
## these cases stage the links SaveLinks reads: a FlightSim's own save, loaded
## as SaveGame stages it (FlightSnapshot.load), and passengers and rating parts
## holding only the ids under test.

## X departs 10:00 and Y 17:00; at 13:00 on day 3 X-d3 and X-d2 are landed,
## Y-d3 is live and X-d0 is long gone.
const AT_MINUTE := 13 * 60

var _flights: Dictionary


func before() -> void:
	var sim := FlightSim.new()
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("Y", 17 * 60))).is_true()
	for t in range(1, GameCalendar.tick_at(3, AT_MINUTE, 0) + 1):
		sim.on_tick(t)
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	_flights = FlightSnapshot.load(data, sim.gate_ids(), 0)
	sim.free()


func _passengers(flight_id: String, where: String) -> Dictionary:
	var parts := {
		"passengers": [],
		"schedule": [],
		"scheduled": {},
		"no_shows": {},
		"flight_results": {},
	}
	match where:
		"passenger":
			var p := Passenger.new()
			p.flight_id = flight_id
			parts["passengers"] = [p]
		"schedule":
			parts["schedule"] = [{"flight": flight_id}]
		"none":
			pass
		_:
			parts[where] = {flight_id: {}}
	return parts


func _problem(flight_id: String, where: String) -> String:
	return SaveLinks._flight_id_problem(_passengers(flight_id, where), {"pending": []}, _flights)


func test_the_staged_flights_hold_what_the_cases_need() -> void:
	assert_bool(_flights.has("error")).is_false()
	var live := []
	for flight: Dictionary in _flights["flights"]:
		live.append(flight["id"])
	var landed := []
	for flight: Dictionary in _flights["landed"]:
		landed.append(flight["id"])
	print("live %s, landed %s" % [live, landed])
	assert_array(live).contains(["Y-d3"])
	assert_array(landed).contains(["X-d2", "X-d3"])
	assert_bool(live.has("X-d0") or landed.has("X-d0")).is_false()
	assert_int(int(_flights["next_day"]["X"])).is_greater(0)


func test_an_active_passenger_on_an_issued_but_forgotten_occurrence_is_refused() -> void:
	for where in ["passenger", "schedule", "scheduled"]:
		var problem := _problem("X-d0", where)
		print("%s on X-d0: '%s'" % [where, problem])
		assert_str(problem).override_failure_message(where).contains(
			"flight X-d0 is named but is neither live nor landed"
		)


func test_a_passenger_on_today_s_or_yesterday_s_occurrence_loads() -> void:
	for id in ["Y-d3", "X-d3", "X-d2"]:
		for where in ["passenger", "schedule", "scheduled"]:
			(
				assert_str(_problem(id, where))
				. override_failure_message("%s %s" % [id, where])
				. is_empty()
			)


## Records only: no-shows, flight results and the rating's pending list may
## keep a forgotten but issued occurrence; one never issued is still refused.
func test_records_may_name_a_forgotten_issued_occurrence() -> void:
	for where in ["no_shows", "flight_results"]:
		assert_str(_problem("X-d0", where)).override_failure_message(where).is_empty()
		assert_str(_problem("X-d99", where)).contains("neither live nor an issued occurrence")
	var empty := _passengers("", "none")
	var pending := {"pending": [{"flight": "X-d0", "tick": 0}]}
	assert_str(SaveLinks._flight_id_problem(empty, pending, _flights)).is_empty()
