class_name BaggageSim
extends Node
## Checked bags from the check-in desk along the player's belt to a bag room
## and onto the plane (decisions baggage-rides-a-player-built-belt-from-check-
## in-to-a-bag-roo and baggage-bag-sim-design-route-field-belt-capacity-
## cutoff).
##
## Every passenger checks one bag when PassengerSim emits checked_in. The bag
## waits at its desk until the belt cell the desk's outlet points into is
## free and has a route, then rides the route field (BagRoutes) one cell at a
## time at BELT_MM per tick, and is IN_ROOM when it reaches the centre of a
## belt end in a ready bag room. A belt cell holds one bag. On the flight's
## cutoff tick (doors close minus LOAD_LEAD_TICKS) a bag in the room is
## loaded and every other bag of the flight is missed; a bag reaching the
## room on the cutoff tick itself is loaded. A bag checked in on or after
## the cutoff is missed at once. A missed bag's cause is LATE (still at the
## desk waiting for space, or riding), NO_BELT (its desk has no belt), NO_ROUTE
## (no way from where it is to a bag room) or LOST (the belt under it or its
## bag room's end was taken away; settled at once). bag_settled fires once
## per bag. The rating and the airline fee (Baggage B4) read bag_settled or
## results; this node changes neither.
##
## Tick order, fixed: reconcile (only after a build edit: rebuild the field
## from the grid as it stands then and bring every bag in line with it),
## transfers (computed from the state the tick started with), moves, then
## settle the flights whose cutoff has come, retire old settled bags and drop
## the results of flights FlightSim no longer lists. A bag is made in the
## check_in() call itself and first moves on the next tick, whichever of the
## two sims ticks first.
##
## Transfers: a bag at a cell centre wants the next cell of the field, and
## the head of each desk's queue (its lowest bag id) wants the desk's entry
## cell. A wanted cell that no bag owns or stands on at the start of the tick
## goes to the bag that has waited longest (wait_tick), then the lower id.
## A bag that gets a cell owns it at once, 1000 mm from its centre (500 from
## a desk); the cell it left stays taken while the bag's body is on it.
##
## Reconcile (final-grid semantics: a belt taken away and laid again before
## the next tick changes nothing): a bag whose body is on a cell that is no
## longer belt is LOST; one still short of its cell's centre whose committed
## belt-to-belt edge no longer joins (the cell behind gone, a wall, a port
## turned away) stops where it is (BLOCKED) and goes on when the edge comes
## back, while the half cell from a desk needs no desk; one at a centre with
## no route is BLOCKED and RIDING again once a route exists; an IN_ROOM bag
## whose end is no longer a root is LOST. AT_DESK bags retry every tick.

## A bag settled as loaded (true) or missed, exactly once.
signal bag_settled(bag_id: int, passenger_id: int, flight_id: String, loaded: bool)
## Automated baggage_cart shuttle lifecycle (board 73fa430a; future Ramp Agent hook eddcd9cd).
signal shuttle_dispatched(shuttle_id: int, flight_id: String, cart_id: int)
signal shuttle_arrived(shuttle_id: int, flight_id: String)
signal shuttle_returned(shuttle_id: int, cart_id: int)
signal shuttle_cancelled(shuttle_id: int, cart_id: int)

## Belt speed in mm per tick: 1 m/s, a tuning value.
const BELT_MM := 50
## The last cart leaves the bag room this many ticks before the doors close.
const LOAD_LEAD_TICKS := 200
## Settled bags are kept this long, then dropped.
const SETTLED_KEEP_TICKS := 200
const CART_DEF: StringName = &"baggage_cart"

@export var clock: SimClock
@export var flights: FlightSim
@export var passengers: PassengerSim
## In a scene the grid comes from BuildMode; tests call bind() instead.
@export var build_mode: BuildMode

## Optional Ramp Agent hook: func(cart_id: int, flight_id: String) -> bool.
## Unset: placed carts dispatch automatically at cutoff.
var shuttle_can_dispatch := Callable()

var grid: BuildGrid
var routes: BagRoutes
## True after a build edit until the next tick's reconcile. No save is taken
## while it is set (SaveGame.save_problem()).
var routes_stale := false
var tick := 0
## Flight id -> {"loaded": n, "missed": n, "causes": {cause name: n}}.
## Dropped when FlightSim no longer lists the flight.
var results := {}
var loaded_total := 0
var missed_total := 0

var _bags: Array[Bag] = []
var _by_id := {}
var _next_id := 1
var _shuttles: Array[BaggageShuttle] = []
var _shuttle_by_id := {}
var _next_shuttle_id := 1


func _ready() -> void:
	if clock == null or flights == null or build_mode == null:
		return
	bind(clock, flights, build_mode.grid, passengers)


## Listens to the clock, the grid's edits and loads, and (when given) the
## passengers' check-ins.
func bind(
	with_clock: SimClock,
	with_flights: FlightSim,
	with_grid: BuildGrid,
	with_passengers: PassengerSim = null,
) -> void:
	clock = with_clock
	flights = with_flights
	grid = with_grid
	passengers = with_passengers
	tick = clock.tick
	routes = BagRoutes.build(grid)
	clock.ticked.connect(on_tick)
	grid.edit_applied.connect(_on_edit_applied)
	grid.graph_changed.connect(_on_graph_changed)
	if passengers != null:
		passengers.checked_in.connect(_on_checked_in)


## Checks passenger `passenger_id`'s bag in at desk `desk_id` now, and returns
## the bag. On or after its flight's cutoff it is missed at once. A passenger
## checks one bag: a second check-in while its first bag is kept pushes an
## error and returns null. While no check-in desk connects via belts to a
## ready bag room, the passenger checks no bag and it returns null with no
## error (decision baggage-loop-completion-connect-gated-penalties-visible-wait).
func check_in(passenger_id: int, flight_id: String, desk_id: int) -> Bag:
	if not has_connected_bag_room():
		return null
	for kept in _bags:
		if kept.passenger == passenger_id:
			push_error(
				"BaggageSim.check_in: passenger %d already has bag %d" % [passenger_id, kept.id]
			)
			return null
	var bag := Bag.new()
	bag.id = _next_id
	_next_id += 1
	bag.passenger = passenger_id
	bag.flight = flight_id
	bag.desk = desk_id
	bag.created_tick = clock.tick
	bag.wait_tick = clock.tick
	bag.cutoff_tick = flights.doors_close_tick(flight_id) - LOAD_LEAD_TICKS
	_bags.append(bag)
	_by_id[bag.id] = bag
	if clock.tick >= bag.cutoff_tick:
		_settle(bag, false, Bag.Cause.LATE, clock.tick)
	return bag


## Whether the grid, as it stands now, holds a bag room that is ready (a belt end
## in it, so it has a root for the route field). Read from the grid each time,
## never saved, so a save and a load always agree on it.
func has_ready_bag_room() -> bool:
	for room_id in grid.room_ids():
		if grid.get_room(room_id)["type"] == BeltShaper.BAG_ROOM:
			if RoomRules.status(grid, room_id).ok:
				return true
	return false


## Whether at least one check-in desk on the grid connects via belts (BagRoutes)
## to a ready bag room's belt end. Read from the live grid without mutating
## `routes` or `routes_stale`, so saves and loads always agree.
func has_connected_bag_room() -> bool:
	var field := BagRoutes.build(grid) if routes_stale or routes == null else routes
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != BeltShaper.DESK:
			continue
		var entry := field.entry_of(object_id)
		if not entry.is_empty() and field.has_route(entry["cell"]):
			return true
	return false


func on_tick(new_tick: int) -> void:
	tick = new_tick
	if routes_stale:
		_reconcile()
	_transfer()
	_move()
	_advance_shuttles()
	_settle_due()
	_retire_settled()
	_prune_results()


func shuttles() -> Array[BaggageShuttle]:
	return _shuttles


func get_shuttle(id: int) -> BaggageShuttle:
	return _shuttle_by_id.get(id)


func active_cart_ids() -> Array[int]:
	var ids: Array[int] = []
	for shuttle in _shuttles:
		ids.append(shuttle.cart_id)
	return ids


## Hook for Tier-2 Ramp Agent staffing (board eddcd9cd) to bind a staff member
## to an active shuttle trip.
func assign_shuttle_driver(shuttle_id: int, staff_id: int) -> bool:
	var shuttle := get_shuttle(shuttle_id)
	if shuttle == null:
		return false
	shuttle.driver_staff_id = staff_id
	return true


func waiting_for_ramp_carts() -> Array[int]:
	var out: Array[int] = []
	if grid == null or flights == null or not shuttle_can_dispatch.is_valid():
		return out
	var ready_by_flight := {}
	for bag in _bags:
		if bag.is_settled() or bag.shuttle_id != 0 or tick < bag.cutoff_tick:
			continue
		if bag.state == Bag.State.IN_ROOM:
			var list: Array[Bag] = ready_by_flight.get(bag.flight, [] as Array[Bag])
			list.append(bag)
			ready_by_flight[bag.flight] = list
	var flight_keys := ready_by_flight.keys()
	flight_keys.sort()
	for flight_id: String in flight_keys:
		var stand := flights.flight_stand(flight_id)
		if stand.is_empty():
			continue
		var doors_close := flights.doors_close_tick(flight_id)
		var by_cart := {}
		for bag: Bag in ready_by_flight[flight_id]:
			var cart_id := _cart_for_bag(bag)
			if cart_id != 0:
				by_cart[cart_id] = true
		var cart_ids := by_cart.keys()
		cart_ids.sort()
		for cart_id: int in cart_ids:
			if out.has(cart_id) or _cart_busy(cart_id):
				continue
			var plan := _shuttle_plan(cart_id, flight_id, stand)
			var finish_tick := tick + int(plan["travel"]) + BaggageShuttle.UNLOAD_TICKS
			if doors_close >= 0 and finish_tick >= doors_close:
				continue
			if not shuttle_can_dispatch.call(cart_id, flight_id):
				out.append(cart_id)
	return out


func waiting_for_ramp_reason(staff: StaffSim = null) -> String:
	if waiting_for_ramp_carts().is_empty():
		return "none"
	if staff != null and staff.count(StaffMember.Role.RAMP) == 0:
		return "none_hired"
	return "all_busy"


func get_bag(id: int) -> Bag:
	return _by_id.get(id)


## The kept bag of passenger `passenger_id`, or null: the passenger never
## checked one in, or it was settled long enough ago to be dropped.
func bag_of_passenger(passenger_id: int) -> Bag:
	for bag in _bags:
		if bag.passenger == passenger_id:
			return bag
	return null


func bag_ids() -> Array[int]:
	var ids: Array[int] = []
	for bag in _bags:
		ids.append(bag.id)
	return ids


func bags() -> Array[Bag]:
	return _bags


## The state a bag on a belt must have in `with_routes`: RIDING, BLOCKED (its
## committed belt-to-belt edge no longer joins, or no route from the centre
## it stands on), IN_ROOM (it stands on a root's centre) or MISSED (lost:
## its body is on a cell that is no longer belt). The half cell from a desk
## needs only the belt it leads onto.
static func belt_state(bag: Bag, with_routes: BagRoutes) -> Bag.State:
	var body := bag.physical_cell()
	if not with_routes.is_belt(body):
		return Bag.State.MISSED
	if bag.remain_mm > 0:
		if not bag.from_desk and not with_routes.joined(bag.cell - bag.from_step, bag.from_step):
			return Bag.State.BLOCKED
		return Bag.State.RIDING
	if with_routes.is_root(bag.cell):
		return Bag.State.IN_ROOM
	return Bag.State.RIDING if with_routes.has_route(bag.cell) else Bag.State.BLOCKED


## Why a bag not in the room misses, judged as things stand.
func miss_cause(bag: Bag) -> Bag.Cause:
	if bag.state == Bag.State.BLOCKED:
		return Bag.Cause.NO_ROUTE
	if bag.state == Bag.State.AT_DESK:
		var entry := routes.entry_of(bag.desk)
		if entry.is_empty():
			return Bag.Cause.NO_BELT
		if not routes.has_route(entry["cell"]):
			return Bag.Cause.NO_ROUTE
	return Bag.Cause.LATE


## JSON-safe state for a save. Reads only. Between a build edit and the next
## tick it pushes an error and returns {}: SaveGame waits for that tick.
func to_snapshot() -> Dictionary:
	if routes_stale:
		push_error("BaggageSim.to_snapshot: a build edit settles on the next tick; save after it")
		return {}
	return BaggageSnapshot.save(self, _next_id, _next_shuttle_id)


## Restores a to_snapshot() dictionary, including one that went through JSON,
## against the grid as it is now (SaveGame installs the grid first). Pushes
## an error and returns false, changing nothing, when it is refused.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := BaggageSnapshot.load(data)
	var problem: String = loaded.get("error", "")
	var built := BagRoutes.build(grid)
	if problem == "":
		problem = BaggageSnapshot.grid_problem(loaded["bags"], built, loaded["shuttles"])
	if problem != "":
		push_error("BaggageSim.from_snapshot: %s" % problem)
		return false
	tick = loaded["tick"]
	_next_id = loaded["next_id"]
	_next_shuttle_id = loaded["next_shuttle_id"]
	results = loaded["results"]
	loaded_total = loaded["loaded_total"]
	missed_total = loaded["missed_total"]
	_bags = loaded["bags"]
	_by_id.clear()
	for bag in _bags:
		_by_id[bag.id] = bag
	_shuttles = loaded["shuttles"]
	_shuttle_by_id.clear()
	for shuttle in _shuttles:
		_shuttle_by_id[shuttle.id] = shuttle
	routes = built
	routes_stale = false
	return true


func _on_checked_in(passenger_id: int, desk_id: int) -> void:
	check_in(passenger_id, passengers.get_passenger(passenger_id).flight_id, desk_id)


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	routes_stale = true


## A grid load relinks everything without an edit; the next tick (or a
## baggage load right after it) rebuilds the field.
func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	routes_stale = true


func _reconcile() -> void:
	routes = BagRoutes.build(grid)
	routes_stale = false
	var kept_shuttles: Array[BaggageShuttle] = []
	for shuttle in _shuttles:
		var record := grid.get_object(shuttle.cart_id)
		if record.is_empty() or StringName(record["def"]) != CART_DEF:
			for bag_id in shuttle.bag_ids:
				var bag := get_bag(bag_id)
				if bag != null and not bag.is_settled():
					_settle(bag, false, Bag.Cause.LOST, tick)
			_shuttle_by_id.erase(shuttle.id)
			shuttle_cancelled.emit(shuttle.id, shuttle.cart_id)
		else:
			kept_shuttles.append(shuttle)
	_shuttles = kept_shuttles
	for bag in _bags:
		if bag.state == Bag.State.IN_ROOM:
			if bag.shuttle_id == 0 and not routes.is_root(bag.cell):
				_settle(bag, false, Bag.Cause.LOST, tick)
		elif bag.on_belt():
			var state := belt_state(bag, routes)
			if state == Bag.State.MISSED:
				_settle(bag, false, Bag.Cause.LOST, tick)
			elif state == Bag.State.IN_ROOM:
				_rest(bag)
			else:
				bag.state = state


func _transfer() -> void:
	var taken := {}
	for bag in _bags:
		if bag.on_belt():
			taken[bag.cell] = true
			taken[bag.physical_cell()] = true
	var heads := {}
	var wants := {}
	for bag in _bags:
		var target := Vector2i.ZERO
		if bag.state == Bag.State.AT_DESK:
			if bag.created_tick >= tick or heads.has(bag.desk):
				continue
			heads[bag.desk] = true
			var entry := routes.entry_of(bag.desk)
			if entry.is_empty() or not routes.has_route(entry["cell"]):
				continue
			target = entry["cell"]
		elif bag.state == Bag.State.RIDING and bag.remain_mm == 0:
			target = bag.cell + routes.step_from(bag.cell)
		else:
			continue
		if taken.has(target):
			continue
		var best: Bag = wants.get(target)
		if (
			best == null
			or bag.wait_tick < best.wait_tick
			or (bag.wait_tick == best.wait_tick and bag.id < best.id)
		):
			wants[target] = bag
	for target in wants:
		var bag: Bag = wants[target]
		if bag.state == Bag.State.AT_DESK:
			bag.from_step = routes.entry_of(bag.desk)["step"]
			bag.from_desk = true
			bag.remain_mm = Bag.CELL_MM / 2
			bag.state = Bag.State.RIDING
		else:
			bag.from_step = target - bag.cell
			bag.from_desk = false
			bag.remain_mm = Bag.CELL_MM
		bag.cell = target


func _move() -> void:
	for bag in _bags:
		if bag.state != Bag.State.RIDING or bag.remain_mm == 0:
			continue
		bag.remain_mm = maxi(0, bag.remain_mm - BELT_MM)
		if bag.remain_mm > 0:
			continue
		bag.wait_tick = tick
		if routes.is_root(bag.cell):
			_rest(bag)
		elif not routes.has_route(bag.cell):
			bag.state = Bag.State.BLOCKED


func _rest(bag: Bag) -> void:
	bag.state = Bag.State.IN_ROOM
	bag.remain_mm = 0
	bag.rest_tick = tick


func _advance_shuttles() -> void:
	var kept: Array[BaggageShuttle] = []
	for shuttle in _shuttles:
		if shuttle.phase == BaggageShuttle.Phase.OUTBOUND and tick >= shuttle.arrive_tick:
			shuttle.phase = BaggageShuttle.Phase.UNLOADING
			shuttle_arrived.emit(shuttle.id, shuttle.flight)
		if shuttle.phase == BaggageShuttle.Phase.UNLOADING and tick >= shuttle.unload_tick:
			for bag_id in shuttle.bag_ids:
				var bag := get_bag(bag_id)
				if bag != null and not bag.is_settled():
					_settle(bag, true, Bag.Cause.NONE, tick)
			shuttle.bag_ids.clear()
			shuttle.phase = BaggageShuttle.Phase.RETURNING
		if shuttle.phase == BaggageShuttle.Phase.RETURNING and tick >= shuttle.return_tick:
			_shuttle_by_id.erase(shuttle.id)
			shuttle_returned.emit(shuttle.id, shuttle.cart_id)
		else:
			kept.append(shuttle)
	_shuttles = kept


func _settle_due() -> void:
	var ready_by_flight := {}
	for bag in _bags:
		if bag.is_settled() or bag.shuttle_id != 0 or tick < bag.cutoff_tick:
			continue
		if bag.state == Bag.State.IN_ROOM:
			var list: Array[Bag] = ready_by_flight.get(bag.flight, [] as Array[Bag])
			list.append(bag)
			ready_by_flight[bag.flight] = list
		else:
			_settle(bag, false, miss_cause(bag), tick)
	var flight_keys := ready_by_flight.keys()
	flight_keys.sort()
	for flight_id: String in flight_keys:
		_dispatch_or_load(flight_id, ready_by_flight[flight_id])


func _dispatch_or_load(flight_id: String, room_bags: Array[Bag]) -> void:
	var stand := flights.flight_stand(flight_id)
	var doors_close := flights.doors_close_tick(flight_id)
	var by_cart := {}
	for bag in room_bags:
		var cart_id := _cart_for_bag(bag)
		var list: Array[Bag] = by_cart.get(cart_id, [] as Array[Bag])
		list.append(bag)
		by_cart[cart_id] = list
	var cart_ids := by_cart.keys()
	cart_ids.sort()
	for cart_id: int in cart_ids:
		var group: Array[Bag] = by_cart[cart_id]
		if cart_id == 0:
			for bag in group:
				_settle(bag, true, Bag.Cause.NONE, tick)
			continue
		if stand.is_empty():
			for bag in group:
				_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		var plan := _shuttle_plan(cart_id, flight_id, stand)
		var finish_tick := tick + int(plan["travel"]) + BaggageShuttle.UNLOAD_TICKS
		if doors_close >= 0 and finish_tick >= doors_close:
			for bag in group:
				_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		if _cart_busy(cart_id):
			continue
		if shuttle_can_dispatch.is_valid() and not shuttle_can_dispatch.call(cart_id, flight_id):
			continue
		_start_shuttle(cart_id, flight_id, stand, plan, group)


func _cart_busy(cart_id: int) -> bool:
	for shuttle in _shuttles:
		if shuttle.cart_id == cart_id:
			return true
	return false


func _cart_for_bag(bag: Bag) -> int:
	var room_id := grid.room_at(bag.cell)
	if room_id == 0:
		return 0
	var in_room: Array[int] = []
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != CART_DEF:
			continue
		if grid.room_at(record["anchor"]) == room_id:
			in_room.append(object_id)
	if in_room.is_empty():
		return 0
	var best_id := 0
	var best_busy := true
	var best_dist := INF
	for object_id in in_room:
		var busy := _cart_busy(object_id)
		var dist := Vector2(grid.get_object(object_id)["anchor"] - bag.cell).length_squared()
		if best_id == 0 or (not busy and best_busy) or (busy == best_busy and dist < best_dist):
			best_id = object_id
			best_busy = busy
			best_dist = dist
	return best_id


func _shuttle_plan(cart_id: int, flight_id: String, stand: Dictionary) -> Dictionary:
	var record := grid.get_object(cart_id)
	var def := BuildCatalog.get_def(CART_DEF)
	var origin := BuildView.object_transform(
		grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	origin.origin.y = BaggageShuttle.ground_y(grid, origin.origin)
	var model := PlaneClasses.flight_model(flights, flight_id)
	var target := BaggageShuttle.cargo_point(stand, model)
	target.y = BaggageShuttle.ground_y(grid, target)
	var route := BaggageShuttle.plan_route(grid, origin.origin, target)
	var dist_m := BaggageShuttle.route_length(route)
	var travel := clampi(
		roundi(dist_m * BaggageShuttle.TRAVEL_TICKS_PER_M),
		BaggageShuttle.MIN_TRAVEL_TICKS,
		BaggageShuttle.MAX_TRAVEL_TICKS
	)
	return {
		"origin": origin.origin,
		"origin_yaw": -int(record["facing"]) * PI / 2.0,
		"target": target,
		"route": route,
		"travel": travel,
	}


func _start_shuttle(
	cart_id: int,
	flight_id: String,
	stand: Dictionary,
	plan: Dictionary,
	group: Array[Bag],
) -> void:
	var travel: int = plan["travel"]
	var shuttle := BaggageShuttle.new()
	shuttle.id = _next_shuttle_id
	_next_shuttle_id += 1
	shuttle.cart_id = cart_id
	shuttle.flight = flight_id
	shuttle.phase = BaggageShuttle.Phase.OUTBOUND
	shuttle.start_tick = tick
	shuttle.arrive_tick = tick + travel
	shuttle.unload_tick = shuttle.arrive_tick + BaggageShuttle.UNLOAD_TICKS
	shuttle.return_tick = shuttle.unload_tick + travel
	shuttle.origin_world = plan["origin"]
	shuttle.origin_yaw = float(plan["origin_yaw"])
	shuttle.target_world = plan["target"]
	shuttle.target_yaw = StandPlacement.SIDE_YAW[StandPlacement.side_of(stand)]
	shuttle.waypoints = plan["route"]
	for bag in group:
		bag.shuttle_id = shuttle.id
		shuttle.bag_ids.append(bag.id)
	_shuttles.append(shuttle)
	_shuttle_by_id[shuttle.id] = shuttle
	shuttle_dispatched.emit(shuttle.id, flight_id, cart_id)


func _settle(bag: Bag, loaded: bool, cause: Bag.Cause, at_tick: int) -> void:
	if bag.is_settled():
		push_error("BaggageSim: bag %d is already settled" % bag.id)
		return
	bag.shuttle_id = 0
	bag.state = Bag.State.LOADED if loaded else Bag.State.MISSED
	bag.cause = cause
	bag.outcome_tick = at_tick
	var result: Dictionary = results.get(bag.flight, {"loaded": 0, "missed": 0, "causes": {}})
	if loaded:
		loaded_total += 1
		result["loaded"] += 1
	else:
		missed_total += 1
		result["missed"] += 1
		var key := Bag.CAUSE_NAMES[cause]
		result["causes"][key] = result["causes"].get(key, 0) + 1
	results[bag.flight] = result
	bag_settled.emit(bag.id, bag.passenger, bag.flight, loaded)


func _retire_settled() -> void:
	var kept: Array[Bag] = []
	for bag in _bags:
		if bag.is_settled() and tick - bag.outcome_tick >= SETTLED_KEEP_TICKS:
			_by_id.erase(bag.id)
		else:
			kept.append(bag)
	if kept.size() != _bags.size():
		_bags = kept


func _prune_results() -> void:
	if results.is_empty():
		return
	var live := flights.flight_ids()
	for flight_id in results.keys():
		if not live.has(flight_id):
			results.erase(flight_id)
