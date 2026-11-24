class_name TestGameMenuSaveLoad
extends GdUnitTestSuite
## Save, Load, Send Feedback, Main Menu, and Quit to Desktop in the Esc game
## menu (decisions title-menu-with-continue-new-airport-load-and-quit-autosave
## and esc-pause-menu-buttons-and-exit-flow-resume-save-load-settin). Save
## writes the manual save (the F5 file); Load lists the saves that exist and
## loads the one picked through load_from_file, which closes the menu and
## leaves the game paused at 1x; a refused load keeps the menu open and shows
## why. Main Menu and Quit to Desktop open an inline confirmation prompt with
## Save & Exit, Exit without Saving, and Cancel. One boot of main.tscn, saves
## in a folder of this run's own.

const SEED := 18_112_028

var _dir := SaveTestKit.run_dir("test_game_menu_save_load")
var _dir_before := ""
var _main: Node
var _menu: GameMenu
var _save: SaveGame
var _clock: SimClock
var _scenes: Array[String] = []
var _quits := 0
var _urls: Array[String] = []
var _quit_log_orig: QuitLogRecorder
var _quick_save_orig := ""
var _locale_before := ""


func before() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	_main = SaveTestKit.boot(self, SEED)
	_menu = _main.get_node("GameMenu")
	_save = SaveTestKit.save_game(_main)
	_clock = _main.get_node("SimClock")
	_quit_log_orig = _menu.quit_log
	_quick_save_orig = _save.quick_save_path
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)


func after() -> void:
	_main.free()
	_remove_files()
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before


func before_test() -> void:
	_locale_before = _locale_settings().current_locale()
	_scenes.clear()
	_quits = 0
	_urls.clear()
	_menu.close()
	_menu.change_scene = func(scene: String) -> Error:
		_scenes.append(scene)
		return OK
	_menu.quit_game = func() -> void: _quits += 1
	_menu.open_url = func(url: String) -> void: _urls.append(url)
	_menu.feedback_url = DemoMode.FEEDBACK_URL
	_menu.quit_log = _quit_log_orig
	_save.quick_save_path = _quick_save_orig
	(_main.get_node("BaggageSim") as BaggageSim).routes_stale = false
	_remove_files()


func after_test() -> void:
	PseudoLocale.disable()
	var settings := _locale_settings()
	var changed_locale: bool = settings.current_locale() != _locale_before
	if changed_locale:
		settings.apply_locale(_locale_before, false)
	(_main.get_node("BaggageSim") as BaggageSim).routes_stale = false
	_save.quick_save_path = _quick_save_orig
	_menu.quit_log = _quit_log_orig
	_menu.feedback_url = DemoMode.FEEDBACK_URL
	_menu.close()
	QuitLog.current = null
	if changed_locale:
		await await_idle_frame()


func _locale_settings() -> Node:
	return get_node("/root/LocaleSettings")


func _remove_files() -> void:
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func _main_page() -> Control:
	return _menu.resume_button().get_parent()


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func test_the_manual_save_follows_the_slot_folder() -> void:
	assert_str(_save.quick_save_path).is_equal(SaveSlots.manual_path())


func test_the_main_page_holds_ruled_buttons_in_order_and_toggles_send_feedback() -> void:
	assert_bool(_menu.open()).is_true()
	var all_names: Array[String] = []
	var visible_names: Array[String] = []
	for child in _main_page().get_children():
		all_names.append(child.name)
		if child.visible:
			visible_names.append(child.name)
	assert_array(all_names).is_equal(
		["Title", "Resume", "Save", "Load", "Settings", "SendFeedback", "MainMenu", "QuitToDesktop"]
	)
	assert_str(DemoMode.FEEDBACK_URL).is_equal("")
	assert_array(visible_names).is_equal(
		["Title", "Resume", "Save", "Load", "Settings", "MainMenu", "QuitToDesktop"]
	)

	_menu.close()
	_menu.feedback_url = "https://example.com/feedback"
	assert_bool(_menu.open()).is_true()
	visible_names.clear()
	for child in _main_page().get_children():
		if child.visible:
			visible_names.append(child.name)
	assert_array(visible_names).is_equal(
		["Title", "Resume", "Save", "Load", "Settings", "SendFeedback", "MainMenu", "QuitToDesktop"]
	)
	(_main_page().get_node("SendFeedback") as Button).pressed.emit()
	assert_array(_urls).is_equal(["https://example.com/feedback"])


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


func test_main_menu_confirm_cancel_and_esc_return_to_main_page() -> void:
	_menu.open()
	assert_bool(_menu.exit_confirm_page.visible).is_false()
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	assert_bool(_main_page().visible).is_false()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str((_menu.exit_confirm_page.get_node("Title") as Label).text).is_equal(
		"Return to main menu?"
	)
	assert_str((_menu.exit_confirm_page.get_node("Body") as Label).text).is_equal(
		"Unsaved progress will be lost."
	)
	(_menu.exit_confirm_page.get_node("Cancel") as Button).pressed.emit()
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_main_page().visible).is_true()
	assert_bool(_menu.exit_confirm_page.visible).is_false()
	assert_array(_scenes).is_empty()
	assert_int(_quits).is_equal(0)

	# Esc on the confirmation page returns to MainPage without exiting; second Esc closes menu.
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	_main.get_viewport().push_input(_esc())
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_main_page().visible).is_true()
	assert_bool(_menu.exit_confirm_page.visible).is_false()
	assert_array(_scenes).is_empty()
	_main.get_viewport().push_input(_esc())
	assert_bool(_menu.is_open()).is_false()


func test_main_menu_exit_without_saving_changes_to_title_without_writing_save() -> void:
	_menu.open()
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).pressed.emit()
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_false()
	assert_array(_scenes).is_equal([GameBoot.TITLE_SCENE])
	assert_int(_quits).is_equal(0)
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_clock.holds.is_holding()).is_false()


func test_main_menu_save_and_exit_writes_manual_save_and_changes_to_title() -> void:
	_menu.open()
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("SaveAndExit") as Button).pressed.emit()
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_true()
	assert_array(_scenes).is_equal([GameBoot.TITLE_SCENE])
	assert_int(_quits).is_equal(0)
	assert_bool(_menu.is_open()).is_false()


func test_save_and_exit_refuses_when_save_problem_or_write_error_and_stays_open() -> void:
	(_main.get_node("BaggageSim") as BaggageSim).routes_stale = true
	_menu.open()
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("SaveAndExit") as Button).pressed.emit()
	assert_array(_scenes).is_empty()
	assert_int(_quits).is_equal(0)
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str(_menu.status_text()).contains("Cannot save right now:")
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_false()

	# Also verify a write failure (when save_problem is empty) refuses exit cleanly.
	(_main.get_node("BaggageSim") as BaggageSim).routes_stale = false
	var bad_dir := _dir.path_join("dir_blocking_file")
	DirAccess.make_dir_recursive_absolute(bad_dir)
	_save.quick_save_path = bad_dir
	var attempt := func() -> void:
		(_menu.exit_confirm_page.get_node("SaveAndExit") as Button).pressed.emit()
	await (assert_error(attempt).is_push_error(
		"SaveGame: Save failed: cannot replace %s (Failed)" % bad_dir
	))
	assert_array(_scenes).is_empty()
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str(_menu.status_text()).contains("Save failed")
	DirAccess.remove_absolute(bad_dir + ".tmp")
	DirAccess.remove_absolute(bad_dir)


func test_quit_to_desktop_confirm_cancel_exit_without_saving_and_save_and_exit() -> void:
	_menu.open()
	(_main_page().get_node("QuitToDesktop") as Button).pressed.emit()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str((_menu.exit_confirm_page.get_node("Title") as Label).text).is_equal(
		"Quit to desktop?"
	)
	(_menu.exit_confirm_page.get_node("Cancel") as Button).pressed.emit()
	assert_bool(_main_page().visible).is_true()
	assert_bool(_menu.exit_confirm_page.visible).is_false()
	assert_int(_quits).is_equal(0)

	(_main_page().get_node("QuitToDesktop") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).pressed.emit()
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_false()
	assert_int(_quits).is_equal(1)
	assert_array(_scenes).is_empty()

	_menu.open()
	(_main_page().get_node("QuitToDesktop") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("SaveAndExit") as Button).pressed.emit()
	assert_bool(FileAccess.file_exists(SaveSlots.manual_path())).is_true()
	assert_int(_quits).is_equal(2)
	assert_array(_scenes).is_empty()


func test_menu_exit_ends_quit_log_with_quit_menu_reason() -> void:
	var log_dir := SaveTestKit.run_dir("game_menu_exit_quit_log")
	var log_settings := SaveTestKit.run_path("game_menu_exit_quit_log_cfg").replace(".json", ".cfg")
	var recorder := QuitLogRecorder.new()
	recorder.clock = _clock
	recorder.settings_path = log_settings
	recorder.log_dir = log_dir
	_main.add_child(recorder)
	assert_bool(recorder.set_enabled(true)).is_true()
	_menu.quit_log = recorder

	_menu.open()
	(_main_page().get_node("QuitToDesktop") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).pressed.emit()
	assert_bool(recorder.is_recording()).is_false()
	assert_int(_quits).is_equal(1)

	var types := []
	var reasons := []
	var abs_dir := ProjectSettings.globalize_path(log_dir)
	for file_name in DirAccess.get_files_at(abs_dir):
		var text := FileAccess.get_file_as_string("%s/%s" % [abs_dir, file_name])
		for line in text.strip_edges().split("\n", false):
			var rec: Dictionary = JSON.parse_string(line)
			types.append(rec["type"])
			if rec["type"] == "session_end":
				reasons.append(rec["data"]["reason"])
	assert_str(types.back()).is_equal("session_end")
	assert_array(reasons).is_equal([QuitLogRecorder.REASON_QUIT_MENU])

	recorder.stop("test_cleanup")
	recorder.free()
	QuitLog.current = null
	for file_name in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute("%s/%s" % [abs_dir, file_name])
	DirAccess.remove_absolute(abs_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(log_settings))


func test_save_and_exit_is_hidden_when_save_game_is_null() -> void:
	var kit := IncidentPanelKit.new()
	kit.build(self)
	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.quit_game = func() -> void: _quits += 1
	kit.port.add_child(menu)
	menu.open()
	(menu.resume_button().get_parent().get_node("QuitToDesktop") as Button).pressed.emit()
	assert_bool(menu.exit_confirm_page.visible).is_true()
	assert_bool((menu.exit_confirm_page.get_node("SaveAndExit") as Button).visible).is_false()
	assert_bool((menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).visible).is_true()
	(menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).pressed.emit()
	assert_int(_quits).is_equal(1)
	kit.port.free()


func test_new_buttons_confirm_copy_and_refusal_retranslate_live() -> void:
	_menu.feedback_url = "https://example.com/feedback"
	(_main.get_node("BaggageSim") as BaggageSim).routes_stale = true
	_menu.open()
	(_main_page().get_node("MainMenu") as Button).pressed.emit()
	(_menu.exit_confirm_page.get_node("SaveAndExit") as Button).pressed.emit()
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str((_main_page().get_node("SendFeedback") as Button).text).is_equal("Send Feedback")
	assert_str((_main_page().get_node("MainMenu") as Button).text).is_equal("Main Menu")
	assert_str((_main_page().get_node("QuitToDesktop") as Button).text).is_equal("Quit to Desktop")
	assert_str((_menu.exit_confirm_page.get_node("Title") as Label).text).is_equal(
		"Return to main menu?"
	)
	assert_str((_menu.exit_confirm_page.get_node("Body") as Label).text).is_equal(
		"Unsaved progress will be lost."
	)
	assert_str((_menu.exit_confirm_page.get_node("SaveAndExit") as Button).text).is_equal(
		"Save & Exit"
	)
	assert_str((_menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).text).is_equal(
		"Exit without Saving"
	)
	assert_str((_menu.exit_confirm_page.get_node("Cancel") as Button).text).is_equal("Cancel")
	assert_str(_menu.status_text()).is_equal(
		"Cannot save right now: the last build change settles on the next tick"
	)

	_locale_settings().apply_locale("ja", false)
	assert_bool(_menu.exit_confirm_page.visible).is_true()
	assert_str((_main_page().get_node("SendFeedback") as Button).text).is_equal(
		TranslationServer.translate("Send Feedback")
	)
	assert_str((_main_page().get_node("MainMenu") as Button).text).is_equal("メインメニュー")
	assert_str((_main_page().get_node("QuitToDesktop") as Button).text).is_equal("デスクトップへ終了")
	assert_str((_menu.exit_confirm_page.get_node("Title") as Label).text).is_equal("メインメニューに戻りますか？")
	assert_str((_menu.exit_confirm_page.get_node("Body") as Label).text).is_equal(
		"保存していない進行状況は失われます。"
	)
	assert_str((_menu.exit_confirm_page.get_node("SaveAndExit") as Button).text).is_equal("保存して終了")
	assert_str((_menu.exit_confirm_page.get_node("ExitWithoutSaving") as Button).text).is_equal(
		"保存せずに終了"
	)
	assert_str((_menu.exit_confirm_page.get_node("Cancel") as Button).text).is_equal("キャンセル")
	assert_str(_menu.status_text()).is_equal(
		"今は保存できません: the last build change settles on the next tick"
	)
