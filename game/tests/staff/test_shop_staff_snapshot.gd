class_name TestShopStaffSnapshot
extends GdUnitTestSuite
## Shop servers in the staff save (StaffSnapshot, version 3). A server on duty
## or walking to a counter saves and loads to play on exactly as continuous
## play. A version 2 save comes from before shop staff: it has none and loads
## as it is, so its cafes and kiosks stay closed until the player hires; a
## shop member in one is refused. A server must work a counter, and on duty it
## stands on that counter's staff spot.

const SHOP := StaffMember.Role.SHOP

var _w: PassengerTestWorld
var _b: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_w.step()


func after_test() -> void:
	for world in [_w, _b]:
		if world != null:
			world.free_all()
	_w = null
	_b = null


## The staff save as JSON hands it back.
func _saved() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_w.staff.to_snapshot())) as Dictionary


func _load_error(data: Dictionary) -> String:
	return str(StaffSnapshot.load(data, _w.sim).get("error", ""))


func _server_record(data: Dictionary) -> Dictionary:
	for record: Dictionary in data["members"]:
		if int(record["role"]) == SHOP:
			return record
	return {}


func test_the_save_is_version_3() -> void:
	assert_int(StaffSim.SAVE_VERSION).is_equal(3)
	assert_int(int(_saved()["save_version"])).is_equal(3)


func test_servers_walking_and_on_duty_load_and_play_on_alike() -> void:
	_w.staff.hire(SHOP)
	_w.staff.hire(SHOP)
	_w.run_to(_w.clock.tick + 20)
	var walking := 0
	for id in _w.staff.member_ids():
		walking += int(_w.staff.get_member(id).state == StaffMember.State.TO_STATION)
	assert_int(walking).is_greater(0)
	_b = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_object(_b).is_not_null()
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_w.staff))
	for i in 400:
		_w.step()
		_b.step()
	var signature := StaffTestKit.signature(_w.staff)
	print("after 400 ticks %s" % signature)
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(signature)
	assert_int(_b.staff.on_duty_count(SHOP)).is_equal(2)
	assert_bool(_b.staff.is_open(_ids["air_counter"])).is_true()
	assert_bool(_b.staff.is_open(_ids["land_counter"])).is_true()


func test_a_version_2_save_loads_with_no_servers_and_its_counters_stay_closed() -> void:
	var data := _saved()
	assert_int((data["members"] as Array).size()).is_greater(0)
	data["save_version"] = 2
	assert_bool(_w.staff.from_snapshot(data)).is_true()
	assert_int(_w.staff.count(SHOP)).is_equal(0)
	assert_array(_w.staff.stations_of(SHOP)).has_size(2)
	for counter in _w.staff.stations_of(SHOP):
		assert_bool(_w.staff.is_open(counter)).is_false()
	assert_array(ShopCounters.closed(_w.sim)).contains_exactly(_w.staff.stations_of(SHOP))


func test_a_version_2_save_with_a_shop_member_is_refused() -> void:
	StaffTestKit.seat_server(_w.staff, _ids["air_counter"])
	var data := _saved()
	data["save_version"] = 2
	assert_str(_load_error(data)).contains("version 2")


func test_a_server_working_at_a_desk_is_refused() -> void:
	StaffTestKit.seat_server(_w.staff, _ids["air_counter"])
	var data := _saved()
	var record := _server_record(data)
	record["state"] = StaffMember.State.TO_STATION
	record["station"] = _w.sim.layout.desks[0]
	assert_str(_load_error(data)).contains("not one of its role")


func test_a_server_on_duty_away_from_its_spot_is_refused() -> void:
	StaffTestKit.seat_server(_w.staff, _ids["air_counter"])
	var data := _saved()
	var record := _server_record(data)
	record["at"] = [25, 4]
	record["path"] = [[25, 4]]
	assert_str(_load_error(data)).contains("away from its post's staff spot")


func test_a_loaded_server_on_duty_opens_its_counter() -> void:
	var id := StaffTestKit.seat_server(_w.staff, _ids["air_counter"])
	var data := _saved()
	assert_bool(_w.staff.from_snapshot(data)).is_true()
	assert_bool(_w.staff.is_open(_ids["air_counter"])).is_true()
	assert_that(_w.staff.get_member(id).at).is_equal(Vector2i(22, 3))
