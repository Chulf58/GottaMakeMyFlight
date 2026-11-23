class_name TestQuietNightChip
extends GdUnitTestSuite
## The QuietNightChip ("Quiet stretch: fast-forwarding" in daytime 06:00-19:59,
## "Quiet night: fast-forwarding" overnight 20:00-05:59; decisions
## quiet-nights-fast-forward-automatically-when-nothing-is-due and
## d3-polish-quiet-stretch-daytime-label-and-bird-flock-curb-sp): it shows under
## the clock panel only while the clock fast-forwards, the clock panel keeps its
## one label (decision top-right-clock-panel-slims-to-day-time-and-speed-flight-
## row), and the right rail hangs GROUP_GAP under the chip while it shows.

const FRAME := 1.0 / 60.0
const LOCALE_SETTINGS := preload("res://locale/locale_settings.gd")

var _world: PassengerTestWorld
var _hud: PassengerHud
var _stop := -1
var _saved_locale := ""
var _added_translation: Translation


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
	if _added_translation != null:
		TranslationServer.remove_translation(_added_translation)
		_added_translation = null
	if not _saved_locale.is_empty():
		_set_locale(_saved_locale)
		_saved_locale = ""
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_world.free_all()
	_stop = -1


func _set_locale(code: String) -> void:
	var settings := get_node_or_null("/root/LocaleSettings") as LOCALE_SETTINGS
	if settings != null:
		settings.apply_locale(code, false)
	else:
		TranslationServer.set_locale(code)


func _chip() -> Control:
	return _hud.find_child("QuietNightChip", false, false) as Control


func _chip_label() -> Label:
	var labels := _chip().find_children("*", "Label", true, false)
	assert_int(labels.size()).is_equal(1)
	return labels[0] as Label


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
	# Initial tick 0 is 06:00 (daytime), so the chip reads Quiet stretch.
	assert_str(_chip_label().text).is_equal("Quiet stretch: fast-forwarding")
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
			pressed.append((button as Button).name)
	assert_array(pressed).is_equal(["Speed2"])


## The rail moves in the same refresh that shows or hides the chip, never a
## refresh later.
func test_the_rail_moves_on_the_refresh_that_shows_or_hides_the_chip() -> void:
	await _settle()
	var panel := (_hud.find_child("FlightPanel", false, false) as Control).get_global_rect()
	var rail := _hud.find_child("AlertStack", false, false) as Control
	assert_float(rail.get_global_rect().position.y).is_equal_approx(
		panel.end.y + HudLayout.GROUP_GAP, 0.5
	)
	_stop = 1_000_000
	_world.clock.advance(FRAME)
	_hud.refresh()
	var chip := _chip().get_global_rect()
	print("first fast refresh: chip=%s rail=%s" % [chip, rail.get_global_rect()])
	assert_bool(_chip().visible).is_true()
	assert_float(chip.size.y).is_greater(0.0)
	assert_float(rail.get_global_rect().position.y).is_equal_approx(
		chip.end.y + HudLayout.GROUP_GAP, 0.5
	)
	_stop = -1
	_world.clock.advance(FRAME)
	_hud.refresh()
	assert_bool(_chip().visible).is_false()
	assert_float(rail.get_global_rect().position.y).is_equal_approx(
		panel.end.y + HudLayout.GROUP_GAP, 0.5
	)


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


func test_the_chip_shows_quiet_stretch_in_daytime_and_quiet_night_overnight() -> void:
	for minute: int in [6 * 60, 9 * 60 + 37, 12 * 60, 19 * 60 + 50]:
		_world.clock.tick = GameCalendar.tick_at(0, minute, _world.clock.epoch)
		_stop = _world.clock.tick + 100_000
		_world.clock.advance(FRAME)
		await _settle()
		assert_bool(_chip().visible).is_true()
		assert_str(_chip_label().text).is_equal("Quiet stretch: fast-forwarding")
	for pair: Array in [
		[0, 20 * 60],
		[0, 21 * 60],
		[0, 23 * 60 + 30],
		[1, 2 * 60],
		[1, 5 * 60 + 50],
	]:
		_world.clock.tick = GameCalendar.tick_at(pair[0], pair[1], _world.clock.epoch)
		_stop = _world.clock.tick + 100_000
		_world.clock.advance(FRAME)
		await _settle()
		assert_bool(_chip().visible).is_true()
		assert_str(_chip_label().text).is_equal("Quiet night: fast-forwarding")
	# Exact minute boundaries (19:59 -> daytime, 20:00 -> night, 05:59 -> night, 06:00 -> daytime).
	_stop = GameCalendar.tick_at(2, 0, _world.clock.epoch)
	_world.clock.advance(FRAME)
	for boundary: Array in [
		[0, 19 * 60 + 59, "Quiet stretch: fast-forwarding"],
		[0, 20 * 60, "Quiet night: fast-forwarding"],
		[1, 5 * 60 + 59, "Quiet night: fast-forwarding"],
		[1, 6 * 60, "Quiet stretch: fast-forwarding"],
	]:
		_world.clock.tick = GameCalendar.tick_at(boundary[0], boundary[1], _world.clock.epoch)
		_hud.refresh()
		assert_bool(_chip().visible).is_true()
		assert_str(_chip_label().text).is_equal(boundary[2])


func test_the_chip_refreshes_when_crossing_the_day_night_boundary() -> void:
	# Evening transition: 19:50 -> 20:00+ while fast-forwarding stays active.
	_world.clock.tick = GameCalendar.tick_at(0, 19 * 60 + 50, _world.clock.epoch)
	_stop = GameCalendar.tick_at(1, 8 * 60, _world.clock.epoch)
	_world.clock.advance(FRAME)
	_hud.refresh()
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_str(_chip_label().text).is_equal("Quiet stretch: fast-forwarding")
	for i in 10:
		if GameCalendar.minute_of_day(_world.clock.tick, _world.clock.epoch) >= 20 * 60:
			break
		_world.clock.advance(FRAME)
	_hud.refresh()
	assert_int(GameCalendar.minute_of_day(_world.clock.tick, _world.clock.epoch)).is_greater_equal(
		20 * 60
	)
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_str(_chip_label().text).is_equal("Quiet night: fast-forwarding")

	# Morning transition: 05:50 -> 06:00+ while fast-forwarding stays active.
	_world.clock.tick = GameCalendar.tick_at(1, 5 * 60 + 50, _world.clock.epoch)
	_world.clock.advance(FRAME)
	_hud.refresh()
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_str(_chip_label().text).is_equal("Quiet night: fast-forwarding")
	for i in 10:
		if GameCalendar.minute_of_day(_world.clock.tick, _world.clock.epoch) >= 6 * 60:
			break
		_world.clock.advance(FRAME)
	_hud.refresh()
	assert_int(GameCalendar.minute_of_day(_world.clock.tick, _world.clock.epoch)).is_greater_equal(
		6 * 60
	)
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_str(_chip_label().text).is_equal("Quiet stretch: fast-forwarding")


func test_locale_change_retranslates_the_active_day_or_night_chip_label() -> void:
	_saved_locale = TranslationServer.get_locale()
	_added_translation = Translation.new()
	_added_translation.locale = "de"
	_added_translation.add_message("Quiet stretch: fast-forwarding", "Ruhiger Abschnitt: Vorspulen")
	_added_translation.add_message("Quiet night: fast-forwarding", "Ruhige Nacht: Vorspulen")
	TranslationServer.add_translation(_added_translation)

	_world.clock.tick = GameCalendar.tick_at(0, 9 * 60 + 37, _world.clock.epoch)
	_stop = _world.clock.tick + 100_000
	_world.clock.advance(FRAME)
	await _settle()
	_set_locale("de")
	assert_str(_chip_label().text).is_equal("Ruhiger Abschnitt: Vorspulen")

	_world.clock.tick = GameCalendar.tick_at(0, 21 * 60, _world.clock.epoch)
	_hud.refresh()
	assert_str(_chip_label().text).is_equal("Ruhige Nacht: Vorspulen")
	_set_locale("en")
	assert_str(_chip_label().text).is_equal("Quiet night: fast-forwarding")
