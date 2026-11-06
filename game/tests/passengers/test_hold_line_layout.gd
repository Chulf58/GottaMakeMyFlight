class_name TestHoldLineLayout
extends GdUnitTestSuite
## The hold line behind each lane (TerminalLayout.holds, line_of()): derived
## from the grid on every rebuild, greedy straight, then left, then right,
## on routable passenger cells, never on a taken or reserved cell or a door
## cell, never crossing a door wall, stations claiming in id order, at most
## HOLD_SLOTS cells, and cut short instead of running back alongside itself.


func _layout(grid: BuildGrid) -> TerminalLayout:
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	return layout


static func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in list:
		out.append(cell)
	return out


func test_a_hold_line_runs_straight_on_behind_the_lane() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(5, 25))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	var layout := _layout(grid)
	var want: Array[Vector2i] = []
	for y in range(8, 20):
		want.append(Vector2i(1, y))
	assert_int(layout.lanes[desk].size()).is_equal(TerminalLayout.LANE_SLOTS)
	assert_int(TerminalLayout.HOLD_SLOTS).is_equal(12)
	assert_array(layout.holds[desk]).is_equal(want)
	assert_array(layout.line_of(desk)).is_equal(_cells(layout.lanes[desk] + want))


func test_a_hold_line_turns_left_then_right_at_a_wall() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(6, 11))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	var want := _cells(
		[
			Vector2i(1, 8),
			Vector2i(1, 9),
			Vector2i(1, 10),
			Vector2i(2, 10),
			Vector2i(3, 10),
			Vector2i(4, 10),
			Vector2i(5, 10),
			Vector2i(5, 9),
			Vector2i(5, 8),
			Vector2i(5, 7),
			Vector2i(5, 6),
			Vector2i(5, 5),
		]
	)
	assert_array(_layout(grid).holds[desk]).is_equal(want)


func test_a_hold_line_is_cut_short_rather_than_run_back_alongside_itself() -> void:
	# Two columns: past the turn at the end the line could only run back up
	# beside itself, so it stops.
	var grid := PassengerTestWorld.floored(Vector2i(2, 10))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(0, 1), 0)
	var holds: Array = _layout(grid).holds[desk]
	assert_array(holds).is_equal(_cells([Vector2i(0, 8), Vector2i(0, 9), Vector2i(1, 9)]))


func test_a_hold_line_stops_at_a_door() -> void:
	var grid := BuildGrid.new(Vector2i(4, 15))
	var edits: Array[BuildEdit] = []
	# The desk's far end, and a way round it to its staff spot (1, 0).
	for cell in [Vector2i(2, 1), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]:
		edits.append(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	for y in 15:
		edits.append(BuildEdit.paint_floor(Vector2i(1, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	var door := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 14), 2)
	# The cell inside the door is its interaction cell, kept clear as well.
	assert_that(grid.interaction_cell(door)).is_equal(Vector2i(1, 13))
	var want: Array[Vector2i] = []
	for y in range(8, 13):
		want.append(Vector2i(1, y))
	assert_array(_layout(grid).holds[desk]).is_equal(want)


func test_a_hold_line_keeps_off_another_station_its_staff_spot_and_lane() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(5, 25))
	var first := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	var second := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 12), 0)
	var layout := _layout(grid)
	var holds: Array = layout.holds[first]
	var spot := StaffSpots.spot_of(grid, second)
	print("staff spot %s interaction %s holds %s" % [spot, grid.interaction_cell(second), holds])
	assert_array(holds.slice(0, 3)).is_equal([Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10)])
	assert_bool(holds.has(spot)).is_false()
	assert_bool(holds.has(grid.interaction_cell(second))).is_false()
	for cell: Vector2i in layout.lanes[second] + layout.holds[second]:
		assert_bool(holds.has(cell)).is_false()


func test_the_lower_station_id_claims_a_contested_hold_cell() -> void:
	# Lanes down x = 1 and x = 4; both hold lines want (4, 9).
	for west_first in [true, false]:
		var grid := PassengerTestWorld.floored(Vector2i(6, 10))
		var ids := {}
		for x in [1, 4] if west_first else [4, 1]:
			ids[x] = PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(x, 1), 0)
		var layout := _layout(grid)
		var lower: int = mini(ids[1], ids[4])
		var higher: int = maxi(ids[1], ids[4])
		print("west first %s holds %s" % [west_first, layout.holds])
		assert_bool((layout.holds[lower] as Array).has(Vector2i(4, 9))).is_true()
		assert_bool((layout.holds[higher] as Array).has(Vector2i(4, 9))).is_false()
		for cell: Vector2i in layout.holds[lower]:
			assert_bool((layout.holds[higher] as Array).has(cell)).is_false()


func test_the_hold_lines_are_deterministic() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var a := _layout(grid)
	var b := _layout(grid)
	a.rebuild(grid)
	assert_dict(a.holds).is_equal(b.holds)
	var total := 0
	for cells: Array in a.holds.values():
		total += cells.size()
	assert_int(total).is_greater(0)


func test_reference_hold_lines_keep_every_rule() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var layout := _layout(grid)
	var banned := {}
	for id in grid.object_ids():
		banned[grid.interaction_cell(id)] = "interaction"
		banned[StaffSpots.spot_of(grid, id)] = "staff spot"
	for door in layout.entrances + layout.exits:
		banned[layout.door_cell(grid, door)] = "door"
	for cells: Array in layout.passages.values():
		for cell: Vector2i in cells:
			banned[cell] = "passage"
	for arch in layout.security_lanes.complete_arches():
		for cell in SecurityLanes.kept_clear_cells(layout.security_lanes.lane(arch)):
			banned[cell] = "kept clear"
	for cells: Array in layout.lanes.values():
		for cell: Vector2i in cells:
			banned[cell] = "lane"
	var seen := {}
	var checked := 0
	for station: int in layout.holds:
		var line: Array = layout.line_of(station)
		var own := {}
		for cell: Vector2i in line:
			own[cell] = true
		var holds: Array = layout.holds[station]
		assert_int(holds.size()).is_less_equal(TerminalLayout.HOLD_SLOTS)
		for i in holds.size():
			var cell: Vector2i = holds[i]
			var before: Vector2i = line[layout.lanes[station].size() + i - 1]
			assert_str(banned.get(cell, "")).is_equal("")
			assert_bool(seen.has(cell)).is_false()
			seen[cell] = true
			assert_bool(grid.is_passenger_cell(cell)).is_true()
			assert_int(absi(cell.x - before.x) + absi(cell.y - before.y)).is_equal(1)
			assert_bool(grid.can_passenger_route(before, cell)).is_true()
			var side := BuildGrid.SIDE_STEP.find(cell - before)
			assert_bool(grid.wall_kind(before, side) == BuildGrid.WallKind.DOOR).is_false()
			for step: Vector2i in BuildGrid.SIDE_STEP:
				var near := cell + step
				if near != before and own.has(near) and line.find(near) < line.find(cell):
					fail("hold cell %s runs alongside its own line at %s" % [cell, near])
			checked += 1
	assert_int(checked).is_greater(0)


func test_no_standing_spot_is_on_a_hold_cell() -> void:
	# The turning line of the 6 x 11 hall, with an exit door whose standing
	# spots (no seats: they start at the exit) reach every cell.
	var grid := PassengerTestWorld.floored(Vector2i(6, 11))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(5, 0), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.standing.rebuild(world.sim)
	var holds: Array = world.sim.layout.holds[desk]
	var on_hold := 0
	var beside_hold := 0
	for spot: int in world.sim.standing._ids:
		var cell := world.sim.standing.cell_of(spot)
		on_hold += int(holds.has(cell))
		for step: Vector2i in BuildGrid.SIDE_STEP:
			beside_hold += int(holds.has(cell + step))
	var spots := world.sim.standing._ids.size()
	print("spots %d, on a hold cell %d, beside one %d" % [spots, on_hold, beside_hold])
	assert_int(holds.size()).is_equal(12)
	assert_int(beside_hold).is_greater(0)
	assert_int(on_hold).is_equal(0)
	world.free_all()
