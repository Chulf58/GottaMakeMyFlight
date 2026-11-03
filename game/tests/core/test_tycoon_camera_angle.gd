class_name TestTycoonCameraAngle
extends GdUnitTestSuite
## The camera angle: three player-chosen steps, fixed while zooming, remembered
## in the HUD settings file, top-down by default (decision camera-angle-is-a-
## player-setting-fixed-while-zooming).

## Half the side of the ground plane in main.tscn (a 2400 m PlaneMesh).
const GROUND_HALF := 1200.0
## View rays per side of the coverage grid.
const RAY_GRID := 12

var _path: String
var _rig: TycoonCamera


func before_test() -> void:
	_path = "user://test_camera_angle_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(_path)
	_rig = _new_rig()


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _new_rig() -> TycoonCamera:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	var rig := scene.instantiate() as TycoonCamera
	rig.settings_path = _path
	add_child(rig)
	return auto_free(rig)


func _tilt_degrees(rig: TycoonCamera) -> float:
	var cam: Camera3D = rig.get_node("Camera3D")
	return rad_to_deg(-cam.rotation.x)


func _key(code: Key, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event


func test_the_default_is_the_top_down_step() -> void:
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	assert_float(_tilt_degrees(_rig)).is_equal_approx(70.0, 0.001)


func test_each_step_has_its_own_pitch_and_they_rise_from_low_to_top_down() -> void:
	var seen: Array[float] = []
	for step in [
		TycoonCamera.AngleStep.LOW, TycoonCamera.AngleStep.MEDIUM, TycoonCamera.AngleStep.TOP_DOWN
	]:
		_rig.set_angle_step(step)
		_rig._process(0.0)
		var pitch := _tilt_degrees(_rig)
		assert_float(pitch).is_equal_approx(_rig.pitch_degrees(), 0.001)
		seen.append(pitch)
	assert_array(seen).has_size(3)
	assert_float(seen[0]).is_equal_approx(38.0, 0.001)
	assert_float(seen[1]).is_equal_approx(54.0, 0.001)
	assert_float(seen[2]).is_equal_approx(70.0, 0.001)


func test_the_tilt_is_the_same_at_min_home_and_max_distance_on_every_step() -> void:
	for step in [0, 1, 2]:
		_rig.set_angle_step(step)
		var expected := _rig.pitch_degrees()
		for d in [_rig.min_distance, _rig.home_distance, 150.0, _rig.max_distance]:
			_rig.distance = d
			_rig._process(0.0)
			(
				assert_float(_tilt_degrees(_rig))
				. override_failure_message("step %d at %s m" % [step, d])
				. is_equal_approx(expected, 0.001)
			)


func test_the_tilt_holds_through_a_zoom_ease() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_rig.zoom(3.0)
	for i in 30:
		_rig._process(0.05)
		assert_float(_tilt_degrees(_rig)).is_equal_approx(54.0, 0.001)
	assert_float(_rig.distance).is_greater(_rig.home_distance)


func test_the_camera_looks_at_the_focus_on_every_step_at_both_zoom_ends() -> void:
	var cam: Camera3D = _rig.get_node("Camera3D")
	for step in [0, 1, 2]:
		_rig.set_angle_step(step)
		for d in [_rig.min_distance, _rig.max_distance]:
			_rig.distance = d
			_rig._process(0.0)
			var forward := -cam.global_transform.basis.z
			var to_focus := (_rig.global_position - cam.global_position).normalized()
			assert_float(forward.dot(to_focus)).is_greater(0.999)
			assert_float(cam.global_position.distance_to(_rig.global_position)).is_equal_approx(
				d, 0.01
			)


func test_the_step_round_trips_through_the_settings_file() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	assert_int(_new_rig().angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	var again := _new_rig()
	assert_int(again.angle_step).is_equal(TycoonCamera.AngleStep.MEDIUM)
	assert_float(_tilt_degrees(again)).is_equal_approx(54.0, 0.001)


func test_the_step_sits_beside_the_other_hud_settings() -> void:
	HudFlagSetting.save_flag(_path, "hints", false, "test")
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	assert_bool(HudFlagSetting.load_flag(_path, "hints", true, "test")).is_false()
	assert_int(HudFlagSetting.load_int(_path, TycoonCamera.ANGLE_KEY, -1, "test")).is_equal(0)


func test_a_missing_or_out_of_range_saved_step_gives_a_step_not_a_crash() -> void:
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	HudFlagSetting.save_int(_path, TycoonCamera.ANGLE_KEY, 99, "test")
	assert_int(_new_rig().angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	HudFlagSetting.save_int(_path, TycoonCamera.ANGLE_KEY, -3, "test")
	assert_int(_new_rig().angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)


func test_cycling_walks_low_medium_top_down_and_wraps() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	_rig.cycle_angle_step()
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.MEDIUM)
	_rig.cycle_angle_step()
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	_rig.cycle_angle_step()
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)


func test_the_v_key_cycles_the_step_and_a_modified_v_does_not() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	_rig._unhandled_input(_key(KEY_V, true))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	_rig._unhandled_input(_key(KEY_V))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.MEDIUM)
	_rig._unhandled_input(_key(KEY_X))
	assert_int(_rig.angle_step).is_equal(TycoonCamera.AngleStep.MEDIUM)


func test_the_v_key_is_free_in_the_input_map() -> void:
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			# Ctrl+V (paste) is a different chord; the camera ignores modified V.
			if event is InputEventKey and not (event.ctrl_pressed or event.meta_pressed):
				(
					assert_bool(event.physical_keycode == KEY_V or event.keycode == KEY_V)
					. override_failure_message("action %s already uses V" % action)
					. is_false()
				)


func test_a_step_change_keeps_the_focus_and_refits_the_start_view() -> void:
	var area := Rect2(Vector2(-23.5, -94.8), Vector2(12.0, 30.0))
	_rig.frame_start_view(area)
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	var low_fit: float = _rig.framing_for(area)["distance"]
	_rig.set_angle_step(TycoonCamera.AngleStep.TOP_DOWN)
	var top_fit: float = _rig.framing_for(area)["distance"]
	assert_float(low_fit).is_not_equal(top_fit)
	assert_float(_rig.target_distance).is_equal_approx(top_fit, 0.001)
	assert_vector(_rig.position).is_equal_approx(
		Vector3(area.get_center().x, 0.0, area.get_center().y), Vector3.ONE * 0.001
	)


func test_home_frames_the_area_at_the_chosen_angle() -> void:
	var area := Rect2(Vector2(-23.5, -94.8), Vector2(12.0, 30.0))
	var cam: Camera3D = _rig.get_node("Camera3D")
	for step in [0, 1, 2]:
		_rig.set_angle_step(step)
		_rig.frame_start_view(area)
		_rig.pan(Vector2(0.5, 0.5))
		_rig.zoom(2.0)
		_rig.go_home()
		for i in 200:
			_rig._process(0.05)
		assert_float(_rig.distance).is_equal_approx(_rig.framing_for(area)["distance"], 0.05)
		assert_float(_tilt_degrees(_rig)).is_equal_approx(_rig.pitch_degrees(), 0.001)
		for x in [area.position.x, area.end.x]:
			for z in [area.position.y, area.end.y]:
				(
					assert_bool(cam.is_position_in_frustum(Vector3(x, 0.0, z)))
					. override_failure_message(
						"step %d: corner (%s, %s) out of view" % [step, x, z]
					)
					. is_true()
				)


func test_glide_to_keeps_the_angle() -> void:
	_rig.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_rig.glide_to(Vector3(40.0, 0.0, -30.0), 25.0)
	for i in 120:
		_rig._process(0.05)
		assert_float(_tilt_degrees(_rig)).is_equal_approx(54.0, 0.001)
	assert_float(_rig.distance).is_equal_approx(25.0, 0.05)


## At the farthest zoom, looking outward from the focus bounds, every view ray
## on every step must land on the ground plane, inside its mesh and inside the
## camera's far clip (the far ground edge, board a9721b10): the low step looks
## much further than the old 65 degree far view did.
func test_the_ground_fills_the_view_at_max_zoom_on_every_step() -> void:
	var cam: Camera3D = _rig.get_node("Camera3D")
	var edge := _rig.bounds_half_extent
	for step in [0, 1, 2]:
		_rig.set_angle_step(step)
		_rig.distance = _rig.max_distance
		for dir in [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]:
			_rig.position = Vector3(dir.x * edge, 0.0, dir.y * edge)
			_rig.yaw = atan2(-dir.x, -dir.y)
			_rig._process(0.0)
			var size := get_viewport().get_visible_rect().size
			for iy in RAY_GRID:
				for ix in RAY_GRID:
					var px := Vector2(
						(ix + 0.5) / RAY_GRID * size.x, (iy + 0.5) / RAY_GRID * size.y
					)
					var ray := cam.project_ray_normal(px)
					var origin := cam.global_position
					var msg := "step %d dir %s ray (%d,%d)" % [step, dir, ix, iy]
					(
						assert_float(ray.y)
						. override_failure_message(msg + " misses the ground")
						. is_less(0.0)
					)
					var hit := origin + ray * (-origin.y / ray.y)
					(
						assert_float(maxf(absf(hit.x), absf(hit.z)))
						. override_failure_message(msg + " lands off the ground mesh at %s" % hit)
						. is_less(GROUND_HALF)
					)
					(
						assert_float(origin.distance_to(hit))
						. override_failure_message(msg + " lands past the far clip at %s" % hit)
						. is_less(cam.far)
					)
