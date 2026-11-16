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
##
## Gates (decision gates-technical-design-gate-desks-link-to-north-exits-one-
## st, point 5): every contract and flight gate must be one of the `gates` the
## load is given (FlightSim.gate_ids()). An occurrence's gate may differ from
## its contract's, since FlightSim.reassign_gate moves only the days not yet
## issued. No two live flights may meet at a gate (FlightTimetable.shares_gate),
## except two one-offs, which add_flight never compares; no running contract
## may meet another contract's live occurrence there.
## Version 5 narrows what a contract may hold (its booked passengers must fit
## its plane class, FlightContract.problem); the keys are those of version 4.
##
## Version 7 (Runway R7) wires in the taxi plans. Each flight keeps the stand
## it was issued at ("stand", a StandPlacement stand), "reserving" lists the
## ended contracts whose days still book their ground, and "landed" lists
## today's occurrences already pruned, as flight entries, so that a load
## re-plans every day exactly as the run did (FlightPlans). The shared runway
## and lane are GroundPlanner's now: only gate clashes are checked here, and
## FlightSim.from_snapshot() re-plans and refuses a save whose plan fails.
##
## Version 9 (airside S2, ruling taxi-time-follows-each-gate-s-route-length-
## far-side-gates-ta) gives every contract its taxi pair (FlightContract.
## TAXI_KEY), its current assignment's. A contract may have moved since an
## occurrence was issued, so a saved occurrence is checked against its own
## record, never against the contract's times now: its fixed phases are
## FlightSim.PHASE_TICKS', its PUSHBACK is its day's departure, its taxi phases
## are a valid pair (TaxiTimes.problem) at least as long as its saved stand's
## routes need, and it is live until PRUNE_AFTER_TICKS after its own DEPARTED.
## "landed" holds yesterday's pruned occurrences as well as today's, so every
## issued day from yesterday on must be live or landed (_coverage_problem()):
## a missing occurrence is found without knowing the pair it flew. Which days
## are issued, and a closed airport's start days, never depend on the pair
## (FlightTimetable.issue_tick), so they are checked exactly; first_day, set
## with the pair the contract had when accepted, is checked against the
## widest the pair bounds allow. Only version 9 loads; every older save is
## refused, with no migration.

const KEYS := [
	"save_version",
	"tick",
	"opened_tick",
	"contracts",
	"start_day",
	"next_day",
	"ended",
	"reserving",
	"flights",
	"landed",
]
const FLIGHT_KEYS := ["id", "starts", "state", "gate", "contract", "day", "stand"]
## Ticks stay exact through JSON (doubles) up to 2^53.
const MAX_TICK := 9007199254740992


static func save(
	tick: int,
	opened_tick: int,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	ended: Dictionary,
	reserving: Dictionary,
	flights: Array[Dictionary],
	landed: Array[Dictionary]
) -> Dictionary:
	var contract_list := []
	for contract in contracts:
		contract_list.append(contract.duplicate())
	return {
		"save_version": FlightSim.SAVE_VERSION,
		"tick": tick,
		"opened_tick": opened_tick,
		"contracts": contract_list,
		"start_day": start_day.duplicate(),
		"next_day": next_day.duplicate(),
		"ended": ended.duplicate(),
		"reserving": _sorted_ids(reserving),
		"flights": _entries(flights),
		"landed": _entries(landed),
	}


static func _sorted_ids(ids: Dictionary) -> Array:
	var out := ids.keys()
	out.sort()
	return out


static func _entries(flights: Array[Dictionary]) -> Array:
	var out := []
	for flight in flights:
		var entry := {}
		for key in FLIGHT_KEYS:
			entry[key] = flight[key]
		entry["starts"] = (flight["starts"] as Array).duplicate()
		entry["stand"] = (flight["stand"] as Dictionary).duplicate()
		out.append(entry)
	return out


## {"tick", "opened_tick", "contracts", "start_day", "next_day", "ended",
## "flights", "landed"} ready to install, or {"error"}. `gates` are the gates
## with a stand. The taxi plans are FlightSim's to check.
static func load(data: Dictionary, gates: Array[String]) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var tick := int(data["tick"])
	var opened := int(data.get("opened_tick", 0))
	var contracts: Array[Dictionary] = []
	problem = _read_contracts(data["contracts"], tick, gates, contracts)
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
	problem = _read_flights(
		data["flights"], contracts, start_day, next_day, ended, tick, gates, flights
	)
	var reserving := {}
	if problem == "":
		problem = _read_reserving(data["reserving"], ended, reserving)
	var landed: Array[Dictionary] = []
	if problem == "":
		problem = _read_landed(
			data["landed"], contracts, start_day, next_day, tick, flights, landed
		)
	if problem == "":
		problem = _coverage_problem(contracts, start_day, next_day, tick, flights, landed)
	if problem != "":
		return {"error": problem}
	return {
		"landed": landed,
		"reserving": reserving,
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
	if not WholeNumber.is_whole(version) or int(version) != FlightSim.SAVE_VERSION:
		return "save_version must be %d" % FlightSim.SAVE_VERSION
	var keys: Array = KEYS
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
	for key in ["contracts", "flights", "landed", "reserving"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return "contracts, flights, landed and reserving must be arrays"
	if typeof(data["next_day"]) != TYPE_DICTIONARY:
		return "next_day must be a dictionary"
	if data.has("ended") and typeof(data["ended"]) != TYPE_DICTIONARY:
		return "ended must be a dictionary"
	return ""


## first_day must be one that accepting between tick 0 and `tick` gives with a
## pair inside the bounds (the contract may have moved since, so its pair now
## need not be the one it was accepted with; a TAXI_IN of TaxiTimes.MAX_IN
## gives the latest day), and the departure one its traits allow
## (FlightContract.window_problem).
static func _read_contracts(
	entries: Array, tick: int, gates: Array[String], out: Array[Dictionary]
) -> String:
	for entry in entries:
		var problem := FlightContract.problem(entry, FlightContract.KEYS)
		if problem == "":
			problem = FlightContract.window_problem(entry)
		if problem != "":
			return problem
		if not gates.has(entry["gate"]):
			return "contract gate '%s' has no stand" % entry["gate"]
		var contract := FlightContract.make(entry)
		var earliest := FlightTimetable.first_day(_with_taxi(contract, TaxiTimes.BASE), 0)
		var latest_taxi := [TaxiTimes.MAX_IN, TaxiTimes.BASE[1]]
		var latest := FlightTimetable.first_day(_with_taxi(contract, latest_taxi), tick)
		if contract["first_day"] < earliest or contract["first_day"] > latest:
			return "contract %s first_day is not one an acceptance could give" % contract["id"]
		for other in out:
			if other["id"] == contract["id"]:
				return "contract id '%s' is used twice" % contract["id"]
		out.append(contract)
	return ""


## `contract` with taxi pair `taxi`, to bound what another pair would give.
static func _with_taxi(contract: Dictionary, taxi: Array) -> Dictionary:
	var fields := contract.duplicate()
	fields[FlightContract.TAXI_KEY] = taxi
	return fields


## Contracts that still run must not hold one gate at the same time; an ended
## contract's time is free.
static func _clash_problem(contracts: Array[Dictionary], ended: Dictionary) -> String:
	for i in contracts.size():
		for j in range(i):
			var both_run: bool = (
				not ended.has(contracts[i]["id"]) and not ended.has(contracts[j]["id"])
			)
			if both_run and FlightTimetable.contracts_share_gate(contracts[i], contracts[j]):
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
## has a first_day no earlier than an acceptance at the opening gives with the
## shortest pair, TaxiTimes.BASE (it may have been accepted at another gate).
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
			var base := _with_taxi(contract, TaxiTimes.BASE)
			ok = day == after_opening or (ok and first >= FlightTimetable.first_day(base, opened))
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
	gates: Array[String],
	out: Array[Dictionary]
) -> String:
	var seen := {}
	for entry in entries:
		var problem := _flight_problem(entry, seen, gates)
		if problem == "":
			var starts := _ints(entry["starts"])
			if entry["contract"] == "":
				problem = _one_off_problem(entry, starts, contracts, ended)
			else:
				problem = _occurrence_problem(entry, starts, contracts, start_day, next_day, tick)
			if problem == "" and int(entry["state"]) != FlightTimetable.state_at(starts, tick):
				problem = "flight %s state does not match the tick" % entry["id"]
			if problem == "" and not out.is_empty():
				if not FlightTimetable.flight_before(out[out.size() - 1], entry):
					problem = "flight %s is out of timetable order" % entry["id"]
			if problem == "":
				out.append(_record(entry, starts))
		if problem != "":
			return problem
	return _fixed_clash_problem(out, contracts, ended)


## A live occurrence keeps the gate and time it was issued with, whether its
## contract ended or moved since: no two live flights may meet at a gate (two
## one-offs excepted), and no running contract may meet another's live
## occurrence there.
static func _fixed_clash_problem(
	flights: Array[Dictionary], contracts: Array[Dictionary], ended: Dictionary
) -> String:
	for i in flights.size():
		var a := flights[i]
		for j in range(i):
			var b := flights[j]
			if a["contract"] == b["contract"]:
				continue
			if not FlightTimetable.shares_gate(a["gate"], a["starts"], b["gate"], b["starts"]):
				continue
			if ended.has(b["contract"]):
				return "flight %s clashes with %s of an ended contract" % [a["id"], b["id"]]
			if ended.has(a["contract"]):
				return "flight %s clashes with %s of an ended contract" % [b["id"], a["id"]]
			return "flights %s and %s clash" % [b["id"], a["id"]]
	for contract in contracts:
		if ended.has(contract["id"]):
			continue
		for flight in flights:
			if flight["contract"] == "" or flight["contract"] == contract["id"]:
				continue
			if FlightTimetable.contract_meets(contract, flight["gate"], flight["starts"]):
				return "contract %s clashes with flight %s" % [contract["id"], flight["id"]]
	return ""


static func _flight_problem(entry: Variant, seen: Dictionary, gates: Array[String]) -> String:
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
	if typeof(entry["gate"]) != TYPE_STRING or not gates.has(entry["gate"]):
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
	if not StandPlacement.is_stand(entry["stand"]):
		return "flight %s stand must be a stand" % entry["id"]
	return ""


static func _one_off_problem(
	entry: Dictionary, starts: Array[int], contracts: Array[Dictionary], ended: Dictionary
) -> String:
	if int(entry["day"]) != -1:
		return "one-off flight %s must have day -1" % entry["id"]
	if not FlightTimetable.parse_occurrence(entry["id"]).is_empty():
		return "one-off flight %s has an occurrence id" % entry["id"]
	for contract in contracts:
		if ended.has(contract["id"]):
			continue
		if FlightTimetable.contract_meets(contract, entry["gate"], starts):
			return "flight %s clashes with contract %s" % [entry["id"], contract["id"]]
	return ""


## An occurrence must be issued (from its contract's start day), not yet
## pruned by its own starts (unless `tick` is -1: a landed one), and at times
## its contract could have issued it with (_starts_problem()). Its gate and
## taxi pair may be others than its contract's: the ones the contract had when
## it was issued.
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
	var problem := _starts_problem(entry, starts, contract, day)
	if problem != "":
		return problem
	if tick >= 0 and tick >= FlightTimetable.prune_tick(starts):
		return "flight %s should have been pruned" % entry["id"]
	return ""


## An occurrence of `contract` on `day` with `starts` departs at its day's
## departure, has the fixed phases of FlightSim.PHASE_TICKS, and taxis with a
## valid pair (TaxiTimes.problem) no shorter than its saved stand's routes need
## (TaxiTimes.for_stand); the pair need not be the contract's now.
static func _starts_problem(
	entry: Dictionary, starts: Array[int], contract: Dictionary, day: int
) -> String:
	var pair := TaxiTimes.of_starts(starts)
	if TaxiTimes.problem(pair) != "":
		return "flight %s taxi times %s are not a pair a gate gives" % [entry["id"], pair]
	var departs := FlightTimetable.starts_for(contract, day)[FlightSim.State.PUSHBACK]
	var built := FlightSim.schedule_starts(starts[0], pair)
	if starts != built or starts[FlightSim.State.PUSHBACK] != departs:
		return "flight %s does not match its contract's timetable" % entry["id"]
	var needed := TaxiTimes.for_stand(_stand_of(entry))
	if not TaxiTimes.covers(pair, needed):
		return "flight %s taxis %s ticks, but its stand needs %s" % [entry["id"], pair, needed]
	return ""


## Each issued day of each contract from yesterday on is a live or a landed
## occurrence. Today's and yesterday's pruned occurrences are all kept as
## landed (FlightSim._prune()), and no earlier one can still be live (a day's
## flight is pruned by 01:00 the next day, TaxiTimes.MAX_OUT), so a missing
## occurrence is found whatever taxi pair it flew.
static func _coverage_problem(
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	tick: int,
	flights: Array[Dictionary],
	landed: Array[Dictionary]
) -> String:
	var listed := {}
	for list in [flights, landed]:
		for flight: Dictionary in list:
			listed[flight["id"]] = true
	var yesterday := GameCalendar.day_of(tick) - 1
	for contract in contracts:
		var id: String = contract["id"]
		for day in range(maxi(start_day[id], yesterday), next_day[id]):
			if not listed.has(FlightTimetable.occurrence_id(id, day)):
				return "occurrence %s is missing" % FlightTimetable.occurrence_id(id, day)
	return ""


static func _stand_of(entry: Dictionary) -> Dictionary:
	return StandPlacement.from_saved(entry["stand"])


static func _record(entry: Dictionary, starts: Array[int]) -> Dictionary:
	return {
		"id": entry["id"],
		"starts": starts,
		"state": int(entry["state"]),
		"gate": entry["gate"],
		"contract": entry["contract"],
		"day": int(entry["day"]),
		"stand": _stand_of(entry),
	}


## reserving: ended contracts whose days not yet issued still book their ground
## (FlightSim.end_contract()), each once, sorted.
static func _read_reserving(entries: Array, ended: Dictionary, out: Dictionary) -> String:
	for entry: Variant in entries:
		if typeof(entry) != TYPE_STRING or not ended.has(entry) or out.has(entry):
			return "reserving must list ended contracts, each once"
		out[entry] = true
	if _sorted_ids(out) != entries:
		return "reserving must be sorted"
	return ""


## landed: today's and yesterday's issued occurrences already pruned (by their
## own starts), in timetable order, each DEPARTED at times its contract could
## have issued it with and at a stand. Its gate may be one that has gone since,
## so only its shape is checked. That none is missing is _coverage_problem()'s.
static func _read_landed(
	entries: Array,
	contracts: Array[Dictionary],
	start_day: Dictionary,
	next_day: Dictionary,
	tick: int,
	flights: Array[Dictionary],
	out: Array[Dictionary]
) -> String:
	var seen := {}
	for flight in flights:
		seen[flight["id"]] = true
	var today := GameCalendar.day_of(tick)
	var all_gates: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("gate")) == TYPE_STRING:
			all_gates.append(entry["gate"])
	for entry: Variant in entries:
		var problem := _flight_problem(entry, seen, all_gates)
		if problem != "":
			return problem
		var starts := _ints(entry["starts"])
		problem = _occurrence_problem(entry, starts, contracts, start_day, next_day, -1)
		if problem != "":
			return problem
		var day := int(entry["day"])
		if day < today - 1 or day > today or tick < FlightTimetable.prune_tick(starts):
			return "landed flight %s is not one pruned today or yesterday" % entry["id"]
		if int(entry["state"]) != FlightSim.State.DEPARTED:
			return "landed flight %s has not departed" % entry["id"]
		if not out.is_empty() and not FlightTimetable.flight_before(out[out.size() - 1], entry):
			return "landed flight %s is out of timetable order" % entry["id"]
		out.append(_record(entry, starts))
	return ""


static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value in values:
		out.append(int(value))
	return out


static func _is_tick(value: Variant) -> bool:
	return WholeNumber.is_whole(value) and value >= 0 and value <= MAX_TICK
