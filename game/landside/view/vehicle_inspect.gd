class_name VehicleInspect
extends RefCounted
## What a selected car or taxi shows (PassengerHud's follow text): what it is
## doing, the passengers aboard, their flight and how late their drop-off is
## so far. The passengers aboard are arrival bookings (ArrivalBookings), not
## Passenger records yet; a party shares one vehicle and one flight. Once
## they got out (or their flight closed) the vehicle shows only what it is
## doing. Display only.

const KIND_TEXT := {LandsideVehicle.Kind.TAXI: "Taxi", LandsideVehicle.Kind.CAR: "Car"}


## The follow text of vehicle `v` at tick `now`, in the PassengerHud style:
## parts joined by three spaces.
static func text(
	arrivals: ArrivalBookings, flights: FlightSim, v: LandsideVehicle, now: int
) -> String:
	var parts := PackedStringArray(["%s %d" % [KIND_TEXT[v.kind], v.id], doing_text(v)])
	if v.bookings.is_empty():
		return "   ".join(parts)
	parts.append("1 passenger" if v.bookings.size() == 1 else "%d passengers" % v.bookings.size())
	var flight_ids := PackedStringArray()
	# The latest of the party's drop-offs, in ticks past its unload tick.
	var late := 0
	var first := true
	for id in v.bookings:
		var b := arrivals.get_booking(id)
		if b == null:
			continue
		var title := FlightResultPanel.title_for(flights, b.flight_id)
		if not flight_ids.has(title):
			flight_ids.append(title)
		late = now - b.unload_tick if first else maxi(late, now - b.unload_tick)
		first = false
	if not flight_ids.is_empty():
		parts.append("Flight %s" % ", ".join(flight_ids))
		parts.append(delay_text(late))
	return "   ".join(parts)


## What the vehicle is doing, from its lane, stage and intent; an empty one
## says so.
static func doing_text(v: LandsideVehicle) -> String:
	var empty := v.bookings.is_empty()
	match v.stage:
		LandsideVehicle.Stage.DWELL:
			return "Empty, at the curb" if empty else "At the curb"
		LandsideVehicle.Stage.PARKED:
			return "Parked, driver away" if empty else "Parked"
		LandsideVehicle.Stage.LEAVE:
			return "Empty, leaving" if empty else "Leaving"
	if empty:
		return "Empty, driving on"
	if v.lane in [LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT]:
		return "Driving into the car park"
	var queued := v.stage == LandsideVehicle.Stage.QUEUE
	if v.intent == LandsideVehicle.Intent.PARK:
		return "Waiting to turn into the car park" if queued else "Driving to the car park"
	return "Queuing for the curb" if queued else "Driving to the curb"


## The drop-off delay so far, from the ticks past the tick the party meant to
## get out: "On time" before it, never once it has passed.
static func delay_text(late_ticks: int) -> String:
	if late_ticks <= 0:
		return "On time"
	@warning_ignore("integer_division")
	var minutes := late_ticks / GameCalendar.TICKS_PER_MINUTE
	if minutes < 1:
		return "Drop-off delay: under 1 min"
	return "Drop-off delay: %d min" % minutes
