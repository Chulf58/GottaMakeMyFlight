class_name DeparturesBoard
extends Control
## The Live Ops departures drawer (decisions hud-steal-list-self-clearing-
## alert-cards-money-hover-departu, departures-live-ops-drawer-and-actionable-
## on-time-hud-stat): collapsed by default on new games, with a dynamic toggle
## button summarizing today's flights or running-late count. When expanded, it
## lists today's non-departed live flights in time order with live
## Boarded/Booked counts, doors-close time on the next departing flight, status
## words, clickable "N running late" pills to follow the tightest runner, and
## click-row-to-focus the flight's gate desk. Gate reassignment and End contract
## controls live exclusively in FlightPlanner (P), sharing the static action
## helpers here.
##
## Its header shows live "In terminal: N" (with a clickable "· K late" pill when
## K > 0) and rolling 3-day "On time: XX%" from AirportRating.

## Emitted when the player clicks a "N running late" pill (row or header).
signal follow_late_requested(flight_id: String)
## Emitted when the player clicks a flight row to pan to its gate desk.
signal focus_gate_requested(gate_id: String)

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
## Shared msgids for FlightPlanner / PlannerDrag and their tests.
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
## Where live In terminal, boarded/booked, and late counts come from.
var passengers: PassengerSim:
	set(value):
		if value == passengers:
			return
		passengers = value
		_late_key = []
		_progress_key = []
## Where the rolling 3-day on-time rate comes from.
var rating: AirportRating
## Where the on/off choice is kept; tests point it at a per-process file.
var settings_path := SETTINGS_PATH
## The bar the list stands over, for how much room the column has.
var menu: BuildMenu

var _shown := false
## The player's saved on/off setting (false by default on new games).
var _setting := false
## Whether at least one live flight is listed today; 0 flights auto-collapses.
var _has_flights := false
## True when the player explicitly expanded the board while 0 flights exist.
var _manual_open := false
## True while the inspect card has the list stepped aside (step_aside()).
var _aside := false
var _toggle := Button.new()
var _panel := PanelContainer.new()
var _counts := VBoxContainer.new()
var _in_terminal_label := Label.new()
var _header_late_btn := Button.new()
var _on_time_label := Label.new()
var _rows := VBoxContainer.new()
## The rows scroll when the column leaves them less room than they take (_process).
var _scroll := ScrollContainer.new()
## How many times the scroll area's height was changed, for tests.
var _scroll_sets := 0
var _lines := PackedStringArray()
var _entries: Array[Dictionary] = []
var _late := {}
var _late_key := []
var _late_total := 0
var _tightest_late_flight := ""
var _today_count := 0
var _last_toggle_text := ""
var _progress := {}
var _progress_key := []
var _rows_pending_layout := false
var _autowrap_labels: Array[Label] = []


## The board's lines for the clock at `tick`: "Today" and today's non-departed
## rows; only EMPTY_TEXT when none are left today.
static func lines_for(sim: FlightSim, tick: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in entries_for(sim, tick):
		lines.append(entry["text"])
	return lines


## What the board draws at `tick` for today's live flights: {kind: "heading" |
## "text" | "row", text}, and for a "row" also {head, airline, status, doors,
## late, boarded, booked, boarded_text, flight, contract, day, gate, key}.
static func entries_for(
	sim: FlightSim, tick: int, late := {}, progress := {}, passengers_sim: PassengerSim = null
) -> Array[Dictionary]:
	var today := GameCalendar.day_of(tick, sim.epoch)
	var todays := _day_entries(sim, today, true, tick, late, progress, passengers_sim)
	var entries: Array[Dictionary] = []
	if todays.is_empty():
		entries.append(
			{"kind": "text", "text": TranslationServer.translate("No flights scheduled")}
		)
		return entries
	entries.append({"kind": "heading", "text": TranslationServer.translate("Today")})
	for entry in todays:
		entries.append(entry)
	return entries


## One day's rows in time order, flights that have departed dropped when
## `drop_departed`, capped at MAX_ROWS_PER_DAY with a "+n more" entry after.
static func _day_entries(
	sim: FlightSim,
	day: int,
	drop_departed: bool,
	tick: int,
	late: Dictionary,
	progress: Dictionary,
	passengers_sim: PassengerSim
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
		var prog := DepartureList.row_progress(
			sim, passengers_sim, row["flight"], row["contract"], progress
		)
		var boarded: int = prog["boarded"]
		var booked: int = prog["booked"]
		(
			entries
			. append(
				{
					"kind": "row",
					"text": DepartureList.doors_line(row, sim.epoch) if is_next else row["line"],
					"head": row["head"],
					"airline": row["airline"],
					"status": "" if is_next else row["status"],
					"doors": DepartureList.doors_text(row, sim.epoch) if is_next else "",
					"late": LateCount.text_for(int(late.get(row["flight"], 0))),
					"boarded": boarded,
					"booked": booked,
					"boarded_text": DepartureList.boarded_text(boarded, booked),
					"flight": row["flight"],
					"contract": row["contract"],
					"day": day,
					"gate": row["gate"],
					"stand": row.get("stand", row["gate"]),
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
	body.add_theme_constant_override("separation", 2)
	_panel.add_child(body)
	_build_counts_header(body)
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.sort_children.connect(_on_rows_sorted)
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


func _build_counts_header(body: VBoxContainer) -> void:
	_counts.name = "Counts"
	_counts.add_theme_constant_override("separation", 1)
	_counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_counts)
	var line_one := HBoxContainer.new()
	line_one.add_theme_constant_override("separation", 6)
	line_one.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counts.add_child(line_one)
	_in_terminal_label.name = "InTerminal"
	_in_terminal_label.theme_type_variation = &"HudHint"
	_in_terminal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_one.add_child(_in_terminal_label)
	_header_late_btn.name = "HeaderLate"
	_header_late_btn.theme_type_variation = &"HudButtonCompact"
	_header_late_btn.focus_mode = Control.FOCUS_NONE
	_header_late_btn.visible = false
	_header_late_btn.tooltip_text = tr("Follow the tightest running-late passenger")
	_header_late_btn.pressed.connect(_on_header_late_pressed)
	line_one.add_child(_header_late_btn)
	_on_time_label.name = "OnTime"
	_on_time_label.theme_type_variation = &"HudHint"
	_on_time_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_on_time_label.tooltip_text = tr("3-day rolling on-time rate (70% of your quality score)")
	_counts.add_child(_on_time_label)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	_last_toggle_text = ""
	_header_late_btn.tooltip_text = tr("Follow the tightest running-late passenger")
	_on_time_label.tooltip_text = tr("3-day rolling on-time rate (70% of your quality score)")
	_sync_toggle()
	_refresh(true)


func _process(_delta: float) -> void:
	_sync_panel_top()
	if not _panel.is_visible_in_tree():
		return
	if _rows_pending_layout or _has_unlaid_autowrap():
		return
	var bar_w := 0.0 if menu == null else menu.bar().get_combined_minimum_size().x
	var room := LeftColumn.list_room(get_tree(), get_viewport().get_visible_rect().size, bar_w)
	var chrome := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var height := minf(_rows.get_combined_minimum_size().y, maxf(0.0, room - chrome))
	if not is_equal_approx(_scroll.custom_minimum_size.y, height):
		_scroll.custom_minimum_size.y = height
		_panel.reset_size()
		_scroll_sets += 1


func _on_rows_sorted() -> void:
	if _panel.is_visible_in_tree() and _rows.size.x > 0.0:
		_rows_pending_layout = false


func _has_unlaid_autowrap() -> bool:
	for label in _autowrap_labels:
		if is_instance_valid(label) and label.visible and label.size.x <= 0.0:
			return true
	return false


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


## True while the panel is expanded (even if stepped aside).
func is_shown() -> bool:
	return _shown


## True while DeparturesPanel is actually visible on screen (expanded and not
## stepped aside). AlertStack suppresses the late-runner alert card while true.
func is_panel_visible() -> bool:
	return _panel.is_visible_in_tree() if is_inside_tree() else _panel.visible


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


## The clickable "N running late" pill on `flight_id`'s row, or null.
func late_button(flight_id: String) -> Button:
	return find_child("Late_%s" % flight_id, true, false) as Button


## Refills the toggle summary, header telemetry, and rows from the sims.
func refresh() -> void:
	_refresh(false)


## Header summary string: "In terminal: N  · K late  On time: XX%", or ""
## while neither PassengerSim nor AirportRating is set.
func counts_text() -> String:
	if passengers == null and rating == null:
		return ""
	var parts := PackedStringArray([_in_terminal_text()])
	if _late_total > 0:
		parts.append(_header_late_text())
	parts.append(_on_time_text())
	return "  ".join(parts)


## Passengers of `flight_id` running late as of the last refresh.
func late_count_of(flight_id: String) -> int:
	return int(_late.get(flight_id, 0))


## Total running-late passengers across active flights as of the last refresh.
func total_late_count() -> int:
	return _late_total


## Number of today's non-departed flights as of the last refresh.
func today_flight_count() -> int:
	return _today_count


func _in_terminal_text() -> String:
	var active := passengers.active_count() if passengers != null else 0
	return tr("In terminal: {active}").format({"active": active})


func _header_late_text() -> String:
	return tr("· {count} late").format({"count": _late_total})


func _on_time_text() -> String:
	if rating != null and rating.has_data():
		var share := roundi(float(rating.parts()["made_share"]) * 100.0)
		return tr("On time: {percent}%").format({"percent": share})
	return tr("On time: —")


func _late_counts() -> Dictionary:
	if passengers == null:
		_late_total = 0
		_tightest_late_flight = ""
		return {}
	var key := _late_signature()
	if key != _late_key:
		_late_key = key
		_late = LateCount.by_flight(passengers)
		var tightest := LateCount.tightest_overall(passengers)
		_late_total = int(tightest.get("total", 0))
		_tightest_late_flight = String(tightest.get("flight", ""))
	return _late


func _progress_counts() -> Dictionary:
	if passengers == null:
		return {}
	var key := [passengers.get_instance_id(), passengers.revision, passengers.pending_spawns()]
	if key != _progress_key:
		_progress_key = key
		_progress = DepartureList.progress_scan(passengers)
	return _progress


func _late_signature() -> Array:
	return [passengers.get_instance_id(), passengers.revision]


## True when `entries` lists at least one flight row (not empty).
static func entries_have_flights(entries: Array[Dictionary]) -> bool:
	for entry in entries:
		if entry["kind"] == "row":
			return true
	return false


func _count_today_live(sim: FlightSim, tick: int) -> int:
	var today := GameCalendar.day_of(tick, sim.epoch)
	var count := 0
	for row in DepartureList.rows_for_day(sim, today):
		if not row["departed"]:
			count += 1
	return count


func _sync_toggle() -> void:
	var text := tr("Departures ({key})").format({"key": HOTKEY})
	var variation := &""
	if _today_count > 0:
		if _late_total > 0:
			text = tr("Departures ({key}) · {count} late").format(
				{"key": HOTKEY, "count": _late_total}
			)
			variation = &"HudButtonYellow"
		else:
			text = tr("Departures ({key}) · {count} today").format(
				{"key": HOTKEY, "count": _today_count}
			)
	if text != _last_toggle_text:
		_last_toggle_text = text
		_toggle.text = text
		_toggle.reset_size()
	if _toggle.theme_type_variation != variation:
		_toggle.theme_type_variation = variation


func _sync_header() -> void:
	_counts.visible = passengers != null or rating != null
	if not _counts.visible:
		return
	_in_terminal_label.text = _in_terminal_text()
	_header_late_btn.visible = _late_total > 0 and _tightest_late_flight != ""
	if _header_late_btn.visible:
		_header_late_btn.text = _header_late_text()
	_on_time_label.text = _on_time_text()


func _refresh(force: bool) -> void:
	if flights == null or clock == null:
		return
	var late := _late_counts()
	var progress := _progress_counts()
	_today_count = _count_today_live(flights, clock.tick)
	_sync_toggle()
	var entries := entries_for(flights, clock.tick, late, progress, passengers)
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
	_sync_header()
	if not force and entries == _entries:
		return
	if not force and _can_update_in_place(entries):
		_update_rows_in_place(entries)
		_entries = entries
		_set_lines(entries)
		return
	_entries = entries
	_set_lines(entries)
	_rebuild_rows(entries)


func _set_lines(entries: Array[Dictionary]) -> void:
	_lines = PackedStringArray()
	for entry in entries:
		_lines.append(entry["text"])


func _can_update_in_place(entries: Array[Dictionary]) -> bool:
	if entries.size() != _entries.size() or _rows.get_child_count() != entries.size():
		return false
	for i in entries.size():
		if not _row_shape_matches(_entries[i], entries[i]):
			return false
	return true


static func _row_shape_matches(prev: Dictionary, cur: Dictionary) -> bool:
	if prev["kind"] != cur["kind"]:
		return false
	if cur["kind"] != "row":
		return true
	return (
		prev["flight"] == cur["flight"]
		and prev["key"] == cur["key"]
		and prev["gate"] == cur["gate"]
		and prev.get("stand", prev["gate"]) == cur.get("stand", cur["gate"])
		and (prev["boarded_text"] != "") == (cur["boarded_text"] != "")
		and (prev["late"] != "") == (cur["late"] != "")
		and (_line_two_text(prev) != "") == (_line_two_text(cur) != "")
		and (prev["doors"] != "") == (cur["doors"] != "")
	)


func _update_rows_in_place(entries: Array[Dictionary]) -> void:
	for i in entries.size():
		var entry := entries[i]
		if entry["kind"] == "row":
			_update_row_in_place(_rows.get_child(i) as VBoxContainer, entry)
		else:
			var label := _rows.get_child(i) as Label
			if label.text != entry["text"]:
				label.text = entry["text"]


func _update_row_in_place(row_box: VBoxContainer, entry: Dictionary) -> void:
	var line_one := row_box.get_child(0) as HBoxContainer
	var head_label := line_one.get_child(0) as Label
	if head_label.text != entry["head"]:
		head_label.text = entry["head"]
	var boarded_str: String = entry["boarded_text"]
	if boarded_str != "":
		var boarded_label := line_one.get_child(1) as Label
		if boarded_label.text != boarded_str:
			boarded_label.text = boarded_str
	var line_two := _line_two_text(entry)
	var late_text: String = entry["late"]
	if late_text == "":
		if line_two != "":
			var airline := row_box.get_child(1) as Label
			if airline.text != line_two:
				airline.text = line_two
	else:
		var flow := row_box.get_child(1) as HFlowContainer
		var btn_idx := 0
		if line_two != "":
			var airline := flow.get_child(0) as Label
			if airline.text != line_two:
				airline.text = line_two
			btn_idx = 1
		var late_btn := flow.get_child(btn_idx) as Button
		if late_btn.text != late_text:
			late_btn.text = late_text
	var doors_text: String = entry["doors"]
	if doors_text != "":
		var doors := row_box.get_child(row_box.get_child_count() - 1) as Label
		if doors.text != doors_text:
			doors.text = doors_text


func _rebuild_rows(entries: Array[Dictionary]) -> void:
	_autowrap_labels.clear()
	_rows_pending_layout = true
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


func _add_row(entry: Dictionary) -> void:
	var row_box := VBoxContainer.new()
	row_box.name = "FlightRow_%s" % entry["flight"]
	row_box.add_theme_constant_override("separation", 1)
	var gate_id: String = entry["gate"]
	var stand_id := String(entry.get("stand", gate_id))
	if gate_id != "":
		row_box.mouse_filter = Control.MOUSE_FILTER_STOP
		row_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if stand_id != gate_id:
			row_box.tooltip_text = tr("Click to focus Gate {gate} → {stand}", "gate name").format(
				{"gate": gate_id, "stand": stand_id}
			)
		else:
			row_box.tooltip_text = tr("Click to focus Gate {gate}", "gate name").format(
				{"gate": gate_id}
			)
		row_box.gui_input.connect(_on_row_input.bind(gate_id))
	else:
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_one := HBoxContainer.new()
	line_one.name = "HeadRow_%s" % entry["flight"]
	line_one.add_theme_constant_override("separation", 6)
	line_one.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head_label := Label.new()
	head_label.text = entry["head"]
	head_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line_one.add_child(head_label)
	var boarded_str: String = entry["boarded_text"]
	if boarded_str != "":
		var boarded_label := Label.new()
		boarded_label.name = "Boarded_%s" % entry["flight"]
		boarded_label.text = boarded_str
		boarded_label.theme_type_variation = &"HudHint"
		boarded_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_one.add_child(boarded_label)
	row_box.add_child(line_one)
	_add_row_line_two(row_box, entry)
	if entry["doors"] != "":
		var doors := Label.new()
		doors.name = "DoorsClose"
		doors.text = entry["doors"]
		doors.theme_type_variation = &"HudHint"
		doors.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_box.add_child(doors)
	_rows.add_child(row_box)


static func _line_two_text(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	var gate_id := String(entry.get("gate", ""))
	var stand_id := String(entry.get("stand", gate_id))
	var remote := ""
	if gate_id != "" and stand_id != "" and stand_id != gate_id:
		remote = TranslationServer.translate("{gate} → {stand}").format(
			{"gate": gate_id, "stand": stand_id}
		)
	for part: String in [entry["airline"], remote, entry["status"]]:
		if part != "":
			parts.append(part)
	return "  ".join(parts)


func _add_row_line_two(row_box: VBoxContainer, entry: Dictionary) -> void:
	var key: String = entry["key"]
	var line_two := _line_two_text(entry)
	var late_text: String = entry["late"]
	var airline_name := "Airline_%s" % key if key != "" else "Airline"
	if late_text == "":
		if line_two != "":
			var airline := Label.new()
			airline.name = airline_name
			airline.text = line_two
			airline.theme_type_variation = &"HudHint"
			airline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			airline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row_box.add_child(airline)
			_autowrap_labels.append(airline)
		return
	var line := HFlowContainer.new()
	line.name = "LateRow_%s" % entry["flight"]
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("h_separation", 6)
	line.add_theme_constant_override("v_separation", 2)
	if line_two != "":
		var airline := Label.new()
		airline.name = airline_name
		airline.text = line_two
		airline.theme_type_variation = &"HudHint"
		airline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		airline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		airline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(airline)
		_autowrap_labels.append(airline)
	var late_btn := Button.new()
	late_btn.name = "Late_%s" % entry["flight"]
	late_btn.text = late_text
	late_btn.tooltip_text = tr("Follow the tightest running-late passenger")
	late_btn.focus_mode = Control.FOCUS_NONE
	var flight_id: String = entry["flight"]
	late_btn.pressed.connect(func() -> void: follow_late_requested.emit(flight_id))
	line.add_child(late_btn)
	row_box.add_child(line)
	late_btn.theme_type_variation = &"HudButtonCompact"


func _on_row_input(event: InputEvent, gate_id: String) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		focus_gate_requested.emit(gate_id)


func _on_header_late_pressed() -> void:
	if _tightest_late_flight != "":
		follow_late_requested.emit(_tightest_late_flight)


## Shared schedule-action helpers called by FlightPlanner and PlannerDrag.
static func move_choices(sim: FlightSim, contract_id: String, gates: Array[String]) -> Dictionary:
	var current := BusGatePairing.stand_id_of(sim.contract_of(contract_id))
	var fitting: Array[String] = []
	var any_other := false
	for gate_id in gates:
		if gate_id == current:
			continue
		any_other = true
		if sim.reassign_problem(contract_id, gate_id) == "":
			fitting.append(gate_id)
	return {"fitting": fitting, "any_other": any_other}


## Moves the contract to `gate_id` unless FlightSim refuses: {moved, text}.
static func move_outcome(sim: FlightSim, contract_id: String, gate_id: String) -> Dictionary:
	var problem := sim.reassign_problem(contract_id, gate_id)
	if problem != "":
		return {"moved": false, "text": reason_text(sim, problem, gate_id)}
	sim.reassign_gate(contract_id, gate_id)
	var moved_contract := sim.contract_of(contract_id)
	var destination: String = moved_contract["destination"]
	if BusGatePairing.is_remote_contract(moved_contract):
		return {
			"moved": true,
			"text":
			(
				TranslationServer
				. translate(
					"{destination} now uses stand {stand} (Bus {gate}) for the days not yet issued"
				)
				. format(
					{"destination": destination, "stand": gate_id, "gate": moved_contract["gate"]}
				)
			),
		}
	return {
		"moved": true,
		"text":
		(
			TranslationServer
			. translate("{destination} now uses gate {gate} for the days not yet issued")
			. format({"destination": destination, "gate": gate_id})
		),
	}


## The End confirm's question for `contract_id` (shared with FlightPlanner).
static func end_prompt(sim: FlightSim, contract_id: String) -> String:
	var fee := sim.end_fee(contract_id)
	if fee > 0:
		return TranslationServer.translate("End this contract? Exit fee ${fee}").format(
			{"fee": fee}
		)
	return TranslationServer.translate("End this contract?")


## Ends the contract as the player unless FlightSim now refuses, returning text.
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


func _on_snapshot_loaded() -> void:
	_manual_open = false
	_entries = []
	_late_key = []
	_progress_key = []
	_refresh(false)


static func reason_text(sim: FlightSim, reason: String, gate_id: String) -> String:
	var found := FlightLabel.parse_clash(reason)
	var busy := TranslationServer.translate("Gate {gate} is busy when this flight needs it")
	if found.is_empty():
		if reason.contains("has no bus gate"):
			return TranslationServer.translate("Stand {gate} has no free bus gate").format(
				{"gate": gate_id}
			)
		return busy.format({"gate": gate_id})
	var label := FlightLabel.parts(sim, found["is_flight"], found["id"])
	if label.is_empty():
		return busy.format({"gate": gate_id})
	var subject := TranslationServer.translate("Gate {gate}", "gate name").format(
		{"gate": found["gate"]}
	)
	if String(found["where"]).begins_with("at stand"):
		subject = TranslationServer.translate("Stand {gate}", "stand name").format(
			{"gate": found["gate"]}
		)
	elif found["where"] == "on the runway":
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


func _load_setting() -> bool:
	return HudFlagSetting.load_boot_flag(settings_path, SETTING_KEY, false, "DeparturesBoard")


func _save_setting() -> void:
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, _setting, "DeparturesBoard")
