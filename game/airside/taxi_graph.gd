class_name TaxiGraph
extends RefCounted
## The airside waypoints by name, kept apart from the passenger grid. The taxi
## routes between them come from TaxiRoutes.

var _positions: Dictionary = {}


## False (with an error) when the name is already taken.
func add_waypoint(waypoint: StringName, position: Vector3) -> bool:
	if _positions.has(waypoint):
		push_error("TaxiGraph: waypoint '%s' already exists" % waypoint)
		return false
	_positions[waypoint] = position
	return true


func has_waypoint(waypoint: StringName) -> bool:
	return _positions.has(waypoint)


func position_of(waypoint: StringName) -> Vector3:
	return _positions.get(waypoint, Vector3.ZERO)


## Every waypoint: name -> position.
func points() -> Dictionary:
	return _positions.duplicate()
