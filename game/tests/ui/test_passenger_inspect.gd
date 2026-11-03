class_name TestPassengerInspect
extends GdUnitTestSuite
## The passenger inspect card (HUD 4/7, decision passenger-inspect-thoughts-
## recorded-at-sim-outcomes-saved-pin-marks-where): live status apart from the
## thoughts, newest first; clicking a thought glides the camera to where the
## passenger was, stops following and pins the spot until another thought is
## clicked, the passenger is deselected or a game is loaded; the passenger's
## name follows them again.

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: TycoonCamera
var _hud: PassengerHud
var _inspect: PassengerInspect
var _id := 0


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
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_id = _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var p := _world.passenger(_id)
	_world.clock.tick = 600
	PassengerThoughts.record(p, PassengerThoughts.Kind.FOOD_GIVEN_UP, 100, Vector2i(2, 3), 5)
	PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 400, Vector2i(5, 1), 6)


func after_test() -> void:
	_hud.free()
	_camera.free()
	_views.free()
	_world.free_all()


func _select() -> void:
	_views.selected_id = _id
	_camera.follow(_views.follow_anchor)
	_hud.refresh()


func test_the_card_is_hidden_with_no_passenger_selected() -> void:
	assert_object(_inspect).is_not_null()
	_hud.refresh()
	assert_bool(_inspect.visible).is_false()
	assert_bool(_inspect.marker.is_shown()).is_false()


func test_the_card_shows_live_status_apart_from_the_thoughts_newest_first() -> void:
	var p := _world.passenger(_id)
	p.hunger = 47
	p.toilet_need = 81
	p.boredom = 12
	_select()
	print(
		(
			"%s | %s | %s | %s"
			% [
				_inspect.name_text(),
				_inspect.status_text(),
				_inspect.flight_text(),
				_inspect.row_texts()
			]
		)
	)
	assert_bool(_inspect.visible).is_true()
	assert_str(_inspect.name_text()).is_equal("Passenger %d" % _id)
	assert_str(_inspect.status_text()).contains("Hunger 47")
	assert_str(_inspect.status_text()).contains("Toilet 81")
	assert_str(_inspect.status_text()).contains("Boredom 12")
	assert_str(_inspect.flight_text()).contains(PassengerTestWorld.FLIGHT)
	assert_array(Array(_inspect.row_texts())).is_equal(
		["That hit the spot · 10 min ago", "Gave up on getting food · 25 min ago"]
	)
	var label := _hud.find_child("FollowText", true, false) as Label
	assert_bool(label.visible).is_false()


func test_clicking_a_thought_glides_there_stops_following_and_pins_the_spot() -> void:
	_select()
	assert_bool(_camera.is_following()).is_true()
	assert_bool(_inspect.press_thought(1)).is_true()
	var where := _world.grid.cell_to_world(Vector2i(2, 3))
	print(
		(
			"pin %s at %s, glide %s, hint %s"
			% [
				_inspect.marker.is_shown(),
				_inspect.marker.position,
				_camera.is_gliding(),
				_inspect.marked_text()
			]
		)
	)
	assert_bool(_camera.is_following()).is_false()
	assert_bool(_camera.is_gliding()).is_true()
	assert_bool(_inspect.marker.is_shown()).is_true()
	assert_float(_inspect.marker.position.x).is_equal_approx(where.x, 0.001)
	assert_float(_inspect.marker.position.z).is_equal_approx(where.z, 0.001)
	assert_that(_inspect.marker.pin_colour()).is_equal(ThoughtMarker.CORAL)
	assert_str(_inspect.marked_text()).contains("where they were")
	assert_int(_views.selected_id).is_equal(_id)
	assert_bool(_inspect.press_thought(0)).is_true()
	assert_that(_inspect.marker.pin_colour()).is_equal(ThoughtMarker.GREEN)
	where = _world.grid.cell_to_world(Vector2i(5, 1))
	assert_float(_inspect.marker.position.x).is_equal_approx(where.x, 0.001)


func test_a_row_with_no_thought_does_nothing() -> void:
	_select()
	assert_bool(_inspect.press_thought(PassengerThoughts.CAP - 1)).is_false()
	assert_bool(_inspect.marker.is_shown()).is_false()
	assert_bool(_camera.is_following()).is_true()


func test_the_name_follows_the_passenger_again() -> void:
	_select()
	_inspect.press_thought(0)
	assert_bool(_camera.is_following()).is_false()
	_inspect.press_name()
	assert_bool(_camera.is_following()).is_true()
	assert_bool(_inspect.marker.is_shown()).is_true()


func test_deselecting_or_a_load_clears_the_pin() -> void:
	_select()
	_inspect.press_thought(0)
	_views.selected_id = 0
	_hud.refresh()
	assert_bool(_inspect.marker.is_shown()).is_false()
	assert_bool(_inspect.visible).is_false()
	_select()
	_inspect.press_thought(0)
	assert_bool(_inspect.marker.is_shown()).is_true()
	_inspect.on_loaded(true)
	assert_bool(_inspect.marker.is_shown()).is_false()


func test_the_card_keeps_the_follow_texts_bottom_left_place() -> void:
	_select()
	var label := _hud.find_child("FollowText", true, false) as Label
	assert_float(_inspect.anchor_top).is_equal(1.0)
	assert_float(_inspect.offset_left).is_equal(label.offset_left)
	assert_float(_inspect.offset_right).is_less_equal(label.offset_right)
	assert_float(_inspect.offset_right - _inspect.offset_left).is_less_equal(PassengerInspect.MAX_W)
	assert_float(_inspect.offset_bottom).is_equal(label.offset_bottom)
	assert_int(_inspect.grow_vertical).is_equal(Control.GROW_DIRECTION_BEGIN)
