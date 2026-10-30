class_name TestLandsideStaggeredClose
extends GdUnitTestSuite
## The stagger of a party's unloading (LandsideSim.RELEASE_GAP_TICKS) is part of
## the plan and never costs a flight: each member has its own expected tick
## (the party's, plus the gap for each member before it), a party boards one
## vehicle, its window leaves room for the whole stagger, and a party that
## reaches its stop so late that the stagger would run to the doors-close tick
## gets out at once, as before the stagger. VehicleInspect measures each
## passenger against that passenger's own tick.

const SEED := 8
const BOOKED := 40

var _land: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _land != null:
		_land.free_all()
	_land = null


func _world() -> LandsideTestWorld:
	var world := LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], SEED)
	assert_bool(world.landside.build_lot(0)).is_true()
	return world


func _parties(world: LandsideTestWorld) -> Dictionary:
	var out := {}
	for id in world.sim.arrivals.booking_ids():
		var party := world.sim.arrivals.get_booking(id).party
		if not out.has(party):
			out[party] = []
		(out[party] as Array).append(id)
	return out


func test_each_member_has_its_own_tick_and_the_whole_stagger_fits_the_window() -> void:
	_land = _world()
	_land.schedule(BOOKED)
	var last_ok := (
		_land.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
		- PassengerSim.LAST_SPAWN_LEAD_TICKS
	)
	var multi := 0
	for party in _parties(_land):
		var ids: Array = _parties(_land)[party]
		multi += int(ids.size() > 1)
		var first := _land.sim.arrivals.get_booking(ids[0]).unload_tick
		for i in ids.size():
			var b := _land.sim.arrivals.get_booking(ids[i])
			assert_int(b.unload_tick).is_equal(first + i * LandsideSim.RELEASE_GAP_TICKS)
			assert_int(b.unload_tick).is_less_equal(last_ok)
	print("%d of %d parties have more than one member" % [multi, _parties(_land).size()])
	assert_int(multi).is_greater(0)


func test_a_party_boards_one_vehicle_together() -> void:
	_land = _world()
	_land.schedule(BOOKED)
	var parties := _parties(_land)
	var boarded := 0
	while _land.sim.tick < 4500:
		_land.step()
		for party in parties:
			var states := {}
			var vehicles := {}
			for id in parties[party]:
				var b := _land.sim.arrivals.get_booking(id)
				if b != null:
					states[b.state] = true
					vehicles[b.vehicle] = true
			# Present members share a state and a vehicle: none boards alone.
			assert_int(states.size()).is_less_equal(1)
			assert_int(vehicles.size()).is_less_equal(1)
			boarded += int(states.has(ArrivalBooking.State.IN_VEHICLE))
	assert_int(boarded).is_greater(0)


## One vehicle of `size` passengers entering on tick 100, with every booking's
## doors-close tick `close_after` ticks after the tick the first gets out
## (found by an unconstrained run of the same vehicle); {tick: [bookings]}. With
## `listed` false the map names other bookings, not these.
func _events(size: int, close_after: int, listed := true) -> Dictionary:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(LandsideTestWorld.STARTER)).is_true()
	sim.wallet = Wallet.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var aboard: Array[int] = []
	for i in size:
		aboard.append(i + 1)
	sim.step(100, true, rng)
	var first_out := 100 + sim.lead_ticks(LandsideVehicle.Intent.DROP)
	sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, aboard)
	var closes := {}
	for id in aboard:
		closes[id if listed else id + 90] = first_out + close_after
	var out := {}
	for t in range(101, 400):
		for event in sim.step(t, true, rng, closes):
			out[t] = event["bookings"]
	return out


func test_a_party_whose_stagger_would_run_to_doors_close_gets_out_at_once() -> void:
	var gap := LandsideSim.RELEASE_GAP_TICKS
	var cases := {
		"room for the whole stagger": [3, 2 * gap + 1, 3],
		"last member on the closing tick": [3, 2 * gap, 1],
		"closing right after the first": [2, 1, 1],
	}
	for case_name in cases:
		var spec: Array = cases[case_name]
		var out := _events(spec[0], spec[1])
		print("%s: %s" % [case_name, out])
		assert_int(out.size()).override_failure_message(case_name).is_equal(spec[2])
		var total := 0
		for t in out:
			total += (out[t] as Array).size()
		assert_int(total).override_failure_message(case_name).is_equal(spec[0])


func test_a_booking_missing_from_the_deadlines_gets_its_party_out_at_once() -> void:
	# Nothing says when its flight closes: an error, and the safe side (no stagger).
	var out := _events(3, 1000, false)
	print("deadlines name other bookings: %s" % [out])
	assert_int(out.size()).is_equal(1)
	assert_array(out.values()[0]).is_equal([1, 2, 3])
	# Control: with the deadlines named and far off, the stagger runs.
	var free := _events(3, 1000)
	assert_int(free.size()).is_equal(3)


func test_a_party_reaching_its_stop_just_before_doors_close_all_gets_out_in_time() -> void:
	_land = _world()
	_land.schedule(BOOKED)
	var close := _land.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var chosen: Array = []
	for party in _parties(_land):
		var ids: Array = _parties(_land)[party]
		if ids.size() >= 2 and chosen.is_empty():
			chosen = ids
	assert_bool(chosen.size() >= 2).is_true()
	# It means to get out one tick before the doors close, the others earlier.
	for id in _land.sim.arrivals.booking_ids():
		var b := _land.sim.arrivals.get_booking(id)
		if chosen.has(id):
			b.unload_tick = close - 1 + chosen.find(id) * LandsideSim.RELEASE_GAP_TICKS
		else:
			b.unload_tick = mini(b.unload_tick, close - 2000)
	while _land.sim.tick < close + 4:
		_land.step()
	var ticks: Array = chosen.map(func(id: int) -> int: return _land.released.get(id, -1))
	var missed: int = _land.sim.arrivals.missed_by_flight.get(PassengerTestWorld.FLIGHT, 0)
	print(
		(
			"doors close %d, party %s got out at %s, transport misses %d"
			% [close, chosen, ticks, missed]
		)
	)
	for t in ticks:
		assert_int(t).is_between(0, close - 1)
	assert_int(missed).is_equal(0)


func test_a_member_waiting_for_its_turn_is_not_reported_late() -> void:
	_land = _world()
	_land.schedule(BOOKED)
	var checked := 0
	while _land.sim.tick < 4500 and checked == 0:
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if v.release_wait == 0 or v.bookings.is_empty():
				continue
			var unload := _land.sim.arrivals.get_booking(v.bookings[0]).unload_tick
			if unload < _land.sim.tick:
				continue
			var text := VehicleInspect.text(
				_land.sim.arrivals, _land.world.flights, v, _land.sim.tick
			)
			print("tick %d, next member's tick %d: %s" % [_land.sim.tick, unload, text])
			assert_str(text).ends_with("On time")
			checked += 1
	assert_int(checked).is_greater(0)
