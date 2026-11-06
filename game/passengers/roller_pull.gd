class_name RollerPull
extends RefCounted
## Where a pulled roller's axle trails behind its walker, and how a roller is
## placed on it (CarryOnProps draws the bags; split out of carry_on_props.gd,
## board 79212dcd). The axle is TRAIL_M back along the line the body walked,
## kept on the pulling hand's side, and the drawn axle follows it at a limited
## speed in sim time (follow()).

## A pulled roller's axle trails this far behind the body's centre, measured
## back along the line the body walked (so it takes each corner where the body
## did and clears the heel of a long stride).
const TRAIL_M := 1.0
## The walked line it follows is this far out on the pulling hand's side, so
## the rods from the hand pass outside the thigh.
const TRAIL_SIDE_M := 0.3
## How far to the pulling hand's side the axle may be, from the body's centre
## line, and how far behind it at least: a walked line that kinks at each
## heading change (a diagonal zig-zag) puts the spot 1 m of walk back nearer
## than 1 m, and with the axle 0.28-0.30 m out an axle 0.85 m or less behind
## meets the trailing foot (windowed contact bench, 2026-10-29: none at 0.9 m).
const TRAIL_SIDE_MIN_M := 0.28
const TRAIL_SIDE_MAX_M := 0.6
const TRAIL_BEHIND_MIN_M := 0.95
## The drawn axle follows its place behind the body at a limited speed in sim
## time, round the pulling hand's side about the body's centre, at least
## SWING_RADIUS_M from it: when the place jumps (the body turned sharply, or
## walked back past its roller) the roller swings there, never in an instant.
## SWING_TURN is radians per tick, SWING_REACH_M metres per tick of radius.
const SWING_TURN := PI / 10.0
const SWING_REACH_M := 0.2
const SWING_RADIUS_M := 0.55
## The probe's snap threshold: a drawn axle moving more than this a sim tick
## (the walk is about 0.07 m a tick; a swing at most SWING_TURN of arc).
const SWING_JUMP_M := 0.6


## A roller pulled by its grip at `grip` with its axle at `axle` (on the floor,
## the wheels' radius up): its length along the line from the axle to the grip,
## its back panel (rods, wheels) down toward the walker: its front faces `ref`
## (up, or out to the side for one hung from the hand by its bar) as far as
## the line allows.
static func pulled(grip: Vector3, axle: Vector3, scale_by: float, ref := Vector3.UP) -> Transform3D:
	var along := (grip - axle).normalized()
	var up := ref - along * along.dot(ref)
	up = up.normalized() if up.length() > 0.001 else Vector3.BACK
	var basis := Basis(up.cross(along), up, along).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## How long a pulled roller's rods are (in its units) for its grip bar to be
## at `grip` with the axle at `axle`; `reach_base` is Pull_Reach's z in the bag.
static func pull_length(grip: Vector3, axle: Vector3, scale_by: float, reach_base: float) -> float:
	var past := reach_base + CarryOnProps.ROLLER_GRIP_PAST_TOP_M - CarryOnProps.ROLLER_AXLE.z
	return maxf(CarryOnProps.REACH_BUILT_M, grip.distance_to(axle) / scale_by - past)


## The point TRAIL_M back along `walked` (the body's positions, oldest first,
## the last one now); past the oldest it goes on straight, along the first
## step walked or along `back` before any step.
static func trail(walked: Array, back: Vector3) -> Vector3:
	var left := TRAIL_M
	var at: Vector3 = walked[-1]
	for i in range(walked.size() - 2, -1, -1):
		var step: Vector3 = walked[i] - at
		if step.length() >= left:
			return at + step.normalized() * left
		left -= step.length()
		at = walked[i]
	var on := back
	if walked.size() > 1:
		on = (walked[0] - walked[1]).normalized()
	return at + on * left


## The drawn axle `dt` sim ticks on from `at` toward `to`, both in the body's
## frame (x across, +z ahead): its angle about the body's centre turns at most
## SWING_TURN a tick, round the pulling hand's side (`hand` 0 right, 1 left),
## its distance changes at most SWING_REACH_M a tick and stays at least
## SWING_RADIUS_M, so it passes beside the body clear of the legs.
static func follow(at: Vector3, to: Vector3, dt: float, hand: int) -> Vector3:
	var out := -1.0 if hand == 0 else 1.0
	# Angle from straight behind (0) toward the hand's side (PI / 2).
	var a0 := atan2(at.x * out, -at.z)
	var a1 := atan2(to.x * out, -to.z)
	if a0 < -PI / 2.0:
		a0 += TAU
	var a := a0 + clampf(a1 - a0, -SWING_TURN * dt, SWING_TURN * dt)
	var r0 := Vector2(at.x, at.z).length()
	var r1 := Vector2(to.x, to.z).length()
	var r := maxf(r0 + clampf(r1 - r0, -SWING_REACH_M * dt, SWING_REACH_M * dt), SWING_RADIUS_M)
	return Vector3(out * r * sin(a), to.y, -r * cos(a))


## Moves a pulled roller's axle one tick on: TRAIL_M back along the line
## walked by a point TRAIL_SIDE_M out on the pulling hand's side of the body's
## tick position (tick_position, as drawn); any other bag has none.
static func step(
	props: CarryOnProps, bag: Dictionary, body: Node3D, id: int, home: SecurityLooks.Home, hand: int
) -> void:
	if bag["carry"] != SecurityLooks.Carry.PULL or home != SecurityLooks.Home.HAND:
		# Not pulled now: the next pull starts its follower afresh behind the
		# walker, not from wherever it was last drawn (perhaps metres back).
		for key in ["axle", "walked", "drawn_axle", "drawn_at", "axle_now"]:
			bag.erase(key)
		return
	var side := Vector3.LEFT if hand == 0 else Vector3.RIGHT
	# The heading the body is drawn with for this tick (PassengerViews.draw()
	# turns it to the step from the last tick position to this one).
	var at := props.views.tick_position(id, true)
	var step := at - props.views.tick_position(id, false)
	var yaw := atan2(step.x, step.z) if step.length() > 0.001 else body.rotation.y
	var turn := Basis(Vector3.UP, yaw)
	var now := at + turn * side * TRAIL_SIDE_M
	var walked: Array = bag.get("walked", [])
	if walked.is_empty() or (walked[-1] as Vector3).distance_to(now) > 0.01:
		walked.append(now)
	# Only as much of the walk as the trail needs.
	var length := 0.0
	for i in range(walked.size() - 1, 0, -1):
		length += (walked[i] as Vector3).distance_to(walked[i - 1])
		if length > TRAIL_M + 0.5:
			walked = walked.slice(i - 1)
			break
	var behind := turn * Vector3.FORWARD
	var cur := trail(walked, behind)
	if (cur - now).dot(behind) < 0.0:
		# The walker turned back past its roller (it is ahead now, not round a
		# corner beside it): the roller swings round behind it over the next
		# tick (drawn from where it was) rather than the walker crossing the
		# rods.
		walked = [now]
		cur = trail(walked, behind)
	bag["walked"] = walked
	# Kept behind the walker on the pulling hand's side, so the rods never
	# cross behind the legs to the other side (a zig-zag of diagonal steps
	# swings the walked line about the body's heading).
	var frame := Transform3D(turn, at)
	var local := frame.affine_inverse() * cur
	var out := -1.0 if hand == 0 else 1.0
	local.x = out * clampf(local.x * out, TRAIL_SIDE_MIN_M, TRAIL_SIDE_MAX_M)
	local.z = minf(local.z, -TRAIL_BEHIND_MIN_M)
	cur = frame * local
	bag["axle"] = [bag["axle"][1] if bag.has("axle") else cur, cur]


## A pulled roller's axle drawn now, on the floor under the body (the wheels'
## radius up), kept behind it on the pulling hand's side; straight behind the
## body before sync() has started one.
static func drawn(
	props: CarryOnProps, bag: Dictionary, body: Node3D, scale_by: float, hand: int
) -> Vector3:
	var at: Vector3
	if bag.has("axle"):
		var alpha := props.clock.alpha if props.clock != null else 1.0
		at = (bag["axle"][0] as Vector3).lerp(bag["axle"][1], alpha)
	else:
		at = body.global_position + Basis(Vector3.UP, body.rotation.y) * Vector3.FORWARD * TRAIL_M
	# Behind the body as drawn now, on the pulling hand's side: between two
	# ticks of a turning walker the blend can cross behind the legs.
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var local := frame.affine_inverse() * at
	var out := -1.0 if hand == 0 else 1.0
	local.x = out * clampf(local.x * out, TRAIL_SIDE_MIN_M, TRAIL_SIDE_MAX_M)
	local.z = minf(local.z, -TRAIL_BEHIND_MIN_M)
	var now := props._now()
	at = frame * local
	if bag.has("drawn_axle"):
		var was := frame.affine_inverse() * (bag["drawn_axle"] as Vector3)
		at = frame * follow(was, local, maxf(now - bag["drawn_at"], 0.0), hand)
	at.y = body.global_position.y + CarryOnProps.ROLLER_AXLE.y * scale_by
	bag["drawn_axle"] = at
	bag["drawn_at"] = now
	bag["follows"] = int(bag.get("follows", 0)) + 1
	return at
