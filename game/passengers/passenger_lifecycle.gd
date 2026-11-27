class_name PassengerLifecycle
extends RefCounted
## The start and end of a passenger's life in PassengerSim: the spawn schedule,
## a new passenger at the entrance, doors closing, a made or missed outcome and
## the retirement of settled passengers. Static helpers over a sim; the state
## stays on the sim.

## Boarding within this many ticks of doors closing counts as a last-second save
## (5 game minutes = 5 sim seconds at 1x).
const CLOSE_CALL_TICKS := 100


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


## The schedule's passengers now due, in order, while the entrance line lets
## arrivals in (EntranceLine.room_for_arrivals()); the rest wait on the
## schedule, still due, so a debug batch is held back like a car is.
static func spawn_due(sim: PassengerSim) -> void:
	if sim.layout.passenger_entrances.is_empty():
		return
	var room := sim.entrance.room_for_arrivals(sim)
	while not sim._schedule.is_empty() and sim._schedule[0]["tick"] <= sim.tick and room > 0:
		room -= 1
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
	sim.entrance.take(sim, p)
	sim.passenger_spawned.emit(p.id)
	return p


## Missed passengers are the ones already in the terminal. Those still on the
## schedule for a closed flight will never board, so they are dropped and
## counted as no-shows, with the cause that holds now.
static func close_doors(sim: PassengerSim) -> void:
	var cause := "no_entrance" if sim.layout.passenger_entrances.is_empty() else "late"
	var kept: Array[Dictionary] = []
	for entry in sim._schedule:
		if sim.flights.is_doors_closed(entry["flight"]) and _held_outside(sim, entry):
			_count_line_miss(sim, entry["flight"])
		elif sim.flights.is_doors_closed(entry["flight"]):
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
	BookingOverrides.clear_closed(sim)
	for p in sim._passengers:
		if not p.is_done() and sim.flights.is_doors_closed(p.flight_id):
			if _in_bus_grace(sim, p):
				continue
			finish(sim, p, false)


static func _in_bus_grace(sim: PassengerSim, p: Passenger) -> bool:
	if sim.flights.state_of(p.flight_id) != FlightSim.State.DOORS_CLOSED:
		return false
	if p.stage == Passenger.Stage.ON_BUS:
		return true
	return p.stage == Passenger.Stage.APRON and sim.layout.bus_exits.has(p.exit_object)


static func finish(sim: PassengerSim, p: Passenger, made: bool) -> void:
	var close_call := false
	var was_stage := p.stage
	var was_apron := p.apron.duplicate()
	var was_apron_mm := p.apron_mm
	var was_pos := p.apron_position() if not p.apron.is_empty() else Vector3.ZERO
	if made:
		var doors_close := sim.flights.doors_close_tick(p.flight_id) if sim.flights != null else -1
		close_call = p.late or (doors_close >= 0 and doors_close - sim.tick <= CLOSE_CALL_TICKS)
		if close_call and p.at != Passenger.NO_CELL:
			PassengerThoughts.record(p, PassengerThoughts.Kind.MADE_CLOSE_CALL, sim.tick, p.at)
	else:
		p.missed_stage = p.stage
		# Held up by people traffic or a full gate, the miss is the terminal's.
		p.missed_stuck = GateCapacity.miss_cause(sim, p)
		# Waiting in the line outside for a check-in place: check-in congestion
		# (FlightResult.ENTRANCE_LINE_TEXT).
		# One marked NO_ROUTE outside (an unreachable desk) keeps that cause.
		var waiting := p.stage == Passenger.Stage.SPAWNED and sim.entrance.waiting(p.id)
		if waiting and p.stuck == Passenger.Stuck.NONE:
			p.missed_stuck = Passenger.Stuck.QUEUE_FULL
		if p.at != Passenger.NO_CELL:
			PassengerThoughts.record(p, PassengerThoughts.Kind.MISSED_FLIGHT, sim.tick, p.at)
	sim.entrance.forget(p.id)
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
	p.bin_detour_bin = 0
	p.bin_detour_end = 0
	p.outcome_tick = sim.tick
	p.needs_replan = false
	var result: Dictionary = sim.flight_results.get(
		p.flight_id, {"made": 0, "missed": 0, "close_calls": 0, "causes": {}}
	)
	if not result.has("close_calls"):
		result["close_calls"] = 0
	if made:
		sim._made += 1
		result["made"] += 1
		if close_call:
			result["close_calls"] += 1
	else:
		sim._missed += 1
		result["missed"] += 1
		QuitLog.note_missed(p.missed_stage, p.missed_stuck)
		var cause := Vector2i(p.missed_stage, p.missed_stuck)
		result["causes"][cause] = int(result["causes"].get(cause, 0)) + 1
		p.mood = 0
		p.clear_path()
		p.missed_phase = Passenger.MissedPhase.PAUSE
		if was_stage == Passenger.Stage.APRON and not was_apron.is_empty() and was_apron_mm > 0:
			p.apron = _reverse_apron_to_start(was_apron, was_apron_mm, was_pos)
			p.apron_mm = 0
		elif was_stage == Passenger.Stage.SPAWNED and not was_apron.is_empty():
			p.apron = [was_pos] as Array[Vector3]
			p.apron_mm = 0
		else:
			p.apron = []
			p.apron_mm = 0
	sim.flight_results[p.flight_id] = result
	sim.outcome.emit(p.id, made)


## Steps one missed passenger through its dismay pause, terminal exit walk,
## outside sidewalk walk to the road, or bounded no-route safety timeout.
static func step_missed(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick - p.outcome_tick >= PassengerSim.MISSED_MAX_WALK_OUT_TICKS:
		_finish_missed_walk(p)
		return
	match p.missed_phase:
		Passenger.MissedPhase.PAUSE:
			if sim.tick - p.outcome_tick < PassengerSim.MISSED_DISMAY_TICKS:
				return
			_begin_missed_walk_out(sim, p)
		Passenger.MissedPhase.APRON_RETURN:
			var total := p.apron_total_mm()
			var speed := p.pace_mm()
			p.odometer_mm += mini(speed, total - p.apron_mm)
			p.apron_mm = mini(p.apron_mm + speed, total)
			if p.apron_mm >= total:
				p.apron = []
				p.apron_mm = 0
				_begin_to_entrance(sim, p, false)
		Passenger.MissedPhase.TO_ENTRANCE:
			if p.needs_replan:
				p.needs_replan = false
				_replan_to_entrance(sim, p)
				if p.missed_phase != Passenger.MissedPhase.TO_ENTRANCE:
					return
			if p.is_moving():
				QueueRipple.walk(p, p.pace_mm(), sim.tick)
			if not p.is_moving():
				var door := _exit_entrance_at(sim, p.at)
				if door != 0:
					_start_road_from_door(sim, p, door)
				else:
					_begin_to_entrance(sim, p, false)
		Passenger.MissedPhase.TO_ROAD:
			var total := p.apron_total_mm()
			var speed := p.pace_mm()
			p.odometer_mm += mini(speed, total - p.apron_mm)
			p.apron_mm = mini(p.apron_mm + speed, total)
			if p.apron_mm >= total:
				_finish_missed_walk(p)
		Passenger.MissedPhase.STUCK_WAIT:
			if sim.tick - p.stage_tick >= PassengerSim.MISSED_NO_ROUTE_TIMEOUT_TICKS:
				_finish_missed_walk(p)
				return
			var beat := (
				posmod(sim.tick, PassengerSim.BEAT_TICKS) == posmod(p.id, PassengerSim.BEAT_TICKS)
			)
			if p.needs_replan or beat:
				p.needs_replan = false
				_retry_stuck_missed(sim, p)


static func _begin_missed_walk_out(sim: PassengerSim, p: Passenger) -> void:
	if (
		p.missed_stage == Passenger.Stage.APRON
		and not p.apron.is_empty()
		and p.apron_mm < p.apron_total_mm()
	):
		p.missed_phase = Passenger.MissedPhase.APRON_RETURN
		p.stage_tick = sim.tick
		step_missed(sim, p)
		return
	if p.missed_stage == Passenger.Stage.SPAWNED:
		if sim.site == null:
			_finish_missed_walk(p)
			return
		var pos := p.apron_position() if not p.apron.is_empty() else sim.grid.cell_to_world(p.at)
		var walk := OutsideWalks.to_road_from(sim, pos)
		if walk.is_empty():
			_enter_missed_stuck(sim, p, pos)
			return
		if walk.size() <= 1:
			_finish_missed_walk(p)
			return
		p.apron = walk
		p.apron_mm = 0
		p.missed_phase = Passenger.MissedPhase.TO_ROAD
		p.stage_tick = sim.tick
		step_missed(sim, p)
		return
	_begin_to_entrance(sim, p, true)


static func _begin_to_entrance(sim: PassengerSim, p: Passenger, step_now: bool) -> void:
	var door := _exit_entrance_at(sim, p.at)
	if door != 0:
		_start_road_from_door(sim, p, door)
		if step_now and p.missed_phase == Passenger.MissedPhase.TO_ROAD:
			step_missed(sim, p)
		return
	var path := _find_entrance_path(sim, p.at)
	if path.size() < 2:
		_enter_missed_stuck(sim, p)
		return
	p.set_path(path)
	p.missed_phase = Passenger.MissedPhase.TO_ENTRANCE
	p.stage_tick = sim.tick
	if step_now:
		QueueRipple.walk(p, p.pace_mm(), sim.tick)
		if not p.is_moving():
			var reached := _exit_entrance_at(sim, p.at)
			if reached != 0:
				_start_road_from_door(sim, p, reached)


static func _replan_to_entrance(sim: PassengerSim, p: Passenger) -> void:
	if not p.is_moving() or p.seg_mm == 0:
		_begin_to_entrance(sim, p, false)
		return
	var here := p.at
	var next := p.path[p.path_index + 1]
	var keep := p.seg_mm
	if sim.grid.can_staff_route(here, next):
		if _exit_entrance_at(sim, next) != 0:
			p.set_path([here, next])
			p.seg_mm = keep
			return
		var tail := _find_entrance_path(sim, next)
		if not tail.is_empty():
			tail.push_front(here)
			p.set_path(tail)
			p.seg_mm = keep
			return
	elif sim.grid.is_walkable(here):
		keep = Passenger.segment_mm(here, next) - keep
		p.at = next
		var back := _find_entrance_path(sim, here)
		if back.is_empty():
			back = [here]
		back.push_front(next)
		p.set_path(back)
		p.seg_mm = keep
		return
	p.clear_path()
	_enter_missed_stuck(sim, p)


static func _retry_stuck_missed(sim: PassengerSim, p: Passenger) -> void:
	if p.missed_stage == Passenger.Stage.SPAWNED and sim.site != null and not p.apron.is_empty():
		var walk := OutsideWalks.to_road_from(sim, p.apron_position())
		if walk.size() > 1:
			p.apron = walk
			p.apron_mm = 0
			p.missed_phase = Passenger.MissedPhase.TO_ROAD
			p.stage_tick = sim.tick
		elif walk.size() == 1:
			_finish_missed_walk(p)
		return
	if not p.apron.is_empty() and p.missed_stage == Passenger.Stage.APRON:
		if OutsideWalks._clear_ahead(sim, p, p.at):
			p.missed_phase = Passenger.MissedPhase.APRON_RETURN
			p.stage_tick = sim.tick
		return
	_begin_to_entrance(sim, p, false)


static func _start_road_from_door(sim: PassengerSim, p: Passenger, door: int) -> void:
	p.clear_path()
	if sim.site == null:
		_finish_missed_walk(p)
		return
	var walk := OutsideWalks.departure_to_road(sim, door)
	if walk.size() <= 1:
		_finish_missed_walk(p)
		return
	p.apron = walk
	p.apron_mm = 0
	p.missed_phase = Passenger.MissedPhase.TO_ROAD
	p.stage_tick = sim.tick


static func _enter_missed_stuck(
	sim: PassengerSim, p: Passenger, outside_pos := Vector3.ZERO
) -> void:
	p.clear_path()
	if outside_pos != Vector3.ZERO:
		p.apron = [outside_pos] as Array[Vector3]
		p.apron_mm = 0
	if p.missed_phase != Passenger.MissedPhase.STUCK_WAIT:
		p.stage_tick = sim.tick
	p.missed_phase = Passenger.MissedPhase.STUCK_WAIT


static func _finish_missed_walk(p: Passenger) -> void:
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	p.missed_phase = Passenger.MissedPhase.DONE


static func _entrance_doors(sim: PassengerSim) -> Array[int]:
	if sim.site != null or not sim.layout.passenger_entrances.is_empty():
		return sim.layout.passenger_entrances
	return sim.layout.entrances


static func _exit_entrance_at(sim: PassengerSim, cell: Vector2i) -> int:
	for door in _entrance_doors(sim):
		if sim.layout.door_cell(sim.grid, door) == cell:
			return door
	return 0


static func _find_entrance_path(sim: PassengerSim, from: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_mm := 0
	for door in _entrance_doors(sim):
		var cell := sim.layout.door_cell(sim.grid, door)
		var path := sim.grid.find_staff_path(from, cell)
		if path.is_empty():
			continue
		var mm := Passenger.path_mm(path)
		if best.is_empty() or mm < best_mm:
			best = path
			best_mm = mm
	return best


static func _reverse_apron_to_start(
	apron: Array[Vector3], mm_walked: int, here: Vector3
) -> Array[Vector3]:
	var out: Array[Vector3] = [here]
	var left := mm_walked
	var last_passed := 0
	for i in range(1, apron.size()):
		var seg := roundi(apron[i - 1].distance_to(apron[i]) * 1000.0)
		if left <= seg:
			break
		left -= seg
		last_passed = i
	for i in range(last_passed, -1, -1):
		if out[out.size() - 1].distance_to(apron[i]) > 0.001:
			out.append(apron[i])
	return out


## Whether schedule `entry` was due and held back because the entrance line
## was full (spawn_due()): the terminal had an entrance, so it would have
## spawned.
static func _held_outside(sim: PassengerSim, entry: Dictionary) -> bool:
	return not sim.layout.passenger_entrances.is_empty() and entry["tick"] <= sim.tick


## A scheduled passenger held back by the full line when its flight closed: a
## miss at the entrance, waiting outside for check-in (FlightResult).
static func _count_line_miss(sim: PassengerSim, flight_id: String) -> void:
	var result: Dictionary = sim.flight_results.get(
		flight_id, {"made": 0, "missed": 0, "close_calls": 0, "causes": {}}
	)
	sim._missed += 1
	result["missed"] += 1
	QuitLog.note_missed(Passenger.Stage.SPAWNED, Passenger.Stuck.QUEUE_FULL)
	var cause := Vector2i(Passenger.Stage.SPAWNED, Passenger.Stuck.QUEUE_FULL)
	result["causes"][cause] = int(result["causes"].get(cause, 0)) + 1
	sim.flight_results[flight_id] = result


## Retires the settled passengers kept for SETTLED_KEEP_TICKS. One that still
## holds a station, seat, cafe or toilet visit or queue place is a bug: it is
## reported and kept, so nothing is left pointing at a passenger that is gone.
static func retire_settled(sim: PassengerSim) -> void:
	for i in range(sim._passengers.size() - 1, -1, -1):
		var p := sim._passengers[i]
		if not p.is_done():
			continue
		if p.stage == Passenger.Stage.MISSED and p.missed_phase != Passenger.MissedPhase.NONE:
			if p.missed_phase != Passenger.MissedPhase.DONE:
				continue
		elif sim.tick - p.outcome_tick <= PassengerSim.SETTLED_KEEP_TICKS:
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
	for flight_id in sim.entrance.held_missed.keys():
		if not live.has(flight_id):
			sim.entrance.held_missed.erase(flight_id)
	for results in [sim.flight_results, sim.no_shows]:
		for flight_id in results.keys():
			if not live.has(flight_id):
				results.erase(flight_id)
