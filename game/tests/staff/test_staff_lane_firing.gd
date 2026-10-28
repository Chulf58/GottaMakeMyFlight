class_name TestStaffLaneFiring
extends GdUnitTestSuite
## Firing at a security lane. The firing contract covers every passenger the
## lane has admitted (decision security-lane-technical-design-one-station-per-
## lane-with-int, point 5): a primary fired mid-admission stays on duty,
## leaving, until the last admitted passenger is cleared, whatever phase it is
## in (repack and return included), and the lane admits nobody new meanwhile.
## Firing lets a helper go before a primary, so the lane stays open.

const SECURITY := StaffMember.Role.SECURITY
const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const PHASE := SecurityRuntime.Phase

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


func test_a_primary_fired_mid_admission_stays_until_every_admitted_passenger_clears() -> void:
	var w := _lane()
	var officer := StaffTestKit.seat(w.world.staff, w.station, PRIMARY)
	var first := w.send(1, true)
	while not w.admitted.has(first) and w.world.clock.tick < 2000:
		w.world.step()
	assert_bool(w.admitted.has(first)).is_true()
	var later := w.send(0)
	assert_bool(w.world.staff.fire(SECURITY)).is_true()
	var m := w.world.staff.get_member(officer)
	assert_bool(m.leaving).is_true()
	assert_bool(w.world.staff.is_open(w.station)).is_false()
	var phases := {}
	while not w.cleared.has(first) and w.world.clock.tick < 3000:
		w.world.step()
		if w.cleared.has(first):
			break
		phases[w.world.passenger(first).security_phase] = true
		assert_int(m.state).override_failure_message("tick %d" % w.world.clock.tick).is_equal(
			StaffMember.State.ON_DUTY
		)
		assert_bool(m.leaving).is_true()
	print("phases held through: %s, cleared at %s" % [phases.keys(), w.cleared.get(first)])
	assert_bool(w.cleared.has(first)).is_true()
	# The firing held through the repack and the walk back, not only the scan.
	assert_bool(phases.has(PHASE.REPACK)).is_true()
	assert_bool(phases.has(PHASE.RETURN)).is_true()
	w.world.step()
	var gone := w.world.staff.get_member(officer)
	assert_bool(gone == null or gone.state == StaffMember.State.WALKING_OUT).is_true()
	assert_int(w.world.staff.count(SECURITY)).is_equal(0)
	# Nobody new was admitted while the officer was leaving, or after.
	for i in 100:
		w.world.step()
	assert_bool(w.admitted.has(later)).is_false()


func test_firing_lets_a_helper_go_before_the_primary() -> void:
	var w := _lane()
	# The primary has the higher id: by id alone (the highest on duty goes
	# first) it would be the one let go, closing the lane.
	var helper := StaffTestKit.seat(w.world.staff, w.station, HELPER)
	var primary := StaffTestKit.seat(w.world.staff, w.station, PRIMARY)
	assert_int(primary).is_greater(helper)
	assert_bool(w.world.staff.fire(SECURITY)).is_true()
	print(
		(
			"primary state %d, helper state %d"
			% [
				w.world.staff.get_member(primary).state,
				w.world.staff.get_member(helper).state,
			]
		)
	)
	assert_int(w.world.staff.get_member(helper).state).is_equal(StaffMember.State.WALKING_OUT)
	assert_int(w.world.staff.get_member(primary).state).is_equal(StaffMember.State.ON_DUTY)
	assert_bool(w.world.staff.is_open(w.station)).is_true()
	assert_int(w.world.staff.staff_at(w.station, HELPER)).is_equal(0)
	assert_int(w.world.staff.count(SECURITY)).is_equal(1)
