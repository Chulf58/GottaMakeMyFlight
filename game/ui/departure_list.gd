class_name DepartureList
extends RefCounted
## Today's departures as the flight panel's text (Economy 7/8), a pure
## function of the FlightSim and the clock tick: one line per flight leaving
## today, earliest first, as "07:38  Oslo  Gotta Air  Boarding". The next
## departing flight (the earliest whose doors have not closed) shows
## "doors close in M:SS" in place of its status word (decision
## flight-panel-the-next-departing-flight-s-row-shows-a-doors-close-countdown);
## the others keep their status words. A contract
## shows its destination and airline from its recorded start day
## (FlightSim.start_days), a one-off flight its id. While the airport is
## closed no contract is listed, since nothing is scheduled until it opens; a
## contract accepted then never shows the days it skipped (decision
## airport-opening-design-stays-open-once-opened-starter-flight-placed-after-
## opening). The list is at most MAX_LINES lines, so the panel keeps its place
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
	var next := _next_departing(rows, tick)
	var lines := PackedStringArray()
	var shown := MAX_LINES - 1 if rows.size() > MAX_LINES else rows.size()
	for row in rows.slice(0, shown):
		lines.append(_countdown_line(row, tick) if row == next else row["line"])
	if shown < rows.size():
		lines.append("+%d more" % (rows.size() - shown))
	return "\n".join(lines)


## The earliest row whose doors have not closed at `tick`, or an empty one.
static func _next_departing(rows: Array[Dictionary], tick: int) -> Dictionary:
	for row in rows:
		if tick < row["doors"]:
			return row
	return {}


static func _countdown_line(row: Dictionary, tick: int) -> String:
	var left := maxi(0, row["doors"] - tick) / SimClock.TICK_RATE
	@warning_ignore("integer_division")
	return "%s  doors close in %d:%02d" % [row["base"], left / 60, left % 60]


## {tick, doors, base, line, departed} for each flight leaving on `today`,
## earliest first; `doors` is the tick its doors close.
static func _rows(flights: FlightSim, today: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var open := flights.opened_tick >= 0
	var start_days := flights.start_days
	for contract_id in flights.contract_ids():
		var contract := flights.contract_of(contract_id)
		if not open or int(start_days[contract_id]) > today:
			continue
		var tick := GameCalendar.tick_at(today, int(contract["departure_minute"]))
		var state := flights.state_of(FlightTimetable.occurrence_id(contract_id, today))
		var title := "%s  %s" % [contract["destination"], contract["airline"]]
		var doors := FlightTimetable.starts_for(contract, today)[FlightSim.State.DOORS_CLOSED]
		rows.append(_row(tick, doors, title, state))
	for id in flights.flight_ids():
		if flights.flight_contract_id(id) != "":
			continue
		var tick := flights.state_start(id, FlightSim.State.PUSHBACK)
		if GameCalendar.day_of(tick) == today:
			var doors := flights.doors_close_tick(id)
			rows.append(_row(tick, doors, id, flights.state_of(id)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])
	return rows


static func _row(tick: int, doors: int, title: String, state: int) -> Dictionary:
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
	}
