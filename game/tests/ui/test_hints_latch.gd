class_name TestHintsLatch
extends GdUnitTestSuite
## The hints' kept opportunity: a cause that becomes true is latched until it
## clears or its hint shows, so it survives another hint on screen and the gap
## after it; a hint already seen is never latched, so Reset hints is no trigger.

const NO_DESK := {"desks": 0, "scanners": 0}

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("hints_latch")
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


func test_a_cause_that_arrives_while_another_hint_shows_is_kept_for_after_the_gap() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	# A toilet need first appears while the check-in hint holds the slot.
	var both := _world({"desks": 0, "scanners": 0, "stalls": 0, "max_toilet_need": 99})
	_run(hints, 2.0, both)
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	# Past its dwell and the gap, with no category open and well short of IDLE_S.
	_run(hints, Hints.DWELL_S + Hints.MIN_GAP_S, both)
	assert_str(hints.shown_id()).is_equal(HintRules.TOILET)
	assert_float(hints._idle).is_less(Hints.IDLE_S)


func test_a_kept_opportunity_is_dropped_when_its_cause_clears() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	var both := _world({"desks": 0, "scanners": 0, "stalls": 0, "max_toilet_need": 99})
	_run(hints, 2.0, both)
	# The need goes away (a stall was built), so the toilet hint is moot.
	_run(hints, 2.0, _world(NO_DESK))
	_run(hints, Hints.DWELL_S + Hints.MIN_GAP_S + 5.0, _world(NO_DESK))
	assert_bool(hints.is_seen(HintRules.TOILET)).is_false()
	# The need comes back: it is a new opportunity, and the hint shows.
	_run(hints, HintRules.HOLD_S + 0.5, both)
	assert_str(hints.shown_id()).is_equal(HintRules.TOILET)


func test_a_seen_hints_returning_cause_is_not_latched_so_reset_needs_a_new_trigger() -> void:
	var hints := _settled(_world(NO_DESK))
	_run(hints, HintRules.HOLD_S + 0.5, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	# The cause clears (a desk is built) and returns (it is removed), and stays.
	_run(hints, 1.0, _world())
	_run(hints, Hints.DWELL_S + 1.0, _world(NO_DESK))
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints._latched.has(HintRules.PLACE_CHECKIN)).is_false()
	_run(hints, 3.0, _world(NO_DESK))
	hints.reset_seen()
	# Reset hints alone is no trigger: no category, no new edge, well short of IDLE_S.
	_run(hints, 5.0, _world(NO_DESK))
	assert_bool(hints.is_showing()).is_false()
	# A new trigger, the category opened, shows it again.
	_run(hints, 1.0, _world(NO_DESK), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
