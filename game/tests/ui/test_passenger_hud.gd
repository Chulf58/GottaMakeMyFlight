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


func test_speed_buttons_set_the_clock() -> void:
	_hud.press_speed(3)
	assert_int(_world.clock.speed).is_equal(3)
	assert_bool(_world.clock.paused).is_false()
	_hud.press_speed(0)
	assert_bool(_world.clock.paused).is_true()
