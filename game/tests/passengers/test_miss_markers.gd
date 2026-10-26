class_name TestMissMarkers
extends GdUnitTestSuite
## The queue-full sign over a full station, drawn by the MissMarkers child
## of PassengerViews.

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


func test_a_desk_removed_while_paused_loses_its_sign_at_once() -> void:
	_attach(_short_lane_world())
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	var tick := _world.clock.tick
	assert_bool(_world.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	assert_int(_world.clock.tick).is_equal(tick)
	assert_object(_markers.sign_for(desk)).is_null()
	assert_bool(sign.visible).is_false()


## One desk on a longer floor: its lane runs y 2 to 6 (5 cells), or y 2 to 4
## (3 cells) while a wall closes the south edge of (2, 4).
func _walled_lane_world(walled: bool) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(6, 7))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 6), 3)
	if walled:
		grid.apply(BuildEdit.place_wall(Vector2i(2, 4), BuildGrid.Side.SOUTH))
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"desk", desk)
	return world


func test_a_lane_lengthened_while_paused_drops_its_sign_at_once() -> void:
	_attach(_walled_lane_world(true))
	var desk: int = _world.sim.get_meta(&"desk")
	assert_int(_world.sim.layout.lanes[desk].size()).is_equal(3)
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 30)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	var tick := _world.clock.tick
	var opened := _world.grid.apply(BuildEdit.remove_wall(Vector2i(2, 4), BuildGrid.Side.SOUTH))
	assert_bool(opened.ok).is_true()
	assert_int(_world.sim.layout.lanes[desk].size()).is_equal(5)
	assert_int(_world.clock.tick).is_equal(tick)
	assert_object(_markers.sign_for(desk)).is_null()
	assert_bool(sign.visible).is_false()


func test_a_lane_shortened_while_paused_shows_its_sign_at_once() -> void:
	_attach(_walled_lane_world(false))
	var desk: int = _world.sim.get_meta(&"desk")
	assert_int(_world.sim.layout.lanes[desk].size()).is_equal(5)
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 30)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	assert_object(_markers.sign_for(desk)).is_null()
	var tick := _world.clock.tick
	var closed := _world.grid.apply(BuildEdit.place_wall(Vector2i(2, 4), BuildGrid.Side.SOUTH))
	assert_bool(closed.ok).is_true()
	assert_int(_world.sim.layout.lanes[desk].size()).is_equal(3)
	assert_int(_world.clock.tick).is_equal(tick)
	var sign := _markers.sign_for(desk)
	assert_object(sign).is_not_null()
	assert_bool(sign.visible).is_true()
	assert_str(_markers.sign_text(desk)).is_equal("Queue full")
