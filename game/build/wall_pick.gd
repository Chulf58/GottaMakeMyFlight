class_name WallPick
extends RefCounted
## Finding the wall a pointer is on, for the Remove tool. A wall stands 2.5 m
## tall, so a click on its face lands on the ground well behind its foot; the
## camera's line of sight to that ground point is followed back and the first
## wall edge it crosses within the wall's drawn height is the one the player
## sees under the pointer. A wall the cutaway has cut to a stub is only its
## stub, and a wall the view does not draw yet counts as full height.

## Extra height past a wall's top that still picks it: the top face is as thick
## as the wall, so a click on it crosses the edge just above the top.
const TOP_SLACK_M := 0.1
## The no-edge answer of first_wall(): an edge whose side (z) is -1.
const NO_EDGE := Vector3i(0, 0, -1)


## The wall edge (WallCutaway.wall_edges form) a point crosses on grid line
## `line` of `axis` (0 for x, 2 for z), or NO_EDGE off the grid. `at` is
## relative to the grid origin.
static func edge_on_line(grid: BuildGrid, axis: int, line: int, at: Vector3) -> Vector3i:
	if axis == 0:
		var row := floori(at.z)
		if row < 0 or row >= grid.size.y:
			return NO_EDGE
		if line < grid.size.x:
			return Vector3i(line, row, BuildGrid.Side.WEST)
		return Vector3i(line - 1, row, BuildGrid.Side.EAST)
	var column := floori(at.x)
	if column < 0 or column >= grid.size.x:
		return NO_EDGE
	if line < grid.size.y:
		return Vector3i(column, line, BuildGrid.Side.NORTH)
	return Vector3i(column, line - 1, BuildGrid.Side.SOUTH)


## How tall the wall on `edge` can be picked: its drawn height, which the
## cutaway lowers to a stub (a cut glass wall is only its kerb).
static func pick_height(grid: BuildGrid, view: BuildView, edge: Vector3i) -> float:
	var cell := Vector2i(edge.x, edge.y)
	var drawn := view.sight_height(edge) if view != null else 0.0
	if grid.wall_kind(cell, edge.z) == BuildGrid.WallKind.GLASS:
		# A glass pane is seen through but picked all the way up, until cut.
		var cut := view != null and view.cut_edges().has(edge)
		return (drawn if cut else BuildView.WALL_HEIGHT) + TOP_SLACK_M
	return (drawn if drawn > 0.0 else BuildView.WALL_HEIGHT) + TOP_SLACK_M


## The nearest wall edge the straight line from `from` to `to` crosses at a
## height the wall reaches, as (x, y, side) in WallCutaway.wall_edges form,
## or NO_EDGE. The line is walked across the grid lines it crosses, so the
## cost grows with the grid's width, not with the number of walls.
static func first_wall(grid: BuildGrid, view: BuildView, from: Vector3, to: Vector3) -> Vector3i:
	var start := from - grid.origin
	var span := to - from
	var nearest := INF
	var found := NO_EDGE
	for axis in [0, 2]:
		if absf(span[axis]) < 0.000001:
			continue
		var cells := grid.size.x if axis == 0 else grid.size.y
		var low := maxi(0, ceili(minf(start[axis], start[axis] + span[axis])))
		var high := mini(cells, floori(maxf(start[axis], start[axis] + span[axis])))
		for line in range(low, high + 1):
			var t := (line - start[axis]) / span[axis]
			if t >= nearest:
				continue
			var at := start + span * t
			var edge := edge_on_line(grid, axis, line, at)
			if edge.z < 0 or not grid.has_wall(Vector2i(edge.x, edge.y), edge.z):
				continue
			if at.y <= pick_height(grid, view, edge):
				nearest = t
				found = edge
	return found
