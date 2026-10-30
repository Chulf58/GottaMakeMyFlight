class_name PrizeCar
extends RefCounted
## The prize car on its podium (decision furniture-set-modelled-on-copenhagen-
## airport-decor-calms-pas, point 2: "Raffle boosts shop spend"; board item
## F4-4). While a podium stands, passengers near it spend a bit more in shops
## and food venues, and some who wait in view of it look at it and are kept
## busy. It costs PriceTable.PRIZE_CAR_UPKEEP a game day on top of the podium's
## placement price, charged at midnight with the other upkeep (Settlement).
##
## Reach: a floor cell within SPEND_RADIUS cells (Chebyshev, from the nearest
## cell of the podium's footprint) that the car can be seen from, with the same
## sight rule as a screen or a piece of decor (ScreenCoverage.sight_clear: a
## plain wall blocks, glass and doors pass). Several podiums do not stack: a
## cell is as near as its nearest car. The reach is derived from the grid, worked out
## again after any edit, and never saved.
##
## Spend: a shop or food visit that settles while the passenger stands (or sits)
## in reach pays boosted() of the usual amount, SPEND_BONUS_PERCENT more. A paid
## service (shower, nap pod) is a fee, not a purchase, and is not boosted.
##
## Looking: every LOOKER_ONE_IN-th passenger (by id) is a looker. A looker who
## is waiting (BoredomSim.WAITING_STAGES) within LOOK_RADIUS of the car stops
## watching the clock: its boredom does not rise and drops LOOK_RELIEF every
## LOOK_RELIEF_BEATS beats (BoredomSim). Looking is ambient, like a screen; no
## passenger detours to the car. Tuned by test_prize_car.

const PODIUM_ID := &"prize_podium"
## How far the spend boost reaches, in cells from the podium.
const SPEND_RADIUS := 6
## A purchase in reach pays this many percent more.
const SPEND_BONUS_PERCENT := 20
## How near a looker must be to stop and look.
const LOOK_RADIUS := 3
## One passenger in this many is a looker.
const LOOKER_ONE_IN := 3
## A looker's boredom drops LOOK_RELIEF once every LOOK_RELIEF_BEATS beats.
const LOOK_RELIEF := 1
const LOOK_RELIEF_BEATS := 2
## What distance_at() says for a cell the car does not reach.
const NO_REACH := -1

var _grid: BuildGrid
var _reach: Dictionary = {}
var _dirty := true


## The ids of every podium on `grid`, ascending.
static func podium_ids(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in grid.object_ids():
		if grid.get_object(id)["def"] == PODIUM_ID:
			out.append(id)
	return out


## What `grid`'s prize cars cost to run for one game day.
static func daily_upkeep(grid: BuildGrid) -> int:
	return podium_ids(grid).size() * PriceTable.PRIZE_CAR_UPKEEP


## The cells a podium at `anchor` and `facing` reaches on `grid`, as cell ->
## distance in cells from its footprint (1 and up): floor within SPEND_RADIUS
## that the car can be seen from, the footprint itself excluded.
static func reach_cells(grid: BuildGrid, anchor: Vector2i, facing: int) -> Dictionary:
	var out := {}
	var def := BuildCatalog.get_def(PODIUM_ID)
	if def == null:
		return out
	var footprint := def.footprint(anchor, facing)
	var low := footprint[0]
	var high := footprint[0]
	for cell in footprint:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	for y in range(low.y - SPEND_RADIUS, high.y + SPEND_RADIUS + 1):
		for x in range(low.x - SPEND_RADIUS, high.x + SPEND_RADIUS + 1):
			var cell := Vector2i(x, y)
			if footprint.has(cell) or not grid.in_bounds(cell):
				continue
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			var nearest := cell.clamp(low, high)
			if ScreenCoverage.sight_clear(grid, nearest, cell):
				var gap := cell - nearest
				out[cell] = maxi(absi(gap.x), absi(gap.y))
	return out


## `amount` with the car's boost, rounded half up.
static func boosted(amount: int) -> int:
	@warning_ignore("integer_division")
	return (amount * (100 + SPEND_BONUS_PERCENT) + 50) / 100


## Whether `p` is a looker: a fixed share of passengers, picked by id.
static func is_looker(p: Passenger) -> bool:
	return posmod(p.id, LOOKER_ONE_IN) == 0


## Follows `grid`: the reach is worked out again after any edit.
func bind(grid: BuildGrid) -> void:
	_grid = grid
	_dirty = true
	grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _dirty = true)


## Distance in cells from the nearest car that can be seen from `cell`, or
## NO_REACH where no car reaches.
func distance_at(cell: Vector2i) -> int:
	return int(cells().get(cell, NO_REACH))


## Every reached cell, as cell -> distance. Worked out again only after the
## grid changed.
func cells() -> Dictionary:
	if _grid == null:
		return {}
	if _dirty:
		_reach.clear()
		for id in podium_ids(_grid):
			var record := _grid.get_object(id)
			var reached := reach_cells(_grid, record["anchor"], record["facing"])
			for cell: Vector2i in reached:
				_reach[cell] = mini(int(_reach.get(cell, SPEND_RADIUS + 1)), int(reached[cell]))
		_dirty = false
	return _reach


## Whether a purchase `p` settles now earns the boost: it stands in reach
## (seated at its chair's cell).
func boosts(p: Passenger) -> bool:
	return distance_at(BoredomSim.watch_cell(p)) != NO_REACH


## Whether `p` is looking at the car now: a looker, waiting, within LOOK_RADIUS.
func looks(p: Passenger) -> bool:
	if not is_looker(p) or not BoredomSim.WAITING_STAGES.has(p.stage):
		return false
	var gap := distance_at(BoredomSim.watch_cell(p))
	return gap != NO_REACH and gap <= LOOK_RADIUS
