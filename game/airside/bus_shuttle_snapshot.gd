class_name BusShuttleSnapshot
extends RefCounted
## Snapshot pack and checked validator for BusShuttleSim (SaveGame v49).

const SNAPSHOT_VERSION := 2
const BUS_KEYS := [
	"gate",
	"state",
	"inbound",
	"flight_id",
	"stand_id",
	"model",
	"exit",
	"start_tick",
	"arrive_tick",
	"load_tick",
	"last_board_tick",
	"unload_tick",
	"aboard",
]


static func pack(tick: int, buses: Dictionary) -> Dictionary:
	var gates := buses.keys()
	gates.sort()
	var list: Array[Dictionary] = []
	for gate: String in gates:
		var b: Dictionary = buses[gate]
		(
			list
			. append(
				{
					"gate": gate,
					"state": int(b["state"]),
					"inbound": bool(b.get("inbound", false)),
					"flight_id": String(b["flight_id"]),
					"stand_id": String(b["stand_id"]),
					"model": String(b["model"]),
					"exit": int(b["exit"]),
					"start_tick": int(b["start_tick"]),
					"arrive_tick": int(b["arrive_tick"]),
					"load_tick": int(b["load_tick"]),
					"last_board_tick": int(b["last_board_tick"]),
					"unload_tick": int(b["unload_tick"]),
					"aboard": (b["aboard"] as Array).duplicate(),
				}
			)
		)
	return {
		"version": SNAPSHOT_VERSION,
		"tick": tick,
		"buses": list,
	}


static func checked(data: Variant, flights: FlightSim, by_id: Dictionary) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "bus shuttle snapshot must be a dictionary"}
	var d: Dictionary = data
	if (
		not WholeNumber.is_whole(d.get("version", -1))
		or int(d["version"]) != SNAPSHOT_VERSION
		or not WholeNumber.is_whole(d.get("tick", -1))
		or int(d["tick"]) < 0
		or typeof(d.get("buses", null)) != TYPE_ARRAY
	):
		return {"error": "malformed bus shuttle snapshot header"}
	var saved_tick := int(d["tick"])
	var bus_grounds := flights.bus_gate_grounds() if flights != null else {}
	var seen_gates := {}
	var claimed_pax := {}
	var out: Array[Dictionary] = []
	for raw: Variant in d["buses"]:
		var err := _entry_problem(
			raw, saved_tick, bus_grounds, flights, by_id, seen_gates, claimed_pax
		)
		if err != "":
			return {"error": err}
		out.append(_clean_entry(raw as Dictionary))
	for pid: int in by_id:
		var p: Passenger = by_id[pid]
		if p.stage == Passenger.Stage.ON_BUS and not claimed_pax.has(pid):
			return {"error": "passenger %d is ON_BUS without a shuttle bus" % pid}
	return {"tick": saved_tick, "buses": out}


static func stage(data: Dictionary, staged: Dictionary, make_flights: Callable) -> String:
	var by_id := {}
	for p: Passenger in staged["passengers"]["passengers"]:
		by_id[p.id] = p
	var staged_flights: FlightSim = staged.get("staged_flights")
	var own := staged_flights == null and staged.has("flights_data")
	if own:
		staged_flights = make_flights.call(staged)
		staged_flights.from_snapshot(staged["flights_data"])
	var res := checked(data, staged_flights, by_id)
	if own:
		staged_flights.free()
	if res.has("error"):
		return str(res["error"])
	staged["buses"] = res
	return ""


static func _entry_problem(
	raw: Variant,
	saved_tick: int,
	bus_grounds: Dictionary,
	flights: FlightSim,
	by_id: Dictionary,
	seen_gates: Dictionary,
	claimed_pax: Dictionary
) -> String:
	if typeof(raw) != TYPE_DICTIONARY or not (raw as Dictionary).has_all(BUS_KEYS):
		return "a bus snapshot entry is missing required fields"
	var e: Dictionary = raw
	var gate := str(e["gate"])
	if typeof(e["gate"]) != TYPE_STRING or not bus_grounds.has(gate):
		return "bus entry refers to unknown bus gate '%s'" % gate
	if seen_gates.has(gate):
		return "bus gate '%s' is listed twice" % gate
	seen_gates[gate] = true
	if not WholeNumber.is_whole(e["state"]) or int(e["state"]) < 0 or int(e["state"]) > 4:
		return "bus '%s' has invalid state" % gate
	if typeof(e["inbound"]) != TYPE_BOOL:
		return "bus '%s' inbound flag must be true or false" % gate
	var state := int(e["state"])
	if not WholeNumber.is_whole(e["exit"]) or int(e["exit"]) != int(bus_grounds[gate]["exit"]):
		return "bus '%s' exit door does not match the bus gate" % gate
	return _flight_and_aboard_problem(e, gate, state, saved_tick, flights, by_id, claimed_pax)


static func _flight_and_aboard_problem(
	e: Dictionary,
	gate: String,
	state: int,
	saved_tick: int,
	flights: FlightSim,
	by_id: Dictionary,
	claimed_pax: Dictionary
) -> String:
	var fid := str(e["flight_id"])
	var inbound := bool(e["inbound"])
	if (
		typeof(e["flight_id"]) != TYPE_STRING
		or typeof(e["stand_id"]) != TYPE_STRING
		or typeof(e["model"]) != TYPE_STRING
	):
		return "bus '%s' flight fields must be text" % gate
	var stand_id := String(e["stand_id"])
	var model := String(e["model"])
	if state == BusShuttleSim.State.IDLE_AT_BAY:
		if (
			inbound
			or fid != ""
			or stand_id != ""
			or model != ""
			or typeof(e["aboard"]) != TYPE_ARRAY
			or not (e["aboard"] as Array).is_empty()
		):
			return "idle bus '%s' may not hold a flight or passengers" % gate
		return ""
	if fid == "" or (flights != null and flights.state_of(fid) < 0):
		return "bus '%s' refers to unknown flight '%s'" % [gate, fid]
	if not PlaneModels.PLANES.has(model):
		return "bus '%s' refers to unknown plane model '%s'" % [gate, model]
	if flights != null and flights.remote_ground_source.is_valid():
		if not flights.remote_stand_grounds().has(stand_id):
			return "bus '%s' refers to unknown remote stand '%s'" % [gate, stand_id]
	for key in ["start_tick", "arrive_tick", "load_tick", "last_board_tick", "unload_tick"]:
		if not WholeNumber.is_whole(e[key]):
			return "bus '%s' tick field '%s' must be whole" % [gate, key]
	if int(e["start_tick"]) > saved_tick or int(e["arrive_tick"]) < int(e["start_tick"]):
		return "bus '%s' drive ticks are inconsistent" % gate
	return _aboard_problem(e, gate, fid, state, inbound, by_id, claimed_pax)


static func _aboard_problem(
	e: Dictionary,
	gate: String,
	fid: String,
	state: int,
	inbound: bool,
	by_id: Dictionary,
	claimed_pax: Dictionary
) -> String:
	if typeof(e["aboard"]) != TYPE_ARRAY:
		return "bus '%s' aboard list must be a list" % gate
	var aboard: Array = e["aboard"]
	if inbound and state == BusShuttleSim.State.DRIVING_OUT and not aboard.is_empty():
		return "inbound bus '%s' driving out must be empty" % gate
	if aboard.size() > BusGatePairing.BUS_CAPACITY:
		return "bus '%s' exceeds BUS_CAPACITY" % gate
	for raw_pid: Variant in aboard:
		if not WholeNumber.is_whole(raw_pid):
			return "bus '%s' holds non-integer passenger id" % gate
		var pid := int(raw_pid)
		if claimed_pax.has(pid) or not by_id.has(pid):
			return "bus '%s' holds invalid or duplicate passenger %d" % [gate, pid]
		var p: Passenger = by_id[pid]
		if p.stage != Passenger.Stage.ON_BUS or p.flight_id != fid:
			return "bus '%s' passenger %d does not match stage/flight" % [gate, pid]
		if p.is_arriving() != inbound:
			return "bus '%s' passenger %d direction does not match trip" % [gate, pid]
		claimed_pax[pid] = gate
	return ""


static func _clean_entry(e: Dictionary) -> Dictionary:
	var aboard: Array[int] = []
	for pid: Variant in e["aboard"]:
		aboard.append(int(pid))
	return {
		"gate": String(e["gate"]),
		"state": int(e["state"]),
		"inbound": bool(e["inbound"]),
		"flight_id": String(e["flight_id"]),
		"stand_id": String(e["stand_id"]),
		"model": String(e["model"]),
		"exit": int(e["exit"]),
		"start_tick": int(e["start_tick"]),
		"arrive_tick": int(e["arrive_tick"]),
		"load_tick": int(e["load_tick"]),
		"last_board_tick": int(e["last_board_tick"]),
		"unload_tick": int(e["unload_tick"]),
		"aboard": aboard,
	}
