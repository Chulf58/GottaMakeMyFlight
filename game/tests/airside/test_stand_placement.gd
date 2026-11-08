class_name TestStandPlacement
extends GdUnitTestSuite
## Where the plane stand goes (StandPlacement, decision plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, point 2): straight out from the
## best north-facing exit with a clear aircraft route and a passenger walk to
## the door, ranked by that walk, then the live exit, then northmost, then the
## lowest id; 'unavailable' with the live stand kept when there is none; a
## walk over 30 m is warned about.

const SITE := preload("res://build/terminal_site.tres")
## The starter shell's exit on the site grid: ReferenceTerminal.EXIT_CELL
## moved 110 rows.
const STARTER_EXIT := Vector2i(20, 112)
## A second exit in the shell's north wall, 9 m west of the starter's.
const WEST_EXIT := Vector2i(11, 112)

var _grid: BuildGrid


func before_test() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()


func _exit_at(cell: Vector2i) -> int:
	return _grid.object_at(cell)


func _paint(cells: Array[Vector2i]) -> void:
	for cell in cells:
		assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()


## Opens the shell's wall at `cell` on `side` and puts an exit door there.
func _add_exit(cell: Vector2i, side: int, facing: int) -> int:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, side)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", cell, facing))
	assert_bool(placed.ok).is_true()
	return placed.object_id


func _place(live: Dictionary) -> Dictionary:
	var result := StandPlacement.place(_grid, SITE, live)
	print(
		(
			"place: %s exit %d x %.2f wall %.2f walk %.2f m longest %.2f m warning %s"
			% [
				result["status"],
				result["stand"].get("exit", -1),
				result["stand"].get("x", 0.0),
				result["stand"].get("wall_z", 0.0),
				result["walk_m"],
				result["longest_walk_m"],
				result["warning"]
			]
		)
	)
	return result


func test_the_starter_stand_sits_nose_in_at_the_starter_exit_with_its_door_on_the_exit_line(
) -> void:
	var exit := _exit_at(STARTER_EXIT)
	var result := _place(StandPlacement.starter_stand(_grid, SITE))
	var stand: Dictionary = result["stand"]
	assert_str(result["status"]).is_equal(StandPlacement.OK)
	assert_int(stand["exit"]).is_equal(exit)
	var at := StandPlacement.stand_point(stand)
	var door := StandPlacement.door_point(stand)
	print(
		(
			"stand %s door %s pushback end %s lane %s"
			% [at, door, StandPlacement.pushback_end(stand), StandPlacement.lane_join(stand)]
		)
	)
	# Exit centre x -22.5, wall line z -98 (its world place before the grid grew).
	# The nose 2.2 m off the wall (StandPlacement.NOSE_GAP_M, was 2.3 m), so
	# the stand and door sit 0.1 m nearer the wall than before.
	assert_vector(door).is_equal_approx(Vector3(-22.5, 0.0, -104.4), Vector3.ONE * 0.001)
	assert_vector(at).is_equal_approx(Vector3(-26.0, 0.0, -114.9), Vector3.ONE * 0.001)
	assert_float(at.z + StandPlacement.NOSE_M).is_equal_approx(-98.0 - 2.2, 0.001)
	assert_float(result["walk_m"]).is_between(6.9, 7.3)
	assert_bool(result["warning"]).is_false()
	assert_bool(StandPlacement.aircraft_clear(_grid, SITE, stand)).is_true()


func test_a_building_in_the_starter_column_slides_the_line_to_the_other_exit() -> void:
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.NORTH, 0)
	var live := StandPlacement.starter_stand(_grid, SITE)
	assert_int(_place(live)["stand"]["exit"]).is_equal(_exit_at(STARTER_EXIT))
	# Floor at x -18, z -180: on the starter stand's way north, beside the
	# west exit's.
	_paint([Vector2i(25, 30)] as Array[Vector2i])
	var result := _place(live)
	assert_str(result["status"]).is_equal(StandPlacement.OK)
	assert_int(result["stand"]["exit"]).is_equal(west)
	assert_float(result["stand"]["x"]).is_equal_approx(-31.5, 0.001)


func test_a_building_between_exit_and_door_rejects_the_candidate_on_passenger_reach() -> void:
	var exit := _exit_at(STARTER_EXIT)
	var live := StandPlacement.for_exit(_grid, exit)
	# Floor round the exit's outward cell (20, 111), in the gap before the nose.
	_paint([Vector2i(19, 111), Vector2i(21, 111), Vector2i(20, 110)] as Array[Vector2i])
	var clear := StandPlacement.aircraft_clear(_grid, SITE, live)
	var walk := StandPlacement.walk_of(_grid, SITE, exit, live)
	print("aircraft clear %s, walk points %d" % [clear, walk.size()])
	assert_bool(clear).is_true()
	assert_array(walk).is_empty()
	var result := _place(live)
	assert_str(result["status"]).is_equal(StandPlacement.UNAVAILABLE)


func test_the_deepest_legal_stand_pushes_back_short_of_the_taxi_lane() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	# The reference terminal with its exit on the grid's north row.
	assert_bool(ReferenceTerminal.build(_grid, Vector2i(0, -2))).is_true()
	var exit := _exit_at(Vector2i(20, 0))
	var result := _place({})
	var stand: Dictionary = result["stand"]
	var back := StandPlacement.pushback_end(stand)
	print("deepest: stand %s pushback end %s" % [StandPlacement.stand_point(stand), back])
	assert_str(result["status"]).is_equal(StandPlacement.OK)
	assert_int(stand["exit"]).is_equal(exit)
	assert_float(stand["wall_z"]).is_equal_approx(-210.0, 0.001)
	# 28.1 m short of the lane's centreline (0.1 m before the lane moved from z
	# -256 to -284): the nose sits 2.2 m off the wall so
	# the parked tail clears the shared lane zone (StandPlacement.NOSE_GAP_M).
	assert_float(back.z).is_equal_approx(StandPlacement.TAXI_LANE_Z + 28.1, 0.001)
	assert_float(result["walk_m"]).is_between(6.9, 7.3)


func test_two_exits_the_shorter_walk_wins_and_a_tie_keeps_the_live_exit() -> void:
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.NORTH, 0)
	var starter := _exit_at(STARTER_EXIT)
	var on_starter := StandPlacement.for_exit(_grid, starter)
	var on_west := StandPlacement.for_exit(_grid, west)
	# A tie on the walk keeps whichever exit is live.
	assert_int(_place(on_starter)["stand"]["exit"]).is_equal(starter)
	assert_int(_place(on_west)["stand"]["exit"]).is_equal(west)
	# Floor straight out of the starter exit makes its walk go round it.
	_paint([Vector2i(20, 110)] as Array[Vector2i])
	var longer := StandPlacement.walk_length(
		StandPlacement.walk_of(_grid, SITE, starter, on_starter)
	)
	var shorter := StandPlacement.walk_length(StandPlacement.walk_of(_grid, SITE, west, on_west))
	print("starter walk %.2f m, west walk %.2f m" % [longer, shorter])
	assert_float(longer).is_greater(shorter)
	assert_int(_place(on_starter)["stand"]["exit"]).is_equal(west)


func test_no_north_exit_gives_unavailable_and_keeps_the_live_stand() -> void:
	var live := StandPlacement.starter_stand(_grid, SITE)
	assert_bool(_grid.apply(BuildEdit.remove_object(_exit_at(STARTER_EXIT))).ok).is_true()
	var result := _place(live)
	assert_str(result["status"]).is_equal(StandPlacement.UNAVAILABLE)
	assert_that(result["stand"]).is_equal(live)


func test_a_walk_over_30_m_warns_and_refuses_nothing() -> void:
	var control := _place(StandPlacement.starter_stand(_grid, SITE))
	assert_float(control["longest_walk_m"]).is_less(StandPlacement.WALK_WARNING_M)
	assert_bool(control["warning"]).is_false()
	# An exit in the south wall walks round the shell to the plane door.
	_add_exit(Vector2i(12, 127), BuildGrid.Side.SOUTH, 2)
	var result := _place(StandPlacement.starter_stand(_grid, SITE))
	assert_str(result["status"]).is_equal(StandPlacement.OK)
	assert_int(result["stand"]["exit"]).is_equal(_exit_at(STARTER_EXIT))
	assert_float(result["longest_walk_m"]).is_greater(StandPlacement.WALK_WARNING_M)
	assert_bool(result["warning"]).is_true()
