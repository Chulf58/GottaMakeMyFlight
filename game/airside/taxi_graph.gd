class_name TaxiGraph
extends RefCounted
## The airside taxi graph: named waypoints joined by taxiways, kept apart from
## the passenger grid. Taxiways run both ways. Routes are shortest by length.

var _astar := AStar3D.new()
var _ids: Dictionary = {}


## False (with an error) when the name is already taken.
func add_waypoint(waypoint: StringName, position: Vector3) -> bool:
	if _ids.has(waypoint):
		push_error("TaxiGraph: waypoint '%s' already exists" % waypoint)
		return false
	var id := _ids.size()
	_ids[waypoint] = id
	_astar.add_point(id, position)
	return true


func has_waypoint(waypoint: StringName) -> bool:
	return _ids.has(waypoint)


func position_of(waypoint: StringName) -> Vector3:
	return _astar.get_point_position(_ids[waypoint]) if _ids.has(waypoint) else Vector3.ZERO


## False (with an error) when either end is not a waypoint.
func link(from: StringName, to: StringName) -> bool:
	if not (_ids.has(from) and _ids.has(to)):
		push_error("TaxiGraph: cannot link '%s' to '%s'" % [from, to])
		return false
	_astar.connect_points(_ids[from], _ids[to], true)
	return true


## Points from `from` to `to` inclusive, or an empty array when either is
## unknown or no taxiway joins them.
func route(from: StringName, to: StringName) -> PackedVector3Array:
	if not (_ids.has(from) and _ids.has(to)):
		return PackedVector3Array()
	return _astar.get_point_path(_ids[from], _ids[to])
