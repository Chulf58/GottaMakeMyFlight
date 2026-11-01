class_name TestMoodTint
extends GdUnitTestSuite
## The colour mapping of the queue and mood floor overlay (HUD 5/7): badness
## from mood and queue wait, green to red, and which floor cells tint.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 5), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))


func after_test() -> void:
	_world.free_all()


## A passenger placed on `cell` in `stage`, as the sim would hold it there.
func _placed(cell: Vector2i, stage: Passenger.Stage, mood := 70) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = cell
	p.stage = stage
	p.stage_tick = _world.sim.tick
	p.mood = mood
	return p


func test_mood_badness_runs_from_fine_to_worst() -> void:
	assert_float(MoodTint.mood_badness(100)).is_equal(0.0)
	assert_float(MoodTint.mood_badness(Passenger.MOOD_START)).is_equal(0.0)
	assert_float(MoodTint.mood_badness(45)).is_equal_approx(0.5, 0.001)
	assert_float(MoodTint.mood_badness(20)).is_equal(1.0)
	assert_float(MoodTint.mood_badness(0)).is_equal(1.0)


func test_wait_badness_runs_from_short_to_long() -> void:
	assert_float(MoodTint.wait_badness(0)).is_equal(0.0)
	assert_float(MoodTint.wait_badness(MoodTint.OK_WAIT_TICKS)).is_equal(0.0)
	assert_float(MoodTint.wait_badness(600)).is_equal_approx(0.5, 0.001)
	assert_float(MoodTint.wait_badness(MoodTint.BAD_WAIT_TICKS)).is_equal(1.0)
	assert_float(MoodTint.wait_badness(100000)).is_equal(1.0)


func test_the_starting_mood_with_no_wait_is_green() -> void:
	var p := _placed(Vector2i(2, 2), Passenger.Stage.CHECKIN_QUEUE)
	assert_float(MoodTint.badness_of(p, _world.sim.tick)).is_equal(0.0)
	var green := MoodTint.color_of(0.0)
	assert_float(green.r).is_equal_approx(MoodTint.GOOD_COLOR.r, 0.001)
	assert_float(green.g).is_equal_approx(MoodTint.GOOD_COLOR.g, 0.001)
	assert_float(green.b).is_equal_approx(MoodTint.GOOD_COLOR.b, 0.001)
	assert_float(green.a).is_equal_approx(MoodTint.ALPHA, 0.001)


func test_colour_goes_green_yellow_red_and_clamps() -> void:
	var middle := MoodTint.color_of(0.5)
	var bad := MoodTint.color_of(1.0)
	assert_float(middle.r).is_equal_approx(MoodTint.MIDDLE_COLOR.r, 0.001)
	assert_float(middle.g).is_equal_approx(MoodTint.MIDDLE_COLOR.g, 0.001)
	assert_float(bad.r).is_equal_approx(MoodTint.BAD_COLOR.r, 0.001)
	assert_float(bad.g).is_equal_approx(MoodTint.BAD_COLOR.g, 0.001)
	assert_bool(MoodTint.color_of(-3.0).is_equal_approx(MoodTint.color_of(0.0))).is_true()
	assert_bool(MoodTint.color_of(9.0).is_equal_approx(MoodTint.color_of(1.0))).is_true()
	# Red rises over the green half and green falls over the red half.
	var last := MoodTint.color_of(0.0)
	for step in range(1, 11):
		var now := MoodTint.color_of(step / 10.0)
		if step <= 5:
			assert_bool(now.r >= last.r - 0.0001).is_true()
		if step > 5:
			assert_bool(now.g <= last.g + 0.0001).is_true()
		assert_float(now.a).is_equal_approx(MoodTint.ALPHA, 0.001)
		last = now


func test_a_long_queue_wait_is_bad_even_with_a_good_mood() -> void:
	var p := _placed(Vector2i(2, 2), Passenger.Stage.SECURITY_QUEUE, 100)
	var later := p.stage_tick + MoodTint.BAD_WAIT_TICKS
	assert_float(MoodTint.badness_of(p, later)).is_equal(1.0)
	assert_float(MoodTint.badness_of(p, p.stage_tick + 600)).is_equal_approx(0.5, 0.001)


func test_waiting_outside_a_queue_stage_does_not_count() -> void:
	var p := _placed(Vector2i(2, 2), Passenger.Stage.SEATED, 100)
	assert_float(MoodTint.badness_of(p, p.stage_tick + 100000)).is_equal(0.0)


func test_a_low_mood_is_bad_whatever_the_stage() -> void:
	var p := _placed(Vector2i(2, 2), Passenger.Stage.TO_GATE, 20)
	assert_float(MoodTint.badness_of(p, p.stage_tick)).is_equal(1.0)


func test_a_stuck_passenger_is_as_bad_as_it_gets() -> void:
	var p := _placed(Vector2i(2, 2), Passenger.Stage.TO_CHECKIN, 100)
	p.stuck = Passenger.Stuck.NO_ROUTE
	assert_float(MoodTint.badness_of(p, p.stage_tick)).is_equal(1.0)


func test_cells_tint_under_passengers_and_lend_half_to_neighbours() -> void:
	_placed(Vector2i(3, 3), Passenger.Stage.CHECKIN_QUEUE, 20)
	var cells := MoodTint.cells_for(_world.sim)
	print("cells: %s" % cells)
	assert_float(cells[Vector2i(3, 3)]).is_equal(1.0)
	for step in MoodTint.NEIGHBOURS:
		assert_float(cells[Vector2i(3, 3) + step]).is_equal(MoodTint.SPREAD)
	assert_int(cells.size()).is_equal(5)


func test_a_cell_takes_the_worst_passenger_on_it() -> void:
	_placed(Vector2i(3, 3), Passenger.Stage.CHECKIN_QUEUE, 70)
	_placed(Vector2i(3, 3), Passenger.Stage.CHECKIN_QUEUE, 45)
	assert_float(MoodTint.cells_for(_world.sim)[Vector2i(3, 3)]).is_equal_approx(0.5, 0.001)


func test_passengers_off_the_floor_tint_nothing() -> void:
	_placed(Vector2i(3, 3), Passenger.Stage.SPAWNED, 0)
	_placed(Vector2i(4, 3), Passenger.Stage.MISSED, 0)
	_placed(Vector2i(5, 3), Passenger.Stage.CAFE_SEATED, 0)
	assert_dict(MoodTint.cells_for(_world.sim)).is_empty()


func test_cells_without_floor_are_left_out() -> void:
	_placed(Vector2i(0, 0), Passenger.Stage.CHECKIN_QUEUE, 20)
	var cells := MoodTint.cells_for(_world.sim)
	assert_bool(cells.has(Vector2i(0, 0))).is_true()
	assert_bool(cells.has(Vector2i(-1, 0))).is_false()
	assert_bool(cells.has(Vector2i(0, -1))).is_false()
	assert_int(cells.size()).is_equal(3)
