class_name TestFlightEndContract
extends GdUnitTestSuite
## FlightSim.end_contract (decision low-rating-ends-one-airline-contract-per-
## low-day): an ended contract keeps its record and the occurrences already
## issued still fly, but no later day is issued and the gate is free for a new
## contract. The end is saved (save version 4) and a load equals an
## uninterrupted run.
##
## AM (08:00) has its first state at 440 + 28800 * day and is issued 2400 ticks
## before it; PM (14:00) at 7640 + 28800 * day.

const DAY := 28800
## AM-d0 and AM-d1 are issued here (d1 at 26840), AM-d2 is not (at 56840).
const ENDED_AT := 26900

var _log: Array[String] = []
var _ended_ids: Array[String] = []


func before_test() -> void:
	_log.clear()
	_ended_ids.clear()


func _world() -> Array:
	var clock := auto_free(SimClock.new()) as SimClock
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.bind_clock(clock)
	sim.occurrence_added.connect(
		func(id: String) -> void: _log.append("%d add %s" % [clock.tick, id])
	)
	sim.state_changed.connect(
		func(id: String, state: int) -> void: _log.append("%d %s %d" % [clock.tick, id, state])
	)
	sim.contract_ended.connect(func(id: String) -> void: _ended_ids.append(id))
	sim.open_airport()
	return [clock, sim]


func _run(clock: SimClock, target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


## AM and PM accepted, run to ENDED_AT, AM ended.
func _ended_world() -> Array:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("PM", 840))).is_true()
	_run(world[0], ENDED_AT)
	assert_bool(sim.end_contract("AM")).is_true()
	return world


func _saved(world: Array) -> Dictionary:
	return JSON.parse_string(JSON.stringify(world[1].to_snapshot()))


func test_an_ended_contract_issues_no_later_day_but_issued_flights_still_fly() -> void:
	var world := _ended_world()
	var sim: FlightSim = world[1]
	assert_array(sim.flight_ids()).contains(["AM-d1"])
	_run(world[0], 3 * DAY)
	var added := _log.filter(func(line: String) -> bool: return " add " in line)
	assert_array(added.filter(func(line: String) -> bool: return "AM-d2" in line)).is_empty()
	assert_array(added.filter(func(line: String) -> bool: return "PM-d2" in line)).is_not_empty()
	assert_array(_log).contains(["%d AM-d1 %d" % [DAY + 440 + 100, FlightSim.State.APPROACH]])
	assert_int(sim.state_of("AM-d1")).is_equal(FlightSim.State.DEPARTED)


func test_the_contract_stays_on_record_and_reports_its_end_day() -> void:
	var sim: FlightSim = _ended_world()[1]
	assert_array(sim.contract_ids()).is_equal(["AM", "PM"])
	assert_str(sim.contract_of("AM")["airline"]).is_equal("Gotta Air")
	assert_array(sim.active_contract_ids()).is_equal(["PM"])
	assert_int(sim.contract_end_day("AM")).is_equal(2)
	assert_int(sim.contract_end_day("PM")).is_equal(-1)
	assert_array(_ended_ids).is_equal(["AM"])


func test_ending_an_unknown_ended_or_closed_contract_is_refused() -> void:
	var world := _ended_world()
	var sim: FlightSim = world[1]
	await (
		assert_error(func() -> void: sim.end_contract("NOPE"))
		. is_push_error("FlightSim.end_contract: no contract 'NOPE'")
	)
	await (
		assert_error(func() -> void: sim.end_contract("AM"))
		. is_push_error("FlightSim.end_contract: contract 'AM' already ended")
	)
	var closed := auto_free(FlightSim.new()) as FlightSim
	closed.accept_contract(TestFlightContracts.terms("AM", 480))
	await (
		assert_error(func() -> void: closed.end_contract("AM"))
		. is_push_error("FlightSim.end_contract: the airport is closed")
	)
	assert_array(_ended_ids).is_equal(["AM"])


## NEW at AM's time would fly on day 1, the day of AM's last issued
## occurrence, so it waits until AM-d1 has gone; AM itself never blocks it.
func test_an_ended_contracts_gate_time_is_free_for_a_new_contract() -> void:
	var world := _world()
	var sim: FlightSim = world[1]
	sim.accept_contract(TestFlightContracts.terms("AM", 480))
	_run(world[0], ENDED_AT)
	var same_time := TestFlightContracts.terms("NEW", 480)
	assert_str(sim.accept_problem(same_time)).contains("clashes with AM")
	sim.end_contract("AM")
	assert_str(sim.accept_problem(same_time)).contains("clashes with flight AM-d1")
	_run(world[0], 40000)
	assert_array(sim.flight_ids()).is_empty()
	assert_str(sim.accept_problem(same_time)).is_empty()
	assert_bool(sim.accept_contract(same_time)).is_true()
	_run(world[0], 3 * DAY)
	assert_array(_log.filter(func(l: String) -> bool: return "add NEW-d2" in l)).is_not_empty()


func test_an_ended_save_round_trips_and_continues_like_the_original() -> void:
	var world := _ended_world()
	_run(world[0], 40000)
	assert_bool(world[1].accept_contract(TestFlightContracts.terms("NEW", 480))).is_true()
	var data := _saved(world)
	assert_int(int(data["save_version"])).is_equal(FlightSim.SAVE_VERSION)
	assert_int(int(data["ended"]["AM"])).is_equal(2)
	assert_int(data["ended"].size()).is_equal(1)
	var clone := _world()
	clone[0].from_snapshot(world[0].to_snapshot())
	assert_bool(clone[1].from_snapshot(data)).is_true()
	assert_str(JSON.stringify(clone[1].to_snapshot())).is_equal(
		JSON.stringify(world[1].to_snapshot())
	)
	assert_int(clone[1].contract_end_day("AM")).is_equal(2)
	_log.clear()
	_run(world[0], 4 * DAY)
	var original_log := _log.duplicate()
	_log.clear()
	_run(clone[0], 4 * DAY)
	assert_array(_log).is_equal(original_log)
	assert_array(_log).is_not_empty()
	assert_str(JSON.stringify(clone[1].to_snapshot())).is_equal(
		JSON.stringify(world[1].to_snapshot())
	)


func test_a_save_without_an_end_has_an_empty_ended_map_and_a_version_3_save_loads() -> void:
	var world := _world()
	world[1].accept_contract(TestFlightContracts.terms("AM", 480))
	_run(world[0], ENDED_AT)
	var data := _saved(world)
	assert_dict(data["ended"]).is_empty()
	var v3 := data.duplicate(true)
	v3["save_version"] = 3
	v3.erase("ended")
	var loaded := auto_free(FlightSim.new()) as FlightSim
	assert_bool(loaded.from_snapshot(v3)).is_true()
	assert_array(loaded.active_contract_ids()).is_equal(["AM"])
	assert_int(int(loaded.to_snapshot()["save_version"])).is_equal(FlightSim.SAVE_VERSION)


func test_an_impossible_ended_state_is_refused_whole() -> void:
	var good := _saved(_ended_world())
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(good)).is_true()
	var v3_with_ended := good.duplicate(true)
	v3_with_ended["save_version"] = 3
	var edits := [
		func(d: Dictionary) -> void: d.erase("ended"),
		func(d: Dictionary) -> void: d["ended"] = [],
		func(d: Dictionary) -> void: d["ended"]["GHOST"] = 2,
		func(d: Dictionary) -> void: d["ended"]["AM"] = 3,
		func(d: Dictionary) -> void: d["ended"]["AM"] = 1,
		func(d: Dictionary) -> void: d["ended"]["AM"] = 2.5,
		func(d: Dictionary) -> void: d["ended"]["AM"] = "2",
		func(d: Dictionary) -> void: d["next_day"]["AM"] = 3,
	]
	var cases := [v3_with_ended]
	for edit in edits:
		var bad := good.duplicate(true)
		edit.call(bad)
		cases.append(bad)
	for bad in cases:
		var target := auto_free(FlightSim.new()) as FlightSim
		assert_bool(target.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_array(target.contract_ids()).is_empty()


## An ended contract releases its future days, not the occurrences it issued:
## a one-off over AM-d1's gate time is refused while AM-d1 is live.
func test_a_one_off_cannot_take_the_gate_time_of_a_live_ended_occurrence() -> void:
	var world := _ended_world()
	var sim: FlightSim = world[1]
	assert_array(sim.flight_ids()).contains(["AM-d1"])
	var starts := FlightTimetable.starts_for(sim.contract_of("AM"), 1)
	await (
		assert_error(func() -> void: sim.add_flight("RAW", starts, "C"))
		. is_push_error("FlightSim: flight 'RAW' would hold gate C during AM-d1")
	)
	assert_array(sim.flight_ids()).not_contains(["RAW"])


func test_a_one_off_may_take_a_day_the_ended_contract_never_issues() -> void:
	var world := _ended_world()
	var sim: FlightSim = world[1]
	_run(world[0], 40000)
	assert_array(sim.flight_ids()).not_contains(["AM-d1"])
	var starts := FlightTimetable.starts_for(sim.contract_of("AM"), 2)
	assert_bool(sim.add_flight("RAW", starts, "C")).is_true()


## The same refusal on load: a save with live AM-d1, ended AM and a one-off on
## AM-d1's gate time cannot come from a run.
func test_a_save_with_a_one_off_over_a_live_ended_occurrence_is_refused() -> void:
	var data := _saved(_ended_world())
	var occurrence: Dictionary = {}
	for entry in data["flights"]:
		if entry["id"] == "AM-d1":
			occurrence = entry
	assert_dict(occurrence).is_not_empty()
	assert_bool(FlightSnapshot.load(data.duplicate(true)).has("error")).is_false()
	var bad := data.duplicate(true)
	var one_off := occurrence.duplicate(true)
	one_off["id"] = "RAW"
	one_off["contract"] = ""
	one_off["day"] = -1
	bad["flights"].append(one_off)
	var loaded := FlightSnapshot.load(bad)
	assert_str(loaded.get("error", "")).contains("flight RAW clashes with AM-d1 of an ended")
	var target := auto_free(FlightSim.new()) as FlightSim
	await (
		assert_error(func() -> void: target.from_snapshot(bad))
		. is_push_error("FlightSim.from_snapshot: %s" % loaded["error"])
	)
	assert_array(target.contract_ids()).is_empty()


## Ended AM with live AM-d1 and a running contract NEW at the same time with
## live NEW-d1: accept_contract would have refused NEW, so the save is refused.
func test_a_save_with_a_running_contract_over_a_live_ended_occurrence_is_refused() -> void:
	var data := _saved(_ended_world())
	var at := 0
	for i in data["flights"].size():
		if data["flights"][i]["id"] == "AM-d1":
			at = i
	var contract: Dictionary = data["contracts"][0].duplicate(true)
	contract["id"] = "NEW"
	contract["first_day"] = 1
	data["contracts"].append(contract)
	data["start_day"]["NEW"] = 1
	data["next_day"]["NEW"] = 2
	var flight: Dictionary = data["flights"][at].duplicate(true)
	flight["id"] = "NEW-d1"
	flight["contract"] = "NEW"
	data["flights"].insert(at + 1, flight)
	var loaded := FlightSnapshot.load(data)
	assert_str(loaded.get("error", "")).contains("flight NEW-d1 clashes with AM-d1 of an ended")


## The valid pair: NEW accepted at AM's time after AM-d1 has gone loads.
func test_a_running_contract_at_an_ended_contracts_time_loads_once_its_flights_are_gone() -> void:
	var world := _ended_world()
	_run(world[0], 40000)
	assert_bool(world[1].accept_contract(TestFlightContracts.terms("NEW", 480))).is_true()
	var data := _saved(world)
	(
		assert_array(data["flights"].filter(func(f: Dictionary) -> bool: return f["id"] == "AM-d1"))
		. is_empty()
	)
	assert_bool(FlightSnapshot.load(data).has("error")).is_false()
