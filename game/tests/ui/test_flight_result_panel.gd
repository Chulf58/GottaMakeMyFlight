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


func test_the_result_lists_three_reasons_and_sums_the_rest_as_other() -> void:
	_close_doors_with_misses(4)
	var stages := [
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.SEATED,
		Passenger.Stage.APRON
	]
	# The reasons are kept per flight, so they are set where they are kept.
	var causes := {}
	for i in 4:
		causes[Vector2i(stages[i], Passenger.Stuck.NONE)] = 1
	_world.sim.flight_results[PassengerTestWorld.FLIGHT]["causes"] = causes
	_hud.dismiss_result()
	_hud.show_result_for(PassengerTestWorld.FLIGHT)
	var lines := _hud.result_text().split("\n")
	assert_int(lines.size()).is_equal(2 + 3 + 1)
	assert_str(lines[lines.size() - 1]).is_equal("1  Other")


func test_the_listed_rows_add_up_to_missed() -> void:
	var summary := {
		"flight": "GMF1",
		"made": 32,
		"missed": 292,
		"reasons":
		[
			{"text": "a", "count": 262},
			{"text": "b", "count": 15},
			{"text": "c", "count": 10},
			{"text": "d", "count": 3},
			{"text": "e", "count": 2},
		],
	}
	var lines := FlightResultPanel.text_for(summary).split("\n")
	assert_array(Array(lines)).contains(["262  a", "15  b", "10  c", "5  Other"])
	var total := 0
	for line in lines.slice(2):
		total += int(line.split(" ")[0])
	assert_int(total).is_equal(292)


func test_no_other_row_when_every_reason_is_listed() -> void:
	var summary := {
		"flight": "GMF1",
		"made": 0,
		"missed": 3,
		"reasons": [{"text": "a", "count": 2}, {"text": "b", "count": 1}],
	}
	assert_str(FlightResultPanel.text_for(summary)).is_equal(
		"GMF1 result\nMade 0   Missed 3\n2  a\n1  b"
	)


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


func test_two_flights_closing_together_show_the_later_one() -> void:
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(10, 20))
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.sim.spawn_now("GMF202")
	_world.sim.spawn_now("GMF202")
	_world.run_to(21)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	assert_str(_hud.result_text()).contains("GMF202 result")
	assert_str(_hud.result_text()).contains("Missed 2")
	_hud.refresh()
	assert_str(_hud.result_text()).contains("GMF202 result")
	_hud.dismiss_result()
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_a_later_closure_replaces_an_open_result_that_was_not_dismissed() -> void:
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(100, 200))
	_close_doors_with_misses(1)
	_world.sim.spawn_now("GMF202")
	_world.sim.spawn_now("GMF202")
	assert_str(_hud.result_text()).contains("GMF101 result")
	_world.run_to(201)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	assert_str(_hud.result_text()).contains("GMF202 result")
	assert_str(_hud.result_text()).contains("Missed 2")


func test_a_result_is_summarized_once_at_closure_and_not_shown_again() -> void:
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(100, 200))
	_close_doors_with_misses(1)
	_world.sim.spawn_now("GMF202")
	_world.sim.spawn_now("GMF202")
	_world.run_to(201)
	_hud.refresh()
	var shown := _hud.result_text()
	assert_str(shown).contains("GMF202 result")
	# The sim drops a pruned flight's results; the shown summary is its own copy.
	_world.sim.flight_results.erase("GMF202")
	_hud.refresh()
	assert_str(_hud.result_text()).is_equal(shown)
	_hud.dismiss_result()
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()


func test_a_dismissed_result_stays_hidden_until_another_flight_closes() -> void:
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(100, 200))
	_close_doors_with_misses(1)
	_hud.dismiss_result()
	_world.run_to(150)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()
	_world.sim.spawn_now("GMF202")
	_world.run_to(201)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
	assert_str(_hud.result_text()).contains("GMF202 result")


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


func test_the_title_names_the_flight_not_its_day_occurrence() -> void:
	var summary := {"flight": "GMF101-d0", "made": 2, "missed": 1, "reasons": []}
	var text := FlightResultPanel.text_for(summary)
	assert_str(text.split("\n")[0]).is_equal("GMF101 result")
	assert_str(text).not_contains("-d0")
	summary["flight"] = "GMF101-d12"
	assert_str(FlightResultPanel.text_for(summary).split("\n")[0]).is_equal("GMF101 result")


func test_a_flight_id_with_no_day_suffix_keeps_its_title() -> void:
	var summary := {"flight": "GMF1", "made": 0, "missed": 0, "reasons": []}
	assert_str(FlightResultPanel.text_for(summary).split("\n")[0]).is_equal("GMF1 result")
