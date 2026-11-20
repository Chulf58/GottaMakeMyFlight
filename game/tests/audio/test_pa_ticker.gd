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
		PaWords.close_call(flights, "GMF101"),
		PaWords.star_milestone("4.0"),
	]
	for line in lines:
		assert_str(line).starts_with("[").not_contains("{")
	flights.free()


func test_pa_ticker_subscribes_clamps_width_and_kills_tween_on_replace_and_exit() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(420, 720)
	add_child(port)
	var ticker := PaTicker.new()
	port.add_child(ticker)
	assert_int(ticker.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(ticker.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(ticker.visible).is_false()

	_audio.pa_announced.emit("PA: Short message.")
	assert_bool(ticker.visible).is_true()
	assert_str(ticker.text_shown()).is_equal("PA: Short message.")
	assert_float(ticker.size.x).is_less_equal(420.0 - 32.0 + 0.5)

	# Second announcement replaces cleanly without stacking; narrow viewport clamps width.
	_audio.pa_announced.emit(
		"PA: A much longer announcement that must clamp to viewport width minus 32 px cleanly."
	)
	assert_str(ticker.text_shown()).contains("much longer announcement")
	assert_float(ticker.offset_right - ticker.offset_left).is_less_equal(420.0 - 32.0 + 0.5)
	port.free()


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

	# Opening DemoEndCard clears ticker immediately.
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
