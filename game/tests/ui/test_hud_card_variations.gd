class_name TestHudCardVariations
extends GdUnitTestSuite
## The theme's card looks (HUD 6/7, decision hud-grid-and-rails-one-spacing-
## grid-centred-top-row-right-ra part 1): HudCardGreen for good news (the
## flight result card) and HudCardCoral for problems (the Offers notices) are
## theme type variations of PanelContainer in the colours of HudButtonGreen and
## HudButtonCoral (decision 0b50e074), and no card paints its own StyleBox.

const THEME := preload("res://ui/hud_theme.tres")


func _button_fill(variation: StringName) -> Color:
	return (THEME.get_stylebox("normal", variation) as StyleBoxFlat).bg_color


func _card_style(variation: StringName) -> StyleBoxFlat:
	return THEME.get_stylebox("panel", variation) as StyleBoxFlat


func test_the_theme_has_both_variations_on_the_card_look() -> void:
	var base := THEME.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	for variation in [&"HudCardGreen", &"HudCardCoral"]:
		assert_str(THEME.get_type_variation_base(variation)).is_equal("PanelContainer")
		var style := _card_style(variation)
		assert_int(style.border_width_left).is_equal(base.border_width_left)
		assert_int(style.corner_radius_top_left).is_equal(base.corner_radius_top_left)
		assert_float(style.content_margin_left).is_equal(base.content_margin_left)
		assert_int(style.shadow_size).is_equal(base.shadow_size)
		assert_that(style.border_color).is_equal(base.border_color)
	assert_that(_card_style(&"HudCardGreen").bg_color).is_equal(_button_fill(&"HudButtonGreen"))
	assert_that(_card_style(&"HudCardCoral").bg_color).is_equal(_button_fill(&"HudButtonCoral"))


func test_the_result_card_uses_the_green_variation_without_an_override() -> void:
	var card := auto_free(FlightResultPanel.new()) as FlightResultPanel
	add_child(card)
	assert_str(card.theme_type_variation).is_equal("HudCardGreen")
	assert_bool(card.has_theme_stylebox_override("panel")).is_false()
	var drawn := card.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(drawn.bg_color).is_equal(_button_fill(&"HudButtonGreen"))
	assert_that(FlightResultPanel.green_card().bg_color).is_equal(drawn.bg_color)


func test_the_offer_notices_use_the_coral_variation_without_an_override() -> void:
	var card := auto_free(OfferPanel.coral_card(&"k", "Title", "Detail")) as PanelContainer
	add_child(card)
	assert_str(card.theme_type_variation).is_equal("HudCardCoral")
	assert_bool(card.has_theme_stylebox_override("panel")).is_false()
	var drawn := card.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(drawn.bg_color).is_equal(_button_fill(&"HudButtonCoral"))
