class_name TestTycoonCameraMotion
extends GdUnitTestSuite

var _rig: TycoonCamera


func before_test() -> void:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = auto_free(scene.instantiate()) as TycoonCamera
	add_child(_rig)


func test_home_input_action_is_the_home_key() -> void:
	assert_bool(InputMap.has_action("camera_home")).is_true()
	var events := InputMap.action_get_events("camera_home")
	assert_int(events.size()).is_equal(1)
	assert_int((events[0] as InputEventKey).physical_keycode).is_equal(KEY_HOME)


func test_home_glides_back_to_the_start_view() -> void:
	_rig.glide_to(Vector3(150.0, 0.0, -180.0), 200.0)
	_settle()
	_rig.rotate_yaw(1.2)
	_rig.go_home()
	assert_bool(_rig.is_gliding()).is_true()
	_settle()
	assert_vector(_rig.position).is_equal_approx(_rig.home_position, Vector3.ONE * 0.05)
	assert_float(_rig.distance).is_equal_approx(_rig.home_distance, 0.1)
	assert_float(_rig.yaw).is_equal_approx(_rig.home_yaw, 0.01)
	assert_bool(_rig.is_gliding()).is_false()


func test_home_key_press_starts_the_glide() -> void:
	_rig.position = Vector3(80.0, 0.0, -80.0)
	var press := InputEventAction.new()
	press.action = "camera_home"
	press.pressed = true
	_rig._unhandled_input(press)
	assert_bool(_rig.is_gliding()).is_true()
	_settle()
	assert_vector(_rig.position).is_equal_approx(_rig.home_position, Vector3.ONE * 0.05)


func test_glide_to_reaches_the_target_and_distance() -> void:
	_rig.glide_to(Vector3(-18.0, 0.0, -117.0), 25.0)
	_rig._process(0.1)
	var partway := _rig.position
	assert_vector(partway).is_not_equal(Vector3(-18.0, 0.0, -117.0))
	_settle()
	assert_vector(_rig.position).is_equal_approx(Vector3(-18.0, 0.0, -117.0), Vector3.ONE * 0.05)
	assert_float(_rig.distance).is_equal_approx(25.0, 0.1)


func test_glide_to_without_distance_keeps_the_zoom() -> void:
	_rig.glide_to(Vector3(40.0, 0.0, 10.0))
	_settle()
	assert_float(_rig.distance).is_equal_approx(_rig.home_distance, 0.001)


func test_follow_tracks_a_moving_node() -> void:
	var mover: Node3D = auto_free(Node3D.new())
	add_child(mover)
	_rig.follow(mover)
	assert_bool(_rig.is_following()).is_true()
	for i in 20:
		mover.global_position += Vector3(2.0, 3.0, -5.0)
		_rig._process(0.1)
	_settle_follow(mover)
	assert_float(_rig.position.x).is_equal_approx(mover.global_position.x, 0.5)
	assert_float(_rig.position.z).is_equal_approx(mover.global_position.z, 0.5)
	assert_float(_rig.position.y).is_equal(0.0)


func test_manual_pan_cancels_follow() -> void:
	var mover: Node3D = auto_free(Node3D.new())
	add_child(mover)
	_rig.follow(mover)
	_rig.pan(Vector2(0.01, 0.0))
	assert_bool(_rig.is_following()).is_false()
	var stayed := _rig.position
	mover.global_position = Vector3(100.0, 0.0, 100.0)
	_settle()
	assert_vector(_rig.position).is_equal(stayed)


func test_manual_pan_cancels_glide() -> void:
	_rig.glide_to(Vector3(100.0, 0.0, 100.0))
	_rig.pan(Vector2(0.0, 0.01))
	assert_bool(_rig.is_gliding()).is_false()
	var stayed := _rig.position
	_settle()
	assert_vector(_rig.position).is_equal(stayed)


func test_glide_to_cancels_follow() -> void:
	var mover: Node3D = auto_free(Node3D.new())
	add_child(mover)
	_rig.follow(mover)
	_rig.glide_to(Vector3(10.0, 0.0, 10.0))
	assert_bool(_rig.is_following()).is_false()


func test_follow_stops_when_the_node_is_freed() -> void:
	var mover := Node3D.new()
	add_child(mover)
	_rig.follow(mover)
	mover.free()
	_rig._process(0.1)
	assert_bool(_rig.is_following()).is_false()


## Runs the rig's frame step long enough for any ease to finish.
func _settle(seconds := 6.0) -> void:
	for i in int(seconds / 0.1):
		_rig._process(0.1)


## Lets the follower catch up with a node that has stopped moving.
func _settle_follow(_node: Node3D) -> void:
	_settle(3.0)
