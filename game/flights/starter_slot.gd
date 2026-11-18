class_name StarterSlot
extends RefCounted
## When the starter contract departs (decision closed-airport-calendar-design-
## an-explicit-calendar-epoch-pa, point 5, under ruling day-clock-stops-until-
## the-airport-opens-the-opening-call-pau). The calendar starts at the opening,
## so the opening is 06:00 on day 0, and the first passenger party arrives at
## once (FirstParty). The starter departs at the later of two leads after the
## opening, rounded up to a whole calendar minute:
## - the plane's: FlightTimetable.departure_offset() of the taxi pair of the
##   gate it gets, so its first state is no earlier than the opening tick and
##   its first occurrence is issued on the opening tick;
## - the passengers': JOURNEY_TICKS from the opening to the first party at
##   the gate, then the whole boarding window (BOARDING and DOORS_CLOSED, so
##   they are at the gate before boarding starts), plus MARGIN_TICKS.
## When an offer accepted while closed holds that slot, the first later minute
## accept_contract takes is used. AirportGate does not open without a starter.

## The first party's journey on the starter terminal, measured by
## game/spike/starter_journey_probe.gd through the real landside flow
## (2026-11-18): from the opening tick (its car or taxi enters the road) to the
## last member of the party at the gate. At the starter's north gate A
## (TaxiTimes.BASE) it was 943 ticks; at a west wing gate B on side land (pair
## [1220, 920], the farthest walk the probe builds) 1099, the one kept here.
const JOURNEY_TICKS := 1099
## Room for a slower party than the measured one (a queue at the desk or the
## scanner, a car park on the way): ten game minutes.
const MARGIN_TICKS := 200


## The least time from the opening to the departure at a gate with taxi pair
## `taxi`.
static func lead(taxi: Array) -> int:
	return maxi(FlightTimetable.departure_offset(taxi), passenger_lead())


## The passengers' least time from the opening to the departure: 2559 ticks,
## shorter than any plane's lead (2660 at TaxiTimes.BASE).
static func passenger_lead() -> int:
	var phases := FlightSim.PHASE_TICKS
	var boarding: int = phases[FlightSim.State.BOARDING] + phases[FlightSim.State.DOORS_CLOSED]
	return JOURNEY_TICKS + boarding + MARGIN_TICKS


## STARTER_TERMS for an opening now: departing at the first whole calendar
## minute at least lead() after `flights`' tick, for the pair of the gate
## accept_contract would give them, that accept_contract takes. {} when it
## refuses every minute of a day.
static func terms(flights: FlightSim) -> Dictionary:
	var now := flights.tick
	var epoch := flights.epoch
	var earliest := whole_minute(now + lead(TaxiTimes.BASE), epoch)
	for minute in GameCalendar.MINUTES_PER_DAY:
		var departure := earliest + minute * GameCalendar.TICKS_PER_MINUTE
		var offered := departing(departure, epoch)
		var gate := flights.accept_gate(offered)
		if gate != "" and departure - now >= lead(flights.gate_taxi(gate)):
			return offered
	return {}


## STARTER_TERMS departing at the calendar minute of tick `departure`.
static func departing(departure: int, epoch: int) -> Dictionary:
	var offered := FlightSim.STARTER_TERMS.duplicate()
	offered["departure_minute"] = GameCalendar.minute_of_day(departure, epoch)
	return offered


## `tick` rounded up to a whole calendar minute, counted from `epoch`.
static func whole_minute(tick: int, epoch: int) -> int:
	var minutes := -GameCalendar.floor_div(epoch - tick, GameCalendar.TICKS_PER_MINUTE)
	return epoch + minutes * GameCalendar.TICKS_PER_MINUTE
