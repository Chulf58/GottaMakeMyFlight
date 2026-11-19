class_name TestBuildMenuCardHint
extends GdUnitTestSuite
## Placement mode ("Drag" / "Click"), footprint size, upkeep and needs moved off
## the compact card face into ItemCardButton's 280 px hover popup (decision
## build-menu-rework-six-domain-tabs-progressive-tab-and-card-u). A drag held by
## the pointer being over the HUD still keeps the status line visible.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _hover_texts(tool: BuildMode.Tool) -> Array[String]:
	var card := _menu.card(tool) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	var out: Array[String] = []
	for label in popup.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_every_area_tool_hover_popup_says_drag() -> void:
	var checked := 0
	for tool in BuildMode.AREA_TOOLS:
		if _menu.card(tool) == null:
			continue
		assert_array(_hover_texts(tool)).contains(["Drag"])
		checked += 1
	assert_int(checked).is_greater_equal(15)
	assert_array(_hover_texts(BuildMode.Tool.TOILET_ROOM)).contains(["2x3 min", "Drag"])
	assert_array(_hover_texts(BuildMode.Tool.BELT)).contains(["Drag a line", "Drag"])


func test_a_placed_item_hover_popup_says_click_size_and_upkeep_or_needs() -> void:
	assert_array(_hover_texts(BuildMode.Tool.TOILET_SINK)).contains(["1x1", "Click"])
	assert_array(_hover_texts(BuildMode.Tool.DESK)).contains(["2x1", "Click"])
	assert_array(_hover_texts(BuildMode.Tool.BAG_ROOM)).contains(
		["2x2 min", "Drag", "Needs belt end"]
	)
	assert_array(_hover_texts(BuildMode.Tool.TOILET_STALL)).contains(
		["1x2", "Click", BuildMenuCatalog.upkeep_text(PriceTable.TOILET_STALL_UPKEEP)]
	)


func test_the_status_line_stays_visible_while_the_hud_holds_a_drag() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(3, 3)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(8, 8)))
	_mode._area_over_ui = true
	_mode._hide_area_ghost()
	_menu.refresh_preview()
	assert_str(_menu.status_label().text).is_equal(BuildMode.DRAG_OVER_UI)
	assert_bool(_menu.status_label().visible).is_true()
	_mode._area_over_ui = false
	_mode.cancel_area()
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()
