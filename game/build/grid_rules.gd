class_name GridRules
extends RefCounted
## The placement rules of a BuildGrid: what each kind of edit needs of the
## cells it touches. Static helpers split out of build_grid.gd (decision
## how-to-split-a-big-gdscript-file-static-helper-classes-that); the grid is
## the first argument. BuildGrid.validate() calls check(), then applies the
## staff spot, officer spot and reach rules.


## The placement rule for `edit` on `grid` as it stands: accepted, or refused
## with the reason. Null when no rule names the edit's kind.
static func check(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result: BuildResult
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			result = _check_paint_floor(grid, edit)
		BuildEdit.Kind.REMOVE_FLOOR:
			result = _check_remove_floor(grid, edit.cell)
		BuildEdit.Kind.PLACE_WALL:
			result = _check_place_wall(grid, edit.cell, edit.side, edit.wall_kind)
		BuildEdit.Kind.REMOVE_WALL:
			result = _check_remove_wall(grid, edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			if _restored_id_taken(edit.object_id, grid._objects, grid._next_object_id):
				result = BuildResult.refused(BuildResult.Reason.OVERLAP, edit.object_id)
			else:
				result = check_place_object(grid, edit.def_id, edit.cell, edit.facing)
		BuildEdit.Kind.REMOVE_OBJECT:
			if grid._objects.has(edit.object_id):
				result = BuildResult.accepted()
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_OBJECT)
		BuildEdit.Kind.PLACE_ROOM:
			if _restored_id_taken(edit.room_id, grid._rooms, grid._next_room_id):
				result = BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
			else:
				result = check_place_room(grid, Rect2i(edit.cell, edit.room_size), edit.room_type)
		BuildEdit.Kind.REMOVE_ROOM:
			if grid._rooms.has(edit.room_id):
				result = BuildResult.accepted()
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_ROOM)
		BuildEdit.Kind.RESIZE_ROOM:
			if grid._rooms.has(edit.room_id):
				var kept: StringName = grid._rooms[edit.room_id]["type"]
				result = check_place_room(
					grid, Rect2i(edit.cell, edit.room_size), kept, edit.room_id
				)
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_ROOM)
		BuildEdit.Kind.RESHAPE_BELT:
			result = _check_reshape_belt(grid, edit)
	return result


## Whether a placement that brings an object or room back under its own id
## (`id` above 0, an undo) cannot have it: the id is in use or was never
## handed out. A placement with id 0 gets a fresh one.
static func _restored_id_taken(id: int, records: Dictionary, next_id: int) -> bool:
	return id != 0 and (id < 0 or id >= next_id or records.has(id))


static func _check_paint_floor(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if not grid.in_bounds(edit.cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if edit.floor_type < 1 or edit.floor_type > BuildGrid.MAX_FLOOR_TYPE:
		return BuildResult.refused(BuildResult.Reason.BAD_FLOOR_TYPE)
	if edit.zone_id < 0:
		return BuildResult.refused(BuildResult.Reason.BAD_ZONE)
	return BuildResult.accepted()


static func _check_remove_floor(grid: BuildGrid, cell: Vector2i) -> BuildResult:
	if not grid.in_bounds(cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var i := grid._index(cell)
	if grid._floor[i] == BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
	if grid._occupant[i] != 0:
		return BuildResult.refused(BuildResult.Reason.OCCUPIED, grid._occupant[i])
	if grid._reserved[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, grid._reserved[i])
	if grid._room_at[i] != 0:
		return BuildResult.refused(BuildResult.Reason.IN_ROOM)
	return BuildResult.accepted()


## A room needs a known type and a non-empty rectangle of floor cells inside
## the grid that no other room covers (`own_id`, a room being resized, does
## not count as another). Its minimum size is not a placement rule: RoomRules
## shows it as a note, so a tuning change never refuses a save.
static func check_place_room(
	grid: BuildGrid, area: Rect2i, type: StringName, own_id := 0
) -> BuildResult:
	if RoomTypes.get_type(type) == null:
		return BuildResult.refused(BuildResult.Reason.UNKNOWN_ROOM_TYPE)
	var has_cells := area.size.x > 0 and area.size.y > 0
	if (
		not has_cells
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := grid._index(Vector2i(x, y))
			if grid._floor[i] == BuildGrid.FLOOR_NONE:
				return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
			if grid._room_at[i] != 0 and grid._room_at[i] != own_id:
				return BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
	return BuildResult.accepted()


## A wall of `kind` on an empty edge, or in place of a wall of another kind.
## A door needs a plain wall in line on both sides, and a plain wall beside a
## door cannot change while the door stands.
static func _check_place_wall(grid: BuildGrid, cell: Vector2i, side: int, kind: int) -> BuildResult:
	if not grid.in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var problem := _wall_kind_problem(grid, cell, side, kind)
	if problem == null and grid._wall_value(cell, side) == BuildGrid.WallKind.NONE:
		problem = _wall_object_problem(grid, cell, side)
	return problem if problem != null else BuildResult.accepted()


## A refusal when `kind` cannot go on the edge as things stand, or null.
static func _wall_kind_problem(
	grid: BuildGrid, cell: Vector2i, side: int, kind: int
) -> BuildResult:
	if kind < BuildGrid.WallKind.PLAIN or kind > BuildGrid.MAX_WALL_KIND:
		return BuildResult.refused(BuildResult.Reason.BAD_WALL_KIND)
	var existing := grid._wall_value(cell, side)
	if existing == kind:
		return BuildResult.refused(BuildResult.Reason.WALL_EXISTS)
	if kind == BuildGrid.WallKind.DOOR and not _between_plain_walls(grid, cell, side):
		return BuildResult.refused(BuildResult.Reason.DOOR_NEEDS_WALLS)
	if existing == BuildGrid.WallKind.PLAIN and _beside_door(grid, cell, side):
		return BuildResult.refused(BuildResult.Reason.WALL_HOLDS_DOOR)
	return null


## A refusal when a new wall on the edge would cut through an object or shut
## an object off from its interaction cell, or null.
static func _wall_object_problem(grid: BuildGrid, cell: Vector2i, side: int) -> BuildResult:
	var other := cell + BuildGrid.SIDE_STEP[side]
	if not grid.in_bounds(other):
		return null
	var here := grid._occupant[grid._index(cell)]
	var there := grid._occupant[grid._index(other)]
	if here != 0 and here == there:
		return BuildResult.refused(BuildResult.Reason.WALL_IN_FOOTPRINT, here)
	for pair in [[here, other], [there, cell]]:
		if pair[0] != 0 and grid._reserved[grid._index(pair[1])] == pair[0]:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, pair[0])
	return null


static func _check_remove_wall(grid: BuildGrid, cell: Vector2i, side: int) -> BuildResult:
	if not grid.in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var existing := grid._wall_value(cell, side)
	if existing == BuildGrid.WallKind.NONE:
		return BuildResult.refused(BuildResult.Reason.NO_WALL)
	if existing == BuildGrid.WallKind.PLAIN and _beside_door(grid, cell, side):
		return BuildResult.refused(BuildResult.Reason.WALL_HOLDS_DOOR)
	return BuildResult.accepted()


## The two edges in line with an edge, one at either end, as [cell, side]
## pairs on the same side. Either may lie outside the grid.
static func _inline_edges(cell: Vector2i, side: int) -> Array:
	var along := (
		Vector2i(1, 0)
		if side == BuildGrid.Side.NORTH or side == BuildGrid.Side.SOUTH
		else Vector2i(0, 1)
	)
	return [[cell - along, side], [cell + along, side]]


static func _between_plain_walls(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	for edge in _inline_edges(cell, side):
		if grid.wall_kind(edge[0], edge[1]) != BuildGrid.WallKind.PLAIN:
			return false
	return true


static func _beside_door(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	for edge in _inline_edges(cell, side):
		if grid.wall_kind(edge[0], edge[1]) == BuildGrid.WallKind.DOOR:
			return true
	return false


## A problem string for the first door edge without a plain wall in line on
## both sides, or "". Visits every edge once: north and west of each cell, the
## south of the last row and the east of the last column.
static func door_walls_problem(grid: BuildGrid) -> String:
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			var sides := [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]
			if y == grid.size.y - 1:
				sides.append(BuildGrid.Side.SOUTH)
			if x == grid.size.x - 1:
				sides.append(BuildGrid.Side.EAST)
			for side in sides:
				var is_door := grid._wall_value(cell, side) == BuildGrid.WallKind.DOOR
				if is_door and not _between_plain_walls(grid, cell, side):
					return "door at %s side %d needs a plain wall on each side" % [cell, side]
	return ""


static func check_place_object(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> BuildResult:
	var def := BuildCatalog.get_def(def_id)
	if def == null:
		return BuildResult.refused(BuildResult.Reason.UNKNOWN_OBJECT)
	if facing < 0 or facing > 3:
		return BuildResult.refused(BuildResult.Reason.BAD_FACING)
	var cells := def.footprint(anchor, facing)
	var problem := _footprint_problem(grid, cells)
	if problem != null:
		return problem
	problem = interaction_problem(grid, def.interaction_cell(anchor, facing), cells)
	if problem != null:
		return problem
	return BuildResult.accepted()


## A refusal for the first footprint cell that cannot take an object, or null.
static func _footprint_problem(grid: BuildGrid, cells: Array[Vector2i]) -> BuildResult:
	for cell in cells:
		if not grid.in_bounds(cell):
			return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for cell in cells:
		var i := grid._index(cell)
		if grid._floor[i] == BuildGrid.FLOOR_NONE:
			return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
		if grid._occupant[i] != 0:
			return BuildResult.refused(BuildResult.Reason.OVERLAP, grid._occupant[i])
		if grid._reserved[i] != 0:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, grid._reserved[i])
		for side in [BuildGrid.Side.EAST, BuildGrid.Side.SOUTH]:
			if cells.has(cell + BuildGrid.SIDE_STEP[side]) and grid._wall_value(cell, side) != 0:
				return BuildResult.refused(BuildResult.Reason.WALL_IN_FOOTPRINT)
	return null


static func interaction_problem(
	grid: BuildGrid, spot: Vector2i, cells: Array[Vector2i]
) -> BuildResult:
	if spot == BuildObjectDef.NO_CELL:
		return null
	if not grid.in_bounds(spot) or grid._floor[grid._index(spot)] == BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED)
	var i := grid._index(spot)
	if grid._occupant[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, grid._occupant[i])
	if grid._reserved[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, grid._reserved[i])
	for side in 4:
		if cells.has(spot + BuildGrid.SIDE_STEP[side]) and grid._wall_value(spot, side) != 0:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED)
	return null


## A belt piece on the cell can become any belt piece at any facing.
static func _check_reshape_belt(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if not grid.in_bounds(edit.cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var object_id := grid.object_at(edit.cell)
	if object_id == 0:
		return BuildResult.refused(BuildResult.Reason.NO_OBJECT)
	var was_belt := BuildCatalog.is_belt(grid._objects[object_id]["def"])
	if not was_belt or not BuildCatalog.is_belt(edit.def_id):
		return BuildResult.refused(BuildResult.Reason.NOT_A_BELT, object_id)
	if edit.facing < 0 or edit.facing > 3:
		return BuildResult.refused(BuildResult.Reason.BAD_FACING)
	return BuildResult.accepted()
