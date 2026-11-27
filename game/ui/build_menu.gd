# gdlint:disable = max-public-methods, max-file-lines
class_name BuildMenu
extends CanvasLayer
## The build menu (decisions hud-layout-bottom-category-bar-with-an-item-tray-time-and-fl,
## build-menu-rework-six-domain-tabs-progressive-tab-and-card-u and
## build-menu-slider-free-wrapping-grid-80x96-cards-9-columns):
## seven domain tabs along the bottom edge plus Templates, Remove and Staff;
## clicking a domain tab opens a slider-free 9-column wrapping grid tray of
## compact 80x96 item cards above it (40x40 Thumbnail + 2-line Name + Price,
## with details in the 280 px hover popup); locked tabs and locked cards stay
## hidden until their tier opens, with warm "New" highlights on newly unlocked
## tabs and cards (and Tier 3 "In the full game" teasers at the end of trays
## once Tier 2 unlocks in DemoMode).
## The status and refusal text and the cost line share one card above the tray
## (or right above the category bar while the tray is closed) (HUD 5/7); a money slot sits top-left.
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
const ROOM_CONTEXT := BuildMenuCatalog.ROOM_CONTEXT
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
const PULSE_TINT := Color(1.3, 1.12, 0.55)
const PULSE_STEP_S := 0.22
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
const CARD_SIZE := Vector2(80.0, 96.0)
const THUMB_SIZE := 40.0
const CARD_SEP := 6
const MAX_COLUMNS := 9
## A bar button: an icon (BarIcons) with its name in the tooltip.
const CATEGORY_SIZE := Vector2(52.0, 44.0)
const WHEEL_STEP := 64.0

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
## Optional: paused while build mode lasts (forwarded to BuildSession).
@export var clock: SimClock
## Optional: marks the cards and tabs of a newly opened tier "New" (PassengerHud
## wires it with watch_guide()); without it no card or tab carries the mark.
var guide: UnlockGuide
var awards: AirportAwards

## True while the hiring card is open; press_staff() changes it.
var staff_open := false
## The Staff button at the end of the bar.
var staff_button := Button.new()
## Build mode: a tray open or a tool picked. The frame is its on-screen sign.
var build_session := BuildSession.new()
var build_frame := BuildModeFrame.new()
## The Templates page; press_category(TEMPLATES_PAGE) opens and closes it.
var templates_page := TemplatesPage.new()

var _open := NO_CATEGORY
## True while a category click clears the tool, so the tool_changed(NONE)
## that follows does not close the tray being opened.
var _browsing := false
var _keep_tray_on_clear := false
var _bar := PanelContainer.new()
var _tray := PanelContainer.new()
var _tray_root := VBoxContainer.new()
var _rows: Array[GridContainer] = []
var _room_cards_pool := Control.new()
var _room_box := VBoxContainer.new()
var _room_header := HBoxContainer.new()
var _room_back_button := Button.new()
var _room_title := Label.new()
var _room_summary := Label.new()
var _room_grid := GridContainer.new()
var _room_cards: Dictionary = {}
var _room_price_labels: Dictionary = {}
var _room_entries: Array[Dictionary] = []
var _starter_kit_cards: Dictionary = {}
var _starter_kit_price_labels: Dictionary = {}
var _room_context_type: StringName = &""
var _room_context_id := 0
var _back_category := NO_CATEGORY
var _selection: BuiltSelection
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
## Cached CardState per tool from the last _refresh_cards(), used by the cheap
## _refresh_money() path on wallet ticks so teaser/locked labels stay intact.
var _card_states: Dictionary = {}
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
var _wages_hold_amount := 0
var _wages_hold_owed := 0
var _staff_card: Control
var _pulsed_tool := BuildMode.Tool.NONE
var _pulse_tween: Tween


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
		build_mode.tool_deselected.connect(_on_tool_deselected)
		build_mode.eyedropper_picked.connect(_on_eyedropper_picked)
		build_mode.status_changed.connect(_on_mode_status_changed)
		build_mode.refusal_shown.connect(_on_refusal_shown)
		if build_mode.grid != null:
			build_mode.grid.edit_refused.connect(_on_edit_refused)
			build_mode.grid.edit_applied.connect(_on_grid_edit_applied)
			build_mode.grid.graph_changed.connect(_on_grid_graph_changed)
		build_mode.templates.status_changed.connect(_on_status_changed)
		build_mode.templates.armed_changed.connect(_show_status)
		build_mode.room_mover.status_changed.connect(_on_status_changed)
		build_mode.room_mover.active_changed.connect(_show_status)
		build_mode.object_mover.status_changed.connect(_on_status_changed)
		build_mode.object_mover.active_changed.connect(_show_status)
		if build_mode.starter_kit != null:
			build_mode.starter_kit.status_changed.connect(_on_status_changed)
			build_mode.starter_kit.armed_changed.connect(_on_starter_kit_armed_changed)
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
	if _selection == null and is_inside_tree():
		var hud := get_node_or_null("../PassengerHud")
		if hud != null:
			watch_selection(hud.get("_built") as BuiltSelection)
	get_viewport().size_changed.connect(sync_tray_bounds)


func _unhandled_input(event: InputEvent) -> void:
	if (
		is_room_context()
		and event.is_action_pressed("build_tool_none")
		and (build_mode == null or build_mode.tool == BuildMode.Tool.NONE)
	):
		if (
			build_mode != null
			and build_mode.starter_kit != null
			and build_mode.starter_kit.is_active()
		):
			return
		if _selection != null and _selection.kind == BuiltSelection.Kind.ROOM:
			return
		exit_room_context()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


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


func is_room_context() -> bool:
	return _open == ROOM_CONTEXT and _room_context_type != &""


func room_context_type() -> StringName:
	return _room_context_type if is_room_context() else &""


func room_context_id() -> int:
	return _room_context_id if is_room_context() else 0


func room_back_button() -> Button:
	return _room_back_button


func room_title_label() -> Label:
	return _room_title


func room_summary_label() -> Label:
	return _room_summary


func room_context_grid() -> GridContainer:
	return _room_grid


## Enters persistent Contextual Room-Items mode for `room_type` (and optional `room_id`).
func enter_room_context(room_type: StringName, room_id: int = 0) -> void:
	if RoomTypes.get_type(room_type) == null:
		return
	if _open >= 0 and _open < remove_category():
		_back_category = _open
	_set_staff_open(false)
	_room_context_type = room_type
	_room_context_id = _validated_room_id(room_id)
	_open = ROOM_CONTEXT
	_rebuild_room_context_cards()
	_sync()


## Exits Contextual Room-Items mode, returning to the parent tab (if opened from one)
## or closing the tray.
func exit_room_context() -> void:
	if not is_room_context():
		return
	var return_cat := _back_category
	_clear_room_context_state()
	if _selection != null and _selection.kind == BuiltSelection.Kind.ROOM:
		_selection.clear()
	if return_cat >= 0 and return_cat < remove_category() and _category_buttons[return_cat].visible:
		_open = return_cat
	else:
		_open = NO_CATEGORY
	_browsing = true
	if build_mode != null:
		build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()


## A category button click: opens its tray (picking no tool), closes it when
## it is already open, or picks Remove, which has no tray.
func press_category(index: int) -> void:
	_set_staff_open(false)
	if index == remove_category():
		_clear_room_context_state()
		build_mode.set_tool(BuildMode.Tool.REMOVE)
		return
	if index >= 0 and index < remove_category() and not _category_buttons[index].visible:
		return
	if index == _open:
		_clear_room_context_state()
		build_mode.set_tool(BuildMode.Tool.NONE)
		return
	_clear_room_context_state()
	_open = index
	templates_page.scroll_horizontal = 0
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()


static func tray_height_for_rows(rows: int) -> float:
	var count := maxi(1, rows)
	return float(count) * CARD_SIZE.y + float(count - 1) * float(CARD_SEP) + 10.0


func tray_height() -> float:
	if not _tray.visible:
		return TRAY_H
	if _open == TEMPLATES_PAGE:
		return templates_page.needed_height() + _tray_pad_y()
	if is_room_context():
		var visible_count := _visible_room_card_count()
		var cols := maxi(1, _room_grid.columns)
		var row_count := maxi(1, ceili(float(maxi(1, visible_count)) / float(cols)))
		var grid_h := (
			float(row_count) * CARD_SIZE.y + float(maxi(0, row_count - 1)) * float(CARD_SEP)
		)
		var header_h := maxf(_room_header.get_combined_minimum_size().y, float(HudLayout.CHIP_H))
		var sep := float(_room_box.get_theme_constant(&"separation"))
		return header_h + sep + grid_h + _tray_pad_y()
	if _open < 0 or _open >= _rows.size():
		return TRAY_H
	var visible_count := _visible_card_count(_open)
	if visible_count <= 0:
		return TRAY_H
	var cols := maxi(1, _rows[_open].columns)
	var row_count := maxi(1, ceili(float(visible_count) / float(cols)))
	return float(row_count) * CARD_SIZE.y + float(row_count - 1) * float(CARD_SEP) + _tray_pad_y()


func tray_columns() -> int:
	return clampi(
		floori((tray_max_inner_width() + float(CARD_SEP)) / (CARD_SIZE.x + float(CARD_SEP))),
		1,
		MAX_COLUMNS
	)


## The Staff button click: opens the hiring card (closing any tray and
## dropping the tool), or closes it when it is open.
func press_staff() -> void:
	if staff_open:
		_set_staff_open(false)
		return
	_clear_room_context_state()
	_open = NO_CATEGORY
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_set_staff_open(true)
	_sync()


## A card click: picks its tool.
func press_card(tool: BuildMode.Tool) -> void:
	_stop_pulse()
	build_mode.set_tool(tool)


func starter_kit_card(kit_id: StringName) -> Button:
	return _starter_kit_cards.get(kit_id) if is_room_context() else null


func press_starter_kit(kit_id: StringName) -> bool:
	if build_mode == null or build_mode.starter_kit == null:
		return false
	_stop_pulse()
	if build_mode.starter_kit.armed == kit_id:
		build_mode.starter_kit.disarm()
		return false
	return build_mode.starter_kit.try_arm(kit_id)


## Opens `tool`'s category tab (or its Contextual Room-Items tray for room-only
## furniture, closing Staff if open) and briefly pulses its card so a checklist
## jump highlights where to build. Returns false when hidden.
func focus_tool(tool: BuildMode.Tool) -> bool:
	if (
		int(_card_states.get(tool, BuildMenuCatalog.CardState.OPEN))
		== BuildMenuCatalog.CardState.HIDDEN
	):
		return false
	if BuildMenuCatalog.is_room_only_tool(tool):
		var owners := BuildMenuCatalog.room_owners_of(tool)
		if owners.is_empty():
			return false
		var target_type: StringName = owners[0]
		if is_room_context() and owners.has(_room_context_type):
			target_type = _room_context_type
		var target_id := (
			_room_context_id if is_room_context() and _room_context_type == target_type else 0
		)
		_browsing = true
		if build_mode != null:
			build_mode.set_tool(BuildMode.Tool.NONE)
		_browsing = false
		enter_room_context(target_type, target_id)
		_pulse_card(tool)
		return true
	var cat := category_of(tool)
	if cat < 0 or cat >= remove_category() or not _cards.has(tool):
		return false
	if cat >= _category_buttons.size() or not _category_buttons[cat].visible:
		return false
	_clear_room_context_state()
	_set_staff_open(false)
	_open = cat
	templates_page.scroll_horizontal = 0
	_browsing = true
	if build_mode != null:
		build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()
	_pulse_card(tool)
	return true


func pulsed_tool() -> BuildMode.Tool:
	return _pulsed_tool


func _pulse_card(tool: BuildMode.Tool) -> void:
	_stop_pulse()
	var card_btn := card(tool) as Control
	if card_btn == null:
		return
	_pulsed_tool = tool
	var base := _card_tint_for(tool, int(_card_states.get(tool, BuildMenuCatalog.CardState.OPEN)))
	_pulse_tween = create_tween()
	for i in 3:
		_pulse_tween.tween_property(card_btn, "modulate", PULSE_TINT, PULSE_STEP_S)
		_pulse_tween.tween_property(card_btn, "modulate", base, PULSE_STEP_S)
	_pulse_tween.finished.connect(
		func() -> void:
			_pulsed_tool = BuildMode.Tool.NONE
			_pulse_tween = null
	)


func _stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if _pulsed_tool != BuildMode.Tool.NONE:
		var state: int = _card_states.get(_pulsed_tool, BuildMenuCatalog.CardState.OPEN)
		var base := _card_tint_for(_pulsed_tool, state)
		if _cards.has(_pulsed_tool):
			(_cards[_pulsed_tool] as Control).modulate = base
		if _room_cards.has(_pulsed_tool):
			(_room_cards[_pulsed_tool] as Control).modulate = base
	_pulsed_tool = BuildMode.Tool.NONE


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


func watch_selection(new_selection: BuiltSelection) -> void:
	if _selection != null and _selection.changed.is_connected(_on_built_selection_changed):
		_selection.changed.disconnect(_on_built_selection_changed)
	_selection = new_selection
	if _selection != null and not _selection.changed.is_connected(_on_built_selection_changed):
		_selection.changed.connect(_on_built_selection_changed)


func category_button(index: int) -> Button:
	return _category_buttons[index]


func card(tool: BuildMode.Tool) -> Button:
	if is_room_context() and _room_cards.has(tool):
		return _room_cards[tool]
	return _cards.get(tool)


func tray() -> Control:
	return _tray


func tray_content() -> Control:
	return _tray_root


func _tray_pad_x() -> float:
	var style := _tray.get_theme_stylebox(&"panel")
	if style == null:
		return 0.0
	return style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)


func _tray_pad_y() -> float:
	var style := _tray.get_theme_stylebox(&"panel")
	if style == null:
		return 0.0
	return style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)


func _available_tray_width() -> float:
	if is_inside_tree() and get_viewport() != null:
		var view_w := get_viewport().get_visible_rect().size.x
		if view_w > 0.0:
			return minf(COLUMN_W, maxf(CARD_SIZE.x + _tray_pad_x(), view_w - 2.0 * MARGIN))
	return COLUMN_W


## Maximum inner width inside `_tray` after subtracting its panel stylebox margins.
func tray_max_inner_width() -> float:
	return _available_tray_width() - _tray_pad_x()


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
	return card_price_label(tool).text


func card_price_label(tool: BuildMode.Tool) -> Label:
	if is_room_context() and _room_price_labels.has(tool):
		return _room_price_labels[tool]
	return _price_labels[tool]


## False while the wallet cannot pay the card's price; true with no wallet.
func is_card_affordable(tool: BuildMode.Tool) -> bool:
	var trophy := tool == BuildMode.Tool.AWARD_TROPHY and awards != null
	if trophy and build_mode != null and build_mode.require_unlocks:
		return awards.trophies_available(build_mode.grid) > 0
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


## Tracks `card` (StaffPanel's hiring card) so a closed-tray status card docks
## above it while Staff is open instead of sitting behind it.
func watch_staff_card(card: Control) -> void:
	if _staff_card == card:
		return
	if _staff_card != null and is_instance_valid(_staff_card):
		if _staff_card.resized.is_connected(sync_tray_bounds):
			_staff_card.resized.disconnect(sync_tray_bounds)
		if _staff_card.visibility_changed.is_connected(sync_tray_bounds):
			_staff_card.visibility_changed.disconnect(sync_tray_bounds)
	_staff_card = card
	if _staff_card != null:
		_staff_card.resized.connect(sync_tray_bounds)
		_staff_card.visibility_changed.connect(sync_tray_bounds)
	if is_node_ready():
		sync_tray_bounds()


func _staff_card_height() -> float:
	if not staff_open:
		return 0.0
	var card := _staff_card if is_instance_valid(_staff_card) else null
	if card == null and is_inside_tree():
		var panel := get_node_or_null("../StaffPanel") as StaffPanel
		if panel != null and panel.is_node_ready():
			card = panel.card()
	if card == null or not card.visible:
		return 0.0
	return maxf(card.size.y, card.get_combined_minimum_size().y)


func _set_staff_open(open: bool) -> void:
	if open == staff_open:
		return
	staff_open = open
	staff_button.set_pressed_no_signal(open)
	staff_toggled.emit(open)
	if is_node_ready():
		sync_tray_bounds()


func _on_tool_deselected() -> void:
	_keep_tray_on_clear = true


func _on_tool_changed(tool: BuildMode.Tool) -> void:
	var keep_tray := _keep_tray_on_clear
	_keep_tray_on_clear = false
	if guide != null and tool != BuildMode.Tool.NONE:
		guide.mark_seen(tool)
	if tool == BuildMode.Tool.NONE:
		if not _browsing and not keep_tray:
			var kit_active := (
				build_mode != null
				and build_mode.starter_kit != null
				and build_mode.starter_kit.is_active()
			)
			if is_room_context() and (_has_selected_room() or kit_active):
				_sync()
				_show_status()
				return
			_clear_room_context_state()
			_open = NO_CATEGORY
			_set_staff_open(false)
	else:
		_set_staff_open(false)
		var card_hidden := _is_tool_hidden(tool)
		if BuildMode.TOOL_ROOMS.has(tool):
			var room_type: StringName = BuildMode.TOOL_ROOMS[tool]
			var index := category_of(tool)
			var tab_hidden := (
				index >= 0
				and index < _category_buttons.size()
				and not _category_buttons[index].visible
			)
			if tab_hidden or card_hidden:
				_clear_room_context_state()
				_open = NO_CATEGORY
			else:
				var keep_id := _room_context_id if _room_context_type == room_type else 0
				enter_room_context(room_type, keep_id)
				_show_status()
				return
		elif is_room_context() and _room_cards.has(tool):
			if card_hidden:
				_clear_room_context_state()
				_open = NO_CATEGORY
		elif BuildMenuCatalog.is_room_only_tool(tool):
			var owners := BuildMenuCatalog.room_owners_of(tool)
			if card_hidden or owners.is_empty():
				_clear_room_context_state()
				_open = NO_CATEGORY
			else:
				enter_room_context(owners[0], 0)
				_show_status()
				return
		else:
			_clear_room_context_state()
			var index := category_of(tool)
			var tab_hidden := (
				index >= 0
				and index < _category_buttons.size()
				and not _category_buttons[index].visible
			)
			if index == remove_category() or index < 0 or tab_hidden or card_hidden:
				_open = NO_CATEGORY
			else:
				_open = index
	_sync()
	_show_status()


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
	if mb.pressed and templates_page.visible:
		var dir := -1.0 if idx == MOUSE_BUTTON_WHEEL_UP or idx == MOUSE_BUTTON_WHEEL_LEFT else 1.0
		var factor := mb.factor if mb.factor > 0.0 else 1.0
		var delta := roundi(dir * WHEEL_STEP * factor)
		templates_page.scroll_horizontal = maxi(0, templates_page.scroll_horizontal + delta)
	_tray.accept_event()


func sync_tray_bounds() -> void:
	var bottom := MARGIN + BAR_H + GAP
	var max_w := _available_tray_width()
	if _open >= 0 and _open < _rows.size():
		var visible_count := _visible_card_count(_open)
		if visible_count > 0:
			_rows[_open].columns = mini(visible_count, tray_columns())
	elif is_room_context():
		var room_visible := _visible_room_card_count()
		if room_visible > 0:
			_room_grid.columns = mini(room_visible, tray_columns())
	var h := tray_height()
	if _tray.visible:
		var content_w := 0.0
		if _open == TEMPLATES_PAGE:
			templates_page.update_width()
			content_w = templates_page.custom_minimum_size.x
		elif is_room_context():
			var cols := maxi(1, _room_grid.columns)
			var grid_w := float(cols) * CARD_SIZE.x + float(maxi(0, cols - 1)) * float(CARD_SEP)
			content_w = maxf(grid_w, minf(_room_header_min_width(), tray_max_inner_width()))
		elif _open >= 0 and _open < _rows.size():
			var cols := maxi(1, _rows[_open].columns)
			content_w = (float(cols) * CARD_SIZE.x + float(maxi(0, cols - 1)) * float(CARD_SEP))
		var pad_x := _tray_pad_x()
		var w := clampf(content_w + pad_x, 0.0, max_w)
		_tray.custom_minimum_size = Vector2(w, h)
		if is_room_context():
			_room_box.reset_size()
		_tray_root.reset_size()
		_tray.reset_size()
		_tray.offset_left = -w * 0.5
		_tray.offset_right = w * 0.5
		_tray.offset_top = -bottom - h
		_tray.offset_bottom = -bottom
		_tray.size = Vector2(w, h)
	_status_card.offset_left = -max_w * 0.5
	_status_card.offset_right = max_w * 0.5
	var card_bottom := bottom
	if _tray.visible:
		card_bottom = bottom + h + GAP
	else:
		var staff_h := _staff_card_height()
		if staff_h > 0.0:
			card_bottom = bottom + staff_h + GAP
	BuildMenuLayout.sync_status_card_bottom(_status_card, card_bottom)


func _on_balance_changed(_balance: int) -> void:
	_refresh_money()


## Cheap wallet-change writer: updates the money slot, each OPEN card's price
## label and every card's affordability/New/locked tint without rebuilding
## hover details or touching TEASER ("In the full game") / LOCKED labels.
func _refresh_money() -> void:
	_money.text = BuildMenuCatalog.money_text(_wallet, MONEY_TEXT)
	_refresh_money_table(_cards, _price_labels)
	if is_room_context():
		_refresh_money_table(_room_cards, _room_price_labels)
		_refresh_starter_kit_money()
	refresh_preview()


func _refresh_money_table(cards: Dictionary, labels: Dictionary) -> void:
	for tool: BuildMode.Tool in labels:
		var state: int = _card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
		if state == BuildMenuCatalog.CardState.OPEN:
			var price := _card_price(tool)
			var label := labels[tool] as Label
			label.text = tr("Free", "price") if _wallet == null or price == 0 else str(price)
		if tool != _pulsed_tool and cards.has(tool):
			(cards[tool] as Control).modulate = _card_tint_for(tool, state)


func watch_awards(with_awards: AirportAwards) -> void:
	if awards == with_awards:
		return
	if awards != null and awards.trophies_changed.is_connected(_refresh_cards):
		awards.trophies_changed.disconnect(_refresh_cards)
	awards = with_awards
	if awards != null and not awards.trophies_changed.is_connected(_refresh_cards):
		awards.trophies_changed.connect(_refresh_cards)
	if is_node_ready():
		_refresh_cards()


## What a card says is locking it (BuildUnlocks.lock_text), "" when it is open.
func _lock_text(tool: BuildMode.Tool) -> String:
	return "" if build_mode == null else build_mode.tool_lock_text(tool)


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
	_money.text = BuildMenuCatalog.money_text(_wallet, MONEY_TEXT)
	var unlocks: BuildUnlocks = build_mode.unlocks if build_mode != null else null
	var required := build_mode.require_unlocks if build_mode != null else false
	var demo := DemoMode.is_demo()
	for tool: BuildMode.Tool in BuildMenuCatalog.all_catalog_tools():
		if not _cards.has(tool):
			continue
		var state := BuildMenuCatalog.card_state(tool, unlocks, required, demo, awards)
		_card_states[tool] = state
		var card_btn := _cards[tool] as ItemCardButton
		_update_card_visuals(tool, card_btn, _price_labels[tool] as Label)
		if BuildMenuCatalog.is_room_only_tool(tool):
			card_btn.visible = state != BuildMenuCatalog.CardState.HIDDEN
	var cats := categories()
	for i in cats.size():
		if i == remove_category():
			_category_buttons[i].visible = true
			continue
		_apply_row_layout(i)
		_category_buttons[i].visible = _row_has_visible_card(i)
	var closed_hidden := false
	if _open >= 0 and _open < remove_category() and not _category_buttons[_open].visible:
		_open = NO_CATEGORY
		closed_hidden = true
	if is_room_context():
		var room_tool := BuildMenuCatalog.room_tool_for(_room_context_type)
		var room_cat := category_of(room_tool)
		var room_tab_hidden := (
			room_cat >= 0
			and room_cat < _category_buttons.size()
			and not _category_buttons[room_cat].visible
		)
		if room_tab_hidden or _is_tool_hidden(room_tool):
			_clear_room_context_state()
			_open = NO_CATEGORY
			closed_hidden = true
		else:
			_refresh_room_context_state()
	templates_page.refresh_locks()
	_sync_tab_tints()
	refresh_preview()
	if closed_hidden:
		_sync()
	else:
		_sync_tray_layout()


func _update_card_visuals(
	tool: BuildMode.Tool, card_btn: ItemCardButton, price_label: Label
) -> void:
	var state: int = _card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
	var lock := _lock_text(tool)
	var card_item := item(tool)
	var shown_name := BuildMenuCatalog.shown(card_item[0])
	card_btn.requirement = _lock_text.bind(tool) if lock != "" else Callable()
	card_btn.set_info(shown_name, ItemInfo.of(tool), BuildMenuCatalog.card_details(tool))
	var name_label := card_btn.get_child(0).get_node_or_null("Name") as Label
	if name_label != null:
		name_label.text = shown_name
	var badge_label := card_btn.get_node_or_null("RoomBadge/RoomBadgeLabel") as Label
	if badge_label != null:
		badge_label.text = tr("Room", "build menu")
	if state == BuildMenuCatalog.CardState.TEASER:
		price_label.text = tr("In the full game")
	elif state == BuildMenuCatalog.CardState.LOCKED:
		price_label.text = tr("Locked")
	else:
		var price := _card_price(tool)
		price_label.text = tr("Free", "price") if _wallet == null or price == 0 else str(price)
	if tool != _pulsed_tool:
		card_btn.modulate = _card_tint_for(tool, state)


func _visible_card_count(index: int) -> int:
	if index < 0 or index >= _rows.size():
		return 0
	var count := 0
	for tool in categories()[index]["tools"]:
		if (
			_cards.has(tool)
			and (
				_card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
				!= BuildMenuCatalog.CardState.HIDDEN
			)
		):
			count += 1
	return count


func _row_has_visible_card(index: int) -> bool:
	return _visible_card_count(index) > 0


func _apply_row_layout(index: int) -> void:
	if index < 0 or index >= _rows.size() or index == remove_category():
		return
	var cats := categories()
	var front_cards: Array[Control] = []
	var teaser_cards: Array[Control] = []
	for tool: BuildMode.Tool in cats[index]["tools"]:
		if not _cards.has(tool):
			continue
		var card_btn := _cards[tool] as Control
		var state: int = _card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
		var shown_here := state != BuildMenuCatalog.CardState.HIDDEN
		card_btn.visible = shown_here
		if not shown_here:
			continue
		if state == BuildMenuCatalog.CardState.TEASER:
			teaser_cards.append(card_btn)
		else:
			front_cards.append(card_btn)
	var ordered: Array[Control] = []
	ordered.append_array(front_cards)
	ordered.append_array(teaser_cards)
	if not ordered.is_empty():
		_rows[index].columns = mini(ordered.size(), tray_columns())
	for pos in ordered.size():
		_rows[index].move_child(ordered[pos], pos)


func _sync_tray_layout() -> void:
	sync_tray_bounds()


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
	elif text == "" and build_mode.object_mover.active:
		text = build_mode.object_mover.status_text()
	elif text == "" and build_mode.starter_kit != null and build_mode.starter_kit.is_active():
		text = build_mode.starter_kit.status_text()
	_on_status_changed(text)


func _on_status_changed(text: String) -> void:
	_raw_status = text
	if _holding:
		_held_status = text
		return
	_show_status()


func _on_refusal_shown(text: String) -> void:
	if not _holding or _hold_is_grant or text == "":
		return
	_raw_status = text
	_end_passive_hold()


func _on_edit_refused(_edit: BuildEdit, result: BuildResult) -> void:
	if not _holding or _hold_is_grant or result == null or result.ok:
		return
	var mode_text := build_mode.status_text() if build_mode != null else ""
	_raw_status = mode_text if mode_text != "" else result.reason_text()
	_end_passive_hold()


func _end_passive_hold() -> void:
	_pending_wages = ""
	_wages_hold_amount = 0
	_wages_hold_owed = 0
	_holding = false
	_hold_generation += 1
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
	if is_grant:
		_wages_hold_amount = 0
		_wages_hold_owed = 0
	_status.text = message
	# A held message is long on purpose (a rescue grant); it wraps and the card
	# grows upward instead of cutting it short.
	_wrap_status(true)
	_rotate_hint.visible = false
	_hold_generation += 1
	if is_inside_tree() and get_tree() != null:
		var timer := get_tree().create_timer(grant_hold_s)
		timer.timeout.connect(_on_hold_timeout.bind(_hold_generation))


## "Wages paid: N", with the debt left when there is one, held like a grant
## message. During a rescue hold it waits (the latest one) instead of replacing it.
func _on_wages_paid(amount: int, owed: int) -> void:
	if amount <= 0:
		return
	_wages_hold_amount = amount
	_wages_hold_owed = owed
	var message := _wages_message(amount, owed)
	if _holding and _hold_is_grant:
		_pending_wages = message
		return
	_start_hold(message, false)


func _wages_message(amount: int, owed: int) -> String:
	if owed > 0:
		return tr("Wages paid: {amount} ({owed} owed)").format({"amount": amount, "owed": owed})
	return tr("Wages paid: {amount}").format({"amount": amount})


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
## move and ends build mode (used when a full-screen modal takes over).
func close_for_modal() -> void:
	_clear_room_context_state()
	_open = NO_CATEGORY
	_set_staff_open(false)
	if build_mode != null:
		build_mode.templates.disarm()
		if build_mode.starter_kit != null:
			build_mode.starter_kit.disarm()
		if build_mode.room_mover.active:
			build_mode.room_mover.cancel()
		if build_mode.object_mover.active:
			build_mode.object_mover.cancel()
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
	_clear_room_context_state()
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
	_wages_hold_amount = 0
	_wages_hold_owed = 0
	_holding = false
	_show_status()


## Shows the open category's row and marks the selected category and card.
func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	for i in _rows.size():
		_rows[i].visible = i == _open
	if _open >= 0 and _open < remove_category():
		_apply_row_layout(_open)
	_room_box.visible = is_room_context()
	if is_room_context():
		_refresh_room_context_state()
	for i in _category_buttons.size():
		var on := _open == i or (i == remove_category() and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	_sync_tab_tints()
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)
	for key in _room_cards:
		_room_cards[key].set_pressed_no_signal(key == tool)
	var armed_kit := (
		build_mode.starter_kit.armed
		if build_mode != null and build_mode.starter_kit != null
		else &""
	)
	for kit_id: StringName in _starter_kit_cards:
		_starter_kit_cards[kit_id].set_pressed_no_signal(kit_id == armed_kit)
	var pulse_in_context := is_room_context() and _room_cards.has(_pulsed_tool)
	if (
		_pulsed_tool != BuildMode.Tool.NONE
		and not pulse_in_context
		and _open != category_of(_pulsed_tool)
	):
		_stop_pulse()
	templates_page.sync(_open == TEMPLATES_PAGE)
	_sync_tray_layout()
	build_session.set_building(_open != NO_CATEGORY or tool != BuildMode.Tool.NONE)


## Height, from the bottom edge, of the top of the tray and status card stack:
## what a card that must not cover any of them docks above.
static func tray_stack_top(tray_h: float = TRAY_H) -> float:
	return MARGIN + BAR_H + GAP + tray_h + GAP + STATUS_H


## Height, from the bottom edge, of the top of the active bottom stack: when a
## tray is open, tray_stack_top() with the live tray height and status card's
## height; when closed, the category bar plus any visible StaffCard and/or
## visible status card above it.
func stack_top() -> float:
	var card_h := maxf(STATUS_H, _status_card.size.y) if _status_card.visible else STATUS_H
	if _tray.visible:
		return MARGIN + BAR_H + GAP + tray_height() + GAP + card_h
	var top := MARGIN + BAR_H
	var staff_h := _staff_card_height()
	if staff_h > 0.0:
		top += GAP + staff_h
	if _status_card.visible:
		top += GAP + card_h
	return top


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
static func anchor_bottom_centre(control: Control, bottom: float) -> void:
	BuildMenuLayout.anchor_bottom_centre(control, bottom)


func _retranslate() -> void:
	templates_page.button.tooltip_text = tr("Templates", "build menu")
	var cats := categories()
	for i in cats.size():
		if i < _category_buttons.size():
			_category_buttons[i].tooltip_text = BuildMenuCatalog.shown(cats[i]["name"])
	staff_button.tooltip_text = tr("Staff", "build menu")
	_room_back_button.text = tr("← Back")
	for tool: BuildMode.Tool in BuildMenuCatalog.all_catalog_tools():
		if _cards.has(tool):
			_update_card_visuals(tool, _cards[tool] as ItemCardButton, _price_labels[tool] as Label)
	if is_room_context():
		_refresh_room_context_state()
	_rotate_hint.text = RotateHint.text()
	if _holding:
		if not _hold_is_grant and _wages_hold_amount > 0:
			_status.text = _wages_message(_wages_hold_amount, _wages_hold_owed)
	elif build_mode != null:
		_on_mode_status_changed(build_mode.status_text())
	if _pending_wages != "" and _wages_hold_amount > 0:
		_pending_wages = _wages_message(_wages_hold_amount, _wages_hold_owed)
	_money_slot.refresh()
	refresh_preview()
	sync_tray_bounds()


func _is_tool_hidden(tool: BuildMode.Tool) -> bool:
	return (
		int(_card_states.get(tool, BuildMenuCatalog.CardState.OPEN))
		== BuildMenuCatalog.CardState.HIDDEN
	)


func _has_selected_room() -> bool:
	return _selection != null and _selection.kind == BuiltSelection.Kind.ROOM


func _validated_room_id(room_id: int) -> int:
	if room_id == 0 or build_mode == null or build_mode.grid == null:
		return 0
	return 0 if build_mode.grid.get_room(room_id).is_empty() else room_id


func _clear_room_context_state() -> void:
	_room_context_type = &""
	_room_context_id = 0
	_back_category = NO_CATEGORY
	_room_entries.clear()
	if build_mode != null and build_mode.starter_kit != null:
		build_mode.starter_kit.disarm()


func _rebuild_room_context_cards() -> void:
	BuildMenuLayout.rebuild_room_context_cards(self)


func _refresh_room_context_state() -> void:
	BuildMenuLayout.refresh_room_context_state(self)


func _visible_room_card_count() -> int:
	var count := 0
	for entry: Dictionary in _room_entries:
		var tool: BuildMode.Tool = entry["tool"]
		if (
			_room_cards.has(tool)
			and (
				_card_states.get(tool, BuildMenuCatalog.CardState.OPEN)
				!= BuildMenuCatalog.CardState.HIDDEN
			)
		):
			count += 1
	if _starter_kit_cards.has(_room_context_type):
		var unlocks: BuildUnlocks = build_mode.unlocks if build_mode != null else null
		var required := build_mode.require_unlocks if build_mode != null else false
		if (
			StarterRoomKits.card_state(_room_context_type, unlocks, required, DemoMode.is_demo())
			!= BuildMenuCatalog.CardState.HIDDEN
		):
			count += 1
	return count


func _room_header_min_width() -> float:
	return BuildMenuLayout.room_header_min_width(self)


func _on_grid_edit_applied(edit: BuildEdit, result: BuildResult) -> void:
	if (
		result != null
		and result.ok
		and edit != null
		and edit.kind == BuildEdit.Kind.PLACE_ROOM
		and build_mode != null
		and (
			BuildMode.TOOL_ROOMS.get(build_mode.tool, &"") == edit.room_type
			or (
				build_mode.starter_kit != null
				and build_mode.starter_kit.is_active()
				and (
					StarterRoomKits.get_kit(build_mode.starter_kit.armed).get("room_type", &"")
					== edit.room_type
				)
			)
		)
	):
		enter_room_context(edit.room_type, result.room_id)
		return
	if is_room_context():
		_refresh_room_context_state()
		_sync_tray_layout()


func _on_grid_graph_changed(_cells: Array[Vector2i]) -> void:
	if awards != null:
		_refresh_money()
	if is_room_context():
		_refresh_room_context_state()
		_sync_tray_layout()


func _on_built_selection_changed() -> void:
	if _selection == null:
		return
	if build_mode != null:
		build_mode.set_selected_room(
			_selection.id if _selection.kind == BuiltSelection.Kind.ROOM else 0
		)
	if (
		_selection.kind == BuiltSelection.Kind.ROOM
		and build_mode != null
		and build_mode.grid != null
	):
		var room := build_mode.grid.get_room(_selection.id)
		if not room.is_empty():
			enter_room_context(StringName(room["type"]), _selection.id)
			return
	var kit_active := (
		build_mode != null and build_mode.starter_kit != null and build_mode.starter_kit.is_active()
	)
	if (
		is_room_context()
		and (build_mode == null or (build_mode.tool == BuildMode.Tool.NONE and not kit_active))
	):
		exit_room_context()


func _on_starter_kit_armed_changed() -> void:
	var armed_kit := (
		build_mode.starter_kit.armed
		if build_mode != null and build_mode.starter_kit != null
		else &""
	)
	for kit_id: StringName in _starter_kit_cards:
		_starter_kit_cards[kit_id].set_pressed_no_signal(kit_id == armed_kit)
	_show_status()


func _on_eyedropper_picked(pick: Dictionary) -> void:
	var picked_tool: BuildMode.Tool = pick.get("tool", BuildMode.Tool.NONE)
	var room_type: StringName = pick.get("room_type", &"")
	var room_id := int(pick.get("room_id", 0))
	if room_type == &"":
		return
	if (
		(
			BuildMenuCatalog.is_room_only_tool(picked_tool)
			and BuildMenuCatalog.room_owners_of(picked_tool).has(room_type)
		)
		or BuildMode.TOOL_ROOMS.get(picked_tool, &"") == room_type
	):
		enter_room_context(room_type, room_id)
		_show_status()


func _refresh_starter_kit_money() -> void:
	BuildMenuLayout.refresh_starter_kit_money(self)
