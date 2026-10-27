class_name RoomTypes
extends RefCounted
## The store types a room can be marked as, keyed by string id. Each type says
## what a room of it needs to work (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces): its required
## pieces, a minimum size, and how many seats each seating piece gives.
## RoomRules judges a room against its type.


## One room type. Plain data, filled in by _build().
class RoomType:
	extends RefCounted
	var id: StringName = &""
	var display_name := ""
	## Smallest room that works, in cells, in either orientation.
	var min_size := Vector2i.ONE
	## [BuildCatalog id, note shown while the room has none of it], in the
	## order the notes are shown.
	var required: Array = []
	## The piece that seats guests, and the seats each one gives.
	var seat_piece: StringName = &""
	var seats_per_piece := 0
	## What one visit spends before mood and the airside bonus (a tuning value).
	var base_spend := 0

	## Whether a room of `size` cells is big enough, turned either way.
	func fits(size: Vector2i) -> bool:
		var straight := size.x >= min_size.x and size.y >= min_size.y
		return straight or (size.x >= min_size.y and size.y >= min_size.x)


static var _types: Dictionary = {}


static func get_type(id: StringName) -> RoomType:
	if _types.is_empty():
		_build()
	return _types.get(id)


static func ids() -> Array[StringName]:
	if _types.is_empty():
		_build()
	var result: Array[StringName] = []
	result.assign(_types.keys())
	return result


static func _build() -> void:
	var cafe := RoomType.new()
	cafe.id = &"cafe"
	cafe.display_name = "Cafe"
	cafe.min_size = Vector2i(3, 3)
	cafe.required = [[&"cafe_counter", "Needs a counter"], [&"cafe_table", "Needs a table"]]
	# cafe_table.glb has two seat mounts, Mount_SitRoot_L and Mount_SitRoot_R.
	cafe.seat_piece = &"cafe_table"
	cafe.seats_per_piece = 2
	cafe.base_spend = 15
	_types[cafe.id] = cafe

	# Bag room (decision baggage-rides-a-player-built-belt-from-check-in-to-a-
	# bag-roo): where the check-in belt ends. It seats nobody and earns no
	# spend; the belt's end piece is what makes it work.
	var bag_room := RoomType.new()
	bag_room.id = &"bag_room"
	bag_room.display_name = "Bag room"
	bag_room.min_size = Vector2i(2, 2)
	bag_room.required = [[&"baggage_belt_end", "Needs a belt end"]]
	_types[bag_room.id] = bag_room
