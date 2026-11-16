class_name TestApronStandSpurGuard
extends GdUnitTestSuite
## The taxi-out guard once the plane has left its stand, at north, west and
## east stands on the S4 spur routes (board the-taxi-out-guard-holds-back-too-
## much-for-an-east-stand-and; ApronStand.route_rects): ground a taxiing-out
## plane has released stays released for the rest of TAXI_OUT, and the guard
## still holds every cell under the drawn plane.
##
## The routes are TaxiRoutes' own (the west stand's out is back, join,
## TaxiWest, Entry; the east stand's back, join, TaxiEast, TaxiWest, Entry),
## the stands come from the site's frame (ReferenceTerminal.EXIT_CELL plus
## SITE.starter_offset, a named step along the grid for the side ones). Each
## run steps the plane along TAXI_OUT every STEP_M of route and works on the
## stand's uncut ground (ApronStand.class_rects(): swing square and connector):
## - the cells of it the cut ground releases (the plane's own box, route_rects()'
##   last rectangle, left out) never shrink as the plane moves on;
## - every sampled cell under the drawn plane is guarded;
## - every cell of it the plane covers later is guarded now;
## - well past the join, no cell of it is held.
## The runs are on the site grid and on a wide one that also holds the lane,
## and are worked out once for the file.

const SITE := preload("res://build/terminal_site.tres")
const WEST_STEP := Vector2i(80, -37)
const EAST_STEP := Vector2i(-80, -37)
const STEP_M := 2.0
## The runs on the site grid that step finely through the corner at the join and
## on past the plane clearing the stand's ground: from FINE_FROM_M before the join
## to FINE_TO_M after it, every FINE_STEP_M, so a window of under a metre shows.
const FINE_STEP_M := 0.25
const FINE_FROM_M := 8.0
const FINE_TO_M := 42.0
const SAMPLE_M := 0.5
const INSET_M := 0.05
## The plane's box is clear of the stand's ground this far past the join.
const CLEAR_M := 50.0
## Models 03, 05 and 07 with their classes.
const PLANES := [
	["tp_plane_03a", "small"],
	["tp_plane_05a", "medium"],
	["tp_plane_07a", "large"],
]

var _grids: Array[BuildGrid] = []
## "side model on grid n" -> the run's summary (_run()).
var _runs := {}


func before() -> void:
	_grids = [
		BuildGrid.new(SITE.grid_size, SITE.grid_origin),
		BuildGrid.new(Vector2i(256, 256), Vector3(-128.0, 0.0, -340.0)),
	]
	for g in _grids.size():
		for stand in _stands():
			for plane: Array in PLANES:
				_runs[_key(g, stand, plane)] = _run(_grids[g], stand, plane)
				_runs["fine " + _key(g, stand, plane)] = _run(_grids[g], stand, plane, true)


static func _key(grid_index: int, stand: Dictionary, plane: Array) -> String:
	return "%s %s on grid %d" % [StandPlacement.side_of(stand), plane[0], grid_index]


func _stands() -> Array[Dictionary]:
	var exit_cell := ReferenceTerminal.EXIT_CELL + SITE.starter_offset
	return (
		[
			StandPlacement.for_cell(_grids[0], exit_cell, 2),
			StandPlacement.for_cell(_grids[0], exit_cell + WEST_STEP, 3, StandPlacement.WEST),
			StandPlacement.for_cell(_grids[0], exit_cell + EAST_STEP, 4, StandPlacement.EAST),
		]
		as Array[Dictionary]
	)


## `stand`'s TAXI_OUT route, from the same TaxiRoutes the airside draws.
static func _route(stand: Dictionary, plane_class: String) -> PackedVector3Array:
	var points := FlightGround.points()
	var paths := TaxiRoutes.phase_paths(
		points, TaxiRoutes.stand_ends(stand), plane_class, TaxiRoutes.north_only(points)
	)
	return paths[FlightSim.State.TAXI_OUT]


## The TAXI_OUT progress that puts the plane `distance` along `path` with no
## pause (MovementPlan.fraction() is a smoothstep), by bisection.
static func _progress(path: PackedVector3Array, distance: float) -> float:
	var total := MovementPlan.path_length(path)
	var low := 0.0
	var high := 1.0
	for i in 60:
		var mid := (low + high) / 2.0
		if total * MovementPlan.fraction(mid) < distance:
			low = mid
		else:
			high = mid
	return (low + high) / 2.0


## The grid cells under `model`'s box `distance` along `path`, found without
## ApronStand's own footprint: centred on the route point, half its length
## ahead and behind and its half span either side, turned to the heading there.
static func _box_cells(
	grid: BuildGrid, path: PackedVector3Array, distance: float, model: String, entry: Vector3
) -> Dictionary:
	var at := MovementPlan.point_at(path, distance)
	var nose := MovementPlan.heading_at(path, distance, entry)
	var left := Vector3(nose.z, 0.0, -nose.x)
	var half_length: float = PlaneModels.PLANES[model]["length"] / 2.0 - INSET_M
	var half_span: float = PlaneModels.PLANES[model]["half_span"] - INSET_M
	var out := {}
	var along := -half_length
	while along <= half_length + 0.0001:
		var across := -half_span
		while across <= half_span + 0.0001:
			var cell := grid.world_to_cell(at + nose * along + left * across)
			if grid.in_bounds(cell):
				out[cell] = true
			across = minf(across + SAMPLE_M, half_span) if across < half_span else INF
		along = minf(along + SAMPLE_M, half_length) if along < half_length else INF
	return out


## Runs `plane` out of `stand` on `grid`, a step at a time, and sums up:
## "released" and "held" (per step: the cells of the stand's uncut ground the cut
## ground releases, and the cells of it any rectangle guards), "retaken" (cells
## released at a step and guarded at the next), "covered" and "missing" (cells
## under the plane over all steps, and those not guarded), "early" (cells of the
## ground the plane covers later that a step has not guarded), "late" (held
## cells of the steps CLEAR_M past the join), and "in_ground" (cell-steps of the
## plane over the stand's ground: the control that the other counts are not
## zero for want of anything to test). With `fine`, only the stretch of
## the route round the join and the plane's clearing of the ground, every
## FINE_STEP_M.
func _run(grid: BuildGrid, stand: Dictionary, plane: Array, fine := false) -> Dictionary:
	var path := _route(stand, plane[1])
	var entry := MovementPlan.flat_dir(
		StandPlacement.stand_point(stand), StandPlacement.pushback_end(stand)
	)
	var join_at := path[0].distance_to(path[1])
	var ground := StandPlacement.cells_under(grid, ApronStand.class_rects(stand, plane[1]))
	var out := {
		"released": [],
		"held": [],
		"retaken": 0,
		"covered": 0,
		"missing": 0,
		"early": 0,
		"in_ground": 0,
		"join_on_grid": grid.in_bounds(grid.world_to_cell(path[1]))
	}
	var late := 0
	var rects_by_step: Array = []
	var under_by_step: Array = []
	var before_released := {}
	var total := MovementPlan.path_length(path)
	var distance := maxf(join_at - FINE_FROM_M, 0.0) if fine else 0.0
	var step := FINE_STEP_M if fine else STEP_M
	var until := minf(join_at + FINE_TO_M, total) if fine else total
	while distance <= until:
		var rects := ApronStand.route_rects(
			stand, path, _progress(path, distance), plane[0], plane[1]
		)
		var guarded := StandPlacement.cells_under(grid, rects)
		var cut := StandPlacement.cells_under(grid, rects.slice(0, rects.size() - 1))
		var released := {}
		var held := 0
		for cell: Vector2i in ground:
			if guarded.has(cell):
				held += 1
			if not cut.has(cell):
				released[cell] = true
		for cell: Vector2i in before_released:
			if not released.has(cell):
				out["retaken"] += 1
		var under := _box_cells(grid, path, distance, plane[0], entry)
		out["covered"] += under.size()
		var in_ground := {}
		for cell: Vector2i in under:
			if not guarded.has(cell):
				out["missing"] += 1
			if ground.has(cell):
				in_ground[cell] = true
				out["in_ground"] += 1
		if distance >= join_at + CLEAR_M:
			late += held
		out["released"].append(released.size())
		out["held"].append(held)
		rects_by_step.append(rects)
		under_by_step.append(in_ground)
		before_released = released
		distance += step
	var later := {}
	for i in range(rects_by_step.size() - 1, -1, -1):
		var guarded := StandPlacement.cells_under(grid, rects_by_step[i])
		for cell: Vector2i in later:
			if not guarded.has(cell):
				out["early"] += 1
		later.merge(under_by_step[i])
	out["late"] = late
	return out


func _each_run(check: Callable, fine := false) -> void:
	for g in _grids.size():
		for stand in _stands():
			for plane: Array in PLANES:
				var key := _key(g, stand, plane)
				if fine:
					key = "fine " + key
				check.call(key, _runs[key])


## Released ground is never guarded again: the cut only moves on with the plane.
## Without the fix a west stand's strip beside the spur and an east stand's
## whole swing square and connector come back as the route turns.
func test_released_ground_stays_released_for_the_rest_of_taxi_out() -> void:
	_each_run(
		func(key: String, run: Dictionary) -> void:
			print(
				(
					"%s: released cells per step %s, %d retaken"
					% [key, run["released"], run["retaken"]]
				)
			)
			assert_int(run["released"][-1]).is_greater(0)
			assert_int(run["retaken"]).is_equal(0)
	)


## The S3 property, past the join: every sampled cell under the drawn plane is
## guarded all the way along TAXI_OUT.
func test_every_cell_under_the_drawn_plane_is_guarded_all_the_way_out() -> void:
	_each_run(
		func(key: String, run: Dictionary) -> void:
			print(
				(
					"%s: %d cell-steps under the plane, %d over the ground, %d not guarded"
					% [key, run["covered"], run["in_ground"], run["missing"]]
				)
			)
			assert_int(run["covered"]).is_greater(100)
			assert_int(run["in_ground"]).is_greater(0)
			assert_int(run["missing"]).is_equal(0)
	)


## A cell the plane covers later, inside the stand's ground, is never released
## before the plane gets there: released ground is ground the plane is done with.
func test_released_ground_is_never_covered_by_the_plane_later() -> void:
	_each_run(
		func(key: String, run: Dictionary) -> void:
			print("%s: %d cell-steps released before the plane covers them" % [key, run["early"]])
			assert_int(run["early"]).is_equal(0)
	)


## Once the plane is clear of the stand nothing of its ground is held, on the
## grid or off it; the north stand is the control (its lane is off the site grid).
func test_no_ground_is_held_once_the_plane_is_clear_of_the_stand() -> void:
	_each_run(
		func(key: String, run: Dictionary) -> void:
			print(
				(
					"%s: cells held per step %s, %d summed %d m past the join"
					% [key, run["held"], run["late"], CLEAR_M]
				)
			)
			assert_int(run["held"][0]).is_greater(0)
			assert_int(run["late"]).is_equal(0)
	)


## The same through the corner at the join and the plane clearing the ground,
## stepped every FINE_STEP_M, so a window of under a metre shows (a small plane
## is past the fixed turn distance with its nose short of the class's way): no
## ground is retaken, none is released before the plane covers it, and the plane
## is guarded at each step.
func test_a_sub_metre_window_at_the_corner_and_the_release_point_stays_guarded() -> void:
	_each_run(
		func(key: String, run: Dictionary) -> void:
			print(
				(
					"%s: %d steps, %d cell-steps over the ground, %d retaken, %d early, %d unguarded"
					% [
						key,
						run["held"].size(),
						run["in_ground"],
						run["retaken"],
						run["early"],
						run["missing"]
					]
				)
			)
			assert_int(run["held"].size()).is_greater(100)
			# A north stand's join (the lane) is off the site grid, so there the plane
			# is never over the ground: the control; the wide grid's run holds it.
			assert_bool(run["in_ground"] > 0).is_equal(run["join_on_grid"])
			assert_int(run["retaken"]).is_equal(0)
			assert_int(run["early"]).is_equal(0)
			assert_int(run["missing"]).is_equal(0),
		true
	)
