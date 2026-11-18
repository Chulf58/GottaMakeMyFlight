class_name TestLeftColumnFit
extends GdUnitTestSuite
## Longer translations in the top-left column (board T10): the Planner toggle
## stays a GAP right of the Departures toggle however wide that grows, the Mood
## legend card sits right of the Planner toggle instead of over it, and a column
## card stops a GAP above a bottom-left card (LeftColumn.FLOOR_GROUP).

const SEED := 4_070_093

var _settings_path := SaveTestKit.run_path("left_column_fit_alerts")
var _mood_path := SaveTestKit.run_path("left_column_fit_mood")
var _departures_path := SaveTestKit.run_path("left_column_fit_departures")

var _main: Node
var _departures: Button
var _planner: Button
var _departures_text := ""


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	(_main.get_node("PassengerHud") as PassengerHud).departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	add_child(_main)
	_departures = _main.find_child("DeparturesToggle", true, false) as Button
	_planner = _main.find_child("PlannerToggle", true, false) as Button
	_departures_text = _departures.text


func after() -> void:
	_main.free()
	for path in [_settings_path, _mood_path, _departures_path]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func after_test() -> void:
	_departures.text = _departures_text
	(_main.get_node("MoodOverlay") as MoodOverlay).set_shown(false)


func _settle() -> void:
	for i in 5:
		await get_tree().process_frame


func test_the_planner_toggle_starts_a_gap_right_of_the_departures_toggle() -> void:
	await _settle()
	var departures := _departures.get_global_rect()
	var planner := _planner.get_global_rect()
	print("RESTING departures=%s planner=%s" % [departures, planner])
	assert_float(departures.size.x).is_equal_approx(HudLayout.TOGGLE_W, 0.5)
	assert_float(planner.position.x).is_equal_approx(departures.end.x + HudLayout.GAP, 0.5)
	assert_float(planner.position.y).is_equal_approx(departures.position.y, 0.5)


func test_a_wider_departures_toggle_pushes_the_planner_toggle_right() -> void:
	_departures.text = "[____%s____]" % _departures_text
	await _settle()
	var departures := _departures.get_global_rect()
	var planner := _planner.get_global_rect()
	print("WIDE departures=%s planner=%s" % [departures, planner])
	assert_float(departures.size.x).is_greater(HudLayout.TOGGLE_W + 20.0)
	assert_bool(departures.intersects(planner)).is_false()
	assert_float(planner.position.x).is_equal_approx(departures.end.x + HudLayout.GAP, 0.5)


func test_the_mood_legend_card_clears_the_departures_row() -> void:
	(_main.get_node("MoodOverlay") as MoodOverlay).set_shown(true)
	_departures.text = "[____%s____]" % _departures_text
	await _settle()
	var card := (_main.find_child("MoodLegendCard", true, false) as Control).get_global_rect()
	var planner := _planner.get_global_rect()
	var mood := (_main.find_child("MoodToggle", true, false) as Control).get_global_rect()
	print(
		"LEGEND card=%s planner=%s departures=%s" % [card, planner, _departures.get_global_rect()]
	)
	assert_bool(card.intersects(planner)).is_false()
	assert_bool(card.intersects(_departures.get_global_rect())).is_false()
	assert_float(card.position.x).is_equal_approx(planner.end.x + HudLayout.GAP, 0.5)
	assert_float(card.position.y).is_equal_approx(mood.position.y, 0.5)


func test_a_floor_card_caps_the_room_below_the_column() -> void:
	var layer := Vector2(1536, 864)
	var free_room := LeftColumn.room_below(float(LeftColumn.LIST_TOP), layer, 0.0)
	var floor_card := Control.new()
	floor_card.position = Vector2(HudLayout.MARGIN, 500.0)
	floor_card.size = Vector2(300.0, 200.0)
	floor_card.add_to_group(LeftColumn.FLOOR_GROUP)
	add_child(floor_card)
	var capped := LeftColumn.room_below(float(LeftColumn.LIST_TOP), layer, 0.0)
	floor_card.visible = false
	var hidden := LeftColumn.room_below(float(LeftColumn.LIST_TOP), layer, 0.0)
	floor_card.free()
	print("ROOM free=%.0f capped=%.0f hidden=%.0f" % [free_room, capped, hidden])
	assert_float(capped).is_equal_approx(500.0 - HudLayout.GAP - LeftColumn.LIST_TOP, 0.5)
	assert_float(capped).is_less(free_room)
	assert_float(hidden).is_equal_approx(free_room, 0.5)
