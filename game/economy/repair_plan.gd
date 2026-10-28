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
## landside or airside from seeds (entrances and desk and scanner service
## cells landside; scanner passage ends and open exits airside). The marking
## spreads one step at a time over open steps with no wall of any kind on the
## edge, so it never crosses a wall, a door wall in the divider or a scanner,
## and a cell both sides reach (an open scanner gap, an exit beside the hall)
## takes the side that reaches it first, landside on a tie. A landside leg
## (desk, scanner) never steps into an airside cell or floors a cell open to
## one; the exit leg does the same the other way. A new scanner must lead out
## of landside. The grid stores no landside or airside zone (every floor cell
## carries the one terminal zone), so the sides are worked out this way.
##
## The leg then takes the cheapest of: a standing desk, scanner or exit the
## search reached, or a new one, priced as its object plus the floor its
## footprint (and a scanner's exit cell, or a door's own cell) still needs. A
## new desk or scanner also needs its staff spot (StaffSpots) free and floored,
## and joined by floor to the walk (_spot_link()), and that floor is part of
## its price. A standing desk or scanner whose spot
## is blocked (StaffSpots.blocked(), only in an old save) or that staff cannot
## reach from an entrance (StaffSpots.unreachable()) is no working
## station, and every standing station's spot is kept clear of new pieces, as
## an interaction cell is. A new piece goes where the
## search reaches first, in its settle order, trying facings 0 to 3, so the
## same grid always gives the same plan. With no entrance, every place an
## entrance may stand (a landside Toon door in a shell, else any edge cell
## facing in) starts the desk leg's search at its own price, so the entrance
## and desk are chosen together. Each choice is
## built on the copy with DoorPlacement's rules and checked with the route
## test; a choice that fails is undone edit by edit and the next one tried.
## When a later leg finds no choice that works, the plan backtracks: it undoes
## the earlier leg's choice and tries that leg's next one (MAX_TRIES choices
## per leg, MAX_ATTEMPTS built in all, so a plan always ends). Running out of
## those caps is not "cannot be repaired": ok stays false and fallback_price
## is set (see _fallback_price()), and the rescue grant pays that instead. Only
## a search that tried every choice without a cap is an error.
##
## The search builds without the staff reach rule (BuildGrid.check_staff_reach)
## and counts a station staff cannot reach yet, since a later leg's floor may
## open the way. A finished plan is then ordered floors and walls first,
## objects after, and must build edit by edit on the original grid under every
## rule, reach included, with every station it uses staffable; one that does
## not is no repair and the search goes on to the next choice, within the caps.
##
## Prices come from BuildTransaction. least_balance() is the money the plan
## needs at the start when its edits are bought one by one in order, each
## refund paying toward the later edits. The plan takes the cheapest choice
## that works per leg, one leg at a time, so it is not always the cheapest
## repair there is; it never adds seats or rooms, and it never removes or
## moves an object the player built (walls, as above, it may take down).

enum Leg { DESK, SCANNER, EXIT }
## Which standing desks and scanners a route may use: any; any whose staff
## spot is not blocked (the search, which judges reach on the finished plan);
## or only those staff can work (spot neither blocked nor out of reach).
enum Staffing { ANY, NOT_BLOCKED, STAFFABLE }

## The piece each leg needs.
const LEG_DEFS: Array[StringName] = [&"checkin_desk", &"security_scanner", &"exit_door"]
## New-piece candidates gathered per leg, and how many choices are built
## before the leg gives up.
const MAX_CANDIDATES := 24
const MAX_TRIES := 12
const MAX_ATTEMPTS := 48
const UNREACHED := 1 << 30
## The side each walkable cell is marked with.
const LAND := 1
const AIR := 2
## Search prices are money times SCALE, plus 1 per wall taken down.
const SCALE := 64

## The caps in use; tests lower or lift them and put them back.
static var max_candidates := MAX_CANDIDATES
static var max_tries := MAX_TRIES
static var max_attempts := MAX_ATTEMPTS

## The edits to apply in order, each priced against the grid as it was when
## make() ran. Empty when the path already works.
var edits: Array[BuildEdit] = []
## False when no repair was found.
var ok := false
## With ok false: what a repair is taken to cost when the caps ran out before
## one was found, or -1 when every choice was tried (the error was pushed).
var fallback_price := -1

var _grid: BuildGrid
## The snapshot of the grid make() was given, for _failing_leg().
var _source := {}
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
## Interaction cells and staff spots of standing objects, and cells some lane
## already holds.
var _reserved := {}
var _lane_cells := {}
## Cells staff can walk to from an entrance (StaffSpots.reach()), for
## _spot_link().
var _staff_reach := {}
## Walkable cell -> LAND, AIR or both; the side a leg may not enter; whether
## any airside exists.
var _region := {}
var _forbidden := 0
var _has_air := false
var _attempts := 0
## The leg a failed finished plan sends the search back to (_failing_leg()),
## or -1; and the size of `edits` when each leg's current choice began.
var _bad_leg := -1
var _marks: Array[int] = [0, 0, 0]
## Set when a cap cut the choices short.
var _capped := false


## Whether a new passenger can walk entrance, desk, scanner and exit on `grid`
## as `layout` (rebuilt from that grid) describes it. With `staffed` false, a
## desk or scanner staff can never work still counts, so AirportGate can tell
## a missing way from a staff spot problem.
static func has_working_path(grid: BuildGrid, layout: TerminalLayout, staffed := true) -> bool:
	if layout.entrances.is_empty():
		return false
	var door := layout.door_cell(grid, layout.entrances[0])
	var staffing := Staffing.STAFFABLE if staffed else Staffing.ANY
	return can_finish(grid, layout, [door] as Array[Vector2i], Leg.DESK, staffing)


## Whether a walker standing on one of `starts` can still use, in journey
## order, the pieces from `leg` on: a desk, a scanner, then an exit.
static func can_finish(
	grid: BuildGrid,
	layout: TerminalLayout,
	starts: Array[Vector2i],
	leg: int,
	staffing := Staffing.STAFFABLE
) -> bool:
	var here := starts
	for next_leg in range(leg, Leg.size()):
		here = _next_cells(grid, layout, here, next_leg, staffing)
		if here.is_empty():
			return false
	return true


## The least balance that buys `edits` one by one in order on `grid`: each
## edit's price (BuildTransaction.quote()) must be there when it is bought,
## and a refund it earns pays toward the edits after it. A cell painted again
## before its floor is taken up is charged once.
## PriceTable.NO_PRICE when an edit has no price.
static func least_balance(grid: BuildGrid, plan_edits: Array[BuildEdit]) -> int:
	var least := 0
	var spent := 0
	var painted := {}
	for edit in plan_edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			if painted.has(edit.cell):
				continue
			painted[edit.cell] = true
		elif edit.kind == BuildEdit.Kind.REMOVE_FLOOR:
			painted.erase(edit.cell)
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
	plan._source = grid.to_snapshot()
	if not plan._grid.from_snapshot(plan._source):
		push_error("RepairPlan: the grid could not be copied")
		return plan
	# The search builds leg by leg, so a piece may stand on a corridor until a
	# later leg's floor goes round it; _failing_leg() judges staff reach on the
	# finished plan, floors and walls first.
	plan._grid.check_staff_reach = false
	plan._layout.rebuild(plan._grid)
	plan.ok = plan._plan()
	return plan


## Where a leg's walkers stand once the leg is done: a desk's service cell,
## a scanner's passage end, an exit's door cell. Each reached from `starts`.
static func _next_cells(
	grid: BuildGrid,
	layout: TerminalLayout,
	starts: Array[Vector2i],
	leg: int,
	staffing := Staffing.STAFFABLE
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for target in _targets(grid, layout, leg, staffing):
		for start in starts:
			if start == target[0] or not grid.find_path(start, target[0]).is_empty():
				out.append(target[1])
				break
	return out


## The standing pieces a leg can use, as [cell walked to, cell left from]. A
## desk or scanner whose staff spot is blocked (a layout saved before spots)
## or out of staff's reach is left out as `staffing` says: StaffSim
## never staffs it, so no passenger gets through it.
static func _targets(
	grid: BuildGrid, layout: TerminalLayout, leg: int, staffing := Staffing.STAFFABLE
) -> Array:
	var out := []
	match leg:
		Leg.DESK:
			for desk in layout.desks:
				if layout.is_usable(desk) and _staffed_enough(grid, layout, desk, staffing):
					out.append([layout.lanes[desk][0], layout.lanes[desk][0]])
		Leg.SCANNER:
			for scanner in layout.scanners:
				if layout.is_usable(scanner) and _staffed_enough(grid, layout, scanner, staffing):
					var passage: Array = layout.passages[scanner]
					out.append([layout.lanes[scanner][0], passage.back()])
		Leg.EXIT:
			for door in layout.open_exits(grid):
				var cell := layout.door_cell(grid, door)
				out.append([cell, cell])
	return out


## Whether `station` passes `staffing`. Its primary post decides
## (StaffPosts): a security lane's officer spot, else its StaffSpots spot. A
## station with no staff spot at all is never staffed, so only ANY lets it
## through.
static func _staffed_enough(
	grid: BuildGrid, layout: TerminalLayout, station: int, staffing: Staffing
) -> bool:
	if staffing == Staffing.ANY:
		return true
	var primary := StaffMember.Slot.PRIMARY
	if StaffPosts.spot(grid, layout, station, primary) == BuildObjectDef.NO_CELL:
		return false
	if StaffPosts.blocked(grid, layout, station):
		return false
	return (
		staffing == Staffing.NOT_BLOCKED
		or not StaffPosts.unreachable(grid, layout, station, primary)
	)


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
	if _solve(Leg.DESK, sources):
		edits = _ordered(edits)
		return true
	if _capped:
		push_warning("RepairPlan: no repair within the caps; pricing a conservative one")
		fallback_price = _fallback_price()
	else:
		push_error("RepairPlan: found no repair that gives a working path (%d tried)" % _attempts)
	return false


## The price taken for a repair when the caps ran out: every essential at its
## price, plus floor for every bare cell in the area the terminal's floor
## spans, one cell wider each way (the whole grid when it has no floor). A
## repair buys at most one of each essential, and one that stays in that area
## floors no more cells than this, so the player gets enough and may get more.
func _fallback_price() -> int:
	var total := 0
	for def_id in [&"entrance_door", &"checkin_desk", &"security_scanner", &"exit_door"]:
		total += _object_price(def_id)
	var area := Rect2i()
	for y in _grid.size.y:
		for x in _grid.size.x:
			if _grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				var one := Rect2i(x, y, 1, 1)
				area = one if area.size == Vector2i.ZERO else area.merge(one)
	area = area.grow(1) if area.size != Vector2i.ZERO else Rect2i(Vector2i.ZERO, _grid.size)
	area = area.intersection(Rect2i(Vector2i.ZERO, _grid.size))
	_refresh_sets(Leg.DESK)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if _grid.floor_at(cell) == BuildGrid.FLOOR_NONE and not _no_floor.has(cell):
				total += _price_of_floor(cell)
	return total


## Repairs `leg` and every leg after it, backtracking over this leg's
## choices when the later legs fail. True when a working path stands.
func _solve(leg: int, sources: Array) -> bool:
	if leg == Leg.size():
		_bad_leg = _failing_leg()
		return _bad_leg < 0
	_refresh_sets(leg)
	_search(sources)
	var choices := _standing_choices(leg)
	choices.append_array(_new_choices(leg, sources))
	choices.sort_custom(_cheaper)
	if choices.size() > max_tries:
		_capped = true
	choices = choices.slice(0, max_tries)
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
		for cell in choice.get("link", []):
			choice["walk"][cell] = true
	for choice in choices:
		if _attempts >= max_attempts:
			_capped = true
			return false
		_attempts += 1
		var kept := _kept.duplicate()
		var mark := edits.size()
		_marks[leg] = mark
		var undo: Array[BuildEdit] = []
		if not _try(choice, leg, undo):
			continue
		var next: Array = [{"cell": choice["next"], "cost": 0, "edits": [] as Array[BuildEdit]}]
		if _solve(leg + 1, next):
			return true
		_undo(undo)
		_kept = kept
		edits.resize(mark)
		# A finished plan failed on an earlier leg's piece: no choice here can
		# mend it, so go back to that leg's next choice.
		if _bad_leg >= 0 and _bad_leg < leg:
			return false
		_bad_leg = -1
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
		var stands := StaffSpots.spot_of(_grid, id)
		if stands != BuildObjectDef.NO_CELL:
			_reserved[stands] = true
	# A whole security lane keeps its berth, return route, exit, pickup and
	# officer spots: a new piece there would end the lane.
	for arch in _layout.security_lanes.complete_arches():
		for cell in SecurityLanes.lane_cells(_layout.security_lanes.lane(arch)):
			_reserved[cell] = true
	_lane_cells.clear()
	for lane in _layout.lanes.values():
		for cell in lane:
			_lane_cells[cell] = true
	_staff_reach = StaffSpots.reach(_grid)


## Marks each walkable cell LAND or AIR (see the class notes).
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
	_has_air = not air.is_empty()
	# One breadth-first spread from both sides at once; the first to reach a
	# cell keeps it.
	var queue: Array[Vector2i] = []
	for cell in land:
		if _grid.is_walkable(cell) and not _region.has(cell):
			_region[cell] = LAND
			queue.append(cell)
	for cell in air:
		if _grid.is_walkable(cell) and not _region.has(cell):
			_region[cell] = AIR
			queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			if _region.has(next) or not _grid.in_bounds(next):
				continue
			if _grid.has_wall(cell, side) or not _grid.can_route(cell, next):
				continue
			_region[next] = _region[cell]
			queue.append(next)


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
	for target in _targets(_grid, _layout, leg, Staffing.NOT_BLOCKED):
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
		if out.size() >= max_candidates:
			_capped = true
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
			var footprint := {}
			for each in cells:
				footprint[each] = true
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
			# Passengers may cross the staff spot, so it may lie on the walk.
			var spot := StaffSpots.cell_of(def_id, anchor, facing)
			var link: Array[Vector2i] = []
			if spot != BuildObjectDef.NO_CELL:
				if not _free_for_piece([spot] as Array[Vector2i], {}, false):
					continue
				# Staff must walk to the spot, so floor joins it to the walk.
				link = _spot_link(spot, footprint, walk)
				if link.is_empty():
					continue
				for each in link:
					if not cells.has(each):
						cells.append(each)
			# The walk's own edits floor its cells, and its price has them.
			var bare: Array[Vector2i] = []
			for each in cells:
				if not walk.has(each):
					bare.append(each)
			var piece := _floors(bare)
			piece.append(BuildEdit.place_object(def_id, anchor, facing))
			var cost := _dist[_index(cell)] + (price + _floors_price(piece)) * SCALE
			var choice := {"cost": cost, "rank": out.size(), "reach": cell, "next": next}
			choice["piece"] = piece
			choice["link"] = link
			out.append(choice)
	return out


## The cells from a new station's staff spot to the nearest cell staff reach
## now (_staff_reach) or that `walk` will floor, by open steps around the
## station's `footprint`, the spot first; empty when there is no such way or
## the spot is outside the grid, must stay bare or lies on the side the leg
## may not reach. StaffSpots refuses a spot with no floored neighbour, and
## staff need the way in, so the bare cells on it are floored with the piece.
## A floor island staff cannot reach is passed over, not taken for the way in.
func _spot_link(spot: Vector2i, footprint: Dictionary, walk: Dictionary) -> Array[Vector2i]:
	if not _grid.in_bounds(spot) or _no_floor.has(spot) or _off_side(spot):
		return [] as Array[Vector2i]
	var prev := {spot: spot}
	var queue: Array[Vector2i] = [spot]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for side in 4:
			var next := cell + BuildGrid.SIDE_STEP[side]
			if prev.has(next) or not _grid.in_bounds(next) or footprint.has(next):
				continue
			if _grid.object_at(next) != 0 or _no_floor.has(next) or _off_side(next):
				continue
			var wall := _grid.wall_kind(cell, side)
			if wall != BuildGrid.WallKind.NONE and wall != BuildGrid.WallKind.DOOR:
				continue
			prev[next] = cell
			if walk.has(next) or _staff_reach.has(next):
				var path: Array[Vector2i] = []
				var at := next
				while at != spot:
					at = prev[at]
					path.push_front(at)
				return path
			queue.append(next)
	return [] as Array[Vector2i]


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
	if out.size() > max_candidates:
		_capped = true
	return out.slice(0, max_candidates)


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
		# Staff reach is judged once the whole plan stands (_solve()).
		here = _next_cells(_grid, _layout, here, each, Staffing.NOT_BLOCKED)
	return here.has(next)


## `plan_edits` with every floor and wall edit ahead of the object placements,
## each group in its own order, so a desk or scanner goes down only once the
## floor round it is laid.
static func _ordered(plan_edits: Array[BuildEdit]) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	var placed: Array[BuildEdit] = []
	for edit in plan_edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			placed.append(edit)
		else:
			out.append(edit)
	out.append_array(placed)
	return out


## -1 when the finished plan works: a route runs through desks and scanners
## staff can work (StaffSpots), and the plan builds edit by edit, in _ordered()
## order, on the grid make() was given under the rules a player's clicks meet,
## staff reach included. Otherwise the leg whose choice to try again: the first
## leg with no such station, or the leg that added the edit a rebuild refused.
func _failing_leg() -> int:
	if _layout.entrances.is_empty():
		return Leg.DESK
	var here: Array[Vector2i] = [_layout.door_cell(_grid, _layout.entrances[0])]
	for each in Leg.size():
		here = _next_cells(_grid, _layout, here, each)
		if here.is_empty():
			return each
	var trial := BuildGrid.new(_grid.size, _grid.origin)
	if not trial.from_snapshot(_source):
		return Leg.DESK
	for edit in _ordered(edits):
		if not trial.apply(edit).ok:
			var at := edits.find(edit)
			for each in range(Leg.size() - 1, -1, -1):
				if at >= _marks[each]:
					return each
			return Leg.DESK
	return -1


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
	if not _grid.in_bounds(to) or _off_side(to):
		return -1
	if _grid.can_route(from, to):
		return 0
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
