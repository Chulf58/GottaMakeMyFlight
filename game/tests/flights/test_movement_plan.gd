class_name TestMovementPlan
extends GdUnitTestSuite
## MovementPlan: the route geometry the ground phases move on, and the taxi
## plan with its one optional pause at a hold line (decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses, point 4).
## test_movement_plan_golden.gd pins that a plan with no pause is the old
## motion.

const L_PATH: Array[Vector3] = [Vector3(0, 0, 0), Vector3(40, 0, 0), Vector3(40, 0, 30)]
## A 300 m straight, held 100 m along for 20 ticks in a 920 tick budget: the
## 900 moving ticks split 300 and 600, so every leg end lands on a half tick.
const STRAIGHT: Array[Vector3] = [Vector3(0, 0, 0), Vector3(300, 0, 0)]
const BUDGET := 920.0
const HOLD := {"hold_s": 100.0, "ticks": 20}


func _path() -> PackedVector3Array:
	return PackedVector3Array(L_PATH)


func _straight(length := 300.0) -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3(length, 0, 0)])


func test_path_length_and_point_at() -> void:
	var path := _path()
	assert_float(MovementPlan.path_length(path)).is_equal_approx(70.0, 0.001)
	assert_that(MovementPlan.point_at(path, 0.0)).is_equal(Vector3.ZERO)
	assert_that(MovementPlan.point_at(path, 20.0)).is_equal(Vector3(20, 0, 0))
	assert_that(MovementPlan.point_at(path, 55.0)).is_equal(Vector3(40, 0, 15))
	assert_that(MovementPlan.point_at(path, 999.0)).is_equal(Vector3(40, 0, 30))
	assert_that(MovementPlan.point_at(path, -5.0)).is_equal(Vector3.ZERO)


func test_heading_follows_segments_and_blends_around_the_corner() -> void:
	var path := _path()
	var entry := Vector3.RIGHT
	assert_float(MovementPlan.heading_at(path, 10.0, entry).dot(Vector3.RIGHT)).is_equal_approx(
		1.0, 0.001
	)
	assert_float(MovementPlan.heading_at(path, 60.0, entry).dot(Vector3.BACK)).is_equal_approx(
		1.0, 0.001
	)
	var at_corner := MovementPlan.heading_at(path, 40.0, entry)
	assert_float(at_corner.dot(Vector3.RIGHT)).is_between(0.6, 0.8)
	assert_float(at_corner.dot(Vector3.BACK)).is_between(0.6, 0.8)


func test_heading_starts_on_the_entry_direction() -> void:
	var start := MovementPlan.heading_at(_path(), 0.0, Vector3.BACK)
	assert_float(start.dot(Vector3.BACK)).is_equal_approx(1.0, 0.001)


func test_exit_dir_is_the_last_segment() -> void:
	assert_that(MovementPlan.exit_dir(_path())).is_equal(Vector3.BACK)


## The plane stands still at hold_s for exactly the pause: every half tick
## from T1 (300) to T1 + p (320) is at the hold, and the half ticks either side
## are not.
func test_a_pause_stands_at_the_hold_for_exactly_its_ticks() -> void:
	var plan := MovementPlan.taxi(PackedVector3Array(STRAIGHT), BUDGET, HOLD)
	var held: Array[float] = []
	for k in range(int(2.0 * BUDGET) + 1):
		var distance := MovementPlan.distance_at(plan, k * 0.5)
		if absf(distance - HOLD["hold_s"]) < 1e-9:
			held.append(k * 0.5)
	var before := MovementPlan.distance_at(plan, 299.5)
	var after := MovementPlan.distance_at(plan, 320.5)
	print(
		(
			"held %d half ticks from %.1f to %.1f; at 299.5 %.6f m, at 320.5 %.6f m"
			% [held.size(), held[0], held[held.size() - 1], before, after]
		)
	)
	assert_int(held.size()).is_equal(2 * HOLD["ticks"] + 1)
	assert_float(held[0]).is_equal(300.0)
	assert_float(held[held.size() - 1]).is_equal(320.0)
	assert_float(before).is_less(HOLD["hold_s"])
	assert_float(after).is_greater(HOLD["hold_s"])
	assert_vector(MovementPlan.position_at(plan, 310.0)).is_equal_approx(
		Vector3(100, 0, 0), Vector3(1e-4, 1e-4, 1e-4)
	)


## Each leg is a smoothstep: the plane arrives at the hold and leaves it (and
## starts and ends the phase) barely moving, against a peak half-tick step.
func test_each_leg_starts_and_ends_at_zero_speed() -> void:
	var plan := MovementPlan.taxi(PackedVector3Array(STRAIGHT), BUDGET, HOLD)
	var step := func(e: float) -> float:
		return MovementPlan.distance_at(plan, e + 0.5) - MovementPlan.distance_at(plan, e)
	var ends: Array[float] = [step.call(0.0), step.call(299.5), step.call(320.0), step.call(919.5)]
	var middle: float = step.call(150.0)
	print("half-tick steps at the leg ends %s, mid leg 1 %.4f m" % [ends, middle])
	assert_float(middle).is_greater(0.2)
	for end in ends:
		assert_float(end).is_greater(0.0).is_less(0.01 * middle)
	assert_float(MovementPlan.distance_at(plan, BUDGET)).is_equal(300.0)


func test_the_legs_and_the_pause_fill_the_budget_in_proportion() -> void:
	var path := _path()
	for case: Array in [[920.0, 13.7, 20], [1000.0, 61.0, 160], [600.0, 35.0, 0], [721.0, 1.0, 80]]:
		var plan := MovementPlan.taxi(path, case[0], {"hold_s": case[1], "ticks": case[2]})
		var t1: float = plan["t1"]
		var t2: float = plan["t2"]
		print("B %.1f hold %.1f p %d: T1 %.4f T2 %.4f" % [case[0], case[1], case[2], t1, t2])
		assert_float(t1 + case[2] + t2).is_equal_approx(case[0], 1e-9)
		assert_float(t1).is_greater(0.0)
		assert_float(t2).is_greater(0.0)
		assert_float(t1 / t2).is_equal_approx(case[1] / (70.0 - case[1]), 1e-9)
	var none := MovementPlan.taxi(path, 600.0)
	assert_float(none["t1"] + none["pause_ticks"] + none["t2"]).is_equal(600.0)


## The peak the plan reports is the fastest half-tick step it really takes.
func test_peak_speed_is_one_and_a_half_times_the_mean_speed() -> void:
	var plan := MovementPlan.taxi(PackedVector3Array(STRAIGHT), BUDGET, HOLD)
	var fastest := 0.0
	for k in range(int(2.0 * BUDGET)):
		var e := k * 0.5
		var step := MovementPlan.distance_at(plan, e + 0.5) - MovementPlan.distance_at(plan, e)
		fastest = maxf(fastest, step / 0.5)
	print("peak %.5f m/tick, fastest sampled %.5f" % [MovementPlan.peak_speed(plan), fastest])
	assert_float(MovementPlan.peak_speed(plan)).is_equal_approx(1.5 * 300.0 / 900.0, 1e-9)
	assert_float(fastest).is_equal_approx(MovementPlan.peak_speed(plan), 1e-4)


func test_the_peak_speed_check_refuses_a_plan_over_0_8_m_per_tick() -> void:
	var over := MovementPlan.taxi(_straight(500.0), BUDGET)
	var under := MovementPlan.taxi(_straight(490.0), BUDGET)
	var paused_over := MovementPlan.taxi(_straight(450.0), BUDGET, {"hold_s": 200.0, "ticks": 160})
	var paused_under := MovementPlan.taxi(_straight(400.0), BUDGET, {"hold_s": 200.0, "ticks": 160})
	print(
		(
			"peaks: 500 m %.4f, 490 m %.4f, 450 m paused %.4f, 400 m paused %.4f"
			% [
				MovementPlan.peak_speed(over),
				MovementPlan.peak_speed(under),
				MovementPlan.peak_speed(paused_over),
				MovementPlan.peak_speed(paused_under),
			]
		)
	)
	assert_float(MovementPlan.peak_speed(over)).is_greater(MovementPlan.MAX_PEAK_SPEED)
	assert_bool(MovementPlan.is_valid(over)).is_false()
	assert_bool(MovementPlan.is_valid(under)).is_true()
	assert_float(MovementPlan.peak_speed(paused_over)).is_greater(MovementPlan.MAX_PEAK_SPEED)
	assert_bool(MovementPlan.is_valid(paused_over)).is_false()
	assert_bool(MovementPlan.is_valid(paused_under)).is_true()


func test_a_pause_is_a_multiple_of_20_ticks_up_to_160_held_on_the_route() -> void:
	var path := PackedVector3Array(STRAIGHT)
	for ticks in [20, 80, 160]:
		var plan := MovementPlan.taxi(path, BUDGET, {"hold_s": 100.0, "ticks": ticks})
		assert_bool(MovementPlan.is_valid(plan)).is_true()
	for ticks in [-20, 30, 180]:
		var plan := MovementPlan.taxi(path, BUDGET, {"hold_s": 100.0, "ticks": ticks})
		(
			assert_bool(MovementPlan.is_valid(plan))
			. override_failure_message("pause %d accepted" % ticks)
			. is_false()
		)
	for hold_s in [-1.0, 301.0]:
		var plan := MovementPlan.taxi(path, BUDGET, {"hold_s": hold_s, "ticks": 20})
		assert_bool(MovementPlan.is_valid(plan)).is_false()


## Segments with no length are skipped: a repeated point mid-route changes
## nothing, and a route ending on a repeated point exits along its last real
## segment (+X here, not the stationary fallback +Z).
func test_repeated_points_are_skipped() -> void:
	var ends_twice := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0, 0, 30), Vector3(40, 0, 30), Vector3(40, 0, 30)]
	)
	var middle_twice := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(20, 0, 0), Vector3(20, 0, 0), Vector3(40, 0, 0)]
	)
	print("exit of a route ending twice: %s" % MovementPlan.exit_dir(ends_twice))
	assert_float(MovementPlan.exit_dir(ends_twice).dot(Vector3.RIGHT)).is_equal_approx(1.0, 1e-6)
	assert_float(MovementPlan.path_length(middle_twice)).is_equal_approx(40.0, 1e-6)
	for at in [10.0, 20.0, 30.0]:
		var heading := MovementPlan.heading_at(middle_twice, at, Vector3.RIGHT)
		assert_float(heading.dot(Vector3.RIGHT)).is_equal_approx(1.0, 1e-6)
		assert_float(MovementPlan.point_at(middle_twice, at).x).is_equal_approx(at, 1e-5)


## A stationary route (one point, or the same point twice) keeps the entry
## heading, is no valid taxi, and has no exit direction, which is reported.
func test_a_stationary_route_keeps_its_entry_heading_and_is_not_a_taxi() -> void:
	var entry := Vector3(0, 1, -2)
	var routes := [
		PackedVector3Array([Vector3(5, 0, 5), Vector3(5, 0, 5)]),
		PackedVector3Array([Vector3(5, 0, 5)]),
	]
	for route: PackedVector3Array in routes:
		var heading := MovementPlan.heading_at(route, 0.0, entry)
		var plan := MovementPlan.taxi(route, 600.0)
		print("stationary %s: heading %s" % [route, heading])
		assert_float(heading.dot(Vector3.FORWARD)).is_equal_approx(1.0, 1e-6)
		assert_that(MovementPlan.position_at(plan, 300.0)).is_equal(Vector3(5, 0, 5))
		assert_bool(MovementPlan.is_valid(plan)).is_false()
		await (
			assert_error(func() -> void: MovementPlan.exit_dir(route))
			. is_push_error("MovementPlan: exit_dir of a stationary route")
		)
	var moving := MovementPlan.taxi(PackedVector3Array(STRAIGHT), 600.0)
	assert_bool(MovementPlan.is_valid(moving)).is_true()
