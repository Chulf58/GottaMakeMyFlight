class_name TestCarryLead
extends GdUnitTestSuite
## Hand-led carry-on moves (CarryLead; decision carry-on-bags-stay-in-the-hand-
## during-every-move-no-overhead): at every progress of a move the bag is
## either at an end where it rests or is worn, or placed from a hand's grip;
## the leading hand reaches a bag before it moves and lets go after it lands;
## a change of hand passes the bag between the hands half way; the stoop bends
## only as far as a low target needs. Pure functions, no scene.

const STEPS := 60
const ENDS := [CarryLead.End.HELD, CarryLead.End.WORN, CarryLead.End.REST]


## Every move between every kind of end, sampled through k: while the bag is
## off its start and short of its end (0 < t < 1) it has a holder, the holder
## is aimed at the carry (weight 1 unless an end is held, where it eases in or
## out of the carry pose), and a holder of -1 only happens at a WORN or REST
## end. Control: the sampled moves do have a carried part.
func test_a_moving_bag_is_always_held_or_at_a_resting_end() -> void:
	var carried := 0
	for from: CarryLead.End in ENDS:
		for to: CarryLead.End in ENDS:
			for step in STEPS + 1:
				var k := step / float(STEPS)
				var ph := CarryLead.phase(k, from, to, 0, 0)
				var t: float = ph["t"]
				if ph["holder"] < 0:
					var at_start := k < CarryLead.span(from, to).x
					var end: CarryLead.End = from if at_start else to
					assert_int(end).is_not_equal(CarryLead.End.HELD)
					continue
				assert_int(ph["holder"]).is_equal(0)
				if t > 0.0 and t < 1.0:
					carried += 1
				if from != CarryLead.End.HELD and to != CarryLead.End.HELD:
					assert_float(ph["weights"][0]).is_equal_approx(1.0, 0.0001)
	assert_int(carried).is_greater(STEPS)


## A bag picked up from the floor waits there while the hand reaches it (the
## hand's weight rises from 0), then rises in the hand; a bag set down is let
## go only once it is down, the hand's weight falling to 0 at the end.
func test_the_hand_reaches_a_resting_bag_first_and_lets_go_last() -> void:
	var up := CarryLead.phase(0.0, CarryLead.End.REST, CarryLead.End.HELD, 1, 1)
	assert_int(up["holder"]).is_equal(-1)
	assert_float(up["weights"][1]).is_equal_approx(0.0, 0.0001)
	var reaching := CarryLead.phase(
		CarryLead.REACH_SHARE * 0.5, CarryLead.End.REST, CarryLead.End.HELD, 1, 1
	)
	assert_int(reaching["holder"]).is_equal(-1)
	assert_float(reaching["weights"][1]).is_between(0.2, 0.8)
	var lifted := CarryLead.phase(
		CarryLead.REACH_SHARE + 0.01, CarryLead.End.REST, CarryLead.End.HELD, 1, 1
	)
	assert_int(lifted["holder"]).is_equal(1)
	var down := CarryLead.phase(1.0, CarryLead.End.HELD, CarryLead.End.REST, 0, 0)
	assert_int(down["holder"]).is_equal(-1)
	assert_float(down["weights"][0]).is_equal_approx(0.0, 0.0001)
	var landing := CarryLead.phase(
		1.0 - CarryLead.REACH_SHARE - 0.01, CarryLead.End.HELD, CarryLead.End.REST, 0, 0
	)
	assert_int(landing["holder"]).is_equal(0)
	assert_float(landing["weights"][0]).is_equal_approx(1.0, 0.0001)


## From the right hand to the left: the right hand holds it to half way, where
## the left hand has come fully to it; the left holds it after.
func test_a_change_of_hand_passes_the_bag_half_way() -> void:
	var lead := CarryLead.lead_hand(CarryLead.End.HELD, CarryLead.End.HELD, 0, 1, 0)
	assert_int(lead).is_equal(1)
	var before := CarryLead.phase(0.45, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_int(before["holder"]).is_equal(0)
	assert_float(before["weights"][0]).is_equal_approx(1.0, 0.0001)
	var at := CarryLead.phase(0.5, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_int(at["holder"]).is_equal(1)
	assert_float(at["weights"][1]).is_equal_approx(1.0, 0.0001)
	var after := CarryLead.phase(1.0, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_float(after["weights"][0]).is_equal_approx(0.0, 0.0001)


## A place's end: in a hand carried by hand or pulled is HELD, on the back or
## the shoulder WORN, on the floor, in a tray or new (-1) REST.
func test_ends_of_places() -> void:
	var hand_r := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var hand_l := (SecurityLooks.Home.HAND * 2 + 1) * 2 + 1
	var tray := (SecurityLooks.Home.TRAY * 2 + 0) * 2
	assert_int(CarryLead.end_of(hand_r, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.HELD)
	assert_int(CarryLead.end_of(hand_l, SecurityLooks.Carry.PULL)).is_equal(CarryLead.End.HELD)
	assert_int(CarryLead.end_of(hand_r, SecurityLooks.Carry.BACK)).is_equal(CarryLead.End.WORN)
	assert_int(CarryLead.end_of(tray, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.REST)
	assert_int(CarryLead.end_of(-1, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.REST)
	assert_int(CarryLead.hand_of(hand_l)).is_equal(1)


## The stoop: none for a target the standing arm reaches; some for a bag on
## the floor ahead, enough that the stooped shoulder is within reach; more for
## a lower target. Skeleton-free (CarryStoop.needed).
func test_the_stoop_bends_only_as_far_as_a_low_target_needs() -> void:
	var shoulder := Vector3(-0.2, 1.35, 0.0)
	var pivot := Vector3(0.0, 1.0, 0.0)
	var reach := 0.6
	var waist := Vector3(-0.25, 0.8, 0.1)
	assert_float(CarryStoop.needed(shoulder, pivot, waist, waist, reach)).is_equal(0.0)
	var floor_bag := Vector3(-0.3, 0.45, 0.3)
	var s := CarryStoop.needed(shoulder, pivot, floor_bag, floor_bag, reach)
	assert_float(s).is_between(0.05, 0.99)
	var bent := CarryStoop.stooped(shoulder, pivot, floor_bag, s)
	assert_float(bent.distance_to(floor_bag)).is_less_equal(reach + 0.001)
	var lower := Vector3(-0.3, 0.3, 0.3)
	assert_float(CarryStoop.needed(shoulder, pivot, lower, lower, reach)).is_greater(s)


## The two-bone reach (CarryStoop.two_bone, used by CarryArm): the end lands on
## a target within reach, and each bone keeps its length.
func test_the_two_bone_reach_lands_on_a_target_in_reach() -> void:
	var root := Vector3(0.0, 1.3, 0.0)
	var target := Vector3(0.3, 0.9, 0.3)
	var joints := CarryStoop.two_bone(root, 0.3, 0.35, target, Vector3(1.0, 0.0, -0.5))
	assert_float(joints[1].distance_to(target)).is_less(0.001)
	assert_float(joints[0].distance_to(root)).is_equal_approx(0.3, 0.001)
	assert_float(joints[0].distance_to(joints[1])).is_equal_approx(0.35, 0.001)


## A hand-led move from the floor to the hand interrupted while the hand is
## still reaching for the bag (k under REACH_SHARE) has not left its start, so
## the next move (back to the floor) starts there, resting: its hand reaches
## first and nothing holds the bag at its start. Control: stamped from the old
## end as before (the hand, not held any more) the next move would start HELD,
## the bag in the hand at once. A move past its reach, one that started held
## and one not hand-led have all left their start.
func test_a_move_interrupted_in_its_reach_starts_the_next_where_the_bag_is() -> void:
	var floor_at := (SecurityLooks.Home.FLOOR * 2 + 0) * 2
	var hand_at := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var bag := {
		"was": floor_at,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": hand_at,
		"carry": SecurityLooks.Carry.HAND,
		"led": true,
	}
	assert_bool(CarryLead.at_start(bag, 0.1)).is_true()
	assert_bool(CarryLead.at_start(bag, CarryLead.REACH_SHARE + 0.01)).is_false()
	# The stamp keeps "was" and "carry_from" of a move that has not left.
	var next := bag.duplicate()
	next["home"] = floor_at
	var started := CarryLead.start_of(next)
	assert_int(started[0]).is_equal(CarryLead.End.REST)
	var to := CarryLead.end_of(next["home"], next["carry"])
	assert_int(CarryLead.phase(0.05, started[0], to, started[1], 0)["holder"]).is_equal(-1)
	var stale := next.duplicate()
	stale["was"] = hand_at
	assert_int(CarryLead.start_of(stale)[0]).is_equal(CarryLead.End.HELD)
	var from_hand := stale.duplicate()
	from_hand["home"] = floor_at
	assert_bool(CarryLead.at_start(from_hand, 0.1)).is_false()
	var not_led := bag.duplicate()
	not_led["led"] = false
	assert_bool(CarryLead.at_start(not_led, 0.1)).is_false()


## Whether a move is hand-led is decided when it is stamped and kept to its
## end: one stamped outside a toilet stall stays hand-led when its walker steps
## into the stall, and one stamped inside stays on the stall's path after it
## steps out. A swap is never hand-led. Control: a finished move leads no more.
func test_a_hand_led_move_keeps_its_mode_across_a_stall_change() -> void:
	var held := {"in_stall": false}
	var bag := {"since": 0.0}
	bag["led"] = CarryOnProps._leads(held, bag)
	held["in_stall"] = true
	assert_bool(CarryOnProps._leading(bag, 1.0)).is_true()
	var in_stall := {"since": 0.0}
	in_stall["led"] = CarryOnProps._leads({"in_stall": true}, in_stall)
	assert_bool(CarryOnProps._leading(in_stall, 1.0)).is_false()
	var swap := {"since": 0.0, "swap": true}
	swap["led"] = CarryOnProps._leads({"in_stall": false}, swap)
	assert_bool(CarryOnProps._leading(swap, 1.0)).is_false()
	assert_bool(CarryOnProps._leading(bag, CarryOnProps.TRANSFER_TICKS)).is_false()
