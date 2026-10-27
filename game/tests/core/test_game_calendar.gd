class_name TestGameCalendar
extends GdUnitTestSuite
## The calendar is a pure function of the sim tick: tick 0 is day 0 at 06:00.

const MIDNIGHT := 21600


func test_a_day_is_24_real_minutes_at_1x() -> void:
	assert_int(GameCalendar.TICKS_PER_MINUTE).is_equal(20)
	assert_int(GameCalendar.TICKS_PER_DAY).is_equal(28800)
	assert_int(GameCalendar.TICKS_PER_DAY / SimClock.TICK_RATE).is_equal(24 * 60)


func test_a_new_game_starts_on_day_zero_at_six() -> void:
	assert_int(GameCalendar.day_of(0)).is_equal(0)
	assert_int(GameCalendar.minute_of_day(0)).is_equal(360)
	assert_str(GameCalendar.clock_text(0)).is_equal("06:00")


func test_the_day_rolls_over_at_midnight_tick() -> void:
	assert_int(GameCalendar.day_of(MIDNIGHT - 1)).is_equal(0)
	assert_str(GameCalendar.clock_text(MIDNIGHT - 1)).is_equal("23:59")
	assert_int(GameCalendar.tick_of_day(MIDNIGHT - 1)).is_equal(GameCalendar.TICKS_PER_DAY - 1)
	assert_int(GameCalendar.day_of(MIDNIGHT)).is_equal(1)
	assert_str(GameCalendar.clock_text(MIDNIGHT)).is_equal("00:00")
	assert_int(GameCalendar.tick_of_day(MIDNIGHT)).is_equal(0)
	assert_int(GameCalendar.day_of(MIDNIGHT + 1)).is_equal(1)
	assert_int(GameCalendar.day_of(MIDNIGHT + GameCalendar.TICKS_PER_DAY)).is_equal(2)


func test_clock_text_pads_hours_and_minutes() -> void:
	# 07:05 is 65 game minutes after the start.
	assert_str(GameCalendar.clock_text(65 * GameCalendar.TICKS_PER_MINUTE)).is_equal("07:05")
	assert_str(GameCalendar.clock_text(65 * GameCalendar.TICKS_PER_MINUTE + 19)).is_equal("07:05")


func test_tick_at_is_the_inverse_of_day_and_minute() -> void:
	assert_int(GameCalendar.tick_at(0, 360)).is_equal(0)
	assert_int(GameCalendar.tick_at(0, 0)).is_equal(-7200)
	assert_int(GameCalendar.tick_at(1, 0)).is_equal(MIDNIGHT)
	assert_int(GameCalendar.day_start(2)).is_equal(MIDNIGHT + GameCalendar.TICKS_PER_DAY)
	for day in [0, 1, 3, 40]:
		for minute in [0, 359, 360, 1439]:
			var tick := GameCalendar.tick_at(day, minute)
			assert_int(GameCalendar.day_of(tick)).is_equal(day)
			assert_int(GameCalendar.minute_of_day(tick)).is_equal(minute)


func test_ticks_before_the_start_floor_into_earlier_days() -> void:
	assert_int(GameCalendar.day_of(-7200)).is_equal(0)
	assert_int(GameCalendar.day_of(-7201)).is_equal(-1)
	assert_int(GameCalendar.tick_of_day(-7201)).is_equal(GameCalendar.TICKS_PER_DAY - 1)
	assert_str(GameCalendar.clock_text(-1)).is_equal("05:59")


func test_reads_the_time_from_a_running_sim_clock() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	while clock.tick < GameCalendar.TICKS_PER_MINUTE:
		clock.advance(SimClock.STEP)
	assert_str(GameCalendar.clock_text(clock.tick)).is_equal("06:01")
