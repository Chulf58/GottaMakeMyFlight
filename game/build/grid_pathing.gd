class_name GridPathing
extends RefCounted
## The passenger A* graph over a BuildGrid. One AStar2D point per cell, at
## the cell's grid coordinates, so diagonal links cost sqrt(2). A link exists
## exactly when BuildGrid.can_route() allows the step, so a door wall links
## like an open edge and a plain or glass wall does not; an AStarGrid2D cannot
## hold that, because walls sit on cell edges and a door blocks its sides.
## Security scanners are never linked: only the passenger a scanner serves
## walks through it, along BuildGrid.passage_cells(), so generic routing can
## never cross security. After an edit only the links around the dirty cells
## are rebuilt.
##
## Passengers walk only indoor cells (BuildGrid.is_indoor()): every other
## cell's point is disabled, so a path is made of BuildGrid.can_passenger_route()
## steps. One removed wall can turn a whole hall outdoor; set_outside() then
## switches those points off without relinking them.
##
## A staff graph (`staff` set) links every BuildGrid.can_staff_route() step
## instead, through security objects along their axis (decision
## staff-may-walk-through-security-scanners-and-lanes-so-shop-s) and across
## baggage belt cells weighted by BELT_COST_SCALE (decision
## staff-step-over-belts-high-cost-fallback-with-step-up-lift, 76c5cc1a),
## keeping every point on: staff access is physical.
##
## A passenger graph disconnects WallKind.DOOR edges that separate landside
## (components holding an entrance or reachable from one over doors without
## crossing an airside anchor) from the secure airside zone (gate seats, exits
## or scanner exits in a different component from their entry), so unscreened
## passengers cannot cross divider doors into airside while same-side doors
## and open-plan terminals stay open (ruling 7c2e1a32).

## Point weight scale applied to baggage belt cells on the staff graph so staff
## strongly prefer open aisles and step over belts only as a fallback.
const BELT_COST_SCALE := 8.0
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

## Links staff steps rather than passenger ones.
var staff := false

var _astar := AStar2D.new()
var _width := 0


func _init(for_staff := false) -> void:
	staff = for_staff


## Canonical integer key for the shared edge between orthogonal neighbours.
static func door_edge_key(grid_width: int, a: Vector2i, b: Vector2i) -> int:
	var cell := a if a.x > b.x or a.y > b.y else b
	var horizontal := a.x == b.x
	return (cell.y * (grid_width + 1) + cell.x) * 2 + (0 if horizontal else 1)


## Canonical keys of WallKind.DOOR edges that separate landside from airside.
static func divider_doors(grid: BuildGrid) -> Dictionary:
	if not grid.has_any_door_wall():
		return {}
	var anchors := _anchors(grid)
	var entrances: Array[Vector2i] = anchors["entrances"]
	if entrances.is_empty():
		return {}
	var built := _doorless_components(grid)
	var comp: PackedInt32Array = built["comp"]
	var doors: Array = built["doors"]
	if doors.is_empty():
		return {}
	var w := grid.size.x
	var land_seeds := {}
	for cell in entrances:
		var c: int = comp[cell.y * w + cell.x]
		if c >= 0:
			land_seeds[c] = true
	if land_seeds.is_empty():
		return {}
	var air_anchors := _air_anchors(grid, comp, land_seeds, anchors)
	if air_anchors.is_empty():
		return {}
	var landside := _landside_components(doors, land_seeds, air_anchors)
	var blocked := {}
	for d: Array in doors:
		if landside.has(d[0]) != landside.has(d[1]):
			blocked[d[2]] = true
	return blocked


func rebuild(grid: BuildGrid) -> void:
	if not staff:
		grid.ensure_divider_doors()
		grid.sync_divider_doors()
	_astar.clear()
	_width = grid.size.x
	_astar.reserve_space(grid.size.x * grid.size.y)
	for y in grid.size.y:
		for x in grid.size.x:
			_astar.add_point(_id(Vector2i(x, y)), Vector2(x, y))
	for y in grid.size.y:
		for x in grid.size.x:
			_relink(grid, Vector2i(x, y))


## Every in-bounds cell within one step of a dirty cell, each once. A
## diagonal link depends on the 2x2 block it crosses, and every such block
## touching a dirty cell lies inside that cell's 3x3 neighbourhood. These are
## the cells update() relinks, and so the cells whose links may have changed.
static func neighbourhood(grid: BuildGrid, dirty_cells: Array[Vector2i]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	for cell in dirty_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := cell + Vector2i(dx, dy)
				if grid.in_bounds(near) and not seen.has(near):
					seen[near] = true
					cells.append(near)
	return cells


## Relinks the neighbourhood of the dirty cells and returns it.
func update(grid: BuildGrid, dirty_cells: Array[Vector2i]) -> Array[Vector2i]:
	var cells := neighbourhood(grid, dirty_cells)
	for cell in cells:
		_relink(grid, cell)
	return cells


## Switches the points of floored cells whose indoor state changed with no
## edit on them, given as cell indices (x + y * width, the point ids), off
## where `outside` (TerminalEnclosure.outside_cells()) is 1 and on where it is
## 0. Links stay as they are. Nothing for a staff graph.
func set_outside(indices: PackedInt32Array, outside: PackedByteArray) -> void:
	if staff:
		return
	for i in indices:
		_astar.set_point_disabled(i, outside[i] != 0)


## Cells from `from` to `to`, both included, or an empty array when either
## cell is not walkable (for passengers, not a BuildGrid.is_passenger_cell())
## or no route exists.
func find_path(grid: BuildGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _may_stand(grid, from) or not _may_stand(grid, to):
		return cells
	for id in _astar.get_id_path(_id(from), _id(to)):
		@warning_ignore("integer_division")
		cells.append(Vector2i(id % _width, id / _width))
	return cells


## find_path() with the cells of `shut` off for this one query: a route that
## never steps onto one, though `from` and `to` may be among them; empty when
## there is none. Each shut point that was on is switched off, the path is
## found, and exactly those points are switched on again, so a point already
## off (not indoor, set_outside()) stays off.
func find_path_around(
	grid: BuildGrid, from: Vector2i, to: Vector2i, shut: Array
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _may_stand(grid, from) or not _may_stand(grid, to):
		return cells
	var off := PackedInt32Array()
	for cell: Vector2i in shut:
		if cell == from or cell == to or not grid.in_bounds(cell):
			continue
		var id := _id(cell)
		if not _astar.is_point_disabled(id):
			_astar.set_point_disabled(id, true)
			off.append(id)
	var ids := _astar.get_id_path(_id(from), _id(to))
	for id in off:
		_astar.set_point_disabled(id, false)
	for id in ids:
		@warning_ignore("integer_division")
		cells.append(Vector2i(id % _width, id / _width))
	return cells


## find_path() with stepping onto each cell of `costly` costing `scale` times
## as much, for this one query; `from` and `to` are never costed. Each costed
## point's weight is set back to 1.0 after the path is found (no other code
## sets a weight), so every other query sees the graph as it was. A gate chair
## guest walks round the other chair fronts so (GateRowWalk.path()).
func find_path_costed(
	grid: BuildGrid, from: Vector2i, to: Vector2i, costly: Array, scale: float
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _may_stand(grid, from) or not _may_stand(grid, to):
		return cells
	var weighted := PackedInt32Array()
	for cell: Vector2i in costly:
		if cell == from or cell == to or not grid.in_bounds(cell):
			continue
		var id := _id(cell)
		_astar.set_point_weight_scale(id, scale)
		weighted.append(id)
	var ids := _astar.get_id_path(_id(from), _id(to))
	for id in weighted:
		_astar.set_point_weight_scale(id, 1.0)
	for id in ids:
		@warning_ignore("integer_division")
		cells.append(Vector2i(id % _width, id / _width))
	return cells


func _relink(grid: BuildGrid, cell: Vector2i) -> void:
	var id := _id(cell)
	if staff:
		_astar.set_point_weight_scale(id, BELT_COST_SCALE if grid.is_belt_cell(cell) else 1.0)
	else:
		_astar.set_point_disabled(id, not grid.is_indoor(cell))
	for offset in NEIGHBOURS:
		var other := cell + offset
		if not grid.in_bounds(other):
			continue
		var other_id := _id(other)
		var linked := _astar.are_points_connected(id, other_id)
		var open := (
			grid.can_staff_route(cell, other)
			if staff
			else grid.can_route(cell, other) and not grid.crosses_divider_door(cell, other)
		)
		if open and not linked:
			_astar.connect_points(id, other_id)
		elif linked and not open:
			_astar.disconnect_points(id, other_id)


func _may_stand(grid: BuildGrid, cell: Vector2i) -> bool:
	return grid.is_staff_walkable(cell) if staff else grid.is_passenger_cell(cell)


func _id(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


static func _anchors(grid: BuildGrid) -> Dictionary:
	var entrances: Array[Vector2i] = []
	var air: Array[Vector2i] = []
	var scanners: Array = []
	for id in grid.object_ids():
		var record := grid.get_object(id)
		var def_id := StringName(record["def"])
		match def_id:
			&"entrance_door":
				entrances.append(record["anchor"])
			&"exit_door":
				air.append(record["anchor"])
			&"seat_row", &"bench_1a":
				var def := BuildCatalog.get_def(def_id)
				var facing: int = record["facing"]
				var cells := def.footprint(record["anchor"], facing)
				var front_step := TerminalLayout.seat_front_of(def_id, facing)
				for i in cells.size():
					if GateChairs.has_chair(def_id, i):
						var front := cells[i] + front_step
						if grid.is_passenger_cell(front):
							air.append(front)
			&"security_scanner":
				var passage := grid.passage_cells(id)
				if not passage.is_empty() and _all_passenger_cells(grid, passage):
					scanners.append([grid.interaction_cell(id), passage.back()])
			&"security_arch":
				var lanes := grid.recognised_lanes()
				if lanes.is_complete(id):
					var lane := lanes.lane(id)
					if _all_passenger_cells(grid, lane["passage"]):
						scanners.append([grid.interaction_cell(id), lane["exit"]])
	return {"entrances": entrances, "air": air, "scanners": scanners}


static func _all_passenger_cells(grid: BuildGrid, cells: Array) -> bool:
	for cell: Vector2i in cells:
		if not grid.is_passenger_cell(cell):
			return false
	return true


static func _doorless_components(grid: BuildGrid) -> Dictionary:
	var area := grid.flood_area()
	if area.size.x <= 0 or area.size.y <= 0:
		return {"comp": PackedInt32Array(), "doors": []}
	var w := grid.size.x
	var comp := PackedInt32Array()
	comp.resize(w * grid.size.y)
	comp.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(area.size.x * area.size.y)
	var x0 := area.position.x
	var y0 := area.position.y
	var x1 := area.end.x
	var y1 := area.end.y
	var next_id := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var idx := y * w + x
			if comp[idx] >= 0 or not grid.is_passenger_cell(Vector2i(x, y)):
				continue
			comp[idx] = next_id
			var head := 0
			var tail := 1
			queue[0] = idx
			while head < tail:
				var c_idx := queue[head]
				head += 1
				@warning_ignore("integer_division")
				var cy := c_idx / w
				var cx := c_idx - cy * w
				var cell := Vector2i(cx, cy)
				for step in NEIGHBOURS:
					var ox := cx + step.x
					var oy := cy + step.y
					if ox < x0 or oy < y0 or ox >= x1 or oy >= y1:
						continue
					var o_idx := oy * w + ox
					if comp[o_idx] >= 0:
						continue
					var other := Vector2i(ox, oy)
					if not grid.is_passenger_cell(other):
						continue
					if not grid.can_route(cell, other) or crosses_door_edge(grid, cell, other):
						continue
					comp[o_idx] = next_id
					queue[tail] = o_idx
					tail += 1
			next_id += 1
	var doors: Array = []
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell := Vector2i(x, y)
			var ca := comp[y * w + x]
			if ca < 0:
				continue
			if y > y0 and grid.wall_kind(cell, BuildGrid.Side.NORTH) == BuildGrid.WallKind.DOOR:
				var north := Vector2i(x, y - 1)
				var cb := comp[(y - 1) * w + x]
				if cb >= 0 and ca != cb and grid.can_route(cell, north):
					doors.append([ca, cb, door_edge_key(w, cell, north)])
			if x > x0 and grid.wall_kind(cell, BuildGrid.Side.WEST) == BuildGrid.WallKind.DOOR:
				var west := Vector2i(x - 1, y)
				var cb := comp[y * w + x - 1]
				if cb >= 0 and ca != cb and grid.can_route(cell, west):
					doors.append([ca, cb, door_edge_key(w, cell, west)])
	return {"comp": comp, "doors": doors}


static func _air_anchors(
	grid: BuildGrid, comp: PackedInt32Array, land_seeds: Dictionary, anchors: Dictionary
) -> Dictionary:
	var w := grid.size.x
	var air_anchors := {}
	for cell: Vector2i in anchors["air"]:
		if not grid.in_bounds(cell):
			continue
		var c: int = comp[cell.y * w + cell.x]
		if c >= 0 and not land_seeds.has(c):
			air_anchors[c] = true
	for pair: Array in anchors["scanners"]:
		var entry: Vector2i = pair[0]
		var exit_cell: Vector2i = pair[1]
		if not grid.in_bounds(entry) or not grid.in_bounds(exit_cell):
			continue
		var ec: int = comp[entry.y * w + entry.x]
		var xc: int = comp[exit_cell.y * w + exit_cell.x]
		if ec >= 0 and xc >= 0 and ec != xc and not land_seeds.has(xc):
			air_anchors[xc] = true
	return air_anchors


static func _landside_components(
	doors: Array, land_seeds: Dictionary, air_anchors: Dictionary
) -> Dictionary:
	var adj := {}
	for d: Array in doors:
		var ca: int = d[0]
		var cb: int = d[1]
		if not adj.has(ca):
			adj[ca] = []
		if not adj.has(cb):
			adj[cb] = []
		(adj[ca] as Array).append(cb)
		(adj[cb] as Array).append(ca)
	var landside := land_seeds.duplicate()
	var frontier: Array[int] = []
	for c: int in land_seeds:
		frontier.append(c)
	var head := 0
	while head < frontier.size():
		var c := frontier[head]
		head += 1
		for nxt: int in adj.get(c, []):
			if not landside.has(nxt) and not air_anchors.has(nxt):
				landside[nxt] = true
				frontier.append(nxt)
	return landside


static func crosses_door_edge(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	var step := to - from
	if step.x == 0 or step.y == 0:
		return _is_door(grid, from, to)
	var across := from + Vector2i(step.x, 0)
	var down := from + Vector2i(0, step.y)
	return (
		_is_door(grid, from, across)
		or _is_door(grid, across, to)
		or _is_door(grid, from, down)
		or _is_door(grid, down, to)
	)


static func _is_door(grid: BuildGrid, a: Vector2i, b: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(b - a)
	return side >= 0 and grid.wall_kind(a, side) == BuildGrid.WallKind.DOOR
