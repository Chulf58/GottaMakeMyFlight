class_name TestLandsideRatingMidnight
extends GdUnitTestSuite
## A passenger still on the road when the doors close counts as missed in the
## airport rating on that tick. When that tick is a day's first and another
## flight closed on the day before's last tick, the earlier flight's no-shows
## are recorded first, so the day that ends is judged with them: the rating
## ends the same as one that took the tick (on_tick) before the miss.

const FLIGHT := "F1"
const NO_SHOWS := 10


func _rating(clock: SimClock, flights: FlightSim, sim: PassengerSim) -> AirportRating:
	var rating: AirportRating = auto_free(AirportRating.new())
	rating.bind(clock, flights, sim)
	return rating


func test_a_miss_on_a_days_first_tick_follows_the_last_days_no_shows() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	var flights: FlightSim = auto_free(FlightSim.new())
	var sim: PassengerSim = auto_free(PassengerSim.new())
	var last_tick := GameCalendar.day_start(1) - 1
	var midnight := GameCalendar.day_start(1)
	var by_signal := _rating(clock, flights, sim)
	var by_tick := _rating(clock, flights, sim)
	for rating in [by_signal, by_tick]:
		rating.record_passenger(last_tick - 100, true, 0)
		rating.note_doors_closed(FLIGHT, last_tick)
	sim.no_shows[FLIGHT] = {"no_entrance": NO_SHOWS, "late": 0}
	sim.tick = midnight
	# The signal reaches both ratings; the control took the tick first.
	by_tick.on_tick(midnight)
	sim.arrivals.missed.emit(FLIGHT)
	print(
		(
			"by signal %s low %d; by tick %s low %d"
			% [
				by_signal.day_totals(0),
				by_signal.low_days(),
				by_tick.day_totals(0),
				by_tick.low_days()
			]
		)
	)
	assert_int(by_signal.day_totals(0)["missed"]).is_equal(NO_SHOWS)
	assert_int(by_signal.day_totals(1)["missed"]).is_equal(1)
	assert_int(by_signal.low_days()).is_equal(1)
	assert_dict(by_signal.to_snapshot()).is_equal(by_tick.to_snapshot())
