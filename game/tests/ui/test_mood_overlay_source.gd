class_name TestMoodOverlaySource
extends GdUnitTestSuite
## The mood overlay's source (HUD 5/7): a missing PassengerSim or grid is
## reported and blocks the overlay instead of silently drawing nothing, and a
## grid edit made while the sim is paused is drawn on the next frame.

var _path: String
var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("mood_overlay_source_setting")
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


func _overlay_on(sim: PassengerSim) -> MoodOverlay:
	var overlay := MoodOverlay.new()
	overlay.settings_path = _path
	overlay.sim = sim
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


func _assert_blocked(overlay: MoodOverlay) -> void:
	assert_bool(_toggle(overlay).disabled).is_true()
	overlay.set_shown(true)
	assert_bool(overlay.is_shown()).is_false()
	assert_bool(_toggle(overlay).button_pressed).is_false()
	var legend := overlay.find_child("MoodLegend", true, false) as Label
	assert_bool(legend.visible).is_false()
	overlay._shortcut_input(_m_key())
	assert_bool(overlay.is_shown()).is_false()
	overlay.refresh()
	assert_dict(overlay.tinted_cells()).is_empty()
	assert_bool(FileAccess.file_exists(_path)).is_false()


func test_without_a_sim_it_reports_it_and_cannot_be_turned_on() -> void:
	var made: Array[MoodOverlay] = []
	(
		assert_error(func() -> void: made.append(_overlay_on(null)))
		. is_push_error("MoodOverlay: sim (PassengerSim) is not set, the overlay is disabled")
	)
	_assert_blocked(made[0])


func test_without_a_grid_it_reports_it_and_cannot_be_turned_on() -> void:
	var gridless := auto_free(PassengerSim.new()) as PassengerSim
	var made: Array[MoodOverlay] = []
	(
		assert_error(func() -> void: made.append(_overlay_on(gridless)))
		. is_push_error(
			"MoodOverlay: sim has no grid yet, the overlay is disabled until it has one"
		)
	)
	_assert_blocked(made[0])


func test_a_grid_that_appears_after_ready_enables_the_overlay() -> void:
	var gridless := auto_free(PassengerSim.new()) as PassengerSim
	var made: Array[MoodOverlay] = []
	(
		assert_error(func() -> void: made.append(_overlay_on(gridless)))
		. is_push_error(
			"MoodOverlay: sim has no grid yet, the overlay is disabled until it has one"
		)
	)
	var overlay := made[0]
	assert_bool(_toggle(overlay).disabled).is_true()
	overlay.sim = _world.sim
	overlay._process(0.0)
	assert_bool(_toggle(overlay).disabled).is_false()
	overlay.set_shown(true)
	assert_bool(overlay.is_shown()).is_true()
	assert_bool(overlay.tinted_cells().has(Vector2i(3, 3))).is_true()


func test_a_grid_edit_while_the_sim_is_paused_redraws_on_the_next_frame() -> void:
	var overlay := _overlay_on(_world.sim)
	overlay.set_shown(true)
	var neighbour := Vector2i(4, 3)
	assert_bool(overlay.tinted_cells().has(neighbour)).is_true()
	var tick_before := _world.sim.tick
	var result := _world.grid.apply(BuildEdit.remove_floor(neighbour))
	assert_bool(result.ok).is_true()
	assert_bool(overlay.tinted_cells().has(neighbour)).is_true()
	overlay._process(0.0)
	assert_int(_world.sim.tick).is_equal(tick_before)
	assert_bool(overlay.tinted_cells().has(neighbour)).is_false()
	assert_bool(overlay.tinted_cells().has(Vector2i(3, 3))).is_true()


func test_a_hidden_overlay_ignores_a_grid_edit() -> void:
	var overlay := _overlay_on(_world.sim)
	_world.grid.apply(BuildEdit.remove_floor(Vector2i(4, 3)))
	overlay._process(0.0)
	assert_dict(overlay.tinted_cells()).is_empty()
