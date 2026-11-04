class_name TestRollerRollUpright
extends GdUnitTestSuite
## Leaving a seat with a roller (decision leaving-a-seat-with-a-roller-roll-it-
## upright-until-clear-then-tip, board 2c659e42): a floor>pull stamped with a
## face whose walker has not moved by the park's end rolls the roller upright
## with the body until the body is RollerPark.CLEAR_M from where it stood, then
## tips it into the pull; every other floor>pull tips as before. The rolling
## itself is drawn and measured by spike/cafe_roller_standup_probe.gd
## (ROLLER_CLEAR); these cases pin the decision and its timing on the move's
## record, and that the pick-ups which must not change cannot roll.

const UP := RollerPark.TICKS_UP

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A floor>pull record at its park's end, standing at the origin facing +z.
func _bag(face: bool) -> Dictionary:
	return {
		"up_near": face,
		"ticks": UP,
		"park_at": Vector3.ZERO,
		"park_frame": Transform3D.IDENTITY,
	}


func _at(z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z))


func test_a_faced_pick_up_rolls_until_the_body_is_clear_then_tips() -> void:
	var bag := _bag(true)
	var k := RollerPark.UP_PARK_END + 0.01
	assert_bool(RollerPark._rolling(bag, k, _at(0.0))).is_true()
	assert_bool(RollerPark.rolls(bag)).is_true()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP + RollerPark.ROLL_TICKS)
	# Stepping off, still within CLEAR_M: it keeps rolling.
	assert_bool(RollerPark._rolling(bag, 1.5, _at(RollerPark.CLEAR_M - 0.05))).is_true()
	assert_bool(bag.has("roll_tip")).is_false()
	# Clear: the tip starts, and the move now ends with it.
	assert_bool(RollerPark._rolling(bag, 2.0, _at(RollerPark.CLEAR_M + 0.05))).is_false()
	assert_float(bag["roll_tip"]).is_equal(2.0)
	assert_float(CarryLead.ticks_of(bag)).is_equal((2.0 + RollerPark.TIP_UP) * UP)
	# Decided for good: no rolling again if the body came back.
	assert_bool(RollerPark._rolling(bag, 2.1, _at(0.0))).is_false()


func test_a_roll_that_never_gets_clear_tips_in_time_to_end_with_its_move() -> void:
	var bag := _bag(true)
	assert_bool(RollerPark._rolling(bag, 0.8, _at(0.0))).is_true()
	var last := (UP + RollerPark.ROLL_TICKS) / UP - RollerPark.TIP_UP
	assert_bool(RollerPark._rolling(bag, last - 0.01, _at(0.0))).is_true()
	assert_bool(RollerPark._rolling(bag, last, _at(0.0))).is_false()
	print("forced tip at up %.3f, move %.1f ticks" % [last, CarryLead.ticks_of(bag)])
	assert_float(CarryLead.ticks_of(bag)).is_equal_approx(UP + RollerPark.ROLL_TICKS, 0.001)


## The phases keep their length in ticks when the move grows: the same sim time
## reads the same up_k() before and after.
func test_up_k_is_the_same_across_the_move_growing() -> void:
	var bag := _bag(true)
	var elapsed := 12.5
	var before := RollerPark.up_k(bag, elapsed / CarryLead.ticks_of(bag))
	RollerPark._rolling(bag, before, _at(0.0))
	var after := RollerPark.up_k(bag, elapsed / CarryLead.ticks_of(bag))
	print("up_k %.4f before, %.4f after, move %.1f ticks" % [before, after, bag["ticks"]])
	assert_float(CarryLead.ticks_of(bag)).is_greater(UP)
	assert_float(after).is_equal_approx(before, 0.0001)


## A rolled roller runs its rods out ROLL_RODS of the way while it rolls upright
## (the bar at the standing hand) and the rest over its tip.
## Control: one that tips at once has them out by the move's end.
func test_a_rolled_rollers_rods_are_part_out_until_its_tip() -> void:
	var bag := _bag(true)
	bag["was"] = SecurityLooks.Home.FLOOR * 4
	bag["carry_from"] = SecurityLooks.Carry.PULL
	assert_float(RollerPark.rods_t(0.99, bag)).is_greater(0.9)
	RollerPark._rolling(bag, 0.8, _at(0.0))
	var rolling := RollerPark.rods_t(1.5 * UP / CarryLead.ticks_of(bag), bag)
	RollerPark._rolling(bag, 2.0, _at(RollerPark.CLEAR_M + 0.1))
	var tipped := RollerPark.rods_t(1.0, bag)
	print("rods rolling %.3f, at the tip's end %.3f" % [rolling, tipped])
	assert_float(rolling).is_equal_approx(RollerPark.ROLL_RODS, 0.001)
	assert_float(tipped).is_equal_approx(1.0, 0.001)


## Unchanged (1): a walker that moved during the park (a shower visitor at the
## door, a collecting walker with a face) tips as before; the move keeps its
## length.
func test_a_walker_moved_in_the_park_tips_as_before() -> void:
	var bag := _bag(true)
	bag["park_cut"] = Vector2(0.7, 0.4)
	assert_bool(RollerPark._rolling(bag, 0.8, _at(0.0))).is_false()
	assert_bool(RollerPark.rolls(bag)).is_false()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP)


## Unchanged (2): a pick-up stamped with no face (a collecting walker, security
## repack) tips as before.
func test_a_pick_up_with_no_face_tips_as_before() -> void:
	var bag := _bag(false)
	assert_bool(RollerPark._rolling(bag, 0.8, _at(0.0))).is_false()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP)


## Unchanged (3): the shower's door pick-up and a collecting walker walk off
## before the park ends, so the park is cut ("park_cut") and they never roll.
func test_the_shower_door_and_collecting_walkers_move_before_the_park_ends() -> void:
	var park_end := UP * RollerPark.UP_PARK_END
	print(
		(
			"park ends %.2f ticks in; shower walks off at %d, collecting at %d"
			% [park_end, ActivityPoses.DOOR_OUT_TICKS, ParkRecovery.COLLECT_TICKS]
		)
	)
	assert_float(float(ActivityPoses.DOOR_OUT_TICKS)).is_less(park_end)
	assert_float(float(ParkRecovery.COLLECT_TICKS)).is_less(park_end)


## Unchanged (4): in a toilet stall a roller's pick-up is no parking move.
func test_a_stall_pick_up_is_no_park() -> void:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"led": true,
		"carry_from": SecurityLooks.Carry.PULL,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry": SecurityLooks.Carry.PULL,
	}
	assert_bool(RollerPark.parks(bag, true, SecurityLooks.Home.HAND)).is_false()


## Unchanged (5): a walker on its way (a collecting walker) or at security has
## no face, so its pick-up cannot roll; a gate sitter and a cafe guest standing
## up have one.
func test_only_seats_give_a_pick_up_a_face() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.TO_GATE
	assert_bool(is_nan(RollerPark.sit_face(_world.sim, p))).is_true()
	p.stage = Passenger.Stage.SECURITY
	assert_bool(is_nan(RollerPark.sit_face(_world.sim, p))).is_true()
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.stage = Passenger.Stage.STANDING_UP
	p.seat_object = seat["object_id"]
	assert_bool(is_nan(RollerPark.sit_face(_world.sim, p))).is_false()


## A walker whose home leaves the hand while it rolls (sitting down again)
## tips at once, so the move ends and the roller can be set down again.
func test_a_walker_sitting_down_again_ends_the_roll_at_once() -> void:
	var bag := _bag(true)
	assert_bool(RollerPark._rolling(bag, 0.8, _at(0.0))).is_true()
	bag["home_held"] = true
	assert_bool(RollerPark._rolling(bag, 1.1, _at(0.0))).is_false()
	assert_float(bag["roll_tip"]).is_equal(1.1)
	assert_float(CarryLead.ticks_of(bag)).is_equal((1.1 + RollerPark.TIP_UP) * UP)
