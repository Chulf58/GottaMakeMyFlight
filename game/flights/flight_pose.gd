class_name FlightPose
extends RefCounted
## Where a plane is and how it sits, as a pure function of a flight state, the
## progress through that state and the state's path. The plane's local +Z is
## its nose. Used by views only; the sim never reads it.

## Distance around a path corner over which the heading turns.
const CORNER_BLEND := 8.0
const APPROACH_PITCH := deg_to_rad(-4.0)
const FLARE_PITCH := deg_to_rad(2.0)
const CLIMB_PITCH := deg_to_rad(12.0)
const PUSHBACK_SWING_START := 0.3


static func path_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## The point `distance` along the path, clamped to its ends.
static func point_at(points: PackedVector3Array, distance: float) -> Vector3:
	var remaining := maxf(distance, 0.0)
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if remaining <= length:
			return points[i - 1].lerp(points[i], remaining / length if length > 0.0 else 0.0)
		remaining -= length
	return points[points.size() - 1]


## Unit direction (flat) of the last segment: the next phase's entry direction.
static func exit_dir(points: PackedVector3Array) -> Vector3:
	return _flat_dir(points[points.size() - 2], points[points.size() - 1])


## Flat unit heading `distance` along the path. It starts on `entry_dir` and
## turns smoothly through each corner.
static func heading_at(points: PackedVector3Array, distance: float, entry_dir: Vector3) -> Vector3:
	var yaws: Array[float] = []
	var starts: Array[float] = []
	var run := 0.0
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if length <= 0.0:
			continue
		yaws.append(_yaw_of(_flat_dir(points[i - 1], points[i])))
		starts.append(run)
		run += length
	var seg := starts.size() - 1
	while seg > 0 and starts[seg] > distance:
		seg -= 1
	var at := clampf(distance, 0.0, run)
	var from_start := at - starts[seg]
	var to_end := (starts[seg + 1] if seg + 1 < starts.size() else run) - at
	var yaw := yaws[seg]
	if from_start < CORNER_BLEND:
		var ratio := from_start / CORNER_BLEND
		yaw = (
			lerp_angle(yaws[seg - 1], yaw, 0.5 + 0.5 * ratio)
			if seg > 0
			else lerp_angle(_yaw_of(entry_dir), yaw, ratio)
		)
	if seg + 1 < yaws.size() and to_end < CORNER_BLEND:
		yaw = lerp_angle(yaw, yaws[seg + 1], 0.5 - 0.5 * to_end / CORNER_BLEND)
	return Vector3(sin(yaw), 0.0, cos(yaw))


## The plane's transform `progress` (0 to 1) through `state` along `points`,
## entering with its nose along `entry_dir`.
static func pose(
	state: int, progress: float, points: PackedVector3Array, entry_dir: Vector3
) -> Transform3D:
	var t := clampf(progress, 0.0, 1.0)
	var distance := path_length(points) * _distance_fraction(state, t)
	var heading := heading_at(points, distance, entry_dir)
	if state == FlightSim.State.PUSHBACK:
		var swing := smoothstep(PUSHBACK_SWING_START, 1.0, t)
		var yaw := lerp_angle(_yaw_of(entry_dir), _yaw_of(exit_dir(points)), swing)
		heading = Vector3(sin(yaw), 0.0, cos(yaw))
	var basis := Basis(Vector3.UP, _yaw_of(heading)) * Basis(Vector3.RIGHT, -_pitch(state, t))
	return Transform3D(basis, point_at(points, distance))


static func _distance_fraction(state: int, t: float) -> float:
	match state:
		FlightSim.State.LANDING:
			return 1.0 - (1.0 - t) * (1.0 - t)
		FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT, FlightSim.State.PUSHBACK:
			return smoothstep(0.0, 1.0, t)
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


static func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat.normalized() if flat.length_squared() > 0.0 else Vector3.BACK


static func _yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)
