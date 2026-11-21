extends SceneTree
## Windowed Vulkan verification plates for Build Menu rework, Templates tab, and
## VF5 thumbnails (rulings 31fe648d, b35d5232, 0e312a7e; board 7ebf8514) at
## both 1536x864 (1.25x) and 1280x720 (1.5x) layout scales:
##   1. plate_01_tier1_day1_1536.png           — Tier 1 Day 1 (3 tabs + Templates + Remove)
##   2. plate_02_demo_food_teasers_1536.png    — Demo Tier 2 Food (dining rooms & sub-filters)
##   3. plate_03_tier4_facilities_all_1536.png — Tier 4 Facilities All (Room badges & dividers)
##   4. plate_04_facilities_lounge_play_1536.png — Tier 4 Facilities filtered to Lounge & Play
##   5. plate_05_templates_and_locks_1536.png  — Templates tab + unlocked/locked previews + Inspect
##   6. plate_06_shops_bar_clear_1280.png      — 1280x720 (1.5x) Shops + bar + Inspect clearance
##   7. plate_07_landside_1280.png             — 1280x720 (1.5x) Landside & Parking (lot_gate)
##   8. plate_08_decor_building_1280.png       — 1280x720 (1.5x) Decor & hover popup
##   9. contact_sheet.png                     — 4x2 contact sheet of plates 01..08

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/build_menu_rework_vf5"
const SCREEN := Vector2i(1920, 1080)
const SCALE_1536 := 1.25
const SCALE_1280 := 1.5
const HOVER_LIMIT_FRAMES := 360
const FLIGHT_LIMIT_FRAMES := 600
const LIMIT_MS := 180000

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


func _set_layout(ui_scale: float) -> void:
	DisplayServer.window_set_size(SCREEN)
	root.content_scale_factor = ui_scale
	await _frames(8)
	var expected := Vector2(SCREEN) / ui_scale
	var got := root.get_visible_rect().size
	print("PROBE layout scale=%.2f got=%s expected=%s" % [ui_scale, got, expected])
	_expect(got.is_equal_approx(expected), "layout %s != %s" % [got, expected])


func _run() -> void:
	var base_seed := randi()
	seed(base_seed)
	print("PROBE world_seed=%d" % base_seed)
	await _set_layout(SCALE_1536)

	await _run_plate_01(base_seed + 1)
	await _run_plate_02(base_seed + 2)
	var main3 := await _run_plate_03_to_05(base_seed + 3)
	if main3 != null:
		main3.queue_free()
		await _frames(4)

	await _set_layout(SCALE_1280)
	await _run_plates_1280(base_seed + 4)

	_expect(_plates.size() == 8, "expected 8 captured plates, got %d" % _plates.size())
	if _plates.size() == 8 and not _failed:
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
	await _frames(8)
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
	menu.press_category(BuildMenu.category_index("building"))
	_warp_away()
	await _frames(8)

	var vis_tabs := _visible_build_tabs(menu)
	var vis_cards := _visible_row_tools(menu, BuildMenu.category_index("building"))
	var tray_rect := menu.tray().get_global_rect()
	print(
		(
			"PLATE_01 tier=%d vis_tabs=%s vis_cards=%d tray=%s"
			% [unlocks.tier(), vis_tabs, vis_cards.size(), tray_rect]
		)
	)
	_expect(unlocks.tier() == 1, "plate_01: expected tier 1")
	_expect(vis_tabs == [0, 1, 2], "plate_01: expected [0, 1, 2] tabs, got %s" % [vis_tabs])
	_expect(
		menu.find_child("TemplatesDock", true, false) == null, "plate_01: TemplatesDock present"
	)
	_expect(
		menu.bar().is_ancestor_of(menu.templates_page.button),
		"plate_01: TemplatesButton not in bar"
	)
	_expect(vis_cards.size() == 7, "plate_01: expected 7 Tier-1 Building cards")
	_check_tray_bounds(menu, BuildMenu.TRAY_H, "plate_01")
	_check_compact_cards(menu, vis_cards, "plate_01")
	_capture("plate_01_tier1_day1_1536.png")
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
	await _frames(8)

	var vis_tabs := _visible_build_tabs(menu)
	var ordered := _visible_row_tools(menu, food_idx)
	var tray_rect := menu.tray().get_global_rect()
	print(
		(
			"PLATE_02 tier=%d vis_tabs=%s ordered=%d tray=%s pills=%d"
			% [unlocks.tier(), vis_tabs, ordered.size(), tray_rect, menu.filter_buttons().size()]
		)
	)
	_expect(vis_tabs == [0, 1, 2, 3, 4, 5, 6], "plate_02: expected all 7 domain tabs")
	_expect(ordered.size() == 10, "plate_02: expected 10 cards in Food & Drink")
	_check_tray_bounds(menu, BuildMenu.TRAY_FILTERED_H, "plate_02")
	_expect(menu.filter_buttons().size() == 3, "plate_02: expected All/Rooms/Items filter pills")
	_check_compact_cards(menu, ordered, "plate_02")
	_capture("plate_02_demo_food_teasers_1536.png")
	DemoMode.clear_override()
	main.queue_free()
	await _frames(4)


func _unlock_tier4(main: Node3D) -> void:
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	for _i in 80:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for _i in 850:
		unlocks.note_made()
	unlocks.check()
	await _frames(6)


func _add_sample_templates(mode: BuildMode) -> void:
	var cafe := RoomTemplate.new()
	cafe.name = "Cafe 4x4"
	cafe.room_type = &"cafe"
	cafe.size = Vector2i(4, 4)
	for _i in 16:
		cafe.floors.append(Vector2i(BuildGrid.FLOOR_TILE, 1))
	cafe.pieces.append({"def": &"cafe_counter", "anchor": Vector2i(1, 0), "facing": 0})
	mode.templates.library.add(cafe)
	var rest := RoomTemplate.new()
	rest.name = "Rest 4x4"
	rest.room_type = &"restaurant"
	rest.size = Vector2i(4, 4)
	for _i in 16:
		rest.floors.append(Vector2i(BuildGrid.FLOOR_TILE, 1))
	rest.pieces.append({"def": &"restaurant_booth", "anchor": Vector2i(1, 0), "facing": 0})
	mode.templates.library.add(rest)


func _open_and_spawn_passenger(main: Node3D) -> void:
	var menu := main.get_node("BuildMenu") as BuildMenu
	var hud := main.get_node("PassengerHud") as PassengerHud
	var sim := main.get_node("PassengerSim") as PassengerSim
	var flights := main.get_node("FlightSim") as FlightSim
	var staff := main.get_node("Staff") as StaffSim
	var views := main.get_node("PassengerViews") as PassengerViews
	var clock := main.get_node("SimClock") as SimClock
	menu.close_for_modal()
	if staff.count(StaffMember.Role.CHECKIN) == 0:
		staff.hire(StaffMember.Role.CHECKIN)
	if staff.count(StaffMember.Role.SECURITY) == 0:
		staff.hire(StaffMember.Role.SECURITY)
	clock.set_paused(false)
	for _i in 600:
		if flights.opened_tick >= 0:
			break
		clock.advance(SimClock.STEP * 4.0)
	if flights.opened_tick >= 0 and sim.passenger_ids().is_empty():
		hud.press_debug_spawn()
	for _i in 60:
		if not sim.passenger_ids().is_empty():
			break
		clock.advance(SimClock.STEP * 4.0)
	clock.set_paused(true)
	if not sim.passenger_ids().is_empty():
		views.selected_id = sim.passenger_ids()[0]
	hud.refresh()


func _run_plate_03_to_05(world_seed: int) -> Node3D:
	DemoMode.clear_override()
	var main := await _boot_world(world_seed, false)
	var menu := main.get_node("BuildMenu") as BuildMenu
	var mode := main.get_node("BuildMode") as BuildMode
	var hud := main.get_node("PassengerHud") as PassengerHud
	await _unlock_tier4(main)
	menu.end_grant_hold()

	# Plate 03: Tier 4 Facilities All (Room badges + renamed items + filter strip).
	var fac_idx := BuildMenu.category_index("facilities")
	menu.press_category(fac_idx)
	await _frames(3)
	menu.tray_scroll().scroll_horizontal = 600
	_warp_away()
	await _frames(6)
	var fac_cards := _visible_row_tools(menu, fac_idx)
	_expect(fac_cards.size() == 20, "plate_03: expected 20 Facilities cards")
	_check_tray_bounds(menu, BuildMenu.TRAY_FILTERED_H, "plate_03")
	_check_compact_cards(menu, fac_cards, "plate_03")
	_capture("plate_03_tier4_facilities_all_1536.png")

	# Plate 04: Facilities filtered to Lounge & Play (7 cards).
	menu.press_filter("lounge_play")
	await _frames(6)
	var lp_cards := _visible_row_tools(menu, fac_idx)
	_expect(lp_cards.size() == 7, "plate_04: expected 7 Lounge & Play cards")
	_check_tray_bounds(menu, BuildMenu.TRAY_FILTERED_H, "plate_04")
	_capture("plate_04_facilities_lounge_play_1536.png")

	# Plate 05: Templates tab (1 unlocked + 1 Demo-locked template + PassengerInspect on MARGIN).
	_add_sample_templates(mode)
	DemoMode.set_override_for_test(true)
	await _open_and_spawn_passenger(main)
	menu._refresh_cards()
	menu.press_category(BuildMenu.TEMPLATES_PAGE)
	await _frames(8)
	var tpl_rect := _check_tray_bounds(menu, BuildMenu.TRAY_H, "plate_05")
	var inspect := hud.find_child("PassengerInspect", true, false) as PassengerInspect
	var inspect_r := inspect.get_global_rect()
	print("PLATE_05 tpl_tray=%s inspect=%s vis=%s" % [tpl_rect, inspect_r, inspect.visible])
	_expect(menu.templates_page.visible, "plate_05: TemplatesPage not visible")
	_expect(
		inspect.visible and inspect.shows_passenger(), "plate_05: Inspect not showing passenger"
	)
	_expect(not inspect_r.intersects(tpl_rect), "plate_05: Inspect overlaps Templates tray")
	_expect(
		is_equal_approx(inspect_r.end.y, root.get_visible_rect().size.y - float(HudLayout.MARGIN)),
		"plate_05: Inspect not resting on MARGIN"
	)
	_capture("plate_05_templates_and_locks_1536.png")
	DemoMode.clear_override()
	return main


func _run_plates_1280(world_seed: int) -> void:
	DemoMode.clear_override()
	var main := await _boot_world(world_seed, false)
	var menu := main.get_node("BuildMenu") as BuildMenu
	var hud := main.get_node("PassengerHud") as PassengerHud
	await _unlock_tier4(main)
	menu.end_grant_hold()
	await _open_and_spawn_passenger(main)

	# Plate 06: 1280x720 Shops tab (Duty Free / Fashion Till) + 10-button bar + Inspect.
	var shops_idx := BuildMenu.category_index("shops")
	menu.press_category(shops_idx)
	await _frames(3)
	menu.tray_scroll().scroll_horizontal = 580
	_warp_away()
	await _frames(6)
	var bar_r := menu.bar().get_global_rect()
	var tray_r := _check_tray_bounds(menu, BuildMenu.TRAY_FILTERED_H, "plate_06")
	var inspect := hud.find_child("PassengerInspect", true, false) as PassengerInspect
	var inspect_r := inspect.get_global_rect()
	print(
		(
			"PLATE_06_1280 bar=%s tray=%s inspect=%s vis=%s"
			% [bar_r, tray_r, inspect_r, inspect.visible]
		)
	)
	_expect(
		inspect.visible and inspect.shows_passenger(), "plate_06: Inspect not showing passenger"
	)
	_expect(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(bar_r),
		"plate_06: CategoryBar leaves 1280 viewport"
	)
	_expect(
		not inspect_r.intersects(bar_r) and not inspect_r.intersects(tray_r),
		"plate_06: Inspect overlaps bar/tray"
	)
	_expect(
		is_equal_approx(inspect_r.end.y, root.get_visible_rect().size.y - float(HudLayout.MARGIN)),
		"plate_06: Inspect not resting on MARGIN at 1280"
	)
	_capture("plate_06_shops_bar_clear_1280.png")

	# Plate 07: 1280x720 Landside & Parking tab (136 px, 4 cards).
	var land_idx := BuildMenu.category_index("landside")
	menu.press_category(land_idx)
	_warp_away()
	await _frames(8)
	var land_cards := _visible_row_tools(menu, land_idx)
	_expect(land_cards.size() == 4, "plate_07: expected 4 Landside cards")
	_check_tray_bounds(menu, BuildMenu.TRAY_H, "plate_07")
	_capture("plate_07_landside_1280.png")

	# Plate 08: 1280x720 Decor tab (12 cards, VF5/VF7 outlines) + hover popup.
	var decor_idx := BuildMenu.category_index("decor")
	menu.press_category(decor_idx)
	await _frames(6)
	var bush_card := menu.card(BuildMode.Tool.BUSH) as ItemCardButton
	var shown := await _open_hover_popup(bush_card)
	_expect(shown != null, "plate_08: hover popup did not open")
	_check_tray_bounds(menu, BuildMenu.TRAY_H, "plate_08")
	_capture("plate_08_decor_building_1280.png")
	main.queue_free()
	await _frames(4)


func _check_tray_bounds(menu: BuildMenu, expect_h: float, tag: String) -> Rect2:
	var bar_r := menu.bar().get_global_rect()
	var tray_r := menu.tray().get_global_rect()
	var cx := root.get_visible_rect().size.x * 0.5
	_expect(menu.is_tray_open(), "%s: tray not open" % tag)
	_expect(
		is_equal_approx(tray_r.size.y, expect_h),
		"%s: tray height %.1f != %.1f" % [tag, tray_r.size.y, expect_h]
	)
	_expect(
		absf(tray_r.get_center().x - cx) <= 1.0,
		"%s: tray center %.1f != %.1f" % [tag, tray_r.get_center().x, cx]
	)
	_expect(
		absf(tray_r.end.y - (bar_r.position.y - float(HudLayout.GAP))) <= 1.0,
		(
			"%s: tray bottom %.1f != bar.top - GAP %.1f"
			% [tag, tray_r.end.y, bar_r.position.y - HudLayout.GAP]
		)
	)
	_expect(not bar_r.intersects(tray_r), "%s: bar intersects tray" % tag)
	return tray_r


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


func _visible_build_tabs(menu: BuildMenu) -> Array[int]:
	var out: Array[int] = []
	for i in BuildMenu.REMOVE_CATEGORY:
		if menu.category_button(i).visible:
			out.append(i)
	return out


func _visible_row_tools(menu: BuildMenu, cat_idx: int) -> Array[int]:
	var out: Array[int] = []
	for tool in BuildMenu.categories()[cat_idx]["tools"]:
		var card := menu.card(tool)
		if card != null and card.visible:
			out.append(tool)
	return out


func _check_compact_cards(menu: BuildMenu, tools: Array[int], tag: String) -> void:
	for tool in tools:
		var card := menu.card(tool)
		var thumb := card.find_child("Thumbnail", true, false) as Control
		var want_sz := Vector2(BuildMenu.THUMB_SIZE, BuildMenu.THUMB_SIZE)
		_expect(
			thumb != null and thumb.size.is_equal_approx(want_sz),
			"%s: tool %d thumbnail size %s != %s" % [tag, tool, thumb.size, want_sz]
		)
		_expect(
			card.size.is_equal_approx(BuildMenu.CARD_SIZE),
			"%s: tool %d card size %s != %s" % [tag, tool, card.size, BuildMenu.CARD_SIZE]
		)


func _warp_away() -> void:
	_warp_to(Vector2(640.0, 200.0))


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
	var tile_w := 640
	var tile_h := 360
	var sheet := Image.create(tile_w * 4, tile_h * 2, false, Image.FORMAT_RGBA8)
	for i in 8:
		var copy := _plates[i].duplicate() as Image
		copy.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
		var slot := Vector2i((i % 4) * tile_w, (i / 4) * tile_h)
		sheet.blit_rect(copy, Rect2i(Vector2i.ZERO, Vector2i(tile_w, tile_h)), slot)
	var path := _out_dir.path_join("contact_sheet.png")
	var err := sheet.save_png(path)
	print("PLATE saved %s size=%s err=%d" % [path, sheet.get_size(), err])
	_expect(err == OK, "failed to save contact_sheet.png")
