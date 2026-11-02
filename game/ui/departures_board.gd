class_name DeparturesBoard
extends VBoxContainer
## The departures board (HUD 3/7, decision hud-steal-list-self-clearing-alert-
## cards-money-hover-departu): a panel listing the flights leaving today that
## have not departed and the flights leaving tomorrow, each in time order,
## drawn from the FlightSim's contracts and occurrences. Row text is
## DepartureList's, so a flight reads here as it does in the flight panel
## ("07:38  Oslo  Gotta Air  Boarding"). Each day lists at most
## MAX_ROWS_PER_DAY rows, then "+n more"; a day with none says "None", and
## with nothing on either day the board says EMPTY_TEXT.
##
## Each row ends in a gate button showing the gate the flight holds (decision
## gates-are-placed-gate-desks-each-desk-links-automatically-to: the gate is
## automatic, and Departures is where the player changes it). Clicking it opens
## a picker under the row listing every other gate with a stand; choosing one
## calls FlightSim.reassign_gate, which moves the contract's days not yet
## issued (an occurrence already issued keeps its gate, so its row still shows
## the old one). A gate whose time is taken is refused with FlightSim's own
## reason, shown under the row, and the picker stays open. With no other gate
## the picker says NO_OTHER_TEXT. A one-off flight or an ended contract shows
## its gate on a disabled button.
##
## It is an optional piece with an on/off setting, so the HUD can be rolled
## back if it turns into information overload: a toggle button (always
## visible) and the B key show and hide the panel, and the choice is kept in a
## ConfigFile at settings_path, "hud/departures_board", and read back when the
## board is built. On is the default. B is free of the build tool keys 1 to 0,
## the speed keys (Space, Shift+1/2/3) and the camera keys (WASD, Q, E, Home).

## The input action for the toggle key, bound to B in project.godot.
const ACTION := &"toggle_departures_board"
const SETTINGS_PATH := "user://hud_settings.cfg"
const SECTION := "hud"
const SETTING_KEY := "departures_board"
const TODAY_HEADING := "Today"
const TOMORROW_HEADING := "Tomorrow"
const EMPTY_TEXT := "No flights scheduled"
const NONE_TEXT := "None"
const NO_OTHER_TEXT := "No other gate exists"
const PICKER_LABEL := "Move to:"
const MOVED_TEXT := "%s now uses gate %s for the days not yet issued"
const TAKEN_TEXT := "%s is taken by the %s %s flight"
const BUSY_TEXT := "Gate %s is busy when this flight needs it"
const MAX_ROWS_PER_DAY := 5
## Top and bottom padding of the gate buttons, below the theme's 6.
const BUTTON_PAD_Y := 1.0
const BOARD_LEFT := 16.0
## Below the room panel's usual place (top-left, under the money slot) and
## above the follow text at the bottom.
const BOARD_TOP := 330.0
const BOARD_W := 300.0

@export var flights: FlightSim
@export var clock: SimClock
## Where the on/off choice is kept; tests point it at a per-process file.
var settings_path := SETTINGS_PATH

var _shown := true
var _toggle := Button.new()
var _panel := PanelContainer.new()
var _rows := VBoxContainer.new()
var _lines := PackedStringArray()
var _entries: Array[Dictionary] = []
var _gates: Array[String] = []
## The row key ("contract_day") whose picker is open, and the row key the
## message under it belongs to; both "" for none.
var _picker_key := ""
var _message_key := ""
var _message := ""
## What FlightSim's refusal reads like: "contract Y clashes with X at gate A",
## "... with flight X-d0 on the runway".
var _clash := RegEx.create_from_string(
	"^contract \\S+ clashes with (flight )?(\\S+) (at gate (\\S+)|on the runway|on the taxi lane)$"
)


## The board's lines for the clock at `tick`: "Today" and its rows, then
## "Tomorrow" and its rows; only EMPTY_TEXT when both days are empty.
static func lines_for(sim: FlightSim, tick: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in entries_for(sim, tick):
		lines.append(entry["text"])
	return lines


## What the board draws at `tick`, in order: {kind: "heading" | "text" | "row",
## text}, and for a "row" also {contract, day, gate, key}.
static func entries_for(sim: FlightSim, tick: int) -> Array[Dictionary]:
	var today := GameCalendar.day_of(tick)
	var todays := _day_entries(sim, today, true)
	var tomorrows := _day_entries(sim, today + 1, false)
	var entries: Array[Dictionary] = []
	if todays.is_empty() and tomorrows.is_empty():
		entries.append({"kind": "text", "text": EMPTY_TEXT})
		return entries
	entries.append({"kind": "heading", "text": TODAY_HEADING})
	_append_day(entries, todays)
	entries.append({"kind": "heading", "text": TOMORROW_HEADING})
	_append_day(entries, tomorrows)
	return entries


static func _append_day(entries: Array[Dictionary], day_entries: Array[Dictionary]) -> void:
	if day_entries.is_empty():
		entries.append({"kind": "text", "text": NONE_TEXT})
	for entry in day_entries:
		entries.append(entry)


## One day's rows in time order, flights that have departed dropped when
## `drop_departed`, capped at MAX_ROWS_PER_DAY with a "+n more" entry after.
static func _day_entries(sim: FlightSim, day: int, drop_departed: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for row in DepartureList.rows_for_day(sim, day):
		if not (drop_departed and row["departed"]):
			kept.append(row)
	for row in kept.slice(0, MAX_ROWS_PER_DAY):
		(
			entries
			. append(
				{
					"kind": "row",
					"text": row["line"],
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
		entries.append({"kind": "text", "text": "+%d more" % (kept.size() - MAX_ROWS_PER_DAY)})
	return entries


func _ready() -> void:
	name = "DeparturesBoard"
	theme = BuildMenu.HUD_THEME
	position = Vector2(BOARD_LEFT, BOARD_TOP)
	custom_minimum_size = Vector2(BOARD_W, 0.0)
	_toggle.name = "DeparturesToggle"
	_toggle.text = "Departures (B)"
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(_toggle)
	_panel.name = "DeparturesPanel"
	add_child(_panel)
	_rows.add_theme_constant_override("separation", 1)
	_panel.add_child(_rows)
	_shown = _load_setting()
	_apply_shown()
	_toggle.toggled.connect(set_shown)
	if flights != null:
		flights.snapshot_loaded.connect(_on_snapshot_loaded)
	refresh()


## True while the panel is on.
func is_shown() -> bool:
	return _shown


## Shows or hides the panel and keeps the choice. The toggle button and the
## key both come through here.
func set_shown(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	_apply_shown()
	_save_setting()
	refresh()


## The lines the panel is showing now: empty while it is hidden.
func shown_lines() -> PackedStringArray:
	return _lines


## The gate button on the row of `contract_id` on `day`, or null.
func gate_button(contract_id: String, day: int) -> Button:
	return find_child("Gate_%s_%d" % [contract_id, day], true, false) as Button


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


func _refresh(force: bool) -> void:
	if not _shown or flights == null or clock == null:
		return
	var entries := entries_for(flights, clock.tick)
	var gates := flights.gate_ids()
	if not force and entries == _entries and gates == _gates:
		return
	_entries = entries
	_gates = gates
	if _picker_key != "" and not _picker_row_live():
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


## True while the open picker's row is listed and its contract still runs.
func _picker_row_live() -> bool:
	for entry in _entries:
		if entry["kind"] == "row" and entry["key"] == _picker_key:
			return entry["active"]
	return false


## A row: its text and a gate button, then the open picker and any message for it.
func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = entry["text"]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var key: String = entry["key"]
	var button := Button.new()
	button.text = "Gate %s" % entry["gate"]
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not entry["active"]
	if entry["active"]:
		button.name = "Gate_%s" % key
		button.tooltip_text = "Move this flight to another gate"
		button.pressed.connect(_on_gate_pressed.bind(key))
	row.add_child(button)
	_rows.add_child(row)
	_compact(button)
	if key != "" and key == _picker_key:
		_add_picker(entry)
	if key != "" and key == _message_key and _message != "":
		var note := Label.new()
		note.name = "Message"
		note.text = _message
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.theme_type_variation = &"HudHint"
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(note)


## The picker under a row: a button for each gate the contract is not at, or a
## note when there is none.
func _add_picker(entry: Dictionary) -> void:
	var current: String = flights.contract_of(entry["contract"])["gate"]
	var others: Array[String] = []
	for gate_id in _gates:
		if gate_id != current:
			others.append(gate_id)
	var picker := HBoxContainer.new()
	picker.name = "Picker"
	if others.is_empty():
		var note := Label.new()
		note.name = "PickerNote"
		note.text = NO_OTHER_TEXT if not _gates.is_empty() else "No gate has a stand"
		note.theme_type_variation = &"HudHint"
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picker.add_child(note)
	else:
		var prompt := Label.new()
		prompt.name = "PickerNote"
		prompt.text = PICKER_LABEL
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


## Trims the theme's button padding so a button is no taller than the text
## beside it and the board stays short. Needs `button` in the tree, so it
## reads the HUD theme.
func _compact(button: Button) -> void:
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		var box := button.get_theme_stylebox(state).duplicate() as StyleBox
		box.content_margin_top = BUTTON_PAD_Y
		box.content_margin_bottom = BUTTON_PAD_Y
		button.add_theme_stylebox_override(state, box)


func _on_gate_pressed(key: String) -> void:
	var was_open := _picker_key == key
	_close_picker()
	if not was_open:
		_picker_key = key
	_refresh(true)


func _close_picker() -> void:
	_picker_key = ""
	_message_key = ""
	_message = ""


## Moves the contract to `gate_id`, or says why not. FlightSim names the
## reason; a refusal keeps the picker open so another gate can be tried.
func _on_pick_pressed(contract_id: String, gate_id: String) -> void:
	var problem := flights.reassign_problem(contract_id, gate_id)
	_message_key = _picker_key
	if problem != "":
		_message = friendly_reason(problem, gate_id)
	else:
		flights.reassign_gate(contract_id, gate_id)
		var contract := flights.contract_of(contract_id)
		_message = MOVED_TEXT % [contract["destination"], gate_id]
		_picker_key = ""
	_refresh(true)


## A load replaces every contract and flight, so the open picker and the
## message under it no longer describe anything: drop them and read the new
## schedule.
func _on_snapshot_loaded() -> void:
	_close_picker()
	_entries = []
	_refresh(false)


## The player-facing text for a FlightSim refusal `reason` of a move to
## `gate_id`. The sim names contracts and flights by id; here the clashing
## flight is named by its departure time and destination, as "Gate A is taken
## by the 10:00 Oslo flight". A reason that is not a clash, or a flight that
## cannot be resolved, reads "Gate A is busy when this flight needs it".
func friendly_reason(reason: String, gate_id: String) -> String:
	var found := _clash.search(reason)
	if found == null:
		return BUSY_TEXT % gate_id
	var label := _flight_label(found.get_string(1) != "", found.get_string(2))
	if label.is_empty():
		return BUSY_TEXT % gate_id
	var subject := "Gate %s" % found.get_string(4)
	if found.get_string(3) == "on the runway":
		subject = "The runway"
	elif found.get_string(3) == "on the taxi lane":
		subject = "The taxi lane"
	return TAKEN_TEXT % [subject, label[0], label[1]]


## [departure time, destination] of the contract (or, when `is_flight`, the
## live flight) that FlightSim named by id, or [] when it is not known. A
## one-off flight is named by its id.
func _flight_label(is_flight: bool, id: String) -> PackedStringArray:
	if is_flight:
		var tick := flights.state_start(id, FlightSim.State.PUSHBACK)
		if tick < 0:
			return PackedStringArray()
		var source := flights.contract_of(flights.flight_contract_id(id))
		var named: String = source["destination"] if not source.is_empty() else id
		return PackedStringArray([GameCalendar.clock_text(tick), named])
	var contract := flights.contract_of(id)
	if contract.is_empty():
		return PackedStringArray()
	var at := GameCalendar.tick_at(0, int(contract["departure_minute"]))
	return PackedStringArray([GameCalendar.clock_text(at), contract["destination"]])


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
	_panel.visible = _shown
	_toggle.set_pressed_no_signal(_shown)
	if not _shown:
		_lines = PackedStringArray()
		_entries = []
		_close_picker()


## The saved choice, on when nothing is saved yet. A settings file that exists
## but cannot be read is reported and the board stays on.
func _load_setting() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	if err == ERR_FILE_NOT_FOUND:
		return true
	if err != OK:
		push_error("DeparturesBoard: cannot read %s (error %d)" % [settings_path, err])
		return true
	return bool(cfg.get_value(SECTION, SETTING_KEY, true))


## Writes the choice next to any other settings already in the file.
func _save_setting() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("DeparturesBoard: cannot read %s (error %d)" % [settings_path, err])
		return
	cfg.set_value(SECTION, SETTING_KEY, _shown)
	err = cfg.save(settings_path)
	if err != OK:
		push_error("DeparturesBoard: cannot write %s (error %d)" % [settings_path, err])
