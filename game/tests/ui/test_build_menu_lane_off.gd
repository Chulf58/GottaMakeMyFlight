class_name TestBuildMenuLaneOff
extends GdUnitTestSuite
## With the lane feature flag at its default (BuildMode.lane_tools_enabled
## off) no security lane can be built in the game: the bar is as it was
## before lanes, no card, hotkey or set_tool() reaches a lane part tool, and
## nothing else in the game places a lane part (RepairPlan builds only its
## leg pieces). A save can then never hold a lane either.

const LANE_TOOLS := [
	BuildMode.Tool.TRAY_TABLE,
	BuildMode.Tool.XRAY_BELT,
	BuildMode.Tool.ARCH,
	BuildMode.Tool.PICKUP_TABLE,
]
const BAR_NAMES := [
	"Structure", "Doors", "Check-in", "Security", "Gates", "Shops", "Baggage", "Remove"
]

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func test_the_flag_is_off_by_default() -> void:
	assert_bool(BuildMode.lane_tools_enabled).is_false()


func test_the_bar_is_as_it_was_before_lanes() -> void:
	var names := []
	for i in BuildMenu.categories().size():
		names.append(_menu.category_button(i).text)
	print("bar: %s" % [names])
	assert_array(names).is_equal(BAR_NAMES)
	assert_array(BuildMenu.categories()).is_equal(BuildMenu.CATEGORIES)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(7)
	assert_int(BuildMenu.remove_category()).is_equal(7)
	assert_int(_menu.find_children("CategoryBar", "", true, false).size()).is_equal(1)
	var bar := _menu.find_children("CategoryBar", "", true, false)[0]
	var buttons := bar.find_children("*", "Button", true, false)
	# Eight categories and the Staff button.
	assert_int(buttons.size()).is_equal(9)


func test_no_card_hotkey_or_set_tool_reaches_a_lane_tool() -> void:
	for action in BuildMode.TOOL_ACTIONS:
		assert_bool(LANE_TOOLS.has(BuildMode.TOOL_ACTIONS[action])).is_false()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for tool in LANE_TOOLS:
		assert_bool(BuildMode.tool_enabled(tool)).is_false()
		assert_object(_menu.card(tool)).is_null()
		assert_int(BuildMenu.category_of(tool)).is_equal(BuildMenu.NO_CATEGORY)
		assert_array(BuildMenu.item(tool)).is_empty()
		_mode.set_tool(tool)
		assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(BuildMode.tool_enabled(BuildMode.Tool.SCANNER)).is_true()


func test_repair_plans_never_place_a_lane_part() -> void:
	for part in SecurityLanes.PART_IDS:
		assert_bool(RepairPlan.LEG_DEFS.has(part)).is_false()
