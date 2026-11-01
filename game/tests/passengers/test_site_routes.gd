class_name TestSiteRoutes
extends GdUnitTestSuite
## The walks outside on the airport site (SiteRoutes): each live door gets a
## walk over open ground, an entrance's from the road and an exit's to the
## plane, and a door whose walk is built over is out of service until it has
## one again (decision player-built-terminal-technical-design-site-plot-
## indoor-mask-passenger-eligibility, point 6).

const SITE := preload("res://build/terminal_site.tres")

var _grid: BuildGrid
var _layout: TerminalLayout
var _entrance := 0
var _exit := 0


func before_test() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(_grid)).is_true()
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
	var out := SiteRoutes.departure(_grid, SITE, cells_out)
	print("entrance cells %d, walk in %s" % [cells_in.size(), into])
	print("exit cells %d, walk out %s" % [cells_out.size(), out])
	# Door (18, 17) out to row 39, door (20, 2) out to row 0.
	assert_int(cells_in.size()).is_equal(23)
	assert_int(cells_out.size()).is_equal(3)
	for cell in cells_in.slice(1) + cells_out.slice(1):
		assert_bool(SiteRoutes.is_open_ground(_grid, SITE, cell)).is_true()
	assert_float(into[0].z).is_equal(SITE.road_z)
	assert_vector(into.back()).is_equal(_grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL))
	assert_vector(out[0]).is_equal(_grid.cell_to_world(ReferenceTerminal.EXIT_CELL))
	assert_vector(out.back()).is_equal(SITE.plane_route[SITE.plane_route.size() - 1])


func test_a_built_over_exit_walk_takes_the_exit_out_of_service_and_back() -> void:
	# Floor round the exit's outward cell (20, 1) leaves it no open ground.
	_paint([Vector2i(19, 1), Vector2i(21, 1), Vector2i(20, 0)] as Array[Vector2i])
	print(
		(
			"blocked: open exits %s, out of service %s"
			% [_layout.open_exits(_grid), _layout.out_of_service]
		)
	)
	assert_array(_layout.open_exits(_grid)).is_empty()
	assert_array(_layout.out_of_service).contains_exactly([_exit])
	assert_bool(_layout.outside_routes.has(_exit)).is_false()
	_clear(Vector2i(20, 0))
	print(
		(
			"reopened: open exits %s, out of service %s"
			% [_layout.open_exits(_grid), _layout.out_of_service]
		)
	)
	assert_array(_layout.open_exits(_grid)).contains_exactly([_exit])
	assert_array(_layout.out_of_service).is_empty()


func test_a_built_over_entrance_walk_takes_the_entrance_out_of_service_and_back() -> void:
	_paint([Vector2i(17, 18), Vector2i(19, 18), Vector2i(18, 19)] as Array[Vector2i])
	print(
		(
			"blocked: entrances %s, out of service %s"
			% [_layout.passenger_entrances, _layout.out_of_service]
		)
	)
	assert_array(_layout.passenger_entrances).is_empty()
	assert_array(_layout.entrances).contains_exactly([_entrance])
	assert_array(_layout.out_of_service).contains_exactly([_entrance])
	_clear(Vector2i(18, 19))
	assert_array(_layout.passenger_entrances).contains_exactly([_entrance])
	assert_int((_layout.outside_routes[_entrance] as Array).size()).is_greater(2)


func test_no_walk_crosses_the_sign_post_cell() -> void:
	assert_bool(SiteRoutes.is_open_ground(_grid, SITE, Vector2i(57, 39))).is_false()
	assert_bool(SiteRoutes.is_open_ground(_grid, SITE, Vector2i(56, 39))).is_true()
	# An entrance straight up column 57 goes round the post to reach the road.
	_grid.apply(BuildEdit.paint_floor(Vector2i(57, 30), BuildGrid.FLOOR_TILE, 1))
	_grid.apply(BuildEdit.paint_floor(Vector2i(57, 29), BuildGrid.FLOOR_TILE, 1))
	var door := _grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(57, 30), 2))
	assert_bool(door.ok).is_true()
	_layout.rebuild(_grid)
	var cells: Array[Vector2i] = _layout.outside_routes[door.object_id]
	print("column 57 entrance cells %s" % [cells])
	assert_bool(cells.has(Vector2i(57, 39))).is_false()
	assert_int(cells.back().y).is_equal(SITE.grid_size.y - 1)
