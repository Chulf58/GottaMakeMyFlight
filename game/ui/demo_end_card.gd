class_name DemoEndCard
extends Node
## End-of-demo summary card (decision
## demo-scope-and-cut-line-d1-cap-playable-unlocks-at-tier-2-1). Mounted by
## PassengerHud; inactive when DemoMode.is_demo() is false. Once Day 5 rolls
## over into Day 6 (GameCalendar.day_of >= DemoMode.MAX_DEMO_DAY, after Day 5's
## flights have finished and while SaveGame queues the Day-6 morning autosave),
## or immediately on start/load when the clock is already past Day 5, it pauses
## SimClock through ClockHolds (non-yielding, synchronous on the rollover tick),
## closes any open build tool or menu, and shows the 5-day summary with
## Wishlist on Steam and Back to Title actions.

signal dialog_changed(open: bool)

const LAYER := 12
const PANEL_W := 620.0
const TITLE_TEXT := "Day 5 complete — thanks for playing the demo!"
const BODY_TEXT := (
	"Start a New Airport anytime, or wishlist the full game for larger planes,"
	+ " restaurants, lounges, car parks, and major airport chaos."
)
const WISHLIST_TEXT := "Wishlist on Steam"
const BACK_TEXT := "Back to Title"

var clock: SimClock
var rating: AirportRating
var unlocks: BuildUnlocks
var finances: Finances
var day_ledger: DayLedger
var build_mode: BuildMode
var build_menu: BuildMenu
var save_game: SaveGame
var hud: PassengerHud
var url_opener: Callable
var back_to_title: Callable
var feedback_url: String = DemoMode.FEEDBACK_URL

var _layer: CanvasLayer
var _panel: PanelContainer
var _hold := ClockHolds.NONE
var _shown := false
var _triggered := false
var _cash_earned := 0
var _bound_wallet: Wallet


func _ready() -> void:
	name = "DemoEndCard"
	if not url_opener.is_valid():
		url_opener = func(url: String) -> void: OS.shell_open(url)
	if not back_to_title.is_valid():
		back_to_title = func() -> void: get_tree().change_scene_to_file(GameBoot.TITLE_SCENE)
	_wire_siblings()
	_bind_wallet()
	if clock != null and not clock.ticked.is_connected(on_tick):
		clock.ticked.connect(on_tick)
	if save_game != null and not save_game.loaded.is_connected(_on_save_loaded):
		save_game.loaded.connect(_on_save_loaded)
	check_now()


func _exit_tree() -> void:
	_unbind_wallet()
	_release_hold()
	if is_instance_valid(_layer):
		_layer.free()
	_layer = null
	_panel = null


func is_open() -> bool:
	return _shown


## True when demo mode is active and the calendar has passed Day 5 (into Day 6+).
func is_due() -> bool:
	if not DemoMode.is_demo() or clock == null or clock.calendar_held:
		return false
	return GameCalendar.day_of(clock.tick, clock.epoch) >= DemoMode.MAX_DEMO_DAY


func on_tick(_tick: int) -> void:
	if not _shown and not _triggered and is_due():
		open()


func check_now() -> void:
	if not _shown and not _triggered and is_due():
		open()


## Opens the end-of-demo card and takes a non-yielding hold on SimClock.
func open() -> bool:
	if _shown or not DemoMode.is_demo():
		return false
	_shown = true
	_triggered = true
	_close_active_ui()
	_sweep_late_ui.call_deferred()
	_build_layer()
	dialog_changed.emit(true)
	return true


func _sweep_late_ui() -> void:
	if not _shown:
		return
	var other_holds := is_instance_valid(clock) and clock.holds.count() > 1
	var tray_open := build_menu != null and build_menu.is_tray_open()
	if other_holds or tray_open:
		_close_active_ui()


func close() -> void:
	if not _shown:
		return
	_free_layer()
	_release_hold()
	dialog_changed.emit(false)


func press_wishlist() -> void:
	if url_opener.is_valid():
		url_opener.call(DemoMode.STEAM_STORE_URL)


func press_feedback() -> void:
	if not feedback_url.is_empty() and url_opener.is_valid():
		url_opener.call(feedback_url)


func press_back_to_title() -> void:
	close()
	if back_to_title.is_valid():
		back_to_title.call()


func summary_stats() -> Dictionary:
	var made := 0
	if unlocks != null:
		made = unlocks.made_total()
	elif rating != null:
		for day in rating.days_held():
			made += int(rating.day_totals(day)["made"])
	var stars := rating.stars() if rating != null else RatingFormula.STARTING_STARS
	var balance := finances.wallet.balance if finances != null else 0
	var earned := day_ledger.total_earned() if day_ledger != null else _cash_earned
	var since_load := day_ledger.is_since_load() if day_ledger != null else false
	return {
		"passengers_made": made,
		"stars": stars,
		"cash_earned": earned,
		"balance": balance,
		"since_load": since_load,
	}


func panel() -> PanelContainer:
	return _panel


func wishlist_button() -> Button:
	return _panel.find_child("WishlistButton", true, false) as Button if _panel != null else null


func feedback_button() -> Button:
	return (
		_panel.find_child("SendFeedbackButton", true, false) as Button if _panel != null else null
	)


func back_button() -> Button:
	return _panel.find_child("BackToTitleButton", true, false) as Button if _panel != null else null


func _wire_siblings() -> void:
	var root := hud.get_parent() if hud != null else get_parent()
	if root == null:
		return
	if rating == null:
		rating = root.get_node_or_null("AirportRating") as AirportRating
	if finances == null:
		finances = root.get_node_or_null("Finances") as Finances
	if day_ledger == null:
		day_ledger = root.get_node_or_null("DayLedger") as DayLedger
	if build_menu == null:
		build_menu = root.get_node_or_null("BuildMenu") as BuildMenu
	if unlocks == null and build_mode != null:
		unlocks = build_mode.unlocks
	if unlocks == null:
		unlocks = root.get_node_or_null("BuildUnlocks") as BuildUnlocks


func _bind_wallet() -> void:
	_unbind_wallet()
	if finances == null:
		return
	_bound_wallet = finances.wallet
	if _bound_wallet != null:
		_bound_wallet.transaction.connect(_on_wallet_transaction)


func _unbind_wallet() -> void:
	if _bound_wallet != null and _bound_wallet.transaction.is_connected(_on_wallet_transaction):
		_bound_wallet.transaction.disconnect(_on_wallet_transaction)
	_bound_wallet = null


func _on_wallet_transaction(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
	if amount > 0 and DayLedger.EARNED_CATEGORIES.has(category):
		_cash_earned += amount


func _on_save_loaded(ok: bool) -> void:
	if not ok:
		return
	var was_open := _shown
	_shown = false
	_triggered = false
	var old_layer := _layer
	_layer = null
	_panel = null
	if is_instance_valid(old_layer):
		old_layer.free()
	_hold = ClockHolds.NONE
	if was_open:
		dialog_changed.emit(false)
	_cash_earned = day_ledger.total_earned() if day_ledger != null else 0
	check_now()


func _close_active_ui() -> void:
	if _shown and is_instance_valid(clock) and is_inside_tree() and not clock.holds.has(_hold):
		_hold = clock.holds.acquire(self, false)
	var root := hud.get_parent() if hud != null else get_parent()
	_close_waiting_turns(root)
	if build_menu != null:
		build_menu.close_for_modal()
	elif build_mode != null:
		build_mode.templates.disarm()
		if build_mode.room_mover.active:
			build_mode.room_mover.cancel()
		build_mode.set_tool(BuildMode.Tool.NONE)
	_close_open_turns(root)


func _close_waiting_turns(root: Node) -> void:
	if hud != null:
		if hud.intro() == null:
			hud.dismiss_intro()
		var guide := hud.unlock_guide()
		if guide != null and not guide.is_open():
			guide.close_for_modal()
	if is_inside_tree():
		for sheet in get_tree().get_nodes_in_group(TopRow.SHEET_GROUP):
			if (
				sheet.has_method("is_open")
				and not sheet.call("is_open")
				and sheet.has_method("close")
			):
				sheet.call("close")
	if root == null:
		return
	var game_menu := root.get_node_or_null("GameMenu") as GameMenu
	if game_menu != null and not game_menu.is_open():
		game_menu.close()
	var incident_panel := root.get_node_or_null("IncidentPanel") as IncidentPanel
	if incident_panel != null and not incident_panel.is_open():
		incident_panel.close_for_modal()


func _close_open_turns(root: Node) -> void:
	if hud != null:
		hud.dismiss_intro()
		if hud.unlock_guide() != null:
			hud.unlock_guide().close_for_modal()
	if is_inside_tree():
		for sheet in get_tree().get_nodes_in_group(TopRow.SHEET_GROUP):
			if sheet.has_method("close"):
				sheet.call("close")
	if root == null:
		return
	var game_menu := root.get_node_or_null("GameMenu") as GameMenu
	if game_menu != null:
		game_menu.close()
		if game_menu.question() != null:
			game_menu.question().dismiss()
	var incident_panel := root.get_node_or_null("IncidentPanel") as IncidentPanel
	if incident_panel != null:
		incident_panel.close_for_modal()


func _build_layer() -> void:
	var stats := summary_stats()
	_layer = CanvasLayer.new()
	_layer.name = "DemoEndCardLayer"
	_layer.layer = LAYER
	var root := _ModalRoot.new()
	root.name = "Root"
	root.theme = BuildMenu.HUD_THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = IntroDialogue.DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "DemoEndPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_panel)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 16)
	pad.add_child(column)
	column.add_child(_make_header())
	column.add_child(_make_stats_card(stats))
	var body := Label.new()
	body.name = "Body"
	body.text = tr(
		# gdlint:ignore = max-line-length
		"Start a New Airport anytime, or wishlist the full game for larger planes, restaurants, lounges, car parks, and major airport chaos."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(body)
	column.add_child(_make_buttons())
	add_child(_layer)


func _make_header() -> Control:
	var header := PanelContainer.new()
	header.name = "Header"
	header.theme_type_variation = &"IntroNameplate"
	var title := Label.new()
	title.name = "Title"
	title.text = tr("Day 5 complete — thanks for playing the demo!")
	title.theme_type_variation = &"IntroName"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	return header


func _make_stats_card(stats: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "StatsCard"
	card.theme_type_variation = &"HudSubCard"
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pad.add_child(box)
	var heading := Label.new()
	heading.name = "StatsHeading"
	heading.text = tr("Your 5-day airport summary")
	heading.theme_type_variation = &"HudTitle"
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.theme_type_variation = &"HudMoneyGrid"
	box.add_child(grid)
	_add_stat_row(
		grid,
		"PassengersRow",
		tr("Passengers who made their flight"),
		str(stats["passengers_made"]),
		&"HudCardName"
	)
	_add_stars_row(grid, float(stats["stars"]))
	if not bool(stats["since_load"]) or int(stats["cash_earned"]) > 0:
		_add_stat_row(
			grid,
			"CashEarnedRow",
			tr("Cash earned"),
			tr("${amount}").format({"amount": stats["cash_earned"]}),
			&"HudMoney"
		)
	_add_stat_row(
		grid,
		"BalanceRow",
		tr("Current balance"),
		tr("${amount}").format({"amount": stats["balance"]}),
		&"HudMoney"
	)
	return card


func _add_stat_row(
	grid: GridContainer,
	row_name: String,
	label_text: String,
	value_text: String,
	variation: StringName
) -> void:
	var label := Label.new()
	label.name = row_name + "Label"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var value := Label.new()
	value.name = row_name + "Value"
	value.text = value_text
	value.theme_type_variation = variation
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)


func _add_stars_row(grid: GridContainer, stars: float) -> void:
	var label := Label.new()
	label.name = "StarsRowLabel"
	label.text = tr("Airport rating")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var right := HBoxContainer.new()
	right.name = "StarsRowBox"
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 8)
	var star_row := RatingBadge.StarRow.new()
	star_row.fills = RatingBadge.star_fills(stars)
	star_row.custom_minimum_size = Vector2(
		(
			RatingBadge.STAR_COUNT * RatingBadge.STAR_SIZE
			+ (RatingBadge.STAR_COUNT - 1) * RatingBadge.STAR_GAP
		),
		RatingBadge.STAR_SIZE
	)
	star_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(star_row)
	var value := Label.new()
	value.name = "StarsRowValue"
	value.text = tr("{stars} stars").format({"stars": "%.1f" % stars})
	value.theme_type_variation = &"HudCardName"
	right.add_child(value)
	grid.add_child(right)


func _make_buttons() -> Control:
	var stack := VBoxContainer.new()
	stack.name = "ButtonStack"
	stack.add_theme_constant_override("separation", 10)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var wishlist := Button.new()
	wishlist.name = "WishlistButton"
	wishlist.text = tr("Wishlist on Steam")
	wishlist.theme_type_variation = &"HudButtonGreen"
	wishlist.custom_minimum_size = Vector2(220.0, float(HudLayout.BUTTON_H))
	wishlist.focus_mode = Control.FOCUS_NONE
	wishlist.pressed.connect(press_wishlist)
	buttons.add_child(wishlist)
	var back := Button.new()
	back.name = "BackToTitleButton"
	back.text = tr("Back to Title")
	back.custom_minimum_size = Vector2(200.0, float(HudLayout.BUTTON_H))
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(press_back_to_title)
	buttons.add_child(back)
	stack.add_child(buttons)
	var feedback := Button.new()
	feedback.name = "SendFeedbackButton"
	feedback.text = tr("Send Feedback")
	feedback.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	feedback.focus_mode = Control.FOCUS_NONE
	feedback.visible = not feedback_url.is_empty()
	feedback.pressed.connect(press_feedback)
	stack.add_child(feedback)
	return stack


func _free_layer() -> void:
	_shown = false
	var layer := _layer
	_layer = null
	_panel = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


func _release_hold() -> void:
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE


class _ModalRoot:
	extends Control

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree():
			return
		var key := event as InputEventKey
		if key == null or not key.pressed:
			return
		if (
			not key.echo
			and not key.ctrl_pressed
			and not key.alt_pressed
			and not key.shift_pressed
			and not key.meta_pressed
			and key.keycode in [SaveGame.QUICK_SAVE_KEY, SaveGame.QUICK_LOAD_KEY]
		):
			return
		get_viewport().set_input_as_handled()
