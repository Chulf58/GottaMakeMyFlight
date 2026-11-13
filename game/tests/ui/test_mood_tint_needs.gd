class_name TestMoodTintNeeds
extends GdUnitTestSuite
## The Hunger, Toilet and Boredom modes of the mood floor overlay (decision
## crowd-need-display-mood-overlay-gains-hunger-toilet-and-bore): per need the
## floor is green below the sim's own threshold, orange at it and red from
## MoodTint.NEED_BAD_AT, and a mode tints only for its own need.

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


func _placed(cell: Vector2i) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = cell
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _world.sim.tick
	return p


## The mode's need threshold read from the sim that acts on it.
func _threshold(mode: MoodTint.Mode) -> int:
	match mode:
		MoodTint.Mode.HUNGER:
			return CafeSim.HUNGRY_AT
		MoodTint.Mode.TOILET:
			return ToiletSim.NEED_AT
		_:
			return BoredomSim.BORED_AT


func test_the_thresholds_are_the_sims_own() -> void:
	for mode in [MoodTint.Mode.HUNGER, MoodTint.Mode.TOILET, MoodTint.Mode.BOREDOM]:
		assert_int(MoodTint.need_threshold(mode)).is_equal(_threshold(mode))


func test_need_badness_is_green_below_orange_at_the_threshold_red_at_the_top() -> void:
	for mode in [MoodTint.Mode.HUNGER, MoodTint.Mode.TOILET, MoodTint.Mode.BOREDOM]:
		var at := _threshold(mode)
		var below := MoodTint.need_badness(mode, at - 1)
		var middle := MoodTint.need_badness(mode, at)
		var between := MoodTint.need_badness(mode, (at + MoodTint.NEED_BAD_AT) / 2)
		var above := MoodTint.need_badness(mode, MoodTint.NEED_BAD_AT)
		var maxed := MoodTint.need_badness(mode, 100)
		print(
			(
				"mode %d: below %s, at %s, between %s, red %s, max %s"
				% [mode, below, middle, between, above, maxed]
			)
		)
		assert_float(MoodTint.need_badness(mode, 0)).is_equal(0.0)
		assert_float(below).is_equal(0.0)
		assert_float(middle).is_equal_approx(0.5, 0.001)
		assert_float(between).is_greater(0.5)
		assert_float(between).is_less(1.0)
		assert_float(above).is_equal(1.0)
		assert_float(maxed).is_equal(1.0)


func test_need_colours_run_green_orange_red() -> void:
	var green := MoodTint.color_of(0.0, MoodTint.Mode.HUNGER)
	var orange := MoodTint.color_of(0.5, MoodTint.Mode.HUNGER)
	var red := MoodTint.color_of(1.0, MoodTint.Mode.HUNGER)
	assert_float(green.g).is_equal_approx(MoodTint.GOOD_COLOR.g, 0.001)
	assert_float(orange.g).is_equal_approx(MoodTint.ORANGE_COLOR.g, 0.001)
	assert_float(red.r).is_equal_approx(MoodTint.BAD_COLOR.r, 0.001)
	assert_float(orange.g).is_less(MoodTint.MIDDLE_COLOR.g)
	assert_float(orange.a).is_equal_approx(MoodTint.ALPHA, 0.001)
	# Mood mode keeps its yellow.
	assert_float(MoodTint.color_of(0.5).g).is_equal_approx(MoodTint.MIDDLE_COLOR.g, 0.001)


func test_each_mode_reads_its_own_need() -> void:
	var p := _placed(Vector2i(3, 3))
	p.hunger = 90
	p.toilet_need = 10
	p.boredom = 55
	var tick := _world.sim.tick
	assert_float(MoodTint.badness_for(p, tick, MoodTint.Mode.HUNGER)).is_equal(1.0)
	assert_float(MoodTint.badness_for(p, tick, MoodTint.Mode.TOILET)).is_equal(0.0)
	assert_float(MoodTint.badness_for(p, tick, MoodTint.Mode.BOREDOM)).is_greater(0.4)
	assert_float(MoodTint.badness_for(p, tick, MoodTint.Mode.MOOD)).is_equal(0.0)


func test_a_hungry_crowd_tints_hunger_mode_and_not_toilet_mode() -> void:
	var p := _placed(Vector2i(3, 3))
	p.hunger = 95
	p.toilet_need = 0
	var hunger := MoodTint.cells_for(_world.sim, MoodTint.Mode.HUNGER)
	var toilet := MoodTint.cells_for(_world.sim, MoodTint.Mode.TOILET)
	print("hunger mode %s; toilet mode (control) %s" % [hunger, toilet])
	assert_float(hunger[Vector2i(3, 3)]).is_equal(1.0)
	assert_float(hunger[Vector2i(4, 3)]).is_equal(MoodTint.SPREAD)
	assert_int(hunger.size()).is_equal(5)
	assert_float(toilet[Vector2i(3, 3)]).is_equal(0.0)
	for cell: Vector2i in toilet:
		assert_float(toilet[cell]).is_equal(0.0)
	assert_dict(MoodTint.cells_for(_world.sim)).is_equal(
		MoodTint.cells_for(_world.sim, MoodTint.Mode.MOOD)
	)
