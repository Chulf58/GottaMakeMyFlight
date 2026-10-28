class_name RouteCache
extends RefCounted
## Walk lengths along a BuildGrid's paths, kept until its walkability graph
## changes: owned by PassengerSim (routes) for the routed forecasts and exit
## choice, so a forecast asked every tick does not search the same route
## again. Every graph_changed clears it, so it never answers for a graph that
## has changed since. It holds what A* returned, not queues or station state,
## which the forecasts still read fresh on every call.
##
## The grid can hold its signals while a build transaction applies edits
## (BuildGrid.hold_signals()); that happens inside one synchronous call, so no
## forecast runs in between and the release clears the cache.

## Above this many routes the cache starts again, so a long stretch without
## an edit cannot grow it without end.
const MAX_ENTRIES := 8192

## How many path searches it has run (for tests and timing).
var searches := 0

var _grid: BuildGrid
## Vector4i(from.x, from.y, to.x, to.y) -> mm, JourneyForecast.NEVER_MM for
## no path.
var _mm: Dictionary = {}


## Reads routes from `grid` and clears on its graph_changed.
func bind(grid: BuildGrid) -> void:
	if _grid != null and _grid.graph_changed.is_connected(_on_graph_changed):
		_grid.graph_changed.disconnect(_on_graph_changed)
	_grid = grid
	_mm.clear()
	grid.graph_changed.connect(_on_graph_changed)


## The length in mm of the grid's path from `from` to `to`, or
## JourneyForecast.NEVER_MM when there is none.
func walk_mm(from: Vector2i, to: Vector2i) -> int:
	var key := Vector4i(from.x, from.y, to.x, to.y)
	if _mm.has(key):
		return _mm[key]
	if _mm.size() >= MAX_ENTRIES:
		_mm.clear()
	searches += 1
	var path := _grid.find_path(from, to)
	var mm := JourneyForecast.NEVER_MM if path.is_empty() else Passenger.path_mm(path)
	_mm[key] = mm
	return mm


func size() -> int:
	return _mm.size()


## Forgets every route (PassengerSim.from_snapshot() after a load).
func clear() -> void:
	_mm.clear()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_mm.clear()
