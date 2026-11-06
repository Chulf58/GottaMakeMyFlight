class_name TestGateCapacityEdits
extends GdUnitTestSuite
## An edit that removes a reserved place while its passenger is inside security
## (decision gate-full-design-passengers-reserve-a-gate-seat-or-standing,
## point 6): the passenger is never cleared without a place. With none free it
## waits on its own cell inside security, counted on the HUD; once one frees it
## reserves it from its station's exit and is cleared to it. Each case builds
## its own small world.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_world = null


## Claims every free standing spot with an id no passenger has; returns the
## first id used.
static func _fill_spots(sim: PassengerSim) -> int:
	var fake := 90000
	for spot: int in sim.standing.spots:
		if sim.standing.is_free(spot, false):
			sim.standing.claim(fake, spot)
			fake += 1
	return 90000


## The spots derived again after an edit, as the next tick does (claims on
## removed spots dropped), then every free one claimed by a fake id, so the
## edit leaves no place to move to; returns the first fake id.
static func _settle_and_fill(sim: PassengerSim) -> int:
	sim.standing.rebuild(sim)
	sim.standing.drop_invalid()
	return _fill_spots(sim)


## Steps until `done` holds, at most `limit` ticks; returns whether it did.
func _run_until(done: Callable, limit: int) -> bool:
	for i in limit:
		if done.call():
			return true
		_world.step()
	return done.call()


## The passenger waits on `cell` inside security for 100 ticks, not cleared,
## and is in the HUD's shortage.
func _waits_on(p: Passenger, cell: Vector2i) -> void:
	_world.run_to(_world.clock.tick + 100)
	var held := _world.sim.gates.shortage(_world.sim)
	print(
		(
			"waiting: stage %d phase %d at %s (cell %s), in shortage %s"
			% [p.stage, p.security_phase, p.at, cell, held.has(p.id)]
		)
	)
	assert_bool(p.cleared).is_false()
	assert_int(p.stage).is_equal(Passenger.Stage.SECURITY)
	assert_that(p.at).is_equal(cell)
	assert_bool(p.is_moving()).is_false()
	assert_bool(held.has(p.id)).is_true()


## A spot frees (the first one still claimed by a fake id from `fake` on):
## the passenger reserves it, is cleared and walks there.
func _cleared_to_freed_spot(p: Passenger, fake: int) -> void:
	var spots := _world.sim.standing
	while spots.spot_of(fake) == StandingSpots.NO_SPOT and fake < 99999:
		fake += 1
	var freed := spots.spot_of(fake)
	assert_int(freed).is_not_equal(StandingSpots.NO_SPOT)
	spots.release(fake)
	assert_bool(_run_until(func() -> bool: return p.cleared, 60)).is_true()
	print("cleared to spot %d (freed %d), path end %s" % [spots.spot_of(p.id), freed, p.path_end()])
	assert_int(spots.spot_of(p.id)).is_equal(freed)
	assert_that(p.path_end()).is_equal(spots.cell_of(freed))


func test_a_spot_removed_while_its_passenger_walks_to_the_lane_exit() -> void:
	var lane := SecurityTestWorld.make(true)
	_world = lane.world
	var sim := _world.sim
	var p := _world.passenger(lane.send(0))
	var leaving := func() -> bool:
		return p.security_phase == SecurityRuntime.Phase.LEAVE and p.is_moving()
	assert_bool(_run_until(leaving, 600)).is_true()
	var spot := sim.standing.reserved_of(p.id)
	assert_int(spot).is_not_equal(StandingSpots.NO_SPOT)
	var gone := sim.standing.cell_of(spot)
	var edit := _world.grid.apply(BuildEdit.remove_floor(gone))
	assert_bool(edit.ok).override_failure_message(edit.reason_text()).is_true()
	var fake := _settle_and_fill(sim)
	_world.step()
	print("reserved %d on %s, removed; now %d" % [spot, gone, sim.standing.reserved_of(p.id)])
	assert_bool(sim.standing.spots.has(spot)).is_false()
	_waits_on(p, sim.security.exit_cell(lane.station))
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.LEAVE)
	_cleared_to_freed_spot(p, fake)


func test_a_seat_removed_while_its_passenger_is_scanned() -> void:
	_world = PassengerTestWorld.reference_world()
	var sim := _world.sim
	sim.standing.rebuild(sim)
	var station: int = sim.layout.scanners.min()
	var p := TestStandingSpotClaims.cleared(_world)
	p.cleared = false
	p.station = station
	p.stage = Passenger.Stage.SECURITY_QUEUE
	p.at = sim.layout.lanes[station][0]
	(sim._queue(station)["lane"] as Array).append(p.id)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SECURITY)
	var key: String = sim.gates.seats.get(p.id, "")
	assert_str(key).is_not_empty()
	# Every other seat and every spot taken, then the reserved seat removed.
	for seat in sim.layout.seats:
		if seat["key"] != key:
			sim._seat_claims[seat["key"]] = 80000
	var removed := int(key.get_slice(":", 0))
	var edit := _world.grid.apply(BuildEdit.remove_object(removed))
	assert_bool(edit.ok).override_failure_message(edit.reason_text()).is_true()
	var fake := _settle_and_fill(sim)
	var at_end := func() -> bool: return not p.is_moving() and p.security_work == 0
	assert_bool(_run_until(at_end, 200)).is_true()
	print("seat %s removed; reservation now %s" % [key, sim.gates.seats.get(p.id, "none")])
	_waits_on(p, sim.security.exit_cell(station))
	_cleared_to_freed_spot(p, fake)


## Two passengers inside security both lost their places: the later one (B,
## a roller) still holds a spot it cannot reach behind a wall, beside the one
## spot left. Every lost place is given up before anyone reserves, so the
## earlier boarding tick (A) takes that spot; B's dead reservation does not
## keep it from A.
func test_the_earlier_boarding_reserves_first_when_both_lost_their_places() -> void:
	_world = PassengerTestWorld.reference_world()
	var sim := _world.sim
	# A wall between x 13 and 14 splits the airside into two route regions.
	for y in range(ReferenceTerminal.FLOOR_MIN.y, ReferenceTerminal.AIRSIDE_MAX_Y + 1):
		var wall := _world.grid.apply(BuildEdit.place_wall(Vector2i(13, y), BuildGrid.Side.EAST))
		assert_bool(wall.ok).override_failure_message(wall.reason_text()).is_true()
	for seat in sim.layout.seats:
		sim._seat_claims[seat["key"]] = 80000
	var spots := sim.standing
	spots.rebuild(sim)
	var station: int = sim.layout.scanners.min()
	var region := spots.region_of(sim.security.exit_cell(station))
	var near := -1
	var far := -1
	for id: int in spots.spots:
		for other in [id - 1, id + 1]:
			if near >= 0 or not spots.spots.has(other):
				continue
			var d: Vector2i = spots.spots[id]["mm"] - spots.spots[other]["mm"]
			var here := spots.region_of(spots.cell_of(id)) == region
			var split := spots.region_of(spots.cell_of(other)) != region
			if here and split and Vector2(d).length() < StandingSpots.ROLLER_CLEAR_MM:
				near = id
				far = other
	assert_int(near).is_not_equal(-1)
	var fake := 90000
	for id: int in spots.spots:
		if id != near and id != far:
			spots.claim(fake, id)
			fake += 1
	var a := _inside(station, 2900, false)
	var b := _inside(station, 3000, true)
	spots.reserve(b.id, far, true)
	sim.security.records[station] = {"admitted": [b.id, a.id], "returns": [], "main": 0, "berth": 0}
	assert_bool(sim.gates.placed(b, sim)).is_false()
	var stations: Array[int] = [station]
	GateCapacity.recover_all(sim, sim.security, stations, sim.gates)
	var held_a := spots.reserved_of(a.id)
	var held_b := spots.reserved_of(b.id)
	print(
		(
			"near %d far %d: A (earlier) holds %d, B (later, roller) holds %d"
			% [near, far, held_a, held_b]
		)
	)
	assert_int(held_a).is_equal(near)
	assert_int(held_b).is_equal(StandingSpots.NO_SPOT)
	sim.security.records.erase(station)


## A passenger inside `station`'s security with boarding tick `boarding`, with
## one roller bag when `roller`, else no bag.
func _inside(station: int, boarding: int, roller: bool) -> Passenger:
	for attempt in 200:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 1
		if ParkRecovery.has_roller(p) != roller:
			_world.sim._finish(p, true)
			continue
		p.carry_on = int(roller)
		p.stage = Passenger.Stage.SECURITY
		p.station = station
		p.boarding_tick = boarding
		return p
	return null
