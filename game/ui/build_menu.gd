# gdlint:disable = max-public-methods
class_name BuildMenu
extends CanvasLayer
## The build menu (decisions hud-layout-bottom-category-bar-with-an-item-tray-time-and-fl
## and build-menu-rework-six-domain-tabs-progressive-tab-and-card-u):
## six domain tabs along the bottom edge plus Remove and Staff; clicking a
## domain tab opens a horizontal-scrolling tray of compact item cards above it
## (Thumbnail + 2-line Name + Price, with details in the 280 px hover popup);
## locked tabs and locked cards stay hidden until their tier opens, with warm
## "New" highlights on newly unlocked tabs and cards (and Tier 3 "In the full
## game" teasers at the right end of trays once Tier 2 unlocks in DemoMode).
## The status and refusal text and the cost line share one card at a fixed place
## above the tray's reserved space (HUD 5/7); a money slot sits top-left.
## BuildMode keeps the tool logic: the menu calls set_tool() and rotate_facing()
## and follows tool_changed and status_changed. Opening a category picks no
## tool; picking a card does, and arming a visible tool opens its own category.
## Esc (tool NONE) closes the tray. The menu also owns the room info panel
## (RoomPanel), top-left under the money slot. The status line also shows the
## rescue grant's message when one is paid (ruling
## going-broke-a-one-off-rescue-grant-when-the-airport-is-stuck) for
## grant_hold_s seconds (a later grant restarts the hold); status text that
## arrives meanwhile (the pointer moving over the grid changes it) waits and
## shows when the hold ends.
##
## The bar buttons are icons with their names in tooltips (BarIcons, HUD 6/7).
## While the edit under the pointer is refused, GhostReason shows a short reason
## beside the ghost.
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

## The card and category data lives in BuildMenuCatalog; these are its
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
## Cards whose thumbnail is not rendered yet
## (tools/blender/thumbnails/render_kit_thumbnails.py renders the others). They
## show a plain tile until the PNG exists; any other missing PNG is an error.
const PLACEHOLDER_THUMBNAILS := []
const PLACEHOLDER_COLOR := Color(0.3, 0.26, 0.2)
## The price slot of a card with no price (a room), or of any card when
## BuildMode has no wallet.
## The English msgids of card bottom labels: tests compare against them, and the
## labels themselves are tr() of the literal, because the POT extractor reads only literals.
const PRICE_TEXT := "Free"
## A locked card's bottom line when unlocks are unwired, and its tint (the hover
## card says what unlocks a locked item).
const LOCKED_TEXT := "Locked"
const LOCKED_TINT := Color(0.5, 0.5, 0.55)
## The tint of a card or unpressed domain tab of the newest opened tier until
## the player hovers or picks its unseen tools (UnlockGuide.is_new); on cards it
## multiplies the affordability tint.
const NEW_TINT := Color(1.0, 0.88, 0.45)
## The money slot's amount when BuildMode has no wallet; a coin icon stands before it.
const MONEY_TEXT := "--"

## Geometry in pixels, measured up from the bottom edge.
const MARGIN := float(HudLayout.MARGIN)
const BAR_H := float(HudLayout.BAR_H)
const GAP := float(HudLayout.GAP)
const TRAY_H := float(HudLayout.TRAY_H)
## The status card's height; it grows upward while a long status wraps.
const STATUS_H := float(HudLayout.BUTTON_H)
## A status wraps onto at most this many lines and then ends in an ellipsis
## (board T12 part 4); a held message (a rescue grant) takes HELD_LINES whole.
const STATUS_LINES := 2
const HELD_LINES := 3
## Maximum width of the centre column the tray and status line live in;
## PassengerHud and PassengerInspect keep left of it.
const COLUMN_W := float(HudLayout.TRAY_W)
const CARD_SIZE := Vector2(96.0, 126.0)
const THUMB_SIZE := 52.0
## A bar button: an icon (BarIcons) with its name in the tooltip.
const CATEGORY_SIZE := Vector2(52.0, 44.0)
const WHEEL_STEP := 64.0
const SCROLL_RETRY_CAP := 6

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
## Optional: marks the cards and tabs of a newly opened tier "New" (PassengerHud
## wires it with watch_guide()); without it no card or tab carries the mark.
var guide: UnlockGuide

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
var _scroll := ScrollContainer.new()
var _scroll_content := HBoxContainer.new()
var _rows: Array[HBoxContainer] = []
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
## Cached CardState per tool from the last _refresh_cards(), used by the cheap
## _refresh_money() path on wallet ticks so teaser/locked labels stay intact.
var _card_states: Dictionary = {}
var _pending_scroll_tool := BuildMode.Tool.NONE
var _pending_scroll_tries := 0
var _scroll_frame_queued := false
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


## What a tool's card costs: the floor tile, one wall piece or the object.
## 0 for a tool with no price (Remove, a room, no tool).
static func tool_price(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.tool_price(tool)


## The categories in bar order (CATEGORIES).
static func categories() -> Array:
	return BuildMenuCatalog.categories()


static func category_id(index: int) -> String:
	return BuildMenuCatalog.category_id(index)


static func category_index(id: String) -> int:
	return BuildMenuCatalog.category_index(id)


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
	if _wallet != null:
		_wallet.changed.connect(_on_balance_changed)
	if build_mode != null and build_mode.land_tool != null and build_mode.land_tool.land != null:
		# A load changes the land and the next plot's price with the wallet
		# unchanged; the Buy land card must follow.
		build_mode.land_tool.land.changed.connect(_refresh_money)
	for tool in _cards:
		_cards[tool].mouse_entered.connect(_on_card_hovered.bind(tool))
	if build_mode != null and build_mode.unlocks != null:
		build_mode.unlocks.tier_changed.connect(_on_tier_changed)
		build_mode.unlocks.unlocked.connect(_on_unlocked)
	_refresh_cards()
	if build_mode != null:
		_on_status_changed(build_mode.status_text())
		_on_tool_changed(build_mode.tool)
	else:
		_sync()
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
	HudLayout.fade_under_ghost(
		_status_card, ghost, delta, StaffPanel.FADED_ALPHA, StaffPanel.FADE_SPEED
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
	if index >= 0 and index < remove_category() and not _category_buttons[index].visible:
		return
	if index == _open:
		build_mode.set_tool(BuildMode.Tool.NONE)
		return
	_open = index
	_pending_scroll_tool = BuildMode.Tool.NONE
	_scroll.scroll_horizontal = 0
	templates_page.scroll_horizontal = 0
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
	_pending_scroll_tool = BuildMode.Tool.NONE
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_set_staff_open(true)
	_sync()


## A card click: picks its tool.
func press_card(tool: BuildMode.Tool) -> void:
	build_mode.set_tool(tool)


## Follows `new_guide`: its "New" marks tint the cards and unpressed domain tabs,
## and hovering a marked card or picking a tool clears it. Called once, by
## whoever builds the HUD.
func watch_guide(new_guide: UnlockGuide) -> void:
	if guide != null and guide.changed.is_connected(_refresh_cards):
		guide.changed.disconnect(_refresh_cards)
	guide = new_guide
	if guide != null:
		guide.changed.connect(_refresh_cards)
	if is_node_ready():
		_refresh_cards()


func category_button(index: int) -> Button:
	return _category_buttons[index]


func card(tool: BuildMode.Tool) -> Button:
	return _cards.get(tool)


func tray() -> Control:
	return _tray


func tray_scroll() -> ScrollContainer:
	return _scroll


## Maximum inner width inside `_tray` after subtracting its panel stylebox margins.
func tray_max_inner_width() -> float:
	var pad_x := 0.0
	var style := _tray.get_theme_stylebox(&"panel")
	if style != null:
		pad_x = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	return COLUMN_W - pad_x


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


## The text on a card's price slot: its price, Free, Locked or In the full game.
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
	if guide != null and tool != BuildMode.Tool.NONE:
		guide.mark_seen(tool)
	var prev_open := _open
	var scroll_to := BuildMode.Tool.NONE
	if tool == BuildMode.Tool.NONE:
		_pending_scroll_tool = BuildMode.Tool.NONE
		if not _browsing:
			_open = NO_CATEGORY
			_set_staff_open(false)
	else:
		_set_staff_open(false)
		var index := category_of(tool)
		var card_hidden := _cards.has(tool) and not (_cards[tool] as Control).visible
		var tab_hidden := (
			index >= 0 and index < _category_buttons.size() and not _category_buttons[index].visible
		)
		if index == remove_category() or index < 0 or tab_hidden or card_hidden:
			_open = NO_CATEGORY
			_pending_scroll_tool = BuildMode.Tool.NONE
		else:
			_open = index
			if _open != prev_open:
				_scroll.scroll_horizontal = 0
			scroll_to = tool
	_sync()
	if scroll_to != BuildMode.Tool.NONE:
		_queue_scroll_to_card(scroll_to)
	_show_status()


## Queues scrolling `tool`'s card into view after `_sync()` makes its row visible
## and after the ScrollContainer and HBoxContainer finish their layout sort.
func _queue_scroll_to_card(tool: BuildMode.Tool) -> void:
	_pending_scroll_tool = tool
	_pending_scroll_tries = 0
	if not is_inside_tree() or _scroll_frame_queued:
		return
	_scroll_frame_queued = true
	get_tree().process_frame.connect(_step_pending_scroll, CONNECT_ONE_SHOT)


func _step_pending_scroll() -> void:
	_scroll_frame_queued = false
	if not is_inside_tree() or _pending_scroll_tool == BuildMode.Tool.NONE:
		return
	if not _scroll.visible or not _cards.has(_pending_scroll_tool):
		_pending_scroll_tool = BuildMode.Tool.NONE
		return
	var target := _cards[_pending_scroll_tool] as Control
	if not target.is_visible_in_tree():
		_pending_scroll_tool = BuildMode.Tool.NONE
		return
	var ready := _is_card_sorted(target) and _scroll.size.x > 0.0
	if not ready and _pending_scroll_tries < SCROLL_RETRY_CAP:
		_pending_scroll_tries += 1
		_scroll_frame_queued = true
		get_tree().process_frame.connect(_step_pending_scroll, CONNECT_ONE_SHOT)
		return
	_scroll.ensure_control_visible(target)
	_pending_scroll_tool = BuildMode.Tool.NONE


func _is_card_sorted(target: Control) -> bool:
	if target.size.x <= 0.0:
		return false
	var parent := target.get_parent()
	if parent == null:
		return true
	for child in parent.get_children():
		if child is Control and (child as Control).visible:
			return child == target or target.position.x > 0.0
	return true


func _on_tray_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	var idx := mb.button_index
	if (
		idx != MOUSE_BUTTON_WHEEL_UP
		and idx != MOUSE_BUTTON_WHEEL_DOWN
		and idx != MOUSE_BUTTON_WHEEL_LEFT
		and idx != MOUSE_BUTTON_WHEEL_RIGHT
	):
		return
	if mb.pressed:
		var dir := -1.0 if idx == MOUSE_BUTTON_WHEEL_UP or idx == MOUSE_BUTTON_WHEEL_LEFT else 1.0
		var factor := mb.factor if mb.factor > 0.0 else 1.0
		var delta := roundi(dir * WHEEL_STEP * factor)
		if _scroll.visible:
			_scroll.scroll_horizontal = maxi(0, _scroll.scroll_horizontal + delta)
		elif templates_page.visible:
			templates_page.scroll_horizontal = maxi(0, templates_page.scroll_horizontal + delta)
	_tray.accept_event()


func _sync_scroll_width() -> void:
	if _scroll == null:
		return
	var row_w := _scroll_content.get_combined_minimum_size().x
	_scroll.custom_minimum_size.x = minf(row_w, tray_max_inner_width())


func _on_balance_changed(_balance: int) -> void:
	_refresh_money()


## Cheap wallet-change writer: updates the money slot, each OPEN card's price
## label and every card's affordability/New/locked tint without rebuilding
## hover details or touching TEASER ("In the full game") / LOCKED labels.
func _refresh_money() -> void:
	_money.text = MONEY_TEXT if _wallet == null else str(_wallet.balance)
	for tool: BuildMode.Tool in _price_labels:
		var state: int = _card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
		if state == BuildMenuCatalog.CardState.OPEN:
			var price := _card_price(tool)
			var label := _price_labels[tool] as Label
			label.text = tr("Free", "price") if _wallet == null or price == 0 else str(price)
		_cards[tool].modulate = _card_tint_for(tool, state)
	refresh_preview()


## What a card says is locking it (BuildUnlocks.lock_text), "" when it is open
## or the menu has no build mode.
func _lock_text(tool: BuildMode.Tool) -> String:
	if build_mode == null:
		return ""
	return BuildUnlocks.lock_text(build_mode.unlocks, build_mode.require_unlocks, tool)


func _card_tint_for(tool: BuildMode.Tool, state: int) -> Color:
	if state == BuildMenuCatalog.CardState.TEASER or state == BuildMenuCatalog.CardState.LOCKED:
		return LOCKED_TINT
	var tint := Color.WHITE if is_card_affordable(tool) else unaffordable_tint()
	return tint * NEW_TINT if guide != null and guide.is_new(tool) else tint


func _on_card_hovered(tool: BuildMode.Tool) -> void:
	if guide != null:
		guide.mark_seen(tool)


## Structural card and category-tab state writer: updates money slot, card
## visibility, bottom price/teaser/locked label, hover popup details + live lock
## requirement, teaser right-end ordering, tab visibility and unpressed tab "New"
## highlight.
func _refresh_cards() -> void:
	_money.text = MONEY_TEXT if _wallet == null else str(_wallet.balance)
	var unlocks: BuildUnlocks = build_mode.unlocks if build_mode != null else null
	var required := build_mode.require_unlocks if build_mode != null else false
	var demo := DemoMode.is_demo()
	var cats := categories()
	for i in cats.size():
		if i == remove_category():
			_category_buttons[i].visible = true
			continue
		var front_cards: Array[Control] = []
		var teaser_cards: Array[Control] = []
		for tool: BuildMode.Tool in cats[i]["tools"]:
			if not _cards.has(tool):
				continue
			var state := BuildMenuCatalog.card_state(tool, unlocks, required, demo)
			_card_states[tool] = state
			var lock := _lock_text(tool)
			var card_btn := _cards[tool] as ItemCardButton
			var price_label := _price_labels[tool] as Label
			var card_item := item(tool)
			card_btn.visible = state != BuildMenuCatalog.CardState.HIDDEN
			card_btn.requirement = _lock_text.bind(tool) if lock != "" else Callable()
			card_btn.set_info(
				BuildMenuCatalog.shown(card_item[0]),
				ItemInfo.of(tool),
				BuildMenuCatalog.card_details(tool)
			)
			if state == BuildMenuCatalog.CardState.TEASER:
				price_label.text = tr("In the full game")
				teaser_cards.append(card_btn)
			elif state == BuildMenuCatalog.CardState.LOCKED:
				price_label.text = tr("Locked")
				front_cards.append(card_btn)
			else:
				var price := _card_price(tool)
				price_label.text = (
					tr("Free", "price") if _wallet == null or price == 0 else str(price)
				)
				front_cards.append(card_btn)
			card_btn.modulate = _card_tint_for(tool, state)
		var ordered := front_cards + teaser_cards
		for pos in ordered.size():
			_rows[i].move_child(ordered[pos], pos)
		_category_buttons[i].visible = _row_has_visible_card(i)
	var closed_hidden := false
	if _open >= 0 and _open < remove_category() and not _category_buttons[_open].visible:
		_open = NO_CATEGORY
		closed_hidden = true
	_sync_tab_tints()
	refresh_preview()
	if closed_hidden:
		_sync()
	else:
		_sync_scroll_width()


func _sync_tab_tints() -> void:
	for i in _category_buttons.size():
		if i == remove_category():
			_category_buttons[i].modulate = Color.WHITE
			continue
		var show_new := i != _open and _category_has_new(i)
		_category_buttons[i].modulate = NEW_TINT if show_new else Color.WHITE


func _category_has_new(index: int) -> bool:
	if guide == null or index < 0 or index >= remove_category():
		return false
	for tool: BuildMode.Tool in categories()[index]["tools"]:
		if guide.is_new(tool):
			return true
	return false


func _row_has_visible_card(index: int) -> bool:
	if index < 0 or index >= _rows.size():
		return false
	for tool in categories()[index]["tools"]:
		if _cards.has(tool) and (_cards[tool] as Control).visible:
			return true
	return false


func _on_tier_changed(_tier: int) -> void:
	_refresh_cards()


## The "Unlocked: ..." line holds the status unless the unlock dialog is open,
## which names the families itself.
func _on_unlocked(_tier: int, text: String) -> void:
	if guide != null and guide.is_open():
		return
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


## Wraps the status text onto up to HELD_LINES lines, whole (a held message), or
## up to STATUS_LINES lines that end in an ellipsis when the text is longer
## (every other status). The label never clips: a clipped label reports no
## height of its own, so the card could not grow for the wrap.
func _wrap_status(held: bool) -> void:
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	_status.max_lines_visible = HELD_LINES if held else STATUS_LINES
	_status.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if held else TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var message := tr("Wages paid: {amount}").format({"amount": amount})
	if owed > 0:
		message = tr("Wages paid: {amount} ({owed} owed)").format({"amount": amount, "owed": owed})
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
	_refresh_cards()


## Closes any open tray, Staff card, held status banner, template paste or room
## move and drops the build session's hold on the clock (used when a full-screen
## modal takes over).
func close_for_modal() -> void:
	_open = NO_CATEGORY
	_pending_scroll_tool = BuildMode.Tool.NONE
	_set_staff_open(false)
	if build_mode != null:
		build_mode.templates.disarm()
		if build_mode.room_mover.active:
			build_mode.room_mover.cancel()
		build_mode.set_tool(BuildMode.Tool.NONE)
	build_session.set_building(false)
	_pending_wages = ""
	_holding = false
	_hold_generation += 1
	_held_status = build_mode.status_text() if build_mode != null else ""
	_raw_status = _held_status
	_show_status()
	refresh_preview()
	_sync()


## The loaded world is a new one: build mode ends with the clock as loaded, the
## tray and tool close, and the undo history goes (as OfferPanel._on_loaded does
## for its sheet).
func _end_build_mode_after_load() -> void:
	build_session.abandon()
	_open = NO_CATEGORY
	_pending_scroll_tool = BuildMode.Tool.NONE
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
	_scroll.visible = _open >= 0
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := _open == i or (i == remove_category() and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	_sync_tab_tints()
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)
	templates_page.sync(_open == TEMPLATES_PAGE)
	_sync_scroll_width()
	build_session.set_building(_open != NO_CATEGORY or tool != BuildMode.Tool.NONE)


## Height, from the bottom edge, of the top of the tray and status card stack:
## what a card that must not cover any of them docks above.
static func tray_stack_top() -> float:
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + STATUS_H


## tray_stack_top() with the status card's height as it is now: a held rescue or
## wages message wraps and grows the card upward, and what docks above the stack
## must clear that too. A hidden card reserves its usual STATUS_H.
func stack_top() -> float:
	var card_h := _status_card.size.y if _status_card.visible else STATUS_H
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + maxf(STATUS_H, card_h)


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
static func anchor_bottom_centre(control: Control, bottom: float) -> void:
	BuildMenuLayout.anchor_bottom_centre(control, bottom)
