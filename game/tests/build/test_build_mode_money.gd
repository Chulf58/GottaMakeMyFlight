class_name TestBuildModeMoney
extends GdUnitTestSuite
## BuildMode's tools paying through BuildTransaction from a Finances wallet:
## clicks, wall strokes, Floor and Remove rectangles, door conversions, the
## ghost check and snapshot load (ruling
## building-costs-money-from-a-starting-budget-you-can-t-build).

const NORTH := BuildGrid.Side.NORTH

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


func _wallet() -> Wallet:
	return _finances.wallet


func _set_balance(amount: int) -> void:
	assert_bool(_wallet().from_snapshot({"balance": str(amount)})).is_true()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _fill(area: Rect2i) -> AreaDrag.Outcome:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_at(area.position))
	_mode.move_area(_at(area.end - Vector2i.ONE))
	return _mode.finish_area()


func test_a_new_game_starts_with_the_starting_budget() -> void:
	assert_int(_wallet().balance).is_equal(PriceTable.STARTING_BUDGET)


func test_a_click_spends_the_price() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var result := _mode.apply_at(_at(Vector2i(2, 2)))
	assert_bool(result.ok).is_true()
	print("balance %d" % _wallet().balance)
	assert_int(_wallet().balance).is_equal(PriceTable.STARTING_BUDGET - PriceTable.FLOOR_PRICE)


func test_repainting_floor_with_a_click_is_free() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.apply_at(_at(Vector2i(2, 2)))
	var balance := _wallet().balance
	assert_bool(_mode.apply_at(_at(Vector2i(2, 2))).ok).is_true()
	assert_int(_wallet().balance).is_equal(balance)


func test_an_unaffordable_click_is_refused_with_a_red_ghost_reason() -> void:
	_fill(Rect2i(1, 1, 6, 6))
	_set_balance(899)
	_mode.set_tool(BuildMode.Tool.SCANNER)
	var edit := _mode.edit_at(_at(Vector2i(3, 3)))
	assert_int(_mode.check(edit).reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	# The ghost under the pointer shows the refusal before the click.
	_mode._update_ghost(_at(Vector2i(3, 3)))
	print("ghost status '%s'" % _mode.status_text())
	assert_str(_mode.status_text()).contains("Not enough money")
	var result := _mode.apply_at(_at(Vector2i(3, 3)))
	print("click %s balance %d" % [result.reason_text(), _wallet().balance])
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_wallet().balance).is_equal(899)


func test_a_wall_stroke_pays_per_segment_and_stops_when_money_runs_out() -> void:
	_fill(Rect2i(1, 1, 8, 8))
	var wall := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	_set_balance(3 * wall + wall / 2)
	_mode.set_tool(BuildMode.Tool.WALL)
	_mode._start_drag(_near_edge(Vector2i(2, 4), NORTH))
	var outcomes: Array[bool] = []
	for x in range(2, 7):
		outcomes.append(_mode.apply_at(_near_edge(Vector2i(x, 4), NORTH)).ok)
		if x == 5:
			# Money that arrives mid-stroke does not restart it.
			_wallet().credit(10 * wall, Wallet.Category.FEES)
	print("segments %s balance %d" % [outcomes, _wallet().balance])
	assert_array(outcomes).is_equal([true, true, true, false, false])
	for x in range(2, 5):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 4), NORTH)).is_true()
	for x in range(5, 7):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 4), NORTH)).is_false()
	assert_int(_wallet().balance).is_equal(wall / 2 + 10 * wall)
	# A new stroke can build again.
	_mode._start_drag(_near_edge(Vector2i(5, 4), NORTH))
	assert_bool(_mode.apply_at(_near_edge(Vector2i(5, 4), NORTH)).ok).is_true()


func test_a_floor_rectangle_is_all_or_nothing() -> void:
	_set_balance(15 * PriceTable.FLOOR_PRICE - 1)
	var outcome := _fill(Rect2i(2, 2, 5, 3))
	print("status '%s' balance %d" % [_mode.status_text(), _wallet().balance])
	assert_int(outcome.placed).is_equal(0)
	assert_int(_mode.grid.floor_at(Vector2i(2, 2))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_wallet().balance).is_equal(15 * PriceTable.FLOOR_PRICE - 1)
	assert_str(_mode.status_text()).is_equal("Not enough money: 15 tiles cost 375")
	_wallet().credit(1, Wallet.Category.FEES)
	outcome = _fill(Rect2i(2, 2, 5, 3))
	assert_int(outcome.placed).is_equal(15)
	assert_int(_wallet().balance).is_equal(0)
	assert_str(_mode.status_text()).is_equal("Placed 15 for 375")


func test_a_floor_rectangle_over_laid_floor_charges_only_the_new_tiles() -> void:
	_fill(Rect2i(2, 2, 2, 2))
	var balance := _wallet().balance
	var outcome := _fill(Rect2i(2, 2, 3, 2))
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.unchanged).is_equal(4)
	assert_int(_wallet().balance).is_equal(balance - 2 * PriceTable.FLOOR_PRICE)


func test_a_remove_rectangle_refunds_at_the_saved_price() -> void:
	_fill(Rect2i(2, 2, 4, 4))
	_mode.set_tool(BuildMode.Tool.SEATS)
	assert_bool(_mode.apply_at(_at(Vector2i(2, 3))).ok).is_true()
	var balance := _wallet().balance
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode.begin_area(_at(Vector2i(2, 2)))
	_mode.move_area(_at(Vector2i(5, 5)))
	var outcome := _mode.finish_area()
	# The seat row comes off first; the floor under it stays for a second drag.
	var floors := 16 - 3
	var expected := balance + PriceTable.refund_of(250) + floors * PriceTable.refund_of(25)
	print("removed %d balance %d expected %d" % [outcome.placed, _wallet().balance, expected])
	assert_int(outcome.placed).is_equal(1 + floors)
	assert_int(_wallet().balance).is_equal(expected)
	assert_str(_mode.status_text()).is_equal(
		"Removed %d, refund %d" % [1 + floors, expected - balance]
	)


func test_an_entrance_on_a_plain_wall_pays_the_door_and_refunds_the_wall() -> void:
	_fill(Rect2i(2, 2, 6, 6))
	_mode.set_tool(BuildMode.Tool.WALL)
	_mode.apply_at(_near_edge(Vector2i(4, 7), BuildGrid.Side.SOUTH))
	var balance := _wallet().balance
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var result := _mode.apply_at(_near_edge(Vector2i(4, 7), BuildGrid.Side.SOUTH))
	assert_bool(result.ok).is_true()
	var expected := (
		balance + PriceTable.refund_of(40) - PriceTable.price_of_object(&"entrance_door")
	)
	print("balance %d expected %d" % [_wallet().balance, expected])
	assert_int(_wallet().balance).is_equal(expected)


func test_loading_a_snapshot_never_spends_and_refunds_follow_its_saved_prices() -> void:
	var source := BuildMode.new()
	source.grid_size = Vector2i(12, 12)
	source.finances = _finances
	add_child(source)
	source.set_tool(BuildMode.Tool.FLOOR)
	source.apply_at(source.grid.cell_to_world(Vector2i(3, 3)))
	var data: Dictionary = JSON.parse_string(JSON.stringify(source.grid.to_snapshot()))
	source.free()
	var balance := _wallet().balance
	assert_bool(_mode.load_snapshot(data)).is_true()
	print("balance before %d after load %d" % [balance, _wallet().balance])
	assert_int(_wallet().balance).is_equal(balance)
	assert_int(_mode.grid.floor_paid(Vector2i(3, 3))).is_equal(PriceTable.FLOOR_PRICE)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(_at(Vector2i(3, 3))).ok).is_true()
	assert_int(_wallet().balance).is_equal(balance + PriceTable.refund_of(PriceTable.FLOOR_PRICE))
