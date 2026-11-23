class_name DepartureList
extends RefCounted
## The rows of one day's departures (Economy 7/8), a pure function of the
## FlightSim: one row per flight leaving that day, earliest first, whose line
## reads "07:38  Oslo  Gotta Air  Boarding". The departures board
## (DeparturesBoard) draws them. The next departing flight (the earliest whose
## doors have not closed) reads "doors close 10:30", the game-clock time its
## doors close, in place of its status word (doors_line; decision
## flight-panel-the-next-departing-flight-s-row-shows-a-doors-c, the clock-time
## wording user-ruled 2026-10-29). A contract shows its destination and airline
## from its recorded start day (FlightSim.start_days), a one-off flight its id.
## While the airport is closed no contract is listed, since nothing is scheduled
## until it opens; a contract accepted then never shows the days it skipped
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening). An ended contract (FlightSim.end_contract) is listed
## only for the days before its end day; the flights it had issued by then
## still fly and show.

## The msgctxt of the status words: short words get one so they stay apart from
## the same English word elsewhere.
const STATUS_CONTEXT := "departure status"


## The earliest row whose doors have not closed at `tick`, or an empty one.
static func next_departing(rows: Array[Dictionary], tick: int) -> Dictionary:
	for row in rows:
		if tick < row["doors"]:
			return row
	return {}


static func doors_line(row: Dictionary, epoch: int) -> String:
	return "%s  %s" % [row["base"], doors_text(row, epoch)]


## "doors close 10:30": the game-clock time the row's doors close.
static func doors_text(row: Dictionary, epoch: int) -> String:
	return TranslationServer.translate("doors close {time}").format(
		{"time": GameCalendar.clock_text(row["doors"], epoch)}
	)


## The flight panel's word for a flight in `state`: "Boarding", then one for each
## state from the doors closing on; "" before boarding.
static func status_word(state: int) -> String:
	match state:
		FlightSim.State.BOARDING:
			return TranslationServer.translate("Boarding", STATUS_CONTEXT)
		FlightSim.State.DOORS_CLOSED:
			return TranslationServer.translate("Doors closed", STATUS_CONTEXT)
		FlightSim.State.PUSHBACK:
			return TranslationServer.translate("Pushback", STATUS_CONTEXT)
		FlightSim.State.TAXI_OUT:
			return TranslationServer.translate("Taxiing", STATUS_CONTEXT)
		FlightSim.State.TAKEOFF:
			return TranslationServer.translate("Taking off", STATUS_CONTEXT)
		FlightSim.State.DEPARTED:
			return TranslationServer.translate("Departed", STATUS_CONTEXT)
	return ""


## The rows for each flight leaving on `day`, earliest first (see _rows); the
## departures board reads today's and tomorrow's.
static func rows_for_day(flights: FlightSim, day: int) -> Array[Dictionary]:
	return _rows(flights, day)


## {tick, doors, head, airline, status, base, line, departed, contract, gate, flight}
## for each flight leaving on `today`, earliest first; `doors` is the tick its
## doors close, `contract` the contract id ("" for a one-off) and `gate` the
## gate the flight holds; `flight` is the flight id its passengers carry (the
## occurrence id for a contract).
static func _rows(flights: FlightSim, today: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var open := flights.opened_tick >= 0
	var start_days := flights.start_days
	for contract_id in flights.contract_ids():
		var contract := flights.contract_of(contract_id)
		if not open or int(start_days[contract_id]) > today:
			continue
		if FlightContract.is_charter(contract) and FlightContract.one_off_day(contract) != today:
			continue
		var end_day := flights.contract_end_day(contract_id)
		if end_day >= 0 and today >= end_day:
			continue
		var tick := GameCalendar.tick_at(today, int(contract["departure_minute"]), flights.epoch)
		var state := flights.state_of(FlightTimetable.occurrence_id(contract_id, today))
		var doors := FlightTimetable.starts_for(contract, today, flights.epoch)[
			FlightSim.State.DOORS_CLOSED
		]
		# An occurrence already issued keeps the gate it was issued at.
		var gate := flights.flight_gate(FlightTimetable.occurrence_id(contract_id, today))
		if gate == "":
			gate = contract["gate"]
		var place_airline := [contract["destination"], contract["airline"]]
		var occurrence := FlightTimetable.occurrence_id(contract_id, today)
		rows.append(
			_row(tick, doors, place_airline, state, contract_id, gate, occurrence, flights.epoch)
		)
	for id in flights.flight_ids():
		if flights.flight_contract_id(id) != "":
			continue
		var tick := flights.state_start(id, FlightSim.State.PUSHBACK)
		if GameCalendar.day_of(tick, flights.epoch) == today:
			var doors := flights.doors_close_tick(id)
			var state := flights.state_of(id)
			var gate := flights.flight_gate(id)
			rows.append(_row(tick, doors, [id, ""], state, "", gate, id, flights.epoch))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])
	return rows


## `place_airline` is [destination or flight id, airline or ""], and `epoch` the
## calendar epoch the times are read at. `head` is the
## time and destination (line 1 of the board row), `airline` the full airline
## name (line 2), `status` the status word; `base` and `line` stay the one-line
## text.
static func _row(
	tick: int,
	doors: int,
	place_airline: Array,
	state: int,
	contract_id: String,
	gate: String,
	flight_id: String,
	epoch: int
) -> Dictionary:
	var place: String = place_airline[0]
	var airline: String = place_airline[1]
	var head := "%s  %s" % [GameCalendar.clock_text(tick, epoch), place]
	var base := head if airline == "" else "%s  %s" % [head, airline]
	var line := base
	var status := status_word(state)
	if status != "":
		line += "  " + status
	return {
		"tick": tick,
		"doors": doors,
		"head": head,
		"airline": airline,
		"status": status,
		"base": base,
		"line": line,
		"departed": state == FlightSim.State.DEPARTED,
		"contract": contract_id,
		"gate": gate,
		"flight": flight_id,
	}


## Scans `passengers` once into {"boarded": {flight: n}, "known": {flight: n}}
## for live Boarded/Booked row telemetry.
static func progress_scan(passengers: PassengerSim) -> Dictionary:
	var boarded := {}
	var known := {}
	if passengers == null:
		return {"boarded": boarded, "known": known}
	for fid: String in passengers.flight_results:
		var res: Dictionary = passengers.flight_results[fid]
		var made := int(res.get("made", 0))
		boarded[fid] = made
		known[fid] = int(known.get(fid, 0)) + made + int(res.get("missed", 0))
	for fid: String in passengers.no_shows:
		var ns: Dictionary = passengers.no_shows[fid]
		known[fid] = int(known.get(fid, 0)) + int(ns.get("no_entrance", 0)) + int(ns.get("late", 0))
	for fid: String in passengers.arrivals.missed_by_flight:
		known[fid] = int(known.get(fid, 0)) + int(passengers.arrivals.missed_by_flight[fid])
	for pid in passengers.passenger_ids():
		var p := passengers.get_passenger(pid)
		if p != null and not p.is_done():
			known[p.flight_id] = int(known.get(p.flight_id, 0)) + 1
	for bid in passengers.arrivals.booking_ids():
		var b := passengers.arrivals.get_booking(bid)
		if b != null:
			known[b.flight_id] = int(known.get(b.flight_id, 0)) + 1
	for entry: Dictionary in passengers._schedule:
		var fid: String = entry.get("flight", "")
		if fid != "":
			known[fid] = int(known.get(fid, 0)) + 1
	return {"boarded": boarded, "known": known}


## Live {"boarded", "booked"} for `flight_id` from `scan` (progress_scan()) and
## its contract terms when unissued.
static func row_progress(
	flights: FlightSim,
	passengers: PassengerSim,
	flight_id: String,
	contract_id: String,
	scan: Dictionary
) -> Dictionary:
	var boarded := int((scan.get("boarded", {}) as Dictionary).get(flight_id, 0))
	var known := int((scan.get("known", {}) as Dictionary).get(flight_id, 0))
	var contract_booked := 0
	if contract_id != "" and flights != null:
		var contract := flights.contract_of(contract_id)
		contract_booked = int(contract.get("booked_passengers", 0))
		if passengers != null:
			contract_booked += passengers.booking_override_of(flight_id)
	return {"boarded": boarded, "booked": maxi(known, contract_booked)}


## "3/6 boarded", or "" when nothing is booked yet.
static func boarded_text(boarded: int, booked: int) -> String:
	if booked <= 0:
		return ""
	return TranslationServer.translate("{boarded}/{booked} boarded").format(
		{"boarded": boarded, "booked": booked}
	)
