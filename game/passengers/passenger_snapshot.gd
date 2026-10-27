class_name PassengerSnapshot
extends RefCounted
## The JSON shape of PassengerSim's state, and its checks on load. Committed
## paths, queue order, service ends, seat claims, apron progress and pending
## replans are all saved, so nothing is recomputed differently after a load.
## Cafe visits and counter queues go under "cafe" (CafeSnapshot).
## Seat claims and walker counts are rebuilt from the passenger records.

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
]
const CELL_FIELDS := ["at", "seat_cell", "seat_front"]
const BOOL_FIELDS := ["late", "cleared", "needs_replan"]


static func save(
	sim: PassengerSim,
	passengers: Array[Passenger],
	schedule: Array[Dictionary],
	queues: Dictionary,
	next_id: int
) -> Dictionary:
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
		schedule.append(
			{
				"tick": int(entry["tick"]),
				"flight": entry["flight"],
				"variant": int(entry["variant"])
			}
		)
	var passengers: Array[Passenger] = []
	var ids := {}
	for entry in data["passengers"]:
		var p := _passenger(entry, grid, int(data["next_id"]))
		if p == null or ids.has(p.id):
			return {"error": "passenger record %s is malformed or repeated" % str(entry).left(80)}
		ids[p.id] = p
		passengers.append(p)
	var cafe := CafeSnapshot.load(data["cafe"], ids)
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
	for key in ["schedule", "passengers", "queues", "no_shows"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return "%s must be an array" % key
	return ""


static func _spawn_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY or not (entry.has("tick") and entry.has("flight")):
		return "a schedule entry is malformed"
	if not entry.has("variant") or not _whole(entry["tick"]) or not _whole(entry["variant"]):
		return "a schedule entry needs whole tick and variant"
	if typeof(entry["flight"]) != TYPE_STRING or int(entry["variant"]) not in [0, 1]:
		return "a schedule entry has a bad flight or variant"
	return ""


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
	var variant_ok := p.variant in [0, 1]
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
