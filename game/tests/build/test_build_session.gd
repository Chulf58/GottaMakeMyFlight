class_name TestBuildSession
extends GdUnitTestSuite
## BuildSession on its own (decision build-mode-pauses-the-game-while-a-build-
## tray-is-open-closin): the clock is taken on sync(), given back as the player
## had it, left alone when the player changed it, and released if the session
## leaves the tree while building.

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


func test_starting_build_mode_pauses_on_the_next_sync_not_before() -> void:
	_session.set_building(true)
	assert_bool(_session.active).is_true()
	assert_bool(_clock.paused).is_false()
	_session.sync()
	assert_bool(_clock.paused).is_true()


func test_ending_gives_back_a_running_clock() -> void:
	_clock.set_speed(3)
	_session.set_building(true)
	_session.sync()
	_session.set_building(false)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_ending_before_the_first_sync_leaves_the_clock_alone() -> void:
	_session.set_building(true)
	_session.set_building(false)
	_session.sync()
	assert_bool(_clock.paused).is_false()


func test_ending_clears_the_undo_history_and_ctrl_z_is_then_a_no_op() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_session.set_building(false)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_object(_mode.undo()).is_null()
	assert_int(_mode.grid.floor_at(Vector2i(1, 1))).is_not_equal(BuildGrid.FLOOR_NONE)


func test_a_clock_the_player_changed_is_not_restored() -> void:
	_session.set_building(true)
	_session.sync()
	_clock.set_paused(false)
	_clock.set_speed(2)
	_session.set_building(false)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_leaving_the_tree_while_building_gives_the_clock_back() -> void:
	_session.set_building(true)
	_session.sync()
	assert_bool(_clock.paused).is_true()
	remove_child(_session)
	assert_bool(_clock.paused).is_false()
	_session.free()


func test_with_no_clock_it_still_reports_and_clears() -> void:
	_session.clock = null
	var seen: Array[bool] = []
	_session.changed.connect(seen.append)
	_session.set_building(true)
	_session.sync()
	_session.set_building(false)
	assert_array(seen).is_equal([true, false])
