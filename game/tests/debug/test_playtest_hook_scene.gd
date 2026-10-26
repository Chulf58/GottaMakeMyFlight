class_name TestPlaytestHookScene
extends GdUnitTestSuite
## PlaytestHook on the real main scene, headless. before() plays one scripted
## session once: the starter terminal, a Floor rectangle with one cell refused,
## both check-in desks taken away and put back (passengers stuck, the
## stuck_too_long anomaly raised and cleared), a passenger spawned too late to
## board, one push_error(), and the flight run to DEPARTED. The cases read the
## log file, the snapshot and the events it left.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
const DIR := "user://playtest_scene_test"
const OFF_DIR := "user://playtest_scene_test_off"
const AGAIN_DIR := "user://playtest_scene_test_again"
const STUCK_LIMIT_S := 2.0
const DESKS_GONE_TICK := 300
const STUCK_CHECK_TICK := 420
const DESKS_BACK_TICK := 430
const CLEAR_CHECK_TICK := 600
const LATE_SPAWN_TICK := 1890
const END_TICK := 2600
const ERROR_TEXT := "PlaytestHook test error"

var _main: Node
var _hook: Node
var _clock: SimClock
var _sim: PassengerSim
var _mode: BuildMode
var _attached := false
var _stuck_open_at_check := false
var _late_id := 0
var _snapshot: Dictionary
var _events: Array[Dictionary] = []


func before() -> void:
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(7)
	_sim = _main.get_node("PassengerSim")
	_mode = _main.get_node("BuildMode")
	add_child(_main)
	_clock.set_paused(true)
	_hook = HOOK.new()
	_hook.configure(true, DIR)
	_hook.stuck_limit_s = STUCK_LIMIT_S
	add_child(_hook)
	_attached = _hook.attach(_main)
	_push_input()
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var grid := _mode.grid
	var behind := ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, 1)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(grid.cell_to_world(behind + Vector2i(-1, 0)))
	_mode.move_area(grid.cell_to_world(behind + Vector2i(1, 0)))
	_mode.finish_area()
	_mode.set_tool(BuildMode.Tool.NONE)
	_run_to(DESKS_GONE_TICK)
	var desks := _take_desks()
	_run_to(STUCK_CHECK_TICK)
	_check()
	_stuck_open_at_check = not _hook.stuck_list().is_empty()
	_put_back(desks)
	_run_to(CLEAR_CHECK_TICK)
	_check()
	_run_to(LATE_SPAWN_TICK)
	_late_id = _sim.spawn_now(FlightSim.DEFAULT_ID)
	_run_to(END_TICK)
	push_error(ERROR_TEXT)
	_check()
	_snapshot = _hook.snapshot(5)
	# The file has every event; the ring only the last ones.
	for line in FileAccess.get_file_as_string(_hook.log_path()).split("\n", false):
		_events.append(JSON.parse_string(line))


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for dir in [DIR, OFF_DIR, AGAIN_DIR]:
		for name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, name])
		DirAccess.remove_absolute(dir)


func test_the_log_file_has_every_event_type() -> void:
	assert_bool(_attached).is_true()
	var counts := {}
	for event in _events:
		counts[event["type"]] = counts.get(event["type"], 0) + 1
	for type in HOOK.EVENT_TYPES:
		assert_int(counts.get(type, 0)).override_failure_message("no %s line" % type).is_greater(0)
	assert_int(counts["passenger_made"] + counts["passenger_missed"]).is_equal(25)


func test_a_refused_rectangle_cell_is_logged_with_its_reason() -> void:
	var refused := _of_type("build_refused")
	assert_int(refused.size()).is_equal(1)
	assert_str(refused[0]["data"]["reason"]).is_equal("DOOR_NOT_ON_EDGE")
	var cell: Array = refused[0]["data"]["cell"]
	assert_that(Vector2i(int(cell[0]), int(cell[1]))).is_equal(Vector2i(18, 18))


func test_the_late_passenger_is_logged_as_missed() -> void:
	var missed := _of_type("passenger_missed").filter(func(e): return e["data"]["id"] == _late_id)
	assert_int(missed.size()).is_equal(1)


func test_the_snapshot_reports_flight_passengers_grid_and_events() -> void:
	assert_bool(_snapshot["attached"]).is_true()
	assert_int(_snapshot["tick"]).is_equal(END_TICK)
	assert_str(_snapshot["flight_state"]).is_equal("DEPARTED")
	var by_stage: Dictionary = _snapshot["passengers"]["by_stage"]
	assert_int(by_stage.get("MADE", 0) + by_stage.get("MISSED", 0)).is_equal(25)
	assert_int(_snapshot["passengers"]["total"]).is_equal(25)
	var grid: Dictionary = _snapshot["grid"]
	# The 12 x 16 terminal plus the two rectangle cells beside the entrance.
	assert_int(grid["floor_cells"]).is_equal(12 * 16 + 2)
	var objects := {
		"checkin_desk": 2,
		"security_scanner": 2,
		"seat_row": 4,
		"entrance_door": 1,
		"exit_door": 1,
	}
	assert_dict(grid["objects"]).is_equal(objects)
	assert_int(grid["walls"]["PLAIN"]).is_greater(0)
	assert_array(grid["entrances"][0]["cell"]).is_equal([18, 17])
	assert_array(grid["exits"][0]["cell"]).is_equal([20, 2])
	assert_int(_snapshot["events"].size()).is_equal(5)
	assert_int(_snapshot["event_total"]).is_greater(_snapshot["events"][4]["i"])
	assert_array(_snapshot["stuck"]).is_empty()
	assert_str(_snapshot["seed"]).is_equal("7")
	assert_str(JSON.stringify(_snapshot)).is_not_empty()


func test_a_stuck_passenger_raises_the_anomaly_once_and_it_clears() -> void:
	assert_bool(_stuck_open_at_check).is_true()
	var stuck := _of_type("passenger_stuck")
	assert_str(stuck[0]["data"]["reason"]).is_equal("NO_CHECKIN")
	var raised := {}
	var cleared := {}
	for event in _of_type("anomaly"):
		var data: Dictionary = event["data"]
		if data["kind"] != "stuck_too_long":
			continue
		var into := raised if data["state"] == "raised" else cleared
		into[data["subject"]] = into.get(data["subject"], 0) + 1
	assert_int(raised.size()).is_greater(0)
	for subject in raised:
		assert_int(raised[subject]).is_equal(1)
		assert_int(cleared.get(subject, 0)).is_equal(1)
	assert_array(_snapshot["anomalies"]).is_empty()


func test_a_push_error_is_logged_as_an_error() -> void:
	var errors := _of_type("error").filter(func(e): return e["data"]["message"] == ERROR_TEXT)
	assert_int(errors.size()).is_equal(1)


func test_input_is_recorded_for_replay_without_typed_text() -> void:
	var lines := FileAccess.get_file_as_string(_hook.input_log_path()).split("\n", false)
	var records: Array[Dictionary] = []
	for line in lines:
		records.append(JSON.parse_string(line))
	# Three moves inside 50 ms keep the first and, before the button, the last;
	# F9 is bound to nothing and is left out.
	var types := records.map(func(r): return r["type"])
	assert_array(types).is_equal(["motion", "motion", "button", "key", "key"])
	assert_float(records[0]["position"][0]).is_equal(100.0)
	assert_float(records[1]["position"][0]).is_equal(140.0)
	assert_float(records[1]["relative"][0]).is_equal(40.0)
	assert_int(int(records[2]["button"])).is_equal(MOUSE_BUTTON_RIGHT)
	assert_int(int(records[3]["physical_keycode"])).is_equal(KEY_SPACE)
	assert_array(records[4]["actions"]).is_equal(["build_rotate"])
	assert_int(int(records[4]["tick"])).is_equal(0)
	for record in records:
		for banned in ["text", "unicode", "keycode"]:
			assert_bool(record.has(banned)).override_failure_message(banned).is_false()


func test_each_attach_starts_a_new_session_file() -> void:
	var again: Node = auto_free(HOOK.new())
	again.configure(true, AGAIN_DIR)
	add_child(again)
	assert_bool(again.attach(_main)).is_true()
	var first: String = again.log_path()
	again.detach()
	assert_bool(again.attach(_main)).is_true()
	var second: String = again.log_path()
	again.detach()
	assert_str(second).is_not_equal(first)
	var first_lines := FileAccess.get_file_as_string(first).split("\n", false)
	assert_int(first_lines.size()).is_equal(2)
	assert_str(JSON.parse_string(first_lines[1])["data"]["state"]).is_equal("end")
	var start: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(second).split("\n")[0])
	assert_int(int(start["i"])).is_equal(0)
	assert_str(start["data"]["state"]).is_equal("start")


func test_events_since_reads_from_an_index() -> void:
	var last: int = _hook.event_counts().values().reduce(func(a, b): return a + b) - 1
	var tail: Array[Dictionary] = _hook.events_since(last - 2)
	assert_int(tail.size()).is_equal(3)
	assert_int(tail[0]["i"]).is_equal(last - 2)
	assert_int(tail[2]["i"]).is_equal(last)


func test_a_disabled_hook_attaches_to_nothing_and_writes_nothing() -> void:
	var off: Node = auto_free(HOOK.new())
	off.configure(false, OFF_DIR, true)
	add_child(off)
	assert_bool(off.is_processing()).is_false()
	assert_bool(get_tree().node_added.is_connected(off._on_node_added)).is_false()
	assert_bool(off.attach(_main)).is_false()
	assert_bool(off.is_attached()).is_false()
	assert_dict(off.snapshot()).is_equal({"enabled": false, "attached": false})
	assert_bool(DirAccess.dir_exists_absolute(OFF_DIR)).is_false()


## Three mouse moves at once, a right-button release, and three key presses:
## F9 (bound to nothing), Space (read by the HUD) and R (build_rotate).
func _push_input() -> void:
	for x in [100.0, 120.0, 140.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(x, 50.0)
		motion.relative = Vector2(20.0, 0.0)
		get_viewport().push_input(motion)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.position = Vector2(140.0, 50.0)
	get_viewport().push_input(button)
	for code in [KEY_F9, KEY_SPACE, KEY_R]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.unicode = 32 if code == KEY_SPACE else 0
		key.pressed = true
		get_viewport().push_input(key)


func _of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _events:
		if event["type"] == type:
			out.append(event)
	return out


## Ticks the paused clock by hand up to `tick`.
func _run_to(tick: int) -> void:
	_clock.set_paused(false)
	while _clock.tick < tick:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


## Draws the views for this tick, as the frame would, and runs the checks.
func _check() -> void:
	(_main.get_node("PassengerViews") as PassengerViews).draw()
	_hook.run_checks()


func _take_desks() -> Array[Dictionary]:
	var grid := _mode.grid
	var desks: Array[Dictionary] = []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if record["def"] == &"checkin_desk":
			desks.append(record)
			grid.apply(BuildEdit.remove_object(object_id))
	(_mode.get_node("BuildView") as BuildView).refresh(grid)
	return desks


func _put_back(desks: Array[Dictionary]) -> void:
	var grid := _mode.grid
	for record in desks:
		grid.apply(BuildEdit.place_object(record["def"], record["anchor"], record["facing"]))
	(_mode.get_node("BuildView") as BuildView).refresh(grid)
