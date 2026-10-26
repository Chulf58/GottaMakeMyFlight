class_name RoomTool
extends RefCounted
## The room tools' rules, called by BuildMode (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces: draw a room,
## then furnish it). A room tool marks a press-drag-release rectangle of floor
## as a room of its type in one BuildGrid edit; a single click marks nothing,
## so a stray click never makes a one-cell room. What the room still needs is
## RoomRules' job, shown once the room exists.


## Whether the grid would accept marking `area` as a room of `type`.
static func check(grid: BuildGrid, area: Rect2i, type: StringName) -> BuildResult:
	return grid.validate(BuildEdit.place_room(area, type))


## Marks `area` as a room of `type`. A refusal changes nothing; the grid emits
## edit_refused for it.
static func mark(grid: BuildGrid, area: Rect2i, type: StringName) -> BuildResult:
	return grid.apply(BuildEdit.place_room(area, type))


## The status line while a rectangle is dragged: "Cafe 4 x 3", followed by
## the reason the grid would refuse it.
static func drag_label(grid: BuildGrid, area: Rect2i, type: StringName) -> String:
	var text := "%s %d x %d" % [RoomTypes.get_type(type).display_name, area.size.x, area.size.y]
	var result := check(grid, area, type)
	if not result.ok:
		text += "  " + result.reason_text()
	return text


## The status line after a release: "Cafe marked: Needs a counter", or the
## refusal.
static func message(grid: BuildGrid, result: BuildResult, type: StringName) -> String:
	if not result.ok:
		return result.reason_text()
	var status := RoomRules.status(grid, result.room_id)
	return "%s marked: %s" % [RoomTypes.get_type(type).display_name, status.headline()]


## The status line while a room tool waits for a drag.
static func hint(type: StringName) -> String:
	return "Drag to mark a %s" % RoomTypes.get_type(type).display_name.to_lower()
