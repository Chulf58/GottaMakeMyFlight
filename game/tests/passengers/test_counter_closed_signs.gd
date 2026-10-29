class_name TestCounterClosedSigns
extends GdUnitTestSuite
## An unstaffed cafe or kiosk counter shows a Closed sign (ruling
## store-mechanics-draw-a-room-then-furnish-it-required-pieces, point 3) until
## a server is on duty there; one no server can stand at says its staff spot
## is blocked.

var _world: PassengerTestWorld
var _views: PassengerViews
var _markers: MissMarkers
var _ids: Dictionary


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


func _attach(grid: BuildGrid) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(1000000))
	_world.auto_staff = false
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


func test_an_unstaffed_counter_shows_closed_until_a_server_is_on_duty() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_attach(grid)
	var counter: int = _ids["air_counter"]
	_markers.sync()
	assert_object(_markers.closed_sign_for(counter)).is_not_null()
	assert_str(_markers.closed_text(counter)).is_equal(MissMarkers.CLOSED_CAPTION)
	StaffTestKit.seat_server(_world.staff, counter)
	_markers.sync()
	assert_object(_markers.closed_sign_for(counter)).is_null()
	assert_object(_markers.closed_sign_for(_ids["land_counter"])).is_not_null()


func test_a_counter_no_server_can_stand_at_says_its_staff_spot_is_blocked() -> void:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, [])
	grid.apply(BuildEdit.place_room(ShopTestLayout.AIRSIDE_ROOM, &"kiosk"))
	var counter := (
		grid.apply(BuildEdit.place_object(&"kiosk_counter", Vector2i(22, 3), 0)).object_id
	)
	grid.apply(BuildEdit.place_object(&"kiosk_display", Vector2i(24, 3), 0))
	_attach(grid)
	_markers.sync()
	assert_str(_markers.closed_text(counter)).is_equal(MissMarkers.SPOT_BLOCKED_CAPTION)


func test_an_airside_counter_past_the_divider_is_staffed_through_security() -> void:
	# The divider has no door: staff cross it through the scanners (decision
	# staff-may-walk-through-security-scanners-and-lanes-so-shop-s), so the
	# sign says Closed, not that staff can't reach, until a server arrives.
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	_attach(grid)
	var counter: int = ids["air_counter"]
	assert_bool(_world.staff.spot_unreachable(counter)).is_false()
	_markers.sync()
	assert_str(_markers.closed_text(counter)).is_equal(MissMarkers.CLOSED_CAPTION)
	var m := _world.staff.get_member(_world.staff.hire(StaffMember.Role.SHOP))
	while m.state != StaffMember.State.ON_DUTY and _world.clock.tick < 1500:
		_world.step()
	assert_int(m.station).is_equal(counter)
	_markers.sync()
	assert_object(_markers.closed_sign_for(counter)).is_null()


func test_removing_the_room_around_an_unstaffed_counter_drops_its_closed_sign() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_attach(grid)
	var counter: int = _ids["air_counter"]
	_markers.sync()
	assert_object(_markers.closed_sign_for(counter)).is_not_null()
	# A room edit changes no walk graph and nobody is hired, so neither
	# graph_changed nor staff_changed fires: the sign follows edit_applied.
	assert_bool(grid.apply(BuildEdit.remove_room(_ids["air_room"])).ok).is_true()
	assert_object(_markers.closed_sign_for(counter)).is_null()
	assert_object(_markers.closed_sign_for(_ids["land_counter"])).is_not_null()
