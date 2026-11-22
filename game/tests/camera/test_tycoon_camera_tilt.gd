class_name TestTycoonCameraTilt
extends GdUnitTestSuite
## Free vertical pitch tilt on Right-Mouse Drag (35-75 deg), angle-locked zoom,
## V cycling via InputMap, and settings persistence + legacy backwards
## compatibility (ruling camera-free-vertical-tilt-on-right-drag-and-angle-presets-in-settings).

var _path: String
var _rig: TycoonCamera
var _nodes: Array[Node] = []


func before_test() -> void:
	_path = SaveTestKit.run_path("camera_tilt").replace(".json", ".cfg")
	_remove_settings()
	_rig = _new_rig()


func after_test() -> void:
	for i in range(_nodes.size() - 1, -1, -1):
		var node := _nodes[i]
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	_rig = null
	_remove_settings()
	assert_bool(FileAccess.file_exists(_path)).is_false()


func _remove_settings() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _new_rig(parent: Node = self) -> TycoonCamera:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	var rig := scene.instantiate() as TycoonCamera
	rig.settings_path = _path
	parent.add_child(rig)
	_nodes.append(rig)
	return rig


func _camera_pitch_deg(rig: TycoonCamera) -> float:
	var cam: Camera3D = rig.get_node("Camera3D")
	return rad_to_deg(-cam.rotation.x)


func _right_drag(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	event.relative = relative
	return event


func _right_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	return event


func _key(code: Key, ctrl := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	return event


func test_right_drag_tilts_pitch_clamped_and_rotates_yaw() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	var start_yaw := _rig.yaw
	var start_pitch := _rig.pitch_degrees()
	assert_float(start_pitch).is_equal_approx(54.0, 0.001)

	# Dragging up (-relative.y) tilts toward horizon (lower pitch) while +x turns yaw.
	_rig._unhandled_input(_right_drag(Vector2(20.0, -40.0)))
	assert_float(_rig.yaw).is_less(start_yaw)
	assert_float(_rig.pitch_degrees()).is_less(start_pitch)
	assert_float(_rig.pitch_degrees()).is_equal_approx(54.0 - 40.0 * _rig.drag_tilt_speed, 0.001)
	assert_float(_camera_pitch_deg(_rig)).is_equal_approx(_rig.pitch_degrees(), 0.001)

	# Extreme upward drag clamps strictly at 35 deg.
	_rig._unhandled_input(_right_drag(Vector2(0.0, -2000.0)))
	assert_float(_rig.pitch_degrees()).is_equal_approx(35.0, 0.001)
	assert_float(_camera_pitch_deg(_rig)).is_equal_approx(35.0, 0.001)

	# Extreme downward drag (+relative.y) clamps strictly at 75 deg.
	_rig._unhandled_input(_right_drag(Vector2(0.0, 2000.0)))
	assert_float(_rig.pitch_degrees()).is_equal_approx(75.0, 0.001)
	assert_float(_camera_pitch_deg(_rig)).is_equal_approx(75.0, 0.001)


func test_zoom_keeps_custom_and_preset_pitch_unchanged() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_rig._unhandled_input(_right_drag(Vector2(0.0, -30.0)))
	var custom_pitch := _rig.pitch_degrees()
	assert_bool(_rig.is_custom_pitch()).is_true()

	_rig.zoom(0.5)
	for i in 20:
		_rig._process(0.05)
		assert_float(_rig.pitch_degrees()).is_equal_approx(custom_pitch, 0.001)
		assert_float(_camera_pitch_deg(_rig)).is_equal_approx(custom_pitch, 0.001)

	_rig.distance = _rig.max_distance
	_rig._process(0.0)
	assert_float(_camera_pitch_deg(_rig)).is_equal_approx(custom_pitch, 0.001)


func test_input_map_has_camera_angle_action_bound_to_v_and_cycles() -> void:
	assert_bool(InputMap.has_action("camera_angle")).is_true()
	var events := InputMap.action_get_events("camera_angle")
	assert_int(events.size()).is_equal(1)
	assert_int((events[0] as InputEventKey).physical_keycode).is_equal(KEY_V)

	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	_rig._unhandled_input(_key(KEY_V, true))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	_rig._unhandled_input(_key(KEY_V, false, true))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)

	_rig._unhandled_input(_key(KEY_V))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.MEDIUM)
	assert_float(_rig.pitch_degrees()).is_equal_approx(54.0, 0.001)

	_rig._unhandled_input(_key(KEY_V))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	assert_float(_rig.pitch_degrees()).is_equal_approx(70.0, 0.001)

	_rig._unhandled_input(_key(KEY_V))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	assert_float(_rig.pitch_degrees()).is_equal_approx(38.0, 0.001)


func test_custom_pitch_persists_on_release_and_round_trips() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	var delta_px := -30.0
	var expected := 54.0 + delta_px * _rig.drag_tilt_speed
	_rig._unhandled_input(_right_button(true))
	_rig._unhandled_input(_right_drag(Vector2(0.0, delta_px)))
	# Mid-drag defers disk write until right-button release.
	var cfg_before := ConfigFile.new()
	assert_int(cfg_before.load(_path)).is_equal(OK)
	(
		assert_float(
			float(cfg_before.get_value(HudFlagSetting.SECTION, TycoonCamera.PITCH_KEY, -1.0))
		)
		. is_equal_approx(54.0, 0.001)
	)

	_rig._unhandled_input(_right_button(false))
	var reloaded := _new_rig()
	assert_float(reloaded.pitch_degrees()).is_equal_approx(expected, 0.001)
	assert_bool(reloaded.is_custom_pitch()).is_true()


func test_legacy_settings_file_without_pitch_key_loads_step_pitch() -> void:
	HudFlagSetting.save_int(_path, TycoonCamera.ANGLE_KEY, TycoonCamera.AngleStep.LOW, "test")
	var low_rig := _new_rig()
	assert_int(low_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	assert_float(low_rig.pitch_degrees()).is_equal_approx(38.0, 0.001)

	HudFlagSetting.save_int(_path, TycoonCamera.ANGLE_KEY, 99, "test")
	var bad_rig := _new_rig()
	assert_int(bad_rig.angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	assert_float(bad_rig.pitch_degrees()).is_equal_approx(70.0, 0.001)


func test_focus_loss_notifications_flush_dirty_pitch_to_disk() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_rig._unhandled_input(_right_drag(Vector2(0.0, -32.0)))
	var expected_app := _rig.pitch_degrees()
	_rig.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_float(_new_rig().pitch_degrees()).is_equal_approx(expected_app, 0.001)

	_rig._unhandled_input(_right_drag(Vector2(0.0, 48.0)))
	var expected_wm := _rig.pitch_degrees()
	_rig.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_float(_new_rig().pitch_degrees()).is_equal_approx(expected_wm, 0.001)


func test_ui_consumed_right_release_flushes_dirty_pitch_to_disk() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(640, 360)
	add_child(port)
	_nodes.append(port)
	var rig := _new_rig(port)
	rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)

	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.size = Vector2(640.0, 360.0)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	port.add_child(blocker)

	rig._unhandled_input(_right_drag(Vector2(0.0, -36.0)))
	var expected := rig.pitch_degrees()
	var cfg_before := ConfigFile.new()
	assert_int(cfg_before.load(_path)).is_equal(OK)
	(
		assert_float(
			float(cfg_before.get_value(HudFlagSetting.SECTION, TycoonCamera.PITCH_KEY, -1.0))
		)
		. is_equal_approx(54.0, 0.001)
	)

	var release := _right_button(false)
	release.position = Vector2(320.0, 180.0)
	release.global_position = Vector2(320.0, 180.0)
	port.push_input(release, true)
	assert_float(_new_rig().pitch_degrees()).is_equal_approx(expected, 0.001)
