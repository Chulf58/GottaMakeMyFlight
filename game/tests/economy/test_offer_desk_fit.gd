class_name TestOfferDeskFit
extends GdUnitTestSuite
## OfferDesk fits each new day's offers to the flights as midnight leaves them
## (decision airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more, point
## 4): a contract the low rating ends at that day boundary is gone before the
## day's offers are fitted, so its freed time can be offered at once.

var _clock: SimClock
var _rating: AirportRating
var _flights: FlightSim
var _desk: OfferDesk


func before_test() -> void:
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.seed_rng(2024)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_desk = auto_free(OfferDesk.new()) as OfferDesk
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.rating = _rating
	_desk.flights = _flights
	_desk.bind_clock(_clock)


## As TestOfferDeskContractEnd does it: the rating saw only misses the day
## before, then the rating ticks, then the desk.
func _low_day_end(day: int) -> void:
	_rating.record_passenger(GameCalendar.day_start(day - 1), false, 0)
	var tick := GameCalendar.day_start(day)
	_clock.tick = tick
	_rating.on_tick(tick)
	_clock.ticked.emit(tick)


func _fitting_offers() -> int:
	var count := 0
	for offer in _desk.board.open_offers():
		count += 1 if FlightFit.fits(_flights, OfferBoard.terms_of(offer)) else 0
	return count


func test_a_contract_ended_at_midnight_frees_its_time_for_that_days_offers() -> void:
	for minute: int in TestOfferBoardFit.FULL_DAY:
		assert_bool(_flights.accept_contract(TestFlightFit.terms("F%d" % minute, minute))).is_true()
	for day in range(1, RatingFormula.LOW_DAYS_TO_END):
		_low_day_end(day)
		# Control: while the gate is full no offer fits.
		assert_int(_fitting_offers()).is_equal(0)
	_low_day_end(RatingFormula.LOW_DAYS_TO_END)
	assert_array(_flights.active_contract_ids()).not_contains(["F420"])
	var minutes := []
	for offer in _desk.board.open_offers():
		minutes.append(offer["departure_minute"])
	print("after F420 ended, day offers depart at %s" % [minutes])
	assert_int(_fitting_offers()).is_greater(0)
	assert_bool(minutes.has(420)).is_true()
