class_name FlightResultPanel
extends PanelContainer
## The result of one flight, a card on the right rail (AlertStack, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra, part 5):
## made, missed, last-second saves and the main reasons passengers missed,
## coloured like IncidentCards (ed443eea): green on zero misses, cream when more
## made than missed, coral when missed >= made. PassengerHud makes one when a
## flight's doors close and posts it to the rail, which takes it down after
## SHOW_SECONDS of real time or on a click and keeps its text in the alerts
## history. Its Dismiss button takes it down too.

## The Dismiss button was pressed.
signal dismissed

## The most reasons listed; the rest are summed into one "Other" row, so the
## rows add up to every reason.
const MAX_REASONS := 3
## Real seconds the card stays on the rail, also while the game is paused.
const SHOW_SECONDS := 20.0

var _label := Label.new()
var _dismiss := Button.new()
var _last_summary: Dictionary = {}


func _init() -> void:
	name = "FlightResultPanel"
	visible = false
	custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	theme = BuildMenu.HUD_THEME
	theme_type_variation = &"HudCardGreen"
	var column := VBoxContainer.new()
	add_child(column)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	_dismiss.name = "DismissResult"
	_dismiss.text = tr("Dismiss")
	_dismiss.size_flags_horizontal = Control.SIZE_SHRINK_END
	_dismiss.focus_mode = Control.FOCUS_NONE
	# A normal action, so teal; yellow means needs-you (decision
	# hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale).
	_dismiss.theme_type_variation = &"HudButtonTeal"
	_dismiss.pressed.connect(dismiss_result)
	column.add_child(_dismiss)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_dismiss.text = tr("Dismiss")
		if not _last_summary.is_empty():
			show_result(_last_summary)


## The theme's HudCardGreen look (the card in the green of HudButtonGreen, the
## colour for good news, decision 0b50e074), for tests and probes to compare
## against. The card itself takes it through its theme type variation.
static func green_card() -> StyleBoxFlat:
	return BuildMenu.HUD_THEME.get_stylebox("panel", "HudCardGreen") as StyleBoxFlat


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
			return TranslationServer.translate("{airline} {destination}").format(
				{"airline": contract["airline"], "destination": contract["destination"]}
			)
	return flight_title(flight_id)


## The panel's theme type variation for a FlightResult.summarize() dictionary,
## matching IncidentCards (ed443eea): coral when zero passengers made it or
## missed >= made, green on zero misses (with made > 0), cream when more made
## than missed.
static func variation_for(summary: Dictionary) -> StringName:
	var made: int = int(summary.get("made", 0))
	var missed: int = int(summary.get("missed", 0))
	if made <= 0:
		return &"HudCardCoral"
	if missed <= 0:
		return &"HudCardGreen"
	if made > missed:
		return &""
	return &"HudCardCoral"


## The panel's text for a FlightResult.summarize() dictionary. A "title" key,
## when present, replaces the flight number in the heading.
static func text_for(summary: Dictionary) -> String:
	var lines := PackedStringArray(
		[
			TranslationServer.translate("{title} result").format(
				{"title": summary.get("title", flight_title(summary["flight"]))}
			),
			TranslationServer.translate("Made {made}   Missed {missed}").format(
				{"made": summary["made"], "missed": summary["missed"]}
			),
		]
	)
	var close_calls: int = int(summary.get("close_calls", 0))
	if close_calls > 0:
		lines.append(
			(
				TranslationServer
				. translate_plural(
					"{count} made it at the last second!",
					"{count} made it at the last second!",
					close_calls
				)
				. format({"count": close_calls})
			)
		)
	var reasons: Array = summary["reasons"]
	for i in mini(reasons.size(), MAX_REASONS):
		lines.append(
			TranslationServer.translate("{count}  {reason}").format(
				{"count": reasons[i]["count"], "reason": reasons[i]["text"]}
			)
		)
	var other := 0
	for i in range(MAX_REASONS, reasons.size()):
		other += reasons[i]["count"]
	if other > 0:
		lines.append(TranslationServer.translate("{count}  Other").format({"count": other}))
	return "\n".join(lines)


func show_result(summary: Dictionary) -> void:
	_last_summary = summary.duplicate()
	theme_type_variation = variation_for(summary)
	_label.text = text_for(summary)
	visible = true


func dismiss_result() -> void:
	visible = false
	dismissed.emit()


func result_text() -> String:
	return _label.text
