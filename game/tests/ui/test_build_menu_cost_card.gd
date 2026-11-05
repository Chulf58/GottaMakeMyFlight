class_name TestBuildMenuCostCard
extends GdUnitTestSuite
## The build menu's CostLine sits on a cream HUD card with a dark outline, so
## it reads over the busy apron stripes (board 72ed0ceb; rulings
## hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale and
## hud-steal-list-self-clearing-alert-cards-money-hover-departu). Costs stay
## neutral, never red; the card shows only while a cost does.

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _card_style() -> StyleBoxFlat:
	return _menu.preview_label().get_theme_stylebox("normal") as StyleBoxFlat


func test_the_cost_line_sits_on_the_hud_card_style() -> void:
	var card := _card_style()
	var hud := BuildMenu.HUD_THEME.get_stylebox("panel", "HudBar") as StyleBoxFlat
	assert_object(card).is_not_null()
	assert_object(card.bg_color).is_equal(hud.bg_color)
	assert_object(card.border_color).is_equal(hud.border_color)
	assert_int(card.border_width_left).is_equal(hud.border_width_left)
	assert_int(card.corner_radius_top_left).is_equal(hud.corner_radius_top_left)


func test_the_card_is_a_copy_not_the_shared_hud_bar_style() -> void:
	var hud := BuildMenu.HUD_THEME.get_stylebox("panel", "HudBar")
	assert_object(_card_style()).is_not_same(hud)


func test_the_cost_text_is_dark_on_the_card_and_neutral() -> void:
	var label := _menu.preview_label()
	assert_str(str(label.theme_type_variation)).is_equal("HudCardName")
	var dark := BuildMenu.HUD_THEME.get_color("font_color", "HudCardName")
	assert_object(label.get_theme_color("font_color")).is_equal(dark)
	assert_int(label.get_theme_constant("outline_size")).is_equal(0)


func test_the_card_shows_while_a_cost_shows_and_hides_with_it() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode._update_ghost(_mode.grid.cell_to_world(Vector2i(3, 3)))
	_menu.refresh_preview()
	var label := _menu.preview_label()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("Cost 400")
	assert_object(_card_style()).is_not_null()
	var padding := _card_style().get_minimum_size()
	assert_float(label.get_combined_minimum_size().x).is_greater(padding.x)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_menu.refresh_preview()
	assert_bool(label.visible).is_false()
