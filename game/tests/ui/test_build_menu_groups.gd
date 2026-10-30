class_name TestBuildMenuGroups
extends GdUnitTestSuite
## HUD 6/7 on the build menu: the category bar shows icons with the names in
## tooltips (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-
## pale); five group buttons, Decor, Food, Services, Leisure and Shops, take
## the place of the one Furniture button and its pages (decision hud-6-7-
## furniture-groups-five-icon-buttons-decor-food-servic); the number keys still
## pick their tools; prices are in the neutral text colour, never red or green;
## the panels are rounder.

## The ruling's groups and the pages it put in each.
const RULED := {
	"Decor": ["Furniture", "Features", "Fittings"],
	"Food": ["Food"],
	"Services": ["Desks", "Care"],
	"Leisure": ["Lounge", "Fun"],
	"Shops": ["Pharmacy", "Duty free", "Fashion"],
}
## The pages added after the ruling's eleven, and the group each joined.
const LATER := {"Dining": "Food", "Money": "Services", "Activities": "Leisure"}
## The bar buttons in order, by their tooltips.
const BAR := [
	"Structure",
	"Doors",
	"Check-in",
	"Security",
	"Lane",
	"Gates",
	"Cafe",
	"Toilets",
	"Kiosk",
	"Landside",
	"Baggage",
	"Decor",
	"Food",
	"Services",
	"Leisure",
	"Shops",
	"Remove",
	"Staff",
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


func _index(page_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == page_name:
			return i
	return BuildMenu.NO_CATEGORY


## The visible bar buttons in order, the Staff button last.
func _bar_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for button in _menu.bar().find_children("*", "Button", true, false):
		if (button as Button).visible:
			out.append(button)
	return out


## The tools whose cards a player can reach from a bar button: press it, then
## follow the Next cards round the group until they come back.
func _reachable_from(index: int) -> Array:
	var seen := []
	_menu.press_category(index)
	for step in BuildMenu.categories().size():
		var page := _menu.open_category()
		for tool in BuildMenu.categories()[page]["tools"]:
			if _menu.card(tool).is_visible_in_tree():
				seen.append(tool)
		var next := _menu.card(BuildMenu.categories()[page]["tools"][0]).get_parent()
		var button := next.find_child("CardNext", true, false) as Button
		if button == null:
			break
		button.pressed.emit()
		if _menu.open_category() == index:
			break
	_menu.press_category(index)
	return seen


func test_the_bar_has_five_group_buttons_and_no_furniture_button() -> void:
	var tips := []
	for button in _bar_buttons():
		tips.append(button.tooltip_text)
	print("bar: %s" % [tips])
	assert_array(tips).is_equal(BAR)
	assert_array(tips).not_contains(["Furniture"])
	for group in RULED:
		var index := BuildMenu.group_index(group)
		assert_int(index).override_failure_message(group).is_not_equal(BuildMenu.NO_CATEGORY)
		assert_str(BuildMenu.bar_name(index)).is_equal(group)
		assert_bool(_menu.category_button(index).visible).is_true()
		assert_str(BuildMenu.categories()[index]["name"]).is_equal(RULED[group][0])


func test_every_bar_button_shows_its_drawn_icon_and_no_text() -> void:
	for button in _bar_buttons():
		var path := BarIcons.icon_path(button.tooltip_text)
		print("%s icon %s %s" % [button.tooltip_text, path, button.icon])
		assert_str(path).override_failure_message(button.tooltip_text).is_not_empty()
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		assert_object(button.icon).override_failure_message(path).is_not_null()
		assert_str(button.icon.resource_path).is_equal(path)
		assert_str(button.text).is_empty()
		assert_bool(button.expand_icon).is_true()
		assert_vector(button.custom_minimum_size).is_equal(BuildMenu.CATEGORY_SIZE)
	# Each has a node name to find it by (the Godot MCP clicks by name).
	var decor := _menu.category_button(BuildMenu.group_index("Decor"))
	assert_str(str(decor.name)).is_equal("BarDecor")
	assert_object(_menu.bar().find_child("BarCheckin", true, false)).is_not_null()


func test_each_page_s_pieces_are_reached_from_exactly_its_ruled_group() -> void:
	var groups := {}
	for i in BuildMenu.categories().size():
		if BuildMenu.categories()[i].has("group"):
			groups[i] = _reachable_from(i)
	assert_int(groups.size()).is_equal(RULED.size())
	var want := {}
	for group in RULED:
		for page_name in RULED[group]:
			want[page_name] = group
	for page_name in LATER:
		want[page_name] = LATER[page_name]
	var checked := 0
	for page_name in want:
		var page := _index(page_name)
		assert_int(page).override_failure_message(page_name).is_not_equal(BuildMenu.NO_CATEGORY)
		for tool in BuildMenu.categories()[page]["tools"]:
			var from := []
			for index in groups:
				if groups[index].has(tool):
					from.append(BuildMenu.bar_name(index))
			assert_array(from).override_failure_message("%s tool %d" % [page_name, tool]).is_equal(
				[want[page_name]]
			)
			checked += 1
	print("checked %d tools on %d pages" % [checked, want.size()])
	# Every furniture piece (the pharmacy counter and shelf, the exchange counter
	# and the ATM among them), the 7 store room, till and shelf tools, and the 2
	# money, 3 dining and 4 activity rooms.
	assert_int(checked).is_equal(FurnitureTools.OBJECTS.size() + 7 + 2 + 3 + 4)


func test_the_number_keys_still_pick_their_tools_and_open_their_trays() -> void:
	var picked := 0
	for action in BuildMode.TOOL_ACTIONS:
		var tool: BuildMode.Tool = BuildMode.TOOL_ACTIONS[action]
		if tool == BuildMode.Tool.NONE or not InputMap.has_action(action):
			continue
		var key: InputEventKey
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				key = event.duplicate()
		assert_object(key).override_failure_message(str(action)).is_not_null()
		_mode.set_tool(BuildMode.Tool.NONE)
		key.pressed = true
		_port.push_input(key)
		var release := key.duplicate() as InputEventKey
		release.pressed = false
		_port.push_input(release)
		assert_int(_mode.tool).override_failure_message(str(action)).is_equal(tool)
		var want := BuildMenu.category_of(tool)
		if want == BuildMenu.remove_category():
			want = BuildMenu.NO_CATEGORY
		assert_int(_menu.open_category()).is_equal(want)
		picked += 1
	print("keys picked %d tools" % picked)
	assert_int(picked).is_equal(10)


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
		print("price %s colour %s" % [label.text, colour])
		assert_int(int(label.text)).is_greater(0)
		assert_bool(colour.is_equal_approx(neutral)).is_true()
		assert_bool(colour.is_equal_approx(problem)).is_false()
	# The cost line keeps the plain float text: cream with the dark outline.
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
	print("corner radii %s" % [radii])
	assert_int(radii["HudBar"]).is_equal(16)
	assert_int(radii["PanelContainer"]).is_equal(16)
	assert_int(radii["Button"]).is_equal(12)
	assert_int(radii["HudSubCard"]).is_equal(12)
	assert_int(radii["TooltipPanel"]).is_equal(12)


func test_the_icon_bar_fits_the_window_with_room_to_spare() -> void:
	await await_idle_frame()
	var bar := _menu.bar().get_global_rect()
	print("bar %s in %s" % [bar, _port.size])
	assert_float(bar.position.x).is_greater(200.0)
	assert_float(bar.end.x).is_less(_port.size.x - 200.0)
	assert_float(bar.size.y).is_equal(BuildMenu.BAR_H)
