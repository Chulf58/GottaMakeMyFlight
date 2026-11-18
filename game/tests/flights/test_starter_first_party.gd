class_name TestStarterFirstParty
extends GdUnitTestSuite
## At the opening the first passengers arrive at once and make the starter
## flight (ruling day-clock-stops-until-the-airport-opens-the-opening-call-pau;
## decision closed-airport-calendar-design-an-explicit-calendar-epoch-pa, point
## 5). On the real main scene with the starter terminal (gate A, TaxiTimes.BASE)
## the opening issues the starter's first flight on the opening tick, its first
## party (FirstParty) boards a car or taxi on that tick through the landside
## flow, and every member gets out, reaches the gate and makes the flight. The
## other parties keep their drawn times: none boards a vehicle on that tick.
## AirportGate emits `opened` inside the opening tick. One boot for the file.

const SEED := 18_112_028
const OPEN_LIMIT := 3000
const FLY_LIMIT := 8000

var _main: Node
var _run := {}
## booking id -> "made" or "missed", for the first party.
var _outcomes := {}
var _passengers := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var clock: SimClock = _main.get_node("SimClock")
	var flights: FlightSim = _main.get_node("FlightSim")
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var gate: AirportGate = _main.get_node("AirportGate")
	gate.opened.connect(func(tick: int) -> void: _run["signal"] = [tick, clock.is_in_tick()])
	SaveTestKit.start_airport(_main)
	while flights.opened_tick < 0 and clock.tick < OPEN_LIMIT:
		SaveTestKit.step(_main)
	var opened := flights.opened_tick
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	_run["opened"] = opened
	_run["first_state"] = flights.state_start(first, FlightSim.State.SCHEDULED)
	_run["doors"] = flights.doors_close_tick(first)
	var party := 1 << 30
	for id in sim.arrivals.booking_ids():
		party = mini(party, sim.arrivals.get_booking(id).party)
	var members := []
	var others_aboard := 0
	for id in sim.arrivals.booking_ids():
		var b := sim.arrivals.get_booking(id)
		if b.party == party:
			members.append([id, b.flight_id, b.vehicle != 0])
		elif b.vehicle != 0:
			others_aboard += 1
	_run["members"] = members
	_run["others_aboard"] = others_aboard
	var party_ids := {}
	for row: Array in members:
		party_ids[row[0]] = true
	sim.arrivals.released.connect(
		func(booking: int, passenger: int) -> void:
			if party_ids.has(booking):
				_passengers[passenger] = booking
	)
	sim.outcome.connect(
		func(passenger: int, made: bool) -> void:
			if _passengers.has(passenger):
				_outcomes[_passengers[passenger]] = "made" if made else "missed"
	)
	while _outcomes.size() < members.size() and clock.tick < opened + FLY_LIMIT:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


func test_the_opening_issues_the_starter_on_the_opening_tick() -> void:
	assert_int(_run["opened"]).is_greater(0)
	assert_int(_run["first_state"]).is_greater_equal(_run["opened"])
	assert_int(_run["first_state"]).is_equal(
		(
			_run["opened"]
			+ StarterSlot.lead(TaxiTimes.BASE)
			- FlightTimetable.departure_offset(TaxiTimes.BASE)
		)
	)
	assert_array(_run["signal"]).is_equal([_run["opened"], true])


func test_the_first_party_is_on_the_road_at_the_opening() -> void:
	var members: Array = _run["members"]
	assert_int(members.size()).is_greater(0)
	for row: Array in members:
		assert_str(row[1]).is_equal(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		assert_bool(row[2]).override_failure_message(str(row)).is_true()
	assert_int(_run["others_aboard"]).is_equal(0)


func test_the_first_party_makes_the_starter_flight() -> void:
	var members: Array = _run["members"]
	assert_int(_outcomes.size()).is_equal(members.size())
	for row: Array in members:
		assert_str(_outcomes.get(row[0], "none")).override_failure_message(str(row)).is_equal(
			"made"
		)


func test_all_relaxed_with_first_at_once_keeps_later_parties_off_the_opening_tick() -> void:
	var w := LandsideTestWorld.make(null, FlightSim.schedule_starts(0), 1)
	var shares: Array[int] = [0, 0, 100]
	w.sim.arrivals.schedule(PassengerTestWorld.FLIGHT, 24, shares, true)
	w.sim.arrivals.step()
	var first_party := w.sim.arrivals.get_booking(1).party
	var first_aboard := 0
	var others_aboard := 0
	var earliest_other_start := 1 << 30
	for id in w.sim.arrivals.booking_ids():
		var b := w.sim.arrivals.get_booking(id)
		if b.party == first_party:
			first_aboard += int(b.vehicle != 0)
		else:
			earliest_other_start = mini(
				earliest_other_start, b.unload_tick - w.landside.lead_ticks(b.intent)
			)
			others_aboard += int(b.vehicle != 0)
	w.free_all()
	assert_int(first_aboard).is_greater(0)
	assert_int(earliest_other_start).is_greater(0)
	assert_int(others_aboard).is_equal(0)
