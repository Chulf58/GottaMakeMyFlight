class_name TestQueueWalkAroundForecast
extends GdUnitTestSuite
## A walker to security whose plain route to the tail runs over queued
## members goes round them in the live sim (decision queue-walkers-route-
## around-their-own-line-a-walker-heading-t), and SecurityForecast, which
## plays the same StationQueue rules, forecasts every clearance exactly.

## Members on line[0..MEMBERS-1]: the tail is past the corner where the line
## turns, so a walker from the far side of the lane crosses it on the plain
## route.
const MEMBERS := 7

var _w: SecurityTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.world.free_all()
		_w = null


## StationQueue.approach() as it was before the shut, on the plain grid
## route: the control, the route a walker took before.
static func _plain_approach(
	grid: BuildGrid, line: Array, from: Vector2i, index: int
) -> Array[Vector2i]:
	var path := StationQueue.path_to(grid, line, from, index)
	if path.size() < 2:
		return path
	var step: Vector2i = line[index] - path[path.size() - 2]
	var front: Vector2i = line[index - 1] - line[index]
	if step.x * front.x + step.y * front.y >= 0:
		return path
	var round := StationQueue.path_to(grid, line, from, index + 1)
	round.append(line[index])
	return round


## Of the cells off `line` and walkable whose plain approach to line[MEMBERS]
## runs over a member's cell, line[0..MEMBERS-1], the one with the shortest
## such route (the first row by row on a tie): near enough that the members
## still stand there when the walker would pass.
static func _crossing_start(grid: BuildGrid, line: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_mm := 0
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if line.has(cell) or not grid.is_passenger_cell(cell):
				continue
			var plain := _plain_approach(grid, line, cell, MEMBERS)
			for i in range(1, plain.size()):
				var at := line.find(plain[i])
				if at >= 0 and at < MEMBERS:
					var mm := Passenger.path_mm(plain)
					if best.x < 0 or mm < best_mm:
						best = cell
						best_mm = mm
					break
	return best


func test_a_walker_routed_round_the_members_is_forecast_exactly() -> void:
	_w = SecurityTestWorld.make(false)
	var sim := _w.world.sim
	var line: Array = sim.layout.line_of(_w.station)
	var members: Array[Passenger] = []
	for i in MEMBERS:
		members.append(HoldLineKit.member(_w.world, _w.station, i % 2))
	var start := _crossing_start(sim.grid, line)
	var plain := _plain_approach(sim.grid, line, start, MEMBERS)
	print("line %s, start %s, plain %s" % [line, start, plain])
	# Control: a start exists whose plain route crosses the members.
	assert_that(start).is_not_equal(Vector2i(-1, -1))
	var walker := HoldLineKit.passenger(_w.world, start, Passenger.Stage.TO_SECURITY, 1)
	var ids: Array[int] = [walker.id]
	for m in members:
		ids.append(m.id)
	var forecasts := []
	var least := INF
	var on_member := 0
	var walked := {}
	# A forecast is read between ticks, once the world has stepped.
	_w.world.step()
	while not ids.all(func(id: int) -> bool: return _w.cleared.has(id)):
		assert_int(sim.tick).is_less(4000)
		if sim.tick >= 4000:
			return
		for id in ids:
			var p := _w.world.passenger(id)
			if p.station == _w.station and not _w.cleared.has(id):
				forecasts.append([sim.tick, id, sim.tick + SecurityForecast.eta(sim, p)])
		_w.world.step()
		if walker.stage == Passenger.Stage.TO_SECURITY:
			walked[walker.at] = true
			for m in members:
				if m.stage != Passenger.Stage.SECURITY_QUEUE:
					continue
				on_member += int(not walker.is_moving() and walker.at == m.at)
				least = minf(least, walker.grid_position().distance_to(m.grid_position()))
	var wrong := []
	for entry: Array in forecasts:
		if entry[2] != _w.cleared[entry[1]]:
			wrong.append(entry + [_w.cleared[entry[1]]])
	print(
		(
			"%d forecasts, cleared %s, walker walked %d cells, least to a member %.3f m"
			% [forecasts.size(), _w.cleared, walked.size(), least]
		)
	)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, measured] %s" % [wrong])
		. is_empty()
	)
	assert_int(forecasts.size()).is_greater(MEMBERS * 50)
	assert_int(walked.size()).is_greater_equal(3)
	assert_int(on_member).is_equal(0)
	assert_float(least).is_greater_equal(0.70)
