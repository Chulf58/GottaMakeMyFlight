class_name TestSiteRoutes
extends GdUnitTestSuite
## The walks outside on the airport site (SiteRoutes): each live door gets a
## walk over open ground, an entrance's from the road and an exit's to the
## plane door at the live stand (decision plane-stand-design-airside-moves-
## 110-m-north-stand-snaps-to, point 6), and a door whose walk is built over is
## out of service until it has one again (decision player-built-terminal-
## technical-design-site-plot-indoor-mask-passenger-eligibility, point 6).

const SITE := preload("res://build/terminal_site.tres")

## The grid columns of side land west of the first site (used by SITE.obstacles).
const SIDE_LAND := Vector2i(85, 0)

var _at := SITE.starter_offset
var _grid: BuildGrid
var _layout: TerminalLayout
var _entrance := 0
var _exit := 0


func before_test() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(_grid, SITE.starter_offset)).is_true()
	_layout = TerminalLayout.new()
	_layout.site = SITE
	_layout.rebuild(_grid)
	var ids := ReferenceTerminal.object_ids(_grid)
	_entrance = ids["entrances"][0]
	_exit = ids["exits"][0]


func _paint(cells: Array[Vector2i]) -> void:
	for cell in cells:
		assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	_layout.rebuild(_grid)


func _clear(cell: Vector2i) -> void:
	assert_bool(_grid.apply(BuildEdit.remove_floor(cell)).ok).is_true()
	_layout.rebuild(_grid)


func test_an_entrance_walks_in_from_the_road_and_an_exit_out_to_the_plane() -> void:
	assert_array(_layout.passenger_entrances).contains_exactly([_entrance])
	assert_array(_layout.open_exits(_grid)).contains_exactly([_exit])
	assert_array(_layout.out_of_service).is_empty()
	var cells_in: Array[Vector2i] = _layout.outside_routes[_entrance]
	var cells_out: Array[Vector2i] = _layout.outside_routes[_exit]
	var into := SiteRoutes.arrival(_grid, SITE, cells_in)
	var stand := _layout.live_stand(_grid)
	var out := SiteRoutes.departure(_grid, SITE, cells_out, stand)
	print("entrance cells %d, walk in %s" % [cells_in.size(), into])
	print("exit cells %d, walk out %s" % [cells_out.size(), out])
	# Door (ENTRANCE_CELL + starter_offset) out to road row; EXIT_CELL + starter_offset
	# out to the plane door's cell, straight ahead.
	assert_int(cells_in.size()).is_equal(
		SITE.grid_size.y - (ReferenceTerminal.ENTRANCE_CELL.y + _at.y)
	)
	assert_int(cells_out.size()).is_equal(8)
	assert_that(cells_out.back()).is_equal(StandPlacement.door_seed(_grid, stand))
	for cell in cells_in.slice(1) + cells_out.slice(1):
		assert_bool(SiteRoutes.is_open_ground(_grid, SITE, cell)).is_true()
	assert_float(into[0].z).is_equal(SITE.road_z)
	assert_vector(into.back()).is_equal(_grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL + _at))
	assert_vector(out[0]).is_equal(_grid.cell_to_world(ReferenceTerminal.EXIT_CELL + _at))
	# The apron route stands on the site's ground (SiteRoutes.to_plane()).
	var end := StandPlacement.door_point(stand)
	assert_vector(out.back()).is_equal(Vector3(end.x, SITE.ground_height, end.z))


func test_an_exit_on_another_wall_walks_round_to_the_plane_door() -> void:
	# An exit in the shell's east wall, facing east.
	var cell := Vector2i(21, 10) + _at
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.EAST)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", cell, 1))
	assert_bool(placed.ok).is_true()
	_layout.rebuild(_grid)
	var cells: Array[Vector2i] = _layout.outside_routes[placed.object_id]
	var stand := _layout.live_stand(_grid)
	var walk := SiteRoutes.departure(_grid, SITE, cells, stand)
	print("east exit cells %d, walk %s" % [cells.size(), walk])
	assert_that(cells[1]).is_equal(cell + Vector2i(1, 0))
	assert_that(cells.back()).is_equal(StandPlacement.door_seed(_grid, stand))
	var end := StandPlacement.door_point(stand)
	assert_vector(walk.back()).is_equal(Vector3(end.x, SITE.ground_height, end.z))
	assert_float(StandPlacement.walk_length(walk)).is_greater(15.0)


func test_a_built_over_exit_walk_takes_the_exit_out_of_service_and_back() -> void:
	# Floor round the exit's outward cell leaves it no open ground.
	var exit_cell := ReferenceTerminal.EXIT_CELL + _at
	_paint(
		(
			[exit_cell + Vector2i(-1, -1), exit_cell + Vector2i(1, -1), exit_cell + Vector2i(0, -2)]
			as Array[Vector2i]
		)
	)
	print(
		(
			"blocked: open exits %s, out of service %s"
			% [_layout.open_exits(_grid), _layout.out_of_service]
		)
	)
	assert_array(_layout.open_exits(_grid)).is_empty()
	assert_array(_layout.out_of_service).contains_exactly([_exit])
	assert_bool(_layout.outside_routes.has(_exit)).is_false()
	_clear(exit_cell + Vector2i(0, -2))
	print(
		(
			"reopened: open exits %s, out of service %s"
			% [_layout.open_exits(_grid), _layout.out_of_service]
		)
	)
	assert_array(_layout.open_exits(_grid)).contains_exactly([_exit])
	assert_array(_layout.out_of_service).is_empty()


func test_a_built_over_entrance_walk_takes_the_entrance_out_of_service_and_back() -> void:
	var entrance_cell := ReferenceTerminal.ENTRANCE_CELL + _at
	_paint(
		(
			[
				entrance_cell + Vector2i(-1, 1),
				entrance_cell + Vector2i(1, 1),
				entrance_cell + Vector2i(0, 2)
			]
			as Array[Vector2i]
		)
	)
	print(
		(
			"blocked: entrances %s, out of service %s"
			% [_layout.passenger_entrances, _layout.out_of_service]
		)
	)
	assert_array(_layout.passenger_entrances).is_empty()
	assert_array(_layout.entrances).contains_exactly([_entrance])
	assert_array(_layout.out_of_service).contains_exactly([_entrance])
	_clear(entrance_cell + Vector2i(0, 2))
	assert_array(_layout.passenger_entrances).contains_exactly([_entrance])
	assert_int((_layout.outside_routes[_entrance] as Array).size()).is_greater(2)


func test_no_walk_crosses_the_sign_post_cell() -> void:
	assert_bool(SiteRoutes.is_open_ground(_grid, SITE, Vector2i(57, 149) + SIDE_LAND)).is_false()
	assert_bool(SiteRoutes.is_open_ground(_grid, SITE, Vector2i(56, 149) + SIDE_LAND)).is_true()
	# An entrance straight up column 142 goes round the post to reach the road.
	_grid.apply(BuildEdit.paint_floor(Vector2i(57, 140) + SIDE_LAND, BuildGrid.FLOOR_TILE, 1))
	_grid.apply(BuildEdit.paint_floor(Vector2i(57, 139) + SIDE_LAND, BuildGrid.FLOOR_TILE, 1))
	var door := _grid.apply(
		BuildEdit.place_object(&"entrance_door", Vector2i(57, 140) + SIDE_LAND, 2)
	)
	assert_bool(door.ok).is_true()
	_layout.rebuild(_grid)
	var cells: Array[Vector2i] = _layout.outside_routes[door.object_id]
	print("column 142 entrance cells %s" % [cells])
	assert_bool(cells.has(Vector2i(57, 149) + SIDE_LAND)).is_false()
	assert_int(cells.back().y).is_equal(SITE.grid_size.y - 1)
