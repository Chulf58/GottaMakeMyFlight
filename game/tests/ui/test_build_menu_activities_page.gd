class_name TestBuildMenuActivitiesPage
extends GdUnitTestSuite
## The activity and rest rooms in the Facilities domain tab: lounge, play area,
## and shower rooms sit in Facilities beside the standalone Nap pod piece.

const TOOLS := [
	BuildMode.Tool.PLAY_AREA_ROOM,
	BuildMode.Tool.LOUNGE_ROOM,
	BuildMode.Tool.SHOWER_ROOM,
]
const ROOMS := {
	BuildMode.Tool.PLAY_AREA_ROOM: &"play_area",
	BuildMode.Tool.LOUNGE_ROOM: &"lounge",
	BuildMode.Tool.SHOWER_ROOM: &"shower",
}
const EXPECTED_TABS := {
	BuildMode.Tool.PLAY_AREA_ROOM: "facilities",
	BuildMode.Tool.LOUNGE_ROOM: "facilities",
	BuildMode.Tool.SHOWER_ROOM: "facilities",
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
	assert_int(BuildMenu.category_of(BuildMode.Tool.NAP_POD)).is_equal(
		BuildMenu.category_index("facilities")
	)


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
	_menu.press_category(BuildMenu.category_of(BuildMode.Tool.NAP_POD))
	var nap_texts := _texts(_menu.card(BuildMode.Tool.NAP_POD))
	var nap_hover := _hover_texts(BuildMode.Tool.NAP_POD)
	assert_array(nap_texts).contains(["Nap pod"])
	assert_array(nap_hover).contains(["1x1", "Click"])
	assert_int(BuildMenu.tool_price(BuildMode.Tool.NAP_POD)).is_greater(0)


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
		assert_bool(_menu.is_room_context()).is_true()
		assert_str(String(_menu.room_context_type())).is_equal(String(ROOMS[tool]))
		assert_bool(_menu.card(tool).button_pressed).is_true()
