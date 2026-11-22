class_name FlightPlanner
extends CanvasLayer
## The flight planner (decision flight-planner-a-full-screen-day-planner-with-
## one-row-per-ga, slice 1: view, then Move or End). A "Planner (P)" button on
## the left column's Departures row, and the P key, open a full-screen cream
## sheet over the game: one row per gate (FlightPlannerModel) with the gate's
## colour on its header, 24 hour columns, and a bar in the gate's colour for each
## flight, spanning its gate hold from the first state to DEPARTED, with a navy
## tick where the flight leaves. A coral line marks the clock on today's day.
## The bar is cut at midnight where the hold crosses it.
##
## Clicking a bar of a running contract selects it and opens, under the grid,
## the Move to / End choices the Departures list has: the same gates, the same
## words, the same FlightSim calls (DeparturesBoard.move_choices, move_outcome,
## end_outcome). Slice 2: a bar can also be dragged (PlannerBar) onto another
## gate row (PlannerTrack). A PlannerDrag child greys the rows FlightSim refuses
## and puts the reasons in the message line while it is dragged; a drop goes
## through move_outcome like a Move to choice. Departure times never change here. A bar
## of a one-off flight or an ended contract cannot be selected or dragged.
##
## The sheet pauses the game while open, as the Offers sheet does (decision
## the-airline-offers-panel-pauses-the-game-while-it-is-open): a hold on the
## clock's ClockHolds taken in the exclusive-dialog line, released on close; the
## player resuming or picking a speed runs the game under the sheet. It joins
## TopRow.SHEET_GROUP, so opening the Offers or Runway sheet closes it and the
## reverse. It closes on Esc, on P, on its Close button, on a build tool pick
## and when a save loads. While open it follows FlightSim.planning_changed
## (checked every frame, since gates change while paused), occurrence_added,
## contract_ended and the day turning over.

## The input action for the toggle key, bound to P in project.godot.
const ACTION := &"toggle_flight_planner"
const HOTKEY := "P"
## One above the Offers and Runway sheets (TopRow.SHEET_LAYER), so their buttons
## do not draw over the full-screen sheet; dialogs (layer 10) stay above it.
const LAYER := TopRow.SHEET_LAYER + 1
## The gate header's width, in layout pixels.
const HEAD_W := 80.0
const ROW_H := 44.0
## Pixels kept clear between a bar's label and its departure tick.
const LABEL_GAP := 6.0
## Meta keys on a bar button: its "HH:MM  Destination" text, and the destination
## alone that replaces it when the room before the departure tick is too tight.
const FULL_TEXT := &"full_text"
const SHORT_TEXT := &"short_text"
## The child Label that draws the text of a bar with a departure tick.
const BAR_LABEL := "BarLabel"
## The Label variation a disabled bar's label takes: the gate buttons' disabled text.
const DISABLED_LABEL := &"HudBarLabelDisabled"
const HOURS := 24
## The toggle's x while the Departures toggle fits its grid slot; a wider one
## pushes it right (LeftColumn.right_of).
const TOGGLE_LEFT := float(HudLayout.MARGIN + HudLayout.TOGGLE_W + HudLayout.GAP)

@export var flights: FlightSim
## Paused while the sheet is open; null leaves the clock alone.
@export var clock: SimClock
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode

var _toggle := Button.new()
var _sheet := PanelContainer.new()
var _day_label := Label.new()
var _hours := Control.new()
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _summary := Label.new()
var _actions := HBoxContainer.new()
var _message := Label.new()
var _tracks: Array[PlannerTrack] = []
## What the grid shows now, so it is rebuilt only when it changes.
var _shown: Array[Dictionary] = []
var _shown_day := -1
var _dirty := true
## The selected bar: its contract id and departure day, "" for none.
var _selected := ""
var _selected_day := -1
var _confirming := false
var _hold := ClockHolds.NONE
var _rebuilds := 0
## Greys the rows while a bar is dragged and carries out the drop.
var _drag := PlannerDrag.new()


func _ready() -> void:
	name = "FlightPlanner"
	layer = LAYER
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	_drag.name = "PlannerDrag"
	_drag.flights = flights
	_drag.message = _message
	_drag.sheet = _sheet
	_drag.tracks = _tracks
	_drag.on_drop = _on_move_pressed
	add_child(_drag)
	if flights != null:
		flights.planning_changed.connect(_mark_dirty)
		flights.occurrence_added.connect(_on_flight_event)
		flights.contract_ended.connect(_on_flight_event)
		flights.snapshot_loaded.connect(_on_snapshot_loaded)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	_toggle.text = tr("Planner ({key})").format({"key": HOTKEY})
	var title := _sheet.find_child("PlannerTitle", true, false) as Label
	if title != null:
		title.text = tr("Flight planner")
	var close_btn := _sheet.find_child("PlannerClose", true, false) as Button
	if close_btn != null:
		close_btn.text = tr("Close")
	if _selected == "":
		_summary.text = _hint_text()
	refresh()


func _process(_delta: float) -> void:
	_toggle.position.x = LeftColumn.right_of(
		get_tree(), LeftColumn.DEPARTURES_TOGGLE_GROUP, TOGGLE_LEFT
	)
	if not _sheet.visible or flights == null:
		return
	flights.check_planning_changed()
	_refresh()


## P toggles; a held key's repeats and modified presses are left alone.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not event.is_action_pressed(ACTION):
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	if not key.echo:
		_on_toggle()
	get_viewport().set_input_as_handled()


## Esc closes the sheet and is not passed on, so it does not also drop a tool.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _sheet.visible


func sheet() -> Control:
	return _sheet


func toggle_button() -> Button:
	return _toggle


## Pauses the clock and shows the sheet, at once or, while another exclusive
## dialog has the turn, when that one closes.
func open() -> void:
	if _sheet.visible or _is_waiting():
		return
	if clock == null:
		_show()
		return
	# Another top-row sheet holds the exclusive turn until it closes, so it is
	# closed first; the turn then comes at once.
	TopRow.close_others(self)
	_hold = clock.holds.take_turn(self, _show, true)


## Hides the sheet, or stops it waiting to show, and releases its hold.
func close() -> void:
	_toggle.set_pressed_no_signal(false)
	if _is_waiting():
		_release_clock()
		return
	if not _sheet.visible:
		return
	_sheet.visible = false
	_deselect()
	_release_clock()


## A planner that leaves the tree while open must not leave the game paused.
func _exit_tree() -> void:
	_release_clock()


## The gates drawn, top to bottom.
func row_gates() -> Array[String]:
	var gates: Array[String] = []
	for row in _shown:
		gates.append(row["gate"])
	return gates


## The bar of `contract_id` leaving on `day`, or null.
func bar_button(contract_id: String, day: int) -> Button:
	return _sheet.find_child("Bar_%s_%d" % [contract_id, day], true, false) as Button


## Every bar drawn, in row order.
func bar_buttons() -> Array[Button]:
	var bars: Array[Button] = []
	for track in _tracks:
		for child in track.get_children():
			if child is Button:
				bars.append(child)
	return bars


## The named part of the sheet (GateHead_A, Track_A, Move_C, EndContract,
## EndPrompt, ConfirmEnd, KeepContract, PlannerClose), or null.
func part(part_name: String) -> Control:
	return _sheet.find_child(part_name, true, false) as Control


func summary_text() -> String:
	return _summary.text


func message_text() -> String:
	return _message.text


func selected_contract() -> String:
	return _selected


## The day the grid shows: the clock's.
func shown_day() -> int:
	return _shown_day


## How many times the grid was rebuilt, for tests.
func rebuild_count() -> int:
	return _rebuilds


## Draws the grid again now.
func refresh() -> void:
	_dirty = true
	_refresh()


func _build() -> void:
	_toggle.name = "PlannerToggle"
	_toggle.text = tr("Planner ({key})").format({"key": HOTKEY})
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.theme = BuildMenu.HUD_THEME
	_toggle.position = Vector2(TOGGLE_LEFT, LeftColumn.slot_top(LeftColumn.SLOT_DEPARTURES))
	_toggle.add_to_group(LeftColumn.PLANNER_TOGGLE_GROUP)
	_toggle.custom_minimum_size = Vector2(
		HudLayout.LIST_W - HudLayout.TOGGLE_W - HudLayout.GAP, HudLayout.BUTTON_H
	)
	_toggle.size = _toggle.custom_minimum_size
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)
	_sheet.name = "PlannerSheet"
	_sheet.theme = BuildMenu.HUD_THEME
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_sheet.set_offset(side, HudLayout.MARGIN if side < 2 else -HudLayout.MARGIN)
	add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_sheet.add_child(column)
	column.add_child(_build_header())
	var hour_row := HBoxContainer.new()
	hour_row.add_theme_constant_override("separation", 4)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(HEAD_W, 0.0)
	hour_row.add_child(pad)
	_hours.name = "Hours"
	_hours.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hours.custom_minimum_size = Vector2(0.0, 18.0)
	for hour in range(HOURS):
		var label := Label.new()
		label.text = "%02d" % hour
		label.theme_type_variation = &"HudHint"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anchor_at(label, float(hour) / HOURS, 3.0)
		_hours.add_child(label)
	hour_row.add_child(_hours)
	column.add_child(hour_row)
	_scroll.name = "PlannerScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.name = "GateRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	_scroll.add_child(_rows)
	column.add_child(_scroll)
	_summary.name = "PlannerSummary"
	_summary.text = _hint_text()
	_summary.theme_type_variation = &"HudSmall"
	# A longer translation wraps instead of widening the sheet past the window.
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)
	_actions.name = "PlannerActions"
	_actions.add_theme_constant_override("separation", 6)
	column.add_child(_actions)
	_message.name = "PlannerMessage"
	_message.theme_type_variation = &"HudHint"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "PlannerTitle"
	title.text = tr("Flight planner")
	title.theme_type_variation = &"HudTitle"
	header.add_child(title)
	_day_label.name = "PlannerDay"
	_day_label.theme_type_variation = &"HudHint"
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_day_label)
	var close_btn := Button.new()
	close_btn.name = "PlannerClose"
	close_btn.text = tr("Close")
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	return header


## Puts `control` at `fraction` of its parent's width, `inset` px to the right.
static func _anchor_at(control: Control, fraction: float, inset: float) -> void:
	control.anchor_left = fraction
	control.anchor_right = fraction
	control.offset_left = inset
	control.offset_right = inset + 40.0


func _on_toggle() -> void:
	if _sheet.visible or _is_waiting():
		close()
	else:
		open()


## The sheet's turn: it shows.
func _show() -> void:
	TopRow.close_others(self)
	_sheet.visible = true
	_toggle.set_pressed_no_signal(true)
	if flights != null:
		flights.check_planning_changed()
	refresh()


func _is_waiting() -> bool:
	return not _sheet.visible and is_instance_valid(clock) and clock.holds.has(_hold)


## Nothing is restored: with no hold left, the player's own pause applies.
func _release_clock() -> void:
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE


func _mark_dirty() -> void:
	_dirty = true


func _on_flight_event(_id: String) -> void:
	_dirty = true


## A load replaces the world the sheet was opened over, so it closes.
func _on_snapshot_loaded() -> void:
	close()
	_dirty = true


func _on_tool_changed(_tool: BuildMode.Tool) -> void:
	close()


## Redraws the grid when something it shows changed; moves the clock line.
func _refresh() -> void:
	if flights == null or clock == null:
		return
	var day := GameCalendar.day_of(clock.tick, clock.epoch)
	var rows := FlightPlannerModel.rows_for_day(flights, day)
	if _dirty or day != _shown_day or rows != _shown:
		_dirty = false
		_shown = rows
		_shown_day = day
		_rebuild()
	var now := float(GameCalendar.tick_of_day(clock.tick, clock.epoch)) / GameCalendar.TICKS_PER_DAY
	for each in _tracks:
		each.now = now


func _rebuild() -> void:
	_rebuilds += 1
	_day_label.text = tr("Day {day}", "calendar day").format({"day": _shown_day + 1})
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_tracks.clear()
	if _shown.is_empty():
		var empty := Label.new()
		empty.name = "PlannerEmpty"
		empty.text = tr("No gate has a stand yet, so there is nothing to plan.")
		_rows.add_child(empty)
	for row in _shown:
		_add_row(row)
	_drag.show_rows()
	if _selected != "" and _selected_bar().is_empty():
		_deselect()
	_show_actions()


func _add_row(row: Dictionary) -> void:
	var gate_id: String = row["gate"]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	var head := PanelContainer.new()
	head.name = "GateHead_%s" % gate_id
	head.custom_minimum_size = Vector2(HEAD_W, ROW_H)
	var box := StyleBoxFlat.new()
	box.bg_color = row["colour"]
	box.set_corner_radius_all(6)
	box.set_border_width_all(2)
	box.border_color = GateColours.TEXT
	head.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = tr("Gate {gate}", "gate name").format({"gate": gate_id})
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", GateColours.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(label)
	line.add_child(head)
	var lane := PlannerTrack.new()
	lane.name = "Track_%s" % gate_id
	lane.gate = gate_id
	_drag.watch(lane)
	lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lane.custom_minimum_size = Vector2(0.0, ROW_H)
	line.add_child(lane)
	_tracks.append(lane)
	for bar: Dictionary in row["bars"]:
		lane.add_child(_make_bar(bar))
	_rows.add_child(line)


func _make_bar(bar: Dictionary) -> Button:
	var button := PlannerBar.new()
	button.contract = bar["contract"]
	button.day = bar["day"]
	button.gate = bar["gate"]
	var key: String = bar["contract"] if bar["contract"] != "" else bar["flight"]
	button.name = "Bar_%s_%d" % [key, bar["day"]]
	button.text = bar["label"]
	button.set_meta(FULL_TEXT, bar["label"])
	button.set_meta(SHORT_TEXT, bar["place"])
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	var selected: bool = bar["contract"] == _selected and bar["day"] == _selected_day
	button.theme_type_variation = GateColours.variation_of(bar["gate"], selected)
	button.disabled = not bar["active"]
	button.anchor_left = bar["from"]
	button.anchor_right = bar["to"]
	button.anchor_top = 0.0
	button.anchor_bottom = 1.0
	button.offset_top = 4.0
	button.offset_bottom = -4.0
	button.tooltip_text = _bar_tooltip(bar)
	if bar["active"]:
		button.pressed.connect(_on_bar_pressed.bind(bar["contract"], bar["day"]))
	_add_departure_tick(button, bar)
	return button


## "Oslo  Gotta Air: gate A 07:47 to 11:02". The hold runs from the first state to
## DEPARTED; the tick on the bar is the departure.
func _bar_tooltip(bar: Dictionary) -> String:
	var airline := "" if bar["airline"] == "" else "  %s" % bar["airline"]
	return (
		tr("{label}{airline}\nGate {gate}, held {from} to {to}")
		. format(
			{
				"label": bar["label"],
				"airline": airline,
				"gate": bar["gate"],
				"from": GameCalendar.clock_text(bar["start"], clock.epoch),
				"to": GameCalendar.clock_text(bar["end"], clock.epoch),
			}
		)
	)


## A navy line across the bar where the flight leaves, when that is on the day.
func _add_departure_tick(button: Button, bar: Dictionary) -> void:
	var span := float(bar["end"] - bar["start"])
	var at := float(bar["departure"] - bar["start"]) / span
	var visible_from := float(maxi(bar["start"], _day_start()) - bar["start"]) / span
	var visible_to := (
		float(mini(bar["end"], _day_start() + GameCalendar.TICKS_PER_DAY) - bar["start"]) / span
	)
	if at < visible_from or at > visible_to:
		return
	var local := (at - visible_from) / (visible_to - visible_from)
	var tick := ColorRect.new()
	tick.name = "DepartureTick"
	tick.color = GateColours.TEXT
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.anchor_left = local
	tick.anchor_right = local
	tick.anchor_top = 0.0
	tick.anchor_bottom = 1.0
	tick.offset_left = -2.0
	tick.offset_right = 0.0
	button.add_child(tick)
	var label := Label.new()
	label.name = BAR_LABEL
	label.text = button.text
	button.accessibility_name = button.text
	button.text = ""
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if button.disabled:
		label.theme_type_variation = DISABLED_LABEL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.anchor_left = 0.0
	label.anchor_right = local
	label.anchor_top = 0.0
	label.anchor_bottom = 1.0
	label.offset_right = -LABEL_GAP
	button.add_child(label)
	button.resized.connect(_keep_label_clear.bind(button, label))


## The label child of a bar that carries a departure tick, or null for a bar
## without one (its text is the button's own).
static func bar_label(bar: Button) -> Label:
	return bar.find_child(BAR_LABEL, false, false) as Label


## The text a bar shows: its label's when it has one, else the button's.
static func bar_text(bar: Button) -> String:
	var label := bar_label(bar)
	return bar.text if label == null else label.text


## Ends the label's room a few pixels before the departure tick (the label's right
## anchor sits at the tick and LABEL_GAP stops it short), so the text never runs
## through the tick. The label is a child of the bar, not the button's own text,
## so no per-bar margin is written into the HudGate theme StyleBoxes that every
## button of that gate colour shares. The label takes its look from the theme, with
## no per-node override: the Label type resolves to the same font, size and navy as a
## gate button, and on a disabled bar the DISABLED_LABEL variation gives it the gate
## button's softer disabled text. The text is the full "HH:MM  Destination" while
## that fits before the tick; when it does not, the time goes (the tick already shows
## it) and the destination stays, trimmed with an ellipsis only if even that does
## not fit.
static func _keep_label_clear(button: Button, label: Label) -> void:
	var left := button.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)
	label.offset_left = left
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var room := button.size.x * label.anchor_right - LABEL_GAP - left
	var full: String = button.get_meta(FULL_TEXT)
	var text := (
		(
			full
			if font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room
			else button.get_meta(SHORT_TEXT)
		)
		as String
	)
	if label.text != text:
		label.text = text


func _day_start() -> int:
	return GameCalendar.day_start(_shown_day, clock.epoch)


func _on_bar_pressed(contract_id: String, day: int) -> void:
	var was_open := _selected == contract_id and _selected_day == day
	_deselect()
	_message.text = ""
	if not was_open:
		_selected = contract_id
		_selected_day = day
	_dirty = true
	_refresh()


func _deselect() -> void:
	_selected = ""
	_selected_day = -1
	_confirming = false


## The selected bar's dictionary, or {} when it is not drawn any more.
func _selected_bar() -> Dictionary:
	for row in _shown:
		for bar: Dictionary in row["bars"]:
			if bar["contract"] == _selected and bar["day"] == _selected_day and bar["active"]:
				return bar
	return {}


## The line under the sheet while no flight is selected.
func _hint_text() -> String:
	return tr(
		# gdlint:ignore = max-line-length
		"Click a flight to move it or end its contract, or drag it to another gate. Days already issued keep their gate."
	)


## The summary line and the Move to / End choices for the selected bar.
func _show_actions() -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	var bar := _selected_bar() if _selected != "" else {}
	if bar.is_empty():
		_summary.text = _hint_text()
		return
	_summary.text = tr("{label}  Gate {gate}", "gate name").format(
		{"label": bar["label"], "gate": bar["gate"]}
	)
	if _confirming:
		_add_end_confirm()
		return
	_add_move_choices(bar)
	var end := Button.new()
	end.name = "EndContract"
	end.text = tr("End", "button: end the contract")
	end.tooltip_text = tr("End this airline contract")
	end.focus_mode = Control.FOCUS_NONE
	end.pressed.connect(_on_end_pressed)
	_actions.add_child(end)


func _add_move_choices(bar: Dictionary) -> void:
	var gates := flights.gate_ids()
	var choices := DeparturesBoard.move_choices(flights, bar["contract"], gates)
	var fitting: Array[String] = choices["fitting"]
	var note := Label.new()
	note.name = "MoveNote"
	if fitting.is_empty():
		note.text = (
			tr("No other gate fits this flight")
			if choices["any_other"]
			else tr("No other gate exists")
		)
		note.theme_type_variation = &"HudHint"
	else:
		note.text = tr("Move to:")
	_actions.add_child(note)
	for gate_id in fitting:
		var choice := Button.new()
		choice.name = "Move_%s" % gate_id
		choice.text = gate_id
		choice.focus_mode = Control.FOCUS_NONE
		choice.pressed.connect(_on_move_pressed.bind(bar["contract"], gate_id))
		_actions.add_child(choice)
		choice.theme_type_variation = GateColours.variation_of(gate_id)


func _add_end_confirm() -> void:
	var prompt := Label.new()
	prompt.name = "EndPrompt"
	prompt.text = DeparturesBoard.end_prompt(flights, _selected)
	_actions.add_child(prompt)
	var confirm := Button.new()
	confirm.name = "ConfirmEnd"
	confirm.text = tr("End contract")
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_end_confirmed)
	_actions.add_child(confirm)
	var keep := Button.new()
	keep.name = "KeepContract"
	keep.text = tr("Keep", "button: keep the contract")
	keep.focus_mode = Control.FOCUS_NONE
	keep.pressed.connect(_on_end_kept)
	_actions.add_child(keep)


## Moves the contract, or says why not. A refusal keeps the choices open.
func _on_move_pressed(contract_id: String, gate_id: String) -> void:
	var outcome := DeparturesBoard.move_outcome(flights, contract_id, gate_id)
	_message.text = outcome["text"]
	_dirty = true
	_refresh()


## Asks "End this contract?", or shows why FlightSim refuses to end it.
func _on_end_pressed() -> void:
	var refusal := DeparturesBoard.end_refusal_words(flights, _selected)
	_message.text = refusal
	_confirming = refusal == ""
	_dirty = true
	_refresh()


func _on_end_confirmed() -> void:
	_message.text = DeparturesBoard.end_outcome(flights, _selected)
	_deselect()
	_dirty = true
	_refresh()


func _on_end_kept() -> void:
	_confirming = false
	_message.text = ""
	_dirty = true
	_refresh()
