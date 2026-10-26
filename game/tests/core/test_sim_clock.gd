class_name TestSimClock
extends GdUnitTestSuite

const FRAME := 1.0 / 60.0

var _seen_ticks: Array[int] = []


func _new_clock() -> SimClock:
	return auto_free(SimClock.new()) as SimClock


func _run_for(clock: SimClock, seconds: float) -> void:
	var frames := int(round(seconds / FRAME))
	for i in frames:
		clock.advance(FRAME)


func _on_ticked(tick: int) -> void:
	_seen_ticks.append(tick)


func test_starts_at_tick_zero_unpaused_at_1x() -> void:
	var clock := _new_clock()
	assert_int(clock.tick).is_equal(0)
	assert_bool(clock.paused).is_false()
	assert_int(clock.speed).is_equal(1)


func test_ticks_match_elapsed_times_speed_times_rate() -> void:
	for speed in SimClock.SPEEDS:
		var clock := _new_clock()
		clock.set_speed(speed)
		_run_for(clock, 10.0)
		var expected := int(floor(10.0 * speed * SimClock.TICK_RATE))
		assert_int(absi(clock.tick - expected)).is_less_equal(1)


func test_odd_frame_deltas_still_match() -> void:
	var clock := _new_clock()
	clock.set_speed(2)
	var elapsed := 0.0
	var deltas := [0.007, 0.031, 0.016, 0.0449, 0.002]
	for i in 400:
		var d: float = deltas[i % deltas.size()]
		elapsed += d
		clock.advance(d)
	var expected := int(floor(elapsed * 2.0 * SimClock.TICK_RATE))
	assert_int(absi(clock.tick - expected)).is_less_equal(1)


func test_pause_yields_no_ticks() -> void:
	var clock := _new_clock()
	clock.set_paused(true)
	_run_for(clock, 5.0)
	assert_int(clock.tick).is_equal(0)


func test_resume_after_pause_does_not_replay_paused_time() -> void:
	var clock := _new_clock()
	_run_for(clock, 1.0)
	var before := clock.tick
	clock.set_paused(true)
	_run_for(clock, 5.0)
	clock.set_paused(false)
	assert_int(clock.tick).is_equal(before)
	clock.advance(FRAME)
	assert_int(clock.tick - before).is_less_equal(1)


func test_cap_limits_steps_on_a_huge_delta() -> void:
	var clock := _new_clock()
	clock.set_speed(3)
	clock.advance(60.0)
	assert_int(clock.tick).is_equal(SimClock.MAX_STEPS_PER_FRAME)


func test_cap_discards_backlog_so_the_next_frame_is_normal() -> void:
	var clock := _new_clock()
	clock.advance(60.0)
	var after_spike := clock.tick
	clock.advance(FRAME)
	assert_int(clock.tick - after_spike).is_less_equal(1)


func test_alpha_stays_in_unit_range() -> void:
	var clock := _new_clock()
	var deltas := [0.007, 0.031, 0.016, 0.0449, 0.05, 0.1, 60.0]
	for speed in SimClock.SPEEDS:
		clock.set_speed(speed)
		for d: float in deltas:
			clock.advance(d)
			assert_float(clock.alpha).is_greater_equal(0.0)
			assert_float(clock.alpha).is_less(1.0)


func test_alpha_is_leftover_fraction_of_a_step() -> void:
	var clock := _new_clock()
	clock.advance(SimClock.STEP * 1.5)
	assert_int(clock.tick).is_equal(1)
	assert_float(clock.alpha).is_equal_approx(0.5, 0.001)


func test_ticked_signal_fires_once_per_tick_in_order() -> void:
	_seen_ticks.clear()
	var clock := _new_clock()
	clock.ticked.connect(_on_ticked)
	clock.advance(SimClock.STEP * 3.5)
	assert_array(_seen_ticks).is_equal([1, 2, 3])


func test_speed_rejects_unknown_values() -> void:
	var clock := _new_clock()
	clock.set_speed(2)
	assert_bool(clock.set_speed(7)).is_false()
	assert_int(clock.speed).is_equal(2)


func test_rng_state_round_trips() -> void:
	var clock := _new_clock()
	clock.seed_rng(12345)
	for i in 10:
		clock.rng.randi()
	var saved_seed := clock.rng.seed
	var saved_state := clock.rng.state
	var first: Array[int] = []
	for i in 20:
		first.append(clock.rng.randi())

	var other := _new_clock()
	other.restore_rng(saved_seed, saved_state)
	var second: Array[int] = []
	for i in 20:
		second.append(other.rng.randi())
	assert_array(second).is_equal(first)


func test_same_seed_gives_same_sequence() -> void:
	var a := _new_clock()
	var b := _new_clock()
	a.seed_rng(99)
	b.seed_rng(99)
	assert_int(a.rng.randi()).is_equal(b.rng.randi())


func test_snapshot_survives_json_with_rng_values_above_2_pow_53() -> void:
	var clock := _new_clock()
	# 2^53 + 1 is the first integer a double cannot hold.
	var big_seed := 9007199254740993
	clock.restore_rng(big_seed, 9223372036854775807)
	clock.set_speed(3)
	clock.advance(SimClock.STEP * 4.25)
	var snapshot := clock.to_snapshot()
	assert_str(snapshot["rng_seed"]).is_equal("9007199254740993")

	var text := JSON.stringify(snapshot)
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()

	var expected: Array[int] = []
	for i in 20:
		expected.append(clock.rng.randi())

	var other := _new_clock()
	assert_bool(other.from_snapshot(parsed)).is_true()
	assert_int(other.tick).is_equal(clock.tick)
	assert_int(other.speed).is_equal(3)
	assert_bool(other.paused).is_false()
	assert_float(other.alpha).is_equal_approx(clock.alpha, 0.0001)
	assert_int(other.rng.seed).is_equal(big_seed)
	var actual: Array[int] = []
	for i in 20:
		actual.append(other.rng.randi())
	assert_array(actual).is_equal(expected)


func test_malformed_snapshot_returns_false_and_leaves_clock_unchanged() -> void:
	var clock := _new_clock()
	clock.seed_rng(7)
	clock.advance(SimClock.STEP * 2.5)
	var good := clock.to_snapshot()
	var before_tick := clock.tick
	var before_alpha := clock.alpha
	var before_state := clock.rng.state
	var before_seed := clock.rng.seed

	var bad_cases: Array[Dictionary] = []
	for key: String in good:
		var missing := good.duplicate()
		missing.erase(key)
		bad_cases.append(missing)
	var wrong_speed := good.duplicate()
	wrong_speed["speed"] = 9
	bad_cases.append(wrong_speed)
	var wrong_paused := good.duplicate()
	wrong_paused["paused"] = "no"
	bad_cases.append(wrong_paused)
	var negative_tick := good.duplicate()
	negative_tick["tick"] = -1
	bad_cases.append(negative_tick)
	var fractional_tick := good.duplicate()
	fractional_tick["tick"] = 1.5
	bad_cases.append(fractional_tick)
	var big_accumulator := good.duplicate()
	big_accumulator["accumulator"] = 5.0
	bad_cases.append(big_accumulator)
	var numeric_seed := good.duplicate()
	numeric_seed["rng_seed"] = 12345
	bad_cases.append(numeric_seed)
	var junk_state := good.duplicate()
	junk_state["rng_state"] = "abc"
	bad_cases.append(junk_state)

	var other := _new_clock()
	other.seed_rng(7)
	other.advance(SimClock.STEP * 2.5)
	for bad in bad_cases:
		assert_bool(other.from_snapshot(bad)).is_false()
		assert_int(other.tick).is_equal(before_tick)
		assert_float(other.alpha).is_equal(before_alpha)
		assert_int(other.rng.seed).is_equal(before_seed)
		assert_int(other.rng.state).is_equal(before_state)
