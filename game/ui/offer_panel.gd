class_name OfferPanel
extends CanvasLayer
## Today's airline offers (Economy 6/8b). A button in the centred top row
## (TopRow's last slot) shows how many offers are open; it opens a cream card
## sheet below the row with one card per
## open offer: airline, destination, departure, plane size, booked
## passengers and fee per passenger, with Accept and Decline. No gate is named:
## the player builds the terminal, which has none to name. Look follows
## decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale: cream
## cards, a dark navy outline and text, a Toon accent per element.
##
## Accept asks FlightSim.accept_problem first, so a refusal (a gate clash, say)
## shows its reason on that offer's own card and the offer stays open; otherwise the board
## turns the offer into a contract. The sheet rebuilds whenever the board
## changes, so midnight expiry and the new day's offers appear on their own.
##
## While the desk's AirportRating is below RatingFormula.WARN_BELOW the airlines
## warn (decision airport-rating-1-5-stars-over-a-rolling-3-days-mostly-made-o):
## a coral card on the right rail (AlertStack.post_notice, HUD 6/7, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra part 6) says so
## with the low days left before contracts end, the button turns coral and
## carries the same text as its tooltip. The card stays until clicked and goes
## when the rating recovers; it follows the rating's changed signal, is posted
## again only when its words change and does not rebuild the cards. An airline
## ending its contract posts a second coral card that stays until clicked. The
## sheet itself shows only offers; a clash refusal stays on its offer's sheet.
##
## While the sheet is open the game clock is paused (decision the-airline-offers-
## panel-pauses-the-game-while-it-is-open); closing it gives back the speed the
## player had, paused included, unless the player picked another speed while it
## was open. The sheet closes on Esc and when a build tool is picked.
##
## A card says "first flight tomorrow" when the sim would not fly today's slot
## (FlightTimetable.first_day), once the airport is open.
##
## Each card has a fit line before Accept (decision airline-offers-2-a-day-fit-
## the-free-gate-slots-1-needs-more, point 6): FlightFit's words for whether
## the offer fits now and why not, in the good-text look when it fits and the
## problem look when not, at the small text size. It is advice, kept apart from
## the click refusal: it is worked out again when the sheet opens, when the
## cards rebuild (an accept, a decline, a new day, a load), when a contract
## ends, and on FlightSim.planning_changed (the gates, their stands, the runway
## or its works), which the open sheet checks for every frame because those
## change while the clock is paused under it.

const SHEET_W := TopRow.SHEET_W
const CARD_TEXT_W := 380.0
## Index of the first-flight note line in a card's lines (under the departure).
const NOTE_LINE := 2
## Rail keys, and the history titles, of the two coral notices.
const WARNING_KEY := &"offer_warning"
const ENDED_KEY := &"offer_ended"
const WARNING_TITLE := "Low airport rating"
const ENDED_TITLE := "Contract ended"
const EMPTY_TEXT := "No offers right now. New offers arrive at midnight."

@export var desk: OfferDesk
@export var flights: FlightSim
## Paused while the sheet is open; null leaves the clock alone.
@export var clock: SimClock
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode
## A successful load replaces the world the sheet was opened over, so it closes.
@export var save_game: SaveGame
## The right rail the warning and ending notices go on; null finds the one in
## AlertStack.GROUP (the HUD builds it, so the scene does not wire it).
var alerts: AlertStack

var _button: Button
var _sheet: PanelContainer
var _cards: VBoxContainer
var _message: Label
## The warning as the rating words it now, and as the card on the rail words it
## ("" while none is up); the ending line the tooltip adds under the warning.
var _warning_text := ""
var _warning_posted := ""
## Instance id of the rail the warning was posted to (0 before any).
var _posted_rail := 0
## The rail whose reset_done this panel listens to (only ever one).
var _watched_rail: AlertStack
var _ended_text := ""
var _offers_waiting := false
var _card_nodes: Dictionary = {}
var _accept_buttons: Dictionary = {}
var _decline_buttons: Dictionary = {}
var _note_labels: Dictionary = {}
var _refusal_labels: Dictionary = {}
var _fit_labels: Dictionary = {}
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


## Ticks a contract accepted while the airport is closed needs between the
## airport opening and its departure to fly the first day's slot: the issue
## lead plus the preparation before departure (FlightTimetable.opening_day).
static func opening_lead_ticks() -> int:
	return FlightTimetable.ISSUE_LEAD_TICKS + FlightTimetable.departure_offset()


## `ticks` as "2 h 50 min", "45 min" or "3 h", rounded up to a whole minute.
static func lead_text(ticks: int) -> String:
	var minutes := -GameCalendar.floor_div(-ticks, GameCalendar.TICKS_PER_MINUTE)
	var parts: PackedStringArray = []
	if minutes >= 60:
		parts.append("%d h" % (minutes / 60))
	if minutes % 60 != 0:
		parts.append("%d min" % (minutes % 60))
	return " ".join(parts)


## The text lines of an offer's card: who and where, when, the plane, and the
## money. `note` (first_flight_note) gets its own line under the departure when
## not empty, so no line wraps. A card without a note has 4 lines, with one 5.
static func card_lines(offer: Dictionary, note := "") -> PackedStringArray:
	var minute: int = offer["departure_minute"]
	var time := GameCalendar.clock_text(GameCalendar.tick_at(0, minute))
	var size: String = offer["plane_size"]
	var lines := PackedStringArray(
		[
			"%s to %s" % [offer["airline"], offer["destination"]],
			"Departs %s daily" % time,
			"%s plane" % size.capitalize(),
			(
				"%d passengers booked   $%d per passenger"
				% [offer["booked_passengers"], offer["fee_per_passenger"]]
			),
		]
	)
	if note != "":
		lines.insert(NOTE_LINE, note_line(note))
	return lines


## A first-flight note as it reads on a line of its own.
static func note_line(note: String) -> String:
	return note.left(1).to_upper() + note.substr(1)


func _ready() -> void:
	if desk == null or flights == null:
		push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = TopRow.SHEET_LAYER
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	desk.board.changed.connect(_refresh)
	if desk.rating != null:
		desk.rating.changed.connect(_refresh_warning)
	desk.contract_ended.connect(_on_contract_ended)
	flights.planning_changed.connect(_refresh_fits)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	_refresh()
	_refresh_warning()


func _process(_delta: float) -> void:
	if not _sheet.visible:
		return
	if _holding_clock and (not clock.paused or clock.speed != _held_speed):
		_holding_clock = false
	if flights.tick != _noted_tick:
		_refresh_notes()
	flights.check_planning_changed()


## Esc closes the sheet and is not passed on, so it does not also drop a tool.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _sheet.visible


## The open sheet's card, or null before the panel has built itself.
func sheet() -> Control:
	return _sheet


## Shows the sheet and pauses the clock, remembering how the player had it.
func open() -> void:
	if _sheet.visible:
		return
	TopRow.close_others(self)
	_sheet.visible = true
	_refresh_notes()
	flights.check_planning_changed()
	_refresh_fits()
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
	_clear_refusals()
	_say_idle()
	_restore_clock()


## A panel that leaves the tree while open must not leave the game paused.
func _exit_tree() -> void:
	_restore_clock()


func _restore_clock() -> void:
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
		if (label as Label).visible:
			lines.append((label as Label).text)
	return "\n".join(lines)


## The airlines' warning, as the Offers button's tooltip says it; "" when the
## rating is fine.
func warning_text() -> String:
	return _warning_text


## The refusal shown on offer `id`'s own card (a clash, say), "" when it shows
## none.
func refusal_text(id: String) -> String:
	return (_refusal_labels[id] as Label).text


func refusal_label(id: String) -> Label:
	return _refusal_labels[id]


## The fit line on offer `id`'s card (FlightFit.text): advice that Accept
## checks again at the click.
func fit_text(id: String) -> String:
	return (_fit_labels[id] as Label).text


func fit_label(id: String) -> Label:
	return _fit_labels[id]


## What the sheet says under the cards: the last accept's confirmation, or
## EMPTY_TEXT when no offer is open. A refusal is on its card, not here.
func message() -> String:
	return _message.text


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_cards = VBoxContainer.new()
	_message = Label.new()
	_button.name = "OffersButton"
	_button.theme = BuildMenu.HUD_THEME
	TopRow.place_in_slot(_button, TopRow.OFFERS_SLOT)
	_button.focus_mode = Control.FOCUS_NONE
	_button.theme_type_variation = &"HudButtonTeal"
	_button.pressed.connect(_on_toggle)
	add_child(_button)
	_sheet.name = "OfferSheet"
	_sheet.theme = BuildMenu.HUD_THEME
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	TopRow.place_sheet(_sheet)
	add_child(_sheet)
	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 6)
	_sheet.add_child(sheet_column)
	var title := Label.new()
	title.name = "OfferTitle"
	title.text = "Today's offers"
	_style_label(title, &"HudTitle")
	sheet_column.add_child(title)
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


## The loaded clock is the player's now, so the sheet closes without restoring
## the state it held from before the load.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	_holding_clock = false
	close()
	# The ending notice is not saved. The rail's own reset (reset_done) posts a
	# warning still due once, whichever of the two handlers runs first, so this
	# only drops the ending and lets the warning follow the loaded rating.
	var rail := _rail()
	if rail != null:
		rail.drop_notice(ENDED_KEY)
	_ended_text = ""
	_refresh_warning.call_deferred()


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
	_note_labels.clear()
	_refusal_labels.clear()
	_fit_labels.clear()
	var offers := desk.board.open_offers()
	for offer in offers:
		_add_card(offer)
	_button.text = "Offers (%d)" % offers.size()
	_offers_waiting = offers.size() > 0
	_style_button()
	_say_idle()
	_noted_tick = flights.tick


## The first-flight note for an offer card right now. While the airport is
## closed a contract accepted starts at the opening, which is not known yet, so
## the note names the lead its slot needs after the opening.
func _note_for(offer: Dictionary) -> String:
	if flights.opened_tick < 0:
		return "first flight %s after opening" % lead_text(opening_lead_ticks())
	return first_flight_note(offer, flights.tick)


## Rewrites each card's note line for the sim's current tick, hiding it while
## there is no note.
func _refresh_notes() -> void:
	_noted_tick = flights.tick
	for id in _note_labels:
		_set_note(_note_labels[id], _note_for(desk.board.offer_of(id)))


func _set_note(label: Label, note: String) -> void:
	label.text = note_line(note)
	label.visible = note != ""


## Rewrites each card's fit line for the sim as it is now.
func _refresh_fits() -> void:
	for id: String in _fit_labels:
		_set_fit(_fit_labels[id], desk.board.offer_of(id))


func _set_fit(label: Label, offer: Dictionary) -> void:
	var assessment := FlightFit.assess(flights, OfferBoard.terms_of(offer))
	label.text = FlightFit.text(assessment, offer["plane_size"])
	label.theme_type_variation = &"HudGoodText" if assessment["fits"] else &"HudProblemText"
	# HudGoodText is larger than the card's other small lines; both looks keep
	# the HudSmall size.
	label.add_theme_font_size_override(
		"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
	)


## Posts or drops the airlines' warning card from the rating, and words the
## button's tooltip. A card is posted again only when its words change, so a
## card the player clicked away stays away until the low-day count moves on.
func _refresh_warning() -> void:
	var rating := desk.rating
	_warning_text = ""
	if rating != null and rating.warning():
		_warning_text = warning_message(rating.low_days())
	var rail := _rail()
	if _warning_text == "":
		_ended_text = ""
		_button.tooltip_text = ""
		_warning_posted = ""
		if rail != null:
			rail.drop_notice(WARNING_KEY)
	else:
		_button.tooltip_text = (
			_warning_text if _ended_text == "" else "%s\n%s" % [_warning_text, _ended_text]
		)
		if rail != null and _warning_text != _warning_posted:
			_warning_posted = _warning_text
			_post(rail, WARNING_KEY, WARNING_TITLE, _warning_text)
	_style_button()


func _on_contract_ended(contract: Dictionary) -> void:
	_ended_text = ended_message(contract["airline"], contract["destination"])
	var rail := _rail()
	if rail == null:
		push_warning("OfferPanel: no alert rail to tell the player: %s" % _ended_text)
	else:
		_post(rail, ENDED_KEY, ENDED_TITLE, _ended_text)
	_refresh_warning()
	_refresh_fits()


## The right rail, found through its group the first time it is needed. A rail
## other than the one the warning was posted to starts the warning again: it has
## no card, and the old rail's click dismissal does not carry over.
func _rail() -> AlertStack:
	if not is_instance_valid(alerts):
		alerts = get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack
	if alerts != null and alerts.get_instance_id() != _posted_rail:
		if (
			is_instance_valid(_watched_rail)
			and _watched_rail.reset_done.is_connected(_on_rail_reset)
		):
			_watched_rail.reset_done.disconnect(_on_rail_reset)
		_watched_rail = alerts
		_posted_rail = alerts.get_instance_id()
		_warning_posted = ""
		alerts.reset_done.connect(_on_rail_reset)
	return alerts


## The rail dropped every card (a load or a new world): the warning, if the
## rating still calls for one, goes up again.
func _on_rail_reset() -> void:
	_warning_posted = ""
	_refresh_warning()


## A coral notice that stays on the rail until clicked, with its history line.
static func _post(rail: AlertStack, key: StringName, title: String, detail: String) -> void:
	rail.post_notice(key, coral_card(key, title, detail), 0.0, title, detail)


## A rail card in the theme's HudCardCoral look (coral means a problem, decision
## 0b50e074): a title over the words, RAIL_W wide like the other cards.
static func coral_card(key: StringName, title: String, detail: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "OfferNotice_%s" % key
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudCardCoral"
	card.custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	for part in [[title, &"HudCardName"], [detail, &"HudSmall"]]:
		var label := Label.new()
		label.text = part[0]
		label.theme_type_variation = part[1]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	return card


## Coral while the airlines warn, yellow while offers wait, else teal.
func _style_button() -> void:
	if _warning_text != "":
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
	var lines := card_lines(offer)
	for i in lines.size():
		texts.add_child(_card_label(lines[i], &"HudTitle" if i == 0 else &"HudSmall"))
	var note := _card_label("", &"HudSmall")
	note.name = "Note_%s" % id
	_set_note(note, _note_for(offer))
	texts.add_child(note)
	texts.move_child(note, NOTE_LINE)
	_note_labels[id] = note
	var fit := _card_label("", &"HudSmall")
	fit.name = "Fit_%s" % id
	_set_fit(fit, offer)
	texts.add_child(fit)
	_fit_labels[id] = fit
	var refusal := Label.new()
	refusal.name = "Refusal_%s" % id
	refusal.visible = false
	refusal.custom_minimum_size = Vector2(CARD_TEXT_W, 0.0)
	refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(refusal, &"HudProblemText")
	texts.add_child(refusal)
	_refusal_labels[id] = refusal
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


func _card_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(CARD_TEXT_W, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(label, variation)
	return label


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
		_refuse(
			id,
			(
				"Can't accept %s to %s: %s"
				% [offer["airline"], offer["destination"], _in_words(problem)]
			)
		)
		return
	var note := _note_for(offer)
	if desk.board.accept(id, flights):
		var then := ", %s" % note if note != "" else ""
		_say("Accepted %s to %s%s" % [offer["airline"], offer["destination"], then])


## FlightSim's refusal `problem` for the player: a clash names what it ran
## into by time, airline and destination, not by id. A clash in a shape
## FlightLabel cannot read is warned about and shown without ids. Any other
## refusal is shown as the sim wrote it.
func _in_words(problem: String) -> String:
	var ran_into := FlightLabel.clash_with(flights, problem)
	if ran_into != "":
		return "it clashes with %s" % ran_into
	if problem.begins_with("contract ") and problem.contains(" clashes with "):
		push_warning("OfferPanel: unreadable clash refusal from FlightSim: %s" % problem)
		return "it clashes with another flight"
	return problem


## What the sheet says when nothing was just done: EMPTY_TEXT with no open
## offer, else nothing. A closed sheet drops its last accept's confirmation.
func _say_idle() -> void:
	_say(EMPTY_TEXT if desk.board.open_offers().is_empty() else "")


## Shows `text` under the cards, hiding the line when it is empty.
func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


## Shows a refusal on the offer's own card, in place of any refusal on another.
func _refuse(id: String, text: String) -> void:
	_say("")
	_clear_refusals()
	var label: Label = _refusal_labels[id]
	label.text = text
	label.visible = true


## Empties every card's refusal line.
func _clear_refusals() -> void:
	for id: String in _refusal_labels:
		(_refusal_labels[id] as Label).text = ""
		(_refusal_labels[id] as Label).visible = false


func _on_decline(id: String) -> void:
	desk.board.decline(id)


func _style_label(label: Label, variation: StringName) -> void:
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
