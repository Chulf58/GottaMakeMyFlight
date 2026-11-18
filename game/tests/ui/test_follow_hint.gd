class_name TestFollowHint
extends GdUnitTestSuite
## The follow hint (decision follow-invitation-and-passenger-card-a-click-a-
## passenger-fir): "Click a passenger to follow them to their flight" is due
## once a passenger is in the terminal and none is selected, it carries a Show
## me button, and the player selecting a passenger is what counts it seen: shown
## alone it is remembered for this launch only, so a player who ignored it hears
## it again next launch.

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("follow_hint")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _world(over := {}) -> Dictionary:
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
	}
	world.merge(over, true)
	return world


func _hints() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	add_child(hints)
	return auto_free(hints)


## A Hints past its start grace and baseline, with nobody in the terminal yet.
func _settled() -> Hints:
	var hints := _hints()
	hints.advance(Hints.GRACE_S + 0.1, _world(), [])
	hints.advance(0.25, _world(), [])
	return hints


func _run(hints: Hints, seconds: float, world: Dictionary) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(0.25, left)
		hints.advance(step, world, [])
		left -= step


func _saved(key: String) -> bool:
	return HudFlagSetting.load_flag(_path, Hints.SEEN_PREFIX + key, false, "Hints")


func test_the_cause_is_a_passenger_in_the_terminal_and_none_selected() -> void:
	var ready := _world({"follow_ready": true, "followed": false})
	assert_array(HintRules.causes(ready)).is_equal([HintRules.FOLLOW_PASSENGER])
	assert_array(HintRules.causes(_world({"follow_ready": true, "followed": true}))).is_empty()
	assert_array(HintRules.causes(_world({"follow_ready": false, "followed": false}))).is_empty()
	# A world that does not carry the two facts has no such cause.
	assert_array(HintRules.causes(_world())).is_empty()


func test_the_hint_comes_last_in_the_order_and_says_the_ruled_words() -> void:
	assert_str(HintRules.IDS[HintRules.IDS.size() - 1]).is_equal(HintRules.FOLLOW_PASSENGER)
	assert_str(HintRules.text(HintRules.FOLLOW_PASSENGER)).is_equal(
		"Click a passenger to follow them to their flight"
	)
	assert_array(HintRules.categories_for(HintRules.FOLLOW_PASSENGER)).is_empty()


func test_it_shows_with_a_show_me_button_once_the_cause_has_held() -> void:
	var hints := _settled()
	assert_bool(hints.show_me_button().visible).is_false()
	var ready := _world({"follow_ready": true, "followed": false})
	_run(hints, 1.0, ready)
	assert_bool(hints.is_showing()).is_false()
	_run(hints, 1.0, ready)
	assert_str(hints.shown_id()).is_equal(HintRules.FOLLOW_PASSENGER)
	assert_str(hints.body_label().text).is_equal("Click a passenger to follow them to their flight")
	assert_bool(hints.show_me_button().visible).is_true()
	assert_str(hints.show_me_button().text).is_equal("Show me")


func test_showing_alone_is_not_saved_so_a_later_launch_asks_again() -> void:
	var hints := _settled()
	_run(hints, 2.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(hints.is_showing()).is_true()
	assert_bool(hints.is_seen(HintRules.FOLLOW_PASSENGER)).is_true()
	assert_bool(_saved("follow_passenger")).is_false()
	# It ran its dwell out with no click: gone, and not up again this launch.
	_run(hints, Hints.DWELL_S + 1.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(hints.is_showing()).is_false()
	_run(hints, Hints.MIN_GAP_S + 5.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(hints.is_showing()).is_false()
	# The next launch reads the same file: the hint is due again.
	var next := _settled()
	assert_bool(next.is_seen(HintRules.FOLLOW_PASSENGER)).is_false()
	_run(next, 2.0, _world({"follow_ready": true, "followed": false}))
	assert_str(next.shown_id()).is_equal(HintRules.FOLLOW_PASSENGER)


func test_selecting_a_passenger_ends_the_hint_and_is_saved_as_seen() -> void:
	var hints := _settled()
	_run(hints, 2.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(hints.is_showing()).is_true()
	hints.advance(0.25, _world({"follow_ready": true, "followed": true}), [])
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.show_me_button().visible).is_false()
	assert_bool(_saved("follow_passenger")).is_true()
	var next := _settled()
	assert_bool(next.is_seen(HintRules.FOLLOW_PASSENGER)).is_true()
	_run(next, 3.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(next.is_showing()).is_false()


func test_a_selection_before_the_hint_shows_keeps_it_from_ever_showing() -> void:
	var hints := _settled()
	hints.advance(0.25, _world({"follow_ready": true, "followed": true}), [])
	assert_bool(_saved("follow_passenger")).is_true()
	_run(hints, 5.0, _world({"follow_ready": true, "followed": false}))
	assert_bool(hints.is_showing()).is_false()


func test_reset_hints_brings_the_follow_hint_back() -> void:
	var hints := _settled()
	hints.advance(0.25, _world({"follow_ready": true, "followed": true}), [])
	assert_bool(_saved("follow_passenger")).is_true()
	hints.reset_seen()
	assert_bool(_saved("follow_passenger")).is_false()
	assert_bool(hints.is_seen(HintRules.FOLLOW_PASSENGER)).is_false()
	# Selecting again saves it again.
	hints.advance(0.25, _world({"follow_ready": true, "followed": true}), [])
	assert_bool(_saved("follow_passenger")).is_true()


func test_a_hint_with_a_cause_waits_for_the_one_on_screen() -> void:
	var hints := _settled()
	var both := _world({"follow_ready": true, "followed": false, "stalls": 0})
	both["max_toilet_need"] = ToiletSim.NEED_AT
	_run(hints, 2.0, both)
	# One at a time: the toilet hint holds the slot first.
	assert_str(hints.shown_id()).is_equal(HintRules.TOILET)
	assert_bool(hints.show_me_button().visible).is_false()
