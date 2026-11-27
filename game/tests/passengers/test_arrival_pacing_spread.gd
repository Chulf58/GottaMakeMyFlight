class_name TestArrivalPacingSpread
extends GdUnitTestSuite
## Arrival pacing & spread (decision 21d34b4f):
## - LAST_SPAWN_LEAD_TICKS is early enough that zero-queue TYPICAL passengers
##   do not turn late immediately after security and still have spare dwell time.
## - ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS opens around SCHEDULED (~2660 ticks
##   before PUSHBACK) while RELAXED remains up to RELAXED_LEAD_TICKS early.
## - ArrivalBookings caps small-flight party sizes (<= 2 when <= 12 pax) and
##   spreads vehicle arrivals across each arrival-type window.

const FIRST := 4400


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func test_typical_passengers_have_spare_dwell_time_after_security_without_turning_late() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST), 7)
	var sim := world.sim
	var cleared_at := {}
	var late_after_security := {}
	var types := {}
	sim.passenger_spawned.connect(
		func(id: int) -> void: types[id] = sim.get_passenger(id).arrival_type
	)
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if stage == Passenger.Stage.TO_GATE and not cleared_at.has(id):
				cleared_at[id] = sim.tick
	)
	var count := 10
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while world.clock.tick <= doors:
		world.step()
		for id: int in cleared_at:
			if (
				not late_after_security.has(id)
				and sim.tick >= int(cleared_at[id]) + PassengerSim.BEAT_TICKS
			):
				var p := sim.get_passenger(id)
				if p != null:
					late_after_security[id] = p.late
	var typical_count := 0
	var typical_late := 0
	var typical_before_boarding := 0
	var typical_dwell_sum := 0
	for id: int in types:
		if types[id] == ArrivalTypes.Type.TYPICAL:
			typical_count += 1
			if bool(late_after_security.get(id, false)):
				typical_late += 1
			var clear_tick := int(cleared_at.get(id, doors))
			if clear_tick < boarding:
				typical_before_boarding += 1
			typical_dwell_sum += boarding - clear_tick
	print(
		(
			"typical=%d late=%d before_boarding=%d mean_dwell=%d made=%d missed=%d"
			% [
				typical_count,
				typical_late,
				typical_before_boarding,
				typical_dwell_sum / maxi(typical_count, 1),
				sim.made_count(),
				sim.missed_count(),
			]
		)
	)
	assert_int(typical_count).is_greater(0)
	assert_int(typical_late).is_equal(0)
	assert_int(typical_before_boarding * 2).is_greater_equal(typical_count)
	assert_int(sim.made_count()).is_equal(count)
	assert_int(sim.missed_count()).is_equal(0)
	world.free_all()


func test_small_flight_vehicles_are_capped_and_spread_across_arrival_window() -> void:
	var checked_gaps := 0
	for seed in [3, 7, 11]:
		var land := LandsideTestWorld.make(null, FlightSim.schedule_starts(FIRST), seed)
		var count := 8
		land.schedule(count)
		var parties := {}
		var by_type := {}
		var typical_vehicles: Array[int] = []
		var all_vehicles: Array[int] = []
		for id in land.sim.arrivals.booking_ids():
			var b := land.sim.arrivals.get_booking(id)
			if not parties.has(b.party):
				parties[b.party] = []
				all_vehicles.append(b.unload_tick)
				if not by_type.has(b.arrival):
					by_type[b.arrival] = []
				(by_type[b.arrival] as Array).append(b.unload_tick)
				if b.arrival == ArrivalTypes.Type.TYPICAL:
					typical_vehicles.append(b.unload_tick)
			(parties[b.party] as Array).append(b.unload_tick)
		var max_party_size := 0
		for party in parties:
			max_party_size = maxi(max_party_size, (parties[party] as Array).size())
		all_vehicles.sort()
		typical_vehicles.sort()
		var span_all := all_vehicles[-1] - all_vehicles[0]
		var span_typ := (
			typical_vehicles[-1] - typical_vehicles[0] if typical_vehicles.size() >= 2 else 999
		)
		for arrival in by_type:
			var ticks: Array = by_type[arrival]
			ticks.sort()
			if ticks.size() < 2:
				continue
			var win := ArrivalTypes.window(
				arrival, land.world.flights, PassengerTestWorld.FLIGHT, land.sim.clock.tick
			)
			var width := win.y - win.x + 1
			if width >= ticks.size() * (2 * ArrivalBookings.INTER_VEHICLE_GAP_TICKS + 1):
				for i in range(1, ticks.size()):
					checked_gaps += 1
					assert_int(int(ticks[i]) - int(ticks[i - 1])).is_greater_equal(
						ArrivalBookings.INTER_VEHICLE_GAP_TICKS
					)
		print(
			(
				"seed %d: vehicles=%d max_party=%d all_span=%d typ_span=%d typ=%s"
				% [seed, parties.size(), max_party_size, span_all, span_typ, typical_vehicles]
			)
		)
		assert_int(max_party_size).is_less_equal(2)
		assert_int(parties.size()).is_greater_equal(4)
		assert_int(span_all).is_greater_equal(800)
		if typical_vehicles.size() >= 3:
			assert_int(span_typ).is_greater_equal(400)
		land.free_all()
	assert_int(checked_gaps).is_greater_equal(5)


func _booking_tuples(seed: int, count: int) -> Array:
	var land := LandsideTestWorld.make(null, FlightSim.schedule_starts(FIRST), seed)
	land.schedule(count)
	var out := []
	for id in land.sim.arrivals.booking_ids():
		var b := land.sim.arrivals.get_booking(id)
		out.append([b.party, b.kind, b.intent, b.arrival, b.variant, b.unload_tick])
	land.free_all()
	return out


func test_arrival_bookings_are_deterministic_for_the_same_seed() -> void:
	for count in [10, 24]:
		assert_array(_booking_tuples(7, count)).is_equal(_booking_tuples(7, count))
		assert_array(_booking_tuples(7, count)).is_not_equal(_booking_tuples(8, count))


func test_charter_arrival_window_stays_wide_and_boards_cleanly() -> void:
	var grid := BuildGrid.new(LandsideTestWorld.SITE.grid_size, LandsideTestWorld.SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, LandsideTestWorld.SITE.starter_offset)).is_true()
	var starts := FlightSim.schedule_starts(FIRST, TaxiTimes.BASE, FlightSim.CHARTER_BOARDING_TICKS)
	var land := LandsideTestWorld.make(null, starts, 11, grid)
	var boarding := land.world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	var doors := land.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var typical_win := ArrivalTypes.window(
		ArrivalTypes.Type.TYPICAL,
		land.world.flights,
		PassengerTestWorld.FLIGHT,
		land.sim.clock.tick
	)
	var rushed_win := ArrivalTypes.window(
		ArrivalTypes.Type.RUSHED, land.world.flights, PassengerTestWorld.FLIGHT, land.sim.clock.tick
	)
	print(
		(
			"charter typical=%s (span=%d) rushed=%s boarding=%d"
			% [typical_win, typical_win.y - typical_win.x + 1, rushed_win, boarding]
		)
	)
	assert_int(typical_win.y - typical_win.x + 1).is_greater_equal(900)
	assert_int(typical_win.y).is_less(boarding)
	assert_int(rushed_win.y - rushed_win.x).is_equal(ArrivalTypes.RUSHED_SPAN_TICKS)
	var count := 8
	var spawned_ticks: Array[int] = []
	land.sim.passenger_spawned.connect(
		func(id: int) -> void: spawned_ticks.append(land.sim.get_passenger(id).spawn_tick)
	)
	land.sim.arrivals.schedule(PassengerTestWorld.FLIGHT, count, ArrivalTypes.CHARTER_SHARES)
	land.run_to(doors + 200)
	assert_int(spawned_ticks.size()).is_equal(count)
	for tick in spawned_ticks:
		assert_int(tick).is_less(boarding)
	assert_int(land.sim.made_count()).is_equal(count)
	assert_int(land.sim.missed_count()).is_equal(0)
	land.free_all()


func test_arrival_type_ordering_and_full_make_rate_on_healthy_terminal() -> void:
	var grid := BuildGrid.new(LandsideTestWorld.SITE.grid_size, LandsideTestWorld.SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, LandsideTestWorld.SITE.starter_offset)).is_true()
	var land := LandsideTestWorld.make(null, FlightSim.schedule_starts(FIRST), 5, grid)
	assert_int(ArrivalTypes.ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS).is_greater_equal(2600)
	assert_int(PassengerSim.LAST_SPAWN_LEAD_TICKS).is_between(1300, 1500)
	var count := 24
	var sum_by_type := {
		ArrivalTypes.Type.RELAXED: 0,
		ArrivalTypes.Type.TYPICAL: 0,
		ArrivalTypes.Type.RUSHED: 0,
	}
	var count_by_type := {
		ArrivalTypes.Type.RELAXED: 0,
		ArrivalTypes.Type.TYPICAL: 0,
		ArrivalTypes.Type.RUSHED: 0,
	}
	land.sim.passenger_spawned.connect(
		func(id: int) -> void:
			var p := land.sim.get_passenger(id)
			sum_by_type[p.arrival_type] += p.spawn_tick
			count_by_type[p.arrival_type] += 1
	)
	land.schedule(count)
	var doors := land.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	land.run_to(doors + 200)
	for t in ArrivalTypes.Type.values():
		assert_int(count_by_type[t]).is_greater(0)
	@warning_ignore("integer_division")
	var mean_relaxed: int = (
		sum_by_type[ArrivalTypes.Type.RELAXED] / count_by_type[ArrivalTypes.Type.RELAXED]
	)
	@warning_ignore("integer_division")
	var mean_typical: int = (
		sum_by_type[ArrivalTypes.Type.TYPICAL] / count_by_type[ArrivalTypes.Type.TYPICAL]
	)
	@warning_ignore("integer_division")
	var mean_rushed: int = (
		sum_by_type[ArrivalTypes.Type.RUSHED] / count_by_type[ArrivalTypes.Type.RUSHED]
	)
	print(
		(
			"means relaxed=%d typical=%d rushed=%d made=%d missed=%d results=%s no_shows=%s road_missed=%s"
			% [
				mean_relaxed,
				mean_typical,
				mean_rushed,
				land.sim.made_count(),
				land.sim.missed_count(),
				land.sim.flight_results,
				land.sim.no_shows,
				land.sim.arrivals.missed_by_flight,
			]
		)
	)
	assert_int(mean_relaxed).is_less(mean_typical)
	assert_int(mean_typical).is_less(mean_rushed)
	assert_int(land.sim.made_count()).is_equal(count)
	assert_int(land.sim.missed_count()).is_equal(0)
	land.free_all()
