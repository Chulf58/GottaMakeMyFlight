class_name TestClockPanelSlim
extends GdUnitTestSuite
## HUD 3b (board 05cf0cf6, decision top-right-clock-panel-slims-to-day-time-
## and-speed-flight-row): the top-right panel is one row, the day and time
## with the Pause, 1x, 2x and 3x buttons, RAIL_W wide. Its flight rows and
## counts moved to the Departures list, and the right rail still hangs
## GROUP_GAP under the panel's real bottom.

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
	_world.flights.open_airport()
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.alert_settings_path = SaveTestKit.run_path("clock_panel_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("clock_panel_departures")
	add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_world.free_all()


func _panel() -> Control:
	return _hud.find_child("FlightPanel", false, false) as Control


func _settle() -> void:
	for i in 3:
		_hud.refresh()
		await get_tree().process_frame


func test_the_panel_has_the_clock_and_the_speed_buttons_and_nothing_else() -> void:
	var labels := _panel().find_children("*", "Label", true, false)
	assert_int(labels.size()).is_equal(1)
	assert_str((labels[0] as Label).name).is_equal("Clock")
	var buttons: Array[String] = []
	for button in _panel().find_children("*", "Button", true, false):
		buttons.append((button as Button).text)
	assert_array(buttons).is_equal(["Pause", "1x", "2x", "3x"])


func test_no_flight_rows_and_no_counts_are_in_the_panel() -> void:
	_world.flights.accept_contract(_small("GA100", 11 * 60))
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	await _settle()
	assert_object(_hud.find_child("Departures", true, false)).is_null()
	for label in _panel().find_children("*", "Label", true, false):
		var text := (label as Label).text
		assert_str(text).not_contains("Made")
		assert_str(text).not_contains("In terminal")
		assert_str(text).not_contains("GMF101")
		assert_str(text).not_contains("GA100")


func test_the_clock_label_shows_the_day_and_time() -> void:
	_hud.refresh()
	var clock := _hud.find_child("Clock", true, false) as Label
	assert_str(clock.text).is_equal(_hud.time_text())
	assert_str(clock.text).starts_with("Day 1  ")


## The recorded height: one HudLayout.BUTTON_H row inside the panel's own
## vertical padding, with the clock label and the buttons on that one row.
func test_the_panel_is_one_row_tall_and_rail_wide() -> void:
	await _settle()
	var panel := _panel()
	var pad := panel.get_theme_stylebox("panel").get_minimum_size().y
	assert_float(panel.size.x).is_equal_approx(HudLayout.RAIL_W, 0.5)
	assert_float(panel.size.y).is_equal_approx(HudLayout.BUTTON_H + pad, 0.5)
	var clock := _hud.find_child("Clock", true, false) as Control
	var last := _panel().find_children("*", "Button", true, false).back() as Control
	assert_float(clock.get_global_rect().position.y).is_less(last.get_global_rect().end.y)
	assert_float(clock.get_global_rect().end.x).is_less_equal(
		(
			(_panel().find_children("*", "Button", true, false)[0] as Control)
			. get_global_rect()
			. position
			. x
		)
	)
	assert_float(last.get_global_rect().end.x).is_less_equal(panel.get_global_rect().end.x)


func test_the_rail_top_is_the_panel_bottom_plus_the_group_gap() -> void:
	await _settle()
	var rail := (_hud.find_child("AlertStack", false, false) as Control).get_global_rect()
	var bottom := _panel().get_global_rect().end.y
	assert_float(rail.position.y).is_equal_approx(bottom + HudLayout.GROUP_GAP, 0.5)
	# Control: the rail moved up with the panel, not left at the old tall one.
	assert_float(bottom).is_less(HudLayout.MARGIN + HudLayout.BUTTON_H * 2.0)


func _small(id: String, minute: int) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = "small"
	terms["booked_passengers"] = 12
	return terms
