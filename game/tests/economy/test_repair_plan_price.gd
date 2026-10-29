class_name TestRepairPlanPrice
extends GdUnitTestSuite
## RepairPlan.least_balance() quotes each edit against the grid as the edits
## before it left it, so a floor painted, taken up and painted again is paid
## for twice (Sol's re-check of 8f93699: the old code quoted every edit against
## the original grid and reset its painted set on REMOVE_FLOOR, so the
## repaint cost nothing on a paid floor and a whole tile too much on bare
## ground). No RepairPlan output holds REMOVE_FLOOR today; this pins the price
## for any list that does.

const CELL := Vector2i(3, 3)


static func _paint() -> BuildEdit:
	return BuildEdit.paint_floor(CELL, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)


static func _paint_remove_repaint() -> Array[BuildEdit]:
	return [_paint(), BuildEdit.remove_floor(CELL), _paint()] as Array[BuildEdit]


## Buys `edits` one by one with a wallet holding `money`; returns the wallet.
func _buy_all(grid: BuildGrid, edits: Array[BuildEdit], money: int) -> Wallet:
	var wallet := Wallet.new(money)
	for edit in edits:
		var result := BuildTransaction.commit_plan(grid, [edit] as Array[BuildEdit], wallet)
		var why := "buying %s at %s refused: %d" % [edit.kind, edit.cell, result.reason]
		assert_bool(result.ok).override_failure_message(why).is_true()
	return wallet


## On a floor the player paid for, the first paint is unchanged and free, the
## removal refunds half, and the repaint costs a whole tile again.
func test_a_paid_floor_taken_up_and_repainted_costs_the_tile_less_the_refund() -> void:
	var grid := BuildGrid.new()
	var first := _paint()
	first.paid = PriceTable.FLOOR_PRICE
	assert_bool(grid.apply(first).ok).is_true()
	var net := PriceTable.FLOOR_PRICE - PriceTable.refund_of(PriceTable.FLOOR_PRICE)
	var price := RepairPlan.least_balance(grid, _paint_remove_repaint())
	prints("paid floor price", price, "net", net)
	assert_int(net).is_equal(13)
	assert_int(price).is_equal(net)
	var wallet := _buy_all(grid, _paint_remove_repaint(), price)
	assert_int(wallet.balance).is_equal(0)


## On bare ground the first paint is bought, then half comes back, then the
## repaint is bought: the wallet must hold 25 at first and 13 more after the
## refund, 38 in all, not 50.
func test_bare_ground_painted_taken_up_and_repainted_needs_the_peak_not_the_sum() -> void:
	var grid := BuildGrid.new()
	var price := RepairPlan.least_balance(grid, _paint_remove_repaint())
	var expected := PriceTable.FLOOR_PRICE * 2 - PriceTable.refund_of(PriceTable.FLOOR_PRICE)
	prints("bare ground price", price, "expected", expected)
	assert_int(expected).is_equal(38)
	assert_int(price).is_equal(expected)
	var wallet := _buy_all(grid, _paint_remove_repaint(), price)
	assert_int(wallet.balance).is_equal(0)


## The grid passed in is only read.
func test_pricing_leaves_the_grid_as_it_was() -> void:
	var grid := BuildGrid.new()
	RepairPlan.least_balance(grid, _paint_remove_repaint())
	assert_int(grid.floor_at(CELL)).is_equal(BuildGrid.FLOOR_NONE)
