class_name BaggageInbound
extends RefCounted
## Inbound baggage lifecycle: spawn at AT_STAND (connect-gated), automated
## BaggageShuttle unloading back to bag_room, inbound belt routing to
## claim_carousel, passenger claim bonus, and deleted-carousel fallback.

const INBOUND_BAG_SHARE := 0.70


static func live_routes(sim: BaggageSim) -> BagRoutes:
	if sim.grid == null:
		return null
	return BagRoutes.build(sim.grid) if sim.routes_stale or sim.routes == null else sim.routes


static func has_connected_claim(sim: BaggageSim) -> bool:
	var field := live_routes(sim)
	return field != null and field.has_connected_baggage_claim()


static func spawn_for_flight(sim: BaggageSim, flight_id: String) -> void:
	if sim == null or sim.grid == null or sim.flights == null:
		return
	if not has_connected_claim(sim):
		return
	for kept in sim._bags:
		if kept.inbound and kept.flight == flight_id:
			return
	var arriving := sim.flights.arriving_passengers_of(flight_id)
	if arriving <= 0:
		return
	var count := clampi(roundi(float(arriving) * INBOUND_BAG_SHARE), 1, arriving)
	var now := sim.clock.tick if sim.clock != null else sim.tick
	var pushback := sim.flights.state_start(flight_id, FlightSim.State.PUSHBACK)
	var cutoff := pushback if pushback >= 0 else maxi(now, sim.flights.doors_close_tick(flight_id))
	for _i in count:
		var bag := Bag.new()
		bag.id = sim._next_id
		sim._next_id += 1
		bag.inbound = true
		bag.passenger = 0
		bag.flight = flight_id
		bag.desk = 0
		bag.color = Bag.color_for_passenger(bag.id)
		bag.state = Bag.State.ON_PLANE
		bag.created_tick = now
		bag.wait_tick = now
		bag.cutoff_tick = cutoff
		sim._bags.append(bag)
		sim._by_id[bag.id] = bag


static func assign_owner(sim: BaggageSim, flight_id: String, passenger_id: int) -> Bag:
	if sim == null or passenger_id <= 0:
		return null
	for bag in sim._bags:
		if bag.inbound and bag.flight == flight_id and bag.passenger == 0 and not bag.is_settled():
			bag.passenger = passenger_id
			return bag
	return null


static func claim_bag(sim: BaggageSim, bag_id: int, passenger_id: int) -> bool:
	if sim == null or bag_id <= 0:
		return false
	var bag := sim.get_bag(bag_id)
	if bag == null or not bag.inbound or bag.state != Bag.State.ON_CAROUSEL:
		return false
	if bag.passenger != 0 and bag.passenger != passenger_id:
		return false
	bag.passenger = passenger_id
	bag.shuttle_id = 0
	bag.state = Bag.State.CLAIMED
	bag.cause = Bag.Cause.NONE
	bag.outcome_tick = sim.tick
	sim.inbound_claimed_total += 1
	if (
		sim._wallet != null
		and PriceTable.CHECKED_BAG_BONUS > 0
		and sim._wallet.can_credit(PriceTable.CHECKED_BAG_BONUS, Wallet.Category.FEES)
	):
		sim._wallet.credit(PriceTable.CHECKED_BAG_BONUS, Wallet.Category.FEES)
	sim.inbound_bag_claimed.emit(bag.id, passenger_id, bag.flight)
	return true


static func abandon_bag(sim: BaggageSim, bag_id: int, cause: Bag.Cause = Bag.Cause.LATE) -> void:
	if sim == null or bag_id <= 0:
		return
	var bag := sim.get_bag(bag_id)
	if bag != null and bag.inbound and not bag.is_settled():
		settle_lost(sim, bag, cause, sim.tick)


static func settle_lost(sim: BaggageSim, bag: Bag, cause: Bag.Cause, at_tick: int) -> void:
	if bag.is_settled():
		push_error("BaggageSim: inbound bag %d is already settled" % bag.id)
		return
	bag.shuttle_id = 0
	bag.state = Bag.State.MISSED
	bag.cause = cause
	bag.outcome_tick = at_tick
	sim.inbound_lost_total += 1
	sim.inbound_bag_lost.emit(bag.id, bag.passenger, bag.flight)


static func enter_carousel(sim: BaggageSim, bag: Bag, carousel_id: int) -> void:
	if carousel_id <= 0:
		settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
		return
	bag.state = Bag.State.ON_CAROUSEL
	bag.remain_mm = 0
	bag.rest_tick = sim.tick
	bag.carousel = carousel_id


static func is_bag_room_end_cell(grid: BuildGrid, cell: Vector2i) -> bool:
	if grid == null:
		return false
	var room_id := grid.room_at(cell)
	if room_id == 0 or not RoomRules.status(grid, room_id).ok:
		return false
	if grid.get_room(room_id).get("type") != BeltShaper.BAG_ROOM:
		return false
	var obj_id := grid.object_at(cell)
	if obj_id == 0:
		return false
	return StringName(grid.get_object(obj_id)["def"]) == BeltShaper.END


static func reconcile_bag(sim: BaggageSim, bag: Bag) -> void:
	if bag.is_settled():
		return
	if bag.state == Bag.State.ON_CAROUSEL:
		if not sim.routes.is_ready_carousel(bag.carousel):
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
		return
	if bag.on_belt():
		var state := BaggageSim.belt_state(bag, sim.routes)
		if state == Bag.State.MISSED:
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
		elif state == Bag.State.ON_CAROUSEL:
			enter_carousel(sim, bag, sim.routes.carousel_of(bag.cell))
		else:
			bag.state = state
		return
	if bag.state == Bag.State.IN_ROOM and bag.shuttle_id == 0:
		if (
			not is_bag_room_end_cell(sim.grid, bag.cell)
			or not sim.routes.has_connected_baggage_claim()
		):
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
	elif bag.state == Bag.State.ON_PLANE and bag.shuttle_id == 0:
		if not sim.routes.has_connected_baggage_claim():
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)


static func dispatch_shuttles(sim: BaggageSim) -> void:
	if sim.grid == null or sim.flights == null or sim.routes == null:
		return
	var waiting := _on_plane_by_flight(sim)
	if waiting.is_empty():
		return
	var flight_keys := waiting.keys()
	flight_keys.sort()
	for flight_id: String in flight_keys:
		var group: Array[Bag] = waiting[flight_id]
		var state: int = sim.flights.state_of(flight_id)
		var stand := sim.flights.flight_stand(flight_id)
		if (
			stand.is_empty()
			or state >= FlightSim.State.PUSHBACK
			or state < FlightSim.State.AT_STAND
		):
			for bag: Bag in group:
				settle_lost(sim, bag, Bag.Cause.LATE, sim.tick)
			continue
		var cart_id := _idle_inbound_cart(sim)
		if cart_id == 0:
			continue
		if (
			sim.shuttle_can_dispatch.is_valid()
			and not sim.shuttle_can_dispatch.call(cart_id, flight_id)
		):
			continue
		var plan := sim._shuttle_plan(cart_id, flight_id, stand)
		if not bool(plan.get("ok", false)):
			continue
		_start_shuttle(sim, cart_id, flight_id, stand, plan, group)


static func reserves_cart_for_inbound(sim: BaggageSim, cart_id: int) -> bool:
	if sim.grid == null or sim.flights == null or sim.routes == null:
		return false
	var waiting := _on_plane_by_flight(sim)
	if waiting.is_empty():
		return false
	var has_active_inbound_flight := false
	for flight_id: String in waiting.keys():
		var state: int = sim.flights.state_of(flight_id)
		var stand := sim.flights.flight_stand(flight_id)
		if (
			not stand.is_empty()
			and state >= FlightSim.State.AT_STAND
			and state < FlightSim.State.PUSHBACK
		):
			has_active_inbound_flight = true
			break
	if not has_active_inbound_flight:
		return false
	var ends := sim.routes.inbound_bag_room_ends()
	if ends.is_empty():
		return false
	var rooms := {}
	for end_cell in ends:
		var rid := sim.grid.room_at(end_cell)
		if rid != 0:
			rooms[rid] = true
	var cart_is_inbound := false
	var idle_inbound_count := 0
	for object_id in sim.grid.object_ids():
		var record := sim.grid.get_object(object_id)
		if StringName(record["def"]) != BaggageSim.CART_DEF:
			continue
		if sim._cart_busy(object_id):
			continue
		var in_inbound_room := false
		for rid: int in rooms.keys():
			if RoomRules.piece_inside(sim.grid, object_id, sim.grid.get_room(rid)["rect"]):
				in_inbound_room = true
				break
		if in_inbound_room:
			idle_inbound_count += 1
			if object_id == cart_id:
				cart_is_inbound = true
	return cart_is_inbound and idle_inbound_count <= 1


static func waiting_for_ramp_carts(sim: BaggageSim, out: Array[int]) -> void:
	if sim.grid == null or sim.flights == null or not sim.shuttle_can_dispatch.is_valid():
		return
	var waiting := _on_plane_by_flight(sim)
	if waiting.is_empty():
		return
	var cart_id := _idle_inbound_cart(sim)
	if cart_id == 0 or out.has(cart_id):
		return
	var flight_keys := waiting.keys()
	flight_keys.sort()
	for flight_id: String in flight_keys:
		var state: int = sim.flights.state_of(flight_id)
		var stand := sim.flights.flight_stand(flight_id)
		if (
			stand.is_empty()
			or state >= FlightSim.State.PUSHBACK
			or state < FlightSim.State.AT_STAND
		):
			continue
		if not sim.shuttle_can_dispatch.call(cart_id, flight_id):
			out.append(cart_id)
			return


static func drop_cell_for_shuttle(sim: BaggageSim, shuttle: BaggageShuttle) -> Vector2i:
	if sim.grid == null or sim.routes == null:
		return Vector2i(-1, -1)
	var record := sim.grid.get_object(shuttle.cart_id)
	if not record.is_empty():
		var room_id := sim.grid.room_at(record["anchor"])
		if room_id != 0:
			var room_ends := sim.routes.inbound_bag_room_ends(room_id)
			if not room_ends.is_empty():
				return room_ends[0]
	var all_ends := sim.routes.inbound_bag_room_ends()
	return Vector2i(-1, -1) if all_ends.is_empty() else all_ends[0]


static func finish_unloading_shuttle(sim: BaggageSim, shuttle: BaggageShuttle) -> void:
	var drop_cell := drop_cell_for_shuttle(sim, shuttle)
	for bag_id in shuttle.pending_bag_ids:
		var bag := sim.get_bag(bag_id)
		if bag == null or bag.is_settled():
			continue
		if drop_cell != Vector2i(-1, -1):
			bag.cell = drop_cell
		bag.state = Bag.State.IN_ROOM
		bag.rest_tick = sim.tick
		bag.wait_tick = sim.tick
		shuttle.bag_ids.append(bag_id)
	shuttle.pending_bag_ids.clear()


static func start_transfer_in(sim: BaggageSim, shuttle: BaggageShuttle) -> bool:
	if shuttle.bag_ids.is_empty():
		return true
	var drop_cell := drop_cell_for_shuttle(sim, shuttle)
	if drop_cell == Vector2i(-1, -1):
		finish_returning_shuttle(sim, shuttle)
		return true
	var drop_w := sim.grid.cell_to_world(drop_cell)
	drop_w.y = BaggageShuttle.ground_y(sim.grid, drop_w)
	shuttle.pickup_world = drop_w
	shuttle.phase = BaggageShuttle.Phase.TRANSFER_IN
	shuttle.load_step_ticks = maxi(1, shuttle.load_step_ticks)
	_pickup_inbound_batch(sim, shuttle)
	if shuttle.carried_bag_ids.is_empty():
		return true
	shuttle.next_load_tick = sim.tick + shuttle.load_step_ticks
	return false


static func advance_transfer_in(sim: BaggageSim, shuttle: BaggageShuttle) -> bool:
	while sim.tick >= shuttle.next_load_tick:
		if not shuttle.carried_bag_ids.is_empty():
			var drop_cell := drop_cell_for_shuttle(sim, shuttle)
			for bag_id in shuttle.carried_bag_ids:
				var bag := sim.get_bag(bag_id)
				if bag == null or bag.is_settled():
					continue
				if drop_cell == Vector2i(-1, -1):
					settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
				else:
					bag.shuttle_id = 0
					bag.state = Bag.State.IN_ROOM
					bag.cell = drop_cell
					bag.rest_tick = sim.tick
					bag.wait_tick = sim.tick
			shuttle.carried_bag_ids.clear()
			if shuttle.bag_ids.is_empty():
				return true
			shuttle.next_load_tick += maxi(1, shuttle.load_step_ticks)
		else:
			_pickup_inbound_batch(sim, shuttle)
			if shuttle.carried_bag_ids.is_empty():
				return true
			shuttle.next_load_tick += maxi(1, shuttle.load_step_ticks)
	return false


static func _pickup_inbound_batch(sim: BaggageSim, shuttle: BaggageShuttle) -> void:
	while (
		not shuttle.bag_ids.is_empty()
		and shuttle.carried_bag_ids.size() < BaggageShuttle.CARRY_BATCH_SIZE
	):
		var bag_id: int = shuttle.bag_ids.pop_front()
		var bag := sim.get_bag(bag_id)
		if bag != null and not bag.is_settled():
			bag.shuttle_id = shuttle.id
			shuttle.carried_bag_ids.append(bag_id)


static func finish_returning_shuttle(sim: BaggageSim, shuttle: BaggageShuttle) -> void:
	var drop_cell := drop_cell_for_shuttle(sim, shuttle)
	for bag_id in shuttle.bag_ids:
		var bag := sim.get_bag(bag_id)
		if bag == null or bag.is_settled():
			continue
		if drop_cell == Vector2i(-1, -1):
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
		else:
			bag.shuttle_id = 0
			bag.state = Bag.State.IN_ROOM
			bag.cell = drop_cell
			bag.rest_tick = sim.tick
			bag.wait_tick = sim.tick
	shuttle.bag_ids.clear()
	for bag_id in shuttle.carried_bag_ids:
		var bag := sim.get_bag(bag_id)
		if bag == null or bag.is_settled():
			continue
		if drop_cell == Vector2i(-1, -1):
			settle_lost(sim, bag, Bag.Cause.LOST, sim.tick)
		else:
			bag.shuttle_id = 0
			bag.state = Bag.State.IN_ROOM
			bag.cell = drop_cell
			bag.rest_tick = sim.tick
			bag.wait_tick = sim.tick
	shuttle.carried_bag_ids.clear()


static func _on_plane_by_flight(sim: BaggageSim) -> Dictionary:
	var out := {}
	for bag in sim._bags:
		if bag.inbound and not bag.is_settled() and bag.shuttle_id == 0:
			if bag.state == Bag.State.ON_PLANE:
				var list: Array[Bag] = out.get(bag.flight, [] as Array[Bag])
				list.append(bag)
				out[bag.flight] = list
	return out


static func _idle_inbound_cart(sim: BaggageSim) -> int:
	var ends := sim.routes.inbound_bag_room_ends()
	if ends.is_empty():
		return 0
	var rooms := {}
	for end_cell in ends:
		var rid := sim.grid.room_at(end_cell)
		if rid != 0:
			rooms[rid] = true
	var ids := sim.grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := sim.grid.get_object(object_id)
		if StringName(record["def"]) != BaggageSim.CART_DEF:
			continue
		if sim._cart_busy(object_id):
			continue
		for rid: int in rooms.keys():
			if RoomRules.piece_inside(sim.grid, object_id, sim.grid.get_room(rid)["rect"]):
				return object_id
	return 0


static func _start_shuttle(
	sim: BaggageSim,
	cart_id: int,
	flight_id: String,
	stand: Dictionary,
	plan: Dictionary,
	group: Array[Bag],
) -> void:
	var sorted := group.duplicate()
	sorted.sort_custom(func(a: Bag, b: Bag) -> bool: return a.id < b.id)
	var travel: int = plan["travel"]
	var entry_ticks := BaggageShuttle.ENTRY_TICKS if sim.shuttle_can_dispatch.is_valid() else 0
	var shuttle := BaggageShuttle.new()
	shuttle.id = sim._next_shuttle_id
	sim._next_shuttle_id += 1
	shuttle.inbound = true
	shuttle.cart_id = cart_id
	shuttle.bay_door_id = int(plan["bay_door_id"])
	shuttle.flight = flight_id
	shuttle.phase = (
		BaggageShuttle.Phase.TO_BAG_ROOM if entry_ticks > 0 else BaggageShuttle.Phase.OUTBOUND
	)
	shuttle.load_start_tick = sim.tick
	shuttle.transfer_start_tick = sim.tick + entry_ticks
	shuttle.load_step_ticks = BaggageShuttle.TRANSFER_LEG_TICKS
	shuttle.next_load_tick = shuttle.transfer_start_tick
	shuttle.start_tick = shuttle.transfer_start_tick
	shuttle.arrive_tick = shuttle.start_tick + travel
	shuttle.unload_tick = shuttle.arrive_tick + BaggageShuttle.UNLOAD_TICKS
	shuttle.return_tick = shuttle.unload_tick + travel
	shuttle.origin_world = plan["origin"]
	shuttle.origin_yaw = float(plan["origin_yaw"])
	shuttle.target_world = plan["target"]
	shuttle.target_yaw = StandPlacement.SIDE_YAW[StandPlacement.side_of(stand)]
	var drop_cell := drop_cell_for_shuttle(sim, shuttle)
	var drop_w := (
		sim.grid.cell_to_world(drop_cell) if drop_cell != Vector2i(-1, -1) else shuttle.origin_world
	)
	drop_w.y = BaggageShuttle.ground_y(sim.grid, drop_w)
	shuttle.pickup_world = drop_w
	shuttle.bay_inside_world = plan["bay_inside"]
	shuttle.bay_door_world = plan["bay_door"]
	shuttle.bay_outside_world = plan["bay_outside"]
	shuttle.waypoints = plan["route"]
	for bag: Bag in sorted:
		bag.shuttle_id = shuttle.id
		shuttle.pending_bag_ids.append(bag.id)
	sim._shuttles.append(shuttle)
	sim._shuttle_by_id[shuttle.id] = shuttle
	sim.shuttle_dispatched.emit(shuttle.id, flight_id, cart_id)
