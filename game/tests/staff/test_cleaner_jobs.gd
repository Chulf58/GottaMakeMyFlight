class_name TestCleanerJobs
extends GdUnitTestSuite
## Cleaners (decision cleaner-staff-and-messes-visits-leave-messes-bins-fill-
## pooled-cleaners-nearest-mess): hired into the pool and fired out of it, an
## idle cleaner takes the nearest job by staff path that nobody holds, no two
## cleaners ever hold one job, cleaning removes the mess and its mood cost,
## emptying a full bin lets it take litter again, and a cleaner fired at work
## lets go of its claim.

const CLEANER := StaffMember.Role.CLEANER

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


func _staff() -> StaffSim:
	return _world.staff


func _messes() -> MessSim:
	return _world.sim.messes


func _edit(edit: BuildEdit, back: BuildEdit) -> void:
	var result := _world.grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	if result.ok:
		_undo.append(back)


func test_a_cleaner_is_hired_into_the_pool_enters_by_the_entrance_and_is_fired() -> void:
	var id := _staff().hire(CLEANER)
	var m := _staff().get_member(id)
	print("hired %d: count %d, in pool %s" % [id, _staff().count(CLEANER), m.in_pool()])
	assert_int(id).is_greater(0)
	assert_int(_staff().count(CLEANER)).is_equal(1)
	assert_bool(m.in_pool()).is_true()
	assert_array(_staff().stations_of(CLEANER)).is_empty()
	var mess := _messes().add(MessSim.Kind.LITTER, Vector2i(10, 10))
	_world.step()
	var door := _world.sim.layout.door_cell(_world.grid, _world.sim.layout.entrances[0])
	print("job %d of mess %d, from %s (door %s)" % [m.job, mess, m.path[0], door])
	assert_int(m.job).is_equal(mess)
	assert_int(int(_messes().get_mess(mess)["claimed_by"])).is_equal(id)
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_that(m.path[0]).is_equal(door)
	assert_bool(_staff().fire(CLEANER)).is_true()
	print(
		(
			"fired: count %d, state %d, claim %d"
			% [_staff().count(CLEANER), m.state, int(_messes().get_mess(mess)["claimed_by"])]
		)
	)
	assert_int(_staff().count(CLEANER)).is_equal(0)
	assert_int(int(_messes().get_mess(mess)["claimed_by"])).is_equal(0)


func test_two_cleaners_never_hold_the_same_job() -> void:
	var a := CleanerTestKit.cleaner_at(_world, Vector2i(15, 10))
	var b := CleanerTestKit.cleaner_at(_world, Vector2i(15, 10))
	var first := _messes().add(MessSim.Kind.LITTER, Vector2i(20, 10))
	_world.step()
	print("one mess: jobs %d and %d, b failed %s" % [a.job, b.job, b.search_failed])
	assert_int(a.job).is_equal(first)
	assert_int(b.job).is_equal(0)
	assert_bool(b.search_failed).is_true()
	var second := _messes().add(MessSim.Kind.SPILL, Vector2i(18, 12))
	var third := _messes().add(MessSim.Kind.TOILET, Vector2i(21, 11))
	var c := CleanerTestKit.cleaner_at(_world, Vector2i(19, 11))
	# Lambdas capture locals by value: count in a dictionary.
	var seen := {"shared": 0, "checks": 0}
	var held := {}
	var cleaned := func() -> bool:
		var jobs := {}
		for m: StaffMember in [a, b, c]:
			if m.job != 0:
				seen["shared"] += int(jobs.has(m.job))
				jobs[m.job] = true
				held[m.job] = true
		seen["checks"] += 1
		return _messes().mess_count() == 0
	assert_bool(CleanerTestKit.step_until(_world, cleaned)).is_true()
	print(
		(
			"jobs held %s, shared %d over %d ticks, left %d"
			% [held.keys(), seen["shared"], seen["checks"], _messes().mess_count()]
		)
	)
	assert_int(seen["shared"]).is_equal(0)
	assert_int(seen["checks"]).is_greater(1)
	assert_bool(held.has(second) and held.has(third)).is_true()


func test_the_nearest_job_is_the_shortest_staff_path_not_the_straight_line() -> void:
	# A wall from x 5 to 25 between rows 7 and 8: the mess above it is 4 cells
	# away in a line but a long walk round; the other is 6 away in the open.
	for x in range(5, 26):
		var cell := Vector2i(x, 8)
		_edit(
			BuildEdit.place_wall(cell, BuildGrid.Side.NORTH),
			BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)
		)
	var behind := _messes().add(MessSim.Kind.LITTER, Vector2i(15, 6))
	var open := _messes().add(MessSim.Kind.LITTER, Vector2i(21, 14))
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(15, 10))
	_world.step()
	var to_behind := _world.grid.find_staff_path(Vector2i(15, 10), Vector2i(15, 6))
	var to_open := _world.grid.find_staff_path(Vector2i(15, 10), Vector2i(21, 14))
	print(
		(
			"job %d (behind %d, open %d); path mm behind %d, open %d"
			% [m.job, behind, open, Passenger.path_mm(to_behind), Passenger.path_mm(to_open)]
		)
	)
	assert_int(Passenger.path_mm(to_behind)).is_greater(Passenger.path_mm(to_open))
	assert_int(m.job).is_equal(open)


func test_cleaning_removes_the_mess_and_the_mood_it_cost() -> void:
	var spot := Vector2i(20, 10)
	var mess := _messes().add(MessSim.Kind.LITTER, spot)
	var watch := Vector2i(20, 12)
	var guest := MessTestKit.guest(_world, watch)
	MessTestKit.run_beats(_world, guest, 3)
	var lost := MessTestKit.START_MOOD - guest.mood
	var dirt := _messes().dirt_at(watch)
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(17, 10))
	var on_duty := {"tick": -1}
	var done := func() -> bool:
		if on_duty["tick"] < 0 and m.state == StaffMember.State.ON_DUTY:
			on_duty["tick"] = _world.clock.tick
		return _messes().mess_count() == 0
	assert_bool(CleanerTestKit.step_until(_world, done)).is_true()
	var took: int = _world.clock.tick - on_duty["tick"]
	guest.mood = MessTestKit.START_MOOD
	MessTestKit.run_beats(_world, guest, 3)
	print(
		(
			"before: dirt %d, mood lost %d; cleaned in %d ticks on duty; after: dirt %d, mood %d"
			% [dirt, lost, took, _messes().dirt_at(watch), guest.mood]
		)
	)
	assert_int(dirt).is_greater(0)
	assert_int(lost).is_greater(0)
	assert_int(took).is_equal(CleanerJobs.CLEAN_TICKS[MessSim.Kind.LITTER])
	assert_dict(_messes().get_mess(mess)).is_empty()
	assert_int(_messes().dirt_at(watch)).is_equal(0)
	assert_int(guest.mood).is_equal(MessTestKit.START_MOOD)
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.job).is_equal(0)


func test_emptying_a_full_bin_lets_it_take_litter_again() -> void:
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(20, 5), 0)
	_undo.append(BuildEdit.remove_object(bin))
	var spot := Vector2i(20, 7)
	for i in MessSim.BIN_CAPACITY:
		MessTestKit.litter(_world, spot)
	var full_before := _messes().fill_of(bin)
	var taker_before := _messes().bin_for(spot)
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(20, 10))
	_world.step()
	var claimed := CleanerJobs.bin_holder(_staff(), bin)
	var on_duty := {"tick": -1}
	var done := func() -> bool:
		if on_duty["tick"] < 0 and m.state == StaffMember.State.ON_DUTY:
			on_duty["tick"] = _world.clock.tick
		return _messes().fill_of(bin) == 0
	assert_bool(CleanerTestKit.step_until(_world, done)).is_true()
	var took: int = _world.clock.tick - on_duty["tick"]
	var taker_after := _messes().bin_for(spot)
	MessTestKit.litter(_world, spot)
	print(
		(
			(
				"fill %d (full bins %s), taker %d; claimed by %d (cleaner %d); emptied in %d;"
				+ " taker %d, fill after one more litter %d, messes %d"
			)
			% [
				full_before,
				_messes().full_bins(),
				taker_before,
				claimed,
				m.id,
				took,
				taker_after,
				_messes().fill_of(bin),
				_messes().mess_count()
			]
		)
	)
	assert_int(full_before).is_equal(MessSim.BIN_CAPACITY)
	assert_int(taker_before).is_equal(0)
	assert_int(claimed).is_equal(m.id)
	assert_int(took).is_equal(CleanerJobs.EMPTY_TICKS)
	assert_int(taker_after).is_equal(bin)
	assert_int(_messes().fill_of(bin)).is_equal(1)
	assert_int(_messes().mess_count()).is_equal(0)
	assert_int(CleanerJobs.bin_holder(_staff(), bin)).is_equal(0)


## StaffPosts plays a step on a copy of the staff for a helper forecast; the
## copy shares the live MessSim, so its cleaners must change no mess or claim.
func test_a_forecast_copy_of_the_staff_changes_no_mess_or_claim() -> void:
	var near := _messes().add(MessSim.Kind.LITTER, Vector2i(20, 10))
	_messes().add(MessSim.Kind.LITTER, Vector2i(25, 15))
	var a := CleanerTestKit.cleaner_at(_world, Vector2i(19, 10))
	CleanerTestKit.cleaner_at(_world, Vector2i(5, 5))
	var working := func() -> bool: return a.state == StaffMember.State.ON_DUTY and a.work_left == 1
	assert_bool(CleanerTestKit.step_until(_world, working)).is_true()
	# The copy's next step would finish the near mess and send its cleaner on.
	var before := MessTestKit.text_of(_messes().to_snapshot())
	var copy := StaffSim.new()
	copy.sim = _world.sim
	copy.forecast = true
	assert_bool(copy.from_snapshot(_staff().to_snapshot())).is_true()
	for i in 3:
		copy.step()
	var copy_state := copy.get_member(a.id).state
	var after := MessTestKit.text_of(_messes().to_snapshot())
	copy.free()
	_world.step()
	print(
		(
			"copy left the messes alone %s (copy's cleaner state %d); live step cleaned %s"
			% [before == after, copy_state, _messes().get_mess(near).is_empty()]
		)
	)
	assert_str(after).is_equal(before)
	assert_bool(_messes().get_mess(near).is_empty()).is_true()


func test_a_cleaner_fired_at_work_lets_go_of_its_claim_and_another_takes_it() -> void:
	var mess := _messes().add(MessSim.Kind.SPILL, Vector2i(20, 10))
	var a := CleanerTestKit.cleaner_at(_world, Vector2i(18, 10))
	var working := func() -> bool: return a.state == StaffMember.State.ON_DUTY
	assert_bool(CleanerTestKit.step_until(_world, working)).is_true()
	var before := int(_messes().get_mess(mess)["claimed_by"])
	assert_bool(_staff().fire(CLEANER)).is_true()
	var after := int(_messes().get_mess(mess)["claimed_by"])
	print("claim %d -> %d, state %d, job %d" % [before, after, a.state, a.job])
	assert_int(before).is_equal(a.id)
	assert_int(after).is_equal(0)
	assert_int(a.state).is_equal(StaffMember.State.WALKING_OUT)
	assert_int(a.job).is_equal(0)
	assert_int(_staff().count(CLEANER)).is_equal(0)
	var b := CleanerTestKit.cleaner_at(_world, Vector2i(10, 10))
	_world.step()
	print("the new cleaner %d holds %d" % [b.id, b.job])
	assert_int(b.job).is_equal(mess)
	(
		assert_bool(
			CleanerTestKit.step_until(_world, func() -> bool: return _messes().mess_count() == 0)
		)
		. is_true()
	)
