class_name TestTycoonCamera
extends GdUnitTestSuite

var _rig: TycoonCamera


func before_test() -> void:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = auto_free(scene.instantiate()) as TycoonCamera
	_rig.settings_path = SaveTestKit.run_path("camera_zoom")
	add_child(_rig)


func test_zoom_is_clamped_both_ways() -> void:
	for i in 100:
		_rig.zoom(0.5)
	assert_float(_rig.target_distance).is_equal(_rig.min_distance)
	_settle()
	assert_float(_rig.distance).is_equal_approx(_rig.min_distance, 0.01)
	for i in 100:
		_rig.zoom(2.0)
	assert_float(_rig.target_distance).is_equal(_rig.max_distance)
	_settle()
	assert_float(_rig.distance).is_equal_approx(_rig.max_distance, 0.01)


func test_pan_is_clamped_to_bounds() -> void:
	_rig.pan(Vector2(1000.0, -1000.0))
	assert_float(_rig.position.x).is_equal(_rig.bounds_half_extent)
	assert_float(_rig.position.z).is_equal(-_rig.bounds_half_extent)


func test_pan_follows_yaw() -> void:
	_rig.rotate_yaw(PI / 2.0)
	_rig.pan(Vector2(0.0, -0.1))
	# Forward is -Z in the rig's frame; a quarter turn left points it along -X.
	assert_float(_rig.position.x).is_less(0.0)
	assert_float(_rig.position.z).is_equal_approx(0.0, 0.0001)


func test_pan_step_grows_with_zoom_distance() -> void:
	_rig.distance = _rig.min_distance
	_rig.pan(Vector2(0.01, 0.0))
	var near := _rig.position.x
	_rig.position = Vector3.ZERO
	_rig.distance = _rig.max_distance
	_rig.pan(Vector2(0.01, 0.0))
	assert_float(_rig.position.x).is_greater(near)


func test_camera_looks_at_the_focus_point() -> void:
	var cam: Camera3D = _rig.get_node("Camera3D")
	var forward := -cam.global_transform.basis.z
	var to_focus := (_rig.global_position - cam.global_position).normalized()
	assert_float(forward.dot(to_focus)).is_greater(0.999)


func test_zoom_range_is_wide() -> void:
	assert_float(_rig.min_distance).is_equal(6.0)
	assert_float(_rig.max_distance).is_equal(300.0)


func test_zoom_is_smooth_not_a_jump() -> void:
	var before := _rig.distance
	_rig.zoom(2.0)
	assert_float(_rig.distance).is_equal(before)
	assert_float(_rig.target_distance).is_equal_approx(before * 2.0, 0.001)
	_rig._process(0.05)
	assert_float(_rig.distance).is_greater(before)
	assert_float(_rig.distance).is_less(_rig.target_distance)
	_settle()
	assert_float(_rig.distance).is_equal_approx(before * 2.0, 0.01)


## Zooming changes only the distance: the pitch is the chosen step's at every
## distance, including ones past the zoom limits (decision camera-angle-is-a-
## player-setting-fixed-while-zooming; it replaced the old pitch-follows-zoom
## curve, 35 degrees at 6 m to 65 degrees at 300 m).
func test_pitch_does_not_depend_on_distance() -> void:
	var pitch := _rig.pitch_degrees()
	assert_float(pitch).is_equal_approx(70.0, 0.0001)
	for d in [1.0, _rig.min_distance, _rig.home_distance, 150.0, _rig.max_distance, 1000.0]:
		_rig.distance = d
		assert_float(_rig.pitch_degrees()).is_equal_approx(pitch, 0.0001)


func test_camera_tilt_does_not_follow_zoom() -> void:
	var cam: Camera3D = _rig.get_node("Camera3D")
	_rig.distance = _rig.min_distance
	_rig._process(0.0)
	assert_float(rad_to_deg(-cam.rotation.x)).is_equal_approx(70.0, 0.001)
	_rig.distance = _rig.max_distance
	_rig._process(0.0)
	assert_float(rad_to_deg(-cam.rotation.x)).is_equal_approx(70.0, 0.001)


func test_camera_looks_at_the_focus_at_both_zoom_ends() -> void:
	var cam: Camera3D = _rig.get_node("Camera3D")
	for d in [_rig.min_distance, _rig.max_distance]:
		_rig.distance = d
		_rig._process(0.0)
		var forward := -cam.global_transform.basis.z
		var to_focus := (_rig.global_position - cam.global_position).normalized()
		assert_float(forward.dot(to_focus)).is_greater(0.999)


func test_starts_on_the_build_area() -> void:
	assert_vector(_rig.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_float(_rig.distance).is_equal(_rig.home_distance)


func test_default_bounds_cover_the_whole_airport() -> void:
	# Runway ends (+-192, -200), the build area corner, and the stand.
	for point in [Vector3(192, 0, -200), Vector3(-192, 0, -200), Vector3(32, 0, 32)]:
		_rig.glide_to(point)
		_settle()
		assert_vector(_rig.position).is_equal_approx(point, Vector3.ONE * 0.05)


## Runs the rig's frame step long enough for any ease to finish.
func _settle(seconds := 6.0) -> void:
	for i in int(seconds / 0.1):
		_rig._process(0.1)
