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
	extends ServiceDef
	## Smallest room that works, in cells, in either orientation.
	var min_size := Vector2i.ONE
	## [BuildCatalog id, note shown while the room has none of it], in the
	## order the notes are shown.
	var required: Array = []
	## The piece a ready room is charged upkeep for each game day, and the
	## charge per piece (PriceTable); none for a room that costs nothing to run.
	var upkeep_piece: StringName = &""
	var upkeep_per_piece := 0
	## Alternative piece ids accepted for a required piece (`StringName -> Array[StringName]`).
	var alt_pieces: Dictionary = {}

	## The pieces that count as the required piece `need_id`: for a food room's
	## counter or table every piece it accepts, any registered alternatives,
	## else the piece itself.
	func pieces_for(need_id: StringName) -> Array[StringName]:
		if counter_pieces.has(need_id):
			return counter_pieces
		if table_pieces.has(need_id):
			return table_pieces
		if alt_pieces.has(need_id):
			var out: Array[StringName] = []
			out.assign(alt_pieces[need_id])
			return out
		return [need_id]

	## Whether a room of `size` cells is big enough, turned either way.
	func fits(size: Vector2i) -> bool:
		var straight := size.x >= min_size.x and size.y >= min_size.y
		return straight or (size.x >= min_size.y and size.y >= min_size.x)


## The cafe's order, dwell and mood bonus, which CafeSim names ORDER_TICKS,
## DWELL_TICKS and SERVED_MOOD_BONUS.
const CAFE_ORDER_TICKS := 60
const CAFE_DWELL_TICKS := 120
const CAFE_MOOD_BONUS := 10
## The cafe's counter and table (restaurant also uses CAFE_COUNTER as its kitchen
## counter; bar and stall take only their own tier pieces).
const CAFE_COUNTER: StringName = &"cafe_counter"
const CAFE_TABLE: StringName = &"cafe_table"

static var _types: Dictionary = {}


static func get_type(id: StringName) -> RoomType:
	if _types.is_empty():
		_build()
	return _types.get(id)


## Whether `piece_id` is a counter piece of some food room.
static func is_food_counter(piece_id: StringName) -> bool:
	for type_id in ids():
		if get_type(type_id).counter_pieces.has(piece_id):
			return true
	return false


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
	cafe.required = [[CAFE_COUNTER, "Needs a counter"], [CAFE_TABLE, "Needs a table"]]
	# cafe_table.glb has two seat mounts, Mount_SitRoot_L and Mount_SitRoot_R.
	cafe.seat_piece = CAFE_TABLE
	cafe.seats_per_piece = 2
	cafe.base_spend = 15
	cafe.food = true
	cafe.counter_pieces = [CAFE_COUNTER]
	cafe.table_pieces = [CAFE_TABLE]
	cafe.order_ticks = CAFE_ORDER_TICKS
	cafe.dwell_ticks = CAFE_DWELL_TICKS
	cafe.mood_bonus = CAFE_MOOD_BONUS
	_types[cafe.id] = cafe

	# The food variants (F4-6; decision food-and-drink-cafe-bar-sit-down-
	# restaurant-and-grab-and-go-st): a visit takes the same path through
	# CafeSim as the cafe's, with a longer visit and a larger spend. Each room
	# has its own pieces (the bar its bar counter, the restaurant its dining
	# table and booth, the stall its grab-and-go stall; user-ruled 2026-11-04,
	# "Make them work") and still accepts the cafe counter and table, so a
	# player can build with either. The grab-and-go stall needs only a
	# counter: its guest buys, pays and walks on with no seat and no dwell.
	# The bar counter's two stools are seats too, so it is one of the bar's
	# table pieces and a bar with only a bar counter is ready; its guests take
	# a stool first, then a table seat (decision bar-guests-sit-at-the-bar-
	# counter-stools-first-then-at-table). Visit length and spend run
	# stall < cafe < bar < restaurant. The bar lifts mood the most; the
	# restaurant needs the most room. A guest who runs short of time leaves
	# early and pays the short share like any cafe guest, so none of them
	# causes a miss. All numbers are tuning values
	# pinned by tests.
	_add_food(
		&"bar", "Bar", Vector2i(3, 4), [24, 80, 200, 20], [[&"bar_counter"], [&"bar_counter"]]
	)
	_add_food(
		&"restaurant",
		"Restaurant",
		Vector2i(4, 4),
		[40, 120, 360, 15],
		[[CAFE_COUNTER], [&"restaurant_table", &"restaurant_booth"]]
	)

	# Bag room (decisions baggage-rides-a-player-built-belt-from-check-in-to-a-
	# bag-roo and baggage-loop-completion-connect-gated-penalties-visible-wait):
	# where check-in belts end. A belt end makes the room ready; placing a
	# baggage_cart inside (or on the grid) upgrades transfer during
	# LOAD_LEAD_TICKS to an animated cart shuttle out to the parked plane
	# (falling back cleanly to immediate LOADED settlement when no cart exists).
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

	# Activities and rest services (F4-7; decisions furniture-set-modelled-on-
	# copenhagen-airport-decor-calms-pas and food-and-drink-cafe-bar-sit-down-
	# restaurant-and-grab-and-go-st, point 3): rooms on the shop pipeline that
	# relieve boredom and give mood, with no counter and no server (they are
	# self-service, ShopCounters.SELF_SERVICE_ROOMS). The play area and the
	# lounge are free. The shower is a paid service for long waits
	# (PriceTable.SHOWER_FEE) and gives mood. A passenger enters only when the
	# forecast admits the whole stay (ShopSim). Each piece's slot is the cell
	# in front of it. The numbers are [use slots per piece, fee, dwell ticks,
	# mood bonus], tuning values pinned by test_activity_rooms; every dwell is
	# above the kiosk's 120-tick browse.
	_add_activity(
		&"play_area",
		"Play area",
		Vector2i(3, 4),
		[[&"play_slide", "Needs a slide"], [&"play_blocks", "Needs play blocks"]],
		[2, 0, 150, 8]
	)
	_add_activity(
		&"lounge", "Lounge", Vector2i(2, 3), [[&"lounge_sofa", "Needs a sofa"]], [2, 0, 240, 6]
	)
	_add_activity(
		&"shower",
		"Shower",
		Vector2i(2, 2),
		[[&"shower_cubicle", "Needs a shower"]],
		[1, PriceTable.SHOWER_FEE, 200, 12]
	)

	var break_room := RoomType.new()
	break_room.id = &"break_room"
	break_room.display_name = "Break Room"
	break_room.min_size = Vector2i(2, 3)
	break_room.required = [[&"lounge_sofa", "Needs a sofa"]]
	break_room.alt_pieces[&"lounge_sofa"] = [&"lounge_sofa", &"lounge_armchair", &"bench_1a"]
	_types[break_room.id] = break_room


## A food room type like the cafe: `numbers` is [base spend, order ticks,
## dwell ticks, mood bonus] and `pieces` is [counter pieces, table pieces],
## each in order with the room's own piece first. A room with no table pieces
## needs only the counter, has no seats and lets its guests walk on after
## paying. Seats come from each table piece's catalog seats (RoomRules).
static func _add_food(
	id: StringName, display_name: String, min_size: Vector2i, numbers: Array, pieces: Array
) -> void:
	var food := RoomType.new()
	food.id = id
	food.display_name = display_name
	food.min_size = min_size
	food.counter_pieces.assign(pieces[0])
	food.table_pieces.assign(pieces[1])
	food.required = [[food.counter_pieces[0], "Needs a counter"]]
	var seated := not food.table_pieces.is_empty()
	if seated:
		food.required.append([food.table_pieces[0], "Needs a table"])
		food.seat_piece = food.table_pieces[0]
		food.seats_per_piece = BuildCatalog.get_def(food.seat_piece).seats.size()
	food.walk_on = not seated
	food.base_spend = numbers[0]
	food.food = true
	food.order_ticks = numbers[1]
	food.dwell_ticks = numbers[2]
	food.mood_bonus = numbers[3]
	_types[id] = food


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


## An activity room type: `pieces` ([BuildCatalog id, note] each) are all
## required and the first is the use piece, and `numbers` is [use slots per
## piece, fee, dwell ticks, mood bonus].
static func _add_activity(
	id: StringName, display_name: String, min_size: Vector2i, pieces: Array, numbers: Array
) -> void:
	var room := RoomType.new()
	room.id = id
	room.display_name = display_name
	room.min_size = min_size
	room.required = pieces
	room.seat_piece = pieces[0][0]
	room.seats_per_piece = numbers[0]
	room.base_spend = numbers[1]
	room.shop = true
	room.activity = true
	room.dwell_ticks = numbers[2]
	room.mood_bonus = numbers[3]
	_types[id] = room
