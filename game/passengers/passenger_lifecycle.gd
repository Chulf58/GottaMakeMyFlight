class_name PassengerLifecycle
extends RefCounted
## The start and end of a passenger's life in PassengerSim: the spawn schedule,
## a new passenger at the entrance, doors closing, a made or missed outcome and
## the retirement of settled passengers. Static helpers over a sim; the state
## stays on the sim.


static func add_spawn(
	sim: PassengerSim,
	at_tick: int,
	flight_id: String,
	variant: int,
	arrival := ArrivalTypes.Type.TYPICAL
) -> void:
	var entry := {"tick": at_tick, "flight": flight_id, "variant": variant, "arrival": arrival}
	var i := sim._schedule.size()
	while i > 0 and sim._schedule[i - 1]["tick"] > at_tick:
		i -= 1
	sim._schedule.insert(i, entry)


## A contract flight's booked passengers; DEFAULT_PASSENGERS for a one-off one.
## An occurrence issued before this sim subscribed (a new game's starter
## contract) is still a contract flight.
static func booked_passengers(sim: PassengerSim, flight_id: String) -> int:
	var contract := sim.flights.contract_of(sim.flights.flight_contract_id(flight_id))
	return PassengerSim.DEFAULT_PASSENGERS if contract.is_empty() else contract["booked_passengers"]


static func spawn_due(sim: PassengerSim) -> void:
	if sim.layout.passenger_entrances.is_empty():
		return
	while not sim._schedule.is_empty() and sim._schedule[0]["tick"] <= sim.tick:
		var entry: Dictionary = sim._schedule.pop_front()
		sim._spawn(entry["flight"], entry["variant"], entry["arrival"])


## A new passenger at the entrance, or, with a `walk` (where it got out of
## a car or taxi, ArrivalBookings), walking from there: the walk replaces the
## road start of the entrance's walk in (OutsideWalks), or ends at the
## entrance's cell when the entrance has none.
static func spawn(
	sim: PassengerSim,
	flight_id: String,
	variant: int,
	arrival: ArrivalTypes.Type,
	walk: Array[Vector3]
) -> Passenger:
	var p := Passenger.new()
	p.id = sim._next_id
	sim._next_id += 1
	p.flight_id = flight_id
	p.variant = variant
	p.arrival_type = arrival
	p.spawn_tick = sim.tick
	p.stage_tick = sim.tick
	p.boarding_tick = sim.flights.boarding_window(flight_id).x
	p.hunger = sim.cafes.start_hunger(sim.clock.rng)
	CarryOnTraits.draw(sim.clock.rng, p)
	p.toilet_need = sim.clock.rng.randi_range(ToiletSim.NEED_START_MIN, ToiletSim.NEED_START_MAX)
	p.boredom = BoredomSim.start_of(p.id)
	p.at = sim.layout.door_cell(sim.grid, sim.layout.passenger_entrances[0])
	p.clear_path()
	p.apron = OutsideWalks.arrival(sim, sim.layout.passenger_entrances[0])
	if not walk.is_empty():
		var road := p.apron
		p.apron = walk.duplicate()
		if road.is_empty():
			p.apron.append(sim.grid.cell_to_world(p.at))
		else:
			p.apron.append_array(road.slice(1))
	sim._passengers.append(p)
	sim._by_id[p.id] = p
	sim.passenger_spawned.emit(p.id)
	return p


## Missed passengers are the ones already in the terminal. Those still on the
## schedule for a closed flight will never board, so they are dropped and
## counted as no-shows, with the cause that holds now.
static func close_doors(sim: PassengerSim) -> void:
	var cause := "no_entrance" if sim.layout.passenger_entrances.is_empty() else "late"
	var kept: Array[Dictionary] = []
	for entry in sim._schedule:
		if sim.flights.is_doors_closed(entry["flight"]):
			var counts: Dictionary = sim.no_shows.get(
				entry["flight"], {"no_entrance": 0, "late": 0}
			)
			counts[cause] += 1
			sim.no_shows[entry["flight"]] = counts
		else:
			kept.append(entry)
	if kept.size() != sim._schedule.size():
		sim._schedule = kept
	for flight_id in sim._scheduled.keys():
		if sim.flights.is_doors_closed(flight_id):
			sim._scheduled.erase(flight_id)
	for p in sim._passengers:
		if not p.is_done() and sim.flights.is_doors_closed(p.flight_id):
			finish(sim, p, false)


static func finish(sim: PassengerSim, p: Passenger, made: bool) -> void:
	if not made:
		p.missed_stage = p.stage
		# Held up by people traffic or a full gate, the miss is the terminal's.
		p.missed_stuck = GateCapacity.miss_cause(sim, p)
	sim._leave_station(p)
	sim._release_seat(p)
	sim.cafes.cleanup(p)
	sim.toilets.cleanup(p)
	sim.shops.cleanup(p)
	sim.info_desks.cleanup(p)
	sim._set_stage(p, Passenger.Stage.MADE if made else Passenger.Stage.MISSED)
	p.stuck = Passenger.Stuck.NONE
	p.late = false
	p.collect_tick = 0
	p.outcome_tick = sim.tick
	var result: Dictionary = sim.flight_results.get(
		p.flight_id, {"made": 0, "missed": 0, "causes": {}}
	)
	if made:
		sim._made += 1
		result["made"] += 1
	else:
		sim._missed += 1
		result["missed"] += 1
		var cause := Vector2i(p.missed_stage, p.missed_stuck)
		result["causes"][cause] = int(result["causes"].get(cause, 0)) + 1
		p.mood = 0
		p.clear_path()
	sim.flight_results[p.flight_id] = result
	sim.outcome.emit(p.id, made)


## Retires the settled passengers kept for SETTLED_KEEP_TICKS. One that still
## holds a station, seat, cafe or toilet visit or queue place is a bug: it is
## reported and kept, so nothing is left pointing at a passenger that is gone.
static func retire_settled(sim: PassengerSim) -> void:
	for i in range(sim._passengers.size() - 1, -1, -1):
		var p := sim._passengers[i]
		if not p.is_done() or sim.tick - p.outcome_tick <= PassengerSim.SETTLED_KEEP_TICKS:
			continue
		var leftover := settled_leftovers(sim, p)
		if leftover != "":
			sim.retire_refused += 1
			push_error("PassengerSim: settled passenger %d still holds %s" % [p.id, leftover])
			continue
		sim._by_id.erase(p.id)
		sim._passengers.remove_at(i)


## What a settled passenger still holds, or "" when it holds nothing.
static func settled_leftovers(sim: PassengerSim, p: Passenger) -> String:
	var held := PackedStringArray()
	if p.station != 0:
		held.append("a station")
	if p.seat_object != 0 or sim._seat_claims.values().has(p.id):
		held.append("a seat")
	if sim.cafes.visit_of(p.id) != null:
		held.append("a cafe visit")
	if sim.toilets.visit_of(p.id) != null:
		held.append("a toilet visit")
	if sim.shops.visit_of(p.id) != null:
		held.append("a kiosk visit")
	if sim.security.holds(p.id):
		held.append("a security place")
	if sim.standing.spot_of(p.id) != StandingSpots.NO_SPOT:
		held.append("a standing spot")
	if sim.files.holds(p.id) or sim.files.was_delayed(p.id):
		held.append("a boarding file place")
	for q in sim._queues.values():
		if (q["lane"] as Array).has(p.id) or (q["holding"] as Array).has(p.id):
			held.append("a queue place")
		elif q["serving"] == p.id:
			held.append("a service")
	for record in sim.cafes.queue_records():
		if (record["lane"] as Array).has(p.id) or record["serving"] == p.id:
			held.append("a cafe queue place")
	return ", ".join(held)


## Drops the results, no-shows and transport misses of flights FlightSim no
## longer lists.
static func prune_results(sim: PassengerSim) -> void:
	if (
		sim.flight_results.is_empty()
		and sim.no_shows.is_empty()
		and sim.arrivals.missed_by_flight.is_empty()
	):
		return
	var live := sim.flights.flight_ids()
	sim.arrivals.prune(live)
	for results in [sim.flight_results, sim.no_shows]:
		for flight_id in results.keys():
			if not live.has(flight_id):
				results.erase(flight_id)
