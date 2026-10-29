class_name CarryMoves
extends RefCounted
## The paths of carry-on bags moving between homes (CarryOnProps' transfer
## moves) that keep clear of the walker's own body (board item pre-existing-
## carry-self-clips-found-by-game-spike-basic-scan). Pure: every transform is
## in the body's frame (x across, +z ahead).
##
## The overhead route (carry-on-bag-kinds-as-built) takes a roller between
## the pull and the hand over the head, along the body's centre plane. A
## roller held in the hand at one end of it goes through a gate in front of the
## body, at that end's own side and height, before it crosses in to the centre
## plane (rising) or after it leaves it (coming down): taken straight in from
## the side it went through the holding arm, and with its origin just behind
## the body it went up the back of the head. A bag picked up from the floor
## ahead of the walker rises ahead of the stepping knee, swings out to its
## hand's side and comes back along the outside of the thigh (pick_up()).

## A gate puts the bag's nearest face this far ahead of the body's centre:
## past the thighs and a stepping knee (body points reach 0.27 m ahead at hip
## height, about 0.4 m at the knee in a stride) and a swinging hand.
const FRONT_CLEAR_M := 0.42
## A bag picked up from a floor spot this far or more ahead of the body takes
## pick_up()'s path.
const PICK_FROM_AHEAD_M := 0.3


## The overhead route at `k` (0 to 1) from `from` to `to`, down by `land` (it
## then waits there, turned): it rises in front of or behind the body, crosses
## over the head with its lowest point (of `box`, the bag's bounds in its own
## frame) at CarryOnProps.OVERHEAD_M, turning there, and comes down on the other side. An
## end held in the hand (`from_hand`, `to_hand`) is joined through its gate().
static func overhead(
	from: Transform3D,
	to: Transform3D,
	k: float,
	box: AABB,
	land := 1.0,
	from_hand := false,
	to_hand := false
) -> Transform3D:
	# It turns only while it is up over the head: rising and coming down it
	# keeps its start and end pose, so it swings into nothing beside the body.
	var turned := clampf(k * 3.0 - 1.0, 0.0, 1.0)
	var turn := from.basis.get_rotation_quaternion().slerp(
		to.basis.get_rotation_quaternion(), turned
	)
	var basis := Basis(turn).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), turned))
	var lowest := INF
	for i in 8:
		lowest = minf(lowest, (basis * box.get_endpoint(i)).y)
	var high := CarryOnProps.OVERHEAD_M - lowest
	var rise_gate := gate(from, box) if from_hand else from.origin
	var fall_gate := gate(to, box) if to_hand else to.origin
	var rise := _route_end(rise_gate, from_hand)
	var fall := _route_end(fall_gate, to_hand)
	rise.y = high
	fall.y = high
	var at: Vector3
	if k < 1.0 / 3.0:
		at = _leg(from.origin, rise_gate, rise, k * 3.0)
	elif k < 2.0 / 3.0:
		at = rise.lerp(fall, k * 3.0 - 1.0)
	else:
		var t := minf((k - 2.0 / 3.0) / (land - 2.0 / 3.0), 1.0)
		at = _leg(to.origin, fall_gate, fall, 1.0 - t)
	return Transform3D(basis, at)


## Where a bag held in the hand at `end` (its bounds `box`) joins the overhead
## route: straight ahead of it at its height, its nearest face FRONT_CLEAR_M
## ahead of the body's centre (or where it is, if that is further).
static func gate(end: Transform3D, box: AABB) -> Vector3:
	var nearest := INF
	for i in 8:
		nearest = minf(nearest, (end.basis * box.get_endpoint(i)).z)
	return Vector3(end.origin.x, end.origin.y, maxf(end.origin.z, FRONT_CLEAR_M - nearest))


## Where the overhead route leaves or joins the body's centre plane, from the
## route's end `at`: in front or behind, at least CarryOnProps.ROUTE_FRONT_M /
## ROUTE_BACK_M
## out; always in front when `front` (an end held in the hand).
static func _route_end(at: Vector3, front := false) -> Vector3:
	if front or at.z >= 0.0:
		return Vector3(0.0, at.y, maxf(at.z, CarryOnProps.ROUTE_FRONT_M))
	return Vector3(0.0, at.y, minf(at.z, -CarryOnProps.ROUTE_BACK_M))


## The point `t` (0 to 1) of the way from `end` through `via` to `top`, at one
## speed along the two straight pieces (`via` is `end` when there is no gate).
static func _leg(end: Vector3, via: Vector3, top: Vector3, t: float) -> Vector3:
	var first := end.distance_to(via)
	var second := via.distance_to(top)
	var walked := t * (first + second)
	if walked <= first and first > 0.0:
		return end.lerp(via, walked / first)
	return via.lerp(top, clampf((walked - first) / maxf(second, 0.0001), 0.0, 1.0))


## Whether a move from `from` (a floor spot) takes pick_up()'s path: it starts
## ahead of the body.
static func picks_up_ahead(from: Transform3D) -> bool:
	return from.origin.z >= PICK_FROM_AHEAD_M


## A bag picked up from the floor ahead of the walker (`from`) to `to` (a hand
## or a shoulder) at `k`: it rises early (and over the knee), out ahead of the
## stride; it comes out to its side early, turning with it, and back toward
## the body late, so it passes outside the thigh rather than across it.
static func pick_up(from: Transform3D, to: Transform3D, k: float) -> Transform3D:
	var out := 1.0 - (1.0 - k) * (1.0 - k)
	var back := k * k * k
	var at := Vector3(
		lerpf(from.origin.x, to.origin.x, out),
		lerpf(from.origin.y, to.origin.y, 1.0 - pow(1.0 - k, 4.0)),
		lerpf(from.origin.z, to.origin.z, back)
	)
	# Over the knee that steps forward, early in the move.
	at.y += CarryOnProps.KNEE_LIFT_M * 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
	at.z += minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.5, 1.0, k)) * CarryOnProps.PICK_AHEAD_M
	var turn := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), out)
	var basis := Basis(turn).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), out))
	return Transform3D(basis, at)
