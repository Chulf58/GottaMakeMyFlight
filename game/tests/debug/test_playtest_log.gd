class_name TestPlaytestLog
extends GdUnitTestSuite
## PlaytestLog's file and ring buffer, PlaytestAnomalies' once-per-subject
## rule, PlaytestErrorLogger's queue and the hook's on/off and seed switches.

const DIR := "user://playtest_log_test"
const HOOK := preload("res://debug/playtest_hook.gd")


func after_test() -> void:
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, name])
	DirAccess.remove_absolute(DIR)


func test_each_event_is_one_json_line_with_tick_wall_type_and_data() -> void:
	var log := PlaytestLog.new()
	assert_bool(log.open(DIR + "/one.jsonl")).is_true()
	log.add(5, "build_edit", {"kind": "PAINT_FLOOR"})
	log.add(6, "anomaly", {"kind": "no_route"})
	log.close()
	var lines := FileAccess.get_file_as_string(DIR + "/one.jsonl").split("\n", false)
	assert_int(lines.size()).is_equal(2)
	var first: Dictionary = JSON.parse_string(lines[0])
	assert_int(int(first["i"])).is_equal(0)
	assert_int(int(first["tick"])).is_equal(5)
	assert_str(first["type"]).is_equal("build_edit")
	assert_str(first["data"]["kind"]).is_equal("PAINT_FLOOR")
	assert_float(first["wall"]).is_greater(1.0e9)
	assert_str(log.path).is_equal(ProjectSettings.globalize_path(DIR + "/one.jsonl"))


func test_the_ring_keeps_the_last_events_and_since_reads_from_an_index() -> void:
	var log := PlaytestLog.new()
	log.ring_size = 3
	for i in 5:
		log.add(i, "passenger_stage", {"n": i})
	assert_int(log.total()).is_equal(5)
	assert_int(log.counts()["passenger_stage"]).is_equal(5)
	var kept := log.since(0)
	assert_int(kept.size()).is_equal(3)
	assert_int(kept[0]["i"]).is_equal(2)
	assert_int(log.since(4).size()).is_equal(1)
	assert_int(log.since(5).size()).is_equal(0)
	assert_int(log.last(2)[0]["i"]).is_equal(3)


func test_an_anomaly_is_raised_once_per_subject_until_it_clears() -> void:
	var anomalies := PlaytestAnomalies.new()
	var key := PlaytestAnomalies.key_of("no_route", "passenger:4")
	var found := {key: {"kind": "no_route", "subject": "passenger:4", "detail": {}}}
	var first := anomalies.update(found, 10)
	assert_int(first["raised"].size()).is_equal(1)
	assert_int(first["raised"][0]["since_tick"]).is_equal(10)
	var again := anomalies.update(found, 20)
	assert_int(again["raised"].size()).is_equal(0)
	assert_int(again["cleared"].size()).is_equal(0)
	assert_bool(anomalies.is_open("no_route", "passenger:4")).is_true()
	var gone := anomalies.update({}, 30)
	assert_int(gone["cleared"].size()).is_equal(1)
	assert_int(gone["cleared"][0]["cleared_tick"]).is_equal(30)
	assert_bool(anomalies.is_open("no_route", "passenger:4")).is_false()
	assert_int(anomalies.update(found, 40)["raised"].size()).is_equal(1)


func test_the_error_logger_queues_errors_until_drained() -> void:
	var logger := PlaytestErrorLogger.new()
	var traces: Array[ScriptBacktrace] = []
	logger._log_error("f", "res://x.gd", 12, "code", "it broke", false, 0, traces)
	var drained := logger.drain()
	assert_int(drained.size()).is_equal(1)
	assert_str(drained[0]["message"]).is_equal("it broke")
	assert_str(drained[0]["kind"]).is_equal("error")
	assert_int(drained[0]["line"]).is_equal(12)
	assert_int(logger.drain().size()).is_equal(0)


## The old table had the hook on in every debug build and on in release with
## --playtest or the setting. The ruling is the reverse on both counts: never
## in release, and in a debug build only when opted in, so a player running the
## game from the editor gets no log files.
func test_the_hook_is_on_only_in_a_debug_build_that_opted_in() -> void:
	var none := PackedStringArray()
	var flag := PackedStringArray(["--playtest"])
	assert_bool(HOOK.wants_enabled(true, none, false, "")).is_false()
	assert_bool(HOOK.wants_enabled(true, flag, false, "")).is_true()
	assert_bool(HOOK.wants_enabled(true, none, true, "")).is_true()
	assert_bool(HOOK.wants_enabled(true, none, false, "1")).is_true()
	assert_bool(HOOK.wants_enabled(true, none, false, "0")).is_false()
	assert_bool(HOOK.wants_enabled(false, flag, true, "1")).is_false()
	assert_bool(HOOK.wants_enabled(false, none, false, "")).is_false()


func test_only_the_playtest_arguments_are_recorded() -> void:
	var args := PackedStringArray(["--playtest", "--token=abc", "--playtest-seed=5", "bob"])
	assert_array(HOOK.recorded_args(args)).is_equal(["--playtest", "--playtest-seed=5"])


func test_the_seed_argument_is_read_when_it_is_a_whole_number() -> void:
	assert_object(HOOK.seed_arg(PackedStringArray())).is_null()
	assert_object(HOOK.seed_arg(PackedStringArray(["--playtest-seed=abc"]))).is_null()
	var given: Variant = HOOK.seed_arg(PackedStringArray(["--x", "--playtest-seed=42"]))
	assert_int(given).is_equal(42)
