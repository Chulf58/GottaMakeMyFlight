class_name TestSecurityHelperPendingCost
extends GdUnitTestSuite
## The helper forecast copies the staff only when the next StaffSim step can
## change the lane's helper post (StaffPosts._pass_pending). Two cases the
## next step cannot change cost no copy: a leaving primary still serving a
## passenger (the step cannot release it yet), and an idle officer whose last
## search failed, off its beat (the pass skips it). Each has a control whose
## next step does change the post, which still copies and still reads right.

const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const SECURITY := StaffMember.Role.SECURITY

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _lane() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	w.world.auto_staff = false
	_worlds.append(w)
	return w


## Forecasts the helper of `w`'s lane `times` times and returns [copies, last].
func _forecast(w: SecurityTestWorld, times: int) -> Array:
	var before := StaffPosts.next_step_copies
	var from := -2
	for i in times:
		from = StaffPosts.helper_from(w.world.staff, w.station)
	return [StaffPosts.next_step_copies - before, from]


## A lane whose primary is leaving mid-service with a helper on duty beside it:
## the primary is seated, a passenger is being screened, the primary is fired
## (it has to finish first), and a helper is seated after. Returns the world.
func _leaving_primary_in_service() -> SecurityTestWorld:
	var w := _lane()
	var staff := w.world.staff
	var primary := staff.get_member(StaffTestKit.seat(staff, w.station, PRIMARY))
	var id := w.send(0)
	var stop := w.world.clock.tick + 2000
	while not StaffPosts.in_service(w.world.sim, w.station) and w.world.clock.tick < stop:
		w.world.step()
	assert_bool(StaffPosts.in_service(w.world.sim, w.station)).is_true()
	assert_bool(staff.fire(SECURITY)).is_true()
	assert_bool(primary.leaving).is_true()
	assert_int(primary.state).is_equal(StaffMember.State.ON_DUTY)
	StaffTestKit.seat(staff, w.station, HELPER)
	assert_bool(w.world.passenger(id).stage == Passenger.Stage.SECURITY).is_true()
	return w


func test_a_helper_beside_a_leaving_primary_still_in_service_costs_no_copy() -> void:
	var w := _leaving_primary_in_service()
	var now := w.world.clock.tick
	var result := _forecast(w, 5)
	print(
		(
			"leaving primary in service: %d copies, helper from %d (tick %d)"
			% [result[0], result[1], now]
		)
	)
	assert_int(result[0]).is_equal(0)
	# The helper stays on duty through the next step, as the plain read says.
	assert_int(result[1]).is_equal(now)
	w.world.step()
	assert_bool(w.world.staff.is_staffed(w.station, HELPER)).is_true()


func test_a_leaving_primary_whose_service_ended_still_copies_and_reads_right() -> void:
	var w := _leaving_primary_in_service()
	var staff := w.world.staff
	var primary_id := staff.staff_at(w.station)
	var stop := w.world.clock.tick + 3000
	while StaffPosts.in_service(w.world.sim, w.station) and w.world.clock.tick < stop:
		w.world.step()
	assert_bool(StaffPosts.in_service(w.world.sim, w.station)).is_false()
	var primary := staff.get_member(primary_id)
	# The service ended on the last tick: the primary has not left yet.
	assert_bool(primary.leaving and primary.state == StaffMember.State.ON_DUTY).is_true()
	var result := _forecast(w, 1)
	print("leaving primary, service ended: %d copies, helper from %d" % [result[0], result[1]])
	assert_int(result[0]).is_equal(1)
	# The next step sends the primary out and the helper walks over to take its post.
	w.world.step()
	assert_int(staff.staff_at(w.station, HELPER)).is_equal(0)
	assert_int(result[1]).is_equal(-1)


## A lane with its primary on duty and a vacant helper post, and one idle
## officer in the pool whose last search failed. Returns [world, officer].
func _failed_searcher() -> Array:
	var w := _lane()
	var staff := w.world.staff
	StaffTestKit.seat(staff, w.station, PRIMARY)
	var officer := staff.get_member(staff.hire(SECURITY))
	officer.search_failed = true
	assert_bool(StaffPosts.is_vacant(staff, w.station, HELPER)).is_true()
	return [w, officer]


## Steps until the next step is on `officer`'s beat (or off it).
func _until_beat(w: SecurityTestWorld, officer: StaffMember, on_beat: bool) -> void:
	var beat := PassengerSim.BEAT_TICKS
	for i in beat:
		var next_on_beat := posmod(w.world.sim.tick + 1, beat) == posmod(officer.id, beat)
		if next_on_beat == on_beat:
			return
		w.world.step()
	assert_bool(false).override_failure_message("no such tick within one beat").is_true()


func test_an_idle_officer_off_its_beat_after_a_failed_search_costs_no_copy() -> void:
	var setup := _failed_searcher()
	var w: SecurityTestWorld = setup[0]
	var officer: StaffMember = setup[1]
	_until_beat(w, officer, false)
	var result := _forecast(w, 5)
	print("failed searcher off beat: %d copies, helper from %d" % [result[0], result[1]])
	assert_int(result[0]).is_equal(0)
	assert_int(result[1]).is_equal(-1)
	# The pass skips it: no helper post taken on the step.
	w.world.step()
	assert_int(w.world.staff.staff_at(w.station, HELPER)).is_equal(0)


func test_an_idle_officer_on_its_beat_after_a_failed_search_still_copies_and_reads_right() -> void:
	var setup := _failed_searcher()
	var w: SecurityTestWorld = setup[0]
	var officer: StaffMember = setup[1]
	_until_beat(w, officer, true)
	var now := w.world.clock.tick
	var result := _forecast(w, 1)
	print(
		"failed searcher on beat: %d copies, helper from %d (tick %d)" % [result[0], result[1], now]
	)
	assert_int(result[0]).is_equal(1)
	# The step sends it to the helper post: it is walking there, due after now.
	assert_int(result[1]).is_greater(now)
	w.world.step()
	assert_int(w.world.staff.staff_at(w.station, HELPER)).is_equal(officer.id)
	var arrived := -1
	while arrived < 0 and w.world.clock.tick < now + 1000:
		if w.world.staff.is_staffed(w.station, HELPER):
			arrived = w.world.clock.tick
		else:
			w.world.step()
	assert_int(arrived).is_equal(result[1])
