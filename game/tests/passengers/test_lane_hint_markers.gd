class_name TestLaneHintMarkers
extends GdUnitTestSuite
## An arch without a whole lane gets a sign whose caption names the first thing
## missing (SecurityLanes.status_text), a whole lane gets the Closed and the
## queue-full signs a basic scanner gets, and the whole feature is off while
## SecurityLanes.enabled is.

const ANCHOR := Vector2i(5, 6)
const S := SecurityLanes.Status

var _world: PassengerTestWorld
var _views: PassengerViews
var _markers: MissMarkers
var _arch := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	SecurityLanes.enabled = true


func after_test() -> void:
	SecurityLanes.enabled = false
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## A floored grid with an entrance and a lane at ANCHOR, facing 0, mirror
## RIGHT. `skip`, `turned` and `blocked` shape it as SecurityLaneBuilder does.
func _attach(
	skip: Array[StringName] = [],
	turned: Array[StringName] = [],
	blocked := Vector2i(-1, -1),
	staffed := false
) -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 14))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 13), 3)
	_arch = SecurityLaneBuilder.build(grid, ANCHOR, 0, SecurityLanes.RIGHT, skip, turned)[
		SecurityLanes.ARCH
	]
	if blocked.x >= 0:
		SecurityLaneBuilder.block(grid, blocked)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.auto_staff = staffed
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


func _assert_hint(status: int) -> void:
	assert_int(_world.sim.layout.security_lanes.status(_arch)).is_equal(status)
	var hint := _markers.hint_sign_for(_arch)
	assert_object(hint).is_not_null()
	assert_bool(hint.visible).is_true()
	assert_str(_markers.hint_text(_arch)).is_equal(SecurityLanes.STATUS_TEXT[status])
	assert_str(_markers.hint_text(_arch)).is_not_empty()
	# An incomplete arch is no station: it is neither closed nor full.
	assert_object(_markers.closed_sign_for(_arch)).is_null()
	assert_object(_markers.sign_for(_arch)).is_null()
	assert_array(MissSignals.closed_stations(_world.sim)).is_empty()


func test_a_missing_tray_table_is_named() -> void:
	_attach([SecurityLanes.TRAY_TABLE])
	_assert_hint(S.NO_TRAY_TABLE)


func test_a_missing_xray_belt_is_named() -> void:
	_attach([SecurityLanes.XRAY_BELT])
	_assert_hint(S.NO_XRAY_BELT)


func test_a_missing_pickup_table_is_named() -> void:
	_attach([SecurityLanes.PICKUP_TABLE])
	_assert_hint(S.NO_PICKUP_TABLE)


func test_the_first_missing_part_in_flow_order_is_named() -> void:
	_attach([SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE])
	_assert_hint(S.NO_XRAY_BELT)


func test_parts_facing_different_ways_are_named() -> void:
	_attach([], [SecurityLanes.XRAY_BELT])
	_assert_hint(S.PARTS_FACING)


func test_a_blocked_cell_of_the_lane_room_is_named() -> void:
	_attach([], [], SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["queue_entry"])
	_assert_hint(S.NO_QUEUE_ROOM)


func test_the_hint_sign_stands_over_the_arch_and_is_a_plain_caption() -> void:
	_attach([SecurityLanes.TRAY_TABLE])
	var hint := _markers.hint_sign_for(_arch)
	var def := BuildCatalog.get_def(SecurityLanes.ARCH)
	var cell_x := _world.grid.cell_to_world(ANCHOR).x
	assert_float(hint.position.x).is_equal_approx(cell_x, 0.6)
	assert_float(hint.position.y).is_greater(def.height)
	# Only the two staff-spot reasons are never hidden by the caption layout; a
	# lane hint hides when it overlaps, like "Closed" and "Queue full".
	for status: int in SecurityLanes.STATUS_TEXT:
		assert_bool(MissMarkers.is_staff_spot_caption(SecurityLanes.STATUS_TEXT[status])).is_false()


func test_completing_the_lane_drops_the_hint_at_once() -> void:
	_attach([SecurityLanes.XRAY_BELT])
	var hint := _markers.hint_sign_for(_arch)
	assert_object(hint).is_not_null()
	var belt_cell: Vector2i = SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["xray_belt"]
	PassengerTestWorld.place(_world.grid, SecurityLanes.XRAY_BELT, belt_cell, 0)
	assert_bool(_world.sim.layout.security_lanes.is_complete(_arch)).is_true()
	assert_object(_markers.hint_sign_for(_arch)).is_null()
	assert_bool(hint.visible).is_false()
	assert_str(_markers.hint_text(_arch)).is_empty()


func test_removing_a_part_shows_the_hint_at_once() -> void:
	_attach()
	assert_object(_markers.hint_sign_for(_arch)).is_null()
	var pickup := _world.grid.object_at(
		SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["pickup_table"]
	)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(pickup)).ok).is_true()
	assert_str(_markers.hint_text(_arch)).is_equal(SecurityLanes.STATUS_TEXT[S.NO_PICKUP_TABLE])


func test_a_whole_lane_with_nobody_on_duty_shows_closed_not_a_hint() -> void:
	_attach()
	assert_bool(_world.sim.layout.security_lanes.is_complete(_arch)).is_true()
	assert_array(MissSignals.closed_stations(_world.sim)).is_equal([_arch])
	assert_object(_markers.hint_sign_for(_arch)).is_null()
	assert_object(_markers.closed_sign_for(_arch)).is_not_null()
	assert_str(_markers.closed_text(_arch)).is_equal(MissMarkers.CLOSED_CAPTION)


func test_a_staffed_whole_lane_shows_no_closed_sign_and_no_hint() -> void:
	_attach([], [], Vector2i(-1, -1), true)
	_world.step()
	assert_array(MissSignals.closed_stations(_world.sim)).is_empty()
	assert_object(_markers.closed_sign_for(_arch)).is_null()
	assert_object(_markers.hint_sign_for(_arch)).is_null()


func test_a_whole_lane_with_a_full_queue_shows_the_queue_full_sign() -> void:
	_attach([], [], Vector2i(-1, -1), true)
	var entry: Vector2i = SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["queue_entry"]
	var capacity := (_world.sim.layout.lanes[_arch] as Array).size()
	for i in capacity + 2:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = entry
		p.clear_path()
	var limit := _world.clock.tick + 200
	while not MissSignals.full_stations(_world.sim).has(_arch) and _world.clock.tick < limit:
		_world.step()
	assert_bool(MissSignals.full_stations(_world.sim).has(_arch)).is_true()
	assert_int(_world.sim.queue_of(_arch).size()).is_equal(capacity)
	assert_object(_markers.sign_for(_arch)).is_not_null()
	assert_str(_markers.sign_text(_arch)).starts_with("Queue full")
	assert_object(_markers.hint_sign_for(_arch)).is_null()


func test_an_incomplete_arch_shows_nothing_while_lanes_are_off() -> void:
	SecurityLanes.enabled = false
	_attach([SecurityLanes.XRAY_BELT])
	# The control: the layout still recognises the arch as incomplete, so only
	# the flag keeps every helper silent.
	assert_int(_world.sim.layout.security_lanes.status(_arch)).is_equal(S.NO_XRAY_BELT)
	assert_array(MissSignals.incomplete_arches(_world.sim)).is_empty()
	assert_str(MissSignals.lane_hint(_world.sim, _arch)).is_empty()
	assert_object(_markers.hint_sign_for(_arch)).is_null()
	assert_str(_markers.hint_text(_arch)).is_empty()
	SecurityLanes.enabled = true
	assert_array(MissSignals.incomplete_arches(_world.sim)).is_equal([_arch])
	assert_str(MissSignals.lane_hint(_world.sim, _arch)).is_equal(
		SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT]
	)
