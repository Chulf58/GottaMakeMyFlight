class_name TestBoardingExitChoiceOrder
extends GdUnitTestSuite
## Every walker that sets off on a tick chooses its exit and files or turns
## pending before anyone steps (PassengerGates.choose_exits()), not in the
## passenger list's own order (boards aa2db71d, 54c9e0ce): a walker early in
## the list used to join an empty file and step, and the walkers later in the
## list then filed in front of it and held it back from the next tick on, one
## step too late.

const BOARDING := TestBoardingFiles.BOARDING
## The walker early in the list stands on (20, 7), the two later ones on
## (21, 6): the walk left of the first is under BoardingFiles.GAP_MM more than
## theirs (586 mm in the reference terminal), so they hold it back.
const BACK_CELL := Vector2i(20, 7)
const FRONT_CELL := Vector2i(21, 6)
const TICKS := 40

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## Three walkers turn out on one tick, the one early in the list (a lower id)
## a step behind the other two, which share a cell, so one is filed and one is
## pending. The first must stand still on that tick, and never close in on the
## walkers in front while they hold it.
func test_a_walker_early_in_the_list_is_held_by_the_ones_filing_after_it() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(BOARDING + 5)
	var early := TestBoardingFiles.walker(_world, BACK_CELL)
	var filed := TestBoardingFiles.walker(_world, FRONT_CELL)
	var pending := TestBoardingFiles.walker(_world, FRONT_CELL)
	_world.step()
	var files := _world.sim.files
	var gap := BoardingFiles.door_left(early) - BoardingFiles.door_left(filed)
	print("early %d mm behind, seg %d, path_index %d" % [gap, early.seg_mm, early.path_index])
	assert_array(files.door_file(early.exit_object)).is_equal([filed.id, early.id])
	assert_bool(files.is_pending(pending.id)).is_true()
	assert_int(gap).is_between(1, BoardingFiles.GAP_MM - 1)
	assert_that(early.at).is_equal(BACK_CELL)
	assert_int(early.path_index).is_equal(0)
	assert_int(early.seg_mm).is_equal(0)
	var gaps := {}
	for i in TICKS:
		_world.step()
		assert_str(TestBoardingFiles.spacing_problem(_world, gaps)).is_empty()
