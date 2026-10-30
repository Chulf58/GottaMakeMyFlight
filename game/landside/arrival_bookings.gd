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
## out. Last, the parties now due board new vehicles.

## A booking's passenger got out and is Passenger `passenger_id`.
signal released(booking_id: int, passenger_id: int)
## A booking still aboard a vehicle when its flight's doors closed.
signal missed(flight_id: String)

## Whole percent of parties that come by taxi; the rest come by car.
const TAXI_SHARE := 40
## Whole percent of cars that mean to park (when a car park stands).
const PARK_SHARE := 50

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
## the sim RNG.
func schedule(flight_id: String, count: int) -> void:
	var rng := _sim.clock.rng
	var left := count
	while left > 0:
		var kind := LandsideVehicle.Kind.CAR
		if rng.randi_range(0, 99) < TAXI_SHARE:
			kind = LandsideVehicle.Kind.TAXI
		var size := rng.randi_range(1, mini(LandsideVehicle.MAX_PARTY[kind], left))
		var intent := LandsideVehicle.Intent.DROP
		if kind == LandsideVehicle.Kind.CAR and rng.randi_range(0, 99) < PARK_SHARE:
			intent = LandsideVehicle.Intent.PARK
		var arrival := ArrivalTypes.draw(rng)
		var span := ArrivalTypes.window(arrival, _sim.flights, flight_id, _sim.clock.tick)
		# The party gets out one at a time (LandsideSim.RELEASE_GAP_TICKS apart), so
		# its last member is out by the window's end (the drawn time is clamped, so
		# the sim RNG draws stay as they were).
		var stagger := (size - 1) * LandsideSim.RELEASE_GAP_TICKS
		var at := mini(rng.randi_range(span.x, span.y), maxi(span.x, span.y - stagger))
		var party := _next_id
		for i in size:
			var b := ArrivalBooking.new()
			b.id = _next_id
			_next_id += 1
			b.party = party
			b.flight_id = flight_id
			b.variant = rng.randi_range(0, 1)
			b.arrival = arrival
			b.unload_tick = at + i * LandsideSim.RELEASE_GAP_TICKS
			b.kind = kind
			b.intent = intent
			_bookings.append(b)
			_by_id[b.id] = b
		left -= size


## One tick, at PassengerSim.tick: settle, step the road, release, board.
func step() -> void:
	var landside := _sim.landside
	if landside == null:
		return
	_settle_closed(landside)
	var can_release := not _sim.layout.entrances.is_empty()
	var closes := {}
	for b in _bookings:
		if b.state == ArrivalBooking.State.IN_VEHICLE:
			closes[b.id] = _sim.flights.doors_close_tick(b.flight_id)
	for event in landside.step(_sim.tick, can_release, _sim.clock.rng, closes):
		var walk: Array[Vector3] = event["walk"]
		for id: int in event["bookings"]:
			var b: ArrivalBooking = _by_id[id]
			b.state = ArrivalBooking.State.RELEASED
			_drop(b)
			var p: Passenger = _spawn.call(b.flight_id, b.variant, b.arrival, walk)
			released.emit(b.id, p.id)
	_board(landside)


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
	var no_entrance := _sim.layout.entrances.is_empty()
	var listed: Array[ArrivalBooking] = _bookings.duplicate()
	for b in listed:
		if not _sim.flights.is_doors_closed(b.flight_id):
			continue
		var aboard := b.state == ArrivalBooking.State.IN_VEHICLE
		if aboard:
			landside.drop_booking(b.vehicle, b.id)
		b.state = ArrivalBooking.State.SETTLED
		_drop(b)
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


func _drop(b: ArrivalBooking) -> void:
	_bookings.erase(b)
	_by_id.erase(b.id)
	b.vehicle = 0
