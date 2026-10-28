class_name TestPlaytestCaps
extends GdUnitTestSuite
## The limits on what a playtest leaves on disk: a size cap per file, after
## which recording stops with one notice, and only the newest sessions kept.

var _dir := SaveTestKit.run_dir("playtest_caps_test")


func after_test() -> void:
	for name in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, name])
	DirAccess.remove_absolute(_dir)


func test_a_file_stops_at_its_cap_and_says_so_once() -> void:
	var file := PlaytestJsonl.new()
	file.max_bytes = 2000
	assert_bool(file.open(_dir + "/cap.jsonl")).is_true()
	var puts: Array[PlaytestJsonl.Put] = []
	for i in 100:
		puts.append(file.put({"i": i, "pad": "x".repeat(40)}))
	assert_int(puts[0]).is_equal(PlaytestJsonl.Put.WRITTEN)
	assert_int(puts.count(PlaytestJsonl.Put.CAPPED_NOW)).is_equal(1)
	assert_int(puts.back()).is_equal(PlaytestJsonl.Put.DROPPED)
	file.put_notice({"type": "capped"})
	file.put_notice({"type": "capped"})
	file.close()
	var text := FileAccess.get_file_as_string(_dir + "/cap.jsonl")
	assert_int(text.to_utf8_buffer().size()).is_less_equal(2000)
	assert_int(text.count('"capped"')).is_equal(1)
	assert_int(text.split("\n", false).size()).is_equal(puts.count(PlaytestJsonl.Put.WRITTEN) + 1)


func test_the_event_log_logs_one_capped_notice_and_keeps_the_ring() -> void:
	var log := PlaytestLog.new()
	log.max_bytes = 3000
	assert_bool(log.open(_dir + "/events.jsonl")).is_true()
	for i in 200:
		log.add(i, "passenger_stage", {"id": i})
	log.close()
	var lines := FileAccess.get_file_as_string(_dir + "/events.jsonl").split("\n", false)
	var last: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	assert_str(last["type"]).is_equal("session")
	assert_str(last["data"]["state"]).is_equal("capped")
	assert_int(log.counts()["session"]).is_equal(1)
	assert_int(log.counts()["passenger_stage"]).is_equal(200)
	assert_int(log.last(1)[0]["data"]["id"]).is_equal(199)


func test_pruning_keeps_the_newest_sessions_and_their_input_files() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for n in range(1, 13):
		for suffix in [".jsonl", ".input.jsonl"]:
			var file := FileAccess.open("%s/s%02d%s" % [_dir, n, suffix], FileAccess.WRITE)
			file.store_line("{}")
			file.close()
	var other := FileAccess.open(_dir + "/notes.txt", FileAccess.WRITE)
	other.close()
	assert_int(PlaytestJsonl.prune_sessions(_dir, 10)).is_equal(2)
	var left := Array(DirAccess.get_files_at(_dir))
	assert_int(left.size()).is_equal(21)
	assert_array(left).not_contains(["s01.jsonl", "s01.input.jsonl", "s02.jsonl"])
	assert_array(left).contains(["s03.jsonl", "s03.input.jsonl", "s12.jsonl", "notes.txt"])


func test_pruning_a_folder_that_does_not_exist_yet_is_quiet() -> void:
	var missing := _dir + "/not_made_yet"
	await assert_error(func() -> void: PlaytestJsonl.prune_sessions(missing, 3)).is_success()
	assert_int(PlaytestJsonl.prune_sessions(missing, 3)).is_equal(0)
