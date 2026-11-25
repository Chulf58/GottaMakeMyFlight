class_name SpurMoves
extends RefCounted
## The side spur moves in FlightSim's planning world (decision side-spur-move-
## design-s7-stands-carry-lane-x-the-wanted-spur, slice S7b). Pure and static:
## everything is worked out from the world, so a scratch trial with other
## contracts, grounds or spurs resolves its own release.
##
## The world (FlightPlans) also holds "spurs" (side -> {"x": the spur x its
## gates' stands are on now, "wanted": the x the build wants}), "tick" (the
## tick the forecast starts at) and "open" (whether the airport has opened). A
## side is pending while its x and wanted differ.
##
## release() is a pending side's release tick R: the first tick from "tick" at
## which no real occurrence at that side's gates is between its issue and its
## TAKEOFF. Real occurrences are the live flights and the days a running
## contract has not issued yet (on the pair it flies now); an ended contract
## that still reserves its ground plans, but never delays R. Departures lie
## between 06:00 and 22:00 and issue to TAKEOFF lasts at most 6 h 03 min, so
## the latest TAKEOFF (23:50) comes before the earliest next issue (01:47): R is
## never later than that night (test_spur_moves_release.gd pins the gap).
##
## resolve() is the one resolver: a contract's occurrence of a day gets its
## stand and taxi pair together, the gate's stand now and the contract as it is
## when it is issued before R, else the gate's stand on the wanted spur
## (next_ground()) and the contract assigned to it (FlightContract.assigned()).
## Issued flights keep their own records. refusal() names the first flight a
## pending side would strand: a running contract its gate's new stand cannot
## take, or an occurrence that would meet another at its gate once re-timed.
## The taxi plans are FlightPlans', whose requests resolve each occurrence.
##
## Not guaranteed: refusal() names the first stranded flight, not every one.

## The reasons refusal() gives, beside the planner's, and typed()'s.
const NO_STAND := "spur_no_stand"
const GATE_MEETS := "spur_gate"
const LOST_PLAN := "spur_lost_plan"
const REASONS: Array[String] = [NO_STAND, GATE_MEETS, LOST_PLAN]


## The spurs of `world`, or none pending when it has none.
static func spurs_of(world: Dictionary) -> Dictionary:
	return world.get("spurs", {})


## Whether `side`'s spur waits to move in `world`.
static func pending(world: Dictionary, side: String) -> bool:
	var spur: Dictionary = spurs_of(world).get(side, {})
	return not spur.is_empty() and not is_equal_approx(float(spur["x"]), float(spur["wanted"]))


## The sides of `world` that are pending.
static func pending_sides(world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for side in SideSpurs.SIDES:
		if pending(world, side):
			out.append(side)
	return out


## The side gate `gate` of `world` stands on, NORTH for none.
static func side_of_gate(world: Dictionary, gate: String) -> String:
	var ground: Dictionary = world["grounds"].get(gate, {})
	return (
		StandPlacement.side_of(ground["stand"]) if not ground.is_empty() else StandPlacement.NORTH
	)


static func side_of_contract(world: Dictionary, contract: Dictionary) -> String:
	return side_of_gate(world, BusGatePairing.stand_id_of(contract))


## Pending `side`'s release tick R in `world` (see the class notes), or -1 when
## it is not pending. Worked out once per world.
static func release(world: Dictionary, side: String) -> int:
	if not pending(world, side):
		return -1
	var cache: Dictionary = world.get_or_add("_release", {})
	if cache.has(side):
		return cache[side]
	var at := int(world.get("tick", 0))
	var contracts: Array = []
	if world.get("open", true):
		for contract: Dictionary in world["contracts"]:
			if _contract_runs_ahead(world, contract) and side_of_contract(world, contract) == side:
				contracts.append(contract)
	var moved := true
	while moved:
		moved = false
		for flight: Dictionary in world["flights"]:
			var takeoff := int(flight["starts"][FlightSim.State.TAKEOFF])
			if StandPlacement.side_of(flight["stand"]) == side and at < takeoff:
				at = takeoff
				moved = true
		for contract: Dictionary in contracts:
			var since := at - FlightTimetable.issue_tick(contract, 0, world["epoch"])
			var day := GameCalendar.floor_div(since, GameCalendar.TICKS_PER_DAY)
			if day < int(world["next_day"][contract["id"]]):
				continue
			if FlightContract.is_charter(contract) and day != FlightContract.one_off_day(contract):
				continue
			var starts := FlightTimetable.starts_for(contract, day, world["epoch"])
			var takeoff := starts[FlightSim.State.TAKEOFF]
			if at < takeoff:
				at = takeoff
				moved = true
	cache[side] = at
	return at


## Gate `gate`'s ground on its side's wanted spur: GateDesks' "next" when it
## gave one, else its stand moved onto the wanted spur with the same max_class.
static func next_ground(world: Dictionary, gate: String) -> Dictionary:
	var ground: Dictionary = world["grounds"][gate]
	if ground.has("next"):
		return ground["next"]
	var side := StandPlacement.side_of(ground["stand"])
	var wanted := float(spurs_of(world)[side]["wanted"])
	return {
		"stand": StandPlacement.with_lane_x(ground["stand"], wanted),
		"max_class": ground["max_class"]
	}


## {"contract": `contract` as it flies day `day`, "stand": the stand it flies
## from} (see the class notes), or {} when its gate has no ground or the gate's
## new stand cannot take it.
static func resolve(world: Dictionary, contract: Dictionary, day: int) -> Dictionary:
	var gate: String = contract["gate"]
	var stand_id := BusGatePairing.stand_id_of(contract)
	var ground: Dictionary = world["grounds"].get(stand_id, {})
	if ground.is_empty():
		return {}
	var side := StandPlacement.side_of(ground["stand"])
	if side == StandPlacement.NORTH or not pending(world, side):
		return {"contract": contract, "stand": ground["stand"]}
	if FlightTimetable.issue_tick(contract, day, world["epoch"]) < release(world, side):
		return {"contract": contract, "stand": ground["stand"]}
	var cache: Dictionary = world.get_or_add("_resolved", {})
	if not cache.has(contract["id"]):
		cache[contract["id"]] = _moved(contract, gate, next_ground(world, stand_id), stand_id)
	return cache[contract["id"]]


## `contract` assigned to gate `gate`'s ground `next`, or {} when it cannot be.
static func _moved(
	contract: Dictionary, gate: String, next: Dictionary, stand_id := ""
) -> Dictionary:
	var resolved_stand := gate if stand_id == "" else stand_id
	if FlightContract.assignment_problem(resolved_stand, next["stand"]) != "":
		return {}
	if not FlightGround.class_fits(contract["plane_size"], next["max_class"]):
		return {}
	return {
		"contract": FlightContract.assigned(contract, gate, next["stand"], resolved_stand),
		"stand": next["stand"],
	}


## The calendar days on which a pending side's occurrences switch: the day of
## each R and the day after (FlightPlans.days_from() samples them).
static func transition_days(world: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for side in pending_sides(world):
		var day := GameCalendar.day_of(release(world, side), world["epoch"])
		out.append_array([day, day + 1])
	return out


## The first day from contract `contract`'s next day issued at or after `at`.
static func first_day_from(world: Dictionary, contract: Dictionary, at: int) -> int:
	var day := int(world["next_day"][contract["id"]])
	while FlightTimetable.issue_tick(contract, day, world["epoch"]) < at:
		day += 1
	return day


## The first flight `world`'s pending sides would strand, as {"id", "reason":
## NO_STAND or GATE_MEETS}, or {}: a running contract whose gate's new stand
## cannot take it (named by its first day from R), or an occurrence that meets
## another at its gate once the days around R are resolved, or, from then on,
## the contracts at their new pairs (named by the later one's first such day).
static func refusal(world: Dictionary) -> Dictionary:
	for side in pending_sides(world):
		var at := release(world, side)
		var by_gate := {}
		for contract: Dictionary in world["contracts"]:
			if (
				not _contract_runs_ahead(world, contract)
				or side_of_contract(world, contract) != side
			):
				continue
			var day := first_day_from(world, contract, at)
			if FlightContract.is_charter(contract) and day > FlightContract.one_off_day(contract):
				continue
			if resolve(world, contract, day).is_empty():
				return {
					"id": FlightTimetable.occurrence_id(contract["id"], day), "reason": NO_STAND
				}
			by_gate.get_or_add(contract["gate"], []).append(contract)
		var last := GameCalendar.day_of(at, world["epoch"]) + 2
		for gate: String in by_gate:
			var meets := _gate_refusal(world, gate, by_gate[gate], last)
			if not meets.is_empty():
				return meets
	return {}


## True when `contract` is not ended and, if a one-off charter, still has its
## single day ahead unissued (`next_day <= one_off_day`).
static func _contract_runs_ahead(world: Dictionary, contract: Dictionary) -> bool:
	if world["ended"].has(contract["id"]):
		return false
	if not FlightContract.is_charter(contract):
		return true
	return int(world["next_day"].get(contract["id"], 0)) <= FlightContract.one_off_day(contract)


## The first occurrence at `gate` that meets another there: among its live
## flights and `contracts`' resolved days up to `last`, then those contracts
## on their new pairs; {} for none.
static func _gate_refusal(
	world: Dictionary, gate: String, contracts: Array, last: int
) -> Dictionary:
	var held: Array = []
	for flight: Dictionary in world["flights"]:
		if flight["gate"] == gate:
			var size := (
				FlightPlans.flight_class(world, flight)
				if flight.get("contract", "") != ""
				else PlaneClasses.MEDIUM
			)
			held.append([flight["id"], flight["starts"], size])
	for contract: Dictionary in contracts:
		var end_day := (
			mini(last, FlightContract.one_off_day(contract))
			if FlightContract.is_charter(contract)
			else last
		)
		for day in range(int(world["next_day"][contract["id"]]), end_day + 1):
			var resolved := resolve(world, contract, day)
			var id := FlightTimetable.occurrence_id(contract["id"], day)
			(
				held
				. append(
					[
						id,
						FlightTimetable.starts_for(resolved["contract"], day, world["epoch"]),
						contract["plane_size"],
					]
				)
			)
	for i in held.size():
		for j in range(i + 1, held.size()):
			if FlightTimetable.shares_gate(
				gate, held[i][1], gate, held[j][1], held[i][2], held[j][2]
			):
				return {"id": held[j][0], "reason": GATE_MEETS}
	for i in contracts.size():
		if FlightContract.is_charter(contracts[i]):
			continue
		var a: Dictionary = resolve(world, contracts[i], last)["contract"]
		for j in range(i + 1, contracts.size()):
			if FlightContract.is_charter(contracts[j]):
				continue
			var b: Dictionary = resolve(world, contracts[j], last)["contract"]
			if FlightTimetable.contracts_share_gate(a, b):
				return {"id": FlightTimetable.occurrence_id(b["id"], last), "reason": GATE_MEETS}
	return {}


## `refusal` (FlightPlans.refusal() of `changed` against the plans of `base`)
## typed as LOST_PLAN when it is an occurrence that planned before the change
## (a TAXI_BUSY of a flight outside `subjects`), not yet issued, whose stand or
## taxi pair the change moved across a release: the change strands it through
## the spur, not through the ground it shares. Else `refusal` as it is.
static func typed(
	base: Dictionary, changed: Dictionary, refusal: Dictionary, subjects := []
) -> Dictionary:
	if refusal.get("reason", "") != GroundPlanner.TAXI_BUSY:
		return refusal
	var parts := FlightTimetable.parse_occurrence(refusal["id"])
	if parts.is_empty() or subjects.has(parts["contract"]) or subjects.has(refusal["id"]):
		return refusal
	var day: int = parts["day"]
	var was := _resolved_of(base, parts["contract"], day)
	var now := _resolved_of(changed, parts["contract"], day)
	if was.is_empty() or now.is_empty():
		return refusal
	if was["stand"] == now["stand"] and was["contract"]["taxi"] == now["contract"]["taxi"]:
		return refusal
	return {"id": refusal["id"], "reason": LOST_PLAN}


## `world` with contract `id` ended from day `day`, and still reserving its
## ground when `reserving` (FlightSim.end_contract()'s trial).
static func ending(world: Dictionary, id: String, day: int, reserving: bool) -> Dictionary:
	world["ended"] = world["ended"].duplicate()
	world["ended"][id] = day
	if reserving:
		world["reserving"] = world["reserving"].duplicate()
		world["reserving"][id] = true
	return world


## `contracts` with a gate removal's `moves` (contract id -> gate, FlightSim.
## move_plan()) carried out, each on its new gate's stand in `grounds` now.
static func with_moves(
	contracts: Array[Dictionary], moves: Dictionary, grounds: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for contract in contracts:
		var to: String = moves.get(contract["id"], "")
		var stand_id := BusGatePairing.stand_id_of(contract)
		if to != "" and BusGatePairing.is_remote_contract(contract) and grounds.has(stand_id):
			out.append(FlightContract.assigned(contract, to, grounds[stand_id]["stand"], stand_id))
			continue
		var ok := to != "" and grounds.has(to)
		ok = ok and FlightContract.assignment_problem(to, grounds[to]["stand"]) == ""
		out.append(FlightContract.assigned(contract, to, grounds[to]["stand"]) if ok else contract)
	return out


## resolve() of contract `id`'s day `day` in `world` when that day is not yet
## issued there, else {}.
static func _resolved_of(world: Dictionary, id: String, day: int) -> Dictionary:
	for contract: Dictionary in world["contracts"]:
		if contract["id"] == id and day >= int(world["next_day"].get(id, day + 1)):
			return resolve(world, contract, day)
	return {}


## Whether live `flight` holds `stand`, its gate's stand now. From TAKEOFF on a
## flight may still hold the spur its side had before the spur moved.
static func holds_stand(flight: Dictionary, stand: Dictionary) -> bool:
	if flight["stand"] == stand:
		return true
	var side := StandPlacement.side_of(stand)
	if int(flight["state"]) < FlightSim.State.TAKEOFF or side == StandPlacement.NORTH:
		return false
	var lane_x := StandPlacement.lane_x_of(flight["stand"])
	return StandPlacement.with_lane_x(stand, lane_x) == flight["stand"]


## What the plans of `world` depend on from its spurs: each side's x, wanted x
## and release tick. FlightSim keys its cached plans on it.
static func key(world: Dictionary) -> String:
	var parts := PackedStringArray()
	for side in SideSpurs.SIDES:
		var spur: Dictionary = spurs_of(world).get(side, {})
		parts.append(
			"%s %s %s %d" % [side, spur.get("x"), spur.get("wanted"), release(world, side)]
		)
	return " ".join(parts)
