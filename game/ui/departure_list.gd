class_name DepartureList
extends RefCounted
## Today's departures as the flight panel's text (Economy 7/8), a pure
## function of the FlightSim and the clock tick: one line per flight leaving
## today, earliest first, as "07:38  Oslo  Gotta Air  Boarding". A contract
## shows its destination and airline from the day it starts, a one-off flight
## its id. The list is at most MAX_LINES lines, so the panel keeps its place
## above the flight result: when more leave today, flights that have departed
## drop off the top first, then the last line becomes "+n more".

const MAX_LINES := 3
const EMPTY_TEXT := "No departures today"


static func text(flights: FlightSim, tick: int) -> String:
	var rows := _rows(flights, GameCalendar.day_of(tick))
	if rows.is_empty():
		return EMPTY_TEXT
	while rows.size() > MAX_LINES and rows[0]["departed"]:
		rows.pop_front()
	var lines := PackedStringArray()
	var shown := MAX_LINES - 1 if rows.size() > MAX_LINES else rows.size()
	for row in rows.slice(0, shown):
		lines.append(row["line"])
	if shown < rows.size():
		lines.append("+%d more" % (rows.size() - shown))
	return "\n".join(lines)


## {tick, line, departed} for each flight leaving on `today`, earliest first.
static func _rows(flights: FlightSim, today: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for contract_id in flights.contract_ids():
		var contract := flights.contract_of(contract_id)
		if int(contract["first_day"]) > today:
			continue
		var tick := GameCalendar.tick_at(today, int(contract["departure_minute"]))
		var state := flights.state_of(FlightTimetable.occurrence_id(contract_id, today))
		var title := "%s  %s" % [contract["destination"], contract["airline"]]
		rows.append(_row(tick, title, state))
	for id in flights.flight_ids():
		if flights.flight_contract_id(id) != "":
			continue
		var tick := flights.state_start(id, FlightSim.State.PUSHBACK)
		if GameCalendar.day_of(tick) == today:
			rows.append(_row(tick, id, flights.state_of(id)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])
	return rows


static func _row(tick: int, title: String, state: int) -> Dictionary:
	var line := "%s  %s" % [GameCalendar.clock_text(tick), title]
	var status: String = (
		"Boarding"
		if state == FlightSim.State.BOARDING
		else PassengerHud.AFTER_DOORS_TEXT.get(state, "")
	)
	if status != "":
		line += "  " + status
	return {"tick": tick, "line": line, "departed": state == FlightSim.State.DEPARTED}
