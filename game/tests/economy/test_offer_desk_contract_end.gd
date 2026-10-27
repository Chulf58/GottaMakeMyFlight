class_name TestOfferDeskContractEnd
extends GdUnitTestSuite
## OfferDesk ends one airline contract at the day end when the rating's low
## days have run out (decision low-rating-ends-one-airline-contract-per-low-
## day): the oldest contract still running goes first, the rating's count
## starts again, and the desk announces who left.

var _clock: SimClock
var _rating: AirportRating
var _flights: FlightSim
var _desk: OfferDesk
var _left: Array[Dictionary] = []


func before_test() -> void:
	_left.clear()
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.seed_rng(2024)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_desk = auto_free(OfferDesk.new()) as OfferDesk
	_desk.rating = _rating
	_desk.flights = _flights
	_desk.contract_ended.connect(func(contract: Dictionary) -> void: _left.append(contract))
	_desk.bind_clock(_clock)


func _accept(id: String, minute: int, airline := "Gotta Air") -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["airline"] = airline
	assert_bool(_flights.accept_contract(terms)).is_true()


## Moves to the start of `day` as the scene does (rating first, then the desk)
## after the rating has seen only misses on the day before.
func _low_day_end(day: int) -> void:
	_rating.record_passenger(GameCalendar.day_start(day - 1), false, 0)
	var tick := GameCalendar.day_start(day)
	_clock.tick = tick
	_rating.on_tick(tick)
	_clock.ticked.emit(tick)


func _ids_left() -> Array:
	return _left.map(func(contract: Dictionary) -> String: return contract["id"])


func test_the_oldest_running_contract_ends_when_the_low_days_run_out() -> void:
	_accept("AM", 480, "Nordic Wing")
	_accept("PM", 840, "Sunhop")
	_accept("LATE", 1200, "Blue Fjord")
	for day in range(1, RatingFormula.LOW_DAYS_TO_END):
		_low_day_end(day)
		assert_array(_left).is_empty()
	_low_day_end(RatingFormula.LOW_DAYS_TO_END)
	assert_array(_ids_left()).is_equal(["AM"])
	assert_str(_left[0]["airline"]).is_equal("Nordic Wing")
	assert_array(_flights.active_contract_ids()).is_equal(["PM", "LATE"])
	assert_int(_rating.low_days()).is_equal(RatingFormula.LOW_DAYS_AFTER_END)


func test_the_next_oldest_goes_after_the_count_runs_out_again() -> void:
	_accept("AM", 480)
	_accept("PM", 840)
	var day := 1
	for ended in 2:
		for i in RatingFormula.LOW_DAYS_TO_END - (RatingFormula.LOW_DAYS_AFTER_END if ended else 0):
			_low_day_end(day)
			day += 1
	assert_array(_ids_left()).is_equal(["AM", "PM"])
	assert_array(_flights.active_contract_ids()).is_empty()


func test_a_day_without_a_due_end_ends_nothing() -> void:
	_accept("AM", 480)
	_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for day in range(1, 6):
		var tick := GameCalendar.day_start(day)
		_clock.tick = tick
		_rating.on_tick(tick)
		_clock.ticked.emit(tick)
	assert_array(_left).is_empty()
	assert_array(_flights.active_contract_ids()).is_equal(["AM"])


func test_ticks_inside_a_day_end_nothing_more() -> void:
	_accept("AM", 480)
	_accept("PM", 840)
	for day in range(1, RatingFormula.LOW_DAYS_TO_END + 1):
		_low_day_end(day)
	var end_tick := GameCalendar.day_start(RatingFormula.LOW_DAYS_TO_END)
	for tick in [end_tick + 1, end_tick + 500]:
		_clock.tick = tick
		_rating.on_tick(tick)
		_clock.ticked.emit(tick)
	assert_array(_ids_left()).is_equal(["AM"])


func test_with_no_contract_running_the_count_is_used_up_and_nothing_is_announced() -> void:
	for day in range(1, RatingFormula.LOW_DAYS_TO_END + 1):
		_low_day_end(day)
	assert_array(_left).is_empty()
	assert_int(_rating.low_days()).is_equal(RatingFormula.LOW_DAYS_AFTER_END)


func test_a_desk_without_flights_leaves_the_rating_alone() -> void:
	_desk.flights = null
	for day in range(1, RatingFormula.LOW_DAYS_TO_END + 1):
		_low_day_end(day)
	assert_array(_left).is_empty()
	assert_bool(_rating.contract_ends()).is_true()


func test_the_end_survives_a_save_and_load_of_the_flights() -> void:
	_accept("AM", 480)
	_accept("PM", 840)
	for day in range(1, RatingFormula.LOW_DAYS_TO_END + 1):
		_low_day_end(day)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_flights.to_snapshot()))
	var loaded := auto_free(FlightSim.new()) as FlightSim
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_array(loaded.active_contract_ids()).is_equal(["PM"])


## A day end after which the rating has recovered: plenty of made passengers
## outweigh the misses still in the window.
func _recovery_day_end(day: int) -> void:
	for i in 200:
		_rating.record_passenger(GameCalendar.day_start(day - 1), true, PassengerSim.MOOD_MAX)
	var tick := GameCalendar.day_start(day)
	_clock.tick = tick
	_rating.on_tick(tick)
	_clock.ticked.emit(tick)


func test_after_the_first_ending_each_further_low_day_ends_one_more() -> void:
	for id in ["A", "B", "C", "D"]:
		_accept(id, 480 + 240 * "ABCD".find(id))
	for day in range(1, RatingFormula.LOW_DAYS_TO_END):
		_low_day_end(day)
	assert_array(_left).is_empty()
	var first_end := RatingFormula.LOW_DAYS_TO_END
	_low_day_end(first_end)
	assert_array(_ids_left()).is_equal(["A"])
	_low_day_end(first_end + 1)
	assert_array(_ids_left()).is_equal(["A", "B"])
	_low_day_end(first_end + 2)
	assert_array(_ids_left()).is_equal(["A", "B", "C"])
	assert_array(_flights.active_contract_ids()).is_equal(["D"])


func test_a_recovery_day_stops_the_run_and_the_warning_starts_over() -> void:
	for id in ["A", "B", "C", "D"]:
		_accept(id, 480 + 240 * "ABCD".find(id))
	var first_end := RatingFormula.LOW_DAYS_TO_END
	for day in range(1, first_end + 2):
		_low_day_end(day)
	assert_array(_ids_left()).is_equal(["A", "B"])
	_recovery_day_end(first_end + 2)
	assert_bool(_rating.warning()).is_false()
	assert_int(_rating.low_days()).is_equal(0)
	assert_array(_ids_left()).is_equal(["A", "B"])
	_low_day_end(first_end + 3)
	assert_array(_ids_left()).is_equal(["A", "B"])
	assert_array(_flights.active_contract_ids()).is_equal(["C", "D"])
