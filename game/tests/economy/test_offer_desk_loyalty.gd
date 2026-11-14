class_name TestOfferDeskLoyalty
extends GdUnitTestSuite
## OfferDesk counts Loyal airline days on its board from the flights' own
## departures: each day on which a contract with the Loyal trait had a flight
## depart counts once for that contract's airline.

const LOYAL := {"up": "loyal_airline", "down": "rush_crowd", "level": 1}

var _clock: SimClock
var _flights: FlightSim
var _desk: OfferDesk
var _departed: Array[String] = []


func before_test() -> void:
	_departed.clear()
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.seed_rng(2024)
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_flights.state_changed.connect(
		func(id: String, state: int) -> void:
			if state == FlightSim.State.DEPARTED:
				_departed.append(id)
	)
	_desk = auto_free(OfferDesk.new()) as OfferDesk
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.flights = _flights
	_desk.bind_clock(_clock)


func _accept(id: String, minute: int, airline: String, traits: Dictionary) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["airline"] = airline
	terms["traits"] = traits
	assert_bool(_flights.accept_contract(terms)).is_true()


## Runs the flights to the departure of contract `id`'s flight on its `nth`
## day (0 for its first_day), and checks the flight really departed then.
func _fly(id: String, nth: int) -> void:
	var contract := _flights.contract_of(id)
	var day: int = contract["first_day"] + nth
	var departs: int = FlightTimetable.starts_for(contract, day)[FlightSim.State.DEPARTED]
	# Half-hour steps: each tick issues, advances and prunes as the clock would.
	var at := _flights.tick
	while at < departs:
		at = mini(at + GameCalendar.TICKS_PER_MINUTE * 30, departs)
		_flights.on_tick(at)
	assert_str(_departed.back()).is_equal(FlightTimetable.occurrence_id(id, day))


func test_each_day_a_loyal_contract_departs_counts_once_for_its_airline() -> void:
	_accept("LA", 420, "Sunhop", LOYAL)
	_accept("PL", 720, "Blue Fjord", {})
	_accept("LB", 1020, "Sunhop", LOYAL)
	# LB leaves last each day, so flying it runs LA's and PL's flights of the day.
	for nth in 3:
		_fly("LB", nth)
	var first: int = _flights.contract_of("LB")["first_day"]
	for day in range(first + 1, first + 3):
		for id in ["LA", "PL"]:
			assert_bool(_departed.has(FlightTimetable.occurrence_id(id, day))).is_true()
	assert_int(_desk.board.loyal_days("Sunhop")).is_equal(3)
	assert_int(_desk.board.loyal_days("Blue Fjord")).is_equal(0)


func test_five_flown_days_make_the_airline_loyal() -> void:
	_accept("LA", 600, "Sunhop", LOYAL)
	for nth in OfferTraits.LOYAL_DAYS:
		assert_bool(_desk.board.is_loyal("Sunhop")).is_false()
		_fly("LA", nth)
	assert_bool(_desk.board.is_loyal("Sunhop")).is_true()


func test_binding_the_clock_again_still_counts_each_departure_once() -> void:
	_desk.bind_clock(auto_free(SimClock.new()) as SimClock)
	_desk.bind_clock(_clock)
	_accept("LA", 600, "Sunhop", LOYAL)
	_fly("LA", 0)
	_fly("LA", 1)
	assert_int(_desk.board.loyal_days("Sunhop")).is_equal(2)
