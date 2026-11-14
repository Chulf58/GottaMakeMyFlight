class_name TestMoodOverlayModes
extends GdUnitTestSuite
## The mood overlay's mode buttons (decision crowd-need-display-mood-overlay-
## gains-hunger-toilet-and-bore): Mood, Hunger, Toilet and Boredom tint the
## floor for their own need, the last mode is kept, and the need icons show only
## in a need mode, only that need's (decision need-icons-show-only-in-the-mood-
## overlay-need-modes-n-key-removed).

var _path: String
var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("mood_overlay_modes")
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 5), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hungry_passenger(Vector2i(3, 3))


func after_test() -> void:
	DirAccess.remove_absolute(_path)
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


## The kinds of need icon `node` shows now, need -> count.
func _icons_by_need(node: Node3D) -> Dictionary:
	var out := {}
	var kinds: Array = node.get_meta(&"need_kinds", [])
	for i in kinds.size():
		if (node.get_node(NeedIcons.SPRITES[i]) as Sprite3D).visible:
			out[kinds[i]] = out.get(kinds[i], 0) + 1
	return out


func _drawn_views(overlay: MoodOverlay) -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.mood_overlay = overlay
	add_child(_views)
	_world.step()
	_views.draw()


func test_it_opens_in_mood_mode_with_five_buttons() -> void:
	var overlay := _overlay()
	assert_int(overlay.mode()).is_equal(MoodTint.Mode.MOOD)
	for mode_name in ["Mood", "Hunger", "Toilet", "Boredom", "Late"]:
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
	# One line per mode; Late (calm view) made it five.
	assert_int(texts.size()).is_equal(MoodTint.Mode.size())
	assert_int(texts.size()).is_equal(5)


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


## Every mode button in turn picks its mode, the last one pressed (Late) is
## saved, and the next overlay opens in it with its button down.
func test_cycling_the_buttons_to_late_keeps_late_for_the_next_overlay() -> void:
	var first := _overlay()
	first.set_shown(true)
	for mode: MoodTint.Mode in MoodTint.Mode.values():
		_button(first, MoodOverlay.MODE_NAMES[mode]).button_pressed = true
		assert_int(first.mode()).is_equal(mode)
	assert_int(first.mode()).is_equal(MoodTint.Mode.LATE)
	assert_bool(first.shows_late()).is_true()
	assert_bool(first.shows_wishes()).is_false()
	assert_int(first.shown_need()).is_equal(MoodOverlay.NO_NEED)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_path)).is_equal(OK)
	assert_int(cfg.get_value("hud", "mood_overlay_mode", -1)).is_equal(MoodTint.Mode.LATE)
	var second := _overlay()
	assert_int(second.mode()).is_equal(MoodTint.Mode.LATE)
	assert_bool(_button(second, "Late").button_pressed).is_true()


## Boredom mode shows the wishes and Late mode the late bubbles, only while the
## overlay is on.
func test_the_bubble_modes_hold_only_while_the_overlay_is_on() -> void:
	var overlay := _overlay()
	overlay.set_mode(MoodTint.Mode.BOREDOM)
	assert_bool(overlay.shows_wishes()).is_false()
	overlay.set_shown(true)
	assert_bool(overlay.shows_wishes()).is_true()
	assert_bool(overlay.shows_late()).is_false()
	overlay.set_mode(MoodTint.Mode.LATE)
	assert_bool(overlay.shows_wishes()).is_false()
	assert_bool(overlay.shows_late()).is_true()
	overlay.set_shown(false)
	assert_bool(overlay.shows_late()).is_false()


## Late mode tints only where a late passenger stands, soft amber, never red.
func test_late_mode_tints_only_the_late_passengers_cells() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	# The control: the hungry passenger is not late, so nothing tints yet.
	assert_int(_tinted(overlay, MoodTint.Mode.LATE)).is_equal(0)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = Vector2i(5, 2)
	p.stage = Passenger.Stage.STANDING
	p.late = true
	overlay.refresh()
	var cells := overlay.tinted_cells()
	print("late mode cells %s" % [cells])
	assert_float(cells.get(Vector2i(5, 2), 0.0)).is_equal(1.0)
	assert_bool(cells.has(Vector2i(3, 3))).is_false()
	var colour := MoodTint.color_of(1.0, MoodTint.Mode.LATE)
	assert_float(colour.r).is_greater(colour.b)
	assert_float(colour.g).is_greater(MoodTint.BAD_COLOR.g)


func test_a_saved_mode_out_of_range_opens_in_mood_mode() -> void:
	HudFlagSetting.save_int(_path, "mood_overlay_mode", 9, "test")
	assert_int(_overlay().mode()).is_equal(MoodTint.Mode.MOOD)


func test_need_icons_show_only_in_the_matching_need_mode() -> void:
	_world.free_all()
	var grid := BuildGrid.new()
	NeedFacilityKit.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	var overlay := _overlay()
	_drawn_views(overlay)
	var node := _views.node_for(p.id)
	var kinds: Array = node.get_meta(&"need_kinds", [])
	# The control: the passenger has both needs, so an icon of each could show.
	assert_array(kinds).contains([NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET])
	var off := _icons_by_need(node)
	overlay.set_shown(true)
	_views.draw()
	var mood := _icons_by_need(node)
	overlay.set_mode(MoodTint.Mode.HUNGER)
	_views.draw()
	var hunger := _icons_by_need(node)
	var hunger_need := overlay.shown_need()
	overlay.set_mode(MoodTint.Mode.TOILET)
	_views.draw()
	var toilet := _icons_by_need(node)
	overlay.set_mode(MoodTint.Mode.BOREDOM)
	_views.draw()
	var boredom := _icons_by_need(node)
	overlay.set_mode(MoodTint.Mode.TOILET)
	overlay.set_shown(false)
	_views.draw()
	var closed := _icons_by_need(node)
	print(
		(
			"icons {hunger, toilet}: off %s, mood %s, hunger %s, toilet %s, boredom %s, closed %s"
			% [off, mood, hunger, toilet, boredom, closed]
		)
	)
	assert_dict(off).is_equal({})
	assert_dict(mood).is_equal({})
	assert_dict(hunger).is_equal({NeedIcons.Need.HUNGER: 1})
	assert_dict(toilet).is_equal({NeedIcons.Need.TOILET: 1})
	assert_dict(boredom).is_equal({})
	assert_dict(closed).is_equal({})
	assert_int(hunger_need).is_equal(NeedIcons.Need.HUNGER)
	assert_int(overlay.shown_need()).is_equal(MoodOverlay.NO_NEED)


func test_main_scene_gives_the_views_the_overlay() -> void:
	var text := FileAccess.get_file_as_string("res://main/main.tscn")
	assert_bool(text.contains('mood_overlay = NodePath("../MoodOverlay")')).is_true()
