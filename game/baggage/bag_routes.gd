class_name BagRoutes
extends RefCounted
## The route field bags follow (decision baggage-bag-sim-design-route-field-
## belt-capacity-cutoff): for every belt cell that can reach a bag room, the
## step to take next and how many cells are left. Built from the grid alone,
## so the same grid always gives the same field and no bag path is saved.
##
## The roots are the belt end pieces inside a ready bag room (RoomRules), in
## coordinate order (y, then x). A breadth-first search goes out from them
## together, neighbours in BuildGrid.SIDE_STEP order, and the first visit to
## a cell decides its step; so each next step leads to a cell one closer to a
## root, and ties go to the earlier root, then the earlier side. There is no
## sorting by flight: a bag goes to the nearest bag room.
##
## Two cells join when BeltShaper.Scene.links() lists the step both ways (no
## wall between them) and both pieces have a port on that edge. Every shaped
## piece joins all its ports, so a bag may ride a belt either way; a piece a
## debug layout left unshaped is crossed only through its own ports.

var grid: BuildGrid
var scene: BeltShaper.Scene
## Outbound route field: cell -> cells left to a bag_room end root, and next step.
var dist := {}
var next := {}
## Inbound route field: cell -> cells left to a ready claim_carousel inlet belt
## cell, and next step toward that carousel.
var inbound_dist := {}
var inbound_next := {}
var inbound_component := {}

var _carousel_by_inlet := {}
var _ready_carousels := {}
var _ready_bag_rooms := {}


static func build(on: BuildGrid) -> BagRoutes:
	var routes := BagRoutes.new()
	routes.grid = on
	routes.scene = BeltShaper.Scene.new(on)
	routes._index_ready_rooms()
	routes._build_inbound()
	var queue: Array[Vector2i] = routes._roots()
	for root in queue:
		routes.dist[root] = 0
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for step in BuildGrid.SIDE_STEP:
			var from: Vector2i = at + step
			if routes.dist.has(from) or not routes.joined(at, step):
				continue
			routes.dist[from] = routes.dist[at] + 1
			routes.next[from] = -step
			queue.append(from)
	return routes


func is_belt(cell: Vector2i) -> bool:
	return scene.is_belt(cell)


func is_root(cell: Vector2i) -> bool:
	return dist.get(cell, -1) == 0


func has_route(cell: Vector2i) -> bool:
	return dist.has(cell)


## The step toward a bag room from `cell`; Vector2i.ZERO on a root or with no
## route.
func step_from(cell: Vector2i) -> Vector2i:
	return next.get(cell, Vector2i.ZERO)


## The belt end root cell reachable from `cell`, or Vector2i(-1, -1) with no route.
func root_of(cell: Vector2i) -> Vector2i:
	if not has_route(cell):
		return Vector2i(-1, -1)
	var cur := cell
	while next.has(cur):
		cur += next[cur]
	return cur


## Whether check-in desk `desk_id` has an outlet belt with a route to a ready bag room.
func desk_connected(desk_id: int) -> bool:
	var entry := entry_of(desk_id)
	return not entry.is_empty() and has_route(entry["cell"])


## Sorted check-in desk ids routed to a ready bag room (or to `room_id` when nonzero).
func connected_desks(room_id: int = 0) -> Array[int]:
	var out: Array[int] = []
	if grid == null:
		return out
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != BeltShaper.DESK:
			continue
		var entry := entry_of(object_id)
		if entry.is_empty() or not has_route(entry["cell"]):
			continue
		if room_id != 0 and grid.room_at(root_of(entry["cell"])) != room_id:
			continue
		out.append(object_id)
	return out


## Number of check-in desks routed to a ready bag room (or to `room_id` when nonzero).
func connected_desk_count(room_id: int = 0) -> int:
	return connected_desks(room_id).size()


func is_inbound_root(cell: Vector2i) -> bool:
	return inbound_dist.get(cell, -1) == 0


func has_inbound_route(cell: Vector2i) -> bool:
	return inbound_dist.has(cell)


func inbound_step_from(cell: Vector2i) -> Vector2i:
	return inbound_next.get(cell, Vector2i.ZERO)


func carousel_of(cell: Vector2i) -> int:
	if _carousel_by_inlet.has(cell):
		return _carousel_by_inlet[cell]
	if not has_inbound_route(cell):
		return 0
	var cur := cell
	while inbound_next.has(cur):
		cur += inbound_next[cur]
	return _carousel_by_inlet.get(cur, 0)


func is_ready_carousel(carousel_id: int) -> bool:
	return _ready_carousels.has(carousel_id)


## Where `claim_carousel` `carousel_id` takes inbound bags: {"cell": inlet belt
## cell, "step": step from that belt cell into the carousel port}, or {} when
## missing/unwired.
func carousel_entry_of(carousel_id: int) -> Dictionary:
	var record := grid.get_object(carousel_id)
	if record.is_empty() or StringName(record["def"]) != BeltShaper.CLAIM_CAROUSEL:
		return {}
	for port in BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"]):
		var side: Vector2i = port["side"]
		var into: Vector2i = port["cell"] + side
		if not is_belt(into) or not scene.open(port["cell"], side):
			continue
		if scene.links(into).has(-side) and _has_port(into, -side):
			return {"cell": into, "step": -side}
	return {}


## Sorted inbound baggage_belt_end cells inside a ready bag room (or `bag_room_id`
## when nonzero) that route to a ready baggage_claim claim_carousel.
func inbound_bag_room_ends(bag_room_id: int = 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null:
		return out
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != BeltShaper.END:
			continue
		var cell: Vector2i = record["anchor"]
		var room_id := grid.room_at(cell)
		if not _ready_bag_rooms.has(room_id):
			continue
		if bag_room_id != 0 and room_id != bag_room_id:
			continue
		if has_inbound_route(cell):
			out.append(cell)
	out.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return out


## Sorted ready claim_carousel ids reachable from at least one ready bag_room
## inbound belt end (filtered to `room_id` when nonzero).
func connected_carousels(room_id: int = 0) -> Array[int]:
	var reached := {}
	for end_cell in inbound_bag_room_ends():
		var cid := carousel_of(end_cell)
		if cid != 0:
			reached[cid] = true
	var out: Array[int] = []
	var ids := grid.object_ids()
	ids.sort()
	for cid in ids:
		if not reached.has(cid):
			continue
		if room_id != 0 and grid.room_at(grid.get_object(cid)["anchor"]) != room_id:
			continue
		out.append(cid)
	return out


func has_connected_baggage_claim() -> bool:
	return not connected_carousels().is_empty()


## Whether a bag can pass the edge from belt cell `cell` toward `step`.
func joined(cell: Vector2i, step: Vector2i) -> bool:
	var other := cell + step
	if not is_belt(cell) or not is_belt(other):
		return false
	if not scene.links(cell).has(step) or not scene.links(other).has(-step):
		return false
	return _has_port(cell, step) and _has_port(other, -step)


## Where the check-in desk `desk_id` puts its bags: {"cell": the belt cell its
## outlet points into, "step": the step from the desk into it}, or {} when the
## desk is gone, is not a desk, or no belt takes its bags there.
func entry_of(desk_id: int) -> Dictionary:
	var record := grid.get_object(desk_id)
	if record.is_empty() or record["def"] != BeltShaper.DESK:
		return {}
	for port in BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"]):
		var side: Vector2i = port["side"]
		var into: Vector2i = port["cell"] + side
		if not is_belt(into) or not scene.open(port["cell"], side):
			continue
		if scene.links(into).has(-side) and _has_port(into, -side):
			return {"cell": into, "step": side}
	return {}


func _has_port(cell: Vector2i, step: Vector2i) -> bool:
	var record := grid.get_object(grid.object_at(cell))
	for port in BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"]):
		if port["cell"] == cell and port["side"] == step:
			return true
	return false


## Belt ends inside a ready bag room, sorted by y, then x. Excludes any
## inbound-component ends connected to a claim_carousel.
func _roots() -> Array[Vector2i]:
	var roots: Array[Vector2i] = []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if record["def"] != BeltShaper.END:
			continue
		var cell: Vector2i = record["anchor"]
		if inbound_component.has(cell):
			continue
		if _ready_bag_rooms.has(grid.room_at(cell)):
			roots.append(cell)
	roots.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return roots


func _index_ready_rooms() -> void:
	if grid == null:
		return
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		var rtype := StringName(room["type"])
		if rtype == BeltShaper.BAG_ROOM and RoomRules.status(grid, room_id).ok:
			_ready_bag_rooms[room_id] = true


func _build_inbound() -> void:
	if grid == null:
		return
	var ready_claims := {}
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		if StringName(room["type"]) == BeltShaper.BAGGAGE_CLAIM:
			if RoomRules.status(grid, room_id).ok:
				ready_claims[room_id] = room["rect"]
	var comp_seeds: Array[Vector2i] = []
	var inbound_roots: Array[Vector2i] = []
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := grid.get_object(object_id)
		if StringName(record["def"]) != BeltShaper.CLAIM_CAROUSEL:
			continue
		var entry := carousel_entry_of(object_id)
		if not entry.is_empty():
			var into: Vector2i = entry["cell"]
			if not inbound_component.has(into):
				inbound_component[into] = true
				comp_seeds.append(into)
		var room_id := grid.room_at(record["anchor"])
		if (
			ready_claims.has(room_id)
			and RoomRules.piece_inside(grid, object_id, ready_claims[room_id])
		):
			_ready_carousels[object_id] = true
			if not entry.is_empty():
				var into: Vector2i = entry["cell"]
				if not _carousel_by_inlet.has(into):
					_carousel_by_inlet[into] = object_id
					inbound_roots.append(into)
	var chead := 0
	while chead < comp_seeds.size():
		var cur := comp_seeds[chead]
		chead += 1
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if inbound_component.has(nxt) or not joined(cur, step):
				continue
			inbound_component[nxt] = true
			comp_seeds.append(nxt)
	inbound_roots.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	for root in inbound_roots:
		inbound_dist[root] = 0
	var head := 0
	while head < inbound_roots.size():
		var at := inbound_roots[head]
		head += 1
		for step in BuildGrid.SIDE_STEP:
			var from: Vector2i = at + step
			if inbound_dist.has(from) or not joined(at, step):
				continue
			inbound_dist[from] = inbound_dist[at] + 1
			inbound_next[from] = -step
			inbound_roots.append(from)
