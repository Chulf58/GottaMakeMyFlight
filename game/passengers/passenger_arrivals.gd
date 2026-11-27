class_name PassengerArrivals
extends RefCounted
## Deboarding & landside exit lifecycle for arriving passengers (Arrivals A1).
## Spawns arriving passengers staggered across FlightSim.State.DEBOARDING,
## walks them up the jet bridge / reversed apron path into the terminal, routes
## airside -> landside by priority (airside_exit_door -> divider door ->
## reverse scanner), lets them take optional landside toilet/cafe/shop stops,
## and walks them out the nearest entrance to the road.

const DEBOARD_FINISH_MARGIN_TICKS := 10
const ARRIVAL_NO_ROUTE_TIMEOUT_TICKS := 1200
const ARRIVAL_MAX_LIFETIME_TICKS := 6000


static func schedule_deboarding(sim: PassengerSim, flight_id: String, count: int) -> void:
	if count <= 0 or sim.flights == null:
		return
	var window := sim.flights.deboarding_window(flight_id)
	var start_t := maxi(sim.tick + 1, window.x)
	var end_t := maxi(start_t, window.y - DEBOARD_FINISH_MARGIN_TICKS)
	for i in count:
		var at := start_t
		if count > 1 and end_t > start_t:
			at = start_t + roundi(float(i) * float(end_t - start_t) / float(count - 1))
		var variant := sim.clock.rng.randi_range(0, 1) if sim.clock != null else (i % 2)
		add_spawn(sim, at, flight_id, variant)


static func add_spawn(sim: PassengerSim, at: int, flight_id: String, variant: int) -> void:
	var entry := {"tick": at, "flight": flight_id, "variant": variant}
	var pos := sim._arrival_schedule.size()
	while pos > 0 and sim._arrival_schedule[pos - 1]["tick"] > at:
		pos -= 1
	sim._arrival_schedule.insert(pos, entry)
	sim.mark_changed()


static func spawn_due(sim: PassengerSim) -> void:
	while not sim._arrival_schedule.is_empty() and sim._arrival_schedule[0]["tick"] <= sim.tick:
		var entry: Dictionary = sim._arrival_schedule[0]
		sim._arrival_schedule.remove_at(0)
		spawn(sim, entry["flight"], int(entry["variant"]))


static func spawn(sim: PassengerSim, flight_id: String, variant: int) -> Passenger:
	var chosen := _arrival_door_and_walk(sim, flight_id)
	var door: int = chosen["door"]
	if door == 0:
		return null
	var walk: Array[Vector3] = chosen["walk"]
	var p := Passenger.new()
	p.id = sim._next_id
	sim._next_id += 1
	p.direction = Passenger.Direction.ARRIVING
	p.flight_id = flight_id
	p.variant = variant
	p.spawn_tick = sim.tick
	p.stage_tick = sim.tick
	var window := sim.flights.deboarding_window(flight_id) if sim.flights != null else Vector2i.ZERO
	p.boarding_tick = window.y if window.y >= 0 else sim.tick
	p.cleared = true
	p.exit_object = door
	p.at = sim.layout.door_cell(sim.grid, door)
	p.clear_path()
	var rng := sim.clock.rng if sim.clock != null else RandomNumberGenerator.new()
	p.hunger = rng.randi_range(0, 45) if sim.cafes.hunger_enabled else 0
	p.toilet_need = rng.randi_range(0, 65)
	p.boredom = 0
	CarryOnTraits.draw(rng, p)
	p.checked_bag_color = Bag.color_for_passenger(p.id)
	p.arrival_stop_cap = rng.randi_range(1, 2)
	p.arrival_stops = 0
	p.arrival_done = false
	if not walk.is_empty():
		p.stage = Passenger.Stage.DEPLANING
		p.apron = walk
		p.apron_mm = 0
	else:
		p.stage = Passenger.Stage.TO_AIRSIDE_EXIT
	sim._passengers.append(p)
	sim._by_id[p.id] = p
	sim.mark_changed()
	sim.arrival_spawned.emit(p.id)
	if p.at != Passenger.NO_CELL and sim.grid != null and sim.grid.in_bounds(p.at):
		PassengerThoughts.record(p, PassengerThoughts.Kind.LANDED_SMOOTH, sim.tick, p.at)
	if p.stage == Passenger.Stage.TO_AIRSIDE_EXIT:
		_plan_airside_exit(sim, p)
	return p


static func advance(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick - p.spawn_tick >= ARRIVAL_MAX_LIFETIME_TICKS:
		finish(sim, p)
		return
	match p.stage:
		Passenger.Stage.TO_AIRSIDE_EXIT:
			_advance_airside_exit(sim, p)
		Passenger.Stage.TO_ROAD_EXIT:
			_advance_road_exit(sim, p)


static func step_outside(sim: PassengerSim, p: Passenger, speed: int) -> void:
	var total := p.apron_total_mm()
	p.odometer_mm += mini(speed, total - p.apron_mm)
	p.apron_mm = mini(p.apron_mm + speed, total)
	if p.apron_mm < total:
		return
	if p.stage == Passenger.Stage.DEPLANING:
		p.apron = []
		p.apron_mm = 0
		var door_cell := sim.layout.door_cell(sim.grid, p.exit_object)
		if door_cell != Passenger.NO_CELL:
			p.at = door_cell
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		sim._set_stage(p, Passenger.Stage.TO_AIRSIDE_EXIT)
		_plan_airside_exit(sim, p)
	elif p.stage == Passenger.Stage.TO_ROAD_EXIT:
		finish(sim, p)


static func finish(sim: PassengerSim, p: Passenger) -> void:
	if p.arrival_done:
		return
	sim._leave_station(p)
	sim._release_seat(p)
	sim.cafes.cleanup(p)
	sim.toilets.cleanup(p)
	sim.shops.cleanup(p)
	sim.info_desks.cleanup(p)
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	p.stuck = Passenger.Stuck.NONE
	p.late = false
	p.arrival_done = true
	p.outcome_tick = sim.tick
	sim.mark_changed()
	sim.arrival_finished.emit(p.id)


static func _advance_airside_exit(sim: PassengerSim, p: Passenger) -> void:
	if p.is_moving():
		return
	if p.path.size() >= 2 and p.at == p.path.back():
		_enter_landside(sim, p, true)
		return
	_plan_airside_exit(sim, p)
	if not p.is_moving() and p.stuck == Passenger.Stuck.NO_ROUTE:
		if sim.tick - p.stage_tick >= ARRIVAL_NO_ROUTE_TIMEOUT_TICKS:
			finish(sim, p)


static func _advance_road_exit(sim: PassengerSim, p: Passenger) -> void:
	if p.walking_outside() or p.is_moving():
		return
	# Seam (A2 landside pickup): attach car/curb pickup routing before entrance road exit.
	var door := _entrance_at(sim, p.at)
	if door != 0:
		_start_road_from_door(sim, p, door)
		return
	var path := _find_entrance_path(sim, p.at)
	if path.size() >= 2:
		p.stuck = Passenger.Stuck.NONE
		p.set_path(path)
		return
	if _entrance_doors(sim).is_empty() or sim.tick - p.stage_tick >= ARRIVAL_NO_ROUTE_TIMEOUT_TICKS:
		finish(sim, p)
		return
	p.stuck = Passenger.Stuck.NO_ROUTE


static func _plan_airside_exit(sim: PassengerSim, p: Passenger) -> void:
	var best := _best_airside_exit_door_path(sim, p.at)
	if best.is_empty():
		best = _best_divider_door_path(sim, p.at)
	if best.is_empty():
		best = _best_reverse_scanner_path(sim, p.at)
	if best.size() >= 2:
		p.stuck = Passenger.Stuck.NONE
		p.set_path(best)
		return
	# Open-plan terminal with no divider: already able to route straight to an entrance.
	if not _find_entrance_path(sim, p.at).is_empty() or _entrance_at(sim, p.at) != 0:
		_enter_landside(sim, p, false)
		return
	p.stuck = Passenger.Stuck.NO_ROUTE


static func _enter_landside(sim: PassengerSim, p: Passenger, crossed_door: bool) -> void:
	p.cleared = false
	p.stuck = Passenger.Stuck.NONE
	p.clear_path()
	if crossed_door and p.at != Passenger.NO_CELL:
		PassengerThoughts.record(p, PassengerThoughts.Kind.QUICK_EXIT, sim.tick, p.at)
	# Seam (A3 baggage claim): route to baggage claim room/carousel before TO_ROAD_EXIT when built.
	sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
	_advance_road_exit(sim, p)


static func _start_road_from_door(sim: PassengerSim, p: Passenger, door: int) -> void:
	p.clear_path()
	if sim.site == null:
		finish(sim, p)
		return
	var walk := OutsideWalks.departure_to_road(sim, door)
	if walk.size() <= 1:
		finish(sim, p)
		return
	p.stuck = Passenger.Stuck.NONE
	p.apron = walk
	p.apron_mm = 0


static func _best_airside_exit_door_path(sim: PassengerSim, from: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_mm := 0
	for door_id in sim.layout.airside_exits:
		if not sim.layout.is_airside_exit_open(sim.grid, door_id):
			continue
		var anchor := sim.layout.door_cell(sim.grid, door_id)
		var land := anchor + sim.layout.door_outward(sim.grid, door_id)
		if not _can_exit_from_landside(sim, land):
			continue
		var to_door: Array[Vector2i] = []
		if from == anchor:
			to_door = [anchor]
		else:
			to_door = sim.grid.find_path(from, anchor)
		if to_door.is_empty():
			continue
		var full := to_door.duplicate()
		full.append(land)
		var mm := Passenger.path_mm(full)
		if best.is_empty() or mm < best_mm:
			best = full
			best_mm = mm
	return best


static func _best_divider_door_path(sim: PassengerSim, from: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_mm := 0
	for pair: Array in sim.grid.divider_door_pairs():
		for attempt in [[pair[0], pair[1]], [pair[1], pair[0]]]:
			var in_cell: Vector2i = attempt[0]
			var out_cell: Vector2i = attempt[1]
			if (
				not sim.grid.is_passenger_cell(out_cell)
				or not _can_exit_from_landside(sim, out_cell)
			):
				continue
			var to_door: Array[Vector2i] = []
			if from == in_cell:
				to_door = [in_cell]
			else:
				to_door = sim.grid.find_path(from, in_cell)
			if to_door.is_empty():
				continue
			var full := to_door.duplicate()
			full.append(out_cell)
			var mm := Passenger.path_mm(full)
			if best.is_empty() or mm < best_mm:
				best = full
				best_mm = mm
	return best


static func _best_reverse_scanner_path(sim: PassengerSim, from: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_mm := 0
	for station in sim.layout.scanners:
		var passage: Array = sim.layout.passages.get(station, [])
		if passage.size() < 2:
			continue
		var air_cell: Vector2i = passage[passage.size() - 1]
		var land_cell: Vector2i = passage[0]
		if not _can_exit_from_landside(sim, land_cell):
			continue
		var to_exit: Array[Vector2i] = []
		if from == air_cell:
			to_exit = [air_cell]
		else:
			to_exit = sim.grid.find_path(from, air_cell)
		if to_exit.is_empty():
			continue
		var full := to_exit.duplicate()
		for idx in range(passage.size() - 2, -1, -1):
			full.append(passage[idx])
		var mm := Passenger.path_mm(full)
		if best.is_empty() or mm < best_mm:
			best = full
			best_mm = mm
	return best


static func _can_exit_from_landside(sim: PassengerSim, cell: Vector2i) -> bool:
	if _entrance_at(sim, cell) != 0:
		return true
	var doors := _entrance_doors(sim)
	if doors.is_empty():
		return sim.grid.is_passenger_cell(cell)
	return not _find_entrance_path(sim, cell).is_empty()


static func _arrival_door_and_walk(sim: PassengerSim, flight_id: String) -> Dictionary:
	var gate := (
		sim.flights.flight_gate(flight_id) if sim.flights != null else FlightSim.DEFAULT_GATE
	)
	var model := PlaneClasses.flight_model(sim.flights, flight_id) if sim.flights != null else ""
	var candidates := sim.layout.open_exits_for(sim.grid, gate)
	if candidates.is_empty():
		candidates = sim.layout.open_exits(sim.grid)
	if candidates.is_empty():
		candidates = sim.layout.exits
	var fallback_door := 0
	for door in candidates:
		if fallback_door == 0 and sim.grid.in_bounds(sim.layout.door_cell(sim.grid, door)):
			fallback_door = door
		var walk := OutsideWalks.departure(sim, door, model)
		if walk.size() >= 2:
			walk.reverse()
			return {"door": door, "walk": walk}
	return {"door": fallback_door, "walk": [] as Array[Vector3]}


static func _entrance_doors(sim: PassengerSim) -> Array[int]:
	if sim.site != null or not sim.layout.passenger_entrances.is_empty():
		return sim.layout.passenger_entrances
	return sim.layout.entrances


static func _entrance_at(sim: PassengerSim, cell: Vector2i) -> int:
	for door in _entrance_doors(sim):
		if sim.layout.door_cell(sim.grid, door) == cell:
			return door
	return 0


static func _find_entrance_path(sim: PassengerSim, from: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_mm := 0
	for door in _entrance_doors(sim):
		var cell := sim.layout.door_cell(sim.grid, door)
		var path: Array[Vector2i] = []
		if from == cell:
			path = [cell]
		else:
			path = sim.grid.find_path(from, cell)
		if path.is_empty():
			continue
		var mm := Passenger.path_mm(path)
		if best.is_empty() or mm < best_mm:
			best = path
			best_mm = mm
	return best
