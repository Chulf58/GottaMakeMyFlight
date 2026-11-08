class_name TestForecastSkipLaneExact
extends GdUnitTestSuite
## SecurityForecast skips the replay ticks on which nothing can change, and an
## admitted passenger walking on through cells off its station's line does
## not wake the replay (SecurityForecast._walk_on_mm()). A skipped tick must
## never change an outcome at either tier: on every tick of a mixed queue,
## through every phase (the berth and the return route at the lane), each
## forecast is made twice on the same sim state, once skipping and once with
## SecurityForecast.every_tick set, and the two must be equal passenger by
## passenger. TestForecastSkipExact covers the cafe streams.

## [bags, liquids, alarm]: both incidents, so the berth and the return route
## are walked, as TestSecurityForecast sends them.
const TRAITS := [
	[1, false, false],
	[2, true, false],
	[0, false, true],
	[2, false, false],
	[1, true, false],
	[0, false, false],
	[2, false, false],
]

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	SecurityForecast.every_tick = false
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## Every tick until all of `ids` are cleared, the forecasts of those committed
## to the station both ways; returns [forecasts compared, steps skipping,
## steps every tick, phases seen] and appends each difference to `wrong` as
## [tick, id, phase, skipping, every tick].
func _compare_run(w: SecurityTestWorld, ids: Array[int], wrong: Array) -> Array:
	var compared := 0
	var skipping_steps := 0
	var every_steps := 0
	var phases := {}
	var sim := w.world.sim
	while not ids.all(func(id: int) -> bool: return w.cleared.has(id)):
		var mine := []
		for id in ids:
			if sim.get_passenger(id).station == w.station and not w.cleared.has(id):
				mine.append(id)
				phases[sim.get_passenger(id).security_phase] = true
		var before := SecurityForecast.steps_played
		var skipping := SecurityForecast.clearances(sim, w.station, mine)
		var mid := SecurityForecast.steps_played
		SecurityForecast.every_tick = true
		var every := SecurityForecast.clearances(sim, w.station, mine)
		SecurityForecast.every_tick = false
		skipping_steps += mid - before
		every_steps += SecurityForecast.steps_played - mid
		for id: int in every:
			compared += 1
			if skipping.get(id, -1) != every[id]:
				var phase := sim.get_passenger(id).security_phase
				wrong.append([sim.tick, id, phase, skipping.get(id, -1), every[id]])
		w.world.step()
	return [compared, skipping_steps, every_steps, phases.keys()]


func _check_tier(use_lane: bool, phases_wanted: Array) -> void:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	var ids := w.send_all(TRAITS)
	var wrong := []
	var made := _compare_run(w, ids, wrong)
	print(
		(
			"lane %s: %d forecasts, %d steps skipping, %d every tick, phases %s, %d wrong"
			% [use_lane, made[0], made[1], made[2], made[3], wrong.size()]
		)
	)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, phase, skipping, every tick] %s" % [wrong])
		. is_empty()
	)
	# Forecasts were made from every phase, and skipping played fewer ticks.
	assert_int(made[0]).is_greater(0)
	assert_int(made[1]).is_less(made[2])
	var seen: Array = made[3]
	seen.sort()
	assert_array(seen).is_equal(phases_wanted)


func test_skipped_ticks_change_no_forecast_at_the_lane() -> void:
	_check_tier(
		true,
		[
			SecurityRuntime.Phase.NONE,
			SecurityRuntime.Phase.UNPACK,
			SecurityRuntime.Phase.ARCH,
			SecurityRuntime.Phase.TO_BERTH,
			SecurityRuntime.Phase.REPACK,
			SecurityRuntime.Phase.RETURN,
			SecurityRuntime.Phase.PICKUP,
			SecurityRuntime.Phase.LEAVE,
		]
	)


func test_skipped_ticks_change_no_forecast_at_the_basic_scanner() -> void:
	_check_tier(
		false,
		[SecurityRuntime.Phase.NONE, SecurityRuntime.Phase.SCAN, SecurityRuntime.Phase.REPACK]
	)
