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

## The hiring card opened or closed (the StaffPanel shows it with this).
signal staff_toggled(open: bool)

## Aliases of BuildMenuCatalog constants.
const THUMBNAIL_DIR := BuildMenuCatalog.THUMBNAIL_DIR
const CATEGORIES := BuildMenuCatalog.CATEGORIES
const REMOVE_CATEGORY := BuildMenuCatalog.REMOVE_CATEGORY
const NO_CATEGORY := BuildMenuCatalog.NO_CATEGORY
const TEMPLATES_PAGE := BuildMenuCatalog.TEMPLATES_PAGE
const ITEMS := BuildMenuCatalog.ITEMS
const LANE_ITEMS := BuildMenuCatalog.LANE_ITEMS
const CARD_NEEDS := BuildMenuCatalog.CARD_NEEDS
const CARD_RUNNING_COSTS := BuildMenuCatalog.CARD_RUNNING_COSTS
const PLACEHOLDER_THUMBNAILS := []
const PLACEHOLDER_COLOR := Color(0.3, 0.26, 0.2)
## The English msgids of card bottom labels: tests compare against them, and the
## labels themselves are tr() of the literal, because the POT extractor reads only literals.
const PRICE_TEXT := "Free"
const LOCKED_TEXT := "Locked"
const LOCKED_TINT := Color(0.5, 0.5, 0.55)
## The tint of a card or domain tab of the newest opened tier until the player
## hovers or picks its unseen tools (UnlockGuide.is_new).
const NEW_TINT := Color(1.0, 0.88, 0.45)
const MONEY_TEXT := "--"

## Geometry in pixels, measured up from the bottom edge.
const MARGIN := float(HudLayout.MARGIN)
const BAR_H := float(HudLayout.BAR_H)
const GAP := float(HudLayout.GAP)
const TRAY_H := float(HudLayout.TRAY_H)
const STATUS_H := float(HudLayout.BUTTON_H)
const STATUS_LINES := 2
const HELD_LINES := 3
## Maximum width of the centre column the tray and status line live in;
## PassengerHud and PassengerInspect keep left of it.
const COLUMN_W := float(HudLayout.TRAY_W)
const CARD_SIZE := Vector2(96.0, 126.0)
const THUMB_SIZE := 52.0
const CATEGORY_SIZE := Vector2(52.0, 44.0)
const WHEEL_STEP := 64.0

const HUD_THEME := preload("res://ui/hud_theme.tres")
const GHOST_REASON_LAYER := 3
const GRANT_HOLD_S := 8.0

@export var build_mode: BuildMode
@export var rescue_grant: RescueGrant
@export var grant_hold_s := GRANT_HOLD_S
@export var day_ledger: DayLedger
@export var settlement: Settlement
@export var save_game: SaveGame
@export var clock: SimClock
## Optional: marks the cards and tabs of a newly opened tier "New" (PassengerHud
## wires it with watch_guide()); without it no card or tab carries the mark.
var guide: UnlockGuide

var staff_open := false
var staff_button := Button.new()
var build_session := BuildSession.new()
var build_frame := BuildModeFrame.new()
var templates_page := TemplatesPage.new()

var _open := NO_CATEGORY
var _browsing := false
var _bar := PanelContainer.new()
var _tray := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _scroll_content := HBoxContainer.new()
var _rows: Array[HBoxContainer] = []
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
var _status_card := PanelContainer.new()
var _status := Label.new()
var _rotate_hint := Label.new()
var _money := Label.new()
var _money_slot := MoneySlot.new()
var _cost := Label.new()
var _wallet: Wallet
var _price_labels: Dictionary = {}
var _rect_cost_key := ""
var _rect_cost := 0
var _room_panel := RoomPanel.new()
var _ghost_reason := GhostReason.new()
var _holding := false
var _hold_generation := 0
var _held_status := ""
var _raw_status := ""
var _hold_is_grant := false
var _pending_wages := ""


static func tool_price(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.tool_price(tool)


static func categories() -> Array:
	return BuildMenuCatalog.categories()


static func category_id(index: int) -> String:
	return BuildMenuCatalog.category_id(index)


static func category_index(id: String) -> int:
	return BuildMenuCatalog.category_index(id)


static func remove_category() -> int:
	return BuildMenuCatalog.remove_category()


static func item(tool: BuildMode.Tool) -> Array:
	return BuildMenuCatalog.item(tool)


static func running_cost(tool: BuildMode.Tool) -> int:
	return BuildMenuCatalog.running_cost(tool)


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
		build_mode.land_tool.land.changed.connect(_refresh_cards)
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
	_scroll.scroll_horizontal = 0
	templates_page.scroll_horizontal = 0
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()


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


func press_card(tool: BuildMode.Tool) -> void:
	build_mode.set_tool(tool)


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


func bar() -> Control:
	return _bar


func status_label() -> Label:
	return _status


func status_card() -> PanelContainer:
	return _status_card


func rotate_hint_label() -> Label:
	return _rotate_hint


func money_label() -> Label:
	return _money


func preview_label() -> Label:
	return _cost


func card_price_text(tool: BuildMode.Tool) -> String:
	return (_price_labels[tool] as Label).text


func card_price_label(tool: BuildMode.Tool) -> Label:
	return _price_labels[tool]


func is_card_affordable(tool: BuildMode.Tool) -> bool:
	return _wallet == null or _wallet.can_afford(_card_price(tool))


func _card_price(tool: BuildMode.Tool) -> int:
	return BuildMenuPrices.card_price(self, tool)


static func unaffordable_tint() -> Color:
	return HUD_THEME.get_color("unaffordable_tint", "HudCard")


func preview_text() -> String:
	return BuildMenuPrices.preview_text(self)


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


func _pointer_on_grid() -> bool:
	return build_mode.pointer_on_grid()


func room_panel() -> RoomPanel:
	return _room_panel


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
	if tool == BuildMode.Tool.NONE:
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
		else:
			_open = index
			if _open != prev_open:
				_scroll.scroll_horizontal = 0
			_ensure_card_visible.call_deferred(tool)
	_sync()
	_show_status()


func _ensure_card_visible(tool: BuildMode.Tool) -> void:
	if not is_inside_tree() or not _scroll.visible or not _cards.has(tool):
		return
	var target := _cards[tool] as Control
	if target.is_visible_in_tree():
		_scroll.ensure_control_visible(target)


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
	var pad_x := 0.0
	var style := _tray.get_theme_stylebox(&"panel")
	if style != null:
		pad_x = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	var max_inner := COLUMN_W - pad_x
	var row_w := _scroll_content.get_combined_minimum_size().x
	_scroll.custom_minimum_size.x = minf(row_w, max_inner)


func _on_balance_changed(_balance: int) -> void:
	_refresh_cards()


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


## Single card and category-tab state writer: updates money slot, card visibility,
## bottom price/teaser/locked label, hover popup details + live lock requirement,
## teaser right-end ordering, tab visibility and tab "New" highlight.
func _refresh_cards() -> void:
	_money.text = MONEY_TEXT if _wallet == null else str(_wallet.balance)
	var unlocks: BuildUnlocks = build_mode.unlocks if build_mode != null else null
	var required := build_mode.require_unlocks if build_mode != null else false
	var demo := DemoMode.is_demo()
	var cats := categories()
	for i in cats.size():
		if i == remove_category():
			_category_buttons[i].visible = true
			_category_buttons[i].modulate = Color.WHITE
			continue
		var front_cards: Array[Control] = []
		var teaser_cards: Array[Control] = []
		for tool: BuildMode.Tool in cats[i]["tools"]:
			if not _cards.has(tool):
				continue
			var state := BuildMenuCatalog.card_state(tool, unlocks, required, demo)
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
		_category_buttons[i].modulate = NEW_TINT if _category_has_new(i) else Color.WHITE
	var closed_hidden := false
	if _open >= 0 and _open < remove_category() and not _category_buttons[_open].visible:
		_open = NO_CATEGORY
		closed_hidden = true
	refresh_preview()
	if closed_hidden:
		_sync()
	else:
		_sync_scroll_width()


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


func _on_unlocked(_tier: int, text: String) -> void:
	if guide != null and guide.is_open():
		return
	_start_hold(text, false)


func _price_floor_rect(area: Rect2i) -> int:
	return AreaDrag.floor_cost(build_mode.grid, area)


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


func _show_status() -> void:
	if not _holding:
		_status.text = _raw_status
		_wrap_status(false)
		_rotate_hint.visible = _status.visible and RotateHint.applies(build_mode)


func _wrap_status(held: bool) -> void:
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	_status.max_lines_visible = HELD_LINES if held else STATUS_LINES
	_status.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if held else TextServer.OVERRUN_TRIM_ELLIPSIS
	)


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
	_wrap_status(true)
	_rotate_hint.visible = false
	_hold_generation += 1
	var timer := get_tree().create_timer(grant_hold_s)
	timer.timeout.connect(_on_hold_timeout.bind(_hold_generation))


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


func close_for_modal() -> void:
	_open = NO_CATEGORY
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


func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	_scroll.visible = _open >= 0
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := _open == i or (i == remove_category() and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)
	templates_page.sync(_open == TEMPLATES_PAGE)
	_sync_scroll_width()
	build_session.set_building(_open != NO_CATEGORY or tool != BuildMode.Tool.NONE)


static func tray_stack_top() -> float:
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + STATUS_H


func stack_top() -> float:
	var card_h := _status_card.size.y if _status_card.visible else STATUS_H
	return MARGIN + BAR_H + GAP + TRAY_H + GAP + maxf(STATUS_H, card_h)


static func anchor_bottom_centre(control: Control, bottom: float) -> void:
	BuildMenuLayout.anchor_bottom_centre(control, bottom)
