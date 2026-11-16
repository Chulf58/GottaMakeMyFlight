class_name SideSpurs
extends RefCounted
## Where the west and east spurs run (decision side-spur-move-design-s7-stands-
## carry-lane-x-the-wanted-spur): the lane_x of every gate's west or east stand
## comes from stand_for_exit() with the side's spur x, and each side's wanted
## spur x follows the build (wanted()). Pure: GateDesks holds each side's
## current x, FlightSim decides when it takes the wanted one (SpurMoves).
##
## The wanted x of a side is the outermost of three: the runway stub's floor
## (StandPlacement.SIDE_LANE_X), the outermost built cell's edge plus
## build_clearance(), and every gate stand on that side's sill plus
## stand_depth(). Both clearances are measured from the plane classes, never a
## fixed distance:
## - build_clearance() is the half width of the band a plane on a spur sweeps,
##   the widest half span of any class (StandEnvelope.lane_band_south()).
## - stand_depth() is how far a spur must be from a side stand's sill for every
##   class's parked plane to keep its tail out of that band (StandEnvelope.
##   clears_lane()), and never less than the pushback's end, so the way out
##   always runs on toward the spur, plus DEPTH_MARGIN_M. Both lengths are
##   along the stand's own frame, so they do not depend on the spur: 70.86 m and
##   21.8 m for today's planes (test_side_spurs_wanted.gd).
##
## A stand being linked (GateDesks) is checked at link_lane(), the spur its own
## sill pushes to beyond the build, so a gate past the current spur can link and
## then push it out. Not guaranteed: a later gate that pushes the spur further
## out than an earlier gate's link_lane() is not re-checked there; nothing is
## built between the two, but the earlier stand's private ground is cut at a
## farther lane band.

const SIDES: Array[String] = [StandPlacement.WEST, StandPlacement.EAST]
## Added to stand_depth(), so a stand exactly that far from its spur clears the
## band for every class despite rounding in the float sums (without it a large
## plane's tail lands on the band's edge and the stand takes only medium).
const DEPTH_MARGIN_M := 0.01
## Side -> which way is out: -1 west, +1 east.
const OUT := {StandPlacement.WEST: -1.0, StandPlacement.EAST: 1.0}

## stand_depth(), worked out once.
static var _depth := -1.0


## Each side's spur x at the floor: {WEST: -SIDE_LANE_X, EAST: SIDE_LANE_X}.
static func floor_lanes() -> Dictionary:
	var out := {}
	for side in SIDES:
		out[side] = StandPlacement.default_lane_x(side)
	return out


## The spurs FlightSim plans with (FlightSim.spurs()): side -> {"x": its x in
## `lanes`, "wanted": its x in `wanted`}, each the floor where a map has none.
static func spurs_at(lanes: Dictionary, wanted: Dictionary) -> Dictionary:
	var out := {}
	for side in SIDES:
		out[side] = {"x": lane_x(side, lanes), "wanted": lane_x(side, wanted)}
	return out


## The spur x of `side` in `lanes` (side -> x), or the floor when it has none.
static func lane_x(side: String, lanes := {}) -> float:
	return float(lanes.get(side, StandPlacement.default_lane_x(side)))


## The stand of exit door `exit_id` on `grid` (StandPlacement.for_exit()), a
## west or east one on its side's spur in `lanes` (side -> x; the floor for a
## side it does not name); {} for none.
static func stand_for_exit(grid: BuildGrid, exit_id: int, lanes := {}) -> Dictionary:
	var stand := StandPlacement.for_exit(grid, exit_id)
	if stand.is_empty() or StandPlacement.side_of(stand) == StandPlacement.NORTH:
		return stand
	var side := StandPlacement.side_of(stand)
	return StandPlacement.with_lane_x(stand, lane_x(side, lanes))


## The half width of the band a plane on a spur sweeps: the widest half span of
## any class, as the north lane's band (StandEnvelope.lane_band_south()).
static func build_clearance() -> float:
	return StandEnvelope.lane_band_south() - StandPlacement.TAXI_LANE_Z


## How far a side stand's spur must be from its sill: the depth at which every
## class's parked model keeps its tail out of the spur's band (the inverse of
## StandEnvelope.clears_lane() in the stand's north-twin frame), or the
## pushback's end when that is farther.
static func stand_depth() -> float:
	if _depth < 0.0:
		var depth := StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M + StandPlacement.PUSHBACK_M
		for plane_class in PlaneClasses.ORDER:
			for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
				var parked := (
					StandPlacement.NOSE_GAP_M
					+ StandPlacement.NOSE_M
					- PlaneClasses.stand_offset(model).z
					+ float(PlaneModels.PLANES[model]["tail"])
				)
				depth = maxf(depth, parked + build_clearance())
		_depth = depth + DEPTH_MARGIN_M
	return _depth


## The outer of two spur x on `side`.
static func outermost(side: String, a: float, b: float) -> float:
	return minf(a, b) if side == StandPlacement.WEST else maxf(a, b)


## The spur x a stand of `side` with its sill at world x `sill_x` needs.
static func stand_lane(side: String, sill_x: float) -> float:
	return sill_x + float(OUT[side]) * stand_depth()


## Each side's spur x the build alone wants on `grid`: the floor, or the
## outermost built cell's edge plus build_clearance() (built_edges()).
static func build_lanes(grid: BuildGrid, edges := {}) -> Dictionary:
	if edges.is_empty():
		edges = built_edges(grid)
	var out := floor_lanes()
	for side in SIDES:
		if edges.has(side):
			var clear := float(edges[side]) + float(OUT[side]) * build_clearance()
			out[side] = outermost(side, out[side], clear)
	return out


## The spur x a stand being linked out of exit `exit_id` is checked at: its own
## stand_lane(), or the build's (build_lanes()) when that is farther out.
static func link_lane(grid: BuildGrid, exit_id: int, built := {}) -> Dictionary:
	var stand := StandPlacement.for_exit(grid, exit_id)
	if stand.is_empty() or StandPlacement.side_of(stand) == StandPlacement.NORTH:
		return {}
	if built.is_empty():
		built = build_lanes(grid)
	var side := StandPlacement.side_of(stand)
	return {side: outermost(side, built[side], stand_lane(side, float(stand["x"])))}


## The stand of exit `exit_id` at its link_lane(): the one GateDesks checks a
## link with.
static func link_stand(grid: BuildGrid, exit_id: int, built := {}) -> Dictionary:
	return stand_for_exit(grid, exit_id, link_lane(grid, exit_id, built))


## link_stand() for a stand `stand` whose exit is not on `grid` yet (a trial).
static func at_link_lane(grid: BuildGrid, stand: Dictionary) -> Dictionary:
	var side := StandPlacement.side_of(stand)
	if side == StandPlacement.NORTH:
		return stand
	var lane := outermost(side, build_lanes(grid)[side], stand_lane(side, float(stand["x"])))
	return StandPlacement.with_lane_x(stand, lane)


## Each side's wanted spur x on `grid` with gates at exit doors `exits`: the
## build's (build_lanes()) or a side gate stand's stand_lane(), whichever is
## farther out. `extra_stands` are stands a trial adds (a desk about to link).
static func wanted(
	grid: BuildGrid, exits: Array, edges := {}, extra_stands: Array[Dictionary] = []
) -> Dictionary:
	var out := build_lanes(grid, edges)
	var stands: Array[Dictionary] = extra_stands.duplicate()
	for exit_id: int in exits:
		stands.append(StandPlacement.for_exit(grid, exit_id))
	for stand in stands:
		if stand.is_empty() or StandPlacement.side_of(stand) == StandPlacement.NORTH:
			continue
		var side := StandPlacement.side_of(stand)
		out[side] = outermost(side, out[side], stand_lane(side, float(stand["x"])))
	return out


## The world x of the outermost built edge on each side of `grid`: {WEST: the
## west edge of the westmost cell that is not apron-clear (a floor, object or
## wall), EAST: the east edge of the eastmost}; a side with none built is left
## out. `gone` names cells to read as cleared (a removal being checked), and
## `added` cells to read as built (a placement being checked).
static func built_edges(grid: BuildGrid, gone := {}, added: Array[Vector2i] = []) -> Dictionary:
	var area := grid.flood_area()
	var west := INF
	var east := -INF
	if area.size != Vector2i.ZERO:
		for x in range(area.position.x, area.end.x):
			if _column_built(grid, x, area, gone):
				west = grid.origin.x + x
				break
		for x in range(area.end.x - 1, area.position.x - 1, -1):
			if _column_built(grid, x, area, gone):
				east = grid.origin.x + x + 1
				break
	for cell in added:
		if grid.in_bounds(cell):
			west = minf(west, grid.origin.x + cell.x)
			east = maxf(east, grid.origin.x + cell.x + 1)
	var out := {}
	if west < INF:
		out[StandPlacement.WEST] = west
	if east > -INF:
		out[StandPlacement.EAST] = east
	return out


static func _column_built(grid: BuildGrid, x: int, area: Rect2i, gone: Dictionary) -> bool:
	for y in range(area.position.y, area.end.y):
		var cell := Vector2i(x, y)
		if not gone.has(cell) and not StandPlacement.apron_clear(grid, null, cell):
			return true
	return false


## The words the works over `side`'s pending spur say on hover (user ruling
## airside-construction-works-are-a-visible-stage-props-mark-th, point 4), with
## the forecast move time `release_tick` (FlightSim.spur_release_tick()) as a
## clock time seen at tick `now` (RunwayWorks.when_text()); no time for -1.
static func works_text(side: String, release_tick := -1, now := 0) -> String:
	var named := "west" if side == StandPlacement.WEST else "east"
	var text := "Taxiway works: the taxiway moves when the %s side is quiet" % named
	if release_tick < 0:
		return text
	return "%s, forecast %s" % [text, RunwayWorks.when_text(release_tick, now)]
