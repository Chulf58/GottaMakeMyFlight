class_name TestPassengerFollowAnchor
extends GdUnitTestSuite
## Selecting or switching a followed passenger syncs PassengerViews.follow_anchor
## before TycoonCamera._process() runs, so frame 1 never pulls toward
## Vector3.ZERO or the previously followed passenger.

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: TycoonCamera
var _eye: Camera3D
var _mode: BuildMode
var _hud: PassengerHud
var _settings := ""
var _alerts := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(32, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_views.set_process(false)
	_camera = TycoonCamera.new()
	_camera.settings_path = SaveTestKit.run_path("follow_anchor_cam")
	_eye = Camera3D.new()
	_eye.name = "Camera3D"
	_camera.add_child(_eye)
	add_child(_camera)
	_camera.set_process(false)
	_mode = BuildMode.new()
	_mode.set_process(false)
	_mode.grid = _world.grid
	_mode.tool = BuildMode.Tool.NONE
	add_child(_mode)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.views = _views
	_hud.build_mode = _mode
	_hud.camera = _camera
	_settings = SaveTestKit.run_path("follow_anchor_board")
	_hud.departures_settings_path = _settings
	_alerts = SaveTestKit.run_path("follow_anchor_alerts")
	_hud.alert_settings_path = _alerts
	add_child(_hud)


func after_test() -> void:
	var cam_settings := _camera.settings_path
	_hud.free()
	_mode.free()
	_camera.free()
	_views.free()
	_world.free_all()
	for path in [_settings, _alerts, cam_settings]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func _place_passenger(cell: Vector2i) -> int:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	p.stage = Passenger.Stage.TO_CHECKIN
	p.at = cell
	p.clear_path()
	return id


func _click_at(world_pos: Vector3) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _eye.unproject_position(world_pos + Vector3(0.0, 1.0, 0.0))
	_hud._unhandled_input(click)


func test_clicking_a_passenger_moves_anchor_before_first_camera_step() -> void:
	var id_a := _place_passenger(Vector2i(26, 4))
	_world.step()
	_views.draw()
	assert_vector(_views.follow_anchor.position).is_equal(Vector3.ZERO)
	var pos_a := _views.node_for(id_a).position
	assert_float(pos_a.x).is_greater(8.0)
	_camera.position = Vector3(4.0, 0.0, pos_a.z)
	_camera.yaw = 0.0
	_camera.distance = 24.0
	_camera._apply()
	_click_at(pos_a)
	assert_int(_views.selected_id).is_equal(id_a)
	assert_vector(_views.follow_anchor.position).is_equal_approx(pos_a, Vector3.ONE * 0.001)
	assert_bool(_views._ring.visible).is_true()
	_camera._process(0.05)
	assert_float(_camera.position.x).is_greater(4.0)


func test_switching_passenger_moves_anchor_before_first_camera_step() -> void:
	var id_a := _place_passenger(Vector2i(20, 4))
	var id_b := _place_passenger(Vector2i(30, 4))
	_world.step()
	_views.draw()
	var pos_a := _views.node_for(id_a).position
	var pos_b := _views.node_for(id_b).position
	assert_float(pos_a.x).is_less(6.0)
	assert_float(pos_b.x).is_greater(12.0)
	_camera.position = Vector3(9.0, 0.0, pos_b.z)
	_camera.yaw = 0.0
	_camera.distance = 30.0
	_camera._apply()
	_click_at(pos_a)
	assert_int(_views.selected_id).is_equal(id_a)
	assert_vector(_views.follow_anchor.position).is_equal_approx(pos_a, Vector3.ONE * 0.001)
	_click_at(pos_b)
	assert_int(_views.selected_id).is_equal(id_b)
	assert_vector(_views.follow_anchor.position).is_equal_approx(pos_b, Vector3.ONE * 0.001)
	_camera._process(0.05)
	assert_float(_camera.position.x).is_greater(9.0)


func test_follow_invite_and_follow_late_move_anchor_before_draw() -> void:
	var id := _place_passenger(Vector2i(28, 4))
	_world.step()
	var expected := _views.draw_position(_world.passenger(id))
	assert_float(expected.x).is_greater(10.0)
	_camera.position = Vector3(5.0, 0.0, expected.z)
	assert_int(FollowInvite.show_me(_world.sim, _views, _camera, null)).is_equal(id)
	assert_vector(_views.follow_anchor.position).is_equal_approx(expected, Vector3.ONE * 0.001)
	_camera._process(0.05)
	assert_float(_camera.position.x).is_greater(5.0)

	_views.select(0)
	assert_bool(_views._ring.visible).is_false()
	_views.follow_anchor.position = Vector3.ZERO
	_world.passenger(id).late = true
	_camera.position = Vector3(5.0, 0.0, expected.z)
	_hud._on_follow_late_requested(PassengerTestWorld.FLIGHT)
	assert_int(_views.selected_id).is_equal(id)
	assert_vector(_views.follow_anchor.position).is_equal_approx(expected, Vector3.ONE * 0.001)
	_camera._process(0.05)
	assert_float(_camera.position.x).is_greater(5.0)


func test_select_without_drawn_node_uses_sim_position_and_rejects_unknown_id() -> void:
	var id := _place_passenger(Vector2i(24, 3))
	assert_object(_views.node_for(id)).is_null()
	var expected := _views.draw_position(_world.passenger(id))
	_views.select(id)
	assert_int(_views.selected_id).is_equal(id)
	assert_vector(_views.follow_anchor.position).is_equal_approx(expected, Vector3.ONE * 0.001)
	assert_bool(_views._ring.visible).is_false()
	_views.select(987654)
	assert_int(_views.selected_id).is_equal(0)
