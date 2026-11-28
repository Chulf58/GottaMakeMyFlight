class_name DoorPlacement
extends RefCounted
## The build tools' rules for entrance and exit door objects. BuildGrid allows
## a door object anywhere; these rules keep one on the terminal's edge with
## its way out open, pick its facing when the player has not turned it, and
## let it take the place of a plain wall. BuildMode calls them for the ghost
## and the click alike.

## How far from a cell's edge a point still counts as on that edge's wall line:
## half the wall's thickness, so a click on the wall's drawn width is on it.
const LINE_SLACK_M := BuildView.WALL_THICKNESS * 0.5


## The cell a piece placed at `point` takes: the cell under it, unless that has
## no floor and the point is on the wall line it shares with a neighbour that
## has, when it is that neighbour. floor() puts a point exactly on a cell's west
## or north edge in that cell, so without this the east and south wall lines of
## a room would pick the cell outside it and the north and west lines the cell
## inside.
static func cell_under(grid: BuildGrid, point: Vector3) -> Vector2i:
	var cell := grid.world_to_cell(point)
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return cell
	var offset := point - grid.cell_to_world(cell)
	var best := cell
	var best_gap := LINE_SLACK_M
	for step in BuildGrid.SIDE_STEP:
		var gap := 0.5 - (offset.x * step.x + offset.z * step.y)
		if gap <= best_gap and grid.floor_at(cell + step) != BuildGrid.FLOOR_NONE:
			best = cell + step
			best_gap = gap
	return best


## The wall edge under `point` as Vector3i(x, y, side), snapping from a just-
## out-of-bounds point (e.g. clicking the outer face of a border wall) back onto
## the in-bounds cell edge within LINE_SLACK_M.
static func wall_edge_at(grid: BuildGrid, point: Vector3) -> Vector3i:
	var cell := grid.world_to_cell(point)
	var side: int = grid.nearest_side(point)
	if grid.in_bounds(cell):
		return Vector3i(cell.x, cell.y, side)
	var offset := point - grid.cell_to_world(cell)
	var best_cell := cell
	var best_side := side
	var best_gap := LINE_SLACK_M
	for i in BuildGrid.SIDE_STEP.size():
		var step: Vector2i = BuildGrid.SIDE_STEP[i]
		var adj := cell + step
		var gap := 0.5 - (offset.x * step.x + offset.z * step.y)
		if gap <= best_gap and grid.in_bounds(adj):
			best_cell = adj
			best_side = (i + 2) % 4
			best_gap = gap
	return Vector3i(best_cell.x, best_cell.y, best_side)


## The grid step from a door's cell out through its back edge.
static func back_step(facing: int) -> Vector2i:
	return BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)


## BuildGrid.validate(), plus the edge rule for entrances and exits: a new one
## stands on the terminal's edge facing in (outside_door_problem()), and a
## standing one keeps its way out open: no wall of any kind on its back edge
## and no floor on the cell beyond.
static func check(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.validate(edit)
	if not result.ok:
		return _named_front_blocker(grid, edit, result)
	var problem := edge_problem(grid, edit)
	return problem if problem != null else result


## A door whose front cell holds an object is refused with DOOR_FRONT_BLOCKED,
## the blocker's name as the detail (decision door-placement-refusal-names-what-
## blocks-the-spot-in-front). Any other refusal, and any other piece, is `result`.
static func _named_front_blocker(
	grid: BuildGrid, edit: BuildEdit, result: BuildResult
) -> BuildResult:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or not BuildCatalog.is_any_door(edit.def_id):
		return result
	if result.reason != BuildResult.Reason.INTERACTION_BLOCKED or result.blocking_object_id == 0:
		return result
	var blocker := BuildCatalog.get_def(grid.get_object(result.blocking_object_id).get("def", &""))
	if blocker == null or blocker.display_name == "":
		return result
	var named := BuildResult.refused(
		BuildResult.Reason.DOOR_FRONT_BLOCKED, result.blocking_object_id
	)
	named.detail = blocker.display_name.to_lower()
	return named


## check()'s rules beyond BuildGrid.validate(): the refusal, or null when the
## edit keeps every entrance and exit on the edge with its way out open.
static func edge_problem(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			if BuildCatalog.is_door(edit.def_id):
				var outside := outside_door_problem(grid, edit.cell, edit.facing)
				return null if outside.ok else outside
			if BuildCatalog.is_airside_exit(edit.def_id):
				var inside := interior_door_problem(grid, edit.cell, edit.facing)
				return null if inside.ok else inside
			if BuildCatalog.is_bay_door(edit.def_id):
				var bay := bay_door_problem(grid, edit.cell, edit.facing)
				return null if bay.ok else bay
			var def := BuildCatalog.get_def(edit.def_id)
			if def != null:
				for cell in def.footprint(edit.cell, edit.facing):
					if beyond_a_bay_door(grid, cell):
						return BuildResult.refused(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)
			return null
		BuildEdit.Kind.PLACE_WALL:
			if (
				on_a_way_out(grid, edit.cell, edit.side)
				or _on_bay_approach_wall(grid, edit.cell, edit.side)
			):
				return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
		BuildEdit.Kind.PAINT_FLOOR:
			if beyond_a_door(grid, edit.cell):
				return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
			if beyond_a_bay_door(grid, edit.cell):
				return BuildResult.refused(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)
	return null


## Whether an airside exit door at `anchor` and `facing` stands on interior
## floor with floor beyond its back edge and no glass or door wall blocking it.
static func interior_door_problem(grid: BuildGrid, anchor: Vector2i, facing: int) -> BuildResult:
	var out := back_step(facing)
	var back := anchor + out
	if not grid.in_bounds(back) or grid.floor_at(back) == BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.AIRSIDE_EXIT_NEEDS_FLOOR)
	var side := BuildGrid.SIDE_STEP.find(out)
	match grid.wall_kind(anchor, side):
		BuildGrid.WallKind.NONE:
			return BuildResult.accepted()
		BuildGrid.WallKind.PLAIN:
			return grid.validate(BuildEdit.remove_wall(anchor, side))
	return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)


## Whether an entrance or exit door object at `anchor` and `facing` stands on
## the terminal's edge: its back edge (the way out) has no floor beyond it and
## no wall on it, the same test TerminalLayout.is_exit_open() makes. A plain
## wall there is allowed when the wall could be removed on its own (it holds
## no door wall), because placing the door takes it down (edits_for()).
## Glass and door walls still refuse.
static func outside_door_problem(grid: BuildGrid, anchor: Vector2i, facing: int) -> BuildResult:
	var out := back_step(facing)
	if grid.floor_at(anchor + out) != BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	var side := BuildGrid.SIDE_STEP.find(out)
	match grid.wall_kind(anchor, side):
		BuildGrid.WallKind.NONE:
			return BuildResult.accepted()
		BuildGrid.WallKind.PLAIN:
			return grid.validate(BuildEdit.remove_wall(anchor, side))
	return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)


## Placement check for a 2x1 Roll-Up Bay Door: both footprint cells must sit on an
## exterior terminal wall facing open, unobstructed apron (never landside road or an
## interior courtyard) with NONE or PLAIN walls along both back edges.
static func bay_door_problem(grid: BuildGrid, anchor: Vector2i, facing: int) -> BuildResult:
	if grid == null:
		return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
	if facing < 0 or facing > 3:
		return BuildResult.refused(BuildResult.Reason.BAD_FACING)
	var out := back_step(facing)
	if out == SiteDefinition.ROAD_STEP:
		return BuildResult.refused(BuildResult.Reason.BAY_DOOR_NEEDS_APRON)
	var cells := bay_door_cells(anchor, facing)
	var approach: Array[Vector2i] = []
	for cell in cells:
		var outside: Vector2i = cell + out
		if not grid.in_bounds(outside):
			return BuildResult.refused(BuildResult.Reason.BAY_DOOR_NEEDS_APRON)
		if grid.floor_at(outside) != BuildGrid.FLOOR_NONE:
			return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
		if not is_apron_cell_open(grid, outside) or beyond_a_bay_door(grid, outside):
			return BuildResult.refused(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)
		approach.append(outside)
	if _has_bay_approach_wall(grid, anchor, facing):
		return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
	if not _reaches_open_apron(grid, approach):
		return BuildResult.refused(BuildResult.Reason.BAY_DOOR_NEEDS_APRON)
	var side := BuildGrid.SIDE_STEP.find(out)
	for cell in cells:
		match grid.wall_kind(cell, side):
			BuildGrid.WallKind.NONE:
				continue
			BuildGrid.WallKind.PLAIN:
				var wall_check := grid.validate(BuildEdit.remove_wall(cell, side))
				if not wall_check.ok:
					return wall_check
			_:
				return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
	return BuildResult.accepted()


## Whether both exterior apron approach cells of a bay door at `anchor`/`facing`
## exist in bounds, have no floor or blocking object/obstacle, do not face landside,
## and connect to open apron.
static func is_bay_door_apron_clear(grid: BuildGrid, anchor: Vector2i, facing: int) -> bool:
	if grid == null or facing < 0 or facing > 3:
		return false
	var out := back_step(facing)
	if out == SiteDefinition.ROAD_STEP:
		return false
	if _has_bay_approach_wall(grid, anchor, facing):
		return false
	var approach: Array[Vector2i] = []
	for cell in bay_door_cells(anchor, facing):
		var outside: Vector2i = cell + out
		if not is_apron_cell_open(grid, outside):
			return false
		approach.append(outside)
	return _reaches_open_apron(grid, approach)


## Whether an exterior cell is open apron ground with no floor, object, or site obstacle.
static func is_apron_cell_open(grid: BuildGrid, cell: Vector2i) -> bool:
	if not grid.in_bounds(cell):
		return false
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return false
	if grid.object_at(cell) != 0:
		return false
	if grid is SiteGrid and (grid as SiteGrid).site.is_obstacle(cell):
		return false
	return true


## Bounded flood-fill over exterior FLOOR_NONE cells starting from `starts` to
## ensure every bay approach cell reaches open north/airside apron rather than a
## sealed courtyard or isolated pocket.
static func _reaches_open_apron(grid: BuildGrid, starts: Array[Vector2i]) -> bool:
	if starts.is_empty():
		return false
	var bounds := grid.flood_area()
	if bounds.size == Vector2i.ZERO:
		bounds = Rect2i(Vector2i.ZERO, grid.size)
	for s in starts:
		if not bounds.has_point(s):
			return false
	for s in starts:
		if not _cell_reaches_open_apron(grid, bounds, s):
			return false
	return true


static func _cell_reaches_open_apron(grid: BuildGrid, bounds: Rect2i, start: Vector2i) -> bool:
	if start.y == bounds.position.y:
		return true
	var w := bounds.size.x
	var h := bounds.size.y
	var ox := bounds.position.x
	var oy := bounds.position.y
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen[(start.y - oy) * w + (start.x - ox)] = 1
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur.y == oy:
			return true
		for side in 4:
			var nxt: Vector2i = cur + BuildGrid.SIDE_STEP[side]
			if not bounds.has_point(nxt):
				continue
			if _edge_has_wall(grid, cur, nxt):
				continue
			var nidx := (nxt.y - oy) * w + (nxt.x - ox)
			if seen[nidx] != 0:
				continue
			if not is_apron_cell_open(grid, nxt):
				continue
			seen[nidx] = 1
			queue.append(nxt)
	return false


## Footprint cells (2 along the wall edge) of a Roll-Up Bay Door at `anchor`/`facing`.
static func bay_door_cells(anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var def := BuildCatalog.get_def(BuildCatalog.BAY_DOOR_ID)
	if def == null:
		return [anchor]
	return def.footprint(anchor, facing)


## Back wall [cell, side] pairs owned by a door (`1` pair) or bay door (`2` pairs).
static func door_edges(def_id: StringName, anchor: Vector2i, facing: int) -> Array:
	var out := back_step(facing)
	var side := BuildGrid.SIDE_STEP.find(out)
	if not BuildCatalog.is_bay_door(def_id):
		return [[anchor, side]]
	var edges := []
	for cell in bay_door_cells(anchor, facing):
		edges.append([cell, side])
	return edges


## The facing a `def_id` door at the cell under `point` takes when the player
## has not turned it. It prefers a facing check() accepts, then one whose back
## has no floor beyond it; among equals, the one whose back edge is nearest
## `point`. With neither, it returns `fallback`, so the refusal says the cell
## is not on the edge.
static func auto_facing(grid: BuildGrid, def_id: StringName, point: Vector3, fallback: int) -> int:
	var cell := cell_under(grid, point)
	var offset := point - grid.cell_to_world(cell)
	var best := fallback
	var best_tier := 2
	var best_distance := INF
	var interior := BuildCatalog.is_airside_exit(def_id)
	var bay := BuildCatalog.is_bay_door(def_id)
	var def := BuildCatalog.get_def(def_id) if bay else null
	for turn in 4:
		var out := back_step(turn)
		var anchor := cell
		if bay and def != null:
			var c_off := BuildObjectDef.rotate_point(
				Vector2((def.size.x - 1) * 0.5, (def.size.y - 1) * 0.5), turn
			)
			anchor = cell_under(grid, point - Vector3(c_off.x, 0.0, c_off.y))
		var tier := 2
		if check(grid, BuildEdit.place_object(def_id, anchor, turn)).ok:
			tier = 0
		elif bay:
			if out != SiteDefinition.ROAD_STEP and is_bay_door_apron_clear(grid, anchor, turn):
				tier = 1
		elif (
			grid.in_bounds(anchor + out) and grid.floor_at(anchor + out) != BuildGrid.FLOOR_NONE
			if interior
			else grid.floor_at(anchor + out) == BuildGrid.FLOOR_NONE
		):
			tier = 1
		var distance := 0.5 - (offset.x * out.x + offset.z * out.y)
		if tier < best_tier or (tier == best_tier and tier < 2 and distance < best_distance):
			best = turn
			best_tier = tier
			best_distance = distance
	return best


## The edits that carry out an edit check() accepted, in order. An entrance, exit,
## or bay door with plain wall(s) on its back edge(s) first removes those walls, which
## cannot make the door's own placement invalid. Removing one puts the plain walls back
## (decision removing-an-exit-or-entrance-door-puts-the-plain-wall-back), so the
## terminal stays enclosed; the wall is bought at its price, like any other. Any
## other edit is itself.
static func edits_for(grid: BuildGrid, edit: BuildEdit) -> Array[BuildEdit]:
	var plan: Array[BuildEdit] = [edit]
	if edit.kind == BuildEdit.Kind.REMOVE_OBJECT:
		var record := grid.get_object(edit.object_id)
		if not record.is_empty() and BuildCatalog.is_any_door(record["def"]):
			for edge: Array in door_edges(record["def"], record["anchor"], record["facing"]):
				if grid.wall_kind(edge[0], edge[1]) == BuildGrid.WallKind.NONE:
					plan.append(BuildEdit.place_wall(edge[0], edge[1]))
		return plan
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or not BuildCatalog.is_any_door(edit.def_id):
		return plan
	var remove_walls: Array[BuildEdit] = []
	for edge: Array in door_edges(edit.def_id, edit.cell, edit.facing):
		if grid.wall_kind(edge[0], edge[1]) == BuildGrid.WallKind.PLAIN:
			remove_walls.append(BuildEdit.remove_wall(edge[0], edge[1]))
	for i in range(remove_walls.size() - 1, -1, -1):
		plan.push_front(remove_walls[i])
	return plan


## Each standing passenger entrance or exit as [anchor, outward step].
## Excludes Roll-Up Bay Doors so passengers never route out through a bag bay.
static func ways_out(grid: BuildGrid) -> Array:
	var out := []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if BuildCatalog.is_door(record["def"]):
			out.append([record["anchor"], back_step(record["facing"])])
	return out


## Each standing exterior door cell that replaces walls to close the terminal
## enclosure ([cell, outward step]): passenger doors plus both cells of bay doors.
static func enclosure_ways(grid: BuildGrid) -> Array:
	var out := ways_out(grid)
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if BuildCatalog.is_bay_door(record["def"]):
			var step := back_step(record["facing"])
			for cell in bay_door_cells(record["anchor"], record["facing"]):
				out.append([cell, step])
	return out


## Whether the edge (from either cell beside it) is any door object's back edge.
static func on_a_way_out(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	var step := BuildGrid.SIDE_STEP[side]
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if not BuildCatalog.is_any_door(record["def"]):
			continue
		for edge: Array in door_edges(record["def"], record["anchor"], record["facing"]):
			var way_cell: Vector2i = edge[0]
			var way_step := BuildGrid.SIDE_STEP[int(edge[1])]
			if (
				(cell == way_cell and step == way_step)
				or (cell == way_cell + way_step and step == -way_step)
			):
				return true
	return false


static func _bay_approach_edges(anchor: Vector2i, facing: int) -> Array:
	var out := back_step(facing)
	var cells := bay_door_cells(anchor, facing)
	var ap0: Vector2i = cells[0] + out
	var ap1: Vector2i = cells[1] + out
	return [[ap0, ap1], [ap0, ap0 + out], [ap1, ap1 + out]]


static func _edge_has_wall(grid: BuildGrid, a: Vector2i, b: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(b - a)
	if side < 0:
		return false
	if grid.in_bounds(a) and grid.wall_kind(a, side) != BuildGrid.WallKind.NONE:
		return true
	var opp := (side + 2) % 4
	return grid.in_bounds(b) and grid.wall_kind(b, opp) != BuildGrid.WallKind.NONE


static func _has_bay_approach_wall(grid: BuildGrid, anchor: Vector2i, facing: int) -> bool:
	for edge: Array in _bay_approach_edges(anchor, facing):
		if _edge_has_wall(grid, edge[0], edge[1]):
			return true
	return false


static func _on_bay_approach_wall(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	var a := cell
	var b := cell + BuildGrid.SIDE_STEP[side]
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if not BuildCatalog.is_bay_door(record["def"]):
			continue
		for edge: Array in _bay_approach_edges(record["anchor"], record["facing"]):
			if (a == edge[0] and b == edge[1]) or (a == edge[1] and b == edge[0]):
				return true
	return false


## Whether `cell` is the cell beyond a standing passenger door's back edge.
static func beyond_a_door(grid: BuildGrid, cell: Vector2i) -> bool:
	for way in ways_out(grid):
		if cell == way[0] + way[1]:
			return true
	return false


## Whether `cell` is one of the 2 exterior apron approach cells outside a standing bay door.
static func beyond_a_bay_door(grid: BuildGrid, cell: Vector2i) -> bool:
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if not BuildCatalog.is_bay_door(record["def"]):
			continue
		var out := back_step(record["facing"])
		for bay_cell in bay_door_cells(record["anchor"], record["facing"]):
			if cell == bay_cell + out:
				return true
	return false
