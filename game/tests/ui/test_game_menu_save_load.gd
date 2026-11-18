class_name TestGameMenuSaveLoad
extends GdUnitTestSuite
## Save and Load in the Esc game menu (decision title-menu-with-continue-new-
## airport-load-and-quit-autosave). Save writes the manual save (the F5 file);
## Load lists the saves that exist and loads the one picked through
## load_from_file, which closes the menu and leaves the game paused at 1x; a
## refused load keeps the menu open and shows why. One boot of main.tscn, saves
## in a folder of this run's own.

const SEED := 18_112_028

var _dir := SaveTestKit.run_dir("test_game_menu_save_load")
var _dir_before := ""
var _main: Node
var _menu: GameMenu
var _save: SaveGame
var _clock: SimClock


func before() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	_main = SaveTestKit.boot(self, SEED)
	_menu = _main.get_node("GameMenu")
	_save = SaveTestKit.save_game(_main)
	_clock = _main.get_node("SimClock")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)


func after() -> void:
	_main.free()
	_remove_files()
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before


func before_test() -> void:
	_menu.close()
	_remove_files()


func _remove_files() -> void:
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func test_the_manual_save_follows_the_slot_folder() -> void:
	assert_str(_save.quick_save_path).is_equal(SaveSlots.manual_path())


func test_the_main_page_holds_resume_save_load_and_settings_in_order() -> void:
	assert_bool(_menu.open()).is_true()
	var names: Array[String] = []
	for child in _menu.resume_button().get_parent().get_children():
		names.append(child.name)
	assert_array(names).is_equal(["Title", "Resume", "Save", "Load", "Settings"])


func test_save_writes_the_manual_save_and_says_so() -> void:
	_menu.open()
	_menu.save_button().pressed.emit()
	print("status: '%s'" % _menu.status_text())
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_true()
	assert_str(_menu.status_text()).is_equal(_save.message_text())
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_menu.load_button().disabled).is_false()


func test_load_lists_the_saves_and_a_pick_loads_it_paused_at_1x() -> void:
	assert_bool(_save.save_to_file(SaveSlots.manual_path())).is_true()
	var saved_tick := _clock.tick
	SaveTestKit.step(_main)
	_clock.set_speed(3)
	var seen: Array[bool] = []
	_save.loaded.connect(func(ok: bool) -> void: seen.append(ok), CONNECT_ONE_SHOT)
	_menu.open()
	_menu.load_button().pressed.emit()
	var list := _menu.save_list()
	assert_bool(list.is_visible_in_tree()).is_true()
	assert_array(list.paths()).is_equal([SaveSlots.manual_path()])
	list.button_for(SaveSlots.manual_path()).pressed.emit()
	print("menu load: loaded=%s tick=%d saved=%d" % [seen, _clock.tick, saved_tick])
	assert_array(seen).is_equal([true])
	assert_int(_clock.tick).is_equal(saved_tick)
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)


func test_a_refused_load_keeps_the_menu_open_and_shows_why() -> void:
	var bad := FileAccess.open(SaveSlots.autosave_paths()[0], FileAccess.WRITE)
	bad.store_string('{"save_version": 1}')
	bad.close()
	var tick := _clock.tick
	_menu.open()
	_menu.press_load()
	_menu.save_list().button_for(SaveSlots.autosave_paths()[0]).pressed.emit()
	print("refused: '%s'" % _menu.status_text())
	assert_bool(_menu.is_open()).is_true()
	assert_str(_menu.status_text()).contains("Load failed")
	assert_str(_menu.status_text()).is_equal(_save.message_text())
	assert_int(_clock.tick).is_equal(tick)


func test_with_no_save_load_is_greyed() -> void:
	_menu.open()
	assert_bool(_menu.load_button().disabled).is_true()
	assert_bool(_menu.save_button().disabled).is_false()
