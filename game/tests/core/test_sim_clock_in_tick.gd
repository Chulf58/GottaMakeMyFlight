class_name TestSimClockInTick
extends GdUnitTestSuite
## SimClock.is_in_tick() is true only while `ticked` is being emitted, so the
## whole-world save can refuse to run from inside a tick.

var _seen: Array[bool] = []


func test_is_in_tick_only_while_ticked_is_emitted() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.ticked.connect(func(_tick: int) -> void: _seen.append(clock.is_in_tick()))
	assert_bool(clock.is_in_tick()).is_false()
	clock.advance(SimClock.STEP * 3.0)
	assert_array(_seen).is_equal([true, true, true])
	assert_bool(clock.is_in_tick()).is_false()
