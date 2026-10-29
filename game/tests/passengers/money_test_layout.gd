class_name MoneyTestLayout
extends RefCounted
## The currency exchange and ATM of F4-5b on ShopTestLayout's floor: the
## reference terminal with floor east of it and a money room in its airside
## (x 22-27, y 3-8) or landside (x 22-27, y 10-15) half. Each room has `pieces`
## exchange counters or ATMs along its north row, from its north-west corner
## three cells apart, all facing south; a piece's one visit slot is the cell
## south of its first footprint cell.

## Room type -> its one piece (the counter or the ATM).
const PIECES := {&"exchange": &"currency_exchange", &"atm": &"atm"}


## A grid holding ShopTestLayout's floor and a `type` room on each side named
## in `sides` ("air", "land"), and their ids: {"<side>_room", "<side>_pieces"
## (object ids, west first)}.
static func build(
	grid: BuildGrid, type: StringName, sides: Array = ["air"], pieces := 1
) -> Dictionary:
	ShopTestLayout.build(grid, [])
	var ids := {}
	for side: String in sides:
		var rect := ShopTestLayout.AIRSIDE_ROOM if side == "air" else ShopTestLayout.LANDSIDE_ROOM
		ids[side + "_room"] = _apply(grid, BuildEdit.place_room(rect, type)).room_id
		var placed: Array = []
		for i in pieces:
			var anchor := Vector2i(ShopTestLayout.COUNTER_X + 3 * i, rect.position.y)
			placed.append(_apply(grid, BuildEdit.place_object(PIECES[type], anchor, 0)).object_id)
		ids[side + "_pieces"] = placed
	return ids


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "money layout edit refused: %s" % result.reason_text())
	return result
