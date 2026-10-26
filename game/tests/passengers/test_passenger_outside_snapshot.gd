class_name TestPassengerOutsideSnapshot
extends GdUnitTestSuite
## Loading a save whose passenger is on its walk outside (save_version 3,
## [x, y, z] points): a well-formed one loads, and one with progress past the
## end of the walk, a non-finite or out-of-world point, or the old version 2
## is refused and leaves the sim exactly as it was.

const SHELL := preload("res://build/toon_terminal_shell.tres")
const ROAD_TICKS := 30

var _source: PassengerTestWorld
var _target: PassengerTestWorld
## The source's save, taken with its passenger on the road.
var _saved: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_source = _shell_world()
	_source.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_source.run_to(ROAD_TICKS)
	_saved = JSON.parse_string(JSON.stringify(_source.sim.to_snapshot())) as Dictionary
	# The target has state of its own, so a refused load has something to keep.
	_target = _shell_world()
	_target.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_target.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_target.run_to(12)


func after_test() -> void:
	_source.free_all()
	_target.free_all()


func _shell_world() -> PassengerTestWorld:
	var grid := BuildGrid.new(SHELL.grid_size, SHELL.grid_origin)
	for y in SHELL.grid_size.y:
		for x in range(15, 18):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(16, 29), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(16, 0), 0)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.sim.shell = SHELL
	return world


func _record() -> Dictionary:
	return (_saved["passengers"] as Array)[0]


## Loads `data` into the target and checks it is refused with nothing changed.
func _assert_refused(data: Dictionary) -> void:
	var before_load := _target.signature()
	var before_tick := _target.sim.tick
	assert_bool(_target.sim.from_snapshot(data)).is_false()
	assert_str(_target.signature()).is_equal(before_load)
	assert_int(_target.sim.tick).is_equal(before_tick)


func test_a_save_on_the_road_loads() -> void:
	var p := _source.passenger(1)
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_int(int(_record()["apron_mm"])).is_greater(0)
	assert_bool(_target.sim.from_snapshot(_saved)).is_true()
	assert_vector(_target.sim.world_position(_target.passenger(1))).is_equal_approx(
		_source.sim.world_position(p), Vector3.ONE * 1e-4
	)


func test_progress_past_the_end_of_the_walk_is_refused() -> void:
	var total := _source.passenger(1).apron_total_mm()
	_record()["apron_mm"] = total + 1
	_assert_refused(_saved)


func test_non_finite_points_are_refused() -> void:
	for bad in [INF, -INF, NAN]:
		var data := _saved.duplicate(true)
		(data["passengers"][0]["apron"][1] as Array)[1] = bad
		_assert_refused(data)


func test_points_outside_the_world_are_refused() -> void:
	var data := _saved.duplicate(true)
	(data["passengers"][0]["apron"][0] as Array)[0] = BuildGrid.MAX_ORIGIN_M + 1.0
	_assert_refused(data)


func test_two_number_points_are_refused() -> void:
	var data := _saved.duplicate(true)
	data["passengers"][0]["apron"][0] = [-17.0, -57.0]
	_assert_refused(data)


func test_a_version_2_save_is_refused() -> void:
	var data := _saved.duplicate(true)
	data["save_version"] = 2
	_assert_refused(data)
