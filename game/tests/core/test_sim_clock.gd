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
