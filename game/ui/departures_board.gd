class_name DeparturesBoard
extends Control
## The departures board (HUD 3/7, decision hud-steal-list-self-clearing-alert-
## cards-money-hover-departu): a panel listing the flights leaving today that
## have not departed and the flights leaving tomorrow, each in time order,
## drawn from the FlightSim's contracts and occurrences. Row text is
## DepartureList's ("07:38  Oslo  Gotta Air  Boarding"), except that today's next departing
## flight (the earliest whose doors have not closed) shows "doors close 10:30",
## the game-clock time its doors close, in place of its status word. Each row
## is two lines (decision departures-list-row-shows-the-airline-on-a-second-
## line, user-ruled 2026-11-12): line 1 has the time, the destination and the
## Gate and End buttons; line 2, small grey text (HudHint), has the airline's
## full name, never trimmed, then the status word, then a soft "N running late"
## when N passengers of that flight are late (LateCount; board 7f89cf1e, decision
## calm-cozy-default-view-quiet-world-detail-on-ask-soft-statio part 4), nothing
## at 0; the "doors close" caption
## goes under line 2 (decision
## flight-panel-the-next-departing-flight-s-row-shows-a-doors-c, moved here by
## top-right-clock-panel-slims-to-day-time-and-speed-flight-row). Each day lists at most
## MAX_ROWS_PER_DAY rows, then "+n more"; a day with none says "None", and
## with nothing on either day the board says EMPTY_TEXT. A header line above
## the rows reads "Made N  Missed N  In terminal N" from the PassengerSim: the
## counts the clock panel used to carry (board 05cf0cf6).
##
## Each row ends in a gate button showing the gate the flight holds (decision
## gates-are-placed-gate-desks-each-desk-links-automatically-to: the gate is
## automatic, and Departures is where the player changes it). Clicking it opens
## a picker under the row listing every other gate the flight fits now
## (FlightSim.reassign_problem() is "": the gate takes its plane, is free at
## its times and has taxi plans for it, Runway R7); choosing one calls
## FlightSim.reassign_gate, which moves the contract's days not yet issued (an
## occurrence already issued keeps its gate, so its row still shows the old
## one). Should the world change between listing and choosing, the refusal is
## shown with FlightSim's own reason under the row, and the picker stays open.
## With no other gate the picker says NO_OTHER_TEXT, and with other gates none
## of which fits, NO_FIT_TEXT. A one-off flight or an ended contract shows
## its gate on a disabled button.
##
## A running contract's row also has an End button (decision end-contract-
## button-in-the-departures-list-lets-the-player-e): it asks "End this
## contract?" under the row, and the confirm calls FlightSim.end_contract_by_player.
## An Exit fee contract within its term asks with its fee instead, "End this
## contract? Exit fee $60" (end_prompt, FlightSim.end_fee; decision odd-hours-
## and-exit-fee-offer-traits-odd-hours-widens-the-dep), and Settlement charges
## it. Flights already booked for today still fly. When FlightSim.end_refusal()
## says ending would leave another flight with no taxi plan, nothing is ended
## and the row says which flight, so the player can move that flight first.
##
## It is an optional piece with an on/off setting, so the HUD can be rolled
## back if it turns into information overload: a toggle button (always
## visible) and the B key show and hide the panel, and the choice is kept in a
## ConfigFile at settings_path, "hud/departures_board", and read back when the
## board is built. On is the default. B is free of the build tool keys 1 to 0,
## the speed keys (Space, Shift+1/2/3) and the camera keys (WASD, Q, E, Home).
##
## While a passenger is inspected the list steps aside for the inspect card
## (step_aside(), decision passenger-inspect-thoughts-recorded-at-sim-outcomes-
## saved-pin-marks-where point 6, user ruling "Card replaces board", which means
## the list: the toggle keeps its column slot, conductor ruling for HUD 7/7);
## B still turns the setting on and off meanwhile, and the list comes back as
## that setting says when the passenger is deselected.

## Emitted when the player clicks a flight row's "N running late" pill.
signal follow_late_requested(flight_id: String)

## The input action for the toggle key, bound to B in project.godot.
const ACTION := &"toggle_departures_board"
## The key the toggle button names, bound in project.godot.
const HOTKEY := "B"
const SETTINGS_PATH := HudFlagSetting.PATH
const SETTING_KEY := "departures_board"
const TODAY_HEADING := "Today"
const TOMORROW_HEADING := "Tomorrow"
const EMPTY_TEXT := "No flights scheduled"
const NONE_TEXT := "None"
const NO_OTHER_TEXT := "No other gate exists"
const NO_FIT_TEXT := "No other gate fits this flight"
const PICKER_LABEL := "Move to:"
## The English msgids. Each is also written as a literal in its tr() call at the
## use site, because the POT extractor reads only literals; tests compare with
## these. The templates take String.format() with the named {placeholders}.
const MOVED_TEXT := "{destination} now uses gate {gate} for the days not yet issued"
const BUSY_TEXT := "Gate {gate} is busy when this flight needs it"
const END_PROMPT := "End this contract?"
const ENDED_TEXT := "{destination} contract ended. Flights already booked still fly"
const END_REFUSED_TEXT := (
	"Can't end this contract: the {time} {airline} flight to {city}" + " would have no taxi plan"
)
const MAX_ROWS_PER_DAY := 5

@export var flights: FlightSim
@export var clock: SimClock
## Where the header's Made / Missed / In terminal counts come from. Setting
## another sim drops the late counts read from the old one.
var passengers: PassengerSim:
	set(value):
		passengers = value
		_late_key = []
## Where the on/off choice is kept; tests point it at a per-process file.
var settings_path := SETTINGS_PATH
## The bar the list stands over, for how much room the column has; unset, the
## bar is taken to leave no room beside it.
var menu: BuildMenu

var _shown := true
## The player's saved on/off setting (false when manually collapsed/hidden).
var _setting := true
## Whether at least one scheduled flight is listed; 0 flights auto-collapses.
var _has_flights := false
## True when the player explicitly expanded the board while 0 flights exist.
var _manual_open := false
## True while the inspect card has the list stepped aside (step_aside()).
var _aside := false
var _toggle := Button.new()
var _panel := PanelContainer.new()
var _counts := Label.new()
var _rows := VBoxContainer.new()
## The rows scroll when the column leaves them less room than they take (_process).
var _scroll := ScrollContainer.new()
## How many times the scroll area's height was changed, for tests.
var _scroll_sets := 0
var _lines := PackedStringArray()
var _entries: Array[Dictionary] = []
## {flight id: passengers running late}, read from the PassengerSim again only
## when _late_signature() changes, so a frame between ticks costs no passenger
## scan. The signature is the sim's revision, not its tick: a snapshot load
## installs fresh Passenger objects at a tick that may equal the one before it
## (load pauses the clock), and the counts must follow it (boards 7f89cf1e,
## 6c08350c).
var _late := {}
var _late_key := []
var _gates: Array[String] = []
## The row key ("contract_day") whose picker is open, and the row key the
## message under it belongs to; both "" for none.
var _picker_key := ""
var _message_key := ""
var _message := ""
## The row key whose "End this contract?" question is open, or "".
var _confirm_key := ""


## The board's lines for the clock at `tick`: "Today" and its rows, then
## "Tomorrow" and its rows; only EMPTY_TEXT when both days are empty.
static func lines_for(sim: FlightSim, tick: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in entries_for(sim, tick):
		lines.append(entry["text"])
	return lines


## What the board draws at `tick`, in order: {kind: "heading" | "text" | "row",
## text}, and for a "row" also {contract, day, gate, key, late}. `late` is
## {flight id: passengers running late} (LateCount.by_flight()); a row's "late"
## is its "N running late" text, "" for none.
static func entries_for(sim: FlightSim, tick: int, late := {}) -> Array[Dictionary]:
	var today := GameCalendar.day_of(tick, sim.epoch)
	var todays := _day_entries(sim, today, true, tick, late)
	var tomorrows := _day_entries(sim, today + 1, false, tick, late)
	var entries: Array[Dictionary] = []
	if todays.is_empty() and tomorrows.is_empty():
		entries.append(
			{"kind": "text", "text": TranslationServer.translate("No flights scheduled")}
		)
		return entries
	entries.append({"kind": "heading", "text": TranslationServer.translate("Today")})
	_append_day(entries, todays)
	entries.append({"kind": "heading", "text": TranslationServer.translate("Tomorrow")})
	_append_day(entries, tomorrows)
	return entries


static func _append_day(entries: Array[Dictionary], day_entries: Array[Dictionary]) -> void:
	if day_entries.is_empty():
		entries.append({"kind": "text", "text": TranslationServer.translate("None")})
	for entry in day_entries:
		entries.append(entry)


## One day's rows in time order, flights that have departed dropped when
## `drop_departed` (today), capped at MAX_ROWS_PER_DAY with a "+n more" entry
## after. On today the next departing flight at `tick` shows its doors time.
static func _day_entries(
	sim: FlightSim, day: int, drop_departed: bool, tick: int, late: Dictionary
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	var all := DepartureList.rows_for_day(sim, day)
	var next := DepartureList.next_departing(all, tick) if drop_departed else {}
	for row in all:
		if not (drop_departed and row["departed"]):
			kept.append(row)
	for row in kept.slice(0, MAX_ROWS_PER_DAY):
		var is_next: bool = row == next
		(
			entries
			. append(
				{
					"kind": "row",
					"text": DepartureList.doors_line(row, sim.epoch) if is_next else row["line"],
					# Line 1 is the time and destination; line 2 the airline and the
					# status word. The doors time of the next flight replaces the
					# status word and is drawn under line 2.
					"head": row["head"],
					"airline": row["airline"],
					"status": "" if is_next else row["status"],
					"doors": DepartureList.doors_text(row, sim.epoch) if is_next else "",
					"late": LateCount.text_for(int(late.get(row["flight"], 0))),
					"flight": row["flight"],
					"contract": row["contract"],
					"day": day,
					"gate": row["gate"],
					"active":
					row["contract"] != "" and sim.active_contract_ids().has(row["contract"]),
					"key": "%s_%d" % [row["contract"], day] if row["contract"] != "" else "",
				}
			)
		)
	if kept.size() > MAX_ROWS_PER_DAY:
		(
			entries
			. append(
				{
					"kind": "text",
					"text":
					TranslationServer.translate("+{count} more").format(
						{"count": kept.size() - MAX_ROWS_PER_DAY}
					),
				}
			)
		)
	return entries


func _ready() -> void:
	name = "DeparturesBoard"
	theme = BuildMenu.HUD_THEME
	# The board's origin is the column's top-left; its toggle is the column's
	# second button and its list opens under the third (LeftColumn).
	position = Vector2(HudLayout.MARGIN, LeftColumn.TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle.name = "DeparturesToggle"
	_toggle.add_to_group(LeftColumn.DEPARTURES_TOGGLE_GROUP)
	_toggle.add_to_group(LeftColumn.TOGGLE_ROW_GROUP)
	_toggle.set_meta(LeftColumn.META_SLOT, LeftColumn.SLOT_DEPARTURES)
	_toggle.text = tr("Departures ({key})").format({"key": HOTKEY})
	LeftColumn.size_toggle(_toggle)
	_toggle.position.y = LeftColumn.slot_top(LeftColumn.SLOT_DEPARTURES) - LeftColumn.TOP
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	add_child(_toggle)
	_panel.name = "DeparturesPanel"
	_panel.custom_minimum_size = Vector2(HudLayout.LIST_W, 0.0)
	_panel.position.y = LeftColumn.list_top(get_tree()) - LeftColumn.TOP
	_panel.add_to_group(LeftColumn.LIST_GROUP)
	add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	_panel.add_child(body)
	_counts.name = "Counts"
	_counts.theme_type_variation = &"HudHint"
	_counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_counts)
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.name = "RowsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_rows)
	body.add_child(_scroll)
	_setting = _load_setting()
	_shown = false
	_has_flights = false
	_manual_open = false
	_apply_shown()
	_toggle.toggled.connect(set_shown)
	if flights != null:
		flights.snapshot_loaded.connect(_on_snapshot_loaded)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	_toggle.text = tr("Departures ({key})").format({"key": HOTKEY})
	_refresh(true)


## Lets the rows scroll in the room the column leaves the list (LeftColumn.
## list_room), so the checklist card under it always has its share and the
## cards never reach the Templates dock, and keeps _panel aligned under any
## visible column buttons.
func _process(_delta: float) -> void:
	_sync_panel_top()
	if not _panel.is_visible_in_tree():
		return
	var bar_w := 0.0 if menu == null else menu.bar().get_combined_minimum_size().x
	var room := LeftColumn.list_room(get_tree(), get_viewport().get_visible_rect().size, bar_w)
	var chrome := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var height := minf(_rows.get_combined_minimum_size().y, maxf(0.0, room - chrome))
	if not is_equal_approx(_scroll.custom_minimum_size.y, height):
		_scroll.custom_minimum_size.y = height
		_panel.reset_size()
		_scroll_sets += 1


func _sync_panel_top() -> void:
	var top := LeftColumn.list_top(get_tree()) - LeftColumn.TOP
	if not is_equal_approx(_panel.position.y, top):
		_panel.position.y = top


## How many times the scroll area's height was set, for tests.
func scroll_sets() -> int:
	return _scroll_sets


## Hides the list while `aside` (PassengerHud, while the inspect card shows)
## and brings it back after, as the setting says; the toggle keeps its column
## slot, and the on/off setting is left as it is.
func step_aside(aside: bool) -> void:
	if aside == _aside:
		return
	_aside = aside
	_apply_shown()


## True while the inspect card has the list stepped aside.
func is_aside() -> bool:
	return _aside


## True while the panel is expanded.
func is_shown() -> bool:
	return _shown


## True while the player's persisted Departures preference is on.
func is_setting_enabled() -> bool:
	return _setting


## Shows or hides the panel and keeps the choice. The toggle button and the
## key both come through here.
func set_shown(value: bool) -> void:
	_setting = value
	_manual_open = value and not _has_flights
	_save_setting()
	if value == _shown:
		return
	_shown = value
	_apply_shown()
	refresh()


## The lines the panel is showing now: empty while it is hidden.
func shown_lines() -> PackedStringArray:
	return _lines


## The gate button on the row of `contract_id` on `day`, or null.
func gate_button(contract_id: String, day: int) -> Button:
	return find_child("Gate_%s_%d" % [contract_id, day], true, false) as Button


## The End button on the row of `contract_id` on `day`, or null.
func end_button(contract_id: String, day: int) -> Button:
	return find_child("End_%s_%d" % [contract_id, day], true, false) as Button


## The clickable "N running late" pill on `flight_id`'s row, or null.
func late_button(flight_id: String) -> Button:
	return find_child("Late_%s" % flight_id, true, false) as Button


## The confirm button of the open "End this contract?" question, or null.
func confirm_end_button() -> Button:
	return find_child("ConfirmEnd", true, false) as Button


## The Keep button of the open "End this contract?" question, or null.
func keep_button() -> Button:
	return find_child("KeepContract", true, false) as Button


## The button for `gate_id` in the open picker, or null.
func picker_button(gate_id: String) -> Button:
	return find_child("Pick_%s" % gate_id, true, false) as Button


## The text of the open picker's note ("No other gate exists" when it has no
## choice), or "" while no picker is open.
func picker_note() -> String:
	var note := find_child("PickerNote", true, false) as Label
	return note.text if note != null else ""


## The refusal or confirmation shown under a row, or "".
func message_text() -> String:
	return _message


## Refills the rows from the FlightSim and the clock when they changed. A
## hidden board reads nothing. Rows are rebuilt only when what they show (the
## text, the gates or the open picker) changes.
func refresh() -> void:
	_refresh(false)


## "Made 3  Missed 1  In terminal 12", or "" while no PassengerSim is set.
func counts_text() -> String:
	if passengers == null:
		return ""
	return (
		tr("Made {made}  Missed {missed}  In terminal {active}")
		. format(
			{
				"made": passengers.made_count(),
				"missed": passengers.missed_count(),
				"active": passengers.active_count(),
			}
		)
	)


## Passengers of `flight_id` running late as of the last refresh.
func late_count_of(flight_id: String) -> int:
	return int(_late.get(flight_id, 0))


func _late_counts() -> Dictionary:
	if passengers == null:
		return {}
	var key := _late_signature()
	if key != _late_key:
		_late_key = key
		_late = LateCount.by_flight(passengers)
	return _late


## What identifies the passenger state the late counts were read from: the sim
## and its revision, an O(1) read that holds no passenger scan. The revision
## moves on every tick, spawn, stage change, outcome and snapshot load, so a
## load at the same tick, or a change inside one tick, moves the signature.
func _late_signature() -> Array:
	return [passengers.get_instance_id(), passengers.revision]


## True when `entries` lists at least one flight row (not empty).
static func entries_have_flights(entries: Array[Dictionary]) -> bool:
	for entry in entries:
		if entry["kind"] == "row":
			return true
	return false


func _refresh(force: bool) -> void:
	if flights == null or clock == null:
		return
	var entries := entries_for(flights, clock.tick, _late_counts())
	var has_flights := entries_have_flights(entries)
	if has_flights != _has_flights:
		_has_flights = has_flights
		if has_flights:
			_manual_open = false
			if _setting and not _shown:
				_shown = true
				_apply_shown()
		elif not _manual_open and _shown:
			_shown = false
			_apply_shown()
	if not _shown:
		return
	_counts.text = counts_text()
	_counts.visible = passengers != null
	var gates := flights.gate_ids()
	if not force and entries == _entries and gates == _gates:
		return
	_entries = entries
	_gates = gates
	if (_picker_key != "" or _confirm_key != "") and not _open_row_live():
		_close_picker()
	_lines = PackedStringArray()
	for entry in entries:
		_lines.append(entry["text"])
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry in entries:
		if entry["kind"] == "row":
			_add_row(entry)
		else:
			var label := Label.new()
			label.text = entry["text"]
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if entry["kind"] == "heading":
				label.theme_type_variation = &"HudHint"
			_rows.add_child(label)


## True while the row of the open picker or question is listed and its
## contract still runs.
func _open_row_live() -> bool:
	var open_key := _picker_key if _picker_key != "" else _confirm_key
	for entry in _entries:
		if entry["kind"] == "row" and entry["key"] == open_key:
			return entry["active"]
	return false


## A row: its text and a gate button, then the open picker and any message for it.
func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = entry["head"]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var key: String = entry["key"]
	var button := Button.new()
	button.text = tr("Gate {gate}", "gate name").format({"gate": entry["gate"]})
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not entry["active"]
	if entry["active"]:
		button.name = "Gate_%s" % key
		button.tooltip_text = tr("Move this flight to another gate")
		button.pressed.connect(_on_gate_pressed.bind(key))
	row.add_child(button)
	var end_btn: Button = null
	if entry["active"]:
		end_btn = Button.new()
		end_btn.name = "End_%s" % key
		end_btn.text = tr("End", "button: end the contract")
		end_btn.tooltip_text = tr("End this airline contract")
		end_btn.focus_mode = Control.FOCUS_NONE
		end_btn.pressed.connect(_on_end_pressed.bind(key, entry["contract"]))
		row.add_child(end_btn)
	_rows.add_child(row)
	button.theme_type_variation = GateColours.variation_of(entry["gate"])
	if end_btn != null:
		_compact(end_btn)
	var parts := PackedStringArray()
	for part: String in [entry["airline"], entry["status"]]:
		if part != "":
			parts.append(part)
	var late_text: String = entry["late"]
	var airline_name := "Airline_%s" % key if key != "" else "Airline"
	if late_text == "":
		if not parts.is_empty():
			var airline := Label.new()
			airline.name = airline_name
			airline.text = "  ".join(parts)
			airline.theme_type_variation = &"HudHint"
			airline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			airline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_rows.add_child(airline)
	else:
		var line := HFlowContainer.new()
		line.name = "LateRow_%s" % entry["flight"]
		line.add_theme_constant_override("h_separation", 6)
		line.add_theme_constant_override("v_separation", 2)
		if not parts.is_empty():
			var airline := Label.new()
			airline.name = airline_name
			airline.text = "  ".join(parts)
			airline.theme_type_variation = &"HudHint"
			airline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			airline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			airline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(airline)
		var late_btn := Button.new()
		late_btn.name = "Late_%s" % entry["flight"]
		late_btn.text = late_text
		late_btn.tooltip_text = tr("Follow the tightest running-late passenger")
		late_btn.focus_mode = Control.FOCUS_NONE
		var flight_id: String = entry["flight"]
		late_btn.pressed.connect(func() -> void: follow_late_requested.emit(flight_id))
		line.add_child(late_btn)
		_rows.add_child(line)
		_compact(late_btn)
	if entry["doors"] != "":
		var doors := Label.new()
		doors.name = "DoorsClose"
		doors.text = entry["doors"]
		doors.theme_type_variation = &"HudHint"
		doors.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(doors)
	if key != "" and key == _picker_key:
		_add_picker(entry)
	if key != "" and key == _confirm_key:
		_add_end_confirm(entry["contract"])
	if key != "" and key == _message_key and _message != "":
		var note := Label.new()
		note.name = "Message"
		note.text = _message
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.theme_type_variation = &"HudHint"
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(note)


## The question under a row after End: confirm or keep the contract.
func _add_end_confirm(contract_id: String) -> void:
	var box := HBoxContainer.new()
	box.name = "EndConfirm"
	var prompt := Label.new()
	prompt.name = "EndPrompt"
	prompt.text = end_prompt(flights, contract_id)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(prompt)
	var confirm := Button.new()
	confirm.name = "ConfirmEnd"
	confirm.text = tr("End contract")
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_end_confirmed.bind(contract_id))
	box.add_child(confirm)
	var keep := Button.new()
	keep.name = "KeepContract"
	keep.text = tr("Keep", "button: keep the contract")
	keep.focus_mode = Control.FOCUS_NONE
	keep.pressed.connect(_on_end_kept)
	box.add_child(keep)
	_rows.add_child(box)
	_compact(confirm)
	_compact(keep)


## The picker under a row: a button for each other gate the contract fits at
## now, or a note when there is none.
func _add_picker(entry: Dictionary) -> void:
	var choices := move_choices(flights, entry["contract"], _gates)
	var others: Array[String] = choices["fitting"]
	var any_other: bool = choices["any_other"]
	var picker := HBoxContainer.new()
	picker.name = "Picker"
	if others.is_empty():
		var note := Label.new()
		note.name = "PickerNote"
		note.text = (
			tr("No other gate fits this flight") if any_other else tr("No other gate exists")
		)
		if _gates.is_empty():
			note.text = tr("No gate has a stand")
		note.theme_type_variation = &"HudHint"
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picker.add_child(note)
	else:
		var prompt := Label.new()
		prompt.name = "PickerNote"
		prompt.text = tr("Move to:")
		prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picker.add_child(prompt)
		for gate_id in others:
			var choice := Button.new()
			choice.name = "Pick_%s" % gate_id
			choice.text = gate_id
			choice.focus_mode = Control.FOCUS_NONE
			choice.pressed.connect(_on_pick_pressed.bind(entry["contract"], gate_id))
			picker.add_child(choice)
	_rows.add_child(picker)
	for piece in picker.get_children():
		if piece is Button:
			_compact(piece)


## Gives a button the theme's short HudButtonCompact padding, so it is no
## taller than the text beside it and the board stays short.
func _compact(button: Button) -> void:
	button.theme_type_variation = &"HudButtonCompact"


func _on_gate_pressed(key: String) -> void:
	var was_open := _picker_key == key
	_close_picker()
	if not was_open:
		_picker_key = key
	_refresh(true)


func _close_picker() -> void:
	_picker_key = ""
	_confirm_key = ""
	_message_key = ""
	_message = ""


## Opens the "End this contract?" question under the row, or closes it on a
## second press. A contract whose ending FlightSim refuses gets the reason
## under its row instead of the question.
func _on_end_pressed(key: String, contract_id: String) -> void:
	var was_open := _confirm_key == key
	_close_picker()
	if not was_open:
		_message_key = key
		_message = end_refusal_text(contract_id)
		if _message == "":
			_confirm_key = key
	_refresh(true)


## Ends the contract unless FlightSim now refuses; the world may have changed
## since the question opened.
func _on_end_confirmed(contract_id: String) -> void:
	var key := _confirm_key
	_close_picker()
	_message_key = key
	_message = end_outcome(flights, contract_id)
	_refresh(true)


## The gates other than the contract's own, from `gates`: {fitting: the ones it
## fits now (FlightSim.reassign_problem is ""), any_other: whether there is any
## other gate at all}. The Move to picker here and the flight planner's both list
## these.
static func move_choices(sim: FlightSim, contract_id: String, gates: Array[String]) -> Dictionary:
	var current: String = sim.contract_of(contract_id)["gate"]
	var fitting: Array[String] = []
	var any_other := false
	for gate_id in gates:
		if gate_id == current:
			continue
		any_other = true
		if sim.reassign_problem(contract_id, gate_id) == "":
			fitting.append(gate_id)
	return {"fitting": fitting, "any_other": any_other}


## Moves the contract to `gate_id` unless FlightSim refuses: {moved, text}, the
## text the confirmation or the refusal in the player's words.
static func move_outcome(sim: FlightSim, contract_id: String, gate_id: String) -> Dictionary:
	var problem := sim.reassign_problem(contract_id, gate_id)
	if problem != "":
		return {"moved": false, "text": reason_text(sim, problem, gate_id)}
	sim.reassign_gate(contract_id, gate_id)
	var destination: String = sim.contract_of(contract_id)["destination"]
	return {
		"moved": true,
		"text":
		(
			TranslationServer
			. translate("{destination} now uses gate {gate} for the days not yet issued")
			. format({"destination": destination, "gate": gate_id})
		),
	}


## The End confirm's question for `contract_id`: END_PROMPT, or END_FEE_PROMPT
## with the Exit fee ending it now costs (FlightSim.end_fee). The Departures
## row and the flight planner both ask this.
static func end_prompt(sim: FlightSim, contract_id: String) -> String:
	var fee := sim.end_fee(contract_id)
	if fee > 0:
		return TranslationServer.translate("End this contract? Exit fee ${fee}").format(
			{"fee": fee}
		)
	return TranslationServer.translate("End this contract?")


## Ends the contract as the player (FlightSim.end_contract_by_player, which has
## Settlement charge any Exit fee due) unless FlightSim now refuses, and says
## what happened: the ENDED_TEXT confirmation, or the refusal's words. "" when
## FlightSim could not end it for another reason.
static func end_outcome(sim: FlightSim, contract_id: String) -> String:
	var refusal := end_refusal_words(sim, contract_id)
	if refusal != "":
		return refusal
	if sim.end_contract_by_player(contract_id):
		return (
			TranslationServer
			. translate("{destination} contract ended. Flights already booked still fly")
			. format({"destination": sim.contract_of(contract_id)["destination"]})
		)
	return ""


func _on_end_kept() -> void:
	_close_picker()
	_refresh(true)


## Why ending `contract_id` is refused, in words naming the flight it would
## strand by departure time, airline and destination, or "" when it can end.
func end_refusal_text(contract_id: String) -> String:
	return end_refusal_words(flights, contract_id)


static func end_refusal_words(sim: FlightSim, contract_id: String) -> String:
	var refusal := sim.end_refusal(contract_id)
	if refusal.is_empty():
		return ""
	var id: String = refusal["id"]
	var parts := FlightTimetable.parse_occurrence(id)
	var label := FlightLabel.label_args(
		sim, parts.is_empty(), id if parts.is_empty() else parts["contract"]
	)
	if label.is_empty():
		return TranslationServer.translate(
			"Can't end this contract: another flight would have no taxi plan"
		)
	# One whole sentence per flight-name shape (FlightLabel.label_args()).
	if label["airline"] == "" or label["city"] == "":
		return (
			TranslationServer
			. translate("Can't end this contract: the {time} flight would have no taxi plan")
			. format(label)
		)
	return (
		TranslationServer
		. translate(
			"Can't end this contract: the {time} {airline} flight to {city} would have no taxi plan"
		)
		. format(label)
	)


## Moves the contract to `gate_id`, or says why not. FlightSim names the
## reason; a refusal keeps the picker open so another gate can be tried.
func _on_pick_pressed(contract_id: String, gate_id: String) -> void:
	var outcome := move_outcome(flights, contract_id, gate_id)
	_message_key = _picker_key
	_message = outcome["text"]
	if outcome["moved"]:
		_picker_key = ""
	_refresh(true)


## A load replaces every contract and flight, so the open picker and the
## message under it no longer describe anything: drop them and read the new
## schedule.
func _on_snapshot_loaded() -> void:
	_close_picker()
	_manual_open = false
	_entries = []
	if not _has_flights and _shown:
		_shown = false
		_apply_shown()
	_refresh(false)


## The player-facing text for a FlightSim refusal `reason` of a move to
## `gate_id`. The sim names contracts and flights by id; here the clashing
## flight is named by its departure time and destination, as "Gate A is taken
## by the 10:00 Oslo flight". A reason that is not a clash, or a flight that
## cannot be resolved, reads "Gate A is busy when this flight needs it".
func friendly_reason(reason: String, gate_id: String) -> String:
	return reason_text(flights, reason, gate_id)


static func reason_text(sim: FlightSim, reason: String, gate_id: String) -> String:
	var found := FlightLabel.parse_clash(reason)
	var busy := TranslationServer.translate("Gate {gate} is busy when this flight needs it")
	if found.is_empty():
		return busy.format({"gate": gate_id})
	var label := FlightLabel.parts(sim, found["is_flight"], found["id"])
	if label.is_empty():
		return busy.format({"gate": gate_id})
	var subject := TranslationServer.translate("Gate {gate}", "gate name").format(
		{"gate": found["gate"]}
	)
	if found["where"] == "on the runway":
		subject = TranslationServer.translate("The runway")
	elif found["where"] == "on the taxi lane":
		subject = TranslationServer.translate("The taxi lane")
	if label[1] == "":
		return TranslationServer.translate("{subject} is taken by the {time} flight").format(
			{"subject": subject, "time": label[0]}
		)
	return (
		TranslationServer
		. translate("{subject} is taken by the {time} {destination} flight")
		. format({"subject": subject, "time": label[0], "destination": label[1]})
	)


## B toggles; a held key's repeats and modified presses are left alone.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not event.is_action_pressed(ACTION):
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	if not key.echo:
		set_shown(not _shown)
	get_viewport().set_input_as_handled()


func _apply_shown() -> void:
	_panel.visible = _shown and not _aside
	_toggle.set_pressed_no_signal(_shown)
	if not _shown:
		_lines = PackedStringArray()
		_entries = []
		_close_picker()


## The saved choice, on when nothing is saved yet. A settings file that exists
## but cannot be read is reported and the board stays on.
func _load_setting() -> bool:
	return HudFlagSetting.load_boot_flag(settings_path, SETTING_KEY, true, "DeparturesBoard")


## Writes the choice next to any other settings already in the file.
func _save_setting() -> void:
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, _setting, "DeparturesBoard")
