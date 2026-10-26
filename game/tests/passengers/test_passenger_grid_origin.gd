class_name TestPassengerGridOrigin
extends GdUnitTestSuite
## A passenger walking the reference terminal built on the shell grid (66x30
## at (-33.5, 0.3, -94.8)) stands at the grid's floor height and over the
## cell the sim says it is on, from the entrance to the exit door.

const SHELL_SIZE := Vector2i(66, 30)
const SHELL_ORIGIN := Vector3(-33.5, 0.3, -94.8)
const LAST_TICK := 3000

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_a_passenger_walks_the_terminal_in_the_grid_frame() -> void:
	var grid := BuildGrid.new(SHELL_SIZE, SHELL_ORIGIN)
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	var samples := 0
	var on_cell := 0
	var cells := {}
	while _world.clock.tick < LAST_TICK and p.stage < Passenger.Stage.APRON:
		_world.step()
		if p.stage >= Passenger.Stage.APRON or not grid.in_bounds(p.at):
			continue
		var at := _world.sim.world_position(p)
		samples += 1
		assert_float(at.y).is_equal_approx(SHELL_ORIGIN.y, 0.0001)
		var under := grid.world_to_cell(at)
		assert_int(maxi(absi(under.x - p.at.x), absi(under.y - p.at.y))).is_less_equal(1)
		if under == p.at:
			on_cell += 1
		cells[p.at] = true
	assert_int(p.stage).is_greater_equal(Passenger.Stage.APRON)
	assert_int(samples).is_greater(100)
	# Mid-step a walker is drawn between two cells, so only some samples sit
	# on p.at. The within-one-cell check above is the frame test; this one
	# proves the walker was seen standing on its own cell, not just near it.
	assert_int(on_cell).is_greater(100)
	assert_bool(cells.has(ReferenceTerminal.ENTRANCE_CELL)).is_true()
	assert_int(cells.size()).is_greater(15)
