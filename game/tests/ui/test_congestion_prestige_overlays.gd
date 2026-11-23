class_name TestCongestionPrestigeOverlays
extends GdUnitTestSuite
## Congestion & Room Prestige overlay modes inside MoodOverlay (Stage 3 S3-P4a,
## decision c5664a34): density/queue congestion heatmap, deterministic
## RoomPrestige L1..L5 room tint, legend swatches, wrapping at 1.0..1.5x UI
## scales, and PseudoLocale translation hygiene.

const SEED := 4_070_093

var _path: String
var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("congestion_prestige_overlay")
	var grid := PassengerTestWorld.floored(Vector2i(20, 14))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 13), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))


func after_test() -> void:
	PseudoLocale.disable()
	for suffix in ["", ".tmp", "_alerts", "_alerts.tmp", "_dep", "_dep.tmp"]:
		DirAccess.remove_absolute(_path + suffix)
	if is_instance_valid(_views):
		_views.free()
	_world.free_all()


func _overlay() -> MoodOverlay:
	var overlay := MoodOverlay.new()
	overlay.settings_path = _path
	overlay.sim = _world.sim
	add_child(overlay)
	return auto_free(overlay)


func _button(overlay: MoodOverlay, mode_name: String) -> Button:
	return overlay.find_child("Mode" + mode_name, true, false) as Button


func _swatch_labels(overlay: MoodOverlay) -> Array[String]:
	var swatches := overlay.find_child("MoodLegendSwatches", true, false) as Control
	var out: Array[String] = []
	if swatches == null or not swatches.visible:
		return out
	for child in swatches.get_children():
		var box := child as Control
		if box != null and box.visible:
			var label := box.get_node("Label") as Label
			out.append(label.text)
	return out


func _icons_by_need(node: Node3D) -> Dictionary:
	var out := {}
	var kinds: Array = node.get_meta(&"need_kinds", [])
	for i in kinds.size():
		if (node.get_node(NeedIcons.SPRITES[i]) as Sprite3D).visible:
			out[kinds[i]] = out.get(kinds[i], 0) + 1
	return out


func test_congestion_mode_tints_by_density_and_queue_load() -> void:
	var light := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	light.at = Vector2i(3, 3)
	light.stage = Passenger.Stage.STANDING

	for i in 4:
		var busy := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		busy.at = Vector2i(12, 3)
		busy.stage = Passenger.Stage.CHECKIN_QUEUE
		busy.stage_tick = _world.sim.tick - MoodTint.BAD_WAIT_TICKS

	var overlay := _overlay()
	overlay.set_shown(true)
	overlay.set_mode(MoodOverlay.Mode.CONGESTION)

	var cells := overlay.tinted_cells()
	assert_bool(cells.has(Vector2i(8, 8))).is_false()
	assert_float(cells[Vector2i(3, 3)]).is_equal_approx(1.0, 0.001)
	assert_float(cells[Vector2i(12, 3)]).is_greater_equal(MoodOverlay.CONGESTION_HIGH_LOAD)

	var light_color := MoodOverlay.color_for(cells[Vector2i(3, 3)], MoodOverlay.Mode.CONGESTION)
	var busy_color := MoodOverlay.color_for(cells[Vector2i(12, 3)], MoodOverlay.Mode.CONGESTION)
	assert_float(light_color.g).is_greater(light_color.r)
	assert_float(busy_color.r).is_greater(busy_color.g)
	assert_bool(light_color.is_equal_approx(busy_color)).is_false()

	var tint := overlay.find_child("MoodTint", true, false) as MultiMeshInstance3D
	assert_int(tint.multimesh.instance_count).is_equal(cells.size())
	assert_int(overlay.shown_need()).is_equal(MoodOverlay.NO_NEED)
	assert_bool(overlay.shows_wishes()).is_false()
	assert_bool(overlay.shows_late()).is_false()


func test_congestion_cells_spillover_walls_floor_none_and_stuck() -> void:
	var grid := _world.grid
	var right_side := BuildGrid.SIDE_STEP.find(Vector2i.RIGHT)
	assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(3, 3), right_side)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.remove_floor(Vector2i(2, 3))).ok).is_true()

	var walker := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	walker.at = Vector2i(3, 3)
	walker.stage = Passenger.Stage.STANDING

	var stuck_p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	stuck_p.at = Vector2i(10, 7)
	stuck_p.stage = Passenger.Stage.STANDING
	stuck_p.stuck = Passenger.Stuck.NO_ROUTE

	var cells := MoodOverlay.congestion_cells(_world.sim)
	assert_float(cells[Vector2i(3, 3)]).is_equal_approx(1.0, 0.001)
	# Open-edge floor neighbours receive spillover; solid wall and FLOOR_NONE stay untinted.
	assert_float(cells[Vector2i(3, 2)]).is_equal_approx(MoodOverlay.CONGESTION_SPREAD, 0.001)
	assert_float(cells[Vector2i(3, 4)]).is_equal_approx(MoodOverlay.CONGESTION_SPREAD, 0.001)
	assert_bool(cells.has(Vector2i(4, 3))).is_false()
	assert_bool(cells.has(Vector2i(2, 3))).is_false()

	var expected_stuck := 1.0 + MoodOverlay.CONGESTION_STUCK_WEIGHT
	assert_float(cells[Vector2i(10, 7)]).is_equal_approx(expected_stuck, 0.001)
	var stuck_color := MoodOverlay.color_for(cells[Vector2i(10, 7)], MoodOverlay.Mode.CONGESTION)
	var walker_color := MoodOverlay.color_for(cells[Vector2i(3, 3)], MoodOverlay.Mode.CONGESTION)
	assert_float(stuck_color.r).is_greater(walker_color.r)


func test_congestion_and_prestige_modes_hide_need_icons() -> void:
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
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.mood_overlay = overlay
	add_child(_views)
	_world.step()
	_views.draw()
	var node := _views.node_for(p.id)

	overlay.set_shown(true)
	overlay.set_mode(MoodOverlay.Mode.HUNGER)
	_views.draw()
	assert_dict(_icons_by_need(node)).is_equal({NeedIcons.Need.HUNGER: 1})

	for non_need_mode in [MoodOverlay.Mode.CONGESTION, MoodOverlay.Mode.PRESTIGE]:
		overlay.set_mode(non_need_mode)
		_views.draw()
		assert_int(overlay.shown_need()).is_equal(MoodOverlay.NO_NEED)
		assert_dict(_icons_by_need(node)).is_empty()


func test_prestige_mode_tints_rooms_l1_to_l5_and_leaves_corridors_untinted() -> void:
	var grid := _world.grid
	var bare_room := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 4, 4), &"cafe")).room_id
	assert_int(bare_room).is_greater(0)

	var fancy_room := grid.apply(BuildEdit.place_room(Rect2i(8, 2, 10, 10), &"cafe")).room_id
	assert_int(fancy_room).is_greater(0)
	for pair in [
		[&"fountain_indoor", Vector2i(12, 2)],
		[&"statue_indoor", Vector2i(15, 2)],
		[&"tree_indoor", Vector2i(12, 5)],
		[&"bench_2a_indoor", Vector2i(8, 7)],
		[&"plant_pot_2a", Vector2i(15, 5)],
		[&"plant_pot_1a", Vector2i(17, 2)],
		[&"bench_1a", Vector2i(17, 5)],
		[&"bush", Vector2i(13, 8)],
		[&"metal_pole", Vector2i(16, 8)],
	]:
		var placed := grid.apply(BuildEdit.place_object(pair[0], pair[1], 0))
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()

	var bare_level := int(RoomPrestige.evaluate_room(grid, bare_room)["level"])
	var fancy_level := int(RoomPrestige.evaluate_room(grid, fancy_room)["level"])
	assert_int(bare_level).is_equal(1)
	assert_int(fancy_level).is_greater_equal(4)

	var overlay := _overlay()
	overlay.set_shown(true)
	overlay.set_mode(MoodOverlay.Mode.PRESTIGE)
	var cells := overlay.tinted_cells()
	assert_bool(cells.has(Vector2i(7, 5))).is_false()
	assert_float(cells[Vector2i(3, 3)]).is_equal(float(bare_level))
	assert_float(cells[Vector2i(10, 4)]).is_equal(float(fancy_level))

	var bare_color := MoodOverlay.color_for(cells[Vector2i(3, 3)], MoodOverlay.Mode.PRESTIGE)
	var fancy_color := MoodOverlay.color_for(cells[Vector2i(10, 4)], MoodOverlay.Mode.PRESTIGE)
	assert_bool(bare_color.is_equal_approx(fancy_color)).is_false()
	assert_int(overlay.shown_need()).is_equal(MoodOverlay.NO_NEED)

	# Adding decor to bare_room while paused refreshes on the next _process frame.
	var upgrade := grid.apply(BuildEdit.place_object(&"fountain_indoor", Vector2i(2, 2), 0))
	assert_bool(upgrade.ok).is_true()
	overlay._process(0.0)
	var upgraded_level := int(RoomPrestige.evaluate_room(grid, bare_room)["level"])
	assert_int(upgraded_level).is_greater(bare_level)
	assert_float(overlay.tinted_cells()[Vector2i(3, 3)]).is_equal(float(upgraded_level))


func test_legend_buttons_switch_modes_swatches_and_persist_respecting_new_airport() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	assert_object(_button(overlay, "Congestion")).is_not_null()
	assert_object(_button(overlay, "Prestige")).is_not_null()

	_button(overlay, "Congestion").button_pressed = true
	assert_int(overlay.mode()).is_equal(MoodOverlay.Mode.CONGESTION)
	assert_array(_swatch_labels(overlay)).is_equal(["Light", "Busy", "Congested"])

	_button(overlay, "Prestige").button_pressed = true
	assert_int(overlay.mode()).is_equal(MoodOverlay.Mode.PRESTIGE)
	assert_array(_swatch_labels(overlay)).is_equal(["Lv. 1", "Lv. 2", "Lv. 3", "Lv. 4", "Lv. 5"])

	_button(overlay, "Mood").button_pressed = true
	assert_array(_swatch_labels(overlay)).is_empty()

	_button(overlay, "Prestige").button_pressed = true
	var new_before := GameBoot.new_airport
	GameBoot.new_airport = false
	var resumed := _overlay()
	assert_int(resumed.mode()).is_equal(MoodOverlay.Mode.PRESTIGE)
	assert_bool(resumed.is_shown()).is_true()

	GameBoot.new_airport = true
	var fresh := _overlay()
	assert_bool(fresh.is_shown()).is_false()
	assert_int(fresh.mode()).is_equal(MoodOverlay.Mode.MOOD)
	GameBoot.new_airport = new_before


func test_congestion_and_prestige_retranslate_on_locale_change() -> void:
	var overlay := _overlay()
	overlay.set_shown(true)
	overlay.set_mode(MoodOverlay.Mode.CONGESTION)

	PseudoLocale.enable(0.4)
	overlay.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)

	var toggle := overlay.find_child("MoodToggle", true, false) as Button
	var legend := overlay.find_child("MoodLegend", true, false) as Label
	assert_str(toggle.text).starts_with("[")
	assert_str(legend.text).starts_with("[")
	for name_str in ["Congestion", "Prestige"]:
		var btn := _button(overlay, name_str)
		assert_str(btn.text).starts_with("[")
		assert_str(btn.text).contains(name_str)
	for label_text in _swatch_labels(overlay):
		assert_str(label_text).starts_with("[")

	overlay.set_mode(MoodOverlay.Mode.PRESTIGE)
	for label_text in _swatch_labels(overlay):
		assert_str(label_text).starts_with("[")

	PseudoLocale.disable()
	overlay.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_array(_swatch_labels(overlay)).is_equal(["Lv. 1", "Lv. 2", "Lv. 3", "Lv. 4", "Lv. 5"])


func _assert_legend_clears_hud(main: Node, size: Vector2i, require_wrapped := false) -> Rect2:
	var card := main.find_child("MoodLegendCard", true, false) as Control
	var modes := main.find_child("MoodModes", true, false) as Control
	var card_rect := card.get_global_rect()
	var view_rect := Rect2(Vector2.ZERO, Vector2(size))
	assert_bool(view_rect.encloses(card_rect)).is_true()
	if require_wrapped:
		assert_float(modes.size.y).is_greater(float(HudLayout.CHIP_H))
	for blocker_name in [
		"MoodToggle",
		"DeparturesToggle",
		"PlannerToggle",
		"RunwayButton",
		"OffersButton",
		"FlightPanel",
		"DeparturesPanel",
		"StaffHintCard",
	]:
		var blocker := main.find_child(blocker_name, true, false) as Control
		if blocker != null and blocker.is_visible_in_tree():
			(
				assert_bool(card_rect.intersects(blocker.get_global_rect()))
				. override_failure_message(
					(
						"MoodLegendCard %s overlaps %s %s at %s"
						% [card_rect, blocker_name, blocker.get_global_rect(), size]
					)
				)
				. is_false()
			)
	return card_rect


func test_legend_wraps_cleanly_and_clears_hud_at_1280x720_and_1536x864() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var main := (load(SaveTestKit.MAIN) as PackedScene).instantiate()
	(main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(main.get_node("SimClock") as SimClock).set_paused(true)
	(main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _path + "_alerts"
	(main.get_node("PassengerHud") as PassengerHud).departures_settings_path = _path + "_dep"
	var overlay := main.get_node("MoodOverlay") as MoodOverlay
	overlay.settings_path = _path
	port.add_child(main)
	await await_idle_frame()
	await await_idle_frame()

	overlay.set_shown(true)
	# Wide viewports keep default Mood mode compact (single button row, < 96 px tall).
	for wide in [Vector2i(1536, 864), Vector2i(1920, 1080)]:
		port.size = wide
		overlay.set_mode(MoodOverlay.Mode.MOOD)
		await await_idle_frame()
		await await_idle_frame()
		var mood_rect := _assert_legend_clears_hud(main, wide, false)
		assert_float(mood_rect.size.y).is_less(
			float(LeftColumn.list_top(main.get_tree()) - LeftColumn.TOP)
		)

	for size in [
		Vector2i(1280, 720), Vector2i(1372, 772), Vector2i(1536, 864), Vector2i(1920, 1080)
	]:
		port.size = size
		for target_mode in [MoodOverlay.Mode.CONGESTION, MoodOverlay.Mode.PRESTIGE]:
			overlay.set_mode(target_mode)
			await await_idle_frame()
			await await_idle_frame()
			_assert_legend_clears_hud(main, size, false)

	# Under PseudoLocale (+40%) at 1.5x scale (1280x720), buttons wrap instead of overflowing.
	PseudoLocale.enable(0.4)
	main.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	port.size = Vector2i(1280, 720)
	for target_mode in [MoodOverlay.Mode.CONGESTION, MoodOverlay.Mode.PRESTIGE]:
		overlay.set_mode(target_mode)
		await await_idle_frame()
		await await_idle_frame()
		_assert_legend_clears_hud(main, Vector2i(1280, 720), true)
