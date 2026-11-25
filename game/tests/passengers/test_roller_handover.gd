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


func _body(lift := 0.0, hand := R) -> Dictionary:
	return {
		"hand": hand,
		"grips":
		[_frame * (_grips[0] + Vector3.UP * lift), _frame * (_grips[1] + Vector3.UP * lift)],
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
		if holder == first and int(bag["was"]) / 4 == SecurityLooks.Home.TRAY:
			# Lifted out of a tray, the palm is TRAY_PALM_M (world up) over the
			# handle.
			anchor -= xf.basis.inverse() * (Vector3.UP * RollerHandover.TRAY_PALM_M)
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


## Handed over, the roller is moved so the middle of its two grips is ahead of
## the body at hip height at half way (SWAP_FRONT_M for hand moves,
## PULL_FRONT_M upright for pull moves), and at its ends at t 0 and 1. Control:
## with no stamped shoulder height it is not moved.
func test_the_roller_is_handed_over_in_front_of_the_body() -> void:
	var a := Vector3(0.0, 0.03, 0.5)
	var b := CarryOnProps.ROLLER_HANDLE
	var on_path := Transform3D(Basis(Vector3.UP, 1.1), _frame * Vector3(-0.3, 0.4, -0.5))
	var start := _frame * Transform3D(Basis(), Vector3(-0.25, 0.35, 0.05))
	var goal := _frame * Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.1, 0.9, 0.6))
	var bag := {"start_shoulder_y": 1.4}
	var front := _frame * Vector3(0.0, 1.4 - CarryLead.SWAP_HIP_BELOW_M, CarryLead.SWAP_FRONT_M)
	var half := RollerHandover.to_front(on_path, start, goal, _frame, 0.5, bag, a, b)
	var middle := half * ((a + b) * 0.5)
	print("to_front at half way: %.4f m off the front point" % middle.distance_to(front))
	assert_float(middle.distance_to(front)).is_less_equal(0.0001)
	for t: float in [0.0, 1.0]:
		var end_xf := RollerHandover.to_front(on_path, start, goal, _frame, t, bag, a, b)
		assert_float(end_xf.origin.distance_to(on_path.origin)).is_less_equal(0.0001)
	var unmoved := RollerHandover.to_front(on_path, start, goal, _frame, 0.5, {}, a, b)
	assert_float(unmoved.origin.distance_to(on_path.origin)).is_equal(0.0)


## To or from the pull (`pull.R>tray`, `pull.L>tray`, `tray>pull.R`,
## `tray>pull.L`), the roller swings round the pulled side (-X right, +X left)
## clear of the pelvis and legs and stands upright in front of the body at the
## handover. Control: shifting the pulled start to the front without turning it
## upright thrusts the shell within 3 cm of the pelvis centre.
func test_pull_handover_swings_round_the_pulled_side_clear_of_the_body() -> void:
	var pull_r := RollerPull.pulled(_grips[R], Vector3(-0.3, 0.03, -0.6), 1.0)
	var pull_l := RollerPull.pulled(_grips[L], Vector3(0.3, 0.03, -0.6), 1.0)
	var tray := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.1, 0.9, 0.6))
	var pull := SecurityLooks.Carry.PULL
	var hand_r := _place(SecurityLooks.Home.HAND, R)
	var hand_l := _place(SecurityLooks.Home.HAND, L)
	var in_tray := _place(SecurityLooks.Home.TRAY)
	var cases := [
		["pull.R>tray", _bag(hand_r, pull, in_tray, pull, pull_r), pull_r, tray, R, R, 0.375],
		["pull.L>tray", _bag(hand_l, pull, in_tray, pull, pull_l), pull_l, tray, L, L, 0.375],
		["tray>pull.R", _bag(in_tray, pull, hand_r, pull, tray), tray, pull_r, L, R, 0.625],
		["tray>pull.L", _bag(in_tray, pull, hand_l, pull, tray), tray, pull_l, R, L, 0.625],
	]
	for item: Array in cases:
		var label: String = item[0]
		var bag: Dictionary = item[1]
		bag["handover"] = item[4]
		var bar_hand: int = item[5]
		var out_sign := -1.0 if bar_hand == R else 1.0
		var flags := {"in_stall": false, "hand": bar_hand, "yaw": 0.6, "clear": 0.0}
		var start: Transform3D = _frame * (item[2] as Transform3D)
		var want: Transform3D = _frame * (item[3] as Transform3D)
		var ks := [0.15, 0.25, 0.33, 0.375, 0.5, 0.625, 0.67, 0.75, 0.85]
		for step in STEPS + 1:
			ks.append(step / float(STEPS))
		var min_clear := INF
		var saw_side := false
		for k: float in ks:
			var plan := CarryLead.plan(bag, k, start, want, _frame, flags, _body(0.0, bar_hand))
			var local_xf: Transform3D = _frame.affine_inverse() * (plan["xf"] as Transform3D)
			min_clear = minf(min_clear, _pelvis_clearance(local_xf))
			var box_mid := local_xf * Vector3(0.0, 0.1, 0.0)
			if absf(box_mid.z) < 0.12:
				saw_side = true
				assert_float(box_mid.x * out_sign).is_greater(0.25)
		var mid_k: float = item[6]
		var at_mid := CarryLead.plan(bag, mid_k, start, want, _frame, flags, _body(0.0, bar_hand))
		var mid_local: Transform3D = _frame.affine_inverse() * (at_mid["xf"] as Transform3D)
		assert_float(mid_local.basis.z.normalized().dot(Vector3.UP)).is_greater(0.999)
		assert_float((mid_local * Vector3(0.0, 0.1, 0.0)).z).is_greater(0.3)
		# Endpoint C0 continuity with start (k = 0 -> 0.01) and want (k = 0.99 -> 1.0).
		var p0 := CarryLead.plan(bag, 0.0, start, want, _frame, flags, _body(0.0, bar_hand))
		var p01 := CarryLead.plan(bag, 0.01, start, want, _frame, flags, _body(0.0, bar_hand))
		var p99 := CarryLead.plan(bag, 0.99, start, want, _frame, flags, _body(0.0, bar_hand))
		var p1 := CarryLead.plan(bag, 1.0, start, want, _frame, flags, _body(0.0, bar_hand))
		var xf0: Transform3D = p0["xf"]
		var xf01: Transform3D = p01["xf"]
		var xf99: Transform3D = p99["xf"]
		var xf1: Transform3D = p1["xf"]
		assert_float(xf0.origin.distance_to(start.origin)).is_less_equal(0.0001)
		assert_float(xf0.basis.z.distance_to(start.basis.z)).is_less_equal(0.0001)
		assert_float(xf0.origin.distance_to(xf01.origin)).is_less(0.01)
		assert_float(xf1.origin.distance_to(want.origin)).is_less_equal(0.0001)
		assert_float(xf1.basis.z.distance_to(want.basis.z)).is_less_equal(0.0001)
		assert_float(xf99.origin.distance_to(want.origin)).is_less(0.01)
		print("%s: min pelvis clearance %.3f m, side=%s" % [label, min_clear, saw_side])
		assert_bool(saw_side).is_true()
		assert_float(min_clear).is_greater(0.13)
	# Control: pull_r shifted to the front without turning upright clips the pelvis.
	var mid_grip := (Vector3(0.0, 0.03, 0.5) + CarryOnProps.ROLLER_HANDLE) * 0.5
	var front_local := Vector3(0.0, 1.4 - CarryLead.SWAP_HIP_BELOW_M, CarryLead.SWAP_FRONT_M)
	var unrotated := pull_r.translated(front_local - pull_r * mid_grip)
	var clip_clear := _pelvis_clearance(unrotated)
	print("unrotated pull-at-front pelvis clearance: %.3f m" % clip_clear)
	assert_float(clip_clear).is_less(0.05)


## On `pull>tray` and `tray>pull`, the carry-handle hand stays at 0 while the
## roller is behind the hip and blends smoothly across t = 0.50 with no step.
func test_pull_handover_weights_blend_smoothly_across_half_way() -> void:
	var moves := _moves()
	var flags := {"in_stall": false, "hand": R, "yaw": 0.6, "clear": 0.0}
	var into_move: Array = moves["pull.R>tray"]
	var into_bag: Dictionary = (into_move[0] as Dictionary).duplicate()
	into_bag["handover"] = R
	var into_s: Transform3D = _frame * (into_move[1] as Transform3D)
	var into_w: Transform3D = _frame * (into_move[2] as Transform3D)
	var early_in := CarryLead.plan(into_bag, 0.2, into_s, into_w, _frame, flags, _body())
	var mid_in := CarryLead.plan(into_bag, 0.3, into_s, into_w, _frame, flags, _body())
	var pre_in := CarryLead.plan(into_bag, 0.374, into_s, into_w, _frame, flags, _body())
	var post_in := CarryLead.plan(into_bag, 0.376, into_s, into_w, _frame, flags, _body())
	assert_float(early_in["weights"][L]).is_equal(0.0)
	assert_float(mid_in["weights"][L]).is_between(0.05, 0.95)
	assert_float(absf(float(post_in["weights"][L]) - float(pre_in["weights"][L]))).is_less(0.001)
	assert_float(post_in["weights"][L]).is_equal_approx(1.0, 0.001)
	var out_move: Array = moves["tray>pull.R"]
	var out_bag: Dictionary = (out_move[0] as Dictionary).duplicate()
	out_bag["handover"] = L
	var out_s: Transform3D = _frame * (out_move[1] as Transform3D)
	var out_w: Transform3D = _frame * (out_move[2] as Transform3D)
	var pre_out := CarryLead.plan(out_bag, 0.624, out_s, out_w, _frame, flags, _body())
	var post_out := CarryLead.plan(out_bag, 0.626, out_s, out_w, _frame, flags, _body())
	var mid_out := CarryLead.plan(out_bag, 0.69, out_s, out_w, _frame, flags, _body())
	var late_out := CarryLead.plan(out_bag, 0.8, out_s, out_w, _frame, flags, _body())
	assert_float(pre_out["weights"][L]).is_equal_approx(1.0, 0.001)
	assert_float(absf(float(post_out["weights"][L]) - float(pre_out["weights"][L]))).is_less(0.001)
	assert_float(mid_out["weights"][L]).is_between(0.05, 0.95)
	assert_float(late_out["weights"][L]).is_equal(0.0)


## Least horizontal distance from the roller shell and rods (in body-local
## frame `local_xf`) to the passenger's hip segment (|x| <= 0.10 m, z = 0).
static func _pelvis_clearance(local_xf: Transform3D) -> float:
	var best := INF
	for x: float in [-0.16, 0.0, 0.16]:
		for y: float in [0.0, 0.11, 0.225]:
			for z: float in [-0.22, -0.11, 0.0, 0.11, 0.22]:
				var p := local_xf * Vector3(x, y, z)
				best = minf(best, Vector2(maxf(absf(p.x) - 0.10, 0.0), p.z).length())
	for z: float in [0.3, 0.4, 0.5]:
		var rod := local_xf * Vector3(0.0, 0.03, z)
		best = minf(best, Vector2(maxf(absf(rod.x) - 0.10, 0.0), rod.z).length())
	return best


## Under roller-suitcases-full-size-only-on-one-bag-passengers, 2-bag
## passengers never carry a roller, so roller_beside_case() is false and
## tray_turn() keeps the bags' order for every 2-bag passenger.
func test_a_roller_beside_a_case_goes_in_last_and_comes_out_first() -> void:
	for id in range(1, 400):
		var p := Passenger.new()
		p.id = id
		p.carry_on = 2
		var kinds := [SecurityLooks.bag_kind(p, 0), SecurityLooks.bag_kind(p, 1)]
		assert_int(kinds.find(SecurityLooks.Kind.ROLLER)).is_equal(-1)
		assert_bool(SecurityLooks.roller_beside_case(p)).is_false()
		for i in 2:
			assert_int(SecurityLooks.tray_turn(p, i, true)).is_equal(i)
			assert_int(SecurityLooks.tray_turn(p, i, false)).is_equal(i)
