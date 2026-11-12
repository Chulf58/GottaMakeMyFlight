class_name TestGameMenu
extends GdUnitTestSuite
## The game menu and the new-game incidents question, apart from the main
## scene: the menu holds the clock, Resume and Esc release it, the Incidents
## switch drives the director's flag, the question sets the flag from
## chosen(accepted), and both queue for the clock's one exclusive turn behind a
## major incident panel (and the panel behind them). The IncidentPanelKit world
## has a clock, a bare SaveGame and the real IncidentPanel.

var _kit := IncidentPanelKit.new()
var _menu: GameMenu


func before_test() -> void:
	_kit.build(self)
	_menu = GameMenu.new()
	_menu.director = _kit.director
	_menu.clock = _kit.clock
	_menu.save_game = _kit.save
	_kit.port.add_child(_menu)


func after_test() -> void:
	_kit.port.free()


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func test_opening_shows_the_menu_and_holds_the_clock() -> void:
	assert_bool(_kit.clock.holds.is_holding()).is_false()
	assert_bool(_menu.open()).is_true()
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	assert_int(_kit.clock.holds.count()).is_equal(1)
	assert_object(_menu.resume_button()).is_not_null()
	assert_object(_menu.settings_button()).is_not_null()
	assert_bool(_menu.open()).is_false()


func test_resume_releases_the_hold_and_removes_the_menu() -> void:
	_menu.open()
	_menu.resume_button().pressed.emit()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()
	assert_int(_kit.clock.holds.count()).is_equal(0)
	assert_object(_menu.resume_button()).is_null()


func test_esc_while_open_closes_it() -> void:
	_menu.open()
	_kit.port.push_input(_esc())
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()


func test_the_menu_tells_the_hud_when_it_opens_and_closes() -> void:
	var seen: Array[bool] = []
	_menu.dialog_changed.connect(func(open: bool) -> void: seen.append(open))
	_menu.open()
	_menu.press_resume()
	assert_array(seen).is_equal([true, false])


func test_the_settings_page_holds_only_the_incidents_switch_and_back() -> void:
	_menu.open()
	_menu.settings_button().pressed.emit()
	var switch := _menu.incidents_switch()
	assert_object(switch).is_not_null()
	assert_bool(switch.get_parent().visible).is_true()
	var names: Array[String] = []
	for child in switch.get_parent().get_children():
		names.append(child.name)
	assert_array(names).is_equal(["Title", "Incidents", "Back"])
	assert_bool(switch.button_pressed).is_false()


func test_the_incidents_switch_sets_and_clears_the_director_flag() -> void:
	assert_bool(_kit.director.is_enabled()).is_false()
	_menu.open()
	_menu.settings_button().pressed.emit()
	_menu.incidents_switch().button_pressed = true
	assert_bool(_kit.director.is_enabled()).is_true()
	_menu.incidents_switch().button_pressed = false
	assert_bool(_kit.director.is_enabled()).is_false()


func test_the_switch_shows_the_flag_as_it_stands() -> void:
	_kit.director.set_enabled(true)
	_menu.open()
	assert_bool(_menu.incidents_switch().button_pressed).is_true()


func test_the_question_turns_incidents_on_when_accepted() -> void:
	assert_bool(_menu.ask_incidents()).is_true()
	assert_bool(_menu.is_question_open()).is_true()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	_menu.question().accept_button().pressed.emit()
	assert_bool(_kit.director.is_enabled()).is_true()
	assert_bool(_menu.is_question_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()


func test_the_question_leaves_incidents_off_when_declined() -> void:
	_kit.director.set_enabled(true)
	_menu.ask_incidents()
	_menu.question().decline_button().pressed.emit()
	assert_bool(_kit.director.is_enabled()).is_false()
	assert_bool(_menu.is_question_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()


func test_a_menu_opened_while_a_major_panel_is_up_waits_behind_it() -> void:
	var id := _kit.offer()
	assert_bool(_kit.panel.is_open()).is_true()
	assert_bool(_menu.open()).is_true()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_menu.has_hold()).is_true()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	_kit.panel.dialog().decline_button().pressed.emit()
	assert_str(_kit.state_of(id)).is_equal(IncidentCatalogue.DECLINED)
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_kit.panel.is_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	_menu.press_resume()
	assert_bool(_kit.clock.holds.is_holding()).is_false()


func test_a_major_that_arrives_while_the_menu_is_open_waits_behind_the_menu() -> void:
	_menu.open()
	var id := _kit.announce()
	assert_bool(_kit.panel.is_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	_menu.press_resume()
	assert_bool(_kit.panel.is_open()).is_true()
	assert_bool(_kit.clock.holds.is_holding()).is_true()
	assert_bool(_kit.is_shown(id)).is_true()


func test_closing_a_menu_that_still_waits_gives_up_its_place() -> void:
	_kit.offer()
	_menu.open()
	_menu.close()
	assert_bool(_menu.has_hold()).is_false()
	assert_int(_kit.clock.holds.count()).is_equal(1)
	_kit.panel.dialog().decline_button().pressed.emit()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()


func test_a_load_ends_the_menu_and_the_question_without_setting_anything() -> void:
	_menu.open()
	_kit.load_happens()
	assert_bool(_menu.is_open()).is_false()
	_menu.ask_incidents()
	_kit.load_happens()
	assert_bool(_menu.is_question_open()).is_false()
	assert_bool(_kit.director.is_enabled()).is_false()
	assert_bool(_kit.clock.holds.is_holding()).is_false()
