class_name ShopLayout
extends RefCounted
## The shop browse slots passengers can use, derived from the grid (decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 2):
## Rooms owns the room and whether it is ready; this layout owns the usable
## slots; ShopSim owns who holds each one. Rebuilt after every grid edit.
##
## A shop is a ready room of a shop type (RoomTypes.RoomType.shop: the kiosk,
## the pharmacy, duty free and fashion; RoomRules: its required pieces, its
## size and an opening). Its slots are those of its type's browse pieces
## (seat_piece) wholly inside it (the rule RoomRules counts pieces by): one in
## front of each of the first seats_per_piece footprint cells of a piece (both
## cells of a kiosk display stand, a duty free shelf or a fashion rail, the
## first of a pharmacy shelf), slot index in footprint order, kept when that
## cell is walkable. A browser stands on the slot's cell facing the piece. A
## shop with no usable slot is left out. The slot's room tells ShopSim the
## type, and so the base spend, a visit pays.

## One entry per usable shop, in room id order: {"room": int, "slots": Array
## of {"key": "<piece id>:<index>", "display": object id of the browse piece,
## "index": int, "room": room id, "approach": Vector2i, "facing": Vector2i
## (towards the piece)} in piece id and index order}.
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
		var type := RoomTypes.get_type(status.type_id)
		if not type.shop or not status.ok:
			continue
		var area: Rect2i = grid.get_room(room_id)["rect"]
		var slots: Array[Dictionary] = []
		for id in ids:
			var record := grid.get_object(id)
			if record["def"] != type.seat_piece or not FacilitySlots.piece_inside(grid, id, area):
				continue
			var def := BuildCatalog.get_def(record["def"])
			var front := TerminalLayout.front_of(record["facing"])
			var cells := def.footprint(record["anchor"], record["facing"])
			for i in mini(type.seats_per_piece, cells.size()):
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
