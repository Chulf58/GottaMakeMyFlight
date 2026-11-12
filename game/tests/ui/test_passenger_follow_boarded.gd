class_name TestPassengerFollowBoarded
extends GdUnitTestSuite
## Following a passenger ends when they board and their view is released: the
## selection clears, the card closes and the camera stops where it stands
## instead of drifting on to the frozen follow anchor.

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: TycoonCamera
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_camera = TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	_camera.add_child(eye)
	add_child(_camera)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.views = _views
	_hud.camera = _camera
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_camera.free()
	_views.free()
	_world.free_all()


func _card() -> PassengerInspect:
	return _hud.find_children("*", "PassengerInspect", true, false)[0] as PassengerInspect


func _frames(count: int) -> void:
	for i in count:
		await await_idle_frame()


func test_a_followed_passenger_who_boards_ends_the_follow_and_the_camera_stays() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_camera.position = Vector3(30.0, 0.0, 30.0)
	_views.selected_id = id
	_camera.follow(_views.follow_anchor)
	_hud.refresh()
	# Control: the follow is live, the card shows, and the camera is drifting
	# toward the followed passenger.
	assert_object(_views.node_for(id)).is_not_null()
	assert_bool(_camera.is_following()).is_true()
	assert_bool(_card().visible).is_true()
	var before := _camera.position
	await _frames(3)
	assert_bool(_camera.position.is_equal_approx(before)).is_false()
	# The passenger boards: the sim keeps them listed, the view lets them go.
	_world.passenger(id).stage = Passenger.Stage.MADE
	_views.sync()
	assert_object(_views.node_for(id)).is_null()
	assert_object(_world.passenger(id)).is_not_null()
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()
	assert_bool(_card().visible).is_false()
	var stopped := _camera.position
	await _frames(5)
	assert_bool(_camera.position.is_equal_approx(stopped)).is_true()
