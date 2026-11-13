class_name NeedFacilityKit
extends RefCounted
## A grid where something built can meet every need, for the view tests that
## draw need icons and are not about the facility gate (decision crowd-need-
## display-mood-overlay-gains-hunger-toilet-and-bore, point 3: an icon is
## hidden while nothing built can meet its need): ToiletTestLayout's airside
## toilet room with its stalls, a cafe with a counter and a table where its
## landside toilet room stood, and a screen stand on airside floor.


## Builds the grid and returns ToiletTestLayout's ids for the airside room.
static func build(grid: BuildGrid) -> Dictionary:
	var ids := ToiletTestLayout.build(grid)
	var at := ReferenceTerminal.offset_on(grid)
	for id: int in ids["land_stalls"] + [ids["land_sink"]]:
		_apply(grid, BuildEdit.remove_object(id))
	_apply(grid, BuildEdit.remove_room(ids["land_room"]))
	add_landside_cafe(grid)
	_apply(grid, BuildEdit.place_object(&"screen_stand", ShopTestLayout.AIRSIDE_CELL + at, 0))
	return ids


## A cafe with a counter and a table in the landside half of ShopTestLayout's
## floor, where no room stands.
static func add_landside_cafe(grid: BuildGrid) -> void:
	var at := ReferenceTerminal.offset_on(grid)
	var rect := Rect2i(
		CafeTestLayout.LANDSIDE_ROOM.position + at, CafeTestLayout.LANDSIDE_ROOM.size
	)
	_apply(grid, BuildEdit.place_room(rect, &"cafe"))
	_apply(grid, BuildEdit.place_object(&"cafe_counter", CafeTestLayout.LAND_COUNTER + at, 0))
	_apply(grid, BuildEdit.place_object(&"cafe_table", CafeTestLayout.LAND_TABLE + at, 0))


static func _apply(grid: BuildGrid, edit: BuildEdit) -> void:
	var result := grid.apply(edit)
	assert(result.ok, "need facility edit refused: %s" % result.reason_text())
