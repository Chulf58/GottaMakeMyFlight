class_name Airside
extends Node3D
## The one runway and one stand, as Marker3D waypoints placed in the scene
## (named children, in this node's own space) plus the taxiway links between
## them. Builds the TaxiGraph and gives each flight phase its path. Also gives
## the two sky tracks views draw around a flight: the arrival lead-in into
## ApproachStart and the climb-out from ClimbEnd, each a flat track through its
## turn waypoints with wide round turns.

const REQUIRED_WAYPOINTS: Array[StringName] = [
	&"ApproachStart",
	&"Touchdown",
	&"RunwayExit",
	&"Stand",
	&"PushbackEnd",
	&"RunwayEntry",
	&"Liftoff",
	&"ClimbEnd",
	&"ArrivalStraightIn",
	&"ArrivalEntry",
	&"ArrivalPass",
	&"ArrivalTurnWest",
	&"ArrivalTurnNorth",
	&"DepartureTurn",
	&"DepartureExit",
]
## The sky tracks' turn waypoints. Only their x and z count: FlightPose sets
## the height above the join (ApproachStart or ClimbEnd).
const LEAD_IN_WAYPOINTS: Array[StringName] = [
	&"ArrivalEntry", &"ArrivalPass", &"ArrivalTurnWest", &"ArrivalTurnNorth", &"ApproachStart"
]
const CLIMB_OUT_WAYPOINTS: Array[StringName] = [&"ClimbEnd", &"DepartureTurn", &"DepartureExit"]
## Turn radius of the sky tracks, in metres. A corner too tight for it gets the
## widest turn that fits.
const SKY_TURN_RADIUS := 160.0
## Straight flight kept at each end of a sky track, so the bank rolls out
## before the join.
const SKY_END_STRAIGHT := 45.0
## Arc length between the points that sample a turn.
const SKY_ARC_STEP := 4.0

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


## The arrival's flat track, ending at ApproachStart on the approach heading.
## Every point has ApproachStart's height.
func lead_in_track() -> PackedVector3Array:
	return _sky_track(LEAD_IN_WAYPOINTS, graph.position_of(&"ApproachStart").y)


## The short straight-in on the runway's extended centreline, ending at
## ApproachStart, for an arrival listed too late for the full lead-in. Every
## point has ApproachStart's height.
func straight_in_track() -> PackedVector3Array:
	return _sky_track(
		[&"ArrivalStraightIn", &"ApproachStart"], graph.position_of(&"ApproachStart").y
	)


## The departure's flat track, starting at ClimbEnd on the climb heading.
## Every point has ClimbEnd's height.
func climb_out_track() -> PackedVector3Array:
	return _sky_track(CLIMB_OUT_WAYPOINTS, graph.position_of(&"ClimbEnd").y)


func _sky_track(names: Array[StringName], height: float) -> PackedVector3Array:
	var corners := _points(names)
	for i in corners.size():
		corners[i] = Vector3(corners[i].x, height, corners[i].z)
	return round_corners(corners, SKY_TURN_RADIUS, SKY_END_STRAIGHT, SKY_ARC_STEP)


## `corners` with every inner corner replaced by a circular arc of `radius`
## (flat, about the vertical) sampled every `step` metres. A turn uses at most
## half of a segment it shares with another turn, and leaves `end_straight` of
## an end segment straight; a corner with less room gets a tighter arc. A
## corner that doubles back on itself is kept sharp.
static func round_corners(
	corners: PackedVector3Array, radius: float, end_straight: float, step: float
) -> PackedVector3Array:
	var last := corners.size() - 1
	var out := PackedVector3Array()
	if last < 0:
		return out
	out.append(corners[0])
	for i in range(1, last):
		var into := (corners[i] - corners[i - 1]).normalized()
		var out_of := (corners[i + 1] - corners[i]).normalized()
		var turn := into.angle_to(out_of)
		# A straight run, a doubled point or a reversal keeps its sharp corner.
		if turn < 0.0001 or turn > PI - 0.001 or into.is_zero_approx() or out_of.is_zero_approx():
			out.append(corners[i])
			continue
		var room_in := _turn_room(corners[i - 1].distance_to(corners[i]), i - 1 == 0, end_straight)
		var room_out := _turn_room(
			corners[i].distance_to(corners[i + 1]), i + 1 == last, end_straight
		)
		var half_tan := tan(turn / 2.0)
		var cut := minf(radius * half_tan, minf(room_in, room_out))
		var bend := cut / half_tan
		var start := corners[i] - into * cut
		var centre := start + (out_of - into * into.dot(out_of)).normalized() * bend
		var sign_up := signf(into.cross(out_of).y)
		var arms := maxi(1, ceili(turn * bend / step))
		out.append(start)
		for k in range(1, arms + 1):
			out.append(centre + (start - centre).rotated(Vector3.UP, sign_up * turn * k / arms))
	out.append(corners[last])
	return out


static func _turn_room(length: float, at_end: bool, end_straight: float) -> float:
	return maxf(length - end_straight, 0.0) if at_end else length / 2.0
