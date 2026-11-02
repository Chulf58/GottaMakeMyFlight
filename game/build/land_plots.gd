class_name LandPlots
extends RefCounted
## The airport site's land plots and which of them the player owns (decision
## player-builds-the-terminal-floor-outer-walls-auto-roof-land-plots-starter-
## one-floor, answer 3, and the land-plot rulings of board ee9914e6). The site
## grid is cut into SiteDefinition.plot_counts plots across and down from cell
## (0, 0), as evenly as whole cells allow: a width that does not divide gives
## its extra cells one each to the first columns (ruling land-plots-are-near-
## even-columns-of-22-22-21-and-21-m-by-25: 22, 22, 21 and 21 on the 86 cell
## site, six rows of 25 down its 150). A new game owns every plot the starter shell stands on
## and every plot that shares an edge or a corner with one (own_start(),
## ruling a-new-game-owns-the-land-plots-under-the-starter-shell-plus). The
## player buys a plot that shares an edge with owned land at the price
## PriceTable.price_of_land_plot() gives for the plots bought so far (ruling
## land-plot-price-rises-with-each-plot-bought-from-a-small-tun), paid from the
## wallet like building. Bought land is never sold and costs nothing to keep
## (ruling bought-land-plots-cannot-be-sold-back-and-have-no-upkeep-one), so
## ownership only grows.
##
## The site's grid (SiteGrid) asks edit_problem() before every edit: building
## on land the player does not own is refused, removing is not. Saved as the
## "land" part (SaveGame).

## A plot was bought or the ownership was loaded.
signal changed

## The edit kinds that build nothing; they pass anywhere.
const REMOVALS: Array[BuildEdit.Kind] = [
	BuildEdit.Kind.REMOVE_FLOOR,
	BuildEdit.Kind.REMOVE_WALL,
	BuildEdit.Kind.REMOVE_OBJECT,
	BuildEdit.Kind.REMOVE_ROOM,
]
const SNAPSHOT_KEYS := ["plot_counts", "owned", "bought"]
## The four plots that share an edge with a plot.
const EDGE_STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]

## The site grid's size in cells.
var grid_size := Vector2i.ZERO
## How many plots there are across (x) and down (y).
var plots := Vector2i.ZERO
## How many plots the player has bought; the next one's price depends on it.
var bought := 0

## 1 per owned plot, at column + row * plots.x.
var _owned := PackedByteArray()
## The first grid cell of each column and row, then the grid's size
## (plots.x + 1 and plots.y + 1 entries).
var _column_starts := PackedInt32Array()
var _row_starts := PackedInt32Array()


func _init(site_grid_size := Vector2i.ONE, counts := Vector2i.ONE) -> void:
	grid_size = site_grid_size
	plots = counts.clamp(Vector2i.ONE, grid_size.max(Vector2i.ONE))
	_column_starts = _starts(grid_size.x, plots.x)
	_row_starts = _starts(grid_size.y, plots.y)
	_owned.resize(plots.x * plots.y)
	_owned.fill(0)


## Unowned plots over `site`'s grid.
static func for_site(site: SiteDefinition) -> LandPlots:
	return LandPlots.new(site.grid_size, site.plot_counts)


## Where `count` near-even parts of `length` cells start, then `length`: the
## first `length % count` parts take one extra cell.
static func _starts(length: int, count: int) -> PackedInt32Array:
	@warning_ignore("integer_division")
	var base := length / count
	var extra := length % count
	var out := PackedInt32Array()
	for i in count + 1:
		out.append(i * base + mini(i, extra))
	return out


func in_site(plot: Vector2i) -> bool:
	return plot.x >= 0 and plot.y >= 0 and plot.x < plots.x and plot.y < plots.y


## The plot a grid cell lies in (off-site for a cell off the grid).
func plot_of(cell: Vector2i) -> Vector2i:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return Vector2i(-1, -1)
	return Vector2i(
		_column_starts.bsearch(cell.x, false) - 1, _row_starts.bsearch(cell.y, false) - 1
	)


## The grid cells of a plot (empty for a plot off the site).
func plot_cells(plot: Vector2i) -> Rect2i:
	if not in_site(plot):
		return Rect2i()
	var start := Vector2i(_column_starts[plot.x], _row_starts[plot.y])
	var end := Vector2i(_column_starts[plot.x + 1], _row_starts[plot.y + 1])
	return Rect2i(start, end - start)


func is_owned(plot: Vector2i) -> bool:
	return in_site(plot) and _owned[plot.x + plot.y * plots.x] != 0


## Whether the player owns the land under a grid cell.
func owns_cell(cell: Vector2i) -> bool:
	return is_owned(plot_of(cell))


## Every owned plot, row by row.
func owned_plots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in plots.y:
		for x in plots.x:
			if _owned[x + y * plots.x] != 0:
				out.append(Vector2i(x, y))
	return out


## Whether a plot shares an edge with an owned one.
func touches_owned(plot: Vector2i) -> bool:
	for step in EDGE_STEPS:
		if is_owned(plot + step):
			return true
	return false


## The plots the player may buy now: on the site, not owned, touching owned
## land. Row by row.
func buyable_plots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in plots.y:
		for x in plots.x:
			var plot := Vector2i(x, y)
			if not is_owned(plot) and touches_owned(plot):
				out.append(plot)
	return out


## What the next plot costs.
func next_price() -> int:
	return PriceTable.price_of_land_plot(bought)


## Why `plot` cannot be bought now from `wallet` (null: buying is free), as a
## BuildResult refusal, or null when it can.
func buy_problem(plot: Vector2i, wallet: Wallet) -> BuildResult:
	if not in_site(plot):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if is_owned(plot):
		return BuildResult.refused(BuildResult.Reason.LAND_OWNED)
	if not touches_owned(plot):
		return BuildResult.refused(BuildResult.Reason.LAND_NOT_TOUCHING)
	var price := next_price()
	if price < 0:
		return BuildResult.refused(BuildResult.Reason.UNPRICED)
	if wallet != null and not wallet.can_afford(price):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	return null


## Buys `plot`, paying next_price() from `wallet` (Wallet.Category.BUILD; null:
## free). Returns the refusal and changes nothing when buy_problem() refuses.
func buy(plot: Vector2i, wallet: Wallet) -> BuildResult:
	var problem := buy_problem(plot, wallet)
	if problem != null:
		return problem
	var price := next_price()
	# Owned and counted before the money moves, so a listener to the wallet
	# (BuildMenu's card price) already reads the next plot's price.
	_owned[plot.x + plot.y * plots.x] = 1
	bought += 1
	if wallet != null and not wallet.spend(price, Wallet.Category.BUILD):
		_owned[plot.x + plot.y * plots.x] = 0
		bought -= 1
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	changed.emit()
	return BuildResult.accepted()


## Owns every plot under one of `cells` and every plot that shares an edge or
## a corner with such a plot, as a new game does for the starter shell. Buys
## nothing: `bought` stays as it is.
func own_around(cells: Array[Vector2i]) -> void:
	var under := {}
	for cell in cells:
		var plot := plot_of(cell)
		if in_site(plot):
			under[plot] = true
	for plot: Vector2i in under:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := plot + Vector2i(dx, dy)
				if in_site(near):
					_owned[near.x + near.y * plots.x] = 1
	changed.emit()


## A new game's land on `site`: the starter shell's plots plus one ring
## (own_around() of every cell the shell's edits name).
func own_start(site: SiteDefinition) -> void:
	var cells: Array[Vector2i] = []
	for edit in ReferenceTerminal.shell_edits(site.starter_offset):
		cells.append(edit.cell)
	own_around(cells)


## The LAND_NOT_OWNED refusal for an edit that builds on land the player does
## not own, else null. Floor, an object's footprint and a room need every
## cell owned; a wall needs an owned cell on one side of its edge, so the
## outer wall of owned land can stand on its border. Removals pass, and cells
## off the grid are left to the grid's own OUT_OF_BOUNDS.
func edit_problem(edit: BuildEdit) -> BuildResult:
	if REMOVALS.has(edit.kind):
		return null
	var unowned := false
	if edit.kind == BuildEdit.Kind.PLACE_WALL:
		var beyond := edit.cell + BuildGrid.SIDE_STEP[edit.side]
		var on_grid := in_site(plot_of(edit.cell)) or in_site(plot_of(beyond))
		unowned = on_grid and not owns_cell(edit.cell) and not owns_cell(beyond)
	else:
		for cell in _cells_of(edit):
			unowned = unowned or (in_site(plot_of(cell)) and not owns_cell(cell))
	return BuildResult.refused(BuildResult.Reason.LAND_NOT_OWNED) if unowned else null


## The cells an edit other than a wall builds on: an object's footprint (none
## for an unknown object, which the grid refuses), a room's area, else its cell.
static func _cells_of(edit: BuildEdit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [edit.cell]
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			var def := BuildCatalog.get_def(edit.def_id)
			cells = def.footprint(edit.cell, edit.facing) if def != null else cells
		BuildEdit.Kind.PLACE_ROOM, BuildEdit.Kind.RESIZE_ROOM:
			cells = []
			for y in edit.room_size.y:
				for x in edit.room_size.x:
					cells.append(edit.cell + Vector2i(x, y))
	return cells


## The edge of the owned land as closed loops of corner points on the ground
## (x is world x, y is world z) for a grid whose cell (0, 0) has its north-west
## corner at `origin`. Each loop runs clockwise seen from above, owned land on
## its right, so a hole of unowned land runs the other way. A loop starts at
## its north-west-most corner and holds only its corners (straight runs are
## one side). Where two owned plots meet only at a corner, the loop turns
## toward the owned side there, so each loop stays simple.
func outline_loops(origin: Vector3) -> Array[PackedVector2Array]:
	# Directed boundary sides, keyed by start corner (in plot corners).
	var leaving := {}
	for plot in owned_plots():
		var corners := [plot, plot + Vector2i(1, 0), plot + Vector2i(1, 1), plot + Vector2i(0, 1)]
		for side in 4:
			if not is_owned(plot + EDGE_STEPS[side]):
				var start: Vector2i = corners[side]
				if not leaving.has(start):
					leaving[start] = []
				leaving[start].append(corners[(side + 1) % 4])
	var loops: Array[PackedVector2Array] = []
	while not leaving.is_empty():
		var first: Vector2i = leaving.keys()[0]
		for start: Vector2i in leaving:
			if start.y < first.y or (start.y == first.y and start.x < first.x):
				first = start
		var corners := _trace(leaving, first)
		var points := PackedVector2Array()
		for corner in corners:
			var cell := Vector2i(_column_starts[corner.x], _row_starts[corner.y])
			points.append(Vector2(origin.x + cell.x, origin.z + cell.y))
		loops.append(points)
	return loops


## Follows the boundary sides from `first` back to it, taking each side out of
## `leaving`, and returns the corners where the direction changes.
func _trace(leaving: Dictionary, first: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [first]
	var at := first
	var heading := Vector2i(1, 0)
	while true:
		var options: Array = leaving[at]
		var next: Vector2i = options[0]
		if options.size() > 1:
			# Prefer a right turn (toward the owned side), then straight on.
			var right := Vector2i(-heading.y, heading.x)
			for wanted in [right, heading]:
				if options.has(at + wanted):
					next = at + wanted
					break
		options.erase(next)
		if options.is_empty():
			leaving.erase(at)
		heading = next - at
		at = next
		if at == first:
			break
		path.append(at)
	var corners: Array[Vector2i] = []
	var count := path.size()
	for i in count:
		var before := path[(i + count - 1) % count]
		var after := path[(i + 1) % count]
		if path[i] - before != after - path[i]:
			corners.append(path[i])
	return corners


## JSON-safe state for a save: the plot counts it was cut into ([across,
## down]), the owned plots as [column, row] pairs row by row, and how many
## were bought.
func to_snapshot() -> Dictionary:
	var owned := []
	for plot in owned_plots():
		owned.append([plot.x, plot.y])
	return {"plot_counts": [plots.x, plots.y], "owned": owned, "bought": bought}


## Why a to_snapshot() dictionary cannot be loaded on `site`, or "".
static func problem(data: Dictionary, site: SiteDefinition) -> String:
	return LandPlots.for_site(site).snapshot_problem(data)


## Why a to_snapshot() dictionary cannot be loaded into these plots, or "".
func snapshot_problem(data: Dictionary) -> String:
	for key in SNAPSHOT_KEYS:
		if not data.has(key):
			return "missing '%s'" % key
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	if not _counts_match(data["plot_counts"]):
		return "the land was cut into another number of plots than the site's"
	if not WholeNumber.is_whole(data["bought"]) or int(data["bought"]) < 0:
		return "'bought' must be a whole number from 0"
	return _owned_problem(data["owned"])


## Whether a snapshot's "plot_counts" value is this site's [across, down].
func _counts_match(counts: Variant) -> bool:
	if typeof(counts) != TYPE_ARRAY or counts.size() != 2:
		return false
	for i in 2:
		if not WholeNumber.is_whole(counts[i]) or int(counts[i]) != plots[i]:
			return false
	return true


## Why a snapshot's "owned" value is not a list of [column, row] pairs on the
## site, or "".
func _owned_problem(owned: Variant) -> String:
	if typeof(owned) != TYPE_ARRAY:
		return "'owned' is not a list"
	for entry in owned:
		var pair: bool = typeof(entry) == TYPE_ARRAY and entry.size() == 2
		if not pair or not WholeNumber.is_whole(entry[0]) or not WholeNumber.is_whole(entry[1]):
			return "an owned plot is not a [column, row] pair"
		if not in_site(Vector2i(int(entry[0]), int(entry[1]))):
			return "owned plot %s is off the site" % [entry]
	return ""


## Why the built cells of `grid` (floor, walls, objects) do not all stand on
## land a to_snapshot() dictionary `data` owns, or "". A wall needs an owned
## cell on one side, as in edit_problem().
static func grid_problem(data: Dictionary, site: SiteDefinition, grid: BuildGrid) -> String:
	var land := LandPlots.for_site(site)
	if not land.from_snapshot(data):
		return "it was refused (see the error log)"
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if land.owns_cell(cell):
				continue
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE or grid.object_at(cell) != 0:
				return "cell %s is built on land the player does not own" % cell
			for side in 4:
				var beyond := cell + BuildGrid.SIDE_STEP[side]
				if grid.has_wall(cell, side) and not land.owns_cell(beyond):
					return "a wall at cell %s stands on land the player does not own" % cell
	return ""


## Loads a to_snapshot() dictionary (one through JSON too), replacing what is
## owned and bought. Pushes an error and returns false, changing nothing, when
## it is malformed or was saved for another plot layout or grid.
func from_snapshot(data: Dictionary) -> bool:
	var why := snapshot_problem(data)
	if why != "":
		push_error("LandPlots.from_snapshot: %s" % why)
		return false
	_owned.fill(0)
	for entry in data["owned"]:
		_owned[int(entry[0]) + int(entry[1]) * plots.x] = 1
	bought = int(data["bought"])
	changed.emit()
	return true
