class_name TestStarterTerminal
extends GdUnitTestSuite
## The starter terminal inside the Toon shell: its entrance stands on landside
## door B and its exit on gate C, so passengers walk the doors' real routes.

const SHELL := preload("res://build/toon_terminal_shell.tres")
const LANDSIDE_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)
const LAST_TICK := 1900

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SHELL.grid_size, SHELL.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, SHELL)).is_true()
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shell = SHELL


func after_test() -> void:
	_world.free_all()
	_world = null


func test_the_entrance_is_on_door_b_and_the_exit_on_gate_c() -> void:
	var ids := ReferenceTerminal.object_ids(_world.grid)
	assert_int(ids["entrances"].size()).is_equal(1)
	assert_int(ids["exits"].size()).is_equal(1)
	var entrance := _world.grid.get_object(ids["entrances"][0])
	var exit_door := _world.grid.get_object(ids["exits"][0])
	assert_that(entrance["anchor"]).is_equal(LANDSIDE_B)
	assert_that(exit_door["anchor"]).is_equal(GATE_C)
	var door_b := SHELL.connection_for(&"entrance_door", entrance["anchor"], entrance["facing"])
	var gate_c := SHELL.connection_for(&"exit_door", exit_door["anchor"], exit_door["facing"])
	assert_str(door_b.label if door_b != null else "").is_equal("B")
	assert_str(gate_c.label if gate_c != null else "").is_equal("C")


func test_both_doors_pass_the_shell_door_rules() -> void:
	for object_id in _world.grid.object_ids():
		var record := _world.grid.get_object(object_id)
		if not BuildCatalog.is_door(record["def"]):
			continue
		var connection := SHELL.connection_for(record["def"], record["anchor"], record["facing"])
		assert_object(connection).is_not_null()
		var side := BuildGrid.SIDE_STEP.find(DoorPlacement.back_step(record["facing"]))
		assert_int(_world.grid.wall_kind(record["anchor"], side)).is_equal(BuildGrid.WallKind.NONE)


func test_a_passenger_walks_the_real_routes_and_makes_the_flight() -> void:
	var entrance: int = ReferenceTerminal.object_ids(_world.grid)["entrances"][0]
	assert_bool(ShellRoutes.arrival(_world.sim, entrance).size() > 2).is_true()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(LAST_TICK)
	assert_int(_world.passenger(id).stage).is_equal(Passenger.Stage.MADE)


func test_without_a_shell_the_layout_is_the_reference_one() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var ids := ReferenceTerminal.object_ids(grid)
	assert_that(grid.get_object(ids["entrances"][0])["anchor"]).is_equal(
		ReferenceTerminal.ENTRANCE_CELL
	)
	assert_that(grid.get_object(ids["exits"][0])["anchor"]).is_equal(ReferenceTerminal.EXIT_CELL)
