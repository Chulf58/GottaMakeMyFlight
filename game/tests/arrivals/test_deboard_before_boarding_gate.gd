class_name TestDeboardBeforeBoardingGate
extends GdUnitTestSuite
## Regression tests for board 964a722b: departing passengers do not start
## boarding until all deboarding arrivals for their flight have crossed into
## the terminal (with a bounded safety timeout so a stuck arrival cannot
## deadlock boarding).

const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _site_world(deboard_ticks := 60, boarding_ticks := 380) -> PassengerTestWorld:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, SITE.starter_offset)).is_true()
	var starts := FlightSim.schedule_starts(0, TaxiTimes.BASE, boarding_ticks, deboard_ticks)
	var world := PassengerTestWorld.make(grid, starts, 77)
	world.sim.site = SITE
	return world


func _seated_departee(world: PassengerTestWorld, at: Vector2i) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.at = at
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	return p


func test_boarding_waits_for_all_deplaning_arrivals_to_enter_terminal() -> void:
	_world = _site_world(60, 380)
	var sim := _world.sim
	var deboard_window := _world.flights.deboarding_window(PassengerTestWorld.FLIGHT)
	var board_window := _world.flights.boarding_window(PassengerTestWorld.FLIGHT)
	_world.run_to(deboard_window.x)

	var departees: Array[Passenger] = []
	for _i in 4:
		departees.append(_seated_departee(_world, SITE.starter_offset + Vector2i(14, 5)))
	PassengerArrivals.schedule_deboarding(sim, PassengerTestWorld.FLIGHT, 6)

	var saw_hold_past_boarding := false
	var overlap_on_apron := 0
	var first_board_tick := -1
	var last_deplane_exit_tick := -1

	while _world.clock.tick < board_window.y:
		_world.step()
		var deplaning := 0
		var boarding_out := 0
		for id in sim.passenger_ids():
			var p := sim.get_passenger(id)
			if p.is_done():
				continue
			if p.is_arriving() and p.stage == Passenger.Stage.DEPLANING:
				deplaning += 1
			elif p.is_departing() and p.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]:
				boarding_out += 1
				if first_board_tick < 0:
					first_board_tick = _world.clock.tick
		if deplaning > 0:
			last_deplane_exit_tick = _world.clock.tick
			if _world.clock.tick >= board_window.x:
				saw_hold_past_boarding = true
			if boarding_out > 0:
				overlap_on_apron += 1
		if sim.made_count() == departees.size():
			break

	print(
		(
			"board_window=%s last_deplaning=%d first_board=%d overlap=%d made=%d missed=%d"
			% [
				board_window,
				last_deplane_exit_tick,
				first_board_tick,
				overlap_on_apron,
				sim.made_count(),
				sim.missed_count()
			]
		)
	)
	assert_bool(saw_hold_past_boarding).is_true()
	assert_int(overlap_on_apron).is_equal(0)
	assert_int(first_board_tick).is_greater(last_deplane_exit_tick)
	assert_int(sim.made_count()).is_equal(departees.size())
	assert_int(sim.missed_count()).is_equal(0)


func test_deboarding_gate_releases_at_bounded_cap_if_arrival_stuck() -> void:
	_world = _site_world(100, 1200)
	var sim := _world.sim
	var board_window := _world.flights.boarding_window(PassengerTestWorld.FLIGHT)
	_world.run_to(board_window.x - 10)
	var departee := _seated_departee(_world, SITE.starter_offset + Vector2i(14, 5))
	var stuck_arr := PassengerArrivals.spawn(sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(stuck_arr).is_not_null()
	assert_int(stuck_arr.stage).is_equal(Passenger.Stage.DEPLANING)

	var cap_tick := PassengerArrivals.deboarding_hold_cap_tick(
		sim, PassengerTestWorld.FLIGHT, stuck_arr.spawn_tick
	)
	assert_int(cap_tick).is_greater(board_window.x)
	assert_int(cap_tick).is_less(board_window.y)

	# Pin the arrival in DEPLANING so it never finishes normally.
	while _world.clock.tick < cap_tick - 1:
		stuck_arr.apron_mm = 0
		_world.step()
	assert_bool(departee.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]).is_false()

	# Once cap_tick arrives, boarding opens despite the stuck DEPLANING arrival.
	while _world.clock.tick < board_window.y and not departee.is_done():
		stuck_arr.apron_mm = 0
		_world.step()

	print(
		(
			"cap_tick=%d departee_stage=%s outcome=%d"
			% [cap_tick, Passenger.Stage.keys()[departee.stage], departee.outcome_tick]
		)
	)
	assert_int(departee.stage).is_equal(Passenger.Stage.MADE)
	assert_int(sim.missed_count()).is_equal(0)


func test_deboarding_gate_holds_while_inbound_arrival_is_on_bus() -> void:
	_world = _site_world(100, 1200)
	var sim := _world.sim
	var board_window := _world.flights.boarding_window(PassengerTestWorld.FLIGHT)
	_world.run_to(board_window.x - 10)
	var departee := _seated_departee(_world, SITE.starter_offset + Vector2i(14, 5))
	var bus_arr := PassengerArrivals.spawn(sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(bus_arr).is_not_null()
	PassengerArrivals.board_bus(sim, bus_arr)
	assert_int(bus_arr.stage).is_equal(Passenger.Stage.ON_BUS)

	_world.run_to(board_window.x + 25)
	assert_bool(departee.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]).is_false()

	# Bus arrives and unloads inbound passenger into the terminal -> boarding opens.
	PassengerArrivals.unload_from_bus(sim, bus_arr, bus_arr.exit_object)
	assert_int(bus_arr.stage).is_equal(Passenger.Stage.TO_AIRSIDE_EXIT)
	while _world.clock.tick < board_window.y and not departee.is_done():
		_world.step()
	assert_int(departee.stage).is_equal(Passenger.Stage.MADE)
	assert_int(sim.missed_count()).is_equal(0)
