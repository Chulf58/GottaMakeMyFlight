# gdlint:disable = max-public-methods
# FlightSim is the one flight data API; ending a contract (end_contract,
# active_contract_ids, contract_end_day) took it past the 20-method cap.
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
## Gates (decision gates-technical-design-gate-desks-link-to-north-exits-one-
## st, points 4 and 5): gate_ids() lists the gates with a stand, from
## gate_source. An accepted contract gets the lowest gate its whole timetable
## fits at; reassign_gate moves its days not yet issued to another gate, while
## the occurrences already issued keep theirs. Flights at different gates share
## the runway and the taxi lane, so they must not hold either at the same time
## (FlightTimetable.flight_holds); flights at one gate must not overlap there.
##
## end_contract stops a contract's future days (decision low-rating-ends-one-
## airline-contract-per-low-day): what it already issued still flies and the
## contract stays on record, but it issues nothing more and no longer holds its
## gate time against new contracts.
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
## Fires once when end_contract stops a contract's future days. Never fires on
## a snapshot load.
signal contract_ended(contract_id: String)
## Fires after from_snapshot() installs a save, so readers of the open state
## (AirportGate) can refresh. The only signal a load emits.
signal snapshot_loaded

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
## TAXI_IN (600) and TAXI_OUT (720) keep the peak taxi speed under 16 m/s on
## the longest route a legal stand gives (decision plane-stand-design-airside-
## moves-110-m-north-stand-snaps-to, point 5; test_airside_stand.gd). Departure
## is the start of PUSHBACK, so a longer TAXI_IN only moves the arrival earlier.
const PHASE_TICKS: Array[int] = [100, 120, 140, 600, 40, 1200, 60, 120, 720, 200]
const DEFAULT_ID := "GMF101"
## The gate of add_flight and add_default_flight unless told otherwise.
const DEFAULT_GATE := "C"
## The gates with a stand while gate_source is unset: the one stand so far.
const DEFAULT_GATES: Array[String] = [DEFAULT_GATE]
## The contract the airport opens with (Economy 7/8), without its departure
## minute: starter_terms() sets that from the opening tick. Fee and size sit
## inside the offer board's ranges.
const STARTER_TERMS := {
	"id": DEFAULT_ID,
	"airline": "Gotta Air",
	"destination": "Oslo",
	"plane_size": "small",
	"booked_passengers": 12,
	"fee_per_passenger": 25,
}
## 2: occurrences are issued FlightTimetable.ISSUE_LEAD_TICKS (2400, was 1200)
## before their first state, which changes the saved next_day at some ticks.
## 3: the airport's open state (opened_tick, start_day). A version 2 save
## loads as open since tick 0.
## 4: ended contracts (ended: contract id -> its first day never issued). A
## version 2 or 3 save loads with none ended.
## 5: a contract holds its plane class's passenger range (FlightContract.problem),
## so what a save may contain narrowed. A version 4 save is refused; there is no
## migration.
const SAVE_VERSION := 5

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
## Returns the gate letters that have a stand now, as an Array of Strings
## (gate_ids() sorts them). Gates slice 1b sets it from the placed gate desks;
## tests set it to supply more gates. Unset: DEFAULT_GATES.
var gate_source := Callable()
## Contract id -> its recorded start day, the first day that is or will be
## issued (see _start_day): a copy, so readers cannot change it. Writing it is
## an error.
var start_days: Dictionary:
	get:
		return _start_day.duplicate()
	set(_value):
		push_error("FlightSim.start_days is read-only")

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
## Contract id -> the first day it never issues, for the contracts that ended
## (end_contract). The day is the contract's _next_day when it ended, so it
## equals its _next_day from then on.
var _ended: Dictionary = {}


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
## gate has no stand, or the flight would meet an occurrence at the gate or
## on the runway or lane.
func add_flight(id: String, starts: Array[int], gate := DEFAULT_GATE) -> bool:
	var problem := _one_off_problem(id, starts, gate)
	if problem != "":
		push_error("FlightSim: flight '%s' %s" % [id, problem])
		return false
	_insert(_record(id, starts, gate, "", -1))
	return true


## Accepts an offer's terms (FlightContract.TERM_KEYS) as a contract whose
## first occurrence is the first one whose whole preparation window is still
## ahead, at the lowest gate its timetable fits at (accept_gate). False (with
## an error) for bad terms, a used id or no gate it fits at. Issues the first
## occurrence at once when it is already due and the airport is open; while it
## is closed the contract waits for the opening.
func accept_contract(terms: Dictionary) -> bool:
	var problem := accept_problem(terms)
	if problem != "":
		push_error("FlightSim.accept_contract: %s" % problem)
		return false
	var contract := _candidate(terms, _assignment(terms)["gate"])
	_contracts.append(contract)
	_next_day[contract["id"]] = contract["first_day"]
	_start_day[contract["id"]] = contract["first_day"]
	_issue_due()
	return true


## Why accept_contract would refuse `terms` right now (bad terms, a used id,
## no gate with a stand, or a clash at every gate, named for the lowest one),
## or "" when it would take them. Read-only: it pushes no error and changes
## nothing, so a caller can ask first.
func accept_problem(terms: Dictionary) -> String:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	if problem != "":
		return problem
	return _assignment(terms)["problem"]


## The gate accept_contract would give `terms` now: the lowest gate with a
## stand whose timetable it fits, or "" when it would refuse them.
func accept_gate(terms: Dictionary) -> String:
	if accept_problem(terms) != "":
		return ""
	return _assignment(terms)["gate"]


## The gates with a stand now, sorted, from gate_source (DEFAULT_GATES while it
## is unset). Pushes an error and lists none when the source returns anything
## but an array of distinct, non-empty strings.
func gate_ids() -> Array[String]:
	var listed: Variant = gate_source.call() if gate_source.is_valid() else DEFAULT_GATES
	var gates: Array[String] = []
	if typeof(listed) != TYPE_ARRAY:
		push_error("FlightSim.gate_source must return an array of gate letters")
		return gates
	for gate_id: Variant in listed:
		if typeof(gate_id) != TYPE_STRING or gate_id == "" or gates.has(gate_id):
			push_error("FlightSim.gate_source returned a bad gate list: %s" % [listed])
			return [] as Array[String]
		gates.append(gate_id)
	gates.sort()
	return gates


## Moves a running contract's days not yet issued to `gate_id`. The
## occurrences it already issued keep their gate and hold it until they are
## pruned. False (with an error) when reassign_problem names a reason.
func reassign_gate(contract_id: String, gate_id: String) -> bool:
	var problem := reassign_problem(contract_id, gate_id)
	if problem != "":
		push_error("FlightSim.reassign_gate: %s" % problem)
		return false
	for i in _contracts.size():
		if _contracts[i]["id"] == contract_id:
			_contracts[i] = _at_gate(_contracts[i], gate_id)
	return true


## Why reassign_gate would refuse to move `contract_id` to `gate_id` now (an
## unknown or ended contract, a gate with no stand, the gate it is at, or a
## clash there as accept_problem checks one, its own issued occurrences left
## out), or "". Read-only.
func reassign_problem(contract_id: String, gate_id: String) -> String:
	var contract := contract_of(contract_id)
	if contract.is_empty():
		return "no contract '%s'" % contract_id
	if _ended.has(contract_id):
		return "contract %s has ended" % contract_id
	if not gate_ids().has(gate_id):
		return "gate '%s' has no stand" % gate_id
	if contract["gate"] == gate_id:
		return "contract %s is already at gate %s" % [contract_id, gate_id]
	return _clash_problem(_at_gate(contract, gate_id))


## Where the running contracts at `from_gates` would go if those gates went:
## {"moves": contract id -> its new gate, "stuck": the contract ids no gate of
## `to_gates` takes}. Oldest first, each to the lowest gate of `to_gates` its
## timetable fits, checked as accept_problem checks one against the rest as
## moved so far (decision gates-technical-design-gate-desks-link-to-north-
## exits-one-st, point 6). Live flights are not moved: an issued occurrence
## keeps its gate. Read-only; move_contracts() carries a plan out.
func move_plan(from_gates: Array[String], to_gates: Array[String]) -> Dictionary:
	var targets := to_gates.duplicate()
	targets.sort()
	var contracts := _contracts.duplicate()
	var moves := {}
	var stuck: Array[String] = []
	for i in contracts.size():
		var contract: Dictionary = contracts[i]
		if _ended.has(contract["id"]) or not from_gates.has(contract["gate"]):
			continue
		var to := ""
		for gate_id in targets:
			if _clash_problem(_at_gate(contract, gate_id), contracts) == "":
				to = gate_id
				break
		if to == "":
			stuck.append(contract["id"])
			continue
		moves[contract["id"]] = to
		contracts[i] = _at_gate(contract, to)
	return {"moves": moves, "stuck": stuck}


## Carries out a move_plan() whose "stuck" is empty, all moves or none: the
## moves are checked in order on a scratch copy of the contracts, each as
## reassign_gate() checks one against the rest as moved so far, and only when
## every one fits does the copy replace the contracts. False (with an error,
## nothing moved) when `plan` has stuck contracts, names a contract that is not
## running, or a move no longer fits (the world changed since the plan).
func move_contracts(plan: Dictionary) -> bool:
	if not (plan["stuck"] as Array).is_empty():
		push_error("FlightSim.move_contracts: contracts %s fit no gate" % [plan["stuck"]])
		return false
	var moves: Dictionary = plan["moves"]
	var scratch := _contracts.duplicate()
	var moved := 0
	for i in scratch.size():
		var contract: Dictionary = scratch[i]
		if not moves.has(contract["id"]):
			continue
		var problem := (
			"contract %s has ended" % contract["id"] if _ended.has(contract["id"]) else ""
		)
		if problem == "":
			problem = _clash_problem(_at_gate(contract, moves[contract["id"]]), scratch)
		if problem != "":
			push_error("FlightSim.move_contracts: nothing moved: %s" % problem)
			return false
		scratch[i] = _at_gate(contract, moves[contract["id"]])
		moved += 1
	if moved != moves.size():
		push_error("FlightSim.move_contracts: nothing moved: the plan names unknown contracts")
		return false
	_contracts = scratch
	return true


## Ends a contract: no day from its next unissued one on is ever issued, so the
## occurrences already issued still fly and the contract stays on record (its
## fee and terms still answer for them). Its gate time is free for a new
## contract. False (with an error) for an unknown or already ended contract or
## while the airport is closed.
func end_contract(contract_id: String) -> bool:
	if contract_of(contract_id).is_empty():
		push_error("FlightSim.end_contract: no contract '%s'" % contract_id)
		return false
	if _ended.has(contract_id):
		push_error("FlightSim.end_contract: contract '%s' already ended" % contract_id)
		return false
	if opened_tick < 0:
		push_error("FlightSim.end_contract: the airport is closed")
		return false
	_ended[contract_id] = _next_day[contract_id]
	contract_ended.emit(contract_id)
	return true


## The contracts that have not ended, in acceptance order (oldest first).
func active_contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			ids.append(contract["id"])
	return ids


## The first day an ended contract never issues, or -1 while it is running or
## unknown.
func contract_end_day(contract_id: String) -> int:
	return _ended.get(contract_id, -1)


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


## The gate a live flight holds: for an occurrence issued before its contract
## moved, the contract's old gate. A pruned occurrence answers with its
## contract's gate now. "" for an unknown flight.
func flight_gate(id: String) -> String:
	return _find(id).get("gate", "")


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
	return FlightSnapshot.save(
		tick, opened_tick, _contracts, _start_day, _next_day, _ended, _flights
	)


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the sim unchanged, when anything is missing, mistyped or inconsistent.
## Emits only snapshot_loaded: what the save had issued stays issued.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := FlightSnapshot.load(data, gate_ids())
	if loaded.has("error"):
		push_error("FlightSim.from_snapshot: %s" % loaded["error"])
		return false
	tick = loaded["tick"]
	opened_tick = loaded["opened_tick"]
	_contracts = loaded["contracts"]
	_start_day = loaded["start_day"]
	_next_day = loaded["next_day"]
	_ended = loaded["ended"]
	_flights = loaded["flights"]
	snapshot_loaded.emit()
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
	if not gate_ids().has(gate):
		return "is at gate '%s', which has no stand" % gate
	return _one_off_clash(starts, gate)


## What a one-off at `gate` with `starts` would meet: a running contract's
## days, or an issued occurrence, at the gate or on the runway or lane.
func _one_off_clash(starts: Array[int], gate: String) -> String:
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			var on := FlightTimetable.contract_meets(contract, gate, starts)
			if on != "":
				return "would %s during contract %s" % [_held(on, gate), contract["id"]]
	# Issued occurrences hold the gate they were issued at: an ended contract's,
	# or one issued before its contract moved. Other one-offs are not checked.
	for flight in _flights:
		if flight["contract"] != "":
			var on := FlightTimetable.clash_on(gate, starts, flight["gate"], flight["starts"])
			if on != "":
				return "would %s during %s" % [_held(on, gate), flight["id"]]
	return ""


## "hold gate C", "use the runway" or "use the taxi lane" for a clash_on answer.
static func _held(on: String, gate_id: String) -> String:
	if on == FlightTimetable.GATE:
		return "hold gate %s" % gate_id
	return "use the %s" % _ground_name(on)


## "at gate C", "on the runway" or "on the taxi lane" for a clash_on answer.
static func _where(on: String, gate_id: String) -> String:
	if on == FlightTimetable.GATE:
		return "at gate %s" % gate_id
	return "on the %s" % _ground_name(on)


static func _ground_name(on: String) -> String:
	return "runway" if on == FlightTimetable.RUNWAY else "taxi lane"


## The contract `terms` would become now at `gate_id`, with its first day.
## Terms must be valid.
func _candidate(terms: Dictionary, gate_id: String) -> Dictionary:
	var fields := terms.duplicate()
	fields["gate"] = gate_id
	fields["first_day"] = 0
	fields["first_day"] = FlightTimetable.first_day(fields, tick)
	return FlightContract.make(fields)


## A read-only copy of `contract` at `gate_id`.
static func _at_gate(contract: Dictionary, gate_id: String) -> Dictionary:
	var fields := contract.duplicate()
	fields["gate"] = gate_id
	return FlightContract.make(fields)


## {"gate": the lowest gate the contract made of valid `terms` fits at, or "";
## "problem": "" or why none fits}. A clash on the runway or lane fails at every
## gate, so it is named first (a candidate at gate "" meets nothing at a gate);
## otherwise the lowest gate's clash is.
func _assignment(terms: Dictionary) -> Dictionary:
	var gates := gate_ids()
	if gates.is_empty():
		return {"gate": "", "problem": "no gate has a stand"}
	var shared := _clash_problem(_candidate(terms, ""))
	if shared != "":
		return {"gate": "", "problem": shared}
	var first := ""
	for gate_id in gates:
		var problem := _clash_problem(_candidate(terms, gate_id))
		if problem == "":
			return {"gate": gate_id, "problem": ""}
		if first == "":
			first = problem
	return {"gate": "", "problem": first}


## Why `contract` could not run beside the rest: a running contract, or a live
## flight (a one-off, or an issued occurrence of another contract, which keeps
## the gate it was issued at), that it would meet at its gate or on the runway
## or lane; "" for none. Its own issued occurrences are left out: they are days
## it no longer issues.
func _clash_problem(contract: Dictionary, contracts: Array[Dictionary] = _contracts) -> String:
	for other in contracts:
		if other["id"] == contract["id"] or _ended.has(other["id"]):
			continue
		var on := FlightTimetable.contracts_clash_on(contract, other)
		if on != "":
			return (
				"contract %s clashes with %s %s"
				% [contract["id"], other["id"], _where(on, other["gate"])]
			)
	for flight in _flights:
		if flight["contract"] == contract["id"]:
			continue
		var on := FlightTimetable.contract_meets(contract, flight["gate"], flight["starts"])
		if on != "":
			return (
				"contract %s clashes with flight %s %s"
				% [contract["id"], flight["id"], _where(on, flight["gate"])]
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
		if _ended.has(contract["id"]):
			continue
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
