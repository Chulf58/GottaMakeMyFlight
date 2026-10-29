class_name TestInfoDeskStaffing
extends GdUnitTestSuite
## An info desk is staffed from the SHOP role like a counter, but needs no
## room (decision info-desk-helps-stuck-passengers-a-short-help-visit-with-a-m;
## ShopCounters.ROOMLESS): it is usable on open floor, gets a staff spot there,
## serves only with a server on duty, and never opens a kiosk it stands in.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_a_desk_on_open_floor_is_a_usable_counter_with_a_staff_spot() -> void:
	_world = InfoDeskTestLayout.world(true, [StaffMember.Role.CHECKIN])
	var grid := _world.grid
	var desk := _world.staff.stations_of(StaffMember.Role.SHOP)[0]
	assert_str(str(grid.get_object(desk)["def"])).is_equal("info_desk")
	assert_int(grid.room_at(InfoDeskTestLayout.DESK_ANCHOR)).is_equal(0)
	assert_bool(ShopCounters.is_counter(grid, desk)).is_true()
	assert_bool(ShopCounters.is_roomless(grid, desk)).is_true()
	assert_bool(ShopCounters.usable(grid, desk)).is_true()
	assert_bool(ShopCounters.blocked(grid, desk)).is_false()
	# Behind the till, as for any counter.
	assert_object(ShopCounters.spot(grid, desk)).is_equal(
		InfoDeskTestLayout.DESK_ANCHOR + Vector2i(0, -1)
	)
	assert_object(grid.interaction_cell(desk)).is_equal(InfoDeskTestLayout.DESK_FRONT)


func test_it_is_closed_without_a_server_and_open_with_one() -> void:
	_world = InfoDeskTestLayout.world(true, [StaffMember.Role.CHECKIN])
	_world.run_to(5)
	var desk := _world.staff.stations_of(StaffMember.Role.SHOP)[0]
	assert_bool(_world.staff.is_open(desk)).is_false()
	assert_array(ShopCounters.closed(_world.sim)).contains_exactly([desk])
	assert_array(_world.sim.info_desks.open_desks()).is_empty()
	StaffTestKit.seat_server(_world.staff, desk)
	assert_bool(_world.staff.is_open(desk)).is_true()
	assert_array(ShopCounters.closed(_world.sim)).is_empty()
	assert_array(_world.sim.info_desks.open_desks()).contains_exactly([desk])


func test_a_staffed_desk_inside_a_kiosk_does_not_open_the_kiosk() -> void:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	var desk := PassengerTestWorld.place(grid, &"info_desk", Vector2i(22, 6), 0)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.auto_staff = false
	_world.run_to(5)
	assert_int(grid.room_at(Vector2i(22, 6))).is_equal(ids["air_room"])
	assert_bool(ShopCounters.usable(grid, desk)).is_true()
	StaffTestKit.seat_server(_world.staff, desk)
	assert_bool(_world.staff.is_open(desk)).is_true()
	assert_bool(_world.staff.is_open(ids["air_counter"])).is_false()
	assert_bool(ShopCounters.room_open(_world.sim, ids["air_room"])).is_false()
	StaffTestKit.seat_server(_world.staff, ids["air_counter"])
	assert_bool(ShopCounters.room_open(_world.sim, ids["air_room"])).is_true()
