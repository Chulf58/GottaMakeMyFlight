class_name TestQueueFrontUnreachable
extends GdUnitTestSuite
## A queued passenger who can no longer walk to its lane cell must not block
## the passengers behind it.

const SEALED := Vector2i(5, 4)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _run_until(stage: Passenger.Stage, id: int, limit: int) -> bool:
	var guard := 0
	while _world.passenger(id).stage != stage and guard < limit:
		_world.step()
		guard += 1
	return _world.passenger(id).stage == stage


func test_stranded_queuer_is_requeued_and_the_desk_keeps_serving() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	grid.apply(BuildEdit.place_wall(SEALED, BuildGrid.Side.WEST))
	grid.apply(BuildEdit.place_wall(SEALED, BuildGrid.Side.NORTH))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var first := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	assert_bool(_run_until(Passenger.Stage.CHECKIN, first, 400)).is_true()
	var stranded := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var guard := 0
	while (
		guard < 400
		and not (
			_world.passenger(stranded).stage == Passenger.Stage.CHECKIN_QUEUE
			and not _world.passenger(stranded).is_moving()
		)
	):
		_world.step()
		guard += 1
	assert_int(_world.passenger(stranded).stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	# An edit leaves the passenger standing where no path leads back to the lane.
	_world.passenger(stranded).clear_path()
	_world.passenger(stranded).at = SEALED
	_world.run_to(_world.clock.tick + 200)
	assert_array(_world.sim.queue_of(desk)).not_contains([stranded])
	assert_int(_world.passenger(stranded).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	var third := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	assert_bool(_run_until(Passenger.Stage.CHECKIN, third, 400)).is_true()
