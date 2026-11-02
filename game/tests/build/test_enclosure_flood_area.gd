class_name TestEnclosureFloodArea
extends GdUnitTestSuite
## BuildGrid floods from outside only over the part of the grid anything was
## built on, one cell wider (BuildGrid.flood_area(), TerminalEnclosure.
## outside_within()), not the whole grid. That must find exactly the indoor
## cells the whole-grid flood finds: after every edit of a seeded random
## sequence of floors, walls and wall removals on a 40x40 grid, every cell's
## is_indoor() is checked against TerminalEnclosure.outside_cells() of the
## same walls. Rooms are built in a corner on the grid border and in the
## middle, so the flood area's sides fall both on the border and inside it.
## A clone and a snapshot load carry the same answer.

const SIZE := Vector2i(40, 40)
const SEED := 20261101
const STEPS := 400


## Every cell where is_indoor() disagrees with the whole-grid flood, as text.
static func _disagreements(grid: BuildGrid) -> PackedStringArray:
	var h: PackedByteArray = grid.get("_h_walls")
	var v: PackedByteArray = grid.get("_v_walls")
	var outside := TerminalEnclosure.outside_cells(grid, h, v)
	var out := PackedStringArray()
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			var want := (
				grid.floor_at(cell) != BuildGrid.FLOOR_NONE and outside[x + y * grid.size.x] == 0
			)
			if grid.is_indoor(cell) != want:
				out.append("%s indoor %s want %s" % [cell, grid.is_indoor(cell), want])
	return out


static func _indoor_count(grid: BuildGrid) -> int:
	var count := 0
	for y in grid.size.y:
		for x in grid.size.x:
			if grid.is_indoor(Vector2i(x, y)):
				count += 1
	return count


## A walled room of floor over `area`.
static func _room(grid: BuildGrid, area: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)


func test_the_bounded_flood_matches_the_whole_grid_flood_after_every_edit() -> void:
	var grid := BuildGrid.new(SIZE)
	_room(grid, Rect2i(0, 0, 6, 5))
	_room(grid, Rect2i(18, 20, 7, 6))
	assert_int(_indoor_count(grid)).is_equal(6 * 5 + 7 * 6)
	assert_array(_disagreements(grid)).is_empty()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var applied := 0
	var flips := 0
	var last := _indoor_count(grid)
	for step in STEPS:
		# Mostly near the two rooms, sometimes anywhere, so the area grows.
		var cell := Vector2i(rng.randi_range(0, 27), rng.randi_range(0, 30))
		if rng.randf() < 0.1:
			cell = Vector2i(rng.randi_range(0, SIZE.x - 1), rng.randi_range(0, SIZE.y - 1))
		var side := rng.randi_range(0, 3)
		var edit: BuildEdit
		match rng.randi_range(0, 3):
			0:
				edit = BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)
			1:
				edit = BuildEdit.place_wall(cell, side)
			2:
				edit = BuildEdit.remove_wall(cell, side)
			3:
				edit = BuildEdit.remove_floor(cell)
		if grid.apply(edit).ok:
			applied += 1
		var now := _indoor_count(grid)
		if now != last:
			flips += 1
			last = now
		var wrong := _disagreements(grid)
		(
			assert_array(wrong)
			. override_failure_message("step %d %s: %s" % [step, cell, wrong])
			. is_empty()
		)
		if not wrong.is_empty():
			return
	print(
		(
			"flood area: %d edits applied, indoor count changed %d times, area %s"
			% [applied, flips, grid.flood_area()]
		)
	)
	# The sequence did real work: edits went through and the enclosure changed.
	assert_int(applied).is_greater(100)
	assert_int(flips).is_greater(5)
	var copy := grid.clone()
	assert_array(_disagreements(copy)).is_empty()
	var loaded := BuildGrid.new(SIZE)
	assert_bool(loaded.from_snapshot(grid.to_snapshot())).is_true()
	assert_array(_disagreements(loaded)).is_empty()
	assert_that(loaded.flood_area()).is_equal(copy.flood_area())


func test_a_new_grid_floods_nothing_and_every_cell_is_outside() -> void:
	var grid := BuildGrid.new(SIZE)
	assert_that(grid.flood_area()).is_equal(Rect2i())
	grid.apply(BuildEdit.paint_floor(Vector2i(5, 5), BuildGrid.FLOOR_TILE, 1))
	assert_that(grid.flood_area()).is_equal(Rect2i(4, 4, 3, 3))
	assert_bool(grid.is_indoor(Vector2i(5, 5))).is_false()


func test_walls_drawn_round_bare_ground_close_in_floor_painted_later() -> void:
	# The walls come first and the floor after: the floor never changes the
	# flood, so the cells the walls close in must already be known as inside.
	var grid := BuildGrid.new(SIZE)
	var area := Rect2i(30, 30, 3, 3)
	var edits: Array[BuildEdit] = []
	for x in range(area.position.x, area.end.x):
		edits.append(BuildEdit.place_wall(Vector2i(x, area.position.y), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, area.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(area.position.y, area.end.y):
		edits.append(BuildEdit.place_wall(Vector2i(area.position.x, y), BuildGrid.Side.WEST))
		edits.append(BuildEdit.place_wall(Vector2i(area.end.x - 1, y), BuildGrid.Side.EAST))
	grid.apply_batch(edits)
	grid.apply(BuildEdit.paint_floor(Vector2i(31, 31), BuildGrid.FLOOR_TILE, 1))
	assert_bool(grid.is_indoor(Vector2i(31, 31))).is_true()
	assert_array(_disagreements(grid)).is_empty()
