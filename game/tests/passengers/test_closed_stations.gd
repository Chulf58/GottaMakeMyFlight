class_name TestClosedStations
extends GdUnitTestSuite
## An unstaffed desk or scanner is closed: its stuck passengers say so ("Check-in
## is closed", not "Where is check-in?") and MissMarkers puts a Closed sign over
## it until a member is on duty there.

var _world: PassengerTestWorld
var _views: PassengerViews
var _markers: MissMarkers


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## The reference terminal with nobody hired.
func _unstaffed() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world()
	world.auto_staff = false
	return world


func _attach() -> void:
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


func test_a_passenger_at_unstaffed_desks_says_check_in_is_closed() -> void:
	_world = _unstaffed()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(_world.clock.tick + 30)
	var p := _world.passenger(id)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_CHECKIN)
	assert_str(_world.sim.bubble_text(p)).is_equal("Check-in is closed")


func test_a_passenger_at_unstaffed_scanners_says_security_is_closed() -> void:
	_world = _unstaffed()
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.CHECKIN])
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.TO_SECURITY and _world.clock.tick < 900:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	_world.run_to(_world.clock.tick + 30)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_SECURITY)
	assert_str(_world.sim.bubble_text(p)).is_equal("Security is closed")


func test_staffing_the_desk_clears_the_closed_reason() -> void:
	_world = _unstaffed()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(_world.clock.tick + 30)
	var p := _world.passenger(id)
	assert_str(_world.sim.bubble_text(p)).is_equal("Check-in is closed")
	StaffTestKit.staff_all(_world.staff)
	_world.run_to(_world.clock.tick + 60)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_str(_world.sim.bubble_text(p)).is_not_equal("Check-in is closed")


func test_no_desk_at_all_still_asks_where_check_in_is() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	assert_str(_world.sim.bubble_text(_world.passenger(id))).is_equal("Where is check-in?")


func test_every_unstaffed_desk_and_scanner_is_listed_closed() -> void:
	_world = _unstaffed()
	var closed := MissSignals.closed_stations(_world.sim)
	var layout := _world.sim.layout
	assert_int(closed.size()).is_equal(layout.desks.size() + layout.scanners.size())
	assert_int(closed.size()).is_greater(0)
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.CHECKIN])
	var left := MissSignals.closed_stations(_world.sim)
	assert_int(left.size()).is_equal(layout.scanners.size())
	for station: int in layout.scanners:
		assert_bool(left.has(station)).is_true()


func test_unstaffed_stations_get_a_closed_sign_that_goes_when_staffed() -> void:
	_world = _unstaffed()
	_attach()
	var layout := _world.sim.layout
	var desk: int = layout.desks[0]
	var scanner: int = layout.scanners[0]
	assert_object(_markers.closed_sign_for(desk)).is_not_null()
	assert_object(_markers.closed_sign_for(scanner)).is_not_null()
	assert_str(_markers.closed_text(desk)).is_equal("Closed")
	assert_bool(_markers.closed_sign_for(desk).visible).is_true()
	var sign := _markers.closed_sign_for(desk)
	assert_float(sign.position.y).is_greater(BuildCatalog.get_def(&"checkin_desk").height)
	StaffTestKit.staff_all(_world.staff)
	_world.step()
	assert_object(_markers.closed_sign_for(desk)).is_null()
	assert_object(_markers.closed_sign_for(scanner)).is_null()
	assert_bool(sign.visible).is_false()


func test_a_closed_sign_is_not_a_queue_full_sign() -> void:
	_world = _unstaffed()
	_attach()
	var desk: int = _world.sim.layout.desks[0]
	assert_object(_markers.sign_for(desk)).is_null()
	assert_object(_markers.closed_sign_for(desk)).is_not_null()


func test_a_staffed_station_shows_no_closed_sign() -> void:
	_world = PassengerTestWorld.reference_world()
	_attach()
	_world.step()
	for station: int in _world.sim.layout.desks:
		assert_object(_markers.closed_sign_for(station)).is_null()
