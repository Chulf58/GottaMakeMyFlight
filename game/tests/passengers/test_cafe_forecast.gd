class_name TestCafeForecast
extends GdUnitTestSuite
## The itinerary forecast for a cafe visit and its leave deadline (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a, point 1): the
## arrival at the plane with the whole visit in it, the boarding wait counted
## once, and a deadline strictly before the doors close.

## Free floor in the reference terminal: airside beside the gate seats, and
## landside between the scanner lanes and the east wall.
const AIRSIDE_CELL := Vector2i(18, 5)
const LANDSIDE_CELL := Vector2i(20, 14)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _legs(dwell: int, cell: Vector2i, resume: Passenger.Stage) -> Dictionary:
	return {
		"pre_ticks": 0,
		"to_queue_mm": 3000,
		"order_ticks": 90,
		"to_seat_mm": 2000,
		"dwell_ticks": dwell,
		"leave_cell": cell,
		"resume_stage": resume,
	}


## A passenger standing still at `cell` in `stage`, for the plain forecast.
func _standing(p: Passenger, cell: Vector2i, stage: Passenger.Stage) -> Passenger:
	var ghost := Passenger.new()
	ghost.id = p.id
	ghost.flight_id = p.flight_id
	ghost.boarding_tick = p.boarding_tick
	ghost.stage = stage
	ghost.cleared = stage == Passenger.Stage.TO_GATE
	ghost.at = cell
	ghost.clear_path()
	return ghost


func _spawned() -> Passenger:
	_world = PassengerTestWorld.reference_world()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(10)
	return _world.passenger(id)


func test_arrival_from_now_is_the_arrival_forecast() -> void:
	_world = PassengerTestWorld.reference_world(7)
	for i in 8:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var compared := 0
	for target in [60, 240, 520, 760]:
		_world.run_to(target)
		for id in _world.sim.passenger_ids():
			var p := _world.passenger(id)
			var plain := JourneyForecast.arrival_tick(_world.sim, p)
			assert_int(JourneyForecast.arrival_from(_world.sim, p, _world.clock.tick)).is_equal(
				plain
			)
			compared += 1
	assert_int(compared).is_equal(32)


func test_a_passenger_heading_for_security_before_choosing_a_scanner_has_a_forecast() -> void:
	var p := _spawned()
	var landside := _standing(p, LANDSIDE_CELL, Passenger.Stage.TO_SECURITY)
	# The far end of the nearer scanner's passage (x 19), where security ends.
	var airside := _standing(p, Vector2i(19, 7), Passenger.Stage.TO_GATE)
	# With no boarding wait, the walk to and through security shows in full.
	landside.boarding_tick = 0
	airside.boarding_tick = 0
	var with_security := JourneyForecast.arrival_tick(_world.sim, landside)
	var past_security := JourneyForecast.arrival_tick(_world.sim, airside)
	print("landside %d airside %d" % [with_security, past_security])
	assert_int(with_security).is_less(JourneyForecast.NEVER)
	assert_int(with_security).is_greater(past_security + PassengerSim.SECURITY_TICKS)
	for scanner in ReferenceTerminal.object_ids(_world.grid)["scanners"]:
		assert_bool(_world.grid.apply(BuildEdit.remove_object(scanner)).ok).is_true()
	assert_int(JourneyForecast.arrival_tick(_world.sim, landside)).is_equal(JourneyForecast.NEVER)


func test_a_short_visit_before_boarding_adds_nothing_to_the_arrival() -> void:
	var p := _spawned()
	var legs := _legs(100, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	var end := CafeForecast.visit_end(_world.sim, legs)
	var plain := JourneyForecast.arrival_tick(
		_world.sim, _standing(p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	)
	print("visit end %d boarding %d plain %d" % [end, p.boarding_tick, plain])
	assert_int(end + PassengerSim.STAND_UP_TICKS).is_less(p.boarding_tick)
	assert_int(CafeForecast.visit_arrival(_world.sim, p, legs)).is_equal(plain)


func test_a_long_visit_counts_the_walk_out_after_it_and_no_boarding_wait() -> void:
	var p := _spawned()
	var exit_ticks := (
		JourneyForecast.arrival_tick(
			_world.sim, _standing(p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
		)
		- p.boarding_tick
	)
	var legs := _legs(900, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	var end := CafeForecast.visit_end(_world.sim, legs)
	var expected_end := (
		_world.clock.tick
		+ JourneyForecast.walk_ticks(3000)
		+ 90
		+ JourneyForecast.walk_ticks(2000)
		+ PassengerSim.SIT_DOWN_TICKS
		+ 900
	)
	assert_int(end).is_equal(expected_end)
	assert_int(end).is_greater(p.boarding_tick)
	var arrival := CafeForecast.visit_arrival(_world.sim, p, legs)
	print("end %d exit %d arrival %d" % [end, exit_ticks, arrival])
	assert_int(arrival).is_equal(end + PassengerSim.STAND_UP_TICKS + exit_ticks)


func test_the_deadline_is_doors_close_less_the_margin_and_the_walk_out() -> void:
	var p := _spawned()
	var doors := _world.flights.doors_close_tick(p.flight_id)
	var exit_ticks := (
		JourneyForecast.arrival_tick(
			_world.sim, _standing(p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
		)
		- p.boarding_tick
	)
	var leave := CafeForecast.leave_ticks(_world.sim, p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	var deadline := CafeForecast.deadline(_world.sim, p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	print("doors %d leave %d deadline %d" % [doors, leave, deadline])
	assert_int(leave).is_equal(PassengerSim.STAND_UP_TICKS + exit_ticks)
	assert_int(deadline).is_equal(doors - CafeForecast.MARGIN_TICKS - leave)
	assert_int(deadline).is_less(doors)
	assert_int(CafeForecast.MARGIN_TICKS).is_greater(JourneyForecast.RUN_ON_SLACK)


func test_a_landside_visit_resumes_through_security() -> void:
	var p := _spawned()
	var land := CafeForecast.leave_ticks(_world.sim, p, LANDSIDE_CELL, Passenger.Stage.TO_SECURITY)
	var air := CafeForecast.leave_ticks(_world.sim, p, AIRSIDE_CELL, Passenger.Stage.TO_GATE)
	print("leave landside %d airside %d" % [land, air])
	assert_int(land).is_less(JourneyForecast.NEVER)
	assert_int(land).is_greater(air + PassengerSim.SECURITY_TICKS)


func test_admission_needs_the_margin_before_doors_close() -> void:
	var p := _spawned()
	var doors := _world.flights.doors_close_tick(p.flight_id)
	assert_bool(CafeForecast.admits(_world.sim, p, doors - CafeForecast.MARGIN_TICKS)).is_true()
	(
		assert_bool(CafeForecast.admits(_world.sim, p, doors - CafeForecast.MARGIN_TICKS + 1))
		. is_false()
	)


func test_an_admitted_visit_stands_up_by_its_deadline() -> void:
	var p := _spawned()
	var admitted := 0
	var refused := 0
	for resume in [Passenger.Stage.TO_GATE, Passenger.Stage.TO_SECURITY]:
		var cell := AIRSIDE_CELL if resume == Passenger.Stage.TO_GATE else LANDSIDE_CELL
		var deadline := CafeForecast.deadline(_world.sim, p, cell, resume)
		for dwell in range(0, 2400, 60):
			var legs := _legs(dwell, cell, resume)
			if CafeForecast.admits(_world.sim, p, CafeForecast.visit_arrival(_world.sim, p, legs)):
				admitted += 1
				assert_int(CafeForecast.visit_end(_world.sim, legs)).is_less_equal(deadline)
			else:
				refused += 1
	print("admitted %d refused %d" % [admitted, refused])
	assert_int(admitted).is_greater(10)
	assert_int(refused).is_greater(10)
