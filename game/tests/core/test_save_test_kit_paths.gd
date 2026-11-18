class_name TestSaveTestKitPaths
extends GdUnitTestSuite
## SaveTestKit.run_path() keeps test files out of the player's save folder.

const PLAYER_SAVES := "user://saves"


func test_run_path_is_outside_the_players_save_folder() -> void:
	var path := SaveTestKit.run_path("test_save_test_kit_paths")
	assert_bool(path.begins_with(PLAYER_SAVES + "/")).is_false()
	assert_str(path.get_base_dir()).is_not_equal(PLAYER_SAVES)


func test_run_path_folder_exists_and_is_per_process() -> void:
	var path := SaveTestKit.run_path("test_save_test_kit_paths")
	assert_bool(DirAccess.dir_exists_absolute(path.get_base_dir())).is_true()
	assert_str(path).contains("_%d.json" % OS.get_process_id())
	assert_str(path.get_base_dir()).contains("/%d" % OS.get_process_id())


func test_run_path_keeps_the_file_name_scheme() -> void:
	var path := SaveTestKit.run_path("abc")
	assert_str(path.get_file()).is_equal("abc_%d.json" % OS.get_process_id())


func test_a_file_written_at_run_path_can_be_written_and_removed() -> void:
	var path := SaveTestKit.run_path("test_save_test_kit_paths_io")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("{}")
	file.close()
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)
	assert_bool(FileAccess.file_exists(path)).is_false()
