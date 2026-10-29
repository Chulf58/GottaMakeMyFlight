class_name BuildMenu
extends CanvasLayer
## The build menu (decision hud-layout-bottom-category-bar-with-an-item-tray-time-and-fl):
## a bar of categories along the bottom edge; clicking one opens a tray of
## item cards above it (thumbnail, name, size, price, key hint); the status
## and refusal text sits at one fixed place above the tray's reserved space;
## a money slot sits top-left. BuildMode keeps the tool logic: the menu calls
## set_tool() and rotate_facing() and follows tool_changed and status_changed.
## Opening a category picks no tool; picking a card does, and a tool picked by
## key opens its own category. Esc (tool NONE) closes the tray. The menu also
## owns the room info panel (RoomPanel), top-left under the money slot. The
## status line also shows the rescue grant's message when one is paid (ruling
## going-broke-a-one-off-rescue-grant-when-the-airport-is-stuck) for
## grant_hold_s seconds (a later grant restarts the hold); status text that
## arrives meanwhile (the pointer moving over the grid changes it) waits and
## shows when the hold ends.
##
## The Staff button ends the bar, after the categories. It has no tray of
## cards: it opens the StaffPanel's hiring card in the tray's place (the panel
## follows staff_toggled), and it is shut by opening a category or picking a
## tool, as a tray is by another.
##
## Money (ruling building-costs-money-from-a-starting-budget-you-can-t-build):
## the money slot shows the wallet BuildMode pays from and follows it; each
## card shows its price and greys out while the wallet cannot pay it (it can
## still be picked, so the cost line can show the shortfall); a cost line above
## the status line shows what the tool, or the dragged Floor rectangle, would
## cost and how short the wallet is. Prices stay in the price colour, never
## red. With no wallet (BuildMode builds for free) the slot reads "--" and
## every card says Free. Hovering the money slot shows today's money from the
## DayLedger (MoneySlot) when day_ledger is set.

## The hiring card opened or closed (the StaffPanel shows it with this).
signal staff_toggled(open: bool)

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
	# get-their-own-lane-build-category): five cards and the rotate card are
	# wider than COLUMN_W, so they get a tray of their own, right after
	# Security.
	{"name": "Lane", "tools": BuildMode.LANE_TOOLS},
	# The screen stand (Boredom 4/5) entertains passengers waiting at the gate.
	{"name": "Gates", "tools": [BuildMode.Tool.SEATS, BuildMode.Tool.SCREEN]},
	{
		"name": "Shops",
		"tools": [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE],
	},
	# The toilet room and its two pieces (Toilets 5/5). Shops holds three cards
	# and Rotate already; six cards and Rotate are wider than COLUMN_W, so the
	# toilet gets a tray of its own, as the Lane did.
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
	# One Belt tool shapes itself (decision baggage-belts-are-one-auto-shaping-
	# belt-tool-one-baggage-tray), so baggage fits one tray.
	{
		"name": "Baggage",
		"tools": [BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART],
	},
	{"name": "Remove", "tools": [BuildMode.Tool.REMOVE]},
]
## The category that is a single button with no tray.
const REMOVE_CATEGORY := 11
const NO_CATEGORY := -1
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
	BuildMode.Tool.SCREEN: ["Screen", "screen_stand", ""],
	BuildMode.Tool.CAFE_ROOM: ["Cafe", "cafe_room", "3x3 min"],
	BuildMode.Tool.COUNTER: ["Counter", "counter", ""],
	BuildMode.Tool.TABLE: ["Table", "table", ""],
	BuildMode.Tool.TOILET_ROOM: ["Toilet", "toilet_room", "2x3 min"],
	BuildMode.Tool.TOILET_STALL: ["Toilet stall", "toilet_stall", ""],
	BuildMode.Tool.TOILET_SINK: ["Sink", "toilet_sink", ""],
	BuildMode.Tool.KIOSK_ROOM: ["Kiosk", "kiosk_room", "3x3 min"],
	BuildMode.Tool.KIOSK_COUNTER: ["Kiosk counter", "kiosk_counter", ""],
	BuildMode.Tool.KIOSK_DISPLAY: ["Display stand", "kiosk_display", ""],
	BuildMode.Tool.BELT: ["Belt", "belt", "Drag a line"],
	BuildMode.Tool.BAG_ROOM: ["Bag room", "bag_room", "2x2 min"],
	BuildMode.Tool.CART: ["Bag cart", "cart", ""],
	BuildMode.Tool.CURB: ["Curb bay", "curb_bay", "16x3 m"],
	BuildMode.Tool.SURFACE_LOT: ["Surface lot", "surface_lot", "32x24 m"],
	BuildMode.Tool.MULTI_STOREY: ["Multi-storey", "multi_storey", "24x52 m"],
	BuildMode.Tool.LOT_GATE: ["Open / close", "lot_gate", "A car park"],
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
## Cards whose thumbnail is not rendered yet
## (tools/blender/thumbnails/render_kit_thumbnails.py renders the others). They
## show a plain tile until the PNG exists; any other missing PNG is an error.
const PLACEHOLDER_THUMBNAILS := []
const PLACEHOLDER_COLOR := Color(0.3, 0.26, 0.2)
## The price slot of a card with no price (a room), or of any card when
## BuildMode has no wallet.
const PRICE_TEXT := "Free"
## The money slot when BuildMode has no wallet.
const MONEY_TEXT := "Money  --"

## Geometry in pixels, measured up from the bottom edge.
const MARGIN := 8.0
const BAR_H := 52.0
const GAP := 6.0
const TRAY_H := 196.0
const STATUS_H := 52.0
const COST_H := 26.0
## Width of the centre column the tray and status line live in; PassengerHud
## keeps the follow text left of it.
const COLUMN_W := 640.0
const CARD_SIZE := Vector2(112.0, 176.0)
const THUMB_SIZE := 72.0
## The card hint labels' font size, as HudHint sets it.
const CARD_HINT_FONT_SIZE := 14
const CATEGORY_SIZE := Vector2(100.0, 44.0)
const ROTATE_SIZE := Vector2(72.0, 176.0)

## The one HUD theme (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).
## A CanvasLayer does not pass a theme down, so every top-level HUD Control
## under a CanvasLayer sets it itself.
const HUD_THEME := preload("res://ui/hud_theme.tres")
## How long a rescue grant's or wages-paid message stays on the status line, in seconds.
const GRANT_HOLD_S := 8.0

@export var build_mode: BuildMode
## Optional: when set, its paid grants are announced on the status line.
@export var rescue_grant: RescueGrant
## Seconds a grant message holds the status line.
@export var grant_hold_s := GRANT_HOLD_S
## Optional: when set, hovering the money slot shows today's money.
@export var day_ledger: DayLedger
## Optional: when set, the money card shows owed wages.
@export var settlement: Settlement
## Optional: when set, a successful load ends any message hold (the notices
## belong to the world that was replaced).
@export var save_game: SaveGame
## Optional: paused while build mode lasts (BuildSession).
@export var clock: SimClock

## True while the hiring card is open; press_staff() changes it.
var staff_open := false
## The Staff button at the end of the bar.
var staff_button := Button.new()
## Build mode: a tray open or a tool picked (decision build-mode-pauses-the-
## game-while-a-build-tray-is-open-closin). The frame is its on-screen sign.
var build_session := BuildSession.new()
var build_frame := BuildModeFrame.new()

var _open := NO_CATEGORY
## True while a category click clears the tool, so the tool_changed(NONE)
## that follows does not close the tray being opened.
var _browsing := false
var _bar := PanelContainer.new()
var _tray := PanelContainer.new()
var _rows: Array[HBoxContainer] = []
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
var _status := Label.new()
var _money := Label.new()
var _money_slot := MoneySlot.new()
var _cost := Label.new()
## The wallet building is paid from, or null when the tools build for free.
var _wallet: Wallet
## Card tool -> its price Label.
var _price_labels: Dictionary = {}
## The last dragged rectangle priced (rectangle and balance) and its cost.
var _rect_cost_key := ""
var _rect_cost := 0
var _room_panel := RoomPanel.new()
## True while the status line holds a grant message; the latest status text
## waits in _held_status until the hold ends.
var _holding := false
## Counts grants, so only the latest grant's timer ends the hold.
var _hold_generation := 0
var _held_status := ""
## True while the hold shows a rescue grant's message, false for a wage one.
var _hold_is_grant := false
## A wages-paid message that waited for a rescue message's hold to end; "" if none.
var _pending_wages := ""


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
	if BuildMode.TOOL_OBJECTS.has(tool):
		return PriceTable.price_of_object(BuildMode.TOOL_OBJECTS[tool])
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


## A tool's card [name, thumbnail, size text] from ITEMS or LANE_ITEMS, or
## an empty array for a tool with no card.
static func item(tool: BuildMode.Tool) -> Array:
	return ITEMS.get(tool, LANE_ITEMS.get(tool, []))


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	var all := categories()
	for i in all.size():
		if all[i]["tools"].has(tool):
			return i
	return NO_CATEGORY


func _ready() -> void:
	layer = 2
	build_session.build_mode = build_mode
	build_session.clock = clock
	build_session.changed.connect(build_frame.set_building)
	add_child(build_session)
	add_child(build_frame)
	_build_bar()
	_build_tray()
	_build_status()
	_build_money()
	_build_cost()
	add_child(_room_panel)
	if build_mode != null:
		_wallet = build_mode.wallet()
		_room_panel.watch(build_mode)
		build_mode.tool_changed.connect(_on_tool_changed)
		build_mode.status_changed.connect(_on_status_changed)
		_on_status_changed(build_mode.status_text())
		_on_tool_changed(build_mode.tool)
	else:
		_sync()
	if _wallet != null:
		_wallet.changed.connect(_on_balance_changed)
	_refresh_money()
	if rescue_grant != null:
		rescue_grant.granted.connect(_on_granted)
	if settlement != null:
		settlement.wages_paid.connect(_on_wages_paid)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	if day_ledger != null:
		_money_slot.watch(day_ledger, settlement)


func _process(_delta: float) -> void:
	refresh_preview()


## The open category, or NO_CATEGORY when the tray is closed.
func open_category() -> int:
	return _open


func is_tray_open() -> bool:
	return _tray.visible


## A category button click: opens its tray (picking no tool), closes it when
## it is already open, or picks Remove, which has no tray.
func press_category(index: int) -> void:
	_set_staff_open(false)
	if index == remove_category():
		build_mode.set_tool(BuildMode.Tool.REMOVE)
		return
	if index == _open:
		build_mode.set_tool(BuildMode.Tool.NONE)
		return
	_open = index
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()


## The Staff button click: opens the hiring card (closing any tray and
## dropping the tool), or closes it when it is open.
func press_staff() -> void:
	if staff_open:
		_set_staff_open(false)
		return
	_open = NO_CATEGORY
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_set_staff_open(true)
	_sync()


## A card click: picks its tool.
func press_card(tool: BuildMode.Tool) -> void:
	build_mode.set_tool(tool)


func category_button(index: int) -> Button:
	return _category_buttons[index]


func card(tool: BuildMode.Tool) -> Button:
	return _cards.get(tool)


func tray() -> Control:
	return _tray


func bar() -> Control:
	return _bar


func status_label() -> Label:
	return _status


func money_label() -> Label:
	return _money


func preview_label() -> Label:
	return _cost


## The text on a card's price slot: its price, or Free.
func card_price_text(tool: BuildMode.Tool) -> String:
	return (_price_labels[tool] as Label).text


func card_price_label(tool: BuildMode.Tool) -> Label:
	return _price_labels[tool]


## False while the wallet cannot pay the card's price; true with no wallet.
func is_card_affordable(tool: BuildMode.Tool) -> bool:
	return _wallet == null or _wallet.can_afford(tool_price(tool))


## What greys out a card the wallet cannot pay: the theme's HudCard
## unaffordable_tint (hud_theme.tres).
static func unaffordable_tint() -> Color:
	return HUD_THEME.get_color("unaffordable_tint", "HudCard")


## What the current tool would cost now, as "Cost 400" and, when the wallet is
## short, "Cost 400   Short by 300"; "" when nothing costs money, there is no
## wallet or the pointer is not over a cell of the grid (no hover yet, over the
## HUD, or over ground outside the grid). The cost is the net of the plan
## BuildMode would apply under the pointer (a door over a paid wall also
## refunds the wall, so it is cheaper than its card), or for a dragged Floor
## rectangle the unfloored tiles the rules accept, as AreaDrag.fill_floor()
## charges.
func preview_text() -> String:
	if _wallet == null or build_mode == null:
		return ""
	var price := _preview_price()
	if price.x <= 0:
		return ""
	var text := "Cost %d" % price.x
	if price.y > _wallet.balance:
		text += "   Short by %d" % (price.y - _wallet.balance)
	return text


## Sets the cost line from preview_text(), and shows the status line only while
## the pointer is over a cell of the grid (or a rectangle drag is held by the
## pointer being over the HUD, where the line says why), so
## a stale hint such as "Facing auto" or the "Outside the building area"
## refusal does not stay over the world. A grant message is never hidden.
func refresh_preview() -> void:
	_cost.text = preview_text()
	_cost.visible = _cost.text != ""
	_status.visible = (
		_holding or build_mode == null or _pointer_on_grid() or build_mode.drag_held_by_ui()
	)


## True while BuildMode has the pointer over a cell inside the grid, whether or
## not the picked tool makes an edit there.
func _pointer_on_grid() -> bool:
	return build_mode.pointer_on_grid()


func room_panel() -> RoomPanel:
	return _room_panel


func _set_staff_open(open: bool) -> void:
	if open == staff_open:
		return
	staff_open = open
	staff_button.set_pressed_no_signal(open)
	staff_toggled.emit(open)


func _on_tool_changed(tool: BuildMode.Tool) -> void:
	if tool == BuildMode.Tool.NONE:
		if not _browsing:
			_open = NO_CATEGORY
			_set_staff_open(false)
	else:
		_set_staff_open(false)
		var index := category_of(tool)
		_open = NO_CATEGORY if index == remove_category() else index
	_sync()


func _on_balance_changed(_balance: int) -> void:
	_refresh_money()


## Writes the wallet into the money slot and each card's price slot, and greys
## out the cards it cannot pay.
func _refresh_money() -> void:
	_money.text = MONEY_TEXT if _wallet == null else "Money  %d" % _wallet.balance
	for tool in _price_labels:
		var price := tool_price(tool)
		var label: Label = _price_labels[tool]
		label.text = PRICE_TEXT if _wallet == null or price == 0 else str(price)
		_cards[tool].modulate = Color.WHITE if is_card_affordable(tool) else unaffordable_tint()
	refresh_preview()


## (what the placement costs net of refunds, what the wallet must hold for it).
## A door over a paid wall costs its price less the wall's refund, but the
## wallet must still hold the full door price (BuildTransaction.needed).
func _preview_price() -> Vector2i:
	var area := build_mode.dragged_area()
	if build_mode.tool == BuildMode.Tool.FLOOR and area.has_area():
		var rect_cost := _floor_rect_cost(area)
		return Vector2i(rect_cost, rect_cost)
	if build_mode.tool == BuildMode.Tool.BELT:
		# Only the cells with no belt yet are bought; reshaping is free.
		var line_cost := build_mode.belt_cells_to_buy() * tool_price(BuildMode.Tool.BELT)
		return Vector2i(line_cost, line_cost)
	if build_mode.tool in BuildMode.LANDSIDE_BUILD_TOOLS:
		return build_mode.landside_preview_price()
	var edit := build_mode.hover_edit()
	if edit == null or not _pointer_on_grid():
		return Vector2i.ZERO
	var plan := DoorPlacement.edits_for(build_mode.grid, edit)
	var net := 0
	for step in plan:
		net += BuildTransaction.quote(build_mode.grid, step).net()
	return Vector2i(maxi(0, net), maxi(0, BuildTransaction.needed(build_mode.grid, plan)))


## A rectangle is priced once per rectangle and balance, not every frame.
func _floor_rect_cost(area: Rect2i) -> int:
	var key := "%s:%d" % [area, _wallet.balance]
	if key != _rect_cost_key:
		_rect_cost_key = key
		_rect_cost = _price_floor_rect(area)
	return _rect_cost


func _price_floor_rect(area: Rect2i) -> int:
	return AreaDrag.floor_cost(build_mode.grid, area)


func _on_status_changed(text: String) -> void:
	if _holding:
		_held_status = text
		return
	_status.text = text


## A rescue message always wins the status line. A wages-paid message it cuts
## short is not lost: it shows once the rescue hold ends.
func _on_granted(_amount: int, message: String) -> void:
	if _holding and not _hold_is_grant:
		_pending_wages = _status.text
	_start_hold(message, true)


func _start_hold(message: String, is_grant: bool) -> void:
	if not _holding:
		_held_status = _status.text
	_holding = true
	_hold_is_grant = is_grant
	_status.text = message
	_hold_generation += 1
	var timer := get_tree().create_timer(grant_hold_s)
	timer.timeout.connect(_on_hold_timeout.bind(_hold_generation))


## "Wages paid: N", with the debt left when there is one, held like a grant
## message. During a rescue hold it waits (the latest one) instead of replacing it.
func _on_wages_paid(amount: int, owed: int) -> void:
	if amount <= 0:
		return
	var message := "Wages paid: %d" % amount
	if owed > 0:
		message += " (%d owed)" % owed
	if _holding and _hold_is_grant:
		_pending_wages = message
		return
	_start_hold(message, false)


## A loaded world starts with a clean status line: the hold and the wages
## message waiting behind it described the world that was replaced.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	_end_build_mode_after_load()
	_pending_wages = ""
	_holding = false
	_held_status = build_mode.status_text() if build_mode != null else ""
	_status.text = _held_status


## The loaded world is a new one: build mode ends with the clock as loaded, the
## tray and tool close, and the undo history goes (as OfferPanel._on_loaded does
## for its sheet).
func _end_build_mode_after_load() -> void:
	build_session.abandon()
	_open = NO_CATEGORY
	_set_staff_open(false)
	if build_mode != null:
		build_mode.set_tool(BuildMode.Tool.NONE)
	_sync()


func _on_hold_timeout(generation: int) -> void:
	if generation == _hold_generation:
		end_grant_hold()


## Ends the message's hold and shows the latest status text, or the wages-paid
## message that waited for a rescue hold, which then holds in its turn.
func end_grant_hold() -> void:
	if not _holding:
		return
	if _hold_is_grant and _pending_wages != "":
		var waiting := _pending_wages
		_pending_wages = ""
		_start_hold(waiting, false)
		return
	_pending_wages = ""
	_holding = false
	_status.text = _held_status


## Shows the open category's row and marks the selected category and card.
func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := i == _open or (i == remove_category() and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)
	build_session.set_building(_open != NO_CATEGORY or tool != BuildMode.Tool.NONE)


## Height, from the bottom edge, of the top of the tray, status and cost stack:
## what a card that must not cover any of them docks above.
static func tray_stack_top() -> float:
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + STATUS_H + COST_H


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
static func anchor_bottom_centre(control: Control, bottom: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = -bottom
	control.offset_bottom = -bottom
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_bar() -> void:
	_bar.name = "CategoryBar"
	_bar.theme = HUD_THEME
	_bar.theme_type_variation = &"HudBar"
	_bar.custom_minimum_size = Vector2(0.0, BAR_H)
	anchor_bottom_centre(_bar, MARGIN)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	for i in categories().size():
		var button := Button.new()
		button.text = categories()[i]["name"]
		button.toggle_mode = true
		button.custom_minimum_size = CATEGORY_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(press_category.bind(i))
		row.add_child(button)
		_category_buttons.append(button)
	staff_button.name = "StaffButton"
	staff_button.text = "Staff"
	staff_button.toggle_mode = true
	staff_button.custom_minimum_size = CATEGORY_SIZE
	staff_button.focus_mode = Control.FOCUS_NONE
	staff_button.pressed.connect(press_staff)
	row.add_child(staff_button)


func _build_tray() -> void:
	_tray.name = "ItemTray"
	_tray.theme = HUD_THEME
	_tray.custom_minimum_size = Vector2(0.0, TRAY_H)
	anchor_bottom_centre(_tray, MARGIN + BAR_H + GAP)
	add_child(_tray)
	for i in categories().size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tray.add_child(row)
		_rows.append(row)
		var turns := false
		for tool in categories()[i]["tools"]:
			if item(tool).is_empty():
				continue
			var button := _make_card(tool)
			row.add_child(button)
			_cards[tool] = button
			turns = turns or BuildMode.TOOL_OBJECTS.has(tool)
		if turns:
			row.add_child(_make_rotate_card())


func _make_card(tool: BuildMode.Tool) -> Button:
	var card_item := item(tool)
	var button := Button.new()
	button.name = "Card%s" % card_item[1].capitalize()
	button.toggle_mode = true
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(press_card.bind(tool))
	var column := _card_column(button)
	var picture := TextureRect.new()
	var path := THUMBNAIL_DIR % card_item[1]
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	elif PLACEHOLDER_THUMBNAILS.has(card_item[1]):
		var tile := ColorRect.new()
		tile.color = PLACEHOLDER_COLOR
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(tile)
	else:
		push_error("BuildMenu: no thumbnail at %s" % path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)
	var key := key_hint(tool)
	_card_label(column, card_item[0], &"HudCardName")
	_card_label(column, _size_text(tool), &"HudHint")
	_price_labels[tool] = _card_label(column, PRICE_TEXT, &"HudPrice")
	if CARD_NEEDS.has(tool):
		var need := _card_label(column, CARD_NEEDS[tool], &"HudAttentionText")
		need.add_theme_font_size_override("font_size", CARD_HINT_FONT_SIZE)
	elif CARD_RUNNING_COSTS.has(tool):
		_card_label(column, RUNNING_COST_TEXT % CARD_RUNNING_COSTS[tool], &"HudHint")
	else:
		_card_label(column, "Key %s" % key if key != "" else _no_key_hint(tool), &"HudHint")
	return button


## What a card with no key says: a rectangle tool is drawn by dragging, any
## other is a click.
static func _no_key_hint(tool: BuildMode.Tool) -> String:
	return "Drag" if BuildMode.AREA_TOOLS.has(tool) else "Click"


func _make_rotate_card() -> Button:
	var button := Button.new()
	button.name = "CardRotate"
	button.custom_minimum_size = ROTATE_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: build_mode.rotate_facing())
	var column := _card_column(button)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_label(column, "Rotate", &"HudCardName")
	_card_label(column, "Key R", &"HudHint")
	return button


func _card_column(button: Button) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6.0
	column.offset_top = 6.0
	column.offset_right = -6.0
	column.offset_bottom = -6.0
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	return column


func _card_label(column: VBoxContainer, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	return label


func _size_text(tool: BuildMode.Tool) -> String:
	if BuildMode.TOOL_OBJECTS.has(tool):
		var def := BuildCatalog.get_def(BuildMode.TOOL_OBJECTS[tool])
		return "%dx%d" % [def.size.x, def.size.y]
	return item(tool)[2]


func _build_status() -> void:
	_status.name = "StatusLine"
	var bottom := MARGIN + BAR_H + GAP + TRAY_H + GAP
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = -COLUMN_W / 2.0
	_status.offset_right = COLUMN_W / 2.0
	_status.offset_top = -bottom - STATUS_H
	_status.offset_bottom = -bottom
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.theme = HUD_THEME
	_status.theme_type_variation = &"HudFloatText"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


## The cost line, centred over the status line's box.
func _build_cost() -> void:
	_cost.name = "CostLine"
	var bottom := MARGIN + BAR_H + GAP + TRAY_H + GAP + STATUS_H
	_cost.anchor_left = 0.5
	_cost.anchor_right = 0.5
	_cost.anchor_top = 1.0
	_cost.anchor_bottom = 1.0
	_cost.offset_left = -COLUMN_W / 2.0
	_cost.offset_right = COLUMN_W / 2.0
	_cost.offset_top = -bottom - COST_H
	_cost.offset_bottom = -bottom
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cost.theme = HUD_THEME
	_cost.theme_type_variation = &"HudFloatText"
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost.visible = false
	add_child(_cost)


func _build_money() -> void:
	var panel := _money_slot
	panel.name = "MoneySlot"
	panel.theme = HUD_THEME
	panel.position = Vector2(16.0, 12.0)
	panel.custom_minimum_size = Vector2(220.0, 0.0)
	add_child(panel)
	_money.text = MONEY_TEXT
	_money.theme_type_variation = &"HudMoney"
	panel.add_child(_money)
