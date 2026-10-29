class_name LandsideSnapshot
extends RefCounted
## The JSON shape of the landside save part and its checks on load: the
## arrival bookings PassengerSim keeps (ArrivalBookings), with the transport
## misses counted so far, and LandsideSim's vehicles and built lots. Berth and
## slot holders are rebuilt from the vehicles. Every booking saved is AWAITING
## (vehicle 0) or IN_VEHICLE in exactly the one vehicle that lists it.

const SAVE_VERSION := 1
const KEYS := [
	"save_version",
	"tick",
	"next_booking_id",
	"bookings",
	"missed",
	"missed_total",
	"next_vehicle_id",
	"vehicles",
	"lots_built",
]
const BOOKING_INTS := [
	"id", "party", "variant", "arrival", "unload_tick", "kind", "intent", "state", "vehicle"
]
const VEHICLE_INTS := [
	"id", "kind", "intent", "lane", "pos_mm", "stage", "stop", "lot", "stage_tick", "leave_tick"
]
## The lane each stage may stand on.
const STAGE_LANES := {
	LandsideVehicle.Stage.DRIVE: [LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.ACCESS],
	LandsideVehicle.Stage.QUEUE: [LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.ACCESS],
	LandsideVehicle.Stage.DWELL: [LandsideVehicle.Lane.BERTH],
	LandsideVehicle.Stage.PARKED: [LandsideVehicle.Lane.SLOT],
	LandsideVehicle.Stage.LEAVE: [LandsideVehicle.Lane.ROAD_OUT, LandsideVehicle.Lane.LOT_EXIT],
}


static func save(
	sim: LandsideSim,
	vehicles: Array[LandsideVehicle],
	next_vehicle_id: int,
	bookings: ArrivalBookings,
	at_tick: int
) -> Dictionary:
	var booking_list := []
	for id in bookings.booking_ids():
		var b := bookings.get_booking(id)
		(
			booking_list
			. append(
				{
					"id": b.id,
					"party": b.party,
					"flight": b.flight_id,
					"variant": b.variant,
					"arrival": b.arrival,
					"unload_tick": b.unload_tick,
					"kind": b.kind,
					"intent": b.intent,
					"state": b.state,
					"vehicle": b.vehicle,
				}
			)
		)
	var missed := []
	var flights: Array = bookings.missed_by_flight.keys()
	flights.sort()
	for flight in flights:
		missed.append({"flight": flight, "count": bookings.missed_by_flight[flight]})
	var vehicle_list := []
	for v in vehicles:
		var record := {"bookings": v.bookings.duplicate()}
		for field in VEHICLE_INTS:
			record[field] = v.get(field)
		vehicle_list.append(record)
	return {
		"save_version": SAVE_VERSION,
		"tick": str(at_tick),
		"next_booking_id": bookings.next_id(),
		"bookings": booking_list,
		"missed": missed,
		"missed_total": bookings.missed_total,
		"next_vehicle_id": next_vehicle_id,
		"vehicles": vehicle_list,
		"lots_built": sim.lots_built.duplicate(),
	}


## The restored state, or a dictionary with "error". Checked against
## `definition` (lanes, berths, slots and lot spots).
static func load(data: Dictionary, definition: LandsideDefinition) -> Dictionary:
	var problem := _top_problem(data, definition)
	if problem != "":
		return {"error": problem}
	var out := {
		"tick": str(data["tick"]).to_int(),
		"next_booking_id": int(data["next_booking_id"]),
		"next_vehicle_id": int(data["next_vehicle_id"]),
		"missed_total": int(data["missed_total"]),
	}
	var built: Array[bool] = []
	built.assign(data["lots_built"])
	out["lots_built"] = built
	var missed := {}
	var missed_sum := 0
	for entry in data["missed"]:
		var ok: bool = typeof(entry) == TYPE_DICTIONARY and entry.has("flight")
		ok = ok and entry.has("count") and _whole(entry["count"]) and int(entry["count"]) > 0
		ok = ok and typeof(entry["flight"]) == TYPE_STRING and not missed.has(entry["flight"])
		if not ok:
			return {"error": "a missed entry is malformed or repeated"}
		missed[entry["flight"]] = int(entry["count"])
		missed_sum += int(entry["count"])
	if missed_sum > out["missed_total"]:
		return {"error": "the missed total is below the flights' misses"}
	out["missed"] = missed
	var bookings := _bookings(data["bookings"], out["next_booking_id"])
	if bookings.has("error"):
		return bookings
	out["bookings"] = bookings["list"]
	var vehicles := _vehicles(data["vehicles"], out["next_vehicle_id"], definition, built)
	if vehicles.has("error"):
		return vehicles
	out["vehicles"] = vehicles["list"]
	problem = _aboard_problem(bookings["list"], vehicles["list"])
	if problem != "":
		return {"error": problem}
	return out


static func _top_problem(data: Dictionary, definition: LandsideDefinition) -> String:
	for key in data.keys():
		if not KEYS.has(key):
			return "unknown key '%s'" % key
	for key in KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not _whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	if not SimClock.is_int64_string(data["tick"]) or str(data["tick"]).begins_with("-"):
		return "tick must be a decimal string, 0 or more"
	for key in ["next_booking_id", "next_vehicle_id"]:
		if not _whole(data[key]) or int(data[key]) < 1:
			return "%s must be a whole number, 1 or more" % key
	if not _whole(data["missed_total"]) or int(data["missed_total"]) < 0:
		return "missed_total must be a whole number, 0 or more"
	for key in ["bookings", "missed", "vehicles", "lots_built"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return "%s must be an array" % key
	if (data["lots_built"] as Array).size() != definition.lots.size():
		return "lots_built must have one entry per lot spot"
	for flag in data["lots_built"]:
		if typeof(flag) != TYPE_BOOL:
			return "lots_built must hold true or false"
	return ""


## {"list": Array[ArrivalBooking]} in id order, or {"error"}.
static func _bookings(list: Array, next_id: int) -> Dictionary:
	var out: Array[ArrivalBooking] = []
	var last := 0
	for entry in list:
		var ok: bool = typeof(entry) == TYPE_DICTIONARY and entry.has("flight")
		for field in BOOKING_INTS:
			ok = ok and entry.has(field) and _whole(entry[field])
		ok = ok and typeof(entry["flight"]) == TYPE_STRING
		if not ok:
			return {"error": "a booking is malformed"}
		var b := ArrivalBooking.new()
		b.flight_id = entry["flight"]
		for field in BOOKING_INTS:
			b.set(field, int(entry[field]))
		var problem := _booking_problem(b, last, next_id)
		if problem != "":
			return {"error": "booking %d: %s" % [b.id, problem]}
		last = b.id
		out.append(b)
	return {"list": out}


static func _booking_problem(b: ArrivalBooking, last: int, next_id: int) -> String:
	if b.id <= last or b.id >= next_id or b.party < 1 or b.party > b.id:
		return "its id or party is out of order"
	if b.variant not in [0, 1] or b.arrival < 0 or b.arrival >= ArrivalTypes.Type.size():
		return "its variant or arrival type is out of range"
	if b.kind < 0 or b.kind >= LandsideVehicle.Kind.size():
		return "its vehicle kind is out of range"
	if b.intent < 0 or b.intent >= LandsideVehicle.Intent.size() or b.unload_tick < 0:
		return "its intent or unload tick is out of range"
	if b.state == ArrivalBooking.State.AWAITING and b.vehicle == 0:
		return ""
	if b.state == ArrivalBooking.State.IN_VEHICLE and b.vehicle > 0:
		return ""
	return "it is neither awaiting with no vehicle nor in a vehicle"


## {"list": Array[LandsideVehicle]} in id order, or {"error"}.
static func _vehicles(
	list: Array, next_id: int, definition: LandsideDefinition, built: Array[bool]
) -> Dictionary:
	var out: Array[LandsideVehicle] = []
	var held := {}
	var last := 0
	for entry in list:
		var ok: bool = typeof(entry) == TYPE_DICTIONARY and entry.has("bookings")
		for field in VEHICLE_INTS:
			ok = ok and entry.has(field) and _whole(entry[field])
		ok = ok and typeof(entry["bookings"]) == TYPE_ARRAY
		if not ok:
			return {"error": "a vehicle is malformed"}
		var v := LandsideVehicle.new()
		for field in VEHICLE_INTS:
			v.set(field, int(entry[field]))
		for id in entry["bookings"]:
			if not _whole(id) or v.bookings.has(int(id)):
				return {"error": "vehicle %d lists a bad or repeated booking" % v.id}
			v.bookings.append(int(id))
		var problem := _vehicle_problem(v, last, next_id, definition, built)
		var key := ""
		match v.lane:
			LandsideVehicle.Lane.BERTH:
				key = "berth %d" % v.stop
			LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT:
				key = "slot %d:%d" % [v.lot, v.stop]
		if problem == "" and key != "":
			problem = "its %s is taken twice" % key if held.has(key) else ""
			held[key] = true
		if problem != "":
			return {"error": "vehicle %d: %s" % [v.id, problem]}
		last = v.id
		out.append(v)
	return {"list": out}


static func _vehicle_problem(
	v: LandsideVehicle, last: int, next_id: int, definition: LandsideDefinition, built: Array[bool]
) -> String:
	if v.id <= last or v.id >= next_id:
		return "its id is out of order"
	if v.kind < 0 or v.kind >= LandsideVehicle.Kind.size():
		return "its kind is out of range"
	if v.intent < 0 or v.intent >= LandsideVehicle.Intent.size():
		return "its intent is out of range"
	if not STAGE_LANES.has(v.stage) or not (STAGE_LANES[v.stage] as Array).has(v.lane):
		return "its stage and lane do not go together"
	var lot_lane := (
		v.lane
		in [LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT, LandsideVehicle.Lane.LOT_EXIT]
	)
	if lot_lane != (v.lot >= 0) or v.lot >= definition.lots.size():
		return "its lot spot does not fit its lane"
	if lot_lane and not built[v.lot]:
		return "it uses a lot spot with no car park"
	var stops := -1
	match v.lane:
		LandsideVehicle.Lane.BERTH:
			stops = definition.curb.berths.size()
		LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT:
			stops = definition.lots[v.lot].slots.size()
	if (stops < 0 and v.stop != -1) or (stops >= 0 and (v.stop < 0 or v.stop >= stops)):
		return "its berth or slot is out of range"
	var length := _lane_length(v, definition)
	if v.lane != LandsideVehicle.Lane.ROAD_IN and (v.pos_mm < 0 or v.pos_mm > length):
		return "its position is off its lane"
	if v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm > definition.curb.stop_mm:
		return "it stands past the curb on road_in"
	if (v.stage == LandsideVehicle.Stage.PARKED) != (v.leave_tick > 0):
		return "only a parked car has a leave tick"
	if v.stage == LandsideVehicle.Stage.LEAVE and not v.bookings.is_empty():
		return "a leaving car carries passengers"
	if v.stage_tick < 0:
		return "its stage tick is negative"
	return ""


static func _lane_length(v: LandsideVehicle, definition: LandsideDefinition) -> int:
	match v.lane:
		LandsideVehicle.Lane.ROAD_OUT:
			return LandsideDefinition.length_mm(definition.road_out)
		LandsideVehicle.Lane.ACCESS:
			return LandsideDefinition.length_mm(definition.lots[v.lot].access)
		LandsideVehicle.Lane.LOT_EXIT:
			return LandsideDefinition.length_mm(definition.lots[v.lot].exit)
		LandsideVehicle.Lane.ROAD_IN:
			return LandsideDefinition.length_mm(definition.road_in)
	return 0


## Every IN_VEHICLE booking is listed by its vehicle, and every booking a
## vehicle lists is IN_VEHICLE there.
static func _aboard_problem(
	bookings: Array[ArrivalBooking], vehicles: Array[LandsideVehicle]
) -> String:
	var by_id := {}
	for b in bookings:
		by_id[b.id] = b
	var listed := {}
	for v in vehicles:
		for id in v.bookings:
			var b: ArrivalBooking = by_id.get(id)
			if b == null or b.state != ArrivalBooking.State.IN_VEHICLE or b.vehicle != v.id:
				return "vehicle %d lists booking %d, which is not aboard it" % [v.id, id]
			listed[id] = true
	for b in bookings:
		if b.state == ArrivalBooking.State.IN_VEHICLE and not listed.has(b.id):
			return "booking %d is in vehicle %d, which does not list it" % [b.id, b.vehicle]
	return ""


static func _whole(value: Variant) -> bool:
	return WholeNumber.is_whole(value)
