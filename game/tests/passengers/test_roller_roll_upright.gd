class_name TestRollerRollUpright
extends GdUnitTestSuite
## Leaving a seat with a roller (decision leaving-a-seat-with-a-roller-roll-it-
## upright-until-clear-then-tip, board 2c659e42): a floor>pull stamped with a
## face whose walker has not moved by the park's end rolls the roller upright
## with the body until the body is RollerPark.CLEAR_M from where it stood, then
## tips it into the pull; every other floor>pull tips as before. The rolling
## itself is drawn and measured by spike/cafe_roller_standup_probe.gd
## (ROLLER_CLEAR); these cases pin the decision and its timing on the move's
## record, taken on sim ticks (RollerPark.roll_step(), board c0707a22), and
## that the pick-ups which must not change cannot roll.

const UP := RollerPark.TICKS_UP
## The most a not-rolled pick-up's rods may run out in one tick: a smoothstep
## over RODS_OUT_TICKS steps at most 0.48 a tick.
const RODS_STEP := 0.5

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A floor>pull record stamped on tick 0 (its "changed" and "since"), with a
## face when `face`.
func _bag(face: bool) -> Dictionary:
	return {
		"park": true,
		"park_up": true,
		"since": 0.0,
		"up_near": face,
		"ticks": UP,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
	}


## Steps `bag` through sim ticks `from` to `to` (inclusive) with its walker at
## z `z` (roll_step(), as CarryOnProps.sync() does each tick).
func _ticks(bag: Dictionary, from: int, to: int, z: float, face := true) -> void:
	for n in range(from, to + 1):
		RollerPark.roll_step(
			bag, SecurityLooks.Kind.ROLLER, float(n), Vector3(0.0, 0.0, z), 0.0 if face else NAN
		)


func test_a_faced_pick_up_rolls_until_the_body_is_clear_then_tips() -> void:
	var bag := _bag(true)
	# Undecided before the park's nominal end, decided on that tick.
	_ticks(bag, 0, int(RollerPark.ROLL_TO) - 1, 0.0)
	assert_bool(bag.has("rolls")).is_false()
	_ticks(bag, int(RollerPark.ROLL_TO), int(RollerPark.ROLL_TO), 0.0)
	assert_bool(RollerPark.rolls(bag)).is_true()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP + RollerPark.ROLL_TICKS)
	assert_bool(RollerPark._rolling(bag, RollerPark.UP_PARK_END + 0.01)).is_true()
	# Stepping off, still within CLEAR_M: it keeps rolling.
	_ticks(bag, 12, 20, RollerPark.CLEAR_M - 0.05)
	assert_bool(bag.has("roll_tip")).is_false()
	assert_bool(RollerPark._rolling(bag, 21.0 / UP)).is_true()
	# Clear on tick 21: drawn a tick behind, the tip starts on tick 22, and the
	# move now ends with it.
	_ticks(bag, 21, 21, RollerPark.CLEAR_M + 0.05)
	assert_float(bag["roll_tip"]).is_equal(22.0 / UP)
	assert_float(CarryLead.ticks_of(bag)).is_equal((22.0 / UP + RollerPark.TIP_UP) * UP)
	assert_bool(RollerPark._rolling(bag, 21.9 / UP)).is_true()
	assert_bool(RollerPark._rolling(bag, 22.0 / UP)).is_false()
	# Decided for good: no rolling again if the body came back.
	_ticks(bag, 22, 23, 0.0)
	assert_float(bag["roll_tip"]).is_equal(22.0 / UP)


func test_a_roll_that_never_gets_clear_tips_in_time_to_end_with_its_move() -> void:
	var bag := _bag(true)
	var last := (UP + RollerPark.ROLL_TICKS) / UP - RollerPark.TIP_UP
	_ticks(bag, 0, floori(last * UP) - 1, 0.0)
	assert_bool(bag.has("roll_tip")).is_false()
	_ticks(bag, floori(last * UP), floori(last * UP), 0.0)
	assert_float(bag["roll_tip"]).is_equal(last)
	assert_bool(RollerPark._rolling(bag, last - 0.01)).is_true()
	assert_bool(RollerPark._rolling(bag, last)).is_false()
	print("forced tip at up %.3f, move %.1f ticks" % [last, CarryLead.ticks_of(bag)])
	assert_float(CarryLead.ticks_of(bag)).is_equal_approx(UP + RollerPark.ROLL_TICKS, 0.001)


## The phases keep their length in ticks when the move grows: the same sim time
## reads the same up_k() before and after.
func test_up_k_is_the_same_across_the_move_growing() -> void:
	var bag := _bag(true)
	var elapsed := 12.5
	var before := RollerPark.up_k(bag, elapsed / CarryLead.ticks_of(bag))
	_ticks(bag, 0, int(RollerPark.ROLL_TO), 0.0)
	var after := RollerPark.up_k(bag, elapsed / CarryLead.ticks_of(bag))
	print("up_k %.4f before, %.4f after, move %.1f ticks" % [before, after, bag["ticks"]])
	assert_float(CarryLead.ticks_of(bag)).is_greater(UP)
	assert_float(after).is_equal_approx(before, 0.0001)


## A rolled move has left its start (CarryLead.at_start()) by the same tick
## as a plain one: its reach is in TICKS_UP ticks, not a share of the longer
## move (12 ticks in, k 12/52, read as still reaching, so a new move stamped
## then started over from the floor). Control: 3 ticks in it is reaching.
func test_a_rolled_move_leaves_its_start_on_the_same_tick() -> void:
	var bag := _bag(true)
	bag["led"] = true
	_ticks(bag, 0, int(RollerPark.ROLL_TO), 0.0)
	var ticks := CarryLead.ticks_of(bag)
	assert_float(ticks).is_equal(UP + RollerPark.ROLL_TICKS)
	assert_bool(CarryLead.at_start(bag, 12.0 / ticks)).is_false()
	assert_bool(CarryLead.at_start(bag, 3.0 / ticks)).is_true()


## Taken late (first drawn past the lift, "park_took" 0.5625: its park and
## SETTLE_TICKS end past k 1), a pick-up that rolls keeps its rods in on its
## first frame (still undecided) and once it rolls; the not-rolled smoothstep's
## edges were the wrong way round there and drew them all out on the first
## frame, then in again once it rolled.
func test_a_late_take_keeps_the_rods_in_until_its_park_ends() -> void:
	var bag := _bag(true)
	bag["park_took"] = 9.0 / UP
	var park := RollerPark.up_ends(bag).y + RollerPark.SETTLE_TICKS / UP
	print("late take: park and settle end at up %.4f" % park)
	assert_float(park).is_greater(1.0)
	assert_float(RollerPark.rods_t(9.0 / UP, bag)).is_equal(0.0)
	_ticks(bag, 0, int(RollerPark.ROLL_TO), 0.0)
	assert_float(RollerPark.rods_t(11.0 / CarryLead.ticks_of(bag), bag)).is_equal(0.0)


## Taken late and not rolling (no face here; the shower's door the same), first
## drawn 9 or 12 ticks in (its park ending at up 0.94 or 1.13): its rods stay in
## through the park, or to RODS_OUT_TICKS before the move's end when the park
## leaves no room, then run out, never back in, all out as the move ends, no
## tick running them out more than RODS_STEP: never held in to the end and
## snapped to the pull's reach (Sol final re-check of af14ddf: drawn 12 ticks
## late they stayed in to k 1), nor all run out in the park's last tick.
## Control: a pick-up taken on time keeps SETTLE_TICKS after its park before
## its rods move.
func test_a_late_take_that_does_not_roll_runs_its_rods_out_by_its_end() -> void:
	var room := 1.0 - RollerPark.RODS_OUT_TICKS / UP
	for late: int in [9, 12]:
		var bag := _bag(false)
		bag["park_took"] = late / UP
		_ticks(bag, 0, 14, 0.0, false)
		assert_bool(bag.has("rolls")).is_true()
		assert_bool(RollerPark.rolls(bag)).is_false()
		var park := RollerPark.up_ends(bag).y
		var held_to := minf(park, room)
		var last := 0.0
		var step := 0.0
		var moved_at := INF
		for n in range(late, int(UP) + 1):
			var k := n / UP
			var now := RollerPark.rods_t(k, bag)
			var line := "late%d k %.4f" % [late, k]
			if k <= held_to:
				assert_float(now).override_failure_message(line).is_equal(0.0)
			elif now > 0.0:
				moved_at = minf(moved_at, k)
			assert_float(now).override_failure_message(line).is_greater_equal(last)
			step = maxf(step, now - last)
			last = now
		print(
			(
				"late%d, not rolled: park ends %.4f, rods out from %.4f, %.3f at k 1, at most %.3f a tick"
				% [late, park, moved_at, last, step]
			)
		)
		assert_float(last).override_failure_message("late%d" % late).is_equal_approx(1.0, 0.0001)
		assert_float(step).override_failure_message("late%d" % late).is_less_equal(RODS_STEP)
	var on_time := _bag(false)
	on_time["park_took"] = 0.3
	var settle := RollerPark.up_ends(on_time).y + RollerPark.SETTLE_TICKS / UP
	assert_float(RollerPark.rods_t(settle, on_time)).is_equal(0.0)
	assert_float(RollerPark.rods_t(settle + 0.01, on_time)).is_greater(0.0)


## A rolled roller runs its rods out ROLL_RODS of the way while it rolls upright
## (the bar at the standing hand) and the rest over its tip.
## Control: one that tips at once has them out by the move's end.
func test_a_rolled_rollers_rods_are_part_out_until_its_tip() -> void:
	var bag := _bag(true)
	assert_float(RollerPark.rods_t(0.99, bag)).is_greater(0.9)
	_ticks(bag, 0, int(RollerPark.ROLL_TO), 0.0)
	var rolling := RollerPark.rods_t(1.5 * UP / CarryLead.ticks_of(bag), bag)
	_ticks(bag, 31, 31, RollerPark.CLEAR_M + 0.1)
	var tipped := RollerPark.rods_t(1.0, bag)
	print("rods rolling %.3f, at the tip's end %.3f" % [rolling, tipped])
	assert_float(rolling).is_equal_approx(RollerPark.ROLL_RODS, 0.001)
	assert_float(tipped).is_equal_approx(1.0, 0.001)


## Unchanged (1): a walker that moved during the park (a shower visitor at the
## door, a collecting walker with a face) tips as before; the move keeps its
## length. Control: the same walker moving only after ROLL_TO rolls.
func test_a_walker_moved_in_the_park_tips_as_before() -> void:
	var bag := _bag(true)
	_ticks(bag, 0, 9, 0.0)
	_ticks(bag, 10, 12, 0.05)
	assert_bool(bag.has("rolls")).is_true()
	assert_bool(RollerPark.rolls(bag)).is_false()
	assert_bool(RollerPark._rolling(bag, 0.8)).is_false()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP)
	var later := _bag(true)
	_ticks(later, 0, int(RollerPark.ROLL_TO), 0.0)
	_ticks(later, int(RollerPark.ROLL_TO) + 1, 14, 0.05)
	assert_bool(RollerPark.rolls(later)).is_true()


## Unchanged (2): a pick-up stamped with no face (a collecting walker, security
## repack) tips as before.
func test_a_pick_up_with_no_face_tips_as_before() -> void:
	var bag := _bag(false)
	_ticks(bag, 0, 14, 0.0, false)
	assert_bool(RollerPark.rolls(bag)).is_false()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP)


## The record a draw stamps late (RollerPark.stamp(), on its first frame) takes
## what the sim already decided: the face the walker had on the move's first
## tick, not on that frame, the roll and its length, and a tip already seen.
## Control: a stamp with no sim record yet decides nothing.
func test_a_late_stamp_takes_the_sims_decision() -> void:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"changed": 0.0,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"from": Transform3D.IDENTITY,
	}
	_ticks(bag, 0, 0, 0.0)
	_ticks(bag, 1, 14, 0.0, false)
	assert_bool(bag.has("rolls")).is_false()
	bag["since"] = 0.0
	RollerPark.stamp(bag, Transform3D.IDENTITY, NAN)
	assert_bool(bag["up_near"]).is_true()
	assert_bool(RollerPark.rolls(bag)).is_true()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP + RollerPark.ROLL_TICKS)
	_ticks(bag, 15, 30, RollerPark.CLEAR_M + 0.1)
	var tip: float = bag["roll_tip"]
	RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
	assert_float(bag["roll_tip"]).is_equal(tip)
	var fresh := {
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"from": Transform3D.IDENTITY,
		"since": 0.0,
	}
	RollerPark.stamp(fresh, Transform3D.IDENTITY, 0.0)
	assert_bool(fresh.has("rolls")).is_false()
	assert_float(CarryLead.ticks_of(fresh)).is_equal(UP)


## Unchanged (3): the shower's door pick-up and a collecting walker walk off
## before the park ends, so they move in it ("roll_moved") and never roll.
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
	_ticks(bag, 0, 16, 0.0)
	assert_bool(RollerPark._rolling(bag, 17.0 / UP)).is_true()
	bag["home_held"] = true
	_ticks(bag, 17, 17, 0.0)
	assert_float(bag["roll_tip"]).is_equal(17.0 / UP)
	assert_float(CarryLead.ticks_of(bag)).is_equal((17.0 / UP + RollerPark.TIP_UP) * UP)
