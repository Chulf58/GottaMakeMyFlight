class_name TestScreensTranslation
extends GdUnitTestSuite
## The hints, the game menu, the intro, the mood overlay's toggle and the money
## card reach the screen through tr() (board T3). The profile is on before each
## piece is built, so a string set without tr() would show no leading bracket.

const C := Wallet.Category

var _kit: IncidentPanelKit
var _paths: Array[String] = []


func before_test() -> void:
	PseudoLocale.enable(0.4)
	_kit = null


func after_test() -> void:
	for path in _paths:
		DirAccess.remove_absolute(path)
	_paths.clear()
	if _kit != null:
		_kit.port.free()
	PseudoLocale.disable()


func _run_path(label: String) -> String:
	var path := SaveTestKit.run_path(label)
	_paths.append(path)
	return path


func test_the_hint_card_and_its_buttons_are_routed() -> void:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _run_path("screens_translation_hints")
	add_child(hints)
	auto_free(hints)
	for text in [
		hints.toggle_button().text,
		(hints.card().find_child("HintCaption", true, false) as Label).text,
	]:
		print("hints text: %s" % text)
		assert_str(text).starts_with("[")
	assert_str(hints.toggle_button().text).contains("Hints (H)")


func test_the_hint_sentences_come_through_the_profile() -> void:
	for id in HintRules.IDS:
		assert_str(HintRules.text(id)).starts_with("[")


func test_the_hint_msgids_match_the_rule_text() -> void:
	PseudoLocale.disable()
	var ids := HintRules.Words.new().msgids()
	for id in HintRules.IDS:
		assert_array(ids).contains([HintRules.TEXT[id]])
	assert_int(ids.size()).is_equal(HintRules.IDS.size())


func test_the_game_menu_and_the_question_are_routed() -> void:
	_kit = IncidentPanelKit.new()
	_kit.build(self)
	var menu := GameMenu.new()
	menu.director = _kit.director
	menu.clock = _kit.clock
	menu.save_game = _kit.save
	_kit.port.add_child(menu)
	menu.open()
	var texts: Array[String] = [menu.resume_button().text, menu.settings_button().text]
	texts.append(menu.incidents_switch().text)
	texts.append(menu.reset_hints_button().text)
	print("menu texts: %s" % [texts])
	for text in texts:
		assert_str(text).starts_with("[")
	assert_str(menu.reset_hints_button().text).contains("Reset hints")
	assert_str(menu.resume_button().text).contains("Resume (Esc)")
	menu.close()
	assert_bool(menu.ask_incidents()).is_true()
	var question := menu.question()
	assert_str(question.body_text()).starts_with("[")
	assert_str(question.body_text()).contains("press Esc, then Settings")
	assert_str(question.accept_button().text).starts_with("[")
	assert_str(question.decline_button().text).starts_with("[")


func test_the_intro_default_text_is_routed() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var dialog := IntroDialogue.new()
	port.add_child(dialog)
	print("intro beats: %s" % [dialog.beats()])
	assert_str(dialog.body_text()).starts_with("[")
	assert_str(dialog.beats()[1]).starts_with("[")
	assert_str(dialog.beats()[1]).contains("Shift+1/2/3 sets speed")
	assert_str(dialog.continue_button().text).starts_with("[")
	assert_str(dialog.continue_button().text).contains("Next (Space)")
	dialog.finish_reveal()
	dialog.continue_button().pressed.emit()
	assert_str(dialog.continue_button().text).starts_with("[")
	assert_str(dialog.continue_button().text).contains("Continue (Space)")
	assert_str(dialog.footer_text()).starts_with("[")
	for chip_lbl in dialog.chip_texts():
		assert_str(chip_lbl).starts_with("[")
	var plate := dialog.find_child("Name", true, false) as Label
	assert_str(plate.text).starts_with("[")
	assert_str((dialog.find_child("Title", true, false) as Label).text).starts_with("[")
	port.free()


func test_a_given_intro_text_is_used_as_it_is() -> void:
	var port := SubViewport.new()
	add_child(port)
	var dialog := IntroDialogue.new("A visit", "Someone wants to visit.", 400.0, true)
	port.add_child(dialog)
	assert_str(dialog.body_text()).is_equal("Someone wants to visit.")
	port.free()


func test_the_mood_overlay_toggle_legend_and_modes_are_routed() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var overlay := MoodOverlay.new()
	overlay.settings_path = _run_path("screens_translation_mood")
	overlay.sim = world.sim
	add_child(overlay)
	var toggle := overlay.find_child("MoodToggle", true, false) as Button
	var legend := overlay.find_child("MoodLegend", true, false) as Label
	assert_str(toggle.text).starts_with("[")
	assert_str(toggle.text).contains("Mood (M)")
	assert_str(legend.text).starts_with("[")
	for mode_name in MoodOverlay.MODE_NAMES:
		var button := overlay.find_child("Mode" + mode_name, true, false) as Button
		assert_str(button.text).starts_with("[")
		assert_str(button.text).contains(mode_name)
	# The overlay reads the sim every frame, so it goes before the world does.
	overlay.free()
	world.free_all()


func test_the_money_card_rows_and_heading_are_routed() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	var wallet := Wallet.new()
	var ledger := auto_free(DayLedger.new()) as DayLedger
	ledger.bind(wallet, clock)
	var rows := MoneySlot.rows(ledger, 30, 40)
	print("money rows: %d first: %s" % [rows.size(), rows[0][0]])
	assert_int(rows.size()).is_greater_equal(12)
	for row: Array in rows:
		assert_str(row[0]).starts_with("[")
	assert_str(MoneySlot.heading(ledger)).starts_with("[")
	assert_str(MoneySlot.heading(ledger)).contains("Today")


func test_the_offer_panel_heading_is_routed() -> void:
	var port := SubViewport.new()
	add_child(port)
	var desk := OfferDesk.new()
	var sim := FlightSim.new()
	sim.open_airport()
	port.add_child(desk)
	port.add_child(sim)
	var panel := OfferPanel.new()
	panel.desk = desk
	panel.flights = sim
	port.add_child(panel)
	var title := panel.find_child("OfferTitle", true, false) as Label
	assert_str(title.text).starts_with("[")
	assert_str(title.text).contains("Airline Contracts")
	port.free()
