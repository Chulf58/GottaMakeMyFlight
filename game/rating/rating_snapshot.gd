class_name RatingSnapshot
extends RefCounted
## The JSON shape of AirportRating's state and its checks on load. A load is
## strict: a bad save is refused whole and the rating is left as it was.

const KEYS := ["save_version", "tick", "days", "low_days", "pending"]
const DAY_KEYS := ["day", "made", "missed", "mood_sum"]
const PENDING_KEYS := ["flight", "tick"]
## Ticks stay exact through JSON (doubles) up to 2^53.
const MAX_TICK := 9007199254740992
## Flights between their doors closing and the next tick; a handful at most.
const MAX_PENDING := 64


## `days` maps day -> {"made", "missed", "mood_sum"}; `pending` holds
## {"flight", "tick"} entries.
static func save(
	tick: int, days: Dictionary, low_days: int, pending: Array[Dictionary]
) -> Dictionary:
	var day_ids: Array = days.keys()
	day_ids.sort()
	var day_list := []
	for day in day_ids:
		var totals: Dictionary = days[day]
		(
			day_list
			. append(
				{
					"day": day,
					"made": totals["made"],
					"missed": totals["missed"],
					"mood_sum": totals["mood_sum"],
				}
			)
		)
	var pending_list := []
	for entry in pending:
		pending_list.append({"flight": entry["flight"], "tick": entry["tick"]})
	return {
		"save_version": AirportRating.SAVE_VERSION,
		"tick": tick,
		"days": day_list,
		"low_days": low_days,
		"pending": pending_list,
	}


## {"tick", "days", "low_days", "pending"} ready to install, or {"error"}.
static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var tick := int(data["tick"])
	var days := {}
	problem = _read_days(data["days"], GameCalendar.day_of(tick), days)
	if problem == "" and not _is_count(data["low_days"], GameCalendar.day_of(tick)):
		problem = "low_days must be a whole number from 0 to the days played"
	var pending: Array[Dictionary] = []
	if problem == "":
		problem = _read_pending(data["pending"], tick, pending)
	if problem != "":
		return {"error": problem}
	return {"tick": tick, "days": days, "low_days": int(data["low_days"]), "pending": pending}


static func _top_problem(data: Dictionary) -> String:
	var problem := ""
	for key in data.keys():
		if not KEYS.has(key):
			problem = "unknown key '%s'" % key
	for key in KEYS:
		if problem == "" and not data.has(key):
			problem = "missing key '%s'" % key
	var version: Variant = data.get("save_version")
	if (
		problem == ""
		and (not WholeNumber.is_whole(version) or int(version) != AirportRating.SAVE_VERSION)
	):
		problem = "save_version must be %d" % AirportRating.SAVE_VERSION
	if problem == "" and not _is_count(data["tick"], MAX_TICK):
		problem = "tick must be a whole number from 0 to 2^53"
	if problem == "" and typeof(data["days"]) != TYPE_ARRAY:
		problem = "days must be an array"
	if problem == "" and typeof(data["pending"]) != TYPE_ARRAY:
		problem = "pending must be an array"
	return problem


## Days strictly ascending, inside the window ending at `current`.
static func _read_days(entries: Array, current: int, out: Dictionary) -> String:
	var previous := current - RatingFormula.WINDOW_DAYS
	for entry in entries:
		var problem := _entry_problem(entry, DAY_KEYS)
		if problem == "":
			problem = _day_problem(entry, previous, current)
		if problem != "":
			return problem
		previous = int(entry["day"])
		out[previous] = {
			"made": int(entry["made"]),
			"missed": int(entry["missed"]),
			"mood_sum": int(entry["mood_sum"]),
		}
	return ""


static func _day_problem(entry: Dictionary, previous: int, current: int) -> String:
	var day: Variant = entry["day"]
	if not WholeNumber.is_whole(day) or int(day) <= previous or int(day) > current:
		return "day %s is outside the window or out of order" % str(day)
	var cap := RatingFormula.MAX_DAY_COUNT
	if not _is_count(entry["made"], cap) or not _is_count(entry["missed"], cap):
		return "day %d counts must be whole numbers from 0 to %d" % [int(day), cap]
	if not _is_count(entry["mood_sum"], int(entry["made"]) * PassengerSim.MOOD_MAX):
		return (
			"day %d mood_sum must be a whole number up to made * %d"
			% [int(day), PassengerSim.MOOD_MAX]
		)
	return ""


static func _read_pending(entries: Array, tick: int, out: Array[Dictionary]) -> String:
	var seen := {}
	if entries.size() > MAX_PENDING:
		return "pending holds more than %d flights" % MAX_PENDING
	for entry in entries:
		var problem := _entry_problem(entry, PENDING_KEYS)
		if problem == "" and (typeof(entry["flight"]) != TYPE_STRING or entry["flight"] == ""):
			problem = "pending flight must be a non-empty string"
		if problem == "" and seen.has(entry["flight"]):
			problem = "pending flight '%s' is listed twice" % entry["flight"]
		if problem == "" and not _is_count(entry["tick"], tick):
			problem = "pending tick must be a whole number from 0 to the saved tick"
		if problem != "":
			return problem
		seen[entry["flight"]] = true
		out.append({"flight": entry["flight"], "tick": int(entry["tick"])})
	return ""


static func _entry_problem(entry: Variant, keys: Array) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "entries must be dictionaries"
	for key in (entry as Dictionary).keys():
		if not keys.has(key):
			return "entry has unknown key '%s'" % key
	for key in keys:
		if not (entry as Dictionary).has(key):
			return "entry is missing key '%s'" % key
	return ""


## A whole number from 0 to `most`.
static func _is_count(value: Variant, most: int) -> bool:
	return WholeNumber.is_whole(value) and value >= 0 and value <= most
