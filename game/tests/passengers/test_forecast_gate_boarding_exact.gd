class_name TestForecastGateBoardingExact
extends GdUnitTestSuite
## A queue front held for a gate place (Passenger.Stuck.GATE_FULL) needs no
## place once its boarding opens (GateCapacity.placed()), and the sim admits
## it on that tick. The security forecast must not skip past it: with the
## gate full, the front's boarding opening a short while ahead and nothing
## else moving, each queued passenger's forecast is made skipping and with
## SecurityForecast.every_tick set, and the two are equal; the front's equals
## the tick it is measured to be cleared.

## Ticks from the forecast until the front's boarding opens: more than any
## replay step, with nothing else moving in between.
const OPENS := 60

var _gate: GateFullWorld
var _cleared := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	SecurityForecast.every_tick = false
	if _gate != null:
		_gate.world.free_all()
	_gate = null
	_cleared.clear()


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if stage == Passenger.Stage.TO_GATE and not _cleared.has(id):
		_cleared[id] = _gate.world.sim.tick


func test_a_front_held_for_a_place_is_forecast_cleared_once_its_boarding_opens() -> void:
	_gate = GateFullWorld.make()
	var sim := _gate.world.sim
	sim.stage_changed.connect(_on_stage)
	_gate.send_many(GateFullWorld.SPOTS + 3)
	var full := func() -> bool:
		var f := _gate.front()
		return f != null and f.stuck == Passenger.Stuck.GATE_FULL and not f.is_moving()
	assert_bool(_gate.run_until(full)).is_true()
	# Let the line settle, so only the front's boarding can change anything.
	_gate.world.run_to(sim.tick + 100)
	var front := _gate.front()
	assert_int(front.stuck).is_equal(Passenger.Stuck.GATE_FULL)
	front.boarding_tick = sim.tick + OPENS
	var ids: Array = sim.queue_of(_gate.station) + sim.holding_of(_gate.station)
	var now := sim.tick
	var scarce := sim.gates.scarce(sim, _gate.station, front)
	var skipping := SecurityForecast.clearances(sim, _gate.station, ids)
	SecurityForecast.every_tick = true
	var every := SecurityForecast.clearances(sim, _gate.station, ids)
	SecurityForecast.every_tick = false
	var done := func() -> bool: return _cleared.has(front.id)
	assert_bool(_gate.run_until(done, OPENS + 1000)).is_true()
	var wrong := []
	for id: int in every:
		if skipping.get(id, -1) != every[id]:
			wrong.append([id, skipping.get(id, -1), every[id]])
	print(
		(
			(
				"tick %d, scarce %s, front %d boards at %d, forecast %d, every tick %d,"
				+ " cleared %d; %d forecasts, wrong %s"
			)
			% [
				now,
				scarce,
				front.id,
				front.boarding_tick,
				now + int(skipping.get(front.id, -1)),
				now + int(every.get(front.id, -1)),
				_cleared[front.id],
				every.size(),
				wrong,
			]
		)
	)
	# The gate places were replayed, and the front was held for one.
	assert_bool(scarce).is_true()
	assert_int(every.size()).is_equal(ids.size())
	(
		assert_array(wrong)
		. override_failure_message("[id, skipping, every tick] %s" % [wrong])
		. is_empty()
	)
	assert_int(now + int(skipping[front.id])).is_equal(_cleared[front.id])
	assert_int(_cleared[front.id]).is_greater_equal(front.boarding_tick)
