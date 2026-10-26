class_name TestPassengerHud
extends GdUnitTestSuite
## The made/missed HUD and the debug spawn button.

var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_world.free_all()


func test_counts_show_made_and_missed_after_doors_close() -> void:
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_hud.refresh()
	assert_str(_hud.counts_text()).is_equal("Made 0   Missed 0   In terminal 1")
	_world.run_to(21)
	_hud.refresh()
	assert_str(_hud.counts_text()).is_equal("Made 0   Missed 1   In terminal 0")
	assert_str(_hud.flight_text()).contains("GMF101")
	assert_str(_hud.flight_text()).contains("Doors closed")


func test_debug_button_spawns_300_and_shows_the_seed() -> void:
	_hud.press_debug_spawn()
	assert_int(_world.sim.pending_spawns()).is_equal(300)
	var seed := _world.sim.last_batch_seed
	assert_str(_hud.seed_text()).is_equal("Debug batch: 300 passengers, seed %d" % seed)


func test_a_refused_debug_batch_leaves_no_seed_and_says_why() -> void:
	_world.run_to(21)
	assert_bool(_world.flights.is_doors_closed(PassengerTestWorld.FLIGHT)).is_true()
	_hud.press_debug_spawn()
	assert_int(_world.sim.pending_spawns()).is_equal(0)
	assert_int(_world.sim.last_batch_seed).is_equal(0)
	_hud.refresh()
	assert_str(_hud.seed_text()).is_equal("")
	assert_str(_hud.status_text()).contains("no flight is open")


func test_a_spawned_debug_batch_replaces_an_earlier_refusal() -> void:
	_world.run_to(21)
	_hud.press_debug_spawn()
	assert_str(_hud.status_text()).contains("no flight is open")
	var later := PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(8, 6)), PassengerTestWorld.starts_with(100, 200)
	)
	_hud.clock = later.clock
	_hud.flights = later.flights
	_hud.sim = later.sim
	_hud.press_debug_spawn()
	assert_int(later.sim.pending_spawns()).is_equal(300)
	assert_str(_hud.status_text()).is_equal("Spawned 300 passengers")
	assert_str(_hud.seed_text()).contains("seed %d" % later.sim.last_batch_seed)
	later.free_all()


func test_a_refusal_after_a_spawned_batch_keeps_the_earlier_seed() -> void:
	_hud.press_debug_spawn()
	var seed := _world.sim.last_batch_seed
	assert_int(seed).is_not_equal(0)
	_world.run_to(21)
	_hud.press_debug_spawn()
	assert_int(_world.sim.last_batch_seed).is_equal(seed)
	assert_str(_hud.status_text()).contains("no flight is open")
	_hud.refresh()
	assert_str(_hud.seed_text()).is_equal("Debug batch: 300 passengers, seed %d" % seed)


func test_speed_buttons_set_the_clock() -> void:
	_hud.press_speed(3)
	assert_int(_world.clock.speed).is_equal(3)
	assert_bool(_world.clock.paused).is_false()
	_hud.press_speed(0)
	assert_bool(_world.clock.paused).is_true()


func _build_mode(size: Vector2i) -> BuildMode:
	var mode := BuildMode.new()
	mode.grid_size = size
	add_child(mode)
	auto_free(mode)
	_hud.build_mode = mode
	return mode


func test_starter_terminal_builds_on_a_pristine_grid() -> void:
	var mode := _build_mode(BuildGrid.DEFAULT_SIZE)
	_hud.press_starter_terminal()
	assert_int(mode.grid.object_ids().size()).is_greater(0)
	assert_str(_hud.status_text()).is_equal("Starter terminal built")


func test_starter_terminal_refuses_a_painted_grid_and_says_so() -> void:
	var mode := _build_mode(BuildGrid.DEFAULT_SIZE)
	mode.grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	var before := JSON.stringify(mode.grid.to_snapshot())
	_hud.press_starter_terminal()
	assert_str(JSON.stringify(mode.grid.to_snapshot())).is_equal(before)
	assert_str(_hud.status_text()).contains("empty")
	mode.grid.apply(BuildEdit.remove_floor(Vector2i(3, 3)))
	var wall := mode.grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.NORTH))
	assert_bool(wall.ok).is_true()
	before = JSON.stringify(mode.grid.to_snapshot())
	_hud.press_starter_terminal()
	assert_str(JSON.stringify(mode.grid.to_snapshot())).is_equal(before)


func test_starter_terminal_refuses_a_grid_with_objects_and_says_so() -> void:
	var mode := _build_mode(BuildGrid.DEFAULT_SIZE)
	for y in range(2, 7):
		for x in range(2, 7):
			mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var desk := mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0))
	assert_bool(desk.ok).is_true()
	_hud.press_starter_terminal()
	assert_int(mode.grid.object_ids().size()).is_equal(1)
	assert_str(_hud.status_text()).contains("empty")


func test_starter_terminal_failure_is_reported_in_the_status() -> void:
	_build_mode(Vector2i(8, 6))
	_hud.press_starter_terminal()
	assert_str(_hud.status_text()).contains("failed")
