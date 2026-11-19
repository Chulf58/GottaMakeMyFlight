extends SceneTree
## Windowed 1920x1080 verification plates for the Build Menu rework (board
## d6f56ecf, decision build-menu-rework-six-domain-tabs-progressive-tab-and-card-u):
##   1. plate_01_tier1_day1.png       — Tier 1 Day 1, 3 build tabs, Operations 4 cards
##   2. plate_02_demo_tier2_teasers.png — Demo Tier 2, 6 tabs, New tints + Tier 3 teasers
##   3. plate_03_tier4_decor_scrolled.png — Tier 4 Decor & Parking (23 cards) scrolled right
##   4. plate_04_inspect_and_hover.png — PassengerInspect + Operations tray + 280 px hover popup
##   5. contact_sheet.png             — 2x2 contact sheet of plates 01..04

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/build-menu-rework"
const SCREEN := Vector2i(1920, 1080)
const UI_SCALE := 1.25
const HOVER_LIMIT_FRAMES := 360
const FLIGHT_LIMIT_FRAMES := 600
const LIMIT_MS := 150000

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _stop := false
var _lock := Mutex.new()
var _guard := Thread.new()
var _plates: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: exceeded %d ms" % LIMIT_MS)
			OS.crash("build_menu_rework_plates_probe timeout")


func _finish(code: int) -> void:
	DemoMode.clear_override()
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	quit(code)


func _invalid(msg: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", msg)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_invalid(msg)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var base_seed := randi()
	seed(base_seed)
	print("PROBE world_seed=%d" % base_seed)
	DisplayServer.window_set_size(SCREEN)
	root.content_scale_factor = UI_SCALE
	await _frames(10)
	_expect(root.size == SCREEN, "window size %s != %s" % [root.size, SCREEN])

	await _run_plate_01(base_seed + 1)
	await _run_plate_02(base_seed + 2)
	var main3 := await _run_plate_03(base_seed + 3)
	if main3 != null:
		await _run_plate_04(main3)
		main3.queue_free()
		await _frames(4)
	_expect(_plates.size() == 4, "expected 4 captured plates, got %d" % _plates.size())
	if _plates.size() == 4 and not _failed:
		_save_contact_sheet()
	print("PROBE_INVALID" if _failed else "PROBE_PASS")
	_finish(1 if _failed else 0)


func _boot_world(world_seed: int, profile_guide: bool) -> Node3D:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	var clock := main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	var hud := main.get_node("PassengerHud") as PassengerHud
	if profile_guide:
		hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	root.add_child(main)
	clock.set_paused(true)
	await _frames(6)
	hud.press_starter_terminal()
	var mode := main.get_node("BuildMode") as BuildMode
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	(rig.get_node("Camera3D") as Camera3D).make_current()
	var area := StartView.area_for(mode.grid)
	rig.frame_start_view(area)
	var center_pt := Vector3(area.get_center().x, 0.22, area.get_center().y)
	await _frames(10)
	_check_terminal_visible(main, center_pt)
	return main


func _check_terminal_visible(main: Node3D, world_pt: Vector3) -> void:
	var cam := main.get_node("TycoonCamera/Camera3D") as Camera3D
	var view := root.get_visible_rect().grow(-16.0)
	var screen_pt := cam.unproject_position(world_pt)
	var in_frame := view.has_point(screen_pt) and not cam.is_position_behind(world_pt)
	print("PROBE terminal focus=%s screen=%s in_frame=%s" % [world_pt, screen_pt, in_frame])
	_expect(in_frame, "terminal focus point is not in frame")


func _run_plate_01(world_seed: int) -> void:
	DemoMode.clear_override()
	var main := await _boot_world(world_seed, true)
	var menu := main.get_node("BuildMenu") as BuildMenu
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	menu.end_grant_hold()
	menu.press_category(BuildMenu.category_index("operations"))
	_warp_away()
	await _frames(10)

	var vis_tabs := _visible_build_tabs(menu)
	var vis_cards := _visible_row_tools(menu, BuildMenu.category_index("operations"))
	var tray_rect := menu.tray().get_global_rect()
	print(
		(
			"PLATE_01 tier=%d vis_tabs=%s vis_cards=%d tray=%s"
			% [unlocks.tier(), vis_tabs, vis_cards.size(), tray_rect]
		)
	)
	_expect(unlocks.tier() == 1, "plate_01: expected tier 1")
	_expect(vis_tabs == [0, 1, 2], "plate_01: expected [0, 1, 2] tabs, got %s" % [vis_tabs])
	_expect(menu.category_button(BuildMenu.REMOVE_CATEGORY).visible, "plate_01: Remove hidden")
	_expect(vis_cards.size() == 4, "plate_01: expected 4 Tier-1 Operations cards")
	_expect(tray_rect.size.x < BuildMenu.COLUMN_W - 80.0, "plate_01: tray did not hug 4 cards")
	_expect(is_equal_approx(tray_rect.size.y, BuildMenu.TRAY_H), "plate_01: tray height != TRAY_H")
	_check_compact_cards(menu, vis_cards, "plate_01")
	_capture("plate_01_tier1_day1.png")
	main.queue_free()
	await _frames(4)


func _run_plate_02(world_seed: int) -> void:
	DemoMode.set_override_for_test(true)
	var main := await _boot_world(world_seed, true)
	var hud := main.get_node("PassengerHud") as PassengerHud
	var menu := main.get_node("BuildMenu") as BuildMenu
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	for _i in 60:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for _i in 55:
		unlocks.note_made()
	unlocks.check()
	await _frames(6)
	if hud.unlock_guide().is_open():
		hud.unlock_guide().dismiss()
	menu.end_grant_hold()
	var food_idx := BuildMenu.category_index("food")
	menu.press_category(food_idx)
	_warp_away()
	await _frames(10)

	var vis_tabs := _visible_build_tabs(menu)
	var new_tabs: Array[int] = []
	for i in BuildMenu.REMOVE_CATEGORY:
		if menu.category_button(i).modulate.is_equal_approx(BuildMenu.NEW_TINT):
			new_tabs.append(i)
	var ordered := _visible_row_tools(menu, food_idx)
	var teaser_label := menu.card(BuildMode.Tool.BAR_ROOM).find_child("Price", true, false) as Label
	print(
		(
			"PLATE_02 tier=%d vis_tabs=%s new_tabs=%s ordered=%d teaser='%s'"
			% [unlocks.tier(), vis_tabs, new_tabs, ordered.size(), teaser_label.text]
		)
	)
	_expect(vis_tabs == [0, 1, 2, 3, 4, 5], "plate_02: expected all 6 build tabs")
	_expect(
		new_tabs == [1, 4, 5],
		"plate_02: expected [1, 4, 5] unpressed new tabs, got %s" % [new_tabs]
	)
	_expect(
		menu.category_button(food_idx).modulate.is_equal_approx(Color.WHITE),
		"plate_02: pressed Food & Drink tab must stay untinted teal"
	)
	_expect(ordered.size() == 10, "plate_02: expected 10 cards in Food & Drink")
	_expect(
		(
			ordered.slice(0, 3)
			== [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE]
		),
		"plate_02: playable Tier-2 cards must precede Tier-3 teasers"
	)
	_expect(
		menu.card(BuildMode.Tool.CAFE_ROOM).modulate.is_equal_approx(BuildMenu.NEW_TINT),
		"plate_02: Cafe card missing NEW_TINT"
	)
	var tfont := teaser_label.get_theme_font(&"font")
	var tsize := teaser_label.get_theme_font_size(&"font_size")
	var twidth := tfont.get_string_size(teaser_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x
	print(
		"PLATE_02 teaser font_size=%d width=%.1f slot=%.1f" % [tsize, twidth, teaser_label.size.x]
	)
	_expect(teaser_label.text == "In the full game", "plate_02: wrong teaser label")
	_expect(twidth <= teaser_label.size.x + 0.5, "plate_02: teaser text clipped in slot")
	_capture("plate_02_demo_tier2_teasers.png")
	DemoMode.clear_override()
	main.queue_free()
	await _frames(4)


func _find_terminal_floor_cell(grid: BuildGrid) -> Vector2i:
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if (
				grid.floor_at(c) != BuildGrid.FLOOR_NONE
				and grid.object_at(c) == 0
				and grid.room_at(c) == 0
			):
				return c
	return Vector2i(10, 10)


func _run_plate_03(world_seed: int) -> Node3D:
	DemoMode.clear_override()
	var main := await _boot_world(world_seed, false)
	var menu := main.get_node("BuildMenu") as BuildMenu
	var mode := main.get_node("BuildMode") as BuildMode
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	for _i in 80:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for _i in 850:
		unlocks.note_made()
	unlocks.check()
	await _frames(6)
	menu.end_grant_hold()
	mode.set_tool(BuildMode.Tool.BENCH)
	var cam := main.get_node("TycoonCamera/Camera3D") as Camera3D
	var bench_cell := _find_terminal_floor_cell(mode.grid)
	_warp_to(cam.unproject_position(mode.grid.cell_to_world(bench_cell)))
	await _frames(6)
	menu.tray_scroll().scroll_horizontal = 99999
	await _frames(8)

	var decor_idx := BuildMenu.category_index("decor")
	var vis_cards := _visible_row_tools(menu, decor_idx)
	var tray_rect := menu.tray().get_global_rect()
	var status_rect := menu.status_card().get_global_rect()
	var scroll_x := menu.tray_scroll().scroll_horizontal
	print(
		(
			"PLATE_03 tier=%d decor_cards=%d scroll_x=%d tray=%s status=%s"
			% [unlocks.tier(), vis_cards.size(), scroll_x, tray_rect, status_rect]
		)
	)
	_expect(unlocks.tier() == 4, "plate_03: expected tier 4")
	_expect(vis_cards.size() == 23, "plate_03: expected 23 Decor & Parking cards")
	_expect(scroll_x > 1000, "plate_03: expected scrolled right end, got %d" % scroll_x)
	_expect(is_equal_approx(tray_rect.size.y, BuildMenu.TRAY_H), "plate_03: tray height != TRAY_H")
	_expect(menu.status_card().visible, "plate_03: StatusCard should be visible")
	_expect(not status_rect.intersects(tray_rect), "plate_03: StatusCard overlaps ItemTray")
	_check_compact_cards(menu, vis_cards, "plate_03")
	_capture("plate_03_tier4_decor_scrolled.png")
	return main


func _run_plate_04(main: Node3D) -> void:
	var clock := main.get_node("SimClock") as SimClock
	var flights := main.get_node("FlightSim") as FlightSim
	var sim := main.get_node("PassengerSim") as PassengerSim
	var views := main.get_node("PassengerViews") as PassengerViews
	var hud := main.get_node("PassengerHud") as PassengerHud
	var menu := main.get_node("BuildMenu") as BuildMenu
	var mode := main.get_node("BuildMode") as BuildMode
	var staff := main.get_node("Staff") as StaffSim
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	mode.set_tool(BuildMode.Tool.NONE)
	clock.set_speed(3)
	clock.set_paused(false)
	for _i in FLIGHT_LIMIT_FRAMES:
		if flights.opened_tick >= 0:
			break
		await process_frame
	if sim.passenger_ids().is_empty():
		hud.press_debug_spawn()
	for _step in 200:
		if not sim.passenger_ids().is_empty():
			break
		clock.advance(SimClock.STEP * 4.0)
	clock.set_paused(true)
	var pax_ids := sim.passenger_ids()
	_expect(not pax_ids.is_empty(), "plate_04: no passengers spawned")
	if not pax_ids.is_empty():
		views.selected_id = pax_ids[0]
	hud.refresh()
	menu.press_category(BuildMenu.category_index("operations"))
	var screen_card := menu.card(BuildMode.Tool.SCREEN) as ItemCardButton
	await _frames(4)
	menu.tray_scroll().ensure_control_visible(screen_card)
	await _frames(8)

	var shown := await _open_hover_popup(screen_card)
	var inspect := hud.find_child("PassengerInspect", true, false) as PassengerInspect
	var inspect_rect := inspect.get_global_rect()
	var tray_rect := menu.tray().get_global_rect()
	print(
		(
			"PLATE_04 inspect_vis=%s inspect=%s tray=%s gap_x=%.1f"
			% [inspect.visible, inspect_rect, tray_rect, tray_rect.position.x - inspect_rect.end.x]
		)
	)
	_expect(inspect.visible and inspect.shows_passenger(), "plate_04: PassengerInspect not open")
	_expect(not inspect_rect.intersects(tray_rect), "plate_04: PassengerInspect overlaps ItemTray")
	_expect(is_equal_approx(tray_rect.size.x, BuildMenu.COLUMN_W), "plate_04: tray width != 640")
	_check_hover_popup(shown, screen_card)
	_capture("plate_04_inspect_and_hover.png")


func _open_hover_popup(card: ItemCardButton) -> Control:
	var card_r := card.get_global_rect()
	var target := root.get_final_transform() * card_r.get_center()
	root.warp_mouse(card_r.get_center())
	var shown: Control = null
	for _i in HOVER_LIMIT_FRAMES:
		var motion := InputEventMouseMotion.new()
		motion.position = target
		motion.global_position = target
		Input.parse_input_event(motion)
		await process_frame
		if is_instance_valid(card._card) and card._card.is_inside_tree():
			shown = card._card
			break
	await _frames(15)
	if is_instance_valid(card._card) and card._card.is_inside_tree():
		return card._card
	return shown


func _check_hover_popup(shown: Control, card: ItemCardButton) -> void:
	if shown == null:
		_invalid("plate_04: hover popup did not open")
		return
	var popup := shown.get_window()
	var popup_r := Rect2(Vector2(popup.position), Vector2(popup.size))
	var card_r := card.get_global_rect()
	var texts: PackedStringArray = []
	for node in shown.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	var joined := " | ".join(texts)
	var size_str := BuildMenuCatalog.size_text(BuildMode.Tool.SCREEN)
	print("PLATE_04 popup=%s card=%s texts=%s" % [popup_r, card_r, joined])
	_expect(not popup_r.intersects(card_r), "plate_04: hover popup overlaps card")
	_expect(popup_r.end.y <= card_r.position.y, "plate_04: hover popup not above card")
	_expect(texts.has(size_str) and texts.has("Click"), "plate_04: popup missing size or Click")
	_expect(joined.contains("Upkeep"), "plate_04: popup missing Upkeep")


func _visible_build_tabs(menu: BuildMenu) -> Array[int]:
	var out: Array[int] = []
	for i in BuildMenu.REMOVE_CATEGORY:
		if menu.category_button(i).visible:
			out.append(i)
	return out


func _visible_row_tools(menu: BuildMenu, cat_idx: int) -> Array[int]:
	var out: Array[int] = []
	var first_tool: int = BuildMenu.categories()[cat_idx]["tools"][0]
	var row := menu.card(first_tool).get_parent()
	for child in row.get_children():
		if child is Control and (child as Control).visible:
			for tool in BuildMenu.categories()[cat_idx]["tools"]:
				if menu.card(tool) == child:
					out.append(tool)
	return out


func _check_compact_cards(menu: BuildMenu, tools: Array[int], tag: String) -> void:
	for tool in tools:
		var card := menu.card(tool)
		var thumb := card.find_child("Thumbnail", true, false) as Control
		var labels := card.find_children("*", "Label", true, false)
		_expect(
			thumb != null and thumb.size.is_equal_approx(Vector2(52.0, 52.0)),
			"%s: tool %d thumbnail size %s != (52, 52)" % [tag, tool, thumb.size]
		)
		_expect(
			labels.size() == 2, "%s: tool %d has %d labels, want 2" % [tag, tool, labels.size()]
		)


func _warp_away() -> void:
	_warp_to(Vector2(768.0, 220.0))


func _warp_to(layout_pt: Vector2) -> void:
	var win_pt := root.get_final_transform() * layout_pt
	root.warp_mouse(layout_pt)
	var motion := InputEventMouseMotion.new()
	motion.position = win_pt
	motion.global_position = win_pt
	Input.parse_input_event(motion)


func _capture(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(filename)
	var err := img.save_png(path)
	print("PLATE saved %s size=%s err=%d" % [path, img.get_size(), err])
	_expect(err == OK and img.get_size() == SCREEN, "failed to save %s" % filename)
	_plates.append(img)


func _save_contact_sheet() -> void:
	var tile_w := SCREEN.x / 2
	var tile_h := SCREEN.y / 2
	var sheet := Image.create(SCREEN.x, SCREEN.y, false, Image.FORMAT_RGBA8)
	var slots: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(tile_w, 0),
		Vector2i(0, tile_h),
		Vector2i(tile_w, tile_h),
	]
	for i in 4:
		var copy := _plates[i].duplicate() as Image
		copy.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(copy, Rect2i(Vector2i.ZERO, Vector2i(tile_w, tile_h)), slots[i])
	var path := _out_dir.path_join("contact_sheet.png")
	var err := sheet.save_png(path)
	print("PLATE saved %s size=%s err=%d" % [path, sheet.get_size(), err])
	_expect(err == OK, "failed to save contact_sheet.png")
