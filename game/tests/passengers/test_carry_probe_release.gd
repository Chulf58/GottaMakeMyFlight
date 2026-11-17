class_name TestCarryProbeRelease
extends GdUnitTestSuite
## The carry probes' gripping hands in a hand swap (game/spike/
## carry_probe_checks.gd, releasing_hand(); board 2237fa05): the hand that has
## handed a roller over still grips it while the move's plan aims it at the bag
## by more than RELEASE_WEIGHT, so its fingers round the bar are not a
## self-clip; once that weight is down, or with no plan or no swap, it is not
## gripping and its points in the bag count. Pure functions, no scene.

const CarryChecks := preload("res://spike/carry_probe_checks.gd")


## A hand.R>pull.L move planned as CarryOnProps plans it, with the record the
## probe reads (CarryOnProps.bag_state()) at `k`: its "held_by" and "lead".
static func _state(k: float, was := 4) -> Dictionary:
	var frame := Transform3D()
	var grips := [Vector3(-0.25, 0.75, 0.05), Vector3(0.25, 0.75, 0.05)]
	var in_hand := Transform3D(Basis(), Vector3(-0.25, 0.35, 0.05))
	var pull := RollerPull.pulled(grips[1], Vector3(0.3, 0.03, -0.6), 1.0)
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": 6,
		"carry": SecurityLooks.Carry.PULL,
		"was": was,
		"carry_from": SecurityLooks.Carry.HAND,
		"from": in_hand,
		"anchor_from": Vector3.ZERO,
	}
	var body := {
		"hand": 0,
		"grips": grips,
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.7,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {"in_stall": false, "hand": 0, "yaw": 0.0, "clear": 0.0}
	var plan := CarryLead.plan(bag, k, in_hand, pull, frame, flags, body)
	bag["lead"] = plan
	bag["held_by"] = plan["holder"]
	return bag


## Handed over at k 0.55 (the right hand's weight about 0.97) the right hand
## still grips; at k 0.9 (weight about 0.1) it does not. Controls: at k 0.45
## it is the holder (gripping() counts it as that), a plan with no weight on
## it, no plan at all, and a move that started in the left hand give none.
func test_a_releasing_hand_grips_only_while_its_plan_holds_it() -> void:
	var on := _state(0.55)
	var off := _state(0.9)
	print(
		(
			"right hand weight at 0.55: %.3f, at 0.9: %.3f"
			% [on["lead"]["weights"][0], off["lead"]["weights"][0]]
		)
	)
	assert_int(on["held_by"]).is_equal(1)
	assert_int(CarryChecks.releasing_hand(on)).is_equal(0)
	assert_float(off["lead"]["weights"][0]).is_less(CarryChecks.RELEASE_WEIGHT)
	assert_int(CarryChecks.releasing_hand(off)).is_equal(-1)
	var holding := _state(0.45)
	assert_int(holding["held_by"]).is_equal(0)
	assert_int(CarryChecks.releasing_hand(holding)).is_equal(-1)
	var weightless := on.duplicate(true)
	weightless["lead"]["weights"] = [0.0, 1.0]
	assert_int(CarryChecks.releasing_hand(weightless)).is_equal(-1)
	var unplanned := on.duplicate(true)
	unplanned.erase("lead")
	assert_int(CarryChecks.releasing_hand(unplanned)).is_equal(-1)
	assert_int(CarryChecks.releasing_hand(_state(0.55, 6))).is_equal(-1)
