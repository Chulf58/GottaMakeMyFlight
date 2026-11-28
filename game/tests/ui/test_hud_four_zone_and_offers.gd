class_name TestHudFourZoneAndOffers
extends GdUnitTestSuite
## Acceptance tests for:
## - HUD 4-zone enforcement (8f51e09c parts 1-4, amended by fa6e54ab):
##   AlertStack toasts, bottom-center 128x128 PhoneRingCue + BuildMenu/StatusCard/
##   PaTicker clearance, Pause/Settings Reset hints, and bottom-right
##   PassengerInspect / BuiltItemCard docking.
## - Airline Offers Day-1 auto-pop once + disabled stretch-card gating (944a44c9).

const SEED := 4_070_093
const LAYOUTS := [Vector2i(1920, 1080), Vector2i(1536, 864), Vector2i(1280, 720)]

var _port: SubViewport
var _main: Node
var _hud: PassengerHud
var _alert_path := SaveTestKit.run_path("four_zone_alerts")
var _departures_path := SaveTestKit.run_path("four_zone_departures")
var _mood_path := SaveTestKit.run_path("four_zone_mood")
var _hints_path := SaveTestKit.run_path("four_zone_hints")
var _shown_before := false


func before() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = true
	_port = SubViewport.new()
	_port.size = LAYOUTS[0]
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_hud.alert_settings_path = _alert_path
	_hud.departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	_port.add_child(_main)
	await _settle()


func after() -> void:
	IntroDialogue.shown_this_session = _shown_before
	if _port != null:
		_port.free()
		_port = null
	_main = null
	_hud = null
	for path in [_alert_path, _departures_path, _mood_path, _hints_path]:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)


func after_test() -> void:
	if _main == null:
		return
	var menu := _main.get_node("GameMenu") as GameMenu
	menu.close()
	var offers := _main.get_node("OfferPanel") as OfferPanel
	offers.close()
	var build_menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_tool(BuildMode.Tool.NONE)
	if build_menu.is_tray_open():
		build_menu.press_category(build_menu.open_category())
	if build_menu.staff_open:
		build_menu.press_staff()
	var stack := _stack()
	if stack != null:
		stack.reset()
	var ticker := _hud.get_node_or_null("PaTicker") as PaTicker
	if ticker != null:
		ticker.clear_now()
	_hud._built.clear()
	_hud.views.select(0)
	_hud.set_debug_open(false)
	_port.size = LAYOUTS[0]
	await _settle()


func _settle(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func test_toasts_route_into_top_right_alert_stack_with_auto_dismiss_and_history() -> void:
	var save := _main.get_node("SaveGame") as SaveGame
	var stack := _stack()
	assert_object(stack).is_not_null()

	var toast := AchievementToast.show_unlocked(
		"FIRST_FLIGHT", "First Departure", "Your first flight took off.", save
	)
	await _settle()
	var ach_card := stack.notice_card(AchievementToast.RAIL_KEY)
	assert_object(ach_card).is_not_null()
	assert_bool(stack.is_ancestor_of(ach_card)).is_true()
	assert_bool(ach_card.is_visible_in_tree()).is_true()
	assert_float(ach_card.get_global_rect().position.x).is_greater_equal(
		float(LAYOUTS[0].x - HudLayout.MARGIN - HudLayout.RAIL_W) - 1.0
	)
	assert_bool(stack.history_lines()[0].contains("First Departure")).is_true()

	var cert_layer := BigFirsts.show_certification(2, "Regional Terminal", 3000, 5, save)
	await _settle()
	var cert_card := stack.notice_card(BigFirsts.CERTIFICATION_RAIL_KEY)
	assert_object(cert_card).is_not_null()
	assert_bool(stack.is_ancestor_of(cert_card)).is_true()
	assert_bool(cert_card.is_visible_in_tree()).is_true()
	assert_bool(ach_card.get_global_rect().intersects(cert_card.get_global_rect())).is_false()
	assert_bool(stack.history_lines()[0].contains("Regional Terminal")).is_true()

	stack.advance(AchievementToast.TOAST_SECONDS + 0.1)
	await _settle()
	assert_object(stack.notice_card(AchievementToast.RAIL_KEY)).is_null()
	assert_object(save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME))).is_null()
	assert_object(stack.notice_card(BigFirsts.CERTIFICATION_RAIL_KEY)).is_not_null()

	stack.advance(BigFirsts.CERTIFICATION_TOAST_SECONDS + 0.1)
	await _settle()
	assert_object(stack.notice_card(BigFirsts.CERTIFICATION_RAIL_KEY)).is_null()
	assert_object(cert_layer).is_null()


func test_phone_ring_cue_bottom_center_128_clears_build_menu_and_pa_ticker() -> void:
	assert_float(IntroDialogue.PhoneRingCue.CUE_SIZE).is_equal(128.0)
	assert_float(IntroDialogue.PhoneRingCue.ICON_SIZE).is_equal(88.0)
	var flights := _main.get_node("FlightSim") as FlightSim
	if flights.opened_tick < 0:
		flights.open_airport()
	var offers_btn := (_main.get_node("OfferPanel") as OfferPanel).toggle_button()
	var ticker := _hud.get_node("PaTicker") as PaTicker
	var build_menu := _main.get_node("BuildMenu") as BuildMenu
	var bar := build_menu.bar()
	var flight_panel := _hud.find_child("FlightPanel", true, false) as Control

	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		var cue := IntroDialogue.PhoneRingCue.new()
		_hud.add_child(cue)
		cue.start_ring(false, false, 0.0)
		ticker.show_announcement("PA: Boarding now at Gate C.")
		await _settle()

		# Collapsed BuildMenu bar: PhoneRingCue sits bottom-center 76 px above bottom.
		var cue_rect := cue.get_global_rect()
		var bar_rect := bar.get_global_rect()
		var ticker_rect := ticker.get_global_rect()
		var offers_rect := offers_btn.get_global_rect()
		var panel_rect := flight_panel.get_global_rect()
		assert_bool(cue.is_visible_in_tree()).is_true()
		assert_float(cue.size.x).is_equal_approx(128.0, 0.5)
		assert_float(cue.size.y).is_equal_approx(128.0, 0.5)
		assert_float(absf(cue_rect.get_center().x - float(layout.x) * 0.5)).is_less_equal(1.0)
		assert_float(-cue.offset_bottom).is_equal_approx(IntroDialogue.PhoneRingCue.CUE_BOTTOM, 0.5)
		assert_bool(cue_rect.intersects(bar_rect)).is_false()
		assert_bool(cue_rect.intersects(ticker_rect)).is_false()
		assert_bool(cue_rect.intersects(offers_rect)).is_false()
		assert_bool(cue_rect.intersects(panel_rect)).is_false()

		# With StatusCard visible: PhoneRingCue lifts above StatusCard and PaTicker lifts above cue.
		build_menu._on_wages_paid(60, 0)
		build_menu.refresh_preview()
		await _settle()

		cue_rect = cue.get_global_rect()
		offers_rect = offers_btn.get_global_rect()
		panel_rect = flight_panel.get_global_rect()
		ticker_rect = ticker.get_global_rect()
		var status_rect := build_menu.status_card().get_global_rect()
		bar_rect = bar.get_global_rect()

		assert_bool(cue.is_visible_in_tree()).is_true()
		assert_float(cue.size.x).is_equal_approx(128.0, 0.5)
		assert_float(cue.size.y).is_equal_approx(128.0, 0.5)
		assert_float(absf(cue_rect.get_center().x - float(layout.x) * 0.5)).is_less_equal(1.0)
		assert_bool(cue_rect.intersects(offers_rect)).is_false()
		assert_bool(cue_rect.intersects(panel_rect)).is_false()
		assert_bool(cue_rect.intersects(ticker_rect)).is_false()
		assert_bool(cue_rect.intersects(status_rect)).is_false()
		assert_bool(cue_rect.intersects(bar_rect)).is_false()
		assert_bool(ticker_rect.intersects(status_rect)).is_false()
		assert_bool(ticker_rect.intersects(bar_rect)).is_false()
		assert_bool(status_rect.intersects(bar_rect)).is_false()
		assert_float(cue_rect.end.y).is_less_equal(status_rect.position.y + 0.5)
		assert_float(ticker_rect.end.y).is_less_equal(cue_rect.position.y + 0.5)

		build_menu.end_grant_hold()
		cue.stop_ring()
		cue.free()
		ticker.clear_now()


func test_reset_hints_lives_in_game_menu_settings_and_not_in_left_column() -> void:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _hints_path
	hints.hud = _hud
	hints.scene_root = _main
	_hud.add_child(hints)
	await _settle()

	assert_object(_main.find_child("HintsReset", true, false)).is_null()
	hints._mark_seen(HintRules.PLACE_CHECKIN)
	hints.set_enabled(false)
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_true()
	assert_bool(hints.is_enabled()).is_false()

	var game_menu := _main.get_node("GameMenu") as GameMenu
	game_menu.hints = hints
	assert_bool(game_menu.open()).is_true()
	game_menu.press_settings()
	await _settle()

	var reset_btn := game_menu.reset_hints_button()
	assert_object(reset_btn).is_not_null()
	assert_bool(reset_btn.is_visible_in_tree()).is_true()
	assert_str(reset_btn.text).is_equal("Reset hints")
	reset_btn.pressed.emit()
	assert_bool(hints.is_enabled()).is_true()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()

	game_menu.close()
	hints.free()


func test_inspect_and_built_item_card_dock_bottom_right_with_zero_overlaps() -> void:
	_hud.press_starter_terminal()
	var pax_sim := _main.get_node("PassengerSim") as PassengerSim
	var pid := pax_sim.spawn_now("GMF101")
	_hud.views.selected_id = pid
	var build_menu := _main.get_node("BuildMenu") as BuildMenu
	var bar := build_menu.bar()
	var inspect := _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	var stack := _stack()
	var notice_card := OfferPanel.coral_card(&"n_inspect", "Notice", "Details")
	stack.post_notice(&"n_inspect", notice_card, 0.0, "Notice", "Details")

	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		_hud.views.selected_id = pid
		_hud._built.clear()
		_hud.refresh()
		await _settle()
		var ir := inspect.get_global_rect()
		var br := bar.get_global_rect()
		var sr := stack.room_rect()
		assert_bool(inspect.is_visible_in_tree()).is_true()
		assert_float(ir.end.x).is_equal_approx(float(layout.x - HudLayout.MARGIN), 1.0)
		assert_float(ir.position.x).is_greater_equal(float(layout.x) * 0.5)
		assert_bool(ir.intersects(br)).is_false()
		if sr.has_area():
			assert_bool(ir.intersects(sr)).is_false()
			assert_float(sr.end.y).is_less_equal(ir.position.y - float(HudLayout.GROUP_GAP) + 1.0)
		var left_card := (_main.get_node("StaffPanel") as StaffPanel).hint_card()
		if left_card.is_visible_in_tree():
			assert_bool(ir.intersects(left_card.get_global_rect())).is_false()

		# Switch to BuiltItemCard with BuildMenu tray open -> still bottom-right & clear.
		_hud.views.selected_id = 0
		build_menu.press_category(0)
		_hud._built.select_object(pax_sim.layout.desks[0])
		_hud.refresh()
		await _settle()
		var b_rect := inspect.get_global_rect()
		var tray_rect := build_menu.tray().get_global_rect()
		assert_bool(inspect.built_card.is_visible_in_tree()).is_true()
		assert_float(b_rect.end.x).is_equal_approx(float(layout.x - HudLayout.MARGIN), 1.0)
		assert_bool(b_rect.intersects(tray_rect)).is_false()
		assert_bool(b_rect.intersects(bar.get_global_rect())).is_false()
		build_menu.press_category(0)

		# Open DebugPanel alongside PassengerInspect -> still clear of DebugCorner & DebugPanel.
		_hud._built.clear()
		_hud.views.selected_id = pid
		_hud.set_debug_open(true)
		_hud.refresh()
		await _settle()
		var debug_corner := _hud.find_child("DebugCorner", true, false) as Control
		var debug_panel := _hud.find_child("DebugPanel", true, false) as Control
		var d_ir := inspect.get_global_rect()
		assert_bool(inspect.is_visible_in_tree()).is_true()
		assert_bool(debug_panel.is_visible_in_tree()).is_true()
		assert_bool(d_ir.intersects(debug_corner.get_global_rect())).is_false()
		assert_bool(d_ir.intersects(debug_panel.get_global_rect())).is_false()
		assert_bool(d_ir.intersects(bar.get_global_rect())).is_false()
		_hud.set_debug_open(false)


func test_day1_offer_panel_auto_pops_once_and_gates_stretch_card() -> void:
	var fresh_port: SubViewport = auto_free(SubViewport.new())
	fresh_port.size = LAYOUTS[0]
	add_child(fresh_port)
	var fresh_main: Node = load(SaveTestKit.MAIN).instantiate()
	(fresh_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(fresh_main.get_node("SimClock") as SimClock).set_paused(true)
	var fresh_hud := fresh_main.get_node("PassengerHud") as PassengerHud
	var a_path := SaveTestKit.run_path("four_zone_fresh_alerts")
	var d_path := SaveTestKit.run_path("four_zone_fresh_deps")
	fresh_hud.alert_settings_path = a_path
	fresh_hud.departures_settings_path = d_path
	fresh_port.add_child(fresh_main)
	await _settle()

	var flights := fresh_main.get_node("FlightSim") as FlightSim
	var desk := fresh_main.get_node("OfferDesk") as OfferDesk
	var panel := fresh_main.get_node("OfferPanel") as OfferPanel
	var gate := fresh_main.get_node("AirportGate") as AirportGate
	var fresh_menu := fresh_main.get_node("GameMenu") as GameMenu
	var fresh_save := fresh_main.get_node("SaveGame") as SaveGame

	# Closed airport: Offers hidden and sheet closed.
	assert_bool(panel.toggle_button().visible).is_false()
	assert_bool(panel.is_open()).is_false()

	# Open airport on Day 1 while a modal (GameMenu) is open -> defers until modal closes.
	fresh_hud.press_starter_terminal()
	StaffTestKit.staff_all(fresh_main.get_node("Staff"))
	assert_bool(fresh_menu.open()).is_true()
	assert_bool(gate.open()).is_true()
	await _settle()
	assert_bool(panel.is_open()).is_false()
	assert_bool(desk.board.is_day1_intro_shown()).is_false()

	fresh_menu.close()
	await _settle()
	assert_bool(panel.is_open()).is_true()
	assert_bool(desk.board.is_day1_intro_shown()).is_true()
	var banner := panel.intro_banner()
	assert_object(banner).is_not_null()
	assert_bool(banner.is_visible_in_tree()).is_true()
	assert_str(panel.intro_banner_text()).is_equal(
		"Accept airlines that fit your gates. Each signed contract sends flights every day."
	)

	# Close and reload through SaveGame -> day1_intro_shown=true persists and never re-pops;
	# loading a Day-1 snapshot with day1_intro_shown=false also stays closed on load.
	panel.close()
	SaveTestKit.step(fresh_main)
	var saved_world: Dictionary = JSON.parse_string(JSON.stringify(fresh_save.snapshot()))
	assert_bool(saved_world.is_empty()).is_false()
	assert_bool(bool(saved_world["offers"].get("day1_intro_shown", false))).is_true()
	assert_bool(fresh_save.load_world(saved_world)).is_true()
	await _settle()
	assert_bool(desk.board.is_day1_intro_shown()).is_true()
	assert_bool(panel.is_open()).is_false()
	panel._on_airport_opened(flights.opened_tick)
	await _settle()
	assert_bool(panel.is_open()).is_false()

	var unshown_world := saved_world.duplicate(true)
	unshown_world["offers"]["day1_intro_shown"] = false
	assert_bool(fresh_save.load_world(unshown_world)).is_true()
	await _settle()
	assert_bool(desk.board.is_day1_intro_shown()).is_false()
	assert_bool(panel.is_open()).is_false()

	# Non-fitting stretch offer (runway too small) disables Accept + shows yellow chip;
	# upgrading runway re-enables Accept and removes the chip.
	var records := TestOfferBoard.day_records(0, [600, 900, 1200])
	records[1]["plane_size"] = PlaneClasses.MEDIUM
	records[1]["booked_passengers"] = 30
	records[1]["fee_per_passenger"] = 25
	assert_bool(desk.board.from_snapshot(TestOfferBoard.save_of(records))).is_true()
	panel.open()
	await _settle()
	var stretch_btn := panel.accept_button("O0N2")
	var chip := panel.requirement_chip("O0N2")
	assert_bool(stretch_btn.disabled).is_true()
	assert_object(chip).is_not_null()
	assert_bool(chip.is_visible_in_tree()).is_true()
	assert_str(panel.requirement_text("O0N2")).is_equal(FlightFit.RUNWAY_TEXT % PlaneClasses.MEDIUM)

	# Upgrade runway -> planning_changed re-enables Accept and hides the yellow chip.
	flights.runway.size = PlaneClasses.MEDIUM
	await _settle()
	assert_bool(stretch_btn.disabled).is_false()
	assert_bool(chip.visible).is_false()

	# Also verify stretch card disables Accept and displays the yellow blocker chip.
	panel.accept_button("O0N1").pressed.emit()
	var gate_clash_records := TestOfferBoard.day_records(0, [600, 900, 1200])
	assert_bool(desk.board.from_snapshot(TestOfferBoard.save_of(gate_clash_records))).is_true()
	await _settle()
	assert_bool(panel.accept_button("O0N1").disabled).is_true()
	assert_bool(panel.requirement_chip("O0N1").is_visible_in_tree()).is_true()
	assert_str(panel.requirement_text("O0N1")).is_equal(OfferPanel.NEEDS_GATE_TEXT)

	fresh_port.free()
	for p in [a_path, d_path, a_path + ".tmp", d_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func test_day2_airport_opening_does_not_auto_open_offer_panel() -> void:
	var day2_port: SubViewport = auto_free(SubViewport.new())
	day2_port.size = LAYOUTS[1]
	add_child(day2_port)
	var day2_main: Node = load(SaveTestKit.MAIN).instantiate()
	var clock := day2_main.get_node("SimClock") as SimClock
	clock.seed_rng(SEED)
	clock.set_paused(true)
	var day2_hud := day2_main.get_node("PassengerHud") as PassengerHud
	var a_path := SaveTestKit.run_path("four_zone_day2_alerts")
	var d_path := SaveTestKit.run_path("four_zone_day2_deps")
	day2_hud.alert_settings_path = a_path
	day2_hud.departures_settings_path = d_path
	day2_port.add_child(day2_main)
	await _settle()

	var flights := day2_main.get_node("FlightSim") as FlightSim
	var desk := day2_main.get_node("OfferDesk") as OfferDesk
	var panel := day2_main.get_node("OfferPanel") as OfferPanel
	var gate := day2_main.get_node("AirportGate") as AirportGate

	day2_hud.press_starter_terminal()
	StaffTestKit.staff_all(day2_main.get_node("Staff"))
	assert_bool(gate.open()).is_true()
	await _settle()
	assert_bool(panel.is_open()).is_true()
	panel.close()
	assert_bool(desk.board.is_day1_intro_shown()).is_true()

	# Roll across midnight into Day 2: new Day-2 offers arrive, sheet stays closed.
	clock.tick = GameCalendar.day_start(1, clock.epoch) - 1
	SaveTestKit.step(day2_main)
	await _settle()
	assert_int(GameCalendar.day_of(flights.tick, flights.epoch)).is_equal(1)
	assert_int(desk.board.day_offer_count(1)).is_equal(OfferBoard.OFFERS_PER_DAY)
	assert_bool(panel.is_open()).is_false()

	# Even if day1_intro_shown / has_been_opened were false on Day 2, opening never pops.
	desk.board._day1_intro_shown = false
	panel.has_been_opened = false
	panel._on_airport_opened(flights.opened_tick)
	await _settle()
	assert_bool(panel.is_open()).is_false()
	assert_bool(desk.board.is_day1_intro_shown()).is_false()

	day2_port.free()
	for p in [a_path, d_path, a_path + ".tmp", d_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
