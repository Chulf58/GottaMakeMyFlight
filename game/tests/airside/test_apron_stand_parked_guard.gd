class_name TestApronStandParkedGuard
extends GdUnitTestSuite
## The guard on a plane that has not left its stand (ApronStand.still_rects();
## board 615b0f2c, after slice S3 of design airside-all-around-technical-design-
## one-route-source-per-con): every grid cell under the parked plane, drawn as
## PlaneView draws it (the model's box at the stand point moved by
## PlaneClasses.stand_offset), is guarded, for models 04, 06 and 07 at a north,
## a west and an east stand. A parked model 04, 06 or 07 reaches past the south
## edge of its class's swing square, so the class ground alone leaves a strip
## by the wall unguarded.
##
## The stands come from the site's own frame: the north one straight out of
## ReferenceTerminal's exit cell moved by SITE.starter_offset, the side ones
## out of cells a named step east and west of it. Each case samples the drawn
## box every STEP_M, INSET_M inside its edges, so a sliver cells_under()
## ignores is not asked for, and asks that every sampled cell is guarded.

const SITE := preload("res://build/terminal_site.tres")
const STEP_M := 0.25
const INSET_M := 0.05
## The side stands' exit cells, a step along the grid from the north one and
## down to the grid's middle rows.
const WEST_STEP := Vector2i(80, -37)
const EAST_STEP := Vector2i(-80, -37)
## Models 04, 06 and 07 with their classes.
const PLANES := [
	["tp_plane_04a", PlaneClasses.MEDIUM],
	["tp_plane_06a", PlaneClasses.LARGE],
	["tp_plane_07a", PlaneClasses.LARGE],
]

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func _stands() -> Array[Dictionary]:
	var exit_cell := ReferenceTerminal.EXIT_CELL + SITE.starter_offset
	return (
		[
			StandPlacement.for_cell(_grid, exit_cell, 2),
			StandPlacement.for_cell(_grid, exit_cell + WEST_STEP, 3, StandPlacement.WEST),
			StandPlacement.for_cell(_grid, exit_cell + EAST_STEP, 4, StandPlacement.EAST),
		]
		as Array[Dictionary]
	)


## The grid cells under `model`'s box parked at `stand`: its origin at the stand
## point moved by the model's stand offset, turned to the stand's side, found
## without ApronStand's own footprint.
func _cells_under_plane(stand: Dictionary, model: String) -> Dictionary:
	var shape: Dictionary = PlaneModels.PLANES[model]
	var origin := (
		StandPlacement.stand_point(stand)
		+ StandPlacement.turn(stand, PlaneClasses.stand_offset(model))
	)
	var box: AABB = shape["aabb"]
	var out := {}
	var x := box.position.x + INSET_M
	while x <= box.end.x - INSET_M + 0.0001:
		var z := box.position.z + INSET_M
		while z <= box.end.z - INSET_M + 0.0001:
			var cell := _grid.world_to_cell(origin + StandPlacement.turn(stand, Vector3(x, 0.0, z)))
			if _grid.in_bounds(cell):
				out[cell] = true
			z += STEP_M
		x += STEP_M
	return out


## How many cells under `plane` parked at `stand` the guard (still_rects())
## leaves open, and how many of them the class ground alone leaves open; prints
## the case.
func _unguarded(stand: Dictionary, plane: Array) -> int:
	var under := _cells_under_plane(stand, plane[0])
	var guarded := StandPlacement.cells_under(
		_grid, ApronStand.still_rects(stand, plane[1], plane[0])
	)
	var class_only := StandPlacement.cells_under(_grid, ApronStand.class_rects(stand, plane[1]))
	var missing := 0
	var strip := 0
	for cell: Vector2i in under:
		if not guarded.has(cell):
			missing += 1
		if not class_only.has(cell):
			strip += 1
	print(
		(
			"%s %s: %d cells under it, %d not guarded, %d outside the class ground"
			% [StandPlacement.side_of(stand), plane[0], under.size(), missing, strip]
		)
	)
	assert_int(under.size()).is_greater(100)
	return missing


func test_every_cell_under_a_parked_plane_is_guarded_at_each_side() -> void:
	for stand in _stands():
		for plane: Array in PLANES:
			assert_int(_unguarded(stand, plane)).is_equal(0)


## The strip is real: with the class ground alone, a parked model 04, 06 or 07
## leaves cells under it open, so the cases above are not passing by default.
func test_the_class_ground_alone_leaves_a_strip_under_models_04_06_and_07() -> void:
	for stand in _stands():
		for plane: Array in PLANES:
			var under := _cells_under_plane(stand, plane[0])
			var class_only := StandPlacement.cells_under(
				_grid, ApronStand.class_rects(stand, plane[1])
			)
			var open := 0
			for cell: Vector2i in under:
				if not class_only.has(cell):
					open += 1
			print(
				(
					"%s %s: %d cells under it outside the class ground"
					% [stand["exit"], plane[0], open]
				)
			)
			assert_int(open).is_greater(0)


## Control: ground clear of the plane, past the swing square, is not guarded.
func test_ground_clear_of_the_plane_is_not_guarded() -> void:
	for stand in _stands():
		for plane: Array in PLANES:
			var guarded := StandPlacement.cells_under(
				_grid, ApronStand.still_rects(stand, plane[1], plane[0])
			)
			var beside := Vector3(50.0, 0.0, 0.0)
			var clear := _grid.world_to_cell(
				StandPlacement.stand_point(stand) + StandPlacement.turn(stand, beside)
			)
			print(
				(
					"%s %s: clear cell %s in bounds %s guarded %s"
					% [stand["exit"], plane[0], clear, _grid.in_bounds(clear), guarded.has(clear)]
				)
			)
			assert_bool(_grid.in_bounds(clear)).is_true()
			assert_bool(guarded.has(clear)).is_false()


## The guard of a flight at the stand is still_rects() of its class and model
## for every state before TAXI_OUT, and holds every cell under the plane it
## draws. The starter flight's small plane lies inside its swing square, so it
## adds no rectangle of its own.
func test_the_guard_of_a_busy_stand_is_the_still_guard_before_taxi_out() -> void:
	var flights := auto_free(FlightSim.new()) as FlightSim
	var apron := auto_free(ApronStand.new()) as ApronStand
	var grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(grid, SITE.starter_offset)).is_true()
	apron.bind(grid, SITE, flights)
	var starts := FlightSim.schedule_starts(1000)
	assert_bool(flights.add_flight("F1", starts)).is_true()
	var model := PlaneClasses.flight_model(flights, "F1")
	var still := ApronStand.still_rects(apron.live, PlaneClasses.SMALL, model)
	var guarded := StandPlacement.cells_under(grid, still)
	var under := _cells_under_plane(apron.live, model)
	var open := 0
	for cell: Vector2i in under:
		if not guarded.has(cell):
			open += 1
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.BOARDING, FlightSim.State.PUSHBACK]:
		flights.on_tick(starts[state])
		print(
			"state %d, %s: %d rects, %d cells under it" % [state, model, still.size(), under.size()]
		)
		assert_array(apron.guard_rects()).is_equal(still)
	assert_int(under.size()).is_greater(50)
	assert_int(open).is_equal(0)
