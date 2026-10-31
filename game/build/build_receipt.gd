class_name BuildReceipt
extends RefCounted
## What one player build action did, so it can be undone (decision
## build-mode-undo-design-action-receipts-with-before-values-at, point 1): one
## inverse edit per edit the grid accepted, in the order they were applied, and
## the build money the action moved. BuildGrid fills it while it is the grid's
## `recorder`; UndoStack keeps the receipts and BuildUndo replays them.
##
## Each inverse is made from the grid as it stood just before its edit
## (inverse_before()), or from the edit's result for a placement, so it puts
## back exactly what was there: a floor's type, zone and saved price, a wall's
## kind and saved price, a removed object or room under its own id with its
## saved price, a belt piece's earlier shape.

## Every inverse edit, in the order the action's edits were applied.
var inverses: Array[BuildEdit] = []
## The build money the action moved, as the wallet's transactions gave it
## (gross, before owed wages or upkeep took any of a refund): negative when it
## spent, positive when it refunded.
var money := 0
## True when the grid was replaced from a snapshot while recording
## (BuildTransaction rolling back a commit): the inverses no longer describe
## the grid, so the receipt cannot be undone.
var replaced := false


## The inverse of `edit` read from `grid` before the edit is applied, or null
## for a placement of an object or a room, whose inverse needs the id the
## placement gets (record()).
static func inverse_before(grid: BuildGrid, edit: BuildEdit) -> BuildEdit:
	var inverse: BuildEdit = null
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR, BuildEdit.Kind.REMOVE_FLOOR:
			if grid.floor_at(edit.cell) == BuildGrid.FLOOR_NONE:
				inverse = BuildEdit.remove_floor(edit.cell)
			else:
				var type := grid.floor_at(edit.cell)
				inverse = BuildEdit.paint_floor(edit.cell, type, grid.zone_at(edit.cell))
				inverse.paid = grid.floor_paid(edit.cell)
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			var kind := grid.wall_kind(edit.cell, edit.side)
			if kind == BuildGrid.WallKind.NONE:
				inverse = BuildEdit.remove_wall(edit.cell, edit.side)
			else:
				inverse = BuildEdit.place_wall(edit.cell, edit.side, kind)
				inverse.paid = grid.wall_paid(edit.cell, edit.side)
		BuildEdit.Kind.REMOVE_OBJECT:
			var record := grid.get_object(edit.object_id)
			inverse = BuildEdit.place_object(record["def"], record["anchor"], record["facing"])
			inverse.object_id = edit.object_id
			inverse.paid = int(record.get("paid", 0))
		BuildEdit.Kind.REMOVE_ROOM:
			var room := grid.get_room(edit.room_id)
			inverse = BuildEdit.place_room(room["rect"], room["type"])
			inverse.room_id = edit.room_id
		BuildEdit.Kind.RESIZE_ROOM:
			inverse = BuildEdit.resize_room(edit.room_id, grid.get_room(edit.room_id)["rect"])
		BuildEdit.Kind.RESHAPE_BELT:
			var record := grid.get_object(grid.object_at(edit.cell))
			inverse = BuildEdit.reshape_belt(edit.cell, record["def"], record["facing"])
	return inverse


## Adds the inverse of an applied edit: `before` from inverse_before(), or for
## a placement the removal of the object or room `result` names.
func record(edit: BuildEdit, result: BuildResult, before: BuildEdit) -> void:
	var inverse := before
	if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
		inverse = BuildEdit.remove_object(result.object_id)
	elif edit.kind == BuildEdit.Kind.PLACE_ROOM:
		inverse = BuildEdit.remove_room(result.room_id)
	inverses.append(inverse)


func is_empty() -> bool:
	return inverses.is_empty() and money == 0


## The edits that undo the action, last applied first.
func undo_edits() -> Array[BuildEdit]:
	var edits := inverses.duplicate()
	edits.reverse()
	return edits
