class_name TestQuitLogRecorder
extends GdUnitTestSuite
## The recorder apart from the main scene: off it writes no file, on it logs
## session_start, the day edges with money, speed and pause changes, and ends
## with the reason the game closed. The switch and the log folder are files of
## this process, never the player's.

var _dir := ""
var _settings := ""
var _clock: SimClock
var _finances: Finances
var _recorder: QuitLogRecorder


func before_test() -> void:
	_dir = SaveTestKit.run_dir("quit_log_recorder")
	_settings = SaveTestKit.run_path("quit_log_recorder_settings").replace(".json", ".cfg")
	QuitLog.current = null
	_clock = auto_free(SimClock.new())
	_clock.seed_rng(777)
	add_child(_clock)
	_finances = auto_free(Finances.new())
	_finances.clock = _clock
	add_child(_finances)
	_recorder = auto_free(QuitLogRecorder.new())
	_recorder.clock = _clock
	_recorder.finances = _finances
	_recorder.settings_path = _settings
	_recorder.log_dir = _dir


func after_test() -> void:
	# Close the session before its file is removed: an open file cannot go.
	_recorder.stop("test_end")
	QuitLog.current = null
	var absolute := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	for name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings))


func _records() -> Array:
	var out := []
	var absolute := ProjectSettings.globalize_path(_dir)
	for name in DirAccess.get_files_at(absolute):
		var text := FileAccess.get_file_as_string("%s/%s" % [absolute, name])
		for line in text.strip_edges().split("\n", false):
			out.append(JSON.parse_string(line))
	return out


func _types() -> Array:
	return _records().map(func(r: Dictionary) -> String: return r["type"])


func test_with_the_switch_off_no_folder_and_no_file_are_made() -> void:
	add_child(_recorder)
	_clock.ticked.emit(GameCalendar.tick_at(1, 0))
	_recorder.stop(QuitLogRecorder.REASON_WINDOW_CLOSE)
	assert_bool(_recorder.is_recording()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir))).is_false()
	assert_bool(_clock.ticked.is_connected(_recorder._on_ticked)).is_false()


func test_with_the_switch_on_the_session_starts_with_the_seed() -> void:
	QuitLog.save_enabled(true, _settings)
	add_child(_recorder)
	assert_bool(_recorder.is_recording()).is_true()
	var first: Dictionary = _records()[0]
	assert_str(first["type"]).is_equal("session_start")
	assert_str(first["data"]["seed"]).is_equal("777")
	assert_str(first["data"]["version"]).is_equal("0.1.0")


func test_a_day_end_and_the_next_day_start_carry_day_and_money() -> void:
	_recorder.set_enabled(true)
	add_child(_recorder)
	_finances.wallet.balance = 12345
	_clock.ticked.emit(GameCalendar.day_start(3) - 1)
	_clock.ticked.emit(GameCalendar.day_start(3))
	var edges: Array = _records().filter(
		func(r: Dictionary) -> bool: return r["type"] in ["day_end", "day_start"]
	)
	assert_int(edges.size()).is_equal(2)
	assert_str(edges[0]["type"]).is_equal("day_end")
	assert_int(int(edges[0]["data"]["day"])).is_equal(2)
	assert_int(int(edges[0]["data"]["money"])).is_equal(12345)
	assert_str(edges[1]["type"]).is_equal("day_start")
	assert_int(int(edges[1]["data"]["day"])).is_equal(3)


func test_speed_and_pause_changes_are_logged_once_each() -> void:
	_recorder.set_enabled(true)
	add_child(_recorder)
	_recorder._process(0.0)
	_clock.set_speed(3)
	_recorder._process(0.0)
	_recorder._process(0.0)
	_clock.set_paused(true)
	_recorder._process(0.0)
	var types := _types()
	assert_int(types.count("speed_changed")).is_equal(1)
	assert_int(types.count("pause_changed")).is_equal(1)


func test_the_window_closing_ends_the_session_with_that_reason() -> void:
	_recorder.set_enabled(true)
	add_child(_recorder)
	_recorder.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var last: Dictionary = _records().back()
	assert_str(last["type"]).is_equal("session_end")
	assert_str(last["data"]["reason"]).is_equal(QuitLogRecorder.REASON_WINDOW_CLOSE)
	assert_bool(_recorder.is_recording()).is_false()


func test_leaving_the_tree_ends_the_session() -> void:
	_recorder.set_enabled(true)
	add_child(_recorder)
	remove_child(_recorder)
	var last: Dictionary = _records().back()
	assert_str(last["data"]["reason"]).is_equal(QuitLogRecorder.REASON_LEFT_GAME)


func test_switching_off_in_play_ends_the_session_and_stops_writing() -> void:
	_recorder.set_enabled(true)
	add_child(_recorder)
	_recorder.set_enabled(false)
	var count := _records().size()
	_clock.ticked.emit(GameCalendar.day_start(5))
	assert_int(_records().size()).is_equal(count)
	assert_str(_records().back()["data"]["reason"]).is_equal(QuitLogRecorder.REASON_SWITCHED_OFF)
	assert_bool(QuitLog.is_enabled(_settings)).is_false()


func test_a_log_that_cannot_open_leaves_the_switch_as_it_was() -> void:
	var blocker := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(blocker.get_base_dir())
	FileAccess.open(blocker, FileAccess.WRITE).close()
	assert_bool(_recorder.set_enabled(true)).is_false()
	assert_bool(_recorder.is_recording()).is_false()
	assert_bool(QuitLog.is_enabled(_settings)).is_false()
	assert_object(QuitLog.current).is_null()
	DirAccess.remove_absolute(blocker)


func test_a_build_edit_logs_its_kind_only() -> void:
	var edit := BuildEdit.new()
	edit.kind = BuildEdit.Kind.PAINT_FLOOR
	edit.cell = Vector2i(4, 5)
	assert_dict(QuitLogRecorder.edit_data(edit)).is_equal({"kind": "paint_floor"})
