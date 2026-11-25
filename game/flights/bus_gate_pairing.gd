class_name BusGatePairing
extends RefCounted
## Auto-pairing between Remote Stands (R1..Rn) and nearest free Bus Gates (D..Z).
## A Bus Gate is held only for [TAXI_IN, DOORS_CLOSED + BUS_RETURN_MARGIN_TICKS]
## so one Bus Gate can serve multiple staggered Remote Stands. Pure helpers.

const BUS_CAPACITY := 40
const BUS_RETURN_MARGIN_TICKS := 120


static func is_remote_stand_id(stand_id: String) -> bool:
	if not stand_id.begins_with(RemoteStands.ID_PREFIX):
		return false
	var suffix := stand_id.substr(RemoteStands.ID_PREFIX.length())
	return suffix.is_valid_int() and int(suffix) >= 1


static func remote_sort_less(a: String, b: String) -> bool:
	var ra := is_remote_stand_id(a)
	var rb := is_remote_stand_id(b)
	if ra != rb:
		return not ra
	if ra and rb:
		return (
			int(a.substr(RemoteStands.ID_PREFIX.length()))
			< int(b.substr(RemoteStands.ID_PREFIX.length()))
		)
	return a < b


static func stand_id_of(contract: Dictionary) -> String:
	return String(contract.get(FlightContract.STAND_KEY, contract.get("gate", "")))


static func is_remote_contract(contract: Dictionary) -> bool:
	var stand_id := stand_id_of(contract)
	return stand_id != "" and stand_id != String(contract.get("gate", ""))


static func bus_hold_span(starts: Array) -> Array[int]:
	return [
		int(starts[FlightSim.State.TAXI_IN]),
		int(starts[FlightSim.State.DOORS_CLOSED]) + BUS_RETURN_MARGIN_TICKS,
	]


static func bus_holds_overlap(a_starts: Array, b_starts: Array) -> bool:
	var a := bus_hold_span(a_starts)
	var b := bus_hold_span(b_starts)
	return FlightTimetable.holds_overlap(a[0], a[1], b[0], b[1])


static func is_charter_allowed(terms: Dictionary, stand_id: String) -> bool:
	if not is_remote_stand_id(stand_id):
		return true
	return not is_charter_over_capacity(terms)


static func is_charter_over_capacity(terms: Dictionary) -> bool:
	return (
		FlightContract.is_charter(terms) and int(terms.get("booked_passengers", 0)) > BUS_CAPACITY
	)


static func stand_point_2d(stand: Dictionary) -> Vector2:
	var pt := StandPlacement.stand_point(stand)
	return Vector2(pt.x, pt.z)


static func bus_distance_sq(bus_grounds: Dictionary, bus_gate: String, stand: Dictionary) -> float:
	if not bus_grounds.has(bus_gate):
		return 0.0
	var info: Dictionary = bus_grounds[bus_gate]
	var pt: Vector2 = info.get("point", Vector2.ZERO)
	return pt.distance_squared_to(stand_point_2d(stand))


static func bus_grounds_on(on_grid: BuildGrid, on_bindings: Array[Dictionary]) -> Dictionary:
	var out := {}
	if on_grid == null:
		return out
	for binding in on_bindings:
		if not GateDesks.is_bus_binding(binding):
			continue
		var stand := StandPlacement.for_exit(on_grid, int(binding["exit"]))
		var bay := BusBays.bay_rect(stand)
		if not bay.has_area():
			continue
		out[String(binding["gate"])] = {
			"gate": String(binding["gate"]),
			"desk": int(binding["desk"]),
			"exit": int(binding["exit"]),
			"bay": bay,
			"point": bay.get_center(),
		}
	return out


static func sorted_bus_gates(
	bus_gates: Array[String], bus_grounds: Dictionary, stand: Dictionary
) -> Array[String]:
	var out := bus_gates.duplicate()
	out.sort_custom(
		func(a: String, b: String) -> bool:
			var da := bus_distance_sq(bus_grounds, a, stand)
			var db := bus_distance_sq(bus_grounds, b, stand)
			if not is_equal_approx(da, db):
				return da < db
			return a < b
	)
	return out


## Builds an assigned contract probe for `terms_or_contract` at `gate_id`/`stand_id`,
## resolving missing `first_day` from `tick` and `epoch` after `taxi` is set.
static func probe_contract(
	terms_or_contract: Dictionary,
	gate_id: String,
	stand: Dictionary,
	stand_id: String,
	tick: int,
	epoch: int
) -> Dictionary:
	var fields := terms_or_contract.duplicate()
	if not fields.has("first_day"):
		fields["first_day"] = (
			FlightContract.one_off_day(fields) if FlightContract.is_charter(fields) else 0
		)
	var probe := FlightContract.assigned(fields, gate_id, stand, stand_id)
	if probe.is_empty():
		return {}
	if not terms_or_contract.has("first_day") and not FlightContract.is_charter(probe):
		var resolved := probe.duplicate()
		resolved["first_day"] = FlightTimetable.first_day(probe, tick, epoch)
		return FlightContract.make(resolved)
	return probe


## Picks the nearest free Bus Gate for `terms_or_contract` on remote `stand_id`.
## Returns {"gate": bus_gate_id, "clash": ""} or {"gate": "", "clash": reason}.
static func nearest_free_bus_gate(
	terms_or_contract: Dictionary,
	stand_id: String,
	stand: Dictionary,
	bus_gates: Array[String],
	bus_grounds: Dictionary,
	contracts: Array[Dictionary],
	flights: Array[Dictionary],
	ended: Dictionary,
	tick: int,
	epoch: int,
	next_day: Dictionary = {}
) -> Dictionary:
	if bus_gates.is_empty():
		return {"gate": "", "clash": "remote stand %s has no bus gate" % stand_id}
	var ordered := sorted_bus_gates(bus_gates, bus_grounds, stand)
	var first_clash := ""
	for bg_id in ordered:
		var probe := probe_contract(terms_or_contract, bg_id, stand, stand_id, tick, epoch)
		if probe.is_empty():
			continue
		var clash := bus_gate_clash(probe, bg_id, contracts, flights, ended, epoch, next_day)
		if clash == "":
			return {"gate": bg_id, "clash": ""}
		if first_clash == "":
			first_clash = clash
	return {"gate": "", "clash": first_clash}


## Returns why `probe` (already assigned to `bus_gate`) clashes on `bus_gate`, or "".
static func bus_gate_clash(
	probe: Dictionary,
	bus_gate: String,
	contracts: Array[Dictionary],
	flights: Array[Dictionary],
	ended: Dictionary,
	epoch: int,
	next_day: Dictionary = {}
) -> String:
	var pid := String(probe["id"])
	for other in contracts:
		if other["id"] == pid or ended.has(other["id"]) or other["gate"] != bus_gate:
			continue
		if (
			FlightContract.is_charter(other)
			and next_day.has(other["id"])
			and int(next_day[other["id"]]) > FlightContract.one_off_day(other)
		):
			continue
		if bus_contracts_overlap(probe, other):
			return "contract %s clashes with %s at gate %s" % [pid, other["id"], bus_gate]
	for flight in flights:
		if flight["contract"] == pid or flight["gate"] != bus_gate:
			continue
		if bus_contract_meets_flight(probe, flight["starts"], epoch):
			return "contract %s clashes with flight %s at gate %s" % [pid, flight["id"], bus_gate]
	return ""


static func bus_contracts_overlap(a: Dictionary, b: Dictionary) -> bool:
	if String(a["gate"]) != String(b["gate"]):
		return false
	if FlightContract.is_charter(a) and FlightContract.is_charter(b):
		var sa := FlightTimetable.starts_for(a, FlightContract.one_off_day(a), 0)
		var sb := FlightTimetable.starts_for(b, FlightContract.one_off_day(b), 0)
		return bus_holds_overlap(sa, sb)
	if FlightContract.is_charter(a):
		return bus_contract_meets_flight(
			b, FlightTimetable.starts_for(a, FlightContract.one_off_day(a), 0), 0
		)
	if FlightContract.is_charter(b):
		return bus_contract_meets_flight(
			a, FlightTimetable.starts_for(b, FlightContract.one_off_day(b), 0), 0
		)
	var a_starts := FlightTimetable.starts_for(a, 0, 0)
	for shift in [-1, 0, 1]:
		if bus_holds_overlap(a_starts, FlightTimetable.starts_for(b, shift, 0)):
			return true
	return false


static func bus_contract_meets_flight(
	contract: Dictionary, flight_starts: Array, epoch: int
) -> bool:
	var f_bus := bus_hold_span(flight_starts)
	if f_bus[0] >= f_bus[1]:
		return false
	if FlightContract.is_charter(contract):
		var c_starts := FlightTimetable.starts_for(
			contract, FlightContract.one_off_day(contract), epoch
		)
		return bus_holds_overlap(flight_starts, c_starts)
	var day0_bus := bus_hold_span(FlightTimetable.starts_for(contract, 0, epoch))
	var day_size := GameCalendar.TICKS_PER_DAY
	var lowest := GameCalendar.floor_div(f_bus[0] - day0_bus[1], day_size) + 1
	var highest := -GameCalendar.floor_div(day0_bus[0] - f_bus[1], day_size) - 1
	for day in range(maxi(lowest, int(contract["first_day"])), highest + 1):
		if bus_holds_overlap(flight_starts, FlightTimetable.starts_for(contract, day, epoch)):
			return true
	return false
