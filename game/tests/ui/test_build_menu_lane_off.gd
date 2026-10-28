class_name TestBuildMenuLaneOff
extends GdUnitTestSuite
## With the lane feature flag at its default (SecurityLanes.enabled off) no
## security lane can be built or loaded in the game: the bar is as it was
## before lanes; no card, hotkey, set_tool(), initial tool or tool written
## straight to BuildMode makes a lane part edit; a grid snapshot holding a
## lane part is refused; and nothing else in the game places a lane part
## (RepairPlan builds only its leg pieces).

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
	assert_bool(SecurityLanes.enabled).is_false()


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


func test_a_lane_initial_tool_starts_on_none_and_makes_no_edit() -> void:
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(12, 12)
	mode.initial_tool = BuildMode.Tool.ARCH
	assert_int(mode.initial_tool).is_equal(BuildMode.Tool.NONE)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
	_port.add_child(mode)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_object(mode.edit_at(mode.grid.cell_to_world(Vector2i(5, 5)))).is_null()


func test_a_lane_tool_set_directly_makes_no_edit_and_places_nothing() -> void:
	var cell := Vector2i(5, 5)
	assert_bool(_mode.grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var point := _mode.grid.cell_to_world(cell)
	# Control: an enabled object tool at the same point makes a placement.
	_mode.tool = BuildMode.Tool.SCANNER
	var control := _mode.edit_at(point)
	assert_object(control).is_not_null()
	assert_int(control.kind).is_equal(BuildEdit.Kind.PLACE_OBJECT)
	for tool in LANE_TOOLS:
		_mode.tool = tool
		assert_object(_mode.edit_at(point)).is_null()
		assert_object(_mode.apply_at(point)).is_null()
	assert_array(_mode.grid.object_ids()).is_empty()


func test_a_snapshot_holding_a_lane_part_is_refused() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 8))
	PassengerTestWorld.place(grid, SecurityLanes.ARCH, Vector2i(3, 3), 0)
	var data := grid.to_snapshot()
	var loaded := BuildGrid.new(Vector2i(8, 8))
	assert_bool(loaded.from_snapshot(data)).is_false()
	assert_array(loaded.object_ids()).is_empty()
	# Control: the same snapshot loads once lanes are on.
	SecurityLanes.enabled = true
	var ok := loaded.from_snapshot(data)
	SecurityLanes.enabled = false
	assert_bool(ok).is_true()
	assert_int(loaded.object_ids().size()).is_equal(1)


func test_repair_plans_never_place_a_lane_part() -> void:
	for part in SecurityLanes.PART_IDS:
		assert_bool(RepairPlan.LEG_DEFS.has(part)).is_false()
