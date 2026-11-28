class_name HelpSheet
extends Control
## Two Point Hospital-style Help & Hints handbook sheet (decision
## interactive-dialog-chips-and-help-hints-handbook-sheet, 257fbadd).
## Shows core airport flow, controls, current unlock highlights, past phone
## calls read dynamically from BuildUnlocks, and the live Auto-hints toggle.

enum Tab { GUIDE, PAST_CALLS }

const DEFAULT_WIDTH := float(TopRow.SHEET_W)
const MIN_SCROLL_H := 160.0

var hints: Hints
var unlocks: BuildUnlocks
var flights: FlightSim
var save_game: SaveGame

var _panel := PanelContainer.new()
var _title := Label.new()
var _auto_hints := Button.new()
var _close_btn := Button.new()
var _guide_tab := Button.new()
var _calls_tab := Button.new()
var _scroll := ScrollContainer.new()
var _cards := VBoxContainer.new()
var _tab := Tab.GUIDE
var _bound_save: SaveGame
var _body_labels: Array[Label] = []


func _init() -> void:
	name = "HelpSheet"
	theme = BuildMenu.HUD_THEME
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	_bind_save()
	sync_auto_hints(hints.is_enabled() if hints != null else true)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)
	if is_instance_valid(_bound_save) and _bound_save.loaded.is_connected(_on_loaded):
		_bound_save.loaded.disconnect(_on_loaded)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _shortcut_input(event: InputEvent) -> void:
	if not is_open():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()
	elif hints == null and event.is_action_pressed(Hints.ACTION):
		if not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed):
			close()
			get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible and _panel.visible


func sheet() -> Control:
	return _panel


func auto_hints_button() -> Button:
	return _auto_hints


func close_button() -> Button:
	return _close_btn


func guide_tab_button() -> Button:
	return _guide_tab


func past_calls_tab_button() -> Button:
	return _calls_tab


func active_tab() -> Tab:
	return _tab


func card_titles() -> PackedStringArray:
	var out := PackedStringArray()
	for card in _cards.get_children():
		var lbl := card.find_child("CardTitle", false, false)
		if lbl == null:
			lbl = card.find_child("CardTitle", true, false)
		if lbl is Label:
			out.append((lbl as Label).text)
	return out


func card_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for card in _cards.get_children():
		var lbl := card.find_child("CardBody", true, false) as Label
		if lbl != null:
			out.append(lbl.text)
	return out


func open() -> void:
	_resolve_refs()
	_bind_save()
	TopRow.close_others(self)
	visible = true
	_panel.visible = true
	sync_auto_hints(hints.is_enabled() if hints != null else true)
	_rebuild_content()
	TopRow.place_sheet(_panel, self)
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()


func close() -> void:
	if not visible and not _panel.visible:
		return
	visible = false
	_panel.visible = false


func select_tab(tab: Tab) -> void:
	_tab = tab
	_sync_tab_buttons()
	if is_open():
		_rebuild_content()
		_fit_scroll_height()
		_fit_scroll_height.call_deferred()


func sync_auto_hints(enabled: bool) -> void:
	_auto_hints.set_pressed_no_signal(enabled)
	_sync_auto_hints_label(enabled)


func _build() -> void:
	_panel.name = "HelpPanel"
	_panel.theme = BuildMenu.HUD_THEME
	_panel.theme_type_variation = &"HudTopCard"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	var header := HBoxContainer.new()
	header.name = "HelpHeader"
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	_title.name = "HelpTitle"
	_title.text = tr("Help & Hints")
	_title.theme_type_variation = &"HudTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_auto_hints.name = "AutoHintsToggle"
	_auto_hints.toggle_mode = true
	_auto_hints.focus_mode = Control.FOCUS_NONE
	_auto_hints.theme_type_variation = &"HudButtonTeal"
	_auto_hints.toggled.connect(_on_auto_hints_toggled)
	header.add_child(_auto_hints)

	_close_btn.name = "HelpClose"
	_close_btn.text = tr("X")
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.theme_type_variation = &"HudButtonCompact"
	_close_btn.custom_minimum_size = Vector2(34.0, 32.0)
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	var tabs := HBoxContainer.new()
	tabs.name = "HelpTabs"
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)

	_guide_tab.name = "GuideTab"
	_guide_tab.text = tr("Guide")
	_guide_tab.toggle_mode = true
	_guide_tab.focus_mode = Control.FOCUS_NONE
	_guide_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_tab.pressed.connect(select_tab.bind(Tab.GUIDE))
	tabs.add_child(_guide_tab)

	_calls_tab.name = "PastCallsTab"
	_calls_tab.text = tr("Past Calls")
	_calls_tab.toggle_mode = true
	_calls_tab.focus_mode = Control.FOCUS_NONE
	_calls_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_calls_tab.pressed.connect(select_tab.bind(Tab.PAST_CALLS))
	tabs.add_child(_calls_tab)

	_scroll.name = "HelpScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_cards.name = "HelpCards"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 8)
	_cards.sort_children.connect(_fit_scroll_height)
	_scroll.add_child(_cards)

	_sync_tab_buttons()
	_rebuild_content()


func _retranslate() -> void:
	_title.text = tr("Help & Hints")
	_close_btn.text = tr("X")
	_guide_tab.text = tr("Guide")
	_calls_tab.text = tr("Past Calls")
	_sync_auto_hints_label(_auto_hints.button_pressed)
	_rebuild_content()
	if is_open():
		_fit_scroll_height()


func _sync_auto_hints_label(enabled: bool) -> void:
	_auto_hints.text = tr("Auto-hints: On") if enabled else tr("Auto-hints: Off")


func _sync_tab_buttons() -> void:
	var on_guide := _tab == Tab.GUIDE
	_guide_tab.set_pressed_no_signal(on_guide)
	_calls_tab.set_pressed_no_signal(not on_guide)
	_guide_tab.theme_type_variation = &"HudButtonTeal" if on_guide else &"HudButtonCompact"
	_calls_tab.theme_type_variation = &"HudButtonCompact" if on_guide else &"HudButtonTeal"


func _on_auto_hints_toggled(enabled: bool) -> void:
	_sync_auto_hints_label(enabled)
	if hints != null:
		hints.set_enabled(enabled)


func _on_viewport_resized() -> void:
	if is_open():
		TopRow.place_sheet(_panel, self)
		_fit_scroll_height()


func _on_loaded(ok: bool) -> void:
	if ok:
		close()


func _resolve_refs() -> void:
	if hints == null:
		return
	var hud := hints.hud
	if hud != null:
		if unlocks == null and hud.build_mode != null:
			unlocks = hud.build_mode.unlocks
		if flights == null:
			flights = hud.flights
		if save_game == null:
			save_game = hud.save_game


func _bind_save() -> void:
	if save_game == _bound_save:
		return
	if is_instance_valid(_bound_save) and _bound_save.loaded.is_connected(_on_loaded):
		_bound_save.loaded.disconnect(_on_loaded)
	_bound_save = save_game
	if is_instance_valid(_bound_save) and not _bound_save.loaded.is_connected(_on_loaded):
		_bound_save.loaded.connect(_on_loaded)


func _rebuild_content() -> void:
	_body_labels.clear()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.free()
	var entries := _guide_entries() if _tab == Tab.GUIDE else _past_call_entries()
	for entry in entries:
		_cards.add_child(_make_card(entry["title"], entry["body"]))
	_scroll.scroll_vertical = 0


func _make_card(title_text: String, body_text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudSubCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var heading := Label.new()
	heading.name = "CardTitle"
	heading.text = title_text
	heading.theme_type_variation = &"HudCardName"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(heading)
	var body := Label.new()
	body.name = "CardBody"
	body.text = body_text
	body.theme_type_variation = &"HudSmall"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	_body_labels.append(body)
	return card


func _guide_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{
			"title": tr("Opening & Staffing"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Build a Check-in Desk, Security Scanner, and Gate Desk, then hire at least one Check-in Agent and Security Officer from Staff. Your airport opens once staff reach their posts."
			),
		},
		{
			"title": tr("Building & Smart-Build"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Drag to lay Floor, Walls, or Rooms, or pick a Smart-Build room to stamp a ready layout. Press R to rotate before placing, Ctrl+Z to undo, or Remove to refund built items."
			),
		},
		{
			"title": tr("Airline Offers & Planner"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Open Offers at the top to review airline contracts and charter flights. Check whether an offer fits your gates before accepting, and open Planner (P) to inspect schedules or move flights."
			),
		},
		{
			"title": tr("Security & Baggage"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Security Lanes clear queues faster than single scanners. Connect the back of Check-in Desks to a Bag Room with Belts and Carts, and build a Baggage Claim room for arrivals."
			),
		},
		{
			"title": tr("Arrivals & Pickup"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Place Curb Bays and a Surface Lot outside the terminal so taxis and cars drop off and pick up passengers without blocking road traffic."
			),
		},
		{
			"title": tr("Controls & Shortcuts"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"WASD / Arrows: pan camera   Q / E: rotate   Wheel: zoom   Space: pause   Shift+1/2/3: speed   B: Departures   P: Planner   M: Mood   H: Help & Hints   Esc: close or menu."
			),
		},
	]
	var tier := unlocks.tier() if unlocks != null else BuildUnlocks.START_TIER
	var unlock_lines := PackedStringArray(
		[tr("Tier 1 (Start): check-in, security, gate desk, seats, toilets, land.")]
	)
	for t in range(BuildUnlocks.CAFE_TIER, tier + 1):
		var family_lines := UnlockFamilies.lines([t])
		if not family_lines.is_empty():
			unlock_lines.append(
				tr("Tier {tier}: {items}").format({"tier": t, "items": " ".join(family_lines)})
			)
	(
		entries
		. append(
			{
				"title": tr("Unlocked Tiers (Tier {tier})").format({"tier": tier}),
				"body": "\n".join(unlock_lines),
			}
		)
	)
	return entries


func _past_call_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{
			"title": tr("Terminal Manager · Your first day at the airport"),
			"body":
			tr(
				# gdlint:ignore = max-line-length
				"Welcome aboard! Build a check-in desk, scanner, and gate from Operations. Hire staff to open the terminal."
			),
		},
	]
	if unlocks != null:
		if unlocks.first_shown(BigFirsts.OPENING):
			(
				entries
				. append(
					{
						"title": tr("Gotta Air · Station manager"),
						"body": BigFirsts.body_for([BigFirsts.OPENING]),
					}
				)
			)
		if unlocks.first_shown(BigFirsts.RUNWAY):
			(
				entries
				. append(
					{
						"title":
						tr("{speaker} · {title}").format(
							{"speaker": tr("Terminal Manager"), "title": BigFirsts.title_text()}
						),
						"body": BigFirsts.body_for([BigFirsts.RUNWAY]),
					}
				)
			)
		if unlocks.first_shown(BigFirsts.INCIDENT):
			(
				entries
				. append(
					{
						"title":
						tr("{speaker} · {title}").format(
							{"speaker": tr("Terminal Manager"), "title": BigFirsts.title_text()}
						),
						"body": BigFirsts.body_for([BigFirsts.INCIDENT]),
					}
				)
			)
		for t in range(BuildUnlocks.CAFE_TIER, BuildUnlocks.TIERS.size() + 1):
			if unlocks.dialog_shown(t):
				var lines := UnlockFamilies.lines([t])
				var body := (
					"\n".join(lines) if not lines.is_empty() else tr("New facilities unlocked.")
				)
				(
					entries
					. append(
						{
							"title":
							tr("Terminal Manager · Tier {tier} unlocked").format({"tier": t}),
							"body": body,
						}
					)
				)
	if hints != null:
		var seen_tips := PackedStringArray()
		for id in HintRules.IDS:
			if hints.is_seen(id):
				seen_tips.append("• " + HintRules.text(id))
		if not seen_tips.is_empty():
			entries.append({"title": tr("Tips Seen"), "body": "\n".join(seen_tips)})
	return entries


func _fit_scroll_height() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var vp_size := viewport.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var extent := TopRow.sheet_extent(vp_size.x, TopRow.sheet_min_left(get_tree()))
	var sheet_w := extent.y if extent.y > 0.0 else DEFAULT_WIDTH
	var text_w := maxf(200.0, sheet_w - 64.0)
	for lbl in _body_labels:
		if is_instance_valid(lbl):
			lbl.custom_minimum_size.x = text_w
	var content_h := _cards.get_combined_minimum_size().y
	var chrome := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var bottom_clear := float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	var max_scroll_h := maxf(MIN_SCROLL_H, vp_size.y - TopRow.SHEET_TOP - bottom_clear - chrome)
	var wanted := minf(maxf(content_h, 120.0), max_scroll_h)
	var changed := (
		not is_equal_approx(_scroll.custom_minimum_size.y, wanted)
		or not is_equal_approx(_panel.custom_minimum_size.x, sheet_w)
		or not is_equal_approx(_panel.offset_left, extent.x)
	)
	if changed:
		_scroll.custom_minimum_size.y = wanted
		TopRow.place_sheet(_panel, self)
		_panel.custom_minimum_size.x = sheet_w
		_panel.reset_size()
