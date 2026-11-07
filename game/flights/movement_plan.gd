class_name MovementPlan
extends RefCounted
## Where a plane is on the ground, as a pure function of its route and the
## ticks since its taxi phase began (decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, point 4). The sim and the
## views both read it, so a booking and the drawn plane agree. Pure and static.
##
## A taxi plan covers route R, of length D, in a budget of B ticks. With no
## pause the plane eases in and out over the whole budget (smoothstep), as it
## always has. A plan may hold one pause {"hold_s": metres along R, "ticks": p}:
## leg 1 eases from 0 to hold_s over T1, the plane stands at hold_s for p
## ticks, and leg 2 eases from hold_s to D over T2. Each leg starts and ends at
## zero speed. T1 and T2 split B - p in proportion to their lengths, so both
## legs peak at the same speed, 1.5 * D / (B - p).
##
## Not checked here: whether the pause sits on a hold line, or whether the
## route is clear. is_valid() checks only that the route has length, the
## pause's size and the peak speed.

## Distance around a path corner over which the heading turns.
const CORNER_BLEND := 8.0
## A pause is a whole number of these ticks.
const PAUSE_STEP_TICKS := 20
const MAX_PAUSE_TICKS := 160
## The fastest a taxiing plane may move, in metres per tick (16 m/s).
const MAX_PEAK_SPEED := 0.8


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


## Unit direction (flat) of the last segment with any length: the next phase's
## entry direction. A stationary route (no such segment) has none, which is
## reported, and gives Vector3.BACK.
static func exit_dir(points: PackedVector3Array) -> Vector3:
	for i in range(points.size() - 1, 0, -1):
		if points[i - 1].distance_to(points[i]) > 0.0:
			return flat_dir(points[i - 1], points[i])
	push_error("MovementPlan: exit_dir of a stationary route")
	return Vector3.BACK


## Flat unit heading `distance` along the path. It starts on `entry_dir` and
## turns smoothly through each corner; segments with no length are skipped. On
## a stationary route (no segment with length) it is `entry_dir`, flattened.
static func heading_at(points: PackedVector3Array, distance: float, entry_dir: Vector3) -> Vector3:
	var yaws: Array[float] = []
	var starts: Array[float] = []
	var run := 0.0
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if length <= 0.0:
			continue
		yaws.append(yaw_of(flat_dir(points[i - 1], points[i])))
		starts.append(run)
		run += length
	if yaws.is_empty():
		return flat_dir(Vector3.ZERO, entry_dir)
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
			else lerp_angle(yaw_of(entry_dir), yaw, ratio)
		)
	if seg + 1 < yaws.size() and to_end < CORNER_BLEND:
		yaw = lerp_angle(yaw, yaws[seg + 1], 0.5 - 0.5 * to_end / CORNER_BLEND)
	return Vector3(sin(yaw), 0.0, cos(yaw))


## Share of a leg covered `t` (0 to 1) through it: eases in and out.
static func fraction(t: float) -> float:
	return smoothstep(0.0, 1.0, t)


## Rate of fraction() over t.
static func fraction_rate(t: float) -> float:
	return 6.0 * t * (1.0 - t)


## The plan for a taxi phase along `route` lasting `budget` ticks, with an
## optional `pause` {"hold_s": metres along the route, "ticks": int}. An empty
## pause is no pause. Build it, then ask is_valid() whether it may fly.
static func taxi(route: PackedVector3Array, budget: float, pause := {}) -> Dictionary:
	var length := path_length(route)
	var plan := {
		"route": route,
		"length": length,
		"budget": budget,
		"hold_s": length,
		"pause_ticks": 0,
		"t1": budget,
		"t2": 0.0,
	}
	if pause.is_empty():
		return plan
	var hold_s: float = pause["hold_s"]
	var ticks: int = pause["ticks"]
	var moving := budget - ticks
	plan["hold_s"] = hold_s
	plan["pause_ticks"] = ticks
	plan["t1"] = moving * hold_s / length if length > 0.0 else 0.0
	plan["t2"] = moving - plan["t1"]
	return plan


## Metres along the route `elapsed` ticks into the plan, clamped to the budget.
static func distance_at(plan: Dictionary, elapsed: float) -> float:
	var e := clampf(elapsed, 0.0, plan["budget"])
	var t1: float = plan["t1"]
	var hold_s: float = plan["hold_s"]
	if e < t1:
		return hold_s * fraction(e / t1)
	var after: float = e - t1 - plan["pause_ticks"]
	if after <= 0.0:
		return hold_s
	var t2: float = plan["t2"]
	if t2 <= 0.0:
		return plan["length"]
	return hold_s + (plan["length"] - hold_s) * fraction(after / t2)


## The point on the route `elapsed` ticks into the plan.
static func position_at(plan: Dictionary, elapsed: float) -> Vector3:
	return point_at(plan["route"], distance_at(plan, elapsed))


## The fastest the plan moves, in metres per tick: each leg's smoothstep peaks
## at 1.5 times its mean speed, and both legs share the mean D / (B - p).
static func peak_speed(plan: Dictionary) -> float:
	var moving: float = plan["budget"] - plan["pause_ticks"]
	return 1.5 * plan["length"] / moving if moving > 0.0 else INF


## Whether the plan may fly: the route has length (a stationary route is not
## a taxi), the pause is 0 to MAX_PAUSE_TICKS in whole PAUSE_STEP_TICKS, its
## hold lies on the route, and the peak speed is at most MAX_PEAK_SPEED.
static func is_valid(plan: Dictionary) -> bool:
	if plan["length"] <= 0.0:
		return false
	var ticks: int = plan["pause_ticks"]
	var hold_s: float = plan["hold_s"]
	if ticks < 0 or ticks > MAX_PAUSE_TICKS or ticks % PAUSE_STEP_TICKS != 0:
		return false
	if hold_s < 0.0 or hold_s > plan["length"]:
		return false
	return peak_speed(plan) <= MAX_PEAK_SPEED


static func flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat.normalized() if flat.length_squared() > 0.0 else Vector3.BACK


static func yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)
