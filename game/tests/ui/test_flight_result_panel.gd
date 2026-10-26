class_name TestFlightResultPanel
extends GdUnitTestSuite
## The flight result panel PassengerHud shows when a flight's doors close:
## made, missed and the main miss reasons, dismissible, clear of the build tray.

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


func test_no_result_shows_before_the_doors_close() -> void:
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(15)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_the_result_opens_when_the_doors_close_with_made_missed_and_reasons() -> void:
	_close_doors_with_misses(3)
	assert_bool(_hud.is_result_open()).is_true()
	var text := _hud.result_text()
	assert_str(text).contains(PassengerTestWorld.FLIGHT)
	assert_str(text).contains("Made 0")
	assert_str(text).contains("Missed 3")
	assert_str(text).contains("3 ")
	assert_str(text).contains(
		FlightResult.reason_text(Passenger.Stage.TO_CHECKIN, Passenger.Stuck.NO_CHECKIN)
	)


func test_the_result_lists_at_most_three_reasons() -> void:
	_close_doors_with_misses(4)
	var stages := [
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.SEATED,
		Passenger.Stage.APRON
	]
	for i in 4:
		var p := _world.passenger(_world.sim.passenger_ids()[i])
		p.missed_stage = stages[i]
		p.missed_stuck = Passenger.Stuck.NONE
	_hud.dismiss_result()
	_hud.show_result_for(PassengerTestWorld.FLIGHT)
	var reason_lines := 0
	for line in _hud.result_text().split("\n"):
		if line.begins_with("1 "):
			reason_lines += 1
	assert_int(reason_lines).is_equal(3)


func test_dismissing_hides_the_result_and_it_stays_hidden() -> void:
	_close_doors_with_misses(2)
	_hud.dismiss_result()
	assert_bool(_hud.is_result_open()).is_false()
	_world.run_to(60)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_the_dismiss_button_hides_the_result() -> void:
	_close_doors_with_misses(1)
	var button := _hud.find_child("DismissResult", true, false) as Button
	assert_object(button).is_not_null()
	button.pressed.emit()
	assert_bool(_hud.is_result_open()).is_false()


func test_a_flight_that_was_already_closed_is_not_announced_again() -> void:
	_close_doors_with_misses(1)
	_hud.dismiss_result()
	_hud.refresh()
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_the_result_sits_below_the_flight_panel_and_above_the_build_tray() -> void:
	_close_doors_with_misses(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var result := _hud.find_child("FlightResultPanel", true, false) as Control
	var flight := _hud.find_child("FlightPanel", true, false) as Control
	var rect := result.get_global_rect()
	assert_float(rect.size.y).is_greater(40.0)
	assert_bool(rect.position.y >= flight.get_global_rect().end.y).is_true()
	var tray_top := (
		_port.size.y
		- (
			BuildMenu.MARGIN
			+ BuildMenu.BAR_H
			+ BuildMenu.GAP
			+ BuildMenu.TRAY_H
			+ BuildMenu.GAP
			+ BuildMenu.STATUS_H
		)
	)
	assert_bool(rect.end.y <= tray_top).is_true()
	assert_bool(rect.end.x <= _port.size.x and rect.position.x >= 0.0).is_true()
