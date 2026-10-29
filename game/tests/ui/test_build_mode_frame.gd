class_name TestBuildModeFrame
extends GdUnitTestSuite
## The build mode sign (user ask 2026-10-29): a black and yellow hazard-stripe
## border and a "Build mode" sign show exactly while build mode lasts, ignore
## the mouse, stay inside the viewport at the HUD's 1.0 and 1.25 scale and keep
## off the bottom bar and the money slot.

const STRUCTURE := 0
const VIEWPORT := Rect2(0.0, 0.0, 1280.0, 720.0)

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func _world(ui_scale: float) -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.scale = Vector2.ONE * ui_scale
	_port.add_child(_menu)


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null


## A control's rectangle on the screen, layer scale included.
func _on_screen(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _parts(frame: BuildModeFrame) -> Array[Control]:
	var out: Array[Control] = [frame, frame.sign_panel()]
	for i in 4:
		out.append(frame.band(i))
	for child in frame.sign_panel().get_children():
		out.append(child as Control)
	return out


func test_the_border_is_as_thick_as_the_menu_margin() -> void:
	assert_float(BuildModeFrame.THICKNESS).is_equal(BuildMenu.MARGIN)


func test_the_frame_shows_exactly_while_build_mode_lasts() -> void:
	_world(1.0)
	var frame := _menu.build_frame
	assert_bool(frame.visible).is_false()
	_menu.press_category(STRUCTURE)
	assert_bool(frame.visible).is_true()
	_menu.press_card(BuildMode.Tool.WALL)
	assert_bool(frame.visible).is_true()
	_menu.press_category(1)
	assert_bool(frame.visible).is_true()
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(frame.visible).is_false()


func test_the_staff_panel_hides_the_frame() -> void:
	_world(1.0)
	_menu.press_category(STRUCTURE)
	_menu.press_staff()
	assert_bool(_menu.build_frame.visible).is_false()


func test_the_sign_reads_build_mode() -> void:
	_world(1.0)
	var texts := PackedStringArray()
	for label in _menu.build_frame.sign_panel().find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_array(texts).is_equal(PackedStringArray(["Build mode"]))


func test_nothing_in_the_frame_takes_the_mouse() -> void:
	_world(1.0)
	for part in _parts(_menu.build_frame):
		assert_int(part.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func _assert_inside_and_clear(ui_scale: float) -> void:
	_world(ui_scale)
	_menu.press_category(STRUCTURE)
	var frame := _menu.build_frame
	var bar := _menu.category_button(0).get_parent().get_parent() as Control
	var money := _menu.money_label().get_parent() as Control
	for i in 4:
		var rect := _on_screen(frame.band(i))
		print("scale %.2f band %d: %s" % [ui_scale, i, rect])
		assert_float(rect.size.x).is_greater(0.0)
		assert_float(rect.size.y).is_greater(0.0)
		assert_bool(VIEWPORT.grow(0.5).encloses(rect)).is_true()
		assert_bool(rect.intersects(_on_screen(bar))).is_false()
		assert_bool(rect.intersects(_on_screen(money))).is_false()
	var sign_rect := _on_screen(frame.sign_panel())
	print("scale %.2f sign: %s" % [ui_scale, sign_rect])
	assert_bool(VIEWPORT.encloses(sign_rect)).is_true()
	assert_float(sign_rect.get_center().x).is_equal_approx(VIEWPORT.get_center().x, 1.0)
	assert_bool(sign_rect.intersects(_on_screen(money))).is_false()
	for i in 4:
		assert_bool(sign_rect.intersects(_on_screen(frame.band(i)))).is_false()


func test_the_frame_stays_inside_the_viewport_and_clear_of_the_hud_at_scale_one() -> void:
	_assert_inside_and_clear(1.0)


func test_the_frame_stays_inside_the_viewport_and_clear_of_the_hud_at_scale_1_25() -> void:
	_assert_inside_and_clear(1.25)
