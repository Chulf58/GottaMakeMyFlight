class_name PassengerSnapshot
extends RefCounted
## The JSON shape of PassengerSim's state, and its checks on load. Committed
## paths, queue order, service ends, seat claims, apron progress and pending
## replans are all saved, so nothing is recomputed differently after a load.
## Cafe visits and counter queues go under "cafe" (CafeSnapshot).
## Seat claims and walker counts are rebuilt from the passenger records. The
## made and missed totals, each flight's results and the scheduled flights are
## saved as they are: settled passengers are retired, so they cannot be rebuilt.

const KEYS := [
	"save_version",
	"tick",
	"next_id",
	"last_batch_seed",
	"schedule",
	"passengers",
	"queues",
	"no_shows",
	"cafe",
	"made",
	"missed",
	"flight_results",
	"scheduled",
]
const NO_SHOW_CAUSES := ["no_entrance", "late"]
const INT_FIELDS := [
	"id",
	"variant",
	"spawn_tick",
	"boarding_tick",
	"stage",
	"stuck",
	"stage_tick",
	"path_index",
	"seg_mm",
	"station",
	"service_end",
	"seat_object",
	"exit_object",
	"apron_mm",
	"mood",
	"outcome_tick",
	"odometer_mm",
	"missed_stage",
	"missed_stuck",
	"hunger",
	"cafe_cooldown",
	"arrival_type",
]
const CELL_FIELDS := ["at", "seat_cell", "seat_front"]
const BOOL_FIELDS := ["late", "cleared", "needs_replan"]


## `totals` is [made, missed]; `scheduled` the scheduled flight ids.
static func save(
	sim: PassengerSim,
	passengers: Array[Passenger],
	schedule: Array[Dictionary],
	queues: Dictionary,
	next_id: int,
	totals: Array,
	scheduled: Array
) -> Dictionary:
	scheduled.sort()
	var records := []
	for p in passengers:
		records.append(_record(p))
	var queue_list := []
	var stations: Array = queues.keys()
	stations.sort()
	for station in stations:
		var q: Dictionary = queues[station]
		(
			queue_list
			. append(
				{
					"station": station,
					"lane": (q["lane"] as Array).duplicate(),
					"holding": (q["holding"] as Array).duplicate(),
					"serving": q["serving"],
				}
			)
		)
	var no_show_list := []
	var flights: Array = sim.no_shows.keys()
	flights.sort()
	for flight in flights:
		var entry := {"flight": flight}
		for cause in NO_SHOW_CAUSES:
			entry[cause] = sim.no_shows[flight][cause]
		no_show_list.append(entry)
	var result_list := []
	var result_flights: Array = sim.flight_results.keys()
	result_flights.sort()
	for flight in result_flights:
		var result: Dictionary = sim.flight_results[flight]
		var causes := []
		var keys: Array = result["causes"].keys()
		keys.sort()
		for key: Vector2i in keys:
			causes.append({"stage": key.x, "stuck": key.y, "count": result["causes"][key]})
		result_list.append(
			{"flight": flight, "made": result["made"], "missed": result["missed"], "causes": causes}
		)
	return {
		"save_version": PassengerSim.SAVE_VERSION,
		"tick": str(sim.tick),
		"next_id": next_id,
		"last_batch_seed": str(sim.last_batch_seed),
		"schedule": schedule.duplicate(true),
		"passengers": records,
		"queues": queue_list,
		"no_shows": no_show_list,
		"cafe": CafeSnapshot.save(sim.cafes),
		"made": totals[0],
		"missed": totals[1],
		"flight_results": result_list,
		"scheduled": scheduled,
	}


## A dictionary with the restored state, or with an "error" key.
static func load(data: Dictionary, grid: BuildGrid) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var out := {
		"tick": str(data["tick"]).to_int(),
		"next_id": int(data["next_id"]),
		"last_batch_seed": str(data["last_batch_seed"]).to_int(),
	}
	var schedule: Array[Dictionary] = []
	for entry in data["schedule"]:
		problem = _spawn_problem(entry)
		if problem != "":
			return {"error": problem}
		(
			schedule
			. append(
				{
					"tick": int(entry["tick"]),
					"flight": entry["flight"],
					"variant": int(entry["variant"]),
					"arrival": int(entry["arrival"]),
				}
			)
		)
	var passengers: Array[Passenger] = []
	var ids := {}
	for entry in data["passengers"]:
		var p := _passenger(entry, grid, int(data["next_id"]))
		if p == null or ids.has(p.id):
			return {"error": "passenger record %s is malformed or repeated" % str(entry).left(80)}
		ids[p.id] = p
		passengers.append(p)
	var cafe := CafeSnapshot.load(data["cafe"], ids, grid, out["tick"])
	if cafe.has("error"):
		return cafe
	out["cafe"] = cafe
	var queues := _queues(data["queues"], ids)
	if queues.has("error"):
		return queues
	var no_shows := _no_shows(data["no_shows"])
	if no_shows.has("error"):
		return no_shows
	out["no_shows"] = no_shows
	var results := _flight_results(data["flight_results"])
	if results.has("error"):
		return results
	problem = _totals_problem(data, results, passengers)
	if problem != "":
		return {"error": problem}
	var scheduled := {}
	for flight in data["scheduled"]:
		if typeof(flight) != TYPE_STRING or scheduled.has(flight):
			return {"error": "scheduled flights must be distinct strings"}
		scheduled[flight] = true
	out["made"] = int(data["made"])
	out["missed"] = int(data["missed"])
	out["flight_results"] = results
	out["scheduled"] = scheduled
	out["schedule"] = schedule
	out["passengers"] = passengers
	out["queues"] = queues
	return out


static func _record(p: Passenger) -> Dictionary:
	var record := {"flight_id": p.flight_id}
	for field in INT_FIELDS:
		record[field] = p.get(field)
	for field in BOOL_FIELDS:
		record[field] = p.get(field)
	for field in CELL_FIELDS:
		var cell: Vector2i = p.get(field)
		record[field] = [cell.x, cell.y]
	var path := []
	for cell in p.path:
		path.append([cell.x, cell.y])
	record["path"] = path
	var apron := []
	for point in p.apron:
		apron.append([point.x, point.y, point.z])
	record["apron"] = apron
	return record


static func _top_problem(data: Dictionary) -> String:
	for key in KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not _whole(data["save_version"]) or int(data["save_version"]) != PassengerSim.SAVE_VERSION:
		return "save_version must be %d" % PassengerSim.SAVE_VERSION
	if not SimClock.is_int64_string(data["tick"]) or str(data["tick"]).begins_with("-"):
		return "tick must be a decimal string, 0 or more"
	if not SimClock.is_int64_string(data["last_batch_seed"]):
		return "last_batch_seed must be a decimal string"
	if not _whole(data["next_id"]) or int(data["next_id"]) < 1:
		return "next_id must be a whole number, 1 or more"
	for key in ["schedule", "passengers", "queues", "no_shows", "flight_results", "scheduled"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return "%s must be an array" % key
	for key in ["made", "missed"]:
		if not _whole(data[key]) or int(data[key]) < 0:
			return "%s must be a whole number, 0 or more" % key
	return ""


static func _spawn_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY or not (entry.has("tick") and entry.has("flight")):
		return "a schedule entry is malformed"
	if not entry.has("variant") or not _whole(entry["tick"]) or not _whole(entry["variant"]):
		return "a schedule entry needs whole tick and variant"
	if typeof(entry["flight"]) != TYPE_STRING or int(entry["variant"]) not in [0, 1]:
		return "a schedule entry has a bad flight or variant"
	if not entry.has("arrival") or not _arrival_ok(entry["arrival"]):
		return "a schedule entry needs an arrival type"
	return ""


static func _arrival_ok(value: Variant) -> bool:
	return _whole(value) and int(value) >= 0 and int(value) < ArrivalTypes.Type.size()


## A Passenger from its record, or null when the record is malformed.
static func _passenger(entry: Variant, grid: BuildGrid, next_id: int) -> Passenger:
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	var record: Dictionary = entry
	for field in INT_FIELDS + CELL_FIELDS + BOOL_FIELDS + ["flight_id", "path", "apron"]:
		if not record.has(field):
			return null
	var p := Passenger.new()
	if not _fill(p, record, grid):
		return null
	var variant_ok := p.variant in [0, 1] and _arrival_ok(p.arrival_type)
	var range_ok := (
		p.mood >= 0
		and p.mood <= PassengerSim.MOOD_MAX
		and p.seg_mm >= 0
		and p.apron_mm >= 0
		and p.apron_mm <= p.apron_total_mm()
		and p.odometer_mm >= 0
		and p.hunger >= 0
		and p.hunger <= CafeSim.HUNGER_MAX
		and p.cafe_cooldown >= 0
	)
	var stage_ok := (
		p.stage >= 0
		and p.stage < Passenger.Stage.size()
		and p.missed_stage >= 0
		and p.missed_stage < Passenger.Stage.size()
	)
	var stuck_ok := (
		p.stuck >= 0
		and p.stuck < Passenger.Stuck.size()
		and p.missed_stuck >= 0
		and p.missed_stuck < Passenger.Stuck.size()
	)
	var index_ok := p.path_index >= 0 and p.path_index < maxi(p.path.size(), 1)
	if (
		not (variant_ok and range_ok and stage_ok and stuck_ok and index_ok)
		or p.id < 1
		or p.id >= next_id
	):
		return null
	return p


static func _fill(p: Passenger, record: Dictionary, grid: BuildGrid) -> bool:
	if typeof(record["flight_id"]) != TYPE_STRING:
		return false
	p.flight_id = record["flight_id"]
	for field in INT_FIELDS:
		if not _whole(record[field]):
			return false
		p.set(field, int(record[field]))
	for field in BOOL_FIELDS:
		if typeof(record[field]) != TYPE_BOOL:
			return false
		p.set(field, record[field])
	for field in CELL_FIELDS:
		var cell: Variant = _cell(record[field], grid, field != "at")
		if cell == null:
			return false
		p.set(field, cell)
	if typeof(record["path"]) != TYPE_ARRAY or typeof(record["apron"]) != TYPE_ARRAY:
		return false
	for value in record["path"]:
		var cell: Variant = _cell(value, grid, false)
		if cell == null:
			return false
		p.path.append(cell)
	for value in record["apron"]:
		if typeof(value) != TYPE_ARRAY or value.size() != 3:
			return false
		for axis in value:
			if typeof(axis) not in [TYPE_INT, TYPE_FLOAT]:
				return false
			if not is_finite(axis) or absf(axis) > BuildGrid.MAX_ORIGIN_M:
				return false
		p.apron.append(Vector3(value[0], value[1], value[2]))
	return true


## A cell from [x, y], or null. NO_CELL is allowed only when `may_be_none`.
static func _cell(value: Variant, grid: BuildGrid, may_be_none: bool) -> Variant:
	if (
		typeof(value) != TYPE_ARRAY
		or value.size() != 2
		or not _whole(value[0])
		or not _whole(value[1])
	):
		return null
	var cell := Vector2i(int(value[0]), int(value[1]))
	if grid.in_bounds(cell) or (may_be_none and cell == Passenger.NO_CELL):
		return cell
	return null


## {flight: {cause: count}} from the saved list, or a dictionary with "error".
static func _no_shows(list: Array) -> Dictionary:
	var out := {}
	for entry in list:
		var ok: bool = typeof(entry) == TYPE_DICTIONARY and entry.has("flight")
		ok = ok and typeof(entry["flight"]) == TYPE_STRING and not out.has(entry["flight"])
		for cause in NO_SHOW_CAUSES:
			ok = ok and entry.has(cause) and _whole(entry[cause]) and int(entry[cause]) >= 0
		if not ok:
			return {"error": "a no-show entry is malformed or repeated"}
		out[entry["flight"]] = {}
		for cause in NO_SHOW_CAUSES:
			out[entry["flight"]][cause] = int(entry[cause])
	return out


## {flight: {"made", "missed", "causes": {Vector2i(stage, stuck): count}}} from
## the saved list, or a dictionary with "error". The causes add up to "missed".
static func _flight_results(list: Array) -> Dictionary:
	var out := {}
	for entry in list:
		var ok: bool = typeof(entry) == TYPE_DICTIONARY
		for key in ["flight", "made", "missed", "causes"]:
			ok = ok and entry.has(key)
		ok = ok and typeof(entry["flight"]) == TYPE_STRING and not out.has(entry["flight"])
		ok = ok and _whole(entry["made"]) and int(entry["made"]) >= 0
		ok = ok and _whole(entry["missed"]) and int(entry["missed"]) >= 0
		ok = ok and typeof(entry["causes"]) == TYPE_ARRAY
		var causes := {}
		var total := 0
		for cause in entry["causes"] if ok else []:
			var cause_ok: bool = typeof(cause) == TYPE_DICTIONARY
			for key in ["stage", "stuck", "count"]:
				cause_ok = cause_ok and cause.has(key) and _whole(cause[key])
			if not cause_ok:
				ok = false
				break
			var at := Vector2i(int(cause["stage"]), int(cause["stuck"]))
			var count := int(cause["count"])
			var in_range := at.x >= 0 and at.x < Passenger.Stage.size()
			in_range = in_range and at.y >= 0 and at.y < Passenger.Stuck.size() and count > 0
			if not in_range or causes.has(at):
				ok = false
				break
			causes[at] = count
			total += count
		if not ok or total != int(entry["missed"]):
			return {"error": "a flight result is malformed, repeated or does not add up"}
		out[entry["flight"]] = {
			"made": int(entry["made"]), "missed": int(entry["missed"]), "causes": causes
		}
	return out


## "" when the totals cover what the flights' results and the retained settled
## passengers say, otherwise what is wrong. Retired passengers are only in the
## totals and the results, so these can only be at least what is still listed.
static func _totals_problem(data: Dictionary, results: Dictionary, passengers: Array) -> String:
	var made := {}
	var missed := {}
	for p: Passenger in passengers:
		if p.stage == Passenger.Stage.MADE:
			made[p.flight_id] = int(made.get(p.flight_id, 0)) + 1
		elif p.stage == Passenger.Stage.MISSED:
			missed[p.flight_id] = int(missed.get(p.flight_id, 0)) + 1
	var made_sum := 0
	var missed_sum := 0
	for flight in results:
		made_sum += results[flight]["made"]
		missed_sum += results[flight]["missed"]
	for flight in made:
		if int(results.get(flight, {}).get("made", 0)) < made[flight]:
			return "flight %s has fewer made results than made passengers" % flight
	for flight in missed:
		if int(results.get(flight, {}).get("missed", 0)) < missed[flight]:
			return "flight %s has fewer missed results than missed passengers" % flight
	if int(data["made"]) < made_sum or int(data["missed"]) < missed_sum:
		return "the made or missed total is below the flights' results"
	# Ids 1 to next_id - 1 were handed out, so no more passengers than that
	# can have settled. Each total is bounded before the sum, so it cannot wrap.
	var spawned := int(data["next_id"]) - 1
	if int(data["made"]) > spawned or int(data["missed"]) > spawned:
		return "the made or missed total is above the passengers ever spawned"
	if int(data["made"]) > spawned - int(data["missed"]):
		return "the made and missed totals together are above the passengers ever spawned"
	return ""


static func _queues(list: Array, ids: Dictionary) -> Dictionary:
	var queues := {}
	for entry in list:
		var ok := typeof(entry) == TYPE_DICTIONARY
		for key in ["station", "lane", "holding", "serving"]:
			ok = ok and entry.has(key)
		ok = ok and _whole(entry["station"]) and _whole(entry["serving"])
		ok = ok and typeof(entry["lane"]) == TYPE_ARRAY and typeof(entry["holding"]) == TYPE_ARRAY
		if not ok:
			return {"error": "a queue entry is malformed"}
		var lane := []
		var holding := []
		for pair in [[entry["lane"], lane], [entry["holding"], holding]]:
			for id in pair[0]:
				if not _whole(id) or not ids.has(int(id)):
					return {"error": "a queue names unknown passenger %s" % str(id)}
				pair[1].append(int(id))
		var serving := int(entry["serving"])
		if serving != 0 and not ids.has(serving):
			return {"error": "a queue serves unknown passenger %d" % serving}
		queues[int(entry["station"])] = {"lane": lane, "holding": holding, "serving": serving}
	return queues


static func _whole(value: Variant) -> bool:
	return WholeNumber.is_whole(value)
