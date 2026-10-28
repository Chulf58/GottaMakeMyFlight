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
## Every phase of each tier: a forecast is checked from each of them.
const BASIC_PHASES := [
	SecurityRuntime.Phase.NONE, SecurityRuntime.Phase.SCAN, SecurityRuntime.Phase.REPACK
]
const LANE_PHASES := [
	SecurityRuntime.Phase.NONE,
	SecurityRuntime.Phase.UNPACK,
	SecurityRuntime.Phase.ARCH,
	SecurityRuntime.Phase.TO_BERTH,
	SecurityRuntime.Phase.REPACK,
	SecurityRuntime.Phase.RETURN,
	SecurityRuntime.Phase.PICKUP,
	SecurityRuntime.Phase.LEAVE,
]
## Hand timing for the two-passenger cases, independent of SecurityRuntime:
## ticks at rate 1 and the walking speed in millimetres a tick.
const WALK := 98
const SCAN := 40
const SCAN_BAG := 15
const UNPACK := 3
const UNPACK_BAG := 4
const PICKUP := 2
const PICKUP_BAG := 4

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A forecast on every tick, for every passenger committed to the station,
## until all are cleared: [tick, id, phase, forecast clearance tick]. Every
## 25th tick also checks that reading it changes nothing.
func _forecasts(w: SecurityTestWorld, ids: Array[int]) -> Array:
	var out := []
	while not ids.all(func(id: int) -> bool: return w.cleared.has(id)):
		for id in ids:
			var p := w.world.passenger(id)
			if p.station != w.station:
				continue
			var check := w.world.sim.tick % 25 == 0
			var before := w.signature() if check else ""
			var eta := SecurityForecast.eta(w.world.sim, p)
			if check:
				assert_str(w.signature()).is_equal(before)
			out.append([w.world.sim.tick, id, p.security_phase, w.world.sim.tick + eta])
		w.world.step()
	return out


## Every forecast of a mixed queue against the measured clearance; `count`
## is the number of observations the run makes, `phases` the phases seen.
func _check_tier(use_lane: bool, count: int, phases_wanted: Array) -> void:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	var ids := w.send_all(TRAITS)
	var forecasts := _forecasts(w, ids)
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
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
	assert_int(forecasts.size()).is_equal(count)
	var seen := phases.keys()
	seen.sort()
	assert_array(seen).is_equal(phases_wanted)


func test_the_forecast_equals_measured_clearance_at_the_basic_scanner() -> void:
	_check_tier(false, 2720, BASIC_PHASES)


func test_the_forecast_equals_measured_clearance_at_the_lane() -> void:
	_check_tier(true, 2197, LANE_PHASES)


static func _walk(mm: int) -> int:
	@warning_ignore("integer_division")
	return (mm + WALK - 1) / WALK


## Two passengers sent SPACING apart from the entrance (5, 15). A walks 8000
## mm to the first lane cell (5, 7) on ticks 1 to _walk(8000), joins on the
## next tick and is admitted on the one after. B, choosing while A is still
## walking, takes the second lane cell (5, 8): it walks 7000 mm from tick
## SPACING + 1, joins, moves up 1000 mm once A has gone, and stands ready on
## the first lane cell the tick after it arrives.
func _arrivals() -> Vector2i:
	var a_admitted := _walk(8000) + 2
	var b_ready := SecurityTestWorld.SPACING + _walk(7000) + 2 + _walk(1000)
	return Vector2i(a_admitted, b_ready)


## Basic scanner, A with one bag and B with none: each scan runs while the
## passage (3000 mm) is walked, and B starts when A is cleared.
func test_two_passengers_clear_at_hand_worked_ticks_at_the_basic_scanner() -> void:
	var at := _arrivals()
	var a_clear := at.x + maxi(SCAN + SCAN_BAG, _walk(3000))
	var b_clear := maxi(a_clear, at.y) + maxi(SCAN, _walk(3000))
	_check_two(false, Vector2i(a_clear, b_clear))


## Lane, A with one bag and B with none: unpack, the passage to the pickup
## cell (2000 mm), pickup and the step to the exit (1000 mm). B starts once A
## has reached the pickup cell.
func test_two_passengers_clear_at_hand_worked_ticks_at_the_lane() -> void:
	var at := _arrivals()
	var a_past_arch := at.x + UNPACK + UNPACK_BAG + _walk(2000)
	var a_clear := a_past_arch + PICKUP + PICKUP_BAG + _walk(1000)
	var b_admitted := maxi(a_past_arch, at.y)
	var b_clear := b_admitted + UNPACK + _walk(2000) + PICKUP + _walk(1000)
	_check_two(true, Vector2i(a_clear, b_clear))


## Sends A (one bag) and B (none), forecasts both once both are committed,
## then measures; forecast and measurement must both equal `want`.
func _check_two(use_lane: bool, want: Vector2i) -> void:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	var ids := w.send_all([[1, false, false], [0, false, false]])
	var forecast := Vector2i(
		w.world.sim.tick + SecurityForecast.eta(w.world.sim, w.world.passenger(ids[0])),
		w.world.sim.tick + SecurityForecast.eta(w.world.sim, w.world.passenger(ids[1]))
	)
	assert_bool(w.run_until_cleared(ids)).is_true()
	var measured := Vector2i(w.cleared[ids[0]], w.cleared[ids[1]])
	print("lane %s: by hand %s, forecast %s, measured %s" % [use_lane, want, forecast, measured])
	assert_that(forecast).is_equal(want)
	assert_that(measured).is_equal(want)


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
