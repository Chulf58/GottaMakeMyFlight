class_name TestSideSpursWanted
extends GdUnitTestSuite
## Each side's wanted spur x follows the build (SideSpurs.wanted(); decision
## side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur): the measured
## clearances, the starter site keeping both spurs on the floor (x -124 / +124,
## so nothing moves in today's game), a built cell past the spur pushing it out
## by the band a plane sweeps, a side stand pushing it out by stand_depth(), and
## a removal being read back in (built_edges()).
##
## Cells are the starter shell's (ReferenceTerminal coordinates) moved by the
## site's starter offset, as in test_gate_desks_side.gd; the far cells are the
## grid's own edge columns, which land == null lets a test build on.

const SITE := preload("res://build/terminal_site.tres")
const WEST_EXIT := Vector2i(ReferenceTerminal.FLOOR_MIN.x, 6)
const EAST_EXIT := Vector2i(ReferenceTerminal.FLOOR_MAX.x, 4)
## Grid cells (not shell ones) on the west and east edges, far south of the
## starter, so they meet no stand.
const FAR_WEST := Vector2i(0, 149)
const FAR_EAST := Vector2i(255, 149)

var _base: SiteGrid
var _grid: SiteGrid


func before() -> void:
	_base = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_base, SITE.starter_offset)).is_true()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid


func _add_exit(cell: Vector2i, side: int, facing: int) -> int:
	var at := cell + SITE.starter_offset
	assert_bool(_grid.apply(BuildEdit.remove_wall(at, side)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", at, facing))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return placed.object_id


func _floor(cell: Vector2i) -> void:
	var painted := _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 0))
	assert_bool(painted.ok).override_failure_message(painted.reason_text()).is_true()


## The clearances are measured from the plane classes: the widest half span,
## and the depth at which every class's parked tail clears that band, with a
## 0.01 m margin. A north twin at that depth clears the lane for every class,
## and 0.1 m nearer it does not for a large plane, so the depth is the least
## that works.
func test_the_clearances_are_measured_from_the_planes() -> void:
	var band := SideSpurs.build_clearance()
	var depth := SideSpurs.stand_depth()
	print("build_clearance %.3f m, stand_depth %.3f m" % [band, depth])
	assert_float(band).is_equal_approx(21.8, 0.001)
	assert_float(depth).is_equal_approx(70.86, 0.001)
	var at := StandPlacement.make(0, 0.0, StandPlacement.TAXI_LANE_Z + depth)
	var nearer := StandPlacement.make(0, 0.0, StandPlacement.TAXI_LANE_Z + depth - 0.1)
	for plane_class in PlaneClasses.ORDER:
		print(
			"%s clears at the depth: %s" % [plane_class, StandEnvelope.clears_lane(at, plane_class)]
		)
		assert_bool(StandEnvelope.clears_lane(at, plane_class)).is_true()
	assert_bool(StandEnvelope.clears_lane(nearer, PlaneClasses.LARGE)).is_false()


## The starter shell with a west and an east gate exit wants both spurs on the
## floor: today's game moves nothing.
func test_the_starter_site_keeps_both_spurs_on_the_floor() -> void:
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.WEST, 3)
	var east := _add_exit(EAST_EXIT, BuildGrid.Side.EAST, 1)
	var wanted := SideSpurs.wanted(_grid, [west, east])
	var edges := SideSpurs.built_edges(_grid)
	print("edges %s, wanted %s" % [edges, wanted])
	assert_float(edges[StandPlacement.WEST]).is_less(-StandPlacement.SIDE_LANE_X + 100.0)
	assert_dict(wanted).is_equal(SideSpurs.floor_lanes())
	var stand := SideSpurs.link_stand(_grid, west)
	assert_float(StandPlacement.lane_x_of(stand)).is_equal(-StandPlacement.SIDE_LANE_X)


## A floor cell on the grid's west edge pushes the west spur out to its edge
## less the band; the east spur stays. The same on the east.
func test_a_cell_past_the_spur_pushes_it_out_by_the_band() -> void:
	_floor(FAR_WEST)
	var wanted := SideSpurs.wanted(_grid, [])
	print("far west floor: wanted %s" % [wanted])
	assert_float(wanted[StandPlacement.WEST]).is_equal_approx(
		_grid.origin.x - SideSpurs.build_clearance(), 0.0001
	)
	assert_float(wanted[StandPlacement.EAST]).is_equal(StandPlacement.SIDE_LANE_X)
	_floor(FAR_EAST)
	wanted = SideSpurs.wanted(_grid, [])
	print("and far east: wanted %s" % [wanted])
	assert_float(wanted[StandPlacement.EAST]).is_equal_approx(
		_grid.origin.x + _grid.size.x + SideSpurs.build_clearance(), 0.0001
	)


## A west stand whose sill is less than stand_depth() inside the floor spur
## pushes the spur out to its sill less stand_depth(); a cell nearer than that
## is outdone by it. link_lane() gives such an exit that spur too.
func test_a_side_stand_pushes_the_spur_out_by_its_depth() -> void:
	var cell := Vector2i(70, 116)
	var stand := StandPlacement.for_cell(_grid, cell, 0, StandPlacement.WEST)
	var sill := float(stand["x"])
	var wanted := SideSpurs.wanted(_grid, [], {}, [stand] as Array[Dictionary])
	print("sill %.2f: wanted %s" % [sill, wanted])
	assert_float(sill).is_greater(-StandPlacement.SIDE_LANE_X)
	assert_float(sill - SideSpurs.stand_depth()).is_less(-StandPlacement.SIDE_LANE_X)
	assert_float(wanted[StandPlacement.WEST]).is_equal_approx(
		sill - SideSpurs.stand_depth(), 0.0001
	)
	assert_float(SideSpurs.stand_lane(StandPlacement.WEST, sill)).is_equal_approx(
		wanted[StandPlacement.WEST], 0.0001
	)


## built_edges() reads a removal's cells as cleared and a placement's as built,
## without the edit applied.
func test_built_edges_read_a_trial_edit() -> void:
	var before := SideSpurs.built_edges(_grid)
	var added: Array[Vector2i] = [FAR_WEST]
	var with_cell := SideSpurs.built_edges(_grid, {}, added)
	print("edges %s, with a far west cell %s" % [before, with_cell])
	assert_float(with_cell[StandPlacement.WEST]).is_equal(_grid.origin.x)
	assert_float(with_cell[StandPlacement.EAST]).is_equal(before[StandPlacement.EAST])
	_floor(FAR_WEST)
	var built := SideSpurs.built_edges(_grid)
	var gone := SideSpurs.built_edges(_grid, {FAR_WEST: true})
	print("built %s, read with it removed %s" % [built, gone])
	assert_float(built[StandPlacement.WEST]).is_equal(_grid.origin.x)
	assert_float(gone[StandPlacement.WEST]).is_equal(before[StandPlacement.WEST])


## The works hover names the side.
func test_the_works_text_names_the_side() -> void:
	assert_str(SideSpurs.works_text(StandPlacement.WEST, -1, 0, 0)).is_equal(
		"Taxiway works: the taxiway moves when the west side is quiet"
	)
	assert_str(SideSpurs.works_text(StandPlacement.EAST, -1, 0, 0)).contains("east side")
