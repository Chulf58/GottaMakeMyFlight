class_name TestAlertRail
extends GdUnitTestSuite
## The right rail (HUD 3/7, decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra, parts 3 and 5): alert cards and notices (the
## flight result card) newest first, at most AlertStack.MAX_CARDS drawn and
## '+N more' for the rest, a notice leaves after its seconds or on a click and
## keeps its history line, and an alert card still clears itself when its
## cause ends. The dirty-terminal cause drives the alert cards here.

const ROW_Y := 8

var _world: PassengerTestWorld
var _path: String
var _stack: AlertStack


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_world)).is_true()
	_path = SaveTestKit.run_path("alert_rail_setting")
	_stack = AlertStack.new()
	_stack.settings_path = _path
	_stack.sim = _world.sim
	add_child(_stack)


func after_test() -> void:
	_stack.free()
	DirAccess.remove_absolute(_path)


## A small notice card, so any number of them fit above the build tray.
func _post(key: StringName, seconds := 0.0) -> void:
	var card := PanelContainer.new()
	var label := Label.new()
	label.text = String(key)
	card.add_child(label)
	_stack.post_notice(key, card, seconds, "Notice %s" % key, "detail of %s" % key)


func _spills() -> void:
	for i in DirtyAlert.SHOW_AT:
		(
			assert_int(_world.sim.messes.add(MessSim.Kind.SPILL, Vector2i(2 + i * 2, ROW_Y)))
			. is_greater(0)
		)


func _clean_all() -> void:
	for id in _world.sim.messes.mess_ids():
		assert_bool(_world.sim.messes.clean(id)).is_true()


func _more() -> Button:
	return _stack.find_child("AlertsMore", true, false) as Button


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func test_alert_cards_and_notices_are_drawn_newest_first() -> void:
	_post(&"first")
	_spills()
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([DirtyAlert.KEY, &"first"])
	_post(&"second")
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([&"second", DirtyAlert.KEY, &"first"])
	# Posted again under its key, a notice replaces itself at the top.
	_post(&"first")
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([&"first", &"second", DirtyAlert.KEY])
	assert_int(_stack.history_lines().size()).is_equal(4)


func test_at_most_four_cards_show_and_the_rest_count_into_more() -> void:
	for i in 3:
		_post(StringName("n%d" % i))
	_stack.refresh()
	# Control: under the cap, everything shows and there is no '+N more'.
	assert_int(_stack.shown_keys().size()).is_equal(3)
	assert_int(_stack.more_count()).is_equal(0)
	assert_bool(_more().is_visible_in_tree()).is_false()
	for i in range(3, 6):
		_post(StringName("n%d" % i))
	_stack.refresh()
	print("RAIL_CAP shown=%s more=%d" % [_stack.shown_keys(), _stack.more_count()])
	assert_int(AlertStack.MAX_CARDS).is_equal(4)
	assert_array(_stack.shown_keys()).is_equal([&"n5", &"n4", &"n3", &"n2"])
	assert_int(_stack.more_count()).is_equal(2)
	assert_bool(_more().is_visible_in_tree()).is_true()
	assert_str(_more().text).is_equal("+2 more")
	_more().pressed.emit()
	assert_bool(_stack.is_tray_open()).is_true()
	_stack.set_tray_open(false)
	_stack.drop_notice(&"n5")
	_stack.drop_notice(&"n4")
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([&"n3", &"n2", &"n1", &"n0"])
	assert_int(_stack.more_count()).is_equal(0)
	assert_bool(_more().is_visible_in_tree()).is_false()


func test_a_timed_notice_leaves_after_its_seconds_and_stays_in_the_history() -> void:
	_post(&"timed", FlightResultPanel.SHOW_SECONDS)
	_post(&"kept")
	_stack.refresh()
	_stack.advance(FlightResultPanel.SHOW_SECONDS - 0.5)
	assert_bool(_stack.notice_card(&"timed") != null).is_true()
	_stack.advance(1.0)
	_stack.refresh()
	assert_bool(_stack.notice_card(&"timed") != null).is_false()
	assert_array(_stack.shown_keys()).is_equal([&"kept"])
	# A notice with no seconds stays until it is clicked.
	_stack.advance(1000.0)
	assert_bool(_stack.notice_card(&"kept") != null).is_true()
	var lines := _stack.history_lines()
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[1]).contains("Notice timed")
	assert_str(lines[1]).contains("detail of timed")


func test_a_click_on_a_notice_removes_it_and_keeps_its_history_line() -> void:
	_post(&"clicked", FlightResultPanel.SHOW_SECONDS)
	_stack.refresh()
	var card := _stack.notice_card(&"clicked")
	assert_bool(card.is_visible_in_tree()).is_true()
	card.gui_input.emit(_left_click())
	_stack.refresh()
	assert_bool(_stack.notice_card(&"clicked") != null).is_false()
	assert_array(_stack.shown_keys()).is_empty()
	assert_str(_stack.history_lines()[0]).contains("Notice clicked")


func test_an_alert_card_still_clears_itself_and_leaves_the_rail() -> void:
	_post(&"note")
	_spills()
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([DirtyAlert.KEY, &"note"])
	_clean_all()
	_stack.refresh()
	assert_array(_stack.shown_keys()).is_equal([&"note"])
	assert_object(_stack.card_node(DirtyAlert.KEY)).is_null()


func test_the_off_switch_hides_alert_cards_but_not_notices() -> void:
	_stack.set_cards_on(false)
	_spills()
	_post(&"note")
	_stack.refresh()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	assert_array(_stack.shown_keys()).is_equal([&"note"])
	assert_int(_stack.more_count()).is_equal(0)


func test_a_reset_drops_the_notices() -> void:
	_post(&"note")
	_stack.refresh()
	_stack.reset()
	assert_bool(_stack.notice_card(&"note") != null).is_false()
	assert_array(_stack.shown_keys()).is_empty()
	assert_int(_stack.history_lines().size()).is_equal(0)
