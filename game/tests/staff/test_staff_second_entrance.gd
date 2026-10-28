class_name TestStaffSecondEntrance
extends GdUnitTestSuite
## A member hired into the pool comes in through the entrance that gives its
## station the shortest path, not always the first one. Staff reach counts
## every entrance (StaffSpots.reach()), so a spot reachable only through the
## second entrance is not "can't reach", and an agent must get there.
##
## A 12x12 floored grid split by a wall along the north edge of row 6: the
## first entrance (lower id) at (0, 11) on the south half, the second at
## (11, 0) on the north half, and a desk at (5, 3) with its spot (5, 2).

const CHECKIN := StaffMember.Role.CHECKIN
const WALL_Y := 6
const LIMIT_TICKS := 600

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func test_a_spot_reached_only_through_the_second_entrance_is_staffed() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	var first := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	for x in 12:
		assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(x, WALL_Y), 0)).ok).is_true()
	var second := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(11, 0), 0)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	assert_int(_w.sim.layout.entrances[0]).is_equal(first)
	assert_bool(_w.sim.layout.is_usable(desk)).is_true()
	assert_bool(_w.staff.spot_unreachable(desk)).is_false()
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	_w.step()
	var came_in := m.path[0] if not m.path.is_empty() else StaffMember.NO_CELL
	print("member %d station %d came in at %s, second door %s" % [m.id, m.station, came_in, second])
	assert_int(m.station).is_equal(desk)
	assert_that(came_in).is_equal(Vector2i(11, 0))
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	print("state %d at %s, tick %d" % [m.state, m.at, _w.clock.tick])
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_that(m.at).is_equal(StaffSpots.spot_of(grid, desk))
	assert_bool(_w.staff.is_staffed(desk)).is_true()
