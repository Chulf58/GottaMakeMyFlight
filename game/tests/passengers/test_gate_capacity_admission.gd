class_name TestGateCapacityAdmission
extends GdUnitTestSuite
## Security admission against the gate places (decision gate-full-design-
## passengers-reserve-a-gate-seat-or-standing, points 1, 2 and 4): a front is
## admitted only with a reserved seat or spot, waits on its lane cell stuck
## GATE_FULL otherwise, is admitted once a place frees or its boarding opens,
## and competing fronts go earliest boarding tick first. Held passengers never
## share a cell. Each case builds its own small world, as each moves
## passengers and claims.

var _gate: GateFullWorld
var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_gate = null
	_world = null


## The gate holds SPOTS passengers; the next front waits on its lane cell,
## GATE_FULL, and no one more is admitted until a stander leaves, then exactly
## one is.
func test_a_full_gate_holds_the_front_until_one_place_frees() -> void:
	_gate = GateFullWorld.make()
	var sim := _gate.world.sim
	sim.standing.rebuild(sim)
	assert_int(sim.standing.spots.size()).is_equal(GateFullWorld.SPOTS)
	_gate.send_many(GateFullWorld.SPOTS + 3)
	var full := func() -> bool:
		var front := _gate.front()
		return front != null and front.stuck == Passenger.Stuck.GATE_FULL
	assert_bool(_gate.run_until(full)).is_true()
	var front := _gate.front()
	var held_count := _gate.admitted.size()
	_gate.world.run_to(_gate.world.clock.tick + 300)
	var cells: Array = sim.layout.lanes[_gate.station]
	print(
		(
			"spots %d, standing %d, admitted %d then %d, front %d at %s (lane cell %s), stuck %d"
			% [
				sim.standing.spots.size(),
				_gate.standing_count(),
				held_count,
				_gate.admitted.size(),
				front.id,
				front.at,
				cells[0],
				front.stuck
			]
		)
	)
	assert_int(held_count).is_equal(GateFullWorld.SPOTS)
	assert_int(_gate.admitted.size()).is_equal(held_count)
	assert_that(front.at).is_equal(cells[0])
	assert_int(front.stuck).is_equal(Passenger.Stuck.GATE_FULL)
	assert_array(sim.gates.shortage(sim)).contains([front.id])
	assert_str(sim.bubble_text(front)).is_equal("The gate is full")
	# One stander leaves: exactly one more is admitted, the old front.
	for id in sim.passenger_ids():
		if _gate.world.passenger(id).stage == Passenger.Stage.STANDING:
			sim._finish(_gate.world.passenger(id), true)
			break
	_gate.world.run_to(_gate.world.clock.tick + 300)
	print("after one place freed: admitted %d" % _gate.admitted.size())
	assert_int(_gate.admitted.size()).is_equal(held_count + 1)
	assert_bool(_gate.admitted.has(front.id)).is_true()


## A front whose boarding has opened needs no gate place: it is admitted.
func test_a_front_whose_boarding_is_open_is_admitted() -> void:
	_gate = GateFullWorld.make()
	_gate.send_many(GateFullWorld.SPOTS + 2)
	var full := func() -> bool:
		var f := _gate.front()
		return f != null and f.stuck == Passenger.Stuck.GATE_FULL
	assert_bool(_gate.run_until(full)).is_true()
	var front := _gate.front()
	var before := _gate.admitted.size()
	front.boarding_tick = _gate.world.clock.tick
	_gate.world.step()
	print("boarding open: admitted %d -> %d" % [before, _gate.admitted.size()])
	assert_bool(_gate.admitted.has(front.id)).is_true()
	assert_int(front.stuck).is_equal(Passenger.Stuck.NONE)


## 30 passengers through security at a gate with SPOTS places: every passenger
## held for want of a place (GateCapacity.shortage()) is on its own cell.
## Passengers waiting in the queue's holding list are a separate cause (board
## c5b6664f) and are only printed.
func test_held_passengers_never_share_a_cell() -> void:
	_gate = GateFullWorld.make()
	var sim := _gate.world.sim
	_gate.send_many(30)
	_gate.world.run_to(_gate.world.clock.tick + 600)
	var held := sim.gates.shortage(sim)
	var cells := {}
	for id in held:
		cells[_gate.world.passenger(id).at] = true
	print(
		(
			"spots %d, claims %d, held %d on %d cells, lane %d, holding %d"
			% [
				sim.standing.spots.size(),
				sim.standing.claim_count(),
				held.size(),
				cells.size(),
				sim.queue_of(_gate.station).size(),
				sim.holding_of(_gate.station).size()
			]
		)
	)
	assert_int(held.size()).is_greater(0)
	assert_int(cells.size()).is_equal(held.size())
	assert_bool(cells.has(GateFullWorld.SCANNER_EXIT)).is_false()


## 30 cleared passengers in the seatless reference terminal, where standing
## spots cover the whole trusted airside: nobody is held while spots remain.
func test_thirty_cleared_passengers_find_spots_in_the_airside() -> void:
	_world = TestStandingSpotClaims.seatless_world()
	var group: Array[Passenger] = []
	for i in 30:
		group.append(TestStandingSpotClaims.cleared(_world))
	var standing := func() -> bool:
		return group.all(func(p: Passenger) -> bool: return p.stage == Passenger.Stage.STANDING)
	for i in 900:
		if standing.call():
			break
		_world.step()
	var held := _world.sim.gates.shortage(_world.sim)
	var spots := _world.sim.standing
	print(
		(
			"spots %d, claims %d, held %d, all standing %s"
			% [spots.spots.size(), spots.claim_count(), held.size(), standing.call()]
		)
	)
	assert_bool(standing.call()).is_true()
	assert_int(held.size()).is_equal(0)
	assert_int(spots.spots.size()).is_greater(spots.claim_count())


## Two fronts ready on one tick, one free place: the earlier boarding tick
## takes it whatever the station order, and the other waits GATE_FULL.
func test_the_earliest_boarding_tick_wins_among_competing_fronts() -> void:
	for early_on_second in [true, false]:
		_world = TestStandingSpotClaims.seatless_world()
		var sim := _world.sim
		var stations: Array[int] = []
		stations.assign(sim.layout.scanners)
		stations.sort()
		assert_int(stations.size()).is_equal(2)
		var spots := sim.standing
		var free := spots.free_nearest(sim.security.exit_cell(stations[0]))
		var fake := 90000
		for id: int in spots.spots:
			if id != free[0]:
				spots.claim(fake, id)
				fake += 1
		var fronts: Array[Passenger] = []
		for station in stations:
			var p := TestStandingSpotClaims.cleared(_world)
			p.cleared = false
			p.station = station
			p.stage = Passenger.Stage.SECURITY_QUEUE
			p.at = sim.layout.lanes[station][0]
			(sim._queue(station)["lane"] as Array).append(p.id)
			fronts.append(p)
		var early := fronts[1] if early_on_second else fronts[0]
		var late := fronts[0] if early_on_second else fronts[1]
		early.boarding_tick = 2900
		late.boarding_tick = 3000
		_world.step()
		print(
			(
				"early %d at station %d: stage %d; late %d at station %d: stage %d, stuck %d"
				% [
					early.id,
					early.station,
					early.stage,
					late.id,
					late.station,
					late.stage,
					late.stuck
				]
			)
		)
		assert_int(early.stage).is_equal(Passenger.Stage.SECURITY)
		assert_int(spots.reserved_of(early.id)).is_equal(free[0])
		assert_int(late.stage).is_equal(Passenger.Stage.SECURITY_QUEUE)
		assert_int(late.stuck).is_equal(Passenger.Stuck.GATE_FULL)


## A miss while held for a gate place is the terminal's: the GATE_FULL front
## and the passenger queued behind it are recorded as crowding misses.
func test_a_miss_while_the_gate_is_full_is_a_crowding_miss() -> void:
	_gate = GateFullWorld.make()
	_gate.send_many(GateFullWorld.SPOTS + 2)
	var full := func() -> bool:
		var f := _gate.front()
		var lane := _gate.world.sim.queue_of(_gate.station)
		return f != null and f.stuck == Passenger.Stuck.GATE_FULL and lane.size() == 2
	assert_bool(_gate.run_until(full)).is_true()
	var sim := _gate.world.sim
	var lane := sim.queue_of(_gate.station)
	var front := _gate.world.passenger(lane[0])
	var behind := _gate.world.passenger(lane[1])
	sim._finish(behind, false)
	sim._finish(front, false)
	print("missed: front stuck %d, behind stuck %d" % [front.missed_stuck, behind.missed_stuck])
	assert_int(front.missed_stuck).is_equal(Passenger.Stuck.CROWDED)
	assert_int(behind.missed_stuck).is_equal(Passenger.Stuck.CROWDED)
	var text := FlightResult.reason_text(front.missed_stage, front.missed_stuck)
	assert_str(text).is_equal(FlightResult.CROWDED_TEXT)
