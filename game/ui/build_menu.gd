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
## Money (ruling building-costs-money-from-a-starting-budget-you-can-t-build):
## the money slot shows the wallet BuildMode pays from and follows it; each
## card shows its price and greys out while the wallet cannot pay it (it can
## still be picked, so the cost line can show the shortfall); a cost line above
## the status line shows what the tool, or the dragged Floor rectangle, would
## cost and how short the wallet is. Prices stay in the price colour, never
## red. With no wallet (BuildMode builds for free) the slot reads "--" and
## every card says Free.

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
	{"name": "Gates", "tools": [BuildMode.Tool.SEATS]},
	{
		"name": "Shops",
		"tools": [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE],
	},
	{"name": "Remove", "tools": [BuildMode.Tool.REMOVE]},
]
## The category that is a single button with no tray.
const REMOVE_CATEGORY := 6
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
	BuildMode.Tool.CAFE_ROOM: ["Cafe", "cafe_room", "3x3 min"],
	BuildMode.Tool.COUNTER: ["Counter", "counter", ""],
	BuildMode.Tool.TABLE: ["Table", "table", ""],
}
## Cards whose thumbnail is not rendered yet
## (tools/blender/thumbnails/render_kit_thumbnails.py renders the others). They
## show a plain tile until the PNG exists; any other missing PNG is an error.
const PLACEHOLDER_THUMBNAILS := ["cafe_room", "counter", "table"]
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
const CATEGORY_SIZE := Vector2(100.0, 44.0)
const ROTATE_SIZE := Vector2(72.0, 176.0)

## The one HUD theme (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).
## A CanvasLayer does not pass a theme down, so every top-level HUD Control
## under a CanvasLayer sets it itself.
const HUD_THEME := preload("res://ui/hud_theme.tres")
## How long a rescue grant's message stays on the status line, in seconds.
const GRANT_HOLD_S := 8.0

@export var build_mode: BuildMode
## Optional: when set, its paid grants are announced on the status line.
@export var rescue_grant: RescueGrant
## Seconds a grant message holds the status line.
@export var grant_hold_s := GRANT_HOLD_S

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
## 0 for a tool with no price (Remove, the cafe room, no tool).
static func tool_price(tool: BuildMode.Tool) -> int:
	if tool == BuildMode.Tool.FLOOR:
		return PriceTable.price_of_floor()
	if BuildMode.TOOL_WALL_KINDS.has(tool):
		return PriceTable.price_of_wall(BuildMode.TOOL_WALL_KINDS[tool])
	if BuildMode.TOOL_OBJECTS.has(tool):
		return PriceTable.price_of_object(BuildMode.TOOL_OBJECTS[tool])
	return 0


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i]["tools"].has(tool):
			return i
	return NO_CATEGORY


func _ready() -> void:
	layer = 2
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
	if index == REMOVE_CATEGORY:
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


## Sets the cost line from preview_text(), and hides the status line while the
## pointer is over ground outside the grid, where its only text would be the
## "Outside the building area" refusal. A grant message is never hidden.
func refresh_preview() -> void:
	_cost.text = preview_text()
	_cost.visible = _cost.text != ""
	_status.visible = _holding or not _pointer_off_grid()


## True while BuildMode hovers an edit on a cell outside the grid.
func _pointer_off_grid() -> bool:
	if build_mode == null:
		return false
	var edit := build_mode.hover_edit()
	return edit != null and not build_mode.grid.in_bounds(edit.cell)


func room_panel() -> RoomPanel:
	return _room_panel


func _on_tool_changed(tool: BuildMode.Tool) -> void:
	if tool == BuildMode.Tool.NONE:
		if not _browsing:
			_open = NO_CATEGORY
	else:
		var index := category_of(tool)
		_open = NO_CATEGORY if index == REMOVE_CATEGORY else index
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
	var edit := build_mode.hover_edit()
	if edit == null or _pointer_off_grid():
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
	var grid := build_mode.grid
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				continue
			var edit := BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
			if DoorPlacement.check(grid, edit).ok:
				edits.append(edit)
	return maxi(0, BuildTransaction.needed(grid, edits))


func _on_status_changed(text: String) -> void:
	if _holding:
		_held_status = text
		return
	_status.text = text


func _on_granted(_amount: int, message: String) -> void:
	if not _holding:
		_held_status = _status.text
	_holding = true
	_status.text = message
	_hold_generation += 1
	var timer := get_tree().create_timer(grant_hold_s)
	timer.timeout.connect(_on_hold_timeout.bind(_hold_generation))


func _on_hold_timeout(generation: int) -> void:
	if generation == _hold_generation:
		end_grant_hold()


## Ends the grant message's hold and shows the latest status text.
func end_grant_hold() -> void:
	if not _holding:
		return
	_holding = false
	_status.text = _held_status


## Shows the open category's row and marks the selected category and card.
func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := i == _open or (i == REMOVE_CATEGORY and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
func _anchor_bottom_centre(control: Control, bottom: float) -> void:
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
	_anchor_bottom_centre(_bar, MARGIN)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	for i in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[i]["name"]
		button.toggle_mode = true
		button.custom_minimum_size = CATEGORY_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(press_category.bind(i))
		row.add_child(button)
		_category_buttons.append(button)


func _build_tray() -> void:
	_tray.name = "ItemTray"
	_tray.theme = HUD_THEME
	_tray.custom_minimum_size = Vector2(0.0, TRAY_H)
	_anchor_bottom_centre(_tray, MARGIN + BAR_H + GAP)
	add_child(_tray)
	for i in CATEGORIES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tray.add_child(row)
		_rows.append(row)
		var turns := false
		for tool in CATEGORIES[i]["tools"]:
			if not ITEMS.has(tool):
				continue
			var button := _make_card(tool)
			row.add_child(button)
			_cards[tool] = button
			turns = turns or BuildMode.TOOL_OBJECTS.has(tool)
		if turns:
			row.add_child(_make_rotate_card())


func _make_card(tool: BuildMode.Tool) -> Button:
	var item: Array = ITEMS[tool]
	var button := Button.new()
	button.name = "Card%s" % item[1].capitalize()
	button.toggle_mode = true
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(press_card.bind(tool))
	var column := _card_column(button)
	var picture := TextureRect.new()
	var path := THUMBNAIL_DIR % item[1]
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	elif PLACEHOLDER_THUMBNAILS.has(item[1]):
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
	_card_label(column, item[0], &"HudCardName")
	_card_label(column, _size_text(tool), &"HudHint")
	_price_labels[tool] = _card_label(column, PRICE_TEXT, &"HudPrice")
	_card_label(column, "Key %s" % key if key != "" else "Click", &"HudHint")
	return button


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
	return ITEMS[tool][2]


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
	var panel := PanelContainer.new()
	panel.name = "MoneySlot"
	panel.theme = HUD_THEME
	panel.position = Vector2(16.0, 12.0)
	panel.custom_minimum_size = Vector2(220.0, 0.0)
	add_child(panel)
	_money.text = MONEY_TEXT
	_money.theme_type_variation = &"HudMoney"
	panel.add_child(_money)
