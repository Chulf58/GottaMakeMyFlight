class_name GateRowWalk
extends RefCounted
## The walk of a guest to its gate chair front (user ruling gate-chair-row-
## walk-guests-walk-one-cell-out-from-the-chair, board 11922532, and the
## user's follow-up "Square turn-in, skip walled rows"): every other gate
## seat's front costs FRONT_COST times its step for that one query
## (BuildGrid.find_path_costed()), so a guest coming along a row of fronts
## walks one cell further out, and it turns in square at its own front: from
## the outer cell straight in front of it, never on a diagonal across the
## neighbour's gap (square()). A neighbour's roller lies beside its front,
## 0.07 m ahead of it (GateRoller.spot()), on the line along the fronts, and a
## guest walking that line put its legs through it. The fronts of one row are
## next to each other, so the gaps between them are front cells too.
##
## A front whose outer cell runs along a wall (a wall on the outer cell's far
## edge) costs nothing extra: walking that outer row put the roller's stamped
## side against the wall, and PullSide sent it across and back within the last
## metre (female_right of the gate_chair_roller_probe). Guests there walk the
## fronts as before. Only GateCapacity's seat claim and PassengerEdits' replan
## of a guest bound for its seat walk so; every other route, the staff graph and
## RouteCache's walk lengths are the plain graph's (a seat walk's forecast
## under-reads the turn round the row a little). Nothing is saved.

## How much a step onto another guest's chair front costs, against a plain
## step: along three fronts that is about 9, one cell out and back in about 5.8.
const FRONT_COST := 3.0


## Every gate seat front of `sim`'s layout but `own` (the guest's own front)
## and those whose outer cell runs along a wall (walled_outer()).
static func costly_fronts(sim: PassengerSim, own: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for seat: Dictionary in sim.layout.seats:
		var front: Vector2i = seat["front"]
		if front == own or front in out:
			continue
		if walled_outer(sim.grid, front, front - (seat["cell"] as Vector2i)):
			continue
		out.append(front)
	return out


## Whether the outer cell of chair front `front` (one step `out` further, out
## of the chair) has a wall on its far edge: its row runs along a wall.
static func walled_outer(grid: BuildGrid, front: Vector2i, out: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(out)
	var outer := front + out
	if side < 0 or not grid.in_bounds(outer):
		return false
	return grid.wall_kind(outer, side) != BuildGrid.WallKind.NONE


## The walk from `from` to the chair front `front` of a guest seating at
## `seat_cell`, round the other fronts and turned in square (square()).
static func path(
	sim: PassengerSim, from: Vector2i, front: Vector2i, seat_cell: Vector2i
) -> Array[Vector2i]:
	var cells := sim.grid.find_path_costed(from, front, costly_fronts(sim, front), FRONT_COST)
	return square(sim.grid, cells, front - seat_cell)


## `cells` (a walk ending on a chair front facing grid way `out`) with a last
## diagonal step onto the front made two straight ones through the outer cell
## (the front plus `out`), when the cell before the front is a straight step
## from that outer cell and both steps are passenger routes; else as it is.
static func square(grid: BuildGrid, cells: Array[Vector2i], out: Vector2i) -> Array[Vector2i]:
	if cells.size() < 2:
		return cells
	var front: Vector2i = cells[-1]
	var before: Vector2i = cells[-2]
	var outer := front + out
	if (front - before).length_squared() != 2 or (outer - before).length_squared() != 1:
		return cells
	if not grid.is_passenger_cell(outer):
		return cells
	if not grid.can_passenger_route(before, outer) or not grid.can_passenger_route(outer, front):
		return cells
	var squared: Array[Vector2i] = cells.slice(0, cells.size() - 1)
	squared.append(outer)
	squared.append(front)
	return squared
