class_name Airside
extends Node3D
## The one runway and one stand, as Marker3D waypoints placed in the scene
## (named children, in this node's own space) plus the taxiway links between
## them. Builds the TaxiGraph and gives each flight phase its path.

const REQUIRED_WAYPOINTS: Array[StringName] = [
	&"ApproachStart",
	&"Touchdown",
	&"RunwayExit",
	&"Stand",
	&"PushbackEnd",
	&"RunwayEntry",
	&"Liftoff",
	&"ClimbEnd",
]

## Taxiways as "From>To" waypoint pairs; each runs both ways.
@export var links := PackedStringArray()

var graph := TaxiGraph.new()


func _ready() -> void:
	rebuild()


## Rebuilds the graph from the Marker3D children. False (with an error) when a
## required waypoint is missing or a link names an unknown waypoint.
func rebuild() -> bool:
	graph = TaxiGraph.new()
	for child in get_children():
		if child is Marker3D:
			graph.add_waypoint(child.name, transform * child.position)
	var ok := true
	for waypoint in REQUIRED_WAYPOINTS:
		if not graph.has_waypoint(waypoint):
			push_error("Airside: missing waypoint '%s'" % waypoint)
			ok = false
	for pair in links:
		var ends := pair.split(">")
		if ends.size() != 2 or not graph.link(StringName(ends[0]), StringName(ends[1])):
			push_error("Airside: bad link '%s'" % pair)
			ok = false
	return ok


## The path a plane follows in `state`, or an empty array for a state that
## stays put.
func phase_path(state: int) -> PackedVector3Array:
	var path := PackedVector3Array()
	match state:
		FlightSim.State.APPROACH:
			path = _points([&"ApproachStart", &"Touchdown"])
		FlightSim.State.LANDING:
			path = _points([&"Touchdown", &"RunwayExit"])
		FlightSim.State.TAXI_IN:
			path = graph.route(&"RunwayExit", &"Stand")
		FlightSim.State.PUSHBACK:
			path = _points([&"Stand", &"PushbackEnd"])
		FlightSim.State.TAXI_OUT:
			path = graph.route(&"PushbackEnd", &"RunwayEntry")
		FlightSim.State.TAKEOFF:
			path = _points([&"RunwayEntry", &"Liftoff", &"ClimbEnd"])
	return path


func _points(names: Array[StringName]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for waypoint in names:
		out.append(graph.position_of(waypoint))
	return out
