class_name CarryLead
extends RefCounted
## Hand-led carry-on moves (decision carry-on-bags-stay-in-the-hand-during-
## every-move-no-overhead; rebuilt narrowly from main, decision floating-bag-
## fix-rebuilt-narrower-from-main-hand-led-moves-only-where-bags-float). Pure:
## CarryOnProps asks it how a move of a bag between two homes goes at `k` (0
## to 1) of the move.
##
## An end of a move is HELD when a hand holds the bag there (a bag carried in
## the hand, a roller pulled by its bar), WORN (on the back or the shoulder)
## or REST (on the floor, in a tray). A move goes in up to three parts:
## - reach: from a WORN or REST start the bag stays where it is while the
##   leading hand goes to it (REACH_SHARE of the move);
## - carry: the bag is placed from the leading hand's grip, along the path
##   (path()), while the hand is aimed at the path's grip point;
## - let go: at a WORN or REST end the bag is where it ends while the hand
##   goes back (REACH_SHARE of the move).
## A move from one hand to the other is carried by the old hand to half way,
## where the new hand has come to it, and by the new hand after.
## What it does not guarantee: the hand reaching its target (CarryArm's reach
## and CarryStoop's bend are limited; the bag is placed from where the grip is,
## so a short reach shortens the path, it never leaves the bag in the air).

enum End { HELD, WORN, REST }

## The share of a move the hand takes to reach a bag that is not in a hand at
## the start, and to come back from one it leaves.
const REACH_SHARE := 0.25
## Picking a bag up off a toilet stall's floor into the hand, the hand reaches
## it over this share instead (CarryOnProps stamps it on the move, "reach"):
## the walker already steps out as the move starts, about 0.1 m a tick, and a
## bag left on the floor for REACH_SHARE was stepped through (stall_bags_probe,
## board item c7b0e7be).
const STALL_PICK_REACH := 0.06
## A backpack goes on and off the back through a hang at the leading hand's
## side, at shoulder height, this far out from the centre line, over this
## share of the carry.
const BACK_SIDE_M := 0.42
const BACK_SHARE := 0.4
## A backpack carried alone between the back and a tray or the floor (not in a
## toilet stall) is led by the hand on the side its resting end lies on, when
## that end is more than this far out from the body's centre line (back_lead()).
const BACK_LEAD_SIDE_M := 0.15
## Outside a toilet stall, the side hang is this far under the leading
## shoulder joint (0.1 in a stall): 0.1 under it the arm folded with the elbow
## up and back, and let go there it stood out sideways at shoulder height
## (backpack_pickup_probe, seed 2811556352, board 41c159bc).
const BACK_HANG_BELOW_M := 0.3
const STALL_HANG_BELOW_M := 0.1
## And the pack is held this far over its grab loop's top (its own frame;
## world: divided by the bag's scale), so the curled fist (CarryArm.loop_grip,
## palm down) closes round the loop: its fingers go down into the loop block
## and stay above the pack's top beside it. Swept over a real pack
## (tools/blender/out/loop_hand, fit mode; male and female, both hands, both
## pack turns): at 0.005 no hand point is in the pack outside the loop, the
## fingers' lowest point is 0.207 (male) and 0.217 (female) in the pack's
## frame (the loop block's floor is 0.205) and 20 to 24 finger points are in
## the loop; at 0 the male fingers reach 0.202, at 0.028 (before, 2 mm under
## the probes' 3 cm GRIP_ON cap) every fist floated 4 to 8 mm over the loop.
## Not shifted along the loop: 1 to 3 cm either way only took fingers out.
const BACK_LOOP_UP := Vector3(0.0, 0.0, 0.005)
## While the pack is still turning to hang plumb (loop_yaw() weight under 1,
## at a move's ends) it is held higher, up to this at weight 0 (2 mm under
## the probes' 3 cm GRIP_ON cap, spike/carry_float_check.gd GRIP_ON_M): held at
## BACK_LOOP_UP over a pack still tilted as it left its tray, the fist went into
## its top beside the loop (crossing probe --lane, seed 1106001, passenger 2
## tray>back at k 0.28, 60 to 76 points against 30 on main).
const BACK_LOOP_UP_TURNING := Vector3(0.0, 0.0, 0.028)
## Off the back into the hand, the hand eases into its carry pose from this
## share of the carry (not 0.6): eased in while the pack still turned on its
## lifted, pushed-out path, the grip came between the two and the pack into the
## belly (stall_bags_probe, seed 3894526912, backpack_in at k 0.83).
const BACK_EASE_IN := 0.8
## Off the floor a bag turns to hang from the hand over this share of its
## carry (off a tray, 0.35: the table is under it).
const UPRIGHT_FROM_FLOOR := 0.2
## Lifting a bag off the floor the stoop is kept on (CarryStoop.keeps) to this
## share of the carry and gone KEEP_FADE later, so the hand reaches the bag's
## path ahead of the knees, not short of it in front of the thighs; setting
## one down, from as far before the end.
const KEEP_T := 0.35
const KEEP_FADE := 0.25
## How high a bag set down on the floor rises midway: the full TRANSFER_LIFT_M
## put the case top against the face of a body stooping to set it down, and
## none put the hand low beside the case's top corner, palm out, not on it.
const SET_DOWN_LIFT_M := 0.15
## Setting a bag down in a toilet stall the back bends first and the hips go
## down (and back) only as far as the bent back leaves the hand short
## (CarryStoop.drops): the hips dropping with every stoop brought the knees
## forward into the bag by the door, the back alone left the hand up to 0.45 m
## short of it (board item c7b0e7be).
const STALL_HIPS := Vector3(1.0, 1.0, 1.0)
## Set down from the hand in a toilet stall, the hand comes back from the bag
## over this last share of the move (not REACH_SHARE): the body shuffles back
## to the seat as it sits (0.4 m over 12 ticks), and a bag let go at the usual
## k 0.75 was out of the hand's reach by then.
const STALL_LET_GO := 0.55
## A bag picked up from a stall's floor goes out this far to its hand's side
## midway (the walker steps out past it).
const STALL_PICK_SIDE_M := 0.12
## A bag picked up in a stall rises toward its carry with the hand no lower than
## this over the feet (the front carry holds it about 1.2 m up).
const STALL_CARRY_GRIP_M := 1.0
## A tote set down in a toilet stall rises this much midway, over the thighs.
const STALL_TOTE_LIFT_M := 0.25
## And it is held this far short of its place by the door until it goes down.
const STALL_TOTE_BACK_M := 0.05
## Picked up there it is not pushed out ahead (path()) to this share of the
## move, and pushed as it is outside from this one on.
const STALL_AHEAD_BACK := Vector2(0.35, 0.65)
## A backpack held by its grab loop on or off the back hangs plumb from the grip
## and is turned about it so the loop lies across the holding hand (loop_yaw()),
## which the arm points level from the shoulder to its target
## (CarryArm._reach_loop): left as the path turned it, the hand lay along the
## loop out of a lane tray and its fingertips went into the pack past the loop's
## ends, and turned only, the pack's top still sloped up into the fingers
## (crossing probe --lane, seed 1106001, tray>back, board bcad1dd0). Eased in
## and out over this share of the carry at each end, so the pack leaves its tray
## and lands on the back as placed there.
const LOOP_YAW_SHARE := 0.15
## A backpack set down in a stall is held this far over its grab loop (its own
## frame), the fingers over the top, not in it, and within the probes' GRIP_ON
## 3 cm of the loop (6 cm left the hand off it).
const STALL_LOOP_UP := Vector3(0.0, 0.0, 0.02)
## A hard case standing in a stall is held by the middle of its top end, the
## grip FRONT_PALM_M over it (the palm on the top, as on the handle in front).
## Its body is this deep (measured on the mesh): bag_box() takes in the handle,
## 3.6 cm proud of the face, so its top corner was in the air past the face,
## where the hand hung beside the case (board item c7b0e7be).
const STALL_CASE_DEPTH_M := 0.19
## Its top front edge is cut off this far both ways (measured on the mesh).
const STALL_CASE_CHAMFER_M := 0.03
## A bag picked up in a stall rises upright and tips into its carry from this
## share of the carry on (path(), stall_tip()).
const STALL_TIP_FROM := 0.4
## Lifting a hard case off the floor into the hand (not in a stall) the grip is
## held FLOOR_PALM_M over the point it is carried by (world up, the palm over the
## top as in the front carry), easing to none over this share of the carry, as
## the arm turns down into the side carry. Held at that point
## itself, the arm reaching out level ahead of the stoop lay with the forearm on
## the case's top behind the hand (crossing probe seed 777, Forearm.R in the
## case at k 0.46, board item 2fbf5edb).
const FLOOR_PALM_FADE := Vector2(0.6, 1.0)
## Since 2026-11-02 the case is held by its top edge on its handle face
## (CarryOnProps.grip_anchor(), on the mesh), 3.6 cm lower than the bounds
## corner at the handle's height it was held by before. With FRONT_PALM_M (4 cm)
## over that edge the forearm went into the case's top end at k 0.46 (crossing
## probe seed 2449926952); 7.6 cm (the old height) is past the probes' GRIP_ON
## limit for a case (7 cm). 6.5 cm keeps the palm over the case top within it.
const FLOOR_PALM_M := 0.065
## And it rises to its side carry with the grip this high over the feet
## (floor_end()): measured in the side carry at the end of that move (1.023 and
## 1.026 m, crossing probe seed 4242). A fixed height, not the hand's as drawn
## on the move's first frame: that frame comes several ticks late at 3x or after
## a slow frame, part way through a stand-up (1.146 m measured; Sol review of
## ebe2a76).
const FLOOR_CASE_END_M := 1.02
## Picking a roller up off a toilet stall's floor, the grip is held this far
## (world up) over its bar as it rises standing, coming in over STALL_BAR_IN
## of the carry and gone over STALL_BAR_OUT as it tips into the carry: held
## at the bar itself, the straight arm lay across the roller's top behind the
## hand (stall_float_probe seed 903959512, Forearm.R in the roller at k 0.55,
## board item f396b087). Gone by 0.7, not 1.0: on with the grip sliding to
## the carry's BAR_PALM_M, the hand was up to 5.7 cm off the roller at k 0.72
## (the probe's GRIP limit is 5 cm).
const STALL_BAR_PALM_M := 0.04
const STALL_BAR_IN := 0.25
const STALL_BAR_OUT := Vector2(0.55, 0.7)
## A pulled roller passed from one pulling hand to the other (pull.R>pull.L)
## goes toward its start mirrored across the body (pull_swap_goal()) and comes
## onto the end the receiving hand pulls it at over this part of the carry,
## once that hand is mostly back in its carry pose (phase(): its reach eases
## out from 0.6).
const PULL_SWAP_END := Vector2(0.85, 1.0)
## In a hand swap (HELD to HELD) the two hands hold a roller's bar this far
## (its own frame) either side of its middle, each on its own side of the body
## (swap_spots()): the hand that gives it slides out to its spot by
## SWAP_SPOT_T.x of the carry, the hand that takes it slides back to the middle
## from SWAP_SPOT_T.y. On one point, both hands were in each other and the
## bar at the handover (crossing probe --lane, seed 1106001, passenger 4,
## hand.R>pull.L, board 2237fa05). The bar is 0.144 m long between its ends.
const SWAP_SPOT_M := 0.035
const SWAP_SPOT_T := Vector2(0.3, 0.7)
## Handed over to the other hand (phase(): half way), the hand that gave a bag
## lets go of it: its target goes this far (m, world) from the point it held
## the bag by, away from the bag's middle (past a roller's bar along its rods,
## over a case's top), over SWAP_RELEASE_T of the carry (swap_release()). Left
## on that point while its reach faded, the right hand was still in the
## roller's handle at k 0.51-0.55; aimed up and out to its side, along the rods
## and the bar, still at k 0.55 (board 2237fa05).
const SWAP_RELEASE_M := 0.08
const SWAP_RELEASE_T := Vector2(0.5, 0.65)
## A roller taken from one hand's carry into the other hand's pull
## (hand.R>pull.L, hand.L>pull.R; hand_pull_path()) has its bar brought round
## in front of the body, SWAP_FRONT_M ahead of its centre and
## SWAP_HIP_BELOW_M under its shoulder joints (about hip height), where the
## other hand takes it half way, the roller leaning SWAP_LEAN (radians from
## plumb) out ahead, away from the legs, before it trails behind on the new
## side (user ruling 2026-11-17, "In front, at hip height", board 295026a6).
## On path() its rods ran out with the bag still upright and the bar went up
## to 1.24 m behind the neck at half way (k 0.5, test_carry_hand_pull_swap).
const SWAP_FRONT_M := 0.3
const SWAP_HIP_BELOW_M := 0.45
const SWAP_LEAN := deg_to_rad(40.0)
## Coming round, the roller turns its front face from the leg (as it hangs in
## the hand) to the outside, through ahead, by this share of the carry, so it is
## never between the bar and the leg (swap_lean()).
const SWAP_SPIN_T := 0.25
## On the second half the bar goes this much wider round the receiving hip than
## a straight sweep from the front to the side (round_front()): the hand held
## the bar in the receiving thigh at k 0.75 (crossing probe --lane seed 1106001,
## passenger 4; test_carry_hand_pull_swap's rods check).
const SWAP_ROUND_OUT_M := 0.1


## Where a bag of `kind` standing in a stall is held (its own frame, the bag
## drawn at `scale_by`): its top (`loose` its kind's grip point: a roller's
## bar), a backpack STALL_LOOP_UP over its grab loop, a hard case FRONT_PALM_M
## (world, as carried_in_front()) over the middle of its top end.
static func stall_top(kind: SecurityLooks.Kind, loose: Vector3, scale_by := 1.0) -> Vector3:
	if kind == SecurityLooks.Kind.BACKPACK:
		return CarryOnProps.BACKPACK_LOOP + STALL_LOOP_UP
	if kind == SecurityLooks.Kind.CASE:
		var top := CarryOnProps.bag_box(kind).end.z + CarryOnProps.FRONT_PALM_M / scale_by
		return Vector3(0.0, STALL_CASE_DEPTH_M * 0.5, top)
	return loose


## How far (world metres) the grip is held over a hard case's carry point at
## `t` of its carry off the floor into the hand (FLOOR_PALM_FADE).
static func floor_palm(t: float) -> float:
	return FLOOR_PALM_M * (1.0 - smoothstep(FLOOR_PALM_FADE.x, FLOOR_PALM_FADE.y, t))


## How far (world metres) the grip is held over a roller's bar at `t` of its
## carry off a toilet stall's floor into the hand (STALL_BAR_PALM_M): none on
## the floor and none in the carry.
static func stall_bar_palm(t: float) -> float:
	var on := smoothstep(0.0, STALL_BAR_IN, t)
	return STALL_BAR_PALM_M * on * (1.0 - smoothstep(STALL_BAR_OUT.x, STALL_BAR_OUT.y, t))


## The end of a hard case's lift off the floor or out of a tray into the hand,
## and of a roller's out of a tray (`want`, held at `grip_at`, world, with the
## body drawn at `frame`), with its grip FLOOR_CASE_END_M over the feet, not
## where the hand is drawn now: `want` follows the hand, which this move poses,
## so a path rising to it raised the hand, the end with it, and the hand again
## (crossing probe seed 777, board items 2fbf5edb and 2fd0356b).
static func floor_end(frame: Transform3D, want: Transform3D, grip_at: Vector3) -> Transform3D:
	return want.translated(Vector3.UP * (frame.origin.y + FLOOR_CASE_END_M - grip_at.y))


## How far (0 to 1) a bag picked up in a stall has tipped from standing into
## its carry at `t` of the carry (path()).
static func stall_tip(t: float) -> float:
	return clampf((t - STALL_TIP_FROM) / (1.0 - STALL_TIP_FROM), 0.0, 1.0)


## The point of a hard case in the hand at `w` (stall_tip()) of its tip from
## standing, held at `from` (stall_top()), into its carry, held at `to` (its
## own frame): the palm rests on the case's top as it turns, the grip `up`
## (CarryOnProps.FRONT_PALM_M world up, in the case's frame as drawn now) over
## a point that slides from the middle of its top end over its top front edge
## (STALL_CASE_CHAMFER_M), on it from 0.4 to 0.6 of the tip as the edge comes
## up, and on to the top of its handle. `up_from`
## and `up_to` are `up` at the tip's start and end, so it starts at `from` and
## ends at `to`. A curve 8 cm out past the edge held the grip off the case, and
## midway only the fingertips were at its corner, the case hanging beside an
## open hand (conductor ruling 2026-11-01, board item e845dfe8); a straight
## blend between the two took the grip 3.5 cm into the case.
static func case_tip_grip(
	from: Vector3, to: Vector3, w: float, up: Vector3, up_from: Vector3, up_to: Vector3
) -> Vector3:
	var box := CarryOnProps.bag_box()
	var top := Vector3(0.0, STALL_CASE_DEPTH_M * 0.5, box.end.z)
	var cut := STALL_CASE_CHAMFER_M
	var edge_end := Vector3(0.0, STALL_CASE_DEPTH_M - cut, box.end.z)
	var edge_face := Vector3(0.0, STALL_CASE_DEPTH_M, box.end.z - cut)
	var handle := Vector3(0.0, box.end.y, box.get_center().z)
	var on := top.lerp(edge_end, w / 0.4)
	if w > 0.6:
		on = edge_face.lerp(handle, (w - 0.6) / 0.4)
	elif w > 0.4:
		on = edge_end.lerp(edge_face, (w - 0.4) / 0.2)
	return on + up + (from - top - up_from) * (1.0 - w) + (to - handle - up_to) * w


## The kind of end a bag's place (`place`, CarryOnProps' (home * 2 + hand) * 2
## + lifted, or -1) carried `carry` is.
static func end_of(place: int, carry: SecurityLooks.Carry) -> End:
	if place < 0 or place / 4 != SecurityLooks.Home.HAND:
		return End.REST
	if carry in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]:
		return End.HELD
	return End.WORN


## The start of a move of `bag` (CarryOnProps' record): [its End, its hand].
## A move that starts while the last one was still in a hand
## ("from_holder") starts HELD in that hand, wherever the bag was going.
static func start_of(bag: Dictionary) -> Array:
	var holder: int = bag.get("from_holder", -1)
	if holder >= 0:
		return [End.HELD, holder]
	return [end_of(bag["was"], bag["carry_from"]), hand_of(bag["was"])]


## Whether a hand-led move of `bag` (CarryOnProps' record, "led") drawn last
## at `k` has not left its start: the hand was still reaching for the bag (a
## move that starts HELD leaves at once). A move that interrupts it starts
## where the bag is, at that start (CarryPlace._stamp). A parking move's reach
## is in ticks of RollerPark.TICKS_UP (RollerPark.up_k()), however long the
## move grew (a roller rolled upright at a seat, RollerPark.roll_step()).
static func at_start(bag: Dictionary, k: float) -> bool:
	if bag.get("park", false):
		k = RollerPark.up_k(bag, k)
	return (
		bag.get("led", false) and k < span(start_of(bag)[0], End.HELD, REACH_SHARE, reach_of(bag)).x
	)


## Stamps on `bag` (CarryOnProps' record of a move starting at its "was",
## carried "carry", to `home`, a SecurityLooks.Home) the share of the move the
## hand takes to reach it: STALL_PICK_REACH off a toilet stall's floor
## (`in_stall`) into the hand, else none (REACH_SHARE).
static func stamp_reach(bag: Dictionary, in_stall: bool, home: int) -> void:
	var was: int = bag["was"]
	var off_floor := was >= 0 and was / 4 == SecurityLooks.Home.FLOOR
	var into_hand: bool = bag["carry"] in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]
	if in_stall and off_floor and home == SecurityLooks.Home.HAND and into_hand:
		bag["reach"] = STALL_PICK_REACH
	else:
		bag.erase("reach")


## Stamps a new move of `bag` (CarryOnProps' record, as for stamp_reach()) with
## its reach and its length (ticks_of()), with `body` the body's frame as it
## starts (kept as "start_body", for back_lead()): a roller laid on the floor
## from the pull or taken off it into the pull parks on its wheels (RollerPark)
## and takes RollerPark.TICKS, parked in `face` when it is a yaw
## (RollerPark.sit_face()). Stamped again before the move has left its start
## (`unmoved`, at_start()), it is the same move and keeps the "start_body" it
## started with: taken from a body that had turned since, the leading hand
## changed while it still reached for the bag (Sol review, board 41c159bc).
## `shoulder_y` is the body's lower shoulder joint's height over its origin
## (world metres) as the move starts, kept as "start_shoulder_y" for a hand to
## pull swap's handover height (hand_pull_path()), with "start_body"; NAN when
## the body has no carry rig yet, and the key is then left off. Taken from the
## skeleton drawn later, the same move and progress gave a handover 0.2 m
## higher with the shoulders 0.2 m higher in a walk or stoop pose (Sol review,
## board 295026a6; anti-pattern d655fcc9).
static func stamp_move(
	bag: Dictionary,
	in_stall: bool,
	home: int,
	body: Transform3D,
	face := NAN,
	unmoved := false,
	shoulder_y := NAN
) -> void:
	stamp_reach(bag, in_stall, home)
	if not (unmoved and bag.has("start_body")):
		bag["start_body"] = body
		bag.erase("start_shoulder_y")
		if not is_nan(shoulder_y):
			bag["start_shoulder_y"] = shoulder_y
	bag.erase("ticks")
	bag.erase("park")
	if RollerPark.parks(bag, in_stall, home):
		RollerPark.stamp(bag, body, face)
	# A queue stand asked for (RollerPark.queue_stand()) is stamped by this move
	# or not at all, never by a later one.
	bag.erase("queue_still")


## How many sim ticks the move of `bag` (CarryOnProps' record) takes: the
## length stamped on it (stamp_move()), else CarryOnProps.TRANSFER_TICKS. Every
## reader of a move's progress or end goes through this.
static func ticks_of(bag: Dictionary) -> float:
	return bag.get("ticks", CarryOnProps.TRANSFER_TICKS)


## The share of a move of `bag` (CarryOnProps' record) the hand takes to reach
## it at its start: REACH_SHARE, or the one stamped on the move (STALL_PICK_REACH).
static func reach_of(bag: Dictionary) -> float:
	return bag.get("reach", REACH_SHARE)


## The hand of a place (0 right, 1 left).
static func hand_of(place: int) -> int:
	return (maxi(place, 0) / 2) % 2


## The hand that leads a move: the one it ends in, else the one it starts in,
## else `fallback` (the bag's own hand or side).
static func lead_hand(from: End, to: End, from_hand: int, to_hand: int, fallback: int) -> int:
	if to == End.HELD:
		return to_hand
	if from == End.HELD:
		return from_hand
	return fallback


## The part of the move (`x` the start, `y` the end of k) the bag is carried;
## the hand reaches a bag not in a hand over the first `reach` of it and comes
## back from a bag it leaves over the last `let_go` of it.
static func span(from: End, to: End, let_go := REACH_SHARE, reach := REACH_SHARE) -> Vector2:
	return Vector2(0.0 if from == End.HELD else reach, 1.0 if to == End.HELD else 1.0 - let_go)


## How far along the carry a move of `bag` (CarryOnProps' record) is at `k`,
## 0 to 1 (0 while it waits at its start, 1 once it is at its end); for a
## parking move (RollerPark), how far its rods have run (RollerPark.rods_t()).
static func carry_t(k: float, bag: Dictionary) -> float:
	if bag.get("park", false):
		return RollerPark.rods_t(k, bag)
	var s := span(start_of(bag)[0], end_of(bag["home"], bag["carry"]), REACH_SHARE, reach_of(bag))
	return clampf((k - s.x) / maxf(s.y - s.x, 0.0001), 0.0, 1.0)


## The move at `k`: {"t": how far along the carry (below 0 before it, above 1
## after it), "holder": the hand the bag is placed from (-1 while it rests or
## is worn at an end), "weights": [right, left] how far each hand is aimed at
## its target (CarryArm.reach_weight), "targets_at": [right, left] the carry
## progress each hand aims at (-1 the start, 2 the end)}. `let_go` and
## `reach` as for span(); into a held end the hand eases into its carry pose
## from `ease_in` of the carry. `first` the hand that holds the bag to half way
## of a roller handover (RollerHandover, the other hand `lead`), -1 for none:
## off a resting end it is that hand that reaches for the bag.
static func phase(
	k: float,
	from: End,
	to: End,
	from_hand: int,
	lead: int,
	let_go := REACH_SHARE,
	reach := REACH_SHARE,
	ease_in := 0.6,
	first := -1
) -> Dictionary:
	var s := span(from, to, let_go, reach)
	var t := (k - s.x) / maxf(s.y - s.x, 0.0001)
	var weights := [0.0, 0.0]
	var aims := [0.0, 0.0]
	var holder := lead
	var lead_w := 1.0
	var swap := from == End.HELD and from_hand != lead
	# The hand that holds the bag to half way and gives it to `lead` then.
	var old := first if first >= 0 else (1 - lead if swap else -1)
	if k < s.x:
		holder = -1
		var w := smoothstep(0.0, 1.0, k / s.x)
		if first >= 0:
			weights[first] = w
			aims[first] = -1.0
			lead_w = 0.0
		else:
			lead_w = w
			aims[lead] = -1.0
	elif k > s.y:
		holder = -1
		lead_w = smoothstep(0.0, 1.0, (1.0 - k) / (1.0 - s.y))
		aims[lead] = 2.0
	else:
		aims[lead] = t
		if from == End.HELD:
			# From the carry pose of the hand it starts in (or the new hand
			# coming to it, by half way).
			# A roller handover's other hand is on its grip by 0.4, settled
			# before it takes the roller at half way.
			lead_w = smoothstep(0.0, 0.4 if first >= 0 or old < 0 else 0.5, t)
		elif old >= 0:
			# The hand it ends in comes to it while the other holds it.
			lead_w = smoothstep(0.0, 0.4, t)
		if to == End.HELD:
			# Into the carry pose of the hand it ends in.
			lead_w *= 1.0 - smoothstep(ease_in, 1.0, t)
		if old >= 0:
			weights[old] = 1.0 - smoothstep(0.5, 1.0, t)
			if first >= 0 and from == End.HELD:
				# A handover's first hand leaves its carry pose as a lone hand does.
				weights[old] *= smoothstep(0.0, 0.4, t)
			aims[old] = t
			if t < 0.5:
				holder = old
	weights[lead] = lead_w
	return {"t": clampf(t, 0.0, 1.0), "holder": holder, "weights": weights, "targets_at": aims}


## How far (0 to 1) the leading hand's stoop is kept on (CarryStoop.keeps) at
## `k` of a move from `from` to `to`: lifting a bag off the floor
## (`from_floor`), through the reach and the carry to KEEP_T, gone by KEEP_T +
## KEEP_FADE; setting one down on it (`to_floor`), the same from the end back.
## `reach` as for span().
static func floor_keep(
	k: float, from: End, to: End, from_floor: bool, to_floor: bool, reach := REACH_SHARE
) -> float:
	var s := span(from, to, REACH_SHARE, reach)
	var t := (k - s.x) / maxf(s.y - s.x, 0.0001)
	var keep := 0.0
	if from == End.REST and from_floor:
		keep = 1.0 - smoothstep(KEEP_T, KEEP_T + KEEP_FADE, t)
	if to == End.REST and to_floor:
		keep = maxf(keep, smoothstep(1.0 - KEEP_T - KEEP_FADE, 1.0 - KEEP_T, t))
	return keep


## The grip point (in the bag's own frame) of a bag of `kind` that is not in
## a hand: a hard case's top edge, a backpack's grab loop, a shoulder bag's
## top edge; a roller's grip bar at `bar_z` along it.
static func anchor(kind: SecurityLooks.Kind, bar_z: float) -> Vector3:
	if kind == SecurityLooks.Kind.ROLLER:
		return Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, bar_z)
	if kind == SecurityLooks.Kind.BACKPACK:
		# Held by its top grab loop, the pack hanging below the hand (conductor
		# ruling 2026-10-30: held 15 cm off it, LOOP_OFFSET, the pack hung beside
		# an open hand at k 0.5 off and onto the back).
		return CarryOnProps.BACKPACK_LOOP
	return CarryOnProps.grip_anchor(kind)


## Whether the move of `bag` (CarryOnProps' record) passes a pulled roller
## from one pulling hand to the other (pull.R>pull.L or pull.L>pull.R),
## outside a toilet stall (`in_stall`).
static func is_pull_swap(bag: Dictionary, in_stall: bool) -> bool:
	var started := start_of(bag)
	return (
		bag["kind"] == SecurityLooks.Kind.ROLLER
		and not in_stall
		and started[0] == End.HELD
		and end_of(bag["home"], bag["carry"]) == End.HELD
		and started[1] != hand_of(bag["home"])
		and bag["carry_from"] == SecurityLooks.Carry.PULL
		and bag["carry"] == SecurityLooks.Carry.PULL
	)


## Where a pulled roller passed between the pulling hands starts from now
## (world), the body drawn at `frame` at sim time `now`: where it was as the
## move started ("from", in the body's frame then, "start_body"), carried
## along with the walker and turned from the body's heading then toward its
## heading now by at most RollerPull.SWING_TURN a tick of the move ("since"),
## as fast as the trailing roller swings. Turned with the body, it swung round
## a walker turning 22 degrees a tick 0.10 m a frame on top of the move's own
## travel, and jumped 0.153 m a frame (test_roller_queue_stand's cafe guest,
## changing hands in the turn onto the cafe's diagonal); held to SWING_TURN,
## 0.137 m. Worked out from the move's start and sim time only, never from the
## frames drawn before: stepped on from the last draw, a first draw a tick late
## left the start unturned (Sol review of f8b021f).
static func pull_swap_start(bag: Dictionary, frame: Transform3D, now: float) -> Transform3D:
	var began: Transform3D = bag.get("start_body", frame)
	var most := RollerPull.SWING_TURN * maxf(now - float(bag["since"]), 0.0)
	var turn := angle_difference(began.basis.get_euler().y, frame.basis.get_euler().y)
	var turned := Basis(Vector3.UP, clampf(turn, -most, most)) * began.basis
	return Transform3D(turned, frame.origin) * (bag["from"] as Transform3D)


## Where a pulled roller passed between the pulling hands goes, at `t` of the
## carry, the body drawn at `frame`: its grip bar (`bar`, the bag's own frame)
## where it was as the move started (`from`, in the body's frame then)
## mirrored across the body, the same pull on the other hand (the hands
## mirror, CarryArm.twist_degrees), its axle where a straight pull trails it on
## that side (RollerPull.TRAIL_SIDE_M out, TRAIL_M back), eased onto `want` (the
## receiving hand's pull) over PULL_SWAP_END. Not `want` itself, which follows
## the hand this move poses: reaching across for the bar, the receiving hand
## drew the pull's end to the giving hand's side, the bar half way was 0.80 m
## from its shoulder, out of its reach, and the bag jumped 0.15 m as it was
## handed over (test_roller_hand_change_reach). Not the whole start mirrored:
## stamped in a turn, the trailing roller was swung 0.18 m wider than a straight
## pull, the goal as far out, and the receiving hand missed the bar by 0.056 m.
static func pull_swap_goal(
	from: Transform3D, want: Transform3D, frame: Transform3D, t: float, bar: Vector3
) -> Transform3D:
	var flip := Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3.BACK)
	var grip := flip * (from * bar)
	var scale_by := from.basis.get_scale().x
	var out := 1.0 if grip.x > 0.0 else -1.0
	var axle := Vector3(
		out * RollerPull.TRAIL_SIDE_M, CarryOnProps.ROLLER_AXLE.y * scale_by, -RollerPull.TRAIL_M
	)
	var goal := frame * RollerPull.pulled(grip, axle, scale_by)
	return goal.interpolate_with(want, smoothstep(PULL_SWAP_END.x, PULL_SWAP_END.y, t))


## Whether the move of `bag` (CarryOnProps' record) takes a roller from one
## hand's carry into the other hand's pull (hand.R>pull.L or hand.L>pull.R),
## outside a toilet stall (`in_stall`).
static func is_hand_pull_swap(bag: Dictionary, in_stall: bool) -> bool:
	var started := start_of(bag)
	return (
		bag["kind"] == SecurityLooks.Kind.ROLLER
		and not in_stall
		and started[0] == End.HELD
		and end_of(bag["home"], bag["carry"]) == End.HELD
		and started[1] != hand_of(bag["home"])
		and bag["carry_from"] == SecurityLooks.Carry.HAND
		and bag["carry"] == SecurityLooks.Carry.PULL
	)


## A roller's turn (the body's frame) at the handover of a hand to pull swap:
## its rods across the body, leaning SWAP_LEAN out ahead from the bar, its
## front face ahead and up (its back panel, with the rods, toward the legs).
static func front_lean() -> Basis:
	var along := Vector3(0.0, cos(SWAP_LEAN), -sin(SWAP_LEAN))
	var face := Vector3(0.0, sin(SWAP_LEAN), cos(SWAP_LEAN))
	return Basis(face.cross(along), face, along)


## A roller's turn (the body's frame) at `t` (0 to 0.5) of a hand to pull swap
## from hand `gave` (0 right), its bar at `bar` (the body's frame) on its way
## round the front: by SWAP_SPIN_T of the carry it leans SWAP_LEAN out from the
## bar, away from the body's centre line, and has turned its front face from
## the body to the outside through ahead, its back panel, with the rods, to the
## legs. From then to half way it keeps that turn as the bar comes round, and at
## half way it is front_lean().
static func swap_lean(bar: Vector3, gave: int, t: float) -> Basis:
	var out := Vector3(bar.x, 0.0, bar.z).normalized()
	var ahead := Vector3(out.z, 0.0, -out.x) * (1.0 if gave == 0 else -1.0)
	var spin := PI * smoothstep(0.0, SWAP_SPIN_T, t)
	var lean := SWAP_LEAN * smoothstep(0.0, SWAP_SPIN_T, t)
	var along := Vector3.UP * cos(lean) - out * sin(lean)
	var face := -out * cos(spin) + ahead * sin(spin)
	face = (face - along * face.dot(along)).normalized()
	return Basis(face.cross(along), face, along)


## Where a roller is at `t` of the carry of a hand to pull swap
## (is_hand_pull_swap()), held at `held_at` (its own frame), the body drawn at
## `frame`, `shoulder_y` its lower shoulder joint's height over the body's
## origin as the move started (stamp_move(), "start_shoulder_y"): its bar
## goes round the front of the body (round_front()) from where it was as the
## move started (`bar_from`, `start` the bag there, world now) to SWAP_FRONT_M
## ahead at hip height (SWAP_HIP_BELOW_M under `shoulder_y`) at half way, and on
## to the other hand's side, mirrored across the body from where the giving
## hand held the bag by its handle as the move started (`from`, the body's
## frame then); eased onto the pull's bar (`want` at `bar_to`) over
## PULL_SWAP_END, as pull_swap_goal() does. The bag turns from its start as
## swap_lean() says, on the hand `gave` gave it from, to front_lean() by half
## way and on to `want`. From the move's stamp and the
## carry's progress only, never from where a hand is drawn (anti-pattern
## d655fcc9).
static func hand_pull_path(
	from: Transform3D,
	start: Transform3D,
	want: Transform3D,
	frame: Transform3D,
	t: float,
	bar_from: Vector3,
	bar_to: Vector3,
	held_at: Vector3,
	shoulder_y: float,
	gave: int
) -> Transform3D:
	var local := frame.affine_inverse()
	var front := Vector3(0.0, shoulder_y - SWAP_HIP_BELOW_M, SWAP_FRONT_M)
	var handle := from * CarryOnProps.ROLLER_HANDLE
	var first := t < 0.5
	var u := smoothstep(0.0, 1.0, t * 2.0 if first else t * 2.0 - 1.0)
	var bar := round_front(local * (start * bar_from), front, u)
	if not first:
		bar = round_front(front, Vector3(-handle.x, handle.y, handle.z), u, SWAP_ROUND_OUT_M)
	var turned := Quaternion(front_lean())
	var was := (local.basis * start.basis).get_rotation_quaternion()
	var to := (local.basis * want.basis).get_rotation_quaternion()
	var turn := turned.slerp(to, u)
	if first:
		# Out of the turn it hung in, over the first tenth of the carry.
		var leaning := Quaternion(swap_lean(bar, gave, t))
		turn = was.slerp(leaning, smoothstep(0.0, SWAP_SPIN_T * 0.4, t))
	var size := start.basis.get_scale().lerp(want.basis.get_scale(), t)
	var basis := frame.basis * Basis(turn).scaled(size)
	var at := (frame * bar).lerp(want * bar_to, smoothstep(PULL_SWAP_END.x, PULL_SWAP_END.y, t))
	return Transform3D(basis, at - basis * held_at)


## A point `u` (0 to 1) of the way from `from` to `to` (the body's frame) round
## the body's centre line: its angle about it, its distance from it and its
## height each go straight from the one to the other, so a point going between
## a side and the front does not cut across the body; its distance is `out`
## more half way, none at either end.
static func round_front(from: Vector3, to: Vector3, u: float, out := 0.0) -> Vector3:
	var angle := lerpf(atan2(from.x, from.z), atan2(to.x, to.z), u)
	var r := lerpf(Vector2(from.x, from.z).length(), Vector2(to.x, to.z).length(), u)
	r += out * sin(PI * u)
	return Vector3(r * sin(angle), lerpf(from.y, to.y, u), r * cos(angle))


## A backpack hanging from the leading hand (`hand` 0 right, 1 left) by its
## grab loop at the side, at `height` (world), of a body drawn at `frame`.
static func back_side(
	centre: Vector3, yaw: float, hand: int, height: float, scale_by: float
) -> Transform3D:
	var out := Vector3.LEFT if hand == 0 else Vector3.RIGHT
	var grip := centre + Basis(Vector3.UP, yaw) * (out * BACK_SIDE_M)
	grip.y = height
	return CarryHand.carried(grip, centre, yaw, scale_by, SecurityLooks.Kind.BACKPACK)


## The hand that leads a backpack's move between the back and a resting end
## at `rest` (world; a tray or the floor) outside a toilet stall, `frame` the
## body's frame as the move started (stamp_move(), "start_body"), `lead` the
## hand lead_hand() gave (the bag's own hand), `scale_by` the bag's scale: the
## hand on the side `rest` lay on, more than BACK_LEAD_SIDE_M out, so the pack
## does not cross the front of the body. Led by the bag's own hand (the open
## side, away from a lane's pickup table), the hand reached across the chest
## and held the pack 1.53 m up and 0.40-0.46 m ahead of it (board 41c159bc).
## Taken from the frame as drawn, the hand changed half way: the walker turns
## from the table to the exit during the move. Not for two bags (scale under
## 1): the other hand may hold the other bag.
static func back_lead(lead: int, rest: Vector3, frame: Transform3D, scale_by: float) -> int:
	if scale_by < 1.0:
		return lead
	var x := (frame.affine_inverse() * rest).x
	if absf(x) <= BACK_LEAD_SIDE_M:
		return lead
	# The body faces +Z: its right is -X.
	return 0 if x < 0.0 else 1


## The leading hand's target `at` at `k` of a move of a backpack on or off the
## back (`from` to `to`), body drawn at `frame` turned to `yaw`, `lead` the
## hand, `shoulder_y` the leading shoulder's height (world) as the move started
## (stamp_move(), "start_shoulder_y", over the body's origin), not the skeleton
## drawn now (board 031cee02): while the hand reaches for the pack on the back
## it comes by the side hang (BACK_SIDE_M out, under the shoulder) and only then
## to the loop, and letting go of it there it goes back out by the side, so
## the arm's blend to and from its own pose does not pass the hand through the
## pack (measured: fingers and the hand inside it, board item 5ed915b0).
static func by_side(
	at: Vector3,
	k: float,
	from: End,
	to: End,
	frame: Transform3D,
	yaw: float,
	lead: int,
	shoulder_y: float,
	below := STALL_HANG_BELOW_M
) -> Vector3:
	var out := Vector3.LEFT if lead == 0 else Vector3.RIGHT
	var side := frame.origin + Basis(Vector3.UP, yaw) * (out * BACK_SIDE_M)
	side.y = shoulder_y - below
	var s := span(from, to)
	if from == End.WORN and k < s.x:
		return side.lerp(at, smoothstep(0.3, 1.0, k / s.x))
	if to == End.WORN and k > s.y:
		return at.lerp(side, smoothstep(0.0, 0.35, (k - s.y) / (1.0 - s.y)))
	return at


## Where a roller's axle is at `t` (0 under the hand at `hung`, 1 at
## `trailing`, both world) of a swap between the hand and the pull at
## security, the body drawn at `frame`, `hand` 0 right: round the hand's side
## of the body (its angle about the body's centre turns from the one to the
## other through the hand's side, as RollerPull.follow() swings a pulled
## roller), at least `clear` from the centre midway, so it passes outside the
## legs. A straight blend with a 0.2 m swing out took it behind the shins of a
## walker standing at a lane (board item 5ed915b0).
static func swap_axle(
	frame: Transform3D, hung: Vector3, trailing: Vector3, t: float, hand: int, clear: float
) -> Vector3:
	var a := frame.affine_inverse() * hung
	var b := frame.affine_inverse() * trailing
	var out := -1.0 if hand == 0 else 1.0
	# Angle from straight behind (0) toward the hand's side (PI / 2).
	var a0 := atan2(a.x * out, -a.z)
	var a1 := atan2(b.x * out, -b.z)
	if a1 < -PI / 2.0:
		a1 += TAU
	var angle := lerpf(a0, a1, t)
	var r := lerpf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length(), t)
	r = maxf(r, clear * 4.0 * t * (1.0 - t))
	return frame * Vector3(out * r * sin(angle), lerpf(a.y, b.y, t), -r * cos(angle))


## Where each hand ([right, left], the bag's own frame, from the point it is
## held by) holds a roller's bar at `t` of a hand swap from the hand `old`
## (0 right, 1 left): SWAP_SPOT_M along the bar either side of its middle, the
## old hand on the side of the bar toward its own side of the body as the move
## started (`from`, the bag in the body's frame then), eased as SWAP_SPOT_T
## says. From the move's stamp and progress only, never from the drawn hands
## (anti-pattern d655fcc9).
static func swap_spots(from: Transform3D, old: int, t: float) -> Array:
	var out := -1.0 if old == 0 else 1.0
	var spot := Vector3(SWAP_SPOT_M * (1.0 if from.basis.x.x * out >= 0.0 else -1.0), 0.0, 0.0)
	var spots := [Vector3.ZERO, Vector3.ZERO]
	spots[old] = spot * smoothstep(0.0, SWAP_SPOT_T.x, t)
	spots[1 - old] = -spot * (1.0 - smoothstep(SWAP_SPOT_T.y, 1.0, t))
	return spots


## How far (world) the hand that has handed a bag of `kind` over to the other
## hand is aimed off the point it held it by (`grip`, the bag's own frame) at
## `t` of the carry, the bag on its path at `on_path`: SWAP_RELEASE_M away from
## the bag's middle, eased in over SWAP_RELEASE_T. From the plan only, never
## from where the hand is drawn (anti-pattern d655fcc9).
static func swap_release(
	kind: SecurityLooks.Kind, grip: Vector3, on_path: Transform3D, t: float
) -> Vector3:
	var away := on_path.basis * (grip - CarryOnProps.bag_box(kind).get_center())
	if away.length() < 0.001:
		return Vector3.ZERO
	return away.normalized() * SWAP_RELEASE_M * smoothstep(SWAP_RELEASE_T.x, SWAP_RELEASE_T.y, t)


## How a hand-led move of `bag` (CarryOnProps' record) goes at `k`, from
## `start` (world now) to `want`, its body drawn at `frame`; `flags` as for
## path(), `body` the body as drawn now: {"hand": the bag's own hand or side,
## "grips": [right, left] grip points (CarryOnProps.grip_of), "shoulders_y":
## [right, left] shoulder joint heights (no longer read: a backpack's side hang
## and a hand to pull swap use the height stamped as the move started,
## "start_shoulder_y"),
## "bar_z": a roller's grip bar along it, "scale": the bag's scale}. Returns
## {"holder", "xf" (the bag at a resting or worn end, or on its path), "anchor"
## (the point of the bag in the holder's grip, its own frame), "targets",
## "weights", "keeps", "drops" (each hand's, right then left; keeps
## floor_keep(), flags "from_floor" and "to_floor"; drops CarryStoop.drops),
## "loops" (each hand's CarryArm.loop_grip: a backpack
## led on or off the back outside a stall, held from BACK_LOOP_UP_TURNING to
## BACK_LOOP_UP over its loop as it turns), "loop_yaw" (loop_yaw()'s weight for
## CarryPlace to turn a loop-held pack plumb and for CarryLeadArms to roll the
## fist palm down, CarryArm.loop_roll; RollerPark plans omit it, so read it
## with a 0.0 default)}.
## A backpack goes on and off the back through a hang at the leading hand's
## side (back_side()); a roller to or from the floor and the pull parks on its
## wheels for the hand to change grip (RollerPark.plan()).
static func plan(
	bag: Dictionary,
	k: float,
	start: Transform3D,
	want: Transform3D,
	frame: Transform3D,
	flags: Dictionary,
	body: Dictionary
) -> Dictionary:
	if bag.get("park", false):
		return RollerPark.plan(bag, k, start, want, frame, flags, body)
	var started := start_of(bag)
	var from_end: End = started[0]
	var to_end := end_of(bag["home"], bag["carry"])
	var from_hand: int = started[1]
	var to_hand := hand_of(bag["home"])
	var lead := lead_hand(from_end, to_end, from_hand, to_hand, body["hand"])
	# A roller handed between its bar and its carry handle (RollerHandover):
	# `first` holds it to half way, the other hand after.
	var first: int = bag.get("handover", -1)
	if first >= 0:
		lead = 1 - first
	var stall: bool = flags.get("in_stall", false)
	var set_down := from_end == End.HELD and to_end == End.REST
	# Set down from the hand in a toilet stall it is down and let go early
	# (STALL_LET_GO): the body shuffles back to the seat as it sits.
	var let_go := STALL_LET_GO if stall and set_down else REACH_SHARE
	var reach := reach_of(bag)
	var off_back: bool = from_end == End.WORN and bag["carry_from"] == SecurityLooks.Carry.BACK
	var on_back: bool = to_end == End.WORN and bag["carry"] == SecurityLooks.Carry.BACK
	if not stall and (off_back and to_end == End.REST or on_back and from_end == End.REST):
		var rest: Vector3 = (want if off_back else start).origin
		lead = back_lead(lead, rest, bag.get("start_body", frame), body["scale"])
	var ease_in := BACK_EASE_IN if off_back else 0.6
	var ph := phase(k, from_end, to_end, from_hand, lead, let_go, reach, ease_in, first)
	var t: float = ph["t"]
	if stall and set_down and k <= span(from_end, to_end, let_go).y:
		# And the hand is on the bag's path at once: the body turns round to sit
		# in one frame, and the bag eased out of the carry pose went through the
		# door ahead (StallCarry.set_down_start).
		ph["weights"][lead] = 1.0
	var loose := anchor(bag["kind"], body["bar_z"])
	if bag["kind"] == SecurityLooks.Kind.SHOULDER:
		# A shoulder bag is lifted on and off the shoulder by its strap's top.
		loose = body["strap_top"]
	var back_move := (off_back or on_back) and not stall
	# The share of the way a loop-held pack has turned to hang plumb under the
	# hand (loop_yaw()), which the arm also rolls its fist palm down by.
	var loop_yaw := 0.0
	if back_move and ph["holder"] == lead:
		loop_yaw = smoothstep(0.0, LOOP_YAW_SHARE, t) * smoothstep(0.0, LOOP_YAW_SHARE, 1.0 - t)
	if back_move:
		loose += BACK_LOOP_UP_TURNING.lerp(BACK_LOOP_UP, loop_yaw) / body["scale"]
	var below := BACK_HANG_BELOW_M if back_move else STALL_HANG_BELOW_M
	# A roller is held by its bar, which moves with its rods (in a stall they
	# stay in, so it is held where the hand had it, BAR_PALM_M off the bar).
	var roller: bool = bag["kind"] == SecurityLooks.Kind.ROLLER
	var anchor_from: Vector3 = loose
	# A lifted roller set down into a tray or onto the floor is held where it
	# hangs from the hand (by its grip bar, rods in), not by the bar as the rods
	# run out: from there the hand went 25 cm up the rods as the move began
	# (board c2bb3bc0). That point is stamped from the bag's geometry as the move
	# starts ("hung_at", CarryPlace.hung_grip(); a returner's put-in keeps its
	# kind's grip), not taken from the hand drawn last: a set-down that cut a
	# pull-to-hand swap short took it from the hand mid-swap, so the plan followed
	# the frames drawn (anti-patterns d655fcc9, 90062867).
	var lifted_down: bool = (
		roller and bag["carry_from"] == SecurityLooks.Carry.HAND and to_end == End.REST
	)
	if from_end == End.HELD and (not roller or flags.get("in_stall", false)):
		anchor_from = bag["anchor_from"]
	elif from_end == End.HELD and lifted_down:
		anchor_from = bag["hung_at"]
		if first >= 0:
			# Handed over, the first hand keeps the bar to half way, on the rods
			# as drawn now: a set-down that cut a pull-to-hand swap short starts
			# with the rods still out, and held at the rods-in point the hand was
			# 0.17 m off the bar (crossing probe --lane, seed 1106001, passenger 7).
			anchor_from.z = loose.z
	# Lying in a tray or on the floor a roller is taken (and left) by its carry
	# handle on top, not by its bar down at the rod line (the forearm went
	# through it, board item 5ed915b0); the hand slides to the bar as it lifts.
	# Standing on its wheels in a toilet stall its bar is on top, and it is held
	# by the bar throughout (decision stall-bag-poses-as-built-bags-stand-
	# upright-against-the-insi).
	var by_handle: bool = roller and not flags.get("in_stall", false)
	if by_handle and from_end == End.REST:
		anchor_from = CarryOnProps.ROLLER_HANDLE
	var anchor_to := loose
	# Between two pulling hands a roller is held by its bar's middle in both
	# (anchor_from above), and goes over to the other side (pull_swap_goal()).
	var pull_swap := is_pull_swap(bag, stall)
	# From one hand's carry into the other's pull the bar comes round the front
	# (hand_pull_path()).
	var hand_swap := is_hand_pull_swap(bag, stall)
	if to_end == End.HELD and not pull_swap:
		anchor_to = want.affine_inverse() * (body["grips"][to_hand] as Vector3)
		if roller:
			# Along the rods, on the bar as the rods are drawn now (they run out
			# or in through the move), not where the end's rods put it: blending
			# the two lengths again took the bar up to 8 cm off the hand passing
			# a pulled roller between hands (crossing probe FLOAT, pull.R>pull.L).
			anchor_to.z = loose.z
	elif by_handle and to_end == End.REST:
		anchor_to = CarryOnProps.ROLLER_HANDLE
	# In a toilet stall (board item c7b0e7be) a bag is set down by its top as it
	# stands (stall_top(): a case's top end, a backpack's grab loop, a roller's
	# bar), from the start: the body turns round to sit in that frame. A
	# backpack is picked up by the point it is carried by, the hand not sliding
	# over it; a hard case by its top while it stands, the hand going over its
	# top front edge to the point it is carried by as it tips (case_tip_grip()):
	# held there from the floor, the hand was beside its side face as it rose.
	var case_up: bool = stall and bag["kind"] == SecurityLooks.Kind.CASE
	if stall and set_down:
		anchor_from = stall_top(bag["kind"], loose, body["scale"])
		anchor_to = anchor_from
	elif case_up and from_end == End.REST and to_end == End.HELD:
		anchor_from = stall_top(bag["kind"], loose, body["scale"])
	elif stall and from_end == End.REST and to_end == End.HELD and not roller:
		anchor_from = anchor_to
	var held_at := anchor_from.lerp(anchor_to, t)
	# A hard case lifted off the floor or out of a tray into the hand outside a
	# stall, and a roller out of a tray, rise to floor_end(), not to `want`, which
	# follows the hand this move poses: out of a lane tray the grip climbed to
	# 1.66 m (a roller's to 1.56 m), the forearm in the case (board 2fd0356b).
	# Only off the floor is a case's palm held over its top (floor_palm()). A
	# roller off the floor parks on its wheels (RollerPark) or is not measured.
	var from_floor: bool = flags.get("from_floor", false)
	var case_up_out: bool = (
		(bag["kind"] == SecurityLooks.Kind.CASE or (roller and not from_floor))
		and not stall
		and from_end == End.REST
		and to_end == End.HELD
	)
	var floor_case: bool = case_up_out and from_floor and not roller
	var on_path: Transform3D
	var shoulder_y := NAN
	if off_back or on_back:
		# The shoulder as the move started, not the skeleton drawn now (a walk or
		# stoop pose moved it; anti-pattern d655fcc9, board 031cee02).
		shoulder_y = frame.origin.y + float(bag["start_shoulder_y"])
		var side := back_side(frame.origin, flags["yaw"], lead, shoulder_y - below, body["scale"])
		# Between the side hang and the hand the pack's middle is kept clear, not
		# its origin (a bottom corner of its back panel): turning between hanging
		# at the side and lying across the front, its body swung into the belly
		# and the hips with the origin clear (board item stall-bags-probe-fails-on-
		# main-at-backpack-out-1-quad-r-vert).
		var by_middle := flags.duplicate()
		by_middle["clear_at"] = CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).get_center()
		by_middle["hand"] = lead
		if off_back and t < BACK_SHARE:
			on_path = start.interpolate_with(side, smoothstep(0.0, 1.0, t / BACK_SHARE))
		elif off_back:
			var u := (t - BACK_SHARE) / (1.0 - BACK_SHARE)
			# Not lifted over a table edge (there is none between the side hang and
			# the hand): lifted TRANSFER_LIFT_M, the hand went over the shoulder, the
			# turning pack round its forearm (stall_bags_probe, backpack_in at k 0.83).
			by_middle["lift"] = 0.0
			on_path = path(side, want, u, frame, frame.affine_inverse() * side, by_middle)
		elif t > 1.0 - BACK_SHARE:
			# From the side hang onto the back the pack's middle is kept clear too,
			# not lifted and not rising (it goes round the hip, then in onto the
			# back as the push fades): blended straight, it cut the corner behind
			# the hip, the hips, the lower back and the thighs in the pack from k
			# 0.62 to 0.70 (test_carry_back_hip_clear; crossing probe --lane, seed
			# 1106001, Hips and Quad.L at k 0.67, board 606ae8a2).
			var u := (t - 1.0 + BACK_SHARE) / BACK_SHARE
			by_middle["lift"] = 0.0
			by_middle["rising"] = false
			var side_local := frame.affine_inverse() * side
			on_path = path(side, want, smoothstep(0.0, 1.0, u), frame, side_local, by_middle)
		else:
			on_path = path(start, side, t / (1.0 - BACK_SHARE), frame, bag["from"], by_middle)
	else:
		# A bag picked up off a stall's floor rises, whatever its origin does (a case
		# stood on its end has its origin higher than flat in the hand).
		var lift := flags
		var goal := want
		if pull_swap:
			goal = pull_swap_goal(bag["from"], want, frame, t, loose)
		if stall and from_end == End.REST and to_end == End.HELD:
			lift = flags.duplicate()
			lift["rising"] = true
			# One bag out to its side midway; two stand on their hands' sides already.
			lift["side"] = STALL_PICK_SIDE_M if body["scale"] >= 1.0 else 0.0
			# It rises to where the hand carries it, not to where the stooping hand
			# is now: the carry end follows the hand, and a path to it led the hand
			# down with it, under the floor (board item c7b0e7be). Not a roller: held by
			# its bar on top it stood up into the stooping head.
			var low: float = frame.origin.y + STALL_CARRY_GRIP_M
			if not roller:
				goal = want.translated(Vector3.UP * maxf(low - (want * anchor_to).y, 0.0))
		elif case_up_out:
			goal = floor_end(frame, want, want * anchor_to)
		on_path = path(start, goal, t, frame, bag["from"], lift)
		if hand_swap:
			# Its handover height is stamped as the move started, not the shoulders
			# drawn now (a walk or stoop pose moved it, Sol review of board 295026a6).
			var low: float = bag["start_shoulder_y"]
			on_path = hand_pull_path(
				bag["from"], start, want, frame, t, anchor_from, anchor_to, held_at, low, from_hand
			)
		# (In a stall path() turns it: upright, tipped late into the carry.)
		if (from_end == End.REST or to_end == End.REST) and not stall:
			# Off the floor or a tray it turns to hang from the hand soon after it
			# rises (off the floor sooner: lying flat it met the thighs); onto one
			# it hangs until it is nearly down (the arm above it).
			var up := UPRIGHT_FROM_FLOOR if flags.get("from_floor", false) else 0.35
			var w := smoothstep(0.0, up, t) if from_end == End.REST else smoothstep(0.65, 1.0, t)
			var q := start.basis.get_rotation_quaternion().slerp(
				want.basis.get_rotation_quaternion(), w
			)
			on_path.basis = Basis(q).scaled(start.basis.get_scale().lerp(want.basis.get_scale(), w))
	if first >= 0:
		# Handed over in front of the body, between its two grips (RollerHandover.
		# to_front()): taken where it hung or trailed, the free hand reached
		# across the body and the forearms crossed, and short of the handle the
		# roller jumped as that hand took it.
		on_path.origin += RollerHandover.to_front(
			on_path, frame, t, float(bag.get("start_shoulder_y", NAN)), anchor_from, anchor_to
		)
	if case_up and from_end == End.REST and to_end == End.HELD:
		# The palm on its top as it tips, world up of the case as path() turns it.
		var palm_up := Vector3.UP * CarryOnProps.FRONT_PALM_M
		held_at = case_tip_grip(
			anchor_from,
			anchor_to,
			stall_tip(t),
			on_path.basis.inverse() * palm_up,
			start.basis.inverse() * palm_up,
			want.basis.inverse() * palm_up
		)
	# A hard case off the floor into the hand is held with the palm over its top
	# (FLOOR_PALM_FADE): the hand and the point the case is placed by both go up.
	# So is a roller off a stall's floor over its bar (stall_bar_palm()).
	var palm := floor_palm(t) if floor_case else 0.0
	if floor_case:
		# Only the part of the palm the end's own held point does not give yet: a
		# front carry holds the case FRONT_PALM_M over its handle, which the grip
		# takes on over the carry (held_at above), and on top of the whole palm
		# it went 0.071 to 0.086 m off the handle face (GRIP_ON 0.07; crossing
		# probe --lane, seed 1106001, passengers 5 and 6 at the repack berth,
		# board a365cb0b). A side carry's point (the edge) is under the handle's
		# top, so it gives none and the palm is whole.
		var end_palm := maxf(anchor_to.y - CarryOnProps.bag_box(bag["kind"]).end.y, 0.0)
		palm = maxf(palm - t * end_palm * float(body["scale"]), 0.0)
	if stall and roller and from_end == End.REST and to_end == End.HELD:
		palm = stall_bar_palm(t)
	var handed_off_tray: bool = first >= 0 and from_end == End.REST
	if handed_off_tray:
		# The hand lifting it out of a tray by its carry handle holds the palm
		# over the handle (RollerHandover.TRAY_PALM_M).
		palm = RollerHandover.TRAY_PALM_M
	held_at += on_path.basis.inverse() * (Vector3.UP * palm)
	# Changing hands, each hand holds a roller's bar at its own spot
	# (swap_spots()); the bag is placed from the holder's.
	var gave := 1 - lead
	var swap := from_end == End.HELD and from_hand == gave
	var spots := [Vector3.ZERO, Vector3.ZERO]
	if swap and roller and first < 0:
		# Its bar lies across the body at the handover (front_lean()).
		var spot_from: Transform3D = Transform3D(front_lean()) if hand_swap else bag["from"]
		spots = swap_spots(spot_from, gave, t)
	# In a roller handover each hand holds its own grip throughout: `first` the
	# one the move starts by, the other the one it ends by.
	if first >= 0:
		spots[first] = anchor_from - held_at
		if handed_off_tray:
			spots[first] += on_path.basis.inverse() * (Vector3.UP * palm)
		spots[lead] = anchor_to - held_at
	var targets := [Vector3.ZERO, Vector3.ZERO]
	for hand in 2:
		match float(ph["targets_at"][hand]):
			-1.0:
				targets[hand] = start * anchor_from + Vector3.UP * palm
			2.0:
				targets[hand] = want * anchor_to
			_:
				targets[hand] = on_path * (held_at + (spots[hand] as Vector3))
	if (swap or first >= 0) and ph["holder"] == lead:
		var grip: Vector3 = held_at + spots[gave]
		targets[gave] += swap_release(bag["kind"], grip, on_path, t)
	if off_back or on_back:
		targets[lead] = by_side(
			targets[lead], k, from_end, to_end, frame, flags["yaw"], lead, shoulder_y, below
		)
	var xf := on_path
	if ph["holder"] < 0:
		xf = start if k < span(from_end, to_end, let_go, reach).x else want
	# Only a hard case, which lies flat on the floor across the feet: a shoulder
	# bag or a backpack lifted with the stoop kept bent the walker deep after a
	# target far ahead (into a lane arch's post). In a stall every kind, stood
	# by the door (a roller lifted with the back straightening early was held
	# short, into the thighs).
	var keeps := [0.0, 0.0]
	if bag["kind"] == SecurityLooks.Kind.CASE or stall:
		keeps[lead] = floor_keep(
			k, from_end, to_end, flags.get("from_floor", false), flags.get("to_floor", false), reach
		)
	# Sitting down in a stall to set a bag down by the door, the back bends
	# first (STALL_HIPS, CarryStoop.drops), as far as the reach needs at any
	# height (kept on).
	var hips := CarryStoop.HIPS_ALL
	if stall and to_end == End.REST:
		keeps[lead] = 1.0
		hips = STALL_HIPS
	elif first >= 0 and (flags.get("from_tray", false) or flags.get("to_tray", false)):
		# A roller handed over at a tray: the hand at the tray leans in to it,
		# the back bent first (STALL_HIPS), as far as the reach needs at table
		# height. Upright, the hand fell 0.3 m short of a lane tray and the
		# roller jumped into it as it was let go (crossing probe --lane, seed
		# 1106001, passenger 4, board a365cb0b G3).
		# Lifted out of one, both hands lean in until the roller comes in toward
		# the body (RollerHandover.TRAY_KEEP): it rises first and comes across
		# late (path()), and with the lean faded at KEEP_T the hand holding it
		# fell 0.15 m short and the roller jumped with it.
		if flags.get("from_tray", false):
			var keep := 1.0 - smoothstep(RollerHandover.TRAY_KEEP.x, RollerHandover.TRAY_KEEP.y, t)
			keeps = [keep, keep]
		else:
			keeps[lead] = floor_keep(k, from_end, to_end, false, true, reach)
		hips = STALL_HIPS
	elif case_up and from_end == End.REST:
		# Reaching down to a case's top to pick it up, the same: with the hips
		# going down with the stoop (to its top, not its handle lower down), the
		# knee came into the case (board item c7b0e7be).
		hips = STALL_HIPS
	return {
		"holder": ph["holder"],
		"xf": xf,
		"anchor": held_at + (spots[ph["holder"]] if ph["holder"] >= 0 else Vector3.ZERO),
		"targets": targets,
		"weights": ph["weights"],
		"keeps": keeps,
		"drops": [hips, hips],
		"loops": [back_move and lead == 0, back_move and lead == 1],
		"loop_yaw": loop_yaw,
	}


## `placed` (a backpack held by its grab loop at `grip`, world) turned `w` (0 to
## 1) of the way about the grip to hang plumb (its z axis up) with its loop (its
## x axis) across `level` (the way the holding hand points, from its shoulder):
## by the smaller of the two turns about up that do so, at most a quarter turn.
## Not turned about up when the hand points straight down.
static func loop_yaw(placed: Transform3D, grip: Vector3, level: Vector3, w: float) -> Transform3D:
	if w <= 0.0:
		return placed
	var upright := Quaternion(placed.basis.z.normalized(), Vector3.UP)
	var plumb := Basis(Quaternion().slerp(upright, w))
	var hung := plumb * placed.basis
	var across := Vector3(level.x, 0.0, level.z)
	var loop := hung.x
	loop.y = 0.0
	var turn := Basis()
	if across.length() >= 0.001 and loop.length() >= 0.001:
		var want := Vector3.UP.cross(across).normalized()
		if want.dot(loop) < 0.0:
			want = -want
		turn = Basis(Vector3.UP, loop.normalized().signed_angle_to(want, Vector3.UP) * w)
	var both := turn * plumb
	return Transform3D(both * placed.basis, grip + both * (placed.origin - grip))


## The path of a moving bag at `k` from `start` (world now) to `want` (world),
## the body drawn at `frame`: a bag going up rises first and then comes across
## (picked up from the floor ahead, CarryMoves.pick_up(), `from_local` its
## start in the body's frame); one going down is lifted on the way, over a
## table edge, and one set down on the floor (`to_floor`) goes out ahead first
## and down late; either way kept `clear` from the body's centre line on the side
## of `hand` (its origin, or the point flag "clear_at" in its own frame), and
## lifted TRANSFER_LIFT_M (or flag "lift") midway when it neither rises nor goes
## to the floor. In a
## toilet stall (`in_stall`) a bag in the hand (`hand_carry`) goes between the
## floor and the front carry ahead of the body with no lift or push out: set
## down straight down, picked up upright first (decision
## stall-bag-poses-as-built-bags-stand-upright-against-the-insi); a tote there
## goes as it does outside (pushed out to its side at the hip, it lay against
## the thigh of a walker sitting down, board item c7b0e7be), but picked up it
## is not pushed out ahead, toward the door. A bag goes up
## when its origin does, or with flag "rising" (plan(): a stall pick-up, which
## also goes flag "side" out to its hand's side midway). Moved
## from CarryPlace.place_bags; the floor set-down added for board item 5ed915b0.
static func path(
	start: Transform3D,
	want: Transform3D,
	k: float,
	frame: Transform3D,
	from_local: Transform3D,
	flags: Dictionary
) -> Transform3D:
	var in_stall: bool = flags.get("in_stall", false)
	var hand_in_stall: bool = in_stall and flags.get("hand_carry", false)
	var placed := start.interpolate_with(want, k)
	var arc := 0.0 if hand_in_stall else 4.0 * k * (1.0 - k)
	var rising: bool = flags.get("rising", want.origin.y > start.origin.y)
	if hand_in_stall and rising:
		# Up fast: hand-led, it rises only after the hand has reached it, and the
		# walker stepping out caught it low with a foot.
		var soon := 1.0 - pow(1.0 - k, 4.0)
		var across := start.origin.lerp(want.origin, k * k)
		var tip := stall_tip(k)
		# Out ahead of the walker's stride as it rises, back to the hand as it
		# tips over, and out to its hand's side midway, off the leg stepping past
		# it (hand-led it hangs where the hand can take it, short of the path).
		var ahead := (
			minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.5, 1.0, k)) * CarryOnProps.PICK_AHEAD_M
		)
		var turn := Basis(Vector3.UP, flags.get("yaw", 0.0))
		var side := Vector3.LEFT if flags.get("hand", 0) == 0 else Vector3.RIGHT
		var out: float = flags.get("side", 0.0) * 4.0 * k * (1.0 - k)
		across += turn * (Vector3.BACK * ahead + side * out)
		placed = Transform3D(
			start.interpolate_with(want, tip).basis,
			Vector3(across.x, lerpf(start.origin.y, want.origin.y, soon), across.z)
		)
	elif hand_in_stall:
		pass
	elif rising and flags.get("from_floor", false) and CarryMoves.picks_up_ahead(from_local):
		var lifted := CarryMoves.pick_up(from_local, frame.affine_inverse() * want, k)
		if in_stall:
			# Not out ahead while the walker is still in the stall (CarryMoves'
			# PICK_AHEAD_M push taken off again, back on by STALL_AHEAD_BACK as it
			# steps out): by a stall's door a tote went through its leaves; across
			# from the door without the side-out of pick_up() it went into the hips,
			# and with no push at all its strap came back into the forearm.
			var ahead := minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.5, 1.0, k))
			var held_back := 1.0 - smoothstep(STALL_AHEAD_BACK.x, STALL_AHEAD_BACK.y, k)
			lifted.origin.z -= ahead * held_back * CarryOnProps.PICK_AHEAD_M
		placed = frame * lifted
	elif rising:
		var across := start.origin.lerp(want.origin, k * k)
		placed.origin.x = across.x
		placed.origin.z = across.z
		placed.origin.y = lerpf(start.origin.y, want.origin.y, 1.0 - pow(1.0 - k, 4.0))
		# Over the knee that steps forward, early in the move, and gone before
		# the bag comes in under the arm that will hold it.
		var early := 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
		placed.origin.y += CarryOnProps.KNEE_LIFT_M * early
	elif flags.get("to_floor", false) and in_stall:
		# A tote set down by a stall's door: out ahead first, up over the thighs
		# of the walker sitting down, then down in front of the knees (straight out
		# ahead at the hip it met the right thigh, board item c7b0e7be), turned to
		# stand as it will by the door as it goes out and held STALL_TOTE_BACK_M
		# short of its place until it goes down (up and turning, it reached into
		# the door's leaves).
		var down := smoothstep(0.55, 1.0, k)
		var out := smoothstep(0.0, 0.35, k)
		var short := Basis(Vector3.UP, flags.get("yaw", 0.0)) * Vector3.BACK * STALL_TOTE_BACK_M
		var ahead := start.origin.lerp(want.origin - short * (1.0 - down), out)
		placed.basis = start.interpolate_with(want, out).basis
		placed.origin = Vector3(ahead.x, lerpf(start.origin.y, want.origin.y, down), ahead.z)
		placed.origin.y += STALL_TOTE_LIFT_M * sin(PI * clampf((k - 0.1) / 0.75, 0.0, 1.0))
	elif flags.get("to_floor", false):
		# Set down on the floor: out ahead first and down late, so it is not
		# low in front of the thighs and the bent knees, lifted only
		# SET_DOWN_LIFT_M (board item 5ed915b0).
		var ahead := start.origin.lerp(want.origin, 1.0 - (1.0 - k) * (1.0 - k))
		placed.origin = Vector3(ahead.x, lerpf(start.origin.y, want.origin.y, k * k), ahead.z)
		placed.origin.y += SET_DOWN_LIFT_M * arc
	else:
		placed.origin.y += flags.get("lift", CarryOnProps.TRANSFER_LIFT_M) * arc
	var clear: float = flags.get("clear", CarryOnProps.TRANSFER_CLEAR_M)
	var yaw: float = flags.get("yaw", 0.0)
	# The point of the bag kept clear: its origin, or flag "clear_at" (its own
	# frame).
	var kept: Vector3 = placed * (flags.get("clear_at", Vector3.ZERO) as Vector3)
	var push := keep_out(kept, frame.origin, yaw, flags.get("hand", 0), clear)
	placed.origin += push * minf(arc * 2.0, 1.0)
	return placed


## How far to push a moving bag at `at` out to `clear` from the centre line of
## a body at `centre` turned to `yaw` (zero when it is already that far out); a
## bag on the centre line goes out on the side of `hand` (0 right, 1 left).
static func keep_out(at: Vector3, centre: Vector3, yaw: float, hand: int, clear: float) -> Vector3:
	var away := at - centre
	away.y = 0.0
	var gap := away.length()
	if gap >= clear:
		return Vector3.ZERO
	if gap < 0.05:
		away = Basis(Vector3.UP, yaw) * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)
	return away.normalized() * (clear - gap)
