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
## would trail to is clear of the stall. The moves to and from the back (over
## the head) and the pull (by the roller's grip bar, CarryOnProps) then happen
## outside the stall, and inside it a bag only goes between the hand and the
## floor, where it stands upright against the door (floor_place()). A roller
## is taken in hand LIFT_LEAD_M earlier than it turns to the front, so the two
## moves do not overlap. Stateless: it reads the stage, the position, the path
## and the stall layout, so a load or a replay draws the same.

## How far before the approach cell the bags are taken in hand (metres of the
## walk left).
const STALL_NEAR_M := 1.0
## A roller is taken off the pull into the hand this much further back (0.7 m
## is 7 ticks of walk, more than CarryOnProps.TRANSFER_TICKS), so it hangs at
## the side before the front-carry turn starts. Leaving, a roller is pulled
## only once it is this much further clear of the stalls than leaving() asks
## (keeps_bar()), so it does not land beside the row of stall fronts.
const LIFT_LEAD_M := 0.7
## A hand holding a roller by its bar beside the stalls (beside_row()) turns
## out this much in the side carry, not CarrySwap.HAND_OUT_DEGREES (board
## a791eb90): turned out 12 degrees, a roller leaving a stall along the row
## hung 1 to 3 cm inside the stall front plane as it passed the side
## partition, at 6 its low edge keeps about 4.5 cm beyond it. Every other hand
## carry keeps 12 degrees, which keeps a case clear of the hip and thigh.
const BAR_OUT_DEGREES := 6.0
## The stall around its footprint centre: its door's outer face, half its
## width to the side partitions' outer faces, and its back.
const DOOR_M := 0.9
const HALF_M := 0.495
const BACK_M := 0.92
## The closed door leaves' inner face, and the gap a bag set down keeps from
## it (SecurityLooks.STALL_BAG_M is the two together).
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
## on the last STALL_NEAR_M (plus `lead`) of the walk to one, or leaving one
## (leaving()).
static func held_by_hand(sim: PassengerSim, p: Passenger, lead := 0.0) -> bool:
	if in_stall(p):
		return true
	if p.stage == Passenger.Stage.TOILET_WALK:
		return p.remaining_mm() <= roundi((STALL_NEAR_M + lead) * 1000.0)
	return leaving(sim, p)


## Whether a pulled roller of `p` would be at a stall: walking, the spot it
## would trail to (CarryOnProps.TRAIL_M straight back from the tick position,
## along the step walked, as a new pull starts) or the walker itself is
## within CLEAR_M (plus `extra`) of a stall's box; standing, the walker is
## within that and a trail of one. Geometry only, whatever path the walker is on (a replanned
## path keeps it), and true for anyone there, not only a stall's last user.
static func leaving(sim: PassengerSim, p: Passenger, extra := 0.0) -> bool:
	var at := sim.world_position(p)
	var spot := at
	var margin := CLEAR_M + extra + CarryOnProps.TRAIL_M
	if p.is_moving():
		var step := Vector2(p.path[p.path_index + 1] - p.path[p.path_index]).normalized()
		spot = at - Vector3(step.x, 0.0, step.y) * CarryOnProps.TRAIL_M
		margin = CLEAR_M + extra
	for stall: Dictionary in sim.toilets.layout.stalls:
		if near(stall, spot, margin) or near(stall, at, margin):
			return true
	return false


## Whether `p` is near enough the stalls for a roller held by its bar to stay
## in the hand and hang from a narrow arm: leaving() with LIFT_LEAD_M more.
static func beside_row(sim: PassengerSim, p: Passenger) -> bool:
	return leaving(sim, p, LIFT_LEAD_M)


## Whether a roller held by its bar for a stall (`bag`, CarryOnProps' record
## as sync() saw it last, still of `kind`) stays in the hand on this tick:
## until the turn back from the front has ended (`front`, its weight now), so
## it goes to the pull from the side, and while `near` (beside_row()), so it
## is pulled away from the stalls, whichever hand holds it (a roller landing
## beside the row of stall fronts clipped their partitions).
static func keeps_bar(bag: Dictionary, kind: SecurityLooks.Kind, front: float, near: bool) -> bool:
	return bag["kind"] == kind and bag.get("by_bar", false) and (front > 0.0 or near)


## Stamps the narrow arm of each hand (right, then left) of `held`
## (CarryOnProps' record, its bags just synced) at sync tick `now`: a hand is
## narrow while it holds a roller by its bar and `near` (beside_row()). A
## hand that changes eases from the turn it has at `now` (hand_out_degrees());
## a new record starts in the turn it needs.
static func stamp_bar_turn(held: Dictionary, near: bool, now: float) -> void:
	var on := [false, false]
	for i in (held["bags"] as Array).size():
		var bag: Dictionary = held["bags"][i]
		if near and bag.get("by_bar", false) and held["homes"][i] == SecurityLooks.Home.HAND:
			on[held["hands"][i]] = true
	if not held.has("bar_on"):
		held["bar_on"] = on
		held["bar_from"] = [1.0 if on[0] else 0.0, 1.0 if on[1] else 0.0]
		held["bar_since"] = [-INF, -INF]
		return
	for side in 2:
		if on[side] != held["bar_on"][side]:
			held["bar_from"][side] = _bar_weight(held, side, now)
			held["bar_since"][side] = now
	held["bar_on"] = on


## The out turn in the side carry (degrees) of each hand (right, then left) of
## `held` (CarryOnProps' record) at sim time `now`: CarrySwap.HAND_OUT_DEGREES,
## or BAR_OUT_DEGREES for a narrow hand (stamp_bar_turn()), eased between the
## two over CarryOnProps.TRANSFER_TICKS from the turn the hand had when it
## changed, so the arm does not jump; a swap to the pull starts from it
## (CarrySwap.pose_arm).
static func hand_out_degrees(held: Dictionary, now: float) -> Array:
	var outs := []
	for side in 2:
		var w := _bar_weight(held, side, now)
		outs.append(lerpf(CarrySwap.HAND_OUT_DEGREES, BAR_OUT_DEGREES, w))
	return outs


## How narrow hand `side` of `held` is at sim time `now`: 0 HAND_OUT_DEGREES,
## 1 BAR_OUT_DEGREES.
static func _bar_weight(held: Dictionary, side: int, now: float) -> float:
	if not held.has("bar_on"):
		return 0.0
	var target := 1.0 if held["bar_on"][side] else 0.0
	var k := clampf((now - held["bar_since"][side]) / CarryOnProps.TRANSFER_TICKS, 0.0, 1.0)
	return lerpf(held["bar_from"][side], target, smoothstep(0.0, 1.0, k))


## The stall `p` is visiting while inside it (a ToiletLayout entry), or {}.
static func stall_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	if not in_stall(p):
		return {}
	var visit := sim.toilets.visit_of(p.id)
	return visit.stall if visit != null else {}


## Where floor bag `index` of `count` (of bounds `box`, drawn at `scale_by`)
## stands in `stall`, in the world: SecurityLooks.stall_floor() lifted so its
## lowest point is on the stall's floor. Fixed in the stall, whatever the body
## under it does.
static func floor_place(
	stall: Dictionary, box: AABB, scale_by: float, index: int, count: int
) -> Transform3D:
	var spot := SecurityLooks.stall_floor(stall, index, count)
	var placed := Transform3D(spot.basis.scaled(Vector3.ONE * scale_by), spot.origin)
	return placed.translated(Vector3.UP * (spot.origin.y - lowest(placed, box)))


## Where a bag set down in a stall from the hand starts: at its place on the
## floor (`floor_at`, of bounds `box`), raised so its lowest point is at
## `low` (the lowest point of the bag as the hand last held it). The body
## turns round on the spot as it starts to sit and the bag held in front,
## 0.63 m ahead, would be through the door 0.43-0.53 m ahead, so the bag
## turns round with it already upright against the door, and goes straight
## down from there, clear of the knees.
static func set_down_start(floor_at: Transform3D, box: AABB, low: float) -> Transform3D:
	return floor_at.translated(Vector3.UP * maxf(low - lowest(floor_at, box), 0.0))


## The lowest point of bounds `box` placed at `placed`.
static func lowest(placed: Transform3D, box: AABB) -> float:
	var low := INF
	for i in 8:
		low = minf(low, (placed * box.get_endpoint(i)).y)
	return low


## Whether the ground point `at` lies within `margin` of the box of `stall`
## (a ToiletLayout entry): its footprint out to its door.
static func near(stall: Dictionary, at: Vector3, margin: float) -> bool:
	var out := SecurityLooks.world_dir(stall["front"])
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var rel := at - centre
	var along := rel.dot(out)
	var across := absf(rel.dot(out.cross(Vector3.UP)))
	return along < DOOR_M + margin and along > -BACK_M - margin and across < HALF_M + margin
