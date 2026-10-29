class_name ShopLayout
extends RefCounted
## The kiosk browse slots passengers can use, derived from the grid (decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 2):
## Rooms owns the room and whether it is ready; this layout owns the usable
## slots; ShopSim owns who holds each one. Rebuilt after every grid edit.
##
## A kiosk is a ready kiosk room (RoomRules: a counter, a display stand, its
## size and an opening). Its slots are those of the kiosk_display pieces wholly
## inside it (the rule RoomRules counts pieces by): one in front of each of a
## stand's footprint cells, slot index in footprint order, kept when that cell
## is walkable. A browser stands on the slot's cell facing the stand. A kiosk
## with no usable slot is left out.

## One entry per usable kiosk, in room id order: {"room": int, "slots": Array
## of {"key": "<display id>:<index>", "display": object id, "index": int,
## "room": room id, "approach": Vector2i, "facing": Vector2i (towards the
## stand)} in display id and index order}.
var shops: Array[Dictionary] = []


static func key_of(display: int, index: int) -> String:
	return "%d:%d" % [display, index]


func rebuild(grid: BuildGrid) -> void:
	shops.clear()
	var rooms := grid.room_ids()
	rooms.sort()
	var ids := grid.object_ids()
	ids.sort()
	for room_id in rooms:
		var status := RoomRules.status(grid, room_id)
		if status.type_id != &"kiosk" or not status.ok:
			continue
		var area: Rect2i = grid.get_room(room_id)["rect"]
		var slots: Array[Dictionary] = []
		for id in ids:
			var record := grid.get_object(id)
			if record["def"] != &"kiosk_display" or not FacilitySlots.piece_inside(grid, id, area):
				continue
			var def := BuildCatalog.get_def(record["def"])
			var front := TerminalLayout.front_of(record["facing"])
			var cells := def.footprint(record["anchor"], record["facing"])
			for i in cells.size():
				var approach: Vector2i = cells[i] + front
				if not grid.is_walkable(approach):
					continue
				(
					slots
					. append(
						{
							"key": key_of(id, i),
							"display": id,
							"index": i,
							"room": room_id,
							"approach": approach,
							"facing": -front,
						}
					)
				)
		if not slots.is_empty():
			shops.append({"room": room_id, "slots": slots})


## A slot entry by display id and index, or an empty dictionary when it is not
## usable.
func slot(display: int, index: int) -> Dictionary:
	for shop in shops:
		for entry in shop["slots"]:
			if entry["display"] == display and entry["index"] == index:
				return entry
	return {}
