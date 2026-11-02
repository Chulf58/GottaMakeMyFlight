class_name TestBuildModeDoorRemoval
extends GdUnitTestSuite
## Removing an entrance or exit puts the plain wall back on its edge in the same
## undo step (decision removing-an-exit-or-entrance-door-puts-the-plain-wall-
## back), so the terminal stays enclosed. The wall is bought at its price.
## BuildMode has no redo; doing the removal again stands in for one.

const NORTH := BuildGrid.Side.NORTH
const CELL := Vector2i(4, 2)

var _finances: Finances
var _mode: BuildMode
var _door_id := 0


## A 12x12 grid with floor on x 2..7, y 2..7, a plain wall round it and an exit
## on the north edge (the wall under it is taken down by the placement).
func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(2, 8):
		for x in range(2, 8):
			_mode.apply_at(_at(Vector2i(x, y)))
	assert_int(EnclosureKit.close_floor(_mode.grid)).is_greater(0)
	_mode.set_tool(BuildMode.Tool.EXIT)
	var placed := _mode.apply_at(_at(CELL))
	assert_bool(placed.ok).is_true()
	_door_id = placed.object_id


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _remove_door() -> BuildResult:
	_mode.set_tool(BuildMode.Tool.REMOVE)
	return _mode.apply_at(_at(CELL))


func test_removing_an_exit_puts_the_plain_wall_back_and_leaves_no_gap() -> void:
	# Control: a standing exit's back edge is filled by the door, with no wall.
	assert_int(_mode.grid.wall_kind(CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	var result := _remove_door()
	print("removed: ok=%s wall=%d" % [result.ok, _mode.grid.wall_kind(CELL, NORTH)])
	assert_bool(result.ok).is_true()
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_mode.grid.wall_kind(CELL, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()


func test_one_undo_brings_the_exit_back_without_the_wall_and_the_money() -> void:
	var balance := _finances.wallet.balance
	_remove_door()
	assert_bool(_mode.undo().ok).is_true()
	print(
		(
			"undone: wall=%d balance %d was %d"
			% [_mode.grid.wall_kind(CELL, NORTH), _finances.wallet.balance, balance]
		)
	)
	assert_array(_mode.grid.object_ids()).is_equal([_door_id])
	assert_int(_mode.grid.wall_kind(CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_the_removal_can_be_done_again_after_an_undo() -> void:
	_remove_door()
	_mode.undo()
	var again := _remove_door()
	assert_bool(again.ok).is_true()
	assert_int(_mode.grid.wall_kind(CELL, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()


func test_removing_the_exit_refunds_the_door_and_buys_the_wall() -> void:
	var balance := _finances.wallet.balance
	_remove_door()
	var door_refund := PriceTable.refund_of(PriceTable.price_of_object(&"exit_door"))
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	print("balance %d expected %d" % [_finances.wallet.balance, balance + door_refund - wall_price])
	assert_int(_finances.wallet.balance).is_equal(balance + door_refund - wall_price)


func test_an_entrance_gets_its_wall_back_too() -> void:
	_remove_door()
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var placed := _mode.apply_at(_at(Vector2i(5, 2)))
	assert_bool(placed.ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(5, 2), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(_at(Vector2i(5, 2))).ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(5, 2), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
