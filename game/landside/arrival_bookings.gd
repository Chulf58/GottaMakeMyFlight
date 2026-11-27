class_name ArrivalBookings
extends RefCounted
## PassengerSim's arrival bookings while it has a LandsideSim (decision
## landside-technical-design-arrival-bookings-landsidesim-vehic): every
## scheduled passenger is a booking with a stable id from scheduling until
## it gets out of its car or taxi, when it becomes a Passenger record, or
## until its flight's doors close while it is still on the road.
##
## Scheduling forms the flight's parties first (decision
## landside-groups-passengers-arrive-in-groups-that-share-a-car): a taxi
## carries 1-2, a car 1-4, and some cars mean to park. Each party draws one
## arrival type and one time in that type's window (ArrivalTypes), the time
## it means to get out (the window ends early enough for the whole party to
## step out, one at a time, and each later member's own tick is
## LandsideSim.RELEASE_GAP_TICKS after the one before). Its vehicle enters the
## road that much free-flow drive earlier (LandsideSim.lead_ticks()), so on a
## free road it gets out on time;
## a party scheduled with less notice than that enters at once and is late by
## the difference.
##
## Each tick (step(), right after PassengerSim takes the tick): first the
## bookings of flights whose doors have closed are settled, each once:
## aboard a vehicle it is a missed flight with the cause 'waiting for
## drop-off' (counted here, in missed_by_flight and missed_total, and
## announced by `missed`), unless the terminal has no entrance, when it is a
## 'no_entrance' no-show like the passengers PassengerSim never spawned; still
## waiting for its vehicle it is a no-show as well. Then LandsideSim steps and
## each passenger it lets out is spawned with the walk from where it got
## out, no more than the line outside the entrance has room for
## (EntranceLine.room_for_arrivals()). Every booking aboard a vehicle the step
## kept for that line (LandsideSim.line_held: refused a place, or queued on
## the road behind such a car) is marked held (EntranceLine.held), and the
## mark stays until it gets out or settles, after the hold clears too: if its
## flight closes on it while still aboard, the miss is check-in congestion, and
## otherwise (never kept) a road delay. Last, the parties now due board new
## vehicles.

## A booking's passenger got out and is Passenger `passenger_id`.
signal released(booking_id: int, passenger_id: int)
## A booking still aboard a vehicle when its flight's doors closed.
signal missed(flight_id: String)

## Whole percent of parties that come by taxi; the rest come by car.
const TAXI_SHARE := 40
## Whole percent of cars that mean to park (when a car park stands).
const PARK_SHARE := 50
## Small flights (at or below SMALL_FLIGHT_MAX_PAX bookings) cap party size at
## SMALL_FLIGHT_MAX_PARTY so passengers arrive in several vehicles instead of clumps.
const SMALL_FLIGHT_MAX_PAX := 12
const SMALL_FLIGHT_MAX_PARTY := 2
## Target minimum gap between consecutive vehicles in the same arrival-type
## window when the window width allows it (4 s).
const INTER_VEHICLE_GAP_TICKS := 80

## Transport misses by flight id, pruned with PassengerSim's flight results.
var missed_by_flight := {}
## Every transport miss so far; part of PassengerSim.missed_count().
var missed_total := 0

var _sim: PassengerSim
## PassengerSim._spawn(flight_id, variant, arrival, walk) -> Passenger.
var _spawn: Callable
var _bookings: Array[ArrivalBooking] = []
var _by_id := {}
var _next_id := 1


func bind(sim: PassengerSim, spawn: Callable) -> void:
	_sim = sim
	_spawn = spawn


## Forms `count` passengers of `flight_id` into parties and books them, from
## the sim RNG, each party's arrival type drawn with `shares`
## (ArrivalTypes.shares_for the flight's contract). With `first_at_once`
## (FirstParty) the first party's vehicle enters the road now and gets out on
## time on a free road, whatever time it drew, and the rest draw after its
## drive so none boards on the opening tick.
func schedule(
	flight_id: String, count: int, shares: Array[int] = ArrivalTypes.SHARES, first_at_once := false
) -> void:
	var rng := _sim.clock.rng
	var parties: Array[Dictionary] = []
	var type_counts := {}
	var left := count
	while left > 0:
		var kind := LandsideVehicle.Kind.CAR
		if rng.randi_range(0, 99) < TAXI_SHARE:
			kind = LandsideVehicle.Kind.TAXI
		var cap: int = LandsideVehicle.MAX_PARTY[kind]
		if count <= SMALL_FLIGHT_MAX_PAX:
			cap = mini(cap, SMALL_FLIGHT_MAX_PARTY)
		var size := rng.randi_range(1, mini(cap, left))
		var intent := LandsideVehicle.Intent.DROP
		if kind == LandsideVehicle.Kind.CAR and rng.randi_range(0, 99) < PARK_SHARE:
			intent = LandsideVehicle.Intent.PARK
		var arrival := ArrivalTypes.draw(rng, shares)
		var variants: Array[int] = []
		for i in size:
			variants.append(rng.randi_range(0, 1))
		var pinned := first_at_once and left == count
		var slot_idx := 0
		if not pinned:
			slot_idx = int(type_counts.get(arrival, 0))
			type_counts[arrival] = slot_idx + 1
		(
			parties
			. append(
				{
					"kind": kind,
					"size": size,
					"intent": intent,
					"arrival": arrival,
					"variants": variants,
					"pinned": pinned,
					"slot": slot_idx,
				}
			)
		)
		left -= size
	for p_info in parties:
		var kind: LandsideVehicle.Kind = p_info["kind"]
		var size: int = p_info["size"]
		var intent: LandsideVehicle.Intent = p_info["intent"]
		var arrival: ArrivalTypes.Type = p_info["arrival"]
		var lead := _sim.landside.lead_ticks(intent)
		var earliest := _sim.clock.tick + lead if first_at_once else _sim.clock.tick
		var span := ArrivalTypes.window(arrival, _sim.flights, flight_id, earliest)
		var slot_span := (
			span
			if p_info["pinned"]
			else _sub_slot(span, p_info["slot"], int(type_counts.get(arrival, 1)))
		)
		# The party gets out one at a time (LandsideSim.RELEASE_GAP_TICKS apart), so
		# its last member is out by the window's end (the drawn time is clamped, so
		# the sim RNG draws stay as they were).
		var stagger := (size - 1) * LandsideSim.RELEASE_GAP_TICKS
		var at := mini(rng.randi_range(slot_span.x, slot_span.y), maxi(span.x, span.y - stagger))
		if p_info["pinned"]:
			at = _sim.clock.tick + lead
		var party := _next_id
		var variants: Array[int] = p_info["variants"]
		for i in size:
			var b := ArrivalBooking.new()
			b.id = _next_id
			_next_id += 1
			b.party = party
			b.flight_id = flight_id
			b.variant = variants[i]
			b.arrival = arrival
			b.unload_tick = at + i * LandsideSim.RELEASE_GAP_TICKS
			b.kind = kind
			b.intent = intent
			_bookings.append(b)
			_by_id[b.id] = b


static func _sub_slot(span: Vector2i, slot: int, total: int) -> Vector2i:
	if total <= 1 or span.y <= span.x:
		return span
	var width := span.y - span.x + 1
	@warning_ignore("integer_division")
	var sub_x := mini(span.x + (slot * width) / total, span.y)
	@warning_ignore("integer_division")
	var sub_y := (
		span.y
		if slot == total - 1
		else clampi(span.x + ((slot + 1) * width) / total - 1, sub_x, span.y)
	)
	@warning_ignore("integer_division")
	var pad := mini(INTER_VEHICLE_GAP_TICKS / 2, (sub_y - sub_x) / 4)
	var lo := sub_x if slot == 0 else sub_x + pad
	var hi := sub_y if slot == total - 1 else maxi(lo, sub_y - pad)
	return Vector2i(lo, hi)


## One tick, at PassengerSim.tick: settle, step the road, release, board.
func step() -> void:
	var landside := _sim.landside
	if landside == null:
		return
	_settle_closed(landside)
	var can_release := not _sim.layout.passenger_entrances.is_empty()
	var closes := {}
	for b in _bookings:
		if b.state == ArrivalBooking.State.IN_VEHICLE:
			closes[b.id] = _sim.flights.doors_close_tick(b.flight_id)
	# One place in the line outside the entrance per passenger let out
	# (EntranceLine); with none free they stay aboard.
	var budget := _sim.entrance.room_for_arrivals(_sim)
	if budget >= EntranceLine.UNLIMITED:
		budget = -1
	var kept := {}
	for b in _bookings:
		if b.state == ArrivalBooking.State.IN_VEHICLE and _sim.entrance.held_now.has(b.id):
			kept[b.vehicle] = true
	var curb_waiters := PassengerArrivals.curb_pickup_waiters(_sim)
	var events := landside.step(
		_sim.tick, can_release, _sim.clock.rng, closes, budget, kept, curb_waiters
	)
	for pickup in landside.picked_up:
		for pid: int in pickup["passengers"]:
			var p := _sim.get_passenger(pid)
			if p != null and not p.arrival_done:
				PassengerArrivals.finish(_sim, p)
	for event in events:
		var walk: Array[Vector3] = event["walk"]
		for id: int in event["bookings"]:
			var b: ArrivalBooking = _by_id[id]
			b.state = ArrivalBooking.State.RELEASED
			_sim.entrance.held.erase(id)
			_sim.entrance.held_now.erase(id)
			_drop(b)
			var p: Passenger = _spawn.call(b.flight_id, b.variant, b.arrival, walk)
			released.emit(b.id, p.id)
	_sim.entrance.held_now.clear()
	for b in _bookings:
		if b.state == ArrivalBooking.State.IN_VEHICLE and landside.line_held.has(b.vehicle):
			_sim.entrance.held[b.id] = true
			_sim.entrance.held_now[b.id] = true
	_board(landside)
	_spawn_pickup_taxis(landside)


## Bookings not yet released or settled.
func pending() -> int:
	return _bookings.size()


func booking_ids() -> Array[int]:
	var ids: Array[int] = []
	for b in _bookings:
		ids.append(b.id)
	return ids


func get_booking(id: int) -> ArrivalBooking:
	return _by_id.get(id)


func next_id() -> int:
	return _next_id


## Drops the transport misses of flights not in `live`.
func prune(live: Array[String]) -> void:
	for flight_id in missed_by_flight.keys():
		if not live.has(flight_id):
			missed_by_flight.erase(flight_id)


## Installs a LandsideSnapshot.load() result.
func restore(loaded: Dictionary) -> void:
	_bookings = loaded["bookings"]
	_by_id.clear()
	for b in _bookings:
		_by_id[b.id] = b
	_next_id = loaded["next_booking_id"]
	missed_by_flight = loaded["missed"]
	missed_total = loaded["missed_total"]


func _settle_closed(landside: LandsideSim) -> void:
	var no_entrance := _sim.layout.passenger_entrances.is_empty()
	var listed: Array[ArrivalBooking] = _bookings.duplicate()
	for b in listed:
		if not _sim.flights.is_doors_closed(b.flight_id):
			continue
		var aboard := b.state == ArrivalBooking.State.IN_VEHICLE
		if aboard:
			landside.drop_booking(b.vehicle, b.id)
		b.state = ArrivalBooking.State.SETTLED
		_drop(b)
		# Kept aboard for the line outside on any step since it boarded, itself
		# or queued behind a car that was (EntranceLine.held): check-in congestion.
		var held_for_line: bool = _sim.entrance.held.has(b.id)
		_sim.entrance.held.erase(b.id)
		_sim.entrance.held_now.erase(b.id)
		if aboard and not no_entrance and held_for_line:
			var line_missed := _sim.entrance.held_missed
			line_missed[b.flight_id] = int(line_missed.get(b.flight_id, 0)) + 1
		if aboard and not no_entrance:
			missed_by_flight[b.flight_id] = int(missed_by_flight.get(b.flight_id, 0)) + 1
			missed_total += 1
			missed.emit(b.flight_id)
			continue
		var cause := "no_entrance" if no_entrance else "late"
		var counts: Dictionary = _sim.no_shows.get(b.flight_id, {"no_entrance": 0, "late": 0})
		counts[cause] += 1
		_sim.no_shows[b.flight_id] = counts


## Hands the parties now due to new vehicles, earliest unload tick first.
func _board(landside: LandsideSim) -> void:
	var lead := {}
	for intent in LandsideVehicle.Intent.values():
		lead[intent] = landside.lead_ticks(intent)
	var due := {}
	var order := []
	var early := {}
	for b in _bookings:
		if b.state != ArrivalBooking.State.AWAITING or early.has(b.party):
			continue
		# A party boards one vehicle once its first member is due; the others
		# follow, each with its own later expected tick.
		if not due.has(b.party):
			if _sim.tick < b.unload_tick - lead[b.intent]:
				early[b.party] = true
				continue
			var members: Array[int] = []
			due[b.party] = members
			order.append([b.unload_tick, b.party])
		(due[b.party] as Array[int]).append(b.id)
	order.sort()
	for entry in order:
		var ids: Array[int] = due[entry[1]]
		var first: ArrivalBooking = _by_id[ids[0]]
		var vehicle := landside.add_vehicle(first.kind, first.intent, ids)
		for id in ids:
			var b: ArrivalBooking = _by_id[id]
			b.state = ArrivalBooking.State.IN_VEHICLE
			b.vehicle = vehicle


func _spawn_pickup_taxis(landside: LandsideSim) -> void:
	var waiters := PassengerArrivals.curb_pickup_waiters(_sim)
	if waiters.is_empty():
		return
	if waiters.size() <= landside.inbound_pickup_capacity():
		return
	if landside.can_spawn_pickup_taxi():
		landside.add_vehicle(
			LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.PICKUP, [] as Array[int]
		)


func _drop(b: ArrivalBooking) -> void:
	_bookings.erase(b)
	_by_id.erase(b.id)
	b.vehicle = 0
