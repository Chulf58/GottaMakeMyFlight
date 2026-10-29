class_name DeparturesBoard
extends VBoxContainer
## The departures board (HUD 3/7, decision hud-steal-list-self-clearing-alert-
## cards-money-hover-departu): a read-only panel listing the flights leaving
## today that have not departed and the flights leaving tomorrow, each in time
## order, drawn from the FlightSim's contracts and occurrences. Row text is
## DepartureList's, so a flight reads here as it does in the flight panel
## ("07:38  Oslo  Gotta Air  Boarding"). Each day lists at most
## MAX_ROWS_PER_DAY rows, then "+n more"; a day with none says "None", and
## with nothing on either day the board says EMPTY_TEXT.
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
const MAX_ROWS_PER_DAY := 5
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


## The board's lines for the clock at `tick`: "Today" and its rows, then
## "Tomorrow" and its rows; only EMPTY_TEXT when both days are empty.
static func lines_for(sim: FlightSim, tick: int) -> PackedStringArray:
	var today := GameCalendar.day_of(tick)
	var todays := _day_lines(sim, today, true)
	var tomorrows := _day_lines(sim, today + 1, false)
	if todays.is_empty() and tomorrows.is_empty():
		return PackedStringArray([EMPTY_TEXT])
	var lines := PackedStringArray([TODAY_HEADING])
	lines.append_array(todays if not todays.is_empty() else PackedStringArray([NONE_TEXT]))
	lines.append(TOMORROW_HEADING)
	lines.append_array(tomorrows if not tomorrows.is_empty() else PackedStringArray([NONE_TEXT]))
	return lines


## One day's rows in time order, flights that have departed dropped when
## `drop_departed`, capped at MAX_ROWS_PER_DAY with a "+n more" line after.
static func _day_lines(sim: FlightSim, day: int, drop_departed: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var kept: Array[Dictionary] = []
	for row in DepartureList.rows_for_day(sim, day):
		if not (drop_departed and row["departed"]):
			kept.append(row)
	for row in kept.slice(0, MAX_ROWS_PER_DAY):
		lines.append(row["line"])
	if kept.size() > MAX_ROWS_PER_DAY:
		lines.append("+%d more" % (kept.size() - MAX_ROWS_PER_DAY))
	return lines


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


## Refills the rows from the FlightSim and the clock when they changed. A
## hidden board reads nothing. Rows are rebuilt only when the lines change.
func refresh() -> void:
	if not _shown or flights == null or clock == null:
		return
	var lines := lines_for(flights, clock.tick)
	if lines == _lines:
		return
	_lines = lines
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = line
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if line in [TODAY_HEADING, TOMORROW_HEADING]:
			label.theme_type_variation = &"HudHint"
		_rows.add_child(label)


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
