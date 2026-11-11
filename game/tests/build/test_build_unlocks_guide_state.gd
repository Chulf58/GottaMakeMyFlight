class_name TestBuildUnlocksGuideState
extends GdUnitTestSuite
## What the unlock guide has shown and the player has seen is game state: it is
## kept in the BuildUnlocks snapshot (the save's "unlocks" part), checked on a
## load like the tier and the count, and empty for a new game.

var _unlocks: BuildUnlocks


func before_test() -> void:
	_unlocks = auto_free(BuildUnlocks.new())
	_unlocks.manual = true


func _through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data)) as Dictionary


func test_a_new_game_has_shown_and_seen_nothing() -> void:
	assert_bool(_unlocks.dialog_shown(2)).is_false()
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_array(_unlocks.to_snapshot()["shown"]).is_empty()
	assert_array(_unlocks.to_snapshot()["seen"]).is_empty()


func test_shown_tiers_and_seen_tools_survive_a_snapshot_through_json() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260})).is_true()
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
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60})).is_true()
	_unlocks.mark_dialog_shown(2)
	_unlocks.mark_tool_seen(BuildMode.Tool.CAFE_ROOM)
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [], "seen": []})).is_true()
	assert_bool(_unlocks.dialog_shown(2)).is_false()
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.CAFE_ROOM)).is_false()


func test_a_tier_that_is_not_open_cannot_be_marked_shown() -> void:
	(
		assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [3], "seen": []}))
		. is_false()
	)
	(
		assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [1], "seen": []}))
		. is_false()
	)
	(
		assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [2.5], "seen": []}))
		. is_false()
	)


func test_a_seen_entry_must_name_an_open_tool() -> void:
	var data := {"tier": 2, "made": 60, "shown": []}
	data["seen"] = ["NOT_A_TOOL"]
	assert_bool(_unlocks.from_snapshot(data)).is_false()
	data["seen"] = ["TREE"]
	assert_bool(_unlocks.from_snapshot(data)).is_false()
	data["seen"] = [7]
	assert_bool(_unlocks.from_snapshot(data)).is_false()


func test_a_refused_snapshot_changes_nothing() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [2], "seen": []})).is_true()
	(
		assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [3], "seen": []}))
		. is_false()
	)
	assert_bool(_unlocks.dialog_shown(2)).is_true()
	assert_int(_unlocks.tier()).is_equal(2)
