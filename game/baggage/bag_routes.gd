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
## Cell -> cells left to a root (0 on a root).
var dist := {}
## Cell -> the step toward the root; none on a root.
var next := {}


static func build(on: BuildGrid) -> BagRoutes:
	var routes := BagRoutes.new()
	routes.grid = on
	routes.scene = BeltShaper.Scene.new(on)
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


## Belt ends inside a ready bag room, sorted by y, then x.
func _roots() -> Array[Vector2i]:
	var ready := {}
	for room_id in grid.room_ids():
		if grid.get_room(room_id)["type"] == BeltShaper.BAG_ROOM:
			ready[room_id] = RoomRules.status(grid, room_id).ok
	var roots: Array[Vector2i] = []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if record["def"] != BeltShaper.END:
			continue
		var cell: Vector2i = record["anchor"]
		if ready.get(grid.room_at(cell), false):
			roots.append(cell)
	roots.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return roots
