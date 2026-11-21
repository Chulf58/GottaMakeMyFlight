class_name BagRoomKit
extends RefCounted
## A ready bag room on a grid that has none, for tests that need bags to be
## checked in without building a belt line: floor, the room and one belt end
## in its top left cell. A desk with no belt to this room still misses its bags
## (NO_BELT), and a belt that does not reach it has NO_ROUTE.

const AREA := Rect2i(2, 2, 3, 3)


## Adds the room on `grid` and returns its id. The cells (and the ring of floor
## round them) must be outside any layout already on the grid.
static func add(grid: BuildGrid, area := AREA) -> int:
	# One ring of floor round the room is its open side to the walkway.
	var floor_area := area.grow(1)
	for y in range(floor_area.position.y, floor_area.end.y):
		for x in range(floor_area.position.x, floor_area.end.x):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var result := grid.apply(BuildEdit.place_room(area, &"bag_room"))
	assert(result.ok, "test bag room refused: %s" % result.reason_text())
	PassengerTestWorld.place(grid, &"baggage_belt_end", area.position, 0)
	var room_id := grid.room_at(area.position)
	assert(RoomRules.status(grid, room_id).ok, "test bag room is not ready")
	return room_id


## Marks a ready 4x3 bag room inside ReferenceTerminal and connects Desk 2's
## outlet (15, 10) east around its staff spot (14, 10) to the room's end at
## (16, 13), leaving Desk 1 unconnected (NO_BELT) while activating checked-bag
## handling. Returns the room id.
static func connect_reference_desk2(grid: BuildGrid) -> int:
	var room_rect := Rect2i(13, 13, 4, 3)
	var result := grid.apply(BuildEdit.place_room(room_rect, &"bag_room"))
	assert(result.ok, "reference bag room refused: %s" % result.reason_text())
	for seg in [
		[Vector2i(15, 10), Vector2i(16, 10)],
		[Vector2i(16, 10), Vector2i(16, 13)],
	]:
		var plan := BeltShaper.plan_line(grid, seg[0], seg[1], 0)
		assert(plan.result.ok, "reference belt refused: %s" % plan.result.reason_text())
		for applied in grid.apply_batch(plan.edits):
			assert(applied.ok, "reference belt edit refused: %s" % applied.reason_text())
	var room_id := grid.room_at(room_rect.position)
	assert(RoomRules.status(grid, room_id).ok, "reference bag room is not ready")
	return room_id
