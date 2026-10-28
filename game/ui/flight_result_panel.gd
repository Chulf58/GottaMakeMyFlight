class_name FlightResultPanel
extends PanelContainer
## The result of one flight, shown by PassengerHud when its doors close: made,
## missed and the main reasons passengers missed. Hidden until shown, then
## dismissed with its button or, failing that, when the game day changes.

## The most reasons listed; the rest are summed into one "Other" row, so the
## rows add up to every reason.
const MAX_REASONS := 3
const WIDTH := 440.0

var _label := Label.new()
## The game day the card was shown on; it is stale once the day moves on.
var _day := 0


func _init() -> void:
	name = "FlightResultPanel"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0.0)
	theme = BuildMenu.HUD_THEME
	var column := VBoxContainer.new()
	add_child(column)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	var dismiss := Button.new()
	dismiss.name = "DismissResult"
	dismiss.text = "Dismiss"
	dismiss.size_flags_horizontal = Control.SIZE_SHRINK_END
	dismiss.focus_mode = Control.FOCUS_NONE
	# The panel's accent: it waits for the player to dismiss it.
	dismiss.theme_type_variation = &"HudButtonYellow"
	dismiss.pressed.connect(dismiss_result)
	column.add_child(dismiss)


## The flight number a player knows: a daily occurrence id ("GMF101-d0") shows
## as its contract ("GMF101"); any other id is shown as it is. Display only.
static func flight_title(flight_id: String) -> String:
	var parsed := FlightTimetable.parse_occurrence(flight_id)
	return parsed["contract"] if not parsed.is_empty() else flight_id


## The title a flight's card carries: a contract flight reads "Airline
## Destination" ("Sunhop Lisbon"), not its internal offer id; a one-off flight
## (the starter) keeps its flight number. Display only.
static func title_for(flights: FlightSim, flight_id: String) -> String:
	var parsed := FlightTimetable.parse_occurrence(flight_id)
	if flights != null and not parsed.is_empty():
		var contract := flights.contract_of(parsed["contract"])
		if not contract.is_empty():
			return "%s %s" % [contract["airline"], contract["destination"]]
	return flight_title(flight_id)


## The panel's text for a FlightResult.summarize() dictionary. A "title" key,
## when present, replaces the flight number in the heading.
static func text_for(summary: Dictionary) -> String:
	var lines := PackedStringArray(
		[
			"%s result" % summary.get("title", flight_title(summary["flight"])),
			"Made %d   Missed %d" % [summary["made"], summary["missed"]],
		]
	)
	var reasons: Array = summary["reasons"]
	for i in mini(reasons.size(), MAX_REASONS):
		lines.append("%d  %s" % [reasons[i]["count"], reasons[i]["text"]])
	var other := 0
	for i in range(MAX_REASONS, reasons.size()):
		other += reasons[i]["count"]
	if other > 0:
		lines.append("%d  Other" % other)
	return "\n".join(lines)


func show_result(summary: Dictionary, day: int) -> void:
	_label.text = text_for(summary)
	_day = day
	visible = true


## Hides the card once `today` is not the day it was shown on.
func expire_on_new_day(today: int) -> void:
	if visible and today != _day:
		dismiss_result()


func dismiss_result() -> void:
	visible = false


func result_text() -> String:
	return _label.text
