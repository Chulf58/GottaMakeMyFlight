class_name TestAreaDragDoorCost
extends GdUnitTestSuite
## A Remove rectangle over an entrance that cost nothing to place: the wall it
## puts back is bought with nothing refunded, so the status line says "cost".

const ZONE := 1

var _grid: BuildGrid


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(20, 20))
	for cell in [Vector2i(5, 5), Vector2i(5, 6)]:
		var painted := _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE))
		assert_bool(painted.ok).is_true()


func test_clear_over_a_free_door_pays_for_its_wall_and_says_cost() -> void:
	# Placed for free, the door saved no price, so its removal refunds nothing.
	var door := _grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0))
	assert_bool(door.ok).is_true()
	var wallet := Wallet.new(1000)
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	var outcome := AreaDrag.clear(_grid, Rect2i(5, 5, 1, 1), wallet)
	assert_int(outcome.placed).is_equal(1)
	assert_int(outcome.skipped).is_equal(0)
	assert_bool(outcome.charged).is_true()
	assert_int(outcome.money).is_equal(wall_price)
	assert_int(wallet.balance).is_equal(1000 - wall_price)
	assert_str(outcome.message()).is_equal("Removed 1, cost %d" % wall_price)
