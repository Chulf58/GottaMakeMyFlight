class_name TestCleanerRetarget
extends GdUnitTestSuite
## A cleaner never stays on a job that went (decision cleaner-staff-and-
## messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess): a mess
## removed, one whose floor an edit took, a bin an edit took, and one it has no
## way to any more are let go, and it takes the next job nobody holds.

const NEAR := Vector2i(20, 10)
const FAR := Vector2i(5, 5)
const START := Vector2i(15, 10)

## One world for the file; each case starts with no messes and no staff, and
## puts back the grid edits it made (_undo).
var _world: PassengerTestWorld
var _undo: Array[BuildEdit] = []


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(CleanerTestKit.reset(_world)).is_true()


func after_test() -> void:
	assert_bool(CleanerTestKit.reset(_world)).is_true()
	MessTestKit.undo(_world, _undo)


func _messes() -> MessSim:
	return _world.sim.messes


func _edit(edit: BuildEdit, back: BuildEdit) -> void:
	var result := _world.grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	if result.ok:
		_undo.append(back)


## A cleaner on START walking to the near mess, two ticks in, and the far
## mess nobody holds: [cleaner, near id, far id].
func _walking() -> Array:
	var near := _messes().add(MessSim.Kind.LITTER, NEAR)
	var far := _messes().add(MessSim.Kind.LITTER, FAR)
	var m := CleanerTestKit.cleaner_at(_world, START)
	_world.step()
	_world.step()
	assert_int(m.job).is_equal(near)
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	return [m, near, far]


func test_a_cleaner_whose_mess_is_removed_lets_go_at_once_and_takes_the_next() -> void:
	var setup := _walking()
	var m: StaffMember = setup[0]
	assert_bool(_messes().remove(setup[1])).is_true()
	var at_once := [m.job, m.state]
	_world.step()
	print(
		(
			"after removal: job %d state %d; next tick job %d (far %d)"
			% [at_once[0], at_once[1], m.job, setup[2]]
		)
	)
	assert_int(at_once[0]).is_equal(0)
	assert_int(at_once[1]).is_equal(StaffMember.State.IDLE)
	assert_int(m.job).is_equal(setup[2])
	assert_int(int(_messes().get_mess(setup[2])["claimed_by"])).is_equal(m.id)


func test_a_mess_whose_floor_an_edit_takes_lets_its_cleaner_go() -> void:
	var setup := _walking()
	var m: StaffMember = setup[0]
	_edit(BuildEdit.remove_floor(NEAR), BuildEdit.paint_floor(NEAR, BuildGrid.FLOOR_TILE, 1))
	_world.step()
	var gone := _messes().get_mess(setup[1]).is_empty()
	var after_edit := m.job
	_world.step()
	print(
		(
			"near gone %s, job after the edit's tick %d, then %d (far %d)"
			% [gone, after_edit, m.job, setup[2]]
		)
	)
	assert_bool(gone).is_true()
	assert_int(after_edit).is_not_equal(setup[1])
	assert_int(m.job).is_equal(setup[2])


func test_a_bin_an_edit_takes_lets_its_cleaner_go() -> void:
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(20, 5), 0)
	var spot := Vector2i(20, 7)
	for i in MessSim.BIN_CAPACITY:
		MessTestKit.litter(_world, spot)
	var m := CleanerTestKit.cleaner_at(_world, START)
	_world.step()
	var claimed := CleanerJobs.bin_holder(_world.staff, bin)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(bin)).ok).is_true()
	print(
		(
			"bin claimed by %d (cleaner %d); after removal job %d state %d, bin claim %d"
			% [claimed, m.id, m.job, m.state, CleanerJobs.bin_holder(_world.staff, bin)]
		)
	)
	assert_int(claimed).is_equal(m.id)
	assert_int(m.job).is_equal(0)
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(CleanerJobs.bin_holder(_world.staff, bin)).is_equal(0)


func test_a_cleaner_with_no_way_to_its_mess_takes_another_and_leaves_it_unclaimed() -> void:
	var setup := _walking()
	var m: StaffMember = setup[0]
	for side in [BuildGrid.Side.NORTH, BuildGrid.Side.EAST, BuildGrid.Side.SOUTH]:
		_edit(BuildEdit.place_wall(NEAR, side), BuildEdit.remove_wall(NEAR, side))
	_edit(
		BuildEdit.place_wall(NEAR, BuildGrid.Side.WEST),
		BuildEdit.remove_wall(NEAR, BuildGrid.Side.WEST)
	)
	var far_done := func() -> bool: return _messes().get_mess(setup[2]).is_empty()
	var held := {}
	var watch := func() -> bool:
		held[m.job] = true
		return far_done.call()
	assert_bool(CleanerTestKit.step_until(_world, watch)).is_true()
	_world.run_to(_world.clock.tick + 3 * PassengerSim.BEAT_TICKS)
	var near := _messes().get_mess(setup[1])
	print(
		(
			"jobs held %s; near left %s claimed by %d; cleaner state %d, failed %s"
			% [
				held.keys(),
				not near.is_empty(),
				int(near.get("claimed_by", -1)),
				m.state,
				m.search_failed
			]
		)
	)
	assert_bool(held.has(setup[2])).is_true()
	assert_bool(near.is_empty()).is_false()
	assert_int(int(near["claimed_by"])).is_equal(0)
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_bool(m.search_failed).is_true()
