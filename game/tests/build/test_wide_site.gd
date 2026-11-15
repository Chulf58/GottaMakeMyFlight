class_name TestWideSite
extends GdUnitTestSuite
## The site grid's wide frame (board a91c3969, decision land-west-and-east-of-
## the-site-becomes-buyable-that-side-s-t): 256 cells, the first 86 m site in
## the middle and 85 m of side land west and east cut into plot columns. A new
## game keeps the starter's world place and today's 6 plots; side columns are
## locked until the side airside slices land and are then bought by the
## touching rule; a plane rides on the paving height over the
## first site only.

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
	var land := LandPlots.new(Vector2i(30, 10), Vector2i(3, 1), PackedInt32Array([10, 10]))
	assert_that(land.plots).is_equal(Vector2i(3, 1))
	assert_that(land.plot_cells(Vector2i(2, 0))).is_equal(Rect2i(20, 0, 10, 10))


func test_the_starter_keeps_its_world_place() -> void:
	var low := Vector2(INF, INF)
	var high := -low
	for edit in ReferenceTerminal.shell_edits(SITE.starter_offset):
		var at := Vector2(SITE.grid_origin.x + edit.cell.x, SITE.grid_origin.z + edit.cell.y)
		low = low.min(at)
		high = high.max(at)
	print("starter cells' north-west corners from %s to %s" % [low, high])
	assert_that(low).is_equal(Vector2(-33, -98))
	assert_that(high.x).is_less(-20.0)
	assert_that(high.y).is_less(-81.0)


func test_a_new_game_owns_todays_six_plots_and_no_side_land() -> void:
	print("owned %s" % [_land.owned_plots()])
	assert_array(_land.owned_plots()).is_equal(START_PLOTS)
	assert_int(_land.bought).is_equal(0)


## Opens the side land on `_land`, as SiteDefinition.SIDE_LAND_OPEN will.
func _open_side_land() -> void:
	_land.open_columns = Vector2i(0, _land.plots.x)


func test_side_land_is_locked_until_the_side_airside_slices_land() -> void:
	assert_bool(SiteDefinition.SIDE_LAND_OPEN).is_false()
	assert_that(_land.open_columns).is_equal(SITE.centre_columns)
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


func test_a_save_owning_locked_side_land_is_refused() -> void:
	var saved := _land.to_snapshot()
	(saved["owned"] as Array).append([3, 4])
	saved["bought"] = 1
	assert_str(LandPlots.problem(saved, SITE)).contains("not for sale")


func test_open_side_land_is_bought_by_the_touching_rule_west() -> void:
	_open_side_land()
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


func test_open_side_land_is_bought_by_the_touching_rule_east() -> void:
	_open_side_land()
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


func test_a_plane_rides_on_the_paving_over_the_first_site_only() -> void:
	var centre := PlaneView.ground_height_at(Vector3(0, 0, -150))
	var edge := PlaneView.ground_height_at(Vector3(43 + PlaneView.paving_ramp_m() / 2.0, 0, -150))
	var side_lane := PlaneView.ground_height_at(Vector3(-124, 0, -150))
	var side_land := PlaneView.ground_height_at(Vector3(90, 0, -100))
	print(
		(
			"ground: centre %.3f, ramp middle %.3f, side lane %.3f, side land %.3f"
			% [centre, edge, side_lane, side_land]
		)
	)
	assert_float(centre).is_equal_approx(SITE.ground_height, 0.0001)
	assert_float(edge).is_equal_approx(SITE.ground_height / 2.0, 0.0001)
	assert_float(side_lane).is_equal(0.0)
	assert_float(side_land).is_equal(0.0)
