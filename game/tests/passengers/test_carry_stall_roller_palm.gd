class_name TestCarryStallRollerPalm
extends GdUnitTestSuite
## A roller picked up off a toilet stall's floor is held with the grip
## STALL_BAR_PALM_M (world up) over its bar while it rises standing, none on
## the floor and none in the carry (CarryLead.stall_bar_palm(); board item
## f396b087: held at the bar itself the straight right arm lay across the
## roller's top, stall_float_probe seed 903959512, Forearm.R in the roller at
## k 0.55). The palm is a constant, not taken from the hand (anti-pattern
## a-carry-move-must-not-take-its-shape-from-the-hand-it-is-pos): two hand
## heights give the same palm. Controls: the same pick-up outside a stall and a
## roller set down in a stall have no palm.

const BAR_Z := 0.3
const STALL := {"in_stall": true, "hand_carry": true, "hand": 0, "yaw": 0.4, "clear": 0.3}


## A roller's move from a stall's floor into the right hand, as CarryOnProps
## records it, and a body for plan() with the right grip at `grip_y`: [bag,
## body].
static func _pick_up(grip_y: float) -> Array:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": (SecurityLooks.Home.HAND * 2 + 0) * 2,
		"carry": SecurityLooks.Carry.HAND,
		"was": (SecurityLooks.Home.FLOOR * 2 + 0) * 2,
		"carry_from": SecurityLooks.Carry.HAND,
		"reach": CarryLead.STALL_PICK_REACH,
		"from": Transform3D(),
	}
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.2, grip_y, 0.3), Vector3(0.2, 0.9, 0.3)],
		"shoulders_y": [1.4, 1.4],
		"bar_z": BAR_Z,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	return [bag, body]


## The start (standing on the stall's floor) and the end (in the hand).
static func _ends() -> Array[Transform3D]:
	var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.1, 0.03, 0.45))
	var turned := Basis(Vector3.UP, 0.4).rotated(Vector3.FORWARD, 0.6)
	var want := Transform3D(turned, Vector3(0.0, 0.7, 0.3))
	return [start, want]


## How far (world) the leading hand's target is from the roller's grip point
## as drawn on the plan's path at `k`: the bar sliding to the carry's grip
## (loose to the end's, as plan() blends them), its palm taken off.
static func _palm_of(move: Array, k: float, flags: Dictionary, from: Vector3) -> Vector3:
	var ends := _ends()
	var plan := CarryLead.plan(move[0], k, ends[0], ends[1], Transform3D(), flags, move[1])
	var to: Vector3 = ends[1].affine_inverse() * (move[1]["grips"][0] as Vector3)
	to.z = BAR_Z
	var t := CarryLead.carry_t(k, move[0])
	var on := (plan["xf"] as Transform3D) * from.lerp(to, t)
	return (plan["targets"][0] as Vector3) - on


## The palm curve pinned to literals (not CarryLead's constants): 0.04 m at
## most, smoothstepped in over t 0 to 0.25 and out over t 0.55 to 0.70. A
## smoothstep is 0.5 half way, so t 0.125 and 0.625 give half the palm; 0.0625
## is a quarter of the way in, 0.25 * 0.25 * (3 - 0.5) = 0.15625 of the palm.
func test_the_palm_curve_is_zero_at_both_ends_full_on_the_plateau_and_eased_between() -> void:
	var samples := {
		0.0: 0.0,
		0.0625: 0.04 * 0.15625,
		0.125: 0.02,
		0.25: 0.04,
		0.4: 0.04,
		0.5: 0.04,
		0.55: 0.04,
		0.625: 0.02,
		0.7: 0.0,
		0.85: 0.0,
		1.0: 0.0,
	}
	for t in samples:
		print("stall_bar_palm(%s) = %s want %s" % [t, CarryLead.stall_bar_palm(t), samples[t]])
		assert_float(CarryLead.stall_bar_palm(t)).is_equal_approx(samples[t], 0.0001)


func test_the_palm_is_over_the_bar_while_it_rises_and_off_at_both_ends() -> void:
	var bar := CarryLead.anchor(SecurityLooks.Kind.ROLLER, BAR_Z)
	var risen := 0
	for step in 21:
		var k := CarryLead.STALL_PICK_REACH + (1.0 - CarryLead.STALL_PICK_REACH) * step / 20.0
		var t := CarryLead.carry_t(k, _pick_up(0.9)[0])
		var want := Vector3.UP * CarryLead.stall_bar_palm(t)
		var low := _palm_of(_pick_up(0.9), k, STALL, bar)
		var high := _palm_of(_pick_up(1.2), k, STALL, bar)
		assert_vector(low).is_equal_approx(want, Vector3.ONE * 0.0001)
		assert_vector(high).is_equal_approx(want, Vector3.ONE * 0.0001)
		risen += int(low.y > 0.04 * 0.9)
	print("stall roller pick-up: palm near full on %d of 21 steps" % risen)
	assert_int(risen).is_greater(4)


func test_outside_a_stall_and_on_a_stall_set_down_there_is_no_palm() -> void:
	var open := STALL.duplicate()
	open["in_stall"] = false
	var k := 0.5
	var outside := _palm_of(_pick_up(0.9), k, open, CarryOnProps.ROLLER_HANDLE)
	assert_vector(outside).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)
	var move := _pick_up(0.9)
	var bag: Dictionary = move[0]
	bag["home"] = (SecurityLooks.Home.FLOOR * 2 + 0) * 2 + 1
	bag["was"] = (SecurityLooks.Home.HAND * 2 + 0) * 2 + 1
	bag["anchor_from"] = Vector3(0.0, 0.1, 0.2)
	bag.erase("reach")
	var ends := _ends()
	var plan := CarryLead.plan(bag, k, ends[1], ends[0], Transform3D(), STALL, move[1])
	var top := CarryLead.stall_top(SecurityLooks.Kind.ROLLER, CarryLead.anchor(bag["kind"], BAR_Z))
	assert_vector(plan["anchor"]).is_equal_approx(top, Vector3.ONE * 0.0001)
