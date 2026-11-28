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
	# Floor around the room on west, east and south; keep the north apron edge clear
	# so the Roll-Up Bay Door faces open apron.
	var floor_area := area.grow(1)
	for y in range(floor_area.position.y, floor_area.end.y):
		for x in range(floor_area.position.x, floor_area.end.x):
			if y < area.position.y and x >= area.position.x and x < area.end.x:
				continue
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var result := grid.apply(BuildEdit.place_room(area, &"bag_room"))
	assert(result.ok, "test bag room refused: %s" % result.reason_text())
	var belt_cell := (
		area.position if area.size.x >= 3 else Vector2i(area.position.x, area.position.y + 1)
	)
	PassengerTestWorld.place(grid, &"baggage_belt_end", belt_cell, 0)
	var bay_anchor := Vector2i(area.end.x - 2, area.position.y)
	for y in range(0, area.position.y):
		for x in range(bay_anchor.x, bay_anchor.x + 2):
			if grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				grid.apply(BuildEdit.remove_floor(Vector2i(x, y)))
	var bay_res := DoorPlacement.check(
		grid, BuildEdit.place_object(&"baggage_bay_door", bay_anchor, 0)
	)
	assert(bay_res.ok, "test bag bay door refused: %s" % bay_res.reason_text())
	for edit in DoorPlacement.edits_for(
		grid, BuildEdit.place_object(&"baggage_bay_door", bay_anchor, 0)
	):
		assert(grid.apply(edit).ok, "test bay door edit failed")
	var room_id := grid.room_at(area.position)
	assert(RoomRules.status(grid, room_id).ok, "test bag room is not ready")
	return room_id


## Marks a ready 6x3 bag room inside ReferenceTerminal against its east exterior
## wall (with a Roll-Up Bay Door at (21, 13)) and connects Desk 2's outlet (15, 10)
## east around its staff spot (14, 10) to the room's end at (16, 13), leaving
## Desk 1 unconnected (NO_BELT) while activating checked-bag handling.
static func connect_reference_desk2(grid: BuildGrid) -> int:
	var room_rect := Rect2i(16, 13, 6, 3)
	var result := grid.apply(BuildEdit.place_room(room_rect, &"bag_room"))
	assert(result.ok, "reference bag room refused: %s" % result.reason_text())
	for edit in DoorPlacement.edits_for(
		grid, BuildEdit.place_object(&"baggage_bay_door", Vector2i(21, 13), 1)
	):
		assert(grid.apply(edit).ok, "reference bay door edit failed")
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
	PassengerTestWorld.place(grid, &"baggage_cart", Vector2i(18, 14), 0)
	return room_id
