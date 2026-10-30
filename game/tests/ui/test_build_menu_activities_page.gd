class_name TestBuildMenuActivitiesPage
extends GdUnitTestSuite
## The activity and rest rooms in the build menu (F4-7; decisions furniture-
## set-modelled-on-copenhagen-airport-decor-calms-pas and food-and-drink-cafe-
## bar-sit-down-restaurant-and-grab-and-go-st): one Activities page after the
## Dining page, behind the Furniture bar button, with the play area, lounge,
## shower and nap pod room cards. Each room takes its piece from the Lounge,
## Fun, Care or Fittings furniture page, so the page holds only the rooms. The
## cards borrow their main piece's thumbnail (no new art).

const TOOLS := [
	BuildMode.Tool.PLAY_AREA_ROOM,
	BuildMode.Tool.LOUNGE_ROOM,
	BuildMode.Tool.SHOWER_ROOM,
	BuildMode.Tool.NAP_POD_ROOM,
]
## Room tool -> its RoomTypes id.
const ROOMS := {
	BuildMode.Tool.PLAY_AREA_ROOM: &"play_area",
	BuildMode.Tool.LOUNGE_ROOM: &"lounge",
	BuildMode.Tool.SHOWER_ROOM: &"shower",
	BuildMode.Tool.NAP_POD_ROOM: &"nap_pod",
}

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)


func after() -> void:
	_port.free()


func _index(category_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_the_activities_page_follows_dining_in_the_furniture_group_before_remove() -> void:
	var all := BuildMenu.categories()
	var page := _index("Activities")
	assert_int(page).is_equal(_index("Dining") + 1)
	assert_bool(all[page].get("page", false)).is_true()
	assert_bool(_menu.category_button(page).visible).is_false()
	assert_int(BuildMenu.group_start(page)).is_equal(_index("Furniture"))
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(page + 1)
	assert_array(all[page]["tools"]).is_equal(TOOLS)
	for tool in TOOLS:
		assert_int(BuildMenu.category_of(tool)).is_equal(page)


func test_the_cards_carry_the_room_names_and_minimum_sizes() -> void:
	_menu.press_category(_index("Activities"))
	for tool in TOOLS:
		var room := RoomTypes.get_type(ROOMS[tool])
		var texts := _texts(_menu.card(tool))
		print("activities card %d: %s" % [tool, texts])
		assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
		assert_array(texts).contains(["%dx%d min" % [room.min_size.x, room.min_size.y]])
		assert_array(texts).contains([BuildMenu.PRICE_TEXT, "Drag"])
		# The card name is the room's own, or a short form of it.
		assert_bool(room.display_name.contains(BuildMenu.item(tool)[0].split("-")[0])).is_true()


func test_every_activities_card_shows_a_real_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for tool in TOOLS:
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		assert_object(picture.texture).override_failure_message(path).is_not_null()


func test_the_activities_tray_fits_the_column_and_next_goes_round_to_furniture() -> void:
	var page := _index("Activities")
	_menu.press_category(page)
	var need := _menu.tray().get_combined_minimum_size()
	print("activities tray needs %s of %s x %s" % [need, BuildMenu.COLUMN_W, BuildMenu.TRAY_H])
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
	var next := _menu.card(TOOLS[0]).get_parent().find_child("CardNext", true, false) as Button
	assert_object(next).is_not_null()
	next.pressed.emit()
	assert_int(_menu.open_category()).is_equal(_index("Furniture"))


func test_picking_an_activities_tool_opens_its_page_and_presses_its_card() -> void:
	for tool in TOOLS:
		_mode.set_tool(tool)
		assert_int(_menu.open_category()).is_equal(_index("Activities"))
		assert_bool(_menu.card(tool).button_pressed).is_true()
