class_name TestDeparturesBoardSetting
extends GdUnitTestSuite
## The departures board's on/off setting (decision hud-steal-list-self-clearing-
## alert-cards-money-hover-departu): the toggle button and the B key hide and
## show it, the choice persists in a settings file, and PassengerHud mounts it.

var _path: String
var _sim: FlightSim
var _clock: SimClock


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("departures_board_setting")
	_sim = auto_free(FlightSim.new())
	_clock = auto_free(SimClock.new())
	_sim.open_airport()


func after_test() -> void:
	DirAccess.remove_absolute(_path)


func _board() -> DeparturesBoard:
	var board := DeparturesBoard.new()
	board.settings_path = _path
	board.flights = _sim
	board.clock = _clock
	add_child(board)
	return auto_free(board)


func _b_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_B
	event.physical_keycode = KEY_B
	event.pressed = true
	return event


func _panel(board: DeparturesBoard) -> Control:
	return board.find_child("DeparturesPanel", true, false) as Control


func _toggle(board: DeparturesBoard) -> Button:
	return board.find_child("DeparturesToggle", true, false) as Button


func test_the_board_is_on_by_default() -> void:
	var board := _board()
	assert_bool(board.is_shown()).is_true()
	assert_bool(_panel(board).visible).is_true()


func test_the_toggle_button_hides_and_shows_the_panel() -> void:
	var board := _board()
	assert_bool(_toggle(board).button_pressed).is_true()
	_toggle(board).button_pressed = false
	assert_bool(board.is_shown()).is_false()
	assert_bool(_panel(board).visible).is_false()
	assert_bool(_toggle(board).visible).is_true()
	_toggle(board).button_pressed = true
	assert_bool(board.is_shown()).is_true()
	assert_bool(_panel(board).visible).is_true()


func test_the_choice_persists_to_the_next_board() -> void:
	_board().set_shown(false)
	var second := _board()
	assert_bool(second.is_shown()).is_false()
	assert_bool(_panel(second).visible).is_false()
	assert_bool(_toggle(second).button_pressed).is_false()
	second.set_shown(true)
	assert_bool(_board().is_shown()).is_true()


func test_the_setting_is_one_key_in_the_hud_section() -> void:
	_board().set_shown(false)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_path)).is_equal(OK)
	assert_bool(cfg.get_value("hud", "departures_board", true)).is_false()


func test_the_key_toggles_the_board_and_a_held_key_does_not_repeat() -> void:
	assert_bool(InputMap.has_action(DeparturesBoard.ACTION)).is_true()
	var board := _board()
	assert_bool(_b_key().is_action_pressed(DeparturesBoard.ACTION)).is_true()
	board._shortcut_input(_b_key())
	assert_bool(board.is_shown()).is_false()
	var held := _b_key()
	held.echo = true
	board._shortcut_input(held)
	assert_bool(board.is_shown()).is_false()
	board._shortcut_input(_b_key())
	assert_bool(board.is_shown()).is_true()


func test_a_modified_b_does_not_toggle() -> void:
	var board := _board()
	var event := _b_key()
	event.ctrl_pressed = true
	board._shortcut_input(event)
	assert_bool(board.is_shown()).is_true()


func test_the_key_is_free_of_every_other_action() -> void:
	for action in InputMap.get_actions():
		if action == DeparturesBoard.ACTION or String(action).begins_with("ui_"):
			continue
		assert_bool(_b_key().is_action_pressed(action)).is_false()


func test_the_hud_mounts_the_board() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var hud := PassengerHud.new()
	hud.clock = world.clock
	hud.flights = world.flights
	hud.sim = world.sim
	hud.departures_settings_path = _path
	add_child(hud)
	var board := hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	assert_object(board).is_not_null()
	assert_bool(board.is_shown()).is_true()
	assert_object(board.flights).is_same(world.flights)
	hud.free()
	world.free_all()
