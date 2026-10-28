class_name TestRepairPlanLane
extends GdUnitTestSuite
## A security lane as the security leg of the working path (RepairPlan), and
## as what opens the airport (AirportGate). The lane's arch has no StaffSpots
## spot; its primary post is the lane's primary officer spot (StaffPosts).
## A station staff can never work is no working leg: a lane whose officer
## spot no entrance reaches does not count, and an arch with no whole lane
## has no post at all.
##
## The grid is SecurityTestWorld's lane grid (entrance (5, 15), lane rooted
## at (5, 6), exit (5, 0)) with a check-in desk at (1, 13) facing 0, and no
## basic scanner.

const DESK_AT := Vector2i(1, 13)
const PRIMARY := StaffMember.Slot.PRIMARY

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## The lane grid with a desk; with `pocket`, the lane's primary officer spot
## walled into a pocket staff cannot reach.
static func _grid(pocket := false) -> BuildGrid:
	var grid := SecurityTestWorld.build_grid(true)
	PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	if pocket:
		var lanes := SecurityLaneBuilder.recognise(grid)
		LaneStaffWorld.pocket_primary_spot(grid, lanes.lane(lanes.complete_arches()[0]))
	return grid


func test_a_staffable_lane_is_the_security_leg() -> void:
	var grid := _grid()
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var arch: int = layout.security_lanes.complete_arches()[0]
	print("scanners %s, arch %d" % [layout.scanners, arch])
	assert_array(layout.scanners).is_equal([arch])
	assert_bool(StaffPosts.workable(grid, layout, arch, PRIMARY)).is_true()
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_true()


func test_a_lane_whose_officer_spot_staff_cannot_reach_is_no_working_leg() -> void:
	var grid := _grid(true)
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var arch: int = layout.security_lanes.complete_arches()[0]
	assert_array(layout.scanners).is_equal([arch])
	assert_bool(StaffPosts.unreachable(grid, layout, arch, PRIMARY)).is_true()
	var staffed := RepairPlan.has_working_path(grid, layout)
	var walkable := RepairPlan.has_working_path(grid, layout, false)
	print("staffed path %s, walkable path %s" % [staffed, walkable])
	assert_bool(staffed).is_false()
	# Control: passengers could still walk it; only staffing fails.
	assert_bool(walkable).is_true()


func test_an_arch_without_a_whole_lane_has_no_post() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	var skip: Array[StringName] = [SecurityLanes.PICKUP_TABLE]
	var arch: int = SecurityLaneBuilder.build(grid, SecurityTestWorld.ARCH_AT, 0, 1, skip)[
		SecurityLanes.ARCH
	]
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	assert_that(StaffPosts.spot(grid, layout, arch, PRIMARY)).is_equal(BuildObjectDef.NO_CELL)
	assert_bool(StaffPosts.workable(grid, layout, arch, PRIMARY)).is_false()
	# Once whole, the same arch has its post.
	var lane := SecurityLanes.geometry(SecurityTestWorld.ARCH_AT, 0, SecurityLanes.RIGHT)
	PassengerTestWorld.place(grid, SecurityLanes.PICKUP_TABLE, lane["pickup_table"], 0)
	layout.rebuild(grid)
	assert_that(StaffPosts.spot(grid, layout, arch, PRIMARY)).is_equal(lane["primary_spot"])
	assert_bool(StaffPosts.workable(grid, layout, arch, PRIMARY)).is_true()


func test_the_airport_opens_with_only_a_lane_staffed() -> void:
	_w = PassengerTestWorld.make(_grid(), FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(_w.flights, _w.staff)
	var arch: int = _w.sim.layout.scanners[0]
	assert_bool(_w.sim.layout.security_lanes.is_complete(arch)).is_true()
	assert_int(gate.blocker()).is_equal(AirportGate.Blocker.NO_CHECKIN)
	var agent := _w.staff.hire(StaffMember.Role.CHECKIN)
	var officer := _w.staff.hire(StaffMember.Role.SECURITY)
	assert_bool(LaneStaffWorld.until_on_duty(_w, agent)).is_true()
	assert_bool(LaneStaffWorld.until_on_duty(_w, officer)).is_true()
	print("officer on duty at %s by tick %d" % [_w.staff.get_member(officer).at, _w.clock.tick])
	assert_int(_w.staff.staff_at(arch)).is_equal(officer)
	assert_bool(_w.staff.is_open(arch)).is_true()
	assert_int(gate.blocker()).is_equal(AirportGate.Blocker.NONE)
	_w.step()
	assert_bool(gate.is_open()).is_true()


func test_a_lane_staff_cannot_reach_keeps_the_airport_closed_on_the_staff_spot() -> void:
	_w = PassengerTestWorld.make(_grid(true), FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(_w.flights, _w.staff)
	_w.staff.hire(StaffMember.Role.CHECKIN)
	_w.staff.hire(StaffMember.Role.SECURITY)
	_w.run_to(_w.clock.tick + 600)
	print("blocker %d, security on duty %d" % [gate.blocker(), _w.staff.on_duty_count(1)])
	assert_int(gate.blocker()).is_equal(AirportGate.Blocker.STAFF_SPOT)
	assert_int(_w.staff.on_duty_count(StaffMember.Role.SECURITY)).is_equal(0)
	assert_bool(gate.is_open()).is_false()
