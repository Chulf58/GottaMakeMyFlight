class_name TestSaveSlots
extends GdUnitTestSuite
## The save files the title screen and the game menu offer (decision title-menu-
## with-continue-new-airport-load-and-quit-autosave): the manual save and two
## autosaves under SaveSlots.dir, which this file points at a folder of its own.
## Newest first by modified time, the autosave that is due next, and the shield
## that keeps a script run off the player's folder.

var _dir := SaveTestKit.run_dir("test_save_slots")
var _dir_before := ""


func before_test() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before


func _write(path: String, version := SaveGame.SAVE_VERSION) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"save_version": %d}' % version)
	file.close()


func test_every_path_is_under_the_slot_folder_manual_first() -> void:
	assert_array(SaveSlots.all_paths()).is_equal(
		[_dir + "/quicksave.json", _dir + "/autosave_1.json", _dir + "/autosave_2.json"]
	)
	assert_str(SaveSlots.manual_path()).is_equal(_dir + "/quicksave.json")
	assert_array(SaveSlots.autosave_paths()).is_equal(
		[_dir + "/autosave_1.json", _dir + "/autosave_2.json"]
	)


func test_the_default_folder_is_the_quick_save_folder() -> void:
	assert_str(SaveSlots.DIR.path_join(SaveSlots.MANUAL_FILE)).is_equal(SaveGame.QUICK_SAVE_PATH)


func test_with_no_files_there_is_no_latest_save() -> void:
	assert_array(SaveSlots.existing()).is_empty()
	assert_str(SaveSlots.latest()).is_equal("")


func test_only_files_that_exist_are_listed() -> void:
	_write(SaveSlots.autosave_paths()[1])
	print("existing: %s" % [SaveSlots.existing()])
	assert_array(SaveSlots.existing()).is_equal([SaveSlots.autosave_paths()[1]])
	assert_str(SaveSlots.latest()).is_equal(SaveSlots.autosave_paths()[1])


func test_newest_first_orders_by_time_and_keeps_list_order_on_a_tie() -> void:
	var times := {"a": 100, "b": 300, "c": 200, "d": 300}
	assert_array(SaveSlots.newest_first(["a", "b", "c", "d"], times)).is_equal(["b", "d", "c", "a"])


func test_a_missing_autosave_is_due_first() -> void:
	var paths := SaveSlots.autosave_paths()
	assert_str(SaveSlots.next_autosave("")).is_equal(paths[0])
	_write(paths[0])
	assert_str(SaveSlots.next_autosave(paths[0])).is_equal(paths[1])
	_write(paths[1])
	DirAccess.remove_absolute(paths[0])
	assert_str(SaveSlots.next_autosave(paths[1])).is_equal(paths[0])


func test_with_both_written_the_one_not_written_last_is_due() -> void:
	var paths := SaveSlots.autosave_paths()
	_write(paths[0])
	_write(paths[1])
	assert_str(SaveSlots.next_autosave(paths[1])).is_equal(paths[0])
	assert_str(SaveSlots.next_autosave(paths[0])).is_equal(paths[1])


## A fresh session knows no last write: the older file is due, and on a tie the
## first.
func test_with_no_last_write_the_older_file_is_due() -> void:
	var paths := SaveSlots.autosave_paths()
	_write(paths[0])
	_write(paths[1])
	var due := SaveSlots.next_autosave("")
	var times := {
		paths[0]: FileAccess.get_modified_time(paths[0]),
		paths[1]: FileAccess.get_modified_time(paths[1]),
	}
	print("times: %s due: %s" % [times, due])
	var older := paths[1] if times[paths[1]] < times[paths[0]] else paths[0]
	assert_str(due).is_equal(older)


func test_a_script_run_on_the_players_folder_is_shielded_and_on_its_own_is_not() -> void:
	assert_bool(SaveSlots.is_shielded()).is_false()
	SaveSlots.dir = SaveSlots.DIR
	assert_bool(SaveSlots.is_shielded()).is_true()


func test_latest_skips_incompatible_and_corrupt_saves_without_deleting_them() -> void:
	var manual := SaveSlots.manual_path()
	var auto1 := SaveSlots.autosave_paths()[0]
	var auto2 := SaveSlots.autosave_paths()[1]
	_write(manual, SaveGame.SAVE_VERSION - 1)
	var corrupt := FileAccess.open(auto1, FileAccess.WRITE)
	corrupt.store_string("{not json")
	corrupt.close()

	assert_int(SaveSlots.file_save_version(manual)).is_equal(SaveGame.SAVE_VERSION - 1)
	assert_int(SaveSlots.file_save_version(auto1)).is_equal(-1)
	assert_bool(SaveSlots.is_compatible(manual)).is_false()
	assert_bool(SaveSlots.is_compatible(auto1)).is_false()
	assert_array(SaveSlots.existing()).has_size(2)
	assert_str(SaveSlots.latest()).is_equal("")
	# Incompatible files are never mutated or deleted.
	assert_bool(FileAccess.file_exists(manual)).is_true()
	assert_bool(FileAccess.file_exists(auto1)).is_true()

	# When a compatible save exists alongside incompatible ones, latest() picks it.
	_write(auto2, SaveGame.SAVE_VERSION)
	assert_bool(SaveSlots.is_compatible(auto2)).is_true()
	assert_str(SaveSlots.latest()).is_equal(auto2)
