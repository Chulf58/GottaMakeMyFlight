class_name RoomMoveKit
extends RefCounted
## The grid the RoomMove tests build on. 24x16 cells with tile floor on
## FLOORED (columns 1 to 12, rows 1 to 10); the rest is bare ground. A cafe on
## CAFE (columns 2 to 5, rows 2 to 4) holds a bin at (2, 2), a statue at
## (3, 4) and a 2x2 plant pot at (4, 3), each saved at a price no catalog
## gives (BIN_PAID, STATUE_PAID, POT_PAID), so a kept price can be told from a
## fresh one. The cafe's centre cell is (3, 3).

const SIZE := Vector2i(24, 16)
const FLOORED := Rect2i(1, 1, 12, 10)
const CAFE := Rect2i(2, 2, 4, 3)
const ZONE := 3
const BIN_PAID := 37
const STATUE_PAID := 413
const POT_PAID := 91

var grid: BuildGrid
var room := 0
var bin := 0
var statue := 0
var pot := 0


func _init() -> void:
	grid = BuildGrid.new(SIZE)
	var edits: Array[BuildEdit] = []
	for y in range(FLOORED.position.y, FLOORED.end.y):
		for x in range(FLOORED.position.x, FLOORED.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, ZONE))
	grid.apply_batch(edits)
	room = grid.apply(BuildEdit.place_room(CAFE, &"cafe")).room_id
	bin = place(&"trash_can", Vector2i(2, 2), 0, BIN_PAID)
	statue = place(&"statue_indoor", Vector2i(3, 4), 0, STATUE_PAID)
	pot = place(&"plant_pot_2a", Vector2i(4, 3), 0, POT_PAID)


## Places `def_id` at `anchor` straight on the grid, saved at `paid`. Returns
## its id, 0 when the grid refused it.
func place(def_id: StringName, anchor: Vector2i, facing: int, paid: int) -> int:
	var edit := BuildEdit.place_object(def_id, anchor, facing)
	edit.paid = paid
	return grid.apply(edit).object_id


func rect() -> Rect2i:
	return grid.get_room(room)["rect"]


## {"def", "anchor", "facing", "paid"} of object `id`.
func record(id: int) -> Dictionary:
	return grid.get_object(id)


## Paints floor on bare cell `cell` as one player action of `history`, paid
## from `wallet`: an earlier undo step a refused move must leave undoable.
func earlier_action(history: UndoStack, wallet: Wallet, cell: Vector2i) -> BuildResult:
	var plan: Array[BuildEdit] = [BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE)]
	history.begin_action()
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	history.end_action()
	return result
