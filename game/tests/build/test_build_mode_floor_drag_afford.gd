class_name TestBuildModeFloorDragAfford
extends GdUnitTestSuite
## A floor rectangle the wallet cannot pay for is tinted invalid like a refused
## room, not valid-green (board item 72ed0ceb, point 1): AreaDrag.fill_floor()
## lays nothing for it (CANT_AFFORD).

var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.FLOOR)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _drag(from: Vector2i, to: Vector2i) -> void:
	_mode.begin_area(_mode.grid.cell_to_world(from))
	_mode.move_area(_mode.grid.cell_to_world(to))
	_mode._draw_area()


func _slab_material() -> Material:
	var ghost := _mode.get_node("Ghost")
	# The previous slab is freed at the end of the frame, so the new one is last.
	var slab := ghost.get_child(ghost.get_child_count() - 1) as MeshInstance3D
	return slab.material_override


func test_an_unaffordable_floor_rectangle_is_tinted_invalid() -> void:
	_balance(PriceTable.price_of_floor() * 3)
	_drag(Vector2i(2, 2), Vector2i(7, 7))
	var cost := AreaDrag.floor_cost(_mode.grid, _mode.dragged_area())
	print("cost %d balance %d" % [cost, _finances.wallet.balance])
	assert_int(cost).is_greater(_finances.wallet.balance)
	assert_object(_slab_material()).is_same(_mode._invalid_material)


func test_an_affordable_floor_rectangle_stays_valid() -> void:
	_balance(PriceTable.price_of_floor() * 100)
	_drag(Vector2i(2, 2), Vector2i(4, 3))
	assert_object(_slab_material()).is_same(_mode._valid_material)


func test_the_tint_follows_the_balance_while_the_rectangle_stays() -> void:
	_balance(PriceTable.price_of_floor() * 3)
	_drag(Vector2i(2, 2), Vector2i(7, 7))
	assert_object(_slab_material()).is_same(_mode._invalid_material)
	_balance(PriceTable.price_of_floor() * 100)
	_mode._draw_area()
	assert_object(_slab_material()).is_same(_mode._valid_material)


func test_tiles_that_already_have_floor_cost_nothing() -> void:
	_balance(PriceTable.price_of_floor() * 100)
	_drag(Vector2i(2, 2), Vector2i(7, 7))
	_mode.finish_area()
	_balance(0)
	_drag(Vector2i(2, 2), Vector2i(7, 7))
	assert_object(_slab_material()).is_same(_mode._valid_material)


func test_the_remove_slab_is_not_tinted_by_money() -> void:
	_balance(0)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(2, 2), Vector2i(7, 7))
	assert_object(_slab_material()).is_same(_mode._area_remove_material)
