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


## With no entrance the grid has no staff reach regions, so the search cannot
## filter by them: messes it has no way to must not use up the bound. Seven
## walled-in messes are nearer in a straight line than the one it can reach.
func test_with_no_entrance_walled_in_messes_never_hide_a_reachable_one() -> void:
	var door: int = _world.sim.layout.entrances[0]
	var record := _world.grid.get_object(door)
	_edit(
		BuildEdit.remove_object(door),
		BuildEdit.place_object(record["def"], record["anchor"], record["facing"])
	)
	var box := Rect2i(18, 9, 3, 3)
	for x in range(box.position.x, box.end.x):
		_wall(Vector2i(x, box.position.y), BuildGrid.Side.NORTH)
		_wall(Vector2i(x, box.end.y - 1), BuildGrid.Side.SOUTH)
	for y in range(box.position.y, box.end.y):
		_wall(Vector2i(box.position.x, y), BuildGrid.Side.WEST)
		_wall(Vector2i(box.end.x - 1, y), BuildGrid.Side.EAST)
	var walled := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if walled < CleanerJobs.SEARCH_CANDIDATES + 1:
				walled += int(_messes().add(MessSim.Kind.LITTER, Vector2i(x, y)) != 0)
	var open := _messes().add(MessSim.Kind.LITTER, Vector2i(5, 15))
	var m := CleanerTestKit.cleaner_at(_world, START)
	_world.step()
	print(
		(
			"entrances %d, reach %d cells; %d walled messes, job %d (open %d)"
			% [
				_world.sim.layout.entrances.size(),
				_world.grid.staff_reach().size(),
				walled,
				m.job,
				open
			]
		)
	)
	assert_int(_world.sim.layout.entrances.size()).is_equal(0)
	assert_int(walled).is_greater(CleanerJobs.SEARCH_CANDIDATES)
	assert_int(m.job).is_equal(open)


## A bin's spot is the first free cell around it. When an edit frees an
## earlier side while a cleaner empties it from a later one, the cleaner walks
## to the new spot and starts over, so a save taken then still loads.
func test_a_bin_spot_an_edit_moves_sends_its_cleaner_to_the_new_spot() -> void:
	var bin_at := Vector2i(20, 5)
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, bin_at, 0)
	_undo.append(BuildEdit.remove_object(bin))
	var blocker := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, bin_at + Vector2i(0, 1), 0)
	var data := _messes().to_snapshot()
	data["bins"][str(bin)] = MessSim.BIN_CAPACITY
	assert_bool(_messes().from_snapshot(data)).is_true()
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(24, 5))
	var working := func() -> bool: return m.state == StaffMember.State.ON_DUTY
	assert_bool(CleanerTestKit.step_until(_world, working)).is_true()
	var first_spot := m.at
	assert_bool(_world.grid.apply(BuildEdit.remove_object(blocker)).ok).is_true()
	var after_edit := [m.state, m.work_left, CleanerJobs.job_spot(_world.staff, m)]
	var problem := str(StaffSnapshot.load(_world.staff.to_snapshot(), _world.sim).get("error", ""))
	var emptied := func() -> bool: return _messes().fill_of(bin) == 0
	assert_bool(CleanerTestKit.step_until(_world, emptied)).is_true()
	print(
		(
			(
				"worked from %s; after the edit state %d work %d spot %s; load check '%s';"
				+ " emptied from %s"
			)
			% [first_spot, after_edit[0], after_edit[1], after_edit[2], problem, m.at]
		)
	)
	assert_that(first_spot).is_equal(bin_at + Vector2i(1, 0))
	assert_int(after_edit[0]).is_equal(StaffMember.State.TO_STATION)
	assert_int(after_edit[1]).is_equal(0)
	assert_that(after_edit[2]).is_equal(bin_at + Vector2i(0, 1))
	assert_str(problem).is_empty()
	assert_that(m.at).is_equal(bin_at + Vector2i(0, 1))


func _wall(cell: Vector2i, side: int) -> void:
	_edit(BuildEdit.place_wall(cell, side), BuildEdit.remove_wall(cell, side))
