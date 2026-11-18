class_name RollerHandover
extends RefCounted
## A roller moved between its grip bar and its carry handle outside a toilet
## stall changes grip by a two-hand handover (decision roller-tray-moves-use-a-
## two-hand-handover-the-free-hand-take, board a365cb0b G3): into a security
## tray or onto the floor from the pull or the hand (pull>tray, hand>tray,
## hand>floor), the free hand comes to the carry handle while the bar hand
## still holds the bar, takes the roller at half way of the carry
## (CarryLead.phase()) and sets it down, and the bar hand lets go; out of a
## tray into the hand or the pull (tray>hand, tray>pull), the reverse: the
## free hand lifts it by the carry handle, and the hand it ends in takes the
## bar by half way. Each hand holds its own grip throughout, so the held point
## never slides through the air between the two (before: CarryLead.plan()
## blended it from the bar to the handle, up to 0.31 m off either grip).
##
## Fallback, when the free hand is busy (it holds another bag, or another bag
## goes into it or is set down from it as the move starts; free_hand_busy()):
## no handover is stamped and the move goes as it did before, one hand sliding
## from the one grip to the other. Pickup and repack order bags 0 then 1, so
## this is a two-bag passenger whose other bag is in the free hand.
##
## A roller parked on its wheels (RollerPark), passed between the pulling
## hands (CarryLead.is_pull_swap(), is_hand_pull_swap()) or picked up off the
## floor is not handed over. What it does not guarantee: the free hand
## reaching the handle (CarryArm's reach is limited; the bag is placed from
## the holding hand's grip, so a short reach moves the bag, it never leaves the
## grip).

## Lifted out of a tray, the body leans in to it (CarryLead.plan(), keeps) to
## this share of the carry, fading by the second: the roller rises first and
## comes in toward the body late (CarryLead.path()), and with the lean gone at
## CarryLead.KEEP_T the hands fell 0.15 to 0.3 m short of it (crossing probe
## --lane, seed 1106001, passenger 4 tray>hand.R).
const TRAY_KEEP := Vector2(0.6, 0.95)

## Lifting a roller out of a tray by its carry handle, the first hand holds
## this far (world up) over the handle, within the probes' GRIP_ON limit for a
## roller (9 cm): on the handle itself, the left hand's fingers went into the
## roller's top as it reached (crossing probe --lane, seed 1106001, passenger 4
## tray>hand.R, Fingertips.L 88 to 174 points in the roller at k 0.18 to 0.22).
const TRAY_PALM_M := 0.04


## Stamps on `bag` (bag `i` of `held`, CarryPlace's record of a move just
## stamped: "was", "home", "carry" and "led" set) "handover", the hand that
## holds the roller first, when its move is a handover with the free hand
## free at `now`; else erases it. From the move's stamp and the bags' records
## only, never from the hands drawn (anti-pattern d655fcc9).
static func stamp(bag: Dictionary, held: Dictionary, i: int, now: float) -> void:
	bag.erase("handover")
	var first := first_hand(bag, held.get("in_stall", false))
	if first < 0:
		return
	var started := CarryLead.start_of(bag)
	var free := 1 - first if started[0] == CarryLead.End.HELD else first
	if free_hand_busy(held, i, free, now):
		return
	bag["handover"] = first


## The hand that holds a roller first in a handover move of `bag` (CarryPlace's
## record), or -1 when the move is not one: from a hand (its bar) into a tray
## or onto the floor, that hand; out of a tray into a hand, the other hand,
## which lifts it by its carry handle.
static func first_hand(bag: Dictionary, in_stall: bool) -> int:
	if bag.get("kind", -1) != SecurityLooks.Kind.ROLLER or in_stall:
		return -1
	if bag.get("park", false) or not bag.get("led", false) or not bag.has("was"):
		return -1
	var started := CarryLead.start_of(bag)
	var to_end := CarryLead.end_of(bag["home"], bag["carry"])
	if started[0] == CarryLead.End.HELD and to_end == CarryLead.End.REST:
		return started[1]
	var was: int = bag["was"]
	var off_tray := was >= 0 and was / 4 == SecurityLooks.Home.TRAY
	if started[0] == CarryLead.End.REST and to_end == CarryLead.End.HELD and off_tray:
		return 1 - CarryLead.hand_of(bag["home"])
	return -1


## Whether hand `free` (0 right) of `held` is busy with a bag other than bag
## `i` at `now`: the sim has another bag in that hand, carried in it (not worn),
## or another bag's record is in that hand or on its way into it, or was set
## down from it less than half way through its move (its hand lets go at
## CarryLead.REACH_SHARE from the end, after this move's handover).
static func free_hand_busy(held: Dictionary, i: int, free: int, now: float) -> bool:
	var bags: Array = held["bags"]
	for j in bags.size():
		if j == i:
			continue
		var other: Dictionary = bags[j]
		var in_hand: bool = (
			other.get("carry", -1) in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]
		)
		var homes: Array = held["homes"]
		var hands: Array = held["hands"]
		if (
			j < homes.size()
			and homes[j] == SecurityLooks.Home.HAND
			and hands[j] == free
			and in_hand
		):
			return true
		if not other.has("home") or int(other["home"]) < 0:
			continue
		var ends := CarryLead.end_of(other["home"], other.get("carry", -1))
		if ends == CarryLead.End.HELD and CarryLead.hand_of(other["home"]) == free:
			return true
		if not other.has("was"):
			continue
		var started := CarryLead.start_of(other)
		var early := CarryPlace.progress_of(other, now) < 0.5
		if started[0] == CarryLead.End.HELD and started[1] == free and early:
			return true
	return false


## How far (world) to move a handed-over roller, on its path at `on_path` at
## `t` of the carry, the body drawn at `frame`, `shoulder_y` its lower shoulder
## joint's height over its origin as the move started (CarryLead.stamp_move(),
## NAN for none: not moved), so the middle of its two grips (`grip_a`, `grip_b`,
## its own frame) comes to CarryLead.SWAP_FRONT_M ahead of the body's centre
## at hip height (CarryLead.SWAP_HIP_BELOW_M under the shoulder) at half way,
## where the hands change, easing in from the start and out to the end. The
## hand-to-pull swap is handed over at the same point (user ruling 2026-11-17,
## "In front, at hip height", board 295026a6). From the move's stamp and
## progress, never from a drawn hand (anti-pattern d655fcc9).
static func to_front(
	on_path: Transform3D,
	frame: Transform3D,
	t: float,
	shoulder_y: float,
	grip_a: Vector3,
	grip_b: Vector3
) -> Vector3:
	if is_nan(shoulder_y):
		return Vector3.ZERO
	var w := smoothstep(0.0, 0.5, t) if t < 0.5 else 1.0 - smoothstep(0.5, 1.0, t)
	var front := Vector3(0.0, shoulder_y - CarryLead.SWAP_HIP_BELOW_M, CarryLead.SWAP_FRONT_M)
	var middle := on_path * ((grip_a + grip_b) * 0.5)
	return (frame * front - middle) * w
