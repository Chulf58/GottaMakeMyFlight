class_name TestGameMenuMain
extends GdUnitTestSuite
## The game menu on the real main scene (one boot): Esc outside build mode
## opens it and holds the clock; Esc inside build mode still closes the tray
## and opens nothing; Resume releases the hold; the Incidents switch drives the
## director's flag and the flag survives a SaveGame round trip; the HUD asks the
## new-game question as the intro welcome closes, with the clock held all the
## way, and the answer sets the flag; the HUD holds the camera still while the
## menu or a major incident panel is open.

const SEED := 2_611_537
const STRUCTURE := 0

var _main: Node
var _clock: SimClock
var _menu: GameMenu
var _director: IncidentDirector
var _hud: PassengerHud
var _build_menu: BuildMenu
var _camera: Node
var _shown_before := false


func before() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false
	_main = SaveTestKit.boot(self, SEED)
	_clock = _main.get_node("SimClock")
	_menu = _main.get_node("GameMenu")
	_director = _main.get_node("IncidentDirector")
	_hud = _main.get_node("PassengerHud")
	_build_menu = _main.get_node("BuildMenu")
	_camera = _main.get_node("TycoonCamera")
	_hud.press_starter_terminal()
	SaveTestKit.step(_main)


func after() -> void:
	IntroDialogue.shown_this_session = _shown_before
	_main.free()


func before_test() -> void:
	_menu.close()
	_director.set_enabled(false)


func _esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event, true)


func test_the_scene_wires_the_menu_to_the_director_clock_and_build_menu() -> void:
	assert_object(_menu.director).is_same(_director)
	assert_object(_menu.clock).is_same(_clock)
	assert_object(_menu.build_menu).is_same(_build_menu)
	assert_object(_menu.save_game).is_same(SaveTestKit.save_game(_main))


func test_esc_outside_build_mode_opens_the_menu_and_holds_the_clock() -> void:
	assert_bool(_clock.holds.is_holding()).is_false()
	assert_bool(_build_menu.is_tray_open()).is_false()
	_esc()
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_clock.holds.is_holding()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)


func test_esc_inside_build_mode_closes_the_tray_and_does_not_open_the_menu() -> void:
	_build_menu.press_category(STRUCTURE)
	_build_menu.build_session.sync()
	assert_bool(_build_menu.is_tray_open()).is_true()
	assert_bool(_clock.holds.is_holding()).is_true()
	_esc()
	assert_bool(_build_menu.is_tray_open()).is_false()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_menu.has_hold()).is_false()
	_build_menu.build_session.sync()
	assert_bool(_clock.holds.is_holding()).is_false()
	# The control: with build mode over, the next Esc opens the menu.
	_esc()
	assert_bool(_menu.is_open()).is_true()


func test_esc_with_a_tool_picked_and_no_tray_drops_the_tool_and_opens_no_menu() -> void:
	var mode: BuildMode = _main.get_node("BuildMode")
	mode.set_tool(BuildMode.Tool.SCANNER)
	_esc()
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_open()).is_false()
	_build_menu.build_session.sync()


func test_resume_releases_the_hold() -> void:
	_esc()
	assert_bool(_clock.holds.is_holding()).is_true()
	_menu.resume_button().pressed.emit()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_clock.holds.is_holding()).is_false()


func test_the_incidents_flag_survives_a_save_round_trip() -> void:
	var save := SaveTestKit.save_game(_main)
	_esc()
	_menu.settings_button().pressed.emit()
	_menu.incidents_switch().button_pressed = true
	assert_bool(_director.is_enabled()).is_true()
	_menu.press_resume()
	var data: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot()))
	assert_bool(data["incidents"]["enabled"]).is_true()
	_director.set_enabled(false)
	assert_bool(save.load_world(data)).is_true()
	assert_bool(_director.is_enabled()).is_true()
	# And off stays off.
	_director.set_enabled(false)
	var off: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot()))
	_director.set_enabled(true)
	assert_bool(save.load_world(off)).is_true()
	assert_bool(_director.is_enabled()).is_false()


func test_the_intro_closing_asks_the_question_and_the_answer_sets_the_flag() -> void:
	assert_bool(_hud.open_intro()).is_true()
	assert_object(_hud.intro()).is_not_null()
	assert_bool(_menu.is_question_open()).is_false()
	_hud.dismiss_intro()
	assert_object(_hud.intro()).is_null()
	assert_bool(_menu.is_question_open()).is_true()
	# The clock was held from the welcome page to here.
	assert_bool(_clock.holds.is_holding()).is_true()
	assert_bool(_director.is_enabled()).is_false()
	_menu.question().accept_button().pressed.emit()
	assert_bool(_director.is_enabled()).is_true()
	assert_bool(_menu.is_question_open()).is_false()
	assert_bool(_clock.holds.is_holding()).is_false()
	IntroDialogue.shown_this_session = false


func test_the_hud_holds_the_camera_still_while_the_menu_is_open() -> void:
	assert_bool(_camera.is_processing()).is_true()
	_esc()
	assert_bool(_camera.is_processing()).is_false()
	_menu.press_resume()
	assert_bool(_camera.is_processing()).is_true()


func test_the_hud_holds_the_camera_still_while_the_major_panel_is_open() -> void:
	var panel: IncidentPanel = _main.get_node("IncidentPanel")
	assert_bool(_camera.is_processing()).is_true()
	panel.dialog_changed.emit(true)
	assert_bool(_camera.is_processing()).is_false()
	panel.dialog_changed.emit(false)
	assert_bool(_camera.is_processing()).is_true()
