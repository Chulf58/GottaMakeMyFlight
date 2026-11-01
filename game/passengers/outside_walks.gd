class_name OutsideWalks
extends RefCounted
## PassengerSim's walks outside the terminal: in from the road to an entrance
## (stage SPAWNED) and out from an exit to the plane (APRON). With a Toon
## shell and no site they are ShellRoutes' authored walks. On the airport site
## (PassengerSim.site) they are SiteRoutes' walks over open ground, and they
## are kept valid as the player builds (decision player-built-terminal-
## technical-design-site-plot-indoor-mask-passenger-eligibility, point 6).
##
## After every graph change (revalidate()) each walker outside checks the
## walk it has left: every grid cell on it must still be open ground, with no
## wall across it, and a road walker's entrance must still be one passengers
## may use. A walker whose walk fails takes a new one from where it stands: a
## road walker to the entrance passengers may use with the shortest walk
## (ties to the lower id), an apron walker to the plane. With none it stops
## where it stands, stuck with NO_ROUTE ("I can't get there"), its walk kept,
## until a later change gives it a walk again. A new walk keeps the walk so
## far, so how far the walker has gone (apron_mm), and with it its place in
## the boarding files, carries on.
##
## Not guaranteed: a walker stopped on the apron holds up the walkers behind
## it in its apron file (BoardingFiles), and a new walk is only looked for
## when the grid changes, never because a shorter one opened up.

## Spacing of the points a walk left is checked at, in metres.
const CHECK_STEP_M := 0.25


## The walk in from the road to entrance `entrance`, or empty when there is
## none.
static func arrival(sim: PassengerSim, entrance: int) -> Array[Vector3]:
	if sim.site == null:
		return ShellRoutes.arrival(sim, entrance)
	if not sim.layout.outside_routes.has(entrance):
		return [] as Array[Vector3]
	return SiteRoutes.arrival(sim.grid, sim.site, sim.layout.outside_routes[entrance])


## The walk from exit `exit_door`'s cell to the plane door, or empty when
## there is none.
static func departure(sim: PassengerSim, exit_door: int) -> Array[Vector3]:
	if sim.site == null:
		return ShellRoutes.departure(sim, exit_door)
	if not sim.layout.outside_routes.has(exit_door):
		return [] as Array[Vector3]
	return SiteRoutes.departure(sim.grid, sim.site, sim.layout.outside_routes[exit_door])


## Whether a road walker at the end of its walk may come in through the
## entrance on its cell (p.at): the cell is a passenger cell and, on a site,
## the entrance is one passengers may use.
static func may_enter(sim: PassengerSim, p: Passenger) -> bool:
	if sim.site == null:
		return sim.grid.is_passenger_cell(p.at)
	return sim.layout.passenger_entrances.has(_entrance_at(sim, p.at))


## Checks every walker outside after a graph change (see the class notes).
## Does nothing without a site. Each distance field it searches (to the plane,
## to each entrance) is worked out once per call, however many walkers use it.
static func revalidate(sim: PassengerSim) -> void:
	if sim.site == null:
		return
	var to_plane := PackedInt32Array()
	var to_doors := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.stage == Passenger.Stage.SPAWNED:
			_check_arrival(sim, p, to_doors)
		elif p.stage == Passenger.Stage.APRON:
			var door := sim.layout.door_cell(sim.grid, p.exit_object)
			if _clear_ahead(sim, p, door):
				_walk_on(p)
				continue
			if to_plane.is_empty():
				var edge := SiteRoutes.edge_cells(sim.grid, sim.site, SiteDefinition.PLANE_STEP)
				to_plane = SiteRoutes.distances(sim.grid, sim.site, edge)
			var cells := _cells_from(sim, p.apron_position(), to_plane)
			if cells.is_empty():
				p.stuck = Passenger.Stuck.NO_ROUTE
				continue
			var walk: Array[Vector3] = [p.apron_position()]
			walk.append_array(SiteRoutes.to_plane(sim.grid, sim.site, cells))
			_take(p, walk)
			sim.files.reroute(sim, p)


## A road walker keeps its walk while its entrance is in use and the walk is
## clear, and otherwise takes the shortest walk to an entrance in use.
## `to_doors` keeps each entrance's distance field (entrance id -> field).
static func _check_arrival(sim: PassengerSim, p: Passenger, to_doors: Dictionary) -> void:
	var entrance := _entrance_at(sim, p.at)
	if sim.layout.passenger_entrances.has(entrance) and _clear_ahead(sim, p, p.at):
		_walk_on(p)
		return
	var best: Array[Vector3] = []
	var best_mm := 0
	var best_door := 0
	for door in sim.layout.passenger_entrances:
		var walk := _walk_to(sim, p, door, to_doors)
		if walk.is_empty():
			continue
		var mm := _length_mm(walk)
		if best.is_empty() or mm < best_mm:
			best = walk
			best_mm = mm
			best_door = door
	if best.is_empty():
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	_take(p, best)
	p.at = sim.layout.door_cell(sim.grid, best_door)


## The walk from where `p` stands to entrance `door`, or empty. Off the grid
## (on the road) it walks back to the road point and in along the entrance's
## walk; on the grid over open ground to the cell beyond the door, down the
## door's field in `to_doors`, searched on first use.
static func _walk_to(
	sim: PassengerSim, p: Passenger, door: int, to_doors: Dictionary
) -> Array[Vector3]:
	var grid := sim.grid
	var here := p.apron_position()
	var route: Array[Vector2i] = sim.layout.outside_routes[door]
	var walk: Array[Vector3] = [here]
	if not grid.in_bounds(grid.world_to_cell(here)):
		walk.append_array(SiteRoutes.arrival(grid, sim.site, route))
		return walk
	if not to_doors.has(door):
		var seeds: Array[Vector2i] = []
		if route.size() > 1:
			seeds.append(route[1])
		else:
			# The door stands on the road edge: out to the road first.
			seeds = SiteRoutes.edge_cells(grid, sim.site, SiteDefinition.ROAD_STEP)
		to_doors[door] = SiteRoutes.distances(grid, sim.site, seeds)
	var cells := _cells_from(sim, here, to_doors[door])
	if cells.is_empty():
		return [] as Array[Vector3]
	for cell in SiteRoutes.corners(cells):
		walk.append(SiteRoutes.ground(grid, sim.site, cell))
	if route.size() == 1:
		# Along the road edge, off the grid, to the door.
		var step := SiteDefinition.ROAD_STEP
		walk.append(walk.back() + Vector3(step.x, 0.0, step.y) * 0.5)
	var centre := grid.cell_to_world(route[0])
	var out := DoorPlacement.back_step(grid.get_object(door)["facing"])
	walk.append(centre + Vector3(out.x, 0.0, out.y) * 0.5)
	walk.append(centre)
	return walk


## The open cells from the cell under `here` down `dist` to a seed, without
## that cell when the walk goes on from it (the walker is in it already, so
## it does not step back to its centre); from a neighbour when that cell is
## not open ground (new floor under the walker, or the door cell it stands
## in). Empty when there is no way.
static func _cells_from(
	sim: PassengerSim, here: Vector3, dist: PackedInt32Array
) -> Array[Vector2i]:
	var grid := sim.grid
	var start := grid.world_to_cell(here)
	var cells := SiteRoutes.descend(grid, dist, start)
	if cells.size() > 1:
		return cells.slice(1)
	if not cells.is_empty() or not grid.in_bounds(start):
		return cells
	var best: Array[Vector2i] = []
	for side in 4:
		var next := start + BuildGrid.SIDE_STEP[side]
		if not grid.in_bounds(next) or grid.has_wall(start, side):
			continue
		var tail := SiteRoutes.descend(grid, dist, next, BuildGrid.SIDE_STEP[side])
		if not tail.is_empty() and (best.is_empty() or tail.size() < best.size()):
			best = tail
	return best


## Whether every grid cell on the walk `p` has left, apart from `door`, is
## open ground, with no wall across a step between two of them.
static func _clear_ahead(sim: PassengerSim, p: Passenger, door: Vector2i) -> bool:
	var grid := sim.grid
	var left := p.apron_mm
	var last := Passenger.NO_CELL
	for i in range(1, p.apron.size()):
		var length := p.apron_segment_mm(i)
		if left >= length and i < p.apron.size() - 1:
			left -= length
			continue
		var from := p.apron[i - 1]
		var to := p.apron[i]
		var count := maxi(1, ceili((length - left) / (CHECK_STEP_M * 1000.0)))
		for k in count + 1:
			var mm := left + (length - left) * k / float(count)
			var cell := grid.world_to_cell(from.lerp(to, mm / float(maxi(length, 1))))
			if not _may_cross(sim, last, cell, door):
				return false
			last = cell
		left = 0
	return true


## Whether a walk may go from cell `from` on to `to`.
static func _may_cross(sim: PassengerSim, from: Vector2i, to: Vector2i, door: Vector2i) -> bool:
	var grid := sim.grid
	if from == to or not grid.in_bounds(to):
		return true
	if to != door and not SiteRoutes.is_open_ground(grid, sim.site, to):
		return false
	var step := from - to
	if absi(step.x) + absi(step.y) == 1:
		return not grid.has_wall(to, BuildGrid.SIDE_STEP.find(step))
	return true


## Replaces the walk `p` has left with `walk`, which starts where it stands:
## its walk so far is kept, so apron_mm carries on.
static func _take(p: Passenger, walk: Array[Vector3]) -> void:
	var kept: Array[Vector3] = []
	var left := p.apron_mm
	if not p.apron.is_empty():
		kept.append(p.apron[0])
	for i in range(1, p.apron.size()):
		var length := p.apron_segment_mm(i)
		if left <= length:
			break
		kept.append(p.apron[i])
		left -= length
	kept.append_array(walk)
	p.apron = kept
	p.apron_mm = _length_mm(kept.slice(0, kept.size() - walk.size() + 1))
	_walk_on(p)


## A walker with a walk again is no longer stuck.
static func _walk_on(p: Passenger) -> void:
	if p.stuck == Passenger.Stuck.NO_ROUTE:
		p.stuck = Passenger.Stuck.NONE


static func _length_mm(points: Array) -> int:
	var walk := Passenger.new()
	walk.apron.assign(points)
	return walk.apron_total_mm()


## The entrance door standing on `cell`, or 0.
static func _entrance_at(sim: PassengerSim, cell: Vector2i) -> int:
	for door in sim.layout.entrances:
		if sim.layout.door_cell(sim.grid, door) == cell:
			return door
	return 0
