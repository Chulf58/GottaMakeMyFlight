class_name AwardsCeremony
extends Node
## Annual Airport Awards Ceremony modal (Stage 3 Pillar 3, decision d5e50843).
## Takes an exclusive non-yielding ClockHolds turn on SimClock when `ceremony_due`
## fires, displays the Year's 5 award categories (Won/Nominated, prizes, and
## free Award Trophy unlock guidance), and releases the hold on Continue or Esc.

signal dialog_changed(open: bool)

const LAYER := 11
const PANEL_W := 600.0

@export var awards: AirportAwards
@export var clock: SimClock
@export var save_game: SaveGame

var _layer: CanvasLayer
var _panel: PanelContainer
var _hold := ClockHolds.NONE
var _queue: Array[Dictionary] = []
var _current_report := {}

var _title_label: Label
var _row_widgets: Array[Dictionary] = []
var _summary_label: Label
var _hint_label: Label
var _continue_button: Button


func _ready() -> void:
	name = "AwardsCeremony"
	bind(awards, clock, save_game)


func _exit_tree() -> void:
	_queue.clear()
	_free_layer(true)
	_release_hold()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_open():
		_populate_texts()


func bind(
	with_awards: AirportAwards, with_clock: SimClock, with_save_game: SaveGame = null
) -> void:
	if awards != null and awards.ceremony_due.is_connected(present):
		awards.ceremony_due.disconnect(present)
	if save_game != null and save_game.loaded.is_connected(_on_save_loaded):
		save_game.loaded.disconnect(_on_save_loaded)
	awards = with_awards
	clock = with_clock
	save_game = with_save_game
	if awards != null and not awards.ceremony_due.is_connected(present):
		awards.ceremony_due.connect(present)
	if save_game != null and not save_game.loaded.is_connected(_on_save_loaded):
		save_game.loaded.connect(_on_save_loaded)


func is_open() -> bool:
	return _layer != null and is_instance_valid(_layer)


func panel() -> PanelContainer:
	return _panel


func continue_button() -> Button:
	return _continue_button


func current_report() -> Dictionary:
	return _current_report.duplicate(true)


## Queues `report` to display on an exclusive ClockHolds turn (or shows immediately
## when no clock is wired or node is outside the tree).
func present(report: Dictionary) -> void:
	if report.is_empty():
		return
	_queue.append(report.duplicate(true))
	_request_turn()


## Closes the open modal, frees its layer, and releases the ClockHolds hold.
func close() -> void:
	if not is_open():
		return
	_free_layer()
	_current_report = {}
	var token := _hold
	_hold = ClockHolds.NONE
	if is_instance_valid(clock):
		clock.holds.release(token)
	dialog_changed.emit(false)
	if not _queue.is_empty():
		_request_turn()


func _request_turn() -> void:
	if is_open() or _queue.is_empty():
		return
	if clock == null or not is_inside_tree():
		_on_turn()
		return
	if clock.holds.has(_hold):
		return
	_hold = clock.holds.take_turn(self, _on_turn, false)
	if not is_open() and _queue.is_empty():
		_release_hold()


func _on_turn() -> void:
	if _queue.is_empty():
		_release_hold()
		return
	var report: Dictionary = _queue.pop_front()
	_show_report(report)


func _show_report(report: Dictionary) -> void:
	_free_layer()
	_current_report = report
	_row_widgets.clear()
	_layer = CanvasLayer.new()
	_layer.name = "AwardsCeremonyLayer"
	_layer.layer = LAYER

	var root := _ModalRoot.new()
	root.name = "Root"
	root.owner_modal = self
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
	_panel.name = "AwardsCeremonyPanel"
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
	column.add_theme_constant_override("separation", 14)
	pad.add_child(column)

	var header := PanelContainer.new()
	header.name = "Header"
	header.theme_type_variation = &"IntroNameplate"
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.theme_type_variation = &"IntroName"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title_label)
	column.add_child(header)

	var card := PanelContainer.new()
	card.name = "CategoriesCard"
	card.theme_type_variation = &"HudSubCard"
	var card_pad := MarginContainer.new()
	card_pad.add_theme_constant_override("margin_left", 16)
	card_pad.add_theme_constant_override("margin_top", 12)
	card_pad.add_theme_constant_override("margin_right", 16)
	card_pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(card_pad)
	var rows_box := VBoxContainer.new()
	rows_box.name = "Categories"
	rows_box.add_theme_constant_override("separation", 8)
	card_pad.add_child(rows_box)

	var cats: Array = _current_report.get("categories", [])
	for cat: Dictionary in cats:
		var row := HBoxContainer.new()
		row.name = "Row_%s" % String(cat.get("id", ""))
		row.add_theme_constant_override("separation", 12)

		var name_lbl := Label.new()
		name_lbl.name = "CategoryName"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var status_lbl := Label.new()
		status_lbl.name = "CategoryStatus"
		status_lbl.custom_minimum_size = Vector2(100.0, 0.0)
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(status_lbl)

		var prize_lbl := Label.new()
		prize_lbl.name = "CategoryPrize"
		prize_lbl.custom_minimum_size = Vector2(84.0, 0.0)
		prize_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(prize_lbl)

		rows_box.add_child(row)
		(
			_row_widgets
			. append(
				{
					"data": cat,
					"name": name_lbl,
					"status": status_lbl,
					"prize": prize_lbl,
				}
			)
		)
	column.add_child(card)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary_label)

	_hint_label = Label.new()
	_hint_label.name = "TrophyHint"
	_hint_label.theme_type_variation = &"HudSmall"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.custom_minimum_size = Vector2(180.0, float(HudLayout.BUTTON_H))
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.pressed.connect(close)
	column.add_child(_continue_button)

	_populate_texts()
	add_child(_layer)
	dialog_changed.emit(true)


func _populate_texts() -> void:
	if _current_report.is_empty():
		return
	var year := int(_current_report.get("year", 1))
	if _title_label != null:
		_title_label.text = tr("Year {year} Airport Awards").format({"year": year})
	for item: Dictionary in _row_widgets:
		var cat: Dictionary = item["data"]
		var won := bool(cat.get("won", false))
		var prize := int(cat.get("prize", 0))
		(item["name"] as Label).text = tr(str(cat.get("title", "")))
		var status_lbl := item["status"] as Label
		status_lbl.text = tr("Won") if won else tr("Nominated")
		if won:
			status_lbl.add_theme_color_override(&"font_color", Color(0.18, 0.56, 0.24, 1.0))
		else:
			status_lbl.remove_theme_color_override(&"font_color")
		var prize_lbl := item["prize"] as Label
		prize_lbl.text = tr("+${amount}").format({"amount": prize}) if won else tr("$0")
	var total_cash := int(_current_report.get("total_cash", 0))
	var trophies := int(_current_report.get("trophies_won", 0))
	if _summary_label != null:
		var summary_fmt := tr_n(
			"Total awarded: +${cash} · {count} Award Trophy unlocked",
			"Total awarded: +${cash} · {count} Award Trophies unlocked",
			trophies
		)
		_summary_label.text = summary_fmt.format({"cash": total_cash, "count": trophies})
	var has_any_trophy := trophies > 0 or (awards != null and awards.trophies_earned() > 0)
	if _hint_label != null:
		_hint_label.text = (
			tr("Place your Award Trophy from the Decor tab for +30 Room Prestige!")
			if has_any_trophy
			else tr("Win a category next year to earn an Award Trophy for +30 Room Prestige!")
		)
	if _continue_button != null:
		_continue_button.text = tr("Continue")


func _on_save_loaded(ok: bool) -> void:
	if not ok:
		return
	var was_open := is_open()
	_queue.clear()
	_current_report = {}
	_free_layer()
	_release_hold()
	if was_open:
		dialog_changed.emit(false)


func _free_layer(immediate := false) -> void:
	var old := _layer
	_layer = null
	_panel = null
	_title_label = null
	_row_widgets.clear()
	_summary_label = null
	_hint_label = null
	_continue_button = null
	if is_instance_valid(old):
		if immediate:
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.free()
		elif not old.is_queued_for_deletion():
			old.queue_free()


func _release_hold() -> void:
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE


class _ModalRoot:
	extends Control

	var owner_modal: AwardsCeremony

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
		if (
			not key.echo
			and (event.is_action_pressed("build_tool_none") or key.keycode == KEY_ESCAPE)
			and owner_modal != null
		):
			get_viewport().set_input_as_handled()
			owner_modal.close()
			return
		get_viewport().set_input_as_handled()


class Words:
	extends RefCounted

	## Category titles inside tr() so POT generation finds them.
	func categories() -> Array[String]:
		return [
			tr("On-Time Champion"),
			tr("Spotless Terminal"),
			tr("Happiest Passengers"),
			tr("Best Hospitality"),
			tr("Airport of the Year"),
		]
