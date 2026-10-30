class_name TestGhostReason
extends GdUnitTestSuite
## The short refusal reason beside the build ghost (HUD 6/7; decision hud-
## steal-list-self-clearing-alert-cards-money-hover-departu, item 6): a refused
## placement under the pointer shows a few words next to it, a placeable one
## shows nothing, and the status line keeps the whole reason.

const POINTER := Vector2(400.0, 300.0)

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_menu.ghost_reason().set_process(false)


func after_test() -> void:
	_port.free()


## Hovers the cell as the pointer would (BuildMode's own hover step), then
## lets the card follow POINTER.
func _hover(cell: Vector2i, pointer := POINTER) -> void:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	_menu.ghost_reason().refresh(pointer)


func _floor(from: Vector2i, to: Vector2i) -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y))).ok).is_true()


func test_a_refused_placement_shows_its_short_reason_beside_the_pointer() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_hover(Vector2i(4, 4))
	var card := _menu.ghost_reason()
	print(
		(
			"card %s visible=%s at %s; status %s"
			% [card.text(), card.visible, card.position, _mode.status_text()]
		)
	)
	assert_bool(card.visible).is_true()
	assert_str(card.text()).is_equal("Needs floor")
	assert_vector(card.position).is_equal(POINTER + GhostReason.OFFSET)
	# The status line above the tray keeps the whole reason.
	assert_str(_mode.status_text()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.NO_FLOOR])


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


func test_no_tool_or_no_hover_shows_no_card() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_hover(Vector2i(4, 4))
	assert_bool(_menu.ghost_reason().visible).is_false()
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode._update_ghost(null)
	_menu.ghost_reason().refresh(POINTER)
	assert_bool(_menu.ghost_reason().visible).is_false()


func test_the_card_stays_inside_the_window_near_its_edges() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	var corner := Vector2(_port.size) - Vector2(4.0, 4.0)
	_hover(Vector2i(4, 4), corner)
	var card := _menu.ghost_reason()
	var rect := Rect2(card.position, card.size)
	print("corner card %s in %s" % [rect, _port.size])
	assert_bool(card.visible).is_true()
	assert_bool(Rect2(Vector2.ZERO, Vector2(_port.size)).encloses(rect)).is_true()
	assert_float(card.size.x).is_greater(20.0)


func test_every_short_reason_is_shorter_than_its_full_text() -> void:
	for reason in GhostReason.SHORT_TEXT:
		var short: String = GhostReason.SHORT_TEXT[reason]
		var full: String = BuildResult.REASON_TEXT[reason]
		assert_int(short.length()).override_failure_message(full).is_less(full.length())
		assert_int(short.length()).override_failure_message(short).is_less_equal(24)
