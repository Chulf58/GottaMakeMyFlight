class_name ArrivalTypes
extends RefCounted
## When a scheduled passenger arrives (decision
## passengers-get-an-arrival-type-rushed-typical-or-relaxed). Each one draws a
## type from the sim RNG: typical passengers arrive in the flight's usual
## window, from just after the arrival opening (ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS
## before departure, the first state until the plane's taxi-in was lengthened) to
## PassengerSim.LAST_SPAWN_LEAD_TICKS before its doors close; rushed ones in
## the last RUSHED_SPAN_TICKS of that window; relaxed ones before the first
## opening, from RELAXED_LEAD_TICKS before departure (the start of PUSHBACK).
## The flight timeline is not touched: FlightTimetable issues an occurrence
## ISSUE_LEAD_TICKS before its first state, earlier than any relaxed arrival.

enum Type { RUSHED, TYPICAL, RELAXED }

const NAMES: Array[String] = ["rushed", "typical", "relaxed"]
## Whole percent of scheduled passengers per type, in Type order. A tuning
## placeholder near the survey in the ruling (about a third of travellers
## arrive two hours early).
const SHARES: Array[int] = [15, 55, 30]
## One-off same-day charters never draw RELAXED arrivals (who arrive 3h ahead),
## keeping all bookings within the compact charter turnaround window.
const CHARTER_SHARES: Array[int] = [15, 85, 0]
## Three game hours (user-ruled): the earliest relaxed arrival is this long
## before departure, 1340 ticks before the first state.
const RELAXED_LEAD_TICKS := 3600
## Passenger timing is set against departure, not the plane's arrival (decision
## plane-stand-design-airside-moves-110-m-north-stand-snaps-to: a longer
## TAXI_IN only brings the plane earlier). The usual window opens this long
## before departure, as it did when the first state was 1960 ticks before it.
const ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS := 1960
## Rushed passengers arrive in the last 15 game minutes of the usual window.
const RUSHED_SPAN_TICKS := 300


## One type drawn with `shares` (whole percent per type, Type order, summing to
## 100: SHARES or shares_for()). One RNG draw whatever the shares.
static func draw(rng: RandomNumberGenerator, shares: Array[int] = SHARES) -> Type:
	var roll := rng.randi_range(0, 99)
	for type in Type.values():
		roll -= shares[type]
		if roll < 0:
			return type
	return Type.TYPICAL


## The shares of a flight whose contract has `traits` (OfferTraits): Shoppers
## sets the relaxed share, Rush crowd the rushed share, and the typical share
## takes the rest. CHARTER_SHARES (0% RELAXED) for one-off charters; SHARES for
## a plain contract or a one-off flight ({}).
static func shares_for(traits: Dictionary, charter := false) -> Array[int]:
	if charter:
		return CHARTER_SHARES.duplicate()
	var shares: Array[int] = SHARES.duplicate()
	var relaxed := OfferTraits.value(traits, OfferTraits.SHOPPERS)
	if relaxed >= 0:
		shares[Type.RELAXED] = relaxed
	var rushed := OfferTraits.value(traits, OfferTraits.RUSH_CROWD)
	if rushed >= 0:
		shares[Type.RUSHED] = rushed
	shares[Type.TYPICAL] = 100 - shares[Type.RUSHED] - shares[Type.RELAXED]
	return shares


## [first, last] spawn ticks for `type` on flight `flight_id`, never before
## `now + 1`. A type whose window is already behind the clock (a flight
## added, or a contract accepted, shortly before its first state) uses what
## is left of the typical window instead.
static func window(type: Type, flights: FlightSim, flight_id: String, now: int) -> Vector2i:
	var first_state := flights.state_start(flight_id, FlightSim.State.SCHEDULED)
	var last := flights.doors_close_tick(flight_id) - PassengerSim.LAST_SPAWN_LEAD_TICKS
	var departure := flights.state_start(flight_id, FlightSim.State.PUSHBACK)
	var opens := maxi(first_state, departure - ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS)
	var span := Vector2i(opens + 1, last)
	if type == Type.RUSHED:
		span.x = maxi(span.x, last - RUSHED_SPAN_TICKS)
	elif type == Type.RELAXED:
		span = Vector2i(departure - RELAXED_LEAD_TICKS, opens)
	span.x = maxi(span.x, now + 1)
	if span.x > span.y and type != Type.TYPICAL:
		return window(Type.TYPICAL, flights, flight_id, now)
	span.y = maxi(span.x, span.y)
	return span
