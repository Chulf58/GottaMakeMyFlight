class_name RepairEnclosure
extends RefCounted
## The walls RepairPlan adds so that the floor of a repair is closed in.
## Passengers use only floor that walls close in (BuildGrid.is_passenger_cell()),
## and RepairPlan's route test walks only such cells, so each repair choice
## built on the plan's grid copy also walls in the floor it uses before that
## test (decision player-built-terminal-technical-design-site-plot-indoor-
## mask-passenger-eligibility, point 8). The walls are ordinary plain wall
## edits in the plan, bought at the normal wall price.
##
## The floor walled in is all the floor joined to the choice's cells across
## edges with no wall or a door wall: its new floor and the floor it walks
## over, so a gap in the player's own walls there is closed too. A wall goes
## only where that floor meets the outside: the grid border, or a cell with no
## floor that the outside reaches without crossing a wall or that floor. A
## hole already closed in (floor taken up inside the walls) gets none. Inside
## a Toon shell the grid border is the facade (BuildGrid.shell_border) and
## all floor is closed in, so no wall is wanted.


## Plain walls on every edge where the floor joined to `seeds` meets the
## outside (see the class notes) and that has no wall yet, except an entrance
## or exit door object's back edge, which the door fills. In cell order, sides
## in Side order. Empty with a closed grid border.
static func walls_for(grid: BuildGrid, seeds: Array) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	if grid.shell_border:
		return out
	# Door objects' back edges (edge_key()), which the doors close.
	var backs := {}
	for way in DoorPlacement.ways_out(grid):
		backs[edge_key(way[0], BuildGrid.SIDE_STEP.find(way[1]))] = true
	var joined := _joined_floor(grid, seeds)
	var outside := _outside(grid, joined, backs)
	for cell: Vector2i in joined:
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			if grid.in_bounds(next) and not outside.has(next):
				continue
			if grid.wall_kind(cell, side) != BuildGrid.WallKind.NONE:
				continue
			if not backs.has(edge_key(cell, side)):
				out.append(BuildEdit.place_wall(cell, side))
	out.sort_custom(_in_cell_order)
	return out


## The floor cells joined to `seeds` across edges with no wall or a door wall.
static func _joined_floor(grid: BuildGrid, seeds: Array) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in seeds:
		if grid.floor_at(cell) != BuildGrid.FLOOR_NONE and not seen.has(cell):
			seen[cell] = true
			queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			var wall := grid.wall_kind(cell, side)
			var open := wall == BuildGrid.WallKind.NONE or wall == BuildGrid.WallKind.DOOR
			if open and not seen.has(next) and grid.floor_at(next) != BuildGrid.FLOOR_NONE:
				seen[next] = true
				queue.append(next)
	return seen


## The cells outside `joined` that the outside of the grid reaches without
## crossing a cell of `joined`, a wall or a door's back edge (in `backs`), as
## TerminalEnclosure floods.
static func _outside(grid: BuildGrid, joined: Dictionary, backs: Dictionary) -> Dictionary:
	var reached := {}
	var queue: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if joined.has(cell):
				continue
			for side in 4:
				var beyond := cell + BuildGrid.SIDE_STEP[side]
				if not grid.in_bounds(beyond) and _open(grid, backs, cell, side):
					reached[cell] = true
					queue.append(cell)
					break
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			if not grid.in_bounds(next) or reached.has(next) or joined.has(next):
				continue
			if _open(grid, backs, cell, side):
				reached[next] = true
				queue.append(next)
	return reached


static func _open(grid: BuildGrid, backs: Dictionary, cell: Vector2i, side: int) -> bool:
	return not grid.has_wall(cell, side) and not backs.has(edge_key(cell, side))


## `plan_edits` without each wall the plan places and later takes down again
## (a later leg's walk through a wall an earlier leg's floor needed) and
## without that removal: the same build for less money.
static func without_undone_walls(plan_edits: Array[BuildEdit]) -> Array[BuildEdit]:
	var placed := {}
	var dropped := {}
	for i in plan_edits.size():
		var edit := plan_edits[i]
		var key := edge_key(edit.cell, edit.side)
		if edit.kind == BuildEdit.Kind.PLACE_WALL:
			placed[key] = i
		elif edit.kind == BuildEdit.Kind.REMOVE_WALL and placed.has(key):
			dropped[placed[key]] = true
			dropped[i] = true
			placed.erase(key)
	var out: Array[BuildEdit] = []
	for i in plan_edits.size():
		if not dropped.has(i):
			out.append(plan_edits[i])
	return out


## One key per cell edge, whichever of its two cells names it: the north or
## west edge of a cell.
static func edge_key(cell: Vector2i, side: int) -> Vector3i:
	match side:
		BuildGrid.Side.SOUTH:
			return Vector3i(cell.x, cell.y + 1, BuildGrid.Side.NORTH)
		BuildGrid.Side.EAST:
			return Vector3i(cell.x + 1, cell.y, BuildGrid.Side.WEST)
	return Vector3i(cell.x, cell.y, side)


static func _in_cell_order(a: BuildEdit, b: BuildEdit) -> bool:
	if a.cell.y != b.cell.y:
		return a.cell.y < b.cell.y
	if a.cell.x != b.cell.x:
		return a.cell.x < b.cell.x
	return a.side < b.side
