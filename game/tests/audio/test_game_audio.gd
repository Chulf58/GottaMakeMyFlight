class_name TestGameAudio
extends GdUnitTestSuite
## The D5 demo audio floor: Master/Ambience/SFX bus creation and routing,
## linear-to-dB volume and mute state on AudioServer, isolated ConfigFile
## persistence and script-run shielding, gameplay ambience loop start/stop,
## UI/build/cash SFX triggers without per-passenger spam or leaks, and live
## slider/mute two-way sync (including drag_ended single-write) in both
## GameMenu and TitleScreen.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""
var _shield_path := ""
var _title_dir := ""
var _dir_before := ""


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("audio_settings").replace(".json", ".cfg")
	_shield_path = SaveTestKit.run_path("audio_shielded").replace(".json", ".cfg")
	_title_dir = SaveTestKit.run_dir("test_audio_title")
	_dir_before = SaveSlots.dir
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_shield_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	if _audio != null:
		_audio.reset_for_test()
	SaveSlots.dir = _dir_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_shield_path))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_title_dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_title_dir))


func test_buses_exist_and_route_to_master() -> void:
	var master_idx := AudioServer.get_bus_index(&"Master")
	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	assert_int(master_idx).is_equal(0)
	assert_int(amb_idx).is_greater(0)
	assert_int(sfx_idx).is_greater(0)
	assert_str(String(AudioServer.get_bus_send(amb_idx))).is_equal("Master")
	assert_str(String(AudioServer.get_bus_send(sfx_idx))).is_equal("Master")


func test_linear_volume_and_mute_drive_audio_server_buses() -> void:
	var master_idx := AudioServer.get_bus_index(&"Master")
	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	var sfx_idx := AudioServer.get_bus_index(&"SFX")

	_audio.set_master_volume(0.5)
	_audio.set_ambience_volume(0.25)
	_audio.set_sfx_volume(0.0)
	assert_float(AudioServer.get_bus_volume_db(master_idx)).is_equal_approx(linear_to_db(0.5), 0.05)
	assert_float(AudioServer.get_bus_volume_db(amb_idx)).is_equal_approx(linear_to_db(0.25), 0.05)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_false()
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_false()
	assert_bool(AudioServer.is_bus_mute(sfx_idx)).is_true()

	_audio.set_muted(true)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_true()
	assert_float(_audio.master_volume).is_equal_approx(0.5, 0.001)
	_audio.set_muted(false)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_false()


func test_settings_persist_to_isolated_config_and_shield_protected_path() -> void:
	_audio.set_master_volume(0.42)
	_audio.set_ambience_volume(0.35)
	_audio.set_sfx_volume(0.64)
	_audio.set_muted(true)
	assert_bool(FileAccess.file_exists(_cfg_path)).is_true()

	_audio.master_volume = 1.0
	_audio.ambience_volume = 1.0
	_audio.sfx_volume = 1.0
	_audio.muted = false
	_audio.load_settings(_cfg_path)
	assert_float(_audio.master_volume).is_equal_approx(0.42, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.35, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.64, 0.001)
	assert_bool(_audio.muted).is_true()

	# Shield check: pointing protected_path + settings_path at _shield_path drops writes in -s runs.
	_audio.protected_path = _shield_path
	_audio.set_settings_path(_shield_path)
	_audio.set_master_volume(0.15)
	assert_bool(FileAccess.file_exists(_shield_path)).is_false()


func test_ambience_loops_only_while_gameplay_is_in_tree() -> void:
	assert_bool(_audio.is_ambience_playing()).is_false()
	var mode := BuildMode.new()
	add_child(mode)
	assert_bool(_audio.is_ambience_playing()).is_true()
	var amb_player := _audio.get_node("AmbiencePlayer") as AudioStreamPlayer
	var wav := amb_player.stream as AudioStreamWAV
	assert_object(wav).is_not_null()
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_equal(308700)
	mode.free()
	assert_bool(_audio.is_ambience_playing()).is_false()


func test_ui_button_build_flight_departure_and_lump_cash_events_trigger_sfx() -> void:
	var btn := Button.new()
	add_child(btn)
	btn.pressed.emit()
	assert_str(String(_audio.last_sfx())).is_equal("ui_click")
	assert_int(_audio.sfx_count(&"ui_click")).is_equal(1)
	btn.free()

	var mode := BuildMode.new()
	add_child(mode)
	var place_edit := BuildEdit.paint_floor(Vector2i(2, 2), BuildGrid.FLOOR_TILE, 1)
	mode.grid.edit_applied.emit(place_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_place")
	var remove_edit := BuildEdit.remove_floor(Vector2i(2, 2))
	mode.grid.edit_applied.emit(remove_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_remove")
	mode.grid.edit_refused.emit(place_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_refuse")
	mode.free()

	var finances := Finances.new()
	add_child(finances)
	# Opening budget, per-passenger boarding FEES and cafe SHOP ticks must not chime.
	finances.wallet.credit(25, Wallet.Category.FEES)
	finances.wallet.credit(8, Wallet.Category.SHOP)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(0)
	# Lump-sum signing bonus rings cash_chime once.
	finances.wallet.credit(250, Wallet.Category.SIGNING_BONUS)
	assert_str(String(_audio.last_sfx())).is_equal("cash_chime")
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(1)
	finances.free()

	# Flight departure completion also rings cash_chime (when off cooldown).
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	var flights := FlightSim.new()
	add_child(flights)
	flights.state_changed.emit("GMF101", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(0)
	flights.state_changed.emit("GMF101", FlightSim.State.DEPARTED)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(1)
	flights.free()


func test_game_menu_settings_sliders_init_from_saved_state_and_save_once_on_drag_end() -> void:
	_audio.set_master_volume(0.30)
	_audio.set_ambience_volume(0.45)
	_audio.set_sfx_volume(0.65)
	_audio.set_muted(true)
	var saves_before := _audio.save_count

	var kit := IncidentPanelKit.new()
	kit.build(self)
	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.save_game = kit.save
	kit.port.add_child(menu)
	assert_bool(menu.open()).is_true()
	assert_bool(menu.audio_card.visible).is_false()
	menu.press_settings()
	assert_bool(menu.audio_card.visible).is_true()

	# Reverse sync: controls initialize to the pre-existing non-default values.
	assert_float(menu.audio_card.master_slider().value).is_equal_approx(30.0, 0.01)
	assert_float(menu.audio_card.ambience_slider().value).is_equal_approx(45.0, 0.01)
	assert_float(menu.audio_card.sfx_slider().value).is_equal_approx(65.0, 0.01)
	assert_bool(menu.audio_card.mute_switch().button_pressed).is_true()
	assert_int(_audio.save_count).is_equal(saves_before)

	# Dragging updates AudioServer live without writing disk until drag_ended.
	var master_idx := AudioServer.get_bus_index(&"Master")
	var slider := menu.audio_card.master_slider()
	slider.drag_started.emit()
	slider.value = 40.0
	slider.value = 55.0
	slider.value = 70.0
	assert_float(AudioServer.get_bus_volume_db(master_idx)).is_equal_approx(
		linear_to_db(0.70), 0.05
	)
	assert_int(_audio.save_count).is_equal(saves_before)
	slider.drag_ended.emit(true)
	assert_int(_audio.save_count).is_equal(saves_before + 1)

	menu.audio_card.ambience_slider().value = 50.0
	menu.audio_card.sfx_slider().value = 90.0
	menu.audio_card.mute_switch().button_pressed = false
	menu.press_back()
	assert_bool(menu.audio_card.visible).is_false()
	kit.port.free()

	_audio.load_settings(_cfg_path)
	assert_float(_audio.master_volume).is_equal_approx(0.70, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.50, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.90, 0.001)
	assert_bool(_audio.muted).is_false()


func test_title_screen_audio_card_inits_from_saved_state_toggles_and_syncs() -> void:
	_audio.set_master_volume(0.25)
	_audio.set_ambience_volume(0.55)
	_audio.set_sfx_volume(0.85)
	_audio.set_muted(true)

	SaveSlots.dir = _title_dir
	DirAccess.make_dir_recursive_absolute(_title_dir)
	var port := SubViewport.new()
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var title := TitleScreen.new()
	title.change_scene = func(_scene: String) -> Error: return OK
	title.quit_game = func() -> void: pass
	port.add_child(title)

	assert_object(title.button("Audio")).is_not_null()
	assert_bool(title.audio_card.visible).is_false()
	title.button("Audio").pressed.emit()
	assert_bool(title.audio_card.visible).is_true()

	# Reverse sync: sliders and mute reflect pre-existing GameAudio state on open.
	assert_float(title.audio_card.master_slider().value).is_equal_approx(25.0, 0.01)
	assert_float(title.audio_card.ambience_slider().value).is_equal_approx(55.0, 0.01)
	assert_float(title.audio_card.sfx_slider().value).is_equal_approx(85.0, 0.01)
	assert_bool(title.audio_card.mute_switch().button_pressed).is_true()

	title.audio_card.master_slider().value = 60.0
	title.audio_card.ambience_slider().value = 20.0
	title.audio_card.sfx_slider().value = 75.0
	title.audio_card.mute_switch().button_pressed = false
	assert_float(_audio.master_volume).is_equal_approx(0.60, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.20, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.75, 0.001)
	assert_bool(_audio.muted).is_false()

	title.press_load()
	assert_bool(title.audio_card.visible).is_false()
	assert_bool(title.button("Audio").is_visible_in_tree()).is_false()
	title.press_back()
	assert_bool(title.button("Audio").is_visible_in_tree()).is_true()
	port.free()
