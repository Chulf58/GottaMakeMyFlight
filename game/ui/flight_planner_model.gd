class_name FlightPlannerModel
extends RefCounted
## What the flight planner draws for one game day (decision flight-planner-a-
## full-screen-day-planner-with-one-row-per-ga), a pure function of the
## FlightSim: one row per gate (FlightSim.gate_ids()) with its colour, and in
## each row one bar per flight whose gate hold overlaps the day. A hold spans
## FlightTimetable.gate_hold_span() (an issued flight's own starts, else
## FlightTimetable.starts_for with its contract's taxi pair),
## so a late-evening flight's bar starts the evening before and an early flight
## can start on the day before; the bar is cut at midnight and says so. The
## gate is the one the occurrence holds: an issued occurrence keeps the gate it
## was issued at, an unissued one takes its contract's (DepartureList's rule).
## A flight on a gate that no longer has a stand has no row and no bar.

const DAY := GameCalendar.TICKS_PER_DAY


## The rows for `day`, in gate order: {gate, colour, bars}. Each bar is {contract
## ("" for a one-off), flight, gate, day (the departure day), start, end (the
## hold, in ticks), departure (the tick it leaves), label ("10:00  Oslo"),
## airline, active (a running contract, so it can be moved or ended), from, to
## (the visible part of the day as a fraction 0 to 1), cut_start, cut_end}.
static func rows_for_day(sim: FlightSim, day: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var by_gate := {}
	for gate_id in sim.gate_ids():
		var row := {"gate": gate_id, "colour": GateColours.of(gate_id), "bars": []}
		rows.append(row)
		by_gate[gate_id] = row
	for bar in bars_for_day(sim, day):
		if by_gate.has(bar["gate"]):
			(by_gate[bar["gate"]]["bars"] as Array).append(bar)
	for row in rows:
		(row["bars"] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return a["start"] < b["start"]
		)
	return rows


## Every bar that overlaps `day`, from the departures of the day before, the
## day and the day after.
static func bars_for_day(sim: FlightSim, day: int) -> Array[Dictionary]:
	var bars: Array[Dictionary] = []
	var day_start := GameCalendar.day_start(day, sim.epoch)
	var active := sim.active_contract_ids()
	for departure_day in [day - 1, day, day + 1]:
		for row in DepartureList.rows_for_day(sim, departure_day):
			var hold := _hold(sim, row, departure_day)
			if hold.end <= day_start or hold.start >= day_start + DAY:
				continue
			bars.append(_bar(row, departure_day, hold, day_start, active))
	return bars


## The row's occurrence's gate hold (FlightTimetable.gate_hold_span()), in ticks.
## An occurrence the sim has issued keeps the starts it was issued with (its
## taxi pair may not be its contract's now), so its hold is read from the sim;
## a day not yet issued takes its contract's times (FlightTimetable.starts_for).
static func _hold(sim: FlightSim, row: Dictionary, departure_day: int) -> Hold:
	if row["contract"] != "":
		var contract := sim.contract_of(row["contract"])
		var plane_size: String = contract.get("plane_size", PlaneClasses.MEDIUM)
		if sim.state_of(row["flight"]) < 0:
			var starts := FlightTimetable.starts_for(contract, departure_day, sim.epoch)
			var span := FlightTimetable.gate_hold_span(starts, plane_size)
			return Hold.new(span[0], span[1])
		var issued: Array[int] = []
		for state in FlightSim.STATE_COUNT:
			issued.append(sim.state_start(row["flight"], state))
		var span := FlightTimetable.gate_hold_span(issued, plane_size)
		return Hold.new(span[0], span[1])
	return Hold.new(
		sim.state_start(row["flight"], FlightSim.State.SCHEDULED),
		sim.state_start(row["flight"], FlightSim.State.DEPARTED)
	)


static func _bar(
	row: Dictionary, departure_day: int, hold: Hold, day_start: int, active: Array[String]
) -> Dictionary:
	var shown_start := maxi(hold.start, day_start)
	var shown_end := mini(hold.end, day_start + DAY)
	return {
		"contract": row["contract"],
		"flight": row["flight"],
		"gate": row["gate"],
		"day": departure_day,
		"start": hold.start,
		"end": hold.end,
		"departure": row["tick"],
		"label": row["head"],
		"place": String(row["head"]).get_slice("  ", 1),
		"airline": row["airline"],
		"active": row["contract"] != "" and active.has(row["contract"]),
		"from": float(shown_start - day_start) / DAY,
		"to": float(shown_end - day_start) / DAY,
		"cut_start": hold.start < day_start,
		"cut_end": hold.end > day_start + DAY,
	}


## A gate hold's two ticks.
class Hold:
	var start: int
	var end: int

	func _init(first: int, last: int) -> void:
		start = first
		end = last
