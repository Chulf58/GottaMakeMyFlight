class_name TestStandSideGrid
extends GdUnitTestSuite
## West and east stands on the site grid (StandPlacement's side frame, slice S3
## of design airside-all-around-technical-design-one-route-source-per-con): an
## exit in the starter shell's west or east wall gets a clear sweep and a walk
## out of its own side to the plane door; a door beyond the grid seeds the edge
## cell in its row; an exit on the grid's edge walks out over its own side; and
## a side stand whose wings would reach over the road is refused, though no
## built cell lies under them.

const SITE := preload("res://build/terminal_site.tres")
const SHELL_OFFSET := Vector2i(85, 110)
## The shell's west and east walls (ReferenceTerminal floor x 10 and 21), in
## its airside half (row 4 of the reference terminal).
const WEST_CELL := Vector2i(10, 4)
const EAST_CELL := Vector2i(21, 4)
## Grid row 148: two rows north of the road edge (z -60).
const ROAD_ROW := 148

var _grid: BuildGrid


func before_test() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(StarterShell.place(_grid, SHELL_OFFSET)).is_true()


## Opens the shell's wall at `cell` on `side` and puts an exit door there.
func _add_exit(cell: Vector2i, side: int, facing: int) -> int:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, side)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", cell, facing))
	assert_bool(placed.ok).is_true()
	return placed.object_id


func test_a_west_and_an_east_exit_walk_out_of_their_own_side_to_the_door() -> void:
	var exits := [
		[WEST_CELL, BuildGrid.Side.WEST, 3, StandPlacement.WEST],
		[EAST_CELL, BuildGrid.Side.EAST, 1, StandPlacement.EAST],
	]
	for exit: Array in exits:
		var cell: Vector2i = exit[0] + SHELL_OFFSET
		var id := _add_exit(cell, exit[1], exit[2])
		var stand := StandPlacement.for_cell(_grid, cell, id, exit[3])
		var step := StandPlacement.out_step(stand)
		var centre := _grid.cell_to_world(cell)
		assert_vector(Vector2(stand["x"], stand["wall_z"])).is_equal_approx(
			Vector2(centre.x, centre.z) + Vector2(step) * 0.5, Vector2.ONE * 0.0001
		)
		var walk := StandPlacement.walk_of(_grid, SITE, id, stand)
		var checked := StandPlacement.check(_grid, SITE, id, stand)
		print(
			(
				"%s exit %d stand %s walk %s check %s max class '%s'"
				% [exit[3], id, stand, walk, checked, StandEnvelope.max_class(_grid, SITE, stand)]
			)
		)
		assert_bool(StandPlacement.aircraft_clear(_grid, SITE, stand)).is_true()
		assert_str(checked["status"]).is_equal(StandPlacement.OK)
		assert_int(walk.size()).is_greater(2)
		# Out of the door cell's own outer edge, and on to the plane door.
		var edge := centre + Vector3(step.x, 0.0, step.y) * 0.5
		assert_vector(walk[1]).is_equal_approx(edge, Vector3.ONE * 0.0001)
		var door := StandPlacement.door_point(stand)
		var last := walk[walk.size() - 1]
		assert_vector(Vector2(last.x, last.z)).is_equal_approx(
			Vector2(door.x, door.z), Vector2.ONE * 0.0001
		)
		assert_str(StandEnvelope.max_class(_grid, SITE, stand)).is_not_equal("")


func test_a_door_beyond_the_grid_seeds_the_edge_cell_in_its_row() -> void:
	var west := StandPlacement.for_cell(_grid, Vector2i(0, 114), 0, StandPlacement.WEST)
	var east := StandPlacement.for_cell(
		_grid, Vector2i(_grid.size.x - 1, 114), 0, StandPlacement.EAST
	)
	var raw_west := _grid.world_to_cell(StandPlacement.door_point(west))
	var raw_east := _grid.world_to_cell(StandPlacement.door_point(east))
	print("raw door cells west %s east %s" % [raw_west, raw_east])
	assert_int(raw_west.x).is_less(0)
	assert_int(raw_east.x).is_greater(_grid.size.x - 1)
	assert_vector(StandPlacement.door_seed(_grid, west)).is_equal(Vector2i(0, 114))
	assert_vector(StandPlacement.door_seed(_grid, east)).is_equal(Vector2i(_grid.size.x - 1, 114))


## An exit on the grid's west edge: the walk goes straight out over the west
## edge (the stand's own out step), never over the north edge's.
func test_an_exit_on_the_grid_edge_walks_out_over_its_own_side() -> void:
	var cell := Vector2i(0, 114)
	var stand := StandPlacement.for_cell(_grid, cell, 0, StandPlacement.WEST)
	var dist := StandPlacement.to_door(_grid, SITE, stand)
	var out := Vector2i(-1, 0)
	var own := SiteRoutes.reaches(_grid, SITE, cell, out, StandPlacement.out_step(stand), dist)
	var north := SiteRoutes.reaches(_grid, SITE, cell, out, SiteDefinition.PLANE_STEP, dist)
	var walk := SiteRoutes.departure(_grid, SITE, [cell] as Array[Vector2i], stand)
	print("edge exit: own side %s, north edge %s, walk %s" % [own, north, walk])
	assert_bool(own).is_true()
	assert_bool(north).is_false()
	assert_vector(walk[1]).is_equal_approx(
		_grid.cell_to_world(cell) + Vector3(-0.5, 0.0, 0.0), Vector3.ONE * 0.0001
	)


## A west stand two rows from the road: its swing square reaches past the
## grid's south edge, where cells_under() finds no cell, so only the road check
## refuses it. Controls: the same stand 34 rows north is clear, and so is a
## north stand on the road row.
func test_a_side_stand_with_wings_over_the_road_is_refused() -> void:
	var stand := StandPlacement.for_cell(_grid, Vector2i(60, ROAD_ROW), 0, StandPlacement.WEST)
	var rects := StandPlacement.swept_rects(stand)
	var south := -INF
	for rect in rects:
		south = maxf(south, rect.end.y)
	var built := 0
	for cell: Vector2i in StandPlacement.cells_under(_grid, rects):
		if not StandPlacement.apron_clear(_grid, SITE, cell):
			built += 1
	var road_edge := _grid.origin.z + _grid.size.y
	print(
		(
			"road stand %s: south edge %.2f, road edge %.2f, built cells %d"
			% [stand, south, road_edge, built]
		)
	)
	assert_float(south).is_greater(road_edge)
	assert_int(built).is_equal(0)
	assert_bool(StandPlacement.reaches_road(_grid, rects)).is_true()
	assert_bool(StandPlacement.aircraft_clear(_grid, SITE, stand)).is_false()
	assert_int(StandEnvelope.blocked_part(_grid, SITE, stand, PlaneClasses.SMALL)).is_equal(
		StandEnvelope.Part.SWING
	)
	assert_str(StandEnvelope.max_class(_grid, SITE, stand)).is_equal("")
	var north_of_it := StandPlacement.for_cell(
		_grid, Vector2i(60, ROAD_ROW - 34), 0, StandPlacement.WEST
	)
	assert_bool(StandPlacement.aircraft_clear(_grid, SITE, north_of_it)).is_true()
	var north_stand := StandPlacement.for_cell(_grid, Vector2i(60, ROAD_ROW))
	assert_bool(StandPlacement.aircraft_clear(_grid, SITE, north_stand)).is_true()
	assert_str(StandEnvelope.max_class(_grid, SITE, north_stand)).is_not_equal("")
