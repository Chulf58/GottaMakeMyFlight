class_name BaggageSnapshot
extends RefCounted
## The bags' part of a whole-world save (SaveGame part "baggage"): the bags,
## the per-flight results and the totals. No route is saved: BagRoutes
## rebuilds the field from the saved grid, and a save is taken only after the
## tick that reconciled the last edit, so every saved bag already fits it.
##
## load() checks the part alone; grid_problem() checks the bags against the
## field built from a grid (BaggageSim.from_snapshot and SaveLinks run it).
## The passenger and desk ids on a bag are historical and never checked
## against the other parts: a settled passenger is retired and a desk can be
## demolished while its bags remain.

const SAVE_VERSION := 5
const KEYS := [
	"save_version",
	"tick",
	"next_id",
	"next_shuttle_id",
	"bags",
	"shuttles",
	"results",
	"loaded_total",
	"missed_total",
	"inbound_claimed_total",
	"inbound_lost_total",
]
const BAG_KEYS := [
	"id",
	"inbound",
	"passenger",
	"flight",
	"desk",
	"carousel",
	"color",
	"state",
	"cause",
	"cell",
	"from",
	"remain_mm",
	"from_desk",
	"wait_tick",
	"created_tick",
	"cutoff_tick",
	"rest_tick",
	"outcome_tick",
	"shuttle_id",
]
const SHUTTLE_KEYS := [
	"id",
	"inbound",
	"cart_id",
	"bay_door_id",
	"flight",
	"phase",
	"load_start_tick",
	"transfer_start_tick",
	"load_step_ticks",
	"next_load_tick",
	"start_tick",
	"arrive_tick",
	"unload_tick",
	"return_tick",
	"origin_world",
	"origin_yaw",
	"target_world",
	"target_yaw",
	"pickup_world",
	"bay_inside_world",
	"bay_door_world",
	"bay_outside_world",
	"waypoints",
	"bag_ids",
	"carried_bag_ids",
	"pending_bag_ids",
	"driver_staff_id",
]
const RESULT_KEYS := ["loaded", "missed", "causes"]
## The whole-number fields of a saved bag that are ticks or ids, at least 0.
const COUNT_FIELDS := [
	"id", "passenger", "desk", "carousel", "color", "wait_tick", "created_tick", "shuttle_id"
]


static func save(sim: BaggageSim, next_id: int, next_shuttle_id := 1) -> Dictionary:
	var bags := []
	for bag in sim.bags():
		(
			bags
			. append(
				{
					"id": bag.id,
					"inbound": bag.inbound,
					"passenger": bag.passenger,
					"flight": bag.flight,
					"desk": bag.desk,
					"carousel": bag.carousel,
					"color": bag.color,
					"state": bag.state,
					"cause": bag.cause,
					"cell": [bag.cell.x, bag.cell.y],
					"from": [bag.from_step.x, bag.from_step.y],
					"remain_mm": bag.remain_mm,
					"from_desk": bag.from_desk,
					"wait_tick": bag.wait_tick,
					"created_tick": bag.created_tick,
					"cutoff_tick": bag.cutoff_tick,
					"rest_tick": bag.rest_tick,
					"outcome_tick": bag.outcome_tick,
					"shuttle_id": bag.shuttle_id,
				}
			)
		)
	var shuttles := []
	for shuttle in sim.shuttles():
		shuttles.append(_save_shuttle(shuttle))
	return {
		"save_version": SAVE_VERSION,
		"tick": sim.tick,
		"next_id": next_id,
		"next_shuttle_id": next_shuttle_id,
		"bags": bags,
		"shuttles": shuttles,
		"results": sim.results.duplicate(true),
		"loaded_total": sim.loaded_total,
		"missed_total": sim.missed_total,
		"inbound_claimed_total": sim.inbound_claimed_total,
		"inbound_lost_total": sim.inbound_lost_total,
	}


static func _save_shuttle(shuttle: BaggageShuttle) -> Dictionary:
	var saved_waypoints := []
	for pt in shuttle.waypoints:
		saved_waypoints.append([pt.x, pt.y, pt.z])
	return {
		"id": shuttle.id,
		"inbound": shuttle.inbound,
		"cart_id": shuttle.cart_id,
		"bay_door_id": shuttle.bay_door_id,
		"flight": shuttle.flight,
		"phase": shuttle.phase,
		"load_start_tick": shuttle.load_start_tick,
		"transfer_start_tick": shuttle.transfer_start_tick,
		"load_step_ticks": shuttle.load_step_ticks,
		"next_load_tick": shuttle.next_load_tick,
		"start_tick": shuttle.start_tick,
		"arrive_tick": shuttle.arrive_tick,
		"unload_tick": shuttle.unload_tick,
		"return_tick": shuttle.return_tick,
		"origin_world": [shuttle.origin_world.x, shuttle.origin_world.y, shuttle.origin_world.z],
		"origin_yaw": shuttle.origin_yaw,
		"target_world": [shuttle.target_world.x, shuttle.target_world.y, shuttle.target_world.z],
		"target_yaw": shuttle.target_yaw,
		"pickup_world": [shuttle.pickup_world.x, shuttle.pickup_world.y, shuttle.pickup_world.z],
		"bay_inside_world":
		[shuttle.bay_inside_world.x, shuttle.bay_inside_world.y, shuttle.bay_inside_world.z],
		"bay_door_world":
		[shuttle.bay_door_world.x, shuttle.bay_door_world.y, shuttle.bay_door_world.z],
		"bay_outside_world":
		[shuttle.bay_outside_world.x, shuttle.bay_outside_world.y, shuttle.bay_outside_world.z],
		"waypoints": saved_waypoints,
		"bag_ids": shuttle.bag_ids.duplicate(),
		"carried_bag_ids": shuttle.carried_bag_ids.duplicate(),
		"pending_bag_ids": shuttle.pending_bag_ids.duplicate(),
		"driver_staff_id": shuttle.driver_staff_id,
	}


## {"error": reason}, or {"tick", "next_id", "next_shuttle_id", "bags": Array[Bag],
## "shuttles": Array[BaggageShuttle], "results", "loaded_total", "missed_total"}
## with every number an int.
static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	var bags: Array[Bag] = []
	var shuttles: Array[BaggageShuttle] = []
	var shuttle_by_id := {}
	var results := {}
	if problem == "":
		problem = _read_shuttles(
			data["shuttles"],
			int(data["tick"]),
			int(data["next_shuttle_id"]),
			shuttles,
			shuttle_by_id
		)
	if problem == "":
		problem = _read_bags(
			data["bags"], int(data["tick"]), int(data["next_id"]), shuttle_by_id, bags
		)
	if problem == "":
		problem = _shuttle_links_problem(shuttles, bags, int(data["tick"]))
	if problem == "":
		problem = _read_results(data["results"], results)
	if problem == "":
		problem = _totals_problem(data, bags, results)
	if problem != "":
		return {"error": problem}
	return {
		"tick": int(data["tick"]),
		"next_id": int(data["next_id"]),
		"next_shuttle_id": int(data["next_shuttle_id"]),
		"bags": bags,
		"shuttles": shuttles,
		"results": results,
		"loaded_total": int(data["loaded_total"]),
		"missed_total": int(data["missed_total"]),
		"inbound_claimed_total": int(data["inbound_claimed_total"]),
		"inbound_lost_total": int(data["inbound_lost_total"]),
	}


## "" or the first bag or shuttle that does not fit the field `routes`: a bag
## on a belt whose state is not the one the field gives it (BaggageSim.belt_state),
## an unassigned bag in the room not on a root, two bags on one cell, or a
## shuttle naming a missing cart.
static func grid_problem(
	bags: Array[Bag], routes: BagRoutes, shuttles: Array[BaggageShuttle] = []
) -> String:
	var taken := {}
	for shuttle in shuttles:
		var record := routes.grid.get_object(shuttle.cart_id)
		if record.is_empty() or StringName(record["def"]) != BaggageSim.CART_DEF:
			return "shuttle %d names missing cart %d" % [shuttle.id, shuttle.cart_id]
		if shuttle.bay_door_id > 0:
			var door := routes.grid.get_object(shuttle.bay_door_id)
			if door.is_empty() or not BuildCatalog.is_bay_door(door["def"]):
				return "shuttle %d names missing bay door %d" % [shuttle.id, shuttle.bay_door_id]
	for bag in bags:
		if bag.state == Bag.State.IN_ROOM and bag.shuttle_id == 0:
			if bag.inbound:
				if not BaggageInbound.is_bag_room_end_cell(routes.grid, bag.cell):
					return (
						"bag %d is inbound in the room at %s, which is no bag room's end"
						% [bag.id, bag.cell]
					)
			elif not routes.is_root(bag.cell):
				return (
					"bag %d is in the room at %s, which is no bag room's end" % [bag.id, bag.cell]
				)
		if bag.state == Bag.State.ON_CAROUSEL:
			if not bag.inbound or not routes.is_ready_carousel(bag.carousel):
				return "bag %d is on missing or unready carousel %d" % [bag.id, bag.carousel]
		if not bag.on_belt():
			continue
		var state := BaggageSim.belt_state(bag, routes)
		if state != bag.state:
			return (
				"bag %d is %s at %s but the belts make it %s"
				% [bag.id, Bag.State.keys()[bag.state], bag.cell, Bag.State.keys()[state]]
			)
		for cell in [bag.cell, bag.physical_cell()]:
			if taken.get(cell, bag.id) != bag.id:
				return "bags %d and %d are on one belt cell %s" % [taken[cell], bag.id, cell]
			taken[cell] = bag.id
	return ""


static func _top_problem(data: Dictionary) -> String:
	var problem := ""
	for key in data.keys():
		if problem == "" and not KEYS.has(key):
			problem = "unknown key '%s'" % key
	for key in KEYS:
		if problem == "" and not data.has(key):
			problem = "missing key '%s'" % key
	if problem != "":
		return problem
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	for key in [
		"tick", "loaded_total", "missed_total", "inbound_claimed_total", "inbound_lost_total"
	]:
		if not _is_count(data[key]):
			return "%s must be a whole number of at least 0" % key
	for key in ["next_id", "next_shuttle_id"]:
		if not WholeNumber.is_whole(data[key]) or int(data[key]) < 1:
			return "%s must be a whole number of at least 1" % key
	if (
		typeof(data["bags"]) != TYPE_ARRAY
		or typeof(data["shuttles"]) != TYPE_ARRAY
		or typeof(data["results"]) != TYPE_DICTIONARY
	):
		return "bags and shuttles must be lists and results a dictionary"
	return ""


static func _read_shuttles(
	saved: Array,
	tick: int,
	next_shuttle_id: int,
	out: Array[BaggageShuttle],
	by_id: Dictionary,
) -> String:
	var last_id := 0
	var claimed_bags := {}
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			return "a shuttle is not a dictionary"
		var shuttle := BaggageShuttle.new()
		var problem := _read_shuttle(entry, shuttle)
		if problem == "":
			problem = _shuttle_rules(shuttle, tick)
		if problem == "" and (shuttle.id <= last_id or shuttle.id >= next_shuttle_id):
			problem = "shuttle ids must rise and stay under next_shuttle_id"
		if problem == "":
			for bag_id in shuttle.bag_ids:
				if claimed_bags.has(bag_id):
					problem = "bag %d is on two shuttles" % bag_id
					break
				claimed_bags[bag_id] = shuttle.id
		if problem == "":
			for bag_id in shuttle.carried_bag_ids:
				if claimed_bags.has(bag_id):
					problem = "bag %d is on two shuttles" % bag_id
					break
				claimed_bags[bag_id] = shuttle.id
		if problem != "":
			return "shuttle %s: %s" % [entry.get("id", "?"), problem]
		last_id = shuttle.id
		by_id[shuttle.id] = shuttle
		out.append(shuttle)
	return ""


static func _read_shuttle(entry: Dictionary, shuttle: BaggageShuttle) -> String:
	var problem := _keys_problem(entry, SHUTTLE_KEYS)
	if problem != "":
		return problem
	for key in ["id", "cart_id", "load_step_ticks"]:
		if not WholeNumber.is_whole(entry[key]) or int(entry[key]) < 1:
			return "%s must be a positive whole number" % key
	if int(entry["load_step_ticks"]) > BaggageShuttle.TRANSFER_LEG_TICKS:
		return "load_step_ticks must be at most %d" % BaggageShuttle.TRANSFER_LEG_TICKS
	for key in [
		"bay_door_id",
		"load_start_tick",
		"transfer_start_tick",
		"next_load_tick",
		"start_tick",
		"arrive_tick",
		"unload_tick",
		"return_tick",
		"driver_staff_id",
	]:
		if not _is_count(entry[key]):
			return "%s must be a whole number of at least 0" % key
	if typeof(entry["inbound"]) != TYPE_BOOL:
		return "inbound must be true or false"
	if typeof(entry["flight"]) != TYPE_STRING or entry["flight"] == "":
		return "flight must be a flight id"
	if not _is_member(entry["phase"], BaggageShuttle.Phase.values()):
		return "phase is not a shuttle phase"
	for vkey in [
		"origin_world",
		"target_world",
		"pickup_world",
		"bay_inside_world",
		"bay_door_world",
		"bay_outside_world",
	]:
		if not _is_vec3(entry[vkey]):
			return "%s must be [x, y, z] numbers" % vkey
	if not _is_finite_num(entry["origin_yaw"]) or not _is_finite_num(entry["target_yaw"]):
		return "origin_yaw and target_yaw must be finite numbers"
	if typeof(entry["waypoints"]) != TYPE_ARRAY:
		return "waypoints must be a list"
	var pts: Array[Vector3] = []
	for raw_pt in entry["waypoints"]:
		if not _is_vec3(raw_pt):
			return "waypoints must hold [x, y, z] numbers"
		pts.append(Vector3(float(raw_pt[0]), float(raw_pt[1]), float(raw_pt[2])))
	var ids: Array[int] = []
	var carried: Array[int] = []
	var pending: Array[int] = []
	var list_err := _read_id_list(entry["bag_ids"], "bag_ids", ids)
	if list_err == "":
		list_err = _read_id_list(entry["carried_bag_ids"], "carried_bag_ids", carried)
	if list_err == "":
		list_err = _read_id_list(entry["pending_bag_ids"], "pending_bag_ids", pending)
	if list_err != "":
		return list_err
	if carried.size() > BaggageShuttle.CARRY_BATCH_SIZE:
		return "carried_bag_ids exceeds carry batch size"
	shuttle.id = int(entry["id"])
	shuttle.inbound = entry["inbound"]
	shuttle.cart_id = int(entry["cart_id"])
	shuttle.bay_door_id = int(entry["bay_door_id"])
	shuttle.flight = entry["flight"]
	shuttle.phase = int(entry["phase"]) as BaggageShuttle.Phase
	shuttle.load_start_tick = int(entry["load_start_tick"])
	shuttle.transfer_start_tick = int(entry["transfer_start_tick"])
	shuttle.load_step_ticks = int(entry["load_step_ticks"])
	shuttle.next_load_tick = int(entry["next_load_tick"])
	shuttle.start_tick = int(entry["start_tick"])
	shuttle.arrive_tick = int(entry["arrive_tick"])
	shuttle.unload_tick = int(entry["unload_tick"])
	shuttle.return_tick = int(entry["return_tick"])
	shuttle.origin_world = _to_vec3(entry["origin_world"])
	shuttle.origin_yaw = float(entry["origin_yaw"])
	shuttle.target_world = _to_vec3(entry["target_world"])
	shuttle.target_yaw = float(entry["target_yaw"])
	shuttle.pickup_world = _to_vec3(entry["pickup_world"])
	shuttle.bay_inside_world = _to_vec3(entry["bay_inside_world"])
	shuttle.bay_door_world = _to_vec3(entry["bay_door_world"])
	shuttle.bay_outside_world = _to_vec3(entry["bay_outside_world"])
	shuttle.waypoints = pts
	shuttle.bag_ids = ids
	shuttle.carried_bag_ids = carried
	shuttle.pending_bag_ids = pending
	shuttle.driver_staff_id = int(entry["driver_staff_id"])
	return ""


static func _read_id_list(raw_list: Variant, field: String, out: Array[int]) -> String:
	if typeof(raw_list) != TYPE_ARRAY:
		return "%s must be a list" % field
	for raw in raw_list:
		if not WholeNumber.is_whole(raw) or int(raw) < 1:
			return "%s must hold positive whole numbers" % field
		out.append(int(raw))
	return ""


static func _to_vec3(arr: Array) -> Vector3:
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _shuttle_rules(shuttle: BaggageShuttle, tick: int) -> String:
	if (
		shuttle.load_start_tick > shuttle.transfer_start_tick
		or shuttle.transfer_start_tick > shuttle.start_tick
		or shuttle.start_tick > shuttle.arrive_tick
		or shuttle.arrive_tick > shuttle.unload_tick
		or shuttle.unload_tick > shuttle.return_tick
	):
		return "shuttle schedule ticks are out of order"
	if (
		shuttle.load_start_tick > tick
		or (shuttle.phase != BaggageShuttle.Phase.TRANSFER_IN and tick >= shuttle.return_tick)
	):
		return "shuttle is outside its active tick span"
	if shuttle.phase == BaggageShuttle.Phase.TO_BAG_ROOM:
		if (
			shuttle.load_start_tick >= shuttle.transfer_start_tick
			or tick >= shuttle.transfer_start_tick
		):
			return "to_bag_room shuttle is outside [load_start_tick, transfer_start_tick)"
	elif shuttle.phase == BaggageShuttle.Phase.TRANSFER_OUT:
		if shuttle.inbound:
			return "inbound shuttle cannot be in transfer_out"
		if (
			shuttle.transfer_start_tick >= shuttle.start_tick
			or tick < shuttle.transfer_start_tick
			or tick >= shuttle.start_tick
		):
			return "transfer_out shuttle is outside [transfer_start_tick, start_tick)"
	elif shuttle.phase == BaggageShuttle.Phase.OUTBOUND:
		if tick < shuttle.start_tick or tick >= shuttle.arrive_tick:
			return "outbound shuttle is outside [start_tick, arrive_tick)"
	elif shuttle.phase == BaggageShuttle.Phase.UNLOADING:
		if tick < shuttle.arrive_tick or tick >= shuttle.unload_tick:
			return "unloading shuttle is outside [arrive_tick, unload_tick)"
	elif shuttle.phase == BaggageShuttle.Phase.RETURNING:
		if tick < shuttle.unload_tick or tick >= shuttle.return_tick:
			return "returning shuttle is outside [unload_tick, return_tick)"
	elif shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN:
		if not shuttle.inbound or tick < shuttle.return_tick:
			return "transfer_in shuttle must be inbound at or after return_tick"
	if shuttle.waypoints.size() < 2:
		return "shuttle waypoints must have at least 2 points"
	if (
		not shuttle.waypoints[0].is_equal_approx(shuttle.origin_world)
		or not shuttle.waypoints[shuttle.waypoints.size() - 1].is_equal_approx(shuttle.target_world)
	):
		return "shuttle waypoints must start at origin_world and end at target_world"
	return ""


static func _shuttle_links_problem(
	shuttles: Array[BaggageShuttle], bags: Array[Bag], tick: int
) -> String:
	var by_id := {}
	for bag in bags:
		by_id[bag.id] = bag
	var claimed := {}
	for shuttle in shuttles:
		var err := _single_shuttle_links_problem(shuttle, by_id, claimed, tick)
		if err != "":
			return err
	return ""


static func _single_shuttle_links_problem(
	shuttle: BaggageShuttle, by_id: Dictionary, claimed: Dictionary, tick: int
) -> String:
	if shuttle.phase == BaggageShuttle.Phase.TO_BAG_ROOM:
		if (
			not shuttle.bag_ids.is_empty()
			or not shuttle.carried_bag_ids.is_empty()
			or shuttle.pending_bag_ids.is_empty()
		):
			return "shuttle %d: to_bag_room shuttle must hold pending bags only" % shuttle.id
		return _shuttle_bag_list_problem(
			shuttle, by_id, claimed, shuttle.pending_bag_ids, shuttle.inbound
		)
	if shuttle.inbound:
		return _inbound_shuttle_links_problem(shuttle, by_id, claimed, tick)
	if shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN:
		return "shuttle %d: outbound shuttle cannot be in transfer_in" % shuttle.id
	if shuttle.phase == BaggageShuttle.Phase.RETURNING:
		if (
			not shuttle.bag_ids.is_empty()
			or not shuttle.carried_bag_ids.is_empty()
			or not shuttle.pending_bag_ids.is_empty()
		):
			return "shuttle %d: returning shuttle must hold no bags" % shuttle.id
		return ""
	if shuttle.phase != BaggageShuttle.Phase.TRANSFER_OUT:
		if (
			not shuttle.carried_bag_ids.is_empty()
			or not shuttle.pending_bag_ids.is_empty()
			or shuttle.bag_ids.is_empty()
		):
			return "shuttle %d: outbound/unloading shuttle must carry bag_ids only" % shuttle.id
	else:
		var sched_err := _transfer_schedule_problem(
			shuttle, shuttle.transfer_start_tick, tick, shuttle.carried_bag_ids
		)
		if sched_err != "":
			return sched_err
		if (
			shuttle.bag_ids.is_empty()
			and shuttle.carried_bag_ids.is_empty()
			and shuttle.pending_bag_ids.is_empty()
		):
			return "shuttle %d: transfer_out shuttle must hold bags" % shuttle.id
	for pair in [
		[shuttle.bag_ids, true],
		[shuttle.carried_bag_ids, true],
		[shuttle.pending_bag_ids, false],
	]:
		var problem := _shuttle_bag_list_problem(shuttle, by_id, claimed, pair[0], pair[1])
		if problem != "":
			return problem
	return ""


static func _inbound_shuttle_links_problem(
	shuttle: BaggageShuttle, by_id: Dictionary, claimed: Dictionary, tick: int
) -> String:
	if shuttle.phase == BaggageShuttle.Phase.RETURNING:
		if (
			not shuttle.pending_bag_ids.is_empty()
			or not shuttle.carried_bag_ids.is_empty()
			or shuttle.bag_ids.is_empty()
		):
			return "shuttle %d: returning inbound shuttle must carry bag_ids only" % shuttle.id
		return _shuttle_bag_list_problem(shuttle, by_id, claimed, shuttle.bag_ids, true)
	if shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN:
		if not shuttle.pending_bag_ids.is_empty():
			return "shuttle %d: transfer_in shuttle cannot hold pending bags" % shuttle.id
		if shuttle.bag_ids.is_empty() and shuttle.carried_bag_ids.is_empty():
			return "shuttle %d: transfer_in shuttle must hold bags" % shuttle.id
		var sched_err := _transfer_schedule_problem(
			shuttle, shuttle.return_tick, tick, shuttle.carried_bag_ids
		)
		if sched_err != "":
			return sched_err
		var p1 := _shuttle_bag_list_problem(shuttle, by_id, claimed, shuttle.bag_ids, true)
		if p1 != "":
			return p1
		return _shuttle_bag_list_problem(shuttle, by_id, claimed, shuttle.carried_bag_ids, true)
	if (
		not shuttle.bag_ids.is_empty()
		or not shuttle.carried_bag_ids.is_empty()
		or shuttle.pending_bag_ids.is_empty()
	):
		return "shuttle %d: outbound inbound shuttle must hold pending bags" % shuttle.id
	return _shuttle_bag_list_problem(shuttle, by_id, claimed, shuttle.pending_bag_ids, true)


static func _transfer_schedule_problem(
	shuttle: BaggageShuttle, base_tick: int, tick: int, carried: Array[int]
) -> String:
	if shuttle.next_load_tick <= tick or shuttle.next_load_tick > tick + shuttle.load_step_ticks:
		return "shuttle %d: next_load_tick is inconsistent with current tick" % shuttle.id
	if (shuttle.next_load_tick - base_tick) % shuttle.load_step_ticks != 0:
		return "shuttle %d: next_load_tick is misaligned with load_step_ticks" % shuttle.id
	@warning_ignore("integer_division")
	var leg_idx := (shuttle.next_load_tick - base_tick) / shuttle.load_step_ticks
	if leg_idx % 2 == 1 and carried.is_empty():
		return "shuttle %d: carry leg must hold carried_bag_ids" % shuttle.id
	if leg_idx % 2 == 0 and not carried.is_empty():
		return "shuttle %d: return leg must hold empty carried_bag_ids" % shuttle.id
	return ""


static func _shuttle_bag_list_problem(
	shuttle: BaggageShuttle,
	by_id: Dictionary,
	claimed: Dictionary,
	list: Array[int],
	owned: bool,
) -> String:
	for bag_id in list:
		var bag: Bag = by_id.get(bag_id)
		if bag == null:
			return "shuttle %d: names missing bag %d" % [shuttle.id, bag_id]
		if bag.flight != shuttle.flight:
			return (
				"shuttle %d: bag %d belongs to flight %s, not %s"
				% [shuttle.id, bag_id, bag.flight, shuttle.flight]
			)
		if bag.inbound != shuttle.inbound:
			return "shuttle %d: flow mismatch on bag %d" % [shuttle.id, bag_id]
		var expected_state := (
			Bag.State.IN_ROOM
			if (
				not shuttle.inbound
				or shuttle.phase == BaggageShuttle.Phase.RETURNING
				or shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN
			)
			else Bag.State.ON_PLANE
		)
		if bag.is_settled() or bag.state != expected_state:
			return "shuttle %d: names wrong-state bag %d" % [shuttle.id, bag_id]
		if claimed.has(bag_id):
			return "shuttle %d: duplicates bag %d" % [shuttle.id, bag_id]
		claimed[bag_id] = true
		var expected_shuttle := shuttle.id if owned else 0
		if bag.shuttle_id != expected_shuttle:
			return (
				"shuttle %d: names bag %d owned by shuttle %d"
				% [shuttle.id, bag_id, bag.shuttle_id]
			)
	return ""


static func _read_bags(
	saved: Array, tick: int, next_id: int, shuttles: Dictionary, out: Array[Bag]
) -> String:
	var last_id := 0
	# Passenger id -> bag id: one bag per passenger, whether or not the
	# passenger is still in the passengers part.
	var owners := {}
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			return "a bag is not a dictionary"
		var bag := Bag.new()
		var problem := _read_bag(entry, bag)
		if problem == "":
			problem = _bag_rules(bag, tick, shuttles)
		if problem == "" and (bag.id <= last_id or bag.id >= next_id):
			problem = "ids must rise and stay under next_id"
		if problem == "" and bag.passenger > 0 and owners.has(bag.passenger):
			problem = "passenger %d already has bag %d" % [bag.passenger, owners[bag.passenger]]
		if problem != "":
			return "bag %s: %s" % [entry.get("id", "?"), problem]
		last_id = bag.id
		if bag.passenger > 0:
			owners[bag.passenger] = bag.id
		out.append(bag)
	return ""


static func _read_bag(entry: Dictionary, bag: Bag) -> String:
	var problem := _keys_problem(entry, BAG_KEYS)
	if problem == "":
		problem = _field_problem(entry)
	if problem != "":
		return problem
	bag.id = int(entry["id"])
	bag.inbound = entry["inbound"]
	bag.passenger = int(entry["passenger"])
	bag.flight = entry["flight"]
	bag.desk = int(entry["desk"])
	bag.carousel = int(entry["carousel"])
	bag.color = int(entry["color"])
	bag.state = int(entry["state"]) as Bag.State
	bag.cause = int(entry["cause"]) as Bag.Cause
	bag.cell = Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
	bag.from_step = Vector2i(int(entry["from"][0]), int(entry["from"][1]))
	bag.remain_mm = int(entry["remain_mm"])
	bag.from_desk = entry["from_desk"]
	bag.wait_tick = int(entry["wait_tick"])
	bag.created_tick = int(entry["created_tick"])
	bag.cutoff_tick = int(entry["cutoff_tick"])
	bag.rest_tick = int(entry["rest_tick"])
	bag.outcome_tick = int(entry["outcome_tick"])
	bag.shuttle_id = int(entry["shuttle_id"])
	return ""


## "" when `entry` has exactly `keys`, else the first unknown or missing one.
static func _keys_problem(entry: Dictionary, keys: Array) -> String:
	var problem := ""
	for key in entry.keys():
		if problem == "" and not keys.has(key):
			problem = "unknown key '%s'" % key
	for key in keys:
		if problem == "" and not entry.has(key):
			problem = "missing key '%s'" % key
	return problem


## The type and range of each saved bag field.
static func _field_problem(entry: Dictionary) -> String:
	var problem := ""
	for key in COUNT_FIELDS + ["remain_mm"]:
		if problem == "" and not _is_count(entry[key]):
			problem = "%s must be a whole number of at least 0" % key
	for key in ["rest_tick", "outcome_tick"]:
		if problem == "" and (not WholeNumber.is_whole(entry[key]) or int(entry[key]) < -1):
			problem = "%s must be a whole number of at least -1" % key
	if problem == "" and not WholeNumber.is_whole(entry["cutoff_tick"]):
		problem = "cutoff_tick must be a whole number"
	if (
		problem == ""
		and (typeof(entry["from_desk"]) != TYPE_BOOL or typeof(entry["inbound"]) != TYPE_BOOL)
	):
		problem = "from_desk and inbound must be true or false"
	if problem != "":
		return problem
	if typeof(entry["flight"]) != TYPE_STRING or entry["flight"] == "":
		problem = "flight must be a flight id"
	elif int(entry["color"]) >= Bag.SUITCASE_COLORS.size():
		problem = "color is not a suitcase color"
	elif not _is_member(entry["state"], Bag.State.values()):
		problem = "state is not a bag state"
	elif not _is_member(entry["cause"], Bag.Cause.values()):
		problem = "cause is not a bag cause"
	elif not _is_pair(entry["cell"]) or not _is_pair(entry["from"]):
		problem = "cell and from must be [x, y] whole numbers"
	return problem


static func _bag_rules(bag: Bag, tick: int, shuttles: Dictionary) -> String:
	var problem := ""
	if bag.created_tick > tick or bag.wait_tick > tick or bag.wait_tick < bag.created_tick:
		problem = "it was made or began waiting after the saved tick"
	elif bag.is_settled() != (bag.outcome_tick >= 0):
		problem = "only a settled bag has an outcome tick"
	elif bag.is_settled() and (bag.outcome_tick < bag.created_tick or bag.outcome_tick > tick):
		problem = "its outcome tick is outside its life"
	elif (
		not bag.inbound
		and not bag.is_settled()
		and bag.shuttle_id == 0
		and (
			(bag.state != Bag.State.IN_ROOM and tick >= bag.cutoff_tick)
			or (
				bag.state == Bag.State.IN_ROOM
				and tick >= bag.cutoff_tick + BaggageSim.LOAD_LEAD_TICKS
			)
		)
	):
		problem = "it is still unsettled after its cutoff"
	elif (bag.state == Bag.State.MISSED) != (bag.cause != Bag.Cause.NONE):
		problem = "a missed bag, and only a missed one, has a cause"
	elif (
		(bag.state == Bag.State.IN_ROOM or bag.state == Bag.State.ON_CAROUSEL)
		and (bag.rest_tick < bag.created_tick or bag.rest_tick > tick)
	):
		problem = "a bag in the room or on a carousel needs a rest tick in its life"
	if problem == "" and bag.inbound:
		if bag.desk != 0 or bag.from_desk:
			problem = "an inbound bag cannot reference a check-in desk"
		elif bag.state == Bag.State.AT_DESK or bag.state == Bag.State.LOADED:
			problem = "an inbound bag cannot be at a desk or loaded onto departure"
		elif bag.state == Bag.State.ON_CAROUSEL and (bag.carousel <= 0 or bag.shuttle_id != 0):
			problem = "a carousel bag needs a carousel and no shuttle"
	elif problem == "" and not bag.inbound:
		if (
			bag.carousel != 0
			or bag.state == Bag.State.ON_CAROUSEL
			or bag.state == Bag.State.CLAIMED
			or bag.state == Bag.State.ON_PLANE
		):
			problem = "an outbound bag cannot use inbound states"
	if problem == "" and bag.is_settled() and bag.shuttle_id != 0:
		problem = "a settled bag cannot reference a shuttle"
	if problem == "" and not bag.is_settled() and bag.shuttle_id > 0:
		var shuttle: BaggageShuttle = shuttles.get(bag.shuttle_id)
		if shuttle == null or shuttle.inbound != bag.inbound:
			problem = "it names no active shuttle"
		elif bag.inbound:
			if (
				shuttle.phase == BaggageShuttle.Phase.RETURNING
				or shuttle.phase == BaggageShuttle.Phase.TRANSFER_IN
			):
				if (
					(not shuttle.bag_ids.has(bag.id) and not shuttle.carried_bag_ids.has(bag.id))
					or bag.state != Bag.State.IN_ROOM
				):
					problem = "a returning inbound bag must be in the room on its shuttle"
			elif not shuttle.pending_bag_ids.has(bag.id) or bag.state != Bag.State.ON_PLANE:
				problem = "an unloading inbound bag must be on the plane for its shuttle"
		elif (
			(not shuttle.bag_ids.has(bag.id) and not shuttle.carried_bag_ids.has(bag.id))
			or bag.state != Bag.State.IN_ROOM
		):
			problem = "a bag riding a shuttle must be in the room on an active trip"
	if problem == "":
		problem = _edge_rules(bag)
	return problem


## Where a bag may be along its edge, by state. A bag on a belt came in by
## one side and is within one cell of its centre (half a cell from a desk).
## A missed bag keeps the place it stopped at. A bag at a desk, in the room
## or loaded is at no edge.
static func _edge_rules(bag: Bag) -> String:
	var problem := ""
	var side := BuildGrid.SIDE_STEP.has(bag.from_step)
	var stopped := bag.on_belt() or bag.state == Bag.State.MISSED
	if not side and bag.from_step != Vector2i.ZERO:
		problem = "it came in by no side"
	elif bag.on_belt() and not side:
		problem = "a bag on a belt came in by one side"
	elif bag.remain_mm > Bag.CELL_MM or (bag.remain_mm > 0 and not (stopped and side)):
		problem = "remain_mm is outside its edge"
	elif bag.from_desk and bag.remain_mm * 2 > Bag.CELL_MM:
		problem = "a bag from a desk rides half a cell"
	return problem


static func _read_results(saved: Dictionary, out: Dictionary) -> String:
	for flight in saved.keys():
		var problem := ""
		if typeof(flight) != TYPE_STRING or typeof(saved[flight]) != TYPE_DICTIONARY:
			problem = "results must map flight ids to dictionaries"
		else:
			problem = _read_result(saved[flight], out, flight)
		if problem != "":
			return "results for %s: %s" % [flight, problem]
	return ""


static func _read_result(entry: Dictionary, out: Dictionary, flight: String) -> String:
	var problem := _keys_problem(entry, RESULT_KEYS)
	if problem == "" and (not _is_count(entry["loaded"]) or not _is_count(entry["missed"])):
		problem = "loaded and missed must be whole counts"
	if problem == "" and typeof(entry["causes"]) != TYPE_DICTIONARY:
		problem = "causes must be a dictionary"
	if problem != "":
		return problem
	var causes := {}
	var summed := 0
	for key in entry["causes"].keys():
		var count: Variant = entry["causes"][key]
		if (
			problem == ""
			and (key == "none" or not Bag.CAUSE_NAMES.has(key) or not _is_count(count))
		):
			problem = "'%s' is not a cause with a count" % key
		elif problem == "":
			causes[key] = int(count)
			summed += int(count)
	if problem == "" and summed != int(entry["missed"]):
		problem = "the causes must add up to the missed bags"
	if problem == "":
		out[flight] = {
			"loaded": int(entry["loaded"]), "missed": int(entry["missed"]), "causes": causes
		}
	return problem


## The totals cover the results, and each flight's results cover its settled
## bags still kept.
static func _totals_problem(data: Dictionary, bags: Array[Bag], results: Dictionary) -> String:
	var kept := {}
	var kept_inbound_claimed := 0
	var kept_inbound_lost := 0
	for bag in bags:
		if not bag.is_settled():
			continue
		if bag.inbound:
			if bag.state == Bag.State.CLAIMED:
				kept_inbound_claimed += 1
			else:
				kept_inbound_lost += 1
			continue
		var counts: Array = kept.get(bag.flight, [0, 0])
		counts[0 if bag.state == Bag.State.LOADED else 1] += 1
		kept[bag.flight] = counts
	var sums := [0, 0]
	for flight in results:
		sums[0] += results[flight]["loaded"]
		sums[1] += results[flight]["missed"]
	for flight in kept:
		var result: Dictionary = results.get(flight, {"loaded": 0, "missed": 0})
		if result["loaded"] < kept[flight][0] or result["missed"] < kept[flight][1]:
			return "results for %s count fewer bags than are kept settled" % flight
	if int(data["loaded_total"]) < sums[0] or int(data["missed_total"]) < sums[1]:
		return "the totals are below the results"
	if (
		int(data["inbound_claimed_total"]) < kept_inbound_claimed
		or int(data["inbound_lost_total"]) < kept_inbound_lost
	):
		return "the inbound totals are below kept settled inbound bags"
	return ""


static func _is_count(value: Variant) -> bool:
	return WholeNumber.is_whole(value) and int(value) >= 0


static func _is_pair(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_ARRAY
		and value.size() == 2
		and WholeNumber.is_whole(value[0])
		and WholeNumber.is_whole(value[1])
	)


static func _is_member(value: Variant, members: Array) -> bool:
	return WholeNumber.is_whole(value) and members.has(int(value))


static func _is_finite_num(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_vec3(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_ARRAY
		and value.size() == 3
		and _is_finite_num(value[0])
		and _is_finite_num(value[1])
		and _is_finite_num(value[2])
	)
