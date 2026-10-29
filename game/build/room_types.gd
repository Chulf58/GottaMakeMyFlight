class_name RoomTypes
extends RefCounted
## The store types a room can be marked as, keyed by string id. Each type says
## what a room of it needs to work (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces): its required
## pieces, a minimum size, how many seats each seating piece gives and what a
## ready room costs to run per day.
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
	## The piece that seats guests, and the seats each one gives. In a shop it
	## is the browse piece and its browse slots (ShopLayout).
	var seat_piece: StringName = &""
	var seats_per_piece := 0
	## Whether passengers visit it through ShopSim: they browse at its seat
	## pieces and pay its base spend when the browse ends.
	var shop := false
	## What one visit spends before mood and the airside bonus (a tuning value).
	var base_spend := 0
	## The piece a ready room is charged upkeep for each game day, and the
	## charge per piece (PriceTable); none for a room that costs nothing to run.
	var upkeep_piece: StringName = &""
	var upkeep_per_piece := 0

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

	# Toilet (decision toilet-design-queue-free-reservable-stalls-per-stall-
	# daily-u, points 1 and 2): each stall is one use slot, and the sink is
	# required furniture. It seats nobody and earns nothing; each stall of a
	# ready toilet costs upkeep every day. 2x3 holds a 1x2 stall and a sink side
	# by side with the approach cell in front of each.
	var toilet := RoomType.new()
	toilet.id = &"toilet"
	toilet.display_name = "Toilet"
	toilet.min_size = Vector2i(2, 3)
	toilet.required = [[&"toilet_stall", "Needs a toilet stall"], [&"toilet_sink", "Needs a sink"]]
	toilet.upkeep_piece = &"toilet_stall"
	toilet.upkeep_per_piece = PriceTable.TOILET_STALL_UPKEEP
	_types[toilet.id] = toilet

	# Kiosk (decision boredom-and-shops-design-boredom-need-while-waiting-kiosk-
	# sh, point 2): a counter makes it work, display stands give its browse
	# slots (two each, ShopLayout). A visit pays base_spend nudged by mood and
	# the airside bonus (ShopSim.spend()). 3x3 holds the counter, a stand and
	# their front cells.
	var kiosk := RoomType.new()
	kiosk.id = &"kiosk"
	kiosk.display_name = "Kiosk"
	kiosk.min_size = Vector2i(3, 3)
	kiosk.required = [
		[&"kiosk_counter", "Needs a kiosk counter"], [&"kiosk_display", "Needs a display stand"]
	]
	kiosk.seat_piece = &"kiosk_display"
	kiosk.seats_per_piece = 2
	kiosk.base_spend = 12
	kiosk.shop = true
	_types[kiosk.id] = kiosk

	# The per-visit stores (F4-5; decisions shops-and-food-stalls-earn-per-
	# visit-toilets-and-screens-cos and duty-free-and-fashion-shops-get-their-
	# own-blender-retail-kit): shops like the kiosk, each with a counter or till
	# a server stands at and a browse piece whose Mount_Browse cells are its
	# browse slots. The pharmacy shelf has one, the duty free shelf and the
	# fashion rail two. Base spends are tuning values: a pharmacy sells less
	# than a kiosk, duty free and fashion more.
	_add_store(
		&"pharmacy",
		"Pharmacy",
		Vector2i(3, 3),
		10,
		[[&"pharmacy_counter", "Needs a pharmacy counter"], [&"pharmacy_shelf", "Needs a shelf"], 1]
	)
	_add_store(
		&"duty_free",
		"Duty free",
		Vector2i(3, 4),
		25,
		[[&"duty_free_till", "Needs a till"], [&"duty_free_shelf", "Needs a shelf"], 2]
	)
	_add_store(
		&"fashion",
		"Fashion store",
		Vector2i(3, 4),
		30,
		[[&"fashion_till", "Needs a till"], [&"fashion_rail", "Needs a clothes rail"], 2]
	)


## A shop room type that needs `pieces[0]` (its counter or till) and
## `pieces[1]` (its browse piece, giving `pieces[2]` browse slots each), each
## as [BuildCatalog id, note].
static func _add_store(
	id: StringName, display_name: String, min_size: Vector2i, base_spend: int, pieces: Array
) -> void:
	var store := RoomType.new()
	store.id = id
	store.display_name = display_name
	store.min_size = min_size
	store.required = [pieces[0], pieces[1]]
	store.seat_piece = pieces[1][0]
	store.seats_per_piece = pieces[2]
	store.base_spend = base_spend
	store.shop = true
	_types[id] = store
