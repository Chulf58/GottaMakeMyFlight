class_name TestBuildUnlocksGuideState
extends GdUnitTestSuite
## What the unlock guide has shown and the player has seen is game state: it is
## kept in the BuildUnlocks snapshot (the save's "unlocks" part, save version
## 15), required on a load like the tier and the count, checked entry by entry,
## and empty for a new game.

var _unlocks: BuildUnlocks


func before_test() -> void:
	_unlocks = auto_free(BuildUnlocks.new())
	_unlocks.manual = true


func _through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data)) as Dictionary


## A snapshot at tier 2 with the given marks.
func _at_tier_2(shown: Array, seen: Array) -> Dictionary:
	return {"tier": 2, "made": 60, "shown": shown, "seen": seen}


func _refused(data: Dictionary) -> bool:
	return not _unlocks.from_snapshot(data)


func test_a_new_game_has_shown_and_seen_nothing() -> void:
	assert_bool(_unlocks.dialog_shown(2)).is_false()
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_array(_unlocks.to_snapshot()["shown"]).is_empty()
	assert_array(_unlocks.to_snapshot()["seen"]).is_empty()


func test_shown_tiers_and_seen_tools_survive_a_snapshot_through_json() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260, "shown": [], "seen": []})).is_true()
	_unlocks.mark_dialog_shown(2)
	_unlocks.mark_dialog_shown(3)
	_unlocks.mark_tool_seen(BuildMode.Tool.CAFE_ROOM)
	var data := _through_json(_unlocks.to_snapshot())
	var other: BuildUnlocks = auto_free(BuildUnlocks.new())
	other.manual = true
	assert_bool(other.from_snapshot(data)).is_true()
	assert_bool(other.dialog_shown(2)).is_true()
	assert_bool(other.dialog_shown(3)).is_true()
	assert_bool(other.tool_seen(BuildMode.Tool.CAFE_ROOM)).is_true()
	assert_bool(other.tool_seen(BuildMode.Tool.COUNTER)).is_false()


func test_a_load_replaces_what_was_shown_and_seen() -> void:
	assert_bool(_unlocks.from_snapshot(_at_tier_2([], []))).is_true()
	_unlocks.mark_dialog_shown(2)
	_unlocks.mark_tool_seen(BuildMode.Tool.CAFE_ROOM)
	assert_bool(_unlocks.from_snapshot(_at_tier_2([], []))).is_true()
	assert_bool(_unlocks.dialog_shown(2)).is_false()
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.CAFE_ROOM)).is_false()


func test_a_snapshot_missing_shown_or_seen_is_refused() -> void:
	var no_shown := _at_tier_2([], [])
	no_shown.erase("shown")
	assert_bool(_refused(no_shown)).is_true()
	var no_seen := _at_tier_2([], [])
	no_seen.erase("seen")
	assert_bool(_refused(no_seen)).is_true()
	assert_bool(_refused({"tier": 2, "made": 60})).is_true()


func test_shown_and_seen_must_be_lists() -> void:
	assert_bool(_refused(_at_tier_2([], []).merged({"shown": 2}, true))).is_true()
	assert_bool(_refused(_at_tier_2([], []).merged({"seen": "CAFE_ROOM"}, true))).is_true()


func test_a_tier_that_is_not_open_cannot_be_marked_shown() -> void:
	assert_bool(_refused(_at_tier_2([3], []))).is_true()
	assert_bool(_refused(_at_tier_2([1], []))).is_true()
	assert_bool(_refused(_at_tier_2([2.5], []))).is_true()


func test_a_shown_tier_listed_twice_is_refused() -> void:
	assert_bool(_refused(_at_tier_2([2, 2], []))).is_true()


func test_a_seen_entry_must_name_an_open_card_tool() -> void:
	assert_bool(_refused(_at_tier_2([], ["NOT_A_TOOL"]))).is_true()
	assert_bool(_refused(_at_tier_2([], ["TREE"]))).is_true()
	assert_bool(_refused(_at_tier_2([], [7]))).is_true()


func test_a_seen_tool_listed_twice_is_refused() -> void:
	assert_bool(_refused(_at_tier_2([], ["CAFE_ROOM", "CAFE_ROOM"]))).is_true()


func test_a_start_tier_tool_cannot_be_seen() -> void:
	assert_bool(_refused(_at_tier_2([], ["WALL"]))).is_true()


func test_none_and_remove_cannot_be_seen() -> void:
	assert_bool(_refused(_at_tier_2([], ["NONE"]))).is_true()
	assert_bool(_refused(_at_tier_2([], ["REMOVE"]))).is_true()


func test_a_good_marked_snapshot_is_accepted() -> void:
	assert_bool(_unlocks.from_snapshot(_at_tier_2([2], ["CAFE_ROOM", "COUNTER"]))).is_true()
	assert_bool(_unlocks.dialog_shown(2)).is_true()
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.COUNTER)).is_true()


func test_a_refused_snapshot_changes_nothing() -> void:
	assert_bool(_unlocks.from_snapshot(_at_tier_2([2], []))).is_true()
	assert_bool(_refused(_at_tier_2([3], []))).is_true()
	assert_bool(_unlocks.dialog_shown(2)).is_true()
	assert_int(_unlocks.tier()).is_equal(2)
