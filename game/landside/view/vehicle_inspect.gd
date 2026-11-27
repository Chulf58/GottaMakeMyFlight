class_name VehicleInspect
extends RefCounted
## What a selected car or taxi shows (PassengerHud's follow text): what it is
## doing, the passengers aboard, their flight and how late their drop-off is
## so far. The passengers aboard are arrival bookings (ArrivalBookings), not
## Passenger records yet; a party shares one vehicle and one flight. Once
## they got out (or their flight closed) the vehicle shows only what it is
## doing. Display only.


## The follow text of vehicle `v` at tick `now`, in the PassengerHud style:
## parts joined by three spaces.
static func text(
	arrivals: ArrivalBookings, flights: FlightSim, v: LandsideVehicle, now: int
) -> String:
	var parts := PackedStringArray([_name_text(v), doing_text(v)])
	if v.bookings.is_empty():
		return "   ".join(parts)
	var aboard := TranslationServer.translate_plural(
		"{count} passenger", "{count} passengers", v.bookings.size()
	)
	parts.append(aboard.format({"count": v.bookings.size()}))
	var flight_ids := PackedStringArray()
	# The latest of the party's drop-offs, in ticks past each passenger's own unload
	# tick, which already counts the planned stagger (a party gets out one at a time),
	# so a member waiting for its turn is not late.
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
		var flight := TranslationServer.translate("Flight {flights}")
		parts.append(flight.format({"flights": ", ".join(flight_ids)}))
		parts.append(delay_text(late))
	return "   ".join(parts)


## What the vehicle is doing, from its lane, stage and intent; an empty one
## says so.
static func doing_text(v: LandsideVehicle) -> String:
	if v.intent == LandsideVehicle.Intent.PICKUP:
		return _pickup_doing_text(v)
	var empty := v.bookings.is_empty()
	match v.stage:
		LandsideVehicle.Stage.DWELL:
			return _t("Empty, at the curb") if empty else _t("At the curb")
		LandsideVehicle.Stage.PARKED:
			if not v.claimants.is_empty():
				return _t("Parked, driver returning")
			return _t("Parked, driver away") if empty else _t("Parked")
		LandsideVehicle.Stage.LEAVE:
			return _t("Empty, leaving") if empty else _t("Leaving")
	if empty:
		return _t("Empty, driving on")
	if v.lane in [LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT]:
		return _t("Driving into the car park")
	var queued := v.stage == LandsideVehicle.Stage.QUEUE
	if v.intent == LandsideVehicle.Intent.PARK:
		return _t("Waiting to turn into the car park") if queued else _t("Driving to the car park")
	return _t("Queuing for the curb") if queued else _t("Driving to the curb")


static func _pickup_doing_text(v: LandsideVehicle) -> String:
	match v.stage:
		LandsideVehicle.Stage.DWELL:
			return _t("Picking up passenger") if v.pickup_boarded > 0 else _t("At the curb")
		LandsideVehicle.Stage.LEAVE:
			return _t("Leaving with passenger") if v.pickup_boarded > 0 else _t("Empty, leaving")
		LandsideVehicle.Stage.QUEUE:
			return _t("Queuing for curb pickup")
	return _t("Driving to curb pickup")


## The drop-off delay so far, from the ticks past the tick the party meant to
## get out: "On time" before it, never once it has passed.
static func delay_text(late_ticks: int) -> String:
	if late_ticks <= 0:
		return TranslationServer.translate("On time")
	@warning_ignore("integer_division")
	var minutes := late_ticks / GameCalendar.TICKS_PER_MINUTE
	if minutes < 1:
		return TranslationServer.translate("Drop-off delay: under 1 min")
	var delay := TranslationServer.translate_plural(
		"Drop-off delay: {minutes} min", "Drop-off delay: {minutes} min", minutes
	)
	return delay.format({"minutes": minutes})


## "Taxi 7" or "Car 7".
static func _name_text(v: LandsideVehicle) -> String:
	var kind := (
		TranslationServer.translate("Taxi", "vehicle")
		if v.kind == LandsideVehicle.Kind.TAXI
		else TranslationServer.translate("Car", "vehicle")
	)
	return TranslationServer.translate("{vehicle} {id}").format({"vehicle": kind, "id": v.id})


## Static code has no tr(); the literal stays at each call so the POT lists it.
static func _t(msgid: String) -> String:
	return TranslationServer.translate(msgid)
