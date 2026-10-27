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
