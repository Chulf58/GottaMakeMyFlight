class_name FirstParty
extends RefCounted
## The first passengers of a new airport (decision closed-airport-calendar-
## design-an-explicit-calendar-epoch-pa, point 5, under ruling day-clock-stops-
## until-the-airport-opens-the-opening-call-pau): the starter's occurrence that
## the opening issues gets one party that arrives at once, through the real
## landside flow, instead of at a drawn time. Its car or taxi enters the road on
## the opening tick and drops it at the curb on time on a free road
## (ArrivalBookings.schedule); with no landside, its first passenger appears at
## the entrance on the next tick. StarterSlot times the starter for this party.


## Whether `flight_id`, being scheduled now, is the starter occurrence the
## airport opened with: scheduled on the opening tick, of the starter contract.
static func due(sim: PassengerSim, flight_id: String) -> bool:
	if sim.flights.opened_tick < 0 or sim.flights.opened_tick != sim.clock.tick:
		return false
	return FlightTimetable.parse_occurrence(flight_id).get("contract", "") == FlightSim.DEFAULT_ID
