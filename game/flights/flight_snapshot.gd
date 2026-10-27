class_name FlightSnapshot
extends RefCounted
## The JSON shape of FlightSim's state, and its checks on load. A load is
## strict: the save must be exactly what an uninterrupted run would hold at its
## tick (issued days, live occurrences and their schedules all derive from the
## contracts and the tick), so a bad save is refused whole.

const KEYS := ["save_version", "tick", "contracts", "next_day", "flights"]
const FLIGHT_KEYS := ["id", "starts", "state", "gate", "contract", "day"]
## Ticks stay exact through JSON (doubles) up to 2^53.
const MAX_TICK := 9007199254740992


static func save(
	tick: int, contracts: Array[Dictionary], next_day: Dictionary, flights: Array[Dictionary]
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
		"contracts": contract_list,
		"next_day": next_day.duplicate(),
		"flights": flight_list,
	}


## {"tick", "contracts", "next_day", "flights"} ready to install, or {"error"}.
static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var tick := int(data["tick"])
	var contracts: Array[Dictionary] = []
	problem = _read_contracts(data["contracts"], tick, contracts)
	if problem == "":
		problem = _next_day_problem(data["next_day"], contracts, tick)
	if problem != "":
		return {"error": problem}
	var next_day := {}
	for contract in contracts:
		next_day[contract["id"]] = int(data["next_day"][contract["id"]])
	var flights: Array[Dictionary] = []
	problem = _read_flights(data["flights"], contracts, next_day, tick, flights)
	if problem != "":
		return {"error": problem}
	return {"tick": tick, "contracts": contracts, "next_day": next_day, "flights": flights}


static func _top_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not KEYS.has(key):
			return "unknown key '%s'" % key
	for key in KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]):
		return "save_version must be %d" % FlightSim.SAVE_VERSION
	if int(data["save_version"]) != FlightSim.SAVE_VERSION:
		return "save_version must be %d" % FlightSim.SAVE_VERSION
	if not _is_tick(data["tick"]):
		return "tick must be a whole number from 0 to 2^53"
	if typeof(data["contracts"]) != TYPE_ARRAY or typeof(data["flights"]) != TYPE_ARRAY:
		return "contracts and flights must be arrays"
	if typeof(data["next_day"]) != TYPE_DICTIONARY:
		return "next_day must be a dictionary"
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
			if FlightTimetable.contracts_clash(contract, other):
				return "contracts %s and %s clash" % [other["id"], contract["id"]]
		out.append(contract)
	return ""


## Each contract's first unissued day must be the one an uninterrupted run
## reaches at `tick`.
static func _next_day_problem(
	next_day: Dictionary, contracts: Array[Dictionary], tick: int
) -> String:
	if next_day.size() != contracts.size():
		return "next_day must have one entry per contract"
	for contract in contracts:
		var value: Variant = next_day.get(contract["id"])
		if not WholeNumber.is_whole(value):
			return "next_day for %s must be a whole number" % contract["id"]
		if int(value) != FlightTimetable.next_day(contract, tick):
			return "next_day for %s does not match the tick" % contract["id"]
	return ""


static func _read_flights(
	entries: Array,
	contracts: Array[Dictionary],
	next_day: Dictionary,
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
				problem = _one_off_problem(entry, starts, contracts)
			else:
				problem = _occurrence_problem(entry, starts, contracts, next_day, tick)
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
		if int(live.get(contract["id"], 0)) != _expected_live(contract, next_day, tick):
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
	entry: Dictionary, starts: Array[int], contracts: Array[Dictionary]
) -> String:
	if int(entry["day"]) != -1:
		return "one-off flight %s must have day -1" % entry["id"]
	if not FlightTimetable.parse_occurrence(entry["id"]).is_empty():
		return "one-off flight %s has an occurrence id" % entry["id"]
	for contract in contracts:
		if contract["gate"] != entry["gate"]:
			continue
		if FlightTimetable.contract_overlaps(contract, starts[0], starts[FlightSim.State.DEPARTED]):
			return "flight %s clashes with contract %s" % [entry["id"], contract["id"]]
	return ""


## An occurrence must be issued, not yet pruned, and exactly as its contract
## schedules it.
static func _occurrence_problem(
	entry: Dictionary,
	starts: Array[int],
	contracts: Array[Dictionary],
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
	if day < contract["first_day"] or day >= next_day[contract["id"]]:
		return "flight %s was not issued" % entry["id"]
	if entry["id"] != FlightTimetable.occurrence_id(contract["id"], day):
		return "flight %s does not match its contract and day" % entry["id"]
	if entry["gate"] != contract["gate"] or starts != FlightTimetable.starts_for(contract, day):
		return "flight %s does not match its contract's timetable" % entry["id"]
	if tick >= FlightTimetable.prune_tick(contract, day):
		return "flight %s should have been pruned" % entry["id"]
	return ""


## How many issued occurrences of `contract` are still live at `tick`.
static func _expected_live(contract: Dictionary, next_day: Dictionary, tick: int) -> int:
	var count := 0
	var day: int = next_day[contract["id"]] - 1
	while day >= contract["first_day"] and tick < FlightTimetable.prune_tick(contract, day):
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
