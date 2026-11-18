class_name TestTitleScreen
extends GdUnitTestSuite
## The title screen (decision title-menu-with-continue-new-airport-load-and-quit-
## autosave): Continue (the latest save, greyed when none), New Airport, Load and
## Quit. The scene change and the quit are swapped for recorders, so no case
## leaves this test run's scene. The saves live in a folder of this run's own.

var _dir := SaveTestKit.run_dir("test_title_screen")
var _dir_before := ""
var _port: SubViewport
var _title: TitleScreen
var _scenes: Array[String] = []
var _quits := 0


func before_test() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	DirAccess.make_dir_recursive_absolute(_dir)
	GameBoot.load_path = ""
	GameBoot.new_airport = false
	GameBoot.refusal = ""
	_scenes.clear()
	_quits = 0
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)


func after_test() -> void:
	_port.free()
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before
	GameBoot.load_path = ""
	GameBoot.new_airport = false
	GameBoot.refusal = ""


func _write(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()


func _build() -> TitleScreen:
	_title = TitleScreen.new()
	_title.change_scene = func(scene: String) -> Error:
		_scenes.append(scene)
		return OK
	_title.quit_game = func() -> void: _quits += 1
	_port.add_child(_title)
	return _title


func test_the_project_boots_into_the_title_scene() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(
		GameBoot.TITLE_SCENE
	)
	var scene: Node = (load(GameBoot.TITLE_SCENE) as PackedScene).instantiate()
	assert_object(scene).is_instanceof(TitleScreen)
	scene.free()


func test_the_main_page_holds_continue_new_airport_load_and_quit_in_order() -> void:
	_build()
	var names: Array[String] = []
	for child in _title.main_page().get_children():
		if child.visible:
			names.append(child.name)
	assert_array(names).is_equal(["Continue", "NewAirport", "Load", "Quit"])


func test_with_no_save_continue_and_load_are_greyed() -> void:
	_build()
	assert_bool(_title.button("Continue").disabled).is_true()
	assert_bool(_title.button("Load").disabled).is_true()
	assert_bool(_title.button("NewAirport").disabled).is_false()
	_title.press_continue()
	assert_array(_scenes).is_empty()


func test_continue_loads_the_latest_save_through_main() -> void:
	_write(SaveSlots.autosave_paths()[0])
	_build()
	assert_bool(_title.button("Continue").disabled).is_false()
	_title.button("Continue").pressed.emit()
	print("continue: scenes=%s load_path=%s" % [_scenes, GameBoot.load_path])
	assert_array(_scenes).is_equal([GameBoot.MAIN_SCENE])
	assert_str(GameBoot.load_path).is_equal(SaveSlots.autosave_paths()[0])


func test_new_airport_starts_main_with_nothing_to_load() -> void:
	GameBoot.load_path = "left over"
	_build()
	_title.button("NewAirport").pressed.emit()
	assert_array(_scenes).is_equal([GameBoot.MAIN_SCENE])
	assert_str(GameBoot.load_path).is_equal("")


func test_load_lists_every_save_and_a_pick_loads_it_through_main() -> void:
	_write(SaveSlots.manual_path())
	_write(SaveSlots.autosave_paths()[1])
	_build()
	_title.button("Load").pressed.emit()
	assert_bool(_title.main_page().visible).is_false()
	var list := _title.save_list()
	assert_bool(list.is_visible_in_tree()).is_true()
	var paths := list.paths()
	print("listed: %s" % [paths])
	assert_int(paths.size()).is_equal(2)
	assert_array(paths).contains([SaveSlots.manual_path(), SaveSlots.autosave_paths()[1]])
	list.button_for(SaveSlots.manual_path()).pressed.emit()
	assert_array(_scenes).is_equal([GameBoot.MAIN_SCENE])
	assert_str(GameBoot.load_path).is_equal(SaveSlots.manual_path())


func test_back_from_the_load_page_shows_the_main_page() -> void:
	_write(SaveSlots.manual_path())
	_build()
	_title.press_load()
	_title.press_back()
	assert_bool(_title.main_page().visible).is_true()
	assert_bool(_title.save_list().is_visible_in_tree()).is_false()


func test_quit_quits() -> void:
	_build()
	_title.button("Quit").pressed.emit()
	assert_int(_quits).is_equal(1)


func test_a_refused_boot_load_shows_its_message_once() -> void:
	GameBoot.refusal = "Load failed: the save is version 1"
	_build()
	print("message: '%s'" % _title.message_text())
	assert_str(_title.message_text()).is_equal("Load failed: the save is version 1")
	assert_str(GameBoot.refusal).is_equal("")


func test_without_a_refusal_no_message_shows() -> void:
	_build()
	assert_str(_title.message_text()).is_equal("")


## The wishlist link has no store page yet: its button stays hidden while the
## URL is the empty placeholder.
func test_the_wishlist_button_hides_while_the_url_is_a_placeholder() -> void:
	_build()
	assert_str(TitleScreen.WISHLIST_URL).is_equal("")
	assert_bool(_title.button("Wishlist").visible).is_false()


func test_every_label_and_button_is_routed_through_tr() -> void:
	_write(SaveSlots.manual_path())
	PseudoLocale.enable(0.4)
	_build()
	var texts: Array[String] = []
	for name in ["Continue", "NewAirport", "Load", "Quit", "Back"]:
		texts.append(_title.button(name).text)
	texts.append(_title.save_list().button_for(SaveSlots.manual_path()).text)
	print("title texts: %s" % [texts])
	PseudoLocale.disable()
	for text in texts:
		assert_str(text).starts_with("[")


## The short labels carry the "menu" context, as the Save and Load labels of the
## game menu do, so a translator can tell them from the same words elsewhere.
## A translation with one entry per label under "menu" and a different one with
## no context: only the "menu" one may reach the buttons.
func test_the_short_labels_are_translated_with_the_menu_context() -> void:
	var labels := {
		"Continue": "Continue", "NewAirport": "New Airport", "Load": "Load", "Quit": "Quit"
	}
	labels["Wishlist"] = "Wishlist"
	labels["Back"] = "Back"
	var translation := Translation.new()
	translation.locale = "en"
	for source: String in labels.values():
		translation.add_message(source, "menu:" + source, "menu")
		translation.add_message(source, "plain:" + source)
	var locale_before := TranslationServer.get_locale()
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("en")
	_write(SaveSlots.manual_path())
	_build()
	var texts := {}
	for name: String in labels:
		texts[name] = _title.button(name).text
	TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(locale_before)
	print("title texts: %s" % [texts])
	for name: String in labels:
		assert_str(texts[name]).is_equal("menu:" + labels[name])
