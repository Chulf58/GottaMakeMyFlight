class_name TestQuitLogMenu
extends GdUnitTestSuite
## The Esc menu's quit log controls and the main scene's recorder: the switch
## and the Open log folder button sit on the Settings page only when a recorder
## is wired in, the switch saves to the file it is given and starts the log, the
## button opens the log folder, and the real main scene boots with the log off
## and writes only the events that happen once it is on.

var _kit := IncidentPanelKit.new()
var _menu: GameMenu
var _recorder: QuitLogRecorder
var _dir := ""
var _settings := ""
var _opened: Array[String] = []


func before_test() -> void:
	_dir = SaveTestKit.run_dir("quit_log_menu")
	_settings = SaveTestKit.run_path("quit_log_menu_settings").replace(".json", ".cfg")
	QuitLog.current = null
	_opened.clear()
	_kit.build(self)
	_recorder = QuitLogRecorder.new()
	_recorder.settings_path = _settings
	_recorder.log_dir = _dir
	_kit.port.add_child(_recorder)
	_menu = GameMenu.new()
	_menu.director = _kit.director
	_menu.clock = _kit.clock
	_menu.save_game = _kit.save
	_menu.quit_log = _recorder
	_menu.open_folder = func(path: String) -> int:
		_opened.append(path)
		return OK
	_kit.port.add_child(_menu)


func after_test() -> void:
	QuitLog.current = null
	_kit.port.free()
	var absolute := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	for name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings))


func _page() -> Control:
	return _menu.incidents_switch().get_parent()


func _switch() -> CheckButton:
	return _page().get_node("QuitLog")


func _types() -> Array:
	var out := []
	var absolute := ProjectSettings.globalize_path(_dir)
	for name in DirAccess.get_files_at(absolute):
		var text := FileAccess.get_file_as_string("%s/%s" % [absolute, name])
		for line in text.strip_edges().split("\n", false):
			out.append(JSON.parse_string(line)["type"])
	return out


func test_the_settings_page_holds_the_switch_a_note_and_the_folder_button() -> void:
	_menu.open()
	_menu.press_settings()
	var names: Array[String] = []
	for child in _page().get_children():
		names.append(child.name)
	assert_array(names).is_equal(
		["Title", "Incidents", "QuitLog", "QuitLogNote", "OpenLogFolder", "Back"]
	)
	assert_bool(_switch().button_pressed).is_false()
	var note: Label = _page().get_node("QuitLogNote")
	assert_str(note.text).contains("this computer")


func test_the_switch_saves_the_choice_and_starts_the_log() -> void:
	_menu.open()
	_switch().button_pressed = true
	assert_bool(QuitLog.is_enabled(_settings)).is_true()
	assert_bool(_recorder.is_recording()).is_true()
	_switch().button_pressed = false
	assert_bool(QuitLog.is_enabled(_settings)).is_false()
	assert_bool(_recorder.is_recording()).is_false()
	var types := _types()
	assert_str(types[0]).is_equal("session_start")
	assert_str(types.back()).is_equal("session_end")


func test_the_menu_opening_is_an_event_only_while_the_log_is_on() -> void:
	_menu.open()
	_menu.close()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir))).is_false()
	_recorder.set_enabled(true)
	_menu.open()
	_menu.close()
	assert_array(_types()).contains(["game_menu_open"])


func test_the_folder_button_opens_the_log_folder() -> void:
	_menu.open()
	_menu.press_settings()
	_page().get_node("OpenLogFolder").pressed.emit()
	assert_array(_opened).is_equal([QuitLog.folder(_dir)])


func test_a_folder_that_will_not_open_says_so_in_the_status_line() -> void:
	_menu.open_folder = func(_path: String) -> int: return ERR_CANT_OPEN
	_menu.open()
	_menu.press_settings()
	_page().get_node("OpenLogFolder").pressed.emit()
	assert_str(_menu.status_text()).contains("Could not open the log folder")


func test_a_menu_without_a_recorder_has_neither_control() -> void:
	_menu.quit_log = null
	_menu.open()
	assert_object(_page().get_node_or_null("QuitLog")).is_null()
	assert_object(_page().get_node_or_null("OpenLogFolder")).is_null()


func test_the_main_scene_boots_with_the_log_off_and_writes_when_it_is_on() -> void:
	var main: Node = load(SaveTestKit.MAIN).instantiate()
	var recorder: QuitLogRecorder = main.get_node("QuitLogRecorder")
	recorder.settings_path = _settings
	recorder.log_dir = _dir
	main.get_node("SimClock").seed_rng(4242)
	main.get_node("SimClock").set_paused(true)
	add_child(main)
	assert_bool(recorder.is_recording()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir))).is_false()
	assert_object(main.get_node("GameMenu").quit_log).is_same(recorder)
	recorder.set_enabled(true)
	var grid: BuildGrid = main.get_node("BuildMode").grid
	var edit := BuildEdit.new()
	edit.kind = BuildEdit.Kind.PAINT_FLOOR
	grid.edit_applied.emit(edit, BuildResult.new())
	main.free()
	var types := _types()
	assert_str(types[0]).is_equal("session_start")
	assert_array(types).contains(["build_edit"])
	assert_str(types.back()).is_equal("session_end")
