class_name TestMoodOverlayModes
extends GdUnitTestSuite
## The mood overlay's mode buttons (decision crowd-need-display-mood-overlay-
## gains-hunger-toilet-and-bore): Mood, Hunger, Toilet and Boredom tint the
## floor for their own need, the last mode is kept, and while a need mode is on
## every need icon hides.

var _path: String
var _views_path: String
var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("mood_overlay_modes")
	_views_path = SaveTestKit.run_path("mood_overlay_modes_icons")
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 5), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hungry_passenger(Vector2i(3, 3))


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_views_path)
	if is_instance_valid(_views):
		_views.free()
	_world.free_all()


## A passenger waiting at a gate on `cell`, hungry and in no other need.
func _hungry_passenger(cell: Vector2i) -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = cell
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _world.sim.tick
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = 0
	p.boredom = 0


func _overlay() -> MoodOverlay:
	var overlay := MoodOverlay.new()
	overlay.settings_path = _path
	overlay.sim = _world.sim
	add_child(overlay)
	return auto_free(overlay)


func _button(overlay: MoodOverlay, mode_name: String) -> Button:
	return overlay.find_child("Mode" + mode_name, true, false) as Button


func _tinted(overlay: MoodOverlay, mode: MoodTint.Mode) -> int:
	overlay.set_mode(mode)
	var count := 0
	for cell: Vector2i in overlay.tinted_cells():
		if overlay.tinted_cells()[cell] > 0.0:
			count += 1
	print("mode %d tints %d cells" % [mode, count])
	return count


func _visible_icons() -> int:
	var count := 0
	for id in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		for sprite_name in NeedIcons.SPRITES:
			if (node.get_node(sprite_name) as Sprite3D).visible:
				count += 1
	return count


func _drawn_views(overlay: MoodOverlay) -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.mood_overlay = overlay
	add_child(_views)
	_world.step()
	_views.draw()


func test_it_opens_in_mood_mode_with_four_buttons() -> void:
	var overlay := _overlay()
	assert_int(overlay.mode()).is_equal(MoodTint.Mode.MOOD)
	for mode_name in ["Mood", "Hunger", "Toilet", "Boredom"]:
		assert_object(_button(overlay, mode_name)).is_not_null()
	assert_bool(_button(overlay, "Mood").button_pressed).is_true()


func test_switching_modes_changes_which_cells_tint() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	var mood := _tinted(overlay, MoodTint.Mode.MOOD)
	var hunger := _tinted(overlay, MoodTint.Mode.HUNGER)
	var toilet := _tinted(overlay, MoodTint.Mode.TOILET)
	var boredom := _tinted(overlay, MoodTint.Mode.BOREDOM)
	assert_int(hunger).is_greater(0)
	assert_int(toilet).is_equal(0)
	assert_int(boredom).is_equal(0)
	assert_int(mood).is_equal(0)


func test_a_button_picks_the_mode() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	_button(overlay, "Hunger").button_pressed = true
	assert_int(overlay.mode()).is_equal(MoodTint.Mode.HUNGER)
	assert_bool(_button(overlay, "Mood").button_pressed).is_false()
	assert_int(overlay.tinted_cells().size()).is_greater(0)


func test_the_mode_drives_the_legend_text() -> void:
	var overlay := _overlay()
	var legend := overlay.find_child("MoodLegend", true, false) as Label
	var texts := {}
	for mode in MoodTint.Mode.values():
		overlay.set_mode(mode)
		texts[legend.text] = true
	assert_int(texts.size()).is_equal(4)


func test_the_last_mode_is_kept_for_the_next_overlay() -> void:
	var first := _overlay()
	first.set_shown(true)
	first.set_mode(MoodTint.Mode.TOILET)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_path)).is_equal(OK)
	assert_int(cfg.get_value("hud", "mood_overlay_mode", -1)).is_equal(MoodTint.Mode.TOILET)
	var second := _overlay()
	assert_int(second.mode()).is_equal(MoodTint.Mode.TOILET)
	assert_bool(_button(second, "Toilet").button_pressed).is_true()


func test_a_saved_mode_out_of_range_opens_in_mood_mode() -> void:
	HudFlagSetting.save_int(_path, "mood_overlay_mode", 9, "test")
	assert_int(_overlay().mode()).is_equal(MoodTint.Mode.MOOD)


func test_need_icons_hide_in_need_modes_and_show_in_mood_mode_and_when_off() -> void:
	_world.free_all()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	var overlay := _overlay()
	_drawn_views(overlay)
	var off := _visible_icons()
	overlay.set_shown(true)
	_views.draw()
	var mood := _visible_icons()
	overlay.set_mode(MoodTint.Mode.HUNGER)
	_views.draw()
	var hunger := _visible_icons()
	overlay.set_mode(MoodTint.Mode.BOREDOM)
	_views.draw()
	var boredom := _visible_icons()
	overlay.set_mode(MoodTint.Mode.MOOD)
	_views.draw()
	var back := _visible_icons()
	overlay.set_mode(MoodTint.Mode.TOILET)
	overlay.set_shown(false)
	_views.draw()
	var closed := _visible_icons()
	print(
		(
			"icons: off %d, mood %d, hunger %d, boredom %d, mood again %d, closed in toilet %d"
			% [off, mood, hunger, boredom, back, closed]
		)
	)
	assert_int(off).is_greater(0)
	assert_int(mood).is_equal(off)
	assert_int(hunger).is_equal(0)
	assert_int(boredom).is_equal(0)
	assert_int(back).is_equal(off)
	assert_int(closed).is_equal(off)


func test_main_scene_gives_the_views_the_overlay() -> void:
	var text := FileAccess.get_file_as_string("res://main/main.tscn")
	assert_bool(text.contains('mood_overlay = NodePath("../MoodOverlay")')).is_true()
