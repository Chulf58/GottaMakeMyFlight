class_name TestWideSite
extends GdUnitTestSuite
## The site grid's wide frame (board a91c3969, decision land-west-and-east-of-
## the-site-becomes-buyable-that-side-s-t): 256 cells, the first 86 m site in
## the middle and 85 m of side land west and east cut into plot columns. A new
## game keeps the starter's world place and today's 6 plots; side columns are
## for sale since the side airside slices landed (S7c) and are bought by the
## touching rule; a plane rides on the paving height over the whole grid.

const SITE := preload("res://build/terminal_site.tres")
## Today's new-game land, in the plot columns of the first site (4 to 7).
const START_PLOTS: Array[Vector2i] = [
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)
]

var _land: LandPlots


func before_test() -> void:
	_land = LandPlots.for_site(SITE)
	_land.own_start(SITE)


func test_the_grid_is_as_wide_as_the_build_grid_allows() -> void:
	assert_that(SITE.grid_size).is_equal(Vector2i(BuildGrid.MAX_SIDE_CELLS, 150))
	assert_float(SITE.grid_origin.x).is_equal(-128.0)
	assert_float(SITE.grid_origin.x + SITE.grid_size.x).is_equal(128.0)


func test_the_plot_columns_are_side_land_the_first_site_and_side_land() -> void:
	var total := 0
	for width in SITE.plot_columns:
		total += width
	assert_int(total).is_equal(SITE.grid_size.x)
	assert_that(_land.plots).is_equal(Vector2i(12, 6))
	var widths := []
	var world_x := []
	for column in _land.plots.x:
		var cells := _land.plot_cells(Vector2i(column, 0))
		widths.append(cells.size.x)
		world_x.append(SITE.grid_origin.x + cells.position.x)
	print("column widths %s, west edges %s" % [widths, world_x])
	assert_array(widths).is_equal([22, 21, 21, 21, 22, 22, 21, 21, 22, 21, 21, 21])
	assert_array(world_x.slice(4, 9)).is_equal([-43.0, -21.0, 1.0, 22.0, 43.0])
	assert_that(SITE.centre_rect()).is_equal(Rect2(-43, -210, 86, 150))
	assert_that(_land.plot_of(Vector2i(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(_land.plot_of(Vector2i(255, 149))).is_equal(Vector2i(11, 5))
	assert_that(_land.plot_of(Vector2i(256, 0))).is_equal(Vector2i(-1, -1))


func test_column_widths_that_miss_the_grid_width_are_refused_loudly() -> void:
	var cases := {
		"short": [PackedInt32Array([10, 10]), "add up to 20 cells, not the grid's 30"],
		"zero": [PackedInt32Array([10, 0, 20]), "column 1 is 0 cells wide"],
		"negative": [PackedInt32Array([40, -10]), "column 1 is -10 cells wide"],
	}
	for name: String in cases:
		var widths: PackedInt32Array = cases[name][0]
		var why: String = cases[name][1]
		var made := func() -> LandPlots:
			return LandPlots.new(Vector2i(30, 10), Vector2i(3, 1), widths)
		await assert_error(made).is_push_error(
			"LandPlots: %s" % LandPlots.column_problem(widths, 30)
		)
		var land: LandPlots = made.call()
		print("%s widths %s: error '%s', plots %s" % [name, widths, land.error, land.plots])
		assert_str(land.error).contains(why)
		# No other layout stands in: no plots, nothing owned or for sale.
		assert_that(land.plots).is_equal(Vector2i.ZERO)
		assert_that(land.plot_of(Vector2i(5, 5))).is_equal(Vector2i(-1, -1))
		assert_array(land.buyable_plots()).is_empty()
	# The control: widths that cut the grid are taken as given.
	var good := LandPlots.new(Vector2i(30, 10), Vector2i(3, 1), PackedInt32Array([5, 10, 15]))
	assert_str(good.error).is_empty()
	assert_that(good.plot_cells(Vector2i(2, 0))).is_equal(Rect2i(15, 0, 15, 10))


func test_a_site_whose_columns_miss_its_grid_gets_no_land() -> void:
	var bad: SiteDefinition = SITE.duplicate()
	bad.plot_columns = PackedInt32Array([22, 21, 21, 21, 22, 22, 21, 21])
	var made := func() -> LandPlots: return LandPlots.for_site(bad)
	await assert_error(made).is_push_error(
		"LandPlots: the column widths add up to 171 cells, not the grid's 256"
	)
	_assert_refused(made.call(), "add up to 171 cells")
	assert_str(LandPlots.for_site(SITE).error).is_empty()


func test_a_site_with_no_plot_columns_gets_no_land() -> void:
	var empty: SiteDefinition = SITE.duplicate()
	empty.plot_columns = PackedInt32Array()
	var made := func() -> LandPlots: return LandPlots.for_site(empty)
	await assert_error(made).is_push_error("LandPlots: the site has no plot columns")
	_assert_refused(made.call(), "no plot columns")


## A refused land: its error, no plots, nothing owned or for sale, and every
## build refused (removals still pass).
func _assert_refused(land: LandPlots, why: String) -> void:
	print("refused land: '%s', plots %s" % [land.error, land.plots])
	assert_str(land.error).contains(why)
	assert_that(land.plots).is_equal(Vector2i.ZERO)
	land.own_start(SITE)
	assert_array(land.owned_plots()).is_empty()
	assert_array(land.buyable_plots()).is_empty()
	var floor_edit := BuildEdit.paint_floor(Vector2i(100, 120), BuildGrid.FLOOR_TILE, 1)
	assert_int(land.edit_problem(floor_edit).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	assert_object(land.edit_problem(BuildEdit.remove_floor(Vector2i(100, 120)))).is_null()


func test_the_first_site_offset_of_the_test_fixtures_is_the_sites() -> void:
	var west := int(SITE.centre_rect().position.x - SITE.grid_origin.x)
	assert_that(LandKit.FIRST_SITE).is_equal(Vector2i(west, 0))


func test_the_starter_keeps_its_world_place() -> void:
	var low := Vector2(INF, INF)
	var high := -low
	for edit in ReferenceTerminal.shell_edits(SITE.starter_offset):
		var at := Vector2(SITE.grid_origin.x + edit.cell.x, SITE.grid_origin.z + edit.cell.y)
		low = low.min(at)
		high = high.max(at)
	print("starter cells' north-west corners from %s to %s" % [low, high])
	assert_that(low).is_equal(Vector2(-33, -84))
	assert_that(high.x).is_less(-20.0)
	assert_that(high.y).is_less(-67.0)


func test_a_new_game_owns_todays_six_plots_and_no_side_land() -> void:
	print("owned %s" % [_land.owned_plots()])
	assert_array(_land.owned_plots()).is_equal(START_PLOTS)
	assert_int(_land.bought).is_equal(0)


## The side land is for sale (SiteDefinition.SIDE_LAND_OPEN, board 16f7f8c2,
## S7c): every column is open, and (3, 4), touching owned (4, 4), is bought.
func test_side_land_is_for_sale() -> void:
	assert_bool(SiteDefinition.SIDE_LAND_OPEN).is_true()
	assert_that(_land.open_columns).is_equal(Vector2i(0, _land.plots.x))
	var wallet := Wallet.new(20000)
	var price := _land.next_price()
	var result := _land.buy(Vector2i(3, 4), wallet)
	print("bought (3, 4): %s for %d" % [result.ok, 20000 - wallet.balance])
	assert_bool(result.ok).is_true()
	assert_bool(_land.is_owned(Vector2i(3, 4))).is_true()
	assert_int(wallet.balance).is_equal(20000 - price)
	var side := BuildEdit.paint_floor(Vector2i(84, 110), BuildGrid.FLOOR_TILE, 0)
	assert_object(_land.edit_problem(side)).is_null()


## The lock still works when a land's open columns are the first site's only,
## as LandPlots.for_site() sets them with SIDE_LAND_OPEN false.
func test_locked_side_land_is_refused() -> void:
	_land.open_columns = SITE.centre_columns
	var buyable := _land.buyable_plots()
	print("buyable while locked %s" % [buyable])
	assert_array(buyable).is_equal(
		[Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5)]
	)
	# (3, 4) touches owned (4, 4) but is side land: refused as locked, buying nothing.
	assert_bool(_land.touches_owned(Vector2i(3, 4))).is_true()
	var wallet := Wallet.new(20000)
	var result := _land.buy(Vector2i(3, 4), wallet)
	assert_int(result.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_bool(_land.is_owned(Vector2i(3, 4))).is_false()
	assert_int(wallet.balance).is_equal(20000)
	assert_int(_land.bought).is_equal(0)
	# East: reached through the first site's own columns, still locked.
	assert_bool(_land.buy(Vector2i(6, 4), null).ok).is_true()
	assert_bool(_land.buy(Vector2i(7, 4), null).ok).is_true()
	assert_int(_land.buy_problem(Vector2i(8, 4), null).reason).is_equal(BuildResult.Reason.LOCKED)
	var side := BuildEdit.paint_floor(Vector2i(84, 110), BuildGrid.FLOOR_TILE, 0)
	assert_int(_land.edit_problem(side).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)


func test_a_save_owning_side_land_loads() -> void:
	var saved := _land.to_snapshot()
	(saved["owned"] as Array).append([3, 4])
	saved["bought"] = 1
	assert_str(LandPlots.problem(saved, SITE)).is_equal("")


func test_side_land_is_bought_by_the_touching_rule_west() -> void:
	var buyable := _land.buyable_plots()
	for row in [3, 4, 5]:
		assert_array(buyable).contains([Vector2i(3, row)])
	assert_object(_land.buy_problem(Vector2i(3, 4), null)).is_null()
	assert_int(_land.buy_problem(Vector2i(2, 4), null).reason).is_equal(
		BuildResult.Reason.LAND_NOT_TOUCHING
	)
	for column in [3, 2, 1, 0]:
		assert_bool(_land.buy(Vector2i(column, 4), null).ok).is_true()
	assert_bool(_land.owns_cell(Vector2i(0, 110))).is_true()
	assert_int(_land.bought).is_equal(4)


func test_side_land_is_bought_by_the_touching_rule_east() -> void:
	assert_int(_land.buy_problem(Vector2i(8, 4), null).reason).is_equal(
		BuildResult.Reason.LAND_NOT_TOUCHING
	)
	assert_bool(_land.buy(Vector2i(6, 4), null).ok).is_true()
	assert_bool(_land.buy(Vector2i(7, 4), null).ok).is_true()
	assert_object(_land.buy_problem(Vector2i(8, 4), null)).is_null()
	assert_bool(_land.buy(Vector2i(8, 4), null).ok).is_true()
	assert_bool(_land.buy(Vector2i(11, 4), null).ok).is_false()
	var east := BuildEdit.paint_floor(Vector2i(171, 110), BuildGrid.FLOOR_TILE, 0)
	assert_object(_land.edit_problem(east)).is_null()
	var beyond := BuildEdit.paint_floor(Vector2i(193, 110), BuildGrid.FLOOR_TILE, 0)
	assert_int(_land.edit_problem(beyond).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)


func test_a_save_cut_into_todays_four_columns_is_refused() -> void:
	var saved := _land.to_snapshot()
	assert_array(saved["plot_counts"]).is_equal([12, 6])
	saved["plot_counts"] = [4, 6]
	assert_str(_land.snapshot_problem(saved)).contains("another number of plots")


## With side land open the plane rides on the paving over the whole grid
## (SiteDefinition.grid_rect()), the floor spur at x -124 included, and ramps
## down outside its edge.
func test_a_plane_rides_on_the_paving_over_the_whole_grid() -> void:
	var centre := PlaneView.ground_height_at(Vector3(0, 0, -150))
	var edge := PlaneView.ground_height_at(Vector3(128 + PlaneView.paving_ramp_m() / 2.0, 0, -150))
	var side_lane := PlaneView.ground_height_at(Vector3(-124, 0, -150))
	var side_land := PlaneView.ground_height_at(Vector3(90, 0, -100))
	var off := PlaneView.ground_height_at(Vector3(-140, 0, -150))
	print(
		(
			"ground: centre %.3f, ramp middle %.3f, side lane %.3f, side land %.3f, off %.3f"
			% [centre, edge, side_lane, side_land, off]
		)
	)
	assert_that(SITE.grid_rect()).is_equal(Rect2(-128, -210, 256, 150))
	assert_float(centre).is_equal_approx(SITE.ground_height, 0.0001)
	assert_float(edge).is_equal_approx(SITE.ground_height / 2.0, 0.0001)
	assert_float(side_lane).is_equal_approx(SITE.ground_height, 0.0001)
	assert_float(side_land).is_equal_approx(SITE.ground_height, 0.0001)
	assert_float(off).is_equal(0.0)
