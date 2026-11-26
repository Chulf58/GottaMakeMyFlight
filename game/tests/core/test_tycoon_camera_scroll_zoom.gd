class_name TestTycoonCameraScrollZoom
extends GdUnitTestSuite

var _port: SubViewport
var _rig: TycoonCamera
var _panel: PanelContainer
var _scroll: ScrollContainer


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1024, 768)
	add_child(_port)
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = scene.instantiate() as TycoonCamera
	_rig.settings_path = SaveTestKit.run_path("camera_scroll_zoom")
	_port.add_child(_rig)
	var layer := CanvasLayer.new()
	_port.add_child(layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(40.0, 40.0)
	_panel.custom_minimum_size = Vector2(260.0, 200.0)
	layer.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(240.0, 180.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	for i in 20:
		var label := Label.new()
		label.text = "Row %d" % i
		label.custom_minimum_size = Vector2(200.0, 30.0)
		rows.add_child(label)
	await get_tree().process_frame
	await get_tree().process_frame


func after() -> void:
	if _rig != null and not _rig.settings_path.is_empty():
		DirAccess.remove_absolute(_rig.settings_path)
	if _port != null:
		_port.free()


func before_test() -> void:
	_rig.distance = _rig.home_distance
	_scroll.scroll_vertical = 0


func _move_mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_port.push_input(motion)


func _wheel(button: MouseButton, at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		_port.push_input(ev)


func _max_scroll() -> int:
	var bar := _scroll.get_v_scroll_bar()
	return maxi(0, int(round(bar.max_value - bar.page)))


func test_wheel_at_top_scroll_limit_does_not_zoom_camera() -> void:
	assert_int(_max_scroll()).is_greater(0)
	_scroll.scroll_vertical = 0
	var over_scroll := _scroll.get_global_rect().get_center()
	_move_mouse(over_scroll)
	var start_dist := _rig.target_distance
	_wheel(MOUSE_BUTTON_WHEEL_UP, over_scroll)
	assert_int(_scroll.scroll_vertical).is_equal(0)
	assert_float(_rig.target_distance).is_equal(start_dist)


func test_wheel_at_bottom_scroll_limit_does_not_zoom_camera() -> void:
	var bottom := _max_scroll()
	assert_int(bottom).is_greater(0)
	_scroll.scroll_vertical = bottom
	var over_scroll := _scroll.get_global_rect().get_center()
	_move_mouse(over_scroll)
	var start_dist := _rig.target_distance
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, over_scroll)
	assert_int(_scroll.scroll_vertical).is_equal(bottom)
	assert_float(_rig.target_distance).is_equal(start_dist)


func test_wheel_inside_scroll_range_scrolls_without_zooming_camera() -> void:
	assert_int(_max_scroll()).is_greater(0)
	_scroll.scroll_vertical = 0
	var over_scroll := _scroll.get_global_rect().get_center()
	_move_mouse(over_scroll)
	var start_dist := _rig.target_distance
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, over_scroll)
	assert_int(_scroll.scroll_vertical).is_greater(0)
	assert_float(_rig.target_distance).is_equal(start_dist)


func test_wheel_over_empty_viewport_zooms_camera() -> void:
	var world_pt := Vector2(800.0, 600.0)
	assert_bool(_panel.get_global_rect().has_point(world_pt)).is_false()
	_move_mouse(world_pt)
	var start_dist := _rig.target_distance
	_wheel(MOUSE_BUTTON_WHEEL_UP, world_pt)
	assert_float(_rig.target_distance).is_less(start_dist)
	var after_up := _rig.target_distance
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, world_pt)
	assert_float(_rig.target_distance).is_greater(after_up)
