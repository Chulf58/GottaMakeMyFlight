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
## row, plus the passenger's body's step forward and up off the chair
## (PassengerLooks.SEAT_SHIFT_M). While sitting down or standing up it scales
## with how far the sim has moved the passenger from the front cell towards the seat, so the step
## blends in and out with the shuffle. Zero away from a gate seat, and zero
## for a row an edit removed until the sim releases the seat on its next tick.
## After a row moves, paused or not, the passenger keeps the chair it sits on
## until it has got up (GateRelocation.chair_of()). A seat cell outside its
## row's footprint is a bug: reported, zero.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var step := seated_step(sim, p)
	if step == Vector3.ZERO:
		return step
	var front := sim.grid.cell_to_world(p.seat_front)
	var seat := sim.grid.cell_to_world(p.seat_cell)
	var full := (front - seat).length() * (1.0 - PassengerSim.SIT_FORWARD_M)
	var share := clampf((sim.world_position(p) - front).length() / full, 0.0, 1.0)
	return step * share


## offset() whole, as on the seat: the sideways step to the chair plus the
## body's step forward and up. Zero where offset() is.
static func seated_step(sim: PassengerSim, p: Passenger) -> Vector3:
	var at_gate_seat := StageKinds.location(p.stage) == StageKinds.Location.GATE_SEAT
	if not at_gate_seat or p.seat_cell == Passenger.NO_CELL:
		return Vector3.ZERO
	var record := GateRelocation.chair_of(sim, p)
	if record.is_empty():
		return Vector3.ZERO
	var def := BuildCatalog.get_def(record["def"])
	var index := def.footprint(record["anchor"], record["facing"]).find(p.seat_cell)
	if index < 0 or index >= CHAIR_OFFSET_M.size():
		push_error("passenger %d seat cell %s is not a chair cell" % [p.id, p.seat_cell])
		return Vector3.ZERO
	var front := sim.grid.cell_to_world(p.seat_front)
	var seat := sim.grid.cell_to_world(p.seat_cell)
	var side := BuildObjectDef.rotate_point(Vector2(CHAIR_OFFSET_M[index], 0.0), record["facing"])
	# The body's own step forward and up, clear of the chair (SEAT_SHIFT_M).
	var shift := PassengerLooks.SEAT_SHIFT_M[PassengerLooks.body_of(p.id, p.variant)]
	var ahead := (front - seat).normalized() * shift.x + Vector3.UP * shift.y
	return Vector3(side.x, 0.0, side.y) + ahead


## The frame (world) `p` is drawn in once seated on its gate chair: the sim's
## seat spot (SIT_FORWARD_M of the way from the seat cell to the front cell,
## PassengerGates.seat_point()) plus seated_step(), facing out of the chair.
## The same on every frame of the sit-down, the stay and the stand-up (a floor
## bag lies in it, CarryPlace.seat_frame()). Null away from a gate seat.
static func seated_frame(sim: PassengerSim, p: Passenger) -> Variant:
	if StageKinds.location(p.stage) != StageKinds.Location.GATE_SEAT:
		return null
	if p.seat_cell == Passenger.NO_CELL or p.seat_front == Passenger.NO_CELL:
		return null
	var front := sim.grid.cell_to_world(p.seat_front)
	var seat := sim.grid.cell_to_world(p.seat_cell)
	var out := front - seat
	var at := seat + out * PassengerSim.SIT_FORWARD_M + seated_step(sim, p)
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), at)
