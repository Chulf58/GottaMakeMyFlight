class_name TestSimClockFastForward
extends GdUnitTestSuite
## The quiet-night fast-forward on SimClock (decision quiet-nights-fast-forward-
## automatically-when-nothing-is-due): a source asked once a frame names the
## tick a fast-forward may run to; until then the clock runs at
## FAST_FORWARD_SPEED, every tick, within MAX_STEPS_PER_FRAME, and stops on that
## exact tick. The speed setting is never touched and nothing of it is saved.

const FRAME := 1.0 / 60.0

var _asked := 0


func _new_clock() -> SimClock:
	return auto_free(SimClock.new()) as SimClock


func _frames(clock: SimClock, count: int) -> void:
	for i in count:
		clock.advance(FRAME)


## A ticked listener that pauses `clock` on tick `at`, as UnlockGuide does when
## a new tier opens at midnight.
func _pause_on(tick: int, clock: SimClock, at: int) -> void:
	if tick == at:
		clock.set_paused(true)


func _source_at(stop: int) -> Callable:
	return func() -> int:
		_asked += 1
		return stop


func test_without_a_source_the_clock_runs_at_the_player_speed() -> void:
	var clock := _new_clock()
	clock.set_speed(2)
	_frames(clock, 60)
	print("no source: ticks=%d" % clock.tick)
	assert_int(absi(clock.tick - 2 * SimClock.TICK_RATE)).is_less_equal(1)
	assert_bool(clock.is_fast_forwarding()).is_false()


func test_a_stop_ahead_runs_the_fast_forward_speed() -> void:
	var clock := _new_clock()
	clock.fast_forward_source = _source_at(1_000_000)
	_frames(clock, 60)
	var expected := SimClock.FAST_FORWARD_SPEED * SimClock.TICK_RATE
	print("fast: ticks=%d expected=%d" % [clock.tick, expected])
	assert_int(absi(clock.tick - expected)).is_less_equal(1)
	assert_bool(clock.is_fast_forwarding()).is_true()
	assert_int(clock.speed).is_equal(1)


func test_the_source_is_asked_once_a_frame_not_once_a_tick() -> void:
	var clock := _new_clock()
	_asked = 0
	clock.fast_forward_source = _source_at(1_000_000)
	_frames(clock, 10)
	print("asked=%d ticks=%d" % [_asked, clock.tick])
	assert_int(_asked).is_equal(10)
	assert_int(clock.tick).is_greater(10)


func test_steps_per_frame_stay_within_the_cap() -> void:
	var clock := _new_clock()
	clock.set_speed(3)
	clock.fast_forward_source = _source_at(1_000_000)
	var most := 0
	for d: float in [FRAME, FRAME, 0.5, FRAME, 0.1, 2.0, FRAME]:
		var before := clock.tick
		clock.advance(d)
		most = maxi(most, clock.tick - before)
	print("most steps in one frame=%d" % most)
	assert_int(most).is_equal(SimClock.MAX_STEPS_PER_FRAME)


## The 2 s frame at 30x owes 1190 more ticks; the cap drops them, so with the
## source gone a STEP-long frame at 2x runs exactly two ticks and leaves the
## leftover fraction where it was.
func test_a_long_fast_frame_drops_its_backlog() -> void:
	var clock := _new_clock()
	clock.set_speed(2)
	clock.fast_forward_source = _source_at(1_000_000)
	clock.advance(2.0 + SimClock.STEP * 0.4 / SimClock.FAST_FORWARD_SPEED)
	assert_int(clock.tick).is_equal(SimClock.MAX_STEPS_PER_FRAME)
	var alpha := clock.alpha
	assert_float(alpha).is_equal_approx(0.4, 0.001)
	clock.fast_forward_source = Callable()
	clock.advance(SimClock.STEP)
	print("after the long frame: ticks=%d alpha %f -> %f" % [clock.tick, alpha, clock.alpha])
	assert_int(clock.tick).is_equal(SimClock.MAX_STEPS_PER_FRAME + 2)
	assert_float(clock.alpha).is_equal_approx(alpha, 0.0001)


func test_a_listener_that_pauses_stops_a_fast_frame_on_its_tick() -> void:
	var clock := _new_clock()
	clock.fast_forward_source = _source_at(1_000_000)
	clock.ticked.connect(_pause_on.bind(clock, 4))
	clock.advance(FRAME)
	print("paused in a fast frame: tick=%d alpha=%f" % [clock.tick, clock.alpha])
	assert_int(clock.tick).is_equal(4)
	assert_bool(clock.paused).is_true()
	assert_float(clock.alpha).is_less(1.0)
	assert_bool(clock.is_fast_forwarding()).is_false()


## The same holds without a fast-forward, in any frame of more than one step.
func test_a_listener_that_pauses_stops_a_3x_frame_on_its_tick() -> void:
	var clock := _new_clock()
	clock.set_speed(3)
	clock.ticked.connect(_pause_on.bind(clock, 3))
	clock.advance(0.2)
	print("paused in a 3x frame: tick=%d alpha=%f" % [clock.tick, clock.alpha])
	assert_int(clock.tick).is_equal(3)
	assert_float(clock.alpha).is_less(1.0)
	# Control: the frame had steps to spare (12 owed, 10 allowed).
	clock.set_paused(false)
	clock.advance(0.2)
	assert_int(clock.tick).is_equal(3 + SimClock.MAX_STEPS_PER_FRAME)


## Reaching the stop with less than a step left still turns that leftover into
## player-speed time: 0.5 STEP of fast time is 0.5 / 30 STEP at 1x.
func test_the_leftover_at_the_stop_is_rescaled_at_once() -> void:
	var clock := _new_clock()
	clock.fast_forward_source = _source_at(1)
	clock.advance(SimClock.STEP * 1.5 / SimClock.FAST_FORWARD_SPEED)
	print("at the stop: tick=%d alpha=%f" % [clock.tick, clock.alpha])
	assert_int(clock.tick).is_equal(1)
	assert_float(clock.alpha).is_equal_approx(0.5 / SimClock.FAST_FORWARD_SPEED, 0.0001)
	clock.advance(SimClock.STEP * 0.9)
	assert_int(clock.tick).is_equal(1)
	clock.advance(SimClock.STEP * 0.1)
	assert_int(clock.tick).is_equal(2)


func test_the_fast_forward_stops_on_the_stop_tick() -> void:
	var clock := _new_clock()
	clock.fast_forward_source = _source_at(237)
	var frames := 0
	while clock.is_fast_forwarding() or clock.tick == 0:
		clock.advance(FRAME)
		frames += 1
		assert_int(clock.tick).is_less_equal(237)
	print("stopped at tick=%d after %d frames" % [clock.tick, frames])
	assert_int(clock.tick).is_equal(237)
	# Fast frames: at 1x it would take 237 / 20 * 60 = 711 frames.
	assert_int(frames).is_less(SimClock.TICK_RATE * 3)


func test_after_the_stop_the_clock_runs_at_the_player_speed_again() -> void:
	var clock := _new_clock()
	clock.set_speed(3)
	clock.fast_forward_source = _source_at(300)
	while clock.tick < 300:
		clock.advance(FRAME)
	var at_stop := clock.tick
	_frames(clock, 60)
	print("after the stop: %d ticks in a second" % (clock.tick - at_stop))
	assert_int(absi(clock.tick - at_stop - 3 * SimClock.TICK_RATE)).is_less_equal(1)
	assert_bool(clock.is_fast_forwarding()).is_false()
	assert_int(clock.speed).is_equal(3)


func test_a_stop_at_or_behind_the_tick_does_not_fast_forward() -> void:
	var clock := _new_clock()
	_frames(clock, 30)
	var start := clock.tick
	clock.fast_forward_source = _source_at(start)
	_frames(clock, 60)
	print("stop behind: ticks=%d start=%d" % [clock.tick, start])
	assert_int(absi(clock.tick - start - SimClock.TICK_RATE)).is_less_equal(1)
	assert_bool(clock.is_fast_forwarding()).is_false()
	clock.fast_forward_source = _source_at(-1)
	_frames(clock, 6)
	assert_bool(clock.is_fast_forwarding()).is_false()


func test_a_paused_clock_never_fast_forwards() -> void:
	var clock := _new_clock()
	clock.fast_forward_source = _source_at(1_000_000)
	_frames(clock, 3)
	assert_bool(clock.is_fast_forwarding()).is_true()
	clock.set_paused(true)
	var held := clock.tick
	_frames(clock, 60)
	assert_int(clock.tick).is_equal(held)
	assert_bool(clock.is_fast_forwarding()).is_false()
	clock.set_paused(false)
	_frames(clock, 1)
	print("resumed: ticks=%d held=%d" % [clock.tick, held])
	assert_int(clock.tick).is_greater(held)
	assert_bool(clock.is_fast_forwarding()).is_true()


func test_the_fast_forward_is_not_saved_and_a_load_ends_it() -> void:
	var clock := _new_clock()
	clock.set_speed(2)
	clock.fast_forward_source = _source_at(1_000_000)
	_frames(clock, 3)
	assert_bool(clock.is_fast_forwarding()).is_true()
	var snapshot := clock.to_snapshot()
	var keys: Array = snapshot.keys()
	keys.sort()
	var expected: Array = SimClock.SNAPSHOT_KEYS.duplicate()
	expected.sort()
	assert_array(keys).is_equal(expected)
	assert_int(snapshot["speed"]).is_equal(2)
	assert_bool(clock.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))).is_true()
	assert_int(clock.fast_forward_until).is_equal(-1)
	assert_bool(clock.is_fast_forwarding()).is_false()
	assert_int(clock.speed).is_equal(2)
