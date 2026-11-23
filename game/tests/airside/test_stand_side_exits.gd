class_name TestStandSideExits
extends GdUnitTestSuite
## Stands for exits in the west and east walls (slice S5 of design airside-
## all-around-technical-design-one-route-source-per-con, building user ruling
## airside-all-around-the-terminal-except-the-road-side-a-gate): for_exit()
## gives a west exit a west stand and an east exit an east one, and a road-side
## (south-facing) exit none; place() breaks a walk tie by the shorter way to the
## stand's own lane, which for north stands is the northmost wall line as
## before; and a side stand's private rects stop at its own side lane band and
## stay south of the north lane band, on every row of the grid.

const SITE := preload("res://build/terminal_site.tres")
const SHELL_OFFSET := Vector2i(85, 110)
## Cells of the starter shell (ReferenceTerminal coordinates), moved onto the
## grid by SHELL_OFFSET so both west and east side stands clear the road.
const WEST_CELL := Vector2i(10, 4)
const EAST_CELL := Vector2i(21, 4)
const SOUTH_CELL := Vector2i(12, 17)

var _base: BuildGrid
var _grid: BuildGrid


func before() -> void:
	_base = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(StarterShell.place(_base, SHELL_OFFSET)).is_true()


func before_test() -> void:
	_grid = _base.clone()


## Opens the shell's wall at `cell` (shell coordinates) on `side` and puts an
## exit door there facing `facing`; its object id.
func _add_exit(cell: Vector2i, side: int, facing: int) -> int:
	var at := cell + SHELL_OFFSET
	assert_bool(_grid.apply(BuildEdit.remove_wall(at, side)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", at, facing))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return placed.object_id


func test_a_west_and_an_east_exit_get_their_side_stands() -> void:
	var west := _add_exit(WEST_CELL, BuildGrid.Side.WEST, 3)
	var east := _add_exit(EAST_CELL, BuildGrid.Side.EAST, 1)
	var on_west := StandPlacement.for_exit(_grid, west)
	var on_east := StandPlacement.for_exit(_grid, east)
	print("west exit %d stand %s, east exit %d stand %s" % [west, on_west, east, on_east])
	assert_dict(on_west).is_equal(
		StandPlacement.for_cell(_grid, WEST_CELL + SHELL_OFFSET, west, StandPlacement.WEST)
	)
	assert_dict(on_east).is_equal(
		StandPlacement.for_cell(_grid, EAST_CELL + SHELL_OFFSET, east, StandPlacement.EAST)
	)
	assert_str(StandPlacement.side_of(on_west)).is_equal(StandPlacement.WEST)
	assert_str(StandPlacement.side_of(on_east)).is_equal(StandPlacement.EAST)
	# Control: the shell's own exit still gives its north stand.
	var north := _grid.object_at(ReferenceTerminal.EXIT_CELL + SHELL_OFFSET)
	assert_dict(StandPlacement.for_exit(_grid, north)).is_equal(
		StandPlacement.for_cell(
			_grid, ReferenceTerminal.EXIT_CELL + SHELL_OFFSET, north, StandPlacement.NORTH
		)
	)


func test_an_exit_facing_the_road_has_no_stand() -> void:
	var south := _add_exit(SOUTH_CELL, BuildGrid.Side.SOUTH, 2)
	var record := _grid.get_object(south)
	print("south exit %d record %s" % [south, record])
	assert_vector(DoorPlacement.back_step(record["facing"])).is_equal(SiteDefinition.ROAD_STEP)
	assert_dict(StandPlacement.for_exit(_grid, south)).is_empty()


## A west and an east exit in the same row of the shell walk the same way out
## to their plane doors (each door straight out from its exit), so the walk
## ties. The east exit has the lower id, so a tie on the id alone would pick
## it; the west stand's way to its lane is the shorter (the shell stands west
## of the middle), and wins. The shell's north exit is walled up first, so the
## shell stays closed (indoor) and only the two side exits are candidates.
func test_a_walk_tie_goes_to_the_stand_with_the_shorter_way_to_its_lane() -> void:
	var at := ReferenceTerminal.EXIT_CELL + SHELL_OFFSET
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(at))).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_wall(at, BuildGrid.Side.NORTH)).ok).is_true()
	var east := _add_exit(EAST_CELL, BuildGrid.Side.EAST, 1)
	var west := _add_exit(WEST_CELL, BuildGrid.Side.WEST, 3)
	assert_int(east).is_less(west)
	var on_west := StandPlacement.for_exit(_grid, west)
	var on_east := StandPlacement.for_exit(_grid, east)
	var walk_west := StandPlacement.walk_length(StandPlacement.walk_of(_grid, SITE, west, on_west))
	var walk_east := StandPlacement.walk_length(StandPlacement.walk_of(_grid, SITE, east, on_east))
	var lane_west := float(StandPlacement.north_twin(on_west)["wall_z"])
	var lane_east := float(StandPlacement.north_twin(on_east)["wall_z"])
	print(
		(
			"walks west %.3f east %.3f m, twin wall_z west %.2f east %.2f"
			% [walk_west, walk_east, lane_west, lane_east]
		)
	)
	assert_int(roundi(walk_west * 1000.0)).is_equal(roundi(walk_east * 1000.0))
	assert_float(lane_west).is_less(lane_east)
	var result := StandPlacement.place(_grid, SITE, {})
	print("place: %s" % [result])
	assert_str(result["status"]).is_equal(StandPlacement.OK)
	assert_int(result["stand"]["exit"]).is_equal(west)
	# The live exit still comes before the way to the lane.
	assert_int(StandPlacement.place(_grid, SITE, on_east)["stand"]["exit"]).is_equal(east)


## Every west and east stand down the grid's rows, at the first site's west
## and east edges: each private rect stays south of the north lane band, and
## reaches out to its own side lane's band and no further.
func test_side_private_rects_stop_at_their_own_lane_band_on_every_row() -> void:
	var centre := SITE.centre_rect()
	var west_cell := _grid.world_to_cell(Vector3(centre.position.x + 0.5, 0.0, 0.0)).x
	var east_cell := _grid.world_to_cell(Vector3(centre.end.x - 0.5, 0.0, 0.0)).x
	var lane_south := StandPlacement.lane_zone().end.y
	var band := lane_south - StandPlacement.TAXI_LANE_Z
	var checked := 0
	var north_most := INF
	var west_reach := INF
	var east_reach := -INF
	for y in _grid.size.y:
		var stands := [
			StandPlacement.for_cell(_grid, Vector2i(west_cell, y), 0, StandPlacement.WEST),
			StandPlacement.for_cell(_grid, Vector2i(east_cell, y), 0, StandPlacement.EAST),
		]
		for stand: Dictionary in stands:
			for rect in GateDesks.private_rects(stand):
				north_most = minf(north_most, rect.position.y)
				if StandPlacement.side_of(stand) == StandPlacement.WEST:
					west_reach = minf(west_reach, rect.position.x)
				else:
					east_reach = maxf(east_reach, rect.end.x)
				checked += 1
	print(
		(
			"%d rects: northmost z %.2f (lane band south %.2f), west reach x %.2f, east %.2f"
			% [checked, north_most, lane_south, west_reach, east_reach]
		)
	)
	assert_int(checked).is_greater(2 * _grid.size.y)
	assert_float(north_most).is_greater(lane_south)
	assert_float(west_reach).is_equal_approx(-StandPlacement.SIDE_LANE_X + band, 0.001)
	assert_float(east_reach).is_equal_approx(StandPlacement.SIDE_LANE_X - band, 0.001)
