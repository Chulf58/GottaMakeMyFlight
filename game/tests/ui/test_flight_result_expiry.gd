class_name TestFlightResultExpiry
extends GdUnitTestSuite
## The flight result card hides itself when the game day changes; Dismiss
## still works. Setup mirrors test_flight_result_panel.gd.

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
	_port.add_child(_hud)


func after_test() -> void:
	_port.free()
	_world.free_all()


func _close_doors_with_misses(count: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(21)
	_hud.refresh()


func test_the_result_stays_up_through_the_rest_of_the_day() -> void:
	_close_doors_with_misses(1)
	_world.clock.tick = GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY - 1
	assert_int(GameCalendar.day_of(_world.clock.tick)).is_equal(0)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()


func test_the_result_hides_itself_when_the_game_day_changes() -> void:
	_close_doors_with_misses(1)
	assert_bool(_hud.is_result_open()).is_true()
	_world.clock.tick = GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY
	assert_int(GameCalendar.day_of(_world.clock.tick)).is_equal(1)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_a_result_shown_on_day_two_stays_up_that_day() -> void:
	_close_doors_with_misses(1)
	_world.clock.tick = GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY
	_hud.refresh()
	_hud.show_result_for(PassengerTestWorld.FLIGHT)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	_world.clock.tick += 100
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()


## A flight whose doors close at `doors`, one passenger spawned shortly before.
func _flight_closing_at(id: String, doors: int) -> void:
	_world.flights.add_flight(id, PassengerTestWorld.starts_with(doors - 1200, doors))
	_world.run_to(doors - 1000)
	_world.sim.spawn_now(id)


func test_a_flight_that_closed_just_before_midnight_hides_at_the_day_change() -> void:
	var midnight := GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY
	_flight_closing_at("GMF202", midnight - 1)
	# The clock runs past midnight before the HUD refreshes.
	_world.run_to(midnight + 5)
	assert_int(GameCalendar.day_of(midnight - 1)).is_equal(0)
	assert_int(GameCalendar.day_of(_world.clock.tick)).is_equal(1)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_a_flight_that_closed_exactly_at_midnight_belongs_to_the_new_day() -> void:
	var midnight := GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY
	_flight_closing_at("GMF202", midnight)
	_world.run_to(midnight + 5)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	assert_str(_hud.result_text()).contains("GMF202 result")
	_world.clock.tick += GameCalendar.TICKS_PER_DAY
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_dismiss_still_works_before_the_day_changes() -> void:
	_close_doors_with_misses(1)
	var button := _hud.find_child("DismissResult", true, false) as Button
	button.pressed.emit()
	assert_bool(_hud.is_result_open()).is_false()
	_world.clock.tick = GameCalendar.TICKS_PER_DAY - GameCalendar.START_TICK_OF_DAY
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()
