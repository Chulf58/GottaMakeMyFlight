class_name TestFurnitureTools
extends GdUnitTestSuite
## The 29 furniture ids of Furniture 4/4 F4-1 are build tools (FurnitureTools):
## each id has exactly one tool, placing through the tool charges the
## OBJECT_PRICES price and removing the piece refunds half of it.

const IDS: Array[StringName] = [
	&"bench_1a",
	&"bench_2a_indoor",
	&"bush",
	&"fountain_indoor",
	&"metal_pole",
	&"metal_pole_chain",
	&"plant_pot_1a",
	&"plant_pot_2a",
	&"statue_indoor",
	&"trash_can",
	&"tree_indoor",
	&"bar_counter",
	&"grab_and_go_stall",
	&"restaurant_table",
	&"restaurant_booth",
	&"info_desk",
	&"info_screen",
	&"currency_exchange",
	&"atm",
	&"pharmacy_counter",
	&"pharmacy_shelf",
	&"shower_cubicle",
	&"nap_pod",
	&"play_blocks",
	&"play_slide",
	&"lounge_sofa",
	&"lounge_armchair",
	&"work_desk",
	&"prize_podium",
]
const START_BALANCE := 100000

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	add_child(_mode)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _tool_of(id: StringName) -> int:
	var found: Array = FurnitureTools.OBJECTS.keys().filter(
		func(tool: int) -> bool: return FurnitureTools.OBJECTS[tool] == id
	)
	return found[0] if found.size() == 1 else -1


func test_every_furniture_id_has_exactly_one_tool() -> void:
	assert_int(IDS.size()).is_equal(29)
	assert_int(FurnitureTools.OBJECTS.size()).is_equal(IDS.size())
	for id in IDS:
		var count := FurnitureTools.OBJECTS.values().count(id)
		assert_int(count).override_failure_message("tools for %s" % id).is_equal(1)
		assert_object(BuildCatalog.get_def(id)).override_failure_message(id).is_not_null()
		assert_int(PriceTable.price_of_object(id)).is_greater(0)


func test_the_new_tools_are_distinct_from_every_older_tool() -> void:
	var older := BuildMode.TOOL_OBJECTS.keys() + BuildMode.TOOL_ROOMS.keys()
	for tool in FurnitureTools.OBJECTS:
		assert_bool(older.has(tool)).override_failure_message("tool %d" % tool).is_false()
		assert_str(str(BuildMode.tool_object(tool))).is_equal(str(FurnitureTools.OBJECTS[tool]))
	assert_str(str(BuildMode.tool_object(BuildMode.Tool.DESK))).is_equal("checkin_desk")
	assert_str(str(BuildMode.tool_object(BuildMode.Tool.FLOOR))).is_equal("")


func test_placing_through_each_tool_charges_the_price_and_removing_refunds_half() -> void:
	var last := Vector2i(11, 11)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i.ZERO))
	_mode.move_area(_mode.grid.cell_to_world(last))
	_mode.finish_area()
	var wallet := _finances.wallet
	var spot := _mode.grid.cell_to_world(Vector2i(3, 3))
	for id in IDS:
		var tool := _tool_of(id)
		assert_int(tool).override_failure_message("no tool for %s" % id).is_greater(0)
		assert_bool(wallet.from_snapshot({"balance": str(START_BALANCE)})).is_true()
		_mode.set_tool(tool)
		var result := _mode.apply_at(spot)
		var why := "%s: %s" % [id, result.reason_text()]
		assert_bool(result.ok).override_failure_message(why).is_true()
		var price := PriceTable.price_of_object(id)
		print("%s price %d balance %d" % [id, price, wallet.balance])
		assert_int(wallet.balance).override_failure_message(id).is_equal(START_BALANCE - price)
		_mode.set_tool(BuildMode.Tool.REMOVE)
		assert_bool(_mode.apply_at(spot).ok).override_failure_message("remove " + id).is_true()
		assert_int(wallet.balance).override_failure_message("refund " + id).is_equal(
			START_BALANCE - price + PriceTable.refund_of(price)
		)
		assert_int(PriceTable.refund_of(price)).is_equal(price / 2)
		assert_int(_mode.grid.object_ids().size()).override_failure_message(id).is_equal(0)
