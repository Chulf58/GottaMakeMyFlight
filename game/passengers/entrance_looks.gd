class_name EntranceLooks
extends RefCounted
## Which way a passenger waiting in the line outside the entrance faces
## (EntranceLine, decision entrance-waiting-line-as-built-16-places-beside-
## the-walk-in): toward the door, the way the line moves, not back along the
## step that brought it to its place. Pure: it reads the sim and keeps nothing.


## The way a standing member of the line faces, as a grid direction (x, y),
## or Vector2.ZERO for anyone else (not in the line, or still walking).
static func face(sim: PassengerSim, p: Passenger) -> Vector2:
	if sim.layout.passenger_entrances.is_empty() or not sim.entrance.waiting(p.id):
		return Vector2.ZERO
	return Vector2(-sim.layout.door_outward(sim.grid, sim.layout.passenger_entrances[0]))
