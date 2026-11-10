class_name RunwayCard
extends CanvasLayer
## The runway upgrade card (Runway R9; ruling runway-upgrade-works-wait-for-a-
## timetable-gap-passengers-per-plane-class): a button in the centred top row
## (TopRow's middle slot, between the Build mode sign and Offers) opens a cream
## card with the runway's size and length, the next
## size with its price and how long the works take, the Upgrade button, and
## either what stops the upgrade (RunwayWorks.problem(): the build tier with the
## stars and passengers the game has, the money, or no quiet stretch) or, once
## bought, when the works start and end. Look follows the HUD theme of
## OfferPanel.
##
## Buying asks RunwayWorks.buy(), which books the works in the first clear
## stretch of the timetable; the card rebuilds when the size changes, the money
## changes, a tier opens, the works are booked and a game minute passes. It
## closes on Esc, when a build tool is picked and on a load.

const SHEET_W := TopRow.SHEET_W
## Ticks between refreshes while the sheet is open: the card shows clock times.
const REFRESH_TICKS := GameCalendar.TICKS_PER_MINUTE

@export var flights: FlightSim
@export var unlocks: BuildUnlocks
@export var finances: Finances
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode
## A successful load replaces the world the sheet describes, so it closes.
@export var save_game: SaveGame

var _button: Button
var _sheet: PanelContainer
var _current: Label
var _next: Label
var _schedule: Label
var _problem: Label
var _upgrade: Button
var _noted_tick := -REFRESH_TICKS


## The card's line for a runway of `size`: "Small runway, 384 m".
static func size_line(size: String) -> String:
	return "%s runway, %d m" % [size.capitalize(), int(Runway.length_m(size))]


## The card's line for the upgrade to `next`: size, length, price and the time
## the works take; "" for no next size.
static func next_line(next: String) -> String:
	if next == "":
		return ""
	@warning_ignore("integer_division")
	var hours := RunwayWorks.ticks(next) / (GameCalendar.TICKS_PER_MINUTE * 60)
	return (
		"Next: %s, $%d, works take %d %s"
		% [size_line(next), PriceTable.runway_price(next), hours, "hour" if hours == 1 else "hours"]
	)


func _ready() -> void:
	if flights == null or finances == null:
		push_error("RunwayCard: flights and finances must be set, so nothing is shown")
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = TopRow.SHEET_LAYER
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	flights.runway.size_changed.connect(_on_changed)
	finances.wallet.changed.connect(_on_changed)
	if unlocks != null:
		unlocks.tier_changed.connect(_on_changed)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	_refresh()


func _process(_delta: float) -> void:
	if _sheet.visible and flights.tick - _noted_tick >= REFRESH_TICKS:
		_refresh()


## Esc closes the sheet and is not passed on, so it does not also drop a tool.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _sheet.visible


func open() -> void:
	TopRow.close_others(self)
	_sheet.visible = true
	_refresh()


func close() -> void:
	_sheet.visible = false


func toggle_button() -> Button:
	return _button


func upgrade_button() -> Button:
	return _upgrade


func sheet() -> Control:
	return _sheet


## All the text on the sheet, one line per label, hidden labels left out.
func card_text() -> String:
	var lines := PackedStringArray()
	for label in [_current, _next, _schedule, _problem]:
		if (label as Label).visible:
			lines.append((label as Label).text)
	return "\n".join(lines)


## What stops the upgrade now, "" when it can be bought.
func problem_text() -> String:
	return _problem.text if _problem.visible else ""


## What the card says about the works, "" when none are booked.
func schedule_text() -> String:
	return _schedule.text if _schedule.visible else ""


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_current = Label.new()
	_next = Label.new()
	_schedule = Label.new()
	_problem = Label.new()
	_upgrade = Button.new()
	_button.name = "RunwayButton"
	_button.text = "Runway"
	_button.theme = BuildMenu.HUD_THEME
	TopRow.place_in_slot(_button, TopRow.RUNWAY_SLOT)
	_button.focus_mode = Control.FOCUS_NONE
	_button.theme_type_variation = &"HudButtonTeal"
	_button.pressed.connect(_on_toggle)
	add_child(_button)
	_sheet.name = "RunwaySheet"
	_sheet.theme = BuildMenu.HUD_THEME
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	TopRow.place_sheet(_sheet)
	add_child(_sheet)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_sheet.add_child(rows)
	var title := Label.new()
	title.name = "RunwayTitle"
	title.text = "Runway"
	_style_label(title, &"HudTitle")
	rows.add_child(title)
	for entry in [
		[_current, "RunwayCurrent", &"HudSmall"],
		[_next, "RunwayNext", &"HudSmall"],
		[_schedule, "RunwaySchedule", &"HudSmall"],
		[_problem, "RunwayProblem", &"HudProblemText"],
	]:
		var label: Label = entry[0]
		label.name = entry[1]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
		_style_label(label, entry[2])
		rows.add_child(label)
	_upgrade.name = "RunwayUpgrade"
	_upgrade.text = "Upgrade runway"
	_upgrade.focus_mode = Control.FOCUS_NONE
	_upgrade.theme_type_variation = &"HudButtonGreen"
	_upgrade.pressed.connect(_on_upgrade)
	rows.add_child(_upgrade)


func _refresh() -> void:
	_noted_tick = flights.tick
	var runway := flights.runway
	var next := RunwayWorks.next_size(runway.size)
	var refusal := RunwayWorks.problem(flights, unlocks, finances.wallet)
	_current.text = size_line(runway.size)
	_next.text = next_line(next)
	_next.visible = next != "" and not runway.works.scheduled()
	_schedule.text = RunwayWorks.schedule_text(runway.works, flights.tick)
	_schedule.visible = _schedule.text != ""
	_problem.text = refusal
	_problem.visible = refusal != "" and not runway.works.scheduled()
	_upgrade.disabled = refusal != ""
	_upgrade.visible = next != "" and not runway.works.scheduled()


func _on_toggle() -> void:
	if _sheet.visible:
		close()
	else:
		open()


func _on_upgrade() -> void:
	var refusal := RunwayWorks.buy(flights, unlocks, finances.wallet)
	_refresh()
	if refusal != "":
		_problem.text = refusal
		_problem.visible = true


## The card re-plans the timetable to name a start for the works, so a closed
## sheet leaves it be: every wallet change would otherwise cost a plan.
func _on_changed(_value: Variant = null) -> void:
	if _sheet.visible:
		_refresh()


func _on_tool_changed(_tool: BuildMode.Tool) -> void:
	close()


func _on_loaded(ok: bool) -> void:
	if ok:
		close()
		_refresh()


func _style_label(label: Label, variation: StringName) -> void:
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
