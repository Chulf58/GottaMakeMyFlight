class_name Airside
extends Node3D
## The one runway and one stand, as Marker3D waypoints placed in the scene
## (named children, in this node's own space) plus the taxiway links between
## them. Builds the TaxiGraph and gives each flight phase its path. The stand
## moves with the terminal (ApronStand, decision plane-stand-design-airside-
## moves-110-m-north-stand-snaps-to): set_stand() puts Stand, PushbackEnd and
## StandLane (where the way north meets the taxi lane) where StandPlacement
## says and rebuilds the graph. With gate desks (decision gates-technical-
## design-gate-desks-link-to-north-exits-one-st, point 3) set_gate_stands()
## gives each gate its own Stand_<gate>, PushbackEnd_<gate> and
## StandLane_<gate>. Every StandLane waypoint sits on the one taxi lane, so
## the lane is a chain: TaxiWest, the StandLane waypoints and TaxiEast joined
## in order of x (links between two of them in `links` give way to it), and a
## plane taxis along it past the other gates' joins. While gates have stands
## the one stand's own StandLane is not on the chain. Also gives
## the two sky tracks views draw around a flight: the arrival lead-in into
## ApproachStart and the climb-out from ClimbEnd, each a flat track through its
## turn waypoints with wide round turns.
##
## Its TaxiPaving child paves every taxi route (taxi_routes()) after each
## rebuild, so the paving follows the stands (user ruling pave-the-taxi-lane-
## and-the-link-from-each-stand-to-it-so-pla).

const REQUIRED_WAYPOINTS: Array[StringName] = [
	&"ApproachStart",
	&"Touchdown",
	&"RunwayExit",
	&"Stand",
	&"PushbackEnd",
	&"StandLane",
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
## The taxi lane's two ends; with every StandLane waypoint they make the lane
## chain.
const LANE_ENDS: Array[StringName] = [&"TaxiWest", &"TaxiEast"]
const STAND_LANE := "StandLane"
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
## How many times set_stand() moved the stand, so a view holding paths read
## before (PlaneView) knows to read them again.
var stand_moves := 0
## Gate letter -> the stand its waypoints were last put at (set_gate_stands()).
var gate_stands: Dictionary = {}
## The asphalt under the taxi routes, rebuilt with the graph.
var paving := TaxiPaving.new()


func _init() -> void:
	add_child(paving)


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
		if ends.size() == 2 and _on_lane(ends[0]) and _on_lane(ends[1]):
			continue
		if ends.size() != 2 or not graph.link(StringName(ends[0]), StringName(ends[1])):
			push_error("Airside: bad link '%s'" % pair)
			ok = false
	for gate: String in gate_stands:
		graph.link(_gate_point(&"StandLane", gate), _gate_point(&"PushbackEnd", gate))
		graph.link(_gate_point(&"PushbackEnd", gate), _gate_point(&"Stand", gate))
	# With gate stands the one stand's StandLane is left off the chain: it would
	# sit on a gate's join (the starter exit's) and add a zero-length step.
	var chain: Array[StringName] = []
	for child in get_children():
		if child is Marker3D and _on_lane(child.name):
			if gate_stands.is_empty() or child.name != &"StandLane":
				chain.append(child.name)
	chain.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return graph.position_of(a).x < graph.position_of(b).x
	)
	for i in range(1, chain.size()):
		graph.link(chain[i - 1], chain[i])
	paving.show_routes(taxi_routes(), StandPlacement.TAXI_LANE_Z)
	return ok


## Every ground route a plane takes: taxi in, pushback and taxi out, for each
## gate with a stand, or for the one stand while no gate has one.
func taxi_routes() -> Array[PackedVector3Array]:
	var gates: Array = gate_stands.keys() if not gate_stands.is_empty() else [""]
	var out: Array[PackedVector3Array] = []
	for gate: String in gates:
		for state in [FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT]:
			out.append(phase_path(state, gate))
	return out


## Whether waypoint `waypoint` is on the taxi lane chain.
static func _on_lane(waypoint: String) -> bool:
	return LANE_ENDS.has(StringName(waypoint)) or waypoint.begins_with(STAND_LANE)


## The waypoint `base` (Stand, PushbackEnd or StandLane) of gate `gate`.
static func _gate_point(base: StringName, gate: String) -> StringName:
	return StringName("%s_%s" % [base, gate])


## Puts the stand waypoints at StandPlacement's `stand` and rebuilds the
## graph. False (with an error) when a stand waypoint is missing.
func set_stand(stand: Dictionary) -> bool:
	var points := {
		&"Stand": StandPlacement.stand_point(stand),
		&"PushbackEnd": StandPlacement.pushback_end(stand),
		&"StandLane": StandPlacement.lane_join(stand),
	}
	for waypoint: StringName in points:
		var marker := get_node_or_null(NodePath(String(waypoint))) as Marker3D
		if marker == null:
			push_error("Airside: missing waypoint '%s'" % waypoint)
			return false
		marker.position = transform.affine_inverse() * (points[waypoint] as Vector3)
	stand_moves += 1
	return rebuild()


## Gives each gate in `stands` (gate letter -> StandPlacement stand) its own
## stand waypoints, drops those of gates no longer listed and rebuilds the
## graph. Nothing changes when the stands are the ones already set.
func set_gate_stands(stands: Dictionary) -> bool:
	if stands == gate_stands:
		return true
	for gate: String in gate_stands:
		if not stands.has(gate):
			for base in [&"Stand", &"PushbackEnd", &"StandLane"]:
				var gone := get_node_or_null(NodePath(String(_gate_point(base, gate))))
				if gone != null:
					remove_child(gone)
					gone.free()
	for gate: String in stands:
		var stand: Dictionary = stands[gate]
		var points := {
			&"Stand": StandPlacement.stand_point(stand),
			&"PushbackEnd": StandPlacement.pushback_end(stand),
			&"StandLane": StandPlacement.lane_join(stand),
		}
		for base: StringName in points:
			var waypoint := _gate_point(base, gate)
			var marker := get_node_or_null(NodePath(String(waypoint))) as Marker3D
			if marker == null:
				marker = Marker3D.new()
				marker.name = waypoint
				add_child(marker)
			marker.position = transform.affine_inverse() * (points[base] as Vector3)
	gate_stands = stands.duplicate(true)
	stand_moves += 1
	return rebuild()


## The path a plane follows in `state`, or an empty array for a state that
## stays put. `gate` names the gate whose stand it uses; a gate with no stand
## waypoints of its own (no gate desks, one stand) uses Stand.
func phase_path(state: int, gate := "") -> PackedVector3Array:
	var stand := &"Stand"
	var pushback := &"PushbackEnd"
	if gate_stands.has(gate):
		stand = _gate_point(&"Stand", gate)
		pushback = _gate_point(&"PushbackEnd", gate)
	var path := PackedVector3Array()
	match state:
		FlightSim.State.APPROACH:
			path = _points([&"ApproachStart", &"Touchdown"])
		FlightSim.State.LANDING:
			path = _points([&"Touchdown", &"RunwayExit"])
		FlightSim.State.TAXI_IN:
			path = graph.route(&"RunwayExit", stand)
		FlightSim.State.PUSHBACK:
			path = _points([stand, pushback])
		FlightSim.State.TAXI_OUT:
			path = graph.route(pushback, &"RunwayEntry")
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
