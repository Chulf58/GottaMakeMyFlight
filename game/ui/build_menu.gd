# gdlint:disable = max-public-methods
class_name BuildMenu
extends CanvasLayer
## The build menu (decision hud-layout-bottom-category-bar-with-an-item-tray-time-and-fl):
## a bar of categories along the bottom edge; clicking one opens a tray of
## item cards above it (thumbnail, name, size, price, key hint); the status
## and refusal text and the cost line share one card at a fixed place above the
## tray's reserved space (HUD 5/7);
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
## The bar buttons are icons with their names in tooltips (BarIcons, HUD 6/7).
## The furniture and its rooms sit in five groups (Decor, Food, Services,
## Leisure, Shops), each one bar button over a tray that pages when its group
## holds more than one tray of cards. While the edit under the pointer is
## refused, GhostReason shows a short reason beside the ghost.
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
## cost and how short the wallet is. Prices are in the neutral text colour
## (HudPrice), never red: a red cost reads as "can't place" (decision hud-
## steal-list-self-clearing-alert-cards-money-hover-departu). With no wallet
## (BuildMode builds for free) the slot reads "--" and every card says Free.
## Hovering the money slot shows today's money from the DayLedger (MoneySlot)
## when day_ledger is set.

## The hiring card opened or closed (the StaffPanel shows it with this).
signal staff_toggled(open: bool)

## The card, category and page data lives in BuildMenuCatalog; these are its
## aliases, kept so every BuildMenu.X reference still resolves.
const THUMBNAIL_DIR := BuildMenuCatalog.THUMBNAIL_DIR
const CATEGORIES := BuildMenuCatalog.CATEGORIES
const REMOVE_CATEGORY := BuildMenuCatalog.REMOVE_CATEGORY
const NO_CATEGORY := BuildMenuCatalog.NO_CATEGORY
const TEMPLATES_PAGE := BuildMenuCatalog.TEMPLATES_PAGE
const ITEMS := BuildMenuCatalog.ITEMS
const LANE_ITEMS := BuildMenuCatalog.LANE_ITEMS
const CARD_NEEDS := BuildMenuCatalog.CARD_NEEDS
const CARD_RUNNING_COSTS := BuildMenuCatalog.CARD_RUNNING_COSTS
const RUNNING_COST_TEXT := BuildMenuCatalog.RUNNING_COST_TEXT
## Cards whose thumbnail is not rendered yet
## (tools/blender/thumbnails/render_kit_thumbnails.py renders the others). They
## show a plain tile until the PNG exists; any other missing PNG is an error.
const PLACEHOLDER_THUMBNAILS := []
const PLACEHOLDER_COLOR := Color(0.3, 0.26, 0.2)
## The price slot of a card with no price (a room), or of any card when
## BuildMode has no wallet.
const PRICE_TEXT := "Free"
## A locked card's last line, and its tint (the hover text says what unlocks it).
const LOCKED_TEXT := "Locked"
const LOCKED_TINT := Color(0.5, 0.5, 0.55)
## The money slot when BuildMode has no wallet.
const MONEY_TEXT := "Money  --"

## Geometry in pixels, measured up from the bottom edge.
const MARGIN := float(HudLayout.MARGIN)
const BAR_H := float(HudLayout.BAR_H)
const GAP := float(HudLayout.GAP)
const TRAY_H := 196.0
## The status card's height; it grows upward only while a long hold message wraps.
const STATUS_H := float(HudLayout.BUTTON_H)
## Width of the centre column the tray and status line live in; PassengerHud
## keeps the follow text left of it.
const COLUMN_W := float(HudLayout.TRAY_W)
const CARD_SIZE := Vector2(112.0, 176.0)
const THUMB_SIZE := 72.0
## The card hint labels' font size, as HudHint sets it.
const CARD_HINT_FONT_SIZE := 14
## A bar button: an icon (BarIcons) with its name in the tooltip.
const CATEGORY_SIZE := Vector2(52.0, 44.0)
const NEXT_SIZE := Vector2(72.0, 176.0)

## The one HUD theme (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).
## A CanvasLayer does not pass a theme down, so every top-level HUD Control
## under a CanvasLayer sets it itself.
const HUD_THEME := preload("res://ui/hud_theme.tres")
## The refusal card's canvas layer: over the HUD (layer 2), under the intro (10).
const GHOST_REASON_LAYER := 3
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
## The Templates page; press_category(TEMPLATES_PAGE) opens and closes it.
var templates_page := TemplatesPage.new()

var _open := NO_CATEGORY
## True while a category click clears the tool, so the tool_changed(NONE)
## that follows does not close the tray being opened.
var _browsing := false
var _bar := PanelContainer.new()
var _tray := PanelContainer.new()
var _rows: Array[HBoxContainer] = []
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
## The status line and the cost line on one card (HUD 5/7): the status text,
## the "R rotate" hint (RotateHint) in a slot of its own so a long refusal never
## pushes it onto a second line, and the cost.
var _status_card := PanelContainer.new()
var _status := Label.new()
var _rotate_hint := Label.new()
var _money := Label.new()
var _money_slot := MoneySlot.new()
var _cost := Label.new()
## The wallet building is paid from, or null when the tools build for free.
var _wallet: Wallet
## Card tool -> its price Label.
var _price_labels: Dictionary = {}
## Tool -> the card's last line and what it said unlocked (a locked card swaps it).
var _hint_labels: Dictionary = {}
var _hint_texts: Dictionary = {}
## The last dragged rectangle priced (rectangle and balance) and its cost.
var _rect_cost_key := ""
var _rect_cost := 0
var _room_panel := RoomPanel.new()
var _ghost_reason := GhostReason.new()
## True while the status line holds a grant message; the latest status text
## waits in _held_status until the hold ends.
var _holding := false
## Counts grants, so only the latest grant's timer ends the hold.
var _hold_generation := 0
var _held_status := ""
## The latest status text; the rotate hint has its own label.
var _raw_status := ""
## True while the hold shows a rescue grant's message, false for a wage one.
var _hold_is_grant := false
## A wages-paid message that waited for a rescue message's hold to end; "" if none.
var _pending_wages := ""


## "3" for the key bound to a tool's action, or "" when the tool has none.
static func key_hint(tool: BuildMode.Tool) -> String:
	return BuildMenuCatalog.key_hint(tool)


## What a tool's card costs: the floor tile, one wall piece or the object.
## 0 for a tool with no price (Remove, a room, no tool).
static func tool_price(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.tool_price(tool)


## The categories in bar order (CATEGORIES).
static func categories() -> Array:
	return BuildMenuCatalog.categories()


## The index of the Remove button, last in categories().
static func remove_category() -> int:
	return BuildMenuCatalog.remove_category()


## A tool's card [name, thumbnail, size text] from ITEMS, LANE_ITEMS or
## FurnitureTools.ITEMS, or an empty array for a tool with no card.
static func item(tool: BuildMode.Tool) -> Array:
	return BuildMenuCatalog.item(tool)


## What a card says its piece costs to run per day, or 0 for none.
static func running_cost(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.running_cost(tool)


## The name a category's bar button carries in its tooltip: its group's name
## on a group's first page, else its own.
static func bar_name(index: int) -> String:
	return BuildMenuCatalog.bar_name(index)


## The first page of the named group (its bar button), or NO_CATEGORY.
static func group_index(group_name: String) -> int:
	return BuildMenuCatalog.group_index(group_name)


## The first page of the group a category belongs to (CATEGORIES), or the
## category itself when it is not a later page.
static func group_start(index: int) -> int:
	return BuildMenuCatalog.group_start(index)


## The page the Next card of a category opens: the following page, the group's
## first page after its last, or NO_CATEGORY for a category with no pages.
static func next_page(index: int) -> int:
	return BuildMenuCatalog.next_page(index)


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.category_of(tool)


func _ready() -> void:
	layer = 2
	build_session.build_mode = build_mode
	build_session.clock = clock
	build_session.changed.connect(build_frame.set_building)
	add_child(build_session)
	add_child(build_frame)
	BuildMenuLayout.build_bar(self)
	BuildMenuLayout.build_tray(self)
	BuildMenuLayout.build_status_card(self)
	BuildMenuLayout.build_money(self)
	templates_page.attach(self)
	add_child(_room_panel)
	_ghost_reason.build_mode = build_mode
	# Its own layer above the HUD panels (all on layer 2), as a tooltip is: it
	# follows the pointer and must not slip under the staff hint card.
	var reason_layer := CanvasLayer.new()
	reason_layer.name = "GhostReasonLayer"
	reason_layer.layer = GHOST_REASON_LAYER
	reason_layer.add_child(_ghost_reason)
	add_child(reason_layer)
	if build_mode != null:
		_wallet = build_mode.wallet()
		_room_panel.watch(build_mode)
		build_mode.tool_changed.connect(_on_tool_changed)
		build_mode.status_changed.connect(_on_mode_status_changed)
		build_mode.templates.status_changed.connect(_on_status_changed)
		build_mode.templates.armed_changed.connect(_show_status)
		build_mode.room_mover.status_changed.connect(_on_status_changed)
		build_mode.room_mover.active_changed.connect(_show_status)
		_on_status_changed(build_mode.status_text())
		_on_tool_changed(build_mode.tool)
	else:
		_sync()
	if _wallet != null:
		_wallet.changed.connect(_on_balance_changed)
	if build_mode != null and build_mode.land_tool != null and build_mode.land_tool.land != null:
		# A load changes the land and the next plot's price with the wallet
		# unchanged; the Buy land card must follow.
		build_mode.land_tool.land.changed.connect(_refresh_money)
	_refresh_money()
	if build_mode != null and build_mode.unlocks != null:
		build_mode.unlocks.tier_changed.connect(_on_tier_changed)
		build_mode.unlocks.unlocked.connect(_on_unlocked)
	_refresh_locks()
	if rescue_grant != null:
		rescue_grant.granted.connect(_on_granted)
	if settlement != null:
		settlement.wages_paid.connect(_on_wages_paid)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	if day_ledger != null:
		_money_slot.watch(day_ledger, settlement)


func _process(delta: float) -> void:
	refresh_preview()
	var ghost := Rect2()
	if build_mode != null:
		ghost = GhostBounds.build_rect(build_mode, get_viewport().get_camera_3d())
	fade_for(ghost, delta)


## Fades the status card to StaffPanel.FADED_ALPHA while `ghost` (the build
## ghost's bounds on screen, empty when there is none) overlaps it, and back to
## full opacity when it does not, `delta` seconds of the fade (decision
## status-banner-fades-under-the-build-ghost-room-labels-slide). The card never
## takes a click, and a faded card still counts as an obstacle for the refusal
## card's nudge.
func fade_for(ghost: Rect2, delta: float) -> void:
	var covered := (
		ghost.has_area()
		and _status_card.visible
		and _status_card.get_global_rect().intersects(ghost)
	)
	var target := StaffPanel.FADED_ALPHA if covered else 1.0
	_status_card.modulate.a = move_toward(
		_status_card.modulate.a, target, delta * StaffPanel.FADE_SPEED
	)


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


## The one card the status line, the rotate hint and the cost line sit on.
func status_card() -> PanelContainer:
	return _status_card


## The "R rotate" hint, in its own slot at the end of the status line.
func rotate_hint_label() -> Label:
	return _rotate_hint


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
	return _wallet == null or _wallet.can_afford(_card_price(tool))


## What a card's price slot shows: tool_price(), or for Buy land the price of
## the next plot (LandPlots.next_price()), which rises with each plot bought.
func _card_price(tool: BuildMode.Tool) -> int:
	return BuildMenuPrices.card_price(self, tool)


## What greys out a card the wallet cannot pay: the theme's HudCard
## unaffordable_tint (hud_theme.tres).
static func unaffordable_tint() -> Color:
	return HUD_THEME.get_color("unaffordable_tint", "HudCard")


## What the current tool would cost now, as "Cost 400" and, when the wallet is
## short, "Cost 400   Short by 300"; "" when nothing costs money (the rules are
## in BuildMenuPrices.preview_text()).
func preview_text() -> String:
	return BuildMenuPrices.preview_text(self)


## Sets the cost line from preview_text(), and shows the status line only while
## the pointer is over a cell of the grid (or a rectangle drag is held by the
## pointer being over the HUD, where the line says why), so
## a stale hint such as "Facing auto" or the "Outside the building area"
## refusal does not stay over the world. A grant message is never hidden. The
## card shows while any of its three parts does.
func refresh_preview() -> void:
	_cost.text = preview_text()
	_cost.visible = _cost.text != ""
	_status.visible = (
		_holding or build_mode == null or _pointer_on_grid() or build_mode.drag_held_by_ui()
	)
	_rotate_hint.visible = (_status.visible and not _holding and RotateHint.applies(build_mode))
	_status_card.visible = (
		(_status.visible and _status.text != "") or _rotate_hint.visible or _cost.visible
	)


## True while BuildMode has the pointer over a cell inside the grid, whether or
## not the picked tool makes an edit there.
func _pointer_on_grid() -> bool:
	return build_mode.pointer_on_grid()


func room_panel() -> RoomPanel:
	return _room_panel


## The short refusal reason beside the ghost.
func ghost_reason() -> GhostReason:
	return _ghost_reason


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
	_show_status()


func _on_balance_changed(_balance: int) -> void:
	_refresh_money()


## Writes the wallet into the money slot and each card's price slot, and greys
## out the cards it cannot pay.
func _refresh_money() -> void:
	_money.text = MONEY_TEXT if _wallet == null else "Money  %d" % _wallet.balance
	for tool in _price_labels:
		var price := _card_price(tool)
		var label: Label = _price_labels[tool]
		label.text = PRICE_TEXT if _wallet == null or price == 0 else str(price)
		_cards[tool].modulate = _card_tint(tool)
	refresh_preview()


## What a card says is locking it (BuildUnlocks.lock_text), "" when it is open
## or the menu has no build mode.
func _lock_text(tool: BuildMode.Tool) -> String:
	if build_mode == null:
		return ""
	return BuildUnlocks.lock_text(build_mode.unlocks, build_mode.require_unlocks, tool)


func _card_tint(tool: BuildMode.Tool) -> Color:
	if _lock_text(tool) != "":
		return LOCKED_TINT
	return Color.WHITE if is_card_affordable(tool) else unaffordable_tint()


## Greys the locked cards, with "Locked" on the last line and the requirement
## (and how far the game is from it) in place of the hover card; an unlocked
## card gets its own line and hover card back.
func _refresh_locks() -> void:
	for tool in _cards:
		var text := _lock_text(tool)
		var card_item := item(tool)
		_hint_labels[tool].text = LOCKED_TEXT if text != "" else _hint_texts[tool]
		_cards[tool].set_info(card_item[0], [] if text != "" else ItemInfo.of(tool))
		if text != "":
			_cards[tool].tooltip_text = text
		_cards[tool].modulate = _card_tint(tool)


func _on_tier_changed(_tier: int) -> void:
	_refresh_locks()


func _on_unlocked(_tier: int, text: String) -> void:
	_start_hold(text, false)


func _price_floor_rect(area: Rect2i) -> int:
	return AreaDrag.floor_cost(build_mode.grid, area)


## BuildMode's status line. While a template is armed, its empty text gives way
## to the template's own (TemplatePaste), which BuildMode's hover would clear.
func _on_mode_status_changed(text: String) -> void:
	if text == "" and build_mode.templates.is_active():
		text = build_mode.templates.status_text()
	elif text == "" and build_mode.room_mover.active:
		text = build_mode.room_mover.status_text()
	_on_status_changed(text)


func _on_status_changed(text: String) -> void:
	_raw_status = text
	if _holding:
		_held_status = text
		return
	_show_status()


## The status line: the latest status text, and the "R rotate" hint (RotateHint)
## in its own label while a piece or a template that can turn is armed. A hold
## keeps its message.
func _show_status() -> void:
	if not _holding:
		_status.text = _raw_status
		_wrap_status(false)
		_rotate_hint.visible = _status.visible and RotateHint.applies(build_mode)


## Wraps the status text onto up to three lines (a held message), or keeps it on
## one line and cuts it short with an ellipsis (every other status). A clipped
## label reports no height of its own, so the card could not grow for the wrap.
func _wrap_status(wrap: bool) -> void:
	_status.autowrap_mode = (TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF)
	_status.clip_text = not wrap
	_status.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if wrap else TextServer.OVERRUN_TRIM_ELLIPSIS
	)


## A rescue message always wins the status line. A wages-paid message it cuts
## short is not lost: it shows once the rescue hold ends.
func _on_granted(_amount: int, message: String) -> void:
	if _holding and not _hold_is_grant:
		_pending_wages = _status.text
	_start_hold(message, true)


func _start_hold(message: String, is_grant: bool) -> void:
	if not _holding:
		_held_status = _raw_status
	_holding = true
	_hold_is_grant = is_grant
	_status.text = message
	# A held message is long on purpose (a rescue grant); it wraps and the card
	# grows upward instead of cutting it short.
	_wrap_status(true)
	_rotate_hint.visible = false
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
	_raw_status = _held_status
	_show_status()


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
	_show_status()


## Shows the open category's row and marks the selected category and card.
func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := (
			(_open != NO_CATEGORY and i == group_start(_open))
			or (i == remove_category() and tool == BuildMode.Tool.REMOVE)
		)
		_category_buttons[i].set_pressed_no_signal(on)
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)
	templates_page.sync(_open == TEMPLATES_PAGE)
	build_session.set_building(_open != NO_CATEGORY or tool != BuildMode.Tool.NONE)


## Height, from the bottom edge, of the top of the tray and status card stack:
## what a card that must not cover any of them docks above.
static func tray_stack_top() -> float:
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + STATUS_H


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
static func anchor_bottom_centre(control: Control, bottom: float) -> void:
	BuildMenuLayout.anchor_bottom_centre(control, bottom)
