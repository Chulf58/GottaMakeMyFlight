class_name TestHoldLineTailReach
extends GdUnitTestSuite
## A hold line never walls off its own tail (board 6cfc0e16): each hold cell
## can be reached from a passenger entrance without crossing the line's
## earlier cells, so a walker heading for it as the tail has a way round the
## members ahead of it (decision queue-walkers-route-around-their-own-line-a-
## walker-heading-t).
##
## The grid is 6 x 11 cells. The desk on (3, 1) sends its lane down x = 3 to
## y = 7 and its hold line on to the south wall at y = 10. The desk's east
## cell (4, 1) and a tray table on (5, 1) close the floor east of the lane
## at its north end, so the pocket x = 4..5, y = 2..9 opens only onto the
## line. The entrance is in the north-west corner.


func _grid() -> Array:
	var grid := PassengerTestWorld.floored(Vector2i(6, 11))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(3, 1), 0)
	PassengerTestWorld.place(grid, &"tray_table", Vector2i(5, 1), 0)
	var door := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 0), 0)
	return [grid, desk, door]


## The line indices k for which line[k] cannot be reached from `from` without
## stepping on line[0..k-1].
static func _sealed(grid: BuildGrid, line: Array[Vector2i], from: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for k in line.size():
		if grid.find_path_around(from, line[k], line.slice(0, k)).is_empty():
			out.append(k)
	return out


func test_the_pocket_east_of_the_lane_opens_only_onto_the_line() -> void:
	# Control: the layout seals the pocket off once the lane and the first
	# hold cells down to the wall stand in the way.
	var made := _grid()
	var grid: BuildGrid = made[0]
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var from := layout.door_cell(grid, made[2])
	var lane: Array = layout.lanes[made[1]]
	var down: Array = lane + [Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10)]
	print("entrances %s lane %s" % [layout.passenger_entrances, lane])
	assert_array(layout.passenger_entrances).contains_exactly([made[2]])
	var want: Array[Vector2i] = []
	for y in range(2, 8):
		want.append(Vector2i(3, y))
	assert_array(lane).is_equal(want)
	assert_array(grid.find_path(from, Vector2i(4, 10))).is_not_empty()
	assert_array(grid.find_path_around(from, Vector2i(4, 10), down)).is_empty()
	assert_array(grid.find_path_around(from, Vector2i(2, 10), down)).is_not_empty()


func test_a_hold_line_turns_away_from_a_pocket_it_would_seal() -> void:
	var made := _grid()
	var grid: BuildGrid = made[0]
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var holds: Array = layout.holds[made[1]]
	print("holds %s" % [holds])
	assert_array(holds.slice(0, 5)).is_equal(
		[Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(2, 10), Vector2i(1, 10)]
	)
	for cell: Vector2i in holds:
		assert_int(cell.x).is_less_equal(3)


func test_every_line_cell_is_reachable_past_the_cells_ahead_of_it() -> void:
	var made := _grid()
	var grid: BuildGrid = made[0]
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var line := layout.line_of(made[1])
	var sealed := _sealed(grid, line, layout.door_cell(grid, made[2]))
	print("line %s sealed %s" % [line, sealed])
	assert_int(line.size()).is_equal(TerminalLayout.LANE_SLOTS + TerminalLayout.HOLD_SLOTS)
	assert_array(sealed).is_empty()


func test_a_second_entrance_in_the_pocket_does_not_open_it() -> void:
	# Passengers spawn at the first entrance (PassengerLifecycle), so a
	# later one on the pocket's east wall gives none of them a way in there.
	var made := _grid()
	var grid: BuildGrid = made[0]
	var second := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 5), 1)
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var holds: Array = layout.holds[made[1]]
	var spawn := layout.door_cell(grid, layout.passenger_entrances[0])
	print("entrances %s holds %s" % [layout.passenger_entrances, holds])
	assert_array(layout.passenger_entrances).contains_exactly([made[2], second])
	assert_that(spawn).is_equal(Vector2i(0, 0))
	assert_array(holds.slice(0, 5)).is_equal(
		[Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(2, 10), Vector2i(1, 10)]
	)
	assert_array(_sealed(grid, layout.line_of(made[1]), spawn)).is_empty()


## Removes the entrance `door` and walls its edge again: (0, 0)'s north edge,
## or `cell`'s `side`. The desk's staff spot may have a way in only through
## it and no staff work here, so the staff reach rule is off for the edit.
func _remove_entrance(
	grid: BuildGrid, door: int, cell := Vector2i(0, 0), side := BuildGrid.Side.NORTH
) -> void:
	grid.check_staff_reach = false
	for edit in [BuildEdit.remove_object(door), BuildEdit.place_wall(cell, side)]:
		var result := grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	grid.check_staff_reach = true


func test_with_no_entrance_in_service_the_line_is_a_fresh_layouts() -> void:
	# The line depends on the grid alone: a layout that saw the entrance
	# derives what a new one does once it is gone. With no entrance there is
	# no check, so the line runs into the pocket again (the stated residual).
	var made := _grid()
	var grid: BuildGrid = made[0]
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var with_door := layout.line_of(made[1]).duplicate()
	_remove_entrance(grid, made[2])
	layout.rebuild(grid)
	var fresh := TerminalLayout.new()
	fresh.rebuild(grid)
	var line := layout.line_of(made[1])
	print("entrances %s line %s" % [layout.passenger_entrances, line])
	assert_array(layout.passenger_entrances).is_empty()
	assert_array(line).is_equal(fresh.line_of(made[1]))
	assert_array(line).is_not_equal(with_door)
	assert_bool(line.has(Vector2i(4, 10))).is_true()


func test_the_same_grid_gives_the_same_lines_whatever_its_history() -> void:
	# Grid a: two entrances come and go, with one layout rebuilt after every
	# edit. Grid b: the same end state (the desk and the table, no entrance)
	# built straight away and read by a new layout.
	var a := PassengerTestWorld.floored(Vector2i(6, 11))
	var layout := TerminalLayout.new()
	var door := PassengerTestWorld.place(a, &"entrance_door", Vector2i(0, 0), 0)
	layout.rebuild(a)
	var desk := PassengerTestWorld.place(a, &"checkin_desk", Vector2i(3, 1), 0)
	layout.rebuild(a)
	var second := PassengerTestWorld.place(a, &"entrance_door", Vector2i(5, 5), 1)
	layout.rebuild(a)
	PassengerTestWorld.place(a, &"tray_table", Vector2i(5, 1), 0)
	layout.rebuild(a)
	var walled_in := layout.line_of(desk).duplicate()
	_remove_entrance(a, second, Vector2i(5, 5), BuildGrid.Side.EAST)
	layout.rebuild(a)
	_remove_entrance(a, door)
	layout.rebuild(a)
	var b := PassengerTestWorld.floored(Vector2i(6, 11))
	var b_desk := PassengerTestWorld.place(b, &"checkin_desk", Vector2i(3, 1), 0)
	PassengerTestWorld.place(b, &"tray_table", Vector2i(5, 1), 0)
	var fresh := TerminalLayout.new()
	fresh.rebuild(b)
	print("a %s b %s" % [layout.line_of(desk), fresh.line_of(b_desk)])
	assert_array(layout.passenger_entrances).is_empty()
	assert_array(walled_in.slice(9, 11)).is_equal([Vector2i(2, 10), Vector2i(1, 10)])
	assert_array(layout.line_of(desk)).is_equal(fresh.line_of(b_desk))


func test_without_an_entrance_the_hold_line_is_as_before() -> void:
	# No walker comes in, so there is nothing to keep a way open for: the line
	# turns left into the pocket as the greedy rule says.
	var grid := PassengerTestWorld.floored(Vector2i(6, 11))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(3, 1), 0)
	PassengerTestWorld.place(grid, &"tray_table", Vector2i(5, 1), 0)
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	var holds: Array = layout.holds[desk]
	print("holds %s" % [holds])
	assert_array(layout.passenger_entrances).is_empty()
	assert_array(holds.slice(0, 5)).is_equal(
		[Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10)]
	)
