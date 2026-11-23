class_name TestDeparturesBoardLateRevision
extends GdUnitTestSuite
## The departures board's late-count cache is keyed on PassengerSim.revision, an
## O(1) counter of passenger-state changes, not on a scan of every passenger
## (board 6c08350c). A change inside one tick, which the old signature of tick,
## size and end objects could not see, moves the revision and so the counts.

var _world: PassengerTestWorld
var _board: DeparturesBoard


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_late_revision")
	_board.flights = _world.flights
	_board.clock = _world.clock
	_board.passengers = _world.sim
	add_child(_board)
	_board.set_shown(true)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_world.free_all()


func test_revision_moves_on_a_spawn_a_tick_a_stage_and_a_mark() -> void:
	var sim := _world.sim
	var seen := sim.revision
	var id := sim.spawn_now(PassengerTestWorld.FLIGHT)
	assert_int(sim.revision).is_greater(seen)
	seen = sim.revision
	_world.step()
	assert_int(sim.revision).is_greater(seen)
	seen = sim.revision
	sim._set_stage(_world.passenger(id), Passenger.Stage.MISSED)
	assert_int(sim.revision).is_greater(seen)
	seen = sim.revision
	sim.mark_changed()
	assert_int(sim.revision).is_greater(seen)
	# Control: reading changes nothing.
	seen = sim.revision
	sim.passenger_ids()
	sim.made_count()
	assert_int(sim.revision).is_equal(seen)


func test_revision_moves_on_a_snapshot_load_at_the_same_tick() -> void:
	var sim := _world.sim
	sim.spawn_now(PassengerTestWorld.FLIGHT)
	var data := sim.to_snapshot()
	var seen := sim.revision
	assert_bool(sim.from_snapshot(data)).is_true()
	assert_int(sim.revision).is_greater(seen)


func test_the_board_sees_a_late_flag_and_a_stage_change_inside_one_tick() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)
	var tick := _world.sim.tick
	p.late = true
	_world.sim.mark_changed()
	_board.refresh()
	var late_now := _board.late_count_of(PassengerTestWorld.FLIGHT)
	print("late flag: tick ", tick, " -> ", _world.sim.tick, " count ", late_now)
	assert_int(_world.sim.tick).is_equal(tick)
	assert_int(late_now).is_equal(1)
	_world.sim._set_stage(p, Passenger.Stage.MISSED)
	_board.refresh()
	assert_int(_world.sim.tick).is_equal(tick)
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)


func test_the_cache_is_keyed_on_the_revision_not_on_a_passenger_scan() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	p.late = true
	_world.sim.mark_changed()
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	# A raw field write nobody announced: the board keeps the count it read.
	p.late = false
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	# The announcement is what makes it re-read.
	_world.sim.mark_changed()
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)


func test_reassigning_same_passengers_preserves_late_and_progress_cache() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	p.late = true
	_world.sim.mark_changed()
	_board.refresh()
	var late_key := _board._late_key.duplicate()
	var progress_key := _board._progress_key.duplicate()
	assert_array(late_key).is_not_empty()
	assert_array(progress_key).is_not_empty()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	assert_int(int(_board._progress.get("boarded", {}).get(PassengerTestWorld.FLIGHT, 0))).is_equal(
		0
	)
	# Reassigning the same PassengerSim without changing revision must not clear keys or rescan.
	p.late = false
	_world.sim.flight_results[PassengerTestWorld.FLIGHT] = {"made": 1, "missed": 0}
	for i in 3:
		_board.passengers = _world.sim
		assert_array(_board._late_key).is_equal(late_key)
		assert_array(_board._progress_key).is_equal(progress_key)
		_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	assert_int(int(_board._progress.get("boarded", {}).get(PassengerTestWorld.FLIGHT, 0))).is_equal(
		0
	)
	_world.sim.mark_changed()
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)
	assert_int(int(_board._progress.get("boarded", {}).get(PassengerTestWorld.FLIGHT, 0))).is_equal(
		1
	)
