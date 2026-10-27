class_name TestPassengerRetirement
extends GdUnitTestSuite
## A settled passenger is kept for SETTLED_KEEP_TICKS (the missed ones stay
## drawn that long) and then retired. The made and missed totals and each
## flight's results are durable, and a retired passenger holds no station, seat
## claim, cafe visit or queue place.

var _world: PassengerTestWorld
## Passenger id -> the tick it was made or missed.
var _outcomes: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _on_outcome(id: int, _made: bool) -> void:
	_outcomes[id] = _world.clock.tick


## Six passengers at the start, then two at tick 1890 who cannot make the plane.
func _reference(count: int) -> Array[int]:
	_world = PassengerTestWorld.reference_world(7)
	_outcomes.clear()
	_world.sim.outcome.connect(_on_outcome)
	var ids: Array[int] = []
	for i in count:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	return ids


func _late(count: int) -> Array[int]:
	_world.run_to(1890)
	var ids: Array[int] = []
	for i in count:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	return ids


func test_settled_passengers_are_kept_for_a_while_then_retired() -> void:
	var ids := _reference(6)
	ids.append_array(_late(2))
	var kept_once := 0
	while _world.clock.tick < 2300:
		_world.step()
		for id in ids:
			if not _outcomes.has(id):
				assert_object(_world.passenger(id)).is_not_null()
				continue
			var kept: bool = _world.clock.tick - _outcomes[id] <= PassengerSim.SETTLED_KEEP_TICKS
			if kept:
				kept_once += 1
			assert_bool(_world.passenger(id) != null).is_equal(kept)
	assert_int(_outcomes.size()).is_equal(8)
	assert_int(kept_once).is_greater(0)
	assert_int(_world.sim.made_count()).is_greater(0)
	assert_int(_world.sim.made_count() + _world.sim.missed_count()).is_equal(8)
	assert_int(_world.sim.passenger_ids().size()).is_equal(0)
	assert_int(_world.sim.active_count()).is_equal(0)


func test_totals_and_flight_results_survive_retirement() -> void:
	var ids := _reference(6)
	ids.append_array(_late(2))
	_world.run_to(1950)
	var made := _world.sim.made_count()
	var missed := _world.sim.missed_count()
	assert_int(missed).is_greater(0)
	var before := FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)
	assert_int(before["made"]).is_equal(made)
	assert_int(before["missed"]).is_equal(missed)
	_world.run_to(1900 + PassengerSim.SETTLED_KEEP_TICKS + 5)
	assert_int(_world.sim.passenger_ids().size()).is_equal(0)
	assert_int(_world.sim.made_count()).is_equal(made)
	assert_int(_world.sim.missed_count()).is_equal(missed)
	var after := FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)
	assert_dict(after).is_equal(before)


func test_passengers_still_on_their_way_are_never_retired() -> void:
	var ids := _reference(2)
	_world.run_to(300)
	for id in ids:
		assert_object(_world.passenger(id)).is_not_null()
		assert_bool(_world.passenger(id).is_done()).is_false()
	assert_int(_world.sim.active_count()).is_equal(2)


func test_a_settled_passenger_that_still_holds_something_is_not_retired() -> void:
	_reference(0)
	var ids := _late(1)
	_world.run_to(1950)
	var p := _world.passenger(ids[0])
	assert_bool(p.is_done()).is_true()
	assert_str(_world.sim._settled_leftovers(p)).is_equal("")
	_world.sim._seat_claims["ghost_seat"] = p.id
	assert_str(_world.sim._settled_leftovers(p)).contains("seat")
	var due := p.outcome_tick + PassengerSim.SETTLED_KEEP_TICKS + 3
	_world.run_to(due)
	assert_object(_world.passenger(p.id)).is_not_null()
	assert_int(_world.sim.retire_refused).is_greater(0)
	_world.sim._seat_claims.erase("ghost_seat")
	_world.step()
	assert_object(_world.passenger(p.id)).is_null()


func test_a_guest_the_doors_caught_at_the_cafe_leaves_nothing_behind() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	var visit := _world.sim.cafes.visit_of(p.id)
	var id := p.id
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	visit.dwell_end = 1000000
	var key := visit.seat_key
	while _world.clock.tick < 1900:
		visit.deadline = 1000000
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	_world.run_to(1900 + PassengerSim.SETTLED_KEEP_TICKS + 2)
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)
	assert_object(_world.sim.cafes.visit_of(id)).is_null()
	assert_int(_world.sim.cafes.seat_holder(key)).is_equal(0)
	for record in _world.sim.cafes.queue_records():
		assert_array(record["lane"]).not_contains([id])
		assert_int(record["serving"]).is_not_equal(id)
	assert_int(_world.sim.missed_count()).is_equal(1)
