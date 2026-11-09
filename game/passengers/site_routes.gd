class_name SiteRoutes
extends RefCounted
## The walks outside a player-built terminal on the airport site
## (SiteDefinition), searched over the site's open ground: grid cells with no
## floor, no object and no kept site obstacle, stepping only across edges
## with no wall (decision player-built-terminal-technical-design-site-plot-
## indoor-mask-passenger-eligibility, point 6). An entrance's walk comes in
## from the road past the grid's south edge, an exit's goes out to the plane
## door at the live stand: to the door's cell (StandPlacement.door_seed()),
## then the stand's apron route (StandPlacement.apron_route()). Each is the
## shortest walk in grid steps, going straight on where a shorter one turns.
##
## TerminalLayout finds each door's cells after every rebuild (door_cells());
## arrival() and departure() turn them into world points, and OutsideWalks
## searches the walks of passengers already outside. Pure: nothing here
## changes the grid.

const UNREACHED := 1 << 30


## Whether a walk outside may cross `cell`.
static func is_open_ground(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> bool:
	return (
		grid.in_bounds(cell)
		and grid.floor_at(cell) == BuildGrid.FLOOR_NONE
		and grid.object_at(cell) == 0
		and not site.is_obstacle(cell)
	)


## The open cells on the grid edge `step` leads out over (ROAD_STEP or
## PLANE_STEP) with no wall on that edge.
static func edge_cells(grid: BuildGrid, site: SiteDefinition, step: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var side := BuildGrid.SIDE_STEP.find(step)
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.in_bounds(cell + step) or not is_open_ground(grid, site, cell):
				continue
			if not grid.has_wall(cell, side):
				out.append(cell)
	return out


## Grid steps from every cell to the nearest of `seeds` over open ground, one
## int per cell at x + y * size.x; UNREACHED where there is no way.
static func distances(
	grid: BuildGrid, site: SiteDefinition, seeds: Array[Vector2i]
) -> PackedInt32Array:
	var w := grid.size.x
	var dist := PackedInt32Array()
	dist.resize(w * grid.size.y)
	dist.fill(UNREACHED)
	var queue: Array[Vector2i] = []
	for cell in seeds:
		if is_open_ground(grid, site, cell) and dist[cell.y * w + cell.x] == UNREACHED:
			dist[cell.y * w + cell.x] = 0
			queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var next_dist := dist[cell.y * w + cell.x] + 1
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			if not grid.in_bounds(next) or dist[next.y * w + next.x] != UNREACHED:
				continue
			if grid.has_wall(cell, side) or not is_open_ground(grid, site, next):
				continue
			dist[next.y * w + next.x] = next_dist
			queue.append(next)
	return dist


## The cells from `start` down `dist` (a distances() result) to a seed, start
## first, going on in `heading` where it can and else in Side order; empty
## when `start` is not reached.
static func descend(
	grid: BuildGrid, dist: PackedInt32Array, start: Vector2i, heading := Vector2i.ZERO
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var w := grid.size.x
	if not grid.in_bounds(start) or dist[start.y * w + start.x] >= UNREACHED:
		return cells
	cells.append(start)
	var at := start
	var dir := heading
	while dist[at.y * w + at.x] > 0:
		var want := dist[at.y * w + at.x] - 1
		var steps: Array[Vector2i] = [dir]
		steps.append_array(BuildGrid.SIDE_STEP)
		var found := false
		for step in steps:
			var next := at + step
			if step == Vector2i.ZERO or not grid.in_bounds(next):
				continue
			if dist[next.y * w + next.x] != want:
				continue
			if grid.has_wall(at, BuildGrid.SIDE_STEP.find(step)):
				continue
			dir = step
			found = true
			break
		if not found:
			push_error("SiteRoutes: no step down the distances from %s" % at)
			return [] as Array[Vector2i]
		at += dir
		cells.append(at)
	return cells


## The walk outside of a door at `anchor` whose back edge leads out by `out`,
## to the grid edge `edge` leads out over: [anchor, the cell beyond, ..., the
## edge cell], down `dist` (distances() from edge_cells(edge)). [anchor] when
## the door itself stands on that edge; empty when it has no way there.
static func door_cells(
	grid: BuildGrid,
	site: SiteDefinition,
	anchor: Vector2i,
	out: Vector2i,
	edge: Vector2i,
	dist: PackedInt32Array
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not reaches(grid, site, anchor, out, edge, dist):
		return cells
	cells.append(anchor)
	if grid.in_bounds(anchor + out):
		cells.append_array(descend(grid, dist, anchor + out, out))
	return cells


## Whether a door at `anchor` leading out by `out` has a walk to the grid edge
## `edge` leads out over (door_cells() is not empty), without walking it.
static func reaches(
	grid: BuildGrid,
	site: SiteDefinition,
	anchor: Vector2i,
	out: Vector2i,
	edge: Vector2i,
	dist: PackedInt32Array
) -> bool:
	if grid.has_wall(anchor, BuildGrid.SIDE_STEP.find(out)):
		return false
	var beyond := anchor + out
	if not grid.in_bounds(beyond):
		# Straight out over the edge, unless kept site art stands in the way.
		return out == edge and not site.is_obstacle(anchor)
	return (
		is_open_ground(grid, site, beyond) and dist[beyond.y * grid.size.x + beyond.x] < UNREACHED
	)


## The walk in from the road along door_cells() `cells` of an entrance: the
## road point straight out from the edge cell, the outside cells' corners
## back to the door, the door cell's outer edge and its centre.
static func arrival(
	grid: BuildGrid, site: SiteDefinition, cells: Array[Vector2i]
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var at_edge := ground(grid, site, cells[cells.size() - 1])
	points.append(Vector3(at_edge.x, site.road_height, site.road_z))
	var outside := cells.slice(1)
	outside.reverse()
	for cell: Vector2i in corners(outside):
		points.append(ground(grid, site, cell))
	var out := cells[1] - cells[0] if cells.size() > 1 else SiteDefinition.ROAD_STEP
	var centre := grid.cell_to_world(cells[0])
	points.append(centre + Vector3(out.x, 0.0, out.y) * 0.5)
	points.append(centre)
	return points


## The walk out to the plane at `stand` along door_cells() `cells` of an exit
## (searched down the distances to the door's cell): the door cell's centre
## and outer edge, the outside cells' corners and the stand's apron route to
## the door of a plane drawn with `model` ("" for the stand's door).
static func departure(
	grid: BuildGrid, site: SiteDefinition, cells: Array[Vector2i], stand: Dictionary, model := ""
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var out := cells[1] - cells[0] if cells.size() > 1 else SiteDefinition.PLANE_STEP
	var centre := grid.cell_to_world(cells[0])
	points.append(centre)
	points.append(centre + Vector3(out.x, 0.0, out.y) * 0.5)
	points.append_array(to_plane(grid, site, cells.slice(1), stand, model))
	return points


## The outside `cells` (ending on the plane door's cell) as corner points,
## then the apron route of `stand` to the door of a plane drawn with `model`.
static func to_plane(
	grid: BuildGrid, site: SiteDefinition, cells: Array, stand: Dictionary, model := ""
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for cell: Vector2i in corners(cells):
		points.append(ground(grid, site, cell))
	points.append_array(Array(StandPlacement.apron_route(stand, model)))
	return points


## The centre of `cell` at the site's ground height.
static func ground(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> Vector3:
	var centre := grid.cell_to_world(cell)
	return Vector3(centre.x, site.ground_height, centre.z)


## The first and last of `cells` and every cell where the walk turns.
static func corners(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in cells.size():
		var cell: Vector2i = cells[i]
		if i == 0 or i == cells.size() - 1:
			out.append(cell)
		elif cell - (cells[i - 1] as Vector2i) != (cells[i + 1] as Vector2i) - cell:
			out.append(cell)
	return out
