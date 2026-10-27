class_name TestPassengerFollowRetired
extends GdUnitTestSuite
## Following a passenger ends when the passenger is retired: the selection
## clears, the ring hides and the camera stops following the frozen anchor.

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
	_views = PassengerViews.new()
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


func test_a_followed_passenger_who_is_retired_ends_the_follow() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_views.selected_id = id
	_camera.follow(_views.follow_anchor)
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(id)
	assert_bool(_camera.is_following()).is_true()
	_world.run_to(20 + PassengerSim.SETTLED_KEEP_TICKS + 2)
	assert_object(_world.passenger(id)).is_null()
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()
	assert_str(_hud.follow_text()).is_equal("")


func test_a_passenger_still_listed_keeps_being_followed() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(30)
	_views.selected_id = id
	_camera.follow(_views.follow_anchor)
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(id)
	assert_bool(_camera.is_following()).is_true()
