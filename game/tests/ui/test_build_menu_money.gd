class_name TestBuildMenuMoney
extends GdUnitTestSuite
## BuildMenu's money: the Money slot shows the wallet and follows it, each
## card shows its live price and greys out when the wallet cannot pay it, and
## a cost line shows what the tool or the dragged rectangle costs and how much
## the wallet is short (ruling
## building-costs-money-from-a-starting-budget-you-can-t-build; costs stay
## neutral, never red, per hud-steal-list-self-clearing-alert-cards-money-hover-departu).

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag(area: Rect2i) -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_at(area.position))
	_mode.move_area(_at(area.end - Vector2i.ONE))


func test_the_money_slot_shows_the_starting_budget() -> void:
	assert_str(_menu.money_label().text).is_equal("Money  %d" % PriceTable.STARTING_BUDGET)


func test_the_money_slot_follows_the_wallet() -> void:
	_finances.wallet.spend(300)
	assert_str(_menu.money_label().text).is_equal("Money  %d" % (PriceTable.STARTING_BUDGET - 300))
	_finances.wallet.credit(1000)
	assert_str(_menu.money_label().text).is_equal("Money  %d" % (PriceTable.STARTING_BUDGET + 700))


func test_a_menu_with_no_finances_shows_no_money_and_free_cards() -> void:
	var bare := BuildMode.new()
	bare.grid_size = Vector2i(20, 20)
	_port.add_child(bare)
	var menu := BuildMenu.new()
	menu.build_mode = bare
	_port.add_child(menu)
	assert_str(menu.money_label().text).is_equal(BuildMenu.MONEY_TEXT)
	assert_str(menu.card_price_text(BuildMode.Tool.DESK)).is_equal(BuildMenu.PRICE_TEXT)
	assert_bool(menu.is_card_affordable(BuildMode.Tool.DESK)).is_true()
	assert_str(menu.preview_text()).is_equal("")


func test_every_card_shows_its_price_from_the_price_table() -> void:
	var expected := {
		BuildMode.Tool.FLOOR: PriceTable.FLOOR_PRICE,
		BuildMode.Tool.WALL: PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN],
		BuildMode.Tool.GLASS: PriceTable.WALL_PRICES[BuildGrid.WallKind.GLASS],
		BuildMode.Tool.DOOR: PriceTable.WALL_PRICES[BuildGrid.WallKind.DOOR],
		BuildMode.Tool.ENTRANCE: PriceTable.OBJECT_PRICES[&"entrance_door"],
		BuildMode.Tool.EXIT: PriceTable.OBJECT_PRICES[&"exit_door"],
		BuildMode.Tool.DESK: PriceTable.OBJECT_PRICES[&"checkin_desk"],
		BuildMode.Tool.SCANNER: PriceTable.OBJECT_PRICES[&"security_scanner"],
		BuildMode.Tool.SEATS: PriceTable.OBJECT_PRICES[&"seat_row"],
		BuildMode.Tool.COUNTER: PriceTable.OBJECT_PRICES[&"cafe_counter"],
		BuildMode.Tool.TABLE: PriceTable.OBJECT_PRICES[&"cafe_table"],
	}
	for tool in expected:
		assert_str(_menu.card_price_text(tool)).is_equal(str(expected[tool]))
	assert_str(_menu.card_price_text(BuildMode.Tool.CAFE_ROOM)).is_equal(BuildMenu.PRICE_TEXT)


func test_a_card_the_wallet_cannot_pay_greys_out_and_comes_back() -> void:
	var desk := _menu.card(BuildMode.Tool.DESK)
	var floor_card := _menu.card(BuildMode.Tool.FLOOR)
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.DESK)).is_true()
	var normal := desk.modulate
	_set_balance(399)
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.DESK)).is_false()
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.FLOOR)).is_true()
	assert_that(desk.modulate).is_not_equal(normal)
	assert_that(floor_card.modulate).is_equal(normal)
	_set_balance(400)
	assert_bool(_menu.is_card_affordable(BuildMode.Tool.DESK)).is_true()
	assert_that(desk.modulate).is_equal(normal)


func test_an_unaffordable_price_stays_neutral_not_red() -> void:
	var label := _menu.card_price_label(BuildMode.Tool.DESK)
	_set_balance(0)
	assert_str(_menu.card_price_text(BuildMode.Tool.DESK)).is_equal("400")
	assert_str(str(label.theme_type_variation)).is_equal("HudPrice")
	assert_bool(label.has_theme_color_override("font_color")).is_false()


func test_an_unaffordable_card_can_still_be_picked_to_see_the_shortfall() -> void:
	_set_balance(100)
	_menu.press_card(BuildMode.Tool.DESK)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	assert_str(_menu.preview_text()).is_equal("Cost 400   Short by 300")


func test_the_cost_line_shows_the_picked_tool_s_price() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	assert_str(_menu.preview_text()).is_equal("Cost 400")
	_menu.refresh_preview()
	assert_str(_menu.preview_label().text).is_equal("Cost 400")
	assert_bool(_menu.preview_label().visible).is_true()


func test_a_dragged_floor_rectangle_shows_its_cost_and_shortfall() -> void:
	_drag(Rect2i(2, 2, 3, 2))
	assert_str(_menu.preview_text()).is_equal("Cost %d" % (6 * PriceTable.FLOOR_PRICE))
	_set_balance(100)
	assert_str(_menu.preview_text()).is_equal("Cost 150   Short by 50")


func test_a_dragged_rectangle_does_not_charge_tiles_already_floored() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.apply_at(_at(Vector2i(2, 2)))
	_drag(Rect2i(2, 2, 3, 2))
	assert_str(_menu.preview_text()).is_equal("Cost %d" % (5 * PriceTable.FLOOR_PRICE))


func test_the_cost_line_is_empty_for_free_tools_and_hides() -> void:
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_str(_menu.preview_text()).is_equal("")
	_menu.refresh_preview()
	assert_bool(_menu.preview_label().visible).is_false()
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_str(_menu.preview_text()).is_equal("")
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_str(_menu.preview_text()).is_equal("")


func test_the_cost_line_ends_with_the_drag() -> void:
	_drag(Rect2i(2, 2, 3, 2))
	_mode.finish_area()
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_str(_menu.preview_text()).is_equal("")


func test_a_door_over_a_paid_wall_shows_the_net_price_not_the_card_price() -> void:
	var cell := Vector2i(5, 5)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.apply_at(_at(cell))
	_mode.set_tool(BuildMode.Tool.WALL)
	var step := BuildGrid.SIDE_STEP[BuildGrid.Side.NORTH]
	assert_bool(_mode.apply_at(_at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode._update_ghost(_at(cell))
	var plan := DoorPlacement.edits_for(_mode.grid, _mode.hover_edit())
	assert_int(plan.size()).is_equal(2)
	var refund := PriceTable.refund_of(PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN])
	var net := PriceTable.OBJECT_PRICES[&"entrance_door"] - refund
	assert_int(net).is_less(PriceTable.OBJECT_PRICES[&"entrance_door"])
	assert_str(_menu.preview_text()).is_equal("Cost %d" % net)
	assert_str(_menu.card_price_text(BuildMode.Tool.ENTRANCE)).is_equal("300")
	# The wallet must still hold the full door price, so a balance between the
	# net and the full price is short, and the line says by how much.
	_set_balance(net + 10)
	assert_str(_menu.preview_text()).is_equal("Cost %d   Short by %d" % [net, 300 - net - 10])


func test_the_cost_line_falls_back_to_the_card_price_off_the_grid() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode._update_ghost(null)
	assert_object(_mode.hover_edit()).is_null()
	assert_str(_menu.preview_text()).is_equal("Cost 300")


func test_the_unaffordable_tint_comes_from_the_hud_theme() -> void:
	assert_that(BuildMenu.unaffordable_tint()).is_equal(
		BuildMenu.HUD_THEME.get_color("unaffordable_tint", "HudCard")
	)
	assert_that(BuildMenu.unaffordable_tint()).is_not_equal(Color.WHITE)
	_set_balance(0)
	assert_that(_menu.card(BuildMode.Tool.DESK).modulate).is_equal(BuildMenu.unaffordable_tint())


func test_picking_a_tool_drops_the_old_tool_s_hovered_edit() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode._update_ghost(_at(Vector2i(3, 3)))
	assert_str(_menu.preview_text()).is_equal("Cost 25")
	_menu.press_card(BuildMode.Tool.DESK)
	assert_object(_mode.hover_edit()).is_null()
	assert_str(_menu.preview_text()).is_equal("Cost 400")
