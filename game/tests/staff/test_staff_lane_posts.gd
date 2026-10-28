class_name TestStaffLanePosts
extends GdUnitTestSuite
## The station-wide staffing pass (StaffPosts; decision security-lane-
## technical-design-one-station-per-lane-with-int, point 5; ruling security-
## lane-staffing-one-officer-opens-a-lane-and-a-second), one case per step:
## primaries stay, an on-duty helper is promoted where the primary left, idle
## officers fill primary vacancies, a vacancy left open recalls the nearest
## helper, and spare officers become helpers. Ties go to the lower id, a
## vacancy no entrance reaches never recalls a helper, and a helper never
## leaves a station closed.

const SECURITY := StaffMember.Role.SECURITY
const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## SecurityTestWorld's one-lane grid, no automatic staffing; returns the arch.
func _one_lane() -> int:
	_w = PassengerTestWorld.make(SecurityTestWorld.build_grid(true), FlightSim.schedule_starts(0))
	_w.auto_staff = false
	return _w.sim.layout.scanners[0]


## Steps `ticks` ticks, checking after each that no helper stands beside a
## vacancy; returns the first breach, or "".
func _run_checked(ticks: int) -> String:
	for i in ticks:
		_w.step()
		var breach := LaneStaffWorld.helper_beside_vacancy(_w.staff)
		if breach != "":
			return "tick %d: %s" % [_w.clock.tick, breach]
	return ""


func test_an_idle_officer_takes_the_primary_post_and_opens_the_lane() -> void:
	var arch := _one_lane()
	var lane := LaneStaffWorld.lane_of(_w, arch)
	var id := _w.staff.hire(SECURITY)
	assert_bool(LaneStaffWorld.until_on_duty(_w, id)).is_true()
	var m := _w.staff.get_member(id)
	print("officer at %s, primary spot %s, tick %d" % [m.at, lane["primary_spot"], _w.clock.tick])
	assert_int(m.slot).is_equal(PRIMARY)
	assert_int(m.station).is_equal(arch)
	assert_that(m.at).is_equal(lane["primary_spot"])
	assert_bool(_w.staff.is_open(arch)).is_true()
	assert_bool(_w.staff.is_staffed(arch, HELPER)).is_false()


func test_a_spare_officer_becomes_the_helper_and_the_primary_stays() -> void:
	var arch := _one_lane()
	var lane := LaneStaffWorld.lane_of(_w, arch)
	var first := _w.staff.hire(SECURITY)
	assert_bool(LaneStaffWorld.until_on_duty(_w, first)).is_true()
	var changes: Array[int] = []
	_w.staff.member_state_changed.connect(
		func(id: int, _state: StaffMember.State) -> void:
			if id == first:
				changes.append(id)
	)
	var second := _w.staff.hire(SECURITY)
	assert_bool(LaneStaffWorld.until_on_duty(_w, second)).is_true()
	var helper := _w.staff.get_member(second)
	print("helper %d at %s, helper spot %s" % [second, helper.at, lane["helper_spot"]])
	assert_int(helper.slot).is_equal(HELPER)
	assert_that(helper.at).is_equal(lane["helper_spot"])
	assert_int(_w.staff.staff_at(arch, HELPER)).is_equal(second)
	assert_bool(_w.staff.is_staffed(arch, HELPER)).is_true()
	# The primary was kept: same member, on duty all along.
	assert_int(_w.staff.staff_at(arch)).is_equal(first)
	assert_array(changes).is_empty()
	assert_bool(_w.staff.is_open(arch)).is_true()


func test_an_on_duty_helper_is_promoted_where_the_primary_left() -> void:
	var arch := _one_lane()
	var lane := LaneStaffWorld.lane_of(_w, arch)
	# A helper on duty with no primary: the state a primary leaving behind a
	# helper on duty leaves for the next step.
	var id := StaffTestKit.seat(_w.staff, arch, HELPER)
	assert_bool(_w.staff.is_open(arch)).is_false()
	_w.step()
	var m := _w.staff.get_member(id)
	print("after one step: slot %d state %d at %s" % [m.slot, m.state, m.at])
	assert_int(m.slot).is_equal(PRIMARY)
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(_w.staff.staff_at(arch)).is_equal(id)
	assert_int(_w.staff.staff_at(arch, HELPER)).is_equal(0)
	assert_bool(LaneStaffWorld.until_on_duty(_w, id)).is_true()
	assert_that(m.at).is_equal(lane["primary_spot"])
	assert_bool(_w.staff.is_open(arch)).is_true()


func test_a_new_vacancy_recalls_the_helper_and_no_station_stays_closed() -> void:
	var arch := _one_lane()
	var primary := StaffTestKit.seat(_w.staff, arch, PRIMARY)
	var helper := StaffTestKit.seat(_w.staff, arch, HELPER)
	_w.step()
	assert_bool(_w.staff.is_staffed(arch, HELPER)).is_true()
	# A basic scanner nobody works: a new primary vacancy, and no idle officer.
	var scanner := PassengerTestWorld.place(_w.grid, &"security_scanner", Vector2i(9, 9), 0)
	assert_bool(_w.sim.layout.scanners.has(scanner)).is_true()
	var breach := _run_checked(1)
	var m := _w.staff.get_member(helper)
	print("recalled: station %d slot %d state %d" % [m.station, m.slot, m.state])
	assert_str(breach).is_empty()
	assert_int(m.station).is_equal(scanner)
	assert_int(m.slot).is_equal(PRIMARY)
	assert_int(_w.staff.staff_at(arch, HELPER)).is_equal(0)
	assert_bool(LaneStaffWorld.until_on_duty(_w, helper)).is_true()
	assert_bool(_w.staff.is_open(scanner)).is_true()
	assert_bool(_w.staff.is_open(arch)).is_true()
	assert_int(_w.staff.staff_at(arch)).is_equal(primary)
	# A third officer now has no vacancy and becomes the lane's helper.
	var third := _w.staff.hire(SECURITY)
	assert_bool(LaneStaffWorld.until_on_duty(_w, third)).is_true()
	assert_int(_w.staff.staff_at(arch, HELPER)).is_equal(third)
	assert_str(_run_checked(20)).is_empty()


func test_the_nearest_helper_is_recalled() -> void:
	var made := LaneStaffWorld.two_lanes()
	_w = PassengerTestWorld.make(made[0], FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var a: int = made[1]
	var b: int = made[2]
	StaffTestKit.seat(_w.staff, a, PRIMARY)
	StaffTestKit.seat(_w.staff, b, PRIMARY)
	var near_a := StaffTestKit.seat(_w.staff, a, HELPER)
	var near_b := StaffTestKit.seat(_w.staff, b, HELPER)
	_w.step()
	# A scanner close to lane B's helper spot (17, 4), far from lane A's (3, 4).
	var scanner := PassengerTestWorld.place(_w.grid, &"security_scanner", Vector2i(18, 1), 0)
	assert_bool(_w.sim.layout.scanners.has(scanner)).is_true()
	assert_str(_run_checked(1)).is_empty()
	print(
		(
			"helper of A at %d, of B at %d"
			% [_w.staff.staff_at(a, HELPER), _w.staff.staff_at(b, HELPER)]
		)
	)
	assert_int(_w.staff.get_member(near_b).station).is_equal(scanner)
	assert_int(_w.staff.staff_at(a, HELPER)).is_equal(near_a)
	assert_int(_w.staff.staff_at(b, HELPER)).is_equal(0)


func test_a_spare_officer_ties_to_the_lower_arch_id() -> void:
	var made := LaneStaffWorld.two_lanes()
	_w = PassengerTestWorld.make(made[0], FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var a: int = made[1]
	var b: int = made[2]
	assert_int(a).is_less(b)
	StaffTestKit.seat(_w.staff, a, PRIMARY)
	StaffTestKit.seat(_w.staff, b, PRIMARY)
	var spare := _w.staff.hire(SECURITY)
	# The two helper spots are mirror images about the entrance's column.
	var door := LaneStaffWorld.ENTRANCE
	var to_a := _w.grid.find_path(door, _w.staff.spot_of(a, HELPER))
	var to_b := _w.grid.find_path(door, _w.staff.spot_of(b, HELPER))
	print("mm to A %d, to B %d" % [Passenger.path_mm(to_a), Passenger.path_mm(to_b)])
	assert_int(Passenger.path_mm(to_a)).is_equal(Passenger.path_mm(to_b))
	_w.step()
	assert_int(_w.staff.staff_at(a, HELPER)).is_equal(spare)
	assert_int(_w.staff.staff_at(b, HELPER)).is_equal(0)


func test_an_unreachable_vacancy_never_recalls_a_helper() -> void:
	var made := LaneStaffWorld.two_lanes()
	var grid: BuildGrid = made[0]
	var b: int = made[2]
	LaneStaffWorld.pocket_primary_spot(grid, SecurityLaneBuilder.recognise(grid).lane(b))
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var a: int = made[1]
	assert_bool(_w.sim.layout.security_lanes.is_complete(b)).is_true()
	assert_bool(_w.staff.spot_unreachable(b)).is_true()
	StaffTestKit.seat(_w.staff, a, PRIMARY)
	var helper := StaffTestKit.seat(_w.staff, a, HELPER)
	for i in 100:
		_w.step()
		var m := _w.staff.get_member(helper)
		assert_int(m.slot).override_failure_message("tick %d" % _w.clock.tick).is_equal(HELPER)
		assert_int(m.station).is_equal(a)
	print(
		(
			"lane B closed: %s, reason '%s'"
			% [not _w.staff.is_open(b), MissSignals.closed_reason(_w.sim, b)]
		)
	)
	assert_bool(_w.staff.is_open(b)).is_false()
	assert_int(_w.staff.staff_at(b)).is_equal(0)
	assert_str(MissSignals.closed_reason(_w.sim, b)).is_equal(MissSignals.UNREACHABLE_REASON)
	# Control: the same layout without the pocket recalls the helper.
	_w.free_all()
	made = LaneStaffWorld.two_lanes()
	_w = PassengerTestWorld.make(made[0], FlightSim.schedule_starts(0))
	_w.auto_staff = false
	StaffTestKit.seat(_w.staff, made[1], PRIMARY)
	var control := StaffTestKit.seat(_w.staff, made[1], HELPER)
	_w.step()
	assert_int(_w.staff.get_member(control).station).is_equal(made[2])
	assert_int(_w.staff.get_member(control).slot).is_equal(PRIMARY)
