class_name TestHoldLineForecast
extends GdUnitTestSuite
## SecurityForecast on the line (decision full-queue-design-a-derived-hold-
## line-behind-each-lane-gives): the replay walks the real paths of the
## walkers to the station and joins and moves them with the sim's StationQueue
## rules, so its clearance equals the measured one for a holder at any index
## and for walkers that reach the line out of the order they chose in.

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
	var forecasts := _forecasts(ids, 6, true)
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


func test_the_forecast_equals_the_sim_when_walkers_reach_the_line_out_of_order() -> void:
	_w = SecurityTestWorld.make(false)
	var sim := _w.world.sim
	var line: Array = sim.layout.line_of(_w.station)
	var p := sim.get_passenger(_w.send(1))
	p.at = Vector2i(5, 14)
	p.clear_path()
	_w.world.step()
	assert_that(p.path_end()).is_equal(line[0])
	var q := sim.get_passenger(_w.send(2))
	q.at = Vector2i(8, 8)
	q.clear_path()
	_w.world.step()
	assert_that(q.path_end()).is_equal(line[1])
	# Q reaches the line first and waits on its cell for P, heading for the
	# cell ahead of it, so neither turns back.
	for i in 40:
		_w.world.step()
	assert_that(q.at).is_equal(line[1])
	assert_bool(q.is_moving()).is_false()
	assert_int(q.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
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
