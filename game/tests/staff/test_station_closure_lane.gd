class_name TestStationClosureLane
extends GdUnitTestSuite
## The player closes a security lane mid-flow (StationClosures; decision
## select-placed-items-design-click-order-gold-footprint-highli): the lane is
## one station, it admits nobody new at once, every passenger already admitted
## finishes whatever phase it is in, the helper stays as long as the primary,
## and then both officers go idle where they stand, still on the roster.

const SECURITY := StaffMember.Role.SECURITY
const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const PHASE := SecurityRuntime.Phase

var _w: SecurityTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = SecurityTestWorld.make(true)
	_w.world.auto_staff = false


func after_test() -> void:
	_w.world.free_all()
	_w = null


func test_closing_a_lane_lets_every_admitted_passenger_finish_then_frees_both_officers() -> void:
	var staff := _w.world.staff
	var primary := staff.get_member(StaffTestKit.seat(staff, _w.station, PRIMARY))
	var helper := staff.get_member(StaffTestKit.seat(staff, _w.station, HELPER))
	var ids := _w.send_all([[0, true, false], [2, false, false]])
	var first: int = ids[0]
	var second: int = ids[1]
	var both := func() -> bool:
		return (
			_w.world.passenger(first).security_phase == PHASE.REPACK
			and [PHASE.UNPACK, PHASE.ARCH].has(_w.world.passenger(second).security_phase)
		)
	while not both.call() and _w.world.clock.tick < 3000:
		_w.world.step()
	assert_bool(both.call()).is_true()
	assert_array(_w.runtime_record()["admitted"]).is_equal([first, second])
	var later := _w.send(0)
	assert_bool(staff.closures.set_closed(_w.station, true)).is_true()
	assert_bool(staff.is_open(_w.station)).is_false()
	var primary_spot := staff.spot_of(_w.station)
	var helper_spot := staff.spot_of(_w.station, HELPER)
	var statuses := {}
	while not (_w.cleared.has(first) and _w.cleared.has(second)) and _w.world.clock.tick < 4000:
		_w.world.step()
		if _w.cleared.has(first) and _w.cleared.has(second):
			break
		statuses[staff.closures.status_text(_w.station)] = true
		for m: StaffMember in [primary, helper]:
			assert_int(m.state).override_failure_message("tick %d" % _w.world.clock.tick).is_equal(
				StaffMember.State.ON_DUTY
			)
	print(
		(
			"cleared %s and %s, statuses %s"
			% [_w.cleared.get(first), _w.cleared.get(second), statuses.keys()]
		)
	)
	assert_bool(_w.cleared.has(first) and _w.cleared.has(second)).is_true()
	assert_array(statuses.keys()).is_equal(["Finishing current service"])
	# The closure held past the first clearance, through the second.
	assert_int(int(_w.cleared[first])).is_not_equal(int(_w.cleared[second]))
	_w.world.step()
	print(
		"primary %d at %s, helper %d at %s" % [primary.state, primary.at, helper.state, helper.at]
	)
	assert_int(primary.state).is_equal(StaffMember.State.IDLE)
	assert_int(helper.state).is_equal(StaffMember.State.IDLE)
	assert_that(primary.at).is_equal(primary_spot)
	assert_that(helper.at).is_equal(helper_spot)
	assert_int(staff.staff_at(_w.station)).is_equal(0)
	assert_int(staff.staff_at(_w.station, HELPER)).is_equal(0)
	assert_int(staff.count(SECURITY)).is_equal(2)
	assert_str(staff.closures.status_text(_w.station)).is_equal("Closed by you")
	for i in 200:
		_w.world.step()
	assert_bool(_w.admitted.has(later)).is_false()
	# Nobody is posted to the closed lane: its posts stay empty.
	assert_int(staff.staff_at(_w.station)).is_equal(0)
	assert_int(staff.staff_at(_w.station, HELPER)).is_equal(0)


func test_a_part_of_the_lane_picks_the_lane_and_reopening_staffs_it_again() -> void:
	var staff := _w.world.staff
	var primary := staff.get_member(StaffTestKit.seat(staff, _w.station, PRIMARY))
	var parts: Dictionary = _w.world.sim.layout.security_lanes.lane(_w.station)["parts"]
	var belt: int = parts[SecurityLanes.XRAY_BELT]
	print("arch %d, belt %d -> station %d" % [_w.station, belt, staff.closures.station_of(belt)])
	assert_int(belt).is_not_equal(_w.station)
	assert_int(staff.closures.station_of(belt)).is_equal(_w.station)
	staff.closures.set_closed(_w.station, true)
	_w.world.step()
	assert_int(primary.state).is_equal(StaffMember.State.IDLE)
	staff.closures.set_closed(_w.station, false)
	var on_duty := false
	for i in 400:
		_w.world.step()
		if staff.is_open(_w.station):
			on_duty = true
			break
	print("reopened lane open %s, primary %d" % [on_duty, staff.staff_at(_w.station)])
	assert_bool(on_duty).is_true()
	assert_int(staff.staff_at(_w.station)).is_equal(primary.id)
