class_name TestBeltMoneyAndSave
extends GdUnitTestSuite
## What auto-shaped belts cost and how they save (decision baggage-belts-are-
## one-auto-shaping-belt-tool-one-baggage-tray; ruling building-costs-money-
## from-a-starting-budget-you-can-t-build). Every new belt cell costs the
## plain belt price whatever shape it takes, a reshape is free and keeps the
## saved price, and the grid saves the resolved pieces, which load back as
## they were with nothing left to reshape.

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 14:
		for x in 14:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.set_tool(BuildMode.Tool.BELT)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _balance() -> int:
	return _finances.wallet.balance


func _record(grid: BuildGrid, cell: Vector2i) -> Dictionary:
	return grid.get_object(grid.object_at(cell))


func _all_cells(grid: BuildGrid) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			cells.append(Vector2i(x, y))
	return cells


func test_each_new_cell_costs_the_belt_price_whatever_its_shape() -> void:
	var price := PriceTable.price_of_object(&"baggage_belt")
	_mode.grid.apply(BuildEdit.place_room(Rect2i(8, 8, 3, 3), &"bag_room"))
	var start := _balance()
	# Six cells: straights, a corner and an end in the bag room.
	assert_bool(_mode.lay_belt(Vector2i(6, 6), Vector2i(9, 8)).ok).is_true()
	assert_int(start - _balance()).is_equal(6 * price)
	for cell in BeltShaper.path(Vector2i(6, 6), Vector2i(9, 8)):
		assert_int(int(_record(_mode.grid, cell)["paid"])).is_equal(price)
	assert_str(str(_record(_mode.grid, Vector2i(9, 6))["def"])).is_equal("baggage_belt_corner")
	assert_str(str(_record(_mode.grid, Vector2i(9, 8))["def"])).is_equal("baggage_belt_end")


func test_a_reshape_is_free_and_a_line_over_belt_costs_nothing() -> void:
	var price := PriceTable.price_of_object(&"baggage_belt")
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	var start := _balance()
	# One new cell turns (5, 6) into a merge: only the new cell is paid for.
	_mode.lay_belt(Vector2i(5, 5), Vector2i(5, 5))
	assert_int(start - _balance()).is_equal(price)
	assert_str(str(_record(_mode.grid, Vector2i(5, 6))["def"])).is_equal("baggage_belt_feed")
	assert_int(int(_record(_mode.grid, Vector2i(5, 6))["paid"])).is_equal(price)
	var again := _balance()
	assert_bool(_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6)).ok).is_true()
	assert_int(_balance()).is_equal(again)


func test_removing_a_shaped_belt_refunds_the_share_of_the_belt_price() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	_mode.lay_belt(Vector2i(5, 5), Vector2i(5, 5))
	var start := _balance()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(5, 6))).ok).is_true()
	var refund := PriceTable.refund_of(PriceTable.price_of_object(&"baggage_belt"))
	assert_int(_balance() - start).is_equal(refund)


func test_a_line_the_wallet_cannot_pay_lays_nothing() -> void:
	var price := PriceTable.price_of_object(&"baggage_belt")
	assert_bool(_finances.wallet.from_snapshot({"balance": str(price * 3)})).is_true()
	var refused := _mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	assert_int(refused.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_balance()).is_equal(price * 3)


func test_the_cost_line_prices_only_the_new_cells() -> void:
	var menu := BuildMenu.new()
	menu.build_mode = _mode
	add_child(menu)
	_mode.lay_belt(Vector2i(2, 6), Vector2i(5, 6))
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(2, 6)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(8, 6)))
	_mode._update_ghost(_mode.grid.cell_to_world(Vector2i(8, 6)))
	assert_int(_mode.belt_cells_to_buy()).is_equal(3)
	var price := PriceTable.price_of_object(&"baggage_belt")
	assert_str(menu.preview_text()).is_equal("Cost %d" % (3 * price))
	_mode.cancel_area()
	menu.free()


func test_shaped_belts_save_and_load_as_the_same_pieces() -> void:
	var grid := _mode.grid
	grid.apply(BuildEdit.place_room(Rect2i(10, 10, 3, 3), &"bag_room"))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(2, 9), 0))
	_mode.lay_belt(Vector2i(3, 8), Vector2i(11, 8))
	_mode.lay_belt(Vector2i(11, 9), Vector2i(11, 11))
	_mode.lay_belt(Vector2i(7, 5), Vector2i(7, 7))
	var kinds := {}
	for object_id in grid.object_ids():
		kinds[str(grid.get_object(object_id)["def"])] = true
	# A straight, a corner, a merge and an end, beside the desk.
	assert_array(kinds.keys()).contains(
		["baggage_belt", "baggage_belt_corner", "baggage_belt_feed", "baggage_belt_end"]
	)
	var data := JSON.parse_string(JSON.stringify(grid.to_snapshot())) as Dictionary
	var loaded := BuildGrid.new(grid.size)
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_array(loaded.object_ids()).is_equal(grid.object_ids())
	for object_id in grid.object_ids():
		assert_dict(loaded.get_object(object_id)).is_equal(grid.get_object(object_id))
	# Nothing is left to reshape after a load.
	assert_array(BeltShaper.reshape_edits(loaded, _all_cells(loaded))).is_empty()


func test_a_dear_belt_piece_reshaped_to_a_cheap_one_still_loads() -> void:
	var grid := _mode.grid
	var end := BuildEdit.place_object(&"baggage_belt_end", Vector2i(4, 4), 0)
	end.paid = PriceTable.price_of_object(&"baggage_belt_end")
	assert_bool(grid.apply(end).ok).is_true()
	assert_bool(grid.apply(BuildEdit.reshape_belt(Vector2i(4, 4), &"baggage_belt", 0)).ok).is_true()
	assert_int(int(_record(grid, Vector2i(4, 4))["paid"])).is_equal(end.paid)
	var loaded := BuildGrid.new(grid.size)
	assert_bool(loaded.from_snapshot(grid.to_snapshot())).is_true()
	assert_int(int(_record(loaded, Vector2i(4, 4))["paid"])).is_equal(end.paid)


func test_a_reshape_edit_only_turns_a_belt_into_a_belt() -> void:
	var grid := _mode.grid
	grid.apply(BuildEdit.place_object(&"baggage_cart", Vector2i(2, 2), 0))
	grid.apply(BuildEdit.place_object(&"baggage_belt", Vector2i(5, 5), 0))
	var on_cart := grid.validate(BuildEdit.reshape_belt(Vector2i(2, 2), &"baggage_belt", 0))
	assert_int(on_cart.reason).is_equal(BuildResult.Reason.NOT_A_BELT)
	var to_cart := grid.validate(BuildEdit.reshape_belt(Vector2i(5, 5), &"baggage_cart", 0))
	assert_int(to_cart.reason).is_equal(BuildResult.Reason.NOT_A_BELT)
	var empty := grid.validate(BuildEdit.reshape_belt(Vector2i(8, 8), &"baggage_belt", 0))
	assert_int(empty.reason).is_equal(BuildResult.Reason.NO_OBJECT)
	(
		assert_bool(
			grid.validate(BuildEdit.reshape_belt(Vector2i(5, 5), &"baggage_belt_end", 2)).ok
		)
		. is_true()
	)
