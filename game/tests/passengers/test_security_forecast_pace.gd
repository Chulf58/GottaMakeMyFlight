class_name TestSecurityForecastPace
extends GdUnitTestSuite
## SecurityForecast replays each walker at the pace the sim gives it (board
## b13ac401): a late passenger runs to its security station, so its forecast
## clearance, read between ticks, is the tick it is really cleared. Before,
## the replay walked every passenger, and a runner was forecast cleared late.

## Doors close soon after the passenger is sent, so it is late and runs.
const BOARDING := 20
const DOORS := 160
const SEND_AT := 5

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


func test_a_late_runner_is_forecast_cleared_on_the_tick_it_is_cleared() -> void:
	var grid := SecurityTestWorld.build_grid(false)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	var station: int = _world.sim.layout.scanners[0]
	var cleared := {}
	_world.sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if stage == Passenger.Stage.TO_GATE:
				cleared[id] = _world.clock.tick
	)
	_world.run_to(SEND_AT)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.hunger = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	# The forecast clearance tick on each tick it is late and on its way to or
	# queuing at its station.
	var forecasts := {}
	while not cleared.has(id) and _world.clock.tick < DOORS:
		var on_way := p.stage in [Passenger.Stage.TO_SECURITY, Passenger.Stage.SECURITY_QUEUE]
		if on_way and p.station == station and p.late:
			forecasts[_world.sim.tick] = _world.sim.tick + SecurityForecast.eta(_world.sim, p)
		_world.step()
	var actual: int = cleared.get(id, -1)
	var wrong := []
	for at: int in forecasts:
		if forecasts[at] != actual:
			wrong.append([at, forecasts[at]])
	print(
		(
			"cleared at %d; forecasts while late %d, first %s, wrong [tick, forecast] %s"
			% [actual, forecasts.size(), forecasts.values().slice(0, 3), wrong.slice(0, 5)]
		)
	)
	# Controls: it was cleared, and forecast while running.
	assert_int(actual).is_greater(0)
	assert_int(forecasts.size()).is_greater(10)
	assert_array(wrong).is_empty()
