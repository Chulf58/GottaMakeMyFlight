class_name Airside
extends Node3D
## The one runway and one stand, as Marker3D waypoints placed in the scene
## (named children, in this node's own space) plus the taxiway links between
## them. Keeps the waypoints in its TaxiGraph and gives each flight phase its
## path from TaxiRoutes, the one route source FlightGround plans on. The stand
## moves with the terminal (ApronStand, decision plane-stand-design-airside-
## moves-110-m-north-stand-snaps-to): set_stand() puts Stand, PushbackEnd and
## StandLane (where the way north meets the taxi lane) where StandPlacement
## says and rebuilds the graph. With gate desks (decision gates-technical-
## design-gate-desks-link-to-north-exits-one-st, point 3) set_gate_stands()
## gives each gate its own Stand_<gate>, PushbackEnd_<gate> and
## StandLane_<gate>. Every StandLane waypoint sits on the one taxi lane
## between TaxiWest and TaxiEast, or, for a west or east stand, on the spur
## that runs south from the lane at the stand's lane_x, TaxiWest's or
## TaxiEast's x or farther out (board airside-all-around-s4, lane_layout()).
## Planes land and take off eastbound, leave the runway at its east end and
## join it again at its west end, so every taxi route runs strictly west along
## the lane (decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses, point 1). A join east of TaxiEast or west of
## TaxiWest would break that, and rebuild() refuses it, as it refuses a join on
## neither the lane nor a spur (TaxiRoutes.joins_lane()). While gates have
## stands the one stand's own StandLane is not checked.
##
## Touchdown, Liftoff and ApproachStart are per plane class, never per runway
## size (same decision, point 1): the medium class (the reference model 05)
## uses the markers of those names, and the small and large classes their
## _small and _large markers (CLASS_SUFFIX). HoldIn and HoldRunway are the
## hold lines on the two stubs between runway and lane (point 4): a plane
## stopped on one keeps the reference footprint clear of the runway band.
## They are waypoints off every route; GroundPlanner's planned pauses stop on
## them.
##
## Also gives the two sky tracks views draw around a flight: the arrival
## lead-in into the class's ApproachStart and the climb-out from ClimbEnd, each
## a flat track through its turn waypoints with wide round turns.
##
## Its TaxiPaving child paves every taxi route (taxi_routes()) after each
## rebuild, with a pad at every stand in use (stand_points()) and a hold bar at
## every hold line (hold_points()), so the paving follows the stands (user
## ruling pave-the-taxi-lane-and-the-link-from-each-stand-to-it-so-pla).

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
	&"ApproachStart_small",
	&"ApproachStart_large",
	&"Touchdown_small",
	&"Touchdown_large",
	&"Liftoff_small",
	&"Liftoff_large",
	&"HoldIn",
	&"HoldRunway",
	&"TaxiWest",
	&"TaxiEast",
]
## Plane class -> the suffix of its Touchdown, Liftoff and ApproachStart
## markers. Medium, the class StandPlacement's footprint is built around, uses
## the unsuffixed ones.
const CLASS_SUFFIX := {
	PlaneClasses.SMALL: "_small",
	PlaneClasses.MEDIUM: "",
	PlaneClasses.LARGE: "_large",
}
## The sky tracks' turn waypoints before the class's ApproachStart. Only their
## x and z count: FlightPose sets the height above the join (ApproachStart or
## ClimbEnd).
const LEAD_IN_WAYPOINTS: Array[StringName] = [
	&"ArrivalEntry", &"ArrivalPass", &"ArrivalTurnWest", &"ArrivalTurnNorth"
]
const CLIMB_OUT_WAYPOINTS: Array[StringName] = [&"ClimbEnd", &"DepartureTurn", &"DepartureExit"]
## The taxi lane's two ends; every StandLane waypoint lies between them.
const LANE_ENDS: Array[StringName] = [&"TaxiWest", &"TaxiEast"]
const STAND_LANE := "StandLane"
## The runway's strip piece, whose width runway_south() reads.
const RUNWAY_PIECE := "tp_runway_03a"
## Turn radius of the sky tracks, in metres. A corner too tight for it gets the
## widest turn that fits.
const SKY_TURN_RADIUS := 160.0
## Straight flight kept at each end of a sky track, so the bank rolls out
## before the join.
const SKY_END_STRAIGHT := 45.0
## Arc length between the points that sample a turn.
const SKY_ARC_STEP := 4.0

## Taxiways as "From>To" waypoint pairs, as main.tscn declares them. rebuild()
## checks that each names two waypoints; the routes come from TaxiRoutes.
@export var links := PackedStringArray()

var graph := TaxiGraph.new()
## How many times set_stand() moved the stand, so a view holding paths read
## before (PlaneView) knows to read them again.
var stand_moves := 0
## The stand set_stand() last put the one stand's waypoints at, {} for the
## scene's own (a north stand): its side and spur pick its routes.
var one_stand: Dictionary = {}
## Gate letter -> the stand its waypoints were last put at (set_gate_stands()).
var gate_stands: Dictionary = {}
## Gate letter -> its max_class, which sizes its stand pad (set_gate_classes()).
var gate_classes: Dictionary = {}
## The asphalt under the taxi routes, rebuilt with the graph.
var paving := TaxiPaving.new()
## The jet bridges and taxi signs (board 4c08b8e5), laid out with the paving.
var props := AirsideProps.new()
## Whether the last rebuild() succeeded. set_gate_stands() skips a call with
## the stands already set only while it did, so a failed call fails again.
var _built := false
## Whether the last rebuild() succeeded in full: every required waypoint, every
## link and every stand's join on the lane; phase_path() gives no taxi route
## while it did not.
var _routable := false


func _init() -> void:
	add_child(paving)
	add_child(props)


func _ready() -> void:
	rebuild()


## Rebuilds the waypoints from the Marker3D children. False (with an error)
## when a required waypoint is missing, a link names an unknown waypoint or a
## stand's join is off the lane.
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
		var known := (
			ends.size() == 2
			and graph.has_waypoint(StringName(ends[0]))
			and graph.has_waypoint(StringName(ends[1]))
		)
		if not known:
			push_error("Airside: bad link '%s'" % pair)
			ok = false
	_routable = ok and _joins_on_lane()
	_show_paving()
	_built = _routable
	return _routable


## Sizes each gate's stand pad for the classes up to its max_class (gate letter ->
## GateDesks.max_class, "" for none) and repaves when that changed. ApronStand
## sends it on every refresh of the gates.
func set_gate_classes(classes: Dictionary) -> void:
	if classes == gate_classes:
		return
	gate_classes = classes.duplicate()
	if _built:
		_show_paving()


func _show_paving() -> void:
	paving.show_routes(
		taxi_routes(),
		StandPlacement.TAXI_LANE_Z,
		stand_pads(),
		hold_points(),
		runway_south(),
		stand_points()
	)
	props.show_layout(gate_stands, taxi_routes())


## The pad under every stand in use (TaxiPaving.stand_pad()): a gate's for the
## classes up to its gate_classes entry, none for a gate with no class; every
## class's for a gate with no entry and for the one stand, which no gate sizes.
## A west or east gate's is its north twin's turned (TaxiPaving.pad_for()).
func stand_pads() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var points := stand_points()
	var gates := gate_stands.keys()
	for i in points.size():
		var classes := PlaneClasses.ORDER
		if i < gates.size() and gate_classes.has(gates[i]):
			classes = classes_up_to(gate_classes[gates[i]])
		if classes.is_empty():
			continue
		var side := StandPlacement.NORTH
		if i < gates.size():
			side = StandPlacement.side_of(gate_stands[gates[i]])
		if side != StandPlacement.NORTH:
			out.append(TaxiPaving.pad_for(gate_stands[gates[i]], classes))
		else:
			out.append(TaxiPaving.stand_pad(points[i], classes))
	return out


## The plane classes from small up to `largest`, or none for "" or an unknown class.
static func classes_up_to(largest: String) -> Array[String]:
	var out: Array[String] = []
	var rank := PlaneClasses.ORDER.find(largest)
	for i in rank + 1:
		out.append(PlaneClasses.ORDER[i])
	return out


## The south edge of the runway's asphalt: the runway pieces are RUNWAY_PIECE's
## width (PlaneModels.PIECES) about StandPlacement.RUNWAY_Z.
static func runway_south() -> float:
	var piece: AABB = PlaneModels.PIECES[RUNWAY_PIECE]["aabb"]
	return StandPlacement.RUNWAY_Z + piece.end.z


## The plane point of every stand in use: each gate's, or the one stand's while
## no gate has one.
func stand_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if gate_stands.is_empty():
		if graph.has_waypoint(&"Stand"):
			out.append(graph.position_of(&"Stand"))
		return out
	for gate: String in gate_stands:
		out.append(graph.position_of(_gate_point(&"Stand", gate)))
	return out


## The hold lines a plane may stop on (decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, point 4): HoldIn and
## HoldRunway on the stubs, then the lead-in hold of each stand in use whose
## pushback ends far enough from its lane or spur to have one (stand_hold();
## the one stand is a north stand, lead_in_hold()), then the west spur head
## (spur_head_hold()) while a west gate stand is in use. No route runs on the
## lane past the east spur's head, so it has no hold line.
func hold_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for waypoint in [&"HoldIn", &"HoldRunway"]:
		if graph.has_waypoint(waypoint):
			out.append(graph.position_of(waypoint))
	if gate_stands.is_empty():
		if graph.has_waypoint(&"PushbackEnd"):
			out.append_array(lead_in_hold(graph.position_of(&"PushbackEnd")))
		return out
	var head := PackedVector3Array()
	for gate: String in gate_stands:
		var stand: Dictionary = gate_stands[gate]
		out.append_array(stand_hold(stand))
		if StandPlacement.side_of(stand) == StandPlacement.WEST and head.is_empty():
			head.append(spur_head_hold(StandPlacement.lane_join(stand)))
	out.append_array(head)
	return out


## The lead-in hold line H_g of `stand` as [point] or []: lead_in_hold() at a
## north stand; at a west or east stand its north twin's turned onto it
## (StandPlacement.to_world()), on the connector from the pushback's end to the
## spur, as far from the spur as the north one is from the lane.
static func stand_hold(stand: Dictionary) -> PackedVector3Array:
	if StandPlacement.side_of(stand) == StandPlacement.NORTH:
		return lead_in_hold(StandPlacement.pushback_end(stand))
	var twin := lead_in_hold(StandPlacement.pushback_end(StandPlacement.north_twin(stand)))
	if twin.is_empty():
		return twin
	return PackedVector3Array([StandPlacement.to_world(stand, twin[0])])


## The hold line on the lane at the head of the spur whose stand join is
## `join`: a plane taxiing toward the spur stops there with every class's door-
## aligned nose clear of the spur band, the same distance (lead_in_hold_z()
## from the lane) that a lead-in hold keeps from the lane. An inbound plane to a
## west stand waits on it for the spur; at the east spur it would lie on no
## route.
static func spur_head_hold(join: Vector3) -> Vector3:
	var clear := lead_in_hold_z() - StandPlacement.TAXI_LANE_Z
	var inward := 1.0 if join.x < 0.0 else -1.0
	return Vector3(join.x + inward * clear, join.y, StandPlacement.TAXI_LANE_Z)


## The hold line H_g on the lead-in from the pushback's end at `pushback_end`
## north to the lane, as [point] or [] when there is none: the point where a
## plane heading north stops with the nose of every class's door-aligned model
## (PlaneClasses.stand_offset) south of the lane band (StandEnvelope.
## lane_band_south()). There is none when the pushback ends at or north of it,
## as on the north row. The paving draws it and GroundPlanner pauses on it.
static func lead_in_hold(pushback_end: Vector3) -> PackedVector3Array:
	var hold_z := lead_in_hold_z()
	if pushback_end.z <= hold_z:
		return PackedVector3Array()
	return PackedVector3Array([Vector3(pushback_end.x, pushback_end.y, hold_z)])


## The z of every lead-in hold line (lead_in_hold()): the lane band's south
## edge plus the farthest any model's door-aligned nose reaches ahead of its
## pose point.
static func lead_in_hold_z() -> float:
	var reach := 0.0
	for model: String in PlaneModels.PLANES:
		var shape: Dictionary = PlaneModels.PLANES[model]
		reach = maxf(reach, PlaneClasses.stand_offset(model).z + float(shape["nose"]))
	return StandEnvelope.lane_band_south() + reach


## Whether every join lies strictly between the lane's ends or on a spur
## (TaxiRoutes.joins_lane(), with an error naming the first that does not;
## the message names the lane's ends, where the spurs run south). With gate
## stands the one stand's StandLane is not checked: it sits on a gate's join
## (the starter exit's).
func _joins_on_lane() -> bool:
	var layout := lane_layout()
	for child in get_children():
		if not (child is Marker3D and _on_lane(child.name) and not LANE_ENDS.has(child.name)):
			continue
		if not gate_stands.is_empty() and child.name == &"StandLane":
			continue
		var join := graph.position_of(child.name)
		if not TaxiRoutes.joins_lane(join, layout):
			push_error(
				(
					"Airside: '%s' at x %.2f is not strictly between the stubs (%.2f to %.2f)"
					% [child.name, join.x, layout["stub_west_x"], layout["stub_east_x"]]
				)
			)
			return false
	return true


## The lane layout the joins are checked on (TaxiRoutes): the north lane between
## TaxiWest and TaxiEast, run on west and east to the spurs of the stands in
## use (each west or east stand's lane_x; decision side-spur-move-design-s7-
## stands-carry-lane-x-the-wanted-spur), with a spur south from each end. A
## side stand on another spur than the outermost of its side is then off the
## lane, and refused.
func lane_layout() -> Dictionary:
	var layout := TaxiRoutes.north_only(graph.points())
	var stands: Array = gate_stands.values() if not gate_stands.is_empty() else [one_stand]
	for stand: Dictionary in stands:
		match StandPlacement.side_of(stand):
			StandPlacement.WEST:
				layout["west_x"] = minf(layout["west_x"], StandPlacement.lane_x_of(stand))
			StandPlacement.EAST:
				layout["east_x"] = maxf(layout["east_x"], StandPlacement.lane_x_of(stand))
	return layout


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
	one_stand = stand.duplicate()
	stand_moves += 1
	return rebuild()


## Gives each gate in `stands` (gate letter -> StandPlacement stand) its own
## stand waypoints, drops those of gates no longer listed and rebuilds the
## graph. Nothing changes when the stands are the ones already set and the
## last rebuild succeeded.
func set_gate_stands(stands: Dictionary) -> bool:
	if stands == gate_stands and _built:
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


## The path a plane of `plane_class` follows in `state`, or an empty array
## for a state that stays put. `gate` names the gate whose stand it uses; a
## gate with no stand waypoints of its own uses Stand. The path is TaxiRoutes',
## from this node's waypoints and the gate's Stand, PushbackEnd and StandLane.
## The class picks the approach, touchdown and liftoff points; the taxi routes
## are the same for every class. Empty for every state while a required
## waypoint is missing, and for the taxi routes while routes_gate() is false.
func phase_path(state: int, gate := "", plane_class := PlaneClasses.MEDIUM) -> PackedVector3Array:
	for waypoint in REQUIRED_WAYPOINTS:
		if not graph.has_waypoint(waypoint):
			return PackedVector3Array()
	var taxi := state == FlightSim.State.TAXI_IN or state == FlightSim.State.TAXI_OUT
	if taxi and not routes_gate(gate):
		return PackedVector3Array()
	var gate_name := gate if gate_stands.has(gate) else ""
	var ends := {
		"spot": graph.position_of(_stand_point(&"Stand", gate_name)),
		"back": graph.position_of(_stand_point(&"PushbackEnd", gate_name)),
		"join": graph.position_of(_stand_point(&"StandLane", gate_name)),
	}
	ends.merge(TaxiRoutes.spur_ends(gate_stands.get(gate_name, one_stand)))
	var paths := TaxiRoutes.phase_paths(graph.points(), ends, plane_class, lane_layout())
	return paths.get(state, PackedVector3Array())


## Whether phase_path() gives gate `gate` its taxi routes: the last rebuild()
## succeeded (every required waypoint, every link, every join on the lane), and
## the gate has a stand of its own, or no gate has one (no gate desks: the one
## stand serves every gate). With gate stands set, a gate not among them gets
## none, so a plane is never drawn along a stand nobody planned it for.
func routes_gate(gate: String) -> bool:
	return _routable and (gate_stands.is_empty() or gate_stands.has(gate))


## The waypoint `base` of gate `gate`'s stand, or of the one stand for "".
static func _stand_point(base: StringName, gate: String) -> StringName:
	return _gate_point(base, gate) if gate != "" else base


## The marker `base` (Touchdown, Liftoff or ApproachStart) of `plane_class`.
## An unknown class is an error and gets the medium marker.
static func class_point(base: StringName, plane_class: String) -> StringName:
	if not CLASS_SUFFIX.has(plane_class):
		push_error("Airside: '%s' is not a plane class" % plane_class)
		return base
	return StringName(String(base) + CLASS_SUFFIX[plane_class])


func _points(names: Array[StringName]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for waypoint in names:
		out.append(graph.position_of(waypoint))
	return out


## The arrival's flat track, ending at the class's ApproachStart on the
## approach heading. Every point has that ApproachStart's height.
func lead_in_track(plane_class := PlaneClasses.MEDIUM) -> PackedVector3Array:
	var approach := class_point(&"ApproachStart", plane_class)
	var names := LEAD_IN_WAYPOINTS.duplicate()
	names.append(approach)
	return _sky_track(names, graph.position_of(approach).y)


## The short straight-in on the runway's extended centreline, ending at the
## class's ApproachStart, for an arrival listed too late for the full lead-in.
## Every point has that ApproachStart's height.
func straight_in_track(plane_class := PlaneClasses.MEDIUM) -> PackedVector3Array:
	var approach := class_point(&"ApproachStart", plane_class)
	return _sky_track([&"ArrivalStraightIn", approach], graph.position_of(approach).y)


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
