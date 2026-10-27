class_name TestRoomRules
extends GdUnitTestSuite
## RoomRules.status(): whether a room is ready, and the notes saying what is
## missing (decision store-mechanics-draw-a-room-then-furnish-it-required-pieces:
## required pieces, a minimum size, a door or open side to the walkway).

const ROOM := Rect2i(2, 2, 5, 4)
const NEEDS_COUNTER := "Needs a counter"
const NEEDS_TABLE := "Needs a table"
const NEEDS_OPENING := "Needs a door or open side to the walkway"
const TOO_SMALL := "Too small: a cafe needs at least 3x3"


## Floor from (1, 1) to (12, 8) on a 14 x 10 grid, so the room has walkway on
## every side.
func _grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(14, 10))
	var edits: Array[BuildEdit] = []
	for y in range(1, 9):
		for x in range(1, 13):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func _room(grid: BuildGrid, rect := ROOM) -> int:
	var result := grid.apply(BuildEdit.place_room(rect, &"cafe"))
	assert_bool(result.ok).is_true()
	return result.room_id


func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing := 0) -> void:
	assert_bool(grid.apply(BuildEdit.place_object(def_id, anchor, facing)).ok).is_true()


## Plain walls on every outer edge of `rect`.
func _wall_ring(grid: BuildGrid, rect: Rect2i, kind := BuildGrid.WallKind.PLAIN) -> void:
	for x in range(rect.position.x, rect.end.x):
		grid.apply(BuildEdit.place_wall(Vector2i(x, rect.position.y), BuildGrid.Side.NORTH, kind))
		grid.apply(BuildEdit.place_wall(Vector2i(x, rect.end.y - 1), BuildGrid.Side.SOUTH, kind))
	for y in range(rect.position.y, rect.end.y):
		grid.apply(BuildEdit.place_wall(Vector2i(rect.position.x, y), BuildGrid.Side.WEST, kind))
		grid.apply(BuildEdit.place_wall(Vector2i(rect.end.x - 1, y), BuildGrid.Side.EAST, kind))


## A counter along the north side (its order spot one row in) and a table
## along the south side.
func _furnish(grid: BuildGrid) -> void:
	_place(grid, &"cafe_counter", Vector2i(3, 2))
	_place(grid, &"cafe_table", Vector2i(3, 5))


func test_an_empty_open_room_needs_a_counter_and_a_table() -> void:
	var grid := _grid()
	var status := RoomRules.status(grid, _room(grid))
	assert_bool(status.ok).is_false()
	assert_array(Array(status.notes)).is_equal([NEEDS_COUNTER, NEEDS_TABLE])
	assert_str(status.headline()).is_equal(NEEDS_COUNTER)
	assert_int(status.seats).is_equal(0)
	assert_str(status.type_name).is_equal("Cafe")


func test_a_furnished_open_room_is_ready() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	var status := RoomRules.status(grid, room_id)
	assert_bool(status.ok).is_true()
	assert_array(Array(status.notes)).is_empty()
	assert_str(status.headline()).is_equal("Ready")
	assert_int(status.seats).is_equal(2)
	# The cafe's base spend is a tuning value: a change to it changes this test.
	assert_int(status.base_spend).is_equal(15)


func test_each_extra_table_adds_two_seats() -> void:
	var grid := _grid()
	var room_id := _room(grid, Rect2i(2, 2, 5, 5))
	_place(grid, &"cafe_counter", Vector2i(3, 2))
	_place(grid, &"cafe_table", Vector2i(3, 4))
	_place(grid, &"cafe_table", Vector2i(3, 6))
	var status := RoomRules.status(grid, room_id)
	assert_bool(status.ok).is_true()
	assert_int(status.seats).is_equal(4)


func test_a_missing_table_is_the_only_note() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_place(grid, &"cafe_counter", Vector2i(3, 2))
	var status := RoomRules.status(grid, room_id)
	assert_array(Array(status.notes)).is_equal([NEEDS_TABLE])


func test_a_room_under_the_minimum_size_says_so_first() -> void:
	var grid := _grid()
	var status := RoomRules.status(grid, _room(grid, Rect2i(2, 2, 2, 5)))
	assert_str(status.notes[0]).is_equal(TOO_SMALL)
	assert_bool(status.ok).is_false()


func test_a_room_walled_all_round_needs_an_opening() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	_wall_ring(grid, ROOM)
	assert_array(Array(RoomRules.status(grid, room_id).notes)).is_equal([NEEDS_OPENING])


func test_a_glass_ring_also_needs_an_opening() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	_wall_ring(grid, ROOM, BuildGrid.WallKind.GLASS)
	assert_array(Array(RoomRules.status(grid, room_id).notes)).is_equal([NEEDS_OPENING])


func test_a_door_in_the_ring_opens_the_room() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	_wall_ring(grid, ROOM)
	var door := grid.apply(
		BuildEdit.place_wall(Vector2i(6, 3), BuildGrid.Side.EAST, BuildGrid.WallKind.DOOR)
	)
	assert_bool(door.ok).is_true()
	assert_bool(RoomRules.status(grid, room_id).ok).is_true()


func test_one_missing_wall_is_an_open_side() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	_wall_ring(grid, ROOM)
	grid.apply(BuildEdit.remove_wall(Vector2i(2, 3), BuildGrid.Side.WEST))
	assert_bool(RoomRules.status(grid, room_id).ok).is_true()


func test_an_opening_onto_bare_ground_or_another_room_does_not_count() -> void:
	# The room fills the floor's west end, so its open west side faces no
	# floor, and the only gap in its walls leads into a second room.
	var grid := _grid()
	var room_id := _room(grid, Rect2i(1, 2, 5, 4))
	var other := Rect2i(6, 2, 4, 4)
	_room(grid, other)
	_place(grid, &"cafe_counter", Vector2i(2, 2))
	_place(grid, &"cafe_table", Vector2i(2, 5))
	for x in range(1, 6):
		grid.apply(BuildEdit.place_wall(Vector2i(x, 2), BuildGrid.Side.NORTH))
		grid.apply(BuildEdit.place_wall(Vector2i(x, 5), BuildGrid.Side.SOUTH))
	assert_array(Array(RoomRules.status(grid, room_id).notes)).is_equal([NEEDS_OPENING])


func test_a_piece_counts_only_with_its_footprint_and_order_spot_inside() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	# Table half outside the east side; counter inside but facing out of the
	# north side, so its order spot is on the walkway.
	_place(grid, &"cafe_table", Vector2i(5, 4))
	_place(grid, &"cafe_counter", Vector2i(4, 2), 2)
	var status := RoomRules.status(grid, room_id)
	assert_array(Array(status.notes)).is_equal([NEEDS_COUNTER, NEEDS_TABLE])
	assert_int(status.seats).is_equal(0)


func test_other_objects_inside_are_ignored() -> void:
	var grid := _grid()
	var room_id := _room(grid)
	_furnish(grid)
	_place(grid, &"seat_row", Vector2i(4, 4))
	assert_bool(RoomRules.status(grid, room_id).ok).is_true()


func test_an_unknown_room_has_no_status() -> void:
	assert_object(RoomRules.status(_grid(), 5)).is_null()
