class_name TestSaveLinksIncidents
extends GdUnitTestSuite
## SaveLinks' rule for the flights an incident plan names (board
## incident-plan-flight-ids-are-not-linked-against-the-saved-fl). A VIP offered
## or accepted and a rush announced ask FlightSim about their flights as the
## game runs, so each flight must be live, landed or not yet issued (a VIP or
## rush can name a day ahead). X-d0 was issued on day 0 but is forgotten by
## day 3: a VIP waiting on it would wait forever.
##
## Same staging as test_save_links_forgotten.gd: a FlightSim played to 13:00 on
## day 3, saved and loaded as SaveGame stages it (FlightSnapshot.load), and an
## incidents part built through IncidentSnapshot.load, so the plans are the
## real loaded shape. At that moment X-d3 and X-d2 are landed, Y-d3 is live,
## X-d0 is gone, X's next day is after today, and Z, accepted on day 2, has
## never issued days 0 and 1. A whole-world case on main.tscn is in
## test_save_game_incident_links.gd.

const AT_MINUTE := 13 * 60
const DEPARTS := 1000

var _flights: Dictionary


func before() -> void:
	var sim := FlightSim.new()
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("Y", 17 * 60))).is_true()
	var z_tick := GameCalendar.tick_at(2, 60, 0)
	for t in range(1, GameCalendar.tick_at(3, AT_MINUTE, 0) + 1):
		sim.on_tick(t)
		if t == z_tick:
			assert_bool(sim.accept_contract(TestFlightContracts.terms("Z", 21 * 60))).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	_flights = FlightSnapshot.load(data, sim.gate_ids(), 0)
	sim.free()


func _next(contract: String) -> int:
	return int(_flights["next_day"][contract])


func _vip(flight: String, state: String) -> Dictionary:
	return {
		"id": 1,
		"kind": IncidentCatalogue.VIP,
		"state": state,
		"plan":
		{
			"flight": flight,
			"departs": DEPARTS,
			"bonus": 100,
			"target": 0,
			"good_mood": 50,
			"miss_half_stars": 1,
		},
	}


func _rush(flights: Array[String], state: String) -> Dictionary:
	var named: Array[Dictionary] = []
	for id in flights:
		named.append({"flight": id, "extra": 5, "departs": DEPARTS})
	return {
		"id": 2,
		"kind": IncidentCatalogue.RUSH,
		"state": state,
		"plan": {"flights": named, "total": 5 * flights.size(), "until": DEPARTS + 500},
	}


## The incidents part as SaveGame stages it (IncidentSnapshot.load) holding
## `records` ({id, kind, state, plan}); the rest of each record is a major's
## plain fields.
func _part(records: Array[Dictionary]) -> Dictionary:
	var incidents: Array[Dictionary] = []
	for record in records:
		(
			incidents
			. append(
				{
					"id": record["id"],
					"kind": record["kind"],
					"roll_day": 3,
					"state": record["state"],
					"fire_tick": 0,
					"cell": [-1, -1],
					"mess_id": 0,
					"place": "",
					"outcome": "",
					"shown": false,
					"plan": record["plan"],
				}
			)
		)
	var data := {
		"save_version": IncidentSnapshot.SAVE_VERSION,
		"enabled": true,
		"last_rolled_day": 3,
		"next_major_day": 5,
		"next_id": 9,
		"incidents": incidents,
	}
	var loaded := IncidentSnapshot.load(JSON.parse_string(JSON.stringify(data)))
	assert_bool(loaded.has("error")).override_failure_message(str(loaded.get("error"))).is_false()
	return loaded


func _problem(record: Dictionary) -> String:
	return SaveLinks._incident_problem(_part([record]), _flights)


func test_the_staged_flights_hold_what_the_cases_need() -> void:
	assert_bool(_flights.has("error")).is_false()
	var known := []
	for list: String in ["flights", "landed"]:
		for flight: Dictionary in _flights[list]:
			known.append(flight["id"])
	print("live and landed %s, X next day %d" % [known, _next("X")])
	assert_array(known).contains(["Y-d3", "X-d3", "X-d2"])
	assert_bool(known.has("X-d0")).is_false()
	assert_int(_next("X")).is_greater(3)
	assert_int(int(_flights["start_day"]["Z"])).is_greater(1)


func test_a_vip_on_a_forgotten_occurrence_is_refused() -> void:
	for state in [IncidentCatalogue.OFFERED, IncidentCatalogue.ACCEPTED]:
		var problem := _problem(_vip("X-d0", state))
		print("%s VIP on X-d0: '%s'" % [state, problem])
		assert_str(problem).override_failure_message(state).contains(
			"incident 1 names flight X-d0, neither live, landed nor to come"
		)


func test_a_rush_naming_a_forgotten_occurrence_is_refused() -> void:
	var problem := _problem(_rush(["Y-d3", "X-d0"], IncidentCatalogue.ANNOUNCED))
	print("rush on X-d0: '%s'" % problem)
	assert_str(problem).contains("incident 2 names flight X-d0, neither live, landed nor to come")


func test_a_vip_or_rush_on_a_live_landed_or_future_flight_loads() -> void:
	var next_issued := "X-d%d" % _next("X")
	var future := "X-d%d" % (_next("X") + 2)
	for id in ["Y-d3", "X-d3", "X-d2", next_issued, future]:
		for state in [IncidentCatalogue.OFFERED, IncidentCatalogue.ACCEPTED]:
			assert_str(_problem(_vip(id, state))).override_failure_message(id).is_empty()
		var rush := _rush([id], IncidentCatalogue.ANNOUNCED)
		assert_str(_problem(rush)).override_failure_message("rush %s" % id).is_empty()


## A past day of a saved contract that was never issued (before its start day),
## a contract the save lacks and an id that is no occurrence are all refused.
func test_a_never_issued_past_day_and_a_strange_id_are_refused() -> void:
	var before_start := "Z-d%d" % (int(_flights["start_day"]["Z"]) - 1)
	for id in [before_start, "Q-d9", "nonsense"]:
		var problem := _problem(_vip(id, IncidentCatalogue.ACCEPTED))
		assert_str(problem).override_failure_message(id).contains("names flight %s" % id)
	assert_str(_problem(_vip("Z-d%d" % _next("Z"), IncidentCatalogue.ACCEPTED))).is_empty()


## Only incidents that still ask about their flights are checked: a done VIP,
## a declined one and a done rush may name flights long gone.
func test_a_finished_incident_may_name_a_forgotten_flight() -> void:
	for state in [IncidentCatalogue.DONE, IncidentCatalogue.DECLINED]:
		assert_str(_problem(_vip("X-d0", state))).override_failure_message(state).is_empty()
	assert_str(_problem(_rush(["X-d0"], IncidentCatalogue.DONE))).is_empty()
	assert_str(SaveLinks._incident_problem(_part([]), _flights)).is_empty()
