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
## Inbound baggage claim / loss signals (Arrivals A3).
signal inbound_bag_claimed(bag_id: int, passenger_id: int, flight_id: String)
signal inbound_bag_lost(bag_id: int, passenger_id: int, flight_id: String)
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
var inbound_claimed_total := 0
var inbound_lost_total := 0

var _wallet: Wallet
var _bags: Array[Bag] = []
var _by_id := {}
var _next_id := 1
var _shuttles: Array[BaggageShuttle] = []
var _shuttle_by_id := {}
var _next_shuttle_id := 1


func _ready() -> void:
	if clock == null or flights == null or build_mode == null:
		return
	bind(clock, flights, build_mode.grid, passengers, build_mode.wallet())


## Listens to the clock, the grid's edits and loads, and (when given) the
## passengers' check-ins.
func bind(
	with_clock: SimClock,
	with_flights: FlightSim,
	with_grid: BuildGrid,
	with_passengers: PassengerSim = null,
	with_wallet: Wallet = null,
) -> void:
	clock = with_clock
	flights = with_flights
	grid = with_grid
	passengers = with_passengers
	_wallet = (
		with_wallet
		if with_wallet != null
		else (build_mode.wallet() if build_mode != null else null)
	)
	tick = clock.tick
	routes = BagRoutes.build(grid)
	clock.ticked.connect(on_tick)
	grid.edit_applied.connect(_on_edit_applied)
	grid.graph_changed.connect(_on_graph_changed)
	if flights != null:
		flights.state_changed.connect(_on_flight_state_changed)
	if passengers != null:
		passengers.checked_in.connect(_on_checked_in)
		if passengers.baggage == null:
			passengers.baggage = self


## Checks passenger `passenger_id`'s bag in at desk `desk_id` now, and returns
## the bag. On or after its flight's cutoff it is missed at once. A passenger
## checks one bag: a second check-in while its first bag is kept pushes an
## error and returns null. While no check-in desk connects via belts to a
## ready bag room, the passenger checks no bag and it returns null with no
## error (decision baggage-loop-completion-connect-gated-penalties-visible-wait).
func check_in(passenger_id: int, flight_id: String, desk_id: int, color_index := -1) -> Bag:
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
	bag.color = (
		clampi(color_index, 0, Bag.SUITCASE_COLORS.size() - 1)
		if color_index >= 0
		else Bag.color_for_passenger(passenger_id)
	)
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


## Number of check-in desks routed to a ready bag room (or to `room_id` when
## nonzero), read from the live grid without mutating `routes` or `routes_stale`.
func connected_desk_count(room_id: int = 0) -> int:
	var field := BagRoutes.build(grid) if routes_stale or routes == null else routes
	return field.connected_desk_count(room_id)


## Whether at least one check-in desk on the grid connects via belts (BagRoutes)
## to a ready bag room's belt end. Read from the live grid without mutating
## `routes` or `routes_stale`, so saves and loads always agree.
func has_connected_bag_room() -> bool:
	return connected_desk_count() > 0


func on_tick(new_tick: int) -> void:
	tick = new_tick
	if routes_stale:
		_reconcile()
	_transfer()
	_move()
	_advance_shuttles()
	BaggageInbound.dispatch_shuttles(self)
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
	var reserved := _pending_shuttle_bags()
	var cutoff_by_flight := {}
	var boarding_by_flight := {}
	for bag in _bags:
		if (
			bag.inbound
			or bag.is_settled()
			or bag.shuttle_id != 0
			or reserved.has(bag.id)
			or bag.state != Bag.State.IN_ROOM
		):
			continue
		if tick >= bag.cutoff_tick:
			var list: Array[Bag] = cutoff_by_flight.get(bag.flight, [] as Array[Bag])
			list.append(bag)
			cutoff_by_flight[bag.flight] = list
		elif flights.state_of(bag.flight) == FlightSim.State.BOARDING:
			var list: Array[Bag] = boarding_by_flight.get(bag.flight, [] as Array[Bag])
			list.append(bag)
			boarding_by_flight[bag.flight] = list
	_collect_waiting_carts(cutoff_by_flight, false, out)
	_collect_waiting_carts(boarding_by_flight, true, out)
	BaggageInbound.waiting_for_ramp_carts(self, out)
	return out


func _collect_waiting_carts(by_flight: Dictionary, early_wave: bool, out: Array[int]) -> void:
	var flight_keys := by_flight.keys()
	flight_keys.sort()
	for flight_id: String in flight_keys:
		var stand := flights.flight_stand(flight_id)
		if stand.is_empty():
			continue
		var doors_close := flights.doors_close_tick(flight_id)
		var by_cart := {}
		for bag: Bag in by_flight[flight_id]:
			var cart_id := _cart_for_bag(bag)
			if cart_id != 0:
				var list: Array[Bag] = by_cart.get(cart_id, [] as Array[Bag])
				list.append(bag)
				by_cart[cart_id] = list
		var cart_ids := by_cart.keys()
		cart_ids.sort()
		for cart_id: int in cart_ids:
			if out.has(cart_id) or _cart_busy(cart_id):
				continue
			var group: Array[Bag] = by_cart[cart_id]
			var plan := _shuttle_plan(cart_id, flight_id, stand)
			if not bool(plan.get("ok", false)):
				continue
			if early_wave and not _early_wave_allowed(cart_id, plan, group, doors_close):
				continue
			var finish_tick := tick + int(plan["travel"]) + BaggageShuttle.UNLOAD_TICKS
			if doors_close >= 0 and finish_tick >= doors_close:
				continue
			if not shuttle_can_dispatch.call(cart_id, flight_id):
				out.append(cart_id)


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
	if bag.inbound:
		if with_routes.is_inbound_root(bag.cell):
			return Bag.State.ON_CAROUSEL
		return Bag.State.RIDING if with_routes.has_inbound_route(bag.cell) else Bag.State.BLOCKED
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
	inbound_claimed_total = loaded["inbound_claimed_total"]
	inbound_lost_total = loaded["inbound_lost_total"]
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
	var p := passengers.get_passenger(passenger_id)
	var color_index := p.checked_bag_color if p != null else -1
	check_in(passenger_id, p.flight_id, desk_id, color_index)


func _on_flight_state_changed(flight_id: String, new_state: int) -> void:
	if new_state == FlightSim.State.AT_STAND:
		BaggageInbound.spawn_for_flight(self, flight_id)


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
		var cart_ok := not record.is_empty() and StringName(record["def"]) == CART_DEF
		var drop_ok := (
			not shuttle.inbound
			or shuttle.phase != BaggageShuttle.Phase.TRANSFER_IN
			or (
				BaggageInbound.drop_cell_for_shuttle(self, shuttle) != Vector2i(-1, -1)
				and routes.has_connected_baggage_claim()
			)
		)
		var door_ok := cart_ok and _reconcile_shuttle_bay_door(shuttle)
		if not cart_ok or not drop_ok or not door_ok:
			_cancel_shuttle(shuttle)
		else:
			kept_shuttles.append(shuttle)
	_shuttles = kept_shuttles
	for bag in _bags:
		if bag.inbound:
			BaggageInbound.reconcile_bag(self, bag)
		elif bag.state == Bag.State.IN_ROOM:
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
	var final_shuttles: Array[BaggageShuttle] = []
	for shuttle in _shuttles:
		var live_pending: Array[int] = []
		for bag_id in shuttle.pending_bag_ids:
			var bag := get_bag(bag_id)
			if shuttle.inbound:
				if (
					bag != null
					and not bag.is_settled()
					and bag.state == Bag.State.ON_PLANE
					and bag.shuttle_id == shuttle.id
				):
					live_pending.append(bag_id)
			elif (
				bag != null
				and not bag.is_settled()
				and bag.state == Bag.State.IN_ROOM
				and bag.shuttle_id == 0
			):
				live_pending.append(bag_id)
		shuttle.pending_bag_ids = live_pending
		if (
			not shuttle.inbound
			and shuttle.bag_ids.is_empty()
			and shuttle.carried_bag_ids.is_empty()
			and shuttle.pending_bag_ids.is_empty()
		):
			_cancel_shuttle(shuttle)
		else:
			if (
				not shuttle.inbound
				and (
					shuttle.phase == BaggageShuttle.Phase.TO_BAG_ROOM
					or shuttle.phase == BaggageShuttle.Phase.TRANSFER_OUT
				)
				and shuttle.carried_bag_ids.is_empty()
				and shuttle.pending_bag_ids.is_empty()
				and not shuttle.bag_ids.is_empty()
			):
				_finish_transfer_out_now(shuttle)
			final_shuttles.append(shuttle)
	_shuttles = final_shuttles


func _reconcile_shuttle_bay_door(shuttle: BaggageShuttle) -> bool:
	if (
		shuttle.bay_door_id > 0
		and not BaggageShuttle.bay_door_anchors(grid, shuttle.bay_door_id).is_empty()
	):
		return true
	var res := BaggageShuttle.plan_room_route(grid, shuttle.origin_world, shuttle.target_world)
	if not bool(res.get("ok", false)):
		return false
	shuttle.bay_door_id = int(res["bay_door_id"])
	shuttle.bay_inside_world = res["bay_inside"]
	shuttle.bay_door_world = res["bay_door"]
	shuttle.bay_outside_world = res["bay_outside"]
	shuttle.waypoints = res["waypoints"]
	return true


func _cancel_shuttle(shuttle: BaggageShuttle) -> void:
	for bag_id in shuttle.bag_ids:
		var bag := get_bag(bag_id)
		if bag != null and not bag.is_settled():
			if bag.inbound:
				BaggageInbound.settle_lost(self, bag, Bag.Cause.LOST, tick)
			else:
				_settle(bag, false, Bag.Cause.LOST, tick)
	for bag_id in shuttle.carried_bag_ids:
		var bag := get_bag(bag_id)
		if bag != null and not bag.is_settled():
			if bag.inbound:
				BaggageInbound.settle_lost(self, bag, Bag.Cause.LOST, tick)
			else:
				_settle(bag, false, Bag.Cause.LOST, tick)
	if shuttle.inbound:
		for bag_id in shuttle.pending_bag_ids:
			var bag := get_bag(bag_id)
			if bag != null and not bag.is_settled():
				BaggageInbound.settle_lost(self, bag, Bag.Cause.LOST, tick)
	shuttle.bag_ids.clear()
	shuttle.carried_bag_ids.clear()
	shuttle.pending_bag_ids.clear()
	_shuttle_by_id.erase(shuttle.id)
	shuttle_cancelled.emit(shuttle.id, shuttle.cart_id)


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
		elif bag.inbound and bag.state == Bag.State.IN_ROOM and bag.shuttle_id == 0:
			if not routes.has_inbound_route(bag.cell):
				continue
			if routes.is_inbound_root(bag.cell):
				if not heads.has(bag.cell) and not taken.has(bag.cell):
					heads[bag.cell] = true
					BaggageInbound.enter_carousel(self, bag, routes.carousel_of(bag.cell))
				continue
			var step := routes.inbound_step_from(bag.cell)
			if step == Vector2i.ZERO:
				continue
			target = bag.cell + step
		elif bag.state == Bag.State.RIDING and bag.remain_mm == 0:
			var step := (
				routes.inbound_step_from(bag.cell) if bag.inbound else routes.step_from(bag.cell)
			)
			if step == Vector2i.ZERO:
				continue
			target = bag.cell + step
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
			bag.state = Bag.State.RIDING
			if bag.inbound:
				bag.carousel = routes.carousel_of(target)
		bag.cell = target


func _move() -> void:
	for bag in _bags:
		if bag.state != Bag.State.RIDING or bag.remain_mm == 0:
			continue
		bag.remain_mm = maxi(0, bag.remain_mm - BELT_MM)
		if bag.remain_mm > 0:
			continue
		bag.wait_tick = tick
		if bag.inbound:
			if routes.is_inbound_root(bag.cell):
				BaggageInbound.enter_carousel(self, bag, routes.carousel_of(bag.cell))
			elif not routes.has_inbound_route(bag.cell):
				bag.state = Bag.State.BLOCKED
		elif routes.is_root(bag.cell):
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
		if (
			shuttle.phase == BaggageShuttle.Phase.TO_BAG_ROOM
			and tick >= shuttle.transfer_start_tick
		):
			if shuttle.inbound:
				shuttle.phase = BaggageShuttle.Phase.OUTBOUND
			else:
				_start_transfer_out(shuttle)
		elif shuttle.phase == BaggageShuttle.Phase.TRANSFER_OUT:
			_advance_transfer_out(shuttle)
		if shuttle.phase == BaggageShuttle.Phase.OUTBOUND and tick >= shuttle.arrive_tick:
			shuttle.phase = BaggageShuttle.Phase.UNLOADING
			shuttle_arrived.emit(shuttle.id, shuttle.flight)
		if shuttle.phase == BaggageShuttle.Phase.UNLOADING and tick >= shuttle.unload_tick:
			if shuttle.inbound:
				BaggageInbound.finish_unloading_shuttle(self, shuttle)
			else:
				for bag_id in shuttle.bag_ids:
					var bag := get_bag(bag_id)
					if bag != null and not bag.is_settled():
						_settle(bag, true, Bag.Cause.NONE, tick)
				shuttle.bag_ids.clear()
			shuttle.phase = BaggageShuttle.Phase.RETURNING
		if shuttle.phase == BaggageShuttle.Phase.RETURNING and tick >= shuttle.return_tick:
			if shuttle.inbound:
				if BaggageInbound.start_transfer_in(self, shuttle):
					_shuttle_by_id.erase(shuttle.id)
					shuttle_returned.emit(shuttle.id, shuttle.cart_id)
				else:
					kept.append(shuttle)
			else:
				_shuttle_by_id.erase(shuttle.id)
				shuttle_returned.emit(shuttle.id, shuttle.cart_id)
		elif shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN:
			if BaggageInbound.advance_transfer_in(self, shuttle):
				_shuttle_by_id.erase(shuttle.id)
				shuttle_returned.emit(shuttle.id, shuttle.cart_id)
			else:
				kept.append(shuttle)
		else:
			kept.append(shuttle)
	_shuttles = kept


func _start_transfer_out(shuttle: BaggageShuttle) -> void:
	if (
		shuttle.pending_bag_ids.is_empty()
		or tick >= shuttle.start_tick
		or shuttle.transfer_start_tick >= shuttle.start_tick
	):
		_load_remaining_pending_now(shuttle)
		_finish_transfer_out_now(shuttle)
		return
	shuttle.phase = BaggageShuttle.Phase.TRANSFER_OUT
	_pickup_outbound_batch(shuttle)
	if shuttle.carried_bag_ids.is_empty() and shuttle.pending_bag_ids.is_empty():
		_finish_transfer_out_now(shuttle)
	else:
		shuttle.next_load_tick = shuttle.transfer_start_tick + maxi(1, shuttle.load_step_ticks)


func _advance_transfer_out(shuttle: BaggageShuttle) -> void:
	while tick >= shuttle.next_load_tick:
		if not shuttle.carried_bag_ids.is_empty():
			shuttle.bag_ids.append_array(shuttle.carried_bag_ids)
			shuttle.carried_bag_ids.clear()
			if shuttle.pending_bag_ids.is_empty():
				_finish_transfer_out_now(shuttle)
				return
			shuttle.next_load_tick += maxi(1, shuttle.load_step_ticks)
		else:
			_pickup_outbound_batch(shuttle)
			if shuttle.carried_bag_ids.is_empty():
				_finish_transfer_out_now(shuttle)
				return
			shuttle.next_load_tick += maxi(1, shuttle.load_step_ticks)
	if tick >= shuttle.start_tick:
		_load_remaining_pending_now(shuttle)
		shuttle.phase = BaggageShuttle.Phase.OUTBOUND


func _load_remaining_pending_now(shuttle: BaggageShuttle) -> void:
	for bid in shuttle.carried_bag_ids:
		shuttle.bag_ids.append(bid)
	shuttle.carried_bag_ids.clear()
	while not shuttle.pending_bag_ids.is_empty():
		var bag_id: int = shuttle.pending_bag_ids.pop_front()
		var bag := get_bag(bag_id)
		if bag != null and not bag.is_settled() and bag.state == Bag.State.IN_ROOM:
			bag.shuttle_id = shuttle.id
			shuttle.bag_ids.append(bag_id)


func _pickup_outbound_batch(shuttle: BaggageShuttle) -> void:
	var target_cell := Vector2i(-1, -1)
	var kept: Array[int] = []
	for bag_id in shuttle.pending_bag_ids:
		var bag := get_bag(bag_id)
		if bag == null or bag.is_settled() or bag.state != Bag.State.IN_ROOM:
			continue
		if (
			shuttle.carried_bag_ids.size() < BaggageShuttle.CARRY_BATCH_SIZE
			and (target_cell == Vector2i(-1, -1) or bag.cell == target_cell)
		):
			target_cell = bag.cell
			bag.shuttle_id = shuttle.id
			shuttle.carried_bag_ids.append(bag_id)
		else:
			kept.append(bag_id)
	shuttle.pending_bag_ids = kept


func _finish_transfer_out_now(shuttle: BaggageShuttle) -> void:
	var travel := maxi(BaggageShuttle.MIN_TRAVEL_TICKS, shuttle.arrive_tick - shuttle.start_tick)
	shuttle.start_tick = tick
	shuttle.arrive_tick = tick + travel
	shuttle.unload_tick = shuttle.arrive_tick + BaggageShuttle.UNLOAD_TICKS
	shuttle.return_tick = shuttle.unload_tick + travel
	shuttle.next_load_tick = tick
	shuttle.phase = BaggageShuttle.Phase.OUTBOUND


func _pending_shuttle_bags() -> Dictionary:
	var out := {}
	for shuttle in _shuttles:
		for bag_id in shuttle.pending_bag_ids:
			out[bag_id] = true
	return out


func _settle_due() -> void:
	var reserved := _pending_shuttle_bags()
	var cutoff_by_flight := {}
	var boarding_by_flight := {}
	for bag in _bags:
		if bag.inbound or bag.is_settled() or bag.shuttle_id != 0 or reserved.has(bag.id):
			continue
		if tick >= bag.cutoff_tick:
			if bag.state == Bag.State.IN_ROOM:
				var list: Array[Bag] = cutoff_by_flight.get(bag.flight, [] as Array[Bag])
				list.append(bag)
				cutoff_by_flight[bag.flight] = list
			else:
				_settle(bag, false, miss_cause(bag), tick)
		elif (
			bag.state == Bag.State.IN_ROOM
			and flights != null
			and flights.state_of(bag.flight) == FlightSim.State.BOARDING
		):
			var list: Array[Bag] = boarding_by_flight.get(bag.flight, [] as Array[Bag])
			list.append(bag)
			boarding_by_flight[bag.flight] = list
	var cutoff_keys := cutoff_by_flight.keys()
	cutoff_keys.sort()
	for flight_id: String in cutoff_keys:
		_dispatch_or_load(flight_id, cutoff_by_flight[flight_id], false)
	var boarding_keys := boarding_by_flight.keys()
	boarding_keys.sort()
	for flight_id: String in boarding_keys:
		_dispatch_or_load(flight_id, boarding_by_flight[flight_id], true)


func _dispatch_or_load(flight_id: String, room_bags: Array[Bag], early_wave := false) -> void:
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
			if not early_wave and (stand.is_empty() or (doors_close >= 0 and tick >= doors_close)):
				for bag in group:
					_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		if stand.is_empty():
			if not early_wave:
				for bag in group:
					_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		var plan := _shuttle_plan(cart_id, flight_id, stand)
		if not bool(plan.get("ok", false)):
			if not early_wave and doors_close >= 0 and tick >= doors_close:
				for bag in group:
					_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		var finish_tick := tick + int(plan["travel"]) + BaggageShuttle.UNLOAD_TICKS
		if doors_close >= 0 and finish_tick >= doors_close:
			if not early_wave:
				for bag in group:
					_settle(bag, false, Bag.Cause.LATE, tick)
			continue
		if early_wave and not _early_wave_allowed(cart_id, plan, group, doors_close):
			continue
		if _cart_busy(cart_id):
			continue
		if shuttle_can_dispatch.is_valid() and not shuttle_can_dispatch.call(cart_id, flight_id):
			continue
		_start_shuttle(cart_id, flight_id, stand, plan, group)


func _early_wave_allowed(
	cart_id: int, plan: Dictionary, group: Array[Bag], doors_close: int
) -> bool:
	if BaggageInbound.reserves_cart_for_inbound(self, cart_id):
		return false
	if doors_close < 0:
		return true
	var final_cutoff := doors_close - LOAD_LEAD_TICKS
	if tick >= final_cutoff:
		return false
	var travel := int(plan["travel"])
	var est := _estimate_schedule(group, travel, -1)
	var est_return := (
		tick
		+ int(est["entry_ticks"])
		+ int(est["transfer_span"])
		+ travel
		+ BaggageShuttle.UNLOAD_TICKS
		+ travel
	)
	return est_return <= final_cutoff


func _cart_busy(cart_id: int) -> bool:
	for shuttle in _shuttles:
		if shuttle.cart_id == cart_id:
			return true
	return false


func _cart_for_bag(bag: Bag) -> int:
	var room_id := grid.room_at(bag.cell)
	if room_id == 0:
		return 0
	var room := grid.get_room(room_id)
	if room.is_empty():
		return 0
	var area: Rect2i = room["rect"]
	var in_room: Array[int] = []
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != CART_DEF:
			continue
		if RoomRules.piece_inside(grid, object_id, area):
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
	var room_route := BaggageShuttle.plan_room_route(grid, origin.origin, target)
	if not bool(room_route.get("ok", false)):
		return {"ok": false, "travel": BaggageShuttle.MIN_TRAVEL_TICKS}
	var route: Array[Vector3] = room_route["waypoints"]
	var dist_m := BaggageShuttle.route_length(route)
	var travel := clampi(
		roundi(dist_m * BaggageShuttle.TRAVEL_TICKS_PER_M),
		BaggageShuttle.MIN_TRAVEL_TICKS,
		BaggageShuttle.MAX_TRAVEL_TICKS
	)
	return {
		"ok": true,
		"origin": origin.origin,
		"origin_yaw": -int(record["facing"]) * PI / 2.0,
		"target": target,
		"route": route,
		"travel": travel,
		"bay_door_id": int(room_route["bay_door_id"]),
		"bay_inside": room_route["bay_inside"],
		"bay_door": room_route["bay_door"],
		"bay_outside": room_route["bay_outside"],
	}


func _trip_count_for_group(group: Array[Bag]) -> int:
	if group.is_empty():
		return 1
	var counts := {}
	for bag in group:
		counts[bag.cell] = int(counts.get(bag.cell, 0)) + 1
	var trips := 0
	for count: int in counts.values():
		trips += ceili(float(count) / float(BaggageShuttle.CARRY_BATCH_SIZE))
	return maxi(1, trips)


func _estimate_schedule(group: Array[Bag], travel: int, doors_close: int) -> Dictionary:
	var wants_entry := shuttle_can_dispatch.is_valid()
	var trips := _trip_count_for_group(group)
	var legs := trips * 2 - 1
	var entry_ticks := BaggageShuttle.ENTRY_TICKS if wants_entry else 0
	var avail := (
		(doors_close - tick - travel - BaggageShuttle.UNLOAD_TICKS)
		if doors_close >= 0
		else entry_ticks + legs * BaggageShuttle.TRANSFER_LEG_TICKS + 1
	)
	if avail <= 1 or avail - 1 < legs:
		return {"entry_ticks": 0, "step_ticks": 1, "transfer_span": 0}
	if entry_ticks > 0:
		entry_ticks = mini(entry_ticks, maxi(0, avail - 1 - legs))
	var transfer_avail := avail - 1 - entry_ticks
	var step_ticks := clampi(
		maxi(1, int(transfer_avail / float(maxi(1, legs)))),
		1,
		BaggageShuttle.TRANSFER_LEG_TICKS,
	)
	var transfer_span := mini(transfer_avail, legs * step_ticks)
	if transfer_span < legs:
		return {"entry_ticks": 0, "step_ticks": 1, "transfer_span": 0}
	return {
		"entry_ticks": entry_ticks,
		"step_ticks": step_ticks,
		"transfer_span": transfer_span,
	}


func _start_shuttle(
	cart_id: int,
	flight_id: String,
	stand: Dictionary,
	plan: Dictionary,
	group: Array[Bag],
) -> void:
	var sorted := group.duplicate()
	sorted.sort_custom(
		func(a: Bag, b: Bag) -> bool:
			return a.rest_tick < b.rest_tick or (a.rest_tick == b.rest_tick and a.id < b.id)
	)
	var doors_close := flights.doors_close_tick(flight_id)
	var travel: int = plan["travel"]
	var sched := _estimate_schedule(sorted, travel, doors_close)
	var entry_ticks: int = sched["entry_ticks"]
	var step_ticks: int = sched["step_ticks"]
	var transfer_span: int = sched["transfer_span"]
	var shuttle := BaggageShuttle.new()
	shuttle.id = _next_shuttle_id
	_next_shuttle_id += 1
	shuttle.cart_id = cart_id
	shuttle.bay_door_id = int(plan["bay_door_id"])
	shuttle.flight = flight_id
	shuttle.load_start_tick = tick
	shuttle.transfer_start_tick = tick + entry_ticks
	shuttle.load_step_ticks = step_ticks
	shuttle.start_tick = shuttle.transfer_start_tick + transfer_span
	shuttle.arrive_tick = shuttle.start_tick + travel
	shuttle.unload_tick = shuttle.arrive_tick + BaggageShuttle.UNLOAD_TICKS
	shuttle.return_tick = shuttle.unload_tick + travel
	shuttle.origin_world = plan["origin"]
	shuttle.origin_yaw = float(plan["origin_yaw"])
	shuttle.target_world = plan["target"]
	shuttle.target_yaw = StandPlacement.SIDE_YAW[StandPlacement.side_of(stand)]
	var first_end := grid.cell_to_world(sorted[0].cell)
	first_end.y = BaggageShuttle.ground_y(grid, first_end)
	shuttle.pickup_world = first_end
	shuttle.bay_inside_world = plan["bay_inside"]
	shuttle.bay_door_world = plan["bay_door"]
	shuttle.bay_outside_world = plan["bay_outside"]
	shuttle.waypoints = plan["route"]
	for bag: Bag in sorted:
		shuttle.pending_bag_ids.append(bag.id)
	if entry_ticks > 0:
		shuttle.phase = BaggageShuttle.Phase.TO_BAG_ROOM
		shuttle.next_load_tick = shuttle.transfer_start_tick
	elif transfer_span > 0:
		_start_transfer_out(shuttle)
	else:
		shuttle.phase = BaggageShuttle.Phase.OUTBOUND
		shuttle.next_load_tick = tick
		shuttle.pending_bag_ids.clear()
		for bag: Bag in sorted:
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
		if (
			_wallet != null
			and PriceTable.CHECKED_BAG_BONUS > 0
			and _wallet.can_credit(PriceTable.CHECKED_BAG_BONUS, Wallet.Category.FEES)
		):
			_wallet.credit(PriceTable.CHECKED_BAG_BONUS, Wallet.Category.FEES)
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
