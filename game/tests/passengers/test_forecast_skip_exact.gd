class_name TestForecastSkipExact
extends GdUnitTestSuite
## SecurityForecast skips the replay ticks on which nothing can change
## (_next_event()). A skipped tick must never change an outcome: every
## forecast here is made twice on the same sim state, once as the forecast
## plays it and once with SecurityForecast.every_tick set, which plays every
## tick, and the two must be equal passenger by passenger. The streams are
## the two-station burst of TestHoldLineForecast and the stream of
## passengers who have just checked in of TestCafeDeadline, over a short
## window.

## Just checked in, between the desks and the scanner lanes (CafeTestLayout).
const CROWD_CELL := Vector2i(16, 12)
## More than both scanners' lines hold together.
const BURST := 32
## TestCafeDeadline's stream: one more passenger this often, from START.
const CROWD_EVERY := 7
const START := 200
## The window of the stream played, and how often it is forecast.
const WINDOW := 260
const EVERY := 10
## How often the two-station burst is forecast (each one replays it all).
const BURST_EVERY := 20
## The most waiting passengers forecast on one tick (each is its own replay).
const SEEKERS := 3

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	SecurityForecast.every_tick = false
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _new_passenger(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	return p


## A passenger who has just checked in and heads for security.
func _checked_in(world: PassengerTestWorld) -> Passenger:
	var p := _new_passenger(world)
	p.stage = Passenger.Stage.TO_SECURITY
	p.service_end = world.clock.tick
	p.at = CROWD_CELL
	p.clear_path()
	return p


## Every forecast of `sim`'s passengers at security on its tick: id ->
## clearance by station for the committed ones (SecurityForecast.clearances()),
## and for up to SEEKERS waiting ones, its clearance at each scanner.
func _forecasts(sim: PassengerSim) -> Dictionary:
	# A waiting passenger's answer is kept for the next ask on the tick.
	SecurityForecast._waiting_memo = []
	var out := {}
	for station: int in sim.layout.scanners:
		var ids := []
		for p in sim._passengers:
			var at_security := (
				p.stage
				in [
					Passenger.Stage.TO_SECURITY,
					Passenger.Stage.SECURITY_QUEUE,
					Passenger.Stage.SECURITY,
				]
			)
			if at_security and p.station == station:
				ids.append(p.id)
		var some := SecurityForecast.clearances(sim, station, ids)
		for id: int in some:
			out["%d@%d" % [id, station]] = some[id]
	var seekers := 0
	for p in sim._passengers:
		if seekers >= SEEKERS or not PassengerStations.is_seeking(sim, p, false):
			continue
		seekers += 1
		for station: int in sim.layout.scanners:
			SecurityForecast._waiting_memo = []
			var ticks := SecurityForecast.clearance(sim, station, p, sim.tick + 1)
			out["waiting %d@%d" % [p.id, station]] = ticks
	return out


## Forecasts `sim` both ways and appends to `wrong` each forecast that
## differs: [tick, key, skipping, every tick]. Returns [forecasts compared,
## steps played skipping, steps played every tick].
func _compare(sim: PassengerSim, wrong: Array) -> Array:
	var before := SecurityForecast.steps_played
	var skipping := _forecasts(sim)
	var mid := SecurityForecast.steps_played
	SecurityForecast.every_tick = true
	var every := _forecasts(sim)
	SecurityForecast.every_tick = false
	for key: String in every:
		if skipping.get(key, -1) != every[key]:
			wrong.append([sim.tick, key, skipping.get(key, -1), every[key]])
	for key: String in skipping:
		if not every.has(key):
			wrong.append([sim.tick, key, skipping[key], -1])
	return [every.size(), mid - before, SecurityForecast.steps_played - mid]


func _report(name: String, totals: Array, wrong: Array) -> void:
	print(
		(
			"%s: %d forecasts, %d steps skipping, %d every tick, %d wrong"
			% [name, totals[0], totals[1], totals[2], wrong.size()]
		)
	)
	(
		assert_array(wrong)
		. override_failure_message("[tick, passenger@station, skipping, every tick] %s" % [wrong])
		. is_empty()
	)
	# Forecasts were made, and skipping played fewer ticks than every tick.
	assert_int(totals[0]).is_greater(0)
	assert_int(totals[1]).is_less(totals[2])


func test_skipped_ticks_change_no_forecast_at_two_stations() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(3000))
	_worlds.append(world)
	var sim := world.sim
	for i in BURST:
		_checked_in(world)
	var wrong := []
	var totals := [0, 0, 0]
	for i in 600:
		if sim.tick % BURST_EVERY == 0 and sim.layout.scanners.all(sim._is_open):
			var made := _compare(sim, wrong)
			for k in 3:
				totals[k] += made[k]
		world.step()
	_report("two stations", totals, wrong)


func test_skipped_ticks_change_no_forecast_in_the_cafe_stream() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	world.run_to(START)
	var wrong := []
	var totals := [0, 0, 0]
	while world.clock.tick < START + WINDOW:
		if posmod(world.clock.tick, CROWD_EVERY) == 0:
			_checked_in(world)
		if world.clock.tick % EVERY == 0:
			var made := _compare(world.sim, wrong)
			for k in 3:
				totals[k] += made[k]
		world.step()
	_report("cafe stream", totals, wrong)


## The whole stream played twice, the sim's own forecasts once skipping and
## once every tick: each tick, every passenger's stage, cell, station and
## outcome are the same.
func test_skipped_ticks_change_no_outcome_of_the_cafe_stream() -> void:
	var runs := []
	for every in [false, true]:
		SecurityForecast.every_tick = every
		var grid := BuildGrid.new()
		CafeTestLayout.build(grid)
		var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		_worlds.append(world)
		world.run_to(START)
		var states := []
		while world.clock.tick < START + WINDOW:
			if posmod(world.clock.tick, CROWD_EVERY) == 0:
				_checked_in(world)
			world.step()
			var state := [world.clock.tick]
			for p in world.sim._passengers:
				state.append([p.id, p.stage, p.at, p.station, p.outcome_tick, p.late])
			states.append(state)
		runs.append(states)
	SecurityForecast.every_tick = false
	var first := -1
	for i in runs[0].size():
		if runs[0][i] != runs[1][i]:
			first = i
			break
	if first >= 0:
		print("skipping: %s\nevery tick: %s" % [runs[0][first], runs[1][first]])
	assert_int(runs[0].size()).is_equal(WINDOW)
	assert_int(first).is_equal(-1)
