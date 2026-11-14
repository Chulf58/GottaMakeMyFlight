class_name TestHoverTargetSigns
extends GdUnitTestSuite
## HoverTarget with station-sign providers and no passengers (decision calm-view-
## technical-design-shared-hover-target-reusing-click, parts 1-2): a sign wins
## only inside its rect plus SIGN_MARGIN_PX, a mouse-catching HUD Control over
## the pointer blocks every target, a click pins a sign until a click elsewhere,
## Esc, the sign going or a load, and the cream tooltip shows the provider's text
## beside the sign.

const SIGN := Rect2(600.0, 400.0, 40.0, 40.0)

var _hover: HoverTarget
var _signs: FakeSignProvider
var _save: SaveGame


func before_test() -> void:
	_save = SaveGame.new()
	_hover = HoverTarget.new()
	_hover.save_game = _save
	add_child(_hover)
	_signs = FakeSignProvider.new()
	_signs.add(&"desk", SIGN, "Waiting for staff")
	_hover.register_provider(_signs)


func after_test() -> void:
	_hover.free()
	_save.free()


func _hover_at(point: Vector2) -> HoverTarget.Target:
	_hover.pointer_override = point
	_hover.refresh()
	return _hover.hovered_target()


func _click(point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	click.global_position = point
	get_viewport().push_input(click, true)
	_hover.refresh()


func _sign_key(target: HoverTarget.Target) -> Variant:
	return target.key if target != null and target.kind == HoverTarget.Kind.SIGN else null


func test_a_sign_wins_inside_its_rect_and_margin_only() -> void:
	var margin := HoverTarget.SIGN_MARGIN_PX
	var centre := SIGN.get_center()
	var inside_margin := Vector2(SIGN.position.x - margin + 1.0, centre.y)
	var outside_margin := Vector2(SIGN.position.x - margin - 2.0, centre.y)
	var at_centre: Variant = _sign_key(_hover_at(centre))
	var at_edge: Variant = _sign_key(_hover_at(inside_margin))
	var beyond := _hover_at(outside_margin)
	print("centre %s, margin edge %s, beyond %s" % [at_centre, at_edge, beyond])
	assert_that(at_centre).is_equal(&"desk")
	assert_that(at_edge).is_equal(&"desk")
	assert_object(beyond).is_null()


func test_of_two_overlapping_signs_the_nearest_centre_wins() -> void:
	_signs.add(&"scanner", Rect2(SIGN.position + Vector2(30.0, 0.0), SIGN.size), "Closed by you")
	var near_desk: Variant = _sign_key(_hover_at(SIGN.position + Vector2(32.0, 20.0)))
	var near_scanner: Variant = _sign_key(_hover_at(SIGN.position + Vector2(40.0, 20.0)))
	print("near desk %s, near scanner %s" % [near_desk, near_scanner])
	assert_that(near_desk).is_equal(&"desk")
	assert_that(near_scanner).is_equal(&"scanner")


func test_a_visible_mouse_catching_hud_control_blocks_the_target() -> void:
	var layer := CanvasLayer.new()
	var panel := Panel.new()
	panel.position = SIGN.position - Vector2(10.0, 10.0)
	panel.size = SIGN.size + Vector2(20.0, 20.0)
	layer.add_child(panel)
	add_child(layer)
	var centre := SIGN.get_center()
	var blocked := _hover_at(centre)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ignored: Variant = _sign_key(_hover_at(centre))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	var hidden: Variant = _sign_key(_hover_at(centre))
	print("blocked %s, ignore-filter %s, hidden panel %s" % [blocked, ignored, hidden])
	assert_object(blocked).is_null()
	assert_that(ignored).is_equal(&"desk")
	assert_that(hidden).is_equal(&"desk")
	layer.free()


func test_a_click_pins_the_sign_and_hover_elsewhere_keeps_the_pin() -> void:
	_hover_at(SIGN.get_center())
	_click(SIGN.get_center())
	var away := Vector2(100.0, 100.0)
	var hovered := _hover_at(away)
	var pinned: Variant = _sign_key(_hover.pinned_target())
	var shown: Variant = _sign_key(_hover.shown_target())
	print("after moving away: hovered %s pinned %s shown %s" % [hovered, pinned, shown])
	assert_object(hovered).is_null()
	assert_that(pinned).is_equal(&"desk")
	assert_that(shown).is_equal(&"desk")


func test_a_click_on_a_sign_takes_the_click() -> void:
	var handled := [false]
	var probe := func(_event: InputEvent) -> void: handled[0] = true
	var spy := _UnhandledSpy.new(probe)
	add_child(spy)
	# The spy sits earlier in the tree, so it hears a click HoverTarget leaves.
	move_child(spy, 0)
	_click(Vector2(100.0, 100.0))
	var heard_off_sign: bool = handled[0]
	handled[0] = false
	_click(SIGN.get_center())
	print("spy heard: off-sign click %s, sign click %s" % [heard_off_sign, handled[0]])
	assert_bool(heard_off_sign).is_true()
	assert_bool(handled[0]).is_false()
	spy.free()


func test_a_click_elsewhere_unpins() -> void:
	_click(SIGN.get_center())
	var before: Variant = _sign_key(_hover.pinned_target())
	_click(Vector2(100.0, 100.0))
	print("pinned before %s, after a click elsewhere %s" % [before, _hover.pinned_target()])
	assert_that(before).is_equal(&"desk")
	assert_object(_hover.pinned_target()).is_null()


func test_esc_unpins_and_takes_the_key_only_while_a_sign_is_pinned() -> void:
	_click(SIGN.get_center())
	_hover.pointer_override = Vector2(100.0, 100.0)
	var esc := InputEventAction.new()
	esc.action = &"build_tool_none"
	esc.pressed = true
	get_viewport().push_input(esc)
	_hover.refresh()
	assert_object(_hover.pinned_target()).is_null()


func test_the_pin_and_hover_clear_when_the_sign_goes() -> void:
	_click(SIGN.get_center())
	_hover_at(SIGN.get_center())
	var pinned: Variant = _sign_key(_hover.pinned_target())
	var hovered: Variant = _sign_key(_hover.hovered_target())
	_signs.signs.clear()
	_hover.refresh()
	print("before: pinned %s hovered %s" % [pinned, hovered])
	assert_that(pinned).is_equal(&"desk")
	assert_that(hovered).is_equal(&"desk")
	assert_object(_hover.pinned_target()).is_null()
	assert_object(_hover.hovered_target()).is_null()
	assert_bool(_hover.tooltip().visible).is_false()


func test_an_unregistered_provider_drops_its_signs() -> void:
	_click(SIGN.get_center())
	var pinned: Variant = _sign_key(_hover.pinned_target())
	_hover.unregister_provider(_signs)
	_hover.refresh()
	assert_that(pinned).is_equal(&"desk")
	assert_object(_hover.pinned_target()).is_null()
	assert_object(_hover_at(SIGN.get_center())).is_null()


func test_a_load_clears_the_pin() -> void:
	_click(SIGN.get_center())
	var pinned: Variant = _sign_key(_hover.pinned_target())
	_hover.pointer_override = Vector2(100.0, 100.0)
	_save.loaded.emit(true)
	_hover.refresh()
	assert_that(pinned).is_equal(&"desk")
	assert_object(_hover.pinned_target()).is_null()


func test_the_tooltip_shows_the_sign_text_beside_the_sign() -> void:
	_hover_at(SIGN.get_center())
	var tip := _hover.tooltip()
	var rect := tip.get_global_rect()
	print("tooltip %s visible %s text '%s'" % [rect, tip.visible, tip.text()])
	assert_bool(tip.visible).is_true()
	assert_str(tip.text()).is_equal("Waiting for staff")
	assert_float(rect.position.x).is_greater_equal(SIGN.end.x)
	assert_float(rect.position.x - SIGN.end.x).is_less_equal(HudLayout.GAP + 1.0)
	assert_bool(rect.position.y < SIGN.end.y and rect.end.y > SIGN.position.y).is_true()
	assert_int(tip.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_tooltip_text_follows_the_provider_each_frame() -> void:
	_hover_at(SIGN.get_center())
	var first := _hover.tooltip().text()
	_signs.signs[0]["text"] = "Staff on the way"
	_hover.refresh()
	print("text before '%s' after '%s'" % [first, _hover.tooltip().text()])
	assert_str(first).is_equal("Waiting for staff")
	assert_str(_hover.tooltip().text()).is_equal("Staff on the way")


func test_the_tooltip_hides_with_no_target() -> void:
	_hover_at(SIGN.get_center())
	var shown := _hover.tooltip().visible
	_hover_at(Vector2(100.0, 100.0))
	assert_bool(shown).is_true()
	assert_bool(_hover.tooltip().visible).is_false()


## A node that records each unhandled input it hears.
class _UnhandledSpy:
	extends Node
	var _heard: Callable

	func _init(heard: Callable) -> void:
		_heard = heard

	func _unhandled_input(event: InputEvent) -> void:
		_heard.call(event)
