class_name TestQuietNightChip
extends GdUnitTestSuite
## The "Quiet night: fast-forwarding" chip (decision quiet-nights-fast-forward-
## automatically-when-nothing-is-due): it shows under the clock panel only
## while the clock fast-forwards, the clock panel keeps its one label (decision
## top-right-clock-panel-slims-to-day-time-and-speed-flight-row), and the right
## rail hangs GROUP_GAP under the chip while it shows.

const FRAME := 1.0 / 60.0

var _world: PassengerTestWorld
var _hud: PassengerHud
var _stop := -1


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(20_000))
	_world.clock.fast_forward_source = func() -> int: return _stop
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.alert_settings_path = SaveTestKit.run_path("quiet_chip_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("quiet_chip_departures")
	add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_world.free_all()
	_stop = -1


func _chip() -> Control:
	return _hud.find_child("QuietNightChip", false, false) as Control


func _settle() -> void:
	for i in 3:
		_hud.refresh()
		await get_tree().process_frame


func test_the_chip_shows_only_while_the_clock_fast_forwards() -> void:
	_world.clock.advance(FRAME)
	await _settle()
	assert_bool(_chip().visible).is_false()
	_stop = 1_000_000
	_world.clock.advance(FRAME)
	await _settle()
	print("fast=%s chip=%s" % [_world.clock.is_fast_forwarding(), _chip().visible])
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_bool(_chip().visible).is_true()
	var labels := _chip().find_children("*", "Label", true, false)
	assert_int(labels.size()).is_equal(1)
	assert_str((labels[0] as Label).text).is_equal(PassengerHud.QUIET_NIGHT_TEXT)
	assert_str(PassengerHud.QUIET_NIGHT_TEXT).is_equal("Quiet night: fast-forwarding")
	_stop = -1
	_world.clock.advance(FRAME)
	await _settle()
	assert_bool(_chip().visible).is_false()


func test_a_pause_hides_the_chip() -> void:
	_stop = 1_000_000
	_world.clock.advance(FRAME)
	await _settle()
	assert_bool(_chip().visible).is_true()
	_hud.press_pause_toggle()
	await _settle()
	assert_bool(_world.clock.paused).is_true()
	assert_bool(_chip().visible).is_false()


func test_the_clock_panel_keeps_one_label_and_the_speed_buttons_show_the_player_speed() -> void:
	_hud.press_speed(2)
	_stop = 1_000_000
	_world.clock.advance(FRAME)
	await _settle()
	var panel := _hud.find_child("FlightPanel", false, false) as Control
	assert_int(panel.find_children("*", "Label", true, false).size()).is_equal(1)
	var pressed: Array[String] = []
	for button in panel.find_children("*", "Button", true, false):
		if (button as Button).button_pressed:
			pressed.append((button as Button).text)
	assert_array(pressed).is_equal(["2x"])


func test_the_chip_sits_under_the_clock_panel_and_the_rail_under_the_chip() -> void:
	_stop = 1_000_000
	_world.clock.advance(FRAME)
	await _settle()
	var panel := (_hud.find_child("FlightPanel", false, false) as Control).get_global_rect()
	var chip := _chip().get_global_rect()
	var rail := (_hud.find_child("AlertStack", false, false) as Control).get_global_rect()
	print("panel=%s chip=%s rail=%s" % [panel, chip, rail])
	assert_float(chip.position.y).is_equal_approx(panel.end.y + HudLayout.GROUP_GAP, 0.5)
	assert_float(chip.size.x).is_equal_approx(HudLayout.RAIL_W, 0.5)
	assert_float(chip.end.x).is_equal_approx(panel.end.x, 0.5)
	assert_float(rail.position.y).is_equal_approx(chip.end.y + HudLayout.GROUP_GAP, 0.5)
	# Control: with the chip gone the rail goes back under the panel.
	_stop = -1
	_world.clock.advance(FRAME)
	await _settle()
	rail = (_hud.find_child("AlertStack", false, false) as Control).get_global_rect()
	assert_float(rail.position.y).is_equal_approx(panel.end.y + HudLayout.GROUP_GAP, 0.5)
