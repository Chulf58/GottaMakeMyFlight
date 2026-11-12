class_name TestIntroDialogueQuickKeys
extends GdUnitTestSuite
## Decision quicksave-f5-and-quickload-f8-work-while-a-dialog-is-open: an open
## IntroDialogue (the incident offer panel is built on it) lets F5 quick-save
## and F8 quick-load reach SaveGame, and still takes every other key. The
## SaveGame here counts the calls and writes nothing; the offer showing again
## after a load is TestIncidentPanelLoad's.


## A SaveGame that records the quick keys instead of touching a world.
class CountingSave:
	extends SaveGame
	var saves := 0
	var loads := 0

	func quick_save() -> bool:
		saves += 1
		return true

	func quick_load() -> bool:
		loads += 1
		return true


## Stands for the game behind the dialogue: counts the key presses that reach it.
class Behind:
	extends Node
	var keys := 0

	func _unhandled_key_input(_event: InputEvent) -> void:
		keys += 1


var _k := IncidentPanelKit.new()
var _counting: CountingSave
var _behind: Behind


func before_test() -> void:
	_k.build(self)
	# The kit's own SaveGame has no world; only the counting one answers keys.
	_k.save.set_process_unhandled_key_input(false)
	_counting = CountingSave.new()
	_k.port.add_child(_counting)
	_behind = Behind.new()
	_k.port.add_child(_behind)


func after_test() -> void:
	_k.port.free()


func _press(code: Key, shift := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = true
	_k.port.push_input(event)


func test_f5_quick_saves_while_an_incident_offer_is_open() -> void:
	_k.offer()
	assert_bool(_k.panel.is_open()).is_true()
	_press(SaveGame.QUICK_SAVE_KEY)
	assert_int(_counting.saves).is_equal(1)
	assert_int(_counting.loads).is_equal(0)
	assert_bool(_k.panel.is_open()).is_true()


func test_f8_quick_loads_and_the_offer_shows_again_after_the_load() -> void:
	_k.offer()
	_press(SaveGame.QUICK_LOAD_KEY)
	assert_int(_counting.loads).is_equal(1)
	assert_int(_counting.saves).is_equal(0)
	_k.load_happens()
	assert_bool(_k.panel.is_open()).is_true()
	assert_bool(_k.panel.dialog().accept_button() != null).is_true()


func test_f5_and_f8_reach_a_plain_dialogue_too() -> void:
	var dialog := IntroDialogue.new("Hello", "A plain dialogue.", 400.0)
	_k.port.add_child(dialog)
	_press(SaveGame.QUICK_SAVE_KEY)
	_press(SaveGame.QUICK_LOAD_KEY)
	assert_int(_counting.saves).is_equal(1)
	assert_int(_counting.loads).is_equal(1)
	assert_bool(dialog.is_dismissed()).is_false()


func test_every_other_key_is_still_taken_by_the_open_offer() -> void:
	_k.offer()
	for code: Key in [KEY_ESCAPE, KEY_F9, KEY_A, KEY_SPACE]:
		_press(code)
	_press(SaveGame.QUICK_SAVE_KEY, true)
	assert_int(_behind.keys).is_equal(0)
	assert_int(_counting.saves).is_equal(0)
	assert_int(_counting.loads).is_equal(0)
	assert_bool(_k.panel.is_open()).is_true()


func test_a_held_quick_key_is_taken_like_any_other() -> void:
	_k.offer()
	_press(SaveGame.QUICK_SAVE_KEY, false, true)
	_press(SaveGame.QUICK_LOAD_KEY, false, true)
	assert_int(_behind.keys).is_equal(0)
	assert_int(_counting.saves).is_equal(0)
	assert_int(_counting.loads).is_equal(0)
