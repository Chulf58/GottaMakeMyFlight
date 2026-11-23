class_name TestHudNewAirport
extends GdUnitTestSuite
## A New Airport opens with the HUD pieces on their defaults, the mood overlay
## closed on Mood among them, while a continued game keeps the choices saved in
## the settings file (decision a-new-airport-starts-with-the-hud-overlays-closed-
## overlay-an). A toggle made in a new airport is still saved. The file is a
## per-run one, never the player's.

var _path: String
var _world: PassengerTestWorld
var _new_before := false


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("hud_new_airport")
	_new_before = GameBoot.new_airport
	_world = PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(8, 6)), PassengerTestWorld.starts_with(10, 20)
	)
	_seed_saved_choices()


func after_test() -> void:
	GameBoot.new_airport = _new_before
	DirAccess.remove_absolute(_path)
	_world.free_all()


## The player's earlier choices: mood overlay on in Boredom mode, departures
## board open, alert cards off (opposites of the defaults).
func _seed_saved_choices() -> void:
	HudFlagSetting.save_flag(_path, MoodOverlay.SETTING_KEY, true, "test")
	HudFlagSetting.save_int(_path, MoodOverlay.SETTING_MODE_KEY, MoodTint.Mode.BOREDOM, "test")
	HudFlagSetting.save_flag(_path, DeparturesBoard.SETTING_KEY, true, "test")
	HudFlagSetting.save_flag(_path, AlertStack.SETTING_KEY, false, "test")


func _overlay() -> MoodOverlay:
	var overlay := MoodOverlay.new()
	overlay.settings_path = _path
	overlay.sim = _world.sim
	add_child(overlay)
	return auto_free(overlay)


func _board() -> DeparturesBoard:
	var board := DeparturesBoard.new()
	board.settings_path = _path
	board.flights = auto_free(FlightSim.new())
	board.clock = auto_free(SimClock.new())
	add_child(board)
	return auto_free(board)


func _stack() -> AlertStack:
	var stack := AlertStack.new()
	stack.settings_path = _path
	stack.sim = _world.sim
	add_child(stack)
	return auto_free(stack)


func test_start_new_marks_a_new_airport_and_start_load_clears_it() -> void:
	GameBoot.start_new(func(_scene: String) -> Error: return OK)
	assert_bool(GameBoot.new_airport).is_true()
	GameBoot.start_load("a save", func(_scene: String) -> Error: return OK)
	assert_bool(GameBoot.new_airport).is_false()
	GameBoot.load_path = ""


func test_a_new_airport_opens_the_mood_overlay_closed_on_mood() -> void:
	GameBoot.new_airport = true
	var overlay := _overlay()
	print("new airport: shown=%s mode=%s" % [overlay.is_shown(), overlay.mode()])
	assert_bool(overlay.is_shown()).is_false()
	assert_int(overlay.mode()).is_equal(MoodTint.Mode.MOOD)


func test_a_continued_game_keeps_the_saved_mood_overlay_and_mode() -> void:
	GameBoot.new_airport = false
	var overlay := _overlay()
	print("continued: shown=%s mode=%s" % [overlay.is_shown(), overlay.mode()])
	assert_bool(overlay.is_shown()).is_true()
	assert_int(overlay.mode()).is_equal(MoodTint.Mode.BOREDOM)


func test_a_new_airport_opens_the_departures_board_and_alert_cards_on_their_defaults() -> void:
	GameBoot.new_airport = true
	var board := _board()
	assert_bool(board.is_setting_enabled()).is_false()
	assert_bool(board.is_shown()).is_false()
	board.flights.open_airport()
	board.flights.add_default_flight()
	board.refresh()
	assert_bool(board.is_shown()).is_false()
	assert_bool(_stack().cards_on()).is_true()


func test_a_continued_game_keeps_the_saved_departures_board_and_alert_cards() -> void:
	GameBoot.new_airport = false
	var board := _board()
	board.flights.open_airport()
	board.flights.add_default_flight()
	board.refresh()
	assert_bool(board.is_shown()).is_true()
	assert_bool(_stack().cards_on()).is_false()


func test_a_toggle_made_in_a_new_airport_is_still_saved() -> void:
	GameBoot.new_airport = true
	_overlay().set_shown(true)
	GameBoot.new_airport = false
	var next := _overlay()
	assert_bool(next.is_shown()).is_true()
