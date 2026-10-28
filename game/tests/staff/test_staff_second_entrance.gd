class_name TestStaffSecondEntrance
extends GdUnitTestSuite
## A member hired into the pool comes in through the entrance that gives its
## station the shortest path, not always the first one. Staff reach counts
## every entrance (StaffSpots.reach()), so a spot reachable only through the
## second entrance is not "can't reach", and an agent must get there.
##
## A 12x12 floored grid split by a wall along the north edge of row 6: the
## first entrance (lower id) at (0, 11) on the south half, the second at
## (11, 0) on the north half, and a desk at (5, 3) with its spot (5, 2). A
## fired member walks out through the entrance it can reach, and removing the
## only entrance that reaches a spot is refused like any other cut.

const CHECKIN := StaffMember.Role.CHECKIN
const WALL_Y := 6
const LIMIT_TICKS := 600
const SECOND_DOOR := Vector2i(11, 0)

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## Builds the split grid and its world; returns [first, second, desk] ids.
func _split_world() -> Array[int]:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	var first := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	for x in 12:
		assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(x, WALL_Y), 0)).ok).is_true()
	var second := PassengerTestWorld.place(grid, &"entrance_door", SECOND_DOOR, 0)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	assert_int(_w.sim.layout.entrances[0]).is_equal(first)
	assert_bool(_w.sim.layout.is_usable(desk)).is_true()
	assert_bool(_w.staff.spot_unreachable(desk)).is_false()
	return [first, second, desk]


## Hires an agent and steps until it is on duty at `desk`.
func _agent_on_duty(desk: int) -> StaffMember:
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	_w.step()
	var came_in := m.path[0] if not m.path.is_empty() else StaffMember.NO_CELL
	print("member %d station %d came in at %s" % [m.id, m.station, came_in])
	assert_int(m.station).is_equal(desk)
	assert_that(came_in).is_equal(SECOND_DOOR)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	print("state %d at %s, tick %d" % [m.state, m.at, _w.clock.tick])
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_that(m.at).is_equal(StaffSpots.spot_of(_w.grid, desk))
	return m


func test_a_spot_reached_only_through_the_second_entrance_is_staffed() -> void:
	var ids := _split_world()
	_agent_on_duty(ids[2])
	assert_bool(_w.staff.is_staffed(ids[2])).is_true()


func test_a_fired_agent_walks_out_through_the_entrance_it_can_reach() -> void:
	var ids := _split_world()
	var m := _agent_on_duty(ids[2])
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_int(m.state).is_equal(StaffMember.State.WALKING_OUT)
	var last := StaffMember.NO_CELL
	while _w.staff.get_member(m.id) != null and _w.clock.tick < LIMIT_TICKS * 2:
		last = m.at
		_w.step()
	print("walked out: gone %s, last at %s" % [_w.staff.get_member(m.id) == null, m.at])
	assert_object(_w.staff.get_member(m.id)).is_null()
	assert_that(m.at).is_equal(SECOND_DOOR)
	assert_that(last).is_not_equal(m.at)


func test_removing_the_only_entrance_that_reaches_a_spot_is_refused() -> void:
	var ids := _split_world()
	var result := _w.grid.apply(BuildEdit.remove_object(ids[1]))
	print(
		"remove second entrance: %s, blocker %d" % [result.reason_text(), result.blocking_object_id]
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_int(result.blocking_object_id).is_equal(ids[2])
	assert_that(StaffSpots.spot_of(_w.grid, ids[2])).is_equal(Vector2i(5, 2))
	assert_str(str(_w.grid.get_object(ids[1])["def"])).is_equal("entrance_door")
	assert_bool(_w.staff.spot_unreachable(ids[2])).is_false()


func test_removing_a_redundant_entrance_passes() -> void:
	var ids := _split_world()
	# A third entrance on the north half reaches the desk too.
	PassengerTestWorld.place(_w.grid, &"entrance_door", Vector2i(0, 0), 0)
	assert_bool(_w.grid.apply(BuildEdit.remove_object(ids[1])).ok).is_true()
	# The first entrance reaches no spot at all.
	assert_bool(_w.grid.apply(BuildEdit.remove_object(ids[0])).ok).is_true()
	assert_bool(_w.staff.spot_unreachable(ids[2])).is_false()
