class_name TestLocaleSettings
extends GdUnitTestSuite

const LOCALE_SETTINGS := preload("res://locale/locale_settings.gd")

var _cfg_path := ""
var _dir_before := ""
var _title_dir := ""
var _locale_before := ""
var _pseudo_before := false


func before_test() -> void:
	_cfg_path = SaveTestKit.run_path("locale_settings").replace(".json", ".cfg")
	_title_dir = SaveTestKit.run_dir("test_locale_title")
	_dir_before = SaveSlots.dir
	var settings := _settings()
	_locale_before = settings.current_locale()
	_pseudo_before = TranslationServer.is_pseudolocalization_enabled()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	settings.protected_path = LOCALE_SETTINGS.DEFAULT_SETTINGS_PATH
	settings.settings_path = LOCALE_SETTINGS.DEFAULT_SETTINGS_PATH
	settings.apply_locale("en", false)
	PseudoLocale.disable()


func after_test() -> void:
	if _pseudo_before:
		PseudoLocale.enable()
	else:
		PseudoLocale.disable()
	var settings := _settings()
	settings.protected_path = LOCALE_SETTINGS.DEFAULT_SETTINGS_PATH
	settings.settings_path = LOCALE_SETTINGS.DEFAULT_SETTINGS_PATH
	settings.apply_locale(
		_locale_before if LOCALE_SETTINGS.is_supported(_locale_before) else "en", false
	)
	SaveSlots.dir = _dir_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	var title_abs := ProjectSettings.globalize_path(_title_dir)
	if DirAccess.dir_exists_absolute(title_abs):
		for f in DirAccess.get_files_at(title_abs):
			DirAccess.remove_absolute(title_abs.path_join(f))
		DirAccess.remove_absolute(title_abs)


func _settings() -> LOCALE_SETTINGS:
	return get_node("/root/LocaleSettings") as LOCALE_SETTINGS


func test_os_locale_normalization_covers_core_steam_10_and_chinese_scripts() -> void:
	var cases := {
		"zh-Hans-CN": "zh_CN",
		"zh_CN": "zh_CN",
		"zh_SG": "zh_CN",
		"zh": "zh_CN",
		"zh_TW": "en",
		"zh_HK": "en",
		"zh_MO": "en",
		"zh-Hant": "en",
		"zh-Hant-TW": "en",
		"pt_PT": "pt_BR",
		"pt_BR": "pt_BR",
		"es_419": "es",
		"es_ES": "es",
		"ru_RU": "ru",
		"en_GB": "en",
		"pl_PL": "pl",
		"fr_FR": "fr",
		"de_DE": "de",
		"ja_JP": "ja",
		"ko_KR": "ko",
		"it_IT": "en",
		"unknown": "en",
		"": "en",
	}
	for raw: String in cases:
		assert_str(LOCALE_SETTINGS.normalize_os_locale(raw)).is_equal(cases[raw])


func test_persistence_round_trip_and_script_launch_shield() -> void:
	assert_bool(Hints.launched_by_script(OS.get_cmdline_args())).is_true()
	assert_str(_settings().current_locale()).is_equal("en")
	assert_bool(LOCALE_SETTINGS.save_to_path(_cfg_path, "ja")).is_true()
	assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("ja")
	assert_bool(LOCALE_SETTINGS.save_to_path(_cfg_path, "xx_INVALID")).is_false()
	assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("ja")
	var settings := _settings()
	settings.settings_path = _cfg_path
	assert_bool(settings.apply_locale("ko", false)).is_true()
	assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("ja")
	assert_bool(settings.select_locale("zh_CN")).is_true()
	assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("zh_CN")


func test_fallback_font_order_and_allow_system_fallback_disabled() -> void:
	var base := load(LOCALE_SETTINGS.BASE_FONT_PATH) as FontFile
	var sc := load(LOCALE_SETTINGS.SC_FONT_PATH) as FontFile
	var jp := load(LOCALE_SETTINGS.JP_FONT_PATH) as FontFile
	var kr := load(LOCALE_SETTINGS.KR_FONT_PATH) as FontFile
	for font in [base, sc, jp, kr]:
		assert_object(font).is_not_null()
		assert_bool(font.allow_system_fallback).is_false()
	var settings := _settings()
	settings.apply_locale("zh_CN", false)
	assert_array(base.fallbacks).is_equal([sc, jp, kr])
	settings.apply_locale("ja", false)
	assert_array(base.fallbacks).is_equal([jp, sc, kr])
	settings.apply_locale("ko", false)
	assert_array(base.fallbacks).is_equal([kr, jp, sc])
	settings.apply_locale("en", false)
	assert_array(base.fallbacks).is_equal([sc, jp, kr])


func test_zero_missing_glyphs_across_all_10_endonyms_and_po_catalogs() -> void:
	var settings := _settings()
	var font := CaptionFont.font()
	for code in LOCALE_SETTINGS.codes():
		settings.apply_locale(code, false)
		var endonym := LOCALE_SETTINGS.display_name(code)
		_assert_all_glyphs(font, endonym, "%s endonym" % code)
		if code == "en":
			continue
		var po_path := "res://locale/%s.po" % code
		assert_bool(FileAccess.file_exists(po_path)).is_true()
		var po_text := FileAccess.get_file_as_string(po_path)
		var entries := PotEntries.parse(po_text)
		assert_int(entries.size()).is_greater(30)
		for entry in entries:
			var msgstr := str(entry.get("str", ""))
			if msgstr != "":
				_assert_all_glyphs(font, msgstr, "%s %s" % [code, entry.get("id", "")])


func _assert_all_glyphs(font: Font, text: String, label: String) -> void:
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp <= 32:
			continue
		(
			assert_bool(font.has_char(cp))
			. override_failure_message("Missing glyph U+%04X (%s) in %s" % [cp, char(cp), label])
			. is_true()
		)


func test_language_picker_disables_auto_translate_and_syncs_peers() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var picker_a := LanguagePicker.new()
	var picker_b := LanguagePicker.new(false)
	port.add_child(picker_a)
	port.add_child(picker_b)
	assert_int(picker_a.option_button().auto_translate_mode).is_equal(
		Node.AUTO_TRANSLATE_MODE_DISABLED
	)
	assert_int(picker_a.option_button().get_popup().auto_translate_mode).is_equal(
		Node.AUTO_TRANSLATE_MODE_DISABLED
	)
	assert_str(picker_a.label().text).is_equal("Language")
	assert_object(picker_b.label()).is_null()
	var codes := LOCALE_SETTINGS.codes()
	assert_int(picker_a.option_button().item_count).is_equal(codes.size())
	for i in codes.size():
		assert_str(picker_a.option_button().get_item_text(i)).is_equal(
			LOCALE_SETTINGS.display_name(codes[i])
		)
	var ja_idx := codes.find("ja")
	picker_a.option_button().select(ja_idx)
	picker_a.option_button().item_selected.emit(ja_idx)
	assert_str(_settings().current_locale()).is_equal("ja")
	assert_str(picker_b.selected_code()).is_equal("ja")
	assert_str(picker_a.label().text).is_equal(TranslationServer.translate("Language"))


func test_title_screen_updates_live_across_locales_without_overlap() -> void:
	SaveSlots.dir = _title_dir
	DirAccess.make_dir_recursive_absolute(_title_dir)
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var title := TitleScreen.new()
	title.change_scene = func(_scene: String) -> Error: return OK
	title.quit_game = func() -> void: pass
	port.add_child(title)
	await get_tree().process_frame
	assert_object(title.language_picker).is_not_null()
	assert_bool(title.language_picker.is_visible_in_tree()).is_true()
	var audio_rect := title.button("Audio").get_global_rect()
	var picker_rect := title.language_picker.get_global_rect()
	assert_bool(audio_rect.intersects(picker_rect)).is_false()
	var settings := _settings()
	for code in ["ja", "zh_CN", "ko", "ru", "pl", "en"]:
		settings.apply_locale(code, false)
		assert_str(title.button("NewAirport").text).is_equal(
			TranslationServer.translate("New Airport", "menu")
		)
		assert_str(title.button("Quit").text).is_equal(TranslationServer.translate("Quit", "menu"))
		assert_str(title.language_picker.label().text).is_equal(
			TranslationServer.translate("Language")
		)


func test_game_menu_updates_in_place_preserving_settings_page_and_hold() -> void:
	var kit := IncidentPanelKit.new()
	kit.build(self)
	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.save_game = kit.save
	kit.port.add_child(menu)
	var dialog_events: Array[bool] = []
	menu.dialog_changed.connect(func(open: bool) -> void: dialog_events.append(open))
	menu.open()
	menu.press_settings()
	assert_array(dialog_events).is_equal([true])
	assert_bool(kit.clock.holds.is_holding()).is_true()
	assert_bool(menu.audio_card.visible).is_true()
	assert_bool(menu.language_picker.visible).is_true()
	assert_bool(menu.incidents_switch().get_parent().visible).is_true()
	var settings := _settings()
	settings.apply_locale("ja", false)
	assert_array(dialog_events).is_equal([true])
	assert_bool(kit.clock.holds.is_holding()).is_true()
	assert_bool(menu.audio_card.visible).is_true()
	assert_bool(menu.language_picker.visible).is_true()
	assert_bool(menu.incidents_switch().get_parent().visible).is_true()
	assert_str(menu.incidents_switch().text).is_equal(TranslationServer.translate("Incidents"))
	assert_str(menu.resume_button().text).is_equal(
		TranslationServer.translate("Resume ({key})").format({"key": GameMenu.ESC_KEY})
	)
	assert_str(menu.audio_card.mute_switch().text).is_equal(
		TranslationServer.translate("Mute audio")
	)
	settings.apply_locale("zh_CN", false)
	assert_str(menu.incidents_switch().text).is_equal(TranslationServer.translate("Incidents"))
	assert_str(menu.language_picker.selected_code()).is_equal("zh_CN")
	kit.port.free()


func test_build_menu_live_refresh_preserves_open_category_across_locale_change() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1536, 864)
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	port.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var ops := BuildMenu.category_index("operations")
	menu.press_category(ops)
	assert_int(menu.open_category()).is_equal(ops)
	_settings().apply_locale("ja", false)
	assert_int(menu.open_category()).is_equal(ops)
	assert_bool(menu.is_tray_open()).is_true()
	assert_str(menu.category_button(ops).tooltip_text).is_equal(
		TranslationServer.translate("Operations", "build menu")
	)
	assert_str(menu.card(BuildMode.Tool.DESK).get_child(0).get_node("Name").text).is_equal(
		TranslationServer.translate("Check-in desk", "build menu")
	)
	assert_float(menu.tray().get_global_rect().size.x).is_less_equal(BuildMenu.COLUMN_W + 0.5)


func test_world_views_clear_cache_and_dirty_redraw_on_locale_change() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var links := GateLinksView.new()
	var room_view := RoomView.new()
	port.add_child(links)
	port.add_child(room_view)
	GateLinksView._caption_sizes["probe_cached_text"] = Vector2(42.0, 12.0)
	assert_bool(GateLinksView._caption_sizes.is_empty()).is_false()
	assert_bool(room_view._dirty).is_false()
	_settings().apply_locale("ja", false)
	assert_bool(GateLinksView._caption_sizes.is_empty()).is_true()
	assert_bool(room_view._dirty).is_true()


func test_alert_stack_and_hud_nodes_update_live_on_locale_change() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var alerts := AlertStack.new()
	alerts.settings_path = _cfg_path
	port.add_child(alerts)
	var mood := MoodOverlay.new()
	mood.settings_path = _cfg_path
	port.add_child(mood)
	assert_str(alerts.find_child("AlertHistoryButton", true, false).text).is_equal("Alerts")
	assert_str(mood.find_child("MoodToggle", true, false).text).is_equal("Mood (M)")
	_settings().apply_locale("ja", false)
	assert_str(alerts.find_child("AlertHistoryButton", true, false).text).is_equal(
		TranslationServer.translate("Alerts")
	)
	assert_str(alerts.find_child("AlertHistoryTitle", true, false).text).is_equal(
		TranslationServer.translate("Alert history")
	)
	assert_str(alerts.find_child("AlertCardsToggle", true, false).text).is_equal(
		TranslationServer.translate("Show alert cards")
	)
	assert_str(mood.find_child("MoodToggle", true, false).text).is_equal(
		TranslationServer.translate("Mood ({key})").format({"key": MoodOverlay.HOTKEY})
	)
	assert_str(mood.find_child("ModeMood", true, false).text).is_equal(
		TranslationServer.translate("Mood", "mood overlay mode")
	)


func test_script_launch_shield_blocks_default_and_protected_path_writes() -> void:
	var default_abs := ProjectSettings.globalize_path(LOCALE_SETTINGS.DEFAULT_SETTINGS_PATH)
	var existed := FileAccess.file_exists(default_abs)
	var before_bytes := FileAccess.get_file_as_bytes(default_abs) if existed else PackedByteArray()
	var settings := _settings()
	assert_bool(settings.select_locale("ja")).is_true()
	assert_bool(FileAccess.file_exists(default_abs)).is_equal(existed)
	if existed:
		assert_array(FileAccess.get_file_as_bytes(default_abs)).is_equal(before_bytes)
	settings.protected_path = _cfg_path
	settings.settings_path = _cfg_path
	assert_bool(settings.select_locale("ko")).is_true()
	assert_bool(FileAccess.file_exists(_cfg_path)).is_false()


func test_corrupt_or_unsupported_locale_cfg_fails_loud_and_returns_empty() -> void:
	var corrupt := FileAccess.open(_cfg_path, FileAccess.WRITE)
	corrupt.store_string("[locale\ncode=broken\n")
	corrupt.close()
	await (
		assert_error(
			func() -> void: assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("")
		)
		. is_push_error("LocaleSettings: cannot read %s (error %d)" % [_cfg_path, ERR_PARSE_ERROR])
	)
	var bogus := FileAccess.open(_cfg_path, FileAccess.WRITE)
	bogus.store_string('[locale]\ncode="xx_BOGUS"\n')
	bogus.close()
	await (
		assert_error(
			func() -> void: assert_str(LOCALE_SETTINGS.load_from_path(_cfg_path)).is_equal("")
		)
		. is_push_error("LocaleSettings: unsupported locale 'xx_BOGUS' in %s" % _cfg_path)
	)


func test_title_message_and_game_menu_status_retranslate_live() -> void:
	SaveSlots.dir = _title_dir
	DirAccess.make_dir_recursive_absolute(_title_dir)
	var bad_file := FileAccess.open(SaveSlots.manual_path(), FileAccess.WRITE)
	bad_file.store_string("{not json")
	bad_file.close()
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var title := TitleScreen.new()
	title.change_scene = func(_scene: String) -> Error: return OK
	title.quit_game = func() -> void: pass
	port.add_child(title)
	title.button("Load").pressed.emit()
	title.save_list().button_for(SaveSlots.manual_path()).pressed.emit()
	assert_str(title.message_text()).is_equal("This save file cannot be read.")
	var kit := IncidentPanelKit.new()
	kit.build(self)
	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.save_game = kit.save
	kit.port.add_child(menu)
	menu.open()
	menu._set_status_spec({"kind": &"quit_log_error", "args": {"path": "/tmp/qlog"}})
	assert_str(menu.status_text()).is_equal("Could not start the quit log in /tmp/qlog")
	_settings().apply_locale("ja", false)
	assert_str(title.message_text()).is_equal("このセーブファイルを読み込めませんでした。")
	assert_str(menu.status_text()).is_equal("/tmp/qlog に終了ログを作成できませんでした")
	kit.port.free()
