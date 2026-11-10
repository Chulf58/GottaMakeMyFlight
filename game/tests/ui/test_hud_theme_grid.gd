class_name TestHudThemeGrid
extends GdUnitTestSuite
## ui/hud_theme.tres follows the HUD grid (board 30d6a3e0, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra part 1, and
## hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale): corner radius
## 12 on every flat style, border 3 on panels and cards, 2 on buttons and on
## the sub-cards that sit inside a panel, one drop shadow, and every text size
## on HudLayout's type scale. The intro dialogue's text keeps its own large
## sizes, so Intro* font sizes are left out of the scale check.

const THEME := preload("res://ui/hud_theme.tres")
const RADIUS := 12
const PANEL_BORDER := 3
const THIN_BORDER := 2
const SUB_CARDS: Array[StringName] = [
	&"HudSubCard", &"TooltipPanel", &"IntroGoldLine", &"IntroNameplate"
]
## The windows that float over the world and so carry the shadow.
const SHADOWED: Array[StringName] = [
	&"HudBar", &"Panel", &"PanelContainer", &"IntroBox", &"HudCostCard", &"HudBuildSign"
]


## Every flat style in the theme as [type, name, style].
func _flat_styles() -> Array:
	var out := []
	for type in THEME.get_type_list():
		for style_name in THEME.get_stylebox_list(type):
			var style := THEME.get_stylebox(style_name, type) as StyleBoxFlat
			if style != null:
				out.append([type, style_name, style])
	return out


func _is_button(type: StringName) -> bool:
	var at := type
	while at != &"":
		if at == &"Button":
			return true
		at = THEME.get_type_variation_base(at)
	return false


func _expected_border(type: StringName) -> int:
	if _is_button(type) or type in SUB_CARDS:
		return THIN_BORDER
	return PANEL_BORDER


func test_the_theme_has_flat_styles_to_check() -> void:
	var styles := _flat_styles()
	print("flat styles: ", styles.size())
	assert_int(styles.size()).is_greater(30)


func test_every_flat_style_has_corner_radius_12() -> void:
	for entry in _flat_styles():
		var style: StyleBoxFlat = entry[2]
		var where := "%s/%s" % [entry[0], entry[1]]
		for corner in [
			style.corner_radius_top_left,
			style.corner_radius_top_right,
			style.corner_radius_bottom_right,
			style.corner_radius_bottom_left,
		]:
			assert_int(corner).override_failure_message(where).is_equal(RADIUS)


func test_borders_are_3_on_panels_and_2_on_buttons_and_sub_cards() -> void:
	var thin := 0
	var thick := 0
	for entry in _flat_styles():
		var style: StyleBoxFlat = entry[2]
		var want := _expected_border(entry[0])
		var where := "%s/%s" % [entry[0], entry[1]]
		for side in [
			style.border_width_left,
			style.border_width_top,
			style.border_width_right,
			style.border_width_bottom,
		]:
			assert_int(side).override_failure_message(where).is_equal(want)
		if want == THIN_BORDER:
			thin += 1
		else:
			thick += 1
	print("thin-border styles: ", thin, " panel-border styles: ", thick)
	assert_int(thin).is_greater(20)
	assert_int(thick).is_greater(4)


func test_every_shadow_is_the_one_shadow_style() -> void:
	var bar := THEME.get_stylebox("panel", "HudBar") as StyleBoxFlat
	assert_int(bar.shadow_size).is_greater(0)
	var shadowed := 0
	for entry in _flat_styles():
		var style: StyleBoxFlat = entry[2]
		if style.shadow_size == 0:
			continue
		shadowed += 1
		var where := "%s/%s" % [entry[0], entry[1]]
		assert_int(style.shadow_size).override_failure_message(where).is_equal(bar.shadow_size)
		assert_object(style.shadow_color).override_failure_message(where).is_equal(bar.shadow_color)
		assert_object(style.shadow_offset).override_failure_message(where).is_equal(
			bar.shadow_offset
		)
	print("shadowed styles: ", shadowed)
	for type in SHADOWED:
		var names := THEME.get_stylebox_list(type)
		assert_bool(names.is_empty()).override_failure_message(type).is_false()
		var style := THEME.get_stylebox(names[0], type) as StyleBoxFlat
		assert_int(style.shadow_size).override_failure_message(type).is_equal(bar.shadow_size)


func test_every_hud_text_size_is_on_the_type_scale() -> void:
	assert_int(THEME.default_font_size).is_equal(HudLayout.TITLE)
	var checked := 0
	for type in THEME.get_type_list():
		if str(type).begins_with("Intro"):
			continue
		for size_name in THEME.get_font_size_list(type):
			var size := THEME.get_font_size(size_name, type)
			var where := "%s/%s = %d" % [type, size_name, size]
			assert_bool(size in HudLayout.TYPE_SCALE).override_failure_message(where).is_true()
			checked += 1
	print("font sizes checked: ", checked)
	assert_int(checked).is_greater(8)


func test_card_names_use_the_caption_size() -> void:
	assert_int(THEME.get_font_size("font_size", "HudCardName")).is_equal(HudLayout.CAPTION)


## HudLayout's numbers are the ruling's, so each is pinned to its literal.
func test_hud_layout_holds_the_ruled_grid() -> void:
	assert_int(HudLayout.UNIT).is_equal(8)
	assert_int(HudLayout.MARGIN).is_equal(16)
	assert_int(HudLayout.GAP).is_equal(8)
	assert_int(HudLayout.GROUP_GAP).is_equal(16)
	assert_int(HudLayout.CHIP_H).is_equal(32)
	assert_int(HudLayout.BUTTON_H).is_equal(40)
	assert_int(HudLayout.BAR_H).is_equal(52)
	assert_int(HudLayout.TOGGLE_W).is_equal(176)
	assert_int(HudLayout.MONEY_W).is_equal(224)
	assert_int(HudLayout.LIST_W).is_equal(304)
	assert_int(HudLayout.RAIL_W).is_equal(440)
	assert_int(HudLayout.SHEET_W).is_equal(560)
	assert_int(HudLayout.TRAY_W).is_equal(640)
	assert_int(HudLayout.CAPTION).is_equal(14)
	assert_int(HudLayout.BODY).is_equal(16)
	assert_int(HudLayout.TITLE).is_equal(18)
	assert_int(HudLayout.PANEL_TITLE).is_equal(22)
	assert_int(HudLayout.FIGURE).is_equal(24)
	assert_array(HudLayout.TYPE_SCALE).is_equal([14, 16, 18, 22, 24])
