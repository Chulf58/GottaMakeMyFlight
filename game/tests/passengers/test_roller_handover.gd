class_name TestRollerHandover
extends GdUnitTestSuite
## A roller moved between its bar and its carry handle changes grip by a
## two-hand handover (RollerHandover; decision roller-tray-moves-use-a-two-hand-
## handover-the-free-hand-take, board a365cb0b G3): each hand holds one grip
## for the whole move, the first to half way of the carry and the other after,
## so the point the bag is held by never slides between the two. Pure
## functions, no scene.

const STEPS := 50
const R := 0
const L := 1

var _frame := Transform3D(Basis(Vector3.UP, 0.6), Vector3(2.0, 0.0, -1.0))
var _grips := [Vector3(-0.25, 0.75, 0.05), Vector3(0.25, 0.75, 0.05)]


## Place code of a bag (CarryOnProps: (home * 2 + hand) * 2 + lifted).
static func _place(home: SecurityLooks.Home, hand := R) -> int:
	return (home * 2 + hand) * 2


## The bag record of a roller move from `was` (carried `carry_from`) to `home`
## (carried `carry`), its start `from` in the body's frame.
func _bag(was: int, carry_from: int, home: int, carry: int, from: Transform3D) -> Dictionary:
	return {
		"kind": SecurityLooks.Kind.ROLLER,
		"was": was,
		"carry_from": carry_from,
		"home": home,
		"carry": carry,
		"from": from,
		"led": true,
		"hung_at": Vector3(0.0, 0.08, 0.3),
		"anchor_from": Vector3(0.0, 0.08, 0.3),
		"start_shoulder_y": 1.4,
	}


func _body(lift := 0.0) -> Dictionary:
	return {
		"hand": R,
		"grips": [_frame * (_grips[0] + Vector3.UP * lift), _frame * _grips[1]],
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.5,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}


## The moves: name -> [bag, start (world), want (world), first hand].
func _moves() -> Dictionary:
	var pull_r := RollerPull.pulled(_grips[0], Vector3(-0.3, 0.03, -0.6), 1.0)
	var in_hand := Transform3D(Basis(), Vector3(-0.25, 0.35, 0.05))
	var tray := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.1, 0.9, 0.6))
	var floor_at := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.3, 0.1, 0.5))
	var pull := SecurityLooks.Carry.PULL
	var hand := SecurityLooks.Carry.HAND
	var hand_r := _place(SecurityLooks.Home.HAND)
	var in_tray := _place(SecurityLooks.Home.TRAY)
	var on_floor := _place(SecurityLooks.Home.FLOOR)
	return {
		"pull.R>tray": [_bag(hand_r, pull, in_tray, pull, pull_r), pull_r, tray, R],
		"hand.R>tray": [_bag(hand_r, hand, in_tray, hand, in_hand), in_hand, tray, R],
		"hand.R>floor": [_bag(hand_r, hand, on_floor, hand, in_hand), in_hand, floor_at, R],
		"tray>hand.R": [_bag(in_tray, pull, hand_r, hand, tray), tray, in_hand, L],
		"tray>pull.R": [_bag(in_tray, pull, hand_r, pull, tray), tray, pull_r, L],
	}


## Each holder's anchor (the bag's own frame) over the move, with the move
## handed over by `first` (-1: not handed over): {holder: [anchors]}.
func _anchors(move: Array, first: int, lift := 0.0) -> Dictionary:
	var bag: Dictionary = (move[0] as Dictionary).duplicate()
	if first >= 0:
		bag["handover"] = first
	var flags := {"in_stall": false, "hand": R, "yaw": 0.6, "clear": 0.0}
	var start: Transform3D = _frame * (move[1] as Transform3D)
	var want: Transform3D = _frame * (move[2] as Transform3D)
	var out := {}
	for step in STEPS + 1:
		var k := step / float(STEPS)
		var plan := CarryLead.plan(bag, k, start, want, _frame, flags, _body(lift))
		var holder: int = plan["holder"]
		if holder < 0:
			continue
		var xf: Transform3D = plan["xf"]
		var anchor: Vector3 = plan["anchor"]
		# The holder is aimed at the point it holds, on the bag's path.
		assert_float((xf * anchor).distance_to(plan["targets"][holder])).is_less_equal(0.0001)
		out.get_or_add(holder, []).append(anchor)
	return out


## The largest distance between any two of `points`.
static func _spread(points: Array) -> float:
	var most := 0.0
	for a: Vector3 in points:
		for b: Vector3 in points:
			most = maxf(most, a.distance_to(b))
	return most


## Handed over, each of the two hands holds one fixed point of the roller for
## the whole move, the first hand its start's grip (the bar, or the carry
## handle off a tray) and the other the end's (the carry handle into a tray or
## onto the floor); both hands hold it in turn. Control: the same moves with no
## handover slide the one hand's held point more than 0.1 m.
func test_each_hand_holds_one_grip_through_the_move() -> void:
	var moves := _moves()
	for name: String in moves:
		var move: Array = moves[name]
		var first: int = move[3]
		var handed := _anchors(move, first)
		var alone := _anchors(move, -1)
		var slide := 0.0
		for holder: int in alone:
			slide = maxf(slide, _spread(alone[holder]))
		var spreads := []
		for holder: int in handed:
			spreads.append(_spread(handed[holder]))
		print("%s: handed spreads %s, alone slides %.3f m" % [name, spreads, slide])
		assert_bool(handed.has(first) and handed.has(1 - first)).is_true()
		for holder: int in handed:
			assert_float(_spread(handed[holder])).is_less_equal(0.0001)
		var bag: Dictionary = move[0]
		var from_tray: bool = int(bag["was"]) / 4 == SecurityLooks.Home.TRAY
		var to_rest: bool = int(bag["home"]) / 4 != SecurityLooks.Home.HAND
		var handle := CarryOnProps.ROLLER_HANDLE
		if from_tray:
			assert_vector(handed[first][0]).is_equal_approx(handle, Vector3.ONE * 0.0001)
		if to_rest:
			assert_vector(handed[1 - first][0]).is_equal_approx(handle, Vector3.ONE * 0.0001)
		assert_float(slide).is_greater(0.1)


## The first hand holds the roller to half way of the carry, the other from
## there on; the hand that gives it lets go away from its grip after (its
## target off the point it held). Into a tray the hand that ends with it has
## come fully to it by half way.
func test_the_first_hand_gives_the_roller_over_half_way() -> void:
	var held := CarryLead.End.HELD
	var rest := CarryLead.End.REST
	var before := CarryLead.phase(0.3, held, rest, R, L, 0.25, 0.25, 0.6, R)
	assert_int(before["holder"]).is_equal(R)
	var at := CarryLead.phase(0.375, held, rest, R, L, 0.25, 0.25, 0.6, R)
	assert_int(at["holder"]).is_equal(L)
	assert_float(at["weights"][L]).is_equal_approx(1.0, 0.0001)
	assert_float(at["weights"][R]).is_equal_approx(1.0, 0.0001)
	var up := CarryLead.phase(0.1, rest, held, R, R, 0.25, 0.25, 0.6, L)
	assert_int(up["holder"]).is_equal(-1)
	assert_float(up["weights"][L]).is_greater(0.0)
	assert_float(up["weights"][R]).is_equal_approx(0.0, 0.0001)
	var lifted := CarryLead.phase(0.4, rest, held, R, R, 0.25, 0.25, 0.6, L)
	assert_int(lifted["holder"]).is_equal(L)
	var taken := CarryLead.phase(0.7, rest, held, R, R, 0.25, 0.25, 0.6, L)
	assert_int(taken["holder"]).is_equal(R)
	# Control: no handover, the one hand holds it throughout.
	var alone := CarryLead.phase(0.7, rest, held, R, R)
	assert_int(alone["holder"]).is_equal(R)
	assert_float(alone["weights"][L]).is_equal_approx(0.0, 0.0001)


## The plan is the same whatever height the holding hand is drawn at
## (anti-pattern d655fcc9): each hand's target from the move's stamp only.
func test_the_handover_does_not_follow_the_drawn_hand() -> void:
	var moves := _moves()
	var flags := {"in_stall": false, "hand": R, "yaw": 0.6, "clear": 0.0}
	var compared := 0
	for name: String in ["pull.R>tray", "hand.R>tray"]:
		var move: Array = moves[name]
		var bag: Dictionary = (move[0] as Dictionary).duplicate()
		bag["handover"] = R
		var start: Transform3D = _frame * (move[1] as Transform3D)
		var want: Transform3D = _frame * (move[2] as Transform3D)
		for k: float in [0.2, 0.4, 0.6]:
			var low := CarryLead.plan(bag, k, start, want, _frame, flags, _body())
			var high := CarryLead.plan(bag, k, start, want, _frame, flags, _body(0.2))
			for hand in 2:
				var a: Vector3 = low["targets"][hand]
				assert_float(a.distance_to(high["targets"][hand])).is_less_equal(0.0001)
				compared += 1
	assert_int(compared).is_equal(12)


## The handover is stamped on a roller between its bar and a tray or the
## floor when the free hand is free: not when the free hand holds another bag,
## nor while another bag set down from it is short of half way (its hand lets
## go late); yes once that bag is past half way, and for a worn bag on that
## side. Never on a hard case, nor in a toilet stall.
func test_the_handover_waits_for_a_free_hand() -> void:
	var moves := _moves()
	var roller: Dictionary = (moves["pull.R>tray"][0] as Dictionary).duplicate()
	var hand_l := _place(SecurityLooks.Home.HAND, L)
	var tray_l := _place(SecurityLooks.Home.TRAY, L)
	var other := {
		"kind": SecurityLooks.Kind.CASE, "home": hand_l, "carry": SecurityLooks.Carry.HAND
	}
	var held := {
		"bags": [roller, other],
		"homes": [SecurityLooks.Home.TRAY, SecurityLooks.Home.HAND],
		"hands": [R, L],
		"in_stall": false,
	}
	RollerHandover.stamp(roller, held, 0, 10.0)
	assert_bool(roller.has("handover")).is_false()
	# The case set down into its tray from the left hand, just started.
	other.merge(
		{"home": tray_l, "was": hand_l, "carry_from": SecurityLooks.Carry.HAND, "since": 9.5}, true
	)
	held["homes"] = [SecurityLooks.Home.TRAY, SecurityLooks.Home.TRAY]
	RollerHandover.stamp(roller, held, 0, 10.0)
	assert_bool(roller.has("handover")).is_false()
	# Past half way of its move: the left hand lets go before it is needed.
	other["since"] = 6.0
	RollerHandover.stamp(roller, held, 0, 10.0)
	assert_int(roller.get("handover", -1)).is_equal(R)
	# A backpack worn on the left: free.
	held["bags"][1] = {
		"kind": SecurityLooks.Kind.BACKPACK, "home": hand_l, "carry": SecurityLooks.Carry.BACK
	}
	held["homes"] = [SecurityLooks.Home.TRAY, SecurityLooks.Home.HAND]
	RollerHandover.stamp(roller, held, 0, 10.0)
	assert_int(roller.get("handover", -1)).is_equal(R)
	# Out of a tray into the right hand, the left lifts it first.
	var up: Dictionary = (moves["tray>hand.R"][0] as Dictionary).duplicate()
	RollerHandover.stamp(up, {"bags": [up], "homes": [1], "hands": [R]}, 0, 10.0)
	assert_int(up.get("handover", -1)).is_equal(L)
	# In a toilet stall, or a hard case: none.
	held["in_stall"] = true
	RollerHandover.stamp(roller, held, 0, 10.0)
	assert_bool(roller.has("handover")).is_false()
	held["in_stall"] = false
	var case_bag := roller.duplicate()
	case_bag["kind"] = SecurityLooks.Kind.CASE
	RollerHandover.stamp(case_bag, held, 0, 10.0)
	assert_bool(case_bag.has("handover")).is_false()
