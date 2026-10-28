class_name TestPassengerJourney
extends GdUnitTestSuite
## The whole journey: security cannot be bypassed, stuck reasons, made and
## missed at doors close, exits, and path invalidation after an edit.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _spawn_many(count: int, every: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_world.run_to(_world.clock.tick + every)
	return ids


## Even with a gap beside the scanners, nobody reaches the airside rows
## (y <= ReferenceTerminal.AIRSIDE_MAX_Y) without being cleared by a scanner.
func test_routing_cannot_bypass_security() -> void:
	_world = PassengerTestWorld.reference_world()
	var gap := Vector2i(12, ReferenceTerminal.DIVIDER_Y)
	assert_bool(_world.grid.apply(BuildEdit.remove_wall(gap, BuildGrid.Side.NORTH)).ok).is_true()
	assert_bool(_world.grid.find_path(Vector2i(12, 12), Vector2i(12, 5)).is_empty()).is_false()
	var ids := _spawn_many(8, 15)
	var airside_seen := 0
	while _world.clock.tick < 1900:
		_world.step()
		for id in ids:
			var p := _world.passenger(id)
			if p == null:
				continue  # settled long ago and retired
			# The scanner footprint reaches the airside row; its passenger is mid-service.
			if p.stage in [Passenger.Stage.SECURITY, Passenger.Stage.APRON, Passenger.Stage.MADE]:
				continue
			if p.at.y <= ReferenceTerminal.AIRSIDE_MAX_Y:
				airside_seen += 1
				(
					assert_bool(p.cleared)
					. override_failure_message(
						"passenger %d at %s is airside without clearance" % [id, p.at]
					)
					. is_true()
				)
	assert_int(airside_seen).is_greater(0)
	assert_int(_world.sim.made_count()).is_equal(8)


func test_without_a_scanner_nobody_reaches_the_gate() -> void:
	_world = PassengerTestWorld.reference_world()
	for id in ReferenceTerminal.object_ids(_world.grid)["scanners"]:
		_world.grid.apply(BuildEdit.remove_object(id))
	var ids := _spawn_many(2, 10)
	_world.run_to(600)
	for id in ids:
		var p := _world.passenger(id)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
		assert_int(p.stuck).is_equal(Passenger.Stuck.NO_SECURITY)
		assert_bool(p.cleared).is_false()
	_world.run_to(1900)
	for id in ids:
		assert_int(_world.passenger(id).stage).is_equal(Passenger.Stage.MISSED)
		assert_int(_world.passenger(id).seat_object).is_equal(0)


func test_no_desk_gives_no_checkin_and_a_walled_desk_gives_no_route() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var lost := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	assert_int(_world.passenger(lost).stuck).is_equal(Passenger.Stuck.NO_CHECKIN)
	assert_str(_world.sim.bubble_text(_world.passenger(lost))).is_equal("Where is check-in?")
	# The wall goes up first: once the desk stands, a wall cutting its staff spot
	# off from the entrance is refused (decision
	# desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3). A
	# second entrance behind the wall lets staff reach the desk, so it is open;
	# passengers still arrive through the first.
	for y in 6:
		grid.apply(BuildEdit.place_wall(Vector2i(4, y), BuildGrid.Side.WEST))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(7, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 1), 0)
	var blocked := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(_world.clock.tick + 21)
	assert_int(_world.passenger(blocked).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(_world.passenger(lost).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	# Opening the wall lets both retry on their own and reach the desk lane.
	grid.apply(BuildEdit.remove_wall(Vector2i(4, 3), BuildGrid.Side.WEST))
	_world.run_to(_world.clock.tick + 120)
	assert_int(_world.passenger(blocked).stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(_world.passenger(blocked).stage).is_greater_equal(Passenger.Stage.CHECKIN_QUEUE)


func test_made_before_doors_close_and_missed_at_doors_close() -> void:
	_world = PassengerTestWorld.reference_world()
	var early: Array[Passenger] = []
	for id in _spawn_many(3, 20):
		early.append(_world.passenger(id))
	_world.run_to(1700)
	var late := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_world.run_to(1899)
	# The early three are made and retired by now, so they are held here.
	for p in early:
		assert_int(p.stage).is_equal(Passenger.Stage.MADE)
		assert_int(p.outcome_tick).is_less(1900)
	assert_int(late.stage).is_not_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.missed_count()).is_equal(0)
	_world.step()
	assert_int(late.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(late.outcome_tick).is_equal(1900)
	assert_int(_world.sim.made_count()).is_equal(3)
	assert_int(_world.sim.missed_count()).is_equal(1)


func test_exit_blocked_when_the_exit_is_gone_or_walled() -> void:
	_world = PassengerTestWorld.reference_world()
	var exit_id: int = ReferenceTerminal.object_ids(_world.grid)["exits"][0]
	var exit_cell := ReferenceTerminal.EXIT_CELL
	_world.grid.apply(BuildEdit.place_wall(exit_cell, BuildGrid.Side.NORTH))
	var walled := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(760)
	assert_int(_world.passenger(walled).stuck).is_equal(Passenger.Stuck.EXIT_BLOCKED)
	assert_str(_world.sim.bubble_text(_world.passenger(walled))).is_equal("The exit is blocked")
	_world.grid.apply(BuildEdit.remove_wall(exit_cell, BuildGrid.Side.NORTH))
	_world.run_to(800)
	assert_int(_world.passenger(walled).stuck).is_equal(Passenger.Stuck.NONE)
	assert_int(_world.passenger(walled).stage).is_greater_equal(Passenger.Stage.TO_EXIT)
	_world.grid.apply(BuildEdit.remove_object(exit_id))
	var other := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(1100)
	assert_int(_world.passenger(other).stuck).is_equal(Passenger.Stuck.EXIT_BLOCKED)


## A diagonal step a -> b depends on its two corner cells. A door on a corner
## blocks the step although neither a nor b changed, so invalidation must use
## the relinked neighbourhood, not the dirty cells.
func test_an_edit_beside_a_diagonal_step_replans_the_committed_path() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(8, 7), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var p := _world.passenger(id)
	var i := _last_diagonal(p)
	assert_int(i).is_greater_equal(p.path_index + 3)
	var a := p.path[i]
	var b := p.path[i + 1]
	var corner := Vector2i(b.x, a.y)
	var facing := 0
	if p.path.has(corner):
		corner = Vector2i(a.x, b.y)
		facing = 1
	assert_bool(p.path.has(corner)).is_false()
	assert_bool(grid.apply(BuildEdit.place_object(&"exit_door", corner, facing)).ok).is_true()
	assert_bool(grid.can_step(a, b)).is_false()
	_world.run_to(_world.clock.tick + 2)
	assert_bool(_has_step(p, a, b)).is_false()
	_world.run_to(_world.clock.tick + 200)
	assert_int(p.stage).is_greater_equal(Passenger.Stage.CHECKIN_QUEUE)


func _last_diagonal(p: Passenger) -> int:
	for i in range(p.path.size() - 2, p.path_index - 1, -1):
		var d := p.path[i + 1] - p.path[i]
		if d.x != 0 and d.y != 0:
			return i
	return -1


func _has_step(p: Passenger, a: Vector2i, b: Vector2i) -> bool:
	for i in range(p.path_index, p.path.size() - 1):
		if p.path[i] == a and p.path[i + 1] == b:
			return true
	return false
