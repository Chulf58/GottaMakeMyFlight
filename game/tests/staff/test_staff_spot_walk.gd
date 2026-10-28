class_name TestStaffSpotWalk
extends GdUnitTestSuite
## Staff walk to their station's staff spot and are on duty only while they
## stand on it. A station whose spot an old save left blocked is never
## staffed, and an old staff save with a member on duty on the service cell
## loads with that member on the spot (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, points 3-4).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const LIMIT_TICKS := 600

var _w: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_w, _b]:
		if world != null:
			world.free_all()
	_w = null
	_b = null


func _until_on_duty(world: PassengerTestWorld, m: StaffMember) -> int:
	var start := world.clock.tick
	while world.clock.tick - start < LIMIT_TICKS:
		world.step()
		if m.state == StaffMember.State.ON_DUTY:
			return world.clock.tick - start
	return -1


## The reference terminal saved with a seat row on the first desk's spot
## (11, 10), as a save from before staff spots could hold it, then loaded.
func _legacy_world() -> PassengerTestWorld:
	var source := BuildGrid.new()
	ReferenceTerminal.build(source)
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	(data["objects"] as Array).append(
		{"id": next, "def": "seat_row", "anchor": [11, 10], "facing": 0}
	)
	data["next_object_id"] = next + 1
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.auto_staff = false
	return world


func test_an_agent_walks_to_the_spot_behind_the_desk_and_is_on_duty_there() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	_w.step()
	var spot := StaffSpots.spot_of(_w.grid, m.station)
	assert_that(m.path_end()).is_equal(spot)
	assert_int(_until_on_duty(_w, m)).is_greater(0)
	print(
		(
			"agent on duty at %s, spot %s, service cell %s"
			% [m.at, spot, _w.sim.layout.lanes[m.station][0]]
		)
	)
	assert_that(m.at).is_equal(spot)
	assert_that(m.at).is_not_equal(_w.sim.layout.lanes[m.station][0])
	assert_bool(_w.staff.is_staffed(m.station)).is_true()


func test_an_officer_is_on_duty_on_the_spot_beside_the_scanner() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	var m := _w.staff.get_member(_w.staff.hire(SECURITY))
	assert_int(_until_on_duty(_w, m)).is_greater(0)
	print("officer on duty at %s" % m.at)
	assert_that(m.at).is_equal(StaffSpots.spot_of(_w.grid, m.station))
	assert_bool(_w.staff.is_open(m.station)).is_true()


func test_a_station_whose_old_save_blocked_its_spot_is_never_staffed() -> void:
	_w = _legacy_world()
	var desks: Array = ReferenceTerminal.object_ids(_w.grid)["desks"]
	var blocked: int = desks[0]
	assert_bool(_w.staff.spot_blocked(blocked)).is_true()
	assert_bool(_w.staff.spot_blocked(desks[1])).is_false()
	var first := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var second := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var claimed := 0
	for i in LIMIT_TICKS:
		_w.step()
		claimed += int(_w.staff.staff_at(blocked) != 0)
	print(
		(
			"first %d at %s, second %d at %s, ticks claimed %d"
			% [first.state, first.at, second.state, second.at, claimed]
		)
	)
	assert_int(claimed).is_equal(0)
	assert_bool(_w.staff.is_staffed(desks[1])).is_true()
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.count(CHECKIN)).is_equal(2)


func test_an_old_save_with_a_member_on_the_service_cell_loads_it_on_the_spot() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	assert_int(_until_on_duty(_w, m)).is_greater(0)
	var data: Dictionary = JSON.parse_string(StaffTestKit.save_text(_w))
	var service: Vector2i = _w.sim.layout.lanes[m.station][0]
	var record: Dictionary = data["staff"]["members"][0]
	record["at"] = [service.x, service.y]
	record["path"] = [[service.x, service.y]]
	record["path_index"] = 0
	_b = StaffTestKit.load_world(JSON.stringify(data))
	assert_object(_b).is_not_null()
	var loaded := _b.staff.get_member(m.id)
	print("migrated member %d state %d at %s" % [loaded.id, loaded.state, loaded.at])
	assert_int(loaded.state).is_equal(StaffMember.State.ON_DUTY)
	assert_that(loaded.at).is_equal(StaffSpots.spot_of(_b.grid, m.station))
	for i in 50:
		_w.step()
		_b.step()
	assert_that(loaded.at).is_equal(m.at)
	assert_int(loaded.state).is_equal(m.state)


func test_an_old_save_on_duty_at_a_station_with_a_blocked_spot_loads_the_member_idle() -> void:
	_w = _legacy_world()
	var desk: int = ReferenceTerminal.object_ids(_w.grid)["desks"][0]
	var service: Vector2i = _w.sim.layout.lanes[desk][0]
	var data: Dictionary = JSON.parse_string(StaffTestKit.save_text(_w))
	data["staff"]["next_id"] = 2
	data["staff"]["members"] = [
		{
			"id": 1,
			"role": CHECKIN,
			"state": StaffMember.State.ON_DUTY,
			"station": desk,
			"at": [service.x, service.y],
			"path": [[service.x, service.y]],
			"path_index": 0,
			"seg_mm": 0,
			"needs_replan": false,
			"search_failed": false,
			"leaving": false,
		}
	]
	_b = StaffTestKit.load_world(JSON.stringify(data))
	assert_object(_b).is_not_null()
	var m := _b.staff.get_member(1)
	print("member state %d station %d at %s" % [m.state, m.station, m.at])
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.station).is_equal(0)
	assert_that(m.at).is_equal(service)
	assert_bool(_b.staff.is_staffed(desk)).is_false()
