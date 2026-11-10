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


## The earliest row whose doors have not closed at `tick`, or an empty one.
static func next_departing(rows: Array[Dictionary], tick: int) -> Dictionary:
	for row in rows:
		if tick < row["doors"]:
			return row
	return {}


static func doors_line(row: Dictionary) -> String:
	return "%s  %s" % [row["base"], doors_text(row)]


## "doors close 10:30": the game-clock time the row's doors close.
static func doors_text(row: Dictionary) -> String:
	return "doors close %s" % GameCalendar.clock_text(row["doors"])


## The rows for each flight leaving on `day`, earliest first (see _rows); the
## departures board reads today's and tomorrow's.
static func rows_for_day(flights: FlightSim, day: int) -> Array[Dictionary]:
	return _rows(flights, day)


## {tick, doors, base, line, departed, contract, gate} for each flight leaving
## on `today`, earliest first; `doors` is the tick its doors close, `contract`
## the contract id ("" for a one-off) and `gate` the gate the flight holds.
static func _rows(flights: FlightSim, today: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var open := flights.opened_tick >= 0
	var start_days := flights.start_days
	for contract_id in flights.contract_ids():
		var contract := flights.contract_of(contract_id)
		if not open or int(start_days[contract_id]) > today:
			continue
		var end_day := flights.contract_end_day(contract_id)
		if end_day >= 0 and today >= end_day:
			continue
		var tick := GameCalendar.tick_at(today, int(contract["departure_minute"]))
		var state := flights.state_of(FlightTimetable.occurrence_id(contract_id, today))
		var title := "%s  %s" % [contract["destination"], contract["airline"]]
		var doors := FlightTimetable.starts_for(contract, today)[FlightSim.State.DOORS_CLOSED]
		# An occurrence already issued keeps the gate it was issued at.
		var gate := flights.flight_gate(FlightTimetable.occurrence_id(contract_id, today))
		if gate == "":
			gate = contract["gate"]
		rows.append(_row(tick, doors, title, state, contract_id, gate))
	for id in flights.flight_ids():
		if flights.flight_contract_id(id) != "":
			continue
		var tick := flights.state_start(id, FlightSim.State.PUSHBACK)
		if GameCalendar.day_of(tick) == today:
			var doors := flights.doors_close_tick(id)
			rows.append(_row(tick, doors, id, flights.state_of(id), "", flights.flight_gate(id)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])
	return rows


static func _row(
	tick: int, doors: int, title: String, state: int, contract_id: String, gate: String
) -> Dictionary:
	var base := "%s  %s" % [GameCalendar.clock_text(tick), title]
	var line := base
	var status: String = (
		"Boarding"
		if state == FlightSim.State.BOARDING
		else PassengerHud.AFTER_DOORS_TEXT.get(state, "")
	)
	if status != "":
		line += "  " + status
	return {
		"tick": tick,
		"doors": doors,
		"base": base,
		"line": line,
		"departed": state == FlightSim.State.DEPARTED,
		"contract": contract_id,
		"gate": gate,
	}
