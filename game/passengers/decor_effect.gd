class_name DecorEffect
extends RefCounted
## Decor calms the passengers near it (decisions furniture-set-modelled-on-
## copenhagen-airport-decor-calms-pas and all-11-exported-decor-models-are-
## placeable-plants-trees-foun). Each decor piece in TABLE has a calm value and
## a radius in cells; the bigger pieces (fountain, statue, tree) have both
## higher. The bin, the posts and the chain give nothing, and the bush
## and benches give the least.
##
## A passenger who is inside the terminal and stands within a piece's radius
## (cells from the nearest cell of its footprint, as ScreenCoverage fans out
## from a screen) gets that piece's calm, if the piece can be seen from there:
## a plain wall between them blocks it like it blocks a screen. A seated
## passenger is calmed at its chair's cell. Calm adds up over the pieces in
## range, but never past MAX_CALM, and is paid out as mood: `calm` points every
## PERIOD_BEATS beats, spread evenly. Decor never lifts mood above CEILING, so
## it eases a wait and cannot carry anyone to a perfect mood alone; mood already
## above the ceiling is left as it is. That ceiling is the cap on the decor
## bonus, and it needs no per-passenger state, so a save holds nothing for
## decor: the covered cells are derived from the grid and worked out again
## after any edit or load.
##
## The mood goes into the airport rating through the passenger's mood when it
## makes its flight (AirportRating). Tuned by test_decor_tuning.

## Calm per period and radius in cells, by catalog id: x is calm, y is radius.
const TABLE := {
	&"fountain_indoor": Vector2i(3, 4),
	&"statue_indoor": Vector2i(2, 4),
	&"tree_indoor": Vector2i(2, 3),
	&"bench_2a_indoor": Vector2i(2, 2),
	&"plant_pot_2a": Vector2i(1, 2),
	&"plant_pot_1a": Vector2i(1, 2),
	&"bench_1a": Vector2i(1, 1),
	&"bush": Vector2i(1, 1),
	&"trash_can": Vector2i.ZERO,
	&"metal_pole": Vector2i.ZERO,
	&"metal_pole_chain": Vector2i.ZERO,
}
## A slow nudge: a fountain's 3 points in 10 beats is 0.3 mood a second, small
## beside a queue's loss of 1 a second and a gate seat's gain of 1 a second.
const PERIOD_BEATS := 10
## The most calm one passenger can draw, however much decor is in range: 4
## points per period, 0.4 mood a second. Two fountains and a statue saturate it.
const MAX_CALM := 4
## Decor lifts mood no higher than this. The top 15 points are left to a seat,
## a served visit and the like.
const CEILING := 85
## Stages where a passenger is not in the terminal: not yet arrived, on the
## apron and finished.
const AWAY_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.SPAWNED,
	Passenger.Stage.APRON,
	Passenger.Stage.MADE,
	Passenger.Stage.MISSED,
]

var _sim: PassengerSim
var _grid: BuildGrid
var _calm: Dictionary = {}
var _dirty := true


## Calm per period of the decor `def_id`; 0 for anything that is not decor.
static func calm_of(def_id: StringName) -> int:
	var row: Vector2i = TABLE.get(def_id, Vector2i.ZERO)
	return row.x


## Radius in cells of the decor `def_id`; 0 for anything that is not decor.
static func radius_of(def_id: StringName) -> int:
	var row: Vector2i = TABLE.get(def_id, Vector2i.ZERO)
	return row.y


## The cells a piece with `calm_of(def_id)` above 0 calms when it stands at
## `anchor` and `facing` on `grid`: cells with floor within its radius of its
## footprint that it can be seen from, its own footprint excluded.
static func calmed_cells(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var def := BuildCatalog.get_def(def_id)
	var radius := radius_of(def_id)
	if def == null or radius <= 0:
		return out
	var footprint := def.footprint(anchor, facing)
	var low := footprint[0]
	var high := footprint[0]
	for cell in footprint:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	for y in range(low.y - radius, high.y + radius + 1):
		for x in range(low.x - radius, high.x + radius + 1):
			var cell := Vector2i(x, y)
			if footprint.has(cell) or not grid.in_bounds(cell):
				continue
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			var nearest := cell.clamp(low, high)
			if ScreenCoverage.sight_clear(grid, nearest, cell):
				out.append(cell)
	return out


## The mood points one passenger draws per period from `calm` summed over the
## decor in range: capped at MAX_CALM.
static func capped(calm: int) -> int:
	return clampi(calm, 0, MAX_CALM)


## How many points of `calm` fall due on beat number `beat_number`: evenly
## spread, exactly `calm` of every PERIOD_BEATS beats.
static func due(calm: int, beat_number: int) -> int:
	@warning_ignore("integer_division")
	return (beat_number * calm) / PERIOD_BEATS - ((beat_number - 1) * calm) / PERIOD_BEATS


func bind(sim: PassengerSim) -> void:
	_sim = sim
	_grid = sim.grid
	_dirty = true
	if _grid != null:
		_grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _dirty = true)


## The summed calm per period at `cell`, before the cap; 0 where no decor
## reaches or without a grid.
func calm_at(cell: Vector2i) -> int:
	return int(cells().get(cell, 0))


## Every calmed cell, as cell -> summed calm. Worked out again only after the
## grid changed.
func cells() -> Dictionary:
	if _grid == null:
		return {}
	if _dirty:
		_calm.clear()
		for id in _grid.object_ids():
			var record := _grid.get_object(id)
			var def_id: StringName = record["def"]
			var calm := calm_of(def_id)
			if calm <= 0:
				continue
			for cell in calmed_cells(_grid, def_id, record["anchor"], record["facing"]):
				_calm[cell] = int(_calm.get(cell, 0)) + calm
		_dirty = false
	return _calm


## Once a simulated second per passenger, after its mood changed: decor in
## range lifts it a little, up to CEILING.
func beat(p: Passenger) -> void:
	if AWAY_STAGES.has(p.stage) or p.mood >= CEILING:
		return
	var calm := capped(calm_at(BoredomSim.watch_cell(p)))
	if calm <= 0:
		return
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	p.mood = mini(p.mood + due(calm, beat_number), CEILING)
