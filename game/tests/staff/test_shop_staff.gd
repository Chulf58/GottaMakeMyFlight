class_name TestShopStaff
extends GdUnitTestSuite
## Shop staff (ruling store-mechanics-draw-a-room-then-furnish-it-required-
## pieces, point 3): a third role in the hiring pool. A hired server walks to
## the nearest unstaffed counter of a ready cafe or kiosk and stands on its
## staff spot (ShopCounters): behind the till when that cell is free floor in
## the room, else beside its west end, else its east end. A counter with no
## such cell is never staffed. Firing works as it does for desks, and each
## server is charged the shop wage at midnight.

const SHOP := StaffMember.Role.SHOP
const ON_DUTY := StaffMember.State.ON_DUTY
const LIMIT_TICKS := 1500

var _w: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## The two cafes of CafeTestLayout, nobody hired.
func _cafe_world() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world_on(grid)


## The floor east of the terminal with one landside kiosk whose counter stands
## at `counter` and its display stand at `display`, both facing south.
func _kiosk_world(room: Rect2i, counter: Vector2i, display: Vector2i) -> void:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, [])
	_ids = {"room": _apply(grid, BuildEdit.place_room(room, &"kiosk")).room_id}
	_ids["counter"] = _apply(grid, BuildEdit.place_object(&"kiosk_counter", counter, 0)).object_id
	_ids["display"] = _apply(grid, BuildEdit.place_object(&"kiosk_display", display, 0)).object_id
	_world_on(grid)


func _world_on(grid: BuildGrid) -> void:
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(1000000))
	_w.auto_staff = false


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


func _until_on_duty(id: int) -> StaffMember:
	var m := _w.staff.get_member(id)
	var start := _w.clock.tick
	while m.state != ON_DUTY and _w.clock.tick - start < LIMIT_TICKS:
		_w.step()
	print("member %d state %d at %s station %d" % [id, m.state, m.at, m.station])
	assert_int(m.state).is_equal(ON_DUTY)
	return m


func test_the_counters_of_ready_cafes_are_the_shop_stations() -> void:
	_cafe_world()
	var counters := _w.staff.stations_of(SHOP)
	print("counters %s" % [counters])
	assert_array(counters).contains_exactly([_ids["air_counter"], _ids["land_counter"]])


func test_a_hired_server_walks_to_a_counter_and_opens_it() -> void:
	_cafe_world()
	for counter in _w.staff.stations_of(SHOP):
		assert_bool(_w.staff.is_open(counter)).is_false()
	var m := _until_on_duty(_w.staff.hire(SHOP))
	assert_array(_w.staff.stations_of(SHOP)).contains([m.station])
	assert_that(m.at).is_equal(_w.staff.spot_of(m.station))
	assert_bool(_w.staff.is_open(m.station)).is_true()
	assert_int(_w.staff.count(SHOP)).is_equal(1)
	assert_int(_w.staff.on_duty_count(SHOP)).is_equal(1)


func test_with_the_till_against_the_room_edge_the_server_stands_at_the_west_end() -> void:
	_cafe_world()
	# Behind the airside till is off the floor; behind the landside one is the
	# walkway between the rooms, outside the room.
	assert_that(_w.staff.spot_of(_ids["air_counter"])).is_equal(Vector2i(22, 3))
	assert_that(_w.staff.spot_of(_ids["land_counter"])).is_equal(Vector2i(22, 10))


func test_with_room_floor_behind_the_till_the_server_stands_behind_it() -> void:
	_kiosk_world(ShopTestLayout.LANDSIDE_ROOM, Vector2i(23, 11), Vector2i(25, 13))
	assert_that(_w.staff.spot_of(_ids["counter"])).is_equal(Vector2i(23, 10))


func test_with_the_west_end_outside_the_room_the_server_stands_at_the_east_end() -> void:
	_kiosk_world(ShopTestLayout.AIRSIDE_ROOM, Vector2i(22, 3), Vector2i(25, 6))
	assert_that(_w.staff.spot_of(_ids["counter"])).is_equal(Vector2i(24, 3))


func test_a_counter_with_no_free_cell_for_a_server_is_never_staffed() -> void:
	# The display stand fills the east end; behind and west are outside.
	_kiosk_world(ShopTestLayout.AIRSIDE_ROOM, Vector2i(22, 3), Vector2i(24, 3))
	var counter: int = _ids["counter"]
	assert_array(_w.staff.stations_of(SHOP)).contains_exactly([counter])
	assert_that(_w.staff.spot_of(counter)).is_equal(BuildObjectDef.NO_CELL)
	assert_bool(_w.staff.spot_blocked(counter)).is_true()
	var m := _w.staff.get_member(_w.staff.hire(SHOP))
	_w.run_to(_w.clock.tick + 300)
	print("member state %d station %d" % [m.state, m.station])
	assert_int(m.station).is_equal(0)
	assert_bool(_w.staff.is_open(counter)).is_false()


func test_two_servers_open_both_counters_and_a_third_waits_in_the_pool() -> void:
	_cafe_world()
	var ids: Array[int] = []
	for i in 3:
		ids.append(_w.staff.hire(SHOP))
	_until_on_duty(ids[0])
	_until_on_duty(ids[1])
	assert_bool(_w.staff.is_open(_ids["air_counter"])).is_true()
	assert_bool(_w.staff.is_open(_ids["land_counter"])).is_true()
	var third := _w.staff.get_member(ids[2])
	assert_int(third.state).is_equal(StaffMember.State.IDLE)
	assert_bool(third.in_pool()).is_true()


func test_firing_a_server_with_nobody_ordering_walks_it_out_and_closes_the_counter() -> void:
	_cafe_world()
	var m := _until_on_duty(_w.staff.hire(SHOP))
	var counter := m.station
	assert_bool(_w.staff.fire(SHOP)).is_true()
	assert_int(m.state).is_equal(StaffMember.State.WALKING_OUT)
	assert_bool(_w.staff.is_open(counter)).is_false()
	assert_int(_w.staff.count(SHOP)).is_equal(0)


func test_a_server_whose_spot_moves_walks_to_the_new_spot() -> void:
	_kiosk_world(ShopTestLayout.LANDSIDE_ROOM, Vector2i(23, 11), Vector2i(25, 13))
	var counter: int = _ids["counter"]
	var m := _until_on_duty(_w.staff.hire(SHOP))
	assert_that(m.at).is_equal(Vector2i(23, 10))
	# A sink on the walkway keeps its approach on the cell behind the till: it
	# stays floor but is no spot any more, so the west end is.
	_apply(_w.grid, BuildEdit.place_object(&"toilet_sink", Vector2i(23, 9), 0))
	assert_that(_w.staff.spot_of(counter)).is_equal(Vector2i(22, 11))
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_bool(_w.staff.is_open(counter)).is_false()
	m = _until_on_duty(m.id)
	assert_that(m.at).is_equal(Vector2i(22, 11))
	assert_bool(_w.staff.is_open(counter)).is_true()


func test_a_server_is_charged_the_shop_wage_at_midnight() -> void:
	var kit := SettlementWagesKit.new(self)
	kit.hire(SHOP, 2)
	kit.charge(1)
	print("charges %s" % [kit.charges])
	assert_int(PriceTable.wage_of(SHOP)).is_equal(50)
	assert_array(kit.charges).is_equal([[0, 100, 0]])
	kit.free_all()
