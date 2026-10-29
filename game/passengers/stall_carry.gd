class_name StallCarry
extends RefCounted
## How carry-on bags are carried in and near a toilet stall (board item
## carry-on-bags-in-a-toilet-stall-clip), for CarryOnProps. A stall is 0.94 m
## wide inside between partitions 2.22 m tall (decision toilet-stall-kit-
## piece-1x2-footprint-side-partitions-out-to), and a standing walker's hair
## reaches about 2.0 m, so no bag can cross over the head inside one, and a
## roller trailing 1 m behind lands over the bowl. So, as at security
## (decision carry-on-bag-kinds-backpack-shoulder-or-tote-bag-small-rolle), a
## backpack or a roller is taken in the hand by its handle before the walker
## reaches the stall, and every hand-carried bag is held in front (decision
## in-a-cell-closed-on-both-sides-a-passenger-carries-their-bag: a stall is
## closed on both sides): from the last STALL_NEAR_M of the walk to the
## stall's approach cell, through the visit, until the spot a pulled roller
## would trail to is clear of the stall. The moves to and from the back or
## the pull (over the head) then happen outside the stall, and inside it a bag
## only goes between the hand and the floor. Stateless: it reads the stage, the
## position, the path and the stall layout, so a load or a replay draws the
## same.

## How far before the approach cell the bags are taken in hand (metres of the
## walk left).
const STALL_NEAR_M := 1.0
## The stall around its footprint centre: its door's outer face, half its
## width to the side partitions' outer faces, and its back.
const DOOR_M := 0.9
const HALF_M := 0.495
const BACK_M := 0.92
## The closed door leaves' inner face, and how far inside it a bag being set
## down starts.
const DOOR_IN_M := 0.881
const DOOR_GAP_M := 0.02
## A bag moving in a stall that is not in the hand (a tote coming off or onto
## the shoulder) keeps this far from the body's centre line, not
## CarryOnProps.TRANSFER_CLEAR_M, so it stays inside the side partitions.
const STALL_CLEAR_M := 0.3
## A spot this close to the stall's box counts as in it: a new pull's axle
## sits TRAIL_SIDE_MIN_M (0.28 m) to the pulling hand's side (the follower
## lets it out to 0.6 m only on a zig-zag walk, later), the roller is 0.33 m
## wide, and the body is drawn up to a tick behind its tick position.
const CLEAR_M := 0.5
## The stages a passenger spends inside a stall.
const IN_STALL: Array[Passenger.Stage] = [
	Passenger.Stage.TOILET_ENTER,
	Passenger.Stage.TOILET_SITTING_DOWN,
	Passenger.Stage.TOILET_USE,
	Passenger.Stage.TOILET_STANDING_UP,
	Passenger.Stage.TOILET_EXIT,
]


## Whether `p` is inside a toilet stall: stepping in, sitting down, using it,
## standing up or stepping out.
static func in_stall(p: Passenger) -> bool:
	return p.stage in IN_STALL


## Whether `p` holds its bags in hand, in front, for a stall: inside one,
## on the last STALL_NEAR_M of the walk to one, or leaving one (leaving()).
static func held_by_hand(sim: PassengerSim, p: Passenger) -> bool:
	if in_stall(p):
		return true
	if p.stage == Passenger.Stage.TOILET_WALK:
		return p.remaining_mm() <= roundi(STALL_NEAR_M * 1000.0)
	return leaving(sim, p)


## Whether a pulled roller of `p` would be at a stall: walking, the spot it
## would trail to (CarryOnProps.TRAIL_M straight back from the tick position,
## along the step walked, as a new pull starts) or the walker itself is
## within CLEAR_M of a stall's box; standing, the walker is within that and a
## trail of one. Geometry only, whatever path the walker is on (a replanned
## path keeps it), and true for anyone there, not only a stall's last user.
static func leaving(sim: PassengerSim, p: Passenger) -> bool:
	var at := sim.world_position(p)
	var spot := at
	var margin := CLEAR_M + CarryOnProps.TRAIL_M
	if p.is_moving():
		var step := Vector2(p.path[p.path_index + 1] - p.path[p.path_index]).normalized()
		spot = at - Vector3(step.x, 0.0, step.y) * CarryOnProps.TRAIL_M
		margin = CLEAR_M
	for stall: Dictionary in sim.toilets.layout.stalls:
		if near(stall, spot, margin) or near(stall, at, margin):
			return true
	return false


## The stall `p` is visiting while inside it (a ToiletLayout entry), or {}.
static func stall_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	if not in_stall(p):
		return {}
	var visit := sim.toilets.visit_of(p.id)
	return visit.stall if visit != null else {}


## `placed` (a bag's world transform, of bounds `box`) moved back toward the
## inside of `stall`, so that no part of it is nearer the door than
## DOOR_GAP_M inside its leaves. A bag set down in a stall starts from the
## front carry, which reaches about 0.63 m ahead of the body, on the frame
## the body turns round to face the door 0.43-0.53 m from it, and turns as it
## goes down; the hand lets go of it on that frame, so it is not pulled off
## the hand.
static func inside_door(stall: Dictionary, placed: Transform3D, box: AABB) -> Transform3D:
	if stall.is_empty():
		return placed
	var out := SecurityLooks.world_dir(stall["front"])
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var reach := -INF
	for i in 8:
		reach = maxf(reach, (placed * box.get_endpoint(i) - centre).dot(out))
	var over := reach - (DOOR_IN_M - DOOR_GAP_M)
	if over > 0.0:
		placed.origin -= out * over
	return placed


## Whether the ground point `at` lies within `margin` of the box of `stall`
## (a ToiletLayout entry): its footprint out to its door.
static func near(stall: Dictionary, at: Vector3, margin: float) -> bool:
	var out := SecurityLooks.world_dir(stall["front"])
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var rel := at - centre
	var along := rel.dot(out)
	var across := absf(rel.dot(out.cross(Vector3.UP)))
	return along < DOOR_M + margin and along > -BACK_M - margin and across < HALF_M + margin
