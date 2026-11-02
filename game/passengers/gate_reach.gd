class_name GateReach
extends RefCounted
## What is near a gate, for the passengers waiting for its flight (user ruling
## 342df92a: they wait on the gate seats closest to their flight's gate desk, and
## with no seats near the gate they stand and get less calm).
##
## A gate's place is its gate desk's footprint (GateDesks). The desk is the one
## the gate is bound to (GateDesks.bindings, the sticky and saved links), passed
## in as gate letter -> desk object id; nothing here guesses a desk from where
## it stands. A seat is near the gate when its cell is at most NEAR_CELLS from a
## desk cell (diagonals counting one, the way GateDesks measures a link), so a
## seat row beside the desk and the row across the gate area count, and a row in
## another gate's corner does not. 8 cells is 8 m: twice GateDesks.LINK_CELLS,
## the walk across a gate lounge.

const NEAR_CELLS := 8


## Gate letter -> the cells of its gate desk, for each of `gate_desk_ids` (gate
## letter -> desk object id) whose desk still stands on `grid`. A gate whose
## desk an edit just removed is left out until ApronStand sends the gates again.
static func cells_of(grid: BuildGrid, gate_desk_ids: Dictionary) -> Dictionary:
	var out := {}
	for gate: String in gate_desk_ids:
		if GateDesks.is_desk(grid, gate_desk_ids[gate]):
			out[gate] = GateDesks.desk_footprint(grid, gate_desk_ids[gate])
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
