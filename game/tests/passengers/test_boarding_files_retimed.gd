class_name TestBoardingFilesRetimed
extends GdUnitTestSuite
## Board 54c9e0ce: a walker that turns pending on a file's line is not walked
## into by the filed walker coming up behind it, and the forecast knows the
## passengers still in security, who come out onto the line ahead of filed
## walkers. The full boarding of test_boarding_files at another timing (doors
## close 40 ticks later), where on main walkers 3 and 7 stood 0.33 m apart and
## two walkers arrived 7 ticks after their forecast. Each case builds its own
## world, because each one moves passengers through the files.

const GAP := BoardingFiles.GAP_MM
## How much later than the reference doors-close tick this timing closes them.
const DOORS_LATER := 40

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## A walker turns pending on the column a filed walker walks up: it stands on
## the cell of the walker ahead of it, so it waits for that one to be a gap
## ahead. The filed walker behind stops a full gap short of it while it waits,
## and never comes within a body's width of it after it joins (the gap is
## kept along the walk, so a turn can bring them a little nearer than GAP).
func test_a_filed_walker_stops_a_gap_behind_a_walker_waiting_in_its_line() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	var ahead := TestBoardingFiles.walker(_world, Vector2i(20, 5))
	var waiting := TestBoardingFiles.walker(_world, Vector2i(20, 5))
	var behind := TestBoardingFiles.walker(_world, Vector2i(20, 6))
	_world.step()
	var files := _world.sim.files
	assert_bool(files.is_pending(waiting.id)).is_true()
	assert_bool(files.is_pending(behind.id)).is_false()
	assert_int(files.door_of(behind.id)).is_equal(ahead.exit_object)
	var start := TestBoardingFiles.apart(_world, waiting, behind)
	var nearest := start
	var nearest_waiting := start
	var capped := 0
	var waited := 0
	var group: Array[Passenger] = [ahead, waiting, behind]
	var done := func() -> bool: return group.all(func(p: Passenger) -> bool: return p.is_done())
	while not done.call() and _world.clock.tick < TestBoardingFiles.DOORS:
		if files.is_pending(waiting.id):
			waited += 1
			if files.allowed(_world.sim, behind, PassengerSim.WALK_MM) < PassengerSim.WALK_MM:
				capped += 1
		_world.step()
		if TestBoardingFiles.heading_out(waiting) and TestBoardingFiles.heading_out(behind):
			nearest = minf(nearest, TestBoardingFiles.apart(_world, waiting, behind))
			if files.is_pending(waiting.id):
				nearest_waiting = minf(
					nearest_waiting, TestBoardingFiles.apart(_world, waiting, behind)
				)
	print(
		(
			(
				"started %.3f m apart, nearest %.3f m while it waited, %.3f m in all;"
				+ " waited %d ticks, behind capped %d of them"
			)
			% [start, nearest_waiting, nearest, waited, capped]
		)
	)
	assert_int(waited).is_greater(0)
	assert_int(capped).is_greater(0)
	assert_float(start).is_greater(GAP / 1000.0)
	assert_float(nearest_waiting).is_greater_equal(GAP / 1000.0 - 0.001)
	assert_float(nearest).is_greater_equal(TestBoardingFiles.BODY_M)
	assert_bool(done.call()).is_true()
	assert_int(_world.sim.made_count()).is_equal(3)


## test_boarding_files' full boarding (seed 4242, 24 passengers), with the
## reference flight's doors closing DOORS_LATER ticks later.
func test_a_full_boarding_with_doors_later_keeps_its_gaps_and_forecasts() -> void:
	var starts := FlightSim.schedule_starts(0)
	starts[FlightSim.State.DOORS_CLOSED] += DOORS_LATER
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, starts, 4242)
	_world.run_to(PassengerTestWorld.arrival_opens_tick())
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var problem := ""
	var gaps := {}
	var pended := 0
	var close_filed := 0
	var forecast := {}
	var made := {}
	var ran := {}
	_world.sim.outcome.connect(
		func(id: int, did: bool) -> void:
			if did:
				made[id] = _world.clock.tick
	)
	while _world.clock.tick <= doors and problem == "":
		for id in _world.sim.passenger_ids():
			ran[id] = ran.get(id, false) or _world.passenger(id).late
			pended += int(_world.sim.files.is_pending(id))
		_world.step()
		problem = TestBoardingFiles.spacing_problem(_world, gaps)
		for pair: Array in TestBoardingFiles.close_pairs(_world):
			var a: Passenger = pair[0]
			var b: Passenger = pair[1]
			if _filed(a) and _filed(b):
				close_filed += 1
				var d := TestBoardingFiles.apart(_world, a, b)
				print("tick %d: filed %d and %d %.3f m apart" % [_world.clock.tick, a.id, b.id, d])
		for id in _world.sim.passenger_ids():
			if _filed(_world.passenger(id)) and not forecast.has(id):
				forecast[id] = JourneyForecast.arrival_tick(_world.sim, _world.passenger(id))
	var latest := -JourneyForecast.NEVER
	var latest_id := 0
	var missed: Array[int] = []
	for id: int in forecast:
		if not made.has(id):
			missed.append(id)
		elif made[id] - forecast[id] > latest:
			latest = made[id] - forecast[id]
			latest_id = id
	var runners := ran.values().count(true)
	print(
		(
			"made %d missed %d, pending %d, close filed %d, ran %d, latest arrival minus forecast %d (%d)"
			% [
				_world.sim.made_count(),
				_world.sim.missed_count(),
				pended,
				close_filed,
				runners,
				latest,
				latest_id
			]
		)
	)
	(
		assert_array(missed)
		. override_failure_message("filed walkers %s missed the flight" % [missed])
		. is_empty()
	)
	assert_str(problem).is_empty()
	assert_int(pended).is_greater(0)
	assert_int(forecast.size()).is_equal(24)
	assert_int(made.size()).is_equal(24)
	assert_int(close_filed).is_equal(0)
	assert_int(latest).is_less_equal(TestBoardingFiles.FORECAST_LATE)


func _filed(p: Passenger) -> bool:
	var files := _world.sim.files
	return TestBoardingFiles.heading_out(p) and files.holds(p.id) and not files.is_pending(p.id)


## The forecast's known walkers being screened are timed by one replay per
## station (BoardingFiles._cleared_at()): each gets the same own times as its
## own SecurityForecast.eta() gives, on every tick while a security lane
## screens a stream of passengers, and some ticks have two or more screened.
func test_one_replay_per_station_times_each_screened_walker_as_its_own_does() -> void:
	var lane := SecurityTestWorld.make(true)
	_world = lane.world
	var traits := []
	for i in 8:
		traits.append([2 - i % 2, i == 0, i == 3])
	var ids := lane.send_all(traits)
	var compared := 0
	var shared := 0
	var differ: Array[String] = []
	var all_cleared := func() -> bool:
		return ids.all(func(id: int) -> bool: return lane.cleared.has(id))
	while not all_cleared.call() and _world.clock.tick < 3000:
		_world.step()
		# Worked out afresh now, not as a forecast earlier in the tick saw it.
		_world.sim.files.clear_derived()
		var screened := 0
		for own: Dictionary in _world.sim.files.known(_world.sim):
			var q := _world.passenger(own["id"])
			if q.stage != Passenger.Stage.SECURITY:
				continue
			screened += 1
			var alone := JourneyForecast.own_times(_world.sim, q, _world.clock.tick, false)
			alone["id"] = q.id
			compared += 1
			if alone != own:
				differ.append("tick %d id %d: %s, alone %s" % [_world.clock.tick, q.id, own, alone])
		shared += int(screened >= 2)
	print("compared %d screened walkers, %d ticks with two or more" % [compared, shared])
	assert_bool(all_cleared.call()).is_true()
	assert_array(differ).is_empty()
	assert_int(compared).is_greater(0)
	assert_int(shared).is_greater(0)
