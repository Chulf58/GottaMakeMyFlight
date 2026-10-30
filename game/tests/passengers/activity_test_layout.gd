class_name ActivityTestLayout
extends RefCounted
## The activity and rest rooms of F4-7 on ShopTestLayout's floor: the reference
## terminal with floor east of it and a room of the given type in its airside
## half (x 22-27, y 3-8). Its use piece stands in the north-west corner facing
## south, so its first slot is the cell south of it, (22, 4); the play area also
## has its blocks in the north-east corner, which gives no slot.

## Room type -> the pieces placed in it, [BuildCatalog id, anchor].
const PIECES := {
	&"play_area": [[&"play_slide", Vector2i(22, 3)], [&"play_blocks", Vector2i(25, 3)]],
	&"lounge": [[&"lounge_sofa", Vector2i(22, 3)]],
	&"shower": [[&"shower_cubicle", Vector2i(22, 3)]],
	&"nap_pod": [[&"nap_pod", Vector2i(22, 3)]],
}
const TYPES: Array[StringName] = [&"play_area", &"lounge", &"shower", &"nap_pod"]


## A grid holding ShopTestLayout's floor and a ready `type` room in its
## airside half, and its ids: {"room", "use" (the use piece's object id)}.
static func build(grid: BuildGrid, type: StringName) -> Dictionary:
	ShopTestLayout.build(grid, [])
	var ids := {
		"room": _apply(grid, BuildEdit.place_room(ShopTestLayout.AIRSIDE_ROOM, type)).room_id
	}
	for piece: Array in PIECES[type]:
		var placed := _apply(grid, BuildEdit.place_object(piece[0], piece[1], 0)).object_id
		if not ids.has("use"):
			ids["use"] = placed
	return ids


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "activity layout edit refused: %s" % result.reason_text())
	return result
