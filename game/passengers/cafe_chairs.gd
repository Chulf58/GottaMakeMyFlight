class_name CafeChairs
extends RefCounted
## Where a food-room guest is drawn on its seat. CafeSim seats a guest at the
## table piece's Mount_SitRoot (BuildObjectDef.seat_root_world), the same spot
## for every body, while the bodies differ in how far their hips and back reach
## behind it. PassengerViews adds offset() to the sim's position, so each body
## is drawn its own step towards the table and up for that piece
## (PassengerLooks.seat_shift(): CAFE_SEAT_SHIFT_M at the cafe_table, the
## smaller PIECE_SEAT_SHIFT_M at the restaurant table and booth), clear of the
## seat's back and frame and of the table top. The piece is the visit's own
## placement snapshot, which still names it after the table is removed.


## The body's step towards the table and up from the sim's position at a cafe
## seat. While sitting down or standing up it scales with how far the sim has
## moved the guest from the seat's approach cell towards the seat root, so it
## is zero at the chair front, where SitHold.chair_front() holds a roller
## sitter, and whole on the seat. Zero away from a cafe seat.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var visit := _seat_visit(sim, p)
	if visit == null:
		return Vector3.ZERO
	var approach := sim.grid.cell_to_world(visit.seat["approach"])
	var root := BuildObjectDef.seat_root_world(sim.grid, visit.seat)
	var full := (root - approach).length()
	var share := 1.0
	if full > 0.0:
		share = clampf((sim.world_position(p) - approach).length() / full, 0.0, 1.0)
	return _step(p, visit) * share


## The frame (world) `p` is drawn in once seated at its cafe seat: the seat
## root (BuildObjectDef.seat_root_world(), where CafeSim seats it) plus the
## whole of offset()'s step, facing the way the seat faces. The same on every
## frame of the sit-down, the stay and the stand-up (a floor bag lies in it,
## CarryPlace.seat_frame()). Null away from a cafe seat.
static func seated_frame(sim: PassengerSim, p: Passenger) -> Variant:
	var visit := _seat_visit(sim, p)
	if visit == null:
		return null
	var facing: Vector2i = visit.seat["facing"]
	var at := BuildObjectDef.seat_root_world(sim.grid, visit.seat) + _step(p, visit)
	return Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.y)), at)


## `p`'s cafe visit while it is at a cafe seat, with its seat; null otherwise.
static func _seat_visit(sim: PassengerSim, p: Passenger) -> CafeVisit:
	if StageKinds.facility(p.stage) != StageKinds.Facility.CAFE:
		return null
	if StageKinds.location(p.stage) != StageKinds.Location.FACILITY_SEAT:
		return null
	var visit := sim.cafes.visit_of(p.id)
	if visit == null or visit.seat.is_empty():
		return null
	return visit


## The body's whole step towards the table and up at `visit`'s seat.
static func _step(p: Passenger, visit: CafeVisit) -> Vector3:
	var facing: Vector2i = visit.seat["facing"]
	var body := PassengerLooks.body_of(p.id, p.variant)
	var shift := PassengerLooks.seat_shift(StringName(visit.piece.get("def", &"")), body)
	var ahead := Vector3(facing.x, 0.0, facing.y).normalized() * shift.x
	return ahead + Vector3.UP * shift.y
