class_name BuildMenuCatalog
extends RefCounted
## What the build menu shows and where: its categories, the card per tool, key
## hints and prices, and the page arithmetic (split out of BuildMenu; BuildMenu
## keeps aliases of these constants and one-line delegates of these functions).
## Static only; it must not reference BuildMenu.

const THUMBNAIL_DIR := "res://assets/ui/thumbnails/%s.png"
const CATEGORIES := [
	{
		"name": "Structure",
		"tools":
		[BuildMode.Tool.FLOOR, BuildMode.Tool.WALL, BuildMode.Tool.GLASS, BuildMode.Tool.DOOR],
	},
	{"name": "Doors", "tools": [BuildMode.Tool.ENTRANCE, BuildMode.Tool.EXIT]},
	{"name": "Check-in", "tools": [BuildMode.Tool.DESK]},
	{"name": "Security", "tools": [BuildMode.Tool.SCANNER]},
	# The security lane's four parts in flow order (decisions security-lane-
	# parts-are-placed-separately-tray-table-x-ray-b and security-lane-parts-
	# get-their-own-lane-build-category): four parts get a tray of their own,
	# right after Security.
	{"name": "Lane", "tools": BuildMode.LANE_TOOLS},
	# The screen stand (Boredom 4/5) entertains passengers waiting at the gate.
	# The gate desk (gates 1b) makes a gate of the north exit it stands by.
	{
		"name": "Gates",
		"tools": [BuildMode.Tool.GATE_DESK, BuildMode.Tool.SEATS, BuildMode.Tool.SCREEN],
	},
	# The cafe, its counter and its table. Named Shops until HUD 6/7 gave that
	# name to the store group's button below.
	{
		"name": "Cafe",
		"tools": [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE],
	},
	# The toilet room and its two pieces (Toilets 5/5). Cafe holds three cards
	# already; six cards are wider than COLUMN_W, so the toilet gets a tray of
	# its own, as the Lane did.
	{
		"name": "Toilets",
		"tools":
		[BuildMode.Tool.TOILET_ROOM, BuildMode.Tool.TOILET_STALL, BuildMode.Tool.TOILET_SINK],
	},
	# The kiosk room and its two pieces (Boredom 2/5), a tray of their own for
	# the same reason as the toilet's.
	{
		"name": "Kiosk",
		"tools":
		[BuildMode.Tool.KIOSK_ROOM, BuildMode.Tool.KIOSK_COUNTER, BuildMode.Tool.KIOSK_DISPLAY],
	},
	# The landside tools (Landside 3/4): a curb bay and the two car park kinds
	# snap to the authored spots outside the terminal; Close opens or closes a
	# car park so it can drain before Remove takes it back.
	{
		"name": "Landside",
		"tools":
		[
			BuildMode.Tool.CURB,
			BuildMode.Tool.SURFACE_LOT,
			BuildMode.Tool.MULTI_STOREY,
			BuildMode.Tool.LOT_GATE,
		],
	},
	# The Buy land tool (user ruling land-plots-are-bought-with-a-buy-land-
	# tool-in-build-mode-buy), a tray of its own beside the landside tools, so
	# the furniture groups still run on to Remove.
	{"name": "Land", "tools": [BuildMode.Tool.BUY_LAND]},
	# One Belt tool shapes itself (decision baggage-belts-are-one-auto-shaping-
	# belt-tool-one-baggage-tray), so baggage fits one tray.
	{
		"name": "Baggage",
		"tools": [BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART],
	},
	# The furniture and the rooms that go with it, in five groups (decision
	# hud-6-7-furniture-groups-five-icon-buttons-decor-food-servic): Decor, Food,
	# Services, Leisure and Shops. A group's first page has the bar button and
	# carries the group's name ("group"); a later page ("page": true) has none
	# and is reached by the Next card on the page before it, and the group's
	# last page leads back to its first. A tray holds four cards and the Next
	# column in COLUMN_W, so a group with more pieces pages inside its
	# tray. The Dining, Money and Activities pages joined Food, Services and
	# Leisure: the ruling named the eleven pages there were before them.
	{"name": "Furniture", "group": "Decor", "tools": FurnitureTools.PAGES[0]},
	{"name": "Features", "tools": FurnitureTools.PAGES[1], "page": true},
	{"name": "Fittings", "tools": FurnitureTools.PAGES[2], "page": true},
	{"name": "Food", "group": "Food", "tools": FurnitureTools.PAGES[3]},
	# The food variants (F4-6): three rooms that take the Cafe tray's counter and
	# table, so a page of their own holds just the room cards.
	{
		"name": "Dining",
		"tools":
		[BuildMode.Tool.BAR_ROOM, BuildMode.Tool.RESTAURANT_ROOM, BuildMode.Tool.STALL_ROOM],
		"page": true,
	},
	{"name": "Desks", "group": "Services", "tools": FurnitureTools.PAGES[4]},
	{"name": "Care", "tools": FurnitureTools.PAGES[5], "page": true},
	# The exchange and the ATM (F4-5b) share one Money page: each room with its
	# one piece, four cards that fit beside the Next column.
	{
		"name": "Money",
		"tools":
		[
			BuildMode.Tool.EXCHANGE_ROOM,
			BuildMode.Tool.EXCHANGE,
			BuildMode.Tool.ATM_ROOM,
			BuildMode.Tool.ATM,
		],
		"page": true,
	},
	{"name": "Lounge", "group": "Leisure", "tools": FurnitureTools.PAGES[6]},
	{"name": "Fun", "tools": FurnitureTools.PAGES[7], "page": true},
	# The activity and rest rooms (F4-7): each takes its own piece from the
	# Lounge and Fun pages, so a page of their own holds just the room cards.
	{
		"name": "Activities",
		"tools":
		[
			BuildMode.Tool.PLAY_AREA_ROOM,
			BuildMode.Tool.LOUNGE_ROOM,
			BuildMode.Tool.SHOWER_ROOM,
			BuildMode.Tool.NAP_POD_ROOM,
		],
		"page": true,
	},
	# The store pages (decision store-rooms-and-retail-pieces-go-on-stores-
	# pages-behind-the-furniture-button): one per store, its room, then its
	# counter or till and its shelf or rail, as the Toilets and Kiosk trays hold
	# theirs.
	{
		"name": "Pharmacy",
		"group": "Shops",
		"tools":
		[
			BuildMode.Tool.PHARMACY_ROOM,
			BuildMode.Tool.PHARMACY_COUNTER,
			BuildMode.Tool.PHARMACY_SHELF,
		],
	},
	{
		"name": "Duty free",
		"tools":
		[
			BuildMode.Tool.DUTY_FREE_ROOM,
			BuildMode.Tool.DUTY_FREE_TILL,
			BuildMode.Tool.DUTY_FREE_SHELF,
		],
		"page": true,
	},
	{
		"name": "Fashion",
		"tools":
		[BuildMode.Tool.FASHION_ROOM, BuildMode.Tool.FASHION_TILL, BuildMode.Tool.FASHION_RAIL],
		"page": true,
	},
	{"name": "Remove", "tools": [BuildMode.Tool.REMOVE]},
]
## The category that is a single button with no tray, last in CATEGORIES (GDScript
## cannot take it from CATEGORIES.size(): tests check the two agree).
const REMOVE_CATEGORY := 26
const NO_CATEGORY := -1
## The open category while the Templates page (TemplatesPage) is open; its
## bar button presses it like a category (press_category()).
const TEMPLATES_PAGE := -2
## Card name and thumbnail per tool. Object sizes come from BuildCatalog.
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
	# short names suit their store's page (FurnitureTools.ITEMS has the
	# pharmacy's).
	BuildMode.Tool.PHARMACY_ROOM: ["Pharmacy", "pharmacy_room", "3x3 min"],
	BuildMode.Tool.DUTY_FREE_ROOM: ["Duty free", "duty_free_room", "3x4 min"],
	BuildMode.Tool.DUTY_FREE_TILL: ["Till", "duty_free_till", ""],
	BuildMode.Tool.DUTY_FREE_SHELF: ["Shelf", "duty_free_shelf", ""],
	BuildMode.Tool.FASHION_ROOM: ["Fashion store", "fashion_room", "3x4 min"],
	BuildMode.Tool.FASHION_TILL: ["Till", "fashion_till", ""],
	BuildMode.Tool.FASHION_RAIL: ["Clothes rail", "fashion_rail", ""],
	BuildMode.Tool.EXCHANGE_ROOM: ["Exchange", "exchange_room", "2x3 min"],
	BuildMode.Tool.ATM_ROOM: ["ATM", "atm_room", "1x2 min"],
	# The food rooms borrow the cafe's thumbnail: no new art (F4-6).
	BuildMode.Tool.BAR_ROOM: ["Bar", "cafe_room", "3x4 min"],
	BuildMode.Tool.RESTAURANT_ROOM: ["Restaurant", "cafe_room", "4x4 min"],
	BuildMode.Tool.STALL_ROOM: ["Grab-and-go", "cafe_room", "3x3 min"],
	# The activity rooms borrow their main piece's thumbnail: no new art (F4-7).
	BuildMode.Tool.PLAY_AREA_ROOM: ["Play area", "play_slide", "3x4 min"],
	BuildMode.Tool.LOUNGE_ROOM: ["Lounge", "lounge_sofa", "2x3 min"],
	BuildMode.Tool.SHOWER_ROOM: ["Shower", "shower_cubicle", "2x2 min"],
	BuildMode.Tool.NAP_POD_ROOM: ["Nap pod", "nap_pod", "2x2 min"],
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
## The Lane tray's cards, as ITEMS (item() looks in both).
const LANE_ITEMS := {
	BuildMode.Tool.TRAY_TABLE: ["Tray table", "tray_table", ""],
	BuildMode.Tool.XRAY_BELT: ["X-ray belt", "xray_belt", ""],
	BuildMode.Tool.ARCH: ["Arch", "arch", ""],
	BuildMode.Tool.PICKUP_TABLE: ["Pickup table", "pickup_table", ""],
}
## Cards that say what the placed thing needs to work, in the warning colour,
## in place of the "Click" hint (the card has no height to spare). A bag room
## does nothing without a belt end.
const CARD_NEEDS := {BuildMode.Tool.BAG_ROOM: "Needs belt end"}
## Cards that say what the placed thing costs to run, in the plain hint style
## (costs are never red), in place of the "Click" hint: a toilet stall is
## charged its upkeep every game day once its room is ready, a screen stand
## wherever it stands.
const CARD_RUNNING_COSTS := {
	BuildMode.Tool.TOILET_STALL: PriceTable.TOILET_STALL_UPKEEP,
	BuildMode.Tool.SCREEN: PriceTable.SCREEN_UPKEEP,
}
const RUNNING_COST_TEXT := "Upkeep %d/day"


## "3" for the key bound to a tool's action, or "" when the tool has none.
static func key_hint(tool: BuildMode.Tool) -> String:
	for action in BuildMode.TOOL_ACTIONS:
		if BuildMode.TOOL_ACTIONS[action] != tool or not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				return OS.get_keycode_string(key.physical_keycode)
	return ""


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


## The name a category's bar button carries in its tooltip: its group's name
## on a group's first page, else its own.
static func bar_name(index: int) -> String:
	return CATEGORIES[index].get("group", CATEGORIES[index]["name"])


## The first page of the named group (its bar button), or NO_CATEGORY.
static func group_index(group_name: String) -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i].get("group", "") == group_name:
			return i
	return NO_CATEGORY


## The first page of the group a category belongs to (CATEGORIES), or the
## category itself when it is not a later page.
static func group_start(index: int) -> int:
	while index > 0 and CATEGORIES[index].get("page", false):
		index -= 1
	return index


## The page the Next card of a category opens: the following page, the group's
## first page after its last, or NO_CATEGORY for a category with no pages.
static func next_page(index: int) -> int:
	if index + 1 < CATEGORIES.size() and CATEGORIES[index + 1].get("page", false):
		return index + 1
	var start := group_start(index)
	return start if start != index else NO_CATEGORY


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	var all := categories()
	for i in all.size():
		if all[i]["tools"].has(tool):
			return i
	return NO_CATEGORY


## What a card with no key says: a rectangle tool is drawn by dragging, any
## other is a click.
static func no_key_hint(tool: BuildMode.Tool) -> String:
	return "Drag" if BuildMode.AREA_TOOLS.has(tool) else "Click"
