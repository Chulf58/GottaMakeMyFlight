class_name TestStaffSnapshot
extends GdUnitTestSuite
## A save while staff walk loads into a world that plays out exactly like the
## one that never stopped, and a damaged save is refused whole.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const COMPARE_TICKS := 1200

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


func _walker(world: PassengerTestWorld) -> StaffMember:
	for id in world.staff.member_ids():
		var m := world.staff.get_member(id)
		if m.state == StaffMember.State.TO_STATION and m.seg_mm > 0:
			return m
	return null


func test_a_save_mid_walk_plays_out_identically() -> void:
	_a = PassengerTestWorld.reference_world(777)
	_a.auto_staff = false
	for i in 6:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(30)
	_a.staff.hire(CHECKIN)
	_a.staff.hire(SECURITY)
	_a.staff.hire(CHECKIN)
	while _walker(_a) == null and _a.clock.tick < 200:
		_a.step()
	var walker := _walker(_a)
	assert_object(walker).is_not_null()
	print(
		(
			"saved at tick %d with member %d at %s, %d mm into a step"
			% [_a.clock.tick, walker.id, walker.at, walker.seg_mm]
		)
	)
	_b = _load(_save(_a))
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))
	assert_str(_b.signature()).is_equal(_a.signature())
	var differing := 0
	for i in COMPARE_TICKS:
		_a.step()
		_b.step()
		var same_staff := StaffTestKit.signature(_a.staff) == StaffTestKit.signature(_b.staff)
		differing += int(not same_staff or _a.signature() != _b.signature())
	var cleared := 0
	for id in _a.sim.passenger_ids():
		cleared += int(_a.passenger(id).cleared)
	print(
		(
			"after %d ticks: differing %d, on duty %d, cleared %d, made %d"
			% [
				COMPARE_TICKS,
				differing,
				_a.staff.on_duty_count(CHECKIN) + _a.staff.on_duty_count(SECURITY),
				cleared,
				_a.sim.made_count(),
			]
		)
	)
	assert_int(differing).is_equal(0)
	assert_int(_a.staff.on_duty_count(CHECKIN)).is_equal(2)
	assert_int(_a.staff.on_duty_count(SECURITY)).is_equal(1)
	assert_int(cleared).is_greater(0)


func test_a_save_right_after_a_station_is_removed_loads() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.auto_staff = false
	var id := _a.staff.hire(CHECKIN)
	while _a.staff.on_duty_count(CHECKIN) == 0 and _a.clock.tick < 600:
		_a.step()
	var desk := _a.staff.get_member(id).station
	assert_bool(_a.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	_b = _load(_save(_a))
	assert_int(_b.staff.get_member(id).station).is_equal(0)
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))


func test_damaged_saves_are_refused_and_change_nothing() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.auto_staff = false
	_a.staff.hire(CHECKIN)
	_a.staff.hire(CHECKIN)
	_a.run_to(10)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.staff.to_snapshot()))
	var before_load := StaffTestKit.signature(_a.staff)
	var bad_version := good.duplicate(true)
	bad_version["save_version"] = 99
	var same_station := good.duplicate(true)
	same_station["members"][1]["station"] = same_station["members"][0]["station"]
	var off_path := good.duplicate(true)
	off_path["members"][0]["at"] = [0, 0]
	var low_next := good.duplicate(true)
	low_next["next_id"] = 2
	var bad_role := good.duplicate(true)
	bad_role["members"][0]["role"] = 5
	var jump := good.duplicate(true)
	jump["members"][0]["path"][1] = [40, 40]
	for bad in [bad_version, same_station, off_path, low_next, bad_role, jump]:
		assert_bool(_a.staff.from_snapshot(bad)).is_false()
		assert_str(StaffTestKit.signature(_a.staff)).is_equal(before_load)
	assert_bool(_a.staff.from_snapshot(good)).is_true()
	assert_str(StaffTestKit.signature(_a.staff)).is_equal(before_load)


func test_a_save_right_after_a_walking_member_is_built_over_loads() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.auto_staff = false
	var id := _a.staff.hire(CHECKIN)
	var m := _a.staff.get_member(id)
	while (m.state != StaffMember.State.TO_STATION or m.path_index < 2) and _a.clock.tick < 300:
		_a.step()
	var desk := m.station
	assert_bool(_a.grid.apply(BuildEdit.remove_floor(m.at)).ok).is_true()
	assert_bool(m.in_pool()).is_true()
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.station).is_equal(0)
	assert_bool(m.needs_replan).is_false()
	assert_array(m.path).is_empty()
	assert_int(_a.staff.staff_at(desk)).is_equal(0)
	_b = _load(_save(_a))
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))


func test_an_on_duty_member_off_its_post_or_at_an_unusable_station_is_refused() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.auto_staff = false
	var id := _a.staff.hire(SECURITY)
	while _a.staff.on_duty_count(SECURITY) == 0 and _a.clock.tick < 600:
		_a.step()
	var m := _a.staff.get_member(id)
	var post := m.at
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.staff.to_snapshot()))
	var off_post := good.duplicate(true)
	off_post["members"][0]["at"] = [post.x, post.y + 1]
	off_post["members"][0]["path"] = [[post.x, post.y + 1]]
	var before_load := StaffTestKit.signature(_a.staff)
	assert_bool(_a.staff.from_snapshot(off_post)).is_false()
	assert_str(StaffTestKit.signature(_a.staff)).is_equal(before_load)
	# A wall across the scanner's passage closes it: the scanner is no longer
	# usable, so the saved member cannot be on duty there.
	var passage: Array = _a.sim.layout.passages[m.station]
	var last: Vector2i = passage[passage.size() - 1]
	var inside: Vector2i = passage[passage.size() - 2]
	var side := BuildGrid.SIDE_STEP.find(last - inside)
	var scanner := m.station
	assert_bool(_a.grid.apply(BuildEdit.place_wall(inside, side)).ok).is_true()
	assert_bool(_a.sim.layout.is_usable(scanner)).is_false()
	before_load = StaffTestKit.signature(_a.staff)
	assert_bool(_a.staff.from_snapshot(good)).is_false()
	assert_str(StaffTestKit.signature(_a.staff)).is_equal(before_load)
