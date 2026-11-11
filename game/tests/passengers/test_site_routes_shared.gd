class_name TestSiteRoutesShared
extends GdUnitTestSuite
## SiteRoutes.distances() shares one whole-site search between callers that ask
## the same question of the same grid (board 4262b55f: a committed build edit
## ran it about 5 times, each a flood fill of the site), and never answers
## from an earlier grid: an edit that changes the open ground, the walls or the
## objects makes the next call search again.
##
## The world case builds the two-gate terminal a build edit meets, with the
## handlers that ask for routes on every graph change (TerminalLayout through
## the passenger sim, GateDesks and ApronStand).

const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ROW := Vector2i(30, 118)
## Open ground above the road edge, straight above its cell (60, 149).
const PROBE := Vector2i(60, 140)
const BLOCK := Vector2i(60, 145)

var _grid: BuildGrid
var _road: Array[Vector2i]


func before_test() -> void:
	SiteRoutes.forget()
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	_road = SiteRoutes.edge_cells(_grid, SITE, SiteDefinition.ROAD_STEP)
	PassengerTestWorld.tracker = self


func after_test() -> void:
	PassengerTestWorld.tracker = null


func _at(dist: PackedInt32Array, cell: Vector2i) -> int:
	return dist[cell.y * _grid.size.x + cell.x]


func test_the_same_question_of_the_same_grid_is_searched_once() -> void:
	var before := SiteRoutes.searches
	var first := SiteRoutes.distances(_grid, SITE, _road)
	var second := SiteRoutes.distances(_grid, SITE, _road.duplicate())
	print(
		(
			"searches %d, probe cell %d and %d"
			% [SiteRoutes.searches - before, _at(first, PROBE), _at(second, PROBE)]
		)
	)
	assert_int(SiteRoutes.searches - before).is_equal(1)
	assert_int(_at(first, PROBE)).is_equal(9)
	assert_array(second).is_equal(first)


func test_other_seeds_are_searched_on_their_own() -> void:
	var before := SiteRoutes.searches
	var to_road := SiteRoutes.distances(_grid, SITE, _road)
	var to_plane := SiteRoutes.distances(
		_grid, SITE, SiteRoutes.edge_cells(_grid, SITE, SiteDefinition.PLANE_STEP)
	)
	var again := SiteRoutes.distances(_grid, SITE, _road)
	print(
		(
			"searches %d, probe cell %d to the road, %d to the plane side"
			% [SiteRoutes.searches - before, _at(to_road, PROBE), _at(to_plane, PROBE)]
		)
	)
	assert_int(SiteRoutes.searches - before).is_equal(2)
	assert_int(_at(to_plane, PROBE)).is_not_equal(_at(to_road, PROBE))
	assert_array(again).is_equal(to_road)


func test_floor_built_in_the_way_is_searched_again_and_lengthens_the_walk() -> void:
	var open := SiteRoutes.distances(_grid, SITE, _road)
	assert_bool(_grid.apply(BuildEdit.paint_floor(BLOCK, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var before := SiteRoutes.searches
	var built := SiteRoutes.distances(_grid, SITE, _road)
	print(
		(
			"probe cell %d open, %d with floor on %s; searches %d"
			% [_at(open, PROBE), _at(built, PROBE), BLOCK, SiteRoutes.searches - before]
		)
	)
	assert_int(SiteRoutes.searches - before).is_equal(1)
	assert_int(_at(open, PROBE)).is_equal(9)
	assert_int(_at(built, PROBE)).is_equal(10)
	assert_int(_at(built, BLOCK)).is_equal(SiteRoutes.UNREACHED)
	assert_array(built).is_equal(SiteRoutes.search(_grid, SITE, _road))


func test_a_wall_in_the_way_is_searched_again() -> void:
	var open := SiteRoutes.distances(_grid, SITE, _road)
	var edit := BuildEdit.place_wall(BLOCK, BuildGrid.Side.SOUTH)
	assert_bool(_grid.apply(edit).ok).is_true()
	var before := SiteRoutes.searches
	var walled := SiteRoutes.distances(_grid, SITE, _road)
	print(
		(
			"probe cell %d open, %d with a wall; searches %d"
			% [_at(open, PROBE), _at(walled, PROBE), SiteRoutes.searches - before]
		)
	)
	assert_int(SiteRoutes.searches - before).is_equal(1)
	assert_int(_at(walled, PROBE)).is_equal(10)
	assert_array(walled).is_equal(SiteRoutes.search(_grid, SITE, _road))


func test_an_edit_undone_gives_the_distances_it_had() -> void:
	var open := SiteRoutes.distances(_grid, SITE, _road)
	assert_bool(_grid.apply(BuildEdit.paint_floor(BLOCK, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var built := SiteRoutes.distances(_grid, SITE, _road)
	assert_bool(_grid.apply(BuildEdit.remove_floor(BLOCK)).ok).is_true()
	var restored := SiteRoutes.distances(_grid, SITE, _road)
	assert_int(_at(built, PROBE)).is_equal(10)
	assert_array(restored).is_equal(open)
	assert_int(_at(restored, PROBE)).is_equal(9)


func test_another_grid_is_not_answered_from_this_ones_search() -> void:
	SiteRoutes.distances(_grid, SITE, _road)
	var other := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(other.apply(BuildEdit.paint_floor(BLOCK, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var dist := SiteRoutes.distances(other, SITE, _road)
	assert_int(dist[BLOCK.y * other.size.x + BLOCK.x]).is_equal(SiteRoutes.UNREACHED)


func test_a_committed_edit_on_the_two_gate_terminal_searches_each_field_once() -> void:
	var grid := SiteGrid.new(SITE)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(24, 125), 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(23, 121), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(24, 116), 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(36000), 4262)
	world.sim.site = SITE
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(grid, world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	var apron := auto_free(ApronStand.new()) as ApronStand
	apron.passengers = world.sim
	apron.bind(grid, SITE, world.flights, gates)
	assert_array(gates.gate_ids()).is_equal(["A", "B"])
	var before := SiteRoutes.searches
	grid.hold_signals()
	var placed := grid.apply(BuildEdit.place_object(&"seat_row", ROW, 0))
	grid.release_signals()
	var made := SiteRoutes.searches - before
	print("one committed edit ran %d searches (road, gate A's door, gate B's door)" % made)
	assert_bool(placed.ok).is_true()
	assert_int(made).is_equal(3)
