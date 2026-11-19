extends SceneTree
## Windowed 1920x1080 plates for Demo Scope & Cut Line (board D1b, decision
## demo-scope-and-cut-line-d1-cap-playable-unlocks-at-tier-2-1):
##   1. tools/blender/out/demo-scope/tier3_teaser_menu.png — BuildMenu tray in
##      demo mode showing unlocked Tier 2 alongside greyed Tier 3 "In the full
##      game" teaser cards, with Tier 4 cards absent and every visible category
##      button verified non-empty.
##   2. tools/blender/out/demo-scope/day5_end_card.png — DemoEndCard triggered
##      at the end of Day 5 over the built starter terminal with non-zero 5-day
##      stats, ruled copy, and Wishlist on Steam / Back to Title buttons.
##
## Windowed, from the repo root (hold the single windowed Godot slot):
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/demo_end_card_probe.gd < /dev/null
## Exits 0 on success with zero engine ERROR lines; prints PROBE_INVALID and
## exits 1 on any failed check.

const MAIN := "res://main/main.tscn"
const OUT_DIR := "res://../tools/blender/out/demo-scope"
const SCREEN := Vector2i(1920, 1080)
const MARGIN := 8.0
const MAX_OPEN_FRAMES := 600
const SETTLE_FRAMES := 12


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_size(SCREEN)
	await _frames(10)
	if root.size != SCREEN:
		_invalid("window size is %s, expected %s" % [root.size, SCREEN])
		return
	DemoMode.set_override_for_test(true)
	var main: Node3D = (load(MAIN) as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d demo=%s" % [world_seed, DemoMode.is_demo()])
	root.add_child(main)
	await _frames(6)
	var hud := main.get_node("PassengerHud") as PassengerHud
	hud.press_starter_terminal()
	var staff := main.get_node("Staff") as StaffSim
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	staff.hire(StaffMember.Role.SECURITY)
	var flights := main.get_node("FlightSim") as FlightSim
	clock.set_speed(3)
	clock.set_paused(false)
	for _i in MAX_OPEN_FRAMES:
		if flights.opened_tick >= 0:
			break
		await process_frame
	if flights.opened_tick < 0:
		_invalid("airport did not open within %d frames" % MAX_OPEN_FRAMES)
		return
	# Let the Day-1 starter flight fly and board real passengers cleanly.
	for contract_id in flights.active_contract_ids():
		flights.end_contract(contract_id)
	var guard := 0
	while not flights.flight_ids().is_empty() and guard < 4000:
		clock.set_paused(false)
		clock.advance(SimClock.STEP * 5.0)
		guard += 1
	if not flights.flight_ids().is_empty():
		_invalid("starter flight did not finish within step budget")
		return
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	while unlocks.made_total() < 55:
		unlocks.note_made()
	for _i in 40:
		rating.record_passenger(clock.tick, true, 96)
	unlocks.check()
	if not await _capture_teaser_menu(main, unlocks):
		return
	if not await _capture_day5_end_card(main, hud, clock, rating, unlocks):
		return
	DemoMode.clear_override()
	print("PROBE done")
	quit(0)


func _capture_teaser_menu(main: Node, unlocks: BuildUnlocks) -> bool:
	var menu := main.get_node("BuildMenu") as BuildMenu
	var bar_problem := _all_bar_buttons_problem(menu)
	if bar_problem != "":
		_invalid(bar_problem)
		return false
	var landside_cat := BuildMenu.category_of(BuildMode.Tool.SURFACE_LOT)
	menu.end_grant_hold()
	menu.press_category(landside_cat)
	await _frames(SETTLE_FRAMES)
	var problem := _teaser_menu_problem(menu, unlocks)
	if problem != "":
		_invalid(problem)
		return false
	var image := root.get_texture().get_image()
	if image.get_size() != SCREEN:
		_invalid("tier3_teaser_menu image is %s, expected %s" % [image.get_size(), SCREEN])
		return false
	if not _save(image, "tier3_teaser_menu.png"):
		_invalid("failed to save tier3_teaser_menu.png")
		return false
	menu.close_for_modal()
	return true


func _all_bar_buttons_problem(menu: BuildMenu) -> String:
	var checked := 0
	for i in BuildMenu.categories().size():
		if i == BuildMenu.remove_category():
			continue
		var btn := menu.category_button(i)
		if not btn.visible:
			continue
		menu.press_category(i)
		var start := menu.open_category()
		if not menu.is_tray_open() or start == BuildMenu.NO_CATEGORY:
			return "bar button %s did not open a tray" % btn.name
		for _step in 6:
			var page := menu.open_category()
			var visible_cards := 0
			for tool in BuildMenu.categories()[page]["tools"]:
				if menu.card(tool).is_visible_in_tree():
					visible_cards += 1
			if visible_cards == 0:
				return (
					"category page %d (%s) opened an empty tray"
					% [page, BuildMenu.categories()[page]["name"]]
				)
			var row := menu.card(BuildMenu.categories()[page]["tools"][0]).get_parent()
			var next_btn := row.find_child("CardNext", true, false) as Button
			if next_btn == null or not next_btn.visible:
				break
			next_btn.pressed.emit()
			if menu.open_category() == start:
				break
		checked += 1
	menu.close_for_modal()
	print("PROBE bar_categories_verified=%d" % checked)
	return "" if checked > 0 else "no visible bar categories found"


func _teaser_menu_problem(menu: BuildMenu, unlocks: BuildUnlocks) -> String:
	if unlocks.tier() != DemoMode.MAX_PLAYABLE_TIER:
		return "expected tier %d, got %d" % [DemoMode.MAX_PLAYABLE_TIER, unlocks.tier()]
	var tier4_problem := _hidden_tier4_problem(menu)
	if tier4_problem != "":
		return tier4_problem
	var layout_screen := Rect2(
		Vector2.ONE * MARGIN, root.get_visible_rect().size - Vector2.ONE * 2.0 * MARGIN
	)
	var curb := menu.card(BuildMode.Tool.CURB)
	var lot := menu.card(BuildMode.Tool.SURFACE_LOT)
	var gate := menu.card(BuildMode.Tool.LOT_GATE)
	var multi := menu.card(BuildMode.Tool.MULTI_STOREY)
	print(
		(
			"PROBE menu curb_vis=%s lot_vis=%s gate_vis=%s multi_vis=%s"
			% [
				curb.is_visible_in_tree(),
				lot.is_visible_in_tree(),
				gate.is_visible_in_tree(),
				multi.is_visible_in_tree(),
			]
		)
	)
	for card: Button in [curb, lot, gate]:
		var rect := card.get_global_rect()
		print("PROBE card %s rect=%s tint=%s" % [card.name, rect, card.modulate])
		if not card.is_visible_in_tree() or not layout_screen.encloses(rect):
			return "card %s is outside viewport bounds (%s)" % [card.name, rect]
		var clip := _labels_clip_problem(card)
		if clip != "":
			return clip
	return _teaser_cards_problem([lot, gate])


func _hidden_tier4_problem(menu: BuildMenu) -> String:
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		if BuildUnlocks.tier_of(tool) >= DemoMode.HIDDEN_MIN_TIER:
			var hidden := menu.card(tool)
			if hidden != null and hidden.is_visible_in_tree():
				return "tier 4 card %s is still visible" % BuildMode.Tool.find_key(tool)
	return ""


func _teaser_cards_problem(teasers: Array[Button]) -> String:
	for teaser: Button in teasers:
		if not teaser.modulate.is_equal_approx(BuildMenu.LOCKED_TINT):
			return "teaser %s is not greyed with LOCKED_TINT" % teaser.name
		var labels := teaser.find_children("*", "Label", true, false)
		var last := (labels[labels.size() - 1] as Label).text
		if last != BuildUnlocks.IN_FULL_GAME_TEXT:
			return "teaser %s last line is '%s', expected 'In the full game'" % [teaser.name, last]
	return ""


func _capture_day5_end_card(
	main: Node, hud: PassengerHud, clock: SimClock, rating: AirportRating, unlocks: BuildUnlocks
) -> bool:
	var menu := main.get_node("BuildMenu") as BuildMenu
	var offer_panel := main.get_node("OfferPanel") as OfferPanel
	var finances := main.get_node("Finances") as Finances
	finances.wallet.credit(5800, Wallet.Category.FEES)
	while unlocks.made_total() < 142:
		unlocks.note_made()
	var rollover := GameCalendar.day_start(DemoMode.MAX_DEMO_DAY, clock.epoch)
	for _i in 40:
		rating.record_passenger(rollover - 20, true, 94)
	# Open OfferPanel (takes exclusive ClockHolds turn) and a BuildMenu tray, let
	# BuildSession acquire its hold on a frame, then yield to 3x play as Space does.
	offer_panel.open()
	menu.press_category(BuildMenu.category_of(BuildMode.Tool.SURFACE_LOT))
	await process_frame
	clock.tick = rollover - 2
	clock.set_paused(false)
	clock.set_speed(3)
	menu.build_session.sync()
	print(
		"PROBE before_rollover paused=%s speed=%d tick=%d" % [clock.paused, clock.speed, clock.tick]
	)
	if clock.paused:
		_invalid("clock stayed paused after yielding holds before rollover")
		return false
	for _i in 30:
		if hud.demo_end_card.is_open():
			break
		await process_frame
	await _frames(SETTLE_FRAMES)
	var problem := _end_card_problem(hud.demo_end_card, menu, offer_panel, clock, rollover)
	if problem != "":
		_invalid(problem)
		return false
	var image := root.get_texture().get_image()
	if image.get_size() != SCREEN:
		_invalid("day5_end_card image is %s, expected %s" % [image.get_size(), SCREEN])
		return false
	if not _save(image, "day5_end_card.png"):
		_invalid("failed to save day5_end_card.png")
		return false
	return true


func _end_card_problem(
	end_card: DemoEndCard, menu: BuildMenu, offer_panel: OfferPanel, clock: SimClock, rollover: int
) -> String:
	var stats := end_card.summary_stats()
	print(
		(
			"PROBE end_card open=%s paused=%s tick=%d rollover=%d tray=%s offers=%s stats=%s"
			% [
				end_card.is_open(),
				clock.paused,
				clock.tick,
				rollover,
				menu.is_tray_open(),
				offer_panel.is_open(),
				stats,
			]
		)
	)
	if not end_card.is_open() or not clock.paused or clock.tick != rollover:
		return "DemoEndCard did not pause synchronously on rollover tick %d" % rollover
	if menu.is_tray_open() or offer_panel.is_open():
		return "an open HUD sheet or tray remained open under DemoEndCard"
	if int(stats["passengers_made"]) <= 0 or int(stats["cash_earned"]) <= 0:
		return "DemoEndCard stats must be non-zero, got %s" % [stats]
	var panel := end_card.panel()
	var layout_screen := Rect2(
		Vector2.ONE * MARGIN, root.get_visible_rect().size - Vector2.ONE * 2.0 * MARGIN
	)
	var rect := panel.get_global_rect()
	print("PROBE end_card panel_rect=%s screen=%s" % [rect, layout_screen])
	if not panel.is_visible_in_tree() or not rect.has_area() or not layout_screen.encloses(rect):
		return "DemoEndCard panel %s is outside viewport bounds %s" % [rect, layout_screen]
	var own := panel.get_parent().get_parent() as CanvasLayer
	for node in root.find_children("*", "CanvasLayer", true, false):
		if node != own and (node as CanvasLayer).layer >= own.layer:
			return "CanvasLayer %s (%d) occludes DemoEndCard" % [node.name, node.layer]
	return _labels_clip_problem(panel)


func _labels_clip_problem(container: Control) -> String:
	for node in container.find_children("*", "Label", true, false):
		var label := node as Label
		if not label.is_visible_in_tree() or label.text == "":
			continue
		var font := label.get_theme_font(&"font")
		var font_size := label.get_theme_font_size(&"font_size")
		var shown := label.atr(label.text)
		if label.max_lines_visible > 0 and label.size.x > 0.0:
			var lines := HudLayout.line_count(shown, font, font_size, label.size.x + 1.0)
			if lines > label.max_lines_visible:
				return (
					"label %s ('%s') wraps to %d lines > %d"
					% [label.name, shown, lines, label.max_lines_visible]
				)
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.size.x > 0.0:
			var needed := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if needed > label.size.x + 2.0:
				return (
					"label %s ('%s') width %.1f exceeds %.1f"
					% [label.name, shown, needed, label.size.x]
				)
	return ""


func _save(image: Image, file: String) -> bool:
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(file))
	var err := image.save_png(path)
	print("PROBE plate %s err=%d size=%s" % [path, err, image.get_size()])
	return err == OK


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	DemoMode.clear_override()
	print("PROBE_INVALID %s" % why)
	quit(1)
