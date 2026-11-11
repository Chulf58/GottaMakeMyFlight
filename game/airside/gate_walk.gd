class_name GateWalk
extends RefCounted
## How long the walk to a gate takes (decision gate-walk-time-shows-on-desk-
## card-and-build-caption-longest-walk-from-security, user-ruled 2026-11-11;
## the walk itself stays as it is, decision long-walk-to-a-far-gate-is-by-
## design-keep-walking-speed-show): for each gate, the longest walk from any
## security exit to the place that gate would hand a passenger first, at
## PassengerSim.WALK_MM a tick, in game minutes rounded up, so no passenger
## who walks takes longer than shown.
##
## The first place from one exit is what GateCapacity.reserve() picks with
## every place free: the gate seat within GateReach.NEAR_CELLS of the gate
## desk nearest the desk (then nearest the exit), walked the way a cleared
## passenger walks it (GateRowWalk); with no such seat, the standing spot
## StandingSpots.free_nearest() would give first, over the grid's path
## (RouteCache). Seats and spots taken by other passengers are ignored, so the
## figure does not move with the crowd. An exit that has no way to the gate
## counts for nothing; a gate no exit reaches, or a world with no security
## exit, has NO_ROUTE.
##
## Worked out again only when the grid was edited or a gate's desk changed,
## on the first read after, never per frame: minutes() compares a small key
## and answers from the last result. View only; nothing here changes the sim.

## What minutes() answers for a gate no security exit reaches.
const NO_ROUTE := -1
## The desk card line, and the line when no walk exists.
const CARD_TEXT := "Walk from security: %d min"
const NO_ROUTE_TEXT := "Walk from security: no route"
## The build-mode caption's third line.
const CAPTION_TEXT := "%d min walk"

## How many times the figures were worked out (for the tests).
var computed := 0

var _sim: PassengerSim
var _watched: BuildGrid
var _edits := 0
var _key := []
var _worked := false
## Gate letter -> minutes, as the last working out found them.
var _minutes := {}


## Reads the walks of `sim`'s gates. Another sim starts over.
func bind(sim: PassengerSim) -> void:
	if sim == _sim:
		return
	_sim = sim
	_worked = false


## The desk card's line for `minutes`.
static func card_line(minutes: int) -> String:
	return CARD_TEXT % minutes if minutes >= 0 else NO_ROUTE_TEXT


## The caption's third line for `minutes`, "" when there is no walk to show.
static func caption_line(minutes: int) -> String:
	return CAPTION_TEXT % minutes if minutes >= 0 else ""


## Game minutes (rounded up) of the longest walk from a security exit to gate
## `gate`'s first place, or NO_ROUTE.
func minutes(gate: String) -> int:
	if _sim == null or _sim.grid == null:
		return NO_ROUTE
	_watch()
	var key := [_edits, _sim.layout.gate_desk_ids.hash(), _sim.layout.gate_desks.hash()]
	if not _worked or key != _key:
		_key = key
		_work_out()
	return _minutes.get(gate, NO_ROUTE)


func _watch() -> void:
	if _sim.grid == _watched:
		return
	_watched = _sim.grid
	_watched.graph_changed.connect(_on_graph_changed)
	_watched.edit_applied.connect(_on_edit_applied)
	_edits += 1


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_edits += 1


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_edits += 1


func _work_out() -> void:
	computed += 1
	_minutes.clear()
	_worked = true
	var exits := _exits()
	for gate: String in _sim.layout.gate_desks:
		var near: Array[Vector2i] = []
		near.assign(_sim.layout.gate_desks[gate])
		var longest := -1
		for exit in exits:
			longest = maxi(longest, _first_place_mm(exit, near))
		_minutes[gate] = NO_ROUTE if longest < 0 else _to_minutes(longest)


## The security exit cells, one each, in station order.
func _exits() -> Array[Vector2i]:
	var stations: Array = _sim.layout.passages.keys()
	stations.sort()
	var out: Array[Vector2i] = []
	for station: int in stations:
		var cell := _sim.security.exit_cell(station)
		if cell != BuildObjectDef.NO_CELL and not out.has(cell):
			out.append(cell)
	return out


## The walk in mm from `exit` to the first place of a gate whose desk is on
## `near`, or -1 when it has none it can walk to.
func _first_place_mm(exit: Vector2i, near: Array[Vector2i]) -> int:
	var layout := _sim.layout
	var seats := []
	for i in layout.seats.size():
		var seat: Dictionary = layout.seats[i]
		var reach := GateReach.cells_from(seat["cell"], near)
		if near.is_empty() or reach <= GateReach.NEAR_CELLS:
			seats.append([reach, Passenger.octile_mm(exit, seat["front"]), i])
	seats.sort()
	for entry: Array in seats:
		var seat: Dictionary = layout.seats[entry[2]]
		var mm := _seat_mm(exit, seat)
		if mm >= 0:
			return mm
	return _spot_mm(exit, near)


func _seat_mm(exit: Vector2i, seat: Dictionary) -> int:
	if exit == seat["front"]:
		return 0
	var path := GateRowWalk.path(_sim, exit, seat["front"], seat["cell"])
	return -1 if path.is_empty() else Passenger.path_mm(path)


## The walk to the first standing spot of the gate that has a way there. While
## the spots wait to be derived again (StandingSpots.stale, after an edit) the
## figure is worked out again on the next read.
func _spot_mm(exit: Vector2i, near: Array[Vector2i]) -> int:
	var standing := _sim.standing
	for spot in standing.ordered_from(exit, near):
		var mm := _sim.routes.walk_mm(exit, standing.cell_of(spot))
		if mm < JourneyForecast.NEVER_MM:
			_worked = not standing.stale
			return mm
	return -1


func _to_minutes(mm: int) -> int:
	var per_minute := GameCalendar.TICKS_PER_MINUTE
	@warning_ignore("integer_division")
	return (JourneyForecast.walk_ticks(mm) + per_minute - 1) / per_minute
