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
const TOP_SLACK_M := 0.18
## Half-thickness of a wall's pick volume so clicks on a wall stub's front or
## back cap hit reliably even at steep camera angles.
const HIT_HALF_THICKNESS_M := BuildView.WALL_THICKNESS * 0.5 + 0.04
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


static func _wall_box(
	grid: BuildGrid, view: BuildView, axis: int, line: int, idx: int, edge: Vector3i
) -> AABB:
	var height := pick_height(grid, view, edge)
	var pad := HIT_HALF_THICKNESS_M
	if axis == 0:
		return AABB(
			Vector3(float(line) - pad, 0.0, float(idx)),
			Vector3(pad * 2.0, height, 1.0),
		)
	return AABB(
		Vector3(float(idx), 0.0, float(line) - pad),
		Vector3(1.0, height, pad * 2.0),
	)


## The nearest wall edge whose 3D pick volume the straight line from `from` to
## `to` hits at a height the wall reaches, as (x, y, side) in
## WallCutaway.wall_edges form, or NO_EDGE.
static func first_wall(grid: BuildGrid, view: BuildView, from: Vector3, to: Vector3) -> Vector3i:
	var start := from - grid.origin
	var span := to - from
	var reach := span.length()
	if reach < 0.000001:
		return NO_EDGE
	var dir := span / reach
	var nearest := reach + 0.001
	var found := NO_EDGE
	var pad := HIT_HALF_THICKNESS_M
	for axis: int in [0, 2]:
		var min_a := minf(start[axis], start[axis] + span[axis]) - pad
		var max_a := maxf(start[axis], start[axis] + span[axis]) + pad
		var cells := grid.size.x if axis == 0 else grid.size.y
		var low := maxi(0, floori(min_a))
		var high := mini(cells, ceili(max_a))
		var other := 2 - axis
		var other_cells := grid.size.y if axis == 0 else grid.size.x
		var min_o_all := maxi(0, floori(minf(start[other], start[other] + span[other]) - 0.05))
		var max_o_all := mini(
			other_cells - 1, floori(maxf(start[other], start[other] + span[other]) + 0.05)
		)
		for line in range(low, high + 1):
			var min_o := min_o_all
			var max_o := max_o_all
			if absf(span[axis]) >= 0.000001:
				var t_lo := (float(line) - pad - start[axis]) / span[axis]
				var t_hi := (float(line) + pad - start[axis]) / span[axis]
				var o_a := start[other] + span[other] * clampf(minf(t_lo, t_hi), 0.0, 1.0)
				var o_b := start[other] + span[other] * clampf(maxf(t_lo, t_hi), 0.0, 1.0)
				min_o = maxi(0, floori(minf(o_a, o_b) - 0.05))
				max_o = mini(other_cells - 1, floori(maxf(o_a, o_b) + 0.05))
			for idx in range(min_o, max_o + 1):
				var cell := (
					Vector2i(line if line < grid.size.x else line - 1, idx)
					if axis == 0
					else Vector2i(idx, line if line < grid.size.y else line - 1)
				)
				var side := (
					(BuildGrid.Side.WEST if line < grid.size.x else BuildGrid.Side.EAST)
					if axis == 0
					else (BuildGrid.Side.NORTH if line < grid.size.y else BuildGrid.Side.SOUTH)
				)
				if not grid.has_wall(cell, side):
					continue
				var edge := Vector3i(cell.x, cell.y, side)
				var hit: Variant = _wall_box(grid, view, axis, line, idx, edge).intersects_ray(
					start, dir
				)
				if hit == null:
					continue
				var dist := start.distance_to(hit)
				if dist < nearest:
					nearest = dist
					found = edge
	return found
