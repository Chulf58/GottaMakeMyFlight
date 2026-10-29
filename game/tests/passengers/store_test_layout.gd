class_name StoreTestLayout
extends RefCounted
## The per-visit stores of F4-5 on ShopTestLayout's floor: the reference
## terminal with floor east of it and a store room in its airside (x 22-27,
## y 3-8) or landside (x 22-27, y 10-15) half. Like a kiosk there, each store
## has its counter or till in its north-west corner and `pieces` browse pieces
## at x 25, three rows apart, all facing south; a piece's browse slots are the
## cells south of it.

## Store type -> [counter or till, browse piece, browse slots per piece].
const STORES := {
	&"pharmacy": [&"pharmacy_counter", &"pharmacy_shelf", 1],
	&"duty_free": [&"duty_free_till", &"duty_free_shelf", 2],
	&"fashion": [&"fashion_till", &"fashion_rail", 2],
}


## A grid holding ShopTestLayout's floor and a `type` store on each side named
## in `sides` ("air", "land"), and their ids: {"<side>_room", "<side>_counter",
## "<side>_pieces" (object ids, north first)}.
static func build(
	grid: BuildGrid, type: StringName, sides: Array = ["air"], pieces := 2
) -> Dictionary:
	ShopTestLayout.build(grid, [])
	var ids := {}
	for side: String in sides:
		var rect := ShopTestLayout.AIRSIDE_ROOM if side == "air" else ShopTestLayout.LANDSIDE_ROOM
		ids[side + "_room"] = _apply(grid, BuildEdit.place_room(rect, type)).room_id
		ids[side + "_counter"] = _place(grid, STORES[type][0], rect.position)
		var placed: Array = []
		for i in pieces:
			var anchor := Vector2i(ShopTestLayout.DISPLAY_X, rect.position.y + 3 * i)
			placed.append(_place(grid, STORES[type][1], anchor))
		ids[side + "_pieces"] = placed
	return ids


static func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> int:
	return _apply(grid, BuildEdit.place_object(def_id, anchor, 0)).object_id


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "store layout edit refused: %s" % result.reason_text())
	return result
