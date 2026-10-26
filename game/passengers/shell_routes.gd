class_name ShellRoutes
extends RefCounted
## PassengerSim's walks outside the terminal, as world points. Inside a
## terminal shell (PassengerSim.shell), an entrance or exit on one of its Toon
## doors walks that ShellDoorConnection's route: in from the road to the
## entrance cell, out from the exit cell to the plane door. With no shell
## there is no road walk and the exit walk is PassengerSim.apron_waypoints.
## A door the shell does not know (only the debug starter terminal can place
## one) is walked the same way as with no shell, with a warning the first
## time, because its passengers then cross the shell's walls.

## Doors already warned about, by "def@anchor:facing".
static var _warned := {}


## The road walk to an entrance's cell: the route, the cell's outer edge and
## its centre. Empty when the entrance has no shell connection.
static func arrival(sim: PassengerSim, entrance: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var door := _connection(sim, entrance)
	if door == null:
		return points
	var centre := sim.grid.cell_to_world(sim.layout.door_cell(sim.grid, entrance))
	points.append_array(Array(door.route))
	points.append(centre + _outward(sim, entrance) * 0.5)
	points.append(centre)
	return points


## The walk from an exit's cell to the plane door: the cell's centre and
## outer edge, then its connection's route, or without one a metre out and
## the default apron waypoints. Empty for an unknown door.
static func departure(sim: PassengerSim, exit_door: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var cell := sim.layout.door_cell(sim.grid, exit_door)
	if cell == BuildObjectDef.NO_CELL:
		return points
	var centre := sim.grid.cell_to_world(cell)
	var out := _outward(sim, exit_door)
	points.append(centre)
	points.append(centre + out * 0.5)
	var door := _connection(sim, exit_door)
	if door != null:
		points.append_array(Array(door.route))
		return points
	points.append(centre + out * 1.5)
	points.append_array(Array(sim.apron_waypoints))
	return points


static func _outward(sim: PassengerSim, door: int) -> Vector3:
	var out := sim.layout.door_outward(sim.grid, door)
	return Vector3(out.x, 0.0, out.y)


## The shell connection a door object stands on, or null.
static func _connection(sim: PassengerSim, door: int) -> ShellDoorConnection:
	if sim.shell == null:
		return null
	var record := sim.grid.get_object(door)
	if record.is_empty():
		return null
	var found := sim.shell.connection_for(record["def"], record["anchor"], record["facing"])
	var key := "%s@%s:%d" % [record["def"], record["anchor"], record["facing"]]
	if found == null and not _warned.has(key):
		_warned[key] = true
		push_warning(
			(
				"ShellRoutes: %s at %s is not on a Toon door; its passengers walk the default route"
				% [record["def"], record["anchor"]]
			)
		)
	return found
