class_name TestVehicleFollow
extends GdUnitTestSuite
## Clicking a car or taxi on the landside (no build tool active) selects it
## instead of any passenger, even one drawn right under the click: the camera
## follows LandsideViews.follow_anchor and the follow text shows the vehicle's
## passengers, flight and drop-off delay (VehicleInspect). A click on empty
## ground clears the selection, and a selected vehicle that drives off the map
## ends the follow.

const BOOKED := 8

var _land: LandsideTestWorld
var _views: PassengerViews
var _cars: LandsideViews
var _camera: TycoonCamera
var _eye: Camera3D
var _mode: BuildMode
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_land = LandsideTestWorld.make(null, [], 3)
	_views = PassengerViews.new()
	_views.clock = _land.world.clock
	_views.sim = _land.sim
	add_child(_views)
	_cars = LandsideViews.new()
	_cars.clock = _land.world.clock
	_cars.landside = _land.landside
	add_child(_cars)
	_camera = TycoonCamera.new()
	_eye = Camera3D.new()
	_eye.name = "Camera3D"
	_camera.add_child(_eye)
	add_child(_camera)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.initial_tool = BuildMode.Tool.NONE
	add_child(_mode)
	_hud = PassengerHud.new()
	_hud.clock = _land.world.clock
	_hud.flights = _land.world.flights
	_hud.sim = _land.sim
	_hud.views = _views
	_hud.landside_views = _cars
	_hud.camera = _camera
	_hud.build_mode = _mode
	add_child(_hud)
	_camera.set_process(false)
	_land.schedule(BOOKED)


func after_test() -> void:
	for node in [_hud, _mode, _camera, _cars, _views]:
		node.free()
	_land.free_all()
	_land = null


## Steps until a vehicle is drawn on road_in and points the eye down at it.
func _drawn_vehicle() -> int:
	while _land.sim.tick < 4000:
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if (
				_cars.has_vehicle(id)
				and v.lane == LandsideVehicle.Lane.ROAD_IN
				and v.pos_mm > 20000
			):
				_cars.draw()
				var at := _cars.node_for(id).global_position
				_eye.look_at_from_position(at + Vector3(0.0, 25.0, 12.0), at)
				return id
	return 0


func _click(at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	_hud._unhandled_input(click)


func test_clicking_a_vehicle_selects_it_and_shows_its_passengers_flight_and_delay() -> void:
	var id := _drawn_vehicle()
	assert_int(id).is_greater(0)
	# A real passenger, drawn right under the car: both pickers find something
	# under the click, and the vehicle wins.
	var passenger := _land.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_views.sync()
	_views.node_for(passenger).position = _cars.node_for(id).global_position
	_views.selected_id = passenger
	var at := _eye.unproject_position(_cars.node_for(id).global_position + Vector3(0.0, 1.0, 0.0))
	var passenger_pick := _views.pick(_eye, at)
	var vehicle_pick := _cars.pick(_eye, at)
	print("at %s passenger pick %d vehicle pick %d" % [at, passenger_pick, vehicle_pick])
	assert_int(passenger_pick).is_equal(passenger)
	assert_int(vehicle_pick).is_equal(id)
	_click(at)
	_hud.refresh()
	var text := _hud.follow_text()
	print("clicked %s on vehicle %d: %s" % [at, id, text])
	assert_int(_cars.selected_id).is_equal(id)
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_true()
	assert_str(text).contains(" %d   " % id)
	assert_str(text).contains("Flight %s" % PassengerTestWorld.FLIGHT)
	assert_bool(text.ends_with("On time") or text.contains("Drop-off delay")).is_true()
	_cars.draw()
	assert_vector(_cars.follow_anchor.position).is_equal(_cars.node_for(id).position)
	# A click on empty ground, far from every vehicle, clears it.
	_click(Vector2(2.0, 2.0))
	assert_int(_cars.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()
	assert_str(_hud.follow_text()).is_equal("")


func test_a_followed_vehicle_that_leaves_the_map_ends_the_follow() -> void:
	var id := _drawn_vehicle()
	assert_int(id).is_greater(0)
	_click(_eye.unproject_position(_cars.node_for(id).global_position + Vector3(0.0, 1.0, 0.0)))
	assert_int(_cars.selected_id).is_equal(id)
	var gone_at := -1
	while _land.sim.tick < 8000 and gone_at < 0:
		_land.step()
		_hud.refresh()
		if _land.landside.get_vehicle(id) == null:
			gone_at = _land.sim.tick
	_hud.refresh()
	print("vehicle %d left at tick %d" % [id, gone_at])
	assert_int(gone_at).is_greater(0)
	assert_int(_cars.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()
	assert_str(_hud.follow_text()).is_equal("")
