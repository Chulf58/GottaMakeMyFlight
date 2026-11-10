class_name TestFlightResultExpiry
extends GdUnitTestSuite
## The flight result card leaves the rail after FlightResultPanel.SHOW_SECONDS
## of real time or on a click, not when the game day changes (decision hud-
## grid-and-rails-one-spacing-grid-centred-top-row-right-ra, part 5, replacing
## the day-change hide of decision 6a13d887 part 2); it stays in the alerts
## history. Setup mirrors test_flight_result_panel.gd.

var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(10, 10)
	_port.add_child(mode)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.build_mode = mode
	_hud.alert_settings_path = SaveTestKit.run_path("result_expiry_setting")
	_port.add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	_port.free()
	_world.free_all()


func _close_doors_with_misses(count: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(21)
	_hud.refresh()


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func test_sim_time_and_a_day_change_do_not_hide_the_result() -> void:
	_close_doors_with_misses(1)
	assert_bool(_hud.is_result_open()).is_true()
	_world.clock.tick = GameCalendar.TICKS_PER_DAY * 2
	assert_int(GameCalendar.day_of(_world.clock.tick)).is_greater(0)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()


func test_the_result_leaves_after_twenty_seconds_of_real_time_while_paused() -> void:
	_close_doors_with_misses(1)
	_world.clock.set_paused(true)
	assert_float(FlightResultPanel.SHOW_SECONDS).is_equal(20.0)
	_stack().advance(FlightResultPanel.SHOW_SECONDS - 0.5)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	_stack().advance(1.0)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()
	var lines := _stack().history_lines()
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).contains("%s result" % PassengerTestWorld.FLIGHT)
	assert_str(lines[0]).contains("Missed 1")


func test_a_later_flight_replaces_the_result_and_starts_its_own_twenty_seconds() -> void:
	_close_doors_with_misses(1)
	_stack().advance(FlightResultPanel.SHOW_SECONDS - 1.0)
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(100, 200))
	_world.sim.spawn_now("GMF202")
	_world.run_to(201)
	_hud.refresh()
	assert_str(_hud.result_text()).contains("GMF202 result")
	_stack().advance(2.0)
	assert_bool(_hud.is_result_open()).is_true()
	assert_int(_stack().history_lines().size()).is_equal(2)


func test_a_click_on_the_card_removes_it() -> void:
	_close_doors_with_misses(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_stack().notice_card(PassengerHud.RESULT_KEY).gui_input.emit(click)
	assert_bool(_hud.is_result_open()).is_false()
	assert_int(_stack().history_lines().size()).is_equal(1)


func test_dismiss_still_works() -> void:
	_close_doors_with_misses(1)
	var button := _hud.find_child("DismissResult", true, false) as Button
	button.pressed.emit()
	assert_bool(_hud.is_result_open()).is_false()
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()
