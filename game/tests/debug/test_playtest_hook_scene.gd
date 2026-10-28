class_name TestPlaytestHookScene
extends GdUnitTestSuite
## PlaytestHook on the real main scene, headless. before() plays one scripted
## session once: the starter terminal on the Toon shell's doors B and C, an
## Entrance placed away from any Toon door (refused), both check-in desks taken
## away and put back (passengers stuck, the
## stuck_too_long anomaly raised and cleared), a passenger spawned too late to
## board, one push_error(), and the flight run to DEPARTED, then two cafe rooms
## marked (one removed again) and one refused for overlapping. The cases read
## the log file, the snapshot and the events it left.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
const STUCK_LIMIT_S := 2.0
## The desk ticks count from the first passenger's arrival, the late spawn
## and the end from the first state of the starter's first flight.
const DESKS_GONE_TICK := 300
const STUCK_CHECK_TICK := 420
const DESKS_BACK_TICK := 430
const CLEAR_CHECK_TICK := 600
const LATE_SPAWN_TICK := 1890
const END_TICK := 2600
const DOOR_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)
## A shell-edge cell more than the snap radius from any Toon door.
const OFF_DOOR_CELL := Vector2i(12, 29)
const ERROR_TEXT := "PlaytestHook test error"
## The starter contract's booked passengers plus the one spawned too late.
const PASSENGERS := FlightSim.STARTER_TERMS["booked_passengers"] + 1

var _dir := SaveTestKit.run_dir("playtest_scene_test")
var _off_dir := SaveTestKit.run_dir("playtest_scene_test_off")
var _again_dir := SaveTestKit.run_dir("playtest_scene_test_again")
var _main: Node
var _hook: Node
var _clock: SimClock
var _sim: PassengerSim
var _mode: BuildMode
var _attached := false
var _stuck_open_at_check := false
var _late_id := 0
## The cafe kept, the one removed again, and the rectangle each one marks.
var _kept_room := 0
var _removed_room := 0
var _kept_rect := Rect2i()
var _removed_rect := Rect2i()
var _snapshot: Dictionary
var _events: Array[Dictionary] = []
## The first state of the starter's first flight.
var _start := 0


func before() -> void:
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(7)
	_sim = _main.get_node("PassengerSim")
	_mode = _main.get_node("BuildMode")
	add_child(_main)
	_clock.set_paused(true)
	_hook = HOOK.new()
	_hook.configure(true, _dir)
	_hook.stuck_limit_s = STUCK_LIMIT_S
	add_child(_hook)
	_attached = _hook.attach(_main)
	_push_input()
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	# A new game has no staff: seat one at every desk and scanner so the
	# session's passengers are served.
	StaffTestKit.staff_all(_main.get_node("Staff"))
	var grid := _mode.grid
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode.apply_at(grid.cell_to_world(OFF_DOOR_CELL))
	_mode.set_tool(BuildMode.Tool.NONE)
	# Staffed, the airport opens on the first tick and the starter's first
	# flight starts ISSUE_LEAD_TICKS later; the session's ticks count from it.
	_run_to(1)
	var starter := (_main.get_node("FlightSim") as FlightSim).contract_of(FlightSim.DEFAULT_ID)
	_start = FlightTimetable.starts_for(starter, 0)[FlightSim.State.SCHEDULED]
	# The first passengers arrive well before the flight's first state; the
	# desks go and come back while they walk to check-in.
	while _sim.passenger_ids().is_empty() and _clock.tick < _start:
		_run_to(_clock.tick + 1)
	var arrived := _clock.tick
	_run_to(arrived + DESKS_GONE_TICK)
	var desks := _take_desks()
	_run_to(arrived + STUCK_CHECK_TICK)
	_check()
	_stuck_open_at_check = not _hook.stuck_list().is_empty()
	_put_back(desks)
	_run_to(arrived + CLEAR_CHECK_TICK)
	_check()
	_run_to(_start + LATE_SPAWN_TICK)
	_late_id = _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	_run_to(_start + END_TICK)
	# Before the last check, whose flush puts the room events in the file.
	_mark_rooms()
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
	for dir in [_dir, _off_dir, _again_dir]:
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
	assert_int(counts["passenger_made"] + counts["passenger_missed"]).is_equal(PASSENGERS)


func test_a_door_away_from_the_toon_doors_is_logged_with_its_reason() -> void:
	var refused := _of_type("build_refused").filter(
		func(e): return e["data"]["kind"] == "PLACE_OBJECT"
	)
	assert_int(refused.size()).is_equal(1)
	assert_str(refused[0]["data"]["reason"]).is_equal("DOOR_NOT_AT_SHELL_DOOR")
	var cell: Array = refused[0]["data"]["cell"]
	assert_that(Vector2i(int(cell[0]), int(cell[1]))).is_equal(OFF_DOOR_CELL)


func test_room_edits_are_logged_with_their_room() -> void:
	var rooms := _of_type("build_edit").filter(
		func(e): return String(e["data"]["kind"]).ends_with("_ROOM")
	)
	assert_int(rooms.size()).is_equal(3)
	var kept: Dictionary = rooms[0]["data"]
	assert_str(kept["kind"]).is_equal("PLACE_ROOM")
	assert_str(kept["room_type"]).is_equal("cafe")
	assert_array(_ints(kept["rect"])).is_equal(_rect_array(_kept_rect))
	assert_int(int(kept["room_id"])).is_equal(_kept_room)
	assert_int(int(rooms[1]["data"]["room_id"])).is_equal(_removed_room)
	var removed: Dictionary = rooms[2]["data"]
	assert_str(removed["kind"]).is_equal("REMOVE_ROOM")
	assert_int(int(removed["room_id"])).is_equal(_removed_room)
	assert_bool(removed.has("cell")).is_false()


func test_a_refused_room_is_logged_with_its_rectangle_and_reason() -> void:
	var refused := _of_type("build_refused").filter(
		func(e): return e["data"]["kind"] == "PLACE_ROOM"
	)
	assert_int(refused.size()).is_equal(1)
	var data: Dictionary = refused[0]["data"]
	assert_str(data["reason"]).is_equal("ROOM_OVERLAP")
	assert_str(data["room_type"]).is_equal("cafe")
	assert_array(_ints(data["rect"])).is_equal(_rect_array(_kept_rect))


func test_the_snapshot_lists_the_rooms_left() -> void:
	var rooms: Array = _snapshot["grid"]["rooms"]
	assert_int(rooms.size()).is_equal(1)
	assert_int(int(rooms[0]["id"])).is_equal(_kept_room)
	assert_str(rooms[0]["type"]).is_equal("cafe")
	assert_array(_ints(rooms[0]["rect"])).is_equal(_rect_array(_kept_rect))
	assert_bool(rooms[0]["ready"]).is_false()


func test_the_late_passenger_is_logged_as_missed() -> void:
	var missed := _of_type("passenger_missed").filter(func(e): return e["data"]["id"] == _late_id)
	assert_int(missed.size()).is_equal(1)


func test_the_snapshot_reports_flight_passengers_grid_and_events() -> void:
	assert_bool(_snapshot["attached"]).is_true()
	assert_int(_snapshot["tick"]).is_equal(_start + END_TICK)
	assert_int(_start).is_equal(1 + 19 + FlightTimetable.ISSUE_LEAD_TICKS)
	assert_str(_snapshot["flight_state"]).is_equal("DEPARTED")
	# Settled passengers are retired 200 ticks after their outcome; the durable
	# totals still count all of them and nobody is left in the list.
	var summary: Dictionary = _snapshot["passengers"]
	assert_int(summary["made"] + summary["missed"]).is_equal(PASSENGERS)
	assert_int(summary["total"]).is_equal(0)
	assert_dict(summary["by_stage"]).is_empty()
	var grid: Dictionary = _snapshot["grid"]
	# The 12 x 30 terminal, door B to gate C.
	assert_int(grid["floor_cells"]).is_equal(12 * 30)
	var objects := {
		"checkin_desk": 2,
		"security_scanner": 2,
		"seat_row": 4,
		"entrance_door": 1,
		"exit_door": 1,
	}
	assert_dict(grid["objects"]).is_equal(objects)
	assert_int(grid["walls"]["PLAIN"]).is_greater(0)
	assert_array(grid["entrances"][0]["cell"]).is_equal([DOOR_B.x, DOOR_B.y])
	assert_array(grid["exits"][0]["cell"]).is_equal([GATE_C.x, GATE_C.y])
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
	again.configure(true, _again_dir)
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
	off.configure(false, _off_dir, true)
	add_child(off)
	assert_bool(off.is_processing()).is_false()
	assert_bool(get_tree().node_added.is_connected(off._on_node_added)).is_false()
	assert_bool(off.attach(_main)).is_false()
	assert_bool(off.is_attached()).is_false()
	assert_dict(off.snapshot()).is_equal({"enabled": false, "attached": false})
	assert_bool(DirAccess.dir_exists_absolute(_off_dir)).is_false()


## The mouse events are pushed in the viewport's own (content-scaled) coordinates,
## so the recorded positions equal the pushed ones.
## Three mouse moves at once, a right-button release, and three key presses:
## F9 (bound to nothing), Space (read by the HUD) and R (build_rotate).
func _push_input() -> void:
	for x in [100.0, 120.0, 140.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(x, 50.0)
		motion.relative = Vector2(20.0, 0.0)
		get_viewport().push_input(motion, true)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.position = Vector2(140.0, 50.0)
	get_viewport().push_input(button, true)
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


## Marks a cafe on the first all-floor 3x3 rectangle, refuses one on top of
## it, and marks and removes a second one beside it.
func _mark_rooms() -> void:
	var grid := _mode.grid
	_kept_rect = _floored_rect(grid, Rect2i())
	_kept_room = grid.apply(BuildEdit.place_room(_kept_rect, &"cafe")).room_id
	grid.apply(BuildEdit.place_room(_kept_rect, &"cafe"))
	_removed_rect = _floored_rect(grid, _kept_rect)
	_removed_room = grid.apply(BuildEdit.place_room(_removed_rect, &"cafe")).room_id
	grid.apply(BuildEdit.remove_room(_removed_room))


## The first 3x3 rectangle, in row order, whose cells all have floor and lie
## outside `skip`.
func _floored_rect(grid: BuildGrid, skip: Rect2i) -> Rect2i:
	for y in grid.size.y - 2:
		for x in grid.size.x - 2:
			var area := Rect2i(x, y, 3, 3)
			if skip.intersects(area):
				continue
			var floored := true
			for cy in range(y, y + 3):
				for cx in range(x, x + 3):
					floored = floored and grid.floor_at(Vector2i(cx, cy)) != BuildGrid.FLOOR_NONE
			if floored:
				return area
	return Rect2i()


func _rect_array(area: Rect2i) -> Array:
	return [area.position.x, area.position.y, area.size.x, area.size.y]


## JSON turns whole numbers into floats.
func _ints(values: Array) -> Array:
	return values.map(func(v): return int(v))
