class_name TestHintsSettings
extends GdUnitTestSuite
## The hints' on/off setting, the Reset hints button, the H key, the file they
## are kept in and the run modes (decision first-time-hints-above-the-build-bar-
## moment-of-need-per-profile-memory, points 4 and 5).

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("hints_settings")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _hints(path := "") -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path if path == "" else path
	add_child(hints)
	return auto_free(hints)


func _h_key(shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_H
	event.physical_keycode = KEY_H
	event.pressed = true
	event.shift_pressed = shift
	return event


func test_hints_start_on_and_the_choice_is_saved() -> void:
	var hints := _hints()
	assert_bool(hints.is_enabled()).is_true()
	hints.set_enabled(false)
	assert_bool(_hints().is_enabled()).is_false()
	assert_bool(HudFlagSetting.load_flag(_path, Hints.SETTING_KEY, true, "test")).is_false()


func test_the_h_key_toggles_hints_and_the_action_is_bound_to_h() -> void:
	assert_bool(InputMap.has_action(Hints.ACTION)).is_true()
	var bound := false
	for event in InputMap.action_get_events(Hints.ACTION):
		bound = bound or (event is InputEventKey and event.physical_keycode == KEY_H)
	assert_bool(bound).is_true()
	var hints := _hints()
	var key := _h_key()
	hints._shortcut_input(key)
	assert_bool(hints.is_enabled()).is_false()
	hints._shortcut_input(key)
	assert_bool(hints.is_enabled()).is_true()


func test_h_with_a_modifier_does_nothing() -> void:
	var hints := _hints()
	hints._shortcut_input(_h_key(true))
	assert_bool(hints.is_enabled()).is_true()


func test_h_does_nothing_while_a_modal_is_open() -> void:
	var hints := _hints()
	hints.modal = func() -> bool: return true
	hints._shortcut_input(_h_key())
	assert_bool(hints.is_enabled()).is_true()


func test_the_toggle_button_follows_the_setting() -> void:
	var hints := _hints()
	var button := hints.toggle_button()
	assert_bool(button.button_pressed).is_true()
	button.button_pressed = false
	assert_bool(hints.is_enabled()).is_false()
	hints.set_enabled(true)
	assert_bool(button.button_pressed).is_true()


func test_the_settings_row_is_visible_with_a_reset_button_beside_the_toggle() -> void:
	var hints := _hints()
	assert_bool(hints.settings_row().visible).is_true()
	assert_str(hints.toggle_button().text).contains("H")
	assert_str(hints.reset_button().text).is_equal("Reset hints")
	assert_object(hints.reset_button().get_parent()).is_same(hints.toggle_button().get_parent())


func test_the_reset_button_forgets_what_was_seen() -> void:
	var hints := _hints()
	hints._mark_seen(HintRules.TOILET)
	assert_bool(_hints().is_seen(HintRules.TOILET)).is_true()
	hints.reset_button().pressed.emit()
	assert_bool(hints.is_seen(HintRules.TOILET)).is_false()
	assert_bool(_hints().is_seen(HintRules.TOILET)).is_false()


func test_the_seen_memory_and_the_setting_share_one_file_beside_other_keys() -> void:
	HudFlagSetting.save_flag(_path, "alert_cards", false, "test")
	var hints := _hints()
	hints._mark_seen(HintRules.FOOD)
	hints.set_enabled(false)
	assert_bool(HudFlagSetting.load_flag(_path, "alert_cards", true, "test")).is_false()
	assert_bool(HudFlagSetting.load_flag(_path, "hint_seen_food", false, "test")).is_true()


func test_the_mode_is_off_in_a_test_or_probe_and_in_a_playtest() -> void:
	var none := PackedStringArray()
	assert_int(Hints.mode_for(false, false, false, none, "")).is_equal(Hints.Mode.OFF)
	assert_int(Hints.mode_for(true, true, false, none, "")).is_equal(Hints.Mode.OFF)
	assert_int(Hints.mode_for(true, false, false, none, "")).is_equal(Hints.Mode.PROFILE)


func test_a_script_run_that_makes_the_game_scene_current_is_off() -> void:
	# intro_dialogue_plate_probe.gd changes scene to main.tscn from an -s script.
	var none := PackedStringArray()
	assert_int(Hints.mode_for(true, false, true, none, "")).is_equal(Hints.Mode.OFF)
	assert_int(Hints.mode_for(true, false, false, none, "")).is_equal(Hints.Mode.PROFILE)
	var args := PackedStringArray(["--hints"])
	assert_int(Hints.mode_for(true, false, true, args, "")).is_equal(Hints.Mode.ISOLATED)


func test_script_runs_are_told_from_the_engine_arguments() -> void:
	assert_bool(Hints.launched_by_script(PackedStringArray(["-s", "res://spike/x.gd"]))).is_true()
	assert_bool(Hints.launched_by_script(PackedStringArray(["--script", "x.gd"]))).is_true()
	assert_bool(Hints.launched_by_script(PackedStringArray(["--path", "game"]))).is_false()
	assert_bool(Hints.launched_by_script(PackedStringArray())).is_false()


func test_the_explicit_switch_turns_hints_on_with_isolated_memory() -> void:
	var args := PackedStringArray(["--hints"])
	assert_int(Hints.mode_for(false, false, false, args, "")).is_equal(Hints.Mode.ISOLATED)
	assert_int(Hints.mode_for(true, true, false, args, "")).is_equal(Hints.Mode.ISOLATED)
	assert_int(Hints.mode_for(false, true, false, PackedStringArray(), "1")).is_equal(
		Hints.Mode.ISOLATED
	)
	assert_int(Hints.mode_for(false, true, false, PackedStringArray(), "0")).is_equal(
		Hints.Mode.OFF
	)


func test_isolated_memory_never_touches_the_profile_file() -> void:
	assert_str(Hints.ISOLATED_PATH).is_not_equal(HudFlagSetting.PATH)
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.ISOLATED
	hints.settings_path = _path
	add_child(hints)
	auto_free(hints)
	hints._mark_seen(HintRules.FOOD)
	assert_bool(hints.is_seen(HintRules.FOOD)).is_true()
	assert_str(hints.memory_path()).is_equal(_path)
	var plain := Hints.new()
	plain.forced_mode = Hints.Mode.ISOLATED
	add_child(plain)
	auto_free(plain)
	assert_str(plain.memory_path()).is_equal(Hints.ISOLATED_PATH)
	DirAccess.remove_absolute(Hints.ISOLATED_PATH)
