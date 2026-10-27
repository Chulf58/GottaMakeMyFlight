class_name GateChairs
extends RefCounted
## Where a gate-seated passenger is drawn: on a chair of the seat row's mesh.
## A seat_row has three cells but four chairs (pans at x -1.08, -0.36, 0.36
## and 1.08 m in build_seat_row, tools/blender/interior/build_interior_kit.py),
## while PassengerSim seats passengers by cell. PassengerViews adds offset() to
## the sim's position, so the sim stays on grid terms and only the drawing
## knows the mesh. The middle cell takes the chair at +0.36; the one at -0.36
## stays empty.

## Sideways from each footprint cell's centre to its chair, along the row's x
## axis at facing 0, by footprint index.
const CHAIR_OFFSET_M: Array[float] = [-0.08, 0.36, 0.08]


## The sideways step from the sim's position to the chair, turned with the
## row. While sitting down or standing up it scales with how far the sim has
## moved the passenger from the front cell towards the seat, so the step
## blends in and out with the shuffle. Zero away from a gate seat, and zero
## for a row an edit removed until the sim releases the seat on its next tick.
## A seat cell outside its row's footprint is a bug: reported, zero.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	if not p.stage in PassengerSim.SEAT_STAGES or p.seat_cell == Passenger.NO_CELL:
		return Vector3.ZERO
	var record := sim.grid.get_object(p.seat_object)
	if record.is_empty():
		return Vector3.ZERO
	var def := BuildCatalog.get_def(record["def"])
	var index := def.footprint(record["anchor"], record["facing"]).find(p.seat_cell)
	if index < 0 or index >= CHAIR_OFFSET_M.size():
		push_error("passenger %d seat cell %s is not a chair cell" % [p.id, p.seat_cell])
		return Vector3.ZERO
	var front := sim.grid.cell_to_world(p.seat_front)
	var seat := sim.grid.cell_to_world(p.seat_cell)
	var full := (front - seat).length() * (1.0 - PassengerSim.SIT_FORWARD_M)
	var share := clampf((sim.world_position(p) - front).length() / full, 0.0, 1.0)
	var side := BuildObjectDef.rotate_point(Vector2(CHAIR_OFFSET_M[index], 0.0), record["facing"])
	return Vector3(side.x, 0.0, side.y) * share
