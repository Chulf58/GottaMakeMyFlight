class_name FlightPose
extends RefCounted
## Where a plane is and how it sits, as a pure function of a flight state, the
## progress through that state and the state's path. The plane's local +Z is
## its nose. Used by views only; the sim never reads it. The ground phases'
## distance and heading come from MovementPlan, which the sim may read, so a
## drawn plane is where the plan says; this file adds the pitch, the pushback
## swing and the sky poses.

const APPROACH_PITCH := deg_to_rad(-4.0)
const FLARE_PITCH := deg_to_rad(2.0)
const CLIMB_PITCH := deg_to_rad(12.0)
const PUSHBACK_SWING_START := 0.3
## The ground phases, whose distance comes from a MovementPlan taxi plan.
const GROUND_STATES: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]
## The sky phases views draw around a flight: the arrival lead-in that ends
## where APPROACH begins and the climb-out that begins where TAKEOFF ends. Each
## flies a flat track (Airside.lead_in_track, climb_out_track) whose height is
## the join's; above it the plane rises toward SKY_CEILING, leaving the join on
## the joining phase's pitch.
const SKY_CEILING := 120.0
## Span on either side of a point over which the sky heading is read.
const SKY_HEADING_SPAN := 2.0
## Span on either side of a point over which the turn rate is read for the
## bank, so the plane rolls into and out of a turn over about 2 * 20 m.
const BANK_SPAN := 20.0
## Bank in radians per radian of heading change per metre: a 160 m turn banks
## about 11 degrees.
const BANK_PER_TURN_RATE := 30.0
const MAX_BANK := deg_to_rad(20.0)


## MovementPlan.path_length(), kept here for the callers that read it here.
static func path_length(points: PackedVector3Array) -> float:
	return MovementPlan.path_length(points)


## MovementPlan.point_at(), kept here for the callers that read it here.
static func point_at(points: PackedVector3Array, distance: float) -> Vector3:
	return MovementPlan.point_at(points, distance)


## MovementPlan.exit_dir(), kept here for the callers that read it here.
static func exit_dir(points: PackedVector3Array) -> Vector3:
	return MovementPlan.exit_dir(points)


## The plane's transform `progress` (0 to 1) through `state` along `points`,
## entering with its nose along `entry_dir`. A ground state (GROUND_STATES)
## may take a MovementPlan `pause` ({"hold_s", "ticks"}) inside a state that
## lasts `budget` ticks; with no pause the budget does not matter.
static func pose(
	state: int,
	progress: float,
	points: PackedVector3Array,
	entry_dir: Vector3,
	pause := {},
	budget := 1.0
) -> Transform3D:
	var t := clampf(progress, 0.0, 1.0)
	var distance := 0.0
	if GROUND_STATES.has(state):
		distance = MovementPlan.distance_at(MovementPlan.taxi(points, budget, pause), t * budget)
	else:
		if not pause.is_empty():
			push_error("FlightPose: a pause on state %d, which is not a ground state" % state)
		distance = path_length(points) * _distance_fraction(state, t)
	var heading := MovementPlan.heading_at(points, distance, entry_dir)
	if state == FlightSim.State.PUSHBACK:
		var swing := smoothstep(PUSHBACK_SWING_START, 1.0, t)
		var yaw := lerp_angle(_yaw_of(entry_dir), _yaw_of(exit_dir(points)), swing)
		heading = Vector3(sin(yaw), 0.0, cos(yaw))
	var basis := Basis(Vector3.UP, _yaw_of(heading)) * Basis(Vector3.RIGHT, -_pitch(state, t))
	return Transform3D(basis, point_at(points, distance))


## The arrival lead-in `distance` along its flat `track`. It ends on the
## track's last point at the approach pitch, descending.
static func lead_in_pose(track: PackedVector3Array, distance: float) -> Transform3D:
	var to_join := path_length(track) - distance
	return _sky_pose(track, distance, to_join, tan(-APPROACH_PITCH), -1.0)


## The climb-out `distance` along its flat `track`. It starts on the track's
## first point at the climb pitch.
static func climb_out_pose(track: PackedVector3Array, distance: float) -> Transform3D:
	return _sky_pose(track, distance, distance, tan(CLIMB_PITCH), 1.0)


## Height above a sky track's join `from_join` metres from it: rises from 0 on
## `join_slope` and eases toward SKY_CEILING. Returns (height, slope).
static func sky_rise(base_height: float, from_join: float, join_slope: float) -> Vector2:
	var room := SKY_CEILING - base_height
	if room <= 0.0:
		return Vector2.ZERO
	var fade := exp(-join_slope * maxf(from_join, 0.0) / room)
	return Vector2(room * (1.0 - fade), join_slope * fade)


## Flat unit heading along a sky track, read across SKY_HEADING_SPAN on either
## side, so it turns smoothly through the sampled arcs.
static func track_heading(track: PackedVector3Array, distance: float) -> Vector3:
	return MovementPlan.flat_dir(
		point_at(track, distance - SKY_HEADING_SPAN), point_at(track, distance + SKY_HEADING_SPAN)
	)


## Heading change in radians per metre around `distance` (positive turns the
## nose toward +X from +Z), read across BANK_SPAN on either side.
static func turn_rate(track: PackedVector3Array, distance: float) -> float:
	var length := path_length(track)
	var from := clampf(distance - BANK_SPAN, 0.0, length)
	var to := clampf(distance + BANK_SPAN, 0.0, length)
	if to <= from:
		return 0.0
	var turn := angle_difference(
		_yaw_of(track_heading(track, from)), _yaw_of(track_heading(track, to))
	)
	return turn / (to - from)


## Flat speed in metres per tick `progress` through `state` along `points`,
## when the state lasts `ticks`: what a sky phase must fly at to join it.
static func flat_speed(
	state: int, progress: float, points: PackedVector3Array, ticks: float
) -> float:
	if ticks <= 0.0:
		return 0.0
	var t := clampf(progress, 0.0, 1.0)
	var length := path_length(points)
	var distance := length * _distance_fraction(state, t)
	return _fraction_rate(state, t) * length / ticks * _flat_share(points, distance)


static func _sky_pose(
	track: PackedVector3Array, distance: float, from_join: float, join_slope: float, climb: float
) -> Transform3D:
	var at := clampf(distance, 0.0, path_length(track))
	var rise := sky_rise(track[0].y, from_join, join_slope)
	var yaw := _yaw_of(track_heading(track, at))
	var pitch := climb * atan(rise.y)
	var roll := -clampf(BANK_PER_TURN_RATE * turn_rate(track, at), -MAX_BANK, MAX_BANK)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(basis, point_at(track, at) + Vector3.UP * rise.x)


## Share of the path's length that is flat, on the segment `distance` lies on.
static func _flat_share(points: PackedVector3Array, distance: float) -> float:
	var remaining := maxf(distance, 0.0)
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if length <= 0.0:
			continue
		if remaining <= length or i == points.size() - 1:
			var flat := Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z)
			return flat.length() / length
		remaining -= length
	return 1.0


## Rate of _distance_fraction over progress.
static func _fraction_rate(state: int, t: float) -> float:
	match state:
		FlightSim.State.LANDING:
			return 2.0 * (1.0 - t)
		FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT, FlightSim.State.PUSHBACK:
			return MovementPlan.fraction_rate(t)
		FlightSim.State.TAKEOFF:
			return 2.0 * t
	return 1.0


static func _distance_fraction(state: int, t: float) -> float:
	match state:
		FlightSim.State.LANDING:
			return 1.0 - (1.0 - t) * (1.0 - t)
		FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT, FlightSim.State.PUSHBACK:
			return MovementPlan.fraction(t)
		FlightSim.State.TAKEOFF:
			return t * t
	return t


## Nose-up angle in radians: nose-down on approach, a flare on landing, a
## rotation after the takeoff roll.
static func _pitch(state: int, t: float) -> float:
	match state:
		FlightSim.State.APPROACH:
			return APPROACH_PITCH
		FlightSim.State.LANDING:
			if t < 0.15:
				return lerpf(APPROACH_PITCH, FLARE_PITCH, t / 0.15)
			return lerpf(FLARE_PITCH, 0.0, smoothstep(0.15, 0.5, t))
		FlightSim.State.TAKEOFF:
			return CLIMB_PITCH * smoothstep(0.55, 0.85, t)
	return 0.0


static func _yaw_of(dir: Vector3) -> float:
	return MovementPlan.yaw_of(dir)
