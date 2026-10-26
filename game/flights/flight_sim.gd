class_name FlightSim
extends Node
## The flight schedule as plain data driven by SimClock ticks. Each flight is
## a record (id, start tick of every state, current state); a tick moves it to
## the next state when that state's start tick arrives. Nodes only read it.
## All times are integer sim ticks (20 per second), so speed and pause change
## nothing here.

signal state_changed(flight_id: String, new_state: int)
## Fires once as a flight enters DOORS_CLOSED. The passenger slice stops
## boarding on it; is_doors_closed() answers the same question as a query.
signal doors_closed(flight_id: String)

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

## The clock to follow when this node enters a scene. Tests call bind_clock.
@export var clock: SimClock

## The tick the sim has been told about; set by the clock or a snapshot.
var tick: int = 0

var _flights: Array[Dictionary] = []


func _ready() -> void:
	if clock != null:
		bind_clock(clock)
		add_default_flight()


## Start ticks of every state for a flight whose SCHEDULED state begins at
## `first_tick`.
static func schedule_starts(first_tick: int) -> Array[int]:
	var starts: Array[int] = [first_tick]
	for ticks in PHASE_TICKS:
		starts.append(starts[starts.size() - 1] + ticks)
	return starts


func bind_clock(clock: SimClock) -> void:
	clock.ticked.connect(on_tick)


## Adds the one scheduled flight, GMF101, starting at tick 0.
func add_default_flight() -> bool:
	return add_flight(DEFAULT_ID, schedule_starts(0))


## False (with an error) when the id is taken or `starts` is not STATE_COUNT
## non-decreasing ticks.
func add_flight(id: String, starts: Array[int]) -> bool:
	if id == "" or _index_of(id) >= 0:
		push_error("FlightSim: flight id '%s' is empty or already used" % id)
		return false
	if not _starts_valid(starts):
		push_error("FlightSim: flight '%s' needs %d non-decreasing start ticks" % [id, STATE_COUNT])
		return false
	_flights.append({"id": id, "starts": starts.duplicate(), "state": _state_at(starts, tick)})
	return true


func on_tick(new_tick: int) -> void:
	tick = new_tick
	for flight in _flights:
		_advance(flight)


func flight_ids() -> Array[String]:
	var ids: Array[String] = []
	for flight in _flights:
		ids.append(flight["id"])
	return ids


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
	var flights: Array = []
	for flight in _flights:
		flights.append(
			{"id": flight["id"], "starts": flight["starts"].duplicate(), "state": flight["state"]}
		)
	return {"tick": tick, "flights": flights}


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the sim unchanged, when anything is missing, mistyped or inconsistent.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("FlightSim.from_snapshot: %s" % problem)
		return false
	tick = int(data["tick"])
	_flights.clear()
	for entry in data["flights"]:
		var starts: Array[int] = []
		for value in entry["starts"]:
			starts.append(int(value))
		_flights.append({"id": entry["id"], "starts": starts, "state": int(entry["state"])})
	return true


func _snapshot_problem(data: Dictionary) -> String:
	if not (data.has("tick") and data.has("flights")):
		return "missing key 'tick' or 'flights'"
	if not _is_whole(data["tick"]) or int(data["tick"]) < 0:
		return "tick must be a whole number, 0 or more"
	if typeof(data["flights"]) != TYPE_ARRAY:
		return "flights must be an array"
	var seen: Array[String] = []
	for entry in data["flights"]:
		var problem := _entry_problem(entry, int(data["tick"]), seen)
		if problem != "":
			return problem
	return ""


func _entry_problem(entry: Variant, now: int, seen: Array[String]) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "each flight must be a dictionary"
	if not (entry.has("id") and entry.has("starts") and entry.has("state")):
		return "a flight is missing 'id', 'starts' or 'state'"
	if typeof(entry["id"]) != TYPE_STRING or entry["id"] == "" or seen.has(entry["id"]):
		return "flight ids must be unique, non-empty strings"
	seen.append(entry["id"])
	var problem := _starts_problem(entry["starts"])
	if problem != "":
		return problem
	var starts: Array[int] = []
	for value in entry["starts"]:
		starts.append(int(value))
	if not _is_whole(entry["state"]) or int(entry["state"]) != _state_at(starts, now):
		return "state does not match the tick"
	return ""


func _starts_problem(values: Variant) -> String:
	if typeof(values) != TYPE_ARRAY or values.size() != STATE_COUNT:
		return "starts must be an array of %d ticks" % STATE_COUNT
	var starts: Array[int] = []
	for value in values:
		if not _is_whole(value):
			return "start ticks must be whole numbers"
		starts.append(int(value))
	if not _starts_valid(starts):
		return "start ticks must be 0 or more and not decrease"
	return ""


func _advance(flight: Dictionary) -> void:
	var starts: Array = flight["starts"]
	while flight["state"] < State.DEPARTED and tick >= starts[flight["state"] + 1]:
		flight["state"] += 1
		state_changed.emit(flight["id"], flight["state"])
		if flight["state"] == State.DOORS_CLOSED:
			doors_closed.emit(flight["id"])


func _find(id: String) -> Dictionary:
	var index := _index_of(id)
	return _flights[index] if index >= 0 else {}


func _index_of(id: String) -> int:
	for i in _flights.size():
		if _flights[i]["id"] == id:
			return i
	return -1


## The state a flight is in at `now`: the last whose start tick has passed.
static func _state_at(starts: Array[int], now: int) -> int:
	var state := State.SCHEDULED
	while state < State.DEPARTED and now >= starts[state + 1]:
		state += 1
	return state


static func _starts_valid(starts: Array[int]) -> bool:
	if starts.size() != STATE_COUNT or starts[0] < 0:
		return false
	for i in range(1, STATE_COUNT):
		if starts[i] < starts[i - 1]:
			return false
	return true


static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value))
