class_name TestLandPlots
extends GdUnitTestSuite
## The site's land plots (LandPlots) on the 86x150 airport site cut into 25 m
## squares: 4 columns (the east one 11 cells wide) by 6 rows. A new game owns
## the starter shell's plots, column 0 rows 4 and 5, plus every plot sharing
## an edge or a corner with them (ruling a-new-game-owns-the-land-plots-under-
## the-starter-shell-plus): columns 0 and 1, rows 3 to 5. A plot is bought only
## when it shares an edge with owned land, at a price that rises with each buy,
## and never when the wallet is short; building is refused off owned land.

const SITE := preload("res://build/terminal_site.tres")
## The plots a new game owns, row by row.
const START: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(0, 5), Vector2i(1, 5)
]

var _land: LandPlots


func before_test() -> void:
	_land = LandPlots.for_site(SITE)
	_land.own_start(SITE)


func test_the_site_is_cut_into_25_m_squares_with_the_rest_in_the_last_column() -> void:
	assert_int(SITE.plot_size).is_equal(25)
	assert_that(_land.plots).is_equal(Vector2i(4, 6))
	assert_that(_land.plot_cells(Vector2i(0, 0))).is_equal(Rect2i(0, 0, 25, 25))
	assert_that(_land.plot_cells(Vector2i(2, 5))).is_equal(Rect2i(50, 125, 25, 25))
	assert_that(_land.plot_cells(Vector2i(3, 5))).is_equal(Rect2i(75, 125, 11, 25))
	assert_that(_land.plot_of(Vector2i(85, 149))).is_equal(Vector2i(3, 5))
	assert_that(_land.plot_of(Vector2i(86, 0))).is_equal(Vector2i(-1, -1))


func test_a_new_game_owns_the_starter_plots_and_one_ring() -> void:
	assert_array(_land.owned_plots()).is_equal(START)
	assert_int(_land.bought).is_equal(0)
	# Every cell the starter shell names is owned.
	for edit in ReferenceTerminal.shell_edits(SITE.starter_offset):
		assert_bool(_land.owns_cell(edit.cell)).override_failure_message("%s" % edit.cell).is_true()
	# The corner-only neighbour of the starter's plots is in the ring too.
	assert_bool(_land.is_owned(Vector2i(1, 3))).is_true()
	assert_bool(_land.is_owned(Vector2i(2, 4))).is_false()
	assert_bool(_land.is_owned(Vector2i(0, 2))).is_false()


func test_the_buyable_plots_share_an_edge_with_owned_land() -> void:
	assert_array(_land.buyable_plots()).is_equal(
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)]
	)
	assert_object(_land.buy_problem(Vector2i(2, 4), null)).is_null()
	# (2, 2) touches owned (1, 3) only at a corner.
	var corner := _land.buy_problem(Vector2i(2, 2), null)
	assert_int(corner.reason).is_equal(BuildResult.Reason.LAND_NOT_TOUCHING)
	assert_int(_land.buy_problem(Vector2i(3, 0), null).reason).is_equal(
		BuildResult.Reason.LAND_NOT_TOUCHING
	)
	assert_int(_land.buy_problem(Vector2i(0, 3), null).reason).is_equal(
		BuildResult.Reason.LAND_OWNED
	)
	assert_int(_land.buy_problem(Vector2i(4, 0), null).reason).is_equal(
		BuildResult.Reason.OUT_OF_BOUNDS
	)


func test_each_buy_costs_the_next_price_and_the_price_rises() -> void:
	var wallet := Wallet.new(20000)
	var changes := [0]
	_land.changed.connect(func() -> void: changes[0] += 1)
	var paid: Array[int] = []
	for plot in [Vector2i(2, 5), Vector2i(2, 4), Vector2i(0, 2), Vector2i(3, 5)]:
		var before := wallet.balance
		var price := _land.next_price()
		var result := _land.buy(plot, wallet)
		assert_bool(result.ok).override_failure_message("%s: %d" % [plot, result.reason]).is_true()
		assert_bool(_land.is_owned(plot)).is_true()
		paid.append(before - wallet.balance)
		assert_int(before - wallet.balance).is_equal(price)
	print("land prices paid %s, balance %d, next %d" % [paid, wallet.balance, _land.next_price()])
	assert_array(paid).is_equal(PriceTable.LAND_PLOT_PRICES.slice(0, 4))
	for i in paid.size() - 1:
		assert_int(paid[i + 1]).is_greater(paid[i])
	assert_int(_land.bought).is_equal(4)
	assert_int(changes[0]).is_equal(4)
	assert_int(wallet.balance).is_equal(20000 - 2500 - 3500 - 5000 - 7000)


func test_the_price_keeps_rising_past_the_end_of_the_table() -> void:
	var last := PriceTable.LAND_PLOT_PRICES.size() - 1
	for bought in range(1, last + 6):
		assert_int(PriceTable.price_of_land_plot(bought)).is_greater(
			PriceTable.price_of_land_plot(bought - 1)
		)
	var step := PriceTable.LAND_PLOT_PRICES[last] - PriceTable.LAND_PLOT_PRICES[last - 1]
	assert_int(PriceTable.price_of_land_plot(last + 2)).is_equal(
		PriceTable.LAND_PLOT_PRICES[last] + 2 * step
	)


func test_a_buy_the_wallet_cannot_pay_is_refused_and_changes_nothing() -> void:
	var wallet := Wallet.new(PriceTable.price_of_land_plot(0) - 1)
	var changes := [0]
	_land.changed.connect(func() -> void: changes[0] += 1)
	var result := _land.buy(Vector2i(2, 4), wallet)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_int(wallet.balance).is_equal(PriceTable.price_of_land_plot(0) - 1)
	assert_bool(_land.is_owned(Vector2i(2, 4))).is_false()
	assert_int(_land.bought).is_equal(0)
	assert_int(changes[0]).is_equal(0)
	# The control: with the money the same buy goes through.
	(
		assert_bool(_land.buy(Vector2i(2, 4), Wallet.new(PriceTable.price_of_land_plot(0))).ok)
		. is_true()
	)


func test_a_refused_buy_out_of_reach_spends_nothing() -> void:
	var wallet := Wallet.new(20000)
	assert_int(_land.buy(Vector2i(3, 0), wallet).reason).is_equal(
		BuildResult.Reason.LAND_NOT_TOUCHING
	)
	assert_int(wallet.balance).is_equal(20000)
	assert_int(_land.bought).is_equal(0)


func test_building_off_owned_land_is_refused_and_removing_is_not() -> void:
	var owned := Vector2i(5, 120)
	var unowned := Vector2i(60, 120)
	assert_object(_land.edit_problem(_floor(owned))).is_null()
	assert_int(_land.edit_problem(_floor(unowned)).reason).is_equal(
		BuildResult.Reason.LAND_NOT_OWNED
	)
	assert_object(_land.edit_problem(BuildEdit.remove_floor(unowned))).is_null()
	assert_object(_land.edit_problem(BuildEdit.remove_wall(unowned, 0))).is_null()
	# A wall on the edge of owned land stands, named from either side.
	assert_object(_land.edit_problem(BuildEdit.place_wall(Vector2i(49, 120), 1))).is_null()
	assert_object(_land.edit_problem(BuildEdit.place_wall(Vector2i(50, 120), 3))).is_null()
	assert_int(_land.edit_problem(BuildEdit.place_wall(unowned, 0)).reason).is_equal(
		BuildResult.Reason.LAND_NOT_OWNED
	)
	# A room needs every cell owned.
	var inside := BuildEdit.place_room(Rect2i(40, 120, 10, 3), &"cafe")
	var across := BuildEdit.place_room(Rect2i(45, 120, 10, 3), &"cafe")
	assert_object(_land.edit_problem(inside)).is_null()
	assert_int(_land.edit_problem(across).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	# Once bought, the plot takes floor.
	assert_bool(_land.buy(Vector2i(2, 4), null).ok).is_true()
	assert_object(_land.edit_problem(_floor(unowned))).is_null()


func test_an_object_needs_its_whole_footprint_owned() -> void:
	var def := BuildCatalog.get_def(&"security_scanner")
	var straddle: BuildEdit = null
	for x in range(40, 51):
		var xs := def.footprint(Vector2i(x, 120), 1).map(func(c: Vector2i) -> int: return c.x)
		if xs.min() < 50 and xs.max() >= 50:
			straddle = BuildEdit.place_object(&"security_scanner", Vector2i(x, 120), 1)
			break
	assert_object(straddle).is_not_null()
	print("scanner footprint across x 50 from %s" % straddle.cell)
	assert_int(_land.edit_problem(straddle).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	var inside := BuildEdit.place_object(&"security_scanner", Vector2i(30, 120), 1)
	assert_object(_land.edit_problem(inside)).is_null()


func test_the_outline_runs_round_the_owned_plots() -> void:
	var o := SITE.grid_origin
	var start := _land.outline_loops(o)
	assert_int(start.size()).is_equal(1)
	assert_that(start[0]).is_equal(_world([[0, 75], [50, 75], [50, 150], [0, 150]]))
	# Buying (2, 5) makes an L: six corners, clockwise from the north-west.
	assert_bool(_land.buy(Vector2i(2, 5), null).ok).is_true()
	var grown := _land.outline_loops(o)
	assert_int(grown.size()).is_equal(1)
	assert_that(grown[0]).is_equal(
		_world([[0, 75], [50, 75], [50, 125], [75, 125], [75, 150], [0, 150]])
	)
	# The east column ends at the grid's edge, 11 cells on.
	assert_bool(_land.buy(Vector2i(3, 5), null).ok).is_true()
	var east := _land.outline_loops(o)
	assert_that(east[0][3]).is_equal(Vector2(o.x + 86, o.z + 125))


func test_a_hole_of_land_not_owned_gets_its_own_loop_running_the_other_way() -> void:
	var land := LandPlots.new(Vector2i(30, 30), 10)
	var ring := []
	for y in 3:
		for x in 3:
			if Vector2i(x, y) != Vector2i(1, 1):
				ring.append([x, y])
	assert_bool(land.from_snapshot({"plot_size": 10, "owned": ring, "bought": 0})).is_true()
	var loops := land.outline_loops(Vector3.ZERO)
	assert_int(loops.size()).is_equal(2)
	assert_that(loops[0]).is_equal(
		PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	)
	# The hole runs south, east, north, west: owned land stays on its right.
	assert_that(loops[1]).is_equal(
		PackedVector2Array([Vector2(10, 10), Vector2(10, 20), Vector2(20, 20), Vector2(20, 10)])
	)


func test_plots_meeting_at_a_corner_only_get_one_loop_each() -> void:
	var land := LandPlots.new(Vector2i(20, 20), 10)
	(
		assert_bool(land.from_snapshot({"plot_size": 10, "owned": [[0, 0], [1, 1]], "bought": 0}))
		. is_true()
	)
	var loops := land.outline_loops(Vector3.ZERO)
	assert_int(loops.size()).is_equal(2)
	for loop in loops:
		assert_int(loop.size()).is_equal(4)
	assert_that(loops[0]).is_equal(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	)


func test_the_snapshot_round_trips_through_json() -> void:
	assert_bool(_land.buy(Vector2i(2, 4), null).ok).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_land.to_snapshot()))
	assert_array(data.keys()).contains_exactly_in_any_order(["plot_size", "owned", "bought"])
	var loaded := LandPlots.for_site(SITE)
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_array(loaded.owned_plots()).is_equal(_land.owned_plots())
	assert_int(loaded.bought).is_equal(1)
	assert_int(loaded.next_price()).is_equal(PriceTable.price_of_land_plot(1))


func test_a_broken_snapshot_is_refused() -> void:
	var good := _land.to_snapshot()
	assert_str(LandPlots.problem(good, SITE)).is_empty()
	var other_size := good.duplicate()
	other_size["plot_size"] = 20
	var off_site := good.duplicate()
	off_site["owned"] = [[9, 9]]
	var negative := good.duplicate()
	negative["bought"] = -1
	var extra := good.duplicate()
	extra["upkeep"] = 5
	var missing := good.duplicate()
	missing.erase("bought")
	for data in [other_size, off_site, negative, extra, missing]:
		assert_str(LandPlots.problem(data, SITE)).is_not_empty()


func test_a_grid_built_off_the_saved_land_is_refused() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	grid.apply(_floor(Vector2i(5, 120)))
	assert_str(LandPlots.grid_problem(_land.to_snapshot(), SITE, grid)).is_empty()
	grid.apply(_floor(Vector2i(60, 120)))
	assert_str(LandPlots.grid_problem(_land.to_snapshot(), SITE, grid)).contains("(60, 120)")


static func _floor(cell: Vector2i) -> BuildEdit:
	return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)


## Grid cell corners [x, y] as points on the ground in the site's frame.
func _world(cells: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in cells:
		out.append(Vector2(SITE.grid_origin.x + c[0], SITE.grid_origin.z + c[1]))
	return out
