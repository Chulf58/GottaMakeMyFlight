class_name TestTycoonCamera
extends GdUnitTestSuite

var _rig: TycoonCamera


func before_test() -> void:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = auto_free(scene.instantiate()) as TycoonCamera
	add_child(_rig)


func test_zoom_is_clamped_both_ways() -> void:
	for i in 100:
		_rig.zoom(0.5)
	assert_float(_rig.distance).is_equal(_rig.min_distance)
	for i in 100:
		_rig.zoom(2.0)
	assert_float(_rig.distance).is_equal(_rig.max_distance)


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
