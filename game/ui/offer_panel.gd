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
## Opening or closing the sheet leaves the sim clock alone (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete).
## It joins TopRow.SHEET_GROUP so opening another top-row sheet closes it, and
## it closes on Esc, when a build tool is picked, and when a save loads.
##
## A card says "first flight tomorrow" when the sim would not fly today's slot
## (FlightTimetable.first_day), once the airport is open. Whether it would
## depends on the taxi pair of the gate the offer gets (TaxiTimes: a longer
## TAXI_IN starts the flight earlier), so the note reads the pair of the gate
## the card's fit line found (FlightSim.gate_taxi), kept with the fit; an offer
## no gate takes now is noted at TaxiTimes.BASE, a first-site gate's times.
##
## Each card reads as a choice (decision airline-offers-stay-accept-many-the-
## three-offer-cards-read-a): one row under the title holds a fit line and the
## daily earnings ("$480 a day", passengers times the fee), so the three
## compare at a glance. The fit line (decision airline-offers-2-a-day-fit-
## the-free-gate-slots-1-needs-more, point 6) says "Fits your gates now" or
## "Needs another gate", and FlightFit's words for any other reason, in the
## good-text look when it fits and the problem look when not, at the small
## text size. It is advice, kept apart from
## the click refusal: it is worked out again when the sheet opens, when the
## cards rebuild (an accept, a decline, a new day, a load), when a contract
## ends, and on FlightSim.planning_changed (the gates, their stands, the runway
## or its works), which the open sheet checks for every frame because those
## change while the clock is paused under it.

signal opened

const SHEET_W := TopRow.SHEET_W
const CARD_TEXT_W := 380.0
## The widths the fit and earnings lines share on the row under the title: the
## fit line may wrap in the space left of the earnings, which stay on one line.
const VERDICT_FIT_W := 200.0
const VERDICT_EARNINGS_W := 150.0
## Index of the first-flight note line in a card's lines (under the departure).
const NOTE_LINE := 2
## Rail keys, and the history titles, of the two coral notices.
const WARNING_KEY := &"offer_warning"
const ENDED_KEY := &"offer_ended"
## The English msgids of the rail card titles, the empty message and the fit line
## when the offer fits the gates now, and when another gate would take it (any
## other blocker keeps FlightFit's own words). Tests compare with these; each is
## shown through tr() of the same literal, because the POT extractor reads only
## literals.
const WARNING_TITLE := "Low airport rating"
const ENDED_TITLE := "Contract ended"
const EMPTY_TEXT := "No offers right now. New offers arrive at midnight."
const FITS_TEXT := "Fits your gates now"
const NEEDS_GATE_TEXT := "Needs another gate"
const CHARTER_BADGE_TEXT := "One-off charter — flies today only"
const BADGE_META := &"badge_monogram"
const BADGE_BORDER := Color(0.1, 0.13, 0.26, 1.0)
const PEAK_CHIP_FILL := Color(0.98, 0.87, 0.56, 1.0)
const PEAK_CHIP_BORDER := Color(0.76, 0.54, 0.16, 1.0)
const HUB_CHIP_FILL := Color(0.98, 0.85, 0.36, 1.0)
const HUB_CHIP_BORDER := Color(0.74, 0.52, 0.08, 1.0)
const PULSE_TINT := Color(1.16, 1.06, 0.72, 0.76)
const PULSE_HALF_S := 0.7
const AIRLINE_BADGES := {
	"Gotta Air": {"code": "GA", "color": Color(0.96, 0.76, 0.28, 1.0)},
	"Nordic Wing": {"code": "NW", "color": Color(0.46, 0.74, 0.94, 1.0)},
	"Blue Fjord": {"code": "BF", "color": Color(0.36, 0.78, 0.74, 1.0)},
	"Sunhop": {"code": "SH", "color": Color(0.96, 0.60, 0.34, 1.0)},
	"Polar Jet": {"code": "PJ", "color": Color(0.62, 0.84, 0.92, 1.0)},
	"Aegean Sky": {"code": "AS", "color": Color(0.48, 0.68, 0.94, 1.0)},
	"Skyline Global": {"code": "SG", "color": Color(0.76, 0.62, 0.90, 1.0)},
	"Meridian Air": {"code": "MA", "color": Color(0.52, 0.82, 0.56, 1.0)},
}
const FALLBACK_BADGE_COLORS: Array[Color] = [
	Color(0.96, 0.76, 0.28, 1.0),
	Color(0.46, 0.74, 0.94, 1.0),
	Color(0.36, 0.78, 0.74, 1.0),
	Color(0.96, 0.60, 0.34, 1.0),
	Color(0.62, 0.84, 0.92, 1.0),
	Color(0.76, 0.62, 0.90, 1.0),
	Color(0.52, 0.82, 0.56, 1.0),
	Color(0.94, 0.64, 0.62, 1.0),
]

@export var desk: OfferDesk
@export var flights: FlightSim
## Kept for scene/test wiring compatibility; OfferPanel leaves the clock alone.
@export var clock: SimClock
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode
## A successful load replaces the world the sheet was opened over, so it closes.
@export var save_game: SaveGame
## The right rail the warning and ending notices go on; null finds the one in
## AlertStack.GROUP (the HUD builds it, so the scene does not wire it).
var alerts: AlertStack
var has_been_opened := false
var pulsing := false

var _button: Button
var _sheet: PanelContainer
var _scroll: ScrollContainer
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
var _offers_unseen := false
var _was_airport_open := false
var _known_offer_ids: Dictionary = {}
var _pulse_tween: Tween
var _card_nodes: Dictionary = {}
var _accept_buttons: Dictionary = {}
var _decline_buttons: Dictionary = {}
var _note_labels: Dictionary = {}
var _refusal_labels: Dictionary = {}
var _fit_labels: Dictionary = {}
## Offer id -> the taxi pair of the gate its last fit found, for its note.
var _fit_taxis: Dictionary = {}
var _earnings_labels: Dictionary = {}
var _trait_rows: Dictionary = {}
var _peak_chips: Dictionary = {}
var _noted_tick := -1


## The airlines' warning once the rating is low: `low_days` day ends have
## already been low, and contracts end at RatingFormula.LOW_DAYS_TO_END.
static func warning_message(low_days: int) -> String:
	var text := (
		TranslationServer
		. translate("Airlines are warning you: the airport rating is below {stars} stars.")
		. format({"stars": int(RatingFormula.WARN_BELOW)})
	)
	var left := RatingFormula.LOW_DAYS_TO_END - low_days
	if left > 0:
		text += (
			" "
			+ (
				TranslationServer
				. translate_plural(
					"Contracts end after {days} more low day.",
					"Contracts end after {days} more low days.",
					left
				)
				. format({"days": left})
			)
		)
	return text


## What the player is told when an airline leaves because the rating stayed low.
static func ended_message(airline: String, destination: String) -> String:
	var text := (
		TranslationServer
		. translate(
			"{airline} to {destination} has ended its contract: the airport rating stayed low."
		)
		. format({"airline": airline, "destination": destination})
	)
	return (
		text
		+ " "
		+ TranslationServer.translate("Flights already issued still fly; no new days will.")
	)


## Says when the first flight is if it is not today: "" when the sim would fly
## today's slot at a gate with taxi pair `taxi` (FlightTimetable.first_day is
## today), else "first flight tomorrow" or, past that, "first flight on Day N"
## (the HUD's day number).
static func first_flight_note(offer: Dictionary, now: int, taxi: Array, epoch: int) -> String:
	var timed := offer.duplicate()
	timed[FlightContract.TAXI_KEY] = taxi
	var first_day := FlightTimetable.first_day(timed, now, epoch)
	var ahead := first_day - GameCalendar.day_of(now, epoch)
	if ahead <= 0:
		return ""
	if ahead == 1:
		return TranslationServer.translate("first flight tomorrow")
	return TranslationServer.translate("first flight on Day {day}").format({"day": first_day + 1})


## Ticks a contract accepted while the airport is closed needs between the
## airport opening and its departure to fly the first day's slot: the issue
## lead before departure (FlightTimetable.issue_lead() and opening_day), the
## same at every gate.
static func opening_lead_ticks() -> int:
	return FlightTimetable.issue_lead()


## `ticks` as "2 h 50 min", "45 min" or "3 h", rounded up to a whole minute.
static func lead_text(ticks: int) -> String:
	var minutes := -GameCalendar.floor_div(-ticks, GameCalendar.TICKS_PER_MINUTE)
	var parts: PackedStringArray = []
	if minutes >= 60:
		parts.append(TranslationServer.translate("{hours} h").format({"hours": minutes / 60}))
	if minutes % 60 != 0:
		parts.append(TranslationServer.translate("{minutes} min").format({"minutes": minutes % 60}))
	return " ".join(parts)


## The text lines of an offer's card: who and where, when, the plane, and the
## money. `note` (first_flight_note) gets its own line under the departure when
## not empty, so no line wraps. A card without a note has 4 lines, with one 5.
static func card_lines(offer: Dictionary, note := "") -> PackedStringArray:
	var minute: int = offer["departure_minute"]
	# A daily minute as a time: the same at every epoch, so read at 0.
	var time := GameCalendar.clock_text(GameCalendar.tick_at(0, minute, 0), 0)
	var when_line := (
		TranslationServer.translate("Departs {time} today").format({"time": time})
		if FlightContract.is_charter(offer)
		else TranslationServer.translate("Departs {time} daily").format({"time": time})
	)
	var lines := PackedStringArray(
		[
			TranslationServer.translate("{airline} to {destination}").format(
				{"airline": offer["airline"], "destination": offer["destination"]}
			),
			when_line,
			_plane_line(offer["plane_size"]),
			(
				TranslationServer
				. translate_plural(
					"{count} passenger booked   ${fee} per passenger",
					"{count} passengers booked   ${fee} per passenger",
					offer["booked_passengers"]
				)
				. format({"count": offer["booked_passengers"], "fee": offer["fee_per_passenger"]})
			),
		]
	)
	if note != "":
		lines.insert(NOTE_LINE, note_line(note))
	return lines


## Peak-wave chip label for `departure_minute`, or "" for off-peak / Odd hours.
static func _peak_chip_text(departure_minute: int) -> String:
	var wave := OfferBoard.peak_wave(departure_minute)
	if wave == OfferBoard.PEAK_WAVE_MORNING:
		return TranslationServer.translate("Morning Peak +15%")
	if wave == OfferBoard.PEAK_WAVE_EVENING:
		return TranslationServer.translate("Evening Peak +15%")
	return ""


## "Small plane", "Medium plane" or "Large plane" for a plane size.
static func _plane_line(size: String) -> String:
	match size:
		PlaneClasses.SMALL:
			return TranslationServer.translate("Small plane")
		PlaneClasses.MEDIUM:
			return TranslationServer.translate("Medium plane")
		PlaneClasses.LARGE:
			return TranslationServer.translate("Large plane")
	push_error("OfferPanel._plane_line: unknown plane size '%s'" % size)
	return ""


## What an offer pays each day it flies: booked passengers times the fee.
static func daily_earnings(offer: Dictionary) -> int:
	return int(offer["booked_passengers"]) * int(offer["fee_per_passenger"])


## The earnings line on a card, the figure the offers are compared by.
static func earnings_text(offer: Dictionary) -> String:
	if FlightContract.is_charter(offer):
		return TranslationServer.translate("${amount} payout").format(
			{"amount": daily_earnings(offer)}
		)
	return TranslationServer.translate("${amount} a day").format({"amount": daily_earnings(offer)})


## The card's fit line for `assessment` of an offer with `plane_size`: the short
## fits / needs-another-gate words, else FlightFit's reason.
static func fit_line(assessment: Dictionary, plane_size: String) -> String:
	if assessment["fits"]:
		return TranslationServer.translate("Fits your gates now")
	if assessment["blocker"] == FlightSim.BLOCKER_GATE and assessment["another_gate_helps"]:
		return TranslationServer.translate("Needs another gate")
	return FlightFit.text(assessment, plane_size)


## A first-flight note as it reads on a line of its own.
static func note_line(note: String) -> String:
	return note.left(1).to_upper() + note.substr(1)


## Crisp 2-letter airline monogram for the offer card badge.
static func airline_code(airline: String) -> String:
	if AIRLINE_BADGES.has(airline):
		return String(AIRLINE_BADGES[airline]["code"])
	var words: Array[String] = []
	for part in airline.strip_edges().split(" ", false):
		words.append(part)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	if words.size() == 1:
		return words[0].left(2).to_upper()
	return "??"


## Deterministic Toon palette swatch color for `airline`.
static func airline_color(airline: String) -> Color:
	if AIRLINE_BADGES.has(airline):
		return AIRLINE_BADGES[airline]["color"]
	var index := posmod(airline.hash(), FALLBACK_BADGE_COLORS.size())
	return FALLBACK_BADGE_COLORS[index]


## One-line cozy flavor pitch tailored to charter status, traits or destination.
static func route_pitch(offer: Dictionary) -> String:
	var airline := String(offer.get("airline", ""))
	var destination := String(offer.get("destination", ""))
	var template := ""
	if FlightContract.is_charter(offer):
		template = TranslationServer.translate(
			"Last-minute charter hop to {destination} — light bags, quick turnaround."
		)
	else:
		var traits: Dictionary = offer.get(FlightContract.TRAITS_KEY, {})
		match String(traits.get("up", "")):
			OfferTraits.TOP_FARE:
				template = TranslationServer.translate(
					"Premium cabin demand to {destination} — passengers pay top fare."
				)
			OfferTraits.SHOPPERS:
				template = TranslationServer.translate(
					"Holiday crowd bound for {destination} — plenty of time to shop."
				)
			OfferTraits.BAG_COVER:
				template = TranslationServer.translate(
					"Smooth bag handling to {destination} — {airline} covers missed bags."
				)
			OfferTraits.FULL_FLIGHT:
				template = TranslationServer.translate(
					"Busy route to {destination} — almost every seat is spoken for."
				)
			OfferTraits.SIGNING_BONUS:
				template = TranslationServer.translate(
					"{airline} brings a welcome bonus on your first flight to {destination}."
				)
			OfferTraits.LOYAL_AIRLINE:
				template = TranslationServer.translate(
					"Steady partner route to {destination} — fly often for higher fares."
				)
			_:
				template = _destination_pitch(destination)
	return template.format({"airline": airline, "destination": destination})


static func _destination_pitch(destination: String) -> String:
	var text := ""
	match destination:
		"Oslo":
			text = TranslationServer.translate(
				"Crisp northern hop with {airline} — steady fjord and business flyers."
			)
		"Berlin":
			text = TranslationServer.translate(
				"Quick city-break run to Berlin — easygoing weekend flyers."
			)
		"Lisbon":
			text = TranslationServer.translate(
				"Warm coastal route to Lisbon — sunlit travelers heading south."
			)
		"Rome":
			text = TranslationServer.translate(
				"Classic Mediterranean hop to Rome — sightseeing crowds all day."
			)
		"Dublin":
			text = TranslationServer.translate(
				"Friendly island link to Dublin — reliable regional commuters."
			)
		"Athens":
			text = TranslationServer.translate(
				"Sunny Aegean flight to Athens — leisure flyers ready to board."
			)
		_:
			text = TranslationServer.translate(
				"Reliable daily link to {destination} with {airline}."
			)
	return text


func _ready() -> void:
	if desk == null or flights == null:
		push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = TopRow.SHEET_LAYER
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	get_viewport().size_changed.connect(_place_row)
	desk.board.changed.connect(_refresh)
	if desk.rating != null:
		desk.rating.changed.connect(_refresh_warning)
	desk.contract_ended.connect(_on_contract_ended)
	flights.planning_changed.connect(_refresh_fits)
	flights.snapshot_loaded.connect(_on_snapshot_loaded)
	flights.occurrence_added.connect(_on_flights_changed)
	var gate := get_node_or_null("../AirportGate") as AirportGate
	if gate != null:
		gate.opened.connect(_on_airport_opened)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	_was_airport_open = flights.opened_tick >= 0
	_known_offer_ids = _open_offer_id_set()
	_refresh()
	_refresh_warning()
	_sync_open_state()


func _exit_tree() -> void:
	_stop_pulse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	if _sheet != null:
		var title := _sheet.find_child("OfferTitle", true, false) as Label
		if title != null:
			title.text = tr("Airline Contracts — Accept to schedule flights")
	if desk != null and flights != null:
		_refresh()
		_refresh_warning()


func _process(_delta: float) -> void:
	if flights != null and _button != null:
		var open_now := flights.opened_tick >= 0
		if _button.visible != open_now:
			_sync_open_state()
	if not _sheet.visible:
		return
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


## Shows the sheet without touching the sim clock. Hidden/refused until the
## airport opens.
func open() -> void:
	_sync_open_state()
	if flights == null or flights.opened_tick < 0 or _sheet.visible:
		return
	TopRow.close_others(self)
	_offers_unseen = false
	has_been_opened = true
	_stop_pulse()
	_sheet.visible = true
	_refresh_notes()
	flights.check_planning_changed()
	_refresh_fits()
	TopRow.place_sheet(_sheet, self)
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()
	opened.emit()
	var rail := _rail()
	if rail != null:
		rail.refresh()


## Hides the sheet and clears transient refusals.
func close() -> void:
	if not _sheet.visible:
		return
	_sheet.visible = false
	_clear_refusals()
	_say_idle()


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
		var lbl := label as Label
		if lbl.visible and not lbl.has_meta(BADGE_META):
			lines.append(lbl.text)
	return "\n".join(lines)


func has_unseen_offers() -> bool:
	return _offers_unseen


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


## The fit line on offer `id`'s card (fit_line): advice that Accept checks
## again at the click.
func fit_text(id: String) -> String:
	return (_fit_labels[id] as Label).text


func fit_label(id: String) -> Label:
	return _fit_labels[id]


## The daily earnings line on offer `id`'s card.
func earnings_text_of(id: String) -> String:
	return (_earnings_labels[id] as Label).text


func earnings_label(id: String) -> Label:
	return _earnings_labels[id]


## The trait line on offer `id`'s card: an HBoxContainer of the Up and Down labels.
func trait_row(id: String) -> HBoxContainer:
	return _trait_rows[id]


## What the sheet says under the cards: the last accept's confirmation, or
## EMPTY_TEXT when no offer is open. A refusal is on its card, not here.
func message() -> String:
	return _message.text


## Puts the button and the sheet back on the row for the viewport's layout width.
func _place_row() -> void:
	TopRow.place_in_slot(_button, TopRow.OFFERS_SLOT, self)
	TopRow.place_sheet(_sheet, self)
	_fit_scroll_height()


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_scroll = ScrollContainer.new()
	_cards = VBoxContainer.new()
	_message = Label.new()
	_button.name = "OffersButton"
	_button.theme = BuildMenu.HUD_THEME
	TopRow.place_in_slot(_button, TopRow.OFFERS_SLOT, self)
	_button.focus_mode = Control.FOCUS_NONE
	_button.theme_type_variation = &"HudButtonTeal"
	_button.pressed.connect(_on_toggle)
	add_child(_button)
	_sheet.name = "OfferSheet"
	_sheet.theme = BuildMenu.HUD_THEME
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	TopRow.place_sheet(_sheet, self)
	add_child(_sheet)
	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 6)
	_sheet.add_child(sheet_column)
	var title := Label.new()
	title.name = "OfferTitle"
	title.text = tr("Airline Contracts — Accept to schedule flights")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(title, &"HudTitle")
	sheet_column.add_child(title)
	_scroll.name = "OfferCardsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_column.add_child(_scroll)
	_cards.name = "OfferCards"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 6)
	_cards.sort_children.connect(_fit_scroll_height)
	_scroll.add_child(_cards)
	_message.name = "OfferMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(_message, &"HudSmall")
	sheet_column.add_child(_message)


func _fit_scroll_height() -> void:
	if _sheet == null or _scroll == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_h := viewport.get_visible_rect().size.y
	if viewport_h <= 0.0:
		return
	var content_h := _cards.get_combined_minimum_size().y
	var chrome := _sheet.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var bottom_clear := float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	var max_scroll_h := maxf(0.0, viewport_h - TopRow.SHEET_TOP - bottom_clear - chrome)
	var wanted := minf(content_h, max_scroll_h)
	var extent := TopRow.sheet_extent(
		viewport.get_visible_rect().size.x, TopRow.sheet_min_left(get_tree())
	)
	var size_changed := (
		not is_equal_approx(_scroll.custom_minimum_size.y, wanted)
		or not is_equal_approx(_sheet.custom_minimum_size.x, extent.y)
		or not is_equal_approx(_sheet.offset_left, extent.x)
	)
	if size_changed:
		_scroll.custom_minimum_size.y = wanted
		TopRow.place_sheet(_sheet, self)
		_sheet.custom_minimum_size.x = extent.y
		_sheet.reset_size()


func _on_toggle() -> void:
	if _sheet.visible:
		close()
	else:
		open()


## A load replaces the world the sheet was opened over, so it closes.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	close()
	_on_snapshot_loaded()
	# The ending notice is not saved. The rail's own reset (reset_done) posts a
	# warning still due once, whichever of the two handlers runs first, so this
	# only drops the ending and lets the warning follow the loaded rating.
	var rail := _rail()
	if rail != null:
		rail.drop_notice(ENDED_KEY)
	_ended_text = ""
	_refresh_warning.call_deferred()


func _on_snapshot_loaded() -> void:
	_offers_unseen = false
	_stop_pulse()
	_was_airport_open = flights != null and flights.opened_tick >= 0
	_known_offer_ids = _open_offer_id_set()
	_sync_open_state()


func _sync_open_state() -> void:
	var open_now := flights != null and flights.opened_tick >= 0
	var became_open := open_now and not _was_airport_open
	_was_airport_open = open_now
	if _button != null:
		_button.visible = open_now
		_button.disabled = not open_now
	if not open_now:
		_offers_unseen = false
		_stop_pulse()
		if _sheet != null:
			close()
	elif (
		became_open
		and desk != null
		and not desk.board.is_loading()
		and not desk.board.open_offers().is_empty()
		and (_sheet == null or not _sheet.visible)
	):
		_known_offer_ids = _open_offer_id_set()
		_notify_fresh_offers()


func _on_airport_opened(_tick: int) -> void:
	_sync_open_state()
	_refresh()


func _on_flights_changed(_id: String) -> void:
	_sync_open_state()


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
	_fit_taxis.clear()
	_earnings_labels.clear()
	_trait_rows.clear()
	_peak_chips.clear()
	var charters := desk.board.open_charters()
	var offers := desk.board.open_offers()
	for charter in charters:
		_add_card(charter)
	for offer in offers:
		_add_card(offer)
	var total := charters.size() + offers.size()
	_button.text = tr("Offers ({count})").format({"count": total})
	_offers_waiting = total > 0
	_style_button()
	_say_idle()
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()
	_noted_tick = flights.tick
	_sync_fresh_offer_cue(offers)


func _open_offer_id_set() -> Dictionary:
	var ids := {}
	if desk == null or desk.board == null:
		return ids
	for offer in desk.board.open_offers():
		ids[String(offer["id"])] = true
	return ids


func _sync_fresh_offer_cue(offers: Array[Dictionary]) -> void:
	var current_ids := {}
	var has_new := false
	for offer in offers:
		var id := String(offer["id"])
		current_ids[id] = true
		if not _known_offer_ids.has(id):
			has_new = true
	_known_offer_ids = current_ids
	if desk.board.is_loading() or flights == null or flights.opened_tick < 0:
		return
	if current_ids.is_empty():
		_offers_unseen = false
		_stop_pulse()
	elif has_new and (_sheet == null or not _sheet.visible):
		_notify_fresh_offers()


func _notify_fresh_offers() -> void:
	_offers_unseen = true
	_start_pulse()
	_play_offer_chime()


func _start_pulse() -> void:
	if _button == null or not is_inside_tree():
		return
	pulsing = true
	if _pulse_tween != null and _pulse_tween.is_valid():
		return
	_button.modulate = Color.WHITE
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	(
		_pulse_tween
		. tween_property(_button, "modulate", PULSE_TINT, PULSE_HALF_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_pulse_tween
		. tween_property(_button, "modulate", Color.WHITE, PULSE_HALF_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _stop_pulse() -> void:
	pulsing = false
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if _button != null:
		_button.modulate = Color.WHITE


func _play_offer_chime() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("GameAudio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"offer_chime")


## The first-flight note for an offer card right now. While the airport is
## closed a contract accepted starts at the opening, which is not known yet, so
## the note names the lead its slot needs after the opening.
func _note_for(offer: Dictionary) -> String:
	if FlightContract.is_charter(offer):
		return ""
	if flights.opened_tick < 0:
		return tr("first flight {lead} after opening").format(
			{"lead": lead_text(opening_lead_ticks())}
		)
	var taxi: Array = _fit_taxis.get(offer["id"], TaxiTimes.BASE)
	return first_flight_note(offer, flights.tick, taxi, flights.epoch)


## Rewrites each card's note line for the sim's current tick, hiding it while
## there is no note.
func _refresh_notes() -> void:
	_noted_tick = flights.tick
	for id in _note_labels:
		_set_note(_note_labels[id], _note_for(desk.board.any_offer_of(id)))


func _set_note(label: Label, note: String) -> void:
	label.text = note_line(note)
	label.visible = note != ""


## Rewrites each card's fit line for the sim as it is now.
func _refresh_fits() -> void:
	_sync_open_state()
	for id: String in _fit_labels:
		_set_fit(_fit_labels[id], desk.board.any_offer_of(id))


func _set_fit(label: Label, offer: Dictionary) -> void:
	var assessment := FlightFit.assess(flights, OfferBoard.terms_of(offer))
	var stand_key := String(assessment.get("stand", assessment["gate"]))
	var taxi: Array = flights.gate_taxi(stand_key) if assessment["fits"] else []
	_fit_taxis[offer["id"]] = taxi if not taxi.is_empty() else TaxiTimes.BASE
	if _note_labels.has(offer["id"]):
		_set_note(_note_labels[offer["id"]], _note_for(offer))
	label.text = fit_line(assessment, offer["plane_size"])
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
			_post(rail, WARNING_KEY, tr("Low airport rating"), _warning_text)
	_style_button()


func _on_contract_ended(contract: Dictionary) -> void:
	_ended_text = ended_message(contract["airline"], contract["destination"])
	var rail := _rail()
	if rail == null:
		push_warning("OfferPanel: no alert rail to tell the player: %s" % _ended_text)
	else:
		_post(rail, ENDED_KEY, tr("Contract ended"), _ended_text)
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
	return _rail_card(&"HudCardCoral", key, title, detail)


## The same card in the theme's HudCardGreen look, the flight result card's
## (green means good news, decision 0b50e074).
static func green_card(key: StringName, title: String, detail: String) -> PanelContainer:
	return _rail_card(&"HudCardGreen", key, title, detail)


static func _rail_card(
	variation: StringName, key: StringName, title: String, detail: String
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "OfferNotice_%s" % key
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = variation
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
	var is_charter := FlightContract.is_charter(offer)
	if is_charter:
		var badge := _card_label(tr("One-off charter — flies today only"), &"HudGoodText")
		badge.name = "CharterBadge_%s" % id
		badge.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		texts.add_child(badge)
	var lines := card_lines(offer)
	var header := HBoxContainer.new()
	header.name = "Header_%s" % id
	header.add_theme_constant_override("separation", 8)
	texts.add_child(header)
	header.add_child(_airline_badge(offer))
	var title_label := _card_label(lines[0], &"HudTitle")
	title_label.custom_minimum_size = Vector2(CARD_TEXT_W - 44.0, 0.0)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	# The departure and the plane share one row, so the trait line below the
	# verdict row costs the sheet no height (it stays inside 720 px at 1.5).
	var when := HBoxContainer.new()
	when.name = "When_%s" % id
	texts.add_child(when)
	for i in [1, 2]:
		var part := _card_label(lines[i], &"HudSmall")
		part.custom_minimum_size.x = VERDICT_FIT_W if i == 1 else 0.0
		part.autowrap_mode = TextServer.AUTOWRAP_OFF
		when.add_child(part)
	for i in range(3, lines.size()):
		texts.add_child(_card_label(lines[i], &"HudSmall"))
	var is_hub := not is_charter and bool(offer.get(OfferBoard.HUB_KEY, false))
	var is_peak := not is_charter and OfferBoard.is_peak_minute(int(offer["departure_minute"]))
	if is_hub or is_peak:
		var chips := HBoxContainer.new()
		chips.name = "Chips_%s" % id
		chips.add_theme_constant_override("separation", 6)
		if is_hub:
			chips.add_child(_hub_badge(offer))
		if is_peak:
			var chip := _peak_chip(offer)
			chips.add_child(chip)
			_peak_chips[id] = chip
		texts.add_child(chips)
	var pitch := _card_label(route_pitch(offer), &"HudHint")
	pitch.name = "Pitch_%s" % id
	texts.add_child(pitch)
	var note := _card_label("", &"HudSmall")
	note.name = "Note_%s" % id
	_set_note(note, _note_for(offer))
	texts.add_child(note)
	var note_index := NOTE_LINE + 1 if is_charter else NOTE_LINE
	texts.move_child(note, note_index)
	_note_labels[id] = note
	# The verdict and the daily earnings share one row straight under the title,
	# so the cards compare by reading down it without making the sheet taller.
	var verdict := HBoxContainer.new()
	verdict.name = "Verdict_%s" % id
	texts.add_child(verdict)
	texts.move_child(verdict, 2 if is_charter else 1)
	var fit := _card_label("", &"HudSmall")
	fit.name = "Fit_%s" % id
	fit.custom_minimum_size.x = VERDICT_FIT_W
	fit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_fit(fit, offer)
	verdict.add_child(fit)
	_fit_labels[id] = fit
	var earnings := _card_label(earnings_text(offer), &"HudSmall")
	earnings.name = "Earnings_%s" % id
	earnings.custom_minimum_size.x = VERDICT_EARNINGS_W
	earnings.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	verdict.add_child(earnings)
	_earnings_labels[id] = earnings
	var traits := _trait_row(offer)
	texts.add_child(traits)
	texts.move_child(traits, verdict.get_index() + 1)
	_trait_rows[id] = traits
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
	var accept := _card_button(tr("Accept", "button: accept an offer"), &"HudButtonGreen", id)
	accept.pressed.connect(_on_accept.bind(id))
	buttons.add_child(accept)
	_accept_buttons[id] = accept
	var decline := _card_button(tr("Decline", "button: decline an offer"), &"HudButtonCoral", id)
	decline.pressed.connect(_on_decline.bind(id))
	buttons.add_child(decline)
	_decline_buttons[id] = decline


## The trait line under the verdict row (OfferTraits.card_labels): the upside in
## HudGoodText and the downside in HudProblemText, each with its numbers as a
## tooltip; a plain offer shows PLAIN_LABEL in HudHint and no downside. An offer
## from a Bronze/Silver/Gold airline ends the line with its tier badge in HudGoodText.
func _trait_row(offer: Dictionary) -> HBoxContainer:
	if FlightContract.is_charter(offer):
		var charter_row := HBoxContainer.new()
		charter_row.name = "Traits_%s" % offer["id"]
		var badge := Label.new()
		badge.name = "CharterTerms"
		badge.text = tr("No exit fee")
		badge.tooltip_text = tr("Flies once today only; no exit fee or daily commitment.")
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		badge.theme_type_variation = &"HudGoodText"
		badge.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		charter_row.add_child(badge)
		return charter_row
	var traits: Dictionary = offer[FlightContract.TRAITS_KEY]
	var plain := OfferTraits.is_plain(traits)
	var tier := int(
		offer.get(OfferBoard.LOYAL_TIER_KEY, 1 if offer.get(OfferBoard.LOYAL_KEY, false) else 0)
	)
	var loyal_text := ""
	var loyal_tip := ""
	match tier:
		OfferBoard.LOYALTY_TIER_BRONZE:
			loyal_text = tr("Bronze +5%")
			loyal_tip = tr("Bronze loyalty: this airline's offers pay 5% more.")
		OfferBoard.LOYALTY_TIER_SILVER:
			loyal_text = tr("Silver +10%")
			loyal_tip = tr("Silver loyalty: this airline's offers pay 10% more.")
		OfferBoard.LOYALTY_TIER_GOLD:
			loyal_text = tr("Gold +15%")
			loyal_tip = tr(
				# gdlint:ignore = max-line-length
				"Gold loyalty: this airline's offers pay 15% more and unlock Hub Contracts at 3★+."
			)
	var labels := Array(OfferTraits.card_labels(traits)) + [loyal_text]
	var tips := Array(OfferTraits.card_tips(traits)) + [loyal_tip]
	var shown: Array[bool] = [true, labels[1] != "", tier > OfferBoard.LOYALTY_TIER_NONE]
	var row := HBoxContainer.new()
	row.name = "Traits_%s" % offer["id"]
	row.add_theme_constant_override("separation", 18)
	var variations: Array[StringName] = [
		&"HudHint" if plain else &"HudGoodText", &"HudProblemText", &"HudGoodText"
	]
	for i in 3:
		var label := Label.new()
		label.name = ["Up", "Down", "Loyal"][i]
		label.text = labels[i]
		label.tooltip_text = tips[i]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.visible = shown[i]
		label.theme_type_variation = variations[i]
		label.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		row.add_child(label)
	return row


func _airline_badge(offer: Dictionary) -> PanelContainer:
	var airline := String(offer.get("airline", ""))
	var badge := PanelContainer.new()
	badge.name = "AirlineBadge_%s" % offer["id"]
	badge.custom_minimum_size = Vector2(36.0, 26.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = airline_color(airline)
	style.border_color = BADGE_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("panel", style)
	var code := Label.new()
	code.name = "Monogram"
	code.text = airline_code(airline)
	code.set_meta(BADGE_META, true)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(code, &"HudCardName")
	badge.add_child(code)
	return badge


func _hub_badge(offer: Dictionary) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "HubBadge_%s" % offer["id"]
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	badge.tooltip_text = tr(
		"Gold Hub Contract: +10% prestige fee bonus and +1 low-rating grace day."
	)
	var style := StyleBoxFlat.new()
	style.bg_color = HUB_CHIP_FILL
	style.border_color = HUB_CHIP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "HubLabel"
	label.text = tr("Hub Contract")
	label.theme_type_variation = &"HudSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BADGE_BORDER)
	badge.add_child(label)
	return badge


func _peak_chip(offer: Dictionary) -> PanelContainer:
	var minute := int(offer["departure_minute"])
	var chip := PanelContainer.new()
	chip.name = "PeakChip_%s" % offer["id"]
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = tr("Peak rush wave: +15% passenger fee included.")
	var style := StyleBoxFlat.new()
	style.bg_color = PEAK_CHIP_FILL
	style.border_color = PEAK_CHIP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "PeakLabel"
	label.text = _peak_chip_text(minute)
	label.theme_type_variation = &"HudSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BADGE_BORDER)
	chip.add_child(label)
	return chip


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
	var offer := desk.board.any_offer_of(id)
	var problem := flights.accept_problem(OfferBoard.terms_of(offer))
	if problem != "":
		_refuse(
			id,
			tr("Can't accept {airline} to {destination}: {reason}").format(
				{
					"airline": offer["airline"],
					"destination": offer["destination"],
					"reason": _in_words(problem)
				}
			)
		)
		return
	var note := _note_for(offer)
	if desk.board.accept(id, flights):
		var named := {"airline": offer["airline"], "destination": offer["destination"]}
		if note == "":
			_say(tr("Accepted {airline} to {destination}").format(named))
		else:
			named["note"] = note
			_say(tr("Accepted {airline} to {destination}, {note}").format(named))


## FlightSim's refusal `problem` for the player: a clash names what it ran
## into by time, airline and destination, not by id. A clash in a shape
## FlightLabel cannot read is warned about and shown without ids. Any other
## refusal is shown as the sim wrote it.
func _in_words(problem: String) -> String:
	var clash := FlightLabel.clash_sentence(flights, problem)
	if clash != "":
		return clash
	if problem.begins_with("contract ") and problem.contains(" clashes with "):
		push_warning("OfferPanel: unreadable clash refusal from FlightSim: %s" % problem)
		return tr("it clashes with another flight")
	return problem


## What the sheet says when nothing was just done: EMPTY_TEXT with no open
## offer, else nothing. A closed sheet drops its last accept's confirmation.
func _say_idle() -> void:
	_say(
		(
			tr("No offers right now. New offers arrive at midnight.")
			if desk.board.open_offers().is_empty() and desk.board.open_charters().is_empty()
			else ""
		)
	)


## Shows `text` under the cards, hiding the line when it is empty.
func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""
	_fit_scroll_height()


## Shows a refusal on the offer's own card, in place of any refusal on another.
func _refuse(id: String, text: String) -> void:
	_say("")
	_clear_refusals()
	var label: Label = _refusal_labels[id]
	label.text = text
	label.visible = true
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()


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
