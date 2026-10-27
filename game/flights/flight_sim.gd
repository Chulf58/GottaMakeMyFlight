class_name FlightSim
extends Node
## The flight schedule as plain data driven by SimClock ticks. Each flight is
## a record (id, start tick of every state, current state, gate); a tick moves
## it to the next state when that state's start tick arrives. Nodes only read
## it. All times are integer sim ticks (20 per second), so speed and pause
## change nothing here.
##
## Flights come from two places. Accepted contracts (FlightContract) run a
## daily timetable: each day's occurrence is issued ahead of its first state
## (FlightTimetable), named "<contract>-d<day>", and pruned after it departs;
## queries on a pruned occurrence still answer from its immutable contract.
## add_flight adds a one-off flight, which is never pruned; add_default_flight
## is the one-off GMF101 that tests still use.
##
## The airport starts closed and issues no occurrence until it opens
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening). AirportGate opens it once it is staffed and has a
## working path, and accepts the STARTER_TERMS contract then; open_airport()
## alone opens it without the starter. It never closes again. A contract
## accepted while closed starts on its first day issued at or after the
## opening (FlightTimetable.opening_day); the days it skipped were never
## flown, so they are never answered as departed.
##
## One tick: set the tick, let the gate open the airport, issue due
## occurrences in time order, advance every flight, prune. PassengerSim binds
## after FlightSim, so it sees the result.

signal state_changed(flight_id: String, new_state: int)
## Fires once as a flight enters DOORS_CLOSED. The passenger slice stops
## boarding on it; is_doors_closed() answers the same question as a query.
signal doors_closed(flight_id: String)
## Fires once when a contract's occurrence is issued, after it is recorded,
## before any of its states is due. Never fires on a snapshot load.
signal occurrence_added(flight_id: String)

enum State {
	SCHEDULED,
	APPROACH,
	LANDING,
	TAXI_IN,
	AT_STAND,
	BOARDING,
	DOORS_CLOSED,
	PUSHBACK,
	TAXI_OUT,
	TAKEOFF,
	DEPARTED,
}

const STATE_COUNT := 11
## How long each state lasts in ticks, SCHEDULED to TAKEOFF. DEPARTED is final.
## BOARDING is 1200 ticks (60 s): in the reference terminal the walk from the
## farthest gate seat out through the exit and along the apron to the plane
## door is about 915 ticks at walking pace (test_boarding_window.gd).
const PHASE_TICKS: Array[int] = [100, 120, 140, 300, 40, 1200, 60, 120, 300, 200]
const DEFAULT_ID := "GMF101"
## Gates with a stand. Only gate C has one; more gates are a later slice.
const GATES: Array[String] = ["C"]
const DEFAULT_GATE := "C"
## The contract the airport opens with (Economy 7/8), without its departure
## minute: starter_terms() sets that from the opening tick. Fee and size sit
## inside the offer board's ranges.
const STARTER_TERMS := {
	"id": DEFAULT_ID,
	"airline": "Gotta Air",
	"destination": "Oslo",
	"gate": DEFAULT_GATE,
	"plane_size": "small",
	"booked_passengers": 12,
	"fee_per_passenger": 25,
}
## 2: occurrences are issued FlightTimetable.ISSUE_LEAD_TICKS (2400, was 1200)
## before their first state, which changes the saved next_day at some ticks.
## 3: the airport's open state (opened_tick, start_day). A version 2 save
## loads as open since tick 0.
const SAVE_VERSION := 3

## The clock to follow when this node enters a scene. Tests call bind_clock.
@export var clock: SimClock

## The tick the sim has been told about; set by the clock or a snapshot.
var tick: int = 0
## The tick the airport opened, or -1 while it is closed. Set only by
## open_airport() and from_snapshot(); read it, never write it.
var opened_tick: int = -1
## Asked on each tick while the airport is closed whether it may open
## (AirportGate.try_open). Set by AirportGate.bind(); without one the airport
## stays closed until open_airport() is called.
var gate: AirportGate

## Live flights {id, starts, state, gate, contract, day}, in timetable order
## (FlightTimetable.flight_before), so the order is a function of what is
## live and a load restores it exactly.
## A one-off flight has contract "" and day -1.
var _flights: Array[Dictionary] = []
## Read-only contracts in acceptance order.
var _contracts: Array[Dictionary] = []
## Contract id -> the first day not yet issued.
var _next_day: Dictionary = {}
## Contract id -> its first day that is or will be issued: first_day, or for a
## contract accepted while closed, FlightTimetable.opening_day. Days from
## first_day up to it were skipped, not flown.
var _start_day: Dictionary = {}


func _ready() -> void:
	if clock != null:
		bind_clock(clock)


## Start ticks of every state for a flight whose SCHEDULED state begins at
## `first_tick`.
static func schedule_starts(first_tick: int) -> Array[int]:
	var starts: Array[int] = [first_tick]
	for ticks in PHASE_TICKS:
		starts.append(starts[starts.size() - 1] + ticks)
	return starts


func bind_clock(clock: SimClock) -> void:
	clock.ticked.connect(on_tick)


## STARTER_TERMS departing so that its first state is ISSUE_LEAD_TICKS after
## `now`, rounded up to a whole minute: its first occurrence is issued at
## `now` or within the minute after, never with less than the normal lead.
static func starter_terms(now: int) -> Dictionary:
	var departure := now + FlightTimetable.ISSUE_LEAD_TICKS + FlightTimetable.departure_offset()
	var minutes := -GameCalendar.floor_div(-departure, GameCalendar.TICKS_PER_MINUTE)
	var terms := STARTER_TERMS.duplicate()
	terms["departure_minute"] = GameCalendar.minute_of_day(minutes * GameCalendar.TICKS_PER_MINUTE)
	return terms


## Opens the airport at the current tick; it never closes again. Each contract
## accepted while closed starts on its first day issued at or after now, and
## what is due is issued at once. False (with an error) when already open.
## The starter contract is AirportGate.open()'s, not this.
func open_airport() -> bool:
	if opened_tick >= 0:
		push_error("FlightSim.open_airport: the airport opened at tick %d" % opened_tick)
		return false
	opened_tick = tick
	for contract in _contracts:
		var day := FlightTimetable.opening_day(contract, tick)
		_start_day[contract["id"]] = day
		_next_day[contract["id"]] = day
	_issue_due()
	return true


## Adds the one-off flight GMF101, starting at tick 0.
func add_default_flight() -> bool:
	return add_flight(DEFAULT_ID, schedule_starts(0))


## Adds a one-off flight. False (with an error) when the id is taken or has
## the occurrence form, `starts` is not STATE_COUNT non-decreasing ticks, the
## gate has no stand, or the flight would hold the gate during an occurrence.
func add_flight(id: String, starts: Array[int], gate := DEFAULT_GATE) -> bool:
	var problem := _one_off_problem(id, starts, gate)
	if problem != "":
		push_error("FlightSim: flight '%s' %s" % [id, problem])
		return false
	_insert(_record(id, starts, gate, "", -1))
	return true


## Accepts an offer's terms (FlightContract.TERM_KEYS) as a contract whose
## first occurrence is the first one whose whole preparation window is still
## ahead. False (with an error) for bad terms, a used id or a gate clash.
## Issues the first occurrence at once when it is already due and the airport
## is open; while it is closed the contract waits for the opening.
func accept_contract(terms: Dictionary) -> bool:
	var problem := accept_problem(terms)
	if problem != "":
		push_error("FlightSim.accept_contract: %s" % problem)
		return false
	var contract := _candidate(terms)
	_contracts.append(contract)
	_next_day[contract["id"]] = contract["first_day"]
	_start_day[contract["id"]] = contract["first_day"]
	_issue_due()
	return true


## Why accept_contract would refuse `terms` right now (bad terms, a gate with no
## stand, a used id or a gate clash), or "" when it would take them. Read-only:
## it pushes no error and changes nothing, so a caller can ask first.
func accept_problem(terms: Dictionary) -> String:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and not GATES.has(terms["gate"]):
		problem = "gate '%s' has no stand" % terms["gate"]
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	if problem != "":
		return problem
	return _clash_problem(_candidate(terms))


func on_tick(new_tick: int) -> void:
	tick = new_tick
	if opened_tick < 0 and gate != null:
		gate.try_open()
	_issue_due()
	for flight in _flights:
		_advance(flight)
	_prune()


## Live flights: one-off flights and issued occurrences not yet pruned.
func flight_ids() -> Array[String]:
	var ids: Array[String] = []
	for flight in _flights:
		ids.append(flight["id"])
	return ids


func contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		ids.append(contract["id"])
	return ids


## The read-only contract, or {} for an unknown id.
func contract_of(contract_id: String) -> Dictionary:
	for contract in _contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


## The contract an occurrence belongs to, or "" for a one-off or unknown flight.
func flight_contract_id(id: String) -> String:
	return _find(id).get("contract", "")


## The live flight holding `gate` now (from its first state until it
## departs), or "". Occurrences at one gate never overlap.
func flight_at_gate(gate: String) -> String:
	for flight in _flights:
		var starts: Array = flight["starts"]
		if flight["gate"] == gate and starts[0] <= tick and tick < starts[State.DEPARTED]:
			return flight["id"]
	return ""


func state_of(id: String) -> int:
	var flight := _find(id)
	return flight["state"] if not flight.is_empty() else -1


func state_start(id: String, state: int) -> int:
	var flight := _find(id)
	return flight["starts"][state] if not flight.is_empty() else -1


## Ticks from the start of BOARDING (x) to the tick the doors close (y).
func boarding_window(id: String) -> Vector2i:
	return Vector2i(state_start(id, State.BOARDING), state_start(id, State.DOORS_CLOSED))


func doors_close_tick(id: String) -> int:
	return state_start(id, State.DOORS_CLOSED)


## True from the moment the doors close until the flight is gone.
func is_doors_closed(id: String) -> bool:
	return state_of(id) >= State.DOORS_CLOSED


## How far through its current state a flight is at sim time `time` (a tick
## plus the clock's alpha), from 0 to 1. A final state reads 1.
func phase_progress(id: String, time: float) -> float:
	var flight := _find(id)
	var state: int = flight["state"] if not flight.is_empty() else -1
	if state < 0:
		return 0.0
	if state == State.DEPARTED:
		return 1.0
	var start: int = flight["starts"][state]
	var end: int = flight["starts"][state + 1]
	if end <= start:
		return 1.0
	return clampf((time - start) / float(end - start), 0.0, 1.0)


## JSON-safe state for a save.
func to_snapshot() -> Dictionary:
	return FlightSnapshot.save(tick, opened_tick, _contracts, _start_day, _next_day, _flights)


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the sim unchanged, when anything is missing, mistyped or inconsistent.
## Emits nothing: what the save had issued stays issued.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := FlightSnapshot.load(data)
	if loaded.has("error"):
		push_error("FlightSim.from_snapshot: %s" % loaded["error"])
		return false
	tick = loaded["tick"]
	opened_tick = loaded["opened_tick"]
	_contracts = loaded["contracts"]
	_start_day = loaded["start_day"]
	_next_day = loaded["next_day"]
	_flights = loaded["flights"]
	return true


## A flight record with the state it is in at the current tick.
func _record(
	id: String, starts: Array[int], gate: String, contract: String, day: int
) -> Dictionary:
	return {
		"id": id,
		"starts": starts.duplicate(),
		"state": FlightTimetable.state_at(starts, tick),
		"gate": gate,
		"contract": contract,
		"day": day,
	}


func _one_off_problem(id: String, starts: Array[int], gate: String) -> String:
	if id == "" or _index_of(id) >= 0:
		return "has an empty or used id"
	if not FlightTimetable.parse_occurrence(id).is_empty():
		return "has an id of the contract occurrence form"
	if not FlightTimetable.starts_valid(starts):
		return "needs %d non-decreasing start ticks, 0 or more" % STATE_COUNT
	if not GATES.has(gate):
		return "is at gate '%s', which has no stand" % gate
	for contract in _contracts:
		if contract["gate"] == gate:
			if FlightTimetable.contract_overlaps(contract, starts[0], starts[State.DEPARTED]):
				return "would hold gate %s during contract %s" % [gate, contract["id"]]
	return ""


## The contract `terms` would become now, with its first day. Terms must be valid.
func _candidate(terms: Dictionary) -> Dictionary:
	var fields := terms.duplicate()
	fields["first_day"] = 0
	fields["first_day"] = FlightTimetable.first_day(fields, tick)
	return FlightContract.make(fields)


func _clash_problem(contract: Dictionary) -> String:
	for other in _contracts:
		if FlightTimetable.contracts_clash(contract, other):
			return (
				"contract %s clashes with %s at gate %s"
				% [contract["id"], other["id"], other["gate"]]
			)
	for flight in _flights:
		var starts: Array = flight["starts"]
		if flight["contract"] == "" and flight["gate"] == contract["gate"]:
			if FlightTimetable.contract_overlaps(contract, starts[0], starts[State.DEPARTED]):
				return (
					"contract %s clashes with flight %s at gate %s"
					% [contract["id"], flight["id"], flight["gate"]]
				)
	return ""


## Issues every occurrence whose issue tick has come, oldest first (then by
## contract order and day), so the order never depends on dictionary order.
## Nothing while the airport is closed.
func _issue_due() -> void:
	if opened_tick < 0:
		return
	var due: Array = []
	for index in _contracts.size():
		var contract := _contracts[index]
		var day: int = _next_day[contract["id"]]
		while FlightTimetable.issue_tick(contract, day) <= tick:
			due.append([FlightTimetable.issue_tick(contract, day), index, day])
			day += 1
	due.sort_custom(_issued_before)
	for entry in due:
		_issue(_contracts[entry[1]], entry[2])


## Orders [issue tick, contract index, day] entries field by field.
static func _issued_before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


func _issue(contract: Dictionary, day: int) -> void:
	var id := FlightTimetable.occurrence_id(contract["id"], day)
	var starts := FlightTimetable.starts_for(contract, day)
	_insert(_record(id, starts, contract["gate"], contract["id"], day))
	_next_day[contract["id"]] = day + 1
	occurrence_added.emit(id)


func _insert(record: Dictionary) -> void:
	var at := _flights.size()
	while at > 0 and FlightTimetable.flight_before(record, _flights[at - 1]):
		at -= 1
	_flights.insert(at, record)


func _prune() -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var flight := _flights[i]
		if flight["contract"] == "":
			continue
		var contract := contract_of(flight["contract"])
		if tick >= FlightTimetable.prune_tick(contract, flight["day"]):
			_flights.remove_at(i)


func _advance(flight: Dictionary) -> void:
	var starts: Array = flight["starts"]
	while flight["state"] < State.DEPARTED and tick >= starts[flight["state"] + 1]:
		flight["state"] += 1
		state_changed.emit(flight["id"], flight["state"])
		if flight["state"] == State.DOORS_CLOSED:
			doors_closed.emit(flight["id"])


## The live record, or for an issued occurrence that was pruned, a departed
## record rebuilt from its contract; {} for anything else, including the days
## a contract skipped while the airport was closed.
func _find(id: String) -> Dictionary:
	var index := _index_of(id)
	if index >= 0:
		return _flights[index]
	var parts := FlightTimetable.parse_occurrence(id)
	if parts.is_empty():
		return {}
	var contract := contract_of(parts["contract"])
	var day: int = parts["day"]
	if contract.is_empty():
		return {}
	if day < _start_day[contract["id"]] or day >= _next_day[contract["id"]]:
		return {}
	var record := _record(
		id, FlightTimetable.starts_for(contract, day), contract["gate"], contract["id"], day
	)
	record["state"] = State.DEPARTED
	return record


func _index_of(id: String) -> int:
	for i in _flights.size():
		if _flights[i]["id"] == id:
			return i
	return -1
