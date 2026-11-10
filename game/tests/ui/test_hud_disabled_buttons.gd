class_name TestHudDisabledButtons
extends GdUnitTestSuite
## A disabled HUD button keeps a readable label (board 3bd42402, HUD 7/7 part a:
## the inspect card's disabled Move button drew its text on a dark teal). For
## Button and every Button variation in ui/hud_theme.tres, the disabled label
## colour against the disabled background reaches WCAG AA, a contrast of 4.5:1,
## as a real Button resolves both through the theme. The disabled state also
## stays apart from the normal one, so the player can tell a button is off.

const THEME := preload("res://ui/hud_theme.tres")
const MIN_CONTRAST := 4.5


## Button and every type whose base chain reaches Button.
func _button_types() -> Array[StringName]:
	var out: Array[StringName] = [&"Button"]
	for type in THEME.get_type_list():
		var at := THEME.get_type_variation_base(type)
		while at != &"":
			if at == &"Button":
				out.append(type)
				break
			at = THEME.get_type_variation_base(at)
	return out


func _button(type: StringName) -> Button:
	var button: Button = auto_free(Button.new())
	button.theme = THEME
	if type != &"Button":
		button.theme_type_variation = type
	button.text = "Move"
	button.disabled = true
	add_child(button)
	return button


## WCAG relative luminance of an sRGB colour.
static func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_every_button_variation_is_listed() -> void:
	var types := _button_types()
	print("BUTTON TYPES %s" % [types])
	for wanted in [&"HudButtonTeal", &"HudButtonCoral", &"HudButtonGreen", &"HudButtonYellow"]:
		assert_array(types).contains([wanted])


func test_a_disabled_label_reads_on_its_disabled_background() -> void:
	for type in _button_types():
		var button := _button(type)
		var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
		assert_object(style).override_failure_message("%s has no flat disabled style" % type)
		if style == null:
			continue
		assert_float(style.bg_color.a).is_equal(1.0)
		var text := button.get_theme_color("font_disabled_color")
		var ratio := contrast(text, style.bg_color)
		print("DISABLED %s text=%s bg=%s contrast=%.2f" % [type, text, style.bg_color, ratio])
		(
			assert_float(ratio)
			. override_failure_message(
				"%s: disabled text %s on %s is %.2f:1" % [type, text, style.bg_color, ratio]
			)
			. is_greater_equal(MIN_CONTRAST)
		)


func test_a_disabled_button_looks_unlike_its_normal_state() -> void:
	for type in _button_types():
		var button := _button(type)
		var off := button.get_theme_stylebox("disabled") as StyleBoxFlat
		var on := button.get_theme_stylebox("normal") as StyleBoxFlat
		if off == null or on == null:
			continue
		(
			assert_bool(off.bg_color.is_equal_approx(on.bg_color))
			. override_failure_message("%s: disabled and normal share %s" % [type, on.bg_color])
			. is_false()
		)
		(
			assert_bool(
				button.get_theme_color("font_disabled_color").is_equal_approx(
					button.get_theme_color("font_color")
				)
			)
			. override_failure_message("%s: disabled text matches normal text" % type)
			. is_false()
		)
