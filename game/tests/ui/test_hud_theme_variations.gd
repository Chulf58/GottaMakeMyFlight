class_name TestHudThemeVariations
extends GdUnitTestSuite
## The HUD parts that once built their own StyleBoxFlat in code now take a
## theme variation from ui/hud_theme.tres, so the theme is the one place the
## look lives (board 30d6a3e0, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra part 1): the
## Build mode sign (HudBuildSign, HudBuildSignText), the Departures gate and
## picker buttons (HudButtonCompact) and the build cost card (HudCostCard,
## checked in test_build_menu_cost_card.gd). The flight result's Dismiss is a
## normal action, so it is teal (decision
## hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).

const THEME := preload("res://ui/hud_theme.tres")
## Every state a Button draws with; a missing one falls back to Button's
## 6 px padding.
const STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]


func _assert_no_style_overrides(control: Control, names: Array[StringName]) -> void:
	for style_name in names:
		var overridden := control.has_theme_stylebox_override(style_name)
		(
			assert_bool(overridden)
			. override_failure_message("%s overrides %s" % [control.name, style_name])
			. is_false()
		)


func test_the_build_mode_sign_uses_its_theme_variation() -> void:
	var frame := auto_free(BuildModeFrame.new()) as BuildModeFrame
	add_child(frame)
	var sign_panel := frame.sign_panel() as PanelContainer
	assert_str(str(sign_panel.theme_type_variation)).is_equal("HudBuildSign")
	_assert_no_style_overrides(sign_panel, [&"panel"])
	var style := sign_panel.get_theme_stylebox("panel")
	assert_object(style).is_same(THEME.get_stylebox("panel", "HudBuildSign"))
	# The sign keeps the hazard stripes' yellow and dark.
	assert_object((style as StyleBoxFlat).bg_color).is_equal(BuildModeFrame.YELLOW)
	assert_object((style as StyleBoxFlat).border_color).is_equal(BuildModeFrame.DARK)
	# The text sits in a holder (SignText) so the panel keeps the top row's 40 px.
	var label := sign_panel.find_children("*", "Label", true, false)[0] as Label
	assert_str(str(label.theme_type_variation)).is_equal("HudBuildSignText")
	assert_bool(label.has_theme_font_size_override("font_size")).is_false()
	assert_bool(label.has_theme_color_override("font_color")).is_false()
	assert_int(label.get_theme_font_size("font_size")).is_equal(HudLayout.FIGURE)
	assert_object(label.get_theme_color("font_color")).is_equal(BuildModeFrame.DARK)


func test_departures_gate_buttons_use_the_compact_variation() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	var clock := auto_free(SimClock.new()) as SimClock
	sim.open_airport()
	sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	var board := DeparturesBoard.new()
	board.settings_path = SaveTestKit.run_path("hud_theme_variations")
	board.flights = sim
	board.clock = clock
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	add_child(board)
	board.refresh()
	var gate := board.gate_button("X", 0)
	assert_object(gate).is_not_null()
	assert_str(str(gate.theme_type_variation)).is_equal("HudButtonCompact")
	_assert_no_style_overrides(gate, STATES)
	var normal := gate.get_theme_stylebox("normal")
	assert_object(normal).is_same(THEME.get_stylebox("normal", "HudButtonCompact"))
	assert_float(normal.content_margin_top).is_equal(1.0)
	assert_float(normal.content_margin_bottom).is_equal(1.0)
	gate.pressed.emit()
	var picks := board.find_children("Pick_*", "Button", true, false)
	print("picker buttons: ", picks.size())
	assert_int(picks.size()).is_greater(0)
	for pick in picks:
		assert_str(str((pick as Button).theme_type_variation)).is_equal("HudButtonCompact")
		_assert_no_style_overrides(pick as Button, STATES)
	var path := board.settings_path
	board.free()
	DirAccess.remove_absolute(path)


func test_the_compact_buttons_keep_the_button_look() -> void:
	for state in STATES:
		var own := THEME.has_stylebox(state, "HudButtonCompact")
		assert_bool(own).override_failure_message("no compact %s" % state).is_true()
		if not own:
			continue
		var compact := THEME.get_stylebox(state, "HudButtonCompact") as StyleBoxFlat
		var plain := THEME.get_stylebox(state, "Button") as StyleBoxFlat
		assert_float(compact.content_margin_top).is_equal(1.0)
		assert_float(compact.content_margin_bottom).is_equal(1.0)
		assert_object(compact.bg_color).is_equal(plain.bg_color)
		assert_object(compact.border_color).is_equal(plain.border_color)
		assert_float(compact.content_margin_left).is_equal(plain.content_margin_left)


func test_the_flight_result_dismiss_is_teal() -> void:
	var panel := auto_free(FlightResultPanel.new()) as FlightResultPanel
	var dismiss := panel.find_child("DismissResult", true, false) as Button
	assert_object(dismiss).is_not_null()
	assert_str(str(dismiss.theme_type_variation)).is_equal("HudButtonTeal")
