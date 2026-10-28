class_name TestSaveGameFile
extends GdUnitTestSuite
## The whole-world save's pre-save step, its files and its keys (Economy
## 8/8). A save is taken only between ticks with no build change waiting for
## the next tick's reconcile; a refused request waits and is written after the
## next tick. Files go through a .tmp file renamed over the old save, and every
## failure is shown. F5 quick-saves and F8 quick-loads. One boot of main.tscn
## for the file; every file a case writes is removed.

const SEED := 27_102_026
const DIR := "user://saves"
var _path := SaveTestKit.run_path("test_save_game_file")
var _blocked := SaveTestKit.run_path("test_save_game_blocked")
var _bad := SaveTestKit.run_path("test_save_game_bad")

var _main: Node
var _save: SaveGame
var _clock: SimClock
var _in_tick_problem := ""


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_clock = _main.get_node("SimClock")
	_save.quick_save_path = _path
	SaveTestKit.start_airport(_main)
	for i in 600:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


func after_test() -> void:
	for path in [_path, _path + ".tmp", _bad, _blocked]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(_blocked + ".tmp"):
		DirAccess.remove_absolute(_blocked + ".tmp")
	_save.pending_path = ""


func _floor_cell() -> Vector2i:
	var grid := (_main.get_node("BuildMode") as BuildMode).grid
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				return cell
	return Vector2i(-1, -1)


## A grid edit (floor painted on a bare cell), which leaves the cafe to be
## settled on the next tick.
func _edit() -> void:
	var build: BuildMode = _main.get_node("BuildMode")
	var result := build.grid.apply(BuildEdit.paint_floor(_floor_cell(), BuildGrid.FLOOR_TILE, 1))
	assert_bool(result.ok).is_true()
	assert_bool((_main.get_node("PassengerSim") as PassengerSim).cafes.deadlines_stale).is_true()


func _press(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	get_viewport().push_input(key)


func test_a_save_from_inside_a_tick_is_refused() -> void:
	var listener := func(_tick: int) -> void: _in_tick_problem = _save.save_problem()
	_clock.ticked.connect(listener)
	SaveTestKit.step(_main)
	_clock.ticked.disconnect(listener)
	assert_str(_in_tick_problem).contains("tick")
	assert_str(_save.save_problem()).is_equal("")


func test_a_save_after_a_build_change_waits_for_the_next_tick_and_changes_nothing() -> void:
	_edit()
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.snapshot().is_empty()).is_true()
	assert_bool(_save.request_save(_path)).is_false()
	assert_bool(FileAccess.file_exists(_path)).is_false()
	assert_str(_save.pending_path).is_equal(_path)
	assert_str(_save.message_text()).contains("next tick")
	# Nothing was settled early: the cafe still waits for the tick.
	assert_bool((_main.get_node("PassengerSim") as PassengerSim).cafes.deadlines_stale).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	assert_bool(_save.retry_pending()).is_false()
	SaveTestKit.step(_main)
	assert_bool(_save.retry_pending()).is_true()
	assert_bool(FileAccess.file_exists(_path)).is_true()
	assert_str(_save.pending_path).is_equal("")


func test_a_load_drops_a_waiting_save() -> void:
	assert_bool(_save.save_to_file(_path)).is_true()
	_edit()
	assert_bool(_save.request_save(_bad)).is_false()
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_str(_save.pending_path).is_equal("")
	SaveTestKit.step(_main)
	assert_bool(_save.retry_pending()).is_false()
	assert_bool(FileAccess.file_exists(_bad)).is_false()


func test_a_save_file_replaces_the_old_one_through_a_temp_file() -> void:
	assert_bool(_save.save_to_file(_path)).is_true()
	var first := FileAccess.get_file_as_string(_path)
	for i in 20:
		SaveTestKit.step(_main)
	assert_bool(_save.save_to_file(_path)).is_true()
	var second := FileAccess.get_file_as_string(_path)
	assert_str(second).is_not_equal(first)
	assert_bool(FileAccess.file_exists(_path + ".tmp")).is_false()
	assert_str(_save.message_text()).is_equal("Saved to %s" % _path)
	var data: Dictionary = JSON.parse_string(second)
	assert_str(str(data["clock"]["tick"])).is_equal(str(_clock.tick))


func test_a_file_that_cannot_be_written_is_shown_and_keeps_the_old_save() -> void:
	const SENTINEL := "the old save, which must survive"
	var old := FileAccess.open(_blocked, FileAccess.WRITE)
	old.store_string(SENTINEL)
	old.close()
	# A folder where the .tmp file goes makes writing it fail.
	assert_int(DirAccess.make_dir_recursive_absolute(_blocked + ".tmp")).is_equal(OK)
	assert_bool(_save.save_to_file(_blocked)).is_false()
	assert_str(_save.message_text()).starts_with("Save failed: cannot write")
	assert_str(FileAccess.get_file_as_string(_blocked)).is_equal(SENTINEL)


func test_a_missing_or_broken_file_is_shown_and_changes_nothing() -> void:
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_from_file(_path)).is_false()
	assert_str(_save.message_text()).contains("there is no save")
	var file := FileAccess.open(_bad, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	assert_bool(_save.load_from_file(_bad)).is_false()
	assert_str(_save.message_text()).contains("is not a save")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


func test_f5_quick_saves_and_f8_quick_loads() -> void:
	var saved_sum := SaveTestKit.checksum(_main)
	_press(SaveGame.QUICK_SAVE_KEY)
	assert_bool(FileAccess.file_exists(_path)).is_true()
	for i in 20:
		SaveTestKit.step(_main)
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(saved_sum)
	_press(SaveGame.QUICK_LOAD_KEY)
	assert_str(_save.message_text()).is_equal("Loaded")
	assert_str(SaveTestKit.checksum(_main)).is_equal(saved_sum)
	assert_bool(DirAccess.dir_exists_absolute(DIR)).is_true()
