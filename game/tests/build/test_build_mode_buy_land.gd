class_name TestBuildModeBuyLand
extends GdUnitTestSuite
## The Buy land tool in build mode (user ruling land-plots-are-bought-with-a-
## buy-land-tool-in-build-mode-buy) on the airport site: buyable plots get a
## dim fill, hovering one shows its price over it, on the status line and on
## BuildMenu's cost line, one click buys it from the wallet, the outline grows
## round it, and building there is then allowed where it was refused before.
## A plot out of reach, or one the wallet cannot pay, is refused and nothing
## changes.

const SITE := preload("res://build/terminal_site.tres")
## Plot (2, 4) touches the start land; (3, 0) does not.
const BUYABLE := Vector2i(2, 4)
const OUT_OF_REACH := Vector2i(3, 0)
## A cell of plot (2, 4).
const NEW_CELL := Vector2i(60, 110)

var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _outline: BuildableOutline


func before_test() -> void:
	_finances = auto_free(Finances.new())
	add_child(_finances)
	_mode = auto_free(BuildMode.new())
	_mode.site = SITE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_menu = auto_free(BuildMenu.new())
	_menu.build_mode = _mode
	add_child(_menu)
	_outline = auto_free(BuildableOutline.new())
	_outline.build_mode = _mode
	add_child(_outline)


## The middle of a plot on the ground.
func _middle(plot: Vector2i) -> Vector3:
	var cells := _mode.land_tool.land.plot_cells(plot)
	return _mode.grid.cell_to_world(cells.position + cells.size / 2)


func _land() -> LandPlots:
	return _mode.land_tool.land


func test_the_tool_shows_a_dim_fill_on_each_buyable_plot_only_while_picked() -> void:
	var tool := _mode.land_tool
	assert_bool(tool.visible).is_false()
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	assert_bool(tool.visible).is_true()
	# Two triangles per buyable plot.
	var buyable := _land().buyable_plots().size()
	assert_int(buyable).is_equal(5)
	assert_int(tool.fill_mesh().get_faces().size()).is_equal(buyable * 6)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(tool.visible).is_false()


func test_hovering_a_buyable_plot_shows_its_price() -> void:
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	_mode.call("_update_ghost", _middle(BUYABLE))
	var price := PriceTable.price_of_land_plot(0)
	var label := _mode.land_tool.price_label()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("Buy  %d" % price)
	assert_str(_mode.status_text()).is_equal("Click to buy this 21x25 m plot")
	assert_vector(_mode.land_tool.preview_price()).is_equal(Vector2i(price, price))
	assert_str(_menu.preview_text()).is_equal("Cost %d" % price)
	assert_int(_menu.call("_card_price", BuildMode.Tool.BUY_LAND)).is_equal(price)


func test_one_click_buys_the_plot_and_building_there_is_then_allowed() -> void:
	var wallet := _finances.wallet
	var before := wallet.balance
	var floor := BuildEdit.paint_floor(NEW_CELL, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
	assert_int(_mode.grid.validate(floor).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	var corners_before := _outline.outline_points().size()
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	var result := _mode.apply_at(_middle(BUYABLE))
	assert_bool(result.ok).is_true()
	assert_bool(_land().is_owned(BUYABLE)).is_true()
	assert_int(before - wallet.balance).is_equal(PriceTable.price_of_land_plot(0))
	# The outline now runs round the bought plot, which juts out east of the
	# middle row: four corners become eight.
	assert_int(corners_before).is_equal(4)
	assert_int(_outline.outline_points().size()).is_equal(8)
	# The next plot costs more, on the card's price slot too (the plates showed
	# it kept the old price when the wallet moved before the count did).
	var label: Label = _menu.card_price_label(BuildMode.Tool.BUY_LAND)
	assert_str(label.text).is_equal(str(PriceTable.price_of_land_plot(1)))
	assert_int(_menu.call("_card_price", BuildMode.Tool.BUY_LAND)).is_equal(
		PriceTable.price_of_land_plot(1)
	)
	# The floor tool now paints there.
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var painted := _mode.apply_at(_mode.grid.cell_to_world(NEW_CELL))
	assert_bool(painted.ok).is_true()
	assert_int(_mode.grid.floor_at(NEW_CELL)).is_equal(BuildGrid.FLOOR_TILE)


func test_a_plot_out_of_reach_is_refused_with_its_reason() -> void:
	var before := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	_mode.call("_update_ghost", _middle(OUT_OF_REACH))
	assert_str(_mode.status_text()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.LAND_NOT_TOUCHING]
	)
	assert_bool(_mode.land_tool.price_label().visible).is_false()
	assert_vector(_mode.land_tool.preview_price()).is_equal(Vector2i.ZERO)
	var result := _mode.apply_at(_middle(OUT_OF_REACH))
	assert_int(result.reason).is_equal(BuildResult.Reason.LAND_NOT_TOUCHING)
	assert_bool(_land().is_owned(OUT_OF_REACH)).is_false()
	assert_int(_finances.wallet.balance).is_equal(before)


func test_a_plot_the_wallet_cannot_pay_is_refused_and_nothing_changes() -> void:
	var wallet := _finances.wallet
	var keep := PriceTable.price_of_land_plot(0) - 1
	assert_bool(wallet.spend(wallet.balance - keep, Wallet.Category.BUILD)).is_true()
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	_mode.call("_update_ghost", _middle(BUYABLE))
	assert_str(_mode.status_text()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.CANT_AFFORD]
	)
	# The price still shows, and the cost line says how much is missing.
	assert_bool(_mode.land_tool.price_label().visible).is_true()
	assert_str(_menu.preview_text()).contains("Short by 1")
	var result := _mode.apply_at(_middle(BUYABLE))
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_bool(_land().is_owned(BUYABLE)).is_false()
	assert_int(wallet.balance).is_equal(keep)
	assert_int(_land().bought).is_equal(0)


func test_a_buy_is_not_an_undo_step() -> void:
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	assert_bool(_mode.apply_at(_middle(BUYABLE)).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(0)


## After (2, 5) is bought the owned land turns in at cell corner (50, 125):
## the band runs on round that inner corner inside the land, and leaves the
## plot not owned to its north-east bare.
func test_the_outline_band_turns_round_an_inner_corner_inside_the_land() -> void:
	_mode.set_tool(BuildMode.Tool.BUY_LAND)
	assert_bool(_mode.apply_at(_middle(Vector2i(2, 5))).ok).is_true()
	var faces := _outline.strip_mesh().get_faces()
	var o := SITE.grid_origin
	var corner := Vector2(o.x + 44.0, o.z + 125.0)
	var inside_corner := corner + Vector2(-0.1, 0.1)
	var along_south := corner + Vector2(3.0, 0.1)
	var along_west := corner + Vector2(-0.1, -3.0)
	var not_owned := corner + Vector2(0.1, -0.1)
	for at in [inside_corner, along_south, along_west]:
		assert_bool(_covered(faces, at)).override_failure_message("%s bare" % at).is_true()
	assert_bool(_covered(faces, not_owned)).is_false()


static func _covered(faces: PackedVector3Array, at: Vector2) -> bool:
	for i in range(0, faces.size(), 3):
		var tri := PackedVector2Array(
			[
				Vector2(faces[i].x, faces[i].z),
				Vector2(faces[i + 1].x, faces[i + 1].z),
				Vector2(faces[i + 2].x, faces[i + 2].z),
			]
		)
		if Geometry2D.is_point_in_polygon(at, tri):
			return true
	return false


func test_the_buy_land_card_follows_a_load_that_leaves_the_wallet_alone() -> void:
	var wallet := _finances.wallet
	var first := PriceTable.price_of_land_plot(0)
	var second := PriceTable.price_of_land_plot(1)
	assert_bool(wallet.from_snapshot({"balance": str(first)})).is_true()
	assert_str(_menu.card_price_text(BuildMode.Tool.BUY_LAND)).is_equal(str(first))
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.BUY_LAND)).is_true()
	var owned := _land().owned_plots().map(func(p: Vector2i) -> Array: return [p.x, p.y])
	owned.append([BUYABLE.x, BUYABLE.y])
	var snapshot := {"plot_counts": [4, 6], "owned": owned, "bought": 1}
	assert_bool(_land().from_snapshot(snapshot)).is_true()
	# The wallet did not change, so nothing but the land told the menu.
	assert_int(wallet.balance).is_equal(first)
	assert_str(_menu.card_price_text(BuildMode.Tool.BUY_LAND)).is_equal(str(second))
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.BUY_LAND)).is_false()
	assert_that(_menu.card(BuildMode.Tool.BUY_LAND).modulate).is_equal(_menu.unaffordable_tint())
