class_name TestGhostReason
extends GdUnitTestSuite
## The short refusal reason beside the build ghost (HUD 6/7; decision hud-
## steal-list-self-clearing-alert-cards-money-hover-departu, item 6): a refused
## placement under the pointer shows a few words right of the drawn ghost's
## on-screen bounds (BuildMode.ghost_screen_rect()), a placeable one shows
## nothing, and the status line keeps the whole reason. A camera looks down on
## the grid so the ghost has a place on screen.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _camera: Camera3D


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_port.add_child(_mode)
	_mode.set_process(false)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 14.0, 10.0), Vector3.ZERO)
	_camera.make_current()
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_menu.ghost_reason().set_process(false)


func after_test() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse(false)
	_port.free()


## Hovers the cell as the pointer would (BuildMode's own hover step), then
## lets the card follow the ghost.
func _hover(cell: Vector2i) -> void:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	_menu.ghost_reason().refresh()


func _floor(from: Vector2i, to: Vector2i) -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y))).ok).is_true()


func _card_rect() -> Rect2:
	var card := _menu.ghost_reason()
	return Rect2(card.position, card.size)


func _on_screen(cell: Vector2i) -> Vector2:
	return _camera.unproject_position(_mode.grid.cell_to_world(cell))


func _mouse(pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = Vector2(100.0, 100.0)
	Input.parse_input_event(click)
	Input.flush_buffered_events()


## The card sits right of the ghost's bounds, GAP apart, level with its middle.
func _assert_beside_ghost(ghost: Rect2) -> void:
	var card := _card_rect()
	assert_float(card.position.x).is_equal_approx(ghost.end.x + GhostReason.GAP, 0.5)
	assert_float(card.get_center().y).is_equal_approx(ghost.get_center().y, 0.5)
	assert_bool(card.intersects(ghost)).is_false()


func test_a_refused_placement_shows_its_short_reason_beside_the_ghost() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	var card := _menu.ghost_reason()
	var ghost := _mode.ghost_screen_rect()
	var cell := _on_screen(Vector2i(4, 4))
	print("card %s %s ghost %s cell %s" % [card.text(), _card_rect(), ghost, cell])
	assert_bool(card.visible).is_true()
	assert_str(card.text()).is_equal("Needs floor")
	# The ghost stands on the hovered cell.
	assert_bool(ghost.has_area()).is_true()
	assert_bool(ghost.grow(1.0).has_point(cell)).is_true()
	_assert_beside_ghost(ghost)
	# The status line above the tray keeps the whole reason.
	assert_str(_mode.status_text()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.NO_FLOOR])


func test_a_large_ghost_puts_the_card_beside_its_bounds_not_the_pointer() -> void:
	var podium := BuildMode.Tool.NONE
	for tool in FurnitureTools.OBJECTS:
		if FurnitureTools.OBJECTS[tool] == &"prize_podium":
			podium = tool
	_mode.set_tool(podium)
	_hover(Vector2i(2, 2))
	var ghost := _mode.ghost_screen_rect()
	var pointer := _on_screen(Vector2i(2, 2))
	print(
		(
			"podium card %s %s ghost %s pointer %s"
			% [_menu.ghost_reason().text(), _card_rect(), ghost, pointer]
		)
	)
	assert_bool(_menu.ghost_reason().visible).is_true()
	# Control: the 6x3 ghost's middle is well away from the hovered cell.
	assert_float(ghost.get_center().distance_to(pointer)).is_greater(40.0)
	assert_float(ghost.size.x).is_greater(80.0)
	_assert_beside_ghost(ghost)
	# Placed off the pointer it would start about a cell right of it, inside the ghost.
	assert_float(_card_rect().position.x).is_greater(pointer.x + 60.0)


func test_a_placeable_edit_shows_no_card() -> void:
	_floor(Vector2i(2, 2), Vector2i(6, 6))
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	print("placeable: visible=%s status %s" % [_menu.ghost_reason().visible, _mode.status_text()])
	assert_bool(_menu.ghost_reason().visible).is_false()
	assert_str(_menu.ghost_reason().text()).is_empty()
	# Control: the same cell refuses a second desk on top of the first.
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 4))).ok).is_true()
	_hover(Vector2i(4, 4))
	print("on top: %s" % _menu.ghost_reason().text())
	assert_bool(_menu.ghost_reason().visible).is_true()
	assert_str(_menu.ghost_reason().text()).is_not_empty()


func test_the_card_follows_a_change_to_the_grid_under_the_same_hover() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	assert_str(_menu.ghost_reason().text()).is_equal("Needs floor")
	_floor(Vector2i(2, 2), Vector2i(6, 6))
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	assert_bool(_menu.ghost_reason().visible).is_false()


## An edit written straight to the grid, not through BuildMode (as the starter
## terminal is), sends neither grid_changed nor a status line change; the card
## still drops its stale answer.
func test_a_direct_grid_change_under_the_same_hover_clears_the_card() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	_menu.ghost_reason().refresh()
	assert_str(_menu.ghost_reason().text()).is_equal("Needs floor")
	for y in range(2, 7):
		for x in range(2, 7):
			var edit := BuildEdit.paint_floor(Vector2i(x, y), 1, 0)
			assert_bool(_mode.grid.apply(edit).ok).is_true()
	# Control: BuildMode has not looked again, so its status line is stale.
	assert_str(_mode.status_text()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.NO_FLOOR])
	assert_bool(_mode.check(_mode.hover_edit()).ok).is_true()
	_menu.ghost_reason().refresh()
	print("after a direct floor: visible=%s" % _menu.ghost_reason().visible)
	assert_bool(_menu.ghost_reason().visible).is_false()


func test_holding_the_button_on_a_refused_desk_keeps_the_card() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	_mouse(true)
	# Control: the left button is held, and no drag owns the hover.
	assert_bool(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)).is_true()
	assert_bool(_mode.is_dragging()).is_false()
	_menu.ghost_reason().refresh()
	print("held: visible=%s text=%s" % [_menu.ghost_reason().visible, _menu.ghost_reason().text()])
	assert_bool(_menu.ghost_reason().visible).is_true()
	assert_str(_menu.ghost_reason().text()).is_equal("Needs floor")
	_mouse(false)


func test_no_tool_or_no_hover_shows_no_card() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_hover(Vector2i(4, 4))
	assert_bool(_menu.ghost_reason().visible).is_false()
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode._update_ghost(null)
	_menu.ghost_reason().refresh()
	assert_bool(_menu.ghost_reason().visible).is_false()
	assert_bool(_mode.ghost_screen_rect().has_area()).is_false()


func test_the_card_stays_inside_the_window_beside_a_ghost_near_its_edge() -> void:
	_port.size = Vector2i(360, 320)
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(8, 5))
	var ghost := _mode.ghost_screen_rect()
	var card := _card_rect()
	print("edge card %s ghost %s in %s" % [card, ghost, _port.size])
	assert_bool(_menu.ghost_reason().visible).is_true()
	# Control: there is no room for the card right of the ghost.
	assert_float(ghost.end.x + GhostReason.GAP + card.size.x).is_greater(_port.size.x - 8.0)
	assert_bool(Rect2(Vector2.ZERO, Vector2(_port.size)).encloses(card)).is_true()
	assert_bool(card.intersects(ghost)).is_false()
	assert_float(card.size.x).is_greater(20.0)


func test_every_short_reason_is_shorter_than_its_full_text() -> void:
	for reason in GhostReason.SHORT_TEXT:
		var short: String = GhostReason.SHORT_TEXT[reason]
		var full: String = BuildResult.REASON_TEXT[reason]
		assert_int(short.length()).override_failure_message(full).is_less(full.length())
		assert_int(short.length()).override_failure_message(short).is_less_equal(24)
