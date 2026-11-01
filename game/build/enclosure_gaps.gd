class_name EnclosureGaps
extends RefCounted
## Where the outer wall of a building is open: the gap edges the build view
## marks (GapMarkers), so the player sees why floor is not indoor (decision
## player-builds-the-terminal-floor-outer-walls-auto-roof-land-plots-starter-
## one-floor, point 2).
##
## A gap edge is an edge of a floored cell that is not indoor
## (BuildGrid.is_indoor) where the cell beyond has no floor (or is off the
## grid), with no wall on it and not a standing entrance or exit's back edge
## (DoorPlacement.ways_out): the door object fills that one. Only floor that
## belongs to a building counts: an unclosed floor region (floored cells that
## are not indoor, joined across edges with no wall) has gap edges only when
## a wall stands on at least one of its cells' edges. Bare floor with no wall
## at all is not a building yet, so marking all of its edges would only say
## "there are no walls".
##
## Pure: it reads only the public BuildGrid API (floor_at, has_wall,
## is_indoor) and DoorPlacement.ways_out, and changes nothing.


## Every gap edge as Vector3i(x, y, side) (BuildGrid.Side), in cell index
## order (y, then x), then side order.
static func gap_edges(grid: BuildGrid) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	var in_building := _building_cells(grid)
	var backs := {}
	for way in DoorPlacement.ways_out(grid):
		var anchor: Vector2i = way[0]
		backs[Vector3i(anchor.x, anchor.y, BuildGrid.SIDE_STEP.find(way[1]))] = true
	for y in grid.size.y:
		for x in grid.size.x:
			if in_building[x + y * grid.size.x] == 0:
				continue
			var cell := Vector2i(x, y)
			for side in 4:
				if grid.has_wall(cell, side) or backs.has(Vector3i(x, y, side)):
					continue
				if grid.floor_at(cell + BuildGrid.SIDE_STEP[side]) == BuildGrid.FLOOR_NONE:
					edges.append(Vector3i(x, y, side))
	return edges


## The gap edges grouped into runs: neighbouring edges on the same side along
## one straight line are one run. In the order of each run's first edge.
static func gap_runs(grid: BuildGrid) -> Array[Run]:
	var edges := gap_edges(grid)
	var known := {}
	for edge in edges:
		known[edge] = true
	var runs: Array[Run] = []
	for edge in edges:
		var along := Run.along_of(edge.z)
		if known.has(edge - Vector3i(along.x, along.y, 0)):
			continue
		var run := Run.new()
		run.cell = Vector2i(edge.x, edge.y)
		run.side = edge.z
		run.length = 1
		while known.has(edge + Vector3i(along.x, along.y, 0) * run.length):
			run.length += 1
		runs.append(run)
	return runs


## One byte per cell at x + y * size.x: 1 for a floored cell that is not
## indoor and whose unclosed floor region has a wall on some cell's edge.
static func _building_cells(grid: BuildGrid) -> PackedByteArray:
	var w := grid.size.x
	var marks := PackedByteArray()
	marks.resize(w * grid.size.y)
	marks.fill(0)
	var seen := PackedByteArray()
	seen.resize(marks.size())
	seen.fill(0)
	for start in marks.size():
		@warning_ignore("integer_division")
		var first := Vector2i(start % w, start / w)
		if seen[start] == 1 or not _unclosed_floor(grid, first):
			continue
		seen[start] = 1
		var region: Array[Vector2i] = [first]
		var walled := false
		var head := 0
		while head < region.size():
			var cell := region[head]
			head += 1
			for side in 4:
				if grid.has_wall(cell, side):
					walled = true
					continue
				var next: Vector2i = cell + BuildGrid.SIDE_STEP[side]
				if not _unclosed_floor(grid, next) or seen[next.x + next.y * w] == 1:
					continue
				seen[next.x + next.y * w] = 1
				region.append(next)
		if walled:
			for cell in region:
				marks[cell.x + cell.y * w] = 1
	return marks


static func _unclosed_floor(grid: BuildGrid, cell: Vector2i) -> bool:
	return grid.floor_at(cell) != BuildGrid.FLOOR_NONE and not grid.is_indoor(cell)


## A straight line of gap edges: the first edge's cell and side, and how many
## edges long it runs (east for a north or south side, south for an east or
## west side).
class Run:
	extends RefCounted
	var cell := Vector2i.ZERO
	var side := 0
	var length := 0

	## The grid step along a run on `side`.
	static func along_of(edge_side: int) -> Vector2i:
		if edge_side == BuildGrid.Side.NORTH or edge_side == BuildGrid.Side.SOUTH:
			return Vector2i(1, 0)
		return Vector2i(0, 1)

	## The middle of the run on the wall line, at floor height.
	func centre(grid: BuildGrid) -> Vector3:
		var step: Vector2i = BuildGrid.SIDE_STEP[side]
		var along := along_of(side)
		var middle := (length - 1) * 0.5
		return (
			grid.cell_to_world(cell)
			+ Vector3(step.x, 0.0, step.y) * 0.5
			+ Vector3(along.x, 0.0, along.y) * middle
		)
