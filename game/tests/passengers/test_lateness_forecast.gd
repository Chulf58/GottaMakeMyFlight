class_name TestLatenessForecast
extends GdUnitTestSuite
## The whole-journey lateness forecast and its walk/run hysteresis.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_hysteresis_turns_on_below_one_slack_and_off_above_another() -> void:
	var on := JourneyForecast.RUN_ON_SLACK
	var off := JourneyForecast.RUN_OFF_SLACK
	assert_int(off).is_greater(on)
	var late := false
	var seen: Array[bool] = []
	for slack in [off + 50, on, on - 1, on + 10, off - 1, off, on + 1, on - 1]:
		late = JourneyForecast.next_late(late, slack)
		seen.append(late)
	assert_array(seen).is_equal([false, false, true, true, true, false, false, true])


func test_early_passenger_walks_and_a_late_one_runs() -> void:
	_world = PassengerTestWorld.reference_world()
	var early := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(40)
	assert_bool(_world.passenger(early).late).is_false()
	assert_int(_moved_mm(early, 5)).is_equal(5 * PassengerSim.WALK_MM)
	_world.run_to(1450)
	var late := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(1475)
	var p := _world.passenger(late)
	assert_bool(p.late).is_true()
	assert_str(_world.sim.bubble_text(p)).is_equal("I'm late!")
	while p.stage != Passenger.Stage.APRON and _world.clock.tick < 1890:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	assert_int(_moved_mm(late, 5)).is_equal(5 * PassengerSim.RUN_MM)


func test_late_flag_does_not_flicker_on_the_way_to_the_plane() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(1250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var flips := 0
	var was := false
	while _world.clock.tick < 1899 and _world.passenger(id).stage < Passenger.Stage.MADE:
		_world.step()
		var now := _world.passenger(id).late
		if now != was:
			flips += 1
			was = now
	assert_int(flips).is_between(1, 2)


func test_queue_wait_makes_the_forecast_later() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 4000))
	var first := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var alone := JourneyForecast.arrival_tick(_world.sim, _world.passenger(first))
	for i in 6:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var crowded_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var crowded := JourneyForecast.arrival_tick(_world.sim, _world.passenger(crowded_id))
	assert_int(crowded).is_greater(alone + PassengerSim.CHECKIN_TICKS)


## Distance one passenger covers over `ticks` ticks.
func _moved_mm(id: int, ticks: int) -> int:
	var before := _world.passenger(id).odometer_mm
	_world.run_to(_world.clock.tick + ticks)
	return _world.passenger(id).odometer_mm - before


## A passenger placed at the gate cell, standing, with boarding still ahead.
func test_standing_passenger_cannot_leave_before_boarding_opens() -> void:
	_world = PassengerTestWorld.reference_world()
	var p := Passenger.new()
	p.stage = Passenger.Stage.STANDING
	p.at = Vector2i(15, 5)
	p.cleared = true
	p.boarding_tick = _world.sim.tick + 1000
	assert_int(JourneyForecast.arrival_tick(_world.sim, p)).is_greater(p.boarding_tick)


## Two idle scanners; one or both then get a passenger mid-service.
func _forecast_with_scanner_load(busy: Array[int], ticks_left: int) -> int:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 4000))
	# The forecast is read before any tick, so the stations are staffed here.
	StaffTestKit.staff_all(_world.staff)
	var scanners: Array = ReferenceTerminal.object_ids(_world.grid)["scanners"]
	var subject := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	# A scanner's service in progress is SecurityRuntime state: one admitted
	# passenger scanning, with `ticks_left` of work and no incident.
	for index in busy:
		var served := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		served.stage = Passenger.Stage.SECURITY
		served.station = scanners[index]
		served.liquids = false
		served.alarm = false
		served.security_phase = SecurityRuntime.Phase.SCAN
		served.security_work = ticks_left
		_world.sim.security.records[scanners[index]] = {
			"admitted": [served.id], "returns": [], "main": served.id, "berth": 0
		}
	return JourneyForecast.arrival_tick(_world.sim, _world.passenger(subject))


func test_forecast_before_check_in_sees_the_scanner_queue() -> void:
	var idle := _forecast_with_scanner_load([], 0)
	_world.free_all()
	var one_busy := _forecast_with_scanner_load([0], 300)
	_world.free_all()
	var both_busy := _forecast_with_scanner_load([0, 1], 300)
	# One scanner still free: the forecast takes it and barely moves.
	assert_int(one_busy - idle).is_less(60)
	# Both busy for 300 ticks: the passenger waits for the sooner one.
	assert_int(both_busy - idle).is_greater(200)
