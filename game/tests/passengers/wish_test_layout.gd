class_name WishTestLayout
extends RefCounted
## Airside shops in a row for the shopping wish tests: ShopTestLayout's floor
## with its airside half (y 3-8) carried east, and room i of `types` the 6x5
## block at x 22 + 6i, y 3-7, so the first is nearest the terminal; row y 8
## is the corridor every room opens on. A kiosk or store
## has its counter or till in its north-west corner and two browse pieces
## three cells east of it, three rows apart, facing south (as ShopTestLayout
## and StoreTestLayout lay them out); an exchange or ATM has its one piece in
## the north-west corner (as MoneyTestLayout does).

const BLOCK := 6
## Room type -> [counter or till, browse piece], or [the one piece] for a
## money room.
const PIECES := {
	&"kiosk": [&"kiosk_counter", &"kiosk_display"],
	&"pharmacy": [&"pharmacy_counter", &"pharmacy_shelf"],
	&"duty_free": [&"duty_free_till", &"duty_free_shelf"],
	&"fashion": [&"fashion_till", &"fashion_rail"],
	&"exchange": [&"currency_exchange"],
	&"atm": [&"atm"],
}


## A grid holding the floor and one room per entry of `types`, and their ids:
## {"rooms": room ids, "counters": counter or till ids (0 for an ATM)}, in
## `types` order.
static func build(grid: BuildGrid, types: Array) -> Dictionary:
	ShopTestLayout.build(grid, [])
	var edits: Array[BuildEdit] = []
	var end_x := ShopTestLayout.FLOOR.position.x + BLOCK * types.size()
	for y in range(ShopTestLayout.AIRSIDE_ROOM.position.y, ShopTestLayout.AIRSIDE_ROOM.end.y):
		for x in range(ShopTestLayout.FLOOR.end.x, end_x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in grid.apply_batch(edits):
		assert(result.ok, "wish layout floor refused: %s" % result.reason_text())
	var ids := {"rooms": [], "counters": []}
	for i in types.size():
		var type: StringName = types[i]
		var rect := ShopTestLayout.AIRSIDE_ROOM
		rect.position.x += BLOCK * i
		rect.size.y -= 1
		ids["rooms"].append(_apply(grid, BuildEdit.place_room(rect, type)).room_id)
		var pieces: Array = PIECES[type]
		var counter := _place(grid, pieces[0], rect.position)
		ids["counters"].append(0 if type == &"atm" else counter)
		if pieces.size() < 2:
			continue
		for row in 2:
			_place(grid, pieces[1], rect.position + Vector2i(3, 3 * row))
	return ids


static func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> int:
	return _apply(grid, BuildEdit.place_object(def_id, anchor, 0)).object_id


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "wish layout edit refused: %s" % result.reason_text())
	return result
