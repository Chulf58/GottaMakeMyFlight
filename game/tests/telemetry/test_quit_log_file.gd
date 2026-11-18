class_name TestQuitLogFile
extends GdUnitTestSuite
## The quit-log writer: one JSON line per record, the size cap with room kept
## for the notice and the session end, and the newest-sessions rule. Every file
## goes in a folder of this process under user://, removed afterwards.

var _dir := ""


func before_test() -> void:
	_dir = SaveTestKit.run_dir("quit_log_file")


func after_test() -> void:
	_wipe(_dir)


func _wipe(dir: String) -> void:
	var absolute := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	for name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)


func _lines(path: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	return text.strip_edges().split("\n", false)


func test_a_record_is_one_json_line() -> void:
	var file := QuitLogFile.new()
	assert_bool(file.open("%s/a.jsonl" % _dir)).is_true()
	assert_int(file.put({"type": "x", "n": 1})).is_equal(QuitLogFile.Put.WRITTEN)
	file.close()
	var lines := _lines(file.path)
	assert_int(lines.size()).is_equal(1)
	assert_int(int(JSON.parse_string(lines[0])["n"])).is_equal(1)


func test_the_file_caps_with_room_kept_for_a_notice_and_an_end() -> void:
	var file := QuitLogFile.new()
	file.max_bytes = 1200
	file.open("%s/cap.jsonl" % _dir)
	var written := 0
	var first_cap := -1
	for i in 100:
		var result := file.put({"i": i, "pad": "xxxxxxxxxxxxxxxxxxxx"})
		if result == QuitLogFile.Put.WRITTEN:
			written += 1
		elif result == QuitLogFile.Put.CAPPED_NOW:
			first_cap = i
	assert_bool(file.capped).is_true()
	assert_int(written).is_greater(0).is_less(100)
	assert_int(first_cap).is_equal(written)
	file.put_notice({"state": "capped"})
	file.put_notice({"state": "capped again"})
	file.put_tail({"type": "session_end"})
	file.close()
	var lines := _lines(file.path)
	assert_int(lines.size()).is_equal(written + 2)
	assert_str(lines[lines.size() - 2]).contains("capped")
	assert_str(lines[lines.size() - 1]).contains("session_end")
	assert_int(FileAccess.get_file_as_bytes(file.path).size()).is_less_equal(1200)


func test_nothing_is_written_while_no_file_is_open() -> void:
	var file := QuitLogFile.new()
	assert_int(file.put({"a": 1})).is_equal(QuitLogFile.Put.DROPPED)
	file.put_notice({"a": 1})
	file.put_tail({"a": 1})
	assert_bool(file.is_open()).is_false()


func test_the_newest_sessions_stay_and_other_files_are_left() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for name in ["a", "b", "c", "d"]:
		var file := FileAccess.open(
			"%s/%s.jsonl" % [ProjectSettings.globalize_path(_dir), name], FileAccess.WRITE
		)
		file.store_line("{}")
		file.close()
	var other := FileAccess.open(
		"%s/notes.txt" % ProjectSettings.globalize_path(_dir), FileAccess.WRITE
	)
	other.store_line("keep me")
	other.close()
	var gone := QuitLogFile.prune_sessions(_dir, 2)
	var left := DirAccess.get_files_at(ProjectSettings.globalize_path(_dir))
	assert_int(gone).is_equal(2)
	assert_array(Array(left)).contains_exactly_in_any_order(["c.jsonl", "d.jsonl", "notes.txt"])


func test_pruning_a_folder_that_is_not_there_removes_nothing() -> void:
	assert_int(QuitLogFile.prune_sessions("%s/missing" % _dir, 3)).is_equal(0)
