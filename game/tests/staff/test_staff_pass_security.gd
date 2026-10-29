class_name TestStaffPassSecurity
extends GdUnitTestSuite
## Staff may walk through security scanners and lanes (decision
## staff-may-walk-through-security-scanners-and-lanes-so-shop-s): staff paths
## and staff reach (BuildGrid.find_staff_path(), StaffSpots.reach()) cross a
## walk-through security object along its axis, so a server reaches an
## airside kiosk with no door in the divider. Passengers are unaffected: their
## routing (BuildGrid.find_path()) still never crosses security.

const SHOP := StaffMember.Role.SHOP
const LIMIT_TICKS := 1500
## Airside floor just west of the terminal's east wall openings.
const AIRSIDE := ShopTestLayout.AIRSIDE_CELL

var _w: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	_ids = ShopTestLayout.build(grid, ["air"])
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(1000000))
	_w.auto_staff = false


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _door() -> Vector2i:
	return _w.sim.layout.door_cell(_w.grid, _w.sim.layout.entrances[0])


func _security_cells(path: Array[Vector2i]) -> int:
	var n := 0
	for cell in path:
		var occupant := _w.grid.object_at(cell)
		n += int(occupant != 0 and BuildCatalog.is_security(_w.grid.get_object(occupant)["def"]))
	return n


func test_staff_paths_cross_security_and_passenger_paths_do_not() -> void:
	var staff_path := _w.grid.find_staff_path(_door(), AIRSIDE)
	var passenger_path := _w.grid.find_path(_door(), AIRSIDE)
	print(
		(
			"staff %d cells, %d in security; passenger %d"
			% [staff_path.size(), _security_cells(staff_path), passenger_path.size()]
		)
	)
	assert_int(staff_path.size()).is_greater(0)
	assert_int(_security_cells(staff_path)).is_greater(0)
	assert_array(passenger_path).is_empty()


func test_staff_reach_takes_in_the_airside() -> void:
	assert_bool(_w.grid.staff_reach().has(AIRSIDE)).is_true()
	assert_bool(_w.staff.spot_unreachable(_ids["air_counter"])).is_false()


func test_a_server_walks_through_security_to_an_airside_kiosk_and_opens_it() -> void:
	var m := _w.staff.get_member(_w.staff.hire(SHOP))
	var crossed := 0
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < LIMIT_TICKS:
		_w.step()
		if not m.in_pool():
			crossed += _security_cells([m.at] as Array[Vector2i])
	print(
		(
			"on duty %d at %s after %d ticks, %d ticks on security cells"
			% [int(m.state == StaffMember.State.ON_DUTY), m.at, _w.clock.tick, crossed]
		)
	)
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_int(m.station).is_equal(_ids["air_counter"])
	assert_int(crossed).is_greater(0)
	assert_bool(_w.staff.is_open(_ids["air_counter"])).is_true()


func test_a_fired_airside_server_walks_back_out_through_security() -> void:
	var id := _w.staff.hire(SHOP)
	var m := _w.staff.get_member(id)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	assert_bool(_w.staff.fire(SHOP)).is_true()
	assert_int(m.state).is_equal(StaffMember.State.WALKING_OUT)
	var start := _w.clock.tick
	while _w.staff.get_member(id) != null and _w.clock.tick - start < LIMIT_TICKS:
		_w.step()
	print("gone after %d ticks at %s" % [_w.clock.tick - start, m.at])
	assert_object(_w.staff.get_member(id)).is_null()
	assert_that(m.at).is_equal(_door())


func test_staff_walk_through_a_security_arch_along_its_axis() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 7))
	for x in 8:
		if x != 3:
			(
				assert_bool(
					grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH)).ok
				)
				. is_true()
			)
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"security_arch", Vector2i(3, 4), 0)).ok)
		. is_true()
	)
	var staff_path := grid.find_staff_path(Vector2i(3, 0), Vector2i(3, 6))
	print("staff path %s" % [staff_path])
	assert_bool(staff_path.has(Vector2i(3, 4))).is_true()
	assert_array(grid.find_path(Vector2i(3, 0), Vector2i(3, 6))).is_empty()
	# Not across the axis: from beside the arch there is no way in.
	assert_bool(grid.can_staff_route(Vector2i(2, 4), Vector2i(3, 4))).is_false()
