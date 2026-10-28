class_name TestSecurityHelperPending
extends GdUnitTestSuite
## A forecast taken between a build edit and the next tick agrees with the
## runtime about a lane's helper (decision
## security-lane-staffing-as-built-helper-doubles-repack-speed, point 6):
## a walking helper whose path the edit touched replans on the next step and
## still arrives, and an on-duty helper the next staff pass recalls to a new
## primary vacancy stops helping on that tick. StaffPosts.helper_from() reads
## both from the pending pass, and the replayed clearance equals the measured
## one.

const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const REPACK := SecurityRuntime.Phase.REPACK

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A lane with its primary seated and no automatic staffing, and one
## passenger with liquids already in REPACK; returns [world, passenger id].
func _repacking() -> Array:
	var w := SecurityTestWorld.make(true)
	w.world.auto_staff = false
	_worlds.append(w)
	StaffTestKit.seat(w.world.staff, w.station, PRIMARY)
	var id := w.send(0, true)
	var stop := w.world.clock.tick + 2000
	while w.world.passenger(id).security_phase != REPACK and w.world.clock.tick < stop:
		w.world.step()
	assert_int(w.world.passenger(id).security_phase).is_equal(REPACK)
	return [w, id]


func test_a_helper_replanning_round_an_edit_still_counts() -> void:
	var setup := _repacking()
	var w: SecurityTestWorld = setup[0]
	var id: int = setup[1]
	var staff := w.world.staff
	var helper := StaffTestKit.send_helper(staff, w.station, Vector2i(1, 4))
	var m := staff.get_member(helper)
	var cut: Vector2i = m.path[1]
	var result := w.world.grid.apply(BuildEdit.remove_floor(cut))
	print("helper path %s, floor removed at %s: %s" % [m.path, cut, result.reason_text()])
	assert_bool(result.ok).is_true()
	# The edit touched the path: the helper plans again on its next step.
	assert_bool(m.needs_replan).is_true()
	var now := w.world.clock.tick
	var from := StaffPosts.helper_from(staff, w.station)
	var eta := SecurityForecast.eta(w.world.sim, w.world.passenger(id))
	var arrived := -1
	while not w.cleared.has(id) and w.world.clock.tick < now + 2000:
		w.world.step()
		if arrived < 0 and staff.is_staffed(w.station, HELPER):
			arrived = w.world.clock.tick
	print(
		(
			"forecast taken at %d: helper from %d, on duty at %d; forecast %d, measured %d"
			% [now, from, arrived, eta, int(w.cleared.get(id, -1)) - now]
		)
	)
	# The helper came round the gap and arrived while the repack ran.
	assert_int(arrived).is_greater(now)
	assert_int(arrived - now).is_less(SecurityRuntime.REPACK_TICKS)
	assert_int(from).is_equal(arrived)
	assert_bool(w.cleared.has(id)).is_true()
	assert_int(int(w.cleared[id]) - now).is_equal(eta)


func test_a_helper_the_next_pass_recalls_no_longer_counts() -> void:
	var setup := _repacking()
	var w: SecurityTestWorld = setup[0]
	var id: int = setup[1]
	var staff := w.world.staff
	StaffTestKit.seat(staff, w.station, HELPER)
	# A few helped ticks, then a scanner built between ticks: a primary
	# vacancy the next pass fills by recalling the helper.
	for i in 5:
		w.world.step()
	var scanner := PassengerTestWorld.place(w.world.grid, &"security_scanner", Vector2i(9, 10), 0)
	assert_bool(StaffPosts.is_vacant(staff, scanner, PRIMARY)).is_true()
	assert_bool(staff.is_staffed(w.station, HELPER)).is_true()
	var now := w.world.clock.tick
	var from := StaffPosts.helper_from(staff, w.station)
	var eta := SecurityForecast.eta(w.world.sim, w.world.passenger(id))
	w.world.step()
	var recalled := staff.staff_at(scanner) != 0 and not staff.is_staffed(w.station, HELPER)
	assert_bool(w.run_until_cleared([id])).is_true()
	print(
		(
			"forecast taken at %d: helper from %d, recalled next tick %s; forecast %d, measured %d"
			% [now, from, recalled, eta, int(w.cleared[id]) - now]
		)
	)
	assert_bool(recalled).is_true()
	assert_int(from).is_equal(-1)
	assert_int(int(w.cleared[id]) - now).is_equal(eta)
