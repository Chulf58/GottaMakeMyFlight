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
const PARK_PICKUP_SHARE := 30
const CURB_PICKUP_PATIENCE_TICKS := 500
const CURB_TIMEOUT_MOOD_LOSS := 4
const CLAIM_PATIENCE_TICKS := 1600
const CLAIM_MIN_ORBIT_TICKS := 40
const CLAIM_BAG_MOOD_BONUS := 5
const CLAIM_TIMEOUT_MOOD_LOSS := 6
const SIDEWALK_Z := -59.95
const CURB_WAIT_X_OFFSETS := [0.0, -0.75, 0.75, -1.50, 1.50]
const CURB_WAIT_ROW_STEP_Z := 0.75
const CURB_WAIT_MIN_SEP_SQ := 0.25


static func schedule_deboarding(sim: PassengerSim, flight_id: String, count: int) -> void:
	if count <= 0 or sim.flights == null:
		return
	var stand_id := sim.flights.flight_stand_id(flight_id)
	if BusGatePairing.is_remote_stand_id(stand_id):
		count = mini(count, BusGatePairing.BUS_CAPACITY)
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
	p.hunger = (
		rng.randi_range(CafeSim.HUNGER_START_MIN, CafeSim.HUNGER_START_MAX + 10)
		if sim.cafes.hunger_enabled
		else 0
	)
	p.toilet_need = rng.randi_range(0, 65)
	p.boredom = 0
	CarryOnTraits.draw(rng, p)
	p.checked_bag_color = Bag.color_for_passenger(p.id)
	p.arrival_stop_cap = rng.randi_range(1, 2)
	p.arrival_stops = 0
	p.arrival_done = false
	p.wants_parked_car = rng.randi_range(0, 99) < PARK_PICKUP_SHARE
	p.pickup_vehicle = 0
	p.pickup_berth = -1
	p.claim_bag_id = 0
	p.claim_carousel = 0
	p.has_claimed_bag = false
	if sim.baggage != null:
		var inbound_bag := BaggageInbound.assign_owner(sim.baggage, flight_id, p.id)
		if inbound_bag != null:
			p.claim_bag_id = inbound_bag.id
			p.checked_bag_color = inbound_bag.color
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


## Active arriving passenger ids currently waiting at the curb for a PICKUP taxi,
## ordered oldest wait first (tie-break id).
static func curb_pickup_waiters(sim: PassengerSim) -> Array[int]:
	var waiters: Array[Passenger] = []
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if (
			p != null
			and p.is_arriving()
			and not p.arrival_done
			and p.stage == Passenger.Stage.WAIT_CURB_PICKUP
		):
			waiters.append(p)
	waiters.sort_custom(
		func(a: Passenger, b: Passenger) -> bool:
			if a.stage_tick != b.stage_tick:
				return a.stage_tick < b.stage_tick
			return a.id < b.id
	)
	var out: Array[int] = []
	for p in waiters:
		out.append(p.id)
	return out


## Releases any pickup claim on `p` and switches it onto an outdoor `TO_ROAD_EXIT` walk.
static func release_pickup_and_exit_to_road(
	sim: PassengerSim, p: Passenger, walk: Array[Vector3]
) -> void:
	if p.pickup_vehicle > 0 and sim.landside != null:
		sim.landside.release_claim(p.pickup_vehicle, p.id)
	p.pickup_vehicle = 0
	p.pickup_berth = -1
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	p.apron = walk
	p.apron_mm = 0
	sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)


static func advance(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick - p.spawn_tick >= ARRIVAL_MAX_LIFETIME_TICKS:
		finish(sim, p)
		return
	match p.stage:
		Passenger.Stage.TO_AIRSIDE_EXIT:
			_advance_airside_exit(sim, p)
		Passenger.Stage.TO_ROAD_EXIT:
			_advance_road_exit(sim, p)
		Passenger.Stage.TO_PARKED_CAR:
			_advance_parked_car(sim, p)
		Passenger.Stage.TO_CURB_PICKUP:
			_advance_curb_pickup(sim, p)
		Passenger.Stage.WAIT_CURB_PICKUP:
			_advance_wait_curb_pickup(sim, p)
		Passenger.Stage.TO_CLAIM:
			_advance_to_claim(sim, p)
		Passenger.Stage.AT_CLAIM:
			_advance_at_claim(sim, p)


static func step_outside(sim: PassengerSim, p: Passenger, speed: int) -> void:
	if p.stage == Passenger.Stage.WAIT_CURB_PICKUP:
		return
	var total := p.apron_total_mm()
	p.odometer_mm += mini(speed, total - p.apron_mm)
	p.apron_mm = mini(p.apron_mm + speed, total)
	if p.apron_mm < total:
		return
	if p.stage == Passenger.Stage.DEPLANING:
		if _waits_for_inbound_bus(sim, p):
			return
		_enter_airside_from_deplane(sim, p, p.exit_object)
	elif p.stage == Passenger.Stage.TO_ROAD_EXIT:
		finish(sim, p)
	elif p.stage == Passenger.Stage.TO_PARKED_CAR:
		_finish_parked_car_walk(sim, p)
	elif p.stage == Passenger.Stage.TO_CURB_PICKUP:
		_arrive_at_curb_pickup(sim, p)


## Moves arriving `p` from the remote stand curb onto the inbound shuttle bus
## without the outbound -6 mood penalty or outbound bus thought.
static func board_bus(sim: PassengerSim, p: Passenger) -> void:
	if sim == null or p == null or p.is_done():
		return
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	p.stuck = Passenger.Stuck.NONE
	sim._set_stage(p, Passenger.Stage.ON_BUS)


## Unloads arriving `p` from the inbound shuttle bus at `exit_id` into TO_AIRSIDE_EXIT.
static func unload_from_bus(sim: PassengerSim, p: Passenger, exit_id: int) -> void:
	if sim == null or p == null or p.is_done():
		return
	_enter_airside_from_deplane(sim, p, exit_id)


static func _enter_airside_from_deplane(sim: PassengerSim, p: Passenger, exit_id: int) -> void:
	p.apron = []
	p.apron_mm = 0
	var door := exit_id
	var door_cell := (
		sim.layout.door_cell(sim.grid, door)
		if sim.grid != null and door != 0
		else Passenger.NO_CELL
	)
	if door_cell == Passenger.NO_CELL or sim.grid == null or not sim.grid.in_bounds(door_cell):
		var fallback := 0
		if sim.grid != null:
			var open := sim.layout.open_exits(sim.grid)
			if not open.is_empty():
				fallback = open[0]
			elif not sim.layout.exits.is_empty():
				fallback = sim.layout.exits[0]
		door = fallback
		door_cell = (
			sim.layout.door_cell(sim.grid, door)
			if sim.grid != null and door != 0
			else Passenger.NO_CELL
		)
	if door_cell == Passenger.NO_CELL or sim.grid == null or not sim.grid.in_bounds(door_cell):
		finish(sim, p)
		return
	p.exit_object = door
	p.at = door_cell
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	sim._set_stage(p, Passenger.Stage.TO_AIRSIDE_EXIT)
	_plan_airside_exit(sim, p)


static func _waits_for_inbound_bus(sim: PassengerSim, p: Passenger) -> bool:
	if (
		sim.bus_shuttle == null
		or sim.flights == null
		or not sim.layout.bus_exits.has(p.exit_object)
	):
		return false
	var stand_id := sim.flights.flight_stand_id(p.flight_id)
	if not BusGatePairing.is_remote_stand_id(stand_id):
		return false
	if sim.bus_shuttle.has_inbound_for(p.flight_id):
		return true
	var fst := sim.flights.state_of(p.flight_id)
	if fst < 0 or fst >= FlightSim.State.DOORS_CLOSED:
		return false
	var gate := sim.flights.flight_gate(p.flight_id)
	return not sim.bus_shuttle.bus_state(gate).is_empty()


static func finish(sim: PassengerSim, p: Passenger) -> void:
	if p.arrival_done:
		return
	if p.pickup_vehicle > 0 and sim.landside != null:
		sim.landside.release_claim(p.pickup_vehicle, p.id)
	p.pickup_vehicle = 0
	p.pickup_berth = -1
	if p.claim_bag_id > 0 and not p.has_claimed_bag and sim.baggage != null:
		BaggageInbound.abandon_bag(sim.baggage, p.claim_bag_id, Bag.Cause.LATE)
	p.claim_bag_id = 0
	p.claim_carousel = 0
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
	var door := _entrance_at(sim, p.at)
	if door != 0:
		_start_outside_exit(sim, p, door)
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


static func _advance_parked_car(sim: PassengerSim, p: Passenger) -> void:
	if not _parked_car_valid(sim, p):
		_fallback_from_invalid_car(sim, p)
		return
	if p.walking_outside() or p.is_moving():
		return
	var door := _entrance_at(sim, p.at)
	if door != 0:
		var v := sim.landside.get_vehicle(p.pickup_vehicle)
		var walk := _walk_to_parked_car(sim, door, v.lot, v.stop)
		if walk.size() >= 2:
			p.clear_path()
			p.stuck = Passenger.Stuck.NONE
			p.apron = walk
			p.apron_mm = 0
			return
		_fallback_from_invalid_car(sim, p)
		return
	var path := _find_entrance_path(sim, p.at)
	if path.size() >= 2:
		p.stuck = Passenger.Stuck.NONE
		p.set_path(path)
		return
	if _entrance_doors(sim).is_empty() or sim.tick - p.stage_tick >= ARRIVAL_NO_ROUTE_TIMEOUT_TICKS:
		_fallback_from_invalid_car(sim, p)
		return
	p.stuck = Passenger.Stuck.NO_ROUTE


static func _advance_curb_pickup(sim: PassengerSim, p: Passenger) -> void:
	if sim.landside == null or sim.site == null or not sim.landside.is_berth_built(p.pickup_berth):
		_reroute_curb_pickup_or_exit(sim, p)
		return
	if p.walking_outside() or p.is_moving():
		return
	var door := _entrance_at(sim, p.at)
	if door != 0:
		var walk := _walk_to_curb_pickup(sim, door, p.pickup_berth, p.id)
		if walk.size() >= 2:
			p.clear_path()
			p.stuck = Passenger.Stuck.NONE
			p.apron = walk
			p.apron_mm = 0
			return
		_reroute_curb_pickup_or_exit(sim, p)
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


static func _advance_wait_curb_pickup(sim: PassengerSim, p: Passenger) -> void:
	if sim.landside == null or sim.site == null or not sim.landside.is_berth_built(p.pickup_berth):
		_fallback_to_sidewalk(sim, p)
		return
	if sim.tick - p.stage_tick >= CURB_PICKUP_PATIENCE_TICKS:
		if p.at != Passenger.NO_CELL and sim.grid != null and sim.grid.in_bounds(p.at):
			PassengerThoughts.record(p, PassengerThoughts.Kind.CURB_TIMEOUT, sim.tick, p.at)
		p.mood = maxi(p.mood - CURB_TIMEOUT_MOOD_LOSS, 0)
		_fallback_to_sidewalk(sim, p)


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
	if _try_start_claim(sim, p):
		return
	sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
	_advance_road_exit(sim, p)


static func _try_start_claim(sim: PassengerSim, p: Passenger) -> bool:
	if p.claim_bag_id <= 0 or p.has_claimed_bag or sim.baggage == null:
		return false
	var bag := sim.baggage.get_bag(p.claim_bag_id)
	if bag == null or bag.is_settled():
		p.claim_bag_id = 0
		p.claim_carousel = 0
		return false
	var routes := BaggageInbound.live_routes(sim.baggage)
	if routes == null:
		return false
	var candidates: Array[int] = []
	if bag.carousel > 0 and routes.is_ready_carousel(bag.carousel):
		candidates.append(bag.carousel)
	for cid in routes.connected_carousels():
		if not candidates.has(cid):
			candidates.append(cid)
	for cid in candidates:
		var chosen := _best_claim_spot(sim, routes, cid, p)
		if not chosen.is_empty():
			p.claim_carousel = cid
			sim._set_stage(p, Passenger.Stage.TO_CLAIM)
			if bool(chosen["at_spot"]):
				sim._set_stage(p, Passenger.Stage.AT_CLAIM)
			else:
				p.set_path(chosen["path"])
			return true
	BaggageInbound.abandon_bag(sim.baggage, p.claim_bag_id, Bag.Cause.NO_ROUTE)
	p.claim_bag_id = 0
	p.claim_carousel = 0
	return false


static func _advance_to_claim(sim: PassengerSim, p: Passenger) -> void:
	var bag := sim.baggage.get_bag(p.claim_bag_id) if sim.baggage != null else null
	var routes := BaggageInbound.live_routes(sim.baggage) if sim.baggage != null else null
	if (
		bag == null
		or bag.is_settled()
		or routes == null
		or not routes.is_ready_carousel(p.claim_carousel)
	):
		_abort_claim_to_exit(sim, p)
		return
	if p.is_moving():
		return
	if p.path.size() >= 2 and p.at == p.path.back():
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		sim._set_stage(p, Passenger.Stage.AT_CLAIM)
		_advance_at_claim(sim, p)
		return
	var chosen := _best_claim_spot(sim, routes, p.claim_carousel, p)
	if not chosen.is_empty():
		p.stuck = Passenger.Stuck.NONE
		if bool(chosen["at_spot"]):
			p.clear_path()
			sim._set_stage(p, Passenger.Stage.AT_CLAIM)
			_advance_at_claim(sim, p)
		else:
			p.set_path(chosen["path"])
		return
	if sim.tick - p.stage_tick >= ARRIVAL_NO_ROUTE_TIMEOUT_TICKS:
		_abort_claim_to_exit(sim, p)
		return
	p.stuck = Passenger.Stuck.NO_ROUTE


static func _advance_at_claim(sim: PassengerSim, p: Passenger) -> void:
	var bag := sim.baggage.get_bag(p.claim_bag_id) if sim.baggage != null else null
	var routes := BaggageInbound.live_routes(sim.baggage) if sim.baggage != null else null
	if (
		bag == null
		or bag.is_settled()
		or routes == null
		or not routes.is_ready_carousel(p.claim_carousel)
	):
		_abort_claim_to_exit(sim, p)
		return
	if (
		bag.carousel > 0
		and bag.carousel != p.claim_carousel
		and routes.is_ready_carousel(bag.carousel)
	):
		p.claim_carousel = bag.carousel
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		sim._set_stage(p, Passenger.Stage.TO_CLAIM)
		_advance_to_claim(sim, p)
		return
	if (
		bag.state == Bag.State.ON_CAROUSEL
		and bag.carousel == p.claim_carousel
		and sim.tick - bag.rest_tick >= CLAIM_MIN_ORBIT_TICKS
	):
		if BaggageInbound.claim_bag(sim.baggage, bag.id, p.id):
			p.has_claimed_bag = true
			p.claim_carousel = 0
			p.mood = mini(100, p.mood + CLAIM_BAG_MOOD_BONUS)
			if p.at != Passenger.NO_CELL and sim.grid != null and sim.grid.in_bounds(p.at):
				PassengerThoughts.record(p, PassengerThoughts.Kind.CLAIMED_BAG, sim.tick, p.at)
			sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
			_advance_road_exit(sim, p)
			return
	if sim.tick - p.stage_tick >= CLAIM_PATIENCE_TICKS:
		p.mood = maxi(0, p.mood - CLAIM_TIMEOUT_MOOD_LOSS)
		_abort_claim_to_exit(sim, p)


static func on_inbound_bag_lost(sim: PassengerSim, bag_id: int, passenger_id: int) -> void:
	if sim == null or bag_id <= 0:
		return
	var p := sim.get_passenger(passenger_id) if passenger_id > 0 else null
	if p == null or p.claim_bag_id != bag_id:
		for pid in sim.passenger_ids():
			var cand := sim.get_passenger(pid)
			if cand != null and cand.claim_bag_id == bag_id:
				p = cand
				break
	if p == null or p.arrival_done or p.has_claimed_bag or p.claim_bag_id != bag_id:
		return
	if p.stage == Passenger.Stage.TO_CLAIM or p.stage == Passenger.Stage.AT_CLAIM:
		_abort_claim_to_exit(sim, p)
	else:
		p.claim_bag_id = 0
		p.claim_carousel = 0
		sim.mark_changed()


static func _abort_claim_to_exit(sim: PassengerSim, p: Passenger) -> void:
	if p.claim_bag_id > 0 and not p.has_claimed_bag and sim.baggage != null:
		BaggageInbound.abandon_bag(sim.baggage, p.claim_bag_id, Bag.Cause.LOST)
	p.claim_bag_id = 0
	p.claim_carousel = 0
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
	_advance_road_exit(sim, p)


static func _best_claim_spot(
	sim: PassengerSim, routes: BagRoutes, carousel_id: int, p: Passenger
) -> Dictionary:
	var spots := _carousel_stand_spots(sim, routes, carousel_id)
	if spots.is_empty():
		return {}
	var start := posmod(p.id, spots.size())
	var best_path: Array[Vector2i] = []
	for i in spots.size():
		var spot: Vector2i = spots[(start + i) % spots.size()]
		if spot == p.at:
			return {"at_spot": true, "path": [] as Array[Vector2i]}
		var path := sim.grid.find_path(p.at, spot)
		if path.size() >= 2:
			if best_path.is_empty():
				best_path = path
				break
	if best_path.is_empty():
		return {}
	return {"at_spot": false, "path": best_path}


static func _carousel_stand_spots(
	sim: PassengerSim, routes: BagRoutes, carousel_id: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if sim.grid == null or carousel_id <= 0:
		return out
	var rec := sim.grid.get_object(carousel_id)
	if rec.is_empty() or StringName(rec["def"]) != BeltShaper.CLAIM_CAROUSEL:
		return out
	var def := BuildCatalog.get_def(BeltShaper.CLAIM_CAROUSEL)
	var fp := def.footprint(rec["anchor"], rec["facing"])
	var fp_set := {}
	for fc in fp:
		fp_set[fc] = true
	var room_id := sim.grid.room_at(rec["anchor"])
	for fc: Vector2i in fp:
		for step in BuildGrid.SIDE_STEP:
			var cell := fc + step
			if fp_set.has(cell) or out.has(cell):
				continue
			if not sim.grid.is_passenger_cell(cell) or routes.is_belt(cell):
				continue
			if room_id != 0 and sim.grid.room_at(cell) != room_id:
				continue
			out.append(cell)
	return out


static func _start_outside_exit(sim: PassengerSim, p: Passenger, door: int) -> void:
	if sim.site == null:
		finish(sim, p)
		return
	if sim.landside != null:
		if p.wants_parked_car and _try_start_parked_car(sim, p, door):
			return
		if _try_start_curb_pickup(sim, p, door):
			return
	_start_road_from_door(sim, p, door)


static func _try_start_parked_car(sim: PassengerSim, p: Passenger, door: int) -> bool:
	var candidate := sim.landside.eligible_parked_car()
	if candidate == null:
		return false
	var walk := _walk_to_parked_car(sim, door, candidate.lot, candidate.stop)
	if walk.size() < 2:
		return false
	var claimed := sim.landside.claim_parked_car(p.id)
	if claimed == null:
		return false
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	p.pickup_vehicle = claimed.id
	p.pickup_berth = -1
	p.apron = walk
	p.apron_mm = 0
	sim._set_stage(p, Passenger.Stage.TO_PARKED_CAR)
	if p.at != Passenger.NO_CELL and sim.grid != null and sim.grid.in_bounds(p.at):
		PassengerThoughts.record(p, PassengerThoughts.Kind.PARKED_CAR, sim.tick, p.at)
	return true


static func _try_start_curb_pickup(sim: PassengerSim, p: Passenger, door: int) -> bool:
	if sim.landside.built_berth_count() <= 0 or sim.landside.definition == null:
		return false
	var from_pt := sim.grid.cell_to_world(sim.layout.door_cell(sim.grid, door))
	var berth := _nearest_built_berth(sim, from_pt)
	if berth < 0:
		return false
	var walk := _walk_to_curb_pickup(sim, door, berth, p.id)
	if walk.size() < 2:
		return false
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	p.pickup_vehicle = 0
	p.pickup_berth = berth
	p.apron = walk
	p.apron_mm = 0
	sim._set_stage(p, Passenger.Stage.TO_CURB_PICKUP)
	return true


static func _finish_parked_car_walk(sim: PassengerSim, p: Passenger) -> void:
	if (
		sim.landside != null
		and p.pickup_vehicle > 0
		and sim.landside.board_parked_car(p.pickup_vehicle, p.id)
	):
		p.pickup_vehicle = 0
		finish(sim, p)
		return
	_fallback_from_invalid_car(sim, p)


static func _arrive_at_curb_pickup(sim: PassengerSim, p: Passenger) -> void:
	var pos := p.apron_position()
	if (
		sim.landside != null
		and sim.landside.definition != null
		and p.pickup_berth >= 0
		and _point_taken(pos, _curb_taken_positions(sim, p.pickup_berth, p.id))
	):
		pos = _curb_wait_spot(sim, p.pickup_berth, p.id)
	p.apron = [pos] as Array[Vector3]
	p.apron_mm = 0
	p.clear_path()
	p.stuck = Passenger.Stuck.NONE
	sim._set_stage(p, Passenger.Stage.WAIT_CURB_PICKUP)


static func _parked_car_valid(sim: PassengerSim, p: Passenger) -> bool:
	if sim.landside == null or p.pickup_vehicle <= 0:
		return false
	var v := sim.landside.get_vehicle(p.pickup_vehicle)
	if v == null or v.stage != LandsideVehicle.Stage.PARKED or not v.claimants.has(p.id):
		return false
	return v.lot >= 0 and v.lot < sim.landside.lots_built.size() and sim.landside.lots_built[v.lot]


static func _fallback_from_invalid_car(sim: PassengerSim, p: Passenger) -> void:
	if sim.landside != null and p.pickup_vehicle > 0:
		sim.landside.release_claim(p.pickup_vehicle, p.id)
	p.pickup_vehicle = 0
	if not p.walking_outside():
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
		_advance_road_exit(sim, p)
		return
	var here := p.apron_position()
	var backtrack := _backtrack_to_sidewalk(sim, p, here)
	var curb := _curb_walk_from_outdoor(sim, backtrack, p.id)
	if not curb.is_empty():
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		p.pickup_berth = int(curb["berth"])
		p.apron = curb["walk"]
		p.apron_mm = 0
		sim._set_stage(p, Passenger.Stage.TO_CURB_PICKUP)
		return
	var road_walk := _walk_backtrack_to_road(sim, backtrack)
	if road_walk.size() <= 1:
		finish(sim, p)
		return
	release_pickup_and_exit_to_road(sim, p, road_walk)


static func _reroute_curb_pickup_or_exit(sim: PassengerSim, p: Passenger) -> void:
	if p.walking_outside():
		var curb := _curb_walk_from_outdoor(sim, [p.apron_position()], p.id)
		if not curb.is_empty():
			p.pickup_berth = int(curb["berth"])
			p.apron = curb["walk"]
			p.apron_mm = 0
			return
	_fallback_to_sidewalk(sim, p)


static func _curb_walk_from_outdoor(
	sim: PassengerSim, prefix: Array[Vector3], exclude_pid := 0
) -> Dictionary:
	if sim.landside == null or sim.site == null or sim.landside.built_berth_count() <= 0:
		return {}
	var walk: Array[Vector3] = prefix.duplicate()
	var start_pt: Vector3 = walk[walk.size() - 1]
	if sim.grid != null and start_pt.z <= _sidewalk_limit_z(sim):
		var to_road := OutsideWalks.to_road_from(sim, start_pt)
		if to_road.is_empty():
			return {}
		var last := to_road.size()
		if last >= 2 and absf(to_road[last - 1].z - sim.site.road_z) < 0.05:
			last -= 1
		for i in last:
			_append_point(walk, to_road[i])
	var sidewalk_pt: Vector3 = walk[walk.size() - 1]
	var berth := _nearest_built_berth(sim, sidewalk_pt)
	if berth < 0:
		return {}
	var target := _curb_wait_spot(sim, berth, exclude_pid)
	_append_point(walk, Vector3(sidewalk_pt.x, target.y, target.z))
	_append_point(walk, target)
	if walk.size() < 2:
		return {}
	return {"berth": berth, "walk": walk}


static func _sidewalk_limit_z(sim: PassengerSim) -> float:
	return sim.site.grid_origin.z + sim.grid.size.y + 0.7


static func _fallback_to_sidewalk(sim: PassengerSim, p: Passenger) -> void:
	p.pickup_berth = -1
	if not p.walking_outside():
		p.clear_path()
		p.stuck = Passenger.Stuck.NONE
		sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
		_advance_road_exit(sim, p)
		return
	var walk := OutsideWalks.to_road_from(sim, p.apron_position())
	if walk.size() <= 1:
		finish(sim, p)
		return
	release_pickup_and_exit_to_road(sim, p, walk)


static func _walk_to_parked_car(
	sim: PassengerSim, door: int, spot: int, slot: int
) -> Array[Vector3]:
	if sim.site == null or sim.landside == null or sim.landside.paths == null:
		return [] as Array[Vector3]
	var lot_walk := sim.landside.paths.lot_walk(spot, slot)
	if lot_walk.size() < 2:
		return [] as Array[Vector3]
	var door_walk := OutsideWalks.departure_to_road(sim, door)
	if door_walk.size() < 2:
		return [] as Array[Vector3]
	var walk: Array[Vector3] = []
	walk.assign(door_walk.slice(0, door_walk.size() - 1))
	var edge_pt: Vector3 = walk[walk.size() - 1]
	var lot_rev: Array[Vector3] = lot_walk.duplicate()
	lot_rev.reverse()
	var cross_pt: Vector3 = lot_rev[0]
	if Vector2(edge_pt.x, edge_pt.z).distance_to(Vector2(cross_pt.x, cross_pt.z)) > 0.05:
		_append_point(walk, Vector3(edge_pt.x, sim.site.ground_height, SIDEWALK_Z))
		_append_point(walk, Vector3(cross_pt.x, sim.site.ground_height, SIDEWALK_Z))
	for pt in lot_rev:
		_append_point(walk, pt)
	return walk


static func _walk_to_curb_pickup(
	sim: PassengerSim, door: int, berth: int, exclude_pid := 0
) -> Array[Vector3]:
	if sim.site == null or sim.landside == null or sim.landside.definition == null:
		return [] as Array[Vector3]
	var door_walk := OutsideWalks.departure_to_road(sim, door)
	if door_walk.size() < 2:
		return [] as Array[Vector3]
	var target := _curb_wait_spot(sim, berth, exclude_pid)
	var walk: Array[Vector3] = []
	walk.assign(door_walk.slice(0, door_walk.size() - 1))
	var edge_pt: Vector3 = walk[walk.size() - 1]
	_append_point(walk, Vector3(edge_pt.x, target.y, target.z))
	_append_point(walk, target)
	return walk


static func _curb_taken_positions(
	sim: PassengerSim, berth: int, exclude_pid: int
) -> Array[Vector3]:
	var taken: Array[Vector3] = []
	for id in sim.passenger_ids():
		if id == exclude_pid:
			continue
		var other := sim.get_passenger(id)
		if (
			other == null
			or other.arrival_done
			or not other.is_arriving()
			or other.pickup_berth != berth
			or other.apron.is_empty()
		):
			continue
		if other.stage == Passenger.Stage.TO_CURB_PICKUP:
			taken.append(other.apron[other.apron.size() - 1])
		elif other.stage == Passenger.Stage.WAIT_CURB_PICKUP:
			taken.append(other.apron[0])
	return taken


static func _point_taken(cand: Vector3, taken: Array[Vector3]) -> bool:
	for pt in taken:
		var dx := cand.x - pt.x
		var dz := cand.z - pt.z
		if dx * dx + dz * dz < CURB_WAIT_MIN_SEP_SQ:
			return true
	return false


static func _curb_wait_spot(sim: PassengerSim, berth: int, exclude_pid: int) -> Vector3:
	var base := sim.landside.definition.berth_get_out(berth)
	var taken := _curb_taken_positions(sim, berth, exclude_pid)
	var cols := CURB_WAIT_X_OFFSETS.size()
	for slot_idx in taken.size() + 1:
		var row := slot_idx / cols
		var col := slot_idx % cols
		var cand := Vector3(
			base.x + float(CURB_WAIT_X_OFFSETS[col]),
			base.y,
			base.z - CURB_WAIT_ROW_STEP_Z * float(row)
		)
		if not _point_taken(cand, taken):
			return cand
	return base


static func _nearest_built_berth(sim: PassengerSim, from_pt: Vector3) -> int:
	if sim.landside == null or sim.landside.definition == null:
		return -1
	var best := -1
	var best_d := INF
	for i in sim.landside.definition.berth_count():
		if not sim.landside.is_berth_built(i):
			continue
		var pt := sim.landside.definition.berth_get_out(i)
		var d := Vector2(from_pt.x - pt.x, from_pt.z - pt.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


static func _backtrack_to_sidewalk(
	sim: PassengerSim, p: Passenger, here: Vector3
) -> Array[Vector3]:
	if sim.site == null or sim.grid == null:
		return [here] as Array[Vector3]
	var sidewalk_limit_z := _sidewalk_limit_z(sim)
	if here.z <= sidewalk_limit_z or p.apron.size() < 2:
		return [here] as Array[Vector3]
	var passed: Array[Vector3] = [p.apron[0]]
	var left := p.apron_mm
	for i in range(1, p.apron.size()):
		var seg := p.apron_segment_mm(i)
		if left <= seg:
			break
		passed.append(p.apron[i])
		left -= seg
	_append_point(passed, here)
	passed.reverse()
	var out: Array[Vector3] = []
	for pt in passed:
		_append_point(out, pt)
		if pt.z <= sidewalk_limit_z:
			break
	if out.is_empty():
		out.append(here)
	return out


static func _walk_backtrack_to_road(sim: PassengerSim, backtrack: Array[Vector3]) -> Array[Vector3]:
	var end_pt: Vector3 = backtrack[backtrack.size() - 1]
	var tail := OutsideWalks.to_road_from(sim, end_pt)
	if tail.is_empty():
		return backtrack
	var out := backtrack.duplicate()
	for pt in tail:
		_append_point(out, pt)
	return out


static func _append_point(points: Array[Vector3], pt: Vector3) -> void:
	if points.is_empty() or not points[points.size() - 1].is_equal_approx(pt):
		points.append(pt)


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
	var stand_id := sim.flights.flight_stand_id(flight_id) if sim.flights != null else ""
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
		if BusGatePairing.is_remote_stand_id(stand_id):
			continue
		var walk := OutsideWalks.departure(sim, door, model)
		if walk.size() >= 2:
			walk.reverse()
			return {"door": door, "walk": walk}
	if BusGatePairing.is_remote_stand_id(stand_id) and sim.flights != null:
		var bus_door := fallback_door
		for door in candidates:
			if (
				sim.layout.bus_exits.has(door)
				and sim.grid.in_bounds(sim.layout.door_cell(sim.grid, door))
			):
				bus_door = door
				break
		var stand := sim.flights.flight_stand(flight_id)
		if stand.is_empty():
			stand = sim.flights.remote_stand_grounds().get(stand_id, {}).get("stand", {})
		if not stand.is_empty():
			var site := (sim.grid as SiteGrid).site if sim.grid is SiteGrid else sim.site
			var gy := AirstairsPose.ground_y(stand) if site != null else sim.grid.origin.y
			var stop_pose := BusShuttleRoutes.stop_pose_for(stand, model, gy)
			var door_idx := posmod(sim._next_id, 4)
			var walk := BusShuttleRoutes.bus_unload_walk(stop_pose, door_idx)
			if walk.size() >= 2:
				walk.reverse()
				return {"door": bus_door, "walk": walk}
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
