class_name BuildMenuCatalog
extends RefCounted
## What the build menu shows and where: its six domain categories plus Remove,
## the card per tool, prices, hover details, and progressive card visibility
## (decision build-menu-rework-six-domain-tabs-progressive-tab-and-card-u; split
## out of BuildMenu, which keeps aliases of these constants and one-line
## delegates of these functions).
## Static only; it must not reference BuildMenu.

enum CardState { OPEN, TEASER, HIDDEN, LOCKED }

## The context of every table name below: the same short word is a build menu card
## here and something else elsewhere.
const NAME_CONTEXT := "build menu"
const THUMBNAIL_DIR := "res://assets/ui/thumbnails/%s.png"
const CATEGORIES := [
	{
		"id": "building",
		"name": "Building",
		"tools":
		[
			BuildMode.Tool.FLOOR,
			BuildMode.Tool.WALL,
			BuildMode.Tool.GLASS,
			BuildMode.Tool.DOOR,
			BuildMode.Tool.ENTRANCE,
			BuildMode.Tool.EXIT,
			BuildMode.Tool.BUY_LAND,
		],
	},
	{
		"id": "operations",
		"name": "Operations",
		"tools":
		[
			BuildMode.Tool.DESK,
			BuildMode.Tool.GATE_DESK,
			BuildMode.Tool.SEATS,
			BuildMode.Tool.SCREEN,
			BuildMode.Tool.SCANNER,
			BuildMode.Tool.TRAY_TABLE,
			BuildMode.Tool.XRAY_BELT,
			BuildMode.Tool.ARCH,
			BuildMode.Tool.PICKUP_TABLE,
			BuildMode.Tool.BELT,
			BuildMode.Tool.BAG_ROOM,
			BuildMode.Tool.CART,
		],
	},
	{
		"id": "facilities",
		"name": "Facilities",
		"tools":
		[
			BuildMode.Tool.TOILET_ROOM,
			BuildMode.Tool.TOILET_STALL,
			BuildMode.Tool.TOILET_SINK,
			BuildMode.Tool.SHOWER_ROOM,
			BuildMode.Tool.SHOWER,
			BuildMode.Tool.NAP_POD_ROOM,
			BuildMode.Tool.NAP_POD,
			BuildMode.Tool.INFO_DESK,
			BuildMode.Tool.INFO_SCREEN,
			BuildMode.Tool.EXCHANGE_ROOM,
			BuildMode.Tool.EXCHANGE,
			BuildMode.Tool.ATM_ROOM,
			BuildMode.Tool.ATM,
			BuildMode.Tool.LOUNGE_ROOM,
			BuildMode.Tool.SOFA,
			BuildMode.Tool.ARMCHAIR,
			BuildMode.Tool.WORK_DESK,
			BuildMode.Tool.PLAY_AREA_ROOM,
			BuildMode.Tool.PLAY_BLOCKS,
			BuildMode.Tool.PLAY_SLIDE,
		],
	},
	{
		"id": "food",
		"name": "Food & Drink",
		"tools":
		[
			BuildMode.Tool.CAFE_ROOM,
			BuildMode.Tool.COUNTER,
			BuildMode.Tool.TABLE,
			BuildMode.Tool.BAR_ROOM,
			BuildMode.Tool.BAR_COUNTER,
			BuildMode.Tool.RESTAURANT_ROOM,
			BuildMode.Tool.DINING_TABLE,
			BuildMode.Tool.BOOTH,
			BuildMode.Tool.STALL_ROOM,
			BuildMode.Tool.GRAB_STALL,
		],
	},
	{
		"id": "shops",
		"name": "Shops",
		"tools":
		[
			BuildMode.Tool.KIOSK_ROOM,
			BuildMode.Tool.KIOSK_COUNTER,
			BuildMode.Tool.KIOSK_DISPLAY,
			BuildMode.Tool.PHARMACY_ROOM,
			BuildMode.Tool.PHARMACY_COUNTER,
			BuildMode.Tool.PHARMACY_SHELF,
			BuildMode.Tool.DUTY_FREE_ROOM,
			BuildMode.Tool.DUTY_FREE_TILL,
			BuildMode.Tool.DUTY_FREE_SHELF,
			BuildMode.Tool.FASHION_ROOM,
			BuildMode.Tool.FASHION_TILL,
			BuildMode.Tool.FASHION_RAIL,
		],
	},
	{
		"id": "decor",
		"name": "Decor",
		"tools":
		[
			BuildMode.Tool.BUSH,
			BuildMode.Tool.PLANTER,
			BuildMode.Tool.PLANT_POT,
			BuildMode.Tool.TREE,
			BuildMode.Tool.BENCH,
			BuildMode.Tool.TREE_BENCH,
			BuildMode.Tool.FOUNTAIN,
			BuildMode.Tool.STATUE,
			BuildMode.Tool.POST,
			BuildMode.Tool.CHAIN,
			BuildMode.Tool.BIN,
			BuildMode.Tool.PRIZE_PODIUM,
		],
	},
	{
		"id": "landside",
		"name": "Landside & Parking",
		"tools":
		[
			BuildMode.Tool.CURB,
			BuildMode.Tool.SURFACE_LOT,
			BuildMode.Tool.MULTI_STOREY,
			BuildMode.Tool.LOT_GATE,
		],
	},
	{"id": "remove", "name": "Remove", "tools": [BuildMode.Tool.REMOVE]},
]
## The category that is a single button with no tray, last in CATEGORIES (GDScript
## cannot take it from CATEGORIES.size(): tests check the two agree).
const REMOVE_CATEGORY := 7
const NO_CATEGORY := -1
## The open category while the Templates page (TemplatesPage) is open; its
## bar button presses it like a category (press_category()).
const TEMPLATES_PAGE := -2
## Visual sub-groups for divider placement inside multi-group "All" trays.
const VISUAL_GROUPS := {
	"operations":
	[
		[
			BuildMode.Tool.DESK,
			BuildMode.Tool.GATE_DESK,
			BuildMode.Tool.SEATS,
			BuildMode.Tool.SCREEN,
		],
		[
			BuildMode.Tool.SCANNER,
			BuildMode.Tool.TRAY_TABLE,
			BuildMode.Tool.XRAY_BELT,
			BuildMode.Tool.ARCH,
			BuildMode.Tool.PICKUP_TABLE,
		],
		[BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART],
	],
	"facilities":
	[
		[
			BuildMode.Tool.TOILET_ROOM,
			BuildMode.Tool.TOILET_STALL,
			BuildMode.Tool.TOILET_SINK,
			BuildMode.Tool.SHOWER_ROOM,
			BuildMode.Tool.SHOWER,
			BuildMode.Tool.NAP_POD_ROOM,
			BuildMode.Tool.NAP_POD,
		],
		[
			BuildMode.Tool.INFO_DESK,
			BuildMode.Tool.INFO_SCREEN,
			BuildMode.Tool.EXCHANGE_ROOM,
			BuildMode.Tool.EXCHANGE,
			BuildMode.Tool.ATM_ROOM,
			BuildMode.Tool.ATM,
		],
		[
			BuildMode.Tool.LOUNGE_ROOM,
			BuildMode.Tool.SOFA,
			BuildMode.Tool.ARMCHAIR,
			BuildMode.Tool.WORK_DESK,
			BuildMode.Tool.PLAY_AREA_ROOM,
			BuildMode.Tool.PLAY_BLOCKS,
			BuildMode.Tool.PLAY_SLIDE,
		],
	],
	"food":
	[
		[BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE],
		[BuildMode.Tool.BAR_ROOM, BuildMode.Tool.BAR_COUNTER],
		[BuildMode.Tool.RESTAURANT_ROOM, BuildMode.Tool.DINING_TABLE, BuildMode.Tool.BOOTH],
		[BuildMode.Tool.STALL_ROOM, BuildMode.Tool.GRAB_STALL],
	],
	"shops":
	[
		[BuildMode.Tool.KIOSK_ROOM, BuildMode.Tool.KIOSK_COUNTER, BuildMode.Tool.KIOSK_DISPLAY],
		[
			BuildMode.Tool.PHARMACY_ROOM,
			BuildMode.Tool.PHARMACY_COUNTER,
			BuildMode.Tool.PHARMACY_SHELF,
		],
		[
			BuildMode.Tool.DUTY_FREE_ROOM,
			BuildMode.Tool.DUTY_FREE_TILL,
			BuildMode.Tool.DUTY_FREE_SHELF,
		],
		[BuildMode.Tool.FASHION_ROOM, BuildMode.Tool.FASHION_TILL, BuildMode.Tool.FASHION_RAIL],
	],
}
## Lightweight sub-filter pills for multi-group tabs ("All" precedes these).
const SUBFILTERS := {
	"operations":
	[
		{
			"id": "checkin",
			"name": "Check-in & Gate",
			"tools":
			[
				BuildMode.Tool.DESK,
				BuildMode.Tool.GATE_DESK,
				BuildMode.Tool.SEATS,
				BuildMode.Tool.SCREEN,
			],
		},
		{
			"id": "security",
			"name": "Security",
			"tools":
			[
				BuildMode.Tool.SCANNER,
				BuildMode.Tool.TRAY_TABLE,
				BuildMode.Tool.XRAY_BELT,
				BuildMode.Tool.ARCH,
				BuildMode.Tool.PICKUP_TABLE,
			],
		},
		{
			"id": "baggage",
			"name": "Baggage",
			"tools": [BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART],
		},
	],
	"facilities":
	[
		{
			"id": "rooms",
			"name": "Rooms",
			"tools":
			[
				BuildMode.Tool.TOILET_ROOM,
				BuildMode.Tool.SHOWER_ROOM,
				BuildMode.Tool.NAP_POD_ROOM,
				BuildMode.Tool.EXCHANGE_ROOM,
				BuildMode.Tool.ATM_ROOM,
				BuildMode.Tool.LOUNGE_ROOM,
				BuildMode.Tool.PLAY_AREA_ROOM,
			],
		},
		{
			"id": "hygiene",
			"name": "Hygiene & Rest",
			"tools":
			[
				BuildMode.Tool.TOILET_ROOM,
				BuildMode.Tool.TOILET_STALL,
				BuildMode.Tool.TOILET_SINK,
				BuildMode.Tool.SHOWER_ROOM,
				BuildMode.Tool.SHOWER,
				BuildMode.Tool.NAP_POD_ROOM,
				BuildMode.Tool.NAP_POD,
			],
		},
		{
			"id": "services",
			"name": "Services",
			"tools":
			[
				BuildMode.Tool.INFO_DESK,
				BuildMode.Tool.INFO_SCREEN,
				BuildMode.Tool.EXCHANGE_ROOM,
				BuildMode.Tool.EXCHANGE,
				BuildMode.Tool.ATM_ROOM,
				BuildMode.Tool.ATM,
			],
		},
		{
			"id": "lounge_play",
			"name": "Lounge & Play",
			"tools":
			[
				BuildMode.Tool.LOUNGE_ROOM,
				BuildMode.Tool.SOFA,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.WORK_DESK,
				BuildMode.Tool.PLAY_AREA_ROOM,
				BuildMode.Tool.PLAY_BLOCKS,
				BuildMode.Tool.PLAY_SLIDE,
			],
		},
	],
	"food":
	[
		{
			"id": "rooms",
			"name": "Rooms",
			"tools":
			[
				BuildMode.Tool.CAFE_ROOM,
				BuildMode.Tool.BAR_ROOM,
				BuildMode.Tool.RESTAURANT_ROOM,
				BuildMode.Tool.STALL_ROOM,
			],
		},
		{
			"id": "items",
			"name": "Items",
			"tools":
			[
				BuildMode.Tool.COUNTER,
				BuildMode.Tool.TABLE,
				BuildMode.Tool.BAR_COUNTER,
				BuildMode.Tool.DINING_TABLE,
				BuildMode.Tool.BOOTH,
				BuildMode.Tool.GRAB_STALL,
			],
		},
	],
	"shops":
	[
		{
			"id": "rooms",
			"name": "Rooms",
			"tools":
			[
				BuildMode.Tool.KIOSK_ROOM,
				BuildMode.Tool.PHARMACY_ROOM,
				BuildMode.Tool.DUTY_FREE_ROOM,
				BuildMode.Tool.FASHION_ROOM,
			],
		},
		{
			"id": "items",
			"name": "Items",
			"tools":
			[
				BuildMode.Tool.KIOSK_COUNTER,
				BuildMode.Tool.KIOSK_DISPLAY,
				BuildMode.Tool.PHARMACY_COUNTER,
				BuildMode.Tool.PHARMACY_SHELF,
				BuildMode.Tool.DUTY_FREE_TILL,
				BuildMode.Tool.DUTY_FREE_SHELF,
				BuildMode.Tool.FASHION_TILL,
				BuildMode.Tool.FASHION_RAIL,
			],
		},
	],
}
## Card name, thumbnail and non-catalog size text per tool. Object sizes come from BuildCatalog.
const ITEMS := {
	BuildMode.Tool.FLOOR: ["Floor", "floor", "1x1 tile"],
	BuildMode.Tool.WALL: ["Wall", "wall", "1 m edge"],
	BuildMode.Tool.GLASS: ["Glass", "glass", "1 m edge"],
	BuildMode.Tool.DOOR: ["Door", "door", "1 m edge"],
	BuildMode.Tool.ENTRANCE: ["Entrance", "entrance", ""],
	BuildMode.Tool.EXIT: ["Exit", "exit", ""],
	BuildMode.Tool.DESK: ["Check-in desk", "desk", ""],
	BuildMode.Tool.SCANNER: ["Scanner", "scanner", ""],
	BuildMode.Tool.SEATS: ["Seats", "seats", ""],
	BuildMode.Tool.GATE_DESK: ["Gate desk", "gate_desk", ""],
	BuildMode.Tool.SCREEN: ["Screen", "screen_stand", ""],
	BuildMode.Tool.CAFE_ROOM: ["Cafe", "cafe_room", "3x3 min"],
	BuildMode.Tool.COUNTER: ["Counter", "counter", ""],
	BuildMode.Tool.TABLE: ["Table", "table", ""],
	BuildMode.Tool.TOILET_ROOM: ["Toilet", "toilet_room", "2x3 min"],
	BuildMode.Tool.TOILET_STALL: ["Toilet stall", "toilet_stall", ""],
	BuildMode.Tool.TOILET_SINK: ["Sink", "toilet_sink", ""],
	BuildMode.Tool.KIOSK_ROOM: ["Kiosk", "kiosk_room", "3x3 min"],
	BuildMode.Tool.KIOSK_COUNTER: ["Kiosk counter", "kiosk_counter", ""],
	# The store rooms carry their RoomTypes names and minimum sizes; the pieces'
	# short names suit their store's cards (FurnitureTools.ITEMS has the
	# pharmacy's).
	BuildMode.Tool.PHARMACY_ROOM: ["Pharmacy", "pharmacy_room", "3x3 min"],
	BuildMode.Tool.DUTY_FREE_ROOM: ["Duty free", "duty_free_room", "3x4 min"],
	BuildMode.Tool.DUTY_FREE_TILL: ["Duty Free Till", "duty_free_till", ""],
	BuildMode.Tool.DUTY_FREE_SHELF: ["Duty Free Shelf", "duty_free_shelf", ""],
	BuildMode.Tool.FASHION_ROOM: ["Fashion store", "fashion_room", "3x4 min"],
	BuildMode.Tool.FASHION_TILL: ["Fashion Till", "fashion_till", ""],
	BuildMode.Tool.FASHION_RAIL: ["Clothes rail", "fashion_rail", ""],
	BuildMode.Tool.EXCHANGE_ROOM: ["Exchange", "exchange_room", "2x3 min"],
	BuildMode.Tool.EXCHANGE: ["Exchange counter", "currency_exchange", ""],
	BuildMode.Tool.ATM_ROOM: ["ATM", "atm_room", "1x2 min"],
	BuildMode.Tool.BAR_ROOM: ["Bar", "bar_room", "3x4 min"],
	BuildMode.Tool.RESTAURANT_ROOM: ["Restaurant", "restaurant_room", "4x4 min"],
	BuildMode.Tool.STALL_ROOM: ["Grab-and-go", "grab_and_go_room", "3x3 min"],
	# The activity rooms carry the Room badge alongside their main piece preview.
	BuildMode.Tool.PLAY_AREA_ROOM: ["Play area", "play_slide", "3x4 min"],
	BuildMode.Tool.LOUNGE_ROOM: ["Lounge", "lounge_sofa", "2x3 min"],
	BuildMode.Tool.SHOWER_ROOM: ["Shower", "shower_cubicle", "2x2 min"],
	BuildMode.Tool.SHOWER: ["Shower cubicle", "shower_cubicle", ""],
	BuildMode.Tool.NAP_POD_ROOM: ["Nap pod", "nap_pod", "2x2 min"],
	BuildMode.Tool.NAP_POD: ["Sleeping pod", "nap_pod", ""],
	BuildMode.Tool.KIOSK_DISPLAY: ["Display stand", "kiosk_display", ""],
	BuildMode.Tool.BELT: ["Belt", "belt", "Drag a line"],
	BuildMode.Tool.BAG_ROOM: ["Bag room", "bag_room", "2x2 min"],
	BuildMode.Tool.CART: ["Bag cart", "cart", ""],
	BuildMode.Tool.CURB: ["Curb bay", "curb_bay", "16x3 m"],
	BuildMode.Tool.SURFACE_LOT: ["Surface lot", "surface_lot", "32x24 m"],
	BuildMode.Tool.MULTI_STOREY: ["Multi-storey", "multi_storey", "24x52 m"],
	BuildMode.Tool.LOT_GATE: ["Open / close", "lot_gate", "A car park"],
	BuildMode.Tool.BUY_LAND: ["Buy land", "buy_land", "about 21x25 m plot"],
}
## The security lane part cards, as ITEMS (item() looks in both).
const LANE_ITEMS := {
	BuildMode.Tool.TRAY_TABLE: ["Tray table", "tray_table", ""],
	BuildMode.Tool.XRAY_BELT: ["X-ray belt", "xray_belt", ""],
	BuildMode.Tool.ARCH: ["Arch", "arch", ""],
	BuildMode.Tool.PICKUP_TABLE: ["Pickup table", "pickup_table", ""],
}
## Hover details that say what the placed thing needs to work, in the warning
## colour: a bag room does nothing without a belt end.
const CARD_NEEDS := {BuildMode.Tool.BAG_ROOM: "Needs belt end"}
## Hover details that say what the placed thing costs to run, in the plain hint
## style (costs are never red), alongside FurnitureTools.RUNNING_COSTS: a toilet
## stall is charged its upkeep every game day once its room is ready, a screen
## stand wherever it stands.
const CARD_RUNNING_COSTS := {
	BuildMode.Tool.TOILET_STALL: PriceTable.TOILET_STALL_UPKEEP,
	BuildMode.Tool.SCREEN: PriceTable.SCREEN_UPKEEP,
}


## Progressive card visibility state (OPEN, TEASER, HIDDEN or unwired LOCKED).
static func card_state(tool: int, unlocks: BuildUnlocks, require_unlocks: bool, demo: bool) -> int:
	if not require_unlocks:
		return CardState.OPEN
	var needed := BuildUnlocks.tier_of(tool as BuildMode.Tool)
	if needed == 0:
		return CardState.OPEN
	if unlocks == null:
		return CardState.LOCKED
	var cap := mini(unlocks.tier(), DemoMode.MAX_PLAYABLE_TIER) if demo else unlocks.tier()
	if needed <= cap:
		return CardState.OPEN
	if demo and unlocks.tier() >= DemoMode.MAX_PLAYABLE_TIER and needed == DemoMode.TEASER_TIER:
		return CardState.TEASER
	return CardState.HIDDEN


## What a tool's card costs: the floor tile, one wall piece or the object.
## 0 for a tool with no price (Remove, a room, no tool).
static func tool_price(tool: BuildMode.Tool) -> int:
	if tool == BuildMode.Tool.FLOOR:
		return PriceTable.price_of_floor()
	if BuildMode.TOOL_WALL_KINDS.has(tool):
		return PriceTable.price_of_wall(BuildMode.TOOL_WALL_KINDS[tool])
	if BuildMode.tool_object(tool) != &"":
		return PriceTable.price_of_object(BuildMode.tool_object(tool))
	if tool == BuildMode.Tool.BELT:
		return PriceTable.price_of_object(BuildMode.BELT_PRICE_ID)
	if BuildMode.LANDSIDE_BUILD_TOOLS.has(tool):
		return PriceTable.price_of_landside(
			LandsidePlacement.PRICE_IDS[BuildMode.LANDSIDE_BUILD_TOOLS[tool]]
		)
	return 0


## The categories in bar order (CATEGORIES).
static func categories() -> Array:
	return CATEGORIES.duplicate()


## Stable identifier of category `index` ("building", "operations", ...).
static func category_id(index: int) -> String:
	return CATEGORIES[index]["id"]


## Index of the category with stable `id`, or NO_CATEGORY.
static func category_index(id: String) -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i]["id"] == id:
			return i
	return NO_CATEGORY


## The index of the Remove button, last in categories().
static func remove_category() -> int:
	return categories().size() - 1


## A tool's card [name, thumbnail, size text] from ITEMS, LANE_ITEMS or
## FurnitureTools.ITEMS, or an empty array for a tool with no card.
static func item(tool: BuildMode.Tool) -> Array:
	return ITEMS.get(tool, LANE_ITEMS.get(tool, FurnitureTools.ITEMS.get(tool, [])))


## What a card says its piece costs to run per day, or 0 for none.
static func running_cost(tool: BuildMode.Tool) -> int:
	return CARD_RUNNING_COSTS.get(tool, FurnitureTools.RUNNING_COSTS.get(tool, 0))


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	var all := categories()
	for i in all.size():
		if all[i]["tools"].has(tool):
			return i
	return NO_CATEGORY


## Footprint size string for `tool` (from BuildCatalog or ITEMS[tool][2]).
static func size_text(tool: BuildMode.Tool) -> String:
	if BuildMode.tool_object(tool) != &"":
		var def := BuildCatalog.get_def(BuildMode.tool_object(tool))
		return "%dx%d" % [def.size.x, def.size.y]
	var entry := item(tool)
	return shown(entry[2]) if entry.size() >= 3 and entry[2] != "" else ""


## Placement mode text: a rectangle or belt tool is drawn by dragging, any other is a click.
static func no_key_hint(tool: BuildMode.Tool) -> String:
	return Words.new().drag_or_click(BuildMode.AREA_TOOLS.has(tool))


## "Upkeep 20/day": what a hover card or a built item's card says it costs to run.
static func upkeep_text(amount: int) -> String:
	return Words.new().upkeep(amount)


## Structured [text, variation] chips for `tool`'s hover popup: footprint size,
## placement mode (Click/Drag), upkeep, and special requirements (Needs belt end).
static func card_details(tool: BuildMode.Tool) -> Array:
	var out := []
	var footprint := size_text(tool)
	if footprint != "":
		out.append([footprint, &"HudHint"])
	out.append([no_key_hint(tool), &"HudHint"])
	var upkeep := running_cost(tool)
	if upkeep > 0:
		out.append([upkeep_text(upkeep), &"HudHint"])
	if CARD_NEEDS.has(tool):
		out.append([shown(CARD_NEEDS[tool]), &"HudAttentionText"])
	return out


## Whether `tool` draws a room zone (used to disambiguate room cards from objects).
static func is_room_tool(tool: BuildMode.Tool) -> bool:
	return BuildMode.TOOL_ROOMS.has(tool)


## Visual group lists for `category_id`, or an empty array for single-group tabs.
static func visual_groups(cat_id: String) -> Array:
	return VISUAL_GROUPS.get(cat_id, [])


## Sub-filter definitions for `category_id`, or an empty array for single-group tabs.
static func subfilters(cat_id: String) -> Array:
	return SUBFILTERS.get(cat_id, [])


## Thumbnail id for a room type (`RoomTypes` id), matching its room-zone card.
static func room_thumbnail(room_type: StringName) -> String:
	for tool: BuildMode.Tool in BuildMode.TOOL_ROOMS:
		if BuildMode.TOOL_ROOMS[tool] == room_type:
			var card_item := item(tool)
			if card_item.size() >= 2:
				return str(card_item[1])
	return ""


## A table name of this file or FurnitureTools (a category, a card, a size text,
## a need) in the player's language. The names stay English in the tables;
## Words.msgids() lists them for POT generation.
static func shown(msgid: String) -> String:
	return TranslationServer.translate(msgid, NAME_CONTEXT)


## tr() is an instance method, so the static code of this file asks a Words.
class Words:
	extends RefCounted

	func drag_or_click(drag: bool) -> String:
		return tr("Drag", "card hint") if drag else tr("Click", "card hint")

	func upkeep(amount: int) -> String:
		return tr("Upkeep {amount}/day").format({"amount": amount})

	## Never called: every table name inside tr(), so POT generation finds it.
	## A test checks that each name in the tables is here.
	func msgids() -> Array[String]:
		return [
			tr("Building", "build menu"),
			tr("Operations", "build menu"),
			tr("Facilities", "build menu"),
			tr("Food & Drink", "build menu"),
			tr("Shops", "build menu"),
			tr("Decor", "build menu"),
			tr("Landside & Parking", "build menu"),
			tr("Remove", "build menu"),
			tr("Templates", "build menu"),
			tr("All", "build menu"),
			tr("Room", "build menu"),
			tr("Check-in & Gate", "build menu"),
			tr("Security", "build menu"),
			tr("Baggage", "build menu"),
			tr("Rooms", "build menu"),
			tr("Hygiene & Rest", "build menu"),
			tr("Services", "build menu"),
			tr("Lounge & Play", "build menu"),
			tr("Items", "build menu"),
			tr("Floor", "build menu"),
			tr("1x1 tile", "build menu"),
			tr("Wall", "build menu"),
			tr("1 m edge", "build menu"),
			tr("Glass", "build menu"),
			tr("Door", "build menu"),
			tr("Entrance", "build menu"),
			tr("Exit", "build menu"),
			tr("Check-in desk", "build menu"),
			tr("Scanner", "build menu"),
			tr("Seats", "build menu"),
			tr("Gate desk", "build menu"),
			tr("Screen", "build menu"),
			tr("Cafe", "build menu"),
			tr("3x3 min", "build menu"),
			tr("Counter", "build menu"),
			tr("Table", "build menu"),
			tr("Toilet", "build menu"),
			tr("2x3 min", "build menu"),
			tr("Toilet stall", "build menu"),
			tr("Sink", "build menu"),
			tr("Kiosk", "build menu"),
			tr("Kiosk counter", "build menu"),
			tr("Pharmacy", "build menu"),
			tr("Duty free", "build menu"),
			tr("3x4 min", "build menu"),
			tr("Duty Free Till", "build menu"),
			tr("Duty Free Shelf", "build menu"),
			tr("Shelf", "build menu"),
			tr("Fashion store", "build menu"),
			tr("Fashion Till", "build menu"),
			tr("Clothes rail", "build menu"),
			tr("Exchange", "build menu"),
			tr("Exchange counter", "build menu"),
			tr("ATM", "build menu"),
			tr("1x2 min", "build menu"),
			tr("Bar", "build menu"),
			tr("Restaurant", "build menu"),
			tr("4x4 min", "build menu"),
			tr("Grab-and-go", "build menu"),
			tr("Play area", "build menu"),
			tr("Lounge", "build menu"),
			tr("Shower", "build menu"),
			tr("Shower cubicle", "build menu"),
			tr("2x2 min", "build menu"),
			tr("Nap pod", "build menu"),
			tr("Sleeping pod", "build menu"),
			tr("Display stand", "build menu"),
			tr("Belt", "build menu"),
			tr("Drag a line", "build menu"),
			tr("Bag room", "build menu"),
			tr("Bag cart", "build menu"),
			tr("Curb bay", "build menu"),
			tr("16x3 m", "build menu"),
			tr("Surface lot", "build menu"),
			tr("32x24 m", "build menu"),
			tr("Multi-storey", "build menu"),
			tr("24x52 m", "build menu"),
			tr("Open / close", "build menu"),
			tr("A car park", "build menu"),
			tr("Buy land", "build menu"),
			tr("about 21x25 m plot", "build menu"),
			tr("Tray table", "build menu"),
			tr("X-ray belt", "build menu"),
			tr("Arch", "build menu"),
			tr("Pickup table", "build menu"),
			tr("Needs belt end", "build menu"),
			tr("Staff", "build menu"),
		]
