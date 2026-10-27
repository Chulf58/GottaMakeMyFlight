class_name TestStaffLeaving
extends GdUnitTestSuite
## A member fired mid-service stays until the service ends: across a save and
## load it leaves on the same tick as in a world that never stopped, and when
## its station is removed meanwhile it goes at once.

const CHECKIN := StaffMember.Role.CHECKIN
const LIMIT_TICKS := 1500

var _a: PassengerTestWorld
var _b: PassengerTestWorld


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


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"staff": world.staff.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	world.auto_staff = false
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.staff.from_snapshot(data["staff"])).is_true()
	return world


func _in_service(world: PassengerTestWorld, station: int) -> bool:
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		if p.station == station and p.stage == Passenger.Stage.CHECKIN:
			return true
	return false


## A world with one agent on duty at a desk, a passenger being checked in there
## and the agent fired, so it is leaving. Returns the agent.
func _world_with_a_leaving_agent() -> StaffMember:
	_a = PassengerTestWorld.reference_world(5)
	_a.auto_staff = false
	for i in 4:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var m := _a.staff.get_member(_a.staff.hire(CHECKIN))
	while _a.clock.tick < LIMIT_TICKS:
		_a.step()
		if m.state == StaffMember.State.ON_DUTY and _in_service(_a, m.station):
			break
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_bool(_in_service(_a, m.station)).is_true()
	assert_bool(_a.staff.fire(CHECKIN)).is_true()
	return m


func test_a_leaving_member_leaves_on_the_same_tick_after_a_save_and_load() -> void:
	var m := _world_with_a_leaving_agent()
	var id := m.id
	var desk := m.station
	assert_bool(m.leaving).is_true()
	assert_bool(_a.staff.is_open(desk)).is_false()
	_b = _load(_save(_a))
	var loaded := _b.staff.get_member(id)
	assert_object(loaded).is_not_null()
	assert_bool(loaded.leaving).is_true()
	assert_int(_b.staff.leaving_count(CHECKIN)).is_equal(1)
	assert_bool(_b.staff.is_open(desk)).is_false()
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))
	var differing := 0
	var left_a := -1
	var left_b := -1
	for i in LIMIT_TICKS:
		_a.step()
		_b.step()
		differing += int(StaffTestKit.signature(_a.staff) != StaffTestKit.signature(_b.staff))
		if left_a < 0 and _a.staff.get_member(id) == null:
			left_a = _a.clock.tick
		if left_b < 0 and _b.staff.get_member(id) == null:
			left_b = _b.clock.tick
		if left_a >= 0 and left_b >= 0:
			break
	print("leaving member %d left at tick %d (continued) and %d (loaded)" % [id, left_a, left_b])
	assert_int(left_a).is_greater(0)
	assert_int(left_b).is_equal(left_a)
	assert_int(differing).is_equal(0)
	assert_int(_b.staff.count(CHECKIN)).is_equal(0)
	assert_int(_b.staff.staff_at(desk)).is_equal(0)


func test_a_station_removed_while_its_member_is_leaving_lets_it_go_at_once() -> void:
	var m := _world_with_a_leaving_agent()
	var id := m.id
	var desk := m.station
	var changes := [0]
	_a.staff.staff_changed.connect(func() -> void: changes[0] += 1)
	assert_bool(_a.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	assert_object(_a.staff.get_member(id)).is_null()
	assert_int(_a.staff.count(CHECKIN)).is_equal(0)
	assert_int(_a.staff.leaving_count(CHECKIN)).is_equal(0)
	assert_int(_a.staff.staff_at(desk)).is_equal(0)
	assert_int(changes[0]).is_greater(0)
	_a.run_to(_a.clock.tick + 60)
	assert_int(_a.staff.count(CHECKIN)).is_equal(0)
	_b = _load(_save(_a))
	assert_int(_b.staff.count(CHECKIN)).is_equal(0)
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))
