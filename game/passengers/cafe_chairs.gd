class_name CafeChairs
extends RefCounted
## Where a cafe guest is drawn on its chair. CafeSim seats a guest at the
## cafe_table's Mount_SitRoot (BuildObjectDef.seat_root_world), the same spot
## for every body, while the bodies differ in how far their hips and back reach
## behind it. PassengerViews adds offset() to the sim's position, so each body
## is drawn its own step towards the table and up
## (PassengerLooks.CAFE_SEAT_SHIFT_M), clear of the chair's back and frame.


## The body's step towards the table and up from the sim's position at a cafe
## seat. While sitting down or standing up it scales with how far the sim has
## moved the guest from the seat's approach cell towards the seat root, so it
## is zero at the chair front, where SitHold.chair_front() holds a roller
## sitter, and whole on the seat. Zero away from a cafe seat.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	if StageKinds.facility(p.stage) != StageKinds.Facility.CAFE:
		return Vector3.ZERO
	if StageKinds.location(p.stage) != StageKinds.Location.FACILITY_SEAT:
		return Vector3.ZERO
	var visit := sim.cafes.visit_of(p.id)
	if visit == null or visit.seat.is_empty():
		return Vector3.ZERO
	var approach := sim.grid.cell_to_world(visit.seat["approach"])
	var root := BuildObjectDef.seat_root_world(sim.grid, visit.seat)
	var full := (root - approach).length()
	var share := 1.0
	if full > 0.0:
		share = clampf((sim.world_position(p) - approach).length() / full, 0.0, 1.0)
	var facing: Vector2i = visit.seat["facing"]
	var shift := PassengerLooks.CAFE_SEAT_SHIFT_M[PassengerLooks.body_of(p.id, p.variant)]
	var ahead := Vector3(facing.x, 0.0, facing.y).normalized() * shift.x
	return (ahead + Vector3.UP * shift.y) * share
