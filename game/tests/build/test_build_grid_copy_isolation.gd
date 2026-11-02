class_name TestBuildGridCopyIsolation
extends GdUnitTestSuite
## A trial copy of the grid (BuildGrid.clone() and cropped()) owns its object
## records, rooms and staff spots: removing an object, reshaping a belt,
## resizing or removing a room on the copy leaves the grid it came from as it
## was. A belt reshape changes its record in place, so a record shared with
## the source would change the source too.
##
## cropped() also gives the grid that the same edits build in the crop's frame
## (the same snapshot, indoor cells and paths) without a load's work: the
## passenger A* graph waits for the first path.

const SIZE := Vector2i(24, 24)
const FLOORED := Rect2i(2, 2, 18, 18)
const BAG_ROOM := Rect2i(3, 3, 4, 4)
const CAFE := Rect2i(10, 3, 4, 3)
const OTHER_CAFE := Rect2i(10, 10, 4, 3)
const BELT_A := Vector2i(4, 4)
const BELT_B := Vector2i(5, 4)
const DESK := Vector2i(4, 14)
const CROP := Rect2i(1, 1, 20, 20)

var _grid: BuildGrid
var _belt_a := 0
var _belt_b := 0
var _desk := 0
var _cafe := 0
var _other_cafe := 0
var _bag_room := 0


func before() -> void:
	_grid = BuildGrid.new(SIZE)
	_build(_grid, Vector2i.ZERO)


## The test layout on `grid`, every cell moved by `shift`: floor, a bag room
## with two belt pieces, two cafes and a check-in desk. Keeps the ids.
func _build(grid: BuildGrid, shift: Vector2i) -> void:
	grid.check_staff_reach = false
	var floors: Array[BuildEdit] = []
	for y in range(FLOORED.position.y, FLOORED.end.y):
		for x in range(FLOORED.position.x, FLOORED.end.x):
			floors.append(BuildEdit.paint_floor(Vector2i(x, y) + shift, BuildGrid.FLOOR_TILE, 1))
	# Walls all round, so the floor is indoor and passengers walk it.
	for x in range(FLOORED.position.x, FLOORED.end.x):
		floors.append(BuildEdit.place_wall(Vector2i(x, FLOORED.position.y) + shift, 0))
		floors.append(BuildEdit.place_wall(Vector2i(x, FLOORED.end.y - 1) + shift, 2))
	for y in range(FLOORED.position.y, FLOORED.end.y):
		floors.append(BuildEdit.place_wall(Vector2i(FLOORED.position.x, y) + shift, 3))
		floors.append(BuildEdit.place_wall(Vector2i(FLOORED.end.x - 1, y) + shift, 1))
	for result in grid.apply_batch(floors):
		assert_bool(result.ok).is_true()
	_bag_room = _applied(BuildEdit.place_room(_moved(BAG_ROOM, shift), &"bag_room"), grid).room_id
	_cafe = _applied(BuildEdit.place_room(_moved(CAFE, shift), &"cafe"), grid).room_id
	_other_cafe = _applied(BuildEdit.place_room(_moved(OTHER_CAFE, shift), &"cafe"), grid).room_id
	_belt_a = _applied(BuildEdit.place_object(&"baggage_belt", BELT_A + shift, 1), grid).object_id
	_belt_b = _applied(BuildEdit.place_object(&"baggage_belt", BELT_B + shift, 1), grid).object_id
	_desk = _applied(BuildEdit.place_object(&"checkin_desk", DESK + shift, 0), grid).object_id


static func _moved(rect: Rect2i, shift: Vector2i) -> Rect2i:
	return Rect2i(rect.position + shift, rect.size)


func _applied(edit: BuildEdit, on_grid: BuildGrid) -> BuildResult:
	var result := on_grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


## The grid the layout builds in CROP's frame.
func _built_in_crop() -> BuildGrid:
	var origin := _grid.origin + Vector3(CROP.position.x, 0.0, CROP.position.y)
	var grid := BuildGrid.new(CROP.size, origin)
	_build(grid, -CROP.position)
	return grid


## Removes and reshapes objects and rooms on `copy` (cells moved by `shift`),
## then checks the source is unchanged: snapshot, records, rooms and spots.
func _mutate_and_check(copy: BuildGrid, shift: Vector2i) -> void:
	var before_snapshot := _grid.to_snapshot()
	var desk_spot := StaffSpots.spot_of(_grid, _desk)
	assert_that(desk_spot).is_not_equal(BuildObjectDef.NO_CELL)
	_applied(BuildEdit.reshape_belt(BELT_A + shift, &"baggage_belt_corner", 2), copy)
	_applied(BuildEdit.remove_object(_belt_b), copy)
	_applied(BuildEdit.remove_object(_desk), copy)
	var wider := Rect2i(CAFE.position + shift, CAFE.size + Vector2i(2, 1))
	_applied(BuildEdit.resize_room(_cafe, wider), copy)
	_applied(BuildEdit.remove_room(_other_cafe), copy)
	_applied(BuildEdit.place_object(&"checkin_desk", DESK + Vector2i(6, 0) + shift, 0), copy)
	print(
		(
			"copy: belt %s, %d objects, %d rooms; source: belt %s, %d objects, %d rooms"
			% [
				copy.get_object(_belt_a)["def"],
				copy.object_ids().size(),
				copy.room_ids().size(),
				_grid.get_object(_belt_a)["def"],
				_grid.object_ids().size(),
				_grid.room_ids().size(),
			]
		)
	)
	assert_str(str(copy.get_object(_belt_a)["def"])).is_equal("baggage_belt_corner")
	assert_str(str(_grid.get_object(_belt_a)["def"])).is_equal("baggage_belt")
	assert_int(_grid.get_object(_belt_a)["facing"]).is_equal(1)
	assert_bool(_grid.get_object(_belt_b).is_empty()).is_false()
	assert_bool(_grid.get_object(_desk).is_empty()).is_false()
	assert_that(StaffSpots.spot_of(_grid, _desk)).is_equal(desk_spot)
	assert_array(_grid.room_ids()).contains([_cafe, _other_cafe, _bag_room])
	assert_dict(_grid.to_snapshot()).is_equal(before_snapshot)


func test_a_clone_owns_its_objects_rooms_and_staff_spots() -> void:
	_mutate_and_check(_grid.clone(), Vector2i.ZERO)


func test_a_cropped_copy_owns_its_objects_rooms_and_staff_spots() -> void:
	_mutate_and_check(_grid.cropped(CROP), -CROP.position)


func test_a_cropped_copy_is_the_grid_the_same_edits_build_in_its_frame() -> void:
	var built := _built_in_crop()
	var copy := _grid.cropped(CROP)
	assert_object(copy).is_instanceof(BuildGrid)
	assert_that(copy.origin).is_equal(built.origin)
	assert_dict(copy.to_snapshot()).is_equal(built.to_snapshot())
	for cell in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(12, 12), Vector2i(19, 19)]:
		assert_bool(copy.is_indoor(cell)).is_equal(built.is_indoor(cell))
	var from := Vector2i(2, 2)
	var to := Vector2i(15, 15)
	assert_array(copy.find_path(from, to)).is_not_empty()
	assert_array(copy.find_path(from, to)).is_equal(built.find_path(from, to))


## The work a load does and a cropped copy skips: a load of the same crop
## builds the passenger A* graph at once (the control), a cropped copy builds
## none until a path is asked for.
func test_a_cropped_copy_builds_no_path_graph_until_a_path_is_asked_for() -> void:
	var loaded := BuildGrid.new(CROP.size)
	assert_bool(loaded.from_snapshot(_built_in_crop().to_snapshot())).is_true()
	var copy := _grid.cropped(CROP)
	print(
		(
			"A* graph built: by the load %s, by the cropped copy %s"
			% [loaded._pathing != null, copy._pathing != null]
		)
	)
	assert_object(loaded._pathing).is_not_null()
	assert_object(copy._pathing).is_null()
	copy.find_path(Vector2i(2, 2), Vector2i(15, 15))
	assert_object(copy._pathing).is_not_null()
