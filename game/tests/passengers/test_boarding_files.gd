class_name TestBoardingFiles
extends GdUnitTestSuite
## The ordered boarding files in the running sim (BoardingFiles): over a full
## boarding every file keeps its order and no walker closes in on the one
## ahead, walkers sharing a cell set off one at a time, a newcomer joins in
## front of a walker that is too close behind and caps it, a walker whose way
## changes takes its place again, a walker that leaves frees the one behind it,
## and nothing is let through on a timer. Each case builds its own world,
## because each one moves passengers through the files.

const GAP := BoardingFiles.GAP_MM
## Boarding opens at this tick in the small worlds, and doors close at DOORS.
const BOARDING := 20
const DOORS := 4000
## A body's width, as the overlap probe counts it (passenger_overlap_probe.gd).
const BODY_M := 0.45
## How much earlier than its forecast a walker that never ran may arrive: the
## forecast adds a tick per walker ahead for the step order
## (BoardingFiles.step_ticks()) and passes walkers through each door in the
## order of their own times; two ticks per passenger of a 24-passenger flight.
const FORECAST_SLACK := 48
## How much later: the walk to the door drops what is left of a step at the
## door, and the apron starts on the next tick, which the forecast's one
## walk_ticks() over both legs rounds away (as it did before the files).
const FORECAST_LATE := 1

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The reference terminal with a flight that boards at BOARDING.
static func boarding_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	return PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))


## A calm, cleared passenger at `cell` that turns to the exit on the next tick.
static func walker(
	world: PassengerTestWorld, cell: Vector2i, flight := PassengerTestWorld.FLIGHT
) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(flight))
	turn_out(world, p, cell)
	return p


## Makes `p` a calm, cleared passenger at `cell` that turns to the exit on the
## next tick.
static func turn_out(world: PassengerTestWorld, p: Passenger, cell: Vector2i) -> void:
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_EXIT
	p.stage_tick = world.clock.tick
	p.at = cell
	p.clear_path()
	p.apron = []
	p.apron_mm = 0


## Every file in order of walk left, and no walker closer than GAP to the one
## ahead of it that got closer since the last call: the first offence as text,
## or "". `gaps` carries each adjacent pair's gap from call to call. A walker
## just behind a newcomer may be closer than GAP, but it never closes in.
static func spacing_problem(world: PassengerTestWorld, gaps: Dictionary) -> String:
	var files := world.sim.files
	var now := {}
	var problem := ""
	for id in world.sim.passenger_ids():
		var lists := []
		if files.door_of(id) != 0:
			lists.append(["door", files.door_file(files.door_of(id))])
		if not files.plane_file_of(id).is_empty():
			lists.append(["apron", files.plane_file_of(id)])
		for entry: Array in lists:
			var ids: Array[int] = entry[1]
			var k := ids.find(id)
			if k <= 0:
				continue
			var a := world.passenger(ids[k - 1])
			var b := world.passenger(id)
			var gap := BoardingFiles.door_left(b) - BoardingFiles.door_left(a)
			if entry[0] == "apron":
				gap = BoardingFiles.plane_left(b) - BoardingFiles.plane_left(a)
			var key := "%s %d>%d" % [entry[0], a.id, b.id]
			now[key] = gap
			if gap < 0 and problem == "":
				problem = "%s: %d behind %d out of order by %d mm" % [key, b.id, a.id, -gap]
			elif gap < GAP and gaps.has(key) and gap < gaps[key] and problem == "":
				problem = "%s closed from %d to %d mm" % [key, gaps[key], gap]
	gaps.clear()
	gaps.merge(now)
	return problem


## The ground distance between two passengers' sim positions, in metres.
static func apart(world: PassengerTestWorld, a: Passenger, b: Passenger) -> float:
	var pa := world.sim.world_position(a)
	var pb := world.sim.world_position(b)
	return Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))


static func heading_out(p: Passenger) -> bool:
	return p.stage == Passenger.Stage.TO_EXIT or p.stage == Passenger.Stage.APRON


## The pairs of walkers heading out closer than a body's width on this tick.
static func close_pairs(world: PassengerTestWorld) -> Array:
	var out := []
	var ids := world.sim.passenger_ids()
	for i in ids.size():
		var a := world.passenger(ids[i])
		if not heading_out(a):
			continue
		for j in range(i + 1, ids.size()):
			var b := world.passenger(ids[j])
			if heading_out(b) and apart(world, a, b) < BODY_M:
				out.append([a, b])
	return out


## Steps until `done` holds, at most `limit` ticks; returns whether it did.
func _run_until(done: Callable, limit := 2000) -> bool:
	for i in limit:
		if done.call():
			return true
		_world.step()
	return done.call()


func _all_done(group: Array[Passenger]) -> bool:
	for p in group:
		if not p.is_done():
			return false
	return true


func test_a_full_boarding_keeps_order_never_closes_a_gap_and_no_filed_walkers_overlap() -> void:
	_world = PassengerTestWorld.reference_world(4242)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var problem := ""
	var gaps := {}
	var held := 0
	var pended := 0
	var close_filed := 0
	var close_any := 0
	var most_filed := 0
	var forecast := {}
	var made := {}
	var ran := {}
	_world.sim.outcome.connect(
		func(id: int, did: bool) -> void:
			if did:
				made[id] = _world.clock.tick
	)
	while _world.clock.tick <= doors and problem == "":
		var filed := 0
		for id in _world.sim.passenger_ids():
			var p := _world.passenger(id)
			if p.late:
				ran[id] = true
			if not _world.sim.files.holds(id):
				continue
			filed += 1
			if _world.sim.files.is_pending(id):
				pended += 1
			elif (
				_world.sim.files.allowed(_world.sim, p, PassengerSim.WALK_MM) < PassengerSim.WALK_MM
			):
				held += 1
		most_filed = maxi(most_filed, filed)
		_world.step()
		problem = spacing_problem(_world, gaps)
		for pair: Array in close_pairs(_world):
			close_any += 1
			var a: Passenger = pair[0]
			var b: Passenger = pair[1]
			if _filed(a) and _filed(b):
				close_filed += 1
				var d := apart(_world, a, b)
				print("tick %d: filed %d and %d %.3f m apart" % [_world.clock.tick, a.id, b.id, d])
		# The forecast once in a door file, kept for the arrival.
		for id in _world.sim.passenger_ids():
			if _filed(_world.passenger(id)) and not forecast.has(id):
				forecast[id] = JourneyForecast.arrival_tick(_world.sim, _world.passenger(id))
	# Arrival minus forecast: no later (but for FORECAST_LATE) for any walker;
	# and close to it for the walkers that never ran (the forecast is at a walk).
	var latest := -JourneyForecast.NEVER
	var earliest := JourneyForecast.NEVER
	for id: int in forecast:
		latest = maxi(latest, made[id] - forecast[id])
		if not ran.has(id):
			earliest = mini(earliest, made[id] - forecast[id])
	print(
		(
			(
				"made %d missed %d, most filed %d, held %d, pending %d, close %d (filed %d),"
				+ " ran %d, arrival minus forecast %d (walked) to %d"
			)
			% [
				_world.sim.made_count(),
				_world.sim.missed_count(),
				most_filed,
				held,
				pended,
				close_any,
				close_filed,
				ran.size(),
				earliest,
				latest
			]
		)
	)
	assert_str(problem).is_empty()
	assert_int(most_filed).is_greater_equal(10)
	assert_int(held).is_greater(0)
	assert_int(pended).is_greater(0)
	assert_int(forecast.size()).is_equal(24)
	assert_int(made.size()).is_equal(24)
	assert_int(ran.size()).is_less(24)
	assert_int(close_filed).is_equal(0)
	assert_int(latest).is_less_equal(FORECAST_LATE)
	assert_int(earliest).is_greater_equal(-FORECAST_SLACK)


func _filed(p: Passenger) -> bool:
	return heading_out(p) and _world.sim.files.holds(p.id) and not _world.sim.files.is_pending(p.id)


func test_two_walkers_on_one_cell_set_off_one_at_a_time() -> void:
	_world = boarding_world()
	_world.run_to(BOARDING + 5)
	var first := walker(_world, Vector2i(19, 6))
	var second := walker(_world, Vector2i(19, 6))
	_world.step()
	assert_array(_world.sim.files.door_file(first.exit_object)).is_equal([first.id])
	assert_bool(_world.sim.files.is_pending(second.id)).is_true()
	var waited := 0
	while _world.sim.files.is_pending(second.id):
		assert_that(second.at).is_equal(Vector2i(19, 6))
		assert_int(second.path_index).is_equal(0)
		assert_int(second.seg_mm).is_equal(0)
		waited += 1
		_world.step()
	var gap := BoardingFiles.door_left(second) - BoardingFiles.door_left(first)
	print("second waited %d ticks, then joined %d mm behind" % [waited, gap])
	assert_int(waited).is_greater(0)
	assert_array(_world.sim.files.door_file(first.exit_object)).is_equal([first.id, second.id])
	assert_int(gap).is_greater_equal(GAP)
	assert_bool(_run_until(_all_done.bind([first, second] as Array[Passenger]))).is_true()
	assert_int(first.stage).is_equal(Passenger.Stage.MADE)
	assert_int(second.stage).is_equal(Passenger.Stage.MADE)
	assert_int(second.outcome_tick - first.outcome_tick).is_greater_equal(
		JourneyForecast.walk_ticks(GAP)
	)


## A file down the x = 20 column, and a newcomer beside it a full gap behind
## the walker ahead but too close in front of the walker behind: it joins at
## once, between them, and the walker behind is capped by it and never closes
## in; the gap only grows until it is a full GAP.
func test_a_newcomer_joins_in_front_and_the_walker_behind_never_closes_in() -> void:
	_world = boarding_world()
	_world.run_to(BOARDING + 5)
	var ahead := walker(_world, Vector2i(20, 5))
	var behind := walker(_world, Vector2i(20, 7))
	var newcomer := walker(_world, Vector2i(21, 6))
	_world.step()
	var door := ahead.exit_object
	var gap := BoardingFiles.door_left(behind) - BoardingFiles.door_left(newcomer)
	print(
		(
			"left ahead %d newcomer %d behind %d"
			% [
				BoardingFiles.door_left(ahead),
				BoardingFiles.door_left(newcomer),
				BoardingFiles.door_left(behind)
			]
		)
	)
	assert_array(_world.sim.files.door_file(door)).is_equal([ahead.id, newcomer.id, behind.id])
	assert_bool(_world.sim.files.is_pending(newcomer.id)).is_false()
	assert_int(gap).is_less(GAP)
	var capped := 0
	var gaps := {}
	while gap < GAP:
		if (
			_world.sim.files.allowed(_world.sim, behind, PassengerSim.WALK_MM)
			< PassengerSim.WALK_MM
		):
			capped += 1
		_world.step()
		assert_str(spacing_problem(_world, gaps)).is_empty()
		var next := BoardingFiles.door_left(behind) - BoardingFiles.door_left(newcomer)
		assert_int(next).is_greater_equal(gap)
		gap = next
	print("behind capped %d ticks, gap now %d" % [capped, gap])
	assert_int(capped).is_greater(0)
	assert_array(_world.sim.files.door_file(door)).is_equal([ahead.id, newcomer.id, behind.id])
	assert_bool(_run_until(_all_done.bind([ahead, behind, newcomer] as Array[Passenger]))).is_true()
	assert_int(_world.sim.made_count()).is_equal(3)


func test_a_walker_whose_way_is_walled_off_takes_its_place_again() -> void:
	_world = boarding_world()
	_world.run_to(BOARDING + 5)
	var p := walker(_world, Vector2i(20, 8))
	var behind := walker(_world, Vector2i(20, 8))
	for i in 3:
		_world.step()
	var door := p.exit_object
	assert_int(_world.sim.files.door_of(p.id)).is_equal(door)
	var before := p.path.duplicate()
	# A wall across the column ahead of it: its committed path is cut.
	var wall := BuildEdit.place_wall(Vector2i(20, 5), BuildGrid.Side.NORTH)
	assert_bool(_world.grid.apply(wall).ok).is_true()
	assert_bool(p.needs_replan).is_true()
	_world.step()
	print("path before %s, after %s, file %s" % [before, p.path, _world.sim.files.door_file(door)])
	assert_that(p.path).is_not_equal(before)
	assert_bool(_world.sim.files.holds(p.id)).is_true()
	assert_str(spacing_problem(_world, {})).is_empty()
	assert_bool(_run_until(_all_done.bind([p, behind] as Array[Passenger]))).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(behind.stage).is_equal(Passenger.Stage.MADE)


## A walker of a second flight sets off first from a cell; the one behind it
## waits. When the second flight's doors close, the first is missed and leaves
## its file, and the waiting one joins and walks on that very tick.
func test_a_walker_that_leaves_frees_the_one_waiting_behind_it() -> void:
	_world = boarding_world()
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(BOARDING, BOARDING + 12))
	_world.run_to(BOARDING + 6)
	var leaving := walker(_world, Vector2i(19, 6), "GMF202")
	var waiting := walker(_world, Vector2i(19, 6))
	_world.step()
	assert_bool(_world.sim.files.is_pending(waiting.id)).is_true()
	while _world.clock.tick < BOARDING + 11:
		_world.step()
		assert_bool(_world.sim.files.is_pending(waiting.id)).is_true()
	var left_before := BoardingFiles.door_left(waiting)
	_world.step()
	var stage: String = Passenger.Stage.keys()[leaving.stage]
	var left_after := BoardingFiles.door_left(waiting)
	print(
		(
			"tick %d: leaving %s, waiting left %d -> %d"
			% [_world.clock.tick, stage, left_before, left_after]
		)
	)
	assert_int(leaving.stage).is_equal(Passenger.Stage.MISSED)
	assert_bool(_world.sim.files.holds(leaving.id)).is_false()
	assert_bool(_world.sim.files.is_pending(waiting.id)).is_false()
	assert_int(BoardingFiles.door_left(waiting)).is_less(left_before)


## Nothing lets a waiting walker through but room: the admission pass and the
## step cap give the same answer however often they are asked while nothing
## moves.
func test_a_wait_is_never_ended_by_time_alone() -> void:
	_world = boarding_world()
	_world.run_to(BOARDING + 5)
	var first := walker(_world, Vector2i(19, 6))
	var second := walker(_world, Vector2i(19, 6))
	_world.step()
	assert_bool(_world.sim.files.is_pending(second.id)).is_true()
	for i in 5000:
		_world.sim._admit_pending()
		assert_int(_world.sim.files.allowed(_world.sim, second, PassengerSim.RUN_MM)).is_equal(0)
	assert_bool(_world.sim.files.is_pending(second.id)).is_true()
	assert_array(_world.sim.files.door_file(first.exit_object)).is_equal([first.id])


## The follower has the lower id, so it steps first each tick and sees where
## the walker ahead was on the tick before. Neither arrives later than its
## forecast (but for FORECAST_LATE).
func test_a_follower_stepped_first_arrives_no_later_than_its_forecast() -> void:
	_world = boarding_world()
	_world.run_to(BOARDING + 5)
	# Spawned first, so it has the lower id, and turned out once the head walks.
	var follower := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var head := walker(_world, Vector2i(20, 7))
	for i in 3:
		_world.step()
	turn_out(_world, follower, Vector2i(20, 7))
	var forecast := {}
	var capped := 0
	for i in 2000:
		for p: Passenger in [follower, head]:
			if _filed(p) and not forecast.has(p.id):
				forecast[p.id] = JourneyForecast.arrival_tick(_world.sim, p)
		var room := _world.sim.files.allowed(_world.sim, follower, PassengerSim.WALK_MM)
		if _filed(follower) and room < PassengerSim.WALK_MM:
			capped += 1
		if follower.is_done() and head.is_done():
			break
		_world.step()
	assert_bool(follower.is_done() and head.is_done()).is_true()
	print(
		(
			"head %d forecast %d, follower %d forecast %d, capped %d"
			% [
				head.outcome_tick,
				forecast[head.id],
				follower.outcome_tick,
				forecast[follower.id],
				capped
			]
		)
	)
	assert_int(capped).is_greater(0)
	assert_int(head.outcome_tick).is_less_equal(forecast[head.id] + FORECAST_LATE)
	assert_int(follower.outcome_tick).is_less_equal(forecast[follower.id] + FORECAST_LATE)
	assert_int(follower.outcome_tick).is_greater_equal(forecast[follower.id] - FORECAST_SLACK)


## Passengers standing on spots that share a cell set off for the exit from
## their spots, one at a time, and never stand on top of each other: the one
## that waits stays on its spot, and the one that goes walks on from its spot.
func test_standing_passengers_sharing_a_cell_set_off_without_meeting() -> void:
	_world = TestStandingSpotClaims.seatless_world(PassengerTestWorld.starts_with(400, 4000))
	var group: Array[Passenger] = []
	for i in 10:
		group.append(TestStandingSpotClaims.cleared(_world))
	_world.run_to(399)
	var by_cell := {}
	for p in group:
		assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
		var cell := _world.sim.standing.cell_of(_world.sim.standing.spot_of(p.id))
		by_cell[cell] = by_cell.get(cell, []) + [p]
	var shared: Array = []
	for cell: Vector2i in by_cell:
		if (by_cell[cell] as Array).size() >= 2 and shared.is_empty():
			shared = by_cell[cell]
	assert_int(shared.size()).is_greater_equal(2)
	var a: Passenger = shared[0]
	var b: Passenger = shared[1]
	var cell := a.at
	var nearest := 100.0
	var biggest_step := 0.0
	var last := {}
	var waited := 0
	while not (a.is_done() and b.is_done()) and _world.clock.tick < 3000:
		_world.step()
		if heading_out(a) and heading_out(b):
			nearest = minf(nearest, apart(_world, a, b))
		for p: Passenger in [a, b]:
			var at := _world.sim.world_position(p)
			if last.has(p.id) and heading_out(p) and p.stage != Passenger.Stage.APRON:
				biggest_step = maxf(biggest_step, (at - last[p.id]).length())
			last[p.id] = at
			waited += int(_world.sim.files.is_pending(p.id))
	print(
		(
			"cell %s: %d and %d, nearest %.3f m, biggest step %.3f m, waited %d"
			% [cell, a.id, b.id, nearest, biggest_step, waited]
		)
	)
	assert_int(waited).is_greater(0)
	assert_int(a.stage).is_equal(Passenger.Stage.MADE)
	assert_int(b.stage).is_equal(Passenger.Stage.MADE)
	assert_float(nearest).is_greater(0.3)
	# Off the spot by walking, never by a jump to the cell's centre.
	assert_float(biggest_step).is_less(0.3)


## Two exit doors whose walks out join the same apron route: walkers from both
## are in one apron file, spaced along the shared tail.
func test_walkers_from_two_doors_are_spaced_on_the_shared_apron() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	(
		assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(17, 2), BuildGrid.Side.NORTH)).ok)
		. is_true()
	)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(17, 2), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.run_to(BOARDING + 5)
	var group: Array[Passenger] = []
	for cell: Vector2i in [Vector2i(17, 4), Vector2i(20, 4), Vector2i(17, 5), Vector2i(20, 5)]:
		group.append(walker(_world, cell))
		group.append(walker(_world, cell))
	var walk := Passenger.new()
	walk.apron.assign(Array(_world.sim.apron_waypoints))
	var tail := walk.apron_total_mm()
	var mixed := 0
	var on_tail := 0
	var nearest := 100.0
	var problem := ""
	var gaps := {}
	while not _all_done(group) and _world.clock.tick < 4000 and problem == "":
		_world.step()
		problem = spacing_problem(_world, gaps)
		var doors := {}
		for p in group:
			if p.stage == Passenger.Stage.APRON:
				doors[p.exit_object] = true
		mixed += int(doors.size() == 2)
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a := group[i]
				var b := group[j]
				var out := a.stage == Passenger.Stage.APRON and b.stage == Passenger.Stage.APRON
				if (
					out
					and BoardingFiles.plane_left(a) <= tail
					and BoardingFiles.plane_left(b) <= tail
				):
					on_tail += 1
					nearest = minf(nearest, apart(_world, a, b))
	var exits := {}
	for p in group:
		exits[p.exit_object] = true
	print(
		(
			"exits %s, mixed ticks %d, pairs on the tail %d, nearest %.3f m"
			% [exits.keys(), mixed, on_tail, nearest]
		)
	)
	assert_str(problem).is_empty()
	assert_int(exits.size()).is_equal(2)
	assert_int(mixed).is_greater(0)
	assert_int(on_tail).is_greater(0)
	assert_float(nearest).is_greater_equal(BODY_M)
	assert_bool(_all_done(group)).is_true()


## A late walker held back behind another flight's walker in a boarding line
## misses, and the flight's result gives the crowding reason; a late walker
## walking free at the head of the line misses for the ordinary reason
## (decision a-late-passenger-held-up-by-people-traffic-at-boarding-misse).
func test_a_late_walker_held_back_in_a_line_misses_from_crowds() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var closing := BOARDING + 60
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, closing))
	_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.run_to(BOARDING + 5)
	var free := walker(_world, Vector2i(20, 3))
	var other := walker(_world, Vector2i(20, 6), "GMF202")
	var held := walker(_world, Vector2i(20, 6))
	var held_ticks := 0
	while _world.clock.tick < closing:
		_world.step()
		held_ticks += int(_world.sim.files.was_delayed(held.id))
	assert_bool(_world.sim.files.was_delayed(free.id)).is_false()
	assert_bool(_world.sim.files.was_delayed(held.id)).is_false()
	var summary := FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)
	print(
		(
			"held %d ticks; held %s %s, free %s %s; reasons %s"
			% [
				held_ticks,
				Passenger.Stage.keys()[held.missed_stage],
				Passenger.Stuck.keys()[held.missed_stuck],
				Passenger.Stage.keys()[free.missed_stage],
				Passenger.Stuck.keys()[free.missed_stuck],
				summary["reasons"]
			]
		)
	)
	assert_int(held_ticks).is_greater(0)
	assert_int(held.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(held.missed_stuck).is_equal(Passenger.Stuck.CROWDED)
	assert_int(free.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(free.missed_stuck).is_equal(Passenger.Stuck.NONE)
	assert_bool(other.is_done()).is_false()
	var texts := {}
	for reason: Dictionary in summary["reasons"]:
		texts[reason["text"]] = reason["count"]
	assert_int(texts.get(FlightResult.CROWDED_TEXT, 0)).is_equal(1)
	assert_int(texts.get(FlightResult.STAGE_TEXT[free.missed_stage], 0)).is_equal(1)


## The reference terminal with a second exit door at (17, 2), both walks out
## joining the same apron route, and walkers crowding both doors, run until
## one stands at its door waiting for room on the apron. Returns that walker,
## or null.
func _waiting_at_a_door() -> Passenger:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	(
		assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(17, 2), BuildGrid.Side.NORTH)).ok)
		. is_true()
	)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(17, 2), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.run_to(BOARDING + 5)
	for cell: Vector2i in [Vector2i(17, 3), Vector2i(20, 3), Vector2i(17, 4), Vector2i(20, 4)]:
		for i in 3:
			walker(_world, cell)
	for i in 600:
		_world.step()
		for id in _world.sim.passenger_ids():
			var files := _world.sim.files
			if files.is_pending(id) and files.door_of(id) != 0:
				return _world.passenger(id)
	return null


## While a walker waits at its door for room on the apron, `edit` closes that
## door: it does not walk out through it, and is not counted as made for
## free; it goes out by the other door.
func _check_closed_while_waiting(close_it: Callable) -> void:
	var p := _waiting_at_a_door()
	assert_object(p).is_not_null()
	var door := p.exit_object
	var cell := _world.sim.layout.door_cell(_world.grid, door)
	print("tick %d: walker %d waits at door %d %s" % [_world.clock.tick, p.id, door, cell])
	assert_bool(close_it.call(door, cell)).is_true()
	assert_bool(_world.sim.layout.open_exits(_world.grid).has(door)).is_false()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_int(p.exit_object).is_not_equal(door)
	assert_bool(_world.sim.files.door_file(door).has(p.id)).is_false()
	var out_by := 0
	while not p.is_done() and _world.clock.tick < DOORS:
		_world.step()
		if p.stage == Passenger.Stage.APRON and out_by == 0:
			out_by = p.exit_object
	print("walker %d went out by door %d, %s" % [p.id, out_by, Passenger.Stage.keys()[p.stage]])
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(out_by).is_not_equal(door)
	assert_int(out_by).is_not_equal(0)


func test_a_walker_waiting_at_a_door_that_is_removed_does_not_board_for_free() -> void:
	_check_closed_while_waiting(
		func(door: int, _cell: Vector2i) -> bool:
			return _world.grid.apply(BuildEdit.remove_object(door)).ok
	)


func test_a_walker_waiting_at_a_door_that_is_blocked_does_not_walk_through_it() -> void:
	# Floor laid on the cell outside the door closes it (TerminalLayout.is_exit_open()).
	_check_closed_while_waiting(
		func(_door: int, cell: Vector2i) -> bool:
			var beyond := cell + Vector2i(0, -1)
			return _world.grid.apply(BuildEdit.paint_floor(beyond, BuildGrid.FLOOR_TILE, 1)).ok
	)
