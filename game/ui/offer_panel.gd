class_name OfferPanel
extends CanvasLayer
## Today's airline offers (Economy 6/8b). A button at the top right shows how
## many offers are open; it opens a cream card sheet below it with one card per
## open offer: airline, destination, departure, gate, plane size, booked
## passengers and fee per passenger, with Accept and Decline. Look follows
## decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale: cream
## cards, a dark navy outline and text, a Toon accent per element.
##
## Accept asks FlightSim.accept_problem first, so a refusal (a gate clash, say)
## shows its reason on the sheet and the offer stays open; otherwise the board
## turns the offer into a contract. The sheet rebuilds whenever the board
## changes, so midnight expiry and the new day's offers appear on their own.
##
## While the desk's AirportRating is below RatingFormula.WARN_BELOW the airlines
## warn (decision airport-rating-1-5-stars-over-a-rolling-3-days-mostly-made-o):
## the sheet shows the warning with the low days left before contracts end, the
## button turns coral and carries the same text as its tooltip, so it is seen
## with the sheet closed. It follows the rating's changed signal and does not
## rebuild the cards.
##
## While the sheet is open the game clock is paused (decision the-airline-offers-
## panel-pauses-the-game-while-it-is-open); closing it gives back the speed the
## player had, paused included, unless the player picked another speed while it
## was open. The sheet closes on Esc and when a build tool is picked.
##
## A card says "first flight tomorrow" when the sim would not fly today's slot
## (FlightTimetable.first_day), once the airport is open.

const SHEET_W := 560.0
const TOP := 12.0
## The panel sits at the top, left of PassengerHud's 440 px flight panel (which
## starts 460 px from the right edge).
const RIGHT_CLEARANCE := 472.0
const CARD_TEXT_W := 380.0
const EMPTY_TEXT := "No offers right now. New offers arrive at midnight."

@export var desk: OfferDesk
@export var flights: FlightSim
## Paused while the sheet is open; null leaves the clock alone.
@export var clock: SimClock
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode

var _button: Button
var _sheet: PanelContainer
var _cards: VBoxContainer
var _message: Label
var _warning: Label
var _notice: Label
var _offers_waiting := false
var _card_nodes: Dictionary = {}
var _accept_buttons: Dictionary = {}
var _decline_buttons: Dictionary = {}
var _departs_labels: Dictionary = {}
var _noted_tick := -1
## True from open() until the player changes the clock or the sheet closes.
var _holding_clock := false
var _held_paused := false
var _held_speed := 1


## The airlines' warning once the rating is low: `low_days` day ends have
## already been low, and contracts end at RatingFormula.LOW_DAYS_TO_END.
static func warning_message(low_days: int) -> String:
	var text := (
		"Airlines are warning you: the airport rating is below %d stars."
		% int(RatingFormula.WARN_BELOW)
	)
	var left := RatingFormula.LOW_DAYS_TO_END - low_days
	if left > 0:
		text += " Contracts end after %d more low %s." % [left, "day" if left == 1 else "days"]
	return text


## What the player is told when an airline leaves because the rating stayed low.
static func ended_message(airline: String, destination: String) -> String:
	var text := (
		"%s to %s has ended its contract: the airport rating stayed low." % [airline, destination]
	)
	return text + " Flights already issued still fly; no new days will."


## Says when the first flight is if it is not today: "" when the sim would fly
## today's slot (FlightTimetable.first_day is today), else "first flight
## tomorrow" or, past that, "first flight on Day N" (the HUD's day number).
static func first_flight_note(offer: Dictionary, now: int) -> String:
	var first_day := FlightTimetable.first_day(offer, now)
	var ahead := first_day - GameCalendar.day_of(now)
	if ahead <= 0:
		return ""
	return "first flight tomorrow" if ahead == 1 else "first flight on Day %d" % (first_day + 1)


## The text lines of an offer's card: who and where, when and what plane, and
## the money. `note` (first_flight_note) follows the departure when not empty.
static func card_lines(offer: Dictionary, note := "") -> PackedStringArray:
	var minute: int = offer["departure_minute"]
	var time := GameCalendar.clock_text(GameCalendar.tick_at(0, minute))
	var size: String = offer["plane_size"]
	var then := ", %s" % note if note != "" else ""
	return PackedStringArray(
		[
			"%s to %s" % [offer["airline"], offer["destination"]],
			(
				"Departs %s daily%s   Gate %s   %s plane"
				% [time, then, offer["gate"], size.capitalize()]
			),
			(
				"%d passengers booked   $%d per passenger"
				% [offer["booked_passengers"], offer["fee_per_passenger"]]
			),
		]
	)


func _ready() -> void:
	if desk == null or flights == null:
		push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = 2
	_build()
	desk.board.changed.connect(_refresh)
	if desk.rating != null:
		desk.rating.changed.connect(_refresh_warning)
	desk.contract_ended.connect(_on_contract_ended)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
	_refresh()
	_refresh_warning()


func _process(_delta: float) -> void:
	if not _sheet.visible:
		return
	if _holding_clock and (not clock.paused or clock.speed != _held_speed):
		_holding_clock = false
	if flights.tick != _noted_tick:
		_refresh_notes()


## Esc closes the sheet and is not passed on, so it does not also drop a tool.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _sheet.visible


## Shows the sheet and pauses the clock, remembering how the player had it.
func open() -> void:
	if _sheet.visible:
		return
	_sheet.visible = true
	_refresh_notes()
	if clock != null:
		_held_paused = clock.paused
		_held_speed = clock.speed
		clock.set_paused(true)
		_holding_clock = true


## Hides the sheet and gives back the paused state the player had, unless they
## changed the clock while it was open.
func close() -> void:
	if not _sheet.visible:
		return
	_sheet.visible = false
	if clock == null or not _holding_clock:
		return
	_holding_clock = false
	if not clock.paused or clock.speed != _held_speed:
		return
	clock.set_paused(_held_paused)


func toggle_button() -> Button:
	return _button


## Ids of the offers shown, in the order drawn.
func card_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _card_nodes:
		ids.append(id)
	return ids


func card(id: String) -> Control:
	return _card_nodes.get(id)


func accept_button(id: String) -> Button:
	return _accept_buttons.get(id)


func decline_button(id: String) -> Button:
	return _decline_buttons.get(id)


## All the text on one offer's card.
func card_text(id: String) -> String:
	var lines := PackedStringArray()
	for label in _card_nodes[id].find_children("*", "Label", true, false):
		lines.append((label as Label).text)
	return "\n".join(lines)


## The airlines' warning shown on the sheet, "" when the rating is fine.
func warning_text() -> String:
	return _warning.text


func warning_label() -> Label:
	return _warning


## The last airline to end its contract, shown under the warning until the
## rating recovers, "" when none has (it is not saved, so a load clears it).
func notice_text() -> String:
	return _notice.text


func notice_label() -> Label:
	return _notice


## What the sheet says under the cards: the last accept's result or refusal,
## or EMPTY_TEXT when no offer is open.
func message() -> String:
	return _message.text


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_cards = VBoxContainer.new()
	_message = Label.new()
	_warning = Label.new()
	_notice = Label.new()
	var column := VBoxContainer.new()
	column.name = "OfferColumn"
	column.theme = BuildMenu.HUD_THEME
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size = Vector2(SHEET_W, 0.0)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	column.offset_right = -RIGHT_CLEARANCE
	column.offset_left = -RIGHT_CLEARANCE - SHEET_W
	column.offset_top = TOP
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(column)
	_button.name = "OffersButton"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.custom_minimum_size = Vector2(170.0, 40.0)
	_button.focus_mode = Control.FOCUS_NONE
	_button.theme_type_variation = &"HudButtonTeal"
	_button.pressed.connect(_on_toggle)
	column.add_child(_button)
	_sheet.name = "OfferSheet"
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_sheet)
	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 6)
	_sheet.add_child(sheet_column)
	var title := Label.new()
	title.name = "OfferTitle"
	title.text = "Today's offers"
	_style_label(title, &"HudTitle")
	sheet_column.add_child(title)
	_warning.name = "OfferWarning"
	_warning.visible = false
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(_warning, &"HudProblemText")
	sheet_column.add_child(_warning)
	_notice.name = "OfferNotice"
	_notice.visible = false
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(_notice, &"HudProblemText")
	sheet_column.add_child(_notice)
	_cards.name = "OfferCards"
	_cards.add_theme_constant_override("separation", 6)
	sheet_column.add_child(_cards)
	_message.name = "OfferMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(_message, &"HudSmall")
	sheet_column.add_child(_message)


func _on_toggle() -> void:
	if _sheet.visible:
		close()
	else:
		open()


func _on_tool_changed(_tool: BuildMode.Tool) -> void:
	close()


## Rebuilds the cards and the button text from the board's open offers.
func _refresh() -> void:
	for node in _card_nodes.values():
		_cards.remove_child(node)
		node.queue_free()
	_card_nodes.clear()
	_accept_buttons.clear()
	_decline_buttons.clear()
	_departs_labels.clear()
	var offers := desk.board.open_offers()
	for offer in offers:
		_add_card(offer)
	_button.text = "Offers (%d)" % offers.size()
	_offers_waiting = offers.size() > 0
	_style_button()
	_say(EMPTY_TEXT if offers.is_empty() else "")
	_noted_tick = flights.tick


## The first-flight note for an offer card right now: "" while the airport is
## closed, because a contract accepted then starts at the opening.
func _note_for(offer: Dictionary) -> String:
	if flights.opened_tick < 0:
		return ""
	return first_flight_note(offer, flights.tick)


## Rewrites each card's departure line for the sim's current tick.
func _refresh_notes() -> void:
	_noted_tick = flights.tick
	for id in _departs_labels:
		var offer := desk.board.offer_of(id)
		(_departs_labels[id] as Label).text = card_lines(offer, _note_for(offer))[1]


## Shows or clears the airlines' warning from the rating, on the sheet and as
## the button's tooltip.
func _refresh_warning() -> void:
	var rating := desk.rating
	var text := ""
	if rating != null and rating.warning():
		text = warning_message(rating.low_days())
	_warning.text = text
	_warning.visible = text != ""
	if text == "":
		_set_notice("")
	else:
		_button.tooltip_text = text if _notice.text == "" else "%s\n%s" % [text, _notice.text]
	_style_button()


func _on_contract_ended(contract: Dictionary) -> void:
	_set_notice(ended_message(contract["airline"], contract["destination"]))
	_refresh_warning()


## Shows `text` as the ending notice, hiding the line when it is empty.
func _set_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = text != ""
	if text == "":
		_button.tooltip_text = ""


## Coral while the airlines warn, yellow while offers wait, else teal.
func _style_button() -> void:
	if _warning.visible:
		_button.theme_type_variation = &"HudButtonCoral"
	elif _offers_waiting:
		_button.theme_type_variation = &"HudButtonYellow"
	else:
		_button.theme_type_variation = &"HudButtonTeal"


func _add_card(offer: Dictionary) -> void:
	var id: String = offer["id"]
	var card_box := PanelContainer.new()
	card_box.name = "Offer_%s" % id
	card_box.theme_type_variation = &"HudSubCard"
	_cards.add_child(card_box)
	_card_nodes[id] = card_box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var lines := card_lines(offer, _note_for(offer))
	for i in lines.size():
		var label := Label.new()
		if i == 1:
			_departs_labels[id] = label
		label.text = lines[i]
		label.custom_minimum_size = Vector2(CARD_TEXT_W, 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_label(label, &"HudTitle" if i == 0 else &"HudSmall")
		texts.add_child(label)
	var buttons := VBoxContainer.new()
	row.add_child(buttons)
	var accept := _card_button("Accept", &"HudButtonGreen", id)
	accept.pressed.connect(_on_accept.bind(id))
	buttons.add_child(accept)
	_accept_buttons[id] = accept
	var decline := _card_button("Decline", &"HudButtonCoral", id)
	decline.pressed.connect(_on_decline.bind(id))
	buttons.add_child(decline)
	_decline_buttons[id] = decline


func _card_button(text: String, variation: StringName, id: String) -> Button:
	var button := Button.new()
	button.name = "%s_%s" % [text, id]
	button.text = text
	button.custom_minimum_size = Vector2(110.0, 36.0)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = variation
	return button


func _on_accept(id: String) -> void:
	var offer := desk.board.offer_of(id)
	var problem := flights.accept_problem(OfferBoard.terms_of(offer))
	if problem != "":
		_say(
			"Can't accept %s to %s: %s" % [offer["airline"], offer["destination"], problem],
			&"HudProblemText"
		)
		return
	if desk.board.accept(id, flights):
		_say("Accepted %s to %s" % [offer["airline"], offer["destination"]])


## Shows `text` under the cards, hiding the line when it is empty.
func _say(text: String, variation := &"HudSmall") -> void:
	_message.text = text
	_message.visible = text != ""
	_message.theme_type_variation = variation


func _on_decline(id: String) -> void:
	desk.board.decline(id)


func _style_label(label: Label, variation: StringName) -> void:
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
