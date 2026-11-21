class_name TestBuildMenuGroups
extends GdUnitTestSuite
## Six domain build tabs plus Remove and Staff on the category bar (decision
## build-menu-rework-six-domain-tabs-progressive-tab-and-card-u): stable ids
## key BarIcons and PascalCase node names (BarBuilding..BarRemove), tooltips
## show the translated tab names, all 77 build tools appear once across [0..5],
## prices are in the neutral text colour, and corner radii follow the HUD grid.

const BAR_IDS := [
	"building",
	"operations",
	"facilities",
	"food",
	"shops",
	"decor",
	"landside",
	"remove",
]
const BAR_BUTTON_IDS := [
	"building",
	"operations",
	"facilities",
	"food",
	"shops",
	"decor",
	"landside",
	"templates",
	"remove",
	"staff",
]
## Matches render_kit_thumbnails.py ALPHA_CUTOFF (0.10 / > 25/255) and MIN_OPAQUE_SHARE (0.15).
const ALPHA_CUTOFF_BYTE := 25
const MIN_OPAQUE_SHARE := 0.15
const BAR_TIPS := [
	"Building",
	"Operations",
	"Facilities",
	"Food & Drink",
	"Shops",
	"Decor",
	"Landside & Parking",
	"Templates",
	"Remove",
	"Staff",
]
const BAR_NODES := [
	"BarBuilding",
	"BarOperations",
	"BarFacilities",
	"BarFood",
	"BarShops",
	"BarDecor",
	"BarLandside",
	"TemplatesButton",
	"BarRemove",
	"StaffButton",
]

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_mode.set_tool(BuildMode.Tool.NONE)


func after_test() -> void:
	_port.free()


func _bar_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for button in _menu.bar().find_children("*", "Button", true, false):
		if (button as Button).visible:
			out.append(button)
	return out


func test_the_bar_has_seven_domain_tabs_plus_templates_remove_and_staff() -> void:
	var buttons := _bar_buttons()
	var tips := buttons.map(func(b: Button) -> String: return b.tooltip_text)
	var node_names := buttons.map(func(b: Button) -> String: return String(b.name))
	assert_array(tips).is_equal(BAR_TIPS)
	assert_array(node_names).is_equal(BAR_NODES)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(7)
	assert_int(BuildMenu.remove_category()).is_equal(7)
	for i in BAR_IDS.size():
		assert_str(BuildMenu.category_id(i)).is_equal(BAR_IDS[i])
		assert_int(BuildMenu.category_index(BAR_IDS[i])).is_equal(i)


func test_every_bar_button_shows_its_drawn_icon_and_no_text() -> void:
	var buttons := _bar_buttons()
	for i in buttons.size():
		var button := buttons[i]
		var bar_id: String = str(BAR_BUTTON_IDS[i])
		var path := BarIcons.icon_path(bar_id)
		assert_str(path).override_failure_message(bar_id).is_not_empty()
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		assert_object(button.icon).override_failure_message(path).is_not_null()
		assert_str(button.icon.resource_path).is_equal(path)
		assert_str(button.text).is_empty()
		assert_bool(button.expand_icon).is_true()
		assert_vector(button.custom_minimum_size).is_equal(BuildMenu.CATEGORY_SIZE)


func test_all_77_build_tools_appear_exactly_once_across_the_seven_domain_tabs() -> void:
	var seen := {}
	var expected_counts := [7, 12, 20, 10, 12, 12, 4]
	var cats := BuildMenu.categories()
	for i in BuildMenu.REMOVE_CATEGORY:
		var tools: Array = cats[i]["tools"]
		assert_int(tools.size()).is_equal(expected_counts[i])
		for tool: BuildMode.Tool in tools:
			assert_bool(seen.has(tool)).override_failure_message("duplicate %d" % tool).is_false()
			seen[tool] = true
			assert_int(BuildMenu.category_of(tool)).is_equal(i)
	assert_int(seen.size()).is_equal(77)
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		if tool == BuildMode.Tool.NONE or tool == BuildMode.Tool.REMOVE:
			assert_bool(seen.has(tool)).is_false()
		else:
			assert_bool(seen.has(tool)).override_failure_message("missing %d" % tool).is_true()


func test_room_cards_have_unique_labels_and_room_badges_and_96x118_size() -> void:
	assert_vector(BuildMenu.CARD_SIZE).is_equal(Vector2(96.0, 118.0))
	var names_per_tab := {}
	for i in BuildMenu.REMOVE_CATEGORY:
		names_per_tab[i] = {}
		for tool: BuildMode.Tool in BuildMenu.categories()[i]["tools"]:
			var item_name := str(BuildMenu.item(tool)[0])
			var seen_names: Dictionary = names_per_tab[i]
			(
				assert_bool(seen_names.has(item_name))
				. override_failure_message("duplicate label '%s' in tab %d" % [item_name, i])
				. is_false()
			)
			seen_names[item_name] = true
			var card := _menu.card(tool)
			assert_vector(card.custom_minimum_size).is_equal(Vector2(96.0, 118.0))
			var badge := card.get_node_or_null("RoomBadge")
			if BuildMenuCatalog.is_room_tool(tool):
				(
					assert_object(badge)
					. override_failure_message("missing RoomBadge %d" % tool)
					. is_not_null()
				)
				assert_str((badge.get_child(0) as Label).text).is_equal("Room")
			else:
				(
					assert_object(badge)
					. override_failure_message("unexpected RoomBadge %d" % tool)
					. is_null()
				)


func test_prices_are_in_the_neutral_text_colour() -> void:
	var finances := Finances.new()
	add_child(finances)
	var mode := BuildMode.new()
	mode.finances = finances
	_port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)
	var neutral := BuildMenu.HUD_THEME.get_color("font_color", "Label")
	var money := BuildMenu.HUD_THEME.get_color("font_color", "HudMoney")
	var problem := BuildMenu.HUD_THEME.get_color("font_color", "HudProblemText")
	assert_bool(neutral.is_equal_approx(money)).is_false()
	for tool in [BuildMode.Tool.DESK, BuildMode.Tool.FLOOR, FurnitureTools.OBJECTS.keys()[0]]:
		var label := menu.card_price_label(tool)
		var colour := label.get_theme_color("font_color")
		assert_int(int(label.text)).is_greater(0)
		assert_bool(colour.is_equal_approx(neutral)).is_true()
		assert_bool(colour.is_equal_approx(problem)).is_false()
	var cost := menu.preview_label().get_theme_color("font_color")
	assert_bool(cost.is_equal_approx(problem)).is_false()
	assert_float(cost.r - cost.g).is_less(0.1)
	finances.free()


func test_the_panels_and_buttons_are_rounder() -> void:
	var theme := BuildMenu.HUD_THEME
	var radii := {
		"HudBar": (theme.get_stylebox("panel", "HudBar") as StyleBoxFlat).corner_radius_top_left,
		"PanelContainer":
		(theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).corner_radius_top_left,
		"Button": (theme.get_stylebox("normal", "Button") as StyleBoxFlat).corner_radius_top_left,
		"HudSubCard":
		(theme.get_stylebox("panel", "HudSubCard") as StyleBoxFlat).corner_radius_top_left,
		"TooltipPanel":
		(theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat).corner_radius_top_left,
	}
	assert_int(radii["HudBar"]).is_equal(12)
	assert_int(radii["PanelContainer"]).is_equal(12)
	assert_int(radii["Button"]).is_equal(12)
	assert_int(radii["HudSubCard"]).is_equal(12)
	assert_int(radii["TooltipPanel"]).is_equal(12)


func test_the_icon_bar_fits_the_window_with_room_to_spare() -> void:
	await await_idle_frame()
	var bar := _menu.bar().get_global_rect()
	assert_float(bar.position.x).is_greater(400.0)
	assert_float(bar.end.x).is_less(_port.size.x - 400.0)
	assert_float(bar.size.y).is_equal(BuildMenu.BAR_H)


func test_every_thumbnail_meets_vf5_opacity_and_dining_rooms_are_distinct() -> void:
	var dining := [
		BuildMode.Tool.CAFE_ROOM,
		BuildMode.Tool.BAR_ROOM,
		BuildMode.Tool.RESTAURANT_ROOM,
		BuildMode.Tool.STALL_ROOM,
	]
	var dining_thumbs := {}
	for tool: BuildMode.Tool in dining:
		var thumb_id := str(BuildMenu.item(tool)[1])
		assert_bool(dining_thumbs.has(thumb_id)).is_false()
		dining_thumbs[thumb_id] = true
	var checked := {}
	for i in BuildMenu.REMOVE_CATEGORY:
		for tool: BuildMode.Tool in BuildMenu.categories()[i]["tools"]:
			var thumb_id := str(BuildMenu.item(tool)[1])
			if checked.has(thumb_id):
				continue
			checked[thumb_id] = true
			var path := BuildMenu.THUMBNAIL_DIR % thumb_id
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			assert_object(img).override_failure_message(path).is_not_null()
			img.convert(Image.FORMAT_RGBA8)
			var data := img.get_data()
			var opaque := 0
			for off in range(3, data.size(), 4):
				if data[off] > ALPHA_CUTOFF_BYTE:
					opaque += 1
			var total := img.get_width() * img.get_height()
			var ratio := float(opaque) / float(total)
			(
				assert_float(ratio)
				. override_failure_message(
					"%s opaque %.3f < %.2f" % [path, ratio, MIN_OPAQUE_SHARE]
				)
				. is_greater_equal(MIN_OPAQUE_SHARE)
			)
