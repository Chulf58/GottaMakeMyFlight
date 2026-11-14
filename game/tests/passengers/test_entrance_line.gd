class_name TestEntranceLine
extends GdUnitTestSuite
## The line outside the entrance (decision arrivals-wait-in-a-tidy-line-outside-
## the-entrance-when-check, EntranceLine): with check-in full, arrivals wait
## spaced and in order outside, the head walks in when a place frees, the
## debug batch waits, spawn_now refuses with the line full, the forecast counts
## the wait once, a miss there reads as check-in congestion, a save keeps the
## order and an edit re-places the line.

var _world: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_world = null
	_other = null


## The desk hall with its desk's whole line (6 lane and 12 hold cells) taken,
## its front in service for HoldLineKit.LONG ticks, and one tick run so the
## desk is staffed (with no desk open the line lets everyone in).
static func _full_hall(scanner := false) -> PassengerTestWorld:
	var world := HoldLineKit.desk_hall()
	if scanner:
		PassengerTestWorld.place(world.grid, &"security_scanner", Vector2i(8, 4), 0)
	var desk: int = world.sim.get_meta(&"desk")
	for i in world.sim.layout.line_of(desk).size():
		HoldLineKit.member(world, desk)
	world.step()
	return world


## `count` new arrivals by spawn_now; their ids.
static func _arrive(world: PassengerTestWorld, count: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	return ids


static func _door(world: PassengerTestWorld) -> Vector2i:
	var sim := world.sim
	return sim.layout.door_cell(sim.grid, sim.layout.passenger_entrances[0])


static func _cell_of(world: PassengerTestWorld, p: Passenger) -> Vector2i:
	return world.grid.world_to_cell(p.apron_position())


func test_waiting_arrivals_stand_on_cells_of_their_own_off_the_doorway() -> void:
	_world = _full_hall()
	var ids := _arrive(_world, 10)
	for i in 30:
		_world.step()
	var cells := {}
	for id in ids:
		var p := _world.passenger(id)
		assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
		var cell := _cell_of(_world, p)
		cells[cell] = int(cells.get(cell, 0)) + 1
	prints("waiting cells", cells, "door", _door(_world))
	assert_int(cells.size()).is_equal(10)
	assert_bool(cells.has(_door(_world))).is_false()
	assert_array(_world.sim.entrance.order).is_equal(ids)


func test_spawn_now_waits_in_the_line_then_is_refused_when_it_is_full() -> void:
	_world = _full_hall()
	var line := _world.sim.entrance
	line.derive(_world.sim)
	assert_int(line.capacity()).is_equal(EntranceLine.MAX_PLACES)
	var ids := _arrive(_world, line.capacity())
	assert_bool(ids.has(0)).is_false()
	assert_str(_world.sim.spawn_refusal).is_empty()
	var refused := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	prints("refused", refused, _world.sim.spawn_refusal)
	assert_int(refused).is_equal(0)
	assert_str(_world.sim.spawn_refusal).contains("line outside the entrance is full")


func test_spawn_batch_waits_on_the_schedule_while_the_line_is_full() -> void:
	_world = _full_hall()
	var sim := _world.sim
	var before := sim.passenger_ids().size()
	assert_bool(sim.spawn_batch(EntranceLine.MAX_PLACES + 5, 7)).is_true()
	for i in EntranceLine.MAX_PLACES + 10:
		_world.step()
	var spawned := sim.passenger_ids().size() - before
	prints(
		"batch spawned", spawned, "held", sim._schedule.size(), "line", sim.entrance.order.size()
	)
	assert_int(spawned).is_equal(EntranceLine.MAX_PLACES)
	assert_int(sim.entrance.order.size()).is_equal(EntranceLine.MAX_PLACES)
	assert_int(sim._schedule.size()).is_greater_equal(5)
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		var on_door := p.stage == Passenger.Stage.TO_CHECKIN and p.at == _door(_world)
		assert_bool(on_door).is_false()


func test_the_head_walks_in_first_and_claims_the_freed_place() -> void:
	_world = _full_hall()
	var sim := _world.sim
	var desk: int = sim.get_meta(&"desk")
	var ids := _arrive(_world, 3)
	_world.step()
	assert_array(sim.entrance.order).is_equal(ids)
	var front := _world.passenger(sim.queue_of(desk)[0])
	front.service_end = sim.tick
	_world.step()
	_world.step()
	prints("order", sim.entrance.order, "claims", sim.entrance.claims)
	assert_array(sim.entrance.order).is_equal([ids[1], ids[2]])
	var head := _world.passenger(ids[0])
	for i in 80:
		if head.stage != Passenger.Stage.SPAWNED:
			break
		_world.step()
	prints("head", head.stage, head.station, "at", head.at)
	assert_int(head.station).is_equal(desk)
	assert_array(sim.entrance.claims).not_contains([ids[0]])
	assert_int(_world.passenger(ids[1]).stage).is_equal(Passenger.Stage.SPAWNED)


func test_the_forecast_counts_the_line_wait_once() -> void:
	_world = _full_hall(true)
	var sim := _world.sim
	var desk: int = sim.get_meta(&"desk")
	var head := _world.passenger(_arrive(_world, 1)[0])
	var wait := sim.entrance.forecast_ticks(sim, head)
	var slot := PassengerStations.slot(sim, desk)
	var expected := JourneyForecast.walk_ticks(3000) + slot * PassengerSim.CHECKIN_TICKS
	var with_line := JourneyForecast._to_gate(sim, head, false).x
	sim.entrance.order.erase(head.id)
	var without := JourneyForecast._to_gate(sim, head, false).x
	prints("wait", wait, "expected", expected, "leg", with_line, without)
	assert_int(wait).is_equal(expected)
	assert_int(with_line - without).is_equal(wait)


func test_a_miss_in_the_line_reads_as_check_in_congestion() -> void:
	_world = _full_hall()
	var sim := _world.sim
	var p := _world.passenger(_arrive(_world, 1)[0])
	PassengerLifecycle.finish(sim, p, false)
	var result := FlightResult.summarize(sim, PassengerTestWorld.FLIGHT)
	prints("reasons", result["reasons"])
	assert_str(FlightResult.ENTRANCE_LINE_TEXT).is_equal("Waiting outside: check-in full")
	assert_array(result["reasons"]).contains(
		[{"text": FlightResult.ENTRANCE_LINE_TEXT, "count": 1}]
	)
	assert_bool(sim.entrance.waiting(p.id)).is_false()


func test_a_save_mid_wait_keeps_the_order_and_plays_on_the_same() -> void:
	_world = _full_hall()
	var ids := _arrive(_world, 5)
	for i in 3:
		_world.step()
	var data := _world.sim.to_snapshot()
	assert_dict(data["entrance_line"]).contains_keys(["order", "claims", "held"])
	_other = HoldLineKit.desk_hall()
	_other.clock.tick = _world.clock.tick
	assert_bool(_other.sim.from_snapshot(data)).is_true()
	assert_array(_other.sim.entrance.order).is_equal(ids)
	for i in 20:
		_world.step()
		_other.step()
	assert_str(_other.signature()).is_equal(_world.signature())
	var stripped := data.duplicate(true)
	stripped.erase("entrance_line")
	assert_bool(HoldLineKit.desk_hall().sim.from_snapshot(stripped)).is_false()


func test_moving_the_entrance_re_places_the_line_and_removing_it_stops_arrivals() -> void:
	_world = _full_hall()
	var sim := _world.sim
	var ids := _arrive(_world, 4)
	_world.step()
	var before := sim.entrance.places.duplicate()
	var door := sim.layout.passenger_entrances[0]
	# The desk's staff spot may be reached only through the door: the staff
	# reach rule is off for the edit (as in TestHoldLineTailReach).
	_world.grid.check_staff_reach = false
	for edit in DoorPlacement.edits_for(_world.grid, BuildEdit.remove_object(door)):
		var result := _world.grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	_world.grid.check_staff_reach = true
	_world.step()
	assert_int(sim.entrance.capacity()).is_equal(0)
	assert_int(sim.entrance.room_for_arrivals(sim)).is_equal(0)
	PassengerTestWorld.place(_world.grid, &"entrance_door", Vector2i(6, 21), 2)
	_world.step()
	assert_int(sim.entrance.capacity()).is_equal(EntranceLine.MAX_PLACES)
	assert_bool(sim.entrance.places[0].is_equal_approx(before[0])).is_false()
	for index in ids.size():
		var p := _world.passenger(ids[index])
		assert_bool(p.apron.back().is_equal_approx(sim.entrance.places[index])).is_true()


func test_a_desk_added_admits_the_line_in_order() -> void:
	_world = _full_hall()
	var sim := _world.sim
	var ids := _arrive(_world, 3)
	for i in 5:
		_world.step()
	assert_array(sim.entrance.order).is_equal(ids)
	var added := PassengerTestWorld.place(_world.grid, &"checkin_desk", Vector2i(7, 1), 0)
	_world.step()
	prints("after a new desk: order", sim.entrance.order, "claims", sim.entrance.claims)
	assert_array(sim.entrance.order).is_empty()
	assert_array(sim.entrance.claims).is_equal(ids)
	for i in 500:
		if sim.queue_of(added).has(ids[2]):
			break
		_world.step()
	var entered: Array[int] = []
	for id in ids:
		var p := _world.passenger(id)
		assert_int(p.station).is_equal(added)
		entered.append(sim.queue_of(added).find(id))
	prints("places in the new desk's lane", entered)
	assert_array(entered).is_equal([0, 1, 2])
