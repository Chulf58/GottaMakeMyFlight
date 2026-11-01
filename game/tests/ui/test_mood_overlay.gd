class_name TestMoodOverlay
extends GdUnitTestSuite
## The queue and mood floor overlay's toggle (HUD 5/7): the M key and the
## button show and hide it, the choice persists in the HUD settings file, it
## reads the sim only while on, and main.tscn mounts it.

var _path: String
var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("mood_overlay_setting")
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 5), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = Vector2i(3, 3)
	p.stage = Passenger.Stage.CHECKIN_QUEUE
	p.mood = 20


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	_world.free_all()


func _overlay() -> MoodOverlay:
	return _overlay_at(_path)


func _overlay_at(path: String) -> MoodOverlay:
	var overlay := MoodOverlay.new()
	overlay.settings_path = path
	overlay.sim = _world.sim
	add_child(overlay)
	return auto_free(overlay)


func _m_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.physical_keycode = KEY_M
	event.pressed = true
	return event


func _toggle(overlay: MoodOverlay) -> Button:
	return overlay.find_child("MoodToggle", true, false) as Button


func _legend(overlay: MoodOverlay) -> Label:
	return overlay.find_child("MoodLegend", true, false) as Label


func test_the_overlay_is_off_by_default_and_draws_nothing() -> void:
	var overlay := _overlay()
	assert_bool(overlay.is_shown()).is_false()
	assert_bool(_toggle(overlay).button_pressed).is_false()
	assert_bool(_legend(overlay).visible).is_false()
	assert_dict(overlay.tinted_cells()).is_empty()
	overlay.refresh()
	assert_dict(overlay.tinted_cells()).is_empty()
	var tint := overlay.find_child("MoodTint", true, false) as MultiMeshInstance3D
	assert_bool(tint.visible).is_false()
	assert_int(tint.multimesh.instance_count).is_equal(0)


func test_turning_it_on_tints_the_floor_under_a_bad_passenger() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	var cells := overlay.tinted_cells()
	print("tinted cells: %s" % cells)
	assert_float(cells[Vector2i(3, 3)]).is_equal(1.0)
	var tint := overlay.find_child("MoodTint", true, false) as MultiMeshInstance3D
	assert_bool(tint.visible).is_true()
	assert_int(tint.multimesh.instance_count).is_equal(cells.size())
	assert_int(cells.size()).is_equal(5)
	assert_bool(_legend(overlay).visible).is_true()


func test_turning_it_off_clears_the_tint() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	overlay.set_shown(false)
	assert_dict(overlay.tinted_cells()).is_empty()
	var tint := overlay.find_child("MoodTint", true, false) as MultiMeshInstance3D
	assert_int(tint.multimesh.instance_count).is_equal(0)
	assert_bool(_legend(overlay).visible).is_false()
	assert_bool(_toggle(overlay).visible).is_true()


func test_the_button_toggles_the_overlay() -> void:
	var overlay := _overlay()
	_toggle(overlay).button_pressed = true
	assert_bool(overlay.is_shown()).is_true()
	assert_bool(overlay.tinted_cells().is_empty()).is_false()
	_toggle(overlay).button_pressed = false
	assert_bool(overlay.is_shown()).is_false()


func test_the_choice_persists_to_the_next_overlay() -> void:
	_overlay().set_shown(true)
	var second := _overlay()
	assert_bool(second.is_shown()).is_true()
	assert_bool(_toggle(second).button_pressed).is_true()
	assert_bool(second.tinted_cells().is_empty()).is_false()
	second.set_shown(false)
	assert_bool(_overlay().is_shown()).is_false()


func test_the_setting_is_one_key_in_the_hud_section() -> void:
	_overlay().set_shown(true)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_path)).is_equal(OK)
	assert_bool(cfg.get_value("hud", "mood_overlay", false)).is_true()


func test_toggling_keeps_other_keys_in_the_file() -> void:
	var seeded := ConfigFile.new()
	seeded.set_value("hud", "departures_board", false)
	assert_int(seeded.save(_path)).is_equal(OK)
	_overlay().set_shown(true)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_path)).is_equal(OK)
	assert_bool(cfg.get_value("hud", "departures_board", true)).is_false()
	assert_bool(cfg.get_value("hud", "mood_overlay", false)).is_true()


func test_an_unreadable_settings_file_starts_it_off_and_reports_it() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("[hud\nbroken = =\n")
	file.close()
	var read_error := ConfigFile.new().load(_path)
	assert_int(read_error).is_not_equal(OK)
	var made: Array[MoodOverlay] = []
	(
		assert_error(func() -> void: made.append(_overlay()))
		. is_push_error("MoodOverlay: cannot read %s (error %d)" % [_path, read_error])
	)
	assert_bool(made[0].is_shown()).is_false()


func test_a_failed_write_keeps_the_toggle_for_the_session_and_reports_it() -> void:
	var path := SaveTestKit.run_dir("mood_overlay_missing_dir") + "/hud_settings.cfg"
	var write_error := ConfigFile.new().save(path)
	assert_int(write_error).is_not_equal(OK)
	var overlay := _overlay_at(path)
	(
		assert_error(func() -> void: overlay.set_shown(true))
		. is_push_error("MoodOverlay: cannot write %s (error %d)" % [path, write_error])
	)
	assert_bool(overlay.is_shown()).is_true()
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_the_key_toggles_and_a_held_key_does_not_repeat() -> void:
	assert_bool(InputMap.has_action(MoodOverlay.ACTION)).is_true()
	var overlay := _overlay()
	assert_bool(_m_key().is_action_pressed(MoodOverlay.ACTION)).is_true()
	overlay._shortcut_input(_m_key())
	assert_bool(overlay.is_shown()).is_true()
	var held := _m_key()
	held.echo = true
	overlay._shortcut_input(held)
	assert_bool(overlay.is_shown()).is_true()
	overlay._shortcut_input(_m_key())
	assert_bool(overlay.is_shown()).is_false()


func test_a_modified_m_does_not_toggle() -> void:
	var overlay := _overlay()
	var event := _m_key()
	event.ctrl_pressed = true
	overlay._shortcut_input(event)
	assert_bool(overlay.is_shown()).is_false()


func test_the_key_is_free_of_every_other_action() -> void:
	for action in InputMap.get_actions():
		if action == MoodOverlay.ACTION or String(action).begins_with("ui_"):
			continue
		assert_bool(_m_key().is_action_pressed(action)).is_false()


func test_a_shown_overlay_follows_the_sim_as_it_moves_on() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	var p := _world.passenger(_world.sim.passenger_ids()[0])
	p.at = Vector2i(5, 2)
	_world.sim.tick += MoodOverlay.REFRESH_TICKS
	overlay._process(0.0)
	assert_bool(overlay.tinted_cells().has(Vector2i(5, 2))).is_true()
	assert_bool(overlay.tinted_cells().has(Vector2i(3, 3))).is_false()


func test_main_scene_mounts_the_overlay_on_the_passenger_sim() -> void:
	var text := FileAccess.get_file_as_string("res://main/main.tscn")
	assert_bool(text.contains('[node name="MoodOverlay" type="Node3D"')).is_true()
	assert_bool(text.contains('script = ExtResource("42_moodoverlay")')).is_true()
	assert_bool(text.contains('sim = NodePath("../PassengerSim")')).is_true()
