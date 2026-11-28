class_name TestBuildSession
extends GdUnitTestSuite
## BuildSession on its own (decision
## build-mode-auto-pause-restored-while-offers-planner-stay-unpaused, 9e86b858):
## acquires a yielding ClockHolds hold while active so build mode pauses the
## clock and resumes on close, lets Space/speed keys unpause while staying
## active, keeps undo history across tray closes and ticks, and clears undo on
## abandon() (load).

var _clock: SimClock
var _mode: BuildMode
var _session: BuildSession


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	add_child(_clock)
	_mode = auto_free(BuildMode.new())
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_session = BuildSession.new()
	_session.build_mode = _mode
	_session.clock = _clock
	add_child(_session)


func after_test() -> void:
	if is_instance_valid(_session):
		_session.free()


func test_starting_build_mode_pauses_clock_and_ending_resumes_it() -> void:
	_clock.set_speed(3)
	_clock.set_paused(false)
	_session.set_building(true)
	assert_bool(_session.active).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_session.set_building(false)
	assert_bool(_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	assert_int(_clock.holds.count()).is_equal(0)


func test_starting_and_ending_build_mode_keeps_a_paused_clock_paused() -> void:
	_clock.set_speed(2)
	_clock.set_paused(true)
	_session.set_building(true)
	assert_bool(_session.active).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_session.set_building(false)
	assert_bool(_session.active).is_false()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)
	assert_int(_clock.holds.count()).is_equal(0)


func test_space_or_speed_key_unpauses_while_keeping_build_mode_active() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	_session.set_building(true)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_clock.set_paused(false)
	_session.sync()
	assert_bool(_session.active).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	_session.set_building(true)
	assert_bool(_clock.paused).is_false()
	_session.set_building(false)
	assert_bool(_session.active).is_false()
	assert_bool(_clock.paused).is_false()


func test_sync_acquires_hold_when_clock_is_wired_later() -> void:
	_session.clock = null
	_session.set_building(true)
	assert_bool(_session.active).is_true()
	assert_bool(_clock.paused).is_false()
	_session.clock = _clock
	_session.sync()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)


func test_ending_keeps_the_undo_history_across_close_and_ticks() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_session.set_building(false)
	assert_int(_mode.undo_history().size()).is_equal(1)
	for i in 5:
		_clock.advance(SimClock.STEP)
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(Vector2i(1, 1))).is_equal(BuildGrid.FLOOR_NONE)


func test_starting_again_keeps_the_history_across_ticks() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	_session.set_building(false)
	_clock.advance(SimClock.STEP)
	_session.set_building(true)
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_abandon_clears_the_history_at_once() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	_session.abandon()
	assert_bool(_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_object(_mode.undo()).is_null()


func test_leaving_the_tree_while_building_releases_hold_and_resumes_clock() -> void:
	_clock.set_paused(false)
	_session.set_building(true)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	remove_child(_session)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	_session.free()


func test_with_no_clock_it_still_reports_and_keeps_undo_until_abandon() -> void:
	_session.clock = null
	var seen: Array[bool] = []
	_session.changed.connect(seen.append)
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	_session.sync()
	_session.set_building(false)
	assert_array(seen).is_equal([true, false])
	assert_int(_mode.undo_history().size()).is_equal(1)
	_session.abandon()
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_ensure_paused_reacquires_hold_after_yield_without_needing_prior_sync() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	_session.set_building(true)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_clock.set_paused(false)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	# Even before sync() runs, ensure_paused() clears the dropped token and re-acquires.
	_session.ensure_paused()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_session.sync()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
