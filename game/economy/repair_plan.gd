class_name RepairPlan
extends RefCounted
## Whether a passenger can still get through the terminal, and the build edits
## that would let one through again, for the rescue grant (ruling going-broke-a-
## one-off-rescue-grant-when-the-airport-is-stuck).
##
## A working path is the walk a new passenger takes: from the first entrance
## (PassengerSim spawns there) to a usable check-in desk's service cell, on to
## a usable scanner's lane, through its passage, and to an open exit. Each leg
## is a BuildGrid.find_path() route, the same A* the passengers walk.
##
## make() plans the repair leg by leg, desk then scanner then exit, on a copy of
## the grid. Each leg runs one cheapest-price search from where the last leg
## ended (Dijkstra over grid cells, four steps per cell): a step the passengers
## can already take costs 0, a step onto a cell with no floor costs the floor's
## price, and a step through a plain or glass wall takes the wall down, which
## costs no money (BuildGrid lets such a wall be removed, and removing pays a
## refund) and is ranked just above an open step, so between routes of the
## same price the plan keeps the player's walls. A wall that saves money is
## taken down, but never the security divider (ruling rescue-grant-repair-
## price-never-removes-the-security-divider-other-walls-may-come-down-when-
## cheaper): before each leg the cells passengers can already walk are marked
## landside (joined to an entrance or a desk or scanner service cell) or
## airside (joined to a scanner's passage end or an open exit), and a landside
## leg (desk, scanner) never steps into an airside cell or floors a cell open
## to one; the exit leg does the same the other way. A cell joined to both, as
## when a scanner is gone and its gap is open, is free to both. A new scanner
## must lead out of landside. The leg then takes the cheapest
## of: a standing desk, scanner or exit the search reached, or a new one,
## priced as its object plus the floor its footprint (and a scanner's exit
## cell, or a door's own cell) still needs. A new piece goes where the
## search reaches first, in its settle order, trying facings 0 to 3, so the
## same grid always gives the same plan. With no entrance, every place an
## entrance may stand (a landside Toon door in a shell, else any edge cell
## facing in) starts the desk leg's search at its own price, so the entrance
## and desk are chosen together. Each choice is
## built on the copy with DoorPlacement's rules and checked with the route
## test; a choice that fails is undone edit by edit and the next one tried.
## When a later leg finds no choice that works, the plan backtracks: it undoes
## the earlier leg's choice and tries that leg's next one (MAX_TRIES choices
## per leg, MAX_ATTEMPTS built in all, so a plan always ends).
##
## Prices come from BuildTransaction. least_balance() is the money the plan
## needs at the start when its edits are bought one by one in order, each
## refund paying toward the later edits. The plan takes the cheapest choice
## that works per leg, one leg at a time, so it is not always the cheapest
## repair there is; it never adds seats or rooms, and it never removes or
## moves an object the player built (walls, as above, it may take down).

enum Leg { DESK, SCANNER, EXIT }

## The piece each leg needs.
const LEG_DEFS: Array[StringName] = [&"checkin_desk", &"security_scanner", &"exit_door"]
## New-piece candidates gathered per leg, and how many choices are built
## before the leg gives up.
const MAX_CANDIDATES := 24
const MAX_TRIES := 12
const MAX_ATTEMPTS := 48
const UNREACHED := 1 << 30
## Cell sides, as flags: LAND | AIR is a cell joined to both.
const LAND := 1
const AIR := 2
## Search prices are money times SCALE, plus 1 per wall taken down.
const SCALE := 64

## The edits to apply in order, each priced against the grid as it was when
## make() ran. Empty when the path already works.
var edits: Array[BuildEdit] = []
## False when no repair was found (the error has been pushed).
var ok := false

var _grid: BuildGrid
var _layout := TerminalLayout.new()
var _shell: ShellDefinition
var _floor_price := -1
## Per cell index: search price, the cell it was reached from (-1 at a
## source), and the index of the source it came from.
var _dist := PackedInt32Array()
var _prev := PackedInt32Array()
var _src := PackedInt32Array()
## Cells in the order the search settled them.
var _order: Array[Vector2i] = []
## Cells a new piece may not cover: the walk planned so far.
var _kept := {}
## Cells beyond a standing door's back edge, which must stay without floor.
var _no_floor := {}
## Interaction cells of standing objects, and cells some lane already holds.
var _reserved := {}
var _lane_cells := {}
## Walkable cell -> LAND, AIR or both; the side a leg may not enter; whether
## any airside exists.
var _region := {}
var _forbidden := 0
var _has_air := false
var _attempts := 0


## Whether a new passenger can walk entrance, desk, scanner and exit on `grid`
## as `layout` (rebuilt from that grid) describes it.
static func has_working_path(grid: BuildGrid, layout: TerminalLayout) -> bool:
	if layout.entrances.is_empty():
		return false
	var door := layout.door_cell(grid, layout.entrances[0])
	return can_finish(grid, layout, [door] as Array[Vector2i], Leg.DESK)


## Whether a walker standing on one of `starts` can still use, in journey
## order, the pieces from `leg` on: a desk, a scanner, then an exit.
static func can_finish(
	grid: BuildGrid, layout: TerminalLayout, starts: Array[Vector2i], leg: int
) -> bool:
	var here := starts
	for next_leg in range(leg, Leg.size()):
		here = _next_cells(grid, layout, here, next_leg)
		if here.is_empty():
			return false
	return true


## The least balance that buys `edits` one by one in order on `grid`: each
## edit's price (BuildTransaction.quote()) must be there when it is bought,
## and a refund it earns pays toward the edits after it.
## PriceTable.NO_PRICE when an edit has no price.
static func least_balance(grid: BuildGrid, plan_edits: Array[BuildEdit]) -> int:
	var least := 0
	var spent := 0
	for edit in plan_edits:
		var quote := BuildTransaction.quote(grid, edit)
		if not quote.priced:
			return PriceTable.NO_PRICE
		least = maxi(least, spent + maxi(quote.net(), 0))
		spent += quote.net()
	return least


## The plan for `grid` (left unchanged), inside `shell` when there is one.
static func make(grid: BuildGrid, shell: ShellDefinition = null) -> RepairPlan:
	var plan := RepairPlan.new()
	plan._shell = shell
	plan._grid = BuildGrid.new(grid.size, grid.origin)
	if not plan._grid.from_snapshot(grid.to_snapshot()):
		push_error("RepairPlan: the grid could not be copied")
		return plan
	plan._layout.rebuild(plan._grid)
	plan.ok = plan._plan()
	return plan


## Where a leg's walkers stand once the leg is done: a desk's service cell,
## a scanner's passage end, an exit's door cell. Each reached from `starts`.
static func _next_cells(
	grid: BuildGrid, layout: TerminalLayout, starts: Array[Vector2i], leg: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for target in _targets(grid, layout, leg):
		for start in starts:
			if start == target[0] or not grid.find_path(start, target[0]).is_empty():
				out.append(target[1])
				break
	return out


## The standing pieces a leg can use, as [cell walked to, cell left from].
static func _targets(grid: BuildGrid, layout: TerminalLayout, leg: int) -> Array:
	var out := []
	match leg:
		Leg.DESK:
			for desk in layout.desks:
				if layout.is_usable(desk):
					out.append([layout.lanes[desk][0], layout.lanes[desk][0]])
		Leg.SCANNER:
			for scanner in layout.scanners:
				if layout.is_usable(scanner):
					var passage: Array = layout.passages[scanner]
					out.append([layout.lanes[scanner][0], passage.back()])
		Leg.EXIT:
			for door in layout.open_exits(grid):
				var cell := layout.door_cell(grid, door)
				out.append([cell, cell])
	return out


func _plan() -> bool:
	if has_working_path(_grid, _layout):
		return true
	var sources := []
	if _layout.entrances.is_empty():
		sources = _door_sources(&"entrance_door")
	else:
		var door := _layout.door_cell(_grid, _layout.entrances[0])
		sources = [{"cell": door, "cost": 0, "edits": [] as Array[BuildEdit]}]
		_kept[door] = true
	if not _solve(Leg.DESK, sources):
		push_error("RepairPlan: found no repair that gives a working path (%d tried)" % _attempts)
		return false
	return true


## Repairs `leg` and every leg after it, backtracking over this leg's
## choices when the later legs fail. True when a working path stands.
func _solve(leg: int, sources: Array) -> bool:
	if leg == Leg.size():
		return has_working_path(_grid, _layout)
	_refresh_sets(leg)
	_search(sources)
	var choices := _standing_choices(leg)
	choices.append_array(_new_choices(leg, sources))
	choices.sort_custom(_cheaper)
	choices = choices.slice(0, MAX_TRIES)
	# The search is redone by the next leg, so each walk is taken from it now.
	for choice in choices:
		var source: Dictionary = sources[_src[_index(choice["reach"])]]
		var wanted: Array[BuildEdit] = []
		wanted.append_array(source["edits"])
		wanted.append_array(_walk_edits(choice["reach"]))
		wanted.append_array(choice["piece"])
		choice["wanted"] = wanted
		choice["walk"] = _walk_cells(choice["reach"])
		if source.has("door"):
			choice["walk"][source["door"]] = true
	for choice in choices:
		if _attempts >= MAX_ATTEMPTS:
			return false
		_attempts += 1
		var kept := _kept.duplicate()
		var mark := edits.size()
		var undo: Array[BuildEdit] = []
		if not _try(choice, leg, undo):
			continue
		var next: Array = [{"cell": choice["next"], "cost": 0, "edits": [] as Array[BuildEdit]}]
		if _solve(leg + 1, next):
			return true
		_undo(undo)
		_kept = kept
		edits.resize(mark)
	return false


static func _cheaper(a: Dictionary, b: Dictionary) -> bool:
	if a["cost"] != b["cost"]:
		return a["cost"] < b["cost"]
	return a["rank"] < b["rank"]


func _refresh_sets(leg: int) -> void:
	_label_regions()
	_forbidden = LAND if leg == Leg.EXIT else AIR
	_no_floor.clear()
	for way in DoorPlacement.ways_out(_grid):
		_no_floor[way[0] + way[1]] = true
	_reserved.clear()
	for id in _grid.object_ids():
		var spot := _grid.interaction_cell(id)
		if spot != BuildObjectDef.NO_CELL:
			_reserved[spot] = true
	_lane_cells.clear()
	for lane in _layout.lanes.values():
		for cell in lane:
			_lane_cells[cell] = true


## Marks each walkable cell LAND, AIR or both (see the class notes).
func _label_regions() -> void:
	_region.clear()
	var land: Array[Vector2i] = []
	var air: Array[Vector2i] = []
	for door in _layout.entrances:
		land.append(_layout.door_cell(_grid, door))
	for station in _layout.desks + _layout.scanners:
		var spot := _grid.interaction_cell(station)
		if spot != BuildObjectDef.NO_CELL:
			land.append(spot)
	for scanner in _layout.scanners:
		var passage: Array = _layout.passages[scanner]
		if not passage.is_empty():
			air.append(passage.back())
	for door in _layout.open_exits(_grid):
		air.append(_layout.door_cell(_grid, door))
	_flood(land, LAND)
	_flood(air, AIR)
	_has_air = not air.is_empty()


func _flood(seeds: Array[Vector2i], side: int) -> void:
	var todo := seeds.duplicate()
	var seen := {}
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		if seen.has(cell) or not _grid.is_walkable(cell):
			continue
		seen[cell] = true
		_region[cell] = _region.get(cell, 0) | side
		for step in BuildGrid.SIDE_STEP:
			if _grid.in_bounds(cell + step) and _grid.can_route(cell, cell + step):
				todo.append(cell + step)


## Whether `cell` lies on the side the current leg may not reach: in it, or,
## for a cell with no floor yet, open to it (floor there would join it).
func _off_side(cell: Vector2i) -> bool:
	if _region.get(cell, 0) == _forbidden:
		return true
	if _grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return false
	for side in 4:
		var near := cell + BuildGrid.SIDE_STEP[side]
		if _region.get(near, 0) != _forbidden:
			continue
		var wall := _grid.wall_kind(cell, side)
		if wall == BuildGrid.WallKind.NONE or wall == BuildGrid.WallKind.DOOR:
			return true
	return false


func _standing_choices(leg: int) -> Array:
	var out := []
	for target in _targets(_grid, _layout, leg):
		var reach: Vector2i = target[0]
		var cost := _dist[_index(reach)]
		if cost < UNREACHED:
			var none: Array[BuildEdit] = []
			out.append({"cost": cost, "rank": -1, "reach": reach, "next": target[1], "piece": none})
	return out


func _new_choices(leg: int, sources: Array) -> Array:
	var def_id := LEG_DEFS[leg]
	if BuildCatalog.is_door(def_id):
		return _door_choices(def_id)
	var def := BuildCatalog.get_def(def_id)
	var price := _object_price(def_id)
	var out := []
	for cell in _order:
		if out.size() >= MAX_CANDIDATES:
			break
		if _grid.object_at(cell) != 0 or _reserved.has(cell) or _lane_cells.has(cell):
			continue
		var walk := _walk_cells(cell)
		var source: Dictionary = sources[_src[_index(cell)]]
		if source.has("door"):
			# A new entrance: its own cell and service cell are taken too.
			if cell == source["cell"]:
				continue
			walk[source["door"]] = true
			walk[source["cell"]] = true
		for facing in 4:
			var anchor := cell - def.interaction_cell(Vector2i.ZERO, facing)
			var cells := def.footprint(anchor, facing)
			var next := cell
			if def.walk_through:
				var back := BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)
				next = cell + back * (def.size.y + 1)
				if _has_air and _region.get(next, 0) == LAND:
					continue
			if not _free_for_piece(cells, walk, not def.walk_through):
				continue
			if def.walk_through:
				if not _free_for_piece([next] as Array[Vector2i], walk, false):
					continue
				cells.append(next)
			var piece := _floors(cells)
			piece.append(BuildEdit.place_object(def_id, anchor, facing))
			var cost := _dist[_index(cell)] + (price + _floors_price(piece)) * SCALE
			out.append(
				{"cost": cost, "rank": out.size(), "reach": cell, "next": next, "piece": piece}
			)
	return out


## New exits: where one may stand, reached through its service cell.
func _door_choices(def_id: StringName) -> Array:
	var out := []
	for source in _door_sources(def_id, true):
		var reach: Vector2i = source["cell"]
		if _dist[_index(reach)] >= UNREACHED:
			continue
		var door: Vector2i = source["door"]
		var piece: Array[BuildEdit] = source["door_edits"]
		if not _free_for_piece([door] as Array[Vector2i], _walk_cells(reach), true):
			continue
		var cost: int = _dist[_index(reach)] + source["door_cost"] * SCALE
		out.append({"cost": cost, "rank": out.size(), "reach": reach, "next": door, "piece": piece})
	out.sort_custom(_cheaper)
	return out.slice(0, MAX_CANDIDATES)


## Every place a `def_id` door may stand, as a search source at its service
## cell: {cell, cost and edits (the door and the floor of both cells), door,
## door_cost and door_edits (the door and the floor of its own cell, for an
## exit whose service cell the walk to it floors)}. With `reached`, only
## spots whose service cell the last search reached.
func _door_sources(def_id: StringName, reached := false) -> Array:
	var spots := []
	if _shell != null:
		var kind := ShellDoorConnection.kind_for(def_id)
		for connection in _shell.connections:
			if connection.kind == kind:
				spots.append([connection.cell, connection.facing])
	else:
		for y in _grid.size.y:
			for x in _grid.size.x:
				for facing in 4:
					spots.append([Vector2i(x, y), facing])
	var price := _object_price(def_id)
	var out := []
	for spot in spots:
		var door: Vector2i = spot[0]
		var facing: int = spot[1]
		var inside := door + TerminalLayout.front_of(facing)
		if not _door_spot_free(door, inside, facing):
			continue
		if reached and _dist[_index(inside)] >= UNREACHED:
			continue
		var door_edits := _floors([door] as Array[Vector2i])
		door_edits.append(BuildEdit.place_object(def_id, door, facing))
		var edits_here := _floors([inside] as Array[Vector2i])
		edits_here.append_array(door_edits)
		(
			out
			. append(
				{
					"cell": inside,
					"cost": (price + _floors_price(edits_here)) * SCALE,
					"edits": edits_here,
					"door": door,
					"door_cost": price + _floors_price(door_edits),
					"door_edits": door_edits,
				}
			)
		)
	return out


func _door_spot_free(door: Vector2i, inside: Vector2i, facing: int) -> bool:
	if not _grid.in_bounds(door) or not _grid.in_bounds(inside):
		return false
	for cell in [door, inside]:
		if _grid.object_at(cell) != 0 or _reserved.has(cell) or _no_floor.has(cell):
			return false
	var out := door + DoorPlacement.back_step(facing)
	if _grid.in_bounds(out) and _grid.floor_at(out) != BuildGrid.FLOOR_NONE:
		return false
	var wall := _grid.wall_kind(door, BuildGrid.SIDE_STEP.find(out - door))
	return wall == BuildGrid.WallKind.NONE or wall == BuildGrid.WallKind.PLAIN


## Whether a new piece may cover `cells`: inside the grid, nothing standing or
## served there, not on the walk planned so far or the one to reach it, and
## with `sided`, not on the side the leg may not reach.
func _free_for_piece(cells: Array[Vector2i], walk: Dictionary, sided: bool) -> bool:
	for cell in cells:
		if not _grid.in_bounds(cell) or _grid.object_at(cell) != 0:
			return false
		if sided and _off_side(cell):
			return false
		if _reserved.has(cell) or _no_floor.has(cell) or _kept.has(cell) or walk.has(cell):
			return false
	return true


## Builds a choice's edits on the copy (the source's own, the walk to it and
## the piece). Keeps them, with what takes them back in `undo`, when every
## leg up to `leg` then works and leaves from the choice's cell; otherwise
## undoes them and returns false.
func _try(choice: Dictionary, leg: int, undo: Array[BuildEdit]) -> bool:
	var done: Array[BuildEdit] = []
	var built := true
	for edit in choice["wanted"]:
		if not _build(edit, done, undo):
			built = false
			break
	_layout.rebuild(_grid)
	if built and _leg_works(leg, choice["next"]):
		edits.append_array(done)
		for cell in choice["walk"]:
			_kept[cell] = true
		_kept[choice["next"]] = true
		return true
	_undo(undo)
	return false


## Takes back built edits, newest first, and rebuilds the layout.
func _undo(undo: Array[BuildEdit]) -> void:
	for i in range(undo.size() - 1, -1, -1):
		if not _grid.apply(undo[i]).ok:
			push_error("RepairPlan: could not undo a tried repair edit")
	undo.clear()
	_layout.rebuild(_grid)


## Applies one edit the way the build tools would (DoorPlacement.check() and
## edits_for()), adding what was applied to `done` and the edit that takes it
## back to `undo`. False on a refusal.
func _build(edit: BuildEdit, done: Array[BuildEdit], undo: Array[BuildEdit]) -> bool:
	if not DoorPlacement.check(_grid, edit, _shell).ok:
		return false
	for step in DoorPlacement.edits_for(_grid, edit):
		var before := 0
		if step.kind == BuildEdit.Kind.REMOVE_WALL:
			before = _grid.wall_kind(step.cell, step.side)
		var result := _grid.apply(step)
		if not result.ok:
			return false
		done.append(step)
		match step.kind:
			BuildEdit.Kind.PAINT_FLOOR:
				undo.append(BuildEdit.remove_floor(step.cell))
			BuildEdit.Kind.REMOVE_WALL:
				undo.append(BuildEdit.place_wall(step.cell, step.side, before))
			BuildEdit.Kind.PLACE_OBJECT:
				undo.append(BuildEdit.remove_object(result.object_id))
	return true


## Whether the legs up to `leg` now work from the first entrance and the last
## one can end at `next`.
func _leg_works(leg: int, next: Vector2i) -> bool:
	if _layout.entrances.is_empty():
		return false
	var here: Array[Vector2i] = [_layout.door_cell(_grid, _layout.entrances[0])]
	for each in range(Leg.DESK, leg + 1):
		here = _next_cells(_grid, _layout, here, each)
	return here.has(next)


## Cheapest search price from `sources` to every cell.
func _search(sources: Array) -> void:
	var count := _grid.size.x * _grid.size.y
	_dist.resize(count)
	_dist.fill(UNREACHED)
	_prev.resize(count)
	_prev.fill(-1)
	_src.resize(count)
	_src.fill(-1)
	_order.clear()
	var heap: Array[Vector2i] = []
	for i in sources.size():
		var at := _index(sources[i]["cell"])
		if sources[i]["cost"] < _dist[at]:
			_dist[at] = sources[i]["cost"]
			_src[at] = i
			_push(heap, Vector2i(_dist[at], at))
	var settled := PackedByteArray()
	settled.resize(count)
	while not heap.is_empty():
		var top := _pop(heap)
		if settled[top.y] == 1 or top.x > _dist[top.y]:
			continue
		settled[top.y] = 1
		var cell := _cell(top.y)
		_order.append(cell)
		for step in BuildGrid.SIDE_STEP:
			var price := _step_price(cell, cell + step)
			if price < 0:
				continue
			var at := _index(cell + step)
			if top.x + price < _dist[at]:
				_dist[at] = top.x + price
				_prev[at] = top.y
				_src[at] = _src[top.y]
				_push(heap, Vector2i(_dist[at], at))


## The price of stepping from `from` to the neighbour `to`, or -1 when the
## step cannot be made. A cell with an object is only crossed the way the
## passengers already can (BuildGrid.can_route()).
func _step_price(from: Vector2i, to: Vector2i) -> int:
	if not _grid.in_bounds(to):
		return -1
	if _grid.can_route(from, to):
		return 0
	if _off_side(to):
		return -1
	if _grid.object_at(from) != 0 or _grid.object_at(to) != 0 or _no_floor.has(to):
		return -1
	var side := BuildGrid.SIDE_STEP.find(to - from)
	var price := 0
	if _grid.has_wall(from, side) and _grid.wall_kind(from, side) != BuildGrid.WallKind.DOOR:
		if not _grid.validate(BuildEdit.remove_wall(from, side)).ok:
			return -1
		price = 1
	if _grid.floor_at(to) == BuildGrid.FLOOR_NONE:
		price += _price_of_floor(to) * SCALE
	return price


## The cells from the search source to `cell`, as a set.
func _walk_cells(cell: Vector2i) -> Dictionary:
	var out := {}
	var at := _index(cell)
	while at != -1:
		out[_cell(at)] = true
		at = _prev[at]
	return out


## The floor and wall removals that open the searched walk to `cell`.
func _walk_edits(cell: Vector2i) -> Array[BuildEdit]:
	var steps: Array[Vector2i] = []
	var at := _index(cell)
	while at != -1:
		steps.push_front(_cell(at))
		at = _prev[at]
	var out: Array[BuildEdit] = []
	for i in range(1, steps.size()):
		var from := steps[i - 1]
		var side := BuildGrid.SIDE_STEP.find(steps[i] - from)
		if _grid.has_wall(from, side) and _grid.wall_kind(from, side) != BuildGrid.WallKind.DOOR:
			out.append(BuildEdit.remove_wall(from, side))
		if _grid.floor_at(steps[i]) == BuildGrid.FLOOR_NONE:
			out.append(_paint(steps[i]))
	return out


## Floor for each of `cells` that has none.
func _floors(cells: Array[Vector2i]) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for cell in cells:
		if _grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			out.append(_paint(cell))
	return out


func _floors_price(piece: Array[BuildEdit]) -> int:
	var total := 0
	for edit in piece:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			total += _price_of_floor(edit.cell)
	return total


static func _paint(cell: Vector2i) -> BuildEdit:
	return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)


## What new floor on a bare cell costs (BuildTransaction.quote()), taken once.
func _price_of_floor(bare: Vector2i) -> int:
	if _floor_price < 0:
		_floor_price = maxi(BuildTransaction.quote(_grid, _paint(bare)).net(), 0)
	return _floor_price


func _object_price(def_id: StringName) -> int:
	var edit := BuildEdit.place_object(def_id, Vector2i.ZERO, 0)
	return maxi(BuildTransaction.quote(_grid, edit).net(), 0)


func _index(cell: Vector2i) -> int:
	return cell.y * _grid.size.x + cell.x


func _cell(index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % _grid.size.x, index / _grid.size.x)


## A binary min-heap of (price, cell index); ties go to the lower index.
static func _push(heap: Array[Vector2i], item: Vector2i) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if not _before(heap[i], heap[parent]):
			break
		var swap := heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _pop(heap: Array[Vector2i]) -> Vector2i:
	var top := heap[0]
	var last: Vector2i = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var best := i
		for child in [2 * i + 1, 2 * i + 2]:
			if child < heap.size() and _before(heap[child], heap[best]):
				best = child
		if best == i:
			break
		var swap := heap[best]
		heap[best] = heap[i]
		heap[i] = swap
		i = best
	return top


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
