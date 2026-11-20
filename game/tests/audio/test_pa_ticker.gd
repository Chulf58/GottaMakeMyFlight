class_name TestPaTicker
extends GdUnitTestSuite
## Tests for PaWords translation/POT coverage and PaTicker layout, click-through,
## tween lifecycle, modal suppression, and BuildMenu stack_top positioning.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("pa_ticker_audio").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	PseudoLocale.disable()
	DemoMode.clear_override()
	IntroDialogue.shown_this_session = false
	if _audio != null:
		_audio.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func test_pa_words_are_in_pot_and_pseudolocalize_cleanly() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	assert_array(PotEntries.malformed(entries)).is_empty()
	assert_array(PotEntries.duplicates(entries)).is_empty()
	for id in PaWords.msgids():
		(
			assert_int(PotEntries.count(entries, PaWords.CONTEXT, id))
			. override_failure_message("Missing POT count for %s" % id)
			. is_equal(1)
		)
		(
			assert_int(PotEntries.complete(entries, PaWords.CONTEXT, id))
			. override_failure_message("Incomplete POT entry for %s" % id)
			. is_equal(1)
		)

	var flights := FlightSim.new()
	flights.add_flight("GMF101", PassengerTestWorld.starts_with(10, 1000), "C")
	PseudoLocale.enable(0.4)
	var lines := [
		PaWords.boarding(flights, "GMF101"),
		PaWords.final_call(flights, "GMF101"),
		PaWords.spill(),
		PaWords.fault(),
		PaWords.rush(),
		PaWords.queue_checkin(),
		PaWords.queue_security(),
		PaWords.close_call("Gotta Air", "Oslo", "C", "GMF101"),
		PaWords.close_call("Gotta Air", "Oslo", "", "GMF101"),
		PaWords.close_call("", "", "C", "GMF101"),
		PaWords.close_call_for(flights, "GMF101"),
		PaWords.star_milestone("4.0"),
	]
	for line in lines:
		assert_str(line).starts_with("[").not_contains("{")
	flights.free()


func test_pa_ticker_subscribes_clamps_width_and_kills_tween_on_replace_and_exit() -> void:
	var conns_before := _audio.pa_announced.get_connections().size()
	var port := SubViewport.new()
	port.size = Vector2i(420, 720)
	add_child(port)
	var ticker := PaTicker.new()
	port.add_child(ticker)
	assert_int(_audio.pa_announced.get_connections().size()).is_equal(conns_before + 1)
	var label := ticker.find_child("PAText", false, false) as Label
	assert_object(label).is_not_null()
	assert_int(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(ticker.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(ticker.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(ticker.visible).is_false()

	_audio.pa_announced.emit("PA: Short message.")
	assert_bool(ticker.visible).is_true()
	assert_str(ticker.text_shown()).is_equal("PA: Short message.")
	assert_float(ticker.size.x).is_less_equal(420.0 - 32.0 + 0.5)
	var first_tween: Tween = ticker._tween
	assert_object(first_tween).is_not_null()
	assert_bool(first_tween.is_valid()).is_true()

	# Second announcement kills prior tween and clamps width to viewport - 32.
	_audio.pa_announced.emit(
		"PA: A much longer announcement that must clamp to viewport width minus 32 px cleanly."
	)
	assert_bool(first_tween.is_valid()).is_false()
	var second_tween: Tween = ticker._tween
	assert_object(second_tween).is_not_null()
	assert_bool(second_tween.is_valid()).is_true()
	assert_str(ticker.text_shown()).contains("much longer announcement")
	assert_float(ticker.offset_right - ticker.offset_left).is_less_equal(420.0 - 32.0 + 0.5)

	# clear_now kills active tween; freeing kills any running tween and disconnects pa_announced.
	ticker.clear_now()
	assert_bool(second_tween.is_valid()).is_false()
	assert_object(ticker._tween).is_null()
	_audio.pa_announced.emit("PA: Exit cleanup.")
	var exit_tween: Tween = ticker._tween
	assert_bool(exit_tween.is_valid()).is_true()
	assert_bool(_audio.pa_announced.is_connected(ticker.show_announcement)).is_true()
	port.free()
	assert_bool(exit_tween.is_valid()).is_false()
	assert_int(_audio.pa_announced.get_connections().size()).is_equal(conns_before)


func test_pa_ticker_positions_above_build_menu_and_clears_on_modals_and_load() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1536, 864)
	add_child(port)
	var root := Node.new()
	port.add_child(root)
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 1000))
	var mode := BuildMode.new()
	mode.grid = grid
	mode.set_tool(BuildMode.Tool.NONE)
	root.add_child(mode)
	var menu := BuildMenu.new()
	menu.name = "BuildMenu"
	menu.build_mode = mode
	root.add_child(menu)
	var staff_panel := StaffPanel.new()
	staff_panel.name = "StaffPanel"
	staff_panel.staff = world.staff
	staff_panel.menu = menu
	root.add_child(staff_panel)
	var save_game := SaveGame.new()
	save_game.name = "SaveGame"
	root.add_child(save_game)
	var rating := AirportRating.new()
	root.add_child(rating)
	var baggage := BaggageSim.new()
	root.add_child(baggage)
	var desk := OfferDesk.new()
	desk.clock = world.clock
	desk.rating = rating
	desk.flights = world.flights
	desk.baggage = baggage
	root.add_child(desk)
	var offers := OfferPanel.new()
	offers.name = "OfferPanel"
	offers.desk = desk
	offers.flights = world.flights
	offers.clock = world.clock
	offers.build_mode = mode
	root.add_child(offers)

	var hud := PassengerHud.new()
	hud.name = "PassengerHud"
	hud.clock = world.clock
	hud.flights = world.flights
	hud.sim = world.sim
	hud.build_mode = mode
	hud.save_game = save_game
	hud.alert_settings_path = SaveTestKit.run_path("pa_ticker_alerts")
	hud.departures_settings_path = SaveTestKit.run_path("pa_ticker_dep")
	root.add_child(hud)

	var ticker := hud.get_node_or_null("PaTicker") as PaTicker
	assert_object(ticker).is_not_null()

	# Default bottom-centre above closed BuildMenu bar.
	_audio.pa_announced.emit("PA: Boarding now for GMF101 at Gate C.")
	assert_bool(ticker.visible).is_true()
	var default_bottom := BuildMenu.MARGIN + BuildMenu.BAR_H + HudLayout.GAP
	assert_float(-ticker.offset_bottom).is_equal_approx(default_bottom, 0.5)

	# Opening BuildMenu tray shifts ticker to 8 px above BuildMenu.stack_top().
	menu.press_category(0)
	hud.refresh()
	assert_bool(menu.is_tray_open()).is_true()
	assert_float(-ticker.offset_bottom).is_equal_approx(menu.stack_top() + HudLayout.GAP, 0.5)

	# Opening StaffPanel shifts ticker above StaffCard.
	menu.press_staff()
	await await_idle_frame()
	hud.refresh()
	var staff_card := staff_panel.get_node_or_null("StaffCard") as Control
	assert_object(staff_card).is_not_null()
	assert_bool(staff_card.visible).is_true()
	var expected_staff_bottom := (
		BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP + staff_card.size.y + HudLayout.GAP
	)
	assert_float(-ticker.offset_bottom).is_equal_approx(expected_staff_bottom, 0.5)
	menu.press_staff()

	# Opening FlightPlanner clears ticker immediately and suppresses new announcements while open.
	var planner := hud.find_child("FlightPlanner", false, false) as FlightPlanner
	assert_object(planner).is_not_null()
	planner.open()
	assert_bool(planner.is_open()).is_true()
	assert_bool(ticker.visible).is_false()
	_audio.pa_announced.emit("PA: Suppressed during planner.")
	assert_bool(ticker.visible).is_false()
	planner.close()

	# Camera-gated modal (_camera_gates > 0 via IntroDialogue) clears & suppresses ticker.
	_audio.pa_announced.emit("PA: Before intro modal.")
	assert_bool(ticker.visible).is_true()
	assert_bool(hud.open_intro()).is_true()
	assert_bool(ticker.visible).is_false()
	_audio.pa_announced.emit("PA: Suppressed during intro.")
	assert_bool(ticker.visible).is_false()
	hud.dismiss_intro()

	# Opening DemoEndCard clears ticker immediately.
	_audio.pa_announced.emit("PA: Before demo end.")
	assert_bool(ticker.visible).is_true()
	DemoMode.set_override_for_test(true)
	assert_bool(hud.demo_end_card.open()).is_true()
	assert_bool(ticker.visible).is_false()
	hud.demo_end_card.close()
	DemoMode.clear_override()

	# Opening OfferPanel suppresses and clears ticker.
	_audio.pa_announced.emit("PA: Another announcement.")
	assert_bool(ticker.visible).is_true()
	offers.open()
	hud.refresh()
	assert_bool(ticker.visible).is_false()
	offers.close()

	# Save load clears ticker immediately.
	_audio.pa_announced.emit("PA: Before load.")
	assert_bool(ticker.visible).is_true()
	save_game.loaded.emit(true)
	assert_bool(ticker.visible).is_false()

	DirAccess.remove_absolute(hud.alert_settings_path)
	DirAccess.remove_absolute(hud.departures_settings_path)
	port.free()
	world.free_all()
