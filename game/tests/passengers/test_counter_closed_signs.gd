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


func test_an_airside_counter_staff_cannot_reach_says_so() -> void:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	# Without the staff door the divider is crossed only through security,
	# which staff never walk (decision staff-spot-reach-rule-an-edit-that-cuts-
	# a-reachable-staff-sp, point 3).
	var shut := BuildEdit.place_wall(ShopTestLayout.STAFF_DOOR, BuildGrid.Side.NORTH)
	assert_bool(grid.apply(shut).ok).is_true()
	_attach(grid)
	var counter: int = ids["air_counter"]
	assert_bool(_world.staff.spot_unreachable(counter)).is_true()
	_markers.sync()
	assert_str(_markers.closed_text(counter)).is_equal(MissMarkers.UNREACHABLE_CAPTION)
	var m := _world.staff.get_member(_world.staff.hire(StaffMember.Role.SHOP))
	_world.run_to(_world.clock.tick + 120)
	assert_int(m.station).is_equal(0)
