class_name TestCleanerSave
extends GdUnitTestSuite
## Cleaners are saved (staff save version 4): a save taken while one cleaner
## cleans and another walks to its job loads back through JSON and plays on
## exactly like the run that never stopped, and a save whose jobs and mess
## claims do not agree is refused.

const SEED := 7
const BIN_AT := Vector2i(25, 3)
## Played on after the load: CHECKS times CHUNK ticks, compared after each.
const CHECKS := 28
const CHUNK := 25

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _bin := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


## The mess tests' open world with a bin, built the same way every time.
func _world() -> PassengerTestWorld:
	var world := MessTestKit.open_world(SEED)
	_bin = PassengerTestWorld.place(world.grid, MessSim.BIN_ID, BIN_AT, 0)
	world.step()
	return world


## Four messes, a full bin and three cleaners: one beside a mess, one below
## the bin, one in the pool. Steps until a cleaner is at work and another is
## partway through a step of its walk; [the one at work, the walker].
func _mid_run(world: PassengerTestWorld) -> Array:
	var messes := world.sim.messes
	var data := messes.to_snapshot()
	data["bins"][str(_bin)] = MessSim.BIN_CAPACITY
	assert_bool(messes.from_snapshot(data)).is_true()
	messes.add(MessSim.Kind.LITTER, Vector2i(8, 12))
	messes.add(MessSim.Kind.SPILL, Vector2i(24, 15))
	messes.add(MessSim.Kind.TOILET, Vector2i(12, 4))
	messes.add(MessSim.Kind.LITTER, Vector2i(28, 18))
	CleanerTestKit.cleaner_at(world, Vector2i(7, 12))
	CleanerTestKit.cleaner_at(world, Vector2i(25, 6))
	CleanerTestKit.cleaner_at(world, StaffMember.NO_CELL)
	var found := []
	var ready := func() -> bool:
		found.clear()
		var working: StaffMember = null
		var walking: StaffMember = null
		for id in world.staff.member_ids():
			var m := world.staff.get_member(id)
			if m.state == StaffMember.State.ON_DUTY:
				working = m
			elif m.state == StaffMember.State.TO_STATION and m.seg_mm > 0 and not m.job_bin:
				walking = m
		if working == null or walking == null:
			return false
		found.append_array([working, walking])
		return true
	assert_bool(CleanerTestKit.step_until(world, ready, 300)).is_true()
	return found


func _text(world: PassengerTestWorld) -> String:
	return (
		MessTestKit.text_of(world.sim.messes.to_snapshot())
		+ MessTestKit.text_of(world.staff.to_snapshot())
	)


func test_a_save_mid_walk_and_mid_clean_plays_on_like_the_unbroken_run() -> void:
	_a = _world()
	var pair := _mid_run(_a)
	var working: StaffMember = pair[0]
	var walking: StaffMember = pair[1]
	# The members play on: what they were at the save, kept now.
	var at_save := [working.id, working.job, working.work_left]
	at_save.append_array([walking.id, walking.job, walking.seg_mm])
	var saved_messes := MessTestKit.through_json(_a.sim.messes.to_snapshot())
	var saved_staff := MessTestKit.through_json(_a.staff.to_snapshot())
	_b = _world()
	_b.run_to(_a.clock.tick)
	var empty_before := _b.staff.member_ids().size()
	assert_bool(_b.sim.messes.from_snapshot(saved_messes)).is_true()
	assert_bool(_b.staff.from_snapshot(saved_staff)).is_true()
	var same_at_load := _text(_a) == _text(_b)
	var messes_before := _a.sim.messes.mess_count()
	var checks := 0
	var differ_at := -1
	for i in CHECKS:
		_a.run_to(_a.clock.tick + CHUNK)
		_b.run_to(_a.clock.tick)
		checks += 1
		if differ_at < 0 and _text(_a) != _text(_b):
			differ_at = _a.clock.tick
	print(
		(
			(
				"saved at work %d (job %d, %d left), walking %d (job %d, %d mm in);"
				+ " b had %d staff; same at load %s; messes %d -> %d, bin fill %d;"
				+ " %d checks, first difference at %d"
			)
			% [
				at_save[0],
				at_save[1],
				at_save[2],
				at_save[3],
				at_save[4],
				at_save[5],
				empty_before,
				same_at_load,
				messes_before,
				_a.sim.messes.mess_count(),
				_a.sim.messes.fill_of(_bin),
				checks,
				differ_at
			]
		)
	)
	assert_int(empty_before).is_equal(0)
	assert_bool(same_at_load).is_true()
	assert_int(at_save[1]).is_greater(0)
	assert_int(at_save[2]).is_greater(0)
	assert_int(at_save[4]).is_greater(0)
	assert_int(at_save[5]).is_greater(0)
	assert_int(messes_before).is_greater(_a.sim.messes.mess_count())
	assert_int(_a.sim.messes.fill_of(_bin)).is_equal(0)
	assert_int(differ_at).is_equal(-1)
	assert_int(checks).is_greater(1)


func test_a_save_whose_jobs_and_claims_disagree_is_refused() -> void:
	_a = _world()
	var pair := _mid_run(_a)
	var working: StaffMember = pair[0]
	var walking: StaffMember = pair[1]
	var good_messes := MessTestKit.through_json(_a.sim.messes.to_snapshot())
	var good_staff := MessTestKit.through_json(_a.staff.to_snapshot())
	var free_mess := -1
	for mess: Dictionary in good_messes["messes"]:
		if int(mess["claimed_by"]) == 0:
			free_mess = int(mess["id"])
	var bin_holder := CleanerJobs.bin_holder(_a.staff, _bin)
	print("free mess %d, bin held by %d" % [free_mess, bin_holder])
	assert_int(free_mess).is_greater(0)
	assert_int(bin_holder).is_greater(0)
	var cases := {
		"a claim naming no cleaner":
		[func(m: Dictionary, _s: Dictionary) -> void: _mess(m, free_mess)["claimed_by"] = 99],
		"a mess job not claimed by its cleaner":
		[func(m: Dictionary, _s: Dictionary) -> void: _mess(m, walking.job)["claimed_by"] = 0],
		"a cleaner at work away from its job":
		[func(_m: Dictionary, s: Dictionary) -> void: _move(_member(s, working.id), 6)],
		"a cleaner at work one cell off its job's spot":
		[func(_m: Dictionary, s: Dictionary) -> void: _move(_member(s, working.id), 1)],
		"more work left than the job takes": [_overworked.bind(working.id)],
		"walking with work left":
		[func(_m: Dictionary, s: Dictionary) -> void: _member(s, walking.id)["work_left"] = 5],
		"a bin job on a bin that is not full":
		[func(m: Dictionary, _s: Dictionary) -> void: m["bins"][str(_bin)] = 3],
		"two cleaners on one bin": [_both_on_the_bin.bind(walking.id)],
		"a cleaner in a version 3 save":
		[func(_m: Dictionary, s: Dictionary) -> void: s["save_version"] = 3],
		"a check-in agent with a job": [_agent_with_a_job],
	}
	var refused := 0
	for name: String in cases:
		var messes: Dictionary = good_messes.duplicate(true)
		var staff: Dictionary = good_staff.duplicate(true)
		(cases[name][0] as Callable).call(messes, staff)
		var state := MessSim.checked(messes, _a.grid)
		var problem := str(state.get("error", ""))
		if problem == "":
			problem = str(StaffSnapshot.load(staff, _a.sim, state).get("error", ""))
		print("%s: refused '%s'" % [name, problem])
		assert_str(problem).override_failure_message(name).is_not_empty()
		refused += int(problem != "")
	assert_int(refused).is_equal(cases.size())
	var good := MessSim.checked(good_messes, _a.grid)
	assert_str(str(StaffSnapshot.load(good_staff, _a.sim, good).get("error", ""))).is_empty()
	var before := _text(_a)
	var bad: Dictionary = good_staff.duplicate(true)
	_member(bad, walking.id)["work_left"] = 5
	assert_bool(_a.staff.from_snapshot(bad)).is_false()
	assert_str(_text(_a)).is_equal(before)


func _mess(messes: Dictionary, id: int) -> Dictionary:
	for mess: Dictionary in messes["messes"]:
		if int(mess["id"]) == id:
			return mess
	return {}


func _member(staff: Dictionary, id: int) -> Dictionary:
	for record: Dictionary in staff["members"]:
		if int(record["id"]) == id:
			return record
	return {}


## Stands the member `cells` cells west of where it is, still on duty.
func _move(record: Dictionary, cells: int) -> void:
	var at: Array = record["at"]
	var cell := [int(at[0]) - cells, int(at[1])]
	record["at"] = cell
	record["path"] = [cell]
	record["path_index"] = 0
	record["seg_mm"] = 0


## Gives the cleaner at work more work left than its job can take: the most
## any job takes (grown toilet mess time, above every litter, spill or bin
## time) plus one.
func _overworked(_messes: Dictionary, staff: Dictionary, worker: int) -> void:
	_member(staff, worker)["work_left"] = CleanerJobs.clean_ticks(MessSim.Kind.TOILET, true) + 1


## The walker gives up its mess and takes the bin the other cleaner holds.
func _both_on_the_bin(messes: Dictionary, staff: Dictionary, walker: int) -> void:
	var record := _member(staff, walker)
	_mess(messes, int(record["job"]))["claimed_by"] = 0
	record["job"] = _bin
	record["job_bin"] = true


## An idle check-in agent in the pool with a job.
func _agent_with_a_job(_messes: Dictionary, staff: Dictionary) -> void:
	var id := int(staff["next_id"])
	staff["next_id"] = id + 1
	(
		staff["members"]
		. append(
			{
				"id": id,
				"role": StaffMember.Role.CHECKIN,
				"state": StaffMember.State.IDLE,
				"station": 0,
				"slot": StaffMember.Slot.PRIMARY,
				"at": [-1, -1],
				"path": [],
				"path_index": 0,
				"seg_mm": 0,
				"needs_replan": false,
				"search_failed": false,
				"leaving": false,
				"backing_out": false,
				"job": 1,
				"job_bin": false,
				"work_left": 0,
			}
		)
	)
