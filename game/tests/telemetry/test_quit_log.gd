class_name TestQuitLog
extends GdUnitTestSuite
## The quit log session and its setting: off writes nothing, an open session
## writes records and ends with session_end, a capped file still ends, old
## sessions are pruned, and the switch is saved in the file it is given (never
## the player's own). Every file is under a folder of this process.

var _dir := ""
var _settings := ""


func before_test() -> void:
	_dir = SaveTestKit.run_dir("quit_log")
	_settings = SaveTestKit.run_path("quit_log_settings").replace(".json", ".cfg")
	QuitLog.current = null


func after_test() -> void:
	QuitLog.current = null
	var absolute := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	for name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings))


func _records(path: String) -> Array:
	var out := []
	for line in FileAccess.get_file_as_string(path).strip_edges().split("\n", false):
		out.append(JSON.parse_string(line))
	return out


func test_with_no_session_a_note_writes_nothing() -> void:
	QuitLog.note("day_end", {"day": 1})
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir))).is_false()


func test_a_session_writes_records_in_order_and_ends() -> void:
	var session := QuitLog.new()
	assert_bool(session.open(_dir, "s1")).is_true()
	assert_object(QuitLog.current).is_same(session)
	session.tick = 42
	QuitLog.note("day_start", {"day": 3})
	QuitLog.note("alert_shown", {"kind": "gate_full"})
	session.end("window_close")
	assert_object(QuitLog.current).is_null()
	var records := _records(session.path)
	assert_int(records.size()).is_equal(3)
	(
		assert_array(records.map(func(r: Dictionary) -> String: return r["type"]))
		. is_equal(["day_start", "alert_shown", "session_end"])
	)
	assert_array(records.map(func(r: Dictionary) -> int: return int(r["i"]))).is_equal([0, 1, 2])
	assert_int(int(records[0]["tick"])).is_equal(42)
	assert_int(int(records[0]["data"]["day"])).is_equal(3)
	assert_str(records[2]["data"]["reason"]).is_equal("window_close")


func test_a_note_after_the_end_writes_nothing() -> void:
	var session := QuitLog.new()
	session.open(_dir, "s1")
	session.end("quit_menu")
	QuitLog.note("day_end", {})
	assert_int(_records(session.path).size()).is_equal(1)


func test_a_capped_file_still_ends_with_its_notice_and_session_end() -> void:
	var session := QuitLog.new()
	session.max_bytes = 1500
	session.open(_dir, "capped")
	for i in 200:
		QuitLog.note("build_edit", {"kind": "PLACE_OBJECT", "n": i})
	session.end("window_close")
	var records := _records(session.path)
	var types := records.map(func(r: Dictionary) -> String: return r["type"])
	assert_str(types[types.size() - 2]).is_equal("log_capped")
	assert_str(types[types.size() - 1]).is_equal("session_end")
	assert_int(types.count("build_edit")).is_less(200)
	assert_int(FileAccess.get_file_as_bytes(session.path).size()).is_less_equal(1500)


func test_opening_keeps_the_newest_sessions_only() -> void:
	for i in QuitLog.KEEP_SESSIONS + 3:
		var old := QuitLog.new()
		old.open(_dir, "old%02d" % i)
		old.end("window_close")
	var absolute := ProjectSettings.globalize_path(_dir)
	assert_int(DirAccess.get_files_at(absolute).size()).is_less_equal(QuitLog.KEEP_SESSIONS)


func test_the_switch_is_off_until_it_is_saved() -> void:
	assert_bool(QuitLog.is_enabled(_settings)).is_false()
	QuitLog.save_enabled(true, _settings)
	assert_bool(QuitLog.is_enabled(_settings)).is_true()
	QuitLog.save_enabled(false, _settings)
	assert_bool(QuitLog.is_enabled(_settings)).is_false()


func test_the_player_settings_file_is_never_read_or_written_by_a_script_run() -> void:
	var before := FileAccess.file_exists(QuitLog.SETTINGS_PATH)
	QuitLog.save_enabled(true)
	assert_bool(QuitLog.is_enabled()).is_false()
	assert_bool(FileAccess.file_exists(QuitLog.SETTINGS_PATH)).is_equal(before)


func test_the_folder_is_an_absolute_path_for_the_open_button() -> void:
	assert_bool(QuitLog.folder().is_absolute_path()).is_true()
	assert_str(QuitLog.folder()).ends_with("telemetry")


func test_session_names_are_safe_in_a_file_name_and_carry_the_process_id() -> void:
	var name := QuitLog.new_session_name()
	assert_str(name).contains("-%d" % OS.get_process_id())
	assert_bool(name.contains(":") or name.contains(" ")).is_false()


func test_two_sessions_with_one_name_both_survive_with_their_ends() -> void:
	var first := QuitLog.new()
	first.open(_dir, "same")
	QuitLog.note("day_start", {"day": 1})
	first.end("switched_off")
	var second := QuitLog.new()
	second.open(_dir, "same")
	QuitLog.note("day_start", {"day": 2})
	second.end("window_close")
	assert_str(first.path).is_not_equal(second.path)
	assert_str(first.path.get_file()).starts_with(QuitLogFile.PREFIX)
	var a := _records(first.path)
	var b := _records(second.path)
	assert_int(int(a[0]["data"]["day"])).is_equal(1)
	assert_str(a.back()["data"]["reason"]).is_equal("switched_off")
	assert_int(int(b[0]["data"]["day"])).is_equal(2)
	assert_str(b.back()["data"]["reason"]).is_equal("window_close")


func test_opening_leaves_an_unrelated_jsonl_in_the_folder_alone() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var own := FileAccess.open(
		"%s/testers_notes.jsonl" % ProjectSettings.globalize_path(_dir), FileAccess.WRITE
	)
	own.store_line("{}")
	own.close()
	for i in QuitLog.KEEP_SESSIONS + 2:
		var old := QuitLog.new()
		old.open(_dir, "n%02d" % i)
		old.end("window_close")
	(
		assert_bool(
			FileAccess.file_exists("%s/testers_notes.jsonl" % ProjectSettings.globalize_path(_dir))
		)
		. is_true()
	)
