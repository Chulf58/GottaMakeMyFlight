class_name TestHints
extends GdUnitTestSuite
## The hint queue (HUD 7/7, decision first-time-hints-above-the-build-bar-
## moment-of-need-per-profile-memory): one hint at a time, triggered by an
## opportunity (a build category opened, the cause first true) or by
## inactivity, remembered per profile, dwell counted only while it shows.

const NO_DESK := {"desks": 0, "scanners": 0}

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("hints")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _hints() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	add_child(hints)
	return auto_free(hints)


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


## A Hints past its start grace, with a baseline read of `world`.
func _settled(world: Dictionary) -> Hints:
	var hints := _hints()
	hints.advance(Hints.GRACE_S + 0.1, world, [])
	return hints


func _run(hints: Hints, seconds: float, world: Dictionary, open: Array = []) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(0.25, left)
		hints.advance(step, world, open)
		left -= step


func test_nothing_shows_during_the_grace_after_the_world_starts() -> void:
	var hints := _hints()
	hints.advance(Hints.GRACE_S - 1.0, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_false()


func test_opening_the_category_shows_its_hint_once_the_cause_has_held() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, 1.0, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_false()
	_run(hints, HintRules.HOLD_S, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	assert_str(hints.body_label().text).is_equal(HintRules.text(HintRules.PLACE_CHECKIN))
	assert_bool(hints.card().visible).is_true()


func test_a_cause_true_from_the_start_waits_for_a_category_or_inactivity() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, Hints.IDLE_S - 1.0, _world(NO_DESK))
	assert_bool(hints.is_showing()).is_false()
	_run(hints, 2.0, _world(NO_DESK))
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)


func test_player_activity_restarts_the_inactivity_clock() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, Hints.IDLE_S - 5.0, _world(NO_DESK))
	hints.note_activity()
	_run(hints, 10.0, _world(NO_DESK))
	assert_bool(hints.is_showing()).is_false()


func test_a_cause_that_becomes_true_is_an_opportunity_with_no_category_open() -> void:
	var hints := _settled(_world())
	_run(hints, 2.0, _world())
	assert_bool(hints.is_showing()).is_false()
	var needy := _world({"stalls": 0, "max_toilet_need": ToiletSim.NEED_AT})
	_run(hints, HintRules.HOLD_S + 0.5, needy)
	assert_str(hints.shown_id()).is_equal(HintRules.TOILET)


func test_a_cause_that_flickers_off_before_it_holds_shows_nothing() -> void:
	var hints := _settled(_world())
	var needy := _world({"stalls": 0, "max_toilet_need": ToiletSim.NEED_AT})
	_run(hints, HintRules.HOLD_S - 0.5, needy)
	_run(hints, 0.5, _world())
	_run(hints, HintRules.HOLD_S - 0.5, needy)
	assert_bool(hints.is_showing()).is_false()


func test_a_hint_counts_as_seen_once_shown_and_a_new_profile_session_keeps_it() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_true()
	var next := _settled(_world(NO_DESK))
	assert_bool(next.is_seen(HintRules.PLACE_CHECKIN)).is_true()
	_run(next, Hints.IDLE_S + 2.0, _world(NO_DESK), ["Check-in"])
	assert_bool(next.is_showing()).is_false()


func test_a_hint_hides_after_its_dwell_and_the_next_waits_out_the_gap() -> void:
	var both := _world({"desks": 0, "scanners": 0, "stalls": 0, "max_toilet_need": 99})
	var hints := _settled(both)
	_run(hints, HintRules.HOLD_S + 0.5, both, ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	_run(hints, Hints.DWELL_S, both)
	assert_bool(hints.is_showing()).is_false()
	_run(hints, Hints.MIN_GAP_S - 2.0, both)
	assert_bool(hints.is_showing()).is_false()
	_run(hints, 3.0, both, ["Toilets"])
	assert_str(hints.shown_id()).is_equal(HintRules.TOILET)


func test_dwell_does_not_count_while_a_modal_is_open() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	var modal_open := [true]
	hints.modal = func() -> bool: return modal_open[0]
	_run(hints, Hints.DWELL_S * 2.0, _world(NO_DESK))
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	modal_open[0] = false
	_run(hints, Hints.DWELL_S + 0.5, _world(NO_DESK))
	assert_bool(hints.is_showing()).is_false()


func test_no_hint_is_picked_while_a_modal_is_open() -> void:
	var hints := _settled(_world(NO_DESK))
	hints.modal = func() -> bool: return true
	_run(hints, Hints.IDLE_S + 5.0, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()


func test_a_solved_cause_ends_the_hint_after_its_least_showing_time() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	_run(hints, 1.0, _world())
	assert_bool(hints.is_showing()).is_true()
	_run(hints, Hints.MIN_SHOW_S, _world())
	assert_bool(hints.is_showing()).is_false()


func test_off_shows_nothing_and_marks_nothing_seen() -> void:
	var hints := _settled(_world(NO_DESK))
	hints.set_enabled(false)
	_run(hints, Hints.IDLE_S + 5.0, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()
	hints.set_enabled(true)
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)


func test_turning_hints_off_hides_the_one_on_screen() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_true()
	hints.set_enabled(false)
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.card().visible).is_false()


func test_a_new_world_starts_the_grace_again_and_keeps_what_was_seen() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	hints.reset_session()
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_true()
	var toilet := _world({"stalls": 0, "max_toilet_need": 99})
	hints.advance(Hints.GRACE_S - 1.0, toilet, [])
	_run(hints, HintRules.HOLD_S + 0.5, toilet, ["Toilets"])
	assert_bool(hints.is_showing()).is_false()


func test_reset_hints_makes_every_hint_new_again() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	hints.reset_seen()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()
	assert_bool(_settled(_world(NO_DESK)).is_seen(HintRules.PLACE_CHECKIN)).is_false()
	_run(hints, 1.0, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)


func test_the_off_mode_runs_nothing_and_hides_the_settings_row() -> void:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.OFF
	hints.settings_path = _path
	add_child(hints)
	auto_free(hints)
	hints.advance(Hints.GRACE_S + 0.1, _world(NO_DESK), [])
	_run(hints, Hints.IDLE_S + 5.0, _world(NO_DESK), ["Check-in"])
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.settings_row().visible).is_false()
	assert_bool(FileAccess.file_exists(_path)).is_false()
