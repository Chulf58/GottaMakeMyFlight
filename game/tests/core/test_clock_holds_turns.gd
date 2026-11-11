class_name TestClockHoldsTurns
extends GdUnitTestSuite
## The exclusive turn on the clock's shared holds (decision daily-incidents-
## technical-design-incidentdirector-shared-clo): dialogs take the turn in the
## order their holds were taken; it moves on a release, an owner leaving or the
## player taking over, never on a tick; a load drops the line and runs no turn.

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


func test_the_exclusive_turn_passes_in_the_order_holds_were_taken() -> void:
	var first := _clock.holds.take_turn(_a, _turn_of("A"))
	var second := _clock.holds.take_turn(_b, _turn_of("B"))
	var third := _clock.holds.take_turn(_c, _turn_of("C"))
	assert_array(_turns).is_equal(["A"])
	assert_bool(_clock.holds.has_turn(first)).is_true()
	assert_bool(_clock.holds.has_turn(second)).is_false()
	_clock.holds.release(first)
	assert_array(_turns).is_equal(["A", "B"])
	assert_bool(_clock.holds.has_turn(second)).is_true()
	# Waiting holds the clock too.
	assert_bool(_clock.paused).is_true()
	_clock.holds.release(second)
	assert_array(_turns).is_equal(["A", "B", "C"])
	_clock.holds.release(third)
	assert_array(_turns).is_equal(["A", "B", "C"])
	assert_bool(_clock.paused).is_false()


func test_a_waiting_hold_released_early_never_gets_its_turn() -> void:
	var first := _clock.holds.take_turn(_a, _turn_of("A"))
	var second := _clock.holds.take_turn(_b, _turn_of("B"))
	_clock.holds.take_turn(_c, _turn_of("C"))
	_clock.holds.release(second)
	assert_array(_turns).is_equal(["A"])
	_clock.holds.release(first)
	assert_array(_turns).is_equal(["A", "C"])


func test_a_plain_hold_never_takes_the_turn_or_blocks_it() -> void:
	var plain := _clock.holds.acquire(_a)
	_clock.holds.take_turn(_b, _turn_of("B"))
	assert_array(_turns).is_equal(["B"])
	_clock.holds.release(plain)
	assert_array(_turns).is_equal(["B"])
	assert_bool(_clock.paused).is_true()


func test_the_turn_never_moves_on_ticks_only_on_a_release() -> void:
	var first := _clock.holds.take_turn(_a, _turn_of("A"))
	_clock.holds.take_turn(_b, _turn_of("B"))
	for i in 5:
		_clock.advance(1.0)
	assert_array(_turns).is_equal(["A"])
	_clock.holds.release(first)
	assert_array(_turns).is_equal(["A", "B"])


func test_an_owner_leaving_the_tree_passes_the_turn_on() -> void:
	_clock.holds.take_turn(_a, _turn_of("A"))
	_clock.holds.take_turn(_b, _turn_of("B"))
	remove_child(_a)
	_a.free()
	assert_array(_turns).is_equal(["A", "B"])


## A resume ends the pause of a hold in line that gives way, never its turn: a
## dialog behind the open sheet waits for the sheet to close.
func test_resuming_keeps_the_turn_of_a_hold_that_gives_way_and_ends_its_pause() -> void:
	var giving := _clock.holds.take_turn(_a, _turn_of("A"), true)
	_clock.set_paused(false)
	assert_bool(_clock.holds.has(giving)).is_true()
	assert_bool(_clock.holds.pauses(giving)).is_false()
	assert_bool(_clock.holds.has_turn(giving)).is_true()
	assert_bool(_clock.paused).is_false()
	var waiting := _clock.holds.take_turn(_b, _turn_of("B"))
	assert_array(_turns).is_equal(["A"])
	assert_bool(_clock.paused).is_true()
	# A second resume changes nothing: the waiting hold does not give way.
	_clock.set_paused(false)
	assert_bool(_clock.paused).is_true()
	_clock.holds.release(giving)
	assert_array(_turns).is_equal(["A", "B"])
	assert_bool(_clock.holds.has_turn(waiting)).is_true()
	_clock.holds.release(waiting)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)


func test_a_turn_handler_may_release_its_own_hold() -> void:
	var tokens: Array[int] = []
	var release_self := func() -> void:
		_turns.append("A")
		_clock.holds.release(tokens[0])
	var first := _clock.holds.take_turn(_b, _turn_of("B"))
	tokens.append(_clock.holds.take_turn(_a, release_self))
	_clock.holds.take_turn(_c, _turn_of("C"))
	_clock.holds.release(first)
	assert_array(_turns).is_equal(["B", "A", "C"])
	assert_bool(_clock.holds.has(tokens[0])).is_false()


func test_clear_drops_every_hold_and_runs_no_turn() -> void:
	var first := _clock.holds.take_turn(_a, _turn_of("A"))
	_clock.holds.take_turn(_b, _turn_of("B"))
	_clock.holds.acquire(_c)
	_clock.holds.clear()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()
	assert_array(_turns).is_equal(["A"])
	# A token from before the clear releases nothing that came after.
	var after := _clock.holds.acquire(_a)
	assert_bool(_clock.holds.release(first)).is_false()
	assert_bool(_clock.holds.has(after)).is_true()


## A ticked listener that takes a hold mid-frame ends the frame on its tick
## (anti-pattern a-simclock-frame-kept-ticking-after-a-tick-listener-paused-t).
func test_a_hold_taken_in_a_tick_ends_the_frame_on_that_tick() -> void:
	_clock.set_speed(3)
	var start := _clock.tick
	var take := func(at: int) -> void:
		if at == start + 2:
			_clock.holds.take_turn(_a, _turn_of("A"))
	_clock.ticked.connect(take)
	_clock.advance(10.0 * SimClock.STEP / 3.0)
	assert_int(_clock.tick).is_equal(start + 2)
	assert_array(_turns).is_equal(["A"])
