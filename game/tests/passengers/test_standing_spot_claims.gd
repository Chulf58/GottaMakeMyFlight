class_name TestStandingSpotClaims
extends GdUnitTestSuite
## Standing spot claims in the running sim (PassengerSim with StandingSpots):
## one passenger per spot, overflow order and the held state, a freed seat
## taken from a spot, release once off the cell on departure, on doors closing and on an edit,
## and the forecast walk to the spot. Each case builds its own small world,
## because each one moves passengers and claims.

## A basic scanner's exit cell in the reference terminal (the passage end).
const SCANNER_EXIT := Vector2i(17, 7)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The reference terminal with its four seat rows taken out: every cleared
## passenger stands, and the gate area grows from the exit door.
static func seatless_world(starts: Array[int] = []) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	for id in ReferenceTerminal.object_ids(grid)["seats"]:
		grid.apply(BuildEdit.remove_object(id))
	if starts.is_empty():
		starts = FlightSim.schedule_starts(0)
	var world := PassengerTestWorld.make(grid, starts)
	world.sim.standing.rebuild(world.sim)
	return world


## A calm, cleared passenger on its way to the gate at `cell`, trying for a
## seat or spot on the next tick.
static func cleared(world: PassengerTestWorld, cell := SCANNER_EXIT) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = world.clock.tick + 1
	p.at = cell
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	return p


## Steps until `done` holds, at most `limit` ticks; returns whether it did.
func _run_until(done: Callable, limit := 600) -> bool:
	for i in limit:
		if done.call():
			return true
		_world.step()
	return done.call()


func _first_in(group: Array[Passenger], stage: Passenger.Stage) -> Passenger:
	for p in group:
		if p.stage == stage:
			return p
	return null


func _all_standing(group: Array[Passenger]) -> bool:
	return group.all(func(p: Passenger) -> bool: return p.stage == Passenger.Stage.STANDING)


func test_no_two_passengers_share_a_spot() -> void:
	_world = seatless_world()
	var group: Array[Passenger] = []
	for i in 20:
		group.append(cleared(_world))
	assert_bool(_run_until(_all_standing.bind(group))).is_true()
	var taken := {}
	var closest := 1.0e9
	_world.run_to(_world.clock.tick + PassengerSim.SHUFFLE_TICKS)
	for a in group.size():
		var spot := _world.sim.standing.spot_of(group[a].id)
		assert_bool(taken.has(spot)).is_false()
		taken[spot] = true
		var pa := _world.sim.world_position(group[a])
		for b in range(a + 1, group.size()):
			var pb := _world.sim.world_position(group[b])
			closest = minf(closest, Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)))
	print("standing=%d spots=%d closest=%.3f m" % [group.size(), taken.size(), closest])
	assert_int(taken.size()).is_equal(20)
	assert_float(closest).is_greater_equal(0.599)


func test_overflow_comes_after_the_gate_area_then_the_passenger_is_held() -> void:
	_world = seatless_world()
	var spots := _world.sim.standing
	var fake := 90000
	for id: int in spots.spots:
		if spots.tier_of(id) == StandingSpots.NEAR:
			spots.claim(fake, id)
			fake += 1
	var expected := spots.free_nearest(SCANNER_EXIT)[0]
	assert_int(spots.tier_of(expected)).is_equal(StandingSpots.OVERFLOW)
	var p := cleared(_world)
	_world.step()
	assert_int(spots.spot_of(p.id)).is_equal(expected)
	# Every spot taken: the next passenger is held where it is, and counted.
	for id in spots.free_nearest(SCANNER_EXIT):
		spots.claim(fake, id)
		fake += 1
	var held := cleared(_world)
	_world.step()
	assert_int(spots.spot_of(held.id)).is_equal(StandingSpots.NO_SPOT)
	assert_bool(_world.sim.standing.is_held(held)).is_true()
	assert_int(_world.sim.standing.shortage(_world.sim)).is_equal(1)
	assert_that(held.at).is_equal(SCANNER_EXIT)
	# A spot frees up: the held passenger takes it on its beat.
	spots.release(90000)
	var freed := spots.free_nearest(SCANNER_EXIT)[0]
	assert_bool(_run_until(func() -> bool: return spots.spot_of(held.id) != -1, 40)).is_true()
	assert_int(spots.spot_of(held.id)).is_equal(freed)
	assert_int(_world.sim.standing.shortage(_world.sim)).is_equal(0)


func test_a_freed_seat_is_taken_and_gives_up_the_spot() -> void:
	_world = PassengerTestWorld.reference_world()
	var group: Array[Passenger] = []
	for i in _world.sim.layout.seats.size() + 1:
		group.append(cleared(_world))
	var settled := func() -> bool:
		return group.all(
			func(p: Passenger) -> bool:
				return p.stage in [Passenger.Stage.SEATED, Passenger.Stage.STANDING]
		)
	assert_bool(_run_until(settled)).is_true()
	var stander := _first_in(group, Passenger.Stage.STANDING)
	assert_int(_world.sim.standing.spot_of(stander.id)).is_not_equal(StandingSpots.NO_SPOT)
	var sitter := _first_in(group, Passenger.Stage.SEATED)
	_world.sim._finish(sitter, true)
	var moved := func() -> bool: return stander.seat_object != 0
	assert_bool(_run_until(moved, PassengerSim.BEAT_TICKS + 1)).is_true()
	assert_int(_world.sim.standing.spot_of(stander.id)).is_equal(StandingSpots.NO_SPOT)
	assert_int(_world.sim.standing.claim_count()).is_equal(0)
	var sits := func() -> bool: return stander.stage == Passenger.Stage.SEATED
	assert_bool(_run_until(sits)).is_true()


## Setting off for the exit, the passenger keeps its spot until it is off the
## spot's cell (so it walks on from the spot, not from the cell's centre), and
## gives it up then.
func test_boarding_keeps_the_spot_until_off_its_cell_then_releases_it() -> void:
	_world = seatless_world()
	var p := cleared(_world)
	assert_bool(_run_until(func() -> bool: return p.stage == Passenger.Stage.STANDING)).is_true()
	assert_int(_world.sim.standing.claim_count()).is_equal(1)
	var cell := p.at
	_world.run_to(p.boarding_tick)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_int(_world.sim.standing.claim_count()).is_equal(1)
	assert_bool(_run_until(func() -> bool: return p.at != cell)).is_true()
	assert_int(_world.sim.standing.claim_count()).is_equal(0)


func test_doors_closing_releases_the_spot_and_retires_cleanly() -> void:
	_world = seatless_world(PassengerTestWorld.starts_with(1000, 1200))
	var p := cleared(_world)
	# Boarding never comes for this passenger: it is still standing when the
	# doors close, so it misses and must let go of its spot.
	p.boarding_tick = 1000000
	assert_bool(_run_until(func() -> bool: return p.stage == Passenger.Stage.STANDING)).is_true()
	_world.run_to(1200 + PassengerSim.SETTLED_KEEP_TICKS + 2)
	assert_int(_world.sim.standing.claim_count()).is_equal(0)
	assert_int(_world.sim.retire_refused).is_equal(0)
	assert_bool(_world.sim.passenger_ids().has(p.id)).is_false()


func test_an_edit_that_removes_the_target_spot_replans() -> void:
	_world = seatless_world()
	var p := cleared(_world)
	_world.step()
	var spots := _world.sim.standing
	var first := spots.spot_of(p.id)
	var target := spots.cell_of(first)
	assert_bool(p.is_moving()).is_true()
	assert_that(target).is_not_equal(p.at)
	assert_bool(_world.grid.apply(BuildEdit.remove_floor(target)).ok).is_true()
	_world.step()
	var second := spots.spot_of(p.id)
	print("first %d at %s, then %d" % [first, target, second])
	assert_bool(spots.spots.has(first)).is_false()
	assert_int(spots.holder_of(first)).is_equal(0)
	assert_int(second).is_not_equal(StandingSpots.NO_SPOT)
	assert_that(spots.cell_of(second)).is_not_equal(target)
	assert_that(p.path_end()).is_equal(spots.cell_of(second))
	assert_bool(_run_until(func() -> bool: return p.stage == Passenger.Stage.STANDING)).is_true()


func test_the_forecast_includes_the_walk_to_the_spot() -> void:
	_world = seatless_world()
	var p := cleared(_world)
	_world.step()
	var spot := _world.sim.standing.spot_of(p.id)
	assert_int(spot).is_not_equal(StandingSpots.NO_SPOT)
	var walk := p.remaining_mm()
	assert_int(walk).is_greater(0)
	# With boarding already open, the passenger leaves the moment it gets
	# to its spot, so the walk there shows in the arrival tick in full.
	p.boarding_tick = 0
	var door: int = _world.sim.layout.exits[0]
	var exit_mm := Passenger.octile_mm(
		_world.sim.standing.cell_of(spot), _world.sim.layout.door_cell(_world.grid, door)
	)
	var expected := (
		_world.sim.tick
		+ JourneyForecast.walk_ticks(walk)
		+ JourneyForecast.walk_ticks(exit_mm + _world.sim.apron_length_mm(door))
	)
	var arrival := JourneyForecast.arrival_tick(_world.sim, p)
	print("walk %d mm, arrival %d, expected %d" % [walk, arrival, expected])
	assert_int(arrival).is_equal(expected)


func test_a_passenger_skips_spots_it_cannot_reach_behind_a_wall() -> void:
	_world = PassengerTestWorld.reference_world()
	# A wall between x 13 and 14 splits the airside into two seating areas.
	for y in range(ReferenceTerminal.FLOOR_MIN.y, ReferenceTerminal.AIRSIDE_MAX_Y + 1):
		var wall := _world.grid.apply(BuildEdit.place_wall(Vector2i(13, y), BuildGrid.Side.EAST))
		assert_bool(wall.ok).override_failure_message(wall.reason_text()).is_true()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	# Every seat and every right-hand spot but the farthest is taken, so the
	# nearest free spots are all on the far side of the wall.
	var fake := 90000
	for seat in _world.sim.layout.seats:
		_world.sim._seat_claims[seat["key"]] = fake
		fake += 1
	var right: Array[int] = []
	var left := 0
	for id: int in spots.spots:
		if spots.cell_of(id).x >= 14:
			right.append(id)
		else:
			left += 1
	assert_int(left).is_greater(StandingSpots.TRIES)
	var keyed := []
	for id in right:
		var d: Vector2i = spots.spots[id]["mm"] - (SCANNER_EXIT * 1000 + Vector2i(500, 500))
		keyed.append([spots.tier_of(id), d.x * d.x + d.y * d.y, id])
	keyed.sort()
	var kept: int = keyed.back()[2]
	for entry in keyed:
		if entry[2] != kept:
			spots.claim(fake, entry[2])
			fake += 1
	var p := cleared(_world)
	_world.step()
	print(
		(
			"left=%d right=%d kept %d at %s, claim %d"
			% [left, right.size(), kept, spots.cell_of(kept), spots.spot_of(p.id)]
		)
	)
	assert_int(spots.spot_of(p.id)).is_equal(kept)
	assert_bool(spots.is_held(p)).is_false()
