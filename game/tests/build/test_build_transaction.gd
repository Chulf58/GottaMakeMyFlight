class_name TestBuildTransaction
extends GdUnitTestSuite
## BuildTransaction on a bare BuildGrid and Wallet: quotes, affordability and
## committing grid and money together (decision
## flights-and-economy-design-tick-derived-calendar-timetable-o, point 6).

const NORTH := BuildGrid.Side.NORTH
const PLAIN := BuildGrid.WallKind.PLAIN
const GLASS := BuildGrid.WallKind.GLASS

var _refused: Array = []


## An 8x8 grid with floor on x 1..6, y 1..6, laid with nothing paid.
func _floored_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in range(1, 7):
		for x in range(1, 7):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_refused.clear()
	grid.edit_refused.connect(
		func(edit: BuildEdit, result: BuildResult) -> void: _refused.append([edit, result])
	)
	return grid


func _paints(area: Rect2i) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return edits


func _plan(edit: BuildEdit) -> Array[BuildEdit]:
	var plan: Array[BuildEdit] = [edit]
	return plan


func test_new_pieces_are_quoted_at_their_price_table_price() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	grid.apply(BuildEdit.paint_floor(Vector2i(2, 2), BuildGrid.FLOOR_TILE, 1))
	var floor_quote := BuildTransaction.quote(
		grid, BuildEdit.paint_floor(Vector2i(4, 4), BuildGrid.FLOOR_TILE, 1)
	)
	var wall_quote := BuildTransaction.quote(grid, BuildEdit.place_wall(Vector2i(2, 2), NORTH))
	var desk_quote := BuildTransaction.quote(
		grid, BuildEdit.place_object(&"checkin_desk", Vector2i(2, 2), 0)
	)
	print("floor %d wall %d desk %d" % [floor_quote.charge, wall_quote.charge, desk_quote.charge])
	assert_int(floor_quote.charge).is_equal(PriceTable.FLOOR_PRICE)
	assert_int(floor_quote.paid).is_equal(PriceTable.FLOOR_PRICE)
	assert_int(wall_quote.charge).is_equal(PriceTable.price_of_wall(PLAIN))
	assert_int(desk_quote.charge).is_equal(PriceTable.price_of_object(&"checkin_desk"))
	assert_int(desk_quote.refund).is_equal(0)


func test_repainting_unchanged_floor_is_free_and_keeps_its_saved_price() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var laid := BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1)
	laid.paid = 25
	grid.apply(laid)
	var again := BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1)
	var quote := BuildTransaction.quote(grid, again)
	assert_int(quote.charge).is_equal(0)
	assert_int(quote.refund).is_equal(0)
	assert_int(quote.paid).is_equal(25)
	var wallet := Wallet.new(100)
	assert_bool(BuildTransaction.commit_plan(grid, _plan(again), wallet).ok).is_true()
	print("balance after repaint %d, saved %d" % [wallet.balance, grid.floor_paid(Vector2i(3, 3))])
	assert_int(wallet.balance).is_equal(100)
	assert_int(grid.floor_paid(Vector2i(3, 3))).is_equal(25)


func test_replacing_a_wall_charges_the_new_kind_and_refunds_the_old() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	BuildTransaction.commit_plan(grid, _plan(BuildEdit.place_wall(Vector2i(2, 2), NORTH)), wallet)
	var quote := BuildTransaction.quote(grid, BuildEdit.place_wall(Vector2i(2, 2), NORTH, GLASS))
	assert_int(quote.charge).is_equal(PriceTable.price_of_wall(GLASS))
	assert_int(quote.refund).is_equal(PriceTable.refund_of(PriceTable.price_of_wall(PLAIN)))
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_wall(Vector2i(2, 2), NORTH, GLASS)), wallet
	)
	assert_bool(result.ok).is_true()
	var expected := 1000 - 40 - (70 - 20)
	print("balance %d expected %d" % [wallet.balance, expected])
	assert_int(wallet.balance).is_equal(expected)
	assert_int(grid.wall_paid(Vector2i(2, 2), NORTH)).is_equal(70)


func test_a_click_spends_the_price_and_the_grid_records_it() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"seat_row", Vector2i(2, 3), 0)), wallet
	)
	assert_bool(result.ok).is_true()
	print("balance %d" % wallet.balance)
	assert_int(wallet.balance).is_equal(1000 - 250)
	assert_int(grid.get_object(result.object_id)["paid"]).is_equal(250)


func test_an_unaffordable_click_changes_neither_grid_nor_wallet() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(899)
	var before := JSON.stringify(grid.to_snapshot())
	var edit := BuildEdit.place_object(&"security_scanner", Vector2i(3, 3), 0)
	var result := BuildTransaction.commit_plan(grid, _plan(edit), wallet)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_str(result.reason_text()).is_equal("Not enough money")
	assert_int(wallet.balance).is_equal(899)
	assert_str(JSON.stringify(grid.to_snapshot())).is_equal(before)
	assert_int(_refused.size()).is_equal(1)
	assert_object(_refused[0][0]).is_same(edit)


func test_an_edit_the_grid_refuses_never_spends() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"seat_row", Vector2i(2, 3), 0)), wallet
	)
	var balance := wallet.balance
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"seat_row", Vector2i(2, 3), 0)), wallet
	)
	print("refused %s balance %d" % [result.reason_text(), wallet.balance])
	assert_int(result.reason).is_equal(BuildResult.Reason.OVERLAP)
	assert_int(wallet.balance).is_equal(balance)


func test_removal_refunds_the_share_of_the_saved_price_not_todays_price() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var laid := BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1)
	# Saved at a price PriceTable no longer charges.
	laid.paid = 10
	grid.apply(laid)
	var wallet := Wallet.new(0)
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.remove_floor(Vector2i(3, 3))), wallet
	)
	assert_bool(result.ok).is_true()
	print("refund %d (price today %d)" % [wallet.balance, PriceTable.FLOOR_PRICE])
	assert_int(wallet.balance).is_equal(PriceTable.refund_of(10))
	assert_int(grid.floor_paid(Vector2i(3, 3))).is_equal(0)


func test_a_piece_that_was_never_paid_for_refunds_nothing() -> void:
	var grid := _floored_grid()
	var placed := grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(2, 2), 0))
	var wallet := Wallet.new(5)
	BuildTransaction.commit_plan(grid, _plan(BuildEdit.remove_object(placed.object_id)), wallet)
	BuildTransaction.commit_plan(grid, _plan(BuildEdit.remove_floor(Vector2i(6, 6))), wallet)
	assert_int(grid.object_ids().size()).is_equal(0)
	assert_int(grid.floor_at(Vector2i(6, 6))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(wallet.balance).is_equal(5)


func test_a_floor_batch_commits_only_when_the_whole_quote_is_affordable() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var wallet := Wallet.new(4 * PriceTable.FLOOR_PRICE - 1)
	var results := BuildTransaction.commit_batch(grid, _paints(Rect2i(1, 1, 2, 2)), wallet)
	var refused := 0
	for result in results:
		if result.reason == BuildResult.Reason.CANT_AFFORD:
			refused += 1
	print("refused %d of %d, balance %d" % [refused, results.size(), wallet.balance])
	assert_int(refused).is_equal(4)
	assert_int(wallet.balance).is_equal(99)
	assert_int(grid.floor_at(Vector2i(1, 1))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(grid.floor_at(Vector2i(2, 2))).is_equal(BuildGrid.FLOOR_NONE)
	wallet.credit(1, Wallet.Category.FEES)
	results = BuildTransaction.commit_batch(grid, _paints(Rect2i(1, 1, 2, 2)), wallet)
	for result in results:
		assert_bool(result.ok).is_true()
	assert_int(wallet.balance).is_equal(0)
	assert_int(grid.floor_paid(Vector2i(2, 2))).is_equal(PriceTable.FLOOR_PRICE)


func test_a_batch_charges_only_for_the_edits_the_grid_accepts() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	var edits := _paints(Rect2i(2, 2, 3, 1))
	var wallet := Wallet.new(1000)
	var results := BuildTransaction.commit_batch(grid, edits, wallet)
	var accepted := 0
	for result in results:
		accepted += 1 if result.ok else 0
	print("accepted %d of %d, balance %d" % [accepted, results.size(), wallet.balance])
	assert_int(accepted).is_equal(2)
	assert_int(wallet.balance).is_equal(1000 - 2 * PriceTable.FLOOR_PRICE)


func test_a_removal_batch_refunds_every_removed_piece() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var wallet := Wallet.new(1000)
	BuildTransaction.commit_batch(grid, _paints(Rect2i(1, 1, 3, 3)), wallet)
	var desk := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"checkin_desk", Vector2i(1, 2), 0)), wallet
	)
	assert_bool(desk.ok).is_true()
	var balance := wallet.balance
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_object(desk.object_id), BuildEdit.remove_floor(Vector2i(3, 3))
	]
	BuildTransaction.commit_batch(grid, edits, wallet)
	var expected := balance + PriceTable.refund_of(400) + PriceTable.refund_of(25)
	print("balance %d expected %d" % [wallet.balance, expected])
	assert_int(wallet.balance).is_equal(expected)


func test_a_door_plan_takes_down_the_plain_wall_with_its_refund() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	var wall := BuildEdit.place_wall(Vector2i(3, 6), BuildGrid.Side.SOUTH)
	BuildTransaction.commit_plan(grid, _plan(wall), wallet)
	var door := BuildEdit.place_object(&"entrance_door", Vector2i(3, 6), 2)
	var plan := DoorPlacement.edits_for(grid, door)
	assert_int(plan.size()).is_equal(2)
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	assert_bool(result.ok).is_true()
	var expected := 1000 - 40 + 20 - 300
	print("balance %d expected %d" % [wallet.balance, expected])
	assert_int(wallet.balance).is_equal(expected)
	assert_int(grid.wall_kind(Vector2i(3, 6), BuildGrid.Side.SOUTH)).is_equal(0)


func test_a_plan_needs_the_balance_to_cover_its_costs_without_counting_refunds() -> void:
	var grid := _floored_grid()
	var wall := BuildEdit.place_wall(Vector2i(3, 6), BuildGrid.Side.SOUTH)
	BuildTransaction.commit_plan(grid, _plan(wall), Wallet.new(40))
	var plan := DoorPlacement.edits_for(
		grid, BuildEdit.place_object(&"entrance_door", Vector2i(3, 6), 2)
	)
	assert_int(BuildTransaction.needed(grid, plan)).is_equal(300)
	assert_bool(BuildTransaction.check(grid, plan, Wallet.new(299)).ok).is_false()
	assert_bool(BuildTransaction.check(grid, plan, Wallet.new(300)).ok).is_true()


func test_without_a_wallet_edits_are_free_and_record_nothing_paid() -> void:
	var grid := _floored_grid()
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"security_scanner", Vector2i(3, 3), 0)), null
	)
	assert_bool(result.ok).is_true()
	assert_int(grid.get_object(result.object_id)["paid"]).is_equal(0)
	var results := BuildTransaction.commit_batch(grid, _paints(Rect2i(0, 0, 2, 1)), null)
	assert_bool(results[0].ok).is_true()
	assert_int(grid.floor_paid(Vector2i(0, 0))).is_equal(0)


func test_rooms_cost_nothing() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(0)
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_room(Rect2i(1, 1, 3, 3), &"cafe")), wallet
	)
	assert_bool(result.ok).is_true()
	BuildTransaction.commit_plan(grid, _plan(BuildEdit.remove_room(result.room_id)), wallet)
	assert_int(wallet.balance).is_equal(0)


## A listener on edit_applied that spends everything it sees: the build's own
## price is already settled when the grid signals, so grid and wallet agree.
func test_the_price_is_settled_before_the_grid_signals() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	var seen: Array[int] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void:
			seen.append(wallet.balance)
			wallet.spend(wallet.balance, Wallet.Category.BUILD)
	)
	var result := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.place_object(&"seat_row", Vector2i(2, 3), 0)), wallet
	)
	print("balance seen by the listener %s, after %d" % [seen, wallet.balance])
	assert_bool(result.ok).is_true()
	assert_array(seen).is_equal([1000 - 250])
	assert_int(wallet.balance).is_equal(0)
	assert_int(grid.object_ids().size()).is_equal(1)


func test_a_batch_settles_to_the_applied_edits_price_before_the_grid_signals() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	var wallet := Wallet.new(1000)
	var seen: Array[int] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void: seen.append(wallet.balance)
	)
	# Three cells, the last outside the grid.
	var results := BuildTransaction.commit_batch(grid, _paints(Rect2i(2, 2, 3, 1)), wallet)
	print("balance seen %s, after %d" % [seen, wallet.balance])
	assert_bool(results[2].ok).is_false()
	# The refused third cell never cost anything; the listeners see the exact settlement.
	assert_array(seen).is_equal([1000 - 50, 1000 - 50])
	assert_int(wallet.balance).is_equal(1000 - 50)


## A refund the wallet cannot hold is refused before the piece is removed.
func test_a_removal_into_a_full_wallet_is_refused_and_keeps_the_piece() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var laid := BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1)
	laid.paid = PriceTable.FLOOR_PRICE
	grid.apply(laid)
	var wallet := Wallet.new(Wallet.MAX_BALANCE)
	var removal := BuildEdit.remove_floor(Vector2i(3, 3))
	var full := BuildResult.Reason.WALLET_FULL
	assert_int(BuildTransaction.check(grid, _plan(removal), wallet).reason).is_equal(full)
	var result := BuildTransaction.commit_plan(grid, _plan(removal), wallet)
	var batch := BuildTransaction.commit_batch(
		grid, _plan(BuildEdit.remove_floor(Vector2i(3, 3))), wallet
	)
	print("plan '%s' batch '%s'" % [result.reason_text(), batch[0].reason_text()])
	assert_int(result.reason).is_equal(full)
	assert_int(batch[0].reason).is_equal(full)
	assert_int(grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE)
	# A removal that refunds nothing still goes through.
	grid.apply(BuildEdit.paint_floor(Vector2i(5, 5), BuildGrid.FLOOR_TILE, 1))
	var unpaid := BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.remove_floor(Vector2i(5, 5))), wallet
	)
	assert_bool(unpaid.ok).is_true()
