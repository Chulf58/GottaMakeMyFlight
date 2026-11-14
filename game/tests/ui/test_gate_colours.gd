class_name TestGateColours
extends GdUnitTestSuite
## The gate palette (decision flight-planner-a-full-screen-day-planner-with-one-
## row-per-ga): one colour per gate letter, the same everywhere.


func test_the_first_eight_gates_each_have_their_own_colour() -> void:
	var seen := {}
	for letter in ["A", "B", "C", "D", "E", "F", "G", "H"]:
		seen[GateColours.of(letter)] = letter
	print("palette slots: ", seen.size())
	assert_int(seen.size()).is_equal(8)


func test_a_gate_keeps_its_colour_and_a_ninth_wraps_to_the_first() -> void:
	assert_object(GateColours.of("C")).is_equal(GateColours.PALETTE[2])
	assert_object(GateColours.of("I")).is_equal(GateColours.of("A"))
	assert_object(GateColours.of("b")).is_equal(GateColours.of("B"))
	assert_object(GateColours.of("")).is_equal(GateColours.PALETTE[0])


func test_every_colour_is_light_enough_for_navy_text() -> void:
	for colour in GateColours.PALETTE:
		var shade := colour.get_luminance()
		print("luminance %.2f of %s" % [shade, colour])
		assert_float(shade).is_greater(0.45)


func test_tint_themed_colours_the_button_without_a_theme_override() -> void:
	var button: Button = auto_free(Button.new())
	button.theme = BuildMenu.HUD_THEME
	button.theme_type_variation = &"HudButtonCompact"
	add_child(button)
	GateColours.tint_themed(button, "B")
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	var drawn := normal.bg_color * button.self_modulate
	print("themed tint: fill ", normal.bg_color, " drawn ", drawn)
	assert_bool(drawn.is_equal_approx(GateColours.of("B"))).is_true()
	assert_str(str(button.theme_type_variation)).is_equal("HudButtonCompact")
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		assert_bool(button.has_theme_stylebox_override(state)).is_false()
	assert_bool(button.has_theme_color_override("font_color")).is_false()


func test_tint_button_colours_every_state_and_keeps_the_padding() -> void:
	var button: Button = auto_free(Button.new())
	button.theme = BuildMenu.HUD_THEME
	button.theme_type_variation = &"HudButtonCompact"
	var before := button.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)
	GateColours.tint_button(button, "B")
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
	print("tinted: ", normal.bg_color, " hover ", hover.bg_color)
	assert_object(normal.bg_color).is_equal(GateColours.of("B"))
	assert_float(hover.bg_color.get_luminance()).is_greater(normal.bg_color.get_luminance())
	assert_float(normal.get_content_margin(SIDE_LEFT)).is_equal(before)
	assert_object(button.get_theme_color("font_color")).is_equal(GateColours.TEXT)
