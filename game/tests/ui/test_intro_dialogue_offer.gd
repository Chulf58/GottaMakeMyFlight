class_name TestIntroDialogueOffer
extends GdUnitTestSuite
## The IntroDialogue's offer form (the major incident panel's): Accept and
## Decline in place of Continue, a chosen(accepted) signal, and no key that
## picks for the player. The plain dialogue keeps its single Continue button and
## emits no choice. How the intro opens is TestIntroDialogue's.

var _port: SubViewport
var _dialog: IntroDialogue
var _chosen: Array[bool] = []
var _dismissed := 0


func before_test() -> void:
	_chosen.clear()
	_dismissed = 0
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)


func after_test() -> void:
	_port.free()


func _open(offer: bool) -> void:
	_dialog = IntroDialogue.new("A visit", "Someone wants to visit.", 400.0, offer)
	_dialog.chosen.connect(func(accepted: bool) -> void: _chosen.append(accepted))
	_dialog.dismissed.connect(func() -> void: _dismissed += 1)
	_port.add_child(_dialog)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_an_offer_has_accept_and_decline_and_no_continue() -> void:
	_open(true)
	assert_bool(_dialog.accept_button() != null).is_true()
	assert_bool(_dialog.decline_button() != null).is_true()
	assert_str(_dialog.accept_button().text).is_equal("Accept")
	assert_str(_dialog.decline_button().text).is_equal("Decline")
	assert_bool(_dialog.accept_button().is_visible_in_tree()).is_true()
	assert_bool(_dialog.decline_button().is_visible_in_tree()).is_true()
	assert_bool(_dialog.continue_button().is_visible_in_tree()).is_false()


func test_the_two_buttons_do_not_overlap_and_sit_inside_the_box() -> void:
	_open(true)
	var box: Rect2 = _dialog.part_rects()["box"]
	var accept := _dialog.accept_button().get_global_rect()
	var decline := _dialog.decline_button().get_global_rect()
	print("box %s accept %s decline %s" % [box, accept, decline])
	assert_bool(accept.intersects(decline)).is_false()
	assert_bool(box.encloses(accept)).is_true()
	assert_bool(box.encloses(decline)).is_true()


func test_accept_emits_true_then_closes() -> void:
	_open(true)
	_dialog.accept_button().pressed.emit()
	assert_array(_chosen).is_equal([true])
	assert_int(_dismissed).is_equal(1)
	assert_bool(_dialog.is_dismissed()).is_true()


func test_decline_emits_false_then_closes() -> void:
	_open(true)
	_dialog.decline_button().pressed.emit()
	assert_array(_chosen).is_equal([false])
	assert_int(_dismissed).is_equal(1)


func test_a_choice_counts_once() -> void:
	_open(true)
	_dialog.accept_button().pressed.emit()
	_dialog.decline_button().pressed.emit()
	_dialog.choose(false)
	assert_array(_chosen).is_equal([true])
	assert_int(_dismissed).is_equal(1)


func test_no_key_picks_for_the_player() -> void:
	_open(true)
	for code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_Y]:
		_port.push_input(_key(code))
	assert_array(_chosen).is_empty()
	assert_int(_dismissed).is_equal(0)
	assert_bool(_dialog.is_dismissed()).is_false()


func test_the_plain_dialogue_is_unchanged_and_offers_no_choice() -> void:
	_open(false)
	assert_bool(_dialog.accept_button() == null).is_true()
	assert_bool(_dialog.decline_button() == null).is_true()
	assert_bool(_dialog.continue_button().is_visible_in_tree()).is_true()
	_dialog.choose(true)
	assert_array(_chosen).is_empty()
	assert_bool(_dialog.is_dismissed()).is_false()
	_port.push_input(_key(KEY_SPACE))
	assert_bool(_dialog.is_dismissed()).is_true()
	assert_array(_chosen).is_empty()
	assert_int(_dismissed).is_equal(1)
