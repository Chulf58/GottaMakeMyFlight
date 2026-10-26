class_name TestMissMarkers
extends GdUnitTestSuite
## The queue-full sign over a station and the late badge over a passenger,
## drawn by the MissMarkers child of PassengerViews.

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


func _attach(world: PassengerTestWorld) -> void:
	_world = world
	_views = PassengerViews.new()
	_views.clock = world.clock
	_views.sim = world.sim
	add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


## One desk whose lane holds exactly 3, as in TestMissSignals.
func _short_lane_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"desk", desk)
	return world


func _tight_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	return PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(200, 400))


func _spawn_spaced(count: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		_world.run_to(_world.clock.tick + 12)


func _desk_centre(desk: int) -> Vector3:
	var record := _world.grid.get_object(desk)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	return BuildView.object_transform(_world.grid, cells, record["facing"]).origin


func test_a_full_desk_gets_a_sign_above_it() -> void:
	_attach(_short_lane_world())
	var desk: int = _world.sim.get_meta(&"desk")
	assert_object(_markers.sign_for(desk)).is_null()
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	assert_bool(sign.visible).is_true()
	assert_str(_markers.sign_text(desk)).is_equal("Queue full")
	var centre := _desk_centre(desk)
	var flat := Vector2(sign.position.x, sign.position.z)
	assert_float(flat.distance_to(Vector2(centre.x, centre.z))).is_less(0.001)
	assert_float(sign.position.y).is_greater(BuildCatalog.get_def(&"checkin_desk").height)


func test_the_sign_caption_counts_the_passengers_held_outside_the_lane() -> void:
	_attach(_short_lane_world())
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(5)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(2)
	assert_str(_markers.sign_text(desk)).is_equal("Queue full · +2 waiting")


func test_the_sign_goes_when_the_queue_drains() -> void:
	_attach(_short_lane_world())
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	_world.run_to(_world.clock.tick + 3 * PassengerSim.CHECKIN_TICKS + 40)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(0)
	assert_object(_markers.sign_for(desk)).is_null()
	assert_bool(sign.visible).is_false()
	# The next full queue reuses the pooled sign and shows it again.
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	assert_object(_markers.sign_for(desk)).is_same(sign)
	assert_bool(sign.visible).is_true()
	assert_str(_markers.sign_text(desk)).is_equal("Queue full")


func test_a_desk_removed_while_paused_loses_its_sign_on_the_next_frame() -> void:
	_attach(_short_lane_world())
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	var tick := _world.clock.tick
	assert_bool(_world.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	_views.draw()
	assert_int(_world.clock.tick).is_equal(tick)
	assert_object(_markers.sign_for(desk)).is_null()
	assert_bool(sign.visible).is_false()


func test_a_late_badge_rides_above_the_drawn_passenger() -> void:
	_attach(_tight_world())
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(PassengerSim.BEAT_TICKS + 8)
	assert_bool(_world.passenger(id).late).is_true()
	# The passenger is moving, so the drawn position lies between two ticks.
	var before := _views.tick_position(id, false)
	assert_float(before.distance_to(_views.tick_position(id, true))).is_greater(0.05)
	_world.clock.advance(SimClock.STEP * 0.5)
	_views.draw()
	var badge := _markers.badge_for(id)
	assert_object(badge).is_not_null()
	assert_bool(badge.visible).is_true()
	var head := _views.node_for(id).position + Vector3(0.0, MissMarkers.HEAD_M, 0.0)
	assert_float(badge.position.distance_to(head)).is_less(0.001)
	var lift := Vector3(0.0, MissMarkers.HEAD_M, 0.0)
	assert_float(badge.position.distance_to(before + lift)).is_greater(0.02)


func test_a_missed_passenger_returns_its_badge_to_the_pool() -> void:
	_attach(_tight_world())
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(PassengerSim.BEAT_TICKS + 2)
	var badge := _markers.badge_for(id)
	assert_object(badge).is_not_null()
	assert_int(_markers.free_badge_count()).is_equal(0)
	_world.run_to(420)
	assert_int(_world.passenger(id).stage).is_equal(Passenger.Stage.MISSED)
	assert_object(_markers.badge_for(id)).is_null()
	assert_bool(badge.visible).is_false()
	assert_int(_markers.free_badge_count()).is_equal(1)


func test_badge_size_keeps_a_readable_floor_and_ceiling() -> void:
	# fov 55 on a 1080-pixel-high view: 0.6 m is 20 px at about 31 m.
	assert_float(MissMarkers.badge_px(5.0, 55.0, 1080.0)).is_equal(MissMarkers.LATE_MAX_PX)
	assert_float(MissMarkers.badge_px(200.0, 55.0, 1080.0)).is_equal(MissMarkers.LATE_MIN_PX)
	assert_float(MissMarkers.badge_px(31.1, 55.0, 1080.0)).is_equal_approx(20.0, 0.1)
	assert_float(MissMarkers.badge_px(0.0, 55.0, 1080.0)).is_equal(MissMarkers.LATE_MAX_PX)
