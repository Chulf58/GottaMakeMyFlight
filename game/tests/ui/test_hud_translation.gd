class_name TestHudTranslation
extends GdUnitTestSuite
## The HUD's own text reaches the screen through tr() (board T3, decision
## translation-format-po-gettext-files-with-tr-and-tr-n-for-all). The profile is
## on before the HUD is built, so a string set without tr() would show no bracket.
## Every probed text starts with "[" under the profile, and the English text it
## wraps is still inside it.

var _world: PassengerTestWorld
var _hud: PassengerHud
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	PseudoLocale.enable(0.4)
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_hud = _new_hud(false)
	add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_views.free()
	_world.free_all()
	PseudoLocale.disable()


func _new_hud(debug_tools: bool) -> PassengerHud:
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	hud.views = _views
	hud.debug_tools = debug_tools
	# Per-process settings, so the player's own user://hud_settings.cfg never reaches the test.
	hud.alert_settings_path = SaveTestKit.run_path("hud_translation_alerts")
	hud.departures_settings_path = SaveTestKit.run_path("hud_translation_departures")
	return hud


## `text` without the profile's lead bracket and padding marks.
func _plain(text: String) -> String:
	return text.trim_prefix("[").lstrip("_")


func _speed_buttons() -> Array[Button]:
	var found: Array[Button] = []
	for button in _hud.find_children("*", "Button", true, false):
		if (button as Button).toggle_mode and button.name.begins_with("Speed"):
			found.append(button)
	return found


func test_the_speed_buttons_are_icons_with_translated_tooltips() -> void:
	var buttons := _speed_buttons()
	print("speed tooltips: %s" % [buttons.map(func(b: Button) -> String: return b.tooltip_text)])
	assert_int(buttons.size()).is_equal(4)
	for button in buttons:
		assert_str(button.text).is_empty()
		assert_object(button.icon).is_not_null()
		assert_str(button.tooltip_text).starts_with("[")
	assert_str(_plain(buttons[0].tooltip_text)).starts_with("Pause (Space)")
	assert_str(_plain(buttons[2].tooltip_text)).starts_with("Speed 2x (Shift+2)")
	assert_str(_plain(buttons[3].tooltip_text)).starts_with("Speed 3x (Shift+3)")


func test_the_clock_text_is_routed_and_keeps_its_values() -> void:
	var text := _hud.time_text()
	print("time text: %s" % text)
	assert_str(text).starts_with("[")
	assert_str(text).contains("Day 1")
	assert_str(text).contains(GameCalendar.clock_text(_world.clock.tick))


func test_the_quiet_night_chip_is_routed() -> void:
	var chip := _hud.find_child("QuietNightChip", true, false)
	var label := chip.get_child(0) as Label
	assert_str(label.text).starts_with("[")
	assert_str(_plain(label.text)).starts_with("Quiet night: fast-forwarding")


func test_the_follow_line_is_routed_part_by_part() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.mood = 55
	p.hunger = 47
	p.toilet_need = 12
	_views.selected_id = p.id
	var parts := _hud.follow_text().split("   ")
	print("follow parts: %s" % [parts])
	assert_int(parts.size()).is_greater_equal(5)
	for part in parts:
		assert_str(part).starts_with("[")
	assert_str(parts[0]).contains("Passenger %d" % p.id)
	assert_str(parts[2]).contains("mood 55")
	assert_str(parts[3]).contains("hunger 47")
	assert_str(parts[4]).contains("toilet 12")


func test_every_passenger_stage_has_text_in_the_players_words() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var seen := {}
	for stage: int in Passenger.Stage.values():
		p.stage = stage
		var text := PassengerHud.stage_text(_world.sim, p)
		assert_str(text).override_failure_message("stage %d has no text" % stage).is_not_empty()
		assert_str(text).starts_with("[")
		seen[stage] = text
	print("stages checked: %d" % seen.size())
	assert_int(seen.size()).is_greater(30)


func test_the_debug_panel_is_absent_without_the_gate_and_not_translated_with_it() -> void:
	for node_name: String in ["DebugCorner", "DebugPanelDock", "DebugToggle", "DebugPanel"]:
		assert_object(_hud.find_child(node_name, true, false)).is_null()
	var debug_hud := _new_hud(true)
	add_child(debug_hud)
	var toggle := debug_hud.find_child("DebugToggle", true, false) as Button
	assert_object(toggle).is_not_null()
	# Control: the dev-only text keeps its English words, with no profile bracket.
	assert_str(toggle.text).is_equal("Debug")
	DirAccess.remove_absolute(debug_hud.alert_settings_path)
	DirAccess.remove_absolute(debug_hud.departures_settings_path)
	debug_hud.free()
