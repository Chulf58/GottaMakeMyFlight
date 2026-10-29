class_name PassengerSnapshot
extends RefCounted
## The JSON shape of PassengerSim's state, and its checks on load. Committed
## paths, queue order, service ends, seat claims, apron progress and pending
## replans are all saved, so nothing is recomputed differently after a load.
## Cafe visits and counter queues go under "cafe" (CafeSnapshot), toilet
## visits under "toilet" (ToiletSnapshot), kiosk visits under "shop"
## (ShopSnapshot), security service under "security"
## (SecurityRuntime.to_list()) with each passenger's phase, remaining work and
## resolved incident on its record.
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
	"security",
	"toilet",
	"shop",
]
## The last version before the security traits, migrated on load.
const V6 := 6
## The last version before the security runtime, migrated on load.
const V7 := 7
## The last version before the shorter lane unpack, migrated on load.
const V8 := 8
## The last version before the toilet need and visits, migrated on load.
const V9 := 9
## The last version before boredom, migrated on load.
const V10 := 10
## A version 8 lane started its unpack work at 6 ticks plus 8 per bag.
const V8_UNPACK_TICKS := 6
const V8_UNPACK_BAG_TICKS := 8
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
	"carry_on",
	"security_phase",
	"security_work",
	"toilet_need",
	"toilet_cooldown",
	"boredom",
	"shop_cooldown",
]
const CELL_FIELDS := ["at", "seat_cell", "seat_front"]
const BOOL_FIELDS := ["late", "cleared", "needs_replan", "liquids", "alarm", "incident_resolved"]


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
		"security": sim.security.to_list(),
		"toilet": ToiletSnapshot.save(sim.toilets),
		"shop": ShopSnapshot.save(sim.shops),
	}


## A dictionary with the restored state, or with an "error" key.
static func load(saved: Dictionary, grid: BuildGrid) -> Dictionary:
	var data := _migrated(saved)
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
	var toilet := ToiletSnapshot.load(data["toilet"], ids, grid, out["tick"])
	if toilet.has("error"):
		return toilet
	for id: int in toilet["visits"]:
		if (cafe["visits"] as Dictionary).has(id):
			return {"error": "passenger %d has both a cafe and a toilet visit" % id}
	out["toilet"] = toilet
	var shop := ShopSnapshot.load(data["shop"], ids, grid, out["tick"])
	if shop.has("error"):
		return shop
	for id: int in shop["visits"]:
		if (cafe["visits"] as Dictionary).has(id) or (toilet["visits"] as Dictionary).has(id):
			return {"error": "passenger %d has a shop visit and another" % id}
	out["shop"] = shop
	var queues := _queues(data["queues"], ids)
	if queues.has("error"):
		return queues
	var security := _security(data["security"], ids, queues, grid)
	if security.has("error"):
		return security
	out["security"] = security["records"]
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


## A version 6, 7, 8, 9 or 10 save as the current version, nothing drawn from
## the sim RNG; each step runs in turn from the save's own version. Version 6 to
## 7: every passenger gets zero bags and no liquids or alarm. Version 7 to 8:
## no passenger has a security phase, except that a basic scanner's passenger
## in service keeps that service exactly as it was: SCAN with the ticks left
## to its saved service end as work, its incident counted as resolved, so it
## ends on the same tick with no repack. Version 8 to 9: unpack work left is
## scaled from the old start (6 + 8 per bag) to the new one, rounded up so a
## passenger still unpacking keeps at least 1; a value past the old start is
## left as it is and refused. Version 9 to 10: every passenger gets the toilet
## need ToiletSim.migrated_need() gives its id and no cooldown, and there are
## no toilet visits. Version 10 to 11: every passenger gets the boredom
## BoredomSim.start_of() gives its id; its toilet need, cooldown and any toilet
## visit are kept as saved, and it gets no kiosk cooldown and no kiosk visits.
## Every step sets a field or block only when the save has none, so a value the
## save already holds is kept for the checks to accept or refuse. Any other save
## is returned as it is, for the checks to accept or refuse. The given
## dictionary is not edited.
static func _migrated(data: Dictionary) -> Dictionary:
	if (
		not _whole(data.get("save_version"))
		or int(data["save_version"]) not in [V6, V7, V8, V9, V10]
	):
		return data
	var out := data.duplicate(true)
	var passengers: Array = out["passengers"] if typeof(out.get("passengers")) == TYPE_ARRAY else []
	var from_version := int(out["save_version"])
	out["save_version"] = PassengerSim.SAVE_VERSION
	if from_version == V6:
		for record in passengers:
			if typeof(record) == TYPE_DICTIONARY:
				_set_missing(record, "carry_on", 0)
				_set_missing(record, "liquids", false)
				_set_missing(record, "alarm", false)
	if from_version <= V7:
		_add_security(out, passengers)
	if from_version == V8:
		_rescale_unpack(passengers)
	if from_version <= V9:
		_add_toilets(out, passengers)
	_add_boredom(out, passengers)
	return out


## Sets `key` on `record` only when the record has no such key.
static func _set_missing(record: Dictionary, key: String, value: Variant) -> void:
	if not record.has(key):
		record[key] = value


## Version 7 to 8: the security runtime's phases and station records. A save
## that already holds a "security" block keeps it and its queues as they are.
static func _add_security(out: Dictionary, passengers: Array) -> void:
	var by_id := {}
	for record in passengers:
		if typeof(record) == TYPE_DICTIONARY:
			_set_missing(record, "security_phase", SecurityRuntime.Phase.NONE)
			_set_missing(record, "security_work", 0)
			_set_missing(record, "incident_resolved", false)
			if _whole(record.get("id")):
				by_id[int(record["id"])] = record
	if out.has("security"):
		return
	var security := []
	var tick := str(out.get("tick")).to_int()
	var queues: Array = out["queues"] if typeof(out.get("queues")) == TYPE_ARRAY else []
	for entry in queues:
		if typeof(entry) != TYPE_DICTIONARY or not _whole(entry.get("serving")):
			continue
		var record: Dictionary = by_id.get(int(entry["serving"]), {})
		var in_scan: bool = _whole(record.get("stage")) and _whole(record.get("service_end"))
		if not in_scan or int(record["stage"]) != Passenger.Stage.SECURITY:
			continue
		record["security_phase"] = SecurityRuntime.Phase.SCAN
		record["security_work"] = maxi(int(record["service_end"]) - tick, 0)
		record["incident_resolved"] = true
		var id := int(entry["serving"])
		entry["serving"] = 0
		security.append(
			{
				"station": entry.get("station"),
				"admitted": [id],
				"returns": [],
				"main": id,
				"berth": 0
			}
		)
	out["security"] = security


## Version 9 to 10: a toilet need from each passenger's id, no cooldown and no
## visits. A record whose id is not a whole number is left for the checks.
static func _add_toilets(out: Dictionary, passengers: Array) -> void:
	for record in passengers:
		if typeof(record) != TYPE_DICTIONARY or not _whole(record.get("id")):
			continue
		_set_missing(record, "toilet_need", ToiletSim.migrated_need(int(record["id"])))
		_set_missing(record, "toilet_cooldown", 0)
	_set_missing(out, "toilet", {"visits": [], "deadlines_stale": false})


## Version 10 to 11: boredom from each passenger's id, no kiosk cooldown and
## no kiosk visits. A record whose id is not a whole number is left for the
## checks.
static func _add_boredom(out: Dictionary, passengers: Array) -> void:
	for record in passengers:
		if typeof(record) == TYPE_DICTIONARY and _whole(record.get("id")):
			_set_missing(record, "boredom", BoredomSim.start_of(int(record["id"])))
			_set_missing(record, "shop_cooldown", 0)
	_set_missing(out, "shop", {"visits": [], "deadlines_stale": false})


## Version 8 to 9: each passenger in UNPACK has its work left scaled to the new
## start, which depends on its bags. A passenger whose bags or work are not
## whole numbers, or whose work is past the old start, is left as it is for
## the checks to refuse.
static func _rescale_unpack(passengers: Array) -> void:
	for record in passengers:
		if typeof(record) != TYPE_DICTIONARY or not _whole(record.get("security_phase")):
			continue
		if int(record["security_phase"]) != SecurityRuntime.Phase.UNPACK:
			continue
		if not _whole(record.get("carry_on")) or not _whole(record.get("security_work")):
			continue
		var bags := int(record["carry_on"])
		var work := int(record["security_work"])
		if bags < 0 or bags > CarryOnTraits.MAX_BAGS or work < 0:
			continue
		var old_start := V8_UNPACK_TICKS + V8_UNPACK_BAG_TICKS * bags
		if work > old_start:
			continue
		var new_start := (
			SecurityRuntime.LANE_UNPACK_TICKS + SecurityRuntime.LANE_UNPACK_BAG_TICKS * bags
		)
		@warning_ignore("integer_division")
		record["security_work"] = (work * new_start + old_start - 1) / old_start


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
	for key in [
		"schedule", "passengers", "queues", "no_shows", "flight_results", "scheduled", "security"
	]:
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
		and p.toilet_need >= 0
		and p.toilet_need <= ToiletSim.NEED_MAX
		and p.toilet_cooldown >= 0
		and p.boredom >= 0
		and p.boredom <= BoredomSim.MAX
		and p.shop_cooldown >= 0
		and p.carry_on >= 0
		and p.carry_on <= CarryOnTraits.MAX_BAGS
		and p.security_phase >= 0
		and p.security_phase < SecurityRuntime.Phase.size()
		and p.security_work >= 0
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


## SecurityRuntime.records from the saved list, as {"records": ...}, or a
## dictionary with "error". Every passenger in Stage.SECURITY is admitted at
## exactly one station, its own, with a phase; nobody else has a phase or
## work; returns are the admitted passengers in RETURN; the main position and
## the berth are held by admitted passengers or nobody, as the station's tier
## allows (_service_problem()).
static func _security(
	list: Array, ids: Dictionary, queues: Dictionary, grid: BuildGrid
) -> Dictionary:
	var records := {}
	var station_of := {}
	for entry in list:
		var ok := typeof(entry) == TYPE_DICTIONARY
		for key in ["station", "admitted", "returns", "main", "berth"]:
			ok = ok and entry.has(key)
		ok = ok and _whole(entry["station"]) and _whole(entry["main"]) and _whole(entry["berth"])
		ok = (
			ok
			and typeof(entry["admitted"]) == TYPE_ARRAY
			and typeof(entry["returns"]) == TYPE_ARRAY
		)
		if not ok or records.has(int(entry["station"])) or (entry["admitted"] as Array).is_empty():
			return {"error": "a security entry is malformed, empty or repeated"}
		var station := int(entry["station"])
		var admitted := []
		for value in entry["admitted"]:
			var p: Passenger = ids.get(int(value)) if _whole(value) else null
			if p == null or station_of.has(p.id) or p.station != station:
				return {
					"error": "security at %d admits an unknown or misplaced passenger" % station
				}
			station_of[p.id] = station
			admitted.append(p.id)
		var returns := []
		for value in entry["returns"]:
			if not _whole(value) or not admitted.has(int(value)) or returns.has(int(value)):
				return {"error": "security at %d returns a passenger it has not admitted" % station}
			returns.append(int(value))
		for key in ["main", "berth"]:
			if int(entry[key]) != 0 and not admitted.has(int(entry[key])):
				return {"error": "security at %d gives its %s to nobody admitted" % [station, key]}
		records[station] = {
			"admitted": admitted,
			"returns": returns,
			"main": int(entry["main"]),
			"berth": int(entry["berth"])
		}
		var problem := _service_problem(station, records[station], ids, queues, grid)
		if problem != "":
			return {"error": "security at %d: %s" % [station, problem]}
	for id: int in ids:
		var p: Passenger = ids[id]
		var admitted := station_of.has(id)
		var phased := p.security_phase != SecurityRuntime.Phase.NONE
		var returning := admitted and (records[station_of[id]]["returns"] as Array).has(id)
		if (
			(p.stage == Passenger.Stage.SECURITY) != admitted
			or phased != admitted
			or (not admitted and p.security_work != 0)
			or returning != (p.security_phase == SecurityRuntime.Phase.RETURN)
		):
			return {"error": "passenger %d's security phase does not match its station" % id}
	return {"records": records}


## What is wrong with a station's service record, or "": the station must be
## a basic scanner or an arch on the grid, its admitted passengers must not
## also stand in any queue, holding list or service, and the record must keep
## the scheduler's rules for its tier (SecurityRuntime.record_problem()). An
## arch is judged as a lane; one that is no longer whole is dropped on the
## next tick.
static func _service_problem(
	station: int, record: Dictionary, ids: Dictionary, queues: Dictionary, grid: BuildGrid
) -> String:
	var object := grid.get_object(station)
	var def: StringName = StringName(object["def"]) if not object.is_empty() else &""
	if def != &"security_scanner" and def != SecurityLanes.ARCH:
		return "it is not a scanner or a security arch"
	var units := []
	for id: int in record["admitted"]:
		units.append(ids[id])
		for q: Dictionary in queues.values():
			if (
				(q["lane"] as Array).has(id)
				or (q["holding"] as Array).has(id)
				or q["serving"] == id
			):
				return "passenger %d is admitted and in a queue as well" % id
	return SecurityRuntime.record_problem(record, units, def == SecurityLanes.ARCH)


static func _whole(value: Variant) -> bool:
	return WholeNumber.is_whole(value)
