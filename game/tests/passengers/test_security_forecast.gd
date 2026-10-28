class_name TestSecurityForecast
extends GdUnitTestSuite
## The security forecast replays the station on a copy of its state
## (decision security-lane-technical-design-one-station-per-lane-with-int,
## point 3): read between ticks, with fixed traits and nobody running, it
## equals the tick each passenger is measured to be cleared, whatever phase
## the passenger is in, and reading it changes nothing.

## [bags, liquids, alarm]: every bag count and both incidents, back to back.
const TRAITS := [
	[1, false, false],
	[2, true, false],
	[0, false, true],
	[2, false, false],
	[1, true, false],
	[0, false, false],
	[2, false, false],
]
## Ticks after the last passenger is sent at which every committed
## passenger's clearance is forecast.
const CHECKPOINTS: Array[int] = [0, 7, 45, 110, 190, 260, 330]

var _worlds: Array[SecurityTestWorld] = []
var _lanes_were := false


func before() -> void:
	PassengerTestWorld.tracker = self
	_lanes_were = SecurityLanes.enabled
	SecurityLanes.enabled = true


func after() -> void:
	PassengerTestWorld.tracker = null
	SecurityLanes.enabled = _lanes_were


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## Forecasts at each checkpoint: [tick, id, phase, forecast clearance tick].
func _forecasts(w: SecurityTestWorld, ids: Array[int]) -> Array:
	var out := []
	var start := w.world.clock.tick
	for at in CHECKPOINTS:
		w.world.run_to(start + at)
		for id in ids:
			var p := w.world.passenger(id)
			if p.station != w.station:
				continue
			var before := w.signature()
			var eta := SecurityForecast.eta(w.world.sim, p)
			assert_str(w.signature()).is_equal(before)
			out.append([w.world.sim.tick, id, p.security_phase, w.world.sim.tick + eta])
	return out


func _check_tier(use_lane: bool) -> void:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	var ids := w.send_all(TRAITS)
	var forecasts := _forecasts(w, ids)
	assert_bool(w.run_until_cleared(ids)).is_true()
	var wrong := []
	var phases := {}
	for entry: Array in forecasts:
		phases[entry[2]] = true
		if entry[3] != w.cleared[entry[1]]:
			wrong.append(entry + [w.cleared[entry[1]]])
	print(
		(
			"lane %s: %d forecasts over phases %s, cleared %s"
			% [use_lane, forecasts.size(), phases.keys(), w.cleared]
		)
	)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, phase, forecast, measured] %s" % [wrong])
		. is_empty()
	)
	assert_int(forecasts.size()).is_greater(20)
	# The checkpoints caught passengers queuing and in service.
	assert_bool(phases.has(SecurityRuntime.Phase.NONE)).is_true()
	assert_int(phases.size()).is_greater(2)


func test_the_forecast_equals_measured_clearance_at_the_basic_scanner() -> void:
	_check_tier(false)


func test_the_forecast_equals_measured_clearance_at_the_lane() -> void:
	_check_tier(true)


func test_a_closed_station_forecasts_never_for_a_newcomer() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	w.world.auto_staff = false
	var id := w.send(1)
	var p := w.world.passenger(id)
	assert_int(w.world.sim.station_eta(w.station, 3000, p)).is_equal(JourneyForecast.NEVER)


func test_the_candidate_forecast_counts_its_own_bags_and_incident() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	w.world.step()
	var light := Passenger.new()
	light.id = 900
	var heavy := Passenger.new()
	heavy.id = 900
	heavy.carry_on = 2
	var incident := Passenger.new()
	incident.id = 900
	incident.liquids = true
	var etas := []
	for p in [light, heavy, incident]:
		etas.append(w.world.sim.station_eta(w.station, 3000, p))
	print("candidate clearance: no bags %d, two bags %d, liquids %d" % etas)
	assert_int(etas[1] - etas[0]).is_equal(
		2 * (SecurityRuntime.LANE_UNPACK_BAG_TICKS + SecurityRuntime.LANE_PICKUP_BAG_TICKS)
	)
	assert_int(etas[2]).is_greater(etas[0] + SecurityRuntime.REPACK_TICKS)


## The replay and its runtime hold each other; the forecast lets go, so
## forecasting on every beat does not pile up objects.
func test_a_forecast_leaves_no_objects_behind() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var ids := w.send_all(TRAITS)
	var p := w.world.passenger(ids[ids.size() - 1])
	SecurityForecast.eta(w.world.sim, p)
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 50:
		SecurityForecast.eta(w.world.sim, p)
	var after := Performance.get_monitor(Performance.OBJECT_COUNT)
	print("objects before %d after %d" % [before, after])
	assert_float(after).is_less(before + 50)
