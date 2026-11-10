class_name TestBottomHudGrid
extends GdUnitTestSuite
## HUD 5/7 (board a2e95d4e, decision hud-grid-and-rails-one-spacing-grid-centred-
## top-row-right-ra part 1): the bottom of the HUD sits on the grid. The build
## bar is MARGIN off the bottom, the tray GAP above it, and the status line and
## the cost line are one TRAY_W x BUTTON_H card above the tray that fades under
## the build ghost (decision status-banner-fades-under-the-build-ghost-room-labels-slide)
## and keeps the "R rotate" hint on one line (decision
## no-rotate-card-in-build-trays-the-r-rotate-key-is-shown-as-a). Templates and
## Debug stand on the same margin. Layout px 1536x864.

const VIEW := Vector2i(1536, 864)
const LONG_REFUSAL := (
	"Too close to a wall: the desk needs a clear tile on every side before it can go "
	+ "here, and this one is blocked by the cafe counter next door"
)

var _port: SubViewport
var _world: PassengerTestWorld
var _mode: BuildMode
var _menu: BuildMenu
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = VIEW
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = Finances.new()
	_port.add_child(_mode.finances)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.alert_settings_path = SaveTestKit.run_path("bottom_hud_grid_setting")
	_port.add_child(_hud)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	_port.free()
	_world.free_all()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## Puts the pointer over a grid cell, so the status line shows.
func _point_at_grid() -> void:
	_mode._update_ghost(_mode.grid.cell_to_world(Vector2i(3, 3)))


func _open_tray_with_status(text: String) -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	_point_at_grid()
	_mode.status_changed.emit(text)
	_menu.refresh_preview()
	await _settle()


func test_the_bar_stands_on_the_margin_and_the_tray_a_gap_above_it() -> void:
	_menu.press_category(0)
	await _settle()
	var bar := _menu.bar().get_global_rect()
	var tray := _menu.tray().get_global_rect()
	print("bar=%s tray=%s" % [bar, tray])
	assert_float(bar.end.y).is_equal(VIEW.y - float(HudLayout.MARGIN))
	assert_float(bar.size.y).is_equal(float(HudLayout.BAR_H))
	assert_float(tray.end.y).is_equal(bar.position.y - float(HudLayout.GAP))


func test_status_and_cost_are_one_card_above_the_tray() -> void:
	_menu.press_category(0)
	_mode.set_tool(BuildMode.Tool.DESK)
	_point_at_grid()
	_mode.status_changed.emit("Placed 1")
	_menu.refresh_preview()
	await _settle()
	var card := _menu.status_card()
	var tray := _menu.tray().get_global_rect()
	var rect := card.get_global_rect()
	print(
		(
			"card=%s tray=%s status='%s' cost='%s'"
			% [rect, tray, _menu.status_label().text, _menu.preview_label().text]
		)
	)
	assert_bool(card.visible).is_true()
	assert_float(rect.size.x).is_equal(float(HudLayout.TRAY_W))
	assert_float(rect.size.y).is_equal(float(HudLayout.BUTTON_H))
	assert_float(rect.end.y).is_equal(tray.position.y - float(HudLayout.GAP))
	assert_float(rect.get_center().x).is_equal(VIEW.x / 2.0)
	# Both lines live in that one card, side by side.
	assert_bool(card.is_ancestor_of(_menu.status_label())).is_true()
	assert_bool(card.is_ancestor_of(_menu.preview_label())).is_true()
	assert_bool(_menu.preview_label().visible).is_true()
	assert_str(_menu.preview_label().text).is_equal("Cost 400")
	var status := _menu.status_label().get_global_rect()
	var cost := _menu.preview_label().get_global_rect()
	assert_float(status.end.x).is_less_equal(cost.position.x)
	assert_float(status.position.y).is_greater_equal(rect.position.y)
	assert_float(cost.end.y).is_less_equal(rect.end.y)
	assert_str(str(card.theme_type_variation)).is_equal("HudTopCard")
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# The stack's height, which the rail and PanelRoom read, is the card's top.
	assert_float(BuildMenu.tray_stack_top()).is_equal(VIEW.y - rect.position.y)


func test_the_card_is_hidden_while_nothing_is_said_and_costs_nothing() -> void:
	_menu.press_category(0)
	await _settle()
	assert_bool(_menu.status_card().visible).is_false()


func test_the_card_fades_under_the_ghost_and_comes_back() -> void:
	_menu.press_category(0)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_point_at_grid()
	_mode.status_changed.emit("Placed 1")
	_menu.refresh_preview()
	await _settle()
	var card := _menu.status_card()
	var under := card.get_global_rect().grow(-4.0)
	for i in 30:
		_menu.fade_for(under, 0.1)
	assert_float(card.modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# A faded card still counts as an obstacle for the refusal-card nudge.
	assert_bool(card.visible).is_true()
	for i in 30:
		_menu.fade_for(Rect2(0.0, 0.0, 20.0, 20.0), 0.1)
	assert_float(card.modulate.a).is_equal_approx(1.0, 0.001)
	for i in 30:
		_menu.fade_for(Rect2(), 0.1)
	assert_float(card.modulate.a).is_equal_approx(1.0, 0.001)


## Smoke playtest 11 friction (e): under a long refusal "R rotate" wrapped onto
## a second status line. The hint has its own slot in the card now; the refusal
## is the part that is cut short.
func test_a_long_refusal_never_pushes_the_rotate_hint_onto_a_second_line() -> void:
	_menu.press_category(0)
	await _open_tray_with_status(LONG_REFUSAL)
	var card := _menu.status_card()
	var hint := _menu.rotate_hint_label()
	var rect := card.get_global_rect()
	print(
		(
			"long: card=%s hint=%s status=%s"
			% [rect, hint.get_global_rect(), _menu.status_label().get_global_rect()]
		)
	)
	assert_bool(hint.visible).is_true()
	assert_str(hint.text).is_equal(RotateHint.TEXT)
	assert_int(hint.get_line_count()).is_equal(1)
	assert_int(_menu.status_label().get_line_count()).is_equal(1)
	assert_float(rect.size.y).is_equal(float(HudLayout.BUTTON_H))
	assert_bool(card.get_global_rect().encloses(hint.get_global_rect())).is_true()
	assert_bool(card.get_global_rect().encloses(_menu.status_label().get_global_rect())).is_true()
	assert_str(_menu.status_label().text).is_equal(LONG_REFUSAL)


func test_a_long_refusal_with_a_cost_keeps_hint_and_cost_whole() -> void:
	_menu.press_category(0)
	_mode.set_tool(BuildMode.Tool.DESK)
	_point_at_grid()
	_mode.status_changed.emit(LONG_REFUSAL)
	_menu.refresh_preview()
	await _settle()
	var card := _menu.status_card().get_global_rect()
	var hint := _menu.rotate_hint_label()
	var cost := _menu.preview_label()
	assert_bool(hint.visible and cost.visible).is_true()
	assert_float(cost.get_global_rect().end.x).is_less_equal(card.end.x)
	assert_float(hint.get_global_rect().end.x).is_less_equal(cost.get_global_rect().position.x)
	assert_int(hint.get_line_count()).is_equal(1)
	assert_int(cost.get_line_count()).is_equal(1)
	assert_float(card.size.y).is_equal(float(HudLayout.BUTTON_H))


func test_no_hint_when_the_tool_places_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_point_at_grid()
	_mode.status_changed.emit("5 x 3")
	_menu.refresh_preview()
	await _settle()
	assert_bool(_menu.rotate_hint_label().visible).is_false()
	assert_bool(_menu.status_card().visible).is_true()


## A rescue grant message is long on purpose and is held for seconds: it wraps
## and the card grows up from its bottom edge, so it is still readable.
func test_a_held_message_wraps_and_the_card_grows_upward() -> void:
	_menu.press_category(0)
	await _settle()
	var bottom := _menu.status_card().get_global_rect().end.y
	var message := (
		"The airport authority has sent a rescue grant of 5000 to rebuild: a check-in desk, "
		+ "a scanner, floor. It is a one-off. A further 300 clears the owed wages (200) and "
		+ "upkeep (100)."
	)
	_menu._on_granted(5300, message)
	_menu.refresh_preview()
	await _settle()
	var rect := _menu.status_card().get_global_rect()
	print(
		(
			"held: card=%s lines=%d status=%s min=%s"
			% [
				rect,
				_menu.status_label().get_line_count(),
				_menu.status_label().get_global_rect(),
				_menu.status_label().get_combined_minimum_size()
			]
		)
	)
	assert_str(_menu.status_label().text).is_equal(message)
	assert_int(_menu.status_label().get_line_count()).is_greater(1)
	assert_float(rect.end.y).is_equal(bottom)
	assert_float(rect.size.y).is_greater(float(HudLayout.BUTTON_H))
	assert_bool(_menu.rotate_hint_label().visible).is_false()
	_menu.end_grant_hold()
	await _settle()
	assert_float(_menu.status_card().get_global_rect().size.y).is_equal(float(HudLayout.BUTTON_H))


func test_templates_and_debug_stand_on_the_margin_with_the_bar() -> void:
	var bar := _menu.bar().get_global_rect()
	var dock := _menu.templates_page.dock.get_global_rect()
	var debug := (_hud.find_child("DebugToggle", true, false) as Button).get_global_rect()
	print("bar=%s templates=%s debug=%s" % [bar, dock, debug])
	assert_float(dock.position.x).is_equal(float(HudLayout.MARGIN))
	assert_float(dock.end.y).is_equal(bar.end.y)
	assert_float(dock.size.y).is_equal(float(HudLayout.BAR_H))
	assert_float(debug.end.x).is_equal(VIEW.x - float(HudLayout.MARGIN))
	assert_float(debug.end.y).is_equal(VIEW.y - float(HudLayout.MARGIN))


func test_the_rail_stop_line_and_panel_room_clear_the_bar() -> void:
	var stack := _hud.find_child("AlertStack", false, false) as AlertStack
	var tray := [false]
	stack.build_tray_open = func() -> bool: return tray[0]
	var bar_top := float(_menu.bar().get_global_rect().position.y)
	var closed := stack._stop_y()
	assert_float(closed).is_equal(bar_top - float(HudLayout.GROUP_GAP))
	tray[0] = true
	_menu.press_category(0)
	await _settle()
	var card_top := _menu.status_card().get_global_rect().position.y
	assert_float(stack._stop_y()).is_equal(card_top - float(HudLayout.GROUP_GAP))
	var room := auto_free(PanelRoom.new()) as PanelRoom
	_port.add_child(room)
	assert_float(room._bar_strip().position.y).is_equal(bar_top)
	assert_float(room._tray_stack(_menu).position.y).is_equal(card_top)


func test_nothing_in_the_bottom_band_overlaps() -> void:
	_menu.press_category(0)
	_mode.set_tool(BuildMode.Tool.SEATS)
	_point_at_grid()
	_mode.status_changed.emit(LONG_REFUSAL)
	_menu.refresh_preview()
	_hud.set_debug_open(true)
	await _settle()
	var rects := {
		"bar": _menu.bar().get_global_rect(),
		"tray": _menu.tray().get_global_rect(),
		"card": _menu.status_card().get_global_rect(),
		"templates": _menu.templates_page.dock.get_global_rect(),
		"debug": (_hud.find_child("DebugToggle", true, false) as Button).get_global_rect(),
		"debug_panel": (_hud.find_child("DebugPanel", true, false) as Control).get_global_rect(),
	}
	print("bottom band: ", rects)
	var keys := rects.keys()
	for i in keys.size():
		assert_bool(Rect2(Vector2.ZERO, Vector2(VIEW)).encloses(rects[keys[i]])).is_true()
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			(
				assert_bool(a.intersects(b))
				. override_failure_message("%s %s overlaps %s %s" % [keys[i], a, keys[j], b])
				. is_false()
			)
