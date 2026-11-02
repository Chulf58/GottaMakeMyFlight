class_name TestAlertBoard
extends GdUnitTestSuite
## AlertBoard, the alert cards' rule (decision hud-steal-list-self-clearing-
## alert-cards-money-hover-departu): a card is up while its cause is true, held
## for show_after ticks first, and clears itself once the cause has been gone
## for clear_after ticks. One card per cause key. Every raise goes in the
## history, which marks when it cleared.

var _board: AlertBoard


func before_test() -> void:
	_board = AlertBoard.new()


func _cause(key: StringName, detail := "", show_after := 0, clear_after := 0) -> Dictionary:
	return {
		"key": key,
		"title": "Title %s" % key,
		"detail": detail,
		"targets": [Vector3(1.0, 0.0, 2.0)],
		"show_after": show_after,
		"clear_after": clear_after,
	}


func _keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for alert in _board.active():
		keys.append(alert["key"])
	return keys


func test_an_alert_appears_while_its_cause_is_true() -> void:
	assert_bool(_board.update([], 10)).is_false()
	assert_array(_board.active()).is_empty()
	assert_bool(_board.update([_cause(&"a")], 11)).is_true()
	assert_array(_keys()).is_equal([&"a"])
	assert_str(_board.active()[0]["title"]).is_equal("Title a")


func test_an_alert_clears_itself_when_its_cause_ends() -> void:
	_board.update([_cause(&"a"), _cause(&"b")], 1)
	assert_array(_keys()).is_equal([&"a", &"b"])
	assert_bool(_board.update([_cause(&"b")], 2)).is_true()
	assert_array(_keys()).is_equal([&"b"])
	_board.update([], 3)
	assert_array(_board.active()).is_empty()


func test_show_after_waits_for_the_cause_to_hold_and_a_gap_starts_again() -> void:
	_board.update([_cause(&"q", "", 60)], 100)
	_board.update([_cause(&"q", "", 60)], 159)
	assert_array(_board.active()).is_empty()
	# Gone for one update: the wait starts again from the next sighting.
	_board.update([], 160)
	_board.update([_cause(&"q", "", 60)], 161)
	_board.update([_cause(&"q", "", 60)], 220)
	assert_array(_board.active()).is_empty()
	_board.update([_cause(&"q", "", 60)], 221)
	assert_array(_keys()).is_equal([&"q"])


func test_clear_after_keeps_the_card_through_a_short_gap_with_one_history_entry() -> void:
	_board.update([_cause(&"q", "", 0, 60)], 0)
	_board.update([], 1)
	_board.update([], 60)
	assert_array(_keys()).is_equal([&"q"])
	# The cause is back inside the grace: same card, no second raise.
	_board.update([_cause(&"q", "", 0, 60)], 61)
	_board.update([], 62)
	_board.update([], 121)
	assert_array(_keys()).is_equal([&"q"])
	assert_int(_board.history().size()).is_equal(1)
	_board.update([], 122)
	assert_array(_board.active()).is_empty()
	assert_int(_board.history()[0]["cleared_tick"]).is_equal(122)


func test_one_card_per_cause_key() -> void:
	_board.update([_cause(&"a", "first"), _cause(&"a", "second")], 1)
	assert_int(_board.active().size()).is_equal(1)
	assert_str(_board.active()[0]["detail"]).is_equal("first")
	for tick in range(2, 30):
		_board.update([_cause(&"a")], tick)
	assert_int(_board.active().size()).is_equal(1)
	assert_int(_board.history().size()).is_equal(1)


func test_the_detail_follows_the_cause_while_the_card_is_up() -> void:
	_board.update([_cause(&"a", "1 desk full")], 1)
	var revision := _board.revision
	assert_bool(_board.update([_cause(&"a", "1 desk full")], 2)).is_false()
	assert_int(_board.revision).is_equal(revision)
	assert_bool(_board.update([_cause(&"a", "2 desks full")], 3)).is_true()
	assert_str(_board.active()[0]["detail"]).is_equal("2 desks full")
	assert_int(_board.revision).is_greater(revision)
	# The history keeps the words the card had when it came up.
	assert_str(_board.history()[0]["detail"]).is_equal("1 desk full")


func test_history_lists_raises_newest_first_with_their_clear_tick() -> void:
	_board.update([_cause(&"a")], 5)
	_board.update([_cause(&"a"), _cause(&"b")], 6)
	_board.update([_cause(&"b")], 7)
	var history := _board.history()
	assert_int(history.size()).is_equal(2)
	assert_that(history[0]["key"]).is_equal(&"b")
	assert_int(history[0]["raised_tick"]).is_equal(6)
	assert_int(history[0]["cleared_tick"]).is_equal(-1)
	assert_that(history[1]["key"]).is_equal(&"a")
	assert_int(history[1]["raised_tick"]).is_equal(5)
	assert_int(history[1]["cleared_tick"]).is_equal(7)
	# A cause that comes back after clearing is a new entry.
	_board.update([_cause(&"a"), _cause(&"b")], 8)
	assert_int(_board.history().size()).is_equal(3)
	assert_that(_board.history()[0]["key"]).is_equal(&"a")


func test_history_keeps_the_newest_entries_up_to_its_cap() -> void:
	for i in AlertBoard.HISTORY_CAP + 5:
		_board.update([_cause(&"a")], i * 2)
		_board.update([], i * 2 + 1)
	var history := _board.history()
	assert_int(history.size()).is_equal(AlertBoard.HISTORY_CAP)
	assert_int(history[0]["raised_tick"]).is_equal((AlertBoard.HISTORY_CAP + 4) * 2)
	assert_int(history[0]["cleared_tick"]).is_equal((AlertBoard.HISTORY_CAP + 4) * 2 + 1)


func test_reset_drops_the_cards_the_waits_and_the_history() -> void:
	_board.update([_cause(&"a"), _cause(&"q", "", 60)], 100)
	_board.reset()
	assert_array(_board.active()).is_empty()
	assert_array(_board.history()).is_empty()
	# A load can put the clock back: the wait for q starts from scratch.
	_board.update([_cause(&"q", "", 60)], 40)
	_board.update([_cause(&"q", "", 60)], 99)
	assert_array(_board.active()).is_empty()
	_board.update([_cause(&"q", "", 60)], 100)
	assert_array(_keys()).is_equal([&"q"])
