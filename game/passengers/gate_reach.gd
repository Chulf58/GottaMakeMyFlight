class_name GateReach
extends RefCounted
## What is near a gate, for the passengers waiting for its flight (user ruling
## 342df92a: they wait on the gate seats closest to their flight's gate desk, and
## with no seats near the gate they stand and get less calm).
##
## A gate's place is its gate desk's footprint (GateDesks): the desk linked to
## the gate's exit, found again from the grid on each layout rebuild as the
## desk nearest that exit within GateDesks.LINK_CELLS, ties to the lower id. A
## seat is near the gate when its cell is at most NEAR_CELLS from a desk cell
## (diagonals counting one, the way GateDesks measures a link), so a seat row
## beside the desk and the row across the gate area count, and a row in
## another gate's corner does not. 8 cells is 8 m: two LINK_CELLS, the walk
## across a gate lounge.

const NEAR_CELLS := 8


## Gate letter -> the cells of the gate desk linked to its exit, for each of
## `exit_gates` (exit id -> gate letter) that has a desk within reach. Each desk
## serves one exit, the lower exit id first.
static func desks_of(grid: BuildGrid, exit_gates: Dictionary) -> Dictionary:
	var out := {}
	var taken := {}
	var exits: Array = exit_gates.keys()
	exits.sort()
	for exit: int in exits:
		# An edit just removed it; ApronStand sends the gates again after.
		if grid.get_object(exit).is_empty():
			continue
		var best := 0
		var best_cells := GateDesks.LINK_CELLS + 1
		for desk in GateDesks.desk_ids(grid):
			if taken.has(desk):
				continue
			var cells := GateDesks.reach_cells(grid, GateDesks.desk_footprint(grid, desk), exit)
			if cells < best_cells:
				best = desk
				best_cells = cells
		if best != 0:
			taken[best] = true
			out[exit_gates[exit]] = GateDesks.desk_footprint(grid, best)
	return out


## How many cells (diagonals counting one) `cell` is from the nearest of
## `anchors`; 0 for none.
static func cells_from(cell: Vector2i, anchors: Array[Vector2i]) -> int:
	var best := 0
	for i in anchors.size():
		var d := maxi(absi(cell.x - anchors[i].x), absi(cell.y - anchors[i].y))
		if i == 0 or d < best:
			best = d
	return best
