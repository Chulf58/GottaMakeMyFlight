class_name TestStandingRollerSpacing
extends GdUnitTestSuite
## Standing spacing next to rollers (decision gate-standing-spacing-standing-
## passengers-keep-wider-apart-o): the 0.6 m lattice stays, but no spot within
## StandingSpots.ROLLER_CLEAR_MM of a taken spot whose passenger has a roller
## is free, and a roller passenger takes no spot that close to any taken one.
## The body-to-roller distances as drawn are the probe's
## (game/spike/gate_full_probe.gd); this checks the claims.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_world = null


func _distance_mm(spots: StandingSpots, a: int, b: int) -> float:
	var d: Vector2i = spots.spots[a]["mm"] - spots.spots[b]["mm"]
	return Vector2(d).length()


## A spot whose neighbour is free on every side, in row order.
func _open_spot(spots: StandingSpots) -> int:
	var ids: Array = spots.spots.keys()
	ids.sort()
	for id: int in ids:
		var ring := 0
		for other: int in ids:
			var d := _distance_mm(spots, id, other)
			if other != id and d < StandingSpots.ROLLER_CLEAR_MM:
				ring += 1
		if ring == StandingSpots.ROLLER_RING.size():
			return id
	return StandingSpots.NO_SPOT


func test_a_roller_claim_keeps_its_ring_free_of_everyone() -> void:
	_world = TestStandingSpotClaims.seatless_world()
	var spots := _world.sim.standing
	var centre := _open_spot(spots)
	assert_int(centre).is_not_equal(StandingSpots.NO_SPOT)
	var ring: Array[int] = []
	for id: int in spots.spots:
		if id != centre and _distance_mm(spots, id, centre) < StandingSpots.ROLLER_CLEAR_MM:
			ring.append(id)
	# Without a roller the neighbours stay free to everyone.
	spots.claim(90000, centre, false)
	var plain_free := ring.filter(func(id: int) -> bool: return spots.is_free(id, false))
	var plain_roller := ring.filter(func(id: int) -> bool: return spots.is_free(id, true))
	# With a roller nobody takes them.
	spots.claim(90000, centre, true)
	var roller_free := ring.filter(func(id: int) -> bool: return spots.is_free(id, false))
	print(
		(
			"ring %d: free beside a plain claim %d (to a roller %d), beside a roller %d"
			% [ring.size(), plain_free.size(), plain_roller.size(), roller_free.size()]
		)
	)
	assert_int(ring.size()).is_equal(StandingSpots.ROLLER_RING.size())
	assert_int(plain_free.size()).is_equal(ring.size())
	assert_int(plain_roller.size()).is_equal(0)
	assert_int(roller_free.size()).is_equal(0)
	# A reservation counts the same, and lets go.
	spots.release(90000)
	spots.reserve(90001, centre, true)
	assert_bool(spots.is_free(ring[0], false)).is_false()
	spots.unreserve(90001)
	assert_bool(spots.is_free(ring[0], true)).is_true()


## 20 cleared passengers, 10 with a roller, stand at a seatless gate:
## no two claimed spots sit closer than ROLLER_CLEAR_MM where either holder
## has a roller, and the plain pairs keep the 0.6 m lattice.
func test_standers_keep_the_roller_clearance() -> void:
	_world = TestStandingSpotClaims.seatless_world()
	var group: Array[Passenger] = []
	var rollers := 0
	var plain := 0
	while group.size() < 20:
		var p := TestStandingSpotClaims.cleared(_world)
		p.carry_on = 1
		var roller := ParkRecovery.has_roller(p)
		if not roller:
			p.carry_on = 0
		if (roller and rollers < 10) or (not roller and plain < 10):
			rollers += int(roller)
			plain += int(not roller)
			group.append(p)
		else:
			_world.sim._finish(p, true)
	var standing := func() -> bool:
		return group.all(func(p: Passenger) -> bool: return p.stage == Passenger.Stage.STANDING)
	for i in 900:
		if standing.call():
			break
		_world.step()
	assert_bool(standing.call()).is_true()
	var spots := _world.sim.standing
	var near_roller := INF
	var near_plain := INF
	for a in group.size():
		for b in range(a + 1, group.size()):
			var d := _distance_mm(spots, spots.spot_of(group[a].id), spots.spot_of(group[b].id))
			if ParkRecovery.has_roller(group[a]) or ParkRecovery.has_roller(group[b]):
				near_roller = minf(near_roller, d)
			else:
				near_plain = minf(near_plain, d)
	print(
		(
			"standing %d, with a roller %d: least spot gap beside a roller %.0f mm, plain %.0f mm"
			% [group.size(), rollers, near_roller, near_plain]
		)
	)
	assert_int(rollers).is_greater(4)
	assert_float(near_roller).is_greater_equal(StandingSpots.ROLLER_CLEAR_MM)
	assert_float(near_plain).is_greater_equal(StandingSpots.PITCH_MM - 1)
