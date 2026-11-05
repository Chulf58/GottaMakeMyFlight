class_name GateCapacity
extends RefCounted
## Gate places held for passengers on their way through security (decision
## gate-full-design-passengers-reserve-a-gate-seat-or-standing), so a passenger
## is never cleared with nowhere to go and held passengers never stack on the
## security exit cell.
##
## - A security queue front is admitted only once it has reserved a gate seat
##   or a standing spot, chosen from its station's exit cell as a cleared
##   passenger chooses there: a free seat within GateReach.NEAR_CELLS of its
##   gate desk (any seat with no gate desk) in the exit's route region, else
##   the first spot StandingSpots.free_nearest() gives (roller spacing
##   included). A front whose boarding has opened needs none: it leaves by the
##   boarding files. With no place it waits on its lane cell, stuck GATE_FULL.
## - Fronts ready on the same tick are admitted earliest boarding tick first,
##   then by station id (admit_all()). A passenger behind a later flight's
##   front can miss; that miss is a crowding miss (miss_cause()).
## - A passenger in security whose place an edit removed reserves again from
##   its station's exit on each tick, before the fronts; SecurityRuntime clears
##   nobody without a place, so it waits inside security, shown on the HUD.
## - On clearance the reservation becomes the seat or spot claim and the
##   passenger walks there (on_cleared()). Leaving security any other way gives
##   it up (stage_set()).
##
## Seat reservations are kept here (passenger id -> seat key) and spot
## reservations in StandingSpots (reserve()); both are saved under
## "gate_places" (to_list()). SecurityForecast replays the admissions against
## a copy (copy()), every competing station at once, whenever the free room
## could run out before the passenger it forecasts is cleared (scarce()).

## Passenger id -> the key of the gate seat reserved for it (TerminalLayout).
var seats := {}
## A copy for SecurityForecast holds its own claims and its sim.
var _copy := false
var _sim: PassengerSim
var _spots: StandingSpots
var _seat_claims := {}
## The last scarce() answer and what it was worked out from.
var _scarce_key := []
var _scarce := false


## A copy whose reservations and claims a replay can change (SecurityForecast).
func copy(sim: PassengerSim) -> GateCapacity:
	var out := GateCapacity.new()
	out._copy = true
	out._sim = sim
	out._spots = sim.standing.copied()
	out._seat_claims = sim._seat_claims.duplicate()
	out.seats = seats.duplicate()
	return out


## Whether `p` may be cleared: its boarding is open on `host`'s tick, or it
## holds a reserved seat or spot.
func placed(p: Passenger, host: Object) -> bool:
	if host.tick >= p.boarding_tick:
		return true
	return seats.has(p.id) or _spots_of(host).reserved_of(p.id) != StandingSpots.NO_SPOT


## Reserves a free gate seat, else a free standing spot, for `p` as if it
## stood on `from` (its station's exit); false when there is none.
func reserve(host: Object, p: Passenger, from: Vector2i) -> bool:
	var sim := _sim_of(host)
	var spots := _spots_of(host)
	var near := sim._gate_cells(p)
	var region := spots.region_of(from)
	var taken := _seat_claims_of(host)
	var held := {}
	for key: String in seats.values():
		held[key] = true
	var free := []
	for seat in sim.layout.seats:
		if taken.has(seat["key"]) or held.has(seat["key"]):
			continue
		if region < 0 or spots.region_of(seat["front"]) != region:
			continue
		var reach := GateReach.cells_from(seat["cell"], near)
		if near.is_empty() or reach <= GateReach.NEAR_CELLS:
			free.append([reach, Passenger.octile_mm(from, seat["front"]), free.size(), seat["key"]])
	if not free.is_empty():
		free.sort()
		seats[p.id] = free[0][3]
		return true
	var roller := ParkRecovery.has_roller(p)
	var open := spots.first_free(from, near, roller)
	if open == StandingSpots.NO_SPOT:
		return false
	spots.reserve(p.id, open, roller)
	return true


## Admits the ready queue fronts of the security `stations` of `host` (a
## PassengerSim, or a SecurityForecast replaying a copy), earliest boarding
## tick first, then by station id. `queues`, `cells` and `opens` are by
## station; `places` is the allocator, or null to admit without one. Before
## the fronts, admitted passengers who lost their place reserve again.
static func admit_all(
	host: Object,
	runtime: SecurityRuntime,
	stations: Array[int],
	queues: Dictionary,
	cells: Dictionary,
	opens: Dictionary,
	places: GateCapacity
) -> void:
	if places != null:
		var lost := []
		for station in stations:
			for id: int in runtime.record_of(station).get("admitted", []):
				var inside: Passenger = host.get_passenger(id)
				if not places.placed(inside, host):
					lost.append([inside.boarding_tick, id, station])
		lost.sort()
		for entry: Array in lost:
			places.reserve(host, host.get_passenger(entry[1]), runtime.exit_cell(entry[2]))
	var fronts := []
	for station in stations:
		if runtime.admit_return(station):
			continue
		var front := runtime.ready_front(station, queues[station], cells[station], opens[station])
		if front != null:
			fronts.append([front.boarding_tick, station, front.id])
	fronts.sort()
	for entry: Array in fronts:
		var front: Passenger = host.get_passenger(entry[2])
		var exit := runtime.exit_cell(entry[1])
		if places == null or places.placed(front, host) or places.reserve(host, front, exit):
			front.stuck = Passenger.Stuck.NONE
			runtime.admit_front(entry[1], queues[entry[1]])
		else:
			front.stuck = Passenger.Stuck.GATE_FULL


## The sim's tick of admissions: every security station of `sim`.
func admit(sim: PassengerSim) -> void:
	var stations: Array[int] = []
	var queues := {}
	var opens := {}
	for station: int in sim.layout.passages:
		stations.append(station)
		queues[station] = sim._queue(station)
		opens[station] = sim._is_open(station)
	stations.sort()
	admit_all(sim, sim.security, stations, queues, sim.layout.lanes, opens, self)


## `p` was cleared at its station's exit: its reservation becomes its seat or
## spot claim, and it walks there. With boarding open, or no way there, it is
## given up, and the passenger plans as any cleared one (GateCapacity.to_spot()).
func on_cleared(sim: PassengerSim, p: Passenger) -> void:
	var key: String = seats.get(p.id, "")
	var spot := sim.standing.reserved_of(p.id)
	seats.erase(p.id)
	sim.standing.unreserve(p.id)
	if sim.tick >= p.boarding_tick:
		return
	for seat in sim.layout.seats:
		if seat["key"] == key:
			var path := _path(sim, p.at, seat["front"])
			if not path.is_empty():
				_take_seat(sim, p, seat, path)
			return
	if spot != StandingSpots.NO_SPOT:
		var path := _path(sim, p.at, sim.standing.cell_of(spot))
		if not path.is_empty():
			sim.standing.claim(p.id, spot, ParkRecovery.has_roller(p))
			p.set_path(path)


## A stage change gives up the reservation of a passenger leaving security
## other than by clearance (sent back, missed).
func stage_set(sim: PassengerSim, p: Passenger, stage: Passenger.Stage) -> void:
	if stage != Passenger.Stage.SECURITY:
		seats.erase(p.id)
		sim.standing.unreserve(p.id)


## Passengers waiting for a gate place: held on the way to the gate
## (StandingSpots.is_held()), a queue front stuck GATE_FULL, or inside
## security with no place. The HUD shows it (AlertSources.gate_full()).
func shortage(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		var inside := p.stage == Passenger.Stage.SECURITY and not placed(p, sim)
		if (
			not p.is_done()
			and (p.stuck == Passenger.Stuck.GATE_FULL or inside or sim.standing.is_held(p))
		):
			out.append(id)
	return out


## Whether a forecast for `target` at `station` must replay the gate places:
## a dry run on a copy of the standing spots cannot reserve a spot from the
## station's exit for every passenger who may take a place before `target`
## is cleared (each with its own roller or none, rollers first, seats left
## out), and then one more a roller could take. Those passengers hold no seat,
## spot or reservation, and their boarding has not opened: at `station` the
## ones queued ahead of `target` (all of its queue and walkers when `target`
## is not queued there yet), at another station the ones in its lane, and
## every cleared one. Otherwise no admission is taken to wait for a place, and
## the replay plays the station alone.
func scarce(sim: PassengerSim, station: int, target: Passenger) -> bool:
	var queue := sim.queue_of(station) + sim.holding_of(station)
	var mine := queue.find(target.id)
	var rollers := int(ParkRecovery.has_roller(target))
	var plain := 1 - rollers
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.is_done() or id == target.id or sim.tick >= p.boarding_tick or p.seat_object != 0:
			continue
		if sim.standing.spot_of(id) != StandingSpots.NO_SPOT or placed(p, sim):
			continue
		var counts := p.cleared
		if p.stage == Passenger.Stage.SECURITY:
			counts = true
		elif p.station == station:
			var at := queue.find(id)
			counts = mine < 0 or (at >= 0 and at < mine)
		elif p.station != 0:
			counts = sim.queue_of(p.station).has(id)
		if counts and ParkRecovery.has_roller(p):
			rollers += 1
		elif counts:
			plain += 1
	var key := [sim.standing.revision, sim.tick, sim.security.exit_cell(station), rollers, plain]
	if key != _scarce_key:
		_scarce_key = key
		_scarce = _dry_run(sim.standing.copied(), key[2], rollers, plain)
	return _scarce


## Whether `spots` cannot hold `rollers` + 1 roller passengers and `plain`
## plain ones reserving from `from` one after another.
static func _dry_run(spots: StandingSpots, from: Vector2i, rollers: int, plain: int) -> bool:
	for i in rollers + plain + 1:
		var roller := i < rollers or i == rollers + plain
		var spot := spots.first_free(from, [], roller)
		if spot == StandingSpots.NO_SPOT:
			return true
		spots.reserve(-1 - i, spot, roller)
	return false


## The cause recorded for `p` missing its flight: CROWDED when a full gate
## held it (stuck GATE_FULL, or queued behind such a front) or people traffic
## at boarding did (decision a-late-passenger-held-up-by-people-traffic-at-
## boarding-misse), else its stuck status.
static func miss_cause(sim: PassengerSim, p: Passenger) -> Passenger.Stuck:
	if p.stuck == Passenger.Stuck.GATE_FULL:
		return Passenger.Stuck.CROWDED
	if p.stuck != Passenger.Stuck.NONE:
		return p.stuck
	if sim.files.was_delayed(p.id):
		return Passenger.Stuck.CROWDED
	if p.stage == Passenger.Stage.SECURITY_QUEUE and p.station != 0:
		var lane := sim.queue_of(p.station)
		if not lane.is_empty() and sim.get_passenger(lane[0]).stuck == Passenger.Stuck.GATE_FULL:
			return Passenger.Stuck.CROWDED
	return Passenger.Stuck.NONE


## The reservations for a save, in passenger id order.
func to_list(sim: PassengerSim) -> Array:
	var by_passenger := sim.standing.reservations()
	for id: int in seats:
		by_passenger[id] = seats[id]
	var ids: Array = by_passenger.keys()
	ids.sort()
	var out := []
	for id: int in ids:
		var place: Variant = by_passenger[id]
		var kind := "seat" if place is String else "spot"
		out.append({"passenger": id, kind: place})
	return out


## Saved reservations checked against the loaded passengers `by_id`, `sim`'s
## layout (rebuilt from the loaded grid), the derived `spots` and the saved
## standing `claims` (passenger -> spot): {"seats": {id: key}, "spots": {id:
## spot}} or {"error": text}. Each names a passenger inside security and not
## cleared, at most once, and one seat that exists and nobody sits in or one
## spot that exists and nobody claims, each at most once.
static func checked(
	list: Variant, by_id: Dictionary, sim: PassengerSim, spots: StandingSpots, claims: Dictionary
) -> Dictionary:
	if typeof(list) != TYPE_ARRAY:
		return {"error": "gate_places must be a list"}
	var keys := {}
	var sat := {}
	for seat in sim.layout.seats:
		keys[seat["key"]] = true
		for p: Passenger in by_id.values():
			if p.seat_object == seat["object_id"] and p.seat_cell == seat["cell"]:
				sat[seat["key"]] = true
	var claimed := {}
	for id: int in claims:
		claimed[claims[id]] = true
	var out := {"seats": {}, "spots": {}}
	var taken := {}
	for entry: Variant in list:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or (entry as Dictionary).size() != 2
			or not WholeNumber.is_whole(entry.get("passenger"))
			or not (
				typeof(entry.get("seat")) == TYPE_STRING or WholeNumber.is_whole(entry.get("spot"))
			)
		):
			return {"error": "gate place %s is malformed" % str(entry).left(80)}
		var id := int(entry["passenger"])
		var p: Passenger = by_id.get(id)
		if p == null or p.stage != Passenger.Stage.SECURITY or p.cleared:
			return {"error": "passenger %d cannot hold a gate place" % id}
		if out["seats"].has(id) or out["spots"].has(id):
			return {"error": "passenger %d holds two gate places" % id}
		if entry.has("seat"):
			var key: String = entry["seat"]
			if not keys.has(key) or sat.has(key) or taken.has(key):
				return {"error": "gate seat %s is unknown or taken" % key}
			taken[key] = true
			out["seats"][id] = key
		else:
			var spot := int(entry["spot"])
			if not spots.spots.has(spot) or claimed.has(spot) or taken.has(spot):
				return {"error": "gate spot %d is unknown or taken" % spot}
			taken[spot] = true
			out["spots"][id] = spot
	return out


## Replaces the reservations with checked()'s, into `spots` (the loaded
## StandingSpots); `by_id` says which passengers have a roller.
func restore(state: Dictionary, spots: StandingSpots, by_id: Dictionary) -> void:
	seats = (state["seats"] as Dictionary).duplicate()
	for id: int in state["spots"]:
		spots.reserve(id, state["spots"][id], ParkRecovery.has_roller(by_id[id]))


## No seat on the way to the gate: a free seat first, else the nearest free
## standing spot (StandingSpots), walked to and then stood on. With neither the
## passenger is held where it is (StandingSpots.is_held()) and tries again on
## the tick it got here and once a beat after.
static func to_spot(sim: PassengerSim, p: Passenger) -> void:
	var spot := sim.standing.spot_of(p.id)
	if spot == StandingSpots.NO_SPOT:
		if p.stage_tick != sim.tick and not sim._retry_now(p):
			return
		if claim_seat(sim, p):
			return
		spot = _claim_spot(sim, p)
		if spot == StandingSpots.NO_SPOT:
			p.clear_path()
			return
	if p.is_moving():
		return
	if p.at == sim.standing.cell_of(spot):
		p.clear_path()
		sim._set_stage(p, Passenger.Stage.STANDING)
	else:
		# Its path ended elsewhere (an edit): plan again on the next beat.
		sim.standing.release(p.id)


## A standing passenger takes a freed gate seat on its beat, which gives up
## its spot.
static func seat_from_spot(sim: PassengerSim, p: Passenger) -> void:
	if sim.standing.spot_of(p.id) == StandingSpots.NO_SPOT or not sim._retry_now(p):
		return
	if claim_seat(sim, p):
		sim.standing.release(p.id)
		sim._set_stage(p, Passenger.Stage.TO_GATE)


## The free seats nearest the passenger's gate desk first, none farther than
## GateReach.NEAR_CELLS from it, then the nearest to the passenger; with no gate
## desk (no gates, or a flight without a gate) the nearest to the passenger. A
## seat reserved for a passenger in security is not free.
static func claim_seat(sim: PassengerSim, p: Passenger) -> bool:
	var near := sim._gate_cells(p)
	var held := {}
	for key: String in sim.gates.seats.values():
		held[key] = true
	var free: Array = []
	for seat in sim.layout.seats:
		if sim._seat_claims.has(seat["key"]) or held.has(seat["key"]):
			continue
		var reach := GateReach.cells_from(seat["cell"], near)
		if near.is_empty() or reach <= GateReach.NEAR_CELLS:
			free.append([reach, Passenger.octile_mm(p.at, seat["front"]), free.size(), seat])
	free.sort()
	for i in mini(free.size(), PassengerSim.SEAT_TRIES):
		var seat: Dictionary = free[i][3]
		var path := sim.grid.find_path(p.at, seat["front"])
		if path.is_empty():
			continue
		_take_seat(sim, p, seat, path)
		return true
	return false


## Claims the nearest free spot that `p` has a path to (StandingSpots.TRIES
## nearest tried) and commits that path; NO_SPOT when none.
static func _claim_spot(sim: PassengerSim, p: Passenger) -> int:
	var tries := 0
	var roller := ParkRecovery.has_roller(p)
	for spot in sim.standing.free_nearest(p.at, sim._gate_cells(p), roller):
		var path := _path(sim, p.at, sim.standing.cell_of(spot))
		if not path.is_empty():
			sim.standing.claim(p.id, spot, roller)
			p.set_path(path)
			return spot
		tries += 1
		if tries >= StandingSpots.TRIES:
			break
	return StandingSpots.NO_SPOT


static func _take_seat(sim: PassengerSim, p: Passenger, seat: Dictionary, path: Array) -> void:
	sim._seat_claims[seat["key"]] = p.id
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.seat_piece = Relocation.placement(sim.grid, seat["object_id"])
	var cells: Array[Vector2i] = []
	cells.assign(path)
	p.set_path(cells)


## A path from `from` to `to`, [from] when they are one cell.
static func _path(sim: PassengerSim, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from]
	if from != to:
		path = sim.grid.find_path(from, to)
	return path


func _sim_of(host: Object) -> PassengerSim:
	return _sim if _copy else host


func _spots_of(host: Object) -> StandingSpots:
	return _spots if _copy else (host as PassengerSim).standing


func _seat_claims_of(host: Object) -> Dictionary:
	return _seat_claims if _copy else (host as PassengerSim)._seat_claims
