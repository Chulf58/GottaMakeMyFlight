class_name TestHelpSheet
extends GdUnitTestSuite
## Help & Hints (H) handbook sheet tests (decision
## interactive-dialog-chips-and-help-hints-handbook-sheet, 257fbadd).

var _port: SubViewport
var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("help_sheet")
	DirAccess.remove_absolute(_path)
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)


func after_test() -> void:
	_port.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _hints() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	_port.add_child(hints)
	return hints


func test_help_button_and_h_key_open_and_close_help_sheet() -> void:
	var hints := _hints()
	var sheet := hints.help_sheet()
	assert_object(sheet).is_not_null()
	assert_bool(sheet.is_open()).is_false()
	assert_str(hints.toggle_button().text).is_equal("Help & Hints (H)")

	# Left-HUD button toggles HelpSheet open and closed.
	hints.toggle_button().pressed.emit()
	assert_bool(sheet.is_open()).is_true()
	assert_bool(hints.toggle_button().button_pressed).is_true()

	# [X] button closes it.
	sheet.close_button().pressed.emit()
	assert_bool(sheet.is_open()).is_false()
	assert_bool(hints.toggle_button().button_pressed).is_false()

	# Pressing H opens and closes it via viewport shortcut input.
	_port.push_input(_key(KEY_H))
	assert_bool(sheet.is_open()).is_true()
	_port.push_input(_key(KEY_H))
	assert_bool(sheet.is_open()).is_false()

	# Pressing Esc closes it.
	_port.push_input(_key(KEY_H))
	assert_bool(sheet.is_open()).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(sheet.is_open()).is_false()


func test_help_sheet_tabs_show_guide_and_dynamic_past_calls() -> void:
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	_port.add_child(unlocks)
	for i in 30:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 25:
		pax.outcome.emit(i, true)
	unlocks.check()
	assert_int(unlocks.tier()).is_equal(2)
	unlocks.mark_dialog_shown(2)
	unlocks.mark_first_shown(BigFirsts.OPENING)
	unlocks.mark_first_shown(BigFirsts.RUNWAY)

	var hints := _hints()
	hints._mark_seen(HintRules.TOILET)
	var sheet := hints.help_sheet()
	sheet.unlocks = unlocks

	hints.toggle_button().pressed.emit()
	await get_tree().process_frame

	assert_int(sheet.active_tab()).is_equal(HelpSheet.Tab.GUIDE)
	var guide_titles := Array(sheet.card_titles())
	(
		assert_array(guide_titles)
		. contains(
			[
				"Opening & Staffing",
				"Building & Smart-Build",
				"Airline Offers & Planner",
				"Security & Baggage",
				"Arrivals & Pickup",
				"Controls & Shortcuts",
				"Unlocked Tiers (Tier 2)",
			]
		)
	)
	assert_str("\n".join(sheet.card_texts())).contains("Tier 2:")

	# Switch to Past Calls tab.
	sheet.past_calls_tab_button().pressed.emit()
	await get_tree().process_frame
	assert_int(sheet.active_tab()).is_equal(HelpSheet.Tab.PAST_CALLS)
	var call_titles := Array(sheet.card_titles())
	(
		assert_array(call_titles)
		. contains(
			[
				"Terminal Manager · Your first day at the airport",
				"Gotta Air · Station manager",
				"Terminal Manager · Big news at the airport",
				"Terminal Manager · Tier 2 unlocked",
				"Tips Seen",
			]
		)
	)
	var call_bodies := "\n".join(sheet.card_texts())
	assert_str(call_bodies).contains("Gotta Air here!")
	assert_str(call_bodies).contains("Runway works finished!")
	assert_str(call_bodies).contains(HintRules.text(HintRules.TOILET))


func test_auto_hints_toggle_inside_help_sheet_syncs_and_persists() -> void:
	var hints := _hints()
	var sheet := hints.help_sheet()
	sheet.open()
	var auto_btn := sheet.auto_hints_button()
	assert_bool(auto_btn.button_pressed).is_true()
	assert_str(auto_btn.text).is_equal("Auto-hints: On")
	assert_bool(hints.is_enabled()).is_true()

	# Turning Auto-hints off in HelpSheet disables Hints and persists to disk.
	auto_btn.button_pressed = false
	assert_bool(hints.is_enabled()).is_false()
	assert_str(auto_btn.text).is_equal("Auto-hints: Off")
	assert_bool(HudFlagSetting.load_flag(_path, Hints.SETTING_KEY, true, "test")).is_false()

	# A fresh Hints reads the persisted Auto-hints setting.
	var second := _hints()
	assert_bool(second.is_enabled()).is_false()
	assert_bool(second.help_sheet().auto_hints_button().button_pressed).is_false()

	# Resetting hints restores Auto-hints to On and syncs button state.
	second.reset_hints()
	assert_bool(second.is_enabled()).is_true()
	assert_bool(second.help_sheet().auto_hints_button().button_pressed).is_true()


func test_help_sheet_layout_focus_none_top_row_exclusion_and_save_load() -> void:
	var clock := SimClock.new()
	_port.add_child(clock)
	var save := SaveGame.new()
	_port.add_child(save)
	var sim := FlightSim.new()
	sim.open_airport()
	_port.add_child(sim)
	var desk := OfferDesk.new()
	desk.clock = clock
	desk.runway = Runway.new(PlaneClasses.LARGE)
	_port.add_child(desk)
	var offers := OfferPanel.new()
	offers.desk = desk
	offers.flights = sim
	_port.add_child(offers)

	var hints := _hints()
	var sheet := hints.help_sheet()
	sheet.save_game = save

	# Every button inside HelpSheet must use FOCUS_NONE.
	for child in sheet.find_children("*", "BaseButton", true, false):
		var btn := child as BaseButton
		assert_int(btn.focus_mode).is_equal(Control.FOCUS_NONE)

	# Opening HelpSheet closes OfferPanel and vice versa via TopRow.SHEET_GROUP.
	offers.open()
	assert_bool(offers.is_open()).is_true()
	sheet.open()
	assert_bool(sheet.is_open()).is_true()
	assert_bool(offers.is_open()).is_false()
	offers.open()
	assert_bool(offers.is_open()).is_true()
	assert_bool(sheet.is_open()).is_false()
	offers.close()

	# Fits cleanly inside top bar, left column, right rail, and bottom build bar at both sizes.
	for size: Vector2i in [Vector2i(1536, 864), Vector2i(1280, 720)]:
		_port.size = size
		sheet.open()
		await get_tree().process_frame
		await get_tree().process_frame
		var rect := sheet.sheet().get_global_rect()
		assert_float(rect.position.y).is_greater_equal(TopRow.SHEET_TOP - 0.5)
		assert_float(rect.position.x).is_greater_equal(TopRow.SHEET_MIN_LEFT - 0.5)
		assert_float(rect.end.x).is_less_equal(
			float(size.x - HudLayout.MARGIN - HudLayout.RAIL_W) + 0.5
		)
		assert_float(rect.end.y).is_less_equal(
			float(size.y - BuildMenu.MARGIN - BuildMenu.BAR_H) + 0.5
		)

	# Save load closes an open HelpSheet cleanly.
	assert_bool(sheet.is_open()).is_true()
	save.loaded.emit(true)
	assert_bool(sheet.is_open()).is_false()
