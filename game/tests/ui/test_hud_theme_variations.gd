class_name TestHudThemeVariations
extends GdUnitTestSuite
## The HUD parts that once built their own StyleBoxFlat in code now take a
## theme variation from ui/hud_theme.tres, so the theme is the one place the
## look lives (board 30d6a3e0, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra part 1): the
## Build mode sign (HudBuildSign, HudBuildSignText), the Departures gate buttons
## (a HudGateA..H variation per gate colour, each based on HudButtonCompact) and
## picker buttons (HudButtonCompact) and the build status card that holds the
## cost (HudTopCard, checked in test_build_menu_cost_card.gd). The flight result's Dismiss is a
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
	var label := sign_panel.get_child(0) as Label
	assert_str(str(label.theme_type_variation)).is_equal("HudBuildSignText")
	assert_bool(label.has_theme_font_size_override("font_size")).is_false()
	assert_bool(label.has_theme_color_override("font_color")).is_false()
	assert_int(label.get_theme_font_size("font_size")).is_equal(HudLayout.FIGURE)
	assert_object(label.get_theme_color("font_color")).is_equal(BuildModeFrame.DARK)


func test_planner_gate_bars_and_move_buttons_use_the_compact_variation() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	var clock := auto_free(SimClock.new()) as SimClock
	sim.open_airport()
	sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	var planner := FlightPlanner.new()
	planner.flights = sim
	planner.clock = clock
	add_child(planner)
	planner.open()
	var bar := planner.bar_button("X", 0)
	assert_object(bar).is_not_null()
	var variation := bar.theme_type_variation
	assert_str(str(variation)).is_equal(str(GateColours.variation_of("A")))
	assert_str(str(THEME.get_type_variation_base(variation))).is_equal("HudButtonCompact")
	_assert_no_style_overrides(bar, STATES)
	assert_bool(bar.has_theme_color_override("font_color")).is_false()
	assert_bool(bar.has_theme_color_override("font_disabled_color")).is_false()
	var normal := bar.get_theme_stylebox("normal")
	assert_object(normal).is_same(THEME.get_stylebox("normal", variation))
	assert_float(normal.content_margin_top).is_equal(1.0)
	assert_float(normal.content_margin_bottom).is_equal(1.0)
	bar.pressed.emit()
	var move_b := planner.part("Move_B") as Button
	assert_object(move_b).is_not_null()
	assert_str(str(move_b.theme_type_variation)).is_equal(str(GateColours.variation_of("B")))
	_assert_no_style_overrides(move_b, STATES)
	planner.free()


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
