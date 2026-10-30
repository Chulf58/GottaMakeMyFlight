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
	## Whether a finished visit resets boredom (ShopSim). False for a shop people
	## go to for money, not to pass time (the exchange and the ATM): a visit
	## leaves boredom as it was, and a bored passenger never plans one.
	var relieves_boredom := true
	## Whether passengers eat and drink here through CafeSim (the cafe, the bar,
	## the sit-down restaurant and the grab-and-go stall): all four use the
	## cafe counter and table, and differ in the numbers below.
	var food := false
	## Whether a food room serves guests at the counter and lets them walk on
	## (the grab-and-go stall): no table or seat is needed or reserved, and the
	## visit has no sit or stand phase, so dwell_ticks is 0.
	var walk_on := false
	## Whether it is an activity or rest room (the play area, the lounge, the
	## shower, the nap pod): a shop-pipeline room with one required piece that
	## is also its use piece, a visit of its own dwell_ticks that gives
	## mood_bonus, and a fee (base_spend) that is 0 for a free one. A bored
	## passenger with a shopping wish never settles for one as a fallback.
	var activity := false
	## Ticks to make an order at the counter, and ticks a served guest stays
	## seated when nothing hurries it (a food room's visit length). An activity
	## room's dwell_ticks is its whole stay at the use slot (ShopSim.browse_
	## ticks(); 0 elsewhere in the shop pipeline means ShopSim.BROWSE_TICKS).
	var order_ticks := 0
	var dwell_ticks := 0
	## Mood a guest who finishes the visit gains (a food or activity room's).
	var mood_bonus := 0
	## The piece a ready room is charged upkeep for each game day, and the
	## charge per piece (PriceTable); none for a room that costs nothing to run.
	var upkeep_piece: StringName = &""
	var upkeep_per_piece := 0

	## The ticks one visit takes at the counter and the table, queue and
	## walking not counted: the order and the dwell.
	func visit_ticks() -> int:
		return order_ticks + dwell_ticks

	## Whether a room of `size` cells is big enough, turned either way.
	func fits(size: Vector2i) -> bool:
		var straight := size.x >= min_size.x and size.y >= min_size.y
		return straight or (size.x >= min_size.y and size.y >= min_size.x)


## The cafe's order, dwell and mood bonus, which CafeSim names ORDER_TICKS,
## DWELL_TICKS and SERVED_MOOD_BONUS.
const CAFE_ORDER_TICKS := 60
const CAFE_DWELL_TICKS := 120
const CAFE_MOOD_BONUS := 10

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
	cafe.food = true
	cafe.order_ticks = CAFE_ORDER_TICKS
	cafe.dwell_ticks = CAFE_DWELL_TICKS
	cafe.mood_bonus = CAFE_MOOD_BONUS
	_types[cafe.id] = cafe

	# The food variants (F4-6; decision food-and-drink-cafe-bar-sit-down-
	# restaurant-and-grab-and-go-st): the bar and restaurant use the same
	# counter and table as the cafe, so a visit takes the same path through
	# CafeSim, with a longer visit and a larger spend. The grab-and-go stall
	# needs only a counter: its guest buys, pays and walks on with no seat and
	# no dwell. Visit length and spend run stall < cafe < bar < restaurant. The
	# bar lifts mood the most; the restaurant needs the most room. A guest who
	# runs short of time leaves early and pays the short share like any cafe
	# guest, so none of them causes a miss. All numbers are tuning values
	# pinned by tests.
	_add_food(&"stall", "Grab-and-go stall", Vector2i(3, 3), [8, 30, 0, 5], false)
	_add_food(&"bar", "Bar", Vector2i(3, 4), [24, 80, 200, 20])
	_add_food(&"restaurant", "Restaurant", Vector2i(4, 4), [40, 120, 360, 15])

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

	# The currency exchange and the ATM (F4-5b; decision currency-exchange-and-
	# atm-visits-front-cell-slot-small-fee-no-boredom): the counter or ATM is
	# both the required piece and the browse piece, its one visit slot the cell
	# in front. A visit pays a small fee and does not lower boredom. 2x3 holds
	# the counter with its server's cell behind and the slot in front; 1x2 holds
	# the ATM and its slot. The exchange counter needs a server
	# (ShopCounters.COUNTER_ROOMS); the ATM is self-service
	# (ShopCounters.SELF_SERVICE_ROOMS). Fees are tuning values.
	_add_money_store(
		&"exchange",
		"Exchange",
		Vector2i(2, 3),
		8,
		[&"currency_exchange", "Needs an exchange counter"]
	)
	_add_money_store(&"atm", "ATM", Vector2i(1, 2), 3, [&"atm", "Needs an ATM"])

	# Activities and rest services (F4-7; decisions furniture-set-modelled-on-
	# copenhagen-airport-decor-calms-pas and food-and-drink-cafe-bar-sit-down-
	# restaurant-and-grab-and-go-st, point 3): rooms on the shop pipeline that
	# relieve boredom and give mood, with no counter and no server (they are
	# self-service, ShopCounters.SELF_SERVICE_ROOMS). The play area and the
	# lounge are free. The shower and the nap pod are paid services for long
	# waits (PriceTable.SHOWER_FEE, NAP_POD_FEE) and give the most mood, the
	# nap pod the longest stay. A passenger enters only when the forecast admits the whole
	# stay (ShopSim). Each piece's slot is the cell in front of it. The numbers
	# are [use slots per piece, fee, dwell ticks, mood bonus], tuning values
	# pinned by test_activity_rooms; every dwell is above the kiosk's 120-tick
	# browse.
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
	_add_activity(
		&"nap_pod",
		"Nap pod",
		Vector2i(2, 2),
		[[&"nap_pod", "Needs a nap pod"]],
		[1, PriceTable.NAP_POD_FEE, 300, 15]
	)


## A food room type like the cafe: `numbers` is [base spend, order ticks,
## dwell ticks, mood bonus]. A room that is not `seated` needs only the
## counter, has no seats and lets its guests walk on after paying.
static func _add_food(
	id: StringName, display_name: String, min_size: Vector2i, numbers: Array, seated := true
) -> void:
	var food := RoomType.new()
	food.id = id
	food.display_name = display_name
	food.min_size = min_size
	food.required = [[&"cafe_counter", "Needs a counter"]]
	if seated:
		food.required.append([&"cafe_table", "Needs a table"])
		food.seat_piece = &"cafe_table"
		food.seats_per_piece = 2
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


## A shop room type people visit for money: `piece` ([BuildCatalog id, note])
## is its one required piece and its browse piece, with one slot, and a visit
## does not relieve boredom.
static func _add_money_store(
	id: StringName, display_name: String, min_size: Vector2i, fee: int, piece: Array
) -> void:
	_add_store(id, display_name, min_size, fee, [piece, piece, 1])
	_types[id].required = [piece]
	_types[id].relieves_boredom = false


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
