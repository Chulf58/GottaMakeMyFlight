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
## Driven by events, never polled (anti-pattern a-view-that-reacts-to-moving-
## sim-objects-must-check-them-on): a grid edit, a change of the gate links
## (GateDesks.changed) or a rebuild of the standing spots marks the figures
## stale and emits `changed`; the next minutes() works them out again and
## keeps them. While the standing spots wait to be derived again after an edit
## (StandingSpots.stale) a result is never kept, so a gate whose first place is
## a spot is not left with an answer worked out from the old spots; the rebuild
## emits `changed` again. View only; nothing here changes the sim.

## Something that can change a figure happened: readers redraw (on the next
## frame, once the rest of the edit has settled).
signal changed

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
var _gates: GateDesks
var _grid: BuildGrid
var _standing: StandingSpots
var _worked := false
## Gate letter -> minutes, as the last working out found them.
var _minutes := {}


## Reads the walks of `sim`'s gates; `gates`, when given, says when the gate
## links changed. Another sim starts over.
func bind(sim: PassengerSim, gates: GateDesks = null) -> void:
	if gates != null and gates != _gates:
		_gates = gates
		_gates.changed.connect(_stale)
	if sim == _sim:
		return
	_sim = sim
	_stale()


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
	if not _worked:
		_work_out()
	return _minutes.get(gate, NO_ROUTE)


## Follows the sim's grid and standing spots, which a load replaces.
func _watch() -> void:
	if _sim.grid != _grid:
		_grid = _sim.grid
		_grid.graph_changed.connect(_on_graph_changed)
		_grid.edit_applied.connect(_on_edit_applied)
		_worked = false
	if _sim.standing != _standing:
		_standing = _sim.standing
		_standing.rebuilt.connect(_stale)
		_worked = false


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_stale()


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_stale()


func _stale() -> void:
	_worked = false
	changed.emit()


func _work_out() -> void:
	computed += 1
	_minutes.clear()
	var exits := _exits()
	for gate: String in _sim.layout.gate_desks:
		var near: Array[Vector2i] = []
		near.assign(_sim.layout.gate_desks[gate])
		var longest := -1
		for exit in exits:
			longest = maxi(longest, _first_place_mm(exit, near))
		_minutes[gate] = NO_ROUTE if longest < 0 else _to_minutes(longest)
	# Kept only while the spots stand as derived; the rebuild says when to look again.
	_worked = not _sim.standing.stale


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


## The walk to the first standing spot of the gate that has a way there.
func _spot_mm(exit: Vector2i, near: Array[Vector2i]) -> int:
	var standing := _sim.standing
	for spot in standing.ordered_from(exit, near):
		var mm := _sim.routes.walk_mm(exit, standing.cell_of(spot))
		if mm < JourneyForecast.NEVER_MM:
			return mm
	return -1


func _to_minutes(mm: int) -> int:
	var per_minute := GameCalendar.TICKS_PER_MINUTE
	@warning_ignore("integer_division")
	return (JourneyForecast.walk_ticks(mm) + per_minute - 1) / per_minute
