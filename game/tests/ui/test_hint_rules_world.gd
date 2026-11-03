class_name TestHintRulesWorld
extends GdUnitTestSuite
## HintRules.read_world(): the second_hire shortage is read from a real sim and
## counts only a usable, reachable station with nobody claimed to it and no
## spare agent. Staff walking there, an agent idle in the pool and a station
## staff cannot reach are not a shortage (decision first-time-hints-above-the-
## build-bar-moment-of-need-per-profile-memory, point 2).

const CHECKIN := StaffMember.Role.CHECKIN
const LIMIT_TICKS := 4000

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## A floor with an entrance and two desks, nobody hired.
func _two_desks() -> Array[int]:
	var grid := PassengerTestWorld.floored(Vector2i(14, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	var first := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0)
	var second := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	return [first, second]


func _shortage() -> Array:
	return HintRules.read_world(_w.sim, [])["shortage_roles"]


func _seat(role: StaffMember.Role) -> StaffMember:
	var m := _w.staff.get_member(_w.staff.hire(role))
	_w.step()
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	return m


func test_desks_nobody_works_and_nobody_is_hired_is_a_shortage() -> void:
	_two_desks()
	assert_array(_shortage()).is_equal([CHECKIN])
	assert_int(HintRules.read_world(_w.sim, [])["desks"]).is_equal(2)


func test_one_agent_for_two_desks_is_a_shortage() -> void:
	_two_desks()
	_seat(CHECKIN)
	assert_array(_shortage()).is_equal([CHECKIN])


func test_one_agent_per_desk_is_no_shortage() -> void:
	_two_desks()
	_seat(CHECKIN)
	_seat(CHECKIN)
	assert_array(_shortage()).is_empty()


func test_agents_walking_to_their_desks_are_no_shortage() -> void:
	_two_desks()
	_w.staff.hire(CHECKIN)
	_w.staff.hire(CHECKIN)
	_w.step()
	var walking := 0
	for id in _w.staff.member_ids():
		walking += int(_w.staff.get_member(id).state == StaffMember.State.TO_STATION)
	assert_int(walking).is_greater(0)
	assert_array(_shortage()).is_empty()


func test_an_agent_still_idle_in_the_pool_is_a_spare_not_a_shortage() -> void:
	_two_desks()
	_seat(CHECKIN)
	# Hired while the clock is paused: no step has sent the new agent anywhere.
	_w.staff.hire(CHECKIN)
	assert_array(_shortage()).is_empty()


func test_a_desk_staff_cannot_reach_is_not_a_shortage() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	for x in 14:
		assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(x, 6), 0)).ok).is_true()
	var near := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 9), 0)
	var far := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	assert_bool(_w.staff.spot_unreachable(far)).is_true()
	_seat(CHECKIN)
	assert_bool(_w.staff.is_staffed(near)).is_true()
	assert_array(_shortage()).is_empty()


func test_a_world_without_a_staff_pool_reads_no_shortage() -> void:
	_two_desks()
	_w.sim.staff = null
	assert_array(_shortage()).is_empty()


func test_read_world_reports_the_neediest_passenger_and_the_rooms() -> void:
	_two_desks()
	var id := _w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_w.passenger(id).toilet_need = 88
	_w.passenger(id).hunger = 61
	var world := HintRules.read_world(_w.sim, [])
	assert_int(world["max_toilet_need"]).is_equal(88)
	assert_int(world["max_hunger"]).is_equal(61)
	assert_int(world["stalls"]).is_equal(0)
	assert_int(world["cafes"]).is_equal(0)
	assert_int(world["scanners"]).is_equal(0)


func test_a_ready_toilet_room_with_a_stall_is_a_usable_stall() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 9), 2)
	assert_bool(grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"toilet")).ok).is_true()
	PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(5, 3), 1)
	var sink := PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(2, 2), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var ready := HintRules.read_world(_w.sim, [])
	print("ready toilet: stalls=%d" % ready["stalls"])
	assert_int(ready["stalls"]).is_equal(1)
	# A room that exists but is not ready (no sink) has no usable stall.
	assert_bool(grid.apply(BuildEdit.remove_object(sink)).ok).is_true()
	var unready := HintRules.read_world(_w.sim, [])
	print("unready toilet: stalls=%d" % unready["stalls"])
	assert_int(unready["stalls"]).is_equal(0)


func test_a_ready_cafe_is_a_usable_cafe_and_one_without_a_table_is_not() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var ready := HintRules.read_world(_w.sim, [])
	print("ready cafes=%d" % ready["cafes"])
	assert_int(ready["cafes"]).is_greater(0)
	_w.free_all()
	var bare := BuildGrid.new()
	CafeTestLayout.build(bare, false, &"cafe", false)
	_w = PassengerTestWorld.make(bare, FlightSim.schedule_starts(0))
	var unready := HintRules.read_world(_w.sim, [])
	print("no-table cafes=%d" % unready["cafes"])
	assert_int(unready["cafes"]).is_equal(0)
