class_name FlightResultPanel
extends PanelContainer
## The result of one flight, a green card on the right rail (AlertStack,
## decision hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra, part
## 5): made, missed and the main reasons passengers missed. PassengerHud makes
## one when a flight's doors close and posts it to the rail, which takes it
## down after SHOW_SECONDS of real time or on a click and keeps its text in the
## alerts history. Its Dismiss button takes it down too.

## The Dismiss button was pressed.
signal dismissed

## The most reasons listed; the rest are summed into one "Other" row, so the
## rows add up to every reason.
const MAX_REASONS := 3
## Real seconds the card stays on the rail, also while the game is paused.
const SHOW_SECONDS := 20.0

var _label := Label.new()


func _init() -> void:
	name = "FlightResultPanel"
	visible = false
	custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	theme = BuildMenu.HUD_THEME
	add_theme_stylebox_override("panel", green_card())
	var column := VBoxContainer.new()
	add_child(column)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	var dismiss := Button.new()
	dismiss.name = "DismissResult"
	dismiss.text = "Dismiss"
	dismiss.size_flags_horizontal = Control.SIZE_SHRINK_END
	dismiss.focus_mode = Control.FOCUS_NONE
	# A normal action, so teal; yellow means needs-you (decision
	# hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).
	dismiss.theme_type_variation = &"HudButtonTeal"
	dismiss.pressed.connect(dismiss_result)
	column.add_child(dismiss)


## The theme's card (border, corners, margins, shadow) in the theme's green,
## the colour for good news (decision 0b50e074). The theme has no green card
## variation, so the card takes the green of its green button.
static func green_card() -> StyleBoxFlat:
	var theme := BuildMenu.HUD_THEME
	var card := theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	card.bg_color = (theme.get_stylebox("normal", "HudButtonGreen") as StyleBoxFlat).bg_color
	return card


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


func show_result(summary: Dictionary) -> void:
	_label.text = text_for(summary)
	visible = true


func dismiss_result() -> void:
	visible = false
	dismissed.emit()


func result_text() -> String:
	return _label.text
