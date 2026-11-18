class_name TestHintsBannerMissing
extends GdUnitTestSuite
## A hint is marked seen only when its card is really shown. While the status
## banner whose slot it takes is expected (the HUD gave the Hints a scene_root)
## but not there, the yield would fail silently and the checklist would keep
## the slot, so nothing shows, nothing is marked and the hint is tried again.

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("hints_banner_missing")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _world() -> Dictionary:
	return {
		"desks": 0,
		"scanners": 0,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
	}


## A Hints past its start grace in a scene with no banner yet.
func _hints(root: Node) -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	hints.scene_root = root
	add_child(hints)
	auto_free(hints)
	hints.advance(Hints.GRACE_S + 0.1, _world(), [])
	return hints


func _run(hints: Hints, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		hints.advance(0.25, _world(), ["Check-in"])
		left -= 0.25


func test_a_missing_banner_shows_nothing_and_marks_nothing_seen() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)
	var hints := _hints(root)
	var shown := []
	hints.shown.connect(func(id: StringName) -> void: shown.append(id))
	_run(hints, HintRules.HOLD_S + 1.0)
	print(
		(
			"NO BANNER showing=%s seen=%s shown=%s"
			% [hints.is_showing(), hints.is_seen(HintRules.PLACE_CHECKIN), shown]
		)
	)
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.card().visible).is_false()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()
	assert_array(shown).is_empty()
	var saved := HudFlagSetting.load_flag(
		_path, Hints.SEEN_PREFIX + HintRules.PLACE_CHECKIN, false, Hints.WHO
	)
	assert_bool(saved).is_false()


func test_the_hint_shows_and_is_marked_once_the_banner_is_there() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)
	var hints := _hints(root)
	_run(hints, HintRules.HOLD_S + 1.0)
	assert_bool(hints.is_showing()).is_false()
	var panel := StaffPanel.new()
	panel.name = "StaffPanel"
	root.add_child(panel)
	await await_idle_frame()
	_run(hints, 1.0)
	print(
		(
			"BANNER showing=%s seen=%s yielded_card_visible=%s"
			% [hints.shown_id(), hints.is_seen(HintRules.PLACE_CHECKIN), panel.hint_card().visible]
		)
	)
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_true()
	assert_bool(hints.card().visible).is_true()
	assert_bool(panel.hint_card().visible).is_false()


func test_with_no_banner_expected_the_hint_shows_as_before() -> void:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	add_child(hints)
	auto_free(hints)
	hints.advance(Hints.GRACE_S + 0.1, _world(), [])
	_run(hints, HintRules.HOLD_S + 1.0)
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_true()
