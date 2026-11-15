class_name TestGateColours
extends GdUnitTestSuite
## The gate palette (decision flight-planner-a-full-screen-day-planner-with-one-
## row-per-ga): one colour per gate letter, the same everywhere. Each colour has
## a button variation in ui/hud_theme.tres (decision hud-theme-file-game-ui-hud-
## theme-tres-nunito-font-set-on-eac), so these tests also pin the theme to the
## palette and keep the navy text readable on every fill.

const THEME := preload("res://ui/hud_theme.tres")
const STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled"]
## WCAG's floor for normal-size text.
const MIN_CONTRAST := 4.5
## How far outside a selected bar its outline is drawn, in px.
const SELECTED_RING := 2.0
## The Label variation a disabled bar's label takes, whose colour is the gate
## buttons' disabled text.
const DISABLED_LABEL := &"HudBarLabelDisabled"


## WCAG contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _relative_luminance(colour: Color) -> float:
	var channels: Array[float] = []
	for value in [colour.r, colour.g, colour.b]:
		channels.append(value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


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


func test_a_gate_takes_the_variation_of_its_slot() -> void:
	assert_str(str(GateColours.variation_of("A"))).is_equal("HudGateA")
	assert_str(str(GateColours.variation_of("h"))).is_equal("HudGateH")
	assert_str(str(GateColours.variation_of("I"))).is_equal("HudGateA")
	assert_str(str(GateColours.variation_of(""))).is_equal("HudGateA")


func test_every_gate_variation_is_the_compact_button_in_the_gate_colour() -> void:
	var compact := THEME.get_stylebox("normal", "HudButtonCompact") as StyleBoxFlat
	for slot in GateColours.PALETTE.size():
		var gate_id := char("A".unicode_at(0) + slot)
		var variation := GateColours.variation_of(gate_id)
		assert_str(str(THEME.get_type_variation_base(variation))).is_equal("HudButtonCompact")
		for state in STATES:
			var own := THEME.has_stylebox(state, variation)
			assert_bool(own).override_failure_message("%s has no %s" % [variation, state]).is_true()
			if not own:
				continue
			var box := THEME.get_stylebox(state, variation) as StyleBoxFlat
			var message := (
				"%s %s fill %s is not %s"
				% [variation, state, box.bg_color, GateColours.shade(gate_id, state)]
			)
			(
				assert_bool(box.bg_color.is_equal_approx(GateColours.shade(gate_id, state)))
				. override_failure_message(message)
				. is_true()
			)
			var plain := THEME.get_stylebox(state, "HudButtonCompact") as StyleBoxFlat
			assert_object(box.border_color).is_equal(plain.border_color)
			assert_int(box.border_width_left).is_equal(plain.border_width_left)
			assert_float(box.content_margin_top).is_equal(compact.content_margin_top)
			assert_float(box.content_margin_left).is_equal(compact.content_margin_left)
			assert_int(box.corner_radius_top_left).is_equal(plain.corner_radius_top_left)


## The selected bar keeps the 2 px button border of the HUD grid (decision hud-
## grid-and-rails-one-spacing-grid-centred-top-row-right-ra); it stands out by
## the HUD's teal accent outline in place of the navy one (user ruling flight-
## planner-selected-bar-2-px-teal-accent-outline, which replaced white), drawn
## SELECTED_RING px outside the bar. The teal is HudButtonTeal's own fill.
func test_every_selected_variation_is_its_gate_with_a_teal_outline() -> void:
	var plain := THEME.get_stylebox("normal", "HudButtonCompact") as StyleBoxFlat
	var teal := (THEME.get_stylebox("normal", "HudButtonTeal") as StyleBoxFlat).bg_color
	for slot in GateColours.PALETTE.size():
		var gate_id := char("A".unicode_at(0) + slot)
		var variation := GateColours.variation_of(gate_id, true)
		assert_str(str(variation)).is_equal("HudGateSel" + gate_id)
		assert_str(str(THEME.get_type_variation_base(variation))).is_equal(
			str(GateColours.variation_of(gate_id))
		)
		var box := THEME.get_stylebox("normal", variation) as StyleBoxFlat
		assert_object(box.bg_color).is_equal(GateColours.of(gate_id))
		assert_object(box.border_color).is_equal(teal)
		assert_object(box.border_color).is_not_equal(plain.border_color)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_int(box.get_border_width(side)).is_equal(plain.get_border_width(side))
			assert_float(box.get_expand_margin(side)).is_equal(SELECTED_RING)
		assert_float(box.content_margin_left).is_equal(plain.content_margin_left)


func test_navy_text_reads_on_every_gate_colour_in_every_state() -> void:
	var worst := 99.0
	for slot in GateColours.PALETTE.size():
		var gate_id := char("A".unicode_at(0) + slot)
		var variation := GateColours.variation_of(gate_id)
		# A real button resolves the colours through the variation chain, as the HUD does.
		var button := auto_free(Button.new()) as Button
		button.theme = THEME
		button.theme_type_variation = variation
		add_child(button)
		for state in STATES:
			var fill := (THEME.get_stylebox(state, variation) as StyleBoxFlat).bg_color
			var text_name := "font_%s_color" % state if state != &"normal" else "font_color"
			var text := button.get_theme_color(text_name)
			var ratio := _contrast(text, fill)
			worst = minf(worst, ratio)
			print("%s %s: text %s on %s = %.2f:1" % [variation, state, text, fill, ratio])
			# Disabled text is a softer navy, so a disabled gate button looks unlike its
			# normal state (test_hud_disabled_buttons); it is the colour the disabled
			# bar label takes, and it still reads on the disabled fill.
			if state == &"disabled":
				assert_object(text).is_not_equal(GateColours.TEXT)
				assert_object(text).is_equal(THEME.get_color("font_color", DISABLED_LABEL))
			else:
				assert_object(text).is_equal(GateColours.TEXT)
			assert_float(ratio).is_greater_equal(MIN_CONTRAST)
	print("worst contrast %.2f:1" % worst)
