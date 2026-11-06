class_name TestHoldLineForecast
extends GdUnitTestSuite
## SecurityForecast on the line (decision full-queue-design-a-derived-hold-
## line-behind-each-lane-gives): the replay walks the real paths of the
## walkers to the station and joins and moves them with the sim's StationQueue
## rules, so its clearance equals the measured one for a holder at any index
## and for walkers that reach the line out of the order they chose in.

## Just checked in, between the desks and the scanner lanes (CafeTestLayout).
const CROWD_CELL := Vector2i(16, 12)
## More than both scanners' lines hold together.
const BURST := 32
## The most replay ticks a forecast of the two-station burst may play on
## average: 213 measured on the rebuild, against about 700 per replay before
## it (decision hold-line-rebuild-the-security-line-follows-where-people-sta).
const MAX_REPLAY_TICKS := 320.0

var _w: SecurityTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.world.free_all()
		_w = null


## Forecasts every `every` ticks for every passenger committed to the
## station (with `holders_only`, only its holders: each forecast replays the
## whole queue, about 40 ms), from the
## tick all of `ids` have chosen it (none can then join ahead of another
## unforeseen), until all are cleared:
## [tick, id, forecast clearance tick, holding index, seg_mm].
func _forecasts(ids: Array[int], every := 1, holders_only := false) -> Array:
	var sim := _w.world.sim
	var out := []
	var all_in := false
	for i in 4000:
		if ids.all(func(id: int) -> bool: return _w.cleared.has(id)):
			break
		all_in = all_in or ids.all(func(id: int) -> bool: return sim.get_passenger(id).station != 0)
		if sim.tick % every != 0:
			_w.world.step()
			continue
		for id in ids:
			var p := sim.get_passenger(id)
			if not all_in or p.station != _w.station:
				continue
			if holders_only and not sim.holding_of(_w.station).has(id):
				continue
			var eta := SecurityForecast.eta(sim, p)
			out.append(
				[sim.tick, id, sim.tick + eta, sim.holding_of(_w.station).find(id), p.seg_mm]
			)
		_w.world.step()
	return out


## The forecasts that missed the measured clearance: entries plus it.
func _wrong(forecasts: Array) -> Array:
	var wrong := []
	for entry: Array in forecasts:
		if entry[2] != _w.cleared.get(entry[1], -1):
			wrong.append(entry + [_w.cleared.get(entry[1], -1)])
	return wrong


func test_the_forecast_equals_the_sim_for_holders_at_every_index() -> void:
	_w = SecurityTestWorld.make(false)
	var ids: Array[int] = []
	for i in 14:
		ids.append(_w.send(2))
		_w.world.run_to(_w.world.clock.tick + 2)
	# Every 5 ticks: moved from 6 for decision hold-line-rebuild-the-security-
	# line-follows-where-people-sta, whose holders' moves fell between samples.
	var forecasts := _forecasts(ids, 5, true)
	var deepest := -1
	var mid_step := 0
	for entry: Array in forecasts:
		deepest = maxi(deepest, entry[3])
		mid_step += int(entry[4] > 0)
	var wrong := _wrong(forecasts)
	print(
		"%d forecasts, deepest holder index %d, %d mid-step" % [forecasts.size(), deepest, mid_step]
	)
	assert_bool(ids.all(func(id: int) -> bool: return _w.cleared.has(id))).is_true()
	assert_int(deepest).is_greater_equal(2)
	assert_int(mid_step).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, holding, seg, measured] %s" % [wrong])
		. is_empty()
	)


## Later but nearer: P chooses first, far from the line, and is latched as
## the claimant on the tail; Q chooses next, beside the line. Moved for the
## latched claim (decision hold-line-rebuild-the-security-line-follows-where-
## people-sta): P keeps the claim, Q waits a step short of the tail and enters
## after P (P used to come up the line from its back while Q waited for it).
func test_the_forecast_equals_the_sim_when_walkers_reach_the_line_out_of_order() -> void:
	_w = SecurityTestWorld.make(false)
	var sim := _w.world.sim
	var line: Array = sim.layout.line_of(_w.station)
	var p := sim.get_passenger(_w.send(1))
	p.at = Vector2i(1, 2)
	p.clear_path()
	_w.world.step()
	assert_that(p.path_end()).is_equal(line[0])
	var q := sim.get_passenger(_w.send(2))
	q.at = Vector2i(6, 9)
	q.clear_path()
	_w.world.step()
	assert_that(q.path_end()).is_equal(line[1])
	# Q is by the line long before P gets there, and waits off its tail cell.
	for i in 40:
		_w.world.step()
	assert_dict(_w.world.sim._claims).is_equal({_w.station: p.id})
	assert_int(q.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_bool(line.slice(0, 1).has(q.at)).is_false()
	var ids: Array[int] = [p.id, q.id]
	var forecasts := _forecasts(ids)
	var mid_step := 0
	for entry: Array in forecasts:
		mid_step += int(entry[4] > 0)
	var wrong := _wrong(forecasts)
	var counts := [_w.joined, forecasts.size(), mid_step, _w.cleared]
	print("joined %s, %d forecasts, %d mid-step, cleared %s" % counts)
	assert_array(_w.joined).is_equal([p.id, q.id])
	assert_int(mid_step).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, holding, seg, measured] %s" % [wrong])
		. is_empty()
	)


## Passengers waiting for a place (the line is full: QUEUE_FULL at the
## entrance) are replayed as the sim plays them: the oldest takes the next
## free place and walks there from where it waits. Every forecast, for the
## waiting ones and for those on the line, equals the measured clearance.
func test_the_forecast_equals_the_sim_for_passengers_waiting_for_a_place() -> void:
	_w = SecurityTestWorld.make(false)
	var sim := _w.world.sim
	var line: Array = sim.layout.line_of(_w.station)
	var ids: Array[int] = []
	for i in line.size() + 5:
		ids.append(_w.send(1))
		_w.world.run_to(_w.world.clock.tick + 2)
	var forecasts := []
	var waiting := 0
	for i in 4000:
		if ids.all(func(id: int) -> bool: return _w.cleared.has(id)):
			break
		if sim.tick % 5 == 0:
			var pending: Array = ids.filter(func(id: int) -> bool: return not _w.cleared.has(id))
			var etas := SecurityForecast.clearances(sim, _w.station, pending)
			for id: int in pending:
				var p := sim.get_passenger(id)
				var seeking := PassengerStations.is_seeking(sim, p, false)
				waiting += int(seeking and etas.has(id))
				forecasts.append(
					[sim.tick, id, sim.tick + etas.get(id, -sim.tick), int(seeking), 0]
				)
		_w.world.step()
	var wrong := _wrong(forecasts)
	print(
		(
			"%d forecasts, %d for waiting passengers, line %d"
			% [forecasts.size(), waiting, line.size()]
		)
	)
	assert_bool(ids.all(func(id: int) -> bool: return _w.cleared.has(id))).is_true()
	assert_int(waiting).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, waiting, -, measured] %s" % [wrong])
		. is_empty()
	)


## Two scanners and a burst bigger than both lines (CafeTestLayout): the
## replay plays both stations and the waiting passengers choose by the sim's
## own estimate (PassengerStations.estimate()), so every forecast, for the
## waiting and the committed at either station, equals the measured
## clearance. It also bounds the forecast's work: replay ticks per replay.
func test_the_forecast_equals_the_sim_at_two_stations_with_passengers_waiting() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	# A late flight: nobody in the burst misses it before it is cleared.
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(3000))
	var sim := world.sim
	var ids: Array[int] = []
	for i in BURST:
		var p := world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.cafe_cooldown = 1000000
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = CROWD_CELL
		p.clear_path()
		ids.append(p.id)
	var cleared := {}
	var forecasts := []
	var waiting := 0
	var replays := 0
	var steps := 0
	for i in 3000:
		if cleared.size() == ids.size():
			break
		# The replay takes a station as open or closed as it is now: forecast
		# once both scanners are staffed.
		if sim.tick % 10 == 0 and sim.layout.scanners.all(sim._is_open):
			var pending: Array = ids.filter(
				func(id: int) -> bool: return not cleared.has(id) and sim.get_passenger(id) != null
			)
			var etas := {}
			for station: int in sim.layout.scanners:
				var before := SecurityForecast.steps_played
				var some := SecurityForecast.clearances(sim, station, pending)
				steps += SecurityForecast.steps_played - before
				replays += 1
				etas.merge(some)
			for id: int in etas:
				var p := sim.get_passenger(id)
				var seeking := p != null and PassengerStations.is_seeking(sim, p, false)
				waiting += int(seeking)
				forecasts.append([sim.tick, id, sim.tick + etas[id], int(seeking)])
		world.step()
		for id in ids:
			var p := sim.get_passenger(id)
			if p != null and p.stage == Passenger.Stage.TO_GATE and not cleared.has(id):
				cleared[id] = sim.tick
	var wrong := []
	for entry: Array in forecasts:
		if entry[2] != cleared.get(entry[1], -1):
			wrong.append(entry + [cleared.get(entry[1], -1)])
	var per := float(steps) / maxf(replays, 1.0)
	print(
		(
			"%d forecasts, %d for waiting passengers, %d replays, %.0f ticks each"
			% [forecasts.size(), waiting, replays, per]
		)
	)
	world.free_all()
	assert_int(cleared.size()).is_equal(ids.size())
	assert_int(waiting).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, waiting, measured] %s" % [wrong])
		. is_empty()
	)
	assert_float(per).is_less_equal(MAX_REPLAY_TICKS)
