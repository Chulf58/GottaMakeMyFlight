class_name TestBuildMenuActivitiesPage
extends GdUnitTestSuite
## The activity and rest rooms in the domain build tabs: shower and nap pod
## rooms sit in Facilities beside their pieces, and lounge and play area rooms
## sit in Decor & Parking beside theirs.

const TOOLS := [
	BuildMode.Tool.PLAY_AREA_ROOM,
	BuildMode.Tool.LOUNGE_ROOM,
	BuildMode.Tool.SHOWER_ROOM,
	BuildMode.Tool.NAP_POD_ROOM,
]
const ROOMS := {
	BuildMode.Tool.PLAY_AREA_ROOM: &"play_area",
	BuildMode.Tool.LOUNGE_ROOM: &"lounge",
	BuildMode.Tool.SHOWER_ROOM: &"shower",
	BuildMode.Tool.NAP_POD_ROOM: &"nap_pod",
}
const EXPECTED_TABS := {
	BuildMode.Tool.PLAY_AREA_ROOM: "decor",
	BuildMode.Tool.LOUNGE_ROOM: "decor",
	BuildMode.Tool.SHOWER_ROOM: "facilities",
	BuildMode.Tool.NAP_POD_ROOM: "facilities",
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


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _hover_texts(tool: BuildMode.Tool) -> Array:
	var card := _menu.card(tool) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	return _texts(popup)


func test_activity_and_rest_rooms_live_in_their_domain_tabs() -> void:
	for tool in TOOLS:
		var want_idx := BuildMenu.category_index(EXPECTED_TABS[tool])
		assert_int(BuildMenu.category_of(tool)).is_equal(want_idx)


func test_the_cards_carry_the_room_names_and_hover_minimum_sizes() -> void:
	for tool in TOOLS:
		_menu.press_category(BuildMenu.category_of(tool))
		var room := RoomTypes.get_type(ROOMS[tool])
		var texts := _texts(_menu.card(tool))
		var hover := _hover_texts(tool)
		assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
		assert_array(texts).contains([BuildMenu.PRICE_TEXT])
		assert_array(hover).contains(["%dx%d min" % [room.min_size.x, room.min_size.y], "Drag"])
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


func test_picking_an_activities_tool_opens_its_tab_and_presses_its_card() -> void:
	for tool in TOOLS:
		_mode.set_tool(tool)
		assert_int(_menu.open_category()).is_equal(BuildMenu.category_of(tool))
		assert_bool(_menu.card(tool).button_pressed).is_true()
