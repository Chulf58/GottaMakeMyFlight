class_name TestTycoonCameraFraming
extends GdUnitTestSuite
## Framing the start view on an area: where the camera looks and how far it
## backs off, and Home returning to that view.

## The starter terminal's floor in the Toon shell: x 10-21, z 0-29 cells from
## the shell's origin (-33.5, -94.8), 12 by 30 m.
const STARTER := Rect2(Vector2(-23.5, -94.8), Vector2(12.0, 30.0))

var _rig: TycoonCamera


func before_test() -> void:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = auto_free(scene.instantiate()) as TycoonCamera
	add_child(_rig)


func test_framing_looks_at_the_middle_of_the_area() -> void:
	var view := _rig.framing_for(STARTER)
	var at: Vector3 = view["position"]
	assert_float(at.x).is_equal_approx(-17.5, 0.001)
	assert_float(at.y).is_equal_approx(0.0, 0.001)
	assert_float(at.z).is_equal_approx(-79.8, 0.001)


func test_a_small_area_is_framed_closer_than_the_old_start_view() -> void:
	var view := _rig.framing_for(STARTER)
	assert_float(view["distance"]).is_less(_rig.home_distance * 0.6)
	assert_float(view["distance"]).is_greater(_rig.min_distance)


func test_a_bigger_area_backs_the_camera_off_further() -> void:
	var small := _rig.framing_for(Rect2(Vector2.ZERO, Vector2(10.0, 10.0)))
	var large := _rig.framing_for(Rect2(Vector2.ZERO, Vector2(40.0, 40.0)))
	assert_float(large["distance"]).is_greater(small["distance"])


func test_the_distance_stays_inside_the_zoom_limits() -> void:
	assert_float(_rig.framing_for(Rect2(Vector2.ZERO, Vector2(0.5, 0.5)))["distance"]).is_equal(
		_rig.min_distance
	)
	(
		assert_float(_rig.framing_for(Rect2(Vector2.ZERO, Vector2(5000.0, 5000.0)))["distance"])
		. is_equal(_rig.max_distance)
	)


func test_the_whole_area_is_in_view_once_framed() -> void:
	_rig.frame_start_view(STARTER)
	var cam: Camera3D = _rig.get_node("Camera3D")
	for x in [STARTER.position.x, STARTER.end.x]:
		for z in [STARTER.position.y, STARTER.end.y]:
			(
				assert_bool(cam.is_position_in_frustum(Vector3(x, 0.0, z)))
				. override_failure_message("corner (%s, %s) is outside the view" % [x, z])
				. is_true()
			)


func test_frame_start_view_jumps_there_and_becomes_home() -> void:
	_rig.glide_to(Vector3(150.0, 0.0, -180.0), 200.0)
	_rig.frame_start_view(STARTER)
	var view := _rig.framing_for(STARTER)
	assert_bool(_rig.is_gliding()).is_false()
	assert_vector(_rig.position).is_equal_approx(view["position"], Vector3.ONE * 0.001)
	assert_float(_rig.distance).is_equal_approx(view["distance"], 0.001)
	assert_float(_rig.target_distance).is_equal_approx(view["distance"], 0.001)
	assert_vector(_rig.home_position).is_equal_approx(view["position"], Vector3.ONE * 0.001)
	assert_float(_rig.home_distance).is_equal_approx(view["distance"], 0.001)


func test_home_returns_to_the_framed_view() -> void:
	_rig.frame_start_view(STARTER)
	var view := _rig.framing_for(STARTER)
	_rig.glide_to(Vector3(100.0, 0.0, 100.0), 150.0)
	_rig.go_home()
	for i in 600:
		_rig._process(0.05)
	assert_vector(_rig.position).is_equal_approx(view["position"], Vector3.ONE * 0.05)
	assert_float(_rig.distance).is_equal_approx(view["distance"], 0.1)
