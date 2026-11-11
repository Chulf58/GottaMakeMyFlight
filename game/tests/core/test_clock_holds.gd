class_name TestClockHolds
extends GdUnitTestSuite
## The clock's shared holds (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): the clock is paused while the player paused it
## or any hold is held, a release restores nothing, a resume or a new speed ends
## only the holds that give way, a hold ends with its owner, and a load drops
## every hold. The exclusive turn is in test_clock_holds_turns.gd.

var _clock: SimClock
var _a: Node
var _b: Node
var _c: Node
## Names of the owners whose turn came, in order.
var _turns: Array[String] = []


func before_test() -> void:
	_turns.clear()
	_clock = auto_free(SimClock.new())
	add_child(_clock)
	_a = _owner("A")
	_b = _owner("B")
	_c = _owner("C")


func _owner(owner_name: String) -> Node:
	var node: Node = auto_free(Node.new())
	node.name = owner_name
	add_child(node)
	return node


func _turn_of(owner_name: String) -> Callable:
	return func() -> void: _turns.append(owner_name)


func _ticks_after(seconds: float) -> int:
	var before := _clock.tick
	_clock.advance(seconds)
	return _clock.tick - before


func test_two_holds_released_first_then_second_never_resume_early() -> void:
	_clock.set_speed(2)
	var first := _clock.holds.acquire(_a)
	var second := _clock.holds.acquire(_b)
	assert_bool(_clock.holds.release(first)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_ticks_after(0.11)).is_equal(0)
	assert_bool(_clock.holds.release(second)).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_ticks_after(0.11)).is_equal(4)


func test_two_holds_released_second_then_first_never_resume_early() -> void:
	var first := _clock.holds.acquire(_a)
	var second := _clock.holds.acquire(_b)
	_clock.holds.release(second)
	assert_bool(_clock.paused).is_true()
	assert_int(_ticks_after(0.11)).is_equal(0)
	_clock.holds.release(first)
	assert_bool(_clock.paused).is_false()
	assert_int(_ticks_after(0.11)).is_equal(2)


func test_a_release_gives_the_players_pause_not_the_one_from_before_the_hold() -> void:
	_clock.set_speed(3)
	var token := _clock.holds.acquire(_a)
	# The player pauses while held: a snapshot from before would resume.
	_clock.set_paused(true)
	_clock.holds.release(token)
	assert_bool(_clock.paused).is_true()
	assert_bool(_clock.player_paused).is_true()
	assert_int(_clock.speed).is_equal(3)


func test_a_held_clock_keeps_the_players_speed_for_after_the_release() -> void:
	_clock.set_paused(true)
	var token := _clock.holds.acquire(_a)
	_clock.set_speed(3)
	_clock.set_paused(false)
	# A hold that does not give way keeps the clock paused meanwhile.
	assert_bool(_clock.paused).is_true()
	assert_bool(_clock.player_paused).is_false()
	_clock.holds.release(token)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	assert_int(_ticks_after(0.11)).is_equal(6)


func test_resuming_ends_the_holds_that_give_way_and_keeps_the_others() -> void:
	var giving := _clock.holds.acquire(_a, true)
	var keeping := _clock.holds.acquire(_b)
	_clock.set_paused(false)
	assert_bool(_clock.holds.has(giving)).is_false()
	assert_bool(_clock.holds.has(keeping)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_bool(_clock.holds.release(giving)).is_false()


func test_a_new_speed_ends_a_hold_that_gives_way_and_the_same_speed_does_not() -> void:
	_clock.set_speed(2)
	_clock.set_paused(true)
	var token := _clock.holds.acquire(_a, true)
	_clock.set_paused(true)
	_clock.set_speed(2)
	assert_bool(_clock.holds.has(token)).is_true()
	_clock.set_speed(3)
	assert_bool(_clock.holds.has(token)).is_false()
	# Still paused by the player, who paused before the hold.
	assert_bool(_clock.paused).is_true()


func test_an_owner_leaving_the_tree_ends_its_hold() -> void:
	var token := _clock.holds.acquire(_a)
	remove_child(_a)
	_a.free()
	assert_bool(_clock.holds.has(token)).is_false()
	assert_bool(_clock.paused).is_false()


func test_an_owner_freed_while_holding_ends_its_hold() -> void:
	var owner := Node.new()
	add_child(owner)
	var token := _clock.holds.acquire(owner)
	assert_bool(_clock.paused).is_true()
	owner.free()
	assert_bool(_clock.holds.has(token)).is_false()
	assert_bool(_clock.paused).is_false()


func test_a_released_hold_no_longer_follows_its_owner() -> void:
	var token := _clock.holds.acquire(_a)
	_clock.holds.release(token)
	assert_bool(_a.tree_exiting.get_connections().is_empty()).is_true()


func test_an_owner_outside_the_tree_gets_no_hold() -> void:
	var loose: Node = auto_free(Node.new())
	(
		assert_error(
			func() -> void: assert_int(_clock.holds.acquire(loose)).is_equal(ClockHolds.NONE)
		)
		. is_push_error("ClockHolds: a hold needs an owner in the tree")
	)
	assert_bool(_clock.paused).is_false()


func test_a_load_drops_every_hold_and_keeps_the_saved_pause() -> void:
	var data := _clock.to_snapshot()
	_clock.holds.acquire(_a)
	_clock.holds.take_turn(_b, _turn_of("B"))
	assert_bool(_clock.from_snapshot(data)).is_true()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()
	data["paused"] = true
	_clock.holds.acquire(_a)
	assert_bool(_clock.from_snapshot(data)).is_true()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.player_paused).is_true()


func test_a_refused_snapshot_keeps_the_holds() -> void:
	var token := _clock.holds.acquire(_a)
	var bad := _clock.to_snapshot()
	bad.erase("tick")
	(
		assert_error(func() -> void: assert_bool(_clock.from_snapshot(bad)).is_false())
		. is_push_error("SimClock.from_snapshot: missing key 'tick'")
	)
	assert_bool(_clock.holds.has(token)).is_true()


func test_a_snapshot_taken_while_held_says_paused() -> void:
	_clock.holds.acquire(_a)
	assert_bool(_clock.to_snapshot()["paused"]).is_true()
	assert_bool(_clock.player_paused).is_false()


func test_setting_paused_sets_only_the_players_pause() -> void:
	var token := _clock.holds.acquire(_a)
	_clock.paused = false
	assert_bool(_clock.paused).is_true()
	_clock.holds.release(token)
	assert_bool(_clock.paused).is_false()


func test_fast_forward_stays_off_while_any_hold_is_held() -> void:
	_clock.fast_forward_source = func() -> int: return _clock.tick + 100_000
	var token := _clock.holds.acquire(_a)
	assert_int(_ticks_after(0.11)).is_equal(0)
	assert_bool(_clock.is_fast_forwarding()).is_false()
	_clock.holds.release(token)
	# Control: released, the same frame fast-forwards (10 steps, the cap).
	assert_int(_ticks_after(0.1)).is_equal(SimClock.MAX_STEPS_PER_FRAME)
	assert_bool(_clock.is_fast_forwarding()).is_true()
