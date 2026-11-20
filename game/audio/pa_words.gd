class_name PaWords
extends RefCounted
## Dry, deadpan PA announcement builders for GameAudio / PaTicker.
## Every line goes through TranslationServer.translate(..., "pa") with named
## placeholders so all non-proper nouns translate cleanly.

const CONTEXT := "pa"


## Announcement when a flight opens boarding.
static func boarding(flights: FlightSim, flight_id: String) -> String:
	var info := _flight_parts(flights, flight_id)
	var airline: String = info["airline"]
	var city: String = info["city"]
	var gate: String = info["gate"]
	if airline != "" and city != "":
		if gate != "":
			return (
				TranslationServer
				. translate("PA: Boarding now for {airline} to {city} at Gate {gate}.", CONTEXT)
				. format({"airline": airline, "city": city, "gate": gate})
			)
		return (
			TranslationServer
			. translate("PA: Boarding now for {airline} to {city}.", CONTEXT)
			. format({"airline": airline, "city": city})
		)
	if gate != "":
		return (
			TranslationServer
			. translate("PA: Boarding now for {flight} at Gate {gate}.", CONTEXT)
			. format({"flight": flight_id, "gate": gate})
		)
	return TranslationServer.translate("PA: Boarding now for {flight}.", CONTEXT).format(
		{"flight": flight_id}
	)


## Announcement when a boarding flight nears doors-close.
static func final_call(flights: FlightSim, flight_id: String) -> String:
	var info := _flight_parts(flights, flight_id)
	var airline: String = info["airline"]
	var city: String = info["city"]
	var gate: String = info["gate"]
	if airline != "" and city != "":
		if gate != "":
			return (
				TranslationServer
				. translate(
					"PA: Final call for {airline} to {city} at Gate {gate}. Doors close soon.",
					CONTEXT
				)
				. format({"airline": airline, "city": city, "gate": gate})
			)
		return (
			TranslationServer
			. translate("PA: Final call for {airline} to {city}. Doors close soon.", CONTEXT)
			. format({"airline": airline, "city": city})
		)
	if gate != "":
		return (
			TranslationServer
			. translate("PA: Final call for {flight} at Gate {gate}. Doors close soon.", CONTEXT)
			. format({"flight": flight_id, "gate": gate})
		)
	return (
		TranslationServer
		. translate("PA: Final call for {flight}. Doors close soon.", CONTEXT)
		. format({"flight": flight_id})
	)


## Announcement when a coffee spill incident starts.
static func spill() -> String:
	return TranslationServer.translate(
		"PA: A minor beverage incident in the terminal. Please step around the enthusiasm.", CONTEXT
	)


## Announcement when a security scanner fault starts.
static func fault() -> String:
	return TranslationServer.translate(
		"PA: One security scanner has paused for a brief reset. Other lanes remain open.", CONTEXT
	)


## Announcement when a seasonal rush major incident is presented.
static func rush() -> String:
	return TranslationServer.translate(
		"PA: A seasonal rush is arriving. Everyone is early except the queue.", CONTEXT
	)


## Announcement when the check-in queue alert rises.
static func queue_checkin() -> String:
	return TranslationServer.translate(
		"PA: Check-in queue is full. Please admire the terminal flooring while waiting.", CONTEXT
	)


## Announcement when the security queue alert rises.
static func queue_security() -> String:
	return TranslationServer.translate(
		"PA: Security queue is full. Take a moment to pre-untie your shoes.", CONTEXT
	)


## Announcement when a passenger catches a flight at the last second.
static func close_call(flights: FlightSim, flight_id: String) -> String:
	var label := ""
	if flights != null:
		label = FlightLabel.words(FlightLabel.label_args(flights, true, flight_id))
	if label == "":
		label = flight_id
	return (
		TranslationServer
		. translate(
			"PA: Bravo to the passenger who caught {flight} with seconds to spare.", CONTEXT
		)
		. format({"flight": label})
	)


## Announcement when the terminal rating crosses a star milestone upward.
static func star_milestone(stars_text: String) -> String:
	return (
		TranslationServer
		. translate(
			"PA: Our terminal is now rated {stars} stars. Same carpet, slightly prouder management.",
			CONTEXT
		)
		. format({"stars": stars_text})
	)


## All English msgids in the "pa" context, for POT completeness checks.
static func msgids() -> PackedStringArray:
	return PackedStringArray(
		[
			"PA: Boarding now for {airline} to {city} at Gate {gate}.",
			"PA: Boarding now for {airline} to {city}.",
			"PA: Boarding now for {flight} at Gate {gate}.",
			"PA: Boarding now for {flight}.",
			"PA: Final call for {airline} to {city} at Gate {gate}. Doors close soon.",
			"PA: Final call for {airline} to {city}. Doors close soon.",
			"PA: Final call for {flight} at Gate {gate}. Doors close soon.",
			"PA: Final call for {flight}. Doors close soon.",
			"PA: A minor beverage incident in the terminal. Please step around the enthusiasm.",
			"PA: One security scanner has paused for a brief reset. Other lanes remain open.",
			"PA: A seasonal rush is arriving. Everyone is early except the queue.",
			"PA: Check-in queue is full. Please admire the terminal flooring while waiting.",
			"PA: Security queue is full. Take a moment to pre-untie your shoes.",
			"PA: Bravo to the passenger who caught {flight} with seconds to spare.",
			"PA: Our terminal is now rated {stars} stars. Same carpet, slightly prouder management.",
		]
	)


static func _flight_parts(flights: FlightSim, flight_id: String) -> Dictionary:
	var airline := ""
	var city := ""
	var gate := ""
	if flights != null:
		var parts := FlightLabel.parts(flights, true, flight_id)
		if parts.size() >= 3:
			city = parts[1]
			airline = parts[2]
		gate = flights.flight_gate(flight_id)
	return {"airline": airline, "city": city, "gate": gate}
