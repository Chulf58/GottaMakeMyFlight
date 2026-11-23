class_name TestDeparturesFollowLate
extends GdUnitTestSuite
## Clicking "N running late" on a DeparturesBoard row jumps to and follows that
## flight's tightest currently running-late passenger in PassengerHud, and is a
## safe no-op when nobody is late on that flight (board ccbc48f5).

const FLIGHT_B := "GMF102"

var _world: PassengerTestWorld
var _views: PassengerViews
var _cars: LandsideViews
var _car_node: Node3D
var _mode: BuildMode
var _camera: TycoonCamera
var _hud: PassengerHud
var _board: DeparturesBoard
var _inspect: PassengerInspect
var _translation: Translation


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_cars = LandsideViews.new()
	_cars.clock = _world.clock
	add_child(_cars)
	_car_node = Node3D.new()
	add_child(_car_node)
	_cars._nodes[42] = _car_node
	_mode = BuildMode.new()
	_mode.set_process(false)
	_mode.grid = _world.grid
	_mode.tool = BuildMode.Tool.NONE
	add_child(_mode)
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
	_hud.landside_views = _cars
	_hud.build_mode = _mode
	_hud.camera = _camera
	_hud.alert_settings_path = SaveTestKit.run_path("follow_late_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("follow_late_board")
	add_child(_hud)
	_board = _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	_board.set_shown(true)
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect


func after_test() -> void:
	PseudoLocale.disable()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_mode.free()
	_cars._nodes.clear()
	_car_node.free()
	_cars.free()
	_camera.free()
	_views.free()
	_world.free_all()


func test_clicking_late_pill_follows_tightest_late_passenger_on_that_flight() -> void:
	_world.flights.add_flight(FLIGHT_B, PassengerTestWorld.starts_with(1500, 1800))
	# Spawn `closer_id` BEFORE `tight_id` so tight_id > closer_id, proving slack
	# beats the lowest-id tie-breaker.
	var closer_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var tight_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var other_id := _world.sim.spawn_now(FLIGHT_B)
	assert_int(tight_id).is_greater(closer_id)
	_world.step()
	var tight := _world.passenger(tight_id)
	var closer := _world.passenger(closer_id)
	var other := _world.passenger(other_id)
	# Put `closer` near the gate exit so `tight` (at check-in) has much less slack.
	closer.cleared = true
	closer.stage = Passenger.Stage.TO_GATE
	closer.at = _world.sim.layout.door_cell(
		_world.grid, _world.sim.layout.open_exits(_world.grid)[0]
	)
	closer.clear_path()
	tight.late = true
	closer.late = true
	other.late = true
	_hud.refresh()
	# Pre-existing landside vehicle and built-item selections must be cleared.
	_cars.select(42)
	_hud._built.select_object(_world.sim.layout.passenger_entrances[0])
	assert_int(_cars.selected_id).is_equal(42)
	assert_bool(_hud._built.is_selected()).is_true()
	var button := _board.late_button(PassengerTestWorld.FLIGHT)
	assert_object(button).is_not_null()
	assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_str(button.text).is_equal("2 running late")
	assert_str(button.tooltip_text).is_not_empty()
	button.pressed.emit()
	assert_int(_views.selected_id).is_equal(tight_id)
	assert_int(_cars.selected_id).is_equal(0)
	assert_bool(_hud._built.is_selected()).is_false()
	assert_bool(_camera.is_following()).is_true()
	assert_bool(_inspect.visible).is_true()
	assert_bool(_board.is_aside()).is_true()


func test_tie_breaks_by_lowest_passenger_id() -> void:
	var first := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var second := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_world.passenger(first).late = true
	_world.passenger(second).late = true
	assert_int(LateCount.tightest_passenger(_world.sim, PassengerTestWorld.FLIGHT)).is_equal(first)


func test_clicking_when_no_late_passenger_remains_is_a_safe_noop() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var p := _world.passenger(id)
	p.late = true
	_hud.refresh()
	# Passenger ceases to be late before the click arrives.
	p.late = false
	_board.follow_late_requested.emit(PassengerTestWorld.FLIGHT)
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()
	assert_bool(_inspect.visible).is_false()


func test_late_pill_tooltip_and_count_are_translated() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_plural_message(
		"{count} running late", ["{count} late one", "{count} late many"]
	)
	TranslationServer.add_translation(_translation)
	assert_str(LateCount.text_for(1)).is_equal("1 late one")
	assert_str(LateCount.text_for(3)).is_equal("3 late many")
	PseudoLocale.enable(0.4)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_world.passenger(id).late = true
	_hud.refresh()
	var button := _board.late_button(PassengerTestWorld.FLIGHT)
	assert_object(button).is_not_null()
	assert_str(button.tooltip_text).starts_with("[")
