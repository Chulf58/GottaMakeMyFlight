class_name FlightSnapshot
extends RefCounted
## The JSON shape of FlightSim's state, and its checks on load. A load is
## strict: the save must be exactly what an uninterrupted run would hold at its
## tick (issued days, live occurrences and their schedules all derive from the
## contracts, the opening tick and the tick), so a bad save is refused whole.
##
## Version 3 adds the airport's open state: opened_tick (-1 while closed) and
## each contract's start_day, its first day that is or will be issued. A
## version 2 save was written before the airport could be closed, so it loads
## as open since tick 0 with every contract starting on its first_day.
##
## Version 4 adds ended: contract id -> the first day it never issues
## (FlightSim.end_contract). An ended contract's next_day is that day for good,
## and it no longer clashes with other contracts at its gate. A version 2 or 3
## save has none ended.

const KEYS := [
	"save_version", "tick", "opened_tick", "contracts", "start_day", "next_day", "ended", "flights"
]
const V3_KEYS := [
	"save_version", "tick", "opened_tick", "contracts", "start_day", "next_day", "flights"
]
const V2_KEYS := ["save_version", "tick", "contracts", "next_day", "flights"]
const FLIGHT_KEYS := ["id", "starts", "state", "gate", "contract", "day"]
## Ticks stay exact through JSON (doubles) up to 2^53.
const MAX_TICK := 9007199254740992


static func save(
	tick: int,
	opened_tick: int,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	ended: Dictionary,
	flights: Array[Dictionary]
) -> Dictionary:
	var contract_list := []
	for contract in contracts:
		contract_list.append(contract.duplicate())
	var flight_list := []
	for flight in flights:
		var entry := {}
		for key in FLIGHT_KEYS:
			entry[key] = flight[key]
		entry["starts"] = (flight["starts"] as Array).duplicate()
		flight_list.append(entry)
	return {
		"save_version": FlightSim.SAVE_VERSION,
		"tick": tick,
		"opened_tick": opened_tick,
		"contracts": contract_list,
		"start_day": start_day.duplicate(),
		"next_day": next_day.duplicate(),
		"ended": ended.duplicate(),
		"flights": flight_list,
	}


## {"tick", "opened_tick", "contracts", "start_day", "next_day", "ended",
## "flights"} ready to install, or {"error"}.
static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var tick := int(data["tick"])
	var opened := int(data.get("opened_tick", 0))
	var contracts: Array[Dictionary] = []
	problem = _read_contracts(data["contracts"], tick, contracts)
	var start_day := {}
	var ended := {}
	if problem == "":
		problem = _read_start_days(data, contracts, opened, start_day)
	if problem == "":
		problem = _read_ended(data, contracts, start_day, opened, tick, ended)
	if problem == "":
		problem = _clash_problem(contracts, ended)
	if problem == "":
		problem = _next_day_problem(data["next_day"], contracts, start_day, ended, opened, tick)
	if problem != "":
		return {"error": problem}
	var next_day := {}
	for contract in contracts:
		next_day[contract["id"]] = int(data["next_day"][contract["id"]])
	var flights: Array[Dictionary] = []
	problem = _read_flights(data["flights"], contracts, start_day, next_day, ended, tick, flights)
	if problem != "":
		return {"error": problem}
	return {
		"tick": tick,
		"opened_tick": opened,
		"contracts": contracts,
		"start_day": start_day,
		"next_day": next_day,
		"ended": ended,
		"flights": flights,
	}


static func _top_problem(data: Dictionary) -> String:
	var version: Variant = data.get("save_version")
	var versions := "save_version must be 2, 3 or %d" % FlightSim.SAVE_VERSION
	if not WholeNumber.is_whole(version) or not [2, 3, FlightSim.SAVE_VERSION].has(int(version)):
		return versions
	var keys: Array = KEYS
	if int(version) == 3:
		keys = V3_KEYS
	elif int(version) == 2:
		keys = V2_KEYS
	for key in data.keys():
		if not keys.has(key):
			return "unknown key '%s'" % key
	for key in keys:
		if not data.has(key):
			return "missing key '%s'" % key
	if not _is_tick(data["tick"]):
		return "tick must be a whole number from 0 to 2^53"
	if data.has("opened_tick"):
		var opened: Variant = data["opened_tick"]
		if not WholeNumber.is_whole(opened) or opened < -1 or opened > data["tick"]:
			return "opened_tick must be -1 or a whole number from 0 to the tick"
	if typeof(data["contracts"]) != TYPE_ARRAY or typeof(data["flights"]) != TYPE_ARRAY:
		return "contracts and flights must be arrays"
	if typeof(data["next_day"]) != TYPE_DICTIONARY:
		return "next_day must be a dictionary"
	if data.has("ended") and typeof(data["ended"]) != TYPE_DICTIONARY:
		return "ended must be a dictionary"
	return ""


## first_day must be one that accepting between tick 0 and `tick` gives.
static func _read_contracts(entries: Array, tick: int, out: Array[Dictionary]) -> String:
	for entry in entries:
		var problem := FlightContract.problem(entry, FlightContract.KEYS)
		if problem != "":
			return problem
		if not FlightSim.GATES.has(entry["gate"]):
			return "contract gate '%s' has no stand" % entry["gate"]
		var contract := FlightContract.make(entry)
		var earliest := FlightTimetable.first_day(contract, 0)
		var latest := FlightTimetable.first_day(contract, tick)
		if contract["first_day"] < earliest or contract["first_day"] > latest:
			return "contract %s first_day is not one an acceptance could give" % contract["id"]
		for other in out:
			if other["id"] == contract["id"]:
				return "contract id '%s' is used twice" % contract["id"]
		out.append(contract)
	return ""


## Contracts that still run must not hold one gate at the same time; an ended
## contract's gate time is free.
static func _clash_problem(contracts: Array[Dictionary], ended: Dictionary) -> String:
	for i in contracts.size():
		for j in range(i):
			var both_run: bool = (
				not ended.has(contracts[i]["id"]) and not ended.has(contracts[j]["id"])
			)
			if both_run and FlightTimetable.contracts_clash(contracts[i], contracts[j]):
				return "contracts %s and %s clash" % [contracts[j]["id"], contracts[i]["id"]]
	return ""


## ended (absent in a version 2 or 3 save): contract id -> a whole day that is
## the first one never issued, so it is from the start day up to the day an
## uninterrupted run would have reached, and only an open airport ends one.
static func _read_ended(
	data: Dictionary,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	opened: int,
	tick: int,
	out: Dictionary
) -> String:
	if not data.has("ended"):
		return ""
	var days: Dictionary = data["ended"]
	for contract in contracts:
		if not days.has(contract["id"]):
			continue
		var value: Variant = days[contract["id"]]
		if not WholeNumber.is_whole(value) or opened < 0:
			return "ended for %s must be a whole day of an open airport" % contract["id"]
		var first: int = start_day[contract["id"]]
		var last := maxi(first, FlightTimetable.next_day(contract, tick))
		if int(value) < first or int(value) > last:
			return "ended for %s is not a day it could have ended on" % contract["id"]
		out[contract["id"]] = int(value)
	if out.size() != days.size():
		return "ended names a contract that does not exist"
	return ""


## Each start day is the contract's first_day, or, for a contract accepted
## while closed, the day it starts on after the opening. While the airport is
## closed nothing has been moved yet; a contract accepted after the opening
## has a first_day no earlier than an acceptance at the opening gives.
static func _read_start_days(
	data: Dictionary, contracts: Array[Dictionary], opened: int, out: Dictionary
) -> String:
	if not data.has("start_day"):
		for contract in contracts:
			out[contract["id"]] = contract["first_day"]
		return ""
	var days: Variant = data["start_day"]
	if typeof(days) != TYPE_DICTIONARY or days.size() != contracts.size():
		return "start_day must be a dictionary with one entry per contract"
	for contract in contracts:
		var value: Variant = days.get(contract["id"])
		if not WholeNumber.is_whole(value):
			return "start_day for %s must be a whole number" % contract["id"]
		var day := int(value)
		var first: int = contract["first_day"]
		var ok := day == first
		if opened >= 0:
			var after_opening := FlightTimetable.opening_day(contract, opened)
			ok = (
				day == after_opening
				or (ok and first >= FlightTimetable.first_day(contract, opened))
			)
		if not ok:
			return "start_day for %s is not one the opening could give" % contract["id"]
		out[contract["id"]] = day
	return ""


## Each contract's first unissued day must be the one an uninterrupted run
## reaches at `tick`: its start day while closed, since nothing is issued.
static func _next_day_problem(
	next_day: Dictionary,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	ended: Dictionary,
	opened: int,
	tick: int
) -> String:
	if next_day.size() != contracts.size():
		return "next_day must have one entry per contract"
	for contract in contracts:
		var value: Variant = next_day.get(contract["id"])
		if not WholeNumber.is_whole(value):
			return "next_day for %s must be a whole number" % contract["id"]
		var expected: int = start_day[contract["id"]]
		if opened >= 0:
			expected = maxi(expected, FlightTimetable.next_day(contract, tick))
		if ended.has(contract["id"]):
			expected = ended[contract["id"]]
		if int(value) != expected:
			return "next_day for %s does not match the tick" % contract["id"]
	return ""


static func _read_flights(
	entries: Array,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	ended: Dictionary,
	tick: int,
	out: Array[Dictionary]
) -> String:
	var seen := {}
	var live := {}
	for entry in entries:
		var problem := _flight_problem(entry, seen)
		if problem == "":
			var starts := _ints(entry["starts"])
			if entry["contract"] == "":
				problem = _one_off_problem(entry, starts, contracts, ended)
			else:
				problem = _occurrence_problem(entry, starts, contracts, start_day, next_day, tick)
				live[entry["contract"]] = int(live.get(entry["contract"], 0)) + 1
			if problem == "" and int(entry["state"]) != FlightTimetable.state_at(starts, tick):
				problem = "flight %s state does not match the tick" % entry["id"]
			if problem == "" and not out.is_empty():
				if not FlightTimetable.flight_before(out[out.size() - 1], entry):
					problem = "flight %s is out of timetable order" % entry["id"]
			if problem == "":
				out.append(_record(entry, starts))
		if problem != "":
			return problem
	for contract in contracts:
		var expected := _expected_live(contract, start_day, next_day, tick)
		if int(live.get(contract["id"], 0)) != expected:
			return "occurrences of %s are missing" % contract["id"]
	return ""


static func _flight_problem(entry: Variant, seen: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "each flight must be a dictionary"
	for key in entry.keys():
		if not FLIGHT_KEYS.has(key):
			return "unknown flight key '%s'" % key
	for key in FLIGHT_KEYS:
		if not entry.has(key):
			return "a flight is missing '%s'" % key
	if typeof(entry["id"]) != TYPE_STRING or entry["id"] == "" or seen.has(entry["id"]):
		return "flight ids must be unique, non-empty strings"
	seen[entry["id"]] = true
	if typeof(entry["gate"]) != TYPE_STRING or not FlightSim.GATES.has(entry["gate"]):
		return "flight %s is at a gate with no stand" % entry["id"]
	if typeof(entry["contract"]) != TYPE_STRING:
		return "flight %s contract must be a string" % entry["id"]
	if not WholeNumber.is_whole(entry["state"]) or not WholeNumber.is_whole(entry["day"]):
		return "flight %s state and day must be whole numbers" % entry["id"]
	var values: Variant = entry["starts"]
	if typeof(values) != TYPE_ARRAY or values.size() != FlightSim.STATE_COUNT:
		return "starts must be an array of %d ticks" % FlightSim.STATE_COUNT
	for value in values:
		if not _is_tick(value):
			return "start ticks must be whole numbers from 0 to 2^53"
	if not FlightTimetable.starts_valid(_ints(values)):
		return "start ticks must not decrease"
	return ""


static func _one_off_problem(
	entry: Dictionary, starts: Array[int], contracts: Array[Dictionary], ended: Dictionary
) -> String:
	if int(entry["day"]) != -1:
		return "one-off flight %s must have day -1" % entry["id"]
	if not FlightTimetable.parse_occurrence(entry["id"]).is_empty():
		return "one-off flight %s has an occurrence id" % entry["id"]
	for contract in contracts:
		if contract["gate"] != entry["gate"] or ended.has(contract["id"]):
			continue
		if FlightTimetable.contract_overlaps(contract, starts[0], starts[FlightSim.State.DEPARTED]):
			return "flight %s clashes with contract %s" % [entry["id"], contract["id"]]
	return ""


## An occurrence must be issued (from its contract's start day), not yet
## pruned, and exactly as its contract schedules it.
static func _occurrence_problem(
	entry: Dictionary,
	starts: Array[int],
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	tick: int
) -> String:
	var contract := {}
	for candidate in contracts:
		if candidate["id"] == entry["contract"]:
			contract = candidate
	if contract.is_empty():
		return "flight %s names an unknown contract" % entry["id"]
	var day := int(entry["day"])
	if day < start_day[contract["id"]] or day >= next_day[contract["id"]]:
		return "flight %s was not issued" % entry["id"]
	if entry["id"] != FlightTimetable.occurrence_id(contract["id"], day):
		return "flight %s does not match its contract and day" % entry["id"]
	if entry["gate"] != contract["gate"] or starts != FlightTimetable.starts_for(contract, day):
		return "flight %s does not match its contract's timetable" % entry["id"]
	if tick >= FlightTimetable.prune_tick(contract, day):
		return "flight %s should have been pruned" % entry["id"]
	return ""


## How many issued occurrences of `contract` are still live at `tick`.
static func _expected_live(
	contract: Dictionary, start_day: Dictionary, next_day: Dictionary, tick: int
) -> int:
	var count := 0
	var day: int = next_day[contract["id"]] - 1
	while day >= start_day[contract["id"]] and tick < FlightTimetable.prune_tick(contract, day):
		count += 1
		day -= 1
	return count


static func _record(entry: Dictionary, starts: Array[int]) -> Dictionary:
	return {
		"id": entry["id"],
		"starts": starts,
		"state": int(entry["state"]),
		"gate": entry["gate"],
		"contract": entry["contract"],
		"day": int(entry["day"]),
	}


static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value in values:
		out.append(int(value))
	return out


static func _is_tick(value: Variant) -> bool:
	return WholeNumber.is_whole(value) and value >= 0 and value <= MAX_TICK
